-- Optional notes for income and expense entries. One entry can have many notes.
create table if not exists public.entry_notes (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.entries(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  note text not null check (char_length(note) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists entry_notes_user_entry_idx on public.entry_notes (user_id, entry_id);

grant select, insert, update, delete on table public.entry_notes to authenticated;

alter table public.entry_notes enable row level security;

drop policy if exists "own entry notes" on public.entry_notes;
create policy "own entry notes" on public.entry_notes for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id and entry_id in (select id from public.entries where user_id = (select auth.uid())));
