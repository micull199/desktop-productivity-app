import UIKit

/// HTML for the new-tab page and the error page. Both render inside the web view so they are
/// fully interactive through the same input bridge as any other page.
enum StartPage {

    struct Shortcut {
        let title: String
        let url: String
    }

    static let defaultShortcuts: [Shortcut] = [
        Shortcut(title: "Gmail", url: "https://mail.google.com"),
        Shortcut(title: "Calendar", url: "https://calendar.google.com"),
        Shortcut(title: "Drive", url: "https://drive.google.com"),
        Shortcut(title: "YouTube", url: "https://www.youtube.com"),
        Shortcut(title: "Notion", url: "https://www.notion.so"),
        Shortcut(title: "Slack", url: "https://app.slack.com"),
        Shortcut(title: "GitHub", url: "https://github.com"),
        Shortcut(title: "Wikipedia", url: "https://en.wikipedia.org"),
        Shortcut(title: "Maps", url: "https://maps.google.com"),
        Shortcut(title: "Docs", url: "https://docs.google.com")
    ]

    static let maxTiles = 10

    /// Bookmarks first, then defaults, de-duplicated by host, at most ten.
    static func shortcuts(bookmarks: [Bookmark]) -> [Shortcut] {
        var seen = Set<String>()
        var out: [Shortcut] = []
        for b in bookmarks {
            let host = b.host.isEmpty ? (URL(string: b.url)?.host ?? b.url) : b.host
            guard seen.insert(host.lowercased()).inserted else { continue }
            out.append(Shortcut(title: b.title, url: b.url))
            if out.count == maxTiles { return out }
        }
        for s in defaultShortcuts {
            let host = URL(string: s.url)?.host ?? s.url
            guard seen.insert(host.lowercased()).inserted else { continue }
            out.append(s)
            if out.count == maxTiles { break }
        }
        return out
    }

    @MainActor
    static func html(bookmarks: [Bookmark]) -> String {
        let engine = Settings.shared.searchEngine
        let action: String
        switch engine {
        case .google: action = "https://www.google.com/search"
        case .duckduckgo: action = "https://duckduckgo.com/"
        case .bing: action = "https://www.bing.com/search"
        }
        let tiles = shortcuts(bookmarks: bookmarks).map { s in
            let host = URL(string: s.url)?.host ?? s.url
            let initial = escape(String(s.title.prefix(1)).uppercased())
            return """
            <a class="tile" href="\(escape(s.url))" title="\(escape(s.title))">\
            <span class="icon"><span class="initial">\(initial)</span>\
            <img src="https://www.google.com/s2/favicons?domain=\(escape(host))&amp;sz=64" alt="" loading="lazy" \
            onload="this.previousElementSibling.style.display='none'" onerror="this.style.display='none'"></span>\
            <span class="label">\(escape(s.title))</span></a>
            """
        }.joined()

        let hues = Theme.wallpaperColors(Settings.shared.wallpaper)
        let hue1 = rgba(hues[0], alpha: 0.55)
        let hue2 = rgba(hues[min(1, hues.count - 1)], alpha: 0.28)
        let hue3 = rgba(hues[min(2, hues.count - 1)], alpha: 0.16)

        return ##"""
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>New Tab</title>
        <style>
          :root { color-scheme: dark; }
          html, body { height: 100%; margin: 0; }
          body { font-family: -apple-system, system-ui, "SF Pro Text", sans-serif; color: #f1f2f5;
                 background: #0e0f12;
                 background-image:
                   radial-gradient(1100px 560px at 50% -12%, __HUE1__ 0%, rgba(0,0,0,0) 62%),
                   radial-gradient(900px 520px at 12% 108%, __HUE2__ 0%, rgba(0,0,0,0) 60%),
                   radial-gradient(760px 480px at 92% 96%, __HUE3__ 0%, rgba(0,0,0,0) 60%),
                   linear-gradient(180deg, #121419 0%, #0c0d10 100%);
                 background-attachment: fixed;
                 display: flex; align-items: center; justify-content: center; -webkit-user-select: none; user-select: none; }
          .wrap { width: min(640px, 86vw); text-align: center; transform: translateY(-4vh); }
          .logo { font-size: 15px; font-weight: 600; letter-spacing: 0.2px; color: rgba(255,255,255,0.55); margin: 0 0 22px; }
          form { position: relative; margin: 0 auto; }
          input { width: 100%; height: 52px; box-sizing: border-box; font: 16px -apple-system, system-ui, sans-serif;
                  padding: 0 52px 0 54px; border-radius: 26px; border: 1px solid rgba(255,255,255,0.10);
                  background: rgba(255,255,255,0.075); color: #fff; outline: none;
                  box-shadow: 0 10px 30px rgba(0,0,0,0.38), inset 0 1px 0 rgba(255,255,255,0.05);
                  transition: background .16s ease-out, border-color .16s ease-out, box-shadow .16s ease-out; }
          input:hover { background: rgba(255,255,255,0.10); }
          input:focus { background: rgba(255,255,255,0.11); border-color: rgba(66,133,244,0.9);
                        box-shadow: 0 10px 30px rgba(0,0,0,0.38), 0 0 0 3px rgba(66,133,244,0.35); }
          input::placeholder { color: rgba(255,255,255,0.42); }
          .icon-search { position: absolute; left: 20px; top: 50%; transform: translateY(-50%); width: 18px; height: 18px; opacity: .55; pointer-events: none; }
          .go { position: absolute; right: 8px; top: 8px; width: 36px; height: 36px; border-radius: 18px; border: 0; background: transparent;
                color: rgba(255,255,255,0.6); display: flex; align-items: center; justify-content: center; cursor: pointer; }
          .go:hover { background: rgba(255,255,255,0.1); color: #fff; }
          .go svg { width: 16px; height: 16px; }
          .grid { display: grid; grid-template-columns: repeat(5, 96px); justify-content: center; gap: 10px 8px; margin-top: 34px; }
          .tile { display: flex; flex-direction: column; align-items: center; gap: 9px; padding: 12px 6px 10px; border-radius: 14px;
                  text-decoration: none; color: rgba(255,255,255,0.82); font-size: 12px;
                  transition: background .14s ease-out; }
          .tile:hover { background: rgba(255,255,255,0.07); }
          .tile:active { background: rgba(255,255,255,0.12); }
          .icon { width: 48px; height: 48px; border-radius: 24px; background: rgba(255,255,255,0.085); display: flex; align-items: center; justify-content: center;
                  position: relative; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05); transition: background .14s ease-out, transform .14s ease-out; }
          .tile:hover .icon { background: rgba(255,255,255,0.13); }
          .icon img { width: 24px; height: 24px; border-radius: 4px; }
          .initial { position: absolute; font-weight: 600; font-size: 17px; color: rgba(255,255,255,0.7); }
          .label { max-width: 88px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .hint { color: rgba(255,255,255,0.28); font-size: 11px; margin-top: 40px; }
          kbd { font: 10.5px -apple-system, system-ui, sans-serif; padding: 1px 5px; border-radius: 4px; background: rgba(255,255,255,.07); border: 1px solid rgba(255,255,255,.1); color: rgba(255,255,255,0.45); }
          @media (max-height: 560px) { .grid { margin-top: 22px; } .hint { display: none; } }
        </style></head>
        <body>
          <div class="wrap">
            <p class="logo">__ENGINE__</p>
            <form action="__ACTION__" method="get" autocomplete="off">
              <svg class="icon-search" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>
              <input name="q" id="q" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" placeholder="Search __ENGINE__ or type a URL" autofocus>
              <button class="go" type="submit" aria-label="Search"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg></button>
            </form>
            <div class="grid">__TILES__</div>
            <p class="hint"><kbd>⌘L</kbd> address bar &nbsp;·&nbsp; <kbd>⌘T</kbd> new tab &nbsp;·&nbsp; <kbd>⌘Space</kbd> launcher</p>
          </div>
          <script>
            (function () {
              var q = document.getElementById('q');
              var form = q.form;
              // Bare hostnames open directly instead of being searched.
              form.addEventListener('submit', function (ev) {
                var t = q.value.trim();
                if (!t) { ev.preventDefault(); return; }
                var isURL = /^(https?:\/\/)/i.test(t) || (/^[a-z0-9.-]+\.[a-z]{2,}(\/\S*)?$/i.test(t) && t.indexOf(' ') < 0) || /^localhost(:\d+)?/.test(t);
                if (isURL) { ev.preventDefault(); location.href = /^https?:\/\//i.test(t) ? t : (t.indexOf('localhost') === 0 ? 'http://' : 'https://') + t; }
              });
              setTimeout(function () { q.focus(); }, 40);
            })();
          </script>
        </body></html>
        """##
        .replacingOccurrences(of: "__ACTION__", with: action)
        .replacingOccurrences(of: "__ENGINE__", with: escape(engine.title))
        .replacingOccurrences(of: "__TILES__", with: tiles)
        .replacingOccurrences(of: "__HUE1__", with: hue1)
        .replacingOccurrences(of: "__HUE2__", with: hue2)
        .replacingOccurrences(of: "__HUE3__", with: hue3)
    }

    /// Dark error page with the host in the title and a Retry button.
    static func errorHTML(message: String, url: String) -> String {
        let host = URL(string: url)?.host ?? url
        return ##"""
        <!doctype html><html><head><meta charset="utf-8"><title>__HOST__</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: dark; }
          html, body { height: 100%; margin: 0; }
          body { font-family: -apple-system, system-ui, sans-serif; background: #0e0f12; color: #ececf0;
                 display: flex; align-items: center; justify-content: center; -webkit-user-select: none; user-select: none; }
          .card { width: min(520px, 86vw); padding: 0 8px; }
          .glyph { width: 72px; height: 72px; border-radius: 20px; background: rgba(255,255,255,0.06); display: flex; align-items: center; justify-content: center; margin-bottom: 26px; }
          .glyph svg { width: 36px; height: 36px; stroke: rgba(255,255,255,0.55); }
          h1 { font-weight: 600; font-size: 22px; margin: 0 0 10px; letter-spacing: -0.2px; }
          p { color: rgba(255,255,255,0.6); margin: 0 0 8px; font-size: 14px; line-height: 1.5; }
          b { color: #fff; font-weight: 600; }
          .detail { color: rgba(255,255,255,0.38); font-size: 12px; margin-top: 14px; }
          .actions { margin-top: 26px; display: flex; gap: 10px; }
          a.button { display: inline-block; padding: 9px 20px; border-radius: 8px; background: #4285f4; color: #fff; text-decoration: none; font-size: 14px; font-weight: 600;
                     box-shadow: 0 6px 18px rgba(66,133,244,0.3); transition: background .14s ease-out; }
          a.button:hover { background: #5a96f6; }
          a.button:active { background: #3b78dc; }
          a.secondary { background: rgba(255,255,255,0.08); box-shadow: none; }
          a.secondary:hover { background: rgba(255,255,255,0.14); }
        </style></head>
        <body><div class="card">
          <div class="glyph"><svg viewBox="0 0 24 24" fill="none" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3.5 9h17M3.5 15h17M12 3c2.8 3 2.8 15 0 18M12 3c-2.8 3-2.8 15 0 18"/><path d="M4 4l16 16" stroke="rgba(255,96,96,0.9)"/></svg></div>
          <h1>This site can’t be reached</h1>
          <p><b>__HOST__</b> took too long to respond or refused the connection.</p>
          <p class="detail">__MESSAGE__</p>
          <div class="actions"><a class="button" href="__URL__">Retry</a></div>
        </div></body></html>
        """##
        .replacingOccurrences(of: "__HOST__", with: escape(host))
        .replacingOccurrences(of: "__MESSAGE__", with: escape(message))
        .replacingOccurrences(of: "__URL__", with: escape(url))
    }

    // MARK: Helpers

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func rgba(_ color: CGColor, alpha: CGFloat) -> String {
        let c = UIColor(cgColor: color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(alpha))"
    }
}
