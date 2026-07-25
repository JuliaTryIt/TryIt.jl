#!/usr/bin/env bash
# Re-resolve every environment that pins TryIt.
#
# Three environments carry their own Manifest.toml, and none of them
# is updated by pulling a commit that changes the package's
# dependencies:
#
#   .        the package itself
#   docs     has its own manifest, breaks `docs/make.jl`
#   test     has its own manifest; `Pkg.test` resolves a fresh
#            sandbox, so this only bites when running the test env
#            directly
#   @TryIt   the shared env the shell function runs against, so
#            breaking it breaks `tryit` itself
#
# A develop install records an ABSOLUTE path, so moving the
# repository breaks all of them at once. Re-running this fixes that
# too.
#
# Run this after adding, removing or bumping a dependency.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

for env in "." "docs" "test" "@TryIt"; do
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
