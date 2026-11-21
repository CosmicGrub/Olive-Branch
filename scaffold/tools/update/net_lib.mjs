/**
 * OLIVE BRANCH - the careful download the verifier (and the tests of the app's rules) use. Node's http and https modules,
 * redirects followed by hand so each hop is judged before it is taken:
 *   - every hop must pass redirectProblem(): https only (cleartext only to a literal loopback address and only when the
 *     developer option is on), no credentials, no non-default port, and the target host must be one the publisher trusts;
 *   - at most five hops, so a loop ends;
 *   - a hard cap on the bytes accepted: the connection is torn down the moment the cap is passed, so a hostile or broken server
 *     cannot fill the disk or memory by never stopping (a "zip bomb" over the wire);
 *   - a response that ends before its declared length is `truncated`, never accepted as "a short file".
 * The integrity of what arrives never depends on this file: the size, chunk hashes and SHA-256 are checked afterwards against
 * the signed manifest. This only keeps the transfer itself polite and honest.
 */
import http from 'node:http';
import https from 'node:https';
import { createWriteStream, rmSync } from 'node:fs';
import { Refusal, redirectProblem } from './manifest_lib.mjs';

const MAX_REDIRECTS = 5;

function open(urlStr, timeoutMs) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlStr);
    const lib = u.protocol === 'https:' ? https : http;
    const req = lib.request(u, { method: 'GET', headers: { 'user-agent': 'olive-update-verifier', accept: '*/*', 'accept-encoding': 'identity' }, timeout: timeoutMs }, resolve);
    req.on('timeout', () => req.destroy(new Refusal('offline', 'timed out')));
    req.on('error', (e) => reject(e instanceof Refusal ? e : new Refusal('offline', e.code || e.message)));
    req.end();
  });
}

/**
 * Downloads [url] (following judged redirects) into either memory ({ to: 'memory' }) or a file ({ to: 'file', path }).
 * Throws Refusal(code): badRedirect, httpError, tooMuchData, truncated, offline.
 * @returns {Promise<{ bytes?:Buffer, path?:string, length:number, finalUrl:string, hops:string[] }>}
 */
export async function download(url, { maxBytes, to = 'memory', path = null, allowLoopbackHttp = false, allowedHosts = [], timeoutMs = 30000 }) {
  let cur = url;
  const hops = [];
  for (let n = 0; n <= MAX_REDIRECTS; n++) {
    const res = await open(cur, timeoutMs);
    const status = res.statusCode ?? 0;
    if (status >= 300 && status < 400 && res.headers.location) {
      res.resume();
      let next;
      try { next = new URL(res.headers.location, cur).href; } catch { throw new Refusal('badRedirect', 'unreadable Location'); }
      const why = redirectProblem(next, { allowLoopbackHttp, allowedHosts });
      if (why) throw new Refusal('badRedirect', why);
      hops.push(next);
      cur = next;
      continue;
    }
    if (status !== 200) { res.resume(); throw new Refusal('httpError', `status ${status}`); }
    const declared = res.headers['content-length'] === undefined ? null : Number(res.headers['content-length']);
    if (declared !== null && declared > maxBytes) { res.destroy(); throw new Refusal('tooMuchData', `declares ${declared} bytes, more than the ${maxBytes} allowed`); }
    const chunks = [];
    const sink = to === 'file' ? createWriteStream(path) : null;
    let length = 0;
    try {
      await new Promise((resolve, reject) => {
        res.on('data', (b) => {
          length += b.length;
          if (length > maxBytes) { res.destroy(); reject(new Refusal('tooMuchData', `more than ${maxBytes} bytes arrived`)); return; }
          if (sink) sink.write(b); else chunks.push(b);
        });
        res.on('end', () => (res.complete ? resolve() : reject(new Refusal('truncated', 'the connection ended early'))));
        res.on('aborted', () => reject(new Refusal('truncated', 'the connection was cut')));
        res.on('error', (e) => reject(e instanceof Refusal ? e : new Refusal('truncated', e.code || e.message)));
        res.on('close', () => { if (!res.complete) reject(new Refusal('truncated', 'the connection closed early')); });
      });
      if (declared !== null && length !== declared) throw new Refusal('truncated', `${length} bytes arrived of ${declared} declared`);
    } catch (e) {
      if (sink) { sink.destroy(); try { rmSync(path, { force: true }); } catch { /* best effort */ } }
      throw e;
    }
    if (sink) await new Promise((resolve) => sink.end(resolve));
    return { bytes: sink ? undefined : Buffer.concat(chunks), path: sink ? path : undefined, length, finalUrl: cur, hops };
  }
  throw new Refusal('badRedirect', `more than ${MAX_REDIRECTS} redirects`);
}
