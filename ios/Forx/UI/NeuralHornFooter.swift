import SwiftUI

/// "© 2026 The Neural Horn" at the foot of Settings: the longhorn opens out from its centre
/// when Settings appears, then the line follows. Taps open theneuralhorn.com. The year is
/// always the current one.
struct NeuralHornFooter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    static let site = URL(string: "https://www.theneuralhorn.com")!

    static var year: Int { Calendar.current.component(.year, from: Date()) }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Link(destination: Self.site) {
            VStack(spacing: 8) {
                Image("neural-horn")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 14)
                    .foregroundStyle(.secondary)
                    // opens from the centre out to the horn tips
                    .mask {
                        Rectangle().scaleEffect(x: open ? 1 : 0.001, y: 1, anchor: .center)
                    }
                Text(verbatim: "© \(Self.year) The Neural Horn")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(open ? 1 : 0)
                    .offset(y: open ? 0 : 3)
                Text(verbatim: "Forx \(Self.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(open ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forx \(Self.version), © \(Self.year) The Neural Horn")
        .accessibilityAddTraits(.isLink)
        .onAppear {
            guard !open else { return }
            if reduceMotion {
                open = true
            } else {
                withAnimation(.spring(duration: 1.0, bounce: 0)) { open = true }
            }
        }
    }
}
