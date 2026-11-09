# Contributing to Remit

Thanks for considering a contribution. Remit is small on purpose; the bar for
a change is "does it make sending transactional mail from your own server
simpler or safer".

## Before you start

- **Bugs and small fixes:** open a pull request directly.
- **New features or behaviour changes:** open an issue first and describe the
  problem you are solving. It saves you from building something that does not
  fit the roadmap ([ROADMAP.md](ROADMAP.md)).
- **Security problems:** do not open an issue. See [SECURITY.md](SECURITY.md).

## Running Remit locally

You need Docker with Compose. Nothing else is installed on your machine.

```bash
git clone https://github.com/helloDesign-art/Remit.git
cd Remit
cp .env.example .env            # REMIT_HOSTNAME can be anything locally
docker compose up -d --build
docker compose exec relay remit project add demo demo.example
docker compose logs -f relay
```

The relay listens on `172.17.0.1:587` (Docker's host-gateway address). Any
container on your machine can reach it with `--add-host remit:host-gateway`.

## Tests

`tests/run.sh` builds the image, starts a throwaway relay on port 2587, and
checks the behaviour that matters most:

- clients without credentials or with a wrong password are rejected;
- a project can only send from its own domains;
- accepted mail arrives DKIM-signed with a signature that verifies;
- the `Received:` header with the client's internal address is removed;
- a domain routed through a provider is never delivered without TLS.

```bash
bash tests/run.sh
```

It cleans up after itself. CI runs the same script on every pull request, so
run it before you push.

## Code

- The relay is Bash plus Postfix/OpenDKIM configuration. Keep it that way for
  anything in `relay/`; the API and dashboard (later stages) live in their own
  directories with their own tooling.
- Bash: `set -euo pipefail`, tabs for indentation, `local` for every variable
  in a function, quote everything. `bash -n` must pass; `shellcheck` warnings
  are worth reading even where we do not enforce them.
- Postfix: policy goes in `relay/postfix/main.cf`, deployment-specific values
  come from environment variables in `relay/entrypoint.sh`. Do not add
  `permit_mynetworks` to any restriction; Remit trusts credentials, not
  networks.
- Anything that changes at runtime (domains, keys, logins, routes) belongs in
  `/var/lib/remit`, never in the image.
- Document user-visible changes in `README.md` or `docs/` in the same pull
  request.

## Commits and pull requests

- Commit messages follow `type(scope): what changed`, in the imperative:
  `feat(cli): add project show`, `fix(relay): keep SigningTable in sync`.
  Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`.
- One topic per pull request. Explain *why* in the description; the diff
  already shows *what*.
- A pull request should pass `tests/run.sh` and, if it changes behaviour,
  extend the tests.

## Licensing

Remit is licensed under the Apache License 2.0. By submitting a contribution
you agree that it is licensed under the same terms (see
[LICENSE](LICENSE), section 5).

## Conduct

Be kind and assume good faith. Disagree with ideas, not with people. Anyone
who makes others feel unwelcome will be asked to leave the project.
