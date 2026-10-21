import SwiftData
import SwiftUI

// MARK: - 文档视图
struct DocumentsView: View {
    @Environment(\.isAIRACPageActive) private var isPageActive
    @State private var selectedDocumentType: DocumentCategory = .aip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AIRACNavigationContainer {
            VStack(spacing: 0) {
                // 文档类型选择器
                DocumentTypeSelector(selectedType: $selectedDocumentType)

                // 文档内容
                KeepAlivePages(selection: selectedDocumentType, pages: DocumentCategory.allCases) { category in
                    switch category {
                    case .aip: AIPDocumentsView()
                    case .sup: FlatDocumentsView(documentType: .sup)
                    case .aic: FlatDocumentsView(documentType: .aic)
                    case .amdt: FlatDocumentsView(documentType: .amdt)
                    case .notam: NOTAMDocumentsView()
                    }
                }
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.2),
                    value: selectedDocumentType
                )
            }
            .airacNavigationTitle("文档")
            .toolbar {
                if isPageActive {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        PinboardToolbarButton()
                    }
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
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.isAIRACPageActive) private var isPageActive
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @StateObject private var page = AIRACPageLoader(initialValue: [AIPDocumentResponse]())
    private var documents: [AIPDocumentResponse] { page.value }
    private var isLoading: Bool { page.isLoading }
    private var errorMessage: String? { page.errorMessage }
    @State private var selectedCategory: AIPCategory = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(AIPCategory.allCases, id: \.self) { category in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        } label: {
                            Text(category.displayName)
                        }
                        .buttonStyle(CompactCapsuleButtonStyle(isSelected: selectedCategory == category))
                        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 4)

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
                    Group {
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
                                    isOpened: document.isOpened,
                                    documentType: .aip
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
                                    documentType: .aip,
                                    airacVersion: document.airacVersion
                                )
                            } label: {
                                AIPDocumentRowView(document: document)
                            }
                        }
                    }
                    .compactListRow()
                }
                .scrollContentBackground(filteredDocuments.isEmpty ? .hidden : .automatic)
                .overlay {
                    if filteredDocuments.isEmpty {
                        SearchEmptyStateView(
                            searchText: $searchText,
                            title: "暂无 AIP 文档",
                            systemImage: "doc.text",
                            description: "当前分类中没有文档，可尝试切换分类或导入其他数据包。"
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await loadAIPDocuments() }
            }
        }
        .airacPageTask(key: "\(airacService.dataRevision)") {
            await loadAIPDocuments(force: false)
        }
    }

    private func loadAIPDocuments(force: Bool = true) async {
        await page.load(key: "\(airacService.dataRevision)", force: force, errorPrefix: "加载AIP文档失败：") { [modelContext] in
            let loaded = try await AIRACPackageStore.loadCharts(modelContext: modelContext, documentType: "aip")
            return loaded.map { $0.toAIPDocumentResponse() }
        }
    }
}

// MARK: - SUP / AIC / AMDT 文档视图
struct FlatDocumentsView: View {
    let documentType: DocumentType
    private var title: String { documentType.rawValue.uppercased() }
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @StateObject private var page = AIRACPageLoader(initialValue: [SUPDocumentResponse]())
    private var documents: [SUPDocumentResponse] { page.value }
    private var isLoading: Bool { page.isLoading }
    private var errorMessage: String? { page.errorMessage }
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
                searchPlaceholder: "搜索 \(title) 文档",
                sortOptions: SUPDocumentSortOption.allCases,
                sortTitle: "排序",
                sortLabel: { $0.displayName }
            )

            LoadingStateView(
                isLoading: isLoading,
                errorMessage: errorMessage,
                loadingMessage: "加载 \(title) 文档...",
                retryAction: { await loadDocuments() }
            ) {
                List(filteredDocuments, id: \.id) { document in
                    Group {
                        if let binding = selectedChartBinding {
                            Button {
                                LoggerService.shared.info(
                                    module: "FlatDocumentsView",
                                    message: "点击文档: ID=\(document.id), Subject=\(document.localSubject)"
                                )
                                binding.wrappedValue = ChartResponse(
                                    id: document.id,
                                    documentId: document.documentId,
                                    parentId: nil,
                                    icao: nil,
                                    nameEn: document.subject,
                                    nameCn: document.localSubject,
                                    chartType: title,
                                    pdfPath: document.pdfPath,
                                    htmlPath: nil,
                                    htmlEnPath: nil,
                                    airacVersion: document.airacVersion,
                                    isModified: document.isModified ?? false,
                                    isOpened: nil,
                                    documentType: documentType
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
                                    chartID: "\(documentType.rawValue)_\(document.id)",
                                    displayName: document.localSubject,
                                    documentType: documentType,
                                    airacVersion: document.airacVersion
                                )
                            } label: {
                                SUPDocumentRowView(document: document)
                            }
                        }
                    }
                    .compactListRow()
                }
                .refreshable { await loadDocuments() }
                .scrollContentBackground(filteredDocuments.isEmpty ? .hidden : .automatic)
                .overlay {
                    if filteredDocuments.isEmpty {
                        SearchEmptyStateView(
                            searchText: $searchText,
                            title: "暂无 \(title) 文档",
                            systemImage: "doc.text",
                            description: "当前分类中没有文档，可尝试切换分类或导入其他数据包。"
                        )
                    }
                }
            }
        }
        .airacPageTask(key: "\(documentType.rawValue)|\(airacService.dataRevision)") {
            await loadDocuments(force: false)
        }
    }

    private func loadDocuments(force: Bool = true) async {
        await page.load(key: "\(documentType.rawValue)|\(airacService.dataRevision)", force: force, errorPrefix: "加载\(title)文档失败：") { [modelContext, documentType] in
            let loaded = try await AIRACPackageStore.loadCharts(modelContext: modelContext, documentType: documentType.rawValue)
            return loaded.map { $0.toSUPDocumentResponse() }
        }
    }
}

// MARK: - NOTAM文档视图
struct NOTAMDocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var airacService = AIRACService.shared
    @Environment(\.selectedChartBinding) private var selectedChartBinding
    @StateObject private var page = AIRACPageLoader(initialValue: [NOTAMDocumentResponse]())
    private var documents: [NOTAMDocumentResponse] { page.value }
    private var isLoading: Bool { page.isLoading }
    private var errorMessage: String? { page.errorMessage }
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
                    Group {
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
                                    isOpened: nil,
                                    documentType: .notam
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
                                    documentType: .notam,
                                    airacVersion: document.airacVersion
                                )
                            } label: {
                                NOTAMDocumentRowView(document: document)
                            }
                        }
                    }
                    .compactListRow()
                }
                .refreshable { await loadNOTAMDocuments() }
                .scrollContentBackground(filteredDocuments.isEmpty ? .hidden : .automatic)
                .overlay {
                    if filteredDocuments.isEmpty {
                        SearchEmptyStateView(
                            searchText: $searchText,
                            title: "暂无 NOTAM 文档",
                            systemImage: "doc.text",
                            description: "当前分类中没有文档，可尝试切换分类或导入其他数据包。"
                        )
                    }
                }
            }
        }
        .airacPageTask(key: "\(airacService.dataRevision)") {
            await loadNOTAMDocuments(force: false)
        }
    }

    private func loadNOTAMDocuments(force: Bool = true) async {
        await page.load(key: "\(airacService.dataRevision)", force: force, errorPrefix: "加载NOTAM文档失败：") { [modelContext] in
            let loaded = try await AIRACPackageStore.loadCharts(modelContext: modelContext, documentType: "notam")
            return loaded.map { $0.toNOTAMDocumentResponse() }
        }
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
    }
}

// MARK: - 枚举定义
enum DocumentCategory: String, CaseIterable {
    case aip = "aip"
    case sup = "sup"
    case aic = "aic"
    case amdt = "amdt"
    case notam = "notam"

    var displayName: String {
        switch self {
        case .aip: return "AIP"
        case .sup: return "SUP"
        case .aic: return "AIC"
        case .amdt: return "AMDT"
        case .notam: return "NOTAM"
        }
    }
}

enum AIPCategory: String, CaseIterable {
    case all = "ALL"
    case gen = "GEN"
    case enr = "ENR"
    case ad = "AD"

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .gen: return "GEN"
        case .enr: return "ENR"
        case .ad: return "AD"
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
