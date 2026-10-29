-- Lista de compras/pedidos v1.5. Execute após a integração dos fornecedores.
begin;
create table if not exists public.supplier_lists(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
 name text not null check(length(trim(name))between 1 and 80),created_at timestamptz not null default now()
);
create table if not exists public.supplier_list_items(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
 list_id uuid not null references public.supplier_lists(id)on delete cascade,
 source_url text not null,snapshot jsonb not null check(jsonb_typeof(snapshot)='object'),
 quantity integer not null check(quantity between 1 and 1000000),customer text not null default '' check(length(customer)<=100),
 note text not null default '' check(length(note)<=1000),status text not null default 'waiting' check(status in('waiting','purchased','imported')),
 product_id uuid references public.products(id)on delete set null,revision integer not null default 0,
 purchased_at timestamptz,imported_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.supplier_list_items add column if not exists final_unit_cost bigint check(final_unit_cost between 1 and 999999900);
alter table public.supplier_list_items add column if not exists final_unit_price bigint check(final_unit_price between 1 and 999999900);
create unique index if not exists supplier_list_pending_source on public.supplier_list_items(list_id,source_url)where status<>'imported';
create index if not exists supplier_lists_owner on public.supplier_lists(user_id);
create index if not exists supplier_list_items_owner on public.supplier_list_items(user_id,list_id);
alter table public.supplier_lists enable row level security;
alter table public.supplier_list_items enable row level security;
drop policy if exists supplier_lists_read on public.supplier_lists;
create policy supplier_lists_read on public.supplier_lists for select to authenticated using(user_id=auth.uid());
drop policy if exists supplier_list_items_read on public.supplier_list_items;
create policy supplier_list_items_read on public.supplier_list_items for select to authenticated using(user_id=auth.uid());
revoke all on public.supplier_lists,public.supplier_list_items from public,anon,authenticated;
grant select on public.supplier_lists,public.supplier_list_items to authenticated;

create or replace function public.create_supplier_list(title text,request_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();begin
 if uid is null then raise exception 'Entre na conta MHY para salvar suas listas';end if;
 if request_id is null or title is null or length(trim(title))not between 1 and 80 then raise exception 'Informe o nome da lista';end if;
 insert into public.supplier_lists(id,user_id,name)values(request_id,uid,trim(title))on conflict(id)do nothing;
 if not exists(select 1 from public.supplier_lists where id=request_id and user_id=uid)then raise exception 'Lista não encontrada';end if;
 return request_id;
end;$$;

create or replace function public.add_supplier_list_item(list uuid,product jsonb,quantity integer,customer text,note text,request_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();source text;existing uuid;begin
 if uid is null or not exists(select 1 from public.supplier_lists where id=list and user_id=uid)then raise exception 'Entre na conta proprietária da lista';end if;
 if request_id is null or product is null or jsonb_typeof(product)<>'object'or length(product::text)>40000 then raise exception 'Produto inválido';end if;
 source:=product->>'url';
 if source is null or length(source)>2000 or source !~ '^https://(www\.)?(charmeperfumeria\.com\.br|newzone\.com\.br|atacadoconnect\.com|megaeletronicos\.com|cellshop\.com\.br|shoppingchina\.com\.br|stargamesparaguay\.com|intershop\.com\.py)/'then raise exception 'Link do fornecedor inválido';end if;
 if coalesce(length(trim(product->>'name')),0)not between 1 and 160 then raise exception 'Informe o nome do produto';end if;
 if quantity is null or quantity not between 1 and 1000000 or length(coalesce(customer,''))>100 or length(coalesce(note,''))>1000 then raise exception 'Revise quantidade, cliente e observação';end if;
 perform pg_advisory_xact_lock(hashtextextended(list::text||source,0));
 select id into existing from public.supplier_list_items where list_id=list and source_url=source and status<>'imported'and user_id=uid;
 if found then return existing;end if;
 if exists(select 1 from public.supplier_list_items where id=request_id and user_id=uid)then return request_id;end if;
 insert into public.supplier_list_items(id,user_id,list_id,source_url,snapshot,quantity,customer,note)
 values(request_id,uid,list,source,product,quantity,coalesce(trim(customer),''),coalesce(trim(note),''));
 return request_id;
end;$$;

create or replace function public.update_supplier_list_item(item uuid,expected_revision integer,quantity integer,customer text,note text,next_status text)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();r public.supplier_list_items%rowtype;begin
 select * into r from public.supplier_list_items where id=item and user_id=uid for update;
 if uid is null or not found then raise exception 'Item não encontrado';end if;
 if r.status='imported'then raise exception 'Este item já foi enviado à MHY e seu histórico é preservado';end if;
 if expected_revision is null or r.revision<>expected_revision then raise exception 'Item alterado em outro aparelho. Atualize a lista';end if;
 if quantity is null or quantity not between 1 and 1000000 or next_status is null or next_status not in('waiting','purchased')or length(coalesce(customer,''))>100 or length(coalesce(note,''))>1000 then raise exception 'Revise os dados do item';end if;
 update public.supplier_list_items set quantity=update_supplier_list_item.quantity,customer=coalesce(trim(update_supplier_list_item.customer),''),note=coalesce(trim(update_supplier_list_item.note),''),status=next_status,
 purchased_at=case when next_status='waiting'then null else coalesce(purchased_at,now())end,revision=revision+1,updated_at=now()where id=item;
 return item;
end;$$;

create or replace function public.remove_supplier_list_item(item uuid,expected_revision integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare r public.supplier_list_items%rowtype;begin
 select * into r from public.supplier_list_items where id=item and user_id=auth.uid()for update;
 if auth.uid()is null or not found then raise exception 'Item não encontrado';end if;
 if r.status='imported'then raise exception 'O histórico do envio à MHY deve ser preservado';end if;
 if expected_revision is null or expected_revision<>r.revision then raise exception 'Item alterado. Atualize a lista';end if;
 delete from public.supplier_list_items where id=item and user_id=auth.uid();return item;
end;$$;

create or replace function public.complete_supplier_list_item(item uuid,expected_revision integer,payload jsonb)
returns table(product_id uuid,already_imported boolean,stock_added integer)
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();r public.supplier_list_items%rowtype;result record;amount numeric;fx numeric;pct numeric;cost_value bigint;price_value bigint;qty integer;begin
 select * into r from public.supplier_list_items where id=item and user_id=uid for update;
 if uid is null or not found then raise exception 'Item não encontrado';end if;
 if r.status='imported'then return query select r.product_id,true,0;return;end if;
 if r.status<>'purchased'then raise exception 'Marque o produto como comprado antes de enviar à MHY';end if;
 if expected_revision is null or r.revision<>expected_revision then raise exception 'Item alterado em outro aparelho. Abra o envio novamente';end if;
 if payload->>'source_url'is distinct from r.source_url then raise exception 'O link deve ser o mesmo do item comprado';end if;
 if coalesce(payload->>'stock','') !~ '^[1-9][0-9]{0,6}$'then raise exception 'Confira a quantidade comprada';end if;
 qty:=(payload->>'stock')::integer;if qty<>r.quantity then raise exception 'A quantidade deve corresponder à lista; ajuste a quantidade comprada na lista primeiro';end if;
 if payload->>'currency'is null or payload->>'currency'not in('USD','BRL','PYG')or jsonb_typeof(payload->'online')is distinct from'boolean'then raise exception 'Moeda ou publicação inválida';end if;
 if exists(select 1 from unnest(array['amount','rate','percent'])k where coalesce(payload->>k,'') !~ '^[0-9]+(\.[0-9]+)?$')then raise exception 'Confira custo, câmbio e percentual';end if;
 amount:=(payload->>'amount')::numeric;fx:=case when payload->>'currency'='BRL'then 1 else(payload->>'rate')::numeric end;pct:=(payload->>'percent')::numeric;
 if amount<=0 or amount>1000000000000 or fx<=0 or fx>1000000 or pct not between 0 and 1000 then raise exception 'Valores fora do limite';end if;
 cost_value:=round(amount*fx*100)::bigint;price_value:=round(cost_value*(1+pct/100))::bigint;
 if cost_value not between 1 and 999999900 or price_value not between 1 and 999999900 then raise exception 'Preço fora do limite';end if;
 select * into result from public.import_supplier_product(payload,r.id);
 if result.already_exists then
  update public.products set stock=stock+qty,cost=cost_value,price=price_value,
  online=case when(payload->>'online')::boolean then true else online end
  where id=result.product_id and user_id=uid;
  if not found then raise exception 'Produto não encontrado na MHY';end if;
 end if;
 update public.supplier_list_items set status='imported',product_id=result.product_id,final_unit_cost=cost_value,final_unit_price=price_value,imported_at=now(),updated_at=now(),revision=revision+1 where id=item and user_id=uid;
 return query select result.product_id,false,qty;
end;$$;

revoke all on function public.create_supplier_list(text,uuid),public.add_supplier_list_item(uuid,jsonb,integer,text,text,uuid),public.update_supplier_list_item(uuid,integer,integer,text,text,text),public.remove_supplier_list_item(uuid,integer),public.complete_supplier_list_item(uuid,integer,jsonb)from public,anon,authenticated;
grant execute on function public.create_supplier_list(text,uuid),public.add_supplier_list_item(uuid,jsonb,integer,text,text,uuid),public.update_supplier_list_item(uuid,integer,integer,text,text,text),public.remove_supplier_list_item(uuid,integer),public.complete_supplier_list_item(uuid,integer,jsonb)to authenticated;
commit;
