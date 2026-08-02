using Documenter
using TryIt

makedocs(
    sitename="TryIt.jl",
    modules=[TryIt],
    checkdocs=:none,
    format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
    pages=[
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Selector Interface" => "interface.md",
        "ManyUI Frontends" => "frontends.md",
        "Standalone App" => "standalone-app.md",
        "Reference" => "reference.md",
        "Rationale" => "rationale.md",
        "Requirements" => "requirements.md",
        "Development" => "development.md"
    ]
)

if get(ENV, "CI", "false") == "true"
    deploydocs(
        repo="github.com/JuliaTryIt/TryIt.jl.git",
        push_preview=true
    )
end
