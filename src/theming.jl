# Theme and animated-background configuration.
#
# Both are resolved from the environment once, at selector open, and
# both fail soft: a typo in a config variable must never throw inside
# the render loop or leave the user staring at a broken TUI.

"""
Backgrounds that animate with cell *background colours* rather than
glyphs.

Tachikoma's own backgrounds (`dotwave`, `phylo`, `clado`) draw braille
in the foreground. Panels only paint the rows they fill, so those
glyphs show through panel interiors as noise, and blanking the
interiors erases them outright — there is no colour underneath to
keep. Everything in this family paints spaces instead, so text over it
keeps its own foreground and inherits the cell background, and panels
can be blanked over it safely.

Choosing an animation is independent of choosing a theme: each one
derives its palette from whatever theme is active.
"""
abstract type ColorBackground end

"""
Drifting fractal noise — a slow fog. The default.
"""
struct FogBackground <: ColorBackground
    speed::Float64
    scale::Float64
    intensity::Float64
end
function FogBackground(; speed=0.006, scale=0.09, intensity=0.35)
    FogBackground(speed, scale, intensity)
end

"""
Undulating horizontal bands, brightest toward the top.
"""
struct AuroraBackground <: ColorBackground
    speed::Float64
    intensity::Float64
end
AuroraBackground(; speed=0.02, intensity=0.45) = AuroraBackground(speed, intensity)

"""
Classic interfering sine fields.
"""
struct PlasmaBackground <: ColorBackground
    speed::Float64
    scale::Float64
    intensity::Float64
end
function PlasmaBackground(; speed=0.035, scale=0.18, intensity=0.4)
    PlasmaBackground(speed, scale, intensity)
end

"""
Columns falling at per-column speeds, brightest at the leading edge.
"""
struct RainBackground <: ColorBackground
    speed::Float64
    intensity::Float64
end
RainBackground(; speed=0.12, intensity=0.5) = RainBackground(speed, intensity)

"""
A single slow brightness breath across the whole frame — the
quietest of the family.
"""
struct PulseBackground <: ColorBackground
    period::Int
    intensity::Float64
end
PulseBackground(; period=180, intensity=0.3) = PulseBackground(period, intensity)

"""
Every animation name accepted by [`resolve_background`](@ref), in
menu order.
"""
const ANIMATION_NAMES = ["fog", "aurora", "plasma", "rain", "pulse"]

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

# Palette endpoints, re-read every frame so a live theme change is
# picked up immediately.
function _palette()
    (Tachikoma.to_rgb(Tachikoma.theme().bg),
        Tachikoma.to_rgb(Tachikoma.theme().primary),
        Tachikoma.to_rgb(Tachikoma.theme().accent))
end

@inline function _paint!(buf, x, y, base, target, amount)
    c = Tachikoma.color_lerp(base, target, clamp(amount, 0.0, 1.0))
    Tachikoma.set_char!(buf, x, y, ' ', Tachikoma.Style(bg=c))
    return nothing
end

"""
Draw `bg` across `area` for frame `tick`.
"""
render_selector_background!(bg::Tachikoma.Background, buf, area, tick::Int) = Tachikoma.render_background!(
    bg, buf, area, tick)

function render_selector_background!(bg::FogBackground, buf, area, tick::Int)
    base, target, _ = _palette()
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        # y is scaled harder than x: cells are about twice as tall as
        # wide, so equal factors stretch the field into bands.
        n = Tachikoma.fbm(
            x * bg.scale + tick * bg.speed,
            y * bg.scale * 2 + tick * bg.speed * 0.7
        )
        _paint!(buf, x, y, base, target, n * bg.intensity)
    end
    return nothing
end

function render_selector_background!(bg::AuroraBackground, buf, area, tick::Int)
    base, target, accent = _palette()
    h = max(1, area.height)
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        row = (y - area.y) / h
        # Two out-of-phase waves so the bands fold through each other
        # rather than marching in lockstep.
        wave = sin(x * 0.06 + tick * bg.speed) +
               0.6sin(x * 0.017 - tick * bg.speed * 1.7)
        band = exp(-8 * abs(row - 0.25 - 0.12wave))
        _paint!(buf, x, y, base, row < 0.5 ? accent : target, band * bg.intensity)
    end
    return nothing
end

function render_selector_background!(bg::PlasmaBackground, buf, area, tick::Int)
    base, target, accent = _palette()
    t = tick * bg.speed
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        u = (x - area.x) * bg.scale
        v = (y - area.y) * bg.scale * 2
        n = sin(u + t) + sin(v + t * 0.8) + sin((u + v) * 0.5 + t * 1.3)
        amount = (n / 3 + 1) / 2                     # → [0, 1]
        _paint!(
            buf, x, y, base, amount > 0.5 ? accent : target,
            abs(amount - 0.5) * 2 * bg.intensity
        )
    end
    return nothing
end

function render_selector_background!(bg::RainBackground, buf, area, tick::Int)
    base, target, _ = _palette()
    h = max(1, area.height)
    for x in (area.x):(area.x + area.width - 1)
        # A stable per-column phase and rate, so columns fall at
        # different speeds without any per-frame randomness.
        phase = Tachikoma.noise(x * 0.7)
        rate = 0.5 + Tachikoma.noise(x * 1.9 + 11.0)
        head = mod(phase * h + tick * bg.speed * rate * h, h)
        for y in (area.y):(area.y + area.height - 1)
            Tachikoma.in_bounds(buf, x, y) || continue
            # Distance behind the leading edge, wrapping at the bottom.
            behind = mod((y - area.y) - head, h)
            _paint!(buf, x, y, base, target, exp(-behind / 3) * bg.intensity)
        end
    end
    return nothing
end

function render_selector_background!(bg::PulseBackground, buf, area, tick::Int)
    base, target, _ = _palette()
    amount = Tachikoma.breathe(tick; period=bg.period) * bg.intensity
    for y in (area.y):(area.y + area.height - 1),
        x in (area.x):(area.x + area.width - 1)

        Tachikoma.in_bounds(buf, x, y) || continue
        # Uniform, save for a faint horizontal gradient so the frame
        # does not read as one flat colour.
        edge = 0.15 * (x - area.x) / max(1, area.width)
        _paint!(buf, x, y, base, target, amount + edge)
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
blanks_panels(::Nothing) = true
blanks_panels(::ColorBackground) = true
blanks_panels(::Tachikoma.Background) = false

"""
Environment variable naming the startup theme.

Any of Tachikoma's built-in theme names (`kokaku`, `dracula`,
`gruvbox`, …). Unset or unrecognised leaves the framework default,
which Tachikoma itself persists across runs via Preferences.

The in-app picker (`Ctrl-\\`) still works and takes precedence for the
rest of the session.
"""
const THEME_ENV = "TRY_THEME"

"""
Environment variable selecting the animated background.
"""
const BACKGROUND_ENV = "TRY_BACKGROUND"

"""
Environment variable naming the animation.

An alias for [`BACKGROUND_ENV`](@ref), which takes precedence — it is
the original name. "Animation" says more plainly what is being
chosen, since which effect plays is independent of which theme is
active.
"""
const ANIMATION_ENV = "TRY_ANIMATION"

"""
Environment variable selecting the background's preset index, for the
glyph backgrounds that have variants.
"""
const BACKGROUND_PRESET_ENV = "TRY_BACKGROUND_PRESET"

"""
Background used when [`BACKGROUND_ENV`](@ref) is unset.
"""
const DEFAULT_BACKGROUND = "fog"

# Spellings that turn the background off. It is on by default, so the
# opt-out has to accept whatever a user reaches for rather than
# insisting on one magic word.
const _BACKGROUND_OFF = Set(["", "none", "off", "no", "0", "false", "disabled"])

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
    key in _BACKGROUND_OFF && return nothing

    # `wash` predates the family and named what is now `fog`.
    (key == "wash" || key == "fog") && return FogBackground()
    key == "aurora" && return AuroraBackground()
    key == "plasma" && return PlasmaBackground()
    key == "rain" && return RainBackground()
    key == "pulse" && return PulseBackground()

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

_clamp_preset(preset::Integer, n::Integer) = clamp(Int(preset), 1, max(1, n))

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
    return resolve_background(kind, preset)
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
theme_names() = [t.name for t in Tachikoma.ALL_THEMES]

"""
The configuration name for `bg`, for persisting the current choice.
"""
animation_name(::Nothing) = "off"
animation_name(::FogBackground) = "fog"
animation_name(::AuroraBackground) = "aurora"
animation_name(::PlasmaBackground) = "plasma"
animation_name(::RainBackground) = "rain"
animation_name(::PulseBackground) = "pulse"
animation_name(::Tachikoma.DotWaveBackground) = "dotwave"
animation_name(::Tachikoma.PhyloTreeBackground) = "phylo"
animation_name(::Tachikoma.CladogramBackground) = "clado"
