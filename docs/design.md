# Design — retromud-mapper Mudlet package

Status: agreed design (Nov 2026). Phases 0-4 implemented; UI (Phase 5) not started.

## Goals

1. A mapper that runs inline with RetroMUD's output **without false rooms or
   duplicates** — see [mapper-protocol.md](mapper-protocol.md) for the core
   algorithm.
2. A Geyser UI layout (mapper pane, status bar) bundled in the same package.
3. Distribution as a single self-contained `retromud-mapper.mpackage` installable via
   Mudlet's Package Manager.

## Non-goals (deferred)

- Offline map generation from the room mirrors in this repo (the fingerprint
  seam in the map data is reserved for it — see mapper-protocol.md).
- OTA package updates via Mudlet's `download_path` mechanism.
- Importing RetroMUD's ASCII virtual `map` output.

## Package format

Developed as modular Lua in `src/` (numbered prefixes fix the load order).
`build.py`:

1. concatenates `src/*.lua` in filename order into one script body,
2. emits `retromud-mapper.xml` containing a **single `<Script>` element** — no GUI
   triggers, aliases, or timers in the XML,
3. zips `retromud-mapper.xml` + `config.lua` (mpackage manifest) into
   `dist/retromud-mapper.mpackage`,
4. sanity-checks the body (balanced tables/functions; no globals outside the
   `rmap` namespace; version bumped).

Why one self-contained Script element (the same shape as Mudlet's bundled
generic_mapper): no filesystem path dependencies, survives Mudlet's XML
importer round-trip, and exactly one artifact to share. The modularity lives in
this repo, not in the artifact.

## Runtime architecture

- **One global namespace `rmap`.** Nothing leaks into the global Lua environment.
- **No GUI objects in the XML.** On load (`sysLoadEvent` / `sysInstall`) the
  script builds its own `tempRegexTrigger`/`tempAlias` objects from the
  settings table and registers anonymous event handlers. Consequences:
  - patterns are *data*, editable at runtime (`rmap prompt <pat>`, `rmap reload`)
    instead of GUI state;
  - everything is git-reviewable;
  - clean uninstall: `sysUninstallPackage` kills every registered handler and
    temp-object id;
  - the whole state machine is testable offline against a stub of the Mudlet
    globals.
- **Settings persistence**: defaults in code, user overrides merged from a
  `table.save`d file in the profile directory. Per-character prompt/exits
  patterns. Persisted UI geometry.
- **Map persistence**: `saveMap`/`loadMap` (plus `saveJsonMap` for
  human-readable exports). Maps are built by playing, plus one walked seed per
  guild start area (`seeds/<guild>.json`). `build.py` embeds every seed in the
  package as `rmap.seedData` (rooms, exits, stubs, user data) and generates
  `rmap.seedIndex` (start-room fingerprint to seed name; it fails on
  duplicates). `45_seed` merges each seed into the player's map as its own
  area, named for the guild, at package start and again at the first room block
  of a session. A merge adds rooms with fresh ids and never touches or replaces
  a room the player has (`loadJsonMap` replaces the whole map, so it is not
  used); a guild whose area name already exists is skipped. Map user data
  `rmap.merged` lists the merged seeds, so a deleted area stays deleted. An
  empty map at the first merge is a new character: `rmap.welcome` is set to
  pending, and the first room block finds the start room by fingerprint, syncs,
  turns mapping on, opens the map pane and sets the zoom (`seedZoom`, per
  area). Anyone else just resumes mapping. A first room that is in no seed gets
  a room of its own. `46_icons` puts ASCII symbols on service rooms of the
  seeds listed in `rmap.icons.seeds`.
  Character-creation rooms (Character Creation, Race Selection, Guild
  Selection) and the one-time "Welcome to RetroMUD" disclaimers room print
  ordinary room blocks around the first login, often in the same segment as the
  guild room. Capture never raises them (`settings.ignoreRooms`, by
  fingerprint), so neither the seeder nor the tracker sees them.
- **Areas**: each seed has one area named for its primary guild ("Fighter").
  A room created by walking joins the area of the room it was entered from,
  so leaving a seeded guild stays in that area; `rmap area <name>` pins the
  area instead. Free grid cells are looked up in the area the new room joins.
- **Mapping on/off**: mapping turns on by itself (seeded, fresh, or resumed for a
  returning player's existing map at the first room of a session). The player's
  explicit `rmap start` / `rmap stop` is stored in the map's user data
  (`rmap.mapping` = on|off) and an `off` is honoured next session; unset means on.
  At the first room of a session `45_seed` also clears the tracker's queue:
  whatever was typed before it (creation, login, registration) cannot relate to
  the map and would otherwise claim the next room block.

## Module layout and contracts

| Module | Contract |
|---|---|
| `10_rmap` | namespace table, version, lifecycle: load/install builds triggers+UI, uninstall tears them down; event wiring |
| `20_settings` | defaults + merge/load/save of user overrides; per-character patterns; no behavior |
| `30_capture` | line buffer → room-block detection (grammar in [output-format.md](output-format.md)); emits internal `rmap.onRoom {name, exits, lines, fingerprint}`; knows nothing about the map |
| `40_tracker` | the expectation queue (`sysDataSendRequest` → classified expectations), sync state (SYNCED / UNSYNCED / PENDING), resolution of blocks against expectations; decides advance/verify/preview — never writes the graph |
| `50_builder` | the **only** module that writes the map graph: fingerprint matching, coordinate-first dedupe, room/area/exits creation, stub semantics, special exits, merge/undo support |
| `60_speedwalk` | `doSpeedWalk()` contract (reads `speedWalkDir`/`speedWalkPath`), confirmed-per-step engine (send → wait for resolved block), abort on move-fail |
| `70_ui` | Geyser container, `Geyser.Mapper` pane, status label, buttons; geometry persisted; `rmap ui off` kill-switch |
| `80_commands` | all aliases: `rmap start/stop`, `rmap goto <room>`, `rmap path`, `rmap where`, `rmap scan`, `rmap undo`, `rmap fix`, `rmap save/load`, `rmap prompt/exits/fail <pat>` (`rmap prompt` deferred to Phase 6), `rmap debug`, `rmap ui`, `rmap reload`, `rmap help` |

Module boundaries are the test contract: capture produces room events without
knowing the map exists; tracker owns intent; builder owns the graph; ui and
commands are pure consumers.

## Testing strategy

- `test/mudlet_stub.lua` fakes the Mudlet globals (`send`, `echo`, `raiseEvent`,
  the mapper API, the event registry) and records calls.
- `test/run_tests.py` loads the stitched module body against the stub and
  replays capture logs line-by-line, asserting graph state. Python-driven to
  match the existing `tools/exit_analyzer` culture.
- Fixtures are the scenarios from [mapper-protocol.md](mapper-protocol.md)
  (look-after-move, failed move, scan-twice, non-Euclidean revisit, …) built
  from real capture logs.

## Compatibility

- Target Mudlet 4.17+ (parity with the bundled generic_mapper's baseline).
- Maps are built on a **mortal** character; wizard-side room display differs
  and would calibrate the patterns wrong.
