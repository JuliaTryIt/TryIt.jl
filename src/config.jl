# Persistent settings, read from a TOML file.
#
# Precedence is environment > file > default, matching `try-rs`.
# Everything here fails soft: a missing, unreadable or malformed file
# yields defaults rather than stopping the CLI from starting. A
# hand-edited config with a typo in it should cost the user a wrong
# theme, not their tool.
#
# Every entry point takes the path explicitly, defaulting to
# `config_path()`. Tests must pass one rather than setting
# `TRY_CONFIG`: `withenv` mutates the process-global `ENV`, so with
# test items running concurrently one item's cleanup can clear
# another's override — and a `write_config` that then falls back to
# the default would write into the developer's real home directory.
# That happened.
#
# EARS coverage: OF6, ED22.

"""
Environment variable overriding the config file location outright.
"""
const CONFIG_ENV = "TRY_CONFIG"

"""
Path to the configuration file.

`TRY_CONFIG` wins outright, then `\$XDG_CONFIG_HOME/tryit/config.toml`,
then `~/.config/tryit/config.toml`. XDG is honoured on every platform,
including macOS, so a dotfile repository behaves the same everywhere.
"""
function config_path()
    override = get(ENV, CONFIG_ENV, "")
    isempty(override) || return String(override)
    base = get(ENV, "XDG_CONFIG_HOME", "")
    isempty(base) && (base = joinpath(get(ENV, "HOME", homedir()), ".config"))
    return joinpath(base, "tryit", "config.toml")
end

"""
Parse the configuration file, or return an empty `Dict`.

Never throws: an absent file is the normal case, and a malformed one
is a typo the user can fix at leisure.
"""
function read_config(path::AbstractString=config_path())
    isfile(path) || return Dict{String, Any}()
    return try
        TOML.parsefile(path)
    catch
        Dict{String, Any}()
    end
end

"""
Write `cfg` to the configuration file, creating parent directories.

Returns whether the write succeeded; failure is reported to the
caller rather than thrown, so a read-only config directory cannot
take down the selector.
"""
function write_config(cfg::AbstractDict, path::AbstractString=config_path())
    return try
        mkpath(dirname(path))
        open(path, "w") do io
            TOML.print(io, Dict(String(k) => v for (k, v) in cfg))
        end
        true
    catch
        false
    end
end

"""
Look `key` up with environment-over-file-over-default precedence.

`env` is consulted first so a one-off `TRY_THEME=nord tryit` still
works without touching the file.
"""
function _setting(
        env::AbstractString, key::AbstractString, default::AbstractString,
        path::AbstractString=config_path()
)
    from_env = strip(get(ENV, env, ""))
    isempty(from_env) || return String(from_env)
    value = get(read_config(path), key, "")
    value isa AbstractString && !isempty(strip(value)) && return String(strip(value))
    return String(default)
end

"""
Environment variable naming the startup theme.

The set of valid names is the UI layer's to define; an unrecognised
one leaves whatever that layer defaults to. The in-app picker still
works and takes precedence for the rest of the session.
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
Background used when [`BACKGROUND_ENV`](@ref) is unset.
"""
const DEFAULT_BACKGROUND = "fog"

"""
The theme to activate at startup.

Empty means "leave whatever is active" — the UI layer restores its
own last-used theme, so the core has nothing to impose.
"""
function configured_theme(path::AbstractString=config_path())
    _setting(
        THEME_ENV, "theme", "", path)
end

"""
The animation to play behind the selector.

`TRY_BACKGROUND` is checked before `TRY_ANIMATION` — it is the older
name and keeps precedence — then the file, then the default.
"""
function configured_animation(path::AbstractString=config_path())
    from_background = strip(get(ENV, BACKGROUND_ENV, ""))
    isempty(from_background) || return String(from_background)
    return _setting(ANIMATION_ENV, "animation", DEFAULT_BACKGROUND, path)
end

"""
Persist the active theme and animation.

Returns a message describing the outcome, for display in the help
bar: writing a file the user never sees needs to say so.

`theme` is passed in rather than read from the active UI layer — the
core cannot reach one. See the architecture boundary test.
"""
function save_settings(
        theme::AbstractString, animation::AbstractString, opacity::Float64=0.25,
        path::AbstractString=config_path()
)
    # Merge, never replace. The file also holds settings this function
    # knows nothing about — `tries_path`, `timezone`, and whatever a
    # later version adds — all of them hand-written and none of them
    # recoverable once overwritten. Losing `tries_path` in particular
    # hides every try, which reads as data loss rather than a reset
    # preference.
    cfg = read_config(path)
    cfg["theme"] = theme
    cfg["animation"] = animation
    cfg["opacity"] = opacity
    ok = write_config(cfg, path)
    return ok ? string("saved to ", path) : string("could not write ", path)
end

"""
Environment variable overriding the selector's opacity.
"""
const OPACITY_ENV = "TRY_OPACITY"

"""
Read `value` as an opacity, or `nothing` if it names none.
"""
function _opacity_from(value)
    n = if value isa Bool
        nothing
    elseif value isa Real
        Float64(value)
    elseif value isa AbstractString
        tryparse(Float64, strip(value))
    else
        nothing
    end
    (n === nothing || !isfinite(n)) && return nothing
    return clamp(n, 0.0, 1.0)
end

"""
Background opacity for the selector.
"""
function configured_opacity(path::AbstractString=config_path())
    from_env = _opacity_from(strip(get(ENV, OPACITY_ENV, "")))
    from_env === nothing || return from_env
    from_file = _opacity_from(get(read_config(path), "opacity", nothing))
    from_file === nothing || return from_file
    return 0.25
end

"""
Environment variable overriding the selector's frame rate.
"""
const FPS_ENV = "TRY_FPS"

"""
Frames per second used when [`FPS_ENV`](@ref) and the config file are
both silent. Matches the render loop's own default.
"""
const DEFAULT_FPS = 60

"""
Lowest frame rate the selector will run at.

Zero would divide by zero in the render loop's frame pacing, and a
negative rate names nothing, so the floor is one frame per second
rather than an error.
"""
const MIN_FPS = 1

"""
Highest frame rate the selector will run at.

Well past any display's refresh rate: beyond this the extra frames are
written to a terminal that cannot show them.
"""
const MAX_FPS = 240

"""
Read `value` as a frame rate, or `nothing` if it names none.

Accepts a number or a numeric string, since TOML does no coercion and
a hand-edited `fps = "24"` means what it says. `Bool` is rejected
despite being a `Real` in Julia — `fps = true` is a mistake, not a
request for one frame per second.
"""
function _fps_from(value)
    n = if value isa Bool
        nothing
    elseif value isa Real
        Float64(value)
    elseif value isa AbstractString
        tryparse(Float64, strip(value))
    else
        nothing
    end
    (n === nothing || !isfinite(n)) && return nothing
    return clamp(round(Int, n), MIN_FPS, MAX_FPS)
end

"""
Frames per second for the selector's render loop.

Lowering this is the remedy for a terminal that cannot keep up with an
animated background: every frame repaints each cell it covers, so the
cost is per frame and scales directly with this number. Which terminals
struggle, and why, is a property of the terminal rather than of this
setting — see the Interface page.

Unlike the other settings, an unusable override falls through to the
file rather than straight to the default, so a typo in `TRY_FPS` still
leaves the configured value in charge.
"""
function configured_fps(path::AbstractString=config_path())
    from_env = _fps_from(strip(get(ENV, FPS_ENV, "")))
    from_env === nothing || return from_env
    from_file = _fps_from(get(read_config(path), "fps", nothing))
    from_file === nothing || return from_file
    return DEFAULT_FPS
end

"""
Environment variable toggling the on-screen frame-rate readout.
"""
const SHOW_FPS_ENV = "TRY_SHOW_FPS"

"""
Read `value` as a boolean, or `nothing` if it names neither state.

Accepts a real boolean or one of the usual truthy/falsy spellings, since
TOML has one and a hand-edited file or an environment variable may carry
the other. Anything unrecognised is `nothing` so the caller can fall
back rather than guess.
"""
function _bool_from(value)
    value isa Bool && return value
    if value isa AbstractString
        s = lowercase(strip(value))
        s in ("true", "yes", "on", "1") && return true
        s in ("false", "no", "off", "0") && return false
    end
    return nothing
end

"""
Whether to draw a small frames-per-second readout over the selector.

Off by default — it is a diagnostic overlay, useful for judging how a
particular terminal keeps up with the animated background. A typo leaves
it off rather than turning it on.
"""
function configured_show_fps(path::AbstractString=config_path())
    from_env = _bool_from(strip(get(ENV, SHOW_FPS_ENV, "")))
    from_env === nothing || return from_env
    from_file = _bool_from(get(read_config(path), "show_fps", nothing))
    from_file === nothing || return from_file
    return false
end

"""
Environment variable overriding the date zone.
"""
const TIMEZONE_ENV = "TRY_TIMEZONE"

"""
Which clock dates are taken from: `:local` (default) or `:utc`.

Anything unrecognised is treated as `:local` — a typo in a
hand-edited config should cost a wrong date at worst.
"""
function date_zone(path::AbstractString=config_path())
    raw = lowercase(_setting(TIMEZONE_ENV, "timezone", "local", path))
    return raw == "utc" ? :utc : :local
end

"""
Calendar date of the unix timestamp `t`, in the configured zone.

Used for directories that carry no date prefix, where the filesystem
mtime stands in for one.
"""
function display_date(t::Real, zone::Symbol=date_zone())
    dt = Dates.unix2datetime(t)
    zone === :utc && return Date(dt)
    return Date(dt + (Dates.now() - Dates.now(Dates.UTC)))
end

"""
Today's date in the configured zone.

Every date TryIt *writes* comes from here, so that a prefix it stamps
and a date it displays are read off the same clock.
"""
function current_date(zone::Symbol=date_zone())
    zone === :utc ? Date(Dates.now(Dates.UTC)) :
    Dates.today()
end
