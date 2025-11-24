# OpenCL CTS Snap

This snap provides an easy way to install and run the tests found in 
[Khronos's OpenCL Conformance Test Suite](https://github.com/KhronosGroup/OpenCL-CTS)

## Build

```
snapcraft pack
```

# Install

```
snap install --classic --dangerous opencl-cts_1.0_<your_arch>.snap
```

# Run
To list possible tests, run:
```
opencl-cts.list-tests
```

Then run your chosen test from the previous list like this:
```
opencl-cts.test basic/test_basic
```
