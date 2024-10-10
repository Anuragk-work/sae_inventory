<?php


/**
 * @author
 * @access public
 */
class DocumentEventManager
{

    /**
     * @var   string|array      $workflow
     */
    var $workflow;

    /**
     * @var EntityManager $workflowMgr
     */
    var $workflowMgr;


    /**
     * @access private
     */
    function __construct()
    {
    }


    /**
     * @param string|string[]|string[][]    $workflow
     * @param EntityManager     $workflowMgr
     */
    function Init($workflow, $workflowMgr)
    {
        $this->SetWorkflow($workflow);
        $this->SetWorkflowManager($workflowMgr);
    }


    /**
     * @param string|string[]|string[][]  $workflow
     */
    function SetWorkflow($workflow = '')
    {
        $this->workflow = $workflow;
    }

    /**
     * @param EntityManager|null $workflowMgr
     */
    function SetWorkflowManager($workflowMgr = null)
    {
        $this->workflowMgr = $workflowMgr;
    }

    /**
     * @return EntityManager
     */
    function GetWorkflowManager()
    {
        return $this->workflowMgr;
    }

    /**
     * @param array  $values
     * @param string $event
     *
     * @return bool
     */
    function ProcessEvent(&$values, $event = '')
    {

        global $gErr;
        //eppp_p($values['STATE']);eppp_p($event);
        if (!$this->ValidateStateAction($values['STATE'], $event)) {
            $msg = "The event is not valid for the state of the document";
            $gErr->addIAError('INV-0354', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        if ($this->workflow['manager_event_actions'][$event]) {

            $workFlowFuncs = $this->workflow['manager_event_actions'][$event];
            $wflCount = count($workFlowFuncs);

            $source = "DocumentEventManager::ExecuteWorkflow";

            $ok = $this->workflowMgr->_QM->beginTrx($source);

            for ($i = 0; $i < $wflCount; $i++) {
                $func = $workFlowFuncs[$i];
                $ok = $ok && $this->workflowMgr->$func($values);
            }

            if ($ok) {
                // Add the audit trail -- ignore save and create
                if ($event != 'ACTION_CREATE' && $event != 'ACTION_SAVE') {
                    $auditTrailSession = AuditTrailSession::getInstance();
                    $workflowAction = null;
                    foreach($this->workflow['actions'] as $label => $value) {
                        if ($value == $event) {
                            $workflowAction = $label;
                            break;
                        }
                    }

                    if ($workflowAction === null) {
                        LogToFile("Unexpected event $event found while attempting to write the Audit Trail.");
                    } else {
                        /**
                         * @var EntityManager $mgr
                         */
                        $mgr = $this->workflowMgr;
                        try {
                            $auditTrailSession->addAuditEvent(
                                $mgr->getAuditEntity(), $values['DOCID'], AuditTrail::AUDITTRAIL_EVENT_WORKFLOW,
                                null, $workflowAction
                            );
                        } catch (IAException $ex) {
                            LogToFile("Exception writing audit log in " . __FILE__.'.'.__LINE__);
                        }
                    }
                }
            }

            $ok = $ok && $this->workflowMgr->_QM->commitTrx($source);

            if (!$ok) {

                // do *not* add error, if it has only warnings
                if(!HasErrors() && HasWarnings()) {
                    $this->workflowMgr->_QM->rollbackTrx($source);
                    return false;
                }

                $msg = "Could not execute workflow";
                $gErr->addIAError('INV-0355', __FILE__ . ':' . __LINE__, $msg, []);
                $this->workflowMgr->_QM->rollbackTrx($source);
            }

            return $ok;
        } else {
            $msg = "Could not find the manager action";
            $gErr->addIAError('INV-0356', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }
    }


    /**
     * @param string $state
     * @param string $event
     * @access private
     *
     * @return bool
     */
    function ValidateStateAction($state, $event)
    {
        global $gErr;
        if (isset($state)) {
            $valid_state_actions = $this->get_state_actions($state);
            // added is_array check to avoid exception for php 8.1
            if (!is_array($valid_state_actions) || !in_array($event, $valid_state_actions)) {
                $msg = "Not a valid action for the document state";
                $gErr->addIAError('INV-0357', __FILE__ . ':' . __LINE__, $msg, [], "Unable To process the document event", []);
                return false;
         }
        }
        return true;
    }



    /**
     * @access private
     *
     * @param string $state
     *
     * @return array|false
     */
    function get_state_actions($state)
    {
        global $gErr;

        $valid_state_actions = $this->workflow['valid_state_actions'][$state];

        if (is_null($valid_state_actions) || (is_countable($valid_state_actions) && count($valid_state_actions) == 0)){
            $msg = "Could not find valid actions for the document state";
            $gErr->addIAError('INV-0358', __FILE__ . ':' . __LINE__, $msg, [], "Unable To process the document event", []);
            return false;
        }
        return $valid_state_actions;
    }


}

