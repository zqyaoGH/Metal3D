//
//  FloatPicker.swift
//  Metal 3D
//
//  Created by TSAR Weasley on 2023/11/9.
//  Modified by ZQYao on 2025/12/26

import SwiftUI

struct FloatPicker: View {
    @Binding var value: Float
    private(set) var range: ClosedRange<Float> = -1...1
    var label: String = ""
    private(set) var step: Float = 1.0
    
    // 拆分：单独生成数值显示字符串（不再拼接label和空格）
    private var valueDisplayString: String {
        let angleLabels: Set<String> = ["LA", "LO", "AN"]
        
        if angleLabels.contains(label)  {
            let degreeValue = value * (180 / Float.pi) // 弧度转角度
            // 统一用3位整数（解决LA/LO/AN行数不一致）
            
            let degreeStrT = degreeValue.formatted(
                .number.precision(.integerAndFractionLength(integer: 3, fraction: 0))
            )
            let degreeInt = Int(degreeStrT) ?? 0 // 转整数自动剔除前导0
            let degreeStr = degreeInt
            let radianStr = value.formatted(
                .number.precision(.integerAndFractionLength(integer: 1, fraction: 2))
            )
            return "\(degreeStr)° \(radianStr)"
        } else {
            let valueStr = value.formatted(
                .number.precision(.integerAndFractionLength(integer: 1, fraction: 2))
            )
            return valueStr
        }
    }
    
    var body: some View {
        HStack {
            Slider(value: $value, in: range)
            Stepper(value: $value, in: range, step: step) {
                // 改用HStack固定布局（替代字符串拼接空格，解决跳动）
                HStack(alignment: .center, spacing: 2) {
                    // 固定label宽度 + 右对齐，避免布局跳动
                    Text("\(label):")
                        .frame(width: 25, alignment: .trailing)
                        .monospaced()
                    // 数值部分单独显示，等宽字体确保对齐
                    Text(valueDisplayString)
                        .monospaced()
                        .frame(minWidth: 53, alignment: .leading)
                }
            }
        }.frame(width: 200)
    }
}

 
#Preview {
    VStack(spacing: 15) {
        // 平移控件：步长0.1
        FloatPicker(value: .constant(0), range: -10...10, label: "平移X", step: 0.1)
        // 旋转控件：步长15*Float.pi/180（即Float.pi/12）
        FloatPicker(value: .constant(0), range: -Float.pi...Float.pi, label: "LA", step: 15 * Float.pi / 180)
        // 缩放控件：步长0.1
        FloatPicker(value: .constant(1), range: 0.1...5, label: "缩放", step: 0.1)
    }
}
