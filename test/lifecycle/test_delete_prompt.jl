@testitem "lifecycle: confirm_delete reads y/N (ED10)" begin
    using TryIt: confirm_delete

    # Happy path: "y" + newline → true, prompt on stderr mentions count.
    for response in ("y\n", "Y\n", "  y  \n", "Y")
        stderr_sink = IOBuffer()
        yes = confirm_delete(
            3; stdin_io=IOBuffer(response), stderr_io=stderr_sink
        )
        @test yes === true
        prompt = String(take!(stderr_sink))
        @test occursin("Delete 3 tries? [y/N]", prompt)
    end

    # Anything else → false.
    for response in ("n\n", "N\n", "\n", "yes\n", "YES\n", "yeah\n", " \n")
        @test confirm_delete(
            2; stdin_io=IOBuffer(response), stderr_io=IOBuffer()
        ) === false
    end

    # N <= 0 short-circuits to false without prompting.
    stderr_sink = IOBuffer()
    @test confirm_delete(
        0; stdin_io=IOBuffer("y\n"), stderr_io=stderr_sink
    ) === false
    @test isempty(String(take!(stderr_sink)))
end
