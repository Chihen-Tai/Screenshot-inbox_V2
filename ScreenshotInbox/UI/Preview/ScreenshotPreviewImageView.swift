import SwiftUI

struct ScreenshotPreviewImageView: View {
    let screenshot: Screenshot
    let thumbnailProvider: MacThumbnailProvider?

    var body: some View {
        if let image = thumbnailProvider?.loadPreviewImage(for: screenshot) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color(nsColor: .textBackgroundColor))
        } else {
            MockThumbnailView(kind: screenshot.thumbnailKind)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
        }
    }
}
