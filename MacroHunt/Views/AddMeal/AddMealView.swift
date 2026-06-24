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
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isAnalyzing {
                        analyzingView
                    } else if showingReview, let analysis = Binding($analysisResult) {
                        reviewView(analysis: analysis)
                    } else {
                        captureView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }

            if isSaving { savingOverlay }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private func sheetHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.chip))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Theme.ink2)
    }

    // MARK: - Capture

    private var captureView: some View {
        VStack(alignment: .leading, spacing: 17) {
            sheetHeader("Add a meal")

            VStack(alignment: .leading, spacing: 9) {
                fieldLabel("Photos")
                PhotoCaptureView(selectedPhotos: $selectedPhotos)
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 9) {
                fieldLabel("Description")
                TextField("What are you eating?", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                    .inputFieldStyle()
            }

            VStack(alignment: .leading, spacing: 9) {
                fieldLabel("Meal type")
                MealTypeSelector(selectedType: $mealType)
            }

            VStack(alignment: .leading, spacing: 9) {
                fieldLabel("When")
                HStack {
                    Image(systemName: "clock").font(.system(size: 15)).foregroundStyle(Theme.ink2)
                    DatePicker("", selection: $mealDate, in: ...Date())
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Spacer()
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.chip)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hair, lineWidth: 1))
                )
            }

            Button {
                analyzePhotos()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Analyze with AI")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: canAnalyze))
            .disabled(!canAnalyze)
            .padding(.top, 4)
        }
    }

    /// Analysis requires at least a photo or a non-empty description.
    private var canAnalyze: Bool {
        !selectedPhotos.isEmpty || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 15) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Analyzing your meal…")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(selectedPhotos.isEmpty ? "Reading your description" : "Reading your photos and description")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewView(analysis: Binding<NutritionAnalysis>) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            sheetHeader("Review meal")

            if !selectedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedPhotos.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                    }
                }
                .frame(height: 86)
            }

            ReviewMealView(analysis: analysis, mealType: $mealType, notes: $notes)

            Button { saveMeal() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("Save meal")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !isSaving))
            .disabled(isSaving)
            .padding(.top, 4)

            Button {
                showingReview = false
                analysisResult = nil
            } label: {
                Text(selectedPhotos.isEmpty ? "Edit details" : "Re-analyze")
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Saving meal…").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            }
            .padding(28)
            .glassContainer(cornerRadius: 22)
        }
    }

    // MARK: - Actions

    private func analyzePhotos() {
        guard canAnalyze else { return }
        guard credentials.isValid else {
            errorMessage = "Please configure your API credentials in Settings."
            return
        }

        isAnalyzing = true
        Task {
            do {
                let imageData = selectedPhotos.compactMap { $0.jpegData(compressionQuality: 0.7) }
                let claude = ClaudeAPI(apiKey: credentials.anthropicKey)
                let result = try await claude.analyzeMealPhotos(images: imageData, description: description, mealType: mealType)
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
                let photoData = selectedPhotos.compactMap { $0.jpegData(compressionQuality: 0.8) }
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
        .modelContainer(for: Meal.self, inMemory: true)
}
