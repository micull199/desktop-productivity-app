import UIKit

struct TaskItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var isDone: Bool
    var createdAt: Date
    /// Added after 1.0; older files decode with `nil`.
    var completedAt: Date? = nil
}

// MARK: - Rows

/// One task: circular checkbox, title, delete-on-hover, right-click menu.
private final class TaskRow: HoverRow {
    static let height: CGFloat = 36

    let taskID: UUID
    var onToggle: ((Bool) -> Void)?
    var onDelete: (() -> Void)?

    let checkbox: DeskCheckbox
    private let label = UILabel()
    private let deleteButton = DeskButton(symbol: "xmark", style: .toolbar)

    init(task: TaskItem) {
        taskID = task.id
        checkbox = DeskCheckbox(isOn: task.isDone)
        super.init(cornerRadius: AppsTheme.Radius.control)
        addSubview(checkbox)
        addSubview(label)
        addSubview(deleteButton)
        checkbox.onToggle = { [weak self] on in self?.onToggle?(on) }
        label.lineBreakMode = .byTruncatingTail
        let font = Theme.font(AppsTheme.TextSize.callout)
        if task.isDone {
            label.attributedText = NSAttributedString(string: task.title, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: Theme.tertiaryText,
                .foregroundColor: Theme.tertiaryText,
                .font: font
            ])
        } else {
            label.attributedText = NSAttributedString(string: task.title, attributes: [.foregroundColor: Theme.text, .font: font])
        }
        deleteButton.iconPointSize = 10
        deleteButton.tintOverride = Theme.secondaryText
        deleteButton.alpha = 0
        deleteButton.onTap = { [weak self] in self?.onDelete?() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cbSize = DeskCheckbox.size
        checkbox.frame = CGRect(x: AppsTheme.Space.m, y: (bounds.height - cbSize) / 2, width: cbSize, height: cbSize)
        deleteButton.frame = CGRect(x: bounds.width - AppsTheme.Space.s - AppsTheme.Size.controlSmall,
                                    y: (bounds.height - AppsTheme.Size.controlSmall) / 2,
                                    width: AppsTheme.Size.controlSmall, height: AppsTheme.Size.controlSmall)
        let labelX = checkbox.frame.maxX + AppsTheme.Space.m
        label.frame = CGRect(x: labelX, y: 0, width: deleteButton.frame.minX - AppsTheme.Space.s - labelX, height: bounds.height)
    }

    override func stateDidChange() {
        deleteButton.alpha = isHovered ? 1 : 0
    }
}

/// "Completed (n)" disclosure row.
private final class SectionRow: HoverRow {
    static let height: CGFloat = 28

    private let chevron = UIImageView()
    private let label = UILabel()

    init(title: String, expanded: Bool) {
        super.init(cornerRadius: AppsTheme.Radius.control)
        addSubview(chevron)
        addSubview(label)
        chevron.image = UIImage.symbol("chevron.right", size: 10, weight: .semibold)
        chevron.tintColor = Theme.tertiaryText
        chevron.contentMode = .center
        chevron.transform = expanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        label.text = title
        label.font = Theme.font(AppsTheme.TextSize.footnote, weight: .semibold)
        label.textColor = Theme.secondaryText
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        chevron.frame = CGRect(x: AppsTheme.Space.m, y: 0, width: 18, height: bounds.height)
        label.frame = CGRect(x: chevron.frame.maxX + AppsTheme.Space.s, y: 0, width: bounds.width - 60, height: bounds.height)
    }
}

// MARK: - Window content

/// Tasks: Reminders-style list with an add field, animated checkboxes and a collapsible
/// completed section. Autosaves to Documents/tasks.json.
final class TasksWindowContent: UIView, WindowContent {

    let app: DeskApp = .tasks
    var windowTitle: String { "Tasks" }
    var onTitleChange: ((String) -> Void)?

    private var tasks: [TaskItem] = []
    private var showCompleted = true
    private let focusGroup = FocusGroup()

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let field = DeskTextField()
    private let scroll = DeskScrollView()
    private var rows: [UIView] = []
    private let empty = EmptyStateView(symbol: "checkmark.circle", title: "No Tasks", hint: "Add a task above and press Return.")
    private var appearingID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.windowBackground
        tasks = Persistence.load([TaskItem].self, from: "tasks") ?? []

        addSubview(titleLabel)
        titleLabel.text = "Tasks"
        titleLabel.font = Theme.font(AppsTheme.TextSize.title2, weight: .semibold)
        titleLabel.textColor = Theme.text

        addSubview(countLabel)
        countLabel.font = Theme.font(AppsTheme.TextSize.body)
        countLabel.textColor = Theme.secondaryText
        countLabel.textAlignment = .right

        addSubview(field)
        field.placeholder = "Add a task"
        field.leadingSymbol = "plus"
        field.font = Theme.font(AppsTheme.TextSize.callout)
        field.focusGroup = focusGroup
        field.onSubmit = { [weak self] text in self?.add(text) }
        field.onEscape = { [weak self] in self?.field.replaceAll(with: "") }

        addSubview(scroll)
        addSubview(empty)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = AppsTheme.Space.l
        titleLabel.frame = CGRect(x: inset + AppsTheme.Space.xs, y: AppsTheme.Space.l, width: bounds.width * 0.5, height: 26)
        countLabel.frame = CGRect(x: bounds.width * 0.5, y: AppsTheme.Space.l + 5, width: bounds.width * 0.5 - inset - AppsTheme.Space.xs, height: 18)
        field.frame = CGRect(x: inset, y: titleLabel.frame.maxY + AppsTheme.Space.m, width: bounds.width - inset * 2, height: AppsTheme.Size.controlLarge)
        let listTop = field.frame.maxY + AppsTheme.Space.m
        scroll.frame = CGRect(x: AppsTheme.Space.s, y: listTop, width: bounds.width - AppsTheme.Space.l, height: bounds.height - listTop)
        empty.frame = scroll.frame
        var y: CGFloat = 0
        for row in rows {
            let h: CGFloat
            if row is SectionRow { y += AppsTheme.Space.s; h = SectionRow.height } else { h = TaskRow.height }
            row.frame = CGRect(x: 0, y: y, width: scroll.bounds.width, height: h)
            y += h
        }
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: y + AppsTheme.Space.m)
    }

    // MARK: - Data

    private func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let task = TaskItem(title: t, isDone: false, createdAt: Date())
        tasks.insert(task, at: 0)
        appearingID = task.id
        field.replaceAll(with: "")
        rebuild()
        save()
    }

    private func setDone(_ id: UUID, _ done: Bool, from row: TaskRow) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone = done
        tasks[i].completedAt = done ? Date() : nil
        save()
        // Let the checkbox finish its fill before the row moves to the other section.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak row] in
            guard let self else { return }
            AppsTheme.Motion.animate(AppsTheme.Motion.fast, { row?.alpha = 0 }) { _ in
                self.appearingID = id
                self.rebuild()
            }
        }
    }

    private func remove(_ id: UUID) {
        guard let row = rows.compactMap({ $0 as? TaskRow }).first(where: { $0.taskID == id }) else {
            tasks.removeAll { $0.id == id }; rebuild(); save(); return
        }
        AppsTheme.Motion.animate(AppsTheme.Motion.fast, {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: -12, y: 0)
        }) { [weak self] _ in
            guard let self else { return }
            self.tasks.removeAll { $0.id == id }
            self.rebuild()
            self.save()
        }
    }

    private func save() { Persistence.save(tasks, to: "tasks") }

    private func rebuild() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter { $0.isDone }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        for task in open { rows.append(makeRow(task)) }
        if !done.isEmpty {
            let header = SectionRow(title: "Completed (\(done.count))", expanded: showCompleted)
            header.onTap = { [weak self] in
                guard let self else { return }
                self.showCompleted.toggle()
                self.rebuild()
            }
            rows.append(header)
            if showCompleted { for task in done { rows.append(makeRow(task)) } }
        }
        rows.forEach { scroll.addSubview($0) }

        empty.isHidden = !tasks.isEmpty
        scroll.isHidden = tasks.isEmpty
        countLabel.text = open.isEmpty ? (tasks.isEmpty ? "" : "All done") : (open.count == 1 ? "1 open" : "\(open.count) open")
        setNeedsLayout()

        if let id = appearingID, let row = rows.compactMap({ $0 as? TaskRow }).first(where: { $0.taskID == id }) {
            appearingID = nil
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: -6)
            AppsTheme.Motion.animate(AppsTheme.Motion.normal) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    private func makeRow(_ task: TaskItem) -> TaskRow {
        let row = TaskRow(task: task)
        row.onToggle = { [weak self, weak row] done in
            guard let self, let row else { return }
            self.setDone(task.id, done, from: row)
        }
        row.onDelete = { [weak self] in self?.remove(task.id) }
        row.onRightClick = { [weak self] event in self?.showRowMenu(task, event: event) }
        return row
    }

    private func showRowMenu(_ task: TaskItem, event: PointerEvent) {
        guard let desktop = enclosingDesktopController else { return }
        let items: [MenuItem] = [
            MenuItem(title: task.isDone ? "Mark as Open" : "Mark as Completed", symbol: task.isDone ? "circle" : "checkmark.circle") { [weak self] in
                guard let self, let row = self.rows.compactMap({ $0 as? TaskRow }).first(where: { $0.taskID == task.id }) else { return }
                row.checkbox.setOn(!task.isDone, animated: true)
                self.setDone(task.id, !task.isDone, from: row)
            },
            .separator,
            MenuItem(title: "Delete", symbol: "trash") { [weak self] in self?.remove(task.id) }
        ]
        desktop.presentContextMenu(items: items, at: event.location)
    }

    // MARK: - WindowContent

    func contentDidFocus() { if focusGroup.current == nil { focusGroup.focus(field) } }
    func contentDidBlur() { focusGroup.blur() }
    func windowWillClose() { save() }

    func handleMenuAction(_ action: MenuAction) -> Bool {
        switch action {
        case .newTask: focusGroup.focus(field); return true
        default: return false
        }
    }

    func handleKey(_ event: KeyEvent) -> Bool {
        if event.isDown, event.command, event.letter == "n" { focusGroup.focus(field); return true }
        return focusGroup.key(event)
    }
}
