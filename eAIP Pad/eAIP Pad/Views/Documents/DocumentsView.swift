import SwiftData
import SwiftUI

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
    @State private var searchText = ""
    @State private var sortOption: AIPDocumentSortOption = .updatedFirst

    // 过滤后的文档列表
    private var filteredDocuments: [AIPDocumentResponse] {
        let categoryFiltered =
            selectedCategory == .all
            ? documents
            : documents.filter { $0.category == selectedCategory.rawValue }

        let searchFiltered = categoryFiltered.filter { document in
            guard !searchText.isEmpty else { return true }
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty else { return true }
            return document.nameCn.localizedCaseInsensitiveContains(keyword)
                || document.name.localizedCaseInsensitiveContains(keyword)
                || document.category.localizedCaseInsensitiveContains(keyword)
        }

        return searchFiltered.sorted(by: sortOption.sorter)
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

            CompactSearchFilterBar(
                searchText: $searchText,
                selectedSort: $sortOption,
                searchPlaceholder: "搜索 AIP 文档",
                sortOptions: AIPDocumentSortOption.allCases,
                sortTitle: "排序",
                sortLabel: { $0.displayName }
            )

            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载AIP文档...",
                retryAction: { await loadAIPDocuments() }
            ) {
                List(filteredDocuments, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        // iPad 模式
                        Button {
                            LoggerService.shared.info(
                                module: "AIPDocumentsView",
                                message: "点击文档: ID=\(document.id), Name=\(document.nameCn)")
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
            guard
                await AIRACHelper.shared.getCurrentAIRACVersion(modelContext: modelContext) != nil
            else {
                throw NSError(
                    domain: "DocumentsView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "暂无本地 AIRAC 数据，请先在「个人」中导入数据包"])
            }

            let descriptor = FetchDescriptor<LocalChart>(
                predicate: #Predicate<LocalChart> { $0.documentType == "aip" }
            )
            let localDocuments = try modelContext.fetch(descriptor)
            documents = localDocuments.map { $0.toAIPDocumentResponse() }
        } catch {
            errorMessage = "加载AIP文档失败: \(error.localizedDescription)"
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
    @State private var searchText = ""
    @State private var sortOption: SUPDocumentSortOption = .updatedFirst

    private var filteredDocuments: [SUPDocumentResponse] {
        let searchFiltered = documents.filter { document in
            guard !searchText.isEmpty else { return true }
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty else { return true }
            return document.localSubject.localizedCaseInsensitiveContains(keyword)
                || document.subject.localizedCaseInsensitiveContains(keyword)
                || document.serial.localizedCaseInsensitiveContains(keyword)
        }

        return searchFiltered.sorted(by: sortOption.sorter)
    }

    var body: some View {
        VStack(spacing: 0) {
            CompactSearchFilterBar(
                searchText: $searchText,
                selectedSort: $sortOption,
                searchPlaceholder: "搜索 SUP 文档",
                sortOptions: SUPDocumentSortOption.allCases,
                sortTitle: "排序",
                sortLabel: { $0.displayName }
            )

            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载SUP文档...",
                retryAction: { await loadSUPDocuments() }
            ) {
                List(filteredDocuments, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        Button {
                            LoggerService.shared.info(
                                module: "SUPDocumentsView",
                                message: "点击文档: ID=\(document.id), Subject=\(document.localSubject)"
                            )
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
            guard
                await AIRACHelper.shared.getCurrentAIRACVersion(modelContext: modelContext) != nil
            else {
                throw NSError(
                    domain: "DocumentsView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "暂无本地 AIRAC 数据，请先在「个人」中导入数据包"])
            }

            let descriptor = FetchDescriptor<LocalChart>(
                predicate: #Predicate<LocalChart> { $0.documentType == "sup" }
            )
            let localDocuments = try modelContext.fetch(descriptor)
            documents = localDocuments.map { $0.toSUPDocumentResponse() }
        } catch {
            errorMessage = "加载SUP文档失败: \(error.localizedDescription)"
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
    @State private var searchText = ""
    @State private var sortOption: AMDTDocumentSortOption = .updatedFirst

    private var filteredDocuments: [AMDTDocumentResponse] {
        let searchFiltered = documents.filter { document in
            guard !searchText.isEmpty else { return true }
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty else { return true }
            return document.localSubject.localizedCaseInsensitiveContains(keyword)
                || document.subject.localizedCaseInsensitiveContains(keyword)
                || document.serial.localizedCaseInsensitiveContains(keyword)
        }

        return searchFiltered.sorted(by: sortOption.sorter)
    }

    var body: some View {
        VStack(spacing: 0) {
            CompactSearchFilterBar(
                searchText: $searchText,
                selectedSort: $sortOption,
                searchPlaceholder: "搜索 AMDT 文档",
                sortOptions: AMDTDocumentSortOption.allCases,
                sortTitle: "排序",
                sortLabel: { $0.displayName }
            )

            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载AMDT文档...",
                retryAction: { await loadAMDTDocuments() }
            ) {
                List(filteredDocuments, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        Button {
                            LoggerService.shared.info(
                                module: "AMDTDocumentsView",
                                message: "点击文档: ID=\(document.id), Subject=\(document.localSubject)"
                            )
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
            }
        }
        .task {
            await loadAMDTDocuments()
        }
    }

    private func loadAMDTDocuments() async {
        // 注：官方 Web 包的 AMDT.JSON 目前未纳入本地导入解析范围，此列表暂时始终为空。
        isLoading = true
        errorMessage = nil
        documents = []
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
    @State private var searchText = ""
    @State private var sortOption: NOTAMDocumentSortOption = .latestFirst

    private var filteredDocuments: [NOTAMDocumentResponse] {
        let searchFiltered = documents.filter { document in
            guard !searchText.isEmpty else { return true }
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty else { return true }
            return document.seriesName.localizedCaseInsensitiveContains(keyword)
                || document.generateTime.localizedCaseInsensitiveContains(keyword)
        }

        return searchFiltered.sorted(by: sortOption.sorter)
    }

    var body: some View {
        VStack(spacing: 0) {
            CompactSearchFilterBar(
                searchText: $searchText,
                selectedSort: $sortOption,
                searchPlaceholder: "搜索 NOTAM 文档",
                sortOptions: NOTAMDocumentSortOption.allCases,
                sortTitle: "排序",
                sortLabel: { $0.displayName }
            )

            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载NOTAM文档...",
                retryAction: { await loadNOTAMDocuments() }
            ) {
                List(filteredDocuments, id: \.id) { document in
                    if let binding = selectedChartBinding {
                        Button {
                            LoggerService.shared.info(
                                module: "NOTAMDocumentsView",
                                message: "点击文档: ID=\(document.id), Series=\(document.seriesName)")
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
            guard
                await AIRACHelper.shared.getCurrentAIRACVersion(modelContext: modelContext) != nil
            else {
                throw NSError(
                    domain: "DocumentsView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "暂无本地 AIRAC 数据，请先在「个人」中导入数据包"])
            }

            let descriptor = FetchDescriptor<LocalChart>(
                predicate: #Predicate<LocalChart> { $0.documentType == "notam" }
            )
            let localDocuments = try modelContext.fetch(descriptor)
            documents = localDocuments.map { $0.toNOTAMDocumentResponse() }
        } catch {
            errorMessage = "加载NOTAM文档失败: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// 注意：响应模型定义在 Models/Network/ 下，这里不需要重复定义

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

enum AIPDocumentSortOption: String, CaseIterable {
    case updatedFirst
    case nameAsc
    case nameDesc

    var displayName: String {
        switch self {
        case .updatedFirst: return "更新优先"
        case .nameAsc: return "名称 A-Z"
        case .nameDesc: return "名称 Z-A"
        }
    }

    var sorter: (AIPDocumentResponse, AIPDocumentResponse) -> Bool {
        switch self {
        case .updatedFirst:
            return { lhs, rhs in
                if (lhs.isModified == true) != (rhs.isModified == true) {
                    return lhs.isModified == true
                }
                return lhs.nameCn.localizedStandardCompare(rhs.nameCn) == .orderedAscending
            }
        case .nameAsc:
            return { lhs, rhs in lhs.nameCn.localizedStandardCompare(rhs.nameCn) == .orderedAscending }
        case .nameDesc:
            return { lhs, rhs in lhs.nameCn.localizedStandardCompare(rhs.nameCn) == .orderedDescending }
        }
    }
}

enum SUPDocumentSortOption: String, CaseIterable {
    case updatedFirst
    case serialDesc
    case titleAsc

    var displayName: String {
        switch self {
        case .updatedFirst: return "更新优先"
        case .serialDesc: return "期号新到旧"
        case .titleAsc: return "标题 A-Z"
        }
    }

    var sorter: (SUPDocumentResponse, SUPDocumentResponse) -> Bool {
        switch self {
        case .updatedFirst:
            return { lhs, rhs in
                let lhsUpdated = (lhs.isModified ?? false) || (lhs.hasUpdate ?? false)
                let rhsUpdated = (rhs.isModified ?? false) || (rhs.hasUpdate ?? false)
                if lhsUpdated != rhsUpdated {
                    return lhsUpdated && !rhsUpdated
                }
                return lhs.serial.localizedStandardCompare(rhs.serial) == .orderedDescending
            }
        case .serialDesc:
            return { lhs, rhs in lhs.serial.localizedStandardCompare(rhs.serial) == .orderedDescending }
        case .titleAsc:
            return { lhs, rhs in
                lhs.localSubject.localizedStandardCompare(rhs.localSubject) == .orderedAscending
            }
        }
    }
}

enum AMDTDocumentSortOption: String, CaseIterable {
    case updatedFirst
    case serialDesc
    case titleAsc

    var displayName: String {
        switch self {
        case .updatedFirst: return "更新优先"
        case .serialDesc: return "期号新到旧"
        case .titleAsc: return "标题 A-Z"
        }
    }

    var sorter: (AMDTDocumentResponse, AMDTDocumentResponse) -> Bool {
        switch self {
        case .updatedFirst:
            return { lhs, rhs in
                let lhsUpdated = (lhs.isModified ?? false) || (lhs.hasUpdate ?? false)
                let rhsUpdated = (rhs.isModified ?? false) || (rhs.hasUpdate ?? false)
                if lhsUpdated != rhsUpdated {
                    return lhsUpdated && !rhsUpdated
                }
                return lhs.serial.localizedStandardCompare(rhs.serial) == .orderedDescending
            }
        case .serialDesc:
            return { lhs, rhs in lhs.serial.localizedStandardCompare(rhs.serial) == .orderedDescending }
        case .titleAsc:
            return { lhs, rhs in
                lhs.localSubject.localizedStandardCompare(rhs.localSubject) == .orderedAscending
            }
        }
    }
}

enum NOTAMDocumentSortOption: String, CaseIterable {
    case latestFirst
    case seriesAsc
    case seriesDesc

    var displayName: String {
        switch self {
        case .latestFirst: return "时间新到旧"
        case .seriesAsc: return "系列 A-Z"
        case .seriesDesc: return "系列 Z-A"
        }
    }

    var sorter: (NOTAMDocumentResponse, NOTAMDocumentResponse) -> Bool {
        switch self {
        case .latestFirst:
            return { lhs, rhs in
                lhs.generateTime.localizedStandardCompare(rhs.generateTime) == .orderedDescending
            }
        case .seriesAsc:
            return { lhs, rhs in
                lhs.seriesName.localizedStandardCompare(rhs.seriesName) == .orderedAscending
            }
        case .seriesDesc:
            return { lhs, rhs in
                lhs.seriesName.localizedStandardCompare(rhs.seriesName) == .orderedDescending
            }
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
    .modelContainer(for: LocalChart.self, inMemory: true)
}
