import Foundation

// MARK: - TOSPlaybackTimeline
//
// Pure timeline math for the TOS player's self-drawn control layer (GitHub
// issue #1). Lives in SmartTubeIOSCore — Foundation-only, no SwiftUI/WebKit —
// so the formatting/clamping logic can be unit-tested on every platform
// without instantiating a player.
//
// The self-drawn control bar needs to render a scrubber, buffered underlay,
// time labels, and ad-aware seeking. All of that is derived from three
// doubles the JS bridge reports (currentTime, duration, buffered end) plus an
// ad flag — this type is the single source of truth for those conversions so
// the view code stays declarative and testable.

public enum TOSPlaybackTimeline {
    /// Formats a playback position as `m:ss` (e.g. "0:07", "12:34"), switching to
    /// `h:mm:ss` from one hour on (e.g. "1:02:03"). Truncates fractional seconds,
    /// matching YouTube's own labels. Negative, NaN, or infinite input renders "0:00".
    public static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Played fraction of the timeline, clamped to `0...1`. Returns 0 for a
    /// non-positive/NaN duration (embed not ready yet, live stream without a
    /// duration, etc.) so the scrubber renders empty instead of NaN-width.
    public static func progressFraction(current: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, current.isFinite else { return 0 }
        return min(max(current / duration, 0), 1)
    }

    /// Buffered fraction of the timeline, clamped to `0...1`. `bufferedEnd` is the
    /// end of the last `video.buffered` range reported by the embed's JS bridge.
    public static func bufferedFraction(bufferedEnd: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, bufferedEnd.isFinite else { return 0 }
        return min(max(bufferedEnd / duration, 0), 1)
    }

    /// Whether the user may seek right now. Seeking is blocked while YouTube is
    /// playing an ad (the ad's timeline is not the video's) and before the embed
    /// has reported a usable duration.
    public static func canSeek(duration: Double, isPlayingAd: Bool) -> Bool {
        guard duration.isFinite, duration > 0 else { return false }
        return !isPlayingAd
    }
}
