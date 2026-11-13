# RetroMUD output format — normative spec

Status: derived from the files in `test/captures/` (Nov 2026):
`2026-11-01_hagrat_lab_sauronan.log`, `2026-11-13_walk_with_combat.md`,
`2026-111-3_width_80.md`. The capture corpus is ground truth; this document is the patterns
the capture module implements. New captures extend it, never contradict it
without a note here.

## Width independence

Output wraps at the player's `width` setting (captures show 120 and 80). No
pattern may depend on columns, line counts, or where wrapping falls — only on
the block grammar below. Wrapping is also mixed within one block: many
descriptions are hard-wrapped by the builder at about 72 columns (and may
contain blank lines and tab-indented lines, e.g. the Tsoda gate banner), while
the light/weather sentence reflows at the terminal width. At width 80 the
weather sentence can spill onto a second line at column 0.

## Room block anatomy

Everything between two prompt lines, in order. The block ends **only at a
prompt** (blank lines and other-player chatter never terminate it):

1. **Noise lines** (optional, from the move or other players):
   `You are flying.`, `<Name> starts using ...`. These are config ignore
   patterns and may appear anywhere in the block.
2. **Room title**: the non-noise line **immediately above the first
   two-space-indented line** (see Anchoring below). May or may not end with a
   period. Never "the first line at column 0": in combat the buffer holds
   round output at column 0 (`--- HP:…`, `You hit … (5)`) that would qualify.
3. **Description**: first line indented exactly two spaces (`^  %S`),
   continuation lines at column 0, wrapped at the builder's or terminal's
   width. Blank lines and tab-indented lines may occur inside it.
4. **Light/weather sentence**: usually its own line starting with a single
   space (one space, not two — do not confuse with the description), but **can flow mid-line glued to the description** (zoo room in the
   capture). Wording varies with lighting (`It is dark and shadowy here.` vs
   `It is dimly lit here.`) and **changes between visits to the same room**
   (`The sky is overcast with dark clouds.` vs `The sky is black and the stars
   shine down brightly. It is the night of the new moon.`). Never used for
   anchoring, and nothing from the description may enter the fingerprint.
5. **Exits sentence — the capture anchor**; see grammar below.
6. **Object/living lines** (`A trading post`, `A smiling trader`): come *after*
   the exits line — the exits line does **not** end the block.
7. **Prompt** (GA-terminated; format is player-configurable — see Prompt patterns).

### Description start and title (corpus of 13 logs)

The description's first line is indented 2 spaces in most rooms, but
builders also use 4, 10, or a whitespace-only line; later paragraphs can
start with 2 spaces too, and boxes/lists inside a description are indented
deeper. Rule (`findTitle`): candidates are exactly-2-space lines first,
then 3+ spaces, then (description-less rooms) the single-space light line.
Walking up from the exits line, the first candidate whose non-indented,
non-noise predecessor is title-like wins. Title-like = not lowercase-first,
not ending in `:`, not starting with a symbol. Titles are right-trimmed.
A `% Connected to` line clears the buffer (login art).

### Anchoring (finding the title)

Because combat produces many lines with no prompt between them, a block's
buffer can hold dozens of unrelated lines before the room starts. Do not scan
forward for a title. Instead, once the exits line is seen:

1. walk back from the exits line to the first line matching `^  %S`
   (two-space indent) that begins the description;
2. the title is the nearest preceding non-noise line;
3. if no such pair exists, the block is not a room (e.g. `look <target>` output
   has no exits line at all) — emit nothing.

Combat output can interleave inside a room block (a round lands between the
title and the description). Default ignore patterns therefore include
`^ %*%*%* NEW ROUND %*%*%*`, `^%-%-%- HP:`, and the attack-result lines; if the
resulting title still disagrees with the fingerprint the tracker expects, it
goes UNSYNCED rather than creating a room.

## Prompt patterns

**RetroMUD sends GA/EOR after every prompt** (verified live in Mudlet on
a wizard and a mortal character: `isPrompt()` returns true on the tall and
the short prompt lines). GA is
the block terminator; the prompt text is not parsed to find block boundaries.

The prompt is also **player-customizable** and can take a wide variety of
formats, so the text pattern is only a fallback and an offline-test aid. The
MUD's `help prompt` shows why: a prompt is a template of free text plus tokens
(`<hp> <sp> <ep> <php> <psp> <pep> <exp> <cash> <bank> <align> <ability>
<domain> <cap> <pcap> <wgt> <rwgt> <wielded> <voted> <hunger> <cmd>`, and
`[cwd]` for wizards), so `prompt RetroMud >` is valid and need not contain
`Hp:` at all. `$` in the template becomes a space. The token `<\n>` is a line
break, so **a prompt can span several lines**.
Resolution order:

1. **GA/EOR** (`isPrompt()`). Format-independent; the live default.
2. **Per-character prompt pattern** from settings (`rmap prompt <pat>`), for a
   connection that sends no GA (Mudlet shows `<No GA>`).
3. **Shipped default** below, a calibration default matching the shapes seen.

Offline replay of the capture files has no GA bytes, so `run_tests.py` always
uses the pattern path; the live path is checked by hand in Mudlet.

The mapper must say so plainly when it has no usable prompt (no GA, and the
pattern never matched) rather than silently never closing a block.

Shapes seen in the captures (one player's settings, not an exhaustive set).
All three are GA-terminated prompts:

- `Hp:3127/3127 Sp:988/988 Ep:2070/2120 Exp:1384189 >` — tall; follows a typed
  command.
- `Hp: 296/296 Sp: 102/102 Ep: 74/74 Gold: 0 Exp: 48 >` — tall with gold.
- `Hp: 3127/3127  Sp: 988/988  Ep: 2120/2120` — short (double-spaced, no `>`).
  Sent unprompted after heal/recovery messages (`You feel fully healed.`) and
  between an echoed command and its output (`>peer away`, then this line, then
  `You peer away.`). Confirmed a real prompt (GA follows), so it **does** end
  a segment. Earlier drafts of this spec called it a status refresh; that was
  wrong.

Multi-line prompts: GA follows the **last** line of the prompt, so
`isPrompt()` is true only there; the earlier lines arrive as ordinary-looking
lines at the end of the preceding block. They never matter to the room
grammar (only the exits line anchors), but a fallback pattern must match the
prompt's **final** line, not its first. The mapper-protocol assumption that
the echoed command rides on the prompt line should be re-checked: the `<cmd>`
token suggests the echo may appear only for prompts that include it.

Properties that hold regardless of format:

- A block is the text between two prompts. Because short prompts arrive
  asynchronously, one could in principle land mid-block and split it; none seen
  in the captures.
- The prompt often carries the typed command appended
  (`... Exp:1384189 >arena`), so anchor at line start, never line end.
- In combat the typed command may instead appear alone on its own line
  (`look`); never infer what was sent from echoes — the tracker uses
  `sysDataSendRequest`.

Default pattern (fallback; calibrated on this one player's prompt, matches
the three shapes above, not end-anchored; a player with another template sets
their own with `rmap prompt`):

```lua
"^[%w ]*:? *Hp:%s*%d+/%d+%s+Sp:%s*%-?%d+/%d+%s+Ep:%s*%d+/%d+"
```

The optional prefix covers `EQ Tick: Hp: ...`; Sp can go negative.

Combat round lines use uppercase `--- HP:` and never match it.

## Combat output

No prompt separates combat rounds; the prompt appears only after the player
types something. Round structure:

```
 *** NEW ROUND ***
--- HP:296/296  SP:102/102  EP:74/74
You hit Tummyache once. (5)
Tummyache fails to hit you.
```

Note the uppercase `HP:`/`SP:`/`EP:` (never matches the `^Hp:` prompt) and the
single leading space on the `NEW ROUND` line. Also seen: `You attack …`,
`X is DEAD, R.I.P.`, `You can act again.`, and the weather-change message
`The clouds begin to break apart and the sky shows through.`. All are noise;
none may be used as a block boundary.

## Exits grammar (the anchor)

Three forms seen (the third has no names):

- None: `There are no obvious exits.` — empty exit list (`An endless descent`).

- Multi: `Obvious exits are: a, b, and c.` — wraps across lines, comma
  separated, final `and`, always ends with a period.
- Solo: `The only obvious exit is x.`

Parse algorithm: match the start pattern; join continuation lines until a line
ending in a period; strip the trailing period; split on `,`; strip the leading
`and ` from the last name; lowercase everything. Names may contain underscores
(`poor_house`, `magic_college`).

Exit names are **freeform** — `sungate`, `clubhouse`, `away`, `zoo`, `gate`,
`leave` appear alongside cardinals (`north`, `southwest`, `up`). A freeform
exit's return is usually another freeform name (`gate` ↔ `leave`); it cannot
be inferred, so the reverse is a stub / soft back-link. Cardinal names drive
coordinates; everything else is a special exit keyed by the command that
triggers it (see [mapper-protocol.md](mapper-protocol.md)).

Lua patterns:

```lua
"^Obvious exits are:%s+(.*)"
"^The only obvious exit is%s+(%S-)%.?%s*$"
```

## Structures to ignore

- **ASCII virtual map** (the `map` command): lines of backtick/pipe/dot art,
  footer `Type 'map legend' to view the legend for this map.` — never feed to
  the room matcher. Future import source, not live-tracker input.
- **Command echo lines**: the prompt may carry the typed command
  (`... >look`); anchor patterns at line start, never at line end.
- **Tables and boxes**: `show skills` and similar print `.---`/`|` art that
  looks like the `map` output; ignored for the same reason (no exits line).
- **Room-adjacent chatter** before the prompt: `Brown tooth arrives from the
  northeast.`, `Sick girl pukes on you.`. Noise; only the exits line anchors.
- **System chatter between prompts**: `Variable updated: WIDTH : 80`,
  `You sizzle with magical energy.`, `You feel fully recovered.`,
  `[info] Hagrat recovers from linkdeath` — prompt-anchored capture skips
  them naturally; they must never satisfy a block.
- **peer output**: a full neighbor block (title, description, weather, exits;
  no object/living lines) preceded by the ack `You peer x.` — consumed by the
  tracker as PREVIEW, never by the builder as creation.

## Move commands and failures

Players type abbreviations (`n`, `s`, `e`, `w`, `ne`, `nw`, `se`, `sw`, `u`,
`d`) as well as full names and freeform exits (`gate`, `up`); the tracker
normalises abbreviations to the exit names before matching expectations.
Failed move: `You can't go that way!` (prompt follows immediately; nothing
else changes).

## Per-block metadata for the tracker

Capture emits with every block: title, exits list (parsed), raw lines,
fingerprint (title + sorted exits), and which expectation (if any) was
resolved by it — the tracker owns that last part, capture only reports.
