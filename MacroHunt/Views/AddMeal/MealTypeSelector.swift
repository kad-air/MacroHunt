// Views/AddMeal/MealTypeSelector.swift
import SwiftUI

struct MealTypeSelector: View {
    @Binding var selectedType: MealType

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MealType.allCases) { type in
                MealTypeButton(
                    type: type,
                    isSelected: selectedType == type,
                    action: { selectedType = type }
                )
            }
        }
    }
}

private struct MealTypeButton: View {
    let type: MealType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.title2)
                Text(type.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selected = MealType.lunch

        var body: some View {
            MealTypeSelector(selectedType: $selected)
                .padding()
        }
    }

    return PreviewWrapper()
}
