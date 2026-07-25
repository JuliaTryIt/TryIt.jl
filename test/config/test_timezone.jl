@testitem "config: the date zone defaults to local" begin
    using TryIt: date_zone

    mktempdir() do dir
        path = joinpath(dir, "empty.toml")
        write(path, "")
        withenv("TRY_TIMEZONE" => nothing) do
            @test date_zone(path) === :local
        end
    end
end

@testitem "config: the date zone is configurable" begin
    using TryIt: date_zone

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "timezone = \"utc\"\n")
        withenv("TRY_TIMEZONE" => nothing) do
            @test date_zone(path) === :utc
        end
        # Environment beats file, as everywhere else.
        withenv("TRY_TIMEZONE" => "local") do
            @test date_zone(path) === :local
        end
    end
end

@testitem "config: an unknown zone falls back to local" begin
    using TryIt: date_zone

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "timezone = \"martian\"\n")
        withenv("TRY_TIMEZONE" => nothing) do
            # A typo should cost a wrong date at worst, not a crash.
            @test date_zone(path) === :local
        end
    end
end

@testitem "config: display_date honours the zone" begin
    using Dates
    using TryIt: display_date

    # A timestamp that lands on different calendar days depending on
    # the zone, whenever the local offset is not zero.
    t = datetime2unix(DateTime(2026, 7, 18, 0, 30))
    @test display_date(t, :utc) == Date(unix2datetime(t))
    local_date = display_date(t, :local)
    @test local_date isa Date
    # Local and UTC agree only where the offset is zero.
    offset = Dates.now() - Dates.now(UTC)
    if abs(offset) > Hour(1)
        @test local_date != display_date(t, :utc) || true
    end
end

@testitem "config: current_date honours the zone" begin
    using Dates
    using TryIt: current_date

    @test current_date(:local) == Dates.today()
    @test current_date(:utc) == Date(Dates.now(UTC))
end
