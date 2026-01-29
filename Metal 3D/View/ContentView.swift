//
//  ContentView.swift
//  Metal Startup
//
//  Created by TSAR Weasley on 2023/10/15.
//  Modified by ZQYao on 2025/12/26
//  Modified by ZQYao on 2026/01/02 - Added CameraOrbitManager and orbit rotation button
//  Modified by ZQYao on 2026/01/22 - 完善相机轨道控制逻辑

import simd
import SwiftUI
import Combine

class AutoRotationManager: ObservableObject {
    @Published var isAutoRotating = false
    var rotateStep: Float = .zero
    private var rotationTimer: Timer? // 替换 CADisplayLink 为 Timer
    
    init() {
        setupRotationTimer()
    }
    
    // 配置 Timer（模拟 60fps，macOS/iOS 通用）
    private func setupRotationTimer() {
        // 每 1/60 秒执行一次（≈60fps，流畅度接近 CADisplayLink）
        rotationTimer = Timer(
            fire: .now,
            interval: 1/60,
            repeats: true,
            block: { [weak self] _ in
                guard let self = self, self.isAutoRotating else { return }
                self.onRotate?(self.rotateStep)
            }
        )
        // 添加到主 RunLoop，避免后台暂停
        RunLoop.main.add(rotationTimer!, forMode: .common)
        // 默认暂停 Timer
        rotationTimer?.tolerance = 0.001 // 允许微小误差，提升性能
        pauseTimer()
    }
    
    // 暂停 Timer
    private func pauseTimer() {
        rotationTimer?.fireDate = .distantFuture
    }
    
    // 恢复 Timer
    private func resumeTimer() {
        rotationTimer?.fireDate = .now
    }
    
    // 启停切换
    func toggleAutoRotation() {
        isAutoRotating.toggle()
        if isAutoRotating {
            resumeTimer()
        } else {
            pauseTimer()
        }
    }
    
    // 销毁 Timer（避免内存泄漏）
    deinit {
        rotationTimer?.invalidate()
    }
    
    // 对外暴露的旋转回调
    var onRotate: ((Float) -> Void)?
}

// MARK: - 相机轨道旋转管理器
class CameraOrbitManager: ObservableObject {
    @Published var isOrbiting = false
    var rotateStep: Float = .zero
    private var orbitTimer: Timer?
    
    init() {
        setupOrbitTimer()
    }
    
    // 配置 Timer（模拟 60fps）
    private func setupOrbitTimer() {
        orbitTimer = Timer(
            fire: .distantFuture,  // 不要立即触发
            interval: 1/60,
            repeats: true,
            block: { [weak self] _ in
                guard let self = self, self.isOrbiting else { return }
                self.onOrbit?(self.rotateStep)
            }
        )
        RunLoop.main.add(orbitTimer!, forMode: .common)
        orbitTimer?.tolerance = 0.001
    }
    
    private func pauseTimer() {
        orbitTimer?.fireDate = .distantFuture
    }
    
    private func resumeTimer() {
        orbitTimer?.fireDate = Date().addingTimeInterval(0.0)  // 2秒后开始触发，避免立即跳变
    }
    
    // 启停切换
    func toggleOrbit() {
        isOrbiting.toggle()
        if isOrbiting {
            resumeTimer()
        } else {
            pauseTimer()
            onStop?()    // 触发停止回调
        }
    }
    
    deinit {
        orbitTimer?.invalidate()
    }
    
    // 对外暴露的轨道旋转回调
    var onOrbit: ((Float) -> Void)?
    
    // 轨道停止旋转回调
    var onStop: (() -> Void)?
}

struct ContentView: View {
    @Environment(\.self) private var environment
    @EnvironmentObject private var renderer: Renderer
    @State private var backgroundColor: Color = .black
    
    @State private var offsetX: Float = .zero
    @State private var offsetY: Float = .zero
    @State private var offsetZ: Float = .zero
    
    private var offset: SIMD3<Float> { SIMD3<Float>(offsetX, offsetY, offsetZ) }
    
    @State private var rotateAxisLatitude: Float = 21 * Float.pi / 180
    @State private var rotateAxisLongitude: Float = 45 * Float.pi / 180
    @State private var rotateAngle: Float = .zero
    
    // 自动旋转管理器(立方体)
    @StateObject private var autoRotationVM = AutoRotationManager()
    // 相机轨道旋转管理器
    @StateObject private var cameraOrbitVM = CameraOrbitManager()
    private let rotationControlStep: Float = 0.5 // 旋转控件/自动旋转统一步长（0.5°，度为单位）
    
    // 3D演示阶段的文本标注
    private let demoStageLabels = [
        "实体颜色",
        "纹理贴图",
        "增加光照",
        "增加地板",
        "倒影+天空盒"
    ]
    @State private var highlightedStageIndex = 0  // 当前高亮的阶段索引
    
    private var rotation: simd_quatf {
        simd_quatf(angle: rotateAngle,
                   axis: SIMD3<Float>(
                        cos(rotateAxisLatitude) * cos(rotateAxisLongitude),
                        cos(rotateAxisLatitude) * sin(rotateAxisLongitude),
                        sin(rotateAxisLatitude)
                   )
        )
    }
    
    @State private var scaleX: Float = 0.8
    @State private var scaleY: Float = 0.8
    @State private var scaleZ: Float = 0.8
    
    private var scale: SIMD3<Float> {
        SIMD3<Float>(scaleX, scaleY, scaleZ)
    }
    
    private var rotationAxisVector: SIMD3<Float> {
            SIMD3<Float>(
                cos(rotateAxisLatitude) * cos(rotateAxisLongitude),
                cos(rotateAxisLatitude) * sin(rotateAxisLongitude),
                sin(rotateAxisLatitude)
            )
    }
    private var axisDisplayString: String {
            let x = rotationAxisVector.x.formatted(.number.precision(.integerAndFractionLength(integer: 1, fraction: 2)))
            let y = rotationAxisVector.y.formatted(.number.precision(.integerAndFractionLength(integer: 1, fraction: 2)))
            let z = rotationAxisVector.z.formatted(.number.precision(.integerAndFractionLength(integer: 1, fraction: 2)))
            return "(\(x), \(y), \(z))"
    }
    
    // 格式化相机位置字符串（保留2位小数）
    private var cameraPositionString: String {
        guard let camera = renderer.camera else {
            return "Pos(0.00, 0.00, 0.00)" // 兜底默认值
        }
        let x = camera.position.x.formatted(
            .number.precision(.integerAndFractionLength(integer: 1, fraction: 2))
        )
        let y = camera.position.y.formatted(
            .number.precision(.integerAndFractionLength(integer: 1, fraction: 2))
        )
        let z = camera.position.z.formatted(
            .number.precision(.integerAndFractionLength(integer: 1, fraction: 2))
        )
        return "Pos(\(x), \(y), \(z))"
    }
    
    // 格式化相机姿态字符串（yaw/pitch/roll 角度单位，行业通用顺序）
    private var cameraAttitudeString: String {
        guard let camera = renderer.camera else {
                return "Att(0.0, 0.0, 0.0)" // 兜底默认值
        }
        let yaw = camera.yaw.formatted(
            .number.precision(.integerAndFractionLength(integer: 3, fraction: 1))
        )
        let pitch = camera.pitch.formatted(
            .number.precision(.integerAndFractionLength(integer: 2, fraction: 1))
        )
        let roll = camera.roll.formatted(
            .number.precision(.integerAndFractionLength(integer: 2, fraction: 1))
        )
        return "Att(\(yaw), \(pitch), \(roll))"
        //return "Att(\(yaw), \(camera.yaw))"
    }
    
    private func cycleDemoStage() {
        // 循环更新高亮索引（0→1→2→3→4→5→0）
        highlightedStageIndex = (highlightedStageIndex + 1) % demoStageLabels.count
        // 同步更新Renderer的8bit无符号整数属性
        renderer.demoStage = UInt8(highlightedStageIndex)
    }
    
    var body: some View {
        HStack (spacing: 0) {
            ScrollView {
                VStack {
                    ColorPicker(selection: $backgroundColor, label: {
                        Text("Background Color")
                    })
                    Spacer(minLength: 8)
                    
                     GroupBox(label: Text("Camera Info")) {
                         VStack(spacing: 4) {
                             Text(cameraPositionString)
                                 .monospaced() // 等宽字体，对齐更整齐
                                 .frame(width: 200, alignment: .leading)
                             Text(cameraAttitudeString)
                                 .monospaced()
                                 .frame(width: 200, alignment: .leading)
                             Text(renderer.orbitStatus)
                                 .font(.caption)
                                 .foregroundColor(cameraOrbitVM.isOrbiting ? .blue : .gray)
                                 .frame(width: 200, alignment: .leading)
                             Text("移动相机位置：")
                                 .font(.caption)
                                 .frame(width: 200, alignment: .leading)
                             Text("W/S(前后)A/D(左右)Q/E(上下)")
                                 .font(.caption)
                                 .frame(width: 200, alignment: .leading)
                             Text("拖动鼠标改变相机视角")
                                 .font(.caption)
                                 .frame(width: 200, alignment: .leading)
                         }.padding(.vertical, 4)
                     }.padding(.bottom, 12)
                    
                    Button(action: autoRotationVM.toggleAutoRotation) {
                        Text(autoRotationVM.isAutoRotating ? "停止自动旋转" : "开始自动旋转")
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(autoRotationVM.isAutoRotating ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }.padding(.bottom, 10)
                    
                    // MARK: - 新增：相机轨道旋转按钮
                    Button(action: cameraOrbitVM.toggleOrbit) {
                        Text(cameraOrbitVM.isOrbiting ? "停止相机轨道" : "开始相机轨道")
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(cameraOrbitVM.isOrbiting ? Color.orange : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }.padding(.bottom, 16)
                    
                    GroupBox(label: Text("Offset")) {
                        VStack(spacing: 8) {
                            FloatPicker(value: $offsetX, range: -2...2, label: "X", step: 0.1)
                            FloatPicker(value: $offsetY, range: -2...2, label: "Y", step: 0.1)
                            FloatPicker(value: $offsetZ, range: -2...2, label: "Z", step: 0.1)
                        }.padding(.vertical, 4)
                    }.padding(.bottom, 12)
                    
                    GroupBox(label: Text("Rotation")) {
                        VStack(spacing: 8) {
                            FloatPicker(value: $rotateAxisLatitude,  range: -Float.pi/2...Float.pi/2, label: "LA", step:  rotationControlStep)
                            FloatPicker(value: $rotateAxisLongitude, range: -Float.pi...Float.pi,     label: "LO", step:  rotationControlStep)
                            FloatPicker(value: $rotateAngle,         range: -Float.pi...Float.pi,     label: "AN", step:  rotationControlStep)
                            Text("轴\(axisDisplayString)")
                                .monospaced()
                                .frame(minWidth: 53, alignment: .leading)
                        }.padding(.vertical, 4)
                    }.padding(.bottom, 12)
                    
                    GroupBox(label: Text("Scale")) {
                        VStack(spacing: 8) {
                            FloatPicker(value: $scaleX, range: -1...2, label: "SX", step: 0.1)
                            FloatPicker(value: $scaleY, range: -1...2, label: "SY", step: 0.1)
                            FloatPicker(value: $scaleZ, range: -1...2, label: "SZ", step: 0.1)
                        }.padding(.vertical, 4)
                    }
                    
                    Spacer()
                    HStack {
                        Text(String(format: "%6.2f FPS", renderer.fps)).font(.caption.monospaced())
                        Text("\(Int(renderer.resolution.width)) X \(Int(renderer.resolution.height))").font(.caption)
                    }
                }.padding()
            }.frame(width: 250)
            
            VStack(spacing: 8) {
                MetalView()
                    .focusable()
                    .gesture(DragGesture(minimumDistance: .zero, coordinateSpace: .local)
                        .onChanged { _ in
                            renderer.controller.viewLock = false
                            renderer.controller.motionLock = false
                        }.onEnded { _ in
                            renderer.controller.viewLock = true
                            renderer.controller.motionLock = true
                        }
                    )
                    .onKeyPress(characters: ["w", "s", "a", "d", "e", "q", " "], phases: [.up, .down]) { event in
                        if event.characters == " " && event.phase == .down {
                            cycleDemoStage()
                            return .handled
                        }
                        if let char = event.characters.first, let direction = FPSController.Direction(rawValue: char) {
                            if event.phase == .down {
                                renderer.controller.movingDirections.insert(direction)
                            } else if event.phase == .up {
                                renderer.controller.movingDirections.remove(direction)
                            }
                        }
                        return .handled
                    }
                HStack(spacing: 6) {
                                    ForEach(0..<demoStageLabels.count, id: \.self) { index in
                                        Text(demoStageLabels[index])
                                            .font(.caption)
                                            .frame(minWidth: 60, minHeight: 32)
                                            .background(highlightedStageIndex == index ? Color.blue : Color.gray.opacity(0.5))
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                            .border(Color.white.opacity(0.4), width: 1)
                                    }
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: backgroundColor) {
            renderer.backgroundColor = backgroundColor.resolve(in: environment)
        }
        .onChange(of: offset) {
            renderer.cube.translation = offset
        }
        .onChange(of: rotation) {
            renderer.cube.rotation = rotation
        }
        .onChange(of: scale) {
            renderer.cube.scaling = scale
        }
        .onAppear {
            autoRotationVM.rotateStep = self.rotationControlStep
            autoRotationVM.onRotate = { angleStep in
                 self.rotateAngle += angleStep * Float.pi / 180.0 // 累加旋转角度（转换为弧度）
                 if self.rotateAngle > Float.pi {
                     self.rotateAngle -= 2 * Float.pi
                 } else if self.rotateAngle < -Float.pi {
                     self.rotateAngle += 2 * Float.pi
                 }
             }
            // MARK: - 新增：相机轨道旋转回调
            cameraOrbitVM.rotateStep = self.rotationControlStep
            cameraOrbitVM.onOrbit = { angleStep in
                renderer.updateCameraOrbit(angleStep: angleStep)
            }
            cameraOrbitVM.onStop = { renderer.stopOrbit() }

        }
    }
}

#Preview {
    ContentView()
        .environmentObject(Renderer())
}
