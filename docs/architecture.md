# Architecture

`ios/Crash/` contains a SwiftUI iOS 17+ app with no package dependencies. `Store.swift` owns HTTPS requests, authentication, a memory-only snapshot, local notifications and background event polling. Keychain stores bearer and recovery secrets with `AfterFirstUnlockThisDeviceOnly` protection. Unsigned simulator builds without Keychain entitlements retain the session only in process memory; real devices refuse login when secure storage fails. UserDefaults stores notification preference and a per-account event cursor. Photos are prepared with the iOS system photo picker and re-encoded as JPEG before upload. There is no location permission or precise GPS lookup.

`backend/server.py` provides a JSON API using Python's standard library and SQLite. `backend/schema.sql` initializes an empty database; it contains no seed accounts. Runtime state is at `/var/lib/spare-room/`, outside all source and public directories. The public server binds only to loopback behind Apache TLS. Passwords use salted PBKDF2-SHA256 with 600,000 iterations; sessions and recovery keys are stored as SHA-256 hashes. Sessions last 180 days. Recovery revokes existing sessions. Auth and network-join attempts are rate-limited.

## Isolation

A room belongs to one network. List it separately if you want it in another network. Every room/photo/date/stay operation checks current membership. Only a host changes their listing and dates. The host and requesting guest see stay notes and identities. Other members receive only occupancy dates. Network owners can revoke joining codes and remove members. Removing members or leaving deletes their listings and guest requests in that network. Owners cannot leave, and account deletion requires deleting any owned networks with remaining members first.

## Calendar model

All ranges are date-only and half open: `[check-in, check-out)`. A night is free when a free period covers it and no busy period or accepted stay covers it. Unoffered dates are unavailable. Dates are interpreted in the listing's IANA time zone. Search and request must cover every selected night. A room can have overlapping free/busy ranges; removing one free range does not imply another is removed. Deleting or adding blocks compares the effective free set, so duplicate free blocks do not generate duplicate notifications.

Mutations acquire `BEGIN IMMEDIATE` before checking availability. Acceptance atomically rechecks all nights, books the stay, and declines overlapping pending requests. Accepted stays must be cancelled before hosts add conflicting busy ranges. Busy blocks and bookings override free periods. Cancellation can produce newly free nights and a corresponding network event. Dates on the iPhone use civil dates rather than UTC-converted midnight to avoid date shifts.

## API

All private endpoints require `Authorization: Bearer <session>`. Bodies are JSON; dates are `YYYY-MM-DD`. Responses use snake_case; the iOS decoder converts keys. Errors are `{ "error": "human-readable message" }` with HTTP status 400, 401, 403, 404, 409, 413, 429 or 500.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/health` | Public health |
| POST | `/api/signup`, `/api/login`, `/api/recover` | Account/session; signup returns recovery_key once |
| POST | `/api/logout` | Revoke current session |
| DELETE | `/api/account` | Delete account; requires password |
| GET | `/api/snapshot` | Current user, networks, members, rooms, periods, private stays, occupancy and photo IDs |
| GET | `/api/events?after=N` | Up to 100 eligible events and a continuation cursor |
| POST | `/api/networks` | Create network |
| POST | `/api/networks/join` | Join with code |
| POST | `/api/networks/ID/rotate` | Owner replaces code |
| POST | `/api/networks/ID/mute` | Set notification mute |
| POST | `/api/networks/ID/leave` | Leave network |
| DELETE | `/api/networks/ID/members/USER` | Owner removes member |
| DELETE | `/api/networks/ID` | Owner deletes network |
| POST | `/api/rooms` | Create listing |
| PATCH / DELETE | `/api/rooms/ID` | Host edits/deletes listing |
| POST | `/api/rooms/ID/periods` | Host adds free/busy range |
| DELETE | `/api/periods/ID` | Host removes range |
| POST | `/api/rooms/ID/photos` | Host uploads base64 JPEG, up to 1 MB, maximum 8 |
| GET / DELETE | `/api/photos/ID` | Private image retrieval / host deletion |
| POST | `/api/stays` | Request stay |
| POST | `/api/stays/ID` | Set accepted, declined or cancelled status |

## Notifications

The server stores durable per-network events. Requests/status events have a private recipient; availability events go to all current unmuted members except the actor. Joining records an event watermark to suppress history. Pagination advances only past returned events until the final page; this prevents dropped alerts beyond a single batch. The iPhone persists its cursor after scheduling the fetched notifications. The first sign-in establishes a current baseline. Event IDs provide notification deduplication on a device.

iOS background scheduling is opportunistic. There is no APNs integration, no remote token registration and no claim of immediate delivery. The app also refreshes on foregrounding and while active. A failed sync leaves the in-memory view and displays an error; edits are not queued offline.
