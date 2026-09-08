# Monetization and Commercialization Strategy

## 1. Business objective

AEVYNO is being built as a sustainable commercial product, not only as a personal technical project.

The long-term goal is to generate lawful revenue from the quality of the software itself while preserving
the product boundary: AEVYNO is a media player/client for user-provided lawful sources. It does not sell
channels, copyrighted catalogs, provider credentials, piracy access or bundled IPTV subscriptions.

Commercial decisions must never weaken the non-negotiable product priorities:
1. design quality.
2. performance.
3. compatibility/reliability.
4. cross-device continuity.
5. maintainability.

## 2. Preferred revenue model

The preferred launch model is a premium freemium product:

- a useful free tier that allows users to understand the product quality before paying.
- AEVYNO Pro as the primary paid tier.
- annual subscription as the preferred recurring plan.
- monthly subscription may be offered for flexibility.
- an optional lifetime purchase may be offered if the economics remain sustainable.
- exact prices and feature gates are intentionally deferred until pre-launch validation.

No core browsing or playback experience should be funded by intrusive advertising.

## 3. Product principles for monetization

Monetization must feel native and respectful:

- no banner ads inside Home, library, player or core browsing flows.
- no interstitial ads that interrupt playback or navigation.
- no misleading countdowns, fake urgency or dark-pattern purchase flows.
- no hiding basic error recovery behind a paywall.
- restore-purchase and entitlement state must be reliable.
- paid state must work consistently across eligible Apple devices when the chosen StoreKit model supports it.
- a user should see the product's value before encountering a purchase decision where practical.
- the app must remain usable locally if a commerce service is temporarily unavailable, subject to entitlement rules.

## 4. Candidate Free vs Pro boundaries

The exact packaging remains a product decision, but the current working direction is:

### Free candidate
- core browsing and playback.
- a limited number of configured sources.
- basic search/library access.
- enough functionality to evaluate design, speed and compatibility.

### Pro candidate
Potential Pro value includes:
- multiple/unlimited sources.
- cross-device continuity and eligible iCloud-synchronized user state.
- advanced EPG and library features.
- richer personalization and quality-of-life features.
- advanced source/library management.
- future premium themes or visual personalization, only if they remain coherent with the design system.

Do not lock in these gates until retention, usage and App Store policy implications are reviewed.

## 5. Commerce implementation direction

Use Apple's native commerce stack.

Preferred implementation:
- StoreKit 2.
- a dedicated entitlement/service boundary independent of SwiftUI screens.
- StoreKit configuration/testing for deterministic local development.
- explicit restore and entitlement refresh behavior.
- localized purchase UI for English, German and Arabic.
- price/offer display sourced from StoreKit rather than hard-coded strings.
- no secrets or purchase-validation tokens in logs.

Before launch, verify the then-current App Store rules and subscription requirements. Do not rely on
outdated assumptions in this document.

## 6. Competitive positioning

AEVYNO should compete on product quality rather than content ownership.

Primary differentiation target:
- Apple TV-first experience.
- original visual identity.
- faster-feeling navigation and browsing.
- better focus behavior and spatial predictability.
- excellent Arabic RTL rather than translated-after-the-fact support.
- high reliability with large catalogs.
- privacy-conscious credential/catalog handling.
- cross-device Apple ecosystem continuity.

## 7. IPTVX quality reference

IPTVX may be used only as a competitive quality reference, never as a design specification.

The product goal is to exceed the perceived quality bar of IPTVX by a clear margin in the areas AEVYNO
controls, especially:
- visual polish and coherence.
- tvOS focus/navigation quality.
- perceived responsiveness.
- Arabic RTL quality.
- accessibility.
- large-catalog behavior.
- error/loading/empty-state quality.
- consistency between Apple TV and companion devices.

"Exceed" must be demonstrated through AEVYNO's own original design and measured/reviewed behavior.
It does not justify copying layouts, typography, assets, interaction details, proprietary text or
reverse-engineered implementation.

## 8. Commercial readiness gate

AEVYNO is not commercially ready until:
1. the core playback/source/library experience is stable.
2. physical Apple TV quality gates pass.
3. accessibility and localization are launch-ready.
4. privacy/security review passes.
5. StoreKit purchase/restore/entitlement flows are tested.
6. Free/Pro packaging and pricing are explicitly approved.
7. App Store policy and legal/content positioning are reviewed using current rules.
8. the purchase experience does not reduce the premium design quality of the product.

