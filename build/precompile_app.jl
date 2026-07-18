# Execution trace recorded into the standalone app image.
#
# Mirrors the `@compile_workload` block in `src/TryIt.jl`, but drives
# the CLI layer that `julia_main` actually enters — the in-package
# workload cannot cover `cli_main` because it would need a TTY.
#
# Kept to pure and filesystem-only paths: `clone` / `worktree` shell
# out to git, which is not reliably present in a build sandbox.

using TryIt

mktempdir() do dir
    redirect_stdout(devnull) do
        TryIt._app_main(["init", dir])
        TryIt._app_main(["a-warmup-slug"])
    end
    redirect_stderr(devnull) do
        TryIt._app_main(["unknown", "arguments", "here"])
    end
end
