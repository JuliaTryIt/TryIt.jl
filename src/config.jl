# Persistent settings, read from a TOML file.
#
# Precedence is environment > file > default, matching `try-rs`.
# Everything here fails soft: a missing, unreadable or malformed file
# yields defaults rather than stopping the CLI from starting. A
# hand-edited config with a typo in it should cost the user a wrong
# theme, not their tool.
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
function read_config()
    path = config_path()
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
function write_config(cfg::AbstractDict)
    path = config_path()
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
function _setting(env::AbstractString, key::AbstractString, default::AbstractString)
    from_env = strip(get(ENV, env, ""))
    isempty(from_env) || return String(from_env)
    value = get(read_config(), key, "")
    value isa AbstractString && !isempty(strip(value)) && return String(strip(value))
    return String(default)
end

"""
The theme to activate at startup.

Empty means "leave whatever is active", which is what Tachikoma
restores from its own preferences.
"""
configured_theme() = _setting(THEME_ENV, "theme", "")

"""
The animation to play behind the selector.

`TRY_BACKGROUND` is checked before `TRY_ANIMATION` — it is the older
name and keeps precedence — then the file, then the default.
"""
function configured_animation()
    from_background = strip(get(ENV, BACKGROUND_ENV, ""))
    isempty(from_background) || return String(from_background)
    return _setting(ANIMATION_ENV, "animation", DEFAULT_BACKGROUND)
end

"""
Persist the active theme and animation.

Returns a message describing the outcome, for display in the help
bar: writing a file the user never sees needs to say so.
"""
function save_settings(animation::AbstractString)
    path = config_path()
    ok = write_config(
        Dict("theme" => Tachikoma.theme().name, "animation" => animation)
    )
    return ok ? string("saved to ", path) : string("could not write ", path)
end
