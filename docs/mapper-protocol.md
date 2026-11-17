# Mapper protocol — idempotent room detection

Status: agreed design (Nov 2026).

## The rule: output never speaks for itself

Every block of room-shaped output is interpreted **only in the context of the
last command the client sent**. This is the fix for the classic inline-mapper
failure where `look` re-triggers mapping: `look` is an expectation the tracker
already knows about, so its output can only confirm or invalidate position.

The tracker maintains a FIFO **expectation queue**. `sysDataSendRequest` pushes
one expectation per sent command; each completed room block pops the head and
resolves it.

## Command classification

| Sent command | Expectation | A room block may… |
|---|---|---|
| `look`, `glance` | VERIFY | confirm or invalidate position — **never create** |
| `peer <x>`, `scry`, other preview verbs | PREVIEW | attach to a neighbor or be ignored — **never create** |
| cardinal direction (`n`, `sw`, `up`…) | ADVANCE | move into the expected neighbor, or create (the only automatic creation) |
| anything else | MAYBE_MOVE | become a special-exit transition only if the block fingerprint ≠ current room; otherwise treat as VERIFY |
| (nothing pending) | SPONTANEOUS | invalidate position → UNSYNCED — **never create**; except the room we are already in (the game redisplays it, e.g. after registration), which changes nothing |

The preview-verb list (`peer`, `scry`, …) is configuration, extended during
calibration as more room-showing commands are discovered.

Each expectation resolves on the command's ack line (e.g. `You peer x.`), the
resulting room block, or a timeout — a failed/silent command can never stall
the queue.

### Outgoing-command capture (verified against Mudlet docs)

The sole capture point is the `sysDataSendRequest` event. Verified contract:

- Raised **right before** a command from `send()`, `sendAll()`, or the command
  line is sent to the game; handlers receive `(event, command_string)`.
- One event per actual send (`sendAll` fires per item, which is why Mudlet's
  own docs warn about re-sent commands from inside the handler).
- Fires for **both user-typed and script-issued** sends — including our own
  speedwalk and `rmap scan` sends. That is required, not a hazard: every real
  movement must produce exactly one expectation regardless of who typed it.
- `denyCurrentSend()` may block the send from inside the handler. The mapper
  never blocks player input; it is a pure observer.

Defensive rules the handler must implement (documented behavior is silent on
these):

1. Ignore empty / whitespace-only commands.
2. Treat any embedded newline in a sent string as separate commands — one
   expectation per line, never one expectation for a multi-line send.
3. **The `sysDataSendRequest` handler is the only code path that pushes
   expectations.** Internal engines (speedwalk, `rmap scan`) must never push
   directly, or their own `send()`s would double-count.
4. Never move the player via `sendSocket()` or other exotic paths — those are
   not documented to raise the event, and an untracked move is exactly the
   SPONTANEOUS state we design against.
5. The prompt line may carry the typed command (e.g. `... >arena`); the prompt
   template's `<cmd>` token suggests this happens only for players whose prompt
   includes it, so never rely on the echo — the expectation queue comes from
   `sysDataSendRequest`. When present, capture treats prompt+echo as the
   terminator line, never as room data.

## Sync states

- **SYNCED(roomID)** — we believe we are in this room.
- **PENDING(command)** — a command is in flight; blocks resolve it.
- **UNSYNCED** — position unknown (spontaneous block, verify mismatch,
  linkdeath, summon). We never guess. `rmap where` recovers.

Move-fail messages cancel the head expectation. Nothing is created on *send*,
so a failed move can never leave a phantom room behind.

**Golden rule: rooms are created only from ADVANCE, from a resolved
MAYBE_MOVE, or explicitly by `rmap where`.** Look, peer, and spontaneous output
can confirm, preview, or invalidate — never create.

## Room identity: fingerprints over graph truth

Every observed block yields a **fingerprint**: room name + sorted exits set.
Both are terminal-width-independent and available in every context (walked,
looked, peered). Fingerprints persist via `setRoomUserData` and are what all
matching compares.

Coordinates are a **rendering hint, not identity**. The graph is truth. The
ADVANCE decision tree:

1. Expected neighbor exists at current position + direction delta → walk into
   it.
2. No expected neighbor, but a room within `max_search_distance` in the area
   has the same fingerprint → non-Euclidean link (winding cave, portal loop):
   `setExit` to the existing room and move there.
3. Neither → create.

Two rooms with identical name *and* identical exits are indistinguishable from
inside; the residual ambiguity is resolved by coordinates when walking, by
peer previews when it matters, and by `rmap fix` (merge) when it slips through.

## Repair commands

- `rmap where` — re-sync from UNSYNCED: `look`, fingerprint-search the map;
  unique match → SYNCED; ambiguous → peer-disambiguate from the candidates;
  no match → report honestly, create nothing (unless mapping is on: explicit
  orphan creation).
- `rmap undo` — delete the last auto-created room and unlink it. Every automatic
  mistake must be a one-keystroke fix.
- `rmap fix` — merge two rooms (rewires exits), for duplicates that escaped the
  decision tree.

## `rmap scan` — peer-fill neighbors from a standing position

`peer <exit>` returns the neighbor's full room block (title, exits; no
object/living lines) **without moving**, so a room can be characterized
without entering it. `rmap scan` exploits this:

1. **Sync first**: if UNSYNCED, run the `rmap where` procedure; abort on failure.
2. `look` once; take the current room's exits list.
3. For each exit: **if a link with that command already exists and its target
   is not a stub, skip it.** Re-running scan after months of play is a no-op —
   this is the idempotency contract.
4. Otherwise `peer <exit>` (one at a time) and fingerprint the preview block:
   - matches an existing room → link to it (upgrade a stub to real);
   - no match → create a **stub room**: name, its exits as `setExitStub`s,
     fingerprint, `source=peer` user data; coordinates = cardinal delta if the
     exit was cardinal, else the nearest free cell beside the current room.
5. The preview block also lists the neighbor's exit back toward us — create
   that back-link as a **soft stub only** (one-way doors exist; a listed exit
   is a promise the game has not kept yet). Soft links harden on first real
   traversal.

Exploration order stops mattering: scan maps a hub's whole frontier as
verified-name/unverified-link stubs, and walking later only confirms and
upgrades.

## Residual risks (calibration checklist)

- Room-showing commands beyond the preview list (scrying, crystal balls) →
  extend PREVIEW config.
- Game-forced movement (drag, summon, recall) arrives as SPONTANEOUS →
  UNSYNCED → next `look` heals.
  A forced move between twin rooms (same fingerprint) is not noticed.
- Following other players: the game sends moves the client did not. Scan and
  speedwalk must refuse to run while a follow is active.
- LP-driver command ordering is assumed strictly per-command; per-expectation
  timeouts protect against violations regardless.

## Test fixtures (from real captures)

1. `look` after a move → verifies, creates nothing.
2. Failed move ("You can't go that way") → expectation cancelled, no room.
3. `rmap scan` run twice → second run creates nothing.
4. Walk a loop back into a same-fingerprint room → link, no duplicate.
5. Spontaneous block (linkdeath recovery) → UNSYNCED, no creation.
6. `peer` preview → neighbor identified, no position change.
7. Repeated `look` in one room, including mid-combat → no-op.
8. Same room, different weather sentence → same fingerprint, nothing created.
9. `You can't go that way!` after `s` → expectation cancelled (walk capture).
10. `gate` then back via `leave` → one room pair, no duplicates.

## Implementation decisions

- An ADVANCE expectation is closed only by its room block, a move-fail line
  or the timeout; unrelated output before it (async chatter) never closes it.
- Step 2 of the decision tree skips the room already linked behind us, so a
  corridor of identical rooms is not folded back onto itself.

- The way back to a newly created room is linked from its exits line alone
  and flagged in room user data `bl`. If a real step along it lands in a
  different room (one-way currents), the link is dropped and corrected
  instead of going UNSYNCED; a link confirmed by a walk is never replaced.
