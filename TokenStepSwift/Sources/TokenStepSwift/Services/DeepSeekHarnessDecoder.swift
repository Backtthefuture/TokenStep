import Foundation
import ZstdDecompressor

struct DeepSeekHarnessDecodeResult: Equatable {
    var completeFrames: Int
    var lineCount: Int
    var partialTail: Bool
}

enum DeepSeekHarnessDecodeError: Error, LocalizedError {
    case cannotOpen(URL)
    case invalidCompressedData(String)
    case invalidUTF8Line

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url): return "Unable to open Harness session: \(url.lastPathComponent)"
        case .invalidCompressedData(let message): return "Invalid Harness Zstandard data: \(message)"
        case .invalidUTF8Line: return "Harness session contains a non-UTF-8 JSONL line"
        }
    }
}

enum DeepSeekHarnessDecoder {
    private static let inputChunkSize = 128 * 1024
    private static let newline = Data([0x0A])

    static func decode(
        fileURL: URL,
        onLine: (Data) throws -> Void
    ) throws -> DeepSeekHarnessDecodeResult {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw DeepSeekHarnessDecodeError.cannotOpen(fileURL)
        }
        defer { try? handle.close() }

        guard let stream = ZSTD_createDStream() else {
            throw DeepSeekHarnessDecodeError.invalidCompressedData("decoder allocation failed")
        }
        defer { _ = ZSTD_freeDStream(stream) }
        let initCode = ZSTD_initDStream(stream)
        guard ZSTD_isError(initCode) == 0 else {
            throw DeepSeekHarnessDecodeError.invalidCompressedData(errorName(initCode))
        }

        let outputSize = max(Int(ZSTD_DStreamOutSize()), 32 * 1024)
        var lineBuffer = Data()
        var completeFrames = 0
        var lineCount = 0
        var partialTail = false
        var sawInput = false
        var waitingForFrame = false

        func emitLines(finalFrameComplete: Bool) throws {
            while let range = lineBuffer.range(of: newline) {
                let line = lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound)
                lineBuffer.removeSubrange(lineBuffer.startIndex...range.upperBound - 1)
                guard !line.isEmpty else { continue }
                guard String(data: line, encoding: .utf8) != nil else {
                    throw DeepSeekHarnessDecodeError.invalidUTF8Line
                }
                try onLine(line)
                lineCount += 1
            }
            if finalFrameComplete, !lineBuffer.isEmpty {
                guard String(data: lineBuffer, encoding: .utf8) != nil else {
                    throw DeepSeekHarnessDecodeError.invalidUTF8Line
                }
                try onLine(lineBuffer)
                lineBuffer.removeAll(keepingCapacity: true)
                lineCount += 1
            }
        }

        while true {
            let compressed = try handle.read(upToCount: inputChunkSize) ?? Data()
            if compressed.isEmpty { break }
            sawInput = true
            let input = compressed
            try input.withUnsafeBytes { inputBytes in
                guard let source = inputBytes.baseAddress else { return }
                var inputBuffer = ZSTD_inBuffer(src: source, size: input.count, pos: 0)
                while inputBuffer.pos < inputBuffer.size {
                    var output = Data(count: outputSize)
                    let outputCapacity = output.count
                    var outputCount = 0
                    var code: size_t = 0
                    output.withUnsafeMutableBytes { outputBytes in
                        guard let destination = outputBytes.baseAddress else { return }
                        var outputBuffer = ZSTD_outBuffer(dst: destination, size: outputCapacity, pos: 0)
                        code = ZSTD_decompressStream(stream, &outputBuffer, &inputBuffer)
                        outputCount = outputBuffer.pos
                    }
                    if ZSTD_isError(code) != 0 {
                        throw DeepSeekHarnessDecodeError.invalidCompressedData(errorName(code))
                    }
                    if outputCount > 0 {
                        lineBuffer.append(output.prefix(outputCount))
                    }
                    if code == 0 {
                        completeFrames += 1
                        waitingForFrame = false
                        try emitLines(finalFrameComplete: true)
                        let resetCode = ZSTD_initDStream(stream)
                        guard ZSTD_isError(resetCode) == 0 else {
                            throw DeepSeekHarnessDecodeError.invalidCompressedData(errorName(resetCode))
                        }
                    } else {
                        waitingForFrame = true
                        try emitLines(finalFrameComplete: false)
                    }
                    if inputBuffer.pos == inputBuffer.size { break }
                }
            }
        }

        if waitingForFrame {
            var emptyInput = ZSTD_inBuffer(src: nil, size: 0, pos: 0)
            for _ in 0..<4 {
                var output = Data(count: outputSize)
                let outputCapacity = output.count
                var outputCount = 0
                var code: size_t = 0
                output.withUnsafeMutableBytes { outputBytes in
                    guard let destination = outputBytes.baseAddress else { return }
                    var outputBuffer = ZSTD_outBuffer(dst: destination, size: outputCapacity, pos: 0)
                    code = ZSTD_decompressStream(stream, &outputBuffer, &emptyInput)
                    outputCount = outputBuffer.pos
                }
                if ZSTD_isError(code) != 0 {
                    throw DeepSeekHarnessDecodeError.invalidCompressedData(errorName(code))
                }
                if outputCount > 0 {
                    lineBuffer.append(output.prefix(outputCount))
                    try emitLines(finalFrameComplete: false)
                }
                if code == 0 {
                    completeFrames += 1
                    waitingForFrame = false
                    try emitLines(finalFrameComplete: true)
                    break
                }
                if outputCount == 0 { break }
            }
            partialTail = waitingForFrame && sawInput
        }
        try emitLines(finalFrameComplete: !waitingForFrame)
        return DeepSeekHarnessDecodeResult(
            completeFrames: completeFrames,
            lineCount: lineCount,
            partialTail: partialTail
        )
    }

    private static func errorName(_ code: size_t) -> String {
        String(cString: ZSTD_getErrorName(code))
    }
}
