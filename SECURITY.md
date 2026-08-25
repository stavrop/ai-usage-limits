# Security Policy

## Reporting a vulnerability

Please report security issues privately using GitHub's
[**Report a vulnerability**](https://github.com/stavrop/ai-usage-limits/security/advisories/new)
(Security → Advisories). Please do **not** open a public issue for a vulnerability
until it has been addressed.

Reports are acknowledged on a best-effort basis — this is a hobby project, not a
commercial product.

## What this app touches

- It performs an OAuth sign-in on each provider's own site (in Safari, via
  `ASWebAuthenticationSession`) or accepts an API key you paste, and stores the
  resulting credential in the device **Keychain**, in an access group shared only
  with its own widget.
- It sends each credential **only** to that provider's hosts, and only to read
  usage. It never sends prompts, runs code, or spends your allowance.
- It has no server, no analytics and no third-party network calls.

## Trust & scope notes

- The bundled OAuth client ids are the **public** client ids used by each
  provider's own command-line tool. They are not secrets, but it does mean the
  approval screen names that tool rather than this app.
- Scopes are kept minimal. For Claude the issued token carries `user:profile`
  only, which cannot send prompts or spend the allowance. See
  **About → Privacy & connections** in the app for the full list.
- The usage endpoints are **undocumented** and may change or break without
  notice. This project is unofficial and unaffiliated.

## Loopback listener

Completing an OAuth sign-in requires catching a `http://localhost` redirect, so
the app briefly binds a local port (`Shared/LoopbackServer.swift`). It is bound to
**127.0.0.1 only**, so it is unreachable from the network, and it exists only for
the duration of a single sign-in attempt.
