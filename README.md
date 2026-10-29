# MHY IMPORTS

Aplicativo de gestão e catálogo público em um único `index.html`, com Supabase.

## Desenvolvimento na nuvem

Use o checkout existente, sem criar outro worktree salvo solicitação explícita.
A fonte principal é `index.html`. A partir da raiz:

```sh
python3 -m http.server 8000 --bind 0.0.0.0
```

## Publicação automática no Netlify

O projeto já contém `netlify.toml`. O build `node scripts/build.mjs` copia o dashboard para `dist/index.html` e
o projeto Fornecedores para `dist/fornecedores/`. A função de consulta usa Cheerio;
instale as dependências com `npm ci`. A pasta publicada é `dist`.
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

## v3 — dinheiro, crediário, histórico e avulsos

Execute `atualizacao-vendas-v3.sql` uma vez no projeto existente. O mesmo SQL está
em Contas a receber > Ativar dinheiro, crediário e itens avulsos > Copiar SQL.
A migração preserva registros existentes e inclui os pré-requisitos de cupons.
Vendas normais sem os recursos novos continuam com fallback para o checkout anterior
caso a migração ainda não tenha sido aplicada. A migração v3 deve ser a última na
sequência; executar manualmente migrações antigas depois dela pode substituir funções.
O botão de SQL dos cupons na interface atual já entrega a migração compatível com v3.

- Dinheiro: taxa zero e entrada imediata no caixa.
- Crediário: cliente obrigatório; telefone opcional; de 1 a 24 parcelas, sem juros,
  com datas e valores configuráveis. Não cria entrada de caixa ao registrar a venda.
- Contas a receber: parcelas, saldos, atrasos, busca por cliente e pagamento parcial
  ou total. O botão de cobrança prepara uma mensagem no WhatsApp para o lojista revisar;
  não envia mensagens automaticamente.
- Recebimento: dinheiro sem taxa, PIX 0,50%, débito 0,99% ou crédito à vista 2,99%.
  A dívida baixa pelo valor pago pelo cliente; o caixa recebe o líquido após taxa.
- Dashboard: faturamento contempla vendas a prazo; lucro realizado do crediário
  reconhece a proporção do custo referente ao principal recebido, menos as taxas
  efetivamente registradas. O saldo a receber e o total vencido ficam separados.
- Histórico: todas as vendas, filtros de data/pagamento/cliente/produto, itens e detalhes.
  Os nomes e valores registrados na venda são preservados mesmo se o cadastro mudar.
- Item avulso/encomenda: descrição, custo, preço e quantidade na sacola. Não cria
  produto e não baixa estoque. Carrinho pode misturar avulsos e produtos cadastrados.

Os dados de clientes, parcelas e recebimentos têm RLS e somente leitura para o dono.
Inserções e baixas são efetuadas por funções transacionais autenticadas e idempotentes.
O catálogo público não recebe dados do crediário e não permite criar itens avulsos.

Testes PostgreSQL locais (PGlite instalado conforme instrução acima):

```sh
NODE_PATH=/tmp/mhy-test-deps/node_modules node --test tests/session.test.mjs tests/coupons-db.test.cjs tests/sales-v3-db.test.cjs
```

A execução da migração no Supabase real é uma etapa do usuário; o build do Netlify
apenas publica HTML e não executa SQL no banco.

## v3.1 — entrada, correções e exclusão de vendas

Execute `atualizacao-vendas-v31.sql` uma vez no mesmo banco (ou copie em
**Contas a receber > Ativar entrada, edição e exclusão protegida > Copiar SQL v3.1**).
A migração inclui os recursos v3 e preserva cadastros, vendas e pagamentos atuais.
Não repita versões antigas do SQL depois desta atualização.

- Em **Vendas > Crediário**, informe a entrada recebida e sua forma de pagamento.
  O plano divide somente o restante; permite ajustar cada vencimento e valor.
  A entrada vai ao caixa com a taxa correspondente (dinheiro 0; PIX 0,50%;
  débito 0,99%; crédito à vista 2,99%). As parcelas futuras só entram ao receber.
- **Histórico de vendas** mostra fotos, nomes e saldo; as vendas recentes do
  dashboard também mostram o item. Novas vendas guardam a foto no histórico.
  Vendas antigas usam a foto do cadastro enquanto o produto existir.
- **Editar** corrige cliente, telefone, forma de pagamento, entrada e plano do saldo.
  Preserva o total, itens e baixa de estoque. Uma venda antiga marcada paga pode
  virar crediário com entrada zero ou parcial, corrigindo o caixa. Recebimentos de
  parcelas já lançados são preservados: suas parcelas ficam quitadas e o restante
  recebe novas datas/valores. A entrada não inclui os recebimentos posteriores.
  Valores e taxas históricos são mantidos se a entrada e a forma não mudam.
- **Excluir** exige e-mail/senha da conta conectada e confirmação dos ajustes.
  Um cliente Supabase separado e sem persistência valida a senha; o banco exige
  `amr.password` recente (até 120 segundos), além da propriedade da venda e revisão
  atual. Uma renovação comum de token não renova essa prova de senha. A senha não
  é enviada a funções SQL, salva ou registrada no histórico.
  A exclusão restaura estoque dos produtos ainda cadastrados, remove parcelas e
  lançamentos vinculados, e guarda snapshot privado em `sale_changes`. Não faz
  devolução financeira ao cliente. Use **Receber** para quitar dívidas reais.
- A revisão da venda impede sobrescrever um recebimento feito em outro aparelho.
  Alterações e exclusões são transacionais; repetir exclusão não duplica estoque.

Validação financeira e de autenticação (PGlite):

```sh
NODE_PATH=/tmp/mhy-tools/node_modules:$NODE_PATH node --test tests/*-db.test.cjs tests/session.test.mjs
```

O teste `tests/sales-v31-browser.test.cjs` usa Playwright/Chromium e PGlite,
serve o HTML localmente e intercepta somente os endpoints de teste. Configure
`MHY_CDN_CACHE` com os scripts oficiais `mhy-tailwind.js` e `mhy-supabase.js`
baixados com verificação TLS (padrão `/tmp`) e, se necessário, `CHROMIUM_PATH`.
Sem as dependências/arquivos, o teste informa SKIP; não valida o Supabase real.

## Projeto Fornecedores Paraguai

A aplicação independente está em [`fornecedores/`](fornecedores/README.md),
publicada pelo mesmo build em `/fornecedores/`. Pesquisa oito fornecedores,
compara ofertas em reais e aplica percentual manual por produto, sem cálculo de
custos de importação. Integração com a MHY por login e RPC revisada; produtos
existentes permanecem intactos. As limitações de leitura pública, ativação SQL e
testes estão no README do projeto. `netlify/functions/suppliers.mjs` faz consultas
públicas no servidor com hosts restritos. A pesquisa real de Club de Nuit foi validada em seis lojas após a liberação
da rede; a integração da Cellshop continua pendente. Veja o README do projeto.

## v3.2 — edição do Fluxo de caixa

Em Fluxo de caixa, cada lançamento **manual** tem o botão Editar para corrigir
descrição, entrada/saída, valor positivo e data/hora. A edição substitui o registro
no cálculo, atualiza saldo/indicadores e guarda antes/depois em tabela privada
`cash_movement_changes`, com RLS da conta. Não cria segunda movimentação nem
executa transferência ou devolução bancária. Uma revisão evita sobrescrever
correções de outro aparelho, e o identificador da solicitação torna retries seguros.

Execute `atualizacao-fluxo-caixa.sql` no mesmo Supabase, uma vez. O SQL está no
final da aba **Fluxo de caixa > Ativar edição > Copiar SQL de edição do caixa**.
Não execute novamente o SQL inicial. Não há exclusão de lançamentos nesta versão.
Vendas e pagamentos vinculados não podem ter valores editados por essa RPC:
lançamentos de venda oferecem **Corrigir na venda**, e parcelas mostram sua origem
em Contas a receber. A função mantém privilégios de update direto bloqueados.

Testes `cash-edit-db.test.cjs` e `sales-v31-browser.test.cjs` verificam alteração de
valor/tipo/data, caixa recalculado, proteção da origem, histórico, retry, isolamento,
migração repetível e regressão de vendas/crediário/login. Sem alterações nos dados
reais até o usuário executar o SQL e salvar uma correção autenticada.
