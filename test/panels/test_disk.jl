@testitem "panels: format_bytes renders human-readable sizes" begin
    using TryIt: format_bytes

    @test format_bytes(0) == "0 B"
    @test format_bytes(512) == "512 B"
    @test format_bytes(1024) == "1.0 KB"
    @test format_bytes(1024^2) == "1.0 MB"
    @test format_bytes(37 * 1024^2) == "37.0 MB"
    @test format_bytes(1024^3) == "1.0 GB"
    @test format_bytes(388_600 * 1024^2) == "379.5 GB"
    @test format_bytes(1024^4) == "1.0 TB"
end

@testitem "panels: parse_df_output extracts used and free bytes" begin
    using TryIt: parse_df_output

    # `df -k` on macOS. Columns: Filesystem 1024-blocks Used Available ...
    macos = """
    Filesystem 1024-blocks     Used Available Capacity  Mounted on
    /dev/disk3s5  971350180    37888 407374848    10%   /System/Volumes/Data
    """
    stats = parse_df_output(macos)
    @test stats !== nothing
    @test stats.used == 37888 * 1024
    @test stats.free == 407374848 * 1024

    # `df -k` on Linux has the same column positions.
    linux = """
    Filesystem     1K-blocks      Used Available Use% Mounted on
    /dev/nvme0n1p2 982940516 123456789 809483727  14% /
    """
    stats = parse_df_output(linux)
    @test stats !== nothing
    @test stats.used == 123456789 * 1024
    @test stats.free == 809483727 * 1024
end

@testitem "panels: parse_df_output returns nothing on unusable output" begin
    using TryIt: parse_df_output

    # Header only — no data row.
    @test parse_df_output("Filesystem 1K-blocks Used Available Use% Mounted on\n") ===
          nothing
    @test parse_df_output("") === nothing
    # Non-numeric columns must not throw.
    @test parse_df_output("Filesystem Blocks Used Avail\nfoo bar baz qux\n") === nothing
end

@testitem "panels: disk_usage returns plausible stats or nothing" begin
    using TryIt: disk_usage

    mktempdir() do dir
        stats = disk_usage(dir)
        # `df` is absent on Windows; the panel degrades to "unavailable"
        # rather than failing the frame.
        if Sys.iswindows()
            @test stats === nothing
        else
            @test stats !== nothing
            @test stats.used >= 0
            @test stats.free >= 0
        end
    end
end

@testitem "panels: disk_usage tolerates a missing path" begin
    using TryIt: disk_usage

    @test disk_usage(joinpath(tempdir(), "does-not-exist-xyz")) === nothing
end
