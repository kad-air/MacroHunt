// Views/Today/MealCard.swift
import SwiftUI

struct MealCard: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 16) {
            // Photo or placeholder
            if let firstPhotoData = meal.photoData.first,
               let uiImage = UIImage(data: firstPhotoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: meal.mealType.icon)
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
            }

            // Meal info
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(meal.mealType.rawValue, systemImage: meal.mealType.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(meal.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Macros
                HStack(spacing: 8) {
                    MacroChip(value: meal.calories, unit: "cal", color: .orange)
                    MacroChip(value: Int(meal.protein), unit: "P", color: .red)
                    MacroChip(value: Int(meal.carbs), unit: "C", color: .blue)
                    MacroChip(value: Int(meal.fat), unit: "F", color: .yellow)
                }
            }

            Spacer()
        }
        .padding()
        .glassContainer(cornerRadius: 16)
    }
}

// MARK: - Macro Chip

private struct MacroChip: View {
    let value: Int
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value)\(unit)")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.secondary)
    }
}

#Preview {
    VStack {
        MealCard(meal: Meal(
            name: "Grilled Chicken Salad",
            mealType: .lunch,
            calories: 450,
            protein: 35.0,
            carbs: 20.5,
            fat: 25.0,
            keyNutrients: "Vitamin A, Vitamin C"
        ))
    }
    .padding()
}
