docs/roadmap/appendix-a-data-model.md

# Appendix A — Data Model (Detailed)

This appendix describes the full SQLite data model (MVP through v1.0) and how the pieces connect.

The design is intentionally “log-first”:
- You can log workouts even if exercises are incomplete.
- You can import messy historical workouts without losing text.
- You can add equipment and stimulus tracking later without rewriting tables.

---

## Mental model: 5 layers

1) **Catalog (slow-changing truth)**
   - Exercises, muscle groups, equipment capability types

2) **Library (examples)**
   - Imported/raw workouts + structured templates derived from them

3) **Planning**
   - User goals + planned workouts on a schedule

4) **Execution**
   - Workout sessions + performed blocks/items + set logs (what actually happened)

5) **Enrichment (optional add-ons)**
   - Stimulus labels, check-in answers, derived metrics
   - Equipment bootstrapping from observed usage
   - Substitution logic

---

## Relationship overview (high level)

```mermaid
erDiagram
  app_user ||--o{ user_goal : has
  app_user ||--o{ planned_workout : schedules
  app_user ||--o{ workout_session : logs

  workout_source ||--o{ raw_workout : provides
  raw_workout }o--|| workout_template : "may link (parsed)"

  workout_template ||--o{ workout_block : has
  workout_block ||--o{ workout_item : has
  workout_template ||--o{ planned_workout : "is scheduled"
  workout_template }o--o{ tag : tagged

  workout_session ||--o{ session_block : has
  session_block ||--o{ session_item : has
  session_item ||--o{ set_log : has

  exercise_family ||--o{ exercise : groups
  exercise ||--o{ workout_item : used_in
  exercise ||--o{ session_item : performed
  exercise ||--o{ exercise_muscle : targets
  muscle_group ||--o{ exercise_muscle : targeted_by

  exercise ||--o{ exercise_setup : has
  exercise_setup ||--o{ setup_equipment_group : requires
  setup_equipment_group ||--o{ setup_equipment_option : offers
  session_item ||--o{ session_item_equipment_choice : used_equipment

  gym ||--o{ workout_session : occurs_in
  gym ||--o{ gym_inventory : stocks
  gym ||--o{ gym_observed_equipment : observes
  equipment_model ||--o{ gym_inventory : stocked_as
  equipment_model ||--o{ gym_observed_equipment : seen_as
  equipment_model ||--o{ equipment_model_type : provides
  equipment_type ||--o{ equipment_model_type : capability

  stimulus_type ||--o{ stimulus_assignment : assigned
  metric_type ||--o{ metric_value : recorded
  session_block ||--o{ block_checkin_response : answered

If your repo doesn’t render Mermaid, treat it as a conceptual diagram.

⸻

Conventions used throughout

IDs

All primary keys are UUIDs (stored as TEXT or BLOB) to support future sync/merge.

JSON fields

Some columns are *_json (TEXT) to avoid schema churn. Examples:
	•	block intent (time cap, interval length)
	•	item prescription (sets/reps/load hints)
	•	raw parsed intermediates
	•	derived summaries

MVP can treat JSON as opaque strings. Later versions can validate them.

Optionality

Many foreign keys are nullable by design. Logging should not be blocked.

⸻

1) Core catalog

app_user

Represents a person using the system (you, your wife, later gym members).

Key columns
	•	user_id (PK)
	•	name
	•	created_at

Connections
	•	workout_session.user_id
	•	planned_workout.user_id
	•	user_goal.user_id

⸻

gym

Represents a training location. In MVP you might only have one gym.

Key columns
	•	gym_id (PK)
	•	name

Connections
	•	workout_session.gym_id
	•	gym_inventory.gym_id
	•	gym_observed_equipment.gym_id

⸻

muscle_group

Catalog of muscle groups with optional hierarchy.

Key columns
	•	muscle_group_id (PK)
	•	name (unique)
	•	parent_id (nullable FK to muscle_group)

Why hierarchy matters
Allows both:
	•	“Chest” as a parent
	•	“Upper chest” as a child
without needing separate tables later.

⸻

exercise_family

Optional grouping like “Bench press” family containing multiple variants.

Key columns
	•	family_id (PK)
	•	name (unique)

⸻

exercise

A named movement you can program and log.

Key columns
	•	exercise_id (PK)
	•	name (unique)
	•	family_id (optional FK)
	•	modality (strength / conditioning / skill / mobility)
	•	movement_pattern (push/pull/squat/hinge/carry/locomotion/core/other)
	•	is_unilateral (0/1)
	•	scope + ownership (optional future-proofing)
	•	scope: global | user | gym
	•	owner_user_id and owner_gym_id as needed
	•	description, notes, extra_json

Connections
	•	Used by templates and sessions:
	•	workout_item.exercise_id
	•	session_item.exercise_id

⸻

exercise_muscle

Weighted mapping of which muscles an exercise trains.

Key columns
	•	exercise_id (FK)
	•	muscle_group_id (FK)
	•	role (primary | secondary | tertiary)
	•	weight (0..1)

How it’s used
	•	substitutions: “find exercises with similar muscle profile”
	•	goal programming: “more chest volume this week”
	•	analytics: “what patterns correlate with progress?”

⸻

Aliases (recommended for parsing)

Historical plans contain abbreviations and nicknames.

exercise_alias
	•	alias (unique text, e.g., “DB bench”, “dumbbell bench press”)
	•	exercise_id (FK)

muscle_alias (optional)
	•	alias
	•	muscle_group_id

These tables greatly improve import/parsing quality without changing core schema.

⸻

2) Equipment model (capabilities → concrete models → gym inventory)

Equipment is split into:
	•	capabilities (equipment_type) — “what something is”
	•	models (equipment_model) — “a specific thing”
	•	gym inventory (gym_inventory) — “how many of those things a gym has”
	•	observed equipment (gym_observed_equipment) — “we’ve seen it used here”

equipment_type (capability)

Examples:
	•	ez_curl_bar
	•	rackable_barbell
	•	cable_machine
	•	adjustable_bench
	•	plate_olympic
	•	fat_grips

Key columns
	•	equipment_type_id (PK)
	•	name (unique)
	•	category (free_weight|machine|cardio|bodyweight|accessory)
	•	is_machine (0/1)
	•	notes, extra_json

Why this exists
This is the stable “capability vocabulary” used by exercise setups and matching.

⸻

equipment_model (concrete item)

Represents a specific implement or a generic “virtual” placeholder.

Key columns
	•	equipment_model_id (PK)
	•	name (e.g., “Rogue EZ Curl Bar” OR “Any EZ Curl Bar”)
	•	primary_type_id (FK to equipment_type)
	•	standard (optional; e.g., olympic_50mm vs standard_25mm)
	•	empty_weight (bars)
	•	fixed_weight (plates, dumbbells, kettlebells)
	•	weight_unit (kg/lb)
	•	attributes_json (e.g., rackable=true, grip_diameter_mm=28)
	•	is_virtual (0/1)

Virtual models
Virtual models let you record “I used a dumbbell” without specifying which dumbbell.
This supports bootstrapping and keeps logging friction low.

⸻

equipment_model_type (capabilities provided by a model)

A model can provide multiple capability types.

Example:
	•	A yoke might provide both yoke and squat_rack capability.

Columns
	•	equipment_model_id (FK)
	•	equipment_type_id (FK)
	•	composite PK (model_id, type_id)

⸻

gym_inventory

Tracks what a gym actually has (when you decide to enter it).

Key columns
	•	gym_id (FK)
	•	equipment_model_id (FK)
	•	quantity (>= 0)
	•	is_enabled (0/1) (handy for “machine is broken/busy” later)
	•	details_json (optional; can include location, notes, brand consistency)

Plates and dumbbells
This table naturally supports plate counts:
	•	model: “45 lb Olympic plate”, quantity: 10
	•	model: “25 lb Olympic plate”, quantity: 6
No special plate table needed.

⸻

gym_observed_equipment (bootstrapping)

Populated automatically from workout logs when a gym is known.

Key columns
	•	gym_id
	•	equipment_model_id
	•	first_seen_at, last_seen_at
	•	seen_count

How it’s used
	•	suggest “add to gym inventory” after it’s been seen enough times
	•	show “likely available equipment” even if inventory is incomplete

⸻

3) Exercise setups (how equipment enables exercises)

Exercises can be performed in different valid ways (setup variants).
This is why we use setups instead of trying to attach equipment requirements directly to exercises.

Example: “Skull crushers”
	•	Setup A: EZ bar + bench
	•	Setup B: Cable machine

exercise_setup

One exercise → many setups.

Key columns
	•	setup_id (PK)
	•	exercise_id (FK)
	•	name (human readable, “EZ bar + bench”)
	•	is_default (0/1)
	•	notes

⸻

setup_equipment_group

Each setup requires groups of equipment. Groups are combined using AND logic.

Key columns
	•	setup_id (FK)
	•	group_id (integer within setup)
	•	role (station|implement|load|attachment)
	•	is_required (0/1)
	•	prompt_user (0/1)
	•	description

Important concept
A setup is feasible if:
	•	for every is_required=1 group, at least one option in that group is available.

⸻

setup_equipment_option

Options inside a group are OR logic.

Key columns
	•	setup_id + group_id (FK to setup_equipment_group)
	•	equipment_type_id (FK to equipment_type)
	•	qty

Example
Setup: “EZ bar + bench”
	•	Group 1 (implement): options = {ez_curl_bar, short_straight_bar}
	•	Group 2 (station): options = {flat_bench, adjustable_bench}

⸻

session_item_equipment_choice (what was used today)

This records actual equipment usage without requiring full setup definition.

Key columns
	•	session_item_id (FK)
	•	role (station|implement|load|attachment)
	•	equipment_model_id (FK to equipment_model)

Bootstrapping behavior
If the user selects an implement and the session has a gym:
	•	upsert into gym_observed_equipment

⸻

4) Library ingestion (raw → parsed templates)

You want to keep every imported workout, even if parsing fails.

workout_source

Describes where workouts came from.

Key columns
	•	source_id (PK)
	•	kind (manual|file_import|link|third_party)
	•	title
	•	author
	•	original_url
	•	license_note
	•	imported_at

⸻

raw_workout

The canonical archive of imported workouts.

Key columns
	•	raw_workout_id (PK)
	•	source_id (FK)
	•	external_ref (filename, URL slug, etc.)
	•	workout_date (optional)
	•	raw_text (the original content)
	•	raw_format (markdown|plain|csv_row|...)
	•	parse_status (new|parsed|failed|needs_review)
	•	parsed_json (optional intermediate representation)
	•	linked_template_id (nullable FK to workout_template)
	•	imported_at

Why both raw and structured exist
	•	raw is your audit trail and future re-parser input
	•	templates are what you browse, schedule, and run

⸻

5) Workout programming (templates)

Templates represent “what is planned.”

workout_template

Key columns
	•	template_id (PK)
	•	name
	•	created_by_user_id (nullable)
	•	description
	•	intent_json (goal stimulus, target duration, etc.)
	•	created_at

Connections
	•	raw_workout.linked_template_id points to the structured version
	•	planned_workout.template_id schedules it

⸻

workout_block

Blocks are where stimulus mostly lives.

Key columns
	•	block_id (PK)
	•	template_id (FK)
	•	block_index (1..N)
	•	name (e.g., Strength / Metcon / Accessory)
	•	block_type (warmup|strength|conditioning|accessory|mobility|skill|other)
	•	structure_type (straight_sets|superset|circuit|amrap|emom|intervals|for_time|freeform)
	•	intent_json (time cap, rest rules, target stimulus)
	•	unique(template_id, block_index)

⸻

workout_item

Items reference exercises.

Key columns
	•	item_id (PK)
	•	block_id (FK)
	•	item_index (1..N)
	•	exercise_id (FK)
	•	prescription_type (reps|time|distance|mixed|freeform)
	•	sets (nullable)
	•	reps_target (nullable, exact)
	•	reps_min (nullable)
	•	reps_max (nullable)
	•	reps_is_per_side (0/1)
	•	time_sec_target (nullable)
	•	time_sec_min (nullable)
	•	time_sec_max (nullable)
	•	distance_m_target (nullable)
	•	distance_m_min (nullable)
	•	distance_m_max (nullable)
	•	pace_sec_per_m_target (nullable)
	•	pace_sec_per_m_min (nullable)
	•	pace_sec_per_m_max (nullable)
	•	prescription_json (non-rep details: load hints, intervals, etc.)
	•	notes

workout_item_set_prescription

Optional per-set prescriptions for complex schemes.

Key columns
	•	item_id (FK)
	•	set_index (1..N)
	•	prescription_type (reps|time|distance|mixed|freeform)
	•	reps_target (nullable)
	•	reps_min (nullable)
	•	reps_max (nullable)
	•	reps_is_per_side (0/1)
	•	time_sec_target (nullable)
	•	time_sec_min (nullable)
	•	time_sec_max (nullable)
	•	distance_m_target (nullable)
	•	distance_m_min (nullable)
	•	distance_m_max (nullable)
	•	pace_sec_per_m_target (nullable)
	•	pace_sec_per_m_min (nullable)
	•	pace_sec_per_m_max (nullable)

⸻

Tags (recommended for search + generator)

You’ll want tags early: “benchmark”, “upper-body”, “engine”, “15-min”, etc.

Minimal tag tables
	•	tag(tag_id, name UNIQUE, kind)
	•	entity_tag(tag_id, entity_kind, entity_id)
where entity_kind is template|exercise|raw_workout

⸻

6) Planning layer (schedule + goals)

user_goal

Key columns
	•	user_id (FK)
	•	goal_kind (strength|hypertrophy|conditioning|general)
	•	focus_muscles_json (array of muscle ids or names)
	•	sessions_per_week
	•	minutes_per_session
	•	notes

⸻

planned_workout

Represents planned training for a person on a date.

Key columns
	•	planned_id (PK)
	•	user_id (FK)
	•	date (YYYY-MM-DD)
	•	template_id (nullable)
	•	status (planned|skipped|done)
	•	generated_by (manual|generator_v1|...)
	•	notes

Connection to sessions
When a planned workout is performed:
	•	a workout_session is created with template_id
	•	you can add a planned_id FK later if you want a direct join (optional)

⸻

7) Execution layer (sessions + logs)

workout_session

Represents one completed workout event.

Key columns
	•	session_id (PK)
	•	user_id (FK)
	•	gym_id (nullable FK)
	•	template_id (nullable FK; sessions can be ad hoc)
	•	started_at, ended_at
	•	notes
	•	rpe (optional session-level effort)
	•	summary_json (overall time, rounds, etc.)

⸻

session_block

A performed block (copied from template, but can diverge).

Key columns
	•	session_block_id (PK)
	•	session_id (FK)
	•	template_block_id (nullable FK)
	•	block_index
	•	name, block_type, structure_type
	•	intent_json (what you intended for this block on that day)

Why this exists
	•	Stimulus questions happen at block boundaries.
	•	You can compare planned intent vs what happened.

⸻

session_item

A performed exercise instance inside a session.

Key columns
	•	session_item_id (PK)
	•	session_id (FK)
	•	session_block_id (nullable FK)
	•	exercise_id (FK)
	•	sequence (order performed)
	•	template_item_id (nullable FK)
	•	setup_id (nullable FK to exercise_setup)
	•	context_json (round number, interval segment, etc.)
	•	notes

⸻

set_log

The core log table. Works for strength, intervals, and simple cardio.

Key columns
	•	set_id (PK)
	•	session_item_id (FK)
	•	set_index (1..N)
	•	reps (nullable)
	•	weight (nullable)
	•	weight_unit (kg|lb, nullable)
	•	duration_sec (nullable)
	•	distance_m (nullable)
	•	calories (nullable)
	•	rpe (nullable)
	•	is_warmup (0/1)
	•	extra_json

How to use it
	•	Strength: reps + weight
	•	Intervals: duration_sec + distance_m
	•	Conditioning sets: reps only
	•	“One long run”: a single set row with duration + distance

⸻

8) Enrichment layer (stimulus, metrics, check-ins)

This layer is optional in MVP, but safe to add now.

Stimulus labeling

stimulus_type

Catalog of stimulus labels.

Examples:
	•	strength
	•	hypertrophy
	•	aerobic_base
	•	threshold
	•	vo2
	•	sprint
	•	skill
	•	mobility

stimulus_assignment

Attaches a stimulus label to exactly one target.

Key columns
	•	kind (planned|observed|inferred)
	•	stimulus_type_id (FK)
	•	one target FK:
	•	template_id OR block_id OR item_id OR session_id OR session_block_id OR session_item_id
	•	confidence (0..1)
	•	source (user|device|rule|model)
	•	model_version (lets you recompute later)
	•	notes, created_at

Planned vs observed vs inferred
	•	Planned: what you wanted
	•	Observed: user check-ins / sensor notes
	•	Inferred: computed after the fact (rules or ML)

⸻

Metrics (generic numeric values)

metric_type

Catalog of metric definitions.

Examples:
	•	avg_hr_bpm
	•	max_hr_bpm
	•	time_in_zone2_sec
	•	avg_power_w
	•	avg_pace_sec_per_km
	•	tonnage_kg

metric_value

Stores metric values attached to exactly one target:
	•	session
	•	session block
	•	session item
	•	set

Key columns
	•	metric_type_id
	•	value
	•	target FK (exactly one)
	•	optional start_ts, end_ts
	•	source (manual|device|imported|derived)
	•	created_at

⸻

Stimulus check-ins (quick questions)

block_checkin_response

Stores the tap-only answers captured at the end of a block.

Key columns
	•	session_block_id (FK)
	•	question_code (stable string like block_rpe, hardest_set_rir)
	•	answer_num (for scales)
	•	answer_choice (for single-choice)
	•	notes
	•	created_at
	•	unique(session_block_id, question_code)

How it connects
	•	Check-ins provide inputs for stimulus_assignment(kind='observed' or 'inferred')
	•	Check-ins can also influence substitutions later (e.g., “joint discomfort high”)

⸻

9) How the pieces work together (end-to-end flows)

Flow A — Import old workouts
	1.	Create workout_source(kind='file_import')
	2.	Create many raw_workout rows (always)
	3.	Parser attempts to create workout_template + blocks/items
	4.	If successful:
	•	link raw_workout.linked_template_id
	•	set parse_status='parsed'
	5.	If not:
	•	keep raw
	•	set parse_status='needs_review' or failed'

Key property: import never fails “hard.”

⸻

Flow B — Schedule workouts for your wife
	1.	Set user_goal for wife
	2.	Generator chooses templates by tags + intent_json (simple rules at first)
	3.	Insert planned_workout for each day

⸻

Flow C — Log a session
	1.	Create workout_session(user_id, template_id, gym_id)
	2.	Copy template blocks into session_block (optional but recommended)
	3.	For each exercise performed:
	•	create session_item(session_block_id, exercise_id, sequence)
	•	add set_log rows as needed
	4.	At end of each block:
	•	store 1–3 block_checkin_response rows
	5.	(Optional) derive:
	•	metric_value (tonnage, time, pace)
	•	stimulus_assignment(kind=‘inferred’)

⸻

Flow D — Bootstrap gym equipment from usage (optional)

When user selects an implement for a session item:
	1.	Insert session_item_equipment_choice(implement=equipment_model)
	2.	If session has gym_id:
	•	upsert gym_observed_equipment
	3.	Later UI/CLI can “promote” observed items into gym_inventory

⸻

Flow E — Substitutions

Given an exercise:
	1.	Use exercise_muscle similarity + movement_pattern matching
	2.	If a gym inventory is present:
	•	ensure candidate exercise has at least one feasible setup
	3.	Return ranked substitutes

⸻

10) MVP vs Later (what’s safe to skip early)

Required for MVP (minimum viable data loop)
	•	app_user, gym (optional)
	•	workout_source, raw_workout
	•	exercise, exercise_family, muscle_group, exercise_muscle (even rough weights)
	•	workout_template, workout_block, workout_item
	•	user_goal, planned_workout
	•	workout_session, session_item, set_log
	•	tags (recommended)

Optional (add when you’re ready)
	•	session_block (recommended once you add check-ins)
	•	exercise_setup + setup_equipment_* (needed for real substitution + equipment modeling)
	•	equipment_model + inventory + observed equipment
	•	stimulus + metrics tables
	•	block_checkin_response

The schema is designed so adding these later is additive, not destructive.

⸻


If you want, I can also add a second appendix with **canonical SQL DDL** (one file that defines every table in `CREATE TABLE` order), so your AI dev can implement `db/migrations/001_initial.sql` directly from it.
