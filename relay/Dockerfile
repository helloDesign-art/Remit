# Remit relay — Postfix (send-only) + OpenDKIM + SASL auth
#
# One small image. Postfix delivers, OpenDKIM signs, Cyrus SASL authenticates
# the projects that are allowed to send. Everything that changes at runtime
# (domains, DKIM keys, senders, passwords) lives in /var/lib/remit, which is a
# volume, so the image stays stateless and upgradable.

FROM alpine:3.20

RUN apk add --no-cache \
        postfix \
        cyrus-sasl cyrus-sasl-login \
        opendkim opendkim-utils \
        bash tini openssl ca-certificates bind-tools \
    && mkdir -p /var/lib/remit /run/opendkim /etc/sasl2 \
    && chown opendkim:opendkim /run/opendkim

COPY postfix/main.cf        /etc/postfix/main.cf
COPY postfix/master.cf      /etc/postfix/master.cf
COPY postfix/header_checks  /etc/postfix/header_checks
COPY opendkim/opendkim.conf /etc/opendkim/opendkim.conf
COPY sasl/smtpd.conf        /etc/sasl2/smtpd.conf
COPY remit                  /usr/local/bin/remit
COPY entrypoint.sh          /entrypoint.sh

RUN chmod 755 /usr/local/bin/remit /entrypoint.sh \
    && chmod 644 /etc/postfix/main.cf /etc/postfix/master.cf /etc/postfix/header_checks \
    && newaliases

VOLUME ["/var/lib/remit"]

# Submission port for authenticated clients. Nothing listens on 25.
EXPOSE 587

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD remit health

ENTRYPOINT ["/sbin/tini", "-s", "--", "/entrypoint.sh"]
