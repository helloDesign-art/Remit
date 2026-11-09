#!/bin/bash
# Integration test for the relay. Builds the image, starts a throwaway relay
# (project "remit-test", port 2587), a mail sink that receives what the relay
# delivers, and a client on a separate Docker network that behaves like a
# project. Checks access rules, DKIM signing, header privacy and the TLS
# requirement for routed domains. Cleans up after itself.
#
#   bash tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=remit-test
PORT="${TEST_PORT:-2587}"
SINK=remit-test-sink
SINK_NAME=sink.test.example          # where direct delivery lands
PROVIDER_NAME=provider.test.example  # the same sink under another name, used as a "provider" that offers no TLS
CLIENT_NET=remit-test-client
PY=python:3.12-alpine

export REMIT_HOSTNAME=smtp.test.example
export REMIT_PUBLIC_IP=203.0.113.10
export REMIT_PORT="$PORT"

compose() { docker compose -p "$PROJECT" -f compose.yml -f tests/compose.test.yml "$@"; }
relay()   { compose exec -T relay "$@"; }

TMP="$(mktemp -d)"
FAILED=0
step() { printf '\n== %s\n' "$*"; }
check() { # description command...
	local desc="$1"; shift
	if "$@"; then printf '[PASS] %s\n' "$desc"; else printf '[FAIL] %s\n' "$desc"; FAILED=1; fi
}

cleanup() {
	step "cleanup"
	compose down -v --remove-orphans >/dev/null 2>&1 || true
	docker rm -f "$SINK" >/dev/null 2>&1 || true
	docker network rm "$CLIENT_NET" >/dev/null 2>&1 || true
	rm -rf "$TMP"
}
trap cleanup EXIT

step "build and start the relay on 172.17.0.1:$PORT"
compose up -d --build --wait --wait-timeout 120
compose ps --format '{{.Name}} {{.Status}}'

step "start the mail sink and point direct delivery at it"
docker run -d --name "$SINK" --network "${PROJECT}_default" \
	--network-alias "$SINK_NAME" --network-alias "$PROVIDER_NAME" \
	-v "$PWD/tests/sink.py:/sink.py:ro" "$PY" python -u /sink.py >/dev/null
relay sh -c "postconf -e 'relayhost = [$SINK_NAME]:25' && postfix reload" >/dev/null 2>&1

step "create two projects and route the second one through a provider without TLS"
ALPHA_PASS="$(relay remit project add alpha a.test.example | awk '/^ *password/{print $2}')"
BETA_PASS="$(relay remit project add beta b.test.example | awk '/^ *password/{print $2}')"
[ "${#ALPHA_PASS}" -eq 32 ] && [ "${#BETA_PASS}" -eq 32 ] || { echo "could not read passwords"; exit 1; }
relay remit route set b.test.example "$PROVIDER_NAME:25"
relay remit project list

step "run the client from another network"
docker network create "$CLIENT_NET" >/dev/null
docker run --rm --network "$CLIENT_NET" --add-host remit:host-gateway \
	-e RELAY_PORT="$PORT" -e ALPHA_PASS="$ALPHA_PASS" -e BETA_PASS="$BETA_PASS" \
	-v "$PWD/tests/client.py:/client.py:ro" "$PY" python -u /client.py || FAILED=1

step "inspect what reached the sink"
sleep 6
docker logs "$SINK" 2>&1 | awk '
	/MESSAGE BEGIN/ { buf=""; on=1; next }
	/MESSAGE END/   { on=0; n++; last=buf }
	on              { buf=buf $0 "\r\n" }
	END             { printf "%s", last > "/dev/stderr"; print n }
' 2>"$TMP/msg.eml" >"$TMP/count"
COUNT="$(cat "$TMP/count")"
check "exactly one message was delivered (the routed one must not be)" [ "$COUNT" = "1" ]
check "message carries a DKIM signature for a.test.example" grep -q "^DKIM-Signature:.*d=a.test.example" "$TMP/msg.eml"
check "client's Received header was stripped" bash -c "! grep -q '^Received:.*test-client' '$TMP/msg.eml'"

step "verify the DKIM signature with the relay's public key"
PUB="$(relay sh -c 'grep -o "\"[^\"]*\"" /var/lib/remit/keys/a.test.example/remit.txt | tr -d "\"\n"')"
check "signature verifies" docker run --rm -v "$TMP:/t:ro" -v "$PWD/tests/verify_dkim.py:/v.py:ro" "$PY" \
	sh -c "pip install -q dkimpy >/dev/null 2>&1 && python /v.py /t/msg.eml '$PUB'"

step "routed domain: deferred because the provider offered no TLS"
LOGS="$(compose logs relay 2>&1)"
QUEUE="$(relay postqueue -p 2>&1)"
check "relay refused to deliver without TLS" grep -q 'TLS is required, but was not offered' <<<"$LOGS"
check "routed message is still queued, not sent" grep -q 'b.test.example' <<<"$QUEUE"

step "result"
if [ "$FAILED" = 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; exit 1; fi
