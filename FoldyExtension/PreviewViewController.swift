//
//  PreviewViewController.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Cocoa
import Quartz

// MARK: - File Item Model

class FileItem: NSObject {
    let url: URL
    let name: String
    let isDirectory: Bool
    let icon: NSImage
    let dateModified: Date?
    let fileSize: Int64?
    var children: [FileItem]?
    
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
            self.children = FileItem.loadChildren(of: url)
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
    private var rootItems: [FileItem] = []
    
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
        
        let items = FileItem.loadChildren(of: url)
        
        await MainActor.run {
            self.rootItems = items
            self.outlineView.reloadData()
        }
    }
    
    // MARK: - Helpers
    
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
        guard let fileItem = item as? FileItem else { return 0 }
        return fileItem.children?.count ?? 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootItems[index]
        }
        guard let fileItem = item as? FileItem else { return NSObject() }
        return fileItem.children?[index] ?? NSObject()
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let fileItem = item as? FileItem else { return false }
        return fileItem.isDirectory && (fileItem.children?.isEmpty == false)
    }
}

// MARK: - NSOutlineViewDelegate

extension PreviewViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let fileItem = item as? FileItem,
              let columnID = tableColumn?.identifier else {
            return nil
        }
        
        switch columnID {
        case .nameColumn:
            return makeNameCell(for: fileItem, in: outlineView)
        case .dateColumn:
            return makeDateCell(for: fileItem, in: outlineView)
        case .sizeColumn:
            return makeSizeCell(for: fileItem, in: outlineView)
        default:
            return nil
        }
    }
    
    // MARK: - Cell Factories
    
    private func makeNameCell(for item: FileItem, in outlineView: NSOutlineView) -> NSTableCellView {
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
    
    private func makeDateCell(for item: FileItem, in outlineView: NSOutlineView) -> NSTableCellView {
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
    
    private func makeSizeCell(for item: FileItem, in outlineView: NSOutlineView) -> NSTableCellView {
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
