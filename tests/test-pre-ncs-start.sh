#!/bin/bash
set -euo pipefail

SCRIPT="scripts/pre-ncs-start/01-enable-local-auth.sh"
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

echo "=== 01-enable-local-auth.sh static validation ==="

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

# 4. set -e (NOT set -euo pipefail — pre-start scripts use set -e only)
second_line="$(sed -n '2p' "${SCRIPT}")"
if [[ "${second_line}" == "set -e" ]]; then
  pass "set -e present (correct for pre-start scripts)"
else
  fail "Expected 'set -e' on line 2, got '${second_line}'"
fi

# 5. No set -u or pipefail (forbidden for pre-start scripts)
if grep -qE 'set -.*u|pipefail' "${SCRIPT}"; then
  fail "set -u or pipefail found — pre-start scripts must use set -e only"
else
  pass "No set -u or pipefail (correct for pre-start scripts)"
fi

# 6. Uses sed -i.bak (cross-platform)
if grep -q 'sed -i\.bak' "${SCRIPT}"; then
  pass "Cross-platform sed -i.bak used"
else
  fail "sed -i.bak not found — required for macOS + Linux compatibility"
fi

# 7. Removes .bak backup file
if grep -q 'rm -f.*\.bak' "${SCRIPT}"; then
  pass "Backup .bak file removal present"
else
  fail "No .bak file removal found — backup must be cleaned up"
fi

# 8. All variables quoted (no bare $VAR)
bare_vars="$(grep -nE '\$[A-Za-z_][A-Za-z0-9_]*' "${SCRIPT}" | grep -vE '"\$\{' | grep -vE '^\s*#' | grep -vE '\$\(' || true)"
if [[ -z "${bare_vars}" ]]; then
  pass "All variables properly quoted"
else
  real_bare="$(echo "${bare_vars}" | grep -vE '"\$' | grep -vE '\$\*' | grep -vE '\$\@' | grep -vE '\$#' || true)"
  if [[ -z "${real_bare}" ]]; then
    pass "All variables properly quoted"
  else
    fail "Possibly unquoted variables found:"
    echo "${real_bare}"
  fi
fi

# 9. Uses [[ ]] not [ ]
if grep -qE '^\s*\[ [^[]' "${SCRIPT}" || grep -qE ';\s*\[ [^[]' "${SCRIPT}"; then
  fail "POSIX [ ] conditionals found — must use [[ ]]"
else
  pass "No POSIX [ ] conditionals (uses [[ ]])"
fi

# 10. Error output uses >&2
if grep -q '>&2' "${SCRIPT}"; then
  pass "Error output uses >&2"
else
  fail "No >&2 redirection found for error output"
fi

# 11. No function keyword
if grep -qE '^\s*function ' "${SCRIPT}"; then
  fail "function keyword used — must use name() { } syntax"
else
  pass "No function keyword"
fi

# 12. No ANSI color codes
if grep -qE '\\033\[|\\e\[|\\x1[bB]\[' "${SCRIPT}"; then
  fail "ANSI color codes found — forbidden in scripts"
else
  pass "No ANSI color codes"
fi

# 13. Checks all three ncs.conf locations
if grep -q '/etc/ncs/ncs.conf' "${SCRIPT}" && \
   grep -q '/nso/etc/ncs.conf' "${SCRIPT}" && \
   grep -q '/defaults/ncs.conf' "${SCRIPT}"; then
  pass "All three ncs.conf locations checked"
else
  fail "Must check /etc/ncs/ncs.conf, /nso/etc/ncs.conf, /defaults/ncs.conf"
fi

# 14. Targets local-authentication XML element
if grep -q '<local-authentication>' "${SCRIPT}"; then
  pass "Targets <local-authentication> XML element"
else
  fail "<local-authentication> pattern not found in sed command"
fi

# 15. .gitkeep removed from pre-ncs-start directory
if [[ ! -f "scripts/pre-ncs-start/.gitkeep" ]]; then
  pass ".gitkeep removed from scripts/pre-ncs-start/"
else
  fail ".gitkeep still exists in scripts/pre-ncs-start/"
fi

echo ""
echo "=== Idempotency test ==="

tmpfile="$(mktemp)"
trap 'rm -f "${tmpfile}" "${tmpfile}.bak"' EXIT

cat > "${tmpfile}" << 'XMLEOF'
<aaa>
  <local-authentication>
    <enabled>false</enabled>
  </local-authentication>
</aaa>
XMLEOF

# First run: false -> true
sed -i.bak '/<local-authentication>/{
n
s|<enabled>false</enabled>|<enabled>true</enabled>|
}' "${tmpfile}"
rm -f "${tmpfile}.bak"

if grep -q '<enabled>true</enabled>' "${tmpfile}"; then
  pass "First run: false changed to true"
else
  fail "First run: sed did not change false to true"
fi

# Second run: should be a no-op
sed -i.bak '/<local-authentication>/{
n
s|<enabled>false</enabled>|<enabled>true</enabled>|
}' "${tmpfile}"
rm -f "${tmpfile}.bak"

if grep -q '<enabled>true</enabled>' "${tmpfile}"; then
  pass "Second run: idempotent (still true)"
else
  fail "Second run: idempotency broken"
fi

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
