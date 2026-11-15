#if os(macOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TOSPlayerScrubber
//
// Custom scrubber: played track, buffered underlay, SponsorBlock segment bands
// and chapter ticks (a Slider cannot layer those), hence GeometryReader +
// DragGesture. While dragging, the thumb follows the pointer and seeks live;
// the poll-driven model.currentTime takes over again on release.

struct TOSPlayerScrubber: View {
    let model: TOSPlayerControlsModel
    let isEnabled: Bool
    let onSeek: (Double) -> Void
    let onScrubbingChanged: (Bool) -> Void

    @State private var dragFraction: Double?

    private var playedFraction: Double {
        dragFraction
            ?? TOSPlaybackTimeline.progressFraction(current: model.currentTime, duration: model.duration)
    }

    private var bufferedFraction: Double {
        TOSPlaybackTimeline.bufferedFraction(bufferedEnd: model.bufferedEnd, duration: model.duration)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let barHeight: CGFloat = 3
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(height: barHeight)
                Capsule()
                    .fill(.white.opacity(0.42))
                    .frame(width: width * bufferedFraction, height: barHeight)
                sponsorBands(width: width, barHeight: barHeight)
                chapterTicks(width: width, barHeight: barHeight)
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: width * playedFraction, height: barHeight)
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .offset(x: width * playedFraction - 5.5)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, model.duration > 0 else { return }
                        if dragFraction == nil {
                            onScrubbingChanged(true)
                        }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        dragFraction = fraction
                        onSeek(fraction * model.duration)
                    }
                    .onEnded { _ in
                        guard dragFraction != nil else { return }
                        dragFraction = nil
                        onScrubbingChanged(false)
                    }
            )
        }
        .frame(height: 18)
        .accessibilityIdentifier("tosPlayer.controls.scrubber")
        .accessibilityLabel(Text("Playback position", bundle: L10n.bundle))
        .accessibilityValue(
            "\(TOSPlaybackTimeline.timeLabel(model.currentTime)) / \(TOSPlaybackTimeline.timeLabel(model.duration))"
        )
    }

    @ViewBuilder
    private func sponsorBands(width: CGFloat, barHeight: CGFloat) -> some View {
        if model.duration > 0 {
            ForEach(model.sponsorSegments) { segment in
                let start = min(max(segment.start / model.duration, 0), 1)
                let end = min(max(segment.end / model.duration, 0), 1)
                Capsule()
                    .fill(segment.category.color.opacity(0.9))
                    .frame(width: max((end - start) * width, 1), height: barHeight)
                    .offset(x: start * width)
            }
        }
    }

    @ViewBuilder
    private func chapterTicks(width: CGFloat, barHeight: CGFloat) -> some View {
        if model.duration > 0 {
            ForEach(model.chapters) { chapter in
                let fraction = min(max(chapter.startTime / model.duration, 0), 1)
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: 1, height: barHeight + 2)
                    .offset(x: fraction * width)
            }
        }
    }
}

#endif
