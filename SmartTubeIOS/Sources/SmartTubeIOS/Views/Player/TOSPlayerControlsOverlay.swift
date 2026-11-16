#if os(macOS)
import AppKit
import SmartTubeIOSCore
import SwiftUI
import os

/// Logger for the self-drawn TOS player control layer (GitHub issue #1).
private let tosControlsOverlayLog = Logger(
    subsystem: "com.void.smarttube.app", category: "TOSPlayerControls")

// MARK: - TOSPlayerControlsModel
//
// Immutable snapshot of everything the self-drawn control layer renders. The
// parent view builds it from TOSPlayerViewModel + the user's settings; the
// overlay itself is a dumb view, which keeps this file free of playback logic.

public struct TOSPlayerControlsModel: Equatable, Sendable {
    public var title: String
    public var channelTitle: String
    public var currentTime: Double
    public var duration: Double
    public var bufferedEnd: Double
    public var isPlaying: Bool
    public var isPlayingAd: Bool
    public var isMuted: Bool
    /// 0...1, mirrors the embed's video.volume.
    public var volume: Double
    public var isFullScreen: Bool
    public var speedLabel: String
    public var canGoPrevious: Bool
    public var canGoNext: Bool
    public var seekBackSeconds: Int
    public var seekForwardSeconds: Int
    public var chapters: [Chapter]
    public var sponsorSegments: [SponsorSegment]

    public init(
        title: String,
        channelTitle: String,
        currentTime: Double,
        duration: Double,
        bufferedEnd: Double,
        isPlaying: Bool,
        isPlayingAd: Bool,
        isMuted: Bool,
        volume: Double,
        isFullScreen: Bool,
        speedLabel: String,
        canGoPrevious: Bool,
        canGoNext: Bool,
        seekBackSeconds: Int,
        seekForwardSeconds: Int,
        chapters: [Chapter],
        sponsorSegments: [SponsorSegment]
    ) {
        self.title = title
        self.channelTitle = channelTitle
        self.currentTime = currentTime
        self.duration = duration
        self.bufferedEnd = bufferedEnd
        self.isPlaying = isPlaying
        self.isPlayingAd = isPlayingAd
        self.isMuted = isMuted
        self.volume = volume
        self.isFullScreen = isFullScreen
        self.speedLabel = speedLabel
        self.canGoPrevious = canGoPrevious
        self.canGoNext = canGoNext
        self.seekBackSeconds = seekBackSeconds
        self.seekForwardSeconds = seekForwardSeconds
        self.chapters = chapters
        self.sponsorSegments = sponsorSegments
    }
}

// MARK: - TOSPlayerControlsActions
//
// Every user gesture the overlay can emit: 1:1 with the TOSPlayerViewModel
// control APIs plus two parent-owned closures (close the player, toggle native
// full screen).

public struct TOSPlayerControlsActions {
    public var onClose: () -> Void
    public var onPlayPause: () -> Void
    public var onSeek: (Double) -> Void
    public var onSeekRelative: (Double) -> Void
    public var onPrevious: () -> Void
    public var onNext: () -> Void
    public var onToggleFullscreen: () -> Void
    public var onToggleMute: () -> Void
    public var onVolumeChange: (Double) -> Void
    public var onSpeedSelected: (Double) -> Void

    public init(
        onClose: @escaping () -> Void,
        onPlayPause: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void,
        onSeekRelative: @escaping (Double) -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onToggleFullscreen: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onVolumeChange: @escaping (Double) -> Void,
        onSpeedSelected: @escaping (Double) -> Void
    ) {
        self.onClose = onClose
        self.onPlayPause = onPlayPause
        self.onSeek = onSeek
        self.onSeekRelative = onSeekRelative
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onToggleFullscreen = onToggleFullscreen
        self.onToggleMute = onToggleMute
        self.onVolumeChange = onVolumeChange
        self.onSpeedSelected = onSpeedSelected
    }
}

// MARK: - TOSPlayerControlsOverlay
//
// The app-drawn chrome for the TOS IFrame player (GitHub issue #1). Rendered
// inside TOSPlayerView's ZStack above the WKWebView; the embed loads with
// controls=0 when this overlay is active, so this is the only player UI.
//
// Layout:
//   - top bar: close, title/channel, playback speed, "more" menu, full screen
//   - bottom bar: scrubber (played + buffered + chapters + SponsorBlock), time
//     labels, play/pause, +/-seek, previous/next, mute + volume, full screen
//
// Auto-hide, idle-timer and keyboard-shortcut plumbing live in
// TOSPlayerControlsVisibility (TOSPlayerControlsAutoHide.swift).

public struct TOSPlayerControlsOverlay: View {
    private let model: TOSPlayerControlsModel
    private let actions: TOSPlayerControlsActions
    private let moreMenuContent: () -> AnyView
    /// Inset from the top of this view to the top of the window's safe area. On macOS
    /// the windowed player draws edge-to-edge under the titlebar (traffic lights,
    /// window title), and `safeAreaInsets.top` is exactly that titlebar height — the
    /// top bar must start below it or its buttons disappear under the OS chrome.
    /// 0 in native full screen, where the bars can hug the top edge (issue #1 §5).
    private let topInset: CGFloat

    @State private var visibility = TOSPlayerControlsVisibility()

    public init(
        model: TOSPlayerControlsModel,
        actions: TOSPlayerControlsActions,
        topInset: CGFloat = 0,
        @ViewBuilder moreMenuContent: @escaping () -> some View
    ) {
        self.model = model
        self.actions = actions
        self.topInset = topInset
        self.moreMenuContent = { AnyView(moreMenuContent()) }
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .opacity(visibility.isVisible ? 1 : 0)
            .allowsHitTesting(visibility.isVisible)
            .animation(.easeInOut(duration: 0.2), value: visibility.isVisible)
        }
        // Keyboard shortcuts stay active even while the bars are faded out.
        .background(keyboardShortcuts)
        .onAppear {
            visibility.startMonitoring()
            visibility.updatePlayback(isPlaying: model.isPlaying, isPlayingAd: model.isPlayingAd)
        }
        .onDisappear {
            visibility.stopMonitoring()
        }
        .onChange(of: model.isPlaying) { _, _ in
            visibility.updatePlayback(isPlaying: model.isPlaying, isPlayingAd: model.isPlayingAd)
        }
        .onChange(of: model.isPlayingAd) { _, _ in
            visibility.updatePlayback(isPlaying: model.isPlaying, isPlayingAd: model.isPlayingAd)
        }
        .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.overlay)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                tosControlsOverlayLog.notice(
                    "[controls] close tapped (fullScreen=\(model.isFullScreen ? "yes" : "no", privacy: .public))")
                actions.onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.closeButton)
            .accessibilityLabel(Text("Close", bundle: L10n.bundle))

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !model.channelTitle.isEmpty {
                    Text(model.channelTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.titleLabel)

            Spacer(minLength: 12)

            // Full screen lives only in the bottom bar — a second button up here was
            // redundant (and the top-right corner belongs to the speed/more menus).
            speedMenu
            moreMenu
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 10)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.65), .black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
        .onHover { visibility.setPointerOverControls($0) }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                Button {
                    actions.onSpeedSelected(speed)
                    visibility.reveal()
                } label: {
                    Text(speedMenuLabel(speed))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.speedLabel)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .tint(.white)
        .fixedSize()
        .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.speedButton)
        .accessibilityLabel(Text("Playback Speed", bundle: L10n.bundle))
    }

    private var moreMenu: some View {
        Menu {
            moreMenuContent()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.35), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .tint(.white)
        .fixedSize()
        .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.moreButton)
        .accessibilityLabel(Text("More", bundle: L10n.bundle))
    }

    private func speedMenuLabel(_ speed: Double) -> String {
        speed == 1.0
            ? L10n.string("Normal (1×)")
            : String(format: "%.2g×", speed)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if model.isPlayingAd {
                adScrubberPlaceholder
            } else {
                scrubber
            }
            HStack(spacing: 14) {
                transportButton(
                    symbol: model.isPlaying ? "pause.fill" : "play.fill",
                    identifier: AccessibilityID.TOSPlayerControls.playPauseButton,
                    label: model.isPlaying
                        ? Text("Pause", bundle: L10n.bundle)
                        : Text("Play", bundle: L10n.bundle)
                ) {
                    actions.onPlayPause()
                }
                transportButton(
                    symbol: "gobackward.\(model.seekBackSeconds)",
                    identifier: AccessibilityID.TOSPlayerControls.seekBackButton,
                    label: Text("Seek Back", bundle: L10n.bundle)
                ) {
                    actions.onSeekRelative(Double(-model.seekBackSeconds))
                }
                transportButton(
                    symbol: "goforward.\(model.seekForwardSeconds)",
                    identifier: AccessibilityID.TOSPlayerControls.seekForwardButton,
                    label: Text("Seek Forward", bundle: L10n.bundle)
                ) {
                    actions.onSeekRelative(Double(model.seekForwardSeconds))
                }
                transportButton(
                    symbol: "backward.end.fill",
                    identifier: AccessibilityID.TOSPlayerControls.previousButton,
                    label: Text("Previous", bundle: L10n.bundle),
                    isEnabled: model.canGoPrevious
                ) {
                    actions.onPrevious()
                }
                transportButton(
                    symbol: "forward.end.fill",
                    identifier: AccessibilityID.TOSPlayerControls.nextButton,
                    label: Text("Next Video", bundle: L10n.bundle),
                    isEnabled: model.canGoNext
                ) {
                    actions.onNext()
                }

                Spacer(minLength: 12)

                muteButton
                volumeSlider
                transportButton(
                    symbol: model.isFullScreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    identifier: AccessibilityID.TOSPlayerControls.fullscreenButtonBottom,
                    label: model.isFullScreen
                        ? Text("Exit Full Screen", bundle: L10n.bundle)
                        : Text("Enter Full Screen", bundle: L10n.bundle)
                ) {
                    actions.onToggleFullscreen()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .onHover { visibility.setPointerOverControls($0) }
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            Text(TOSPlaybackTimeline.timeLabel(model.currentTime))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.currentTimeLabel)
            TOSPlayerScrubber(
                model: model,
                isEnabled: TOSPlaybackTimeline.canSeek(duration: model.duration, isPlayingAd: model.isPlayingAd),
                onSeek: { actions.onSeek($0) },
                onScrubbingChanged: { visibility.setScrubbing($0) }
            )
            Text(TOSPlaybackTimeline.timeLabel(model.duration))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.durationLabel)
        }
    }

    private var adScrubberPlaceholder: some View {
        HStack(spacing: 10) {
            Text("Ad", bundle: L10n.bundle)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.yellow, in: Capsule())
                .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.adBadge)
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(height: 3)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 16)
    }

    private var muteButton: some View {
        Button {
            actions.onToggleMute()
            visibility.reveal()
        } label: {
            Image(systemName: muteSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.muteButton)
        .accessibilityLabel(
            Text(model.isMuted ? "Unmute" : "Mute", bundle: L10n.bundle)
        )
    }

    private var muteSymbol: String {
        if model.isMuted || model.volume <= 0.001 { return "speaker.slash.fill" }
        if model.volume < 0.34 { return "speaker.fill" }
        if model.volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    private var volumeSlider: some View {
        Slider(
            value: Binding(
                get: { model.isMuted ? 0 : min(max(model.volume, 0), 1) },
                set: { actions.onVolumeChange($0) }
            ),
            in: 0...1
        )
        .controlSize(.mini)
        .frame(width: 86)
        .tint(.white)
        .accessibilityIdentifier(AccessibilityID.TOSPlayerControls.volumeSlider)
        .accessibilityLabel(Text("Volume", bundle: L10n.bundle))
    }

    private func transportButton(
        symbol: String,
        identifier: String,
        label: Text,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            visibility.reveal()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    // MARK: Keyboard shortcuts

    private var keyboardShortcuts: some View {
        Group {
            Button("") { actions.onPlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { actions.onSeekRelative(Double(-model.seekBackSeconds)) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { actions.onSeekRelative(Double(model.seekForwardSeconds)) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { actions.onVolumeChange(min(1, model.volume + 0.05)) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { actions.onVolumeChange(max(0, model.volume - 0.05)) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { actions.onToggleFullscreen() }
                .keyboardShortcut("f", modifiers: [])
            Button("") { actions.onToggleMute() }
                .keyboardShortcut("m", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

#endif
