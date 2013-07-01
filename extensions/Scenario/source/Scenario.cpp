/** @file
 *
 * @ingroup scoreExtension
 *
 * @brief Scenario time process class is a container class to manage other time processes instances in the time
 *
 * @see TimeProcessLib, TTTimeProcess
 *
 * @authors Théo de la Hogue & Clément Bossut
 *
 * @copyright Copyright © 2013, Théo de la Hogue & Clément Bossut @n
 * This code is licensed under the terms of the "CeCILL-C" @n
 * http://www.cecill.info
 */

#include "Scenario.h"

#define thisTTClass                 Scenario
#define thisTTClassName             "Scenario"
#define thisTTClassTags             "time, process, scenario"

extern "C" TT_EXTENSION_EXPORT TTErr TTLoadJamomaExtension_Scenario(void)
{
	TTFoundationInit();
	Scenario::registerClass();
	return kTTErrNone;
}

TIME_PROCESS_CONSTRUCTOR,
mNamespace(NULL),
mEditionSolver(NULL),
mExecutionGraph(NULL)
{
    TIME_PROCESS_INITIALIZE
    
	TT_ASSERT("Correct number of args to create Scenario", arguments.size() == 0);
    
    addMessage(Compile);
    
    addMessageWithArguments(TimeProcessAdd);
    addMessageProperty(TimeProcessAdd, hidden, YES);
    
    addMessageWithArguments(TimeProcessRemove);
    addMessageProperty(TimeProcessRemove, hidden, YES);
    
    addMessageWithArguments(TimeProcessMove);
    addMessageProperty(TimeProcessMove, hidden, YES);
    
    addMessageWithArguments(TimeProcessLimit);
    addMessageProperty(TimeProcessLimit, hidden, YES);
    
    addMessageWithArguments(TimeEventAdd);
    addMessageWithArguments(TimeEventRemove);
    addMessageWithArguments(TimeEventMove);
    addMessageWithArguments(TimeEventReplace);
    addMessageWithArguments(TimeEventTrigger);
    
    // all messages below are hidden because they are for internal use
    addMessageWithArguments(TimeProcessActiveChange);
    addMessageProperty(TimeProcessActiveChange, hidden, YES);
    
    // Create the edition solver
    mEditionSolver = new Solver();
    
    // Create extended int
    plusInfinity = ExtendedInt(PLUS_INFINITY, 0);
    minusInfinity = ExtendedInt(MINUS_INFINITY, 0);
    integer0 = ExtendedInt(INTEGER, 0);
}

Scenario::~Scenario()
{
    if (mNamespace) {
        delete mNamespace;
        mNamespace = NULL;
    }
    
    if (mEditionSolver) {
        delete mEditionSolver;
        mEditionSolver = NULL;
    }
    
    if (mExecutionGraph) {
        delete mExecutionGraph;
        mExecutionGraph = NULL;
    }
}

TTErr Scenario::getParameterNames(TTValue& value)
{
    value.clear();
	//value.append(TTSymbol("aParameterName"));
	
	return kTTErrNone;
}

TTErr Scenario::ProcessStart()
{
    // start the execution graph
    mExecutionGraph->start();
    
    // TODO : deal with the timeOffset
    // problem : if we offset the scheduler time it will never call ProcessStart method (called when progression == 0)
    // idea : add the offset afterward ? for any time process or is this specific to a scenario ?
    //mExecutionGraph->addTime(mExecutionGraph->getTimeOffset() * 1000);
    
    return kTTErrNone;
}

TTErr Scenario::ProcessEnd()
{
    // Trigger the end event
    mEndEvent->sendMessage(TTSymbol("Trigger"), kTTValNONE, kTTValNONE);
    
    // Notify the end event subscribers
    mEndEvent->sendMessage(TTSymbol("Notify"));
    
    return kTTErrNone;
}

TTErr Scenario::Process(const TTValue& inputValue, TTValue& outputValue)
{
    TTFloat64   progression, realTime;
    TTValue     v;
    
    if (inputValue.size() == 1) {
        
        if (inputValue[0].type() == kTypeFloat64) {
            
            progression = inputValue[0];
            
            // TODO : the SchedulerLib should also returns the realtime
            mScheduler->getAttributeValue(TTSymbol("realTime"), v);
            realTime = v[0];
            
            // update the mExecutionGraph to process the scenario
            if (mExecutionGraph->makeOneStep(realTime))
                return kTTErrNone;
            
            else
                // stop the scenario
                return this->sendMessage(TTSymbol("Stop"));
            
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::Compile()
{
    // compile the mExecutionGraph to prepare scenario execution
    // TODO : pass a time offset
    compileScenario(0);
    
    return kTTErrNone;
}

TTErr Scenario::TimeProcessAdd(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeProcessPtr        aTimeProcess;
    TTValue                 aCacheElement, v;
    TTValue                 startEvent, endEvent;
    TTValue                 duration, durationMin, durationMax, scenarioDuration;
    SolverVariablePtr       startVariable, endVariable;
    SolverObjectMapIterator it;
    
    if (inputValue.size() == 1) {
        
        if (inputValue[0].type() == kTypeObject) {
            
            aTimeProcess = TTTimeProcessPtr((TTObjectBasePtr)inputValue[0]);
            
            // check time process duration
            if (!aTimeProcess->getAttributeValue(TTSymbol("duration"), duration)) {
                
                // check if the time process is not already registered
                mTimeProcessList.find(&ScenarioFindTimeProcess, (TTPtr)aTimeProcess, aCacheElement);
                
                // if couldn't find the same time process in the scenario
                if (aCacheElement == kTTValNONE) {
                    
                    // create all observers
                    makeTimeProcessCacheElement(aTimeProcess, aCacheElement);
                    
                    // store time process object and observers
                    mTimeProcessList.append(aCacheElement);
                    
                    // add the time process events to the scenario
                    aTimeProcess->getAttributeValue(TTSymbol("startEvent"), startEvent);
                    TimeEventAdd(startEvent, kTTValNONE);
                    
                    aTimeProcess->getAttributeValue(TTSymbol("endEvent"), endEvent);
                    TimeEventAdd(endEvent, kTTValNONE);
                    
                    // get time process duration bounds
                    aTimeProcess->getAttributeValue(TTSymbol("durationMin"), durationMin);
                    aTimeProcess->getAttributeValue(TTSymbol("durationMax"), durationMax);
                    
                    // get scenario duration
                    this->getAttributeValue(TTSymbol("duration"), scenarioDuration);
                    
                    // retreive solver variable relative to each event
                    it = mVariablesMap.find(TTObjectBasePtr(startEvent[0]));
                    startVariable = SolverVariablePtr(it->second);
                    
                    it = mVariablesMap.find(TTObjectBasePtr(endEvent[0]));
                    endVariable = SolverVariablePtr(it->second);
                    
                    // update the Solver depending on the type of the time process
                    if (aTimeProcess->getName() == TTSymbol("Interval")) {
                        
                        // add a relation between the 2 variables to the solver
                        SolverRelationPtr relation = new SolverRelation(mEditionSolver, startVariable, endVariable, TTUInt32(durationMin[0]), TTUInt32(durationMax[0]));
                        
                        // store the relation relative to this time process
                        mRelationsMap.emplace(aTimeProcess, relation);

                    }
                    else {
                        
                        // limit the start variable to the process duration
                        // this avoid time crushing when a time process moves while it is connected to other process
                        startVariable->limit(duration, duration);
                        
                        // add a constraint between the 2 variables to the solver
                        SolverConstraintPtr constraint = new SolverConstraint(mEditionSolver, startVariable, endVariable, TTUInt32(durationMin[0]), TTUInt32(durationMax[0]), TTUInt32(scenarioDuration[0]));
                        
                        // store the constraint relative to this time process
                        mConstraintsMap.emplace(aTimeProcess, constraint);
                        
                    }
                }
                
                return kTTErrNone;
            }
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeProcessRemove(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeProcessPtr        aTimeProcess;
    TTValue                 aCacheElement;
    TTValue                 startEvent, endEvent;
    SolverObjectMapIterator it;
    
    if (inputValue.size() == 1) {
        
        if (inputValue[0].type() == kTypeObject) {
            
            aTimeProcess = TTTimeProcessPtr((TTObjectBasePtr)inputValue[0]);
            
            // try to find the time process
            mTimeProcessList.find(&ScenarioFindTimeProcess, (TTPtr)aTimeProcess, aCacheElement);
            
            // couldn't find the same time process in the scenario :
            if (aCacheElement == kTTValNONE)
                return kTTErrValueNotFound;
            
            else {
                
                // remove time process object and observers
                mTimeProcessList.remove(aCacheElement);
                
                // delete all observers
                deleteTimeProcessCacheElement(aCacheElement);
                
                // update the Solver depending on the type of the time process
                if (aTimeProcess->getName() == TTSymbol("Interval")) {
                    
                    // retreive solver relation relative to the time process
                    it = mRelationsMap.find(aTimeProcess);
                    SolverRelationPtr relation = SolverRelationPtr(it->second);
                    
                    mRelationsMap.erase(aTimeProcess);
                    delete relation;
                    
                } else {
 
                    // retreive solver constraint relative to the time process
                    it = mConstraintsMap.find(aTimeProcess);
                    SolverConstraintPtr constraint = SolverConstraintPtr(it->second);
                    
                    mConstraintsMap.erase(aTimeProcess);
                    delete constraint;
                }
                
                // remove the time process events from the scenario
                aTimeProcess->getAttributeValue(TTSymbol("startEvent"), startEvent);
                TimeEventRemove(startEvent, kTTValNONE);
                
                aTimeProcess->getAttributeValue(TTSymbol("endEvent"), endEvent);
                TimeEventRemove(endEvent, kTTValNONE);
                
                return kTTErrNone;
            }
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeProcessMove(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeProcessPtr        aTimeProcess;
    TTValue                 v;
    TTValue                 startEvent, endEvent;
    TTValue                 duration, scenarioDuration;
    TTSymbol                timeProcessType;
    SolverObjectMapIterator it;
    SolverError             sErr;
    
    if (inputValue.size() == 3) {
        
        if (inputValue[0].type() == kTypeObject && inputValue[1].type() == kTypeUInt32 && inputValue[2].type() == kTypeUInt32) {
            
            aTimeProcess = TTTimeProcessPtr((TTObjectBasePtr)inputValue[0]);
            
            // get time process events
            aTimeProcess->getAttributeValue(TTSymbol("startEvent"), startEvent);
            aTimeProcess->getAttributeValue(TTSymbol("endEvent"), endEvent);
            
            // get time process duration
            aTimeProcess->getAttributeValue(TTSymbol("duration"), duration);
            
            // get scenario duration
            this->getAttributeValue(TTSymbol("duration"), scenarioDuration);
            
            // update the Solver depending on the type of the time process
            timeProcessType = aTimeProcess->getName();
            
            if (timeProcessType == TTSymbol("Interval")) {
                
                // retreive solver relation relative to the time process
                it = mRelationsMap.find(aTimeProcess);
                SolverRelationPtr relation = SolverRelationPtr(it->second);
                
                sErr = relation->move(inputValue[1], inputValue[2]);

            } else {
                
                // retreive solver constraint relative to the time process
                it = mConstraintsMap.find(aTimeProcess);
                SolverConstraintPtr constraint = SolverConstraintPtr(it->second);
                
                // extend the limit of the start variable
                constraint->startVariable->limit(0, TTUInt32(scenarioDuration[0]));
                
                sErr = constraint->move(inputValue[1], inputValue[2]);
                
                // set the start variable limit back
                // this avoid time crushing when a time process moves while it is connected to other process
                constraint->startVariable->limit(TTUInt32(duration[0]), TTUInt32(duration[0]));
            }
            
            if (!sErr) {
                
                // update each solver variable value
                for (it = mVariablesMap.begin() ; it != mVariablesMap.end() ; it++)
                    
                    SolverVariablePtr(it->second)->update();
                
                return kTTErrNone;
            }
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeProcessLimit(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeProcessPtr        aTimeProcess;
    TTValue                 durationMin, durationMax;
    TTSymbol                timeProcessType;
    SolverObjectMapIterator it;
    SolverError             sErr;
    
    if (inputValue.size() == 3) {
        
        if (inputValue[0].type() == kTypeObject && inputValue[1].type() == kTypeUInt32 && inputValue[2].type() == kTypeUInt32) {
            
            aTimeProcess = TTTimeProcessPtr((TTObjectBasePtr)inputValue[0]);
            
            // update the Solver depending on the type of the time process
            timeProcessType = aTimeProcess->getName();
            
            if (timeProcessType == TTSymbol("Interval")) {
                
                // retreive solver relation relative to the time process
                it = mRelationsMap.find(aTimeProcess);
                SolverRelationPtr relation = SolverRelationPtr(it->second);
                
                sErr = relation->limit(inputValue[1], inputValue[2]);
                
            } else {
                
                // retreive solver constraint relative to the time process
                it = mConstraintsMap.find(aTimeProcess);
                SolverConstraintPtr constraint = SolverConstraintPtr(it->second);
                
                sErr = constraint->limit(inputValue[1], inputValue[2]);
            }
            
            if (!sErr) {
                
                // update each solver variable value
                for (it = mVariablesMap.begin() ; it != mVariablesMap.end() ; it++)
                    
                    SolverVariablePtr(it->second)->update();
                
                return kTTErrNone;
            }
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeEventAdd(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeEventPtr  aTimeEvent;
    TTValue         aCacheElement, scenarioDuration;
    
    if (inputValue.size() == 1) {
        
        if (inputValue[0].type() == kTypeObject) {
            
            aTimeEvent = TTTimeEventPtr((TTObjectBasePtr)inputValue[0]);
            
            // check if the time event is not already registered
            mTimeEventList.find(&ScenarioFindTimeEvent, (TTPtr)aTimeEvent, aCacheElement);
            
            // if couldn't find the same time event in the scenario
            if (aCacheElement == kTTValNONE) {
                
                // create all observers
                makeTimeEventCacheElement(aTimeEvent, aCacheElement);
                
                // store time event object and observers
                mTimeEventList.append(aCacheElement);
                
                // get scenario duration
                this->getAttributeValue(TTSymbol("duration"), scenarioDuration);
                
                // add variable to the solver
                SolverVariablePtr variable = new SolverVariable(mEditionSolver, aTimeEvent, TTUInt32(scenarioDuration[0]));
                
                // store the variables relative to those time events
                mVariablesMap.emplace(TTObjectBasePtr(aTimeEvent), variable);
            }
            
            return kTTErrNone;
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeEventRemove(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeEventPtr          aTimeEvent;
    TTValue                 aCacheElement;
    TTBoolean               found;
    SolverVariablePtr       variable;
    SolverObjectMapIterator it;
    
    if (inputValue.size() == 1) {
        
        if (inputValue[0].type() == kTypeObject) {
            
            aTimeEvent = TTTimeEventPtr((TTObjectBasePtr)inputValue[0]);
            
            // try to find the time event
            mTimeEventList.find(&ScenarioFindTimeEvent, (TTPtr)aTimeEvent, aCacheElement);
            
            // couldn't find the same time event in the scenario
            if (aCacheElement == kTTValNONE)
                return kTTErrValueNotFound;
            else {
                
                // remove time event object and observers
                mTimeEventList.remove(aCacheElement);
                
                // delete all observers
                deleteTimeEventCacheElement(aCacheElement);
                
                // retreive solver variable relative to each event
                it = mVariablesMap.find(aTimeEvent);
                variable = SolverVariablePtr(it->second);
                
                // remove variable from the solver
                // if it is still not used in a constraint
                found = NO;
                for (it = mConstraintsMap.begin() ; it != mConstraintsMap.end() ; it++) {
                    
                    found = SolverConstraintPtr(it->second)->startVariable == variable || SolverConstraintPtr(it->second)->endVariable == variable;
                    if (found) break;
                }
                
                if (!found) {
                    
                    // if it is still not used in a relation
                    for (it = mRelationsMap.begin() ; it != mRelationsMap.end() ; it++) {
                        
                        found = SolverRelationPtr(it->second)->startVariable == variable || SolverRelationPtr(it->second)->endVariable == variable;
                        if (found) break;
                    }
                }
                
                if (!found) {
                    mVariablesMap.erase(aTimeEvent);
                    delete variable;
                }
                
                return kTTErrNone;
            }
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeEventMove(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeEventPtr          aTimeEvent;
    TTValue                 v;
    TTSymbol                timeEventType;
    SolverVariablePtr       variable;
    SolverObjectMapIterator it;
    SolverError             sErr;
    
    if (inputValue.size() == 2) {
        
        if (inputValue[0].type() == kTypeObject && inputValue[1].type() == kTypeUInt32 ) {
            
            aTimeEvent = TTTimeEventPtr((TTObjectBasePtr)inputValue[0]);
            
            // retreive solver variable relative to the time event
            it = mVariablesMap.find(aTimeEvent);
            variable = SolverVariablePtr(it->second);
            
            // move all constraints relative to the variable
            for (it = mConstraintsMap.begin() ; it != mConstraintsMap.end() ; it++) {
                
                if (SolverConstraintPtr(it->second)->startVariable == variable)
                    sErr = SolverConstraintPtr(it->second)->move(TTUInt32(inputValue[1]), SolverConstraintPtr(it->second)->endVariable->get());
                    
                if (SolverConstraintPtr(it->second)->endVariable == variable)
                    sErr = SolverConstraintPtr(it->second)->move(SolverConstraintPtr(it->second)->startVariable->get(), TTUInt32(inputValue[1]));
                
                if (sErr)
                    break;
            }
            
            if (!sErr) {
                
                // update each solver variable value
                for (it = mVariablesMap.begin() ; it != mVariablesMap.end() ; it++)
                    
                    SolverVariablePtr(it->second)->update();
                
                return kTTErrNone;
            }
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeEventReplace(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeEventPtr          aFormerTimeEvent, aNewTimeEvent, timeEvent;
    TTTimeProcessPtr        aTimeProcess;
    TTBoolean               isInteractive;
    TTValue                 v, aCacheElement;
    SolverObjectMapIterator it;
    
    if (inputValue.size() == 2) {
        
        if (inputValue[0].type() == kTypeObject && inputValue[1].type() == kTypeObject) {
            
            aFormerTimeEvent = TTTimeEventPtr((TTObjectBasePtr)inputValue[0]);
            aNewTimeEvent = TTTimeEventPtr((TTObjectBasePtr)inputValue[1]);
            
            // try to find the former time event
            mTimeEventList.find(&ScenarioFindTimeEvent, (TTPtr)aFormerTimeEvent, aCacheElement);
            
            // couldn't find the former time event in the scenario
            if (aCacheElement == kTTValNONE)
                return kTTErrValueNotFound;
            
            else {
                
                // remove the former time event object and observers
                mTimeEventList.remove(aCacheElement);
                
                // delete all observers on the former time event
                deleteTimeEventCacheElement(aCacheElement);
                
                // create all observers on the new time event
                makeTimeEventCacheElement(aNewTimeEvent, aCacheElement);
                
                // store the new time event object and observers
                mTimeEventList.append(aCacheElement);
            }
            
            // is the new event interactive ?
            aNewTimeEvent->getAttributeValue(TTSymbol("interactive"), v);
            isInteractive = v[0];
                        
            // replace the former time event in all time process which binds on it
            for (mTimeProcessList.begin(); mTimeProcessList.end(); mTimeProcessList.next()) {
                
                aTimeProcess = TTTimeProcessPtr(TTObjectBasePtr(mTimeProcessList.current()[0]));
                
                aTimeProcess->getAttributeValue(TTSymbol("startEvent"), v);
                timeEvent = TTTimeEventPtr(TTObjectBasePtr(v[0]));
                
                if (timeEvent == aFormerTimeEvent) {
                    
                    aTimeProcess->sendMessage(TTSymbol("StartEventRelease"));
                    aTimeProcess->setAttributeValue(TTSymbol("startEvent"), TTObjectBasePtr(aNewTimeEvent));
                    continue;
                }
                
                aTimeProcess->getAttributeValue(TTSymbol("endEvent"), v);
                timeEvent = TTTimeEventPtr(TTObjectBasePtr(v[0]));
                
                if (timeEvent == aFormerTimeEvent) {
                    
                    aTimeProcess->sendMessage(TTSymbol("EndEventRelease"));
                    aTimeProcess->setAttributeValue(TTSymbol("endEvent"), TTObjectBasePtr(aNewTimeEvent));
                    
                    // a time process with an interactive end event cannot be rigid
                    v = TTBoolean(!isInteractive);
                    aTimeProcess->setAttributeValue(TTSymbol("rigid"), v);
                }
            }
            
            // retreive solver variable relative to the time event
            it = mVariablesMap.find(aFormerTimeEvent);
            SolverVariablePtr variable = SolverVariablePtr(it->second);
            
            // replace the time event
            // note : only in the variable as all other solver elements binds on variables
            variable->event = aNewTimeEvent;
            
            // update the variable (this will copy the date into the new time event)
            variable->update();
            
            // update the variables map
            mVariablesMap.erase(aFormerTimeEvent);
            mVariablesMap.emplace(aNewTimeEvent, variable);
            
            return kTTErrNone;
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeProcessActiveChange(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeProcessPtr    aTimeProcess;
    TTBoolean           active;
	
    if (inputValue.size() == 2) {
        
        if (inputValue[0].type() == kTypeObject && inputValue[1].type() == kTypeBoolean) {
            
            // get time process where the change comes from
            aTimeProcess = TTTimeProcessPtr((TTObjectBasePtr)inputValue[0]);
            
            // get new active value
            active = inputValue[1];
            
            // TODO : warn Solver (or mExecutionGraph ?) that this time process active state have changed
            // TODO : update all Solver (or mExecutionGraph ?) consequences by setting time processes attributes that are affected by the consequence
        }
    }
    
    return kTTErrGeneric;
}

TTErr Scenario::TimeEventTrigger(const TTValue& inputValue, TTValue& outputValue)
{
    TTTimeEventPtr aTimeEvent;
    
    if (inputValue.size() == 1) {
        
        if (inputValue[0].type() == kTypeObject) {
            
            // get time event to trigger
            aTimeEvent = TTTimeEventPtr((TTObjectBasePtr)inputValue[0]);
            
            // cf ECOMachine::receiveNetworkMessage(std::string netMessage)
            
            if (mExecutionGraph) {

                // if the excecution graph is running
                if (mExecutionGraph->getUpdateFactor() != 0) {
                
                    // append the event to the event queue to process its triggering
                    TTLogMessage("Scenario::TimeEventTrigger : %p\n", TTPtr(aTimeEvent));
                    mExecutionGraph->putAnEvent(TTPtr(aTimeEvent));
                
                    return kTTErrNone;
                }
            }
        }
    }

    return kTTErrGeneric;
}

TTErr Scenario::WriteAsXml(const TTValue& inputValue, TTValue& outputValue)
{
	TTXmlHandlerPtr	aXmlHandler = NULL;
	
	aXmlHandler = TTXmlHandlerPtr((TTObjectBasePtr)inputValue[0]);
	
	// TODO : pass the XmlHandlerPtr to all the time processes and their time events of the scenario to write their content into the file
	
	return kTTErrGeneric;
}

TTErr Scenario::ReadFromXml(const TTValue& inputValue, TTValue& outputValue)
{
	TTXmlHandlerPtr	aXmlHandler = NULL;
	
	aXmlHandler = TTXmlHandlerPtr((TTObjectBasePtr)inputValue[0]);
	
	// TODO : pass the XmlHandlerPtr to all the time processes of the scenario to read their content from the file
	
	return kTTErrGeneric;
}

TTErr Scenario::WriteAsText(const TTValue& inputValue, TTValue& outputValue)
{
	TTTextHandlerPtr	aTextHandler;
	
	aTextHandler = TTTextHandlerPtr((TTObjectBasePtr)inputValue[0]);
	
	// TODO : pass the TextHandlerPtr to all the time processes of the scenario to write their content into the file
	
	return kTTErrGeneric;
}

TTErr Scenario::ReadFromText(const TTValue& inputValue, TTValue& outputValue)
{
	TTTextHandlerPtr aTextHandler;
	TTValue	v;
	
	aTextHandler = TTTextHandlerPtr((TTObjectBasePtr)inputValue[0]);
	
    // TODO : pass the TextHandlerPtr to all the time processes of the scenario to read their content from the file
	
	return kTTErrGeneric;
}

void Scenario::makeTimeProcessCacheElement(TTTimeProcessPtr aTimeProcess, TTValue& newCacheElement)
{
    newCacheElement.clear();
    
	// 0 : cache time process object
	newCacheElement.append((TTObjectBasePtr)aTimeProcess);
}

void Scenario::deleteTimeProcessCacheElement(const TTValue& oldCacheElement)
{
    ;
}

void Scenario::makeTimeEventCacheElement(TTTimeEventPtr aTimeEvent, TTValue& newCacheElement)
{
    newCacheElement.clear();
    
	// 0 : cache time event object
	newCacheElement.append((TTObjectBasePtr)aTimeEvent);
}

void Scenario::deleteTimeEventCacheElement(const TTValue& oldCacheElement)
{
    ;
}

#if 0
#pragma mark -
#pragma mark Some Methods
#endif

void ScenarioFindTimeProcess(const TTValue& aValue, TTPtr timeProcessPtrToMatch, TTBoolean& found)
{
	found = (TTObjectBasePtr)aValue[0] == (TTObjectBasePtr)timeProcessPtrToMatch;
}

void ScenarioFindTimeProcessWithTimeEvent(const TTValue& aValue, TTPtr timeEventPtrToMatch, TTBoolean& found)
{
    TTTimeProcessPtr    timeProcess = TTTimeProcessPtr(TTObjectBasePtr(aValue[0]));
    TTValue             v;
    
    // ignore interval process
    if (timeProcess->getName() != TTSymbol("Interval")) {
        
        // check start event
        timeProcess->getAttributeValue(TTSymbol("startEvent"), v);
        found = TTObjectBasePtr(v[0]) == TTObjectBasePtr(timeEventPtrToMatch);
        
        if (found)
            return;
        
        // check end event
        timeProcess->getAttributeValue(TTSymbol("endEvent"), v);
        found = TTObjectBasePtr(v[0]) == TTObjectBasePtr(timeEventPtrToMatch);
        
        return;
    }
}

void ScenarioFindTimeEvent(const TTValue& aValue, TTPtr timeEventPtrToMatch, TTBoolean& found)
{
    found = (TTObjectBasePtr)aValue[0] == (TTObjectBasePtr)timeEventPtrToMatch;
}

void ScenarioGraphTransitionTimeEventCallBack(void* arg)
{
    // cf ECOMachine : crossAControlPointCallBack function

    TTTimeEventPtr aTimeEvent = (TTTimeEventPtr) arg;
    
	aTimeEvent->sendMessage(TTSymbol("Happen"));
}

/*
void waitedTriggerPointMessageCallBack(void* arg, bool isWaited, TransitionPtr transition)
{
	ECOMachine* currentECOMachine = (ECOMachine*) arg;
    
	if (currentECOMachine->hasTriggerPointInformations(transition)) {
		TriggerPointInformations currentTriggerPointInformations = currentECOMachine->getTriggerPointInformations(transition);
        
		if (currentTriggerPointInformations.m_waitedTriggerPointMessageAction != NULL) {
			currentTriggerPointInformations.m_waitedTriggerPointMessageAction(currentECOMachine->m_waitedTriggerPointMessageArg,
																			  isWaited,
																			  currentTriggerPointInformations.m_triggerId,
																			  currentTriggerPointInformations.m_boxId,
																			  currentTriggerPointInformations.m_controlPointIndex,
																			  currentTriggerPointInformations.m_waitedString);
            
		}
	}
}
*/