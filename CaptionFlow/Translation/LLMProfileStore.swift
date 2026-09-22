import Foundation

enum LLMProfileStore {
    private static let profilesKey = "llm.profiles"
    private static let selectedIDKey = "llm.selectedProfileID"
    private static let keychain = KeychainStore(service: "com.taihongteng.CaptionFlow")

    static func load() -> [LLMProfile] {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let profiles = try? JSONDecoder().decode([LLMProfile].self, from: data) {
            return profiles
        }
        guard let migrated = migrateLegacyProfile() else { return [] }
        return [migrated]
    }

    static func save(_ profiles: [LLMProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: profilesKey)
    }

    static var selectedID: UUID? {
        get { UserDefaults.standard.string(forKey: selectedIDKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: selectedIDKey) }
    }

    /// One-time migration from the single flat llm.* settings used before multi-model support.
    private static func migrateLegacyProfile() -> LLMProfile? {
        let defaults = UserDefaults.standard
        guard let baseURLString = defaults.string(forKey: "llm.baseURL"),
              let baseURL = URL(string: baseURLString),
              let model = defaults.string(forKey: "llm.model") else {
            return nil
        }
        let apiStyle = defaults.string(forKey: "llm.apiStyle").flatMap(LLMAPIStyle.init(rawValue:)) ?? .anthropic
        let profile = LLMProfile(name: model, apiStyle: apiStyle, baseURL: baseURL, model: model)
        save([profile])
        selectedID = profile.id
        if let secret = try? keychain.secret(for: "default"), !secret.isEmpty {
            try? keychain.save(secret: secret, for: profile.id.uuidString)
        }
        return profile
    }
}
