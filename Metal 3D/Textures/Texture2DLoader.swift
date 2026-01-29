//
//  Texture2DLoader.swift
//  Metal 3D
//
//  Created by 姚振强 on 2025/12/31.
//

import Metal
import AppKit // macOS 专用图片框架（仅用NSImage，无其他依赖）

class Texture2DLoader {
    /// 从Assets.xcassets加载2D纹理（极简版，仅保留核心逻辑）
    /// - Parameters:
    ///   - device: Metal设备
    ///   - assetName: Assets中的纹理名称（无后缀，如"floorTexture"）
    /// - Returns: Metal 2D纹理（失败返回nil，控制台打印明确错误）
    static func loadFromAssets(device: MTLDevice, assetName: String) -> MTLTexture? {
        // 1. 从Assets加载NSImage（最基础的第一步）
        guard let nsImage = NSImage(named: assetName) else {
            print("❌ 2D纹理加载失败：Assets中找不到\(assetName)（检查名称/是否勾选Target）")
            return nil
        }
        
        // 2. 转CGImage获取真实尺寸（NSImage.size是逻辑尺寸，CGImage是像素尺寸）
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("❌ 2D纹理加载失败：\(assetName)转CGImage失败")
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        
        // 3. 准备像素缓冲区（适配Metal的RGBA8格式，翻转Y轴）
        let bytesPerRow = width * 4 // 4字节/像素（RGBA）
        let totalBytes = bytesPerRow * height
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        // 创建CGContext处理像素（仅做必要的Y轴翻转，无多余逻辑）
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("❌ 2D纹理加载失败：\(assetName)创建像素上下文失败")
            return nil
        }
        
        // 关键：翻转Y轴（NSImage左上原点 → Metal纹理左下原点）
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 4. 创建Metal 2D纹理描述符（仅保留必要配置）
        let textureDesc = MTLTextureDescriptor()
        textureDesc.textureType = .type2D          // 纯2D纹理
        textureDesc.pixelFormat = .rgba8Unorm      // 通用RGBA格式（和立方体纹理一致）
        textureDesc.width = width
        textureDesc.height = height
        textureDesc.mipmapLevelCount = 1           // 关闭mipmap（简化）
        textureDesc.usage = [.shaderRead]          // 仅用于着色器读取
        
        // 5. 创建纹理并写入像素数据
        guard let texture = device.makeTexture(descriptor: textureDesc) else {
            print("❌ 2D纹理加载失败：\(assetName)创建Metal纹理对象失败")
            return nil
        }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &pixelData,
            bytesPerRow: bytesPerRow
        )
        
        print("✅ 2D纹理加载成功：\(assetName)（像素尺寸：\(width)×\(height)）")
        return texture
    }
}
