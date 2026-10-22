-- Fornecedores Paraguai: integração privada. Execute após a estrutura existente da MHY.
begin;
create table if not exists public.supplier_imports (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
 product_id uuid not null unique references public.products(id)on delete cascade,
 supplier text not null,source_url text not null,original_amount numeric not null check(original_amount>0),
 currency text not null check(currency in('BRL','USD','PYG')),exchange_rate numeric not null check(exchange_rate>0),
 markup numeric not null check(markup between 0 and 1000),created_at timestamptz not null default now(),unique(user_id,source_url)
);
alter table public.supplier_imports enable row level security;
drop policy if exists supplier_imports_owner on public.supplier_imports;
create policy supplier_imports_owner on public.supplier_imports for select to authenticated using(user_id=auth.uid());
revoke all on public.supplier_imports from public,anon,authenticated;
grant select on public.supplier_imports to authenticated;
create or replace function public.import_supplier_product(payload jsonb,request_id uuid)
returns table(product_id uuid,already_exists boolean)
language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();source text;supplier text;title text;sku text;description text;category text;photo text;currency text;amount numeric;fx numeric;pct numeric;cost bigint;price bigint;stock integer;minimum integer;online boolean;existing uuid;
begin
 if uid is null or request_id is null then raise exception 'Entre na sua conta MHY para importar';end if;
 source:=payload->>'source_url';supplier:=payload->>'supplier';
 if source is null or length(source)>2000 or source !~ '^https://(www\.)?(charmeperfumeria\.com\.br|newzone\.com\.br|atacadoconnect\.com|megaeletronicos\.com|cellshop\.com\.br|shoppingchina\.com\.br|stargamesparaguay\.com|intershop\.com\.py)/'then raise exception 'Link do fornecedor inválido';end if;
 if supplier is null or supplier not in('charme','newzone','connect','mega','cellshop','china','stargames','intershop')then raise exception 'Fornecedor inválido';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text||source,0));
 select si.product_id into existing from public.supplier_imports si where si.user_id=uid and(si.source_url=source or si.product_id=request_id);
 if found then return query select existing,true;return;end if;
 if exists(select 1 from public.products p where p.id=request_id)then raise exception 'Identificador já utilizado. Reabra o produto';end if;
 title:=trim(payload->>'name');sku:=trim(payload->>'sku');description:=coalesce(payload->>'description','');category:=coalesce(payload->>'category','');photo:=nullif(payload->>'image','');currency:=payload->>'currency';
 if title is null or length(title)not between 1 and 120 or sku is null or length(sku)not between 1 and 60 or length(description)>3000 or length(category)>60 then raise exception 'Revise nome, SKU, descrição e categoria';end if;
 if photo is not null and(length(photo)>900000 or photo !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$')then raise exception 'Envie uma foto JPEG pelo aplicativo';end if;
 if currency is null or currency not in('USD','BRL','PYG')then raise exception 'Informe a moeda';end if;
 if exists(select 1 from unnest(array['amount','rate','percent'])k where coalesce(payload->>k,'') !~ '^[0-9]+(\.[0-9]+)?$')then raise exception 'Preço, câmbio ou percentual inválido';end if;
 amount:=(payload->>'amount')::numeric;fx:=case when currency='BRL'then 1 else(payload->>'rate')::numeric end;pct:=(payload->>'percent')::numeric;
 if amount<=0 or amount>1000000000000 or fx<=0 or fx>1000000 or pct not between 0 and 1000 then raise exception 'Valores fora do limite';end if;
 cost:=round(amount*fx*100)::bigint;price:=round(cost*(1+pct/100))::bigint;
 if cost not between 1 and 999999900 or price not between 1 and 999999900 then raise exception 'Preço fora do limite da loja';end if;
 if coalesce(payload->>'stock','') !~ '^[0-9]{1,7}$'or coalesce(payload->>'minimum','') !~ '^[0-9]{1,7}$'or jsonb_typeof(payload->'online')is distinct from'boolean'then raise exception 'Estoque ou publicação inválidos';end if;
 stock:=(payload->>'stock')::integer;minimum:=(payload->>'minimum')::integer;online:=(payload->>'online')::boolean;
 if stock>1000000 or minimum>1000000 then raise exception 'Estoque fora do limite';end if;
 insert into public.products(id,user_id,name,sku,cost,price,stock,minimum,image,description,category,online)
 values(request_id,uid,title,sku,cost,price,stock,minimum,photo,description,category,online);
 insert into public.supplier_imports(user_id,product_id,supplier,source_url,original_amount,currency,exchange_rate,markup)
 values(uid,request_id,supplier,source,amount,currency,fx,pct);
 return query select request_id,false;
end;$$;
revoke all on function public.import_supplier_product(jsonb,uuid)from public,anon,authenticated;
grant execute on function public.import_supplier_product(jsonb,uuid)to authenticated;
commit;
