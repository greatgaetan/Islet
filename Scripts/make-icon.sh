#!/bin/bash
#
# Generates Resources/Islet.icns: a black squircle with a progress ring.
#
# The only test an app icon has to pass is legibility at 16 pt, which is why
# there is exactly one shape and one ring in it.
#
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/draw.swift" <<'SWIFT'
import AppKit

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setShouldAntialias(true)

// macOS icons sit inset from their canvas.
let inset = side * 0.09
let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let squircle = NSBezierPath(roundedRect: rect,
                            xRadius: rect.width * 0.235,
                            yRadius: rect.width * 0.235)
NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
squircle.fill()

// The ring: 70% of a turn, starting at the top, so the icon reads as "time
// passing" rather than "a circle".
let ringInset = rect.width * 0.28
let ringRect = rect.insetBy(dx: ringInset, dy: ringInset)
let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
let radius = ringRect.width / 2
let lineWidth = rect.width * 0.075

let track = NSBezierPath()
track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
track.lineWidth = lineWidth
NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
track.stroke()

let progress = NSBezierPath()
progress.appendArc(withCenter: center, radius: radius,
                   startAngle: 90, endAngle: 90 - 252, clockwise: true)
progress.lineWidth = lineWidth
progress.lineCapStyle = .round
NSColor(calibratedWhite: 0.97, alpha: 1).setStroke()
progress.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

echo "==> rendering 1024px master"
swift "$WORK/draw.swift" "$WORK/icon-1024.png"

echo "==> building iconset"
SET="$WORK/Islet.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
	sips -z "$size" "$size" "$WORK/icon-1024.png" \
		--out "$SET/icon_${size}x${size}.png" > /dev/null
	sips -z $((size * 2)) $((size * 2)) "$WORK/icon-1024.png" \
		--out "$SET/icon_${size}x${size}@2x.png" > /dev/null
done

mkdir -p Resources
iconutil --convert icns "$SET" --output Resources/Islet.icns
echo "built Resources/Islet.icns"
