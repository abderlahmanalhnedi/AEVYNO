# Design System and tvOS UX Rules

## 1. Design goal

The app should feel like a premium Apple TV application, not a ported phone interface and not a generic IPTV utility.

The visual language must be original. Inspiration may come from Apple TV, Netflix and high-quality media apps, but copying proprietary screens/assets is prohibited.

## 2. Principles

- Content first.
- Calm hierarchy.
- Large legible typography.
- Strong but tasteful focus feedback.
- Minimal persistent chrome.
- predictable navigation.
- motion that explains spatial relationships.
- graceful empty/loading/error states.

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

## 6. Typography

Prefer system typography and platform semantics. Avoid hard-coded tiny text.

Use a small token set:
- hero/title.
- section title.
- card title.
- metadata.
- caption/status.

## 7. Spacing

Use spacing tokens; do not invent arbitrary values in each screen.

Suggested token names:
- `xxs`, `xs`, `sm`, `md`, `lg`, `xl`, `xxl`.

Exact values may be tuned after real-device review.

## 8. Motion

Use motion sparingly and purposefully.

Respect Reduce Motion where applicable.

Avoid long chained animations that slow interaction.

Never block remote input while decorative animation completes.

## 9. Images/posters

- use placeholders immediately.
- load asynchronously.
- cache with bounds.
- cancel work for abandoned cells/items.
- avoid decoding giant source images when a smaller display size is enough.
- preserve aspect ratio.

## 10. Loading

Prefer stable skeleton/placeholders over global spinners for catalog screens.

Loading must not steal focus.

Cached content should remain visible while refresh happens when safe.

## 11. Error UX

Examples:
- Provider unavailable -> Retry / Use cached library.
- Credentials invalid -> Edit source.
- Stream unsupported -> Show useful message and diagnostics ID, not raw codec dumps.
- iCloud unavailable -> Continue locally and show non-blocking sync status.

## 12. iPhone/iPad adaptation

Share visual tokens and domain behavior, not the exact tvOS layout.

Touch UI may use:
- tab/sidebar navigation as appropriate.
- sheets.
- context menus.
- drag/scroll patterns that are inappropriate on tvOS.

## 13. Accessibility

Support platform accessibility semantics from the beginning:
- meaningful labels.
- focus order.
- sufficient contrast.
- VoiceOver labels for progress and playback controls.
- avoid conveying state by color alone.
- large text/dynamic type where platform behavior applies.
