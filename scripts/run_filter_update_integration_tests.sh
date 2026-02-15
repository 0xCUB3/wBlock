#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-18765}"
BASE_URL="http://127.0.0.1:${PORT}"
SERVER_LOG="${ROOT_DIR}/scripts/.mock_filter_server.log"
TEST_BIN="/tmp/filter_update_http_tests"

python3 "${ROOT_DIR}/scripts/mock_filter_server.py" "${PORT}" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!
trap 'kill "${SERVER_PID}" >/dev/null 2>&1 || true' EXIT

for _ in {1..50}; do
    if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

if ! curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    echo "Mock server failed to start"
    cat "${SERVER_LOG}" || true
    exit 1
fi

swiftc \
    "${ROOT_DIR}/wBlockCoreService/FilterUpdateResponseClassifier.swift" \
    "${ROOT_DIR}/scripts/test_filter_update_http.swift" \
    -o "${TEST_BIN}"

"${TEST_BIN}" "${BASE_URL}"
