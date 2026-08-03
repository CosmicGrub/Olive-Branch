/**
 * MASTERFILE §8.9 — two languages in one family.
 *
 * A US-only product (§1), in a country where roughly one household in five speaks
 * a language other than English at home. The common case is not "the app is in
 * Spanish" — it is **a child in English and a grandmother in Spanish**, in the
 * same family, at the same time.
 *
 * So language is a property of a PERSON, not of the app.
 */

export type Lang = 'en' | 'es' | 'zh' | 'tl' | 'vi' | 'ar' | 'fr' | 'ko' | 'ru' | 'pt';

export const LANGS: { code: Lang; name: string; endonym: string; rtl: boolean }[] = [
  { code: 'en', name: 'English',    endonym: 'English',    rtl: false },
  { code: 'es', name: 'Spanish',    endonym: 'Espanol',    rtl: false },
  { code: 'zh', name: 'Chinese',    endonym: '\u4e2d\u6587', rtl: false },
  { code: 'tl', name: 'Tagalog',    endonym: 'Tagalog',    rtl: false },
  { code: 'vi', name: 'Vietnamese', endonym: 'Tieng Viet', rtl: false },
  { code: 'ar', name: 'Arabic',     endonym: '\u0627\u0644\u0639\u0631\u0628\u064a\u0629', rtl: true },
  { code: 'fr', name: 'French',     endonym: 'Francais',   rtl: false },
  { code: 'ko', name: 'Korean',     endonym: '\ud55c\uad6d\uc5b4', rtl: false },
  { code: 'ru', name: 'Russian',    endonym: '\u0420\u0443\u0441\u0441\u043a\u0438\u0439', rtl: false },
  { code: 'pt', name: 'Portuguese', endonym: 'Portugues',  rtl: false },
];

export const isRtl = (l: Lang) => {
  const e = LANGS.find(x => x.code === l);
  return e ? e.rtl : false;
};

export interface LangPrefs { userId: string; lang: Lang }

export function langFor(prefs: LangPrefs[], userId: string, fallback: Lang = 'en'): Lang {
  const p = prefs.find(x => x.userId === userId);
  return p ? p.lang : fallback;
}

/**
 * §8.9.1 — translating what a person WROTE.
 *
 * The rule: **the original is always shown, and it is shown first.** A
 * translation sits underneath, marked as machine-produced, and never replaces the
 * words a parent chose.
 *
 * That is not politeness. In a co-parenting context a translated message can end
 * up in front of a judge, and a paraphrase presented as a quotation is a
 * fabricated exhibit.
 */
export interface Translated {
  original: string;
  originalLang: Lang;
  translation: string | null;
  targetLang: Lang;
  machine: true;
  disclaimer: string;
  storedInLog: 'original_only';
}

export function present(
  original: string, from: Lang, to: Lang, translation: string | null,
): Translated {
  return { original, originalLang: from, targetLang: to,
    translation: from === to ? null : translation, machine: true,
    disclaimer: 'Machine translation. The original is above.',
    storedInLog: 'original_only' };
}

/** §13 — a court export carries the original. Never the translation. */
export function forCourtLog(t: Translated): { text: string; lang: Lang } {
  return { text: t.original, lang: t.originalLang };
}

/**
 * §8.9.2 — what is NEVER machine-translated.
 *
 * A child's own words are hers. Running a five-year-old's caption through a
 * translator and showing the result to her father as if she said it is putting
 * words in her mouth — and the error rate on a small child's grammar is high
 * enough that it will sometimes be badly wrong.
 */
export const NEVER_TRANSLATED = [
  'child_journal', 'child_caption', 'child_message', 'child_voice_transcript',
  'story_refrain', 'her_name', 'care_note', 'legal_clause',
] as const;

export function mayTranslate(kind: string): boolean {
  return !(NEVER_TRANSLATED as readonly string[]).includes(kind);
}

/** Interface copy is a different matter — that is ours, and it is translated. */
export const UI_TRANSLATABLE = true;
