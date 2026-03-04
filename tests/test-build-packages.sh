#!/bin/bash
set -euo pipefail

SCRIPT="scripts/build-packages.sh"
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

echo "=== build-packages.sh static validation ==="

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

# 4. set -euo pipefail
if grep -q '^set -euo pipefail' "${SCRIPT}"; then
  pass "set -euo pipefail present"
else
  fail "set -euo pipefail not found"
fi

# 5. No bare $VAR (unquoted variables) — check for common unquoted patterns
# Exclude comments, echo strings, and arithmetic contexts
bare_vars="$(grep -nE '\$[A-Za-z_][A-Za-z0-9_]*' "${SCRIPT}" | grep -vE '"\$\{' | grep -vE '^\s*#' | grep -vE '\$\(' | grep -vE '\$\(\(' | grep -vE 'shopt' || true)"
if [[ -z "${bare_vars}" ]]; then
  pass "No bare (unquoted) variables detected"
else
  # Filter further: allow $((, $*, $@, and already-quoted patterns
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

# 7. No hardcoded package names
if grep -qiE '(cisco-ios|cisco-iosxr|cisco-nx|juniper|arista)' "${SCRIPT}"; then
  fail "Hardcoded package/NED names found — must dynamically discover"
else
  pass "No hardcoded package/NED names"
fi

# 8. No colored output (ANSI escape codes)
if grep -qE '\\033\[|\\e\[|\\x1[bB]\[' "${SCRIPT}"; then
  fail "ANSI color codes found — forbidden in scripts"
else
  pass "No ANSI color codes"
fi

# 9. Uses [[ ]] not [ ]
if grep -qE '^\s*\[ [^[]' "${SCRIPT}" || grep -qE ';\s*\[ [^[]' "${SCRIPT}"; then
  fail "POSIX [ ] conditionals found — must use [[ ]]"
else
  pass "No POSIX [ ] conditionals (uses [[ ]])"
fi

# 10. Functions use name() { } syntax, not function keyword
if grep -qE '^\s*function ' "${SCRIPT}"; then
  fail "function keyword used — must use name() { } syntax"
else
  pass "Functions use name() { } syntax"
fi

# 11. Dynamic NED discovery (uses globbing or find, not static list)
if grep -qE '\.bin' "${SCRIPT}" && grep -qE 'NED_DIR' "${SCRIPT}"; then
  pass "Dynamic NED discovery pattern detected"
else
  fail "No dynamic NED discovery pattern found"
fi

# 12. Empty state handling
if grep -q 'No packages found' "${SCRIPT}"; then
  pass "Empty state warning present"
else
  fail "No empty state handling found"
fi

# 13. make -C used for compilation
if grep -q 'make -C' "${SCRIPT}"; then
  pass "make -C pattern used for compilation"
else
  fail "make -C not found — required for package compilation"
fi

# 14. --skip-verification used for NED unpacking
if grep -q '\-\-skip-verification' "${SCRIPT}"; then
  pass "--skip-verification flag used for NED unpacking"
else
  fail "--skip-verification not found"
fi

# 15. Output directory is /nso/run/packages
if grep -q '/nso/run/packages' "${SCRIPT}"; then
  pass "Output directory /nso/run/packages configured"
else
  fail "Output directory /nso/run/packages not found"
fi

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
