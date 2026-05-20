import Foundation

public enum HealthArchiveServerNamespace {
    public static func normalized(from url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else {
            return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var namespace = "\(scheme)://\(host)"
        if let port = url.port {
            namespace += ":\(port)"
        }
        if !url.path.isEmpty && url.path != "/" {
            namespace += url.path
        }
        return namespace
    }
}
