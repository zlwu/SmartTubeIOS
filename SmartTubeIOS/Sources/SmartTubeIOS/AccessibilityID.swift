import Foundation

// MARK: - AccessibilityID
//
// Single source of truth for the accessibility identifiers introduced by the
// self-drawn TOS player control layer (GitHub issue #1). AGENTS.md asks for
// identifiers to come from an AccessibilityID namespace; older views still use
// inline strings (the SwiftLint baseline owns those), but new UI adds its
// identifiers here so they stay greppable and typo-proof.
//
// The SwiftLint custom rule "raw_accessibility_identifier" flags raw string
// literals passed to accessibilityIdentifier(_:); routing them through these
// constants is also what keeps the new files lint-clean.

public enum AccessibilityID {
    public enum Settings {
        public static let useCustomTOSControlsOnMacToggle = "settings.useCustomTOSControlsOnMacToggle"
    }

    public enum TOSPlayerControls {
        public static let overlay = "tosPlayer.controls.overlay"
        public static let closeButton = "tosPlayer.controls.closeButton"
        public static let titleLabel = "tosPlayer.controls.titleLabel"
        public static let speedButton = "tosPlayer.controls.speedButton"
        public static let moreButton = "tosPlayer.controls.moreButton"
        public static let fullscreenButton = "tosPlayer.controls.fullscreenButton"
        public static let playPauseButton = "tosPlayer.controls.playPauseButton"
        public static let seekBackButton = "tosPlayer.controls.seekBackButton"
        public static let seekForwardButton = "tosPlayer.controls.seekForwardButton"
        public static let previousButton = "tosPlayer.controls.previousButton"
        public static let nextButton = "tosPlayer.controls.nextButton"
        public static let fullscreenButtonBottom = "tosPlayer.controls.fullscreenButtonBottom"
        public static let currentTimeLabel = "tosPlayer.controls.currentTimeLabel"
        public static let durationLabel = "tosPlayer.controls.durationLabel"
        public static let adBadge = "tosPlayer.controls.adBadge"
        public static let muteButton = "tosPlayer.controls.muteButton"
        public static let volumeSlider = "tosPlayer.controls.volumeSlider"
        public static let scrubber = "tosPlayer.controls.scrubber"
    }
}
