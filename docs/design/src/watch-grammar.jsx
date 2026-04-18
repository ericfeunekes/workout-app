// WorkoutDB Watch — Face Grammar
// =============================================================
// A face is a JSON spec. The watch is a dumb renderer.
// Backend pushes { header, hero, stats, progress, footer, swipe }
// Every widget declares { kind, ...data }. Renderer picks a component.
// =============================================================

// ─── WIDGET LIBRARY ──────────────────────────────────────────
// Each widget takes a plain JSON blob and returns JSX.

const Widgets = {

  // ── Text widgets ──
  kicker: ({ text, tone = "muted" }) => (
    <div className="w-kicker" data-tone={tone}>{text}</div>
  ),

  exname: ({ text }) => (
    <div className="w-exname">{text}</div>
  ),

  // ── Big primary value (hero) ──
  // {kind:"number", value:102.5, unit:"kg", size:"huge|big|mid"}
  number: ({ value, unit, size = "big", tone }) => (
    <div className={`w-hero w-hero-${size}`} data-tone={tone}>
      {value}{unit && <span className="w-unit">{unit}</span>}
    </div>
  ),

  // ── Running-specific hero: pace as "4:52" ──
  pace: ({ value, unit = "/km", size = "big", tone }) => (
    <div className={`w-hero w-hero-${size}`} data-tone={tone}>
      {value}<span className="w-unit">{unit}</span>
    </div>
  ),

  // ── Elapsed / countdown timer (live) ──
  // {kind:"timer", seconds:84, mode:"mmss|hhmmss", size:"big", countdown:false}
  timer: ({ seconds, mode = "mmss", size = "big", tone, countdown = false }) => {
    const s = Math.max(0, Math.floor(seconds));
    let text;
    if (mode === "hhmmss") {
      const hh = Math.floor(s/3600);
      const mm = Math.floor((s%3600)/60);
      const ss = s%60;
      text = hh > 0
        ? `${hh}:${String(mm).padStart(2,"0")}:${String(ss).padStart(2,"0")}`
        : `${mm}:${String(ss).padStart(2,"0")}`;
    } else {
      const mm = Math.floor(s/60);
      const ss = s%60;
      text = `${mm}:${String(ss).padStart(2,"0")}`;
    }
    return <div className={`w-hero w-hero-${size}`} data-tone={tone}>{text}</div>;
  },

  // ── Progress ring (rest countdown, run progress) ──
  // {kind:"ring", pct:0.4, tone:"accent"}
  ring: ({ pct, tone = "accent" }) => {
    const r = 108, c = 2 * Math.PI * r, dash = c * pct;
    return (
      <div className="w-ring-wrap">
        <svg viewBox="0 0 240 240">
          <circle cx="120" cy="120" r={r} fill="none" stroke="#242018" strokeWidth="4"/>
          <circle cx="120" cy="120" r={r} fill="none"
            stroke={tone === "warn" ? "var(--warn)" : "var(--accent)"}
            strokeWidth="4" strokeLinecap="round"
            strokeDasharray={`${dash} ${c}`}
            transform="rotate(-90 120 120)"/>
        </svg>
      </div>
    );
  },

  // ── Stat cell (small labeled metric) ──
  // {kind:"stat", label:"DIST", value:"3.2", unit:"km", tone:"ink"}
  stat: ({ label, value, unit, tone }) => (
    <div className="w-stat" data-tone={tone}>
      <div className="w-stat-label">{label}</div>
      <div className="w-stat-value">{value}{unit && <span className="w-stat-unit">{unit}</span>}</div>
    </div>
  ),

  // ── HR with pulse dot ──
  hr: ({ bpm, zone }) => {
    const toneMap = { 1: "ok", 2: "ok", 3: "accent", 4: "warn", 5: "danger" };
    const tone = zone ? toneMap[zone] : "hr";
    return (
      <span className="w-hr" data-tone={tone}>
        <i className="w-hr-dot"/>{bpm}{zone && <span className="w-hr-zone"> Z{zone}</span>}
      </span>
    );
  },

  // ── Tap hint ──
  taphint: ({ text, tone = "accent" }) => (
    <span className="w-taphint" data-tone={tone}>{text}</span>
  ),

  // ── Plain sub text ──
  sub: ({ text, tone }) => (
    <div className="w-sub" data-tone={tone}>{text}</div>
  ),

  // ── Spacer ──
  spacer: () => <div style={{flex: 1}}/>,
};

// ─── SLOT RENDERERS ──────────────────────────────────────────
// Slots compose widgets. Renderer walks the spec and fills each slot.

function Slot({ content }) {
  if (!content) return null;
  if (Array.isArray(content)) {
    return <>{content.map((w, i) => <Slot key={i} content={w}/>)}</>;
  }
  const W = Widgets[content.kind];
  if (!W) return <span style={{color:"red"}}>?{content.kind}</span>;
  return <W {...content}/>;
}

// ─── CLOCK (always on) ───────────────────────────────────────
function Clock({ t = "9:41" }) { return <span className="w-clock">{t}</span>; }

// ─── SWIPE-LEFT ACTION DRAWER ────────────────────────────────
// Drag face left to reveal End / Pause. Release to commit.
function FaceShell({ spec, onTap, interactive = true }) {
  const [dragX, setDragX] = React.useState(0);
  const [dragging, setDragging] = React.useState(false);
  const startX = React.useRef(0);

  const hasSwipe = spec.swipe && spec.swipe.length > 0;
  const maxDrag = hasSwipe ? -132 : 0;

  const onStart = (e) => {
    if (!hasSwipe) return;
    setDragging(true);
    startX.current = (e.touches?.[0]?.clientX ?? e.clientX);
  };
  const onMove = (e) => {
    if (!dragging) return;
    const x = (e.touches?.[0]?.clientX ?? e.clientX);
    const d = Math.min(0, Math.max(maxDrag, x - startX.current));
    setDragX(d);
  };
  const onEnd = () => {
    if (!dragging) return;
    setDragging(false);
    setDragX(dragX < maxDrag / 2 ? maxDrag : 0);
  };

  const tapped = React.useRef(false);
  const handleClick = (e) => {
    if (Math.abs(dragX) > 5) { setDragX(0); return; }
    if (interactive && onTap) onTap();
  };

  return (
    <div className="face-shell">
      {hasSwipe && (
        <div className="swipe-actions">
          {spec.swipe.map((a, i) => (
            <button key={i} className={`swipe-btn tone-${a.tone || "muted"}`}
              onClick={(ev) => { ev.stopPropagation(); a.onClick?.(); setDragX(0); }}>
              {a.icon && <span className="swipe-icon">{a.icon}</span>}
              <span>{a.label}</span>
            </button>
          ))}
        </div>
      )}
      <div className="face-layer"
        style={{transform: `translateX(${dragX}px)`, transition: dragging ? "none" : "transform .25s"}}
        onMouseDown={onStart} onMouseMove={onMove} onMouseUp={onEnd} onMouseLeave={onEnd}
        onTouchStart={onStart} onTouchMove={onMove} onTouchEnd={onEnd}
        onClick={handleClick}>
        <Face spec={spec}/>
      </div>
    </div>
  );
}

// ─── FACE RENDERER ───────────────────────────────────────────
// Takes a spec, lays out the slots.
function Face({ spec }) {
  const { header, hero, stats, progress, footer, layout = "default" } = spec;

  return (
    <div className={`face face-layout-${layout}`}>
      {progress && <Slot content={progress}/>}
      <Clock/>
      {header && <div className="face-header"><Slot content={header}/></div>}
      {hero && <div className="face-hero"><Slot content={hero}/></div>}
      {stats && <div className="face-stats" data-count={stats.length}>
        {stats.map((s, i) => <Slot key={i} content={s}/>)}
      </div>}
      {footer && <div className="face-footer"><Slot content={footer}/></div>}
    </div>
  );
}

// Export for the app file
window.WatchGrammar = { Face, FaceShell, Widgets, Slot };
