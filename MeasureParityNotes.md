# Measure Parity Notes

This document tracks the ongoing effort to fix CQL measure test failures in this repo, why the
work is scoped the way it is, and the status of what's been found and fixed so far. It exists so
that work can resume across sessions (human or AI) without re-deriving context from scratch.

## Why this work exists

The repo is mid-migration from the QICore 6.0.0 model to the new US Quality Core (USQualityCore)
model (see `USQualityCoreUpdateProcess.md`). After that migration, the measure test suite regressed:
`scripts/comparison/discrepancy_report-main-2026-08-20.md` showed 61 of 74 measures failing (up
from 44/73 in the January pre-connectathon baseline).

**The goal is not "make the CQL logic correct" in the abstract — it's parity between two CQL
engines.** This repo's test fixtures encode *expected* results produced by MADiE's TypeScript CQL
engine, which is treated as the gold standard and currently passes 100% of these same test cases.
The *actual* results being compared come from the Java `cql-engine` (via the VS Code CQL extension
/ `clinical-reasoning`), which is what this repo's CI/tooling actually runs. A "discrepancy" is a
place where the Java engine's output diverges from MADiE's.

This reframes how to interpret every mismatch. For each one, decide which bucket it's in before
touching any code:

1. **Real CQL logic bug** — the CQL itself doesn't express the intended clinical logic, regardless
   of which engine runs it. Fix the CQL.
2. **Engine parity gap** — the two engines handle some construct differently (e.g. one engine
   implicitly excludes `doNotPerform=true` resources from a plain retrieve, the other doesn't), and
   the CQL needs to be more explicit to get identical behavior on both. Also fine to fix — being
   explicit is spec-compliant either way, not a workaround.
3. **Suspected MADiE quirk** — the Java engine may actually be more spec-correct here, and MADiE
   has a known behavior gap. Don't silently rewrite spec-correct CQL to match a MADiE quirk — flag
   it and check before changing anything.

Only fix category 1 and 2. Flag category 3 for a human decision rather than guessing.

## Verification loop

Three scripts, run in order from the repo root after CQL/fixture changes and a fresh CQL-engine
test run (`input/tests/results/*.txt` regenerated — this repo doesn't run that engine directly
from a shell tool; it's driven by the VS Code CQL extension / MADiE test harness):

```sh
python ./scripts/extract_population_expected.py   # only needed if MeasureReport expected results changed
python ./scripts/extract_population_actual.py      # re-run whenever input/tests/results/*.txt changes
python ./scripts/compare_results.py                 # regenerates scripts/comparison/discrepancy_report.md
```

See `scripts/readme.md` for details.

## Where to look

- **Discrepancy reports**: `scripts/comparison/discrepancy_report*.md` — per-measure pass/fail
  breakdown, including which population (Initial Population, Denominator, Numerator, Denominator
  Exclusion/Exception) mismatched, for which test-case GUID, expected vs. actual.
- **Per-test-case trace dumps**: `input/tests/results/<Measure>.txt` — a full dump of every CQL
  `define`'s computed value per test case, in roughly alphabetical-by-name order per patient block
  (blocks are separated by blank lines; `Patient=Patient(id=...)` appears partway through a block,
  not necessarily first — don't assume ordering, split on blank lines and read the whole block).
- **Test fixtures**: `input/tests/measure/<Measure>/<guid>/` — the FHIR resources for one test
  case, plus the expected `MeasureReport-*.json`. The `MeasureReport`'s
  `cqfm-testCaseDescription` extension often states the clinical intent in plain English — read it
  before assuming a mismatch is a bug.
- **Engine/translator source** (for anything that looks like an engine-level issue, not a CQL
  issue): `/Users/raleigh.thompson/projects/smile/vs-code-cql/_repo/clinical_quality_language`
  (cql-to-elm translator, cql-engine) and
  `/Users/raleigh.thompson/projects/smile/vs-code-cql/_repo/clinical-reasoning` (FHIR integration
  layer — retrieve providers, code extraction, model resolvers). The CQL language server's output
  channel (in VS Code) shows real translation/evaluation errors and stack traces that the
  `input/tests/results/*.txt` summary lines don't include.
- **ELM/AST**: the VS Code CQL extension can generate ELM (JSON/XML) and an AST view for any
  library — invaluable for confirming exactly what a CQL expression compiled to, rather than
  guessing from the source text.

## Change log

Every change attempted in this effort, in chronological order, with the reasoning behind it and
its outcome. Entries marked **KEPT** are in the working tree (uncommitted unless noted).
Entries marked **REVERTED** were tried, didn't resolve the issue, and were removed — the CQL/repo
state was confirmed clean via `git diff` after reverting. This section is meant to be detailed
enough to share with teammates or MADiE without needing to re-derive the reasoning.

### 1. Stale `onc` → `astp` profile namespace in test fixtures — KEPT, verified

- **Files**: 2,679 files under `input/tests/measure/`, across 12 measures (led by
  `CMS347FHIRStatinPreventionTxCVD` at 1,129 files, `CMS129FHIRProstCaBoneScanUse` at 459,
  `CMS69FHIRPCSBMIScreenAndFollowUp` at 316, plus `CMS56FHIRFuncStatHipReplacement`,
  `CMS90FHIRFSAforHeartFailure`, `CMS50FHIRReceiptofSpecialistReport`,
  `CMS68FHIRDocumentationCurrentMeds`, `CMS75FHIRChildrenDentalDecay`,
  `CMS74FHIRDentalCariesPrevention`, `CMS165FHIRControllingHighBP`,
  `NHSNGlycemicControlHypoglycemiaInitialPopulation`, `CMS135FHIRACEIorARBorARNIforHF`).
- **Why**: the IG renamed its US Quality Core profile namespace from
  `http://fhir.org/guides/onc/us-quality-core/...` to
  `http://fhir.org/guides/astp/us-quality-core/...`. `usqualitycore-modelinfo-0.1.0-cibuild.xml`
  and every `.cql` library had already moved to `astp` (confirmed 0 remaining `onc` references in
  either), but these 2,679 fixture files still had `meta.profile` and extension URLs on the old
  `onc` path. USQualityCore profile-typed retrieves (e.g. `[USQualityCore.Encounter: ...]`,
  `isEncounterPerformed()`) classify a resource by matching `meta.profile` against the model info's
  declared profile URL — a fixture on the stale URL silently fails that match and the retrieve
  returns empty, with no error.
- **Fix**: bulk find-and-replace `onc` → `astp` in the profile URL, scripted (not hand-edited).
- **Verified**: suite-wide pass rate 85.23% → 87.51% (fail count 3504 → 2962). Confirmed via a
  fresh test run + `compare_results.py`.

### 2. CMS1264FHIRECATREHQR default Measurement Period — KEPT, verified

- **File**: `input/cql/CMS1264FHIRECATREHQR.cql`.
- **Why**: 57 of 58 test cases failing (98%). The `"Measurement Period"` default was
  `Interval[@2026-01-01, @2027-01-01)`, a year behind this measure's own test fixtures (e.g. an
  encounter dated `2027-05-01`) and its expected `MeasureReport.period` (`2027-01-01`–
  `2027-12-31`). No test case in the repo carries a `Parameters` resource, so this CQL default is
  what actually executes — every other measure in the suite uses the 2026 default and has fixtures
  dated accordingly; CMS1264 alone was authored a year ahead without updating its default.
- **Fix**: changed the default to `Interval[@2027-01-01, @2028-01-01)`.
- **Verified**: moved CMS1264 into "Measures with No Discrepancies" — 58/58 pass.

### 3. Invalid UCUM system URI in 3 test fixtures — KEPT, verified

- **Files**:
  `input/tests/measure/CMS347FHIRStatinPreventionTxCVD/6da189af-7eb0-47b0-8c77-905944706aa1/Observation-dce97708-c832-464b-a62e-0f15142b6a10.json`,
  `input/tests/measure/CMS69FHIRPCSBMIScreenAndFollowUp/45b1ce40-0f49-4559-8c3b-5c2a8070b0a7/Observation-db3631fe-ff4a-47b7-8380-1d7e13bc119c.json`,
  `input/tests/measure/CMS69FHIRPCSBMIScreenAndFollowUp/7b34e64e-e7fe-402c-9a26-12da90662897/Observation-b13e9323-0c0c-445d-a7b0-d90dad09fc88.json`.
- **Why**: `valueQuantity.system` was `"https://ucum.org"` instead of the correct canonical UCUM
  system URI `"http://unitsofmeasure.org"` (used correctly 1,001 other times across the fixture
  set) — a data typo, not a CQL issue. Caused
  `FHIRHelpers.ToQuantity.InvalidFHIRQuantity: Invalid FHIR Quantity code: mg/dL` and showed up as
  4 "Missing Results" rows in CMS347 (one test case × 4 groups, since all 4 groups reference the
  same fixture).
- **Fix**: corrected all 3 to `http://unitsofmeasure.org`.
- **Verified**: the affected test cases moved from "Missing Results" (execution error) to either
  passing or a real, diagnosable mismatch.

### 4. CMS871FHIRHHHyper missing valueset — KEPT, verified (partially)

- **File added**:
  `input/vocabulary/valueset/external/ValueSet-2.16.840.1.113762.1.4.1196.394-20250227.json`.
- **Why**: `"Hypoglycemics Treatment Medications"`
  (`http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1196.394`) had no corresponding file
  in `input/vocabulary/valueset/external/`, causing `"Unable to locate ValueSet ..."`. Found a
  fully-expanded, correctly-formed copy already sitting in the IG Publisher's terminology cache
  (`input-cache/txcache/vs-4d4e1cfc-8e1d-45e5-ae0e-f62f71192e14.json` — 238 codes, version
  `20250227`) — evidently resolved once during a prior IG publish but never persisted into the
  repo's committed vocabulary source.
- **Fix**: copied the cached expansion into `input/vocabulary/valueset/external/`, matching the
  naming convention of sibling files (`id` field updated to include the date suffix, e.g.
  `2.16.840.1.113762.1.4.1196.394-20250227`).
- **Also determined** (no code change needed): CMS871's separate
  `"Invalid Interval - the ending boundary (0) must be greater than or equal to the starting
  boundary (1)"` error is a *downstream cascade* of the `Min()`/`DateTimeType` engine bug (see
  external issues below), not an independent defect —
  `hospitalDaysMax10()` (`CMS871FHIRHHHyper.cql:238-241`) calls `Min({...})`, which throws; the
  resulting garbage `Period` then breaks `daysInPeriod()`'s day-count construction
  (`USQualityCoreCommon.cql:219-225`).
- **Verified**: CMS871's missing-result count dropped (5 → 3, matching the number of test cases
  whose failure was solely the missing valueset, not the separate engine bug). The remaining
  failures trace to the external `Min()` issue, not this repo.

### 5. Comparison script — group-scoped denominator gating — KEPT, verified, repo-wide impact

- **File**: `scripts/extract_population_actual.py`,
  `validate_measure_population_counts()`.
- **Why**: for multi-stratum measures — CMS347 has 4 groups, each with its own `Denominator N`
  criteria expression, but *one shared* `Numerator` / `Denominator Exceptions` /
  `Denominator Exclusions` expression referenced by all 4 groups (confirmed directly from the
  Measure resource's population `criteria.expression` mapping in
  `input/resources/measure/CMS347FHIRStatinPreventionTxCVD.json`) — the script reported the raw
  shared boolean as the "actual" value for every group referencing it, without checking whether
  the patient was even a member of *that specific group's* denominator. Concretely: a patient in
  only `Denominator 3` was reported with `Denominator Exception Actual=1` for Groups 1, 2, and 4
  too, groups they were never in. The existing validation logic tried to handle this (there was
  already a `if not numer and not denom: denexc_count = 0` rule) but keyed off `numer`, which is
  *also* a shared, non-group-scoped value in this class of measure — so the rule silently failed to
  fire whenever the shared `Numerator` happened to be `true` from another group's perspective.
- **Fix**: added an explicit, unconditional gate — `if not denom_count: numer_count = numex_count
  = denex_count = denexc_count = 0` — evaluated *before* the existing (single-stratum-oriented)
  adjustment rules, since a patient who isn't in a group's own denominator can never belong to that
  group's numerator, exclusion, or exception population, full stop, regardless of what any shared
  expression says.
- **Verified**: `python ./scripts/extract_population_actual.py && python
  ./scripts/compare_results.py` — CMS347's mismatches dropped 134 → 74. Confirmed via a scripted
  diff against the prior report that CMS347 was the *only* measure in the current dataset whose
  counts changed — no regressions elsewhere. This fix is generic (not CMS347-specific); watch for
  it helping other multi-stratum measures as Phase 2 continues.
- **Discuss with MADiE**: this raises a real question worth asking their team — does MADiE's own
  scoring/reporting layer correctly scope shared exception/exclusion/numerator expressions to each
  group's own denominator for multi-stratum measures, or could they have a latent version of the
  same class of bug in a different place in their pipeline? Worth confirming given they're the
  reference implementation.

### 6. CMS347 CQL bugs: `doNotPerform` and an intent-code typo — KEPT, verified

- **File**: `input/cql/CMS347FHIRStatinPreventionTxCVD.cql`.
- **Why**: `"Statin Therapy Ordered during Measurement Period"` and
  `"Medication Active during the Measurement Period"` retrieved
  `[MedicationRequest: "... Statin Therapy"]` without excluding `doNotPerform = true` records. A
  `MedicationRequest` profiled as `us-quality-core-medicationnotrequested` — i.e. an explicit
  "do NOT perform, contraindicated" record, which is the *correct* representation for a
  denominator-exception case — was being double-counted as an actual statin order, wrongly
  flipping `Numerator` to `true` and suppressing the intended `Denominator Exception`.
  Root-caused via one concrete failing test case (`8b0f2e04-...`, description: "no high statin
  prescribed d/t contraindicated") whose `MedicationRequest` fixture has `"doNotPerform": true`.
  Confirmed `doNotPerform` is a declared element on `USQualityCore.MedicationRequest` in the model
  info, and that this "regular request vs. negation request" distinction is an established pattern
  elsewhere in the repo (`NHSNAcuteCareHospitalMonthlyInitialPopulation1.cql`'s
  `// doNotPerform is false or absent` comments). Also found a typo, `'filter-order'`, which should
  be the real FHIR `MedicationRequest.intent` code `'filler-order'` (confirmed against the correct
  spelling used in `AHAOverall.cql`).
- **Fix**: added `and ( StatinRequest.doNotPerform is null or not StatinRequest.doNotPerform )`
  (and the `ActiveStatin` equivalent) to both retrieves' `where` clauses; fixed the typo.
- **Verified**: CMS347's mismatches dropped 74 → 53 after a fresh test run.

### 7. CMS347 (and 3 other measures) test fixtures reference the wrong patient — KEPT, pending re-verification

- **Files**: 40 resource files fixed — 34 in `CMS347FHIRStatinPreventionTxCVD`, 3 in
  `CMS72FHIRSTKAntithromboticDay2`, 1 in `CMS108FHIRVTEProphylaxis`, 1 in
  `NHSNGlycemicControlHypoglycemiaInitialPopulation`.
- **Why**: of the remaining 53 CMS347 mismatches, every one still showing an
  Initial-Population/Denominator-level discrepancy traced to a resource (`Condition`, `Encounter`,
  `Observation`, `MedicationRequest`, `Procedure`, or `ServiceRequest`) whose `subject.reference`
  pointed at a *different* patient GUID than the one whose test-case folder it lived in — so the
  CQL, scoped to `context Patient`, correctly never saw that resource at all for the intended test
  case. Confirmed by scanning every resource in every test case folder for every measure and
  comparing `subject.reference` against that folder's own `Patient-<guid>.json`: 40 files across 4
  measures had a mismatch. These are data-authoring typos, not CQL bugs — one was a stray leading
  `d` character (`Patient/d759a89b4-...` instead of `Patient/759a89b4-...`), another had a literal
  embedded double-space splitting a GUID in half (`Patient/1d3021bb-b593-4efc-af5b-3  20243bbe9b7`).
  Each test case folder is self-contained with exactly one `Patient-*.json`, so the correct
  reference is unambiguous in every case.
- **Fix**: mechanically corrected each mismatched `subject.reference` to point to its own folder's
  patient GUID. Validated all touched files remain syntactically valid JSON afterward.
- **Verified**: CMS347's mismatches dropped 53 → 48 after a fresh test run. Fewer than the 34
  fixed references might suggest, because fixing a reference sometimes only revealed a *further*,
  separate issue for that same test case rather than making it pass outright (see #8 below — most
  of the newly-exposed failures turned out to be the shared-library parameter-default bug, not
  something wrong with the reference fix itself). `CMS72FHIRSTKAntithromboticDay2`,
  `CMS108FHIRVTEProphylaxis`, and `NHSNGlycemicControlHypoglycemiaInitialPopulation` showed no
  count change — their single fixed files weren't the cause of those measures' reported
  mismatches, but the references were still wrong and worth having fixed regardless.

### 8. Shared libraries missing a default `"Measurement Period"` — SUPERSEDED by #9 below

- **Files (original fix, since superseded)**: `input/cql/PalliativeCare.cql`,
  `input/cql/Hospice.cql`, `input/cql/AdvancedIllnessandFrailty.cql`.
- **Why**: after fix #7 above, 13 CMS347 mismatches remained, and their test-case descriptions
  were overwhelmingly palliative-care- or hospice-related (9 palliative-care cases spanning *all
  four* of `PalliativeCare.cql`'s OR-branches — Condition diagnosis, Encounter, Procedure, and the
  FACIT-Pal Assessment — plus 2 hospice cases). Checked each palliative-care case's underlying data
  individually (codes, valueset membership, dates, `.verified()`/`.isEncounterPerformed()` helper
  functions) and found nothing wrong with any of it. The one thing common to *every* branch of
  *both* libraries: `PalliativeCare.cql` and `Hospice.cql` both declare
  `parameter "Measurement Period" Interval<DateTime>` with **no default value**, unlike every
  other shared library that had one at the time (`AHAOverall.cql`, `CQMCommon.cql`, `VTE.cql`,
  `PCMaternal.cql`, `TJCOverall.cql`, `AdultOutpatientEncounters.cql`, `Antibiotic.cql`) and every
  measure — if the test harness doesn't propagate the calling measure's parameter value into an
  included library, `"Measurement Period"` would evaluate to `null` inside these two libraries,
  breaking every date-scoped check in them uniformly. `AdvancedIllnessandFrailty.cql` had the same
  gap, fixed preemptively.
- **Original fix (now removed, see #9)**: added the standard default to all three files.
- **Superseded**: you pointed out the harness actually supports parameters via
  `input/tests/config.json` (global and library/test-case-scoped), which is the better long-term
  fix — one source of truth instead of ~80 duplicated per-file defaults that can drift. See #9.
  The root-cause diagnosis above (missing default → null parameter → uniform failure) is still the
  reason this mattered; only the *fix location* changed.

### 9. Centralized `"Measurement Period"` via `input/tests/config.json`; removed all per-file CQL defaults — KEPT, pending re-verification

- **Files**: `input/tests/config.json`, plus all 82 `.cql` files that declare a
  `"Measurement Period"` parameter (every measure, plus `AHAOverall`, `CQMCommon`, `VTE`,
  `PCMaternal`, `TJCOverall`, `AdultOutpatientEncounters`, `Antibiotic`, `AdvancedIllnessandFrailty`,
  `Hospice`, `PalliativeCare`).
- **Why**: fix #8 (and CMS1264's earlier fix #2) worked by editing CQL defaults directly, but that
  meant the actual measurement period was duplicated across ~85 files with no single source of
  truth, and — as #8 demonstrated — easy to silently omit in a shared library. The CQL test
  harness supports parameter injection via `input/tests/config.json`, with global, library-scoped,
  and test-case-scoped entries (merge priority: global → library → test case; see
  `.vscode/extensions/cqframework.cql-0.9.9/schemas/cql-config.schema.json` for the schema). Moving
  to this makes the measurement period a single, explicit, version-controlled setting instead of
  an implicit convention repeated in every file.
- **Found and fixed two format bugs in the existing global entry** before proceeding: it was named
  `"MeasurementPeriod"` (no space) with type `"Interval<Date>"` and a date-only literal
  (`Interval[@2026-01-01, @2027-01-01)`), none of which match the CQL declarations
  (`parameter "Measurement Period" Interval<DateTime>`, used with full `DateTime` literals
  everywhere in the repo). Corrected the global entry's `name`/`type`/`value` to match exactly.
- **Added two library-scoped overrides** for the libraries whose correct measurement period
  genuinely differs from the global default (confirmed by checking their own test fixtures/expected
  results, not just their CQL default):
  - `CMS1264FHIRECATREHQR` → `Interval[@2027-01-01T00:00:00.000Z, @2028-01-01T00:00:00.000Z)`
    (matches fix #2 above — this measure's fixtures are dated a year later than everything else).
  - `NHSNAcuteCareHospitalMonthlyInitialPopulation1` → `Interval[@2026-01-01T00:00:00.000Z,
    @2026-02-01T00:00:00.000Z)` (a 1-month window — this is an NHSN *monthly* measure, intentionally
    not annual; its CQL default was already correctly a 1-month period, unlike everything else).
- **Fix**: commented out the `default Interval[...]` line in all 82 files with a note
  (`// Measurement Period default removed; value is now supplied via input/tests/config.json`),
  leaving `parameter "Measurement Period" Interval<DateTime>` declared with no default (valid CQL
  — the parameter becomes required at runtime instead). Left `AdultOutpatientEncounters.cql`'s
  slightly-differently-formatted default (`[@2026-01-01T00:00:00, @2026-12-31T23:59:59]` — no `Z`
  suffix, closed interval) commented out the same way rather than adding an override, since it's
  functionally equivalent to the global default (off by under a second, not a real behavioral
  difference). 5 shared libraries (`AlaraCommonFunctions`, `NHSNHelpers`, `Status`,
  `SupplementalDataElements`, `USQualityCoreCommon`) don't declare this parameter at all and were
  left untouched.
- **Status**: not yet verified against a fresh test run. This is the highest-leverage open item —
  it determines whether the harness actually propagates config.json parameters into every library
  in the dependency graph (the working theory behind fix #8) or whether something else is going
  on. **If measures regress after this change** (i.e. things that were passing before now fail),
  that's decisive evidence the harness does *not* reliably propagate parameters the way assumed,
  and the per-file defaults may need to come back for libraries the harness doesn't reach.

## Tried and reverted (did not resolve the issue)

### CMS135FHIRACEIorARBorARNIforHF — two independent CQL rewrite attempts, both reverted

- **Symptom**: `"Unable to extract codes from fhirType Reference"`, causing 3 test cases to be
  reported as "Missing Results" (no MeasureReport population values at all).
- **Root cause hypothesis (turned out incomplete)**: `"Has ACEI or ARB or ARNI Ordered"` /
  `"Is Currently Taking ACEI or ARB or ARNI"` used
  `[MedicationRequest: medication in "ACE Inhibitor or ARB or ARNI"]`.
  `MedicationRequest.medication` is a FHIR choice type (`CodeableConcept | Reference(Medication)`),
  and the 3 failing fixtures legitimately use `medicationReference` (pointing to a separate
  `Medication` resource whose `.code` holds the actual coding) rather than
  `medicationCodeableConcept` — a valid, spec-compliant representation that a naive
  terminology-filtered retrieve can't auto-resolve.
- **Attempt 1**: rewrote both `define`s to retrieve unfiltered `[MedicationRequest]` and branch
  explicitly with an inline `if medication is FHIR.CodeableConcept then ... else exists([FHIR.Medication] ... where (medication as FHIR.Reference).references(...))`,
  matching a working precedent already in the repo (`CQMCommon.cql`'s `GetMedicationCode`).
  **Result**: byte-identical error, same 3 test cases, no change whatsoever.
- **Attempt 2**: rewrote again with an explicit `is FHIR.Reference` guard (not just the complement
  of the CodeableConcept check) and moved the valueset filter onto the `Medication.code` retrieve
  bracket (`[FHIR.Medication: "..."]` — safe, since `Medication.code` is always plain
  `CodeableConcept`, never a choice type). **Result**: still byte-identical error, same 3 test
  cases.
- **Decisive evidence neither attempt could have worked**: in both re-runs, the error blocks in
  `input/tests/results/CMS135FHIRACEIorARBorARNIforHF.txt` were **completely empty** — no
  `Patient=`, no `Initial Population=`, nothing printed at all for these 3 test cases — meaning the
  failure happens before any CQL `define` evaluates, not inside the code being rewritten.
- **Investigated further using the actual engine/translator source**
  (`/Users/raleigh.thompson/projects/smile/vs-code-cql/_repo/clinical_quality_language` and
  `.../clinical-reasoning`): traced the exact throw site to `CodeExtractor.getCodesFromBase` in
  `cqf-fhir-cql`. Generated the real ELM for attempt 2 and cross-referenced it against
  `InValueSetEvaluator.kt`, `AsEvaluator.kt`/`IsEvaluator.kt`, and `FhirModelResolver.kt` — the
  generated logic is spec-compliant and null-safe at every step (`As` with `strict=false` returns
  `null` on a type mismatch rather than throwing; `FHIRHelpers.ToConcept` and
  `InValueSetEvaluator` both null-check before touching codes; `FhirModelResolver.toCqlValue()`
  tags values by their actual runtime Java class, so `Reference` vs. `CodeableConcept`
  discrimination should be correct). Nothing in the ELM explains the crash.
- **Also tried**: the CQL language server's VS Code output channel showed
  `ERROR RepositoryFhirModelInfoProvider Unable to locate model info content for USCore` — a real,
  separate gap (no local `uscore-modelinfo-*.xml` exists in `input/cql/`, unlike `USQualityCore`,
  which has one vendored). Found a `uscore-modelinfo-6.1.0-derived.xml` of **unconfirmed
  provenance** elsewhere on disk (it "just appeared" via other tooling; not sourced from a verified
  authoritative location) and copied it into `input/cql/` as a reversible experiment.
  **Result**: no change, identical error persisted. Removed the file afterward (never committed).
- **Final state**: both CQL rewrites reverted; `CMS135FHIRACEIorARBorARNIforHF.cql` confirmed
  byte-identical to the committed original via `git diff`. **Tabled** — needs an actual JVM stack
  trace (debugger breakpoint on the exception, or increased engine log verbosity) to make further
  progress; static analysis of CQL, ELM, and engine source is exhausted.

### CMS165FHIRControllingHighBP — investigated, no fix attempted, tabled

- **Symptom**: same error string as CMS135, `"Unable to extract codes from fhirType Reference"`.
- **Investigation**: bisected the one failing test case (`43efb820-9e6e-4180-9a4d-2d7459896e5f`)
  down to its full fixture bundle — just `Patient`, `Condition`, `Encounter`, `Observation`, no
  `MedicationRequest`/`ServiceRequest`/any other `Reference`-bearing resource at all. Confirmed
  this is **not** the same medication-choice-type cause as CMS135. Searched CMS165's own CQL and
  its shared includes (`AdultOutpatientEncounters`, `Hospice`, `PalliativeCare`,
  `AdvancedIllnessandFrailty`, `SupplementalDataElements`) for any other `Reference`-typed
  code-extraction site — found none.
- **Final state**: no CQL change attempted (no credible hypothesis to test). Tabled alongside
  CMS135, pending the same stack-trace diagnostic.

## External issues log (not fixable in this repo — track, don't chase with more CQL rewrites)

- **`Min()`/`DateTimeType` — likely cql-engine gap.** `Min({...})` over a homogeneous set of plain
  `DateTime` values throws `"... not comparable"` / `"... not implemented"`. Per the CQL spec,
  `DateTime` is an explicitly supported `Min`/`Max` operand type, so this looks like a genuine
  engine limitation, not a CQL mistake. Affects `CMS645FHIRBoneDensityPCADTherapy`,
  `CMS646FHIRIntravesicalBCGTherapy`, `CMS156FHIRHighRiskMedsElderly`, `CMS871FHIRHHHyper`,
  `CMS1173FHIRDiagnosticDelayVTE`. Not reshaping correct CQL to route around it — file upstream if
  this gets prioritized.
- **Ambiguous overload resolution — likely cql-to-elm gap.** `USQualityCoreCommon.cql` defines
  `recorded(Procedure)` and `recorded(ProcedureNotDone)` as separate overloads; since
  `ProcedureNotDone` derives from `Procedure`, calling `.recorded()` on a `ProcedureNotDone` value
  is structurally ambiguous to this translator version instead of resolving to the more specific
  overload. Surfaced in `CMS68FHIRDocumentationCurrentMeds` once its retrieve started actually
  matching data (after fix #1 above).
- **CMS135/CMS165's `"Unable to extract codes from fhirType Reference"`** — see "Tried and
  reverted" above. Leaning external but not confirmed; needs a stack trace before filing anything.

## Not yet started

- **CMS145FHIRCADBBlockerTPMIorLVSD / CMS149FHIRDementiaCognitiveAssess** — no CQL source exists
  at all (confirmed via `find` and `git log`), despite full Measure resources and test fixtures
  existing. This is a content-authoring gap (139 test cases), materially larger than anything else
  here — scope as its own follow-up, likely via `/madie`, `/cql`, `/qicore` skills.
- The remaining ~52 measures with measure-specific mismatches, one at a time, top-down by fail
  count from the latest discrepancy report.
