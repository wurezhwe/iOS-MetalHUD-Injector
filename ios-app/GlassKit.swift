import SwiftUI

/// Visual pieces shared by the app.
///
/// On iOS 26+ the cards and the search field use the real Liquid Glass material
/// (`View.glassEffect(_:in:)`). The deployment target is 16.0, so everything is
/// wrapped in an availability check and falls back to a hand-rolled frosted
/// surface that reads the same in a screenshot.
enum Glass {

    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }
}

// MARK: - Card surface

/// A rounded panel: Liquid Glass on iOS 26+, a tuned material on older systems.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    tint.map { Glass.regular.tint($0) } ?? Glass.regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }
}

// MARK: - Search field

/// Pill-shaped search box. Built from a TextField so the keyboard behaves, with
/// the glass drawn behind it.
struct GlassSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // The list is local; there is no reason to submit on every key.
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .modifier(GlassPill())
        .animation(.easeOut(duration: 0.12), value: text.isEmpty)
    }
}

private struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(Glass.regular.interactive(true), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
}

// MARK: - Buttons

/// Small rounded action button. Uses the system glass button style where it
/// exists so it picks up the platform tinting.
struct GlassActionButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var tint: Color = Theme.accent
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.black : Color.primary)
        .modifier(GlassActionSurface(prominent: prominent, tint: tint))
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

private struct GlassActionSurface: ViewModifier {
    var prominent: Bool
    var tint: Color

    func body(content: Content) -> some View {
        let shape = Capsule()

        if #available(iOS 26.0, *) {
            content.glassEffect(
                prominent
                    ? Glass.regular.tint(tint).interactive(true)
                    : Glass.regular.interactive(true),
                in: shape
            )
        } else {
            content
                .background {
                    if prominent {
                        shape.fill(tint)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                }
                .overlay(shape.strokeBorder(Color.white.opacity(prominent ? 0 : 0.10), lineWidth: 1))
        }
    }
}

// MARK: - Modifier helpers

extension View {
    /// Rounded glass panel.
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}
