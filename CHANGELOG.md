# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Project-language legends now retain their stable badge colours in TUI,
  WebTUI, and WebNative instead of being flattened into monochrome list text.
- The `pulse` background uses a bounded set of visual levels, allowing the
  terminal diff to skip identical frames instead of saturating slower terminal
  emulators and making the selector appear frozen.
- Theme, animation, About, and Help modal windows are transparent in every
  ManyUI projection, so the active animated background remains visible.
- The selector now uses the common `isopen`/`close`/`wait` handle contract
  directly for every backend; the WebNative-specific lifecycle adapter was
  removed after `ManyUIWeb.WebNativeServer` gained `Base.isopen`.
- The ManyUI TUI now derives its foreground, dim, title, border, and modal
  colours from the active Tachikoma theme. Light animated backgrounds no
  longer inherit the terminal's pale default foreground.
- `Ctrl+T` and `Ctrl+B` now open centered theme and animation pickers in the
  ManyUI frontends, with live preview, confirmation, and cancellation.
  `Ctrl+A` About and `?` Help use the same centered modal presentation instead
  of being inserted into the selector layout.

### Added

- The selector now has a ManyUI-first application path shared by local TUI,
  WebNative, and WebTUI projections. `TRY_FRONTEND` selects `tui` (the new
  default), `webnative`, `webtui`, or the temporary legacy `tachikoma` path;
  `TRY_WEB_PORT` configures either web target. The programmatic
  `launch_selector` entry point accepts the same targets.

- TryIt backgrounds now have a backend-neutral
  `SelectorBackgroundEffect` and a compositing `SelectorBackgroundWidget`.
  All color and glyph effects project to terminal cells for TUI/WebTUI and to
  an animated canvas or CSS fallback for WebNative, leaving a renderer seam
  for a future Dear ImGui draw-list projection.

### Changed

- The ManyUI selector now follows the Tachikoma reference layout: Search/New
  and Folders occupy the main column, while Disk, Preview, and Legends form a
  secondary column above a shared shortcut footer. Delete, rename, graduate,
  theme, background, help, and about actions are available from the same
  widget tree in every projection.

- TUI and WebTUI now measure the selector composition root against the full
  backend viewport and run the original Tachikoma background renderer on each
  animation tick. WebNative uses the same logical cell aspect, theme palette,
  effect parameters, and absolute frame clock for the color-effect canvas.
  This fixes the former 80x24 top-left layout and the animation task race that
  could leave the first frame permanently frozen. The local TUI driver also
  writes through the original stderr TTY, whose `displaysize` reports the real
  window, instead of the `/dev/tty` IOStream that Julia reports as 80x24.

- `Slug`'s conversion and hashing methods are covered, restoring the
  100 % line coverage of the slug generator that NF16 requires. The
  gate had been failing on `main` before the layering work — nothing
  exercised `Base.string`, `Base.print` or `Base.hash` on a `Slug`,
  and those one-line definitions only count as covered when called.

  The threshold was not lowered: the tests assert what the methods
  exist for. `string`/`print` keep a `Slug` from reaching user-visible
  output as `Slug("foo-bar")`, and the `:Slug` salt in `hash` keeps a
  `Slug` distinct from the bare `String` of the same characters in a
  mixed collection.

  Worth noting for whoever sees this next: `Julia 1.10 - ubuntu`
  passed this gate on the same commit where `Julia 1 - ubuntu` failed
  it. Coverage attribution for these definitions changed in 1.12, and
  raising the floor removed the only cell that was passing.

- CI no longer pins `arch: x64`. `macos-latest` moved to Apple
  Silicon, and `setup-julia` refuses x64 on an arm64 runner, so every
  macOS job failed in 10 seconds before Julia was even installed —
  on `main`, before this branch existed. Letting the action default
  gives x64 on Linux and Windows and aarch64 on macOS, which is what
  users actually run; `force-arch: true` would have "fixed" it by
  testing an emulated architecture nobody ships on.

- The selector's state moved into the core as
  `src/selector_state.jl`. `SelectorState` holds 25 of the model's 27
  fields; `SelectorSession` is now a thin `Tachikoma.Model` wrapper
  keeping only the two that are irreducibly a frontend's — the
  terminal handle and the resolved background object, whose type spans
  both layers.

  Property access is forwarded, so `session.filter` and
  `session.state.filter` name the same slot and not one of the ~1700
  lines of call sites had to learn where a field lives. The
  forwarding is covered by a test asserting every state field is
  reachable through the wrapper: a gap there would surface only on
  whichever branch happens to touch the missing field.

  Scope, stated plainly: this extracts the *state*, not the
  transitions. `update!` and `view` are still typed on
  `Tachikoma.KeyEvent` and `Tachikoma.Frame`, so `selector.jl` went
  from 1725 to 1693 lines and from 209 to 206 Tachikoma references.
  A second frontend can now hold and mutate the state, but cannot yet
  drive it without reimplementing the reducer. That is the next step.

- `tries_path` can be set in `~/.config/tryit/config.toml`, with a
  leading `~` expanded against `$HOME`. Resolution is now positional
  argument, then `TRY_PATH`, then the file, then `$HOME/work/tries`
  (UB1).

  This closes a migration cliff opened the same day: moving the
  default from `~/src/tries` to `~/work/tries` stranded every existing
  user's tries with no warning, and the environment variable was the
  only remedy — while `try-rs`, the tool whose default TryIt was
  aligning to, stores its own root in a config file under the same key
  and the same `~` spelling. Sharing one root between the two tools
  therefore required an `export` in the shell profile.

  Two defects surfaced while wiring it up, both of which would have
  shipped the setting broken:

  - The emitted shell function pinned
    `TRY_PATH=${TRY_PATH:-$HOME/work/tries}`, so the variable was
    always set, the environment branch always won, and `tries_path`
    was unreachable through the only entry point anyone uses. The
    function no longer sets the variable unless `tryit init <dir>`
    gave it an explicit root.
  - `save_settings` wrote the config file wholesale, so `Ctrl-W`
    silently erased `tries_path` and `timezone`. It now merges into
    the existing file. Losing `tries_path` hides every try, which
    reads as data loss rather than a reset preference.

- The core no longer references any UI layer, enforced by an
  architecture test (`test/spec/test_core_boundary.jl`). `config.jl`
  was the last offender: `save_settings` read `Tachikoma.theme().name`
  and now takes the theme name as data, the view layer supplying it.

  This is not stylistic. A dependency on Tachikoma runs its
  `__init__`, which performs seven `@load_preference` reads; under
  `juliac --trim` these reach `Base.get_preferences`, which splats
  into a vararg that cannot be resolved statically, and the binary
  dies at load before reaching `main`. Reproduced on 2026-07-18 with
  a seven-line package depending only on `Preferences` — so it is
  neither a Tachikoma nor a TryIt bug, and no amount of care inside
  TryIt avoids it while Tachikoma is a dependency of the core.

  First step toward splitting core / CLI / TUI / GUI into submodules.

- The core is now a real submodule, `TryIt.Core`, holding `slug`,
  `errors`, `paths`, `git`, `lifecycle`, `panels` and `config`. It
  depends on `Dates`, `TOML`, `Unicode` and `DocStringExtensions` —
  no UI layer. Its whole surface is re-exported, so every name stays
  reachable as `TryIt.x` and no caller had to change.

  `THEME_ENV`, `BACKGROUND_ENV`, `ANIMATION_ENV` and
  `DEFAULT_BACKGROUND` moved from `theming.jl` down into `config.jl`:
  the core's settings resolution read them, which was an upward
  reference into the UI layer. `BACKGROUND_PRESET_ENV` stayed put,
  its only reader being `background_preset`.

  The boundary now has two guards — a grep over the core file list,
  and `isdefined(TryIt.Core, :Tachikoma)` on the live module, which
  catches a `using` the grep cannot see. Both were verified by
  injecting the regression and watching the right one fail.

- The animated-background family moved into the core as
  `src/animations.jl`: the `ColorBackground` types, `ANIMATION_NAMES`,
  `BACKGROUND_OFF_NAMES`, the new `color_animation` lookup, and the
  colour-family methods of `animation_name` and `blanks_panels`. They
  are parameter bundles and name tables with no colour or terminal in
  them. `theming.jl` keeps the rendering and adds the glyph-background
  methods to the same functions, so `animation_name` stays one
  function owned by the core with nine methods across two layers.

  This required the core re-export to switch from `using` to
  `import`: `using` brings a name in without the right to extend it,
  and the package no longer precompiles at all if it regresses.

  Worth recording honestly: `theming.jl` went from 371 to 258 lines
  but only from 40 to 38 Tachikoma references. The plan had called
  this step "abstract the palette", which overestimated it — TryIt
  defines no themes of its own, it consumes the UI layer's and
  already carried only the *name* across the boundary. What was
  actually extractable was the animation family, and what remains in
  `theming.jl` is genuine rendering that belongs in the UI layer.

- Minimum Julia version raised from `1.10` to `1.12` (NF11, NF18).
  This drops support for the current LTS. The motivation is to keep
  the static-compilation path open — `juliac` / `--trim` land in
  1.12 and target a smaller, faster-starting `tryit` binary than
  `PackageCompiler.create_app` produces. `1.11` was not considered:
  it is already out of support, so the choice was 1.10 or 1.12.

### Added

- An optional frames-per-second readout: `show_fps` in the config file,
  `TRY_SHOW_FPS` in the environment. Off by default. When on, a small
  rolling-average rate is drawn in the top-right corner.

  It measures what the animation *actually* achieves in the terminal it
  is running in, which the `fps` setting alone cannot tell you: `fps` is
  the rate the selector *asks* for, but a terminal that cannot keep up
  with the animated background renders fewer. The readout makes that gap
  visible — the same `fps = 30` can render at 30 in one terminal and a
  fraction of that in another — so it is the direct way to judge whether
  a terminal, or a lighter animation, is the right choice.

  The meter (`FpsMeter`) is pure state driven by a caller-supplied
  timestamp, so it is unit-tested without a running event loop; the UI
  layer feeds it `time()` once per rendered frame and reads the average
  back to draw.

- A configurable frame rate: `fps` in the config file, `TRY_FPS` in the
  environment. Defaults to 60, matching Tachikoma's own default, and is
  clamped into 1–240 — zero would divide by zero in the frame pacing,
  and past 240 the extra frames go to a terminal that cannot show them.

  The animated backgrounds repaint the background colour of every cell
  they cover, every frame. Computing that is cheap — under 3 ms per
  frame for a full-screen `plasma` — but writing it is not: at roughly
  20 bytes per styled cell, a full-screen frame is a couple of hundred
  kilobytes, and sixty a second is over ten megabytes.

  GPU-accelerated terminals absorb that; terminals built on xterm.js do
  not, and not for want of bandwidth. Their glyph cache is keyed on the
  background colour, so an animated background makes every glyph over
  it a cache miss and a fresh rasterisation. Against a real frame
  stream, about a third of the glyphs miss on *every* frame and the
  cache never warms up. The frame rate was previously fixed at 60, so
  the only remedies were turning the animation off or changing
  terminal.

  A fractional or quoted value is accepted, because TOML does no
  coercion and `fps = "24"` means what it says. Unlike every other
  setting, an unusable `TRY_FPS` falls through to the *file* rather
  than straight to the default: the environment is where typos are
  made, and a mistyped override should not silently discard a
  deliberate configured value. `Ctrl-W` still writes only the theme
  and animation, and merges rather than replaces, so a hand-written
  `fps` survives it.

- Colour for non-TUI output (UB7). Diagnostics now carry a coloured
  `tryit: <subsystem>:` prefix; the message itself is left plain,
  since that is the part a user copies, greps, or pastes into a bug
  report.

  Colour is suppressed when `--no-colors` is passed, when `NO_COLOR`
  is set and non-empty (per no-color.org — an *empty* value is not
  "set", or `NO_COLOR=` could not undo an inherited one), or when the
  destination stream is not colour-capable. That last condition is
  the load-bearing one and is decided **per stream**: stdout carries
  shell commands under UB4, and an escape sequence wrapped around a
  `cd` would be `eval`'d by the caller's shell.

  All three conditions were previously advertised and none
  implemented. `--no-colors` was filtered out of the argument list
  and discarded; `NO_COLOR` appeared only in the help text; and
  nothing outside the TUI emitted colour at all, so none of it had
  ever mattered. The help text is now true rather than aspirational.

  Applied at `diag`, the single funnel all thirty diagnostic call
  sites already pass through, so no call site changed. The policy
  (`color_enabled`) is kept separate from the rendering (`paint`)
  precisely so the policy can be tested without a terminal.

  Stream capability is read from `get(io, :color, false)` — Julia's
  own answer, which rides on `IOContext`, is per-stream, and already
  honours `julia --color=yes|no`. An earlier attempt called `isatty`,
  which does not exist in `Base` in Julia 1.12; a broad `catch`
  turned the resulting `UndefVarError` into `false`, so colour was
  suppressed unconditionally and every suppression test passed for
  the wrong reason. JET caught it. The suite now also asserts the
  positive case, which is what was missing.

- Optional trust scanning of anything `clone` or `fetch` brings in,
  via a package extension on
  [PluginGuard.jl](https://github.com/s-celles/PluginGuard.jl)
  (OF7, OF8). With PluginGuard installed, the new try is statically
  scanned before the `cd` is emitted and high-severity findings go to
  stderr; without it, both commands behave exactly as before, with no
  diagnostic and no added latency.

  The warning is advisory and stays advisory: the `cd` is still
  emitted and the status is still `0`. Blocking was considered and
  rejected — a false positive stranding a legitimate download behind
  a scanner the user cannot override costs more than the warning
  gains. TryIt never executes a try's contents, so informing the user
  before *they* run something is the honest ceiling here, and the
  documentation says so rather than implying safety.

  The core owns the vocabulary (`TrustFinding`, `TrustReport`,
  `TrustScanner`) and never names the backend, which is what keeps
  the weak dependency weak; `test_core_boundary.jl` now fails if
  `PluginGuard` becomes reachable from `TryIt.Core`. A backend that
  throws yields an *unavailable* report rather than propagating,
  because the scan runs after an operation that already succeeded on
  disk. `available` is kept distinct from *no findings* throughout:
  collapsing the two would report a tree as clean when nothing ever
  looked at it.

  Only `HIGH` is surfaced. Reporting `LOW` and `MED` as well would
  bury the line that matters under noise on every clone of an
  ordinary repository, and a warning nobody reads is worse than none.

  Registration is blocked until PluginGuard reaches General: weak
  dependencies are resolved by Pkg like any other. The test
  environment pulls it via a `[sources]` entry, which is legal there
  because that environment is never registered.

- `tryit fetch <url> [<name>]` downloads a single resource into a new
  try (ED26). The file keeps its own basename; the try is named after
  that basename with its final extension dropped, or after `<name>`
  when given. The resource is stored verbatim — archives are not
  extracted. No upstream fetches; the motivating case is a single-file
  snippet linked from a forum or a gist, which is among the most
  common reasons to make a scratch directory and previously had no
  path at all.

  A failed fetch exits `1` and leaves the tries path untouched
  (UN11). The download lands outside the tries path and is moved in
  only once it has completed and passed a 100 MiB cap, which makes
  the no-residue guarantee structural rather than a matter of
  remembering to clean up. `ExitCode.FAILURE` is new for this and is
  deliberately not `127`: a status code that means both "missing
  program" and "HTTP 404" is one scripts cannot branch on (UB6
  amended).

- A bare URL now routes to `clone` *or* `fetch` by inspecting the
  whole URL rather than its extension (ED27). Extension alone cannot
  decide this in Julia: the ecosystem names repositories `Foo.jl`, so
  `github.com/s-celles/PluginGuard.jl` and
  `cdn.example.com/3X/b/3/<hash>.jl` share a suffix while requiring
  opposite handling. An `ssh`/`git@`/`git://` form, a `.git` suffix,
  or a known forge with an exactly-`owner/repo` path is a repository;
  every other `http(s)` URL is a file.

  Host-and-shape was chosen over probing the network because it is
  decidable offline and therefore testable without a server. Two
  consequences are accepted rather than hidden: a self-hosted forge
  routes to `fetch` unless its URL ends in `.git`, and a deep forge
  URL such as `github.com/<owner>/<repo>/blob/<ref>/<file>` routes to
  `fetch`, downloading the HTML page rather than the file it renders.
  `tryit clone` and `tryit fetch` override the guess in both cases.

  This replaces `_looks_like_url`, which treated any `http(s)`
  argument as a git remote — the reason a link to a raw `.jl` file
  produced a failed clone and no try at all.

- `tryit path` prints the tries root and `tryit list` prints every
  try's absolute path, one per line (ED24). Neither upstream offers a
  non-interactive listing — their shell completions re-derive the
  path in shell to work around it.
- A bare git URL is treated as a clone (ED25), matching all three
  upstreams.
- `--no-colors` is accepted and consumed wherever it appears.

- `timezone` setting, `local` (default) or `utc`, deciding which clock
  every date is read from — both the prefixes TryIt writes and the
  dates it infers from mtimes, so the two always agree.

- Development guide and `bin/resolve-envs.sh`. Three environments
  pin TryIt and each keeps its own `Manifest.toml`; none is updated
  by pulling a commit that changes dependencies, and the `@TryIt`
  shared environment is the one that breaks `tryit` itself rather
  than the build. This went wrong twice while adding CommonMark and
  TOML, so the recovery is now one command and is documented where a
  contributor will look.

- Configuration file for `theme` and `animation` (OF6), read from
  `$TRY_CONFIG`, `$XDG_CONFIG_HOME/tryit/config.toml` or
  `~/.config/tryit/config.toml`, with precedence environment > file >
  default. A missing, unreadable or malformed file yields defaults
  rather than preventing startup. Uses the `TOML` stdlib, so no new
  external dependency.
- `Ctrl-B` opens an animation picker, applying each choice live and
  restoring the previous one on `Esc` (ED21).
- `Ctrl-W` saves the active theme and animation to the config file
  and reports where it went (ED22).

- Five colour animations rather than one: `fog` (the former `wash`),
  `aurora`, `plasma`, `rain` and `pulse`, selectable with
  `TRY_ANIMATION` or `TRY_BACKGROUND`. Each derives its palette from
  the active theme, so choosing an animation is independent of
  choosing a theme. Tests assert the five are mutually distinct and
  that each changes between frames, so the family cannot quietly
  become one effect under five names.

- `F1` opens the manual inside the selector (ED20). The same markdown
  that builds the website is embedded at precompile time and rendered
  with CommonMark through Tachikoma's `MarkdownPane`; Documenter
  `@docs` directives are expanded against the package, so the
  Reference page shows real docstrings in the terminal rather than
  the directive standing for them. Embedded rather than read from
  disk because a PackageCompiler bundle contains no markdown files
  and `pkgdir` inside one points at the build machine.
- `CommonMark.jl` runtime dependency, required by the above; NF1
  amended.

- `Ctrl-P` toggles a folder's date prefix from the selector (ED19).
  Adding asks which date to stamp — the folder's own or today's —
  naming both concretely, since the reason to ask is that they
  differ. Removing does not ask; there is nothing to decide. It commits the date already
  displayed rather than today's, so the row does not jump, and
  prepends the prefix without re-slugging, so `LibPARI.jl` becomes
  `2026-07-18-LibPARI.jl`. Pressing it on an already-dated try
  reports why instead of doing nothing.

- Backlog of gaps against `try-rs` recorded in `spec.md` §12 (B1–B14)
  after auditing its source: a `config.toml` layer, multiple tries
  paths, fuzzy ranked matching, an inline picker, multi-shell setup,
  and more. Written with `B`-prefixed handles outside the requirement
  syntax, so unbuilt work does not satisfy the traceability check.
- UB2 reaffirmed: `try-rs` separates the date prefix with a space and
  defaults it off; this project keeps a mandatory hyphenated ISO
  date, and the divergence is now recorded as deliberate.

- Packaging automation: `TagBot.yml` (NF19), `Register.yml` (NF20),
  `.github/dependabot.yml` (NF21) and `CITATION.bib` (NF9).
  `Register.yml` bumps `Project.toml` itself, because
  `julia-actions/RegisterAction` takes only `token` and
  `registrator` — the version input NF20 describes does not exist on
  the action. The bump was exercised for patch, minor and major
  before landing; it defaults to patch, so a release cannot leave
  0.x unintentionally.
- `spec.md` is now tracked, so the traceability test runs in CI
  rather than skipping.

- `spec.md` reconciled with the implementation. Four requirements
  amended (UB1 default path, ED3 narrowed, ED11 rebound to `Ctrl+N`,
  NF1 dependency set), UB5 given an explicit TUI exception, and
  twelve capabilities that existed without a written requirement now
  have one: ED14–ED18, SD4–SD6, OF4, OF5, UN8, UN9. All 72
  requirements trace to code.

- Requirements traceability page documenting which EARS requirements
  are met, which have drifted, and what remains for v1.0.
- Drift guards in the test suite: every requirement ID in `spec.md`
  must be referenced from `src/` or `test/` or carry a written
  exemption, and every documented key binding must exist in the code
  and appear in the `?` overlay. Both were verified to fail on
  injected drift, not just to pass.

- The selector owns its keymap (`default_bindings=false`), matching
  `try-rs`: `Ctrl+T` theme picker, `Ctrl+A` About, `Ctrl+R` rename,
  `?` key-binding overlay. Creating a dated placeholder try moves
  from `Ctrl+T` to `Ctrl+N`. Tachikoma's settings overlay and
  clipboard copy are given up in the trade — its bindings are
  all-or-nothing apart from recording.
- Theme picker applying each theme live as the cursor moves, with
  `Esc` restoring the theme active when it opened.
- Help bar restyled after `try-rs` and made responsive: `StatusBar`
  clips rather than wraps, so a fixed list silently dropped
  `Esc Quit` at 100 columns and cut mid-word at 80.

- Open-or-create prompt. Filtering matches substrings of
  `"<date> <slug>"`, so typing the beginning of an existing name
  always opened that try and left no way to create the shorter name —
  with `2026-07-18-help-me` present, `help` was uncreatable, and
  since the date is in the haystack, `2026` matched everything from
  the year. `Enter` on an ambiguous filter now asks whether to open
  the highlighted try or create one named after the typed text.
  Opening is the default. Typing a full existing name still opens it
  in a single keystroke. This is the same gap as `try-rs` issue #44.

- Multi-panel selector TUI, modelled on the reference `try-rs`
  interface: bordered `Search/New`, `Folders`, `Disk`, `Preview`, and
  `Legends` panels, plus a key-binding help bar. The folder list now
  shows a project-type badge and a right-aligned `DDd HHh MMm` age
  column.
- Project-type detection (`detect_badges`) for Rust, Julia, Python,
  Go, Maven, Flutter, and Mise, plus lockfile, git repository, linked
  worktree, and submodule markers, each with its own legend colour.
- Preview panel listing the selected try's contents, directories
  first.
- `F9` toggles `.tach` screen recording, replacing the framework
  binding that collided with rename.
- Theme selection via `TRY_THEME`, covering all 24 Tachikoma themes.
  `Ctrl-\` still opens the in-app picker, which wins for the rest of
  the session. An unknown name is ignored rather than fatal.
- Animated background, on by default, configured with
  `TRY_BACKGROUND` (`wash`, `dotwave`, `phylo`, `clado`, or an
  opt-out spelling) and `TRY_BACKGROUND_PRESET`. Skipped when
  Tachikoma's global motion switch is off.
- `WashBackground`, the default: an animated colour gradient derived
  from the active theme. Tachikoma's own backgrounds draw braille in
  the *foreground*, which shows through panel interiors as noise;
  blanking the interiors erases them entirely, since no background
  colour sits underneath. The wash paints cell background colours
  instead, so text over it stays legible and panels can be blanked
  safely. The glyph backgrounds remain available, rendered full-bleed.
- Disk panel showing used and free space for the filesystem holding
  the tries root. Degrades to "unavailable" on Windows, where `df`
  does not exist.

- Standalone application build via
  [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl).
  `julia --project=build build/build.jl` produces a self-contained
  `tryit` executable in `build/tryit-app/` that bundles its own Julia
  runtime, removing interpreter startup cost per invocation.
- `julia_main` entry point (`Cint`, zero-argument) as required by
  PackageCompiler's `create_app`, with `_app_main` as the testable
  seam that accepts explicit arguments.
- `tryit init` now detects whether it is running as a compiled app
  and emits a shell function that calls the executable directly,
  instead of booting `julia` against the `@TryIt` shared environment.
- Documentation page covering the standalone app build.
- This changelog.

### Fixed

- The trust scanner never ran for anyone using `tryit` as a command,
  which is everyone (OF7). Two independent faults, both invisible to
  the test suite as it stood:

  A package extension activates when its trigger package is
  *loaded*, not when it is installed. The shell function `tryit init`
  emits runs `julia -e 'using TryIt; TryIt.main(ARGS)'` and never
  loads PluginGuard, so the scanner stayed `NoScanner` however the
  user installed it. Every test in `test/trust/` said
  `using PluginGuard` first, so all of them passed against a feature
  that was inert in production. The backend is now loaded on demand
  from `_report_trust`, which is both the moment it is needed and
  the only one — opening the selector or creating a try from a name
  still costs nothing. Doing it there rather than in the emitted
  shell function means an already-installed shell function picks the
  feature up without anyone re-running `tryit init`.

  Then, once loading worked, the first scan still reported nothing:
  `Base.require` adds the extension's `scan_try` method *during* the
  call that leads to it, and a method added after a function starts
  executing is invisible to it. The direct call raised `MethodError`
  in a stale world age, which `scan_try`'s own `catch` turned into an
  *unavailable* report — scanner live, finding real, user told
  nothing. The dispatch goes through `invokelatest`, and a
  subprocess test now exercises the whole path with only `TryIt`
  loaded, on a cold extension cache.

- A URL pasted into the selector made an empty directory instead of
  fetching anything (ED4, ED27). The clone-or-fetch routing had been
  wired into the command-line dispatcher only, so the selector took
  the same URL, slugified it, and created something like
  `2026-07-19-https-cdn-example-com-forum-original-3x-b-3-abc123-jl`
  — a directory of some sixty to a hundred characters containing
  nothing, which the caller was then `cd`'d into. Typing a URL is
  exactly what a user does after learning `tryit <url>` works from
  the shell.

  The selector now classifies the filter with the same `url_kind` the
  command line uses, and defers the transfer to after the event loop
  exits. That placement is deliberate: a network round trip inside
  the reducer would freeze the display, and UB5's selector exception
  means a diagnostic written from a key handler reaches nobody. Once
  the loop is out, `clone` and `fetch` run exactly as they do from
  the shell — same diagnostics, same trust scan, same exit codes.

  `exit_url` is a new field rather than a reuse of `exit_path`, which
  is always a local path. One field meaning two things is how a `cd`
  into a URL eventually happens, and a test asserts the separation.

- A failing `tryit clone` never told the user why. `_collapse_stderr`
  reduced git's stderr to its **first** non-empty line, and for
  `clone` that line is always the progress banner
  `Cloning into '<dest>'...`. The diagnostic therefore read
  `tryit: git: Cloning into '…'` — which looks like success — while
  the `fatal:` line naming the actual cause was discarded. This had
  been true of every failing clone since the helper was written: a
  wrong URL, a 403, a missing repository and a refused credential
  were indistinguishable.

  Surfaced by `tryit <url>` on a link to a raw `.jl` file, where git
  returns 403 and the user saw only the banner.

  The line is now chosen by scanning from the end for git's
  `fatal:`/`error:` prefix, falling back to the last non-empty line.
  Scanning backwards keeps trailing `hint:` lines from displacing the
  cause; the fallback keeps the rule working under a locale that
  translates the prefix. Forcing `LC_ALL=C` on the subprocess was
  rejected — it would hand a French user an English error message to
  spare us a regex. UN3 amended to require the cause, not just the
  exit code.

- Three test items never ran their assertions. `@testitem` evaluates
  each block in its own module, and two blocks in
  `test/config/test_min_size.jl` plus one in
  `test/app/test_shell_init_app_mode.jl` referenced `TryIt` while the
  import lived in a *different* block of the same file. They errored
  with `UndefVarError` instead of testing anything — so UN6's
  too-small-terminal rejection, its 0×0 fail-open, and the compiled
  app's shell-function text were all unverified.

- `tryit --help`, `--version`, `path` and `list` were unusable
  through the shell function. Everything on stdout is `eval`'d, so
  the shell tried to execute the help text line by line —
  `command not found: usage:`, `no such file or directory: name`, and
  so on. The emitted function now recognises those four and runs the
  binary directly instead of capturing and evaluating, which keeps
  their stdout clean for scripting. UB4 clarified to say that stdout
  is a command channel, not an output channel.

- Every command-line flag was treated as a slug. `slug("--help")`
  strips to `help`, so `tryit --help` created `2026-07-18-help` and
  exited `0` — no help, and a directory littering the tries root.
  Leading-dash arguments are now flags: `-h`/`--help` and
  `-V`/`--version` print and exit `0`, anything else is a usage error
  (`64`), and `--` forces the next argument to be read as a slug
  (ED23).
- Attribution corrected. `tobi/try-cli` is a **C** implementation, not
  the Ruby original; the `try-cli` gem comes from `tobi/try`, a
  different repository. The README, spec and docs called them one
  project.

- The date shown for an undated folder was computed in UTC while
  every date TryIt writes comes from `Dates.today()`, which is local.
  A folder touched shortly after midnight was therefore listed under
  the previous day, and the date offered when stamping a prefix
  disagreed with the one displayed. Surfaced by a test that set an
  mtime with `touch -t` and got a year back that was off by one.

- Config reads and writes take their path explicitly instead of only
  through `TRY_CONFIG`. `withenv` mutates the process-global `ENV`,
  so with test items running concurrently one item's cleanup could
  clear another's override — and `write_config` then fell back to the
  default path and wrote into the developer's real
  `~/.config/tryit/`. It did.

- Embedded documentation pages went stale silently. Julia invalidates
  a precompiled image when an *included* source file changes, but a
  file merely `read` is invisible to that machinery — so editing
  `docs/src/*.md` left the in-app copy showing the previous text with
  nothing to indicate it. Each page is now registered with
  `include_dependency`. Caught by the staleness test rather than by
  anyone noticing the wrong manual.

- The selector listed only directories matching `YYYY-MM-DD-<slug>`,
  so anything else under the tries root was invisible — 8 of 12
  directories in a real tries path, including hand-cloned
  repositories. Every directory is now listed; undated ones are
  rendered dimmed and dated from their filesystem mtime.
- A dated try whose name was not a valid slug was misread as undated
  and stamped with today's date: the parser required the portion
  after the date to match `^[a-z0-9-]+$`, which
  `2026-04-15-s-celles-Nghttp2Wrapper.jl` fails on its uppercase and
  dot. The date prefix is now parsed independently of the rest.
- `?` opens the help overlay only while the filter is empty.
  Directories are listed under their real names now, so a folder
  called `what?` is both possible and filterable, and taking `?`
  unconditionally would have made it unreachable.

- Deleting a try that is a linked git worktree used an unconditional
  `rm -rf`, leaving it registered in its parent repository: `git
  worktree list` kept showing it as `prunable` and its admin
  directory survived under `.git/worktrees`. The worktree is now
  unregistered with `git worktree remove` first, and the directory is
  removed regardless of whether that succeeds. Found by comparing
  against `try-rs`, which branches on the same condition.

- Deleting the try under the cursor emitted a `cd` into the removed
  directory, so the caller's shell failed with
  `(eval):cd:1: no such file or directory`. Deletes run after the
  selector picks its target but before the `cd` is written, so the
  target could already be gone. The `cd` is now suppressed with a
  diagnostic when its target is no longer a directory — which also
  covers a try removed by another process while the selector is open.

- Building the standalone app created warm-up directories inside the
  building user's *real* tries root. `build/precompile_app.jl` drove
  the direct form, which takes no path argument and so resolved
  `TriesPath()` to the default rather than to the script's temporary
  directory. `TRY_PATH` is now set for the whole workload.

- `tryit init` could not install its shell function for users with an
  existing `alias tryit=...` (common when migrating from `try-cli` or
  `try-rs`). zsh expands aliases while *parsing* a function
  definition, so the definition was a syntax error and the whole
  `eval` aborted, silently leaving the old command in place — the
  selector appeared to ignore selections because a different `tryit`
  was running. The snippet now drops any conflicting alias and
  defines the function through a nested `eval`, which is parsed only
  after the `unalias` has executed. Emitting the `unalias` on a
  preceding line is not sufficient: zsh parses the entire `eval`
  string before running any of it.
- Switching animations off with `Ctrl-A` did not stop the background
  until the next launch: the motion setting was read once at
  `open_session` and cached. The selector now re-checks it every
  frame, so a reduced-motion preference takes effect immediately.
- A `.tach` recording left running when the selector closed was
  silently discarded — `stop_recording!` performs the write, and
  selecting a try, quitting, or aborting never passed through the F9
  toggle. The recording is now flushed from `cleanup!`, which covers
  every exit path. Recordings are written to the tries root rather
  than the process's working directory.
- Ctrl-R opened Tachikoma's `.tach` screen recorder instead of
  renaming. The framework claims Ctrl+R in its default bindings and
  intercepts it before `update!` runs. Recording is now disabled for
  the selector and re-offered on `F9`, with a `● REC` indicator in
  the help bar. See `upstream-bugs.md`.
- `TriesPath` now resolves symlinks via `realpath` after ensuring the
  root exists. Previously it used only `abspath(normpath(...))`, so on
  macOS — where `/var` and `/tmp` are symlinks into `/private` — two
  spellings of the same root compared unequal, which could mislead the
  graduate and rename collision checks. This also fixes three
  pre-existing test failures that were latent on Linux CI.

- Documentation build: `docs/make.jl` failed on an unresolvable
  `@ref` to `emit_shell_init`, which was referenced from a docstring
  but never included in the manual. It now has an entry on the
  Reference page.

### Changed

- The default tries root moved from `$HOME/src/tries` to
  `$HOME/work/tries`, following `try-rs`. The two upstreams disagree:
  `try-cli` documents `~/src/tries`, `try-rs` documents and
  implements `~/work/tries`. `TRY_PATH` overrides it either way.
  **Existing users with tries under `~/src/tries` should set
  `TRY_PATH=~/src/tries` or move the directory.**

- Exit statuses moved from loose `const EXIT_*` integers to a
  module-scoped enum, `ExitCode.T`, per the project's Julia enum
  convention. Call sites read `ExitCode.USAGE` instead of
  `EXIT_USAGE`, and the names no longer leak into `TryIt`. The
  numeric values are unchanged — they are the process wire format.
  The CLI dispatchers narrow to `::Int` rather than `::ExitCode.T`,
  because `tryit clone` propagates git's own exit code verbatim
  (FR-029) and that is an arbitrary integer outside the enum; the
  enum names only the statuses TryIt itself originates.
- README: removed links to `ROADMAP.md`, `SPEC.md`, and
  `specs/001-walking-skeleton/quickstart.md`, none of which are
  present in the repository; added `try-rs` alongside `try-cli` as
  acknowledged inspiration, and documented the configuration
  environment variables.
- Documentation: dropped the remaining dead links to `SPEC.md` and
  `specs/` from `index.md`, `rationale.md`, and the module docstring.

[Unreleased]: https://github.com/s-celles/TryIt.jl/compare/v0.1.0...HEAD
