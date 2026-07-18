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
The theme to activate at startup.

Empty means "leave whatever is active", which is what Tachikoma
restores from its own preferences.
"""
configured_theme(path::AbstractString=config_path()) = _setting(
    THEME_ENV, "theme", "", path)

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
"""
function save_settings(
        animation::AbstractString, path::AbstractString=config_path()
)
    ok = write_config(
        Dict("theme" => Tachikoma.theme().name, "animation" => animation), path
    )
    return ok ? string("saved to ", path) : string("could not write ", path)
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
current_date(zone::Symbol=date_zone()) = zone === :utc ? Date(Dates.now(Dates.UTC)) :
                                         Dates.today()
