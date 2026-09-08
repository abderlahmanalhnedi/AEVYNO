import DesignSystem
import Domain
import SwiftUI

struct TVDetailView: View {
  @State private var isShowingPreviewNotice = false
  @State private var isSavedForDemo = false

  let item: MediaItem
  let artworkPipeline: ArtworkImagePipeline

  private var presentation: MediaPresentation {
    AppText.mediaPresentation(for: item)
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      AEVYNOColor.background.ignoresSafeArea()
      heroArtwork
      detailGradient
      details
    }
    .navigationBarBackButtonHidden(false)
    .alert(AppText.detailPreviewNoticeTitle, isPresented: $isShowingPreviewNotice) {
      Button(AppText.done, role: .cancel) {}
    } message: {
      Text(AppText.detailPreviewNoticeMessage)
    }
  }

  private var heroArtwork: some View {
    GeometryReader { proxy in
      ArtworkImageView(
        request: ArtworkRequest(
          itemID: item.id,
          theme: item.artworkTheme,
          kind: item.kind,
          pixelWidth: min(Int(proxy.size.width * 1.25), 2_048),
          pixelHeight: min(Int(proxy.size.height * 1.25), 2_048)
        ),
        pipeline: artworkPipeline
      )
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
      .accessibilityHidden(true)
    }
    .ignoresSafeArea()
  }

  private var detailGradient: some View {
    LinearGradient(
      stops: [
        .init(color: AEVYNOColor.background.opacity(0.05), location: 0),
        .init(color: AEVYNOColor.background.opacity(0.72), location: 0.48),
        .init(color: AEVYNOColor.background, location: 0.84),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: AEVYNOSpacing.lg) {
      VStack(alignment: .leading, spacing: AEVYNOSpacing.sm) {
        Text(AppText.detailEyebrow(for: item.kind))
          .aevynoTypography(.eyebrow)
          .tracking(2.4)
          .foregroundStyle(AEVYNOColor.accent)

        Text(presentation.title)
          .aevynoTypography(.detailTitle)
          .foregroundStyle(AEVYNOColor.primaryText)
          .accessibilityIdentifier("detail.title")
          .accessibilityAddTraits(.isHeader)

        if !presentation.facts.isEmpty {
          Text(presentation.facts.joined(separator: "  ·  "))
            .aevynoTypography(.metadata)
            .foregroundStyle(Color.white.opacity(0.82))
            .accessibilityLabel(presentation.facts.joined(separator: ", "))
        }
      }
      .accessibilityElement(children: .contain)

      Text(presentation.summary)
        .aevynoTypography(.status)
        .foregroundStyle(AEVYNOColor.primaryText.opacity(0.9))
        .lineLimit(3)
        .frame(maxWidth: 860, alignment: .leading)

      HStack(spacing: AEVYNOSpacing.md) {
        Button {
          isShowingPreviewNotice = true
        } label: {
          Label(AppText.detailPlayPreview, systemImage: "play.fill")
            .frame(minWidth: 220)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .accessibilityIdentifier("detail.play")
        .accessibilityHint(AppText.detailPlayAccessibilityHint)

        Button {
          isSavedForDemo.toggle()
        } label: {
          Label(
            isSavedForDemo ? AppText.detailSaved : AppText.detailSave,
            systemImage: isSavedForDemo ? "checkmark" : "plus"
          )
          .frame(minWidth: 220)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("detail.save")
        .accessibilityValue(
          isSavedForDemo
            ? AppText.detailSavedAccessibilityValue
            : AppText.detailNotSavedAccessibilityValue
        )
        .accessibilityHint(AppText.detailSaveAccessibilityHint)
      }
    }
    .padding(.horizontal, 110)
    .padding(.bottom, 88)
  }
}
