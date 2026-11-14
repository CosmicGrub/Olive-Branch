// The ten synthetic families. Synthetic names only; no real data. Ages are spread
// across the four age bands the app uses (t34 / t57 / t812 / t1317). Ids are
// deterministic so a run is reproducible and cleanup is exact.
import { sid, KIND } from './util.mjs';

export const NS = '51a00000';   // every simulator id starts with this: "olive sim"

export function bandOf(age) {
  return age <= 4 ? 't34' : age <= 7 ? 't57' : age <= 12 ? 't812' : 't1317';
}

const TEMPLATES = [
  { name: 'The Marlowes',       tz: 'America/New_York',    guardians: ['Rowan Marlowe', 'Sage Marlowe'],   kids: [['Pip', 4], ['Juno', 9]] },
  { name: 'Okafor-Reyes',       tz: 'America/Chicago',     guardians: ['Ada Okafor', 'Leo Reyes'],         kids: [['Wren', 6]] },
  { name: 'The Lindqvists',     tz: 'Europe/Stockholm',    guardians: ['Maja Lindqvist'],                  kids: [['Fia', 3], ['Ove', 5], ['Elin', 8]], single: true },
  { name: 'Tanaka-Brooks',      tz: 'America/Los_Angeles', guardians: ['Kei Tanaka', 'Dana Brooks'],       kids: [['Moss', 11], ['Indy', 15]], custody: true },
  { name: 'The Haddads',        tz: 'Asia/Dubai',          guardians: ['Layla Haddad', 'Omar Haddad'],     kids: [['Nour', 16]] },
  { name: 'The Petrovs',        tz: 'Europe/Sofia',        guardians: ['Irina Petrov'],                    kids: [['Misha', 7]], single: true },
  { name: 'Alvarez-Whitfield',  tz: 'America/Denver',      guardians: ['Sol Alvarez', 'Jo Whitfield'],     kids: [['Bea', 5], ['Cal', 12]], sitter: 'Pat Sitter' },
  { name: 'The Nkemelus',       tz: 'Africa/Lagos',        guardians: ['Chidi Nkemelu', 'Ngozi Nkemelu'],  kids: [['Ife', 13], ['Zuri', 17], ['Tobe', 4]] },
  { name: 'The Sorensens',      tz: 'Pacific/Auckland',    guardians: ['Birk Sorensen', 'Tove Sorensen'],  kids: [['Lark', 8]] },
  { name: 'Yamamoto-Clarke',    tz: 'Asia/Tokyo',          guardians: ['Hana Yamamoto', 'Sam Clarke'],     kids: [['Kit', 3], ['Rei', 10]], custody: true },
];

export function buildFamilies(n = 10, { today = new Date() } = {}) {
  const fams = [];
  for (let i = 0; i < n; i++) {
    const t = TEMPLATES[i % TEMPLATES.length];
    const wrap = Math.floor(i / TEMPLATES.length);
    const f = i + 1;
    const guardians = t.guardians.map((name, k) => ({
      id: sid(NS, f, KIND.guardian, k + 1), name: wrap ? `${name} ${wrap + 1}` : name, pin: String(135700 + f * 11 + k) }));
    const kids = t.kids.map(([name, age], k) => {
      const d = new Date(today.getTime() - (age * 365.25 + 40 + k * 17) * 86400000);
      return { id: sid(NS, f, KIND.child, k + 1), name: wrap ? `${name} ${wrap + 1}` : name, age, band: bandOf(age),
               birthDate: d.toISOString().slice(0, 10) };
    });
    fams.push({
      index: i, n: f, name: wrap ? `${t.name} ${wrap + 1}` : t.name, tz: t.tz, guardians, kids,
      single: !!t.single, custody: !!t.custody, sitter: t.sitter ?? null,
      medicationId: sid(NS, f, KIND.medication, 1), bagItemId: sid(NS, f, KIND.bag, 1),
      sitterEmail: t.sitter ? `sim-sitter-${f}-${Date.now().toString(36)}@olive-sim.invalid` : null,
    });
  }
  return fams;
}

export const allUserIds = (fams) => fams.flatMap((f) => f.guardians.map((g) => g.id));
export const allChildIds = (fams) => fams.flatMap((f) => f.kids.map((k) => k.id));
