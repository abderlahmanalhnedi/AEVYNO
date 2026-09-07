# Localization, Arabic and RTL

## 1. Product languages

AEVYNO ships with these first-class interface languages from the localization foundation:

- English (`en`) — base development language.
- German (`de`).
- Arabic (`ar`) — first-class language with complete right-to-left support.

Additional languages may be added later without changing the localization architecture.

Provider-supplied channel, movie, series, episode, category and EPG text is content data and
may be in any language. The app must preserve that content rather than forcing it into one of
the interface languages.

## 2. Non-negotiable Arabic quality bar

Arabic support is a design requirement, not a translation-only task.

The Arabic interface must:

- use native RTL layout direction throughout tvOS and iOS/iPadOS.
- remain visually premium, calm and cinematic rather than appearing like a mirrored afterthought.
- preserve correct Arabic shaping, ligatures and glyph rendering.
- avoid clipped, overlapping, truncated or incorrectly aligned Arabic text.
- handle mixed Arabic/Latin metadata, numbers, times and provider names safely.
- preserve predictable tvOS focus movement and focus restoration in RTL.
- use semantic `leading` / `trailing` alignment and spacing rather than hard-coded left/right assumptions.
- mirror only directional UI symbols that should semantically mirror; do not blindly flip artwork,
  media imagery, logos or non-directional symbols.
- avoid manual string reversal, Unicode direction hacks and layout tricks that fight the platform.
- treat loading, empty, error, Detail, source setup, search, player and settings states as part of
  the same localization quality bar.

## 3. Apple-native localization implementation

Use Apple's native localization stack.

Preferred baseline:

- String Catalogs (`.xcstrings`) for app-owned user-facing strings.
- `String(localized:)`, localized resources and SwiftUI-native localized text APIs as appropriate.
- locale-aware `FormatStyle` APIs for dates, durations, counts, numbers and percentages.
- system semantic typography so Apple selects high-quality Arabic glyphs correctly.
- SwiftUI environment layout direction driven by the selected locale/system language.

Do not scatter raw user-facing strings through views when they should be localized.

Do not add a custom Arabic font merely for style. A bundled font requires explicit design,
legibility, shaping, licensing, binary-size and performance review. The default should remain
Apple system typography, including the platform's Arabic system font behavior.

## 4. Typography

Arabic typography must feel intentionally designed.

Rules:

- prefer Apple system fonts and semantic text styles.
- keep the same visual hierarchy across English, German and Arabic while allowing language-specific
  line height and wrapping.
- never force Arabic into Latin-tuned fixed heights that clip ascenders/descenders or diacritics.
- avoid excessive tracking/letter spacing for Arabic.
- do not rely on uppercase transformations for hierarchy.
- allow titles and metadata to wrap or truncate according to the component's documented behavior,
  with Arabic fixtures included in visual tests.
- test at TV viewing distance on physical Apple TV before declaring the Arabic tvOS experience complete.

## 5. Layout and focus

All reusable components must be localization-safe.

Use:

- semantic alignment.
- adaptive spacing.
- layout containers that can naturally reflow.
- stable card geometry where tvOS focus depends on spatial predictability.

Avoid:

- absolute left/right positioning for text or controls.
- offsets that only work in LTR.
- assumptions that the first actionable item always appears on the physical left.
- using string length as a proxy for layout size.

For tvOS, verify at least:

- initial focus in Arabic.
- left/right directional movement across Home rails.
- Home -> Detail -> Back focus restoration.
- Retry/error action focus.
- long Arabic titles and mixed Arabic/Latin metadata.
- Reduce Motion behavior under RTL.

## 6. Provider content and bidirectional text

Provider content is untrusted display data.

- preserve original provider strings.
- do not manually reverse Arabic.
- do not infer interface direction from provider content language.
- redact credential-bearing URLs as required by security rules even when mixed-direction text is present.
- prefer platform text rendering and Unicode bidirectional behavior.
- sanitize only for security/correctness reasons, not to reshape or reorder legitimate Arabic text.

## 7. Testing matrix

Localization changes require automated and visual coverage across:

| Surface | English | German | Arabic RTL |
| --- | --- | --- | --- |
| tvOS Home | required | required | required |
| tvOS Detail | required | required | required |
| loading/empty/error | required | required | required |
| focus restoration | required | required | required |
| iPhone/iPad shell | required | required | required |

Arabic test fixtures must include:

- short labels.
- long titles.
- Arabic with diacritics.
- Arabic mixed with Latin provider names.
- numeric metadata and durations.
- strings that expand beyond the English width.

Snapshots/screenshots alone do not prove focus behavior. tvOS UI tests and physical Apple TV review
remain required for milestone-critical RTL UX.

## 8. Definition of localization-ready

A screen is not localization-ready until:

1. all app-owned user-facing strings are localizable.
2. English, German and Arabic resources exist for its strings.
3. no obvious hard-coded LTR assumptions remain.
4. Arabic layout is reviewed in RTL.
5. accessibility labels are localized where applicable.
6. relevant automated tests pass.
7. physical Apple TV validation is recorded for milestone-critical tvOS screens.

