//
//  WorldAxes.swift
//  Metal 3D
//
//  Created by 姚振强 on 2025/12/26.
//
//  用于渲染固定在世界原点的红 / 绿 / 蓝坐标轴（线图元）

import Foundation

import simd
import Metal

// 继承自你的Geometry基类（和Axes保持一致）
class WorldAxes: Geometry {
    // 坐标轴顶点：X(红)、Y(绿)、Z(蓝)，从原点延伸2个单位（清晰可见）
    private static let axesVertices: [Vertex] = [
        // X轴：原点 → (2,0,0) 红色
        Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(1, 0, 0, 1), normal: SIMD3<Float>(1, 0, 0)),
        Vertex(position: SIMD3<Float>(4, 0, 0), color: SIMD4<Float>(1, 0, 0, 1), normal: SIMD3<Float>(1, 0, 0)),
        // Y轴：原点 → (0,2,0) 绿色
        Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(0, 1, 0, 1), normal: SIMD3<Float>(0, 1, 0)),
        Vertex(position: SIMD3<Float>(0, 4, 0), color: SIMD4<Float>(0, 1, 0, 1), normal: SIMD3<Float>(0, 1, 0)),
        // Z轴：原点 → (0,0,2) 蓝色
        Vertex(position: SIMD3<Float>(0, 0, 0), color: SIMD4<Float>(0, 0, 1, 1), normal: SIMD3<Float>(0, 0, 1)),
        Vertex(position: SIMD3<Float>(0, 0, 4), color: SIMD4<Float>(0, 0, 1, 1), normal: SIMD3<Float>(0, 0, 1))
    ]
    
    // 坐标轴索引（线图元：每2个顶点组成1条线）
    private static let axesIndices: [UInt16] = [0,1, 2,3, 4,5]
    
    // 静态缓冲区（所有WorldAxes实例共享）
    private static var axesVertexBuffer: MTLBuffer!
    private static var axesIndexBuffer: MTLBuffer!
    
    // 初始化静态缓冲区（全局只执行一次）
    static func initType(_ device: MTLDevice) {
        axesVertexBuffer = device.makeBuffer(
            bytes: axesVertices,
            length: axesVertices.count * MemoryLayout<Vertex>.stride
        )
        axesIndexBuffer = device.makeBuffer(
            bytes: axesIndices,
            length: axesIndices.count * MemoryLayout<UInt16>.stride
        )
    }
    
    // 模型矩阵缓冲区（传递给着色器）
    private var modelBuffer: MTLBuffer!
    
    init(_ device: MTLDevice) {
        super.init()
        // 创建模型矩阵缓冲区
        modelBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.size)
    }
    
    // 自定义draw方法：接收外部模型矩阵（世界坐标轴传单位矩阵）
    func draw(_ encoder: MTLRenderCommandEncoder, modelMatrix: simd_float4x4) {
        // 传递模型矩阵（世界坐标轴用单位矩阵，固定在原点）
        modelBuffer.contents().storeBytes(
            of: modelMatrix,
            toByteOffset: 0,
            as: simd_float4x4.self
        )
        
        // 设置顶点/模型矩阵缓冲区
        encoder.setVertexBuffer(Self.axesVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(modelBuffer, offset: 0, index: 1)
        
        // 绘制线图元（坐标轴）
        encoder.drawIndexedPrimitives(
            type: .line,          // 线图元（区别于立方体的三角形）
            indexCount: Self.axesIndices.count,
            indexType: .uint16,
            indexBuffer: Self.axesIndexBuffer,
            indexBufferOffset: 0
        )
    }
}
