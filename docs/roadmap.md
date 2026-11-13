# Roadmap

Status: Phases 0-4 implemented (Nov 2026); Phase 5 onward not started. Phases are ordered so each one's output is testable against the
capture logs before the next builds on it.

## Phase 0 — scaffold

Create `config.lua`, `build.py`, `src/` stub modules with header contracts,
`test/mudlet_stub.lua`, `.gitignore` (dist/, nothing else).

**Done when**: `python3 build.py` produces `dist/retromud.mpackage`; installing
it in Mudlet loads without errors and `rmap help` responds; `git grep` shows no
global assignments outside the `rm` namespace.

## Phase 1 — capture engine

Implement the block grammar from [output-format.md](output-format.md) in
`30_capture.lua`: line buffer, prompt anchoring (GA/EOR preferred,
settings-held default pattern as fallback; the `rmap prompt` command itself is
Phase 6), exits parsing, fingerprint computation, `rm.onRoom` event.

**Done when**: `run_tests.py` replays all three captures
(`2026-11-01_hagrat_lab_sauronan.log`, `2026-11-13_walk_with_combat.md`,
`2026-111-3_width_80.md`) and every block in them yields the correct
(title, exits list) — including:

- the width-120/width-80 reflow, builder hard-wrapped descriptions with blank
  and tab-indented lines (Tsoda gate), and the weather sentence spilling onto
  a second column-0 line at width 80;
- the mid-line glued weather sentence in the zoo room;
- the ASCII map block and the `show skills` table being ignored;
- block termination via GA/`isPrompt()` live and via the configured prompt
  pattern in replay (captures contain no GA bytes); the pattern is taken from
  settings, not hard-coded, and the default matches the tall, tall-with-gold,
  and short `Hp:  Sp:  Ep:` shapes — the short one is a real prompt (confirmed
  live: GA follows it);
- the module reports "no usable prompt" when neither GA nor the pattern
  matches, instead of never closing a block;
- a `look` mid-combat yielding the right title despite `NEW ROUND` / `--- HP:`
  lines in the buffer, and `look <target>` (no exits line) yielding no room.

## Phase 2 — tracker + builder

Expectation queue (`sysDataSendRequest` classification), sync states,
coordinate-first dedupe, fingerprint matching, ADVANCE decision tree, move-fail
cancellation.

Also: normalise direction abbreviations (`n`, `ne`, `u`, …) to exit names, and
handle freeform exit pairs (`gate` ↔ `leave`) as stub / soft back-link.

**Done when**: fixtures 1, 2, 4, 5, 6 from
[mapper-protocol.md](mapper-protocol.md) pass against replayed capture logs —
`look` after a move creates nothing, failed moves cancel cleanly, a
same-fingerprint revisit links instead of duplicating — plus these new
fixtures (7-10 in mapper-protocol.md):

- repeated `look` in one room (including mid-combat) is a no-op;
- the same room seen with a different weather sentence keeps its fingerprint
  and creates nothing;
- `You can't go that way!` after `s` cancels the expectation (walk capture);
- walking `gate` then back via `leave` creates one room pair, not duplicates.

## Phase 3 — `rmap scan` / `rmap where` / `rmap undo`

Peer-fill algorithm, stub rooms, soft back-links, re-sync procedure, undo.

**Done when**: fixture 3 passes (scan twice = no-op on second run); a scan over
the Sun Gate fixture creates correct stubs with soft back-links; `rmap where`
recovers from a synthetic UNSYNCED state; `rmap undo` removes exactly the last
auto-created room and its link.

## Phase 4 — speedwalk

`doSpeedWalk` contract, confirmed-per-step engine, abort on move-fail.

**Done when**: a scripted path in the stub walks stop-by-stop, halting on an
injected move-fail with position intact.

## Phase 5 — UI + package polish

Geyser layout (mapper pane, status bar, buttons), geometry persistence,
`rmap ui` kill-switch, package icon/version metadata, README install section.

**Done when**: the mpackage installs on a clean profile, the layout renders,
and a first live session on a mortal character maps a small area (Sun Gate
neighborhood) with no manual fixes.

## Phase 6 — deferred

- Offline map generation from `mirrors/` room files (share the fingerprint
  scheme; import via `saveJsonMap`/`loadJsonMap`).
- OTA updates via Mudlet `download_path`.
- `rmap prompt <pat>` command and learn-from-template (read the player's `prompt`
  string, turn tokens into a pattern) for connections that send no GA. GA
  works on both wizard and mortal characters, so until then the pattern is a
  settings-file default only.
- Import of RetroMUD's ASCII virtual `map` output as map seed data.
- `peer`-based pre-creation beyond `rmap scan` (auto-scan on room entry while
  mapping).

## Open capture gaps

Multi-line prompts: no capture has a prompt using `<\n>` (see `help prompt`).
Capture one; the fallback pattern must match the final line.

Prompts from other players: every capture so far is one player's prompt
setting. Collect a few differently-configured prompts before Phase 1 sign-off.
GA was confirmed live on both the `hagrat` wizard character and a mortal
character (Nov 2026).

No capture yet shows a move made **during combat** (fleeing), the case where a
wrong title would create a bad room. Capture one before Phase 2 sign-off.

## Live calibration loop (ongoing)

Every in-game session starts with `rmap debug on` and ends with the log added to
`test/captures/` plus any grammar notes in [output-format.md](output-format.md).
Pattern fixes get a fixture so they stay fixed.
