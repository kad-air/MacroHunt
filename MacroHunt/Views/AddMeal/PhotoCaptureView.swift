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
        VStack(spacing: 16) {
            // Display selected photos
            if !selectedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedPhotos.enumerated()), id: \.offset) { (index: Int, image: UIImage) in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                Button {
                                    withAnimation {
                                        selectedPhotos.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 110)
            }

            // Add photo buttons
            HStack(spacing: 16) {
                Button {
                    showingCamera = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Camera")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                }

                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text("Library")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                }
            }
            .foregroundColor(.primary)
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
