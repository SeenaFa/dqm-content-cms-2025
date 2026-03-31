/*
NOTE: For use by March 2026 US Realm Connectathon participants for internal use only. Not for use or distribution in commercial products.
*/
library AdultOutpatientEncounters version '5.1.000'

using USQualityCore version '0.1.0-cibuild'
using USCore version '6.1.0-derived'
using FHIR version '4.0.1'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1' called FHIRHelpers
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0' called FHIRCommon

include Status version '2.1.000'

valueset "Annual Wellness Visit": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.526.3.1240' 
valueset "Home Healthcare Services": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1016' 
valueset "Office Visit": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1001' 
valueset "Virtual Encounter": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1089' 
valueset "Preventive Care Services Established Office Visit, 18 and Up": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1025' 
valueset "Preventive Care Services Initial Office Visit, 18 and Up": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1023' 
valueset "Telephone Visits": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.464.1003.101.12.1080' 

parameter "Measurement Period" Interval<DateTime>
  default Interval[@2026-01-01T00:00:00, @2026-12-31T23:59:59]

context Patient

// NOTE: The USQualityCore encounter here is not introducing any constraints, and so could be expressed directly using US Core
define "Qualifying Encounters":
  ( ( 
    [USQualityCore.Encounter: "Office Visit"]
      union [USQualityCore.Encounter: "Annual Wellness Visit"]
      union [USQualityCore.Encounter: "Preventive Care Services Established Office Visit, 18 and Up"]
      union [USQualityCore.Encounter: "Preventive Care Services Initial Office Visit, 18 and Up"]
      union [USQualityCore.Encounter: "Home Healthcare Services"]
      union [USQualityCore.Encounter: "Virtual Encounter"]
      union [USQualityCore.Encounter: "Telephone Visits"] 
    ).isEncounterPerformed() 
  ) ValidEncounter
    where ValidEncounter.period during day of "Measurement Period"