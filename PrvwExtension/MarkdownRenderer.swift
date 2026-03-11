//
//  MarkdownRenderer.swift
//  PrvwExtension
//
//  Created by Akshat Shukla on 11/03/26.
//

import Cocoa
import Markdown

// MARK: - MarkdownRenderer

/// Converts a Markdown file URL into a styled NSAttributedString.
/// Analogous to ZipParser, TarParser, etc. — pure parsing/rendering, no view logic.
enum MarkdownRenderer {

    // MARK: - Public API

    /// Parses the Markdown file at `url` and returns a styled attributed string.
    static func render(url: URL) throws -> NSAttributedString {
        let source = try String(contentsOf: url, encoding: .utf8)
        let document = Document(parsing: source)
        var walker = AttributedStringWalker()
        walker.visit(document)
        return walker.result
    }
}

// MARK: - AttributedStringWalker

private struct AttributedStringWalker: MarkupWalker {

    // MARK: - State

    var result = NSMutableAttributedString()

    /// Tracks the current list nesting level for indentation.
    private var listDepth = 0
    /// Tracks the current item counter for ordered lists (per depth).
    private var orderedCounters: [Int: Int] = [:]
    /// Whether the current list level is ordered.
    private var isOrderedList: [Int: Bool] = [:]

    // MARK: - Heading

    mutating func visitHeading(_ heading: Heading) -> () {
        let text = heading.plainText
        let fontSize = Self.headingFontSize(level: heading.level)
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Self.headingParagraphStyle(level: heading.level),
        ]
        let str = NSMutableAttributedString(string: text, attributes: attrs)
        str.append(NSAttributedString(string: "\n"))
        result.append(str)
    }

    // MARK: - Paragraph

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        let inline = renderInlineChildren(of: paragraph)
        inline.append(NSAttributedString(string: "\n"))
        // Apply body paragraph style
        inline.addAttribute(.paragraphStyle, value: Self.bodyParagraphStyle, range: NSRange(location: 0, length: inline.length))
        result.append(inline)
    }

    // MARK: - Code Blocks

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        let str = NSMutableAttributedString(string: codeBlock.code, attributes: Self.codeBlockAttributes)
        str.append(NSAttributedString(string: "\n"))
        result.append(str)
    }

    // MARK: - Block Quote

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        // Collect inner content with a recursive walker
        var inner = AttributedStringWalker()
        for child in blockQuote.children {
            inner.visit(child)
        }
        let rendered = inner.result

        // Apply blockquote foreground and paragraph style
        let full = NSMutableAttributedString(attributedString: rendered)
        let range = NSRange(location: 0, length: full.length)
        full.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        full.addAttribute(.paragraphStyle, value: Self.blockquoteParagraphStyle, range: range)

        result.append(full)
    }

    // MARK: - Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> () {
        isOrderedList[listDepth] = false
        listDepth += 1
        defer { listDepth -= 1 }
        for child in unorderedList.children { visit(child) }
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> () {
        isOrderedList[listDepth] = true
        orderedCounters[listDepth] = Int(orderedList.startIndex)
        listDepth += 1
        defer {
            listDepth -= 1
            orderedCounters.removeValue(forKey: listDepth)
        }
        for child in orderedList.children { visit(child) }
    }

    mutating func visitListItem(_ listItem: ListItem) -> () {
        let depth = listDepth - 1
        let bullet: String
        if isOrderedList[depth] == true {
            let counter = orderedCounters[depth] ?? 1
            bullet = "\(counter)."
            orderedCounters[depth] = counter + 1
        } else {
            bullet = depth % 2 == 0 ? "•" : "◦"
        }

        let indent = CGFloat(depth + 1) * 20
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 2
        ps.headIndent = indent + 18
        ps.firstLineHeadIndent = indent
        ps.tabStops = [NSTextTab(textAlignment: .left, location: indent + 18)]

        let prefix = NSAttributedString(string: "\(bullet)\t", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps,
        ])

        var inner = AttributedStringWalker()
        inner.listDepth = listDepth
        inner.orderedCounters = orderedCounters
        inner.isOrderedList = isOrderedList
        for child in listItem.children { inner.visit(child) }

        // Strip trailing newline from last child so list items space correctly
        let body = inner.result
        body.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: body.length))

        let item = NSMutableAttributedString()
        item.append(prefix)
        item.append(body)
        if !item.string.hasSuffix("\n") {
            item.append(NSAttributedString(string: "\n"))
        }
        result.append(item)
    }

    // MARK: - Thematic Break

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        // Render as a visible divider line using a special character trick
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 6),
            .foregroundColor: NSColor.separatorColor,
            .paragraphStyle: Self.bodyParagraphStyle,
        ]
        result.append(NSAttributedString(string: "\u{00A0}\n", attributes: attrs))
    }

    // MARK: - Fallback (other block-level nodes)

    mutating func defaultVisit(_ markup: any Markup) -> () {
        // For any unhandled block nodes, visit children
        for child in markup.children { visit(child) }
    }

    // MARK: - Inline Rendering

    /// Renders all inline children of a block element into a single mutable attributed string.
    private func renderInlineChildren(of markup: any Markup) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(renderInline(child, traits: []))
        }
        return out
    }

    private func renderInline(_ markup: any Markup, traits: NSFontDescriptor.SymbolicTraits) -> NSAttributedString {
        switch markup {
        case let text as Markdown.Text:
            return attributed(text.string, traits: traits)

        case let emphasis as Emphasis:
            var newTraits = traits
            newTraits.insert(.italic)
            return renderChildren(of: emphasis, traits: newTraits)

        case let strong as Strong:
            var newTraits = traits
            newTraits.insert(.bold)
            return renderChildren(of: strong, traits: newTraits)

        case let strikethrough as Strikethrough:
            let inner = renderChildren(of: strikethrough, traits: traits)
            let s = NSMutableAttributedString(attributedString: inner)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                           range: NSRange(location: 0, length: s.length))
            return s

        case let code as InlineCode:
            return NSAttributedString(string: code.code, attributes: Self.inlineCodeAttributes)

        case let link as Markdown.Link:
            let inner = renderChildren(of: link, traits: traits)
            let s = NSMutableAttributedString(attributedString: inner)
            let range = NSRange(location: 0, length: s.length)
            s.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            if let dest = link.destination, let url = URL(string: dest) {
                s.addAttribute(.link, value: url, range: range)
            }
            return s

        case _ as SoftBreak:
            return NSAttributedString(string: " ")

        case _ as LineBreak:
            return NSAttributedString(string: "\n")

        case let image as Markdown.Image:
            // Just show alt text for images
            return attributed(image.plainText.isEmpty ? "[image]" : "[\(image.plainText)]", traits: traits)

        default:
            // Recurse into unknown inline nodes
            return renderChildren(of: markup, traits: traits)
        }
    }

    private func renderChildren(of markup: any Markup, traits: NSFontDescriptor.SymbolicTraits) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(renderInline(child, traits: traits))
        }
        return out
    }

    // MARK: - Attribute Helpers

    private func attributed(_ string: String, traits: NSFontDescriptor.SymbolicTraits) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 13)
        let font: NSFont
        if traits.isEmpty {
            font = baseFont
        } else {
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: 13) ?? baseFont
        }
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
    }

    // MARK: - Paragraph Styles

    private static let bodyParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 6
        ps.lineSpacing = 2
        return ps
    }()

    private static let blockquoteParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 4
        ps.lineSpacing = 2
        ps.headIndent = 16
        ps.firstLineHeadIndent = 16
        return ps
    }()

    private static func headingParagraphStyle(level: Int) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = level <= 2 ? 10 : 6
        ps.paragraphSpacingBefore = level <= 2 ? 16 : 10
        return ps
    }

    // MARK: - Font Sizes

    private static func headingFontSize(level: Int) -> CGFloat {
        switch level {
        case 1: return 26
        case 2: return 22
        case 3: return 18
        case 4: return 15
        case 5: return 13
        default: return 12
        }
    }

    // MARK: - Code Attributes

    private static let inlineCodeAttributes: [NSAttributedString.Key: Any] = {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        return [
            .font: font,
            .foregroundColor: NSColor.systemTeal,
            .backgroundColor: NSColor.quaternaryLabelColor,
        ]
    }()

    private static let codeBlockAttributes: [NSAttributedString.Key: Any] = {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 6
        ps.headIndent = 12
        ps.firstLineHeadIndent = 12
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternarySystemFill,
            .paragraphStyle: ps,
        ]
    }()
}
