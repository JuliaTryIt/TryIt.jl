using Documenter
using TryIt

makedocs(
    sitename="TryIt.jl",
    modules=[TryIt],
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    pages=[
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Selector Interface" => "interface.md",
        "Standalone App" => "standalone-app.md",
        "Reference" => "reference.md",
        "Rationale" => "rationale.md",
        "Requirements" => "requirements.md",
        "Development" => "development.md"
    ],
    warnonly=[:missing_docs]
)

deploydocs(
    repo="github.com/JuliaTryIt/TryIt.jl.git",
    push_preview=true
)
