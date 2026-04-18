// Meta wireframes — app shell, sync, settings, rest day, week peek

// ─── APP LAUNCH + SYNC ────────────────────────────────────

function FirstLaunch() {
  return (
    <Phone>
      <div style={{padding: "60px 24px 0", textAlign: "center"}}>
        <div className="hand" style={{fontSize: 32, lineHeight: 1.1, marginBottom: 8}}>WorkoutDB</div>
        <div className="tiny" style={{marginBottom: 40}}>Point at your server to begin</div>
        <div style={{border: "var(--stroke-ghost)", borderRadius: 8, padding: "14px 12px", textAlign: "left", marginBottom: 16}}>
          <div className="tiny" style={{marginBottom: 4}}>Server</div>
          <div className="small" style={{color: "var(--ink)"}}>https://___________________</div>
        </div>
        <div className="btn primary" style={{marginBottom: 10}}>Connect</div>
        <div className="btn ghost" style={{fontSize: 14}}>Scan QR</div>
      </div>
    </Phone>
  );
}

function SyncingFirstTime() {
  return (
    <Phone>
      <div style={{padding: "80px 24px 0", textAlign: "center"}}>
        <div className="hand" style={{fontSize: 28, marginBottom: 8}}>Syncing</div>
        <div className="small" style={{marginBottom: 32}}>pulling your program</div>
        <Ring pct={0.6} t="—" s="sync"/>
        <div className="tiny" style={{marginTop: 16}}>4 weeks · 14 sessions · 42 exercises</div>
      </div>
    </Phone>
  );
}

function SyncedReady() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right="⋮"/>
      <div style={{padding: "16px 16px 0"}}>
        <div className="hand" style={{fontSize: 28, marginBottom: 2}}>Push A</div>
        <div className="tiny">WEEK 3 · DAY 1 · ~54 MIN</div>
      </div>
      <div style={{padding: "20px 16px", display: "flex", flexDirection: "column", gap: 10}}>
        <div className="small">• Barbell Bench Press · 4 × 5</div>
        <div className="small">• Barbell Row · 3 × 8</div>
        <div className="small">• Overhead Press · 3 × 6</div>
        <div className="small">• Weighted Dip · 3 × 10</div>
      </div>
      <div style={{padding: "8px 16px"}}>
        <div className="btn primary">Start workout</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function OfflineQuiet() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right={<span className="small" style={{color: "var(--ink-3)", fontSize: 9}}>· offline</span>}/>
      <div style={{padding: "16px 16px 0"}}>
        <div className="hand" style={{fontSize: 28, marginBottom: 2}}>Push A</div>
        <div className="tiny">WEEK 3 · DAY 1 · ~54 MIN</div>
      </div>
      <div style={{padding: "20px 16px", display: "flex", flexDirection: "column", gap: 10}}>
        <div className="small">• Barbell Bench Press · 4 × 5</div>
        <div className="small">• Barbell Row · 3 × 8</div>
        <div className="small">• Overhead Press · 3 × 6</div>
        <div className="small">• Weighted Dip · 3 × 10</div>
      </div>
      <div style={{padding: "8px 16px"}}>
        <div className="btn primary">Start workout</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function OfflineSyncing() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right={<span className="small" style={{color: "var(--ink-3)", fontSize: 9}}>↻ syncing…</span>}/>
      <div style={{padding: "16px 16px 0"}}>
        <div className="hand" style={{fontSize: 28, marginBottom: 2}}>Push A</div>
        <div className="tiny">WEEK 3 · DAY 1 · ~54 MIN</div>
      </div>
      <div style={{padding: "20px 16px", display: "flex", flexDirection: "column", gap: 10}}>
        <div className="small">• Barbell Bench Press · 4 × 5</div>
        <div className="small">• Barbell Row · 3 × 8</div>
        <div className="small">• Overhead Press · 3 × 6</div>
        <div className="small">• Weighted Dip · 3 × 10</div>
      </div>
      <div style={{padding: "8px 16px"}}>
        <div className="btn primary">Start workout</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function SyncFailed() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right={<span className="small" style={{color: "var(--ink-3)", fontSize: 9}}>· offline · 2h</span>}/>
      <div style={{padding: "16px 16px 0"}}>
        <div className="hand" style={{fontSize: 28, marginBottom: 2}}>Push A</div>
        <div className="tiny">WEEK 3 · DAY 1 · ~54 MIN</div>
      </div>
      <div style={{padding: "20px 16px", display: "flex", flexDirection: "column", gap: 10}}>
        <div className="small">• Barbell Bench Press · 4 × 5</div>
        <div className="small">• Barbell Row · 3 × 8</div>
        <div className="small">• Overhead Press · 3 × 6</div>
        <div className="small">• Weighted Dip · 3 × 10</div>
      </div>
      <div style={{padding: "8px 16px"}}>
        <div className="btn primary">Start workout</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function AppLaunchSection() {
  return (
    <Section title="1 · App launch & sync" kicker="BLOCKING · V1">
      <p className="section-intro">Local-first. The app works whether or not the server is reachable. Sync happens silently on open, on log-write, and on a gentle interval (≈1 min while foregrounded). Offline isn't an error state — it's the default. First launch is the only screen that actually <i>needs</i> a server, because there's nothing cached yet.</p>
      <div className="row">
        <Variant num="1.A" name="First launch" tagline="No cache yet — server is required. Paste or scan.">
          <FirstLaunch/>
          <Notes tag pros={["One decision","Server is the identity"]} cons={["User must know a URL — rely on Claude to hand it over"]}/>
        </Variant>
        <Variant num="1.B" name="First sync" tagline="Visible once. After this, sync is silent.">
          <SyncingFirstTime/>
          <Notes pros={["Shows what's being pulled","One-time ceremony"]}/>
        </Variant>
        <Variant num="1.C" name="Today · steady state" tagline="Online or offline — looks the same. No badge.">
          <SyncedReady/>
          <Notes pros={["No decoration when nothing's wrong","Silent by design"]}/>
        </Variant>
      </div>
      <div className="row" style={{marginTop: 48}}>
        <Variant num="1.D" name="Offline · small indicator" tagline="Not yellow, not a warning. Neutral state text.">
          <OfflineQuiet/>
          <Notes tag pros={["Offline is not an error — no alarm color","Indicator sits where a menu would"]} cons={["Might be too subtle — consider with/without 'last synced' timestamp"]}/>
        </Variant>
        <Variant num="1.E" name="Syncing…" tagline="Brief. Appears when retry succeeds or user taps refresh.">
          <OfflineSyncing/>
          <Notes pros={["Neutral, not alarming","Auto-hides when done"]}/>
        </Variant>
        <Variant num="1.F" name="Offline · with age" tagline="Same layout, shows how long since last sync.">
          <SyncFailed/>
          <Notes pros={["Lets user judge staleness at a glance","No retry button — app retries itself"]} cons={["Extra data cost; may only show if >1h"]}/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── REST DAY ─────────────────────────────────────────────

function RestDay() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right="⋮"/>
      <div style={{padding: "80px 24px 0", textAlign: "center"}}>
        <div className="hand" style={{fontSize: 32, marginBottom: 8}}>Rest day</div>
        <div className="small" style={{marginBottom: 40, color: "var(--ink-2)"}}>Next: Pull A · tomorrow</div>
        <div className="tiny" style={{marginBottom: 16}}>LAST TRAINED</div>
        <div className="small">Push A · yesterday · RIR 1.5 avg</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function RestDayWithPeek() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right="⋮"/>
      <div style={{padding: "50px 24px 0", textAlign: "center"}}>
        <div className="hand" style={{fontSize: 26, marginBottom: 8}}>Rest day</div>
        <div className="small" style={{marginBottom: 28, color: "var(--ink-2)"}}>Next: Pull A · tomorrow</div>
      </div>
      <div style={{padding: "0 16px"}}>
        <div className="tiny" style={{marginBottom: 8}}>THIS WEEK</div>
        <div style={{display: "flex", flexDirection: "column", gap: 6}}>
          <div className="small" style={{color: "var(--ink-3)"}}>MON · Push A ✓</div>
          <div className="small" style={{color: "var(--ink)"}}>TUE · Rest ←</div>
          <div className="small" style={{color: "var(--ink-2)"}}>WED · Pull A</div>
          <div className="small" style={{color: "var(--ink-2)"}}>THU · Legs A</div>
          <div className="small" style={{color: "var(--ink-2)"}}>FRI · Rest</div>
          <div className="small" style={{color: "var(--ink-2)"}}>SAT · Push B</div>
          <div className="small" style={{color: "var(--ink-2)"}}>SUN · Rest</div>
        </div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function UnscheduledDay() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right="⋮"/>
      <div style={{padding: "80px 24px 0", textAlign: "center"}}>
        <div className="hand" style={{fontSize: 26, marginBottom: 8}}>Nothing scheduled</div>
        <div className="small" style={{marginBottom: 32, color: "var(--ink-2)"}}>Your program ended 3 days ago</div>
        <div className="small" style={{color: "var(--ink-3)", lineHeight: 1.5, marginBottom: 24}}>Ask Claude to push<br/>the next block</div>
        <div className="btn ghost" style={{fontSize: 14}}>Sync now</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function RestDaySection() {
  return (
    <Section title="2 · Rest day & no-workout states" kicker="BLOCKING · V1">
      <p className="section-intro">Today isn't always a workout. Keep these screens calm — no filler, no motivational copy. The answer to "what now" is always "rest, or ask Claude for more."</p>
      <div className="row">
        <Variant num="2.A" name="Rest day — minimal" tagline="Just the facts. Most common state.">
          <RestDay/>
          <Notes pros={["No clutter","Last session as anchor"]} cons={["No sense of weekly shape"]}/>
        </Variant>
        <Variant num="2.B" name="Rest day — week peek" tagline="Shows the week. Good for weekly-view people.">
          <RestDayWithPeek/>
          <Notes tag pros={["Answers 'when's leg day'","Serves as week peek everywhere"]} cons={["More to render / more stale if offline"]}/>
        </Variant>
        <Variant num="2.C" name="Unscheduled / program ended" tagline="Tell user to ask Claude. Don't fake more content.">
          <UnscheduledDay/>
          <Notes pros={["Honest","Points user to the upstream fix"]}/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── WEEK PEEK (tappable from Today) ──────────────────────

function WeekPeekSheet() {
  return (
    <Phone>
      <div style={{position: "absolute", inset: 0, background: "rgba(0,0,0,0.3)"}}/>
      <div style={{position: "absolute", left: 0, right: 0, bottom: 0, background: "var(--paper)", borderRadius: "20px 20px 0 0", padding: "14px 0 24px", border: "var(--stroke)"}}>
        <div style={{width: 40, height: 3, background: "var(--ink-3)", borderRadius: 2, margin: "0 auto 14px"}}/>
        <div className="hand" style={{fontSize: 20, padding: "0 20px 4px"}}>This week</div>
        <div className="tiny" style={{padding: "0 20px 12px"}}>PUSH / PULL / LEGS · WEEK 3</div>
        <div style={{padding: "0 20px", display: "flex", flexDirection: "column", gap: 8}}>
          <div className="small" style={{color: "var(--ink-3)"}}>MON · Push A · 4 ex · ✓ done</div>
          <div className="small" style={{color: "var(--ink-3)"}}>TUE · Rest</div>
          <div className="small" style={{color: "var(--ink)", fontWeight: 600}}>WED · Pull A · 4 ex ← today</div>
          <div className="small" style={{color: "var(--ink-2)"}}>THU · Legs A · 5 ex</div>
          <div className="small" style={{color: "var(--ink-2)"}}>FRI · Rest</div>
          <div className="small" style={{color: "var(--ink-2)"}}>SAT · Push B · 4 ex</div>
          <div className="small" style={{color: "var(--ink-2)"}}>SUN · Rest</div>
        </div>
      </div>
    </Phone>
  );
}

function WeekPeekEntry() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Today" back=" " right="⋮"/>
      <div style={{padding: "16px 16px 0"}}>
        <div className="hand" style={{fontSize: 28, marginBottom: 2}}>Pull A</div>
        <div className="tiny" style={{marginBottom: 4}}>WEEK 3 · DAY 3 · ~48 MIN</div>
        <div className="pill" style={{fontSize: 9, marginBottom: 10}}>VIEW WEEK →</div>
      </div>
      <div style={{padding: "8px 16px", display: "flex", flexDirection: "column", gap: 8}}>
        <div className="small">• Pull-up · 4 × AMRAP</div>
        <div className="small">• Barbell Row · 3 × 8</div>
        <div className="small">• Face Pull · 3 × 12</div>
        <div className="small">• Barbell Curl · 3 × 10</div>
      </div>
      <div style={{padding: "8px 16px"}}>
        <div className="btn primary">Start workout</div>
      </div>
      <TabBar active="Today"/>
    </Phone>
  );
}

function WeekPeekSection() {
  return (
    <Section title="3 · Week peek" kicker="IMPORTANT · V1">
      <p className="section-intro">A small affordance on Today for "what's the rest of the week look like?" Sheet, not a new screen — keeps Today as the only real home.</p>
      <div className="row">
        <Variant num="3.A" name="Entry — pill on Today" tagline="Subtle 'view week' pill below day header.">
          <WeekPeekEntry/>
          <Notes pros={["Doesn't interrupt flow","Discoverable without being pushy"]}/>
        </Variant>
        <Variant num="3.B" name="Peek sheet" tagline="Bottom sheet · today marked · done days checked.">
          <WeekPeekSheet/>
          <Notes tag pros={["Weekly rhythm visible","Tap a day → that day's detail (future)"]} cons={["Program could be longer than 7 days — need 'next week' scroll"]}/>
        </Variant>
      </div>
    </Section>
  );
}

// ─── SETTINGS ─────────────────────────────────────────────

function SettingsMain() {
  return (
    <Phone tall>
      <StatusRow/>
      <Nav title="Settings" back=" " right=" "/>
      <div style={{padding: "0 20px", flex: 1, overflow: "auto"}}>
        <div className="tiny" style={{margin: "10px 0 6px"}}>SERVER</div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--ink)"}}>wdb.local:8080</div>
          <div className="tiny" style={{marginTop: 2}}>SYNCED 4 MIN AGO</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Sync now</div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)", borderBottom: "var(--stroke-ghost)"}}>
          <div className="small">Change server</div>
        </div>

        <div className="tiny" style={{margin: "16px 0 6px"}}>DEVICE</div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Units · <span style={{color: "var(--ink-2)"}}>kg</span></div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Watch · <span style={{color: "var(--ink-2)"}}>Apple Watch Series 9</span></div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)", borderBottom: "var(--stroke-ghost)"}}>
          <div className="small">Rest sound · <span style={{color: "var(--ink-2)"}}>chime</span></div>
        </div>

        <div className="tiny" style={{margin: "16px 0 6px"}}>AUTOREG DEFAULTS</div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Overshoot trigger · <span style={{color: "var(--ink-2)"}}>RIR target + 2</span></div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small">Step size · <span style={{color: "var(--ink-2)"}}>2.5 kg</span></div>
        </div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)", borderBottom: "var(--stroke-ghost)"}}>
          <div className="small">Apply to · <span style={{color: "var(--ink-2)"}}>remaining sets</span></div>
        </div>

        <div className="tiny" style={{margin: "16px 0 6px"}}>DATA</div>
        <div style={{padding: "10px 0", borderTop: "var(--stroke-ghost)"}}>
          <div className="small" style={{color: "var(--accent)"}}>Reset local data</div>
        </div>
        <div style={{padding: "10px 0 20px", borderTop: "var(--stroke-ghost)"}}>
          <div className="tiny">BUILD 0.14.2 · COMMIT a3f91c</div>
        </div>
      </div>
      <TabBar active="Settings"/>
    </Phone>
  );
}

function SettingsChangeServer() {
  return (
    <Phone>
      <StatusRow/>
      <Nav title="Change server" right=" "/>
      <div style={{padding: "20px 24px 0"}}>
        <div className="tiny" style={{marginBottom: 6}}>NEW SERVER</div>
        <div style={{border: "var(--stroke)", borderRadius: 8, padding: "10px 12px", marginBottom: 4}}>
          <div className="small" style={{color: "var(--ink)"}}>https://wdb.local:8080</div>
        </div>
        <div className="tiny" style={{marginBottom: 24, color: "var(--accent)"}}>CHANGING SERVERS WIPES LOCAL DATA</div>

        <div className="btn primary" style={{marginBottom: 10}}>Connect to new server</div>
        <div className="btn ghost" style={{fontSize: 14}}>Scan QR instead</div>
      </div>
    </Phone>
  );
}

function SettingsSection() {
  return (
    <Section title="4 · Settings" kicker="BLOCKING · V1">
      <p className="section-intro">Minimal. Four groups: server, device, autoreg defaults, data. No user profile — server is identity.</p>
      <div className="row">
        <Variant num="4.A" name="Settings main" tagline="One list, grouped. Autoreg defaults are overridable per-exercise upstream.">
          <SettingsMain/>
          <Notes tag pros={["All knobs in one place","Autoreg defaults are a copy of upstream — user can override"]} cons={["'Watch pairing' implies native integration — out of scope?"]}/>
        </Variant>
        <Variant num="4.B" name="Change server" tagline="Destructive. Explicit wipe warning.">
          <SettingsChangeServer/>
          <Notes pros={["Clear it's destructive","Same affordance as first launch"]}/>
        </Variant>
      </div>
    </Section>
  );
}

function MetaSection() {
  return (
    <>
      <AppLaunchSection/>
      <RestDaySection/>
      <WeekPeekSection/>
      <SettingsSection/>
    </>
  );
}

Object.assign(window, {
  FirstLaunch, SyncingFirstTime, SyncedReady, OfflineQuiet, OfflineSyncing, SyncFailed, AppLaunchSection,
  RestDay, RestDayWithPeek, UnscheduledDay, RestDaySection,
  WeekPeekEntry, WeekPeekSheet, WeekPeekSection,
  SettingsMain, SettingsChangeServer, SettingsSection,
  MetaSection,
});
