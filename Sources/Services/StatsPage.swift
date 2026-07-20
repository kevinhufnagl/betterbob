// The phone stats page, embedded as a single self-contained string — no
// external assets, so the server needs exactly one route for it. shadcn-style
// design (zinc tokens, bordered cards, badges), the real Bob ported to SVG
// from BobMascot.swift, light/dark from the phone's system setting, and
// hold-to-confirm action buttons. Plain copy, no emojis, per house style.
enum StatsPage {
    static let html = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>BetterBob</title>
<style>
:root {
  --bg: #fafafa; --card: #ffffff; --border: #e4e4e7; --fg: #18181b;
  --muted: #71717a; --faint: #a1a1aa; --track: #f4f4f5;
  --work: #0a6166; --work-fg: #ffffff; --work-soft: rgba(10,97,102,.09);
  --brk: #bf5721; --brk-soft: rgba(191,87,33,.09);
  --stop: #b82640; --stop-fg: #ffffff;
  --shadow: 0 1px 2px rgba(0,0,0,.05);
  --hero-bg: #e7edf2; --hero-border: rgba(0,0,0,.08); --hero-ink: #10262e;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #09090b; --card: #101013; --border: #27272a; --fg: #fafafa;
    --muted: #a1a1aa; --faint: #63636b; --track: #27272a;
    --work: #4dd1d9; --work-fg: #032527; --work-soft: rgba(77,209,217,.10);
    --brk: #ffa16e; --brk-soft: rgba(255,161,110,.12);
    --stop: #ff7080; --stop-fg: #33060b;
    --shadow: none;
    --hero-bg: #0b0f17; --hero-border: rgba(255,255,255,.09); --hero-ink: #ffffff;
  }
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html { background: var(--bg); color: var(--fg);
  font: 15px/1.45 -apple-system, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
  -webkit-font-smoothing: antialiased; -webkit-text-size-adjust: 100%; }
main { max-width: 430px; margin: 0 auto; display: grid; gap: 12px;
  padding: max(18px, env(safe-area-inset-top)) 18px 30px; }
.mono { font-variant-numeric: tabular-nums; }

header { display: flex; align-items: center; justify-content: space-between; padding: 2px 2px 0; }
#brand { font-size: 13px; font-weight: 600; color: var(--muted); letter-spacing: .01em; }
#badge { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 500;
  padding: 4px 10px; border-radius: 999px; border: 1px solid var(--border);
  background: var(--card); color: var(--muted); box-shadow: var(--shadow); }
#dot { width: 7px; height: 7px; border-radius: 50%; background: var(--faint); }
.st-working #dot { background: var(--work); }
.st-break #dot { background: var(--brk); }
.st-working #badge, .st-break #badge { color: var(--fg); }

.card { background: var(--card); border: 1px solid var(--border);
  border-radius: 14px; padding: 16px; box-shadow: var(--shadow); }
.card h2 { font-size: 11px; font-weight: 600; letter-spacing: .06em;
  text-transform: uppercase; color: var(--muted); margin-bottom: 10px; }
main > * { animation: rise .4s ease both; }
main > *:nth-child(2) { animation-delay: .04s } main > *:nth-child(3) { animation-delay: .08s }
main > *:nth-child(4) { animation-delay: .12s } main > *:nth-child(5) { animation-delay: .16s }
main > *:nth-child(6) { animation-delay: .20s } main > *:nth-child(7) { animation-delay: .24s }
@keyframes rise { from { opacity: 0; transform: translateY(6px) } }

/* Hero — liquid progress: the water sweeps in from the left, its leading
   edge sloshes as a wave that keeps a small swell until the day is done,
   and its color drifts from cold blue to the brand teal as the day fills.
   The edge light is a second fill of the same wave shape, so it hugs the
   sloshing edge exactly instead of reading as a blurred oval. */
#hero { position: relative; overflow: hidden; border-radius: 16px; color: var(--hero-ink);
  background: var(--hero-bg); border: 1px solid var(--hero-border);
  padding: 18px; min-height: 196px;
  display: flex; flex-direction: column; justify-content: flex-end; }
#water { position: absolute; inset: 0; width: 100%; height: 100%; }
#hero .hc { position: relative; padding-right: 96px; }
#hlabel { font-size: 13px; font-weight: 500; color: color-mix(in srgb, var(--hero-ink) 72%, transparent); }
#big { font-size: 54px; font-weight: 800; letter-spacing: -.03em; line-height: 1.08; margin: 2px 0 4px; }
#big small { font-size: 26px; font-weight: 700; letter-spacing: 0; }
#line2 { font-size: 14px; font-weight: 600; color: color-mix(in srgb, var(--hero-ink) 92%, transparent); }
#line3 { font-size: 12.5px; color: color-mix(in srgb, var(--hero-ink) 66%, transparent); margin-top: 1px; }

/* Bob (ported from BobMascot.swift) */
#bob { position: absolute; right: 12px; bottom: 10px; width: 88px; height: 88px; }
#zzz text { fill: color-mix(in srgb, var(--hero-ink) 55%, transparent) !important; }
.st-working #bob { animation: bobble 2.8s ease-in-out infinite; }
@keyframes bobble { 0%,100% { transform: translateY(0) } 50% { transform: translateY(-4px) } }
#bob .eyeb { transform-box: fill-box; transform-origin: center; animation: blink 4.6s infinite; }
@keyframes blink { 0%, 95%, 100% { transform: scaleY(1) } 96.5%, 98.5% { transform: scaleY(.1) } }
.st-out #bob .eyeb { transform: scaleY(.1); animation: none; }
.st-out #bob .glint { display: none; }
#mug, #zzz { opacity: 0; transition: opacity .35s; }
.st-break #mug { opacity: 1; }
.st-out #zzz { opacity: 1; }
#zzz text { fill: var(--faint); font-size: 11px; font-weight: 700; }
.st-out #zzz text { animation: floatz 3.2s ease-in-out infinite; }
.st-out #zzz text:nth-child(2) { animation-delay: .55s; }
.st-out #zzz text:nth-child(3) { animation-delay: 1.1s; }
@keyframes floatz { 0% { opacity: 0; transform: translateY(3px) } 35% { opacity: 1 }
  100% { opacity: 0; transform: translateY(-6px) } }

/* Stats */
.grid3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; }
.stat { background: var(--card); border: 1px solid var(--border); border-radius: 14px;
  padding: 12px 14px; box-shadow: var(--shadow); }
.stat .k { font-size: 10px; font-weight: 600; letter-spacing: .06em;
  text-transform: uppercase; color: var(--muted); }
.stat .v { font-size: 17px; font-weight: 700; margin-top: 3px; letter-spacing: -.01em; }

/* Actions */
#abox { display: flex; gap: 10px; }
.abtn { position: relative; overflow: hidden; flex: 1; height: 46px; border-radius: 10px;
  border: 1px solid transparent; font: 600 14px/1 inherit; font-family: inherit;
  touch-action: none; -webkit-user-select: none; user-select: none; -webkit-touch-callout: none;
  -webkit-tap-highlight-color: transparent; transition: transform .12s ease, opacity .2s; }
.abtn:active { transform: scale(.98); }
.abtn[disabled] { opacity: .5; }
.abtn .fill { position: absolute; inset: 0; background: currentColor; opacity: .28;
  transform: scaleX(0); transform-origin: left; transition: transform .18s ease; }
.abtn.holding .fill { transform: scaleX(1); transition: transform 2s linear; }
.abtn .lbl { position: relative; }
.abtn.solid-work { background: var(--work); color: var(--work-fg); }
.abtn.solid-stop { background: var(--stop); color: var(--stop-fg); }
.abtn.line-brk { background: var(--brk-soft); color: var(--brk);
  border-color: color-mix(in srgb, var(--brk) 35%, transparent); }
.hint { font-size: 11.5px; color: var(--faint); margin-top: 9px; text-align: center; }
#breakline { font-size: 12.5px; font-weight: 500; color: var(--brk); text-align: center; margin-top: 9px; }
#breakline:empty, #breakline:empty + .hint { margin-top: 0; }

/* Timeline + entries. Segments stay square — only the strip's outer ends are
   rounded, via the container's clip. */
#strip { display: flex; gap: 2px; height: 12px; border-radius: 999px;
  overflow: hidden; background: var(--track); }
#strip div { min-width: 2px; }
#strip .w { background: var(--work); } #strip .b { background: var(--brk); }
#strip .gap { background: transparent; min-width: 0; }
#striplabels { display: flex; justify-content: space-between; font-size: 11px;
  color: var(--faint); margin-top: 7px; }
.row { display: flex; align-items: center; gap: 10px; padding: 10px 0;
  border-top: 1px solid var(--border); font-size: 13px; }
.row:first-of-type { border-top: none; padding-top: 2px; }
.row:last-of-type { padding-bottom: 2px; }
.pill { font-size: 11px; font-weight: 600; padding: 3px 9px; border-radius: 999px; }
.pill.w { background: var(--work-soft); color: var(--work); }
.pill.b { background: var(--brk-soft); color: var(--brk); }
.row .range { color: var(--muted); }
.row .dur { margin-left: auto; font-weight: 600; }
.empty { font-size: 13px; color: var(--muted); }

footer { text-align: center; font-size: 11.5px; color: var(--faint); padding-top: 4px; }
.offline #badge { color: var(--muted); }
.offline #dot { background: var(--stop); }

@media (prefers-reduced-motion: reduce) {
  * { animation: none !important; }
  .abtn.holding .fill { transition: transform 2s linear !important; }
}
</style>
</head>
<body class="st-out">
<main>
<header>
  <span id="brand">BetterBob</span>
  <span id="badge"><span id="dot"></span><span id="state">Connecting</span></span>
</header>

<section id="hero">
  <svg id="water" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
    <defs>
      <linearGradient id="wgrad" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" id="ws0"/><stop offset=".68" id="ws1"/><stop offset="1" id="ws2"/>
      </linearGradient>
      <linearGradient id="egrad" x1="0" y1="0" x2="100" y2="0" gradientUnits="userSpaceOnUse">
        <stop id="es0" stop-opacity="0"/><stop id="es1" stop-opacity=".11"/>
        <stop id="es2" stop-opacity=".27"/><stop id="es3" stop-opacity=".5"/>
      </linearGradient>
    </defs>
    <path id="wpath" fill="url(#wgrad)"/>
    <path id="epath" fill="url(#egrad)"/>
  </svg>
  <svg id="bob" viewBox="0 0 100 100" aria-hidden="true">
      <defs>
        <linearGradient id="furG" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#A37047"/><stop offset="1" stop-color="#8C5C38"/>
        </linearGradient>
        <linearGradient id="capG" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#1A8C94"/><stop offset="1" stop-color="#17828A"/>
        </linearGradient>
      </defs>
      <g id="zzz"><text x="84" y="26">z</text><text x="91" y="17">z</text><text x="97" y="9">z</text></g>
      <ellipse cx="24" cy="69" rx="6.5" ry="9" fill="#8C5C38"/>
      <ellipse cx="76" cy="69" rx="6.5" ry="9" fill="#8C5C38"/>
      <rect x="26" y="51" width="48" height="44" rx="16" fill="url(#furG)"/>
      <ellipse cx="50" cy="77" rx="14" ry="15" fill="#EBD1AD" opacity=".8"/>
      <ellipse cx="40" cy="93" rx="8" ry="5" fill="#6B4529"/>
      <ellipse cx="60" cy="93" rx="8" ry="5" fill="#6B4529"/>
      <circle cx="21" cy="23" r="9" fill="#8C5C38"/><circle cx="21" cy="23" r="4.3" fill="#6B4529"/>
      <circle cx="79" cy="23" r="9" fill="#8C5C38"/><circle cx="79" cy="23" r="4.3" fill="#6B4529"/>
      <ellipse cx="50" cy="37" rx="29" ry="27" fill="url(#furG)"
               stroke="#4D301C" stroke-opacity=".25" stroke-width="1.2"/>
      <rect x="14" y="24" width="72" height="12" rx="5" fill="#0F5C63"/>
      <path d="M20 31.5 A30 30 0 0 1 80 31.5 A4 4 0 0 1 76 35.5 H24 A4 4 0 0 1 20 31.5 Z"
            fill="url(#capG)"/>
      <circle cx="50" cy="2.6" r="2.2" fill="#0F5C63"/>
      <text x="50" y="21" text-anchor="middle" font-size="14" font-weight="800"
            fill="#fff" font-family="inherit">bob</text>
      <ellipse cx="32" cy="46" rx="6.5" ry="4.3" fill="#ED8C7A" opacity=".45"/>
      <ellipse cx="68" cy="46" rx="6.5" ry="4.3" fill="#ED8C7A" opacity=".45"/>
      <g transform="translate(39,35)"><g class="eyeb">
        <circle r="7.5" fill="#fff" stroke="#4D301C" stroke-opacity=".18" stroke-width=".6"/>
        <circle cy="3" r="3.75" fill="#291A12"/>
        <circle class="glint" cx="-1.8" cy="1.2" r="1.2" fill="#fff" opacity=".9"/>
      </g></g>
      <g transform="translate(61,35)"><g class="eyeb">
        <circle r="7.5" fill="#fff" stroke="#4D301C" stroke-opacity=".18" stroke-width=".6"/>
        <circle cy="3" r="3.75" fill="#291A12"/>
        <circle class="glint" cx="-1.8" cy="1.2" r="1.2" fill="#fff" opacity=".9"/>
      </g></g>
      <ellipse cx="50" cy="48" rx="20" ry="15" fill="#EBD1AD"/>
      <rect x="44" y="38.5" width="12" height="8" rx="3" fill="#472E21"/>
      <rect x="43.5" y="48" width="6.2" height="12" rx="1.4" fill="#FCFAED"
            stroke="#4D301C" stroke-opacity=".18" stroke-width=".5"/>
      <rect x="50.3" y="48" width="6.2" height="12" rx="1.4" fill="#FCFAED"
            stroke="#4D301C" stroke-opacity=".18" stroke-width=".5"/>
      <g id="mug" transform="translate(80,60) rotate(8)">
        <path d="M2 -8 q1.6 -4 0 -7 M7 -8 q1.6 -4 0 -7" stroke="#a1a1aa"
              stroke-width="1.8" fill="none" stroke-linecap="round"/>
        <rect x="-3" y="-6" width="15" height="15" rx="3" fill="#bf5721"/>
        <path d="M12 -3 q7 4 0 9" stroke="#bf5721" stroke-width="3" fill="none"/>
      </g>
  </svg>
  <div class="hc">
    <p id="hlabel">Hello</p>
    <p id="big" class="mono">–</p>
    <p id="line2" class="mono"></p>
    <p id="line3" class="mono"></p>
  </div>
</section>

<section class="grid3">
  <div class="stat"><p class="k">Worked</p><p class="v mono" id="sworked">–</p></div>
  <div class="stat"><p class="k">Break</p><p class="v mono" id="sbreak">–</p></div>
  <div class="stat"><p class="k" id="sleftk">Left</p><p class="v mono" id="sleft">–</p></div>
</section>

<section class="card" id="actionscard" hidden>
  <div id="abox"></div>
  <p id="breakline"></p>
  <p class="hint">Hold a button for two seconds to confirm.</p>
</section>

<section class="card">
  <h2>Timeline</h2>
  <div id="strip"></div>
  <div id="striplabels"><span id="lstart"></span><span id="lend"></span></div>
</section>

<section class="card">
  <h2>Entries</h2>
  <div id="entries"><p class="empty">No entries yet today.</p></div>
</section>

<footer>BetterBob · live from your Mac</footer>
</main>
<script>
"use strict";
const $ = id => document.getElementById(id);
const base = location.pathname.replace(/\/+$/, "");
let snap = null;
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Water: sweeps in from the left with a sine-wave edge that keeps a small
// swell while the day is unfinished; its color lerps from cold blue (empty)
// to the brand teal (full). Deep tones in dark mode, pastels in light.
const darkMq = matchMedia("(prefers-color-scheme: dark)");
const PAL = {
  dark: { blue: [[19, 52, 107], [25, 81, 158], [40, 115, 204]],
          teal: [[17, 62, 71], [23, 105, 112], [33, 145, 153]],
          gblue: [115, 184, 255], gteal: [117, 212, 219] },
  light: { blue: [[107, 148, 204], [125, 166, 217], [143, 184, 230]],
           teal: [[97, 173, 181], [115, 191, 196], [133, 207, 212]],
           gblue: [230, 242, 255], gteal: [219, 250, 250] },
};
// Fresh wave character on every load, so no two sloshes look alike.
const SEED = { p0: Math.random() * Math.PI * 2, freq: 1.9 + Math.random() * 0.7,
               ap: Math.random() * Math.PI * 2 };
const lerp = (a, b, f) => a + (b - a) * f;
const mixc = (a, b, f) =>
  "rgb(" + a.map((v, i) => Math.round(lerp(v, b[i], f))).join(",") + ")";
const levelFrac = () => snap && snap.target > 0 ? Math.min(1, workedNow() / snap.target) : 0;
let waveStarted = false, waveDone = reduceMotion, heroT0 = 0, lastFrame = 0;

function paintWater(level, amp, phase, asym) {
  asym = asym || 0;
  const f = levelFrac();
  const pal = darkMq.matches ? PAL.dark : PAL.light;
  for (let i = 0; i < 3; i++)
    $("ws" + i).setAttribute("stop-color", mixc(pal.blue[i], pal.teal[i], f));
  const l = level * 100;
  // `asym` blends in a second harmonic so the arrival slosh leans to one
  // side instead of being a clean symmetric sine.
  const wave = th => amp * (Math.sin(th) + asym * Math.sin(2 * th + SEED.ap));
  let d = "M0 0 Z";
  if (l > 0.1) {
    d = "M0 0 L" + (l + wave(phase)).toFixed(2) + " 0";
    for (let y = 5; y <= 100; y += 5)
      d += " L" + (l + wave(y / 100 * Math.PI * SEED.freq + phase)).toFixed(2) + " " + y;
    d += " L0 100 Z";
  }
  $("wpath").setAttribute("d", d);
  // Edge light: same shape, a tight eased ramp into the waterline (a wide
  // linear ramp reads as a hard band reaching too far into the water).
  $("epath").setAttribute("d", d);
  const glow = mixc(pal.gblue, pal.gteal, f);
  const offs = [l - 10, l - 5, l - 2, l];
  ["es0", "es1", "es2", "es3"].forEach((id, i) => {
    $(id).setAttribute("offset", (Math.max(0, offs[i]) / 100).toFixed(3));
    $(id).setAttribute("stop-color", glow);
  });
}

function waveFrame(nowMs) {
  if (nowMs - lastFrame < 30) { requestAnimationFrame(waveFrame); return; }
  lastFrame = nowMs;
  const t = (nowMs - heroT0) / 1000;
  const eased = 1 - Math.pow(1 - Math.min(1, t / 1.5), 3);
  // The arrival slosh is bigger, faster and lopsided (second harmonic);
  // all three fade slowly toward the small, slow, symmetric standing wave,
  // which only flattens out once the day is complete.
  const decay = Math.exp(-t / 3);
  const sustain = levelFrac() < 1 ? 1.1 : 0;
  const amp = sustain + (3.4 - sustain) * decay * (0.3 + 0.7 * eased);
  const phase = SEED.p0 + 1.5 * t + (3.3 - 1.5) * 3 * (1 - decay);
  paintWater(levelFrac() * eased, amp, phase, 0.55 * Math.exp(-t / 2.5));
  if (sustain > 0 || amp > 0.04) requestAnimationFrame(waveFrame);
  else waveDone = true;
}
// Repaint the settled water when the phone flips light/dark.
darkMq.addEventListener("change", () => { if (snap && waveDone) paintWater(levelFrac(), 0, 0); });

const hm = s => { s = Math.max(0, Math.floor(s));
  return Math.floor(s / 3600) + "h " + String(Math.floor(s / 60) % 60).padStart(2, "0") + "m"; };
const clock = t => new Date(t * 1000).toTimeString().slice(0, 5);
const workedNow = () => !snap ? 0 :
  snap.worked + (snap.state === "working" ? Math.max(0, Date.now() / 1000 - snap.asOf) : 0);

async function poll() {
  try {
    const r = await fetch(base + "/stats.json", { cache: "no-store" });
    if (!r.ok) throw 0;
    snap = await r.json();
    document.body.classList.remove("offline");
    render();
  } catch (e) {
    document.body.classList.add("offline");
    $("state").textContent = "Reconnecting";
  }
}

function render() {
  if (!snap) return;
  document.body.className = "st-" + snap.state;
  const h = new Date().getHours();
  const part = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
  $("hlabel").textContent = snap.name ? part + ", " + snap.name : part;
  $("state").textContent =
    snap.state === "working" ? "Working" : snap.state === "break" ? "On break" : "Clocked out";

  // Timeline strip + entries.
  const strip = $("strip"), list = $("entries");
  strip.innerHTML = ""; list.innerHTML = "";
  if (snap.entries.length) {
    const now = Date.now() / 1000;
    const start = Math.min(...snap.entries.map(e => e.start));
    // A clocked-out day ends at its last entry — only an open entry extends
    // the span (and the label) to now.
    const open = snap.entries.some(e => !e.end);
    const end = open ? Math.max(now, ...snap.entries.map(e => e.end ?? now))
                     : Math.max(...snap.entries.map(e => e.end));
    const span = Math.max(1, end - start);
    let cursor = start;
    for (const e of snap.entries.slice().sort((a, b) => a.start - b.start)) {
      const s = e.start, f = e.end ?? now;
      // Grow factors scaled up: fractional flex-grow sums below 1 leave
      // free space undistributed, so the strip would never reach the edge.
      if (s > cursor + 30) { const g = document.createElement("div");
        g.className = "gap"; g.style.flexGrow = (s - cursor) / span * 1000; strip.appendChild(g); }
      const seg = document.createElement("div");
      seg.className = e.kind === "break" ? "b" : "w";
      seg.style.flexGrow = Math.max(0, f - s) / span * 1000;
      if (!e.end) seg.style.opacity = ".75";
      strip.appendChild(seg);
      cursor = f;

      const row = document.createElement("div"); row.className = "row";
      row.innerHTML = "<span class='pill'></span><span class='range mono'></span><span class='dur mono'></span>";
      const pill = row.querySelector(".pill");
      pill.classList.add(e.kind === "break" ? "b" : "w");
      pill.textContent = e.kind === "break" ? "Break" : "Work";
      row.querySelector(".range").textContent =
        clock(e.start) + " – " + (e.end ? clock(e.end) : "now");
      row.querySelector(".dur").textContent = hm(f - s);
      list.appendChild(row);
    }
    $("lstart").textContent = clock(start);
    $("lend").textContent = (open ? "now " : "") + clock(end);
  } else {
    list.innerHTML = "<p class='empty'>No entries yet today.</p>";
    $("lstart").textContent = "Nothing tracked yet";
    $("lend").textContent = "";
  }
  renderActions();
  if (!waveStarted) {
    waveStarted = true;
    if (reduceMotion) { paintWater(levelFrac(), 0, 0); }
    else { heroT0 = performance.now(); requestAnimationFrame(waveFrame); }
  }
  tick();
}

function tick() {
  if (!snap) return;
  const w = workedNow();
  $("sworked").textContent = hm(w);
  $("sbreak").textContent = hm(snap.breakTotal);
  if (snap.target > 0) {
    const f = w / snap.target;
    $("big").innerHTML = Math.round(f * 100) + "<small>%</small>";
    $("line2").textContent = hm(w) + " worked";
    const over = w - snap.target;
    $("line3").textContent = over >= 0
      ? "+" + hm(over) + " over your " + hm(snap.target) + " target"
      : hm(-over) + " left of " + hm(snap.target);
    $("sleftk").textContent = over >= 0 ? "Over" : "Left";
    $("sleft").textContent = over >= 0 ? "+" + hm(over) : hm(-over);
  } else {
    $("big").textContent = hm(w);
    $("line2").textContent = "worked today";
    $("line3").textContent = "No target today";
    $("sleftk").textContent = "Left";
    $("sleft").textContent = "–";
  }
  if (waveDone) {
    if (levelFrac() < 1 && !reduceMotion) {
      // Dropped back under 100% (e.g. target changed) — resume the swell.
      waveDone = false;
      requestAnimationFrame(waveFrame);
    } else {
      paintWater(levelFrac(), 0, 0);
    }
  }
  const bl = $("breakline");
  if (snap.state === "break" && snap.breakEndsAt) {
    const left = snap.breakEndsAt - Date.now() / 1000;
    bl.textContent = left > 0
      ? "Bob clocks you back in at " + clock(snap.breakEndsAt) + " — " + hm(left).replace(/^0h /, "") + " to go"
      : "Clocking back in any moment";
  } else bl.textContent = "";
}

// Buttons mirror the popover: they offer the state after queued punches.
// Hold for 2 s to fire — the sweeping fill is the confirmation.
const ACTIONS = {
  out:     [["clockIn", "Clock in", "solid-work"]],
  working: [["clockOut", "Clock out", "solid-stop"], ["startBreak", "Start break", "line-brk"]],
  break:   [["endBreak", "End break", "solid-work"], ["clockOut", "Clock out", "solid-stop"]],
};

function renderActions() {
  const card = $("actionscard"), box = $("abox");
  card.hidden = !snap.actions;
  if (!snap.actions) return;
  box.innerHTML = "";
  for (const [name, label, cls] of ACTIONS[snap.projected] ?? []) {
    const b = document.createElement("button");
    b.className = "abtn " + cls;
    b.innerHTML = "<span class='fill'></span><span class='lbl'></span>";
    b.querySelector(".lbl").textContent = label;
    hold(b, name);
    box.appendChild(b);
  }
}

function hold(b, name) {
  let timer = 0;
  const stop = () => { clearTimeout(timer); b.classList.remove("holding"); };
  b.addEventListener("pointerdown", e => {
    e.preventDefault();
    if (b.disabled) return;
    b.classList.add("holding");
    timer = setTimeout(() => { stop(); act(name); }, 2000);
  });
  for (const ev of ["pointerup", "pointerleave", "pointercancel"])
    b.addEventListener(ev, stop);
  b.addEventListener("contextmenu", e => e.preventDefault());
}

async function act(name) {
  for (const b of $("abox").querySelectorAll("button")) b.disabled = true;
  try {
    const r = await fetch(base + "/action/" + name, { method: "POST", cache: "no-store" });
    if (!r.ok) throw 0;
    snap = await r.json();
  } catch (e) {}
  render();
}

poll();
setInterval(poll, 5000);
setInterval(tick, 1000);
</script>
</body>
</html>
"""#
}
