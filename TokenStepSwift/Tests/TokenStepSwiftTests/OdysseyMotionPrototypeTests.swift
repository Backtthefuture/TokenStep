import AppKit
import Darwin
import XCTest
@testable import TokenStepSwift

final class OdysseyMotionPrototypeTests: XCTestCase {
    func testPrototypeModesExposeExpectedProfiles() {
        XCTAssertEqual(OdysseyMotionPrototypeMode.off.preferredFramesPerSecond, 0)
        XCTAssertEqual(OdysseyMotionPrototypeMode.automatic.preferredFramesPerSecond, 12)
        XCTAssertEqual(OdysseyMotionPrototypeMode.cinematic.preferredFramesPerSecond, 24)
        XCTAssertEqual(OdysseyMotionPrototypeMode.off.particleIntensity, 0)
        XCTAssertGreaterThan(
            OdysseyMotionPrototypeMode.cinematic.particleIntensity,
            OdysseyMotionPrototypeMode.automatic.particleIntensity
        )
    }

    func testTrojanRendererStaysMountedWhileHiddenAndOnlyAnimatesWhenVisible() {
        XCTAssertTrue(mountEligibility())
        XCTAssertTrue(animationEligibility())
        XCTAssertTrue(mountEligibility(isSurfaceVisible: false))
        XCTAssertFalse(animationEligibility(isSurfaceVisible: false))
        XCTAssertFalse(mountEligibility(isVoyage: false))
        XCTAssertFalse(mountEligibility(chapter: .aegeanMist))
        XCTAssertFalse(mountEligibility(mode: .off))
        XCTAssertFalse(mountEligibility(isScreenshotRendering: true))
    }

    func testSceneKeepsConfiguredEmitterSetAcrossThirtyVisibilityCycles() async {
        await MainActor.run {
            let scene = OdysseyTrojanParticleScene(size: CGSize(width: 900, height: 590))
            XCTAssertEqual(
                scene.emitterNodeCount,
                OdysseyTrojanParticleScene.expectedEmitterNodeCount
            )

            scene.apply(mode: .automatic)
            let automaticFireRate = scene.birthRate(for: .fire)
            scene.apply(mode: .cinematic)
            XCTAssertGreaterThan(scene.birthRate(for: .fire), automaticFireRate)

            for _ in 0..<30 {
                scene.setRenderingActive(true)
                XCTAssertFalse(scene.isPaused)
                scene.setRenderingActive(false)
                XCTAssertTrue(scene.isPaused)
                XCTAssertEqual(
                    scene.emitterNodeCount,
                    OdysseyTrojanParticleScene.expectedEmitterNodeCount
                )
            }

            scene.updateCanvasSize(CGSize(width: 720, height: 480))
            XCTAssertEqual(scene.size, CGSize(width: 720, height: 480))
            XCTAssertEqual(
                scene.emitterNodeCount,
                OdysseyTrojanParticleScene.expectedEmitterNodeCount
            )

            scene.apply(mode: .off)
            for layer in OdysseyTrojanParticleLayer.allCases {
                XCTAssertEqual(scene.birthRate(for: layer), 0, accuracy: 0.0001)
            }
        }
    }

    @MainActor
    func testTrojanFireShaderClockAdvancesFromSceneUpdateAndSurvivesPauseCycles() {
        let scene = OdysseyTrojanParticleScene(size: CGSize(width: 900, height: 590))
        XCTAssertEqual(scene.fireTimeValue, 0, accuracy: 0.0001)

        // The first update only anchors the clock; animation starts afterwards.
        scene.update(1.0)
        XCTAssertEqual(scene.fireTimeValue, 0, accuracy: 0.0001)
        scene.update(1.1)
        XCTAssertEqual(scene.fireTimeValue, 0.1, accuracy: 0.001)

        // Long gaps while the popover is hidden are clamped so the flame phase
        // stays continuous instead of leaping to an arbitrary phase.
        scene.setRenderingActive(false)
        scene.update(61.0)
        XCTAssertEqual(scene.fireTimeValue, 0.35, accuracy: 0.001)

        // Reopening keeps accumulating from the previous phase.
        scene.setRenderingActive(true)
        scene.update(61.1)
        XCTAssertEqual(scene.fireTimeValue, 0.45, accuracy: 0.001)

        // Clock time running backwards never rewinds the flame.
        scene.update(0.5)
        XCTAssertEqual(scene.fireTimeValue, 0.45, accuracy: 0.001)
    }

    @MainActor
    func testWindowVisibilityObserverTracksOrderFrontAndOrderOutWithoutPolling() async throws {
        _ = NSApplication.shared
        var observedValues: [Bool] = []
        let coordinator = OdysseySurfaceVisibilityReader.Coordinator {
            observedValues.append($0)
        }
        let window = NSWindow(
            contentRect: CGRect(x: 10, y: 10, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0

        coordinator.attach(to: window)
        try await waitForVisibility(false, observedValues: { observedValues })
        XCTAssertEqual(observedValues.last, false)

        window.orderFront(nil)
        try await waitForVisibility(true, observedValues: { observedValues })
        XCTAssertEqual(observedValues.last, true)

        window.orderOut(nil)
        try await waitForVisibility(false, observedValues: { observedValues })
        XCTAssertEqual(observedValues.last, false)

        coordinator.detach()
    }

    @MainActor
    private func waitForVisibility(
        _ expected: Bool,
        observedValues: () -> [Bool]
    ) async throws {
        for _ in 0..<25 {
            if observedValues().last == expected { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testDiagnosticsWritesTransitionLogOnlyWhenExplicitlyEnabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-odyssey-motion-diagnostics-\(UUID().uuidString)")
        let logURL = directory.appendingPathComponent("events.log")
        let key = OdysseyMotionPrototypeDiagnostics.environmentKey
        let previousValue = getenv(key).map { String(cString: $0) }

        setenv(key, logURL.path, 1)
        defer {
            if let previousValue {
                setenv(key, previousValue, 1)
            } else {
                unsetenv(key)
            }
            try? FileManager.default.removeItem(at: directory)
        }

        OdysseyMotionPrototypeDiagnostics.record(
            "render_stop",
            fields: [
                "emitters": String(OdysseyTrojanParticleScene.expectedEmitterNodeCount),
                "paused": "true"
            ]
        )

        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("event=render_stop"))
        XCTAssertTrue(
            content.contains("emitters=\(OdysseyTrojanParticleScene.expectedEmitterNodeCount)")
        )
        XCTAssertTrue(content.contains("paused=true"))
        XCTAssertTrue(content.contains("uptime_ns="))
    }

    private func mountEligibility(
        isVoyage: Bool = true,
        chapter: TokenStepOdysseyChapter = .trojanInferno,
        mode: OdysseyMotionPrototypeMode = .automatic,
        isSurfaceVisible: Bool = true,
        isScreenshotRendering: Bool = false
    ) -> Bool {
        OdysseyMotionPrototypeEligibility.shouldMount(
            isVoyage: isVoyage,
            chapter: chapter,
            mode: mode,
            isScreenshotRendering: isScreenshotRendering
        )
    }

    private func animationEligibility(
        isVoyage: Bool = true,
        chapter: TokenStepOdysseyChapter = .trojanInferno,
        mode: OdysseyMotionPrototypeMode = .automatic,
        isSurfaceVisible: Bool = true,
        isScreenshotRendering: Bool = false
    ) -> Bool {
        OdysseyMotionPrototypeEligibility.shouldAnimate(
            isVoyage: isVoyage,
            chapter: chapter,
            mode: mode,
            isSurfaceVisible: isSurfaceVisible,
            isScreenshotRendering: isScreenshotRendering
        )
    }
}
