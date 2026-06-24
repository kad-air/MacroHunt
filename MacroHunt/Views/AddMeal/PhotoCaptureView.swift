// Views/AddMeal/PhotoCaptureView.swift
import SwiftUI
import PhotosUI
import UIKit

// MARK: - Camera View Controller Wrapper

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Capture View

struct PhotoCaptureView: View {
    @Binding var selectedPhotos: [UIImage]
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var photoPickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 10) {
            if selectedPhotos.isEmpty {
                // Empty slot prompt
                VStack(spacing: 7) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.ink2)
                    Text("Add up to 5 photos — or just describe it below")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 118)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.chip)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.hair, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        )
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedPhotos.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedPhotos[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                                Button {
                                    withAnimation { _ = selectedPhotos.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 110)
            }

            // Take photo / Choose photo
            HStack(spacing: 8) {
                Button {
                    showingCamera = true
                } label: {
                    photoActionLabel(icon: "camera", title: "Take photo")
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                    photoActionLabel(icon: "photo.on.rectangle", title: "Choose photo")
                }
                .buttonStyle(.plain)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                selectedPhotos.append(image)
                capturedImage = nil
            }
        }
        .onChange(of: photoPickerItems) { _, items in
            Task<Void, Never> {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedPhotos.append(image)
                        }
                    }
                }
                await MainActor.run {
                    photoPickerItems = []
                }
            }
        }
    }

    private func photoActionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 16))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.chip)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hair, lineWidth: 1))
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var photos: [UIImage] = []

        var body: some View {
            PhotoCaptureView(selectedPhotos: $photos)
                .padding()
        }
    }

    return PreviewWrapper()
}
