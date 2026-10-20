import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]
    @State private var showingAIRACImport = false

    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    HStack {
                        AppSymbolView(systemImage: "gearshape.fill", size: .compact)
                        
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
                            AppSymbolView(systemImage: "moon.fill", tint: .indigo, size: .compact)
                            
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
                        AppSymbolView(systemImage: "pin.fill", tint: .orange, size: .compact)
                        
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
                .compactListRow()
                
                Section("数据") {
                    Button {
                        showingAIRACImport = true
                    } label: {
                        HStack {
                            AppSymbolView(systemImage: "tray.and.arrow.down.fill", size: .compact)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("导入 AIRAC 数据包")
                                    .foregroundColor(.primary)
                                Text("从 EAIP China 官网下载 Web 数据包后手动导入")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .compactListRow()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAIRACImport) {
                AIRACUpdateView()
            }
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
