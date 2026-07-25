# Selector state, free of any UI type.
#
# Every field the event loop reads or writes lives here except the two
# that are irreducibly Tachikoma's — the terminal handle and the
# resolved background object — which stay on the wrapper in
# selector.jl. Splitting them out is what lets a second frontend drive
# the same state without reimplementing it.

"""
Mutable state backing the try selector, independent of any frontend.

Holds every piece of state the event loop needs. Output (the `cd`
command) is NOT written from within the reducer — the TUI captures
stdout while the app is running, so the decision is recorded here and
`cli_main` emits the shell command after the loop returns.

Wrapped by `SelectorSession`, which adds the frontend-specific handles
and forwards property access here, so `session.filter` and
`session.state.filter` are the same slot.

EARS coverage: ED1, ED2, ED3, ED4, ED12, SD1, UN7.
"""
@kwdef mutable struct SelectorState
    """
    Resolved tries root.
    """
    root::TriesPath
    """
    Snapshot of every try at selector-open time, mtime-desc.
    """
    all_tries::Vector{Try} = Try[]
    """
    Current filter string; empty matches everything.
    """
    filter::String = ""
    """
    1-based cursor into `visible`. `0` when `visible` is empty.
    """
    cursor::Int = 0
    """
    Filter-applied projection of `all_tries`.
    """
    visible::Vector{Try} = Try[]
    """
    Decision taken when the event loop exits: `:none`, `:cd`, `:quit`,
    `:interrupted`, `:usage_error`, `:clone`, `:fetch`.
    """
    exit_action::Symbol = :none
    """
    Absolute path to emit with `cd` when `exit_action == :cd`.
    """
    exit_path::String = ""
    """
    URL to hand to `clone` or `fetch` when `exit_action` is one of
    those. Kept apart from `exit_path`, which is always a local path —
    one field meaning two different things is how a `cd` into a URL
    eventually happens.
    """
    exit_url::String = ""
    """
    Set to `true` to terminate the event loop.
    """
    done::Bool = false
    """
    Index into `visible` of the top-most rendered row (SD3). `0` when `visible` is empty.
    """
    viewport_top::Int = 0
    """
    Current terminal dimensions `(rows, cols)`; refreshed on every redraw.
    """
    terminal_size::Tuple{Int, Int} = (24, 80)
    """
    Sub-mode: `:normal` (default), `:rename` (Ctrl-R), or `:choose`
    (open-or-create prompt). SD2-masked in `:rename`.
    """
    mode::Symbol = :normal
    """
    Highlighted action while in `:choose`: `:open` or `:create`.
    """
    choice::Symbol = :open
    """
    Transient message shown in the help bar. The TUI redirects stderr
    for the whole session, so `diag` output from inside the reducer
    is invisible — failures have to be surfaced in-frame.
    """
    notice::String = ""
    """
    Which date `Ctrl-P` will apply while in `:datepick`: `:mtime` or
    `:today`.
    """
    date_choice::Symbol = :mtime
    """
    Cursor into the background name table while in `:animation`.
    """
    anim_index::Int = 1
    """
    Animation active when the picker opened, restored if cancelled.
    """
    anim_before::String = "fog"
    """
    Cursor into the opacity name table while in `:opacity`.
    """
    opacity_index::Int = 3
    """
    Opacity active when the picker opened, restored if cancelled.
    """
    opacity_before::Float64 = 0.25
    """
    Cursor into the documentation pages while in `:docs`.
    """
    doc_index::Int = 1
    """
    Scroll offset within the current docs page.
    """
    doc_offset::Int = 0
    """
    Cursor into the frontend's theme table while in `:theme`.
    """
    theme_index::Int = 1
    """
    Theme active when the picker opened, restored if it is cancelled.
    """
    theme_before::String = ""
    """
    Input line contents while in `:rename`. Empty otherwise.
    """
    rename_buf::String = ""
    """
    Absolute paths flagged for delete on selector exit (ED9 / ED10).
    """
    marked_for_delete::Set{String} = Set{String}()
    """
    Badge cache keyed by try path. Populated lazily; `detect_badges`
    touches the filesystem and the view runs every frame.
    """
    badge_cache::Dict{String, Vector{Symbol}} = Dict{String, Vector{Symbol}}()
    """
    Path the `preview` field currently describes. Empty when none.
    """
    preview_path::String = ""
    """
    Directory listing of the selected try, for the preview panel.
    """
    preview::Vector{PreviewEntry} = PreviewEntry[]
    """
    Filesystem stats for the tries root. `nothing` when unavailable.
    """
    disk::Union{Nothing, DiskStats} = nothing
    """
    Frame counter driving the background animation. There is no tick
    event; the view runs every frame and advances this itself.
    """
    tick::Int = 0
    """
    Whether to draw the frames-per-second readout. Read once at open
    from `configured_show_fps`.
    """
    show_fps::Bool = false
    """
    Rolling frame-rate estimate, advanced once per rendered frame when
    `show_fps` is set.
    """
    fps::FpsMeter = FpsMeter()
end
