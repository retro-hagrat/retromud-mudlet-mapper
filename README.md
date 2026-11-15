# Mudlet mapping package for RetroMUD

A shareable Mudlet package providing a trigger-based auto-mapper for RetroMUD (www.retromud.org).

RetroMUD does not support GMCP, so all room detection is text-trigger based.
The package is being developed in this repository as readable, testable Lua and
built into one self-contained `.mpackage` for distribution.

## Install

1. Get `retromud.mpackage`: download it from the [releases page](https://github.com/retro-hagrat/retromud-mudlet-mapper/releases) or from the `dist` directory of this repo
2. In Mudlet (4.17 or newer), open **Toolbox → Package Manager** (`Alt+O`), click **Install**, and pick `retromud.mpackage`. Or run `lua installPackage("/full/path/to/retromud.mpackage")` in the command line.
3. Connect to RetroMUD (retromud.org) with a **mortal** character; wizard room display differs and will not map correctly.
4. Type `rmap start` to begin mapping, then walk around. Type `rmap help` for the command list.

Useful first commands: `rmap where` re-syncs your position, `rmap scan` maps every exit of the current room, `rmap undo` removes the last auto-created room.

To update, uninstall the old `retromud` package in the Package Manager, then install the new file.

## Documentation

| Doc | Contents |
|---|---|
| [docs/design.md](docs/design.md) | Package format, runtime architecture, module layout and contracts, testing strategy |
| [docs/mapper-protocol.md](docs/mapper-protocol.md) | The mapper's core algorithm: expectation queue, room identity/fingerprints, creation rules, `rmap scan`/`rmap where`/`rmap undo`, idempotency guarantees |
| [docs/output-format.md](docs/output-format.md) | Normative spec of RetroMUD's room-block output grammar and the patterns derived from it |
| [docs/roadmap.md](docs/roadmap.md) | Build phases with acceptance criteria |
| [test/captures/README.md](test/captures/README.md) | Raw session logs (calibration corpus) and conventions |

## License

[MIT](LICENSE).
