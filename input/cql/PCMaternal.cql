/*
NOTE: For use by March 2026 US Realm Connectathon participants for internal use only. Not for use or distribution in commercial products.
*/
library PCMaternal version '6.1.000'

using USQualityCore version '0.1.0-cibuild'
using USCore version '6.1.0-derived'
using FHIR version '4.0.1'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1' called FHIRHelpers
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0' called FHIRCommon
include hl7.fhir.us.cql.USCoreCommon version '2.0.0-ballot' called USCoreCommon
include hl7.fhir.us.cql.USCoreElements version '2.0.0-ballot' called USCoreElements

include USQualityCoreCommon version '0.1.0-cibuild' called USQualityCoreCommon
include CQMCommon version '5.1.000' called CQMCommon

codesystem "LOINC": 'http://loinc.org' 

valueset "Delivery Procedures": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1045.59' 
valueset "ED Visit and OB Triage": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1029.369' 
valueset "Encounter Inpatient": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113883.3.666.5.307' 
valueset "Estimated Gestational Age at Delivery": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1045.26' 
valueset "Observation Services": 'http://cts.nlm.nih.gov/fhir/ValueSet/2.16.840.1.113762.1.4.1111.143' 

code "Date and time of obstetric delivery": '93857-1' from "LOINC" display 'Date and time of obstetric delivery'
code "Delivery date Estimated": '11778-8' from "LOINC" display 'Delivery date Estimated'

parameter "Measurement Period" Interval<DateTime>
  default Interval[@2026-01-01T00:00:00.000Z, @2027-01-01T00:00:00.000Z)

context Patient

define "Delivery Encounter With Age Range":
  "Encounter With Age Range" EncounterWithAge
    with ["Procedure": "Delivery Procedures"] DeliveryProcedure
      such that DeliveryProcedure.status = 'completed'
        and DeliveryProcedure.performed.toInterval  ( ) starts during EncounterWithAge.hospitalizationWithEDOBTriageObservation ()

define "Encounter With Age Range":
  CQMCommon."Inpatient Encounter" InpatientEncounter
    where AgeInYearsAt(date from start of InpatientEncounter.period) in Interval[ 8, 65 )
                  

define "Variable Calculated Gestational Age":
 "Delivery Encounter With Age Range" DeliveryEncounter
    let CGA: DeliveryEncounter.calculatedGestationalAge()
    return {
      EncounterID: DeliveryEncounter.id,
      CalculatedCGA: CGA
    }

define fluent function calculatedGestationalAge (TheEncounter Encounter ):
  //Gestational Age = (280 -(Estimated Delivery Date minus Reference Date/Delivery Date))/7
 ( 280 - ( difference in days between TheEncounter.lastTimeOfDelivery () and TheEncounter.lastEstimatedDeliveryDate( )) ) div 7

    
    
define fluent function hospitalizationWithEDOBTriageObservation (TheEncounter Encounter ):
  /*hospitalizationWithEDOBTriageObservation returns the total interval from the start of any immediately prior emergency department visit or OB Triage visit through the observation visit to the discharge of the given encounter*/
  TheEncounter Visit
    let ObsVisit: Last(["Encounter": "Observation Services"] LastObs
        where LastObs.period ends 1 hour or less on or before start of Visit.period
          and LastObs.status = 'finished'
        sort by 
        end of period
    ),
    VisitStart: Coalesce(start of ObsVisit.period, start of Visit.period),
    EDOBTriageVisit: Last(["Encounter": "ED Visit and OB Triage"] LastEDOBTriage
        where LastEDOBTriage.period ends 1 hour or less on or before VisitStart
          and LastEDOBTriage.status = 'finished'
        sort by 
        end of period
    )
    return Interval[Coalesce(start of EDOBTriageVisit.period, VisitStart), 
    end of Visit.period]
  

define fluent function lastEstimatedDeliveryDate (TheEncounter Encounter ):
  /*This function identifies the last time the EDD was assessed 42 weeks or less prior to or on delivery and stores the result of that assessment.*/
  Last(["SimpleObservation": "Delivery date Estimated"] EstimatedDateOfDelivery
      where EstimatedDateOfDelivery.value as FHIR.dateTime is not null
        and EstimatedDateOfDelivery.status in { 'final', 'amended', 'corrected' }
        and EstimatedDateOfDelivery.effective.earliest ( ) 42 weeks or less before or on TheEncounter.lastTimeOfDelivery ()
      sort by effective.earliest ( )
  ).value as FHIR.dateTime


  define fluent function lastEstimatedGestationalAge (TheEncounter Encounter ):
  Last(["SimpleObservation": "Estimated Gestational Age at Delivery"] EstimatedGestationalAge
  let EGATiming:  EstimatedGestationalAge.effective.earliest() where 
  (EGATiming 24 hours or less before or on TheEncounter.lastTimeOfDelivery () 
  and EstimatedGestationalAge.value is not null 
  and EstimatedGestationalAge.status in { 'final', 'amended', 'corrected' }) or 
      (EGATiming same day as TheEncounter.lastTimeOfDelivery () 
      and EGATiming during TheEncounter.hospitalizationWithEDOBTriageObservation() 
      and EstimatedGestationalAge.value is not null)
 sort by effective.earliest ())
         .value as Quantity

define fluent function lastTimeOfDelivery (TheEncounter Encounter ):
  Last(["SimpleObservation": "Date and time of obstetric delivery"] TimeOfDelivery
      where TimeOfDelivery.value as FHIR.dateTime is not null
        and TimeOfDelivery.status in { 'final', 'amended', 'corrected' }
        and TimeOfDelivery.effective.earliest () during TheEncounter.hospitalizationWithEDOBTriageObservation ()
        and TimeOfDelivery.value as FHIR.dateTime during TheEncounter.hospitalizationWithEDOBTriageObservation()
      sort by effective.earliest()
  ).value as FHIR.dateTime