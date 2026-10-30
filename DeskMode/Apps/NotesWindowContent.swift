import UIKit

struct Note: Codable, Identifiable {
    var id: UUID
    var text: String
    var modifiedAt: Date

    init(id: UUID = UUID(), text: String, modifiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.modifiedAt = modifiedAt
    }

    // Earlier builds stored the date as `updatedAt`; both spellings decode.
    private enum CodingKeys: String, CodingKey { case id, text, modifiedAt, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
            ?? c.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }

    var title: String {
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? "New Note" : first
    }

    var preview: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return "No additional text" }
        return lines[1].trimmingCharacters(in: .whitespaces)
    }
}

/// Loading and saving for Notes, including migration from the single-note store of early builds.
enum NotesStore {
    static let file = "notes"

    static func load() -> [Note] {
        if let notes = Persistence.load([Note].self, from: file) { return notes }
        // The first version kept one plain-text note.
        let legacyText = Persistence.load(String.self, from: "note")
            ?? UserDefaults.standard.string(forKey: "noteText")
        if let legacyText, !legacyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let migrated = [Note(text: legacyText)]
            save(migrated)
            Persistence.remove("note")
            UserDefaults.standard.removeObject(forKey: "noteText")
            return migrated
        }
        return []
    }

    static func save(_ notes: [Note]) {
        Persistence.save(notes, to: file)
    }
}

/// Date strings used by the Notes list and editor header.
private enum NoteDates {
    static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    static let dayMonth: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()
    static let header: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .short; return f
    }()

    static func list(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) { return dayMonth.string(from: date) }
        return shortDate.string(from: date)
    }
}

// MARK: - Sidebar row

private final class NoteRow: HoverRow {
    static let height: CGFloat = 56

    let noteID: UUID
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let previewLabel = UILabel()
    /// Selection shows accent while the list has keyboard focus, grey otherwise (like macOS).
    var listFocused = true { didSet { if oldValue != listFocused { refreshState(animated: true) } } }

    init(note: Note) {
        noteID = note.id
        super.init(cornerRadius: AppsTheme.Radius.control)
        for l in [titleLabel, dateLabel, previewLabel] { addSubview(l); l.lineBreakMode = .byTruncatingTail }
        titleLabel.font = Theme.font(AppsTheme.TextSize.body, weight: .semibold)
        dateLabel.font = Theme.font(AppsTheme.TextSize.caption)
        previewLabel.font = Theme.font(AppsTheme.TextSize.caption)
        update(note)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ note: Note) {
        titleLabel.text = note.title
        dateLabel.text = NoteDates.list(note.modifiedAt)
        previewLabel.text = note.preview
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = AppsTheme.Space.m
        let w = bounds.width - x * 2
        titleLabel.frame = CGRect(x: x, y: 10, width: w, height: 17)
        let dateW = min(w * 0.45, dateLabel.intrinsicContentSize.width)
        dateLabel.frame = CGRect(x: x, y: 30, width: dateW, height: 14)
        previewLabel.frame = CGRect(x: x + dateW + AppsTheme.Space.s, y: 30, width: max(0, w - dateW - AppsTheme.Space.s), height: 14)
    }

    override func highlightColor() -> UIColor {
        if isSelected { return listFocused ? AppsTheme.selectedRow : Theme.controlBackgroundPressed }
        return super.highlightColor()
    }

    override func stateDidChange() {
        let accent = isSelected && listFocused
        titleLabel.textColor = accent ? AppsTheme.onAccent : Theme.text
        dateLabel.textColor = accent ? AppsTheme.onAccentSecondary : Theme.secondaryText
        previewLabel.textColor = accent ? AppsTheme.onAccentSecondary : Theme.tertiaryText
    }
}

// MARK: - Sidebar list

/// The scrolling note list. Focusable so arrow keys move the selection and ⌫ deletes.
private final class NotesListView: UIView, Focusable {

    var onSelect: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onContextMenu: ((UUID, PointerEvent) -> Void)?

    private let scroll = DeskScrollView()
    private var rows: [NoteRow] = []
    private var separators: [UIView] = []
    private var ids: [UUID] = []
    private var selectedID: UUID?
    private(set) var hasFocus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(notes: [Note], selected: UUID?) {
        selectedID = selected
        let newIDs = notes.map(\.id)
        if newIDs != ids {
            rows.forEach { $0.removeFromSuperview() }
            separators.forEach { $0.removeFromSuperview() }
            rows = notes.map { note in
                let row = NoteRow(note: note)
                row.onTap = { [weak self] in self?.onSelect?(note.id) }
                row.onRightClick = { [weak self] e in self?.onContextMenu?(note.id, e) }
                scroll.addSubview(row)
                return row
            }
            separators = notes.dropLast().map { _ in
                let s = UIView()
                s.backgroundColor = Theme.separator
                s.isUserInteractionEnabled = false
                scroll.addSubview(s)
                return s
            }
            ids = newIDs
        } else {
            for (row, note) in zip(rows, notes) { row.update(note) }
        }
        for row in rows {
            row.listFocused = hasFocus
            row.isSelected = row.noteID == selected
        }
        updateSeparators()
        setNeedsLayout()
    }

    private func updateSeparators() {
        // Hide the hairlines touching the selected row, as macOS does.
        guard let i = rows.firstIndex(where: { $0.isSelected }) else {
            separators.forEach { $0.alpha = 1 }
            return
        }
        for (j, s) in separators.enumerated() { s.alpha = (j == i || j == i - 1) ? 0 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let w = bounds.width
        var y: CGFloat = 0
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: y, width: w, height: NoteRow.height)
            y += NoteRow.height
            if i < separators.count {
                separators[i].frame = CGRect(x: AppsTheme.Space.m, y: y - pixelHairline, width: w - AppsTheme.Space.m * 2, height: pixelHairline)
            }
        }
        scroll.contentSize = CGSize(width: w, height: y + AppsTheme.Space.s)
    }

    func scrollToSelected() {
        guard let row = rows.first(where: { $0.isSelected }) else { return }
        scroll.scrollRectToVisible(row.frame.insetBy(dx: 0, dy: -AppsTheme.Space.s), animated: true)
    }

    // MARK: Focusable

    func setFocused(_ focused: Bool) {
        hasFocus = focused
        for row in rows { row.listFocused = focused }
    }

    func key(_ event: KeyEvent) -> Bool {
        guard event.isDown else { return true }
        switch event.keyCode {
        case .keyboardUpArrow: moveSelection(-1); return true
        case .keyboardDownArrow: moveSelection(1); return true
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward:
            if let selectedID { onDelete?(selectedID) }
            return true
        default: return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !ids.isEmpty else { return }
        let current = ids.firstIndex { $0 == selectedID } ?? (delta > 0 ? -1 : ids.count)
        let next = min(max(0, current + delta), ids.count - 1)
        onSelect?(ids[next])
        scrollToSelected()
    }
}

// MARK: - Window content

/// Notes: a macOS-style two-pane editor. Autosaves to Documents/notes.json.
final class NotesWindowContent: UIView, WindowContent {

    let app: DeskApp = .notes
    var windowTitle: String { "Notes" }
    var onTitleChange: ((String) -> Void)?

    private var notes: [Note] = []
    private var selectedID: UUID?
    private let focusGroup = FocusGroup()

    private static let sidebarWidth: CGFloat = 220
    private static let headerHeight: CGFloat = 36

    private let sidebar = UIView()
    private let newButton = DeskButton(title: "New Note", symbol: "plus", style: .plain)
    private let list = NotesListView()
    private let divider = UIView()
    private let dateLabel = UILabel()
    private let editor = DeskTextView()
    private let noNotes = EmptyStateView(symbol: "note.text", title: "No Notes", hint: "Click New Note or press ⌘N to start writing.")
    private let noSelection = EmptyStateView(symbol: "note.text", title: "No Note Selected", hint: "Choose a note from the list.")
    private var saveTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.windowBackground
        notes = NotesStore.load().sorted { $0.modifiedAt > $1.modifiedAt }

        addSubview(sidebar)
        sidebar.backgroundColor = AppsTheme.sidebarBackground
        sidebar.addSubview(newButton)
        sidebar.addSubview(list)
        newButton.font = Theme.font(AppsTheme.TextSize.body, weight: .medium)
        newButton.iconPointSize = 12
        newButton.tintOverride = Theme.accentText
        newButton.onTap = { [weak self] in self?.createNote() }

        list.onSelect = { [weak self] id in
            guard let self else { return }
            self.focusGroup.focus(self.list)
            self.select(id)
        }
        list.onDelete = { [weak self] id in self?.delete(id) }
        list.onContextMenu = { [weak self] id, event in self?.showRowMenu(id, event: event) }

        addSubview(divider)
        divider.backgroundColor = Theme.separator

        addSubview(dateLabel)
        dateLabel.font = Theme.font(AppsTheme.TextSize.caption)
        dateLabel.textColor = Theme.tertiaryText
        dateLabel.textAlignment = .center

        addSubview(editor)
        editor.focusGroup = focusGroup
        editor.placeholder = "Start writing…"
        editor.onChange = { [weak self] text in self?.editorChanged(text) }

        addSubview(noNotes)
        addSubview(noSelection)

        if let first = notes.first { select(first.id) } else { showEditor(nil) }
        refreshList()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sw = Self.sidebarWidth
        sidebar.frame = CGRect(x: 0, y: 0, width: sw, height: bounds.height)
        newButton.frame = CGRect(x: AppsTheme.Space.s, y: AppsTheme.Space.s, width: sw - AppsTheme.Space.s * 2, height: AppsTheme.Size.control)
        let listTop = AppsTheme.Space.s + AppsTheme.Size.control + AppsTheme.Space.s
        list.frame = CGRect(x: AppsTheme.Space.s, y: listTop, width: sw - AppsTheme.Space.s * 2, height: bounds.height - listTop)
        divider.frame = CGRect(x: sw - pixelHairline, y: 0, width: pixelHairline, height: bounds.height)
        let pane = CGRect(x: sw, y: 0, width: bounds.width - sw, height: bounds.height)
        dateLabel.frame = CGRect(x: pane.minX + AppsTheme.Space.l, y: 0, width: pane.width - AppsTheme.Space.xxl, height: Self.headerHeight)
        editor.frame = CGRect(x: pane.minX, y: Self.headerHeight, width: pane.width, height: pane.height - Self.headerHeight)
        noNotes.frame = pane
        noSelection.frame = pane
    }

    // MARK: - Data

    private var selectedIndex: Int? { notes.firstIndex { $0.id == selectedID } }

    private func createNote() {
        let note = Note(text: "")
        notes.insert(note, at: 0)
        select(note.id)
        refreshList()
        focusGroup.focus(editor)
        list.scrollToSelected()
        save()
    }

    private func delete(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: i)
        if selectedID == id {
            let nextIndex = min(i, notes.count - 1)
            if nextIndex >= 0 { select(notes[nextIndex].id) } else { selectedID = nil; showEditor(nil) }
        }
        refreshList()
        save()
    }

    private func select(_ id: UUID) {
        selectedID = id
        if let note = notes.first(where: { $0.id == id }) { showEditor(note) }
        refreshList()
    }

    private func showEditor(_ note: Note?) {
        let hasNotes = !notes.isEmpty
        editor.isHidden = note == nil
        dateLabel.isHidden = note == nil
        noNotes.isHidden = hasNotes
        noSelection.isHidden = !hasNotes || note != nil
        if let note {
            if editor.text != note.text { editor.text = note.text }
            dateLabel.text = NoteDates.header.string(from: note.modifiedAt)
        } else {
            dateLabel.text = ""
            if focusGroup.current === editor { focusGroup.blur() }
        }
    }

    private func editorChanged(_ text: String) {
        guard let i = selectedIndex, notes[i].text != text else { return }
        notes[i].text = text
        notes[i].modifiedAt = Date()
        dateLabel.text = NoteDates.header.string(from: notes[i].modifiedAt)
        // The edited note becomes the most recent one.
        if i != 0 { notes.insert(notes.remove(at: i), at: 0) }
        refreshList()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    private func save() {
        NotesStore.save(notes)
    }

    private func refreshList() {
        list.update(notes: notes, selected: selectedID)
        noNotes.isHidden = !notes.isEmpty
        noSelection.isHidden = notes.isEmpty || selectedID != nil
    }

    private func showRowMenu(_ id: UUID, event: PointerEvent) {
        guard let desktop = enclosingDesktopController else { return }
        focusGroup.focus(list)
        select(id)
        let items: [MenuItem] = [
            MenuItem(title: "New Note", symbol: "square.and.pencil", shortcut: "⌘N") { [weak self] in self?.createNote() },
            .separator,
            MenuItem(title: "Delete Note", symbol: "trash", shortcut: "⌘⌫") { [weak self] in self?.delete(id) }
        ]
        desktop.presentContextMenu(items: items, at: event.location)
    }

    // MARK: - WindowContent

    func contentDidFocus() {
        if focusGroup.current == nil {
            if selectedID != nil { focusGroup.focus(editor) } else { focusGroup.focus(list) }
        }
    }

    func contentDidBlur() { focusGroup.blur() }

    func windowWillClose() {
        saveTimer?.invalidate()
        save()
    }

    func handleMenuAction(_ action: MenuAction) -> Bool {
        switch action {
        case .newNote:
            createNote()
            return true
        case .selectAll, .copy, .cut, .paste:
            let letter: String = action == .selectAll ? "a" : action == .copy ? "c" : action == .cut ? "x" : "v"
            return focusGroup.key(KeyEvent(phase: .down, characters: letter, charactersIgnoringModifiers: letter,
                                           keyCode: .keyboardA, modifiers: .command, isRepeat: false))
        default:
            return false
        }
    }

    func handleKey(_ event: KeyEvent) -> Bool {
        if event.isDown, event.command {
            if event.letter == "n", !event.option { createNote(); return true }
            // ⌘⌫ deletes the note unless the editor has the caret (there it clears the line).
            if event.isBackspace, focusGroup.current !== editor, let selectedID {
                delete(selectedID)
                return true
            }
        }
        if event.isDown, event.isEscape, focusGroup.current === editor {
            focusGroup.focus(list)
            return true
        }
        return focusGroup.key(event)
    }
}
