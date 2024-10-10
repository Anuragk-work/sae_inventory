<?php
/**
 * Trait for all codes related to state of the document
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2015 Intacct Corporation All, Rights Reserved
 */

/**
 * Trait for all codes related to state of the document
 */
trait DocumentStateTrait
{

    /**
     * assign the default state for the document
     *
     * @param array $values values
     */
    private function assignDefaultState(&$values)
    {
        $approvalEnabled = $this->IsDocParApprovalEnabled($values['DOCPARID']);
        if (empty($values['STATE']) || $values['STATE'] == self::SUBMITTED_STATE) {
            if ($approvalEnabled) {
                $values['STATE'] = self::SUBMITTED_STATE;
            } else {
                $values['STATE'] = $this->getFinalState($values);
            }
        }
    }

    /**
     * get state of the document which is not enabled for approval
     *
     * @param array $values values
     *
     * @return string State
     */
    public function getFinalState(&$values)
    {
        if (!isset($values[self::ALLOWED_DOCS_COUNT]) || $values[self::ALLOWED_DOCS_COUNT] === '') {
            /**
             * @var DocumentParamsManager $docParMgr
             */
            $docParMgr = $this->get_docpar_manager();
            $allowedDocs = $docParMgr->getRecallDocs($values['_DOCPAR']['DOCID']);
            $values[self::ALLOWED_DOCS_COUNT] = count($allowedDocs);
        }

        if (
            $values[self::ALLOWED_DOCS_COUNT] == 0
            && !in_array($values['DOCPARID'], array(BUILD_KIT, DIS_KIT))
        ) {
            $state = self::CLOSED_STATE;
        } else {
            $state = self::DEFAULT_STATE;
        }

        return $state;

    }

    /**
     * validate given states of the document
     *
     * @param array $values values
     *
     * @return bool
     */
    protected function validateDocumentState(&$values)
    {
        $gErr = Globals::$g->gErr;
        $creinstalled = CRESetupManager::isCREInstalled();

        // assign default state if it is empty
        $this->assignDefaultState($values);

        $errCnt = $gErr->ErrorCount;
        $curState = $values['EXISTING_DOC']['STATE'];
        $newState = $values['STATE'];
        $ok = true;

        // allowing to edit construction related fields in converted state
        // checking for cre is enabled and state as converted and mod as purchase or order
        if($creinstalled && $curState == self::CONVERTED_STATE && ($this->mod == "po" || $this->mod == "so")){
            $ok = true;
        }else { // regular part
            if (
                !empty($curState)
                && in_array(
                    $curState, array(self::CONVERTED_STATE)
                )&& $values['HASCHANGE'] !== 'true'
            ) {
                $msg = 'Transaction ' . $values['EXISTING_DOC']['DOCID'] . ' is ' . $values['EXISTING_DOC']['STATE']
                       . '. Cannot edit ' . $values['EXISTING_DOC']['STATE'] . ' transactions.';
                $gErr->addIAError(
                    'INV-1431', __FILE__ . ':' . __LINE__,
                    'Error on editing ' . $values['EXISTING_DOC']['DOCID'],
                    ['DOCID' => $values['EXISTING_DOC']['DOCID']],
                    $msg,
                    ['DOCID' => $values['EXISTING_DOC']['DOCID'], 'DOCSTATE' => $values['EXISTING_DOC']['STATE']],
                    'Invalid Operation'
                );
                $ok = false;
            }
        }

        // Check for disallowed resubmits.
        $doReposting        = $this->isRepostingRequired($values);
        if (
            $ok
            && ($newState == self::SUBMITTED_STATE)
            && !empty($curState)
            && in_array($curState, array(self::PARTIALLY_APPROVED_STATE, self::APPROVED_STATE, self::SUBMITTED_STATE))
            && $doReposting
        ) {
            $gErr->addIAError(
                'INV-1432',
                __FILE__ . ':' . __LINE__,
                'You cannot resubmit the transaction when it is submitted or partially/fully approved.'
            );
            $ok = false;
        }

        // Check for disallowed drafts
        if (
            $ok
            && $newState == self::DRAFT_STATE
            && !empty($curState)
            && !in_array(
                $curState,
                array(
                    self::DECLINED_STATE, self::DRAFT_STATE, self::SUBMITTED_STATE, self::PARTIALLY_APPROVED_STATE, self::ANALYZING_STATE
                )
            )
        ) {
            $gErr->addIAError(
                'INV-1433',
                __FILE__ . ':' . __LINE__,
                'You cannot draft the transaction when it is posted.'
            );
            $ok = false;
        }

        $approvalEnabled = $this->IsDocParApprovalEnabled($values['DOCPARID']);

        if ($approvalEnabled) {

            // if approval enabled document comes up with posting state
            if (
                $ok
                && $newState != $curState
                && $curState != self::APPROVED_STATE
                && !in_array(
                    $newState,
                    array(
                        self::DECLINED_STATE, self::DRAFT_STATE, self::SUBMITTED_STATE, self::PARTIALLY_APPROVED_STATE,
                        self::ANALYZING_STATE
                    )
                )
                && $values['BACKORDER'] != 'Yes'
            ) {
                if ( empty($curState) || !$this->isDocumentInPostingState($curState) ) {
                    $gErr->addIAError(
                        'INV-1434',
                        __FILE__ . ':' . __LINE__,
                        'Transactions must be submitted before it can be approved.'
                    );
                    $ok = false;
                }
            }

            // modifying approved document
            if (
                $ok
                && $this->isDocumentInPostingState($newState)
                && $curState == $newState
            ) {

                $warn = $this->validateForReApproval($values);

                $fileLine = __FILE__ . ':' . __LINE__;
                if ($warn && $this->_warningValidation && $this->shouldWarn(null, $data, [$fileLine])) {
                    $msg = "The transaction has to be resubmitted because it has been modified.";
                    $gErr->AddDetailWarning("", $fileLine, $msg, "", "", "Submit");
                    $ok = false;
                }
            }

        } else {
            $validStates = array(
                self::DRAFT_STATE, self::PENDING_STATE, self::CLOSED_STATE,self::PARTIALLY_CONVERTED_BY_LINE_STATE, self::EXCEPTION_STATE, self::ANALYZING_STATE
            );

            // if curState is not empty we are in edit mode.
            // in edit mode ignore the partially converted document, we need to allow editing the partially convrted documents
            if (!empty($curState)) {
                $validStates[] = self::PARTIALLY_CONVERTED_STATE;
                $validStates[] = self::CONVERTED_BY_LINE_STATE;
                $validStates[] = self::EXCEPTION_STATE;
            }

            // allowing to edit construction related fields in converted state
            // checking for cre is enabled and state as converted and mod as purchase or order
            if($creinstalled && in_array($newState, [self::CONVERTED_STATE, self::INPROGRESS_STATE]) && ($this->mod == "po" || $this->mod == "so")){
                $ok = true;
            }else{ // regular part
                if (
                    $ok
                    && !in_array(
                        $newState,
                        $validStates
                    )&& $values['HASCHANGE'] !== 'true'
                ) {
                    $gErr->addIAError(
                        'INV-1435',
                        __FILE__ . ':' . __LINE__,
                        "The state of the transaction has to be Draft, Pending, Partially Converted or Closed."
                    );
                    $ok = false;
                }
            }

        }

        if (
            $ok
            && !empty($curState)
            && $this->isDocumentInPostingState($curState)
            && !$this->isDocumentInPostingState($newState)
        ) {
            if ($approvalEnabled) {
                // resubmitting case
                // should unpost the old postings
            } else {
                $gErr->addIAError(
                    'INV-1436',
                    __FILE__ . ':' . __LINE__,
                    "You cannot change state of the posted transaction to '" . $newState . "'.",
                    ['NEWSTATE' => $newState]
                );
                $ok = false;
            }
        }

        // temporary fix to allow 2.1 and 3.0 calls even if invalid state is passed.
        if (!$ok && !$errCnt && ($this->_fromAPI || $values['FROMAPI_2.1'])) {
            $gErr->Clear();

            $perfdata = Globals::$g->perfdata;
            $senderId = $perfdata->getXmlpartnerid();
            if (!empty($curState)) {

                if ($curState != $values['STATE']) {
                    LogToFile(
                        "iascmInvalidState: Replacing the state '" . $values['STATE'] . "' with '$curState' " .
                        " cny# : " . GetMyCompany() . " title : " . GetMyCompanyTitle() . " senderid : " . $senderId
                        . "\n"
                    );
                }
                $values['STATE'] = $curState;
            } else {
                $invalidState = $values['STATE'];
                $values['STATE'] = '';
                $this->assignDefaultState($values);

                if ( $values['STATE'] != $invalidState ) {
                    LogToFile(
                        "iascmInvalidState: Ignoring the state '" . $invalidState .
                        "' and keeping it with '" . $values['STATE'] . "'" .
                        " cny# : " . GetMyCompany() . " title : " . GetMyCompanyTitle() . " senderid : " . $senderId
                        . "\n"
                    );
                }
            }

            $ok = true;
        }

        return $ok;
    }

    /**
     * check the state of the document to allow postings
     *
     * @param string $state state of the document
     *
     * @return bool
     */
    public static function isDocumentInPostingState($state)
    {
        $ok = true;
        if (
            $state == self::DRAFT_STATE
            || $state == self::SUBMITTED_STATE
            || $state == self::PARTIALLY_APPROVED_STATE
            || $state == self::DECLINED_STATE
            || $state == self::EXCEPTION_STATE
            || $state == self::ANALYZING_STATE
        ) {
            $ok = false;
        }

        return $ok;
    }

    /**
     * check the state of the document to allow creation of compliance records for primary document
     *
     * @param string $state state of the document
     *
     * @return bool
     */
    public static function shouldWeCreateComplianceRecordsForPrimaryDoc($state)
    {
        $ok = false;
        if (
            $state == self::DRAFT_STATE
            || $state == self::PENDING_STATE
            || $state == self::CLOSED_STATE
            || $state == self::SUBMITTED_STATE
            || $state == self::PARTIALLY_APPROVED_STATE
        ) {
            $ok = true;
        }

        return $ok;
    }
}