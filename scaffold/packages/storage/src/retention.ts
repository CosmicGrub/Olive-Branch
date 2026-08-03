/**
 * Retention POLICY. Deliberately separate from `storage.ts`, which carries a
 * `node:crypto` dependency for URL signing.
 *
 * The same reasoning as the ledger's portable SHA-256: a policy module that
 * decides what a family keeps has no business requiring a Node runtime. It has
 * to be evaluable in a browser, in a worker, and in a test — anywhere the
 * question "is this about to be lost?" gets asked.
 */

// ------------------------------------------------- expiry digest (§16.2 #5) --
/**
 * §16.2 #5, SETTLED v0.23.0 — **preservation is a standing rule, not an
 * election.** Anything a parent sends is kept by default.
 *
 * A parent who forgets to tick a box loses the thing forever, and that is
 * unrecoverable. Opt-in preservation optimises for storage cost at the expense
 * of the one thing this product exists to protect.
 *
 * The counterweight, and the reason this is defensible under §10.7: anything
 * NOT covered by the standing rule — a child's incidental capture, a
 * screenshare frame, a call clip — surfaces in a digest **before** it is
 * deleted, with one tap to keep it. Nothing is lost without the guardian having
 * been given the chance to say otherwise.
 */
export const DIGEST_LEAD_DAYS = 14;

export interface ExpiringArtifact {
  artifactId: string;
  kind: string;
  caption: string | null;
  capturedAt: string;
  expiresAt: string;
  daysLeft: number;
}

export interface ExpiryDigest {
  items: ExpiringArtifact[];
  /** Grouped so the digest reads as a list of things, not a list of dates. */
  byKind: { kind: string; count: number }[];
  /** Never shown to the child. See below. */
  audience: 'guardian';
  headline: string;
}

/**
 * Artifacts inside the lead window, soonest first.
 *
 * Preserved artifacts never appear: they have no clock. Anything already past
 * its expiry is excluded too — a digest offering to save something the reaper
 * has already taken would be a lie.
 */
export function expiringSoon(
  artifacts: { id: string; kind: string; caption?: string | null;
    capturedAt: string; preserved: boolean; expiresAt: string | null }[],
  now: Date, leadDays = DIGEST_LEAD_DAYS,
): ExpiryDigest {
  const horizon = now.getTime() + leadDays * 86_400_000;
  const items: ExpiringArtifact[] = artifacts
    .filter(a => !a.preserved && a.expiresAt)
    .map(a => ({ artifactId: a.id, kind: a.kind, caption: a.caption ?? null,
      capturedAt: a.capturedAt, expiresAt: a.expiresAt!,
      daysLeft: Math.ceil((Date.parse(a.expiresAt!) - now.getTime()) / 86_400_000) }))
    .filter(a => a.daysLeft > 0 && Date.parse(a.expiresAt) <= horizon)
    .sort((x, y) => x.daysLeft - y.daysLeft);

  const counts = new Map<string, number>();
  for (const i of items) counts.set(i.kind, (counts.get(i.kind) ?? 0) + 1);

  return { items, audience: 'guardian',
    byKind: [...counts.entries()].map(([kind, count]) => ({ kind, count }))
      .sort((a, b) => b.count - a.count),
    headline: items.length === 0 ? 'Nothing is due to be cleared.'
      : items.length === 1 ? 'One thing will be cleared soon unless you keep it.'
      : `${items.length} things will be cleared soon unless you keep them.` };
}

/**
 * THE RULE: a child is never shown this digest.
 *
 * "These memories are about to be deleted" is a sentence no eight-year-old
 * should read about her own life. The decision is an adult's, and the child
 * experiences only the outcome.
 */
export function digestVisibleTo(role: string): boolean {
  return role !== 'child';
}

/** One tap. Preserving is always allowed and never reversible by the product. */
export function keepForever(
  ids: string[], all: { id: string; preserved: boolean }[],
): { id: string; preserved: true }[] {
  return all.filter(a => ids.includes(a.id) && !a.preserved)
    .map(a => ({ id: a.id, preserved: true as const }));
}

