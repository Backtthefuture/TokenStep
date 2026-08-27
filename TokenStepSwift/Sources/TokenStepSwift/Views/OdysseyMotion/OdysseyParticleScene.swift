import AppKit
import SpriteKit

enum OdysseyTrojanParticleLayer: String, CaseIterable {
    case smoke
    case fire
    case sparks
    case embers
}

final class OdysseyTrojanParticleScene: SKScene {
    static let expectedEmitterNodeCount = 8

    private let artworkNode = SKSpriteNode()
    private var artworkSourceSize: CGSize?
    private var fireTimeUniform: SKUniform?
    private var fireTime: Float = 0
    private var lastFireTimeUpdate: TimeInterval?
    private var fireUpdateCounter = 0
    private let smokeEmitter = SKEmitterNode()
    private let maneFireEmitter = SKEmitterNode()
    private let backFireEmitter = SKEmitterNode()
    private let legFireEmitter = SKEmitterNode()
    private let rightFireEmitter = SKEmitterNode()
    private let groundFireEmitter = SKEmitterNode()
    private let sparkEmitter = SKEmitterNode()
    private let emberEmitter = SKEmitterNode()
    private var didPrewarm = false

    private var fireEmitters: [SKEmitterNode] {
        [
            maneFireEmitter,
            backFireEmitter,
            legFireEmitter,
            rightFireEmitter,
            groundFireEmitter
        ]
    }

    private var allEmitters: [SKEmitterNode] {
        [smokeEmitter] + fireEmitters + [sparkEmitter, emberEmitter]
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
        configureAnimatedArtwork()
        configureEmitters()
        layoutEmitters()
        apply(mode: .automatic)
        isPaused = true
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    var emitterNodeCount: Int {
        emitterCount(in: self)
    }

    var fireTimeValue: Float {
        fireTime
    }

    func birthRate(for layer: OdysseyTrojanParticleLayer) -> CGFloat {
        switch layer {
        case .smoke: return smokeEmitter.particleBirthRate
        case .fire: return fireEmitters.reduce(0) { $0 + $1.particleBirthRate }
        case .sparks: return sparkEmitter.particleBirthRate
        case .embers: return emberEmitter.particleBirthRate
        }
    }

    func updateCanvasSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0, size != newSize else { return }
        size = newSize
        layoutEmitters()
    }

    /// SpriteKit's built-in u_time uniform stops advancing once a scene has
    /// been paused and resumed under an always-mounted SpriteView, which froze
    /// the Trojan Inferno flame shader in 0.2.11. Drive the shader clock from
    /// the scene update loop instead so the flame keeps burning on every visit.
    override func update(_ currentTime: TimeInterval) {
        if let lastFireTimeUpdate {
            // 0.25s is above the 12fps frame interval, so the flame runs at
            // real-time speed, while still clamping the huge first delta after
            // the popover reopens.
            let delta = min(max(currentTime - lastFireTimeUpdate, 0), 0.25)
            fireTime += Float(delta)
        }
        lastFireTimeUpdate = currentTime
        fireTimeUniform?.floatValue = fireTime
        fireUpdateCounter += 1
        if fireUpdateCounter % 12 == 0 {
            OdysseyMotionPrototypeDiagnostics.record(
                "fire_clock",
                fields: [
                    "t": String(format: "%.3f", fireTime),
                    "now": String(format: "%.3f", currentTime),
                    "uniform": fireTimeUniform.map { String(format: "%.3f", $0.floatValue) } ?? "nil"
                ]
            )
        }
    }

    func apply(mode: OdysseyMotionPrototypeMode) {
        let intensity = mode.particleIntensity
        maneFireEmitter.particleBirthRate = 7.2 * intensity
        backFireEmitter.particleBirthRate = 5.8 * intensity
        legFireEmitter.particleBirthRate = 6.8 * intensity
        rightFireEmitter.particleBirthRate = 5.8 * intensity
        groundFireEmitter.particleBirthRate = 8.4 * intensity
        smokeEmitter.particleBirthRate = 0.68 * intensity
        sparkEmitter.particleBirthRate = 6.4 * intensity
        emberEmitter.particleBirthRate = 0.82 * intensity
    }

    func setRenderingActive(_ active: Bool) {
        guard active else {
            isPaused = true
            return
        }

        if !didPrewarm {
            isPaused = false
            allEmitters.forEach {
                $0.advanceSimulationTime(2.4)
            }
            didPrewarm = true
        }
        isPaused = false
    }

    private func configureEmitters() {
        configureSmoke()
        configureFire(
            maneFireEmitter,
            scale: 0.30,
            lifetime: 0.92,
            speed: 34,
            drift: -4
        )
        configureFire(
            backFireEmitter,
            scale: 0.27,
            lifetime: 0.86,
            speed: 30,
            drift: -6
        )
        configureFire(
            legFireEmitter,
            scale: 0.29,
            lifetime: 0.88,
            speed: 31,
            drift: 2
        )
        configureFire(
            rightFireEmitter,
            scale: 0.27,
            lifetime: 0.84,
            speed: 29,
            drift: -5
        )
        configureFire(
            groundFireEmitter,
            scale: 0.24,
            lifetime: 0.78,
            speed: 25,
            drift: -2
        )
        configureSparks()
        configureEmbers()

        smokeEmitter.name = OdysseyTrojanParticleLayer.smoke.rawValue
        maneFireEmitter.name = "fire-mane"
        backFireEmitter.name = "fire-back"
        legFireEmitter.name = "fire-legs"
        rightFireEmitter.name = "fire-right"
        groundFireEmitter.name = "fire-ground"
        sparkEmitter.name = OdysseyTrojanParticleLayer.sparks.rawValue
        emberEmitter.name = OdysseyTrojanParticleLayer.embers.rawValue

        smokeEmitter.zPosition = 0
        fireEmitters.forEach { $0.zPosition = 10 }
        sparkEmitter.zPosition = 20
        emberEmitter.zPosition = 30

        allEmitters.forEach {
            $0.targetNode = self
            addChild($0)
        }
    }

    private func configureAnimatedArtwork() {
        guard let artwork = OdysseyTrojanArtworkLoader.load() else { return }

        artworkSourceSize = artwork.size
        artworkNode.texture = SKTexture(image: artwork)
        artworkNode.texture?.filteringMode = .linear
        let shader = OdysseyTrojanFireShader.make()
        let uniform = SKUniform(name: OdysseyTrojanFireShader.timeUniformName, float: 0)
        shader.uniforms = [uniform]
        fireTimeUniform = uniform
        artworkNode.shader = shader
        artworkNode.zPosition = -100
        artworkNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(artworkNode)
    }

    private func configureSmoke() {
        smokeEmitter.particleTexture = OdysseyParticleTextures.smoke
        smokeEmitter.particleLifetime = 5.6
        smokeEmitter.particleLifetimeRange = 1.4
        smokeEmitter.emissionAngle = .pi * 0.58
        smokeEmitter.emissionAngleRange = .pi * 0.16
        smokeEmitter.particleSpeed = 18
        smokeEmitter.particleSpeedRange = 7
        smokeEmitter.xAcceleration = 2.5
        smokeEmitter.yAcceleration = 1.5
        smokeEmitter.particleAlpha = 0.20
        smokeEmitter.particleAlphaRange = 0.06
        smokeEmitter.particleAlphaSpeed = -0.025
        smokeEmitter.particleScale = 1.05
        smokeEmitter.particleScaleRange = 0.30
        smokeEmitter.particleScaleSpeed = 0.15
        smokeEmitter.particleRotationRange = .pi
        smokeEmitter.particleRotationSpeed = 0.04
        smokeEmitter.particleBlendMode = .alpha
        smokeEmitter.particleColorBlendFactor = 1
        smokeEmitter.particleColorSequence = colorSequence(
            [
                NSColor(calibratedRed: 0.20, green: 0.12, blue: 0.09, alpha: 0.72),
                NSColor(calibratedRed: 0.10, green: 0.09, blue: 0.09, alpha: 0.44),
                NSColor(calibratedWhite: 0.06, alpha: 0)
            ]
        )
    }

    private func configureFire(
        _ emitter: SKEmitterNode,
        scale: CGFloat,
        lifetime: CGFloat,
        speed: CGFloat,
        drift: CGFloat
    ) {
        emitter.particleTexture = OdysseyParticleTextures.flame
        emitter.particleLifetime = lifetime
        emitter.particleLifetimeRange = 0.22
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 0.14
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = 9
        emitter.xAcceleration = drift
        emitter.yAcceleration = 4
        emitter.particleAlpha = 0.34
        emitter.particleAlphaRange = 0.08
        emitter.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0, 0.38, 0.24, 0],
            times: [0, 0.16, 0.68, 1]
        )
        emitter.particleScale = scale
        emitter.particleScaleRange = 0.08
        emitter.particleScaleSequence = SKKeyframeSequence(
            keyframeValues: [0.72, 1, 0.66],
            times: [0, 0.40, 1]
        )
        emitter.particleRotationRange = 0.18
        emitter.particleRotationSpeed = 0.07
        emitter.particleBlendMode = .add
        emitter.particleColorBlendFactor = 1
        emitter.particleColorSequence = colorSequence(
            [
                NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.22, alpha: 0.88),
                NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.06, alpha: 0.70),
                NSColor(calibratedRed: 0.34, green: 0.08, blue: 0.03, alpha: 0)
            ]
        )
    }

    private func configureSparks() {
        sparkEmitter.particleTexture = OdysseyParticleTextures.spark
        sparkEmitter.particleLifetime = 2.5
        sparkEmitter.particleLifetimeRange = 0.7
        sparkEmitter.emissionAngle = .pi * 0.54
        sparkEmitter.emissionAngleRange = .pi * 0.22
        sparkEmitter.particleSpeed = 72
        sparkEmitter.particleSpeedRange = 26
        sparkEmitter.xAcceleration = -5
        sparkEmitter.yAcceleration = 4
        sparkEmitter.particleAlpha = 0.80
        sparkEmitter.particleAlphaRange = 0.18
        sparkEmitter.particleAlphaSpeed = -0.27
        sparkEmitter.particleScale = 0.20
        sparkEmitter.particleScaleRange = 0.10
        sparkEmitter.particleScaleSpeed = -0.025
        sparkEmitter.particleBlendMode = .add
        sparkEmitter.particleColorBlendFactor = 1
        sparkEmitter.particleColorSequence = colorSequence(
            [
                NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.34, alpha: 0.94),
                NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.08, alpha: 0.72),
                NSColor(calibratedRed: 0.55, green: 0.11, blue: 0.03, alpha: 0)
            ]
        )
    }

    private func configureEmbers() {
        emberEmitter.particleTexture = OdysseyParticleTextures.ember
        emberEmitter.particleLifetime = 4.2
        emberEmitter.particleLifetimeRange = 1.2
        emberEmitter.emissionAngle = .pi * 0.57
        emberEmitter.emissionAngleRange = .pi * 0.26
        emberEmitter.particleSpeed = 34
        emberEmitter.particleSpeedRange = 13
        emberEmitter.xAcceleration = -2
        emberEmitter.yAcceleration = 1
        emberEmitter.particleAlpha = 0.48
        emberEmitter.particleAlphaRange = 0.15
        emberEmitter.particleAlphaSpeed = -0.10
        emberEmitter.particleScale = 0.15
        emberEmitter.particleScaleRange = 0.07
        emberEmitter.particleScaleSpeed = -0.012
        emberEmitter.particleBlendMode = .add
        emberEmitter.particleColorBlendFactor = 1
        emberEmitter.particleColorSequence = colorSequence(
            [
                NSColor(calibratedRed: 0.96, green: 0.48, blue: 0.12, alpha: 0.76),
                NSColor(calibratedRed: 0.68, green: 0.20, blue: 0.05, alpha: 0.48),
                NSColor(calibratedRed: 0.30, green: 0.07, blue: 0.02, alpha: 0)
            ]
        )
    }

    private func layoutEmitters() {
        let width = max(size.width, 1)
        let height = max(size.height, 1)

        if let artworkSourceSize,
           artworkSourceSize.width > 0,
           artworkSourceSize.height > 0 {
            let scale = max(
                width / artworkSourceSize.width,
                height / artworkSourceSize.height
            )
            artworkNode.size = CGSize(
                width: artworkSourceSize.width * scale,
                height: artworkSourceSize.height * scale
            )
            artworkNode.position = CGPoint(x: width / 2, y: height / 2)
        }

        // Five small flicker fields track the real flame wall in the artwork. They
        // brighten existing fire instead of drawing a second, unrelated fire layer.
        maneFireEmitter.position = CGPoint(x: width * 0.62, y: height * 0.71)
        maneFireEmitter.particlePositionRange = CGVector(dx: width * 0.11, dy: height * 0.23)

        backFireEmitter.position = CGPoint(x: width * 0.42, y: height * 0.43)
        backFireEmitter.particlePositionRange = CGVector(dx: width * 0.07, dy: height * 0.20)

        legFireEmitter.position = CGPoint(x: width * 0.62, y: height * 0.17)
        legFireEmitter.particlePositionRange = CGVector(dx: width * 0.32, dy: height * 0.05)

        rightFireEmitter.position = CGPoint(x: width * 0.89, y: height * 0.34)
        rightFireEmitter.particlePositionRange = CGVector(dx: width * 0.045, dy: height * 0.44)

        groundFireEmitter.position = CGPoint(x: width * 0.66, y: height * 0.035)
        groundFireEmitter.particlePositionRange = CGVector(dx: width * 0.58, dy: height * 0.025)

        smokeEmitter.position = CGPoint(x: width * 0.62, y: height * 0.11)
        smokeEmitter.particlePositionRange = CGVector(dx: width * 0.48, dy: height * 0.09)

        sparkEmitter.position = CGPoint(x: width * 0.62, y: height * 0.18)
        sparkEmitter.particlePositionRange = CGVector(dx: width * 0.48, dy: height * 0.30)

        emberEmitter.position = CGPoint(x: width * 0.64, y: height * 0.25)
        emberEmitter.particlePositionRange = CGVector(dx: width * 0.52, dy: height * 0.38)
    }

    private func emitterCount(in node: SKNode) -> Int {
        node.children.reduce(node is SKEmitterNode ? 1 : 0) {
            $0 + emitterCount(in: $1)
        }
    }

    private func colorSequence(_ colors: [NSColor]) -> SKKeyframeSequence {
        SKKeyframeSequence(
            keyframeValues: colors,
            times: [0, 0.52, 1]
        )
    }
}

private enum OdysseyTrojanArtworkLoader {
    static func load() -> NSImage? {
        if let path = ProcessInfo.processInfo.environment["TOKENSTEP_ODYSSEY_TROJAN_ART_PATH"],
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        if let url = Bundle.main.url(
            forResource: "OdysseyTrojanPopover",
            withExtension: "png"
        ) {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

private enum OdysseyTrojanFireShader {
    static let timeUniformName = "u_fireTime"

    static func make() -> SKShader {
        SKShader(source: """
        void main() {
            vec2 uv = v_tex_coord;
            vec4 source = texture2D(u_texture, uv);

            float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
            float warmDifference = max(source.r - source.b, 0.0);
            float redLead = max(source.r - source.g, 0.0);
            float heat = smoothstep(0.08, 0.34, warmDifference)
                * smoothstep(0.02, 0.18, redLead)
                * smoothstep(0.12, 0.62, luminance);

            float upwardFlow = sin(
                (uv.y + u_fireTime * 0.085) * 108.0
                + sin(uv.x * 34.0) * 2.4
            );
            float sideRipple = sin(
                uv.x * 76.0
                - u_fireTime * 5.8
                + upwardFlow * 1.7
            );
            vec2 displacement = vec2(
                sideRipple * 0.0032,
                upwardFlow * 0.0015
            ) * heat;
            vec2 animatedUV = clamp(
                uv + displacement,
                vec2(0.001),
                vec2(0.999)
            );

            vec4 animated = texture2D(u_texture, animatedUV);
            float flicker = 0.5 + 0.5 * sin(
                u_fireTime * 7.4
                + uv.y * 61.0
                + sin(uv.x * 47.0) * 2.0
            );
            animated.rgb *= 1.0 + heat * (0.055 + flicker * 0.16);
            gl_FragColor = animated;
        }
        """)
    }
}

private enum OdysseyParticleTextures {
    static let flame = flameTexture(width: 36, height: 84)

    static let smoke = radialTexture(
        diameter: 96,
        colors: [
            NSColor(calibratedWhite: 1, alpha: 0.58),
            NSColor(calibratedWhite: 1, alpha: 0.24),
            NSColor(calibratedWhite: 1, alpha: 0)
        ],
        locations: [0, 0.46, 1]
    )

    static let spark = radialTexture(
        diameter: 20,
        colors: [
            NSColor(calibratedWhite: 1, alpha: 1),
            NSColor(calibratedWhite: 1, alpha: 0.52),
            NSColor(calibratedWhite: 1, alpha: 0)
        ],
        locations: [0, 0.28, 1]
    )

    static let ember = radialTexture(
        diameter: 28,
        colors: [
            NSColor(calibratedWhite: 1, alpha: 0.88),
            NSColor(calibratedWhite: 1, alpha: 0.35),
            NSColor(calibratedWhite: 1, alpha: 0)
        ],
        locations: [0, 0.32, 1]
    )

    private static func flameTexture(width: Int, height: Int) -> SKTexture {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return SKTexture()
        }

        let w = CGFloat(width)
        let h = CGFloat(height)
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor(calibratedWhite: 1, alpha: 0.72).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0.32).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0).cgColor
            ] as CFArray,
            locations: [0, 0.46, 1]
        ) else {
            return SKTexture()
        }

        context.saveGState()
        context.translateBy(x: w * 0.50, y: h * 0.40)
        context.scaleBy(x: 1, y: h / w * 0.82)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: 0,
            endCenter: CGPoint(x: 0, y: w * 0.10),
            endRadius: w * 0.46,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()

        guard let image = context.makeImage() else { return SKTexture() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func radialTexture(
        diameter: Int,
        colors: [NSColor],
        locations: [CGFloat],
        verticalOffset: CGFloat = 0
    ) -> SKTexture {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: diameter,
            height: diameter,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        )
        else {
            return SKTexture()
        }

        let radius = CGFloat(diameter) / 2
        let center = CGPoint(x: radius, y: radius + radius * verticalOffset)
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )

        guard let image = context.makeImage() else { return SKTexture() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        return texture
    }
}
