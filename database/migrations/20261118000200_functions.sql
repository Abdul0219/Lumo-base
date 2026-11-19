-- Migration: 20261118000200_functions.sql
-- SECURITY DEFINER functions are the ONLY way to write to app.workspaces.
-- This keeps workspace creation and owner membership atomic and prevents clients
-- from asserting membership or tenant identifiers.

create or replace function app.is_workspace_member(p_workspace_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from app.memberships m
        where m.workspace_id = p_workspace_id
          and m.user_id = p_user_id
    );
$$;

revoke all on function app.is_workspace_member(uuid, uuid) from public;
grant execute on function app.is_workspace_member(uuid, uuid) to authenticated;

create or replace function app.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists documents_touch_updated_at on app.documents;
create trigger documents_touch_updated_at
    before update on app.documents
    for each row execute function app.touch_updated_at();

-- Workspace creation is an RPC, never a direct INSERT.
-- auth.uid() comes from the verified JWT claim, never from client input.
create or replace function app.create_workspace(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_workspace uuid;
begin
    if v_user is null then
        raise exception 'authentication required' using errcode = '42501';
    end if;
    if p_name is null or char_length(p_name) not between 1 and 120 then
        raise exception 'invalid workspace name' using errcode = '22023';
    end if;

    insert into app.workspaces (name) values (p_name)
    returning id into v_workspace;

    insert into app.memberships (workspace_id, user_id, role)
    values (v_workspace, v_user, 'owner');

    return v_workspace;
end;
$$;

revoke all on function app.create_workspace(text) from public;
grant execute on function app.create_workspace(text) to authenticated;

comment on function app.create_workspace(text) is
    'Atomically creates a workspace and an owner membership for auth.uid(). No client-supplied tenant or role.';
