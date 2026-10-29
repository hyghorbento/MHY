-- MHY v3.2: edição de lançamentos manuais. Preserva vendas e recebimentos vinculados.
begin;
alter table public.movements add column if not exists revision integer not null default 0;
create table if not exists public.cash_movement_changes(
 id uuid primary key,user_id uuid not null references auth.users(id),movement_id uuid not null,
 previous jsonb not null,current_value jsonb not null,created_at timestamptz not null default now()
);
alter table public.cash_movement_changes enable row level security;
drop policy if exists cash_changes_owner on public.cash_movement_changes;
create policy cash_changes_owner on public.cash_movement_changes for select to authenticated using(user_id=auth.uid());
revoke all on public.cash_movement_changes from public,anon,authenticated;
grant select on public.cash_movement_changes to authenticated;
create index if not exists cash_changes_owner_movement on public.cash_movement_changes(user_id,movement_id,created_at);

create or replace function public.edit_cash_movement(movement uuid,expected_revision integer,description text,kind text,amount bigint,occurred_at timestamptz,request_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();m public.movements%rowtype;after_edit public.movements%rowtype;begin
 if uid is null or request_id is null then raise exception 'Entre na sua conta para corrigir o lançamento';end if;
 perform pg_advisory_xact_lock(hashtextextended(request_id::text,0));
 if exists(select 1 from public.cash_movement_changes c where c.id=request_id and c.user_id=uid and c.movement_id=movement)then return movement;end if;
 select * into m from public.movements where id=movement and user_id=uid for update;
 if not found then raise exception 'Lançamento não encontrado';end if;
 if m.sale_id is not null or nullif(to_jsonb(m)->>'receivable_payment_id','')is not null then raise exception 'Este lançamento está vinculado a uma venda ou recebimento. Corrija o registro de origem';end if;
 if expected_revision is null or expected_revision<>m.revision then raise exception 'O lançamento mudou em outro aparelho. Atualize e abra a edição novamente';end if;
 if description is null or length(trim(description))not between 1 and 150 or kind is null or kind not in('in','out')or amount is null or amount not between 1 and 999999900 or occurred_at is null then raise exception 'Confira descrição, tipo, valor positivo e data';end if;
 update public.movements set description=trim(edit_cash_movement.description),kind=edit_cash_movement.kind,amount=edit_cash_movement.amount,created_at=occurred_at,revision=revision+1
 where id=movement and user_id=uid returning * into after_edit;
 insert into public.cash_movement_changes(id,user_id,movement_id,previous,current_value)values(request_id,uid,movement,to_jsonb(m),to_jsonb(after_edit));
 return movement;
end;$$;
revoke all on function public.edit_cash_movement(uuid,integer,text,text,bigint,timestamptz,uuid)from public,anon,authenticated;
grant execute on function public.edit_cash_movement(uuid,integer,text,text,bigint,timestamptz,uuid)to authenticated;
commit;
