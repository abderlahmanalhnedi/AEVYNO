import CryptoKit
import Domain
import Foundation

struct CatalogReferenceCipher {
  let key: SymmetricKey

  struct References: Codable {
    let media: String?
    let artwork: String?
    let provider: ProviderItemReference?
  }

  func seal(_ item: CatalogItem) throws -> String {
    let payload = References(
      media: item.mediaURL?.absoluteString, artwork: item.artworkURL?.absoluteString,
      provider: item.providerReference)
    do {
      let box = try AES.GCM.seal(
        JSONEncoder().encode(payload), using: key, authenticating: Data(item.id.utf8))
      guard let combined = box.combined else { throw CatalogStoreError.writeFailed }
      return combined.base64EncodedString()
    } catch { throw CatalogStoreError.writeFailed }
  }

  func open(_ sealed: String, id: String) throws -> References {
    do {
      guard let data = Data(base64Encoded: sealed) else { throw CatalogStoreError.corruptedStore }
      let plaintext = try AES.GCM.open(
        AES.GCM.SealedBox(combined: data), using: key, authenticating: Data(id.utf8))
      return try JSONDecoder().decode(References.self, from: plaintext)
    } catch { throw CatalogStoreError.corruptedStore }
  }
}
