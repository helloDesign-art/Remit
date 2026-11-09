# Connecting a project

Each application is a **project**: a login and the list of domains it may
send from.

## 1. Create the project

```bash
docker compose exec relay remit project add myapp app.example.com
```

Several domains: `remit project add myapp example.com,app.example.com`.

This registers any domain that is new (generating its DKIM key and printing
the DNS records to publish) and prints the SMTP password once. Store it in the
application's secrets.

## 2. Point the application at the relay

The relay is published on Docker's `host-gateway` address. In the
application's Compose file:

```yaml
services:
  app:
    extra_hosts:
      - "remit:host-gateway"
```

and in its configuration:

| Setting | Value |
| --- | --- |
| host | `remit` |
| port | `587` |
| encryption | none (`secure: false`, no STARTTLS) unless `REMIT_SUBMISSION_TLS=may` |
| user | `myapp` |
| password | from step 1 |
| from | any address at an assigned domain |

The application and the relay do not share a Docker network; the connection
goes through the host, so the relay sees each project as a separate client
and applies limits per project.

### Nodemailer

```js
const transport = nodemailer.createTransport({
	host: "remit",
	port: 587,
	secure: false,
	auth: { user: "myapp", pass: process.env.SMTP_PASSWORD },
});
```

### Python

```python
import smtplib
with smtplib.SMTP("remit", 587) as s:
    s.login("myapp", password)
    s.sendmail("noreply@app.example.com", [to], message.as_bytes())
```

## What is enforced

- The envelope sender must be at one of the login's domains, otherwise
  `553 Sender address rejected: not owned by user`.
- The recipient domain must exist.
- Per-client limits: `REMIT_CLIENT_RATE_LIMIT` messages per minute, 20
  concurrent connections, 50 recipients per message, `REMIT_MESSAGE_SIZE_MB`.

## Changing the domain

```bash
docker compose exec relay remit project domain add myapp new-example.com
```

Publish the DNS records it prints and check them with
`remit project show myapp`. Switch the application's From address to
`@new-example.com`; nothing else changes on its side. When the old domain is
no longer used:

```bash
docker compose exec relay remit project domain remove myapp app.example.com
```

## Rotating or removing

```bash
docker compose exec relay remit project passwd myapp   # new password
docker compose exec relay remit project remove myapp
```
