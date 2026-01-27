# MacroHunt

A personal iOS app for logging meals with photos, AI-powered nutritional analysis, and comprehensive tracking/analytics. Meals are saved locally with SwiftData and synced to Craft Docs.

## Features

- **Photo-based meal logging** - Capture meals with camera or photo library (up to 5 photos)
- **AI nutritional analysis** - Gemini AI analyzes photos to estimate calories, protein, carbs, fat, and key nutrients
- **Today view** - Daily summary with calorie/macro progress and meal cards
- **Calendar view** - Monthly grid with color-coded calorie indicators and day details
- **Trends view** - Visualize calorie trends and macro breakdowns with Swift Charts
- **Craft Docs sync** - Meals saved to your "Meal Tracker" collection in Craft

## Screenshots

*Coming soon*

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Gemini API key (for nutritional analysis)
- Craft Docs API credentials (for cloud sync)

## Setup

1. Clone the repository
2. Open `MacroHunt.xcodeproj` in Xcode
3. Build and run on your device or simulator
4. On first launch, complete the onboarding to enter your API credentials:
   - **Craft API Token** - From Craft Docs developer settings
   - **Craft Space ID** - Your Craft workspace ID
   - **Collection ID** - The "Meal Tracker" collection ID
   - **Gemini API Key** - From Google AI Studio

## Architecture

- **SwiftUI** - Modern declarative UI
- **SwiftData** - Local persistence for fast analytics
- **Swift Charts** - Native charting for trends visualization
- **Async/Await** - Modern concurrency throughout
- **Keychain** - Secure credential storage

### Project Structure

```
MacroHunt/
├── Models/
│   └── Meal.swift              # SwiftData model
├── Views/
│   ├── MainTabView.swift
│   ├── Today/                  # Daily summary
│   ├── AddMeal/                # Photo capture & analysis flow
│   ├── Calendar/               # Monthly calendar
│   ├── Trends/                 # Charts & analytics
│   └── Settings/               # Credentials & preferences
├── Services/
│   ├── CraftAPI.swift          # Craft Docs integration
│   ├── GeminiAPI.swift         # AI analysis
│   └── MealRepository.swift    # Data layer
└── Utilities/
    ├── CredentialsManager.swift
    ├── KeychainHelper.swift
    └── DesignSystem.swift      # Liquid Glass components
```

## Design

MacroHunt uses an iOS 26 Liquid Glass design language with translucent materials and modern visual effects.

## License

Private project - All rights reserved
