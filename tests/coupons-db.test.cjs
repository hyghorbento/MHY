const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
let PGlite;
try { ({PGlite}=require('@electric-sql/pglite')); } catch {}
// Integração opcional: requer @electric-sql/pglite no NODE_PATH ou instalado localmente.
test('cupons: migração, acesso público, cálculo financeiro e venda atômica', {skip:!PGlite}, async t=>{
 const root=path.join(__dirname,'..'),db=new PGlite();
 const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
 const base=html.split('const setupSQL = `')[1].split('`;')[0];
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('app.uid',true),'')::uuid $$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;create publication supabase_realtime;`);
 await db.exec(base);
 await db.exec(fs.readFileSync(path.join(root,'atualizacao-supabase.sql'),'utf8'));
 const sql=fs.readFileSync(path.join(root,'atualizacao-cupons.sql'),'utf8');
 await db.exec(sql);await db.exec(sql);
 const owner='11111111-1111-4111-8111-111111111111',other='22222222-2222-4222-8222-222222222222',pid='33333333-3333-4333-8333-333333333333',hidden='44444444-4444-4444-8444-444444444444';
 await db.exec(`insert into auth.users values('${owner}'),('${other}');set app.uid='${owner}';set role authenticated;insert into store_settings(name,published,whatsapp) values('MHY',true,'5541995492589');insert into products(id,name,sku,cost,price,stock,minimum,online) values('${pid}','Teste','TEST',3520,10000,30,1,true),('${hidden}','Privado','PRIVATE',500,1000,5,1,false);insert into coupons(code,kind,value,minimum,expires_at,active) values('DEZ','percent',1000,0,null,true),('FIXO','fixed',2500,0,null,true),('GRATIS','percent',10000,0,null,true),('MINIMO','fixed',1000,15000,null,true),('VENCIDO','percent',1000,0,now()-interval '1 hour',true),('INATIVO','percent',1000,0,null,false);reset role;set app.uid='';set role anon;`);
 const items=[{id:pid,qty:1}],validate=(code,cart=items,store=owner)=>db.query('select * from validate_coupon($1,$2,$3::jsonb)',[store,code,JSON.stringify(cart)]);
 let seq=0;const request=()=>`55555555-5555-4555-8555-${String(++seq).padStart(12,'0')}`;
 const checkout=(code,id=request(),payment='pix',parts=1,pass=false)=>db.query('select checkout_with_coupon($1::jsonb,$2,$3,$4,$5::uuid,$6)',[JSON.stringify(items),payment,parts,pass,id,code]);
 const asOwner=()=>db.exec(`reset role;set app.uid='${owner}';set role authenticated;`);
 await t.test('percentual, normalização e preço real, ignorando valores forjados',async()=>{const r=(await validate(' dez ',[{id:pid,qty:1,price:1,discount:999999}])).rows[0];assert.deepEqual(r,{code:'DEZ',subtotal:10000,discount:1000,total:9000});});
 await t.test('desconto fixo e teto no subtotal',async()=>{assert.equal((await validate('FIXO')).rows[0].discount,2500);await asOwner();await db.exec("update coupons set value=999999 where code='FIXO';reset role;set app.uid='';set role anon;");assert.equal((await validate('FIXO')).rows[0].total,0);});
 await t.test('validade, inatividade, mínimo e código inexistente',async()=>{for(const code of ['VENCIDO','INATIVO','MINIMO','NAOEXISTE'])await assert.rejects(()=>validate(code),/Cupom|mínimo/);assert.equal((await validate('MINIMO',[{id:pid,qty:2}])).rows[0].discount,1000);});
 await t.test('não divulga nem aceita produtos privados, quantidades inválidas ou duplicação',async()=>{await assert.rejects(()=>validate('DEZ',[{id:hidden,qty:1}]),/indisponível/);await assert.rejects(()=>validate('DEZ',[{id:pid,qty:-1}]),/Quantidade/);await assert.rejects(()=>validate('DEZ',[...items,...items]),/duplicado/);await assert.rejects(()=>validate('DEZ',[{id:pid,qty:999}]),/Quantidade indisponível/);});
 await t.test('visitante não lê cupons nem executa cálculo interno ou confirma venda',async()=>{await assert.rejects(()=>db.query('select * from coupons'),/permission denied/);await assert.rejects(()=>db.query('select mhy_coupon_discount($1,$2,10000)',[owner,'DEZ']),/permission denied/);await assert.rejects(()=>checkout('DEZ'),/permission denied/);});
 await t.test('RLS isola cupons entre contas',async()=>{await db.exec(`reset role;set app.uid='${other}';set role authenticated;`);assert.equal((await db.query('select * from coupons')).rows.length,0);assert.equal((await db.query("update coupons set active=false where code='DEZ' returning id")).rows.length,0);await asOwner();});
 await t.test('venda absorvendo PIX registra desconto, custo, lucro, caixa e estoque',async()=>{const id=request();await checkout('DEZ',id);const s=(await db.query('select * from sales where id=$1',[id])).rows[0];assert.equal(s.original_base,10000);assert.equal(s.base,9000);assert.equal(s.discount,1000);assert.equal(s.coupon_code,'DEZ');assert.equal(s.total,9000);assert.equal(s.fee,45);assert.equal(s.net,8955);assert.equal(s.profit,5435);assert.equal((await db.query('select amount from movements where sale_id=$1',[id])).rows[0].amount,8955);assert.equal((await db.query('select stock from products where id=$1',[pid])).rows[0].stock,29);await checkout('DEZ',id);assert.equal((await db.query('select stock from products where id=$1',[pid])).rows[0].stock,29);});
 await t.test('taxa repassada em 18x preserva o valor após desconto',async()=>{const id=request();await checkout('DEZ',id,'credit',18,true);const s=(await db.query('select * from sales where id=$1',[id])).rows[0];assert.equal(s.total,9277);assert.equal(s.fee,277);assert.equal(s.net,9000);assert.equal(s.profit,5480);});
 await t.test('cupom expirado antes da confirmação não consome estoque nem cria venda',async()=>{const stock=(await db.query('select stock from products where id=$1',[pid])).rows[0].stock,id=request();await assert.rejects(()=>checkout('VENCIDO',id),/expirado/);assert.equal((await db.query('select stock from products where id=$1',[pid])).rows[0].stock,stock);assert.equal((await db.query('select * from sales where id=$1',[id])).rows.length,0);});
 await t.test('desconto de 100% tem total zero e lucro negativo igual ao custo',async()=>{const id=request();await checkout('GRATIS',id);const s=(await db.query('select * from sales where id=$1',[id])).rows[0];assert.equal(s.total,0);assert.equal(s.discount,10000);assert.equal(s.net,0);assert.equal(s.profit,-3520);});
 await t.test('preço de centavos arredonda desconto sem exceder subtotal',async()=>{await db.exec(`update products set price=1 where id='${pid}'`);const r=(await validate('DEZ')).rows[0];assert.equal(r.discount,0);assert.equal(r.total,1);await db.exec(`update products set price=10000 where id='${pid}'`);});
 await t.test('checkout anterior continua funcionando sem cupom',async()=>{const id=request();await db.query('select checkout($1::jsonb,$2,1,false,$3::uuid)',[JSON.stringify(items),'pix',id]);const s=(await db.query('select * from sales where id=$1',[id])).rows[0];assert.equal(s.total,10000);assert.equal(s.discount,0);assert.equal(s.coupon_code,'');});
 await t.test('catálogo desativado impede validar cupons como visitante',async()=>{await db.exec(`update store_settings set published=false;reset role;set app.uid='';set role anon;`);await assert.rejects(()=>validate('DEZ'),/Catálogo indisponível/);});
 await db.close();
});
