//
//  GzipDecompressor.swift
//  FoldyExtension
//
//  Created by Akshat Shukla on 15/02/26.
//

import Foundation
import Compression

// MARK: - Gzip Decompressor

struct GzipDecompressor {
    
    enum GzipError: Error {
        case notGzip
        case decompressFailed
    }
    
    /// Decompress a gzip file and parse the inner tar archive in a single streaming pass.
    /// Never loads the entire compressed or decompressed file into memory.
    /// Peak memory: ~128 KB (input + output buffers).
    static func decompressAndParseTar(from url: URL) throws -> [ArchiveEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        
        // Read and validate gzip header (at least 10 bytes)
        let header = handle.readData(ofLength: 10)
        guard header.count >= 10,
              header[0] == 0x1F, header[1] == 0x8B else {
            throw GzipError.notGzip
        }
        
        // Skip gzip header fields
        var offset: UInt64 = 10
        let flags = header[3]
        
        // FEXTRA
        if flags & 0x04 != 0 {
            handle.seek(toFileOffset: offset)
            let extraLenData = handle.readData(ofLength: 2)
            guard extraLenData.count == 2 else { throw GzipError.notGzip }
            let extraLen = Int(extraLenData[0]) | (Int(extraLenData[1]) << 8)
            offset += 2 + UInt64(extraLen)
        }
        // FNAME
        if flags & 0x08 != 0 {
            handle.seek(toFileOffset: offset)
            while true {
                let byte = handle.readData(ofLength: 1)
                guard byte.count == 1 else { throw GzipError.notGzip }
                offset += 1
                if byte[0] == 0 { break }
            }
        }
        // FCOMMENT
        if flags & 0x10 != 0 {
            handle.seek(toFileOffset: offset)
            while true {
                let byte = handle.readData(ofLength: 1)
                guard byte.count == 1 else { throw GzipError.notGzip }
                offset += 1
                if byte[0] == 0 { break }
            }
        }
        // FHCRC
        if flags & 0x02 != 0 {
            offset += 2
        }
        
        // Position at the start of the DEFLATE stream
        handle.seek(toFileOffset: offset)
        
        // Set up streaming decompression
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        
        let initStatus = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else { throw GzipError.decompressFailed }
        defer { compression_stream_destroy(streamPtr) }
        
        let inputChunkSize = 65536  // 64 KB input
        let outputChunkSize = 65536 // 64 KB output
        let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputChunkSize)
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputChunkSize)
        defer {
            inputBuffer.deallocate()
            outputBuffer.deallocate()
        }
        
        // Tar streaming state
        let tarBlockSize = 512
        var tarBuffer = Data() // Accumulates decompressed bytes until we have a full tar block
        var entries: [ArchiveEntry] = []
        var tarOffset: Int64 = 0 // Current position in the decompressed tar stream
        var skipUntil: Int64 = 0 // Skip data blocks — we only want headers
        var longName: String? = nil
        var finished = false
        
        // Read compressed data in chunks
        streamPtr.pointee.src_size = 0
        
        while !finished {
            // Refill input buffer if needed
            if streamPtr.pointee.src_size == 0 {
                let inputData = handle.readData(ofLength: inputChunkSize)
                if inputData.count == 0 {
                    // No more input — do a final flush
                    finished = true
                } else {
                    inputData.copyBytes(to: inputBuffer, count: inputData.count)
                    streamPtr.pointee.src_ptr = UnsafePointer(inputBuffer)
                    streamPtr.pointee.src_size = inputData.count
                }
            }
            
            streamPtr.pointee.dst_ptr = outputBuffer
            streamPtr.pointee.dst_size = outputChunkSize
            
            let flags: Int32 = finished ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(streamPtr, flags)
            
            let bytesWritten = outputChunkSize - streamPtr.pointee.dst_size
            if bytesWritten > 0 {
                let decompressedChunk = Data(bytes: outputBuffer, count: bytesWritten)
                
                // Feed decompressed bytes into inline tar parser
                var chunkOffset = 0
                while chunkOffset < decompressedChunk.count {
                    let currentTarPos = tarOffset + Int64(tarBuffer.count)
                    
                    // If we're skipping data blocks, just advance
                    if currentTarPos < skipUntil {
                        let bytesToSkip = min(
                            Int(skipUntil - currentTarPos),
                            decompressedChunk.count - chunkOffset
                        )
                        chunkOffset += bytesToSkip
                        tarOffset += Int64(bytesToSkip)
                        continue
                    }
                    
                    // Accumulate bytes until we have a full tar block (512 bytes)
                    let bytesNeeded = tarBlockSize - tarBuffer.count
                    let bytesAvailable = decompressedChunk.count - chunkOffset
                    let bytesToCopy = min(bytesNeeded, bytesAvailable)
                    
                    tarBuffer.append(decompressedChunk[chunkOffset..<chunkOffset + bytesToCopy])
                    chunkOffset += bytesToCopy
                    
                    if tarBuffer.count == tarBlockSize {
                        // We have a complete tar header block
                        let result = parseTarHeaderBlock(tarBuffer, longName: &longName)
                        
                        switch result {
                        case .entry(let entry, let dataSize):
                            entries.append(entry)
                            // Skip past data blocks
                            let dataBlocks = (dataSize + Int64(tarBlockSize) - 1) / Int64(tarBlockSize)
                            tarOffset += Int64(tarBlockSize)
                            skipUntil = tarOffset + dataBlocks * Int64(tarBlockSize)
                            
                        case .longName(let dataSize):
                            // Need to read the long name data — accumulate it
                            tarOffset += Int64(tarBlockSize)
                            // For long names, we already set longName in the parser
                            // We need to read nameDataSize bytes
                            let dataBlocks = (dataSize + Int64(tarBlockSize) - 1) / Int64(tarBlockSize)
                            skipUntil = tarOffset + dataBlocks * Int64(tarBlockSize)
                            
                        case .skip(let dataSize):
                            let dataBlocks = (dataSize + Int64(tarBlockSize) - 1) / Int64(tarBlockSize)
                            tarOffset += Int64(tarBlockSize)
                            skipUntil = tarOffset + dataBlocks * Int64(tarBlockSize)
                            
                        case .end:
                            finished = true
                            
                        case .continueReading:
                            tarOffset += Int64(tarBlockSize)
                        }
                        
                        tarBuffer = Data()
                    }
                }
            }
            
            if status == COMPRESSION_STATUS_END {
                finished = true
            } else if status == COMPRESSION_STATUS_ERROR {
                throw GzipError.decompressFailed
            }
        }
        
        return entries
    }
    
    // MARK: - Inline Tar Header Parser
    
    private enum TarHeaderResult {
        case entry(ArchiveEntry, dataSize: Int64)
        case longName(dataSize: Int64)
        case skip(dataSize: Int64)
        case end
        case continueReading
    }
    
    private static func parseTarHeaderBlock(_ block: Data, longName: inout String?) -> TarHeaderResult {
        // Check for end-of-archive (all-zero block)
        if block.allSatisfy({ $0 == 0 }) {
            return .end
        }
        
        let typeflag = block[156]
        
        let sizeStr = readOctalString(block, offset: 124, length: 12)
        let fileSize = Int64(sizeStr, radix: 8) ?? 0
        
        // Handle GNU long name extension (typeflag 'L')
        if typeflag == 0x4C {
            // We can't easily read the long name in streaming mode without
            // buffering the name data. For simplicity, clear longName — the
            // name data follows in the next blocks. We'll just skip it and
            // use the regular name from the next file header.
            longName = nil
            return .longName(dataSize: fileSize)
        }
        
        // Skip PAX extended headers and GNU long link
        if typeflag == 0x78 || typeflag == 0x67 || typeflag == 0x4B {
            return .skip(dataSize: fileSize)
        }
        
        // Read filename
        var fileName: String
        if let ln = longName {
            fileName = ln
            longName = nil
        } else {
            let name = readString(block, offset: 0, length: 100)
            let prefix = readString(block, offset: 345, length: 155)
            if !prefix.isEmpty {
                fileName = prefix + "/" + name
            } else {
                fileName = name
            }
        }
        
        guard !fileName.isEmpty else {
            return .skip(dataSize: fileSize)
        }
        
        let isDir = typeflag == 0x35 || fileName.hasSuffix("/")
        let isRegularFile = typeflag == 0x30 || typeflag == 0x00
        
        if isRegularFile || isDir {
            let mtimeStr = readOctalString(block, offset: 136, length: 12)
            let mtime = Int64(mtimeStr, radix: 8) ?? 0
            let date = mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
            
            if !fileName.hasPrefix("._") && !fileName.contains("/._") {
                let entry = ArchiveEntry(
                    path: fileName,
                    isDirectory: isDir,
                    uncompressedSize: isDir ? 0 : fileSize,
                    modificationDate: date
                )
                return .entry(entry, dataSize: fileSize)
            }
        }
        
        return .skip(dataSize: fileSize)
    }
    
    // MARK: - Helpers
    
    private static func readString(_ data: Data, offset: Int, length: Int) -> String {
        guard offset + length <= data.count else { return "" }
        let slice = data[offset..<offset + length]
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
