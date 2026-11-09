#!/bin/bash
# Remit relay entrypoint: apply the environment to Postfix, render the state
# tables, then supervise OpenDKIM and Postfix.
set -euo pipefail

STATE=/var/lib/remit
log() { printf 'remit: %s\n' "$*"; }

[ -n "${REMIT_HOSTNAME:-}" ] || { log "REMIT_HOSTNAME is required (the FQDN this relay announces; it must resolve to this server)"; exit 1; }

# --- Postfix settings from the environment ----------------------------------
postconf -e "myhostname = ${REMIT_HOSTNAME}"
postconf -e "message_size_limit = $(( ${REMIT_MESSAGE_SIZE_MB:-25} * 1024 * 1024 ))"
postconf -e "smtpd_client_message_rate_limit = ${REMIT_CLIENT_RATE_LIMIT:-300}"
postconf -e "smtpd_client_recipient_rate_limit = $(( ${REMIT_CLIENT_RATE_LIMIT:-300} * 5 ))"

# Render the tables first so the realm file exists before SASL settings.
remit render no-reload
postconf -e "smtpd_sasl_local_domain = $(cat "$STATE/realm")"

# Optional STARTTLS on the submission port with a self-signed certificate.
# Off by default: on a single host the traffic never leaves the machine, and a
# self-signed certificate breaks clients that verify certificates.
if [ "${REMIT_SUBMISSION_TLS:-none}" = "may" ]; then
	mkdir -p "$STATE/tls"
	if [ ! -f "$STATE/tls/key.pem" ]; then
		openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
			-subj "/CN=${REMIT_HOSTNAME}" \
			-keyout "$STATE/tls/key.pem" -out "$STATE/tls/cert.pem" >/dev/null 2>&1
		chmod 600 "$STATE/tls/key.pem"
	fi
	postconf -e "smtpd_tls_security_level = may" \
	           "smtpd_tls_cert_file = $STATE/tls/cert.pem" \
	           "smtpd_tls_key_file = $STATE/tls/key.pem" \
	           "smtpd_tls_protocols = >=TLSv1.2" \
	           "smtpd_tls_auth_only = no"
else
	postconf -e "smtpd_tls_security_level = none"
fi

# Optional upstream relay for everything, for hosts whose provider blocks
# outbound port 25. Its credentials and TLS policy are written by `remit render`
# together with the per-domain routes.
if [ -n "${REMIT_RELAYHOST:-}" ]; then
	postconf -e "relayhost = ${REMIT_RELAYHOST}"
	log "relaying everything through ${REMIT_RELAYHOST}"
else
	postconf -e "relayhost ="
fi

# Spool ownership can be lost when the volume is recreated.
postfix set-permissions >/dev/null 2>&1 || true
postfix check

# --- Supervise --------------------------------------------------------------
OPENDKIM_PID=""
POSTFIX_PID=""
STOPPING=0

start_opendkim() {
	/usr/sbin/opendkim -f -x /etc/opendkim/opendkim.conf &
	OPENDKIM_PID=$!
}

shutdown() {
	STOPPING=1
	log "stopping"
	postfix stop >/dev/null 2>&1 || true
	[ -n "$OPENDKIM_PID" ] && kill "$OPENDKIM_PID" 2>/dev/null || true
	wait 2>/dev/null || true
	exit 0
}
trap shutdown TERM INT

# OpenDKIM only logs through syslog: forward it to the container's stdout.
syslogd -n -O /proc/1/fd/1 &
start_opendkim
sleep 1
postfix start-fg &
POSTFIX_PID=$!

log "relay up as ${REMIT_HOSTNAME} ($(grep -c . "$STATE/domains" || true) domains, $(grep -c . "$STATE/senders" || true) senders)"

# OpenDKIM is restarted if it ever exits (`remit render` reloads it with
# SIGUSR1, so in normal operation it never does). If Postfix exits, the
# container exits and Docker restarts it.
while true; do
	wait -n "$OPENDKIM_PID" "$POSTFIX_PID" 2>/dev/null || true
	[ "$STOPPING" = 1 ] && exit 0
	if ! kill -0 "$POSTFIX_PID" 2>/dev/null; then
		log "postfix exited"
		[ -n "$OPENDKIM_PID" ] && kill "$OPENDKIM_PID" 2>/dev/null || true
		exit 1
	fi
	if ! kill -0 "$OPENDKIM_PID" 2>/dev/null; then
		log "opendkim restarting"
		sleep 0.5
		start_opendkim
	fi
done
