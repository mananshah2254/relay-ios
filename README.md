# Relay — iPhone referral outreach

A native iOS app with a Share Extension, saved referral templates, Hunter contact discovery, optional PDF resumes, and Gmail sending. **Relay is a working development name.**

The Xcode project is [iOS/Relay.xcodeproj](iOS/Relay.xcodeproj). The dependency-free email service is in [server/](server/). The shared Swift logic is a local package, so the iOS project does not need third-party Swift packages.

## What this build includes

- Native Jobs, Outreach, Templates, and Settings screens, plus an explicit sample-data demo.
- Manual job entry with only a role and company; job links and descriptions are optional.
- URL/text sharing with role-and-company confirmation, persistent imports in an App Group, and background upload handoff.
- Gmail connection through Google's browser OAuth flow; Hunter key setup.
- A saved subject/body, sender name, contact limit, recipient preferences, minimum spacing, daily cap, and review/automatic modes.
- PDF import and one attachment version per prepared outreach campaign.
- Individual message previews, approval, cancellation, and account queue controls.
- Server adapters for Hunter and Gmail, Hunter Domain Finder for exact company-to-domain matching, plus supported Greenhouse and Lever job metadata.
- Encrypted persistent backend state, duplicate prevention, and conservative handling of uncertain sends.

### Current limits

This is an initial implementation, not an App Store-approved release. Full Xcode is now installed and the Swift package/tests and project metadata have been checked; run a clean app build and the physical LinkedIn share test in your Xcode environment before distribution.

**A shared LinkedIn URL is reference material, not a data source.** Relay asks the user to confirm the role and company in the Share Extension or quick-add screen. A manual job needs no URL. It does not scrape LinkedIn or claim access to its job database. The company website is optional: Hunter Domain Finder suggests a matching domain, which the user must confirm before contact lookup (including automatic mode). Greenhouse/Lever metadata can still fill missing fields; a host's company slug is not treated as a verified employer domain.

The app needs a reachable backend, a Hunter account/key, and your configured Google OAuth project for live outreach. Demo mode uses clearly labeled sample data and makes no provider calls. Replies remain in Gmail; the app does not read the inbox. “Submitted” is an API outcome, not a delivery or reply measurement.

The first backend runs one process with encrypted files on a persistent disk. It is appropriate for development and a controlled pilot. It is not a multi-replica production service, and device sessions do not yet have account recovery or cross-device login.

## Start the backend

Requires Node.js 22 or newer. No `npm install` is needed.

```sh
cd server
npm run setup
npm test
npm start
```

Setup creates a private `.env` with a new storage-encryption key and does not overwrite an existing file. Preserve that key alongside a secure backup of the encrypted data. See [server/README.md](server/README.md) for all configuration and operational details.

Run `npm --prefix server run preflight` from the project root to check the local setup
without displaying secrets. A prepared single-VM phone pilot is in
[server/deploy](server/deploy/README.md); it has not been provisioned or deployed.

For an iOS Simulator, use `http://localhost:8787` in Relay's service settings. For your physical iPhone, deploy the service behind HTTPS and use its reachable HTTPS origin. `localhost` on the iPhone means the phone, not your Mac. The app accepts cleartext HTTP only for loopback development.

### Connect Gmail

In your Google Cloud project:

1. Enable the Gmail API and configure the OAuth consent screen.
2. Create a **Web application** OAuth client for the backend browser flow.
3. Register exactly `https://YOUR_SERVICE/v1/google/callback` as its redirect URI. Google permits a localhost callback for local development.
4. Set `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `PUBLIC_BASE_URL` in the backend environment. Keep the client secret off the phone and out of source control.
5. While your OAuth app is in testing, add your Gmail address as a test user.
6. In Relay, connect the service and choose **Connect Gmail**. Grant the requested email-sending permission.

The backend uses `openid`, `email`, and `gmail.send`. Google redirects to the server, which returns to the app via `relayreferrals://oauth/complete`; that return URL contains no access or refresh token. Test-mode OAuth grants may expire and require reconnection. Public availability requires the applicable Google verification.

### Connect Hunter and prepare a test

Enter the Hunter key inside Relay, set your sender name, save the template, and optionally import your PDF. Keep review mode enabled for your initial tests. Set the server's `TEST_RECIPIENT_ALLOWLIST` to designated test inboxes before testing live credentials; contacts outside it will not be sent mail. No real outreach is sent by the automated test suite.

Automatic mode is available after explicit configuration. When job information, account setup, or recipients are insufficient, the app stops that campaign with an explanation. The configured contact limit (5 by default) is a maximum, not a promise that that many matching people are available.

## Open on your iPhone

1. Install full **Xcode**, open it once, and install its iOS platform support.
2. Open `iOS/Relay.xcodeproj` and select the **Relay** scheme.
3. Set your Apple signing team and unique bundle identifiers. The configuration template is [iOS/Config/Local.xcconfig.example](iOS/Config/Local.xcconfig.example); create the ignored `Local.xcconfig` beside it with your values.
4. Enable the same **App Group** and **Keychain Sharing** group for both Relay and RelayShare. The group IDs in the configuration and provisioning must agree.
5. Connect the iPhone, trust the development Mac, enable Developer Mode if requested, select the phone as the run destination, and run.
6. Open Relay once to connect its service and set preferences. In LinkedIn, share a job, open the system **Share via…** sheet, and choose Relay. You may need **More** to enable or favorite it.

Apple supports personal on-device development signing with limitations. For the complete App Group/share-extension configuration and App Store distribution, plan to use an Apple Developer Program team. Installation and App Store review are separate steps. [Apple device-running guidance](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [membership comparison](https://developer.apple.com/support/compare-memberships/).

## Verify or regenerate

```sh
# From the repository root:
swift test --disable-sandbox
npm --prefix server test
node scripts/generate-xcode-project.mjs

# With full Xcode selected:
xcodebuild -project iOS/Relay.xcodeproj -scheme Relay \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The Swift package tests pass with the full Xcode toolchain. If command-line
`xcodebuild` is blocked by local CoreSimulator or SwiftPM permissions, open the
project in Xcode and build from the IDE; the project and package reference are
already generated.

The project generator discovers Swift files in `iOS/Relay`, `iOS/ShareExtension`, and the explicitly shared files. Rerun it after adding native Swift source files. The generated project is checked into the source tree; XcodeGen is not required.

The development icon is generated from vector paths using `scripts/generate-placeholder-icon.swift` and should be replaced when the name and branding are finalized.

## Before public release

The unresolved product dependency is permission and reliable coverage for LinkedIn-only job enrichment. The separate distribution dependency is Apple's treatment of third-party contact discovery under guideline 5.1.1(viii), as well as Google's review of the actual email workflow. Neither a Hunter key nor successful tests prove those approvals. See [BUILD_PLAN.md](BUILD_PLAN.md).

Complete on-device testing, Google verification, App Store review materials, and an operator-specific privacy policy. The included privacy manifest records the data categories and required-reason APIs in this implementation; review it against the final hosted service and final behavior before submission. Add production enrollment/account recovery, operational limits, monitoring, and backup/recovery procedures before opening the service broadly.

Further detail: [production release path](docs/PRODUCTION_RELEASE.md), [API contract](docs/API.md), [device test checklist](docs/DEVICE_TESTS.md), [data handling](docs/DATA_HANDLING.md).
