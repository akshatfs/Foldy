//
//  ZipParser.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Foundation

// MARK: - Zip Central Directory Parser

struct ZipParser {
    
    /// Parse the zip central directory and return all entries.
    static func parseEntries(from url: URL) throws -> [ArchiveEntry] {
        let data = try Data(contentsOf: url)
        guard let eocdOffset = findEOCD(in: data) else {
            throw NSError(domain: "ZipParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid zip file"])
        }
        
        // Read EOCD record
        let cdEntryCount = readUInt16(data, offset: eocdOffset + 10)
        let _ = readUInt32(data, offset: eocdOffset + 12) // cdSize
        let cdOffset = readUInt32(data, offset: eocdOffset + 16)
        
        // Check for Zip64 EOCD locator
        var actualCDOffset = UInt64(cdOffset)
        var actualEntryCount = UInt64(cdEntryCount)
        
        if cdOffset == 0xFFFFFFFF || cdEntryCount == 0xFFFF {
            // Try to find Zip64 EOCD locator (just before EOCD)
            if eocdOffset >= 20 {
                let locatorSig = readUInt32(data, offset: eocdOffset - 20)
                if locatorSig == 0x07064b50 {
                    let zip64EOCDOffset = readUInt64(data, offset: eocdOffset - 20 + 8)
                    let zip64Sig = readUInt32(data, offset: Int(zip64EOCDOffset))
                    if zip64Sig == 0x06064b50 {
                        actualEntryCount = readUInt64(data, offset: Int(zip64EOCDOffset) + 32)
                        actualCDOffset = readUInt64(data, offset: Int(zip64EOCDOffset) + 48)
                    }
                }
            }
        }
        
        var entries: [ArchiveEntry] = []
        var offset = Int(actualCDOffset)
        
        for _ in 0..<actualEntryCount {
            guard offset + 46 <= data.count else { break }
            
            let sig = readUInt32(data, offset: offset)
            guard sig == 0x02014b50 else { break } // Central directory file header signature
            
            let modTime = readUInt16(data, offset: offset + 12)
            let modDate = readUInt16(data, offset: offset + 14)
            var uncompressedSize = UInt64(readUInt32(data, offset: offset + 24))
            let fileNameLength = Int(readUInt16(data, offset: offset + 28))
            let extraFieldLength = Int(readUInt16(data, offset: offset + 30))
            let commentLength = Int(readUInt16(data, offset: offset + 32))
            
            guard offset + 46 + fileNameLength <= data.count else { break }
            
            let nameData = data[offset + 46 ..< offset + 46 + fileNameLength]
            let fileName = String(data: nameData, encoding: .utf8) ?? ""
            
            // Check for Zip64 extra field to get real uncompressed size
            if uncompressedSize == 0xFFFFFFFF {
                let extraStart = offset + 46 + fileNameLength
                let extraEnd = extraStart + extraFieldLength
                if extraEnd <= data.count {
                    uncompressedSize = findZip64UncompressedSize(
                        in: data, extraStart: extraStart, extraEnd: extraEnd
                    ) ?? uncompressedSize
                }
            }
            
            let isDir = fileName.hasSuffix("/")
            let date = dosDateTime(date: modDate, time: modTime)
            
            // Skip macOS metadata entries
            if !fileName.hasPrefix("__MACOSX/") && !fileName.isEmpty {
                entries.append(ArchiveEntry(
                    path: fileName,
                    isDirectory: isDir,
                    uncompressedSize: Int64(uncompressedSize),
                    modificationDate: date
                ))
            }
            
            offset += 46 + fileNameLength + extraFieldLength + commentLength
        }
        
        return entries
    }
    
    // MARK: - Binary Helpers
    
    /// Find the End of Central Directory record
    private static func findEOCD(in data: Data) -> Int? {
        // EOCD signature is 0x06054b50
        // Minimum EOCD size is 22 bytes, max comment is 65535
        let minOffset = max(0, data.count - 65557)
        for i in stride(from: data.count - 22, through: minOffset, by: -1) {
            if readUInt32(data, offset: i) == 0x06054b50 {
                return i
            }
        }
        return nil
    }
    
    /// Find Zip64 uncompressed size in an extra field
    private static func findZip64UncompressedSize(in data: Data, extraStart: Int, extraEnd: Int) -> UInt64? {
        var pos = extraStart
        while pos + 4 <= extraEnd {
            let headerID = readUInt16(data, offset: pos)
            let dataSize = Int(readUInt16(data, offset: pos + 2))
            if headerID == 0x0001 && pos + 4 + 8 <= extraEnd { // Zip64 extended info
                return readUInt64(data, offset: pos + 4)
            }
            pos += 4 + dataSize
        }
        return nil
    }
    
    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
             | (UInt32(data[offset + 1]) << 8)
             | (UInt32(data[offset + 2]) << 16)
             | (UInt32(data[offset + 3]) << 24)
    }
    
    private static func readUInt64(_ data: Data, offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        return UInt64(data[offset])
             | (UInt64(data[offset + 1]) << 8)
             | (UInt64(data[offset + 2]) << 16)
             | (UInt64(data[offset + 3]) << 24)
             | (UInt64(data[offset + 4]) << 32)
             | (UInt64(data[offset + 5]) << 40)
             | (UInt64(data[offset + 6]) << 48)
             | (UInt64(data[offset + 7]) << 56)
    }
    
    /// Convert DOS date/time to Foundation Date
    static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        var components = DateComponents()
        components.year = Int((date >> 9) & 0x7F) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int((time & 0x1F) * 2)
        return Calendar.current.date(from: components)
    }
}
