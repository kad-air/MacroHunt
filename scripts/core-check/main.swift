// scripts/core-check/main.swift
//
// Compiled together with the app's platform-neutral sources into a macOS CLI by
// scripts/core-check.sh. Every check prints ok/FAIL; the process exits non-zero on any FAIL.
// Offline checks pin the landmines this code fixed; the live section proves the real API
// accepts the exact request the app sends and returns sane numbers against USDA values.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

var failures = 0

func check(_ condition: Bool, _ message: String) {
    print("  \(condition ? "ok  " : "FAIL")  \(message)")
    if !condition { failures += 1 }
}

func section(_ title: String) {
    print("\n\(title)")
}

// MARK: - Image helpers

/// A JPEG of the given size. `noise` fills it with random pixels (worst case for JPEG size);
/// otherwise it's a yellow ellipse on white. `orientation` is written as EXIF orientation.
func makeJPEG(width: Int, height: Int, noise: Bool = false, orientation: Int = 1, quality: Double = 0.9) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    if noise, let pixels = context.data {
        arc4random_buf(pixels, context.bytesPerRow * height)
    } else {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.98, green: 0.84, blue: 0.21, alpha: 1))
        context.fillEllipse(in: CGRect(x: width / 6, y: height / 3, width: width * 2 / 3, height: height / 3))
    }
    let image = context.makeImage()!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality,
        kCGImagePropertyOrientation: orientation
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

/// Pixel size of an encoded image as it would display (orientation 1 after downsampling).
func pixelSize(_ data: Data) -> (width: Int, height: Int) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return (0, 0) }
    return (image.width, image.height)
}

func megabytes(_ bytes: Int) -> String {
    String(format: "%.1f MB", Double(bytes) / 1_048_576)
}

// MARK: - Offline: photo downsampling

section("Photo downsampling (ImageDownsampler) — what AddMealView sends to Claude")

// Worst case: a 48 MP frame of noise. Its JPEG is far past the API's 5 MB per-image limit,
// which is what a full-resolution photo used to hit (HTTP 400, meal can't be analyzed).
let huge = makeJPEG(width: 8064, height: 6048, noise: true, quality: 0.7)
print("  info  48 MP worst-case input JPEG: \(megabytes(huge.count))")
if let payload = ImageDownsampler.analysisJPEG(from: huge) {
    let size = pixelSize(payload)
    check(max(size.width, size.height) == ImageDownsampler.analysisMaxPixel,
          "analysis payload long edge is \(ImageDownsampler.analysisMaxPixel) px (got \(size.width)×\(size.height))")
    check(payload.count <= 5 * 1024 * 1024,
          "analysis payload is under the Anthropic API's 5 MB image limit (\(megabytes(payload.count)))")
} else {
    check(false, "analysis payload produced from a 48 MP JPEG")
}

// EXIF orientation 6 = shot in portrait, stored sideways. It must reach Claude upright.
let sideways = makeJPEG(width: 4032, height: 3024, orientation: 6)
if let payload = ImageDownsampler.analysisJPEG(from: sideways) {
    let size = pixelSize(payload)
    check(size.height > size.width && size.height == ImageDownsampler.analysisMaxPixel,
          "EXIF orientation is applied — a portrait photo stays portrait (got \(size.width)×\(size.height))")
} else {
    check(false, "analysis payload produced from an EXIF-rotated JPEG")
}

let small = makeJPEG(width: 800, height: 600)
if let payload = ImageDownsampler.analysisJPEG(from: small) {
    let size = pixelSize(payload)
    check(size.width == 800 && size.height == 600, "small photos are never upscaled (got \(size.width)×\(size.height))")
} else {
    check(false, "analysis payload produced from a small JPEG")
}

if let stored = ImageDownsampler.jpeg(from: huge, maxPixel: ImageDownsampler.storageMaxPixel) {
    let size = pixelSize(stored)
    check(max(size.width, size.height) == ImageDownsampler.storageMaxPixel,
          "stored meal photos are capped at \(ImageDownsampler.storageMaxPixel) px (got \(size.width)×\(size.height))")
} else {
    check(false, "storage JPEG produced from a 48 MP JPEG")
}

check(ImageDownsampler.analysisJPEG(from: Data("not an image".utf8)) == nil, "non-image data is rejected, not crashed on")

// MARK: - Offline: response decoding

section("Claude response handling (ClaudeAPI.decodeResponse)")

func response(_ json: String) -> Data { Data(json.utf8) }

// Sonnet 5.5 thinks adaptively, so a response opens with an (empty) thinking block. The old
// code happened to search by type; this pins it, since reading content[0] would break.
let withThinking = response("""
{"stop_reason":"end_turn","content":[
  {"type":"thinking","thinking":"","signature":"abc"},
  {"type":"text","text":"{\\"mealName\\":\\"Two eggs\\",\\"calories\\":155,\\"protein\\":12.6,\\"carbs\\":1.1,\\"fat\\":10.6,\\"keyNutrients\\":\\"Choline\\"}"}
]}
""")
do {
    let analysis = try ClaudeAPI.decodeResponse(NutritionAnalysis.self, data: withThinking, statusCode: 200, refusalMessage: "declined")
    check(analysis.calories == 155 && analysis.mealName == "Two eggs", "reads the JSON text block after a leading thinking block")
} catch {
    check(false, "reads the JSON text block after a leading thinking block (threw \(error))")
}

func expectError(_ label: String, data: Data, status: Int, matches: (APIError) -> Bool) {
    do {
        _ = try ClaudeAPI.decodeResponse(NutritionAnalysis.self, data: data, statusCode: status, refusalMessage: "declined")
        check(false, "\(label) (decoded instead of throwing)")
    } catch let error as APIError {
        check(matches(error), "\(label) (\(error.localizedDescription))")
    } catch {
        check(false, "\(label) (threw non-APIError \(error))")
    }
}

// Thinking counts toward max_tokens; a cut-off answer is truncated JSON and must say so.
expectError("max_tokens cut-off is reported as truncated, not a parse error",
            data: response(#"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{\"mealName\":\"Tw"}]}"#),
            status: 200) { if case .truncated = $0 { return true }; return false }
expectError("a refusal surfaces its user-facing message",
            data: response(#"{"stop_reason":"refusal","content":[]}"#),
            status: 200) { if case .refused("declined") = $0 { return true }; return false }
expectError("HTTP 401 carries the API's error type",
            data: response(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#),
            status: 401) { if case .httpError(401, let body) = $0 { return body.contains("authentication_error") }; return false }
expectError("HTTP 529 (overloaded) is a retryable server error",
            data: response(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#),
            status: 529) { if case .serverError(529) = $0 { return true }; return false }

check(ClaudeAPI(apiKey: " sk-ant-example\n").apiKey == "sk-ant-example", "a pasted key's whitespace/newline is trimmed before use")

// MARK: - Offline: settings defaults

section("Settings defaults (CredentialsManager)")

let suiteName = "macrohunt-core-check-\(UUID().uuidString)"
let freshDefaults = UserDefaults(suiteName: suiteName)!
let fresh = CredentialsManager(defaults: freshDefaults)
check(fresh.dailyCalorieGoal == 2000,
      "a fresh install's calorie goal is 2000, not 0 (got \(fresh.dailyCalorieGoal))")
check(fresh.proteinGoal > 0 && fresh.carbsGoal > 0 && fresh.fatGoal > 0,
      "a fresh install has non-zero macro goals (P \(fresh.proteinGoal) C \(fresh.carbsGoal) F \(fresh.fatGoal))")
freshDefaults.set(1800, forKey: "dailyCalorieGoal")
check(CredentialsManager(defaults: freshDefaults).dailyCalorieGoal == 1800, "a stored calorie goal still wins over the default")
freshDefaults.removePersistentDomain(forName: suiteName)

section("Meal type default (MealType.suggested)")
func at(_ hour: Int, _ minute: Int = 0) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
}
check(MealType.suggested(for: at(7, 30)) == .breakfast, "07:30 → Breakfast")
check(MealType.suggested(for: at(12, 30)) == .lunch, "12:30 → Lunch")
check(MealType.suggested(for: at(15, 30)) == .snack, "15:30 → Snack")
check(MealType.suggested(for: at(19)) == .dinner, "19:00 → Dinner")

// MARK: - Live: the real API

section("Live Anthropic API (\(ClaudeAPI.model))")

if ProcessInfo.processInfo.environment["OFFLINE"] == "1" {
    print("  skip  OFFLINE=1 — the model/effort/fallback request shape is NOT verified this run")
} else if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
    let claude = ClaudeAPI(apiKey: key)

    // USDA FoodData Central, egg, whole, cooked, hard-boiled: 50 g per large egg →
    // 77.5 kcal, 6.3 g protein, 5.3 g fat, 0.6 g carbs. Two eggs ≈ 155 kcal, 12.6 g P, 10.6 g F.
    do {
        let eggs = try await claude.analyzeMealPhotos(images: [], description: "2 large hard-boiled eggs", mealType: .breakfast)
        print("  info  \"2 large hard-boiled eggs\" → \(eggs.calories) kcal, P \(eggs.protein) g, C \(eggs.carbs) g, F \(eggs.fat) g")
        check((120...190).contains(eggs.calories), "calories within USDA 155 kcal ± ~20% (got \(eggs.calories))")
        check((10...16).contains(eggs.protein), "protein within USDA 12.6 g ± ~25% (got \(eggs.protein))")
        check((7...14).contains(eggs.fat), "fat within USDA 10.6 g ± ~30% (got \(eggs.fat))")
        check(eggs.carbs <= 4, "carbs near zero (USDA 1.1 g; got \(eggs.carbs))")
    } catch {
        check(false, "text-only analyze call succeeds (threw: \(error.localizedDescription))")
    }

    // The photo path: a downsampled image block must be accepted. USDA: medium banana
    // (118 g) ≈ 105 kcal; the synthetic photo is abstract, so the range is generous.
    do {
        guard let photo = ImageDownsampler.analysisJPEG(from: makeJPEG(width: 4032, height: 3024)) else {
            throw APIError.invalidResponse
        }
        let banana = try await claude.analyzeMealPhotos(images: [photo], description: "1 medium banana", mealType: .snack)
        print("  info  photo + \"1 medium banana\" → \(banana.calories) kcal")
        check((60...160).contains(banana.calories), "photo analyze call succeeds; calories near USDA 105 kcal (got \(banana.calories))")
    } catch {
        check(false, "photo analyze call succeeds (threw: \(error.localizedDescription))")
    }

    do {
        let reflection = try await claude.generateReflection(context: """
        GOALS
        - Daily calorie goal: 2000 kcal
        TODAY
        - Eaten so far: 900 kcal · P 60 g · C 90 g · F 30 g
        LAST 7 DAYS
        - Logged 5 of the last 7 days
        - Averages over the days they logged: 1850 kcal/day · P 95 g · C 210 g · F 65 g
        """)
        check(!reflection.headline.isEmpty && !reflection.observations.isEmpty && !reflection.suggestion.isEmpty,
              "reflection call succeeds with a headline, \(reflection.observations.count) observations and a suggestion")
    } catch {
        check(false, "reflection call succeeds (threw: \(error.localizedDescription))")
    }
} else {
    check(false, "ANTHROPIC_API_KEY is set for the live checks (or run with OFFLINE=1 to skip them)")
}

print(failures == 0 ? "\ncore-check: all checks passed" : "\ncore-check: \(failures) check(s) FAILED")
exit(failures == 0 ? 0 : 1)
