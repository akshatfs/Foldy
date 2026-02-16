//
//  PreviewItem.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Cocoa

// MARK: - Preview Item Protocol

protocol PreviewItem: AnyObject {
    var name: String { get }
    var isDirectory: Bool { get }
    var icon: NSImage { get }
    var dateModified: Date? { get }
    var fileSize: Int64? { get }
    var children: [PreviewItem]? { get }
}
