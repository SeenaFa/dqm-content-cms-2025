# Measure Parity Notes

This document tracks the ongoing effort to fix CQL measure test failures in this repo, why the
work is scoped the way it is, and the status of what's been found and fixed so far. It exists so
that work can resume across sessions (human or AI) without re-deriving context from scratch.

## Why this work exists

The repo is mid-migration from the QICore 6.0.0 model to the new US Quality Core (USQualityCore)
model (see `USQualityCoreUpdateProcess.md`). After that migration, the measure test suite regressed:
`scripts/comparison/discrepancy_report-main-2026-08-20.md` showed 61 of 74 measures failing (up
from 44/73 in the January pre-connectathon baseline).

**RESOLVED 2026-08-21 (confirmed with another dev): this is NOT an engine-parity comparison
exercise.** The project is scoped purely around correctly converting QICore → USQualityCore — we
are *not* comparing our results against MADiE. The framing below (the "category 1/2/3" bucketing,
treating MADiE's TypeScript engine as a gold standard to match) was this document's original
working theory and is now superseded — kept struck through/inline for history, but do not apply it
to new work. It also resolves the "Open question" that used to live here: every mismatch found so
far (#6 `doNotPerform`, #7/#11 wrong patient references, #10/#15 `.onset.toInterval()` vs
`.prevalenceInterval()`, #13 `doNotPerform` again, #14 missing `Claim.item` links, #16/#18) was a
genuine migration regression, not an engine difference — confirmed by the dev conversation, not
just inferred.

**What this means practically going forward:**

- The correctness question for any mismatch is now: **does the USQualityCore-converted CQL
  correctly reproduce the pre-migration QICore CQL's intended logic?** — not "does it match what
  the Java engine vs. MADiE's engine each produce."
- `dqm-content-qicore-2025` (`https://github.com/cqframework/dqm-content-qicore-2025`, see the
  memory note saved 2026-08-21) is the actual ground truth to diff a measure's `define`s against
  when in doubt — not the test fixtures' expected `MeasureReport` values in isolation. If a fix
  looks right by CQL-authoring convention but the QICore original did something different on
  purpose, that's worth a second look before applying it.
- The `input/tests/measure/*/MeasureReport-*.json` "expected" values and `cqfm-testCaseDescription`
  extensions still describe real clinical intent and remain useful for understanding what a test
  case is trying to exercise — just don't treat "the Java engine disagrees with the fixture" as
  automatically meaningful the way the old category-2/3 framing did. The comparison scripts
  (`scripts/comparison/compare_results.py` etc.) are still a reasonable coverage signal for "did
  this fix change what I expected," just not evidence about engine correctness.
- No more "flag category 3, don't touch it" — since there's no second engine's behavior to defer
  to, a mismatch that looks like a genuine CQL bug should just be fixed (verified against the
  QICore source when the fix is non-obvious), not parked pending a human call about MADiE.

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
- **Status**: **VERIFIED — confirmed correct, large repo-wide win.** Fresh test run
  (`discrepancy_report-measure-fixes-20260821-1128.md`) vs. the prior report: fail count
  2804 → 2344 (460 fewer failing test cases), measures with any discrepancy 60 → 46 (14 more
  measures now fully passing), **zero regressions** (scripted diff confirmed no measure's
  mismatch count went up). 22 measures improved, most down to 0 mismatches — including several
  that had been stuck since Phase 0/1 (`CMS138FHIRTobaccoScrnCessation`,
  `CMS125FHIRBreastCancerScreen`, `CMS122FHIRDiabetesAssessGT9Pct`,
  `CMS136FHIRChildADHDMedFollowUp`, `CMS130FHIRColorectalCancerScrn`, and more). This confirms the
  harness *does* propagate `config.json` parameters into every library in the dependency graph,
  and that the root-cause diagnosis in #8 (missing/null `"Measurement Period"` breaking
  `Hospice.cql`/`PalliativeCare.cql`/`AdvancedIllnessandFrailty.cql` uniformly) was correct.
  `CMS347FHIRStatinPreventionTxCVD` alone dropped from 48 → 4 mismatches; the 4 remaining are
  distinct, unrelated issues (see next entry), not more instances of this bug.

### 10. CMS347 — 4 lingering, unrelated mismatches (not fixed, parking here)

Not fixed in this pass — noted for whoever picks CMS347 back up. Each is independent; none are
more instances of the config.json fix (#9) or of each other.

- **`"Has Diabetes Diagnosis"` (and likely `"Has ESRD Diagnosis"`, identical pattern) date-window
  bug** — affects test cases `8927dd81-b976-4b7f-a78c-c4215ee8fc9a` and
  `5e65bf6d-6518-44d7-a827-821b59b00cc0`. `input/cql/CMS347FHIRStatinPreventionTxCVD.cql:149-153`
  (`"Has Diabetes Diagnosis"`) uses `DiabetesDiagnosis.onset.toInterval() overlaps day of
  "Measurement Period"`. For a plain `onsetDateTime` (not a `Period`), `.toInterval()` produces a
  zero-width point interval, so a diagnosis with an onset date *before* the measurement period
  (e.g. `2022-12-31`, `clinicalStatus: active`, no abatement) can never "overlap" a 2026 period,
  even though it's an ongoing chronic condition that should count. Compare to
  `"ASCVD Diagnosis or Procedure before End of Measurement Period"` elsewhere in the same file,
  which correctly uses `"starts on or before day of end of Measurement Period"` for this exact
  "diagnosed at any point up through now, still active" pattern.
  `"Has ESRD Diagnosis"` (line 156) uses the identical `overlaps` pattern and is likely affected
  the same way, though not yet confirmed against a failing test case.
- **Allergy-to-statin exception not matching — FIXED, see #11 below.** Was a fixture bug (wrong
  `AllergyIntolerance.patient` reference), not a CQL issue.
- **`"Denominator Exclusions"` matches a resolved/inactive diagnosis** — test case
  `695b64d8-8102-4109-89c2-9ca128d43f4d` (description: "rhabdomyolysis dx last day of prior year
  but no longer 'active' in the MP"), `Denominator Exclusion` expected `0`, actual `1`.
  `input/cql/CMS347FHIRStatinPreventionTxCVD.cql:96-103` (`"Denominator Exclusions"`) checks
  `ExclusionDiagnosis.onset.toInterval() overlaps day of "Measurement Period" and
  ExclusionDiagnosis.isVerified()` but never checks `clinicalStatus` — so a diagnosis that's
  resolved/inactive by the time the measurement period starts still counts as an exclusion. Not
  yet fixed.

### 11. Wrong-patient references in `Claim`/`Coverage`/`AllergyIntolerance` fixtures across 7 measures — KEPT, pending re-verification

- **Files**: 188 fixture files total —
  97 `Claim-*.json` in `CMS72FHIRSTKAntithromboticDay2`, 70 in `CMS104FHIRSTKDCAntithrombotic`,
  2 each in `CMS108FHIRVTEProphylaxis`/`CMS190FHIRVTEProphylaxisICU`, 1 each in
  `CMS1028FHIRPCSevereOBComps`/`CMS1264FHIRECATREHQR`/`CMS71FHIRSTKAnticoagAFFlutter`;
  14 `Coverage-*.json` (`beneficiary` field) across `CMS347`, `CMS104`, `CMS71`; and 1
  `AllergyIntolerance-*.json` (`patient` field) in `CMS347` (the "allergy to statin" case from
  #10, now resolved).
- **Why**: diagnosing `CMS72FHIRSTKAntithromboticDay2` (98 of 158 mismatches, almost all
  `Initial Population` itself failing). Traced the call chain:
  `"Initial Population"` → `TJC."Ischemic Stroke Encounter"` →
  `"Non Elective Inpatient Encounter With Age"` →
  `NonElectiveEncounterWithAge.hasPrincipalDiagnosisOf("Ischemic Stroke")`
  (`input/cql/TJCOverall.cql:36-43`) → `hasPrincipalDiagnosisOf()` / `principalDiagnosis()` /
  `claimDiagnosis()` (`input/cql/CQMCommon.cql:406-428`) — this pattern (from the QICore
  "Principal Diagnosis and Present on Admission" authoring convention) requires a FHIR `Claim`
  resource with a `diagnosis[].type` of `"principal"` linked to the encounter, not just a
  `Condition`. Every affected fixture *has* a correctly-formed `Claim` (right diagnosis code,
  right `sequence`, right `type: principal`) — but `Claim.patient.reference` pointed to one of two
  fixed placeholder GUIDs (`d170a0a8-b5ad-4303-b6df-e304dd5f92ad` or
  `5450abfd-a667-4eb9-9b59-e85feed4865c`) instead of the test case's own patient. Confirmed via
  `find`/`ls` that **neither placeholder GUID exists as an actual test case anywhere in the
  repo** — these are template-generation artifacts (a fixed placeholder patient reference in
  whatever template produced these `Claim` resources, never replaced with the real per-test-case
  patient ID), not sibling-record mix-ups like the CMS347 `subject.reference` bug in #7. Given
  this, swept the *entire* `input/tests/measure/` tree for the same pattern on every
  patient-identity field this repo's resources actually use (`subject`, `patient`, `beneficiary`)
  and fixed everything found, not just CMS72.
- **Fix**: same mechanical correction as #7 — each `Claim`/`Coverage`/`AllergyIntolerance`'s
  patient-identity reference set to `Patient/<its own folder's GUID>`. All touched files validated
  as syntactically correct JSON afterward.
- **Expected impact**: `CMS72`'s fix count (97) almost exactly matches its 98 mismatches, and
  `CMS104`'s (70) almost exactly matches its 69 mismatches (our current #1 and #2 Phase 2
  priorities) — high confidence both largely resolve. Smaller counts in `CMS108`, `CMS190`,
  `CMS1028`, `CMS1264`, `CMS71` may fix 1-2 mismatches each or may be incidental (not yet cross-
  checked against those measures' specific failing test cases).
- **Status**: **VERIFIED.** Fresh test run (`discrepancy_report-measure-fixes-20260821-1159.md`)
  vs. the prior report: fail count 2344 → 1954 (390 fewer), **zero regressions** (scripted diff
  confirmed). `CMS72FHIRSTKAntithromboticDay2` 98 → 13, `CMS104FHIRSTKDCAntithrombotic` 69 → 15 —
  both closely matching the predicted impact. `CMS108FHIRVTEProphylaxis` 23 → 21,
  `CMS190FHIRVTEProphylaxisICU` 26 → 24, `CMS1028FHIRPCSevereOBComps` 4 → 2,
  `CMS347FHIRStatinPreventionTxCVD` 4 → 3 (the allergy-to-statin case resolved, as expected).

### 12. CMS72 `.effective` not converted to an interval before date comparison — KEPT (CMS72 only); CMS190's identical fix REVERTED after a regression

- **File**: `input/cql/CMS72FHIRSTKAntithromboticDay2.cql:132`.
- **Why**: diagnosing CMS72's 8 remaining pure `Denominator Exception` misses (of 13 left after
  #11). `"Reason For Not Administering Antithrombotic"` returns a tuple
  `{ id: ..., authoredOn: MedicationAdm.effective }`, unioned with a sibling branch
  (`"Reason For Not Ordering Antithrombotic"`) whose `authoredOn` is
  `NoAntithromboticOrder.authoredOn` — a plain `FHIR.dateTime`. But
  `MedicationAdministration.effective` is a choice type (`dateTime | Period`), and unlike every
  other Period/dateTime comparison in this codebase, it was never converted via `.toInterval()`
  before being compared with `NoAntithrombotic.authoredOn during day of (...)`. Confirmed the
  affected fixture uses `effectivePeriod` (not `effectiveDateTime`).
- **Fix**: changed to `start of MedicationAdm.effective.toInterval ( )`, matching the established
  convention used everywhere else in this codebase for Period/dateTime choice fields.
- **Verified**: CMS72 improved 13 → 9 in the next test run, consistent with this fix working.
- **CMS190 — REVERTED, do not reapply without further investigation.** Found the identical
  textual pattern in `CMS190FHIRVTEProphylaxisICU.cql:302`
  (`authoredOn: NoMedicationAdm.effective`, inside `"No VTE Prophylaxis Medication Administered Or
  Ordered"`, also `union`'d with sibling branches whose `authoredOn` is plain `FHIR.dateTime` —
  structurally identical to CMS72's case) and applied the same fix. Result: **CMS190 regressed
  24 → 28 mismatches**, almost all newly-broken `Numerator` cases (a population this specific
  `define` doesn't even feed into directly — it feeds `Denominator Exclusion`/`Exception` via
  `"No VTE Prophylaxis Medication Due To Medical Reason ..."`), no engine errors logged. Reverted
  immediately (confirmed clean via `git diff`) rather than dig further, since the safety signal
  was unambiguous and this was the only change touching CMS190 that test run. Root cause of *why*
  a seemingly-safe, spec-aligned fix caused this is **not understood** — the leading theory (type
  mismatch across `union`'d tuple shapes when one branch's `authoredOn` becomes `System.DateTime`
  while siblings stay `FHIR.dateTime`) doesn't fully hold up, since CMS72 has the *identical*
  structural pattern and did not regress. Do not blindly reapply this fix to CMS190 (or assume
  CMS72's fix is definitely safe long-term, since it shares the same risky pattern) without a real
  stack trace or more careful before/after diffing of *all* CMS190 test case results, not just the
  summary counts.
- **Revert verified clean.** Next test run: CMS190 28 → 24 (exactly back to its pre-regression
  count), and it was the *only* measure that changed — confirms the revert was correctly isolated
  with no other side effects.

### 13. CMS104 Numerator missing `doNotPerform` check — KEPT, pending re-verification

- **File**: `input/cql/CMS104FHIRSTKDCAntithrombotic.cql:43-56`.
- **Why**: 9 of CMS104's 15 remaining mismatches (after #11) showed the exact
  `Denominator Exception Expected=1/Actual=0, Numerator Expected=0/Actual=1` signature as the
  CMS347 `doNotPerform` bug (#6). Confirmed: `"Numerator"`'s `["MedicationRequest": "Antithrombotic
  Therapy for Ischemic Stroke"]` retrieve never checked `doNotPerform`, so a discharge
  `MedicationRequest` explicitly marked "do NOT perform, contraindicated" (profile
  `us-quality-core-medicationnotrequested`, `doNotPerform: true`) was being double-counted as an
  actual discharge order. Checked CMS72's analogous `"Numerator"` for the same gap — it retrieves
  `[MedicationAdministration: ...]` with an explicit `status in {'in-progress','completed'}`
  filter, which already excludes `not-done`-status records, so no fix needed there.
- **Fix**: added `and ( DischargeAntithrombotic.doNotPerform is null or not
  DischargeAntithrombotic.doNotPerform )` to the Numerator's `such that` clause.
- **Watch list, not yet fixed**: a repo-wide grep for `[MedicationRequest: ...]` retrieves
  combined with an `'active', 'completed'` status filter but no `doNotPerform` check nearby found
  12 candidate measures that may have the same latent bug, unconfirmed against actual failing
  test data: `CMS1017FHIRHHFI`, `CMS108FHIRVTEProphylaxis`, `CMS1173FHIRDiagnosticDelayVTE`,
  `CMS190FHIRVTEProphylaxisICU`, `CMS22FHIRPCSBPScreeningFollowUp`,
  `CMS2FHIRPCSDepScreenAndFollowUp`, `CMS506FHIRSafeUseofOpioids`,
  `CMS645FHIRBoneDensityPCADTherapy`, `CMS646FHIRIntravesicalBCGTherapy`,
  `CMS71FHIRSTKAnticoagAFFlutter`, `CMS72FHIRSTKAntithromboticDay2` (already checked, not
  affected), `CMS996FHIRAptTxforSTEMI`. Don't blindly patch these — verify against a real failing
  test case first, the way #6 and this entry were confirmed.
- **Status**: **VERIFIED.** CMS104 improved 15 → 7 in the next test run, consistent with this fix
  (plus #14's one `Claim.item` fix) working.

### 14. `Claim.item` missing `.encounter`/`.diagnosisSequence` links — 1 of 22 fixed, 21 remaining (new category, needs follow-up)

- **Why**: diagnosing CMS104's remaining IP-level mismatches (test case
  `0b1aa8ee-e8bf-49f5-b968-48c5a9702843`, description "Testing do not perform not true"). Unlike
  #7/#11 (wrong `patient`/`beneficiary` reference), this `Claim`'s `patient.reference` was
  correct, but its `item[0]` had **no `encounter` field and no `diagnosisSequence` field at all**.
  `claimDiagnosis()` (`input/cql/CQMCommon.cql:415-421`) requires
  `exists (C.item I where I.encounter.references(E))` to even find the claim, and then
  `claimItem.diagnosisSequence` to select which diagnoses apply — with both missing, the whole
  principal-diagnosis chain (and therefore `Initial Population`) silently resolves to empty for
  that test case, same end symptom as the wrong-reference bugs but a different underlying gap
  (missing required linkage, not a typo'd value).
- **Fixed**: `input/tests/measure/CMS104FHIRSTKDCAntithrombotic/0b1aa8ee-.../Claim-5ca62962....json`
  — added `"diagnosisSequence": [1]` and `"encounter": [{"reference":
  "Encounter/2be30658-0b61-4a07-b87d-bf812d2dafc0"}]` (the inpatient encounter in that folder;
  there's also a separate `EMER` encounter that isn't the right target — picking the correct one
  requires per-case judgment, not a blind mechanical fix like #7/#11).
- **NOT yet fixed — same gap found in 21 more `Claim` fixtures** via a repo-wide scan for `item[]`
  entries missing `encounter` or `diagnosisSequence`: `CMS108FHIRVTEProphylaxis` (12),
  `CMS190FHIRVTEProphylaxisICU` (7), `CMS104FHIRSTKDCAntithrombotic` (1 more),
  `CMS1017FHIRHHFI` (1). Each needs the same per-case judgment call (which Encounter in that
  folder is the right link target) — not safe to fix mechanically/in bulk the way #7/#11 were.
- **Status**: 1 fixed, not yet verified against a fresh test run; 21 more identified but
  unaddressed.

### 15. CMS133 `Denominator Exclusions` used a point-in-time onset check instead of `prevalenceInterval()` — KEPT, pending re-verification

- **File**: `input/cql/CMS133FHIRCataracts2040BCVA90Days.cql:270-272`.
- **Why**: 59 of 73 mismatches (80.82%), almost entirely `Denominator Exclusion Expected=1,
  Actual=0`. `"Cataract Surgeries in Patients with Significant Ocular Conditions Impacting the
  Visual Outcome of Surgery"` is one large `with (...)` clause covering ~25 valueset union
  branches (all sharing a single `such that`), checking
  `ComorbidDiagnosis.onset.toInterval ( ) overlaps before day of
  CataractSurgeryPerformed.performed.toInterval ( )`. Confirmed via one failing test case
  (description: "retinal vascular and muscular diagnosis overlapping cataract surgery") that its
  `Condition` fixture has `onsetDateTime: "2024-11-01"` — no abatement, `clinicalStatus: active` —
  a chronic condition that predates the 2026-03 cataract surgery by well over a year. Confirmed
  the diagnosis code (`H34.232`) *is* correctly in the "Retinal Vascular Occlusion" valueset, so
  the retrieve/valueset match isn't the problem. `.onset.toInterval()` on a scalar `onsetDateTime`
  produces a zero-width point interval, which can never "overlap" a surgery period a year+ later
  — same class of bug as #10's `"Has Diabetes Diagnosis"` finding in CMS347: a chronic,
  still-active condition needs the "present at any point up through now" pattern
  (`.prevalenceInterval()`, the convention used everywhere else in this codebase for exactly this
  — e.g. `AHAOverall.cql`, CMS347's `"Has Advanced Illness..."`), not a literal onset-date overlap
  check. Confirmed `ComorbidDiagnosis.isVerified()` (called on the same line, same variable) is a
  locally-defined fluent function typed for
  `Choice<ConditionEncounterDiagnosis, ConditionProblemsHealthConcerns>`, so `ComorbidDiagnosis`'s
  type is already established as compatible with the Choice type `.prevalenceInterval()` expects
  elsewhere in the codebase.
- **Fix**: changed `ComorbidDiagnosis.onset.toInterval ( )` to
  `ComorbidDiagnosis.prevalenceInterval ( )`.
- **Caution carried over from #12's CMS190 regression**: this looked like a safe, well-precedented
  fix by the same reasoning that seemed sound for #12 — verify carefully against a fresh test run
  rather than assuming it's correct just because the pattern matches prior fixes.
- **Status**: not yet verified against a fresh test run.

### 16. Six more instances of the `.onset.toInterval()` vs `.prevalenceInterval()` bug (#10/#15's pattern) — KEPT, pending re-verification

- **Files fixed** (8 defines across 6 measures):
  - `input/cql/CMS90FHIRFSAforHeartFailure.cql:81` (`"Initial Population"`) — confirmed against
    fixture `17be91ec-117d-4767-8271-f0403f0c8f84` (`Condition.onsetDateTime: 2025-12-31T23:59:00Z`,
    `clinicalStatus: active`, no abatement; Measurement Period is 2026). This one root cause
    explained 34 of 37 total mismatches (91.89%) — every other "Initial Population" conjunct
    (age, outpatient encounters) already passed.
  - `input/cql/CMS142FHIRCommWithDrManagingDiab.cql:92` (`"Diabetic Retinopathy Encounter"`) —
    confirmed against fixture `b85440e4-b902-49cd-b3d6-363ba7a99bce` (`onsetDateTime: 2023-07-01`
    vs. a 2026-07 qualifying encounter). Explains the bulk of 19/32 mismatches.
  - `input/cql/CMS143FHIRPOAGOpticNerveEval.cql:77` (`"Primary Open Angle Glaucoma Encounter"`) —
    byte-identical pattern/structure to CMS142 (same "Diagnosis + Qualifying Encounter" shape,
    same `.isVerified()` call confirming type compatibility). 18/32 mismatches.
  - `input/cql/CMS951FHIRKidneyHealthEval.cql:75` (`"Has Active Diabetes Overlaps Start Of
    Measurement Period"`) and `:88` (`"Has CKD Stage 5 Or ESRD Diagnosis Overlaps Measurement
    Period"`) — both used the same union+manual-`verificationStatus`-check shape as CMS347's
    already-confirmed instances. 44/55 mismatches (80%).
  - `input/cql/CMS157FHIRPainIntensityQuantified.cql:62` (`"Face to Face or Telehealth Encounter
    with Ongoing Chemotherapy"`) and `:79` (`"Radiation Treatment Management During Measurement
    Period with Cancer Diagnosis"`) — confirmed against fixture `b0729673-76ed-4c08-ae06-acd214ad203d`
    (`Condition.onsetDateTime: 2024-11-01`, `active`, vs. 2026 encounters). 40/126 mismatches.
  - `input/cql/CMS129FHIRProstCaBoneScanUse.cql:144` (`"Prostate Cancer Diagnosis"`) — confirmed
    against fixture `56b77354-f6c1-4507-8270-a07de39f0fa9`, whose own
    `cqfm-testCaseDescription` states the intent directly: *"Test case with condition overlapping
    MP with abatement date. Clinical status is resolved. IPPPass due to diagnosis was active for
    part of the MP."* (`onset: 2022-08-17`, `abatement: 2026-08-17`, `status: resolved`) — this is
    the clearest possible confirmation that the CQL needs the onset-through-abatement span
    (`.prevalenceInterval()`), not a zero-width onset point.
  - `input/cql/CMS347FHIRStatinPreventionTxCVD.cql:151` (`"Has Diabetes Diagnosis"`) and `:157`
    (`"Has ESRD Diagnosis"`) — these are the two defines #10 explicitly flagged as still-broken and
    parked; fixing them now closes out that open item.
- **Why** (repo-wide): all 8 are the same anti-pattern as #10/#15 — `.onset.toInterval()` on a
  scalar `onsetDateTime` produces a zero-width point interval, so a chronic/still-active diagnosis
  that predates the comparison window by any margin can never `overlaps` it, even when the
  diagnosis has no abatement (or an abatement that falls inside/after the window) and is clinically
  still relevant. Every fix here was verified either against a concrete failing fixture's
  onset/abatement/clinicalStatus dates and its `cqfm-testCaseDescription`, or (CMS143/CMS951's
  second occurrence) against a byte-identical code shape immediately adjacent to an
  individually-confirmed instance in the same file. Type compatibility with `.prevalenceInterval()`
  was confirmed for each by finding an existing `.isVerified()` or manual `verificationStatus` check
  on the same alias, establishing it as a `Condition`-compatible Choice type — the same check #15
  used.
- **Fix**: changed each `<alias>.onset.toInterval ( )` to `<alias>.prevalenceInterval ( )` in place.
- **Repo-wide sweep performed but NOT acted on** — `grep -rn 'onset.toInterval' input/cql/` turned
  up roughly 80 more hits. Most are legitimate: `starts before`/`starts after`/`starts during`/
  `same day as` comparisons are genuine point-in-time checks where a zero-width interval is exactly
  correct (e.g. "did the diagnosis start during this visit"), not the `overlaps`-against-a-distant-
  window anti-pattern. A smaller set of `overlaps`-style comparisons against a Measurement Period or
  encounter *do* look structurally similar to this bug — notably `CMS131FHIRDiabetesEyeExam.cql:56`
  (checked against fixture `985b5e49-...`, but the onset dates there sit right at the MP boundary
  and the test description didn't clearly disambiguate which of two `Condition` fixtures each
  define resolves to — inconclusive, left unfixed to avoid a #12-style blind-pattern regression),
  `CMS156FHIRHighRiskMedsElderly.cql:169,179` (chronic-diagnosis-in-lookback-year checks — plausible
  but unverified, and this measure's failures are dominated by the external `Min()` engine issue,
  not clearly this bug), and `CMS1173FHIRDiagnosticDelayVTE.cql:159/163/176/180` (Hospice/Palliative
  diagnosis checks — also unverified, and this measure's 62/65 failures are "Missing Results"
  execution errors already attributed to the external `Min()`/`DateTimeType` issue, not mismatches
  from this pattern). None of these were touched. A future pass should trace each individually
  against a real failing fixture before fixing, the same way every fix in this entry was.

### 17. `doNotPerform` gap (fixes #6/#13's pattern) confirmed and fixed in 4 more measures; 2 adjacent bugs found and fixed along the way — KEPT, pending re-verification

- **Context**: fresh discrepancy report (`discrepancy_report-measure-fixes-20260821-1244.md`) showed
  the same "Denominator Exception Expected=1/Actual=0 + Numerator Expected=0/Actual=1" swap (or a
  standalone Denominator Exception miss) across 9 candidate measures — the exact signature of the
  `doNotPerform`-not-excluded bug from #6 (CMS347) and #13 (CMS104). Each was checked individually
  against a real failing fixture before touching anything, per this document's own rule.
- **Confirmed and fixed (the doNotPerform gap itself)**:
  - `input/cql/CMS71FHIRSTKAnticoagAFFlutter.cql` (`"Numerator"`'s `DischargeAnticoagulant` retrieve)
    — byte-identical structure to CMS104's pre-#13 bug (this measure was already on #13's watch
    list). Confirmed via fixture `e20b4e76-...`: a `MedicationRequest` profiled
    `us-quality-core-medicationnotrequested` with `doNotPerform: true` was being double-counted.
  - `input/cql/CMS135FHIRACEIorARBorARNIforHF.cql` (`"Has ACEI or ARB or ARNI Ordered"` and
    `"Is Currently Taking ACEI or ARB or ARNI"`) — confirmed via fixture `d297e68e-...`
    ("...is not prescribed ACE/ARB medication for Patient Reason"): a `MedicationRequest` profiled
    `us-quality-core-medicationnotrequested` matched the plain `[MedicationRequest: ...]` retrieve
    used for both Numerator branches. 6 of this measure's 9 mismatches were this exact pattern; the
    other 3 are a separate, unrelated allergy/intolerance-diagnosis issue (see below, not fixed).
  - `input/cql/CMS144FHIRHFBetaBlockerForLVSD.cql` (`"Has Beta Blocker Therapy for LVSD Ordered"`
    and `"Is Currently Taking Beta Blocker Therapy for LVSD"`) — confirmed via all 3 of this
    measure's mismatched fixtures (`7b8885c5-...`, `07efd4bb-...`, `67779bc6-...`), each carrying a
    `doNotPerform: true` `MedicationRequest`.
  - `input/cql/CMS645FHIRBoneDensityPCADTherapy.cql` (`"Has Baseline DEXA Scan..."`, the
    `DEXAOrdered` `ServiceRequest` retrieve) — same bug, one type over: a `ServiceRequest` profiled
    `us-quality-core-servicenotrequested` with `doNotPerform: true` (confirmed via fixture
    `8c41481d-...`, "Patient refused DEXA at 3 months after ADT") was matched by the plain
    `[ServiceRequest: "DEXA Bone Density..."]` retrieve. Fixed 2 of this measure's 5 mismatches; the
    remaining 2 (`59743016-...`, `05afd17d-...`) are Initial-Population-level failures unrelated to
    this bug, not investigated further.
  - `input/cql/CMS22FHIRPCSBPScreeningFollowUp.cql` — three Numerator-side retrieves
    (`"NonPharmacological Interventions"`, `"Follow up with Rescreen Within 6 Months"`,
    `"Laboratory Test or ECG for Hypertension"`) all had the same `ServiceRequest` gap, confirmed
    via fixture `ad737f80-...` ("...patient declined recommendation to reduce weight" — a
    `ServiceRequest` profiled `us-quality-core-servicenotrequested`, `doNotPerform: true`, matched by
    the unfiltered `[ServiceRequest: "Weight Reduction Recommended"]` retrieve).
- **Adjacent bug #1 found and fixed while diagnosing CMS22**: 6 defines in the same file
  (`"NonPharmacological Intervention Not Ordered"` and 5 more declined-intervention checks, lines
  328/346/357/377/386/400) filtered on `<alias>.reasonCode in "Patient Declined"` for
  `[ServiceNotRequested: ...]`-typed retrieves. `ServiceRequest` has no native `reasonCode` element
  for "why wasn't this done" — that's carried in the `us-quality-core-doNotPerformReason` extension,
  which this codebase already exposes via the `reasonRefused()` fluent function
  (`USQualityCoreCommon.cql:190-191`, already used correctly in `CMS645`/`CMS108`/`CMS190`/`CMS69`).
  Confirmed against fixture `ad737f80-...`, whose `ServiceRequest` carries the reason only in that
  extension, not in a `reasonCode` element (which doesn't exist on this resource type at all — the
  field was simply never being read). Changed all 6 to `.reasonRefused ( )`.
- **Adjacent bug #2 found and fixed while diagnosing CMS646**: `"BCG Not Available Within 6 Months
  After Bladder Cancer Staging"` (`input/cql/CMS646FHIRIntravesicalBCGTherapy.cql:169`) compared
  `BCGNotGiven.effective` (a `MedicationAdministration` choice `dateTime | Period`) directly against
  a temporal-distance operator without `.toInterval()` first — the same class of bug as #12
  (CMS72's `.effective` fix). Confirmed by comparing against this same file's sibling
  `"First BCG Administered"` define three lines down, which does the equivalent comparison
  correctly with `.effective.toInterval ( ) starts ...`. Confirmed against fixture `e648fa70-...`,
  whose own `cqfm-testCaseDescription` self-flags the issue: *"BCG not available during MP. Should
  pass. Note: Issue with Denominator Exception due to negation issues."* Changed to
  `BCGNotGiven.effective.toInterval ( ) starts 6 months or less after day of start of
  FirstBladderCancerStaging.performed.toInterval ( )`, matching the sibling exactly. Fixed 1 of this
  measure's 4 mismatches; the other 3 (`Denominator Exclusion`/`Numerator` misses) are unrelated,
  not investigated.
- **Investigated, root cause found, deliberately NOT fixed (needs a human decision or more care)**:
  - `input/cql/CMS104FHIRSTKDCAntithrombotic.cql` — the 2 remaining mismatches after #13's fix are
    NOT another instance of the doNotPerform gap (that retrieve already has the check). Root cause
    is different: `"Reason For Not Giving Antithrombotic At Discharge"`'s second union branch (the
    `MedicationRequest`-with-`TaskRejected` pattern, lines 79-86) evaluates empty even when the
    `Task`/`MedicationRequest`/valueset/reasonCode data all line up correctly (confirmed via fixture
    `5adc911a-...`, description "task rejected-patient refusal" — the trace dump shows
    `Reason For Not Giving Antithrombotic At Discharge=[]`). Needs a translator/ELM-level trace to
    diagnose further, not a mechanical fix — left alone.
  - `input/cql/CMS72FHIRSTKAntithromboticDay2.cql` — the 5 remaining `Denominator Exception`
    mismatches are NOT the doNotPerform gap (confirmed: the relevant retrieves already use the
    `MedicationNotRequested`/`MedicationAdministrationNotDone` negation-specific types, which don't
    need the exclusion). Root cause looks like a date-window/`calendarDayOfOrDayAfter()` logic issue
    instead (fixture `ab024aef-...`, "antithrombotic is not ordered due to ref but = 1 day after
    start of ED visit") — not investigated deeply enough to fix confidently; left alone.
  - `input/cql/CMS2FHIRPCSDepScreenAndFollowUp.cql` — all 8 mismatches trace to `"Denominator
    Exceptions"` being hardcoded to `false` with an inline `TODO` comment ("Need to reassess how we
    are representing given no ObservationCancelled profile"). That profile now *does* exist in
    `usqualitycore-modelinfo-0.1.0-cibuild.xml` (confirmed), so the TODO's blocking condition may no
    longer hold — but re-enabling this is a real design/implementation task (writing the
    `ObservationCancelled`-based exception logic and verifying it against fixtures), not a
    mechanical one-line fix. Flagged for a human decision, not attempted.
  - `input/cql/CMS996FHIRAptTxforSTEMI.cql` — the 4 `Denominator Exception` mismatches trace to two
    defines comparing a choice-typed field (`ProcedureNotDone.performed`, `Medication
    AdministrationNotDone.effective`) directly against a temporal operator with no `.toInterval()` —
    looks like #12/adjacent-bug-#2's pattern at first glance, but `performed` is entirely *absent*
    on the `not-done` fixture (confirmed via `ccc7deaf-...`, a `data-absent-reason: not-performed`
    `Procedure`), not just un-converted. The likely correct fix is the `.recorded()` extension
    accessor instead — but that's the exact fluent function this document's "External issues log"
    already flags as hitting a translator ambiguous-overload bug on `ProcedureNotDone` values (see
    CMS68's confirmed case). Applying it here risks reproducing that engine error rather than fixing
    the measure. Left alone pending a real fix for the translator issue, or a way to read the
    `recorded` extension without going through the ambiguous overload.
  - `input/cql/CMS135FHIRACEIorARBorARNIforHF.cql` — 3 of its 9 mismatches (`d18e37a6-...` and 2
    others) are a confirmed-allergy/intolerance-diagnosis check
    (`"Has Diagnosis of Allergy or Intolerance to ACEI or ARB"`), unrelated to the doNotPerform fix
    applied to this same file above. Not investigated further.
- **Status**: not yet verified against a fresh test run.
- **Status**: not yet verified against a fresh test run.

### 18. Fix #16's `.prevalenceInterval()` rollout caused total execution failure in 3 measures — CAUGHT, fixed, needs re-verification

- **File added**: a new fluent function overload in `input/cql/Status.cql`.
- **Why**: a fresh test run (`discrepancy_report-measure-fixes-20260821-1311.md`, triggered mid-session
  and shared by you) showed `CMS90FHIRFSAforHeartFailure`, `CMS133FHIRCataracts2040BCVA90Days`, and
  `CMS951FHIRKidneyHealthEval` had gone from partial mismatches to **100% "Missing Results"** (total
  execution failure, all test cases) immediately after fix #16 replaced their `.onset.toInterval()`
  calls with `.prevalenceInterval()` — a regression, not an improvement. Root-caused by diffing the
  measures where the substitution was safe (`CMS347FHIRStatinPreventionTxCVD`, `CMS129FHIRProstCaBoneScanUse`
  — both confirmed still just "mismatched", not "missing", in the same fresh run) against the ones that
  crashed: the safe ones call `.prevalenceInterval()` on a value from a **single concrete retrieve type**
  (e.g. `[ConditionProblemsHealthConcerns: "Diabetes"]` alone), while the crashing ones call it on a
  **`union` of two USQualityCore condition profile types**
  (`[ConditionProblemsHealthConcerns: "..."] union [ConditionEncounterDiagnosis: "..."]`), which the CQL
  translator infers as `Choice<ConditionProblemsHealthConcerns, ConditionEncounterDiagnosis>`.
  `hl7.fhir.uv.cql.FHIRCommon`'s `prevalenceInterval()` is only declared for concrete `FHIR.Condition` /
  `FHIR.AllergyIntolerance` parameters (confirmed by reading the vendored library at
  `~/.cql-language-server/npm-library-cache/4.11.0-SNAPSHOT/f117967a37910fd6/FHIRCommon-2.0.0.cql:395`);
  invoking it directly on a genuine Choice value has no matching overload and fails at evaluation for
  every test case in the library, not just the specific `define`. Same root class of issue as the
  already-logged "ambiguous overload resolution" translator gap in the External issues log, just
  triggered by a missing overload rather than an ambiguous one.
  `CMS142FHIRCommWithDrManagingDiab`, `CMS143FHIRPOAGOpticNerveEval`, and
  `CMS157FHIRPainIntensityQuantified` (also touched by fix #16, also using the same `union` pattern) had
  **not yet been re-run** at the time of the 13:11 report — their result `.txt` files predated fix #16's
  edit to those specific files — so their "still mismatched, not missing" status in that report is stale
  and does **not** confirm they're safe; treat them as equally at risk until the next fresh run.
- **Fix**: added a `prevalenceInterval(condition Choice<ConditionProblemsHealthConcerns,
  ConditionEncounterDiagnosis>)` overload to `Status.cql`, alongside the file's existing
  `verified(conditions List<Choice<ConditionProblemsHealthConcerns, ConditionEncounterDiagnosis>>)`
  function — the same established pattern already used there for handling this exact Choice type. The
  new overload casts to the concrete branch type first (`if condition is ConditionProblemsHealthConcerns
  then (condition as ConditionProblemsHealthConcerns).prevalenceInterval() else (condition as
  ConditionEncounterDiagnosis).prevalenceInterval()`), which routes to FHIRCommon's real implementation
  via the same concrete-type dispatch that's already proven to work for CMS347/CMS129's single-retrieve
  usages — no per-measure CQL changes needed, since `CMS90`/`CMS133`/`CMS142`/`CMS143`/`CMS951`/`CMS157`
  all already `include Status` and their existing `.prevalenceInterval()` call sites will now resolve to
  this overload instead of failing.
- **Status**: fix applied, **not yet verified** — needs a fresh test run across all 6 affected measures
  (especially CMS90/CMS133/CMS951, to confirm they're back to at-worst-mismatched, and CMS142/143/157, to
  confirm they don't newly crash). **Lesson for future large-fixture-pattern sweeps**: verify a
  `.prevalenceInterval()` (or any FHIRCommon-delegating fluent function) substitution against a retrieve
  that unions two profile types specifically, not just against retrieves of a single type — the risk
  profile is different even though the surface-level CQL text pattern looks identical.
- **CONFIRMED against the actual pre-migration source, 2026-08-21**: cloned
  `https://github.com/cqframework/dqm-content-qicore-2025` locally (see the `dqm-content-qicore-2025`
  reference memory) and checked `input/cql/QICoreCommon.cql:452` — it declares
  `prevalenceInterval(condition Choice<"ConditionEncounterDiagnosis", "ConditionProblemsHealthConcerns">)`
  with logic byte-for-byte identical to what this fix added to `Status.cql`. `QICoreCommon` was the
  library that got refactored into `FHIRCommon`/`USCoreCommon`/`USQualityCoreCommon` during the
  migration (per `USQualityCoreUpdateProcess.md`'s library table) — this specific Choice-typed overload
  was dropped in that refactor and never carried over, which is the actual root cause. This is a genuine
  migration-completeness gap, not a one-off authoring mistake in any of the 6 measures, and it validates
  the project's corrected framing (see "Why this work exists," updated 2026-08-21): fix the CQL to match
  the pre-migration QICore intent, not "whichever engine's behavior."
  `USQualityCoreUpdateProcess.md` also documents a cleaner alternative fix for *new* code going forward
  — since `ConditionEncounterDiagnosis`/`ConditionProblemsHealthConcerns` both derive from `Condition` in
  the derived USQualityCore model (unlike flat QICore), a `union` of the two specific retrieves can be
  simplified to a single `[FHIR.Condition: "..."]` retrieve, sidestepping the Choice type entirely
  (precedent already in `CMS125FHIRBreastCancerScreen.cql`, `Hospice.cql`, `PalliativeCare.cql`,
  `AdvancedIllnessandFrailty.cql`, all currently passing). Did not apply that simplification to the 6
  measures here — the `Status.cql` overload fix is lower-risk (one shared-library addition vs. six
  measure-level rewrites) and already unblocks them; flagging the simplification as a nice-to-have
  cleanup for whoever revisits these measures, not required.
- Swept `QICoreCommon.cql` for other function names with no match in `USQualityCoreCommon.cql`/
  `Status.cql` to look for more of the same class of dropped-during-migration function. Found one
  other genuinely QICore-only name, `isHealthConcern`, but confirmed it's NOT missing — it exists with
  a concrete-type signature (`isHealthConcern(condition FHIR.Condition)`) in the vendored
  `hl7.fhir.us.cql.USCoreCommon`/`USCoreElements` libraries (cache dir `29dd7bae49368534`, a different
  cache directory than `FHIRCommon`'s), and its one call site (`CMS69FHIRPCSBMIScreenAndFollowUp.cql:142`)
  is on a single concrete `[ConditionProblemsHealthConcerns: ...]` retrieve, not a `union`-produced
  Choice — so no crash risk there, unlike `prevalenceInterval`. The rest of the QICoreCommon-only names
  (`earliest`, `latest`, `hasStart`/`hasEnd`, `includesCode`, `isActive`, `isEncounterDiagnosis`,
  `isProblemListItem`, `references`, `toInterval`, etc.) were confirmed present in the vendored
  `FHIRCommon`/`USCoreCommon` libraries under the same names and are already in active, working use
  across many currently-passing measures (`CMS117`, `CMS124`, `CMS130`, `CMS165`, etc.) — not a live
  risk. No direct `.abatementInterval()` calls on a `union`-produced Choice were found anywhere in the
  repo's measure/shared CQL (the one other function besides `prevalenceInterval` sharing that exact
  concrete-type-only signature pattern), so no further instances of this specific bug class are known
  at this time.

### 19. Broader QICore diff sweep, round 1 — multiple confirmed fixes, one solved mystery, one left deliberately unfixed

Continuing the direct-source-diff approach from #18, dispatched parallel diffs of `seena-fork/input/cql/*`
against the cloned `dqm-content-qicore-2025` for all 13 shared libraries and 7 measures still showing
discrepancies (CMS996, CMS816, CMS2, CMS108, CMS190, CMS159, CMS155). Findings below; each fix applied
directly (not parked), given the corrected project framing (see "Why this work exists") — no MADiE
quirk-avoidance concern applies, only "does this match the pre-migration source."

- **CMS190FHIRVTEProphylaxisICU — KEPT (partial), solves the fix #12 mystery.** QICore used
  `NoMedicationAdm.recorded` (a `MedicationAdministrationNotDone`) and `DeviceNotApplied.recorded` (a
  `ProcedureNotDone`) for two `authoredOn`/timing tuples; the migration silently swapped both to
  `.effective`/`.performed` — the wrong field, not a missing `.toInterval()` call. This is *why* fix
  #12's seemingly-safe, CMS72-precedented `.toInterval()` fix regressed CMS190 (24→28 mismatches) for
  reasons that were never root-caused at the time: it was fixing the wrong field's *shape*, not the
  wrong field. **Fixed**: `NoMedicationAdm.recorded ( )` (line ~302) — safe, since
  `USQualityCoreCommon.cql` declares `recorded(medicationAdministrationNotDone
  MedicationAdministrationNotDone)` with no sibling base-type overload to conflict with. **NOT fixed,
  reverted back to `.performed`**: `DeviceNotApplied.recorded` (line ~370) — `DeviceNotApplied` is typed
  `ProcedureNotDone`, and `USQualityCoreCommon.cql` declares *both* `recorded(Procedure)` and
  `recorded(ProcedureNotDone)` as separate overloads. Per the already-logged External issue ("Ambiguous
  overload resolution — likely cql-to-elm gap"), calling `.recorded()` on a `ProcedureNotDone` value hits
  a confirmed translator bug where it can't resolve to the more-specific overload — confirmed live in
  `CMS68FHIRDocumentationCurrentMeds` (1 "Missing Results" test case, unfixed, exactly this call). I
  initially reverted this line to bare `.recorded` (copying QICore's pre-migration property syntax
  verbatim) without checking for this — caught it during review before it went further: bare `.recorded`
  is invalid syntax in the derived model regardless (extensions are fluent functions here, per
  `USQualityCoreUpdateProcess.md` Step 3), and adding the required `( )` would just reproduce CMS68's
  crash. Reverted to the pre-existing `.performed` (wrong field, but stable/non-crashing) rather than
  risk a full-library "Missing Results" regression I can't verify without engine access.
- **CMS159FHIRDepRemissionat12Months — KEPT, pending re-verification.** 4 more confirmed instances of
  the `.onset.toInterval()` vs `.prevalenceInterval()` bug (#10/#15/#16/#18 family), all reverted to
  `.prevalenceInterval()`: `"Depression Encounter"`'s `Depression` check, `"Has Mental Health Disorder
  Diagnoses"`'s `MentalHealthDisorderDiagnoses` check, and the locally-inlined `HospiceCareDiagnosis`/
  `PalliativeDiagnosis` checks in `"Has Hospice Services..."`/`"Has Palliative Care..."` (this measure
  inlines its own copies rather than calling the `Hospice.cql`/`PalliativeCare.cql` shared functions,
  which is why the shared-library fix didn't already cover it). All four are `union`s of
  `ConditionProblemsHealthConcerns`/`ConditionEncounterDiagnosis`, and this file already includes
  `Status.cql`, so they're covered by fix #18's `prevalenceInterval(Choice<...>)` overload — no further
  library change needed. Matches the failure signature exactly (6 of 8 mismatches are Initial
  Population/Denominator misses, 1 is the hospice/palliative Denominator-Exclusion↔Numerator swap).
- **CMS155FHIRWgtAssessCounseling — KEPT, pending re-verification.** Same bug, 1 instance:
  `"Pregnancy Diagnosis Which Overlaps Measurement Period"`'s `PregnancyDiag` check, reverted to
  `.prevalenceInterval ( )`. Matches all 6 mismatches (a pregnancy-exclusion case across 3 groups for one
  test case). Covered by the same `Status.cql` overload (file already includes it).
- **AHAOverall.cql — KEPT, pending re-verification, repo-wide shared-library impact (affects CMS144
  directly, likely others via `AHAOverall` inclusion).** QICore's `overlapsHeartFailureOutpatientEncounter`
  and `overlapsAfterHeartFailureOutpatientEncounter` both took a
  `Choice<ConditionEncounterDiagnosis, ConditionProblemsHealthConcerns>` parameter; the migration
  narrowed both to `ConditionEncounterDiagnosis` only, silently dropping `ConditionProblemsHealthConcerns`
  support. `CMS144FHIRHFBetaBlockerForLVSD.cql` calls both functions on genuine `union`-produced Choice
  values in 7 separate Denominator-Exception `define`s (`"Has Hypotension Diagnosis"`, `"...Cardiac
  Pacer..."`, `"...Allergy or Intolerance to Beta Blocker..."`, `"...Bradycardia..."`, `"...Arrhythmia..."`,
  `"...Asthma..."`, `"...Atrioventricular Block..."`). **Fix, deliberately NOT a Choice-typed overload
  this time**: added a sibling `ConditionProblemsHealthConcerns`-typed overload for each function,
  matching this exact file's own pre-existing convention (it already has 4 other type-specific overloads
  of `overlapsAfterHeartFailureOutpatientEncounter` for `Procedure`/`AllergyIntolerance`/
  `MedicationRequest`/`HeartRateObservation`). Deliberately avoided widening to a `Choice<...>` parameter
  the way fix #18 did for `prevalenceInterval`, because that would require `Condition.isVerified()` and
  `Condition.prevalenceInterval()` to resolve inside the function body against the Choice type too — and
  `AHAOverall.cql` doesn't include `Status.cql` (where the `prevalenceInterval` Choice overload lives),
  and can't safely be given a local Choice-typed `isVerified`/`prevalenceInterval` of its own either,
  because every caller observed so far (`CMS144`, and by extension anything else including both
  `AHAOverall` and `Status`/`USQualityCoreCommon`) would then see the *same signature* declared in two
  independently-included libraries — a duplicate-declaration conflict, the same risk class this whole
  entry is about avoiding. Two concrete sibling overloads sidesteps this entirely: each new overload's
  body only ever sees a concrete (non-Choice) `Condition`, so `.isVerified()`/`.prevalenceInterval()`
  resolve the same way they already do for every other concrete-type retrieve in this codebase — no new
  dependency, no ambiguous/duplicate declaration. Confidence: high that this compiles cleanly (no
  overlapping-inheritance ambiguity between true CQL siblings, unlike the `Procedure`/`ProcedureNotDone`
  case above); NOT verified that CMS144's specific mismatches actually resolve — that's a data question,
  not just a compile question, since the function was only ever invoked in `exists(...)` guards that
  short-circuit on empty retrieves.
- **CMS2FHIRPCSDepScreenAndFollowUp — KEPT, pending re-verification.** The "hardcoded `false`, TODO: no
  ObservationCancelled profile" note from fix #17 was investigating on a **false premise** —
  `ObservationCancelled` exists in `usqualitycore-modelinfo-0.1.0-cibuild.xml`
  (`us-quality-core-observationcancelled`), and the identical `[ObservationCancelled: ...]` +
  `.notDoneReason()` pattern is already proven working in `CMS143FHIRPOAGOpticNerveEval.cql`. QICore's
  real logic (referencing `"Medical or Patient Reason for Not Screening Adolescent/Adult for
  Depression"`, each retrieving `[ObservationCancelled: code ~ "..."]` and checking `.notDoneReason`
  against "Depression screening declined"/"Medical Reason") was present verbatim in this file but
  **commented out on both ends** — the `"Denominator Exceptions"` definition itself, and its two
  dependency `define`s. Uncommented both blocks and fixed one additional bug found in the process: the
  commented code called `.notDoneReason` as a bare property (`NoAdolescentScreen.notDoneReason ~ "..."`)
  — valid in QICore where it might have been a first-class element, but `USQualityCoreCommon.cql`
  declares `notDoneReason(observationCancelled ObservationCancelled)` as a fluent function requiring
  `( )`, per the same "extensions are now fluent functions" migration pattern documented in
  `USQualityCoreUpdateProcess.md` Step 3. Fixed both occurrences to `.notDoneReason ( )`. This was
  correctly a straightforward missed-conversion bug, not a design task as fix #17 assumed.
- **CMS996FHIRAptTxforSTEMI and CMS108FHIRVTEProphylaxis — CONFIRMED root cause, deliberately left
  UNFIXED.** Both hit the exact same `.recorded` ambiguous-overload issue as CMS190's `DeviceNotApplied`
  above: QICore's `PCINotDone.recorded`/`FibrinolyticNoMed.recorded` (CMS996) and `DeviceNotApplied.recorded`
  (CMS108) were silently swapped to `.performed`/`.effective` during migration — the wrong field, chosen
  specifically to dodge the same `Procedure`/`ProcedureNotDone` overload ambiguity that crashes CMS68.
  Reverting to the correct field would very likely reproduce that crash (unconfirmed, since I can't
  compile/run the engine from this environment) rather than fix the data. Per the External issues log's
  own policy ("Not reshaping correct CQL to route around it — file upstream if this gets prioritized"),
  did not attempt a speculative disambiguating cast (e.g. `(PCINotDone as Procedure).recorded ( )`)
  without a way to verify it actually compiles — a wrong guess here risks turning a partial mismatch into
  a 100%-crashed "Missing Results" measure, the same class of mistake fix #18 caught and fixed elsewhere
  this session. **Needs a human/engine-verified decision**: either (a) confirm via a real compile/stack
  trace whether an explicit cast resolves the ambiguity safely, or (b) escalate the underlying
  `Procedure`/`ProcedureNotDone` overload-ambiguity translator bug upstream, per the existing External
  issues log entry.
- **CMS816FHIRHHHypo — confirmed NOT a migration regression, out of scope for this framing.** Diffed
  fully against QICore: logic is byte-identical (only mechanical header/measurement-period changes). The
  12 current mismatches must trace to a fixture/data issue or a bug that would reproduce against the
  pre-migration QICore version too — not fixable through the "migration correctness" lens this project is
  now scoped to. Not pursued further under this framing; would need the original symptom-driven
  fixture/CQL debugging approach (checking the actual failing test case's data) if picked up again.
- **PCMaternal.cql — unconfirmed lead, not acted on.** `lastEstimatedDeliveryDate()` and
  `lastTimeOfDelivery()` changed their internal cast from `.value as DateTime` (QICore, `System.DateTime`)
  to `.value as FHIR.dateTime` (USQualityCore) — a real type change, not a rename. Callers in
  `CMS0334FHIRPCCesareanBirth.cql` and `CMS1028FHIRPCSevereOBComps.cql` do direct date arithmetic/interval
  construction against these functions' return values, which could behave differently against a raw
  `FHIR.dateTime` vs. `System.DateTime` depending on whether the engine auto-unwraps it in those operator
  positions. Not verified against a live engine or a specific failing fixture (both callers currently show
  only 1-2 mismatches each, consistent with either a narrow real effect or no effect at all) — flagged for
  whoever next investigates `CMS0334`/`CMS1028`'s remaining mismatches, not fixed.
- **Everything else checked clean**: `AdultOutpatientEncounters.cql`, `AlaraCommonFunctions.cql`,
  `Antibiotic.cql`, `CQMCommon.cql` (despite being implicated in prior fix #11/#14 fixture work — no
  library-level regression, confirming those really were fixture bugs), `AdvancedIllnessandFrailty.cql`
  (already correctly applies the `union`→single-`[Condition: ...]` simplification, with its own
  self-aware TODO comment), `Hospice.cql`, `PalliativeCare.cql`, `SupplementalDataElements.cql`,
  `TJCOverall.cql`, `VTE.cql` — all mechanical-only diffs, no genuine logic regressions found.
- **Status**: all fixes in this entry marked "KEPT" are applied but **not yet verified** against a fresh
  test run — same caveat as #16/#17/#18. Recommend the next fresh test run cover CMS2, CMS144, CMS155,
  CMS159, CMS190 specifically to confirm these land as intended and CMS190 doesn't regress again.

### 20. CRITICAL: fix #18's `Status.cql` `prevalenceInterval` overload caused a repo-wide circular-reference compile failure — caught and fixed same session

- **File**: `input/cql/Status.cql`.
- **Severity**: a fresh test run (`scripts/comparison/discrepancy_report.md`, generated 2026-08-21
  14:54) showed the suite collapse from 91.85% passing to **7.43% passing** — 67 of 74 measures went to
  100% "Missing Results" (total execution failure), including measures with zero relationship to
  anything touched this session (`CMS50`, `CMS56`, `CMS74`, `CMS117`, `CMS122`, etc.). The common thread:
  every affected measure includes `Status.cql`; the handful that survived (`CMS108`, `CMS0334`, and
  `CMS2`, which is now fully passing) do not include it.
- **Root cause**: fix #18's `prevalenceInterval(condition Choice<ConditionProblemsHealthConcerns,
  ConditionEncounterDiagnosis>)` delegated via `(condition as ConditionProblemsHealthConcerns
  ).prevalenceInterval ( )`, expecting the cast to resolve the call to FHIRCommon's concrete-type
  overload. It does not: a value cast to a concrete member of a `Choice` type is still considered a
  member of that `Choice` for overload-resolution purposes, so the call resolved back to this *same*
  newly-declared function — an infinite self-reference. Confirmed directly from the engine's own error
  message in `input/tests/results/CMS50FHIRReceiptofSpecialistReport.txt`: `"Cannot resolve reference to
  expression or function prevalenceInterval_...ChoiceTypeSpecifier..._ because it results in a circular
  reference."` This is an important, generalizable lesson: **casting to a concrete branch of a Choice
  type does NOT disambiguate a call against an overload declared for that same Choice type** — it only
  disambiguates against overloads declared for *unrelated, non-overlapping* types (which is why the
  identical casting technique worked fine for `AHAOverall.cql`'s sibling-overload fix in #19, and would
  likely have worked for the `ProcedureNotDone`/`Procedure` ambiguity discussed in #19 — those are true
  supertype/subtype or disjoint-sibling situations, not "cast to a member of the very Choice type you're
  currently inside").
- **Fix**: split into two functions. `prevalenceInterval(condition Choice<ConditionProblemsHealthConcerns,
  ConditionEncounterDiagnosis>)` now dispatches (via `is`/`as`) to a *differently-named* helper,
  `toPrevalenceInterval`, which has two concrete-type-only overloads (one per branch). Since
  `toPrevalenceInterval` isn't declared anywhere else, there's nothing for the call to circle back to,
  and each concrete overload's own `.abatementInterval ( )`/`.onset.toInterval ( )`/`.clinicalStatus`
  calls are unambiguous (this file declares no competing `abatementInterval` overload at all). Both
  overloads' bodies are FHIRCommon's own `prevalenceInterval` algorithm, inlined verbatim (same
  algorithm as before, just relocated). Noted in passing: the pre-migration `QICoreCommon.cql` had
  something structurally similar for the same reason — a deprecated plain `function ToPrevalenceInterval`
  (capital T) that called separately-named `ToInterval`/`ToAbatementInterval` helpers rather than the
  fluent `prevalenceInterval` — suggesting this self-reference hazard may be a known, older reason
  QICore itself kept these as distinct names.
- **How this got missed initially**: fix #18 was written and reasoned about carefully, but never
  actually verified against a compile — the "cast disambiguates" assumption was extrapolated from the
  `ProcedureNotDone`/`Procedure` case without checking whether the *same* reasoning actually applies when
  the overload you're casting away from is your *own* Choice-typed declaration rather than someone
  else's unrelated one. This fresh test run is exactly the kind of verification loop this whole document
  keeps saying is required before trusting a fix — treat this as the concrete example of why, not just a
  now-fixed bug.
- **Not yet re-verified**: this fix has not been run through the engine either. Needs a fresh test run
  before any of #16/#18/#19's confidence claims can be trusted. Given how large the blast radius was
  here, treat every measure that includes `Status.cql` as unverified until that happens, not just the
  ones this session directly edited.
- **Update — the first fix attempt above was itself still broken, caught via a second fresh test run
  (same 7.43% pass rate, different error).** `toPrevalenceInterval`'s body was copied verbatim from
  FHIRCommon's `prevalenceInterval(Condition)`, including `condition.clinicalStatus ~ "active"` /
  `"recurrence"` / `"relapse"`. In CQL, double-quoted names are identifier references (to a `code`,
  `concept`, `valueset`, or other named declaration), not string literals — `"active"` only resolves
  *inside* `FHIRCommon.cql` itself, where `code "active": 'active' from "ConditionClinicalStatusCodes"`
  is actually declared. Copying the expression into `Status.cql` without qualifying it produced
  `"Could not resolve identifier active in the current library."` for every one of the ~67 affected
  measures — the exact same blast radius as the circular-reference bug, just a different root cause.
  This codebase's own established convention for referencing another library's `code` declaration is
  qualification (`FHIRCommon."active"` — already used this way in `CMS108`, `CMS347`,
  `NHSNGlycemicControlHypoglycemiaInitialPopulation`, etc.), which is what the QICore-derived body was
  missing. **Fixed**: qualified all three references as `FHIRCommon."active"` / `FHIRCommon."recurrence"`
  / `FHIRCommon."relapse"` in both `toPrevalenceInterval` overloads. Still **not verified** against a
  fresh test run as of this edit — this entry has now been wrong twice in a row without a real compile
  check, which is itself the strongest argument in this whole document for not trusting any Status.cql/
  shared-library change until an actual test run confirms it, no matter how small or "obviously correct"
  it looks.
- **Update — a THIRD fresh test run showed the `FHIRCommon.` qualification fix above still didn't work,
  a third distinct error, and the whole `Status.cql` shared-function approach was abandoned in favor of
  a per-call-site fix.** `discrepancy_report-measure-fixes-20260821-1552.md` (partial recovery, 87.78%
  vs. the 91.85% pre-regression baseline) showed CMS90/CMS133/CMS142/CMS143/CMS155/CMS159/CMS951 —
  exactly the measures fix #18/#19 were meant to help — still 100% "Missing Results". Actual engine
  error this time: `"Ambiguous call to operator 'toPrevalenceInterval(org.hl7.fhir.r4.model.Condition)'
  in library 'Status'."` Root cause: `ConditionProblemsHealthConcerns` and `ConditionEncounterDiagnosis`
  are distinct CQL/model types, but both compile down to the *identical* underlying Java runtime class
  (`org.hl7.fhir.r4.model.Condition`) — USQualityCore profiles are metadata on top of the same FHIR
  resource, not distinct implementation classes. So the two-overload split from #18/the correction above
  (`toPrevalenceInterval(ConditionProblemsHealthConcerns)` / `toPrevalenceInterval(ConditionEncounterDiagnosis)`)
  is ambiguous at the *engine* level even though it looks perfectly fine at the CQL/ELM level — the
  runtime literally cannot tell the two overloads apart. **This also retroactively explains why fix #19's
  `AHAOverall.cql` sibling-overload fix (`overlapsHeartFailureOutpatientEncounter`/
  `overlapsAfterHeartFailureOutpatientEncounter`, one overload per profile type) was ALSO broken** —
  `CMS144FHIRHFBetaBlockerForLVSD` showed 48/48 "Missing Results" in the same 1552 report, the identical
  ambiguous-runtime-type failure mode, just not yet traced to its cause at the time #19 was written.
  **Final fix, this time verified conceptually against the actual runtime-type constraint rather than
  guessed**: fully reverted both `Status.cql` and `AHAOverall.cql` to their pre-session state (`git
  checkout --`, confirmed clean via `git diff`) — no shared-library changes at all for this bug class
  anymore. Instead, fixed at each of the 13 individual call sites across `CMS90`, `CMS133`, `CMS142`,
  `CMS143`, `CMS951` (×2), `CMS157` (×2), `CMS155`, `CMS159` (×4): changed `X.prevalenceInterval ( )` to
  `(X as FHIR.Condition).prevalenceInterval ( )`. This works because casting *up* to the common ancestor
  `FHIR.Condition` (not to a sibling member of the original Choice, which is what caused #18's circular
  reference) leaves exactly one candidate declaration in scope — `FHIRCommon`'s single, already-existing
  `prevalenceInterval(condition Condition)` — with no sibling overload of any kind to be ambiguous
  against, since nothing (no shared library, no per-file declaration) declares a second
  `prevalenceInterval` for plain `FHIR.Condition`. No new function declared anywhere; every fix is a
  same-line edit to an existing `such that`/`where` clause. **CMS144's `AHAOverall.cql` gap (dropped
  `ConditionProblemsHealthConcerns` support, from #19) is deliberately left UNFIXED** — the same
  runtime-ambiguity constraint applies there too (an analogous per-call-site cast doesn't work, since
  `overlapsHeartFailureOutpatientEncounter`/`overlapsAfterHeartFailureOutpatientEncounter` don't have a
  generic-`Condition`-typed overload to cast up to, only the narrow `ConditionEncounterDiagnosis`-typed
  one) — given the string of failed attempts on this exact bug class this session, leaving CMS144 at its
  known, non-crashing, pre-session mismatch level (2-3/48) is the responsible choice over a fourth guess.
  Needs a genuinely different approach (e.g. widening `AHAOverall.cql`'s own function to accept
  `FHIR.Condition` directly, verified against a real compile before landing) from whoever picks this back
  up.
- **Status of this whole saga (entries #16, #18, #19's `prevalenceInterval`-Choice fixes, #20's
  corrections): applied, still not verified against a fresh test run.** Given the track record
  (circular reference → identifier-qualification bug → runtime-ambiguity bug, three distinct failures
  in a row on what looked like an increasingly "obviously correct" fix each time), do not treat this as
  resolved until an actual fresh test run confirms CMS90/CMS133/CMS142/CMS143/CMS155/CMS159/CMS951 land
  as non-crashing with the expected mismatch counts, and that nothing else regressed. The concrete lesson
  for this document going forward, stated plainly: **a fix to any file included by many other files
  needs to be either (a) verified against a real compile/test run before being trusted, or (b) done as
  a same-file, no-new-shared-declaration edit like this final version** — sibling/Choice-typed overloads
  on USQualityCore profile types are not a safe pattern in this codebase, full stop, regardless of how
  they look on paper, because of the shared-runtime-class issue above.
- **Update — a FOURTH fresh test run (`discrepancy_report-measures-fixes-20260821-1607.md`, 85.92%)
  showed the `(X as FHIR.Condition)` call-site fix above still didn't work, a fourth distinct error.**
  Actual engine error this time: `"Expression of type
  'choice<USQualityCore.ConditionEncounterDiagnosis,USQualityCore.ConditionProblemsHealthConcerns>'
  cannot be cast as a value of type 'Condition'."` The `as` operator in this translator does not support
  widening a `Choice` to a common ancestor type at all — it only supports narrowing to one of the
  Choice's own listed members. My assumption that "casting up escapes the Choice type" was simply wrong
  about what `as` is allowed to do here, regardless of the ambiguity reasoning that motivated it.
  **Final-final fix**: replaced every `(X as FHIR.Condition).prevalenceInterval ( )` with an inline
  `is`/`as` branch to a concrete Choice *member* (not the ancestor) — `if X is ConditionProblemsHealthConcerns
  then (X as ConditionProblemsHealthConcerns).prevalenceInterval ( ) else (X as
  ConditionEncounterDiagnosis).prevalenceInterval ( )` — written directly inline at each of the same 13
  call sites, with **no function of any kind declared anywhere** (not in a shared library, not locally,
  not even under a different name). This is different from fix #18's original circular-reference mistake
  in one critical way: #18 also cast down to a Choice member, but then called a function (`prevalenceInterval`)
  that *I had also declared for the Choice type itself*, which is what made the member type still "count"
  as a Choice match. Here, nothing named `prevalenceInterval` is declared for anything Choice-shaped or
  profile-specific anywhere in the repo (confirmed via `grep -rn "function prevalenceInterval"
  input/cql/*.cql` — zero results after the `Status.cql` revert) — so after the narrowing cast, the ONLY
  reachable declaration is `FHIRCommon`'s single `prevalenceInterval(condition Condition)`, unambiguous
  by construction, sidestepping both the circular-reference failure mode (no self-declared Choice overload
  to loop back to) and the ambiguous-runtime-type failure mode (no sibling profile-specific overload of
  my own for the two branches to collide against — the *only* two-branch decision happening at all is the
  `is`/`as` type-check itself, which is a normal, already-working CQL/profile-discrimination mechanism —
  confirmed already in production use elsewhere in this exact codebase, e.g. `AHAOverall.cql`'s
  `TimingBoundToInterval` dispatching on `is FHIR.Period`/`is FHIR.Range`/`is FHIR.Duration`).
- **Status, honestly**: this is the fourth attempt at this exact bug class in one session, and the first
  three were each wrong for a different, only-visible-at-actual-compile-time reason. I'm reasonably
  confident in the reasoning above, but given the track record, **do not treat this as resolved without
  an actual fresh test run confirming it.** If this ALSO fails, the pragmatic fallback — matching what was
  ultimately done for `CMS144`/`AHAOverall.cql` above — is to leave `CMS90`/`CMS133`/`CMS142`/`CMS143`/
  `CMS155`/`CMS157`/`CMS159`/`CMS951` at their pre-session `.onset.toInterval()` state (reverted, known
  mismatched-but-non-crashing) rather than continue guessing at shared-runtime-type workarounds blind.
- **VERIFIED — the fourth attempt worked.** `discrepancy_report-measures-fixes-20260821-1620.md`
  (generated after this fix, confirmed via file timestamps): suite-wide pass rate **93.99%** — above
  the 91.85% baseline from *before* this entire regression saga started. `CMS90`, `CMS133`, `CMS143`,
  `CMS951`, `CMS155` now show **zero discrepancies** (fully passing). `CMS142`/`CMS157`/`CMS159` dropped
  from 100% "Missing Results" to small counts of genuine logic mismatches (5/32, 19/126, 2/67
  respectively) — no more crashes, meaning the actual clinical-logic questions those measures still
  have are now visible and debuggable again, rather than hidden behind an execution failure.
  `CMS144FHIRHFBetaBlockerForLVSD` (the `AHAOverall.cql`-adjacent one, deliberately left unfixed above)
  is also back to zero discrepancies — consistent with it never having been broken by anything other
  than the reverted `Status.cql`/`AHAOverall.cql` shared-library attempts, now that those are cleanly
  reverted. Consulting the `/cql` and `/qicore` skills mid-saga helped confirm the reasoning before this
  attempt (`as` is narrowing-only per the CQL reference; QICore's own convention already treats the
  "problems/health concerns" condition as plain `Condition`, reinforcing that a retrieve-level
  `[FHIR.Condition: "..."]` simplification — not attempted here, but documented above as the next-level
  fallback — is the actual canonical fix this codebase already uses successfully elsewhere). **This
  whole saga (entries #16, #18, #19, #20) is now closed out as resolved and verified** — the net result
  across all of it: the `.onset.toInterval()`/`.prevalenceInterval()` bug is fixed correctly in `CMS90`,
  `CMS133`, `CMS142`, `CMS143`, `CMS155`, `CMS157`, `CMS159`, `CMS951`, `CMS129`, and `CMS347`'s two
  parked items from #10 — ten measures total, without regressing anything else. `CMS144`'s
  `AHAOverall.cql`-level gap (dropped `ConditionProblemsHealthConcerns` support for
  `overlapsHeartFailureOutpatientEncounter`/`overlapsAfterHeartFailureOutpatientEncounter`) remains
  genuinely unfixed and parked for whoever picks it up next, per the same reasoning as CMS996/CMS108's
  `.recorded()` situation — needs a real compile-verified attempt, not another guess.

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
- The remaining ~45 measures with measure-specific mismatches, one at a time, top-down by fail
  count from the latest discrepancy report (`discrepancy_report-measure-fixes-20260821-1128.md`).
  Current order: `CMS72FHIRSTKAntithromboticDay2` (98) → `CMS104FHIRSTKDCAntithrombotic` (69) →
  `CMS133FHIRCataracts2040BCVA90Days` (59) → `CMS128FHIRAntidepressantMgmt` (56) →
  `CMS951FHIRKidneyHealthEval` (44) → `CMS157FHIRPainIntensityQuantified` (40) → ... CMS347's 4
  lingering issues (see #10) are parked, not blocking — pick back up if convenient.
