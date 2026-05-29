// client/Sources/Features/Chat/MarkdownContentView.swift
import SwiftUI
import MarkdownUI
import Highlightr
import LaTeXSwiftUI

// MARK: - Content segmentation (Markdown + display math)

private enum ContentSegment: Identifiable {
    case markdown(String)
    case displayMath(String)    // $$...$$ blocks

    var id: String {
        switch self {
        case .markdown(let s):    return "md:\(s.hashValue)"
        case .displayMath(let s): return "math:\(s.hashValue)"
        }
    }
}

// Splits text on $$...$$ boundaries so LaTeX renders natively.
private func parseSegments(_ raw: String) -> [ContentSegment] {
    guard let regex = try? NSRegularExpression(pattern: #"(?s)\$\$(.+?)\$\$"#) else {
        return [.markdown(raw)]
    }
    let ns = raw as NSString
    var result: [ContentSegment] = []
    var cursor = 0
    for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
        let before = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.markdown(before))
        }
        if let r = Range(match.range(at: 1), in: raw) {
            let formula = String(raw[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formula.isEmpty { result.append(.displayMath(formula)) }
        }
        cursor = match.range.upperBound
    }
    let tail = ns.substring(from: cursor)
    if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(.markdown(tail))
    }
    return result.isEmpty ? [.markdown(raw)] : result
}

// MARK: - Public view

struct MarkdownContentView: View {
    let text: String

    private var segments: [ContentSegment] { parseSegments(text) }

    var body: some View {
        // Fast path: plain markdown, no LaTeX blocks
        if segments.count == 1, case .markdown(let md) = segments[0] {
            markdownView(md)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(segments) { seg in
                    switch seg {
                    case .markdown(let md):     markdownView(md)
                    case .displayMath(let eq):  DisplayMathBlock(formula: eq)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func markdownView(_ md: String) -> some View {
        Markdown(md)
            .markdownTheme(.maverick)
            .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter.shared)
            .textSelection(.enabled)
    }
}

// MARK: - Display math block  ($$...$$)

private struct DisplayMathBlock: View {
    let formula: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Text("LaTeX")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = "$$\(formula)$$"
                    withAnimation(.snappy(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.snappy(duration: 0.15)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                        Text(copied ? "Copied!" : "Copy").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? Color.green.opacity(0.85) : .white.opacity(0.35))
                    .animation(.snappy(duration: 0.15), value: copied)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.035))

            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)

            LaTeX("$$\(formula)$$")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - Highlightr syntax highlighter

final class HighlightrSyntaxHighlighter: CodeSyntaxHighlighter {
    static let shared = HighlightrSyntaxHighlighter()
    private let highlightr: Highlightr

    private init() {
        let h = Highlightr()!
        h.setTheme(to: "atom-one-dark")
        self.highlightr = h
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        if let lang = language?.lowercased(),
           let ns = highlightr.highlight(content, as: lang),
           let attr = try? AttributedString(ns, including: \.uiKit) {
            return Text(attr)
        }
        return Text(content)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
    }
}

// MARK: - Code block with language header + copy button

private struct CodeBlockWithCopyButton: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                if let lang = configuration.language, !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.40))
                }
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = configuration.content
                    withAnimation(.snappy(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.snappy(duration: 0.15)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                        Text(copied ? "Copied!" : "Copy").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? Color.green.opacity(0.85) : .white.opacity(0.38))
                    .animation(.snappy(duration: 0.15), value: copied)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.035))

            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)

            configuration.label
                .relativeLineSpacing(.em(0.22))
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - Maverick refined markdown theme

private extension MarkdownUI.Theme {
    static let maverick: MarkdownUI.Theme = MarkdownUI.Theme()

        // ── Body text ──────────────────────────────────────────────────────────────
        .text {
            ForegroundColor(.white.opacity(0.88))
            FontSize(15)
        }
        .link {
            ForegroundColor(Color(red: 0.33, green: 0.65, blue: 1.0))
        }

        // ── Inline styles ──────────────────────────────────────────────────────────
        .code {
            FontFamily(.custom("MesloLGS NF"))
            FontSize(13)
            ForegroundColor(Color(red: 0.96, green: 0.64, blue: 0.30))
            BackgroundColor(Color.white.opacity(0.09))
        }
        .strong {
            FontWeight(.semibold)
        }

        // ── Headings ───────────────────────────────────────────────────────────────
        .heading1 { label in
            VStack(alignment: .leading, spacing: 7) {
                label.markdownTextStyle {
                    FontSize(22)
                    FontWeight(.bold)
                    ForegroundColor(.white)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.5)
            }
            .markdownMargin(top: 20, bottom: 12)
        }
        .heading2 { label in
            label
                .markdownMargin(top: 16, bottom: 6)
                .markdownTextStyle {
                    FontSize(18)
                    FontWeight(.semibold)
                    ForegroundColor(Color.white.opacity(0.95))
                }
        }
        .heading3 { label in
            label
                .markdownMargin(top: 12, bottom: 4)
                .markdownTextStyle {
                    FontSize(16)
                    FontWeight(.semibold)
                    ForegroundColor(Color.white.opacity(0.90))
                }
        }
        .heading4 { label in
            label
                .markdownMargin(top: 10, bottom: 3)
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.semibold)
                    ForegroundColor(Color.white.opacity(0.72))
                }
        }
        .heading5 { label in
            label
                .markdownMargin(top: 8, bottom: 2)
                .markdownTextStyle {
                    FontSize(13)
                    FontWeight(.medium)
                    ForegroundColor(Color.white.opacity(0.58))
                }
        }
        .heading6 { label in
            label
                .markdownMargin(top: 6, bottom: 2)
                .markdownTextStyle {
                    FontSize(12)
                    FontWeight(.medium)
                    ForegroundColor(Color.white.opacity(0.45))
                }
        }

        // ── Block elements ─────────────────────────────────────────────────────────
        .paragraph { label in
            label.markdownMargin(top: 0, bottom: 10)
        }

        .blockquote { label in
            HStack(alignment: .top, spacing: 0) {
                // Accent bar
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 3)
                // Content with tinted background
                label
                    .markdownTextStyle {
                        ForegroundColor(.white.opacity(0.60))
                        FontSize(14)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.vertical, 4)
        }

        .codeBlock { config in
            CodeBlockWithCopyButton(configuration: config)
        }

        // ── Table ──────────────────────────────────────────────────────────────────
        .table { label in
            label
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .padding(.vertical, 6)
        }
        .tableCell { config in
            config.label
                .markdownTextStyle { FontSize(13) }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 0.5)
                }
        }

        // ── Thematic break ─────────────────────────────────────────────────────────
        .thematicBreak {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 0.5)
                .padding(.vertical, 10)
        }

}
