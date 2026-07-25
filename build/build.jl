#!/usr/bin/env julia
#
# Build a standalone `tryit` executable with PackageCompiler.
#
# Usage (from the repository root):
#
#     julia --startup-file=no --project=build build/build.jl [outdir]
#
# `outdir` defaults to `build/tryit-app` and is always replaced.
#
# PackageCompiler lives in `build/Project.toml` rather than the
# package's own `[deps]`, so installing TryIt as a library never
# drags in the compiler toolchain.

using PackageCompiler

const PKG_ROOT = abspath(joinpath(@__DIR__, ".."))
const OUTDIR = abspath(length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "tryit-app"))

@info "Building standalone tryit app" package=PKG_ROOT destination=OUTDIR

create_app(
    PKG_ROOT,
    OUTDIR;
    executables=["tryit" => "julia_main"],
    precompile_execution_file=joinpath(@__DIR__, "precompile_app.jl"),
    incremental=false,
    filter_stdlibs=false,
    force=true
)

@info "Done" executable=joinpath(OUTDIR, "bin", "tryit")
