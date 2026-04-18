// Section 1 — Canonical straight_sets active-set screen
// Three density / timer treatments

// ─── Variant A: Glance-dominant rest timer ────────────────────
function StraightA() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Block 2 of 4"/>
      <div className="exname">Back Squat</div>
      <div className="submeta">Set 3 of 5 · Strength</div>

      <Ring pct={0.48} t="1:24" s="Rest"/>

      <div style={{padding: "0 16px", textAlign: "center"}}>
        <div className="small hand" style={{fontSize: 16, color: "var(--ink)"}}>
          Next: <b>225 lb × 5</b>
        </div>
        <div className="tiny" style={{marginTop: 4}}>RPE target 8 · 2:00 prescribed</div>
      </div>

      <LastTime summary="220×5 @ RPE 7.5  ·  4d ago"/>

      <div style={{padding: "0 16px", marginTop: "auto", display:"flex", gap: 8}}>
        <div className="btn ghost" style={{flex: 1}}>Skip rest</div>
        <div className="btn accent" style={{flex: 2}}>Start set 3</div>
      </div>

      <TabBar active="Workout"/>
    </Phone>
  );
}

// ─── Variant B: Dense data table, timer secondary ─────────────
function StraightB() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat"/>
      <div style={{padding: "0 16px"}}>
        <div className="submeta" style={{padding: 0, marginBottom: 6}}>Strength · 5×5 @ 225 · RPE 8</div>
      </div>

      <div style={{padding: "0 16px", display:"flex", justifyContent:"space-between", alignItems:"baseline"}}>
        <div>
          <div className="tiny">Rest</div>
          <div className="big-num" style={{fontSize: 34, lineHeight: 1}}>1:24</div>
        </div>
        <div style={{textAlign:"right"}}>
          <div className="tiny">Next</div>
          <div className="hand" style={{fontSize: 18}}>225 × 5</div>
        </div>
      </div>

      <div className="divider dashed"/>

      <div className="set-row head">
        <span>#</span><span>Load</span><span>Reps</span><span>RPE</span><span></span>
      </div>
      <div className="set-row done"><span className="num-cell">1</span><span>225</span><span>5</span><span>7</span><span className="check"/></div>
      <div className="set-row done"><span className="num-cell">2</span><span>225</span><span>5</span><span>7.5</span><span className="check"/></div>
      <div className="set-row current"><span className="num-cell">3</span><span>225</span><span>5</span><span>8</span><span className="check">—</span></div>
      <div className="set-row"><span>4</span><span>225</span><span>5</span><span>8</span><span></span></div>
      <div className="set-row"><span>5</span><span>225</span><span>5</span><span>8.5</span><span></span></div>

      <LastTime summary="220×5,5,5,4,4  ·  RPE 7→9  ·  4d"/>

      <div style={{padding: "8px 16px 0", display:"flex", gap: 8}}>
        <div className="btn ghost" style={{flex: 1}}>Skip</div>
        <div className="btn primary" style={{flex: 2}}>Start set 3</div>
      </div>

      <TabBar active="Workout"/>
    </Phone>
  );
}

// ─── Variant C: Thumb-optimized — action hero, data above ────
function StraightC() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Back Squat" right="swap"/>

      <div style={{padding: "0 16px 8px"}}>
        <div className="small">Set 3 / 5</div>
        <div className="hand" style={{fontSize: 56, lineHeight: 0.95, marginTop: 4}}>225</div>
        <div className="submeta" style={{padding: 0}}>lb × 5 reps · RPE 8</div>
      </div>

      <div style={{padding: "0 16px"}}>
        <div style={{display: "flex", gap: 6, marginBottom: 12}}>
          {[1,2,3,4,5].map(i => (
            <div key={i} style={{
              flex: 1, height: 5, borderRadius: 3,
              background: i < 3 ? "var(--accent)" : i === 3 ? "var(--ink-2)" : "var(--ink-4)",
            }}/>
          ))}
        </div>
      </div>

      <LastTime summary="220×5,5,5,4,4  ·  4d ago"/>

      <div style={{padding: "0 16px"}}>
        <div className="callout" style={{marginBottom: 0, fontSize: 13, padding: "6px 12px"}}>
          <span className="tiny" style={{color: "var(--ink-2)"}}>Resting</span>{" "}
          <b style={{fontFamily: "var(--mono)"}}>1:24</b> of 2:00
        </div>
      </div>

      <div style={{marginTop: "auto", padding: "0 16px 10px"}}>
        <div className="btn accent" style={{padding: "22px 20px", fontSize: 22}}>Start set 3</div>
        <div style={{display:"flex", justifyContent:"space-between", marginTop: 8}}>
          <span className="tiny">+ rest</span>
          <span className="tiny">skip rest</span>
          <span className="tiny">log now</span>
        </div>
      </div>

      <TabBar active="Workout"/>
    </Phone>
  );
}

function StraightSetsSection() {
  return (
    <Section
      title="1. straight_sets — the 80% case"
      kicker="canonical screen · 3 density variants"
      intro="The core screen, stress-tested for information density and action placement. Rest timer dominance is the main dial. Annotations call out what each tradeoff buys you."
    >
      <div className="row">
        <Variant
          num="1.A"
          name="Glance ring"
          tagline="Timer is the whole screen. Everything else is one line."
          notes={<Notes
            pros={[
              "Under-the-barbell readable — timer is ~72pt",
              "Clear single CTA",
              "Works 1:1 on watch",
            ]}
            cons={[
              "Set-by-set history hidden",
              "RPE logging pushed to completion",
            ]}
          />}
        >
          <StraightA/>
        </Variant>

        <Variant
          num="1.B"
          name="Ledger"
          tagline="Every set visible. Timer demoted. For the lifter who logs."
          notes={<Notes
            pros={[
              "See pattern of RPE across sets",
              "Edit-in-place feels natural",
              "Matches a paper log",
            ]}
            cons={[
              "Timer small — easy to miss haptic",
              "Dense; sweaty-thumb risk",
            ]}
          />}
        >
          <StraightB/>
        </Variant>

        <Variant
          num="1.C"
          name="Action bottom"
          tagline="Giant CTA in the thumb zone. Data above, timer inline."
          notes={<Notes
            pros={[
              "Thumb never leaves bottom 1/3",
              "Progress pips are glanceable",
              "Big Start button = big haptic target",
            ]}
            cons={[
              "Rest timer demoted to one line",
              "Less history on screen",
            ]}
          />}
        >
          <StraightC/>
        </Variant>
      </div>
    </Section>
  );
}

Object.assign(window, { StraightSetsSection });
