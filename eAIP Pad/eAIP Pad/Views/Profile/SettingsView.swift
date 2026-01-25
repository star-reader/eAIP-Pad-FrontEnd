import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    
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
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
