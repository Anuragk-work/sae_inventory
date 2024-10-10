<?php
/**
 * =============================================================================
 *
 * @filesource CostingChangesEditor.cls
 * @author
 * @copyright  2019, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */


/**
 * class ReplenishmentEditor extends FormEditor
 */
class CostingChangesEditor extends FormEditor
{

    /** @var string  $module*/
    private $module = 'inv';


    /**
     * Constructor
     *
     * @param array $_params
     */
    function __construct($_params=array())
    {
        parent::__construct($_params);

        //Add handlers for buttons/menus on this form
        $this->addActionHandlers();
    }

    /**
     * Get the layout file that has to be used for this editor
     *
     * @param array $params
     *
     * @return string       the name of the layout file
     */
    protected function getMetadataKeyName(&$params)
    {
        $file = 'costingchanges_form.pxml';
        return $file;
    }

    /**
     * Method getJavaScriptFileNames - get list of required client-side script files
     *
     * @return array of required javascript files to be included
     */
    protected function getJavaScriptFileNames()
    {
        return array('../resources/js/invhlthrun.js');  // re-use this
    }


    /**
     * @param array     $_params
     * @param array     $obj
     * @param bool      $ok
     *
     * @return bool
     */
    protected function innerProcessCreateAction(&$_params, &$obj, $ok)
    {
        // not sure if this is needed, but invHlthRunEditor does this
        $obj['MODULE'] = $this->module;
        return parent::innerProcessCreateAction($_params, $obj, $ok);
    }


    /**
     * @param string    $field          the field name
     */
    private function hideSection( $field )
    {
        $this->setProperty( $field, 'hidden', true );
    }


    /**
     * @param string    $field          the field name
     */
    private function showSection( $field )
    {
        $this->setProperty( $field, 'hidden', false );
    }


    /**
     * @param  string   $field          the field name
     * @param  string   $property       property to set, like 'hidden'
     * @param  string   $to             what to set it to
     * @param  bool     $isField        is it a field or a section?
     */
    private function setProperty( $field, $property, $to, $isField = false )
    {
        $view = $this->getView();
        $view->findAndSetProperty(array('id' => $field), array($property => $to), $isField ? EditorComponentFactory::TYPE_FIELD : EditorComponentFactory::TYPE_SECTION);
    }


    /**
     * mediateDataAndMetadata
     *
     * @param  array &$obj    Object variable
     *
     * @return bool           true on success
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $ok = parent::mediateDataAndMetadata($obj);

        // widen the description field
        $this->setProperty('DESCRIPTION','numofcols', 200, true );
        $obj['DESCRIPTION'] = "";

        //Initialize our obj data when we are showing the form in the new state
        if ($this->state == $this->kShowNewState) {
            $this->hideSection('updatedGridSection');
            $this->showSection('previewGridSection');
            $obj['CHANGES'] = $this->getListOfPotentialChanges();
            if (empty($obj['CHANGES'])) {
                $obj['DESCRIPTION'] = _("COGS in the Inventory subledger are all up-to-date.");
            }
        } else {
            $this->hideSection('previewGridSection');
            $this->showSection('updatedGridSection');
            if (empty($obj['CHANGES'])) {
                $obj['DESCRIPTION'] = _("COGS in the Inventory subledger did not change.");
            } else {
                $obj['CHANGES'] = $this->removeNonCogsInbound($obj['CHANGES']);

                $obj['DESCRIPTION'] .= count($obj['CHANGES']) . _(" costing issues were fixed.  ");

                foreach ($obj['CHANGES'] as $oneCCHrecord) {
                    if (isset($oneCCHrecord['COGSADJUSTMENTNEEDED']) && ($oneCCHrecord['COGSADJUSTMENTNEEDED'] != 0.00)) {
                        $obj['DESCRIPTION'] .= _("Some updates could not be posted to the General Ledger because the period is closed.  Use Prior Period COGS Adjustments to align the ledgers.");
                        break;
                    }
                }
                if (($obj['ERRORSNOGL'] ?? 0) > 0) {
                    $obj['DESCRIPTION'] .= $obj['ERRORSNOGL'] . _(" COGS batches could not be updated because of these errors: ") . $obj['GLERRORS'];
                }
            }
        }
        return $ok;
    }


    /**
     *      For now, 2019 R3, Tracy doesn't want the inbound triggering transactions to show.
     *  Idea is that we may figure out how to show them later....
     *
     * Note: this routine modifies the passed-in array, which is not by-ref, and so a copy can be made, which can
     *       be quite expensive.  But, we only do it once.
     *
     * @param array $records        Cost Change History records to be trimmed.
     *
     * @return array                The new array
     */
    private function removeNonCogsInbound($records)
    {
        $changesMade = false;
        foreach ($records as $key => $record) {
            // we only want COGS-affecting transactions, and will specifically remove inbound non-COGS here....
            if (($record['INCREMENTORDECREMENT'] == 'I') && ($record['COGSPOSTEDBEFORE'] === null)) {
                unset($records[$key]);      // sadly, we have to let you go.
                $changesMade = true;
            }
            if ($record['TRANSACTIONNAME'] == _("STANDARD COST CHANGE")) {  // the weird standard-cost placeholder
                unset($records[$key]);      // sadly, we have to let you go.
                $changesMade = true;
            }
        }
        // Our grid control HATES having missing row numbers. so make sure the array is in 0...n-1 sequence
        return $changesMade ? array_values($records) : $records;
    }


    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $buttons = array();
        $runOp = GetOperationId('inv/activities/costingchanges/create');
        $runOpAutorized = CheckAuthorization($runOp);
        if ($runOpAutorized) {
            $this->setButtonDetails($buttons,'idRunUpdates', 'btnRunUpdates', 'IA.RUN_UPDATES', 'runupdates', true, 'runUpdatesAction()', false);
        }
        return $buttons;
    }


    /**
     * Add button/menu handlers
     */
    private function addActionHandlers()
    {
        $this->kActionHandlers['runupdates'] = array(
            'handler' => 'runUpdates',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
        $this->kActionHandlers['applydaterange'] = array(
            'handler' => 'applyDateRange',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
    }


    /**
     *      What transactions that affect COGS may need changing by the costing code?
     *
     * @return array        The list of records, in CostChangeHistory format, that may need changing
     */
    private function getListOfPotentialChanges()
    {
        $values = [];
        $values['FROM_UI']           = true;
        $values['ANALYZE_OR_UPDATE'] = InvHlthRunManager::QuickAnalyze;  // not really, but identify as Quick

        $eMgr = Globals::$g->gManagerFactory->getManager('invhlthrun');
        $ret = $eMgr->getListOfPotentialChanges($values);
        return $ret;
    }


    /**
     * Handler to process the 'Run updates' button action triggered from JS code
     *
     * @param array $_params    the metadata
     *
     * @return bool             true on success
     */
    protected function runUpdates(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        // Eventually there may be filters or something, but for now there aren't any parameters that we care about...
        $ok = $this->retrieveObjectFromView($_params, $obj);

        $values = [];
        $values['FROM_UI']                  = true;
        $values['ANALYZE_OR_UPDATE']        = InvHlthRunManager::QuickUpdate;
        $values['DESCRIPTION']              = _("Costing updates run");
        $values['NOTES']                    = _("Run on ") . date('n/d/Y h:i:s A');
        $values['SUMMARY_CHILDREN_ONLY']    = true; // only the summary records from the result
        $values['FROMITEMID']               = '';   // filters could fill these in...
        $values['TOITEMID']                 = '';
        $values['ITEMGLGROUP']              = '';
        $values['WAREHOUSEID']              = '';
        $values['LOCATIONID']               = '';

        $eMgr = Globals::$g->gManagerFactory->getManager('invhlthrun');
        $ok = $ok && $eMgr->add($values);

        $obj['CHANGES']         = $values['CHANGES'];
        $obj['ERRORSDFOUND']    = $values['ERRORSDFOUND'];
        $obj['ERRORSQTY0']      = $values['ERRORSQTY0'];
        $obj['ERRORSDFIXED']    = $values['ERRORSDFIXED'];
        $obj['ERRORDATA']       = $values['ERRORDATA'];

        return $ok;
    }


    /**
     * Handler to process the 'Apply Date Range' button action triggered from JS code
     *
     * @param array $_params    the metadata
     *
     * @return bool             true on success
     */
    protected function applyDateRange(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;
        $obj['CHANGES'] = [];   // clear any prior changes

            // Eventually there may be filters or something, but for now there aren't any parameters that we care about...
        $ok = $this->retrieveObjectFromView($_params, $obj);

        // Get the user's dates, and default them as needed
        $startDate = $obj['REPORTING_START_DATE'] ?? GetCurrentDate(IADATE_USRFORMAT);
        $endDate   = $obj['REPORTING_END_DATE']   ?? GetCurrentDate(IADATE_USRFORMAT);

        $eMgr = Globals::$g->gManagerFactory->getManager('costchangehistory');
        $changes = $eMgr->getFromCostingDateRange($startDate, $endDate);
        $ok = $ok && ($changes !== false);
        if ($ok) {
            $obj['CHANGES'] = (array)$changes;
        }

        return $ok;
    }


}

