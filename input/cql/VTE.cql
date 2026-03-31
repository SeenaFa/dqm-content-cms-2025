/*
@description: VTE Common Functions

NOTE: This library is not published in this IG, it is included here for convenience. The source of truth for
this library will be the MADiE environment once it fully supports use of QICore STU6-derived.
*/
library VTE version '9.1.000'

using USQualityCore version '0.1.0-cibuild'
using USCore version '6.1.0-derived'
using FHIR version '4.0.1'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1' called FHIRHelpers
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0' called FHIRCommon
include hl7.fhir.us.cql.USCoreCommon version '2.0.0-ballot' called USCoreCommon
include hl7.fhir.us.cql.USCoreElements version '2.0.0-ballot' called USCoreElements

include CQMCommon version '5.1.000' called CQMCommon
include USQualityCoreCommon version '0.1.0-cibuild' called USQualityCoreCommon

valueset "Obstetrical or Pregnancy Related Conditions": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.117.1.7.1.263' 
valueset "Obstetrics VTE": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.117.1.7.1.264'
valueset "Venous Thromboembolism": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.117.1.7.1.279' 

parameter "Measurement Period" Interval<DateTime>
  default Interval[@2026-01-01T00:00:00.000Z, @2027-01-01T00:00:00.000Z)

context Patient

  
define "Initial Population":
"Encounter With Age Range And Without VTE Diagnosis Or Obstetrical Conditions"


define "Admission Without VTE Or Obstetrical Conditions":
  CQMCommon."Inpatient Encounter" InpatientEncounter
  where not (InpatientEncounter.hasEncDiagnosisOf("Obstetrical or Pregnancy Related Conditions")
             or InpatientEncounter.hasEncDiagnosisOf("Venous Thromboembolism")
             or InpatientEncounter.hasEncDiagnosisOf("Obstetrics VTE")
            )


define "Encounter With Age Range And Without VTE Diagnosis Or Obstetrical Conditions":
 "Admission Without VTE Or Obstetrical Conditions" EncounterWithoutConditions
     where AgeInYearsAt(date from start of EncounterWithoutConditions.period) >= 18
    
    
define fluent function fromDayOfStartOfHospitalizationToDayAfterAdmission(TheEncounter Encounter):
	Interval[ date from (start of TheEncounter.hospitalizationWithObservation()), date from (start of TheEncounter.period) + 1 days]
	
	
define fluent function hasEncDiagnosisOf(TheEncounter Encounter, DiagnosisValueSet System.ValueSet):
   TheEncounter E
     return (E.encounterDiagnosis()).code in DiagnosisValueSet
       or E.reasonCode in DiagnosisValueSet
       
       
define fluent function hasPrincipalProcedureOf(TheEncounter Encounter, DiagnosisValueSet System.ValueSet):
   TheEncounter E
   let
        PPx: E.principalProcedure(),
        CPx: singleton from ([Procedure] P where PPx.procedure.references(P.id))
     return PPx.procedure in DiagnosisValueSet
       or CPx.code in DiagnosisValueSet