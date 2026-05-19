# Privacy Policy

**App:** OpenEmu-Silicon
**Last updated:** May 17, 2026
**Contact:** [Open an issue](https://github.com/nickybmon/OpenEmu-Silicon/issues)

---

## What this app does

OpenEmu-Silicon is a macOS game emulator. Most gameplay and library features run locally on your computer.

The app only connects to external services for optional features you choose to use, or for optional crash reporting if you consent:

- **RetroAchievements** — optional achievements, leaderboards, and Rich Presence.
- **Google Drive Save Sync** — optional save-state and battery-save backup/sync.
- **Sentry crash reporting** — optional crash and hang diagnostics.

OpenEmu-Silicon does not operate its own account server, telemetry backend, or analytics service.

---

## RetroAchievements (optional)

RetroAchievements support lets you earn achievements, submit leaderboard scores, and show Rich Presence for supported games. It is off unless you sign in from **Preferences → Achievements**.

### What is sent to RetroAchievements

When RetroAchievements is enabled, OpenEmu-Silicon uses the rcheevos client library to communicate with RetroAchievements. Depending on the game and session, this may send:

- Your RetroAchievements login/token request.
- Game hashes and game-identification requests.
- Achievement unlock submissions.
- Leaderboard start/update/submit data.
- Rich Presence updates.
- Client and system information such as the OpenEmu-Silicon User-Agent, macOS version, and rcheevos version.

### What is stored locally

After sign-in, the RetroAchievements token is stored locally in OpenEmu-Silicon's encrypted credential file at `~/Library/Application Support/OpenEmu/.oe_credentials`. The app may also store local preferences such as whether hardcore mode is enabled.

Your RetroAchievements password is not stored by OpenEmu-Silicon.

### Data controlled by RetroAchievements

RetroAchievements is an external service. OpenEmu-Silicon does not operate RetroAchievements servers and does not control RetroAchievements-side retention, account deletion, or profile data. For RetroAchievements account/privacy questions, refer to RetroAchievements directly.

---

## Google Drive Save Sync (optional)

This feature lets you back up and sync your save states and battery saves to your own Google Drive. It is off by default and only activates after you sign in.

### What access is requested

OpenEmu-Silicon requests the `drive.appdata` scope. This gives the app access to a private, hidden App Data folder inside your Google Drive. This folder:

- Is not visible in the Google Drive web interface
- Cannot be read by other apps
- Can only be accessed by OpenEmu-Silicon

The app does **not** request access to your files, documents, photos, or any other part of your Google Drive.

### What is stored in your Drive

Only your game save data:

- Save state files (snapshots of game progress)
- Battery save files (in-game save data)

No personal information, no device identifiers, no usage metrics.

### How authentication works

Sign-in uses Google's standard OAuth 2.0 flow. Your Google account password is never seen or stored by the app. After you authorize access, Google issues an OAuth token. That token is stored locally in OpenEmu-Silicon's encrypted credential file at `~/Library/Application Support/OpenEmu/.oe_credentials` and is used only to read and write your save data to the App Data folder.

### Revoking access

You can disconnect Google Drive at any time from **Preferences → Cloud Sync → Sign Out**. This clears the stored Google Drive token from OpenEmu-Silicon's local credential store. You can also revoke access from your Google Account at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

---

## Sentry crash reporting (optional)

OpenEmu-Silicon can send crash, hang, and performance diagnostic reports to Sentry. This is optional and consent-gated. On first launch, the app asks whether you want to send crash reports.

If you opt in, reports may include:

- App version and build number.
- macOS/device diagnostic information.
- Stack traces, crash details, hangs, and performance traces.
- Breadcrumbs and structured logs related to app behavior.
- Active game title, system identifier, and core identifier at the time of a crash.

Crash reports do **not** intentionally include:

- Game ROM files.
- Save state files.
- Battery save files.
- Passwords.

Sentry events are sent to Sentry's hosted service. The current project configuration uses Sentry's US ingest endpoint (`ingest.us.sentry.io`). OpenEmu-Silicon does not operate Sentry's servers.

You can decline crash reporting when prompted. If you previously opted in and want to stop future reports, open an issue for help resetting the local crash-reporting preference while a user-facing toggle is being added.

---

## What this app does not do

- Does not sell your data.
- Does not include ads.
- Does not include in-app purchases or subscriptions.
- Does not operate its own analytics backend.
- Does not transmit game ROMs to this project.
- Does not transmit save data to this project.
- Does not access your Google Drive files outside the hidden App Data folder.

---

## Open source

The full source code is available at [github.com/nickybmon/OpenEmu-Silicon](https://github.com/nickybmon/OpenEmu-Silicon). You can inspect exactly what data is read, written, and transmitted.

---

## Changes to this policy

If the app adds new network features that affect privacy, this document will be updated and the "Last updated" date above will change. Significant changes will be noted in the release notes.

---

## Contact

Questions or concerns? [Open an issue](https://github.com/nickybmon/OpenEmu-Silicon/issues) on GitHub.
