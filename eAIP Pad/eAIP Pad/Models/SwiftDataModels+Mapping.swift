import Foundation

// MARK: - SwiftData -> 视图层 Response 结构体的映射
// App 完全离线运行后，Response 结构体不再来自网络，而是本地导入数据的展示层表示。

extension Airport {
    func toResponse() -> AirportResponse {
        AirportResponse(
            icao: icao,
            nameEn: nameEn,
            nameCn: nameCn,
            hasTerminalCharts: hasTerminalCharts,
            createdAt: ISO8601DateFormatter().string(from: createdAt),
            isModified: isModified
        )
    }
}

extension LocalChart {
    func toChartResponse() -> ChartResponse {
        ChartResponse(
            id: documentID,
            documentId: documentID,
            parentId: parentID,
            icao: icao,
            nameEn: nameEn,
            nameCn: nameCn,
            chartType: chartType,
            pdfPath: pdfPath,
            htmlPath: htmlPath,
            htmlEnPath: htmlEnPath,
            airacVersion: airacVersion,
            isModified: isModified,
            isOpened: isOpened
        )
    }

    func toAIPDocumentResponse() -> AIPDocumentResponse {
        AIPDocumentResponse(
            id: documentID,
            documentId: documentID,
            parentId: parentID,
            name: nameEn,
            nameCn: nameCn,
            category: category ?? "",
            airportIcao: icao,
            pdfPath: pdfPath,
            htmlPath: htmlPath,
            htmlEnPath: htmlEnPath,
            airacVersion: airacVersion,
            isModified: isModified,
            hasUpdate: nil,
            isOpened: isOpened
        )
    }

    func toSUPDocumentResponse() -> SUPDocumentResponse {
        SUPDocumentResponse(
            id: documentID,
            documentId: documentID,
            serial: serialNumber ?? "",
            subject: subject ?? "",
            localSubject: localSubject ?? "",
            chapterType: chapterType ?? "",
            pdfPath: pdfPath,
            effectiveTime: effectiveTime,
            outDate: outDate,
            pubDate: pubDate,
            airacVersion: airacVersion,
            isModified: isModified,
            hasUpdate: nil
        )
    }

    func toNOTAMDocumentResponse() -> NOTAMDocumentResponse {
        NOTAMDocumentResponse(
            id: documentID,
            documentId: documentID,
            seriesName: seriesName ?? "",
            pdfPath: pdfPath,
            generateTime: generateTime ?? "",
            generateTimeEn: generateTimeEn ?? "",
            airacVersion: airacVersion
        )
    }
}
