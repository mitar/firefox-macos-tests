// Finds a line of text on the screen with the text recognition of macOS's Vision framework, for clicking a control of a
// browser's own pages and dialogs, which the browser does not expose to System Events without assistive technology.
//
// Usage: find-text SCREENSHOT TEXT...
//
// SCREENSHOT is a capture of the whole screen by screencapture. The program prints the center of the first line of text
// on the screen which equals one of TEXT, ignoring case, arrows at its ends and a glyph before it, as "X Y" in the
// screen's points, followed by the TEXT it matched, and exits with 1 when the screen shows none of them.

import AppKit
import Foundation
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: find-text SCREENSHOT TEXT...\n".data(using: .utf8)!)
    exit(2)
}
guard let image = NSImage(contentsOfFile: arguments[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read \(arguments[1])\n".data(using: .utf8)!)
    exit(2)
}
let wanted = arguments[2...].map { $0.lowercased() }

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cgImage).perform([request])

// A button's label can end with an arrow, as Edge's "Start setup \u{2192}".
let ends = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{2192}\u{203A}\u{00BB}>"))
// The capture has the screen's pixels, which are two for a point on a Retina display.
let screen = NSScreen.main?.frame.size ?? CGSize(width: cgImage.width, height: cgImage.height)
for text in wanted {
    for observation in request.results ?? [] {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let line = candidate.string.trimmingCharacters(in: ends).lowercased()
        // A radio button close to its label is read as a glyph of one or two characters before it, as "O Open tabs".
        guard line == text || (line.hasSuffix(" " + text) && line.count - text.count <= 3) else { continue }
        // Vision's coordinates are normalized, with the origin at the bottom left.
        let box = observation.boundingBox
        print(Int(box.midX * screen.width), Int((1 - box.midY) * screen.height), text)
        exit(0)
    }
}
exit(1)
