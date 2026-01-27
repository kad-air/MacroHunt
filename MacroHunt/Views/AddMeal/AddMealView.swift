// Views/AddMeal/AddMealView.swift
import SwiftUI
import UIKit

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @State private var selectedPhotos: [UIImage] = []
    @State private var mealType: MealType = .lunch
    @State private var mealDate: Date = Date()
    @State private var description: String = ""
    @State private var notes: String = ""

    @State private var isAnalyzing = false
    @State private var analysisResult: NutritionAnalysis?
    @State private var errorMessage: String?
    @State private var showingReview = false

    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if !showingReview {
                            captureView
                        } else if let analysis = Binding($analysisResult) {
                            reviewView(analysis: analysis)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(showingReview ? "Review Meal" : "Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if showingReview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveMeal()
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .overlay {
                if isAnalyzing {
                    analyzingOverlay
                }
                if isSaving {
                    savingOverlay
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Capture View

    private var captureView: some View {
        VStack(spacing: 24) {
            // Photo Capture
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Meal Photos", icon: "camera.fill")
                    PhotoCaptureView(selectedPhotos: $selectedPhotos)
                }
            }

            // Description
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Description (Optional)", icon: "text.alignleft")
                    TextField("What are you eating?", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                        .inputFieldStyle()
                }
            }

            // Meal Type
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Meal Type", icon: "fork.knife")
                    MealTypeSelector(selectedType: $mealType)
                }
            }

            // Date & Time
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Date & Time", icon: "clock.fill")
                    DatePicker("", selection: $mealDate, in: ...Date())
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
            }

            // Analyze Button
            Button {
                analyzePhotos()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Analyze with AI")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !selectedPhotos.isEmpty))
            .disabled(selectedPhotos.isEmpty)
        }
    }

    // MARK: - Review View

    @ViewBuilder
    private func reviewView(analysis: Binding<NutritionAnalysis>) -> some View {
        VStack(spacing: 24) {
            // Photo preview
            if !selectedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedPhotos.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .frame(height: 90)
            }

            GlassCard {
                ReviewMealView(analysis: analysis, mealType: $mealType, notes: $notes)
            }

            Button {
                showingReview = false
                analysisResult = nil
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Retake Photos")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Overlays

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            GlassCard {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing your meal...")
                        .font(.headline)
                    Text("This may take a moment")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 200)
            }
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            GlassCard {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Saving meal...")
                        .font(.headline)
                }
                .frame(width: 200)
            }
        }
    }

    // MARK: - Actions

    private func analyzePhotos() {
        guard !selectedPhotos.isEmpty else { return }
        guard credentials.isValid else {
            errorMessage = "Please configure your API credentials in Settings."
            return
        }

        isAnalyzing = true

        Task {
            do {
                // Convert images to JPEG data
                let imageData = selectedPhotos.compactMap { image -> Data? in
                    image.jpegData(compressionQuality: 0.7)
                }

                let gemini = GeminiAPI(apiKey: credentials.geminiKey)
                let result = try await gemini.analyzeMealPhotos(
                    images: imageData,
                    description: description,
                    mealType: mealType
                )

                await MainActor.run {
                    analysisResult = result
                    showingReview = true
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func saveMeal() {
        guard let analysis = analysisResult else { return }

        isSaving = true

        Task {
            do {
                // Convert photos to data
                let photoData = selectedPhotos.compactMap { image -> Data? in
                    image.jpegData(compressionQuality: 0.8)
                }

                // Create meal object
                let meal = Meal(
                    name: analysis.mealName,
                    date: mealDate,
                    mealType: mealType,
                    calories: analysis.calories,
                    protein: analysis.protein,
                    carbs: analysis.carbs,
                    fat: analysis.fat,
                    keyNutrients: analysis.keyNutrients,
                    notes: notes,
                    photoData: photoData
                )

                // Save to both Craft and local DB (transactional - Craft first)
                let repository = MealRepository(modelContext: modelContext, credentials: credentials)
                try await repository.saveMealWithSync(meal)

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save meal: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    AddMealView()
        .environmentObject(CredentialsManager())
}
