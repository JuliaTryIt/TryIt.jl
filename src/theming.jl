# Theme and animated-background configuration.
#
# Both are resolved from the environment once, at selector open, and
# both fail soft: a typo in a config variable must never throw inside
# the render loop or leave the user staring at a broken TUI.

# The ColorBackground family, ANIMATION_NAMES, BACKGROUND_OFF_NAMES,
# `color_animation`, `_clamp_preset`, and the core methods of
# `animation_name` / `blanks_panels` live in animations.jl, inside
# Core: they are values and name tables, with no colour or terminal in
# them. This file is the UI layer that paints them, and adds the
# methods covering the glyph backgrounds Tachikoma supplies.

"""
Any background the selector can render.
"""
const SelectorBackground = Union{Tachikoma.Background, ColorBackground}

"""
Every background the picker offers, in menu order.

The colour family first, then Tachikoma's glyph backgrounds, then the
opt-out — most-used to least.
"""
const BACKGROUND_NAMES = vcat(ANIMATION_NAMES, ["dotwave", "phylo", "clado", "off"])

#  Julia Dark ── based on official Julia language colors
#  High contrast, distinctive purple/green/blue/red accents on dark background.
const JULIA_DARK = Tachikoma.Theme(
    "julia_dark",
    Tachikoma.Color256(234),  # bg: very dark gray
    Tachikoma.Color256(238),  # border: dark gray
    Tachikoma.Color256(98),   # border_focus: Julia purple
    Tachikoma.Color256(252),  # text: light gray
    Tachikoma.Color256(243),  # text_dim: medium gray
    Tachikoma.Color256(255),  # text_bright: white
    Tachikoma.Color256(98),   # primary: Julia purple
    Tachikoma.Color256(26),   # secondary: Julia blue
    Tachikoma.Color256(34),   # accent: Julia green
    Tachikoma.Color256(34),   # success: Julia green
    Tachikoma.Color256(214),  # warning: orange/yellow
    Tachikoma.Color256(160),  # error: Julia red
    Tachikoma.Color256(98),   # title: Julia purple
)

#  Julia Light ── based on official Julia language colors
#  Clean, professional, with distinctive purple/green/blue/red accents on white.
const JULIA_LIGHT = Tachikoma.Theme(
    "julia_light",
    Tachikoma.Color256(231),  # bg: pure white
    Tachikoma.Color256(249),  # border: light gray
    Tachikoma.Color256(98),   # border_focus: Julia purple
    Tachikoma.Color256(234),  # text: near-black
    Tachikoma.Color256(245),  # text_dim: medium gray
    Tachikoma.Color256(232),  # text_bright: black
    Tachikoma.Color256(98),   # primary: Julia purple
    Tachikoma.Color256(26),   # secondary: Julia blue
    Tachikoma.Color256(34),   # accent: Julia green
    Tachikoma.Color256(34),   # success: Julia green
    Tachikoma.Color256(214),  # warning: orange
    Tachikoma.Color256(160),  # error: Julia red
    Tachikoma.Color256(98),   # title: Julia purple
)

const TRY_THEMES = (JULIA_DARK, JULIA_LIGHT)

# Palette endpoints, re-read every frame so a live theme change is
# picked up immediately.
function _palette()
    (Tachikoma.to_rgb(Tachikoma.theme().bg),
        Tachikoma.to_rgb(Tachikoma.theme().primary),
        Tachikoma.to_rgb(Tachikoma.theme().secondary),
        Tachikoma.to_rgb(Tachikoma.theme().accent),
        Tachikoma.to_rgb(Tachikoma.theme().error))
end

@inline function _paint!(buf, x, y, base, target, amount)
    c = Tachikoma.color_lerp(base, target, clamp(amount, 0.0, 1.0))
    Tachikoma.set_char!(buf, x, y, ' ', Tachikoma.Style(bg=c))
    return nothing
end

"""
Draw `bg` across `area` for frame `tick`.
"""
function render_selector_background!(bg::Tachikoma.Background, buf, area, tick::Int)
    Tachikoma.render_background!(
        bg, buf, area, tick)
end

function render_selector_background!(bg::FogBackground, buf, area, tick::Int)
    base, c1, c2, c3, c4 = _palette()
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        n = Tachikoma.fbm(
            x * bg.scale + tick * bg.speed,
            y * bg.scale * 2 + tick * bg.speed * 0.7
        )
        n = clamp(n, 0.0, 1.0)
        c_target = if n < 0.33
            Tachikoma.color_lerp(c1, c2, n * 3)
        elseif n < 0.66
            Tachikoma.color_lerp(c2, c3, (n - 0.33) * 3)
        else
            Tachikoma.color_lerp(c3, c4, (n - 0.66) * 3)
        end
        _paint!(buf, x, y, base, c_target, n * bg.intensity)
    end
    return nothing
end

function render_selector_background!(bg::AuroraBackground, buf, area, tick::Int)
    base, c1, c2, c3, c4 = _palette()
    h = max(1, area.height)
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        row = (y - area.y) / h
        wave = sin(x * 0.06 + tick * bg.speed) +
               0.6sin(x * 0.017 - tick * bg.speed * 1.7)
        band = exp(-8 * abs(row - 0.25 - 0.12wave))
        c_target = if row < 0.33
            Tachikoma.color_lerp(c4, c3, row * 3)
        elseif row < 0.66
            Tachikoma.color_lerp(c3, c2, (row - 0.33) * 3)
        else
            Tachikoma.color_lerp(c2, c1, (row - 0.66) * 3)
        end
        _paint!(buf, x, y, base, c_target, band * bg.intensity)
    end
    return nothing
end

function render_selector_background!(bg::PlasmaBackground, buf, area, tick::Int)
    base, c1, c2, c3, c4 = _palette()
    t = tick * bg.speed
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        u = (x - area.x) * bg.scale
        v = (y - area.y) * bg.scale * 2
        n = sin(u + t) + sin(v + t * 0.8) + sin((u + v) * 0.5 + t * 1.3)
        amount = clamp((n / 3 + 1) / 2, 0.0, 1.0)    # → [0, 1]
        
        phase = amount * 4
        c_target = if phase < 1.0
            Tachikoma.color_lerp(c1, c2, phase)
        elseif phase < 2.0
            Tachikoma.color_lerp(c2, c3, phase - 1.0)
        elseif phase < 3.0
            Tachikoma.color_lerp(c3, c4, phase - 2.0)
        else
            Tachikoma.color_lerp(c4, c1, phase - 3.0)
        end
        _paint!(
            buf, x, y, base, c_target,
            (0.3 + 0.7 * abs(sin(phase * pi))) * bg.intensity
        )
    end
    return nothing
end

function render_selector_background!(bg::RainBackground, buf, area, tick::Int)
    base, c1, c2, c3, c4 = _palette()
    h = max(1, area.height)
    for x in (area.x):(area.x + area.width - 1)
        phase = Tachikoma.noise(x * 0.7)
        rate = 0.5 + Tachikoma.noise(x * 1.9 + 11.0)
        head = mod(phase * h + tick * bg.speed * rate * h, h)
        for y in (area.y):(area.y + area.height - 1)
            Tachikoma.in_bounds(buf, x, y) || continue
            behind = mod((y - area.y) - head, h)
            
            c_target = (x % 4 == 0) ? c1 : ((x % 4 == 1) ? c2 : ((x % 4 == 2) ? c3 : c4))
            _paint!(buf, x, y, base, c_target, exp(-behind / 3) * bg.intensity)
        end
    end
    return nothing
end

function render_selector_background!(bg::PulseBackground, buf, area, tick::Int)
    base, c1, c2, c3, c4 = _palette()
    amount = Tachikoma.breathe(tick; period=bg.period) * bg.intensity
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        edge = 0.15 * (x - area.x) / max(1, area.width)
        
        grad = (x - area.x) / max(1, area.width)
        c_target = if grad < 0.33
            Tachikoma.color_lerp(c1, c2, grad * 3)
        elseif grad < 0.66
            Tachikoma.color_lerp(c2, c3, (grad - 0.33) * 3)
        else
            Tachikoma.color_lerp(c3, c4, (grad - 0.66) * 3)
        end
        _paint!(buf, x, y, base, c_target, amount + edge)
    end
    return nothing
end

function _draw_mesh_triangle(buf, area, a, b, c, fill_col, edge_col, intensity, base)
    min_x = max(area.x, floor(Int, min(a[1], b[1], c[1])))
    max_x = min(area.x + area.width - 1, ceil(Int, max(a[1], b[1], c[1])))
    min_y = max(area.y, floor(Int, min(a[2], b[2], c[2])))
    max_y = min(area.y + area.height - 1, ceil(Int, max(a[2], b[2], c[2])))
    
    l1 = max(1e-4, hypot(b[1]-a[1], b[2]-a[2]))
    l2 = max(1e-4, hypot(c[1]-b[1], c[2]-b[2]))
    l3 = max(1e-4, hypot(a[1]-c[1], a[2]-c[2]))
    
    for y in min_y:max_y
        for x in min_x:max_x
            Tachikoma.in_bounds(buf, x, y) || continue
            
            d1 = (x - a[1]) * (b[2] - a[2]) - (y - a[2]) * (b[1] - a[1])
            d2 = (x - b[1]) * (c[2] - b[2]) - (y - b[2]) * (c[1] - b[1])
            d3 = (x - c[1]) * (a[2] - c[2]) - (y - c[2]) * (a[1] - c[1])
            
            has_neg = (d1 < 0) || (d2 < 0) || (d3 < 0)
            has_pos = (d1 > 0) || (d2 > 0) || (d3 > 0)
            
            if !(has_neg && has_pos)
                dist1 = abs(d1) / l1
                dist2 = abs(d2) / l2
                dist3 = abs(d3) / l3
                
                is_edge = min(dist1, dist2, dist3) < 0.6
                c_target = is_edge ? edge_col : fill_col
                _paint!(buf, x, y, base, c_target, intensity)
            end
        end
    end
end

function render_selector_background!(bg::MeshBackground, buf, area, tick::Int)
    base, c1, c2, c3, c4 = _palette()
    palette = (c1, c2, c3, c4)
    t = tick * bg.speed
    
    cell_w = max(1.0, 1.0 / bg.scale)
    cell_h = max(1.0, 1.0 / bg.scale / 2.0)
    
    cols = ceil(Int, area.width / cell_w) + 1
    rows = ceil(Int, area.height / cell_h) + 1
    
    function get_v(i, j)
        bx = area.x + i * cell_w
        by = area.y + j * cell_h
        nx = Tachikoma.fbm(i * 0.8 + t, j * 0.8) - 0.5
        ny = Tachikoma.fbm(i * 0.8, j * 0.8 + t) - 0.5
        return (bx + nx * cell_w * 0.9, by + ny * cell_h * 0.9)
    end
    
    for j in -1:rows, i in -1:cols
        v00 = get_v(i, j)
        v10 = get_v(i+1, j)
        v01 = get_v(i, j+1)
        v11 = get_v(i+1, j+1)
        
        parity = iseven(i + j)
        if parity
            t1 = (v00, v10, v11)
            t2 = (v00, v11, v01)
        else
            t1 = (v00, v10, v01)
            t2 = (v10, v11, v01)
        end
        
        h1 = hash(i) ⊻ hash(j * 0x123) ⊻ hash(1)
        _draw_mesh_triangle(buf, area, t1..., palette[(h1 % 4) + 1], base, bg.intensity, base)
        
        h2 = hash(i) ⊻ hash(j * 0x123) ⊻ hash(2)
        _draw_mesh_triangle(buf, area, t2..., palette[(h2 % 4) + 1], base, bg.intensity, base)
    end
    return nothing
end

"""
Whether panel interiors should be blanked before drawing `bg`.

The colour family survives blanking — it lives in each cell's background
colour, which `set_char!` preserves when the incoming style has none.
Glyph backgrounds do not, so they are rendered full-bleed and show
through the panels, as they do in Tachikoma's own demos.
"""
blanks_panels(::Tachikoma.Background) = false

# THEME_ENV, BACKGROUND_ENV, ANIMATION_ENV and DEFAULT_BACKGROUND live
# in config.jl: they are read by the core's settings resolution, which
# cannot reach up into this layer. BACKGROUND_PRESET_ENV stays here —
# its only reader is `background_from_env` below.

"""
Environment variable selecting the background's preset index, for the
glyph backgrounds that have variants.
"""
const BACKGROUND_PRESET_ENV = "TRY_BACKGROUND_PRESET"

"""
Build the animated background named by `kind`.

`kind` is matched case-insensitively after trimming:

| Name      | Background                                      |
|:--------- |:----------------------------------------------- |
| `wash`    | [`WashBackground`](@ref) — animated colour      |
| `dotwave` | `Tachikoma.DotWaveBackground` — braille terrain |
| `phylo`   | `Tachikoma.PhyloTreeBackground`                 |
| `clado`   | `Tachikoma.CladogramBackground`                 |

Any of `none`, `off`, `no`, `0`, `false`, `disabled`, or the empty
string returns `nothing`. An unrecognised name falls back to
[`DEFAULT_BACKGROUND`](@ref) rather than `nothing` — a typo should not
be indistinguishable from a deliberate opt-out.

`preset` is clamped into range; an out-of-range index would otherwise
index past the end of the preset table inside the render loop.
"""
function resolve_background(kind::AbstractString, preset::Integer=1)
    key = lowercase(strip(kind))
    key in BACKGROUND_OFF_NAMES && return nothing

    # The colour family is the core's; ask it first. A `nothing` back
    # means "not mine" — the opt-out was already handled above.
    colour = color_animation(key)
    colour === nothing || return colour

    if key == "phylo"
        idx = _clamp_preset(preset, length(Tachikoma.PHYLO_PRESETS))
        return Tachikoma.PhyloTreeBackground(preset=idx)
    elseif key == "clado"
        idx = _clamp_preset(preset, length(Tachikoma.CLADO_PRESETS))
        return Tachikoma.CladogramBackground(preset=idx)
    end

    if key == "dotwave"
        idx = _clamp_preset(preset, length(Tachikoma.DOTWAVE_PRESETS))
        return Tachikoma.DotWaveBackground(preset=idx)
    end

    # Anything unrecognised falls back to the default.
    return FogBackground()
end

"""
Resolve the animated background from the environment.

Returns `nothing` when the user opted out, or when Tachikoma's global
motion switch is off — respecting a reduced-motion preference matters
more than our default.

EARS coverage: OF5.
"""
function background_from_env()
    Tachikoma.animations_enabled() || return nothing
    # Environment > config file > default, resolved in config.jl.
    kind = configured_animation()
    raw = get(ENV, BACKGROUND_PRESET_ENV, "")
    preset = something(tryparse(Int, strip(raw)), 1)
    
    bg = resolve_background(kind, preset)
    if bg !== nothing
        bg = with_intensity(bg, configured_opacity())
    end
    return bg
end

"""
Activate the theme called `name`.

Returns `true` when a theme was applied, `false` when `name` is empty
or unknown. Deliberately not an error: `Tachikoma.set_theme!` throws
on an unknown name, and a stray `TRY_THEME` typo should leave the
current theme in place rather than abort the CLI.
"""
function apply_theme!(name::AbstractString)
    key = lowercase(strip(name))
    isempty(key) && return false
    for t in TRY_THEMES
        if t.name == key
            Tachikoma.set_theme!(t)
            return true
        end
    end
    for t in Tachikoma.ALL_THEMES
        if t.name == key
            Tachikoma.set_theme!(t)
            return true
        end
    end
    return false
end

"""
Apply the theme named by [`THEME_ENV`](@ref), if any.

Returns whether a theme was applied.

EARS coverage: OF4.
"""
apply_theme_from_env!() = apply_theme!(configured_theme())

"""
Every built-in theme name, for documentation and error messages.
"""
theme_names() = [t.name for t in vcat(Tachikoma.ALL_THEMES..., TRY_THEMES...)]

# Configuration names for the glyph backgrounds. The colour family's
# methods are in animations.jl; these extend the same function.
animation_name(::Tachikoma.DotWaveBackground) = "dotwave"
animation_name(::Tachikoma.PhyloTreeBackground) = "phylo"
animation_name(::Tachikoma.CladogramBackground) = "clado"

# Tachikoma's glyph backgrounds have no opacity field. They still pass through
# the shared opacity control so switching between color and glyph effects does
# not require a backend-specific branch.
with_intensity(bg::Tachikoma.DotWaveBackground, _) = bg
with_intensity(bg::Tachikoma.PhyloTreeBackground, _) = bg
with_intensity(bg::Tachikoma.CladogramBackground, _) = bg
