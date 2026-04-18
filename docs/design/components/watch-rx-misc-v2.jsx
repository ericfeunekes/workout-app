// v2 · watch/rx/misc
// Watch: HR + time always, single progress button per mode.
// Prescription shapes: RIR. Misc: offline demoted to tiny pill.

function WatchFace({ top, mid, sub, hr = "112", hrColor, time = "9:41" }) {
  return (
    <div className="watch">
      <span className="w-time">{time}</span>
      <div className="tiny" style={{color:"#aaa"}}>{top}</div>
      {mid}
      <div className="tiny" style={{color:"#aaa", marginTop: 2}}>{sub}</div>
      <div style={{marginTop: "auto", borderTop: "1px solid #333", paddingTop: 6,
        display:"flex", justifyContent:"space-between", alignItems:"center"}}>
        <span style={{fontFamily:"var(--mono)", fontSize: 11, color: hrColor || "var(--accent)"}}>♥ {hr}</span>
        <span style={{fontFamily:"var(--mono)", fontSize: 10, color:"#aaa"}}>TAP →</span>
      </div>
    </div>
  );
}

function WatchSet() {
  return <WatchFace
    top="SET 3 / 5 · BACK SQUAT"
    mid={<div style={{fontFamily:"var(--mono)", fontSize:44, fontWeight:200, marginTop: 4}}>225</div>}
    sub="LB × 5 · 2 RIR"
    hr="112"/>;
}

function WatchRest() {
  return <WatchFace
    top="REST"
    mid={<div style={{fontFamily:"var(--mono)", fontSize: 56, fontWeight: 200, marginTop: 2, color:"var(--accent)"}}>1:24</div>}
    sub="NEXT · 225 × 5"
    hr="98"/>;
}

function WatchSuper() {
  return <WatchFace
    top="SUPERSET · ROUND 2/4"
    mid={<div style={{fontFamily:"var(--mono)", fontSize: 26, marginTop: 4}}>DB Bench<br/><span style={{fontSize:20, color:"#aaa"}}>60×10</span></div>}
    sub="THEN · ROW 50×12"
    hr="134"/>;
}

// NEW: superset face with dual action (advance + advance-to-end)
function WatchSuperDual() {
  return (
    <div className="watch">
      <span className="w-time">9:41</span>
      <div className="tiny" style={{color:"#aaa"}}>SUPERSET · R 2/4</div>
      <div style={{fontFamily:"var(--mono)", fontSize: 22, marginTop: 4}}>DB Bench 60×10</div>
      <div className="tiny" style={{color:"#aaa", marginTop: 2}}>THEN · ROW 50×12</div>
      <div style={{marginTop: "auto", display: "flex", gap: 4}}>
        <div style={{flex: 3, padding: "6px 0", textAlign:"center", border: "1px solid var(--accent)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11, color:"var(--accent)"}}>NEXT ›</div>
        <div style={{flex: 2, padding: "6px 0", textAlign:"center", border: "1px solid #555", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 10, color:"#aaa"}}>END ››</div>
      </div>
      <div style={{fontFamily:"var(--mono)", fontSize: 10, color:"var(--accent)", textAlign:"center", marginTop: 4}}>♥ 134</div>
    </div>
  );
}

function WatchEmom() {
  return <WatchFace
    top="EMOM · MIN 5/12"
    mid={<div style={{fontFamily:"var(--mono)", fontSize: 46, fontWeight: 200, marginTop: 4}}>:43</div>}
    sub="10 POWER CLEANS @ 95"
    hr="164" hrColor="#ff6b5a"/>;
}

function WatchSection() {
  return (
    <Section
      title="7. Watch · HR + time always · one progress tap"
      kicker="single button per mode"
      intro="HR and time are always on screen. The wrist action is always 'tap to progress' — start the set, end the set, advance the station, +1 round. No rep counting on the watch."
    >
      <div className="row">
        <Variant num="7.A" name="Set face" tagline="225 × 5 · 2 RIR · tap starts the set."
          notes={<Notes pros={["All prescribed signals visible","One-tap start / end"]} cons={[]}/>}>
          <WatchSet/>
        </Variant>
        <Variant num="7.B" name="Rest face" tagline="Big countdown, next set teased. Tap = skip rest."
          notes={<Notes pros={["HR drop visible during rest","Auto-advance at zero"]} cons={[]}/>}>
          <WatchRest/>
        </Variant>
        <Variant num="7.C" name="Superset face · advance" tagline="Tap = next exercise. Rare case needs a second action."
          notes={<Notes pros={["Matches phone pattern"]} cons={["Needs companion face for advance-to-end"]}/>}>
          <WatchSuper/>
        </Variant>
        <Variant num="7.C2" name="Superset · dual button" tagline="NEXT (primary) + END (secondary) · tap-tap through the rest."
          notes={<Notes pros={["One tap = common case","Rare skip-to-end is explicit, not a weird gesture","Easy to tap-tap-tap through a few"]} cons={["Two targets on a small face"]}/>}>
          <WatchSuperDual/>
        </Variant>
        <Variant num="7.D" name="EMOM face" tagline="Timer + HR + rep target. Tap = done early."
          notes={<Notes pros={["HR is the signal in metcons","Early-done stops waiting for :0"]} cons={[]}/>}>
          <WatchEmom/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── PRESCRIPTION STRESS-TESTS (RIR) ───────────────────────
function RxCard({ kind, rx, children }) {
  return (
    <div style={{width: 240, border: "1.5px solid var(--ink)", borderRadius: 14, padding: 14, background: "var(--paper)"}}>
      <div className="tiny" style={{color:"var(--accent)"}}>{kind}</div>
      <div className="hand" style={{fontSize: 18, margin: "4px 0 10px"}}>{rx}</div>
      {children}
    </div>
  );
}

function PrescriptionSection() {
  return (
    <Section
      title="8. Prescription-shape stress tests"
      kicker="RIR-based · every rx shape"
      intro="Every prescription shape rendered inline, RIR as the effort signal."
    >
      <div className="row" style={{gap: 16}}>
        <RxCard kind="STRAIGHT" rx="5 × 5 @ 225 lb">
          <div className="small">Sets × reps × load · target 2 RIR.</div>
        </RxCard>
        <RxCard kind="REPS ONLY" rx="3 × 12 push-ups">
          <div className="small">No load · RIR asked on finish.</div>
        </RxCard>
        <RxCard kind="TIME-HOLD" rx="3 × :45 plank">
          <div className="small">Per-set countdown · haptic at :15, :0.</div>
        </RxCard>
        <RxCard kind="DIST + PACE" rx="6 × 400 m @ 1:30">
          <div className="small">Distance target · pace ghost on watch.</div>
        </RxCard>
        <RxCard kind="REP RANGE" rx="4 × 6–10 @ 145 · 2 RIR">
          <div style={{display:"flex", gap: 3, marginTop: 6}}>
            {Array.from({length: 10}).map((_, i) => (
              <div key={i} style={{flex: 1, height: 6, borderRadius: 2,
                background: i < 7 ? "var(--ink)" : i < 6 ? "transparent" : "var(--ink-4)",
                border: i < 6 ? "none" : "1px dashed var(--ink-4)"}}/>
            ))}
          </div>
          <div className="tiny" style={{marginTop: 4}}>7 reps · still in range</div>
        </RxCard>
        <RxCard kind="PER-SIDE" rx="3 × 12/side SA Row">
          <div style={{display:"flex", gap: 8, marginTop: 6}}>
            <div style={{flex: 1, padding: "6px 0", textAlign:"center", border: "1px solid var(--ink)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 12}}>L ✓</div>
            <div style={{flex: 1, padding: "6px 0", textAlign:"center", border: "1.5px solid var(--accent)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 12, background:"var(--accent-soft)"}}>R</div>
          </div>
        </RxCard>
        <RxCard kind="%1RM" rx="5 × 3 @ 82% · 2 RIR">
          <div className="tiny" style={{marginTop: 4, color:"var(--accent)"}}>= 265 lb (est 1RM 325)</div>
        </RxCard>
        <RxCard kind="TEMPO" rx="3 × 8 · tempo 3-1-2-0">
          <div style={{fontFamily:"var(--mono)", fontSize: 11, marginTop: 4, display: "flex", gap: 6}}>
            <span>ecc 3</span><span>pause 1</span><span>con 2</span><span>top 0</span>
          </div>
        </RxCard>
        <RxCard kind="PER-SET VAR" rx="Pyramid 12/10/8/6/4">
          <div style={{display:"grid", gridTemplateColumns:"repeat(5, 1fr)", gap: 4}}>
            {[{r:12,l:135,done:true},{r:10,l:155,done:true},{r:8,l:175,on:true},{r:6,l:195},{r:4,l:215}].map((s, i) => (
              <div key={i} style={{textAlign:"center", padding: "6px 2px",
                border: s.on ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
                borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11, opacity: s.done ? 0.5 : 1}}>
                <div>×{s.r}</div><div style={{color:"var(--ink-2)"}}>{s.l}</div>
              </div>
            ))}
          </div>
        </RxCard>
        <RxCard kind="DROP SET" rx="1 top set → 2 drops">
          <div style={{display:"flex", gap: 4, alignItems:"center", marginTop: 4, flexWrap: "wrap"}}>
            <div style={{padding: "5px 8px", border: "1.5px solid var(--ink)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11}}>8@185</div>
            <span className="tiny">↓</span>
            <div style={{padding: "5px 8px", border: "1px dashed var(--ink-4)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11}}>AMRAP@155</div>
            <span className="tiny">↓</span>
            <div style={{padding: "5px 8px", border: "1px dashed var(--ink-4)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11}}>AMRAP@135</div>
          </div>
        </RxCard>
        <RxCard kind="CLUSTER" rx="5 × (3.3.3) @ 245 · :15 intra">
          <div style={{display:"flex", gap: 4, marginTop: 4}}>
            {["3", ":15", "3", ":15", "3"].map((s, i) => (
              <div key={i} style={{padding: "4px 8px", border: "1px solid var(--ink-4)", borderRadius: 4,
                fontFamily:"var(--mono)", fontSize: 11, background: s.startsWith(":") ? "var(--paper-2)" : "transparent"}}>{s}</div>
            ))}
          </div>
        </RxCard>
        <RxCard kind="ROUNDS" rx="21-15-9 chipper">
          <div style={{display:"flex", gap: 8, fontFamily:"var(--mono)", fontSize: 16, marginTop: 4}}>
            <span style={{color:"var(--ink-3)", textDecoration:"line-through"}}>21</span>
            <span style={{color:"var(--accent)"}}>15</span>
            <span style={{color:"var(--ink-2)"}}>9</span>
          </div>
          <div className="small" style={{marginTop: 6}}>big NEXT on group done</div>
        </RxCard>
      </div>
    </Section>
  );
}

// ─── FIRST-RUN + HISTORY + QUIET OFFLINE ──────────────
function FirstRun() {
  return (
    <Phone>
      <StatusRow/>
      <div style={{padding: "16px 16px 0"}}>
        <div className="hand" style={{fontSize: 28}}>WorkoutDB</div>
        <div className="small">One-time setup · stays local</div>
      </div>
      <div style={{padding: "20px 16px 0"}}>
        {[
          {l: "Server URL", v: "https://workoutdb.eric.local"},
          {l: "Bearer token", v: "••••••••••••••b9f3"},
          {l: "User UUID", v: "eric-a7c2-4f…"},
        ].map(f => (
          <div key={f.l} style={{marginBottom: 16}}>
            <div className="tiny" style={{marginBottom: 4}}>{f.l}</div>
            <div style={{border: "1.5px solid var(--ink)", borderRadius: 8, padding: "10px 12px",
              fontFamily: "var(--mono)", fontSize: 12, color: "var(--ink-2)"}}>{f.v}</div>
          </div>
        ))}
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Connect & pull</div>
      </div>
    </Phone>
  );
}

function TodayQuietOffline() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today"/>
      <div style={{padding: "0 16px 6px", display: "flex", justifyContent: "flex-end"}}>
        <span className="pill" style={{fontSize: 9, borderStyle: "dashed", color: "var(--ink-3)"}}>
          offline · 2 queued · tap to retry
        </span>
      </div>
      <div style={{padding: "4px 16px 0"}}>
        <div className="tiny">next up</div>
        <div className="hand" style={{fontSize: 24}}>Lower B · Pull</div>
        <div className="small">8 exercises · ~52 min</div>
      </div>
      <div style={{padding: "12px 16px 0"}}>
        {["Back Squat 5×5","RDL 4×8","Bulgarian Split 3×10","Leg Curl 3×12","Hanging Knee Raise 3×12"].map(x => (
          <div key={x} style={{padding: "8px 0", borderTop: "1px dashed var(--ink-4)", fontFamily: "var(--mono)", fontSize: 12}}>{x}</div>
        ))}
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Start workout</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function History() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="History"/>
      <div className="small" style={{padding: "0 16px 8px"}}>logs only — no charts, no PRs</div>
      {[
        {d: "Apr 15", n: "Upper A · Push", sub: "48:22 · avg 2 RIR"},
        {d: "Apr 13", n: "Lower B · Pull", sub: "52:10 · avg 2 RIR"},
        {d: "Apr 11", n: "Conditioning · Tabata", sub: "18:40"},
        {d: "Apr 9", n: "Upper B · Pull", sub: "45:01 · avg 1 RIR"},
        {d: "Apr 7", n: "Lower A · Push", sub: "56:32 · avg 1 RIR"},
      ].map(x => (
        <div key={x.d} style={{display:"flex", alignItems:"center", padding: "12px 16px",
          borderTop: "1px dashed var(--ink-4)"}}>
          <div style={{width: 50}} className="tiny">{x.d}</div>
          <div style={{flex: 1}}>
            <div className="hand" style={{fontSize: 15}}>{x.n}</div>
            <div className="small">{x.sub}</div>
          </div>
          <span className="tiny">›</span>
        </div>
      ))}
      <TabBar active="History"/>
    </Phone>
  );
}

function HistoryDetail() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Apr 15"/>
      <div style={{padding: "0 16px"}}>
        <div className="hand" style={{fontSize: 22}}>Upper A · Push</div>
        <div className="submeta" style={{padding: 0}}>48:22 · 42 sets · avg 2 RIR</div>
      </div>
      <div className="divider dashed"/>
      {[
        {n: "Back Squat", sets: "225×5 (3), ×5 (2), ×5 (2), ×5 (1), ×4 (0)"},
        {n: "DB Bench", sets: "60×10 (3), ×10 (2), ×9 (1)"},
        {n: "Chest Row", sets: "50×12 (3), ×12 (2), ×11 (2)"},
      ].map(x => (
        <div key={x.n} style={{padding: "10px 16px", borderTop: "1px dashed var(--ink-4)"}}>
          <div className="hand" style={{fontSize: 15}}>{x.n}</div>
          <div className="small" style={{marginTop: 2, fontFamily: "var(--mono)", fontSize: 11}}>{x.sets}</div>
          <div className="tiny" style={{marginTop: 4}}>() = RIR</div>
        </div>
      ))}
      <TabBar active="History"/>
    </Phone>
  );
}

function HistoryFirstRunSection() {
  return (
    <Section
      title="6. Supporting · history · setup · quiet offline"
      kicker="RIR throughout · offline demoted"
      intro="Offline is now just a small dashed pill (tap to retry). History and first-run unchanged in spirit, with RIR replacing RPE."
    >
      <div className="row">
        <Variant num="6.A" name="First-run" tagline="URL · token · UUID. Pull once."
          notes={<Notes pros={["Unchanged — it's right"]} cons={[]}/>}>
          <FirstRun/>
        </Variant>
        <Variant num="6.B" name="Today · quiet offline" tagline="Tiny pill in the corner. Session data never gated on sync."
          notes={<Notes pros={["Invisible when online","Tap pill = manual retry","Doesn't eat vertical space"]} cons={[]}/>}>
          <TodayQuietOffline/>
        </Variant>
        <Variant num="6.C" name="History list" tagline="avg RIR per session shown; conditioning omits it."
          notes={<Notes pros={["Matches ADR scope"]} cons={[]}/>}>
          <History/>
        </Variant>
        <Variant num="6.D" name="History detail" tagline="Set logs with RIR in parens — parseable by Claude."
          notes={<Notes pros={["Paper-log feel","Copy-friendly"]} cons={[]}/>}>
          <HistoryDetail/>
        </Variant>
      </div>
    </Section>
  );
}

Object.assign(window, { WatchSection, PrescriptionSection, HistoryFirstRunSection });
