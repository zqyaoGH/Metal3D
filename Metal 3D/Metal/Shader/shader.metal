//
//  shader.metal
//  Metal Startup
//
//  Created by TSAR Weasley on 2023/10/15.
//  Modified by ZQYao on 2025/12/29
//

#include <metal_stdlib>
using namespace metal;

enum DrawObjectType: uint {
    Cube = 0,
    CoordinateAxis = 1,
    Floor = 2,
    CubeReflection = 3,
    SkyBox = 4
};

struct Vertex {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
    float3 normal   [[attribute(2)]];  // 顶点所在面法线
    float2 textureCoordinate [[attribute(3)]]; // 地板纹理坐标
};

struct Uniform {
    float4x4 view;
    float4x4 projection;
};

// 管理绘制类型的Uniform
struct DrawTypeUniform {
    DrawObjectType objectType;
};

struct DemoStageUniform {
    uchar demoStage; // 3D效果演示阶段
};

struct LightUniform {
    float3 position;
    float3 ambient;
    float3 diffuse;
    float3 specular;
    float shininess;
    float padding;
};

// 修改顶点输出结构体：替换color为worldPos（用于立方体纹理采样）
struct RasterizerData {
    float4 position [[position]];
    float3 localPos; // 传递局部空间位置 worldPos; // 世界空间位置 → 作为Cube Map的采样方向向量
    float4 color;
    float3 worldPos;       // 世界空间位置（光照计算用）
    float3 worldNormal;    // 世界空间法线（光照计算用）
    float3 viewPos;        // 相机位置（光照计算用）
    float2 textureCoordinate; // 传递纹理坐标到片段着色器
};

// 实现3*3矩阵求逆的逻辑（用于法线变换，避免非均匀缩放导致的错误光照）
float3x3 inverse_3x3(float3x3 m) {
    // 学习要点：为什么需要矩阵逆？法线变换用模型矩阵的逆转置，以保持垂直性
    // 步骤1：计算3x3矩阵的行列式（determinant，判断矩阵是否可逆）
    float det = m[0].x * (m[1].y * m[2].z - m[1].z * m[2].y)
              - m[0].y * (m[1].x * m[2].z - m[1].z * m[2].x)
              + m[0].z * (m[1].x * m[2].y - m[1].y * m[2].x);
    
    // 避免除0（行列式接近0时返回单位矩阵，不影响立方体场景）
    if (abs(det) < 1e-6) {
        return float3x3(1.0); // 单位矩阵
    }
    
    // 步骤2：计算伴随矩阵（余子式矩阵的转置）
    float3x3 adjugate;
    adjugate[0].x = (m[1].y * m[2].z - m[1].z * m[2].y);
    adjugate[0].y = -(m[0].y * m[2].z - m[0].z * m[2].y);
    adjugate[0].z = (m[0].y * m[1].z - m[0].z * m[1].y);
    
    adjugate[1].x = -(m[1].x * m[2].z - m[1].z * m[2].x);
    adjugate[1].y = (m[0].x * m[2].z - m[0].z * m[2].x);
    adjugate[1].z = -(m[0].x * m[1].z - m[0].z * m[1].x);
    
    adjugate[2].x = (m[1].x * m[2].y - m[1].y * m[2].x);
    adjugate[2].y = -(m[0].x * m[2].y - m[0].y * m[2].x);
    adjugate[2].z = (m[0].x * m[1].y - m[0].y * m[1].x);
    
    // 步骤3：逆矩阵 = 伴随矩阵 / 行列式
    return adjugate / det;
}

[[vertex]] RasterizerData vertexShader(
    Vertex in [[stage_in]],
    constant float4x4& model [[buffer(1)]],
    constant Uniform& uniform [[buffer(2)]],
    constant DrawTypeUniform& drawType [[buffer(3)]],
    constant DemoStageUniform& demoStage [[buffer(4)]]
) {
    RasterizerData out;
    
    // 计算世界空间位置
    float4 worldPos = model * float4(in.position, 1.0);
    out.worldPos = float3(worldPos);
    
    // 计算裁剪空间位置
    out.position = uniform.projection * uniform.view * worldPos;
    
    // 计算世界空间法线(使用模型矩阵的逆运算)
    float3x3 model3x3 = float3x3(model[0].xyz, model[1].xyz, model[2].xyz);
    float3x3 normalMatrix = transpose(inverse_3x3(model3x3));
    float3 transformedNormal = normalMatrix * in.normal;
    out.worldNormal = normalize(normalize(transformedNormal));
    
    // 传递相机位置(视图矩阵的逆矩阵提取)
    float3x3 viewRotation = float3x3(
            uniform.view.columns[0].xyz,
            uniform.view.columns[1].xyz,
            uniform.view.columns[2].xyz
        );
    float3 viewTranslation = uniform.view.columns[3].xyz;
    out.viewPos = -(viewRotation * viewTranslation);
    
    // 计算裁剪空间位置（保留，不影响交互）
    out.localPos = in.position;
    out.color = in.color;
    
    out.textureCoordinate = in.textureCoordinate;
    
    return out;
}

// 实现Phong光照计算函数（模拟真实世界光照的基本模型）
float4 calculatePhongLight(
    float4 baseColor,
    float3 worldPos,
    float3 worldNormal,
    float3 viewPos,
    constant LightUniform& light
) {
    // 学习要点：Phong模型分解为环境光（ambient）+漫反射（diffuse）+镜面反射（specular），简单高效
    // 1. 环境光
    float3 ambient = light.ambient * float3(baseColor);
    
    // 2. 漫反射
    float3 lightDir = normalize(light.position - worldPos);
    float3 normal = normalize(worldNormal);
    float diff = max(dot(normal, lightDir), 0.0);
    float3 diffuse = light.diffuse * diff * float3(baseColor);
    
    // 3. 镜面反射
    float3 viewDir = normalize(viewPos - worldPos);
    float3 reflectDir = reflect(-lightDir, normal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), light.shininess);
    float3 specular = light.specular * spec;
    
    // 合并光照结果
    float3 result = clamp(ambient + diffuse + specular, 0.0, 1.0);
    return float4(result, baseColor.a);
}

[[fragment]] float4 fragmentShader(
    RasterizerData in [[stage_in]],
    texturecube<float> cubeMap [[texture(0)]],    // 立方体纹理
    sampler cubeSampler [[sampler(0)]],            // 立方体纹理采样器
    texture2d<float> floorTexture [[texture(1)]], // 地板纹理（index1）
    sampler floorSampler [[sampler(1)]],          // 地板采样器（index1）
    texturecube<float> skyBoxMap [[texture(2)]],  // 天空盒纹理（index2）
    constant DrawTypeUniform& drawType [[buffer(3)]],
    constant DemoStageUniform& demoStage [[buffer(4)]],
    constant LightUniform& light [[buffer(5)]]
) {
    float4 finalColor;
    
    if ( demoStage.demoStage == uchar(0) ) {
        return in.color;
    } else if (demoStage.demoStage == uchar(1)) {
        if (drawType.objectType == DrawObjectType::Cube) {
            float3 sampleDir = normalize(float3(in.localPos.x, -in.localPos.y, in.localPos.z)); // 归一化方向向量，确保采样精度
            finalColor = cubeMap.sample(cubeSampler, sampleDir);
        } else {
            finalColor = in.color;
        }
    } else if (demoStage.demoStage == uchar(2)) {
        if (drawType.objectType == DrawObjectType::Cube) {
            // 纹理颜色作为基础色
            float3 sampleDir = normalize(float3(in.localPos.x, -in.localPos.y, in.localPos.z));
            float4 textureColor = cubeMap.sample(cubeSampler, sampleDir);
            // 应用光照计算
            finalColor = calculatePhongLight(textureColor, in.worldPos, in.worldNormal, in.viewPos, light);
            //finalColor = float4(in.viewPos / 5.0, 1.0);
        } else {
            // 坐标轴保留原有颜色
            finalColor = in.color;
        }
    }
    else if (demoStage.demoStage == uchar(3)) {
        if (drawType.objectType == DrawObjectType::Cube) {
            // 立方体：纹理+光照
            float3 sampleDir = normalize(float3(in.localPos.x, -in.localPos.y, in.localPos.z));
            float4 textureColor = cubeMap.sample(cubeSampler, sampleDir);
            finalColor = calculatePhongLight(textureColor, in.worldPos, in.worldNormal, in.viewPos, light);
        }
        else if (drawType.objectType == DrawObjectType::CoordinateAxis) {
            // 坐标轴：原有颜色
            finalColor = in.color;
        }
        else if (drawType.objectType == DrawObjectType::Floor) {
            // 地板：2D纹理采样
            //float2 texCoord = in.localPos.xz * 0.5;
            finalColor = floorTexture.sample(floorSampler, in.textureCoordinate);
            finalColor.a = 0.5;
        }
        else {
            // 兜底
            finalColor = in.color;
        }
    } else {
        if (drawType.objectType == DrawObjectType::Cube) {
            // 立方体：纹理 + 天空盒环境反射 + 光照
            // 1. 采样立方体自己的6面纹理
            float3 sampleDir = normalize(float3(in.localPos.x, -in.localPos.y, in.localPos.z));
            float4 textureColor = cubeMap.sample(cubeSampler, sampleDir);
            // 2. 计算反射方向并采样天空盒
            float3 viewDir = normalize(in.viewPos - in.worldPos);
            float3 reflectDir = reflect(-viewDir, normalize(in.worldNormal));
            float4 envColor = skyBoxMap.sample(cubeSampler, reflectDir);
            // 3. 混合原纹理和环境反射
            float reflectionStrength = 0.4;  // 环境反射强度（可调节：0.3-0.5）
            float4 mixedColor = mix(textureColor, envColor, reflectionStrength);
            // 4. 应用光照
            finalColor = calculatePhongLight(mixedColor, in.worldPos, in.worldNormal, in.viewPos, light);
        }
        else if (drawType.objectType == DrawObjectType::CubeReflection) {
            // 倒影：同样应用环境反射
            float3 sampleDir = normalize(float3(in.localPos.x, -in.localPos.y, in.localPos.z));
            float4 textureColor = cubeMap.sample(cubeSampler, sampleDir);
            
            float3 viewDir = normalize(in.viewPos - in.worldPos);
            float3 reflectDir = reflect(-viewDir, normalize(in.worldNormal));
            float4 envColor = skyBoxMap.sample(cubeSampler, reflectDir);
            
            float reflectionStrength = 0.4;
            float4 mixedColor = mix(textureColor, envColor, reflectionStrength);
            
            finalColor = calculatePhongLight(mixedColor, in.worldPos, in.worldNormal, in.viewPos, light);
        }
        else if (drawType.objectType == DrawObjectType::CoordinateAxis) {
            // 坐标轴：原有颜色
            finalColor = in.color;
        }
        else if (drawType.objectType == DrawObjectType::Floor) {
            // 地板：2D纹理采样
            //float2 texCoord = in.localPos.xz * 0.5;
            finalColor = floorTexture.sample(floorSampler, in.textureCoordinate);
            finalColor.a = 0.5;
        }
        else if (drawType.objectType == DrawObjectType::SkyBox) {
            // 天空盒：使用天空盒纹理采样
            float3 sampleDir = normalize(in.localPos);
            finalColor = skyBoxMap.sample(cubeSampler, sampleDir);
            finalColor.a = 1.0;
        }
        else {
            // 兜底
            finalColor = in.color;
        }
    }
    
    return finalColor;
}
