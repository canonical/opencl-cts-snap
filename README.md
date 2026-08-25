# OpenCL CTS Snap

This snap provides an easy way to install and run the tests found in
[Khronos's OpenCL Conformance Test Suite](https://github.com/KhronosGroup/OpenCL-CTS)

## Snap bases

The snap is maintained for multiple bases, each in its own self-contained
snapcraft project directory:

| Directory | Base   | GPU content | Notes                                         |
|-----------|--------|-------------|-----------------------------------------------|
| `core24/` | core24 | `gpu-2404`  | Drivers and CTS from the 24.04 archive        |
| `core26/` | core26 | `gpu-2604`  | Newer drivers and CTS from the 26.04 archive  |

Newer hardware needs newer userspace drivers. If a test fails at startup with
`clGetPlatformIDs failed`, the base you installed likely predates your GPU;
use a newer base.

In the Snap Store the variants are published on separate tracks
(`latest`/default for core24, `core26` for core26).

## Build

Each directory is a directly-buildable snapcraft project. `cd` into the base
you want and run snapcraft:

```
cd core24 && snapcraft pack
cd core26 && snapcraft pack
```

## Install

```
snap install --dangerous opencl-cts_<version>_<your_arch>.snap
```

Or from the store, choosing the channel that matches your hardware:

```
snap install opencl-cts                       # default (core24) track
snap install opencl-cts --channel=core26/edge # core26 track
```

The GPU content interface auto-connects for store installs. For a sideloaded
(`--dangerous`) install, connect it manually to match the base:

```
snap connect opencl-cts:gpu-2404 mesa-2404:gpu-2404   # core24
snap connect opencl-cts:gpu-2604 mesa-2604:gpu-2604   # core26
```

## Run

To list possible tests, run:

```
opencl-cts.list-tests
```

Then run your chosen test from the previous list like this:

```
opencl-cts.test basic/test_basic
```
