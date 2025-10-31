import SwiftUI
import SwiftData
import PDFKit

// MARK: - PDF 阅读器视图
struct PDFReaderView: View {
    let chartID: String
    let displayName: String
    let documentType: DocumentType
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var annotations: [ChartAnnotation]
    @Query private var pinnedCharts: [PinnedChart]
    @Query private var userSettings: [UserSettings]
    
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAnnotationTools = false
    @State private var currentPage = 0
    @State private var totalPages = 0
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == chartID }
    }
    
    private var chartAnnotations: [ChartAnnotation] {
        annotations.filter { $0.chartID == chartID && $0.documentType == documentType.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    ProgressView("加载PDF...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task {
                                await loadPDF()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let pdfDocument = pdfDocument {
                    PDFViewRepresentable(
                        document: pdfDocument,
                        annotations: chartAnnotations,
                        currentPage: $currentPage,
                        totalPages: $totalPages,
                        isDarkMode: currentSettings.isDarkMode,
                        onAnnotationAdded: { annotation in
                            saveAnnotation(annotation)
                        }
                    )
                    .ignoresSafeArea(.all, edges: .bottom)
                } else {
                    Text("无法加载PDF")
                        .foregroundColor(.secondary)
                }
                
                // 标注工具栏
                if showingAnnotationTools {
                    VStack {
                        Spacer()
                        AnnotationToolbar(
                            onDismiss: {
                                showingAnnotationTools = false
                            }
                        )
                        .padding()
                    }
                }
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 收藏按钮
                    Button {
                        togglePin()
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundColor(isPinned ? .orange : .primary)
                    }
                    
                    // 标注工具按钮
                    Button {
                        showingAnnotationTools.toggle()
                    } label: {
                        Image(systemName: "pencil.tip.crop.circle")
                            .foregroundColor(showingAnnotationTools ? .orange : .primary)
                    }
                    
                    // 页面信息
                    if totalPages > 0 {
                        Text("\(currentPage + 1)/\(totalPages)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .task {
            await loadPDF()
        }
    }
    
    private func loadPDF() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 根据文档类型获取签名URL
            let signedURLResponse: SignedURLResponse
            
            switch documentType {
            case .chart:
                let actualID = Int(chartID.replacingOccurrences(of: "chart_", with: "")) ?? 0
                signedURLResponse = try await NetworkService.shared.getChartSignedURL(id: actualID)
            case .ad:
                // AD细则使用Terminal目录，走chart的签名URL，但ID提取方式不同
                let actualID = Int(chartID.replacingOccurrences(of: "ad_", with: "")) ?? 0
                signedURLResponse = try await NetworkService.shared.getChartSignedURL(id: actualID)
            case .enroute:
                let actualID = Int(chartID.replacingOccurrences(of: "enroute_", with: "")) ?? 0
                signedURLResponse = try await NetworkService.shared.getEnrouteSignedURL(id: actualID)
            case .aip, .sup, .amdt, .notam:
                let actualID = Int(chartID.replacingOccurrences(of: "\(documentType.rawValue)_", with: "")) ?? 0
                signedURLResponse = try await NetworkService.shared.getDocumentSignedURL(type: documentType.rawValue, id: actualID)
            }
            
            // 构建完整URL - 将 /api/v1/ 替换为 /eaip/v1/
            let correctedPath = signedURLResponse.url.replacingOccurrences(of: "/api/v1/", with: "/eaip/v1/")
            let fullURL = URL(string: NetworkConfig.baseURL + correctedPath)!

            print("signedURLResponse: \(signedURLResponse)")
            print("fullURL: \(fullURL)")
            
            // 下载PDF - 需要带Authorization头
            var pdfRequest = URLRequest(url: fullURL)
            
            // 从NetworkService获取当前的access token
            if let accessToken = NetworkService.shared.getCurrentAccessToken() {
                pdfRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, _) = try await URLSession.shared.data(for: pdfRequest)
            
            await MainActor.run {
                if let document = PDFDocument(data: data) {
                    self.pdfDocument = document
                    self.totalPages = document.pageCount
                } else {
                    self.errorMessage = "无法解析PDF文档"
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载PDF失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    private func togglePin() {
        if isPinned {
            // 移除收藏
            if let pinToRemove = pinnedCharts.first(where: { $0.chartID == chartID }) {
                modelContext.delete(pinToRemove)
            }
        } else {
            // 添加收藏
            let newPin = PinnedChart(
                chartID: chartID,
                displayName: displayName,
                icao: "", // TODO: 从上下文获取ICAO
                type: documentType.rawValue,
                documentType: documentType.rawValue,
                airacVersion: "2510" // TODO: 从上下文获取AIRAC版本
            )
            modelContext.insert(newPin)
        }
        
        try? modelContext.save()
    }
    
    private func saveAnnotation(_ annotationData: AnnotationData) {
        let compositeID = "\(chartID)_\(annotationData.pageNumber)"
        
        // 检查是否已存在该页的标注
        let existingAnnotations = try? modelContext.fetch(
            FetchDescriptor<ChartAnnotation>(
                predicate: #Predicate { $0.compositeID == compositeID }
            )
        )
        
        if let existing = existingAnnotations?.first {
            // 更新现有标注
            existing.pathsJSON = annotationData.pathsJSON
            existing.updatedAt = Date()
        } else {
            // 创建新标注
            let annotation = ChartAnnotation(
                chartID: chartID,
                pageNumber: annotationData.pageNumber,
                pathsJSON: annotationData.pathsJSON,
                documentType: documentType.rawValue
            )
            modelContext.insert(annotation)
        }
        
        try? modelContext.save()
    }
}

// MARK: - 标注数据结构
struct AnnotationData {
    let pageNumber: Int
    let pathsJSON: String
}

// MARK: - 标注工具栏
struct AnnotationToolbar: View {
    let onDismiss: () -> Void
    @State private var selectedTool: AnnotationTool = .pen
    @State private var selectedColor: Color = .red
    @State private var strokeWidth: Double = 2.0
    
    private let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .black]
    
    var body: some View {
        VStack(spacing: 12) {
            // 工具选择
            HStack(spacing: 16) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.iconName)
                            .font(.title2)
                            .foregroundColor(selectedTool == tool ? .white : .primary)
                            .frame(width: 44, height: 44)
                            .background(
                                selectedTool == tool ? .orange : .clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.orange, lineWidth: selectedTool == tool ? 0 : 1)
                            )
                    }
                }
                
                Spacer()
                
                Button("完成") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            // 颜色选择
            HStack(spacing: 8) {
                Text("颜色:")
                    .font(.caption)
                
                ForEach(colors, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: selectedColor == color ? 2 : 0)
                            )
                    }
                }
                
                Spacer()
            }
            
            // 笔触粗细
            HStack {
                Text("粗细:")
                    .font(.caption)
                
                Slider(value: $strokeWidth, in: 1...10, step: 1)
                    .frame(width: 100)
                
                Text("\(Int(strokeWidth))px")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 标注工具枚举
enum AnnotationTool: CaseIterable {
    case pen
    case highlighter
    case eraser
    
    var iconName: String {
        switch self {
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }
    
    var displayName: String {
        switch self {
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .eraser: return "橡皮擦"
        }
    }
}

#Preview {
    PDFReaderView(
        chartID: "chart_123",
        displayName: "ZBAA-SID-01A",
        documentType: .chart
    )
    .modelContainer(for: ChartAnnotation.self, inMemory: true)
}
