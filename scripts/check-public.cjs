const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const violations=[];
const forbidden=[
 ['private key',/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
 ['JWT credential',/eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/],
 ['GitHub credential',/(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/],
 ['Supabase credential',/sb_(?:publishable|secret)_[A-Za-z0-9_-]{16,}/],
 ['production Supabase URL',/https:\/\/(?!your-project\.)[a-z0-9]{20}\.supabase\.co/],
 ['Netlify production URL',/https:\/\/[a-z0-9-]+\.netlify\.app/],
 ['local user path',/\/Users\/[^/\s]+\//]
];
function scan(dir){for(const item of fs.readdirSync(dir,{withFileTypes:true})){
 if(['.git','node_modules'].includes(item.name))continue;
 const full=path.join(dir,item.name),rel=path.relative(root,full);
 if(item.isDirectory()){
  if(['.banking-private','copias'].includes(item.name))violations.push(rel+': private folder');
  scan(full);continue;
 }
 if(/\.(pem|key|p12)$/i.test(item.name)||/^\.env(?:\.|$)/.test(item.name))violations.push(rel+': private file');
 if(/\.(png|jpg|jpeg|gif|webp)$/i.test(item.name))continue;
 const text=fs.readFileSync(full,'utf8');
 for(const [label,pattern] of forbidden)if(pattern.test(text))violations.push(rel+': '+label);
}}
scan(root);
const demo=fs.readFileSync(path.join(root,'index.html'),'utf8');
if(/\bfetch\s*\(|\bXMLHttpRequest\b|\bWebSocket\b|\bsendBeacon\b/.test(demo))violations.push('demo: external transport present');
if(!demo.includes("connect-src 'none'"))violations.push('demo: missing connection isolation');
if(violations.length){console.error(violations.join('\n'));process.exit(1)}
console.log('Public copy: no detected credentials, production URLs or private files; demo connections disabled.');
