//
//  SkyBox.swift
//  Metal 3D
//
//  Created by 姚振强 on 2026/1/1.
//

import simd
import Metal

class SkyBox: Geometry {
    // 天空盒顶点（只需要位置，不需要颜色、法线、纹理坐标）
    private static let vertices: [Vertex] = [
        // 前面
        Vertex(position: [-1, -1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1, -1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1,  1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1,  1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        
        // 后面
        Vertex(position: [-1, -1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1, -1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1,  1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1,  1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        
        // 左面
        Vertex(position: [-1, -1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1, -1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1,  1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1,  1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        
        // 右面
        Vertex(position: [ 1, -1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1, -1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1,  1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1,  1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        
        // 上面
        Vertex(position: [-1,  1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1,  1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1,  1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1,  1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        
        // 下面
        Vertex(position: [-1, -1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1, -1,  1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [ 1, -1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0]),
        Vertex(position: [-1, -1, -1], color: [1, 1, 1, 1], normal: [0, 0, 0])
    ]
    
    // 天空盒索引（注意：内向渲染，索引顺序与普通立方体相反）
    private static let indices: [UInt16] = [
        // 前面
         0, 2, 3, 0, 1, 2,
        // 后面
         4, 6, 7, 4, 5, 6,
        // 左面
         8,10,11, 8, 9,10,
        // 右面
        12,14,15,12,13,14,
        // 上面
        16,18,19,16,17,18,
        // 下面
        20,22,23,20,21,22
    ]
    
    private static var indexBuffer: MTLBuffer!
    private static var buffer: MTLBuffer!
    
    static func initType(_ device: MTLDevice) {
        buffer = device.makeBuffer(bytes: Self.vertices, length: Self.vertices.count * MemoryLayout<Vertex>.stride)
        indexBuffer = device.makeBuffer(bytes: Self.indices, length: Self.indices.count * MemoryLayout<UInt16>.stride)
    }
    
    init(_ device: MTLDevice) {
        super.init()
        // 天空盒不需要缩放和变换，始终跟随相机
    }
    
    func draw(_ encoder: MTLRenderCommandEncoder, cameraPosition: SIMD3<Float>) {
        // 天空盒的模型矩阵：只有平移（跟随相机位置），没有旋转和缩放
        var skyboxModel = simd_float4x4(1)
        skyboxModel[3] = SIMD4<Float>(cameraPosition, 1)
        
        encoder.setVertexBuffer(Self.buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&skyboxModel, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: Self.indices.count,
            indexType: .uint16,
            indexBuffer: Self.indexBuffer,
            indexBufferOffset: 0
        )
    }
}
