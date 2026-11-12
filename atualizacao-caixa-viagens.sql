begin;

create table if not exists public.cash_trips (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  name text not null check (char_length(trim(name)) between 1 and 100),
  opened_at timestamptz not null,
  closed_at timestamptz,
  summary jsonb,
  check (closed_at is null or closed_at > opened_at)
);
create unique index if not exists cash_trips_one_open on public.cash_trips(user_id) where closed_at is null;
alter table public.cash_trips enable row level security;
drop policy if exists cash_trips_owner on public.cash_trips;
create policy cash_trips_owner on public.cash_trips for select to authenticated using (user_id = auth.uid());
revoke all on public.cash_trips from public, anon, authenticated;
grant select on public.cash_trips to authenticated;

create or replace function public.close_cash_trip(expected_trip uuid, first_name text, next_name text, request_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  active_trip public.cash_trips%rowtype;
  boundary timestamptz;
  snapshot jsonb;
begin
  if owner_id is null or request_id is null then raise exception 'Entre na sua conta'; end if;
  if next_name is null or char_length(trim(next_name)) not between 1 and 100 then
    raise exception 'Informe o nome da próxima viagem';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text, 0));
  if exists (select 1 from public.cash_trips where id = request_id and user_id = owner_id) then
    return request_id;
  end if;
  select * into active_trip from public.cash_trips where user_id = owner_id and closed_at is null;
  if active_trip.id is distinct from expected_trip then
    raise exception 'A viagem mudou em outro aparelho. Atualize e revise o fechamento';
  end if;
  boundary := clock_timestamp();
  if active_trip.id is null then
    if first_name is null or char_length(trim(first_name)) not between 1 and 100 then
      raise exception 'Informe o nome da viagem atual';
    end if;
    insert into public.cash_trips (id, user_id, name, opened_at)
    values (gen_random_uuid(), owner_id, trim(first_name), 'epoch') returning * into active_trip;
  end if;
  select jsonb_build_object(
    'sales_count', count(s.id),
    'revenue', coalesce(sum(total), 0),
    'receivable', coalesce(sum(case when method = 'store_credit' then greatest(total - coalesce((to_jsonb(s)->>'paid_amount')::bigint, 0), 0) else 0 end), 0),
    'incoming', cash.incoming,
    'outgoing', cash.outgoing
  ) into snapshot
  from (
    select coalesce(sum(amount) filter (where kind = 'in'), 0) incoming,
           coalesce(sum(amount) filter (where kind = 'out'), 0) outgoing
    from public.movements
    where user_id = owner_id and created_at >= active_trip.opened_at and created_at < boundary
  ) cash
  left join public.sales s on s.user_id = owner_id and s.created_at >= active_trip.opened_at and s.created_at < boundary
  group by cash.incoming, cash.outgoing;
  update public.cash_trips set closed_at = boundary, summary = snapshot where id = active_trip.id;
  insert into public.cash_trips (id, user_id, name, opened_at)
  values (request_id, owner_id, trim(next_name), boundary);
  return request_id;
end;
$$;
revoke all on function public.close_cash_trip(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.close_cash_trip(uuid, text, text, uuid) to authenticated;
commit;
