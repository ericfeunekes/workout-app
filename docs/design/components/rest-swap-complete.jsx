// Section 3 — Rest/transition + Alternatives + Completion + Watch + First-run + Prescription shapes

// ─── REST / TRANSITION ──────────────────────────────────────
function RestBig() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Resting" right="+0:30"/>
      <div style={{marginTop: 20}}>
        <div style={{textAlign: "center"}}>
          <div className="megareps" style={{fontSize: 130, color: "var(--accent)"}}>1:24</div>
          <div className="tiny">of 2:00 prescribed</div>
        </div>
      </div>
      <div style={{padding: "20px 16px 0"}}>
        <div className="tiny">up next</div>
        <div className="hand" style={{fontSize: 22}}>Back Squat · Set 4</div>
        <div className="small">225 × 5 · RPE 8</div>
      </div>
      <div style={{marginTop:"auto", padding:"0 16px 10px", display: "flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>+0:30</div>
        <div className="btn accent" style={{flex: 2}}>Skip · Start set 4</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function RestInline() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{
        margin: "10px 16px", padding: "8px 14px",
        border: "1.5px solid var(--accent)", borderRadius: 100,
        display:"flex", justifyContent:"space-between", alignItems: "center",
      }}>
        <span className="tiny" style={{color: "var(--accent)"}}>REST</span>
        <span className="big-num" style={{fontSize: 22}}>1:24</span>
        <span className="tiny">of 2:00</span>
      </div>

      <div style={{padding: "6px 16px"}}>
        <div className="tiny">next set</div>
        <div className="hand" style={{fontSize: 28}}>225 × 5</div>
      </div>

      <div className="set-row head"><span>#</span><span>load</span><span>reps</span><span>RPE</span><span/></div>
      <div className="set-row done"><span className="num-cell">1</span><span>225</span><span>5</span><span>7</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">2</span><span>225</span><span>5</span><span>7.5</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">3</span><span>225</span><span>5</span><span>8</span><span className="check"/></div>
      <div className="set-row current"><span className="num-cell">4</span><span>225</span><span>5</span><span>8</span><span className="check">—</span></div>

      <div style={{marginTop:"auto", padding:"0 16px 10px"}}>
        <div className="btn accent">Start set 4 now</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function RestAmbient() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="" right=""/>
      <div style={{flex: 1, display:"flex", flexDirection:"column", justifyContent:"center", alignItems:"center"}}>
        <svg viewBox="0 0 200 200" style={{width: 230, height: 230}}>
          <circle cx="100" cy="100" r="88" fill="none" stroke="var(--ink-4)" strokeWidth="2"/>
          <circle cx="100" cy="100" r="88" fill="none" stroke="var(--accent)" strokeWidth="6"
            strokeDasharray="270 550" strokeDashoffset="138" strokeLinecap="round"
            transform="rotate(-90 100 100)"/>
          <text x="100" y="96" textAnchor="middle" fontFamily="var(--mono)" fontSize="42" fill="var(--ink)">1:24</text>
          <text x="100" y="118" textAnchor="middle" fontFamily="var(--mono)" fontSize="9" fill="var(--ink-2)" letterSpacing="2">REST</text>
        </svg>
        <div className="hand" style={{fontSize: 18, marginTop: 12}}>Back Squat · Set 4 coming</div>
      </div>
      <div style={{padding: "0 16px 14px"}}>
        <div className="small" style={{textAlign: "center"}}>tap anywhere to skip rest</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function RestSection() {
  return (
    <Section
      title="3. Rest / transition screens"
      kicker="between sets · between blocks"
      intro="Rest is the glance-heaviest moment. The user asked for rest timer to be the biggest thing when resting, so the tradeoff is how much context to keep visible behind it."
    >
      <div className="row">
        <Variant num="3.A" name="Takeover" tagline="Timer eats the screen. Everything else demoted."
          notes={<Notes pros={["Readable across the gym", "Auto-dismiss when zero"]}
            cons={["Context (set history) hidden", "Might feel jumpy if auto-shown between every set"]}/>}>
          <RestBig/>
        </Variant>
        <Variant num="3.B" name="Inline pill" tagline="Set screen stays, timer is a pill at top."
          notes={<Notes pros={["No context switch", "Ledger + timer coexist"]}
            cons={["Smaller timer", "Relies on haptic to signal zero"]}/>}>
          <RestInline/>
        </Variant>
        <Variant num="3.C" name="Ambient ring" tagline="Big ring, no chrome. Tap-anywhere to skip."
          notes={<Notes pros={["Zero-UI vibe", "Massive hit-target"]}
            cons={["Discovery of 'tap anywhere'", "Loses ledger entirely"]}/>}>
          <RestAmbient/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── ALTERNATIVES / SWAP ────────────────────────────────────
function SwapSwipe() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{position:"relative", margin: "10px 16px"}}>
        <div style={{
          border: "1.5px solid var(--ink)", borderRadius: 12, padding: 14,
          transform: "translateX(-40px)", background: "var(--paper)",
          position: "relative", zIndex: 2,
        }}>
          <div className="hand" style={{fontSize: 20}}>Back Squat</div>
          <div className="small">225 × 5 · RPE 8</div>
        </div>
        <div style={{
          position: "absolute", right: 0, top: 0, bottom: 0,
          width: 60, display: "flex", alignItems: "center", justifyContent: "center",
          background: "var(--accent)", color: "#fff", borderRadius: 12,
          fontFamily: "var(--hand)", fontSize: 14,
        }}>
          swap →
        </div>
      </div>

      <div style={{padding:"0 16px"}}>
        <div className="tiny">alternatives (pre-picked)</div>
      </div>
      {["Front Squat", "Safety Bar Squat", "Goblet Squat"].map(n => (
        <div key={n} style={{margin: "6px 16px", padding: "10px 12px", border: "1px dashed var(--ink-4)", borderRadius: 8}}>
          <div className="hand" style={{fontSize: 16}}>{n}</div>
          <div className="small">same prescription</div>
        </div>
      ))}
      <TabBar active="Workout"/>
    </Phone>
  );
}

function SwapLongpress() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{
        margin: "10px 16px", padding: 14,
        border: "1.5px solid var(--accent)", borderRadius: 12,
        boxShadow: "0 0 0 3px var(--accent-soft)",
      }}>
        <div className="hand" style={{fontSize: 20}}>Back Squat</div>
        <div className="small">hold to see alternatives</div>
      </div>

      <div style={{
        margin: "18px 16px 0", border: "1.5px solid var(--ink)", borderRadius: 14,
        padding: 12, background: "var(--paper)",
      }}>
        <div className="tiny" style={{marginBottom: 6}}>Swap to…</div>
        {["Front Squat", "Safety Bar Squat", "Goblet Squat", "Keep Back Squat"].map((n, i) => (
          <div key={n} style={{
            padding: "10px 6px",
            borderTop: i ? "1px dashed var(--ink-4)" : "none",
            display: "flex", justifyContent: "space-between",
          }}>
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

      <div style={{
        marginTop: "auto",
        border: "1.5px solid var(--ink)",
        borderRadius: "20px 20px 0 0",
        padding: "12px 0 10px",
        background: "var(--paper)",
      }}>
        <div style={{width: 40, height: 4, background: "var(--ink-4)", borderRadius: 2, margin: "0 auto 10px"}}/>
        <div style={{padding: "0 16px 8px"}}>
          <div className="hand" style={{fontSize: 18}}>Alternatives</div>
          <div className="small">preserves sets × reps × RPE</div>
        </div>
        {["Front Squat", "Safety Bar Squat", "Goblet Squat"].map((n, i) => (
          <div key={n} style={{
            display:"flex", justifyContent:"space-between", alignItems:"center",
            padding: "10px 16px", borderTop: "1px dashed var(--ink-4)",
          }}>
            <span className="hand" style={{fontSize: 15}}>{n}</span>
            <span className="tiny">last 12d</span>
          </div>
        ))}
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function SwapStack() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title=""/>
      <div style={{padding: "0 16px", textAlign:"center"}}>
        <div className="tiny">exercise 4 of 8</div>
      </div>
      {/* stack of cards */}
      <div style={{position: "relative", height: 260, margin: "20px 24px 0"}}>
        {[2, 1, 0].map(i => (
          <div key={i} style={{
            position: "absolute", inset: 0,
            transform: `translateY(${i * -10}px) scale(${1 - i * 0.05})`,
            border: i === 0 ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
            borderRadius: 14, padding: 20, background: "var(--paper)",
            zIndex: 3 - i, opacity: i === 0 ? 1 : 0.5,
          }}>
            <div className="tiny">{["current", "alt", "alt"][i]}</div>
            <div className="hand" style={{fontSize: 24, marginTop: 6}}>
              {["Back Squat", "Front Squat", "Safety Bar"][i]}
            </div>
            <div className="small" style={{marginTop: 6}}>225 × 5 · RPE 8</div>
          </div>
        ))}
      </div>
      <div style={{padding: "24px 16px 0", textAlign:"center"}}>
        <div className="hand" style={{fontSize: 14, color: "var(--ink-2)"}}>
          ← swipe to swap · tap to keep
        </div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function SwapSection() {
  return (
    <Section
      title="4. Alternatives / swap gesture"
      kicker="4 gestures, same backing data"
      intro="Swaps are pre-picked in the workout JSON — UI is just a chooser. All four options preserve the current prescription; pick based on how mid-set-friendly the gesture is."
    >
      <div className="row">
        <Variant num="4.A" name="Swipe reveal" tagline="Swipe exercise card left to reveal a swap action."
          notes={<Notes pros={["Familiar pattern", "One-handed"]}
            cons={["Hidden affordance on first run", "Accidental swipes"]}/>}>
          <SwapSwipe/>
        </Variant>
        <Variant num="4.B" name="Long-press menu" tagline="Hold the exercise → menu of alts."
          notes={<Notes pros={["Zero chrome — keeps screen clean", "Clear intent"]}
            cons={["Slow gesture (300ms+)", "Also hidden at first"]}/>}>
          <SwapLongpress/>
        </Variant>
        <Variant num="4.C" name="Bottom sheet" tagline="Explicit swap button in nav → half-sheet chooser."
          notes={<Notes pros={["Most discoverable", "Room for metadata"]}
            cons={["Takes a tap target up top", "Feels heavier"]}/>}>
          <SwapSheet/>
        </Variant>
        <Variant num="4.D" name="Stack" tagline="Exercise is a card stack; swipe through alts Tinder-style."
          notes={<Notes pros={["Delightful, discoverable via animation", "All alts in peripheral view"]}
            cons={["Overkill when there are no alts", "Careful with accidental swipes mid-set"]}/>}>
          <SwapStack/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── COMPLETION FLOW ────────────────────────────────────────
function CompleteSummary() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Workout done" right=""/>
      <div style={{padding: "0 16px"}}>
        <div className="hand" style={{fontSize: 28}}>Upper A · Push</div>
        <div className="submeta" style={{padding: 0, marginTop: 4}}>48:22 · 12 exercises · 42 sets</div>
      </div>
      <div style={{margin: "10px 16px", padding: 12, border: "1px dashed var(--ink-4)", borderRadius: 10}}>
        <div className="tiny">notes for next time</div>
        <div style={{height: 64, marginTop: 6, borderTop: "1px solid var(--ink-4)"}}/>
      </div>
      <div style={{padding: "0 16px"}}>
        <div className="tiny">overall RPE</div>
        <div style={{display: "flex", gap: 4, marginTop: 6}}>
          {[6,7,8,9,10].map(n => (
            <div key={n} style={{
              flex: 1, padding: "10px 0", textAlign: "center",
              border: n === 8 ? "1.5px solid var(--accent)" : "1px solid var(--ink-4)",
              borderRadius: 6, fontFamily: "var(--mono)", fontSize: 12,
              background: n === 8 ? "var(--accent-soft)" : "transparent",
            }}>{n}</div>
          ))}
        </div>
      </div>
      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent">Finish & sync</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function CompleteCelebrate() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="" right=""/>
      <div style={{flex: 1, display:"flex", flexDirection:"column", justifyContent:"center", padding: "0 20px"}}>
        <div className="hand" style={{fontSize: 48, lineHeight: 1.05}}>done.</div>
        <div style={{marginTop: 18}}>
          <div className="big-num" style={{fontSize: 40}}>48:22</div>
          <div className="tiny">total time</div>
        </div>
        <div style={{display: "flex", gap: 20, marginTop: 18}}>
          <div>
            <div className="big-num" style={{fontSize: 28}}>42</div>
            <div className="tiny">sets</div>
          </div>
          <div>
            <div className="big-num" style={{fontSize: 28}}>12</div>
            <div className="tiny">exercises</div>
          </div>
          <div>
            <div className="big-num" style={{fontSize: 28}}>8.1</div>
            <div className="tiny">avg RPE</div>
          </div>
        </div>
      </div>
      <div style={{padding: "0 16px 10px", display: "flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Notes</div>
        <div className="btn accent" style={{flex: 2}}>Sync & close</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function CompleteReview() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Review & sync"/>
      <div className="small" style={{padding: "0 16px 6px"}}>tap any set to edit before syncing</div>

      {[
        {n: "Back Squat", s: "5×5 @ 225", rpe: "8", ok: true},
        {n: "Romanian DL", s: "4×8 @ 185", rpe: "7.5", ok: true},
        {n: "Bulgarian Split", s: "3×10 @ 40", rpe: "9", warn: true},
        {n: "Leg Curl", s: "3×12 @ 70", rpe: "8"},
      ].map(x => (
        <div key={x.n} style={{
          display: "flex", alignItems:"center",
          padding: "10px 16px", borderTop: "1px dashed var(--ink-4)",
        }}>
          <div style={{flex: 1}}>
            <div className="hand" style={{fontSize: 15}}>{x.n}</div>
            <div className="small">{x.s}</div>
          </div>
          <div style={{fontFamily: "var(--mono)", fontSize: 12, marginRight: 8}}>{x.rpe}</div>
          <span className="tiny">{x.warn ? "⚠︎" : "✓"}</span>
        </div>
      ))}

      <div style={{marginTop: "auto", padding: "0 16px 10px", display: "flex", gap: 8}}>
        <div className="btn" style={{flex: 1}}>Later</div>
        <div className="btn accent" style={{flex: 2}}>Sync now (4)</div>
      </div>
      <TabBar active="Workout"/>
    </Phone>
  );
}

function CompletionSection() {
  return (
    <Section
      title="5. Completion flow"
      kicker="after the last set · where logs solidify"
      intro="Workout ends. This is the moment to capture notes, overall RPE, and trigger sync. Three takes on how much ceremony to give it."
    >
      <div className="row">
        <Variant num="5.A" name="Summary + note" tagline="Quick stats, note field, overall RPE picker."
          notes={<Notes pros={["Captures the 'how it felt' signal", "One screen"]}
            cons={["Requires typing", "Note field ignored often"]}/>}>
          <CompleteSummary/>
        </Variant>
        <Variant num="5.B" name="Celebration" tagline="Big numbers. No friction. Sync and go."
          notes={<Notes pros={["Rewarding", "Fast"]}
            cons={["No nuanced feedback captured"]}/>}>
          <CompleteCelebrate/>
        </Variant>
        <Variant num="5.C" name="Review ledger" tagline="See every logged set before sync."
          notes={<Notes pros={["Catches typos", "Flag for sets with warnings (missed reps, etc.)"]}
            cons={["Heavy after a long session"]}/>}>
          <CompleteReview/>
        </Variant>
      </div>
    </Section>
  );
}

Object.assign(window, {
  RestSection, SwapSection, CompletionSection,
});
