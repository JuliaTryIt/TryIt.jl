@testitem "Aqua quality checks (v0.2 enforced)" begin
    using Aqua
    using TryIt

    # v0.2 promotes Aqua from trivial-pass to hard enforcement
    # (FR-031 / NF14). No `broken=true` annotations are allowed; any
    # failure here blocks the PR.
    Aqua.test_all(
        TryIt;
        ambiguities=true,
        unbound_args=true,
        undefined_exports=true,
        project_extras=true,
        stale_deps=true,
        deps_compat=true,
        piracies=true,
        persistent_tasks=false
    )
end
