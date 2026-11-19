#!/usr/bin/env bash
# Lumo Base RLS isolation runner.
# Requires a running stack with migrations + policies applied.
# Test users MUST already exist in GoTrue (create them with the admin API and
# pass their UUIDs). We never INSERT into auth.users directly.
set -euo pipefail

: "${LUMO_DB_URL:?set LUMO_DB_URL (postgres/superuser connection, injected at runtime)}"
: "${LUMO_TEST_USER_A:?UUID of test user A}"
: "${LUMO_TEST_USER_B:?UUID of test user B}"
: "${LUMO_TEST_USER_C:?UUID of test user C}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_A="$(python3 -c 'import uuid; print(uuid.uuid4())')"
WS_B="$(python3 -c 'import uuid; print(uuid.uuid4())')"
DOC_A="$(python3 -c 'import uuid; print(uuid.uuid4())')"
DOC_B="$(python3 -c 'import uuid; print(uuid.uuid4())')"

COMMON=(-v "user_a=$LUMO_TEST_USER_A" -v "user_b=$LUMO_TEST_USER_B" -v "user_c=$LUMO_TEST_USER_C" \
        -v "ws_a=$WS_A" -v "ws_b=$WS_B" -v "doc_a=$DOC_A" -v "doc_b=$DOC_B")

cleanup() {
  echo "== cleaning up test fixtures =="
  psql "$LUMO_DB_URL" -q -v ON_ERROR_STOP=1 "${COMMON[@]}" <<'SQL' || true
DELETE FROM app.documents  WHERE id IN (:'doc_a'::uuid, :'doc_b'::uuid);
DELETE FROM app.memberships WHERE workspace_id IN (:'ws_a'::uuid, :'ws_b'::uuid);
DELETE FROM app.workspaces  WHERE id IN (:'ws_a'::uuid, :'ws_b'::uuid);
SQL
}
trap cleanup EXIT

echo "== seeding two workspaces, three users, two documents =="
psql "$LUMO_DB_URL" -q -v ON_ERROR_STOP=1 "${COMMON[@]}" <<'SQL'
INSERT INTO app.workspaces (id, name) VALUES
  (:'ws_a'::uuid, 'rls-test-a'), (:'ws_b'::uuid, 'rls-test-b');
INSERT INTO app.memberships (workspace_id, user_id, role) VALUES
  (:'ws_a'::uuid, :'user_a'::uuid, 'owner'),
  (:'ws_a'::uuid, :'user_b'::uuid, 'member'),
  (:'ws_b'::uuid, :'user_c'::uuid, 'owner');
INSERT INTO app.documents (id, workspace_id, owner_id, title, body) VALUES
  (:'doc_a'::uuid, :'ws_a'::uuid, :'user_a'::uuid, 'owned by A', 'original'),
  (:'doc_b'::uuid, :'ws_a'::uuid, :'user_b'::uuid, 'owned by B', 'original');
SQL

echo "== running isolation suite =="
psql "$LUMO_DB_URL" -v ON_ERROR_STOP=1 "${COMMON[@]}" -f "$SCRIPT_DIR/rls_isolation.sql"

echo "== PASS: RLS isolation suite =="
