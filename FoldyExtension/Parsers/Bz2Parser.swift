//
//  Bz2Parser.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Foundation
import bzip2_swift

struct Bz2Parser {
    
    enum Bz2Error: Error {
        case notBz2
        case decompressFailed
    }
    
    static func decompressAndParseTar(from url: URL) throws -> [ArchiveEntry] {
        let fileData = try Data(contentsOf: url)
        
        // Check for bzip2 magic bytes
        guard fileData.count >= 2, fileData[0] == 0x42, fileData[1] == 0x5A else {
            throw Bz2Error.notBz2
        }
        
        let decompressedData: Data
        do {
            decompressedData = try BZip2.decompress(fileData)
        } catch {
            throw Bz2Error.decompressFailed
        }
        
        return try TarParser.parseEntries(from: decompressedData)
    }
    
    static func parseStandaloneBz2(from url: URL) throws -> [ArchiveEntry] {
        let fileData = try Data(contentsOf: url)
        
        // Check for bzip2 magic bytes
        guard fileData.count >= 2, fileData[0] == 0x42, fileData[1] == 0x5A else {
            throw Bz2Error.notBz2
        }
        
        let decompressedData: Data
        do {
            decompressedData = try BZip2.decompress(fileData)
        } catch {
            throw Bz2Error.decompressFailed
        }
        
        let fileName = url.deletingPathExtension().lastPathComponent
        
        let entry = ArchiveEntry(
            path: fileName,
            isDirectory: false,
            uncompressedSize: Int64(decompressedData.count),
            modificationDate: nil // Bzip2 doesn't store modification dates in the header
        )
        
        return [entry]
    }
}
