# Metal 3D 技术文档

## 1. 架构概览

本项目是一个基于 SwiftUI 和 Metal 的 3D 渲染教程应用，演示了先进的图形渲染技术。整体架构分为三层：

- **SwiftUI 层**：负责用户界面控件、状态管理和 Metal 视图集成。核心文件包括 `Metal_3DApp.swift`（应用入口）、`ContentView.swift`（主界面）和 `MetalView.swift`（Metal 视图桥接）。
- **Metal 层**：处理 GPU 渲染管道、着色器执行和几何体绘制。核心文件为 `Renderer.swift`，负责 Metal 设备初始化、渲染循环和资源管理。
- **核心组件**：包括相机系统（`Camera.swift`、`FPSController`）、几何类（`Cube.swift`、`Plane.swift` 等）、纹理加载器（`Texture2DLoader.swift`、`CubeTextureLoader.swift`）和数据结构（`Data.swift`）。

## 2. 核心渲染管道

Metal 渲染管道在 `Renderer.swift:initWithView()` 中初始化：

- **设备和队列**：使用 `MTLCreateSystemDefaultDevice()` 获取 Metal 设备，创建命令队列用于提交渲染指令。
- **着色器管道**：加载 `shader.metal` 中的顶点和片段着色器，配置渲染管道状态，包括颜色附件、深度附件和 Alpha 混合。
- **深度测试和混合**：启用深度写入和小于比较函数；配置 Alpha 混合用于透明渲染。
- **渐进式渲染**：根据 `demoStage` 变量（0-4），在 `draw()` 方法中条件渲染不同阶段的对象。

## 3. 几何系统

几何系统基于继承的 `Geometry` 基类，提供统一的变换支持（平移、旋转、缩放）。

- **Cube**（`Cube.swift`）：立方体几何，支持立方体纹理映射。静态初始化顶点和索引缓冲区。
- **Plane**（`Plane.swift`）：地板平面，位置固定在 y=-0.7，支持 2D 纹理和半透明渲染。
- **SkyBox**（`SkyBox.swift`）：天空盒，使用内向渲染（索引顺序相反），跟随相机位置。
- **WorldAxes**（`WorldAxes.swift`）：世界坐标轴，使用线图元渲染 RGB 轴线。
- **缓冲区管理**：所有几何类使用静态缓冲区共享顶点/索引数据，减少内存占用。

## 4. 着色器系统

着色器使用 Metal Shading Language 编写，位于 `shader.metal`。

- **顶点着色器**：计算世界空间位置、法线变换、相机位置提取。使用 3x3 矩阵求逆函数处理法线矩阵。
- **片段着色器**：多分支渲染逻辑，根据 `demoStage` 和 `objectType` 执行不同渲染：
  - 阶段 0：纯色渲染
  - 阶段 1：立方体纹理采样
  - 阶段 2：添加 Phong 光照
  - 阶段 3+：地板纹理、天空盒和反射效果
- **优化**：自定义 3x3 矩阵求逆避免依赖外部库，计算 Phong 光照模型（环境光 + 漫反射 + 镜面反射）。

## 5. 光照和材质

- **Phong 模型**：在片段着色器中实现，包含环境光、漫反射和镜面反射。光源参数在 `Renderer.swift:36-42` 定义。
- **环境反射**：使用天空盒纹理采样反射方向，实现表面镜面反射效果。
- **镜像反射**：通过镜像矩阵变换创建地板倒影，结合 Alpha 混合实现半透明效果。

## 6. 相机和控件

- **Camera 类**（`Camera.swift`）：计算视图和投影矩阵。支持欧拉角（Yaw/Pitch/Roll）控制，适应 Metal 左手坐标系。
- **FPSController**：处理键盘（WASD + EQ）和鼠标输入，更新相机位置和角度。使用角度归一化和坐标系转换。
- **轨道模式**：在 `Renderer.swift:updateCameraOrbit()` 中实现，允许相机围绕场景旋转。

## 7. 纹理管理

- **立方体纹理**：`CubeTextureLoader.loadCubeTexture()` 加载 6 个面纹理，创建 `MTLTextureType.typeCube`。
- **2D 纹理**：`Texture2DLoader.loadFromAssets()` 从 Assets 加载，翻转 Y 轴适配 Metal 坐标系。
- **采样器配置**：不同纹理类型使用不同采样器（线性过滤、重复模式等）。

## 8. 定时器和异步处理

项目使用 macOS `Timer` 类实现定时功能，主要在 `ContentView.swift` 的管理器类中：

- **AutoRotationManager** 和 **CameraOrbitManager**：使用 `Timer` 模拟 60fps 动画。
- **初始化**：在 `setupRotationTimer()` 中配置 Timer，添加到主 RunLoop，避免后台暂停。
- **状态管理**：通过 `fireDate` 控制暂停/恢复，`invalidate()` 销毁避免内存泄漏。
- **应用**：定时器驱动立方体自动旋转和相机轨道运动，提供平滑动画效果。

## 9. Swift 匿名函数（闭包）技术细节

Swift 匿名函数即闭包，用于事件处理和异步回调。

- **语法**：`{ [weak self] (参数) -> 返回类型 in 代码 }`，支持捕获列表避免循环引用。
- **项目示例**：
  - Timer block：`{ [weak self] _ in guard let self = self else { return }; self.onRotate?(self.rotateStep) }`（`ContentView.swift:31-34`）
  - 事件回调：`cameraOrbitVM.onOrbit = { angleStep in renderer.updateCameraOrbit(angleStep: angleStep) }`（`ContentView.swift:82-85`）
- **优势**：简化异步代码，提高可读性。使用 `[weak self]` 防止内存泄漏。
- **模式**：尾随闭包语法，非逃逸闭包用于同步回调，逃逸闭包用于异步操作。

## 10. Xcode 项目文件和配置

- **.entitlements 文件**：定义应用权限和功能，项目中 `Metal_3D.entitlements` 当前为空（无特殊权限）。
- **作用**：告诉 iOS/macOS 系统应用需要哪些特权，如访问硬件或服务。
- **在项目中的体现**：用于配置 macOS 应用的权限，确保应用能正常运行所需的功能。

## 11. SwiftUI 视图生命周期管理

- **.onAppear 修饰符**：视图首次出现时执行，用于初始化设置（如绑定回调、配置定时器）。
- **.onChange 修饰符**：监听状态变化时执行，用于响应式更新（如同步 renderer 属性）。
- **异同**：.onAppear 一次性触发（初始化），.onChange 响应式触发（动态更新）；均用于增强视图功能。
- **在项目中的应用**：`ContentView.swift` 中使用 .onAppear 设置定时器回调，使用 .onChange 更新渲染器状态。

## 12. 相机轨道和定时器交互

- **按钮逻辑**：相机轨道按钮直接调用 `toggleOrbit()`，内部处理状态切换和定时器启停。
- **定时器机制**：使用 Timer 实现 60fps 轨道旋转，通过闭包回调更新相机位置。
- **系统流程**：按钮按下 → `toggleOrbit()` → `resumeTimer()` → 定时器触发 → `onOrbit` 回调 → `updateCameraOrbit()` → 相机更新。

## 13. Swift 编程概念深入

- **Timer block 作用**：定时执行逻辑，避免内存泄漏，通过回调驱动异步更新。
- **闭包解析**：`{ [weak self] _ in guard let self = self, self.isOrbiting else { return }; self.onOrbit?(self.rotateStep) }` 的逐行解释。
- **捕获列表概念**：控制变量捕获方式，`[weak self]` 避免循环引用，确保安全释放。

## 14. 代码注释教学增强

项目代码已重组注释，采用中英文混合风格，面向学习者提供详细教学解释：
- **核心概念**：如Phong光照、视图矩阵（View Matrix）、深度测试等，解释“为什么”和“如何”。
- **学习要点**：每个复杂部分添加总结，如“为什么用极坐标？轨道是圆形”。
- **文件覆盖**：Renderer.swift（渲染逻辑）、shader.metal（着色器数学）、几何类等均有增强。
- **教学价值**：适合Metal 3D初学者，逐步理解GPU渲染流程。详见代码中的// 学习要点注释。