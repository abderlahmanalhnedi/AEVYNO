import DesignSystem
import Domain
import Library
import Playback
import SwiftUI

private struct TVGuideProgrammeSelection: Identifiable, Hashable {
  let channel: EPGGuideChannel
  let programme: EPGProgramme
  var id: String { "\(channel.id)|\(programme.id)" }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A bounded Apple TV guide. Its only retained data is one 40-channel, eight-hour presentation.
struct TVEPGGuideView: View {
  @Environment(\.resetFocus) private var resetFocus
  @Namespace private var guideFocusScope
  let sourceID: SourceConfiguration.ID
  let serviceFactory: EPGGuideViewModel.ServiceFactory
  let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  let playbackEngineFactory: PlaybackDetailViewModel.EngineFactory
  @State private var viewModel: EPGGuideViewModel
  @State private var selection: TVGuideProgrammeSelection?
  @FocusState private var focusedProgrammeID: String?
  @State private var rememberedProgrammeID: String?

  init(
    sourceID: SourceConfiguration.ID,
    serviceFactory: @escaping EPGGuideViewModel.ServiceFactory,
    playbackServiceFactory: @escaping PlaybackDetailViewModel.ServiceFactory,
    playbackEngineFactory: @escaping PlaybackDetailViewModel.EngineFactory
  ) {
    self.sourceID = sourceID
    self.serviceFactory = serviceFactory
    self.playbackServiceFactory = playbackServiceFactory
    self.playbackEngineFactory = playbackEngineFactory
    _viewModel = State(
      initialValue: EPGGuideViewModel(sourceID: sourceID, serviceFactory: serviceFactory))
  }

  var body: some View {
    ZStack {
      AEVYNOColor.background.ignoresSafeArea()
      if viewModel.isLoading && viewModel.guide == nil {
        ProgressView().tint(AEVYNOColor.accent)
      } else if viewModel.isUnavailable {
        StatusPanel(
          symbolName: "calendar.badge.exclamationmark", title: AppText.guideUnavailable,
          message: AppText.guideEmptyMessage)
      } else if let guide = viewModel.guide, !guide.channels.isEmpty {
        guideContent(guide)
      } else {
        StatusPanel(
          symbolName: "calendar", title: AppText.guideEmptyTitle,
          message: AppText.guideEmptyMessage)
      }
    }
    .navigationTitle(AppText.guide)
    .sheet(item: $selection, onDismiss: restoreProgrammeFocus) { selection in
      TVGuideProgrammeDetail(
        selection: selection, playbackServiceFactory: playbackServiceFactory,
        playbackEngineFactory: playbackEngineFactory)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if viewModel.guide?.nextOffset != nil {
          Button(AppText.guideLoadMore) { Task { await viewModel.loadNextPage() } }
            .accessibilityIdentifier("guide.more-channels")
        }
      }
    }
    .task { await viewModel.load() }
  }

  private func guideContent(_ guide: EPGGuidePresentation) -> some View {
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
        guideAxis(guide.interval)
        ForEach(guide.channels) { channel in
          HStack(alignment: .top, spacing: AEVYNOSpacing.md) {
            Text(channel.title).aevynoTypography(.cardTitle).frame(width: 230, alignment: .leading)
            ScrollView(.horizontal) {
              LazyHStack(spacing: AEVYNOSpacing.xs) {
                ForEach(channel.programmes) { programme in
                  let identity = "\(channel.id)|\(programme.id)"
                  Button {
                    rememberedProgrammeID = identity
                    selection = TVGuideProgrammeSelection(channel: channel, programme: programme)
                  } label: {
                    VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
                      Text(programme.title).aevynoTypography(.cardTitle).lineLimit(2)
                      Text(
                        "\(AppText.guideTime(programme.timeRange.start)) – \(AppText.guideTime(programme.timeRange.end))"
                      )
                      .aevynoTypography(.metadata).foregroundStyle(AEVYNOColor.secondaryText)
                    }
                    .padding(AEVYNOSpacing.md).frame(
                      width: cellWidth(programme, in: guide.interval), height: 104,
                      alignment: .leading
                    )
                    .background(
                      programme.timeRange.contains(Date())
                        ? AEVYNOColor.accent.opacity(0.28) : AEVYNOColor.surface
                    )
                    .clipShape(
                      RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
                  }
                  .buttonStyle(TVMediaButtonStyle())
                  .focused($focusedProgrammeID, equals: identity)
                  .prefersDefaultFocus(
                    focusedProgrammeID == identity, in: guideFocusScope
                  )
                  .accessibilityIdentifier(
                    "guide.cell.\(channel.id).\(programmeAccessibilitySuffix(programme))"
                  )
                  .accessibilityLabel(
                    AppText.guideProgrammeAccessibility(
                      programme.title, channel: channel.title, start: programme.timeRange.start,
                      end: programme.timeRange.end))
                }
                if channel.programmes.isEmpty {
                  Text("—").foregroundStyle(AEVYNOColor.secondaryText).frame(
                    width: 144, height: 104)
                }
              }
            }.scrollIndicators(.hidden)
          }
        }
      }
      .padding(.horizontal, AEVYNOSpacing.xxl).padding(.vertical, AEVYNOSpacing.xl)
    }
    .focusScope(guideFocusScope)
    .accessibilityIdentifier("guide.loaded")
    .onChange(of: guide.channels.map(\.id)) { _, _ in
      guard let channel = guide.channels.first, let first = channel.programmes.first else { return }
      focusedProgrammeID = "\(channel.id)|\(first.id)"
      resetFocus(in: guideFocusScope)
    }
  }

  private func guideAxis(_ interval: EPGGuideInterval) -> some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      HStack {
        Text("\(AppText.guideTime(interval.start)) – \(AppText.guideTime(interval.end))")
        Spacer()
        Text(AppText.guideNow).foregroundStyle(AEVYNOColor.accent)
        Circle().fill(AEVYNOColor.accent).frame(width: 8, height: 8)
      }
      .aevynoTypography(.metadata).foregroundStyle(AEVYNOColor.secondaryText).frame(maxWidth: 1_600)
    }
  }

  private func cellWidth(_ programme: EPGProgramme, in interval: EPGGuideInterval) -> CGFloat {
    let proportion =
      programme.timeRange.end.timeIntervalSince(programme.timeRange.start)
      / interval.end.timeIntervalSince(interval.start)
    return max(144, min(520, 1_200 * proportion))
  }

  private func restoreProgrammeFocus() {
    guard let rememberedProgrammeID else { return }
    Task { @MainActor in
      await Task.yield()
      focusedProgrammeID = rememberedProgrammeID
      resetFocus(in: guideFocusScope)
    }
  }

  private func programmeAccessibilitySuffix(_ programme: EPGProgramme) -> String {
    programme.title.lowercased().unicodeScalars.map { scalar in
      CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
    }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

private struct TVGuideProgrammeDetail: View {
  let selection: TVGuideProgrammeSelection
  let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  let playbackEngineFactory: PlaybackDetailViewModel.EngineFactory
  @State private var playbackSession: PlaybackSession?

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      Text(selection.channel.title).aevynoTypography(.eyebrow).foregroundStyle(AEVYNOColor.accent)
      Text(selection.programme.title).aevynoTypography(.detailTitle)
      Text(
        "\(AppText.guideTime(selection.programme.timeRange.start)) – \(AppText.guideTime(selection.programme.timeRange.end))"
      ).aevynoTypography(.metadata)
      if let subtitle = selection.programme.subtitle { Text(subtitle).aevynoTypography(.status) }
      if let description = selection.programme.description {
        Text(description).aevynoTypography(.status)
      }
      Button(AppText.play) { play() }.buttonStyle(.borderedProminent).accessibilityIdentifier(
        "guide.detail.play")
    }
    .padding(110).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(AEVYNOColor.background)
    .fullScreenCover(item: $playbackSession) { PlaybackPresentationView(session: $0) }
  }

  private func play() {
    Task {
      guard let dependencies = try? await playbackServiceFactory() else { return }
      let session = PlaybackSession(
        resolver: dependencies.resolver, progressRepository: dependencies.progressRepository,
        engineFactory: playbackEngineFactory)
      session.start(mediaID: selection.channel.id, title: selection.channel.title, kind: .live)
      playbackSession = session
    }
  }
}
