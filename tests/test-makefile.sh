#!/bin/bash
set -euo pipefail

MAKEFILE="Makefile"
GITIGNORE=".gitignore"
PASS=0
FAIL=0

pass() {
  echo "  PASS: $*"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

echo "=== Makefile static validation ==="

# 1. Makefile exists at project root
if [[ -f "${MAKEFILE}" ]]; then
  pass "Makefile exists at project root"
else
  fail "Makefile does not exist at project root"
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi

# 2. include .env at top of file
if head -n 10 "${MAKEFILE}" | grep -q '^include .env'; then
  pass "include .env present near top"
else
  fail "include .env not found near top of Makefile"
fi

# 3. export directive
if head -n 10 "${MAKEFILE}" | grep -q '^export'; then
  pass "export directive present near top"
else
  fail "export directive not found near top of Makefile"
fi

# 4. NSO_BUILD_IMAGE variable defined
if grep -q '^NSO_BUILD_IMAGE' "${MAKEFILE}"; then
  pass "NSO_BUILD_IMAGE variable defined"
else
  fail "NSO_BUILD_IMAGE variable not defined"
fi

# 5. NSO_PROD_IMAGE variable defined
if grep -q '^NSO_PROD_IMAGE' "${MAKEFILE}"; then
  pass "NSO_PROD_IMAGE variable defined"
else
  fail "NSO_PROD_IMAGE variable not defined"
fi

# 6. NSO_CUSTOM_IMAGE variable defined
if grep -q '^NSO_CUSTOM_IMAGE' "${MAKEFILE}"; then
  pass "NSO_CUSTOM_IMAGE variable defined"
else
  fail "NSO_CUSTOM_IMAGE variable not defined"
fi

# 7. .PHONY: build declared
if grep -q '^\.PHONY:.*build' "${MAKEFILE}"; then
  pass ".PHONY: build declared"
else
  fail ".PHONY: build not declared"
fi

# 8. ## comment above build target
if grep -q '^## ' "${MAKEFILE}"; then
  pass "## documentation comment present"
else
  fail "## documentation comment not found"
fi

# 9. No @ prefix on recipe lines (lines starting with tab then @)
if grep -q "$(printf '^\t@')" "${MAKEFILE}"; then
  fail "@ prefix found on recipe lines — commands must be shown"
else
  pass "No @ prefix on recipe lines"
fi

# 10. No hardcoded NSO version (e.g., 6.6 or 6.7)
if grep -qE '[^#]*[= ](cisco-nso-(build|prod)|nso-custom-prod):[0-9]+\.[0-9]+' "${MAKEFILE}"; then
  fail "Hardcoded NSO version found — must use \$(NSO_VERSION)"
else
  pass "No hardcoded NSO version"
fi

# 11. Image verification uses docker image inspect
if grep -q 'docker image inspect' "${MAKEFILE}"; then
  pass "docker image inspect used for image verification"
else
  fail "docker image inspect not found — required for image verification"
fi

# 12. docker build uses --build-arg NSO_VERSION
if grep -q '\-\-build-arg NSO_VERSION' "${MAKEFILE}"; then
  pass "docker build uses --build-arg NSO_VERSION"
else
  fail "docker build --build-arg NSO_VERSION not found"
fi

# 13. docker compose uses --profile build
if grep -q 'docker compose --profile build up -d nso-build' "${MAKEFILE}"; then
  pass "docker compose --profile build up -d nso-build present"
else
  fail "docker compose --profile build up -d nso-build not found"
fi

# 14. docker compose exec with build script
if grep -q 'docker compose exec nso-build /build-packages.sh' "${MAKEFILE}"; then
  pass "docker compose exec nso-build /build-packages.sh present"
else
  fail "docker compose exec nso-build /build-packages.sh not found"
fi

# 15. Uses $(NSO_VERSION) not ${NSO_VERSION} in Make variable definitions
if grep -qE '^\$\(NSO_VERSION\)' "${MAKEFILE}" || grep -q 'NSO_VERSION)' "${MAKEFILE}"; then
  pass "Uses Make-style \$(NSO_VERSION) references"
else
  fail "Make-style \$(NSO_VERSION) references not found"
fi

# 16. docker load -i referenced for auto-loading
if grep -q 'docker load' "${MAKEFILE}"; then
  pass "docker load referenced for image auto-loading"
else
  fail "docker load not found — required for FR6 auto-loading"
fi

# 17. Error messages go to stderr (>&2)
if grep -q '>&2' "${MAKEFILE}"; then
  pass "Error messages use >&2 redirection"
else
  fail "No >&2 found — errors must go to stderr"
fi

# 18. No docker-compose (hyphenated) — must use docker compose (space)
if grep -q 'docker-compose' "${MAKEFILE}"; then
  fail "docker-compose (hyphenated) found — must use 'docker compose' (Compose v2)"
else
  pass "Uses 'docker compose' (not hyphenated)"
fi

# 19. No ANSI color codes
if grep -qE '\\033\[|\\e\[|\\x1[bB]\[' "${MAKEFILE}"; then
  fail "ANSI color codes found — forbidden per architecture"
else
  pass "No ANSI color codes"
fi

# 20. images/*.tar.gz in .gitignore
if [[ -f "${GITIGNORE}" ]] && grep -q 'images/\*.tar.gz' "${GITIGNORE}"; then
  pass "images/*.tar.gz pattern in .gitignore"
else
  fail "images/*.tar.gz pattern not found in .gitignore"
fi

# 21. Custom image tag uses nso-custom-prod
if grep -q 'nso-custom-prod' "${MAKEFILE}"; then
  pass "Custom image uses nso-custom-prod tag"
else
  fail "nso-custom-prod tag not found in Makefile"
fi

echo ""
echo "=== Deployment targets validation (Story 2.4) ==="

# 22. All deployment targets exist
for target in up down cli logs clean; do
  if grep -q "^${target}:" "${MAKEFILE}"; then
    pass "Target '${target}' exists"
  else
    fail "Target '${target}' not found"
  fi
done

# 27. All deployment targets in .PHONY
for target in up down cli logs clean; do
  if grep -q "^\.PHONY:.*${target}" "${MAKEFILE}"; then
    pass ".PHONY includes '${target}'"
  else
    fail ".PHONY missing '${target}'"
  fi
done

# 32. Each deployment target has ## comment above it
for target in up down cli logs clean; do
  if grep -B1 "^${target}:" "${MAKEFILE}" | grep -q '^##'; then
    pass "## comment above '${target}' target"
  else
    fail "Missing ## comment above '${target}' target"
  fi
done

# 37. 'up' uses docker compose -f compose.yaml up -d
if grep -A1 '^up:' "${MAKEFILE}" | grep -q 'docker compose -f compose.yaml up -d'; then
  pass "'up' runs: docker compose -f compose.yaml up -d"
else
  fail "'up' target command incorrect"
fi

# 38. 'down' includes all three compose files
if grep -A1 '^down:' "${MAKEFILE}" | grep -q 'compose.netsim.yaml' && \
   grep -A1 '^down:' "${MAKEFILE}" | grep -q 'compose.observability.yaml'; then
  pass "'down' includes all compose overlay files"
else
  fail "'down' missing overlay compose files"
fi

# 39. 'down' does NOT include -v flag
if grep -A1 '^down:' "${MAKEFILE}" | grep -qv '^down:' | grep -q '\-v'; then
  fail "'down' should not include -v flag (volumes must be preserved)"
else
  pass "'down' preserves volumes (no -v flag)"
fi

# 40. 'cli' uses ncs_cli with ADMIN_USERNAME and Cisco-style
if grep -A1 '^cli:' "${MAKEFILE}" | grep -q 'ncs_cli -u .* -C'; then
  pass "'cli' uses ncs_cli with -C (Cisco-style)"
else
  fail "'cli' target command incorrect"
fi

# 41. 'logs' uses docker compose logs -f
if grep -A1 '^logs:' "${MAKEFILE}" | grep -q 'docker compose logs -f'; then
  pass "'logs' runs: docker compose logs -f"
else
  fail "'logs' target command incorrect"
fi

# 42. 'clean' includes -v flag for volume destruction
if grep -A1 '^clean:' "${MAKEFILE}" | grep -q '\-v'; then
  pass "'clean' includes -v flag (destroys volumes)"
else
  fail "'clean' missing -v flag"
fi

# 43. 'clean' includes all three compose files
if grep -A1 '^clean:' "${MAKEFILE}" | grep -q 'compose.netsim.yaml' && \
   grep -A1 '^clean:' "${MAKEFILE}" | grep -q 'compose.observability.yaml'; then
  pass "'clean' includes all compose overlay files"
else
  fail "'clean' missing overlay compose files"
fi

# 44. Placeholder compose overlay files exist
if [[ -f "compose.netsim.yaml" ]]; then
  pass "compose.netsim.yaml exists"
else
  fail "compose.netsim.yaml not found"
fi

if [[ -f "compose.observability.yaml" ]]; then
  pass "compose.observability.yaml exists"
else
  fail "compose.observability.yaml not found"
fi

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
