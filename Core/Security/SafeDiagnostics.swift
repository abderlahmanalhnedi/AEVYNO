import Foundation

public enum SafeDiagnostics {
  public static let redactionMarker = "<redacted>"
  public static let redactedURLMarker = "<redacted-url>"

  public static func redacting(_ sensitiveValues: [String], in message: String) -> String {
    sensitiveValues
      .filter { !$0.isEmpty }
      .sorted { $0.count > $1.count }
      .reduce(message) { redactedMessage, sensitiveValue in
        redactedMessage.replacingOccurrences(
          of: sensitiveValue,
          with: redactionMarker
        )
      }
  }

  public static func sanitizedURL(_ url: URL) -> String {
    guard
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme,
      let host = components.host
    else {
      return redactedURLMarker
    }

    var sanitizedComponents = URLComponents()
    sanitizedComponents.scheme = scheme
    sanitizedComponents.host = host
    sanitizedComponents.port = components.port

    if !components.path.isEmpty && components.path != "/" {
      sanitizedComponents.path = "/redacted"
    } else {
      sanitizedComponents.path = components.path
    }

    if components.percentEncodedQuery != nil {
      sanitizedComponents.query = "redacted"
    }

    return sanitizedComponents.string ?? redactedURLMarker
  }
}
