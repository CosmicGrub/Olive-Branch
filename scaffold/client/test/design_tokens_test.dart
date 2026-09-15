// OLIVE BRANCH — design_tokens.dart tests. docs/superpowers/specs/2026-09-
// 15-design-tokens-named-migration-design.md (UI/UX review theme #4). A
// thin, honest test — this is a constants file, not logic — sanity-checking
// the documented values every migrated call site (see the spec's own Fix
// #1-#4) now depends on.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/design_tokens.dart';

void main() {
  group('AppSpacing — matches the spec\'s own documented scale', () {
    test('xs is 4', () => expect(AppSpacing.xs, 4.0));
    test('sm is 8', () => expect(AppSpacing.sm, 8.0));
    test('md is 12', () => expect(AppSpacing.md, 12.0));
    test('lg is 16', () => expect(AppSpacing.lg, 16.0));
    test('xl is 24', () => expect(AppSpacing.xl, 24.0));
    test('xxl is 32', () => expect(AppSpacing.xxl, 32.0));

    test('strictly ascending — each step really is larger than the last', () {
      const steps = [AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg,
        AppSpacing.xl, AppSpacing.xxl];
      for (int i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]));
      }
    });
  });

  group('AppRadius — matches the spec\'s own documented scale', () {
    test('sm is 8', () => expect(AppRadius.sm, 8.0));
    test('md is 12', () => expect(AppRadius.md, 12.0));
    test('lg is 16', () => expect(AppRadius.lg, 16.0));

    test('strictly ascending — each step really is larger than the last', () {
      const steps = [AppRadius.sm, AppRadius.md, AppRadius.lg];
      for (int i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]));
      }
    });
  });
}
