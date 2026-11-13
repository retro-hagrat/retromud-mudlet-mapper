# Raw captures

Verbatim RetroMUD session logs used to calibrate the mapper's text patterns and
to regression-test the capture state machine offline.

Rules:

- Never annotate or edit a capture after saving — tests replay these files
  byte-for-byte.
- Findings and grammar notes go in the normative spec,
  [../../docs/output-format.md](../../docs/output-format.md), not here.
- Naming: `YYYY-MM-DD_<where>.log`
- Capture with the mapper's debug logging (`rmap debug on`) once it exists; until
  then, paste verbatim from the client.

## Files

- `2026-11-01_hagrat_lab_sauronan.log` — first capture. Demonstrates: hagrat's
  lab at width 120 and 80 (wrap reflow), move to Sauronan Sun Gate via
  freeform exit `sungate`, arena and zoo rooms, `The only obvious exit is`
  solo grammar, ASCII virtual `map` output, `peer away` neighbor preview,
  noise lines between move and room (`You are flying.`, `Trader starts
  using ...`), both prompt variants (tall with `Exp:` and `>`, short spaced
  without), object/living lines after the exits line, mid-line glued weather
  sentence in the zoo room.
