# Branch strategy

This repo uses two different *kinds* of long-lived branch, for two different
reasons. Mixing them up is the most likely way to lose someone's work, so
this file exists to write the policy down in one place.

## `main` — the trunk

`main` is the single shared source of truth for the app. All day-to-day
feature work happens on a `feature/<name>` branch cut from `main`, and lands
back on `main` only after review. **Nothing gets pushed directly to `main`
without explicit sign-off from the project owner** — that rule applies to
every session working in this repo, human or otherwise.

## `device/phone`, `device/tablet`, `device/pc`, `device/watch` — per-device branches

These four branches exist so that device-specific work — packaging tweaks,
platform-specific fixes, a layout adjustment that only makes sense on one
form factor, native-build config — can be committed to the one branch it
actually concerns, without being forced onto the other three at the same
time.

**They are ordinary, independent branches. Nothing in this repo merges them
into each other automatically.** A commit made on `device/tablet` will not
appear on `device/phone` unless someone explicitly brings it over (merge,
rebase, or cherry-pick) — and the reverse is equally true. Treat a push to
one of these branches as scoped to that branch alone.

They were cut from `main` on 2026-08-08 at `18ec8cdf` and, as of this
writing, still sit at that same commit — identical to each other, but no
longer identical to `main` itself, which has since moved well ahead (37
commits, as of 2026-08-21) on ordinary trunk work that never had a reason to
touch a device branch. That's expected: these branches pick up shared work
only via a deliberate merge/rebase (see "Working with a device branch"
below), not automatically, so drifting behind `main` is normal, not a sign
of anything broken. They'll pick up their first real device-specific
commits as that work comes in, at which point they'll genuinely stop being
identical to each other too.

### Why this isn't four separate apps

The Flutter client itself is intentionally **one shared, responsive
codebase** across phone and tablet — not a fork per screen size. MASTERFILE
is explicit about why: a separated family frequently doesn't control what
device the child ends up with (a hand-me-down phone, a budget tablet, a
folding phone's tiny cover screen next to its tablet-sized unfolded one),
so the app is built to adapt to whatever screen it's actually given rather
than assuming one shape. `device/phone` and `device/tablet` are
integration branches for that one codebase, not the seam of a future
phone-app/tablet-app split. `device/pc` (Windows) and `device/watch`
(Wear OS) are the ones with a genuine platform difference underneath, since
those are separate Flutter build targets already.

### Working with a device branch

- **Shared feature work** (the normal case): merges to `main` as usual.
  Bringing a shared feature onto a device branch is a deliberate, separate
  step — merge or rebase `main` into `device/<name>` when you want that
  device to pick it up, not automatically.
- **Device-only change**: commit straight to `device/<name>`. It stays
  there until someone deliberately ports it elsewhere (e.g. cherry-picking
  a tablet-only layout fix back onto `main` once it's proven out).
- Before pushing to any `device/*` branch, `git fetch` and check you're
  not about to overwrite a commit someone else just pushed to that same
  branch — the usual courtesy for any shared branch, doubly so here since
  more than one session may be working in this repo at once.
