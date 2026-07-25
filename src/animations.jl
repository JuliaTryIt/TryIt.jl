# The animated-background family, as values.
#
# These are parameter bundles and a name table — no rendering, no
# colour, no terminal. The code that paints them lives in theming.jl,
# which is the UI layer and may add methods to the functions here.
#
# Themes are deliberately absent: TryIt defines none of its own, it
# consumes whichever the UI layer offers and carries only the *name*
# across the boundary (see `configured_theme` in config.jl).

"""
Backgrounds that animate with cell *background colours* rather than
glyphs.

The glyph backgrounds the UI layer supplies draw braille in the
foreground. Panels only paint the rows they fill, so those glyphs show
through panel interiors as noise, and blanking the interiors erases
them outright — there is no colour underneath to keep. Everything in
this family paints spaces instead, so text over it keeps its own
foreground and inherits the cell background, and panels can be blanked
over it safely.

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
A triangulated mesh, colored with the 4 Julia palette colors.
"""
struct MeshBackground <: ColorBackground
    speed::Float64
    scale::Float64
    intensity::Float64
end
MeshBackground(; speed=0.015, scale=0.04, intensity=0.25) = MeshBackground(speed, scale, intensity)

"""
Every colour-family animation name, in menu order.
"""
const ANIMATION_NAMES = ["fog", "aurora", "plasma", "rain", "pulse", "mesh"]

"""
Spellings that turn the background off.

It is on by default, so the opt-out has to accept whatever a user
reaches for rather than insisting on one magic word.
"""
const BACKGROUND_OFF_NAMES = Set(
    ["", "none", "off", "no", "0", "false", "disabled"])

"""
The colour-family background named by `key`, or `nothing` if the name
does not belong to this family.

`nothing` here means "not mine, ask the next layer" — it does *not*
mean the opt-out, which the caller must test for with
[`BACKGROUND_OFF_NAMES`](@ref) first. Two different meanings for an
empty answer would be one too many, so the off-check is deliberately
kept outside.

`key` is expected already lowercased and stripped.
"""
function color_animation(key::AbstractString)
    # `wash` predates the family and named what is now `fog`.
    (key == "wash" || key == "fog") && return FogBackground()
    key == "aurora" && return AuroraBackground()
    key == "plasma" && return PlasmaBackground()
    key == "rain" && return RainBackground()
    key == "pulse" && return PulseBackground()
    key == "mesh" && return MeshBackground()
    return nothing
end

"""
Clamp a preset index into `1:n`.

Out of range would otherwise index past the end of a preset table
inside the render loop.
"""
_clamp_preset(preset::Integer, n::Integer) = clamp(Int(preset), 1, max(1, n))

"""
The configuration name for `bg`, for persisting the current choice.

The UI layer adds methods for its own background types.
"""
animation_name(::Nothing) = "off"
animation_name(::FogBackground) = "fog"
animation_name(::AuroraBackground) = "aurora"
animation_name(::PlasmaBackground) = "plasma"
animation_name(::RainBackground) = "rain"
animation_name(::PulseBackground) = "pulse"
animation_name(::MeshBackground) = "mesh"

"""
Whether panel interiors should be blanked before drawing `bg`.

The colour family survives blanking — it lives in each cell's
background colour, which the buffer preserves when the incoming style
has none. Glyph backgrounds do not, so the UI layer overrides this to
`false` for its own types and renders them full-bleed.
"""
blanks_panels(::Nothing) = true
blanks_panels(::ColorBackground) = true

"""
Reconstruct a background with a new intensity (opacity).
"""
with_intensity(bg::Nothing, i) = nothing
with_intensity(bg::FogBackground, i) = FogBackground(bg.speed, bg.scale, i)
with_intensity(bg::AuroraBackground, i) = AuroraBackground(bg.speed, i)
with_intensity(bg::PlasmaBackground, i) = PlasmaBackground(bg.speed, bg.scale, i)
with_intensity(bg::RainBackground, i) = RainBackground(bg.speed, i)
with_intensity(bg::PulseBackground, i) = PulseBackground(bg.period, i)
with_intensity(bg::MeshBackground, i) = MeshBackground(bg.speed, bg.scale, i)

