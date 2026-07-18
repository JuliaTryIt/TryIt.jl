# Shared data for the traceability tests. Not a @testitem file, so
# it can be `include`d from inside test items without recursing.

const SPEC_PATH = joinpath(@__DIR__, "..", "..", "spec.md")

"""
Requirements deliberately not traceable to a code annotation, with
the reason. Everything else must be referenced from `src/` or `test/`.
"""
const UNTRACEABLE = Dict(
    # Process and infrastructure — verified by the repository's shape
    # or by CI configuration, not by a line of Julia.
    "NF9" => "PkgTemplates scaffolding",
    "NF10" => "registry state",
    "NF12" => "build/build.jl",
    "NF18" => "CI matrix in CI.yml",
    "NF19" => "TagBot workflow",
    "NF20" => "Register workflow",
    "NF21" => "Dependabot config",
    "NF22" => "Documenter workflow",
    "NF23" => "README badges",
    "NF24" => "docs page set",
    # Style rules enforced by tooling rather than by tests.
    "NF5" => "SciML style, enforced by JuliaFormatter",
    "NF6" => ".JuliaFormatter.toml",
    "NF7" => "docstring templates",
    "NF8" => "line length, enforced by JuliaFormatter",
    # Performance budgets — measured, not asserted.
    "NF3" => "render rate",
    "NF4" => "headless test harness (the suite itself)",
    "NF11" => "Project.toml [compat]",
    "NF13" => "test layout",
    # Non-goals describe what is absent; nothing to annotate.
    "NG1" => "non-goal", "NG2" => "non-goal",
    "NG3" => "non-goal", "NG4" => "non-goal",
    # Behavioural, but covered by create_try idempotence.
    "UN2" => "same-day reuse"
)
