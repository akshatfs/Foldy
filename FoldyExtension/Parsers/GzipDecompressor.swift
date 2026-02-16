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
    
    /// Decompress gzip data using streaming compression_stream API.
    static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 10,
              data[0] == 0x1F, data[1] == 0x8B else {
            throw GzipError.notGzip
        }
        
        // Skip gzip header to find the raw DEFLATE stream
        var offset = 10
        let flags = data[3]
        
        // FEXTRA
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { throw GzipError.notGzip }
            let extraLen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + extraLen
        }
        // FNAME
        if flags & 0x08 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FCOMMENT
        if flags & 0x10 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC
        if flags & 0x02 != 0 {
            offset += 2
        }
        
        guard offset < data.count else { throw GzipError.notGzip }
        
        // Compressed DEFLATE data (excluding trailing 8 bytes: CRC32 + ISIZE)
        let compressedData = data[offset..<(data.count - 8)]
        
        // Use streaming decompression to handle arbitrary output sizes
        return try streamingDecompress(compressedData)
    }
    
    /// Streaming decompression using compression_stream — handles any output size.
    private static func streamingDecompress(_ compressedData: Data) throws -> Data {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        
        let initStatus = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else { throw GzipError.decompressFailed }
        defer { compression_stream_destroy(streamPtr) }
        
        let chunkSize = 65536 // 64 KB output chunks
        var result = Data()
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { outputBuffer.deallocate() }
        
        try compressedData.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) in
            guard let srcBase = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw GzipError.decompressFailed
            }
            
            streamPtr.pointee.src_ptr = srcBase
            streamPtr.pointee.src_size = compressedData.count
            
            repeat {
                streamPtr.pointee.dst_ptr = outputBuffer
                streamPtr.pointee.dst_size = chunkSize
                
                let processStatus = compression_stream_process(streamPtr, 0)
                
                let bytesWritten = chunkSize - streamPtr.pointee.dst_size
                if bytesWritten > 0 {
                    result.append(outputBuffer, count: bytesWritten)
                }
                
                if processStatus == COMPRESSION_STATUS_END {
                    break
                } else if processStatus == COMPRESSION_STATUS_ERROR {
                    throw GzipError.decompressFailed
                }
            } while streamPtr.pointee.src_size > 0 || streamPtr.pointee.dst_size == 0
        }
        
        return result
    }
}
