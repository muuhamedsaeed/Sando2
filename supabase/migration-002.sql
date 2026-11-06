-- sando2 feature migration: themes are client-side; this file adds balance
-- carry-over and admin-managed pinned transactions.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.pinned_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type text not null check (type in ('income', 'expense')),
  description text not null check (char_length(description) between 1 and 80),
  category text not null,
  amount numeric(14,2) check (amount > 0),
  start_month date not null default date_trunc('month', current_date)::date
    check (start_month = date_trunc('month', start_month)::date),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.pinned_amounts (
  pinned_id uuid not null references public.pinned_items(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  month date not null check (month = date_trunc('month', month)::date),
  amount numeric(14,2) not null check (amount > 0),
  primary key (pinned_id, month)
);

create index if not exists pinned_items_user_month_idx on public.pinned_items (user_id, start_month);
create index if not exists pinned_amounts_user_month_idx on public.pinned_amounts (user_id, month);

-- Tables created by an earlier run of this idempotent migration receive the
-- same month-boundary validation.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pinned_items_start_month_check' and conrelid = 'public.pinned_items'::regclass) then
    alter table public.pinned_items add constraint pinned_items_start_month_check check (start_month = date_trunc('month', start_month)::date);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'pinned_amounts_month_check' and conrelid = 'public.pinned_amounts'::regclass) then
    alter table public.pinned_amounts add constraint pinned_amounts_month_check check (month = date_trunc('month', month)::date);
  end if;
end;
$$;

-- The Data API now requires explicit grants on new public tables. RLS below is
-- the row-level enforcement layer.
grant select, insert, update, delete on table public.settings, public.categories, public.entries, public.pinned_items, public.pinned_amounts to authenticated;

alter table public.settings enable row level security;
alter table public.categories enable row level security;
alter table public.entries enable row level security;
alter table public.pinned_items enable row level security;
alter table public.pinned_amounts enable row level security;

drop policy if exists "own settings" on public.settings;
drop policy if exists "own categories" on public.categories;
drop policy if exists "own entries" on public.entries;
drop policy if exists "own pinned items" on public.pinned_items;
drop policy if exists "own pinned amounts" on public.pinned_amounts;

create policy "own settings" on public.settings for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own categories" on public.categories for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own entries" on public.entries for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own pinned items" on public.pinned_items for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own pinned amounts" on public.pinned_amounts for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create or replace function public.balance_through(p_month date)
returns numeric
language sql
stable
security invoker
set search_path = public
as $$
  with target as (
    select date_trunc('month', p_month)::date as month_start
  ), entry_total as (
    select coalesce(sum(case when e.type = 'income' then e.amount else -e.amount end), 0)::numeric as total
    from public.entries e
    cross join target t
    where e.user_id = auth.uid()
      and e.entry_date < (t.month_start + interval '1 month')::date
  ), fixed_pinned_total as (
    select coalesce(sum(
      (case when p.type = 'income' then p.amount else -p.amount end) *
      (((extract(year from t.month_start)::integer - extract(year from p.start_month)::integer) * 12) +
       (extract(month from t.month_start)::integer - extract(month from p.start_month)::integer) + 1)
    ), 0)::numeric as total
    from public.pinned_items p
    cross join target t
    where p.user_id = auth.uid()
      and p.active
      and p.amount is not null
      and p.start_month <= t.month_start
  ), variable_pinned_total as (
    select coalesce(sum(case when p.type = 'income' then a.amount else -a.amount end), 0)::numeric as total
    from public.pinned_amounts a
    join public.pinned_items p on p.id = a.pinned_id
    cross join target t
    where a.user_id = auth.uid()
      and p.user_id = auth.uid()
      and p.active
      and p.amount is null
      and a.month >= p.start_month
      and a.month <= t.month_start
  )
  select (select total from entry_total) + (select total from fixed_pinned_total) + (select total from variable_pinned_total);
$$;

revoke all on function public.balance_through(date) from public, anon;
grant execute on function public.balance_through(date) to authenticated;

-- The user-creation trigger still needs this function, but no API role should
-- be able to invoke it directly.
revoke all on function public.handle_new_user() from public, anon, authenticated;
