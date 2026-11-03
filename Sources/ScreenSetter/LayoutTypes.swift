import Foundation

enum LayoutError: LocalizedError {
    case layoutNotFound
    case groupNotFound
    case emptyName
    case displaysChanged
    /// The named layout's display set is not the connected one.
    case displayNotConnected(String)
    case invalidArrangement(String)
    case modeUnavailable(String)
    case invalidSnapshot
    case automaticChanged
    case newerLibrary
    case libraryUnreadable

    var errorDescription: String? {
        switch self {
        case .layoutNotFound:
            return "That layout no longer exists."
        case .groupNotFound:
            return "That display set no longer exists."
        case .emptyName:
            return "Enter a name for the layout."
        case .displaysChanged:
            return "The layout must use the same displays it was saved with."
        case .displayNotConnected(let name):
            return "Connect the displays used by “\(name)”, then try again."
        case .invalidArrangement(let reason):
            return reason
        case .modeUnavailable(let name):
            return "The selected resolution is not available on “\(name)”."
        case .invalidSnapshot:
            return "The layout contains invalid display data. Save it again from the current arrangement."
        case .automaticChanged:
            return "The displays changed while automatic restore was waiting. Review the layout and apply it manually."
        case .newerLibrary:
            return "Your layouts were saved by a newer version of Screen Setter. Update the app to change them."
        case .libraryUnreadable:
            return "Screen Setter cannot read its library file, so changes are not saved. Check the permissions of ~/Library/Application Support/Screen Setter."
        }
    }
}
