import Foundation

/// The HTML shown in a new tab. Rendered inside the web view so it is fully interactive
/// through the same input bridge as any other page.
enum StartPage {

    struct Shortcut {
        let title: String
        let url: String
        let color: String
    }

    static let shortcuts: [Shortcut] = [
        Shortcut(title: "Gmail", url: "https://mail.google.com", color: "#ea4335"),
        Shortcut(title: "Calendar", url: "https://calendar.google.com", color: "#4285f4"),
        Shortcut(title: "Drive", url: "https://drive.google.com", color: "#fbbc04"),
        Shortcut(title: "Notion", url: "https://www.notion.so", color: "#ffffff"),
        Shortcut(title: "Slack", url: "https://app.slack.com", color: "#4a154b"),
        Shortcut(title: "GitHub", url: "https://github.com", color: "#24292f"),
        Shortcut(title: "YouTube", url: "https://www.youtube.com", color: "#ff0000"),
        Shortcut(title: "Wikipedia", url: "https://en.wikipedia.org", color: "#636466")
    ]

    @MainActor
    static func html() -> String {
        let engine = Settings.shared.searchEngine
        let action: String
        let param: String
        switch engine {
        case .google: action = "https://www.google.com/search"; param = "q"
        case .duckduckgo: action = "https://duckduckgo.com/"; param = "q"
        case .bing: action = "https://www.bing.com/search"; param = "q"
        }
        let tiles = shortcuts.map { s in
            let initial = String(s.title.prefix(1))
            return """
            <a class="tile" href="\(s.url)"><span class="badge" style="background:\(s.color)">\(initial)</span><span>\(s.title)</span></a>
            """
        }.joined()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        let date = formatter.string(from: Date())

        return ##"""
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>New Tab</title>
        <style>
          html, body { height: 100%; margin: 0; }
          body { font-family: -apple-system, system-ui, "SF Pro Text", sans-serif; color: #f2f2f5;
                 background: radial-gradient(1200px 600px at 50% -10%, #2a3b63 0%, #121419 60%, #0d0e12 100%);
                 display: flex; align-items: center; justify-content: center; }
          .wrap { width: min(760px, 86vw); text-align: center; }
          .clock { font-size: 64px; font-weight: 200; letter-spacing: -1px; margin: 0; }
          .date { color: #9a9ca6; margin: 4px 0 36px; font-size: 15px; }
          form { position: relative; }
          input { width: 100%; box-sizing: border-box; font: 18px -apple-system, system-ui, sans-serif; padding: 16px 22px 16px 52px;
                  border-radius: 16px; border: 1px solid rgba(255,255,255,0.14); background: rgba(255,255,255,0.08); color: #fff; outline: none; }
          input:focus { border-color: #3f84fa; background: rgba(255,255,255,0.11); box-shadow: 0 0 0 4px rgba(63,132,250,0.25); }
          input::placeholder { color: #8a8c96; }
          .icon { position: absolute; left: 20px; top: 50%; transform: translateY(-50%); width: 20px; height: 20px; opacity: .6 }
          .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 14px; margin-top: 40px; }
          .tile { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 18px 8px 14px; border-radius: 16px;
                  background: rgba(255,255,255,0.05); text-decoration: none; color: #d8d9e0; font-size: 13px; border: 1px solid transparent; }
          .tile:hover { background: rgba(255,255,255,0.1); border-color: rgba(255,255,255,0.12); }
          .badge { width: 44px; height: 44px; border-radius: 12px; display: inline-flex; align-items: center; justify-content: center;
                   font-weight: 700; font-size: 20px; color: #fff; text-shadow: 0 1px 2px rgba(0,0,0,.35); }
          .hint { color: #6f717c; font-size: 12px; margin-top: 36px; }
          kbd { font: 11px ui-monospace, Menlo, monospace; padding: 2px 6px; border-radius: 5px; background: rgba(255,255,255,.1); border: 1px solid rgba(255,255,255,.15); }
        </style></head>
        <body>
          <div class="wrap">
            <p class="clock" id="clock"></p>
            <p class="date">__DATE__</p>
            <form action="__ACTION__" method="get">
              <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>
              <input name="__PARAM__" id="q" autocomplete="off" placeholder="Search __ENGINE__ or enter a website" autofocus>
            </form>
            <div class="grid">__TILES__</div>
            <p class="hint"><kbd>⌘L</kbd> address bar &nbsp; <kbd>⌘T</kbd> new tab &nbsp; <kbd>⌘Space</kbd> launcher</p>
          </div>
          <script>
            function tick() {
              const d = new Date();
              document.getElementById('clock').textContent = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            }
            tick(); setInterval(tick, 10000);
            setTimeout(function () { document.getElementById('q').focus(); }, 50);
          </script>
        </body></html>
        """##
        .replacingOccurrences(of: "__DATE__", with: date)
        .replacingOccurrences(of: "__ACTION__", with: action)
        .replacingOccurrences(of: "__PARAM__", with: param)
        .replacingOccurrences(of: "__ENGINE__", with: engine.title)
        .replacingOccurrences(of: "__TILES__", with: tiles)
    }

    static func errorHTML(message: String, url: String) -> String {
        let safeMessage = message.replacingOccurrences(of: "<", with: "&lt;")
        let safeURL = url.replacingOccurrences(of: "<", with: "&lt;")
        return ##"""
        <!doctype html><html><head><meta charset="utf-8"><title>Can’t open page</title>
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; background: #141518; color: #e8e8ec; margin: 0; height: 100vh;
                 display: flex; align-items: center; justify-content: center; text-align: center; }
          h1 { font-weight: 600; font-size: 22px; margin: 0 0 8px; }
          p { color: #9a9ca6; margin: 0 0 20px; max-width: 480px; }
          code { color: #c8c9d2; }
          a { display: inline-block; padding: 9px 18px; border-radius: 9px; background: #3f84fa; color: #fff; text-decoration: none; font-size: 14px; }
        </style></head>
        <body><div><h1>DeskMode can’t open the page</h1><p>__MESSAGE__</p><p><code>__URL__</code></p><a href="__URL__">Try again</a></div></body></html>
        """##
        .replacingOccurrences(of: "__MESSAGE__", with: safeMessage)
        .replacingOccurrences(of: "__URL__", with: safeURL)
    }
}
