-- Policy file: 002_rls_policies.sql
-- Trusted claims only: every boundary derives from auth.uid() (verified JWT
-- claim) or from app.is_workspace_member(). No client-supplied role or tenant id.
-- Tests in tests/security/rls_isolation.sql prove cross-user and cross-tenant denial.

drop policy if exists "workspaces_select_members" on app.workspaces;
create policy "workspaces_select_members"
    on app.workspaces for select
    to authenticated
    using (app.is_workspace_member(id, auth.uid()));

drop policy if exists "memberships_select_own_workspaces" on app.memberships;
create policy "memberships_select_own_workspaces"
    on app.memberships for select
    to authenticated
    using (
        user_id = auth.uid()
        or app.is_workspace_member(workspace_id, auth.uid())
    );

-- Documents: read requires membership; write requires membership AND ownership.
drop policy if exists "documents_select_members" on app.documents;
create policy "documents_select_members"
    on app.documents for select
    to authenticated
    using (app.is_workspace_member(workspace_id, auth.uid()));

drop policy if exists "documents_insert_owner" on app.documents;
create policy "documents_insert_owner"
    on app.documents for insert
    to authenticated
    with check (
        owner_id = auth.uid()
        and app.is_workspace_member(workspace_id, auth.uid())
    );

drop policy if exists "documents_update_owner" on app.documents;
create policy "documents_update_owner"
    on app.documents for update
    to authenticated
    using (
        owner_id = auth.uid()
        and app.is_workspace_member(workspace_id, auth.uid())
    )
    with check (
        owner_id = auth.uid()
        and app.is_workspace_member(workspace_id, auth.uid())
    );

drop policy if exists "documents_delete_owner" on app.documents;
create policy "documents_delete_owner"
    on app.documents for delete
    to authenticated
    using (
        owner_id = auth.uid()
        and app.is_workspace_member(workspace_id, auth.uid())
    );

-- NOTE: no policies for anon. RLS is enabled with zero anon policies, so anon
-- sees nothing. Do not add a "read-only public" policy without a reviewed reason.
-- NOTE: do not add FORCE ROW LEVEL SECURITY on these tables; service_role must
-- continue to bypass RLS for migrations, seeding and verified restore drills.
