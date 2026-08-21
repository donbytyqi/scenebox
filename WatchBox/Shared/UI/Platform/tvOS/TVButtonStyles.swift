//
//  TVButtonStyles.swift
//  SceneBox
//
//  Created by SpontaneousArray on 06.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVAccentButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, selected: selected)
    }

    struct Content: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(isFocused || selected ? Theme.onAccent : .white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(fill, in: Capsule())
                .scaleEffect(isFocused ? 1.05 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var fill: Color {
            if isFocused { return Theme.accent }
            return selected ? Theme.accent.opacity(0.85) : .white.opacity(0.12)
        }
    }
}

struct TVCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, diameter: diameter)
    }

    struct Content: View {
        let configuration: Configuration
        let diameter: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(isFocused ? Color.black : .white.opacity(0.85))
                .frame(width: diameter, height: diameter)
                .background(isFocused ? Color.white : Color.white.opacity(0.14), in: Circle())
                .scaleEffect(isFocused ? 1.05 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

struct TVListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    struct Content: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isFocused ? Color.white : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .scaleEffect(isFocused ? 1.01 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

struct TVFocusRing: View {
    var cornerRadius: CGFloat = Theme.posterCorner
    let isFocused: Bool
    static let gap: CGFloat = 8
    static let width: CGFloat = 4

    var body: some View {
        let inset = Self.gap + Self.width
        RoundedRectangle(cornerRadius: cornerRadius + inset, style: .continuous)
            .strokeBorder(.white, lineWidth: Self.width)
            .padding(-inset)
            .opacity(isFocused ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

struct TVPosterButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.posterCorner
    var ring = true
    var scale: CGFloat = 1.08

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, cornerRadius: cornerRadius, ring: ring, scale: scale)
    }

    struct Content: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let ring: Bool
        let scale: CGFloat
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .overlay {
                    if ring { TVFocusRing(cornerRadius: cornerRadius, isFocused: isFocused) }
                }
                .scaleEffect(isFocused ? scale : 1)
                .shadow(color: .black.opacity(isFocused ? 0.55 : 0), radius: 28, y: 14)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}
#endif
