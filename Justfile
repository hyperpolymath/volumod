# SPDX-License-Identifier: PMPL-1.0-or-later
# justfile - Just recipes for VoluMod
# See: https://github.com/hyperpolymath/mustfile

# Default recipe
default:
    @just --list

# Build the V system application
build:
    v -prod src/main.v -o volumod

# Build debug version
build-debug:
    v src/main.v -o volumod-debug

# Build the ReScript browser extension
build-browser:
    cd browser/rescript && npx rescript build

# Build everything
build-all: build build-browser

# Run the application
run: build
    ./volumod

# Run V tests
test:
    v test src/

# Run all tests (V + browser)
test-all: test
    @echo "Browser extension tests not yet configured"

# Format V source code
fmt:
    v fmt -w src/

# Lint V source code
lint:
    v fmt -verify src/

# Clean build artifacts
clean:
    rm -f volumod volumod-debug
    rm -f browser/rescript/lib/bs/.compiler.log
    rm -rf browser/rescript/lib/bs/.bsbuild
    rm -f browser/rescript/src/*.mjs

# Check project status
status:
    @echo "=== Build Status ==="
    @v . && echo "V build: OK" || echo "V build: FAILED"
    @echo ""
    @echo "=== Test Status ==="
    @v test src/ 2>&1 || true
    @echo ""
    @echo "=== Binary ==="
    @ls -lh volumod 2>/dev/null || echo "No binary (run 'just build')"

# Run panic-attack security scan
scan:
    panic-attack assail . --output /tmp/volumod-scan.json
    @echo "Scan output: /tmp/volumod-scan.json"
