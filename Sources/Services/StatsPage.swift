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
  --muted: #71717a; --faint: #7c7c85; --track: #f4f4f5;
  --work: #0a6166; --work-fg: #ffffff; --work-soft: rgba(10,97,102,.09);
  --brk: #bf5721; --brk-soft: rgba(191,87,33,.09);
  --stop: #b82640; --stop-fg: #ffffff;
  --shadow: 0 1px 2px rgba(0,0,0,.05);
  --hero-bg: #e7edf2; --hero-border: rgba(0,0,0,.08); --hero-ink: #10262e;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #09090b; --card: #101013; --border: #27272a; --fg: #fafafa;
    --muted: #a1a1aa; --faint: #8f8f98; --track: #27272a;
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
#hero .hc { position: relative; padding-right: 8px; }
#hlabel { font-size: 13px; font-weight: 500; color: color-mix(in srgb, var(--hero-ink) 72%, transparent); }
#big { font-size: 54px; font-weight: 800; letter-spacing: -.03em; line-height: 1.08; margin: 2px 0 4px; }
#big small { font-size: 26px; font-weight: 700; letter-spacing: 0; }
#line2 { font-size: 14px; font-weight: 600; color: color-mix(in srgb, var(--hero-ink) 92%, transparent); }
#line3 { font-size: 12.5px; color: color-mix(in srgb, var(--hero-ink) 66%, transparent); margin-top: 1px; }

/* Bob (ported from BobMascot.swift), in his swim ring — straddling the
   hero's top edge: ring on the waterline, head out of the water. The
   wrapper's headroom keeps him unclipped; JS gives him a float and tilt. */
#herowrap { position: relative; padding-top: 32px; }
#buoy { position: absolute; left: 20px; top: 0; width: 64px; height: 64px;
  pointer-events: none; z-index: 2; }
#buoy.dry .ring { display: none; }
/* Awake on dry land he hangs behind the card: the clip cuts him at the
   hero's top edge, so only his head and gripping paws peek over. */
#buoy.dry { top: 0; clip-path: inset(0 0 calc(100% - 32px) 0); }
#buoy .paws { display: none; }
#buoy .shades { display: none; }
.st-break #buoy .shades { display: block; }
/* Break-time drink: floats beside the ring, or stands on the lip while he
   peeks over (it lives outside the buoy so the dry clip can't cut it). */
#drink { position: absolute; width: 26px; height: 34px; display: none;
  pointer-events: none; z-index: 3; }
.st-break #drink { display: block; }
#buoy.dry .paws { display: block; }

/* Asleep on dry land: the profile sleeper replaces the buoy — perfectly
   still except the chest slowly rising. */
#sleeper { position: absolute; right: 14px; bottom: 8px; width: 64px; height: 40px;
  display: none; pointer-events: none; z-index: 2; }
#sleeper .chest { transform-box: fill-box; transform-origin: 50% 100%;
  animation: breathe 3.6s ease-in-out infinite; }
@keyframes breathe { 0%, 100% { transform: scaleY(1) } 50% { transform: scaleY(1.05) } }
#sleeper .zs text { font-size: 7px; font-weight: 700;
  fill: color-mix(in srgb, var(--hero-ink) 55%, transparent);
  animation: floatz 3.2s ease-in-out infinite; }
#sleeper .zs text:nth-child(2) { animation-delay: .55s; }
#sleeper .zs text:nth-child(3) { animation-delay: 1.1s; }
#zzz text { fill: color-mix(in srgb, var(--hero-ink) 55%, transparent) !important; }
#buoy .eyeb { transform-box: fill-box; transform-origin: center; animation: blink 4.6s infinite; }
@keyframes blink { 0%, 95%, 100% { transform: scaleY(1) } 96.5%, 98.5% { transform: scaleY(.1) } }
.st-out #buoy .eyeb { transform: scaleY(.1); animation: none; }
.st-out #buoy .glint { display: none; }
#zzz { opacity: 0; transition: opacity .35s; }
.st-out #zzz { opacity: 1; }
#zzz text { font-size: 7px; font-weight: 700; }
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
.abtn .lbl { position: relative; display: flex; flex-direction: column;
  align-items: center; gap: 1px; }
.abtn .sub { font-size: 10px; font-weight: 500; opacity: .78; }
.abtn .sub:empty { display: none; }
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

<div id="herowrap">
<section id="hero">
  <svg id="water" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
    <defs>
      <linearGradient id="wgrad" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" id="ws0"/><stop offset=".68" id="ws1"/><stop offset="1" id="ws2"/>
      </linearGradient>
      <linearGradient id="ringG" x1="0" y1="0" x2="0" y2="1">
        <stop id="rg0" offset="0"/><stop id="rg1" offset="1"/>
      </linearGradient>
      <linearGradient id="ringW" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#d4d6d9"/>
      </linearGradient>
      <linearGradient id="egrad" x1="0" y1="0" x2="100" y2="0" gradientUnits="userSpaceOnUse">
        <stop id="es0" stop-opacity="0"/><stop id="es1" stop-opacity=".14"/>
        <stop id="es2" stop-opacity=".5"/>
      </linearGradient>
    </defs>
    <path id="wpath" fill="url(#wgrad)"/>
    <path id="epath" fill="url(#egrad)"/>
    <path id="rim" fill="none" stroke-width="1.5" stroke-linejoin="round"
          stroke-linecap="round" opacity=".9" vector-effect="non-scaling-stroke"/>
  </svg>

  <div class="hc">
    <p id="hlabel">Hello</p>
    <p id="big" class="mono">–</p>
    <p id="line2" class="mono"></p>
    <p id="line3" class="mono"></p>
  </div>
</section>
  <svg id="buoy" viewBox="0 0 60 60" aria-hidden="true">
      <defs>
        <linearGradient id="furG" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#A37047"/><stop offset="1" stop-color="#8C5C38"/>
        </linearGradient>
        <linearGradient id="capG" x1="0" y1="0" x2="0" y2="1">
          <stop id="cg0" offset="0" stop-color="#1A8C94"/>
          <stop id="cg1" offset="1" stop-color="#17828A"/>
        </linearGradient>
      </defs>
      <g id="zzz"><text x="40" y="16">z</text><text x="47" y="10">z</text><text x="54" y="5">z</text></g>
      <g transform="translate(5,3) scale(0.5)">
        <!-- Whole Bob behind: his body sits inside the ring. -->
        <ellipse cx="24" cy="69" rx="6.5" ry="9" fill="#8C5C38"/>
        <ellipse cx="76" cy="69" rx="6.5" ry="9" fill="#8C5C38"/>
        <rect x="26" y="51" width="48" height="44" rx="16" fill="url(#furG)"/>
        <ellipse cx="50" cy="77" rx="14" ry="15" fill="#EBD1AD" opacity=".8"/>
        <ellipse class="feet" cx="40" cy="93" rx="8" ry="5" fill="#6B4529"/>
        <ellipse class="feet" cx="60" cy="93" rx="8" ry="5" fill="#6B4529"/>
        <!-- Chunky ring over the body, around his waist — feet stick out
             below its bottom arc. Hidden while he sits dry on the edge. -->
        <ellipse class="ring" cx="50" cy="58" rx="38" ry="20" fill="none"
                 stroke="url(#ringG)" stroke-width="26"/>
        <ellipse class="ring" cx="50" cy="58" rx="38" ry="20" fill="none" opacity=".92"
                 stroke="url(#ringW)" stroke-width="26" stroke-dasharray="23.3 23.3"/>
        <ellipse class="ring" cx="50" cy="55" rx="38" ry="20" fill="none"
                 stroke="rgba(255,255,255,.35)" stroke-width="3"/>
        <!-- Head and face again, in front of the ring's top arc. -->
        <circle cx="21" cy="23" r="9" fill="#8C5C38"/><circle cx="21" cy="23" r="4.3" fill="#6B4529"/>
        <circle cx="79" cy="23" r="9" fill="#8C5C38"/><circle cx="79" cy="23" r="4.3" fill="#6B4529"/>
        <ellipse cx="50" cy="37" rx="29" ry="27" fill="url(#furG)"
                 stroke="#4D301C" stroke-opacity=".25" stroke-width="1.2"/>
        <rect class="capd" x="14" y="24" width="72" height="12" rx="5" fill="#0F5C63"/>
        <path d="M20 31.5 A30 30 0 0 1 80 31.5 A4 4 0 0 1 76 35.5 H24 A4 4 0 0 1 20 31.5 Z"
              fill="url(#capG)"/>
        <circle class="capd" cx="50" cy="2.6" r="2.2" fill="#0F5C63"/>
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
        <g class="shades">
          <rect x="31" y="29" width="16" height="12" rx="4" fill="#16181C"/>
          <rect x="53" y="29" width="16" height="12" rx="4" fill="#16181C"/>
          <rect x="46" y="32" width="8" height="2.6" rx="1.3" fill="#16181C"/>
          <path d="M34 32 l4 -2" stroke="rgba(255,255,255,.35)" stroke-width="1.6" stroke-linecap="round"/>
          <path d="M56 32 l4 -2" stroke="rgba(255,255,255,.35)" stroke-width="1.6" stroke-linecap="round"/>
        </g>
        <g class="paws">
          <ellipse cx="30" cy="52" rx="9" ry="7" fill="#A37047"
                   stroke="#6B4529" stroke-opacity=".55" stroke-width="2"/>
          <ellipse cx="70" cy="52" rx="9" ry="7" fill="#A37047"
                   stroke="#6B4529" stroke-opacity=".55" stroke-width="2"/>
        </g>
      </g>
  </svg>
  <svg id="drink" viewBox="0 0 26 34" aria-hidden="true">
    <defs><linearGradient id="drinkG" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFB859"/><stop offset="1" stop-color="#FA853D"/>
    </linearGradient></defs>
    <line x1="14" y1="12" x2="19" y2="1" stroke="#F07048" stroke-width="2.4"
          stroke-linecap="round"/>
    <rect x="5" y="10" width="13" height="20" rx="2.6" fill="url(#drinkG)"
          stroke="rgba(255,255,255,.55)" stroke-width="1.2"/>
  </svg>
  <svg id="sleeper" viewBox="0 0 64 40" aria-hidden="true">
    <g class="zs"><text x="46" y="10">z</text><text x="52" y="6">z</text><text x="58" y="3">z</text></g>
    <ellipse cx="8" cy="33" rx="8" ry="4" fill="#6B4529" transform="rotate(-10 8 33)"/>
    <g class="chest">
      <ellipse cx="26" cy="29" rx="17" ry="10" fill="url(#furG)"/>
      <ellipse cx="24" cy="32" rx="9" ry="5" fill="#EBD1AD" opacity=".8"/>
    </g>
    <ellipse cx="15" cy="36.5" rx="4.5" ry="2.5" fill="#6B4529"/>
    <circle cx="45" cy="27" r="11" fill="url(#furG)"/>
    <circle cx="42" cy="17" r="3.2" fill="#8C5C38"/><circle cx="42" cy="17" r="1.6" fill="#6B4529"/>
    <g transform="rotate(-22 41 15)">
      <rect x="33" y="10" width="16" height="9" rx="4" fill="url(#capG)"/>
      <rect class="capd" x="45" y="15.5" width="9" height="3" rx="1.5" fill="#0F5C63"/>
    </g>
    <path d="M47.5 25 q2.2 1.8 4.4 0" stroke="#291A12" stroke-width="1.4"
          fill="none" stroke-linecap="round"/>
    <ellipse cx="46" cy="30" rx="2.4" ry="1.5" fill="#ED8C7A" opacity=".45"/>
    <ellipse cx="54" cy="29" rx="5.5" ry="4.5" fill="#EBD1AD"/>
    <rect x="56" y="24.5" width="3.4" height="2.6" rx="1" fill="#472E21"/>
    <rect x="53" y="31.5" width="2.4" height="3.8" rx="0.8" fill="#FCFAED"/>
  </svg>
</div>

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
// swell while the day is unfinished. It wears the Mac's accent hue (sent in
// the snapshot) with fixed saturation/lightness — deep tones in dark mode,
// pastels in light.
const darkMq = matchMedia("(prefers-color-scheme: dark)");
function palette() {
  const h = (snap && snap.accentHue) || 190;
  return darkMq.matches
    ? { water: [`hsl(${h} 61% 17%)`, `hsl(${h} 66% 26%)`, `hsl(${h} 64% 36%)`],
        glow: `hsl(${h} 59% 66%)` }
    : { water: [`hsl(${h} 36% 55%)`, `hsl(${h} 40% 61%)`, `hsl(${h} 47% 68%)`],
        glow: `hsl(${h} 76% 92%)` };
}
// Fresh wave character on every load, so no two sloshes look alike.
const SEED = { p0: Math.random() * Math.PI * 2, freq: 1.9 + Math.random() * 0.7,
               ap: Math.random() * Math.PI * 2,
               o2: Math.random() * Math.PI * 2, o3: Math.random() * Math.PI * 2 };
const levelFrac = () => snap && snap.target > 0 ? Math.min(1, workedNow() / snap.target) : 0;
let waveStarted = false, waveDone = reduceMotion, heroT0 = 0, lastFrame = 0;
// Displayed level chases the live one, so entry edits glide instead of snap.
let shown = 0;

function paintWater(level, amp, phase, asym) {
  asym = asym || 0;
  const f = levelFrac();
  const pal = palette();
  for (let i = 0; i < 3; i++)
    $("ws" + i).setAttribute("stop-color", pal.water[i]);
  // Bob's cap and the UI's primary token follow the accent hue too.
  const ch = (snap && snap.accentHue) || 190;
  const root = document.documentElement.style;
  root.setProperty("--work", darkMq.matches ? `hsl(${ch} 62% 57%)` : `hsl(${ch} 74% 22%)`);
  root.setProperty("--work-soft", darkMq.matches
    ? `hsl(${ch} 62% 57% / .10)` : `hsl(${ch} 74% 22% / .09)`);
  $("cg0").setAttribute("stop-color", `hsl(${ch} 70% 34%)`);
  $("cg1").setAttribute("stop-color", `hsl(${ch} 71% 32%)`);
  document.querySelectorAll(".capd").forEach(el =>
    el.setAttribute("fill", `hsl(${ch} 74% 22%)`));
  $("rg0").setAttribute("stop-color", `hsl(${ch} 55% 62%)`);
  $("rg1").setAttribute("stop-color", `hsl(${ch} 72% 36%)`);
  const l = level * 100;
  // Three sine components with incommensurate wavelengths and speeds sum
  // into an organic, never-quite-repeating edge; `asym` adds the lopsided
  // slosh harmonic during the arrival.
  const wave = u => {
    const th = u * Math.PI * SEED.freq + phase;
    let v = Math.sin(th)
      + 0.55 * Math.sin(u * Math.PI * SEED.freq * 1.83 + phase * 1.31 + SEED.o2)
      + 0.30 * Math.sin(u * Math.PI * SEED.freq * 3.10 + phase * 0.57 + SEED.o3);
    v *= 0.54;
    v += asym * Math.sin(2 * th + SEED.ap);
    return amp * v;
  };
  let d = "M0 0 Z", edge = "";
  if (l > 0.1) {
    let pts = (l + wave(0)).toFixed(2) + " 0";
    for (let y = 2.5; y <= 100; y += 2.5)
      pts += " L" + (l + wave(y / 100)).toFixed(2) + " " + y;
    d = "M0 0 L" + pts + " L0 100 Z";
    edge = "M" + pts;
  }
  $("wpath").setAttribute("d", d);
  // Edge light: a tight, sharp gradient hugging the waterline plus a crisp
  // rim stroked exactly along the edge — specular, not a soft blur.
  $("epath").setAttribute("d", d);
  $("rim").setAttribute("d", edge);
  const glow = pal.glow;
  $("rim").setAttribute("stroke", glow);
  const offs = [l - 5, l - 1.4, l];
  ["es0", "es1", "es2"].forEach((id, i) => {
    $(id).setAttribute("offset", (Math.max(0, offs[i]) / 100).toFixed(3));
    $(id).setAttribute("stop-color", glow);
  });
  // Bob floats top-left, bobbing with the swell — until then he sits dry
  // on the card's edge without the ring (not enough water to swim).
  const dry = f < 0.15;
  const asleepDry = dry && document.body.classList.contains("st-out");
  $("buoy").classList.toggle("dry", dry);
  $("buoy").style.display = asleepDry ? "none" : "block";
  $("sleeper").style.display = asleepDry ? "block" : "none";
  // Dry: standing on the deck (feet on the hero's top edge); swimming:
  // back to the fixed top-left straddle.
  $("buoy").style.left = "";
  $("buoy").style.transform = dry
    ? "none"
    : "translateY(" + (Math.sin(phase * 1.2) * 2.5 + 6).toFixed(1) + "px) rotate("
      + (Math.sin(phase * 0.9) * 5).toFixed(1) + "deg)";
  // Break drink: on the lip beside peeking Bob, or bobbing beside the ring.
  const dk = $("drink");
  if (dry) {
    dk.style.left = "88px"; dk.style.top = "-2px"; dk.style.transform = "none";
  } else {
    dk.style.left = "84px"; dk.style.top = "28px";
    dk.style.transform = "translateY(" + (Math.sin(phase * 1.2) * 2.5 + 6).toFixed(1)
      + "px) rotate(-8deg)";
  }
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
  const target = levelFrac() * eased;
  shown += (target - shown) * 0.12;
  if (Math.abs(target - shown) < 0.0006) shown = target;
  paintWater(shown, amp, phase, 0.55 * Math.exp(-t / 2.5));
  if (sustain > 0 || amp > 0.04 || shown !== target) requestAnimationFrame(waveFrame);
  else waveDone = true;
}
// Repaint the settled water when the phone flips light/dark.
darkMq.addEventListener("change", () => { if (snap && waveDone) paintWater(levelFrac(), 0, 0); });

const hm = s => { s = Math.max(0, Math.floor(s));
  return Math.floor(s / 3600) + "h " + String(Math.floor(s / 60) % 60).padStart(2, "0") + "m"; };
// The Mac app's short duration style: "42m", "6h", "6h 12m".
const hmShort = s => { const m = Math.max(0, Math.floor(s / 60));
  const h = Math.floor(m / 60), r = m % 60;
  return h > 0 ? (r > 0 ? h + "h " + r + "m" : h + "h") : m + "m"; };
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
    // Worked time is the headline; the percentage sits under it.
    $("big").textContent = hm(w);
    $("line2").textContent = Math.round(f * 100) + "% of " + hm(snap.target);
    const over = w - snap.target;
    $("line3").textContent = over >= 0 ? "+" + hm(over) + " over" : hm(-over) + " left";
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
    if ((levelFrac() < 1 || Math.abs(levelFrac() - shown) > 0.002) && !reduceMotion) {
      // Under 100% again or the level moved (entry edit) — resume the wave
      // loop, which glides `shown` toward the live level.
      waveDone = false;
      requestAnimationFrame(waveFrame);
    } else {
      shown = levelFrac();
      paintWater(shown, 0, 0);
    }
  }
  for (const b of document.querySelectorAll("#abox .abtn")) {
    const sub = b.querySelector(".sub");
    if (sub) sub.textContent = buttonInfo(b.dataset.name);
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
  working: [["clockOut", "Clock out", "solid-work"], ["startBreak", "Start break", "solid-work"]],
  break:   [["endBreak", "End break", "solid-work"], ["clockOut", "Clock out", "solid-work"]],
};

function renderActions() {
  const card = $("actionscard"), box = $("abox");
  card.hidden = !snap.actions;
  if (!snap.actions) return;
  box.innerHTML = "";
  for (const [name, label, cls] of ACTIONS[snap.projected] ?? []) {
    const b = document.createElement("button");
    b.className = "abtn " + cls;
    b.dataset.name = name;
    b.innerHTML = "<span class='fill'></span><span class='lbl'><span class='main'></span><span class='sub'></span></span>";
    b.querySelector(".main").textContent = label;
    b.querySelector(".sub").textContent = buttonInfo(name);
    hold(b, name);
    box.appendChild(b);
  }
}

// The Mac Today view's trailing info, mirrored: auto-tag reason on Clock in,
// auto-break countdown on Start break, back-in countdown (plus tag) on End
// break. Refreshed every tick so the countdowns stay live.
function buttonInfo(name) {
  if (!snap) return "";
  const now = Date.now() / 1000;
  const tag = snap.autoReason || "";
  if (name === "clockIn") return tag;
  if (name === "startBreak" && snap.autoBreakDueAt) {
    const left = snap.autoBreakDueAt - now;
    return left <= 0 ? "auto now" : "auto in " + hmShort(left);
  }
  if (name === "endBreak") {
    let out = "";
    if (snap.breakEndsAt) {
      const left = snap.breakEndsAt - now;
      out = left <= 0 ? "back now" : "back in " + hmShort(left);
    }
    return out && tag ? out + " \u00b7 " + tag : (out || tag);
  }
  return "";
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
