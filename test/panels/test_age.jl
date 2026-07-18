@testitem "panels: format_age renders the try-rs duration shape" begin
    using TryIt: format_age

    # `(00d 13h 53m)` — zero-padded days, hours, minutes, as in the
    # reference TUI.
    @test format_age(0) == "00d 00h 00m"
    @test format_age(60) == "00d 00h 01m"
    @test format_age(3600) == "00d 01h 00m"
    @test format_age(13 * 3600 + 53 * 60) == "00d 13h 53m"
    @test format_age(43 * 86400 + 16 * 3600 + 22 * 60) == "43d 16h 22m"

    # Seconds are truncated, never rounded up — a try created 59s ago
    # is still "00m" old, not "01m".
    @test format_age(59) == "00d 00h 00m"

    # Days are not capped at two digits.
    @test format_age(365 * 86400) == "365d 00h 00m"
end

@testitem "panels: format_age clamps negative deltas" begin
    using TryIt: format_age

    # An mtime in the future (clock skew, or a file touched by another
    # machine) must not render as garbage or a negative field.
    @test format_age(-1) == "00d 00h 00m"
    @test format_age(-100000) == "00d 00h 00m"
end

@testitem "panels: try_age_seconds measures against a reference time" begin
    using TryIt: TriesPath, slug, create_try, try_age_seconds

    mktempdir() do dir
        root = TriesPath(positional=dir)
        t = create_try(root, slug("aged"))
        # `now` is passed explicitly so the test is not clock-racy.
        @test try_age_seconds(t, t.mtime) == 0.0
        @test try_age_seconds(t, t.mtime + 3600) == 3600.0
    end
end
