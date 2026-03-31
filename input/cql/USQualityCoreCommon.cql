/*
@description: Common terminologies and functions used in USQualityCore-based CQL artifacts
@comment: The modelinfo included with the published IG is using [derived modelinfo](https://hl7.org/fhir/uv/cql/using-modelinfo.html#derived-modelinfo)
to enable reuse of data elements and libraries defined in the [US Core](https://hl7.org/fhir/us/core) 
and [US CQL](https://hl7.org/fhir/us/cql) Common IGs. This library is derived from the QICoreCommon shared library used in FHIR-based 
quality measure specifications. However, most of the functionality that was defined in QICoreCommon is now either in [FHIRCommon](https://hl7.org/fhir/uv/cql/Library-FHIRCommon.html)
or [USCoreCommon](https://hl7.org/fhir/us/cql/Library-USCoreCommon.html).
*/
library USQualityCoreCommon version '0.1.0-cibuild'

using USQualityCore version '0.1.0-cibuild'

include hl7.fhir.uv.cql.FHIRHelpers version '4.0.1'
include hl7.fhir.uv.cql.FHIRCommon version '2.0.0'

codesystem "TaskCodeSystem": 'http://hl7.org/fhir/CodeSystem/task-code' 

//Task codes
code "Fulfill": 'fulfill' from "TaskCodeSystem" display 'Fulfill'

context Patient

/*
@description: Returns the value of the recorded extension for a Medication Administration Not Done
*/
define fluent function recorded(medicationAdministrationNotDone MedicationAdministrationNotDone):
  medicationAdministrationNotDone.ext('http://fhir.org/guides/astp/us-quality-core/StructureDefinition/us-quality-core-recorded').value as FHIR.dateTime

/*
@description: Returns the value of the recorded extension for a Medication Administration Not Done
*/
define fluent function recorded(procedureNotDone ProcedureNotDone):
  procedureNotDone.ext('http://fhir.org/guides/astp/us-quality-core/StructureDefinition/us-quality-core-recorded').value as FHIR.dateTime

/*
@description: Returns the value of the recorded extension for a Medication Administration Not Done
*/
define fluent function reasonRefused(serviceNotRequested ServiceNotRequested):
  serviceNotRequested.ext('http://fhir.org/guides/astp/us-quality-core/StructureDefinition/us-quality-core-doNotPerformReason').value as FHIR.CodeableConcept

/*
@description: Creates a list of integers from 1 to how many days are in the interval. Note, this wont create an index for
the final day if it is less than 24 hours. This also includes the first 24 hour period.
*/
define fluent function toDayNumbers(Period Interval<DateTime>):
  ( expand { Interval[1, duration in days between start of Period and end of Period]} ) DayNumber
    return end of DayNumber

/*
@description: Creates a list of 24 hour long intervals in an interval paired with the index (1 indexed) to which 24 hour interval it is.
Note that the result will include intervals that are closed at the beginning and open at the end
*/
define fluent function daysInPeriod(Period Interval<DateTime>):
  ( Period.toDayNumbers()) DayIndex
    let startPeriod: start of Period + (24 hours * (DayIndex - 1)),
    endPeriod: if (hours between startPeriod and end of Period < 24) then startPeriod
      else start of Period + (24 hours * DayIndex)
    return Tuple {
      dayIndex: DayIndex,
      dayPeriod: Interval[startPeriod, endPeriod)
    }
  