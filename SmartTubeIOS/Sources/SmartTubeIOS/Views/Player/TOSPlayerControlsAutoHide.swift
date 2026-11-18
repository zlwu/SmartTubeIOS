#if os(macOS)
import AppKit
import Observation
import os

/// Logger for the self-drawn TOS player control layer (GitHub issue #1).
private let tosControlsVisibilityLog = Logger(
    subsystem: "com.void.smarttube.app", category: "TOSPlayerControls")

// MARK: - TOSPlayerControlsVisibility
//
// Visibility/auto-hide state machine for `TOSPlayerControlsOverlay` on macOS.
//
// Behaviour (issue #1, §5):
//  * Controls are shown on first appearance and whenever the pointer moves or
//    clicks anywhere over the player window.
//  * While playing (and not during an ad) they fade out after `hideDelay`
//    (~3 s) without mouse movement.
//  * They never hide while paused, during an ad, while the pointer is over the
//    bars, while a menu is open, or while the scrubber is being dragged.
//
// The overlay view owns one instance and feeds playback state in via
// `updatePlayback(isPlaying:isPlayingAd:)`. A parent that wants to reveal the
// controls itself (e.g. on a surface tap or video change) can hold the instance
// and call `reveal()`.
//
// SwiftUI's `Menu` exposes no "is presented" binding, so the overlay marks
// `isMenuOpen` itself when a menu label is tapped and the local mouse monitor
// clears it on the first event delivered to the player window after the menu
// tracking loop ends. Call `setMenuOpen(_:)` directly if you ever present a
// custom menu instead.

@MainActor
@Observable
public final class TOSPlayerControlsVisibility {

    /// Whether the overlay should be visible. The overlay renders this with a
    /// 0.2 s ease-in-out opacity animation.
    public private(set) var isVisible: Bool = true

    /// Pointer is over the top or bottom control bar (set via `.onHover`).
    public private(set) var isPointerOverControls: Bool = false

    /// A speed/more menu is currently presented.
    public private(set) var isMenuOpen: Bool = false

    /// The user is dragging the scrubber.
    public private(set) var isScrubbing: Bool = false

    /// Idle time before the controls fade out while playing. Default 3 s.
    public var hideDelay: Duration

    private var isPlaying: Bool = false
    private var isPlayingAd: Bool = false

    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private weak var monitoredWindow: NSWindow?
    @ObservationIgnored private var previousAcceptsMouseMovedEvents: Bool?

    public init(hideDelay: Duration = .seconds(3)) {
        self.hideDelay = hideDelay
    }

    // MARK: - Playback state

    /// Feed the overlay's current model state in. Paused playback and ads pin
    /// the controls open; resuming playback restarts the idle timer.
    public func updatePlayback(isPlaying: Bool, isPlayingAd: Bool) {
        self.isPlaying = isPlaying
        self.isPlayingAd = isPlayingAd
        if !isPlaying || isPlayingAd {
            cancelHide()
            setVisible(true)
        } else {
            rescheduleHide()
        }
    }

    // MARK: - Show / hide

    /// Show the controls and restart the idle timer (mouse move, click, or any
    /// control interaction).
    public func reveal() {
        setVisible(true)
        rescheduleHide()
    }

    /// Hide immediately, cancelling any pending timer.
    public func hideNow() {
        cancelHide()
        setVisible(false)
    }

    /// Pointer entered/left the top or bottom bar.
    public func setPointerOverControls(_ isOver: Bool) {
        guard isOver != isPointerOverControls else { return }
        isPointerOverControls = isOver
        if isOver {
            cancelHide()
            setVisible(true)
        } else {
            rescheduleHide()
        }
    }

    /// A menu was opened (`true`) or dismissed (`false`).
    public func setMenuOpen(_ isOpen: Bool) {
        guard isOpen != isMenuOpen else { return }
        isMenuOpen = isOpen
        if isOpen {
            cancelHide()
            setVisible(true)
        } else {
            rescheduleHide()
        }
    }

    /// The scrubber drag started (`true`) or ended (`false`).
    public func setScrubbing(_ scrubbing: Bool) {
        guard scrubbing != isScrubbing else { return }
        isScrubbing = scrubbing
        if scrubbing {
            cancelHide()
            setVisible(true)
        } else {
            rescheduleHide()
        }
    }

    // MARK: - Mouse monitoring

    /// Installs the local `NSEvent` monitor that reveals the controls on mouse
    /// movement/clicks. Call from `.onAppear`; pair with `stopMonitoring()` in
    /// `.onDisappear`.
    public func startMonitoring() {
        guard mouseMonitor == nil else { return }
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        monitoredWindow = window
        if let window {
            previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
            // Windows do not deliver .mouseMoved by default; the player window
            // must opt in for the monitor to see idle-hover movement.
            window.acceptsMouseMovedEvents = true
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.handleMonitoredEvent(event)
            return event
        }
        tosControlsVisibilityLog.debug(
            "[controls] mouse monitor installed (window=\(window == nil ? "missing" : "found"))")
    }

    /// Removes the mouse monitor and restores the window's prior
    /// `acceptsMouseMovedEvents` value.
    public func stopMonitoring() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let window = monitoredWindow, let previousValue = previousAcceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = previousValue
        }
        previousAcceptsMouseMovedEvents = nil
        monitoredWindow = nil
        cancelHide()
        tosControlsVisibilityLog.debug("[controls] mouse monitor removed")
    }

    private func handleMonitoredEvent(_ event: NSEvent) {
        // Only react to events in the player's own window; menu popups and
        // other app windows must not flash the overlay.
        if monitoredWindow == nil, let window = event.window {
            monitoredWindow = window
            previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
            window.acceptsMouseMovedEvents = true
        }
        guard let window = monitoredWindow, event.window === window else { return }
        // Any event reaching the player window means the menu tracking loop (if
        // one was running) has ended.
        if isMenuOpen { setMenuOpen(false) }
        reveal()
    }

    // MARK: - Hide timer

    private func rescheduleHide() {
        hideTask?.cancel()
        hideTask = nil
        guard isPlaying, !isPlayingAd, !isPointerOverControls, !isMenuOpen, !isScrubbing else {
            return
        }
        let delay = hideDelay
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            guard self.isPlaying, !self.isPlayingAd, !self.isPointerOverControls,
                !self.isMenuOpen, !self.isScrubbing
            else { return }
            self.setVisible(false)
            tosControlsVisibilityLog.debug("[controls] auto-hid after idle timeout")
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
    }
}

#endif
