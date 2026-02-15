//
//  PreviewViewController.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Cocoa
import Quartz
import UniformTypeIdentifiers

// MARK: - Preview Item Protocol

protocol PreviewItem: AnyObject {
    var name: String { get }
    var isDirectory: Bool { get }
    var icon: NSImage { get }
    var dateModified: Date? { get }
    var fileSize: Int64? { get }
    var children: [PreviewItem]? { get }
}

// MARK: - File Item Model (folders on disk)

class FileItem: NSObject, PreviewItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    let icon: NSImage
    let dateModified: Date?
    let fileSize: Int64?
    var _children: [FileItem]?
    
    var children: [PreviewItem]? {
        return _children
    }
    
    init(url: URL) {
        self.url = url
        
        let resourceValues = try? url.resourceValues(forKeys: [
            .nameKey, .isDirectoryKey, .contentModificationDateKey,
            .fileSizeKey, .totalFileSizeKey
        ])
        
        self.name = resourceValues?.name ?? url.lastPathComponent
        self.isDirectory = resourceValues?.isDirectory ?? false
        self.dateModified = resourceValues?.contentModificationDate
        self.fileSize = resourceValues?.fileSize.map { Int64($0) }
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon.size = NSSize(width: 16, height: 16)
        
        if self.isDirectory {
            self._children = FileItem.loadChildren(of: url)
        }
        
        super.init()
    }
    
    static func loadChildren(of url: URL) -> [FileItem] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .nameKey, .isDirectoryKey, .contentModificationDateKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        let items = contents.map { FileItem(url: $0) }
        
        // Sort: folders first, then files, alphabetically within each group
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - Zip File Item Model (entries inside a zip archive)

class ZipFileItem: NSObject, PreviewItem {
    let name: String
    let isDirectory: Bool
    let icon: NSImage
    let dateModified: Date?
    let fileSize: Int64?
    var _children: [ZipFileItem]?
    
    var children: [PreviewItem]? {
        return _children
    }
    
    init(name: String, isDirectory: Bool, fileSize: Int64?, dateModified: Date?) {
        self.name = name
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.dateModified = dateModified
        
        if isDirectory {
            self.icon = NSWorkspace.shared.icon(for: UTType.folder)
        } else {
            // Determine icon from file extension
            let ext = (name as NSString).pathExtension
            if ext.isEmpty {
                self.icon = NSWorkspace.shared.icon(for: UTType.data)
            } else if let type = UTType(filenameExtension: ext) {
                self.icon = NSWorkspace.shared.icon(for: type)
            } else {
                self.icon = NSWorkspace.shared.icon(for: UTType.data)
            }
        }
        self.icon.size = NSSize(width: 16, height: 16)
        
        super.init()
    }
    
    /// Sort children: folders first, then alphabetically
    func sortChildren() {
        _children?.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        _children?.forEach { $0.sortChildren() }
    }
}

// MARK: - Zip Central Directory Parser

struct ZipParser {
    
    struct Entry {
        let path: String
        let isDirectory: Bool
        let uncompressedSize: Int64
        let modificationDate: Date?
    }
    
    /// Parse the zip central directory and return all entries.
    static func parseEntries(from url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        guard let eocdOffset = findEOCD(in: data) else {
            throw NSError(domain: "ZipParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid zip file"])
        }
        
        // Read EOCD record
        let cdEntryCount = readUInt16(data, offset: eocdOffset + 10)
        let _ = readUInt32(data, offset: eocdOffset + 12) // cdSize
        let cdOffset = readUInt32(data, offset: eocdOffset + 16)
        
        // Check for Zip64 EOCD locator
        var actualCDOffset = UInt64(cdOffset)
        var actualEntryCount = UInt64(cdEntryCount)
        
        if cdOffset == 0xFFFFFFFF || cdEntryCount == 0xFFFF {
            // Try to find Zip64 EOCD locator (just before EOCD)
            if eocdOffset >= 20 {
                let locatorSig = readUInt32(data, offset: eocdOffset - 20)
                if locatorSig == 0x07064b50 {
                    let zip64EOCDOffset = readUInt64(data, offset: eocdOffset - 20 + 8)
                    let zip64Sig = readUInt32(data, offset: Int(zip64EOCDOffset))
                    if zip64Sig == 0x06064b50 {
                        actualEntryCount = readUInt64(data, offset: Int(zip64EOCDOffset) + 32)
                        actualCDOffset = readUInt64(data, offset: Int(zip64EOCDOffset) + 48)
                    }
                }
            }
        }
        
        var entries: [Entry] = []
        var offset = Int(actualCDOffset)
        
        for _ in 0..<actualEntryCount {
            guard offset + 46 <= data.count else { break }
            
            let sig = readUInt32(data, offset: offset)
            guard sig == 0x02014b50 else { break } // Central directory file header signature
            
            let modTime = readUInt16(data, offset: offset + 12)
            let modDate = readUInt16(data, offset: offset + 14)
            var uncompressedSize = UInt64(readUInt32(data, offset: offset + 24))
            let fileNameLength = Int(readUInt16(data, offset: offset + 28))
            let extraFieldLength = Int(readUInt16(data, offset: offset + 30))
            let commentLength = Int(readUInt16(data, offset: offset + 32))
            
            guard offset + 46 + fileNameLength <= data.count else { break }
            
            let nameData = data[offset + 46 ..< offset + 46 + fileNameLength]
            let fileName = String(data: nameData, encoding: .utf8) ?? ""
            
            // Check for Zip64 extra field to get real uncompressed size
            if uncompressedSize == 0xFFFFFFFF {
                let extraStart = offset + 46 + fileNameLength
                let extraEnd = extraStart + extraFieldLength
                if extraEnd <= data.count {
                    uncompressedSize = findZip64UncompressedSize(
                        in: data, extraStart: extraStart, extraEnd: extraEnd
                    ) ?? uncompressedSize
                }
            }
            
            let isDir = fileName.hasSuffix("/")
            let date = dosDateTime(date: modDate, time: modTime)
            
            // Skip macOS metadata entries
            if !fileName.hasPrefix("__MACOSX/") && !fileName.isEmpty {
                entries.append(Entry(
                    path: fileName,
                    isDirectory: isDir,
                    uncompressedSize: Int64(uncompressedSize),
                    modificationDate: date
                ))
            }
            
            offset += 46 + fileNameLength + extraFieldLength + commentLength
        }
        
        return entries
    }
    
    /// Build a tree of ZipFileItem from flat entries
    static func buildTree(from entries: [Entry]) -> [ZipFileItem] {
        let root = ZipFileItem(name: "", isDirectory: true, fileSize: nil, dateModified: nil)
        root._children = []
        
        // Map of path -> ZipFileItem for quick lookups
        var nodeMap: [String: ZipFileItem] = ["": root]
        
        for entry in entries {
            let path = entry.isDirectory ? String(entry.path.dropLast()) : entry.path
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard !components.isEmpty else { continue }
            
            // Ensure all parent directories exist
            var currentPath = ""
            var parentNode = root
            
            for (index, component) in components.enumerated() {
                let isLast = index == components.count - 1
                let partPath = currentPath.isEmpty
                    ? String(component)
                    : currentPath + "/" + String(component)
                
                if let existing = nodeMap[partPath] {
                    parentNode = existing
                } else {
                    let isDir = isLast ? entry.isDirectory : true
                    let item = ZipFileItem(
                        name: String(component),
                        isDirectory: isDir,
                        fileSize: (isLast && !entry.isDirectory) ? entry.uncompressedSize : nil,
                        dateModified: isLast ? entry.modificationDate : nil
                    )
                    
                    if parentNode._children == nil {
                        parentNode._children = []
                    }
                    parentNode._children?.append(item)
                    nodeMap[partPath] = item
                    parentNode = item
                }
                
                currentPath = partPath
            }
        }
        
        root.sortChildren()
        return root._children ?? []
    }
    
    // MARK: - Binary Helpers
    
    /// Find the End of Central Directory record
    private static func findEOCD(in data: Data) -> Int? {
        // EOCD signature is 0x06054b50
        // Minimum EOCD size is 22 bytes, max comment is 65535
        let minOffset = max(0, data.count - 65557)
        for i in stride(from: data.count - 22, through: minOffset, by: -1) {
            if readUInt32(data, offset: i) == 0x06054b50 {
                return i
            }
        }
        return nil
    }
    
    /// Find Zip64 uncompressed size in an extra field
    private static func findZip64UncompressedSize(in data: Data, extraStart: Int, extraEnd: Int) -> UInt64? {
        var pos = extraStart
        while pos + 4 <= extraEnd {
            let headerID = readUInt16(data, offset: pos)
            let dataSize = Int(readUInt16(data, offset: pos + 2))
            if headerID == 0x0001 && pos + 4 + 8 <= extraEnd { // Zip64 extended info
                return readUInt64(data, offset: pos + 4)
            }
            pos += 4 + dataSize
        }
        return nil
    }
    
    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
             | (UInt32(data[offset + 1]) << 8)
             | (UInt32(data[offset + 2]) << 16)
             | (UInt32(data[offset + 3]) << 24)
    }
    
    private static func readUInt64(_ data: Data, offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        return UInt64(data[offset])
             | (UInt64(data[offset + 1]) << 8)
             | (UInt64(data[offset + 2]) << 16)
             | (UInt64(data[offset + 3]) << 24)
             | (UInt64(data[offset + 4]) << 32)
             | (UInt64(data[offset + 5]) << 40)
             | (UInt64(data[offset + 6]) << 48)
             | (UInt64(data[offset + 7]) << 56)
    }
    
    /// Convert DOS date/time to Foundation Date
    private static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        var components = DateComponents()
        components.year = Int((date >> 9) & 0x7F) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int((time & 0x1F) * 2)
        return Calendar.current.date(from: components)
    }
}

// MARK: - Column Identifiers

extension NSUserInterfaceItemIdentifier {
    static let nameColumn = NSUserInterfaceItemIdentifier("NameColumn")
    static let dateColumn = NSUserInterfaceItemIdentifier("DateColumn")
    static let sizeColumn = NSUserInterfaceItemIdentifier("SizeColumn")
}

// MARK: - Preview View Controller

class PreviewViewController: NSViewController, QLPreviewingController {
    
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var rootItems: [PreviewItem] = []
    
    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    override var nibName: NSNib.Name? {
        return nil
    }
    
    override func loadView() {
        self.view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupOutlineView()
    }
    
    // MARK: - Setup
    
    private func setupOutlineView() {
        // Create the outline view
        outlineView = NSOutlineView()
        outlineView.headerView = NSTableHeaderView()
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 18
        outlineView.autoresizesOutlineColumn = true
        outlineView.style = .automatic
        
        // Name column
        let nameColumn = NSTableColumn(identifier: .nameColumn)
        nameColumn.title = "Name"
        nameColumn.width = 300
        nameColumn.minWidth = 150
        nameColumn.resizingMask = .userResizingMask
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn
        
        // Date Modified column
        let dateColumn = NSTableColumn(identifier: .dateColumn)
        dateColumn.title = "Date Modified"
        dateColumn.width = 180
        dateColumn.minWidth = 100
        dateColumn.resizingMask = .userResizingMask
        outlineView.addTableColumn(dateColumn)
        
        // Size column
        let sizeColumn = NSTableColumn(identifier: .sizeColumn)
        sizeColumn.title = "Size"
        sizeColumn.width = 80
        sizeColumn.minWidth = 60
        sizeColumn.resizingMask = .userResizingMask
        outlineView.addTableColumn(sizeColumn)
        
        // Set delegates
        outlineView.dataSource = self
        outlineView.delegate = self
        
        // Wrap in scroll view
        scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    // MARK: - QLPreviewingController
    
    func preparePreviewOfFile(at url: URL) async throws {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        let items: [PreviewItem]
        
        if isZipFile(url: url) {
            let entries = try ZipParser.parseEntries(from: url)
            items = ZipParser.buildTree(from: entries)
        } else {
            items = FileItem.loadChildren(of: url)
        }
        
        await MainActor.run {
            self.rootItems = items
            self.outlineView.reloadData()
        }
    }
    
    // MARK: - Helpers
    
    private func isZipFile(url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: UTType.zip)
        }
        return url.pathExtension.lowercased() == "zip"
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - NSOutlineViewDataSource

extension PreviewViewController: NSOutlineViewDataSource {
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootItems.count
        }
        guard let previewItem = item as? PreviewItem else { return 0 }
        return previewItem.children?.count ?? 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootItems[index]
        }
        guard let previewItem = item as? PreviewItem else { return NSObject() }
        return previewItem.children?[index] ?? NSObject()
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let previewItem = item as? PreviewItem else { return false }
        return previewItem.isDirectory && (previewItem.children?.isEmpty == false)
    }
}

// MARK: - NSOutlineViewDelegate

extension PreviewViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let previewItem = item as? PreviewItem,
              let columnID = tableColumn?.identifier else {
            return nil
        }
        
        switch columnID {
        case .nameColumn:
            return makeNameCell(for: previewItem, in: outlineView)
        case .dateColumn:
            return makeDateCell(for: previewItem, in: outlineView)
        case .sizeColumn:
            return makeSizeCell(for: previewItem, in: outlineView)
        default:
            return nil
        }
    }
    
    // MARK: - Cell Factories
    
    private func makeNameCell(for item: PreviewItem, in outlineView: NSOutlineView) -> NSTableCellView {
        let cellID = NSUserInterfaceItemIdentifier("NameCell")
        let cell: NSTableCellView
        
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 13)
            textField.lineBreakMode = .byTruncatingTail
            
            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.imageView = imageView
            cell.textField = textField
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        
        cell.imageView?.image = item.icon
        cell.textField?.stringValue = item.name
        
        return cell
    }
    
    private func makeDateCell(for item: PreviewItem, in outlineView: NSOutlineView) -> NSTableCellView {
        let cellID = NSUserInterfaceItemIdentifier("DateCell")
        let cell: NSTableCellView
        
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.textColor = .secondaryLabelColor
            textField.lineBreakMode = .byTruncatingTail
            
            cell.addSubview(textField)
            cell.textField = textField
            
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        
        if let date = item.dateModified {
            cell.textField?.stringValue = dateFormatter.string(from: date)
        } else {
            cell.textField?.stringValue = "--"
        }
        
        return cell
    }
    
    private func makeSizeCell(for item: PreviewItem, in outlineView: NSOutlineView) -> NSTableCellView {
        let cellID = NSUserInterfaceItemIdentifier("SizeCell")
        let cell: NSTableCellView
        
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.textColor = .secondaryLabelColor
            textField.lineBreakMode = .byTruncatingTail
            textField.alignment = .right
            
            cell.addSubview(textField)
            cell.textField = textField
            
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        
        if item.isDirectory {
            let count = item.children?.count ?? 0
            cell.textField?.stringValue = count == 1 ? "1 item" : "\(count) items"
        } else if let size = item.fileSize {
            cell.textField?.stringValue = formatFileSize(size)
        } else {
            cell.textField?.stringValue = "--"
        }
        
        return cell
    }
}
