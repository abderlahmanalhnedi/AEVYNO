import DesignSystem
import Domain
import Library
import SwiftUI

struct MobileHomeView: View {
  @State private var viewModel: HomeViewModel

  init(viewModel: HomeViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AEVYNOColor.background.ignoresSafeArea()
        content
      }
      .navigationTitle(AppText.appName)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
    .task {
      await viewModel.loadIfNeeded()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.state {
    case .loading:
      MobileLoadingView()
    case .loaded(let sections):
      ScrollView {
        LazyVStack(alignment: .leading, spacing: AEVYNOSpacing.lg) {
          Text(AppText.mobileHomeSubtitle)
            .aevynoTypography(.status)
            .foregroundStyle(AEVYNOColor.secondaryText)

          ForEach(sections) { section in
            mobileSection(section)
          }
        }
        .padding(AEVYNOSpacing.md)
      }
      .accessibilityIdentifier("home.loaded")
    case .empty:
      StatusPanel(
        symbolName: "rectangle.stack.badge.plus",
        title: AppText.mobileHomeEmptyTitle,
        message: AppText.mobileHomeEmptyMessage
      )
      .padding(AEVYNOSpacing.md)
    case .failure:
      StatusPanel(
        symbolName: "arrow.clockwise.circle",
        title: AppText.homeErrorTitle,
        message: AppText.homeErrorMessage,
        actionTitle: AppText.retry,
        actionAccessibilityHint: AppText.retryAccessibilityHint
      ) {
        Task { await viewModel.reload() }
      }
      .padding(AEVYNOSpacing.md)
    }
  }

  private func mobileSection(_ section: HomeSection) -> some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
      Text(AppText.sectionTitle(for: section.id, fallback: section.title))
        .aevynoTypography(.sectionTitle)
        .foregroundStyle(AEVYNOColor.primaryText)
        .accessibilityAddTraits(.isHeader)

      ScrollView(.horizontal) {
        LazyHStack(spacing: AEVYNOSpacing.sm) {
          ForEach(section.items) { item in
            MobileMediaCard(item: item)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }
}

private struct MobileMediaCard: View {
  let item: MediaItem

  private var presentation: MediaPresentation {
    AppText.mediaPresentation(for: item)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.xs) {
      ArtworkPlaceholder(theme: item.artworkTheme, kind: item.kind)
        .frame(width: 190, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: AEVYNOCornerRadius.card, style: .continuous))

      Text(presentation.title)
        .aevynoTypography(.cardTitle)
        .foregroundStyle(AEVYNOColor.primaryText)
        .lineLimit(1)

      Text(presentation.subtitle)
        .aevynoTypography(.metadata)
        .foregroundStyle(AEVYNOColor.secondaryText)
        .lineLimit(1)
    }
    .frame(width: 190, alignment: .leading)
    .padding(AEVYNOSpacing.sm)
    .aevynoCardSurface()
    .accessibilityElement(children: .combine)
  }
}

private struct MobileLoadingView: View {
  var body: some View {
    ScrollView {
      LazyVStack(spacing: AEVYNOSpacing.md) {
        ForEach(0..<4, id: \.self) { _ in
          LoadingPlaceholder()
            .frame(height: 150)
        }
      }
      .padding(AEVYNOSpacing.md)
    }
    .accessibilityIdentifier("home.loading")
  }
}
