//
//  RarParser.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Foundation

// MARK: - RAR Archive Parser (v4 + v5)

struct RarParser {
    
    /// RAR v4 signature: Rar!\x1a\x07\x00
    private static let rarV4Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    /// RAR v5 signature: Rar!\x1a\x07\x01\x00
    private static let rarV5Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    
    /// Parse RAR archive headers (v4 or v5) and return all file entries.
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
        
        if isV5 {
            return try parseV5Entries(from: data)
        }
        
        // --- RAR v4 parsing ---
        
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
                let entry = parseV4FileHeader(data: data, offset: offset, headFlags: headFlags, headSize: headSize)
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
    
    // MARK: - RAR v4 File Header
    
    private static func parseV4FileHeader(data: Data, offset: Int, headFlags: UInt16, headSize: Int) -> ArchiveEntry? {
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
    
    // MARK: - RAR v5 Parsing
    
    /// Parse RAR v5 archive blocks and return all file entries.
    private static func parseV5Entries(from data: Data) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var offset = 8 // Skip v5 signature (8 bytes)
        
        while offset < data.count {
            // Each v5 block starts with:
            //   Header CRC32  — uint32 (4 bytes)
            //   Header size   — vint (size of header after this field)
            //   Header type   — vint
            //   Header flags  — vint
            
            guard offset + 4 <= data.count else { break }
            
            // Skip Header CRC32
            let headerStart = offset + 4
            
            // Read header size (vint)
            let (headerSize, headerSizeBytes) = readVInt(data, offset: headerStart)
            guard headerSizeBytes > 0 else { break }
            
            let headerBodyStart = headerStart + headerSizeBytes
            let headerEnd = headerStart + headerSizeBytes + Int(headerSize)
            guard headerEnd <= data.count else { break }
            
            var pos = headerBodyStart
            
            // Read header type (vint)
            let (headerType, headerTypeBytes) = readVInt(data, offset: pos)
            guard headerTypeBytes > 0 else { break }
            pos += headerTypeBytes
            
            // Read header flags (vint)
            let (headerFlags, headerFlagsBytes) = readVInt(data, offset: pos)
            guard headerFlagsBytes > 0 else { break }
            pos += headerFlagsBytes
            
            let hasExtraArea = (headerFlags & 0x0001) != 0
            let hasDataArea  = (headerFlags & 0x0002) != 0
            
            // Read optional extra area size and data size
            var dataSize: UInt64 = 0
            
            if hasExtraArea {
                let (_, bytes) = readVInt(data, offset: pos)
                guard bytes > 0 else { break }
                pos += bytes
            }
            
            if hasDataArea {
                let (val, bytes) = readVInt(data, offset: pos)
                guard bytes > 0 else { break }
                dataSize = val
                pos += bytes
            }
            
            // End of archive (type 5) — stop parsing
            if headerType == 5 {
                break
            }
            
            // File header (type 2)
            if headerType == 2 {
                let entry = parseV5FileHeader(data: data, offset: pos, endOffset: headerEnd)
                if let entry = entry {
                    entries.append(entry)
                }
            }
            
            // Advance past this block: header CRC (4) + header size vint + header body + data area
            offset = headerEnd + Int(dataSize)
        }
        
        return entries
    }
    
    /// Parse a single RAR v5 file header starting at the file-specific fields.
    private static func parseV5FileHeader(data: Data, offset: Int, endOffset: Int) -> ArchiveEntry? {
        var pos = offset
        
        // File flags (vint)
        let (fileFlags, fileFlagsBytes) = readVInt(data, offset: pos)
        guard fileFlagsBytes > 0 else { return nil }
        pos += fileFlagsBytes
        
        let isDirectory = (fileFlags & 0x0001) != 0
        
        // Unpacked size (vint)
        let (unpSize, unpSizeBytes) = readVInt(data, offset: pos)
        guard unpSizeBytes > 0 else { return nil }
        pos += unpSizeBytes
        
        // Attributes (vint) — OS-specific file attributes
        let (_, attrBytes) = readVInt(data, offset: pos)
        guard attrBytes > 0 else { return nil }
        pos += attrBytes
        
        // mtime — uint32 Unix timestamp (if flag 0x0002 is set)
        var modDate: Date? = nil
        if (fileFlags & 0x0002) != 0 {
            guard pos + 4 <= data.count else { return nil }
            let timestamp = readUInt32LE(data, offset: pos)
            modDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
            pos += 4
        }
        
        // CRC32 — uint32 (if flag 0x0004 is set)
        if (fileFlags & 0x0004) != 0 {
            guard pos + 4 <= data.count else { return nil }
            pos += 4 // skip CRC32
        }
        
        // Compression information (vint)
        let (_, compBytes) = readVInt(data, offset: pos)
        guard compBytes > 0 else { return nil }
        pos += compBytes
        
        // Host OS (vint)
        let (_, hostOSBytes) = readVInt(data, offset: pos)
        guard hostOSBytes > 0 else { return nil }
        pos += hostOSBytes
        
        // Name length (vint)
        let (nameLength, nameLenBytes) = readVInt(data, offset: pos)
        guard nameLenBytes > 0 else { return nil }
        pos += nameLenBytes
        
        // File name — UTF-8 encoded, no trailing zero
        let nameLen = Int(nameLength)
        guard pos + nameLen <= data.count else { return nil }
        let nameData = data[pos..<pos + nameLen]
        var fileName = String(data: nameData, encoding: .utf8) ?? ""
        
        // Normalize path separators (forward slash is standard in v5,
        // but handle backslashes just in case for Windows-created archives)
        fileName = fileName.replacingOccurrences(of: "\\", with: "/")
        
        guard !fileName.isEmpty else { return nil }
        
        return ArchiveEntry(
            path: isDirectory && !fileName.hasSuffix("/") ? fileName + "/" : fileName,
            isDirectory: isDirectory,
            uncompressedSize: isDirectory ? 0 : Int64(unpSize),
            modificationDate: modDate
        )
    }
    
    // MARK: - Binary Helpers
    
    /// Read a RAR v5 variable-length integer (vint).
    /// Returns (value, bytesConsumed). bytesConsumed == 0 indicates a read error.
    private static func readVInt(_ data: Data, offset: Int) -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift = 0
        var pos = offset
        
        // vint can be at most 10 bytes (64-bit value stored in 7-bit chunks)
        let maxBytes = min(10, data.count - offset)
        guard maxBytes > 0 else { return (0, 0) }
        
        for i in 0..<maxBytes {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1
            shift += 7
            
            // If the continuation bit (MSB) is not set, this is the last byte
            if byte & 0x80 == 0 {
                return (result, i + 1)
            }
        }
        
        // If we consumed 10 bytes and the last one still had continuation set,
        // treat it as valid (max vint length reached)
        return (result, maxBytes)
    }
    
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
