import AppKit

// Rasterises an SVG to a square PNG.
//
// The icon is authored as vector source (docs/brand/kvitta-app-icon.svg) so it stays editable and
// diffable; this turns it into the one PNG the asset catalog wants. AppKit reads SVG directly, so
// there is no dependency to install — deliberate, since a build asset that needs Homebrew to
// regenerate is an asset nobody regenerates.
//
// Compile it rather than running it as a script — `swift tools/rasterize-icon.swift` uses the
// interpreter, which takes minutes to load AppKit and looks like a hang:
//
//   swiftc -O tools/rasterize-icon.swift -o /tmp/rasterize-icon
//   /tmp/rasterize-icon docs/brand/kvitta-app-icon.svg \
//       ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png 1024

let arguments = CommandLine.arguments
guard arguments.count == 4, let side = Int(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: rasterize-icon <in.svg> <out.png> <side>\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: input) else {
    FileHandle.standardError.write(Data("could not read \(input.path)\n".utf8))
    exit(1)
}
image.size = NSSize(width: side, height: side)

// RGBA, even though an app icon must ship opaque. AppKit has no alpha-less 32-bit layout, and
// asking for three samples at 24bpp gives a rep CoreGraphics cannot back a context with: it draws
// nowhere and silently writes a solid black PNG. Every pixel here is opaque because the artwork
// covers the frame edge to edge, and actool flattens the channel when it compiles the catalog.
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("could not allocate a \(side)x\(side) bitmap\n".utf8))
    exit(1)
}

// Not `NSGraphicsContext.current = ...` on its own: that accepts nil, and a nil context is how
// the black-PNG bug got all the way into a build.
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("could not make a drawing context for the bitmap\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.restoreGraphicsState()

// The whole icon coming out one flat colour means the SVG did not render. Nothing downstream
// notices — actool happily compiles a black square and it ships — so check it here.
let corner = bitmap.colorAt(x: 4, y: 4)
let middle = bitmap.colorAt(x: side / 2, y: side / 2)
guard let corner, let middle, corner != middle else {
    FileHandle.standardError.write(Data("rendered a flat image — the SVG did not draw\n".utf8))
    exit(1)
}

guard let png = bitmap.representation(using: .png, properties: [.interlaced: false]) else {
    FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
    exit(1)
}
try png.write(to: output)
print("wrote \(output.lastPathComponent) at \(side)x\(side)")
