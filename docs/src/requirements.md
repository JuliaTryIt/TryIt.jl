# Requirements status

Traceability against the EARS specification, as of the current
`main`. `spec.md` is not tracked in git; this page is the tracked
summary of it.

The spec was reconciled with the implementation on 2026-07-18: the
four divergences below were resolved by amending the requirement, and
twelve capabilities that had been built without a written requirement
were given one. All 72 requirements are now traceable to code.

Legend: **met** · **drift** (implemented, but differs from the
written requirement) · **open** (not implemented) · **unmeasured**
(no evidence either way).

## How this stays honest

Three mechanisms, all in the test suite, so drift fails CI rather
than waiting to be noticed:

- `test/spec/test_traceability.jl` — every requirement ID in
  `spec.md` must appear in `src/` or `test/`, or be listed in an
  exemption table with a reason. Stale exemptions fail too.
- `test/spec/test_docs_sync.jl` — every `Ctrl+X` in the documented
  key-binding tables must be a key the selector actually handles, and
  must appear in the `?` overlay. The documented default tries root
  must match `_resolve_tries_root`.
- The usual gates: `Pkg.test()`, a zero-dead-cross-ref
  `docs/make.jl`, and `JuliaFormatter --check`.

The two docs-sync checks exist because that drift already happened
twice: the bindings table kept listing `Ctrl-T` as create-new-try
after it moved to `Ctrl-N`, and a section documented five Tachikoma
shortcuts that `default_bindings=false` had switched off.

## Ubiquitous

| ID  | Status | Note                                                       |
| --- | ------ | ---------------------------------------------------------- |
| UB1 | met    | Amended: default is `$HOME/work/tries`, following `try-rs`. `try-cli` uses `src`; the two upstreams disagree. |
| UB2 | met    |                                                            |
| UB3 | met    | 100 % line coverage enforced by `test/coverage/gate.jl`.   |
| UB4 | met    |                                                            |
| UB5 | met    | With one caveat — see the note under ED7/ED8 below.        |
| UB6 | met    | `ExitCode.T`, a module-scoped enum.                        |

## Event-driven

| ID   | Status | Note                                                      |
| ---- | ------ | --------------------------------------------------------- |
| ED1  | met    |                                                            |
| ED2  | met    |                                                            |
| ED3  | met    | Amended: narrowed to an exact-slug or empty filter. The ambiguous case is now ED14. |
| ED4  | met    |                                                            |
| ED5  | met    |                                                            |
| ED6  | met    |                                                            |
| ED7  | met    | Failures now surface in-frame, not on stderr.              |
| ED8  | met    | Same.                                                      |
| ED9  | met    |                                                            |
| ED10 | met    |                                                            |
| ED11 | met    | Amended to `Ctrl+N`; `Ctrl+T` is the theme picker (ED15), matching `try-rs`. |
| ED12 | met    |                                                            |
| ED13 | met    | Snippet now clears a conflicting alias first (UN9).        |
| ED14 | met    | Open-or-create prompt for an ambiguous filter.             |
| ED15 | met    | Theme picker, `Ctrl+T`.                                    |
| ED16 | met    | About overlay, `Ctrl+A`.                                   |
| ED17 | met    | Key-map overlay, `?`.                                      |
| ED18 | met    | `.tach` recording on `F9`, flushed on every exit path.     |

!!! note "UB5 and the TUI"
    UB5 requires diagnostics on stderr. Tachikoma redirects stderr
    for the whole TUI session, so a `diag` call from inside a key
    handler reaches nobody — a failing `Ctrl+G` looked like a dead
    key. Selector-internal failures therefore render in the help bar
    instead. Outside the TUI, UB5 holds unchanged. The spec records
    this as an explicit exception.

## State-driven, optional, unwanted

| IDs       | Status | Note                                               |
| --------- | ------ | -------------------------------------------------- |
| SD1–SD3   | met    |                                                    |
| SD4       | met    | Disk / Preview / Legends panels; dropped below 64 cols. |
| SD5       | met    | Help bar drops bindings as the terminal narrows.    |
| SD6       | met    | The selector owns the whole key map.               |
| OF1–OF3   | met    |                                                    |
| OF4       | met    | `TRY_THEME`.                                        |
| OF5       | met    | `TRY_BACKGROUND`.                                   |
| UN1       | met    |                                                    |
| UN2       | met    | Implicit in `create_try` idempotence.              |
| UN3–UN7   | met    |                                                    |
| UN8       | met    | No `cd` into a directory that was just deleted.    |
| UN9       | met    | Shell function installs over a conflicting alias.  |

## Non-functional

| ID   | Status     | Note                                                |
| ---- | ---------- | --------------------------------------------------- |
| NF1  | met        | Amended to include `DocStringExtensions` (required by NF7). `PackageCompiler` is build-only. |
| NF2  | unmeasured | First-frame < 250 ms never benchmarked.             |
| NF3  | unmeasured | 30 Hz render rate never benchmarked.                |
| NF4  | met        | Whole suite runs headless.                          |
| NF5–NF8 | met     | SciML style, margin 92, enforced in CI.             |
| NF9  | met        | TagBot, Register, Dependabot workflows and `CITATION.bib` present. |
| NF10 | open       | Not in the General registry.                        |
| NF11 | met        | `[compat]` for every dep; `julia = "1.10"`.         |
| NF12 | met        | `build/build.jl` produces a standalone executable.  |
| NF13 | met        |                                                     |
| NF14 | met        | Aqua, no broken checks.                             |
| NF15 | met        | JET green.                                          |
| NF16 | met        | Coverage gate in CI.                                |
| NF17 | met        |                                                     |
| NF18 | met        | 3 OS × 3 Julia versions.                            |
| NF19 | met        | `TagBot.yml`, wired to `DOCUMENTER_KEY`.            |
| NF20 | met        | `Register.yml`; the bump is done in-workflow, as `RegisterAction` has no version input. |
| NF21 | met        | `dependabot.yml`, monthly, GitHub Actions only.     |
| NF22 | met        |                                                     |
| NF23 | met        |                                                     |
| NF24 | met        | Plus Interface, Standalone App, and this page.      |

## Backlog against `try-rs`

An audit of `tassiovirginio/try-rs` on 2026-07-18 found 20 gaps. One
was a defect on our side and is fixed (UN10, deleting a linked
worktree). The rest are recorded in `spec.md` §12 with `B`-prefixed
handles, deliberately in a form the traceability test does not match
so unbuilt work cannot pass as a requirement.

The largest are a `config.toml` layer (B1), multiple tries paths with
a tab bar (B2), fuzzy ranked matching instead of substring (B5), and
multi-shell setup with completions (B7).

Two divergences are deliberate rather than pending:

- **Directory naming.** `try-rs` makes the date prefix optional,
  defaults it off, and separates with a space. We keep a mandatory
  hyphenated ISO date — it is what the parser, filter, rename and
  graduate are built on, and changing it would make every existing
  try unlistable.
- **Deletion.** `try-rs` deletes immediately behind a y/n popup; we
  mark with `✗` and confirm in a batch on exit (ED9, ED10).

## Non-goals

NG1–NG4 are all respected. NG4 (no public Julia API) is the reason
`main` is the only export.

## Path to v1.0

The spec scopes v1.0 as NF9–NF12, NF19–NF21, plus a polish pass and
registration. Everything except NF10 is now met, so the remaining
work is measurement and the release itself.

The project stays on 0.x until then: `Register.yml` defaults to a
patch bump, so a release cannot leave 0.x without explicitly choosing
`major`.

1. ~~**Reconcile the spec with reality.**~~ Done 2026-07-18. One
   thing remains: `spec.md` is still untracked, so the traceability
   test *skips* in CI instead of running. Tracking it is what turns
   this from a local check into a gate.
2. ~~**Add the missing automation.**~~ Done 2026-07-18. `TagBot.yml`,
   `Register.yml`, `dependabot.yml` and `CITATION.bib` are in place;
   the version-bump logic was exercised for all three SemVer
   components before landing.
3. **Measure NF2 and NF3.** Both are numeric budgets with no
   evidence attached. A benchmark that fails CI when first-frame
   render regresses would turn two unmeasured claims into two met
   ones.
4. **Register** (NF10), which closes v1.0.

Two things worth deciding before 1.0, neither currently in the spec:

- **The animation toggle has no binding.** `Ctrl+A` used to toggle
  motion and now opens About, so `TRY_BACKGROUND=off` is the only
  route. A reduced-motion preference arguably deserves a key.
- **The TUI has only been driven headlessly.** Every check is an
  offscreen buffer assertion. Nobody has watched the animated
  background, the theme picker, or the open-or-create prompt run at
  30 Hz in a real terminal.
