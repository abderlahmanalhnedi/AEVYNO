import Foundation

struct XtreamAuthenticationDTO: Decodable {
  struct UserInfo: Decodable {
    let authenticated: Bool?
    let status: String?
    let expiresAtEpoch: Int64?
    let isTrial: Bool?
    let activeConnections: Int?
    let maximumConnections: Int?
    let allowedOutputFormats: [String]

    enum CodingKeys: String, CodingKey {
      case authenticated = "auth"
      case status
      case expiresAtEpoch = "exp_date"
      case isTrial = "is_trial"
      case activeConnections = "active_cons"
      case maximumConnections = "max_connections"
      case allowedOutputFormats = "allowed_output_formats"
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      authenticated = container.flexibleBool(forKey: .authenticated)
      status = container.flexibleString(forKey: .status)
      expiresAtEpoch = container.flexibleInt64(forKey: .expiresAtEpoch)
      isTrial = container.flexibleBool(forKey: .isTrial)
      activeConnections = container.flexibleInt(forKey: .activeConnections)
      maximumConnections = container.flexibleInt(forKey: .maximumConnections)
      allowedOutputFormats = container.flexibleStringArray(forKey: .allowedOutputFormats)
    }
  }

  struct ServerInfo: Decodable {
    let timeZoneIdentifier: String?

    enum CodingKeys: String, CodingKey {
      case timeZoneIdentifier = "timezone"
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      timeZoneIdentifier = container.flexibleString(forKey: .timeZoneIdentifier)
    }
  }

  let userInfo: UserInfo?
  let serverInfo: ServerInfo?

  enum CodingKeys: String, CodingKey {
    case userInfo = "user_info"
    case serverInfo = "server_info"
  }
}

struct XtreamCategoryDTO: Decodable {
  let providerID: String?
  let title: String?

  enum CodingKeys: String, CodingKey {
    case providerID = "category_id"
    case title = "category_name"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerID = container.flexibleString(forKey: .providerID)
    title = container.flexibleString(forKey: .title)
  }
}

struct XtreamCatalogItemDTO: Decodable {
  let streamID: String?
  let seriesID: String?
  let title: String?
  let categoryID: String?
  let streamIcon: String?
  let cover: String?
  let coverBig: String?

  enum CodingKeys: String, CodingKey {
    case streamID = "stream_id"
    case seriesID = "series_id"
    case title = "name"
    case categoryID = "category_id"
    case streamIcon = "stream_icon"
    case cover
    case coverBig = "cover_big"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    streamID = container.flexibleString(forKey: .streamID)
    seriesID = container.flexibleString(forKey: .seriesID)
    title = container.flexibleString(forKey: .title)
    categoryID = container.flexibleString(forKey: .categoryID)
    streamIcon = container.flexibleString(forKey: .streamIcon)
    cover = container.flexibleString(forKey: .cover)
    coverBig = container.flexibleString(forKey: .coverBig)
  }
}

private struct FlexibleScalar: Decodable {
  let stringValue: String

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      stringValue = value
    } else if let value = try? container.decode(Int64.self) {
      stringValue = String(value)
    } else if let value = try? container.decode(Double.self), value.isFinite {
      stringValue = Int64(exactly: value).map(String.init) ?? String(value)
    } else if let value = try? container.decode(Bool.self) {
      stringValue = value ? "1" : "0"
    } else {
      throw DecodingError.typeMismatch(
        FlexibleScalar.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected a string-compatible scalar."
        )
      )
    }
  }
}

extension KeyedDecodingContainer {
  fileprivate func flexibleString(forKey key: Key) -> String? {
    guard
      let value = try? decodeIfPresent(FlexibleScalar.self, forKey: key)?.stringValue,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }
    return value
  }

  fileprivate func flexibleInt(forKey key: Key) -> Int? {
    flexibleString(forKey: key).flatMap(Int.init)
  }

  fileprivate func flexibleInt64(forKey key: Key) -> Int64? {
    flexibleString(forKey: key).flatMap(Int64.init)
  }

  fileprivate func flexibleBool(forKey key: Key) -> Bool? {
    guard let value = flexibleString(forKey: key)?.lowercased() else {
      return nil
    }
    switch value {
    case "1", "true", "yes":
      return true
    case "0", "false", "no":
      return false
    default:
      return nil
    }
  }

  fileprivate func flexibleStringArray(forKey key: Key) -> [String] {
    if let values = try? decodeIfPresent([FlexibleScalar].self, forKey: key) {
      return values.map(\.stringValue).filter { !$0.isEmpty }
    }
    if let value = flexibleString(forKey: key) {
      return [value]
    }
    return []
  }
}
