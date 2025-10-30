import SwiftUI
import PDFKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - PDFKit UIViewRepresentable 包装器
struct PDFViewRepresentable: UIViewRepresentable {
    let document: PDFDocument
    let annotations: [ChartAnnotation]
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    let isDarkMode: Bool
    let onAnnotationAdded: (AnnotationData) -> Void
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        
        // 基础配置
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(true)
        
        // 夜间模式配置
        if isDarkMode {
            pdfView.backgroundColor = UIColor.systemBackground
        }
        
        // 设置代理
        pdfView.delegate = context.coordinator
        
        // 添加手势识别器用于标注
        let drawingGestureRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDrawing(_:))
        )
        pdfView.addGestureRecognizer(drawingGestureRecognizer)
        
        // 监听页面变化
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        // 更新文档
        if pdfView.document != document {
            pdfView.document = document
            totalPages = document.pageCount
        }
        
        // 更新标注
        context.coordinator.updateAnnotations(annotations)
        
        // 更新夜间模式
        if isDarkMode {
            pdfView.backgroundColor = UIColor.systemBackground
        } else {
            pdfView.backgroundColor = UIColor.systemBackground
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, PDFViewDelegate {
        let parent: PDFViewRepresentable
        private var currentDrawingPath: UIBezierPath?
        private var currentAnnotationLayer: CAShapeLayer?
        private var isDrawing = false
        
        init(_ parent: PDFViewRepresentable) {
            self.parent = parent
        }
        
        // MARK: - 页面变化处理
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPDFPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            
            let pageIndex = document.index(for: currentPDFPage)
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }
        
        // MARK: - 绘制手势处理
        @objc func handleDrawing(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView = gesture.view as? PDFView,
                  let currentPDFPage = pdfView.currentPage else { return }
            
            let location = gesture.location(in: pdfView)
            let pageLocation = pdfView.convert(location, to: currentPDFPage)
            
            switch gesture.state {
            case .began:
                startDrawing(at: pageLocation, on: currentPDFPage, in: pdfView)
            case .changed:
                continueDrawing(to: pageLocation)
            case .ended, .cancelled:
                finishDrawing(on: currentPDFPage, in: pdfView)
            default:
                break
            }
        }
        
        private func startDrawing(at point: CGPoint, on page: PDFPage, in pdfView: PDFView) {
            isDrawing = true
            currentDrawingPath = UIBezierPath()
            currentDrawingPath?.move(to: point)
            
            // 创建绘制层
            currentAnnotationLayer = CAShapeLayer()
            currentAnnotationLayer?.strokeColor = UIColor.red.cgColor
            currentAnnotationLayer?.fillColor = UIColor.clear.cgColor
            currentAnnotationLayer?.lineWidth = 2.0
            currentAnnotationLayer?.lineCap = .round
            currentAnnotationLayer?.lineJoin = .round
            
            // 添加到页面视图
            if let pageView = pdfView.subviews.first(where: { $0 is PDFPageView }) as? PDFPageView {
                pageView.layer.addSublayer(currentAnnotationLayer!)
            }
        }
        
        private func continueDrawing(to point: CGPoint) {
            guard isDrawing, let path = currentDrawingPath else { return }
            
            path.addLine(to: point)
            currentAnnotationLayer?.path = path.cgPath
        }
        
        private func finishDrawing(on page: PDFPage, in pdfView: PDFView) {
            guard isDrawing,
                  let path = currentDrawingPath,
                  let document = pdfView.document else { return }
            
            isDrawing = false
            
            // 获取页面索引
            let pageIndex = document.index(for: page)
            
            // 将路径转换为JSON
            let pathData = encodePathToJSON(path)
            
            // 保存标注
            let annotationData = AnnotationData(
                pageNumber: pageIndex,
                pathsJSON: pathData
            )
            
            parent.onAnnotationAdded(annotationData)
            
            // 清理临时绘制层
            currentAnnotationLayer?.removeFromSuperlayer()
            currentAnnotationLayer = nil
            currentDrawingPath = nil
        }
        
        // MARK: - 标注管理
        func updateAnnotations(_ annotations: [ChartAnnotation]) {
            // TODO: 实现标注的显示和更新
            // 这里需要将存储的标注路径重新绘制到PDF页面上
        }
        
        private func encodePathToJSON(_ path: UIBezierPath) -> String {
            var pathPoints: [[String: Double]] = []
            
            path.cgPath.applyWithBlock { element in
                switch element.pointee.type {
                case .moveToPoint:
                    let point = element.pointee.points[0]
                    pathPoints.append([
                        "type": 0, // moveTo
                        "x": Double(point.x),
                        "y": Double(point.y)
                    ])
                case .addLineToPoint:
                    let point = element.pointee.points[0]
                    pathPoints.append([
                        "type": 1, // lineTo
                        "x": Double(point.x),
                        "y": Double(point.y)
                    ])
                case .addQuadCurveToPoint:
                    let controlPoint = element.pointee.points[0]
                    let endPoint = element.pointee.points[1]
                    pathPoints.append([
                        "type": 2, // quadCurveTo
                        "cpx": Double(controlPoint.x),
                        "cpy": Double(controlPoint.y),
                        "x": Double(endPoint.x),
                        "y": Double(endPoint.y)
                    ])
                case .addCurveToPoint:
                    let cp1 = element.pointee.points[0]
                    let cp2 = element.pointee.points[1]
                    let endPoint = element.pointee.points[2]
                    pathPoints.append([
                        "type": 3, // bezierCurveTo
                        "cp1x": Double(cp1.x),
                        "cp1y": Double(cp1.y),
                        "cp2x": Double(cp2.x),
                        "cp2y": Double(cp2.y),
                        "x": Double(endPoint.x),
                        "y": Double(endPoint.y)
                    ])
                case .closeSubpath:
                    pathPoints.append(["type": 4]) // closePath
                @unknown default:
                    break
                }
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: pathPoints)
                return String(data: jsonData, encoding: .utf8) ?? "[]"
            } catch {
                return "[]"
            }
        }
    }
}

// MARK: - PDFPageView 扩展（用于获取页面视图）
extension PDFView {
    var currentPageView: PDFPageView? {
        return subviews.compactMap { $0 as? PDFPageView }.first
    }
}

// 为了编译通过，添加 PDFPageView 的简单定义
// 实际使用时应该使用 PDFKit 的真实 PDFPageView
class PDFPageView: UIView {
    // PDFKit 的 PDFPageView 实现
}
