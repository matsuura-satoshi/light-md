import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let htmlContent: String
    let bodyHTML: String
    let themeCSS: String
    let fontOverrideCSS: String
    var scrollTarget: String?
    var exportTrigger: UUID?
    var onTOCExtracted: (([TOCHeading]) -> Void)?
    var onActiveHeadingChanged: ((String) -> Void)?
    var onScrollComplete: (() -> Void)?

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
        // Prevent WebKit from intercepting file drops so the SwiftUI .onDrop
        // on ContentView reliably receives them.
        webView.unregisterDraggedTypes()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTOCExtracted = onTOCExtracted
        coordinator.onActiveHeadingChanged = onActiveHeadingChanged

        // Always-current snapshot for exportPDF. Kept separate from the
        // last* diff anchors below so the export path never depends on
        // hot-swap timing or DOM serialization.
        coordinator.currentBodyHTML = bodyHTML
        coordinator.currentThemeCSS = themeCSS
        coordinator.currentFontOverrideCSS = fontOverrideCSS

        // Scroll to heading
        if let target = scrollTarget, target != coordinator.lastScrollTarget {
            coordinator.lastScrollTarget = target
            let escaped = target.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("scrollToHeading('\(escaped)')")
            DispatchQueue.main.async {
                self.onScrollComplete?()
            }
        }

        // Export PDF — defer to the next runloop tick so NSSavePanel.runModal()
        // does not run inside SwiftUI's view-update cycle. Running it inline
        // silently fails to present the panel (observed for the toolbar icon
        // and the Cmd+P NSEvent monitor paths).
        if let trigger = exportTrigger, trigger != coordinator.lastExportTrigger {
            coordinator.lastExportTrigger = trigger
            DispatchQueue.main.async {
                coordinator.exportPDF()
            }
        }

        // HTML body changed → full reload (theme CSS bundled into the document)
        if htmlContent != coordinator.lastHTML {
            coordinator.lastHTML = htmlContent
            coordinator.lastThemeCSS = themeCSS
            coordinator.lastFontOverrideCSS = fontOverrideCSS
            webView.evaluateJavaScript("window.scrollY") { result, _ in
                coordinator.savedScrollY = result as? Double ?? 0
                webView.loadHTMLString(htmlContent, baseURL: nil)
            }
            return
        }

        // Body unchanged, only CSS changed → hot-swap in place via JS.
        // Avoids a navigation event, so scroll position and TOC observer
        // are preserved with no flicker.
        if themeCSS != coordinator.lastThemeCSS {
            coordinator.lastThemeCSS = themeCSS
            webView.evaluateJavaScript(Self.cssSwapJS(styleID: "theme-css", css: themeCSS))
        }
        if fontOverrideCSS != coordinator.lastFontOverrideCSS {
            coordinator.lastFontOverrideCSS = fontOverrideCSS
            webView.evaluateJavaScript(Self.cssSwapJS(styleID: "font-override", css: fontOverrideCSS))
        }
    }

    /// Builds a JS snippet that replaces the text content of a `<style>` tag
    /// in-place. Uses JSONSerialization to safely encode the CSS as a JS string
    /// literal — handles backslashes, quotes, newlines, and non-ASCII correctly.
    static func cssSwapJS(styleID: String, css: String) -> String {
        let jsLiteral = jsStringLiteral(css)
        // Fall back to creating a fresh <style> element if the target is missing
        // (e.g. after a body rebuild that hasn't finished loading yet).
        return """
        (function() {
            var el = document.getElementById('\(styleID)');
            if (!el) {
                el = document.createElement('style');
                el.id = '\(styleID)';
                document.head.appendChild(el);
            }
            el.textContent = \(jsLiteral);
        })();
        """
    }

    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.hasPrefix("["), json.hasSuffix("]") else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var savedScrollY: Double = 0
        var lastHTML: String = ""
        var lastThemeCSS: String = ""
        var lastFontOverrideCSS: String = ""
        var lastScrollTarget: String?
        var lastExportTrigger: UUID?
        var currentBodyHTML: String = ""
        var currentThemeCSS: String = ""
        var currentFontOverrideCSS: String = ""
        var onTOCExtracted: (([TOCHeading]) -> Void)?
        var onActiveHeadingChanged: ((String) -> Void)?

        init(onTOCExtracted: (([TOCHeading]) -> Void)?, onActiveHeadingChanged: ((String) -> Void)?) {
            self.onTOCExtracted = onTOCExtracted
            self.onActiveHeadingChanged = onActiveHeadingChanged
        }

        private var pdfWebView: WKWebView?
        private var pdfSaveURL: URL?

        func exportPDF() {
            guard webView != nil else { return }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "document.pdf"
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let saveURL = panel.url else { return }

            // Rebuild a fresh HTML document from the Swift-side state rather
            // than extracting outerHTML from the live DOM. The live preview
            // hot-swaps the <style id="font-override"> textContent on CSS-only
            // updates, and round-tripping that through outerHTML has been
            // observed to lose the current font size in the exported PDF.
            // Copy buttons (JS-injected) are intentionally absent here — they
            // are hidden in print anyway via @media print.
            let html = HTMLTemplateBuilder.build(
                body: currentBodyHTML,
                themeCSS: currentThemeCSS,
                fontOverrideCSS: currentFontOverrideCSS
            )
            renderPDFOffscreen(html: html, saveURL: saveURL)
        }

        private func renderPDFOffscreen(html: String, saveURL: URL) {
            let a4Width: CGFloat = 595.28

            let config = WKWebViewConfiguration()
            let offscreen = WKWebView(frame: CGRect(x: -9999, y: -9999, width: a4Width, height: 10), configuration: config)
            offscreen.navigationDelegate = self
            self.pdfWebView = offscreen
            self.pdfSaveURL = saveURL

            if let window = webView?.window {
                window.contentView?.addSubview(offscreen)
            }

            offscreen.loadHTMLString(html, baseURL: nil)
        }

        private func finishPDFExport(_ offscreenWebView: WKWebView) {
            guard let saveURL = pdfSaveURL,
                  let window = webView?.window else {
                pdfWebView?.removeFromSuperview()
                pdfWebView = nil
                pdfSaveURL = nil
                return
            }

            let printInfo = NSPrintInfo()
            printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 32
            printInfo.rightMargin = 32
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = false
            printInfo.jobDisposition = .save
            printInfo.dictionary().setValue(saveURL, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue)

            let printOp = offscreenWebView.printOperation(with: printInfo)
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = false

            printOp.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }

        @objc nonisolated private func printOperationDidRun(
            _ printOperation: NSPrintOperation,
            success: Bool,
            contextInfo: UnsafeMutableRawPointer?
        ) {
            DispatchQueue.main.async { [weak self] in
                self?.pdfWebView?.removeFromSuperview()
                self?.pdfWebView = nil
                self?.pdfSaveURL = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView === pdfWebView {
                finishPDFExport(webView)
                return
            }

            if savedScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(savedScrollY))")
            }
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
