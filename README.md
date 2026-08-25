# AI Usage Limits

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey.svg)](#build)
[![Buy me a coffee](https://img.shields.io/badge/%E2%98%95-buy%20me%20a%20coffee-ffdd00.svg)](https://buymeacoffee.com/stavrop)

See how much of your **Claude**, **ChatGPT**, **Grok**, **Cursor** and
**OpenRouter** allowance you've used — and when each one resets — without opening
a single dashboard. iPhone app with configurable Home Screen and Lock Screen
widgets.

> **Unofficial — not affiliated with Anthropic, OpenAI, xAI, Anysphere or
> OpenRouter.** It reads **undocumented** usage endpoints and reuses the public
> OAuth clients that each provider's own CLI uses, so it may break at any time and
> could conflict with a provider's terms of service. Use it **at your own risk**.
> It authenticates only with *your own* logins and sends each token only to its own
> provider; nothing goes anywhere else.

## Why it exists

Every provider shows your remaining quota somewhere, and it's somewhere different
every time. This puts them on one screen and one widget.

There's also a macOS sibling — [**AI Usage
Monitor**](https://github.com/stavrop/ai-usage-monitor), a menu bar app for Claude
and ChatGPT. It works differently: it reads credentials your desktop CLIs already
wrote, while this app signs in itself, because a phone has no `~/.claude` to read.

## Privacy

**No server, no analytics, no account.** Credentials live in your device Keychain,
usage figures are cached on-device for the widget, and each token is sent only to
the provider it belongs to. **Settings → Delete all data** erases all of it.

See the [privacy policy](https://stavrop.github.io/ai-usage-limits/privacy.html)
([source](PRIVACY.md)) and [terms](https://stavrop.github.io/ai-usage-limits/terms.html),
and **About → Privacy & connections** in the app for the exact scopes each
provider is asked for.

## Providers

| Provider | Sign-in | Usage source | Confidence |
|---|---|---|---|
| **Claude** | Loopback OAuth (PKCE) | `api.anthropic.com/api/oauth/usage` | Verified |
| **ChatGPT** | Loopback OAuth (PKCE), port 1455 | `chatgpt.com/backend-api/wham/usage` | Verified |
| **Grok** | Loopback OAuth (PKCE) | `cli-chat-proxy.grok.com/v1/billing` | Untested |
| **Cursor** | Browser approve + poll | `cursor.com/api/usage-summary` | Untested |
| **OpenRouter** | API key | `openrouter.ai/api/v1/key` | Officially documented |

Only OpenRouter has a supported, documented API. The rest are reverse-engineered
from each provider's own CLI, and Cursor most speculatively of all. Issues and
fixes welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

Deliberately **not** included: Gemini, Mistral, DeepSeek and similar expose
per-key billing dashboards rather than subscription limits with reset windows, so
they'd render as an empty or misleading card. Antigravity is excluded because its
Google flow requires the broad `cloud-platform` scope — too much authority to ask
for in exchange for a usage percentage.

## How sign-in works

Two constraints shape it:

1. **Providers block sign-in inside embedded web views** (Claude's consent page is
   Arkose-gated and fingerprints the runtime). `ASWebAuthenticationSession` runs
   out of process in real Safari, which passes — and means the app never sees your
   password.
2. **The OAuth redirect is `http://localhost:<port>/…`**, and
   `ASWebAuthenticationSession` only auto-detects custom-scheme or universal-link
   callbacks — neither registrable against a public client id we don't own. So
   [`Shared/LoopbackServer.swift`](Shared/LoopbackServer.swift) binds a loopback
   port and serves the redirect itself, exactly as the CLIs do. It is bound to
   127.0.0.1 only and lives for one sign-in attempt.

### Scopes are kept minimal

Claude is asked for **`org:create_api_key user:profile`** and nothing else. The
server does not grant the first, so the issued token carries `user:profile` alone:
enough to read usage, **not** enough to send prompts or spend your allowance.

### Request details that are easy to get wrong

| Detail | Requirement |
|---|---|
| `state` | **32 bytes** (43 base64url chars). A 16-byte state makes Claude return "Invalid request format". |
| `org:create_api_key` | Must be **requested** for Claude or authorize fails — but it is never granted. |
| Refresh `scope` | Replay the **granted** scope from the token response, not the requested list, or 400 `invalid_scope`. |
| `anthropic-beta` | Send on the code exchange, **not** on refresh. |
| `User-Agent` | Required — some token hosts are Cloudflare-fronted and 403 unrecognised clients with `error code: 1010`. |
| Refresh token | **Rotates on every use** — persist the new one or the next refresh fails. |

Claude's access token lasts ~8h; the refresh chain lasts ~29 days and is
**absolute, not sliding**, so a full re-login is due roughly monthly.

## Widgets

| Widget | Shows |
|---|---|
| **All Providers** | every connected provider, one summary bar each |
| **Single Provider** | one provider in full detail — every bucket with reset times, plus credits |

Both show an "Updated HH:MM" footer that turns orange when cached values are being
shown, so a stale number is never mistaken for a live one. Families: small,
medium, large, and the accessory rectangular / inline / circular Lock Screen sizes.

The widget **never refreshes tokens** — app and widget share one Keychain item and
refresh tokens rotate on use, so both renewing would strand one with a dead token.

## Build

Requires **Xcode 26+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate
open AIUsageLimits.xcodeproj      # then ⌘R
```

Or from the command line:

```sh
xcodebuild build -project AIUsageLimits.xcodeproj -scheme AIUsageLimits \
  -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

`project.yml` is the source of truth; the `.xcodeproj` is committed so CI can build
without running XcodeGen first. Regenerate and commit it after editing
`project.yml`. **Change `DEVELOPMENT_TEAM` in `project.yml` to your own team** to
run on a device.

## Layout

```
App/
  AIUsageLimitsApp.swift, ContentView.swift, RootTabView.swift, UsageStore.swift
  Onboarding/   first-run flow
  Connect/      ASWebAuthenticationSession driver, connect row, API-key sheet
  Dashboard/    provider cards + bars
  Settings/     provider management, preferences, delete all data
  About/        links, support prompt, "Privacy & connections"
Shared/         compiled into both app and widget
  Constants.swift        app group / keychain ids + preferences
  LoopbackServer.swift   on-device 127.0.0.1 listener for OAuth redirects
  Providers/             the provider protocol, registry and implementations
Widget/         both widgets
```

Adding a provider means conforming to `UsageProvider` and adding a `ProviderID`
case — onboarding, Settings, the dashboard and the widgets all enumerate the
registry. Three auth styles are supported: `.oauth` (loopback PKCE),
`.browserPoll` (approve in the browser, then poll — Cursor has no redirect to
catch) and `.apiKey`.

## Support this project

It's free, has no ads, no tracking and no account — and it takes real time to keep
working, because these endpoints move without warning.

- ☕ **[Buy me a coffee](https://buymeacoffee.com/stavrop)** — the only way this
  project earns anything.
- ⭐ **[Star this repo](https://github.com/stavrop/ai-usage-limits)** — free, and
  it's how other people find it.
- 🐛 **[Report a bug or request a provider](https://github.com/stavrop/ai-usage-limits/issues)**
  — especially when a provider breaks. You'll usually notice before I do.

## License

[Apache License 2.0](LICENSE) © 2026 Georgios Stavropoulos. See also
[NOTICE](NOTICE). Apache-2.0 is chosen partly for its explicit trademark clause
(§6): the license grants no rights to any of the marks referenced by this project.
