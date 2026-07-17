@testitem "git: _url_basename corpus (ED5)" begin
    using TryIt: _url_basename

    # Happy-path URL corpus from research §2.
    cases = [
        "https://github.com/foo/bar.git" => "bar",
        "https://github.com/foo/bar/" => "bar",
        "https://github.com/foo/bar" => "bar",
        "git@github.com:foo/bar.git" => "bar",
        "git@github.com:foo/bar" => "bar",
        "ssh://git@github.com/foo/bar.git" => "bar",
        "ssh://git@example.com:2222/org/repo.git" => "repo",
        "/local/path/to/some-repo/" => "some-repo",
        "../relative/path/repo" => "repo",
        "repo.git" => "repo"
    ]
    for (url, expected) in cases
        @test _url_basename(url) == expected
    end

    # A URL with no real path still yields a hostname-based basename:
    # `http://example.com/` → `example.com` (not pretty, but valid).
    @test _url_basename("http://example.com/") == "example.com"

    # Truly empty basenames (empty string, bare slashes) throw.
    @test_throws ArgumentError _url_basename("")
    @test_throws ArgumentError _url_basename("/")
    @test_throws ArgumentError _url_basename("////")
end
