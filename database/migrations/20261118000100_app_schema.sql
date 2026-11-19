-- Migration: 20261118000100_app_schema.sql
-- Lumo Base APPLICATION schema. This is NOT an upstream Supabase schema.
-- Upstream roles (anon, authenticated, service_role) and auth.users are created by
-- the official supabase/postgres:17.6.1.136 init SQL - we never redefine them.
--
-- Design rule: PostgreSQL is the authoritative data AND authorization layer.
-- Tenant/workspace membership lives in the database. Clients never supply a
-- trusted role or tenant identifier; every boundary is derived from auth.uid().

create schema if not exists app;

create table if not exists app.workspaces (
    id          uuid primary key default gen_random_uuid(),
    name        text not null check (char_length(name) between 1 and 120),
    created_at  timestamptz not null default now()
);

create table if not exists app.memberships (
    workspace_id uuid not null references app.workspaces(id) on delete cascade,
    user_id      uuid not null references auth.users(id) on delete cascade,
    role         text not null default 'member'
                 check (role in ('owner', 'member')),
    created_at   timestamptz not null default now(),
    primary key (workspace_id, user_id)
);

create table if not exists app.documents (
    id            uuid primary key default gen_random_uuid(),
    workspace_id  uuid not null references app.workspaces(id) on delete cascade,
    owner_id      uuid not null references auth.users(id) on delete cascade,
    title         text not null check (char_length(title) between 1 and 200),
    body          text not null default '',
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists documents_workspace_id_idx
    on app.documents (workspace_id, created_at desc);
create index if not exists documents_owner_id_idx
    on app.documents (owner_id);
create index if not exists memberships_user_id_idx
    on app.memberships (user_id);

-- RLS is enabled here, BEFORE any policy exists (deny-by-default).
-- Policies are applied in database/policies/002_rls_policies.sql.
alter table app.workspaces  enable row level security;
alter table app.memberships enable row level security;
alter table app.documents   enable row level security;

comment on schema app is
    'Lumo Base application data. Every user-exposed table has RLS enabled and explicit GRANTs.';
