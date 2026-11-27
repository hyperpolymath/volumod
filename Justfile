# SPDX-License-Identifier: MPL-2.0
# justfile - Just recipes for VoluMod
# See: https://github.com/hyperpolymath/mustfile

# Default recipe
default:
    @just --list

# Build the Zig system application (release)
build:
    zig build -Doptimize=ReleaseSafe

# Build debug version
build-debug:
    zig build

# Build the ReScript browser extension
build-browser:
    cd browser/rescript && bunx rescript build

# Build everything
build-all: build build-browser

# Run the application
run:
    zig build run

# Run Zig unit tests
test:
    zig build test

# Run all tests (Zig + browser)
test-all: test
    @echo "Browser extension tests not yet configured"

# Format Zig source code
fmt:
    zig fmt build.zig src/zig

# Check Zig formatting
lint:
    zig fmt --check build.zig src/zig

# Clean build artifacts
clean:
    rm -rf zig-out .zig-cache
    rm -f browser/rescript/lib/bs/.compiler.log
    rm -rf browser/rescript/lib/bs/.bsbuild
    rm -f browser/rescript/src/*.mjs

# Check project status
status:
    @echo "=== Build Status ==="
    @zig build && echo "Zig build: OK" || echo "Zig build: FAILED"
    @echo ""
    @echo "=== Test Status ==="
    @zig build test 2>&1 || true
    @echo ""
    @echo "=== Binary ==="
    @ls -lh zig-out/bin/volumod 2>/dev/null || echo "No binary (run 'just build')"

# Run panic-attack security scan
scan:
    panic-attack assail . --output /tmp/volumod-scan.json
    @echo "Scan output: /tmp/volumod-scan.json"

secret-scan-trufflehog:
    @command -v trufflehog >/dev/null && trufflehog filesystem . --only-verified || true
