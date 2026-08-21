/*
NOTE: For use by March 2026 US Realm Connectathon participants for internal use only. Not for use or distribution in commercial products.
*/
library Antibiotic version '2.1.000'

using USQualityCore version '0.1.0-cibuild'
using USCore version '6.1.0-derived'
using FHIR version '4.0.1'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1' called FHIRHelpers
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0' called FHIRCommon
include hl7.fhir.us.cql.CumulativeMedicationDuration version '2.0.0-ballot' called CMD
include hl7.fhir.us.cql.USCoreCommon version '2.0.0-ballot' called USCoreCommon
include hl7.fhir.us.cql.USCoreElements version '2.0.0-ballot' called USCoreElements

include USQualityCoreCommon version '0.1.0-cibuild' called USQualityCoreCommon

parameter "Measurement Period" Interval<DateTime>
  // Measurement Period default removed; value is now supplied via input/tests/config.json
  // default Interval[@2026-01-01T00:00:00.000Z, @2027-01-01T00:00:00.000Z)

context Patient

define function "Encounter with Comorbid Condition History"(episodes List<Encounter>, comorbidConditions List<Condition>):
  episodes episode
      with comorbidConditions comcondition
        such that date from start of comcondition.prevalenceInterval() during Interval[date from start of episode.period - 1 year, date from start of episode.period]
      return episode

define function "Encounter with Competing Diagnosis History"(episodes List<Encounter>, competingConditions List<Condition>):
  episodes episode
      with competingConditions competcondition
        such that competcondition.prevalenceInterval() starts 3 days or less on or after day of start of episode.period
      return episode

define function "Encounter with Antibiotic Medication History"(episodes List<Encounter>, antibioticMedications List<MedicationRequest>):
   episodes episode
    with antibioticMedications ActiveMedication
      such that ActiveMedication.medicationRequestPeriod() overlaps day of Interval[date from start of episode.period  - 30 days, date from start of episode.period - 1 day]