# LIVE prototype: shared contract (v1)

A clickable, stateful simulation of Olive Branch: TWO devices side by side (guardian phone on the left, child tablet on the right) that talk to a SIMULATED server through a virtual clock. Plain HTML, CSS and JS, no build step, no network, no libraries beyond what the overhaul kit already uses. Reuse `kit.js` and `overhaul.css` helpers (K.top, K.card, K.row, K.tile, K.btn, K.ico, K.avatar, K.sheet and the rest documented in KIT-CHANGES.md) so screens look like the Round 3 mockups. Palette and mode tokens come from `K.theme(palette, mode)` applied on each device's `.ob` root.

Files (each owned by ONE agent; never edit another agent's file):
- `index.html`, `live-core.js`, `mod-shell.js`, `mod-onboarding.js`, `mod-console.js`: agent CORE.
- `mod-messages.js`: agent MSG.
- `mod-guardian.js`: agent GRD.
- `mod-child.js`: agent KID.

Load order: kit.js, live-core.js, mod-shell.js, mod-onboarding.js, mod-messages.js, mod-guardian.js, mod-child.js, mod-console.js. Every module is an IIFE that calls `LIVE.module(name, function(L){ ... })`; core runs the modules after DOMContentLoaded in load order. `window.LIVE` is created by live-core.js.

## State and rendering
- `L.S` is one plain, JSON-serialisable state object (optionally persisted to localStorage key `olive-live-v1`, with a Reset). Keys owned by modules are namespaced: `S.clock`, `S.net`, `S.server`, `S.family`, `S.dev.g`, `S.dev.k`, `S.ui` (CORE); `S.msg` (MSG); `S.grd` (GRD); `S.kid` (KID).
- `L.update(fn)` mutates S, then re-renders both devices and the console. `L.render()` forces a render. Rendering is string based; clicks use event delegation.
- Devices: `dev` is `'g'` (guardian Fold5-style phone) or `'k'` (child Tab S9 FE-style tablet, also switchable to phone width). `S.dev[dev] = {role: null|'kid'|'mom'|'dad'|'other', stack: [{id, params}], paired: false, deviceId, sessionOk: false, battery, locked: false}`.
- Screens: `L.screen(id, {dev: 'g'|'k'|'both', title, render(c)})`. Navigation: `L.go(dev, id, params)`, `L.back(dev)`, `L.home(dev)`. Feedback: `L.toast(dev, text)`, `L.sheet(dev, html)`, `L.closeSheet(dev)`.
- Context `c` given to render: `{dev, S, params, role, L, labels, band, now}`.
- Actions: in HTML use `data-act="name" data-arg="value"` (and optionally `data-arg2`). Register with `L.act('name', function(c, arg, el, ev){ ... })`. Text inputs: `data-bind="path.in.S"` two-way binds into S; typing does not re-render, blur or change does.
- Contributing UI without editing the shell: `L.tile({dev, area: 'home'|'more'|'settings', tier: 'hero'|'featured'|'standard', id, title, sub, icon, screen, order, when: function(c){return bool}, badge: function(c){return null|true|number}})`. Child tiles follow the child rules (picture first, the badge is a dot, never a number). Settings rows use `L.tile({dev: 'g', area: 'settings', group: 'Her'|'Family'|'Safety'|'Learn'|'Account', ...})`.
- Age bands: `L.band()` returns `'t34'|'t57'|'t812'|'t1317'` from `S.family.child.age` (3 to 17). Home layouts: `L.homeVariant(band, function(c){return html})` (agent KID registers all four; CORE falls back to a default).
- Labels (owner rule): `L.labels.forChild(guardianId)` returns 'Mom' or 'Dad' before the child's age is locked; once locked and the age is 5 to 15 it returns 'Mommy' or 'Daddy'; age 16 and up returns 'Mom' or 'Dad'. A child nickname (`S.family.child.nicknames[guardianId]`) always wins. `L.labels.forGuardian(guardianId)` shows both, for example 'Ivy calls you Dada'. `L.labels.rename(guardianId, nick)`. A guardian can never overwrite a nickname.

## Virtual clock and server
- `S.clock = {t: ms since epoch, speed: 1|60|600|3600, paused}`. `L.now()` returns `new Date(S.clock.t)`. Core advances it with a timer. `L.every(virtualMs, fn, name)` and `L.after(virtualMs, fn, name)` schedule against the VIRTUAL clock. Time zones: Mom is America/Chicago, Dad is America/New_York; the child's home follows custody. Show 'her time' and 'your time' where the real app does.
- Server simulation: `L.route(method, path, fn(req){return {status, body}})` registers handlers under `/v1/...` mirroring the real API. `L.api(dev, method, path, body)` returns a Promise that:
  - fails with status 0 `offline` when `S.net.online === false` for that device;
  - waits a simulated latency (`S.net.latencyMs`);
  - requires auth (`S.dev[dev].sessionOk`) on authenticated routes;
  - applies simulated rate limits;
  - appends a line to `S.server.log` (`{t, dev, method, path, status, ms, reqId}`), shown in the console;
  - calls the handler with `req = {dev, principal, body, params}`.
  Principals are guardian, child and sitter. Use the real server's error codes where known (`not_a_child_surface`, `stale_version`, `device_revoked`, `invalid_device_credential`, and so on).
- Events: `L.emit(type, payload)` and `L.on(type, fn)`, also appended to `S.server.events`. Standard events: `time:tick`, `net:change`, `device:paired`, `family:changed`, `msg:delivered`, `msg:opened`, `msg:watched`, `call:knock`, `age:band`.

## Behaviour that must be TRUE to the real app
Read `Z:\olive branch files\MASTERFILE.md` and the Round 3 mockups under `..\overhaul3` for detail.
- **Role-first onboarding (CORE).** The first screen on each device asks 'Who is using this device?' with Kid, Mom, Dad and a smaller 'Someone else'.
  - Kid path: name, age (5 to 15 picker; the age locks), colour, birthday, 'what do you call your grown-ups?' (renaming like contacts), and LAST 'Connect this device' (a 6-digit code made on the guardian device; needs the network; draft answers are saved locally first and uploaded after pairing; offline shows a friendly picture-only retry).
  - Guardian path: your name and label, the child's name and age (locks it), home time zone, PIN, then Connect this device where it honestly can be last.
- **Prohibitions P1 to P11.** No scores, streaks, rewards or leaderboards for the child. No location. The child shell has no settings. The child never sees counts (unread is a dot). The child's private journal and worry box are never visible to guardians unless she chooses to show them. Guardians never see her feelings weather. Child copy is warm and plain, with no error codes on the child device (picture-only states).

## Console (CORE), beside or below the devices
Virtual time controls (play, pause, 1x, 1 min per second, 10 min per second, 1 hour per second, jump to next bedtime, next morning, next exchange). A network toggle per device. A 'Child age' slider from 3 to 17 that derives the band live. Palette and mode switch. The server request log with filters. The event timeline. A state inspector. Reset. 'Scenarios': one-click scripted walkthroughs that drive the real UI actions step by step with captions (Golden path, Offline night, Family change released, Birthday band change, Call knock, Play window, Account deletion hold). Mark everything 'SIMULATION: no real server'.

## Rules for all modules
- Sample data only: Ivy (the child), Jess (Mom), Marcus (Dad).
- Every interactive element is keyboard reachable with a visible focus ring. Targets are at least 48 px (64 px on the child device). AA contrast in light and dark. Reduced motion respected.
- No horizontal overflow at 1280 px or 400 px (the devices stack on narrow screens, with a single-device view switch).
- No external requests, and no libraries from CDNs beyond the Google Fonts the kit already uses.

---

# CORE addendum (what `live-core.js`, `mod-shell.js`, `mod-onboarding.js`, `mod-console.js` actually provide)

SIMULATION: no real server. Everything below is implemented; names are exact.

## Resolved ambiguities
- **`L.api` never rejects.** It always resolves `{ok, status, body, code, error, message, reqId, ms}`. Offline is `status:0, code:'offline'`. Error bodies are `{error:{code,message,...}}`. Branch on `r.ok`, `r.status` or `r.code`.
- **Online state** is `S.net.g.online` / `S.net.k.online` (never a single global). Read it with `L.online(dev)`; change it with `L.setOnline(dev, bool)` (emits `net:change {dev, online}`).
- **Routes are authenticated by default.** `L.route(method, path, fn, opts)`; `opts.public:true` skips auth, `opts.principals:['guardian'|'child'|'sitter']` restricts who may call. A child-only route called by a guardian returns 403 `not_a_child_surface`; a guardian-only route called by a child returns 403 `forbidden` (`error.reason:'not_a_guardian_surface'`). Handler returns `{status, body}` (or a Promise of it). Helpers: `L.ok(body, status)`, `L.fail(status, code, message, extra)`. `req` is `{dev, principal:{kind,id,deviceId,role,dev}, body, params, query, method, path, reqId}`.
- **Auth/session**: `S.server.sessions[dev] = {token, expiresAt}` (virtual time). An expired session returns 401 `session_expired` and emits `auth:expired {dev}`. A revoked device returns 401 `device_revoked` (`S.server.revoked[deviceId]`). `L.newSession(dev, days)` signs a device in.
- **Pairing codes are 6 digits, digits 1 to 9 only** (so the child's nine-key pad can type any code). Valid for 10 virtual minutes; a new code revokes older open ones.
- **`L.reset()` reloads the page** (every module re-initialises its own namespace). `L.reset({scenario:id})` reloads and autostarts a scenario. `L.state(ns, factory)` gives a module namespace a default (applied if `S[ns]` is missing, including after a persisted restore). Persistence is off by default; the console checkbox (or `L.setPersist(true)`) turns it on (pref key `olive-live-pref`, state key `olive-live-v1`).
- **Child's colour**: the tablet's theme uses `S.family.child.color` (a `K.SEEDS` key) unless `S.ui.childColour === false`; while unpaired it previews `S.dev.k.draft.color`.
- Guardian ids are `'mom' | 'dad' | 'other'`. The first guardian created through onboarding takes the id of the chosen role; `L.gid(dev)` and `L.me(dev)` give the device's guardian id and record. `S.family.guardians[i] = {id,name,label,tz,devices,joinedAt}`. A second guardian (GRD) should push another record; `S.family.custody` already alternates between two guardians at each exchange.

## State owned by CORE (extra keys)
`S.family = {id, created, homeTz, guardians[], child:{id,name,age,ageLocked,color,birthday:{m,d},nicknames:{mom,dad}}, schedule:{bedtime:'19:30', morning:'07:00', exchange:{dow:5,time:'17:00'}}, custody:{with,since}, pin, devices[{dev,deviceId,kind,name,pairedAt}]}`.
`S.dev[dev]` also has `onboarded` and `draft` (per-device local drafts: kid answers, guardian answers, pairing UI state). `S.net = {g:{online}, k:{online}, latencyMs, failNext:{g,k}, rate:{limit,windowMs}}`. `S.server = {log[], events[], seq, pairing[], sessions, pinFails, pinLockUntil, redeemFails, revoked}`. `S.ui = {palette, mode, form:{g,k}, view, persist, childColour, g:{sheet,toast}, k:{sheet,toast}}` (`form.g` is `'cover'|'phone'|'foldMain'`, `form.k` is `'tablet'|'phone'`).
The virtual clock starts on Monday 9 Nov 2026, 17:30 in Chicago. Time zones: Mom America/Chicago, Dad America/New_York.

## Extra public API
- Time: `L.t()`, `L.advance(ms)`, `L.jumpTo(t)`, `L.jumpToNext('bedtime'|'morning'|'exchange'|'birthday')`, `L.nextAt(kind, from?)`, `L.setClock({speed,paused})`, `L.cancel(timerId)`. `L.every/after` return a timer id. Time zone helpers: `L.parts(t,tz)`, `L.zoned(y,m,d,h,min,tz)`, `L.homeTz()` (tz of the guardian who currently has the child), `L.tzName(tz)`, `L.dayPart(t,tz)`, `L.fmt.time|day|dayFull|dayTime|short|dur|mss`. Elements with `data-clock="time|America/Chicago"` (format|tz) and `data-countdown="<epoch ms>"` are refreshed every tick without a re-render; use them for live clocks and countdowns.
- Schedule events emitted by the clock: `time:bedtime`, `time:morning`, `time:exchange {from,to}` (flips `S.family.custody` when two guardians exist), `time:jump`, plus `family:changed {what}` and `age:band {from,to,age}`. A birthday (`S.family.child.birthday`) increments the age at local midnight. `L.setAge(n)` changes the age and emits `age:band` when the band changes.
- Other events: `device:paired {dev,kind,deviceId}`, `device:revoked {deviceId}`, `pairing:code`, `pairing:mismatch`, `auth:expired`, `auth:signin`, `auth:signout`, `net:change`, `booted`. `L.emit` also schedules a render.
- Navigation: `L.replace(dev,id,params)`, `L.reroot(dev,id,params)` (replace the whole stack), `L.current(dev)`, `L.hasScreen(id,dev)`. `L.sheet(dev, htmlOrFn)` accepts a function `(c)=>html` for sheets that must stay live. The Back button (`.cbtn[aria-label=Back]` from `K.top({back:true})`) works with no wiring. Esc closes a sheet.
- HTML helpers (they inject `data-act` / `data-bind` into kit markup): `L.a(name,arg,arg2)` attribute string, `L.withAct(html,name,arg,arg2)`, `L.btn(text,act,arg,{kind,full,size,disabled,ic})`, `L.iconBtn(ic,act,arg)`, `L.row({..., act, arg})`, `L.field({label,path,ph,hint,error,type,ic,req,maxlength,inputmode})` (input bound to an S path), `L.seg(items,active,act,{args})`, `L.chips(items,active,act,{args})`, `L.toggle(on,act,arg)`, `L.toggleRow({..., act,arg})`, `L.tabbar(dev,[{ic,label,screen|act,arg,badge}],activeScreen)`, `L.renderTile(c,tile)`. Built-in actions: `go` (arg = screen id, `data-arg2` = JSON params), `back`, `home`, `sheet.close`, `noop`, `toast`. Form controls with `data-act` fire on `change` with the control's value as `arg`.
- Driving the real UI from code: `L.tap(dev, actName, arg)` clicks the on-screen element if present (with a visible pulse) else runs the action; `L.type(dev, path, value)` types into a `data-bind` input; `L.run(dev, actName, arg, arg2)` runs an action directly. Also `L.hasAct(name)` and `L.acts()`.
- Shell (`mod-shell.js`): `L.ui.empty|loading|error(opts)`, `L.stateLine(fn(c), priority)` (add a sentence for the guardian home; the first non-empty wins; a built-in fallback exists), `L.stateText(c)`. Tile areas used by the shell: guardian `home` (hero / featured / standard), `more`, `settings` (with `group`); child `home`, `more`. Tiles take `act`+`arg` (instead of `screen`), `scene` (hero background), `tone`, `params`; `title` and `sub` may be functions of `c`. Shell-owned settings rows: Her calls you (`ob.names`), Paired devices (`ob.devices`), Add a tablet (`ob.addDevice`), Guardian PIN (`ob.pinInfo`), Sign out (`ob.signOut`). If no variant is registered for the band, the shell renders a default child home (picture-first, dot badges, a "More for you" tile, lock chip, no settings).
- Console (`mod-console.js`): `L.scenario(id, {title, desc, fresh, steps:[{cap, dev, acts:[...]}]})` registers a scenario; `L.fastFamily()` builds a ready, paired family through the real routes (a module can set `L.fastExtras = function(){ return promiseOrNothing; }` to add its own fixtures, for example the simulated Marcus). A scenario with `fresh:true` resets first.

## Built-in routes (all under `/v1`)
| Route | Who | Notes |
|---|---|---|
| `GET /now`, `GET /me` | any (`/now` public) | `/me` returns principal, family summary, device |
| `POST /families` | public | body `{guardian:{role,name,label,tz}, child:{name,age}, pin, homeTz}`; creates the family, locks the child's age, signs the device in |
| `POST /children/:childId/device-pairing-codes` | guardian only | body `{pin}`; 403 `invalid_pin` (5 wrong = 423 `pin_locked` for 15 virtual min); a child gets 403 `forbidden`; returns `{code, expiresAt, ttlMs, qr}` (201) |
| `POST /device-pairing/redeem` | public | body `{code, role:'child'}`; unknown/expired/used code = 404 `not_found`; a non-child device = 409 `role_mismatch` (`failed_attempts` +1, 5 revokes the code); offline = status 0; 5 wrong codes = 429 `rate_limited` (5 virtual min) |
| `PUT /children/:childId/profile` | child only | merges the tablet's draft answers; a locked age is never overwritten |
| `POST /auth/session` | public | sign back in with the guardian PIN |
| `POST /auth/session/refresh` | public | needs a device credential |
| `POST /auth/session/sign-out` | any | |
| `DELETE /devices/:deviceId` | guardian | revokes a paired device (`device_revoked` afterwards) |

## Screens and actions registered by onboarding (stable names for scenarios)
Screens: `ob.role`, `ob.kid.name|age|color|birthday|names|connect|welcome`, `ob.g.you|child|zone|pin|connect|done|join`, `ob.other`, `ob.addDevice`, `ob.devices`, `ob.signin|expired|signedout`, `ob.revoked`, `ob.names`, `ob.pinInfo`.
Actions: `ob.pickRole(role)`, `ob.kid.pickAge(n)`, `ob.kid.askLock`, `ob.kid.lockAge`, `ob.kid.pickColor(key)`, `ob.kid.setBM(m)`, `ob.kid.setBD(d)`, `ob.kid.submit`, `ob.kid.retry`, `ob.kid.finish`, `ob.g.label`, `ob.g.pickAge`, `ob.g.zone(tz)`, `ob.g.create`, `ob.g.finish`, `ob.pad(digit|'del')`, `ob.add.make`, `ob.add.again`, `ob.add.done`, `ob.dev.ask(id)`, `ob.dev.remove(id)`, `ob.signin.go`, `ob.signOut`, `ob.restart`. Bound inputs: `dev.<g|k>.draft.name|gname|cname|nick.mom|nick.dad|inviteCode`.
