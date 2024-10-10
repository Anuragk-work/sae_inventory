<?php


/**
 * An editor class for Inventory Supplies
 */
class InvSuppliesEditor extends FormEditor
{


    /**
     * Inventory supplies specific tokens
     * @var array
     */
    private $inventorySuppliesTokens = [ 'IA.DONE', 'IA.NONE' ];


    /**
     * @param array $_params the parameters of the class
     */
    public function __construct($_params)
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->inventorySuppliesTokens);
        parent::__construct($_params);

        $this->addHandler_Refresh();
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
        return false;
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
     * Add refresh handler
     */
    private function addHandler_Refresh()
    {
        $this->kActionHandlers['refresh'] = array(
            'handler' => 'processRefresh',
            'states' => array(
                $this->kShowViewState,
                $this->kShowEditState,
                $this->kShowNewState,
                $this->kInitState,
            )
        );
    }


    /**
     * Handler to process the refreshing of the screen.
     *
     * @param array $_params   the metadata
     *
     * @return bool            true on success
     */
    protected function processRefresh(&$_params)
    {
        $obj = $this->getEntityMgr()->get(0);

        $this->mediateDataAndMetadata($obj);

        Request::$r->SetCurrentObject($obj);

        return true;
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
     *      Manage UI presentation for view/edit
     *
     * @param array $obj
     *
     * @return bool  true on success and false on failure
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        // setup the href link for clicking on DOCID
        $docviewop = GetOperationId("po/lists/podocument/view");
        $this->setProperty('DOCID', 'onclick', "LaunchObjLink(this, $docviewop, 'po');");

        // setup the href link for clicking on ITEM
        $invviewop = GetOperationId("inv/lists/item/view");
        $this->setProperty('ITEM', 'onclick', "LaunchObjLink(this, $invviewop, 'po');");

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

        $vars['rootLevel'] = ( IsMultiEntityCompany() && (! GetContextLocation()));
        // for callbacks
        $vars['doc_op'] = GetOperationId('inv/lists/invsupplies');
        $vars['inv_op'] = GetOperationId('inv/lists/invdocument/create');
        $vars['po_op']  = GetOperationId('po/lists/podocument/create');
        $vars['replenish_op']  = GetOperationId('inv/activities/replenishment');

        GetModulePreferences(Globals::$g->kINVid, $invPrefs);
        $vars['DirectShipTD'] = $invPrefs['SUPPLIESINVENTORYDS'] ?? '';
        $vars['PoTD']         = $invPrefs['SUPPLIESINVENTORYPO'] ?? '';


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
            '../resources/js/oeinvouttrackinggrid.js', // ??
            '../resources/js/invsupplies.js',
        );
    }


    /**
     *      Get the action items for one line
     *
     * @return array
     */
    private function getLineActions($row)
    {
        // ACTION MENU:

        $actionItems = [];

        $legalActions = $row['VALID_ACTIONS'];

        if (in_array('ISSUE', $legalActions)) {
            $actionItems[] = [
                "label" => "IA.ISSUE",
                "type"  => "callback",
                "props" => ["func" => "rowAction", "customProps" => ['action' => 'ISSUE']],
            ];
        }

        if (in_array('PO', $legalActions)) {
            $actionItems[] = [
                "label" => "IA.CREATE_PO",
                "type"  => "callback",
                "props" => ["func" => "rowAction", "customProps" => ['action' => 'PO']],
            ];
        }

        if (in_array('DIRECTSHIP', $legalActions)) {
            $actionItems[] = [
                "label" => "IA.CREATE_DIRECT_SHIP",
                "type"  => "callback",
                "props" => ["func" => "rowAction", "customProps" => ['action' => 'DIRECTSHIP']],
            ];
        }

        if (in_array('REPLENISH', $legalActions)) {
            $actionItems[] = [
                "label" => "IA.REPLENISHMENT",
                "type"  => "callback",
                "props" => ["func" => "rowAction", "customProps" => ['action' => 'REPLENISH']],
            ];
        }
        /* ****
            if (in_array('LINK', $legalActions)) {
                $actionItems[] = [
                    "label" => "Link to purchase order",
                    "type"  => "callback",
                    "props" => ["func" => "rowAction", "customProps" => ['action' => 'LINK']],
                ];
            }

            if (in_array('TRANSFER', $legalActions)) {
                $actionItems[] = [
                    "label" => "Warehouse transfer",
                    "type"  => "callback",
                    "props" => ["func" => "rowAction", "customProps" => ['action' => 'TRANSFER']],
                ];
            }
        *** */
        if (in_array('ACK', $legalActions)) {
            $actionItems[] = [
                "label" => "IA.ACKNOWLEDGE_RECEIPT",
                "type"  => "callback",
                "props" => ["func" => "rowAction", "customProps" => ['action' => 'ACK']],
            ];
        }

        $actionItems[] = [
            "label" => "IA.PRINT",
            "type" => "callback",
            "props" => ["func" => "rowAction", "customProps" => ['action' => 'PRINT']],
        ];

        // others go here....

        return $actionItems;
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
        $suppliesManager = Globals::$g->gManagerFactory->getManager("invsupplies");
        $docId           = Request::$r->_obj__FROMDOCID ?? 0;
        $obj2            = $suppliesManager->Get($docId);
        if ($obj2 === false) {
            return false;
        }
        foreach ($obj2['LINES'] as $index => $row) {
            $obj2['LINES'][$index]['LINEACTIONS'] = [
                "label" => "IA.ACTION",
                "items" => $this->getLineActions($row)
            ];
        }
        $obj = (array)$obj2;    // without the shenanigans, the compiler complains $obj is JUST an array, not array|bool

        return true;
    }




    /**
     *      take Action - one or more lines in the UI are invoking an action.
     *                      The action is one of the 'ACTION' commands:
     *
     * @return  array                what to return
     */
    protected function takeAction()
    {
        $action = Request::$r->ACTION;
        $rows = json_decode(Request::$r->ROWS, true);
        $result = [];
        $result['ok'] = false;
        $errorCheckpoint = Globals::$g->gErr->Checkpoint();

        // fill in each row with its action
        foreach ($rows as $i => $row) {
            $rows[$i]['ACTION'] = $action;  // same action for all
        }
        $suppliesManager = Globals::$g->gManagerFactory->getManager("invsupplies");

        // handle actions
        try {
            $result['text'] = '';
            $result['ok']   = $suppliesManager->takeAction($action, $rows, $refresh);
            if ( ! $result['ok']) {
                $result['text'] = $this->getPrintableErrorString();
            } else if ($action === 'ACK') {
                $textMap        = getLocalizedText(I18N::tokenArrayToObjectArray(['IA.RECEIPT_ACKNOWLEDGED']), $error);
                $text           = $textMap['IA.RECEIPT_ACKNOWLEDGED'];
                $result['text'] = $text;
            }
            $result['refresh'] = $refresh;
        } catch (Exception $e) {
            $result['ok'] = false;
            $result['text'] = $e->getMessage();
        }
        Globals::$g->gErr->Restore($errorCheckpoint);
        return $result;
    }


    /**
     * This function handles bulk convert from the supplies workbench screen.
     *
     * @return  array                what to return
     */
    protected function bulkConvert()
    {
        $rows           = json_decode(Request::$r->ROWS, true);
        $result         = [];

        try {
            $suppliesManager = Globals::$g->gManagerFactory->getManager("invsupplies");
            $whatHappened   = [];
            $result['ok']   = $suppliesManager->bulkConvert($rows, $whatHappened);
            if ($result['ok']) {
                $result['text'] = $whatHappened;    // this could be very large!
            } else {
                $result['text'] = $this->getPrintableErrorString();
            }
        } catch (Exception $e) {
            $result['ok']   = false;
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
            case 'bulkAction':
                $list = $this->takeAction();
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
        $this->textTokens = array_merge($this->textTokens,['IA.NUMBER_PERCENT_FULFILLABLE' , 'IA.ALL_100','IA.NONE_0','IA.PART_PERCENTAGE',
            'IA.YES', 'IA.NO',
            'IA.SELECT_ONE_OR_MORE_ORDER_THEN_CLICK_BUTTON_AGAIN', 'IA.ARE_YOU_SURE_YOU_WANT_TO_BULK_CONVERT_LINES',
            'IA.THERE_WAS_ERROR_SENDING_THIS_DATA_TO_SERVER',
            'IA.SELECT_ORDER_LINES_THEN_CLICK_PRINT_AGAIN', 'IA.SELECT_ORDERS_THEN_CLICK_PRINT_AGAIN',
            'IA.BULK_CONVERT', 'IA.CONVERT','IA.EQUALS', 'IA.SERIAL_NUMBER', 'IA.LOT_NUMBER','IA.EXPIRATION_DATE',
            'IA.SERIAL','IA.SERIAL_EXPIRATION', 'IA.LOT','IA.LOT_EXPIRATION','IA.BIN','IA.SERIAL_LOT','IA.SERIAL_LOT_EXPIRATION',
            'IA.SERIAL_BIN','IA.SERIAL_BIN_EXPIRATION','IA.LOT_BIN','IA.LOT_BIN_EXPIRATION','IA.SERIAL_LOT_BIN','IA.SERIAL_LOT_BIN_EXPIRATION',
            'IA.DOCUMENT','IA.DOCID','IA.DOCUMENT_TYPE','IA.DOCUMENT_NUMBER', 'IA.RECORD_URL','IA.LINE_NO',
            'IA.SPECIFY_A_VALID_TRANSACTION_FOR_DS', 'IA.SPECIFY_A_VALID_TRANSACTION_FOR_PO',
            'IA.REPLENISHMENT', 'IA.SELECTED_ROWS_MUST_BE_INVENTORY_ITEMS']);
        return parent::getFormTokens();
    }




//  *****************************************************************
//  *****************************************************************
//
//  PRINT support
//
//  *****************************************************************
//  *****************************************************************



    /**
     * Overridden function to change data before printing
     *
     * @param array   $values Object details
     */
    protected function prepareDataForPrinting(&$values)
    {
        parent::prepareDataForPrinting($values);

        $rows               = Request::$r->_rows ?? '';
        $values['RECORDS']  = ($rows !== '') ? json_decode($rows, true, 512,  JSON_OBJECT_AS_ARRAY) : [];

        $suppliesManager    = Globals::$g->gManagerFactory->getManager('invsupplies');

        $values['PRINT_ONE_DOCUMENT'] = false;

        $docId              = Request::$r->_obj__FROMDOCID ?? '';
        if ($docId != '') {
            $values['DOC']    = $suppliesManager->Get($docId);
            $values['LINES']  = $values['DOC']['LINES'] ?? [];
            $values['PRINT_ONE_DOCUMENT'] = true;
        }

        $suppliesManager->prepareDataForPrinting($values);
    }


    /**
     * Abbreviated Editor Deliver to generate output from a Word Template.....
     *
     * This is for EA, not GA; likely we'll want user-created forms and more data....
     *
     * @param array         $_params  the editor params
     * @param bool          $offline  true if we are printing offline else false
     * @param string|false  $out      output when Request::$r->_deliverymethod pdf (the defautl)
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        $dataForPrinting = $this->GetDataForPrinting(false);

        return $this->getEntityMgr()->printSuppliesReport($dataForPrinting, $dataForPrinting['REC']['PRINT_ONE_DOCUMENT'] ?? false);
    }

}
