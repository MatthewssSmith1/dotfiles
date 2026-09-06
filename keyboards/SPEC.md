# Intended Keyboard Specification

**Intended configuration, not a live-state report.** This specification and
[offline reference](reference.html) describe the checked-in native targets, not
the configurations currently stored in a device or loaded by keyd. Review-required
choices below must be accepted or changed before a separate explicit apply.
Toucan choices were approved and applied for testing; see [the live record](toucan/LIVE-TEST.md).
Air60's distinct modes and switch swap were approved and applied for testing;
see [its live record](air60/LIVE-TEST.md).
US HID legends assume a US host layout; shifted usages are not Unicode injection.

## Sources And Ownership

| Target | Native authority | Remap owner after verified migration |
| --- | --- | --- |
| Toucan | `toucan/keymap.json`, captured `snapshots/toucan/snapshot.json` geometry | ZMK firmware; explicit keyd pass-through |
| Air60 Enhanced / Plain | `air60/layout.json`, `snapshots/air60/via-definition.json` geometry | VIA firmware in both switch positions; explicit keyd pass-through |
| Generic | `keyd/default.conf`, `home-row-mods`, `shared-layers` | keyd wildcard profile |

Maintain native files, this document and HTML together. No universal generation
schema, network, build, server, firmware flashing or implicit application is
required. Backend READMEs specify protocol and recovery limits. `dotfiles.sh`
must not install keyboard settings, reload keyd or write `/etc`.

keyd retains original device profiles until a target has persisted readback
matching the intended firmware keymap (with hash/date/record) and identity
evidence for each used transport. Explicit migration then starts **test
pass-through**, removing duplicate host processing before physical tests.
Readback is not behavioral verification. Complete typing, rolls, modifiers,
layers, operators and reconnect tests with a fallback keyboard; test both Air60
modes. Record results, date, transports and firmware/profile hashes separately.
Failed tests are not completed migration: stop rollout and review coordinated
firmware/host recovery, rather than blindly restoring overlapping host remaps.
Unused transports must remain explicitly disconnected. File-level `verify`
does not certify physical test completion.

Toucan USB selector is `k:1d50:615e:982e9afd`; Air60 known
selectors are `k:19f5:3255:0d7157bb` and `k:19f5:3246:838051e9`.
Toucan Bluetooth selector `k:1d50:615e:b1063934` was confirmed during live testing;
Air60 receiver coverage remains unverified. Transport identities must be
observed, not inferred. Unknown transports must not silently
receive generic remaps. Both Air60 switch positions need migration testing.

## Reading Positions

Large labels in the HTML are emitted keys/actions. Small position labels are
Toucan indices, Air60 matrix coordinates, or generic physical input names.
They are not interchangeable with keycap legends. `Pass` means transparent to
the next active lower layer, not necessarily Base; `None` explicitly emits
nothing. In particular, Toucan Functions falls through active Symbols/Nav, and
Air60 Utilities falls through Functions while Fn remains held.

Toucan positions 0..11, 12..23, 24..35 are three left-six/right-six rows;
36..41 are left-three/right-three thumbs. Its diagram uses captured column
stagger, thumb positions and rotation pivots (100 coordinate units = 1u).
These are firmware presentation coordinates, not measured case dimensions.

Air60's 6x17 electrical matrix is not six physical rows. There are five visual
rows, 64 keys, with widths from the VIA definition:

```text
visual row   matrix coordinates in physical left-to-right order
number       [0,0] [1,1..13]
top          [2,0..13]
home         [3,0..11] [3,13]
bottom       [4,0] [4,2..11] [4,13] [4,15] [2,14]
thumb/arrows [5,0] [5,1] [5,2] [5,6] [5,9] [5,10] [5,14..16]
```

Generic has no single hardware geometry: HTML uses a representative ANSI
typing block plus Escape and arrows. Laptop/ISO/Fn/extra keys vary; unmapped
physical keys retain their normal input. It is not an Air60 matrix diagram.

## Shared Core

Tap A/S/D/F emits the letter; hold gives Super/Alt/Shift/Ctrl. H/J/K/L mirror
Ctrl/Shift/Alt/Super. Toucan and Air60 use explicit left modifiers on A/S/D/F,
right modifiers on H/J/K/L. keyd uses its modifier layers, not an assertion of
right-side HID usages. Air60 Plain has ordinary letters, no letter dual roles.

| Emitted Base positions | Symbols | Nav |
| --- | --- | --- |
| Q W E R T | ! @ # $ % | fall through |
| moved backslash Y U I O | ^ & * ( ) | fall through, Home PageDown PageUp End |
| A S D F G | 1 2 3 4 5 | device-specific modifiers/G below |
| semicolon H J K L | 6 7 8 9 0 | fall through, Left Down Up Right |
| N M comma period | underscore minus plus equals | device-specific N, VolumeDown VolumeUp, device-specific period |

Volume is directly below Down/Up. No Symbols bottom row emits legacy A/S/D/F.
Air60/generic operators are direct bindings once Symbols is active: hold another
trigger (for example the Base slash position) while pressing N/M/comma/period.
Release, rollover and nested layer-tap semantics must be tested per engine.

| Device | Nav | Symbols | Functions |
| --- | --- | --- | --- |
| Toucan | middle left thumb, stable ID 1 | middle right thumb, ID 2 | both middle thumbs, existing conditional ID 3 |
| Air60 Enhanced, Mac switch, base 0, stock NKRO off | hold Z/X/C/V/B, layer 4 | hold slash/N/M/comma/period, layer 5 | dedicated Fn `[2,14]`, layer 6 |
| Air60 Plain, Windows switch, base 3, stock NKRO on | not reachable | not reachable | same dedicated Fn, layer 6 |
| Generic | hold physical Z/X/C/V/B | hold physical N/M/comma/dot/slash | Symbols + physical 1..0/minus/equal = F1..F12; no separate layer |

Air60 Fn + Base slash `[4,8]` holds Utilities layer 7. Keep Fn held so
transparent Utilities keys inherit Functions. Layers 1/2 are retired:
all physical positions transparent, absent cells `KC_NO`, no references.
Toucan display order is 0,2,1,3; stable IDs must never be replaced by that order.
Conditional Functions is user-confirmed historical behavior, not exposed or
recreated by runtime setters. Base bottom-row letters stay ordinary on Toucan.

## Toucan Maps

Each row below is in the exact position order above. `L`/`R` modifier prefixes
mean left/right, not physical half. Base home-row hold roles are as specified.

```text
Base (0)
'       Q       W       E       R       T       | \       Y       U       I       O       P
Esc     A       S       D       F       G       | ;       H       J       K       L       Enter
[       Z       X       C       V       B       | /       N       M       ,       .       ]
                Backspace Nav Space            | Tab Symbols Delete

Nav (1)
Pass    Pass    Pass    Pass    Pass    Pass    | Pass    Home    PgDn    PgUp    End     PrintScreen
Pass    LSuper  LAlt    LShift  LCtrl   MouseR  | Pass    Left    Down    Up      Right   Pass
Pass    Unlock  Pass    Pass    Mouse5  Mouse4  | Pass    Pass    Vol-    Vol+    RShift  RCtrl
                Backspace Pass Space           | Tab Pass Delete

Symbols (2)
Grave   !       @       #       $       %       | ^       &       *       (       )       RShift
Pass    1       2       3       4       5       | 6       7       8       9       0       Pass
~       None    None    None    None    Pass    | Pass    _       -       +       =       LShift+RCtrl
                Backspace Pass Space           | Tab Pass Delete

Functions (3)
Anomaly BLE1    BLE2    BLE3    F11     F12     | USB     BLE     Pass    Pass    Pass    Pass
LCtrl   F1      F2      F3      F4      F5      | F6      F7      F8      F9      F10     Pass
LCtrl   LShift  Pass    Pass    Pass    Pass    | Pass    Pass    BTprev  BTnext  RShift  RCtrl
                Nav Space Enter                | Symbols RAlt Unknown0
```

Nav mouse actions are G/index17 = right button (mask 2), V/28 = Mouse5
(mask 16), B/29 = Mouse4 (mask 8). Nav+Z/25 preserves Studio unlock. Immediate
Nav modifiers A/S/D/F support dragging and navigation chords. Nav N/31 stays
transparent; period/34 stays right Shift. Volume uses consumer usages
`0x000c00ea`/`0x000c00e9`, correcting original keyboard-page usages.

Base top-left is apostrophe/double quote, not grave/tilde. Symbols top-left
is grave; Symbols index24 is direct tilde. Symbols index35 is the explicit
chord **left Shift + right Ctrl**, not merely right Ctrl.

**Review required:** F11/F12 move from Q/W to R/T (4/5), allowing BLE profiles
at Q/W/E (1/2/3). USB/BLE output at backslash/Y (6/7) is proposed. Preserve
BT previous/next at M/comma (32/33). Freed Symbols Z/X/C/V are None; B is Pass.
Nav N/period choices and all retained peripheral modifier/chord bindings need
review, as do the unusual Functions thumbs (not the Base thumb outputs).

Functions index0 retains momentary target `458795`, an invalid-looking layer
reference; index41 retains unadvertised behavior ID 0. Neither is a promised
working control. They are preserved evidence, never sent to setters; live
differences block application rather than triggering guessed restoration.

ZMK BLE1/2/3 use selection parameters 0/1/2. Selecting an empty profile allows
pairing; clearing an occupied bond is separate and never automatic. No NuPhy-like
long-hold pairing is invented. RGB/battery display are not advertised and deferred.

## Air60 Maps And Exceptions

Enhanced (Mac, layer 0) preserves the previous Enhanced layer 3 exactly,
including the shared home-row mods and bottom-row layer-taps:

```text
Esc  1 2 3 4 5 - 6 7 8 9 0 = Backspace
'    Q W E R T Tab \ Y U I O P \
Esc  A S D F G Caps ; H J K L Enter
[    Z X C V B F9 / N M , . ] Fn
Ctrl Super Backspace    Space    Delete Left Down Up Right
```

Moved backslash `[2,7]` is Symbols caret; rightmost backslash `[2,13]` is
Functions F12. Fn is electrically `[2,14]` but physically at the bottom-row
right edge. Backspace `[5,2]` and Delete `[5,9]` flank Space `[5,6]`.
Duplicate Escape/backslash, the inserted Tab/Caps/F9, brackets and arrows are
intentional carry-forwards, not standard QWERTY assumptions.
Center INS `[2,6]` = Tab, CMD `[3,6]` = Caps, END `[4,7]` = F9 for
Omarchy voxtype. Physical Tab `[2,0]` = quote, Caps `[3,0]` = Esc,
left Shift `[4,0]` = left bracket.

Plain (Windows, layer 3) emits immediate letters without any MT/LT:

```text
Esc    1 2 3 4 5 - 6 7 8 9 0 = Backspace
Tab    Q W E R T ' \ Y U I O P \
Caps   A S D F G Delete ; H J K L Enter
LShift Z X C V B [ / N M , . ] Fn
Ctrl Super LAlt          Space    RAlt Left Down Up Right
```

Physical Tab `[2,0]`, Caps `[3,0]`, left Shift `[4,0]` regain their ordinary
roles. LAlt `[5,2]` / RAlt `[5,9]` flank Space. Center INS `[2,6]` = quote,
CMD `[3,6]` = Delete, END `[4,7]` = left bracket. Ctrl/Super `[5,0]`/`[5,1]`
remain ordinary in both modes. All other base positions retain the moved
right-hand layout; Fn `[2,14]` remains `MO(6)` in both modes.

Nav/Symbols use the shared table; unspecified physical keys are Pass.
Nav A/S/D/F are immediate left Super/Alt/Shift/Ctrl, G is Pass; N/period are
explicit None. Nav/Symbols/Functions `[2,0]` = grave. Symbols and Functions
`[0,0]` = direct tilde. Plain Base moves apostrophe to `[2,6]` and retains
number-row Escape. Overlays 4/5/6/7 are byte-for-byte unchanged: grave stays
at physical Tab `[2,0]`, not Plain's relocated quote.
Symbols Z/X/C/V/B remain transparent, never legacy A/S/D/F replacements.
Symbols physical left Shift `[4,0]` emits direct tilde, matching Toucan's
left-bracket position. Enhanced Base remains `[`; Plain Base remains Shift.

Functions A/S/D/F/G/semicolon/H/J/K/L = F1..F10, P/rightmost backslash = F11/F12.
Physical number-row `[1,1..12]` duplicates F1..F12 in physical order, **not**
Base digit order (Base has moved minus/6..0). Q/W/E = BLE1/2/3; R = RF; T = USB;
O = battery indication. There are no number-row Bluetooth duplicates.
N/M = main RGB slower/faster; `[4,0]`/`[4,15]` = brightness down/up
(Enhanced bracket positions, not Plain's relocated left bracket);
Down = mode; Up = brightness down; Right = hue; slash = hold Utilities.

Utilities explicit overrides (everything else Pass, including inherited F keys):

| Base positions | Layer 7 actions |
| --- | --- |
| physical `[1,1..12]` | display brightness down/up, Mac task/search/voice/DND, previous track, play/pause, next track, mute, volume down/up |
| Q W E R T | Mac task/search/voice/console/DND |
| U I | screenshot area/whole |
| O P | auto-sleep toggle / battery indication |
| N M | side-light slower/faster |
| right bracket | side brightness up |
| Down Up Right | side mode / brightness down / color |

**Review required:** Utilities uses layer 7 (not spare), the utility placement,
F11/F12 positions and number-row duplicates, inert Nav N/period, transparent
freed Symbols keys and retained peripherals. RF DFU, reset and RGB factory test
were deliberately omitted. Sleep toggle is persistent when pressed; do not
exercise it merely for coverage. Mac actions may differ or do nothing on Linux.

Custom indices 1/2 = USB/RF, 3/4/5 = BLE1/2/3, 6..10 = Mac actions,
11/12 = whole/area screenshot, 13..18 = side-light controls, 20 = sleep,
21 = battery. Wire base is `0x7e00` for the supported VIA protocol 12 profile.
Short RF/BLE presses select; vendor long holds pair. RF/BLE are ignored in USB
link mode. These are installed-firmware-dependent actions, not ZMK bond clearing.

The distinct bases and switch swap are approved. Plain is **not stock QWERTY**,
but has dedicated Ctrl/Super/Shift/Alt and immediate letters for plain typing.
Stock compiled Mac mode disables NKRO (Enhanced); Windows enables it (Plain).
Runtime VIA does not change that policy; installed-firmware behavior still
requires separate physical verification.

## Generic Maps And Exceptions

Native bindings address physical Linux input names. Physical Y/U/I/O/P emit
backslash/Y/U/I/O; H/J/K/L/semicolon emit semicolon/H/J/K/L;
N/M/comma/dot/slash emit slash/N/M/comma/dot. Physical left/right bracket emit
P/backslash; physical backslash stays backslash. Physical apostrophe stays
apostrophe. Caps/Escape swap; physical left/right Shift emit brackets;
left/right Alt emit Backspace/Delete immediately around a conventional Space.
Other keys (including dedicated Ctrl/Super) remain unchanged.

Nav physical G = Enter. Physical U/I/O/P and J/K/L/semicolon implement the
shared navigation block; physical M/slash = None, comma/dot = volume down/up.
Other keys inherit Base, **including dual-role A/S/D/F**, unlike immediate Nav
modifiers on firmware devices. **Review required:** this modifier-access
difference and G = Enter are current native exceptions, not shared equivalence.

Symbols uses the shared punctuation/digit/operator table, physical 1..0/minus/
equal = F1..F12, physical Tab/grave = grave and left Shift = direct tilde.
Physical N emits ordinary slash on Symbols (not a nested layer-tap).
Physical Z/X/C/V/B inherit Base Nav layer-taps. Physical grave stays grave on
Base too, unlike Toucan/Air60 top-left apostrophe. No Bluetooth/RGB/device
controls and no tri-layer Functions are assigned. **Review required:** all base
punctuation carry-forwards, Nav inert endpoints and Symbols fall-through choices.

## Verification Boundary

keyd explicitly sets 200 ms dual-role timing, 180 ms for Shift. Toucan getters
and Air60 VIA do not expose equivalent runtime timing/flavor tuning; 200 ms is
only a design/source baseline there. Engine equivalence is not promised.

Before migration, review native diffs and these exceptions; retain a fallback
keyboard. Separately verify setter acceptance and persisted readback before
explicit test pass-through. After pass-through, verify fast rolls, repeated
letters, shortcuts, modifier release, layers, operator rollover, volume, mouse
dragging, Functions thumbs, reconnect and both Air60 switch modes; record
physical test completion separately from readback/file verification.
Test non-destructive BLE selection deliberately, never bond clearing for coverage.
Keep both Toucan halves USB-powered; battery operation is outside scope.
Offline checks and this reference do not prove applied state or hardware behavior.
