# Codex Usage Widget

A macOS desktop widget for the signed-in Codex CLI account. It shows the weekly allowance used and remaining, the time until reset, and the percentage you would have used by now at an even pace.

The racing-style split is target usage minus actual usage, in percentage points. A negative split means you are ahead of the target. A positive split means you are behind.

## Build and run

You need macOS 14 or later, Xcode 15 or later for the app, and the Codex CLI signed in with `codex login`.

1. Open `CodexUsageWidget.xcodeproj` in Xcode and select your Apple development team for both the app and widget targets. If needed, set a unique `CODEX_USAGE_BUNDLE_ID` at the project level. The widget bundle ID and shared App Group derive from those settings.
2. Run the **Codex Usage** scheme. In macOS, open **Edit Widgets** and add **Codex Usage**.
3. To hide the menu bar icon, open **Open Details…** from its menu and turn off **Show menu bar icon**. To turn it back on, open the running **Codex Usage** app from Finder to bring up Details.
4. Turn on **Launch at login** in Details to start the companion at sign-in. It starts without opening Details and uses your saved menu bar icon preference. If macOS requires approval, enable Codex Usage in **System Settings → General → Login Items & Extensions**.

The companion refreshes on launch and every 15 minutes while running, including when the icon is hidden. It calls the local Codex CLI for weekly rate-limit data and writes percentages and reset timestamps to a shared App Group. The desktop widget continues to display the last snapshot when the companion is closed.

For an unsigned build check:

```sh
xcodebuild -project CodexUsageWidget.xcodeproj -scheme 'Codex Usage' CODE_SIGNING_ALLOWED=NO build
```
