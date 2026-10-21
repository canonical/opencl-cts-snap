# CI on real hardware: Testflinger + spread

The `spread` job in `.github/workflows/snap-ci.yml` runs the OpenCL CTS smoke
suite on arm64 hardware provided by
[Testflinger](https://canonical-testflinger.readthedocs-hosted.com/) at
`testflinger.canonical.com`: a **Raspberry Pi 5** and one or more **MediaTek
Genio EVK** boards. Tests are driven by
[`spread`](https://github.com/canonical/spread) — or rather
[spread-plus](https://github.com/canonical/spread-plus), the fork that ships a
native Testflinger backend.

## How it works

```
build job ──► arm64 snap artifact
                    │
spread job ────► download artifact, rename to opencl-cts.snap
                    │
            spread-plus testflinger:<system>:tests/
                    │  1. submits a reservation job to the queue
                    │  2. waits until the device is allocated (device IP)
                    │  3. imports your GitHub SSH keys into the board (reserve-key)
                    │  4. SSHes in and copies the project files (incl. the snap)
                    │  5. runs tests/board/opencl-cts/task.yaml
                    └──  installs the host Mesa ICD, sideloads the snap with
                         `snap install --dangerous`, connects the GPU content
                         interface and runs a smoke subset of the CTS tests.
```

Each matrix entry targets a queue with a matching Ubuntu image, so both snap
bases are validated on the Pi (`rpi5-core24`, `rpi5-core26`) and Genio boards
are validated with the core24 snap.

### Raspberry Pi 5

The `rpi5-*` systems use a pre-installed Ubuntu SD image (`image:` shorthand)
and boot straight into a reachable system.

### MediaTek Genio EVK

The `genio-*` systems are provisioned by the **`zapper_iot`** device connector,
which flashes the board before the test phase. Flashing needs more than a single
URL (an Ubuntu disk image *and* a board-specific boot firmware archive), so the
systems use the free-form `provision-data` map instead of the `image:` shorthand:

```yaml
- genio-1200:
    queue: <genio-1200-queue>
    provision-data:
      urls:
        - <ubuntu-disk-image-url>
        - <boot-firmware-url>
    username: ubuntu
    reserve-key: gh:replace-with-your-github-user
    ssh-rsa-key: '$(HOST: echo "$SPREAD_SSH_KEY")'
```

`provision-data` is passed through verbatim as the Testflinger job's
`provision_data`, so any key understood by the connector serving the queue can be
supplied. The provisioning method itself is selected by the queue/agent, not by
spread, so make sure the Genio queue is backed by a `zapper_iot` agent.

Only Ubuntu 24.04 images are published for Genio today, hence the `core24` snap.

> **Before enabling the Genio jobs** fill in the real queue names and image URLs
> in `spread.yaml` (currently `REPLACE_ME-*` placeholders). CI fails fast with a
> clear message while placeholders remain. If the queues are *restricted* they
> may also need their own Testflinger client credentials.

### Browsing and running the matrix

Use `spread-plus -list` to print the job matrix without running it:

## Prerequisites

You need access to a Testflinger deployment (default: `testflinger.canonical.com`):

1. **Testflinger client credentials**
   An OAuth2 client (`client_id` / `secret_key`) that is allowed to submit jobs
   to the `rpi5b` queue and the Genio queues. Ask a Testflinger admin on your
   team, or use your own Testflinger deployment with a client that can reach
   your queues.
2. **Queue access** The `rpi5b` queue and each `genio-*` queue must exist and
   be visible to your client (restricted queues need to grant access explicitly).
3. **Reserve support** SSH authentication relies on Testflinger's *reserve*
   mechanism (`reserve_data.ssh_keys`): the device connector imports public
   keys from a keys provider (GitHub or Launchpad) into the provisioned image.
   The queue you target must support this.
4. **zapper_iot** The Genio queues must be backed by agents configured with the
   [`zapper_iot`](https://canonical-testflinger.readthedocs-hosted.com/latest/reference/device-connector-types/)
   device connector, since the board is flashed during provisioning.

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

The Genio systems use the same `reserve-key` mechanism, but replace `image:`
with `provision-data:` for the zapper_iot flash (see above).

## Required GitHub secrets and variables

Configure these at **Settings → Secrets and variables → Actions** for the
repository (or with `gh secret set` / `gh variable set`):

| Name | Type | Required for | Description |
|------|------|--------------|-------------|
| `TESTFLINGER_CLIENT_ID` | secret | `spread` job | OAuth2 client ID that can submit jobs to the `rpi5b` and Genio queues. |
| `TESTFLINGER_SECRET_KEY` | secret | `spread` job | OAuth2 client secret paired with `TESTFLINGER_CLIENT_ID`. |
| `SPREAD_SSH_KEY` | secret | `spread` job | Private SSH key used by spread to connect to the board. Its public half must be on the GitHub account named by `SPREAD_RESERVE_KEY`. Store it **as a single-line value** (e.g. the base64/one-line form of the PEM) and make sure the environment variable is exported unaltered by GitHub Actions. |
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

- **In CI:** the `spread` job runs on every push to `main`, `develop`, and any
  branch whose name contains `testflinger`, for both snap bases on the Pi
  (`core24`, `core26`) and for the core24 snap on each Genio board.
- **Locally:** install spread-plus, export the credentials above (no store
  publish needed), place an `opencl-cts.snap` at the repo root, and run:

```
export TESTFLINGER_CLIENT_ID=... TESTFLINGER_SECRET_KEY=...
export SPREAD_SSH_KEY="$(cat ~/.ssh/id_ed25519)"
sed -i "s|gh:replace-with-your-github-user|gh:your-github-username|" spread.yaml
spread testflinger:tests/   # or: spread testflinger:rpi5-core24:tests/
spread testflinger:genio-1200:tests/   # a Genio board
```

Use `spread -list` to print the job matrix without running it.

## Troubleshooting

- **Queue contention** — the queues are shared; `wait-timeout: 45m` in
  `spread.yaml` bounds how long spread waits for an allocation.
- **Stranded devices** — if a runner is killed mid-run, the Testflinger job may
  still be active. Jobs are tagged `spread` and carry a `halt-timeout` so
  Testflinger cancels them once they outlive it (3h). You can also cancel by
  hand from the Testflinger UI or `spread -gc`.
- **Genio flash failures** — zapper_iot streams the flash over the serial
  console; when a Genio job fails during provisioning, check the job's
  provision logs in the Testflinger UI. Verify the disk image and boot firmware
  URLs match the target board and that the queue's agent is a `zapper_iot`
  agent.
- **`clGetPlatformIDs failed` at test start** — the OS image on the device is
  older than your GPU support; try the newer base (see README).