# Contributing

Thanks for taking an interest.

## Ground rules

- **Never paste tokens, API keys or screenshots containing them** in an issue or
  PR. Nothing here needs a credential to reproduce.
- Keep scopes minimal. A usage monitor should never hold a token that can send
  prompts or spend someone's allowance. If a provider forces a broader scope than
  reading usage requires, say so in the PR and we'll weigh it.

## Adding a provider

A provider is viable here if it has **both**:

1. a sign-in that works on a phone — loopback OAuth, a browser-approve-and-poll
   flow, or a user-pasted API key; and
2. an endpoint reporting **usage or quota with a reset window**, not just a
   billing total.

Then conform to `UsageProvider` and add a `ProviderID` case. Nothing else needs
changing: onboarding, Settings, the dashboard and the widgets all enumerate the
registry.

Please note in the PR how you ground-truthed the endpoints and whether you tested
a real sign-in end to end — several providers here are implemented from public
sources and have never been connected for real, which is worth being honest about.

## Reporting a broken provider

These endpoints are undocumented and move. When one breaks, the useful details are
the provider, the app version (About tab), and the error text shown on the
provider's row — **with any tokens redacted**.
