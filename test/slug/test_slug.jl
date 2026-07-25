@testitem "slug: UB3 corpus" begin
    using TryIt: slug

    # ASCII happy path.
    @test slug("foo bar").value == "foo-bar"
    @test slug("Hello, World!").value == "hello-world"
    @test slug("   leading and trailing   ").value == "leading-and-trailing"
    @test slug("already-kebab").value == "already-kebab"

    # Unicode fold (acceptance scenario US1.3).
    @test slug("Réécriture!! v2").value == "reecriture-v2"
    @test slug("café").value == "cafe"
    @test slug("naïve piñata").value == "naive-pinata"

    # Pure punctuation / empty / whitespace → usage error.
    @test_throws ArgumentError slug("")
    @test_throws ArgumentError slug("!!!")
    @test_throws ArgumentError slug("   ")
    @test_throws ArgumentError slug("---")

    # Dashes collapse.
    @test slug("foo   bar").value == "foo-bar"
    @test slug("foo---bar").value == "foo-bar"
    @test slug("foo___bar").value == "foo-bar"

    # Large input stays fast.
    big = repeat("Réécriture ", 400) # ~4 KiB
    t0 = time_ns()
    result = slug(big)
    elapsed_ms = (time_ns() - t0) / 1e6
    @test !isempty(result.value)
    @test elapsed_ms < 250
end

@testitem "slug: idempotence (SC-008)" begin
    using TryIt: slug
    using Random

    rng = Xoshiro(0xdeadbeef)
    for _ in 1:100
        # Random ASCII-ish input of length 1..64.
        len = rand(rng, 1:64)
        chars = Char[]
        for _ in 1:len
            push!(chars, rand(rng, ' ':'~'))
        end
        s_raw = String(chars)
        # Skip inputs that would throw (pure punctuation); idempotence
        # is only meaningful on well-formed slugs.
        try
            s1 = slug(s_raw)
            s2 = slug(s1.value)
            @test s1.value == s2.value
        catch err
            err isa ArgumentError || rethrow()
        end
    end
end

@testitem "slug: a Slug converts and prints as its value" begin
    using TryIt: slug

    s = slug("Hello, World!")

    # `string` and `print` exist so a Slug reaches string contexts as
    # its value rather than as `Slug("hello-world")`. Without them
    # every interpolation into a path or a shell command would carry
    # the struct wrapper into user-visible output.
    @test string(s) == "hello-world"
    @test sprint(print, s) == "hello-world"
    @test "$(s)" == "hello-world"
    @test joinpath("/tmp", string(s)) == "/tmp/hello-world"
end

@testitem "slug: a Slug is usable as a dictionary key" begin
    using TryIt: slug

    a = slug("Foo Bar")
    b = slug("foo!!!bar")           # same canonical form, built differently

    @test a == b
    @test hash(a) == hash(b)        # equal values must hash equally
    @test length(Set([a, b])) == 1

    d = Dict(a => 1)
    @test d[b] == 1

    # The hash is salted with `:Slug`, so a Slug and the bare String
    # holding the same characters are distinct keys. Dropping the salt
    # would silently merge the two in any mixed collection.
    mixed = Dict{Any, Int}(a => 1, "foo-bar" => 2)
    @test length(mixed) == 2
    @test mixed[a] == 1
    @test mixed["foo-bar"] == 2
end
