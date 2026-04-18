// v2 · rest/swap/complete
// Rest = inline pill winner; edit last set on rest. Swap = longpress winner + sheet alt.
// Completion: tap any group, voice note, editable RIR.

// ─── REST ───────────────────────────────────────────────
function RestInline() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>

      <div style={{
        margin: "10px 16px", padding: "10px 14px",
        border: "1.5px solid var(--accent)", borderRadius: 100,
        display:"flex", justifyContent:"space-between", alignItems: "center",
      }}>
        <span className="tiny" style={{color: "var(--accent)"}}>REST</span>
        <span className="big-num" style={{fontSize: 22}}>1:24</span>
        <span className="tiny">of 2:00</span>
      </div>

      <div style={{padding: "6px 16px"}}>
        <div className="tiny">just did · tap to edit</div>
      </div>
      <div className="set-row done" style={{background:"var(--paper-2)", borderRadius: 6, margin: "0 16px", padding: "9px 10px"}}>
        <span className="num-cell">3</span>
        <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>225</span>
        <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>5</span>
        <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>2 RIR</span>
        <span className="check" style={{color:"var(--accent)"}}>✎</span>
      </div>

      <div style={{padding: "10px 16px 6px"}}>
        <div className="tiny">next set</div>
        <div className="hand" style={{fontSize: 24}}>225 × 5 · target 2 RIR</div>
      </div>

      <div className="set-row head"><span>#</span><span>load</span><span>reps</span><span>RIR</span><span/></div>
      <div className="set-row done"><span className="num-cell">1</span><span>225</span><span>5</span><span>3</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">2</span><span>225</span><span>5</span><span>2</span><span className="check"/></div>

      <div style={{marginTop:"auto", padding:"0 16px 10px"}}>
        <div className="btn accent">Start set 4 now</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function RestCatchup() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{margin: "10px 16px", padding: "10px 14px", border: "1.5px solid var(--accent)", borderRadius: 100,
        display:"flex", justifyContent:"space-between", alignItems: "center"}}>
        <span className="tiny" style={{color: "var(--accent)"}}>REST</span>
        <span className="big-num" style={{fontSize: 22}}>1:24</span>
        <span className="tiny">of 2:00</span>
      </div>

      <div style={{margin: "8px 16px", padding: "10px 12px", border: "1.5px solid var(--ink)", borderRadius: 10}}>
        <div className="tiny" style={{color: "var(--accent)"}}>GAP DETECTED · 9 MIN</div>
        <div className="small" style={{marginTop: 4}}>Looks like you did a couple sets without logging. Fill in what you remember:</div>
        <div style={{display:"grid", gridTemplateColumns:"auto 1fr 1fr 1fr", gap: 6, marginTop: 8, alignItems:"center"}}>
          <span className="tiny">Set 2</span>
          <div className="pill" style={{textAlign:"center"}}>225</div>
          <div className="pill" style={{textAlign:"center"}}>5</div>
          <div className="pill accent" style={{textAlign:"center"}}>2 RIR</div>
          <span className="tiny">Set 3</span>
          <div className="pill" style={{textAlign:"center"}}>225</div>
          <div className="pill" style={{textAlign:"center"}}>5</div>
          <div className="pill accent" style={{textAlign:"center"}}>2 RIR</div>
        </div>
        <div className="small" style={{marginTop: 8, textAlign:"center", color:"var(--accent)"}}>+ add another</div>
      </div>

      <div style={{marginTop:"auto", padding:"0 16px 10px", display:"flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Skip</div>
        <div className="btn accent" style={{flex: 2}}>Log & continue</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function RestSection() {
  return (
    <Section
      title="3. Rest is the logging moment"
      kicker="inline pill · edit last set · catch-up"
      intro="You picked inline pill — keeping the ledger visible while the timer counts. The just-completed set is always one tap away to edit. The catch-up variant handles 'I forgot to log' inline, no modal."
    >
      <div className="row">
        <Variant num="3.A" name="Inline pill · editable last set" tagline="Timer is a pill, last set highlighted + editable, next set preview below."
          notes={<Notes pros={["Log and rest in one screen","Edit RIR/reps/load without leaving","Context for next set is visible"]} cons={["Needs reliable haptic for rest-end"]}/>}>
          <RestInline/>
        </Variant>
        <Variant num="3.B" name="Rest + catch-up inline" tagline="Same screen, but a missing-gap card appears when timestamps don't line up."
          notes={<Notes pros={["Never blocks forward progress","Inline, not a modal","Dismissable"]} cons={["Heuristic must be conservative"]}/>}>
          <RestCatchup/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── SWAP ─────────────────────────────────────────────────
function SwapLongpress() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{margin: "10px 16px", padding: 14, border: "1.5px solid var(--accent)", borderRadius: 12,
        boxShadow: "0 0 0 3px var(--accent-soft)"}}>
        <div className="hand" style={{fontSize: 20}}>Back Squat</div>
        <div className="small">hold → swap</div>
      </div>
      <div style={{margin: "18px 16px 0", border: "1.5px solid var(--ink)", borderRadius: 14, padding: 12, background: "var(--paper)"}}>
        <div className="tiny" style={{marginBottom: 6}}>Swap to…</div>
        {["Front Squat", "Safety Bar Squat", "Goblet Squat", "Keep Back Squat"].map((n, i) => (
          <div key={n} style={{padding: "10px 6px", borderTop: i ? "1px dashed var(--ink-4)" : "none",
            display: "flex", justifyContent: "space-between"}}>
            <span className="hand">{n}</span>
            <span className="small">{i === 3 ? "cancel" : "→"}</span>
          </div>
        ))}
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function SwapSheet() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat" right="swap"/>
      <div style={{opacity: 0.3, padding: "0 16px"}}>
        <div className="exname">Back Squat</div>
        <div className="submeta">Set 3 of 5</div>
        <Ring pct={0.48} t="1:24" s="Rest"/>
      </div>
      <div style={{marginTop: "auto", border: "1.5px solid var(--ink)", borderRadius: "20px 20px 0 0",
        padding: "12px 0 10px", background: "var(--paper)"}}>
        <div style={{width: 40, height: 4, background: "var(--ink-4)", borderRadius: 2, margin: "0 auto 10px"}}/>
        <div style={{padding: "0 16px 8px"}}>
          <div className="hand" style={{fontSize: 18}}>Alternatives</div>
          <div className="small">preserves sets × reps × RIR target</div>
        </div>
        {["Front Squat", "Safety Bar Squat", "Goblet Squat"].map((n, i) => (
          <div key={n} style={{display:"flex", justifyContent:"space-between", alignItems:"center",
            padding: "10px 16px", borderTop: "1px dashed var(--ink-4)"}}>
            <span className="hand" style={{fontSize: 15}}>{n}</span>
            <span className="tiny">last 12d</span>
          </div>
        ))}
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function SwapSection() {
  return (
    <Section
      title="4. Swap · longpress (+ sheet alt)"
      kicker="both patterns are fine"
      intro="Longpress is the pick. Sheet kept as a fallback for discoverability on first use — a small hint 'hold to swap' can appear on day 1."
    >
      <div className="row">
        <Variant num="4.A" name="Longpress menu" tagline="Hold the exercise card → menu with pre-picked alts."
          notes={<Notes pros={["Zero chrome","Fast once learned","Preserves prescription"]} cons={["Needs a one-time hint"]}/>}>
          <SwapLongpress/>
        </Variant>
        <Variant num="4.B" name="Sheet alt" tagline="Explicit swap action in nav bar → half-sheet chooser."
          notes={<Notes pros={["Discoverable","Room for metadata"]} cons={["Takes a nav-bar tap target"]}/>}>
          <SwapSheet/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── COMPLETION ───────────────────────────────────────────
function CompleteReviewRIR() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="Review & close"/>
      <div style={{padding: "0 16px"}}>
        <div className="hand" style={{fontSize: 24}}>Upper A · Push</div>
        <div className="submeta" style={{padding: 0}}>48:22 · 12 exercises · 42 sets</div>
      </div>
      <div className="small" style={{padding: "6px 16px"}}>tap any group to edit</div>
      {[
        {n: "Back Squat", sets: "225×5 (3), 225×5 (2), 225×5 (2), 225×5 (1), 225×4 (0)", avg: "2"},
        {n: "Romanian DL", sets: "185×8 (3), 185×8 (2), 185×8 (2), 185×8 (1)", avg: "2"},
        {n: "Bulgarian Split", sets: "40×10 (2), 40×10 (1), 40×9 (0)", avg: "1", warn: true},
        {n: "Leg Curl", sets: "70×12 (3), 70×12 (2), 70×11 (1)", avg: "2"},
      ].map(x => (
        <div key={x.n} style={{
          display: "flex", alignItems:"center", gap: 8,
          padding: "10px 16px", borderTop: "1px dashed var(--ink-4)",
        }}>
          <div style={{flex: 1}}>
            <div className="hand" style={{fontSize: 15}}>{x.n}</div>
            <div className="small" style={{fontFamily:"var(--mono)", fontSize: 10}}>{x.sets}</div>
          </div>
          <div style={{textAlign: "right"}}>
            <div className="tiny">avg RIR</div>
            <div className="big-num" style={{fontSize: 16}}>{x.avg}</div>
          </div>
          <span className="tiny">{x.warn ? "⚠︎" : "›"}</span>
        </div>
      ))}

      <div style={{margin: "10px 16px", padding: "10px 12px", border: "1px dashed var(--ink-4)", borderRadius: 10}}>
        <div style={{display:"flex", justifyContent:"space-between", alignItems:"center"}}>
          <div className="tiny">notes</div>
          <div style={{
            width: 32, height: 32, borderRadius: "50%",
            border:"1.5px solid var(--accent)",
            display:"flex", alignItems:"center", justifyContent:"center",
            color:"var(--accent)", fontFamily:"var(--mono)", fontSize: 14,
          }}>🎤</div>
        </div>
        <div className="hand" style={{fontSize: 14, marginTop: 6, color:"var(--ink-2)"}}>
          tap mic to dictate · or type
        </div>
      </div>

      <div style={{marginTop: "auto", padding: "0 16px 10px", display: "flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Later</div>
        <div className="btn accent" style={{flex: 2}}>Close out</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function CompleteGroupEdit() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="Bulgarian Split" right="done"/>
      <div style={{padding: "0 16px 4px"}}>
        <div className="submeta" style={{padding: 0}}>3 × 10 @ 40 · all sets editable</div>
      </div>

      <div className="set-row head" style={{marginTop: 8}}><span>#</span><span>load</span><span>reps</span><span>RIR</span><span/></div>
      {[
        {n: 1, l: "40", r: "10", rir: "2"},
        {n: 2, l: "40", r: "10", rir: "1"},
        {n: 3, l: "40", r: "9", rir: "0", warn: true},
      ].map(s => (
        <div key={s.n} className="set-row" style={{background: "var(--paper-2)", margin: "3px 16px", padding: "8px 10px", borderRadius: 6}}>
          <span className="num-cell">{s.n}</span>
          <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>{s.l}</span>
          <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>{s.r}</span>
          <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>{s.rir}</span>
          <span className="check" style={{color: s.warn ? "var(--accent)" : "var(--ink-3)"}}>{s.warn ? "⚠︎" : "✎"}</span>
        </div>
      ))}

      <div style={{padding: "10px 16px"}}>
        <div className="btn ghost" style={{fontSize: 13}}>+ add a set I forgot</div>
      </div>

      <div style={{padding: "6px 16px"}}>
        <div className="tiny">note for this exercise</div>
        <div style={{border:"1px dashed var(--ink-4)", borderRadius: 8, padding: 10, marginTop: 4, minHeight: 50}}>
          <div className="hand" style={{fontSize: 13, color:"var(--ink-2)"}}>left side felt shaky on set 3</div>
        </div>
      </div>

      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Save</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function CompletionSection() {
  return (
    <Section
      title="5. Completion · ledger with voice note"
      kicker="tap any group · edit anything · 🎤"
      intro="The completion flow is the second place logs solidify (the first is rest). It's a ledger summary: every exercise visible, any group tappable to edit (loads / reps / RIR), voice dictation on the workout-level note, and an escape hatch to add a set you forgot."
    >
      <div className="row">
        <Variant num="5.A" name="Ledger summary + voice note" tagline="Review everything; mic on the note field; avg RIR per exercise."
          notes={<Notes pros={["All signals tracked are editable","Voice > typing post-workout","Warning flags on sub-target RIR"]} cons={["Long workouts = long scroll"]}/>}>
          <CompleteReviewRIR/>
        </Variant>
        <Variant num="5.B" name="Group editor" tagline="Tap an exercise → every set editable, per-exercise note."
          notes={<Notes pros={["Exact depth when you need it","Add-a-forgotten-set inline"]} cons={["Drill-down adds a tap"]}/>}>
          <CompleteGroupEdit/>
        </Variant>
      </div>
    </Section>
  );
}

Object.assign(window, { RestSection, SwapSection, CompletionSection });
