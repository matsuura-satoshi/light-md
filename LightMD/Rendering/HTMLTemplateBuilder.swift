import Foundation

enum HTMLTemplateBuilder {

    static func build(body: String, themeCSS: String? = nil, fontOverrideCSS: String? = nil) -> String {
        let css = themeCSS ?? BuiltinThemes.warmLight
        let fontCSS = fontOverrideCSS ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style id="theme-css">\(css)</style>
            <style id="font-override">\(fontCSS)</style>
        </head>
        <body>
            <article id="content">\(body)</article>
            <script>\(copyButtonScript)</script>
        </body>
        </html>
        """
    }

    private static let copyButtonScript = """
    (function() {
        var svgCopy = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>';
        var svgCheck = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

        function copyText(text, btn) {
            window.webkit.messageHandlers.copyToClipboard.postMessage(text);
            btn.innerHTML = svgCheck;
            btn.classList.add('copied');
            setTimeout(function() {
                btn.innerHTML = svgCopy;
                btn.classList.remove('copied');
            }, 1500);
        }

        document.querySelectorAll('pre').forEach(function(pre) {
            var btn = document.createElement('button');
            btn.className = 'copy-btn';
            btn.innerHTML = svgCopy;
            btn.title = 'Copy';
            btn.onclick = function() {
                var code = pre.querySelector('code');
                copyText(code ? code.textContent : pre.textContent, btn);
            };
            pre.appendChild(btn);
        });

        document.querySelectorAll('blockquote').forEach(function(bq) {
            var btn = document.createElement('button');
            btn.className = 'copy-btn';
            btn.innerHTML = svgCopy;
            btn.title = 'Copy';
            btn.onclick = function() {
                copyText(bq.textContent.trim(), btn);
            };
            bq.appendChild(btn);
        });
    })();
    """
}
