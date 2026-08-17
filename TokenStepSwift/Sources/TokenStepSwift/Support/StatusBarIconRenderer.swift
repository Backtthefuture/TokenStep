import AppKit

enum StatusBarIconRenderer {
    static func progressRing(
        progress: Double,
        lap: Int,
        refreshing: Bool,
        size: CGFloat = 22,
        radius: CGFloat = 8.7,
        lineWidth: CGFloat = 3,
        showsCenterDot: Bool = true,
        warning: Bool = false
    ) -> NSImage {
        let size = NSSize(width: size, height: size)
        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let progress = min(max(progress, 0), 1)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.16).cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        let rgb = TokenStepLapProgress.rgb(for: lap)
        let ringColor = NSColor(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        context.setStrokeColor(ringColor.cgColor)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - (.pi * 2 * progress),
            clockwise: true
        )
        context.strokePath()

        if showsCenterDot {
            let dotColor = refreshing
                ? NSColor.secondaryLabelColor.withAlphaComponent(0.78)
                : ringColor
            dotColor.setFill()
            let dotSize = max(2.4, size.width * 0.15)
            NSBezierPath(ovalIn: NSRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize)).fill()
        }

        if warning {
            let badge = NSRect(x: size.width - 7.2, y: size.height - 7.2, width: 5.6, height: 5.6)
            NSColor(calibratedRed: 0.92, green: 0.45, blue: 0.16, alpha: 1).setFill()
            NSBezierPath(ovalIn: badge).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
