# The extension catalogue and its listing (ED28, ED29, UN13).

@testitem "extensions: the catalogue is non-empty and well formed (ED28)" begin
    using TryIt

    @test !isempty(TryIt.EXTENSIONS)
    for ext in TryIt.EXTENSIONS
        @test !isempty(ext.name)
        @test !isempty(ext.package)
        @test !isempty(ext.summary)
        @test startswith(ext.url, "https://")
        # Names are what the user types; duplicates would make the
        # lookup silently pick one.
        @test count(e -> e.name == ext.name, TryIt.EXTENSIONS) == 1
    end
end

@testitem "extensions: lookup by name, or nothing (ED28)" begin
    using TryIt

    @test TryIt.find_extension("pluginguard") isa TryIt.Extension
    @test TryIt.find_extension("no-such-extension") === nothing
end

@testitem "extensions: state is measured, not read off the manifest (ED28)" begin
    using TryIt
    using PluginGuard

    # PluginGuard is a dependency of the test environment, so it is
    # installed *and* loadable here: the state must be `enabled`, and
    # it must have been reached by actually loading rather than by
    # observing a manifest entry.
    ext = TryIt.find_extension("pluginguard")
    @test TryIt.extension_installed(ext)
    @test TryIt.extension_state(ext) === :enabled
    @test ext.probe()
end

@testitem "extensions: an uninstalled package reads as available (ED28)" begin
    using TryIt

    absent = TryIt.Extension(
        "ghost", "DefinitelyNotAPackageAnyoneHas",
        "https://example.com/Ghost.jl", "not real", () -> false
    )
    @test !TryIt.extension_installed(absent)
    @test TryIt.extension_state(absent) === :available
end

@testitem "extensions: installed but never registering reads as broken (ED28)" begin
    using TryIt

    # The state ED28 exists for. `PluginGuard` really is installed
    # here, so `extension_installed` is true, but a probe that never
    # returns true stands in for a backend whose `__init__` failed to
    # register. Reading the manifest would have called this enabled.
    liar = TryIt.Extension(
        "liar", "PluginGuard",
        "https://example.com/Liar.jl", "never registers", () -> false
    )
    @test TryIt.extension_installed(liar)
    @test TryIt.extension_state(liar) === :broken
end

@testitem "extensions: the install hint names the active project (ED29)" begin
    using TryIt

    ext = TryIt.find_extension("pluginguard")
    cmd = TryIt.install_command(ext, "/some/env")
    @test occursin("--project=/some/env", cmd)
    @test occursin("Pkg.add", cmd)
    @test occursin(ext.url, cmd)
end

@testitem "extensions: the listing is readable without colour (ED28, UB7)" begin
    using TryIt

    # An IOBuffer is not colour-capable, so this is the piped form.
    io = IOBuffer()
    TryIt._print_extensions(io)
    text = String(take!(io))
    @test !occursin('\e', text)
    @test occursin("pluginguard", text)
    # The state must survive losing its colour, which is what the
    # glyphs are for.
    @test occursin("enabled", text) || occursin("available", text) ||
          occursin("broken", text)
    @test any(occursin(m, text) for m in values(TryIt.EXTENSION_STATE_MARKERS))
end

@testitem "extensions: the listing colours its states (ED28, UB7)" begin
    using TryIt

    io = IOContext(IOBuffer(), :color => true)
    TryIt._print_extensions(io)
    text = String(take!(io.io))
    @test occursin("\e[", text)
    @test occursin("pluginguard", text)
end

@testitem "extensions: columns align whether or not colour is on (ED28)" begin
    using TryIt

    plain = IOBuffer()
    TryIt._print_extensions(plain)
    plain_text = String(take!(plain))

    lit = IOContext(IOBuffer(), :color => true)
    TryIt._print_extensions(lit)
    # Strip the escapes back out; the visible layout must match, or
    # padding was applied after painting and the coloured rows sit at
    # a different column from the plain ones.
    lit_text = replace(String(take!(lit.io)), r"\e\[[0-9;]*m" => "")
    @test lit_text == plain_text
end

@testitem "extensions: a bad argument is a usage error (UN13)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    (code, out, err) = run_cli_subprocess("extension", "instal")
    @test code == 64
    @test isempty(out)
    @test occursin("tryit: usage:", err)
end

@testitem "extensions: bare and `list` forms agree (ED28)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    (code_bare, out_bare, _e1) = run_cli_subprocess("extension")
    (code_list, out_list, _e2) = run_cli_subprocess("extension", "list")
    @test code_bare == 0
    @test code_list == 0
    @test out_bare == out_list
    @test occursin("pluginguard", out_bare)
end

@testitem "extensions: the listing goes to stdout, not stderr (UB4, ED28)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # It is output for the caller, which is why the emitted shell
    # function has to run `extension` directly rather than capturing
    # and evaluating it.
    (_code, out, err) = run_cli_subprocess("extension")
    @test occursin("pluginguard", out)
    @test !occursin("pluginguard", err)
end

@testitem "extensions: the emitted shell function runs `extension` directly (UB4)" begin
    using TryIt

    io = IOBuffer()
    TryIt.emit_shell_init(io, "/some/tries")
    text = String(take!(io))
    # Without this the shell would `eval` the listing, which is the
    # failure UB4's clarification was written to stop.
    @test occursin("extension)", text) || occursin("|extension)", text)
end
