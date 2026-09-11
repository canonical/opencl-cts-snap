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
echo "=== Step 3: Connect GPU content interface ==="
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
echo "=== Step 4: List available tests ==="
run_on_device "opencl-cts.list-tests"

echo ""
echo "=== Step 5: Run test suite ==="
# Get list of all tests and run them
TESTS=$(run_on_device "opencl-cts.list-tests")
echo "Found tests:"
echo "$TESTS"

# Run each test and collect results
FAILED_TESTS=""
PASSED_TESTS=""
TOTAL=0
FAILED=0

for test in $TESTS; do
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "--- Running test: $test ---"
    
    if run_on_device "opencl-cts.test $test"; then
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