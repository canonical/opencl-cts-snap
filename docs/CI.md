# CI on real hardware: Testflinger + spread

The `spread` job in `.github/workflows/snap-ci.yml` runs the OpenCL CTS smoke
suite on a **Raspberry Pi 5** provided by
[Testflinger](https://canonical-testflinger.readthedocs-hosted.com/) at
`testflinger.canonical.com`. Tests are driven by
[`spread`](https://github.com/canonical/spread) — or rather
[spread-plus](https://github.com/canonical/spread-plus), the fork that ships a
native Testflinger backend.

## How it works

```
build job ──► arm64 snap artifact
                    │
spread job ────► download artifact, rename to opencl-cts.snap
                    │
            spread-plus testflinger:rpi5-<base>:tests/
                    │  1. submits a reservation job to the rpi5b queue
                    │  2. waits until the device is allocated (device IP)
                    │  3. imports your GitHub SSH keys into the Pi (reserve-key)
                    │  4. SSHes in and copies the project files (incl. the snap)
                    │  5. runs tests/rpi/opencl-cts/task.yaml
                    └──  installs mesa-opencl-icd, sideloads the snap with
                         `snap install --dangerous`, connects the GPU content
                         interface and runs a smoke subset of the CTS tests.
```

Each matrix entry (`rpi5-core24`, `rpi5-core26`) targets the `rpi5b` queue with
a matching Ubuntu pre-installed Raspberry Pi image, so both snap bases are
validated on the Pi.

## Prerequisites

You need access to a Testflinger deployment (default: `testflinger.canonical.com`):

1. **Testflinger client credentials**
   An OAuth2 client (`client_id` / `secret_key`) that is allowed to submit jobs
   to the `rpi5b` queue. Ask a Testflinger admin on your team, or use your own
   Testflinger deployment with a client that can reach your queues.
2. **Queue access** The `rpi5b` queue must exist and be visible to your client.
3. **Reserve support** SSH authentication relies on Testflinger's *reserve*
   mechanism (`reserve_data.ssh_keys`): the device connector imports public
   keys from a keys provider (GitHub or Launchpad) into the provisioned image.
   The queue you target must support this.

### Why spread-plus and not upstream spread

Upstream `spread` has no Testflinger backend. Use
[spread-plus](https://github.com/canonical/spread-plus), which is fully
compatible with the `spread.yaml` format and adds the `testflinger` backend.
The workflow installs a **pinned release** (currently `2026.09.22`) so CI is
reproducible. You can also install it locally:

```
go install github.com/canonical/spread-plus/cmd/spread@latest
```

### SSH authentication (reserve-key)

The spread entry for each system in `spread.yaml` looks like:

```yaml
- rpi5-core24:
    queue: rpi5b
    image: https://cdimage.ubuntu.com/.../ubuntu-24.04.4-preinstalled-server-arm64+raspi.img.xz
    username: ubuntu
    reserve-key: gh:replace-with-your-github-user
    ssh-rsa-key: '$(HOST: echo "$SPREAD_SSH_KEY")'
```

- `reserve-key: gh:<your-github-username>` tells Testflinger to import the
  public SSH keys of that GitHub account into the device. spread-plus does
  **not** expand environment references in this field, so the workflow
  substitutes the value (from the `SPREAD_RESERVE_KEY` variable) into
  `spread.yaml` with `sed` before running.
- `ssh-rsa-key` is the **private** key whose public half is on that GitHub
  account (see `https://github.com/<your-github-username>.keys`). spread
  expands `$(HOST: echo "$SPREAD_SSH_KEY")` on the runner, so the key is read
  from the `SPREAD_SSH_KEY` secret.

## Required GitHub secrets and variables

Configure these at **Settings → Secrets and variables → Actions** for the
repository (or with `gh secret set` / `gh variable set`):

| Name | Type | Required for | Description |
|------|------|--------------|-------------|
| `TESTFLINGER_CLIENT_ID` | secret | `spread` job | OAuth2 client ID that can submit jobs to the `rpi5b` queue. |
| `TESTFLINGER_SECRET_KEY` | secret | `spread` job | OAuth2 client secret paired with `TESTFLINGER_CLIENT_ID`. |
| `SPREAD_SSH_KEY` | secret | `spread` job | Private SSH key used by spread to connect to the Pi. Its public half must be on the GitHub account named by `SPREAD_RESERVE_KEY`. Store it **as a single-line value** (e.g. the base64/one-line form of the PEM) and make sure the environment variable is exported unaltered by GitHub Actions. |
| `SPREAD_RESERVE_KEY` | variable | `spread` job | The reserve key account, e.g. `gh:your-github-username`. Public identifier (only used to look up the account's public keys), so it is stored as a variable and injected into `spread.yaml` at run time. |
| `SNAPCRAFT_STORE_CREDENTIALS` | secret | `build` job | Snap Store credentials used to publish the built snap to the store on pushes to the default branch. Not used by the `spread` job. |

> Note on `SPREAD_SSH_KEY`: spread expands `ssh-rsa-key` with a `$(HOST: ...)`
> command, so the private key is read from the environment on the runner. If
> your provider normalizes multi-line values, provide the key on a single line
> (newlines can be embedded with `\n`) or adjust the workflow to write the
> secret to a file and point `ssh-rsa-key` at that path.

### Setting secrets from the CLI

```
gh secret set TESTFLINGER_CLIENT_ID
gh secret set TESTFLINGER_SECRET_KEY
gh secret set SPREAD_SSH_KEY
gh variable set SPREAD_RESERVE_KEY --body "gh:your-github-username"
```

## Running the tests

- **In CI:** the `spread` job runs on every push to `main`, `develop`, and the
  `rpi5b-testflinger` test branch, for both snap bases (`core24`, `core26`).
- **Locally:** install spread-plus, export the four values above plus
  `SNAPCRAFT_STORE_CREDENTIALS`-free setup (no store publish needed), place an
  `opencl-cts.snap` at the repo root, and run:

```
export TESTFLINGER_CLIENT_ID=... TESTFLINGER_SECRET_KEY=...
export SPREAD_SSH_KEY="$(cat ~/.ssh/id_ed25519)"
sed -i "s|gh:replace-with-your-github-user|gh:your-github-username|" spread.yaml
spread testflinger:tests/   # or: spread testflinger:rpi5-core24:tests/
```

Use `spread -list` to print the job matrix without running it.

## Troubleshooting

- **Queue contention** — the `rpi5b` queue is shared; `wait-timeout: 30m` in
  `spread.yaml` bounds how long spread waits for an allocation.
- **Stranded devices** — if a runner is killed mid-run, the Testflinger job may
  still be active. Jobs are tagged `spread` and carry a `halt-timeout` so
  Testflinger cancels them once they outlive it (2h). You can also cancel by
  hand from the Testflinger UI or `spread -gc`.
- **`clGetPlatformIDs failed` at test start** — the OS image on the device is
  older than your GPU support; try the newer base (see README).