// OLIVE BRANCH — GET /media/:key?exp=...&sig=... — the real signed-URL-
// serving route `StoragePort.signedUrl()`/`verifySignedKey()` have always
// been able to mint and verify, with nothing in this codebase ever serving
// the result (`server/routes.mjs`'s own comment on
// `GET .../messages/:artifactId/media` named this as real, separate
// follow-up work).
//
// A side-effect-free module, deliberately, NOT folded into server/index.mjs
// directly: that file has real, unconditional module-level side effects (a
// real Postgres Pool, `server.listen()`, no `isMain` guard — it was written
// to be run, `node server/index.mjs`, never imported) that would fire the
// moment anything imported it just to reach this one function, including a
// test. This mirrors why routes.mjs is its own side-effect-free module too.
//
// Called directly from the raw HTTP handler in index.mjs, not registered
// via `api.register()`, for the same structural reason dev-login/webauthn-
// login in that file aren't: it authenticates via the signature+expiry
// ALONE, with no session/Authorization header at all — `api.ts`'s whole
// dispatch is built around a verified session already existing, which this
// deliberately has none of.
//
// The key's own namespacing (`children/<childId>/messages/<uuid>`,
// `routes.mjs`'s real convention for every key `POST .../media` ever
// mints) is already covered by the signature itself — `signKey()` signs the
// full key string, so a signature minted for one key cannot be replayed
// against a different one. No separate childId check on top of that is
// needed — see `storage.ts`'s own `StoragePort.verifySignedKey()` doc
// comment for the full reasoning.
//
// Content-Type is honestly generic (`application/octet-stream`) — nothing
// in this storage system tracks a real MIME type per blob
// (`media_artifact.kind` is a category like `'video_msg'`, not a MIME type,
// and this route deliberately never queries the database at all — the
// whole point of a signed URL is that it needs no session/RLS-scoped
// lookup to serve). A real per-blob Content-Type would need that field
// added somewhere in the upload pipeline; not invented here.
export async function serveSignedMedia(reqUrl, res, storage) {
  const json = (status, body) => {
    res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(body));
  };
  let parsed;
  try {
    parsed = new URL(reqUrl, 'http://internal');
  } catch {
    return json(400, { error: 'bad_signed_url' });
  }
  const key = decodeURIComponent(parsed.pathname.replace(/^\/media\//, ''));
  // A MISSING exp param must be caught explicitly, before Number() ever
  // sees it: Number(null) coerces to 0, not NaN, so a bare
  // !Number.isFinite(exp) check alone silently admits a request with no
  // exp at all (found and fixed by this route's own first test,
  // server/test/signed_media_route.test.mjs's "D malformed" group).
  const rawExp = parsed.searchParams.get('exp');
  const exp = rawExp === null ? NaN : Number(rawExp);
  const sig = parsed.searchParams.get('sig');
  if (!key || !Number.isFinite(exp) || !sig) {
    return json(400, { error: 'bad_signed_url' });
  }
  const verified = storage.verifySignedKey(key, exp, sig, Date.now());
  if (!verified.ok) {
    return json(403, { error: verified.reason });
  }
  const bytes = await storage.get(key);
  if (!bytes) {
    return json(404, { error: 'media_not_found' });
  }
  res.writeHead(200, {
    'content-type': 'application/octet-stream',
    // Private and short — matches SIGNED_URL_TTL_SECONDS (5 minutes); a
    // shared/public cache holding a child's media past the URL's own real
    // expiry would defeat the entire point of a short-TTL signed URL.
    'cache-control': 'private, max-age=300',
    'x-content-type-options': 'nosniff',
  });
  res.end(bytes);
}
