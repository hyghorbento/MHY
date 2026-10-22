// Somente fixtures de teste: downloads oficiais com a verificação TLS padrão do curl.
import{execFileSync}from'node:child_process';import{createHash}from'node:crypto';import{existsSync}from'node:fs';
const urls=['https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js','https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/worker.min.js','https://cdn.jsdelivr.net/npm/tesseract.js-core@6.0.0/tesseract-core-simd-lstm.wasm.js','https://cdn.jsdelivr.net/npm/@tesseract.js-data/eng@1.0.0/4.0.0_best_int/eng.traineddata.gz'];
for(const url of urls){const file=url.endsWith('/dist/tesseract.min.js')?'/tmp/tesseract.min.js':'/tmp/tess-'+createHash('sha256').update(url).digest('hex');if(!existsSync(file))execFileSync('curl',['--fail','--silent','--show-error','--max-time','60',url,'-o',file],{stdio:'inherit'});}
console.log('Arquivos oficiais de OCR disponíveis para os testes em /tmp.');
