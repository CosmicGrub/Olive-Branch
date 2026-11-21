# Plain-words release notes (what a grown-up reads before tapping "Download")

One file per published version: `docs/release-notes/<version>.txt`, for example `0.52.0.txt`. It is the text the signed update
manifest carries (`headline` and `notes`) and the only thing the app shows an adult about an update. The CHANGELOG is written for the
people who build the app; this is written for a parent on a phone, once, deciding whether to update.

Start from the CHANGELOG, then rewrite:

```bash
cd scaffold
node tools/update/draft-release-notes.mjs 0.52.0     # writes docs/release-notes/0.52.0.txt, stamped DRAFT, never over an existing file
```

## Format

```
# a line starting with # is a note to the writer and is ignored
headline: One calm sentence, at most 100 characters.
- One thing a grown-up would notice, in plain words. At most 300 characters.
- At most 12 of these.
```

## Rules for the words

- **What changes for them**, not what changed in the code. "Fewer taps to reach a saved message", not "refactored the inbox route".
- Calm, honest, adult words. No exclamation marks, no urgency, no "critical". If an update fixes something that matters, say what and
  why plainly.
- Never mention a child by name, a device, an address or anything about a family. The file is public.
- Plain text only: no angle brackets, no backticks, no markup, no links. It is shown as text and never rendered.
- If the update is required (the minimum supported version was raised), say so in one honest sentence.

## The DRAFT line

The drafting tool puts a `# DRAFT` paragraph at the top. `tools/update/build-update-package.mjs` **refuses** a file that still has it,
so a machine's first guess can never go out under the owner's signature. Rewrite every line, then delete that paragraph.
