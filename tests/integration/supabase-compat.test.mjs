// Lumo Base SDK conformance suite — REAL supabase-js against a running stack.
// No mocks. No stubs. If the stack is not configured, tests SKIP (they never
// fabricate a pass). Compatibility claims in docs/COMPATIBILITY.md are only
// valid for the pinned @supabase/supabase-js version with these tests passing.
//
// Required runtime env (never stored in this repo):
//   LUMO_SUPABASE_URL, LUMO_PUBLISHABLE_KEY, LUMO_SERVICE_KEY
//
// Run: npm ci && npm test

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.LUMO_SUPABASE_URL;
const PUBLISHABLE = process.env.LUMO_PUBLISHABLE_KEY;
const SECRET = process.env.LUMO_SERVICE_KEY;
const configured = Boolean(URL && PUBLISHABLE && SECRET);
const skip = configured ? false : 'set LUMO_SUPABASE_URL, LUMO_PUBLISHABLE_KEY and LUMO_SERVICE_KEY';
const opts = (name) => ({ skip, timeout: 30000 });

const suffix = Date.now().toString(36);
const emailA = `lumo-a-${suffix}@example.invalid`;
const emailB = `lumo-b-${suffix}@example.invalid`;
const password = `Lumo!Test-${suffix}-x9`;
const bucket = `lumo-compat-${suffix}`;

let admin, userA, userB, idA, idB, workspaceId, documentId, objectPath;

before(async () => {
  if (!configured) return;
  admin = createClient(URL, SECRET, { auth: { persistSession: false } });
  userA = createClient(URL, PUBLISHABLE, { auth: { persistSession: false } });
  userB = createClient(URL, PUBLISHABLE, { auth: { persistSession: false } });

  for (const [email, slot] of [[emailA, 'a'], [emailB, 'b']]) {
    const { data, error } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,
    });
    assert.ifError(error);
    if (slot === 'a') idA = data.user.id; else idB = data.user.id;
  }

  const { error: bucketErr } = await admin.storage.createBucket(bucket, { public: false });
  assert.ifError(bucketErr);
});

after(async () => {
  if (!configured || !admin) return;
  try { await admin.storage.deleteBucket(bucket); } catch { /* best effort */ }
  for (const id of [idA, idB]) {
    if (id) { try { await admin.auth.admin.deleteUser(id); } catch { /* best effort */ } }
  }
});

test('auth: sign in, getSession, refresh, invalid token, sign out', opts(), async () => {
  const { data: signIn, error } = await userA.auth.signInWithPassword({ email: emailA, password });
  assert.ifError(error);
  assert.ok(signIn.session?.access_token, 'access token present');
  assert.equal(signIn.user.id, idA);

  const { data: session } = await userA.auth.getSession();
  assert.equal(session.session?.user.id, idA);

  const { data: refreshed, error: refreshErr } = await userA.auth.refreshSession();
  assert.ifError(refreshErr);
  assert.ok(refreshed.session?.access_token);

  const { data: bogus, error: bogusErr } = await admin.auth.getUser('not-a-real-jwt');
  assert.ok(bogusErr || !bogus?.user, 'invalid signature must not yield a user');

  const { error: signOutErr } = await userA.auth.signOut();
  assert.ifError(signOutErr);
});

test('REST: select, filters, insert, update, delete via PostgREST', opts(), async () => {
  await userA.auth.signInWithPassword({ email: emailA, password });
  const { data: ws, error: rpcErr } = await userA.rpc('create_workspace', { p_name: `compat-${suffix}` });
  assert.ifError(rpcErr);
  workspaceId = ws;

  const { data: inserted, error: insErr } = await userA
    .from('documents').insert({ workspace_id: workspaceId, title: 'conformance', body: 'v1' })
    .select().single();
  assert.ifError(insErr);
  documentId = inserted.id;
  assert.equal(inserted.owner_id, idA, 'owner is derived server-side from auth.uid()');

  const { data: filtered, error: filterErr } = await userA
    .from('documents').select('id,title').eq('title', 'conformance').limit(10);
  assert.ifError(filterErr);
  assert.ok(filtered.some((r) => r.id === documentId), 'eq filter works');

  const { data: ordered, error: orderErr } = await userA
    .from('documents').select('*').order('created_at', { ascending: false }).limit(5);
  assert.ifError(orderErr);
  assert.ok(Array.isArray(ordered));

  const { error: updErr } = await userA
    .from('documents').update({ body: 'v2' }).eq('id', documentId);
  assert.ifError(updErr);

  const { error: delErr } = await userA
    .from('documents').delete().eq('id', documentId);
  assert.ifError(delErr);
  documentId = undefined;
});

test('RLS: user B cannot read or write user A workspace', opts(), async () => {
  await userB.auth.signInWithPassword({ email: emailB, password });
  const { data, error } = await userB
    .from('documents').select('*').eq('workspace_id', workspaceId);
  // PostgREST returns an empty array for RLS-denied SELECT (not an error).
  assert.ifError(error);
  assert.equal(data.length, 0, 'cross-workspace SELECT must return zero rows');

  const { error: insErr, data: insData } = await userB
    .from('documents').insert({ workspace_id: workspaceId, title: 'intrusion' }).select();
  assert.ok(insErr || !insData?.length, 'cross-workspace INSERT must be denied');
});

test('error format: PostgREST-shaped error object', opts(), async () => {
  const { error } = await userA.from('documents').select('column_that_does_not_exist');
  assert.ok(error, 'unknown column must error');
  assert.equal(typeof error.message, 'string');
  assert.ok('code' in error || 'details' in error || 'hint' in error,
    'error carries PostgREST fields (code/details/hint)');
});

test('Storage: upload, list, download, signed URL, cross-user denial', opts(), async () => {
  await userA.auth.signInWithPassword({ email: emailA, password });
  objectPath = `${idA}/conformance.txt`;
  const payload = new Blob(['lumo base conformance\n'], { type: 'text/plain' });

  const { error: upErr } = await userA.storage.from(bucket).upload(objectPath, payload);
  assert.ifError(upErr);

  const { data: listed, error: listErr } = await userA.storage.from(bucket).list(`${idA}/`);
  assert.ifError(listErr);
  assert.ok(listed.some((o) => o.name === 'conformance.txt'));

  const { data: blob, error: dlErr } = await userA.storage.from(bucket).download(objectPath);
  assert.ifError(dlErr);
  assert.equal(await blob.text(), 'lumo base conformance\n');

  const { data: signed, error: signErr } = await userA.storage.from(bucket)
    .createSignedUrl(objectPath, 60);
  assert.ifError(signErr);
  assert.ok(signed?.signedUrl?.startsWith('http'));

  await userB.auth.signInWithPassword({ email: emailB, password });
  const { data: denied, error: deniedErr } = await userB.storage.from(bucket).download(objectPath);
  assert.ok(deniedErr || !denied, 'cross-user object download must be denied');
});

test('RPC create_workspace rejects unauthenticated calls', opts(), async () => {
  const anon = createClient(URL, PUBLISHABLE, { auth: { persistSession: false } });
  await anon.auth.signOut();
  const { error } = await anon.rpc('create_workspace', { p_name: 'should-fail' });
  assert.ok(error, 'unauthenticated RPC must fail');
});
