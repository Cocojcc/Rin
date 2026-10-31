import SwiftUI

/// Her face from the app icon on a rounded tile, in a given mood.
struct AppMark: View {
    var size: CGFloat
    var mood: Mood = .calm

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(mood.avatar)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The mark as things stand now. Its own view, so only the face redraws with each reading.
struct MoodMark: View {
    var size: CGFloat

    var body: some View {
        AppMark(size: size, mood: Status.now().mood)
    }
}
