//
//  CubeTextureLoader.swift
//  Metal 3D
//
//  Created by 姚振强 on 2025/12/29.
//
//

import Metal
import AppKit // macOS 专用图片框架（替换UIKit）

class CubeTextureLoader {
    /// 加载Assets中的6个面纹理，创建立方体纹理（MTLTexture.typeCube）
    static func loadCubeTexture(device: MTLDevice) -> MTLTexture? {
        // 纹理名称与Cube Map面的对应关系（关键！确保纹理贴对）
        // Cube Map索引：0=正X, 1=负X, 2=正Y, 3=负Y, 4=正Z, 5=负Z
        let faceMap: [Int: String] = [
            0: "cube_texture_right",  // 正X → 右侧面
            1: "cube_texture_left",   // 负X → 左侧面
            2: "cube_texture_top",    // 正Y → 顶面
            3: "cube_texture_bottom", // 负Y → 底面
            4: "cube_texture_front",  // 正Z → 前面
            5: "cube_texture_back"    // 负Z → 后面
        ]
        
        // 读取第一个纹理获取尺寸（所有面必须是正方形且尺寸相同）
        guard let firstName = faceMap[0],
              let firstImage = NSImage(named: firstName),
              let cgImage = firstImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ 无法加载基准纹理：\(faceMap[0]!)")
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        guard width == height else {
            print("❌ 立方体纹理必须是正方形（当前：\(width)x\(height)）")
            return nil
        }
        
        // 创建立方体纹理描述符
        let textureDesc = MTLTextureDescriptor()
        textureDesc.textureType = .typeCube          // 立方体纹理类型
        textureDesc.pixelFormat = .rgba8Unorm        // 通用RGBA格式
        textureDesc.width = width
        textureDesc.height = height
        textureDesc.mipmapLevelCount = 1             // 关闭mipmap（简化）
        textureDesc.storageMode = .shared            // 共享存储模式
        textureDesc.usage = [.shaderRead, .renderTarget]
        
        guard let cubeTexture = device.makeTexture(descriptor: textureDesc) else {
            print("❌ 无法创建立方体纹理对象")
            return nil
        }
        
        // 逐个加载6个面的纹理数据
        for (index, name) in faceMap {
            guard let nsImage = NSImage(named: name),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("❌ 加载纹理失败：\(name)")
                return nil
            }
            
            // 转换为Metal兼容的像素数据（RGBA8，premultipliedAlpha）
            let bytesPerRow = width * 4 // 4字节/像素（RGBA）
            let bytesPerImage = bytesPerRow * height // 新增：补充bytesPerImage参数
            var pixelData = [UInt8](repeating: 0, count: bytesPerImage)
            
            let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            
            // 绘制图片到像素缓冲区（翻转Y轴，适配Metal纹理坐标系）
            context?.translateBy(x: 0, y: CGFloat(height))
            context?.scaleBy(x: 1, y: -1)
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // 修复：补充bytesPerImage参数（macOS下必须）
            cubeTexture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                slice: index, // 对应Cube Map的6个面索引
                withBytes: &pixelData,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage // 新增：解决Missing argument报错
            )
        }
        
        print("✅ 立方体纹理加载成功（尺寸：\(width)x\(height)）")
        return cubeTexture
    }
    
    // 从Assets.xcassets加载天空盒纹理（6张独立图片）
    /// 从Assets.xcassets加载天空盒纹理（6张独立图片）
    /// - Parameters:
    ///   - device: Metal设备
    ///   - baseName: 基础名称（如"outer_space"）
    /// - Returns: Metal立方体纹理
    static func loadSkyBoxFromAssets(device: MTLDevice, baseName: String) -> MTLTexture? {
        // 6个面的后缀（按Metal的立方体纹理顺序）
        let faceNames = [
            "\(baseName)_right",   // +X
            "\(baseName)_left",    // -X
            "\(baseName)_top",     // +Y
            "\(baseName)_bottom",  // -Y
            "\(baseName)_front",   // +Z
            "\(baseName)_back"     // -Z
        ]
        
        // 加载第一张图片以获取尺寸
        guard let firstImage = NSImage(named: faceNames[0]),
              let firstCGImage = firstImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ 天空盒加载失败：找不到\(faceNames[0])")
            return nil
        }
        
        let width = firstCGImage.width
        let height = firstCGImage.height
        
        // 创建立方体纹理描述符
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .typeCube
        textureDescriptor.pixelFormat = .rgba8Unorm
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.mipmapLevelCount = 1
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .shared
        
        guard let cubeTexture = device.makeTexture(descriptor: textureDescriptor) else {
            print("❌ 天空盒加载失败：无法创建立方体纹理")
            return nil
        }
        
        // 加载并上传6个面的图片
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        
        for (slice, faceName) in faceNames.enumerated() {
            guard let nsImage = NSImage(named: faceName),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("❌ 天空盒加载失败：找不到\(faceName)")
                return nil
            }
            
            // 准备像素缓冲区
            var pixelData = [UInt8](repeating: 0, count: totalBytes)
            
            guard let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                print("❌ 天空盒加载失败：无法创建\(faceName)的像素上下文")
                return nil
            }
            
            // 翻转Y轴
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // 上传到对应的立方体面
            cubeTexture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                slice: slice,  // 立方体的第几个面
                withBytes: &pixelData,
                bytesPerRow: bytesPerRow,
                bytesPerImage: 0
            )
        }
        
        print("✅ 天空盒加载成功：\(baseName)（尺寸：\(width)×\(height)）")
        return cubeTexture
    }
}

