import SwiftUI
#if compiler(<6.2) || COMPILER_PRE_MACOS26
import AppKit
import CoreMedia
@preconcurrency import ScreenCaptureKit

extension NSImage: @unchecked @retroactive Sendable {}
extension CMSampleBuffer: @unchecked @retroactive Sendable {}
extension SCShareableContent: @unchecked @retroactive Sendable {}
extension SCContentFilter: @unchecked @retroactive Sendable {}
extension SCStreamConfiguration: @unchecked @retroactive Sendable {}
#endif

#if compiler(<6.2) || COMPILER_PRE_MACOS26

// MARK: - Glass Effect Fallbacks for macOS < 26 / Xcode < 16.5

public struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        HStack(spacing: spacing) {
            content()
        }
    }
}

public struct GlassEffectStyle: Sendable {
    public static var regular: GlassEffectStyle { GlassEffectStyle() }

    public func interactive(_ isInteractive: Bool = true) -> GlassEffectStyle { self }
    public func tint(_ color: Color) -> GlassEffectStyle { self }
}

extension View {
    @ViewBuilder
    public func glassEffect<S: Shape>(_ style: GlassEffectStyle = .regular, in shape: S) -> some View {
        self.background(shape.fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    public func glassEffect<S: Shape>(in shape: S) -> some View {
        self.background(shape.fill(Color.primary.opacity(0.06)))
    }
}

public struct GlassFallbackButtonStyle: ButtonStyle {
    let isProminent: Bool

    public init(isProminent: Bool) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isProminent ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .foregroundStyle(isProminent ? Color.white : Color.primary)
    }
}

extension ButtonStyle where Self == GlassFallbackButtonStyle {
    public static var glass: GlassFallbackButtonStyle {
        GlassFallbackButtonStyle(isProminent: false)
    }

    public static var glassProminent: GlassFallbackButtonStyle {
        GlassFallbackButtonStyle(isProminent: true)
    }
}

#endif
