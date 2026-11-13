import Testing
import UIKit
@testable import Playscribe

struct CoverCacheTests {
    @Test func downsampleCapsLongestSide() throws {
        let size = CGSize(width: 528, height: 748)
        let jpeg = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        let small = try #require(CoverImageCache.downsample(jpeg, maxPixel: 240))
        let px = max(small.size.width * small.scale, small.size.height * small.scale)
        #expect(px <= 240)
        #expect(CoverImageCache.downsample(Data([1, 2, 3]), maxPixel: 240) == nil)
    }
}
