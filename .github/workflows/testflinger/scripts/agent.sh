#!/usr/bin/env bash
# Test script for running OpenCL CTS tests on testflinger machines
set -e

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== OpenCL CTS Test Script ==="
echo "Snap channel: $SNAP_CHANNEL"
echo "Snap base: $SNAP_BASE"
echo "Device IP: $DEVICE_IP"

# By default ssh with user ubuntu
DEVICE_USER="${DEVICE_USER:-ubuntu}"
export DEVICE_USER

# Common SSH options
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3"
export SSH_OPTS

# Helper function to run commands on the device
run_on_device() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$DEVICE_USER@$DEVICE_IP" "$@"
}

echo ""
echo "=== Step 1: Update system snaps ==="
run_on_device "sudo snap refresh"

echo ""
echo "=== Step 2: Install OpenCL CTS snap ==="
# Install the snap from the specified channel
run_on_device "sudo snap install opencl-cts --channel=$SNAP_CHANNEL"

echo ""
echo "=== Step 3: Detect architecture and install OpenCL driver ==="
DEVICE_ARCH=$(run_on_device "dpkg --print-architecture")
echo "Device architecture: $DEVICE_ARCH"

# Raspberry Pi boards expose the V3D GPU through Mesa Rusticl instead of a
# vendor OpenCL driver. The snap cannot reach the host ICD while confined
# (no ICD is staged inside the arm64 snap), so tests must run unsandboxed
# via the test wrapper's --no-confinement mode.
NO_CONFINEMENT=false
if [ "$DEVICE_ARCH" = "arm64" ]; then
    NO_CONFINEMENT=true
    echo "Installing host OpenCL driver (mesa-opencl-icd) for Rusticl on V3D"
    run_on_device "sudo apt-get update -qq && sudo apt-get install -y -qq ocl-icd-libopencl1 mesa-opencl-icd"
    # Rusticl on V3D requires Mesa >= 24.1; fail early if the loader is missing.
    run_on_device "test -f /usr/lib/aarch64-linux-gnu/libOpenCL.so.1"
    echo "Host OpenCL ICDs on device:"
    run_on_device "ls /etc/OpenCL/vendors/ || echo 'no ICDs found'"
fi

echo ""
echo "=== Step 4: Connect GPU content interface ==="
# Determine which GPU content interface to connect based on snap base
if [ "$SNAP_BASE" = "core26" ]; then
    GPU_INTERFACE="gpu-2604"
    GPU_PROVIDER="mesa-2604"
else
    GPU_INTERFACE="gpu-2404"
    GPU_PROVIDER="mesa-2404"
fi

echo "Connecting $GPU_INTERFACE to $GPU_PROVIDER"
run_on_device "sudo snap connect opencl-cts:$GPU_INTERFACE $GPU_PROVIDER:$GPU_INTERFACE || true"

echo ""
echo "=== Step 5: List available tests ==="
run_on_device "opencl-cts.list-tests"

echo ""
echo "=== Step 6: Run test suite ==="
# Get list of all tests and run them
TESTS=$(run_on_device "opencl-cts.list-tests")
echo "Found tests:"
echo "$TESTS"

# On Raspberry Pi (rusticl) Rusticl is not officially CTS-conformant and some
# tests can hang, so run a representative smoke subset instead of the whole suite.
if [ "$NO_CONFINEMENT" = "true" ]; then
    SMOKE_PREFIXES="${SMOKE_PREFIXES:-api basic buffer bufimage vector}"
    SUBSET=""
    for prefix in $SMOKE_PREFIXES; do
        for test in $TESTS; do
            case "$test" in
                "$prefix/"*) SUBSET="$SUBSET $test" ;;
            esac
        done
    done
    if [ -z "$SUBSET" ]; then
        echo "No tests matched smoke prefixes, falling back to first 5 tests"
        SUBSET=$(echo "$TESTS" | head -n 5)
    fi
    TESTS=$SUBSET
    echo ""
    echo "Running smoke subset on Raspberry Pi:"
    echo "$TESTS"
fi

# Run each test and collect results
FAILED_TESTS=""
PASSED_TESTS=""
TOTAL=0
FAILED=0

run_test() {
    local test="$1"
    if [ "$NO_CONFINEMENT" = "true" ]; then
        # Execute the snap's test wrapper directly (bypassing snapd confinement)
        # so it can LD_PRELOAD the host OpenCL ICD loader. A timeout guards
        # against tests that hang on the Rusticl V3D driver.
        local wrapper
        wrapper=$(run_on_device "find /snap/opencl-cts/current -maxdepth 2 -type f -name test | head -n1")
        echo "Running unsandboxed: ${wrapper##*/} --no-confinement $test"
        # shellcheck disable=SC2029
        run_on_device "SNAP=/snap/opencl-cts/current timeout 300 $wrapper --no-confinement $test"
    else
        run_on_device "opencl-cts.test $test"
    fi
}

for test in $TESTS; do
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "--- Running test: $test ---"

    if run_test "$test"; then
        PASSED_TESTS="$PASSED_TESTS $test"
        echo "PASSED: $test"
    else
        FAILED_TESTS="$FAILED_TESTS $test"
        FAILED=$((FAILED + 1))
        echo "FAILED: $test"
    fi
done

echo ""
echo "=== Test Summary ==="
echo "Total tests: $TOTAL"
echo "Passed: $((TOTAL - FAILED))"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for test in $FAILED_TESTS; do
        echo "  - $test"
    done
    exit 1
fi

echo ""
echo "All tests passed!"
exit 0