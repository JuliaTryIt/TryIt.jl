# Traceability between spec.md and the implementation.
#
# `spec.md` is not tracked in git, so these tests skip when it is
# absent rather than failing a clean checkout.

@testitem "spec: every requirement is traceable to code" begin
    include(joinpath(@__DIR__, "spec_helpers.jl"))
    isfile(SPEC_PATH) || return

    spec = read(SPEC_PATH, String)
    defined = unique([m.captures[1]
                      for m in eachmatch(r"\*\*([A-Z]{2}\d+)\.\*\*", spec)])
    @test !isempty(defined)

    src_and_tests = String[]
    for root in ("src", "test")
        for (dir, _, files) in walkdir(joinpath(@__DIR__, "..", "..", root))
            for f in files
                endswith(f, ".jl") && push!(src_and_tests, read(joinpath(dir, f), String))
            end
        end
    end
    corpus = join(src_and_tests, "\n")

    untraced = [id
                for id in defined
                if !haskey(UNTRACEABLE, id) && !occursin(Regex("\\b$(id)\\b"), corpus)]
    # A requirement with no annotation anywhere is either unimplemented
    # or implemented without anyone noticing it satisfied the spec.
    @test isempty(untraced)
end

@testitem "spec: the untraceable list has no stale entries" begin
    include(joinpath(@__DIR__, "spec_helpers.jl"))
    isfile(SPEC_PATH) || return

    spec = read(SPEC_PATH, String)
    defined = Set(m.captures[1]
    for m in eachmatch(r"\*\*([A-Z]{2}\d+)\.\*\*", spec))

    # An exemption for a requirement that no longer exists hides the
    # fact that the list is no longer being maintained.
    @test isempty(setdiff(keys(UNTRACEABLE), defined))
end
