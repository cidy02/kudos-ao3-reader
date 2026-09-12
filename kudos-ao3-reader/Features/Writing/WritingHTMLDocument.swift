import Foundation
import SwiftSoup

nonisolated enum WritingHTMLDocument {
    /// Rich editing must never silently discard unsupported markup. Source mode
    /// remains available for arbitrary AO3 HTML; supported fragments render offline.
    static func supportsRichEditing(_ html: String) -> Bool {
        let allowed = Set(["body", "p", "br", "hr", "em", "strong", "b", "i", "u", "s", "strike",
                           "blockquote", "a", "span", "div", "ul", "ol", "li", "sup", "sub", "pre", "code"])
        guard let body = try? SwiftSoup.parseBodyFragment(html).body(),
              let elements = try? body.getAllElements().array() else { return false }
        return elements.allSatisfy { element in
            guard allowed.contains(element.tagName()) else { return false }
            return element.getAttributes()?.asList().allSatisfy { attribute in
                let key = attribute.getKey().lowercased()
                if key == "href" {
                    return element.tagName() == "a" && safeLink(attribute.getValue())
                }
                return ["class", "title", "lang", "dir"].contains(key)
            } ?? true
        }
    }

    static func safeLink(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["https", "http", "mailto"].contains(scheme)
    }

    static let html = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline';
    script-src 'none'; img-src 'none'; connect-src 'none'; form-action 'none'; base-uri 'none'">
    <style>
    :root { color-scheme: light dark; font: -apple-system-body; }
    html, body { margin:0; height:100%; background:transparent; }
    #rich, #source { box-sizing:border-box; width:100%; min-height:100%; padding:16px;
      outline:none; color:inherit; background:transparent; border:0; }
    #rich { font-family:Georgia,serif; font-size:1.05rem; line-height:1.6; overflow-wrap:anywhere; }
    #source { height:100%; resize:none; font:1rem/1.5 ui-monospace,monospace; }
    a { color:var(--link); }
    blockquote { margin-left:1em; border-left:2px solid GrayText; padding-left:1em; }
    </style></head><body>
    <div id="rich" contenteditable="true" role="textbox" aria-label="Formatted text" aria-multiline="true"></div>
    <textarea id="source" aria-label="HTML source" hidden></textarea>
    </body></html>
    """

    // Runs only in WebKit's isolated client world, never in the author's page world.
    static let script = #"""
    const rich = document.getElementById('rich'), source = document.getElementById('source');
    let raw = '', sourceMode = false, range = null;
    const send = () => window.webkit.messageHandlers.writing.postMessage(raw);
    rich.addEventListener('input', () => { raw = rich.innerHTML; send(); });
    source.addEventListener('input', () => { raw = source.value; send(); });
    document.addEventListener('selectionchange', () => {
      const s = getSelection();
      if (s.rangeCount && rich.contains(s.anchorNode)) range = s.getRangeAt(0).cloneRange();
    });
    const restore = () => {
      rich.focus();
      if (range && rich.contains(range.startContainer)) {
        const s = getSelection(); s.removeAllRanges(); s.addRange(range);
      }
    };
    // Pasted markup never enters the live DOM. Plain-text insertion preserves undo.
    rich.addEventListener('paste', e => {
      e.preventDefault(); document.execCommand('insertText', false, e.clipboardData.getData('text/plain'));
    });
    rich.addEventListener('drop', e => e.preventDefault());
    document.addEventListener('click', e => { if (e.target.closest('a')) e.preventDefault(); });
    window.writing = {
      snapshot() { document.activeElement.blur(); return raw; },
      set(value, useSource) {
        raw = value; sourceMode = useSource; range = null;
        source.hidden = !useSource; rich.hidden = useSource;
        if (useSource) source.value = value; else rich.innerHTML = value;
      },
      command(tag, href) {
        if (tag === 'undo' || tag === 'redo') {
          if (sourceMode) source.focus(); else restore();
          document.execCommand(tag); raw = sourceMode ? source.value : rich.innerHTML; send(); return;
        }
        if (sourceMode) {
          source.focus();
          const start = source.selectionStart, end = source.selectionEnd;
          const selected = source.value.slice(start, end);
          const open = tag === 'a' ? '<a href="' + href.replaceAll('&', '&amp;').replaceAll('"', '&quot;') + '">' : '<' + tag + '>';
          const close = ['br', 'hr'].includes(tag) ? '' : '</' + tag + '>';
          document.execCommand('insertText', false, open + selected + close);
          raw = source.value; send();
        } else {
          restore();
          if (tag === 'strong') document.execCommand('bold');
          else if (tag === 'em') document.execCommand('italic');
          else if (tag === 'a') document.execCommand('createLink', false, href);
          else if (tag === 'p' || tag === 'blockquote') document.execCommand('formatBlock', false, tag);
          else if (tag === 'br') document.execCommand('insertLineBreak');
          else if (tag === 'hr') document.execCommand('insertHorizontalRule');
          raw = rich.innerHTML; send();
        }
      }
    };
    """#
}
