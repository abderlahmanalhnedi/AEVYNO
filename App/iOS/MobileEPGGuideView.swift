import DesignSystem
import Domain
import Library
import Playback
import SwiftUI

/// Touch-native companion guide. It shares the bounded query/presentation model but has no focus state.
struct MobileEPGGuideView: View {
  let sourceID: SourceConfiguration.ID
  let serviceFactory: EPGGuideViewModel.ServiceFactory
  let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  @State private var viewModel: EPGGuideViewModel
  @State private var selected: GuideSelection?

  init(
    sourceID: SourceConfiguration.ID, serviceFactory: @escaping EPGGuideViewModel.ServiceFactory,
    playbackServiceFactory: @escaping PlaybackDetailViewModel.ServiceFactory
  ) {
    self.sourceID = sourceID
    self.serviceFactory = serviceFactory
    self.playbackServiceFactory = playbackServiceFactory
    _viewModel = State(
      initialValue: EPGGuideViewModel(sourceID: sourceID, serviceFactory: serviceFactory))
  }

  var body: some View {
    Group {
      if viewModel.isLoading && viewModel.guide == nil {
        ProgressView().tint(AEVYNOColor.accent)
      } else if let guide = viewModel.guide, !guide.channels.isEmpty {
        guideRows(guide)
      } else {
        StatePresentation(
          symbolName: "calendar",
          title: viewModel.isUnavailable ? AppText.guideUnavailable : AppText.guideEmptyTitle,
          message: AppText.guideEmptyMessage)
      }
    }
    .navigationTitle(AppText.guide).background(AEVYNOColor.background)
    .navigationDestination(item: $selected) { selection in
      MobileGuideDetail(selection: selection, playbackServiceFactory: playbackServiceFactory)
    }
    .task { await viewModel.load() }
  }

  private func guideRows(_ guide: EPGGuidePresentation) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
          Text(
            "\(AppText.guideNow) · \(AppText.guideTime(guide.interval.start)) – \(AppText.guideTime(guide.interval.end))"
          )
          .aevynoTypography(.metadata).foregroundStyle(AEVYNOColor.accent)
        }
        ForEach(guide.channels) { channel in
          VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
            Text(channel.title).aevynoTypography(.sectionTitle)
            ScrollView(.horizontal) {
              LazyHStack(spacing: AEVYNOSpacing.sm) {
                ForEach(channel.programmes) { programme in
                  Button {
                    selected = GuideSelection(channel: channel, programme: programme)
                  } label: {
                    VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
                      Text(programme.title).aevynoTypography(.cardTitle).lineLimit(2)
                      Text(
                        "\(AppText.guideTime(programme.timeRange.start)) – \(AppText.guideTime(programme.timeRange.end))"
                      ).aevynoTypography(.metadata)
                    }.padding(AEVYNOSpacing.md).frame(width: 190, height: 100, alignment: .leading)
                      .background(AEVYNOColor.surface).clipShape(
                        RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))
                  }.buttonStyle(.plain).accessibilityLabel(
                    AppText.guideProgrammeAccessibility(
                      programme.title, channel: channel.title, start: programme.timeRange.start,
                      end: programme.timeRange.end))
                }
              }
            }.scrollIndicators(.hidden)
          }
        }
        if guide.nextOffset != nil {
          Button(AppText.guideLoadMore) { Task { await viewModel.loadNextPage() } }.buttonStyle(
            .borderedProminent)
        }
      }.padding(AEVYNOSpacing.md)
    }
  }
}

private struct GuideSelection: Identifiable, Hashable {
  let channel: EPGGuideChannel
  let programme: EPGProgramme
  var id: String { "\(channel.id)|\(programme.id)" }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct MobileGuideDetail: View {
  let selection: GuideSelection
  let playbackServiceFactory: PlaybackDetailViewModel.ServiceFactory
  @State private var session: PlaybackSession?
  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.md) {
      Text(selection.channel.title).aevynoTypography(.eyebrow)
      Text(selection.programme.title).aevynoTypography(.detailTitle)
      Text(
        "\(AppText.guideTime(selection.programme.timeRange.start)) – \(AppText.guideTime(selection.programme.timeRange.end))"
      ).aevynoTypography(.metadata)
      if let subtitle = selection.programme.subtitle { Text(subtitle) }
      if let description = selection.programme.description { Text(description) }
      Button(AppText.play) { play() }.buttonStyle(.borderedProminent)
    }.padding(AEVYNOSpacing.md).frame(
      maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading
    ).background(AEVYNOColor.background)
      .fullScreenCover(item: $session) { PlaybackPresentationView(session: $0) }
  }
  private func play() {
    Task {
      guard let dependencies = try? await playbackServiceFactory() else { return }
      let next = PlaybackSession(
        resolver: dependencies.resolver, progressRepository: dependencies.progressRepository)
      next.start(mediaID: selection.channel.id, title: selection.channel.title, kind: .live)
      session = next
    }
  }
}
