<?php

/**
 * An editor class for the Inventory WQOrder class (Fulfillment by order)
 *
 * @author    Roger
 * @copyright 2021 Intacct Corporation All, Rights Reserved
 */

/**
 * An editor class for the Inventory WQOrder class (Fulfillment by order)
 */
class InventoryWQOrderEditor extends FormEditor
{

    /**
     * InventoryWQOrder specific tokens
     * @var array
     */
    private $inventoryWQOrderTokens = [ 'IA.DONE'];

    /**
     * @param array $_params the parameters of the class
     */
    public function __construct($_params)
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->inventoryWQOrderTokens);
        parent::__construct($_params);
    }

    /**
     * @return bool
     */
    protected function CanPost()
    {
        return false;
    }

    /**
     * @return bool
     */
    protected function CanEdit()
    {
        return false;
    }

    /**
     * @return bool
     */
    protected function CanSubmit()
    {
        return true;
    }

    /**
     * @return bool
     */
    function CanSave()
    {
        return false;       // ?????
    }

    /**
     * @return bool
     */
    function CanSaveAndNew()
    {
        return false;
    }

    /**
     * @return bool
     */
    function CanDuplicate()
    {
        return false;
    }


    /**
     *      Leave the standard buttons, but add a special 'can we save?' action when hitting SAVE.
     *
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $values = parent::getStandardButtons($state);

        // turn 'cancel' into 'done'
        foreach ($values as $index => $row) {
            if ($row['id'] == Editor_CancelBtnID) {
                $values[$index] = $this->createAction(Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);
            }
        }

        return $values;
    }


    /**
     * @param string $field the field name
     * @param string $property property to set, like 'hidden'
     * @param string $to what to set it to
     * @param string $type the type of field
     */
    private function setProperty($field, $property, $to, $type = EditorComponentFactory::TYPE_FIELD)
    {
        $idOrPath = ($type == EditorComponentFactory::TYPE_TAB) ? 'id' : 'path';
        $view = $this->getView();
        $fields = array();
        $view->findComponents(array($idOrPath => $field), $type, $fields);
        foreach ($fields as $oneField) {
            $oneField->setProperty($property, $to);
        }
    }


    /**
     * @param string $field the field name
     * @param string $type the type of field
     */
    private function hideField($field, $type = EditorComponentFactory::TYPE_FIELD)
    {
        $this->setProperty($field, 'hidden', true, $type);
    }


    /**
     *  The 'ACTION' dropdown can be gelded via checkboxes in Inventory Config.  Do so here....
     *
     */
    private function alterActionDropdowns()
    {
        global $kINVid;
        GetModulePreferences($kINVid, $prefs);
        $pick = ($prefs['PICK'] == 'T');
        $pack = ($prefs['PACK'] == 'T');
        $ship = ($prefs['SHIP'] == 'T');;
        $invoice = ($prefs['INVOICE'] == 'T');

        // while we're here, hide tabs that shouldn't show
        // these are to be removed
        $remove = [];
        if ($pick == false) {
            $remove[] = 'RPI';
            $remove[] = 'PI';
            $this->hideField("pickOrders", EditorComponentFactory::TYPE_TAB);
            $this->hideField("SUMMARY.READYTOPICK");
            $this->hideField("SUMMARY.PICKED");
        }
        if ($pack == false) {
            $remove[] = 'RPA';
            $remove[] = 'PA';
            $this->hideField("packOrders", EditorComponentFactory::TYPE_TAB);
            $this->hideField("SUMMARY.READYTOPACK");
            $this->hideField("SUMMARY.PACKED");
        }
        if ($ship == false) {
            $remove[] = 'RS';
            $remove[] = 'S';
            $this->hideField("shipOrders", EditorComponentFactory::TYPE_TAB);
            $this->hideField("SUMMARY.READYTOSHIP");
            $this->hideField("SUMMARY.SHIPPED");
        }
        if ($invoice == false) {
            $remove[] = 'RI';
            $remove[] = 'I';
            $this->hideField("invoiceOrders", EditorComponentFactory::TYPE_TAB);
            $this->hideField("SUMMARY.READYTOINVOICE");
            $this->hideField("SUMMARY.INVOICED");
        }

        // Now, for each ACTION field (there are six or so), remove the corresponding fields
        $view = $this->getView();
        $fields = array();
        $view->findComponents(array('path' => 'ACTION'), EditorComponentFactory::TYPE_FIELD, $fields);
        foreach ($fields as $i => $oneField) {
            // params.validValues, params.type.validValues, params.type.validLabels, params.type._validValues <-- short names
            $params = $oneField->params;
            foreach ($remove as $removeThisIndex) {
                $foundKey = array_search($removeThisIndex, $params['type']['_validivalues']);
                unset($params['type']['_validivalues'][$foundKey]);
                unset($params['type']['validvalues'][$foundKey]);
                unset($params['type']['validlabels'][$foundKey]);
                unset($params['validvalues'][$foundKey]);
            }
            $fields[$i]->params['type']['_validivalues'] = array_values($params['type']['_validiValues']); // reindex the array
            $fields[$i]->params['type']['validvalues'] = array_values($params['type']['validvalues']);
            $fields[$i]->params['type']['validlabels'] = array_values($params['type']['validlabels']);
            $fields[$i]->params['validvalues'] = array_values($params['validvalues']);
        }
    }


    /**
     *      Manage UI presentation for view/edit
     *
     * @param array $obj
     *
     * @return bool  true on success and false on failure
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        if ($this->state == 'shownew') {

            // we don't have rows yet, so save LINEACTIONS for the whole object
            $this->alterActionDropdowns();

            // These are filled in by the JavaScript code, based on what is
            // fetched by the filter framework
            $obj['SUMMARY'] = array(
                'ALLORDERS' => "0",
                'READYTOPICK' => "0",
                'PICKED' => "0",
                'READYTOPACK' => "0",
                'PACKED' => "0",
                'READYTOSHIP' => "0",
                'SHIPPED' => "0",
                'READYTOINVOICE' => "0"
            );

        }

        // If they don't enable the new date fields, don't show them....
        $ptionalDateFields = [
            'SHIPBYDATE', 'SHIPPEDDATE', 'NEEDBYDATE', 'DONOTSHIPBEFOREDATE',
            'DONOTSHIPAFTERDATE', 'CANCELAFTERDATE'
        ];

        if (InventoryWQOrderManager::areShipDatesEnabled()) {
            $obj['ADDFIELDS'] = $ptionalDateFields;
        } else {
            $obj['ADDFIELDS'] = [];
            foreach ($ptionalDateFields as $field) {
                $this->hideField($field);
            }
        }

        // setup the href link for clicking on DOCID
        $docviewop = GetOperationId("so/lists/sodocument/view");
        $this->setProperty('DOCID', 'onclick', "LaunchObjLink(this, $docviewop, 'so');");

        // setup the href link for clicking on CUSTOMERID
        $custviewop = GetOperationId("so/lists/customer/view");
        $this->setProperty('CUSTOMERID', 'onclick', "LaunchObjLink(this, $custviewop, 'so');");

        // setup the href link for clicking on CUSTOMERID
        $invviewop = GetOperationId("inv/lists/item/view");
        $this->setProperty('ITEMID', 'onclick', "LaunchObjLink(this, $invviewop, 'inv');");

        //Hide/show the pick,pack,ship, and invoice grids layout base on the config
        global $kINVid;
        GetModulePreferences($kINVid, $prefs);
        $view = $this->getView();
        $gridPaths = ['PICK', 'PACK', 'SHIP', 'INVOICE'];
        foreach ($gridPaths as $gridPath) {
            $grids = array();
            $view->findComponents([ 'path' => $gridPath ], EditorComponentFactory::TYPE_GRID, $grids);
            if ($grids) {
                $grids[0]->setProperty('allowEditPage', $prefs[$gridPath] == 'T' ? 'true' : 'false');
            }
        }

        return true;
    }


    /**
     * Register global javascript variables
     *
     * @return array the editor globals
     */
    protected function getEditorGlobals()
    {
        $vars = parent::getEditorGlobals();

        // this copies from the .ent file for ACTION.  Not sure how to keep them in synch.
        $_validivalues = array('O', 'RPI', 'PI', 'RPA', 'PA', 'RS', 'S', 'RI', 'I');
        $validValues = array ('IA.OPEN', 'IA.READY_TO_PICK', 'IA.PICKED', 'IA.READY_TO_PACK', 'IA.PACKED', 'IA.READY_TO_SHIP', 'IA.SHIPPED', 'IA.READY_TO_INVOICE', 'IA.INVOICED');

        global $kINVid;
        GetModulePreferences($kINVid, $prefs);
        $pick       = ($prefs['PICK'] == 'T');
        $pack       = ($prefs['PACK'] == 'T');
        $ship       = ($prefs['SHIP'] == 'T');
        $invoice    = ($prefs['INVOICE'] == 'T');

        // for the ACTIONS column, we generate the list from the above trimming.....
        $actionItems = [];
        foreach ($validValues as $i => $value) {
            $action = $_validivalues[$i];
            if (!$pick && (($action == 'RPI') || ($action == 'PI') || ($action == 'PIPRINT'))) {
                continue;
            }
            if (!$pack && (($action == 'RPA') || ($action == 'PA') || ($action == 'PAPRINT'))) {
                continue;
            }
            if (!$ship && (($action == 'RS') || ($action == 'S') || ($action == 'SPRINT'))) {
                continue;
            }
            if (!$invoice && (($action == 'RI') || ($action == 'I') || ($action == 'IPRINT'))) {
                continue;
            }
            $actionItems[] = [
                "label" => $value,
                "type" => "callback",
                "props" => ["func" => "rowAction", "customProps" => ['action' => $action]],
            ];
        }

        $lineActionMenu = [
            "label" => "Action",
            "items" => $actionItems,
        ];

        // we don't have rows yet, so save LINEACTIONS for the whole object
        $vars["LINEACTIONS"] = $lineActionMenu;

        // for callbacks
        $vars['doc_op'] = GetOperationId('inv/lists/inventorywqorder/view');

        //So we know which (pick, pack, ship, invoice) is turned on at UI client side
        $vars['config_pick'] = $pick;
        $vars['config_pack'] = $pack;
        $vars['config_ship'] = $ship;
        $vars['config_invoice'] = $invoice;

        $vars['rootLevel'] = ( IsMultiEntityCompany() && (! GetContextLocation()));

        return $vars;
    }


    /**
     * Return an Array of javascript files to include into the page
     *
     * @return array the list of javascript files to include
     */
    protected function getJavaScriptFileNames()
    {
        return array(
            '../resources/js/oeinvouttrackinggrid.js',
            '../resources/js/inventorywqorder.js',
        );
    }


    /**
     *  given the data we read, setup the data for the form
     *
     * @param array $obj
     *
     * @return bool
     *
     * @throws Exception
     */
    protected function transformBizObjectToView(&$obj)
    {
        // here we get one 'orders' record, but not in the orders array.
        // not sure if that's something to change, or not.
        return true;
    }

    /**
     *      take Action - one or more lines in the UI are invoking an action.
     *                      The action is one of the 'ACTION' commands:
     *                      ('O', 'RPI', 'PI', 'RPA', 'PA', 'RS', 'S', 'H'),
     *                      or the PRINT commands: SPRINT, PAPRINT, PIPRINT
     *
     * @return  array                what to return
     */
    protected function takeAction()
    {
        $action = Request::$r->ACTION;
        $byOrder = Request::$r->BYORDER;
        $rows = json_decode(Request::$r->ROWS, true);
        $result = [];
        $result['ok'] = false;
        $errorCheckpoint = Globals::$g->gErr->Checkpoint();

        // fill in each row with its action
        foreach ($rows as $i => $row) {
            $rows[$i]['ACTION'] = $action;  // same action for all
        }
        $iwqoManager = Globals::$g->gManagerFactory->getManager("inventorywqorder");
        $iwqManager  = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");

        // Note: Print commands are handled in the UI as of now....
        //'PIPRINT', 'PAPRINT', 'SPRINT'

        if (strpos($action, 'PRINT') !== false) {
            $result['text'] = '[Code Bug] Print command down in takeAction()';
        } else if ($byOrder) {
            try {
                // The backend always uses 'TRACKINGENTRIES' but the UI uses 'TRACKING'.
                foreach ($rows as $index => $row) {
                    if (isset($rows[$index]['TRACKING'])) {
                        $rows[$index]['TRACKINGENTRIES'] = [];
                        foreach ($row['TRACKING'] as $trackRow) {
                            // is it a real row? Not one added in the UI and never filled in?
                            if (isset($trackRow['QUANTITY']) ||
                                isset($trackRow['QUANTITYRESERVED']) ||
                                isset($trackRow['QUANTITYPICKED']) ||
                                isset($trackRow['QUANTITYPACKED'])) {

                                // The UI doesn't send us the QUANTITY field unless we sent it to the UI.
                                // that is, for a new tracking row created in the Fulfilment UI, QUANTITY is empty.
                                // and if we sent UP a tracking record, the QUANTITY is whatever we sent it.
                                // so, if the customer enters a new tracking quantity, the quantity may be wrong.
                                // The UI does insure that the quantity picked/packed is not more than the txn can handle,
                                // so here I derive QUANTITY from that.
                                //
                                // and RESERVED is like QUANTITY: the UI doesn't alter it from what was sent.  So if the
                                // customer entered a RESERVED amount in OE it comes back to us.  And may be too large!
                                //
                                // so here we need to make quantity at least as large as max(picked, packed)
                                // and reserved can't cause us to exceed quantity.
                                $minQuantity  = max(($trackRow['QUANTITYPICKED'] ?? 0), ($trackRow['QUANTITYPACKED'] ?? 0));
                                $minQuantity2 = ($trackRow['QUANTITYRESERVED'] ?? 0) + $minQuantity;
                                $quantityToFulfill = $trackRow['QUANTITY'] ?? 0;
                                if ($quantityToFulfill < $minQuantity) {  // what we sent or the min we need
                                    $quantityToFulfill = $minQuantity;
                                }
                                if ($minQuantity2 > $quantityToFulfill) {
                                    $trackRow['QUANTITYRESERVED'] = $quantityToFulfill - $minQuantity;  // could be zero
                                }

                                $trackRow['QUANTITY']       = $quantityToFulfill;
                                $trackRow['TRACK_QUANTITY'] = $quantityToFulfill;

                                unset($trackRow['QUANTITYALLOCATED'], $trackRow['__dummy'], $trackRow['_isNewLine']); // FF UI does not use this
                                $rows[$index]['TRACKINGENTRIES'][] = $trackRow;
                            }
                        }
                        unset($rows[$index]['TRACKING']);
                    }
                }

                $result['ok'] = $iwqoManager->takeActionOnOrders($rows);
                if ($result['ok']) {
                    $result['text'] = _('Action taken.');
                } else {
                    $result['text'] = $this->getPrintableErrorString();
                }
            } catch (Exception $e) {
                $result['ok'] = false;
                $result['text'] = $e->getMessage();
            }
        } else {
            $result['text'] = '[Code Bug] non by-order commands not ready yet, sorry';
        }
        $result['counts'] = $iwqManager->countsPerQueue();
        Globals::$g->gErr->Restore($errorCheckpoint);
        return $result;
    }


    /**
     *  get Detail Records.
     *
     * @param   string           $iwqorderid
     * @return array|bool       what to be sent back to the client
     */
    protected function getDetails($iwqorderid)
    {
        $result                  = [];
        $result['ok']            = true;
        $result['text']          = '';
        $result['RESULT']        = [];
        $result['AVAIL_TRACKED'] = [];

        $iwqoManager  = Globals::$g->gManagerFactory->getManager("inventorywqorder");
        try {
            $bundle = $iwqoManager->get($iwqorderid);
            if (($bundle === false) || HasErrors()) {
                $result['ok']   = false;
                $result['text'] = Globals::$g->gErr->getErrorsByEnvironment($errCount, $errToShow, $allErrors);   // myToString(true, 20);
            } else {
                foreach ($bundle['ENTRIES'] as $index => $row) {
                    if (isset($row['TRACKINGENTRIES'])) {
                        foreach ($row['TRACKINGENTRIES'] as $rowIndex => $trackingEntry) {
                            unset($row['TRACKINGENTRIES'][$rowIndex]['QUANTITYALLOCATED']); // FF UI does not use this
                        }
                        $bundle['ENTRIES'][$index]['TRACKING'] = $row['TRACKINGENTRIES'];
                        unset($bundle['ENTRIES'][$index]['TRACKINGENTRIES']);
                    }
                }
                // records are in record# order or some such, not in lineno order....
                usort($bundle['ENTRIES'], function($a,$b) {
                    if ($a['LINENO'] < $b['LINENO']) {
                        return -1;
                    }
                    if ($a['LINENO'] > $b['LINENO']) {
                        return +1;
                    }
                    return 0;
                });
                $this->collectItemDataForTracking($bundle);  // there must be at least ONE
                $result['RESULT']        = $bundle['ENTRIES'];
                $result['AVAIL_TRACKED'] = $bundle['AVAIL_TRACKED'];
            }
        } catch (Exception $e) {
            $result['ok']   = false;
            $result['text'] = $e->getMessage();
        }
        return $result;
    }


    /**
     * This function handles bulk convert from fulfillment screen. It's called from inventorywqoder.js::onBulkConvertHandler
     *
     * @return  array                what to return
     */
    protected function bulkConvert()
    {
        $rows           = json_decode(Request::$r->ROWS, true);
        $result         = [];

        try {
            $bizLogic       = Globals::$g->gManagerFactory->_getObjectInstance("InvBizLogicForWD");
            $whatHappened   = [];
            $result['ok']   = $bizLogic->bulkConvert($rows, $whatHappened);
            if ($result['ok']) {
                $result['text'] = $whatHappened;    // this could be very large!
            } else {
                $result['text'] = $this->getPrintableErrorString();
            }
        } catch (Exception $e) {
            $result['ok'] = false;
            $result['text'] = $e->getMessage();
        }
        return $result;
    }


    /**
     * Map the ajax action to a PHP function
     *
     * @param string $cmd the Ajax action requested
     *
     * @return bool false if command not found
     */
    protected function runAjax($cmd)
    {
        $ok = true;
        switch ($cmd) {
            case 'takeAction':
                $list = $this->takeAction();
                echo json_encode($list);
                break;

            case 'getDetails':
                $list = $this->getDetails(Request::$r->ID);
                echo json_encode($list);
                break;

            case 'bulkConvert':
                $list = $this->bulkConvert();
                echo json_encode($list);
                break;

            default:
                $ok = parent::runAjax($cmd);
                break;
        }

        return $ok;
    }


    /**
     *      Given a set of Inventory WQ Detail records, look up all possible tracking
     *  records for them.  Attach them to the records so the UI can find them.
     *
     *
     * @param array        $bundle     The records being sent to the UI
     *
     * @return bool
     */
    protected function collectItemDataForTracking( & $bundle )
    {
        $itemidArray             = [];
        $bundle['AVAIL_TRACKED'] = [];

        // get the list of items and warehouses
        foreach ($bundle['ENTRIES'] as $index => $entry) {
            $bundle['ENTRIES'][$index]['IS_TRACKED'] = 'false';   // default
            if (!empty($entry['ITEMID']) && !empty($entry['WAREHOUSEID'])) {
                list($itemId)           = explode("--", $entry['ITEMID']);
                $itemidArray[$itemId]   = true;   // eliminate dups
            }
        }

        if (!empty($itemidArray)) {
            // get a list of ONLY the tracked items
            $qry   = array();
            $qry[] = "select itemid, enablesno, enablebin, enablelot, enableexpiration, itemtype
                        from icitemmst
                       where cny# = :1 ";
            $qry[] = GetMyCompany();
            $qry   = PrepINClauseStmt($qry, array_keys($itemidArray), " and itemid ");
            $res   = QueryResult($qry);
            if ($res === false) {
                return false;
            }

            // Index the tracked items
            $itemidArray = [];
            foreach ($res as $row) {
                $itemidArray[$row['ITEMID']] = $row;    // one per item
            }

            // The result is only tracked items.  For each, fetch all possible tracking options...
            if (!empty($itemidArray)) {
                $itemMgr     = Globals::$g->gManagerFactory->getManager('item');
                foreach ($bundle['ENTRIES'] as $index => $entry) {
                    list($itemId) = explode("--", ($entry['ITEMID'] ?? ''));
                    if (isset($itemidArray[$itemId])) {
                        $tracking = $itemidArray[$itemId];
                        $enableBin = $tracking['ENABLEBIN'] ?? 'F';
                        $enableSno = $tracking['ENABLESNO'] ?? 'F';
                        $enableLot = $tracking['ENABLELOT'] ?? 'F';
                        $enableExpiration = $tracking['ENABLEEXPIRATION'] ?? 'F';
                        $isTracked = ($enableBin === 'T' || $enableSno === 'T' || $enableLot === 'T' || $enableExpiration === 'T')? 'true' : 'false';

                        $bundle['ENTRIES'][$index]['IS_TRACKED'] = $isTracked;
                        $bundle['ENTRIES'][$index]['ENABLEBIN'] = $enableBin;
                        $bundle['ENTRIES'][$index]['ENABLESNO'] = $enableSno;
                        $bundle['ENTRIES'][$index]['ENABLELOT'] = $enableLot;
                        $bundle['ENTRIES'][$index]['ENABLEEXPIRATION'] = $enableExpiration;
                        $bundle['ENTRIES'][$index]['ITEMTYPE'] = $tracking['ITEMTYPE'];

                        // same item/warehouse as a previous item?
                        // if not, get the tracking data
                        if ( $isTracked === 'true' && ! isset($bundle['AVAIL_TRACKED'][$itemId])) {
                            [$warehouseId] = explode("--", $entry['WAREHOUSEID']);
                            $existingToIgnore                       = [];
                            if (isset($entry['TRACKING'])) { // Note: TRACKING, not TRACKINGENTRIES, to match the UI :-(
                                $existingToIgnore = $entry['TRACKING'];
                                if ($bundle['DOCUMENTTYPE'] === 'order') {
                                    //Only need to tweak the TRACK_QUANTITY if we are an order doc type
                                    foreach ($existingToIgnore as &$existEntry) {
                                        // just want the alloc/reserved, not the total quantity, which,
                                        // when in OPEN state, might be more
                                        $existEntry['TRACK_QUANTITY'] =
                                            ibcadd($existEntry['QUANTITYRESERVED'] ?? 0,
                                                   max($existEntry['QUANTITYPACKED'] ?? 0, $existEntry['QUANTITYPICKED'] ?? 0),
                                                   ItemManager::AVERAGE_COST_DECIMALS, true);
                                        $existEntry['QUANTITY'] = $existEntry['TRACK_QUANTITY'];
                                    }
                                    unset($existEntry);
                                }
                            }
                            $deepFetchForItemTypeSK = false; //We don't need to get the SK components tracking
                            $retVal = $itemMgr->fetchSnLotExpirationInternal($itemId, $warehouseId, '', $tracking, false, $existingToIgnore, $deepFetchForItemTypeSK);
                            $bundle['AVAIL_TRACKED'][$itemId] =  $retVal['track'];
                        }
                    }
                }
            }
        }
        return true;
    }

//  *****************************************************************
//  *****************************************************************
//
//  PRINT support
//
//  *****************************************************************
//  *****************************************************************

    /**
     * Delivers current record in online as well as offline mode
     *
     * @param array $_params the editor params
     * @param bool $offline true if we are printing offline else false
     * @param string|false $out output when Request::$r->_deliverymethod pdf (the defautl)
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {

        $reportSelection = [];
        if ($offline) {
            return parent::Editor_Deliver($_params, $offline, $out);
        }
        //  If tracking access, mark it as for print.
        AdvAuditTracking::setOperation(AuditTrail::OPID_PRINT);

        $action  = Request::$r->_r;
        $request = Request::$r->_rows;
        $request = json_decode($request, true, 512,  JSON_OBJECT_AS_ARRAY);

        //prepare Selection Array
        $reportSelection['ORDERID'] = Request::$r->_orderid;
        $reportSelection['SHIPDATE'] = Request::$r->_shipdate;
        $reportSelection['TRACKINGINFO'] = Request::$r->_trankinginfo;
        $reportSelection['GROUPBY'] = Request::$r->_groupby;
        $reportSelection['SORTBY'] = explode('#~#', Request::$r->_sortby);
        $iwqoManager = Globals::$g->gManagerFactory->getManager("inventorywqorder");
        foreach ($request as $i => $row) {
            $request[$i]['ACTION'] = $action;
        }

        $rows = $iwqoManager->clientRowsToInternalRows($request);

        if ( ! empty($rows)) {
            if ($this->runReport($rows, ($action == 'PIPRINT'), $reportSelection)) {
                // Record the timestamp of when we printed
                $field = ($action == 'PIPRINT') ? 'PICKLISTPRINTED' : 'PACKLISTPRINTED';
                foreach ($request as $index => $row) {
                    $request[$index]['ACTION'] = 'SAVE';
                    $request[$index][$field]   = str_replace('/', '-', GetCurrentUTCTimestamp());
                }
                // todo: can we do anything with the return?
                //    we already have output the print data :-(
                $iwqoManager->takeActionOnOrders($request);
            }
        }
        return true;
    }


    /**
     * @param int[] $recordsToPrint
     * @param bool $printType is this a picklist or a packlist?
     *
     * @param array $reportSelection
     * @return bool
     */
    private function runReport($recordsToPrint, $printType, $reportSelection)
    {
        $params = [];
        $finalIntacctXML= [];
        $params['printas']          = $printType ? 'IA.PICK_SHEET' : 'IA.PACK_SHEET';
        $params['type']             = '_pdf'; // '_html';
        $params['title']            = $params['printas'];
        $params['filenameforexport']= '';
        $params['report']           = 'inventorywqpicklist';    // we're using this report
        $params['2stage']           = false;

        $plr     = new InventoryWQPickListReport($params);
        $ok      = $plr->DoQuery($recordsToPrint, $reportSelection);
        if ($ok) {
            $map = $plr->DoMap();
            //$map = $this->getCompanyInfo($map);
            foreach ($map as $eachReport){
                $dataxml = $plr->GenerateXML($eachReport);
                $intacctxml = [];
                $ok = $ok && $plr->CreateIntacctXML($dataxml, $intacctxml);
                $finalIntacctXML[] = $intacctxml;
            }
            if ($ok) {
                // pass 'true' if you want the pdf returned,
                // otherwise it gets echoed out to the screen.
                /** @noinspection PhpUndefinedVariableInspection */
                $ok = $plr->GeneratePDF($finalIntacctXML, 'false');
            }
        }
        return $ok;
    }


    /**
     * @param array $map
     * @return array
     */
    protected function getCompanyInfo($map)
    {
        $companyData = $this->GetCompanyData(true, false) ;
        $map['report'][0]['COMPANY'][] = $companyData;
        return $map;
    }



    /**
     *  Normally, the 'Key' of the line is the first field.  In our case, the first field, say, BINID,
     *  may not be in use.
     *
     * @param EditorGrid    $grid
     * @param EntityManager $entityMgr
     * @param array         $_obj
     */
    protected function innerCleanupLineItems($grid, $entityMgr, &$_obj)
    {
        $path = $grid->getProperty('path');
        if ( ! is_array($_obj[$path]) ) {
            return;
        }

        if ($path === 'TRACKINGENTRIES') {
            $value = '';
            foreach ($_obj[$path] as $row) {

                if (isset($row['SERIALNO']) && ($row['SERIALNO'] != '')) {
                    $value = 'SERIALNO';
                    break;
                }
                if (isset($row['LOTNO']) && ($row['LOTNO'] != '')) {
                    $value = 'LOTNO';
                    break;
                }
                if (isset($row['EXPIRATION']) && ($row['EXPIRATION'] != '')) {
                    $value = 'EXPIRATION';
                    break;
                }
                if (isset($row['BINID']) && ($row['BINID'] != '')) { // go last, may be --no bin--
                    $value = 'BINID';
                    break;
                }
            }
            if ($value != '') {
                $grid->setProperty('primaryField', $value);
            }
        }
        parent::innerCleanupLineItems($grid, $entityMgr, $_obj);
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens(): array
    {
        $this->textTokens = array_merge($this->textTokens,['IA.NUMBER_PERCENT_FULFILLABLE' , 'IA.ALL_100','IA.NONE_0','IA.PART_PERCENTAGE','IA.OPEN',
        'IA.READY_TO_PICK','IA.PICKED','IA.READY_TO_PACK','IA.PACKED', 'IA.READY_TO_SHIP', 'IA.SHIPPED','IA.READY_TO_INVOICE',
        'IA.HOLD', 'IA.MIXED', 'IA.YES', 'IA.NO', 'IA.STATUS_OF_LINE_ITEMS_THAT_ARE_MARKED_AS_ON_HOLD_WILL_NOT_BE_CHANGED',
        'IA.SELECT_ONE_OR_MORE_ORDER_THEN_CLICK_BUTTON_AGAIN', 'IA.ARE_YOU_SURE_YOU_WANT_TO_BULK_CONVERT_LINES', 'IA.ORDER_CANNOT_BE_CONVERTED_BECAUSE_LINES_ON_HOLD',
        'IA.FF_TD_NEEDS_SETUP_BEFORE_CAN_BE_CONVERTED', 'IA.STATUS_OF_LINE_CANNOT_CHANGE_BECAUSE_IT_IS_ON_HOLD',
        'IA.ORDERS_QTY_BEEN_ALLOCATED_FOR_ITEMS_CHANGING_STATUS_BACK_TO_OPEN_WILL_LOSE_ALLOCATED_QTY','IA.ENTER_NONNEGATIVE_NUMBER_IN_QTY_PICKED_FLD',
        'IA.ENTER_NONNEGATIVE_NUMBER_IN_QTY_PACKED_FLD', 'IA.THERE_WAS_ERROR_SENDING_THIS_DATA_TO_SERVER','IA.THERE_WAS_ERROR_REQUESTING_DETAIL_RECORDS_FROM_SERVER',
        'IA.SELECT_ORDER_LINES_THEN_CLICK_PRINT_AGAIN', 'IA.SELECT_ORDERS_THEN_CLICK_PRINT_AGAIN', 'IA.ROWS_OF_SELECTIONS_HAVE_EXISTING_ASSIGNEES',
        'IA.NO_ORDERS_FOUND', 'IA.NOTHING_TO_INVOICE', 'IA.NOTHING_TO_SHIP', 'IA.NOTHING_TO_PACK' , 'IA.NOTHING_TO_PICK',
        'IA.LOADING_DETAILS','IA.OE_TOTAL_QTY_GREATER_THAN_ENTRY_QTY', 'IA.OE_TRACK_QTY_GREATER_THAN_ENTRY_QTY', 'IA.OE_TRACK_QTY_GREATER_THAN_AVAILABLE_QTY',
        'IA.PRINT_PACK_LIST','IA.BULK_CONVERT','IA.PRINT_PACK_SLIP', 'IA.ASSIGN_TO', 'IA.CONVERT','IA.EQUALS',
        'IA.SERIAL_NUMBER', 'IA.LOT_NUMBER','IA.EXPIRATION_DATE',
        'IA.SERIAL','IA.SERIAL_EXPIRATION', 'IA.LOT','IA.LOT_EXPIRATION','IA.BIN','IA.SERIAL_LOT','IA.SERIAL_LOT_EXPIRATION',
        'IA.SERIAL_BIN','IA.SERIAL_BIN_EXPIRATION','IA.LOT_BIN','IA.LOT_BIN_EXPIRATION','IA.SERIAL_LOT_BIN','IA.SERIAL_LOT_BIN_EXPIRATION',
        'IA.LOWERCASE_TRUE','IA.DOCUMENT','IA.DOCUMENT_TYPE','IA.DOCUMENT_NUMBER','IA.DOCUMENT_TEMPLATE_ID','IA.DOCUMENT_TEMPLATE_KEY',
        'IA.DOCUMENT_TEMPLATE_RECORD_NUMBER','IA.MAIN_KEY','IA.ORIGINATING_DOCUMENT','IA.RECORD_URL','IA.SHIPPING_TRACKING','IA.SOME_ITEMS_ALLOCATED']);
        return parent::getFormTokens();
    }

}
