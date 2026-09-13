import type { GameMeta } from './games.ts';

/**
 * MASTERFILE §9.2 — GamePickerScreen's Recommended row.
 * docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-design.md.
 *
 * Mirrors packages/jokes/src/jokes.ts's own favourites shape exactly, rather
 * than a new convention invented from scratch: `star`/`unstar` are
 * idempotent list edits, `favouritesFor` resolves stored kinds against the
 * live catalogue so a removed game silently drops rather than dangling. The
 * one deliberate difference from jokes.ts's `JokeFavourite { id, starredAt }`
 * shape is that a favourite here is a bare kind string, not an object with a
 * timestamp — the design spec's own Architecture section, and this file's
 * `guardian_game_favorite` table (db/migrations/0030), both key on
 * (guardian, kind) only; ORDER of favouriting is never surfaced to her (P2),
 * so there is nothing a `starredAt` field would earn its keep doing here.
 *
 * The third signal, age-unlock (`newlyUnlocked`), is genuinely new logic,
 * not a port of anything: a game whose `minAge` has been crossed since her
 * last visit to this screen is new to her, derived purely from her real age
 * and `child.birth_date` — no play-history, no usage tracking of any kind
 * (see the design spec's own §"Why favorites and age-unlock, not
 * play-history" for the full reasoning). `randomGame` ("Surprise me")
 * reuses jokes.ts's own `randomJoke(age, excludeId, pick)` contract
 * verbatim, down to the injectable `pick` for deterministic tests.
 *
 * P2 governs the whole file the identical way it governs jokes.ts: a
 * favourite is a kind and nothing else, no count, no order, no streak —
 * there is no field here to leak one.
 */

/** Idempotent — starring an already-starred kind is a no-op, not a duplicate. */
export function star(current: string[], kind: string): string[] {
  return current.includes(kind) ? current : [...current, kind];
}

export function unstar(current: string[], kind: string): string[] {
  return current.filter((k) => k !== kind);
}

/**
 * Resolves stored favourite kinds against the live catalogue. A kind that no
 * longer exists in `all` (a game removed from the catalogue) silently drops
 * out — never a dangling reference the UI would have to guard against
 * separately. Order follows `all`'s own order, not `starred`'s, so a
 * favourite's position in the Recommended row is stable catalogue order,
 * never "most recently favourited" (P2 — no order-of-favouriting signal).
 */
export function favouritesFor(all: GameMeta[], starred: string[]): GameMeta[] {
  return all.filter((g) => starred.includes(g.kind));
}

/**
 * Games she has newly grown into since her last visit to this screen — see
 * this file's own header for why age-unlock exists alongside favourites
 * rather than instead of it.
 *
 * `ageAtLastOpen == null` means either a first-ever open or no live session
 * at all — either way there is no real "since last time" to measure, so this
 * returns nothing rather than treating her ENTIRE starting catalogue as
 * newly unlocked, which would be a fabrication, not a recommendation.
 */
export function newlyUnlocked(
  all: GameMeta[], age: number, ageAtLastOpen: number | null,
): GameMeta[] {
  if (ageAtLastOpen === null) return [];
  return all.filter((g) => g.minAge <= age && g.minAge > ageAtLastOpen);
}

/**
 * "Surprise me" — one age-appropriate game she isn't currently looking at,
 * never the one she just came from. Identical contract to jokes.ts's own
 * `randomJoke(age, excludeId, pick)`: `pick` is injectable so a test can
 * drive it deterministically; production passes nothing and gets
 * Math.random. Returns null only if the age floor leaves nothing at all to
 * pick from.
 */
export function randomGame(
  all: GameMeta[], age: number, excludeKind: string | null,
  pick: () => number = Math.random,
): GameMeta | null {
  const pool = all.filter((g) => g.minAge <= age && g.kind !== excludeKind);
  if (pool.length === 0) return null;
  return pool[Math.floor(pick() * pool.length) % pool.length];
}
