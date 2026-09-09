import DesignSystem
import Domain
import Library
import SwiftUI
import UIKit

@main
struct AEVYNOTVApp: App {
  private let viewModel: HomeViewModel
  private let artworkPipeline: ArtworkImagePipeline
  private let sourceServiceFactory: SourceManagementViewModel.ServiceFactory
  private let sourceEditorDraft: SourceDraft?
  private let startsInSourceManagement: Bool

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    startsInSourceManagement = arguments.contains("--ui-open-sources")
    let repository = TVDemoConfiguration.repository(arguments: arguments)
    viewModel = HomeViewModel(
      loader: HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: repository)
      )
    )
    artworkPipeline = ArtworkImagePipeline()
    if arguments.contains("--ui-source-management") {
      let fixture = TVSourceManagementFixture(
        seeded: arguments.contains("--ui-source-seeded"),
        connectionFails: arguments.contains("--ui-source-connection-failure")
      )
      sourceServiceFactory = { fixture }
      sourceEditorDraft = TVSourceManagementFixture.editorDraft(arguments: arguments)
    } else {
      sourceServiceFactory = { try await SourceManagementService.openDefault() }
      sourceEditorDraft = nil
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if startsInSourceManagement {
          NavigationStack {
            TVSourcesView(
              serviceFactory: sourceServiceFactory,
              newSourceDraft: sourceEditorDraft
            )
          }
        } else {
          TVHomeView(
            viewModel: viewModel,
            artworkPipeline: artworkPipeline,
            sourceServiceFactory: sourceServiceFactory,
            sourceEditorDraft: sourceEditorDraft
          )
        }
      }
      .preferredColorScheme(.dark)
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
