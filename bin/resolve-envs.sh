#!/usr/bin/env bash
# Re-resolve every environment that pins TryIt.
#
# Three environments carry their own Manifest.toml, and none of them
# is updated by pulling a commit that changes the package's
# dependencies:
#
#   .        the package itself
#   docs     has its own manifest, breaks `docs/make.jl`
#   @TryIt   the shared env the shell function runs against, so
#            breaking it breaks `tryit` itself
#
# Run this after adding, removing or bumping a dependency.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

for env in "." "docs" "@TryIt"; do
    printf '%-8s ' "$env"
    if julia --startup-file=no --project="$env" \
        -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()' >/dev/null 2>&1; then
        echo "ok"
    else
        echo "FAILED"
        julia --startup-file=no --project="$env" \
            -e 'using Pkg; Pkg.resolve()' 2>&1 | tail -5
        exit 1
    fi
done

echo "all environments resolved"
