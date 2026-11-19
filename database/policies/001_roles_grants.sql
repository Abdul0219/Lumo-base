-- Policy file: 001_roles_grants.sql
-- Explicit GRANTs. RLS is NOT a substitute for privileges - both are required.
-- Roles anon / authenticated / service_role are defined by upstream Supabase
-- init SQL. We GRANT here; we never CREATE or ALTER those roles.

-- Deny everything to anonymous by default; re-grant deliberately below.
revoke all on schema app from public, anon;
revoke all on all tables in schema app from public, anon;
revoke all on all functions in schema app from public, anon;

-- Authenticated users get schema access, then narrow table-level privileges.
grant usage on schema app to authenticated;
grant select on app.workspaces  to authenticated;
grant select on app.memberships to authenticated;
grant select, insert, update, delete on app.documents to authenticated;
grant usage, select on all sequences in schema app to authenticated;

-- No direct writes to workspaces or memberships. Those happen only through
-- app.create_workspace() (SECURITY DEFINER), which also writes the owner row.
revoke insert, update, delete on app.workspaces  from authenticated;
revoke insert, update, delete on app.memberships from authenticated;

-- service_role is server-side only. It bypasses RLS by design and must NEVER
-- be exposed to client code. Reserved for migrations, seeding and backups.
grant usage on schema app to service_role;
grant all on all tables in schema app to service_role;
grant all on all functions in schema app to service_role;
grant all on all sequences in schema app to service_role;

-- Future objects in app must not silently become world-readable.
alter default privileges in schema app
    revoke all on tables from public, anon;
alter default privileges in schema app
    revoke all on functions from public, anon;

-- Verification queries (run as postgres):
--   select relname, relrowsecurity from pg_class
--     where relnamespace = 'app'::regnamespace and relkind = 'r';
--   select table_name, grantee, string_agg(privilege_type, ',')
--     from information_schema.role_table_grants
--    where table_schema = 'app' group by 1, 2 order by 1, 2;
