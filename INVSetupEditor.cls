<?php

/**
 * INVSetupEditor.cls
 *
 * @author    Alexandre Sonier <asonier@intacct.com>
 * @copyright 2000 Intacct Corporation, All Rights Reserved
 */



/**
 * Class INVSetupEditor
 */
class INVSetupEditor extends DocumentSetupEditor
{
        // For Advanced Inventory, show the checkbox only if the underlying code is ready.
    const AI_CYCLE_COUNTS_READY     = true;
    const MAX_GRAPH_TABLE_SIZE      = 200;  // the fulfillment graph of TDs maximum size


    /**
     * @param array $_params parameters
     */
    public function __construct($_params = array())
    {
        $this->mod = 'inv';
        $this->additionalTokens[] = 'IA.BIN';
        $this->additionalTokens[] = 'IA.CLASSIC_BIN';
        $this->additionalTokens[] = 'IA.CONVERT_ITEMS';
        $this->additionalTokens[] = 'IA.UPLOAD';
        $this->additionalTokens[] = 'IA.TEMPLATE';
        $this->additionalTokens[] = 'IA.ACTUAL_COSTS_ONLY';
        $this->additionalTokens[] = 'IA.ESTIMATES_AND_ACTUAL_COSTS';
        $this->additionalTokens[] = 'IA.SL_SETUP_DIMENSIONS_NOTE';
        $this->additionalTokens[] = 'IA.EXPORT_WORKFLOW';

        parent::__construct($_params);
    }

    /**
     * Override parent's method
     *
     * @param array &$params parameters
     */
    protected function buildDynamicMetadata(&$params)
    {
        parent::buildDynamicMetadata($params);

        // Manage grid document columns hidden state
        $paths = array(
            array('path' => 'REVRECJOURNAL'),
            array('path' => 'DEFREVACCT'),
            //array('path' => 'PRINVBATCH'),
            array('path' => 'PRINVJOURNAL'),
        );
        foreach ($paths as $path) {
            self::findAndSetMetadata($params, $path, array('hidden' => true));
        }


        // In Inventory, we can't change workflow in a simplified company
        if (!$this->isAdvancedConfiguration) {
            self::findAndSetMetadata(
                $params,
                array('id' => 'workflow_section'),
                array('hidden' => true),
                EditorComponentFactory::TYPE_SECTION
            );

        }
    }

    /**
     * Override parent's method
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        parent::mediateDataAndMetadata($obj);
        $view = $this->getView();
        $ctx = GetContextLocation();

        $obj['ADVANCED_INVENTORY'] = 'true';
        $obj['FLUCTUATING_FORECAST'] =  'true' ;

        if (!$this->isAdvancedConfiguration) {
            // Simplified company

            // Hide advanced items settings
            $elements = array(
                'ENABLESERIAL',
                'ENABLELOT',
                'ENABLEBIN',
                'ENABLE_EXPIRATION',

                'AI_SECTION',                  // I'm guessing advanced inventory would be out of the question.... :-)
            );
            foreach ( $elements as $value) {
                $view->findAndSetProperty(array('path' => $value), array('hidden' => true));
            }
            // For simple companies make the offset account as required.
            $view->findAndSetProperty(array('path' => 'OFF_GLACCOUNT'), array('required' => true));
        } else {
            // Advanced company

            // Hide GL accounts and 'KIT' and 'LIGHTASSEMBLY' from 'General' section
            $elements = array(
                'SCRAP_GLACCOUNT',
                'DAM_GLACCOUNT',
                'INV_GLACCOUNT',
                'OFF_GLACCOUNT',
            );
            foreach ( $elements as $value) {
                $view->findAndSetProperty(array('path' => $value), array('hidden' => true));
            }
        }

        // Disable preferences for entity level setup
        if (IsMultiEntityCompany() && $ctx) {
            // Set these options to readonly at entity level, they can be set only from root level
            $elements = array(
                // Configuration
                'ENABLE_ADVANCED',
                'MCPENTRY',
                'USERCONTACT',
                'STATUS',
                // Setup
                'KIT',
                'ENABLESERIAL',
                'ENABLELOT',
                'ENABLEBIN',
                'ENABLE_EXPIRATION',
                'DISALLOW_NEGINV',
                'DISALLOW_QTY_CHANGE_WHENCONVERT',
                'ITEMPRECISION',
                'ENABLEWAREHOUSETRANSFER',
                'ENABLEINTRANSITTRANSFER',
                'DEFAULTINTRANSITTRANSFER',
                'INCLUDEINTRANSIT',
                'INCLUDEONORDER',
                'WAREHOUSESEQUENCE',
                'EXCH_RATE_TYPE_ID',
                'AI_REPLENISHMENTS',
                'DF_GLACCOUNT',
                'FORECAST_METHOD',
                'DEFAULT_PURCHASE_TRANSACTION',
                'AI_CYCLE_COUNTS',
                'ENABLELANDEDCOST',
                'LANDEDCOSTACCOUNT',
                'LANDEDCOSTACCOUNTESTIMATE',
                'LANDEDCOSTRADIO',
                'CLOSEDPERIODJOURNAL',
                'REPLENISH_OPT_IN',
                'COSTING_ON_A_SCHEDULE',
                'ENABLESHIPPINGDATES',
                'ENABLEAUTOPRINTLABEL',
                'ENABLECYCLECOUNT',
                'CYCLECOUNTSEQUENCE',
                'ENABLEFULFILLMENT',
                'PICK',
                'PACK',
                'SHIP',
                'INVOICE',
                'FULFILLMENTDOCPAR',
                'NEGATIVEFULFILLMENT',
            );
            foreach ( $elements as $value) {
                $view->findAndSetProperty(array('path' => $value), array('readonly' => true));
            }
        }

        $landedCostGrid = array();
        $view->findComponents(array('path' => 'LANDEDCOSTGRID'), EditorComponentFactory::TYPE_GRID, $landedCostGrid);
        $landedCostGrid = $landedCostGrid[0];

        if ($obj['ENABLELANDEDCOST'] != 'true') {
            $landedCostGrid->setProperty('hidden', true);
            $view->findAndSetProperty(array('path' => 'LANDEDCOSTACCOUNT'), array('disabled' => true));
        } else {
            $landedCostGrid->setProperty('hidden', false);
            $view->findAndSetProperty(array('path' => 'LANDEDCOSTACCOUNT'), array('disabled' => false));

            if (!IsMultiEntityCompany()) {
                $landedCostLoc = array();
                $landedCostGrid->findComponents(
                    array('path' => 'LANDEDCOSTLOC'), EditorComponentFactory::TYPE_FIELD, $landedCostLoc
                );
                // PHP 8.1 issue IA-77548
                if($landedCostLoc[0] != null) {
                    $landedCostLoc[0]->setProperty('hidden', true);
                }
            } else {
                // Get all the fields from the Grid
                $allLineFields = array();
                $landedCostGrid->findComponents(null, EditorComponentFactory::TYPE_FIELD, $allLineFields);
                $this->setFieldsReadOnly($allLineFields);

                if (GetContextLocation()) {
                    $matches = array();
                    $landedCostGrid->findComponents(
                        array('path' => 'LANDEDCOSTDOCPAR'), EditorComponentFactory::TYPE_FIELD, $matches
                    );

                    if ($matches && $matches[0]) {
                        $type = $matches[0]->getProperty('type');
                        $type['restrict'] = array(
                            array(
                                'pickField' => 'MEGAENTITYKEY',
                                'nonulls' => true,
                            )
                        );
                        $matches[0]->setProperty('type', $type);
                    }
                }
            }
        }
        if (QXCommon::isQuixote()) {
            $view->findAndSetProperty(array('path' => 'LANDEDCOSTRADIO'), array('noLabel' => true));
        }

        //Only preserve the radio button on the first load when we have yet to preserve
        if (!$obj['LANDEDCOSTRADIOPREV']) {
            $obj['LANDEDCOSTRADIOPREV'] = $obj['LANDEDCOSTRADIO'];
        }

        /*
         * INV subscription is specific
         * When subscribing, STD_INV workflow is set, so as some DB entries
         * However, since the state will be 'show_new', it won't go through the 'Get' method of the manager assuming
         * there are no values to get because it's a brand new subscription
         * Consequently, since we need those values to be taken into account, we load the current preferences into obj
         */
        if ($this->state == Editor_ShowNewState) {
            $prefs = $this->getEntityMgr()->get(0);
            $obj = array_merge($obj, $prefs);
            // Specific logic to init document grid
            foreach ($obj['DOCUMENTS_GRID'] as &$line) {
                if (array_key_exists($line['DOCPATH'], $obj['DOCTYPES'])) {
                    $line['STATUS'] = $obj['DOCTYPES'][$line['DOCPATH']];
                }
            }

            //If customer is subscribing for INV module then make MIV(Maintain Inventory Valuation) tool enabled by default.
            $obj['COSTING_ON_A_SCHEDULE'] = 'true';
        }

        if ($obj['ENABLEWAREHOUSETRANSFER'] == 'true') {
            $view->findAndSetProperty(
                array('path' => 'WAREHOUSESEQUENCE'), array('disabled' => 'false', 'required' => 'true')
            );
            $view->findAndSetProperty(
                array('path' => 'ENABLEINTRANSITTRANSFER'), array('disabled' => 'false', 'hidden' => false)
            );
            $view->findAndSetProperty(
                array('path' => 'INCLUDEINTRANSIT'), array('disabled' => 'false', 'hidden' => false)
            );
            $subSection = array();
            $view->findComponents(array('id' => 'DEFAULTINTRANSITTRANSFER_SECTION'),
                                  EditorComponentFactory::TYPE_SUBSECTION,$subSection);

            if(isset($subSection) && isset($subSection[0])){
                if ($obj['ENABLEINTRANSITTRANSFER'] == 'true') {
                    $subSection[0]->setProperty('disabled', false);
                    $subSection[0]->setProperty('hidden', false);
                }else{
                    $subSection[0]->setProperty('hidden', true);
                }
            }
        }else{
            $view->findAndSetProperty(array('path' => 'WAREHOUSESEQUENCE'), array('hidden' => true));
            $view->findAndSetProperty(array('path' => 'ENABLEINTRANSITTRANSFER'), array('hidden' => true));
            $view->findAndSetProperty(array('path' => 'DEFAULTINTRANSITTRANSFER'), array('hidden' => true));
            $view->findAndSetProperty(array('path' => 'INCLUDEINTRANSIT'), array('hidden' => true));
        }

        if (self::AI_CYCLE_COUNTS_READY == false) {
            $view->findAndSetProperty(array('path' => 'AI_CYCLE_COUNTS'), array('hidden' => true));
        }

        if (IsMCMESubscribed()) {
            $view->findAndSetProperty(
                array('path' => 'EXCH_RATE_TYPE_ID'), array('hidden' => false));
        }

        if ($obj['DEFAULT_COST_METHOD'] != 'Average' && $obj['ENABLE_MULTI_COST'] != 'true') {
            $view->findAndSetProperty(
                array('path' => 'AVGCOSTSEQUENCE'), array('hidden' => 'true')
            );
        }

        // If the advanced bin tracking flag has never been set set it now:
        if ( ! isset($obj['ADVANCEDBINTRACKING'])) {
            $obj['ADVANCEDBINTRACKING'] = (BinManager::areAdvanedBinsOn() ? "true" : "false");
        }

        // This may be temporary, but: what kind of bins do we have?
        $binLabel = ( $obj['ADVANCEDBINTRACKING'] == 'true' )
            ? GT($this->textMap, 'IA.BIN') : GT($this->textMap, 'IA.CLASSIC_BIN');
        $view->findAndSetProperty(array('path' => 'ENABLEBIN'), array('fullname' => $binLabel));

        //Check for the feature flag enabled fo the Particular company then only enable this configuration.
        $this->checkForCycleCountEnable($obj);

        //Check for the feature flag enabled fo the Particular company then only enable this configuration.
        $this->checkForFulfillmentEnable();

        $obj['OLDINVSTARTDATE'] = $obj['INVSTARTDATE'] ?? '';

        //So we can disable/enable the fulfillment checkboxes on client side UI
        $iwqManager  = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");
        $obj['FULFILLMENTCOUNTS'] = $iwqManager->countsPerQueue();

        $obj['FULFILLMENTGRID']   = [];
        if (InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_FF)) {
            $lines = $this->getFulfillmentDocumentGraph();
            foreach ($lines as $oneLine) {
                $obj['FULFILLMENTGRID'][] = ['FLOW' => $oneLine];
            }
        }

        $suppliesPossible = FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_SUPPLIESINV_FEATURE');
        $view->findAndSetProperty(array('path' => 'ENABLESUPPLIESINVENTORY'), array('hidden' => ( ! $suppliesPossible)));
        $view->findAndSetProperty(array('path' => 'SUPPLIESINVENTORYPO'), array('hidden' => ( ! $suppliesPossible)));
        $view->findAndSetProperty(array('path' => 'SUPPLIESINVENTORYDS'), array('hidden' => ( ! $suppliesPossible)));
        if ($obj['ENABLESUPPLIESINVENTORY'] === 'true') {
            $view->findAndSetProperty(array('path' => 'COSTING_ON_A_SCHEDULE'), array('readonly' => true));
            $view->findAndSetProperty(array('path' => 'DISALLOW_NEGINV'), array('readonly' => true));
        }

        return true;
    }


    /**
     *      Get the graph of fulfillment documents and their paths.  The 'grid' is one-text-line-per-row.
     *
     *
     * @return string|array
     */
    private function getFulfillmentDocumentGraph()
    {
        // get ALL the fulfillment TDs
        $qry   = [];
        $qry[] = "SELECT docid
                    FROM docpar
                    WHERE cny# = :1
                      and latestversionkey is null
                      and sale_pur_trans = 'S'
                      and status = 'T'
                      and enablefulfillment = 'T'
                      ORDER BY docid";
        $qry[] = GetMyCompany();
        $rows  = QueryResult($qry);
        if ($rows === false) {
            return [];
        }

        $docparids = [];
        foreach ($rows as $row) {
            $docparids[$row['DOCID']] = true;
        }

        // Get the conversion graph
        $conversionManager = new ConversionManager(['mod' => 'so']);
        $graph = $conversionManager->bulkConvertTo(array_keys($docparids), true); // true is fulfillment only

        $rtn = [];

        // first, find docs that have no source or target TDs
        foreach ($docparids as $docparid => $ignore) {
            if ( ! isset($graph[$docparid])) {
                $rtn[] = $docparid . ' ----> ??';   // let the customer know there is nowhere to go
            }
        }

        // Now walk the graph, starting with TD's that have no previous TD's
        // the sort above puts us in alpha order
        // NOTE! WATCH OUT FOR LOOPS!  A-->B-->A or A-->A
        foreach ($graph as $docparid => $oneDocPar) {
            $sources = $oneDocPar['SOURCES'] ?? [];
            $doctype = $oneDocPar['DOCTYPE'] ?? '';
            if (empty($sources) || ($doctype === InvBizLogicForWD::TD_TYPE_SALESORDER)) {
                $line = $docparid;
                $loopDetection = [$docparid];
                $this->followTargets($line, $docparid, $graph, $loopDetection, $rtn);
                if (count($rtn) > self::MAX_GRAPH_TABLE_SIZE) {
                    return $rtn;
                }
            }
        }
        return $rtn;
    }


    /**
     *  This recursive routine follows ONE target path to completion, resulting in a row of text
     *  that can go on the fulfillment paths grid.
     *
     * @param string    $line           The string for this path so far
     * @param string    $docparid       The docpar id
     * @param array     $graph          The whole graph of possibilities
     * @param array     &$loopDetection Are we in a loop?
     * @param string[]  &$table         The resulting table
     *
     */
    private function followTargets($line, $docparid, $graph, &$loopDetection, & $table)
    {
        $targets = $graph[$docparid]['TARGETS'] ?? [];
        if (empty($targets)) {
            $table[] = $line;
        } else {
            $bulk = $graph[$docparid]['BULK'] ?? '';
            foreach ($targets as $target) {
                $targetDocId = $target['DOCID'];
                $loop        = in_array( $targetDocId, $loopDetection );
                // use squiggles as a simple way of temporarily denoting the start and end of the doc id,
                // so that we can below search for it in the string to detect loops
                // we'll remove these squiggles before saving the line in the table.
                $line2 = $line . (($targetDocId === $bulk) ? _(" --(bulk)--> ") : ' ----> ') . $targetDocId;
                // not already seen, right?  You can make loops in TDs; let the loop show ONCE
                if ($loop) { // is this the beginning of the loop?
                    // yes, then it is the end of the line, as if there were no more targets
                    $table[] = $line2;
                } else {
                    if (count($table) > self::MAX_GRAPH_TABLE_SIZE) {
                        return;
                    }
                    $loopDetection[] = $targetDocId; // loop detection
                    $this->followTargets($line2, $targetDocId, $graph, $loopDetection, $table);    // Curses!  He recurses!
                }
            }
        }
    }




    /**
     * Put fields readonly according to the current state of the screen
     *
     * @param array &$fields reference on the view structure
     */
    protected function setFieldsReadOnly(&$fields)
    {
        foreach ( $fields as &$field ) {

            if ($field->getProperty('readonly') || $field->getProperty('disabled')) {
                continue;
            }

            $currentClazz = $field->getProperty('clazz', false);

            if (!$currentClazz || $currentClazz == 'Field') {
                $field->setProperty('clazz', "DropShipLineField");
            }
        }
    }

    /**
     * Override parent's method
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    protected function prepareObjectForSave(&$obj)
    {
        unset($obj['DISPLAYPAYMENTS']);

        if (!IsAdvancedConfiguration()) {
            unset($obj['DOCTYPES']);
        }

        if(!IsInstalled(Globals::$g->kSOid)){
            $obj['ENABLEFULFILLMENT'] = "false";
        }
        if ($obj['ENABLEFULFILLMENT'] == "false"){
            $obj['PICK'] = "false";
            $obj['PACK'] = "false";
            $obj['SHIP'] = "false";
            $obj['INVOICE'] = "false";
            $obj['NEGATIVEFULFILLMENT'] = "false";
        }

        if ($obj['OLDINVSTARTDATE'] != ($obj['INVSTARTDATE'] ?? '')) {
            $obj['INVSTARTDATECHANGEDON'] = GetCurrentDate(IADATE_SYSFORMAT);
        }

        return parent::prepareObjectForSave($obj);
    }

    /**
     * Override parent's method
     *
     * @param string    $entity  entity name
     * @param string    $objId   id object
     * @param string    $doctype document type
     * @param string[]  $fields
     *
     * @return array
     */
    protected function getEntityData($entity, $objId, $doctype = '', $fields=null)
    {
        $entityData = parent::getEntityData($entity, $objId);

        $glacctmgr = Globals::$g->gManagerFactory->getManager('glaccount');
        if (isset($entityData['OFF_GLACCOUNT']) && $entityData['OFF_GLACCOUNT'] != '') {
            list($glacct_no) = explode('--', $entityData['OFF_GLACCOUNT']);
            $glaccount = $glacctmgr->GetRaw($glacct_no);
            $entityData['OFF_GLACCOUNT'] = $glaccount[0]['ACCT_NO']."--".$glaccount[0]['TITLE'];
        }

        if (isset($entityData['DIRECT_GLACCOUNT']) && $entityData['DIRECT_GLACCOUNT'] != '') {
            list($glacct_no) = explode('--', $entityData['DIRECT_GLACCOUNT']);
            $glaccount = $glacctmgr->GetRaw($glacct_no);
            $entityData['DIRECT_GLACCOUNT'] = $glaccount[0]['ACCT_NO']."--".$glaccount[0]['TITLE'];
        }

        return $entityData;
    }

    /**
     * checkForCycleCountEnable to check whether Cycle count enabled or not
     *
     * @param array $obj reference on the view structure
     */
    protected function checkForCycleCountEnable(&$obj)
    {
        $view = $this->getView();
        // If Bin tracking is enabled, we support cycle counting only for the Advance bin tracking, so we should verify
        // and enable the configuration.
        if (isset($obj['ENABLEBIN']) && $obj['ENABLEBIN'] == 'true' && $obj['ADVANCEDBINTRACKING'] != 'true') {
            $view->findAndSetProperty(array('path' => 'ENABLECYCLECOUNT'), array('hidden' => true));
            $view->findAndSetProperty(array('path' => 'CYCLECOUNTSEQUENCE'), array('hidden' => true));
        } else if ($obj['ENABLECYCLECOUNT'] == 'true') {
            $view->findAndSetProperty(
                array('path' => 'CYCLECOUNTSEQUENCE'), array('disabled' => 'false', 'required' => 'true')
            );
        }
    }

    /**
     * checkForFulfillmentEnable to check whether Cycle count enabled or not
     *
     */
    protected function checkForFulfillmentEnable()
    {
        $view = $this->getView();

        //Only check for FF feature flag and classic bins as we are hidding all the UI controls in inventory config
        if ( ! (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_FULFILLMENT_FEATURE') &&
                (BinManager::areClassicBinsOn() === false))) {

            // turn off the entire section
            $subSection = array();
            $view->findComponents(array('id' => 'FULFILLMENT_SECTION'),
                EditorComponentFactory::TYPE_SUBSECTION,$subSection);
            $subSection[0]->setProperty('hidden', true);
        }
    }

    /**
     * @return string[] Tokens required by this form's js
     */
    protected function getFormTokens() : array
    {
        $this->textTokens = array_merge($this->textTokens, [
            'IA.ALERT_NONE_SELECTED',
            'IA.ALERT_SELECT_NEW_WORKFLOW',
            'IA.CONFIRM_ENABLE_ADVANCED_MODE',
            'IA.CONFIRM_DIFFERENT_WORKFLOW',
            'IA.CONFIRM_ADVANCED_REVENUE_MANAGEMENT',
            'IA.CONFIRM_ENABLE_STOCKABLE_KITS',
            'IA.CONFIRM_ENABLE_LANDED_COST',
            'IA.CONFIRM_ENABLE_MULTI_COST',
            'IA.CONFIRM_ENABLE_SERIAL',
            'IA.CONFIRM_ENABLE_LOT',
            'IA.CONFIRM_ENABLE_EXPIRATION',
            'IA.CONFIRM_ENABLE_BIN',
            'IA.ALERT_ENABLE_OE_SUBSCRIPTION_BEFORE_FULFILLMENT',
            'IA.CANT_TURN_OFF_SUPPLIES_BECAUSE_OF_ITEMS',
            'IA.NOTE_ABOUT_TURNING_ON_SUPPLIES',
            'IA.ENABLING_SUPPLIES_INV_CHANGES_SETTINGS',
            'IA.SUPPLIES_MUST_HAVE_PURCHASING',
            'IA.SUPPLIES_MUST_HAVE_DELIVERTO',
        ]);
        return parent::getFormTokens();
    }


    /**
     * Define vars to be used into javascript files
     * Override parent's method
     *
     * @return array
     */
    protected function getEditorGlobals()
    {
        $toReturn = parent::getEditorGlobals();

        // SUPPLIES stuff:
        $enabled = ItemManager::isSuppliesInventoryEnabled();
        $toReturn['SUPPLIES_ARE_ENABLED'] = $enabled ? 'true' : 'false';
        $toReturn['SUPPLIES_ITEMS_EXIST'] = 'false';
        if ($enabled) {
            $qry    = "SELECT 1 as count FROM DUAL WHERE EXISTS(SELECT record# FROM icitemmst WHERE cny# = :1 and issupplyitem = 'T') ";
            $result = QueryResult([$qry, GetMyCompany()]);
            if (isset($result[0]['COUNT']) && ($result[0]['COUNT'] > 0)) {
                $toReturn['SUPPLIES_ITEMS_EXIST'] = 'true';
            }
        }

        $purchasesExist = IsInstalled(Globals::$g->kPOid);
        $toReturn['POMODULEEXISTS'] = $purchasesExist ? 'true' : 'false';
        $toReturn['DELIVERTOSETUP'] = 'false';
        if ($purchasesExist) {
            GetModulePreferences(Globals::$g->kPOid, $preferences);
            $deliverTo = ($preferences['DELIVERTO_FOR_HEADER']   === 'T') &&
                         ($preferences['DELIVERTO_FOR_LINEITEM'] === 'T');
            $toReturn['DELIVERTOSETUP'] = $deliverTo ? 'true' : 'false';
        }

        $toReturn['HASNEGATIVEINVOVERRIDDENWAREHOUSE'] = (WarehouseManager::negativeInvOverriddenWarehouseCount() > 0)? 'true' : 'false';

        return $toReturn;
    }


}
