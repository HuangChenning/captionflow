import Foundation

struct FallbackTranslator: Translator {
    let primary: Translator
    let fallback: Translator
    let timeout: Duration
    let onProvisional: (@Sendable (String) -> Void)?

    init(
        primary: Translator,
        fallback: Translator,
        timeout: Duration = .seconds(1.5),
        onProvisional: (@Sendable (String) -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
        self.onProvisional = onProvisional
    }

    func translate(_ text: String) async throws -> String {
        let primaryTask = Task { try await primary.translate(text) }

        let primaryFinishedFirst = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = try? await primaryTask.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        guard !primaryFinishedFirst else {
            return try await primaryTask.value
        }

        if let provisional = try? await fallback.translate(text) {
            onProvisional?(provisional)
        }

        return try await primaryTask.value
    }
}
