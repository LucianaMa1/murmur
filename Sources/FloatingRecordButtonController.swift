//
//  FloatingRecordButtonController.swift
//  Always-on-top mouse hold-to-record controls.
//

import AppKit

@MainActor
final class FloatingRecordButtonController {
    private weak var coordinator: DictationCoordinator?
    private var panel: NSPanel?
    private weak var contentView: FloatingRecordControlsView?

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let panel {
            DebugLog.shared.add("Floating controls already exist; bringing them forward")
            panel.orderFrontRegardless()
            return
        }

        let controls = FloatingRecordControlsView(frame: NSRect(x: 0, y: 0, width: 300, height: 118))
        controls.onPress = { [weak self] mode in
            self?.coordinator?.beginMouseDictation(mode: mode)
        }
        controls.onRelease = { [weak self] mode in
            self?.coordinator?.endMouseDictation(mode: mode)
        }

        coordinator?.onStateChange = { [weak controls] state in
            controls?.setState(state)
        }

        let panel = NSPanel(
            contentRect: defaultFrame(size: controls.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = controls
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.orderFrontRegardless()
        self.panel = panel
        self.contentView = controls
        DebugLog.shared.add("Floating controls panel created at x=\(Int(panel.frame.origin.x)), y=\(Int(panel.frame.origin.y))")
    }

    private func defaultFrame(size: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSRect(
            x: visibleFrame.maxX - size.width - 28,
            y: visibleFrame.minY + 36,
            width: size.width,
            height: size.height
        )
    }
}

private final class FloatingRecordControlsView: NSView {
    var onPress: ((DictationMode) -> Void)?
    var onRelease: ((DictationMode) -> Void)?

    private let statusPill = StatusPill()
    private let rawButton = HoldToRecordButton(
        mode: .raw,
        idleTitle: "Transcribe",
        activeTitle: "Listening",
        symbolName: "mic.fill",
        idleFill: NSColor.white.withAlphaComponent(0.16)
    )
    private let rewriteButton = HoldToRecordButton(
        mode: .llm,
        idleTitle: "Rewrite",
        activeTitle: "Listening",
        symbolName: "sparkles",
        idleFill: NSColor.white.withAlphaComponent(0.10)
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    func setState(_ state: DictationCoordinatorState) {
        switch state {
        case .idle:
            statusPill.set(text: "Murmur ready", color: .systemGreen)
            rawButton.setInteractionEnabled(true)
            rewriteButton.setInteractionEnabled(true)
        case .recording(let mode):
            statusPill.set(
                text: mode == .raw ? "Transcribing" : "Rewriting",
                color: .systemRed
            )
            rawButton.setInteractionEnabled(mode == .raw)
            rewriteButton.setInteractionEnabled(mode == .llm)
        case .processing:
            statusPill.set(text: "Processing", color: .systemGreen)
            rawButton.setInteractionEnabled(false)
            rewriteButton.setInteractionEnabled(false)
        case .error(let message):
            statusPill.set(text: "Needs attention", color: .systemOrange)
            rawButton.setInteractionEnabled(true)
            rewriteButton.setInteractionEnabled(true)
            toolTip = message
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.11).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 20
        layer?.shadowOffset = NSSize(width: 0, height: -8)

        rawButton.onPress = { [weak self] mode in self?.onPress?(mode) }
        rawButton.onRelease = { [weak self] mode in self?.onRelease?(mode) }
        rewriteButton.onPress = { [weak self] mode in self?.onPress?(mode) }
        rewriteButton.onRelease = { [weak self] mode in self?.onRelease?(mode) }

        for view in [statusPill, rawButton, rewriteButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            statusPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusPill.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            statusPill.heightAnchor.constraint(equalToConstant: 26),

            rawButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            rawButton.topAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: 14),
            rawButton.widthAnchor.constraint(equalToConstant: 125),
            rawButton.heightAnchor.constraint(equalToConstant: 44),

            rewriteButton.leadingAnchor.constraint(equalTo: rawButton.trailingAnchor, constant: 10),
            rewriteButton.topAnchor.constraint(equalTo: rawButton.topAnchor),
            rewriteButton.widthAnchor.constraint(equalToConstant: 125),
            rewriteButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}

private final class StatusPill: NSView {
    private let glowView = NSView()
    private let dotView = NSView()
    private let label = NSTextField(labelWithString: "Murmur ready")
    private var color = NSColor.systemGreen

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func set(text: String, color: NSColor) {
        self.color = color
        label.stringValue = text
        label.textColor = color.withAlphaComponent(0.92)
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        layer?.borderColor = color.withAlphaComponent(0.30).cgColor
        glowView.layer?.backgroundColor = color.withAlphaComponent(0.25).cgColor
        dotView.layer?.backgroundColor = color.cgColor
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = 6.5
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5
        label.font = .systemFont(ofSize: 12.5, weight: .medium)

        for view in [glowView, dotView, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            glowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            glowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glowView.widthAnchor.constraint(equalToConstant: 13),
            glowView.heightAnchor.constraint(equalToConstant: 13),

            dotView.centerXAnchor.constraint(equalTo: glowView.centerXAnchor),
            dotView.centerYAnchor.constraint(equalTo: glowView.centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),

            label.leadingAnchor.constraint(equalTo: glowView.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        set(text: "Murmur ready", color: color)
    }
}

private final class HoldToRecordButton: NSButton {
    var onPress: ((DictationMode) -> Void)?
    var onRelease: ((DictationMode) -> Void)?

    private let mode: DictationMode
    private let idleTitle: String
    private let activeTitle: String
    private let symbolName: String
    private let idleFill: NSColor
    private let topHighlightLayer = CALayer()
    private var recording = false
    private var interactionEnabled = true

    init(mode: DictationMode, idleTitle: String, activeTitle: String, symbolName: String, idleFill: NSColor) {
        self.mode = mode
        self.idleTitle = idleTitle
        self.activeTitle = activeTitle
        self.symbolName = symbolName
        self.idleFill = idleFill
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageLeading
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        font = .systemFont(ofSize: 14, weight: .semibold)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.masksToBounds = true
        topHighlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.addSublayer(topHighlightLayer)
        configure(title: idleTitle, symbolName: symbolName, fill: idleFill)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard interactionEnabled else { return }
        DebugLog.shared.add("Mouse down on \(idleTitle) button")
        startRecording()

        while let nextEvent = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if nextEvent.type == .leftMouseUp {
                DebugLog.shared.add("Mouse up on \(idleTitle) button")
                stopRecording()
                return
            }
        }

        DebugLog.shared.add("\(idleTitle) mouse loop ended without leftMouseUp")
        stopRecording()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHighlightFrame()
    }

    override func layout() {
        super.layout()
        updateHighlightFrame()
    }

    func setInteractionEnabled(_ enabled: Bool) {
        interactionEnabled = enabled
        isEnabled = enabled
        alphaValue = enabled ? 1.0 : 0.46
    }

    private func startRecording() {
        guard !recording else { return }
        recording = true
        animateScale(0.96)
        configure(title: activeTitle, symbolName: "waveform", fill: NSColor.systemRed.withAlphaComponent(0.62))
        DebugLog.shared.add("\(idleTitle) button entered recording state")
        onPress?(mode)
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        animateScale(1.0)
        configure(title: idleTitle, symbolName: symbolName, fill: idleFill)
        DebugLog.shared.add("\(idleTitle) button exited recording state")
        onRelease?(mode)
    }

    private func configure(title: String, symbolName: String, fill: NSColor) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        self.image = image
        contentTintColor = .white
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        layer?.backgroundColor = fill.cgColor
    }

    private func animateScale(_ scale: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    private func updateHighlightFrame() {
        topHighlightLayer.frame = NSRect(x: 0, y: bounds.height / 2, width: bounds.width, height: bounds.height / 2)
    }
}
