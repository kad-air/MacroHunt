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

// MARK: - Downsampling at ingest

extension UIImage {
    /// This image capped at `maxPixel` on its long edge, upright. A 12–48 MP photo held as a
    /// `UIImage` is a 48–190 MB bitmap; five of them in the Add sheet was a real memory spike.
    func downsampled(maxPixel: Int) -> UIImage {
        guard let data = jpegData(compressionQuality: 0.9),
              let image = ImageDownsampler.cgImage(from: data, maxPixel: maxPixel) else { return self }
        return UIImage(cgImage: image)
    }

    /// Object identity, for `ForEach` (the same photo picked twice must still be two rows).
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
}

// MARK: - Photo Capture View

struct PhotoCaptureView: View {
    /// The analyze prompt and the empty-state copy both promise "up to 5 photos".
    static let maxPhotos = 5

    @Binding var selectedPhotos: [UIImage]
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var photoPickerItems: [PhotosPickerItem] = []

    private var remainingSlots: Int { max(Self.maxPhotos - selectedPhotos.count, 0) }
    /// No camera on the simulator (and some iPads); presenting the camera picker there crashes.
    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

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
                        // Identity is the image object, not its index: an index-keyed row
                        // whose remove button captured a stale index could remove the wrong
                        // photo (or trap out of range) on a quick double tap.
                        ForEach(selectedPhotos, id: \.identity) { photo in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                                Button {
                                    withAnimation { selectedPhotos.removeAll { $0 === photo } }
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

            // Take photo / Choose photo — hidden once the photo limit is reached.
            if remainingSlots > 0 {
                HStack(spacing: 8) {
                    if cameraAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            photoActionLabel(icon: "camera", title: "Take photo")
                        }
                        .buttonStyle(.plain)
                    }

                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: remainingSlots, matching: .images) {
                        photoActionLabel(icon: "photo.on.rectangle", title: "Choose photo")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                if remainingSlots > 0 {
                    selectedPhotos.append(image.downsampled(maxPixel: ImageDownsampler.storageMaxPixel))
                }
                capturedImage = nil
            }
        }
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task<Void, Never> {
                for item in items {
                    // Downsample straight from the encoded data, so the full-size bitmap is
                    // never decoded — and off the main actor, since a 48 MP HEIC takes a moment.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = await Task.detached(priority: .userInitiated, operation: {
                           ImageDownsampler.cgImage(from: data, maxPixel: ImageDownsampler.storageMaxPixel)
                       }).value,
                       selectedPhotos.count < Self.maxPhotos {
                        selectedPhotos.append(UIImage(cgImage: image))
                    }
                }
                photoPickerItems = []
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
