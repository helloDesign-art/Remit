# Deliverability

Mail from your own server lands in the inbox when the receiving side can
verify who you are. Three DNS records per domain and two facts about the
server do that.

## Per domain

### DKIM

`remit domain add <domain>` generates a 2048-bit RSA key and prints the record:

```
remit._domainkey.<domain>   TXT   v=DKIM1; k=rsa; s=email; p=MIIB...
```

Paste the whole value as one string. Receivers fetch it to verify the
signature Remit adds to every message from that domain.

To rotate keys, change `REMIT_DKIM_SELECTOR` (for example to `remit2`),
restart, run `remit domain add` again for each domain and publish the new
records; keep the old TXT records for a week so in-flight mail still verifies.

### SPF

One record, and only one, on the sending domain:

```
<domain>   TXT   v=spf1 ip4:<server ip> ~all
```

If the domain already sends through another service (Google Workspace,
Mailchimp...), add `ip4:<server ip>` to the existing record instead of
creating a second one. Two SPF records are a permanent error and every
receiver treats the domain as failing SPF.

Subdomains have their own SPF: if you send as `noreply@app.example.com`, the
record goes on `app.example.com`.

### DMARC

```
_dmarc.<domain>   TXT   v=DMARC1; p=none; rua=mailto:dmarc@<domain>
```

Start with `p=none` (monitor only). When the reports show that everything
legitimate passes, move to `p=quarantine` and eventually `p=reject`.
Subdomains inherit the parent's policy unless they publish their own.

`remit domain check <domain>` verifies all three records against what the
relay expects.

## Per server

### Hostname and reverse DNS

`REMIT_HOSTNAME` is the name the relay uses to introduce itself (HELO). It
needs an A record to the server's public IP (not proxied through a CDN).

The IP's reverse DNS (PTR) should point to a hostname that resolves back to
the same IP. Most providers let you set it in their panel. Gmail and Outlook
reject or junk mail from IPs with no reverse DNS. The PTR does not have to
equal `REMIT_HOSTNAME`, but matching is slightly better.

### Outbound port 25

Remit delivers directly to the recipients' mail servers on port 25. Many
cloud providers block it by default (ask them to open it, usually a form), and
some never do. In that case set `REMIT_RELAYHOST` to an upstream SMTP service;
Remit still signs with your DKIM keys.

### IP reputation

A fresh IP has no reputation. Keep volume steady, avoid bulk sends from day
one, and check the IP against the common blocklists (Spamhaus ZEN, SpamCop,
Barracuda). Transactional mail from a clean IP with correct DNS is accepted
by the big providers without a warm-up period.

## Testing

Send a message to a seed address and read the headers: look for
`dkim=pass`, `spf=pass` and `dmarc=pass` in `Authentication-Results`. Services
such as mail-tester.com give the same information with a score.
