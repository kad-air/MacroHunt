# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build for simulator
xcodebuild -scheme MacroHunt -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for device (requires signing)
xcodebuild -scheme MacroHunt -destination 'generic/platform=iOS' build
```

No test target exists. Open `MacroHunt.xcodeproj` in Xcode for development.

## Architecture

iOS 17+ app using SwiftUI, SwiftData, and Swift Charts. Follows a services-based architecture with transactional sync to Craft Docs.

### Data Flow

1. **Meal logging**: Photos → GeminiAPI (AI analysis) → Meal object → MealRepository
2. **Persistence**: MealRepository saves to Craft first, then SwiftData locally (transactional - if Craft fails, local save is skipped)
3. **Credentials**: Stored in Keychain via KeychainHelper, managed by CredentialsManager (@EnvironmentObject)

### Key Services

- **MealRepository** (`Services/MealRepository.swift`): Data layer wrapping SwiftData ModelContext. All operations are `@MainActor`. Provides `saveMealWithSync` and `deleteMealWithSync` for transactional Craft+local persistence.
- **CraftAPI** (`Services/CraftAPI.swift`): Craft Docs REST API client. Creates collection items with meal data, uploads photos, handles retries with exponential backoff.
- **GeminiAPI** (`Services/GeminiAPI.swift`): Google Gemini API for photo-based nutritional analysis. Returns `NutritionAnalysis` struct.

### Data Model

Single SwiftData model: `Meal` with photo data stored externally (`@Attribute(.externalStorage)`). Uses `craftDocId` to track synced items.

### Design System

Uses iOS 26 Liquid Glass design language. Components in `Utilities/DesignSystem.swift`.
