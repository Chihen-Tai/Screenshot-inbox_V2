import SwiftUI

/// 10 mock thumbnail variants drawn with SwiftUI primitives.
/// Phase 3 deletes this and replaces with image-based thumbnails from disk.
struct MockThumbnailView: View {
    let kind: ThumbnailKind

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                content(in: geo.size)
                    .padding(geo.size.width * 0.07)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .code, .terminal:
            Color(red: 0.10, green: 0.12, blue: 0.16)
        case .uiMockup:
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.95, blue: 0.99), Color(red: 0.84, green: 0.87, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .chat:
            Color(red: 0.96, green: 0.97, blue: 0.99)
        default:
            Color.white
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        switch kind {
        case .document, .paper, .notes, .lectureSlide:
            documentish(size: size)
        case .code:
            codeLines(size: size)
        case .terminal:
            terminalLines(size: size)
        case .chat:
            chatBubbles(size: size)
        case .chart:
            barChart(size: size)
        case .uiMockup:
            mockupPanels(size: size)
        case .table:
            tableGrid(size: size)
        }
    }

    private func documentish(size: CGSize) -> some View {
        let isSlide = kind == .lectureSlide
        let isPaper = kind == .paper
        let isNotes = kind == .notes
        return VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78))
                .frame(width: size.width * (isSlide ? 0.62 : 0.5), height: isSlide ? 12 : 6)
            if isSlide {
                Capsule().fill(Color.black.opacity(0.45))
                    .frame(width: size.width * 0.4, height: 5)
                Spacer().frame(height: 4)
            }
            ForEach(0..<(isSlide ? 4 : (isNotes ? 3 : 7)), id: \.self) { i in
                if isNotes {
                    HStack(spacing: 4) {
                        Circle().fill(Color.black.opacity(0.3)).frame(width: 3, height: 3)
                        Capsule().fill(Color.black.opacity(0.18))
                            .frame(width: size.width * (0.7 - Double(i) * 0.07), height: 3)
                    }
                } else {
                    Capsule().fill(Color.black.opacity(0.18))
                        .frame(width: size.width * (0.85 - Double(i % 3) * 0.12), height: 3)
                }
            }
            if isPaper {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(Color.black.opacity(0.14)).frame(height: 2.5)
                        }
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                        .frame(width: size.width * 0.22, height: 26)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func codeLines(size: CGSize) -> some View {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.55, blue: 0.6),
            Color(red: 0.55, green: 0.85, blue: 0.95),
            Color(red: 0.95, green: 0.85, blue: 0.55),
            Color(red: 0.7, green: 0.85, blue: 0.55),
        ]
        return VStack(alignment: .leading, spacing: 3.5) {
            ForEach(0..<9, id: \.self) { i in
                HStack(spacing: 4) {
                    Capsule().fill(Color.gray.opacity(0.45)).frame(width: 12, height: 2.5)
                    Capsule().fill(palette[i % palette.count])
                        .frame(width: CGFloat(28 + (i * 13) % 50), height: 2.5)
                    Capsule().fill(Color.white.opacity(0.55))
                        .frame(width: CGFloat(14 + (i * 9) % 28), height: 2.5)
                    if i % 3 == 0 {
                        Capsule().fill(palette[(i + 1) % palette.count])
                            .frame(width: CGFloat(20 + (i * 7) % 22), height: 2.5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func terminalLines(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<9, id: \.self) { i in
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.95, blue: 0.7))
                    Capsule()
                        .fill(Color.white.opacity(i % 2 == 0 ? 0.7 : 0.45))
                        .frame(width: CGFloat(40 + (i * 17) % 90), height: 2.5)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func chatBubbles(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 0) {
                    if i % 2 == 1 { Spacer(minLength: 0) }
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(i % 2 == 1 ? Theme.Palette.accent.opacity(0.85) : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7).strokeBorder(
                                Color.black.opacity(i % 2 == 1 ? 0 : 0.10),
                                lineWidth: 0.5
                            )
                        )
                        .frame(width: CGFloat(60 + (i * 11) % 40), height: 13)
                    if i % 2 == 0 { Spacer(minLength: 0) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func barChart(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(Color.black.opacity(0.6)).frame(width: size.width * 0.4, height: 5)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let h = CGFloat(14 + (i * 19) % 50)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.7))
                        .frame(width: 9, height: h)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mockupPanels(size: CGSize) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.55)).frame(width: 5, height: 5)
                Circle().fill(Color.yellow.opacity(0.55)).frame(width: 5, height: 5)
                Circle().fill(Color.green.opacity(0.55)).frame(width: 5, height: 5)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.7))
                    .frame(width: size.width * 0.22)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color.black.opacity(0.45)).frame(width: size.width * 0.3, height: 4)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tableGrid(size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        ZStack {
                            Rectangle()
                                .fill(row == 0 ? Color.gray.opacity(0.18)
                                      : (col == 0 ? Color.gray.opacity(0.06) : Color.clear))
                            Capsule()
                                .fill(Color.black.opacity(row == 0 ? 0.55 : 0.22))
                                .frame(height: 2.5)
                                .padding(.horizontal, 5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .border(Color.black.opacity(0.08), width: 0.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
