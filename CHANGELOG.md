# Changelog

All notable changes to AI Usage Limits are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
