-- FaceFusion x Supabase schema
-- Run once in: Supabase Dashboard > SQL Editor. Safe to re-run (idempotent).
-- Security model: every row is owned by a signed-in user (auth.uid()).
-- The publishable key alone can read/write NOTHING; a user session is required.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- types
do $$ begin
	create type public.run_status as enum ('queued', 'running', 'completed', 'failed', 'cancelled');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------- helpers
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
	new.updated_at = now();
	return new;
end;
$$;

-- ---------------------------------------------------------------- runs
-- One row per processing run (headless, batch or UI).
create table if not exists public.runs
(
	id            uuid primary key default gen_random_uuid(),
	user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
	job_id        text,
	command       text not null default 'run',
	status        public.run_status not null default 'queued',
	processors    text[] not null default '{}',
	source_names  text[] not null default '{}',
	target_name   text,
	output_name   text,
	args          jsonb not null default '{}'::jsonb,
	error         text,
	started_at    timestamptz,
	finished_at   timestamptz,
	duration_ms   integer generated always as
	(
		case when started_at is not null and finished_at is not null
			then (extract(epoch from (finished_at - started_at)) * 1000)::integer
		end
	) stored,
	created_at    timestamptz not null default now(),
	updated_at    timestamptz not null default now(),
	constraint runs_finished_after_started check (finished_at is null or started_at is null or finished_at >= started_at)
);

create index if not exists runs_user_created_idx on public.runs (user_id, created_at desc);
create index if not exists runs_user_status_idx  on public.runs (user_id, status);
create index if not exists runs_job_id_idx       on public.runs (job_id) where job_id is not null;

drop trigger if exists runs_set_updated_at on public.runs;
create trigger runs_set_updated_at before update on public.runs
	for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- presets
-- Named, reusable argument sets.
create table if not exists public.presets
(
	id          uuid primary key default gen_random_uuid(),
	user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
	name        text not null check (char_length(name) between 1 and 80),
	description text,
	args        jsonb not null default '{}'::jsonb,
	created_at  timestamptz not null default now(),
	updated_at  timestamptz not null default now(),
	unique (user_id, name)
);

drop trigger if exists presets_set_updated_at on public.presets;
create trigger presets_set_updated_at before update on public.presets
	for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- row level security
alter table public.runs    enable row level security;
alter table public.presets enable row level security;

-- (select auth.uid()) is evaluated once per query instead of once per row.
drop policy if exists runs_owner_select on public.runs;
drop policy if exists runs_owner_insert on public.runs;
drop policy if exists runs_owner_update on public.runs;
drop policy if exists runs_owner_delete on public.runs;
create policy runs_owner_select on public.runs for select to authenticated using ((select auth.uid()) = user_id);
create policy runs_owner_insert on public.runs for insert to authenticated with check ((select auth.uid()) = user_id);
create policy runs_owner_update on public.runs for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy runs_owner_delete on public.runs for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists presets_owner_select on public.presets;
drop policy if exists presets_owner_insert on public.presets;
drop policy if exists presets_owner_update on public.presets;
drop policy if exists presets_owner_delete on public.presets;
create policy presets_owner_select on public.presets for select to authenticated using ((select auth.uid()) = user_id);
create policy presets_owner_insert on public.presets for insert to authenticated with check ((select auth.uid()) = user_id);
create policy presets_owner_update on public.presets for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy presets_owner_delete on public.presets for delete to authenticated using ((select auth.uid()) = user_id);

-- No access for the anonymous role at all.
revoke all on public.runs, public.presets from anon;
grant select, insert, update, delete on public.runs, public.presets to authenticated;

-- ---------------------------------------------------------------- storage (private outputs bucket)
-- Objects must be stored under "<user_id>/..." so each user only sees their own folder.
insert into storage.buckets (id, name, public)
values ('outputs', 'outputs', false)
on conflict (id) do nothing;

drop policy if exists outputs_owner_select on storage.objects;
drop policy if exists outputs_owner_insert on storage.objects;
drop policy if exists outputs_owner_update on storage.objects;
drop policy if exists outputs_owner_delete on storage.objects;
create policy outputs_owner_select on storage.objects for select to authenticated
	using (bucket_id = 'outputs' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy outputs_owner_insert on storage.objects for insert to authenticated
	with check (bucket_id = 'outputs' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy outputs_owner_update on storage.objects for update to authenticated
	using (bucket_id = 'outputs' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy outputs_owner_delete on storage.objects for delete to authenticated
	using (bucket_id = 'outputs' and (storage.foldername(name))[1] = (select auth.uid())::text);
