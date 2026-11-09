# Behaves like a project talking to the relay and checks the access rules.
# Configuration comes from the environment (see tests/run.sh).
import email.utils
import os
import smtplib
import sys

HOST = os.environ.get("RELAY_HOST", "remit")
PORT = int(os.environ.get("RELAY_PORT", "587"))
ALPHA_PASS = os.environ["ALPHA_PASS"]
BETA_PASS = os.environ["BETA_PASS"]
RCPT = os.environ.get("RCPT", "someone@gmail.com")
DIRECT = "a.test.example"   # delivered directly (to the sink via relayhost)
ROUTED = "b.test.example"   # routed through a "provider" that offers no TLS


def attempt(label, user=None, password=None, mail_from=None, expect_ok=True):
    try:
        s = smtplib.SMTP(HOST, PORT, timeout=20)
        s.ehlo("test-client")
        if user:
            s.login(user, password)
        msg = (
            f"From: Test <{mail_from}>\r\nTo: <{RCPT}>\r\nSubject: {label}\r\n"
            f"Date: {email.utils.formatdate()}\r\nMessage-ID: {email.utils.make_msgid()}\r\n"
            f"\r\nbody for {label}\r\n"
        )
        s.sendmail(mail_from, [RCPT], msg)
        s.quit()
        result = "ACCEPTED"
    except Exception as e:  # noqa: BLE001 - any failure is a rejection for this test
        result = f"REJECTED {type(e).__name__}: {str(e)[:100]}"
    ok = result.startswith("ACCEPTED") == expect_ok
    print(f"[{'PASS' if ok else 'FAIL'}] {label}: {result}", flush=True)
    return ok


results = [
    attempt("no credentials", mail_from=f"noreply@{DIRECT}", expect_ok=False),
    attempt("wrong password", "alpha", "nope", f"noreply@{DIRECT}", expect_ok=False),
    attempt("alpha sends from its own domain", "alpha", ALPHA_PASS, f"noreply@{DIRECT}", expect_ok=True),
    attempt("alpha sends from beta's domain", "alpha", ALPHA_PASS, f"noreply@{ROUTED}", expect_ok=False),
    attempt("beta sends from an unregistered domain", "beta", BETA_PASS, "x@gmail.com", expect_ok=False),
    attempt("beta sends from its routed domain (accepted, must not leave without TLS)",
            "beta", BETA_PASS, f"noreply@{ROUTED}", expect_ok=True),
]
sys.exit(0 if all(results) else 1)
