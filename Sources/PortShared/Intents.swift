import AppIntents

/// Widget button: re-scan listening ports. `openAppWhenRun = true`
/// hands execution off to the host (the standalone Port shim or its
/// in-process equivalent inside the merged launcher), which has the
/// privileges to enumerate sockets via libproc. The widget itself
/// is sandboxed and never reads ports directly.
public struct RefreshPortIntent: AppIntent {
    public static var title: LocalizedStringResource =
        "Refresh open ports"
    public static var description = IntentDescription(
        "Re-enumerate listening sockets and refresh the widget.")
    public static var openAppWhenRun: Bool = true
    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentBus.shared.refresh()
        return .result()
    }
}
