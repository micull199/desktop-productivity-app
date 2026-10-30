import Foundation

/// JavaScript injected into every page. It turns the desktop's virtual cursor and keyboard
/// into real DOM events, so links, buttons, forms, text selection and custom widgets behave
/// as they would under a real mouse.
enum BrowserScripts {

    static let bridge = #"""
    (function () {
      if (window.__dm) { return; }
      const dm = {};
      let hovered = null;
      let downEl = null;
      let downButton = -1;
      let selecting = false;
      let selectAnchor = null;
      let lastX = 0, lastY = 0;
      let selectPopup = null;

      // ---- helpers -------------------------------------------------------------

      function resolve(x, y) {
        let doc = document;
        let el = doc.elementFromPoint(x, y);
        // Descend into same-origin iframes so embedded content is clickable too.
        for (let i = 0; i < 6 && el && el.tagName === 'IFRAME'; i++) {
          try {
            const inner = el.contentDocument;
            if (!inner) { break; }
            const r = el.getBoundingClientRect();
            x -= r.left; y -= r.top;
            doc = inner;
            el = inner.elementFromPoint(x, y);
          } catch (e) { break; }
        }
        return { doc: doc, el: el, x: x, y: y };
      }

      function fire(el, type, x, y, button, extra) {
        if (!el) { return true; }
        const win = el.ownerDocument.defaultView || window;
        const init = Object.assign({
          bubbles: true, cancelable: true, composed: true, view: win,
          clientX: x, clientY: y, screenX: x, screenY: y,
          button: button || 0, buttons: (downButton === 0 ? 1 : downButton === 2 ? 2 : 0)
        }, extra || {});
        let ev;
        if (type.indexOf('pointer') === 0) {
          ev = new PointerEvent(type, Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true, width: 1, height: 1, pressure: button === undefined ? 0 : 0.5 }, init));
        } else if (type === 'wheel') {
          ev = new WheelEvent(type, init);
        } else {
          ev = new MouseEvent(type, init);
        }
        return el.dispatchEvent(ev);
      }

      function isEditable(el) {
        if (!el) { return false; }
        if (el.isContentEditable) { return true; }
        const tag = el.tagName;
        if (tag === 'TEXTAREA') { return !el.disabled && !el.readOnly; }
        if (tag === 'INPUT') {
          const t = (el.type || 'text').toLowerCase();
          return !el.disabled && !el.readOnly && ['button', 'submit', 'reset', 'checkbox', 'radio', 'file', 'image', 'color', 'range'].indexOf(t) < 0;
        }
        return false;
      }

      function cursorFor(el, x, y) {
        if (!el) { return 'default'; }
        try {
          const c = getComputedStyle(el).cursor;
          if (c && c !== 'auto') { return c; }
        } catch (e) {}
        if (el.closest('a[href],button,[role=button],[role=link],input[type=submit],input[type=button],input[type=checkbox],input[type=radio],select,label,summary,[onclick]')) { return 'pointer'; }
        if (isEditable(el)) { return 'text'; }
        // I-beam over real text, like macOS.
        try {
          const doc = el.ownerDocument;
          const range = doc.caretRangeFromPoint(x, y);
          if (range && range.startContainer && range.startContainer.nodeType === 3) {
            const node = range.startContainer;
            const r = doc.createRange();
            r.selectNodeContents(node);
            const rects = r.getClientRects();
            for (let i = 0; i < rects.length; i++) {
              const rc = rects[i];
              if (x >= rc.left && x <= rc.right && y >= rc.top && y <= rc.bottom) { return 'text'; }
            }
          }
        } catch (e) {}
        return 'default';
      }

      function focusedDoc() {
        let doc = document;
        for (let i = 0; i < 6; i++) {
          const a = doc.activeElement;
          if (a && a.tagName === 'IFRAME') {
            try { if (a.contentDocument) { doc = a.contentDocument; continue; } } catch (e) {}
          }
          break;
        }
        return doc;
      }

      // ---- pointer ---------------------------------------------------------------

      dm.move = function (x, y) {
        lastX = x; lastY = y;
        const r = resolve(x, y);
        const el = r.el;
        if (el !== hovered) {
          if (hovered) {
            fire(hovered, 'pointerout', r.x, r.y);
            fire(hovered, 'mouseout', r.x, r.y);
            fire(hovered, 'pointerleave', r.x, r.y, 0, { bubbles: false });
            fire(hovered, 'mouseleave', r.x, r.y, 0, { bubbles: false });
          }
          if (el) {
            fire(el, 'pointerover', r.x, r.y);
            fire(el, 'mouseover', r.x, r.y);
            fire(el, 'pointerenter', r.x, r.y, 0, { bubbles: false });
            fire(el, 'mouseenter', r.x, r.y, 0, { bubbles: false });
          }
          hovered = el;
        }
        if (el) {
          fire(el, 'pointermove', r.x, r.y);
          fire(el, 'mousemove', r.x, r.y);
        }
        if (selecting && selectAnchor) {
          try {
            const pos = r.doc.caretRangeFromPoint(r.x, r.y);
            if (pos) {
              const sel = r.doc.getSelection();
              sel.setBaseAndExtent(selectAnchor.startContainer, selectAnchor.startOffset, pos.startContainer, pos.startOffset);
            }
          } catch (e) {}
        }
        return cursorFor(el, r.x, r.y);
      };

      dm.down = function (x, y, button, clicks, mods) {
        closeSelectPopup();
        const r = resolve(x, y);
        const el = r.el;
        downEl = el; downButton = button;
        if (!el) { return ''; }
        const ok = fire(el, 'pointerdown', r.x, r.y, button, { detail: clicks }) &&
                   fire(el, 'mousedown', r.x, r.y, button, { detail: clicks });

        const doc = r.doc;
        const focusable = el.closest('input,textarea,select,button,a[href],[contenteditable],[tabindex]');
        const active = doc.activeElement;
        if (focusable && focusable !== active) {
          try { focusable.focus({ preventScroll: true }); } catch (e) {}
        } else if (!focusable && active && active !== doc.body && !(active.isContentEditable)) {
          try { active.blur(); } catch (e) {}
        }

        if (button === 0 && ok) {
          if (isEditable(el) && !el.isContentEditable) {
            // Caret placement inside inputs / textareas.
            if (clicks >= 3) { try { el.select(); } catch (e) {} }
            else if (clicks === 2) { selectWordInField(el); }
            else { placeCaretInField(el, r.x, r.y); }
          } else {
            // Mac-style text selection with the mouse on ordinary page text.
            try {
              const range = doc.caretRangeFromPoint(r.x, r.y);
              const sel = doc.getSelection();
              if (range) {
                if (clicks === 2) {
                  sel.removeAllRanges(); sel.addRange(range);
                  sel.modify('move', 'backward', 'word'); sel.modify('extend', 'forward', 'word');
                } else if (clicks >= 3) {
                  sel.removeAllRanges(); sel.addRange(range);
                  sel.modify('move', 'backward', 'paragraphboundary'); sel.modify('extend', 'forward', 'paragraphboundary');
                } else {
                  if (!(mods & 4)) { sel.removeAllRanges(); }
                  selectAnchor = range; selecting = true;
                }
              }
            } catch (e) {}
          }
        }
        if (button === 2) {
          const link = el.closest('a[href]');
          const img = el.closest('img');
          const sel = doc.getSelection ? doc.getSelection().toString() : '';
          return JSON.stringify({ link: link ? link.href : '', image: img ? img.currentSrc || img.src : '', selection: sel, editable: isEditable(el) });
        }
        return '';
      };

      dm.up = function (x, y, button, clicks) {
        const r = resolve(x, y);
        const el = r.el;
        const wasDown = downEl;
        selecting = false; selectAnchor = null;
        downButton = -1;
        if (!el) { downEl = null; return; }
        fire(el, 'pointerup', r.x, r.y, button, { detail: clicks });
        fire(el, 'mouseup', r.x, r.y, button, { detail: clicks });
        if (button === 0 && wasDown) {
          // A click targets the nearest common ancestor of press and release, like real browsers.
          let target = el;
          if (wasDown !== el) {
            target = wasDown.contains(el) ? wasDown : (el.contains(wasDown) ? el : commonAncestor(wasDown, el));
          }
          if (target) {
            const sel = r.doc.getSelection ? r.doc.getSelection().toString() : '';
            if (!sel || clicks > 1 || isEditable(target) || target.closest('a[href],button,input,select,label,[role=button]')) {
              // A bubbling synthetic click runs the activation behaviour of the nearest
              // <a>, <button>, <label> or checkbox in the event path, exactly like a real click.
              fire(target, 'click', r.x, r.y, 0, { detail: clicks });
              if (clicks === 2) { fire(target, 'dblclick', r.x, r.y, 0, { detail: 2 }); }
              const sel2 = target.closest && target.closest('select');
              if (sel2 && !sel2.disabled) { openSelectPopup(sel2); }
            }
          }
        } else if (button === 1 && wasDown) {
          const link = wasDown.closest && wasDown.closest('a[href]');
          if (link) { window.open(link.href, '_blank'); }
        }
        downEl = null;
      };

      function commonAncestor(a, b) {
        let n = a;
        while (n) { if (n.contains(b)) { return n; } n = n.parentElement; }
        return null;
      }

      dm.scroll = function (x, y, dx, dy) {
        const r = resolve(x, y);
        let el = r.el;
        if (el && !fire(el, 'wheel', r.x, r.y, 0, { deltaX: dx, deltaY: dy, deltaMode: 0 })) { return 'handled'; }
        while (el && el !== r.doc.documentElement && el !== r.doc.body) {
          const cs = getComputedStyle(el);
          const canY = /(auto|scroll|overlay)/.test(cs.overflowY) && el.scrollHeight > el.clientHeight + 1;
          const canX = /(auto|scroll|overlay)/.test(cs.overflowX) && el.scrollWidth > el.clientWidth + 1;
          if ((canY && dy) || (canX && dx)) {
            const t = el.scrollTop, l = el.scrollLeft;
            el.scrollBy(dx, dy);
            if (el.scrollTop !== t || el.scrollLeft !== l) { return 'inner'; }
          }
          el = el.parentElement;
        }
        if (r.doc !== document) {
          const w = r.doc.defaultView;
          w.scrollBy(dx, dy);
          return 'inner';
        }
        return 'main';
      };

      // ---- <select> replacement -------------------------------------------------

      function closeSelectPopup() {
        if (selectPopup) { selectPopup.remove(); selectPopup = null; }
      }

      function openSelectPopup(sel) {
        closeSelectPopup();
        const doc = sel.ownerDocument;
        const rect = sel.getBoundingClientRect();
        const pop = doc.createElement('div');
        pop.setAttribute('data-dm-popup', '1');
        pop.style.cssText = 'position:fixed;z-index:2147483647;left:' + rect.left + 'px;top:' + (rect.bottom + 2) + 'px;min-width:' + Math.max(rect.width, 160) + 'px;max-height:320px;overflow:auto;background:#1e1e22;color:#f2f2f2;border:1px solid rgba(255,255,255,0.18);border-radius:8px;box-shadow:0 12px 32px rgba(0,0,0,0.45);font:13px -apple-system,system-ui,sans-serif;padding:4px;';
        Array.prototype.forEach.call(sel.options, function (opt, i) {
          const row = doc.createElement('div');
          row.textContent = opt.textContent;
          row.style.cssText = 'padding:5px 12px;border-radius:5px;cursor:default;white-space:nowrap;' + (opt.selected ? 'background:#3f84fa;color:#fff;' : '') + (opt.disabled ? 'opacity:0.4;' : '');
          row.addEventListener('mouseenter', function () { if (!opt.disabled) { row.style.background = '#3f84fa'; row.style.color = '#fff'; } });
          row.addEventListener('mouseleave', function () { row.style.background = opt.selected ? '#3f84fa' : ''; row.style.color = opt.selected ? '#fff' : ''; });
          row.addEventListener('click', function (ev) {
            ev.stopPropagation();
            if (opt.disabled) { return; }
            sel.selectedIndex = i;
            sel.dispatchEvent(new Event('input', { bubbles: true }));
            sel.dispatchEvent(new Event('change', { bubbles: true }));
            closeSelectPopup();
          });
          pop.appendChild(row);
        });
        doc.body.appendChild(pop);
        selectPopup = pop;
      }

      // ---- keyboard -------------------------------------------------------------

      function placeCaretInField(el, x, y) {
        try {
          if (el.tagName === 'TEXTAREA' || /^(text|search|url|tel|password)$/i.test(el.type || 'text')) {
            // Approximate caret placement by measuring text width.
            const style = getComputedStyle(el);
            const canvas = placeCaretInField.c || (placeCaretInField.c = document.createElement('canvas'));
            const ctx = canvas.getContext('2d');
            ctx.font = style.font;
            const rect = el.getBoundingClientRect();
            const relX = x - rect.left - parseFloat(style.paddingLeft) + el.scrollLeft;
            const value = el.value;
            if (el.tagName === 'TEXTAREA') { el.setSelectionRange(value.length, value.length); return; }
            let best = value.length, bestD = Infinity;
            for (let i = 0; i <= value.length; i++) {
              const w = ctx.measureText(value.slice(0, i)).width;
              const d = Math.abs(w - relX);
              if (d < bestD) { bestD = d; best = i; }
            }
            el.setSelectionRange(best, best);
          }
        } catch (e) {}
      }

      function selectWordInField(el) {
        try {
          const v = el.value, p = el.selectionStart || 0;
          let a = p, b = p;
          while (a > 0 && /\w/.test(v[a - 1])) { a--; }
          while (b < v.length && /\w/.test(v[b])) { b++; }
          el.setSelectionRange(a, b);
        } catch (e) {}
      }

      function insertText(el, text) {
        if (el.isContentEditable) {
          el.ownerDocument.execCommand('insertText', false, text);
          return;
        }
        let handled = false;
        try {
          const s = el.selectionStart, e = el.selectionEnd;
          if (s !== null && s !== undefined && typeof el.setRangeText === 'function') {
            el.setRangeText(text, s, e, 'end');
            handled = true;
          }
        } catch (err) {}
        if (!handled) { el.value = (el.value || '') + text; }
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
      }

      function deleteInField(el, forward, word) {
        if (el.isContentEditable) {
          el.ownerDocument.execCommand(forward ? 'forwardDelete' : 'delete', false, null);
          return;
        }
        try {
          let s = el.selectionStart, e = el.selectionEnd;
          const v = el.value;
          if (s === null || s === undefined) { el.value = v.slice(0, -1); }
          else if (s !== e) { el.setRangeText('', s, e, 'start'); }
          else if (forward) { if (e < v.length) { el.setRangeText('', s, e + 1, 'start'); } }
          else if (s > 0) {
            let from = s - 1;
            if (word) { while (from > 0 && v[from - 1] === ' ') { from--; } while (from > 0 && v[from - 1] !== ' ' && v[from - 1] !== '\n') { from--; } }
            el.setRangeText('', from, e, 'start');
          }
        } catch (err) { el.value = (el.value || '').slice(0, -1); }
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: forward ? 'deleteContentForward' : 'deleteContentBackward' }));
      }

      function moveCaretInField(el, key, shift, meta, alt) {
        try {
          const v = el.value, len = v.length;
          let s = el.selectionStart, e = el.selectionEnd, dir = el.selectionDirection;
          const head = dir === 'backward' ? s : e;
          let target = head;
          const isTextarea = el.tagName === 'TEXTAREA';
          if (key === 'ArrowLeft' || key === 'Home') {
            if (meta || key === 'Home') { target = isTextarea ? v.lastIndexOf('\n', head - 1) + 1 : 0; }
            else if (alt) { target = head; while (target > 0 && /\W/.test(v[target - 1])) { target--; } while (target > 0 && /\w/.test(v[target - 1])) { target--; } }
            else if (s !== e && !shift) { target = s; }
            else { target = Math.max(0, head - 1); }
          } else if (key === 'ArrowRight' || key === 'End') {
            if (meta || key === 'End') { const nl = isTextarea ? v.indexOf('\n', head) : -1; target = nl < 0 ? len : nl; }
            else if (alt) { target = head; while (target < len && /\W/.test(v[target])) { target++; } while (target < len && /\w/.test(v[target])) { target++; } }
            else if (s !== e && !shift) { target = e; }
            else { target = Math.min(len, head + 1); }
          } else if (key === 'ArrowUp' || key === 'ArrowDown') {
            if (!isTextarea) { target = key === 'ArrowUp' ? 0 : len; }
            else {
              const lineStart = v.lastIndexOf('\n', head - 1) + 1;
              const col = head - lineStart;
              if (key === 'ArrowUp') {
                if (lineStart === 0) { target = 0; }
                else { const prevStart = v.lastIndexOf('\n', lineStart - 2) + 1; target = Math.min(prevStart + col, lineStart - 1); }
              } else {
                const nextNl = v.indexOf('\n', head);
                if (nextNl < 0) { target = len; }
                else { const nextEnd = v.indexOf('\n', nextNl + 1); target = Math.min(nextNl + 1 + col, nextEnd < 0 ? len : nextEnd); }
              }
            }
          }
          if (shift) {
            const anchor = dir === 'backward' ? e : s;
            el.setSelectionRange(Math.min(anchor, target), Math.max(anchor, target), target < anchor ? 'backward' : 'forward');
          } else {
            el.setSelectionRange(target, target);
          }
          return true;
        } catch (err) { return false; }
      }

      function focusNext(doc, backwards) {
        const all = Array.prototype.filter.call(doc.querySelectorAll('a[href],button,input,select,textarea,[tabindex]:not([tabindex="-1"]),[contenteditable=true]'), function (n) {
          if (n.disabled || n.tabIndex < 0) { return false; }
          const r = n.getBoundingClientRect();
          return r.width > 0 && r.height > 0;
        });
        if (!all.length) { return; }
        let i = all.indexOf(doc.activeElement);
        i = backwards ? (i <= 0 ? all.length - 1 : i - 1) : (i + 1) % all.length;
        try { all[i].focus(); if (isEditable(all[i]) && all[i].select) { all[i].select(); } } catch (e) {}
      }

      // Returns: 'handled' | 'unhandled' | 'copy:<text>' | 'paste'
      dm.key = function (phase, key, code, text, mods, keyCode, repeat) {
        const doc = focusedDoc();
        const active = doc.activeElement || doc.body;
        const ctrl = !!(mods & 1), alt = !!(mods & 2), shift = !!(mods & 4), meta = !!(mods & 8);
        const init = { key: key, code: code, bubbles: true, cancelable: true, composed: true, repeat: !!repeat,
                       ctrlKey: ctrl, altKey: alt, shiftKey: shift, metaKey: meta, keyCode: keyCode, which: keyCode };
        if (phase === 'up') {
          active.dispatchEvent(new KeyboardEvent('keyup', init));
          return 'handled';
        }
        if (!active.dispatchEvent(new KeyboardEvent('keydown', init))) { return 'handled'; }
        if (key === 'Escape') { closeSelectPopup(); }
        if (selectPopup && (key === 'Enter' || key === 'Escape')) { closeSelectPopup(); return 'handled'; }

        const editable = isEditable(active);
        if (meta) {
          const k = (key || '').toLowerCase();
          if (k === 'a') {
            if (editable && !active.isContentEditable) { try { active.select(); } catch (e) {} }
            else { try { doc.execCommand('selectAll'); } catch (e) { doc.getSelection().selectAllChildren(doc.body); } }
            return 'handled';
          }
          if (k === 'c' || k === 'x') {
            let t = '';
            if (editable && !active.isContentEditable) { try { t = active.value.substring(active.selectionStart, active.selectionEnd); } catch (e) {} }
            else { t = doc.getSelection().toString(); }
            if (k === 'x' && editable) { deleteInField(active, false, false); }
            return 'copy:' + t;
          }
          if (k === 'v') { return editable ? 'paste' : 'handled'; }
          if (k === 'z' && editable) { try { doc.execCommand(shift ? 'redo' : 'undo'); } catch (e) {} return 'handled'; }
          if (editable && (key === 'ArrowLeft' || key === 'ArrowRight' || key === 'ArrowUp' || key === 'ArrowDown')) {
            if (!active.isContentEditable) { moveCaretInField(active, key, shift, true, false); }
            else { doc.getSelection().modify(shift ? 'extend' : 'move', key === 'ArrowLeft' || key === 'ArrowUp' ? 'backward' : 'forward', key === 'ArrowUp' || key === 'ArrowDown' ? 'documentboundary' : 'lineboundary'); }
            return 'handled';
          }
          return 'unhandled';
        }

        if (key === 'Tab') { focusNext(doc, shift); return 'handled'; }

        if (editable) {
          if (key === 'Enter') {
            if (active.tagName === 'TEXTAREA' || active.isContentEditable) {
              if (active.isContentEditable) { doc.execCommand('insertParagraph'); } else { insertText(active, '\n'); }
              return 'handled';
            }
            // Many sites listen for keypress/Enter on inputs (search boxes) instead of a form submit.
            const kp = active.dispatchEvent(new KeyboardEvent('keypress', Object.assign({}, init, { charCode: 13 })));
            if (!kp) { return 'handled'; }
            const form = active.form;
            if (form) {
              const btn = form.querySelector('button[type=submit],input[type=submit],button:not([type])');
              if (btn) { btn.click(); } else if (form.requestSubmit) { form.requestSubmit(); } else { form.submit(); }
            }
            return 'handled';
          }
          if (key === 'Backspace') { deleteInField(active, false, alt); return 'handled'; }
          if (key === 'Delete') { deleteInField(active, true, false); return 'handled'; }
          if (key === 'Escape') { try { active.blur(); } catch (e) {} return 'handled'; }
          if (/^Arrow|^Home$|^End$/.test(key)) {
            if (active.isContentEditable) {
              const sel = doc.getSelection();
              const dirBack = key === 'ArrowLeft' || key === 'ArrowUp' || key === 'Home';
              const gran = key === 'ArrowUp' || key === 'ArrowDown' ? 'line' : (alt ? 'word' : (key === 'Home' || key === 'End' ? 'lineboundary' : 'character'));
              sel.modify(shift ? 'extend' : 'move', dirBack ? 'backward' : 'forward', gran);
            } else { moveCaretInField(active, key, shift, false, alt); }
            return 'handled';
          }
          if (text && !ctrl && key !== 'Enter' && key !== 'Tab') {
            if (active.tagName === 'INPUT' && active.type === 'number' && !/^[0-9.,\-+e]$/i.test(text)) { return 'handled'; }
            insertText(active, text);
            active.dispatchEvent(new KeyboardEvent('keypress', Object.assign({}, init, { charCode: text.charCodeAt(0) })));
            return 'handled';
          }
          return 'handled';
        }

        // Not editing: a few mac-like page shortcuts; everything else is left to native scrolling.
        if (active && active.tagName === 'SELECT') {
          if (key === 'Enter' || key === ' ') { openSelectPopup(active); return 'handled'; }
        }
        if ((key === 'Enter' || key === ' ') && active && active !== doc.body && (active.tagName === 'BUTTON' || active.tagName === 'A' || active.getAttribute('role') === 'button')) {
          active.click();
          return 'handled';
        }
        return 'unhandled';
      };

      dm.paste = function (text) {
        const doc = focusedDoc();
        const active = doc.activeElement;
        if (isEditable(active)) { insertText(active, text); }
      };

      dm.pageInfo = function () {
        return JSON.stringify({ title: document.title, url: location.href });
      };

      document.addEventListener('click', function (ev) {
        if (selectPopup && !selectPopup.contains(ev.target)) { closeSelectPopup(); }
      }, true);

      window.__dm = dm;
    })();
    """#

    /// Hides native scrollbars-on-hover artefacts and gives pages a desktop-like base font.
    static let style = #"""
    (function () {
      const s = document.createElement('style');
      s.textContent = '[data-dm-popup] { user-select: none; } ::selection { background: rgba(63,132,250,0.45); }';
      (document.head || document.documentElement).appendChild(s);
    })();
    """#
}
