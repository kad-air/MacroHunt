// Views/AddMeal/MealTypeSelector.swift
import SwiftUI

struct MealTypeSelector: View {
    @Binding var selectedType: MealType

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases) { type in
                let isOn = selectedType == type
                Button {
                    selectedType = type
                } label: {
                    Text(type.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.accent : Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(isOn ? Theme.accentSoft : Theme.chip)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(isOn ? Theme.accent : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selected = MealType.lunch
        var body: some View {
            MealTypeSelector(selectedType: $selected).padding()
        }
    }
    return PreviewWrapper()
}
