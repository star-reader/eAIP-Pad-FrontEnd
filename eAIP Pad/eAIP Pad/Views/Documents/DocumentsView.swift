import SwiftUI
import SwiftData

// MARK: - 文档视图
struct DocumentsView: View {
    @State private var selectedDocumentType: DocumentCategory = .aip
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 文档类型选择器
                DocumentTypeSelector(selectedType: $selectedDocumentType)
                    .padding(.horizontal)
                
                // 文档内容
                Group {
                    switch selectedDocumentType {
                    case .aip:
                        AIPDocumentsView()
                    case .sup:
                        SUPDocumentsView()
                    case .notam:
                        NOTAMDocumentsView()
                    }
                }
            }
            .navigationTitle("文档")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PinboardToolbarButton()
                }
            }
        }
    }
}

// MARK: - 文档类型选择器（使用SwiftUI原生样式）
struct DocumentTypeSelector: View {
    @Binding var selectedType: DocumentCategory
    
    var body: some View {
        Picker("文档类型", selection: $selectedType) {
            ForEach(DocumentCategory.allCases, id: \.self) { type in
                Text(type.displayName)
                    .tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - AIP文档视图
struct AIPDocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @State private var documents: [AIPDocumentResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCategory: AIPCategory = .all
    
    // 过滤后的文档列表
    private var filteredDocuments: [AIPDocumentResponse] {
        if selectedCategory == .all {
            return documents
        } else {
            return documents.filter { $0.category == selectedCategory.rawValue }
        }
    }
    
    var body: some View {
        VStack {
            // AIP 分类选择器 - HStack 按钮样式
            HStack(spacing: 12) {
                ForEach(AIPCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(selectedCategory == category ? .white : .blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category ? Color.blue : Color.blue.opacity(0.1),
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            if isLoading {
                ProgressView("加载AIP文档...")
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
                            await loadAIPDocuments()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredDocuments, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        // iPad 模式
                        Button {
                            print("📄 AIPDocumentsView - 点击文档: ID=\(document.id), Name=\(document.nameCn)")
                            // 转换为 ChartResponse，使用 "AIP" 作为 chartType
                            binding.wrappedValue = ChartResponse(
                                id: document.id,
                                documentId: document.documentId,
                                parentId: document.parentId,
                                icao: document.airportIcao,
                                nameEn: document.name,
                                nameCn: document.nameCn,
                                chartType: "AIP",  // 统一使用 "AIP" 而不是 category
                                pdfPath: document.pdfPath,
                                htmlPath: document.htmlPath,
                                htmlEnPath: document.htmlEnPath,
                                airacVersion: document.airacVersion,
                                isModified: document.isModified ?? false,
                                isOpened: document.isOpened
                            )
                        } label: {
                            AIPDocumentRowView(document: document)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // iPhone 模式
                        NavigationLink {
                            PDFReaderView(
                                chartID: "aip_\(document.id)",
                                displayName: document.nameCn,
                                documentType: .aip
                            )
                        } label: {
                            AIPDocumentRowView(document: document)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            await loadAIPDocuments()
        }
    }
    
    private func loadAIPDocuments() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "Documents", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            let category = selectedCategory == .all ? nil : selectedCategory.rawValue
            let cacheKey = category != nil ? "aip_\(category!)" : PDFCacheService.DataType.aipDocuments
            
            // 1. 先尝试从缓存加载
            if let cachedDocuments = PDFCacheService.shared.loadCachedData(
                [AIPDocumentResponse].self,
                airacVersion: currentAIRAC,
                dataType: cacheKey
            ) {
                await MainActor.run {
                    self.documents = cachedDocuments
                }
                isLoading = false
                return
            }
            
            print("⬇️ 从网络下载 AIP 文档列表")
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getAIPDocuments(category: category)
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: cacheKey
            )
            
            await MainActor.run {
                self.documents = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载AIP文档失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - SUP文档视图
struct SUPDocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @State private var documents: [SUPDocumentResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载SUP文档...")
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
                            await loadSUPDocuments()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(documents, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        // iPad 模式
                        Button {
                            print("📋 SUPDocumentsView - 点击文档: ID=\(document.id), Subject=\(document.localSubject)")
                            // 创建简化的 ChartResponse
                            binding.wrappedValue = ChartResponse(
                                id: document.id,
                                documentId: document.documentId,
                                parentId: nil,
                                icao: nil,
                                nameEn: document.subject,
                                nameCn: document.localSubject,
                                chartType: "SUP",
                                pdfPath: document.pdfPath,
                                htmlPath: nil,
                                htmlEnPath: nil,
                                airacVersion: document.airacVersion,
                                isModified: document.isModified ?? false,
                                isOpened: nil
                            )
                        } label: {
                            SUPDocumentRowView(document: document)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // iPhone 模式
                        NavigationLink {
                            PDFReaderView(
                                chartID: "sup_\(document.id)",
                                displayName: document.localSubject,
                                documentType: .sup
                            )
                        } label: {
                            SUPDocumentRowView(document: document)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            await loadSUPDocuments()
        }
    }
    
    private func loadSUPDocuments() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "Documents", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 1. 先尝试从缓存加载
            if let cachedDocuments = PDFCacheService.shared.loadCachedData(
                [SUPDocumentResponse].self,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.supDocuments
            ) {
                await MainActor.run {
                    self.documents = cachedDocuments
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getSUPDocuments()
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.supDocuments
            )
            
            await MainActor.run {
                self.documents = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载SUP文档失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - AMDT文档视图
struct AMDTDocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @State private var documents: [AMDTDocumentResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载AMDT文档...")
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
                            await loadAMDTDocuments()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(documents, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        // iPad 模式
                        Button {
                            print("📝 AMDTDocumentsView - 点击文档: ID=\(document.id), Subject=\(document.localSubject)")
                            // 创建简化的 ChartResponse
                            binding.wrappedValue = ChartResponse(
                                id: document.id,
                                documentId: "\(document.id)",
                                parentId: nil,
                                icao: nil,
                                nameEn: document.subject,
                                nameCn: document.localSubject,
                                chartType: "AMDT",
                                pdfPath: document.pdfPath,
                                htmlPath: nil,
                                htmlEnPath: nil,
                                airacVersion: document.airacVersion,
                                isModified: document.isModified ?? false,
                                isOpened: nil
                            )
                        } label: {
                            AMDTDocumentRowView(document: document)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // iPhone 模式
                        NavigationLink {
                            PDFReaderView(
                                chartID: "amdt_\(document.id)",
                                displayName: document.localSubject,
                                documentType: .amdt
                            )
                        } label: {
                            AMDTDocumentRowView(document: document)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            await loadAMDTDocuments()
        }
    }
    
    private func loadAMDTDocuments() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "Documents", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 1. 先尝试从缓存加载
            if let cachedDocuments = PDFCacheService.shared.loadCachedData(
                [AMDTDocumentResponse].self,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.amdtDocuments
            ) {
                await MainActor.run {
                    self.documents = cachedDocuments
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getAMDTDocuments()
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.amdtDocuments
            )
            
            await MainActor.run {
                self.documents = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载AMDT文档失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - NOTAM文档视图
struct NOTAMDocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @State private var documents: [NOTAMDocumentResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载NOTAM文档...")
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
                            await loadNOTAMDocuments()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(documents, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        // iPad 模式
                        Button {
                            print("🔔 NOTAMDocumentsView - 点击文档: ID=\(document.id), Series=\(document.seriesName)")
                            // 创建简化的 ChartResponse
                            binding.wrappedValue = ChartResponse(
                                id: document.id,
                                documentId: "\(document.id)",
                                parentId: nil,
                                icao: nil,
                                nameEn: "NOTAM \(document.seriesName)",
                                nameCn: "NOTAM \(document.seriesName)",
                                chartType: "NOTAM",
                                pdfPath: nil,
                                htmlPath: nil,
                                htmlEnPath: nil,
                                airacVersion: document.airacVersion,
                                isModified: false,
                                isOpened: nil
                            )
                        } label: {
                            NOTAMDocumentRowView(document: document)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // iPhone 模式
                        NavigationLink {
                            PDFReaderView(
                                chartID: "notam_\(document.id)",
                                displayName: "NOTAM \(document.seriesName)",
                                documentType: .notam
                            )
                        } label: {
                            NOTAMDocumentRowView(document: document)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            await loadNOTAMDocuments()
        }
    }
    
    private func loadNOTAMDocuments() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 获取当前 AIRAC 版本
            guard let currentAIRAC = PDFCacheService.shared.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw NSError(domain: "Documents", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 AIRAC 版本"])
            }
            
            // 1. 先尝试从缓存加载
            if let cachedDocuments = PDFCacheService.shared.loadCachedData(
                [NOTAMDocumentResponse].self,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.notamDocuments
            ) {
                await MainActor.run {
                    self.documents = cachedDocuments
                }
                isLoading = false
                return
            }
            
            // 2. 缓存未命中，从网络获取
            let response = try await NetworkService.shared.getNOTAMDocuments()
            
            // 3. 保存到缓存
            try? PDFCacheService.shared.cacheData(
                response,
                airacVersion: currentAIRAC,
                dataType: PDFCacheService.DataType.notamDocuments
            )
            
            await MainActor.run {
                self.documents = response
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "加载NOTAM文档失败: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// 注意：响应模型已在 NetworkService.swift 中定义，这里不需要重复定义

// MARK: - 文档行视图
struct AIPDocumentRowView: View {
    let document: AIPDocumentResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.nameCn)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            Text(document.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                Text(document.category)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundColor(.blue)
                
                Text("AIRAC \(document.airacVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if document.isModified == true {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

struct SUPDocumentRowView: View {
    let document: SUPDocumentResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SUP \(document.serial)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundColor(.orange)
                
                if (document.isModified ?? false) || (document.hasUpdate ?? false) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                Spacer()
            }
            
            Text(document.localSubject)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            Text(document.subject)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if let effectiveTime = document.effectiveTime {
                Text("生效时间: \(effectiveTime)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AMDTDocumentRowView: View {
    let document: AMDTDocumentResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AMDT \(document.serial)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
                    .foregroundColor(.green)
                
                if (document.isModified ?? false) || (document.hasUpdate ?? false) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                Spacer()
            }
            
            Text(document.localSubject)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
            
            Text(document.subject)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if let effectiveTime = document.effectiveTime {
                Text("生效时间: \(effectiveTime)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NOTAMDocumentRowView: View {
    let document: NOTAMDocumentResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("NOTAM \(document.seriesName)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.2), in: Capsule())
                    .foregroundColor(.red)
                
                Spacer()
            }
            
            Text("航行通告 \(document.seriesName) 系列")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("生成时间: \(document.generateTime)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 枚举定义
enum DocumentCategory: String, CaseIterable {
    case aip = "aip"
    case sup = "sup"
    case notam = "notam"
    
    var displayName: String {
        switch self {
        case .aip: return "AIP"
        case .sup: return "SUP"
        case .notam: return "NOTAM"
        }
    }
}

enum AIPCategory: String, CaseIterable {
    case all = "ALL"
    case gen = "GEN"
    case enr = "ENR"
    
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .gen: return "GEN"
        case .enr: return "ENR"
        }
    }
}

// 模拟数据已移除，现在使用真实的网络请求

#Preview {
    NavigationStack {
        DocumentsView()
    }
    .modelContainer(for: LocalChart.self, inMemory: true)
}
