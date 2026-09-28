import Foundation

/// Private pilot invitations never choose the server that receives their key.
public enum RelayInvitation {
    public static func connectionURL(serviceURL: String, code: String) throws -> String {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...128).contains(code.count),
              code.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw InvitationError.invalidCode
        }
        guard let url = URL(string: serviceURL) else { throw APIClientError.invalidBaseURL }
        _ = try APIClient(baseURL: url)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIClientError.invalidBaseURL }
        components.fragment = code
        guard let result = components.string else { throw APIClientError.invalidBaseURL }
        return result
    }
}

public enum InvitationError: LocalizedError {
    case invalidCode
    public var errorDescription: String? {
        "Paste the complete invite code from your Relay administrator. It contains only letters, numbers, hyphens, and underscores."
    }
}
