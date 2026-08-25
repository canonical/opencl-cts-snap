# OpenCL CTS Snap

This snap provides an easy way to install and run the tests found in
[Khronos's OpenCL Conformance Test Suite](https://github.com/KhronosGroup/OpenCL-CTS)

## Snap bases

The snap is maintained for two bases, each in its own self-contained
snapcraft project directory:

| Directory | Base   | GPU content | Intel driver source  | Use for                                     |
|-----------|--------|-------------|----------------------|---------------------------------------------|
| `core24/` | core24 | `gpu-2404`  | Ubuntu 24.04 archive | Up to Arc A-series (Alchemist)              |
| `core26/` | core26 | `gpu-2604`  | Ubuntu 26.04 archive | Newer GPUs: Arc B-series (Battlemage), PTL  |

The core24 driver predates recent Intel GPUs, so on hardware like the Arc
B-series or Panther Lake it enumerates no devices and tests fail with
`clGetPlatformIDs failed`. Use the `core26` build on that hardware.

In the Snap Store the two variants are published on separate tracks
(`latest`/default for core24, `core26` for core26).

## Build

Each directory is a directly-buildable snapcraft project. `cd` into the base
you want and run snapcraft:

```
cd core24 && snapcraft pack     # core24 variant
cd core26 && snapcraft pack     # core26 variant
```

## Install

```
snap install --dangerous opencl-cts_<version>_<your_arch>.snap
```

Or from the store, choosing the channel that matches your hardware:

```
snap install opencl-cts                       # default (core24) track
snap install opencl-cts --channel=core26/edge # core26 track (Battlemage/PTL)
```

Connect the matching GPU content interface if it isn't auto-connected:

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
