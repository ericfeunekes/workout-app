// History wireframes — list, session detail, per-exercise view + chart

// ─── HISTORY LIST ─────────────────────────────────────────

function HistoryList() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="History" back=" " right="⋮"/>
      <div style={{padding: "0 16px", flex: 1, overflow: "auto"}}>
        <div className="tiny" style={{margin: "6px 0"}}>APR · WEEK 15</div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Push A · MON</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 1.5 · 54 MIN · 82.1 KG BW</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Pull A · WED</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 2.0 · 48 MIN</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Legs A · THU</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 0.5 · 64 MIN · FORM NOTE</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Push B · SAT</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 1.8 · 51 MIN</div>
        </div>
        <div className="tiny" style={{margin: "16px 0 6px"}}>APR · WEEK 14</div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Push A · MON</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 2.0 · 51 MIN</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Pull A · WED</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 1.5 · 46 MIN</div>
        </div>
      </div>
      <TabBar active="History"/>
    </Phone>
  );
}

function HistoryFilters() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="History" back=" " right="⋮"/>
      <div style={{padding: "6px 16px 10px", display: "flex", gap: 6, flexWrap: "wrap"}}>
        <span className="pill filled">ALL</span>
        <span className="pill">PUSH</span>
        <span className="pill">PULL</span>
        <span className="pill">LEGS</span>
        <span className="pill">BY EXERCISE →</span>
      </div>
      <div style={{padding: "0 16px", flex: 1, overflow: "auto"}}>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Push A · MON APR 14</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 1.5 · 54 MIN</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Push B · SAT APR 12</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 1.8 · 51 MIN</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>Push A · MON APR 7</div>
          <div className="tiny" style={{marginTop: 2}}>RIR 2.0 · 51 MIN</div>
        </div>
      </div>
      <TabBar active="History"/>
    </Phone>
  );
}

function HistoryListSection() {
  return (
    <Section title="1 · History list" kicker="IMPORTANT · V1">
      <p className="section-intro">Reverse-chronological. Grouped by week. Tap a session → detail. Tap "by exercise" → per-exercise history. No charts here — summary numbers only.</p>
      <div className="row">
        <Variant num="1.A" name="List — minimal" tagline="Date, name, RIR, duration. That's it.">
          <HistoryList/>
          <Notes pros={["Scannable","No slop — just facts"]}/>
        </Variant>
        <Variant num="1.B" name="List — with filters" tagline="Toggle split, jump to exercise view.">
          <HistoryFilters/>
          <Notes tag pros={["Fast narrowing","'By exercise' is a pivot, not a filter"]} cons={["Filter pills eat vertical space"]}/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── SESSION DETAIL ───────────────────────────────────────

function SessionDetail() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="MON APR 14" right="⋮"/>
      <div style={{padding: "0 16px", flex: 1, overflow: "auto"}}>
        <div className="hand" style={{fontSize: 24, marginBottom: 2}}>Push A</div>
        <div className="tiny" style={{marginBottom: 14}}>RIR 1.5 AVG · 54 MIN · 82.1 KG BW</div>

        <div className="tiny" style={{marginTop: 8}}>BARBELL BENCH PRESS</div>
        <div style={{padding: "6px 0", fontFamily: "var(--mono)", fontSize: 11, color: "var(--ink-2)", lineHeight: 1.7}}>
          <div>1 · 100 kg × 5 · RIR 2</div>
          <div>2 · 100 kg × 5 · RIR 2</div>
          <div>3 · 100 kg × 5 · RIR 1</div>
          <div>4 · 100 kg × 4 · RIR 0</div>
        </div>

        <div className="tiny" style={{marginTop: 14}}>BARBELL ROW</div>
        <div style={{padding: "6px 0", fontFamily: "var(--mono)", fontSize: 11, color: "var(--ink-2)", lineHeight: 1.7}}>
          <div>1 · 77.5 kg × 8 · RIR 1</div>
          <div>2 · 77.5 kg × 8 · RIR 1</div>
          <div>3 · 77.5 kg × 7 · RIR 0</div>
        </div>

        <div className="tiny" style={{marginTop: 14}}>OVERHEAD PRESS</div>
        <div style={{padding: "6px 0", fontFamily: "var(--mono)", fontSize: 11, color: "var(--ink-2)", lineHeight: 1.7}}>
          <div>1 · 52.5 kg × 6 · RIR 2</div>
          <div>2 · 52.5 kg × 6 · RIR 2</div>
          <div>3 · 52.5 kg × 6 · RIR 1</div>
        </div>

        <div style={{marginTop: 16, padding: "10px 12px", background: "var(--paper-2)", borderRadius: 6}}>
          <div className="tiny" style={{marginBottom: 4}}>NOTE</div>
          <div className="small" style={{color: "var(--ink)", lineHeight: 1.5}}>Bench grip felt narrow. Try standard width next time.</div>
        </div>
      </div>
      <TabBar active="History"/>
    </Phone>
  );
}

function SessionDetailEditable() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="MON APR 14" right="DONE"/>
      <div style={{padding: "0 16px", flex: 1, overflow: "auto"}}>
        <div className="hand" style={{fontSize: 24, marginBottom: 14}}>Push A · editing</div>

        <div className="tiny" style={{marginTop: 8}}>BARBELL BENCH PRESS</div>
        <div style={{padding: "6px 0", fontFamily: "var(--mono)", fontSize: 11, lineHeight: 1.8}}>
          <div>1 · <span style={{borderBottom: "1px dashed var(--ink-3)"}}>100 kg</span> × <span style={{borderBottom: "1px dashed var(--ink-3)"}}>5</span> · <span style={{borderBottom: "1px dashed var(--ink-3)"}}>RIR 2</span></div>
          <div>2 · 100 kg × 5 · RIR 2</div>
          <div style={{color: "var(--accent)"}}>3 · <b>102.5 kg</b> × 5 · RIR 1 ← edited</div>
          <div>4 · 100 kg × 4 · RIR 0</div>
        </div>
        <div className="tiny" style={{marginTop: 10, color: "var(--accent)"}}>CORRECTING LOG · NO AUTOREG</div>
      </div>
      <TabBar active="History"/>
    </Phone>
  );
}

function SessionDetailSection() {
  return (
    <Section title="2 · Session detail" kicker="IMPORTANT · V1">
      <p className="section-intro">Everything that happened in one session. Every value tap-editable (corrective, no autoreg rerun — same rule as in-workout).</p>
      <div className="row">
        <Variant num="2.A" name="Detail — read" tagline="Default view. Clean ledger, optional note.">
          <SessionDetail/>
          <Notes pros={["Dense but calm","Mono for data, no decoration"]}/>
        </Variant>
        <Variant num="2.B" name="Detail — editing" tagline="Same surface, underlined cells, edit highlight.">
          <SessionDetailEditable/>
          <Notes tag pros={["No separate edit mode","Matches in-workout tap-to-edit"]} cons={["'DONE' vs '⋮' menu — only one visible at a time"]}/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── PER-EXERCISE VIEW ────────────────────────────────────

function ExerciseHistory() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="Bench Press" right="⋮"/>
      <div style={{padding: "0 16px", flex: 1, overflow: "auto"}}>
        <div className="tiny" style={{margin: "4px 0 4px"}}>LAST 12 WEEKS</div>

        {/* Simple chart placeholder */}
        <div style={{height: 90, border: "var(--stroke-ghost)", borderRadius: 6, margin: "6px 0 4px", position: "relative", padding: 8}}>
          <svg width="100%" height="72" viewBox="0 0 240 72" preserveAspectRatio="none" style={{display: "block"}}>
            <polyline fill="none" stroke="var(--accent)" strokeWidth="1.5"
              points="0,60 20,58 40,56 60,52 80,48 100,44 120,40 140,36 160,30 180,28 200,22 220,18 240,14"/>
            <g fontFamily="var(--mono)" fontSize="7" fill="var(--ink-3)">
              <text x="2" y="10">top set load</text>
              <text x="2" y="70">80</text>
              <text x="215" y="70">105</text>
            </g>
          </svg>
        </div>
        <div className="tiny" style={{marginBottom: 14}}>TOP SET · TREND ↑ 25 KG / 12 WK</div>

        <div className="tiny" style={{marginTop: 6}}>RECENT SESSIONS</div>
        <div style={{padding: "6px 0", fontFamily: "var(--mono)", fontSize: 11, color: "var(--ink-2)", lineHeight: 1.8}}>
          <div>MON APR 14 · 4 × 100 × 5 · RIR 1.5</div>
          <div>MON APR 7 · 4 × 100 × 5 · RIR 2</div>
          <div>MON MAR 31 · 4 × 97.5 × 5 · RIR 1.5</div>
          <div>MON MAR 24 · 4 × 97.5 × 5 · RIR 2</div>
          <div>MON MAR 17 · 4 × 95 × 5 · RIR 1</div>
          <div>MON MAR 10 · 4 × 95 × 5 · RIR 2</div>
          <div>MON MAR 3 · 4 × 92.5 × 5 · RIR 1.5</div>
        </div>
      </div>
      <TabBar active="History"/>
    </Phone>
  );
}

function ExercisePicker() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="By exercise" right="⋮"/>
      <div style={{padding: "6px 16px 10px"}}>
        <div style={{border: "var(--stroke-ghost)", borderRadius: 6, padding: "6px 10px"}}>
          <div className="small" style={{color: "var(--ink-3)"}}>Search exercises…</div>
        </div>
      </div>
      <div style={{padding: "0 16px", flex: 1, overflow: "auto"}}>
        <div className="tiny" style={{marginBottom: 4}}>IN YOUR PROGRAM</div>
        <div style={{padding: "8px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Barbell Bench Press</div>
          <div className="tiny" style={{marginTop: 2}}>12 SESSIONS · TOP 102.5 KG</div>
        </div>
        <div style={{padding: "8px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Barbell Row</div>
          <div className="tiny" style={{marginTop: 2}}>12 SESSIONS · TOP 80 KG</div>
        </div>
        <div style={{padding: "8px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Overhead Press</div>
          <div className="tiny" style={{marginTop: 2}}>12 SESSIONS · TOP 55 KG</div>
        </div>
        <div style={{padding: "8px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Weighted Dip</div>
          <div className="tiny" style={{marginTop: 2}}>12 SESSIONS · TOP 20 KG</div>
        </div>
        <div className="tiny" style={{margin: "16px 0 4px"}}>PAST PROGRAMS</div>
        <div style={{padding: "8px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink-2)"}}>Incline DB Press</div>
          <div className="tiny" style={{marginTop: 2}}>6 SESSIONS · LAST 2 MO AGO</div>
        </div>
      </div>
      <TabBar active="History"/>
    </Phone>
  );
}

function ExerciseHistorySection() {
  return (
    <Section title="3 · By-exercise view" kicker="IMPORTANT · V1">
      <p className="section-intro">Pivot of history by exercise. Small chart for trend (top set load over time). Recent sessions as a list. This is the "how'd I do on bench last time" view.</p>
      <div className="row">
        <Variant num="3.A" name="Exercise picker" tagline="Entry from 'by exercise'. Grouped: current program / past.">
          <ExercisePicker/>
          <Notes pros={["Current program first","Past exercises stay reachable"]}/>
        </Variant>
        <Variant num="3.B" name="Exercise history + trend" tagline="Minimal chart + recent sessions. Everything else — ask Claude.">
          <ExerciseHistory/>
          <Notes tag pros={["One chart, one list","Scope is 'just enough'"]} cons={["No volume chart, no RIR overlay — punted to Claude"]}/>
        </Variant>
      </div>
    </Section>
  );
}

function HistorySection() {
  return (
    <>
      <HistoryListSection/>
      <SessionDetailSection/>
      <ExerciseHistorySection/>
    </>
  );
}

Object.assign(window, {
  HistoryList, HistoryFilters, HistoryListSection,
  SessionDetail, SessionDetailEditable, SessionDetailSection,
  ExerciseHistory, ExercisePicker, ExerciseHistorySection,
  HistorySection,
});
