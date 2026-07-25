"""
Binds PluginGuard's static scanner to TryIt's trust layer.

Loaded automatically when both packages are present. Everything
TryIt-side lives behind [`TryIt.TrustScanner`](@ref); this module is
the only place the two vocabularies meet.

EARS coverage: OF7, OF8.
"""
module TryItPluginGuardExt

using TryIt
using PluginGuard

"""
PluginGuard's `TrustCheck` as a TryIt scanner backend.
"""
struct PluginGuardScanner <: TryIt.TrustScanner end

"""
Map a `PluginGuard.Severity` onto TryIt's own vocabulary.

The mapping is total: an unrecognised value becomes `:low` rather
than raising, so a new severity added upstream degrades to an
under-report instead of breaking a clone (OF8).
"""
function _severity(s)
    s === PluginGuard.HIGH && return :high
    s === PluginGuard.MED && return :med
    return :low
end

"""
Scan `path` with `TrustCheck` and translate the result.

`scan_dir` walks the tree and never executes, includes, or imports
what it inspects — which is the whole reason this is safe to run on
a directory that was filled from a URL moments ago.

Exceptions are left to propagate: `TryIt.scan_try` already wraps
this call and converts any failure into an unavailable report, and
duplicating that here would only make the failure harder to trace.
"""
function TryIt.scan_try(::PluginGuardScanner, path::AbstractString)
    findings = PluginGuard.scan_dir(path)
    return TryIt.TrustReport(
        true,
        [TryIt.TrustFinding(f.file, f.line, _severity(f.severity), f.description)
         for f in findings],
        ""
    )
end

function __init__()
    TryIt.register_trust_scanner!(PluginGuardScanner())
    return nothing
end

end # module
