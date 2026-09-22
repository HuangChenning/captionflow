enum AppSessionState: Equatable {
    case idle
    case requestingPermission
    case running
    case stopping
    case failed(String)
}
