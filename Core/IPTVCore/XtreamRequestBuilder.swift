import AEVYNOSecurity
import Domain
import Foundation

struct XtreamRequestBuilder: Sendable {
  let timeout: TimeInterval

  func request(
    endpoint: SourceEndpoint,
    credential: SourceCredential,
    action: XtreamAction?
  ) throws -> URLRequest {
    guard
      timeout > 0,
      let username = credential.username,
      !username.isEmpty,
      var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
    else {
      throw ProviderAdapterError.invalidSourceConfiguration
    }

    let trimmedPath =
      components.path.hasSuffix("/")
      ? String(components.path.dropLast())
      : components.path
    if !trimmedPath.hasSuffix("/player_api.php") {
      components.path = trimmedPath + "/player_api.php"
    }

    var queryItems = [
      URLQueryItem(name: "username", value: username),
      URLQueryItem(name: "password", value: credential.secret),
    ]
    if let action {
      queryItems.append(URLQueryItem(name: "action", value: action.rawValue))
    }
    components.queryItems = queryItems

    guard let url = components.url else {
      throw ProviderAdapterError.invalidSourceConfiguration
    }

    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: timeout
    )
    request.httpMethod = "GET"
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    return request
  }
}

enum XtreamAction: String, Sendable {
  case liveCategories = "get_live_categories"
  case liveStreams = "get_live_streams"
  case vodCategories = "get_vod_categories"
  case vodStreams = "get_vod_streams"
  case seriesCategories = "get_series_categories"
  case series = "get_series"

  init(categoryKind kind: ProviderMediaKind) {
    switch kind {
    case .live:
      self = .liveCategories
    case .vod:
      self = .vodCategories
    case .series:
      self = .seriesCategories
    }
  }

  init(catalogKind kind: ProviderMediaKind) {
    switch kind {
    case .live:
      self = .liveStreams
    case .vod:
      self = .vodStreams
    case .series:
      self = .series
    }
  }
}
