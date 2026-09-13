/**
 * MASTERFILE §9.1, §3.1 — the shared annotation surface.
 *
 * Collaborative undo is the whole difficulty. The naive implementation pops the
 * last stroke on the canvas, which means a parent's undo erases the child's
 * drawing — and on a homework sheet that reads as the parent deleting her work.
 * Undo must be scoped to the actor's own strokes and must never resurrect a
 * stroke someone else erased.
 */

export type ActorKind = 'child' | 'guardian' | 'observer';

export interface Stroke {
  id: string;
  actorId: string;
  actorKind: ActorKind;
  /** Monotonic per-session ordering. Ties break on actorId for determinism. */
  seq: number;
  points: [number, number][];
  color: string;
  widthPx: number;
  /** Set when undone. Strokes are tombstoned, never spliced out. */
  undoneAt: number | null;
  /** Set when someone erased it explicitly (distinct from undo). */
  erasedBy: string | null;
}

export interface PointerEvent {
  actorId: string;
  x: number;
  y: number;
  at: number;
}

/** §17.3 — an observer watches. They may point, they may not draw. */
export const CAN_DRAW: Record<ActorKind, boolean> = {
  child: true, guardian: true, observer: false,
};

export const POINTER_TTL_MS = 1500;

export class Canvas {
  private strokes: Stroke[] = [];
  private seq = 0;
  private pointers = new Map<string, PointerEvent>();

  add(input: Omit<Stroke, 'seq' | 'undoneAt' | 'erasedBy'>):
    { ok: true; stroke: Stroke } | { ok: false; reason: 'observer_readonly' | 'empty' } {
    if (!CAN_DRAW[input.actorKind]) return { ok: false, reason: 'observer_readonly' };
    if (!input.points.length) return { ok: false, reason: 'empty' };
    const s: Stroke = { ...input, seq: ++this.seq, undoneAt: null, erasedBy: null };
    this.strokes.push(s);
    return { ok: true, stroke: s };
  }

  /**
   * Undo the actor's own most recent live stroke. Three properties that a
   * last-on-canvas implementation gets wrong:
   *
   *  - It must skip strokes belonging to anyone else.
   *  - It must skip strokes already undone, so repeated undo walks backwards
   *    rather than toggling one stroke.
   *  - It must skip ERASED strokes entirely — including ones the same actor
   *    erased themselves. Erase and undo are deliberately distinct, one-way
   *    mechanisms: undo only ever manipulates `undoneAt`, and erase only
   *    ever manipulates `erasedBy`. Letting a self-erased stroke re-enter
   *    the undoneAt bookkeeping here would hand it a timestamp that
   *    competes with real draw-undos in redo()'s "most recently undone"
   *    ordering — corrupting which stroke a later redo() actually restores.
   *    (Live-found bug, not a hypothetical: the original version of this
   *    guard only skipped strokes erased by someone ELSE.)
   */
  undo(actorId: string, at: number): Stroke | null {
    for (let i = this.strokes.length - 1; i >= 0; i--) {
      const s = this.strokes[i];
      if (s.actorId !== actorId) continue;
      if (s.undoneAt !== null) continue;
      if (s.erasedBy !== null) continue;
      s.undoneAt = at;
      return s;
    }
    return null;
  }

  /** Redo the actor's most recently undone stroke. */
  redo(actorId: string): Stroke | null {
    let best: Stroke | null = null;
    for (const s of this.strokes) {
      if (s.actorId !== actorId || s.undoneAt === null) continue;
      if (!best || s.undoneAt! > best.undoneAt!) best = s;
    }
    if (best) best.undoneAt = null;
    return best;
  }

  erase(strokeId: string, byActorId: string): boolean {
    const s = this.strokes.find(x => x.id === strokeId);
    if (!s || s.erasedBy) return false;
    s.erasedBy = byActorId;
    // A stroke must never simultaneously carry a live undoneAt AND a set
    // erasedBy — undo()'s own guard (above) already keeps an ALREADY-erased
    // stroke from ever being handed a fresh undoneAt, but the reverse
    // ordering (undo a stroke first, legitimately, THEN erase that same
    // stroke) was a real, live-found gap: erase() left the stale undoneAt in
    // place, so redo()'s "most recently undone" comparison could still pick
    // the now-erased stroke as its restoration target — a silent no-op on
    // the wrong stroke that shadowed the actually-expected one. Clearing it
    // here closes the invariant at its one real source, rather than adding
    // a second erasedBy check to every future undoneAt reader.
    s.undoneAt = null;
    return true;
  }

  /** Deterministic render order regardless of arrival order. */
  visible(): Stroke[] {
    return this.strokes
      .filter(s => s.undoneAt === null && s.erasedBy === null)
      .sort((a, b) => a.seq - b.seq || a.actorId.localeCompare(b.actorId));
  }

  /**
   * A pointer is a gesture, not ink. It expires and is never persisted with the
   * artifact — a homework photo that accumulated every laser sweep would be
   * unreadable, and the pointer carries no meaning after the moment.
   */
  point(e: PointerEvent) { this.pointers.set(e.actorId, e); }
  activePointers(now: number): PointerEvent[] {
    return [...this.pointers.values()].filter(p => now - p.at < POINTER_TTL_MS);
  }
  /** What gets written to the artifact. Pointers deliberately absent. */
  serialize(): { strokes: Stroke[] } {
    return { strokes: this.visible() };
  }
}
