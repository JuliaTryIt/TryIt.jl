# A frame-rate meter, as pure state.
#
# No terminal, no clock of its own: every measurement is driven by a
# timestamp the caller passes in, which is what makes it testable without
# a running event loop. The UI layer feeds it `time()` once per rendered
# frame and reads `.value` back to draw.

"""
Rolling frames-per-second estimate.

Counts frames within a wall-clock window and divides at the window's
end, so the reported rate is an average over the last window rather than
a noisy instantaneous figure. `value` is `0.0` until the first window
closes.
"""
mutable struct FpsMeter
    """
    Timestamp the current window opened at; `NaN` before the first tick.
    """
    window_start::Float64
    """
    Frames counted since `window_start`.
    """
    frames::Int
    """
    Last computed rate, in frames per second.
    """
    value::Float64
end
FpsMeter() = FpsMeter(NaN, 0, 0.0)

"""
Record a rendered frame at time `now` and return the current estimate.

The first call only seeds the window — there is no elapsed time to
divide by yet, so it returns `0.0`. Thereafter each call adds a frame and,
once `window` seconds have passed, recomputes the rate and opens a fresh
window.

`window` trades responsiveness for steadiness: shorter reacts faster,
longer reads smoother.
"""
function fps_tick!(m::FpsMeter, now::Float64; window::Float64=0.5)
    if isnan(m.window_start)
        m.window_start = now
        m.frames = 0
        return m.value
    end
    m.frames += 1
    elapsed = now - m.window_start
    if elapsed >= window
        m.value = elapsed > 0 ? m.frames / elapsed : 0.0
        m.window_start = now
        m.frames = 0
    end
    return m.value
end
