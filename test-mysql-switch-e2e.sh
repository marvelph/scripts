#!/usr/bin/env bash
set -euo pipefail

# End-to-end test for mysql-switch.
# Required commands: mysql, mysqldump, python3
#
# Optional env vars:
#   MYSQL_TEST_HOST
#   MYSQL_TEST_PORT
#   MYSQL_TEST_USER
#   MYSQL_TEST_PASSWORD
#   MYSQL_SWITCH_BIN (default: ./mysql-switch)

MYSQL_TEST_HOST="${MYSQL_TEST_HOST:-}"
MYSQL_TEST_PORT="${MYSQL_TEST_PORT:-}"
MYSQL_TEST_USER="${MYSQL_TEST_USER:-}"
MYSQL_TEST_PASSWORD="${MYSQL_TEST_PASSWORD:-}"
MYSQL_SWITCH_BIN="${MYSQL_SWITCH_BIN:-./mysql-switch}"

DB_NAME="mswitch_e2e_$(date +%Y%m%d%H%M%S)_$$"
DEV_DB="${DB_NAME}__develop"
MASTER_DB="${DB_NAME}__master"

MYSQL_ARGS=(
)

SWITCH_ARGS=(
)
if [[ -n "${MYSQL_TEST_HOST}" ]]; then
  MYSQL_ARGS+=("--host" "${MYSQL_TEST_HOST}")
  SWITCH_ARGS+=("--host" "${MYSQL_TEST_HOST}")
fi
if [[ -n "${MYSQL_TEST_PORT}" ]]; then
  MYSQL_ARGS+=("--port" "${MYSQL_TEST_PORT}")
  SWITCH_ARGS+=("--port" "${MYSQL_TEST_PORT}")
fi
if [[ -n "${MYSQL_TEST_USER}" ]]; then
  MYSQL_ARGS+=("--user" "${MYSQL_TEST_USER}")
  SWITCH_ARGS+=("--user" "${MYSQL_TEST_USER}")
fi
if [[ -n "${MYSQL_TEST_PASSWORD}" ]]; then
  export MYSQL_PWD="${MYSQL_TEST_PASSWORD}"
  SWITCH_ARGS+=("--password" "${MYSQL_TEST_PASSWORD}")
fi

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "ASSERTION FAILED: ${message}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual  : ${actual}" >&2
    exit 1
  fi
}

mysql_q() {
  local sql="$1"
  mysql "${MYSQL_ARGS[@]}" -N -e "${sql}"
}

cleanup() {
  set +e
  "${MYSQL_SWITCH_BIN}" "${SWITCH_ARGS[@]}" reset --database "${DB_NAME}" --yes >/dev/null 2>&1 || true
  mysql "${MYSQL_ARGS[@]}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; DROP DATABASE IF EXISTS \`${MASTER_DB}\`; DROP DATABASE IF EXISTS \`${DEV_DB}\`;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[1/7] connectivity check"
mysql_q "SELECT 1;" >/dev/null

echo "[2/7] prepare base database"
mysql "${MYSQL_ARGS[@]}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; DROP DATABASE IF EXISTS \`${MASTER_DB}\`; DROP DATABASE IF EXISTS \`${DEV_DB}\`;"
mysql "${MYSQL_ARGS[@]}" -e "CREATE DATABASE \`${DB_NAME}\`;"
mysql "${MYSQL_ARGS[@]}" -e "CREATE TABLE \`${DB_NAME}\`.users (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(50));"
mysql "${MYSQL_ARGS[@]}" -e "INSERT INTO \`${DB_NAME}\`.users(name) VALUES ('alice'),('bob');"
mysql "${MYSQL_ARGS[@]}" -e "CREATE VIEW \`${DB_NAME}\`.v_user_names AS SELECT name FROM \`${DB_NAME}\`.users;"
mysql "${MYSQL_ARGS[@]}" -e "CREATE FUNCTION \`${DB_NAME}\`.f_add(x INT, y INT) RETURNS INT DETERMINISTIC RETURN x + y;"

echo "[3/7] init + branch-add"
"${MYSQL_SWITCH_BIN}" "${SWITCH_ARGS[@]}" init --database "${DB_NAME}" --branch master
"${MYSQL_SWITCH_BIN}" "${SWITCH_ARGS[@]}" branch-add --database "${DB_NAME}" --branch develop

echo "[4/7] verify copied objects in develop snapshot"
dev_count="$(mysql_q "SELECT COUNT(*) FROM \`${DEV_DB}\`.users;")"
dev_view_count="$(mysql_q "SELECT COUNT(*) FROM \`${DEV_DB}\`.v_user_names;")"
dev_func="$(mysql_q "SELECT \`${DEV_DB}\`.f_add(2,3);")"
assert_eq "2" "${dev_count}" "develop snapshot users count"
assert_eq "2" "${dev_view_count}" "develop snapshot view count"
assert_eq "5" "${dev_func}" "develop snapshot function value"

echo "[5/7] mutate current(master) then switch to develop"
mysql "${MYSQL_ARGS[@]}" -e "INSERT INTO \`${DB_NAME}\`.users(name) VALUES ('carol');"
"${MYSQL_SWITCH_BIN}" "${SWITCH_ARGS[@]}" switch --database "${DB_NAME}" --branch develop

echo "[6/7] verify switch results"
current_count="$(mysql_q "SELECT COUNT(*) FROM \`${DB_NAME}\`.users;")"
master_count="$(mysql_q "SELECT COUNT(*) FROM \`${MASTER_DB}\`.users;")"
current_func="$(mysql_q "SELECT \`${DB_NAME}\`.f_add(7,8);")"
current_view_count="$(mysql_q "SELECT COUNT(*) FROM \`${DB_NAME}\`.v_user_names;")"
assert_eq "2" "${current_count}" "current(develop) users count"
assert_eq "3" "${master_count}" "master snapshot users count"
assert_eq "15" "${current_func}" "current(develop) function value"
assert_eq "2" "${current_view_count}" "current(develop) view count"

echo "[7/7] branch-remove + reset"
"${MYSQL_SWITCH_BIN}" "${SWITCH_ARGS[@]}" branch-remove --database "${DB_NAME}" --branch master --yes
"${MYSQL_SWITCH_BIN}" "${SWITCH_ARGS[@]}" reset --database "${DB_NAME}" --yes

echo "E2E PASS: ${DB_NAME}"
