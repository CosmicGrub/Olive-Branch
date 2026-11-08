# Round 2 kit changes (kit.js, overhaul.css)

Everything is additive. Round-1 helpers keep their names, arguments and CSS classes. K = OB. Every helper returns an HTML string.
The full signature list is also the comment block at the top of `kit.js`.

## Changed behaviour of existing helpers (same call, richer output)
- `K.toggle(on,{label})`, `K.seg`, `K.tabbar`, `K.tile`, `K.row` (when `go`), `K.avatar`, `K.banner`, `K.progress`, `K.dots`, `K.sheet`, `K.btn({disabled,label})` now emit `role`/`aria-*`/`tabindex`. Output still contains `class="btn `, `class="cbtn"`, `class="tabbar"`, `class="tile feat`, so string `.replace()` tricks in screen files keep working.
- `K.avatar` gains `tone: ok|info|warn|quiet` and `status: on|away`. `K.btn` gains `type="button"`.
- Hit areas: back/icon buttons are 44 visual, 48 hit (child 56 visual, 64 hit). Segmented spans are 48 tall including padding. Tab items 48 (child 64).

## Theme tokens (set on `.ob`)
`--line` hairline, `--edge` control border (3:1), `--track`, `--focus` ring, `--hiC` inner highlight, `--hero1/--hero2/--sheen`, `--shadow0..3` (shadow1/2 keep round-1 meaning but are layered). CSS-only tokens: radii `--r0..--r5`, space `--sp1..--sp6`, type `--fs-*`, motion `--ease-out --ease-spring --ease-in --d-press(40ms) --d-fast --d-base --d-slow(340ms)`.
Contrast verified: 7 palettes x light/dark, all text pairs >= 4.5:1 (ink/ink2/ink3 on bg, surface, surface2, surface3; on-primary on primary and primary-dark; on-tint; ok/warn/bad/info on tints and surface; ink on accent tint; hero gradient with sheen), non-text >= 3:1 (edge on bg/surface/surface2, track, focus ring on bg/surface, semantic icons on tints). Tertiary text was darkened (light) or raised (dark). Day-part colours untouched.

## Type classes (inside `.ob`)
`t-display` 34/1 -.035em, `t-title` 22, `t-head` 17, `t-body` 15, `t-cap` 12.5 (ink3), `t-label` mono caps 10.5, `t-mono`, `tnum` (tabular numerals). `.big`, `.dual`, `.ttl b` got tighter tracking.

## New helpers (one example each)
| Helper | Example |
|---|---|
| `K.segmented(items,a,o)` | `K.segmented([{l:"Today",count:3},"Week","Month"],0)` |
| `K.filterChip` / `K.filterChips` | `K.filterChips(["All","Dad",{l:"Grandma",count:2}],[0,2])` |
| `K.check(on)` `K.radio(on)` `K.slider(pct,o)` | `K.slider(60,{label:"Volume"})` |
| `K.toggleRow` `K.radioRow` `K.checkRow` | `K.toggleRow({title:"Quiet hours",sub:"After 8",on:true,ic:"moon"})` |
| `K.sliderRow(o)` | `K.sliderRow({title:"Text size",value:60,text:"Large",l:"A",r:"A"})` |
| `K.formField(o)` | `K.formField({label:"Email",value:"dad@",error:"Looks unfinished",req:true})` (real `<input>`, aria-describedby) |
| `K.pinPad(o)` | `K.pinPad({title:"Grown-ups only",filled:2,zero:true,bio:true})` (child pad: omit `zero`, 9 shuffled digits) |
| `K.avatarStack(list,o)` | `K.avatarStack([["I"],["D","accent"],"M","G","H"],{size:34,max:4})` |
| `K.status(kind,text)` | `K.status("watched","Watched 7:04")` kinds: queued sent delivered watched failed banked (icon + word + shape, never colour only) |
| `K.notice(o)` | `K.notice({tone:"warn",title:"Clock ahead",text:"…",action:"See why",dismiss:true})` |
| `K.offlineBanner(o)` | `K.offlineBanner({action:"Retry"})` |
| `K.toast(text,o)` | `K.toast("Message banked",{ic:"check",action:"Undo"})` absolute above tab bar; `inline:true` to flow |
| `K.emptyState(o)` | `K.emptyState({spot:"envelope",title:"No letters yet",sub:"…",action:"Write one"})` |
| `K.errorState(o)` | `K.errorState({title:"That did not work",detail:"E-4012"})` |
| `K.skeleton(kind,n)` | `K.skeleton("row",3)` kinds row card text tile hero (static, no shimmer) |
| `K.permission(o)` | `K.permission({ic:"camera",title:"Allow the camera?",body:"…",why:["…"]})` |
| `K.bottomSheet(o)` | `K.bottomSheet({title:"Send to",inner:"…",actions:K.btn("Done"),close:true,detent:"full"})` |
| `K.modal(o)` | `K.modal({ic:"trash",tone:"bad",title:"Remove?",body:"…",actions:K.btn("Cancel",{kind:"ghost"})+K.btn("Remove",{kind:"danger"})})` |
| `K.swipe(rowHtml,o)` | `K.swipe(K.row({title:"Pencils"}),{actions:[{l:"Delete",ic:"trash",tone:"bad"}],open:false})` |
| `K.stepper(total,active)` / `K.steps(labels,active)` | `K.stepper(5,3)`, `K.steps(["Role","Code","Scan"],1)` |
| `K.kv(rows)` `K.divider(text)` | `K.kv([["Recorded","Tuesday"]])` |
| `K.stat(o)` | `K.stat({label:"Next handover",value:"3",unit:"sleeps",note:"Friday",ic:"calendar"})` never a score, rank or streak |
| `K.timeline(items)` | `K.timeline([{time:"7:04",title:"Watched",state:"done",tone:"ok"},{title:"Now",state:"now"},{title:"Later",state:"next"}])` |
| `K.schedule(blocks,o)` / `K.scheduleBlock` | `K.schedule([{s:8.5,e:15,title:"School",tone:"info"}],{from:7,to:20,now:11})` |
| `K.calMonth(o)` / `K.dayCell` | `K.calMonth({today:7,sel:12,marks:{1:"a",5:"b",4:"mix",14:"ev"}})` a = house A (Mom), b = house B (Dad), shape differs as well as tint |
| `K.recordBtn(o)` | `K.recordBtn({state:"rec",time:"0:12"})` states idle rec done |
| `K.waveform(o)` | `K.waveform({played:.4,h:48,seed:3})` |
| `K.player(o)` | `K.player({scene:"garden",caption:"Goodnight, Ivy.",progress:34,playing:false})` |
| `K.qrCard(o)` | `K.qrCard({code:"OLIVE-7K4P",title:"Scan on her tablet",expires:"10 minutes"})` placeholder pattern, not a real QR |
| `K.spot(kind,size,o)` | `K.spot("family",96)` kinds in `K.SPOTS`: family houses envelope key shield lock phone tablet video mic leaf |
| `K.scene(kind,w,h)` | new kinds: day garden kitchen car classroom bedroom park twohouses (alias houses) |
| `K.sr(text)` | visually hidden text |

Card variants: `card raised`, `card sunk`, `card outline`, `card interactive`, `card hero warm`.
Frames: `K.FORMS` size table; new frame-only postures `foldMain` (520x620, vertical crease) and `foldTabletop` (520x600, horizontal crease). `K.frame(s,"foldMain")` works; screens only get `c.form` of that name.

## Motion
Press 40 ms, state changes 120-220 ms, optional entrances (`.enter` on sheet/modal/toast/scrim) 220-340 ms with spring easing under 6% overshoot. Nothing animates by itself (skeleton is static). `prefers-reduced-motion` collapses all durations.
