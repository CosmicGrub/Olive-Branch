# design-reference

A committed SNAPSHOT of the prototype's design kit, so CI can regenerate the Flutter design tokens
deterministically (the prototype itself lives outside git).

| file | copied from |
|---|---|
| `kit.js` | `docs/superpowers/mockups/live/kit.js` (the Round 2/3 premium kit, `OB.theme`, icons, spots) |
| `overhaul.css` | `docs/superpowers/mockups/live/overhaul.css` (type scale, radii, spacing, motion, focus ring) |

Do not edit these two files here. The prototype is the reference (`docs/superpowers/parity/PARITY.md`);
change the prototype, then refresh the snapshot.

## Refresh

```sh
cp docs/superpowers/mockups/live/kit.js docs/superpowers/mockups/live/overhaul.css scaffold/tools/design-reference/
cd scaffold && node tools/gen-design-tokens.mjs      # rewrites assets/design/tokens.json + lib/design_tokens_generated.dart
cd client && flutter test test/design_parity_test.dart   # the real theme must still equal the tokens
```

Commit the two snapshot files and both generated outputs together. `tools/test/design_tokens.test.mjs`
(part of `npm test` and `tools/verify.sh`) fails when the generated files are stale, and the generator
refuses to write tokens that fail WCAG AA unless the failure is recorded as a documented adjustment.
