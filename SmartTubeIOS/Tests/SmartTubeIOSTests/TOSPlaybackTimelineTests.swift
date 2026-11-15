import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - TOSPlaybackTimelineTests
//
// Unit tests for the pure timeline math behind the TOS player's self-drawn
// control layer (GitHub issue #1, 彻底自绘播放器). The type lives in
// SmartTubeIOSCore precisely so these conversions can be exercised without a
// WKWebView or a player instance: the embed's JS bridge reports raw doubles
// (currentTime, duration, buffered end) plus an ad flag, and the control bar
// renders whatever these helpers return.

@Suite("TOS playback timeline (self-drawn controls)")
struct TOSPlaybackTimelineTests {

    // MARK: - timeLabel

    @Test("Zero renders as 0:00")
    func timeLabelZero() {
        #expect(TOSPlaybackTimeline.timeLabel(0) == "0:00")
    }

    @Test("Sub-minute positions render m:ss with a padded seconds field")
    func timeLabelSubMinute() {
        #expect(TOSPlaybackTimeline.timeLabel(7) == "0:07")
        #expect(TOSPlaybackTimeline.timeLabel(59) == "0:59")
    }

    @Test("Minute boundaries roll over correctly")
    func timeLabelMinuteBoundaries() {
        #expect(TOSPlaybackTimeline.timeLabel(60) == "1:00")
        #expect(TOSPlaybackTimeline.timeLabel(3599) == "59:59")
    }

    @Test("One hour and beyond switch to h:mm:ss")
    func timeLabelHours() {
        #expect(TOSPlaybackTimeline.timeLabel(3600) == "1:00:00")
        #expect(TOSPlaybackTimeline.timeLabel(3661) == "1:01:01")
        #expect(TOSPlaybackTimeline.timeLabel(7384) == "2:03:04")
    }

    @Test("Fractional seconds are truncated, never rounded up")
    func timeLabelTruncatesFractions() {
        #expect(TOSPlaybackTimeline.timeLabel(7.999) == "0:07")
        #expect(TOSPlaybackTimeline.timeLabel(59.5) == "0:59")
        #expect(TOSPlaybackTimeline.timeLabel(3599.99) == "59:59")
        #expect(TOSPlaybackTimeline.timeLabel(0.9) == "0:00")
    }

    @Test("Negative input renders 0:00")
    func timeLabelNegative() {
        #expect(TOSPlaybackTimeline.timeLabel(-1) == "0:00")
        #expect(TOSPlaybackTimeline.timeLabel(-0.5) == "0:00")
    }

    @Test("NaN and infinite input render 0:00")
    func timeLabelNonFinite() {
        #expect(TOSPlaybackTimeline.timeLabel(.nan) == "0:00")
        #expect(TOSPlaybackTimeline.timeLabel(.infinity) == "0:00")
        #expect(TOSPlaybackTimeline.timeLabel(-.infinity) == "0:00")
    }

    // MARK: - progressFraction

    @Test("Played fraction is current over duration")
    func progressFractionBasic() {
        #expect(TOSPlaybackTimeline.progressFraction(current: 0, duration: 100) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: 25, duration: 100) == 0.25)
        #expect(TOSPlaybackTimeline.progressFraction(current: 50, duration: 100) == 0.5)
        #expect(TOSPlaybackTimeline.progressFraction(current: 100, duration: 100) == 1)
    }

    @Test("Played fraction clamps to 0...1")
    func progressFractionClamps() {
        #expect(TOSPlaybackTimeline.progressFraction(current: 150, duration: 100) == 1)
        #expect(TOSPlaybackTimeline.progressFraction(current: -10, duration: 100) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: -0.001, duration: 100) == 0)
    }

    @Test("Unusable durations yield an empty bar instead of NaN")
    func progressFractionInvalidDuration() {
        #expect(TOSPlaybackTimeline.progressFraction(current: 10, duration: 0) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: 10, duration: -5) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: 10, duration: .nan) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: 10, duration: .infinity) == 0)
    }

    @Test("Non-finite current yields 0")
    func progressFractionInvalidCurrent() {
        #expect(TOSPlaybackTimeline.progressFraction(current: .nan, duration: 100) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: .infinity, duration: 100) == 0)
        #expect(TOSPlaybackTimeline.progressFraction(current: -.infinity, duration: 100) == 0)
    }

    // MARK: - bufferedFraction

    @Test("Buffered fraction is buffered end over duration")
    func bufferedFractionBasic() {
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 0, duration: 100) == 0)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 25, duration: 100) == 0.25)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 100, duration: 100) == 1)
    }

    @Test("Buffered fraction clamps to 0...1")
    func bufferedFractionClamps() {
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 250, duration: 100) == 1)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: -25, duration: 100) == 0)
    }

    @Test("Unusable duration or buffered end yields 0")
    func bufferedFractionInvalidInput() {
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 10, duration: 0) == 0)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 10, duration: -100) == 0)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: 10, duration: .nan) == 0)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: .nan, duration: 100) == 0)
        #expect(TOSPlaybackTimeline.bufferedFraction(bufferedEnd: .infinity, duration: 100) == 0)
    }

    // MARK: - canSeek

    @Test("Seeking is allowed with a positive finite duration and no ad")
    func canSeekAllowed() {
        #expect(TOSPlaybackTimeline.canSeek(duration: 100, isPlayingAd: false))
        #expect(TOSPlaybackTimeline.canSeek(duration: 0.5, isPlayingAd: false))
    }

    @Test("Seeking is blocked while an ad plays")
    func canSeekBlockedDuringAd() {
        #expect(!TOSPlaybackTimeline.canSeek(duration: 100, isPlayingAd: true))
        #expect(!TOSPlaybackTimeline.canSeek(duration: 0.5, isPlayingAd: true))
    }

    @Test("Seeking is blocked before a usable duration is known")
    func canSeekBlockedWithoutDuration() {
        #expect(!TOSPlaybackTimeline.canSeek(duration: 0, isPlayingAd: false))
        #expect(!TOSPlaybackTimeline.canSeek(duration: -10, isPlayingAd: false))
        #expect(!TOSPlaybackTimeline.canSeek(duration: .nan, isPlayingAd: false))
        #expect(!TOSPlaybackTimeline.canSeek(duration: .infinity, isPlayingAd: false))
        // The ad guard must not mask the duration guard.
        #expect(!TOSPlaybackTimeline.canSeek(duration: .nan, isPlayingAd: true))
    }
}
