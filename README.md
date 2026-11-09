# Remit

**Your own transactional email service, on your own server.**

Remit is a self-hosted relay for the emails your applications send: sign-ups,
password resets, invoices, invitations. It runs on the machine you already pay
for, signs every message with DKIM, and lets each of your projects send only
from the domains you assign to it. No per-email pricing, no third-party
provider between you and your users.

> Status: **v0.1 — the relay**. This release is the sending engine: Postfix,
> DKIM, per-project credentials and a small CLI. The HTTP API (compatible with
> Resend's), the dashboard and bounce handling come next; see
> [ROADMAP.md](ROADMAP.md).

## Why

Open-source alternatives to Resend exist, but most still hand the actual
sending to Amazon SES. Full mail servers (Postfix+Dovecot stacks, Mailcow,
Postal) do send on their own, but they are built for mailboxes, not for
applications, and they are heavy. Remit sits in between: it only sends, it is
one small container, and it is designed to host several isolated projects on
one server.

## What you get today

- **Send-only Postfix** tuned for transactional mail. Nothing listens on port
  25; there is no inbound mail, no mailboxes, no open relay.
- **DKIM for every domain** you register, with a one-command setup that prints
  the exact DNS records to add (DKIM, SPF, DMARC) and a checker that tells you
  whether they are live.
- **One login per project.** Credentials are created with the CLI and each
  login can only send from the domains assigned to it. A project cannot
  impersonate another, even on the same server.
- **Private by default.** The relay binds to Docker's `host-gateway` address,
  which every container on the host can reach and the internet cannot. Your
  applications connect to host `remit`, port 587, with their login.
- **Abuse limits** per client (messages per minute, connections, recipients
  per message, message size), all tunable.
- **Clean headers.** The `Received:` line that would expose your internal
  container addresses is removed.
- **Routes per domain.** A domain can leave through a provider instead
  (Google Workspace, SES, Mailgun...) while applications keep talking to Remit;
  TLS is required and the provider's signature is used. Or send everything
  through one upstream relay when the host blocks port 25.

## Quick start

Requirements: Docker with Compose, a server that can open outbound port 25
(or an upstream SMTP relay), and a hostname with an A record pointing to the
server (for example `smtp.example.com`).

```bash
git clone https://github.com/helloDesign-art/Remit.git
cd Remit
cp .env.example .env         # set REMIT_HOSTNAME and REMIT_PUBLIC_IP
docker compose up -d --build

# Register a sending domain. This creates its DKIM key and prints the DNS records.
docker compose exec relay remit domain add example.com

# Create credentials for an application and allow it to send as @example.com.
docker compose exec relay remit sender add myapp example.com

# Once DNS has propagated:
docker compose exec relay remit domain check example.com
```

Then, in the application's Compose file:

```yaml
services:
  app:
    extra_hosts:
      - "remit:host-gateway"
    environment:
      SMTP_HOST: remit
      SMTP_PORT: 587
      SMTP_USER: myapp
      SMTP_PASSWORD: <printed by `remit sender add`>
```

Any SMTP library works (Nodemailer, smtplib, PHPMailer, JavaMail...). Use
plain SMTP with AUTH (`secure: false`, no STARTTLS) unless you enabled
`REMIT_SUBMISSION_TLS`.

## CLI

```
remit domain add <domain>         register a domain, create its DKIM key, print DNS records
remit domain dns <domain>         print the DNS records again
remit domain check <domain>       verify DKIM / SPF / DMARC as published
remit domain list
remit domain remove <domain>

remit sender add <login> <domain>[,<domain>...]   create SMTP credentials
remit sender passwd <login>       rotate a password
remit sender list
remit sender remove <login>

remit route set <domain> <host>[:port] [<user>] [--sign]   deliver a domain through a provider
remit route remove <domain>       deliver it directly again
remit route list

remit test <from> <to>            send a signed test message
remit status                      queue, domains, senders
remit render                      rebuild tables from state (normally automatic)
```

Everything the CLI changes lives in the `state` volume (`/var/lib/remit`):
domains, DKIM keys, logins and their hashed passwords. Back it up; the image
itself is stateless.

## Deliverability checklist

Sending from your own IP is not harder than sending through a provider, but
the DNS has to be right. For every domain:

1. **DKIM** — the `TXT` record `remit domain add` prints.
2. **SPF** — a single `v=spf1 ... ip4:<your ip> ~all` record. Two SPF records
   on one domain make SPF fail for everything.
3. **DMARC** — `_dmarc.<domain>` with at least `v=DMARC1; p=none;`.

And once for the server:

4. **A record** for `REMIT_HOSTNAME` → your public IP, not proxied.
5. **Reverse DNS (PTR)** of your IP → a hostname that resolves back to it.
   Set it in your provider's panel. The hostname does not have to be
   `REMIT_HOSTNAME`, but it must exist.
6. **Outbound port 25** open, or `REMIT_RELAYHOST` configured.

`remit domain check <domain>` verifies 1–3. See [docs/deliverability.md](docs/deliverability.md),
[docs/connecting-a-project.md](docs/connecting-a-project.md) and [docs/routes.md](docs/routes.md).

## Configuration

All settings are environment variables; see [`.env.example`](.env.example).

| Variable | Default | Purpose |
| --- | --- | --- |
| `REMIT_HOSTNAME` | required | FQDN announced to other servers; must resolve to this host |
| `REMIT_PUBLIC_IP` | — | Used to print SPF records |
| `REMIT_BIND_ADDR` / `REMIT_PORT` | `172.17.0.1` / `587` | Where the submission port is published |
| `REMIT_DKIM_SELECTOR` | `remit` | DKIM selector (change to rotate keys) |
| `REMIT_SUBMISSION_TLS` | `none` | `may` offers STARTTLS with a self-signed cert |
| `REMIT_MESSAGE_SIZE_MB` | `25` | Maximum message size |
| `REMIT_CLIENT_RATE_LIMIT` | `300` | Messages per minute per client address |
| `REMIT_RELAYHOST` (+ `_USER`, `_PASSWORD`) | — | Send through an upstream SMTP relay |

## Security model

- Clients must authenticate; there is no network-based trust.
- A login may only use sender addresses in its assigned domains
  (`reject_sender_login_mismatch`). Unknown domains are rejected.
- Recipient domains must exist in DNS.
- Messages are signed only when OpenDKIM is running; if it is down they are
  deferred, never sent unsigned.
- The relay is not reachable from the internet in the default configuration.
  If you bind it to a public address, enable TLS and firewall the port.
- Passwords are stored hashed in a `sasldb`; Remit never shows them again.
- Credentials for upstream providers are only ever sent over TLS; without it
  the mail is deferred, not sent in clear.

Report security issues privately to the maintainers (see
[SECURITY.md](SECURITY.md)).

## Project layout

```
relay/          the relay image: Postfix, OpenDKIM, SASL, entrypoint and the `remit` CLI
compose.yml     one-service deployment
docs/           deliverability and integration notes
```

## License

To be announced with the first public release.
