# ManyUI frontend for the selector.
#
# The selector's filesystem and lifecycle state remains in SelectorState.
# This file translates that state into one high-level widget tree and keeps
# target selection outside the application. A future Dear ImGui integration
# can therefore add another SelectorFrontend and launch method without
# rebuilding the selector itself.

"""
Frontend used to display the interactive selector.

`SelectorFrontend` is deliberately smaller than a rendering backend: it is
TryIt's policy seam. Implementations decide how a shared ManyUI widget factory
is launched, while [`manyui_selector`](@ref) owns the application itself.
"""
abstract type SelectorFrontend end

"""
The original, full-featured Tachikoma selector.
"""
struct TachikomaFrontend <: SelectorFrontend end

"""
ManyUI rendered directly in the local terminal.
"""
struct ManyUITUIFrontend <: SelectorFrontend end

"""
ManyUI rendered as native browser DOM controls.
"""
struct WebNativeFrontend <: SelectorFrontend
    port::Int
    function WebNativeFrontend(port::Integer=8000)
        1 <= port <= 65535 || throw(ArgumentError("port must be in 1:65535"))
        return new(Int(port))
    end
end

"""
ManyUI rendered as a terminal grid transported to the browser.
"""
struct WebTUIFrontend <: SelectorFrontend
    port::Int
    function WebTUIFrontend(port::Integer=8000)
        1 <= port <= 65535 || throw(ArgumentError("port must be in 1:65535"))
        return new(Int(port))
    end
end

frontend_name(::TachikomaFrontend) = "tachikoma"
frontend_name(::ManyUITUIFrontend) = "tui"
frontend_name(::WebNativeFrontend) = "webnative"
frontend_name(::WebTUIFrontend) = "webtui"

requires_terminal(::TachikomaFrontend) = true
requires_terminal(::ManyUITUIFrontend) = true
requires_terminal(::SelectorFrontend) = false

"""
Resolve a selector frontend by name.

Supported names are `tachikoma`, `tui`, `webnative`, and `webtui`.
The three non-legacy modes all use the same ManyUI widget tree.
"""
function selector_frontend(name::Union{Symbol, AbstractString}; port::Integer=8000)
    key = lowercase(strip(String(name)))
    key == "tachikoma" && return TachikomaFrontend()
    key == "tui" && return ManyUITUIFrontend()
    key in ("webnative", "native") && return WebNativeFrontend(port)
    key in ("webtui", "web") && return WebTUIFrontend(port)
    throw(ArgumentError(
        "unknown frontend '$name' (expected tachikoma, tui, webnative, or webtui)"))
end

"""
Resolve the selector frontend from `TRY_FRONTEND` and `TRY_WEB_PORT`.

The shared ManyUI TUI is the default. `tachikoma` explicitly selects the
legacy selector during the migration.
"""
function configured_selector_frontend(env=ENV)
    name = get(env, "TRY_FRONTEND", "tui")
    raw_port = get(env, "TRY_WEB_PORT", "8000")
    port = tryparse(Int, raw_port)
    port === nothing && throw(ArgumentError(
        "TRY_WEB_PORT must be an integer in 1:65535"))
    return selector_frontend(name; port=port)
end

"""
Backend-neutral description of a TryIt animated background.

The name, opacity and preset are application data. Terminal cells, DOM/CSS,
and a future Dear ImGui draw list are projection details and deliberately do
not appear in this type.
"""
struct SelectorBackgroundEffect
    name::Symbol
    intensity::Float64
    preset::Int
end

background_name(effect::SelectorBackgroundEffect) = String(effect.name)

function configured_background_preset(env=ENV)
    raw = get(env, BACKGROUND_PRESET_ENV, "1")
    return max(1, something(tryparse(Int, strip(raw)), 1))
end

"""
Resolve every TryIt background name to a backend-neutral effect.
"""
function selector_background_effect(
        name::Union{Symbol, AbstractString}=configured_animation();
        intensity::Real=configured_opacity(),
        preset::Integer=configured_background_preset())
    key = lowercase(strip(String(name)))
    key == "wash" && (key = "fog")
    key in BACKGROUND_OFF_NAMES && (key = "off")
    key in BACKGROUND_NAMES || (key = "fog")
    return SelectorBackgroundEffect(Symbol(key), clamp(Float64(intensity), 0.0, 1.0),
        max(1, Int(preset)))
end

"""
A ManyUI composition root that paints an animated effect below its child.

It is an ordinary widget: painter order puts `render!` below the child tree.
Projection-specific methods translate the same `effect` into terminal cells
or browser CSS.
"""
mutable struct SelectorBackgroundWidget <: ManyUI.Widget
    node::ManyUI.WidgetNode
    effect::SelectorBackgroundEffect
    tick::ManyUI.Reactive{Int}
end

function SelectorBackgroundWidget(content::ManyUI.Widget;
        effect::SelectorBackgroundEffect=selector_background_effect())
    w = SelectorBackgroundWidget(
        ManyUI.WidgetNode(; id=:tryit_background,
            classes=[:tryit_background], type_name=:SelectorBackground),
        effect,
        ManyUI.Reactive(0; kind=ManyUI.Dirty.PAINT))
    ManyUI.attach_reactives!(w)
    ManyUI.mount!(w, content)
    return w
end

const _BG_BASE = (0x12, 0x12, 0x18)
const _BG_PALETTE = (
    (0x95, 0x58, 0xb2),
    (0x40, 0x6c, 0xb4),
    (0x38, 0x91, 0x26),
    (0xcb, 0x3c, 0x33)
)

@inline function _bg_lerp(a, b, amount)
    t = clamp(Float64(amount), 0.0, 1.0)
    return ntuple(i -> round(Int, a[i] + (b[i] - a[i]) * t), 3)
end

@inline _bg_color(rgb) = ManyUI.rgb(rgb[1], rgb[2], rgb[3])

function _background_sample(effect::SelectorBackgroundEffect, x, y, width, height, tick)
    name = effect.name
    if name === :fog
        n = Tachikoma.fbm(x * 0.09 + tick * 0.006,
            y * 0.18 + tick * 0.0042)
        return (clamp(n, 0.0, 1.0), 1 + mod(floor(Int, 4n), 4))
    elseif name === :aurora
        row = y / max(1, height)
        wave = sin(x * 0.06 + tick * 0.02) +
               0.6sin(x * 0.017 - tick * 0.034)
        return (clamp(exp(-8 * abs(row - 0.25 - 0.12wave)), 0.0, 1.0),
            1 + mod(floor(Int, 4row), 4))
    elseif name === :plasma
        t = tick * 0.035
        n = sin(x * 0.18 + t) + sin(y * 0.36 + 0.8t) +
            sin((x + 2y) * 0.09 + 1.3t)
        amount = clamp((n / 3 + 1) / 2, 0.0, 1.0)
        return (0.3 + 0.7abs(sin(amount * 4pi)), 1 + mod(floor(Int, 4amount), 4))
    elseif name === :rain
        phase = Tachikoma.noise(x * 0.7)
        rate = 0.5 + Tachikoma.noise(x * 1.9 + 11.0)
        head = mod(phase * height + tick * 0.12 * rate * height, max(1, height))
        behind = mod(y - head, max(1, height))
        return (exp(-behind / 3), 1 + mod(x, 4))
    elseif name === :pulse
        return (Tachikoma.breathe(tick; period=180),
            1 + mod(floor(Int, 4x / max(1, width)), 4))
    else # mesh
        n = 0.5 + 0.5sin(x * 0.18 + tick * 0.015 + sin(y * 0.31))
        return (n, 1 + mod(fld(x, 8) + fld(y, 4), 4))
    end
end

function _render_glyph_background!(w::SelectorBackgroundWidget, buf, name::Symbol)
    width, height = size(buf)
    glyphs = name === :dotwave ? ('⡀', '⢀', '⠠', '⠐', '⠈') :
             name === :phylo ? ('│', '├', '─', '└', '┬') :
             ('╱', '╲', '─', '┼', '│')
    color = _bg_color(_BG_PALETTE[1 + mod(w.effect.preset - 1, 4)])
    style = ManyUI.Style(; fg=color, dim=true)
    tick = w.tick[]
    for y in 1:height, x in 1:width

        phase = x + 2y + fld(tick, 2) + 3w.effect.preset
        threshold = name === :dotwave ? 3 : 7
        mod(phase + floor(Int, 3sin(0.2x + 0.04tick)), threshold) == 0 || continue
        glyph = glyphs[1 + mod(phase, length(glyphs))]
        ManyUITUI.set_cell!(buf, x, y, string(glyph), style)
    end
    return nothing
end

function ManyUITUI.render!(w::SelectorBackgroundWidget,
        buf::AbstractMatrix{ManyUITUI.Cell})::Nothing
    effect = w.effect
    effect.name === :off && return nothing
    effect.name in (:dotwave, :phylo, :clado) &&
        return _render_glyph_background!(w, buf, effect.name)

    width, height = size(buf)
    tick = w.tick[]
    for y in 1:height, x in 1:width

        amount, palette_index = _background_sample(effect, x, y, width, height, tick)
        target = _BG_PALETTE[palette_index]
        mixed = _bg_lerp(_BG_BASE, target, amount * effect.intensity)
        ManyUITUI.set_cell!(buf, x, y, " ", ManyUI.Style(; bg=_bg_color(mixed)))
    end
    return nothing
end

const _WEB_BACKGROUND_CSS = """
<style>
@keyframes tryit-drift { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }
@keyframes tryit-pulse { 0%, 100% { filter: saturate(.8) brightness(.75); } 50% { filter: saturate(1.35) brightness(1.15); } }
.tryit-background { position: relative; width: 100%; min-height: 100vh; background-color: #121218; }
.tryit-background > .manyui-container { position: relative; z-index: 1; }
</style>
"""

function _web_background_style(effect::SelectorBackgroundEffect)
    alpha = effect.intensity
    name = effect.name
    name === :off && return "background: #121218"
    name === :fog &&
        return "background: radial-gradient(circle at 20% 20%, rgba(149,88,178,$alpha), transparent 42%), radial-gradient(circle at 80% 70%, rgba(64,108,180,$alpha), transparent 45%), #121218; background-size: 180% 180%; animation: tryit-drift 12s ease infinite"
    name === :aurora &&
        return "background: linear-gradient(135deg, rgba(56,145,38,$alpha), rgba(64,108,180,$alpha), rgba(149,88,178,$alpha), #121218); background-size: 300% 300%; animation: tryit-drift 9s ease infinite"
    name === :plasma &&
        return "background: conic-gradient(from 45deg, rgba(149,88,178,$alpha), rgba(64,108,180,$alpha), rgba(56,145,38,$alpha), rgba(203,60,51,$alpha), rgba(149,88,178,$alpha)); background-size: 220% 220%; animation: tryit-drift 7s linear infinite"
    name === :rain &&
        return "background: repeating-linear-gradient(100deg, transparent 0 18px, rgba(56,145,38,$alpha) 20px, transparent 22px 38px), #121218; background-size: 100% 180%; animation: tryit-drift 5s linear infinite"
    name === :pulse &&
        return "background: radial-gradient(circle, rgba(149,88,178,$alpha), rgba(64,108,180,$alpha), #121218 70%); animation: tryit-pulse 4s ease-in-out infinite"
    name === :mesh &&
        return "background: repeating-conic-gradient(from 30deg, rgba(149,88,178,$alpha) 0 12deg, rgba(64,108,180,$alpha) 12deg 24deg, rgba(56,145,38,$alpha) 24deg 36deg, transparent 36deg 48deg), #121218; background-size: 120px 120px; animation: tryit-drift 16s linear infinite"
    name === :dotwave &&
        return "background: radial-gradient(circle, rgba(149,88,178,$alpha) 1px, transparent 2px), #121218; background-size: 12px 8px; animation: tryit-drift 10s linear infinite"
    name === :phylo &&
        return "background: repeating-linear-gradient(60deg, transparent 0 30px, rgba(56,145,38,$alpha) 31px 32px, transparent 33px 60px), repeating-linear-gradient(-60deg, transparent 0 30px, rgba(64,108,180,$alpha) 31px 32px, transparent 33px 60px), #121218; background-size: 180% 180%; animation: tryit-drift 18s linear infinite"
    return "background: repeating-linear-gradient(45deg, transparent 0 24px, rgba(149,88,178,$alpha) 25px 26px, transparent 27px 48px), repeating-linear-gradient(-45deg, transparent 0 24px, rgba(203,60,51,$alpha) 25px 26px, transparent 27px 48px), #121218; background-size: 160% 160%; animation: tryit-drift 14s linear infinite"
end

function ManyUIWeb.to_html(w::SelectorBackgroundWidget)
    effect = w.effect
    inner = join((ManyUIWeb.to_html(child) for child in ManyUI.children(w)))
    class = "tryit-background tryit-background--$(background_name(effect))"
    return string(_WEB_BACKGROUND_CSS, "<div id=\"tryit_background\" class=\"",
        class, "\" style=\"", _web_background_style(effect), "\">", inner, "</div>")
end

function _start_background_animation!(w::SelectorBackgroundWidget, stop::Base.RefValue{Bool})
    w.effect.name === :off && return nothing
    period = 1 / configured_fps()
    @async begin
        while !stop[]
            app = ManyUI.app(w)
            if app !== nothing
                isopen(app) || break
                w.tick[] = w.tick[] + 1
            end
            sleep(period)
        end
    end
    return nothing
end

const MANYUI_SELECTOR_STYLESHEET = ManyUITUI.parse_css("""
    #screen  { layout: column; padding: 1; gap: 1; }
    #title   { color: #7dd3fc; shrink: 0; }
    #filter  { border: round #475569; height: 1; shrink: 0; }
    #folders { border: round #475569; grow: 1; }
    #actions { layout: row; gap: 1; shrink: 0; }
    #status  { color: #94a3b8; shrink: 0; }
    #preview { border: round #475569; height: 6; shrink: 0; }
""")

_manyui_try_label(t::Try) = basename(t.path)

function _manyui_status(m::SelectorSession)
    count = length(m.visible)
    noun = count == 1 ? "try" : "tries"
    return "$count $noun — $(m.root.root)"
end

function _manyui_preview(m::SelectorSession)
    refresh_panels!(m)
    isempty(m.preview) && return "No files to preview"
    return join((entry.isdir ? "$(entry.name)/" : entry.name for entry in m.preview), '\n')
end

function _manyui_select!(m::SelectorSession, list, preview)
    idx = ManyUI.row_cursor(list)
    if 1 <= idx <= length(m.visible)
        m.cursor = idx
        preview.text[] = _manyui_preview(m)
    end
    return nothing
end

function _manyui_sync!(m::SelectorSession, list, status, preview)
    ManyUI.set_items!(list, copy(m.visible))
    status.text[] = _manyui_status(m)
    if isempty(m.visible)
        preview.text[] = "No matching try"
        return nothing
    end
    m.cursor = clamp(m.cursor, 1, length(m.visible))
    ManyUI.set_cursor!(list, m.cursor)
    preview.text[] = _manyui_preview(m)
    return nothing
end

function _manyui_open_selected!(m::SelectorSession, list)
    idx = ManyUI.row_cursor(list)
    1 <= idx <= length(list.items) || return nothing
    selected = list.items[idx]
    m.cursor = idx
    m.exit_action = :cd
    m.exit_path = selected.path
    m.done = true
    return nothing
end

"""
Build TryIt's high-level ManyUI selector for `session`.

The returned widget tree is backend-neutral. It is used unchanged by the
terminal, WebNative, and WebTUI launch paths; selection and filtering mutate
the existing `SelectorState`, so the shell/lifecycle layer remains shared with
the Tachikoma frontend.
"""
function manyui_selector(m::SelectorSession;
        effect::SelectorBackgroundEffect=selector_background_effect(),
        animate::Bool=false,
        animation_stop::Base.RefValue{Bool}=Ref(false))::ManyUI.Widget
    list_ref = Ref{Any}()
    status_ref = Ref{Any}()
    preview_ref = Ref{Any}()

    filter_box = ManyUI.TextInput(m.filter, w -> _manyui_open_selected!(m, list_ref[]);
        on_change=w -> begin
            m.filter = w.text[]
            refresh_visible!(m)
            _manyui_sync!(m, list_ref[], status_ref[], preview_ref[])
        end,
        placeholder="Filter or type a new try name…",
        id=:filter)

    preview = ManyUI.Label(""; id=:preview)
    folders = ManyUI.List(copy(m.visible),
        w -> _manyui_open_selected!(m, w);
        format=_manyui_try_label,
        on_change=w -> _manyui_select!(m, w, preview),
        id=:folders)
    status = ManyUI.Label(_manyui_status(m); id=:status)

    list_ref[] = folders
    status_ref[] = status
    preview_ref[] = preview
    preview.text[] = _manyui_preview(m)

    open_button = ManyUI.Button("Open", _ -> _manyui_open_selected!(m, folders);
        id=:open)
    create_button = ManyUI.Button(
        "Create", _ -> begin
            _create_from_filter!(m)
            m.done || (status.text[] = "Type a name before creating a try")
            nothing
        end;
        id=:create)
    refresh_button = ManyUI.Button(
        "Refresh", _ -> begin
            m.all_tries = list_tries(m.root)
            refresh_visible!(m)
            _manyui_sync!(m, folders, status, preview)
        end; id=:refresh)
    quit_button = ManyUI.Button("Quit", _ -> begin
            m.exit_action = :quit
            m.done = true
            nothing
        end; id=:quit)

    actions = ManyUI.Container(open_button, create_button, refresh_button, quit_button;
        id=:actions)
    content = ManyUI.Container(
        ManyUI.Label("TryIt — ephemeral workspaces"; id=:title),
        filter_box,
        folders,
        actions,
        status,
        preview;
        id=:screen)
    canvas = SelectorBackgroundWidget(content; effect=effect)
    animate && _start_background_animation!(canvas, animation_stop)
    return canvas
end

function _launch_manyui(factory, ::ManyUITUIFrontend)
    return ManyUITUI.launch(factory;
        stylesheet=MANYUI_SELECTOR_STYLESHEET, wait=false)
end

function _launch_manyui(factory, frontend::WebNativeFrontend)
    return ManyUITUI.launch(factory, ManyUI.WebNative();
        port=frontend.port, wait=false)
end

function _launch_manyui(factory, frontend::WebTUIFrontend)
    backend = ManyUIWeb.WebBackend(port=frontend.port)
    return ManyUITUI.launch(factory, backend;
        stylesheet=MANYUI_SELECTOR_STYLESHEET, wait=false)
end

_selector_handle_isopen(handle) = isopen(handle)

# ManyUIWeb 0.1's WebNative handle predates the common launch-handle contract:
# it has close/wait but no Base.isopen method. Keep the compatibility shim at
# this boundary instead of extending a foreign function for a foreign type.
_selector_handle_isopen(handle::ManyUIWeb.WebNativeServer) = isopen(handle.http_server)

function _drive_manyui!(handle, m::SelectorSession)
    try
        while _selector_handle_isopen(handle) && !m.done
            sleep(0.05)
        end
    catch err
        if err isa InterruptException
            m.exit_action = :interrupted
            m.done = true
        else
            rethrow()
        end
    finally
        _selector_handle_isopen(handle) && close(handle)
        try
            wait(handle)
        catch err
            err isa InterruptException || rethrow()
        end
    end
    return nothing
end

function run_selector!(m::SelectorSession, ::TachikomaFrontend)
    _with_terminal_stdout() do
        Tachikoma.app(m; default_bindings=false, fps=configured_fps())
    end
    return m
end

function run_selector!(m::SelectorSession, frontend::SelectorFrontend)
    animation_stop = Ref(false)
    native = frontend isa WebNativeFrontend
    factory = () -> manyui_selector(m;
        animate=(!native), animation_stop=animation_stop)
    try
        _with_terminal_stdout() do
            handle = _launch_manyui(factory, frontend)
            _drive_manyui!(handle, m)
        end
    finally
        animation_stop[] = true
    end
    return m
end

"""
Launch the interactive selector with an explicit frontend.

`frontend` accepts a `SelectorFrontend`, a symbol, or one of the strings
accepted by [`selector_frontend`](@ref). The returned `SelectorSession`
contains the resulting action and path. This is the programmatic entry point
for embedding TryIt above ManyUI.
"""
function launch_selector(; frontend::Union{SelectorFrontend, Symbol, AbstractString}=:tui,
        port::Integer=8000, root::TriesPath=TriesPath())
    target = frontend isa SelectorFrontend ? frontend :
             selector_frontend(frontend; port=port)
    session = open_session(root; tachikoma=(target isa TachikomaFrontend))
    return run_selector!(session, target)
end
