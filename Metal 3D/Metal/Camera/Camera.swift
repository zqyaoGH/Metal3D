//
//  Camera.swift
//  Metal 3D
//
//  Created by TSAR Weasley on 2023/11/9.
//  Modified by ZQYao on 2025/12/26
//
// FPSController 是 “交互层”：处理鼠标（视角）、键盘（移动），只负责 “操作相机”，不关心渲染:
// 用户动鼠标 / 按键盘 → FPSController 接收输入, 控制器更新Camera的角度（yaw/pitch）和位置（position）
//
// Camera 是 “计算层”：定义相机状态，计算 view/projection 矩阵，是 3D 渲染视角的核心:
// Camera 实时计算 view/projection 矩阵；
//
//  渲染器（Renderer）把这两个矩阵传给 Metal 着色器，最终渲染出对应视角的 3D 画面。
//  Modified by ZQYao 2026/01/08
//  核心功能：实现第一人称相机的交互控制（鼠标/键盘）和 3D 视角矩阵计算
//  适配 Metal 左手坐标系，遵循“Yaw-水平转向、Pitch-俯仰、Roll-横滚”的标准欧拉角定义
//

import simd
import SwiftUI

// MARK: - FPSController：第一人称相机交互控制器
/// 负责处理鼠标/键盘输入，更新相机的位置和角度（仅交互逻辑，不涉及渲染）
/// 核心职责：
/// 1. 鼠标/触控板输入 → 更新相机的 yaw（水平）/pitch（俯仰）角度
/// 2. 键盘 WASDEQ 输入 → 更新相机的世界坐标位置
class FPSController {      // 第一人称控制器
    /// 关联的相机实例（无主引用，避免循环引用）
    unowned var camera: Camera
    /// 记录上一帧的鼠标位置，用于计算鼠标偏移量
    var mouse: CGPoint?
    
    /// 视角锁定开关（true：锁定视角，false：允许鼠标控制视角）
    var viewLock = true
    /// 移动锁定开关（true：锁定移动，false：允许键盘控制移动）
    var motionLock = true
    
    /// 键盘移动方向枚举（映射 WASDEQ 键）
    enum Direction: Character {
        case forward = "w"      // 向前（水平方向）
        case backward = "s"     // 向后（水平方向）
        case left = "a"         // 向左
        case right = "d"        // 向右
        case up = "e"           // 向上（垂直方向）
        case down = "q"         // 向下（垂直方向）
    }
    
    /// 当前按下的移动方向集合（支持多方向同时按下，如 W+D 斜向移动）
    var movingDirections: Set<Direction> = []
    
    // MARK: 初始化
    init(camera: Camera) {
        self.camera = camera
    }
    
    // MARK: 帧更新
    /// 每帧调用，更新鼠标视角和键盘移动
    ///  - Parameter deltaT: 帧间隔时间（秒），用于移动速度的时间归一化
    func update(_ deltaT: Float) {
        updateMouse()
        updateMotion(deltaT)
    }
    
    func normalizeAngle(_ angle: Float) -> Float {
        var normalized = fmod(angle, 360.0)
        if normalized > 180.0 {
            normalized -= 360.0
        } else if normalized <= -180.0 {
            normalized += 360.0
        }
        return normalized
    }
    
    // MARK: 私有方法 - 处理鼠标/触控板输入
    private func updateMouse() {
        if let mouse {
            let currentMouseLocation = NSEvent.mouseLocation
            
            // 视角未锁定时，计算鼠标偏移并更新相机角度
            if !viewLock {
                let dx = Float(currentMouseLocation.x - mouse.x) // 水平偏移（X轴）
                let dy = Float(currentMouseLocation.y - mouse.y) // 垂直偏移（Y轴）
                
                // 更新水平视角（Yaw）：左滑→视角左移，右滑→视角右移，灵敏度 0.1，并归一化到-180°到180°的范围
                camera.yaw = camera.yaw - dx * 0.1
                camera.yaw = normalizeAngle(camera.yaw)
                // 更新俯仰视角（Pitch）：上滑→视角上移，下滑→视角下移，限制范围 [-89°, 89°] 避免视角翻转
                camera.pitch = camera.pitch + dy * 0.1
                camera.pitch = max(-89, min(89, camera.pitch))
            }
            
            // 更新鼠标位置为当前位置，供下一帧计算偏移
            self.mouse = currentMouseLocation
        } else {
            // 首次记录鼠标位置
            mouse = NSEvent.mouseLocation
        }
    }
    
    // MARK: 私有方法 - 处理键盘移动输入
    /// 根据按下的方向键，计算相机的移动向量并更新位置
    /// - Parameter deltaT: 帧间隔时间（秒），保证移动速度与帧率无关
    private func updateMotion(_ deltaT: Float) {
        var dir = SIMD3<Float>.zero     // 最终移动方向向量
        
        for direction in movingDirections {
            // 先定义当前方向的分量
            var directionComponent = SIMD3<Float>.zero
            
            switch direction {
            case .forward:
                // 向前：取相机前方向，仅保留水平分量（X/Z）并归一化
                var horizontalFront = camera.front
                horizontalFront.y = 0
                directionComponent = normalize(horizontalFront)

            case .backward:
                // 向后：向前方向的反方向
                var horizontalFront = camera.front
                horizontalFront.y = 0
                directionComponent = -normalize(horizontalFront) // 直接归一化
                
            case .up:
                // 向上：纯垂直方向（世界Y轴正方向）
                directionComponent = SIMD3<Float>(0, 1, 0)
                
            case .down:
                // 向下：纯垂直方向（世界Y轴负方向）
                directionComponent = SIMD3<Float>(0, -1, 0)
                
            case .right:
                // 向右：相机的右方向（基于当前视角）
                directionComponent = camera.right
                
            case .left:
                // 向左：相机右方向的反方向
                directionComponent = -camera.right
            }
           dir = dir + directionComponent
        }
        
        if length(dir) > 0 {
            let velocity = normalize(dir)
            
            camera.position = camera.position + velocity * deltaT
        }
    }
}

// MARK: - Camera：3D 相机核心类
/// 定义相机的状态（位置、角度），计算视图矩阵（View）和投影矩阵（Projection）
/// 核心职责：
/// 1. 存储相机的世界坐标、欧拉角（Yaw/Pitch/Roll）
/// 2. 实时计算相机的前/右/上方向向量（基于欧拉角）
/// 3. 计算 Metal 渲染所需的 View 矩阵和 Projection 矩阵
/// 4. 提供 lookAt 方法，让相机快速朝向指定目标点
class Camera {
    // MARK: 欧拉角（单位：角度°，最终计算时转为弧度）
    var yaw: Float = .zero      // 偏航角：绕 Y 轴旋转（水平转向，左/右）
    var pitch: Float = .zero    // 俯仰角：绕 X 轴旋转（垂直转向，上/下）
    var roll: Float = .zero     // 横滚角：绕 Z 轴旋转（画面倾斜，默认不用）
    
    // MARK: 相机方向向量（基于欧拉角实时计算）
    // 直接从欧拉角计算方向向量（适配 Metal 左手坐标系）
    // MARK: 相机方向向量（基于欧拉角实时计算）
    var right: SIMD3<Float> { euler.columns.0 }   // 相机右方向（X 轴，列向量）
    var front: SIMD3<Float> { euler.columns.2 }   // 相机前方向（Z 轴，列向量）
    var up   : SIMD3<Float> { euler.columns.1 }   // 相机上方向（Y 轴，列向量）
    
    // MARK: 相机位置（世界坐标系）
    var position: SIMD3<Float> = .zero
    
    // MARK: 投影矩阵参数
    var fov: Float = 45         // 垂直视场角（°）
    var aspectRatio: Float = 1  // 屏幕宽高比（宽/高）
    var near: Float = 0.1       // 近裁剪面（距离相机最近可见距离）
    var far: Float = 100        // 远裁剪面（距离相机最远可见距离）
    
    // MARK: 投影矩阵（Projection）
    /// 计算透视投影矩阵（适配 Metal 左手坐标系）
    /// 作用：将 3D 世界坐标转换为 2D 裁剪空间坐标
    var projection: simd_float4x4 {
        let tangentTheta = tan(fov * Float.pi / 360)    // tan(FOV/2)
        let tangentPhi = tangentTheta * aspectRatio     // 水平方向tan值（适配宽高比）
        
        return simd_float4x4(
            SIMD4<Float>(1 / tangentPhi, 0, 0, 0),
            SIMD4<Float>(0, 1 / tangentTheta, 0, 0),
            SIMD4<Float>(0, 0, -far / (far - near), -1),
            SIMD4<Float>(0, 0, -far * near / (far - near), 0)
        )
    }
    
    // MARK: 视图矩阵（View）
    /// 计算视图矩阵（相机的“观察矩阵”）
    /// 作用：将世界坐标系转换为相机局部坐标系（模拟“相机看世界”的效果）
    /// 计算逻辑：平移矩阵（相机位置取反） + 旋转矩阵（基于欧拉角）
    var view: simd_float4x4 {
        // 1. 平移矩阵：将世界原点移到相机位置（相机位置取反）
        var translateMatrix = simd_float4x4(1)
        translateMatrix[3] = SIMD4<Float>(-position, 1)

        // 2. 旋转矩阵：基于欧拉角（Yaw→Pitch→Roll）构建，适配 Metal 左手坐标系
        let yawRad = yaw * Float.pi / 180
        let pitchRad = pitch * Float.pi / 180
        let rollRad = roll * Float.pi / 180

        // 绕 Y 轴旋转矩阵（Yaw，左手坐标系适配）
        let yawMat = simd_float3x3(
            SIMD3<Float>(cos(yawRad), 0, sin(yawRad)),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(-sin(yawRad), 0, cos(yawRad))
        )

        // 绕 X 轴旋转矩阵（Pitch）
        let pitchMat = simd_float3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, cos(pitchRad), -sin(pitchRad)),
            SIMD3<Float>(0, sin(pitchRad),  cos(pitchRad))
        )

        // 绕 Z 轴旋转矩阵（Roll，左手坐标系修正）
        let rollMat = simd_float3x3(
            SIMD3<Float>(cos(rollRad), -sin(rollRad), 0),
            SIMD3<Float>(sin(rollRad), cos(rollRad), 0),
            SIMD3<Float>(0, 0, 1)
        )

        // 欧拉角矩阵乘法顺序：Pitch × Yaw × Roll（FPS 视角的正确顺序）
        let rotate3x3 = pitchMat * yawMat * rollMat

        // 3. 3x3 旋转矩阵转为 4x4 矩阵（Metal 要求 4x4 矩阵，列主序赋值）
        var rotateMatrix = simd_float4x4(1)
        rotateMatrix.columns.0 = SIMD4<Float>(rotate3x3.columns.0, 0) // 按列赋值
        rotateMatrix.columns.1 = SIMD4<Float>(rotate3x3.columns.1, 0)
        rotateMatrix.columns.2 = SIMD4<Float>(rotate3x3.columns.2, 0)
        rotateMatrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)

        // 4. 视图矩阵 = 旋转矩阵 × 平移矩阵（列主序矩阵乘法顺序）
        return rotateMatrix * translateMatrix
    }
    
    // MARK: 私有方法 - 计算欧拉角旋转矩阵
    /// 基于 Yaw/Pitch/Roll 计算 3x3 旋转矩阵，用于推导相机的前/右/上方向
    private var euler: simd_float3x3 {
        let yawRad = yaw * Float.pi / 180
        let pitchRad = pitch * Float.pi / 180
        let rollRad = roll * Float.pi / 180

        // 绕 Y 轴旋转矩阵（与 view 矩阵中保持一致）
        let yawMat = simd_float3x3(
            SIMD3<Float>(cos(yawRad), 0, sin(yawRad)),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(-sin(yawRad), 0, cos(yawRad))
        )

        // 绕 X 轴旋转矩阵
        let pitchMat = simd_float3x3(
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, cos(pitchRad), -sin(pitchRad)),
            SIMD3<Float>(0, sin(pitchRad), cos(pitchRad))
        )

        // 绕 Z 轴旋转矩阵（左手坐标系修正）
        let rollMat = simd_float3x3(
            SIMD3<Float>(cos(rollRad), -sin(rollRad), 0),
            SIMD3<Float>(sin(rollRad), cos(rollRad), 0),
            SIMD3<Float>(0, 0, 1)
        )

        // 欧拉角矩阵乘法顺序：Pitch × Yaw × Roll（尝试不同的顺序）
        let rotate3x3 = pitchMat * yawMat * rollMat

        return rotate3x3
    }
    
    // MARK: 相机朝向控制 - lookAt（基础版）
    /// 让相机朝向指定目标点，自动计算 Yaw 和 Pitch 角度
    /// - Parameter target: 目标点的世界坐标
    func lookAt(target: SIMD3<Float>) {
        // 计算相机到目标点的方向向量（归一化）
        let direction = normalize(target - position)
        
        // 计算 Yaw（水平角）：atan2(Z, X) 适配 Metal 左手坐标系（修正）
        yaw = atan2(direction.z, direction.x) * 180 / Float.pi
        
        // 计算 Pitch（俯仰角）：asin(Y) 限制在 [-90°, 90°]
        pitch = asin(direction.y) * 180 / Float.pi
        
        // 横滚角重置为 0（避免画面倾斜）
        roll = 0
    }
    
    // MARK: 相机朝向控制 - lookAt（进阶版，避免视角颠倒）
    /// 让相机朝向指定目标点，指定上方向，避免俯仰角过大导致视角颠倒
    /// - Parameters:
    ///   - target: 目标点的世界坐标
    ///   - up: 相机的上方向（默认世界 Y 轴，保证画面始终"朝上"）
    func lookAt(target: SIMD3<Float>, up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) {
        // 1. 计算相机到目标的视线方向（归一化）
        let forward = normalize(target - position)

        // 2. 计算相机右方向（基于指定的上方向，确保水平）
        let rightDir = normalize(cross(up, forward))
        // 3. 重新计算相机真实上方向（正交于视线和右方向，避免颠倒）
        let cameraUp = cross(forward, rightDir)

        // 4. 计算水平视线方向（仅 X/Z 分量，去掉俯仰影响）
        let horizontalForward = SIMD3<Float>(forward.x, 0, forward.z)
        let horizontalForwardNorm = normalize(horizontalForward)

        // 5. 计算 Yaw（仅基于水平视线，避免俯仰干扰）
        // 修正：使用 atan2(z, x) 适配 Metal 左手坐标系
        yaw = atan2(horizontalForwardNorm.z, horizontalForwardNorm.x) * 180 / Float.pi

        // 6. 计算 Pitch（限制范围 [-89°, 89°]，彻底避免视角翻转）
        pitch = asin(forward.y) * 180 / Float.pi
        pitch = max(-89, min(89, pitch))

        // 7. 强制roll为0，彻底避免横滚颠倒
        roll = 0


    }
}
