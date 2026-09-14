import Domain
import Foundation
import Library

actor TVContinueWatchingFixture: ContinueWatchingServing {
  private let fixtureItems: [ContinueWatchingItemPresentation]

  static func service(arguments: [String]) -> ContinueWatchingViewModel.ServiceFactory {
    let fixture = TVContinueWatchingFixture(arguments: arguments)
    return { fixture }
  }

  init(arguments: [String]) {
    if arguments.contains("--ui-continue-watching") {
      fixtureItems = [
        ContinueWatchingItemPresentation(
          id: "m3u-1",
          title: "Movie Night Live.m3u8",
          mediaKind: .unspecified,
          artworkURL: URL(string: "https://image.invalid/continue-watching"),
          progressFraction: 0.25,
          position: 125,
          duration: 500
        )
      ]
    } else {
      fixtureItems = []
    }
  }

  func items() -> [ContinueWatchingItemPresentation] { fixtureItems }

  func revisions() -> AsyncStream<UInt64> { AsyncStream { $0.finish() } }
}
