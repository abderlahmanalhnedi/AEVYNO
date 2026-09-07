import DesignSystem
import Library
import SwiftUI
import UIKit

@main
struct AEVYNOTVApp: App {
  private let viewModel: HomeViewModel
  private let artworkPipeline: ArtworkImagePipeline

  init() {
    let repository = TVDemoConfiguration.repository(
      arguments: ProcessInfo.processInfo.arguments
    )
    viewModel = HomeViewModel(
      loader: HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: repository)
      )
    )
    artworkPipeline = ArtworkImagePipeline()
  }

  var body: some Scene {
    WindowGroup {
      TVHomeView(
        viewModel: viewModel,
        artworkPipeline: artworkPipeline
      )
      .onReceive(
        NotificationCenter.default.publisher(
          for: UIApplication.didReceiveMemoryWarningNotification
        )
      ) { _ in
        Task { await artworkPipeline.removeAll() }
      }
    }
  }
}

private enum TVDemoConfiguration {
  static func repository(arguments: [String]) -> any HomeRepository {
    if arguments.contains("--ui-state-empty") {
      return MockHomeRepository(scenario: .empty)
    }
    if arguments.contains("--ui-state-error") {
      return MockHomeRepository(scenario: .failure)
    }
    if arguments.contains("--ui-state-loading") {
      return MockHomeRepository(scenario: .prolongedLoading)
    }
    if arguments.contains("--ui-stress-catalog") {
      return SyntheticLargeCatalogHomeRepository(
        scale: .tenThousand,
        itemsPerSection: 160
      )
    }
    return MockHomeRepository()
  }
}
