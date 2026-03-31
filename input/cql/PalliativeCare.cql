/*
NOTE: For use by March 2026 US Realm Connectathon participants for internal use only. Not for use or distribution in commercial products.
*/
library PalliativeCare version '2.1.000'

using USQualityCore version '0.1.0-cibuild'
using USCore version '6.1.0-derived'
using FHIR version '4.0.1'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1' called FHIRHelpers
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0' called FHIRCommon

include Status version '2.1.000' called Status

codesystem "LOINC": 'http://loinc.org'

valueset "Palliative Care Encounter": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1090'
valueset "Palliative Care Intervention": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.198.12.1135'
valueset "Palliative Care Diagnosis": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.1167'

code "Functional Assessment of Chronic Illness Therapy - Palliative Care Questionnaire (FACIT-Pal)": '71007-9' from "LOINC" display 'Functional Assessment of Chronic Illness Therapy - Palliative Care Questionnaire (FACIT-Pal)'

parameter "Measurement Period" Interval<DateTime>

context Patient

define "Has Palliative Care in the Measurement Period":
  // TODO: Shouldn't need to specify a code path here (see https://jira.hl7.org/browse/FHIR-53941)
  exists ((([USQualityCore.ObservationScreeningAssessment: code ~ "Functional Assessment of Chronic Illness Therapy - Palliative Care Questionnaire (FACIT-Pal)"]).isAssessmentPerformed()) PalliativeAssessment
      where PalliativeAssessment.effective.toInterval() overlaps day of "Measurement Period"
  )
    // TODO: Consider whether to keep this as the union of the problems and encounter diagnosis list? Anything enforced by the profiles that is expected but isn't stated here?
    or exists ((([FHIR.Condition: "Palliative Care Diagnosis"]).verified()) PalliativeDiagnosis
        where PalliativeDiagnosis.prevalenceInterval() overlaps day of "Measurement Period"
    )
    or exists ((([USQualityCore.Encounter: "Palliative Care Encounter"]).isEncounterPerformed()) PalliativeEncounter
        where PalliativeEncounter.period overlaps day of "Measurement Period"
    )
    or exists ((([USQualityCore.Procedure: "Palliative Care Intervention"]).isInterventionPerformed()) PalliativeIntervention
        where PalliativeIntervention.performed.toInterval() overlaps day of "Measurement Period"
    )