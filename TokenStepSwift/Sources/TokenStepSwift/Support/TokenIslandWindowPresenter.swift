import AppKit
import Combine
import SwiftUI

@MainActor
final class TokenIslandWindowPresenter {
    static let shared = TokenIslandWindowPresenter()

    static let collapsedSize = NSSize(width: 88, height: 24)
    static let expandedSize = NSSize(width: 356, height: 238)

    private weak var appState: AppState?
    private var ringPanel: TokenIslandPanel?
    private var popoverPanel: TokenIslandPanel?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var hidePopoverTask: DispatchWorkItem?
    private var popoverVisible = false

    func bind(appState: AppState) {
        guard self.appState !== appState else {
            syncVisibility()
            return
        }

        self.appState = appState
        cancellables.removeAll()

        appState.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncVisibility()
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncVisibility()
            }
        }

        syncVisibility()
    }

    func showPopover() {
        hidePopoverTask?.cancel()
        hidePopoverTask = nil

        guard let appState,
              appState.shouldShowTokenIsland,
              let screen = TokenIslandDisplayDetector.notchedPrimaryScreen
        else { return }

        let panel = popoverPanel ?? makePopoverPanel(appState: appState)
        popoverPanel = panel
        positionPopoverPanel(panel, on: screen)

        guard !popoverVisible else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        popoverVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func scheduleHidePopover() {
        hidePopoverTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.hidePopover()
        }
        hidePopoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: task)
    }

    func cancelHidePopover() {
        hidePopoverTask?.cancel()
        hidePopoverTask = nil
    }

    func hidePopover() {
        hidePopoverTask?.cancel()
        hidePopoverTask = nil
        popoverVisible = false
        guard let panel = popoverPanel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func syncVisibility() {
        guard let appState else { return }

        appState.refreshTokenIslandAvailability()

        guard appState.shouldShowTokenIsland,
              let screen = TokenIslandDisplayDetector.notchedPrimaryScreen
        else {
            ringPanel?.orderOut(nil)
            popoverPanel?.orderOut(nil)
            popoverVisible = false
            return
        }

        let panel = ringPanel ?? makeRingPanel(appState: appState)
        self.ringPanel = panel
        positionRingPanel(panel, on: screen, placement: appState.settings.tokenIslandPlacement)
        panel.orderFrontRegardless()

        if popoverVisible, let popoverPanel {
            positionPopoverPanel(popoverPanel, on: screen)
        }
    }

    private func makeRingPanel(appState: AppState) -> TokenIslandPanel {
        let rootView = TokenIslandWindowView(
            onHoverChanged: { [weak self] hovering in
                if hovering {
                    self?.showPopover()
                } else {
                    self?.scheduleHidePopover()
                }
            },
            onTap: { [weak self] in
                self?.showPopover()
            }
        )
        .environmentObject(appState)

        return makePanel(
            title: "TokenStep Island",
            identifier: "token-island",
            size: Self.collapsedSize,
            rootView: rootView,
            hasShadow: false
        )
    }

    private func makePopoverPanel(appState: AppState) -> TokenIslandPanel {
        let rootView = TokenIslandPopoverWindowView { [weak self] hovering in
            if hovering {
                self?.cancelHidePopover()
            } else {
                self?.scheduleHidePopover()
            }
        }
        .environmentObject(appState)

        return makePanel(
            title: "TokenStep Island Popover",
            identifier: "token-island-popover",
            size: Self.expandedSize,
            rootView: rootView,
            hasShadow: true
        )
    }

    private func makePanel<RootView: View>(
        title: String,
        identifier: String,
        size: NSSize,
        rootView: RootView,
        hasShadow: Bool
    ) -> TokenIslandPanel {

        let controller = NSHostingController(rootView: rootView)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = TokenIslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        panel.contentViewController = controller
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = hasShadow
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = .readOnly
        return panel
    }

    private func positionRingPanel(_ panel: TokenIslandPanel, on screen: NSScreen, placement: TokenIslandDisplayPlacement) {
        let frame = TokenIslandDisplayDetector.collapsedFrame(on: screen, size: Self.collapsedSize, placement: placement)
            ?? NSRect(
                x: screen.frame.midX - Self.collapsedSize.width / 2,
                y: screen.visibleFrame.maxY - Self.collapsedSize.height - 2,
                width: Self.collapsedSize.width,
                height: Self.collapsedSize.height
            )
        panel.setFrame(frame, display: true, animate: false)
    }

    private func positionPopoverPanel(_ panel: TokenIslandPanel, on screen: NSScreen) {
        let maxHeight = max(Self.collapsedSize.height, screen.visibleFrame.height - 24)
        let size = NSSize(width: Self.expandedSize.width, height: min(Self.expandedSize.height, maxHeight))
        let ringFrame = ringPanel?.frame
            ?? TokenIslandDisplayDetector.collapsedFrame(
                on: screen,
                size: Self.collapsedSize,
                placement: appState?.settings.tokenIslandPlacement ?? .automatic
            )
        let notchBottomY = TokenIslandDisplayDetector.cameraHousingBottomY(on: screen) ?? screen.visibleFrame.maxY
        let topY = min(screen.visibleFrame.maxY - 6, notchBottomY - 6)
        let anchorX = ringFrame.map { $0.minX } ?? (screen.frame.midX - size.width / 2)
        let clampedX = min(
            max(anchorX, screen.visibleFrame.minX + 8),
            screen.visibleFrame.maxX - size.width - 8
        )
        let frame = NSRect(
            x: clampedX,
            y: topY - size.height,
            width: size.width,
            height: size.height
        )

        panel.setFrame(frame, display: true, animate: false)
    }
}

final class TokenIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
