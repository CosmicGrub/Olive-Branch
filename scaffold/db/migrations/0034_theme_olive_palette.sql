-- ============================================================================
--  OLIVE BRANCH — theme_olive_palette
--
--  The overhaul (docs/superpowers/mockups/overhaul) adds a seventh palette,
--  `olive`, the brand colour, and makes it the app's default. The wire value
--  is the Dart enum's `.name` (client/lib/theme.dart ThemePalette), so the
--  CHECK constraint on child_theme_preference.theme_palette (0017) must admit
--  it, or a guardian choosing Olive in the picker would get a constraint
--  violation instead of a saved preference.
--
--  Only the allowed set widens. Nothing about who may read or write the row
--  changes: RLS is untouched, and the "complete or absent" constraint
--  (palette and brightness set together, or both null) is untouched.
-- ============================================================================

BEGIN;

ALTER TABLE child_theme_preference
  DROP CONSTRAINT child_theme_preference_theme_palette_check;

ALTER TABLE child_theme_preference
  ADD CONSTRAINT child_theme_preference_theme_palette_check CHECK (theme_palette IN
    ('olive','classic','calmModern','warmGrounded','softPlayful','deepCozy','brightBold'));

COMMIT;
