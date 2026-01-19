import Foundation
import SwiftUI
import SwiftData
import PDFKit
import Combine

// MARK: - PDF 阅读器 ViewModel
@MainActor
@Observable
class PDFReaderViewModel {
    // MARK: - 依赖注入的服务
    private let pdfCacheService: PDFCacheService
    private let networkService: NetworkService
    private let errorHandler: ErrorHandler
    
    // MARK: - 状态属性
    var pdfDocument: PDFDocument?
    var isLoading = false
    var errorMessage: String?
    var currentPage = 0
    var totalPages = 0
    var pdfRotation: Int = 0
    var showingAnnotationTools = false
    var showingThumbnails = false
    var showingShareSheet = false
    var pdfFileToShare: URL?
    
    // MARK: - 初始化（支持依赖注入）
    init(
        pdfCacheService: PDFCacheService? = nil,
        networkService: NetworkService? = nil,
        errorHandler: ErrorHandler? = nil
    ) {
        self.pdfCacheService = pdfCacheService ?? .shared
        self.networkService = networkService ?? .shared
        self.errorHandler = errorHandler ?? .shared
    }
    
    // MARK: - 加载 PDF
    func loadPDF(chartID: String, documentType: DocumentType, modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 从 chartID 提取实际的 ID
            let id = chartID.replacingOccurrences(of: "chart_", with: "")
            
            // 获取当前 AIRAC 版本
            guard let airacVersion = pdfCacheService.getCurrentAIRACVersion(modelContext: modelContext) else {
                throw AppError.airacVersionNotFound
            }
            
            // 先检查缓存
            if let cachedPDF = pdfCacheService.loadFromCache(
                airacVersion: airacVersion,
                documentType: documentType.rawValue,
                id: id
            ) {
                pdfDocument = cachedPDF
                totalPages = cachedPDF.pageCount
                isLoading = false
                LoggerService.shared.info(module: "PDFReaderViewModel", message: "从缓存加载 PDF 成功")
                return
            }
            
            // 缓存未命中，从网络下载
            LoggerService.shared.info(module: "PDFReaderViewModel", message: "缓存未命中，开始下载 PDF")
            
            // 获取签名 URL
            let signedURLResponse: SignedURLResponse
            if documentType == .chart {
                signedURLResponse = try await networkService.getChartSignedURL(id: Int(id) ?? 0)
            } else {
                signedURLResponse = try await networkService.getDocumentSignedURL(
                    type: documentType.rawValue,
                    id: Int(id) ?? 0
                )
            }
            
            // 下载 PDF
            guard let url = URL(string: signedURLResponse.url) else {
                throw AppError.network(.invalidURL)
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // 保存到缓存
            try pdfCacheService.saveToCache(
                pdfData: data,
                airacVersion: airacVersion,
                documentType: documentType.rawValue,
                id: id
            )
            
            // 加载 PDF
            guard let pdf = PDFDocument(data: data) else {
                throw AppError.pdfLoadFailed("无法解析 PDF 数据")
            }
            
            pdfDocument = pdf
            totalPages = pdf.pageCount
            isLoading = false
            
            LoggerService.shared.info(module: "PDFReaderViewModel", message: "PDF 下载并加载成功")
            
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.localizedDescription
            isLoading = false
            errorHandler.handle(error, context: "加载 PDF")
            LoggerService.shared.error(
                module: "PDFReaderViewModel",
                message: "加载 PDF 失败: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - 切换 Pin 状态
    func togglePin(chartID: String, displayName: String, icao: String, type: String, documentType: DocumentType, airacVersion: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PinnedChart>(
            predicate: #Predicate<PinnedChart> { $0.chartID == chartID }
        )
        
        do {
            let existingPins = try modelContext.fetch(descriptor)
            
            if let existingPin = existingPins.first {
                // 已存在，删除
                modelContext.delete(existingPin)
                LoggerService.shared.info(module: "PDFReaderViewModel", message: "取消 Pin: \(chartID)")
            } else {
                // 不存在，添加
                let newPin = PinnedChart(
                    chartID: chartID,
                    displayName: displayName,
                    icao: icao,
                    type: type,
                    documentType: documentType.rawValue,
                    airacVersion: airacVersion
                )
                modelContext.insert(newPin)
                LoggerService.shared.info(module: "PDFReaderViewModel", message: "添加 Pin: \(chartID)")
            }
            
            try modelContext.save()
        } catch {
            errorHandler.handle(error, context: "切换 Pin 状态")
            LoggerService.shared.error(
                module: "PDFReaderViewModel",
                message: "切换 Pin 状态失败: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - 保存标注
    func saveAnnotation(chartID: String, pageNumber: Int, pathsJSON: String, documentType: DocumentType, modelContext: ModelContext) {
        do {
            let annotation = ChartAnnotation(
                chartID: chartID,
                pageNumber: pageNumber,
                pathsJSON: pathsJSON,
                documentType: documentType.rawValue
            )
            modelContext.insert(annotation)
            try modelContext.save()
            
            LoggerService.shared.info(
                module: "PDFReaderViewModel",
                message: "保存标注成功: \(chartID) - 第 \(pageNumber) 页"
            )
        } catch {
            errorHandler.handle(error, context: "保存标注")
            LoggerService.shared.error(
                module: "PDFReaderViewModel",
                message: "保存标注失败: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - 旋转 PDF
    func rotatePDF() {
        pdfRotation = (pdfRotation + 90) % 360
        LoggerService.shared.info(module: "PDFReaderViewModel", message: "PDF 旋转至: \(pdfRotation)°")
    }
    
    // MARK: - 切换标注工具
    func toggleAnnotationTools() {
        showingAnnotationTools.toggle()
        LoggerService.shared.info(
            module: "PDFReaderViewModel",
            message: "标注工具: \(showingAnnotationTools ? "显示" : "隐藏")"
        )
    }
    
    // MARK: - 切换缩略图
    func toggleThumbnails() {
        showingThumbnails.toggle()
        LoggerService.shared.info(
            module: "PDFReaderViewModel",
            message: "缩略图: \(showingThumbnails ? "显示" : "隐藏")"
        )
    }
    
    // MARK: - 分享 PDF
    func sharePDF() {
        // 实现分享逻辑
        showingShareSheet = true
        LoggerService.shared.info(module: "PDFReaderViewModel", message: "显示分享菜单")
    }
}
