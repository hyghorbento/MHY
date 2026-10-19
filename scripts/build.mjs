// Mantém um único index.html como fonte e publica apenas o aplicativo.
import { mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
await mkdir(new URL('dist/', root), { recursive: true });
await copyFile(new URL('index.html', root), new URL('dist/index.html', root));
console.log(`Aplicativo preparado em ${fileURLToPath(new URL('dist/', root))}`);
