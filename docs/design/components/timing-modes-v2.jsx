// v2 · timing modes
// Key changes: Superset is pure NEXT. AMRAP is +1 only, partial at end.
// For-time: big NEXT on group finish. RIR not RPE.

function ModePhone({ mode, children, right }) {
  return (
    <Phone>
      <StatusRow/>
      <div className="nav">
        <span className="back">‹ End</span>
        <span className="pill accent" style={{fontSize: 9}}>{mode}</span>
        <span>{right || "•••"}</span>
      </div>
      {children}
      <TabBar active="Workout"/>
    </Phone>
  );
}

// Superset — pure NEXT, no mid-set logging
function Superset() {
  return (
    <ModePhone mode="SUPERSET · A/B">
      <div style={{padding: "0 16px"}}>
        <div className="submeta" style={{padding: 0}}>Round 2 of 4 · just keep moving</div>
      </div>

      <div style={{padding: "10px 16px 6px", borderLeft: "3px solid var(--accent)", margin: "6px 16px"}}>
        <div className="tiny">NOW · A</div>
        <div className="hand" style={{fontSize: 26}}>DB Bench Press</div>
        <div className="small">60 × 10</div>
      </div>

      <div style={{margin: "6px 16px", opacity: 0.55}}>
        <div className="tiny">THEN · B</div>
        <div className="hand" style={{fontSize: 18}}>Chest-supported Row · 50 × 12</div>
      </div>

      <div className="divider dashed"/>
      <div className="small" style={{padding: "0 16px", textAlign:"center"}}>log everything on rest · just move</div>

      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent" style={{fontSize: 22, padding: "20px 20px"}}>Next →</div>
      </div>
    </ModePhone>
  );
}

// Circuit — single NEXT
function Circuit() {
  return (
    <ModePhone mode="CIRCUIT · 4 stations">
      <div style={{padding: "0 16px 4px"}}><div className="submeta" style={{padding:0}}>Round 1 of 3</div></div>
      <div style={{padding: "0 16px"}}>
        {[
          {i: 1, n: "Goblet Squat", r: "12 reps", on: false, done: true},
          {i: 2, n: "Push-Up", r: "AMRAP", on: true, done: false},
          {i: 3, n: "Ring Row", r: "12 reps"},
          {i: 4, n: "Plank", r: ":45"},
        ].map(s => (
          <div key={s.i} style={{
            display: "flex", gap: 10, alignItems: "center", padding: "9px 12px", margin: "5px 0",
            border: s.on ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)", borderRadius: 8,
            opacity: s.done ? 0.45 : 1,
          }}>
            <span className="tiny" style={{width: 14}}>{s.done ? "✓" : s.i}</span>
            <div style={{flex: 1}}>
              <div className="hand" style={{fontSize: s.on ? 18 : 15}}>{s.n}</div>
              <div className="small">{s.r}</div>
            </div>
          </div>
        ))}
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent" style={{fontSize: 20, padding: "18px 20px"}}>Next station →</div>
      </div>
    </ModePhone>
  );
}

// EMOM — still timed, but post-round log opens on rest
function Emom() {
  return (
    <ModePhone mode="EMOM · 12 min">
      <div style={{padding: "0 16px"}}><div className="submeta" style={{padding:0}}>Minute 5 of 12</div></div>
      <Ring pct={0.72} t=":43" s="this minute"/>
      <div style={{textAlign: "center"}}>
        <div className="hand" style={{fontSize: 22}}>10 Power Cleans @ 95</div>
        <div className="small">then rest remainder · haptic at :0</div>
      </div>
      <div className="divider dashed"/>
      <div className="set-row head"><span>min</span><span>reps</span><span>finish</span><span>RIR</span><span/></div>
      <div className="set-row done"><span className="num-cell">1</span><span>10</span><span>:38</span><span>4</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">2</span><span>10</span><span>:42</span><span>3</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">3</span><span>10</span><span>:45</span><span>3</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">4</span><span>10</span><span>:48</span><span>2</span><span className="check"/></div>
      <div className="set-row current"><span className="num-cell">5</span><span>—</span><span>—</span><span>—</span><span className="check"/></div>
    </ModePhone>
  );
}

// AMRAP — station advance + partial station at end
function Amrap() {
  return (
    <ModePhone mode="AMRAP · 15 min">
      <div style={{padding: "12px 16px 0", textAlign: "center"}}>
        <div className="big-num" style={{fontSize: 56}}>8:24</div>
        <div className="tiny">remaining</div>
      </div>
      <div className="divider dashed"/>
      <div style={{textAlign: "center"}}>
        <div className="tiny">round 4 · current</div>
        <div className="megareps" style={{fontSize: 56, color: "var(--accent)"}}>Push-Up</div>
      </div>
      <div style={{padding: "10px 16px"}}>
        <div className="small hand" style={{color: "var(--ink)"}}>1 round =</div>
        <div className="small">10 Pull-Ups · 15 Push-Ups · 20 Air Squats</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent" style={{fontSize: 24, padding: "22px 20px"}}>next</div>
        <div className="small" style={{textAlign:"center", marginTop: 6}}>logs this station, advances to the next</div>
      </div>
    </ModePhone>
  );
}

// NEW: AMRAP partial picker at end
function AmrapEnd() {
  return (
    <ModePhone mode="AMRAP · done">
      <div style={{padding: "16px 16px 0", textAlign: "center"}}>
        <div className="hand" style={{fontSize: 26}}>Time.</div>
        <div className="big-num" style={{fontSize: 44, marginTop: 8}}>4 rounds</div>
        <div className="tiny">full rounds counted</div>
      </div>
      <div style={{padding: "20px 16px 0"}}>
        <div className="tiny">any partial reps?</div>
        <div className="small" style={{marginTop: 4}}>1 round = 10 pull-ups · 15 push-ups · 20 squats</div>
      </div>
      <div style={{padding: "10px 16px", display:"grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 6}}>
        {[{l:"pull-ups", m:10, v:"10"},{l:"push-ups", m:15, v:"6"},{l:"squats", m:20, v:"0"}].map(x => (
          <div key={x.l} style={{border:"1.5px solid var(--ink)", borderRadius: 8, padding: "8px 6px", textAlign:"center"}}>
            <div className="big-num" style={{fontSize: 22}}>{x.v}</div>
            <div className="tiny">{x.l} /{x.m}</div>
          </div>
        ))}
      </div>
      <div style={{padding: "6px 16px"}}>
        <div className="btn ghost" style={{fontSize: 13}}>+ add a round I missed counting</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Save</div>
      </div>
    </ModePhone>
  );
}

// For Time — big NEXT on group completion
function ForTime() {
  return (
    <ModePhone mode="FOR TIME · 21-15-9">
      <div style={{padding: "12px 16px 0", textAlign: "center"}}>
        <div className="big-num" style={{fontSize: 44}}>4:12</div>
        <div className="tiny">elapsed</div>
      </div>
      <div className="divider dashed"/>
      <div style={{padding: "0 16px"}}>
        {[
          {r: "21", a: "Thrusters @ 95", done: true},
          {r: "21", a: "Pull-Ups", done: true},
          {r: "15", a: "Thrusters @ 95", on: true},
          {r: "15", a: "Pull-Ups"},
          {r: "9", a: "Thrusters @ 95"},
          {r: "9", a: "Pull-Ups"},
        ].map((s, i) => (
          <div key={i} style={{
            display: "flex", padding: "6px 0", gap: 10, alignItems: "center",
            borderTop: i === 0 ? "none" : "1px dashed var(--ink-4)",
            opacity: s.done ? 0.35 : 1,
          }}>
            <span className="big-num" style={{fontSize: 18, width: 30, color: s.on ? "var(--accent)" : "var(--ink-2)"}}>{s.r}</span>
            <span className="hand" style={{flex: 1, fontSize: s.on ? 17 : 14}}>{s.a}</span>
            {s.done && <span className="small">✓</span>}
          </div>
        ))}
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent" style={{fontSize: 24, padding: "22px 20px"}}>Finished · Next →</div>
        <div className="small" style={{textAlign:"center", marginTop: 6}}>one tap per group · no rep counting</div>
      </div>
    </ModePhone>
  );
}

// Intervals, Tabata, Continuous, Custom, Rest — unchanged conceptually, RIR polish only
function Intervals() {
  return (
    <ModePhone mode="INTERVALS · 5 × 3:00 / 1:30">
      <div style={{padding: "0 16px 4px"}}><div className="submeta" style={{padding: 0}}>Interval 3 of 5 · WORK</div></div>
      <Ring pct={0.4} t="1:48" s="work"/>
      <div style={{textAlign: "center"}}>
        <div className="hand" style={{fontSize: 18}}>Target pace 6:40 /mi</div>
        <div className="tiny">then 1:30 easy · auto-advances</div>
      </div>
      <div className="divider dashed"/>
      <div style={{padding: "4px 16px"}}>
        <div className="set-row head"><span>#</span><span>time</span><span>dist</span><span>HR</span><span/></div>
        <div className="set-row done"><span className="num-cell">1</span><span>3:00</span><span>0.45mi</span><span>164</span><span className="check"/></div>
        <div className="set-row done"><span className="num-cell">2</span><span>3:00</span><span>0.44mi</span><span>171</span><span className="check"/></div>
        <div className="set-row current"><span className="num-cell">3</span><span>1:12</span><span>0.18</span><span>168</span><span className="check">—</span></div>
      </div>
    </ModePhone>
  );
}

function Tabata() {
  return (
    <ModePhone mode="TABATA · 8 × :20/:10">
      <div style={{padding: "12px 16px 0", textAlign: "center"}}>
        <div className="tiny">REST</div>
        <div className="megareps" style={{color: "var(--accent)"}}>0:07</div>
        <div className="tiny" style={{marginTop: 6}}>round 4 of 8 · auto</div>
      </div>
      <div style={{padding: "12px 16px"}}>
        <div style={{display: "flex", gap: 4}}>
          {[1,2,3,4,5,6,7,8].map(i => (
            <div key={i} style={{
              flex: 1, height: 28, borderRadius: 4, border: "1px solid var(--ink-4)",
              background: i < 4 ? "var(--accent)" : i === 4 ? "var(--ink-4)" : "transparent",
            }}/>
          ))}
        </div>
        <div className="small hand" style={{textAlign: "center", marginTop: 8}}>Burpees</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="small" style={{textAlign: "center"}}>watch buzzes at every transition</div>
      </div>
    </ModePhone>
  );
}

function Continuous() {
  return (
    <ModePhone mode="CONTINUOUS · Z2 ride">
      <div style={{padding: "12px 16px 0"}}>
        <div className="tiny">ELAPSED</div>
        <div className="big-num" style={{fontSize: 48}}>42:18</div>
        <div className="small">of 60:00 target</div>
      </div>
      <div style={{padding: "12px 16px"}}>
        <div style={{display:"flex", justifyContent:"space-between", padding:"6px 0", borderBottom:"1px dashed var(--ink-4)"}}>
          <span className="tiny">avg HR</span><span className="big-num" style={{fontSize: 18}}>138</span>
        </div>
        <div style={{display:"flex", justifyContent:"space-between", padding:"6px 0", borderBottom:"1px dashed var(--ink-4)"}}>
          <span className="tiny">zone</span><span className="hand">Z2 · 128–148</span>
        </div>
        <div style={{display:"flex", justifyContent:"space-between", padding:"6px 0"}}>
          <span className="tiny">distance</span><span className="big-num" style={{fontSize: 18}}>12.4 mi</span>
        </div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px", display:"flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Pause</div>
        <div className="btn accent" style={{flex: 1}}>End</div>
      </div>
    </ModePhone>
  );
}

function Custom() {
  return (
    <ModePhone mode="CUSTOM · 4 segments">
      <div style={{padding: "0 16px 4px"}}><div className="submeta" style={{padding: 0}}>Segment 2 of 4</div></div>
      <div style={{padding: "0 16px"}}>
        {[
          {n: "Warmup spin", d: ":10:00", done: true},
          {n: "3 × 5 @ Z4 /2 easy", d: ":25:00", on: true},
          {n: "Tempo :15:00", d: ":15:00"},
          {n: "Cooldown", d: ":10:00"},
        ].map((s, i) => (
          <div key={i} style={{
            display: "flex", gap: 10, padding: "8px 10px", margin: "4px 0",
            border: s.on ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
            borderRadius: 8, alignItems: "center", opacity: s.done ? 0.45 : 1,
          }}>
            <span className="tiny" style={{width: 14}}>{s.done ? "✓" : i+1}</span>
            <div style={{flex: 1}}>
              <div className="hand" style={{fontSize: s.on ? 16 : 14}}>{s.n}</div>
              <div className="small">{s.d}</div>
            </div>
          </div>
        ))}
      </div>
      <div style={{padding: "4px 16px"}}><Ring pct={0.25} t="6:08" s="in segment"/></div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Next segment →</div>
      </div>
    </ModePhone>
  );
}

function RestBlock() {
  return (
    <ModePhone mode="REST BLOCK · 3:00">
      <div style={{textAlign: "center", padding: "20px 16px 0"}}>
        <div className="megareps" style={{fontSize: 110, color: "var(--accent)"}}>2:14</div>
        <div className="tiny">between blocks</div>
      </div>
      <div style={{padding: "16px 16px 0"}}>
        <div className="tiny" style={{marginBottom: 4}}>Up next</div>
        <div className="hand" style={{fontSize: 20}}>Block 3 · Accessory superset</div>
        <div className="small">DB Row + Face Pull · 3 rounds</div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Start early</div>
      </div>
    </ModePhone>
  );
}

function ModesSection() {
  const items = [
    { num: "2.1", name: "Superset · NEXT only", tag: "No mid-set logging. Just advance.", pros: ["One button = one action","Logging deferred to rest"], cons: ["Assumes discipline to fill out rest logs"], cmp: <Superset/> },
    { num: "2.2", name: "Circuit · NEXT station", tag: "Tap through stations; confirm at rest.", pros: ["Same pattern as superset","Any station count"], cons: [], cmp: <Circuit/> },
    { num: "2.3", name: "EMOM", tag: "Per-minute ring. Edit history from rest.", pros: ["Pace signal is finish-time","Logs populated on auto-advance"], cons: ["Haptic required"], cmp: <Emom/> },
    { num: "2.4", name: "AMRAP · +1 only", tag: "One giant button. Partials captured at end.", pros: ["No counting under fatigue","Partials only asked once"], cons: ["Rounds w/ heavy loads still need a rep counter"], cmp: <Amrap/> },
    { num: "2.4b", name: "AMRAP · end-of-round picker", tag: "Timer hits zero → pick how far into the next round.", pros: ["Catches 'I started round 5'","+ missed round escape hatch"], cons: [], cmp: <AmrapEnd/> },
    { num: "2.5", name: "For Time · big NEXT", tag: "Finish a group → one tap. No per-rep counting.", pros: ["Matches how chippers actually feel","Minimal under-fatigue friction"], cons: ["Can't see split-per-rep — fine per brief"], cmp: <ForTime/> },
    { num: "2.6", name: "Intervals", tag: "Work / rest auto-advances. HR logged.", pros: ["Zero-input after start"], cons: [], cmp: <Intervals/> },
    { num: "2.7", name: "Tabata", tag: "Auto-advance across 8 rounds.", pros: ["Watch-only possible","8 pips = total glance"], cons: [], cmp: <Tabata/> },
    { num: "2.8", name: "Continuous", tag: "Ambient HR + zone + dist.", pros: ["Long-session friendly"], cons: [], cmp: <Continuous/> },
    { num: "2.9", name: "Custom · Next segment", tag: "Named segments, one tap to advance.", pros: ["Catch-all with familiar controls"], cons: [], cmp: <Custom/> },
    { num: "2.10", name: "Rest block", tag: "Countdown between blocks. Start-early.", pros: [], cons: [], cmp: <RestBlock/> },
  ];

  return (
    <Section
      title="2. Timing modes · progression-first"
      kicker="one big NEXT · log on rest"
      intro="Under fatigue, only one decision: advance. Supersets/circuits/for-time all collapse to a single giant NEXT button. Logging (RIR, reps, load) is deferred until rest or completion. AMRAP advances station-by-station; the finish picker captures only the partial station reached when the clock hits zero."
    >
      <div className="row">
        {items.map(it => (
          <Variant key={it.num} num={it.num} name={it.name} tagline={it.tag}
            notes={<Notes pros={it.pros} cons={it.cons}/>}>{it.cmp}</Variant>
        ))}
      </div>
    </Section>
  );
}

Object.assign(window, { ModesSection });
