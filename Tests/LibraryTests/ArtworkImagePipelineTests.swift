import DesignSystem
import Domain
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
