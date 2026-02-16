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
    /// Uses FileHandle to stream block headers and seek past packed data.
    static func parseEntries(from url: URL) throws -> [ArchiveEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        
        let fileSize = handle.seekToEndOfFile()
        handle.seek(toFileOffset: 0)
        
        // Read signature (8 bytes covers both v4=7 and v5=8)
        guard fileSize >= 7 else {
            throw NSError(domain: "RarParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "File too small for RAR"])
        }
        
        let sigData = handle.readData(ofLength: 8)
        let sigV4 = sigData.count >= 7 ? [UInt8](sigData[0..<7]) : []
        let sigV5 = sigData.count >= 8 ? [UInt8](sigData[0..<8]) : []
        
        let isV4 = sigV4 == rarV4Signature
        let isV5 = sigV5 == rarV5Signature
        
        guard isV4 || isV5 else {
            throw NSError(domain: "RarParser", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid RAR file"])
        }
        
        if isV5 {
            return try parseV5Entries(handle: handle, fileSize: fileSize)
        }
        
        return try parseV4Entries(handle: handle, fileSize: fileSize)
    }
    
    // MARK: - RAR v4 Parsing
    
    private static func parseV4Entries(handle: FileHandle, fileSize: UInt64) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var position: UInt64 = 7 // Skip v4 signature
        
        while position + 7 <= fileSize {
            // Read 7-byte common block header: CRC(2) + TYPE(1) + FLAGS(2) + SIZE(2)
            handle.seek(toFileOffset: position)
            let commonHeader = handle.readData(ofLength: 7)
            guard commonHeader.count == 7 else { break }
            
            let headType = commonHeader[2]
            let headFlags = readUInt16LE(commonHeader, offset: 3)
            let headSize = Int(readUInt16LE(commonHeader, offset: 5))
            
            guard headSize >= 7 else { break }
            guard position + UInt64(headSize) <= fileSize else { break }
            
            // End of archive marker
            if headType == 0x7B {
                break
            }
            
            // For non-file blocks, calculate ADD_SIZE if the flag is set
            var addSize: UInt64 = 0
            if headFlags & 0x8000 != 0 && headSize >= 11 {
                // Read the full header to get ADD_SIZE at offset 7
                handle.seek(toFileOffset: position)
                let fullHeader = handle.readData(ofLength: min(headSize, 32))
                if fullHeader.count >= 11 {
                    addSize = UInt64(readUInt32LE(fullHeader, offset: 7))
                }
            }
            
            // File header (0x74)
            if headType == 0x74 && headSize >= 32 {
                // Read the full file header
                handle.seek(toFileOffset: position)
                let headerData = handle.readData(ofLength: headSize)
                guard headerData.count == headSize else { break }
                
                let entry = parseV4FileHeader(data: headerData, headFlags: headFlags, headSize: headSize)
                if let entry = entry {
                    entries.append(entry)
                }
                
                // PACK_SIZE is at offset 7 (4 bytes) in the header
                var packSize = UInt64(readUInt32LE(headerData, offset: 7))
                
                // 64-bit sizes
                if headFlags & 0x0100 != 0 && headSize >= 36 {
                    let highPackSize = UInt64(readUInt32LE(headerData, offset: headSize - 8))
                    packSize |= (highPackSize << 32)
                }
                
                // Seek past header + packed data
                position += UInt64(headSize) + packSize
            } else {
                // Non-file block: skip header + ADD_SIZE
                position += UInt64(headSize) + addSize
            }
        }
        
        return entries
    }
    
    // MARK: - RAR v4 File Header
    
    private static func parseV4FileHeader(data: Data, headFlags: UInt16, headSize: Int) -> ArchiveEntry? {
        // File header layout after the 7-byte common header:
        // PACK_SIZE(4) + UNP_SIZE(4) + HOST_OS(1) + FILE_CRC(4) + FTIME(4) + UNP_VER(1) + METHOD(1) + NAME_SIZE(2) + ATTR(4)
        // = 7 + 4+4+1+4+4+1+1+2+4 = 32 bytes minimum
        guard data.count >= 32 else { return nil }
        
        var unpSize = Int64(readUInt32LE(data, offset: 11))
        let ftime = readUInt32LE(data, offset: 20)
        let nameSize = Int(readUInt16LE(data, offset: 26))
        let attr = readUInt32LE(data, offset: 28)
        
        // 64-bit sizes
        if headFlags & 0x0100 != 0 && headSize >= 36 && data.count >= 40 {
            let highUnpSize = Int64(readUInt32LE(data, offset: 36))
            unpSize |= (highUnpSize << 32)
        }
        
        // Read filename
        let nameStart = 32
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
    
    /// Parse RAR v5 archive blocks using FileHandle, seeking past data areas.
    private static func parseV5Entries(handle: FileHandle, fileSize: UInt64) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var position: UInt64 = 8 // Skip v5 signature (8 bytes)
        
        while position < fileSize {
            // Each v5 block starts with:
            //   Header CRC32  — uint32 (4 bytes)
            //   Header size   — vint (size of header after this field)
            //   Header type   — vint
            //   Header flags  — vint
            
            guard position + 4 <= fileSize else { break }
            
            // Read header CRC + some extra bytes for vints
            // We need at least 4 (CRC) + up to ~30 bytes for vints
            handle.seek(toFileOffset: position)
            let peekSize = min(Int(fileSize - position), 64)
            let peekData = handle.readData(ofLength: peekSize)
            guard peekData.count >= 5 else { break }
            
            // Skip Header CRC32
            let headerStart = 4
            
            // Read header size (vint)
            let (headerSize, headerSizeBytes) = readVInt(peekData, offset: headerStart)
            guard headerSizeBytes > 0 else { break }
            
            let headerBodyStart = headerStart + headerSizeBytes
            let totalHeaderLen = 4 + headerSizeBytes + Int(headerSize)
            
            guard position + UInt64(totalHeaderLen) <= fileSize else { break }
            
            // If the peek wasn't big enough for the full header, read the full header
            let headerData: Data
            if totalHeaderLen <= peekData.count {
                headerData = peekData
            } else {
                handle.seek(toFileOffset: position)
                headerData = handle.readData(ofLength: totalHeaderLen)
                guard headerData.count == totalHeaderLen else { break }
            }
            
            var pos = headerBodyStart
            
            // Read header type (vint)
            let (headerType, headerTypeBytes) = readVInt(headerData, offset: pos)
            guard headerTypeBytes > 0 else { break }
            pos += headerTypeBytes
            
            // Read header flags (vint)
            let (headerFlags, headerFlagsBytes) = readVInt(headerData, offset: pos)
            guard headerFlagsBytes > 0 else { break }
            pos += headerFlagsBytes
            
            let hasExtraArea = (headerFlags & 0x0001) != 0
            let hasDataArea  = (headerFlags & 0x0002) != 0
            
            // Read optional extra area size and data size
            var dataSize: UInt64 = 0
            
            if hasExtraArea {
                let (_, bytes) = readVInt(headerData, offset: pos)
                guard bytes > 0 else { break }
                pos += bytes
            }
            
            if hasDataArea {
                let (val, bytes) = readVInt(headerData, offset: pos)
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
                let headerEnd = 4 + headerSizeBytes + Int(headerSize)
                let entry = parseV5FileHeader(data: headerData, offset: pos, endOffset: headerEnd)
                if let entry = entry {
                    entries.append(entry)
                }
            }
            
            // Advance past this block: full header + data area
            position += UInt64(totalHeaderLen) + dataSize
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
        
        // Normalize path separators
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
