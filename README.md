# MHY IMPORTS

Aplicativo de gestão e catálogo público em um único `index.html`, com Supabase.

## Desenvolvimento na nuvem

Use o checkout existente, sem criar outro worktree salvo solicitação explícita.
A fonte principal é `index.html`. A partir da raiz:

```sh
python3 -m http.server 8000 --bind 0.0.0.0
```

## Publicação automática no Netlify

O projeto já contém `netlify.toml`. O build `node scripts/build.mjs` copia somente
`index.html` para `dist/index.html`, sem dependências npm. A pasta publicada é `dist`.
O SQL e os documentos não são copiados para a publicação.

Para ativar, envie o código deste checkout ao repositório GitHub `hyghorbento/MHY`
e vincule esse repositório ao projeto **existente** no Netlify. Escolha a branch
que contém o aplicativo e deixe o Netlify usar `netlify.toml`.
No painel, procure Project configuration > Build & deploy > Continuous deployment
> Repository > Link repository. A interface pode usar nomes equivalentes.

Depois de conectado, cada push na branch de produção dispara build e publicação.
Trabalhar nesta conversa não publica sozinho: as alterações precisam ser enviadas
ao GitHub. Uma nova migração SQL precisa ser executada separadamente no Supabase;
o build não acessa nem altera o banco.

Use o mesmo projeto e domínio Netlify para preservar os links compartilhados.
Os dados estão no Supabase e não são apagados quando o HTML é republicado.
Não coloque service_role, senhas ou outros segredos no HTML ou no repositório.

A primeira conexão GitHub/Netlify ainda precisa ser realizada. A preparação local
não comprova publicação automática ativa.

Veja `ATUALIZAR.md` para configuração da personalização e do catálogo.

## Cupons

A aba Cupons cadastra descontos percentuais ou em reais, com compra mínima,
validade opcional e ativação. Execute `atualizacao-cupons.sql` uma vez no SQL Editor;
o mesmo código está em Cupons > Ativar cupons no Supabase > Copiar SQL dos cupons.
A migração preserva vendas anteriores e mantém o checkout sem cupom funcionando.

Visitantes aplicam o código na sacola, antes do WhatsApp. O banco consulta preços,
estoque disponível, validade e mínimo; o navegador não determina o desconto.
O pedido não consome estoque nem cupom e continua sujeito à confirmação da loja.
Ao confirmar no checkout administrativo, aplique o código recebido no WhatsApp.
A venda registra subtotal original, desconto e código, calculando taxa e lucro
após o desconto e preservando o custo integral dos produtos. Não há limite de
usos por cliente, cumulatividade de cupons ou pagamento online nesta versão.

Testes de sessão (sem dependências adicionais):

```sh
node --test tests/session.test.mjs
```

Para testar SQL em PostgreSQL/PGlite sem alterar o projeto Supabase real:

```sh
npm install --prefix /tmp/mhy-test-deps --cache /tmp/mhy-npm-cache @electric-sql/pglite@0.5.10
NODE_PATH=/tmp/mhy-test-deps/node_modules node --test tests/coupons-db.test.cjs
```

O teste de SQL fica explicitamente marcado como skipped se PGlite não estiver
instalado. Não interprete skipped como validação do banco.
