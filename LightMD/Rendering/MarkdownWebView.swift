import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let htmlContent: String
    var onTOCExtracted: (([TOCHeading]) -> Void)?
    var onActiveHeadingChanged: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTOCExtracted: onTOCExtracted,
            onActiveHeadingChanged: onActiveHeadingChanged
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "tocHandler")
        contentController.add(context.coordinator, name: "activeHeading")
        contentController.add(context.coordinator, name: "copyToClipboard")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTOCExtracted = onTOCExtracted
        coordinator.onActiveHeadingChanged = onActiveHeadingChanged

        guard htmlContent != coordinator.lastHTML else { return }
        coordinator.lastHTML = htmlContent

        webView.evaluateJavaScript("window.scrollY") { result, _ in
            coordinator.savedScrollY = result as? Double ?? 0
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    func scrollToHeading(_ id: String, webView: WKWebView) {
        let escaped = id.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("scrollToHeading('\(escaped)')")
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var savedScrollY: Double = 0
        var lastHTML: String = ""
        var onTOCExtracted: (([TOCHeading]) -> Void)?
        var onActiveHeadingChanged: ((String) -> Void)?

        private nonisolated(unsafe) var observers: [Any] = []

        init(onTOCExtracted: (([TOCHeading]) -> Void)?, onActiveHeadingChanged: ((String) -> Void)?) {
            self.onTOCExtracted = onTOCExtracted
            self.onActiveHeadingChanged = onActiveHeadingChanged
            super.init()

            observers.append(NotificationCenter.default.addObserver(
                forName: .scrollToHeading, object: nil, queue: .main
            ) { [weak self] notification in
                guard let id = notification.userInfo?["id"] as? String,
                      let webView = self?.webView else { return }
                let escaped = id.replacingOccurrences(of: "'", with: "\\'")
                webView.evaluateJavaScript("scrollToHeading('\(escaped)')")
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: .zoomIn, object: nil, queue: .main
            ) { [weak self] _ in
                guard let webView = self?.webView else { return }
                webView.pageZoom = min(webView.pageZoom + 0.1, 3.0)
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: .zoomOut, object: nil, queue: .main
            ) { [weak self] _ in
                guard let webView = self?.webView else { return }
                webView.pageZoom = max(webView.pageZoom - 0.1, 0.5)
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: .zoomReset, object: nil, queue: .main
            ) { [weak self] _ in
                self?.webView?.pageZoom = 1.0
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: .exportPDF, object: nil, queue: .main
            ) { [weak self] _ in
                self?.exportPDF()
            })
        }

        private var pdfWebView: WKWebView?
        private var pdfSaveURL: URL?

        private func exportPDF() {
            guard let webView else { return }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "document.pdf"
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                guard let html = result as? String else { return }
                self?.renderPDFOffscreen(html: html, saveURL: saveURL)
            }
        }

        private func renderPDFOffscreen(html: String, saveURL: URL) {
            let a4Width: CGFloat = 595.28

            let config = WKWebViewConfiguration()
            let offscreen = WKWebView(frame: CGRect(x: -9999, y: -9999, width: a4Width, height: 1), configuration: config)
            offscreen.navigationDelegate = self
            self.pdfWebView = offscreen
            self.pdfSaveURL = saveURL

            // Attach to a window so it actually renders
            if let window = NSApp.mainWindow {
                window.contentView?.addSubview(offscreen)
                offscreen.isHidden = true
            }

            offscreen.loadHTMLString(html, baseURL: nil)
        }

        private func finishPDFExport(_ offscreenWebView: WKWebView) {
            guard let saveURL = pdfSaveURL else { return }

            // Get full content height, then resize and create PDF
            offscreenWebView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                let contentHeight = result as? CGFloat ?? 841.89
                offscreenWebView.frame.size.height = contentHeight

                // Small delay to let layout settle after resize
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let pdfConfig = WKPDFConfiguration()
                    // Don't set rect — captures full scrollable content as one page
                    // Then we split into A4 pages

                    offscreenWebView.createPDF(configuration: pdfConfig) { [weak self] pdfResult in
                        offscreenWebView.removeFromSuperview()
                        self?.pdfWebView = nil
                        self?.pdfSaveURL = nil

                        switch pdfResult {
                        case .success(let fullData):
                            let a4Data = PDFPaginator.paginate(
                                pdfData: fullData,
                                pageWidth: 595.28,
                                pageHeight: 841.89,
                                margin: 48
                            )
                            try? a4Data.write(to: saveURL)
                        case .failure:
                            break
                        }
                    }
                }
            }
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if this is the offscreen PDF web view
            if webView === pdfWebView {
                finishPDFExport(webView)
                return
            }

            if savedScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollY))")
            }
            // Inject and run TOC script
            let tocJS = TOCScript.source
            webView.evaluateJavaScript(tocJS)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "tocHandler", let json = message.body as? String {
                if let data = json.data(using: .utf8),
                   let headings = try? JSONDecoder().decode([TOCHeading].self, from: data) {
                    onTOCExtracted?(headings)
                }
            }
            if message.name == "activeHeading", let id = message.body as? String {
                onActiveHeadingChanged?(id)
            }
            if message.name == "copyToClipboard", let text = message.body as? String {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }
}

private enum TOCScript {
    static let source = """
    (function() {
        'use strict';
        function extractTOC() {
            var headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
            var toc = [];
            for (var i = 0; i < headings.length; i++) {
                var h = headings[i];
                if (!h.id) h.id = 'heading-' + i;
                toc.push({ id: h.id, text: h.textContent.trim(), level: parseInt(h.tagName[1]) });
            }
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tocHandler) {
                window.webkit.messageHandlers.tocHandler.postMessage(JSON.stringify(toc));
            }
            setupScrollObserver(headings);
        }
        function setupScrollObserver(headings) {
            if (!headings.length) return;
            var observer = new IntersectionObserver(function(entries) {
                for (var i = 0; i < entries.length; i++) {
                    if (entries[i].isIntersecting) {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.activeHeading) {
                            window.webkit.messageHandlers.activeHeading.postMessage(entries[i].target.id);
                        }
                        break;
                    }
                }
            }, { rootMargin: '-10% 0px -80% 0px' });
            for (var i = 0; i < headings.length; i++) { observer.observe(headings[i]); }
        }
        window.scrollToHeading = function(id) {
            var el = document.getElementById(id);
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        };
        extractTOC();
    })();
    """
}
