# Development

## Changing a dependency breaks three environments

This is the single most common way to break a working checkout, and
nothing detects it automatically — the failure surfaces as a
precompilation error the next time you run `tryit`:

```text
ERROR: Package TryIt does not have TOML in its dependencies
```

Three environments each carry their own `Manifest.toml`, and **none
of them is updated by pulling a commit that changes dependencies**:

| Environment | What breaks when it goes stale |
| ----------- | ------------------------------ |
| `.`         | `Pkg.test()`                   |
| `docs`      | `docs/make.jl`                 |
| `@TryIt`    | **`tryit` itself** — the shell function runs against it |

`@TryIt` is the one that bites, because it breaks the tool rather
than the build, and it is the one a contributor is least likely to
think of.

After adding, removing or bumping any dependency:

```sh
./bin/resolve-envs.sh
```

That resolves all three and reports which failed. Doing it by hand
means three separate `Pkg.resolve()` invocations, and forgetting the
third leaves `tryit` broken while every test passes.

## Gates

Everything below runs in CI; run it locally before pushing.

```sh
julia --startup-file=no --project=.    -e 'using Pkg; Pkg.test()'
julia --startup-file=no --project=docs docs/make.jl
julia --startup-file=no -e 'using Pkg; Pkg.activate(temp=true);
    Pkg.add("JuliaFormatter"); using JuliaFormatter; format(".")'
```

Check the **exit status**, not the output. A pipeline like
`… | tail -5` or a trailing `&& echo ok` will report success for a
command that failed — that has already produced two false "passing"
readings in this project's history, once masking a build error and
once masking a docs failure.

## Guards worth knowing about

Three tests exist to catch drift rather than defects, and each has
caught something real:

- `test/spec/test_traceability.jl` — every requirement ID in
  `spec.md` must appear in `src/` or `test/`, or carry a written
  exemption. It found twelve capabilities that had been built with no
  written requirement.
- `test/spec/test_docs_sync.jl` — every documented `Ctrl+X` must be a
  key the selector handles and must appear in the `?` overlay; the
  documented default tries root must match the code.
- `test/docs/test_embedded_docs.jl` — the manual embedded for the
  in-app browser must match `docs/src`. It caught the embedding going
  stale because Julia does not invalidate a precompiled image for a
  file that is merely `read`; `include_dependency` fixed it.

When one of these fails, the fix is usually the documentation or the
spec, not the test.

## Adding a key binding

The selector owns its whole key map (`default_bindings=false`), so a
new binding needs four things, and the guards enforce the last two:

1. A branch in `Tachikoma.update!` in `src/selector.jl`.
2. A mapping in `press_keys!` in `test/tachikoma_helpers.jl` —
   without it the keystroke silently lands in the filter and the test
   passes for the wrong reason.
3. A row in `HELP_KEYS`, which is the `?` overlay.
4. A row in the key-binding table in `docs/src/interface.md`.
