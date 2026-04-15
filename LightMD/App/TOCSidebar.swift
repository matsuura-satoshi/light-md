import SwiftUI

struct TOCSidebar: View {
    let headings: [TOCHeading]
    let activeID: String?
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if headings.isEmpty {
                Spacer()
                Text("No headings")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(headings) { heading in
                            Button {
                                onSelect(heading.id)
                            } label: {
                                Text(heading.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(heading.id == activeID ? accent : .secondary)
                                    .fontWeight(heading.id == activeID ? .medium : .regular)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 12)
                                    .padding(.leading, CGFloat((heading.level - 1) * 12))
                                    .background(
                                        heading.id == activeID
                                            ? accent.opacity(0.08)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(width: 220)
        .background(.background.opacity(0.8))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(.separator),
            alignment: .leading
        )
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
