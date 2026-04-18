// Section 6-8 — Watch, Prescription shapes, First-run, History

// ─── WATCH ─────────────────────────────────────────────
function WatchSet() {
  return (
    <div className="watch">
      <span className="w-time">9:41</span>
      <div className="tiny" style={{color:"#aaa"}}>SET 3 / 5</div>
      <div style={{fontFamily:"var(--mono)", fontSize:48, fontWeight: 200, marginTop: 6}}>
        225
      </div>
      <div className="tiny" style={{color:"#aaa"}}>LB × 5</div>
      <div style={{marginTop: "auto", borderTop: "1px solid #333", paddingTop: 6, display:"flex", justifyContent:"space-between"}}>
        <span style={{fontFamily:"var(--mono)", fontSize: 11, color:"var(--accent)"}}>♥ 112</span>
        <span style={{fontFamily:"var(--mono)", fontSize: 11}}>TAP→START</span>
      </div>
    </div>
  );
}

function WatchRest() {
  return (
    <div className="watch">
      <span className="w-time">9:42</span>
      <div className="tiny" style={{color:"#aaa"}}>REST</div>
      <div style={{fontFamily:"var(--mono)", fontSize: 56, fontWeight: 200, marginTop: 4, color:"var(--accent)"}}>
        1:24
      </div>
      <div className="tiny" style={{color:"#aaa", marginTop: 4}}>NEXT · 225×5</div>
      <div className="watch-face-tabbar">
        <span className="dot"/><span className="dot on"/><span className="dot"/>
      </div>
    </div>
  );
}

function WatchMinimal() {
  return (
    <div className="watch">
      <span className="w-time" style={{color:"#666"}}>9:41</span>
      <div style={{flex: 1, display:"flex", alignItems:"center", justifyContent:"center"}}>
        <div style={{textAlign:"center"}}>
          <div style={{fontFamily:"var(--mono)", fontSize: 72, fontWeight: 200}}>5</div>
          <div className="tiny" style={{color:"#aaa", marginTop: 2}}>REPS TO GO</div>
        </div>
      </div>
      <div className="tiny" style={{textAlign:"center", color:"#aaa"}}>TAP TO END SET</div>
    </div>
  );
}

function WatchHR() {
  return (
    <div className="watch">
      <span className="w-time">9:41</span>
      <div className="tiny" style={{color:"#aaa"}}>EMOM · MIN 5/12</div>
      <div style={{fontFamily:"var(--mono)", fontSize: 42, fontWeight: 200, marginTop: 4}}>
        :43
      </div>
      <div style={{display:"flex", justifyContent:"space-between", marginTop: 6}}>
        <div>
          <div style={{fontFamily:"var(--mono)", fontSize: 20, color:"var(--accent)"}}>164</div>
          <div className="tiny" style={{color:"#aaa"}}>♥ BPM</div>
        </div>
        <div style={{textAlign:"right"}}>
          <div style={{fontFamily:"var(--mono)", fontSize: 20}}>10/10</div>
          <div className="tiny" style={{color:"#aaa"}}>reps</div>
        </div>
      </div>
      <div className="watch-face-tabbar">
        <span className="dot on"/><span className="dot"/><span className="dot"/>
      </div>
    </div>
  );
}

function WatchSection() {
  return (
    <Section
      title="7. Watch companion"
      kicker="v1 · not an afterthought"
      intro="Watch contract: haptic at every timer transition, tap to start/end a set, HR auto-capture. These four explore what lives on the face while a set is running."
    >
      <div className="row">
        <Variant num="7.A" name="Set face" tagline="Load × reps. Heart rate pinned. One-tap start."
          notes={<Notes pros={["Zero-read under the bar", "HR always visible"]}
            cons={["No set-history context"]}/>}>
          <WatchSet/>
        </Variant>
        <Variant num="7.B" name="Rest face" tagline="Countdown hero. Next set teased."
          notes={<Notes pros={["Auto-switches when set ends", "Page pips for phone parity"]}
            cons={["Small 'next' text"]}/>}>
          <WatchRest/>
        </Variant>
        <Variant num="7.C" name="Minimal" tagline="One number, one tap. Maximum glance."
          notes={<Notes pros={["Impossible to misread", "Fastest interaction"]}
            cons={["Loses load + RPE context — phone does that"]}/>}>
          <WatchMinimal/>
        </Variant>
        <Variant num="7.D" name="EMOM face" tagline="Timer + HR + rep counter for conditioning modes."
          notes={<Notes pros={["Everything the metcon needs", "HR is the signal here"]}
            cons={["Three elements = harder to glance"]}/>}>
          <WatchHR/>
        </Variant>
      </div>

      {/* Watch-phone relationship matrix */}
      <div style={{marginTop: 36, maxWidth: 840, padding: 16, border: "1px dashed var(--ink-4)", borderRadius: 12}}>
        <div className="hand" style={{fontSize: 20, marginBottom: 10}}>Watch ⇄ phone relationships to try</div>
        <div style={{display:"grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12}}>
          {[
            {t: "Watch-primary", d: "Phone mirrors; you drive with the wrist.", n: "best under a barbell"},
            {t: "Phone-primary", d: "Watch is a glance + haptic surface only.", n: "best for logging-heavy lifters"},
            {t: "Equal / whichever's handy", d: "Tap on either advances the set. Sync in background.", n: "best for mixed sessions (lift + run)"},
          ].map(x => (
            <div key={x.t} style={{padding: 10, border: "1px solid var(--ink-4)", borderRadius: 8}}>
              <div className="hand" style={{fontSize: 16}}>{x.t}</div>
              <div className="small" style={{marginTop: 4}}>{x.d}</div>
              <div className="tiny" style={{marginTop: 8, color: "var(--accent)"}}>{x.n}</div>
            </div>
          ))}
        </div>
      </div>
    </Section>
  );
}

// ─── PRESCRIPTION STRESS-TESTS ─────────────────────────
function RxCard({ kind, rx, children }) {
  return (
    <div style={{
      width: 240, border: "1.5px solid var(--ink)", borderRadius: 14,
      padding: 14, background: "var(--paper)",
    }}>
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
      kicker="every rx shape, same layout"
      intro="The active-set screen has to render every prescription shape in the spec. Shown as inline cards so you can compare shapes side-by-side without re-reading the chrome."
    >
      <div className="row" style={{gap: 16}}>
        <RxCard kind="STRAIGHT" rx="5 × 5 @ 225 lb">
          <div className="small">Sets × reps × load. RPE 8 target.</div>
        </RxCard>

        <RxCard kind="REPS ONLY" rx="3 × 12 push-ups">
          <div className="small">No load. RPE optional on finish.</div>
        </RxCard>

        <RxCard kind="TIME-HOLD" rx="3 × :45 plank">
          <div className="small">Per-set countdown · haptic at :15, :0.</div>
        </RxCard>

        <RxCard kind="DIST + PACE" rx="6 × 400 m @ 1:30">
          <div className="small">Distance target · pace ghost on watch.</div>
        </RxCard>

        <RxCard kind="REP RANGE" rx="4 × 6–10 @ 145">
          <div className="small">Ranges render as 10 pips · filled = done.</div>
          <div style={{display:"flex", gap: 3, marginTop: 6}}>
            {Array.from({length: 10}).map((_, i) => (
              <div key={i} style={{
                flex: 1, height: 6, borderRadius: 2,
                background: i < 7 ? "var(--ink)" : i < 6 ? "transparent" : "var(--ink-4)",
                border: i < 6 ? "none" : "1px dashed var(--ink-4)",
              }}/>
            ))}
          </div>
          <div className="tiny" style={{marginTop: 4}}>7 reps · still in range</div>
        </RxCard>

        <RxCard kind="PER-SIDE" rx="3 × 12/side SA Row">
          <div className="small">L/R toggles · completed side ticked.</div>
          <div style={{display:"flex", gap: 8, marginTop: 6}}>
            <div style={{flex: 1, padding: "6px 0", textAlign:"center", border: "1px solid var(--ink)", borderRadius: 6, fontFamily: "var(--mono)", fontSize: 12}}>L ✓</div>
            <div style={{flex: 1, padding: "6px 0", textAlign:"center", border: "1.5px solid var(--accent)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 12, background:"var(--accent-soft)"}}>R</div>
          </div>
        </RxCard>

        <RxCard kind="%1RM" rx="5 × 3 @ 82%">
          <div className="small">Resolves to 265 lb from history.</div>
          <div className="tiny" style={{marginTop: 4, color:"var(--accent)"}}>= 265 lb (est 1RM 325)</div>
        </RxCard>

        <RxCard kind="TEMPO" rx="3 × 8 · tempo 3-1-2-0">
          <div className="small">Countdown beats render on watch.</div>
          <div style={{fontFamily:"var(--mono)", fontSize: 11, marginTop: 4, display: "flex", gap: 6}}>
            <span>ecc 3</span><span>pause 1</span><span>con 2</span><span>top 0</span>
          </div>
        </RxCard>

        <RxCard kind="PER-SET VAR" rx="Pyramid 12/10/8/6/4">
          <div style={{display:"grid", gridTemplateColumns:"repeat(5, 1fr)", gap: 4}}>
            {[
              {r:12, l:135, on:false, done:true},
              {r:10, l:155, on:false, done:true},
              {r:8, l:175, on:true},
              {r:6, l:195},
              {r:4, l:215},
            ].map((s, i) => (
              <div key={i} style={{
                textAlign:"center", padding: "6px 2px",
                border: s.on ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
                borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11,
                opacity: s.done ? 0.5 : 1,
              }}>
                <div>×{s.r}</div>
                <div style={{color:"var(--ink-2)"}}>{s.l}</div>
              </div>
            ))}
          </div>
        </RxCard>

        <RxCard kind="DROP SET" rx="1 top set → 2 drops">
          <div style={{display:"flex", gap: 4, alignItems:"center", marginTop: 4}}>
            <div style={{padding: "6px 10px", border: "1.5px solid var(--ink)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11}}>8 @ 185</div>
            <span className="tiny">↓</span>
            <div style={{padding: "6px 10px", border: "1px dashed var(--ink-4)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11}}>AMRAP @ 155</div>
            <span className="tiny">↓</span>
            <div style={{padding: "6px 10px", border: "1px dashed var(--ink-4)", borderRadius: 6, fontFamily:"var(--mono)", fontSize: 11}}>AMRAP @ 135</div>
          </div>
        </RxCard>

        <RxCard kind="CLUSTER" rx="5 × (3.3.3) @ 245 · :15 intra">
          <div style={{display:"flex", gap: 4, marginTop: 4}}>
            {["3", ":15", "3", ":15", "3"].map((s, i) => (
              <div key={i} style={{
                padding: "4px 8px", border: "1px solid var(--ink-4)", borderRadius: 4,
                fontFamily:"var(--mono)", fontSize: 11,
                background: s.startsWith(":") ? "var(--paper-2)" : "transparent",
              }}>{s}</div>
            ))}
          </div>
          <div className="tiny" style={{marginTop: 4}}>intra-cluster countdown auto-runs</div>
        </RxCard>

        <RxCard kind="ROUNDS" rx="21-15-9 chipper">
          <div style={{display:"flex", gap: 8, fontFamily:"var(--mono)", fontSize: 16, marginTop: 4}}>
            <span style={{color:"var(--ink-3)", textDecoration:"line-through"}}>21</span>
            <span style={{color:"var(--accent)"}}>15</span>
            <span style={{color:"var(--ink-2)"}}>9</span>
          </div>
          <div className="small" style={{marginTop: 6}}>current round highlighted · struck-through = done</div>
        </RxCard>
      </div>
    </Section>
  );
}

// ─── FIRST RUN + HISTORY ───────────────────────────────
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
            <div style={{
              border: "1.5px solid var(--ink)", borderRadius: 8,
              padding: "10px 12px", fontFamily: "var(--mono)", fontSize: 12,
              color: "var(--ink-2)",
            }}>{f.v}</div>
          </div>
        ))}
      </div>
      <div style={{padding: "0 16px", marginTop: 4}}>
        <div className="small">App will pull your next workout once on connect, then never again automatically. Refresh manually to re-sync.</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Connect & pull</div>
      </div>
    </Phone>
  );
}

function SyncOffline() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today"/>
      <div style={{margin: "0 16px", padding: "10px 12px",
        border: "1.5px solid var(--ink)", borderRadius: 10,
        background: "var(--accent-soft)",
        display: "flex", justifyContent: "space-between", alignItems: "center"}}>
        <div>
          <div className="tiny" style={{color: "var(--accent)"}}>OFFLINE · 2 sessions queued</div>
          <div className="small">Will sync when connection returns</div>
        </div>
        <div className="pill accent">retry</div>
      </div>
      <div style={{padding: "20px 16px 0"}}>
        <div className="tiny">next up</div>
        <div className="hand" style={{fontSize: 22}}>Lower B · Pull</div>
        <div className="small">8 exercises · ~52 min</div>
      </div>
      <div style={{padding: "12px 16px 0"}}>
        {["Back Squat 5×5","RDL 4×8","Bulgarian Split 3×10","Leg Curl 3×12","Hanging Knee Raise 3×12"].map(x => (
          <div key={x} style={{padding: "8px 0", borderTop: "1px dashed var(--ink-4)", fontFamily: "var(--mono)", fontSize: 12}}>
            {x}
          </div>
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
        {d: "Apr 15", n: "Upper A · Push", sub: "48:22 · RPE 8"},
        {d: "Apr 13", n: "Lower B · Pull", sub: "52:10 · RPE 7.5"},
        {d: "Apr 11", n: "Conditioning · Tabata", sub: "18:40 · RPE 9"},
        {d: "Apr 9", n: "Upper B · Pull", sub: "45:01 · RPE 8"},
        {d: "Apr 7", n: "Lower A · Push", sub: "56:32 · RPE 8.5"},
      ].map(x => (
        <div key={x.d} style={{
          display:"flex", alignItems:"center",
          padding: "12px 16px", borderTop: "1px dashed var(--ink-4)",
        }}>
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
        <div className="submeta" style={{padding: 0}}>48:22 · 42 sets · overall RPE 8</div>
      </div>
      <div className="divider dashed"/>
      {[
        {n: "Back Squat", sets: "225×5, 225×5, 225×5, 225×5, 225×4", rpe: "8"},
        {n: "DB Bench", sets: "60×10, 60×10, 60×9", rpe: "8"},
        {n: "Chest Row", sets: "50×12, 50×12, 50×11", rpe: "7.5"},
      ].map(x => (
        <div key={x.n} style={{padding: "10px 16px", borderTop: "1px dashed var(--ink-4)"}}>
          <div className="hand" style={{fontSize: 15}}>{x.n}</div>
          <div className="small" style={{marginTop: 2, fontFamily: "var(--mono)", fontSize: 11}}>{x.sets}</div>
          <div className="tiny" style={{marginTop: 4}}>rpe {x.rpe}</div>
        </div>
      ))}
      <TabBar active="History"/>
    </Phone>
  );
}

function HistoryFirstRunSection() {
  return (
    <Section
      title="6. History · first-run · sync indicators"
      kicker="supporting surfaces"
      intro="History is a read-only archive of what happened (per the ADR — no PRs, no charts). First-run is a single-screen token paste. Offline/sync state lives in a persistent banner."
    >
      <div className="row">
        <Variant num="6.A" name="First-run" tagline="One screen. URL · token · UUID. Pull once."
          notes={<Notes pros={["Zero-ambiguity setup", "Token masked by default"]}
            cons={["Requires user to generate token elsewhere"]}/>}>
          <FirstRun/>
        </Variant>
        <Variant num="6.B" name="Today + offline" tagline="Home screen showing queued sessions + offline pill."
          notes={<Notes pros={["Sync state never hidden", "One-tap retry"]}
            cons={["Banner adds vertical space"]}/>}>
          <SyncOffline/>
        </Variant>
        <Variant num="6.C" name="History list" tagline="Date · name · duration · overall RPE. Nothing else."
          notes={<Notes pros={["Exactly what the ADR scopes", "Fast to scroll"]}
            cons={["No trends — intentional"]}/>}>
          <History/>
        </Variant>
        <Variant num="6.D" name="History detail" tagline="Tap a row → the set logs, flat."
          notes={<Notes pros={["Paper-log feel", "Easy to copy into Claude for analysis"]}
            cons={["Long workouts = long scroll"]}/>}>
          <HistoryDetail/>
        </Variant>
      </div>
    </Section>
  );
}

Object.assign(window, {
  WatchSection, PrescriptionSection, HistoryFirstRunSection,
});
