library NegationTest version '0.1'

using USQualityCore version '0.1.0-cibuild'
using USCore version '6.1.0-derived'
using FHIR version '4.0.1'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1' called FHIRHelpers
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0' called FHIRCommon
include hl7.fhir.us.cql.USCoreCommon version '2.0.0-ballot' called USCoreCommon
include hl7.fhir.us.cql.USCoreElements version '2.0.0-ballot' called USCoreElements

include USQualityCoreCommon version '0.1.0-cibuild' called USQualityCoreCommon
include Status version '2.1.000' called Status

codesystem "ActCode": 'http://terminology.hl7.org/CodeSystem/v3-ActCode'
codesystem "LOINC": 'http://loinc.org'
codesystem "CPT": 'http://www.ama-assn.org/go/cpt'
codesystem "SNOMEDCT": 'http://snomed.info/sct'

valueset "Cup to Disc Ratio": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.1333'
valueset "Diabetic Retinopathy": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.327'
valueset "Level of Severity of Retinopathy Findings": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.1283'
valueset "Medical Reason": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.1007'
valueset "Office Visit": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1001'
valueset "Patient Reason": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.1008'
valueset "Primary Open-Angle Glaucoma": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.326'

code "Acute health crisis (finding)": '705016005' from "SNOMEDCT" display 'Acute health crisis (finding)'
code "Documentation of current medications (procedure)": '428191000124101' from "SNOMEDCT" display 'Documentation of current medications (procedure)'
code "virtual": 'VR' from "ActCode" display 'virtual'
code "Quality of life score [HOOS]": '72093-8' from "LOINC" display 'Quality of life score [HOOS]'
code "Sport-recreation score [HOOS]": '72094-6' from "LOINC" display 'Sport-recreation score [HOOS]'

parameter "Measurement Period" Interval<DateTime>
  default Interval[@2026-01-01T00:00:00.000Z, @2027-01-01T00:00:00.000Z)

context Patient


//Taken from CMS 56. ObservationScreeningAssessment does not return, but a base FHIR Observation does
define "Date Screening Assessment Completed":
    from
        ( ([ObservationScreeningAssessment: "Quality of life score [HOOS]"] ).isAssessmentPerformed ( ))  HOOSLifeQuality,
        ( ( [ObservationScreeningAssessment: "Sport-recreation score [HOOS]"] ).isAssessmentPerformed ( ) ) HOOSSport
        let HOOSLifeQualityDate: date from start of HOOSLifeQuality.effective.toInterval ( ),
        HOOSSportDate: date from start of HOOSSport.effective.toInterval ( )
        where HOOSLifeQualityDate same day as HOOSSportDate
        and ( HOOSSport as ObservationScreeningAssessment ).value is not null
      and ( HOOSLifeQuality as ObservationScreeningAssessment ).value is not null
    return Max({ HOOSLifeQualityDate, HOOSSportDate})

//Taken from CMS 68. ProcedureNotDone
define "Procedure Not Done for Medical Reasons":
  "Qualifying Encounter During Day of Measurement Period" QualifyingEncounter
    with [ProcedureNotDone: code ~ "Documentation of current medications (procedure)"] MedicationsNotDocumented
      such that MedicationsNotDocumented.recorded ( ) during day of QualifyingEncounter.period
        and MedicationsNotDocumented.status = 'not-done'
        and exists ( MedicationsNotDocumented.reasonCode reasonItem
            where reasonItem ~ "Acute health crisis (finding)"
        )

//Taken from CMS 142. CommunicationNotDone not returning.
define "Qualifying Encounter During Day of Measurement Period":
  ( ["Encounter": "Office Visit"] ) QualifyingEncounter
    where QualifyingEncounter.period during day of "Measurement Period"
      and QualifyingEncounter.status = 'finished'
      and QualifyingEncounter.class !~ "virtual"

define "Diabetic Retinopathy Encounter":
  "Qualifying Encounter During Day of Measurement Period" ValidQualifyingEncounter
    with ( ["ConditionProblemsHealthConcerns": "Diabetic Retinopathy"]
      union ["ConditionEncounterDiagnosis": "Diabetic Retinopathy"] ) DiabeticRetinopathy
      such that DiabeticRetinopathy.onset.toInterval ( ) overlaps day of ValidQualifyingEncounter.period
        and DiabeticRetinopathy.isVerified ( )

define "Medical or Patient Reason for Not Communicating Level of Severity of Retinopathy":
  [CommunicationNotDone: category in "Level of Severity of Retinopathy Findings"] LevelOfSeverityNotCommunicated
    with "Diabetic Retinopathy Encounter" EncounterDiabeticRetinopathy
      such that LevelOfSeverityNotCommunicated.recorded () during day of EncounterDiabeticRetinopathy.period
    where ( LevelOfSeverityNotCommunicated.statusReason in "Medical Reason"
        or LevelOfSeverityNotCommunicated.statusReason in "Patient Reason"
    )

define fluent function isVerified(condition Choice<ConditionEncounterDiagnosis, ConditionProblemsHealthConcerns>):
  condition.verificationStatus is not null implies ( condition.verificationStatus ~ Status."confirmed"
      or condition.verificationStatus ~ Status."unconfirmed"
      or condition.verificationStatus ~ Status."provisional"
      or condition.verificationStatus ~ Status."differential"
  )

//Taken from CMS 143. ObservationCancelled
define "Primary Open Angle Glaucoma Encounter":
  "Qualifying Encounter During Day of Measurement Period" ValidQualifyingEncounter
    with ( ["ConditionProblemsHealthConcerns": "Primary Open-Angle Glaucoma"]
      union ["ConditionEncounterDiagnosis": "Primary Open-Angle Glaucoma"] ) PrimaryOpenAngleGlaucoma
      such that PrimaryOpenAngleGlaucoma.onset.toInterval ( ) overlaps day of ValidQualifyingEncounter.period
        and PrimaryOpenAngleGlaucoma.isVerified ( )

define "Medical Reason for Not Performing Cup to Disc Ratio":
  ["ObservationCancelled": "Cup to Disc Ratio"] CupToDiscExamNotPerformed
    with "Primary Open Angle Glaucoma Encounter" EncounterWithPOAG
      such that CupToDiscExamNotPerformed.issued during day of EncounterWithPOAG.period
    where CupToDiscExamNotPerformed.notDoneReason ( ) in "Medical Reason"