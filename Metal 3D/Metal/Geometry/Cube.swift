//
//  Cube.swift
//  Metal 3D
//
//  Created by TSAR Weasley on 2023/11/9.
//  Modified by ZQYao on 2025/12/26

import simd
import Metal

// 立方体几何类：演示3D模型的顶点、法线和索引缓冲区
// 学习要点：立方体有24顶点（每面4顶点），通过索引复用减少内存；法线用于光照计算
class Cube: Geometry {
    private static let vertices: [Vertex] = [
        // 前面 (法线: 0,0,1)
        Vertex(position: [-0.5, -0.5,  0.5], color: [1, 0, 0, 1], normal: [0, 0, 1]),
        Vertex(position: [ 0.5, -0.5,  0.5], color: [0, 1, 0, 1], normal: [0, 0, 1]),
        Vertex(position: [ 0.5,  0.5,  0.5], color: [0, 0, 1, 1], normal: [0, 0, 1]),
        Vertex(position: [-0.5,  0.5,  0.5], color: [1, 1, 0, 1], normal: [0, 0, 1]),
        
        // 后面 (法线: 0,0,-1)
        Vertex(position: [-0.5, -0.5, -0.5], color: [1, 0, 1, 1], normal: [0, 0, -1]),
        Vertex(position: [ 0.5, -0.5, -0.5], color: [0, 1, 1, 1], normal: [0, 0, -1]),
        Vertex(position: [ 0.5,  0.5, -0.5], color: [1, 0, 0, 1], normal: [0, 0, -1]),
        Vertex(position: [-0.5,  0.5, -0.5], color: [0, 1, 0, 1], normal: [0, 0, -1]),
        
        // 左面 (法线: -1,0,0)
        Vertex(position: [-0.5, -0.5,  0.5], color: [1, 0, 0, 1], normal: [-1, 0, 0]),
        Vertex(position: [-0.5, -0.5, -0.5], color: [1, 0, 1, 1], normal: [-1, 0, 0]),
        Vertex(position: [-0.5,  0.5, -0.5], color: [0, 1, 0, 1], normal: [-1, 0, 0]),
        Vertex(position: [-0.5,  0.5,  0.5], color: [1, 1, 0, 1], normal: [-1, 0, 0]),
        
        // 右面 (法线: 1,0,0)
        Vertex(position: [ 0.5, -0.5,  0.5], color: [0, 1, 0, 1], normal: [1, 0, 0]),
        Vertex(position: [ 0.5, -0.5, -0.5], color: [0, 1, 1, 1], normal: [1, 0, 0]),
        Vertex(position: [ 0.5,  0.5, -0.5], color: [1, 0, 0, 1], normal: [1, 0, 0]),
        Vertex(position: [ 0.5,  0.5,  0.5], color: [0, 0, 1, 1], normal: [1, 0, 0]),
        
        // 上面 (法线: 0,1,0)
        Vertex(position: [-0.5,  0.5,  0.5], color: [1, 1, 0, 1], normal: [0, 1, 0]),
        Vertex(position: [ 0.5,  0.5,  0.5], color: [0, 0, 1, 1], normal: [0, 1, 0]),
        Vertex(position: [ 0.5,  0.5, -0.5], color: [1, 0, 0, 1], normal: [0, 1, 0]),
        Vertex(position: [-0.5,  0.5, -0.5], color: [0, 1, 0, 1], normal: [0, 1, 0]),
        
        // 下面 (法线: 0,-1,0)
        Vertex(position: [-0.5, -0.5,  0.5], color: [1, 0, 0, 1], normal: [0, -1, 0]),
        Vertex(position: [ 0.5, -0.5,  0.5], color: [0, 1, 0, 1], normal: [0, -1, 0]),
        Vertex(position: [ 0.5, -0.5, -0.5], color: [0, 1, 1, 1], normal: [0, -1, 0]),
        Vertex(position: [-0.5, -0.5, -0.5], color: [1, 0, 1, 1], normal: [0, -1, 0])
    ]
    
    // 立方体三角形索引（6个面×2个三角形=12个三角形）
    private static let indices: [UInt16] = [
        // 前面
         0, 3, 2, 0, 2, 1,
         // 后面
         4, 5, 6, 4, 6, 7,
         // 左面
         8,11,10, 8,10, 9, // 8, 9,11, 8,11,10,
         // 右面
        12,15,14,12,14,13,
         // 上面
        16,17,18,16,18,19,
         // 下面
        20,21,22,20,22,23
    ]

    private static var indexBuffer: MTLBuffer! // 索引缓冲区
    private static var buffer: MTLBuffer!      // 顶点缓冲区
    
    static func initType(_ device: MTLDevice) {
        // 顶点缓冲区
        buffer      = device.makeBuffer(bytes: Self.vertices, length: Self.vertices.count * MemoryLayout<Vertex>.stride)
        // 索引缓冲区
        indexBuffer = device.makeBuffer(bytes: Self.indices,  length: Self.indices.count * MemoryLayout<UInt16>.stride)
    }
    
    //private var modelBuffer: MTLBuffer!
    
    init(_ device: MTLDevice) {
        super.init()
        scaling = .one * 0.8
        //modelBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.size)
    }
    
    func draw(_ encoder: MTLRenderCommandEncoder, externalModel: simd_float4x4? = nil) {
        var finalModel = externalModel ?? super.model // 优先使用外部矩阵，否则用自身model
        // 传递模型矩阵
        //modelBuffer.contents().storeBytes(of: finalModel, toByteOffset: 0, as: simd_float4x4.self)
        
        encoder.setVertexBuffer(Self.buffer, offset: 0, index: 0)
        //encoder.setVertexBuffer(modelBuffer, offset: 0, index: 1)
        encoder.setVertexBytes(&finalModel, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: Self.indices.count,
            indexType: .uint16,
            indexBuffer: Self.indexBuffer,
            indexBufferOffset: 0
        )
    }
}

