/**
 * Demo drive test.
 *
 * The demo is only useful if it cannot break under exploration, and that is a
 * claim until every screen is rendered and every control clicked. This walks
 * the guided tour end to end, visits all 19 screens in explore mode, clicks
 * every interactive control on every screen, and fails on any error card or
 * uncaught exception.
 */
import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';

/**
 * The colouring book's tappable regions are SVG <path> elements, and SVGElement
 * in jsdom has no .click(). The shell uses delegated listeners on document, so a
 * bubbling synthetic event reaches them either way — but the harness had assumed
 * every control was HTML.
 */
function clickEl(el) {
  if (!el) return;
  if (typeof el.click === 'function') return el.click();
  const W = el.ownerDocument.defaultView;
  el.dispatchEvent(new W.MouseEvent('click', { bubbles: true, cancelable: true }));
}


const html = readFileSync(new URL('../../../DEMO.html', import.meta.url).pathname, 'utf8');

let pass = 0, fail = 0; const rows = [];
const check = (n, fn) => {
  try { fn(); pass++; rows.push([n, true]); }
  catch (e) { fail++; rows.push([n, false, e.message]); }
};

/**
 * The target device is a Galaxy Z Fold 5, which is TWO devices: a 344 CSS px
 * cover screen and a 673 x 841 nearly-square main screen. A demo that works
 * folded and breaks unfolded is not wired, so the whole drive runs at both
 * viewports rather than at one arbitrary default.
 */
const DEVICE = JSON.parse(
  html.match(/<script type="application\/json" id="tl-device">([\s\S]*?)<\/script>/)[1]);

async function driveAt(key) {
  const vp = DEVICE[key].css;
  const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'http://localhost/' });
  const w = dom.window, d = w.document;
  const errs = [];
  w.addEventListener('error', e => errs.push('window.error: ' + e.message));
  w.console.error = (...a) => errs.push('console.error: ' + a.join(' '));
  Object.defineProperty(w, 'innerWidth', { value: vp.w, configurable: true });
  Object.defineProperty(w, 'innerHeight', { value: vp.h, configurable: true });
  await new Promise(r => setTimeout(r, 800));
  w.dispatchEvent(new w.Event('resize'));
  d.getElementById(key === 'cover' ? 'd-cover' : 'd-main').click();
  return { w, d, errs, vp, key };
}

const errorCardIn = (d) =>
  /hit an error/.test(d.getElementById('screen').innerHTML +
                      d.getElementById('panel').innerHTML);

for (const key of ['cover', 'main']) {
  const { d, errs, vp } = await driveAt(key);
  const tag = `[${key} ${vp.w}x${vp.h}]`;
  const errorCard = () => errorCardIn(d);

  check(`${tag} initial render produces a screen`, () => {
    if (!d.getElementById('screen').innerHTML.length) throw new Error('empty'); });
  check(`${tag} live clock is populated from the engines`, () => {
    if (!/live ·/.test(d.getElementById('livenote').textContent)) throw new Error('no clock'); });
  check(`${tag} device frame matches the true aspect ratio`, () => {
    const ph = d.querySelector('.phone');
    const got = parseInt(ph.style.width) / parseInt(ph.style.height);
    const want = vp.w / vp.h;
    if (Math.abs(got - want) > 0.02) throw new Error(`${got.toFixed(3)} vs ${want.toFixed(3)}`); });
  check(`${tag} frame never exceeds the viewport width`, () => {
    const px = parseInt(d.querySelector('.phone').style.width);
    if (px > vp.w - 24) throw new Error(`${px}px in ${vp.w}px`); });

  const next = d.getElementById('next'), prev = d.getElementById('prev');
  for (let i = 0; i < 20; i++) next.click();
  check(`${tag} guided tour reaches the last step`, () => {
    if (!/Step 14 of 14/.test(d.getElementById('stepn').textContent))
      throw new Error(d.getElementById('stepn').textContent); });
  for (let i = 0; i < 20; i++) prev.click();
  check(`${tag} tour walks back to step 1`, () => {
    if (!/Step 1 of 14/.test(d.getElementById('stepn').textContent))
      throw new Error('back failed'); });

  d.getElementById('m-explore').click();
  const nav = [...d.querySelectorAll('#nav button[data-go]')];
  check(`${tag} explore nav lists every screen`, () => {
    if (nav.length < 69) throw new Error(`${nav.length} screens`); });

  let rendered = 0;
  for (const b of nav) {
    b.click();
    const s = d.getElementById('screen').innerHTML;
    if (s.length > 20 && !/hit an error/.test(s)) rendered++;
  }
  check(`${tag} all ${nav.length} screens render clean`, () => {
    if (rendered !== nav.length) throw new Error(`${rendered}/${nav.length}`); });

  let clicks = 0, broke = 0;
  for (const b of nav) {
    b.click();
    for (const c of [...d.querySelectorAll('[data-hw],[data-hint],[data-tamper],[data-age],[data-age2],[data-handicap],[data-streak],[data-go]')]) {
      clickEl(c); clicks++;
      if (errorCard()) broke++;
    }
  }
  check(`${tag} ${clicks} control clicks produce no error card`, () => {
    if (broke) throw new Error(`${broke} broke`); });

  d.querySelector('[data-go=video]').click();
  check(`${tag} unfinished areas say "under construction"`, () => {
    if (!/under construction/i.test(d.getElementById('panel').innerHTML))
      throw new Error('missing'); });

  // ---- Read-only surfaces. The engine room is one of them: it renders live
  // engine output and has nothing to click, which is the point. It is covered by
  // the render check and by E6 in check-markup, which asserts all fourteen
  // engines are named in the BUILT artifact.
  // ---- Read-only surfaces: a briefing card, a list of things he could show her,
  // a catch-up digest. They have no controls by design and are covered by the
  // render check. `hisworld`, `briefing`, `catchup` and `paletteParent` are the
  // four of these; asserting playability on them asserts the wrong property.
  //
  // ---- Play every INTERACTIVE screen. Read-only views — what a parent sees —
  // are deliberately excluded: they have no controls by design, and asserting
  // playability on them would be asserting the wrong property. They are still
  // covered by the render check above.
  const GAMES = ['playTicTacToe','playDots','playMemory','playStory','playCheckers',
                 'playBattleship','playWordSearch','playHangman','playChess','playChain','playKim','playHunt','playLive','playPictionary','playShowcase','playShowPrompt','playCollection','playShowGuardian','expiry','onboarding','palette','paletteDaily','birthday','storyteller','colouring','findthing','spotdiff','library','thebook','asks','gallery','carenote','inbox','closing','reading','handoff','busy','ladder','quieting','letters','childbank','availability','deletion','siblings','teachme'];
  for (const g of GAMES) {
    d.querySelector(`[data-go=${g}]`).click();
    let moved = 0;
    for (let round = 0; round < 30; round++) {
      const cells = [...d.querySelectorAll(
        '[data-ttt],[data-ck],[data-bs],[data-ws],[data-hm],[data-mem],[data-chess],[data-db],[data-story],[data-chain],[data-kim],[data-kimgo],[data-hunt],[data-lv],[data-lvnext],[data-conn],[data-pict],[data-scage],[data-scshow],[data-sckind],[data-scdo],[data-scadd],[data-scadd2],[data-screply],[data-keep],[data-keepall],[data-obk],[data-obage],[data-obnext],[data-obback],[data-obrestart],[data-obcol],[data-pal],[data-bdm],[data-bdd],[data-bdy],[data-bdrestart],[data-bdage],[data-stnew],[data-stagain],[data-stcode],[data-colpick],[data-coltap],[data-colundo],[data-colmode],[data-colnew],[data-findtap],[data-findhint],[data-findnew],[data-spottap],[data-spotnew],[data-libstar],[data-libmark],[data-libresume],[data-libseed],[data-askadd],[data-askans],[data-galview],[data-galhide],[data-care],[data-inboxdone],[data-closestart],[data-closenext],[data-closeskip],[data-readturn],[data-readswap],[data-handoff],[data-busy],[data-a11y],[data-scale],[data-callmode],[data-callflip],[data-calldrop],[data-calllift],[data-panedock],[data-panesize],[data-paneavoid],[data-panehome],[data-mreduce],[data-tier],[data-tick],[data-streamreset],[data-sigsend],[data-sigtap],[data-sigdismiss],[data-sigmute],[data-sighour],[data-sigbusy],[data-sigreset],[data-ladderage],[data-quietage],[data-lseal],[data-lopen],[data-bankstart],[data-bankadd],[data-availpub],[data-delage],[data-sibclose],[data-sibreset],[data-teachadd],[data-teachagain]')];
      if (!cells.length) break;
      clickEl(cells[Math.floor(cells.length / 2)]);
      moved++;
      if (errorCard()) break;
    }
    check(`${tag} ${g} accepts real moves`, () => {
      if (moved === 0) throw new Error('no playable control found');
      if (errorCard()) throw new Error('error card while playing'); });
  }

  // New game / take back / handicap on every board.
  for (const g of GAMES) {
    d.querySelector(`[data-go=${g}]`).click();
    for (const c of [...d.querySelectorAll('[data-gnew],[data-gundo],[data-gh],[data-wsclear]')]) clickEl(c);
  }
  check(`${tag} restart, take-back and handicap work on every board`, () => {
    if (errorCard()) throw new Error('error card'); });

  // The hinge resizes the viewport live; nothing may depend on a width read once.
  d.getElementById('d-main').click(); d.getElementById('d-cover').click();
  d.getElementById('d-main').click();
  check(`${tag} survives folding and unfolding repeatedly`, () => {
    if (!d.getElementById('screen').innerHTML.length || errorCard())
      throw new Error('broke on fold'); });

  check(`${tag} no uncaught exceptions`, () => {
    if (errs.length) throw new Error(errs.slice(0, 2).join(' | ')); });
}

for (const [n, ok, why] of rows) {
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}` + (ok ? '' : `\n         ${why}`));
}
console.log(`\n${'-'.repeat(50)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
