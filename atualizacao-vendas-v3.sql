-- MHY v3: dinheiro, crediário, histórico e venda avulsa. Preserva os dados.
begin;
create table if not exists public.coupons (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id),
 code text not null check(code ~ '^[A-Z0-9_-]{3,32}$'),
 kind text not null check(kind in ('percent','fixed')),
 value integer not null check(value>0 and value<=999999900),
 minimum bigint not null default 0 check(minimum between 0 and 999999900),
 expires_at timestamptz,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(user_id,code),
 check(kind<>'percent' or value<=10000)
);
alter table public.coupons enable row level security;
drop policy if exists coupon_owner on public.coupons;
create policy coupon_owner on public.coupons for all to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
revoke all on public.coupons from public,anon,authenticated;
grant select,insert,update,delete on public.coupons to authenticated;
alter table public.sales add column if not exists discount bigint not null default 0 check(discount>=0);
alter table public.sales add column if not exists coupon_code text not null default '';
alter table public.sales add column if not exists original_base bigint;

-- Função interna: somente as funções abaixo podem calcular o benefício.
create or replace function public.mhy_coupon_discount(store uuid,coupon_code text,subtotal bigint)
returns bigint language plpgsql security definer set search_path=public as $$
declare c public.coupons%rowtype;
begin
 select * into c from public.coupons
 where user_id=store and code=upper(trim(coupon_code)) for share;
 if not found or not c.active or (c.expires_at is not null and c.expires_at<=now()) then
  raise exception 'Cupom inválido, desativado ou expirado';
 end if;
 if subtotal<c.minimum then raise exception 'Compra abaixo do mínimo exigido pelo cupom'; end if;
 return least(subtotal,case when c.kind='percent'
  then round(subtotal::numeric*c.value/10000)::bigint else c.value::bigint end);
end; $$;
revoke all on function public.mhy_coupon_discount(uuid,text,bigint) from public,anon,authenticated;

alter table public.sales add column if not exists customer_name text not null default '';
alter table public.sales add column if not exists customer_phone text not null default '';
alter table public.sales add column if not exists paid_amount bigint check(paid_amount>=0);
alter table public.sales add column if not exists discount bigint not null default 0;
alter table public.sales add column if not exists coupon_code text not null default '';
alter table public.sales add column if not exists original_base bigint;
create table if not exists public.receivables (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
 sale_id uuid not null references public.sales(id),customer_name text not null,customer_phone text not null default '',
 installment integer not null,due_date date not null,amount bigint not null check(amount>0 and amount<=1000000000000),
 paid bigint not null default 0 check(paid>=0 and paid<=amount),created_at timestamptz not null default now(),unique(sale_id,installment)
);
create table if not exists public.receivable_payments (
 id uuid primary key,user_id uuid not null references auth.users(id),receivable_id uuid not null references public.receivables(id),
 amount bigint not null check(amount>0),method text not null check(method in ('cash','pix','debit','credit')),
 fee bigint not null check(fee>=0),net bigint not null check(net>=0),created_at timestamptz not null default now()
);
alter table public.movements add column if not exists receivable_payment_id uuid unique references public.receivable_payments(id);
alter table public.receivables enable row level security;
alter table public.receivable_payments enable row level security;
drop policy if exists receivables_owner_read on public.receivables;
create policy receivables_owner_read on public.receivables for select to authenticated using(user_id=auth.uid());
drop policy if exists receivable_payments_owner_read on public.receivable_payments;
create policy receivable_payments_owner_read on public.receivable_payments for select to authenticated using(user_id=auth.uid());
revoke all on public.receivables,public.receivable_payments from public,anon,authenticated;
grant select on public.receivables,public.receivable_payments to authenticated;
create index if not exists receivables_owner_due on public.receivables(user_id,due_date);
create index if not exists receivable_payments_owner on public.receivable_payments(user_id,created_at);

-- Somente funções internas podem obter custos e bloquear estoque.
create or replace function public.mhy_sale_items(store uuid,items jsonb,lock_stock boolean,allow_custom boolean,public_only boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare line record;p public.products%rowtype;subtotal bigint:=0;costs bigint:=0;snapshot jsonb:='[]';
 qty integer;price bigint;cost bigint;title text;sku text;custom boolean;
begin
 if items is null or jsonb_typeof(items)<>'array' then raise exception 'Sacola inválida';end if;
 if jsonb_array_length(items) not between 1 and 100 then raise exception 'Sacola deve ter 1 a 100 itens';end if;
 if exists(select 1 from jsonb_array_elements(items)x where not(x ? 'id' and x ? 'qty') or jsonb_typeof(x->'qty')<>'number'
 or (x->>'qty') !~ '^[1-9][0-9]{0,6}$' or (x ? 'custom' and jsonb_typeof(x->'custom')<>'boolean'))then raise exception 'Item ou quantidade inválida';end if;
 if (select count(*)from jsonb_array_elements(items))<>(select count(distinct(x->>'id')::uuid)from jsonb_array_elements(items)x)then raise exception 'Item duplicado';end if;
 for line in select x as item,(x->>'id')::uuid as id from jsonb_array_elements(items)x order by(x->>'id')::uuid loop
  qty:=(line.item->>'qty')::integer;custom:=coalesce((line.item->>'custom')::boolean,false);
  if custom then
   if not allow_custom or public_only then raise exception 'Item avulso permitido somente ao lojista';end if;
   title:=trim(line.item->>'name');
   if title is null or length(title) not between 1 and 120 then raise exception 'Nome do item avulso inválido';end if;
   if coalesce(line.item->>'price','') !~ '^[0-9]{1,9}$' or coalesce(line.item->>'cost','') !~ '^[0-9]{1,9}$'
   or jsonb_typeof(line.item->'price')<>'number' or jsonb_typeof(line.item->'cost')<>'number'then raise exception 'Preço ou custo avulso inválido';end if;
   price:=(line.item->>'price')::bigint;cost:=(line.item->>'cost')::bigint;
   if price not between 1 and 999999900 or cost not between 0 and 999999900 then raise exception 'Preço ou custo avulso fora do limite';end if;
   sku:='AVULSO';
  else
   if lock_stock then select * into p from public.products where id=line.id and user_id=store and(not public_only or online)for update;
   else select * into p from public.products where id=line.id and user_id=store and(not public_only or online);end if;
   if not found then raise exception 'Produto não encontrado ou indisponível';end if;
   if p.stock<qty then raise exception 'Estoque insuficiente para %',p.name;end if;
   title:=p.name;sku:=p.sku;price:=p.price;cost:=p.cost;
  end if;
  subtotal:=subtotal+price*qty;costs:=costs+cost*qty;
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('id',line.id,'name',title,'sku',sku,'qty',qty,'price',price,'cost',cost,'custom',custom));
 end loop;
 if subtotal>1000000000000 or costs>1000000000000 then raise exception 'Valor da venda excede o limite permitido';end if;
 return jsonb_build_object('subtotal',subtotal,'costs',costs,'items',snapshot);
end;$$;
revoke all on function public.mhy_sale_items(uuid,jsonb,boolean,boolean,boolean)from public,anon,authenticated;

create or replace function public.validate_coupon(store uuid,coupon text,items jsonb)
returns table(code text,subtotal bigint,discount bigint,total bigint)
language plpgsql security definer set search_path=public as $$
declare owner_access boolean:=coalesce(auth.uid()=store,false);assembled jsonb;amount bigint;benefit bigint;
begin
 if not owner_access and not exists(select 1 from public.store_settings s where s.user_id=store and s.published)then raise exception 'Catálogo indisponível';end if;
 if coupon is null or upper(trim(coupon)) !~ '^[A-Z0-9_-]{3,32}$'then raise exception 'Cupom inválido';end if;
 assembled:=public.mhy_sale_items(store,items,false,owner_access,not owner_access);amount:=(assembled->>'subtotal')::bigint;
 benefit:=public.mhy_coupon_discount(store,coupon,amount);
 return query select upper(trim(coupon)),amount,benefit,amount-benefit;
end;$$;
revoke all on function public.validate_coupon(uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.validate_coupon(uuid,text,jsonb)to anon,authenticated;

create or replace function public.record_sale(items jsonb,payment text,parts integer,pass_fee boolean,request_id uuid,coupon text default '',customer jsonb default null,schedule jsonb default null,expected_base bigint default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();assembled jsonb;line record;subtotal bigint;costs bigint;benefit bigint:=0;
 basis integer;charged bigint;fee_value bigint;snapshot jsonb;client_name text;phone text;plan_total bigint;plan_size integer;
begin
 if uid is null then raise exception 'Autenticação necessária';end if;
 if request_id is null or pass_fee is null then raise exception 'Pedido inválido';end if;
 perform pg_advisory_xact_lock(hashtextextended(request_id::text,0));
 if exists(select 1 from public.sales where id=request_id and user_id=uid)then return request_id;end if;
 if payment is null or payment not in('pix','debit','credit','cash','store_credit')or parts is null
 or(payment='credit'and parts not between 1 and 18)or(payment='store_credit'and parts not between 1 and 24)
 or(payment not in('credit','store_credit')and parts<>1)then raise exception 'Pagamento inválido';end if;
 if payment in('cash','store_credit')and pass_fee then raise exception 'Dinheiro e crediário não possuem taxa';end if;
 client_name:=coalesce(trim(customer->>'name'),'');phone:=coalesce(customer->>'phone','');
 if length(client_name)>100 or length(phone)>15 or(phone<>''and phone !~ '^[0-9]{8,15}$')then raise exception 'Dados do cliente inválidos';end if;
 if payment='store_credit'and client_name=''then raise exception 'Informe o nome do cliente para o crediário';end if;
 assembled:=public.mhy_sale_items(uid,items,true,true,false);
 subtotal:=(assembled->>'subtotal')::bigint;costs:=(assembled->>'costs')::bigint;snapshot:=assembled->'items';
 if coalesce(trim(coupon),'')<>''then benefit:=public.mhy_coupon_discount(uid,coupon,subtotal);end if;
 if expected_base is not null and expected_base<>subtotal-benefit then raise exception 'Os valores mudaram. Atualize a sacola e revise antes de confirmar';end if;
 basis:=case when payment in('cash','store_credit')then 0 when payment='pix'then 50 when payment='debit'then 99 when parts=1 then 299 when parts<=6 then 229 when parts<=12 then 269 else 299 end;
 charged:=case when pass_fee then round((subtotal-benefit)::numeric*10000/(10000-basis))::bigint else subtotal-benefit end;
 fee_value:=round(charged::numeric*basis/10000)::bigint;
 if payment='store_credit'then
  if charged<=0 then raise exception 'Use dinheiro para uma venda com total zero';end if;
  if schedule is null or jsonb_typeof(schedule)<>'array'then raise exception 'Informe as datas e valores do crediário';end if;
  plan_size:=jsonb_array_length(schedule);if plan_size<>parts then raise exception 'Quantidade de parcelas diferente do plano';end if;
  if exists(select 1 from jsonb_array_elements(schedule)x where coalesce(x->>'due_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(x->>'amount','') !~ '^[1-9][0-9]{0,12}$'or jsonb_typeof(x->'amount')<>'number')then raise exception 'Data ou valor de parcela inválido';end if;
  select sum((x->>'amount')::bigint)into plan_total from jsonb_array_elements(schedule)x;
  if plan_total<>charged then raise exception 'A soma das parcelas deve ser igual ao total da venda';end if;
  perform(x->>'due_date')::date from jsonb_array_elements(schedule)x;
 end if;
 for line in select(x->>'id')::uuid as id,(x->>'qty')::integer as qty from jsonb_array_elements(snapshot)x where not(x->>'custom')::boolean loop
  update public.products set stock=stock-line.qty where id=line.id and user_id=uid;
 end loop;
 insert into public.sales(id,user_id,method,installments,base,total,fee,net,profit,items,discount,coupon_code,original_base,customer_name,customer_phone,paid_amount)
 values(request_id,uid,payment,parts,subtotal-benefit,charged,fee_value,charged-fee_value,charged-fee_value-costs,snapshot,benefit,upper(trim(coalesce(coupon,''))),subtotal,client_name,phone,case when payment='store_credit'then 0 else charged end);
 if payment='store_credit'then
  insert into public.receivables(user_id,sale_id,customer_name,customer_phone,installment,due_date,amount)
  select uid,request_id,client_name,phone,n::integer,(x->>'due_date')::date,(x->>'amount')::bigint from jsonb_array_elements(schedule)with ordinality as plan(x,n);
 else
  insert into public.movements(user_id,kind,description,amount,sale_id)values(uid,'in','Venda (recebimento líquido)',charged-fee_value,request_id);
 end if;
 return request_id;
end;$$;
revoke all on function public.record_sale(jsonb,text,integer,boolean,uuid,text,jsonb,jsonb,bigint)from public,anon,authenticated;
grant execute on function public.record_sale(jsonb,text,integer,boolean,uuid,text,jsonb,jsonb,bigint)to authenticated;

create or replace function public.receive_installment(receivable uuid,amount bigint,payment text,request_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();r public.receivables%rowtype;sale uuid;basis integer;fee_value bigint;
begin
 if uid is null or request_id is null then raise exception 'Autenticação e identificador necessários';end if;
 perform pg_advisory_xact_lock(hashtextextended(request_id::text,0));
 if exists(select 1 from public.receivable_payments where id=request_id and user_id=uid)then return request_id;end if;
 if amount is null or amount<=0 or payment is null or payment not in('cash','pix','debit','credit')then raise exception 'Pagamento inválido';end if;
 select sale_id into sale from public.receivables where id=receivable and user_id=uid;
 if not found then raise exception 'Parcela não encontrada';end if;
 perform 1 from public.sales where id=sale and user_id=uid for update;
 select * into r from public.receivables where id=receivable and user_id=uid for update;
 if amount>r.amount-r.paid then raise exception 'O pagamento excede o saldo da parcela';end if;
 basis:=case payment when 'cash'then 0 when 'pix'then 50 when 'debit'then 99 else 299 end;
 fee_value:=round(amount::numeric*basis/10000)::bigint;
 insert into public.receivable_payments(id,user_id,receivable_id,amount,method,fee,net)values(request_id,uid,receivable,amount,payment,fee_value,amount-fee_value);
 update public.receivables set paid=paid+receive_installment.amount where id=receivable and user_id=uid;
 update public.sales set paid_amount=coalesce(paid_amount,0)+amount,fee=fee+fee_value,net=net-fee_value,profit=profit-fee_value where id=sale and user_id=uid;
 insert into public.movements(user_id,kind,description,amount,receivable_payment_id)values(uid,'in',left('Recebimento crediário · '||r.customer_name,150),amount-fee_value,request_id);
 return request_id;
end;$$;
revoke all on function public.receive_installment(uuid,bigint,text,uuid)from public,anon,authenticated;
grant execute on function public.receive_installment(uuid,bigint,text,uuid)to authenticated;
do $$declare t text;begin
 foreach t in array array['receivables','receivable_payments','coupons']loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='public'and tablename=t)then execute format('alter publication supabase_realtime add table public.%I',t);end if;
 end loop;
end $$;
commit;
