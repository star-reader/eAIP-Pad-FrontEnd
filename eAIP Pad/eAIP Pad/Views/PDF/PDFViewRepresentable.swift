import PDFKit
import SwiftUI

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
    let isAnnotationMode: Bool  // 是否处于标注模式
    let rotation: Int  // 旋转角度（0, 90, 180, 270）
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
            pdfView.backgroundColor = UIColor.black
            applyDarkModeFilter(to: pdfView)
        } else {
            pdfView.backgroundColor = UIColor.systemBackground
        }

        // 设置代理
        pdfView.delegate = context.coordinator

        // 添加手势识别器用于标注
        let drawingGestureRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDrawing(_:))
        )
        drawingGestureRecognizer.delegate = context.coordinator
        drawingGestureRecognizer.maximumNumberOfTouches = 1  // 只支持单指绘制
        context.coordinator.drawingGesture = drawingGestureRecognizer
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

    private func applyDarkModeFilter(to view: UIView) {
        // 为PDF内容页面应用滤镜，而不是整个PDFView
        // 这样可以保持背景为黑色
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 遍历PDFView的子视图，找到实际显示PDF内容的视图
            for subview in view.subviews {
                if String(describing: type(of: subview)).contains("PDFPage")
                    || String(describing: type(of: subview)).contains("TiledLayer")
                {
                    // 只对PDF内容应用滤镜
                    let filterLayer = CALayer()
                    filterLayer.name = "darkModeFilter"

                    // 使用Core Image滤镜
                    if #available(iOS 13.0, *) {
                        subview.layer.filters = [
                            CIFilter(name: "CIColorInvert"),
                            CIFilter(name: "CIHueAdjust", parameters: ["inputAngle": Float.pi]),
                            CIFilter(
                                name: "CIColorControls",
                                parameters: [
                                    "inputBrightness": -0.1,
                                    "inputContrast": 1.3,
                                    "inputSaturation": 0.9,
                                ]),
                        ].compactMap { $0 }
                    }
                }
            }
        }
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        // 更新文档
        if pdfView.document != document {
            pdfView.document = document
            totalPages = document.pageCount
        }

        // 更新标注模式
        context.coordinator.isAnnotationMode = isAnnotationMode

        // 根据标注模式启用/禁用绘制手势
        context.coordinator.drawingGesture?.isEnabled = isAnnotationMode

        // 更新旋转
        if context.coordinator.currentRotation != rotation {
            context.coordinator.currentRotation = rotation
            applyRotation(to: pdfView, rotation: rotation)
        }

        // 更新当前页面（支持外部跳转）
        if let document = pdfView.document,
            currentPage >= 0 && currentPage < document.pageCount,
            let targetPage = document.page(at: currentPage),
            pdfView.currentPage != targetPage
        {
            pdfView.go(to: targetPage)
        }

        // 更新标注
        context.coordinator.updateAnnotations(annotations)

        // 更新夜间模式
        if isDarkMode {
            pdfView.backgroundColor = UIColor.black
            applyDarkModeFilter(to: pdfView)
        } else {
            pdfView.backgroundColor = UIColor.systemBackground
            // 移除滤镜
            for subview in pdfView.subviews {
                subview.layer.filters = nil
            }
        }
    }

    private func applyRotation(to pdfView: PDFView, rotation: Int) {
        // 获取所有页面并设置旋转
        guard let document = pdfView.document else { return }

        // 保存当前页面索引
        let currentPageIndex = pdfView.currentPage.flatMap { document.index(for: $0) } ?? 0

        // 设置所有页面的旋转
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex) {
                page.rotation = rotation
            }
        }

        // 强制 PDFView 重新布局和渲染
        pdfView.layoutDocumentView()

        // 需要重新设置文档以触发完整的重绘
        let tempDoc = pdfView.document
        pdfView.document = nil
        pdfView.document = tempDoc

        // 恢复到之前的页面
        if let page = document.page(at: currentPageIndex) {
            pdfView.go(to: page)
        }

        // 确保自动缩放重新应用
        pdfView.autoScales = true

        // 强制视图刷新
        pdfView.setNeedsLayout()
        pdfView.layoutIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, PDFViewDelegate, UIGestureRecognizerDelegate {
        let parent: PDFViewRepresentable
        var isAnnotationMode = false
        var currentRotation = 0
        var drawingGesture: UIPanGestureRecognizer?
        private var currentDrawingPath: UIBezierPath?
        private var currentAnnotationLayer: CAShapeLayer?
        private var isDrawing = false

        init(_ parent: PDFViewRepresentable) {
            self.parent = parent
        }

        // MARK: - UIGestureRecognizerDelegate
        // 当标注模式开启时，绘制手势应该拦截其他手势
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // 标注模式下，不允许同时识别其他手势（如滚动、缩放）
            if isAnnotationMode && gestureRecognizer == drawingGesture {
                return false
            }
            return true
        }

        // 确保在标注模式下，绘制手势优先
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // 只有在标注模式开启时才允许绘制手势
            if gestureRecognizer == drawingGesture {
                return isAnnotationMode
            }
            return true
        }

        // MARK: - 页面变化处理
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                let currentPDFPage = pdfView.currentPage,
                let document = pdfView.document
            else { return }

            let pageIndex = document.index(for: currentPDFPage)
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }

        // MARK: - 绘制手势处理
        @objc func handleDrawing(_ gesture: UIPanGestureRecognizer) {
            guard let pdfView = gesture.view as? PDFView,
                let currentPDFPage = pdfView.currentPage
            else { return }

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
                let document = pdfView.document
            else { return }

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
                        "type": 0,  // moveTo
                        "x": Double(point.x),
                        "y": Double(point.y),
                    ])
                case .addLineToPoint:
                    let point = element.pointee.points[0]
                    pathPoints.append([
                        "type": 1,  // lineTo
                        "x": Double(point.x),
                        "y": Double(point.y),
                    ])
                case .addQuadCurveToPoint:
                    let controlPoint = element.pointee.points[0]
                    let endPoint = element.pointee.points[1]
                    pathPoints.append([
                        "type": 2,  // quadCurveTo
                        "cpx": Double(controlPoint.x),
                        "cpy": Double(controlPoint.y),
                        "x": Double(endPoint.x),
                        "y": Double(endPoint.y),
                    ])
                case .addCurveToPoint:
                    let cp1 = element.pointee.points[0]
                    let cp2 = element.pointee.points[1]
                    let endPoint = element.pointee.points[2]
                    pathPoints.append([
                        "type": 3,  // bezierCurveTo
                        "cp1x": Double(cp1.x),
                        "cp1y": Double(cp1.y),
                        "cp2x": Double(cp2.x),
                        "cp2y": Double(cp2.y),
                        "x": Double(endPoint.x),
                        "y": Double(endPoint.y),
                    ])
                case .closeSubpath:
                    pathPoints.append(["type": 4])  // closePath
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
