// Phụ đề Việt — add-on phụ đề tiếng Việt cho Stremio (Mac, iPhone, Android, TV)
// Chạy trên Cloudflare Workers.
//   Không cần key nào. Nguồn chính: OpenSubtitles (qua máy chủ của Stremio, miễn phí).
//   Secret tuỳ chọn : SUBDL_KEY  (thêm nguồn SubDL, cũng miễn phí)
//   Binding tuỳ chọn: AI         (Workers AI, dùng dự phòng khi Google Dịch lỗi)
//
// Mỗi phim trả về:
//   • phụ đề tiếng Việt có sẵn (OpenSubtitles, SubDL) — đã sửa bảng mã, SRT UTF-8
//   • phụ đề "dịch máy" Anh → Việt từ phụ đề tiếng Anh khớp nhất

const VERSION = '2.2.0';
const MAX_VI = 6;       // số phụ đề Việt có sẵn tối đa
const MAX_TR = 2;       // số phụ đề dịch máy tối đa
const CHUNK = 4000;     // số ký tự mỗi lần gửi Google Dịch

const MANIFEST = {
  id: 'com.thayphong.phudeviet',
  version: VERSION,
  name: 'Phụ đề Việt',
  description: 'Phụ đề tiếng Việt từ OpenSubtitles và SubDL + phụ đề tự dịch Anh → Việt.',
  logo: 'https://flagcdn.com/w160/vn.png',
  resources: ['subtitles'],
  types: ['movie', 'series'],
  idPrefixes: ['tt'],
  catalogs: [],
  behaviorHints: { configurable: false, configurationRequired: false }
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS'
};

const json = (obj, maxAge = 0) => new Response(JSON.stringify(obj), {
  headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': `public, max-age=${maxAge}` }
});

// ---------------------------------------------------------------- router
export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    const p = url.pathname;
    try {
      if (p === '/' || p === '') return home(url);
      if (p === '/manifest.json') return json(MANIFEST, 3600);
      if (p === '/kiemtra') return json(await selfTest(env));
      let m = p.match(/^\/subtitles\/(movie|series)\/([^/]+?)(?:\/([^/]*))?\.json$/);
      if (m) return await cached(request, ctx, () => listSubs(url, env, m[1], decodeURIComponent(m[2]), m[3] || ''), 6 * 3600);
      m = p.match(/^\/sub\/(vi|tr)\/(os|sd)\/([A-Za-z0-9_-]+)\/(\d+)\/(\d+)\/[^/]+\.srt$/);
      if (m) return await cached(request, ctx, () => serveSub(env, m[1], m[2], b64d(m[3]), +m[4], +m[5]), 30 * 86400);
      return new Response('Not found', { status: 404, headers: CORS });
    } catch (e) {
      return new Response('Lỗi: ' + (e && e.message || e), { status: 500, headers: CORS });
    }
  }
};

async function cached(request, ctx, make, maxAge) {
  const cache = typeof caches !== 'undefined' ? caches.default : null;
  const ku = new URL(request.url); ku.searchParams.set('v', VERSION);
  const key = new Request(ku.toString(), { method: 'GET' });
  if (cache) { const hit = await cache.match(key); if (hit) return hit; }
  const res = await make();
  const noStore = /max-age=0/.test(res.headers.get('Cache-Control') || '');
  if (cache && res.status === 200 && !noStore) {
    const copy = new Response(res.clone().body, res);
    copy.headers.set('Cache-Control', `public, max-age=${maxAge}`);
    ctx && ctx.waitUntil ? ctx.waitUntil(cache.put(key, copy)) : await cache.put(key, copy);
  }
  return res;
}

function home(url) {
  const m = `${url.origin}/manifest.json`;
  const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phụ đề Việt</title>
<body style="font:17px -apple-system,Arial;max-width:560px;margin:40px auto;padding:0 18px;text-align:center">
<h1>🇻🇳 Phụ đề Việt ${VERSION}</h1>
<p>Phụ đề tiếng Việt + tự dịch Anh → Việt cho Stremio.</p>
<p><a href="stremio://${url.host}/manifest.json" style="display:inline-block;background:#7b5bf5;color:#fff;padding:14px 26px;border-radius:10px;text-decoration:none;font-weight:600">Cài vào Stremio</a></p>
<p>Hoặc dán link này vào ô tìm add-on của Stremio:</p>
<p><code style="background:#eee;padding:8px;border-radius:6px;word-break:break-all">${m}</code></p>
</body>`;
  return new Response(html, { headers: { ...CORS, 'Content-Type': 'text/html; charset=utf-8' } });
}

// ---------------------------------------------------------------- danh sách phụ đề
async function listSubs(url, env, type, id, extraStr) {
  const [imdb, sStr, eStr] = id.split(':');
  const season = +sStr || 0, episode = +eStr || 0;
  const extra = Object.fromEntries(new URLSearchParams(extraStr));
  const filename = (extra.filename || '').toLowerCase();
  const toks = new Set(filename.split(/[^a-z0-9]+/).filter(t => t.length > 1));
  const match = name => {
    let sc = 0;
    for (const t of (name || '').toLowerCase().split(/[^a-z0-9]+/)) if (toks.has(t)) sc += 1;
    return sc;
  };

  const [os, sd] = await Promise.all([
    fromOpenSubtitles(type, id, extraStr).catch(() => []),
    env.SUBDL_KEY ? fromSubDL(env, type, imdb, season, episode).catch(() => []) : []
  ]);
  const all = [...os, ...sd];

  const okEp = s => {
    if (!season) return true;
    if (s.season && s.season !== season) return false;
    if (s.episode && episode && s.episode !== episode) return false;
    return true;
  };
  const score = s => match(s.name) + (episode && s.episode === episode ? 5 : 0)
    + (/\b(cam|ts|telesync|hdcam)\b/i.test(s.name || '') ? -3 : 0) + (s.src === 'os' ? 0.5 : 0);
  const pick = (arr, n) => arr.filter(okEp).sort((a, b) => score(b) - score(a))
    .filter((s, i, a) => a.findIndex(x => x.ref === s.ref) === i).slice(0, n);

  const vi = pick(all.filter(s => s.lang === 'vi'), MAX_VI);
  const en = pick(all.filter(s => s.lang === 'en'), MAX_TR);
  const mk = (mode, s, i) => ({
    id: `phudeviet-${mode}-${s.src}-${i}`,
    url: `${url.origin}/sub/${mode}/${s.src}/${b64e(s.ref)}/${season}/${episode}/${mode === 'vi' ? 'vietsub' : 'dichmay'}.srt`,
    lang: 'vie',
    label: mode === 'vi' ? `Tiếng Việt – ${(s.name || '').slice(0, 60)}` : `Tiếng Việt (dịch máy) – ${(s.name || '').slice(0, 50)}`
  });
  const out = [...vi.map((s, i) => mk('vi', s, i)), ...en.map((s, i) => mk('tr', s, i))];
  return json({ subtitles: out, cacheMaxAge: 6 * 3600 }, out.length ? 6 * 3600 : 0);
}

// OpenSubtitles qua máy chủ của Stremio: miễn phí, không cần key
async function fromOpenSubtitles(type, id, extraStr) {
  const u = `https://opensubtitles-v3.strem.io/subtitles/${type}/${encodeURIComponent(id)}${extraStr ? '/' + extraStr : ''}.json`;
  const r = await fetch(u);
  if (!r.ok) return [];
  const d = await r.json();
  return (d.subtitles || [])
    .filter(s => (s.lang === 'vie' || s.lang === 'eng') && /^https:\/\/[\w.-]*strem\.io\//.test(s.url || ''))
    .map(s => ({
      src: 'os', ref: s.url, lang: s.lang === 'vie' ? 'vi' : 'en',
      name: s.movieReleaseName || s.subtitleFileName || 'OpenSubtitles',
      season: +s.season || 0, episode: +s.episode || 0
    }));
}

async function fromSubDL(env, type, imdb, season, episode) {
  const q = new URLSearchParams({
    api_key: env.SUBDL_KEY, imdb_id: imdb, type: type === 'series' ? 'tv' : 'movie',
    languages: 'VI,EN', subs_per_page: '30'
  });
  if (season) q.set('season_number', String(season));
  if (episode) q.set('episode_number', String(episode));
  const r = await fetch('https://api.subdl.com/api/v1/subtitles?' + q, { headers: { Accept: 'application/json' } });
  if (!r.ok) return [];
  const d = await r.json();
  return (d.subtitles || []).map(s => ({
    src: 'sd', ref: String(s.url || '').split('?')[0],
    lang: (/viet/i.test(s.lang || '') || /^vi$/i.test(s.language || '')) ? 'vi'
      : (/^english$/i.test(s.lang || '') || /^en$/i.test(s.language || '')) ? 'en' : '',
    name: s.release_name || s.name || 'SubDL', season: +s.season || 0, episode: +s.episode || 0
  })).filter(s => s.lang);
}

// ---------------------------------------------------------------- tải + xử lý 1 phụ đề
async function serveSub(env, mode, src, ref, season, episode) {
  let dl;
  if (src === 'sd' && /^\/subtitle\/[\w.\-]+$/.test(ref)) dl = 'https://dl.subdl.com' + ref;
  else if (src === 'os' && /^https:\/\/[\w.-]*strem\.io\//.test(ref)) dl = ref;
  else return new Response('bad path', { status: 400, headers: CORS });
  const path = dl;
  const r = await fetch(dl);
  if (!r.ok) return new Response('download ' + r.status, { status: 502, headers: CORS });
  const buf = new Uint8Array(await r.arrayBuffer());

  let files;
  let data = buf;
  if (data[0] === 0x1f && data[1] === 0x8b) data = await gunzip(data);
  if (data[0] === 0x50 && data[1] === 0x4b) files = await unzip(data);
  else files = [{ name: /\.(srt|ass|ssa|vtt)$/i.test(path) ? path.split('/').pop() : 'sub.srt', data }];
  files = files.filter(f => /\.(srt|ass|ssa|vtt|sub|txt)$/i.test(f.name));
  if (!files.length) return new Response('Không có file phụ đề trong gói', { status: 404, headers: CORS });

  const f = chooseFile(files, season, episode);
  const text = decodeText(f.data);
  let cues = /\.(ass|ssa)$/i.test(f.name) || /^\s*\[Script Info\]/i.test(text) ? parseAss(text) : parseSrt(text);
  if (!cues.length) return new Response('Không đọc được phụ đề', { status: 422, headers: CORS });

  let ok = true;
  if (mode === 'tr') {
    const r = await translateCues(cues, env);
    cues = r.cues;
    ok = r.ratio >= 0.6;
  }
  return new Response(toSrt(cues), {
    headers: { ...CORS, 'Content-Type': 'application/x-subrip; charset=utf-8',
      'Cache-Control': ok ? 'public, max-age=2592000' : 'max-age=0' }
  });
}

function chooseFile(files, season, episode) {
  if (files.length === 1) return files[0];
  if (season && episode) {
    const s = season, e = episode, e2 = String(e).padStart(2, '0');
    const res = [
      new RegExp(`s0*${s}[ ._-]*e0*${e}(?!\\d)`, 'i'),
      new RegExp(`(?<!\\d)${s}x0*${e}(?!\\d)`, 'i'),
      new RegExp(`(?:e|ep|episode|tap|tập)[ ._-]*0*${e}(?!\\d)`, 'i'),
      new RegExp(`(?<!\\d)${e2}(?!\\d)`)
    ];
    for (const re of res) { const hit = files.find(f => re.test(f.name)); if (hit) return hit; }
  }
  const pref = files.filter(f => /\.srt$/i.test(f.name));
  return (pref.length ? pref : files).sort((a, b) => b.data.length - a.data.length)[0];
}

// ---------------------------------------------------------------- giải nén ZIP
async function unzip(buf) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) return [];
  const count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  const out = [];
  for (let n = 0; n < count && p + 46 <= buf.length; n++) {
    if (dv.getUint32(p, true) !== 0x02014b50) break;
    const flags = dv.getUint16(p + 8, true);
    const method = dv.getUint16(p + 10, true);
    const csize = dv.getUint32(p + 20, true);
    const nlen = dv.getUint16(p + 28, true), xlen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true);
    const loc = dv.getUint32(p + 42, true);
    const nameBytes = buf.subarray(p + 46, p + 46 + nlen);
    const name = (flags & 0x800) ? new TextDecoder().decode(nameBytes) : latin(nameBytes);
    p += 46 + nlen + xlen + clen;
    if (name.endsWith('/')) continue;
    const lnl = dv.getUint16(loc + 26, true), lxl = dv.getUint16(loc + 28, true);
    const start = loc + 30 + lnl + lxl;
    const comp = buf.subarray(start, start + csize);
    let data = null;
    if (method === 0) data = comp;
    else if (method === 8) data = await inflate(comp);
    if (data) out.push({ name: name.split('/').pop(), data });
  }
  return out;
}

async function inflate(u8) {
  const ds = new DecompressionStream('deflate-raw');
  const res = new Response(new Blob([u8]).stream().pipeThrough(ds));
  return new Uint8Array(await res.arrayBuffer());
}

async function gunzip(u8) {
  const res = new Response(new Blob([u8]).stream().pipeThrough(new DecompressionStream('gzip')));
  return new Uint8Array(await res.arrayBuffer());
}

const latin = b => Array.from(b, c => String.fromCharCode(c)).join('');

// ---------------------------------------------------------------- bảng mã
const CP1258_HI = (() => {
  // 0x80–0xFF của Windows-1258 (bảng mã Việt cũ hay gặp trong file .srt)
  const t = '€\u0081‚ƒ„…†‡ˆ‰\u008a‹Œ\u008d\u008e\u008f\u0090‘’“”•–—˜™\u009a›œ\u009d\u009eŸ' +
    ' ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿' +
    'ÀÁÂĂÄÅÆÇÈÉÊË̀ÍÎÏĐÑ̉ÓÔƠÖ×ØÙÚÛÜỮß' +
    'àáâăäåæçèéêë́íîïđṇ̃óôơö÷øùúûüư₫ÿ';
  return Array.from(t);
})();

function decodeText(b) {
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return new TextDecoder('utf-8').decode(b.subarray(3));
  if (b[0] === 0xff && b[1] === 0xfe) return new TextDecoder('utf-16le').decode(b.subarray(2));
  if (b[0] === 0xfe && b[1] === 0xff) {
    const sw = new Uint8Array(b.length - 2);
    for (let i = 2; i + 1 < b.length; i += 2) { sw[i - 2] = b[i + 1]; sw[i - 1] = b[i]; }
    return new TextDecoder('utf-16le').decode(sw);
  }
  // UTF-16 không có BOM (nhiều số 0 xen kẽ)
  let zeros = 0;
  for (let i = 1; i < Math.min(b.length, 2000); i += 2) if (b[i] === 0) zeros++;
  if (zeros > 300) return new TextDecoder('utf-16le').decode(b);
  try { return new TextDecoder('utf-8', { fatal: true }).decode(b); } catch (e) { /* không phải UTF-8 */ }
  let s = '';
  for (const c of b) s += c < 0x80 ? String.fromCharCode(c) : CP1258_HI[c - 0x80];
  return s.normalize('NFC');
}

// ---------------------------------------------------------------- đọc SRT / ASS
function parseTime(t) {
  const m = t.trim().match(/(?:(\d+):)?(\d{1,2}):(\d{1,2})[,.](\d{1,3})/);
  if (!m) return null;
  return ((+(m[1] || 0)) * 3600 + (+m[2]) * 60 + (+m[3])) * 1000 + +m[4].padEnd(3, '0');
}

function parseSrt(text) {
  const cues = [];
  const blocks = text.replace(/\r\n?/g, '\n').replace(/^WEBVTT[^\n]*\n/, '').split(/\n\s*\n/);
  for (const blk of blocks) {
    const lines = blk.split('\n').filter(l => l.trim() !== '');
    const ti = lines.findIndex(l => l.includes('-->'));
    if (ti < 0) continue;
    const [a, b] = lines[ti].split('-->');
    const start = parseTime(a), end = parseTime(b);
    if (start == null || end == null) continue;
    const body = lines.slice(ti + 1).join('\n').trim();
    if (body) cues.push({ start, end, text: body });
  }
  return cues;
}

function parseAss(text) {
  const cues = [];
  let fmt = null;
  for (const raw of text.replace(/\r/g, '').split('\n')) {
    const line = raw.trim();
    if (/^Format:/i.test(line) && fmt === null && /Start/i.test(line) && /Text/i.test(line)) {
      fmt = line.slice(7).split(',').map(s => s.trim().toLowerCase());
    } else if (/^Dialogue:/i.test(line)) {
      const f = fmt || ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
      const parts = line.slice(9).split(',');
      const head = parts.slice(0, f.length - 1);
      const body = parts.slice(f.length - 1).join(',');
      const start = parseTime(head[f.indexOf('start')] || ''), end = parseTime(head[f.indexOf('end')] || '');
      const t = body.replace(/\{[^}]*\}/g, '').replace(/\\N/gi, '\n').replace(/\\h/g, ' ').trim();
      if (start != null && end != null && t) cues.push({ start, end, text: t });
    }
  }
  return cues.sort((a, b) => a.start - b.start);
}

const pad = (n, w = 2) => String(n).padStart(w, '0');
function fmtTime(ms) {
  const h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60;
  return `${pad(h)}:${pad(m)}:${pad(s)},${pad(ms % 1000, 3)}`;
}
function toSrt(cues) {
  return cues.map((c, i) => `${i + 1}\n${fmtTime(c.start)} --> ${fmtTime(c.end)}\n${c.text}\n`).join('\n');
}

// ---------------------------------------------------------------- dịch Anh → Việt
const strip = t => t.replace(/<[^>]+>/g, '').replace(/\{[^}]*\}/g, '').replace(/\s*\n\s*/g, ' ').replace(/\s+/g, ' ').trim();

async function translateCues(cues, env) {
  const src = cues.map(c => strip(c.text));
  const uniq = [...new Set(src.filter(Boolean))];
  const map = new Map();

  const chunks = [];
  let cur = [], len = 0;
  for (const t of uniq) {
    if (len + t.length > CHUNK && cur.length) { chunks.push(cur); cur = []; len = 0; }
    cur.push(t); len += t.length + 1;
  }
  if (cur.length) chunks.push(cur);

  const queue = chunks.slice();
  await Promise.all([0, 1, 2, 3].map(async () => {
    while (queue.length) {
      const ch = queue.shift();
      const out = await translateChunk(ch, env, 0);
      ch.forEach((t, i) => { if (out[i]) map.set(t, out[i]); });
    }
  }));

  const out = cues.map((c, i) => {
    const vi = map.get(src[i]);
    return { ...c, text: vi ? wrap(vi) : c.text };
  });
  return { cues: out, ratio: uniq.length ? map.size / uniq.length : 1 };
}

async function translateChunk(lines, env, depth) {
  for (const eng of [gtx, gtxGet, dictChrome]) {
    try {
      const out = await eng(lines);
      if (out.length === lines.length && out.some(Boolean)) return out;
    } catch (e) { /* thử cách khác */ }
  }
  if (lines.length > 1 && depth < 2) {
    const mid = Math.ceil(lines.length / 2);
    const [a, b] = await Promise.all([
      translateChunk(lines.slice(0, mid), env, depth + 1),
      translateChunk(lines.slice(mid), env, depth + 1)
    ]);
    if (a.some(Boolean) || b.some(Boolean)) return a.concat(b);
  }
  if (env.AI) {
    try {
      const r = await env.AI.run('@cf/meta/m2m100-1.2b', { requests: lines.map(t => ({ text: t, source_lang: 'en', target_lang: 'vi' })) });
      const arr = Array.isArray(r) ? r : (r && r.result) || [];
      if (arr.length === lines.length) return arr.map(x => x && x.translated_text);
    } catch (e) { /* thử từng câu */ }
    try {
      return await Promise.all(lines.map(async t => {
        const r = await env.AI.run('@cf/meta/m2m100-1.2b', { text: t, source_lang: 'en', target_lang: 'vi' });
        return r && r.translated_text;
      }));
    } catch (e) { /* bỏ qua */ }
  }
  return lines.map(() => null);
}

const UA = { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36' };

async function gtx(lines) {
  const res = await fetch('https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=vi&dt=t', {
    method: 'POST', redirect: 'manual',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8', ...UA },
    body: 'q=' + encodeURIComponent(lines.join('\n'))
  });
  if (res.status !== 200) throw new Error('gtx ' + res.status);
  const j = await res.json();
  return (j[0] || []).map(x => (x && x[0]) || '').join('').split('\n').map(s => s.trim());
}

async function gtxGet(lines) {
  const q = encodeURIComponent(lines.join('\n'));
  if (q.length > 7000) throw new Error('too long');
  const res = await fetch('https://translate.google.com/translate_a/single?client=gtx&sl=en&tl=vi&dt=t&q=' + q, { redirect: 'manual', headers: UA });
  if (res.status !== 200) throw new Error('gtx2 ' + res.status);
  const j = await res.json();
  return (j[0] || []).map(x => (x && x[0]) || '').join('').split('\n').map(s => s.trim());
}

async function dictChrome(lines) {
  const q = lines.map(t => 'q=' + encodeURIComponent(t)).join('&');
  const res = await fetch('https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=en&tl=vi', {
    method: 'POST', redirect: 'manual',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8', ...UA }, body: q
  });
  if (res.status !== 200) throw new Error('dict ' + res.status);
  const j = await res.json();
  return (Array.isArray(j) ? j : []).map(x => Array.isArray(x) ? x[0] : x);
}

async function selfTest(env) {
  const out = { version: VERSION, subdl_key: !!env.SUBDL_KEY, workers_ai: !!env.AI };
  for (const [name, f] of [['google_1', gtx], ['google_2', gtxGet], ['google_3', dictChrome]]) {
    try { out[name] = (await f(['Hello, how are you?', 'Where are you going tonight?'])).join(' | '); }
    catch (e) { out[name] = 'LỖI: ' + e.message; }
  }
  if (env.AI) {
    try { const r = await env.AI.run('@cf/meta/m2m100-1.2b', { text: 'Hello, how are you?', source_lang: 'en', target_lang: 'vi' }); out.workers_ai_test = r && r.translated_text; }
    catch (e) { out.workers_ai_test = 'LỖI: ' + e.message; }
  }
  return out;
}

// Chia câu dài thành 2 dòng cho dễ đọc trên điện thoại
function wrap(t) {
  if (t.length <= 44) return t;
  const mid = Math.floor(t.length / 2);
  let best = -1;
  for (let d = 0; d < mid; d++) {
    if (t[mid + d] === ' ') { best = mid + d; break; }
    if (t[mid - d] === ' ') { best = mid - d; break; }
  }
  return best > 0 ? t.slice(0, best) + '\n' + t.slice(best + 1) : t;
}

// ---------------------------------------------------------------- base64url
function b64e(s) {
  const b = new TextEncoder().encode(s);
  let bin = ''; for (const c of b) bin += String.fromCharCode(c);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64d(s) {
  const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4));
  return new TextDecoder().decode(Uint8Array.from(bin, c => c.charCodeAt(0)));
}
