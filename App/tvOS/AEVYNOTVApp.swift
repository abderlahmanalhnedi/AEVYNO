import DesignSystem
import Domain
import Library
import Playback
import SwiftUI
import UIKit

@main
struct AEVYNOTVApp: App {
  @Environment(\.scenePhase) private var scenePhase

  private let viewModel: HomeViewModel
  private let artworkPipeline: ArtworkImagePipeline
  private let sourceServiceFactory: SourceManagementViewModel.ServiceFactory
  private let sourceEditorDraft: SourceDraft?
  private let startsInSourceManagement: Bool
  private let refreshLifecycle: RefreshSchedulingLifecycleController
  private let usesSyntheticHome: Bool
  private let productionLibraryViewModel: ProductionLibraryViewModel?
  private let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  private let playbackEngineFactory: PlaybackDetailViewModel.EngineFactory
  private let continueWatchingServiceFactory: ContinueWatchingViewModel.ServiceFactory
  private let favoritesServiceFactory: FavoritesViewModel.ServiceFactory
  private let epgServiceFactory: EPGNowNextViewModel.ServiceFactory

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    startsInSourceManagement = arguments.contains("--ui-open-sources")
    usesSyntheticHome = TVDemoConfiguration.isExplicitSyntheticMode(arguments: arguments)
    let repository = TVDemoConfiguration.repository(arguments: arguments)
    viewModel = HomeViewModel(
      loader: HomeLoader(
        fetchHomeSections: FetchHomeSections(repository: repository)
      )
    )
    artworkPipeline = ArtworkImagePipeline()
    if arguments.contains("--ui-source-management") {
      let fixture = TVSourceManagementFixture(arguments: arguments)
      sourceServiceFactory = { fixture }
      sourceEditorDraft = TVSourceManagementFixture.editorDraft(arguments: arguments)
      refreshLifecycle = RefreshSchedulingLifecycleController { fixture }
      productionLibraryViewModel = nil
      let playbackFixture = TVPlaybackFixture(arguments: arguments)
      let playbackDependencies = playbackFixture.dependencies
      playbackServiceFactory = { playbackDependencies }
      playbackEngineFactory = { playbackFixture.makeEngine() }
      continueWatchingServiceFactory = TVContinueWatchingFixture.service(arguments: arguments)
      favoritesServiceFactory = TVFavoritesFixture.service(arguments: arguments)
      epgServiceFactory = { throw EPGPresentationError.unavailable }
    } else if let fixture = TVProductionLibraryFixture.fixture(arguments: arguments) {
      let sourceFixture = TVSourceManagementFixture(arguments: [])
      let playbackFixture = TVPlaybackFixture(arguments: arguments)
      let playbackDependencies = playbackFixture.dependencies
      sourceServiceFactory = { sourceFixture }
      sourceEditorDraft = nil
      refreshLifecycle = RefreshSchedulingLifecycleController { sourceFixture }
      productionLibraryViewModel = ProductionLibraryViewModel(
        serviceFactory: { fixture },
        initialQuery: TVProductionLibraryFixture.initialQuery(arguments: arguments)
      )
      playbackServiceFactory = { playbackDependencies }
      playbackEngineFactory = { playbackFixture.makeEngine() }
      continueWatchingServiceFactory = TVContinueWatchingFixture.service(arguments: arguments)
      favoritesServiceFactory = TVFavoritesFixture.service(arguments: arguments)
      let hasEPGFixture =
        arguments.contains("--ui-production-now-next")
        || arguments.contains("--ui-production-guide")
      if hasEPGFixture {
        epgServiceFactory = { TVEPGPresentationFixture.service() }
      } else {
        epgServiceFactory = { throw EPGPresentationError.unavailable }
      }
    } else {
      let serviceContainer = AppSourceServiceContainer()
      sourceServiceFactory = { try await serviceContainer.services().sourceManagement }
      sourceEditorDraft = nil
      refreshLifecycle = RefreshSchedulingLifecycleController {
        try await serviceContainer.services().refreshScheduling
      }
      productionLibraryViewModel = ProductionLibraryViewModel {
        try await serviceContainer.services().productionLibrary
      }
      playbackServiceFactory = { try await serviceContainer.playbackDependencies() }
      playbackEngineFactory = { NativeAVPlayerEngine() }
      continueWatchingServiceFactory = { try await serviceContainer.services().continueWatching }
      favoritesServiceFactory = { try await serviceContainer.services().favorites }
      epgServiceFactory = { try await serviceContainer.services().epg }
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
        } else if usesSyntheticHome {
          TVHomeView(
            viewModel: viewModel,
            artworkPipeline: artworkPipeline,
            sourceServiceFactory: sourceServiceFactory,
            sourceEditorDraft: sourceEditorDraft
          )
        } else if let productionLibraryViewModel {
          TVProductionLibraryView(
            viewModel: productionLibraryViewModel,
            artworkPipeline: artworkPipeline,
            sourceServiceFactory: sourceServiceFactory,
            playbackServiceFactory: playbackServiceFactory,
            continueWatchingServiceFactory: continueWatchingServiceFactory,
            favoritesServiceFactory: favoritesServiceFactory,
            playbackEngineFactory: playbackEngineFactory,
            epgServiceFactory: epgServiceFactory
          )
        }
      }
      .preferredColorScheme(.dark)
      .onChange(of: scenePhase, initial: true) { _, phase in
        refreshLifecycle.transition(to: phase)
      }
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
  static func isExplicitSyntheticMode(arguments: [String]) -> Bool {
    arguments.contains("--ui-demo-home")
      || arguments.contains("--ui-state-empty")
      || arguments.contains("--ui-state-error")
      || arguments.contains("--ui-state-loading")
      || arguments.contains("--ui-stress-catalog")
      || arguments.contains("--ui-source-management")
  }

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
