// Seeded differential fuzz restricted to upstream's documented JSONC grammar
// (docs/menu.md: whole-line // comments + trailing commas; strings never carry
// a comma followed by optional whitespace and } or ]). Compares each variant's
// parseMenuJsonc with a reference model.
const V=process.argv.slice(2).map(f=>[f.split('/').pop(),require(f)]);
let seed=+process.env.SEED||12345; const rnd=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return ((seed>>>0)%1e6)/1e6};
const pick=a=>a[Math.floor(rnd()*a.length)];
const STR=['a','A // B','q\\"','http://x','q\\\\','é—✓','','a, b','x ]y','{"k": 1}','// not a comment'];
const str=()=>JSON.stringify(pick(STR));
const ws=()=>pick(['',' ','\n','\n  ','\r\n','\t']);
const cm=()=>rnd()<0.3?'\n'+pick(['','  ','\t'])+pick(['// full line','// c, } ]','//','// "quoted','// x\r'])+'\n':ws();
function gen(){const n=1+Math.floor(rnd()*3);let o=(rnd()<0.2?'// head\n':'')+'{'+cm();
 for(let i=0;i<n;i++){o+=JSON.stringify('k'+i)+':'+ws()+'{'+cm()+'"label":'+ws()+str()+(rnd()<0.4?','+cm()+'"aliases":'+ws()+'['+cm()+str()+(rnd()<0.5?','+cm():cm())+']':'')+(rnd()<0.4?','+cm():cm())+'}';
  if(i<n-1) o+=','+cm(); else o+=(rnd()<0.5?','+cm():cm());}
 return o+'}'+(rnd()<0.3?'\n// tail line':'')}
function ref(t){ // reference: drop whole comment lines, then drop commas whose next significant char closes (string-aware)
 const lines=t.split('\n').filter(l=>!/^\s*\/\//.test(l)).join('\n'); let o='',s=false;
 for(let i=0;i<lines.length;i++){const c=lines[i]; if(s){o+=c; if(c==='\\'){o+=lines[++i]} else if(c==='"') s=false} else if(c==='"'){s=true;o+=c} else if(c===','){let j=i+1;while(j<lines.length&&/\s/.test(lines[j]))j++; if(!(lines[j]==='}'||lines[j]===']')) o+=c} else o+=c}
 try{const p=JSON.parse(o);return Object.keys(p).map(k=>k+'='+(p[k].label||k)+'|'+JSON.stringify((p[k].aliases||[]).filter(x=>x))).join(';')}catch(e){return 'ERR:'+e.message}}
const N=+process.env.N||20000; const bad={}, ex={}; let referr=0;
for(let k=0;k<N;k++){const s=gen(); const want=ref(s); if(want.startsWith('ERR')){referr++;continue}
 for(const [name,m] of V){const got=m.parseMenuJsonc(s).map(r=>r.id+'='+r.label+'|'+JSON.stringify(r.aliases)).join(';'); if(got!==want){bad[name]=(bad[name]||0)+1; (ex[name]=ex[name]||[]).length<2&&ex[name].push({s,want,got})}}}
console.log('cases',N,'reference-invalid(skipped)',referr);
for(const [name] of V) console.log(name.padEnd(24),'wrong:',bad[name]||0);
for(const n in ex) for(const e of ex[n]) console.log(n,JSON.stringify(e).slice(0,300));
