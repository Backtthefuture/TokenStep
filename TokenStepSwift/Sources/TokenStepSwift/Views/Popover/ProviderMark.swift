import SwiftUI

/// Provider marks bundled with the app, drawn from their SVG path data so they
/// need no resource files. Used when the provider's desktop app is not
/// installed and so has no icon to borrow.
enum ProviderMark {
    /// The Claude symbol, in a 100×100 view box.
    static let claudePath =
        "m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 2.9.2 6." +
        "3.5 9.5.6 6.9.4L38 49.1h1.6l.2-.7-.5-.4-.4-.4L29 41l-10.6-7-5.6-4.1-3-2-1.5-2-.6-4.2 2.7-3 3.7.3" +
        ".9.2 3.7 2.9 8 6.1L37 36l1.5 1.2.6-.4.1-.3-.7-1.1L33 25l-6-10.4-2.7-4.3-.7-2.6c-.3-1-.4-2-.4-3l3" +
        "-4.2L28 0l4.2.6L33.8 2l2.6 6 4.1 9.3L47 29.9l2 3.8 1 3.4.3 1h.7v-.5l.5-7.2 1-8.7 1-11.2.3-3.2 1." +
        "6-3.8 3-2L61 2.6l2 2.9-.3 1.8-1.1 7.7L59 27.1l-1.5 8.2h.9l1-1.1 4.1-5.4 6.9-8.6 3-3.5L77 13l2.3-" +
        "1.8h4.3l3.1 4.7-1.4 4.9-4.4 5.6-3.7 4.7-5.3 7.1-3.2 5.7.3.4h.7l12-2.6 6.4-1.1 7.6-1.3 3.5 1.6.4 " +
        "1.6-1.4 3.4-8.2 2-9.6 2-14.3 3.3-.2.1.2.3 6.4.6 2.8.2h6.8l12.6 1 3.3 2 1.9 2.7-.3 2-5.1 2.6-6.8-" +
        "1.6-16-3.8-5.4-1.3h-.8v.4l4.6 4.5 8.3 7.5L89 80.1l.5 2.4-1.3 2-1.4-.2-9.2-7-3.6-3-8-6.8h-.5v.7l1" +
        ".8 2.7 9.8 14.7.5 4.5-.7 1.4-2.6 1-2.7-.6-5.8-8-6-9-4.7-8.2-.5.4-2.9 30.2-1.3 1.5-3 1.2-2.5-2-1." +
        "4-3 1.4-6.2 1.6-8 1.3-6.4 1.2-7.9.7-2.6v-.2H49L43 72l-9 12.3-7.2 7.6-1.7.7-3-1.5.3-2.8L24 86l10-" +
        "12.8 6-7.9 4-4.6-.1-.5h-.3L17.2 77.4l-4.7.6-2-2 .2-3 1-1 8-5.5Z"
    static let claudeColor = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
}

/// Fills an SVG path string scaled into the view's frame. Supports the
/// commands M, L, H, V, C, S, Z in absolute and relative form, which covers
/// the bundled marks.
struct SVGPathShape: Shape {
    var pathData: String
    var viewBox: CGSize = CGSize(width: 100, height: 100)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let offset = CGPoint(
            x: rect.minX + (rect.width - viewBox.width * scale) / 2,
            y: rect.minY + (rect.height - viewBox.height * scale) / 2
        )
        return Self.parse(pathData).applying(
            CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        )
    }

    static func parse(_ data: String) -> Path {
        var path = Path()
        var tokens = SVGPathTokens(data)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"

        while let next = tokens.nextCommand(default: command) {
            command = next
            let relative = command.isLowercase
            let base = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = tokens.nextNumber(), let y = tokens.nextNumber() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }

            switch command.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                // Extra pairs after a move are implicit line-tos.
                command = relative ? "l" : "L"
                lastControl = nil
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H":
                guard let x = tokens.nextNumber() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = tokens.nextNumber() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                return path
            }
        }
        return path
    }
}

private struct SVGPathTokens {
    private let scalars: [Character]
    private var index = 0

    init(_ data: String) {
        scalars = Array(data)
    }

    private mutating func skipSeparators() {
        while index < scalars.count, scalars[index] == " " || scalars[index] == "," || scalars[index].isNewline {
            index += 1
        }
    }

    /// The next command letter, or `defaultCommand` repeated when numbers follow
    /// without one. Nil at the end of the data.
    mutating func nextCommand(default defaultCommand: Character) -> Character? {
        skipSeparators()
        guard index < scalars.count else { return nil }
        let character = scalars[index]
        if character.isLetter {
            index += 1
            return character
        }
        return defaultCommand == "Z" || defaultCommand == "z" ? nil : defaultCommand
    }

    mutating func nextNumber() -> CGFloat? {
        skipSeparators()
        let begin = index
        if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
        var seenDot = false
        var seenDigit = false
        while index < scalars.count {
            let character = scalars[index]
            if character.isASCII, character.isNumber {
                seenDigit = true
            } else if character == ".", !seenDot {
                seenDot = true
            } else {
                break
            }
            index += 1
        }
        guard seenDigit, let value = Double(String(scalars[begin..<index])) else {
            index = begin
            return nil
        }
        return CGFloat(value)
    }
}
