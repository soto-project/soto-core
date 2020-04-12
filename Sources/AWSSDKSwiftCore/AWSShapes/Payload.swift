//
//  Payload.swift
//  AWSSDKCore
//
//  Created by Adam Fowler on 2020/03/01.
//
import struct Foundation.Data
import NIO

public struct AWSPayload {
    
    public static func byteBuffer(_ byteBuffer: ByteBuffer) -> Self {
        return Self(byteBuffer: byteBuffer)
    }
    
    public static func data(_ data: Data) -> Self {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        return Self(byteBuffer: byteBuffer)
    }
    
    public static func string(_ string: String) -> Self {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
        byteBuffer.writeString(string)
        return Self(byteBuffer: byteBuffer)
    }

    let byteBuffer: ByteBuffer
}
