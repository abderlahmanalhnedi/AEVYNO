import DesignSystem
import Domain
import SwiftUI

struct TVDetailView: View {
  @State private var isShowingPreviewNotice = false
  @State private var isSavedForDemo = false

  let item: MediaItem
  let artworkPipeline: ArtworkImagePipeline

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      AEVYNOColor.background.ignoresSafeArea()
      heroArtwork
      detailGradient
      details
    }
    .navigationBarBackButtonHidden(false)
    .alert("Playback comes later", isPresented: $isShowingPreviewNotice) {
      Button("Done", role: .cancel) {}
    } message: {
      Text("This Phase 1 action is a safe interface preview and does not start playback.")
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
        Text(item.kind.detailEyebrow)
          .aevynoTypography(.eyebrow)
          .tracking(2.4)
          .foregroundStyle(AEVYNOColor.accent)

        Text(item.title)
          .aevynoTypography(.detailTitle)
          .foregroundStyle(AEVYNOColor.primaryText)
          .accessibilityIdentifier("detail.title")
          .accessibilityAddTraits(.isHeader)

        if !item.facts.isEmpty {
          Text(item.facts.joined(separator: "  ·  "))
            .aevynoTypography(.metadata)
            .foregroundStyle(Color.white.opacity(0.82))
            .accessibilityLabel(item.facts.joined(separator: ", "))
        }
      }
      .accessibilityElement(children: .contain)

      Text(item.summary)
        .aevynoTypography(.status)
        .foregroundStyle(AEVYNOColor.primaryText.opacity(0.9))
        .lineLimit(3)
        .frame(maxWidth: 860, alignment: .leading)

      HStack(spacing: AEVYNOSpacing.md) {
        Button {
          isShowingPreviewNotice = true
        } label: {
          Label("Play Preview", systemImage: "play.fill")
            .frame(minWidth: 220)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .accessibilityIdentifier("detail.play")
        .accessibilityHint("Shows a message; playback is not included in this preview")

        Button {
          isSavedForDemo.toggle()
        } label: {
          Label(
            isSavedForDemo ? "Saved for Demo" : "Save for Demo",
            systemImage: isSavedForDemo ? "checkmark" : "plus"
          )
          .frame(minWidth: 220)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("detail.save")
        .accessibilityValue(isSavedForDemo ? "Saved" : "Not saved")
        .accessibilityHint("Changes only this temporary synthetic preview")
      }
    }
    .padding(.horizontal, 110)
    .padding(.bottom, 88)
  }
}

extension MediaKind {
  fileprivate var detailEyebrow: String {
    switch self {
    case .movie: return "AEVYNO FILM"
    case .series: return "AEVYNO SERIES"
    case .liveChannel: return "AEVYNO LIVE"
    }
  }
}
