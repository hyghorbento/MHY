
begin;
alter table public.products add column if not exists online boolean not null default false;
alter table public.products add column if not exists category text not null default '';
alter table public.products add column if not exists description text not null default '';
create index if not exists products_public_catalog on public.products(user_id,online,id);
create table if not exists public.store_settings(
 user_id uuid primary key default auth.uid() references auth.users(id),
 name text not null default 'MHY IMPORTS' check(length(trim(name)) between 1 and 100),
 tagline text not null default '' check(length(tagline)<=300),
 headline text not null default '' check(length(headline)<=160),
 whatsapp text not null default '' check(whatsapp='' or whatsapp ~ '^[1-9][0-9]{9,14}$'),
 accent text not null default '#D4AF37' check(accent ~ '^#[0-9A-Fa-f]{6}$'),
 background text not null default '#0c0d10' check(background in ('#0c0d10','#111827','#171717')),
 logo text check(logo is null or (length(logo)<=500000 and logo like 'data:image/jpeg;base64,%')),
 banner text check(banner is null or (length(banner)<=1800000 and banner like 'data:image/jpeg;base64,%')),
 published boolean not null default false
);
alter table public.store_settings enable row level security;
drop policy if exists store_owner on public.store_settings;
create policy store_owner on public.store_settings for all to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
revoke all on public.store_settings from public,anon,authenticated;
grant select,insert,update,delete on public.store_settings to authenticated;

-- Catálogo só recebe os campos abaixo; custo e finanças não são concedidos ao visitante.
create or replace function public.get_storefront(store uuid)
returns table(name text,tagline text,headline text,whatsapp text,accent text,background text,logo text,banner text)
language sql stable security definer set search_path=public
as $$
 select s.name,s.tagline,s.headline,s.whatsapp,s.accent,s.background,s.logo,s.banner
 from public.store_settings s where s.user_id=store and s.published=true;
$$;
create or replace function public.get_catalog_products(store uuid,page_number integer default 0)
returns table(id uuid,name text,sku text,price bigint,image text,available boolean,category text,description text)
language sql stable security definer set search_path=public
as $$
 select p.id,p.name,p.sku,p.price,p.image,(p.stock>0),left(p.category,60),left(p.description,1000)
 from public.products p join public.store_settings s on s.user_id=p.user_id
 where s.user_id=store and s.published=true and p.online=true
 order by p.id limit 100 offset (greatest(0,least(coalesce(page_number,0),10000))*100);
$$;
revoke all on function public.get_storefront(uuid) from public,anon,authenticated;
revoke all on function public.get_catalog_products(uuid,integer) from public,anon,authenticated;
grant execute on function public.get_storefront(uuid) to anon,authenticated;
grant execute on function public.get_catalog_products(uuid,integer) to anon,authenticated;
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='store_settings') then
  alter publication supabase_realtime add table public.store_settings;
 end if;
end $$;
commit;
