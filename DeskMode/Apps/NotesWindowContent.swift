import UIKit

struct Note: Codable, Identifiable {
    var id = UUID()
    var text: String
    var updatedAt: Date

    var title: String {
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return first.isEmpty ? "New Note" : first
    }

    var preview: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespaces) : "No additional text"
    }
}

/// Notes: a sidebar list plus a plain-text editor. Autosaves to Documents/notes.json.
final class NotesWindowContent: UIView, WindowContent {

    let app: DeskApp = .notes
    var windowTitle: String { "Notes" }
    var onTitleChange: ((String) -> Void)?

    private var notes: [Note] = []
    private var selectedID: UUID?
    private let focusGroup = FocusGroup()

    private let sidebar = UIView()
    private let listStack = UIStackView()
    private let listScroll = UIScrollView()
    private let newButton = DeskButton(symbol: "square.and.pencil", style: .toolbar)
    private let deleteButton = DeskButton(symbol: "trash", style: .toolbar)
    private let searchField = DeskTextField()
    private let editor = DeskTextView()
    private let emptyLabel = UILabel()
    private let dateLabel = UILabel()
    private var saveTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.windowBackground
        notes = Persistence.load([Note].self, from: "notes") ?? []

        addSubview(sidebar)
        sidebar.backgroundColor = UIColor(white: 0.09, alpha: 1)
        sidebar.addSubview(newButton)
        sidebar.addSubview(deleteButton)
        sidebar.addSubview(searchField)
        sidebar.addSubview(listScroll)
        listScroll.addSubview(listStack)
        listScroll.showsVerticalScrollIndicator = false
        listStack.axis = .vertical
        listStack.spacing = 2

        newButton.onTap = { [weak self] in self?.createNote() }
        deleteButton.onTap = { [weak self] in self?.deleteSelected() }
        searchField.placeholder = "Search"
        searchField.leadingSymbol = "magnifyingglass"
        searchField.focusGroup = focusGroup
        searchField.onChange = { [weak self] _ in self?.rebuildList() }

        addSubview(dateLabel)
        dateLabel.font = Theme.font(11)
        dateLabel.textColor = Theme.tertiaryText
        dateLabel.textAlignment = .center

        addSubview(editor)
        editor.focusGroup = focusGroup
        editor.placeholder = "Start writing…"
        editor.onChange = { [weak self] text in self?.editorChanged(text) }

        addSubview(emptyLabel)
        emptyLabel.text = "No note selected"
        emptyLabel.textColor = Theme.tertiaryText
        emptyLabel.font = Theme.font(15)
        emptyLabel.textAlignment = .center

        if let first = notes.sorted(by: { $0.updatedAt > $1.updatedAt }).first { select(first.id) }
        rebuildList()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sidebarWidth: CGFloat = min(280, bounds.width * 0.36)
        sidebar.frame = CGRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        newButton.frame = CGRect(x: sidebarWidth - 70, y: 8, width: 30, height: 28)
        deleteButton.frame = CGRect(x: sidebarWidth - 38, y: 8, width: 30, height: 28)
        searchField.frame = CGRect(x: 10, y: 8, width: sidebarWidth - 88, height: 28)
        listScroll.frame = CGRect(x: 6, y: 44, width: sidebarWidth - 12, height: bounds.height - 44)
        let h = listStack.systemLayoutSizeFitting(CGSize(width: listScroll.bounds.width, height: 0),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        listStack.frame = CGRect(x: 0, y: 0, width: listScroll.bounds.width, height: h)
        listScroll.contentSize = CGSize(width: listScroll.bounds.width, height: h + 8)
        dateLabel.frame = CGRect(x: sidebarWidth, y: 8, width: bounds.width - sidebarWidth, height: 16)
        editor.frame = CGRect(x: sidebarWidth, y: 26, width: bounds.width - sidebarWidth, height: bounds.height - 26)
        emptyLabel.frame = editor.frame
    }

    // MARK: - Data

    private var selectedIndex: Int? { notes.firstIndex { $0.id == selectedID } }

    private func createNote() {
        let note = Note(text: "", updatedAt: Date())
        notes.insert(note, at: 0)
        select(note.id)
        rebuildList()
        focusGroup.focus(editor)
        save()
    }

    private func deleteSelected() {
        guard let i = selectedIndex else { return }
        notes.remove(at: i)
        selectedID = notes.first?.id
        if let id = selectedID { select(id) } else { showEditor(nil) }
        rebuildList()
        save()
    }

    private func select(_ id: UUID) {
        selectedID = id
        if let note = notes.first(where: { $0.id == id }) { showEditor(note) }
        rebuildList()
    }

    private func showEditor(_ note: Note?) {
        editor.isHidden = note == nil
        emptyLabel.isHidden = note != nil
        if let note {
            editor.text = note.text
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            dateLabel.text = f.string(from: note.updatedAt)
        } else {
            dateLabel.text = ""
        }
    }

    private func editorChanged(_ text: String) {
        guard let i = selectedIndex else { return }
        guard notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updatedAt = Date()
        rebuildList(updateOnly: true)
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    private func save() {
        Persistence.save(notes, to: "notes")
    }

    private func rebuildList(updateOnly: Bool = false) {
        let query = searchField.text.lowercased()
        let visible = notes.filter { query.isEmpty || $0.text.lowercased().contains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
        if updateOnly, listStack.arrangedSubviews.count == visible.count {
            for (i, note) in visible.enumerated() {
                if let b = listStack.arrangedSubviews[i] as? DeskButton {
                    b.title = note.title
                    b.subtitle = note.preview
                    b.isSelected = note.id == selectedID
                }
            }
            return
        }
        for v in listStack.arrangedSubviews { listStack.removeArrangedSubview(v); v.removeFromSuperview() }
        for note in visible {
            let b = DeskButton(title: note.title, style: .list)
            b.subtitle = note.preview
            b.isSelected = note.id == selectedID
            b.font = Theme.font(13, weight: .semibold)
            b.heightAnchor.constraint(equalToConstant: 50).isActive = true
            b.onTap = { [weak self] in self?.select(note.id) }
            listStack.addArrangedSubview(b)
        }
        setNeedsLayout()
    }

    // MARK: - WindowContent

    func contentDidFocus() {
        if selectedID != nil, focusGroup.current == nil { focusGroup.focus(editor) }
    }
    func contentDidBlur() { focusGroup.blur() }
    func windowWillClose() { saveTimer?.invalidate(); save() }

    func handleMenuAction(_ action: MenuAction) -> Bool {
        switch action {
        case .newNote: createNote(); return true
        case .selectAll, .copy, .cut, .paste:
            let letter: String = action == .selectAll ? "a" : action == .copy ? "c" : action == .cut ? "x" : "v"
            return focusGroup.key(KeyEvent(phase: .down, characters: letter, charactersIgnoringModifiers: letter, keyCode: .keyboardA, modifiers: .command, isRepeat: false))
        default: return false
        }
    }

    func handleKey(_ event: KeyEvent) -> Bool {
        if event.isDown, event.command {
            switch event.letter {
            case "n" where !event.option: createNote(); return true
            case "f": focusGroup.focus(searchField); return true
            default: break
            }
            if event.isBackspace, focusGroup.current !== editor { deleteSelected(); return true }
        }
        return focusGroup.key(event)
    }
}
