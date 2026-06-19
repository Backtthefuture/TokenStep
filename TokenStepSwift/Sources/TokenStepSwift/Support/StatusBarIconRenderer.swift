import AppKit

enum StatusBarIconRenderer {
    static func progressRing(progress: Double, lap: Int, refreshing: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let progress = min(max(progress, 0), 1)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 8.7
        let lineWidth: CGFloat = 3

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

        let dotColor = refreshing
            ? NSColor.secondaryLabelColor.withAlphaComponent(0.78)
            : ringColor
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.65, y: center.y - 1.65, width: 3.3, height: 3.3)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
