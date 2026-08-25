# Privacy Policy

**AI Usage Limits** (iOS) — last updated 2026-08-25

> Hosted version: <https://stavrop.github.io/ai-usage-limits/privacy.html>
> (This Markdown file is the source; run `python3 docs/build.py` after editing.)

**Short version: this app has no servers and collects nothing.** Everything happens
on your iPhone. The only services it talks to are the AI providers you choose to
connect, using your own login with each of them.

## Scope

This policy covers the **AI Usage Limits** iOS app (bundle id
`com.stavrop.ailimits`), distributed via the App Store and TestFlight, with source
at <https://github.com/stavrop/ai-usage-limits>.

It does **not** cover the separate macOS menu bar app, *AI Usage Monitor*, which
has [its own policy](https://stavrop.github.io/ai-usage-monitor/privacy.html).
The two apps work differently: the Mac app reads credentials your desktop CLIs
already wrote, while this app signs in itself.

## What the developer collects

**Nothing.** There is no server operated by the developer, no analytics, no
telemetry, no crash reporting, no advertising, no tracking and no account. The
developer never receives your credentials or your usage figures, and has no way
to.

## How signing in works

You sign in on **each provider's own web page**, opened in Apple's Safari through
`ASWebAuthenticationSession` — not in a web view inside this app. Your password is
typed into the provider, never into AI Usage Limits. The app receives only the
token the provider issues after you approve.

For providers that use an API key (OpenRouter), you paste a key you created in
that provider's dashboard.

**The approval screen names the provider's own command-line tool** — for example
"Claude Code" or "Codex" — rather than this app, because the app uses those same
public OAuth clients. This is also why the app is unofficial: the providers have
not published an API for reading your usage.

## What is stored, and where

- **Credentials** (OAuth tokens or API keys) are stored in your device's
  **Keychain**, in a group shared only between this app and its own widget.
- **The most recent usage figures** are cached in the app's own App Group
  container so the widget can render without a network call.
- **Preferences** (refresh interval, alert threshold) are stored the same way.

None of this leaves your device. There is no iCloud sync and no backup to the
developer.

## What is sent, and to whom

Each token is sent **only to the provider it belongs to**, and only to read your
usage:

| Provider | Hosts contacted |
|---|---|
| Claude | `claude.com`, `platform.claude.com`, `api.anthropic.com` |
| ChatGPT | `auth.openai.com`, `chatgpt.com` |
| Grok | `auth.x.ai`, `cli-chat-proxy.grok.com` |
| Cursor | `cursor.com`, `api2.cursor.sh` |
| OpenRouter | `openrouter.ai` |

There are no other network calls. The app never sends prompts, never runs code,
never changes your plan and never spends your allowance.

## Scopes

The app asks each provider for as little as it can. For Claude it requests
`org:create_api_key user:profile`; the provider does not grant the first, so the
resulting token carries `user:profile` only — enough to read usage, and not enough
to send prompts. Every provider's exact scopes are listed in the app under
**About → Privacy & connections**, read directly from the code so the screen
cannot disagree with what is actually requested.

## Deleting your data

**Settings → Delete all data** removes every stored credential, all cached usage
and all preferences from the device, and signs you out of every provider inside
the app. Deleting the app removes the same data. Because nothing was ever sent
anywhere else, that erases everything the app holds about you.

To revoke the app's access at the provider end, use that provider's own account
or security settings.

## Children

The app is not directed at children and collects no personal information from
anyone.

## Changes

Material changes will be noted in this file and in the repository's CHANGELOG.

## Contact

Open an issue at <https://github.com/stavrop/ai-usage-limits/issues>, or report a
security concern privately via
<https://github.com/stavrop/ai-usage-limits/security/advisories/new>.
