//
//  RarParser.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Foundation

// MARK: - RAR v4 Archive Parser

struct RarParser {
    
    /// RAR v4 signature: Rar!\x1a\x07\x00
    private static let rarV4Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    /// RAR v5 signature: Rar!\x1a\x07\x01\x00
    private static let rarV5Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    
    /// Parse RAR v4 archive headers and return all file entries.
    static func parseEntries(from url: URL) throws -> [ArchiveEntry] {
        let data = try Data(contentsOf: url)
        
        // Validate signature
        guard data.count >= 7 else {
            throw NSError(domain: "RarParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "File too small for RAR"])
        }
        
        // Check for RAR v4 or v5 signature
        let sigV4 = data.count >= 7 ? [UInt8](data[0..<7]) : []
        let sigV5 = data.count >= 8 ? [UInt8](data[0..<8]) : []
        
        let isV4 = sigV4 == rarV4Signature
        let isV5 = sigV5 == rarV5Signature
        
        guard isV4 || isV5 else {
            throw NSError(domain: "RarParser", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid RAR file"])
        }
        
        // RAR5 uses a completely different header format — for now we only parse v4
        guard isV4 else {
            throw NSError(domain: "RarParser", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "RAR v5 parsing not yet supported"])
        }
        
        var entries: [ArchiveEntry] = []
        var offset = 7 // Skip v4 signature
        
        while offset + 7 <= data.count {
            // Read block header: CRC(2) + TYPE(1) + FLAGS(2) + SIZE(2)
            let headType = data[offset + 2]
            let headFlags = readUInt16LE(data, offset: offset + 3)
            let headSize = Int(readUInt16LE(data, offset: offset + 5))
            
            guard headSize >= 7 else { break }
            guard offset + headSize <= data.count else { break }
            
            // Calculate total block size (header + optional ADD_SIZE for data)
            var addSize: Int = 0
            if headFlags & 0x8000 != 0 && offset + 11 <= data.count {
                addSize = Int(readUInt32LE(data, offset: offset + 7))
            }
            
            // End of archive marker
            if headType == 0x7B {
                break
            }
            
            // File header (0x74)
            if headType == 0x74 && headSize >= 32 {
                let entry = parseFileHeader(data: data, offset: offset, headFlags: headFlags, headSize: headSize)
                if let entry = entry {
                    entries.append(entry)
                }
                
                // For file headers, ADD_SIZE is the packed data size
                // PACK_SIZE is at offset+7 (4 bytes)
                var packSize = Int(readUInt32LE(data, offset: offset + 7))
                
                // 64-bit sizes
                if headFlags & 0x0100 != 0 {
                    let highPackSize = Int(readUInt32LE(data, offset: offset + headSize - 8))
                    packSize |= (highPackSize << 32)
                }
                
                offset += headSize + packSize
            } else {
                offset += headSize + addSize
            }
        }
        
        return entries
    }
    
    private static func parseFileHeader(data: Data, offset: Int, headFlags: UInt16, headSize: Int) -> ArchiveEntry? {
        // File header layout after the 7-byte common header:
        // PACK_SIZE(4) + UNP_SIZE(4) + HOST_OS(1) + FILE_CRC(4) + FTIME(4) + UNP_VER(1) + METHOD(1) + NAME_SIZE(2) + ATTR(4)
        // = 7 + 4+4+1+4+4+1+1+2+4 = 32 bytes minimum
        guard offset + 32 <= data.count else { return nil }
        
        var unpSize = Int64(readUInt32LE(data, offset: offset + 11))
        let ftime = readUInt32LE(data, offset: offset + 20)
        let nameSize = Int(readUInt16LE(data, offset: offset + 26))
        let attr = readUInt32LE(data, offset: offset + 28)
        
        // 64-bit sizes
        if headFlags & 0x0100 != 0 && offset + headSize >= offset + 36 {
            let highUnpSize = Int64(readUInt32LE(data, offset: offset + 36))
            unpSize |= (highUnpSize << 32)
        }
        
        // Read filename
        let nameStart = offset + 32
        guard nameStart + nameSize <= data.count else { return nil }
        let nameData = data[nameStart..<nameStart + nameSize]
        var fileName = String(data: nameData, encoding: .utf8)
            ?? String(data: nameData, encoding: .ascii) ?? ""
        
        // RAR uses backslash as path separator on Windows
        fileName = fileName.replacingOccurrences(of: "\\", with: "/")
        
        guard !fileName.isEmpty else { return nil }
        
        // Directory flag: check attribute bit 0x10 (MS-DOS directory attribute)
        // or if the entry has the directory flag in headFlags
        let isDir = (attr & 0x10) != 0 || (headFlags & 0x00E0) == 0x00E0 || fileName.hasSuffix("/")
        
        // Parse DOS date/time from FTIME
        let dosDate = UInt16((ftime >> 16) & 0xFFFF)
        let dosTime = UInt16(ftime & 0xFFFF)
        let date = ZipParser.dosDateTime(date: dosDate, time: dosTime)
        
        return ArchiveEntry(
            path: isDir && !fileName.hasSuffix("/") ? fileName + "/" : fileName,
            isDirectory: isDir,
            uncompressedSize: isDir ? 0 : unpSize,
            modificationDate: date
        )
    }
    
    // MARK: - Binary Helpers
    
    private static func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
             | (UInt32(data[offset + 1]) << 8)
             | (UInt32(data[offset + 2]) << 16)
             | (UInt32(data[offset + 3]) << 24)
    }
}
