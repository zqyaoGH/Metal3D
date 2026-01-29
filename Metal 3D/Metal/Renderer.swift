//
//  Renderer.swift
//  Metal Startup
//
//  Created by TSAR Weasley on 2023/10/15.
//  Modified by ZQYao on 2025/12/26
//  Modified by ZQYao on 2026/01/01
//  Modified by ZQYao on 2026/01/02 - Added camera orbit rotation feature

import SwiftUI
import MetalKit

class Renderer: NSObject, MTKViewDelegate, ObservableObject {
    // MARK: - 核心属性
    private let device = MTLCreateSystemDefaultDevice()
    private var commandQueue: MTLCommandQueue?
    
    var backgroundColor: Color.Resolved?
    
    private var lastFrameTimestamp = Date.now
    @Published var fps = 0.0
    var resolution = CGSize()
    
    private var renderPipelineState: MTLRenderPipelineState?
    private var uniformBuffer: MTLBuffer?
    
    // 纹理/采样器
    private var cubeMapTexture: MTLTexture?
    private var cubeMapSampler: MTLSamplerState? // 原错误：MTLRenderPipelineState
    private var floorTexture: MTLTexture?
    private var floorSampler: MTLSamplerState?
    private var skyBoxTexture: MTLTexture?
    private var skyBoxSampler: MTLSamplerState?
    
    // 光照参数：定义Phong光照模型所需的数据
    // 学习要点：Phong模型包括环境光（ambient）提供基础亮度，漫反射（diffuse）模拟光线散射，镜面反射（specular）创造高光
    // 为什么用这个模型？它简单高效，适合实时3D渲染，模拟真实世界光照效果
    private var lightData: LightUniform = LightUniform(
          position: simd_float3(1.2, 1.0, 2.0),
          ambient: simd_float3(0.4, 0.4, 0.4),
          diffuse: simd_float3(0.8, 0.8, 0.8),
          specular: simd_float3(1.0, 1.0, 1.0),
          shininess: 128.0
    )
    
    // 几何对象
    var camera: Camera!
    var controller: FPSController!
    // 几何对象
    var cube: Cube!
    var worldAxes: WorldAxes!
    var floor: Plane!
    var skyBox: SkyBox!
    
    // 变换参数
    var uniform: Uniform = Uniform(view: .init(1), projection: .init(1))
    @Published var rotateX: Float = 0.0
    @Published var rotateY: Float = 0.0
    @Published var rotateZ: Float = 0.0
    @Published var translateX: Float = 0.0
    @Published var translateY: Float = 0.0
    @Published var translateZ: Float = 0.0
    @Published var scaleX: Float = 0.5
    @Published var scaleY: Float = 0.5
    @Published var scaleZ: Float = 0.5
    
    // 演示阶段
    var demoStage: UInt8 = 0
    
    // 辅助状态
    private var depthStencilState: MTLDepthStencilState!
    private var emptySampler: MTLSamplerState!
    
    // MARK: - 相机轨道旋转状态
    private var cameraOrbitAngle: Float = 0.0  // 当前轨道角度
    private var cameraOrbitRadius: Float = 0.0  // 轨道半径
    private var cameraOrbitHeight: Float = 0.0  // 轨道高度
    private var isOrbitActive = false  // 轨道是否正在运行
    @Published var orbitStatus: String = "轨道未启动"  // 轨道状态信息

    // MARK: - 初始化
    override init() {
        super.init()
        camera = Camera()
        controller = FPSController(camera: camera)
    }
    
    func initWithView(_ view: MTKView) {
        view.delegate = self
        view.device = device
        view.depthStencilPixelFormat = .depth32Float
        
        guard let device = device else { return }
        
        // 初始化几何对象
        Cube.initType(device)
        cube = Cube(device)
        WorldAxes.initType(device)
        worldAxes = WorldAxes(device)
        Plane.initType(device)
        floor = Plane(device)
        SkyBox.initType(device)
        skyBox = SkyBox(device)
        
        // 初始化采样器
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        cubeMapSampler = device.makeSamplerState(descriptor: samplerDesc)
        skyBoxSampler = device.makeSamplerState(descriptor: samplerDesc)
        
        let emptySamplerDesc = MTLSamplerDescriptor()
        emptySamplerDesc.minFilter = .linear
        emptySamplerDesc.magFilter = .linear
        emptySamplerDesc.sAddressMode = .clampToEdge
        emptySamplerDesc.tAddressMode = .clampToEdge
        emptySampler = device.makeSamplerState(descriptor: emptySamplerDesc)
        
        let floorSamplerDesc = MTLSamplerDescriptor()
        floorSamplerDesc.minFilter = .linear
        floorSamplerDesc.magFilter = .linear
        floorSamplerDesc.mipFilter = .linear
        floorSamplerDesc.sAddressMode = .repeat
        floorSamplerDesc.tAddressMode = .repeat
        floorSamplerDesc.rAddressMode = .repeat
        floorSamplerDesc.maxAnisotropy = 16         // 最大各向异性级别（1-16）
        floorSampler = device.makeSamplerState(descriptor: floorSamplerDesc)
        
        // 加载纹理
        cubeMapTexture = CubeTextureLoader.loadCubeTexture(device: device)
        skyBoxTexture = CubeTextureLoader.loadSkyBoxFromAssets(device: device, baseName: "outer_space")
        floorTexture = Texture2DLoader.loadFromAssets(device: device, assetName: "floor_texture")
        if floorTexture == nil {
            print("❌ 地板纹理加载失败：未找到floor_texture资源或加载出错")
        } else {
            print("✅ 地板纹理加载成功")
        }
        
        /*
        | Test 1 | (0, 1, 5)  | (0°, 0°, 0°)    | ⏳ 已测 | 看到立方体前面
        | Test 2 | (5, 1, 0)  | (90°, 0°, 0°)   | ⏳ 已测 | 看到立方体右面
        | Test 3 | (0, 1, -5) | (180°, 0°, 0°)  | ⏳ 已测 | 看到立方体后面
        | Test 4 | (-5, 1, 0) | (-90°, 0°, 0°)  | ⏳ 已测 | 看到立方体左面
        */
         // 相机参数（初始位置和朝向）
        camera.position = SIMD3<Float>(0, 1, 5) //
        camera.yaw = 0 //
        camera.pitch = 0 //

        // 初始化命令队列和Uniform缓冲区
        commandQueue = device.makeCommandQueue()
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniform>.size)
        
        // 深度模板状态：控制深度测试，确保正确绘制顺序
        // 学习要点：深度测试（Depth Testing）防止远物遮挡近物，isDepthWriteEnabled允许写入深度缓冲区
        // 为什么用.less？因为Metal左手坐标系，近物Z值小
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = true // 原错误：depthWriteEnabled
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
        
        // 渲染管线状态
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        let defaultLibrary = device.makeDefaultLibrary()
        renderPipelineDescriptor.vertexFunction = defaultLibrary?.makeFunction(name: "vertexShader")
        renderPipelineDescriptor.fragmentFunction = defaultLibrary?.makeFunction(name: "fragmentShader")
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        
        // 启用 Alpha 混合：处理透明物体渲染
        // 学习要点：Alpha Blending混合透明像素，公式为：结果 = 源 * 源Alpha + 目标 * (1 - 源Alpha)
        // 为什么需要？地板半透明，避免硬边缘，实现倒影效果
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // 顶点描述符
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = MemoryLayout<Vertex>.offset(of: \.position)!
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = MemoryLayout<Vertex>.offset(of: \.color)!
        
        vertexDescriptor.attributes[2].format = .float3
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[2].offset = MemoryLayout<Vertex>.offset(of: \.normal)!
        
        vertexDescriptor.attributes[3].format = .float2
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[3].offset = MemoryLayout<Vertex>.offset(of: \.textureCoordinate)!
        
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineState = try? device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspectRatio = Float(size.width / size.height)
        resolution = size
    }
    
    // MARK: - 新增：相机轨道旋转更新方法
    /// 更新相机轨道旋转：让相机围绕场景中心旋转，模拟轨道运动
    /// - Parameter angleStep: 旋转角度步长（弧度）
    func updateCameraOrbit(angleStep: Float) {
        // 如果轨道刚刚启动（从非活跃变为活跃），重新初始化轨道参数
        // 学习要点：轨道基于当前相机位置，半径=sqrt(x²+z²)，角度=atan2(x,z)
        if !isOrbitActive {
            let currentPos = camera.position
            cameraOrbitHeight = currentPos.y
            // 轨道半径基于当前XZ平面距离：用勾股定理计算
            cameraOrbitRadius = sqrt(currentPos.x * currentPos.x + currentPos.z * currentPos.z)
            // 轨道角度基于当前位置：用atan2避免象限问题
            cameraOrbitAngle = atan2(currentPos.x, currentPos.z) * 180.0 / .pi
            isOrbitActive = true
            orbitStatus = String(format: "轨道运行中: 半径%.2f, 高度%.2f", cameraOrbitRadius, cameraOrbitHeight)
            print("🔧 相机轨道重新初始化：半径=\(cameraOrbitRadius), 高度=\(cameraOrbitHeight), 基准角度=\(cameraOrbitAngle)°")
        }

        // 累加角度（以度为单位）：逐步旋转，避免跳跃
        cameraOrbitAngle += angleStep

        // 角度归一化到 [0°, 360°]：确保连续旋转
        cameraOrbitAngle = fmod(cameraOrbitAngle, 360.0)
        if cameraOrbitAngle < 0 {
            cameraOrbitAngle += 360.0
        }

        // 计算新位置（弧度转换）：用极坐标公式 x=r*sin(θ), z=r*cos(θ)
        // 学习要点：为什么用极坐标？轨道是圆形，方便计算位置
        let angleRadians = cameraOrbitAngle * .pi / 180.0
        let newX = cameraOrbitRadius * sin(angleRadians)
        let newZ = cameraOrbitRadius * cos(angleRadians)
        camera.position = SIMD3<Float>(newX, cameraOrbitHeight, newZ)

        // 用数学公式直接计算yaw：相机朝向目标，pitch和roll保持不变
        // 学习要点：yaw=atan2(newX,newZ)，确保相机始终面向中心
        let θ = atan2(newX, newZ) * 180.0 / .pi
        camera.yaw = θ
        // pitch和roll保持启动时的值，不做修改

        // 注释掉lookAt调用（保留以备不时之需）
        // camera.lookAt(target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - 轨道控制辅助方法
    func stopOrbit() {
        isOrbitActive = false
        orbitStatus = "轨道已停止"
        print("⏹️ 相机轨道已停止")
    }


    
    // MARK: - 核心绘制逻辑
    func draw(in view: MTKView) {
        // MARK: --------------- 公共逻辑（所有阶段共享）---------------
        // 1. 帧率更新
        let currentFrameTimestamp = Date.now
        let timeInterval = currentFrameTimestamp.timeIntervalSince(lastFrameTimestamp)
        lastFrameTimestamp = currentFrameTimestamp
        fps = 1.0 / timeInterval
        
        // 2. 相机控制器更新
        controller.update(Float(timeInterval))
        
        // 3. 背景色设置
        if let backgroundColor = backgroundColor {
            view.clearColor = MTLClearColor(
                red: Double(backgroundColor.red),
                green: Double(backgroundColor.green),
                blue: Double(backgroundColor.blue),
                alpha: Double(backgroundColor.opacity)
            )
        }
        
        // 4. 更新VP矩阵到Uniform缓冲区：传递视图（View）和投影（Projection）矩阵给着色器
        // 学习要点：视图矩阵（View Matrix）将世界坐标转换为相机坐标，投影矩阵（Projection Matrix）转换为裁剪空间
        // 为什么需要？GPU需要这些矩阵来正确变换顶点，实现3D到2D投影
        uniform.projection = camera.projection
        uniform.view = camera.view
        if let uniformBuffer = uniformBuffer {
            uniformBuffer.contents().storeBytes(
                of: uniform.view,
                toByteOffset: MemoryLayout<Uniform>.offset(of: \.view)!,
                as: simd_float4x4.self
            )
            uniformBuffer.contents().storeBytes(
                of: uniform.projection,
                toByteOffset: MemoryLayout<Uniform>.offset(of: \.projection)!,
                as: simd_float4x4.self
            )
        }
        
        // 5. 创建命令缓冲区和渲染编码器
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // 6. 设置公共管线状态
        renderCommandEncoder.setRenderPipelineState(renderPipelineState!)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        
        // 7. 传递公共Uniform（所有绘制共享）
        // - VP矩阵（buffer2）
        renderCommandEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 2)
        // - 演示阶段（buffer4）
        var demoStageU = DemoStageUniform(demoStage: demoStage)
        renderCommandEncoder.setVertexBytes(&demoStageU, length: MemoryLayout<DemoStageUniform>.stride, index: 4)
        renderCommandEncoder.setFragmentBytes(&demoStageU, length: MemoryLayout<DemoStageUniform>.stride, index: 4)
        // - 光照参数（buffer5）
        renderCommandEncoder.setFragmentBytes(&lightData, length: MemoryLayout<LightUniform>.stride, index: 5)
        
        // 8. 初始化纹理/采样器为默认空状态
        renderCommandEncoder.setFragmentTexture(nil, index: 0)
        renderCommandEncoder.setFragmentSamplerState(emptySampler, index: 0)
        renderCommandEncoder.setFragmentTexture(nil, index: 1)
        renderCommandEncoder.setFragmentSamplerState(emptySampler, index: 1)
        
        // MARK: --------------- 按演示阶段处理绘制逻辑 ---------------
        // 学习要点：为什么要分阶段演示？为了逐步学习3D渲染技术，从基础（纯色）到高级（光照、反射）
        // 每个阶段添加新功能，展示渲染管道的构建过程
        switch demoStage {
        case 0...2:
            // 阶段 0-2：仅绘制立方体 + 坐标轴
            // 绘制立方体
            var cubeDrawType = DrawTypeUniform(objectType: DrawObjectType.cube.rawValue)
            renderCommandEncoder.setVertexBytes(&cubeDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&cubeDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            
            // 绑定立方体纹理/采样器（✅ 类型匹配，无报错）
            if let cubeMapTexture = cubeMapTexture {
                renderCommandEncoder.setFragmentTexture(cubeMapTexture, index: 0)
            }
            if let cubeMapSampler = cubeMapSampler {
                renderCommandEncoder.setFragmentSamplerState(cubeMapSampler, index: 0)
            }
            
            cube.draw(renderCommandEncoder)

            // 绘制坐标轴
            var axisDrawType = DrawTypeUniform(objectType: DrawObjectType.coordinateAxis.rawValue)
            renderCommandEncoder.setVertexBytes(&axisDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&axisDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            worldAxes.draw(renderCommandEncoder, modelMatrix: simd_float4x4(1))
            
        case 3:
            // 阶段 3：绘制立方体 + 地板 + 坐标轴
            // 1. 绘制立方体
            var cubeDrawType = DrawTypeUniform(objectType: DrawObjectType.cube.rawValue)
            renderCommandEncoder.setVertexBytes(&cubeDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&cubeDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            
            if let cubeMapTexture = cubeMapTexture {
                renderCommandEncoder.setFragmentTexture(cubeMapTexture, index: 0)
            }
            if let cubeMapSampler = cubeMapSampler {
                renderCommandEncoder.setFragmentSamplerState(cubeMapSampler, index: 0)
            }
            
            cube.draw(renderCommandEncoder)
            
            // 2. 绘制地板
            var floorDrawType = DrawTypeUniform(objectType: DrawObjectType.floor.rawValue)
            renderCommandEncoder.setVertexBytes(&floorDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&floorDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            
            if let floorTexture = floorTexture, let floorSampler = floorSampler {
                renderCommandEncoder.setFragmentTexture(floorTexture, index: 1)
                renderCommandEncoder.setFragmentSamplerState(floorSampler, index: 1)
            }
            
            floor.draw(renderCommandEncoder)
            renderCommandEncoder.setFragmentTexture(nil, index: 1)
            renderCommandEncoder.setFragmentSamplerState(emptySampler, index: 1)
            
            // 3. 绘制坐标轴
            var axisDrawType = DrawTypeUniform(objectType: DrawObjectType.coordinateAxis.rawValue)
            renderCommandEncoder.setVertexBytes(&axisDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&axisDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            worldAxes.draw(renderCommandEncoder, modelMatrix: simd_float4x4(1))
            
        default:
            // 0. 绘制天空盒（最先绘制，作为背景）
            // 学习要点：天空盒（SkyBox）是无限远的背景，深度测试设为.always确保它总在最后绘制，不影响前景物体
            // 为什么不写入深度？避免天空盒遮挡其他对象
            // 创建一个不写入深度的深度模板状态
            let skyboxDepthDescriptor = MTLDepthStencilDescriptor()
            skyboxDepthDescriptor.isDepthWriteEnabled = false  // 不写入深度
            skyboxDepthDescriptor.depthCompareFunction = .always  // 总是通过深度测试
            let skyboxDepthState = device?.makeDepthStencilState(descriptor: skyboxDepthDescriptor)
            // 临时切换到天空盒的深度状态
            renderCommandEncoder.setDepthStencilState(skyboxDepthState!)

            var skyBoxDrawType = DrawTypeUniform(objectType: DrawObjectType.skyBox.rawValue)
            renderCommandEncoder.setVertexBytes(&skyBoxDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&skyBoxDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)

            // 绑定天空盒纹理到index 2
            if let skyBoxTexture = skyBoxTexture {
                renderCommandEncoder.setFragmentTexture(skyBoxTexture, index: 2)
            }
            if let skyBoxSampler = skyBoxSampler {
                renderCommandEncoder.setFragmentSamplerState(skyBoxSampler, index: 0)
            }

            skyBox.draw(renderCommandEncoder, cameraPosition: camera.position)

            // 恢复正常的深度状态
            renderCommandEncoder.setDepthStencilState(depthStencilState)

            // 阶段 >3：绘制原立方体 + 倒影立方体 + 坐标轴
            // 1. 绘制原立方体
            var cubeDrawType = DrawTypeUniform(objectType: DrawObjectType.cube.rawValue)
            renderCommandEncoder.setVertexBytes(&cubeDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&cubeDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            
            if let cubeMapTexture = cubeMapTexture {
                renderCommandEncoder.setFragmentTexture(cubeMapTexture, index: 0)
            }
            if let cubeMapSampler = cubeMapSampler {
                renderCommandEncoder.setFragmentSamplerState(cubeMapSampler, index: 0)
            }
            cube.draw(renderCommandEncoder)

            // 2. 绘制倒影立方体
            var reflectionDrawType = DrawTypeUniform(objectType: DrawObjectType.cubeReflection.rawValue)
            renderCommandEncoder.setVertexBytes(&reflectionDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&reflectionDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            
            // 构建镜像矩阵
            let floorY: Float = -0.7
            let mirrorMatrix = simd_float4x4(
                simd_float4(1.0, 0.0, 0.0, 0.0),
                simd_float4(0.0, -1.0, 0.0, 0.0),
                simd_float4(0.0, 0.0, 1.0, 0.0),
                simd_float4(0.0, 2 * floorY, 0.0, 1.0)
            )
            let reflectionModel = mirrorMatrix * cube.model
            
            cube.draw(renderCommandEncoder, externalModel: reflectionModel)
            
            // 3. 绘制地板（新增）
            var floorDrawType = DrawTypeUniform(objectType: DrawObjectType.floor.rawValue)
            renderCommandEncoder.setVertexBytes(&floorDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&floorDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
                
            // 解绑立方体纹理（index 0）
            renderCommandEncoder.setFragmentTexture(nil, index: 0)
            renderCommandEncoder.setFragmentSamplerState(emptySampler, index: 0)
            
            // 绑定地板纹理（index 1）
            if let floorTexture = floorTexture, let floorSampler = floorSampler {
                renderCommandEncoder.setFragmentTexture(floorTexture, index: 1)
                renderCommandEncoder.setFragmentSamplerState(floorSampler, index: 1)
            }
            
            floor.draw(renderCommandEncoder)

            // 清理地板纹理
            renderCommandEncoder.setFragmentTexture(nil, index: 1)
            renderCommandEncoder.setFragmentSamplerState(emptySampler, index: 1)
            
            // 4. 绘制坐标轴
            var axisDrawType = DrawTypeUniform(objectType: DrawObjectType.coordinateAxis.rawValue)
            renderCommandEncoder.setVertexBytes(&axisDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            renderCommandEncoder.setFragmentBytes(&axisDrawType, length: MemoryLayout<DrawTypeUniform>.stride, index: 3)
            worldAxes.draw(renderCommandEncoder, modelMatrix: simd_float4x4(1))
        }
        
        // MARK: --------------- 公共收尾逻辑 ---------------
        renderCommandEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }


}
