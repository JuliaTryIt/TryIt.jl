#!/usr/bin/env julia
# Coverage gate — parses lcov.info emitted by
# julia-actions/julia-processcoverage and fails CI when the slug
# generator drops below 100 % or overall src/ coverage drops below
# 80 %.
#
# EARS coverage: NF16 / FR-042.
#
# Called from CI as:
#   julia --startup-file=no --project=. test/coverage/gate.jl
#
# Pure Julia stdlib — no test-time deps.

using Printf

const SLUG_PATH_SUFFIX = joinpath("src", "slug.jl")
const SLUG_THRESHOLD = 1.0
const GENERAL_THRESHOLD = 0.80

struct FileCoverage
    path::String
    total::Int
    hit::Int
end

"""
Parse an LCOV `lcov.info` file into a list of per-file coverage
records. We only need the `SF:` / `DA:` / `end_of_record` lines;
other record types are ignored.
"""
function parse_lcov(lcov_path::AbstractString)
    isfile(lcov_path) ||
        error("lcov.info not found at $lcov_path — run tests with coverage=true first")
    records = FileCoverage[]
    current_path = ""
    current_total = 0
    current_hit = 0
    for line in eachline(lcov_path)
        if startswith(line, "SF:")
            current_path = strip(line[4:end])
            current_total = 0
            current_hit = 0
        elseif startswith(line, "DA:")
            # DA:<line>,<count>
            parts = split(line[4:end], ',')
            length(parts) >= 2 || continue
            count = tryparse(Int, parts[2])
            count === nothing && continue
            current_total += 1
            count > 0 && (current_hit += 1)
        elseif line == "end_of_record"
            if !isempty(current_path)
                push!(records, FileCoverage(current_path, current_total, current_hit))
            end
            current_path = ""
        end
    end
    return records
end

function threshold_for(path::AbstractString)
    endswith(path, SLUG_PATH_SUFFIX) && return SLUG_THRESHOLD
    occursin(string(Base.Filesystem.path_separator, "src", Base.Filesystem.path_separator),
        string(Base.Filesystem.path_separator, path, Base.Filesystem.path_separator)) ||
        return nothing
    # macOS / Linux path separator is /, the above handles both forms.
    occursin("/src/", path) && return GENERAL_THRESHOLD
    return nothing
end

function main()
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))
    lcov_path = joinpath(repo_root, "lcov.info")
    records = parse_lcov(lcov_path)
    failures = String[]
    checked = 0
    for rec in records
        threshold = threshold_for(rec.path)
        threshold === nothing && continue
        checked += 1
        ratio = rec.total == 0 ? 0.0 : rec.hit / rec.total
        if ratio < threshold
            pct = @sprintf("%.1f", ratio*100)
            req = round(Int, threshold * 100)
            push!(failures,
                "COVERAGE FAIL: $(rec.path) $(pct)% < $(req)% ($(rec.hit)/$(rec.total) lines)"
            )
        end
    end
    if !isempty(failures)
        for msg in failures
            println(stderr, msg)
        end
        println(stderr,
            "coverage gate: FAIL ($(length(failures)) of $(checked) files below threshold)")
        exit(1)
    end
    println("coverage gate: PASS ($(checked) files checked)")
    exit(0)
end

main()
