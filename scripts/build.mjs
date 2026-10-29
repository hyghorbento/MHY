// Publica a MHY e o projeto independente Fornecedores Paraguai.
import { mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
await mkdir(new URL('dist/', root), { recursive: true });
await copyFile(new URL('index.html', root), new URL('dist/index.html', root));
await mkdir(new URL('dist/fornecedores/', root), { recursive: true });
for(const file of ['index.html','app.mjs','app.css','suppliers.mjs','photo-search.mjs','shopping-list.mjs','integracao.sql']){
 await copyFile(new URL('fornecedores/'+file,root),new URL('dist/fornecedores/'+file,root));
}
console.log(`Aplicativo preparado em ${fileURLToPath(new URL('dist/', root))}`);
