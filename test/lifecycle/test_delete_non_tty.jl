@testitem "lifecycle: confirm_delete fails safe on EOF stdin (ED10)" begin
    using TryIt: confirm_delete

    # Empty IOBuffer → readline returns "" → confirm returns false.
    @test confirm_delete(
        1; stdin_io=IOBuffer(""), stderr_io=IOBuffer()
    ) === false

    # Closed IOBuffer is handled via the try/catch around readline.
    closed = IOBuffer()
    close(closed)
    @test confirm_delete(
        1; stdin_io=closed, stderr_io=IOBuffer()
    ) === false
end

@testitem "lifecycle: execute_deletes! is best-effort (ED10)" begin
    using TryIt: execute_deletes!

    dir = mktempdir()
    a = joinpath(dir, "a")
    b = joinpath(dir, "b")
    missing_path = joinpath(dir, "never-existed")
    mkpath(a)
    mkpath(b)

    # Mix real + missing paths; execute_deletes! skips the missing one.
    deleted = execute_deletes!([a, missing_path, b])
    @test deleted == 2
    @test !isdir(a)
    @test !isdir(b)
end
