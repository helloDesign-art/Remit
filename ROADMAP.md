# Roadmap

Each stage is usable on its own. Nothing here is a promise of dates.

## v0.1 — The relay  ✅

- Send-only Postfix, DKIM per domain, SASL login per project, sender
  ownership enforcement, abuse limits, private binding, `remit` CLI.
- Routes: deliver a domain through an external provider (Google Workspace,
  SES...) with TLS required, or everything through one upstream relay.
- `remit doctor`: server-level checks (hostname, reverse DNS, outbound port
  25, blocklists) and `remit domain check` for the DNS of each domain.

## v0.2 — API

- `POST /emails`, `POST /emails/batch`, `GET /emails/:id` with the same
  request and response shapes as Resend, so the official SDKs work by changing
  the base URL.
- API keys per project, scoped to domains; rate limits per key.
- Idempotency keys; queued delivery with retries (Redis); delivery status
  parsed from Postfix.
- Postgres as the source of truth for domains, keys and SMTP logins
  (Postfix reads them through `pgsql:` maps; the CLI becomes a thin client).

## v0.3 — Dashboard

- Domains: add, verify DNS live (a "verify" button per record), rotate DKIM keys.
- DNS automation: with a Cloudflare API token, `remit project add` publishes
  the records itself; other providers behind the same interface later.
- Projects and API keys / SMTP credentials.
- Message log with status, headers and rendered preview.
- Simple, fast UI; dark and light; no build step heavier than the API itself.

## v0.4 — Feedback loop

- Bounce and complaint capture on a dedicated `bounces.` subdomain (VERP).
- Suppression lists per project; automatic handling of hard bounces.
- Webhooks: `email.sent`, `email.delivered`, `email.bounced`,
  `email.complained`.
- DMARC aggregate report intake.

## Later

- Templates with variables; attachments via API; scheduled sends.
- Multiple sending IPs and warm-up schedules.
- Metrics endpoint (Prometheus) and alerting on queue growth.
