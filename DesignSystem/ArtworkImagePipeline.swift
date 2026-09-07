import CoreGraphics
import Domain
import Foundation
import ImageIO
import SwiftUI

public struct ArtworkImage: @unchecked Sendable {
  public let cgImage: CGImage
  public let costInBytes: Int

  public init(cgImage: CGImage) {
    self.cgImage = cgImage
    costInBytes = cgImage.bytesPerRow * cgImage.height
  }
}

public struct ArtworkRequest: Hashable, Sendable {
  public let itemID: MediaItem.ID
  public let theme: ArtworkTheme
  public let kind: MediaKind
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(
    itemID: MediaItem.ID,
    theme: ArtworkTheme,
    kind: MediaKind,
    pixelWidth: Int,
    pixelHeight: Int
  ) {
    self.itemID = itemID
    self.theme = theme
    self.kind = kind
    self.pixelWidth = min(max(pixelWidth, 1), 2_048)
    self.pixelHeight = min(max(pixelHeight, 1), 2_048)
  }
}

public struct ArtworkCacheMetrics: Equatable, Sendable {
  public let itemCount: Int
  public let costInBytes: Int
  public let maximumCostInBytes: Int
}

public enum ArtworkPipelineError: Error, Equatable, Sendable {
  case dataUnavailable
  case decodingFailed
  case renderingFailed
}

public typealias ArtworkRenderer = @Sendable (ArtworkRequest) async throws -> ArtworkImage
public typealias ArtworkDataLoader = @Sendable (ArtworkRequest) async throws -> Data

public actor ArtworkImagePipeline {
  private struct Entry: Sendable {
    let image: ArtworkImage
    var lastAccess: UInt64
  }

  private let maximumCostInBytes: Int
  private let renderer: ArtworkRenderer
  private var entries: [ArtworkRequest: Entry] = [:]
  private var totalCostInBytes = 0
  private var accessCounter: UInt64 = 0
  private var cacheGeneration: UInt64 = 0

  public init(maximumCostInBytes: Int = 48 * 1_024 * 1_024) {
    self.maximumCostInBytes = max(0, maximumCostInBytes)
    renderer = { request in
      try await SyntheticArtworkRenderer.render(request)
    }
  }

  public init(
    maximumCostInBytes: Int = 48 * 1_024 * 1_024,
    renderer: @escaping ArtworkRenderer
  ) {
    self.maximumCostInBytes = max(0, maximumCostInBytes)
    self.renderer = renderer
  }

  public init(
    maximumCostInBytes: Int = 48 * 1_024 * 1_024,
    dataLoader: @escaping ArtworkDataLoader
  ) {
    self.maximumCostInBytes = max(0, maximumCostInBytes)
    renderer = { request in
      let data = try await dataLoader(request)
      try Task.checkCancellation()
      return try ArtworkDownsampler.decode(data: data, request: request)
    }
  }

  public func image(for request: ArtworkRequest) async throws -> ArtworkImage {
    try Task.checkCancellation()

    if var entry = entries[request] {
      accessCounter &+= 1
      entry.lastAccess = accessCounter
      entries[request] = entry
      return entry.image
    }

    let generation = cacheGeneration
    let image = try await renderer(request)
    try Task.checkCancellation()
    if generation == cacheGeneration {
      insert(image, for: request)
    }
    return image
  }

  public func removeAll() {
    entries.removeAll(keepingCapacity: false)
    totalCostInBytes = 0
    accessCounter = 0
    cacheGeneration &+= 1
  }

  public func metrics() -> ArtworkCacheMetrics {
    ArtworkCacheMetrics(
      itemCount: entries.count,
      costInBytes: totalCostInBytes,
      maximumCostInBytes: maximumCostInBytes
    )
  }

  private func insert(_ image: ArtworkImage, for request: ArtworkRequest) {
    guard maximumCostInBytes > 0, image.costInBytes <= maximumCostInBytes else { return }

    if let previous = entries.removeValue(forKey: request) {
      totalCostInBytes -= previous.image.costInBytes
    }

    accessCounter &+= 1
    entries[request] = Entry(image: image, lastAccess: accessCounter)
    totalCostInBytes += image.costInBytes

    while totalCostInBytes > maximumCostInBytes,
      let leastRecentlyUsed = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })
    {
      entries.removeValue(forKey: leastRecentlyUsed.key)
      totalCostInBytes -= leastRecentlyUsed.value.image.costInBytes
    }
  }
}

public struct ArtworkImageView: View {
  private let request: ArtworkRequest
  private let pipeline: ArtworkImagePipeline
  @State private var image: ArtworkImage?

  public init(request: ArtworkRequest, pipeline: ArtworkImagePipeline) {
    self.request = request
    self.pipeline = pipeline
  }

  public var body: some View {
    Group {
      if let image {
        Image(decorative: image.cgImage, scale: 1, orientation: .up)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        ArtworkPlaceholder(theme: request.theme, kind: request.kind)
      }
    }
    .task(id: request) {
      do {
        let loadedImage = try await pipeline.image(for: request)
        try Task.checkCancellation()
        image = loadedImage
      } catch is CancellationError {
        return
      } catch {
        image = nil
      }
    }
  }
}

private enum ArtworkDownsampler {
  static func decode(data: Data, request: ArtworkRequest) throws -> ArtworkImage {
    let sourceOptions: [CFString: Any] = [
      kCGImageSourceShouldCache: false
    ]
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData,
        sourceOptions as CFDictionary
      )
    else {
      throw ArtworkPipelineError.dataUnavailable
    }

    let maximumDimension = max(request.pixelWidth, request.pixelHeight)
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
    ]

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw ArtworkPipelineError.decodingFailed
    }
    return ArtworkImage(cgImage: image)
  }
}

private enum SyntheticArtworkRenderer {
  static func render(_ request: ArtworkRequest) async throws -> ArtworkImage {
    try Task.checkCancellation()

    let width = request.pixelWidth
    let height = request.pixelHeight
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw ArtworkPipelineError.renderingFailed
    }

    let palette = request.theme.palette
    guard
      let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [palette.start, palette.end] as CFArray,
        locations: [0, 1]
      )
    else {
      throw ArtworkPipelineError.renderingFailed
    }

    context.drawLinearGradient(
      gradient,
      start: CGPoint(x: 0, y: CGFloat(height)),
      end: CGPoint(x: CGFloat(width), y: 0),
      options: []
    )

    let unit = CGFloat(min(width, height))
    context.setFillColor(CGColor(gray: 1, alpha: 0.10))
    context.fillEllipse(
      in: CGRect(
        x: CGFloat(width) - unit * 0.68,
        y: CGFloat(height) - unit * 0.46,
        width: unit * 0.72,
        height: unit * 0.72
      )
    )

    context.setStrokeColor(CGColor(gray: 1, alpha: 0.17))
    context.setLineWidth(max(2, unit * 0.018))
    context.move(to: CGPoint(x: -unit * 0.1, y: unit * 0.22))
    context.addCurve(
      to: CGPoint(x: CGFloat(width) + unit * 0.1, y: CGFloat(height) * 0.62),
      control1: CGPoint(x: CGFloat(width) * 0.28, y: CGFloat(height) * 0.92),
      control2: CGPoint(x: CGFloat(width) * 0.7, y: -unit * 0.12)
    )
    context.strokePath()

    try Task.checkCancellation()
    guard let image = context.makeImage() else {
      throw ArtworkPipelineError.renderingFailed
    }
    return ArtworkImage(cgImage: image)
  }
}

extension ArtworkTheme {
  fileprivate var palette: (start: CGColor, end: CGColor) {
    switch self {
    case .aurora:
      return (rgb(0.18, 0.12, 0.48), rgb(0.12, 0.72, 0.76))
    case .ember:
      return (rgb(0.29, 0.035, 0.08), rgb(0.93, 0.34, 0.08))
    case .lagoon:
      return (rgb(0.015, 0.14, 0.25), rgb(0.04, 0.62, 0.62))
    case .meadow:
      return (rgb(0.025, 0.18, 0.11), rgb(0.24, 0.65, 0.28))
    case .midnight:
      return (rgb(0.018, 0.02, 0.09), rgb(0.35, 0.13, 0.58))
    case .solar:
      return (rgb(0.29, 0.1, 0.01), rgb(0.91, 0.62, 0.06))
    }
  }

  private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: 1)
  }
}
