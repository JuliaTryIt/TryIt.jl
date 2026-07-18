# Reference

## Public entry point

```@docs
TryIt.main
```

## Exit statuses

```@docs
TryIt.ExitCode
```

## Shell integration

```@docs
TryIt.emit_shell_init
```

## Notes

`TryIt` does not expose a Julia library API
until a future major release. The only supported public entry
point is the CLI command surface documented on the
[Getting Started](getting-started.md) page. Everything else in
`src/` is an implementation detail and subject to change without
notice in 0.x releases.
