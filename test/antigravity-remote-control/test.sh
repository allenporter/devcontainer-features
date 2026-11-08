#!/bin/bash
set -e

# Import devcontainer features test library
source dev-container-features-test-lib

check "language_server binary is installed" which language_server
check "agy CLI is installed" which agy
check "agy-upgrade helper is installed" which agy-upgrade
check "antigravity-host-bridge helper is installed" which antigravity-host-bridge
check "start-antigravity launcher is installed" which start-antigravity

reportResults
