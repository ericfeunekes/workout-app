// Shared wireframe primitives

function Phone({ children, tall, style }) {
  return (
    <div className={"phone " + (tall ? "tall" : "")} style={style}>
      <div className="screen">{children}</div>
    </div>
  );
}

function Nav({ title, right = "•••", back = "‹ Back" }) {
  return (
    <div className="nav">
      <span className="back">{back}</span>
      <span className="title">{title}</span>
      <span>{right}</span>
    </div>
  );
}

function TabBar({ active = "Workout" }) {
  const tabs = ["Today", "Workout", "History", "Settings"];
  return (
    <div className="tabbar">
      {tabs.map(t => (
        <div key={t} className={"tab " + (t === active ? "active" : "")}>{t}</div>
      ))}
    </div>
  );
}

function Variant({ num, name, tagline, notes, children }) {
  return (
    <div className="variant">
      <div className="variant-head">
        <div className="num">{num}</div>
        <div className="name">{name}</div>
        <div className="tagline">{tagline}</div>
      </div>
      <div className="variant-body">
        {children}
        {notes && <div className="notes">{notes}</div>}
      </div>
    </div>
  );
}

function Notes({ pros = [], cons = [], tag }) {
  return (
    <>
      {tag && <span className="label">Trade</span>}
      {pros.map((p, i) => <span key={"p"+i} className="pro">{p}</span>)}
      {cons.map((c, i) => <span key={"c"+i} className="con">{c}</span>)}
    </>
  );
}

function Ring({ pct = 0.35, t = "1:24", s = "Rest" }) {
  const r = 80;
  const c = 2 * Math.PI * r;
  const dash = c * pct;
  return (
    <div className="ring-wrap">
      <svg viewBox="0 0 200 200">
        <circle cx="100" cy="100" r={r} fill="none" stroke="var(--ink-4)" strokeWidth="4"/>
        <circle cx="100" cy="100" r={r} fill="none" stroke="var(--accent)" strokeWidth="4"
          strokeDasharray={`${dash} ${c - dash}`} strokeDashoffset={c / 4} strokeLinecap="round"
          transform="rotate(-90 100 100)"/>
      </svg>
      <div className="ring-label">
        <div className="t">{t}</div>
        <div className="s">{s}</div>
      </div>
    </div>
  );
}

function StatusRow() {
  return (
    <div className="status-row">
      <span>9:41</span>
      <span>●●●●</span>
    </div>
  );
}

function LastTime({ summary = "225×5 @ RPE 8  ·  4d ago" }) {
  return (
    <div className="last-time">
      <span className="lt-head">Last time</span>
      {summary}
    </div>
  );
}

function Bar({ w = "100%", h = 8, c = "" }) {
  return <div className={"bar " + c} style={{ width: w, height: h }} />;
}

function Section({ title, kicker, intro, children }) {
  return (
    <section className="section">
      <div className="section-head">
        <h2>{title}</h2>
        <span className="kicker">{kicker}</span>
      </div>
      {intro && <p className="section-intro">{intro}</p>}
      {children}
    </section>
  );
}

Object.assign(window, { Phone, Nav, TabBar, Variant, Notes, Ring, StatusRow, LastTime, Bar, Section });
