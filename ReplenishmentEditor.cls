<?php
/**
 * =============================================================================
 *
 * @filesource ReplenishmentEditor.cls
 * @author
 * @copyright  2018, Intacct Corporation, All Rights Reserved
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
class ReplenishmentEditor extends FormEditor
{
    /** @var string $mod */
    var $mod = 'inv';

    /**
     * @var array
     */
    protected $additionalTokens = [
        'IA.VIEW_REPLENISHMENT_RUN'
    ];


    /**
     * {{{ Constructor
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
        $file = 'replenishment_form.pxml';
        return $file;
    }

    /**
     * Method getJavaScriptFileNames - get list of required client-side script files
     *
     * @return array of required javascript files to be included
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles = array("../resources/js/replenishment.js");
        return $jsfiles;
    }


    /**
     * @param string    $field          the field name
     * @param string    $type           the UI field type
     */
    private function hideField($field, $type = EditorComponentFactory::TYPE_FIELD )
    {
        $this->setProperty($field, 'hidden', true, $type);
    }


    /**
     * @param string    $field          the field name
     * @param string    $type           the UI field type
     */
    private function showField($field, $type = EditorComponentFactory::TYPE_FIELD )
    {
        $this->setProperty($field, 'hidden', false, $type);
    }


    /**
     * @param string $field    the field name
     * @param string $property property to set, like 'hidden'
     * @param string $to       what to set it to
     * @param string $type     the UI field type
     */
    private function setProperty($field, $property, $to, $type = EditorComponentFactory::TYPE_FIELD)
    {
        $view = $this->getView();
        $fields = array();
        $find = ($type === EditorComponentFactory::TYPE_SECTION) ? 'id' : 'path';  // maybe add TYPE_SUBSECTION?
        $view->findComponents(array($find => $field), $type, $fields);
        foreach ($fields as $oneField) {
            $oneField->setProperty($property, $to);
        }
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

        // is this request specifically for Supplies?
        $isSupplies      = ((Request::$r->_supplies ?? 'false') === 'true');    // first time?
        if ( ! $isSupplies) {
            $isSupplies  = (($obj['is_supplies'] ?? 'false') === 'true');       // subsequent run?
        }

        // Is Deliver-To available?
        $mgr             = Globals::$g->gManagerFactory->getManager('podocument', true, ['DOCTYPE' => $obj['TRANSACTION_DEFINITION']]);
        $deliverToOn     = $mgr->isDeliverToHeaderItemEnable() || $mgr->isVATEnabled();
        $deliverToHeader = $mgr->deliverToHeaderDefault();  // will return '' if deliver-to is not on.

        //Initialize our obj data when we are showing the form in the new state
        if ($this->state == $this->kShowNewState) {
            GetModulePreferences(Globals::$g->kINVid, $inventoryPrefs);

            $obj['TRANSACTION_DEFINITION'] = $isSupplies ? $inventoryPrefs['SUPPLIESINVENTORYPO'] : $inventoryPrefs['DEFAULT_PURCHASE_TRANSACTION'];
            $obj['TRANSACTION_DATE'] = GetCurrentDate();
            $obj['FILTER_ASOFDATE'] = GetCurrentDate();
            $tokens = [ [ 'id' => 'IA.MORE_FILTERS_DOT' ] ];
            $text = getLocalizedTextWithThrow($tokens);
            $obj['FILTERS_TOGGLE'] = ($obj['FILTERS_TOGGLE']) ?: GT($text,'IA.MORE_FILTERS_DOT');
            $obj['DELIVERTOHEADER'] = $deliverToHeader;
        }

        $poDocumentParamsManager    = Globals::$g->gManagerFactory->getManager('podocumentparams');
        $docpar                     = $poDocumentParamsManager->GetLatestRaw( $obj['TRANSACTION_DEFINITION']);
        $allowedToChangeDeliverTo   = 'true';
        $deptOverride               = false;
        $locOverride                = false;
        if (($docpar !== false) && (isset($docpar[0]))) {
            $docpar = $docpar[0];
            $allowedToChangeDeliverTo   = ($docpar['ALLOWEDITDELIVERTO'] == 'T');   // can the user CHANGE the Deliver-To?
            $deptOverride               = ($docpar['DEPTOVERRIDE'] == 'T');
            $locOverride                = ($docpar['LOCOVERRIDE'] == 'T');
        }

        // show location and department if multi-entiry company at the root (for location) and not vat (for both)
        GetTaxEngine('po',TaxSolutionManager::TAXSOLUTION_AVALARA,$isAvaVatEnabled);
        $showDepartment = $deptOverride && !$isAvaVatEnabled;
        if ( $showDepartment ) {
            $this->showField("DEPARTMENT");
        }

        $showLocation = $locOverride && IsMultiEntityCompany() && !$isAvaVatEnabled;
        if ($showLocation) {
            $this->showField("LOCATION");   // even if not at the root, there might be sub-locations that are ok
        }

        $this->hideField("WAREHOUSEID"); // if present.  It is the warehouse ID in the Dimensions...

        if (IsMultiEntityCompany() && GetContextLocation()) {
            $obj['FILTER_LOCATIONKEY'] = GetContextLocation(true);  // true returns the location short name
        }

        // Is Deliver-To an option?  If not, hide the relevent fields.
        if ($deliverToOn == false) {
            $this->hideField('DELIVERTOHEADER');
            $this->hideField('DELIVERTOKEY');
        } else {
            // deliver to is ON, but is it on at the line level?
            // can we CHANGE the Deliver-To?
            $deliverToLine   = $mgr->isShipToLineItemEnable() || $mgr->isVATEnabled();
            if ($deliverToLine == false) {
                $this->hideField('DELIVERTOKEY');
            }

            if ($allowedToChangeDeliverTo == false) {
                $this->setProperty( 'DELIVERTOHEADER', 'readonly', true );  // was 'nonew', but spec changed....
                $this->setProperty( 'DELIVERTOKEY',    'readonly', true );
            }
        }

        $this->showField('EXPORTFORECAST');

        // were we invoked from the Supplies Workbench?
        // Is this a launch from Supplies Workbench?  If so, we have a list of docentry records to replenish items for....
        $docEntryRecords = [];
        if ($isSupplies) {

            // hide the whole filters section
            $this->hideField('FiltersSectionId',         EditorComponentFactory::TYPE_SECTION);
            $this->showField('FiltersSectionIdSupplies', EditorComponentFactory::TYPE_SECTION);

            $suppliesMgr     = Globals::$g->gManagerFactory->getManager('invsupplies');
            $docEntryRecords = $suppliesMgr->sanitizeRecordNumbers(Request::$r->_records ?? '');
        }

        $obj['is_supplies']     = $isSupplies ? 'true' : 'false';
        $obj['docEntryRecords'] = implode(',', $docEntryRecords);

        return $ok;
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $buttons = array();
        $replenishmentRunOp = GetOperationId('inv/lists/replenishmentrun/create');
        $replenishmentRunOpAutorized = CheckAuthorization($replenishmentRunOp);
        if ($replenishmentRunOpAutorized) {
            $this->setButtonDetails($buttons,'idCreatePO', 'btnCreatePO', 'IA.CREATE_PURCHASE_ORDERS', 'createpo', true, 'handleCreatePOAction()', false);
        }
        $this->setButtonDetails($buttons,'idPreviewSnapshot', 'subMenuPreviewSnapshot','IA.CREATE_PREVIEW_SNAPSHOT','previewsnapshot', false, 'handleCreatePreviewSnapshot()', 'false', true);

        // Does this company allow this?
        if (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('SCM_REPLENISHMENT_DIAGNOSTICS')) {
            $this->createMoreActionEntry($buttons, 'diagnoseitemissues', 'diagnoseitemissues', 'IA.DIAGNOSE_ISSUE', 'diagnosefilter', true, null, true, false, array('after' => 1));
        }
        return $buttons;
    }

    /**
     * Add button/menu handlers
     */
    private function addActionHandlers()
    {
        $this->addHandler_ApplyFilter();
        $this->addHandler_CreatePO();
        $this->addHandler_PreviewSnapshot();
        $this->addHandler_DiagnoseFilter();
    }

    /**
     * Add apply filter handler
     */
    private function addHandler_ApplyFilter()
    {
        $this->kActionHandlers['applyfilter'] = array(
            'handler' => 'processApplyFilter',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
    }


    /**
     * Add apply filter handler
     */
    private function addHandler_DiagnoseFilter()
    {
        $this->kActionHandlers['diagnosefilter'] = array(
            'handler' => 'processDiagnoseFilter',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
    }

    /**
     * Add create PO handlers
     */
    private function addHandler_CreatePO()
    {
        $this->kActionHandlers['onlinecreatepo'] = array(
            'handler' => 'processOnlineCreatePO',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
        $this->kActionHandlers['offlinecreatepo'] = array(
            'handler' => 'processOfflineCreatePO',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
    }

    /**
     * Add create preview snapshot handler
     */
    private function addHandler_PreviewSnapshot()
    {
        $this->kActionHandlers['previewsnapshot'] = array(
            'handler' => 'processPreviewSnapshot',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
    }

    /**
     * Handler to process the online PO creation action triggered from JS code handleCreatePOAction
     *
     * @param array $_params    the metadata
     *
     * @return bool             true on success
     */
    protected function processOnlineCreatePO(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        /**
         * @var ReplenishmentManager $mgr
         */
        $mgr = Globals::$g->gManagerFactory->getManager('replenishment');
        $ok = $this->retrieveObjectFromView($_params, $obj);

        if (isset($obj['DIAGNOSTICS'])) {
            Globals::$g->gErr->addIAError('INV-0237', __FILE__ . ':' . __LINE__,
                "Apply Filters must be used before creating POs.", [], "Use Apply Filters and try again.", []);
            $ok = false;
        }

        $replenishmentRun = [];
        $ok = $ok && $mgr->generatePOs($obj, $replenishmentRun);

        //We just created some PO's. We need to reapply the filters to remove the selected rows
        //that we just generated PO's for.
        $ok = $ok && $this->applyFilter($obj);   // ignore prior errors here

        //Set the message to show the replenishment run result
        if ($ok) {
            $replenishmentRun_record = $replenishmentRun['RECORDNO'];
            $sess = Session::getKey();
            $replenishmentRun_viewopid = GetOperationId('inv/lists/replenishmentrun/create');
            $replenishmentRun_viewurl = "editor.phtml?.op=$replenishmentRun_viewopid&.sess=$sess&.popup=1&.r=" . $replenishmentRun_record;
            $replenishmentRun_ref = '<a href=\'javascript:Launch( "' . $replenishmentRun_viewurl . '" , "replenishmentrun");\' target1="_blank">'.GT($this->textMap, 'IA.VIEW_REPLENISHMENT_RUN').'</a>';
            parent::SetMessage($replenishmentRun_ref);
        }

        if ( ! $ok) {
            include 'popuperror.phtml';
            exit();
        }
        return $ok;
    }

    /**
     * Handler to process the offline PO creation action triggered from JS code handleCreatePOAction
     *
     * @param array $_params    the metadata
     *
     * @return bool             true on success
     */
    protected function processOfflineCreatePO(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        /**
         * @var ReplenishmentManager $mgr
         */
        $mgr = Globals::$g->gManagerFactory->getManager('replenishment');
        $ok = $this->retrieveObjectFromView($_params, $obj);
        if (isset($obj['DIAGNOSTICS'])) {
            Globals::$g->gErr->addIAError('INV-0238', __FILE__ . ':' . __LINE__,
                "Apply Filters must be used before creating POs.", [],"Use Apply Filters and try again.", []);
            $ok = false;
        }
        $ok = $ok && $mgr->generatePOsOffline($obj);

        //Set the message to show the replenishment run OFFLINE kicked off
        if ($ok) {
            parent::SetMessage('IA.REPLENISHMENT_RUN_OFFLINE_INITIATED');

            //Remove the included rows from UI to show we just kicked off offline
            $rowsNotIncluded = [];
            foreach ($obj['ITEMS_ORDERING_INFO'] as $aRow) {
                if ($aRow['INCLUDED'] != 'true') {
                    $rowsNotIncluded[] = $aRow;
                }
            }
            $obj['ITEMS_ORDERING_INFO'] = $rowsNotIncluded;
        }
        return $ok;
    }

    /**
     * Handler to process the preview button action triggered from JS code handleApplyFilterAction
     *
     * @param array $_params   the metadata
     *
     * @return bool            true on success
     */
    protected function processApplyFilter(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj['DIAGNOSE'] = false;   // not doing diagnostics
        $ok = $ok && $this->applyFilter($obj);
        return $ok;
    }


    /**
     * Handler to see WHY some set of filters does not produce desired results
     *
     * @param array $_params   the metadata
     *
     * @return bool            true on success
     */
    protected function processDiagnoseFilter(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj['DIAGNOSE'] = true; // ONLY doing diagnostics
        $ok = $ok && $this->applyFilter($obj);
        return $ok;
    }


    /**
     * Does the actual application of the filters
     *
     * @param array &$obj   the UI data structure
     *
     * @return bool          true on success
     */
    private function applyFilter(&$obj)
    {
        unset($obj['DIAGNOSTICS']); // in case it is left over from the last run

        $mgr = Globals::$g->gManagerFactory->getManager('replenishment');
        $ok = $mgr->generateSnapshot($obj, $snapshotData);

        if (($obj['DIAGNOSE'] ?? false) !== false) {
            if ($ok) {
                $obj['DIAGNOSTICS'] = $mgr->getDiagnostics();
            }
            unset($obj['DIAGNOSE']); // so it doesn't haunt us
        }

        // Simulate the work of 'fetchPlatformRels()' in the base class.
        // It was designed for DOCUMENT FORMS, which we aren't one of, so we have to
        // call the underlying routines ourself....
        $ownedObjects =& $mgr->GetOwnedObjects();
        foreach ($ownedObjects as $objRec) {
            if ($objRec['path'] == 'ITEMS_ORDERING_INFO') { // really, the only one we expect
                $fields = $this->getPlatformRels($objRec['path']);
                foreach ($snapshotData as &$row) {
                    $row['RECORDNO'] = $row['ITEMDIMKEY'];  // needed by the following call
                    $this->setPlatformRelsAtrribute($fields, $row);
                }

                // these run after the above, as they are dependent on the above
                $entity = $objRec['entity'];
                foreach ($snapshotData as &$row) {
                    $this->setGLDimRelsAttribute($entity, $fields, $row);
                }
            }
        }

        $ok = $ok && $this->convertSnapshotDataToUI($snapshotData, $obj['ITEMS_ORDERING_INFO']);

        // Trouble?
        if ($ok === false) {
            include 'popuperror.phtml';
            exit();
        }

        return $ok;
    }

    /**
     *    On the UI, we want the future demand to always show in the 'forecast demand' field.
     *    So, we copy the relevent demand field into forecast_demand.
     *
     * @param string[] $aRow
     *
     */
    private function setForecastDemandToAppropriateField(&$aRow)
    {
        $method = ReplenishDetailManager::getInternalSalesForecastMethod($aRow['REPLENISHMENT_METHOD'] ?? '');
        switch ($method) {
            case 'FORECAST_TABLE':
                $aRow['FORECAST_DEMAND_IN_LEAD_TIME'] = $aRow['FORECAST_TABLE'];
                break;

            case 'REORDER_POINT':
                $aRow['FORECAST_DEMAND_IN_LEAD_TIME'] = $aRow['REORDER_POINT'];
                break;

            case 'FORECAST_DEMAND': // already set right
            default:
                break;
        }
    }

    /**
     * Convert the snapshot data to a structure that the UI can display
     *
     * @param array $snapshotData         the snapshot data
     * @param array &$orderingLineItems   the UI data to display
     *
     * @return bool                       true on success
     */
    private function convertSnapshotDataToUI($snapshotData, &$orderingLineItems)
    {
        $ok = false;
        $orderingLineCount = 0;
        $orderingLineItems = [];
        $curWareHouseItemGroup = null;
        $item_viewopid = GetOperationId('inv/lists/item/view');
        $sess = Session::getKey();
        if ($item_viewopid && $sess) {
            $ok = true;
            foreach ($snapshotData as $aRow) {
                $this->setForecastDemandToAppropriateField($aRow);
                //Form the item href to put in the current row
                $item_editorurl = "editor.phtml?.op=$item_viewopid&.sess=$sess&.r=".$aRow['ITEM'].'&.popup=1';
                $item_ref = '<a href=\'javascript:Launch( "'.$item_editorurl.'" , "itemid");\' target1="_blank">'.$aRow['ITEMNAME'].'</a>';
                $aRow['ITEMNAMEHTML'] = $item_ref;

                if (!$curWareHouseItemGroup || $curWareHouseItemGroup != $aRow['WAREHOUSE_ITEM_GROUP']) {
                    $orderingLineItems[] = $aRow;
                    $orderingLineCount++;
                    $curWareHouseItemGroup = $aRow['WAREHOUSE_ITEM_GROUP'];
                } else {
                    //Preserve the row for the non-displaying vendor
                    $orderingLineItems[$orderingLineCount-1][$aRow['VENDORNAME']] = $aRow;
                }
                $orderingLineItems[$orderingLineCount-1]['VENDORS'][] = $aRow['VENDORNAME'];
            }
        }
        return $ok;
    }

    /**
     * Handler to process the create preview snapshot action triggered from JS code handlePreviewSnapshot
     *
     * @param array $_params   the metadata
     *
     * @return bool            true on success
     */
    protected function processPreviewSnapshot(&$_params)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $mgr = Globals::$g->gManagerFactory->getManager('replenishment');
        $ok = $ok && $mgr->saveSnapshot($obj, $obj['ITEMS_ORDERING_INFO']);
        if ($ok) {
            $tokens = [
                [
                    'id' => 'IA.SNAPSHOT_HAS_BEEN_CREATED',
                    'placeHolders' => [
                        ['name' => 'SNAPSHOT_NAME', 'value' => $obj['SNAPSHOT_NAME']]
                    ]
                ]
            ];
            $text = getLocalizedTextWithThrow($tokens);
            $msg = GT($text, 'IA.SNAPSHOT_HAS_BEEN_CREATED');
            parent::SetMessage($msg);
        } else {
            include 'popuperror.phtml';
            exit();
        }

        return $ok;
    }

    /**
     * Handler to export the fluctuating forecast table as CSV.
     *
     * @return bool            true on success
     */
    protected function processExportForecastCSV()
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        $mgr = Globals::$g->gManagerFactory->getManager('replenishforecastdetail');
        $rtn = $mgr->exportTableAsCSV();

        // download
        header("Content-type: application/vnd.ms-excel");
        header("Content-Disposition: attachment; filename=\"FluctuatingForecast.csv\"");
        echo $rtn;

        return true;
    }

    /**
     * Handler to export the fluctuating forecast table as CSV.
     *
     * @param mixed $itemid
     * @return bool            true on success
     */
    protected function processExportForecastItemCSV($itemid)
    {
        //To identify we are in edit state
        $this->state = $this->kShowEditState;

        $mgr = Globals::$g->gManagerFactory->getManager('replenishforecastdetail');
        $rtn = $mgr->exportItemAsCSV($itemid);

        // download
        header("Content-type: application/vnd.ms-excel");
        header("Content-Disposition: attachment; filename=\"FluctuatingForecast.csv\"");
        echo $rtn;

        return true;
    }


    /**
     * This is a hook functions for subclases to add the dynamic metadata into the current layout.
     * At the time this function is called, the data, state and view objects are not available.
     * The subclass must operate on the given params structure.
     *
     * @param array $params
     */
    protected function buildDynamicMetadata(&$params)
    {
        // add the change event to auto-populate the project information at the line level
        $matches = [];
        FormEditor::findElements($params, array('path' => 'PROJECTID'), EditorComponentFactory::TYPE_FIELD, $matches);
        if ( isset($matches[0]) ) {
            $onchange = "onChangeProjectID(this);";
            $matches[0]['events']['change'] .= $onchange;
        }
        // add the change event to auto-populate the task information at the line level
        $matches = [];
        FormEditor::findElements($params, array('path' => 'TASKID'), EditorComponentFactory::TYPE_FIELD, $matches);
        if ( isset($matches[0]) ) {
            $onchange = "onChangeTaskID(this);";
            $matches[0]['events']['change'] .= $onchange;
        }
        parent::buildDynamicMetadata($_params);
    }


    /**
     * This is an override of the parent's function, in order to override bad behavior after an error is thrown.
     *
     * @return array
     */
    protected function getDimensionIDsInOrder()
    {
        // after an error, for some reason, the _mod gets reset to 'inv',
        // and we're pretending to be a PO module so we can get the magic that comes with that.
        $mod = 'po'; // Request::$r->_mod;
        $dimOrder = IADimensions::getDimensionIDsInGLOrder($mod, !util_isPlatformDisabled());
        return $dimOrder;
    }


    /**
     * This is an override of the parent's function, in order to override bad behavior after an error is thrown.
     *
     * @return array
     */
    protected function getGlobalHiddenFields()
    {
        // after an error, for some reason, the _mod gets reset to 'inv',
        // and we're pretending to be a PO module so we can get the magic that comes with that.
        $rtn = parent::getGlobalHiddenFields();
        $rtn[Globals::$g->kMod] = 'po'; // Request::$r->_mod;
        return $rtn;
    }


    /**
     *   This is an override of the parent method and gets called from an ajax call in replenishment.js
     *
     * @param array         $_params
     * @param bool          $offline
     * @param string|false  $out
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        $obj = $this->getViewData();
        if (isset($obj['DOWNLOAD'])) {
            $this->processExportForecastCSV();
        } else {
            parent::Editor_Deliver($_params, $offline, $out);
        }

        return true;
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.EXPORT_FLUCTUATING_FORECAST_TO_CSV';
        $this->textTokens[] = 'IA.MORE_FILTERS_DOT';
        $this->textTokens[] = 'IA.FEWER_FILTERS';
        $this->textTokens[] = 'IA.PLEASE_SELECT_ROW_TO_CREATE_PO';
        $this->textTokens[] = 'IA.PREVIEW_SNAPSHOT_NAME_IS_REQUIRED';
        $this->textTokens[] = 'IA.ROWS_SELECTED';
        return parent::getFormTokens();
    }

}


