"""
A kebab-cased projection of a user-supplied name. Construction is
idempotent: `slug(slug(x).value).value == slug(x).value`.

EARS coverage: UB3.
"""
struct Slug
    """
    Canonical slug string (characters from `[a-z0-9-]`).
    """
    value::String
end

"""
Project `input` into a `Slug`.

Steps (FR-003 / UB3):

 1. NFKD normalise.
 2. Drop combining marks.
 3. Lowercase.
 4. Replace every run of non-`[a-z0-9]` characters with a single `-`.
 5. Trim leading / trailing `-`.

Throws `ArgumentError("empty slug")` if the result would be empty.

EARS coverage: UB3, UB6 (feeds `ExitCode.USAGE`).
"""
function slug(input::AbstractString)
    # NFKD normalise and strip combining marks in one call — handles
    # "Réécriture" → "Reecriture" deterministically on every OS.
    stripped = Unicode.normalize(
        input;
        decompose=true,
        compat=true,
        stripmark=true
    )
    lower = lowercase(stripped)
    dashed = replace(lower, r"[^a-z0-9]+" => "-")
    trimmed = strip(dashed, '-')
    isempty(trimmed) && throw(ArgumentError("empty slug"))
    return Slug(String(trimmed))
end

Base.string(s::Slug) = s.value
Base.print(io::IO, s::Slug) = print(io, s.value)
Base.:(==)(a::Slug, b::Slug) = a.value == b.value
Base.hash(s::Slug, h::UInt) = hash(s.value, hash(:Slug, h))
