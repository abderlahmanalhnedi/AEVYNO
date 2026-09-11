import CoreGraphics
import DesignSystem
import Domain
import Foundation
import Testing

@Test("Artwork requests clamp target dimensions")
func artworkRequestClampsTargetDimensions() {
  let request = ArtworkRequest(
    itemID: MediaItem.ID(rawValue: "sizing"),
    theme: .aurora,
    kind: .movie,
    pixelWidth: 9_000,
    pixelHeight: 0
  )

  #expect(request.pixelWidth == 2_048)
  #expect(request.pixelHeight == 1)
}

@Test("Production artwork requests retain only real remote artwork identity")
func productionArtworkRequestDoesNotFabricateSyntheticPresentation() throws {
  let url = try #require(
    URL(string: "https://images.example.invalid/poster.jpg?opaque=private"))
  let request = ArtworkRequest(
    catalogItemID: "stable-catalog-id",
    artworkURL: url,
    pixelWidth: 9_000,
    pixelHeight: 0
  )

  #expect(request.itemID.rawValue == "stable-catalog-id")
  #expect(request.remoteURL == url)
  #expect(request.theme == nil)
  #expect(request.kind == nil)
  #expect(request.pixelWidth == 2_048)
  #expect(request.pixelHeight == 1)
}

@Test("Artwork cache defaults to exactly 48 MiB")
func artworkCacheUsesExpectedDefaultBound() async {
  let metrics = await ArtworkImagePipeline().metrics()

  #expect(metrics.maximumCostInBytes == 48 * 1_024 * 1_024)
  #expect(metrics.costInBytes == 0)
  #expect(metrics.itemCount == 0)
}

@Test("Artwork cache never exceeds its memory cost bound")
func artworkCacheIsBounded() async throws {
  let pipeline = ArtworkImagePipeline(maximumCostInBytes: 3_500)

  for index in 0..<3 {
    _ = try await pipeline.image(
      for: ArtworkRequest(
        itemID: MediaItem.ID(rawValue: "cache-\(index)"),
        theme: .lagoon,
        kind: .movie,
        pixelWidth: 20,
        pixelHeight: 20
      )
    )
  }

  let metrics = await pipeline.metrics()
  #expect(metrics.costInBytes <= metrics.maximumCostInBytes)
  #expect(metrics.itemCount > 0)
  #expect(metrics.itemCount < 3)
}

@Test("Artwork cache updates recency and accounts for duplicate keys once")
func artworkCacheUsesLRUEviction() async throws {
  let image = try makeArtworkImage(width: 10, height: 10)
  let renderCounts = RenderCounts()
  let pipeline = ArtworkImagePipeline(maximumCostInBytes: image.costInBytes * 2) { request in
    await renderCounts.record(request)
    return image
  }
  let first = request(id: "lru-first")
  let second = request(id: "lru-second")
  let third = request(id: "lru-third")

  _ = try await pipeline.image(for: first)
  _ = try await pipeline.image(for: second)
  _ = try await pipeline.image(for: first)
  _ = try await pipeline.image(for: third)
  _ = try await pipeline.image(for: second)

  let metrics = await pipeline.metrics()
  #expect(metrics.itemCount == 2)
  #expect(metrics.costInBytes == image.costInBytes * 2)
  #expect(await renderCounts.count(for: first) == 1)
  #expect(await renderCounts.count(for: second) == 2)
  #expect(await renderCounts.count(for: third) == 1)
}

@Test("Artwork larger than the cache bound is returned but never cached")
func oversizedArtworkIsNotCached() async throws {
  let image = try makeArtworkImage(width: 10, height: 10)
  let renderCounts = RenderCounts()
  let artworkRequest = request(id: "oversized")
  let pipeline = ArtworkImagePipeline(maximumCostInBytes: image.costInBytes - 1) { request in
    await renderCounts.record(request)
    return image
  }

  _ = try await pipeline.image(for: artworkRequest)
  _ = try await pipeline.image(for: artworkRequest)

  let metrics = await pipeline.metrics()
  #expect(metrics.itemCount == 0)
  #expect(metrics.costInBytes == 0)
  #expect(await renderCounts.count(for: artworkRequest) == 2)
}

@Test("Cancelled artwork work is not inserted into the cache")
func cancelledArtworkIsNotCached() async {
  let sourcePipeline = ArtworkImagePipeline()
  let pipeline = ArtworkImagePipeline(maximumCostInBytes: 1_000_000) { request in
    try await Task.sleep(for: .seconds(5))
    return try await sourcePipeline.image(for: request)
  }
  let request = ArtworkRequest(
    itemID: MediaItem.ID(rawValue: "cancelled"),
    theme: .ember,
    kind: .series,
    pixelWidth: 100,
    pixelHeight: 100
  )

  let task = Task { try await pipeline.image(for: request) }
  await Task.yield()
  task.cancel()

  do {
    _ = try await task.value
    Issue.record("Expected artwork work to be cancelled")
  } catch is CancellationError {
    // Expected structured cancellation path.
  } catch {
    Issue.record("Unexpected artwork error: \(error)")
  }

  #expect(await pipeline.metrics().itemCount == 0)
}

@Test("Cache purge clears entries and prevents in-flight work from repopulating it")
func artworkCachePurgeInvalidatesInFlightInsertion() async throws {
  let image = try makeArtworkImage(width: 10, height: 10)
  let gate = RenderGate()
  let artworkRequest = request(id: "purged-in-flight")
  let pipeline = ArtworkImagePipeline(maximumCostInBytes: image.costInBytes * 2) { _ in
    await gate.waitForRelease()
    return image
  }

  let task = Task { try await pipeline.image(for: artworkRequest) }
  await gate.waitUntilStarted()
  await pipeline.removeAll()
  await gate.release()
  _ = try await task.value

  let metrics = await pipeline.metrics()
  #expect(metrics.itemCount == 0)
  #expect(metrics.costInBytes == 0)
}

@Test("Malformed artwork data fails without entering the cache")
func malformedArtworkDataIsRejected() async {
  let pipeline = ArtworkImagePipeline { _ in Data("not an image".utf8) }

  do {
    _ = try await pipeline.image(for: request(id: "malformed"))
    Issue.record("Expected malformed artwork data to fail")
  } catch let error as ArtworkPipelineError {
    #expect(error == .dataUnavailable || error == .decodingFailed)
  } catch {
    Issue.record("Unexpected artwork error: \(error)")
  }

  #expect(await pipeline.metrics().itemCount == 0)
}

private func request(id: String) -> ArtworkRequest {
  ArtworkRequest(
    itemID: MediaItem.ID(rawValue: id),
    theme: .aurora,
    kind: .movie,
    pixelWidth: 10,
    pixelHeight: 10
  )
}

private func makeArtworkImage(width: Int, height: Int) throws -> ArtworkImage {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let context = try #require(
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  )
  return ArtworkImage(cgImage: try #require(context.makeImage()))
}

private actor RenderCounts {
  private var counts: [ArtworkRequest: Int] = [:]

  func record(_ request: ArtworkRequest) {
    counts[request, default: 0] += 1
  }

  func count(for request: ArtworkRequest) -> Int {
    counts[request, default: 0]
  }
}

private actor RenderGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var hasStarted = false

  func waitForRelease() async {
    hasStarted = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while !hasStarted {
      await Task.yield()
    }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}
