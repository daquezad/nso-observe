#!/bin/bash
set -euo pipefail

USERS_XML="init/users.xml"
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

echo "=== init/users.xml static validation ==="

# 1. File exists
if [[ -f "${USERS_XML}" ]]; then
  pass "users.xml exists"
else
  fail "users.xml does not exist: ${USERS_XML}"
  echo "RESULT: ${PASS} passed, ${FAIL} failed"
  exit 1
fi

# 2. XML is well-formed (requires xmllint)
if command -v xmllint > /dev/null 2>&1; then
  if xmllint --noout "${USERS_XML}" 2>/dev/null; then
    pass "XML is well-formed (xmllint)"
  else
    fail "XML is not well-formed"
  fi
else
  pass "xmllint not available — skipping well-formedness check"
fi

# 3. Config namespace declaration
if grep -q 'xmlns="http://tail-f.com/ns/config/1.0"' "${USERS_XML}"; then
  pass "Config namespace (http://tail-f.com/ns/config/1.0) present"
else
  fail "Config namespace missing"
fi

# 4. AAA namespace declaration
if grep -q 'xmlns="http://tail-f.com/ns/aaa/1.1"' "${USERS_XML}"; then
  pass "AAA namespace (http://tail-f.com/ns/aaa/1.1) present"
else
  fail "AAA namespace missing"
fi

# 5. Operator user name is 'oper'
if grep -q '<name>oper</name>' "${USERS_XML}"; then
  pass "Operator user name is 'oper'"
else
  fail "Operator user name 'oper' not found"
fi

# 6. Password uses $0$ cleartext prefix
if grep -q '<password>\$0\$' "${USERS_XML}"; then
  pass "Password uses \$0\$ cleartext prefix"
else
  fail "Password does not use \$0\$ cleartext prefix"
fi

# 7. All mandatory AAA user fields present
for field in name uid gid password ssh_keydir homedir; do
  if grep -q "<${field}>" "${USERS_XML}"; then
    pass "Mandatory field '${field}' present"
  else
    fail "Mandatory field '${field}' missing"
  fi
done

# 13. No tab characters (must use spaces)
if grep -q '	' "${USERS_XML}"; then
  fail "Tab characters found — must use 2-space indentation"
else
  pass "No tab characters (uses space indentation)"
fi

# 14. Uses 2-space indent increments (no odd indentation)
if grep -nE '^( {1}| {3}| {5}| {7}| {9}| {11})<' "${USERS_XML}" | grep -q .; then
  fail "Odd-space indentation found — must use 2-space increments"
else
  pass "Indentation uses 2-space increments"
fi

# 15. .gitkeep removed from init directory
if [[ ! -f "init/.gitkeep" ]]; then
  pass ".gitkeep removed from init/"
else
  fail ".gitkeep still exists in init/"
fi

# 16. No admin user defined (admin is created by run-nso.sh)
if grep -q '<name>admin</name>' "${USERS_XML}"; then
  fail "Admin user found — admin is created by run-nso.sh, not CDB init XML"
else
  pass "No admin user in CDB init XML"
fi

# 17. Compose config still validates with users.xml present
if command -v docker > /dev/null 2>&1; then
  if docker compose config > /dev/null 2>&1; then
    pass "docker compose config validates"
  else
    fail "docker compose config fails"
  fi
else
  pass "docker not available — skipping compose validation"
fi

echo ""
echo "=== RESULT: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
