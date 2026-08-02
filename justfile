default:
	@just --list

test:
	julia --startup-file=no --project=@. -e 'using Pkg; Pkg.test()'

docs:
	julia --startup-file=no --project=docs docs/make.jl

format:
	julia --startup-file=no -e 'using Pkg; Pkg.activate(temp=true); Pkg.add("JuliaFormatter"); using JuliaFormatter; format(".")'
