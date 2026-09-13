import AVKit
import DesignSystem
import Domain
import Library
import Observation
import Playback
import SwiftUI

struct PlaybackDependencies: Sendable {
  let resolver: any PlaybackAssetResolving
  let progressRepository: any WatchProgressRepository
}

@MainActor
@Observable
final class PlaybackDetailViewModel {
  typealias ServiceFactory = @Sendable () async throws -> PlaybackDependencies
  typealias EngineFactory = @MainActor () -> any PlaybackEngine

  enum State: Equatable {
    case loading
    case play
    case resume(TimeInterval)
    case unavailable(PlaybackFailure)
  }

  private let item: LibraryItemPresentation
  private let serviceFactory: ServiceFactory
  private let engineFactory: EngineFactory
  private var dependencies: PlaybackDependencies?

  private(set) var state: State = .loading

  init(
    item: LibraryItemPresentation,
    serviceFactory: @escaping ServiceFactory,
    engineFactory: @escaping EngineFactory = { NativeAVPlayerEngine() }
  ) {
    self.item = item
    self.serviceFactory = serviceFactory
    self.engineFactory = engineFactory
  }

  func load() async {
    state = .loading
    do {
      let dependencies = try await serviceFactory()
      self.dependencies = dependencies
      switch await dependencies.resolver.availability(for: item.id) {
      case .playable:
        let progress = try? await dependencies.progressRepository.progress(for: item.id)
        if let position = PlaybackSession.resumablePosition(from: progress) {
          state = .resume(position)
        } else {
          state = .play
        }
      case .unavailable(let failure):
        state = .unavailable(failure)
      }
    } catch is CancellationError {
      return
    } catch {
      state = .unavailable(.sourceUnavailable)
    }
  }

  func makeSession(startOver: Bool) -> PlaybackSession? {
    guard let dependencies else { return nil }
    let session = PlaybackSession(
      resolver: dependencies.resolver,
      progressRepository: dependencies.progressRepository,
      engineFactory: engineFactory
    )
    session.start(
      mediaID: item.id,
      title: item.title,
      kind: item.mediaKind,
      startOver: startOver
    )
    return session
  }
}

struct PlaybackPresentationView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State var session: PlaybackSession
  #if os(tvOS)
    @FocusState private var isRetryFocused: Bool
  #endif

  var body: some View {
    ZStack {
      SystemPlayerControllerView(session: session)
        .ignoresSafeArea()

      statusOverlay
    }
    .background(Color.black)
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { Task { await session.checkpoint() } }
    }
    .onDisappear { Task { await session.dismiss() } }
  }

  @ViewBuilder
  private var statusOverlay: some View {
    switch session.state {
    case .idle, .loading, .ready:
      playbackStatus(
        title: AppText.playbackLoading,
        identifier: "playback.state.\(session.state.rawValue)",
        showsProgress: true
      )
    case .buffering:
      playbackStatus(
        title: AppText.playbackBuffering,
        identifier: "playback.state.buffering",
        showsProgress: true
      )
    case .failed:
      VStack(spacing: AEVYNOSpacing.md) {
        Text(AppText.playbackFailed)
          .aevynoTypography(.sectionTitle)
          .accessibilityIdentifier("playback.state.failed")
        Text(AppText.playbackFailureMessage(session.failure))
          .aevynoTypography(.status)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        HStack(spacing: AEVYNOSpacing.sm) {
          retryButton
          Button(AppText.done) { dismiss() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("playback.close")
        }
      }
      .padding(AEVYNOSpacing.xl)
      .frame(maxWidth: 680)
      .background(.black.opacity(0.9))
      .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.panel, style: .continuous))
      .task {
        #if os(tvOS)
          isRetryFocused = true
        #endif
      }
    case .playing, .paused, .ended:
      Color.clear
        .accessibilityElement()
        .accessibilityLabel(AppText.playbackState(session.state))
        .accessibilityIdentifier("playback.state.\(session.state.rawValue)")
    }
  }

  @ViewBuilder
  private var retryButton: some View {
    #if os(tvOS)
      retryButtonContent.focused($isRetryFocused)
    #else
      retryButtonContent
    #endif
  }

  private var retryButtonContent: some View {
    Button(AppText.retry) { session.retry() }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("playback.retry")
      .accessibilityHint(AppText.playbackRetryHint)
  }

  private func playbackStatus(
    title: String,
    identifier: String,
    showsProgress: Bool
  ) -> some View {
    VStack(spacing: AEVYNOSpacing.md) {
      if showsProgress { ProgressView().tint(.white) }
      Text(title).aevynoTypography(.status)
    }
    .padding(AEVYNOSpacing.lg)
    .background(.black.opacity(0.82))
    .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
    .accessibilityIdentifier(identifier)
  }
}

private struct SystemPlayerControllerView: UIViewControllerRepresentable {
  let session: PlaybackSession

  func makeUIViewController(context _: Context) -> AVPlayerViewController {
    session.makePlayerViewController()
  }

  func updateUIViewController(_: AVPlayerViewController, context _: Context) {}
}
