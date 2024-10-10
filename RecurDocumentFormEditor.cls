<?php

/**
 * =============================================================================
 *
 * FILE:        RecurDocumentFormEditor.cls
 * AUTHOR:        Shreerajath Hebbar
 * DESCRIPTION:    Editor for the Purchasing transaction screens
 *
 * (C)2000,2010 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */
require_once "backend_dates.inc";
require_once "scm_util.inc";
require_once "MailaddressManager.cls";
define( "NONINV", 'Non-Inventory' );
define( "NONINV_SO", 'Non-Inventory (Sales only)' );

define( 'DIS_KIT', 'Disassemble Kits' );
define( 'BUILD_KIT', 'Build Kits' );

class RecurDocumentFormEditor extends DocumentFormEditor
{
    // private variables
    //override dept and loc based on template configuration


    /** @var  bool $hasStarted */
    var $hasStarted;

    /**
     * @var bool $docTypeSelectMode
     * Is to determine the creation page.
     */
    protected $docTypeSelectMode = true;

    /**
     * @var array $_params old data members from editor class
     */
    public $_paramsdata;
    
    /**
     * RecurDocument specific tokens
     * @var string[]
     */
    private $recurDocumentTokens = [
        'IA.USE_KIT_REVENUE_RULES',
        'IA.RECURRING_TITLE',
        'IA.SUGGESTED_BR_PRICE',
        'IA.EXTENDED_COST',
        'IA.RENAMED_WAREHOUSE',
        'IA.SUGGEST',
        'IA.YOUR_RECURRING_TEMPLATE'
    ];

    /**
     * RecurDocumentFormEditor constructor.
     *
     * @param array $_params
     */

    public function __construct($_params)
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->recurDocumentTokens);
        // Activated XSS encoding;
        // To exclude fields from encoding please add them to the member $xssEncodeExcludeFields
        $this->xssEncode = false;
        parent::__construct( $_params );
    }

    /**
     * @param string|string[] $_msg
     * @param array $obj
     */
    public function SetMessageWithObject($_msg, $obj)
    {
        if ($obj && $obj['DOCID']) {
            $this->message = I18N::getSingleToken(
                'IA.YOUR_RECURRING_TEMPLATE',
                [['name' => 'DOC_ID', 'value' => $obj['DOCID']]]
            );
        } else {
            parent::SetMessage( $_msg );
        }
    }

    /**
     * Adds outboxview and appymtview actions to ActionHandlers
     */
    protected function addApplyActions()
    {
        $this->kActionHandlers['apply'] = array('handler' => 'processCreateRecurringTransaction', 'states' => array($this->kShowNewState, $this->kInitState,));
    }

    /**
     * Process Outbox View handler
     */

    protected function processCreateRecurringTransaction()
    {
        $this->docTypeSelectMode = false;

    }

    /**
     * @param array $_params
     * @param array|false $obj
     *
     * @return bool
     */
    function retrieveObjectFromView(&$_params, &$obj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ok = true;
        parent::retrieveObjectFromView( $_params, $obj );
        //Get the object current screen or from transaction screen
        //when repeat action is done from document transaction screen
        $obj = Request::$r->GetCurrentObject();

        // For new editor we do not have the current object structure. The right way is to query the current document.
        if (!$obj || count( $obj['ENTRIES'] ) == 0) {
            $orgTrxID = Request::$r->_origTrxID;
            if ($orgTrxID) {
                //dieFL();
                $mod = Request::$r->_mod;
                $docMgr = $gManagerFactory->getManager( $mod . 'document', false, array('DOCTYPE' => $this->dt) );
                $obj = $docMgr->get( $orgTrxID );
            }
        }

        return $ok;
    }


    /**
     * Method to allow setup interaction with data or
     * display elements when mode is copy.
     *
     * @param array $obj
     * @return bool
     */
    function prepareObjectForCopyNew(&$obj)
    {
        $this->docTypeSelectMode = false;

        unset( $obj['RECORDNO'] );

        if (isset( $this->dt ) && $this->dt != '') {
            $docparmrec = $this->GetBaseDocPar();
            if ($docparmrec['ENABLEOVERRIDETAX'] != 'true') {
                for ($i = 0; $i < count( $obj['ENTRIES'] ); $i++) {
                    unset( $obj['ENTRIES'][$i]['OVERRIDETAX'] );
                }
            }
        }

        if (isset( $obj['DOCID'] ) && isset( $obj['DOCNO'] )) {
            $obj['SOURCEDOCUMENT'] = $obj['DOCID'] . '--' . $obj['DOCNO'];
        }

        // unsetting entries values.
        foreach ($obj['ENTRIES'] as $key => $val) {
            unset( $obj['ENTRIES'][$key]['RECORDNO'] );
            unset( $obj['ENTRIES'][$key]['DOCENTRYKEY'] );
        }
        //Need to set REPEATCOUNT while copying to mentain the same countwith original transaction template
        if (isset( $obj['REPEATCOUNT'] ) && isset( $obj['EXECCOUNT'] )) {
            $obj['REPEATCOUNT'] = $obj['REPEATCOUNT'] + $obj['EXECCOUNT'];
        }

        if (!isset( $obj['SCHEDULEDCONTACTEMAIL'] ) || $obj['SCHEDULEDCONTACTEMAIL'] == '') {
            $obj['SCHEDULEDCONTACTEMAIL'] = '';
        }

        // unsetting schedule values.
        $obj['EXECCOUNT'] = '';
        $obj['DISPLAYNEXTEXECDATE'] = '';
        $obj['NEXTEXECDATE'] = '';
        $obj['LASTEXECDATE'] = '';
        unset( $obj['SCHOPKEY'] );
        unset( $obj['DOCHDRNO'] );
        $ok = parent::prepareObjectForCopyNew( $obj );
        return $ok;
    }

    // As of now commenting this we may need to use this in future
    /**
     * Method to allow setup interaction with data or
     * display elements when state is shownew.
     *
     * @param array $_params
     *
     * @return bool
     */
    /*function ProcessEditNewAction(&$_params)
    {
        $this->docTypeSelectMode = false;
        $ok = parent::ProcessEditNewAction($_params);

        return $ok;
    }*/

    /**
     * @access protected
     */
    protected function InitConstants()
    {
        parent::InitConstants();
        $this->addApplyActions();
        $this->kActionHandlers[$this->kDeriveDocumentAction] = array('handler' => 'ProcessDeriveDocumentAction', 'states' => array($this->kShowNewState, $this->kShowEditState, $this->kShowViewState));
        $this->kActionHandlers[$this->kFetchForNewAction] = array('handler' => 'ProcessEditNewAction', 'states' => array($this->kInitState, $this->kShowNewState));

        $this->kActionHandlers[$this->kFetchForEditAction] = array('handler' => 'ProcessEditAction', 'states' => array($this->kInitState, $this->kShowViewState, $this->kShowEditState));

        $this->kActionHandlers[$this->kSaveAction] = array('handler' => 'ProcessSaveAction', 'states' => array($this->kShowEditState, $this->kShowViewState, $this->kEditWarningState), 'csrf' => true,);
        $this->kActionHandlers['fetchdefaultrevrectemplate'] = array('handler' => 'fetchDefaultRevRecTemplate', 'states' => array($this->kInitState));
        $this->documentInitConstants();
    }

    function documentInitConstants()
    {

        $this->mod = $this->getRequestModule();
        $this->dt = Request::$r->_dt;
        $this->do = Request::$r->_do;
        $this->ismcpEnabled = IsMCPEnabled( $this->mod );
        $this->cny = GetMyCompany();
        $this->atlas = IsMCMESubscribed();
        $this->hasInventoryItems = HasInventoryItem();

        // This is particularly added for the error on goback
        if (isset( Request::$r->_docTypeSelectMode )) {
            $this->docTypeSelectMode = false;
        }


        // When coming from Map doctype will NOT be set,
        // pick the first doctype for the app
        if (!$this->dt && $this->do == 'create') {
            $this->_doctypeeditable = true;

            $cat = Request::$r->_cat;

            import( 'DocumentManager' );
            if(CRESetupManager::isCREInstalled()){
                $docs = GetNonCCODocumentParams($this->mod, $cat, true);
            }else{
                $docs = GetDocumentParams($this->mod, $cat, true);
            }

            if (count( $docs ) > 0) {
                $this->dt = $docs[0];

                if (isset( $this->dt ) && $this->dt != '') {
                    Request::$r->_dt = $this->dt;
                }
            }
        }

        if (!isset( $this->dt ) || $this->dt == '') {
            $docid = Request::$r->_r;
            if ($docid != '') {
                $this->dt = GetRecurDocumentType( $docid );
                if ($this->dt != '') {
                    Request::$r->_dt = $this->dt;
                }
            }
        }
        if (isset( $this->dt ) && $this->dt != '') {
            $docparmrec = $this->GetBaseDocPar();
            $recordno = $docparmrec['RECORDNO'];
            $this->affectsOnHandQty = IsDocumentAffectsOnHandQty( $recordno );
            $this->_isCustVendRequired = IsCustVendRequired( $docparmrec );
        } else {

            //  If not in build context.
            if (!defined( 'INTACCTCONTEXT' )) {
                //  Portable URLs can land here if the user doesn't have access to this object.
                $gErr = Globals::$g->gErr;

                $gErr->addIAError( 'INV-0219', __FILE__ . ":" . __LINE__, "You do not have access to this record.", [] );
                include 'popuperror.phtml';
                exit( 0 );
            }
        }

        $this->isAdvancedSetup = IsAdvancedConfiguration();

    }

    /**
     * Get the list of buttons for the screen
     *
     * @param string $state current state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        switch ($state) {
            case Template_CreateWarningState:
            case Editor_ShowNewState:
                $this->createNewButtons( $values );
                break;
            case Template_EditWarningState:
            case Editor_ShowEditState:
                if ($this->CanSave()) {
                    $this->setButtonDetails( $values, Editor_SaveBtnID, 'dobutton', $this->getLabelForSaveButton(), 'save' );
                }
                if (array_key_exists( 'submit', $this->kActionHandlers ) && $this->CanSubmit()) {
                    $this->setButtonDetails( $values, Editor_SubmitBtnID, 'submitbutton', 'IA.SUBMIT', 'submit' );
                }
                if ($this->CanDuplicate()) {
                    $this->createMoreActionEntry( $values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'window.editor.prepareForDuplicate()', true, true );
                }

                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton( $values );
                }
                // removed Not Needd for recurring Template
                /*if( $this->CanPrint() ) {
                    $this->setButtonDetails($values, 'saveandprintbuttid', 'deliverbutton', _('Print to...'), 'deliver', false, "showDeliverPageNew(true, data)", false);
                }*/
                $this->setButtonDetails( $values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false );
                break;
            case Editor_ShowViewState:
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton( $values );
                }
                //removed Not Needd for recurring Template
                /*if( $this->CanPrint() ) {
                    $this->setButtonDetails($values, 'saveandprintbuttid', 'deliverbutton', _('Print to...'), 'deliver', false, "showDeliverPageNew(true, data)", false);
                }*/

                if ($this->CanEdit()) {
                    $this->setButtonDetails($values, 'editbuttid', 'editbutton', 'IA.EDIT', 'edit', false, 'window.editor.doEdit()', false);
                }
                if ($this->CanDuplicate()) {
                    $this->createMoreActionEntry($values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }
                $this->setButtonDetails( $values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false );
                break;
        }

        $this->addHelpButton( $values );
        return $values;
    }

    /**
     * Creates create and cancel buttons for new form state.
     *
     * @param array $values
     *
     * @return array
     */
    protected function createNewButtons(&$values)
    {
        $view = $this->getView();


        $isCopyAction = $view->getProperty( 'copynew' );

        if ($this->CanSave() && (!$this->docTypeSelectMode || $isCopyAction || HasWarnings())) {

            $buttonsProperty = array('IA.SAVE' => array('action' => 'create', 'isSaveNew' => false, 'isDefault' => true, 'id' => Editor_SaveBtnID, 'jsCode' => "beforeSubmitJS();"), 'IA.SAVE_AND_NEW' => array('action' => 'create', 'isSaveNew' => true, 'isDefault' => false, 'id' => Editor_SaveAndNewBtnID),);
            $this->createSplitButtonEntry( $values, $buttonsProperty );
        }
        $this->setButtonDetails( $values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false );
        $this->addHelpButton( $values );
        return $values;
    }

    /**
     * @param array $buttons
     * @param array $buttonsProperty
     */
    protected function createSplitButtonEntry(&$buttons, $buttonsProperty)
    {
        $actions = array();
        foreach ($buttonsProperty as $buttonkey => $buttonproperty) {
            //$action = array();

            $action = $this->createAction( $buttonproperty['id'], 'saveandnewbutton_' . $buttonproperty['id'], $buttonkey, $buttonproperty['action'], true, "beforeSubmitJS()" );

            if (isset( $buttonproperty['isSaveNew'] ) && $buttonproperty['isSaveNew'] == true) {
                $action = $this->createAction( $buttonproperty['id'], 'saveandnewbutton_' . $buttonproperty['id'], $buttonkey, $buttonproperty['action'], true, "beforeSubmitJS()", true, false, array('after' => 1) );
            }
            if (isset( $buttonproperty['isDefault'] ) && $buttonproperty['isDefault'] == true) {
                $action['default'] = true;
            }
            $actions[] = $action;
        }
        $this->createSplitButton( $buttons, $actions );
    }

    /**
     * @param string[] $_params
     *
     * @throws Exception
     */
    protected function fetchDefaultRevRecTemplate(/** @noinspection PhpUnusedParameterInspection */ &$_params)
    {
        $itemlabel = Request::$r->itemlabel;

        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr = $gManagerFactory->getManager( 'item' );
        $itemglgrpMgr = $gManagerFactory->getManager( 'itemglgroup' );

        list( $ID ) = explode( '--', $itemlabel );
        $selects = array('ITEMTYPE', 'REVPOSTING', 'GLGROUP');
        $querySpec = array('selects' => $selects, 'filters' => array(array(array('ITEMID', '=', $ID),)),);
        $itemObj = $itemMgr->GetList( $querySpec )[0];

        if (empty( $itemObj )) {

            // In the unlikely event that the Get failed, let's try a more lenient search (see ticket 19886) which also matches the logic in ItemManager::FetchItem.
            // We then use the actual ITEMID to do the Get.  I know it is not very efficient, but ItemFetch doesn't return the necesesary fields, and again this is not a common scenario.
            $itemFetched = $itemMgr->ItemFetch( $ID );
            if (isset( $itemFetched[0]['ITEMID'] )) {
                $querySpec = array('selects' => $selects, 'filters' => array(array(array('ITEMID', '=', $itemFetched[0]['ITEMID']),)),);
                $itemObj = $itemMgr->GetList( $querySpec )[0];
            }
        }
        $itemGLGroup = $itemObj['GLGROUP'];
        if ($itemObj['ITEMTYPE'] == 'Kit' && $itemObj['REVPOSTING'] == 'Component Level') {
            echo(GT($this->textMap,'IA.USE_KIT_REVENUE_RULES'));
        } elseif (isset( $itemGLGroup ) && $itemGLGroup != '') {
            $querySpec = array('selects' => array('REVRECTEMPLID'), 'filters' => array(array(array('NAME', '=', $itemGLGroup),)),);
            $itemglgrpObj = $itemglgrpMgr->GetList( $querySpec )[0];
            echo($itemglgrpObj['REVRECTEMPLID']);
        }

        exit;
    }

    /**
     * @return string[]
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles = parent::getJavaScriptFileNames();
        $jsfiles[] = '../resources/js/recurdocument_form.js';
        return $jsfiles;
    }

    /**
     * @return string[]
     * @throws Exception
     */
    protected function getEditorGlobals()
    {
        $vars = parent::getEditorGlobals();
        $vars['fromRecurDocument'] = true;
        return $vars;
    }

    /**
     * @return RecurDocumentEntryManager
     */
    protected function getEntryManager()
    {
        return $this->GetManager('recurdocumententry');
    }

    /**
     *
     */
    protected function show()
    {
        // Go Back button must pass document type value
        global $gGoBackParams;
        $gGoBackParams['.docTypeSelectMode'] = false;
        parent::show();
    }

    /**
     * @param array $obj
     *
     * @return bool
     * @throws Exception
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        /*
         * We always need this docparmrec variable to generate subtotals and payment information
         * hence we cannot generate this with respect to other conditions
         */
        $params = &$this->_paramsdata;

        if (isset( $this->dt ) && $this->dt != '') {
            $obj['DOCID'] = $this->dt;
        }
        //Populate docpar values here
        $docidfields = array();
        self::findElements( $params, array('path' => 'DOCID'), EditorComponentFactory::TYPE_FIELD, $docidfields );
        if ($docidfields[0]) {
            $docidfields[0]['type']['validlabels'] = $docidfields[0]['validvalues'];
            $docidfields[0]['type']['validvalues'] = $docidfields[0]['validvalues'];
            $docidfields[0]['type']['_validivalues'] = $docidfields[0]['validvalues'];
        }

        if (!$this->docTypeSelectMode || $this->state === $this->kShowEditState || $this->state == $this->kShowViewState) {

            $obj['CREATERECURTRANS'] = true;
        }

        if ($obj['CREATERECURTRANS']) {

            $tokens = [
                [
                    'id' => 'IA.RECURRING_TITLE',
                    'placeHolders' => [
                        [   'name' => 'RECURRING_TITLE_CONTENT', 'value' => isl_htmlspecialchars($this->dt) ]
                    ]
                ]

            ];
            $result = I18N::getTokensForArray($tokens);
            $params['title'] = GT($result, 'IA.RECURRING_TITLE');

            self::findElements( $params, array('id' => 'docidSection'), EditorComponentFactory::TYPE_SECTION, $docidSectionView );
            $docidSectionView[0]['hidden'] = true;

            self::findElements( $params, array('id' => 'trxSection'), EditorComponentFactory::TYPE_SECTION, $trxSectionView );
            $trxSectionView[0]['hidden'] = false;

            self::findElements( $params, array('id' => 'schedulePage'), EditorComponentFactory::TYPE_PAGE, $schedulePage );
            $schedulePage[0]['hidden'] = false;

            if (isset( $this->dt ) && $this->dt != '') {
                $docparmrec = $this->GetBaseDocPar();
            }

            //Initialize VAT data, this need to happen before header and entries as those functions depend on the VAT data
            $this->mediateDataAndMetadata_VAT($obj);

            $this->mediateDataAndMetadata_Header( $obj );

            /** @noinspection PhpUndefinedVariableInspection */
            $this->mediateDataAndMetadata_Entries( $obj, $docparmrec );

            $this->mediateDataAndMetadata_Subtotals( $obj, $docparmrec );

            $this->mediateDataAndMetadata_Scheduler( $obj, $params );
        }
        return true;
    }

    /**
     * @param array $_params
     */
    protected function buildDynamicMetadata(&$_params)
    {
        // why does this function not call the
        // base class function
        // parent::buildDynamicMetadata($_params)?
        //  buildDynamicMetadata in DocumentFormEditor has some extra fields
        //  and logic which was not supported in RecurDocumentFormEditor

        $docMgr = Globals::$g->gManagerFactory->getManager( 'recurdocument' );

        $docid = Request::$r->_r;
        $action = Request::$r->{$this->kAction};
        $state = Request::$r->_state;

        $isDocEditable = true;
        if (isset( $docid ) && $docid != '') {
            $isDocEditable = $docMgr->canEdit( $docid );
        }

        if (($this->do == 'edit' || $this->do == 'view') && !($action == 'new' || $state == 'shownew')) {
            /** @noinspection PhpUndefinedVariableInspection */
            if (!$isDocEditable) {
                Request::$r->_do = 'view';
                $this->do = 'view';
                if (is_object( $this->entityMgr )) {
                    $this->getEntityMgr()->_canupdate = false;
                }
            }
        }

        if(CRESetupManager::isCREInstalled()){
            $getDocParams = "return GetNonCCODocumentParams('$this->mod', '', true);";
        }else{
            $getDocParams = "return GetDocumentParams('$this->mod', '', true);";
        }

        // Specifically added to filter the document based on the location and user restriction.
        $docidFlds = array();
        self::findElements( $_params, array('path' => 'DOCID'), EditorComponentFactory::TYPE_FIELD, $docidFlds );
        foreach ( $docidFlds as $i => $x) {
            $docidFlds[$i]['noedit']           = false;
            $docidFlds[$i]['readonly']         = false;
            $docidFlds[$i]['required']         = true;
            $docidFlds[$i]['hidden']           = false;
            $docidFlds[$i]['type']             = array (
                'type'                 => 'enum',
                'ptype'             => 'enum',
                'validvaluesfunc'    =>   $getDocParams ,
                'format'             => '/^[\w\s_\-]{0,30}$/',
                'norename' => true,
            );
        }

        $warehouseFlds = array();
        self::findElements( $_params, array('path' => 'WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FIELD, $warehouseFlds );
        if ($warehouseFlds[0]) {
            $warehouseFlds[0]['type']['ptype'] = 'ptr';
            $warehouseFlds[0]['type']['type'] = 'text';
            $warehouseFlds[0]['type']['entity'] = 'warehouse';
            $warehouseFlds[0]['type']['addlPickFields'] = array('NAME');
        }

        $unitFld = array();
        self::findElements( $_params, array('path' => 'UNIT'), EditorComponentFactory::TYPE_FIELD, $unitFld );
        if ($unitFld[0]) {
            $unitFldType = array('ptype' => 'webCombo', 'type' => 'enum', 'size' => '5',);
            $unitFld[0]['type'] = $unitFldType;
        }

        $priceFld = array();
        self::findElements( $_params, array('path' => 'PRICE'), EditorComponentFactory::TYPE_FIELD, $priceFld );
        if ($priceFld[0]) {
            $priceFld[0]['type']['type'] = 'decimal';
            $priceFld[0]['type']['ptype'] = 'currency';
            $priceFld[0]['type']['size'] = '16';
        }

        $trxpriceFld = array();
        self::findElements( $_params, array('path' => 'TRX_PRICE'), EditorComponentFactory::TYPE_FIELD, $trxpriceFld );
        if ($trxpriceFld[0]) {
            $trxpriceFld[0]['type']['type'] = 'decimal';
            $trxpriceFld[0]['type']['ptype'] = 'currency';
            $trxpriceFld[0]['type']['size'] = '16';
            $trxpriceFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $trxpriceFld[0]['nocalc'] = true;
        }

        $discMemoFld = array();
        self::findElements( $_params, array('path' => 'DISCOUNT_MEMO'), EditorComponentFactory::TYPE_FIELD, $discMemoFld );
        if ($discMemoFld[0]) {
            $discMemoFld[0]['type']['type'] = 'text';
            $discMemoFld[0]['type']['showpopup'] = true;
            $discMemoFld[0]['numofrows'] = 3;
        }

        $retailPrcFld = array();
        self::findElements( $_params, array('path' => 'RETAILPRICE'), EditorComponentFactory::TYPE_FIELD, $retailPrcFld );
        if ($retailPrcFld[0]) {
            $retailPrcFld[0]['type']['ptype'] = 'currency';
            $retailPrcFld[0]['type']['type'] = 'decimal';
            $retailPrcFld[0]['type']['size'] = '16';
            $retailPrcFld[0]['fullname'] = 'IA.SUGGESTED_BR_PRICE';
            $retailPrcFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $retailPrcFld[0]['nocalc'] = true;
        }

        $uipriceFld = array();
        self::findElements( $_params, array('path' => 'UIPRICE'), EditorComponentFactory::TYPE_FIELD, $uipriceFld );
        if ($uipriceFld[0]) {
            $uipriceFld[0]['type']['type'] = 'decimal';
            $uipriceFld[0]['type']['ptype'] = 'currency';
            $uipriceFld[0]['type']['size'] = '16';
            $uipriceFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $uipriceFld[0]['nocalc'] = true;
        }

        $extendedPrcFld = array();
        self::findElements( $_params, array('path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $extendedPrcFld );
        if ($extendedPrcFld[0]) {
            $extendedPrcFld[0]['type']['ptype'] = 'currency';
            $extendedPrcFld[0]['type']['type'] = 'decimal';
            $extendedPrcFld[0]['type']['size'] = '16';
            $extendedPrcFld[0]['fullname'] = $this->mod == 'inv' ? 'IA.EXTENDED_PRICE' : 'IA.EXTENDED_COST';
            $extendedPrcFld[0]['nocalc'] = true;
        }

        $trxextendedPrcFld = array();
        self::findElements( $_params, array('path' => 'TRX_VALUE'), EditorComponentFactory::TYPE_FIELD, $trxextendedPrcFld );
        if ($trxextendedPrcFld[0]) {
            $trxextendedPrcFld[0]['type']['ptype'] = 'currency';
            $trxextendedPrcFld[0]['type']['type'] = 'decimal';
            $trxextendedPrcFld[0]['type']['size'] = '16';
            $trxextendedPrcFld[0]['nocalc'] = true;
        }

        // Override the function call applyGridDefaults(FormEditor.cls) to applySCMGridDefaults(DocumentFormEditor.cls)  for button 'OK'
        $defgridbutton = array();
        self::findElements( $_params, array('name' => 'OK'), EditorComponentFactory::TYPE_FLOATING_PAGE, $defgridbutton );
        $defgridbutton[0]['events']['click'] = "applySCMGridDefaults('ENTRIES', 'ENTRIESDefaultsPage', 'ENTRIES_DEFAULTS_PAGE')";

        // Rename warehouse field label
        $defgridwarehouse = array();
        self::findElements( $_params, array('path' => 'HEADER_WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FLOATING_PAGE, $defgridwarehouse );
        if ($defgridwarehouse) {
            $defgridwarehouse[0]['fullname'] = 'IA.RENAMED_WAREHOUSE';
        }

        //TODO: Clean this up for GA Ends

        // add the change event to auto-populate the project information at the line level
        $matches = [];
        self::findElements( $_params, array('path' => 'PROJECTID'), EditorComponentFactory::TYPE_FIELD, $matches );
        if (isset( $matches[0] )) {
            $onchange = "onChangeProjectID(this);";
            $matches[0]['events']['change'] .= $onchange;
        }
        // add the change event to auto-populate the task information at the line level
        $matches = [];
        self::findElements( $_params, array('path' => 'TASKID'), EditorComponentFactory::TYPE_FIELD, $matches );
        if (isset( $matches[0] )) {
            $onchange = "onChangeTaskID(this);";
            $matches[0]['events']['change'] .= $onchange;
        }

        // the code below needs to include here because
        //  it is in the base class, but doesn't get called.
        $view = Request::$r->_do == 'view';
        if ($view)
        {
            // make the item and warehouse grid values clickable links
            // do only for view, edit needs to remain picker.
            $matches = [];
            self::findElements($_params, ['path' => 'ITEMID'], EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches[0])
            {
                $matches[0]['type']['ptype'] = 'href';
                $matches[0]['type']['type'] = 'href';
                $matches[0]['onclick'] = "ViewItem(this, 'item');";
            }

            $matches = [];
            self::findElements($_params, ['path' => 'WAREHOUSE.LOCATION_NO'], EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches[0])
            {
                $matches[0]['type']['ptype'] = 'href';
                $matches[0]['type']['type'] = 'href';
                $matches[0]['onclick'] = "ViewWarehouse(this, 'warehouse');";
            }
        }
        $this->_paramsdata = &$_params;

    }

    /**
     * @param array $obj
     *
     * @throws Exception
     */
    protected function mediateDataAndMetadata_Header(&$obj)
    {
        parent::mediateDataAndMetadata_Header( $obj );
        $trxSummarySection = array();
        // This is just extra code added for dispaying vendor information on trxSummary while viewing. only UI change
        self::findElements( $this->_paramsdata, array('id' => 'trxSummary'), EditorComponentFactory::TYPE_SECTION, $trxSummarySection );
        if ($this->state == $this->kShowViewState && $obj['CUSTVENDID']) {
            $custId = explode( '--', $obj['CUSTVENDID'] );
            $trxSummarySection[0]['title'] = isl_htmlspecialchars( $custId[1] ) . ' (' . isl_htmlspecialchars( $custId[0] ) . ')';
        }

        if ( !$obj['WHENCREATED'] && $this->state == $this->kShowEditState ) {
            $obj['WHENCREATED'] = GetCurrentDate();
        }
    }

    /**
     * @param string[]|string[][] $_params
     * @param array $objRec
     *
     * @return string[]|string[][]
     */
    protected function getGridDefaultsFields(&$_params, $objRec)
    {
        $fields = FormEditor::getGridDefaultsFields( $_params, $objRec );
        global $kSOid;
        GetModulePreferences( $kSOid, $prefs );

        if (isset( $this->dt ) && $this->dt != '') {
            $docparmrec = $this->GetBaseDocPar();
            $this->deptOverride = ($docparmrec['DEPTOVERRIDE'] == 'true');
            $this->locOverride = ($docparmrec['LOCOVERRIDE'] == 'true');
            if ($this->mod == 'so') {
                $enablerevrec = $docparmrec['ENABLEREVREC'] != 'None' ? true : false;
            }
        }

        if ($this->hasInventoryItems) {
            // For GA clean this up
            $warehouseType = array('ptype' => 'ptr', 'type' => 'text', 'entity' => 'warehouse', 'addlPickFields' => array('NAME'));
            $fields[] = array('path' => 'WAREHOUSE.LOCATION_NO', 'noview' => false, 'type' => $warehouseType);
        }

        //Show the TASK dimension if it is enabled. It is defaulted as hidden.  This is necessary because we are using
        //TASKID instead of TASKDIMKEY.  Also, this requires us to change the default 'dimdbkey' to match what is used for
        // the documententry applications.
        /*if (IADimensions::IsDimensionEnabled($this->mod, 'task')) {
            $fields[] = IADimensions::getDimensionObjectsInfo($this->mod)['task'];
            $fields[count($fields)-1]['dimdbkey'] = 'TASKID';
        }*/

        if ($this->deptOverride) {
            $fields[] = array('path' => 'DEPARTMENT', 'hidden' => false);
        }

        if ($this->locOverride) {
            $fields[] = array('path' => 'LOCATION', 'hidden' => false);
        }
        /** @noinspection PhpUndefinedVariableInspection */
        if ($this->mod == 'so' && ($prefs['ITEMSHAVESTARTENDDATE'] == 'T' || $enablerevrec)) {
            if (isset( $enablerevrec ) && $enablerevrec) {
                $fields[] = array('path' => 'REVRECTEMPLATE', 'hidden' => false);
            }
            $fields[] = array('path' => 'REVRECSTARTDATE', 'hidden' => false);
            $fields[] = array('path' => 'REVRECENDDATE', 'hidden' => false);
        }

        return $fields;
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Entries(&$obj, $docparmrec)
    {

        $view = $this->getView();

        $enabledNewVAT = $this->getEntityMgr()->isVATEnabled($obj);
        $docpar = $this->GetBaseDocPar();

        $entriesViewArr = array();
        /* @var EditorComponent[] $entriesViewArr */
        $view->findComponents( array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entriesViewArr );
        $entriesView = $entriesViewArr[0];

        if ($this->deptOverride) {
            $entriesView->findAndSetProperty( array('path' => 'DEPARTMENT'), array('hidden' => false) );
        }

        if ($this->locOverride) {
            $entriesView->findAndSetProperty( array('path' => 'LOCATION'), array('hidden' => false) );
        }

        /*
         * In View mode, hide the link used to populate the defaults in the line items.
         */
        if ($this->state == 'showview') {
            $entriesView->findComponents( array('id' => 'ITEMDEFAULTS'), EditorComponentFactory::TYPE_CAPTION, $itemDefaultsLink );

            if ($itemDefaultsLink && $itemDefaultsLink[0]) {
                $itemDefaultsLink[0]->parent->removeChild( $itemDefaultsLink[0] );
            }
        }

        //Apply the Item Picker defaults
        /* @var EditorComponent[] $itemIDs */
        $entriesView->findComponents( array('path' => 'ITEMID'), EditorComponentFactory::TYPE_FIELD, $itemIDs );
        $itemID = $itemIDs[0];
        if ($itemID) {
            $itemTypes = $this->getItemPickRestrictParams();
            if ($enabledNewVAT) {
                $events = $itemID->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $itemID->setProperty( 'events', $events );
                $itemID->setProperty( 'onchange', 'calculateLineTax(this);' );
            }
            if ($itemTypes && count( $itemTypes ) > 0) {
                $itemFldType = $itemID->getProperty( 'type' );

                if (!$itemFldType['restrict']) {
                    $itemFldType['restrict'] = array();
                }

                $itemFldType['restrict'][] = array('pickField' => 'ITEMTYPE', 'operand' => 'NOT IN', 'value' => $itemTypes,);

                $itemID->setProperty( 'type', $itemFldType );
            }
        }
        if ($enabledNewVAT) {
            /** @var EditorComponent[] $quantity */
            $entriesView->findComponents( array('path' => 'UIQTY'), EditorComponentFactory::TYPE_FIELD, $quantity );
            $quantity = $quantity[0];
            if ($quantity) {
                $events = $quantity->getProperty( 'events' );
                $events['change'] .= "calculateLineTax(this);";
                $quantity->setProperty( 'events', $events );
            }
            /** @var EditorComponent[] $unit */
            $entriesView->findComponents( array('path' => 'UNIT'), EditorComponentFactory::TYPE_FIELD, $unit );
            $unit = $unit[0];
            if ($unit) {
                $events = $unit->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $unit->setProperty( 'events', $events );
            }
            /** @var EditorComponent[] $uiPrice */
            $entriesView->findComponents( array('path' => 'UIPRICE'), EditorComponentFactory::TYPE_FIELD, $uiPrice );
            $uiPrice = $uiPrice[0];
            if ($uiPrice) {
                $events = $uiPrice->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $uiPrice->setProperty( 'events', $events );
            }
            /** @var EditorComponent[] $trxPrice */
            $entriesView->findComponents( array('path' => 'TRX_PRICE'), EditorComponentFactory::TYPE_FIELD, $trxPrice );
            $trxPrice = $trxPrice[0];
            if ($trxPrice) {
                $events = $trxPrice->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $trxPrice->setProperty( 'events', $events );
            }
            /** @var EditorComponent[] $wareHouseLocation */
            $entriesView->findComponents( array('path' => 'WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FIELD, $wareHouseLocation );
            $wareHouseLocation = $wareHouseLocation[0];
            if ($wareHouseLocation) {
                $events = $wareHouseLocation->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $wareHouseLocation->setProperty( 'events', $events );
            }

            /** @var EditorComponent[] $uiValue */
            $entriesView->findComponents( array('path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $uiValue );
            $uiValue = $uiValue[0];
            if ($uiValue) {
                $events = $uiValue->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $uiValue->setProperty( 'events', $events );
            }

            /** @var EditorComponent[] $trxValue */
            $entriesView->findComponents( array('path' => 'TRX_VALUE'), EditorComponentFactory::TYPE_FIELD, $trxValue );
            $trxValue = $trxValue[0];
            if ($trxValue) {
                $events = $trxValue->getProperty( 'events' );
                $events['change'] .= ";calculateLineTax(this);";
                $trxValue->setProperty( 'events', $events );
            }
        }

        if ($docpar['ENABLEOVERRIDETAX'] == 'true' && !$enabledNewVAT) {
            $entriesView->findAndSetProperty( array('path' => 'OVERRIDETAX'), array('hidden' => false) );
            /* @var EditorComponent[] $overridetaxflds */
            $entriesView->findComponents( array('path' => 'OVERRIDETAX'), EditorComponentFactory::TYPE_FIELD, $overridetaxflds );
            foreach ($overridetaxflds as $key => $overridetax) {
                if ($obj['ENTRIES'][$key]['TAXCAPABLE']) {
                    $overridetaxflds[$key]->setProperty( 'disabled', false );
                } else {
                    $overridetaxflds[$key]->setProperty( 'disabled', true );
                }
            }
        } else {
            //This code is added to maintain the existing behavior with old editor, if the ENABLEOVERRIDETAX is false
            // we will unset the OVERRIDETAX in all entries
            if ( $this->state == $this->kShowEditState ) {
                foreach ($obj['ENTRIES'] as &$entries) {
                    unset( $entries['OVERRIDETAX'] );
                }
            }
        }

        /* @var EditorComponent[] $warehouseFlds */
        $entriesView->findComponents( array('path' => 'WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FIELD, $warehouseFlds );
        $warehouseFld = $warehouseFlds[0];
        if ($warehouseFld && $this->hasInventoryItems) {
            if ($docpar['WAREHOUSESELMETHOD'] == 'Sort by Name') {

                //TODO For GA move this to ent
                if ($warehouseFld) {
                    $warehouseType = $warehouseFld->getProperty( 'type' );
                    $warehouseType['orders'] = 'NAME:a,LOCATIONID:a';
                    $warehouseFld->setProperty( 'type', $warehouseType );
                    $warehouseFld->setProperty( 'noedit', true );
                    $warehouseFld->setProperty( 'noview', true );
                }
            }
            if ($this->mod == 'inv') {
                $warehouseFld->setProperty( 'fullname','IA.RENAMED_WAREHOUSE');
            }
        } else {
            $warehouseFld->setProperty( 'hidden', true );
        }

        if ($this->state != 'showview') {
            $uiPriceAssists = array('customlink' => "SuggestPriceClick(this);", 'text' => GT($this->textMap,'IA.SUGGEST'), 'statusmsg' =>GT($this->textMap,'IA.SUGGEST_PRICE'),);
            $entriesView->findAndSetProperty( array('path' => 'UIPRICE'), array('assists' => $uiPriceAssists) );
        }


        //to get the view link in the line entry screen level
        $entriesView->findAndSetProperty( array('path' => 'ITEMID'), array('assist' => 'notfat') );

        if (!$this->isTaskDimensionEnabled) {
            $entriesView->findAndSetProperty( array('path' => 'TASKKEY'), array('hidden' => true) );
            $entriesView->findAndSetProperty( array('path' => 'TASKID'), array('hidden' => true) );
        }

        // hide the qty_converted field if non of the lines are converted
        if (!$obj['HASCONVERTEDLINES']) {
            $entriesView->findAndSetProperty( array('path' => 'QTY_CONVERTED'), array('hidden' => true) );
        }

        $showVatFieldsForAvaTaxEngine = $this->showVatFieldsForAvaTaxEngine( $obj, $docparmrec );

        if (!$showVatFieldsForAvaTaxEngine && !$enabledNewVAT) {
            $entriesView->findAndSetProperty( array('path' => 'PERCENTVAL'), array('hidden' => true) );
            $entriesView->findAndSetProperty( array('path' => 'TAXABSVAL'), array('hidden' => true) );
            $entriesView->findAndSetProperty( array('path' => 'LINETOTAL'), array('hidden' => true) );
        }

        if ($this->ismcpEnabled) {
            $entriesView->findAndSetProperty( array('path' => 'TRX_PRICE'), array('hidden' => false, 'fullname' => 'IA.TRANSACTION_PRICE', 'required' => true));
            $entriesView->findAndSetProperty( array('path' => 'TRX_VALUE'), array('hidden' => false, 'fullname' => 'IA.EXTENDED_PRICE'));
            if ($showVatFieldsForAvaTaxEngine) {
                $entriesView->findAndSetProperty( array('path' => 'TRX_LINETOTAL'), array('hidden' => false, 'fullname' => 'IA.TRANSACTION_GROSS_AMOUNT'));
            }
            if ($docpar['DISPLAY_BASECURRENCY'] != 'true') {
                $entriesView->findAndSetProperty( array('path' => 'UIPRICE'), array('hidden' => true) );
                $entriesView->findAndSetProperty( array('path' => 'UIVALUE'), array('hidden' => true) );
                if ($showVatFieldsForAvaTaxEngine) {
                    $entriesView->findAndSetProperty( array('path' => 'TAXABSVAL'), array('hidden' => true) );
                    $entriesView->findAndSetProperty( array('path' => 'LINETOTAL'), array('hidden' => true) );
                }
            } else {
                $entriesView->findAndSetProperty( array('path' => 'UIPRICE'), array('fullname' => 'IA.BASE_PRICE'));
                $entriesView->findAndSetProperty( array('path' => 'UIVALUE'), array('fullname' => 'IA.EXTENDED_BASE_PRICE'));
                if ($showVatFieldsForAvaTaxEngine) {
                    $entriesView->findAndSetProperty( array('path' => 'LINETOTAL'), array('fullname' => 'IA.GROSS_BASE_AMOUNT'));
                }
            }
        }
        if ($enabledNewVAT) {
            /** @var EditorComponent[] $buttons */
            $view->findComponents( null, EditorComponentFactory::TYPE_BUTTONS, $buttons );
            $ix = 0;
            while ($ix < count( $buttons )) {
                $buttonData = $buttons[$ix]->getProperty( 'button' );
                if (array_key_exists( 'id', $buttonData[0] ) && $buttonData[0]['id'] == 'subtotalCalculateButton') {
                    $buttonData[0]['events']['click'] = "calculateSubtotalsAjax(true);";
                    $buttons[$ix]->setProperty( 'button', $buttonData );
                    break;
                }
                $ix++;
            }
        }
        $valueFields = array('TRX_VALUE', 'UIVALUE');
        $priceFields = array('UIPRICE');
        $precision = $this->lookupAppPrecision();

        foreach ($obj['ENTRIES'] as &$entry) {
            foreach ($valueFields as $costFld) {
                if (!$entry[$costFld]) {
                    continue;
                }
                $entry[$costFld] = ibcmul( $entry[$costFld], '1', DEFAULT_INVPRECISION, false );
            }
            foreach ($priceFields as $costFld) {
                if (!$entry[$costFld]) {
                    continue;
                }
                $precision = ($entry['ITEM_PRECISION']) ?: $precision;
                $entry[$costFld] = ibcmul( $entry[$costFld], '1', $precision, false );
            }

            // fix is to not to carry trx_price to manager since the field name is ui_price in Non MCP
            if (!$this->ismcpEnabled) {
                $entry['TRX_PRICE'] = '';
            }

            unset( $entry );
        }

        /** @var RecurDocumentManager $docMngr */
        $docMngr = Globals::$g->gManagerFactory->getManager($this->mod . 'recurdocument');
        $isShiptoEnabled = $docMngr->isShipToLineItemEnable();
        $isLineShiptoEnabled = $isShiptoEnabled && isset($docparmrec) && $docparmrec['SHOW_TOTALS'] == 'true'
            && GetTaxEngine($this->mod,$obj['TAXSOLUTIONID']) == TaxSolutionManager::TAXMETHOD_I_ADVANCED;
        if (($obj['CUSTVENDID'] != '' || $this->state != 'shownew') && $isLineShiptoEnabled) {
            $entrySubtotalsArr = array();
            $entriesView->findComponents(array('path' => 'SUBTOTALSENTRY'), EditorComponentFactory::TYPE_GRID, $entrySubtotalsArr);
            $entrySubtotalView = $entrySubtotalsArr[0];
            $entrySubtotalView->setProperty('hidden', false);
            if ($entrySubtotalView) {
                if ($this->ismcpEnabled) {
                    $entrySubtotalView->findAndSetProperty(array('path' => 'TRX_ABSVAL'), array('hidden' => false));
                    $hide = ($docparmrec['DISPLAY_BASECURRENCY'] != 'true');
                    $entrySubtotalView->findAndSetProperty(array('path' => 'ABSVAL'), array('readonly' => true, 'fullname' => 'IA.BASE_VALUE', 'hidden' => $hide));
                    $entrySubtotalView->findAndSetProperty(array('path' => 'TOTAL'), array('fullname' => 'IA.BASE_TOTAL', 'hidden' => $hide));
                    $entrySubtotalView->findAndSetProperty(array('path' => 'TRX_TOTAL'), array('hidden' => false, 'readonly' => true));
                }
            }
        }

        $this->processCostLink( $entriesView );

        $this->processPickLink( $entriesView );

        // Show Conversion Type column when the Price Conversion feature is enabled.
        $priceConversionTypeEnabled = ($this->isPriceConversionEnabled());
        $entriesView->findAndSetProperty(['path' => 'CONVERSIONTYPE'], ['hidden' => (!$priceConversionTypeEnabled)]);
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Subtotals(&$obj, $docparmrec)
    {
        parent::mediateDataAndMetadata_Subtotals( $obj, $docparmrec );
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.TRANSACTION_PRICE';
        $this->textTokens[] = 'IA.EXTENDED_PRICE';
        $this->textTokens[] = 'IA.TRANSACTION_GROSS_AMOUNT';
        $this->textTokens[] = 'IA.BASE_PRICE';
        $this->textTokens[] = 'IA.EXTENDED_BASE_PRICE';
        $this->textTokens[] = 'IA.GROSS_BASE_AMOUNT';
        $this->textTokens[] = 'IA.BASE_VALUE';
        $this->textTokens[] = 'IA.BASE_TOTAL';
        $this->textTokens[] = 'IA.REPEAT_COUNT';
        return parent::getFormTokens();
    }

    /**
     * @param array $obj
     * @param array $params
     *
     * @throws Exception
     */
    protected function mediateDataAndMetadata_Scheduler(&$obj, $params)
    {
        //Schedule Page Defaulting while Create/Edit/View
        if (isset( $obj['REPEATCOUNT'] ) && $obj['REPEATCOUNT'] != '') {
            // We store temp values onload and use it on error go back.
            if  (!isset($obj['REPEATCOUNT_TEMP'])){
                $obj['REPEATCOUNT_TEMP'] = $obj['REPEATCOUNT'];
            }

            $obj['REPEATCOUNT_TEMP'] = (!(Util::php7eqEmptyStr($obj['REPEATCOUNT_TEMP'] ?? ''))? $obj['REPEATCOUNT_TEMP'] : 0);
            $obj['EXECCOUNT'] = (!(Util::php7eqEmptyStr($obj['EXECCOUNT'] ?? ''))? $obj['EXECCOUNT'] : 0);
            $obj['REPEATCOUNT'] = $obj['REPEATCOUNT_TEMP'] - $obj['EXECCOUNT'];

            //This is perticularly added to work for compositelabels, if it is integer 0 it is not calculating {{REPEATCOUNT}}
            // So we are making it as string 0 so that values is calculated properly.
            //This is temp fi, we need to look for other alternatives for this.
            if ($obj['REPEATCOUNT'] === 0) {
                $obj['REPEATCOUNT'] = '0';
            }

            $obj['ENDING'] = 'Number of occurrences';
        } else if (isset( $obj['ENDDATE'] ) && $obj['ENDDATE'] != '') {
            $obj['ENDING'] = 'End Date';
        } else {
            $obj['ENDING'] = 'Never';
        }
        self::findElements( $params, array('id' => 'Repeate'), EditorComponentFactory::TYPE_SECTION, $repeateSectionData );
        if (isset( $obj['REPEATBY'] ) && $obj['REPEATBY'] == 'None') {
            if ($this->state == 'showview') {
                $repeateSectionData[0]['hidden'] = true;
            } else {
                $disableFields = array('INTERVAL', 'REPEATCOUNT', 'ENDDATE', 'ENDING');
                foreach ($disableFields as $disableField) {
                    $fields = array();
                    self::findElements( $params, array('path' => $disableField), EditorComponentFactory::TYPE_FIELD, $fields );
                    $obj['INTERVAL'] = '';
                    $obj['REPEATCOUNT'] = '';
                    $fields[0]['disabled'] = true;
                }
            }
        } else {
            $repeateSectionData[0]['hidden'] = false;
        }

        if (isset( $obj['NEXTEXECDATE'] ) && $obj['NEXTEXECDATE'] != '') {
            // DISPLAYNEXTEXECDATE is diplay fields in header section of the document header. So populating it here
            $obj['DISPLAYNEXTEXECDATE'] = $obj['NEXTEXECDATE'];
        }
        // checking if its empty and forcing the $obj['EXECCOUNT'] value to float 165092
        $execCount = isset($obj['EXECCOUNT']) && is_numeric($obj['EXECCOUNT']) ? (float)$obj['EXECCOUNT'] : 0;

        if ($execCount > 0) {
            $this->hasStarted = true;
        } else {
            $this->hasStarted = false;
        }

        if ($this->hasStarted) {
            //adding change event customerChanged() for the CUSTVENDID if the payments is enbled
            self::findElements( $params, array('path' => 'STARTDATE'), EditorComponentFactory::TYPE_FIELD, $startDateParam );
            $startDateParam[0]['readonly'] = true;

            self::findElements( $params, array('path' => 'LASTEXECDATE'), EditorComponentFactory::TYPE_FIELD, $lastexecdateParam );
            $lastexecdateParam[0]['hidden'] = false;

            if ($this->state == $this->kShowEditState) {
                self::findElements( $params, array('id' => 'schedulePage'), EditorComponentFactory::TYPE_PAGE, $entriesFields );
                self::findElements( $entriesFields, array('path' => 'NEXTEXECDATE'), EditorComponentFactory::TYPE_FIELD, $nextExecParam );
                $nextExecParam[0]['readonly'] = false;
            }
        }
    }

    /**
     * @access private
     */
    protected function SetDoneParam()
    {
        $list_op = GetOperationId( $this->mod . '/lists/' . $this->mod . 'recurdocument' );
        $_done = Request::$r->_done;
        $_sess = Session::getKey();
        if (isl_strstr( $_done, "sforcekey" ) === false) {
            $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . util_encode($this->dt) . '&.sess=' . $_sess;
        }
    }

    /**
     * @param array $ownerobject
     *
     * @return string
     */

    function GetCustomOwnerObject($ownerobject)
    {
        $mod = Request::$r->_mod;

        $recurCustomOwnerObject = array($mod . 'recurdocument' => $mod . 'document', 'recurdocumententry' => $mod . 'documententry',);

        foreach ($recurCustomOwnerObject as $key => $value) {
            if ($ownerobject == $key) {
                $ownerobject = $value;
                break;
            }
        }

        return $ownerobject;
    }

    /**
     * @param string[]|string[][] $_params
     */
    protected function mergeMacroFields(&$_params)
    {

    }

    /**
     * @param string[]|string[][] $_params
     *
     * @return bool
     * @throws Exception
     */
    protected function mergeMacroHistory(&$_params)
    {
        return true;
    }

    /**
     * @param array $obj
     * @param bool $newDoc
     */
    protected function getSubtotals(&$obj, $newDoc = true)
    {
        //Following the same functionality in old editor to recalculate subtotal in view of Recur Document.
        //Which will fix the issue with convert by line which will calculate subtotal properly.
        // We will skip the $newDoc if it is from RecurDocumentFormEditor, so that default value true is taken
        // and recalculate the Subtotal.

        parent::getSubTotals( $obj );
    }
    /**
     * Retrieve form data from JSON
     *
     * @return array
     */
    /*private function getData()
    {
        $jsondata = Request::$r->_data;
        if (isset($jsondata) && $jsondata != '') {
            $data = Util_DataRecordFormatter::jsonToPhp($jsondata);
        } else {
            $data = null;
        }
        return $data;
    }*/
}
