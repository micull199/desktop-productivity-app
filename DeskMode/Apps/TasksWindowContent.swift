import UIKit

struct TaskItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var isDone: Bool
    var createdAt: Date
}

/// A single row in the task list: checkbox, title, delete-on-hover.
private final class TaskRow: UIView, PointerTarget {
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?

    private let checkbox = DeskButton(style: .plain)
    private let label = UILabel()
    private let deleteButton = DeskButton(symbol: "xmark", style: .toolbar)
    private let highlight = UIView()

    init(task: TaskItem) {
        super.init(frame: .zero)
        addSubview(highlight)
        addSubview(checkbox)
        addSubview(label)
        addSubview(deleteButton)
        highlight.layer.cornerRadius = 8
        checkbox.layer.cornerRadius = 10
        checkbox.layer.borderWidth = 1.5
        checkbox.layer.borderColor = task.isDone ? Theme.accent.cgColor : UIColor(white: 1, alpha: 0.35).cgColor
        checkbox.backgroundColor = task.isDone ? Theme.accent : .clear
        checkbox.symbolName = task.isDone ? "checkmark" : nil
        checkbox.iconPointSize = 10
        checkbox.tintOverride = .white
        checkbox.contentInsets = .zero
        checkbox.onTap = { [weak self] in self?.onToggle?() }
        label.font = Theme.font(14)
        label.textColor = task.isDone ? Theme.tertiaryText : Theme.text
        label.attributedText = NSAttributedString(string: task.title, attributes: task.isDone ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.tertiaryText, .font: Theme.font(14)] : [.foregroundColor: Theme.text, .font: Theme.font(14)])
        deleteButton.iconPointSize = 10
        deleteButton.alpha = 0
        deleteButton.onTap = { [weak self] in self?.onDelete?() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        highlight.frame = bounds
        checkbox.frame = CGRect(x: 12, y: (bounds.height - 20) / 2, width: 20, height: 20)
        deleteButton.frame = CGRect(x: bounds.width - 36, y: (bounds.height - 24) / 2, width: 26, height: 24)
        label.frame = CGRect(x: 44, y: 0, width: bounds.width - 90, height: bounds.height)
    }

    func pointer(_ event: PointerEvent, local: CGPoint) {
        if case .up(.left) = event.kind, event.clickCount == 2 { onToggle?() }
    }
    func pointerEntered() { highlight.backgroundColor = Theme.controlBackground; deleteButton.alpha = 1 }
    func pointerExited() { highlight.backgroundColor = .clear; deleteButton.alpha = 0 }
}

/// Tasks: quick capture with a text field, checkboxes, and a completed section.
final class TasksWindowContent: UIView, WindowContent {

    let app: DeskApp = .tasks
    var windowTitle: String { "Tasks" }
    var onTitleChange: ((String) -> Void)?

    private var tasks: [TaskItem] = []
    private let focusGroup = FocusGroup()
    private let field = DeskTextField()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let summaryLabel = UILabel()
    private let clearButton = DeskButton(title: "Clear Completed", style: .pill)
    private var showCompleted = true
    private let toggleCompleted = DeskButton(title: "Hide Completed", style: .pill)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.windowBackground
        tasks = Persistence.load([TaskItem].self, from: "tasks") ?? []

        addSubview(field)
        field.placeholder = "Add a task and press Return"
        field.leadingSymbol = "plus"
        field.font = Theme.font(14)
        field.focusGroup = focusGroup
        field.onSubmit = { [weak self] text in self?.add(text) }

        addSubview(summaryLabel)
        summaryLabel.font = Theme.font(12)
        summaryLabel.textColor = Theme.secondaryText

        addSubview(clearButton)
        clearButton.onTap = { [weak self] in
            self?.tasks.removeAll { $0.isDone }
            self?.rebuild()
            self?.save()
        }
        addSubview(toggleCompleted)
        toggleCompleted.onTap = { [weak self] in
            guard let self else { return }
            self.showCompleted.toggle()
            self.toggleCompleted.title = self.showCompleted ? "Hide Completed" : "Show Completed"
            self.rebuild()
        }

        addSubview(scroll)
        scroll.addSubview(stack)
        scroll.indicatorStyle = .white
        stack.axis = .vertical
        stack.spacing = 2
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        field.frame = CGRect(x: 16, y: 14, width: bounds.width - 32, height: 36)
        summaryLabel.frame = CGRect(x: 20, y: 60, width: bounds.width * 0.5, height: 24)
        let cw = clearButton.intrinsicContentSize.width
        let tw = toggleCompleted.intrinsicContentSize.width
        clearButton.frame = CGRect(x: bounds.width - 16 - cw, y: 60, width: cw, height: 24)
        toggleCompleted.frame = CGRect(x: bounds.width - 24 - cw - tw, y: 60, width: tw, height: 24)
        scroll.frame = CGRect(x: 10, y: 92, width: bounds.width - 20, height: bounds.height - 92)
        let h = CGFloat(stack.arrangedSubviews.count) * 40 + CGFloat(max(0, stack.arrangedSubviews.count - 1)) * 2
        stack.frame = CGRect(x: 0, y: 0, width: scroll.bounds.width, height: h)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: h + 12)
    }

    private func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tasks.insert(TaskItem(title: t, isDone: false, createdAt: Date()), at: 0)
        field.replaceAll(with: "")
        rebuild()
        save()
    }

    private func rebuild() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter { $0.isDone }
        for task in open + (showCompleted ? done : []) {
            let row = TaskRow(task: task)
            row.heightAnchor.constraint(equalToConstant: 40).isActive = true
            row.onToggle = { [weak self] in self?.toggle(task.id) }
            row.onDelete = { [weak self] in self?.remove(task.id) }
            stack.addArrangedSubview(row)
        }
        if tasks.isEmpty {
            let l = UILabel()
            l.text = "Nothing to do. Add a task above."
            l.textColor = Theme.tertiaryText
            l.font = Theme.font(14)
            l.textAlignment = .center
            l.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stack.addArrangedSubview(l)
        }
        summaryLabel.text = open.isEmpty ? (tasks.isEmpty ? "" : "All done 🎉") : "\(open.count) remaining"
        clearButton.isHidden = done.isEmpty
        toggleCompleted.isHidden = done.isEmpty
        setNeedsLayout()
    }

    private func toggle(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone.toggle()
        rebuild()
        save()
    }

    private func remove(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        rebuild()
        save()
    }

    private func save() { Persistence.save(tasks, to: "tasks") }

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
