// R-11: reads one simctl screenshot and prints the 99th-percentile luma of the video and of the mirror band, over columns 60 to
// 90% of the video's width (clear of the caption plate and the rail). Used by mirror-pixels.sh.
// Usage: swift mirror_pixels.swift <png> <windowWidth> <vx> <vy> <vw> <vh> <bandTop> <bandHeight>
import CoreGraphics
import Foundation
import ImageIO

let a = CommandLine.arguments
guard a.count == 9, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("usage or unreadable png"); exit(2) }
let n = a[2...].compactMap { Double($0) }
let (winW, vx, vy, vw, vh, bt, bh) = (n[0], n[1], n[2], n[3], n[4], n[5], n[6])
let w = img.width, h = img.height
let s = Double(w) / winW
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// The context owns its buffer: `&array` is only valid for the init call, so a later draw wrote through a dangling
// pointer and a read could come back 0 (BrightArtScrimTests on CI: one sample of 15 read 0, row 270 left 59 right 64).
ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
func peak(_ y0: Double, _ y1: Double) -> Int {
    let x0 = Int((vx + vw * 0.6) * s), x1 = Int((vx + vw * 0.9) * s)
    var v: [Int] = []
    for y in stride(from: max(0, Int(y0 * s)), to: min(h, Int(y1 * s)), by: 2) {
        for x in stride(from: max(0, x0), to: min(w, x1), by: 2) {
            let i = (y * w + x) * 4
            v.append((299 * Int(px[i]) + 587 * Int(px[i + 1]) + 114 * Int(px[i + 2])) / 1000)
        }
    }
    guard !v.isEmpty else { return -1 }
    v.sort(); return v[min(v.count - 1, v.count * 99 / 100)]
}
print("video \(peak(vy, vy + vh)) mirror \(peak(bt, bt + bh))")
