//
//  Plane.swift
//  Metal 3D
//
//  Created by 姚振强 on 2025/12/31.
//

import simd
import Metal

// 地板几何体（纯增量，不依赖任何新增字段）
class Plane: Geometry {
    // 地板顶点：y固定-1，覆盖x(-5~5)、z(-5~5)的大平面（避免相机移动后看不到地板）
    private static let vertices: [Vertex] = [
        // 左下
        Vertex(position: [-4, -0.7, -5], color: [0.5, 0.5, 0.5, 1], normal: [0, 1, 0], textureCoordinate: [0, 0]),
        // 右下
        Vertex(position: [4,  -0.7, -5], color: [0.5, 0.5, 0.5, 1], normal: [0, 1, 0], textureCoordinate: [1, 0]),
        // 右上
        Vertex(position: [4,  -0.7,  5], color: [0.5, 0.5, 0.5, 1], normal: [0, 1, 0], textureCoordinate: [1, 1]),
        // 左上
        Vertex(position: [-4, -0.7,  5], color: [0.5, 0.5, 0.5, 1], normal: [0, 1, 0], textureCoordinate: [0, 1])
    ]
    
    // 地板索引（2个三角形组成矩形平面）
    private static let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
    
    // 静态缓冲区（所有Plane实例共享）
    private static var vertexBuffer: MTLBuffer!
    private static var indexBuffer: MTLBuffer!
    
    // 初始化静态缓冲区（和Cube/WorldAxes的initType逻辑一致）
    static func initType(_ device: MTLDevice) {
        // 顶点缓冲区
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )
        // 索引缓冲区
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )
    }
    
    // 模型矩阵缓冲区（实例变量，传递给着色器）
    private var modelBuffer: MTLBuffer!
    
    init(_ device: MTLDevice) {
        super.init()
        // 创建模型矩阵缓冲区（和Cube/WorldAxes逻辑一致）
        modelBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride)
    }
    
    // 绘制方法（和Cube的draw逻辑对齐，保证兼容）
    func draw(_ encoder: MTLRenderCommandEncoder) {
        // 传递模型矩阵（地板固定在y=-1，用单位矩阵即可）
        modelBuffer.contents().storeBytes(
            of: super.model,
            toByteOffset: 0,
            as: simd_float4x4.self
        )
        
        // 设置顶点/模型矩阵缓冲区（index0=顶点，index1=模型矩阵，和现有逻辑一致）
        encoder.setVertexBuffer(Self.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(modelBuffer, offset: 0, index: 1)
        
        // 绘制地板（三角形图元，和立方体一致）
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: Self.indices.count,
            indexType: .uint16,
            indexBuffer: Self.indexBuffer,
            indexBufferOffset: 0
        )
    }
}
