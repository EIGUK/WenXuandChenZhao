-- 照照与闻叙 · 两只爱心罐
-- Run once in Supabase SQL editor after a project exists.
-- This file contains no credentials. GitHub Pages stays unchanged until cloud sync is ready.
-- Counts: 照照 → 闻叙 (to_wenxu) and 闻叙 → 照照 (to_zhaozhao).
-- Existing browser counts (e.g. 1214/99) are migrated with GREATEST, never reset to 999/99.

create table if not exists public.heart_jars (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  to_wenxu bigint not null default 999 check (to_wenxu >= 0),
  to_zhaozhao bigint not null default 99 check (to_zhaozhao >= 0),
  updated_at timestamptz not null default now()
);

alter table public.heart_jars enable row level security;

drop policy if exists "Read my own heart jars" on public.heart_jars;
create policy "Read my own heart jars"
  on public.heart_jars for select to authenticated
  using (owner_id = (select auth.uid()));

-- All changes go through checked RPCs. Signed-in browser sessions get SELECT only.
revoke all on public.heart_jars from anon, authenticated;
grant select on public.heart_jars to authenticated;

create or replace function public.heart_jars_initialize(
  p_to_wenxu bigint default 999,
  p_to_zhaozhao bigint default 99
)
returns public.heart_jars
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_owner uuid := auth.uid();
  v_result public.heart_jars;
begin
  if v_owner is null then
    raise exception 'Please sign in before accessing heart jars.';
  end if;
  if p_to_wenxu < 0 or p_to_zhaozhao < 0 or p_to_wenxu is null or p_to_zhaozhao is null then
    raise exception 'Invalid heart counts.';
  end if;

  insert into public.heart_jars as jars (owner_id, to_wenxu, to_zhaozhao)
  values (v_owner, p_to_wenxu, p_to_zhaozhao)
  on conflict (owner_id) do update
    set to_wenxu = greatest(jars.to_wenxu, excluded.to_wenxu),
        to_zhaozhao = greatest(jars.to_zhaozhao, excluded.to_zhaozhao),
        updated_at = now()
  returning * into v_result;

  return v_result;
end;
$fn$;

create or replace function public.heart_jars_add(
  p_recipient text,
  p_amount integer default 1
)
returns public.heart_jars
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_owner uuid := auth.uid();
  v_result public.heart_jars;
begin
  if v_owner is null then
    raise exception 'Please sign in before adding hearts.';
  end if;
  if p_recipient not in ('wenxu', 'zhaozhao')
     or p_recipient is null
     or p_amount is null
     or p_amount < 1
     or p_amount > 9999 then
    raise exception 'Invalid heart deposit.';
  end if;

  update public.heart_jars
     set to_wenxu = to_wenxu + case when p_recipient = 'wenxu' then p_amount else 0 end,
         to_zhaozhao = to_zhaozhao + case when p_recipient = 'zhaozhao' then p_amount else 0 end,
         updated_at = now()
   where owner_id = v_owner
   returning * into v_result;

  if not found then
    raise exception 'Initialize your heart jars first.';
  end if;

  return v_result;
end;
$fn$;

revoke all on function public.heart_jars_initialize(bigint, bigint) from public, anon, authenticated;
revoke all on function public.heart_jars_add(text, integer) from public, anon, authenticated;
grant execute on function public.heart_jars_initialize(bigint, bigint) to authenticated;
grant execute on function public.heart_jars_add(text, integer) to authenticated;

-- Do not put a Supabase service_role key into index.html or a public GitHub repo.
-- Browser integration should use the public publishable/anon key with Supabase Auth.
-- On first sign-in, call heart_jars_initialize(localCount1, localCount2).
-- On deposit, call heart_jars_add(recipient, amount) for atomic increments.
