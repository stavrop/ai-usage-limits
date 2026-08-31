# Changelog

All notable changes to AI Usage Limits are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-08-30

### Added
- **Sample data mode.** Every provider here is an account with another service,
  so there was no way to see what the app does without signing in to one first.
  A new demo fills the dashboard and both widgets with fixed, made-up figures —
  offered on the last onboarding page, from the empty dashboard, and as a toggle
  in Settings.
  - Nothing is fetched, nothing is written to the Keychain and nothing is written
    to the shared usage cache: the readings exist only in memory, so switching
    the demo off shows the real data exactly as it was left.
  - Labelled as sample data wherever it appears — a banner above the cards, a
    "Sample" marker in the widget footer, and a fictional account label.
  - Connecting a real provider turns it off automatically.
- Settings rows now track *stored credentials* rather than what is on screen, so
  the demo can never make a provider look signed in when it isn't.

### Fixed
- A provider whose session died mid-use kept its "Connected" checkmark in
  Settings until the next refresh, because only the displayed list was pruned.
- The sample account label could appear against a genuinely connected provider
  when the demo was switched on from Settings.
- Lock Screen and inline widgets showed sample figures with no marker at all —
  the "Sample" label lived only in the footer, which those families don't draw.
- Sample reset times are now anchored to each window's own cycle rather than to
  "now", so a countdown ticks down and rolls over instead of snapping back to
  the same value on every refresh.

## [1.0] - 2026-08-25

### Added
- Initial public release of the iOS app.
- **iPhone only.** The layout targets one-handed phone use and has never been
  tested on iPad, so claiming iPad support would ship an unverified surface.
- **Five providers**: Claude and ChatGPT (loopback OAuth), Grok (loopback OAuth),
  Cursor (browser approve + poll) and OpenRouter (API key). Only Claude and
  ChatGPT have been verified end to end; Grok and Cursor are implemented from
  public sources and remain untested.
- **Onboarding** that explains what the app does and how credentials are handled
  before asking for anything, and supports finishing with nothing connected.
- **Settings**: connect / reconnect / disconnect each provider, refresh cadence,
  alert threshold, and **Delete all data** — which clears every credential, cached
  reading and preference, then resets onboarding.
- **About**: version, support and feedback links, and a **Privacy & connections**
  screen listing the exact scopes each provider is asked for, read from the code
  so it cannot drift.
- **Two widgets**: *All Providers* (one bar each) and *Single Provider* (one
  provider in full detail), both with an "Updated HH:MM" footer that marks stale
  cached values.

### Security
- Claude sign-in requests **read-only scope**: `org:create_api_key user:profile`.
  The server does not grant the first, so the issued token carries `user:profile`
  alone and cannot send prompts or spend the user's allowance.
- Credentials are stored per provider in the Keychain, so one provider breaking or
  being disconnected never disturbs another.
- The OAuth loopback listener binds **127.0.0.1 only** and exists for the duration
  of a single sign-in.
