// v2 · straight_sets — RIR not RPE · edit-last-set inline · catch-up flow

function StraightA() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Block 2 of 4"/>
      <div className="exname">Back Squat</div>
      <div className="submeta">Set 3 of 5 · Strength</div>

      <Ring pct={0.48} t="1:24" s="Rest"/>

      {/* Edit-last-set right on the rest screen */}
      <div style={{margin: "6px 16px", padding: "8px 12px", border: "1.5px solid var(--ink)", borderRadius: 10, background: "var(--paper-2)"}}>
        <div className="tiny" style={{marginBottom: 4}}>Just did · tap to edit</div>
        <div style={{display: "flex", gap: 8, alignItems: "center"}}>
          <span className="pill" style={{flex: 1}}>225 lb</span>
          <span className="pill" style={{flex: 1}}>5 reps</span>
          <span className="pill accent" style={{flex: 1}}>2 RIR</span>
        </div>
      </div>

      <div style={{padding: "8px 16px", textAlign: "center"}}>
        <div className="small hand" style={{fontSize: 15, color:"var(--ink)"}}>Next: <b>225 × 5</b> · target 2 RIR</div>
      </div>

      <LastTime summary="220×5 @ 2 RIR  ·  4d ago"/>

      <div style={{padding: "0 16px", marginTop: "auto", display:"flex", gap: 8}}>
        <div className="btn ghost" style={{flex: 1}}>+0:30</div>
        <div className="btn accent" style={{flex: 2}}>Start set 3</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function StraightB() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{padding: "0 16px"}}>
        <div className="submeta" style={{padding: 0, marginBottom: 6}}>Strength · 5×5 @ 225 · target 2 RIR</div>
      </div>

      <div style={{padding: "0 16px", display:"flex", justifyContent:"space-between", alignItems:"baseline"}}>
        <div><div className="tiny">Rest</div><div className="big-num" style={{fontSize: 34, lineHeight: 1}}>1:24</div></div>
        <div style={{textAlign:"right"}}><div className="tiny">Next</div><div className="hand" style={{fontSize: 18}}>225 × 5</div></div>
      </div>

      <div className="divider dashed"/>

      <div className="set-row head">
        <span>#</span><span>Load</span><span>Reps</span><span>RIR</span><span/>
      </div>
      <div className="set-row done"><span className="num-cell">1</span><span>225</span><span>5</span><span>3</span><span className="check"/></div>
      {/* last set inline-editable */}
      <div className="set-row done" style={{background:"var(--paper-2)", borderRadius: 6, margin: "0 8px", padding: "7px 8px"}}>
        <span className="num-cell">2</span>
        <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>225</span>
        <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>5</span>
        <span style={{border:"1px dashed var(--ink-3)", padding:"1px 4px", borderRadius: 3}}>2</span>
        <span className="check" style={{color:"var(--accent)"}}>✎</span>
      </div>
      <div className="set-row current"><span className="num-cell">3</span><span>225</span><span>5</span><span>2</span><span className="check">—</span></div>
      <div className="set-row"><span>4</span><span>225</span><span>5</span><span>2</span><span/></div>
      <div className="set-row"><span>5</span><span>225</span><span>5</span><span>1</span><span/></div>

      <LastTime summary="220×5,5,5,4,4 · 3→0 RIR · 4d"/>

      <div style={{padding: "8px 16px 0", display:"flex", gap: 8}}>
        <div className="btn ghost" style={{flex: 1}}>Skip rest</div>
        <div className="btn primary" style={{flex: 2}}>Start set 3</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

// NEW: catch-up variant — "I forgot to log 2 sets"
function StraightCatchup() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{padding: "0 16px"}}>
        <div className="submeta" style={{padding: 0}}>Forgot to log? Fill what you did.</div>
      </div>

      <div style={{margin: "10px 16px", padding: "10px 12px", border: "1.5px solid var(--accent)", borderRadius: 10, background: "var(--accent-soft)"}}>
        <div className="tiny" style={{color: "var(--accent)"}}>CATCH-UP · inferred from timestamps</div>
        <div className="small" style={{marginTop: 4}}>Looks like you did sets 2 & 3 ~9 min ago.</div>
      </div>

      {[
        {n: 2, pre: "225 × 5", rir: 2},
        {n: 3, pre: "225 × 5", rir: 2},
      ].map(s => (
        <div key={s.n} style={{margin: "6px 16px", padding: "10px 12px", border: "1px dashed var(--ink-4)", borderRadius: 8}}>
          <div className="tiny">Set {s.n} · prescribed {s.pre}</div>
          <div style={{display:"flex", gap: 6, marginTop: 6}}>
            <div className="pill" style={{flex: 1, textAlign:"center"}}>225</div>
            <div className="pill" style={{flex: 1, textAlign:"center"}}>5</div>
            <div className="pill accent" style={{flex: 1, textAlign:"center"}}>{s.rir} RIR</div>
          </div>
        </div>
      ))}

      <div style={{padding: "0 16px"}}>
        <div className="small" style={{textAlign:"center", marginTop: 6}}>or</div>
      </div>
      <div style={{padding: "6px 16px"}}>
        <div className="btn ghost" style={{fontSize: 14}}>+ add another set</div>
      </div>

      <div style={{marginTop: "auto", padding: "0 16px 10px", display:"flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Dismiss</div>
        <div className="btn accent" style={{flex: 2}}>Log & continue</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function StraightSetsSection() {
  return (
    <Section
      title="1. straight_sets · rest-is-the-log"
      kicker="canonical screen · RIR-based"
      intro="Rest is the only logging moment. The just-completed set is always editable at a glance. A catch-up flow handles 'I forgot to start/stop' without forcing a split-timer UI."
    >
      <div className="row">
        <Variant num="1.A" name="Glance ring + editable just-did" tagline="Timer is hero. Last set is a pill row you can tap."
          notes={<Notes pros={["Edit the last set without leaving the screen","RIR pill is the primary data to confirm","Glanceable under the bar"]} cons={["Editing 3+ back sets needs the ledger variant"]}/>}>
          <StraightA/>
        </Variant>
        <Variant num="1.B" name="Inline-editable ledger" tagline="Previous set is highlighted and editable in place."
          notes={<Notes pros={["See pattern across sets","Any row tappable to fix"]} cons={["Denser screen","Timer demoted"]}/>}>
          <StraightB/>
        </Variant>
        <Variant num="1.C" name="Catch-up" tagline="Forgot to start/stop? App infers from timestamps and asks."
          notes={<Notes pros={["Unblocks you fast — 2 taps to reconcile","No split-timer complexity","Defaults are prescribed values"]} cons={["Requires timestamp heuristic","Dismissable if wrong"]}/>}>
          <StraightCatchup/>
        </Variant>
      </div>
    </Section>
  );
}

Object.assign(window, { StraightSetsSection });
