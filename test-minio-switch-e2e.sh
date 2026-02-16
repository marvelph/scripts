#!/usr/bin/env bash
set -euo pipefail

# End-to-end test for minio-switch.
# Required: mc, python3, local MinIO alias configured in mc
#
# Optional env vars:
#   MINIO_TEST_ALIAS (default: local)
#   MINIO_SWITCH_BIN (default: ./minio-switch)

MINIO_TEST_ALIAS="${MINIO_TEST_ALIAS:-local}"
MINIO_SWITCH_BIN="${MINIO_SWITCH_BIN:-./minio-switch}"

BUCKET="mswitch-e2e-$(date +%Y%m%d%H%M%S)-$$"
MAIN_SNAPSHOT="${BUCKET}--main"
DEV_SNAPSHOT="${BUCKET}--develop"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "ASSERTION FAILED: ${message}" >&2
    echo "  missing: ${needle}" >&2
    echo "  actual : ${haystack}" >&2
    exit 1
  fi
}

bucket_exists() {
  mc ls "${MINIO_TEST_ALIAS}/$1" >/dev/null 2>&1
}

cleanup() {
  set +e
  "${MINIO_SWITCH_BIN}" --alias "${MINIO_TEST_ALIAS}" reset --bucket "${BUCKET}" --yes >/dev/null 2>&1 || true
  mc rb --force "${MINIO_TEST_ALIAS}/${BUCKET}" >/dev/null 2>&1 || true
  mc rb --force "${MINIO_TEST_ALIAS}/${MAIN_SNAPSHOT}" >/dev/null 2>&1 || true
  mc rb --force "${MINIO_TEST_ALIAS}/${DEV_SNAPSHOT}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[1/8] connectivity check"
mc ls "${MINIO_TEST_ALIAS}" >/dev/null

echo "[2/8] prepare base bucket and seed objects"
cleanup
mc mb "${MINIO_TEST_ALIAS}/${BUCKET}" >/dev/null
printf 'hello-main\n' > "${TMP_DIR}/hello.txt"
printf 'public-main\n' > "${TMP_DIR}/public.txt"
mc cp "${TMP_DIR}/hello.txt" "${MINIO_TEST_ALIAS}/${BUCKET}/private/hello.txt" >/dev/null
mc cp "${TMP_DIR}/public.txt" "${MINIO_TEST_ALIAS}/${BUCKET}/public/hello.txt" >/dev/null
mc anonymous set download "${MINIO_TEST_ALIAS}/${BUCKET}/public" >/dev/null
policy_before="$(mc anonymous get "${MINIO_TEST_ALIAS}/${BUCKET}" 2>/dev/null || true)"

# smoke check for seeded object
seeded="$(mc cat "${MINIO_TEST_ALIAS}/${BUCKET}/private/hello.txt")"
assert_eq "hello-main" "${seeded}" "seeded object content"

echo "[3/8] init + branch-add"
"${MINIO_SWITCH_BIN}" --alias "${MINIO_TEST_ALIAS}" init --bucket "${BUCKET}" --branch main
"${MINIO_SWITCH_BIN}" --alias "${MINIO_TEST_ALIAS}" branch-add --bucket "${BUCKET}" --branch develop

if ! bucket_exists "${DEV_SNAPSHOT}"; then
  echo "ASSERTION FAILED: develop snapshot bucket not created" >&2
  exit 1
fi

echo "[4/8] verify copied objects in develop snapshot"
dev_obj="$(mc cat "${MINIO_TEST_ALIAS}/${DEV_SNAPSHOT}/private/hello.txt")"
assert_eq "hello-main" "${dev_obj}" "develop snapshot object content"


echo "[5/8] mutate current(main)"
printf 'main-only\n' > "${TMP_DIR}/main-only.txt"
mc cp "${TMP_DIR}/main-only.txt" "${MINIO_TEST_ALIAS}/${BUCKET}/private/main-only.txt" >/dev/null
mc rm "${MINIO_TEST_ALIAS}/${BUCKET}/public/hello.txt" >/dev/null

echo "[6/8] switch to develop"
"${MINIO_SWITCH_BIN}" --alias "${MINIO_TEST_ALIAS}" switch --bucket "${BUCKET}" --branch develop

echo "[7/8] verify switched contents and main snapshot"
current_obj="$(mc cat "${MINIO_TEST_ALIAS}/${BUCKET}/private/hello.txt")"
assert_eq "hello-main" "${current_obj}" "current(develop) object content"

if mc stat "${MINIO_TEST_ALIAS}/${BUCKET}/private/main-only.txt" >/dev/null 2>&1; then
  echo "ASSERTION FAILED: main-only object should not exist after switch to develop" >&2
  exit 1
fi

main_snapshot_obj="$(mc cat "${MINIO_TEST_ALIAS}/${MAIN_SNAPSHOT}/private/main-only.txt")"
assert_eq "main-only" "${main_snapshot_obj}" "main snapshot preserves mutation"


echo "[8/8] verify policy remains on logical bucket"
policy_after="$(mc anonymous get "${MINIO_TEST_ALIAS}/${BUCKET}" 2>/dev/null || true)"
assert_eq "${policy_before}" "${policy_after}" "bucket anonymous policy should remain unchanged"
assert_contains "${policy_after}" "${BUCKET}" "policy output references logical bucket"

"${MINIO_SWITCH_BIN}" --alias "${MINIO_TEST_ALIAS}" branch-remove --bucket "${BUCKET}" --branch main --yes
"${MINIO_SWITCH_BIN}" --alias "${MINIO_TEST_ALIAS}" reset --bucket "${BUCKET}" --yes

echo "E2E PASS: ${MINIO_TEST_ALIAS}/${BUCKET}"
