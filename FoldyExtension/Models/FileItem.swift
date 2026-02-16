//
//  FileItem.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Cocoa

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
