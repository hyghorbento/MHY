# MHY v2 — personalização e catálogo

Preparado localmente, ainda não aplicado ao Supabase nem publicado no Netlify.

A versão completa continua em um único `index.html`. O complemento em
`atualizacao-personalizacao.html` pode ser copiado pelo chat e colado uma vez
antes de `</body>` do arquivo v1.1 que já funciona no computador do usuário.
Não substitua o arquivo inteiro apenas pelo complemento.

1. Faça uma cópia de segurança do HTML atual.
2. Execute `atualizacao-supabase.sql` no SQL Editor do projeto existente.
   O mesmo SQL está na nova tela Personalizar. Ele preserva produtos, vendas e caixa;
   acrescenta campos, tabela de configurações e consultas públicas com campos limitados.
   Produtos existentes iniciam com `online=false`.
3. Publique o `index.html` completo atualizado na publicação existente no Netlify,
   ou acrescente o complemento ao HTML já existente antes de publicar.
4. Entre com a mesma conta. Em Personalizar, configure nome, logo, banner, cor e fundo.
   Nome inicial: MHY IMPORTS. WhatsApp solicitado: +55 (41) 99549-2589.
5. Salve a personalização. Em Estoque, edite produtos e marque Exibir no catálogo.
6. Em Personalizar, marque Ativar catálogo público, salve e copie o link gerado.
   O link é o mesmo HTML com `?loja=<UUID do usuário>`.
7. Teste o link em janela anônima e em celular, sem login.

Visitantes recebem apenas nome/SKU/foto/categoria/descrição/preço/disponibilidade.
Não há leitura pública direta da tabela de produtos ou das tabelas financeiras.
As consultas públicas retornam dados apenas de lojas ativas e produtos selecionados.
Não publique service_role ou outras chaves secretas no HTML.

O carrinho abre o WhatsApp para revisão e envio pelo cliente. Não envia mensagens
sozinho, não recebe pagamentos, não reserva estoque nem registra vendas. O lojista
confirma a venda na área administrativa. A disponibilidade pública é atualizada
periodicamente e conferida novamente antes de preparar a mensagem do pedido.

Validação local: Playwright/Chromium em desktop e 390px; endpoints Supabase simulados
para testar personalização, catálogo e carrinho; scripts CDN baixados com TLS validado.
PostgreSQL/PGlite com auth.uid simulado: migração repetível, preservação de dados,
isolamento RLS, campos públicos, catálogo desativado e ausência de acesso financeiro anônimo.
O login, CRUD, sincronização e venda da v1.1 foram confirmados pelo usuário no projeto real.
A nova migração e a versão v2 ainda precisam ser executadas/publicadas pelo usuário;
não houve acesso administrativo ao Supabase ou Netlify nesta tarefa.

## v2.1 — cupons

A nova aba Cupons contém o SQL de `atualizacao-cupons.sql` e seu botão de cópia.
Execute esse SQL no projeto existente após a publicação do código. É uma migração
complementar; não repita a configuração inicial e não apague tabelas.
Cupons só passam a validar no projeto real depois dessa execução. As vendas sem
cupom continuam usando a função anterior. Consulte README.md para testes e regras.

## v3 — novos pagamentos e controle de cobrança

1. Aguarde a publicação da versão atual no Netlify e atualize o site.
2. Abra Contas a receber e copie o SQL da atualização v3 na seção de ativação.
3. Execute no SQL Editor do mesmo projeto Supabase e atualize o aplicativo.
4. Em Vendas, escolha Dinheiro ou Crediário/fiado. Para fiado, informe o cliente,
   escolha as parcelas e confira datas e valores. Sem juros.
5. Registre o dinheiro recebido em Contas a receber > Receber (parcial ou integral).
6. Use Histórico de vendas > Ver itens para conferir vendas antigas e novas.
7. Para encomendas não cadastradas, use Vendas > Item avulso/encomenda.

A migração é aditiva e não apaga dados existentes. Até a execução, recursos novos
não conseguem gravar no Supabase. Não repita o SQL inicial nem exclua tabelas.

## v3.1 — entrada no crediário, fotos e correção de vendas

1. Abra o site publicado e confira **v3.1** no cabeçalho.
2. Em **Contas a receber**, expanda **Ativar entrada, edição e exclusão protegida**.
3. Clique **Copiar SQL da atualização v3.1**; cole no SQL Editor do projeto
   Supabase existente e execute **Run**. O arquivo equivalente é
   `atualizacao-vendas-v31.sql`. Não execute o SQL inicial nem apague tabelas.
4. Atualize o aplicativo. Em Vendas > Crediário, informe a entrada recebida e
   parcele apenas o restante. Confira o caixa e o plano antes de confirmar.
5. Em Histórico, use **Editar** para corrigir uma venda antiga que ainda não foi
   paga: selecione Crediário, informe somente a entrada realmente recebida e
   ajuste as datas/valores do saldo. O total e os produtos são preservados.
6. Para excluir, informe novamente seu e-mail/senha e confirme os ajustes. A
   exclusão altera estoque, caixa e contas a receber; não é o comando de quitação.

O SQL mantém os dados existentes. Pagamentos de parcelas já registrados não são
apagados pela edição; só o restante recebe novo plano. Não execute migrações
anteriores depois da v3.1, pois elas podem substituir as funções atualizadas.

## v3.2 — editar lançamento manual de caixa

1. Atualize o sistema principal e confira v3.2 no cabeçalho.
2. Em **Fluxo de caixa**, expanda **Ativar edição do Fluxo de caixa** e clique
   **Copiar SQL de edição do caixa**.
3. Cole no SQL Editor do mesmo Supabase e execute Run; é uma atualização aditiva
   que preserva todos os lançamentos e vendas existentes.
4. Atualize o sistema, localize o lançamento manual e clique **Editar**.
5. Corrija descrição, tipo, valor ou data/hora; confira a variação prevista no
   saldo e confirme **Salvar correção**.

O sistema não duplica o lançamento corrigido. Vendas mantêm o vínculo e devem ser
corrigidas por **Corrigir na venda**. Pagamentos de parcelas não são liberados para
edição financeira isolada pelo Fluxo de caixa.
