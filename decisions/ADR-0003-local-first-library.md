# ADR-0003 — Local-First Media Catalog

Status: Accepted
Date: 2026-09-07

## Context

IPTV providers can expose tens of thousands of catalog items. Synchronizing the entire provider catalog through iCloud would increase latency, storage usage and complexity without clear user benefit.

## Decision

Treat provider catalog and EPG as local, rebuildable/cacheable data.

Use local persistence with indexed/batched queries. Synchronize only compact user state.

The exact local persistence implementation remains benchmark-driven and may be decided by a later ADR.

## Consequences

- fast local reads are possible.
- each device imports/refreshes provider data.
- CloudKit stays compact.
