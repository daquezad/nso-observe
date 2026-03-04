#!/bin/bash
set -euo pipefail

SCRIPT="netsim/netsim-start.sh"
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

echo "=== netsim-start.sh static validation ==="

# 1. File exists
if [[ -f "${SCRIPT}" ]]; then
  pass "Script file exists"
else
  fail "Script file does not exist: ${SCRIPT}"
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi

# 2. Executable permission
if [[ -x "${SCRIPT}" ]]; then
  pass "Script is executable"
else
  fail "Script is not executable"
fi

# 3. Shebang
first_line="$(head -n 1 "${SCRIPT}")"
if [[ "${first_line}" == "#!/bin/bash" ]]; then
  pass "Shebang is #!/bin/bash"
else
  fail "Shebang is '${first_line}', expected '#!/bin/bash'"
fi

# 4. set -euo pipefail (standalone script, not pre/post-start)
if grep -q '^set -euo pipefail' "${SCRIPT}"; then
  pass "set -euo pipefail present"
else
  fail "set -euo pipefail not found"
fi

# 5. No bare $VAR (unquoted variables)
bare_vars="$(grep -nE '\$[A-Za-z_][A-Za-z0-9_]*' "${SCRIPT}" | grep -vE '"\$\{' | grep -vE '^\s*#' | grep -vE '\$\(' | grep -vE '\$\(\(' | grep -vE 'shopt' || true)"
if [[ -z "${bare_vars}" ]]; then
  pass "No bare (unquoted) variables detected"
else
  real_bare="$(echo "${bare_vars}" | grep -vE '"\$' | grep -vE '\$\*' | grep -vE '\$\@' | grep -vE '\$#' | grep -vE '\$\?' || true)"
  if [[ -z "${real_bare}" ]]; then
    pass "All variables properly quoted"
  else
    fail "Possibly unquoted variables found (review manually):"
    echo "${real_bare}"
  fi
fi

# 6. Error output uses >&2
if grep -q '>&2' "${SCRIPT}"; then
  pass "Error output uses >&2"
else
  fail "No >&2 redirection found for error output"
fi

# 7. No colored output (ANSI escape codes)
if grep -qE '\\033\[|\\e\[|\\x1[bB]\[' "${SCRIPT}"; then
  fail "ANSI color codes found — forbidden in scripts"
else
  pass "No ANSI color codes"
fi

# 8. Uses [[ ]] not [ ]
if grep -qE '^\s*\[ [^[]' "${SCRIPT}" || grep -qE ';\s*\[ [^[]' "${SCRIPT}"; then
  fail "POSIX [ ] conditionals found — must use [[ ]]"
else
  pass "No POSIX [ ] conditionals (uses [[ ]])"
fi

# 9. Functions use name() { } syntax, not function keyword
if grep -qE '^\s*function ' "${SCRIPT}"; then
  fail "function keyword used — must use name() { } syntax"
else
  pass "Functions use name() { } syntax"
fi

# 10. Uses ncs-xml-init + sed to replace 127.0.0.1 with container hostname
if grep -q 'ncs-xml-init' "${SCRIPT}"; then
  pass "Uses ncs-xml-init for device XML generation"
else
  fail "ncs-xml-init not found"
fi
if grep -q 'sed.*127\.0\.0\.1' "${SCRIPT}"; then
  pass "Uses sed to replace 127.0.0.1 with container hostname"
else
  fail "sed replacement of 127.0.0.1 not found"
fi

# 11. PYTHONPATH is set
if grep -q 'PYTHONPATH' "${SCRIPT}"; then
  pass "PYTHONPATH is set"
else
  fail "PYTHONPATH not set — required for ncs-netsim"
fi

# 12. Idempotent device creation (checks before creating)
if grep -q 'if.*!.*NETSIM_DIR' "${SCRIPT}"; then
  pass "Idempotent device creation check present"
else
  fail "No idempotency check before device creation"
fi

# 13. Uses ncs-netsim create-network (not create-device in a loop)
if grep -q 'create-network' "${SCRIPT}"; then
  pass "Uses ncs-netsim create-network for batch creation"
else
  fail "ncs-netsim create-network not found"
fi

# 14. Reads NETSIM_DEVICE_COUNT from environment with default
if grep -q 'NETSIM_DEVICE_COUNT:-' "${SCRIPT}"; then
  pass "NETSIM_DEVICE_COUNT read from env with default"
else
  fail "NETSIM_DEVICE_COUNT not read from environment with default"
fi

# 15. tail -f /dev/null at end of script
if tail -3 "${SCRIPT}" | grep -q 'tail -f /dev/null'; then
  pass "tail -f /dev/null keeps container alive"
else
  fail "Missing tail -f /dev/null at end of script"
fi

# 16. NED package auto-discovery (not hardcoded)
if grep -qiE '(cisco-ios|cisco-iosxr|cisco-nx|juniper|arista)' "${SCRIPT}"; then
  fail "Hardcoded NED package names found — must auto-discover"
else
  pass "No hardcoded NED package names"
fi

# 17. discover_ned_package function exists
if grep -q 'discover_ned_package()' "${SCRIPT}"; then
  pass "discover_ned_package() function exists"
else
  fail "discover_ned_package() function not found"
fi

# 18. Packages directory is /nso/run/packages
if grep -q '/nso/run/packages' "${SCRIPT}"; then
  pass "Packages directory /nso/run/packages configured"
else
  fail "Packages directory /nso/run/packages not found"
fi

echo ""
echo "=== Directory structure validation ==="

# 19. netsim/ directory exists
if [[ -d "netsim" ]]; then
  pass "netsim/ directory exists"
else
  fail "netsim/ directory does not exist"
fi

# 20. netsim/post-ncs-start/ directory exists
if [[ -d "netsim/post-ncs-start" ]]; then
  pass "netsim/post-ncs-start/ directory exists"
else
  fail "netsim/post-ncs-start/ directory does not exist"
fi

# 21. netsim/post-ncs-start/01-load-netsim-devices.sh exists
if [[ -f "netsim/post-ncs-start/01-load-netsim-devices.sh" ]]; then
  pass "netsim/post-ncs-start/01-load-netsim-devices.sh exists"
else
  fail "netsim/post-ncs-start/01-load-netsim-devices.sh not found"
fi

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
