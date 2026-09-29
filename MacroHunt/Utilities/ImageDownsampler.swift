// Utilities/ImageDownsampler.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Downsamples encoded image data with ImageIO, without ever decoding the full-resolution
/// bitmap.
///
/// Why this exists: a 12–48 MP camera photo decodes to 48–190 MB in memory, its JPEG can pass
/// the Anthropic API's 5 MB per-image limit (the analyze request then fails with a 400), and
/// every byte of it rides the upload the user is waiting on. Photos are capped once when they
/// are picked (`storageMaxPixel`) and again for the analysis payload (`analysisMaxPixel`).
///
/// Deliberately platform-neutral (no UIKit) so `scripts/core-check.sh` can exercise it on macOS.
enum ImageDownsampler {
    /// Long edge sent to Claude. Portion estimation doesn't need more, and larger images cost
    /// more image tokens and upload time. (Sonnet 5.x accepts up to 2576 px; 1568 px is the
    /// size earlier models downscaled to server-side, so this keeps estimates comparable.)
    static let analysisMaxPixel = 1568
    /// Long edge for the photos stored with a meal (and mirrored to Craft).
    static let storageMaxPixel = 2048
    /// The Anthropic API rejects any image larger than this.
    static let apiImageByteLimit = 5 * 1024 * 1024

    /// A `CGImage` no larger than `maxPixel` on its long edge, with the EXIF orientation baked
    /// in (so the result is always upright). Never upscales. `nil` if `data` isn't an image.
    static func cgImage(from data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG-encodes a `CGImage`.
    static func jpegData(from image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Downsampled, upright JPEG — or `nil` if `data` isn't a decodable image.
    static func jpeg(from data: Data, maxPixel: Int, quality: Double = 0.8) -> Data? {
        guard let image = cgImage(from: data, maxPixel: maxPixel) else { return nil }
        return jpegData(from: image, quality: quality)
    }

    /// The payload for one image in an analyze request.
    static func analysisJPEG(from data: Data) -> Data? {
        jpeg(from: data, maxPixel: analysisMaxPixel, quality: 0.8)
    }
}
