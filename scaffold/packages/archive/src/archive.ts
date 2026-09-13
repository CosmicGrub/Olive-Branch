import { DateTime } from 'luxon';

/**
 * MASTERFILE §9.8 — the archive, its annual compilation, and its terminus.
 *
 * §2.10: the archive belongs to the child; parents are custodians of it, not
 * owners. §9.8.4 is where that stops being a sentence.
 */

export interface Artifact {
  id: string; childId: string; kind: string; storageKey: string;
  capturedAt: string; capturedTz: string;
  preserved: boolean; eraTag: string | null; authorId: string | null;
}

// ================================================================= Year Book =
export interface YearBookSection { title: string; artifactIds: string[]; }
export interface YearBook {
  childId: string; year: number;
  sections: YearBookSection[];
  artifactCount: number;
  /** Seasons she was in each zone — she moved, and the book should say so. */
  places: { zone: string; days: number }[];
  printable: boolean;
}

/**
 * §9.8.2 — compiled from PRESERVED artifacts only.
 *
 * An unpreserved artifact is on a retention clock and may already be gone by
 * the time a book is printed; including it would produce a volume with holes.
 * This is also why §12.1 put the `preserved` column in the Phase 0 migration.
 */
export function compileYearBook(
  all: Artifact[], childId: string, year: number,
): YearBook {
  const mine = all.filter(a =>
    a.childId === childId && a.preserved &&
    DateTime.fromISO(a.capturedAt).setZone(a.capturedTz).year === year);

  const by = (kinds: string[]) => mine.filter(a => kinds.includes(a.kind)).map(a => a.id);
  const sections: YearBookSection[] = [
    { title: 'Things you said',   artifactIds: by(['video_msg', 'voice_note']) },
    { title: 'Things you made',   artifactIds: by(['drawing']) },
    { title: 'Things you learned',artifactIds: by(['homework']) },
    { title: 'Moments',           artifactIds: by(['photo', 'call_clip']) },
  ].filter(s => s.artifactIds.length > 0);

  const places = Object.entries(
    mine.reduce<Record<string, Set<string>>>((acc, a) => {
      const d = DateTime.fromISO(a.capturedAt).setZone(a.capturedTz).toISODate()!;
      (acc[a.capturedTz] ??= new Set()).add(d);
      return acc;
    }, {}),
  ).map(([zone, days]) => ({ zone, days: days.size }))
   .sort((a, b) => b.days - a.days);

  return {
    childId, year, sections, artifactCount: mine.length, places,
    // A book of three items is not a book. Below this it is a slideshow and
    // offering to print it would be a poor use of a family's money.
    printable: mine.length >= 12,
  };
}

// =========================================================== majority handover
export interface Child {
  id: string; birthDate: string; majorityAge: number;
  handedOverAt: string | null; deceasedAt?: string | null;
}

export type HandoverDenial =
  | 'not_yet_of_age' | 'already_handed_over' | 'child_deceased';

export interface HandoverResult {
  childId: string;
  at: string;
  /** Every guardianship edge closes with this reason. */
  closeGuardianshipsWithReason: 'majority';
  /** Artifacts transferred, including the journal (§9.9.2). */
  transferred: { artifacts: number; journalEntries: number };
  exportBundleRequested: true;
  irreversible: true;
}

/**
 * §9.8.4 — at the age of majority the archive transfers to the young adult,
 * guardian read access ends, a full export is generated, and the transition is
 * IRREVERSIBLE.
 *
 * §10.7 — this is also the compliance answer. "Preserved indefinitely" is
 * indefensible under the amended COPPA Rule; "held in custodianship and returned
 * to the data subject at majority, at which point operator retention ends unless
 * the adult elects otherwise" is defensible, and happens to be the emotionally
 * correct answer too.
 */
export function handover(
  child: Child, artifacts: Artifact[], journalCount: number, now: DateTime,
): { ok: true; result: HandoverResult } | { ok: false; reason: HandoverDenial } {
  if (child.handedOverAt) return { ok: false, reason: 'already_handed_over' };
  if (child.deceasedAt) return { ok: false, reason: 'child_deceased' };

  const age = now.diff(DateTime.fromISO(child.birthDate), 'years').years;
  // Strictly on or after the birthday. A handover one day early strips a
  // guardian of access they still legally hold.
  if (age < child.majorityAge) return { ok: false, reason: 'not_yet_of_age' };

  return {
    ok: true,
    result: {
      childId: child.id,
      at: now.toISO()!,
      closeGuardianshipsWithReason: 'majority',
      transferred: {
        artifacts: artifacts.filter(a => a.childId === child.id).length,
        journalEntries: journalCount,
      },
      exportBundleRequested: true,
      irreversible: true,
    },
  };
}

/**
 * After handover a guardian retains NO read access — that is the whole point of
 * §9.8.4, and an exception here would make §2.10 untrue.
 */
export function guardianCanReadAfterHandover(): false { return false; }

/**
 * §9.8.3 — "on this day" is opt-in with a per-era mute. Resurfacing is powerful
 * and dangerous in this population: a memory from before a separation can wound,
 * and the product chose the moment. Prohibition P9.
 */
export function onThisDay(
  all: Artifact[], childId: string, today: DateTime, childZone: string,
  prefs: { enabled: boolean; mutedEras: string[] },
): Artifact[] {
  if (!prefs.enabled) return [];
  const md = today.setZone(childZone).toFormat('MM-dd');
  return all.filter(a => {
    if (a.childId !== childId || !a.preserved) return false;
    // Fail closed, not open: a `null` eraTag (a real, common state for
    // legacy/untagged data — the column is nullable) used to skip this check
    // entirely via the `a.eraTag &&` short-circuit, so untagged material
    // could never be suppressed by ANY era mute a family configured — a
    // real, live P9 gap in exactly the mechanism this comment already
    // claims is the mitigation. Whenever at least one era is muted, an
    // untagged artifact can't be proven to be from an unmuted era, so it's
    // excluded too, the same "can't confirm it's safe, so don't show it"
    // posture the rest of this file already applies.
    if (prefs.mutedEras.length > 0 && (a.eraTag === null || prefs.mutedEras.includes(a.eraTag))) return false;
    const d = DateTime.fromISO(a.capturedAt).setZone(a.capturedTz);
    return d.toFormat('MM-dd') === md && d.year < today.year;
  });
}
