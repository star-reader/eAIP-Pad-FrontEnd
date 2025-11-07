import SwiftUI
import SwiftData
import PDFKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - PDF 阅读器视图
struct PDFReaderView: View {
    let chartID: String
    let displayName: String
    let documentType: DocumentType
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.columnVisibilityBinding) private var columnVisibilityBinding
    @Query private var annotations: [ChartAnnotation]
    @Query private var pinnedCharts: [PinnedChart]
    @Query private var userSettings: [UserSettings]
    
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAnnotationTools = false
    @State private var currentPage = 0
    @State private var totalPages = 0
    @State private var pdfRotation: Int = 0  // PDF 旋转角度（0, 90, 180, 270）
    @State private var showingThumbnails = false  // 显示缩略图目录
    @State private var showingShareSheet = false  // 显示分享菜单
    @State private var pdfFileToShare: URL?  // 要分享的 PDF 文件 URL
    
    private var currentSettings: UserSettings {
        userSettings.first ?? UserSettings()
    }
    
    private var isPinned: Bool {
        pinnedCharts.contains { $0.chartID == chartID }
    }
    
    private var chartAnnotations: [ChartAnnotation] {
        annotations.filter { $0.chartID == chartID && $0.documentType == documentType.rawValue }
    }
    
    private var shouldUseDarkMode: Bool {
        if currentSettings.followSystemAppearance {
            // 跟随系统时，检查当前的颜色方案
            #if canImport(UIKit)
            return UITraitCollection.current.userInterfaceStyle == .dark
            #else
            return false
            #endif
        } else {
            return currentSettings.isDarkMode
        }
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
                        isDarkMode: shouldUseDarkMode,
                        isAnnotationMode: showingAnnotationTools,
                        rotation: pdfRotation,
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 页面信息
                    if totalPages > 0 {
                        Text("\(currentPage + 1)/\(totalPages)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 8)
                    }
                    
                    // iPad 侧边栏切换按钮（仅在 iPad 模式下显示）
                    if let binding = columnVisibilityBinding {
                        Button {
                            withAnimation {
                                // 切换侧边栏显示状态
                                if binding.wrappedValue == .all || binding.wrappedValue == .doubleColumn {
                                    binding.wrappedValue = .detailOnly
                                } else {
                                    binding.wrappedValue = .doubleColumn
                                }
                            }
                        } label: {
                            Image(
                                systemName: "sidebar.left"
                                // systemName: binding.wrappedValue == .detailOnly ? "sidebar.left" : "sidebar.left.fill"
                                )
                                .foregroundColor(.primary)
                        }
                    }
                    
                    // Pinboard 按钮
                    Button {
                        togglePin()
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundColor(isPinned ? .orange : .primary)
                    }
                    
                    // 更多操作菜单
                    Menu {
                        
                        // 视图操作
                        Section {
                            Button {
                                // 左旋转
                                pdfRotation = (pdfRotation - 90 + 360) % 360
                            } label: {
                                Label("向左旋转", systemImage: "rotate.left")
                            }
                            
                            Button {
                                // 右旋转
                                pdfRotation = (pdfRotation + 90) % 360
                            } label: {
                                Label("向右旋转", systemImage: "rotate.right")
                            }
                            
                            Button {
                                showingThumbnails = true
                            } label: {
                                Label("查看缩略图", systemImage: "square.grid.3x3")
                            }
                        }

                        Section {
                            Button {
                                sharePDF()
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            
                            Button {
                                downloadPDF()
                            } label: {
                                Label("下载到文件", systemImage: "arrow.down.doc")
                            }
                            
                            Button {
                                printPDF()
                            } label: {
                                Label("打印", systemImage: "printer")
                            }
                        }
                        
                        // 搜索和标注
                        // Section {
                            // Button {
                            //     // TODO: 搜索文本；这个v2升级做
                            // } label: {
                            //     Label("搜索", systemImage: "magnifyingglass")
                            // }
                            
                            // 标注工具按钮 - 暂时隐藏
                            // Button {
                            //     showingAnnotationTools.toggle()
                            // } label: {
                            //     Label("标注工具", systemImage: "pencil.tip.crop.circle")
                            // }
                        // }
                        
                        // 页面导航
                        Section {
                            Button {
                                goToFirstPage()
                            } label: {
                                Label("跳转到首页", systemImage: "arrow.up.to.line")
                            }
                            
                            Button {
                                goToLastPage()
                            } label: {
                                Label("跳转到末页", systemImage: "arrow.down.to.line")
                            }
                        }
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingThumbnails) {
                if let pdfDocument = pdfDocument {
                    PDFThumbnailView(document: pdfDocument, currentPage: $currentPage)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let pdfFile = pdfFileToShare {
                    ShareSheet(items: [pdfFile])
                }
            }
        }
        .task(id: chartID) {
            LoggerService.shared.info(module: "PDFReaderView", message: "task 触发 - chartID: \(chartID), documentType: \(documentType.rawValue)")
            await loadPDF()
        }
        .onChange(of: chartID) { oldValue, newValue in
            LoggerService.shared.info(module: "PDFReaderView", message: "chartID 变化: \(oldValue) -> \(newValue)")
            Task {
                await loadPDF()
            }
        }
        .onAppear {
            LoggerService.shared.info(module: "PDFReaderView", message: "onAppear - chartID: \(chartID)")
        }
        .onDisappear {
            LoggerService.shared.info(module: "PDFReaderView", message: "onDisappear - chartID: \(chartID)")
        }
    }
    
    private func loadPDF() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 提取实际的 ID - 从 chartID 中提取最后一个下划线后的数字
            let actualID: String
            if let lastUnderscoreIndex = chartID.lastIndex(of: "_") {
                actualID = String(chartID[chartID.index(after: lastUnderscoreIndex)...])
            } else {
                actualID = chartID
            }
            
            LoggerService.shared.info(module: "PDFReaderView", message: "chartID: \(chartID), actualID: \(actualID), documentType: \(documentType.rawValue)")
            
            // 获取当前 AIRAC 版本（如果没有则从 API 获取）
            var currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext)
            
            // 如果本地没有 AIRAC 版本，尝试从 API 获取
            if currentAIRAC == nil {
                LoggerService.shared.warning(module: "PDFReaderView", message: "本地无 AIRAC 版本，从 API 获取")
                do {
                    let airacResponse = try await NetworkService.shared.getCurrentAIRAC()
                    currentAIRAC = airacResponse.version
                    
                    // 保存到本地数据库
                    let newVersion = AIRACVersion(
                        version: airacResponse.version,
                        effectiveDate: ISO8601DateFormatter().date(from: airacResponse.effectiveDate) ?? Date(),
                        isCurrent: true
                    )
                    modelContext.insert(newVersion)
                    try? modelContext.save()
                    
                    LoggerService.shared.info(module: "PDFReaderView", message: "已获取并保存 AIRAC 版本: \(airacResponse.version)")
                } catch {
                    LoggerService.shared.warning(module: "PDFReaderView", message: "无法从 API 获取 AIRAC 版本，使用默认值: \(error.localizedDescription)")
                    // 使用一个默认的 AIRAC 版本（用于降级处理）
                    currentAIRAC = "unknown"
                }
            }
            
            // 确保 airacVersion 不为 nil（如果 API 获取失败，已设置为 "unknown"）
            let airacVersion = currentAIRAC ?? "unknown"
            
            // 1. 先尝试从缓存加载
            if let cachedDocument = PDFCacheService.shared.loadFromCache(
                airacVersion: airacVersion,
                documentType: documentType.rawValue,
                id: actualID
            ) {
                await MainActor.run {
                    self.pdfDocument = cachedDocument
                    self.totalPages = cachedDocument.pageCount
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络下载
            // 根据文档类型获取签名URL
            let signedURLResponse: SignedURLResponse
            switch documentType {
            case .chart:
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getChartSignedURL(id: id)
            case .enroute:
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getEnrouteSignedURL(id: id)
            case .ad:
                // AD 细则使用 documents/ad API
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getDocumentSignedURL(type: "ad", id: id)
            case .aip:
                // AIP 使用 documents/aip API
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getDocumentSignedURL(type: "aip", id: id)
            case .sup:
                // SUP 使用 documents/sup API
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getDocumentSignedURL(type: "sup", id: id)
            case .amdt:
                // AMDT 使用 documents/amdt API
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getDocumentSignedURL(type: "amdt", id: id)
            case .notam:
                // NOTAM 使用 documents/notam API
                let id = Int(actualID) ?? 0
                signedURLResponse = try await NetworkService.shared.getDocumentSignedURL(type: "notam", id: id)
            }
            
            // 构建完整URL - 将 /api/v1/ 替换为 /eaip/v1/
            let correctedPath = signedURLResponse.url.replacingOccurrences(of: "/api/v1/", with: "/eaip/v1/")
            let fullURL = URL(string: NetworkConfig.baseURL + correctedPath)!
            
            // 下载PDF - 需要带Authorization头
            var pdfRequest = URLRequest(url: fullURL)
            
            // 从NetworkService获取当前的access token
            if let accessToken = NetworkService.shared.getCurrentAccessToken() {
                pdfRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, _) = try await URLSession.shared.data(for: pdfRequest)
            
            // 3. 保存到缓存（只在有有效 AIRAC 版本时才缓存）
            if airacVersion != "unknown" {
                try? PDFCacheService.shared.saveToCache(
                    pdfData: data,
                    airacVersion: airacVersion,
                    documentType: documentType.rawValue,
                    id: actualID
                )
            }
            
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
            // 从chartID中提取ICAO
            // 格式通常为: {icao}_{type}_{id}
            let icaoCode: String
            if let firstUnderscoreIndex = chartID.firstIndex(of: "_") {
                icaoCode = String(chartID[..<firstUnderscoreIndex])
            } else {
                icaoCode = "" // 如果无法提取，则使用空字符串
            }

            LoggerService.shared.info(module: "PDFReaderView", message: "猜测的ICAO: \(icaoCode)")
            
            // 获取当前AIRAC版本
            let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) ?? "unknown"
            
            // 添加收藏
            let newPin = PinnedChart(
                chartID: chartID,
                displayName: displayName,
                icao: icaoCode,
                type: documentType.rawValue,
                documentType: documentType.rawValue,
                airacVersion: currentAIRAC
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
    
    // MARK: - PDF 操作方法
    
    // 清理文件名，移除非法字符
    private func sanitizeFileName(_ name: String) -> String {
        // 替换文件系统中的非法字符
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = name.components(separatedBy: invalidCharacters)
        return components.joined(separator: "-")
    }
    
    private func sharePDF() {
        guard let pdfDocument = pdfDocument,
              let pdfData = pdfDocument.dataRepresentation() else {
            return
        }
        
        // 创建临时文件用于分享，清理文件名
        let cleanFileName = sanitizeFileName(displayName)
        let fileName = "\(cleanFileName).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: tempURL)
            pdfFileToShare = tempURL
            showingShareSheet = true
        } catch {
            LoggerService.shared.error(module: "PDFReaderView", message: "创建临时文件失败: \(error.localizedDescription)")
        }
    }
    
    private func downloadPDF() {
        guard let pdfDocument = pdfDocument,
              let pdfData = pdfDocument.dataRepresentation() else {
            return
        }
        
        // 使用文档选择器保存文件，清理文件名
        let cleanFileName = sanitizeFileName(displayName)
        let fileName = "\(cleanFileName).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: tempURL)
            
            // 使用文档选择器保存
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL])
            documentPicker.shouldShowFileExtensions = true
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                rootViewController.present(documentPicker, animated: true)
            }
        } catch {
            LoggerService.shared.error(module: "PDFReaderView", message: "保存PDF失败: \(error.localizedDescription)")
        }
    }
    
    private func printPDF() {
        guard let pdfDocument = pdfDocument else {
            return
        }
        
        // 清理文件名用于打印作业名称
        let cleanJobName = sanitizeFileName(displayName)
        
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = cleanJobName
        
        printController.printInfo = printInfo
        
        // 直接使用 PDFDocument 而不是转换为 Data，避免大文件卡顿
        printController.printingItem = pdfDocument.dataRepresentation()
        
        // 异步呈现打印界面，避免阻塞主线程
        DispatchQueue.main.async {
            printController.present(animated: true) { controller, completed, error in
                if let error = error {
                    LoggerService.shared.error(module: "PDFReaderView", message: "打印失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func goToFirstPage() {
        guard let pdfDocument = pdfDocument,
              pdfDocument.pageCount > 0 else {
            return
        }
        currentPage = 0
        // PDF 视图会通过 binding 自动更新
    }
    
    private func goToLastPage() {
        guard let pdfDocument = pdfDocument else {
            return
        }
        let lastPageIndex = pdfDocument.pageCount - 1
        currentPage = lastPageIndex
        // PDF 视图会通过 binding 自动更新
    }
}

// MARK: - 分享 Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

// MARK: - PDF 缩略图视图
struct PDFThumbnailView: View {
    let document: PDFDocument
    @Binding var currentPage: Int
    @Environment(\.dismiss) private var dismiss
    
    // iOS 每行显示 2 个缩略图，iPad 显示 3 个
    private var columns: [GridItem] {
        #if os(iOS)
        // 检测设备类型
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if isIPad {
            return [
                GridItem(.flexible(minimum: 120, maximum: 250), spacing: 20),
                GridItem(.flexible(minimum: 120, maximum: 250), spacing: 20),
                GridItem(.flexible(minimum: 120, maximum: 250), spacing: 20)
            ]
        } else {
            // iPhone 只显示 2 列
            return [
                GridItem(.flexible(minimum: 140, maximum: 300), spacing: 20),
                GridItem(.flexible(minimum: 140, maximum: 300), spacing: 20)
            ]
        }
        #else
        return [
            GridItem(.flexible(minimum: 100, maximum: 200), spacing: 20),
            GridItem(.flexible(minimum: 100, maximum: 200), spacing: 20)
        ]
        #endif
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(0..<document.pageCount, id: \.self) { pageIndex in
                        if let page = document.page(at: pageIndex) {
                            Button {
                                // 跳转到该页并关闭缩略图视图
                                currentPage = pageIndex
                                dismiss()
                            } label: {
                                VStack(spacing: 8) {
                                    // 使用 aspectRatio 保持页面原始比例
                                    PDFPageThumbnail(page: page)
                                        .aspectRatio(page.bounds(for: .mediaBox).width / page.bounds(for: .mediaBox).height, contentMode: .fit)
                                        .background(Color.white)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(currentPage == pageIndex ? Color.blue : Color.gray.opacity(0.3), lineWidth: currentPage == pageIndex ? 3 : 1)
                                        )
                                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                                    
                                    Text("第 \(pageIndex + 1) 页")
                                        .font(.caption2)
                                        .foregroundColor(currentPage == pageIndex ? .blue : .secondary)
                                        .fontWeight(currentPage == pageIndex ? .semibold : .regular)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("缩略图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - PDF 页面缩略图
struct PDFPageThumbnail: UIViewRepresentable {
    let page: PDFPage
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }
    
    func updateUIView(_ imageView: UIImageView, context: Context) {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 300 / max(pageRect.width, pageRect.height)
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(scaledSize, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: scaledSize))
        
        context.saveGState()
        context.translateBy(x: 0, y: scaledSize.height)
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        imageView.image = thumbnail
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
