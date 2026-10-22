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

O ambiente de desenvolvimento respondeu `Tunnel connection failed: 403 Forbidden`
para os oito domínios em 22/10/2026. Isso é uma restrição da rede deste ambiente,
não evidência de indisponibilidade das lojas. Nenhum preço real foi confirmado.
Para validar aqui, os domínios abaixo precisam estar acessíveis nas configurações
de rede do ambiente, preservando os domínios que já estiverem autorizados:

- www.charmeperfumeria.com.br / charmeperfumeria.com.br
- newzone.com.br / www.newzone.com.br
- atacadoconnect.com / www.atacadoconnect.com
- megaeletronicos.com / www.megaeletronicos.com
- cellshop.com.br / www.cellshop.com.br
- www.shoppingchina.com.br / shoppingchina.com.br
- stargamesparaguay.com / www.stargamesparaguay.com
- intershop.com.py / www.intershop.com.py

As rotas de Charme, Atacado Connect, Mega, Cellshop e Shopping China foram
compostas a partir dos links enviados pelo usuário. Star Games usa o formato
padrão de busca WooCommerce e precisa de validação ao vivo. New Zone e Intershop
ficam explicitamente em busca assistida: não foi inventada uma rota de pesquisa.

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

A liberação dos oito domínios e da hospedagem foi salva no rascunho de rede do
ambiente, preservando o preset de gerenciadores de pacotes. Só fica ativa após
revisar/salvar e publicar o ambiente. Até validar respostas reais, os novos
leitores HTML são melhorias testadas em fixtures, não correções confirmadas em
cada loja. Não contornam bloqueios HTTP 403/429 de Mega ou Cellshop.
