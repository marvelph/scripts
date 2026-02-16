#!/usr/bin/env bash
set -euo pipefail

# End-to-end test for postgres-switch.
# Required commands: psql, pg_dump, python3
#
# Optional env vars:
#   PG_TEST_HOST
#   PG_TEST_PORT
#   PG_TEST_USER
#   PG_TEST_PASSWORD
#   POSTGRES_SWITCH_BIN (default: ./postgres-switch)

PG_TEST_HOST="${PG_TEST_HOST:-}"
PG_TEST_PORT="${PG_TEST_PORT:-}"
PG_TEST_USER="${PG_TEST_USER:-}"
PG_TEST_PASSWORD="${PG_TEST_PASSWORD:-}"
POSTGRES_SWITCH_BIN="${POSTGRES_SWITCH_BIN:-./postgres-switch}"

DB_NAME="pswitch_e2e_$(date +%Y%m%d%H%M%S)_$$"
DEV_DB="${DB_NAME}__develop"
MAIN_DB="${DB_NAME}__main"

PSQL_ARGS=(
)
SWITCH_ARGS=(
)

if [[ -n "${PG_TEST_HOST}" ]]; then
  PSQL_ARGS+=("--host" "${PG_TEST_HOST}")
  SWITCH_ARGS+=("--host" "${PG_TEST_HOST}")
fi
if [[ -n "${PG_TEST_PORT}" ]]; then
  PSQL_ARGS+=("--port" "${PG_TEST_PORT}")
  SWITCH_ARGS+=("--port" "${PG_TEST_PORT}")
fi
if [[ -n "${PG_TEST_USER}" ]]; then
  PSQL_ARGS+=("--username" "${PG_TEST_USER}")
  SWITCH_ARGS+=("--user" "${PG_TEST_USER}")
fi
if [[ -n "${PG_TEST_PASSWORD}" ]]; then
  export PGPASSWORD="${PG_TEST_PASSWORD}"
  SWITCH_ARGS+=("--password" "${PG_TEST_PASSWORD}")
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

psql_q() {
  local sql="$1"
  if (( ${#PSQL_ARGS[@]} )); then
    psql "${PSQL_ARGS[@]}" --dbname=postgres -v ON_ERROR_STOP=1 -X -q -t -A -F $'\t' -c "${sql}"
  else
    psql --dbname=postgres -v ON_ERROR_STOP=1 -X -q -t -A -F $'\t' -c "${sql}"
  fi
}

psql_db_q() {
  local db="$1"
  local sql="$2"
  if (( ${#PSQL_ARGS[@]} )); then
    psql "${PSQL_ARGS[@]}" "--dbname=${db}" -v ON_ERROR_STOP=1 -X -q -t -A -F $'\t' -c "${sql}"
  else
    psql "--dbname=${db}" -v ON_ERROR_STOP=1 -X -q -t -A -F $'\t' -c "${sql}"
  fi
}

switch_exec() {
  if (( ${#SWITCH_ARGS[@]} )); then
    "${POSTGRES_SWITCH_BIN}" "${SWITCH_ARGS[@]}" "$@"
  else
    "${POSTGRES_SWITCH_BIN}" "$@"
  fi
}

drop_db_force() {
  local db="$1"
  psql_q "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db}' AND pid <> pg_backend_pid();" >/dev/null || true
  psql_q "DROP DATABASE IF EXISTS \"${db}\";" >/dev/null || true
}

cleanup() {
  set +e
  switch_exec reset --database "${DB_NAME}" --yes >/dev/null 2>&1 || true
  drop_db_force "${DB_NAME}"
  drop_db_force "${MAIN_DB}"
  drop_db_force "${DEV_DB}"
}
trap cleanup EXIT

echo "[1/7] connectivity check"
psql_q "SELECT 1;" >/dev/null

echo "[2/7] prepare base database"
cleanup
BASE_ENCODING="$(psql_q "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = 'template0';" | tr -d '[:space:]')"
BASE_COLLATION="$(psql_q "SELECT datcollate FROM pg_database WHERE datname = 'template0';" | tr -d '[:space:]')"
BASE_CTYPE="$(psql_q "SELECT datctype FROM pg_database WHERE datname = 'template0';" | tr -d '[:space:]')"
psql_q "CREATE DATABASE \"${DB_NAME}\" TEMPLATE template0 ENCODING '${BASE_ENCODING}' LC_COLLATE '${BASE_COLLATION}' LC_CTYPE '${BASE_CTYPE}';" >/dev/null
psql_db_q "${DB_NAME}" "CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT NOT NULL);"
psql_db_q "${DB_NAME}" "INSERT INTO users(name) VALUES ('alice'),('bob');"
psql_db_q "${DB_NAME}" "CREATE VIEW v_user_names AS SELECT name FROM users;"
psql_db_q "${DB_NAME}" "CREATE FUNCTION f_add(x INT, y INT) RETURNS INT LANGUAGE SQL IMMUTABLE AS 'SELECT x + y';"

echo "[3/7] init + branch-add"
switch_exec init --database "${DB_NAME}" --branch main
switch_exec branch-add --database "${DB_NAME}" --branch develop

echo "[4/7] verify copied objects in develop snapshot"
dev_count="$(psql_db_q "${DEV_DB}" "SELECT COUNT(*) FROM users;" | tr -d '[:space:]')"
dev_view_count="$(psql_db_q "${DEV_DB}" "SELECT COUNT(*) FROM v_user_names;" | tr -d '[:space:]')"
dev_func="$(psql_db_q "${DEV_DB}" "SELECT f_add(2,3);" | tr -d '[:space:]')"
dev_encoding="$(psql_q "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = '${DEV_DB}';" | tr -d '[:space:]')"
dev_collation="$(psql_q "SELECT datcollate FROM pg_database WHERE datname = '${DEV_DB}';" | tr -d '[:space:]')"
dev_ctype="$(psql_q "SELECT datctype FROM pg_database WHERE datname = '${DEV_DB}';" | tr -d '[:space:]')"
assert_eq "2" "${dev_count}" "develop snapshot users count"
assert_eq "2" "${dev_view_count}" "develop snapshot view count"
assert_eq "5" "${dev_func}" "develop snapshot function value"
assert_eq "${BASE_ENCODING}" "${dev_encoding}" "develop snapshot encoding"
assert_eq "${BASE_COLLATION}" "${dev_collation}" "develop snapshot collation"
assert_eq "${BASE_CTYPE}" "${dev_ctype}" "develop snapshot ctype"

echo "[5/7] mutate current(main) then switch to develop"
psql_db_q "${DB_NAME}" "INSERT INTO users(name) VALUES ('carol');"
switch_exec switch --database "${DB_NAME}" --branch develop

echo "[6/7] verify switch results"
current_count="$(psql_db_q "${DB_NAME}" "SELECT COUNT(*) FROM users;" | tr -d '[:space:]')"
main_count="$(psql_db_q "${MAIN_DB}" "SELECT COUNT(*) FROM users;" | tr -d '[:space:]')"
current_func="$(psql_db_q "${DB_NAME}" "SELECT f_add(7,8);" | tr -d '[:space:]')"
current_view_count="$(psql_db_q "${DB_NAME}" "SELECT COUNT(*) FROM v_user_names;" | tr -d '[:space:]')"
current_encoding="$(psql_q "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = '${DB_NAME}';" | tr -d '[:space:]')"
current_collation="$(psql_q "SELECT datcollate FROM pg_database WHERE datname = '${DB_NAME}';" | tr -d '[:space:]')"
current_ctype="$(psql_q "SELECT datctype FROM pg_database WHERE datname = '${DB_NAME}';" | tr -d '[:space:]')"
main_encoding="$(psql_q "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = '${MAIN_DB}';" | tr -d '[:space:]')"
main_collation="$(psql_q "SELECT datcollate FROM pg_database WHERE datname = '${MAIN_DB}';" | tr -d '[:space:]')"
main_ctype="$(psql_q "SELECT datctype FROM pg_database WHERE datname = '${MAIN_DB}';" | tr -d '[:space:]')"
assert_eq "2" "${current_count}" "current(develop) users count"
assert_eq "3" "${main_count}" "main snapshot users count"
assert_eq "15" "${current_func}" "current(develop) function value"
assert_eq "2" "${current_view_count}" "current(develop) view count"
assert_eq "${BASE_ENCODING}" "${current_encoding}" "current(develop) encoding"
assert_eq "${BASE_COLLATION}" "${current_collation}" "current(develop) collation"
assert_eq "${BASE_CTYPE}" "${current_ctype}" "current(develop) ctype"
assert_eq "${BASE_ENCODING}" "${main_encoding}" "main snapshot encoding"
assert_eq "${BASE_COLLATION}" "${main_collation}" "main snapshot collation"
assert_eq "${BASE_CTYPE}" "${main_ctype}" "main snapshot ctype"

echo "[7/7] branch-remove + reset"
switch_exec branch-remove --database "${DB_NAME}" --branch main --yes
switch_exec reset --database "${DB_NAME}" --yes

echo "E2E PASS: ${DB_NAME}"
