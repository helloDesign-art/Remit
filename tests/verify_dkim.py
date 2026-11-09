# Verifies the DKIM signature of a message against a public key given on the
# command line (no DNS involved): python verify_dkim.py message.eml "v=DKIM1; ..."
import sys

import dkim

message = open(sys.argv[1], "rb").read()
public = sys.argv[2].encode()


def dns(name, timeout=5):
    return public


ok = dkim.verify(message, dnsfunc=dns)
print("DKIM valid:", ok)
sys.exit(0 if ok else 1)
