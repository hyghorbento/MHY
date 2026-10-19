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
