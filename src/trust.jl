# Advisory trust reporting for code that arrived from a URL.
#
# The core owns the vocabulary and the dispatch point; the scanning
# itself belongs to an optional backend loaded as a package extension.
# Nothing here names that backend, and nothing here depends on it —
# that is what keeps the weak dependency weak, and what lets a second
# backend exist without touching this file.

"""
One thing a scanner found, in TryIt's own vocabulary.

`severity` is `:low`, `:med` or `:high`. A backend's own severity
type is mapped onto these three at the boundary rather than being
re-exported: the core must not gain a type it cannot construct
without the optional dependency present.

EARS coverage: OF7.
"""
struct TrustFinding
    file::String
    line::Int
    severity::Symbol
    description::String
end

"""
The outcome of scanning a try.

`available` distinguishes *nothing was found* from *nothing looked*,
and the distinction is the point: a caller that collapses them
reports a tree as clean when no scanner ever ran. `error` is
non-empty only when a scan was attempted and failed.

EARS coverage: OF7, OF8.
"""
struct TrustReport
    available::Bool
    findings::Vector{TrustFinding}
    error::String
end

TrustReport() = TrustReport(false, TrustFinding[], "")

"""
Backend that can inspect a directory for untrusted-code indicators.

A trait rather than a function reference: an extension adds a
subtype and a [`scan_try`](@ref) method for it, which is ordinary
dispatch rather than a callback that has to be installed correctly.

EARS coverage: OF7.
"""
abstract type TrustScanner end

"""
The default backend, which scans nothing.

Its report is *unavailable*, never *clean*.

EARS coverage: OF7, OF8.
"""
struct NoScanner <: TrustScanner end

"""
The active backend.

A `Ref` rather than a constant because a package extension can only
register itself from `__init__`, which runs after this module is
loaded. Abstractly typed on purpose: the concrete scanner type lives
in an extension the core cannot name.

EARS coverage: OF7.
"""
const TRUST_SCANNER = Ref{TrustScanner}(NoScanner())

"""
Install `scanner` as the active backend, returning it.

Called from an extension's `__init__`, and from tests that need to
swap a stub in and put the previous one back.

EARS coverage: OF7.
"""
function register_trust_scanner!(scanner::TrustScanner)
    TRUST_SCANNER[] = scanner
    return scanner
end

"""
Scan `path` with the active backend.

Never throws. A backend that fails — for any reason, including one
the core cannot anticipate because it does not know what the backend
is — yields an unavailable report carrying the message. This runs
after an operation that has already succeeded on disk, so letting it
raise would turn a completed clone or fetch into a failed command
(OF8).

EARS coverage: OF7, OF8.
"""
function scan_try(path::AbstractString)::TrustReport
    return try
        # `invokelatest` is load-bearing, not defensive. The backend
        # may have been loaded moments ago, inside the very call that
        # leads here — and a method added after this function started
        # executing is invisible to it, so a direct call raises
        # `MethodError` in a world age that predates the extension.
        # Caught, that became an *unavailable* report: the scanner was
        # live, the finding was real, and the user was told nothing.
        Base.invokelatest(scan_try, TRUST_SCANNER[], path)
    catch err
        TrustReport(false, TrustFinding[], _trust_error_message(err))
    end
end

"""
The no-backend case: nothing looked, so nothing is known.

EARS coverage: OF7, OF8.
"""
scan_try(::NoScanner, ::AbstractString) = TrustReport()

"""
Rank a severity so findings can be compared.

Total by construction: an unrecognised symbol ranks below every real
severity rather than throwing. Severities arrive from a backend the
core does not control, and a typo there must not abort a clone (OF8).

EARS coverage: OF7, OF8.
"""
function trust_rank(severity::Symbol)
    severity === :high && return 3
    severity === :med && return 2
    severity === :low && return 1
    return 0
end

"""
The worst severity in `report`, or `nothing` when it holds no
findings.

Returns `nothing` both for a clean scan and for an unavailable one;
`report.available` is what separates those two.

EARS coverage: OF7.
"""
function trust_max_severity(report::TrustReport)
    isempty(report.findings) && return nothing
    worst = report.findings[1].severity
    for finding in report.findings
        trust_rank(finding.severity) > trust_rank(worst) && (worst = finding.severity)
    end
    return worst
end

"""
Reduce a backend's exception to one line.

Same one-line discipline `diag` imposes everywhere else (UB5).
"""
function _trust_error_message(err)
    for line in eachsplit(sprint(showerror, err), '\n')
        stripped = strip(line)
        isempty(stripped) || return String(stripped)
    end
    return "unknown error"
end
