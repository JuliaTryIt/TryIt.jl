# Upstream issues

Issues found in dependencies while developing TryIt.jl.

## Tachikoma.jl — recording shortcut is hardcoded to Ctrl+R

**Package:** Tachikoma.jl v2 (`~/.julia/packages/Tachikoma/sti9l`)
**Found:** 2026-07-18
**Status:** open, not yet reported upstream
**Impact:** worked around in TryIt.jl; no blocker

### Problem

`app()`'s default bindings claim Ctrl+R for `.tach` screen recording
and intercept it at `src/app.jl:259`, *before* dispatching to the
model's `update!`. An application that wants Ctrl+R for its own
purpose has exactly one escape hatch — `recording_enabled(model) =
false` (`src/app.jl:84`) — which turns the feature off rather than
moving it.

TryIt.jl uses Ctrl+R for rename, matching the reference `try-cli` and
`try-rs` interfaces, so the two collide and rename was unreachable.

### Why rebinding to Ctrl+Shift+R is not possible

1. `KeyEvent` (`src/events.jl:9`) is `(key::Symbol, char::Char,
   action::KeyAction)` — no modifier fields at all, unlike
   `MouseEvent` (`src/events.jl:20`), which carries
   `shift`/`alt`/`ctrl`. There is nowhere to record that shift was
   held.
2. The Kitty-protocol parser guards every Ctrl branch on `!shift`
   (`src/events.jl:592-600`), so Ctrl+Shift+R falls through to the
   shifted-codepoint path at `src/events.jl:633` and is delivered as
   `KeyEvent(:char, 'R')` — indistinguishable from typing a capital
   letter.
3. Outside the Kitty protocol the distinction does not exist on the
   wire: a legacy terminal sends the same `0x12` byte for Ctrl+R and
   Ctrl+Shift+R.

### Suggested upstream fix

Either would resolve it:

- Make the binding configurable, e.g. `recording_key(::Model) =
  (:ctrl, 'r')`, so an app can move the shortcut instead of losing
  the feature.
- Give `KeyEvent` modifier fields for parity with `MouseEvent`, so
  chords like Ctrl+Shift+R become expressible where the terminal
  supports the Kitty keyboard protocol. This does not help legacy
  terminals, which cannot encode the distinction at all.

### Workaround in TryIt.jl

`Tachikoma.recording_enabled(::SelectorSession) = false` frees Ctrl+R
for rename, and recording is re-offered on **F9**, driven through the
exported `start_recording!` / `stop_recording!` / `clear_recording!`
API against the `CastRecorder` reached via `init!(model, terminal)`.

F9 was chosen because function keys parse in both legacy
(`src/events.jl:369-380`) and Kitty terminals, so the binding carries
no modifier-encoding risk.

The framework's countdown notification and export modal live in the
private `AppOverlay` and are deliberately not reproduced; the
selector renders its own `● REC` indicator instead.
`start_recording!` still applies its own 5-second countdown, since
that lives on the recorder rather than the overlay.

The remaining framework bindings (Ctrl+\\ theme picker, Ctrl+? help,
Ctrl+, settings, Ctrl+Y copy) are left intact.
