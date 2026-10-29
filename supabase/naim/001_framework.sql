-- naim-local · 001 framework
-- One Supabase project for every local client system: one schema per system (hotel, duka, water, fruit), one
-- business_id per client, and row-level security that lets a person or an assistant see and change only their own
-- business. Who is asking comes from app_metadata in their sign-in token (business_id, app_role), which only our
-- server (Netlify Functions, service role) can set; a user can never edit it.
--
-- The founder runs this once in the SQL editor of the naim-local project (docs/NAIM-LOCAL.md), then each system's
-- own migrations create its tables and call naim.protect() on each one. Safe to run again.
-- Tested on a local Postgres with a stand-in for Supabase's auth.jwt(): supabase/naim-local/tests/framework_test.sql.

create schema if not exists naim;
revoke all on schema naim from public;
grant usage on schema naim to authenticated, service_role;

-- Who is asking: the business and the role in the token ('' / null when nobody is signed in).
-- A malformed business_id makes the cast fail, and the query with it: closed, never open.
create or replace function naim.business_id() returns uuid
  language sql stable set search_path = ''
  as $$ select nullif((select auth.jwt()) -> 'app_metadata' ->> 'business_id', '')::uuid $$;

create or replace function naim.app_role() returns text
  language sql stable set search_path = ''
  as $$ select coalesce((select auth.jwt()) -> 'app_metadata' ->> 'app_role', '') $$;

-- The clients on this project: one row per client per system. The founder's office sets plan and plan_state
-- (late-payment states from the agreements) through a Netlify Function with the service role.
create table if not exists naim.tenants (
  business_id uuid primary key default gen_random_uuid(),
  system text not null check (system in ('hotel', 'duka', 'water', 'fruit')),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,40}$'),
  name text not null,
  contract_number text,                                   -- e.g. NAS-AG-2026-0007
  plan text check (plan in ('msingi', 'biashara', 'sauti')),
  cycle text check (cycle in ('month', 'week', 'day')),
  plan_state text not null default 'active'
    check (plan_state in ('active', 'reminded', 'assistant_paused', 'read_only', 'ended')),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);
alter table naim.tenants enable row level security;
revoke all on naim.tenants from public, anon, authenticated;
grant select on naim.tenants to authenticated;
grant all on naim.tenants to service_role;
drop policy if exists tenants_own on naim.tenants;
create policy tenants_own on naim.tenants for select to authenticated
  using (business_id = (select naim.business_id()));

-- Writes are allowed while the plan allows them. read_only and ended keep reading and the export working:
-- data is never withheld because of payment.
create or replace function naim.can_write() returns boolean
  language sql stable set search_path = ''
  as $$ select exists (select 1 from naim.tenants t
                        where t.business_id = naim.business_id() and t.plan_state not in ('read_only', 'ended')) $$;

-- A system's schema, its grants, and the helpers its master prompt names:
--   <system>.current_business()  <system>.current_role()  (always schema-qualified: current_role alone is SQL's own)
--   <system>.my_plan             the signed-in business's plan and plan state (read-only banner in the app)
-- Tables get no access by default: naim.protect() grants each one, so a table nobody protected stays closed.
create or replace function naim.add_system(sch text) returns void
  language plpgsql set search_path = ''
as $$
begin
  if sch not in ('hotel', 'duka', 'water', 'fruit') then raise exception 'naim.add_system: unknown system %', sch; end if;
  execute format('create schema if not exists %I', sch);
  execute format('revoke all on schema %I from public, anon', sch);
  execute format('grant usage on schema %I to authenticated, service_role', sch);
  execute format('grant all on all tables in schema %I to service_role', sch);
  execute format('alter default privileges in schema %I grant all on tables to service_role', sch);
  execute format('alter default privileges in schema %I grant usage, select on sequences to authenticated, service_role', sch);
  execute format('alter default privileges in schema %I revoke execute on functions from public', sch);
  execute format('alter default privileges in schema %I grant execute on functions to authenticated, service_role', sch);
  execute format('create or replace function %I.current_business() returns uuid language sql stable set search_path = '''' as %L', sch, 'select naim.business_id()');
  execute format('create or replace function %I.current_role() returns text language sql stable set search_path = '''' as %L', sch, 'select naim.app_role()');
  execute format('grant execute on function %I.current_business(), %I.current_role() to authenticated, service_role', sch, sch);
  execute format('create or replace view %I.my_plan with (security_invoker = true) as '
                 'select plan, cycle, plan_state, contract_number from naim.tenants where business_id = naim.business_id()', sch);
  execute format('revoke all on %I.my_plan from public, anon', sch);
  execute format('grant select on %I.my_plan to authenticated', sch);
end $$;

-- The standard tenant policies for one table, e.g. select naim.protect('fruit', 'sales'):
--   read    own business (and, if readers is given, only those roles: costs and profit for the owner, say)
--   insert  own business, while the plan allows writes, by the writer roles
--   update  the same (not on append-only tables: corrections there are new rows)
--   delete  own business, while the plan allows writes, by the owner only (not on append-only tables)
-- Every table it protects must have a business_id uuid column; it also gets an index on it.
create or replace function naim.protect(
  sch text,
  tbl text,
  writers text[] default array['owner', 'seller', 'attendant', 'cashier', 'delivery', 'assistant_owner', 'assistant_staff'],
  readers text[] default null,
  append_only boolean default false
) returns void
  language plpgsql set search_path = ''
as $$
declare
  t text := format('%I.%I', sch, tbl);
  own text := 'business_id = (select naim.business_id())';
  can text := format('(select naim.can_write()) and (select naim.app_role()) = any (%L::text[])', writers);
  who text := case when readers is null then '' else format(' and (select naim.app_role()) = any (%L::text[])', readers) end;
begin
  if sch not in ('hotel', 'duka', 'water', 'fruit') then raise exception 'naim.protect: unknown system schema %', sch; end if;
  execute format('alter table %s enable row level security', t);
  execute format('drop policy if exists naim_read on %s', t);
  execute format('drop policy if exists naim_insert on %s', t);
  execute format('drop policy if exists naim_update on %s', t);
  execute format('drop policy if exists naim_delete on %s', t);
  execute format('create policy naim_read on %s for select to authenticated using (%s%s)', t, own, who);
  execute format('create policy naim_insert on %s for insert to authenticated with check (%s and %s)', t, own, can);
  execute format('revoke all on %s from public, anon, authenticated', t);
  if append_only then
    execute format('grant select, insert on %s to authenticated', t);
  else
    execute format('create policy naim_update on %s for update to authenticated using (%s and %s) with check (%s)', t, own, can, own);
    execute format('create policy naim_delete on %s for delete to authenticated using (%s and (select naim.can_write()) and (select naim.app_role()) = %L)', t, own, 'owner');
    execute format('grant select, insert, update, delete on %s to authenticated', t);
  end if;
  execute format('grant all on %s to service_role', t);
  execute format('create index if not exists %I on %s (business_id)', left(tbl, 50) || '_business_id_idx', t);
end $$;

-- Only the founder's migrations run the two builders; the helpers are for signed-in users and the server.
revoke all on function naim.add_system(text), naim.protect(text, text, text[], text[], boolean) from public;
revoke all on function naim.business_id(), naim.app_role(), naim.can_write() from public;
grant execute on function naim.business_id(), naim.app_role(), naim.can_write() to authenticated, service_role;
