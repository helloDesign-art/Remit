# Routes: delivering a domain through a provider

By default Remit delivers directly to the recipients' mail servers and signs
with the domain's DKIM key. Sometimes a domain should go out through someone
else instead: it already uses Google Workspace, it has reputation built up at
SES or Mailgun, or the host cannot open port 25 for that traffic. A **route**
does that per domain. Applications do not notice: they keep sending to Remit.

```bash
# Google Workspace SMTP relay, authenticated by IP (no password)
docker compose exec relay remit route set example.com smtp-relay.gmail.com:587

# A provider with credentials (the password is asked interactively)
docker compose exec relay remit route set example.com email-smtp.eu-west-1.amazonaws.com:587 AKIA...

# Back to direct delivery
docker compose exec relay remit route remove example.com

docker compose exec relay remit route list
```

What a route changes for that domain:

- Mail is handed to the provider with TLS **required**; credentials are never
  sent in clear.
- Remit stops adding its own DKIM signature, because the provider signs for
  you and a second signature that the provider may break helps nobody. Pass
  `--sign` to keep Remit's signature as well.
- The domain's SPF must include the provider (`include:_spf.google.com`,
  `include:amazonses.com`, ...). `remit domain dns <domain>` reminds you.

Sender ownership still applies: the login that sends as the domain must own it.

## Google Workspace

Use the **SMTP relay service**, not `smtp.gmail.com`: the latter rewrites the
From address to the authenticated account and has low limits.

In the Admin console: *Apps → Google Workspace → Gmail → Routing → SMTP relay
service → Add setting*:

- Allowed senders: **Only addresses in my domains**.
- Authentication: **Only accept mail from the specified IP addresses** → add
  your server's public IP.
- **Require TLS encryption**: on.

Then `remit route set <domain> smtp-relay.gmail.com:587`. Make sure DKIM is
turned on for the domain in *Gmail → Authenticate email*, and that the SPF
record contains `include:_spf.google.com`.

If you prefer account credentials instead of the IP allowlist, create an app
password for a Workspace user and run
`remit route set <domain> smtp-relay.gmail.com:587 user@example.com`.

## Amazon SES

Create SMTP credentials in the SES console and run
`remit route set <domain> email-smtp.<region>.amazonaws.com:587 <smtp-user>`.
Verify the domain in SES and publish the SPF/DKIM records SES gives you.

## Everything through one provider

To send *all* mail through an upstream relay (typical when the provider blocks
port 25), set `REMIT_RELAYHOST`, `REMIT_RELAY_USER` and `REMIT_RELAY_PASSWORD`
in `.env` instead. Routes still take precedence for their domains.

## Where routes are stored

`/var/lib/remit/routes/<domain>` (in the `state` volume), one `key=value` file
per domain, readable by root only. Passwords are stored in clear because
Postfix needs them to authenticate; protect the volume accordingly.
