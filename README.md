# Crash

An open-source, native iPhone and iPad app for sharing rooms, homes and camper vans with private networks of family and friends.

**Website and source download:** https://rooms.leobrown.co.uk

**Repository:** https://github.com/leo-brown/spare-room

**License:** MIT

## Run the iOS app

1. Download this repository and open `ios/Crash.xcodeproj` in Xcode on a Mac.
2. Select the **Crash** scheme and an iPhone simulator, then Run.
3. For a real iPhone, select your Apple development team under **Signing & Capabilities**. The default bundle ID is `uk.co.leobrown.crash`; change it if your team cannot register that ID.
4. Create an account, **save your recovery key**, and create or join a network.
5. Add a room, home or van under **My places**, upload photos, and add free/busy dates.
6. Enable notifications in **Networks → Settings** and enable Background App Refresh in iOS Settings.

The app connects to the live HTTPS API by default. Unsigned simulator builds keep their session in memory when simulator Keychain entitlements are unavailable; real devices require Keychain storage. There are no client API keys, third-party packages, or committed signing identities. Requires **iOS 17+** and Xcode with an iOS 17+ SDK. A source ZIP is not an installable IPA. Distribution through TestFlight or the App Store requires your Apple developer account and signing.

```sh
python3 ios/create_project.py
xcodebuild -project ios/Crash.xcodeproj -scheme Crash \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/crash-build CODE_SIGNING_ALLOWED=NO build
```

## Included

- Anyone can create several networks, join by a shared ten-character code, and switch between them.
- Network owners can replace codes, remove members, and delete a network; members can leave or mute it.
- Multiple listings per home/person, including rooms, whole homes and camper vans.
- Up to eight private photos per listing; iOS resizes/re-encodes images and removes source metadata.
- Street, city, postcode/ZIP, country and time zone, with no door-number field.
- Free and busy night ranges, a network month calendar, and place/date/guest searches.
- Requests with dates, guest count and a note; host acceptance/decline and guest/host cancellation.
- Accepted stays block availability. Transactional checks prevent double bookings and decline overlapping pending requests.
- iOS local notifications for newly free nights, including removal of busy blocks and cancelled accepted stays, plus private stay updates.
- Email/password login, device Keychain sessions, recovery keys, session revocation and account deletion.
- Credential-free public source, static source-download site, private runtime SQLite database and scheduled backups.

## Notification timing

The app requests iOS Background App Refresh no earlier than 15 minutes after scheduling and polls while open. **Apple decides when or whether to run a background check. This is not instant push and has no guaranteed delivery interval.** Low Power Mode, disabled Background App Refresh and force-quitting can prevent checks. Reopen the app to catch up. Muting a network suppresses its notifications. Events are paginated, scoped to current membership, and exclude your own changes and pre-join history.

No APNs key or push server is required. Reliable immediate alerts would require adding APNs and your Apple push credentials; that is a future improvement.

## Backend and tests

Python 3.11+ standard library only; SQLite persists accounts, photos, networks, availability and requests. Production runs behind Apache HTTPS under a dedicated unprivileged systemd user. No external DB provider or cloud account is needed.

```sh
ROOMS_DATABASE=/tmp/crash-dev/rooms.sqlite3 python3 backend/server.py --port 8791
python3 -m unittest discover -s tests -v
```

The tests use temporary databases and loopback HTTP. They never call production. CI builds iOS and runs the API tests. See [architecture](docs/architecture.md), [deployment](docs/deployment.md) and [verification](docs/verification.md).

## Privacy and scope

Listings and photos are visible only within the associated network. Guest identities and request notes are restricted to guest and host; accepted occupancy is visible to network members. Shared codes are invitations, so share them only with trusted people. Email is a login identifier: email ownership verification and email password resets are not provided. Save the recovery key.

The app keeps live network data in memory and requires connectivity for changes; there is no offline editing queue. Arrange exact addresses and arrival details through your usual private channels. No payments, public booking marketplace, chat, tracking, advertising or real family sample data are included. Source archives exclude runtime data and credentials.

## Native UI acceptance test

Start a separate local API, then run the shared scheme’s UI test on an iPhone simulator:

```sh
ROOMS_DATABASE=/tmp/crash-ui/rooms.sqlite3 python3 backend/server.py --port 8792
# In another terminal, from the repository:
xcodebuild -project ios/Crash.xcodeproj -scheme Crash \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

The test injects a **Debug-only localhost** endpoint and creates synthetic accounts in that local database. Regular launches and Release builds use the production HTTPS API. UI tests never create production records.
