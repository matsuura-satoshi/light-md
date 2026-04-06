import Foundation
import PDFKit
import CoreGraphics

enum PDFPaginator {

    /// Takes a single tall PDF page and splits it into A4-sized pages with margins.
    static func paginate(pdfData: Data, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) -> Data {
        guard let source = PDFDocument(data: pdfData),
              let sourcePage = source.page(at: 0) else {
            return pdfData
        }

        let sourceRect = sourcePage.bounds(for: .mediaBox)
        let contentHeight = pageHeight - margin * 2
        let contentWidth = pageWidth - margin * 2
        let totalHeight = sourceRect.height
        let scaleX = contentWidth / sourceRect.width
        let pageCount = Int(ceil(totalHeight * scaleX / contentHeight))

        let pdfOutput = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfOutput as CFMutableData) else { return pdfData }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return pdfData }

        for i in 0..<pageCount {
            context.beginPDFPage(nil)

            context.saveGState()

            // Clip to content area (inside margins)
            context.clip(to: CGRect(x: margin, y: margin, width: contentWidth, height: contentHeight))

            // Translate and scale: place the correct slice of the source into the content area
            let yOffset = CGFloat(i) * contentHeight
            context.translateBy(x: margin, y: margin + contentHeight + yOffset)
            context.scaleBy(x: scaleX, y: scaleX)
            context.translateBy(x: 0, y: -sourceRect.height)

            sourcePage.draw(with: .mediaBox, to: context)

            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
        return pdfOutput as Data
    }
}
