// TOC extraction and scroll tracking for LightMD
(function() {
    'use strict';

    function extractTOC() {
        const headings = document.querySelectorAll('#content h1, #content h2, #content h3, #content h4, #content h5, #content h6');
        const toc = [];
        headings.forEach(function(h, i) {
            if (!h.id) {
                h.id = 'heading-' + i;
            }
            toc.push({
                id: h.id,
                text: h.textContent.trim(),
                level: parseInt(h.tagName[1])
            });
        });

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

        headings.forEach(function(h) { observer.observe(h); });
    }

    window.scrollToHeading = function(id) {
        var el = document.getElementById(id);
        if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    };

    // Run after DOM is loaded
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', extractTOC);
    } else {
        extractTOC();
    }
})();
