@testitem "JET static analysis (v0.2 enforced)" begin
    using JET
    using TryIt
    using Tachikoma

    # v0.2 promotes JET from trivial-pass to enforcement (FR-032 /
    # NF15). Reports are restricted to `TryIt` itself via
    # `target_modules`, and `Tachikoma` is on the ignore list so
    # `@test_call` does not chase dispatch into Tachikoma's
    # terminal-capture / widget internals — Tachikoma is a trusted
    # runtime dependency (SPEC NF1 as amended 2026-04-19), and any
    # inference noise inside it is not a TryIt bug.
    argv_matrix = (
        String[],
        String["init"],
        String["init", "/custom/tries"],
        String["clone", "https://example.com/foo.git"],
        String["clone", "https://example.com/foo.git", "name"],
        String["worktree", "scratch"],
        String["my-slug"],
        String["bogus", "extra", "argv"]
    )
    for argv in argv_matrix
        @test_call target_modules=(TryIt,) ignored_modules=(Tachikoma,) TryIt.cli_main(argv)
    end

    # Targeted package check stays — it catches any new drift in
    # functions outside the CLI dispatcher.
    JET.test_package(
        TryIt;
        target_modules=(TryIt,),
        ignored_modules=(Tachikoma,)
    )
end
