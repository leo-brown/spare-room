# Verification

## Completed locally

- Unsigned iOS simulator build with Xcode 27.2, deployment target iOS 17.
- Twelve isolated HTTP acceptance tests using temporary SQLite databases: authentication and validation; recovery/session revocation/deletion; cross-network isolation and owner permissions; free/busy precedence; accurate newly-free events; double-booking prevention and overlapping-request decline; concurrent approvals; cancellation reopening; check-out exclusivity/date/capacity checks; private photos, vans and multiple rooms; code rotation/member removal/join baseline; network mute; event pagination beyond 100 entries.
- Native simulator UI acceptance passed: account creation, recovery-key acknowledgement, network creation, listing creation, Explore and Calendar navigation, using a separate local API and synthetic records.
- Real simulator first-screen and browser landing-page visual checks passed.
- Live read-only checks passed: HTTPS health and landing/source responses; unauthenticated private API returns 401; database URL returns 404; database integrity is OK; production users, networks, rooms, photos, periods and stays all contain zero records. Service, TLS and daily local backup timer are active. Production account-creation tests were not run.

## Required before a store release

- Signed physical-iPhone test of notification permission and actual Background App Refresh delivery. iOS does not promise a fixed interval; force-quit, Low Power Mode and disabled background refresh must be checked on-device.
- Full VoiceOver, larger Dynamic Type, dark-mode and iPad interaction review. Native controls provide the starting accessibility behavior, but a full audit has not been performed.
- Apple signing, archive/upload and App Store Connect privacy/release configuration. No App Store/TestFlight release is implied by source publication.
- User-owned off-site backup destination if needed. Existing automatic backups are local to the host.

The repository and production launch contain no family sample records. Test users use reserved `example.invalid` addresses and remain confined to temporary test databases. Any live smoke-test accounts must be deleted before handoff.
