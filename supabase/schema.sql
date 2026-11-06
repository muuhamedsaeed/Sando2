-- sando2 database schema for Supabase
-- Run this whole file once in: Supabase dashboard > SQL Editor > New query > Run

create extension if not exists pgcrypto with schema extensions;

-- 1) Site settings (one row per user)
create table if not exists public.settings (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  site_name text not null default 'sando2' check (char_length(site_name) between 1 and 30),
  tagline text not null default 'Monthly income and expense log' check (char_length(tagline) <= 80),
  home_title text not null default 'Monthly ledger' check (char_length(home_title) between 1 and 60),
  home_desc text not null default 'Income and expenses for the month you pick.' check (char_length(home_desc) <= 160),
  currency text not null default 'EGP' check (currency in ('EGP','USD','EUR','SAR','AED')),
  updated_at timestamptz not null default now()
);

-- 2) Categories (income and expense)
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type text not null check (type in ('income','expense')),
  name text not null check (char_length(name) between 1 and 24),
  unique (user_id, type, name)
);

-- 3) Entries (every income / expense line)
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  type text not null check (type in ('income','expense')),
  entry_date date not null,
  description text not null check (char_length(description) between 1 and 80),
  category text not null,
  amount numeric(14,2) not null check (amount > 0),
  created_at timestamptz not null default now()
);
create index if not exists entries_user_date_idx on public.entries (user_id, entry_date);

-- 4) Optional notes linked to income and expense entries.
create table if not exists public.entry_notes (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  note text not null check (char_length(note) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists entry_notes_user_entry_idx on public.entry_notes (user_id, entry_id);

-- 5) Admin-managed recurring transactions and their per-month variable amounts.
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

-- 6) Explicit Data API grants plus Row Level Security.
-- New Supabase projects require these grants in addition to RLS policies.
grant select, insert, update, delete on table public.settings, public.categories, public.entries, public.entry_notes, public.pinned_items, public.pinned_amounts to authenticated;

alter table public.settings enable row level security;
alter table public.categories enable row level security;
alter table public.entries enable row level security;
alter table public.entry_notes enable row level security;
alter table public.pinned_items enable row level security;
alter table public.pinned_amounts enable row level security;

drop policy if exists "own settings" on public.settings;
drop policy if exists "own categories" on public.categories;
drop policy if exists "own entries" on public.entries;
drop policy if exists "own entry notes" on public.entry_notes;
drop policy if exists "own pinned items" on public.pinned_items;
drop policy if exists "own pinned amounts" on public.pinned_amounts;

create policy "own settings" on public.settings for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own categories" on public.categories for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own entries" on public.entries for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own entry notes" on public.entry_notes for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id and entry_id in (select id from public.entries where user_id = (select auth.uid())));
create policy "own pinned items" on public.pinned_items for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "own pinned amounts" on public.pinned_amounts for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- 7) When a user is created, give them default settings and categories.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.settings (user_id) values (new.id) on conflict do nothing;
  insert into public.categories (user_id, type, name)
  select new.id, c.type, c.name
  from (values
    ('income','Salary'),('income','Freelance'),('income','Rent'),('income','Sales'),
    ('expense','Housing'),('expense','Food'),('expense','Bills'),('expense','Transport'),('expense','Work')
  ) as c(type, name)
  on conflict do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 8) Running balance through the end of a selected month.
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
