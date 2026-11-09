# Security policy

Remit sends email on your behalf; a flaw in it can turn a server into a spam
source. We take reports seriously.

**Please do not open public issues for vulnerabilities.** Email
`security@hellodesign.art` with a description, steps to reproduce and the
version or commit affected. You will get an acknowledgement within a few days
and a fix or a mitigation plan as soon as we have one. Credit is given in the
release notes unless you prefer otherwise.

In scope: anything that lets a client send without valid credentials, send as
a domain it does not own, bypass rate limits, read another project's data, or
reach the relay from outside the host in the default configuration.
