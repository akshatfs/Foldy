//
//  PreviewViewController.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Cocoa
import Quartz
import UniformTypeIdentifiers

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
    private var progressIndicator: NSProgressIndicator!
    private var errorLabel: NSTextField?
    private var rootItems: [PreviewItem] = []
    
    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    private lazy var byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
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
        setupLoadingView()
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
    
    private func setupLoadingView() {
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(progressIndicator)
        
        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Error UI
    
    private func showError(_ message: String) {
        // Hide the outline/scroll view so the user doesn't see a blank table
        scrollView.isHidden = true
        
        // Reuse or create the error label
        if errorLabel == nil {
            let label = NSTextField(wrappingLabelWithString: "")
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            
            view.addSubview(label)
            
            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
            
            errorLabel = label
        }
        
        errorLabel?.stringValue = message
        errorLabel?.isHidden = false
    }
    
    // MARK: - QLPreviewingController
    
    func preparePreviewOfFile(at url: URL) async throws {
        await MainActor.run {
            progressIndicator.startAnimation(nil)
            scrollView.isHidden = true
            errorLabel?.isHidden = true
        }
        
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let items: [PreviewItem]
            let archiveType = detectArchiveType(url: url)
            
            switch archiveType {
            case .zip:
                let entries = try ZipParser.parseEntries(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .tar:
                let entries = try TarParser.parseEntries(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .gzipTar:
                let entries = try GzipDecompressor.decompressAndParseTar(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .gzip:
                let entries = try GzipDecompressor.parseStandaloneGzip(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .rar:
                let entries = try RarParser.parseEntries(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .bz2Tar:
                let entries = try Bz2Parser.decompressAndParseTar(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .bz2:
                let entries = try Bz2Parser.parseStandaloneBz2(from: url)
                items = ArchiveTreeBuilder.buildTree(from: entries)
            case .folder:
                items = FileItem.loadChildren(of: url)
            }
            
            await MainActor.run {
                self.progressIndicator.stopAnimation(nil)
                self.rootItems = items
                self.scrollView.isHidden = false
                self.outlineView.reloadData()
            }
        } catch {
            await MainActor.run {
                self.progressIndicator.stopAnimation(nil)
                self.showError("Unable to preview this archive: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Archive Type Detection
    
    private enum ArchiveType {
        case zip, tar, gzipTar, gzip, rar, bz2, bz2Tar, folder
    }
    
    private func detectArchiveType(url: URL) -> ArchiveType {
        // Check compound extensions first so ".tar.gz" isn't mismatched on "gz" alone
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") {
            return .gzipTar
        }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") || name.hasSuffix(".tbz2") {
            return .bz2Tar
        }
        
        // Then check single extensions
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip":
            return .zip
        case "tar":
            return .tar
        case "tgz":
            return .gzipTar
        case "gz":
            return .gzip
        case "rar":
            return .rar
        case "bz2":
            return .bz2
        default:
            break
        }
        
        // Fall back to UTType
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: UTType.zip) { return .zip }
            if type.conforms(to: UTType.gzip) { return .gzipTar }
            if let bz2Type = UTType(filenameExtension: "bz2"), type.conforms(to: bz2Type) { return .bz2 }
        }
        
        return .folder
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        return byteCountFormatter.string(fromByteCount: bytes)
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
