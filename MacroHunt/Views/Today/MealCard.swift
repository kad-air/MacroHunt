// Views/Today/MealCard.swift
import SwiftUI

/// A logged meal as a glass row: thumbnail, name + meal type/time, P/C/F chips, and the
/// calorie figure on the trailing edge.
struct MealCard: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 13) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text("\(meal.mealType.rawValue) · \(meal.date.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink2)

                HStack(spacing: 9) {
                    macroChip(Int(meal.protein), "P", Theme.protein)
                    macroChip(Int(meal.carbs), "C", Theme.carbs)
                    macroChip(Int(meal.fat), "F", Theme.fat)
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 8)

            VStack(spacing: 1) {
                Text("\(meal.calories)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text("KCAL")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(11)
        .glassContainer(cornerRadius: 22)
    }

    private var thumbnail: some View {
        Group {
            if let firstPhotoData = meal.photoData.first, let uiImage = UIImage(data: firstPhotoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.chip
                    .overlay {
                        Image(systemName: meal.mealType.icon)
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.ink2)
                    }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func macroChip(_ value: Int, _ letter: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)\(letter)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink2)
        }
    }
}

#Preview {
    MealCard(meal: Meal(
        name: "Grilled Chicken Salad",
        mealType: .lunch,
        calories: 450,
        protein: 35.0,
        carbs: 20.5,
        fat: 25.0,
        keyNutrients: "Vitamin A, Vitamin C"
    ))
    .padding()
    .background(WarmBackground())
}
