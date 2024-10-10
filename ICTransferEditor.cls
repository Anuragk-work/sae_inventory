<?php

/**
 * An editor class for the Warehouse Transfer
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * An editor class for the Warehouse Transfer
 */
class ICTransferEditor extends FormEditor
{
    /** @var array $itemDetails */
    private $itemDetails = array();

    /** @var string[] $exchangeFields */
    private $exchangeFields = ['EXCH_RATE_DATE', 'EXCH_RATE_TYPE_ID', 'EXCHANGE_RATE', 'OUT_CURRENCY', 'IN_CURRENCY' ];

    /** @var string $noBinIdHuman */
    private string $noBinIdHuman;  // English or French text of - 'no binid'

    /**
     * Document specific tokens
     * @var string[]
     */
    private $documentTokens = [
        TrackingHandler::NO_BIN_ID_TOKEN,
        'IA.DEFINITION',
        'IA.CREATED_DATE'
    ];
    /**
     * @param array $_params   the parameters of the class
     */
    public function __construct($_params)
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->documentTokens);
        parent::__construct($_params);
    }

     protected function loadTokenLabels() : void
     {
         parent::loadTokenLabels();
         // as soon as translation is ready , set our local var with translated value
         $this->noBinIdHuman = I18N::getSingleToken(TrackingHandler::NO_BIN_ID_TOKEN);
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
        $values = array();
        $data = $this->getViewData();
        $transferState = $data['TRANSFERSTATE'];
        $transferType = $data['TRANSFERTYPE'];

        switch ($state) {
            case Template_CreateWarningState:
            case Editor_ShowNewState:
                if( $this->CanSave() ) {
                    $this->setButtonDetails($values, 'transferoutbuttonid', 'transferoutbutton', 'IA.TRANSFER_OUT', 'transferout', true, 'okToSave(data)');
                    $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', 'IA.POST', 'create', true, 'okToSave(data)');
                    $this->setButtonDetails($values, 'draftbuttonid', 'draftbutton', 'IA.DRAFT', 'draftcreate');
                    $this->createMoreActionEntry($values, 'transferoutbuttonnewid', 'transferoutbuttonnew',
                        'IA.TRANSFER_OUT_AND_NEW', 'transferout', true, 'okToSave(data)', true, false, array('after' => 1));
                    $this->createMoreActionEntry($values, Editor_SaveAndNewBtnID, 'dobuttonnew',
                        'IA.POST_AND_NEW', 'create', true, 'okToSave(data)', true, false, array('after' => 1));
                    $this->createMoreActionEntry($values, 'draftaddandnewbuttid', 'draftaddandnewbutton',
                                                 'IA.DRAFT_AND_NEW', 'draftcreate', true, null, true, true, array('after' => 1));

                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);
                break;
            case Template_EditWarningState:
            case Editor_ShowEditState:
                if ($transferState == 'Draft' && $transferType == 'In transit') {
                    $this->setButtonDetails($values, 'transferoutbuttonid', 'transferoutbutton', 'IA.TRANSFER_OUT', 'save', true, 'okToSave(data)');
                    $this->setButtonDetails($values, 'draftbuttonid', 'draftbutton', 'IA.DRAFT', 'draftsave');
                } else if ( $transferState == 'In transit') {
                    if( $this->CanSave() ) {
                        $this->setButtonDetails($values, 'transferinbuttonid', 'transferinbutton', 'IA.TRANSFER_IN', 'transferin', true, 'okToSave(data)');
                        $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', $this->getLabelForSaveButton(), 'save', true, 'okToSave(data)');
                    }
                } else if ( $transferState == 'Posted'){
                    if( $this->CanSave() ) {
                        $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', $this->getLabelForSaveButton(), 'save', true, 'okToSave(data)');
                    }
                } else {
                    if( $this->CanSave() ) {
                        $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', 'IA.POST', 'save', true, 'okToSave(data)');
                        $this->setButtonDetails($values, 'draftbuttonid', 'draftbutton', 'IA.DRAFT', 'draftsave');
                    }
                }
                 if ($this->CanDuplicate()) {
                     $this->createMoreActionEntry($values, 'savebutton', 'copybutton',
                                                 'IA.DUPLICATE', 'copy', true, 'okToDuplicate(data)', true, true);
                }

                // doesn't seem to be used in the php editor and its action is not right $this->setButtonDetails($values, 'saveandprintbutton', 'Save & Print', 'save');
                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton',
                        'IA.PRINT_TO', 'deliver', false, "showDeliverPageNew(true, data)", false);
                }

                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }

                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);
                break;
            case Editor_ShowViewState:
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }
                if( $this->CanPrint() ) {
                    $this->setButtonDetails($values, 'saveandprintbuttid', 'deliverbutton', 'IA.PRINT_TO', 'deliver', false, "showDeliverPageNew(true, data)", false);
                }
                if($this->CanEdit()) {
                    $this->setButtonDetails($values, 'editbuttid', 'editbutton', 'IA.EDIT', 'edit', false, 'window.editor.doEdit()', false);
                }
                if ($this->CanDuplicate()) {
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'okToDuplicate(data)', true, true);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);
                break;
        }

        $this->addHelpButton($values);
        return $values;
    }



    /**
     * @param array $obj
     *
     * @return bool  true on success and false on failure
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $view = $this->getView();
        $action = $this->kDefaultVerbActions[Request::$r->_do];
        $obj['DUMMY'] = '   ';
        $obj['LINEITEMWAREHOUSE'] = "  ";   // placeholders
        $obj['LINEITEMID']        = "  ";
        $kINVid = Globals::$g->kINVid;
        GetModulePreferences($kINVid, $prefs);
        if ($this->state != $this->kShowNewState) {
            if ($obj['DOCNO'] != '') {
                $this->setTitleEncoded('Warehouse Transfer : ' . $obj['DOCNO']);
            }
        }
        if ( $action == 'edit'){
            $view->findAndSetProperty(array('path' => 'TRANSFERTYPE'), array('readonly' => true));

        }
        if ($action == 'view' || $action == 'edit') {
            $sess = Session::getKey();
            $docviewop = GetOperationId("inv/lists/invdocument/view");

            // Roger's note: These fields are not on the UI anymore, but Tracy would like them on a 'history tab',
            //        so I'm leaving the code here....
            $matches = array();
            $view->findComponents(array('path' => 'OUT_DOCID'), EditorComponentFactory::TYPE_FIELD, $matches);
            if (isset($matches[0])) {
                $url = "editor.phtml?.sess=$sess&.op=$docviewop&.mod=inv&.r=" . urlencode($obj['OUT_DOCID']) . "&.popup=1";
                $matches[0]->setProperty('onclick', "Launch('$url','mywindow','700','500');");
            }

            $matches = array();
            $view->findComponents(array('path' => 'IN_DOCID'), EditorComponentFactory::TYPE_FIELD, $matches);
            if (isset($matches[0])) {
                $url = "editor.phtml?.sess=$sess&.op=$docviewop&.mod=inv&.r=" . urlencode($obj['IN_DOCID']) . "&.popup=1";
                $matches[0]->setProperty('onclick', "Launch('$url','mywindow','700','500');");
            }

            if ($action == 'edit') {
                $itemDetails = $this->collectItemData();
                foreach ($obj['ENTRIES'] as &$entry) {
                    $entry['COSTMETHOD'] = $itemDetails[$entry['ITEMID']]['cost_method'];
                }
            }
        } elseif ($action == 'new') {
            $obj['TRANSACTIONDATE'] = GetCurrentDate();
            $obj['EXCH_RATE_DATE'] = $obj['TRANSACTIONDATE'];
            if (IsMCMESubscribed() && GetContextLocation() == '') {
                $gManagerFactory = Globals::$g->gManagerFactory;
                $invSubsMgr = $gManagerFactory->getManager('invsetup');
                $obj['EXCH_RATE_TYPE_ID'] = $invSubsMgr->getExchangeRateType();
            }
            $obj['OUT_LOCATIONID'] = $obj['OUT_LOCATIONID'] ?? '';
            $obj['IN_LOCATIONID']  = $obj['IN_LOCATIONID']  ?? '';
            $obj['OUT_CURRENCY']   = $obj['OUT_CURRENCY']   ?? '';
            $obj['IN_CURRENCY']    = $obj['IN_CURRENCY']    ?? '';
        }
        $obj['ARE_ADVANCED_BINS_ON'] = (BinManager::areAdvanedBinsOn() ? 'T' : 'F');
        $obj['RESTRICT_BINS_BY_QTY'] = 'F'; // on the OUTBOUND side, not the INBOUND side

        if($prefs['ENABLEINTRANSITTRANSFER'] == 'T'){
            $view->findAndSetProperty(array('path' => 'TRANSFERTYPE'), array('hidden' => false));
            if($action == 'new' && (empty($obj['TRANSFERTYPE']))){
                if($prefs['DEFAULTINTRANSITTRANSFER'] == 'T'){
                    $obj['TRANSFERTYPE'] = 'In transit';
                    $view->findAndSetProperty(array('path' => 'OUTDATE'), array('required'=> true));
                    $view->findAndSetProperty(array('path' => 'INDATE'),  array('required'=> true));
                } else {
                    $obj['TRANSFERTYPE'] = 'Immediate';
                    //$view->findAndSetProperty(array('path' => 'OUTDATE'), array('hidden' => true));
                    //$view->findAndSetProperty(array('path' => 'INDATE'), array('hidden' => true));
                }
            } else if (($action == 'view' || $action == 'edit')) {
                if($obj['TRANSFERTYPE'] == 'In transit'){
                    $view->findAndSetProperty(array('path' => 'OUTDATE'), array( 'required'=> true));
                    $view->findAndSetProperty(array('path' => 'INDATE'),  array( 'required'=> true));
                    if($obj['TRANSFERSTATE'] == 'In transit'){
                        $view->findAndSetProperty(array('path' => 'OUTDATE'), array( 'fullname'=> 'IA.TRANSFER_OUT_DATE'));
                    } else if($obj['TRANSFERSTATE'] == 'Posted'){
                        $view->findAndSetProperty(array('path' => 'OUTDATE'), array( 'fullname'=> 'IA.TRANSFER_OUT_DATE'));
                        $view->findAndSetProperty(array('path' => 'INDATE'),  array( 'fullname'=> 'IA.TRANSFER_IN_DATE'));
                    }
                } else{
                    $view->findAndSetProperty(array('path' => 'OUTDATE'), array('hidden' => true));
                    $view->findAndSetProperty(array('path' => 'INDATE'), array('hidden' => true));
                }
            }
        } else {
            $obj['TRANSFERTYPE'] = 'Immediate';
            $view->findAndSetProperty(array('path' => 'OUTDATE'), array('hidden' => true));
            $view->findAndSetProperty(array('path' => 'INDATE'), array('hidden' => true));
        }
        $this->mediateDataAndMetadata_History();

        return true;
    }


    /**
     * @param  string   $field          the field name
     * @param  string   $property       property to set, like 'hidden'
     * @param  string   $to             what to set it to
     */
    private function setProperty( $field, $property, $to )
    {
        $view = $this->getView();
        $fields = array();
        $view->findComponents(array('path' => $field), EditorComponentFactory::TYPE_FIELD, $fields);
        foreach ($fields as $oneField) {
            $oneField->setProperty($property, $to);
        }
    }


    /**
     * @param string    $field          the field name
     */
    private function hideField( $field )
    {
        $this->setProperty( $field, 'hidden', true );
    }


    /**
     * @param array $params
     */
    protected function buildDynamicMetadata(&$params)
    {
        parent::buildDynamicMetadata($params);

        $multiCurrency = (IsMCMESubscribed() && GetContextLocation() =='');

        $unitFld = array();
        self::findElements($params, array('path' => 'UNIT'), EditorComponentFactory::TYPE_FIELD, $unitFld);
        if ($unitFld[0]) {
            $unitFldType = array(
                'ptype' => 'webCombo',
                'type' => 'enum',
                'size' => '5',
            );
            $unitFld[0]['type'] = $unitFldType;
        }

        $matches = array();
        self::findElements(
            $params, array('path' => 'IN_WAREHOUSEID'), EditorComponentFactory::TYPE_FIELD, $matches
        );
        $matches[0]['events']['change'] .= 'getWarehouseLocation(this);';
        if ($multiCurrency) {
            $matches[0]['events']['change'] .= 'UpdateExchangeRateIn(this);';
            $matches[0]['events']['change'] .= 'calculateInPrice(this);';
        }

        if ( !util_isPlatformDisabled() ) {
            $matches[0]['standard'] = true;
            $matches[0]['autofillrelated'] = Pt_StandardUtil::autoFillRelated('warehouse');
        }

        $matches = array();
        self::findElements(
            $params, array('path' => 'OUT_WAREHOUSEID'), EditorComponentFactory::TYPE_FIELD, $matches
        );
        $matches[0]['events']['change'] .= 'getWarehouseLocation(this);';
        if ($multiCurrency) {
            $matches[0]['events']['change'] .= 'UpdateExchangeRateIn(this);';
        }
        if ( !util_isPlatformDisabled() ) {
            $matches[0]['standard'] = true;
            $matches[0]['autofillrelated'] = Pt_StandardUtil::autoFillRelated('warehouse');
        }

        // Deal with the exchange rate fields
        if ($multiCurrency) {
            foreach ($this->exchangeFields as $exchangeField) {
                $matches = array();
                self::findElements(
                    $params, array('path' => $exchangeField), EditorComponentFactory::TYPE_FIELD, $matches
                );
                if ($exchangeField != 'EXCHANGE_RATE') {
                    $matches[0]['events']['change'] .= 'UpdateExchangeRateIn(this);';
                }
                $matches[0]['events']['change'] .= 'calculateInPrice(this);';
            }
        }

        $matches = array();
        self::findElements(
            $params, array('path' => 'IN_CURRENCY'), EditorComponentFactory::TYPE_FIELD, $matches
        );
        $matches[0]['events']['change'] .= 'UpdateExchangeRateIn(this);';
        $matches[0]['events']['change'] .= 'calculateInPrice(this);';

        $matches = array();
        self::findElements(
            $params, array('path' => 'OUT_CURRENCY'), EditorComponentFactory::TYPE_FIELD, $matches
        );
        $matches[0]['events']['change'] .= 'UpdateExchangeRateIn(this);';
        $matches[0]['events']['change'] .= 'calculateInPrice(this);';

        $view = Request::$r->_do == 'view';
        if ($view) {
            // make the item and warehouse grid values clickable links
            // do only for view, edit needs to remain picker.
            $matches = [];
            self::findElements($params, ['path' => 'ITEMID'], EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches[0]) {
                $matches[0]['type']['ptype'] = 'href';
                $matches[0]['type']['type'] = 'href';
                $matches[0]['onclick'] = "ViewItem(this, 'item');";
            }

            $matches = [];
            self::findElements($params, ['path' => 'WAREHOUSE.LOCATION_NO'], EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches[0]) {
                $matches[0]['type']['ptype'] = 'href';
                $matches[0]['type']['type'] = 'href';
                $matches[0]['onclick'] = "ViewWarehouse(this, 'warehouse');";
            }
        }
    }


    /**
     * Prepare the view for customization
     */
    protected function processViewBeforePageCustomzations()
    {
        // Get the view
        $view = $this->getView();

        $this->setProperty( 'OUT_WAREHOUSEID', 'required', true );
        $this->setProperty( 'IN_WAREHOUSEID',  'required', true );

        $this->setProperty( 'OUT_CURRENCY','readonly', true );
        $this->setProperty( 'IN_CURRENCY', 'readonly', true );


        /* *** When we get in and out doc id
        $action = $this->kDefaultVerbActions[Request::$r->_do];
        if ($action == 'view' || $action == 'edit') {
            $this->setProperty( 'OUT_DOCID', 'hidden', false );
            $this->setProperty( 'IN_DOCID',  'hidden', false );
        }
        ****************** */

        if (IsMultiEntityCompany()) {
            $this->setProperty( 'OUT_LOCATIONID', 'required', true );
            $this->setProperty( 'IN_LOCATIONID',  'required', true );
        }

        //hiding dimensions from the grid
        $matches = array();
        $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $matches);
        $gridObj = &$matches[0];

        // $prePrintedPageFormat[$key]->SetProperty(array('type', 'validlabels'), $validLabels);

        $prefix = '';
        $fields = $this->getDimensionsFields($params, $prefix);

        foreach ($fields as &$field) {
            $matches = array();
            $gridObj->findComponents(array('path' => $field['path']), EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches) {
                $matches[0]->setProperty('hidden', true);
            }
        }

        $multiCurrency = (IsMCMESubscribed() && GetContextLocation() =='');
        foreach ($this->exchangeFields as $exchangeField) {
            if ( ! $multiCurrency) {
                $this->hideField($exchangeField);
            }
        }
    }


    /**
     * Register global javascript variables
     *
     * @return array the editor globals
     */
    protected function getEditorGlobals()
    {
        $vars = parent::getEditorGlobals();

        $kINVid = Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invprefs);

        $vars['defaultuomgrp'] = $invprefs['DEFAULT_UOMGRP'];
        $vars['app_precision'] = ($invprefs['ITEMPRECISION']) ?: 2;
        $vars['itemdensearr']  = $this->collectItemData();
        $vars['_dt'] = ICTransferManager::OUTDOCTYPE;
        $vars['invstatusop'] = GetOperationId('inv/reports/invstatus');
        $vars['mod'] = Request::$r->_mod;
        $vars['ismcpEnabled'] = IsMCPEnabled();
        $vars['EXCHANGERATE_OPID_VIEW'] = GetOperationId("co/lists/exchangerate/view");
        $vars['IS_MCME'] = IsMCMESubscribed();
        $vars['CONTXT_LOC'] =  GetContextLocation();
        $vars['intransferEnabled'] = ( $invprefs['ENABLEINTRANSITTRANSFER']
            && $invprefs['ENABLEINTRANSITTRANSFER'] == 'T') ? true: false;
        $vars['docviewop'] = GetOperationId("inv/lists/invdocument/view");
        $vars['configOp'] = GetOperationId("inv/activities/invdocumentparams/view");

        if ( StkitDocumentManager::isStockableKitTrackingEnabled() ) {
            $vars['ENABLESTOCKABLEKITTRACKING'] = 'T';
        } else {
            $vars['ENABLESTOCKABLEKITTRACKING'] = 'F';
        }

        if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled() ) {
            $vars['ENABLESTOCKABLEKITCOMPONENTTRACKING'] = 'T';
        } else {
            $vars['ENABLESTOCKABLEKITCOMPONENTTRACKING'] = 'F';
        }

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
            '../resources/thirdparty/fancybox/jquery.mousewheel-3.1.13.min.js',
            '../resources/thirdparty/fancybox/fancybox.js',
            '../resources/js/allocation_helper.js',
            '../resources/js/documenteditor_new.js',
            '../resources/js/ictransfer.js',
            '../resources/js/mvdocument.js',
            '../resources/js/polyfill/promise.js',
            '../resources/js/qrequest.js',
            '../resources/js/project_helper.js',

        );
    }



    /**
     * @param array     $_params
     * @param string    $platformFldnameSuffix
     *
     * @return array
     */
    private function getDimensionsFields(&$_params, $platformFldnameSuffix)
    {
        $primaryDim = $this->getEntityMgr()->getPrimaryDimensions();
        if (is_array($primaryDim)) {
            foreach ($primaryDim as $dimPath => $fieldPath) {
                $_params['view']['primaryDimensions'][$dimPath] = $fieldPath;
            }
        }

        $nodes = $this->getDefaultsDimensionsFields(
            $_params, 'ictransferitem', '', $platformFldnameSuffix
        );

        return $nodes;
    }


    /**
     * This function can be overriden if no default dimension fields are wanted
     *
     * @return bool
     */
    protected function isShowGridDefaults()
    {
        return false;
    }


    /**
     * Merge dimension fields in the UI
     *
     * @param array $_params
     */
    protected function MergeOwnerDimensions(&$_params)
    {
        parent::MergeOwnerDimensions($_params);
        $this->mergeTransferOut($_params);
        $this->mergeTransferIn($_params);
    }

    /**
     * @param array $params
     *
     * @return bool
     */
    protected function mergeTransferOut(&$params)
    {
        $ok = $this->mergeDims($params, 'outSection', 'OUT_', 'IA.TRANSFER_OUT_DIMENSIONS');
        return $ok;
    }

    /**
     * @param array $params
     *
     * @return bool
     */
    protected function mergeTransferIn(&$params)
    {
        $ok = $this->mergeDims($params, 'inSection', 'IN_', 'IA.TRANSFER_IN_DIMENSIONS');
        return $ok;
    }


    /**
     * @param array         $params
     * @param string|int    $sectionId
     * @param string        $prefix
     * @param string        $title
     *
     * @return bool
     */
    private function mergeDims(&$params, $sectionId, $prefix, $title)
    {
        $matches = array();
        self::findElements($params, array('id' => $sectionId), EditorComponentFactory::TYPE_SECTION, $matches);
        if (is_array($matches) && !empty($matches)) {
            $section =& $matches[0];

            /* **********
                $stdFlds = array(  // now warehouse and docid are in another section

                    array(
                        'path' => $prefix . 'WAREHOUSEID'
                    ),
                    array(
                        'path' => $prefix . 'DOCID',
                    ),
                );

                if (IsMCMESubscribed() && GetContextLocation() == '') {
                    if (strcmp($prefix, 'IN_') == 0) {
                        array_push($stdFlds, array('path' => 'EXCH_RATE_TYPE_ID'));
                        array_push($stdFlds, array('path' => 'EXCH_RATE_DATE'));
                        array_push($stdFlds, array('path' => 'EXCHANGE_RATE'));
                        array_push($stdFlds, array('path' => 'IN_CURRENCY'));
                    } else {
                        array_push($stdFlds, array('path' => 'OUT_CURRENCY'));
                    }
                }
            ***** */
            $stdDims = array();
            if (locationsExist()) {
                $stdDims[] = array(
                    'path' => $prefix . 'LOCATIONID'
                );
            }
            if (departmentsExist()) {
                $stdDims[] = array(
                    'path' => $prefix . 'DEPARTMENTID'
                );
            }

        } else {
            return false;
        }

        $fields = $this->getDimensionsFields($params, $prefix);

        foreach ($fields as &$field) {
            if (!$field['platform']) {
                $field['path'] = $prefix . $field['path'];

                // rename references as well..
                if ( $field['type']['restrict'] ) {
                    foreach ( $field['type']['restrict'] as &$restrictRow ) {
                        $restrictRow['field'] = $prefix . $restrictRow['field'];
                    }
                }
            }
            $field['pathPrefix'] = $prefix;
        }
        unset ($field);

        $fields = INTACCTarray_merge($stdDims, $fields);

        $section = array(
            'title' => $title,
            "isCollapsible" => true,
            "showCollapsed" => true,
            'subsection' => array(
                /* *****************
                    array(
                        'className' => "subSection qx-cfg-subsection",
                        'columnCount' => 3,
                        'field' => $stdFlds
                    ),
                ****************** */
                array(
                    'className' => "subSection qx-cfg-subsection",
                    'title' => '',
                    'columnCount' => 3,
                     'field' => $fields
                ),
            )

        );

        return true;
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {

        $ok = parent::transformBizObjectToView($obj);

        $gManagerFactory = Globals::$g->gManagerFactory;
        $entries = array();
        $populatedOut = false;
        $populatedIn = false;
        $dimFields = $this->getDimensionsFields($params, 'OUT_');
        $itemIDs   = [];

        if (is_array($obj['ENTRIES'])) {
            foreach ($obj['ENTRIES'] as $val) {
                $tempItemID = explode("--", $val['ITEMID']);
                $itemIDs[] = $tempItemID[0];
            }
        }

        $itemCache = [];
        if ( !empty($itemIDs)) {
            $mod =  Request::$r->_mod;
            $itemMgr = $gManagerFactory->getManager('item');
            $itemFieldList = array('ITEMID', 'NAME', 'ITEMTYPE', 'ENABLELOT', 'ENABLESNO', 'ENABLEBIN', 'ENABLEEXPIRATION');
            $itemCache = $itemMgr->GetItemsRawCache(array_unique($itemIDs), true, $itemFieldList, $mod);
            $uomInfoVals = $itemMgr->GetUOMInfoCache($itemIDs, true, false);
        }

        $outByLineNo = [];
        if (is_array($obj['ENTRIES'])) {
            foreach ($obj['ENTRIES'] as $val) {

                [$itemID] = explode('--', $val['ITEMID']);
                $val['ENABLESNO'] = $itemCache[$itemID]['ENABLESNO'];
                $val['ENABLELOT'] = $itemCache[$itemID]['ENABLELOT'];
                $val['ENABLEBIN'] = $itemCache[$itemID]['ENABLEBIN'];
                $val['ENABLEEXPIRATION'] = $itemCache[$itemID]['ENABLEEXPIRATION'];
                $val['ITEMTYPE'] = $itemCache[$itemID]['ITEMTYPE'];
                $val['ITEMNAME'] = $itemCache[$itemID]['NAME'];

                $paths = [];
                if ($val['ENABLESNO'] == 'T') {
                    $paths[] = 'SERIALNO';
                }
                if ($val['ENABLELOT'] == 'T') {
                    $paths[] = 'LOTNO';
                }
                if ($val['ENABLEBIN'] == 'T') {
                    $paths[] = 'BINID';
                    $paths[] = 'TO_BINID';
                }
                if ($val['ENABLEEXPIRATION'] == 'T') {
                    $paths[] = 'EXPIRATION';
                }

                if ($val['IN_OUT'] == 'O') {
                    if (!$populatedOut) {
                        foreach ($dimFields as $field) {
                            $obj['OUT_' . $field['path']] = $val[$field['path']];
                        }
                        $obj['OUT_LOCATIONID'] = $val['LOCATIONID'];
                        $obj['OUT_DEPARTMENTID'] = $val['DEPARTMENTID'];
                        $obj['OUT_WAREHOUSEID'] = $val['WAREHOUSEID'];
                        $obj['OUT_WAREHOUSENAME'] = $val['WAREHOUSENAME'];
                        $populatedOut = true;
                        $this->mergeCustomDimensionsToHeader($obj, $val['CUSTOMDIMENSIONS'], 'OUT_');
                    }
                    foreach ($dimFields as $field) {
                        unset($val[$field['path']]);
                    }

                    $tempItemID = explode("--", $val['ITEMID']);
                    $tempItemID = $tempItemID[0];

                    $itemuoms = array();
                    /** @noinspection PhpUndefinedVariableInspection */
                    foreach ( $uomInfoVals[$tempItemID] as $value) {
                        $itemuoms[] = $value;
                    }

                    $val['ITEMUOM'] = $itemuoms;

                    /** @noinspection PhpUndefinedVariableInspection */
                    $precision = $itemCache[$tempItemID]['PRECISION'] ?? 0;
                    if ($precision || $precision === 0) {
                        $val['ITEM_PRECISION'] = $precision;
                    }
                    $val['IN_TRX_PRICE'] = ibcmul($val['TRX_PRICE'], $obj['EXCHANGE_RATE'], $precision,true);
                    $trx_Val = ibcmul($val['IN_TRX_PRICE'],$val['QUANTITY'],  $precision,true);
                    $val['IN_TRX_VALUE'] = iround($trx_Val, 2);
                    $outByLineNo[ $val['LINENO'] ] = count($entries);
                    if (isset($val['TRACKINGENTRIES'])) {
                        $this->cleanTrackingEntries($val['TRACKINGENTRIES'], $paths, true);
                    } else if ((count($paths) == 2) && ($paths[0] == 'BINID')) { // so [1] would be TO_BINID
                        // this is a bin-only item and with no bin....
                        $val['TRACKINGENTRIES'] = [];
                        $val['TRACKINGENTRIES'][] = ['BINID' => $this->noBinIdHuman]; // what a hack!
                    }
                    $entries[] = $val;
                } else {
                    if (!$populatedIn) {
                        foreach ($dimFields as $field) {
                            $obj['IN_' . $field['path']] = $val[$field['path']];
                        }
                        $obj['IN_LOCATIONID'] = $val['LOCATIONID'];
                        $obj['IN_DEPARTMENTID'] = $val['DEPARTMENTID'];
                        $obj['IN_WAREHOUSEID'] = $val['WAREHOUSEID'];
                        $obj['IN_WAREHOUSENAME'] = $val['WAREHOUSENAME'];
                        $populatedIn = true;
                        $this->mergeCustomDimensionsToHeader($obj, $val['CUSTOMDIMENSIONS'], 'IN_');
                    }
                }
            }
        }

        // pass two: update the TO_BINID field in the tracking entries of the TO, or IN records.
        foreach ($obj['ENTRIES'] as $val) {
            if ($val['IN_OUT'] != 'O') {    // get the IN entries
                $lineNo = $val['LINENO'];   // line number should match between in and out
                if (isset($outByLineNo[$lineNo], $val['TRACKINGENTRIES'])) { // did we get an OUT for this line?  We should!
                    foreach ($val['TRACKINGENTRIES'] as $key => $track) {
                        if (isset($track['BINID'])) {   // are we tracking bins?
                            // the tracking entries should be in the same order;
                            // above we callously tossed aside the IN tracking entries; but!  We need the TO BINID
                            $entries[ $outByLineNo[$lineNo] ]['TRACKINGENTRIES'][$key]['TO_BINID'] = $track['BINID'];
                        }
                        $entries[ $outByLineNo[$lineNo] ]['TRACKINGENTRIES'][$key]['TRACK_QUANTITY'] = $track['QUANTITY'];
                    }
                }
            }
        }

        $obj['ENTRIES'] = $entries; // now we're in the format the UI wants
        $this->getTrackingTables($obj['TRANSFERSTATE'], $obj['ENTRIES'], $obj['OUT_WAREHOUSEID'], $obj['IN_WAREHOUSEID']);

        // logFL(var_export("transformBizObjectToView2" . $obj, true));
        return $ok;
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformViewObjectToBiz(&$obj)
    {
        $ok = parent::transformViewObjectToBiz($obj);
        $dimFields = $this->getDimensionsFields($params, 'OUT_');
        $entries = array();
        $paths = ['BINID', 'TO_BINID', 'SERIALNO', 'LOTNO', 'EXPIRATION'];

        foreach ( $obj['ENTRIES'] as $val) {

            if (empty($val['ITEMID'])) {
                continue;
            }

            $outEntries = $val;
            $inEntries = $val;
            foreach ($dimFields as $field) {
                $outEntries[$field['path']] = $obj['OUT_' . $field['path']];
                $inEntries[$field['path']] = $obj['IN_' . $field['path']];
            }

            $outEntries['LOCATIONID'] = $obj['OUT_LOCATIONID'];
            $outEntries['DEPARTMENTID'] = $obj['OUT_DEPARTMENTID'];
            $outEntries['WAREHOUSEID'] = $obj['OUT_WAREHOUSEID'];

            $inEntries['LOCATIONID'] = $obj['IN_LOCATIONID'];
            $inEntries['DEPARTMENTID'] = $obj['IN_DEPARTMENTID'];
            $inEntries['WAREHOUSEID'] = $obj['IN_WAREHOUSEID'];

            $outEntries['IN_OUT'] = 'O';
            $inEntries['IN_OUT'] = 'I';

            // sanitize drop down fields.  and,
            // on the TO, or IN side, set BINID from the TO_BINID
            if (isset($inEntries['TRACKINGENTRIES'])) {
                $this->cleanTrackingEntries( $inEntries['TRACKINGENTRIES'], $paths, false);
                foreach ($inEntries['TRACKINGENTRIES'] as $key=> $track) {
                    if (isset($track['TO_BINID'])) {
                        $inEntries['TRACKINGENTRIES'][$key]['BINID'] = $track['TO_BINID'];
                    }
                }
            }
            if (isset($outEntries['TRACKINGENTRIES'])) {
                $this->cleanTrackingEntries( $outEntries['TRACKINGENTRIES'], $paths, false);
            }

            $entries[] = $outEntries;
            $entries[] = $inEntries;
        }

        $obj['ENTRIES'] = $entries;

        return $ok;
    }


    /**
     *       Clean tracking entries by removing the -- descriptions ('Bin 7--My fun bin'), but also
     *  handle the case of 'NO ENTRY' (--No Binid--), which is a special flag for tracking to ignore
     *  a specific entry.  This allows us to transfer from old txns without tracking to the new formats.
     *
     * @param array     $trackingEntries    The tracking entries
     * @param string[]  $paths              The paths in the entry to pay attention to
     * @param bool      $cleanToDisplay     The flag to let this method know how to clean the trackingEntries (true for display, false for saving to disk)
     */
    private function cleanTrackingEntries( & $trackingEntries, $paths, $cleanToDisplay)
    {
        $advancedBins = BinManager::areAdvanedBinsOn();
        foreach ($trackingEntries as $key=> $track) {
            // just in case....
            if ($advancedBins) {
                unset($trackingEntries[$key]['AISLEID']);
                unset($trackingEntries[$key]['AISLEKEY']);
                unset($trackingEntries[$key]['ROWID']);
                unset($trackingEntries[$key]['ROWKEY']);
            }

            foreach ($paths as $path) {
                if ($cleanToDisplay && $path == 'BINID') {
                    //We are cleaning the trackingEntries for displaying on UI for BINID field
                    //
                    //We are processing the BINID field and will be displaying on UI so clean the markers
                    //we added below when passing through this method as we save to disk
                    if ($track[$path] == null ||
                        $track[$path] == $this->noBinIdHuman ||
                        $track[$path] == TrackingHandler::TRACK_EMPTY_FIELD) {
                        $trackingEntries[$key][$path] = $cleanToDisplay ? $this->noBinIdHuman : '';
                    }
                } else {
                    //We are cleaning the trackingEntries for saving to disk or display to disk with non-BINID fields
                    //
                    if (isset($track[$path]) && ($track[$path] != '')) {
                        if (strpos($track[$path], '--') !== false) {
                            $value = trim(explode('--', $track[$path])[0]);
                            if (($value == '') && ($path == 'BINID')) {
                                $value = TrackingHandler::TRACK_EMPTY_FIELD;    // signal to the tracking manager
                            }
                            $trackingEntries[$key][$path] = $value;
                        } else if (($path == 'BINID') && ($track[$path] == TrackingHandler::TRACK_EMPTY_FIELD)) {   // on return on error
                            $trackingEntries[$key][$path] = $this->noBinIdHuman;
                        }
                    } else if ($path == 'BINID') {
                        $trackingEntries[$key][$path] = $this->noBinIdHuman;
                    }
                }
            }
        }
    }


    /**
     * @param array $obj
     */
    protected function ProcessTrackingEntries(&$obj)
    {
        foreach ($obj['ENTRIES'] as $key => $lineEntry) {
            $trackEntries = array();

            foreach ($lineEntry['TRACKINGENTRIES'] as $tEntry) {
                $hasTrackData = trim(($tEntry['TRACK_QUANTITY'] ?? '') . ""); // force to be a string.
                if ($hasTrackData == '') {
                    continue;
                }
                $tEntry['QUANTITY'] = $tEntry['TRACK_QUANTITY'];
                $trackEntries[] = $tEntry;
            }
            if (count($trackEntries)) {
                unset($obj['ENTRIES'][$key]['TRACKINGENTRIES']);
                $obj['ENTRIES'][$key]['TRACKINGENTRIES'] = $trackEntries;
            }
        }
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForCreate(&$obj)
    {
        $this->ProcessTrackingEntries($obj);
        return parent::prepareObjectForCreate($obj);
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForSave(&$obj)
    {
        $this->ProcessTrackingEntries($obj);
        return parent::prepareObjectForSave($obj);
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForCopyNew(&$obj)
    {
        unset($obj['OUTDOCHDRKEY']);
        unset($obj['INDOCHDRKEY']);
        unset($obj['OUTDOCID']);
        unset($obj['INDOCID']);
        unset($obj['RECORDNO']);
        unset($obj['DOCNO']);

        // All intransit fields need to unset
        unset($obj['INTRANSITDOCHDRKEY']);
        unset($obj['INTRANSITDOCID']);
        unset($obj['TRANSFERSTATE']);
        unset($obj['OUTDATE']);
        unset($obj['INDATE']);
        $obj['TRANSACTIONDATE'] = GetCurrentDate();

        foreach ($obj['ENTRIES'] as &$entry) {
            unset($entry['RECORDNO']);
            unset($entry['DOCHDRKEY']);
            unset($entry['DOCENTRYKEY']);
            if ($entry['COSTMETHOD'] == 'F' || $entry['COSTMETHOD'] == 'L') {
                unset($entry['TRX_PRICE']);
                unset($entry['TRX_VALUE']);
            }
            unset($entry['TRACKINGENTRIES']);
        }
        unset($entry);

        return true;
    }

    /**
     * @return array
     */
    protected function collectItemData()
    {
        if (!empty($this->itemDetails)) {
            return $this->itemDetails;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;
        $obj =& Request::$r->GetCurrentObject();

        $jsonVals = array('__dummy' => null);

        if ($obj['ENTRIES']) {

            $itemidArray = [];

            foreach ($obj['ENTRIES'] as $entry) {

                if (!empty($entry['ITEMID'])) {

                    $itemId = $entry['ITEMID'];
                    $itemId = explode('--', $itemId)[0];
                    $itemidArray[] = $itemId;
                    $itemUOM = array();
                    foreach ($entry['ITEMUOM'] as $key => $val) {
                        $itemUOM[$key] = array_change_key_case($val);
                    }
                    $jsonVals[$itemId]['uomdetails'] = $itemUOM;
                }
            }

            if (!empty($itemidArray)) {
                $itemMgr = $gManagerFactory->getManager('item');

                $stmt = array();
                $stmt[0]
                    = "select icitem.itemid itemid, icitem.name name,icitem.taxable tax,icitem.productlinekey prodline,
                                stduom.unit as stdunit, stduom.convfactor as convfactor, standard_cost standardcost,
                                average_cost averagecost, numdec_std precision, uomgrp.name as uomgrpname, 
                                icitem.itemtype itemtype,icitem.hasstartenddates, icitem.termperiod,
                                icitem.totalperiods,icitem.computeforshortterm, icitem.cost_method, icitem.enablesno, 
                                icitem.enablebin, icitem.enablelot, icitem.enableexpiration
                from icitem, icuomgrp uomgrp, icuom stduom
                where  icitem.cny# = :1 and uomgrp.cny#(+)=icitem.cny# and uomgrp.record# (+) = icitem.uomgrpkey
                                and stduom.cny#(+)=uomgrp.cny#
                                and uomgrp.record# = stduom.grpkey (+) 
                                and stduom.record# (+) = uomgrp.invdefunitkey";

                $stmt[1] = GetMyCompany();
                $stmt = PrepINClauseStmt($stmt, $itemidArray, " and icitem.itemid ");

                $res = QueryResult($stmt);
                $jsitemCnt = count($res);

                $itemWhseMgr = $gManagerFactory->getManager('itemwarehouseinfo');

                $params = array(
                    'selects' => array('ITEMID', 'AVERAGE_COST'),
                    'filters' => array(
                        array(
                            array('ITEMID', 'IN', $itemidArray),
                            array('WAREHOUSEID', '=', $obj['OUT_WAREHOUSEID']),
                        )
                    ),
                );

                $avgres = $itemWhseMgr->GetList($params);
                $averageCost = array();
                foreach ($avgres as $r) {
                    $averageCost[$r['ITEMID']] = $r['AVERAGE_COST'];
                }

                for ($i = 0; $i < $jsitemCnt; $i++) {
                    $thisItem = $res[$i]['ITEMID'];
                    foreach ($res[$i] as $key => $value) {
                        if ($key == 'AVERAGECOST' && $res[$i]['COST_METHOD'] == 'A') {
                            $value = $averageCost[$thisItem];
                        }

                        $jsonVals[$thisItem][strtolower($key)] = $value;
                    }

                    /** @noinspection PhpUndefinedVariableInspection */
                    $jsonVals[$thisItem]['isserialized'] = $itemMgr->IsItemSerialized($thisItem, true, $res[$i]);
                }
                $this->itemDetails = $jsonVals;
            }
        }

        return $jsonVals;
    }


    /**
     *      Get the tracking informatin for this line, needed by ictransfer.js
     *
     * @param array  $transferState      The state of this WH transfer such as 'Draft', 'In transit', 'Posted'
     * @param array  $entries            The entry lines
     * @param string $fromWarehouse      The from-warehouse to look up
     * @param string $toWarehouse        The to-warehouse to look up
     *
     */
    private function getTrackingTables($transferState, &$entries, $fromWarehouse, $toWarehouse)
    {
        if (($fromWarehouse == '') || ($toWarehouse == '')) {
            return;
        }
        $itemTrackingArray = [];

        // We use the existing tracking data to ADD to the current tracking data on a non-new entry.
        // for example, suppose you post a transaction with 10 hammers.  When you EDIT the transaction,
        // and we find there are 3 hammers available, really, including THIS transaction, there are 13.
        if ($this->state != Editor_ShowNewState) {
            foreach ($entries as $key => $entry) {
                if (!empty($entry['ITEMID'])) {
                    $itemId = $entry['ITEMID'];
                    $itemId = explode('--', $itemId)[0];
                    if (isset($entry['TRACKINGENTRIES'])) {
                        if (isset($itemTrackingArray[$itemId])) {
                            // numeric keys in the traking entries means array_merge is really array_append....
                            $itemTrackingArray[$itemId] = array_merge($itemTrackingArray[$itemId], $entry['TRACKINGENTRIES']);
                        } else {
                            $itemTrackingArray[$itemId] = $entry['TRACKINGENTRIES'];  // first time
                        }

                        // is there a tracking quantity already?  Maybe in Quantity?
                        if ( ! isset($entry['TRACK_QUANTITY']) || ($entry['TRACK_QUANTITY'] == '')) {
                            $entries[$key]['TRACK_QUANTITY'] = $entry['QUANTITY'] ?? '';
                        }
                    }
                }
            }
        }

        $itemData = $this->collectItemData();
        $itemMgr  = Globals::$g->gManagerFactory->getManager('item');

        // ok, now, in pass two, we fetch available for each row
        foreach ($entries as $key => $entry) {
            if (!empty($entry['ITEMID'])) {
                $itemId = $entry['ITEMID'];
                $itemId = explode('--', $itemId)[0];
                $rec = $itemData[$itemId] ?? [];

                if (!empty($rec)) {
                    //Need to copy to since collectItemData above issue a SQL query which returns raw data with lowercase vars
                    $rec['ENABLEBIN'] = $rec['enablebin'];
                    $rec['ENABLESNO'] = $rec['enablesno'];
                    $rec['ENABLELOT'] = $rec['enablelot'];
                    $rec['ENABLEEXPIRATION'] = $rec['enableexpiration'];

                    //If this transfer is a draft, we don't need to account it for the qty available
                    $existingEntries = [];
                    if ($transferState !== 'Draft') {
                        $existingEntries = $itemTrackingArray[$itemId] ?? [];
                    }
                    $entries[$key]['TRACKINGTABLE'] = $itemMgr->fetchSnLotExpirationInternal($itemId,
                                                            $fromWarehouse, '', $rec,
                                                            false, $existingEntries);
                }
            }
        }
    }


    /**
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

        if ($path == 'TRACKINGENTRIES') {
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
     * @param array $obj
     * @param string $entryCustomDimesionValue
     * @param string $prefix
     *
     * @return bool
     */
    private function mergeCustomDimensionsToHeader(&$obj, $entryCustomDimesionValue, $prefix)
    {
        $customDimensionEntry = [];
        if ( !util_isPlatformDisabled() && IADimensions::isCustomDimensionsEnabled() ) {
            $customDimensionEntry["CUSTOMDIMENSIONS"] = $entryCustomDimesionValue;
            IADimensions::explodeCustomDimensionString($customDimensionEntry);
            unset($customDimensionEntry["CUSTOMDIMENSIONS"]);
        }

        if (count($customDimensionEntry) > 0) {
            foreach ( $customDimensionEntry as $custFieldKey => $custField){
                // if we don't set the _disp key then transfer IN/OUT dimensions shows null for custom dimesnsion fields
                $obj[$prefix.$custFieldKey] = $custField;
                $data = Pt_DataObjectManager::getById2($obj[$prefix.$custFieldKey]);
                $obj[$prefix.$custFieldKey. '_disp'] = (string)$data;

                // Clearing the corrupted values
                unset($obj[$prefix.'OUT_'.$custFieldKey]);
                unset($obj[$prefix.'IN_'.$custFieldKey]);
            }
        }

        return true;
    }


    /**
     *
     */
    protected function mediateDataAndMetadata_History()
    {
        $view = $this->getView();

        $matches = array();
        $view->findComponents(array('id' => 'historyPage'), null, $matches);
        $historyTab = null;
        if ( $matches ) {
            $historyTab = $matches[0];
        }

        if ( $this->state == 'shownew' ) {
            $historyTab->parent->removeChild($historyTab);
            return;
        }

        $historyViewArr = array();
        $view->findComponents(array('path' => 'HISTORY'), EditorComponentFactory::TYPE_GRID, $historyViewArr);
        $historyView = $historyViewArr[0];

        $docidFields = array();
        $historyView->findComponents(array('path' => 'DOCUMENTID'), EditorComponentFactory::TYPE_FIELD, $docidFields);

        $docStates = array();
        $historyView->findComponents(array('path' => 'DOCSTATE'), EditorComponentFactory::TYPE_FIELD, $docStates);

        $auWhenCreated = array();
        $view->findComponents(array('path' => 'AUWHENCREATED'), EditorComponentFactory::TYPE_FIELD, $auWhenCreated);
        foreach ( $auWhenCreated as $whenCreated ) {
            $whenCreated->setProperty('hidden', false);
            $whenCreated->setProperty('fullname', 'IA.CREATED_DATE');
        }

        foreach ( $docidFields as $docidField ) {
            $docidField->setProperty('onclick', "LaunchHistoryLink(this);");
        }

        $docConfigFlds = array();
        $historyView->findComponents(array('path' => 'DOCCONFIG'), EditorComponentFactory::TYPE_FIELD, $docConfigFlds);
        foreach ( $docConfigFlds as $docConfigFld ) {
            $docConfigFld->setProperty('displayValue', I18N::getSingleToken('IA.DEFINITION'));
            $docConfigFld->setProperty('onclick', "LaunchDefinitionLink(this);");
        }

        //Hiding fields Created By and Modified By while creating transaction
        if($this->state == $this->kShowNewState) {
            $hidefields = array();
            $view->findComponents(array('path' => 'USERID'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $view->findComponents(array('path' => 'CREATEDUSERID'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $view->findComponents(array('path' => 'PRINTEDUSERID'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            foreach ( $hidefields as $hidefield ) {
                $hidefield->setProperty('hidden', true);
            }
        }
    }

    /**
     * This function is executed when a create action is done
     *
     * @param array   &$_params the metadata
     * @param array   &$obj     the data
     * @param bool $ok       false if error else true
     *
     * @return bool  false if error else true
     */
    protected function innerProcessCreateAction(&$_params, &$obj, $ok)
    {
        $ok = parent::innerProcessCreateAction($_params, $obj, $ok);

        if ( $ok ) {
            // If it is save and new we will clear the object
            $after = Request::$r->after;
            if ( $after == 1 ) {
                $obj = array();
                if ( $this->postAndNew ) {
                    // Since we now redirect for post and new, we must put these re-populate fields into the redirect url
                    $this->postAndNewPopData = $obj;
                }
                Request::$r->SetCurrentObject($obj);
            }
        }

        return $ok;
    }

    /**
     * Return the confirmation message for create action. We may want to extend this function later
     * and make it handle all the other confirmation message instead of hardcode them
     *
     * @param string $entityDesc the object name
     * @param array  $obj        the data
     *
     * @return string the confirmation message
     */
    protected function getConfirmationMsg($entityDesc, $obj)
    {
        $confirmation = '';
        $transferId = $obj['DOCNO'];

        if (isset($transferId) && $transferId != '') {
            $confirmation = sprintf(_('Warehouse Transfer %1$s was created successfully'), $transferId);
        }

        return $confirmation;
    }

    protected function InitConstants()
    {
        parent::InitConstants();
        $this->kActionHandlers['transferin'] = [
            'handler' => 'ProcessSaveAction',
            'states' => array($this->kShowEditState),
            'csrf'    => true,
            ];
        $this->kActionHandlers['transferout'] = [
            'handler' => 'ProcessCreateAction',
            'states' => array(
                $this->kShowEditState,
                $this->kShowNewState,
            ),
        'csrf'    => true,
        ];
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.CANT_TRANSFER_BINTRACKED_ITEM_BECAUSE_NOBIN_DEFINED_FOR_TO_WAREHOUSE';
        $this->textTokens[] = 'IA.THERE_IS_NO_AVAILABLE_QTY_TO_TRANSFER_OUT_OF_FROM_WAREHOUSE_ON_LINENO';
        $this->textTokens[] = 'IA.THERE_IS_NO_AVAILABLE_QTY_TO_TRANSFER_OUT_OF_FROM_WAREHOUSE';
        $this->textTokens[] = 'IA.SELECT_A_TO_BIN_ON_LINENO';
        $this->textTokens[] = 'IA.SELECT_A_TO_BIN';
        $this->textTokens[] = 'IA.WAREHOUSE_TRANSFER_NO_LONGER_ALLOW_AILSE_ROW_FOR_A_BIN';
        $this->textTokens[] = 'IA.ENTER_ITEMID_AND_TRY_AGAIN';
        $this->textTokens[] = 'IA.ENTER_VALID_FIELD_NAME_AND_TRY_AGAIN';
        $this->textTokens[] = 'IA.VALUE_MUST_BE_POSITIVE';
        $this->textTokens[] = 'IA.ON_LINE_OF_ITEM_IS_NOT_A_NUMBER';
        $this->textTokens[] = 'IA.ON_LINE_IS_NOT_A_NUMBER';
        $this->textTokens[] = 'IA.ON_LINE_OF_ITEM_SELECT_FIELD_BEFORE_ENTERING_QTY';
        $this->textTokens[] = 'IA.ON_LINE_SELECT_FIELD_BEFORE_ENTERING_QTY';
        $this->textTokens[] = 'IA.ON_LINE_OF_ITEM_QTY_VALUE_EXCEEDS_QTY_AVAILABLE';
        $this->textTokens[] = 'IA.ON_LINE_QTY_VALUE_EXCEEDS_QTY_AVAILABLE';
        $this->textTokens[] = 'IA.ON_LINE_OF_ITEM_QTY_TOTAL_EXCEEDS_QTY_VALUE';
        $this->textTokens[] = 'IA.ON_LINE_QTY_TOTAL_EXCEEDS_QTY_VALUE';
        $this->textTokens[] = 'IA.ON_LINE_OF_ITEM_QTY_TOTAL_LESS_THAN_QTY_VALUE';
        $this->textTokens[] = 'IA.FROM_BIN';
        $this->textTokens[] = 'IA.TO_BIN';
        $this->textTokens[] = 'IA.SERIAL_NUMBER2';
        $this->textTokens[] = 'IA.LOT_NUMBER2';
        $this->textTokens[] = 'IA.EXPIRATION_DATE';
        $this->textTokens[] = 'IA.ENTER_IN_DATE_FOR_IMMEDIATE_TRANSFER';
        $this->textTokens[] = 'IA.ENTER_IN_ESTIMATED_DATE_FOR_TRANSIT_TRANSFER';
        $this->textTokens[] = 'IA.ENTER_IN_DATE_FOR_TRANSIT_TRANSFER';
        $this->textTokens[] = 'IA.ENTER_OUT_DATE_FOR_IMMEDIATE_TRANSFER';
        $this->textTokens[] = 'IA.ENTER_OUT_DATE_FOR_TRANSIT_TRANSFER';
        $this->textTokens[] = 'IA.INVALID_TRACKING_INFO_PROVIDED';
        $this->textTokens[] = 'IA.BIN';
        $this->textTokens[] = 'IA.LOT';
        $this->textTokens[] = 'IA.SERIAL';
        $this->textTokens[] = 'IA.EXPIRATION';
        $this->textTokens[] = 'IA.ENTER_FROM_AND_TO_WAREHOUSE';
        $this->textTokens[] = 'IA.ERROR_COLON';
        $this->textTokens[] = 'IA.DO_YOU_WISH_TO_SAVE_ANYWAY';
        $this->textTokens[] = 'IA.THERE_ARE_ITEMS_WITH_TRACKING_ENTRIES_ALREADY';
        $this->textTokens[] = TrackingHandler::NO_BIN_ID_TOKEN;
        return parent::getFormTokens();
    }

}
