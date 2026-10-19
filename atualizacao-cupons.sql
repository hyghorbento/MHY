-- MHY: cupons. Execute uma vez no SQL Editor do projeto existente.
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

-- Não recebe preço nem valor de desconto do navegador. Consulta os preços reais.
create or replace function public.validate_coupon(store uuid,coupon text,items jsonb)
returns table(code text,subtotal bigint,discount bigint,total bigint)
language plpgsql security definer set search_path=public as $$
declare
 owner_access boolean := coalesce(auth.uid()=store,false);
 line record; p public.products%rowtype; amount bigint := 0; benefit bigint;
begin
 if not owner_access and not exists(
  select 1 from public.store_settings s where s.user_id=store and s.published
 ) then raise exception 'Catálogo indisponível'; end if;
 if coupon is null or upper(trim(coupon)) !~ '^[A-Z0-9_-]{3,32}$' then
  raise exception 'Cupom inválido'; end if;
 if items is null or jsonb_typeof(items)<>'array' then raise exception 'Sacola inválida'; end if;
 if jsonb_array_length(items) not between 1 and 100 then raise exception 'Sacola deve ter 1 a 100 produtos'; end if;
 if exists(select 1 from jsonb_array_elements(items) x where
  not(x ? 'id' and x ? 'qty') or jsonb_typeof(x->'qty')<>'number'
  or (x->>'qty') !~ '^[1-9][0-9]{0,6}$') then raise exception 'Quantidade inválida'; end if;
 if (select count(*) from jsonb_array_elements(items)) <>
  (select count(distinct x->>'id') from jsonb_array_elements(items) x)
 then raise exception 'Produto duplicado'; end if;
 for line in select (x->>'id')::uuid as id,(x->>'qty')::integer as qty
  from jsonb_array_elements(items) x loop
  select * into p from public.products
  where id=line.id and user_id=store and (owner_access or online);
  if not found then raise exception 'Produto indisponível'; end if;
  if p.stock<line.qty then raise exception 'Quantidade indisponível para %',p.name; end if;
  amount := amount+p.price*line.qty;
 end loop;
 if amount>1000000000000 then raise exception 'Valor da venda excede o limite permitido'; end if;
 benefit := public.mhy_coupon_discount(store,coupon,amount);
 return query select upper(trim(coupon)),amount,benefit,amount-benefit;
end; $$;
revoke all on function public.validate_coupon(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.validate_coupon(uuid,text,jsonb) to anon,authenticated;

create or replace function public.checkout_with_coupon(items jsonb,payment text,parts integer,pass_fee boolean,request_id uuid,coupon text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
 uid uuid := auth.uid(); line record; product public.products%rowtype;
 subtotal bigint := 0; costs bigint := 0; basis integer;
 charged bigint; fee_value bigint; original_subtotal bigint; benefit bigint; snapshot jsonb := '[]'::jsonb;
begin
 if uid is null then raise exception 'Autenticação necessária'; end if;
 if request_id is null or pass_fee is null then raise exception 'Pedido inválido'; end if;
 perform pg_advisory_xact_lock(hashtextextended(request_id::text,0));
 if exists(select 1 from public.sales where id=request_id and user_id=uid) then return request_id; end if;
 if payment is null or parts is null or payment not in ('pix','debit','credit') or parts not between 1 and 18
 or (payment<>'credit' and parts<>1) then raise exception 'Pagamento inválido'; end if;
 if items is null or jsonb_typeof(items)<>'array' then raise exception 'Sacola inválida'; end if;
 if jsonb_array_length(items) not between 1 and 100 then raise exception 'Sacola deve ter 1 a 100 produtos'; end if;
 if exists(select 1 from jsonb_array_elements(items) x where
    not (x ? 'id' and x ? 'qty') or jsonb_typeof(x->'qty')<>'number'
    or (x->>'qty') !~ '^[1-9][0-9]{0,6}$') then raise exception 'Quantidade inválida'; end if;
 if (select count(*) from jsonb_array_elements(items)) <>
    (select count(distinct x->>'id') from jsonb_array_elements(items) x)
 then raise exception 'Produto duplicado'; end if;
 for line in select (x->>'id')::uuid as id,(x->>'qty')::integer as qty
   from jsonb_array_elements(items) x order by (x->>'id')::uuid loop
   select * into product from public.products where id=line.id and user_id=uid for update;
   if not found then raise exception 'Produto não encontrado'; end if;
   if product.stock<line.qty then raise exception 'Estoque insuficiente para %',product.name; end if;
   subtotal := subtotal+product.price*line.qty;
   costs := costs+product.cost*line.qty;
   snapshot := snapshot || jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,
      'sku',product.sku,'qty',line.qty,'price',product.price,'cost',product.cost));
   update public.products set stock=stock-line.qty where id=product.id;
 end loop;
 if subtotal>1000000000000 then raise exception 'Valor da venda excede o limite permitido'; end if;
 original_subtotal := subtotal;
 benefit := public.mhy_coupon_discount(uid,coupon,subtotal);
 subtotal := subtotal-benefit;
 basis := case when payment='pix' then 50 when payment='debit' then 99
   when parts=1 then 299 when parts<=6 then 229 when parts<=12 then 269 else 299 end;
 charged := case when pass_fee then round(subtotal::numeric*10000/(10000-basis))::bigint else subtotal end;
 fee_value := round(charged::numeric*basis/10000)::bigint;
 insert into public.sales(id,user_id,method,installments,base,total,fee,net,profit,items,discount,coupon_code,original_base)
 values(request_id,uid,payment,parts,subtotal,charged,fee_value,charged-fee_value,charged-fee_value-costs,snapshot,benefit,upper(trim(coupon)),original_subtotal);
 insert into public.movements(user_id,kind,description,amount,sale_id)
 values(uid,'in','Venda (recebimento líquido)',charged-fee_value,request_id);
 return request_id;
end; $$;
revoke all on function public.checkout_with_coupon(jsonb,text,integer,boolean,uuid,text) from public,anon,authenticated;
grant execute on function public.checkout_with_coupon(jsonb,text,integer,boolean,uuid,text) to authenticated;
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='coupons') then
  alter publication supabase_realtime add table public.coupons;
 end if;
end $$;
commit;
