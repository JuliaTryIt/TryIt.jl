# Theme and animated-background configuration.
#
# Both are resolved from the environment once, at selector open, and
# both fail soft: a typo in a config variable must never throw inside
# the render loop or leave the user staring at a broken TUI.

"""
Animated colour wash — the default background.

Tachikoma's own backgrounds (`dotwave`, `phylo`, `clado`) draw braille
glyphs in the *foreground*. Panels only paint the rows they fill, so
those glyphs show through panel interiors as noise, and blanking the
interiors erases the background outright — there is no background
colour underneath to keep.

This one paints spaces with an animated background *colour* instead.
Text drawn over it keeps its own foreground and inherits the cell's
background, so the frame animates without ever competing with the
content.

Fields tune the noise field; the defaults are deliberately subtle.
"""
struct WashBackground
    "Multiplier on the frame counter. Larger drifts faster."
    speed::Float64
    "Spatial frequency of the noise. Larger means finer detail."
    scale::Float64
    "Peak blend toward the theme's accent, in `[0, 1]`."
    intensity::Float64
end

function WashBackground(; speed=0.006, scale=0.09, intensity=0.35)
    WashBackground(speed, scale, intensity)
end

"""
Any background the selector can render.

`WashBackground` is ours; the rest come from Tachikoma.
"""
const SelectorBackground = Union{Tachikoma.Background, WashBackground}

"""
Draw `bg` across `area` for frame `tick`.

Dispatches between our wash and Tachikoma's glyph backgrounds so the
view does not have to care which kind it holds.
"""
render_selector_background!(bg::Tachikoma.Background, buf, area, tick::Int) = Tachikoma.render_background!(
    bg, buf, area, tick)

function render_selector_background!(bg::WashBackground, buf, area, tick::Int)
    th = Tachikoma.theme()
    base = Tachikoma.to_rgb(th.bg)
    accent = Tachikoma.to_rgb(th.primary)
    for y in (area.y):(area.y + area.height - 1)
        for x in (area.x):(area.x + area.width - 1)
            Tachikoma.in_bounds(buf, x, y) || continue
            # y is scaled harder than x: terminal cells are roughly
            # twice as tall as wide, so equal factors would stretch
            # the field into horizontal bands.
            n = Tachikoma.fbm(
                x * bg.scale + tick * bg.speed,
                y * bg.scale * 2 + tick * bg.speed * 0.7
            )
            c = Tachikoma.color_lerp(base, accent, clamp(n * bg.intensity, 0.0, 1.0))
            Tachikoma.set_char!(buf, x, y, ' ', Tachikoma.Style(bg=c))
        end
    end
    return nothing
end

"""
Whether panel interiors should be blanked before drawing `bg`.

The wash survives blanking — it lives in each cell's background
colour, which `set_char!` preserves when the incoming style has none.
Glyph backgrounds do not, so they are rendered full-bleed and show
through the panels, as they do in Tachikoma's own demos.
"""
blanks_panels(::Nothing) = true
blanks_panels(::WashBackground) = true
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
Environment variable selecting the background's preset index.
"""
const BACKGROUND_PRESET_ENV = "TRY_BACKGROUND_PRESET"

"""
Background used when [`BACKGROUND_ENV`](@ref) is unset.
"""
const DEFAULT_BACKGROUND = "wash"

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

    if key == "wash"
        return WashBackground()
    elseif key == "phylo"
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
    return WashBackground()
end

_clamp_preset(preset::Integer, n::Integer) = clamp(Int(preset), 1, max(1, n))

"""
Resolve the animated background from the environment.

Returns `nothing` when the user opted out, or when Tachikoma's global
motion switch is off — respecting a reduced-motion preference matters
more than our default.
"""
function background_from_env()
    Tachikoma.animations_enabled() || return nothing
    kind = get(ENV, BACKGROUND_ENV, DEFAULT_BACKGROUND)
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
"""
apply_theme_from_env!() = apply_theme!(get(ENV, THEME_ENV, ""))

"""
Every built-in theme name, for documentation and error messages.
"""
theme_names() = [t.name for t in Tachikoma.ALL_THEMES]
