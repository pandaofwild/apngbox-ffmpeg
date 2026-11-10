// 사용: node scripts/ffmpeg-build/pe-imports.cjs <ffmpeg.exe>
// mfplat.dll이 정적 import에 있으면 Windows N(미디어 기능 팩 없음)에서 ffmpeg.exe가 아예 뜨지 않는다 — 없어야 한다.
// libwinpthread-1.dll · libgcc_s_*.dll · libstdc++-6.dll이 보이면 정적 링크가 빠진 것이다.
const fs = require('fs');
const b = fs.readFileSync(process.argv[2]);
const pe = b.readUInt32LE(0x3c);
const nsec = b.readUInt16LE(pe + 6), optSize = b.readUInt16LE(pe + 20), opt = pe + 24;
const dd = opt + 112; // PE32+ data directories
const secs = [];
for (let i = 0; i < nsec; i++) { const s = opt + optSize + i * 40; secs.push({ va: b.readUInt32LE(s + 12), vs: b.readUInt32LE(s + 8), raw: b.readUInt32LE(s + 20) }); }
const off = (rva) => { const s = secs.find(x => rva >= x.va && rva < x.va + Math.max(x.vs, 1)); return s ? rva - s.va + s.raw : -1; };
const str = (rva) => { let o = off(rva), e = o; while (b[e]) e++; return b.toString('latin1', o, e); };
const list = (dir, size, nameOff) => { const out = []; let o = off(b.readUInt32LE(dd + dir * 8)); if (o < 0 || !b.readUInt32LE(dd + dir * 8)) return out; for (;; o += size) { const n = b.readUInt32LE(o + nameOff); if (!n) break; out.push(str(n)); } return out; };
console.log('import:', list(1, 20, 12).join(' '));
console.log('delay :', list(13, 32, 4).join(' '));
