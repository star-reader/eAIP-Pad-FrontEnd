import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingDeleteAccountDoneAlert = false
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    HStack {
                        Image(systemName: "gear")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        Text("跟随系统外观")
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { currentSettings.followSystemAppearance },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentSettings.followSystemAppearance = newValue
                                }
                                try? modelContext.save()
                            }
                        ))
                    }
                    
                    if !currentSettings.followSystemAppearance {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.indigo)
                                .frame(width: 24)
                            
                            Text("深色模式")
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { currentSettings.isDarkMode },
                                set: { newValue in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentSettings.isDarkMode = newValue
                                    }
                                    try? modelContext.save()
                                }
                            ))
                        }
                    }
                    
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        
                        Text("Pinboard 样式")
                        
                        Spacer()
                        
                        Picker("Pinboard 样式", selection: Binding(
                            get: { PinboardStyle(rawValue: currentSettings.pinboardStyle) ?? .compact },
                            set: { newValue in
                                currentSettings.pinboardStyle = newValue.rawValue
                                try? modelContext.save()
                            }
                        )) {
                            ForEach(PinboardStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                
                Section("数据") {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("自动同步")
                            Text("启动时自动检查AIRAC更新")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: .constant(true))
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.minus")
                                .foregroundColor(.red)
                                .frame(width: 24)

                            Text("账号注销")
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("账户")
                } footer: {
                    Text("注销后将清除本机登录状态与账号凭据，后续可重新登录。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("确认注销账号？", isPresented: $showingDeleteAccountConfirmation) {
                Button("确认注销", role: .destructive) {
                    AuthenticationService.shared.signOut()
                    showingDeleteAccountDoneAlert = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除本机登录信息并退出登录。此操作不会影响 Apple 账号本身。")
            }
            .alert("账号已注销", isPresented: $showingDeleteAccountDoneAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("您已退出当前账号，可继续以游客模式使用基础功能。")
            }
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
