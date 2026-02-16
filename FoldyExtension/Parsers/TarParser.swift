//
//  TarParser.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Foundation

// MARK: - Tar Archive Parser

struct TarParser {
    
    /// Parse tar headers and return all entries (does NOT decompress — expects raw tar data).
    static func parseEntries(from data: Data) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var offset = 0
        let blockSize = 512
        var longName: String? = nil
        
        while offset + blockSize <= data.count {
            let headerBlock = data[offset..<offset + blockSize]
            
            // Check for end-of-archive (two consecutive zero blocks)
            if headerBlock.allSatisfy({ $0 == 0 }) {
                break
            }
            
            // Read typeflag (offset 156, 1 byte)
            let typeflag = data[offset + 156]
            
            // Read file size (offset 124, 12 bytes, octal ASCII)
            let sizeStr = readOctalString(data, offset: offset + 124, length: 12)
            let fileSize = Int64(sizeStr, radix: 8) ?? 0
            
            // Handle GNU long name extension (typeflag 'L')
            if typeflag == 0x4C { // 'L'
                let nameDataSize = Int(fileSize)
                let nameStart = offset + blockSize
                let nameEnd = min(nameStart + nameDataSize, data.count)
                if nameEnd > nameStart {
                    let nameData = data[nameStart..<nameEnd]
                    longName = String(data: nameData, encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                }
                // Skip past data blocks
                let dataBlocks = (Int(fileSize) + blockSize - 1) / blockSize
                offset += blockSize + dataBlocks * blockSize
                continue
            }
            
            // Skip PAX extended headers (typeflags 'x', 'g') and GNU long link ('K')
            if typeflag == 0x78 || typeflag == 0x67 || typeflag == 0x4B {
                let dataBlocks = (Int(fileSize) + blockSize - 1) / blockSize
                offset += blockSize + dataBlocks * blockSize
                continue
            }
            
            // Read filename
            var fileName: String
            if let ln = longName {
                fileName = ln
                longName = nil
            } else {
                // USTAR: prefix at offset 345 (155 bytes) + name at offset 0 (100 bytes)
                let name = readString(data, offset: offset, length: 100)
                let prefix = readString(data, offset: offset + 345, length: 155)
                if !prefix.isEmpty {
                    fileName = prefix + "/" + name
                } else {
                    fileName = name
                }
            }
            
            guard !fileName.isEmpty else {
                // Skip past data blocks
                let dataBlocks = (Int(fileSize) + blockSize - 1) / blockSize
                offset += blockSize + dataBlocks * blockSize
                continue
            }
            
            // Determine if directory: typeflag '5' or trailing '/'
            let isDir = typeflag == 0x35 || fileName.hasSuffix("/") // '5'
            
            // Only include regular files ('0', '\0') and directories ('5')
            let isRegularFile = typeflag == 0x30 || typeflag == 0x00 // '0' or NUL
            if isRegularFile || isDir {
                // Read modification time (offset 136, 12 bytes, octal — unix timestamp)
                let mtimeStr = readOctalString(data, offset: offset + 136, length: 12)
                let mtime = Int64(mtimeStr, radix: 8) ?? 0
                let date = mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
                
                // Skip macOS metadata
                if !fileName.hasPrefix("._") && !fileName.contains("/._") {
                    entries.append(ArchiveEntry(
                        path: fileName,
                        isDirectory: isDir,
                        uncompressedSize: isDir ? 0 : fileSize,
                        modificationDate: date
                    ))
                }
            }
            
            // Advance past header + data blocks
            let dataBlocks = (Int(fileSize) + blockSize - 1) / blockSize
            offset += blockSize + dataBlocks * blockSize
        }
        
        return entries
    }
    
    /// Parse entries from a tar file on disk.
    static func parseEntries(from url: URL) throws -> [ArchiveEntry] {
        let data = try Data(contentsOf: url)
        return try parseEntries(from: data)
    }
    
    // MARK: - Helpers
    
    private static func readString(_ data: Data, offset: Int, length: Int) -> String {
        guard offset + length <= data.count else { return "" }
        let slice = data[offset..<offset + length]
        // Null-terminated ASCII
        if let nullIndex = slice.firstIndex(of: 0) {
            let trimmed = data[offset..<nullIndex]
            return String(data: trimmed, encoding: .utf8) ?? ""
        }
        return String(data: slice, encoding: .utf8) ?? ""
    }
    
    private static func readOctalString(_ data: Data, offset: Int, length: Int) -> String {
        return readString(data, offset: offset, length: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}
