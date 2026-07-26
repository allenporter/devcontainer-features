#!/bin/bash
set -e

# Import devcontainer features test library
source dev-container-features-test-lib

check "language_server binary is installed" which language_server
check "start-antigravity launcher is installed" which start-antigravity

reportResults
