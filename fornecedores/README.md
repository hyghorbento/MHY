# Fornecedores Paraguai

Projeto independente em `/fornecedores/`, compartilhando somente a hospedagem e
a conta Supabase da MHY IMPORTS para envio revisado de produtos. O dashboard da
MHY continua em `/`; seu `index.html` não foi modificado por este projeto.

## Escopo desta versão

Oito fornecedores: Charme, New Zone, Atacado Connect, Mega Eletrônicos, Cellshop,
Shopping China, Star Games e Intershop. Busca centralizada com seleção de lojas;
comparação das ofertas escolhidas pelo usuário; leitura por link direto;
preenchimento manual quando a loja não permite leitura; percentual manual por
produto; envio confirmado para estoque/catálogo da MHY. Sem compras automáticas.

Precificação: converte o preço unitário para reais usando o câmbio manual do
aparelho e acrescenta o percentual informado naquele produto. Nenhum percentual
padrão é aplicado. **Não calcula transporte, taxas ou custos de importação**.
Comparação com lojas oficiais do Brasil está fora do escopo desta primeira etapa.
Arredondamento decimal em centavos corresponde ao cálculo PostgreSQL.

## Consulta de fornecedores: limites e evidências

Após a publicação da configuração de rede pelo usuário em 22/10/2026, a pesquisa
real de `club de nuit` foi validada nos domínios públicos. O acesso Node neste
ambiente exige `NODE_USE_ENV_PROXY=1` para usar o proxy já fornecido; não desative
TLS nem extraia credenciais de proxy. A hospedagem Netlify usa sua rede normal.

- Atacado Connect: 20 itens lidos na primeira página; preço primário em U$.
- Shopping China: 7 itens; preço público em reais. Valores em dólares comentados
  no HTML não são utilizados como ofertas.
- Mega Eletrônicos: 22 itens; preço primário em U$.
- New Zone: 12 itens; `/busca/<termo>` confirmado no formulário e resposta real.
  Lê apenas preço unitário; o imposto estimado exibido à parte não é somado.
- Intershop: 19 itens; `/category?searchHttp=<termo>` confirmado no formulário.
- Charme: 12 itens, incluindo itens marcados sem estoque e sem valor. O formato
  `U$S: 30,00` é dólar explícito; não é convertido a partir do símbolo $ sozinho.
- Star Games: página real informou **Sem resultados** para o termo. O sistema
  distingue esse retorno explícito de uma falha de leitura.
- Cellshop: a página abriu, mas os resultados são carregados por JavaScript via
  serviço de busca. Essa integração continua pendente e é indicada como tal.

As quantidades acima registram o teste de 22/10/2026, não uma garantia de estoque
ou preço atual. As seis leituras são específicas dos layouts observados. Amostras
reais mínimas estão em tests/fixtures/suppliers para regressão. Bloqueios 403/406
podem variar por rede; não são contornados pelo aplicativo.

A função Netlify `suppliers` consulta HTML público e lê JSON-LD Product/ItemList,
microdados e cartões de produto (incluindo preços promocionais). Se a busca
contiver apenas links, consulta até quatro páginas do mesmo fornecedor em paralelo;
a leitura de um produto também aceita metadados Open Graph. Sites com conteúdo
só em JavaScript, autenticação, bloqueios ou formato diferente podem retornar
leitura indisponível. Não executa login nos fornecedores, não contorna CAPTCHA,
não inventa preços e não considera falta de leitura como falta de estoque.
Preços de faixa não são recomendações de menor preço e exigem revisão manual.
Modelos, versões, volumes e variantes devem ser comparados pelo usuário.

As requisições só aceitam HTTPS nos oito hosts, recusam credenciais/portas,
validam redirecionamentos, limitam tamanho/tempo e mantêm cache curto. A limitação
de chamadas em memória é por instância da função, não um rate limit distribuído.
Não existe proxy de URL arbitrária nem leitura de recursos privados do cliente.

Fotos externas dependem de CORS da loja/CDN: se não for possível preparar JPEG,
a tela informa e oferece upload da foto pelo aparelho. Não publica URL externa
incompatível como se fosse uma foto salva na MHY.

## Integração com o catálogo

No aplicativo, abra Configurações > Ativar integração > Copiar SQL da integração.
Execute `fornecedores/integracao.sql` no mesmo Supabase da MHY. É uma migração
aditiva; não recria tabelas de produtos nem altera cadastros anteriores.

A RPC `import_supplier_product` exige autenticação, calcula custo/preço no banco e
cria produto novo mais registro privado de origem numa transação. Não altera
vendas ou caixa. Retry pelo UUID e repetição do link não duplicam produto nem
sobrescrevem preços/estoque existentes. Informações da compra e percentual ficam
na tabela privada `supplier_imports`, protegida por RLS; não são acrescentadas à
descrição pública. A publicação no catálogo é opt-in; padrão é privado/estoque zero.
O usuário pode informar estoque disponível e optar por exibir no catálogo.

Use a conta da MHY no login. Na hospedagem existente, a sessão Supabase pode ser
compartilhada pelo mesmo navegador. Nenhuma senha ou chave privada fica no código.
A chave publishable é pública; as permissões continuam aplicadas no Supabase.

## Desenvolvimento e publicação

Use o checkout existente, sem criar worktree. Instale o parser HTML fixado no lockfile:

```sh
cd /workspace/MHY
npm ci
node fornecedores/dev.mjs
```

O servidor local inicia na porta 8010 e executa a função de consulta; a rede local
continua sujeita aos bloqueios descritos. O SQL da integração não é aplicado por
esse servidor nem pelo build. `PORT` permite escolher outra porta.

`node scripts/build.mjs` publica os arquivos do projeto em `dist/fornecedores/`
e preserva `dist/index.html` da MHY. O Netlify compila a função em
`netlify/functions/suppliers.mjs` com esbuild. Não abre produtos ou efetua compras
ao publicar o código.

Testes do parser e precificação (após npm ci):

```sh
node --test tests/suppliers.test.mjs
```

Testes PostgreSQL e navegador (opcionais; SKIP explícito sem dependências):

```sh
npm install --prefix /tmp/mhy-tools --cache /tmp/mhy-npm-cache @electric-sql/pglite@0.5.10
curl --fail --silent --show-error https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2 -o /tmp/mhy-supabase.js
NODE_PATH=/tmp/mhy-tools/node_modules:$NODE_PATH node --test tests/suppliers-db.test.cjs tests/suppliers-browser.test.cjs
```

O teste de navegador usa Playwright, Chromium `/usr/bin/chromium`, respostas de
fornecedores simuladas e PostgreSQL/PGlite local. Verifica integração real contra
o banco de teste, foto/câmbio/percentual/estoque/repetição de envio e telas de 390px;
não comprova leitura ao vivo dos fornecedores ou execução no Supabase real.

## v1.1 — Buscar por foto

Nova aba permite escolher foto da galeria, tirar foto, girar a imagem, ler o
nome/rótulo e revisar a consulta antes de pesquisar nas mesmas lojas selecionadas.
Usa OCR Tesseract.js 6.0.1 no navegador, com worker/core/modelo versionados no
jsDelivr. A imagem não é enviada ao Netlify, Supabase ou fornecedores pela busca;
só o texto confirmado vira consulta. O OCR pode errar em rótulos estilizados e
não identifica um produto apenas por sua aparência. Para uma foto sem nome
legível, o usuário pode editar a consulta. Não resolve bloqueios de leitura nas
lojas e não confirma preço ou identidade por similaridade visual.

No teste funcional, o OCR verdadeiro reconheceu ARMAF CLUB DE NUIT INTENSE MAN
em uma imagem de teste, encaminhou o texto editado para as oito consultas e não
enviou imagem na requisição. Para reproduzir com os arquivos oficiais em cache:

```sh
node scripts/cache-ocr-test-assets.mjs
node --test tests/suppliers-photo-browser.test.cjs
```

A liberação de rede foi aplicada pelo usuário em 22/10/2026. O teste no navegador
local executando a API real retornou 92 cartões para Club de Nuit (incluindo
variações e itens sem estoque), sem respostas simuladas de fornecedores. A
Cellshop continua pendente por carregar resultados em JavaScript.

## v1.2 — leitura validada com Club de Nuit

Substitui as buscas assistidas de New Zone e Intershop por rotas confirmadas e
inclui adaptadores específicos para os seis fornecedores acima. A leitura de
produto único não usa cartões de recomendações como se fossem o item selecionado.
Nenhuma alteração SQL ou de precificação foi necessária nesta correção.

## v1.3 — ordem dos resultados

Os cartões de situação das lojas ficam ao final da pesquisa, depois dos produtos.
O seletor Ordenar por oferece ordem da consulta, menor/maior preço em reais, nome
e fornecedor. Usa o câmbio manual salvo; ofertas sem preço exato ou câmbio ficam
no final em ambas as ordens de preço. Ordenar preserva a associação do produto aos
botões Comparar e Precificar, inclusive enquanto chegam resultados novos.
