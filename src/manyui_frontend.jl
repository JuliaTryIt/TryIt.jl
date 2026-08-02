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
    background::Union{Nothing, SelectorBackground}
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
    opacity = clamp(Float64(intensity), 0.0, 1.0)
    variant = max(1, Int(preset))
    background = resolve_background(key, variant)
    background === nothing || (background = with_intensity(background, opacity))
    return SelectorBackgroundEffect(Symbol(key), opacity, variant, background)
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
    keymap::Dict{ManyUI.KeyEvent, Function}
    on_popup_close::Function
    on_unmapped_key::Function
end

function SelectorBackgroundWidget(content::ManyUI.Widget;
        effect::SelectorBackgroundEffect=selector_background_effect(),
        keymap::Dict{ManyUI.KeyEvent, Function}=Dict{ManyUI.KeyEvent, Function}(),
        on_popup_close::Function=() -> nothing,
        on_unmapped_key::Function=() -> false)
    w = SelectorBackgroundWidget(
        ManyUI.WidgetNode(; id=:tryit_background,
            classes=[:tryit_background], type_name=:SelectorBackground),
        effect,
        ManyUI.Reactive(0; kind=ManyUI.Dirty.PAINT),
        keymap,
        on_popup_close,
        on_unmapped_key)
    ManyUI.attach_reactives!(w)
    ManyUI.mount!(w, content)
    return w
end

ManyUI.on_popup_close!(w::SelectorBackgroundWidget)::Nothing =
    (w.on_popup_close(); nothing)

"A backend-neutral, two-column legend with a stable colour per badge."
mutable struct SelectorLegendWidget <: ManyUI.Widget
    node::ManyUI.WidgetNode
    badges::Vector{Symbol}
end

function SelectorLegendWidget(; id::Symbol=:legend,
        badges::AbstractVector{Symbol}=BADGE_ORDER)
    return SelectorLegendWidget(
        ManyUI.WidgetNode(; id=id, classes=[:tryit_legend],
            type_name=:SelectorLegend),
        collect(badges))
end

# Like a List, the legend consumes the area offered by its panel.
ManyUI.measure(::SelectorLegendWidget, available::ManyUI.Size)::ManyUI.Size =
    available

"A zero-sized TUI sibling projected as a fixed modal layer by WebNative."
mutable struct SelectorModalLayer <: ManyUI.Widget
    node::ManyUI.WidgetNode
end

function SelectorModalLayer(dialogs::ManyUI.Widget...)
    layer = SelectorModalLayer(ManyUI.WidgetNode(; id=:modal_layer,
        classes=[:modal_layer], type_name=:SelectorModalLayer))
    for dialog in dialogs
        ManyUI.mount!(layer, dialog)
    end
    ManyUI.set_visible!(layer, false)
    return layer
end

ManyUI.measure(::SelectorModalLayer, ::ManyUI.Size)::ManyUI.Size = ManyUI.Size(0, 0)

# This is the application composition root, not a content-sized decoration.
# Returning the offered viewport is what lets terminal and WebTUI targets use
# every row and column instead of collapsing to the 80x24 intrinsic minimum.
ManyUI.measure(::SelectorBackgroundWidget, available::ManyUI.Size)::ManyUI.Size = available

function ManyUI.on_event!(w::SelectorBackgroundWidget,
        dispatch::ManyUI.Dispatch{ManyUI.KeyEvent})::Nothing
    action = get(w.keymap, ManyUI.event(dispatch), nothing)
    if action === nothing
        w.on_unmapped_key() && ManyUI.consume!(dispatch)
        return nothing
    end
    action() === false && return nothing
    ManyUI.consume!(dispatch)
    return nothing
end

_manyui_color(::Tachikoma.NoColor) = ManyUI.COLOR_UNSET
_manyui_color(c::Tachikoma.Color256) = ManyUI.ansi256(Int(c.code))
_manyui_color(c::Tachikoma.ColorRGB) = ManyUI.rgb(c.r, c.g, c.b)

function _manyui_style(style::Tachikoma.Style)
    return ManyUI.Style(;
        fg=_manyui_color(style.fg),
        bg=_manyui_color(style.bg),
        bold=style.bold,
        dim=style.dim,
        italic=style.italic,
        underline=style.underline,
        strike=style.strikethrough)
end

function ManyUITUI.render!(w::SelectorBackgroundWidget,
        buf::AbstractMatrix{ManyUITUI.Cell})::Nothing
    effect = w.effect
    effect.background === nothing && return nothing
    width, height = size(buf)
    area = Tachikoma.Rect(1, 1, width, height)
    reference = Tachikoma.Buffer(area)
    render_selector_background!(effect.background, reference, area, w.tick[])
    for y in 1:height, x in 1:width

        cell = reference.content[Tachikoma.buf_index(reference, x, y)]
        cell.char == Tachikoma.WIDE_CHAR_PAD && continue
        ManyUITUI.set_cell!(buf, x, y, Tachikoma.cell_glyph(cell),
            _manyui_style(cell.style))
    end
    return nothing
end

function ManyUITUI.render!(w::SelectorLegendWidget,
        buf::AbstractMatrix{ManyUITUI.Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    column_width = max(1, div(width, LEGEND_COLUMNS))
    base_style = ManyUI.computed_style(w)

    for (i, badge) in enumerate(w.badges)
        row = cld(i, LEGEND_COLUMNS)
        column = mod(i - 1, LEGEND_COLUMNS)
        row > height && break
        x = 1 + column * column_width
        badge_style = merge(base_style,
            _manyui_style(get(BADGE_STYLES, badge, Tachikoma.tstyle(:text))))
        x += ManyUITUI.write_text!(buf, x, row,
            string(BADGE_GLYPH, ' '), badge_style)
        ManyUITUI.write_text!(buf, x, row, BADGE_LABELS[badge], base_style)
    end
    return nothing
end

const _WEB_BACKGROUND_CSS = """
<style>
@keyframes tryit-drift { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }
@keyframes tryit-pulse { 0%, 100% { filter: saturate(.8) brightness(.75); } 50% { filter: saturate(1.35) brightness(1.15); } }
html, body { width: 100%; min-height: 100%; margin: 0 !important; }
body { padding: 0 !important; display: block !important; background: transparent !important; overflow: hidden !important; }
body::before, body::after { display: none !important; }
.tryit-background { position: relative; width: 100vw; height: 100vh; padding: .35rem; box-sizing: border-box; overflow: hidden; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
.tryit-background-canvas { position: absolute; inset: 0; z-index: 0; width: 100%; height: 100%; image-rendering: pixelated; pointer-events: none; }
.tryit-background .manyui-container { min-width: 0; padding: 0; gap: 0; border-radius: 0; border: 0; box-shadow: none; animation: none; align-items: stretch; background: transparent; backdrop-filter: none; }
.tryit-background > #screen { position: relative; z-index: 1; display: flex !important; width: 100%; height: 100%; flex-direction: column !important; }
#main { display: grid !important; grid-template-columns: minmax(0, 1fr) 22rem; flex: 1 1 auto; min-height: 0; }
#left, #side { display: flex !important; flex-direction: column !important; min-height: 0; }
.panel { border: 1px solid var(--tryit-border); background: var(--tryit-panel) !important; color: var(--tryit-text); overflow: hidden; }
.panel_title { box-sizing: border-box; min-height: 1.65rem; padding: .18rem .55rem; color: var(--tryit-title); font-size: .9rem !important; font-weight: 700; text-align: left !important; text-shadow: none !important; }
#search_panel { flex: 0 0 auto; }
#search_panel .manyui-textinput { border: 0; border-top: 1px solid var(--tryit-border); border-radius: 0; padding: .35rem .55rem; background: var(--tryit-input); color: var(--tryit-text); font: inherit; box-shadow: none; }
#folders_panel, #preview_panel { flex: 1 1 auto; min-height: 0; }
#disk_panel, #legend_panel { flex: 0 0 auto; }
#disk { padding: .35rem .55rem; color: var(--tryit-dim); font-size: .82rem; text-align: left; }
#folders, #preview, #legend { width: 100%; height: 100%; overflow: auto; border: 0; border-radius: 0; background: transparent; }
#folders .manyui-list-item, #preview .manyui-list-item { padding: .18rem .55rem; border: 0; color: var(--tryit-text); font-size: .82rem; line-height: 1.25rem; }
#legend { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); align-content: start; box-sizing: border-box; padding: .18rem .55rem; color: var(--tryit-dim); font-size: .82rem; line-height: 1.25rem; }
.tryit-legend-item { min-width: 0; white-space: nowrap; }
.tryit-legend-glyph { font-weight: 700; }
#folders .manyui-list-selected { padding-left: .35rem; border-left: .2rem solid var(--tryit-accent); background: var(--tryit-selected) !important; }
#preview .manyui-list-selected, #legend .manyui-list-selected { border-left: 0; background: transparent !important; font-weight: normal; }
#footer { display: flex !important; flex-direction: row !important; flex: 0 0 auto; align-items: center; min-height: 2rem; gap: .5rem; background: var(--tryit-panel) !important; border-top: 1px solid var(--tryit-border) !important; }
#actions { display: flex !important; flex: 1 1 auto; flex-flow: row wrap !important; align-items: center; }
#key_help { display: none; }
#actions .manyui-button { padding: .25rem .45rem; border: 0; border-radius: 0; background: transparent; color: var(--tryit-dim); box-shadow: none; font: 700 .72rem/1rem ui-monospace, monospace; }
#actions .manyui-button:hover { transform: none; color: var(--tryit-accent); background: var(--tryit-selected); box-shadow: none; }
#status { padding: .25rem .5rem; color: var(--tryit-dim); font-size: .72rem; white-space: nowrap; text-align: right; }
#modal_layer { position: fixed; inset: 0; z-index: 20; display: flex !important; align-items: center !important; justify-content: center !important; padding: 1rem; background: transparent !important; }
#modal_layer .modal { display: flex !important; flex-direction: column !important; width: min(34rem, calc(100vw - 2rem)); max-height: calc(100vh - 2rem); padding: .65rem; border: 1px solid var(--tryit-accent); background: transparent !important; color: var(--tryit-text); box-shadow: 0 1rem 3rem rgba(0, 0, 0, .35); }
#modal_layer .modal_title { color: var(--tryit-title); font-weight: 700; }
#modal_layer .modal_hint { color: var(--tryit-dim); }
#modal_layer .manyui-list { min-height: 8rem; overflow: auto; }
#modal_layer .manyui-list-item { padding: .2rem .45rem; color: var(--tryit-text); }
#modal_layer .manyui-list-selected { background: var(--tryit-selected) !important; color: var(--tryit-accent); font-weight: 700; }
@media (max-width: 850px) {
  #main { grid-template-columns: 1fr; grid-template-rows: minmax(18rem, 1fr) auto; overflow: auto; }
  #side { display: grid !important; grid-template-columns: 1fr 1fr; }
  #preview_panel { min-height: 10rem; }
  #legend_panel { display: none; }
  #status { display: none; }
}
</style>
"""

const _WEB_SHORTCUT_SCRIPT = """
<script>
if (!window.tryitShortcutsInstalled) {
  window.tryitShortcutsInstalled = true;
  document.addEventListener('keydown', function (event) {
    let key = null;
    if (event.ctrlKey && ['a', 'b', 'd', 'g', 'r', 't'].includes(event.key.toLowerCase())) {
      key = 'ctrl+' + event.key.toLowerCase();
    } else if (event.key === 'Escape') {
      key = 'escape';
    } else if (event.key === 'ArrowUp') {
      key = 'up';
    } else if (event.key === 'ArrowDown') {
      key = 'down';
    } else if (event.key === '?' && !event.target.matches('input, textarea')) {
      key = '?';
    }
    if (key === null) {
      if (document.getElementById('modal_layer')) event.preventDefault();
      return;
    }
    event.preventDefault();
    dispatch_event('tryit_background', 'key', key);
  });
}
</script>
"""

# The WebNative projection uses the same logical terminal grid and equations as
# the Tachikoma colour backgrounds. Keeping the animation in the browser avoids
# replacing the complete DOM at the configured frame rate.
const _WEB_CANVAS_SCRIPT = """
<script>
if (!window.tryitBackgroundLoopInstalled) {
  window.tryitBackgroundLoopInstalled = true;

  const smooth = t => t * t * (3 - 2 * t);
  const hashNoise = n => {
    n = (n + 0x165667b1) >>> 0;
    n = Math.imul((n ^ (n >>> 16)) >>> 0, 0x45d9f3b) >>> 0;
    n = Math.imul((n ^ (n >>> 16)) >>> 0, 0x45d9f3b) >>> 0;
    n = (n ^ (n >>> 16)) >>> 0;
    return n / 0xffffffff;
  };
  const noise = (x, y = null) => {
    const xi = Math.floor(x), xf = x - xi;
    if (y === null) {
      return hashNoise(xi) + smooth(xf) * (hashNoise(xi + 1) - hashNoise(xi));
    }
    const yi = Math.floor(y), yf = y - yi;
    const a = hashNoise(xi + yi * 7919);
    const b = hashNoise(xi + 1 + yi * 7919);
    const c = hashNoise(xi + (yi + 1) * 7919);
    const d = hashNoise(xi + 1 + (yi + 1) * 7919);
    const top = a + smooth(xf) * (b - a);
    const bottom = c + smooth(xf) * (d - c);
    return top + smooth(yf) * (bottom - top);
  };
  const fbm = (x, y) => {
    let value = 0, amplitude = 1, frequency = 1, total = 0;
    for (let octave = 0; octave < 3; octave++) {
      value += amplitude * noise(x * frequency, y * frequency);
      total += amplitude;
      amplitude *= .5;
      frequency *= 2;
    }
    return value / total;
  };
  const mix = (a, b, t) => a.map((value, i) =>
    Math.round(value + (b[i] - value) * Math.max(0, Math.min(1, t))));
  const css = color => 'rgb(' + color[0] + ',' + color[1] + ',' + color[2] + ')';
  const colorBand = (palette, amount) => {
    const phase = Math.max(0, Math.min(1, amount)) * 4;
    const i = Math.min(3, Math.floor(phase));
    return mix(palette[i], palette[(i + 1) % 4], phase - i);
  };
  const paintCell = (ctx, base, target, amount, x, y) => {
    ctx.fillStyle = css(mix(base, target, amount));
    ctx.fillRect(x, y, 1, 1);
  };

  function drawBackground(canvas, tick) {
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(1, Math.ceil(rect.width / 8));
    const height = Math.max(1, Math.ceil(rect.height / 16));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    const ctx = canvas.getContext('2d');
    const data = canvas.dataset;
    const base = JSON.parse(data.base);
    const palette = JSON.parse(data.palette);
    const intensity = Number(data.intensity);
    const speed = Number(data.speed);
    const scale = Number(data.scale);
    const period = Number(data.period);
    const name = data.name;
    ctx.fillStyle = css(base);
    ctx.fillRect(0, 0, width, height);

    if (name === 'fog') {
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        const n = fbm((x + 1) * scale + tick * speed,
          (y + 1) * scale * 2 + tick * speed * .7);
        const target = n < .33 ? mix(palette[0], palette[1], n * 3) :
          n < .66 ? mix(palette[1], palette[2], (n - .33) * 3) :
          mix(palette[2], palette[3], (n - .66) * 3);
        paintCell(ctx, base, target, n * intensity, x, y);
      }
    } else if (name === 'aurora') {
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        const row = y / height;
        const wave = Math.sin((x + 1) * .06 + tick * speed) +
          .6 * Math.sin((x + 1) * .017 - tick * speed * 1.7);
        const band = Math.exp(-8 * Math.abs(row - .25 - .12 * wave));
        const target = row < .33 ? mix(palette[3], palette[2], row * 3) :
          row < .66 ? mix(palette[2], palette[1], (row - .33) * 3) :
          mix(palette[1], palette[0], (row - .66) * 3);
        paintCell(ctx, base, target, band * intensity, x, y);
      }
    } else if (name === 'plasma') {
      const time = tick * speed;
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        const u = x * scale, v = y * scale * 2;
        const n = Math.sin(u + time) + Math.sin(v + time * .8) +
          Math.sin((u + v) * .5 + time * 1.3);
        const amount = (n / 3 + 1) / 2;
        const phase = amount * 4;
        paintCell(ctx, base, colorBand(palette, amount),
          (.3 + .7 * Math.abs(Math.sin(phase * Math.PI))) * intensity, x, y);
      }
    } else if (name === 'rain') {
      for (let x = 0; x < width; x++) {
        const phase = noise((x + 1) * .7);
        const rate = .5 + noise((x + 1) * 1.9 + 11);
        const head = (phase * height + tick * speed * rate * height) % height;
        for (let y = 0; y < height; y++) {
          const behind = ((y - head) % height + height) % height;
          paintCell(ctx, base, palette[x % 4], Math.exp(-behind / 3) * intensity, x, y);
        }
      }
    } else if (name === 'pulse') {
      const phase = (tick % period) / period;
      const breath = phase < .6 ? Math.pow(phase / .6, 3) :
        1 - Math.pow((phase - .6) / .4, 2);
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        const gradient = x / width;
        const target = gradient < .33 ? mix(palette[0], palette[1], gradient * 3) :
          gradient < .66 ? mix(palette[1], palette[2], (gradient - .33) * 3) :
          mix(palette[2], palette[3], (gradient - .66) * 3);
        paintCell(ctx, base, target, breath * intensity + .15 * gradient, x, y);
      }
    } else if (name === 'mesh') {
      const cellWidth = Math.max(1, 1 / scale);
      const cellHeight = Math.max(1, 1 / scale / 2);
      const cols = Math.ceil(width / cellWidth) + 1;
      const rows = Math.ceil(height / cellHeight) + 1;
      const time = tick * speed;
      const vertex = (i, j) => [
        i * cellWidth + (fbm(i * .8 + time, j * .8) - .5) * cellWidth * .9,
        j * cellHeight + (fbm(i * .8, j * .8 + time) - .5) * cellHeight * .9
      ];
      const triangle = (points, color) => {
        ctx.beginPath();
        ctx.moveTo(points[0][0], points[0][1]);
        ctx.lineTo(points[1][0], points[1][1]);
        ctx.lineTo(points[2][0], points[2][1]);
        ctx.closePath();
        ctx.fillStyle = css(mix(base, color, intensity));
        ctx.fill();
        ctx.strokeStyle = css(base);
        ctx.lineWidth = 1.2;
        ctx.stroke();
      };
      for (let j = -1; j <= rows; j++) for (let i = -1; i <= cols; i++) {
        const v00 = vertex(i, j), v10 = vertex(i + 1, j);
        const v01 = vertex(i, j + 1), v11 = vertex(i + 1, j + 1);
        const first = Math.abs(((i * 31) ^ (j * 291) ^ 1)) % 4;
        const second = Math.abs(((i * 31) ^ (j * 291) ^ 2)) % 4;
        if ((i + j) % 2 === 0) {
          triangle([v00, v10, v11], palette[first]);
          triangle([v00, v11, v01], palette[second]);
        } else {
          triangle([v00, v10, v01], palette[first]);
          triangle([v10, v11, v01], palette[second]);
        }
      }
    }
  }

  let tick = 0, previous = 0;
  function animate(now) {
    const canvas = document.getElementById('tryit_background_canvas');
    const framePeriod = canvas ? 1000 / Number(canvas.dataset.fps) : 50;
    if (canvas && now - previous >= framePeriod) {
      drawBackground(canvas, tick++);
      previous = now;
    }
    window.requestAnimationFrame(animate);
  }
  window.requestAnimationFrame(animate);
}
</script>
"""

_css_rgb(c) =
    let rgb = Tachikoma.to_rgb(c)
        "rgb($(rgb.r),$(rgb.g),$(rgb.b))"
    end

_css_rgba(c, alpha) =
    let rgb = Tachikoma.to_rgb(c)
        "rgba($(rgb.r),$(rgb.g),$(rgb.b),$alpha)"
    end

function _web_theme_variables()
    theme = Tachikoma.theme()
    return join(
        (
            "--tryit-base:$(_css_rgb(theme.bg))",
            "--tryit-panel:$(_css_rgba(theme.bg, 0.82))",
            "--tryit-input:$(_css_rgba(theme.bg, 0.65))",
            "--tryit-border:$(_css_rgb(theme.border))",
            "--tryit-text:$(_css_rgb(theme.text))",
            "--tryit-dim:$(_css_rgb(theme.text_dim))",
            "--tryit-title:$(_css_rgb(theme.title))",
            "--tryit-accent:$(_css_rgb(theme.accent))",
            "--tryit-selected:$(_css_rgba(theme.accent, 0.22))"
        ),
        ';')
end

_rgb_values(c) =
    let rgb = Tachikoma.to_rgb(c)
        "[$(rgb.r),$(rgb.g),$(rgb.b)]"
    end

function _web_canvas(effect::SelectorBackgroundEffect)
    background = effect.background
    background isa ColorBackground || return ""
    theme = Tachikoma.theme()
    palette = join(
        (_rgb_values(theme.primary), _rgb_values(theme.secondary),
            _rgb_values(theme.accent), _rgb_values(theme.error)),
        ',')
    speed = hasproperty(background, :speed) ? background.speed : 0.0
    scale = hasproperty(background, :scale) ? background.scale : 1.0
    period = hasproperty(background, :period) ? background.period : 180
    return string("<canvas id=\"tryit_background_canvas\" ",
        "class=\"tryit-background-canvas\" data-name=\"", effect.name,
        "\" data-base=\"", _rgb_values(theme.bg),
        "\" data-palette=\"[", palette,
        "]\" data-intensity=\"", effect.intensity,
        "\" data-speed=\"", speed,
        "\" data-scale=\"", scale,
        "\" data-period=\"", period,
        "\" data-fps=\"", configured_fps(), "\"></canvas>")
end

function _web_background_style(effect::SelectorBackgroundEffect)
    alpha = effect.intensity
    name = effect.name
    theme = Tachikoma.theme()
    base = _css_rgb(theme.bg)
    c1, c2 = _css_rgba(theme.primary, alpha), _css_rgba(theme.secondary, alpha)
    c3, c4 = _css_rgba(theme.accent, alpha), _css_rgba(theme.error, alpha)
    name === :off && return "background: $base"
    effect.background isa ColorBackground && return "background: $base"
    name === :fog &&
        return "background: radial-gradient(circle at 20% 20%, $c1, transparent 42%), radial-gradient(circle at 80% 70%, $c2, transparent 45%), $base; background-size: 180% 180%; animation: tryit-drift 12s ease infinite"
    name === :aurora &&
        return "background: linear-gradient(135deg, $c3, $c2, $c1, $base); background-size: 300% 300%; animation: tryit-drift 9s ease infinite"
    name === :plasma &&
        return "background: conic-gradient(from 45deg, $c1, $c2, $c3, $c4, $c1); background-size: 220% 220%; animation: tryit-drift 7s linear infinite"
    name === :rain &&
        return "background: repeating-linear-gradient(100deg, transparent 0 18px, $c3 20px, transparent 22px 38px), $base; background-size: 100% 180%; animation: tryit-drift 5s linear infinite"
    name === :pulse &&
        return "background: radial-gradient(circle, $c1, $c2, $base 70%); animation: tryit-pulse 4s ease-in-out infinite"
    name === :mesh &&
        return "background: repeating-conic-gradient(from 30deg, $c1 0 12deg, $c2 12deg 24deg, $c3 24deg 36deg, $base 36deg 48deg); background-size: 120px 120px; animation: tryit-drift 16s linear infinite"
    name === :dotwave &&
        return "background: radial-gradient(circle, $c1 1px, transparent 2px), $base; background-size: 12px 8px; animation: tryit-drift 10s linear infinite"
    name === :phylo &&
        return "background: repeating-linear-gradient(60deg, transparent 0 30px, $c3 31px 32px, transparent 33px 60px), repeating-linear-gradient(-60deg, transparent 0 30px, $c2 31px 32px, transparent 33px 60px), $base; background-size: 180% 180%; animation: tryit-drift 18s linear infinite"
    return "background: repeating-linear-gradient(45deg, transparent 0 24px, $c1 25px 26px, transparent 27px 48px), repeating-linear-gradient(-45deg, transparent 0 24px, $c4 25px 26px, transparent 27px 48px), $base; background-size: 160% 160%; animation: tryit-drift 14s linear infinite"
end

function ManyUIWeb.to_html(w::SelectorBackgroundWidget)
    effect = w.effect
    inner = join((ManyUIWeb.to_html(child) for child in ManyUI.children(w)))
    class = "tryit-background tryit-background--$(background_name(effect))"
    return string(_WEB_BACKGROUND_CSS, "<div id=\"tryit_background\" class=\"",
        class, "\" style=\"", _web_theme_variables(), ";",
        _web_background_style(effect), "\">", _web_canvas(effect), inner, "</div>",
        _WEB_SHORTCUT_SCRIPT, _WEB_CANVAS_SCRIPT)
end

function ManyUIWeb.to_html(w::SelectorModalLayer)
    ManyUI.is_visible(w) || return ""
    inner = join(ManyUIWeb.to_html(child) for child in ManyUI.children(w)
        if ManyUI.is_visible(child))
    return "<div id=\"modal_layer\" class=\"modal_layer\">$inner</div>"
end

function ManyUIWeb.to_html(w::SelectorLegendWidget)
    items = map(w.badges) do badge
        colour = _css_rgb(get(BADGE_STYLES, badge,
            Tachikoma.tstyle(:text)).fg)
        string("<div class=\"tryit-legend-item\"><span aria-hidden=\"true\" ",
            "class=\"tryit-legend-glyph\" style=\"color: ", colour, "\">",
            BADGE_GLYPH, "</span> ", BADGE_LABELS[badge], "</div>")
    end
    return "<div id=\"$(ManyUI.node(w).id)\" class=\"tryit-legend\">$(join(items))</div>"
end

function ManyUIWeb.process_native_event!(root::SelectorBackgroundWidget, data)::Bool
    if String(data.id) == "tryit_background" && String(data.event) == "key"
        value = hasproperty(data, :value) ? data.value : nothing
        value === nothing && return false
        key = tryparse(ManyUI.KeyEvent, String(value))
        key === nothing && return false
        action = get(root.keymap, key, nothing)
        action === nothing && return false
        return action() !== false
    end
    return invoke(ManyUIWeb.process_native_event!, Tuple{ManyUI.Widget, Any}, root, data)
end

function _start_background_animation!(w::SelectorBackgroundWidget, stop::Base.RefValue{Bool})
    w.effect.name === :off && return nothing
    period = 1 / configured_fps()
    @async begin
        seen_open = false
        while !stop[]
            app = ManyUI.app(w)
            if app !== nothing
                if isopen(app)
                    seen_open = true
                    w.tick[] = w.tick[] + 1
                elseif seen_open
                    break
                end
            end
            sleep(period)
        end
    end
    return nothing
end

function manyui_selector_stylesheet()
    theme = Tachikoma.theme()
    text = _css_rgb(theme.text)
    dim = _css_rgb(theme.text_dim)
    title = _css_rgb(theme.title)
    accent = _css_rgb(theme.accent)
    return ManyUITUI.parse_css("""
    #screen        { layout: column; width: 100%; height: 100%; gap: 0; color: $text; }
    #main          { layout: row; grow: 1; gap: 0; }
    #left          { layout: column; grow: 1; }
    #side          { layout: column; width: 34; shrink: 0; }
    .panel         { layout: column; border: solid $accent; }
    .panel_title   { color: $title; text-style: bold; height: 1; shrink: 0; }
    #search_panel  { height: 4; shrink: 0; }
    #filter        { height: 1; shrink: 0; }
    #rename_input  { height: 1; shrink: 0; }
    #folders_panel { grow: 1; }
    #folders       { grow: 1; }
    #disk_panel    { height: 4; shrink: 0; }
    #preview_panel { grow: 1; }
    #preview       { grow: 1; }
    #legend_panel  { height: 9; shrink: 0; }
    #legend        { color: $dim; grow: 1; }
    #footer        { layout: row; height: 1; shrink: 0; }
    #actions       { display: none; }
    #key_help      { color: $dim; grow: 1; }
    #status        { display: none; }
    .modal         { layout: column; color: $text; background: transparent; border: round $accent; padding: 1; }
    .modal_title   { color: $title; text-style: bold; height: 1; shrink: 0; }
    .modal_hint    { color: $dim; height: 1; shrink: 0; }
    #theme_list, #animation_list { grow: 1; }
    """)
end

function _manyui_try_label(t::Try)
    return string(t.date, " ", t.name, "  (",
        format_age(try_age_seconds(t)), ")")
end

function _manyui_try_label(m::SelectorSession, t::Try)
    marked = t.path in m.marked_for_delete
    badges = badges_for(m, t)
    marker = marked ? "✗" : isempty(badges) ? " " : "●"
    return string(marker, " ", _manyui_try_label(t))
end

function _manyui_status(m::SelectorSession)
    count = length(m.visible)
    noun = count == 1 ? "try" : "tries"
    return "$count $noun — $(m.root.root)"
end

function _manyui_preview_items(m::SelectorSession)
    refresh_panels!(m)
    isempty(m.preview) && return [isempty(m.preview_path) ? "No selection" : "empty"]
    return [entry.isdir ? "▸ $(entry.name)" : "  $(entry.name)" for entry in m.preview]
end

function _manyui_disk(m::SelectorSession)
    refresh_panels!(m)
    m.disk === nothing && return "unavailable"
    return "Used: $(format_bytes(m.disk.used)) | Free: $(format_bytes(m.disk.free))"
end

function _manyui_select!(m::SelectorSession, list, preview)
    idx = ManyUI.row_cursor(list)
    if 1 <= idx <= length(m.visible)
        m.cursor = idx
        ManyUI.set_items!(preview, _manyui_preview_items(m))
    end
    return nothing
end

function _manyui_sync!(m::SelectorSession, list, status, preview, folders_title=nothing)
    ManyUI.set_items!(list, copy(m.visible))
    status.text[] = _manyui_status(m)
    if isempty(m.visible)
        ManyUI.set_items!(preview, ["No matching try"])
        folders_title === nothing || (folders_title.text[] = "Folders")
        return nothing
    end
    m.cursor = clamp(m.cursor, 1, length(m.visible))
    ManyUI.set_cursor!(list, m.cursor)
    ManyUI.set_items!(preview, _manyui_preview_items(m))
    folders_title === nothing ||
        (folders_title.text[] = "Folders  $(m.cursor)/$(length(m.visible))")
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
    folders_title_ref = Ref{Any}()
    canvas_ref = Ref{Any}()

    filter_box = ManyUI.TextInput(m.filter, w -> _manyui_open_selected!(m, list_ref[]);
        on_change=w -> begin
            m.filter = w.text[]
            refresh_visible!(m)
            _manyui_sync!(m, list_ref[], status_ref[], preview_ref[],
                folders_title_ref[])
        end,
        placeholder="Filter or type a new try name…",
        id=:filter)

    preview = ManyUI.List(_manyui_preview_items(m); id=:preview)
    folders = ManyUI.List(copy(m.visible),
        w -> _manyui_open_selected!(m, w);
        format=t -> _manyui_try_label(m, t),
        on_change=w -> _manyui_select!(m, w, preview),
        id=:folders)
    status = ManyUI.Label(_manyui_status(m); id=:status)
    folders_title = ManyUI.Label(
        isempty(m.visible) ? "Folders" : "Folders  $(m.cursor)/$(length(m.visible))";
        id=:folders_title, classes=[:panel_title])

    list_ref[] = folders
    status_ref[] = status
    preview_ref[] = preview
    folders_title_ref[] = folders_title

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
            _manyui_sync!(m, folders, status, preview, folders_title)
        end; id=:refresh)
    quit_button = ManyUI.Button("Quit", _ -> begin
            m.exit_action = :quit
            m.done = true
            nothing
        end; id=:quit)

    rename_box = ManyUI.TextInput(
        "", w -> begin
            m.rename_buf = w.text[]
            _commit_rename!(m)
            if m.mode === :normal
                ManyUI.set_visible!(w, false)
                ManyUI.set_visible!(filter_box, true)
                _manyui_sync!(m, folders, status, preview, folders_title)
            else
                status.text[] = m.notice
            end
            nothing
        end;
        on_change=w -> (m.rename_buf = w.text[]),
        placeholder="New name…", id=:rename_input)
    ManyUI.set_visible!(rename_box, false)

    delete_button = ManyUI.Button("Ctrl+D Delete",
        _ -> begin
            _handle_ctrl_d!(m)
            ManyUI.refresh_rows!(folders)
            status.text[] = isempty(m.marked_for_delete) ? _manyui_status(m) :
                            "$(length(m.marked_for_delete)) marked for deletion"
            nothing
        end;
        id=:delete)
    rename_button = ManyUI.Button(
        "Ctrl+R Rename", _ -> begin
            _handle_ctrl_r!(m)
            m.mode === :rename || return nothing
            rename_box.text[] = m.rename_buf
            ManyUI.set_visible!(filter_box, false)
            ManyUI.set_visible!(rename_box, true)
            nothing
        end; id=:rename)
    graduate_button = ManyUI.Button("Ctrl+G Graduate",
        _ -> begin
            _handle_ctrl_g!(m)
            m.done || (status.text[] = isempty(m.notice) ? _manyui_status(m) : m.notice)
            nothing
        end;
        id=:graduate)

    theme_action = Ref{Function}(() -> nothing)
    animation_action = Ref{Function}(() -> nothing)
    about_action = Ref{Function}(() -> nothing)
    help_action = Ref{Function}(() -> nothing)

    theme_button = ManyUI.Button("Ctrl+T Theme", _ -> theme_action[](); id=:theme)
    background_button = ManyUI.Button(
        "Ctrl+B Animation", _ -> animation_action[](); id=:background)
    about_button = ManyUI.Button("Ctrl+A About", _ -> about_action[](); id=:about)
    help_button = ManyUI.Button("? Help", _ -> help_action[](); id=:help)

    search_panel = ManyUI.Container(
        ManyUI.Label("Search/New"; id=:search_title, classes=[:panel_title]),
        filter_box, rename_box; id=:search_panel, classes=[:panel])
    folders_panel = ManyUI.Container(folders_title, folders;
        id=:folders_panel, classes=[:panel])
    left = ManyUI.Container(search_panel, folders_panel; id=:left)

    disk_panel = ManyUI.Container(
        ManyUI.Label("Disk"; id=:disk_title, classes=[:panel_title]),
        ManyUI.Label(_manyui_disk(m); id=:disk);
        id=:disk_panel, classes=[:panel])
    preview_panel = ManyUI.Container(
        ManyUI.Label("Preview"; id=:preview_title, classes=[:panel_title]),
        preview; id=:preview_panel, classes=[:panel])
    legend = SelectorLegendWidget()
    legend_panel = ManyUI.Container(
        ManyUI.Label("Legends"; id=:legend_title, classes=[:panel_title]),
        legend; id=:legend_panel, classes=[:panel])
    side = ManyUI.Container(disk_panel, preview_panel, legend_panel; id=:side)
    main = ManyUI.Container(left, side; id=:main)

    actions = ManyUI.Container(open_button, create_button, delete_button,
        rename_button, graduate_button, theme_button, background_button,
        about_button, help_button, refresh_button, quit_button; id=:actions)
    key_help = ManyUI.Label(
        "↑↓ Nav | Enter Select | Ctrl+D Del | Ctrl+R Rename | Ctrl+G Graduate | Ctrl+T Theme | Ctrl+B Animation | Ctrl+A About | ? Help | Esc Quit";
        id=:key_help)
    footer = ManyUI.Container(actions, key_help, status; id=:footer)
    content = ManyUI.Container(main, footer; id=:screen)

    function info_dialog(id::Symbol, title::String, body::String)
        return ManyUI.Container(
            ManyUI.Label(title; classes=[:modal_title]),
            ManyUI.Label(body),
            ManyUI.Label("Esc  Close"; classes=[:modal_hint]);
            id=id, classes=[:modal])
    end

    about_body = "TryIt.jl  version $(ABOUT_VERSION)\n" *
        "Repo: github.com/s-celles/TryIt.jl\n" *
        "Docs: s-celles.github.io/TryIt.jl\n\n" *
        "Ephemeral-workspace manager for Julia.\n\n" *
        "Inspired by try-cli and try-rs\n" *
        "UI powered by ManyUI"
    help_body = join((rpad(key, 10) * description for (key, description) in HELP_KEYS),
        '\n')

    theme_change = Ref{Function}(_ -> nothing)
    theme_submit = Ref{Function}(_ -> nothing)
    animation_change = Ref{Function}(_ -> nothing)
    animation_submit = Ref{Function}(_ -> nothing)

    theme_list = ManyUI.List(copy(theme_names()),
        w -> theme_submit[](w); on_change=w -> theme_change[](w), id=:theme_list)
    theme_dialog = ManyUI.Container(
        ManyUI.Label("Theme"; classes=[:modal_title]), theme_list,
        ManyUI.Label("↑↓ Preview  Enter Keep  Esc Cancel"; classes=[:modal_hint]);
        id=:theme_dialog, classes=[:modal])
    native_theme_list = ManyUI.List(copy(theme_names()),
        w -> theme_submit[](w); on_change=w -> theme_change[](w),
        id=:native_theme_list)
    native_theme_dialog = ManyUI.Container(
        ManyUI.Label("Theme"; classes=[:modal_title]), native_theme_list,
        ManyUI.Label("↑↓ Preview  Enter Keep  Esc Cancel"; classes=[:modal_hint]);
        id=:native_theme_dialog, classes=[:modal])

    animation_list = ManyUI.List(copy(BACKGROUND_NAMES),
        w -> animation_submit[](w); on_change=w -> animation_change[](w),
        id=:animation_list)
    animation_dialog = ManyUI.Container(
        ManyUI.Label("Animation"; classes=[:modal_title]), animation_list,
        ManyUI.Label("↑↓ Preview  Enter Keep  Esc Cancel"; classes=[:modal_hint]);
        id=:animation_dialog, classes=[:modal])
    native_animation_list = ManyUI.List(copy(BACKGROUND_NAMES),
        w -> animation_submit[](w); on_change=w -> animation_change[](w),
        id=:native_animation_list)
    native_animation_dialog = ManyUI.Container(
        ManyUI.Label("Animation"; classes=[:modal_title]), native_animation_list,
        ManyUI.Label("↑↓ Preview  Enter Keep  Esc Cancel"; classes=[:modal_hint]);
        id=:native_animation_dialog, classes=[:modal])

    about_dialog = info_dialog(:about_dialog, "About", about_body)
    native_about_dialog = info_dialog(:native_about_dialog, "About", about_body)
    help_dialog = info_dialog(:help_dialog, "Key bindings", help_body)
    native_help_dialog = info_dialog(:native_help_dialog, "Key bindings", help_body)
    native_dialogs = (native_theme_dialog, native_animation_dialog,
        native_about_dialog, native_help_dialog)
    foreach(dialog -> ManyUI.set_visible!(dialog, false), native_dialogs)
    modal_layer = SelectorModalLayer(native_dialogs...)

    terminal_app() = begin
        current = ManyUI.app(canvas_ref[])
        current isa ManyUITUI.App ? current : nothing
    end
    function repaint_theme!()
        current = terminal_app()
        if current !== nothing
            sheet = manyui_selector_stylesheet()
            current.stylesheet = sheet
            ManyUI.apply_stylesheet!(sheet, current.root)
            popup = ManyUI.popup_of(current)
            popup === nothing || ManyUI.apply_stylesheet!(sheet, popup.content)
            ManyUITUI.invalidate!(current)
        end
        ManyUI.mark!(canvas_ref[], ManyUI.Dirty.PAINT)
        return nothing
    end
    function show_native_dialog!(dialog)
        foreach(item -> ManyUI.set_visible!(item, item === dialog), native_dialogs)
        ManyUI.set_visible!(modal_layer, true)
        return nothing
    end
    function hide_native_dialogs!()
        ManyUI.set_visible!(modal_layer, false)
        foreach(item -> ManyUI.set_visible!(item, false), native_dialogs)
        return nothing
    end
    function open_modal!(mode::Symbol, terminal_dialog, native_dialog,
            size::ManyUI.Size)
        m.mode === :normal || return nothing
        m.mode = mode
        current = terminal_app()
        if current === nothing
            show_native_dialog!(native_dialog)
        else
            ManyUI.open_popup!(current,
                ManyUI.Popup(terminal_dialog, canvas_ref[], size;
                    placement=ManyUI.PopupPlacement.CENTER))
        end
        return nothing
    end
    function close_modal!()
        m.mode = :normal
        current = terminal_app()
        if current === nothing
            hide_native_dialogs!()
        else
            ManyUI.close_popup!(current, canvas_ref[])
        end
        return nothing
    end

    animation_before = Ref(effect)
    function restore_open_picker!()
        if m.mode === :theme
            apply_theme!(m.theme_before)
            repaint_theme!()
        elseif m.mode === :animation
            canvas_ref[].effect = animation_before[]
            m.background = animation_before[].background
            ManyUI.mark!(canvas_ref[], ManyUI.Dirty.PAINT)
        end
        m.mode = :normal
        hide_native_dialogs!()
        return nothing
    end

    function preview_theme!(source)
        idx = ManyUI.row_cursor(source)
        1 <= idx <= length(theme_names()) || return nothing
        m.theme_index = idx
        source === theme_list || ManyUI.set_cursor!(theme_list, idx)
        source === native_theme_list || ManyUI.set_cursor!(native_theme_list, idx)
        name = theme_names()[idx]
        apply_theme!(name)
        status.text[] = "Theme: $name"
        repaint_theme!()
        return nothing
    end
    function preview_animation!(source)
        idx = ManyUI.row_cursor(source)
        1 <= idx <= length(BACKGROUND_NAMES) || return nothing
        m.anim_index = idx
        source === animation_list || ManyUI.set_cursor!(animation_list, idx)
        source === native_animation_list || ManyUI.set_cursor!(native_animation_list, idx)
        name = BACKGROUND_NAMES[idx]
        current = canvas_ref[].effect
        canvas_ref[].effect = selector_background_effect(name;
            intensity=current.intensity, preset=current.preset)
        m.background = canvas_ref[].effect.background
        status.text[] = "Animation: $name"
        ManyUI.mark!(canvas_ref[], ManyUI.Dirty.PAINT)
        return nothing
    end
    theme_change[] = preview_theme!
    animation_change[] = preview_animation!
    theme_submit[] = _ -> close_modal!()
    animation_submit[] = _ -> close_modal!()

    function open_theme!()
        _open_theme_picker!(m)
        idx = m.theme_index
        ManyUI.set_cursor!(theme_list, idx)
        ManyUI.set_cursor!(native_theme_list, idx)
        # `_open_theme_picker!` sets the mode before the common opener.
        m.mode = :normal
        return open_modal!(:theme, theme_dialog, native_theme_dialog,
            ManyUI.Size(34, min(length(theme_names()) + 4, 24)))
    end
    function open_animation!()
        animation_before[] = canvas_ref[].effect
        m.anim_before = background_name(animation_before[])
        idx = findfirst(==(m.anim_before), BACKGROUND_NAMES)
        m.anim_index = something(idx, 1)
        ManyUI.set_cursor!(animation_list, m.anim_index)
        ManyUI.set_cursor!(native_animation_list, m.anim_index)
        return open_modal!(:animation, animation_dialog, native_animation_dialog,
            ManyUI.Size(30, min(length(BACKGROUND_NAMES) + 4, 24)))
    end
    theme_action[] = open_theme!
    animation_action[] = open_animation!
    about_action[] = () -> open_modal!(:about, about_dialog, native_about_dialog,
        ManyUI.Size(52, 15))
    help_action[] = () -> open_modal!(:help, help_dialog, native_help_dialog,
        ManyUI.Size(64, min(length(HELP_KEYS) + 4, 26)))

    click(button) = () -> (button.on_click(button); nothing)
    escape = () -> begin
        if m.mode === :theme
            apply_theme!(m.theme_before)
            repaint_theme!()
            close_modal!()
        elseif m.mode === :animation
            canvas_ref[].effect = animation_before[]
            m.background = animation_before[].background
            ManyUI.mark!(canvas_ref[], ManyUI.Dirty.PAINT)
            close_modal!()
        elseif m.mode in (:about, :help)
            close_modal!()
        elseif m.mode === :rename
            m.mode = :normal
            m.rename_buf = ""
            ManyUI.set_visible!(rename_box, false)
            ManyUI.set_visible!(filter_box, true)
        else
            quit_button.on_click(quit_button)
        end
        return nothing
    end
    question = () -> begin
        m.mode === :normal || return false
        isempty(m.filter) || return false
        help_button.on_click(help_button)
        return nothing
    end
    move_selection = delta -> begin
        if m.mode === :theme
            ManyUI.set_cursor!(theme_list,
                clamp(m.theme_index + delta, 1, length(theme_names())))
            return nothing
        elseif m.mode === :animation
            ManyUI.set_cursor!(animation_list,
                clamp(m.anim_index + delta, 1, length(BACKGROUND_NAMES)))
            return nothing
        elseif m.mode !== :normal
            return false
        end
        isempty(m.visible) && return nothing
        ManyUI.set_cursor!(folders,
            clamp(ManyUI.row_cursor(folders) + delta, 1, length(m.visible)))
        return nothing
    end
    enter = () -> begin
        m.mode in (:theme, :animation, :about, :help) || return false
        close_modal!()
        return nothing
    end
    keymap = Dict{ManyUI.KeyEvent, Function}(
        ManyUI.key(ManyUI.Key.UP) => () -> move_selection(-1),
        ManyUI.key(ManyUI.Key.DOWN) => () -> move_selection(1),
        ManyUI.key(ManyUI.Key.ENTER) => enter,
        ManyUI.key('d'; ctrl=true) => click(delete_button),
        ManyUI.key('r'; ctrl=true) => click(rename_button),
        ManyUI.key('g'; ctrl=true) => click(graduate_button),
        ManyUI.key('t'; ctrl=true) => click(theme_button),
        ManyUI.key('a'; ctrl=true) => click(about_button),
        ManyUI.key('b'; ctrl=true) => click(background_button),
        ManyUI.key('?') => question,
        ManyUI.key(ManyUI.Key.ESCAPE) => escape
    )
    canvas = SelectorBackgroundWidget(content; effect=effect, keymap=keymap,
        on_popup_close=restore_open_picker!,
        on_unmapped_key=() -> m.mode in (:theme, :animation, :about, :help))
    canvas_ref[] = canvas
    ManyUI.mount!(canvas, modal_layer)
    animate && _start_background_animation!(canvas, animation_stop)
    return canvas
end

function _launch_manyui(factory, ::ManyUITUIFrontend)
    # TryIt's shell function captures stdout. `_with_terminal_stdout` routes
    # it through an IOStream opened on /dev/tty, whose `displaysize` falls
    # back to 80x24 on Julia. stderr remains the original Base.TTY and reports
    # the real window size, so make it the terminal driver's explicit output.
    backend = ManyUITUI.TerminalBackend(in_stream=stdin, out_stream=stderr)
    return ManyUITUI.launch(factory, backend;
        stylesheet=manyui_selector_stylesheet(), wait=false)
end

function _launch_manyui(factory, frontend::WebNativeFrontend)
    return ManyUITUI.launch(factory, ManyUI.WebNative();
        port=frontend.port, wait=false)
end

function _launch_manyui(factory, frontend::WebTUIFrontend)
    backend = ManyUIWeb.WebBackend(port=frontend.port)
    return ManyUITUI.launch(factory, backend;
        stylesheet=manyui_selector_stylesheet(), wait=false)
end

function _drive_manyui!(handle, m::SelectorSession)
    try
        while isopen(handle) && !m.done
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
        isopen(handle) && close(handle)
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
