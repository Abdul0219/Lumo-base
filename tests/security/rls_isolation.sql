-- tests/security/rls_isolation.sql
-- Positive + negative authorization tests. Run via run-security-tests.sh, which
-- supplies psql variables: :'user_a' :'user_b' :'user_c' :'ws_a' :'ws_b' :'doc_a' :'doc_b'
--
-- Every CRUD verb, the RPC-only write path, anon and service_role are exercised.
-- A violation RAISES an exception -> psql exits non-zero -> the phase gate fails.
--
-- Implementation note: psql does NOT interpolate :'vars' inside dollar-quoted
-- DO blocks, so fixtures live in a small lumo_test schema that every test role
-- can read. The schema is dropped at the end of the script.

\set ON_ERROR_STOP on
\echo '== Lumo Base RLS isolation suite =='

CREATE SCHEMA IF NOT EXISTS lumo_test;
CREATE TABLE IF NOT EXISTS lumo_test.fixture (key text primary key, val uuid not null);
TRUNCATE lumo_test.fixture;
INSERT INTO lumo_test.fixture (key, val) VALUES
  ('user_a', :'user_a'::uuid), ('user_b', :'user_b'::uuid), ('user_c', :'user_c'::uuid),
  ('ws_a',   :'ws_a'::uuid),   ('ws_b',   :'ws_b'::uuid),
  ('doc_a',  :'doc_a'::uuid),  ('doc_b',  :'doc_b'::uuid);

CREATE OR REPLACE FUNCTION lumo_test.assert_true(p_ok boolean, p_label text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT coalesce(p_ok, false) THEN
    RAISE EXCEPTION 'RLS TEST FAILED: %', p_label;
  END IF;
  RAISE NOTICE 'PASS: %', p_label;
END;
$$;

-- Both claim forms are set: upstream releases differ in how auth.uid() reads
-- the JWT. Verify against the pinned supabase/postgres init SQL before claiming
-- these tests prove anything.
GRANT USAGE ON SCHEMA lumo_test TO authenticated, anon, service_role;
GRANT SELECT ON lumo_test.fixture TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION lumo_test.assert_true(boolean, text) TO authenticated, anon, service_role;

-- ------------------------------------------------------------------ user A (workspace A)
BEGIN;
  SET LOCAL ROLE authenticated;
  SELECT set_config('request.jwt.claim.sub', (SELECT val::text FROM lumo_test.fixture WHERE key = 'user_a'), true);
  SELECT set_config('request.jwt.claims',
    json_build_object('role', 'authenticated', 'sub', (SELECT val::text FROM lumo_test.fixture WHERE key = 'user_a'))::text, true);

  SELECT lumo_test.assert_true(
    (SELECT count(*) = 1 FROM app.documents WHERE id = (SELECT val FROM lumo_test.fixture WHERE key = 'doc_a')),
    'A can SELECT own document');
  SELECT lumo_test.assert_true(
    (SELECT count(*) = 1 FROM app.documents WHERE id = (SELECT val FROM lumo_test.fixture WHERE key = 'doc_b')),
    'A can SELECT B document in the SAME workspace');
  SELECT lumo_test.assert_true(
    (SELECT count(*) = 1 FROM app.workspaces WHERE id = (SELECT val FROM lumo_test.fixture WHERE key = 'ws_a')),
    'A can SELECT own workspace');
  SELECT lumo_test.assert_true(
    (SELECT count(*) = 0 FROM app.workspaces WHERE id = (SELECT val FROM lumo_test.fixture WHERE key = 'ws_b')),
    'A cannot SELECT workspace B');

  DO $$
  DECLARE v_doc uuid; v_user_b uuid;
  BEGIN
    SELECT val INTO v_doc   FROM lumo_test.fixture WHERE key = 'doc_b';
    SELECT val INTO v_user_b FROM lumo_test.fixture WHERE key = 'user_b';

    BEGIN
      UPDATE app.documents SET body = 'hijacked' WHERE id = v_doc;
      IF (SELECT count(*) FROM app.documents WHERE id = v_doc AND body = 'hijacked') > 0 THEN
        RAISE EXCEPTION 'RLS TEST FAILED: A updated B document';
      END IF;
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN NULL;
    END;
    PERFORM lumo_test.assert_true(true, 'A cannot UPDATE B document');

    BEGIN
      DELETE FROM app.documents WHERE id = v_doc;
      IF (SELECT count(*) FROM app.documents WHERE id = v_doc) = 0 THEN
        RAISE EXCEPTION 'RLS TEST FAILED: A deleted B document';
      END IF;
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN NULL;
    END;
    PERFORM lumo_test.assert_true(true, 'A cannot DELETE B document');

    BEGIN
      INSERT INTO app.documents (workspace_id, owner_id, title)
      VALUES ((SELECT val FROM lumo_test.fixture WHERE key = 'ws_a'), v_user_b, 'spoofed owner');
      RAISE EXCEPTION 'RLS TEST FAILED: INSERT with owner_id = B succeeded';
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN NULL;
    END;
    PERFORM lumo_test.assert_true(true, 'INSERT with another owner rejected');
  END $$;
ROLLBACK;

-- ------------------------------------------------------------------ user C (different workspace)
BEGIN;
  SET LOCAL ROLE authenticated;
  SELECT set_config('request.jwt.claim.sub', (SELECT val::text FROM lumo_test.fixture WHERE key = 'user_c'), true);
  SELECT set_config('request.jwt.claims',
    json_build_object('role', 'authenticated', 'sub', (SELECT val::text FROM lumo_test.fixture WHERE key = 'user_c'))::text, true);

  SELECT lumo_test.assert_true((SELECT count(*) = 0 FROM app.documents),  'C sees zero documents from workspace A');
  SELECT lumo_test.assert_true((SELECT count(*) = 0 FROM app.workspaces), 'C sees zero workspaces');
  SELECT lumo_test.assert_true((SELECT count(*) = 0 FROM app.memberships),'C sees zero memberships');

  DO $$
  BEGIN
    BEGIN
      INSERT INTO app.documents (workspace_id, owner_id, title)
      VALUES ((SELECT val FROM lumo_test.fixture WHERE key = 'ws_a'),
              (SELECT val FROM lumo_test.fixture WHERE key = 'user_c'), 'cross-tenant insert');
      RAISE EXCEPTION 'RLS TEST FAILED: C inserted into workspace A';
    EXCEPTION WHEN insufficient_privilege OR check_violation THEN NULL;
    END;
    PERFORM lumo_test.assert_true(true, 'cross-workspace INSERT denied');

    BEGIN
      INSERT INTO app.workspaces (name) VALUES ('direct insert');
      RAISE EXCEPTION 'RLS TEST FAILED: direct workspace INSERT bypassed the RPC';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM lumo_test.assert_true(true, 'direct workspace INSERT denied (RPC-only write path)');
  END $$;
ROLLBACK;

-- ------------------------------------------------------------------ anon
BEGIN;
  SET LOCAL ROLE anon;
  SELECT lumo_test.assert_true((SELECT count(*) = 0 FROM app.documents), 'anon sees zero documents');
  SELECT lumo_test.assert_true((SELECT count(*) = 0 FROM app.workspaces), 'anon sees zero workspaces');
ROLLBACK;

-- ------------------------------------------------------------------ service_role
BEGIN;
  SET LOCAL ROLE service_role;
  SELECT lumo_test.assert_true((SELECT count(*) >= 2 FROM app.documents),
    'service_role bypasses RLS (server-side only)');
ROLLBACK;

DROP SCHEMA lumo_test CASCADE;
\echo '== ALL RLS ISOLATION CHECKS PASSED =='
