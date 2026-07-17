@testitem "paths: placeholder_slug_for_today picks smallest free N (ED11)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, placeholder_slug_for_today

    dir = mktempdir()
    root = TriesPath(positional=dir)
    today = Date(2026, 4, 19)

    # With no existing placeholders, the first Ctrl-T → "new-try".
    @test placeholder_slug_for_today(root, today).value == "new-try"

    # Create `new-try` → next free is `-1`.
    create_try(root, slug("new-try"), today)
    @test placeholder_slug_for_today(root, today).value == "new-try-1"

    # Add `new-try-3` (skipping 2) → smallest unused is still `-1`.
    create_try(root, slug("new-try-3"), today)
    @test placeholder_slug_for_today(root, today).value == "new-try-1"

    # Fill `-1` then `-2` → smallest unused is now `-4`.
    create_try(root, slug("new-try-1"), today)
    create_try(root, slug("new-try-2"), today)
    @test placeholder_slug_for_today(root, today).value == "new-try-4"
end

@testitem "paths: placeholder_slug ignores other dates (ED11)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, placeholder_slug_for_today

    dir = mktempdir()
    root = TriesPath(positional=dir)

    # Yesterday's `new-try` must NOT interfere with today's choice.
    create_try(root, slug("new-try"), Date(2026, 4, 18))
    @test placeholder_slug_for_today(root, Date(2026, 4, 19)).value == "new-try"
end
