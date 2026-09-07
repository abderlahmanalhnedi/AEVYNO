# Security and Privacy

## 1. Threat model

Sensitive data includes:
- IPTV/provider username.
- password.
- API/token values.
- credential-bearing URLs.
- possibly viewing history depending on user expectations.

## 2. Secret storage

Use Keychain for secrets.

Never store plaintext secrets in:
- UserDefaults.
- plist committed to repo.
- CloudKit records.
- local catalog database fields unless encrypted by a reviewed design.
- logs.
- crash breadcrumbs.

## 3. Logging

Create redaction helpers early.

Never log:
- full source URL containing credentials/query tokens.
- raw playlist lines containing credentials.
- passwords/tokens.

Use correlation IDs and normalized error categories instead.

## 4. Repository hygiene

- no production credentials.
- no personal provider URLs.
- no copyrighted playlist dumps.
- `.gitignore` local secret files.
- sample configs use `example.invalid` or synthetic values.

## 5. Network transport

Prefer TLS/HTTPS.

Do not globally disable ATS.

Any compatibility relaxation must be narrowly scoped and ADR-reviewed.

## 6. Cloud privacy

Use CloudKit private database for private synchronized state.

The app should clearly distinguish local-only operation when iCloud is unavailable.

## 7. Content/legal boundary

No bundled channels/movies/series.

No DRM circumvention.

No scraping protected catalogs.

No credential harvesting or sharing.

No feature whose primary purpose is unauthorized access to paid content.

## 8. Analytics

Do not add third-party analytics SDKs by default.

If analytics is later desired, create an ADR covering privacy, data minimization, opt-in/consent as applicable, and performance impact.
