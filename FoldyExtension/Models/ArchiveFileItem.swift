//
//  ArchiveFileItem.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - Archive File Item Model (entries inside any archive)

class ArchiveFileItem: NSObject, PreviewItem {
    let name: String
    let isDirectory: Bool
    let icon: NSImage
    let dateModified: Date?
    let fileSize: Int64?
    var _children: [ArchiveFileItem]?
    
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

// MARK: - Shared Archive Entry & Tree Builder

struct ArchiveEntry {
    let path: String
    let isDirectory: Bool
    let uncompressedSize: Int64
    let modificationDate: Date?
}

struct ArchiveTreeBuilder {
    /// Build a tree of ArchiveFileItem from flat entries
    static func buildTree(from entries: [ArchiveEntry]) -> [ArchiveFileItem] {
        let root = ArchiveFileItem(name: "", isDirectory: true, fileSize: nil, dateModified: nil)
        root._children = []
        
        // Map of path -> ArchiveFileItem for quick lookups
        var nodeMap: [String: ArchiveFileItem] = ["": root]
        
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
                    let item = ArchiveFileItem(
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
}
