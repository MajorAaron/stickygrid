#!/bin/bash
# Generates Resources/AppIcon.icns from Resources/AppIcon-source.png.
# Masks the full-bleed 1024x1024 artwork to the standard macOS icon shape
# (824px rounded square centered on a transparent 1024 canvas), then emits
# every .iconset size and packs the .icns.
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="Resources/AppIcon-source.png"
MASKED="$(mktemp -d)/AppIcon-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"

swift - "$SOURCE" "$MASKED" <<'SWIFT'
import AppKit

let source = CommandLine.arguments[1]
let dest = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: source),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot read \(source)")
}

let canvas: CGFloat = 1024
let tile: CGFloat = 824        // Apple icon grid: content tile on 1024 canvas
let radius: CGFloat = 185.4    // Apple's corner radius at 1024pt

let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let inset = (canvas - tile) / 2
let tileRect = CGRect(x: inset, y: inset, width: tile, height: tile)
ctx.addPath(CGPath(roundedRect: tileRect, cornerWidth: radius,
                   cornerHeight: radius, transform: nil))
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))

let out = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: out)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: dest))
SWIFT

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASKED" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASKED" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
