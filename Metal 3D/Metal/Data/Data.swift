//
//  Data.swift
//  Metal 3D
//
//  Created by TSAR Weasley on 2023/11/9.
//  Modified by ZQYao on 2025/12/26

import simd

struct Vertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var normal: SIMD3<Float>   // 点所在面法线
    var textureCoordinate: SIMD2<Float> = .zero // 纹理坐标
}

struct Uniform {
    var view: simd_float4x4
    var projection: simd_float4x4
}

enum DrawObjectType: UInt32 {
    case cube = 0
    case coordinateAxis = 1
    case floor = 2
    case cubeReflection = 3
    case skyBox = 4
}

struct DrawTypeUniform {
    var objectType: UInt32 // 存储枚举的rawValue
}

struct DemoStageUniform {
    var demoStage: UInt8 = 0  // 3D效果演示阶段
}

struct LightUniform {
    var position: simd_float3   // 光源位置 (1.2f, 1.0f, 2.0f)
    var ambient: simd_float3    // 环境光 (0.2f, 0.2f, 0.2f)
    var diffuse: simd_float3    // 漫反射光 (0.8f, 0.8f, 0.8f)
    var specular: simd_float3   // 镜面反射光 (1.0f, 1.0f, 1.0f)
    var shininess: Float        // 高光指数 256.0f    
    var padding: Float = 0.0  // 填充字节（Metal要求结构体大小为4的倍数）
}
