begin;

alter table public.movements add column if not exists revision integer not null default 0;

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

create or replace function public.cash_trip_summary(owner_id uuid, period_start timestamptz, period_end timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'sales_count', count(s.id),
    'revenue', coalesce(sum(total), 0),
    'receivable', coalesce(sum(case when method = 'store_credit' then greatest(total - coalesce((to_jsonb(s)->>'paid_amount')::bigint, 0), 0) else 0 end), 0),
    'incoming', cash.incoming,
    'outgoing', cash.outgoing
  )
  from (
    select coalesce(sum(amount) filter (where kind = 'in'), 0) incoming,
           coalesce(sum(amount) filter (where kind = 'out'), 0) outgoing
    from public.movements
    where user_id = owner_id and created_at >= period_start and created_at < period_end
  ) cash
  left join public.sales s on s.user_id = owner_id and s.created_at >= period_start and s.created_at < period_end
  group by cash.incoming, cash.outgoing;
$$;
revoke all on function public.cash_trip_summary(uuid, timestamptz, timestamptz) from public, anon, authenticated;

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
  snapshot := public.cash_trip_summary(owner_id, active_trip.opened_at, boundary);
  update public.cash_trips set closed_at = boundary, summary = snapshot where id = active_trip.id;
  insert into public.cash_trips (id, user_id, name, opened_at)
  values (request_id, owner_id, trim(next_name), boundary);
  return request_id;
end;
$$;
revoke all on function public.close_cash_trip(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.close_cash_trip(uuid, text, text, uuid) to authenticated;
create table if not exists public.cash_trip_corrections (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  trip_id uuid not null references public.cash_trips(id),
  movement_id uuid,
  previous jsonb,
  current_value jsonb,
  created_at timestamptz not null default now()
);
alter table public.cash_trip_corrections enable row level security;
revoke all on public.cash_trip_corrections from public, anon, authenticated;

create or replace function public.correct_cash_trip(trip_id uuid, movement_id uuid, expected_movement jsonb,
  movement_description text, movement_amount bigint, request_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  trip public.cash_trips%rowtype;
  previous public.movements%rowtype;
  saved public.movements%rowtype;
begin
  if owner_id is null or request_id is null then raise exception 'Entre na sua conta'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text, 0));
  if exists (select 1 from public.cash_trip_corrections c where c.id = request_id and c.user_id = owner_id and c.trip_id = correct_cash_trip.trip_id) then
    return trip_id;
  end if;
  select * into trip from public.cash_trips t where t.id = trip_id and t.user_id = owner_id and t.closed_at is not null;
  if not found then raise exception 'Viagem fechada não encontrada'; end if;

  if movement_description is not null or movement_amount is not null or movement_id is not null then
    if movement_description is null or char_length(trim(movement_description)) not between 1 and 150
      or movement_amount is null or movement_amount not between 1 and 999999900 then
      raise exception 'Confira a descrição e o valor da despesa';
    end if;
    if movement_id is null then
      insert into public.movements (user_id, kind, description, amount, created_at)
      values (owner_id, 'out', trim(movement_description), movement_amount, greatest(trip.opened_at, trip.closed_at - interval '1 millisecond'))
      returning * into saved;
    else
      select * into previous from public.movements m where m.id = movement_id and m.user_id = owner_id
        and m.kind = 'out' and m.sale_id is null and nullif(to_jsonb(m)->>'receivable_payment_id','') is null
        and m.created_at >= trip.opened_at and m.created_at < trip.closed_at for update;
      if not found then raise exception 'Despesa manual da viagem não encontrada'; end if;
      if expected_movement is distinct from to_jsonb(previous) then
        raise exception 'A despesa mudou em outro aparelho. Atualize e abra a correção novamente';
      end if;
      update public.movements m set description = trim(movement_description), amount = movement_amount, revision = m.revision + 1
      where m.id = previous.id returning * into saved;
    end if;
  end if;
  update public.cash_trips t set summary = public.cash_trip_summary(owner_id, trip.opened_at, trip.closed_at)
  where t.id = trip.id;
  insert into public.cash_trip_corrections (id, user_id, trip_id, movement_id, previous, current_value)
  values (request_id, owner_id, trip.id, saved.id,
    case when previous.id is not null then to_jsonb(previous) end,
    case when saved.id is not null then to_jsonb(saved) end);
  return trip.id;
end;
$$;
revoke all on function public.correct_cash_trip(uuid, uuid, jsonb, text, bigint, uuid) from public, anon, authenticated;
grant execute on function public.correct_cash_trip(uuid, uuid, jsonb, text, bigint, uuid) to authenticated;
commit;
