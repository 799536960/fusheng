import AppKit
import ApplicationServices
import Carbon
import Foundation
import OSLog

private let hotkeyLogger = Logger(subsystem: "com.fusheng.voiceinput", category: "Hotkey")

private func writeHotkeyDiagnostic(_ message: String) {
    DiagnosticLog.write(category: "Hotkey", message: message)
}

protocol HotkeyEventRegistering {
    func onKeyDown(_ action: @escaping () -> Void)
    func onKeyUp(_ action: @escaping () -> Void)
}

final class SingleKeyHotkeyRegisterer: HotkeyEventRegistering {
    typealias EventTapFactory = (
        CGEventTapLocation,
        CGEventTapPlacement,
        CGEventTapOptions,
        CGEventMask,
        CGEventTapCallBack,
        UnsafeMutableRawPointer?
    ) -> CFMachPort?
    typealias EventTapEnabler = (CFMachPort, Bool) -> Void

    private let settings: SettingsProviding
    private let accessibilityInspector: AccessibilityInspecting
    private let promptForAccessibility: Bool
    private let eventTapFactory: EventTapFactory
    private let eventTapEnabler: EventTapEnabler
    private let eventTapHealthInterval: TimeInterval?
    private let lock = NSLock()
    private var activeHotkey: SpeechHotkey
    private var keyDownAction: (() -> Void)?
    private var keyUpAction: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapHealthTimer: Timer?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var hotkeyChangeObserver: NSObjectProtocol?
    private var permissionRetryObserver: NSObjectProtocol?
    private var recorderCaptureObserver: NSObjectProtocol?
    private var isHotkeyRecorderCapturing = false
    private var lastCaptureHealthSummary: String?

    init(
        settings: SettingsProviding,
        accessibilityInspector: AccessibilityInspecting = SystemAccessibilityInspector(),
        promptForAccessibility: Bool = false,
        eventTapFactory: @escaping EventTapFactory = CGEvent.tapCreate,
        eventTapEnabler: @escaping EventTapEnabler = { eventTap, enabled in
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        },
        eventTapHealthInterval: TimeInterval? = 2
    ) {
        self.settings = settings
        self.accessibilityInspector = accessibilityInspector
        self.promptForAccessibility = promptForAccessibility
        self.eventTapFactory = eventTapFactory
        self.eventTapEnabler = eventTapEnabler
        self.eventTapHealthInterval = eventTapHealthInterval
        self.activeHotkey = settings.holdKey
    }

    deinit {
        eventTapHealthTimer?.invalidate()
        if let hotkeyChangeObserver {
            NotificationCenter.default.removeObserver(hotkeyChangeObserver)
        }
        if let permissionRetryObserver {
            NotificationCenter.default.removeObserver(permissionRetryObserver)
        }
        if let recorderCaptureObserver {
            NotificationCenter.default.removeObserver(recorderCaptureObserver)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
        }
        if let globalKeyUpMonitor {
            NSEvent.removeMonitor(globalKeyUpMonitor)
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
        }
        if let localKeyUpMonitor {
            NSEvent.removeMonitor(localKeyUpMonitor)
        }
    }

    func onKeyDown(_ action: @escaping () -> Void) {
        lock.lock()
        keyDownAction = action
        lock.unlock()
        hotkeyLogger.info("registered keyDown handler")
        installMonitorsIfNeeded()
    }

    func onKeyUp(_ action: @escaping () -> Void) {
        lock.lock()
        keyUpAction = action
        lock.unlock()
        hotkeyLogger.info("registered keyUp handler")
        installMonitorsIfNeeded()
    }

    func handleForTesting(keyCode: UInt16, isKeyDown: Bool, isRepeat: Bool = false) {
        guard !isRecorderCapturing else { return }
        guard matchesActiveHotkey(keyCode: keyCode) else { return }
        guard !(isKeyDown && isRepeat) else { return }
        invokeAction(isKeyDown: isKeyDown)
    }

    private func installMonitorsIfNeeded() {
        observeHotkeyChangesIfNeeded()
        observePermissionRetryIfNeeded()
        observeRecorderCaptureIfNeeded()
        installLocalEventMonitorsIfNeeded()
        installGlobalCaptureIfPossible()
        logCaptureHealth(reason: "installMonitorsIfNeeded", force: true)
    }

    private func installGlobalCaptureIfPossible() {
        guard accessibilityInspector.isProcessTrusted(prompt: promptForAccessibility) else {
            hotkeyLogger.info("global capture unavailable: accessibility is not trusted secureInput=\(IsSecureEventInputEnabled(), privacy: .public)")
            writeHotkeyDiagnostic("global capture unavailable: accessibility is not trusted secureInput=\(IsSecureEventInputEnabled())")
            logCaptureHealth(reason: "accessibility-not-trusted", force: true)
            return
        }

        if let eventTap {
            if CFMachPortIsValid(eventTap) {
                eventTapEnabler(eventTap, true)
                logCaptureHealth(reason: "reuse-valid-event-tap")
                return
            }

            hotkeyLogger.info("event tap is invalid before install; rebuilding")
            uninstallEventTap()
        }

        guard eventTap == nil else { return }

        if installEventTapIfPossible() {
            removeGlobalFallbackEventMonitors()
        } else {
            hotkeyLogger.error("event tap creation failed; falling back to global monitors secureInput=\(IsSecureEventInputEnabled(), privacy: .public)")
            writeHotkeyDiagnostic("event tap creation failed; falling back to global monitors secureInput=\(IsSecureEventInputEnabled())")
            installGlobalFallbackEventMonitors()
        }
    }

    private func installEventTapIfPossible() -> Bool {
        let eventsOfInterest = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let eventTap = eventTapFactory(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            CGEventMask(eventsOfInterest),
            Self.handleEventTap,
            Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTapEnabler(eventTap, true)
        startEventTapHealthCheckIfNeeded()
        hotkeyLogger.info("installed event tap for hotkey keyCode=\(self.activeHotkey.keyCode, privacy: .public) displayName=\(self.activeHotkey.displayName, privacy: .public) secureInput=\(IsSecureEventInputEnabled(), privacy: .public)")
        writeHotkeyDiagnostic("installed event tap keyCode=\(activeHotkey.keyCode) displayName=\(activeHotkey.displayName) secureInput=\(IsSecureEventInputEnabled())")
        return true
    }

    private func startEventTapHealthCheckIfNeeded() {
        guard eventTapHealthTimer == nil, let eventTapHealthInterval else { return }

        let timer = Timer(timeInterval: eventTapHealthInterval, repeats: true) { [weak self] _ in
            self?.reenableEventTapIfNeeded()
        }
        eventTapHealthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func reenableEventTapIfNeeded() {
        guard let eventTap else {
            logCaptureHealth(reason: "health-check-missing-event-tap")
            installGlobalCaptureIfPossible()
            return
        }

        guard CFMachPortIsValid(eventTap) else {
            rebuildEventTap(reason: "invalid health check")
            return
        }

        eventTapEnabler(eventTap, true)
        logCaptureHealth(reason: "health-check")
    }

    private func installGlobalFallbackEventMonitors() {
        guard globalKeyDownMonitor == nil, globalKeyUpMonitor == nil else { return }
        hotkeyLogger.info("event tap unavailable; installing global fallback monitors")
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleObservedEvent(event, isKeyDown: true)
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleObservedEvent(event, isKeyDown: false)
        }
        logCaptureHealth(reason: "installed-global-fallback", force: true)
    }

    private func removeGlobalFallbackEventMonitors() {
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }

        if let globalKeyUpMonitor {
            NSEvent.removeMonitor(globalKeyUpMonitor)
            self.globalKeyUpMonitor = nil
        }
    }

    private func installLocalEventMonitorsIfNeeded() {
        guard localKeyDownMonitor == nil, localKeyUpMonitor == nil else { return }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleObservedEvent(event, isKeyDown: true)
            return event
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleObservedEvent(event, isKeyDown: false)
            return event
        }
        hotkeyLogger.info("installed local event monitors for active app key events")
    }

    private func observePermissionRetryIfNeeded() {
        guard permissionRetryObserver == nil else { return }

        permissionRetryObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            hotkeyLogger.info("app became active; checking hotkey capture")
            self?.reenableEventTapIfNeeded()
            self?.installGlobalCaptureIfPossible()
        }
    }

    private func observeHotkeyChangesIfNeeded() {
        guard hotkeyChangeObserver == nil else { return }

        hotkeyChangeObserver = NotificationCenter.default.addObserver(
            forName: .speechHotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshActiveHotkey()
            self?.logCaptureHealth(reason: "hotkey-changed", force: true)
        }
    }

    private func observeRecorderCaptureIfNeeded() {
        guard recorderCaptureObserver == nil else { return }

        recorderCaptureObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecorderCaptureDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isCapturing = notification.userInfo?["isCapturing"] as? Bool ?? false
            self?.setRecorderCapturing(isCapturing)
        }
    }

    private func refreshActiveHotkey() {
        lock.lock()
        activeHotkey = settings.holdKey
        let activeHotkey = activeHotkey
        lock.unlock()
        hotkeyLogger.info("active hotkey refreshed keyCode=\(activeHotkey.keyCode, privacy: .public) displayName=\(activeHotkey.displayName, privacy: .public)")
    }

    private func handleObservedEvent(_ event: NSEvent, isKeyDown: Bool) {
        if isRecorderCapturing {
            hotkeyLogger.info("ignored \(isKeyDown ? "down" : "up", privacy: .public) from NSEvent because hotkey recorder is capturing")
            writeHotkeyDiagnostic("ignored \(isKeyDown ? "down" : "up") from NSEvent because hotkey recorder is capturing")
            return
        }
        let keyCode = UInt16(event.keyCode)
        guard matchesActiveHotkey(keyCode: keyCode) else { return }
        if isKeyDown, event.isARepeat {
            hotkeyLogger.info("ignored repeated keyDown from NSEvent keyCode=\(keyCode, privacy: .public)")
            writeHotkeyDiagnostic("ignored repeated keyDown from NSEvent keyCode=\(keyCode)")
            return
        }
        hotkeyLogger.info("matched \(isKeyDown ? "down" : "up", privacy: .public) from NSEvent keyCode=\(keyCode, privacy: .public) secureInput=\(IsSecureEventInputEnabled(), privacy: .public)")
        writeHotkeyDiagnostic("matched \(isKeyDown ? "down" : "up") from NSEvent keyCode=\(keyCode) secureInput=\(IsSecureEventInputEnabled())")
        invokeAction(isKeyDown: isKeyDown)
    }

    private func handleTappedEvent(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reason = type == .tapDisabledByTimeout ? "disabled by timeout" : "disabled by user input"
            hotkeyLogger.error("event tap \(reason, privacy: .public); scheduling rebuild secureInput=\(IsSecureEventInputEnabled(), privacy: .public)")
            writeHotkeyDiagnostic("event tap \(reason); scheduling rebuild secureInput=\(IsSecureEventInputEnabled())")
            Task { @MainActor in
                self.rebuildEventTap(reason: reason)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        if isRecorderCapturing {
            hotkeyLogger.info("passing through \(type == .keyDown ? "keyDown" : "keyUp", privacy: .public) from eventTap because hotkey recorder is capturing")
            writeHotkeyDiagnostic("passing through \(type == .keyDown ? "keyDown" : "keyUp") from eventTap because hotkey recorder is capturing")
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard matchesActiveHotkey(keyCode: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            hotkeyLogger.info("ignored repeated keyDown from eventTap keyCode=\(keyCode, privacy: .public)")
            writeHotkeyDiagnostic("ignored repeated keyDown from eventTap keyCode=\(keyCode)")
            return nil
        }

        hotkeyLogger.info("matched \(type == .keyDown ? "keyDown" : "keyUp", privacy: .public) from eventTap keyCode=\(keyCode, privacy: .public) secureInput=\(IsSecureEventInputEnabled(), privacy: .public)")
        writeHotkeyDiagnostic("matched \(type == .keyDown ? "keyDown" : "keyUp") from eventTap keyCode=\(keyCode) secureInput=\(IsSecureEventInputEnabled())")
        invokeAction(isKeyDown: type == .keyDown)
        return nil
    }

    private func rebuildEventTap(reason: String) {
        hotkeyLogger.info("rebuilding event tap: \(reason, privacy: .public)")
        uninstallEventTap()
        installGlobalCaptureIfPossible()
        logCaptureHealth(reason: "rebuild-\(reason)", force: true)
    }

    private func uninstallEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        logCaptureHealth(reason: "uninstall-event-tap", force: true)
    }

    private func matchesActiveHotkey(keyCode: UInt16) -> Bool {
        lock.lock()
        let matches = keyCode == activeHotkey.keyCode
        lock.unlock()
        return matches
    }

    private var isRecorderCapturing: Bool {
        lock.lock()
        let isCapturing = isHotkeyRecorderCapturing
        lock.unlock()
        return isCapturing
    }

    private func setRecorderCapturing(_ isCapturing: Bool) {
        lock.lock()
        isHotkeyRecorderCapturing = isCapturing
        lock.unlock()
        hotkeyLogger.info("hotkey recorder capturing=\(isCapturing, privacy: .public)")
        writeHotkeyDiagnostic("hotkey recorder capturing=\(isCapturing)")
        logCaptureHealth(reason: "recorder-capture-changed", force: true)
    }

    private func invokeAction(isKeyDown: Bool) {
        lock.lock()
        let action = isKeyDown ? keyDownAction : keyUpAction
        lock.unlock()

        guard let action else {
            hotkeyLogger.error("matched hotkey but \(isKeyDown ? "keyDown" : "keyUp", privacy: .public) handler is missing")
            writeHotkeyDiagnostic("matched hotkey but \(isKeyDown ? "keyDown" : "keyUp") handler is missing")
            return
        }
        hotkeyLogger.info("dispatching \(isKeyDown ? "keyDown" : "keyUp", privacy: .public) action")
        writeHotkeyDiagnostic("dispatching \(isKeyDown ? "keyDown" : "keyUp") action")
        invokeOnMain(action)
    }

    private func logCaptureHealth(reason: String, force: Bool = false) {
        let summary = captureHealthSummary()

        lock.lock()
        let shouldLog = force || summary != lastCaptureHealthSummary
        if shouldLog {
            lastCaptureHealthSummary = summary
        }
        lock.unlock()

        guard shouldLog else { return }
        hotkeyLogger.info("capture health reason=\(reason, privacy: .public) \(summary, privacy: .public)")
        writeHotkeyDiagnostic("capture health reason=\(reason) \(summary)")
    }

    private func captureHealthSummary() -> String {
        lock.lock()
        let activeHotkey = activeHotkey
        let isRecorderCapturing = isHotkeyRecorderCapturing
        let eventTapInstalled = eventTap != nil
        let eventTapValid = eventTap.map { CFMachPortIsValid($0) } ?? false
        let hasRunLoopSource = runLoopSource != nil
        let hasGlobalFallback = globalKeyDownMonitor != nil || globalKeyUpMonitor != nil
        let hasLocalMonitors = localKeyDownMonitor != nil || localKeyUpMonitor != nil
        lock.unlock()

        let accessibilityTrusted = accessibilityInspector.isProcessTrusted(prompt: false)
        let secureInput = IsSecureEventInputEnabled()
        return "activeKeyCode=\(activeHotkey.keyCode) activeDisplayName=\(activeHotkey.displayName) eventTapInstalled=\(eventTapInstalled) eventTapValid=\(eventTapValid) runLoopSource=\(hasRunLoopSource) globalFallback=\(hasGlobalFallback) localMonitors=\(hasLocalMonitors) recorderCapturing=\(isRecorderCapturing) accessibilityTrusted=\(accessibilityTrusted) secureInput=\(secureInput)"
    }

    private func invokeOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            Task { @MainActor in
                action()
            }
        }
    }

    private static let handleEventTap: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let registerer = Unmanaged<SingleKeyHotkeyRegisterer>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return registerer.handleTappedEvent(event, type: type)
    }
}

@MainActor
final class HotkeyService {
    private let registerer: HotkeyEventRegistering
    private let canStart: () -> Bool
    private let onStart: () -> Void
    private let onFinish: () -> Void
    private let stalePressedRecoveryInterval: TimeInterval
    private let dateProvider: () -> Date
    private var isPressed = false
    private var pressedAt: Date?

    init(
        settings _: SettingsProviding,
        registerer: HotkeyEventRegistering,
        canStart: @escaping () -> Bool = { true },
        onToggle _: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        stalePressedRecoveryInterval: TimeInterval = 1,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.registerer = registerer
        self.canStart = canStart
        self.onStart = onStart
        self.onFinish = onFinish
        self.stalePressedRecoveryInterval = stalePressedRecoveryInterval
        self.dateProvider = dateProvider
    }

    convenience init(
        settings: SettingsProviding,
        canStart: @escaping () -> Bool = { true },
        onToggle: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.init(
            settings: settings,
            registerer: SingleKeyHotkeyRegisterer(settings: settings),
            canStart: canStart,
            onToggle: onToggle,
            onStart: onStart,
            onFinish: onFinish
        )
    }

    func start() {
        hotkeyLogger.info("HotkeyService started")
        writeHotkeyDiagnostic("HotkeyService started")
        registerer.onKeyDown { [weak self] in
            guard let self else { return }
            if self.isPressed {
                guard self.canStart(), self.isPressedStale else {
                    hotkeyLogger.info("ignored keyDown because hotkey is already pressed stale=\(self.isPressedStale, privacy: .public) canStart=\(self.canStart(), privacy: .public)")
                    writeHotkeyDiagnostic("ignored keyDown because hotkey is already pressed stale=\(self.isPressedStale) canStart=\(self.canStart())")
                    return
                }

                hotkeyLogger.info("recovering stale pressed hotkey; accepting keyDown")
                writeHotkeyDiagnostic("recovering stale pressed hotkey; accepting keyDown")
                self.pressedAt = self.dateProvider()
                self.onStart()
                return
            }
            guard self.canStart() else {
                hotkeyLogger.info("ignored keyDown because workflow cannot start isPressed=\(self.isPressed, privacy: .public)")
                writeHotkeyDiagnostic("ignored keyDown because workflow cannot start isPressed=\(self.isPressed)")
                return
            }
            self.isPressed = true
            self.pressedAt = self.dateProvider()
            hotkeyLogger.info("accepted keyDown; isPressed=true")
            writeHotkeyDiagnostic("accepted keyDown; isPressed=true")
            hotkeyLogger.info("invoking onStart callback")
            writeHotkeyDiagnostic("invoking onStart callback")
            self.onStart()
            hotkeyLogger.info("returned from onStart callback")
            writeHotkeyDiagnostic("returned from onStart callback")
        }

        registerer.onKeyUp { [weak self] in
            guard let self else { return }
            guard self.isPressed else {
                hotkeyLogger.info("ignored keyUp because hotkey is not pressed")
                writeHotkeyDiagnostic("ignored keyUp because hotkey is not pressed")
                return
            }
            self.isPressed = false
            self.pressedAt = nil
            hotkeyLogger.info("accepted keyUp; isPressed=false")
            writeHotkeyDiagnostic("accepted keyUp; isPressed=false")
            hotkeyLogger.info("invoking onFinish callback")
            writeHotkeyDiagnostic("invoking onFinish callback")
            self.onFinish()
            hotkeyLogger.info("returned from onFinish callback")
            writeHotkeyDiagnostic("returned from onFinish callback")
        }
    }

    private var isPressedStale: Bool {
        guard let pressedAt else { return false }
        return dateProvider().timeIntervalSince(pressedAt) >= stalePressedRecoveryInterval
    }
}
