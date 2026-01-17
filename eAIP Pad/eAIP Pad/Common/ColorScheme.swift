import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - 应用配色方案（蓝色主题）
extension Color {
    // 主色调
    static let primaryBlue = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let secondaryBlue = Color(red: 0.2, green: 0.6, blue: 0.9)
    static let darkBlue = Color(red: 0.0, green: 0.32, blue: 0.8)
    static let lightBlue = Color(red: 0.9, green: 0.95, blue: 1.0)
    
    // 辅助色
    static let accentBlue = Color(red: 0.1, green: 0.7, blue: 1.0)
    static let mutedBlue = Color(red: 0.4, green: 0.6, blue: 0.8)
    
    // 功能色
    static let successGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let warningOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let errorRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    
    // 中性色
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    
    #if canImport(UIKit)
    static let backgroundPrimary = Color(UIColor.systemBackground)
    static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    #else
    static let backgroundPrimary = Color(.background)
    static let backgroundSecondary = Color(.background)
    #endif
    
    // 航空专用色
    static let aviationBlue = Color(red: 0.0, green: 0.4, blue: 0.8)
    static let skyBlue = Color(red: 0.5, green: 0.8, blue: 1.0)
}

// MARK: - 渐变色定义
extension LinearGradient {
    static let primaryBlueGradient = LinearGradient(
        colors: [Color.primaryBlue, Color.secondaryBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let skyGradient = LinearGradient(
        colors: [Color.skyBlue, Color.primaryBlue],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let aviationGradient = LinearGradient(
        colors: [Color.aviationBlue, Color.darkBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 按钮样式
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primaryBlue)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primaryBlue)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primaryBlue, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.lightBlue.opacity(configuration.isPressed ? 0.3 : 0.1))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 卡片样式
struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.primaryBlue.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }
}
