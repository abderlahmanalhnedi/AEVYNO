# Design System and tvOS UX Rules

## 1. Design goal

The app should feel like a premium Apple TV application, not a ported phone interface and not a generic IPTV utility.

The visual language must be original. Inspiration may come from Apple TV, Netflix, IPTVX and other
high-quality media apps, but copying proprietary screens/assets is prohibited.

The explicit competitive goal is not merely to match IPTVX. AEVYNO should exceed its perceived
quality bar by a clear margin in the areas under our control: visual polish, compositional coherence,
focus behavior, motion restraint, responsiveness, Arabic RTL, accessibility, loading/error states
and consistency across Apple devices. This is a quality target, not permission to imitate its UI.

## 2. Principles

- Content first.
- Calm hierarchy.
- Large legible typography.
- Strong but tasteful focus feedback.
- Minimal persistent chrome.
- predictable navigation.
- motion that explains spatial relationships.
- graceful empty/loading/error states.
- every screen should look intentionally designed rather than framework-default or utility-like.
- polish must survive English, German and Arabic RTL, not only the base locale.
- visual novelty is valuable only when navigation remains obvious and fast.

## 3. tvOS focus

Every interactive card/button must define:
- normal state.
- focused state.
- pressed/selected state when applicable.
- disabled state.

Focused state should communicate selection without excessive scaling or glow.

Do not let focus disappear during async updates.

When returning from Detail to a rail/grid, restore the previous item when feasible.

Avoid moving layouts while the user is navigating.

## 4. Home information architecture

Initial structure:
- Continue Watching.
- Recently/available content as product evolves.
- Movies.
- Series.
- Live TV.
- Favorites.

Do not show empty rails unless they convey useful onboarding.

## 5. Card families

Define reusable card families instead of one-off screens:
- poster card.
- landscape hero/card.
- live channel card.
- episode card.
- Continue Watching card with progress.

Cards must not fetch business data themselves.

## 6. Localization and RTL design

AEVYNO supports English, German and Arabic as first-class interface languages.

Arabic is a design constraint from the beginning:

- use native RTL layout direction.
- use semantic leading/trailing alignment rather than physical left/right assumptions.
- preserve predictable focus geometry and restoration on tvOS.
- do not manually reverse strings or force mirrored layouts with custom hacks.
- mirror only directional controls that should semantically mirror.
- test mixed Arabic/Latin metadata and long Arabic titles.
- loading, empty, error and Detail states must be equally polished in RTL.

Read `docs/LOCALIZATION.md`.

## 7. Typography

Prefer system typography and platform semantics. Avoid hard-coded tiny text.

Use Apple system typography for Arabic by default so shaping and glyph selection remain native and
high quality. Do not add a custom Arabic font without a documented design/licensing/performance
review. Avoid Latin-oriented tracking and fixed text heights that can damage Arabic rendering.

Use a small token set:
- hero/title.
- section title.
- card title.
- metadata.
- caption/status.

## 8. Spacing

Use spacing tokens; do not invent arbitrary values in each screen.

Suggested token names:
- `xxs`, `xs`, `sm`, `md`, `lg`, `xl`, `xxl`.

Exact values may be tuned after real-device review.

## 9. Motion

Use motion sparingly and purposefully.

Respect Reduce Motion where applicable.

Avoid long chained animations that slow interaction.

Never block remote input while decorative animation completes.

## 10. Images/posters

- use placeholders immediately.
- load asynchronously.
- cache with bounds.
- cancel work for abandoned cells/items.
- avoid decoding giant source images when a smaller display size is enough.
- preserve aspect ratio.

## 11. Loading

Prefer stable skeleton/placeholders over global spinners for catalog screens.

Loading must not steal focus.

Cached content should remain visible while refresh happens when safe.

## 12. Error UX

Examples:
- Provider unavailable -> Retry / Use cached library.
- Credentials invalid -> Edit source.
- Stream unsupported -> Show useful message and diagnostics ID, not raw codec dumps.
- iCloud unavailable -> Continue locally and show non-blocking sync status.

## 13. iPhone/iPad adaptation

Share visual tokens and domain behavior, not the exact tvOS layout.

Touch UI may use:
- tab/sidebar navigation as appropriate.
- sheets.
- context menus.
- drag/scroll patterns that are inappropriate on tvOS.

## 14. Competitive design review

For milestone-critical screens, perform an explicit design review that asks:

- does this feel unmistakably like AEVYNO rather than a clone of another IPTV app?
- is the hierarchy more refined and less utility-like than common IPTV clients?
- is tvOS focus clearer and more predictable?
- is the interface at least as polished in Arabic RTL as in English?
- are loading, empty and error states premium rather than afterthoughts?
- does the experience remain fast and calm under large-catalog stress?
- are motion, spacing, typography and artwork treatment coherent as one system?

IPTVX may be included in internal competitive review only as a quality benchmark. Never reproduce
its exact screen composition, visual tokens or proprietary assets.

## 15. Accessibility

Support platform accessibility semantics from the beginning:
- meaningful labels.
- focus order.
- sufficient contrast.
- VoiceOver labels for progress and playback controls.
- avoid conveying state by color alone.
- large text/dynamic type where platform behavior applies.
