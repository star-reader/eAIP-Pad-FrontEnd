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
            // AIP分类选择器
            AIPCategorySelector(selectedCategory: $selectedCategory)
                .padding(.horizontal)
            
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
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadAIPDocuments()
                }
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
            let category = selectedCategory == .all ? nil : selectedCategory.rawValue
            let response = try await NetworkService.shared.getAIPDocuments(category: category)
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
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadSUPDocuments()
                }
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
            let response = try await NetworkService.shared.getSUPDocuments()
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
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadAMDTDocuments()
                }
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
            let response = try await NetworkService.shared.getAMDTDocuments()
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
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadNOTAMDocuments()
                }
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
            let response = try await NetworkService.shared.getNOTAMDocuments()
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

// MARK: - AIP分类选择器
struct AIPCategorySelector: View {
    @Binding var selectedCategory: AIPCategory
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AIPCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedCategory == category ? .blue : .clear,
                                in: Capsule()
                            )
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .overlay(
                                Capsule()
                                    .stroke(.blue, lineWidth: selectedCategory == category ? 0 : 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
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
