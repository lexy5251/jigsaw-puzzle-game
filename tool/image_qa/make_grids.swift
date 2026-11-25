// Cut an image into 15x15 piece-patches and write 9 labeled 5x5 contact sheets.
// Usage: swift make_grids.swift <imagePath> <outDir>
// Sheets: <outDir>/sheet-<n>.jpg, cells labeled A1..O15 (row letter, col number).
import AppKit

let args = CommandLine.arguments
let (imagePath, outDir) = (args[1], args[2])
let GRID = 15, BAND = 5          // 15x15 cells, 5x5 per sheet
let CELL = 160, LABEL = 26, PAD = 8

guard let src = NSImage(contentsOfFile: imagePath),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("cannot read \(imagePath)") }
let (w, h) = (cg.width, cg.height)

func bound(_ i: Int, _ total: Int, _ span: Int) -> Int {
    Int((Double(i) * Double(span) / Double(total)).rounded())
}

let rowLetters = (0..<GRID).map { String(UnicodeScalar(65 + $0)!) }   // A..O
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.black]

var sheetIndex = 0
for bandRow in 0..<(GRID / BAND) {
    for bandCol in 0..<(GRID / BAND) {
        let sheetW = BAND * CELL + (BAND + 1) * PAD
        let sheetH = BAND * (CELL + LABEL) + (BAND + 1) * PAD
        let sheet = NSImage(size: NSSize(width: sheetW, height: sheetH))
        sheet.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: sheetW, height: sheetH).fill()
        NSGraphicsContext.current!.imageInterpolation = .high

        for r in 0..<BAND {
            for c in 0..<BAND {
                let (gr, gc) = (bandRow * BAND + r, bandCol * BAND + c)
                let (x0, x1) = (bound(gc, GRID, w), bound(gc + 1, GRID, w))
                let (y0, y1) = (bound(gr, GRID, h), bound(gr + 1, GRID, h))
                guard let crop = cg.cropping(to: CGRect(
                    x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { continue }

                let px = PAD + c * (CELL + PAD)
                let pyTop = PAD + r * (CELL + LABEL + PAD)
                let py = sheetH - pyTop - CELL - LABEL     // flip to top-left order
                NSGraphicsContext.current!.cgContext.draw(crop,
                    in: CGRect(x: px, y: py + LABEL, width: CELL, height: CELL))
                let label = "\(rowLetters[gr])\(gc + 1)"
                NSString(string: label).draw(
                    at: NSPoint(x: CGFloat(px), y: CGFloat(py + 3)), withAttributes: attrs)
            }
        }
        sheet.unlockFocus()
        let rep = NSBitmapImageRep(cgImage: sheet.cgImage(
            forProposedRect: nil, context: nil, hints: nil)!)
        let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
        try! jpg.write(to: URL(fileURLWithPath: "\(outDir)/sheet-\(sheetIndex).jpg"))
        sheetIndex += 1
    }
}
print("wrote \(sheetIndex) sheets for \(imagePath)")
