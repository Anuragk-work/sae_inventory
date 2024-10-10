<?php

/**
 * =============================================================================
 *
 * PHP version 5
 *
 * @category    : __FormEditor_Class
 * @package     : __SCM
 * @author      : Unknown, Sudeendra Ramesh
 * @license     : (C)2000,2010 Intacct Corporation, All Rights Reserved
 * @link        :
 * @file:       : DocumentEditor.cls
 * @description : Editor for all documents in Supply Chain Management (SCM) modules
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
define("NONINV", 'Non-Inventory');
define("NONINV_SO", 'Non-Inventory (Sales only)');

define('DIS_KIT', 'Disassemble Kits');
define('BUILD_KIT', 'Build Kits');
import('ConversionManager.cls');

class DocumentFormEditor extends FormEditor
{

    // private variables
    //override dept and loc based on template configuration

    /** @var string $autoBatchFrequency */
    protected $autoBatchFrequency;


    /**
     * @var bool    $deptOverride
     */
    protected $deptOverride = false;

    /**
     * @var bool    $locOverride
     */
    protected $locOverride = false;

    /**
     * @var bool    $fromError
     */
    protected $fromError = false;

    /**
     * @var bool    $ismcpEnabled
     */
    protected $ismcpEnabled = false;

    /**
     * @var bool       $atlas
     */
    protected $atlas = false;

    /**
     * @var bool    $isAdvancedSetup
     */
    protected $isAdvancedSetup = false;

    /**
     * @var null|bool   $affectsOnHandQty
     */
    protected $affectsOnHandQty = null;

    /**
     * @var string  $mod
     */
    protected $mod = "";

    /**
     * @var string  $dt
     */
    protected $dt = "";

    /**
     * @var string  $do
     */
    protected $do = "";

    /**
     * @var null|int $cny
     */
    protected $cny = null;

    /**
     * @var string $docpar
     */
    protected $docpar = "";

    /**
     * @var string  $kDeriveDocumentAction
     */
    protected $kDeriveDocumentAction = 'derive';

    /**
     * @var bool    $hasInventoryItems
     */
    protected $hasInventoryItems = false;

    /**
     * @var string[]   $sourceDocsArr   array of doc ids
     */
    protected $sourceDocsArr = array();

    /**
     * @var string  $xsltemplateInfo
     */
    protected $xsltemplateid = "";

    /**
     * @var string[]   $xsltemplateInfo
     */
    protected $xsltemplateInfo = array();

    /**
     * @var string[]|string[][]   $printTemplateCache
     */
    protected $printTemplateCache = array();

    /**
     * @var bool    $_isCustVendRequired
     */
    protected $_isCustVendRequired = true;

    /**
     * @var string  $sfcrlimit
     */
    protected $sfcrlimit = "";

    /**
     * @var string  $sftotdue
     */
    protected $sftotdue = "";

    /**
     * @var bool    $macroForDocument
     */
    protected $macroForDocument = false;

    /**
     * @var bool    $macroForLines
     */
    protected $macroForLines = false;

    /**
     * @var array $macroNames
     */
    protected $macroNames = [];

    /**
     * @var bool $docCreatedThruMacro
     */
    protected $docCreatedThruMacro = false;

    /**
     * @var bool $showConvertCopyRepeat
     */
    protected $showConvertCopyRepeat = true;

    /**
     * @var bool $isReverseConversionAllowed
     */
    protected $isReverseConversionAllowed = false;

    /**
     * @var bool    $_doctypeeditable
     */
    protected   $_doctypeeditable = false;

    /**
     * @var bool $_stateEditable
     */
    protected   $_stateEditable = false;

    /**
     * @var bool    $priceFetchDisabled
     */
    protected   $priceFetchDisabled = false;

    /**
     * @var bool    $itemsHaveStartEndDate
     */
    protected   $itemsHaveStartEndDate = false;

    /**
     * @var string $XSL_Template_Type
     */
    protected   $XSL_Template_Type = '';

    /**
     * @var string $sfdcPricing  a string bool or bool string or whatever.  "true" or "false"
     */
    protected   $sfdcPricing = 'false';

    /**
     * @var string[]|string[][]   $locationArrayCache
     */
    protected $locationArrayCache= array();

    /**
     * @var bool $isTaskDimensionEnabled
     * Is Task enabled as a dimension in GL.
     */
    protected $isTaskDimensionEnabled = false;

    /**
     * @var string  $origin
     */
    protected $origin;

    /**
     * @var bool $isRetainageBeingUsed
     * Is retainage enabled in docpar?
     */
    protected $isRetainageBeingUsed = false;

    /**
     * @var bool $canEditConvertDoc
     */
    var $canEditConvertDoc = false;

    /**
     * @var bool $copyToAdapter
     */
    var $copyToAdapter = null;

    /** @var bool $onlySupplies */
    protected bool $onlySupplies      = false;    // true means ONLY show supply items

    /** @var bool $includeSupplies */
    protected bool $includeSupplies   = false;    // true means include supply items


    /**
     * @var string DRAFTCONTINUE
     */
    const DRAFT_CONTINUE = 'draftcontinue';

    /**
     * @var string DRAFT_SAVE
     */
    const DRAFT_SAVE = 'draftsave';

    /**
     * @var string DRAFT_CREATE
     */
    const DRAFT_CREATE = 'draftcreate';
    /**
     * Document specific tokens
     * @var string[]
     */
    private $documentTokens = [
        'IA.PARTIALLY_CONVERTED_BY_LINE',
        'IA.VENDOR',
        'IA.CUSTOMER',
        'IA.DONE',
        'IA.EDIT',
        'IA.SUBMIT',
        'IA.DRAFT',
        'IA.POST',
        'IA.PENDING',
        'IA.CLOSED',
        'IA.REPEAT',
        'IA.PRINT_PICK_LIST',
        'IA.CONVERT_TO',
        'IA.COPY_FROM',
        'IA.COPY_TO',
        'IA.NEW_CHANGE',
        'IA.PRINT_TO',
        'IA.EXTENDED_COST',
        'IA.EXTENDED_PRICE',
        'IA.WAREHOUSE',
        'IA.AMOUNT_RETAINED',
        'IA.SHIP_DATE',
        'IA.EXPIRATION_DATE',
        'IA.CUSTOMER_NAME',
        'IA.VENDOR_NAME',
        'IA.VIEW_RECURRING_SCHEDULE',
        'IA.SUGGEST',
        'IA.SUGGEST_PRICE',
        'IA.SUGGESTED_BR_PRICE',
        'IA.TEMPLATE',
        'IA.VIEW_DOCUMENT',
        'IA.VIEW_DOCUMENT_TEMPLATE',
        'IA.TRANSACTIONS',
        'IA.TRANSACTION_PRICE',
        'IA.TRANSACTION_GROSS_AMOUNT',
        'IA.PAY',
        'IA.POST_AND_NEW',
        'IA.POST_AND_PAY',
        'IA.POST_AND_PRINT',
        'IA.POST_AND_CONTINUE',
        'IA.SUBMIT_AND_PRINT',
        'IA.DRAFT_AND_CONTINUE',
        'IA.RECALC_DOCUMENT_TOTALS',
        'IA.AMOUNT_RETAINED',
        'IA.TAX',
        'IA.TRANSACTION_GROSS_AMOUNT',
        'IA.BASE_PRICE',
        'IA.EXTENDED_BASE_PRICE',
        'IA.BASE_TAX',
        'IA.GROSS_BASE_AMOUNT',
        'IA.BASE_VALUE',
        'IA.BASE_TOTAL',
        'IA.CREATED_DATE',
        'IA.LAST_CHANGE_LOG_NUMBER',
        'IA.CONVERT_FROM_AN_EXISTING_TRANSACTION',
        'IA.DEFINITION',
        "IA.BUY_TO_ORDER",
        "IA.DROP_SHIP",
        "IA.BILL_TO",
        "IA.SHIP_TO",
        "IA.CUSTOMER",
        "IA.SUBTOTAL",
        "IA.TOTAL",
        "IA.SALES_DISCOUNT",
        "IA.DISCOUNTED_TOTALS",
        "IA.PROMPT_PAY",
        "IA.CONTACT_TITLE_CONTACT",
        "IA.DOCUMENT_ID_DRAFT",
        "IA.SUBTOTALS_SECTION_SUBTOTAL_CONSTANT_LABEL",
        "IA.SUBTOTALS_SECTION_TOTAL_CONSTANT_LABEL",
        'IA.UK_PARTLY_EXEMPT',
        'IA.ITC',
        'IA.RITC',
        'IA.TRANSACTION',
        'IA.LINE_ITEMS',
        'IA.DETAILS',
        'IA.CT_CHANGE',
        'IA.REMOVE'
    ];

    /**
     * @param array $_params
     */
    public function __construct($_params)
    {
        $this->additionalTokens = array_merge($this->additionalTokens, $this->documentTokens);
        parent::__construct($_params);

        // CopyToAdapter is the base class with default implementations of functions, which do exactly the same
        // as was done before the CopyToAdapter was introduced.
        //
        // If you want "Copy to" functionality, where:
        // - source object is some object that is not a document (SO document or PO document)
        // - dest object is a document (SO document or PO document)
        // then you can create a class derived from CopyToAdapter, to provide specific behavior for your source object.
        // Then, in the constructor of SODocumentFormEditor or PODocumentFormEditor, instantiate that new class
        // and set the value of $this->copyToAdapter to that new class.
        $this->copyToAdapter = new CopyToAdapter();
    }

    protected function InitConstants()
    {
        parent::InitConstants();

        $this->kActionHandlers[$this->kDeriveDocumentAction]
            = array(
            'handler' => 'ProcessDeriveDocumentAction',
            'states' => array(
                $this->kShowNewState,
                $this->kShowEditState,
                $this->kShowViewState
            )
        );
        $this->kActionHandlers[$this->kFetchForNewAction]
            = array('handler' => 'ProcessEditNewAction',
                    'states' => array($this->kInitState,
                                      $this->kShowNewState));

        $this->kActionHandlers[$this->kFetchForEditAction]
            = array('handler' => 'ProcessEditAction',
                    'states' => array($this->kInitState,
                                      $this->kShowViewState,
                                      $this->kShowEditState)
        );

        $this->kActionHandlers[$this->kSaveAction]
            = array('handler' => 'ProcessSaveAction',
                    'states' => array($this->kShowEditState,
                                      $this->kShowViewState,
                                      $this->kEditWarningState),
                    'csrf' => true,
        );
        $this->kActionHandlers['fetchdefaultrevrectemplate']
            = array(
            'handler' => 'fetchDefaultRevRecTemplate',
            'states' => array($this->kInitState)
        );

        $this->kActionHandlers[self::DRAFT_CONTINUE] = [
            'handler' => 'ProcessDraftContinueAction',
            'states' => array(
                $this->kShowNewState,
                $this->kShowEditState,
                $this->kEditWarningState,
            ),
            'csrf' => true,
        ];

        $this->documentInitConstants();

        $this->isTaskDimensionEnabled =  IADimensions::IsDimensionEnabled('gl', 'task');


        parent::addSubmitAction();
    }

    /**
     * Description
     * @access public
     *
     * @return string mod, the requested module
     */
    public function getRequestModule()
    {
        $mod = Request::$r->_mod;
        if ( $mod == "pa" ) {
            $mod = "so";
        }
        return $mod;
    }

    /**
     * @param array   $tabNavigator
     * @param string  $tabName
     *
     * @return int
     */
    private function getTabId($tabNavigator, string $tabName)
    {
        $visibleIndex=0;
        $c = count($tabNavigator->children);
        for ( $i = 0; $i < $c; $i++ ) {
           if($tabNavigator->children[$i]->params["id"]==$tabName) {
               return $visibleIndex;
           }
            $hidden = $tabNavigator->children[$i]->params["hidden"];
            if (!(isset($hidden) && $hidden =="true")) {
                $visibleIndex++;
            }
        }
        return 0;
    }

    /**
     * @access protected
     */
    protected function documentInitConstants()
    {

        $this->mod = $this->getRequestModule();
        $this->dt = Request::$r->_dt;
        $this->do = Request::$r->_do;
        $this->ismcpEnabled = IsMCPEnabled($this->mod);
        $this->cny = GetMyCompany();
        $this->atlas = IsMCMESubscribed();
        $this->hasInventoryItems = HasInventoryItem();

        // origin should be set when in sales order view mode. If it's set assign it further to add in agrs of copy to or convert action.
        if(isset(Request::$r->_origin) && Request::$r->_origin != 'null'){
            $this->origin = Request::$r->_origin;
        }
        // When coming from Map doctype will NOT be set,
        // pick the first doctype for the app
        if ( !$this->dt && $this->do == 'create' ) {
            $this->_doctypeeditable = true;

            $cat = Request::$r->_cat;

            import('DocumentManager');
            $docs = GetDocumentParams($this->mod, $cat);

            if (!empty($docs)) {
                $this->dt = $docs[0];

                if ( isset($this->dt) && $this->dt != '' ) {
                    Request::$r->_dt = $this->dt;
                }
            }
        }

        if ( !isset($this->dt) || $this->dt == ''){
            // docid will be string always. to fix php 8.1 issue 165526
            $docid = (string)Request::$r->_r;
            if ( $docid != '' ) {
                $this->dt = GetDocumentType($docid);
                if ( $this->dt != '' ) {
                    Request::$r->_dt = $this->dt;
                }
            }
        }

        if ( isset($this->dt) && $this->dt != '' ) {

            $params = array(
                'selects' => array('DOCCLASS', 'UPDATES_GL', 'POSTTOGL','UPDATES_INV', 'ENABLE_RETAINAGE', 'DOCID','RECORDNO'),
                'filters' => array(
                    array(array('DOCID', '=', $this->dt))
                ),
            );
            $gManagerFactory = Globals::$g->gManagerFactory;
            $docParMgr = $gManagerFactory->getManager('documentparams');
            $docparmrec = $docParMgr->GetList($params)[0];

            $recordno = $docparmrec['RECORDNO'];
            $this->affectsOnHandQty = IsDocumentAffectsOnHandQty($recordno);
            $this->_isCustVendRequired = IsCustVendRequired($docparmrec);

            $this->isRetainageBeingUsed = false;
            if ( in_array($this->mod, array('so','pa','po')) && $this->getIsRetainageEnabled()) {
                if ($docparmrec['CATEGORY'] != 'Return' &&
                    ($docparmrec['ENABLE_RETAINAGE'] == 'T' || $docparmrec['ENABLE_RETAINAGE'] == 'true')
                ) {
                    $this->isRetainageBeingUsed = true;
                }
            }

        } else {

            //  If not in build context.
            if (!defined('INTACCTCONTEXT')) {
                //  Portable URLs can land here if the user doesn't have access to this object.
                $gErr = Globals::$g->gErr;

                $gErr->addIAError(
                    'INV-0016', __FILE__ . ":" . __LINE__,
                    "You do not have access to this record." , []
                );
                include 'popuperror.phtml';
                exit(0);
            }
        }

        $this->isAdvancedSetup = IsAdvancedConfiguration();
    }



    /**
     * @access private
     *
     * @param bool $getLatest
     *
     * @return array|false
     */
    public function GetBaseDocPar(/** @noinspection PhpUnusedParameterInspection */ $getLatest = false)
    {
        if ( !$this->dt || $this->dt == '' ) {
            $this->dt = Request::$r->_dt;
        }
        if ( $this->dt && (!isset($this->docpar) || $this->docpar == '') ) {
            /** @var DocumentParamsManager $docparMgr */
            $docparMgr = Globals::$g->gManagerFactory->getManager($this->mod . 'documentparams');
            $this->docpar = $docparMgr->GetBaseLatest($this->dt, true);
        }
        return $this->docpar;
    }


    /**
     *
     */
    protected function show()
    {
        // Go Back button must pass document type value
        global $gGoBackParams;
        $copy = Request::$r->copymode;
        $gGoBackParams['.dt'] = $this->dt;
        $gGoBackParams['.copymode'] = $copy;
        parent::show();
    }


    /*

      public function ShowPreListerEditorInfo() {
      // Does nothing allow to override
      global $gRequest;
      $msg = $this->GetMessage();
      if (!$msg) $msg = Request::$r->_msg;
      if ($msg) {
      ?>
      <center>
      <table border="0" cellpadding="1" cellspacing="0" width="70%" bgcolor="#999966">
      <tr>
      <td valign="top">

      <table border="0" cellpadding="4" cellspacing="0" width="100%" bgcolor="#FFFFCC">
      <tr>
      <td valign="middle" align="center">
      <font face="Verdana, Arial, Helvetica" size="2"><b><? echo $msg; ?></b></font>
      </td>
      </tr>
      </table>

      </td>
      </tr>
      </table>
      </center>
      <?
      $this->message='';
      }
      }

     * *
     */

    /**
     * @param string   $_msg
     * @param array    $obj
     */
    protected function SetMessageWithObject($_msg, $obj)
    {
        if ( $obj['DOCID'] ) {
            $tokens = [
                [
                    'id' => 'IA.DOCUMENT_CREATED_SUCCESSFULLY',
                    'placeHolders' => [
                        ['name' => 'DOCID', 'value' => $obj['DOCID']]
                    ]
                ]
            ];
            $text = getLocalizedTextWithThrow($tokens);
            $this->message = GT($text, 'IA.DOCUMENT_CREATED_SUCCESSFULLY');
        } else {
            parent::SetMessage($_msg);
        }
    }


    /**
     * @param string $state
     *
     * @return string[]
     * @throws Exception
     */
    public function getStandardButtons($state)
    {
        $buttons = [];
        switch ($state) {
            case Template_CreateWarningState:
            case Editor_ShowNewState:
                $this->createNewStateButtons($buttons);
                break;

            case Template_EditWarningState:
            case Editor_ShowEditState:
                $this->createEditStateButtons($buttons);
                break;

            case Editor_ShowViewState:
                $this->createViewStateButtons($buttons);
                break;
        }

        // For 'Build Kits' and 'Disassemble Kits' , dont show 'Convert To', 'Copy To' and 'Repeat' actions,
        // block txn creation for multi jurisdiction
        $this->getStandardButtonsForshowConvertCopyRepeat($buttons);

        return $buttons;
    }

    /**
     * @param array $values
     */
    protected function getStandardButtonsForshowConvertCopyRepeat(&$values)
    {
        $viewData = $this->getViewData();

        // For 'Build Kits' and 'Disassemble Kits' , dont show 'Convert To', 'Copy To' and 'Repeat' actions,
        // block txn creation for multi jurisdiction
        if (
            ($this->state != $this->kShowNewState
                && !in_array(
                    $this->dt, array(BUILD_KIT, DIS_KIT, ICTransferManager::OUTDOCTYPE, ICTransferManager::INDOCTYPE)
                )
                && $this->showConvertCopyRepeat)) {

            $recurOp = GetOperationId($this->mod . '/lists/' . $this->mod . 'recurdocument/edit');

            if (
                !in_array($viewData['STATE'], array(DocumentManager::DRAFT_STATE, DocumentManager::DECLINED_STATE))
                && $recurOp != '-1' && CheckAuthorization($recurOp, 1) && !$this->hideRepeatForChangeOrder($viewData)
                && !$this->hideRepeatForPCB($viewData)) {

                $args = array(
                    'recurOp' => $recurOp,
                    'dt' => $this->dt,
                    'mod' => $this->mod,
                );
                if (isset($this->mod) && $this->mod != 'inv') {
                    $this->createMoreActionEntry($values, 'repeat', 'repeat', 'IA.REPEAT', '', false, 'handleRepeat(data)', false, false, $args);
                }
            }

            if ($this->canPrintPickList()) {
                /** @noinspection PhpUndefinedVariableInspection */
                $this->createMoreActionEntry($values, 'hdrpicklist', 'hdrpicklist', 'IA.PRINT_PICK_LIST', '', false, 'HdrPickListReport()', false, false, $args);
            }


            $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
            $spi = $modArray[$this->mod];


            //if (!in_array($viewData['STATE'], array('Draft', 'Submitted', 'Partially Approved', 'Approved', 'Declined', 'In Progress', 'Closed', 'In Progress', 'Converted', 'Partially Converted'))) {

            // Show convert link only for pending/partially converted docs,
            // If sales document is linked to contract, do not show convert link
            $docMgr = Globals::$g->gManagerFactory->getManager('document');
            if (
                (in_array(
                        $viewData['STATE'], array(DocumentManager::PENDING_STATE, DocumentManager::PARTIALLY_CONVERTED_STATE)
                    ) || ($docMgr->isReverseConversionAllowed($this->mod) && $viewData['STATE'] == DocumentManager::CONVERTED_STATE))
                && $viewData['SALESCONTRACT'] != 'Y'
            ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $ddlist = $this->getRecallDocList($spi, $ddlist);

                $actions = array();

                if (is_array($ddlist)) {
                    foreach ($ddlist as $recallDocType) {
                        $args = array(
                            'dt' => $recallDocType,
                            'copymode' => 'Update',
                            'parentdt' => Request::$r->_parentdt,
                            'origin' => $this->origin,
                        );
                        $actions[] = $this->createAction($recallDocType, $recallDocType, $recallDocType, '', false,
                            'recallDocument(data)', false, false, $args);
                    }
                }
                $sConvertLink = true;

                if (!is_object($this->entityMgr)) {
                    $this->entityMgr = $this->GetManager($this->getEntity());
                }

                if (IsMultiEntityCompany() && GetContextLocation()) {
                    $sConvertLink = $this->getEntityMgr()->_entityownership ? true : false;
                }
                if ($sConvertLink) {
                    $this->createMoreActionsSubMenu($values, 'Convert', 'Convert', 'IA.CONVERT_TO', $actions);
                }
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $completeList = $this->getCompleteDocList($completeList);

            $copyActions = array();

            foreach ($completeList as $recallDocType) {
                $args = array(
                    'dt' => $recallDocType,
                    'copymode' => 'Copy',
                    'origin' => $this->origin,
                );
                $copyActions[] = $this->createAction($recallDocType, $recallDocType, $recallDocType, '', false, 'recallDocument(data)', false, false, $args);
            }

            $this->createMoreActionsSubMenu($values, 'Copy', 'Copy', 'IA.COPY_TO', $copyActions);

            /**
             * @var DocumentManager $documentManager
             */
            $documentManager = $this->getEntityMgr();

            $createOpID = GetOperationId($this->mod . '/activities/' . $this->getEntity() . '/create');
            $hasCreatePermission = CheckAuthorization($createOpID);
            if ($documentManager->canCreateChangeDocument($viewData) && $hasCreatePermission) {
                $changeDocList = $this->getChangeDocList();
                $changeActions = [];
                foreach ($changeDocList as $changeDoc) {
                    $args = array(
                        'dt' => $changeDoc,
                        'copymode' => 'Copy',
                        'origin' => $this->origin,
                        'createchange' => 'New',
                    );
                    $changeActions[] = $this->createAction($changeDoc, $changeDoc, $changeDoc, '', false, 'changeOrderDocumentHandler.newChangeDocument(data)', false, false, $args);
                }
                $this->createMoreActionsSubMenu($values, 'Newchangedoc', 'New change', 'IA.NEW_CHANGE', $changeActions);
            }
            //visible only for CCO and Reverse conversion enabled document

            $hasCreatePermission = CheckAuthorization($createOpID);
            if ($documentManager->canCreateChangeDocument($viewData) && $hasCreatePermission ||
                (!$documentManager->isValidDraftAndDeclinedState($viewData['STATE'])
                    && $documentManager->getDocChangeType($viewData) !== 'Change Order'
                    && $documentManager->isReverseConversionAllowed()
                )
            ) {
                $this->addRecalcChangeOrderFieldsAction($values, $viewData);
            }
        }
    }

    /**
     * Creates buttons for kShowNewState
     * @param array $values
     *
     * @return array
     */
    protected function createNewStateButtons(&$values)
    {
        if ($this->canPay()) {
            $this->setButtonDetails(
                $values,
                Editor_SubmitBtnID,
                'paybutton',
                'IA.POST_AND_PAY',
                'savepay',
                true,
                "translateSubtotalConstantLabels(); beforeSubmitJS();"
            );
        }

        if (array_key_exists('submit', $this->kActionHandlers) && $this->CanSubmit()) {

            $this->setButtonDetails(
                $values,
                Editor_SubmitBtnID,
                'submitbutton',
                'IA.SUBMIT',
                'submit',
                true, "translateSubtotalConstantLabels();"
            );
        } else {

            if ($this->CanSave()) {
                $this->setButtonDetails(
                    $values,
                    Editor_SaveBtnID,
                    'dobutton',
                    'IA.POST',
                    'create',
                    true,
                    "translateSubtotalConstantLabels(); beforeSubmitJS();"
                );
            }
        }
        $isDraftMode = $this->IsDraftMode();
        if ($isDraftMode) {

            $this->setButtonDetails(
                $values,
                Editor_SaveBtnID,
                'draftbutton',
                'IA.DRAFT',
                'draftcreate',
                true,
                "translateSubtotalConstantLabels(); draftDocument(this, 'draftcreate');",
            );
        }

        $this->setButtonDetails(
            $values,
            Editor_CancelBtnID,
            'cancelbutton',
            'IA.CANCEL',
            'cancel',
            false,
            "translateSubtotalConstantLabels();"
        );

        //createMoreActionEntry(&$buttons, $id, $name, $button, $action, $submitData = true, $jsCode = '', $serverAction = true, $disableValidation = false, $args = '')

        if (!$this->CanSubmit() && $this->CanSave()) {
            //$this->setButtonDetails($values, Editor_SaveBtnID, 'saveandnewbutton', 'Post & New', 'savecontinue');
            $this->createMoreActionEntry(
                $values,
                Editor_SaveAndNewBtnID,
                'saveandnewbutton',
                'IA.POST_AND_NEW',
                'create',
                true,
                "translateSubtotalConstantLabels(); beforeSubmitJS();",
                true,
                false,
                array('after' => 1)
            );
        }

        if ($this->showPostAndPrintButton()) {
            $saveAndPrintButtonLabel = (array_key_exists('submit', $this->kActionHandlers) && $this->CanSubmit()) ? 'IA.SUBMIT_AND_PRINT' : 'IA.POST_AND_PRINT';
            $this->createMoreActionEntry(
                $values,
                'saveandprintbuttonid',
                'saveandprintbutton',
                $saveAndPrintButtonLabel,
                'saveandprint',
                true,
                'translateSubtotalConstantLabels();',
                true,
                false,
                array('after' => 1)
            );
        }
        if ($isDraftMode) {
            $this->createMoreActionEntry(
                $values,
                Editor_SaveBtnID,
                'scontinuebutton',
                'IA.DRAFT_AND_CONTINUE',
                self::DRAFT_CONTINUE,
                true,
                "translateSubtotalConstantLabels(); draftDocument(this, '".self::DRAFT_CONTINUE."');"
            );
        }

        $this->createMoreActionEntry(
            $values,
            Editor_SaveBtnID,
            'copyfrombutton',
            'IA.COPY_FROM',
            'copyfrom',
            false,
            "translateSubtotalConstantLabels(); copyFromClicked();"
        );

        return $values;
    }


    /**
     * Creates buttons for kShowEditState
     * @param array $values
     */
    protected function createEditStateButtons(&$values)
    {
        if ($this->canPay()) {
            $this->setButtonDetails(
                $values,
                Editor_SubmitBtnID,
                'paybutton',
                'IA.POST_AND_PAY',
                'savepay',
                true,
                "translateSubtotalConstantLabels(); beforeSubmitJS();"
            );
        }

        if (array_key_exists('submit', $this->kActionHandlers) && $this->CanSubmit()) {

            $this->setButtonDetails(
                $values,
                Editor_SubmitBtnID,
                'submitbutton',
                'IA.SUBMIT',
                'submit',
                true,
                "translateSubtotalConstantLabels();"
            );
        } else {

            if ($this->showPostButtonOnEdit()) {
                $this->setButtonDetails(
                    $values,
                    Editor_SaveBtnID,
                    'dobutton',
                    'IA.POST',
                    'save',
                    true,
                    "translateSubtotalConstantLabels(); beforeSubmitJS();"
                );
            }
        }

        $isDraftMode = $this->IsDraftMode();
        if ($this->CanSave() && $this->CanDraft() & $isDraftMode) {
            $this->setButtonDetails(
                $values,
                Editor_SaveBtnID,
                'draftbutton',
                'IA.DRAFT',
                'draftsave',
                true,
                "translateSubtotalConstantLabels(); draftDocument(this, 'draftsave');"
            );
        }

        $this->setButtonDetails(
            $values,
            Editor_CancelBtnID,
            'cancelbutton',
            'IA.CANCEL',
            'cancel',
            false,
            "translateSubtotalConstantLabels();"
        );

        if ($this->showPostAndPrintButton()) {
            $saveAndPrintButtonLabel = (array_key_exists('submit', $this->kActionHandlers) && $this->CanSubmit()) ? 'IA.SUBMIT_AND_PRINT' : 'IA.POST_AND_PRINT';
            $this->createMoreActionEntry(
                $values,
                'saveandprintbuttonid',
                'saveandprintbutton',
                $saveAndPrintButtonLabel,
                'saveandprint',
                true,
                'translateSubtotalConstantLabels();',
                true,
                false,
                array('after' => 1)
            );
        }
        if ($this->CanPrint()) {
            $this->showPrintButton($values);
        }

        if (!$this->CanSubmit() && $this->CanSave()) {
            //$this->setButtonDetails($values, Editor_SaveBtnID, 'scontinuebutton', $this->getContinueButtonName(), 'savecontinue');
            if ($isDraftMode && $this->CanDraft()) {
                $this->createMoreActionEntry(
                    $values,
                    Editor_SaveBtnID,
                    'scontinuebutton',
                    'IA.DRAFT_AND_CONTINUE',
                    'draftcontinue',
                    true,
                    "translateSubtotalConstantLabels(); draftDocument(this, 'draftcontinue');"
                );
            } else {
                $this->createMoreActionEntry(
                    $values,
                    Editor_SaveBtnID,
                    'scontinuebutton',
                    'IA.POST_AND_CONTINUE',
                    'savecontinue',
                    true,
                    "translateSubtotalConstantLabels(); "
                );
            }

        }

        if ($this->CanShowAuditTrail()) {
            $this->configureAuditTrailButton($values);
        }

    }

    /**
     * Creates buttons for kShowViewState
     * @param array $values
     */
    protected function createViewStateButtons(&$values)
    {
        if ($this->canPay()) {
            $this->setButtonDetails(
                $values,
                Editor_SubmitBtnID,
                'paybutton',
                'IA.PAY',
                'pay',
                true,
                "beforeSubmitJS()"
            );
        }

        if ($this->_stateEditable) {
            $this->setButtonDetails(
                $values,
                Editor_SaveBtnID,
                'dobutton',
                'IA.POST',
                'save',
                true,
                "beforeSubmitJS()"
            );
        }

        if (array_key_exists('submit', $this->kActionHandlers) && $this->CanSubmit()) {
            $this->setButtonDetails(
                $values,
                Editor_SubmitBtnID,
                'submitbutton',
                'IA.SUBMIT',
                'submit'
            );
        }

        if ($this->CanEdit()) {
            $this->setButtonDetails(
                $values,
                'editbuttid',
                'editbutton',
                'IA.EDIT',
                'edit',
                false,
                'window.editor.doEdit()',
                false
            );
        }

        $this->setButtonDetails(
            $values,
            Editor_CancelBtnID,
            'cancelbutton',
            'IA.DONE',
            'cancel',
            false
        );

        if ($this->CanPrint()) {
            $this->showPrintButton($values);
        }

        if ($this->CanShowAuditTrail()) {
            $this->configureAuditTrailButton($values);
        }

    }


    /**
     * Creates Post buttons for CRE company enabled document for kShowViewState
     * @param array buttons
     */
    protected function createPostButtonsInViewStateForCRECompany(&$buttons)
    {
        $obj = &Request::$r->GetCurrentObject();
        $isValidDocumentState = in_array($obj['STATE'], [DocumentManager::CONVERTED_STATE, DocumentManager::INPROGRESS_STATE]);
        $canEditChangeLog = (CRESetupManager::isCREInstalled() && isset($obj['_DOCPAR']['ENABLEDOCCHANGE']) && $obj['_DOCPAR']['ENABLEDOCCHANGE'] == 'Enable Change');
        $checkAdditionalInfoEnabled = $this->checkAddInfoEnabled();
        if ($isValidDocumentState && (($checkAdditionalInfoEnabled && $this->canEditConvertDoc) || $canEditChangeLog)) {
            $this->setButtonDetails(
                $buttons,
                Editor_SaveBtnID,
                'dobutton',
                'IA.POST',
                'save',
                true,
                "translateSubtotalConstantLabels(); beforeSubmitJS();");
        }
    }

    /**
     * add a recalc cco fields button if the user is admin
     *
     * @param array $buttons
     * @param array $viewData
     */
    private function addRecalcChangeOrderFieldsAction(array &$buttons, array $viewData) {
        $adminLevel = GetMyAdminLevel();
        if($adminLevel === '2') {
            $this->createMoreActionEntry(
                $buttons,
                'recalc_ccoid',
                'recalc_ccoid',
                'IA.RECALC_DOCUMENT_TOTALS',
                'deliver',
                false,
                "changeOrderDocumentHandler.recalcCCOFields('{$viewData['RECORDNO']}');",
                false,
                false
            );
        }
    }


    /**
     * @param string[]  $values
     */
    protected function showPrintButton(&$values)
    {
        //$this->setButtonDetails($values, 'saveandprintbuttid', 'deliverbutton', 'Print To...', 'deliver', false, "showDeliverPageNew(true, data)", false);
        $this->createMoreActionEntry(
            $values,
            'saveandprintbuttid',
            'deliverbutton',
            'IA.PRINT_TO',
            'deliver',
            false,
            "showDeliverPageNew(true, data)",
            false,
            false
        );
    }

    /**
     * @return bool
     */
    protected function CanDraft()
    {
        $viewData = $this->getViewData();
        if (
            (
                in_array($viewData['STATE'], array(DocumentManager::DRAFT_STATE, DocumentManager::DECLINED_STATE))
                || $this->state == $this->kShowNewState
            )
            && $this->do != 'view'
        ) {
            return true;
        }
        return false;
    }

    // Subclasses to override this

    /**
     * @return bool
     */
    protected function CanSubmit()
    {
        return false;
    }

    // Subclasses to override this

    /**
     * @return bool
     */
    protected function canPay()
    {
        return false;
    }

    /**
     * @return bool
     */
    protected function canPrintPickList()
    {
        if ( $this->isAdvancedSetup && $this->affectsOnHandQty && CheckAuthorization(GetOperationId('so/reports/pickinglist'), 1) && $this->do != 'shownew' ) {
            return true;
        }
        return false;
    }

    /**
     * @param bool  $isDraftMode
     *
     * @return string
     */
    protected function getContinueButtonName($isDraftMode)
    {
        $contButtonName = 'IA.POST_AND_CONTINUE';
        if ( $this->CanDraft() && $isDraftMode ) {
            $contButtonName = 'IA.DRAFT_AND_CONTINUE';
        }
        return $contButtonName;
    }

    /**
     * @param array  $obj
     *
     * @return bool
     */
    protected function prepareObjectForSubmit(&$obj)
    {
        $obj['STATE'] = DocumentManager::SUBMITTED_STATE;

        foreach ( (($obj['ENTRIES']) ?? []) as $key => $lineEntry) {
            if(!isset($obj['ENTRIES'][$key]['ITEMDESC'])) {
                $obj['ENTRIES'][$key]['ITEMDESC'] = '';
            }
        }

        $this->ProcessTrackingEntries($obj);

        return true;
    }

    /**
     * @param string[]  $entity
     *
     * @return bool
     */
    protected function CanCreateObject($entity)
    {
        return true;
    }

    /**
     * @param array  $obj
     *
     * @return bool
     * @throws Exception
     */
    protected function prepareObjectForCreate(&$obj)
    {
        foreach ( (($obj['ENTRIES']) ?? []) as $key => $lineEntry) {
            unset($obj['ENTRIES'][$key]['QUANTITY']);

            if(!isset($obj['ENTRIES'][$key]['ITEMDESC'])) {
                $obj['ENTRIES'][$key]['ITEMDESC'] = '';
            }
        }

        // Setting the request objects as part of the $obj array that would be used by the Add/Set of the Managers
        $obj['_kNoWarn'] = Request::$r->_kNoWarn;
        $obj['_kNoDupl'] = Request::$r->_kNoDupl;
        $obj['_do'] = Request::$r->_do;
        $obj['_mod'] = Request::$r->_mod;
        $this->processDefaultDimensionsForSubtotals($obj);
        $this->ProcessTrackingEntries($obj);

        unset($obj['PRRECORDKEY']);

        $list_op = GetOperationId($this->mod . '/lists/' . $this->getEntity());

        //get preference to reroute to source or child transactions list
        GetUserPreferences($upref, 'DOC_POSTING_OPTION');

        $_done = Request::$r->_done;
        if ( isl_strstr($_done, "sforcekey") === false ) {
            $_sess = Session::getKey();
            $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . $this->dt . '&.sess=' . $_sess;

            // 'F' => reroute to source transaction list
            // 'T' => reroute to child transaction list
            if ( $this->isListerPrefAllowed() && isset($upref) && $upref['DOC_POSTING_OPTION'] == 'F' && isset($obj)
                && $obj['CREATEDFROM'] != null ) {
                $this->done = 'lister.phtml?.op=' . $list_op . '&.sess=' . $_sess;
            }
        }

        return true;
    }

    /**
     * @param array  $obj
     *
     * @return bool
     * @throws Exception
     */
    protected function prepareObjectForSave(&$obj)
    {
        $updatePriceandValue = false;
        if ($obj['_DOCPAR']['DISPLAY_BASECURRENCY']=='true' && IsMCPEnabled()) {
            $updatePriceandValue = true;
        }

        foreach ((($obj['ENTRIES']) ?? []) as $key => $lineEntry) {
            unset($obj['ENTRIES'][$key]['QUANTITY']);

            if(!isset($obj['ENTRIES'][$key]['ITEMDESC'])) {
                $obj['ENTRIES'][$key]['ITEMDESC'] = '';
            }

            if ($updatePriceandValue) {
                $obj['ENTRIES'][$key]['UIVALUE'] = ibcmul($lineEntry['TRX_VALUE'], $lineEntry['EXCHRATE'], DEFAULT_INVPRECISION, true);
                $obj['ENTRIES'][$key]['UIPRICE'] = ibcdiv($lineEntry['UIVALUE'], $lineEntry['UIQTY'], 10, true);
            }
        }

        // Setting the request objects as part of the $obj array that would be used by the Add/Set of the Managers
        $obj['_kNoWarn'] = Request::$r->_kNoWarn;
        $obj['_kNoDupl'] = Request::$r->_kNoDupl;
        $obj['_do'] = Request::$r->_do;
        $obj['_mod'] = Request::$r->_mod;

        $this->processDefaultDimensionsForSubtotals($obj);
        $this->ProcessSubtotalsForSave($obj);
        $this->ProcessTrackingEntries($obj);

        $entityMgr = $this->getEntityMgr();
        $entityMgr->setWarningValidation();

        return true;
    }

    /**
     * @param array  $obj
     *
     * @throws Exception
     */
    protected function ProcessTrackingEntries(&$obj)
    {
        $this->GetItemInfo($obj);
        foreach ((($obj['ENTRIES']) ?? []) as $key => $lineEntry) {
            $trackEntries = array();
            $isSerialTrackingEnabled = $lineEntry['ENABLESNO']=='T';

            foreach ($lineEntry['TRACKINGENTRIES'] ?? [] as $tEtnry) {
                $hasTrackData = $tEtnry['TRACK_QUANTITY'];
                if (strlen($hasTrackData) == 0 || ($isSerialTrackingEnabled && empty($tEtnry['SERIALNO'])) ) {
                    continue;
                }
                $tEtnry['QUANTITY'] = $tEtnry['TRACK_QUANTITY'];
                $trackEntries[] = $tEtnry;
            }
            unset($obj['ENTRIES'][$key]['TRACKINGENTRIES']);
            $obj['ENTRIES'][$key]['TRACKINGENTRIES'] = $trackEntries;
        }
    }

    /**
     * @param array  $obj
     *
     * @throws Exception
     */
    protected function GetItemInfo(&$obj){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr =  $gManagerFactory->getManager('item');
        // The below code is to avoid the number of queries hitting database.
        // Though we do 3 loops, it is effective than using the oracle resources for query each item.
        $itemIDs = array();

        $entries = $obj['ENTRIES'] ?? [];

        $entryCnt = count($entries);
        if ($entryCnt > 0) {
            for ($i = 0; $i < $entryCnt; $i++) {
                [$itemid] = explode('--', $obj['ENTRIES'][$i]['ITEMID']);
                if (!in_array($itemid, $itemIDs, true)) {
                    $itemIDs[] = $itemid;
                }
            }

            if (!empty($itemIDs)) {
                StartTimer('ItemCache');
                $itemFieldList = array('ITEMID', 'NAME', 'ITEMTYPE', 'ENABLELOT', 'ENABLESNO', 'ENABLEBIN', 'ENABLEEXPIRATION');
                $itemCache = $itemMgr->GetItemsRawCache(array_unique($itemIDs), true, $itemFieldList);
                StopTimer('ItemCache');

                for ($i = 0; $i < $entryCnt; $i++) {
                    [$itemID] = explode('--', $obj['ENTRIES'][$i]['ITEMID']);
                    $obj['ENTRIES'][$i]['ENABLESNO'] = $itemCache[$itemID]['ENABLESNO'];
                    $obj['ENTRIES'][$i]['ENABLELOT'] = $itemCache[$itemID]['ENABLELOT'];
                    $obj['ENTRIES'][$i]['ENABLEBIN'] = $itemCache[$itemID]['ENABLEBIN'];
                    $obj['ENTRIES'][$i]['ENABLEEXPIRATION'] = $itemCache[$itemID]['ENABLEEXPIRATION'];
                    $obj['ENTRIES'][$i]['ITEMTYPE'] = $itemCache[$itemID]['ITEMTYPE'];

                }
            }
        }
    }


    /**
     * @param string[]  $_params
     */
    protected function ProcessDeriveDocumentAction(/** @noinspection PhpUnusedParameterInspection */ &$_params)
    {
        $_sess = Session::getKey();

        $obj = & Request::$r->GetCurrentObject();

        $done = Request::$r->_done;
        $ent = $obj['CUSTVENDID'];
        [$ent] = explode('--', $ent);

        $srcdoc = $obj['DOCID'];
        $dt = $obj['DERIVEDOCTYPE'];
        $op = GetOperationId($this->mod . '/activities/' . $this->mod . 'document/create');
        $url = "editor.phtml?.sess=$_sess&.op=$op&.do=create&_dt=" . urlencode($dt) . "&_ent=" . urlencode($ent)
            . "&_mod=$this->mod&_srcdoc=" . urlencode($srcdoc) . "&_copymode=Update&_derive=1";
        Fwd($url, $done);
    }


    // This function is used when a document is created from multiple source transactions (mass comversion)
    // This function gets all the source document entries and filters the fully converted entries
    // This function is called from PreprocessEditNewAction
    // $values -> this is the temp object stored in object_store table
    // $srcEntityMgr -> the source entity manager object
    /**
     * @param array         $values
     * @param object        $srcEntityMgr
     *
     * @return string[]
     * @throws Exception
     */
    protected function ProcessMultipleSourceTransactions($values, $srcEntityMgr)
    {
        global $gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');
        $destdoctype = Request::$r->_dt;

        $isCREInstalled = CRESetupManager::isCREInstalled();

        /**
         * @var DocumentParamsManager   $docparMgr
         */
        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');

        $newdocpar = $docparMgr->GetBaseLatest($destdoctype);
        $newenableoverride = $newdocpar['ENABLEOVERRIDETAX'];

        $ownedObjects =& $srcEntityMgr->GetOwnedObjects();
        // get all the convertable line entries from each source document
        $sourceDocs = $values['SOURCE_DOCS'];
        foreach ( $sourceDocs as $sourceDocID ) {
            $sourceDoc = $srcEntityMgr->get($sourceDocID);
            //$sDocs[] = "['" . $sourceDocID . "']";
            $sDocs[] = $sourceDocID;

            if( ! util_isPlatformDisabled() ) {
                foreach ($ownedObjects as $objRec) {
                    $platform_rels = $this->getPlatformRels($objRec['path']);
                    if (!empty($platform_rels)) {
                        $this->fetchPlatformRels($objRec, $platform_rels, $sourceDoc);
                    }
                }
            }

            $exchRate = 1;
            if ( $this->ismcpEnabled ) {
                $exchRateMgr = $gManagerFactory->getManager('exchangerate');
                $basecurr = $sourceDoc['BASECURR'] ?: GetBaseCurrency();

                if ($sourceDoc['EXCH_RATE_TYPE_ID'] != CUSTOM_RATE_ID) {
                    $exchRate = $exchRateMgr->GetTrxExchangeRateByTypeID(
                        $sourceDoc['EXCH_RATE_TYPE_ID'], $sourceDoc['CURRENCY'], $basecurr, GetCurrentDate()
                    );
                }
            }
            $precision = $this->lookupAppPrecision();

            $enableDocChange = $sourceDoc["_DOCPAR"]["ENABLEDOCCHANGE"] ?? "No Change";
            $isCCOSourceDoc = $isCREInstalled && ($enableDocChange == 'Enable Change');

            foreach ( (($sourceDoc['ENTRIES']) ?? []) as $sourceEntry ) {
                $itemid = explode('--', $sourceEntry['ITEMID']); //splitting the itemid
                $itemid = $itemid[0];


                // Get the conversion factor
                $uomInfo = $itemMgr->GetUOMInfoCache(array($itemid), true);
                $itemMgr->GetLineEntry_UOMPrecissionInfo($sourceEntry, $uomInfo, $conversion, $uomPrecission);

                if($isCCOSourceDoc){
                    $sourceEntry['QUANTITY'] = $sourceEntry['REVISEDQTY'] ?: $sourceEntry['QUANTITY'];
                    $sourceEntry['TRX_VALUE'] = $sourceEntry['TRX_REVISEDVALUE'];
                    $sourceEntry['UIPRICE'] = $sourceEntry['REVISEDPRICE'];
                    $sourceEntry['UIVALUE'] = $sourceEntry['REVISEDVALUE'];
                    $sourceEntry['UIQTY'] = $sourceEntry['REVISEDUNITQTY'];
                }
                // pick only those entries which are not fully converted
                if ( $sourceEntry['QUANTITY'] != $sourceEntry['QTY_CONVERTED'] ) {

                    // get the remaining quantity to convert
                    $quantity = $sourceEntry['QUANTITY'];

                    //if changeorder is enabled, we try to use to revisedqty if it exists
                    $revisedQuantity = $sourceEntry['REVISEDQTY'] ?? "";

                    if(Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled() && $revisedQuantity !== "") {
                        $quantity = $revisedQuantity;
                    }

                    $sourceEntry['QUANTITY'] = ibcsub($quantity, $sourceEntry['QTY_CONVERTED'], $uomPrecission, true);
                    $sourceEntry['UIQTY'] = ibcdiv($sourceEntry['QUANTITY'], $conversion, $uomPrecission, true);

                    if ($sourceEntry['CONVERSIONTYPE'] == 'Price') {
                        $sourceEntry['QUANTITY'] = $sourceEntry['UIQTY'] = '1';
                        if($isCCOSourceDoc) {
                            $totalAmtRemaining = ibcsub($sourceEntry["REVISEDPRICE"], $sourceEntry["PRICE_CONVERTED"]);
                            $sourceEntry['PRICE'] = $sourceEntry['TRX_PRICE'] = $sourceEntry['UIPRICE'] = $totalAmtRemaining;
                        }else{
                            $sourceEntry['PRICE'] = $sourceEntry['TRX_PRICE'] = $sourceEntry['UIPRICE'] = $sourceEntry['TOTAL_AMOUNT_REMAINING'];
                        }
                        $sourceEntry['QTY_CONVERTED'] = '0';
                    }

                    $discountOnExtPrice = ($newdocpar['DISCOUNT_ON_EXTENDEDPRICE'] === 'true');
                    $this->computeExtendedPriceWhenConverting($sourceEntry, $discountOnExtPrice, $exchRate, $precision);

                    // get the source docid & linekey
                    $sourceEntry['SOURCE_DOCKEY'] = $sourceEntry['DOCHDRNO'];
                    $sourceEntry['SOURCE_DOCLINEKEY'] = $sourceEntry['RECORDNO'];
                    $sourceEntry['SOURCE_DOCID'] = $sourceDoc['DOCID'];

                    if($newdocpar['ALLOW_ALLOCATIONS'] == 'true') {
                        // in case of PO document there might be allocations set
                        // carry the source entry splits
                        if (isset($sourceEntry['ALLOCATIONKEY']) && $sourceEntry['ALLOCATIONKEY'] !== ''
                            && isset($sourceEntry['SPLIT']) && is_array($sourceEntry['SPLIT'])) {
                            $sourceEntry['SOURCE_SPLIT'] = $sourceEntry['SPLIT'];
                            $sourceEntry['SOURCE_ALLOCATIONKEY'] = $sourceEntry['ALLOCATIONKEY'];
                        }
                    } else {
                        unset($sourceEntry['SPLIT']);
                    }

                    // If destination document has subscribed to override tax
                    // then "Override Tax" tax checkbox value should be defaulted to ITEM.TAXABLE value
                    if ( $newenableoverride == 'true' ) {
                        $sourceEntry['OVERRIDETAX'] = $sourceEntry['ITEM']['TAXABLE'];
                    }
                    unset($sourceEntry['RECORDNO']);
                    if (!is_null($sourceEntry['TRACKINGENTRIES']))
                    {
                        foreach( $sourceEntry['TRACKINGENTRIES'] as &$tEntry){
                            unset($tEntry['RECORDNO']);
                        }
                    }
                    $values['ENTRIES'][] = $sourceEntry;
                }
            }

            // get source docuemnts history
            foreach ( (($sourceDoc['HISTORY']) ?? []) as $shistory ) {
                if ( $shistory['DOCUMENTID'] == $sourceDocID ) {
                    $values['HISTORY'][] = $shistory;
                }
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $this->sourceDocsArr = $sDocs;

        // JS array sourceDocsArr is also defined in ShowScripts in edit mode if the child document
        // is created from multiple source transactions
        // the following sourceDocsArr var is defined only when creating
        // a new transaction from multiple source docuemnts
        //$sourceDocsjs = '[' . join(',', $sDocs) . ']';
        //$sourceDocsjs = "<SCRIPT> sourceDocsArr = " . $sourceDocsjs . "; </SCRIPT>";
        //echo $sourceDocsjs;

        return $values;
    }


    /**
     * @param array $sourceDoc
     * @param array $backOrder
     *
     * @return bool
     */
    protected function processBackOrder(&$sourceDoc, $backOrder)
    {
        if (empty($backOrder)) {
            return true;
        }

        // back order document type will same as that of the source document
        $bOrderDocType = $sourceDoc['_DOCPAR']['DOCID'];

        $gManagerFactory = Globals::$g->gManagerFactory;
        /**
         * @var DocumentEntryManager $docentryMgr
         */
        $docentryMgr = $gManagerFactory->getManager($this->mod . 'documententry',
                                                    true,
                                                    array('DOCTYPE' => $bOrderDocType));
        $backOrderEntries = $docentryMgr->GetByParent($backOrder['RECORD#']);

        if (empty($backOrderEntries)) {
            return true;
        }

        if(!is_null($sourceDoc['ENTRIES']))
        {
            foreach ($sourceDoc['ENTRIES'] as &$sEntry) {
                [$sItemId] = explode('--', $sEntry['ITEMID']);

                foreach ($backOrderEntries as $bEntry) {
                    [$bItemId] = explode('--', $bEntry['ITEMID']);

                    if ($sItemId == $bItemId
                        && $sEntry['DOCHDRNO'] == $bEntry['SOURCE_DOCKEY']
                        && $sEntry['RECORDNO'] == $bEntry['SOURCE_DOCLINEKEY']) {

                        $sEntry['QTY_CONVERTED'] = ibcadd(
                            $sEntry['QTY_CONVERTED'], $bEntry['QUANTITY'], ItemManager::BASEUNITPRECISION
                        );
                    }
                }
            }
        }

        $sourceDoc['HASCONVERTEDLINES'] = true;

        return true;
    }

    /**
     * @param string[]|string[][]|string[][][]  $obj
     *
     * @return bool
     * @throws Exception
     */
    protected function innerProcessEditNewAction(&$obj)
    {
        $copy = Request::$r->_copymode;
        $_createdfrom = Request::$r->_createdfrom;
        //$this->state = 'shownew';

        $destdoctype = Request::$r->_dt;
        $recalledID = Request::$r->{Globals::$g->kId};
        if($copy == 'Update' && $this->state == 'shownew' && $recalledID != '') {
            Request::$r->_copymode = '';
            Globals::$g->kId = '';
            $copy = '';
            $recalledID = '';
        }

        if (!in_array(SCMMacroManager::LCEST, $this->macroNames)) {
            unset($obj['ENTRIESLCEST']);
        }

        // Copy compatible custom fields from source document to destination document
        $srcdoctype = $this->copyToAdapter->getThisDocType($recalledID);

        if ( ! $this->processToConvertDocument($new, $old, $copy, $docpar, $srcdoctype, $recalledID)) {
            return false;
        }

        $new['DOCPARID'] = $destdoctype;

        if(!$this->validateConvertDocumentonTD($new, $docpar)){
            return false;
        }

        $new =  $this->prepareSalesforceValuesForCreate($new, $docpar);

        $this->PreProcessEditorGetSubTotals($srcdoctype, $destdoctype, $old, $new, Profile::getProperty('SFORCEKEY'));

        // Give child classes oppertunity do additional processing
        $this->PostProcessCopyConvert($srcdoctype, $destdoctype, $old, $new);

        if ( $copy == 'Update' ) {
            // either unset or inherit from source document based on the user preference
            $this->processDateFromSourceTrans($new, $old);
        }

        $obj = $new;

        return true;
    }

    /**
     * @param array $_params
     * @param array $obj
     *
     * @return bool
     */
    protected function innerProcessEditAction(&$_params, &$obj)
    {
        $ok = parent::innerProcessEditAction($_params, $obj);

        // validate On Change source option is available or not
        // This will validate the PO match draft document
        // If its is not available we need to skip this otherwise continue
        if (!$this->onChangeSrcDocOptionIsAvailable($obj)) {
            return $ok;
        }

        $copy = Request::$r->_copymode ?? '';

        $_createdfrom = Request::$r->_createdfrom;
        $destdoctype = Request::$r->_dt;

        // This Change source document option should be only for edit mode
        // This _sourcedocid variable will set only in change source document functionality
        // from changeOptionToConvertFrom in Js
        $recalledID = Request::$r->_sourcedocid;

        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();

        if (!$ok
            || $copy != 'Update'
            || $recalledID == $multipleSrcDocText) {
            return $ok;
        }

        // Copy compatible custom fields from source document to destination document
        $srcdoctype = $this->copyToAdapter->getThisDocType($recalledID);

        if ( ! $this->processToConvertDocument($new, $old, $copy, $docpar, $srcdoctype, $recalledID)) {
            return false;
        }

        $new['DOCPARID'] = $destdoctype;

        if (!$this->validateConvertDocumentonTD($new, $docpar)) {
            return false;
        }

        $ok = $ok && $this->PreProcessEditorGetSubTotals($srcdoctype, $destdoctype, $old, $new, Profile::getProperty('SFORCEKEY'));

        // Give child classes oppertunity do additional processing
        // this function only for SO
        $ok = $ok && $this->PostProcessCopyConvert($srcdoctype, $destdoctype, $old, $new);

        // either unset or inherit from source document based on the user preference
        $this->processDateFromSourceTrans($new, $old);

        $ok = $ok && $this->processChangeSourceTransforUpdate($new, $recalledID, $obj);

        return $ok;
    }

    /**
     * @param array $new
     * @param string $recalledID
     * @param array $obj
     *
     * @return bool
     */
    protected function processChangeSourceTransforUpdate(&$new, $recalledID, &$obj)
    {
        $ok = true;

        if (empty($recalledID)) {
            return $ok;
        }

        if (Util::countOrZero($obj) > 0
            && Util::countOrZero($new['ENTRIES']) > 0) {

            // Here we are going throw each line entries of source document and updating the child document details
            // Child document details like DOCHDRNO, DOCHDRID DOCPARID fields value
            // Because for documententry manager need the child document header details identify the document
            foreach ($new['ENTRIES'] as $key => $newEntry) {
                $new['ENTRIES'][$key]['DOCHDRNO'] = $obj['RECORDNO'];
                $new['ENTRIES'][$key]['DOCHDRID'] = $obj['DOCID'];
                $new['ENTRIES'][$key]['DOCPARID'] = $obj['DOCPARID'];
            }

            // After preparing, Here we are updating the entries details
            $obj['ENTRIES'] = $new['ENTRIES'];
            $obj['CREATEDFROM'] = $recalledID;
        }

        return $ok;
    }

    /**
     * handle the mult-currency fields in case of MCP company
     * when handling a change order document, we do not want to set the currency fields as they get copied from source document
     *
     * @param  array $new
     */
    private function handleMCPValues(&$new) {
        global $gManagerFactory;
        /** @noinspection PhpIllegalStringOffsetInspection */
        if ( $this->ismcpEnabled && $this->docpar["ENABLEDOCCHANGE"] !== 'Change Order') {
            $new['EXCHRATEDATE'] = GetCurrentDate();

            $exchRateMgr = $gManagerFactory->getManager('exchangerate');
            $basecurr = $new['BASECURR'] ?: GetBaseCurrency();

            if ($new['EXCH_RATE_TYPE_ID'] != CUSTOM_RATE_ID) {
                $new['EXCHRATE'] = $exchRateMgr->GetTrxExchangeRateByTypeID(
                    $new['EXCH_RATE_TYPE_ID'], $new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']
                );
            }
        }
    }


    /**
     * @param string[]|string[][]|string[][][]    $values
     */
    function ProcessSubtotalsForSave(&$values)
    {
        // This function is to retain the subtotals of the source document if any when it is copied or converted
        //
        // the first [SUBTOTAL] and the last element [TOTAL] are not the subtotals

        // remove the [SUBTOTAL] & [TOTAL] elements from the ssubtotal structure
        $subtotals = $values['SUBTOTALS'];
        $subtotcount = (is_countable($subtotals)) ? count($subtotals) : 0;
        if(isset($subtotals)) {
            if($subtotals[0]['DESCRIPTION'] == 'SUBTOTAL') {
                unset($subtotals[0]);
            }
            if($subtotals[$subtotcount-1]['DESCRIPTION'] == 'TOTAL') {
                unset($subtotals[$subtotcount-1]);
            }
        }
        // now check if there are any actual subtotals left
        // if not then unset the subtotal section
        if(!$subtotcount) {
            unset($values['SUBTOTALS']);
        }

    }

    /**
     * @return bool
     */
    protected function CanEdit()
    {
        $ok = parent::CanEdit();
        if ( $ok ) {
            //$view = $this->getView();
            //$view->findComponents(array('path' => 'STATE'), EditorComponentFactory::TYPE_FIELD, $_state);
            //$_currentState = $this->currentObject['STATE'];
            $nonEditableStates = array(
                DocumentManager::CONVERTED_STATE,
                DocumentManager::CONVERTED_BY_LINE_STATE,
                DocumentManager::INPROGRESS_STATE,
                DocumentManager::SUBMITTED_STATE,
                DocumentManager::PARTIALLY_APPROVED_STATE,
                DocumentManager::APPROVED_STATE,
                DocumentManager::ANALYZING_STATE
            );
            //foreach ($_state as $state) {
            $obj = & Request::$r->GetCurrentObject();

            if ( in_array($obj['STATE'], $nonEditableStates) ) {
                $ok = false;
            }

            $ok = $ok && $this->canSaveEditForMacro();
        }

        return $ok;
    }

    /**
     * @return bool
     */
    protected function showPostButtonOnEdit()
    {
        return $this->CanSave();
    }

    /**
     * @return bool
     */
    protected function CanSave()
    {
        $ok = parent::CanSave();
        $ok = $ok && $this->canSaveEditForMacro();

        return $ok;
    }

    /**
     * @return bool
     */
    private function canSaveEditForMacro()
    {
        $ok = true;

        if ($this->macroForDocument &&
            ($obj = &Request::$r->GetCurrentObject()) != null &&
            $obj['SCMMACROLINK'] == 'T') {
            if (in_array(SCMMacroManager::LCEST, $this->macroNames)) {
                //LC estimate doc can be save unless is linked to a LC actual doc
                foreach ((($obj['ENTRIESLCEST']) ?? []) as $entry) {
                    if ($entry['LCDOCHDRNO'] || $entry['LCDOCENTRYNO']) {
                        $ok = false; //This LC estimate doc is linked to LC actual doc so we can not edit
                    }
                }
            } else {
                //Macro linked docs, cannot be saved
                $ok = false;
            }
        }
        return $ok;
    }

    /**
     * @param  string $entity
     * @param string $doctype
     *
     * @return EntityManager
     * @throws Exception
     */
    public function GetManager($entity, $doctype='')
    {
        if ( $doctype == '' ) {
            // docid will be string always. to fix php 8.1 issue 165526
            $docid = (string)Request::$r->_r;
            if ( $this->dt == '' && $docid != '' ) {
                $this->dt = GetDocumentType($docid);
                if ( $this->dt != '' ) {
                    Request::$r->_dt = $this->dt;
                }
            }
            $doctype = (string)$this->dt;
        }
        $entManager =  Globals::$g->gManagerFactory->getManager($entity, false, array( 'DOCTYPE' => $doctype));
        return $entManager;
    }


    /**
     * @param string[] $_params
     *
     * @return bool|mixed
     */
    protected function ProcessSaveContinueAction(&$_params)
    {
        global $gErr;

        if ( !is_object($this->entityMgr) ) {
            $this->entityMgr =  $this->GetManager($this->getEntity());
        }
        $entityMgr = $this->getEntityMgr();

        if ( $this->ProcessErrorRetrivalAction($entityMgr) ) {
            $this->state = $this->kShowNewState;
            return true;
        }

        $_params['_iscontinue'] = true;

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj =  $this->DoRefreshAction($_params, $obj);


        if ( $this->state == $this->kShowNewState ) {
            $obj['_isdraft'] = true;
            $ok = $ok && $this->prepareObjectForCreate($obj);
            $ok = $this->innerProcessCreateAction($_params, $obj, $ok);
        } else {
            if ( $obj['STATE'] == 'Draft' ) {
                $obj['_isdraft'] = true;
            }
            $ok = $ok && $this->prepareObjectForSave($obj);
            $ok = $this->innerProcessSaveAction($_params, $obj, $ok);
        }

        if ( !in_array($this->state, array($this->kErrorState, $this->kEditWarningState)) && !$gErr->hasWarnings() ) {
            Request::$r->_currentlayer = '';
            Request::$r->_changed = 'false';
            $obj = & Request::$r->GetCurrentObject();
            //$entityMgr = $this->GetManager($_params['entity']);
            EntityManager::SetByPath($obj, $entityMgr->GetKeyFieldName(), '');

            $ent = $obj['CUSTVENDID'];
            [$ent] = explode('--', $ent);

            $srcdoc = $obj['DOCPARID'] . "-" . $obj['DOCNO'];

            $op = $this->getOperationIdForSaveContinue();

            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowEditState;
            $this->SetDoneParam();

            Fwd(
                'editor.phtml?.sess=' . Session::getKey() . '&.r=' . urlencode($srcdoc) . '&.op=' . $op
                . '&_ent=' . urlencode($ent) . '&.dt=' . urlencode($this->dt)
                . '&_msg=' . urlencode($this->GetMessage()), $this->done
            );
        }
        return $ok;
    }

    /**
     * @param array $_params
     *
     * @return bool|mixed
     */
    protected function ProcessDraftContinueAction(&$_params)
    {
        global $gErr;

        if (!is_object($this->entityMgr)) {
            $this->entityMgr = $this->GetManager($this->getEntity());
        }
        $entityMgr = $this->getEntityMgr();
        if ($this->ProcessErrorRetrivalAction($entityMgr)) {
            $this->state = $this->kShowNewState;
            return true;
        }

        $_params['_iscontinue'] = true;

        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);
        $obj['_isdraft'] = true;

        if ($this->state == $this->kShowNewState) {
            $ok = $ok && $this->prepareObjectForCreate($obj);
            $ok = $this->innerProcessCreateAction($_params, $obj, $ok);
        } else {
            $ok = $ok && $this->prepareObjectForSave($obj);
            $ok = $this->innerProcessSaveAction($_params, $obj, $ok);
        }

        if (!in_array($this->state, array($this->kErrorState, $this->kEditWarningState)) && !$gErr->hasWarnings()) {
            Request::$r->_currentlayer = '';
            Request::$r->_changed = 'false';
            $obj = &Request::$r->GetCurrentObject();
            EntityManager::SetByPath($obj, $entityMgr->GetKeyFieldName(), '');

            $ent = $obj['CUSTVENDID'];
            [$ent] = explode('--', $ent);
            $srcdoc = $obj['DOCPARID'] . "-" . $obj['DOCNO'];

            $op = $this->getOperationIdForSaveContinue();

            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowEditState;
            $this->SetDoneParam();

            Fwd(
                'editor.phtml?.sess=' . Session::getKey() . '&.r=' . urlencode($srcdoc) . '&.op=' . $op
                . '&_ent=' . urlencode($ent) . '&.dt=' . urlencode($this->dt)
                . '&_msg=' . urlencode($this->GetMessage()), $this->done
            );
        }
        return $ok;
    }

    /**
     * @return int
     */
    protected function getOperationIdForSaveContinue()
    {
        return GetOperationId($this->mod . '/lists/' . $this->mod . 'document/edit');
    }

    /**
     * @param string[] $_params
     * @param string[]|string[][]|string[][][]   $obj
     * @param bool  $ok
     *
     * @return bool
     */
    protected function innerProcessCreateAction(&$_params, &$obj, $ok)
    {
        $oldState = $obj['STATE'];
        if ($obj['_isdraft'] === true) {
            $obj['STATE'] = DocumentManager::DRAFT_STATE;
        }

        $ok = parent::innerProcessCreateAction($_params, $obj, $ok);

        if ( $ok ) {
            $obj = & Request::$r->GetCurrentObject();
            EntityManager::SetByPath($obj, $this->getEntityMgr()->GetKeyFieldName(), '');

            $after = Request::$r->after;

            if ( $after == 1 ) {
                $ok = $ok && $this->innerProcessEditNewAction($obj);

                if ( $this->postAndNew ) {
                    // Since we now redirect for post and new, we must put these re-populate fields into the redirect url
                    $this->postAndNewPopData = $obj;
                }

                Request::$r->SetCurrentObject($obj);
            }

            GetUserPreferences($upref, 'DOC_POSTING_OPTION');
            $upref_doc_posting = $upref['DOC_POSTING_OPTION'];
            $op = GetOperationId($this->mod . '/lists/' . $this->mod . 'document');
            $done = 'lister.phtml?.op=' . $op . '&.sess=' . Session::getKey();
            //If document is result of conversion, after saving go to conveted from document lister
            if ($this->isListerPrefAllowed() && isset($upref_doc_posting) && $upref_doc_posting == 'F'
                && isset($obj) && $obj['CREATEDFROM'] != null) {
                $dt = Request::$r->_parentdt;
            } elseif ($this->isListerPrefAllowed() && isset($upref_doc_posting) && $upref_doc_posting == 'T'
                && isset($obj) && $obj['CREATEDFROM'] != null) {
                //If document is result of conversion, after saving go to conveted to document lister
                $dt = Request::$r->_dt;
            }
            if (isset($dt) && $dt != '' && $dt != 'null') {
                $done .= '&.dt=' . $dt;
                $this->done = $done;
            }
        } else {
            $obj['STATE'] = $oldState;
            unset($obj['_isdraft']);
        }

        return $ok;
    }

    /**
     * @param string[] $_params
     * @param string[]|string[][]|string[][][]   $obj
     * @param bool  $ok
     *
     * @return bool
     */
    protected function innerProcessSaveAction(&$_params, &$obj, $ok)
    {
        /**
         * @var URLS $gURLs
         */
        global $gURLs;
        $origValues = $obj;

        $oldState = $obj['STATE'];
        if ($obj['_isdraft'] === true) {
            $obj['STATE'] = DocumentManager::DRAFT_STATE;
        } else if ($obj['STATE'] == DocumentManager::DRAFT_STATE) {
            unset($obj['STATE']);
        }

        if ($oldState === DocumentManager::EXCEPTION_STATE) {
            $obj['OVERRIDE_EXCEPTION'] = $_params['OVERRIDE_EXCEPTION'];
        }

        if ( !is_object($this->entityMgr) ) {
            $this->entityMgr =  $this->GetManager($_params['entity']);
        }
        $entityMgr = $this->getEntityMgr();

        $entityMgr->setWarningValidation();
        $ok = $ok && $entityMgr->CleanupEditorValues($obj);
        $ok = $ok && $this->validatePlatformData($obj);
        if ( $this->_stateEditable ) {
            /**
             * @var DocumentManager $documentManager
             */
            $documentManager = $entityMgr;
            $ok = $ok && $documentManager->PartialSet($obj);
        } else {
            $ok = $ok && $entityMgr->set($obj);
        }
        // Some of these reimplementations don't call the parent function, so we need to make sure we clean the cache
        // here, as we moved away from clearing the warningCache in FormEditor::ProcessSaveAction (issue 88295)
        if ($ok) {
            // Clear the warning cache struncture WHEN operation is successful
            Globals::$g->gErr->warningsCache->clear();
        }

        $entityDesc = $_params['entityDesc'];
        if ( !$ok ) {
            // restore the original values because they got modified by
            // the CleanupEditorValues and Add function
            $obj = $origValues;

            $obj['STATE'] = $oldState;
            unset($obj['_isdraft']);

            global $gErr;

            if ( $gErr->hasWarnings() ) {
                $this->warningmessage = true;
            }

            if ( $gErr->hasErrors() ) {
                $gErr->addIAError('INV-0361', __FILE__ . ":" . __LINE__, "Creating $entityDesc failed", ['ENTITY_DESC' => $entityDesc]);
                $this->state = $this->kErrorState;
            }
        } elseif ( $this->GetPreference($_params, "Update.RequireConfirmation") ) {
            $tokens = [
                [
                    'id' => 'IA.THE_ENTITY_WAS_SAVED_SUCCESSFULLY',
                    'placeHolders' => [
                        ['name' => 'DOCID', 'value' => $entityDesc]
                    ]
                ]
            ];
            $text = getLocalizedTextWithThrow($tokens);
            $confirmation = GT($text, 'IA.THE_ENTITY_WAS_SAVED_SUCCESSFULLY');
            $this->SetMessageWithObject($confirmation, $obj);
            $this->state = $this->kConfirmState;
        } elseif ( $gURLs->HasReturnPath() ) {
            $this->state = $this->kGoBackState;
        } elseif ( $_params['popup'] || $_params['ydialog'] ) {
            $this->state = $this->kCloseState;
        } else {
            $this->state = $this->kGoHomeState;
        }
        return $ok;
    }

    /**
     * @param string[] $_params
     * @param string[]|string[][]|string[][][]   $obj
     * @param bool  $ok
     *
     * @return bool
     * @throws Exception
     */
    protected function innerProcessRefreshAction($_params, &$obj, $ok)
    {
        $this->getSubTotals($obj, true);
        return $ok;
    }




    /**
     * @access private
     */
    protected function SetDoneParam()
    {
        $list_op = GetOperationId($this->mod . '/lists/' . $this->mod . 'document');
        $_done = Request::$r->_done;
        $_sess = Session::getKey();
        if ( isl_strstr($_done, "sforcekey") === false ) {
            $this->done = 'lister.phtml?.op=' . $list_op . '&.dt=' . $this->dt . '&.sess=' . $_sess;
        }
    }


    /**
     * @param string    $srcdoctype
     * @param string    $destdoctype
     * @param array     $old
     * @param array     $new
     * @param string    $sfkey
     *
     * @return bool
     * @throws Exception
     */
    function PreProcessEditorGetSubTotals($srcdoctype, $destdoctype, &$old, &$new, $sfkey)
    {
        //eppp_p("PreProcessEditorGetSubTotals");
        //eppp_p("srcdoctype:".$srcdoctype);
        //eppp_p("destdoctype:".$destdoctype);
        //eppp_p('SFORCEKEY:'.Profile::getProperty('SFORCEKEY'));
        $countEntries = isset($new['ENTRIES']) ? count($new['ENTRIES']) : 0;
        if ( isset($sfkey) && $sfkey != '' ) {
            $action = Request::$r->_action;
            //eppp_p("action:".$action);
            // Set the default value to OVERRIDETAX checkbox
            // only when drawing txn screen for first time
            if ( $action != 'refresh' ) {
                global $gManagerFactory;
                /**
                 * @var DocumentParamsManager   $docparMgr
                 */
                $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
                $itemMgr = $gManagerFactory->getManager('item');

                $newdocpar = $docparMgr->GetBaseLatest($destdoctype);
                $newenableoverride = $newdocpar['ENABLEOVERRIDETAX'];
                //eppp_p("newenableoverride:".$newenableoverride);

                if ( $newenableoverride == 'true' ) {
                    //eppp_p($new['ENTRIES']);

                    $itemsArr = array();
                    if ($countEntries) {
                        foreach ($new['ENTRIES'] as $entry) {
                            [$itemid] = explode('--', $entry['ITEMID']);
                            if (!in_array($itemid, $itemsArr, true)) {
                                $itemsArr[] = $itemid;
                            }
                        }
                    }

                    $itemRawCache = $itemMgr->GetItemsRawCache($itemsArr);

                    for ( $i = 0; $i < $countEntries; $i++ ) {
                        [$itemid] = explode('--', $new['ENTRIES'][$i]['ITEMID'] ?? '');
                        //eppp_p("itemid:".$itemid);
                        //eppp_p($itemraw);

                        $taxable = $itemRawCache[$itemid]['TAXABLE'];
                        //eppp_p("taxable:".$taxable);

                        $new['ENTRIES'][$i]['OVERRIDETAX'] = ($taxable == 'T') ? 'true' : 'false';
                    }
                }
            }

            return true;
        }

        if ( $srcdoctype == "" || $destdoctype == "" ) {
            return true;
        }

        // _DOCPAR is not set, fetching it
        // DocumentparamsManager::GetBaseLatest caches information
        // There is no risk of hitting database too many times

        global $gManagerFactory;
        /**
         * @var DocumentParamsManager   $docparMgr
         */
        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
        $olddocpar = $docparMgr->GetBaseLatest($srcdoctype);
        //eppp_p($olddocpar);

        $newdocpar = $docparMgr->GetBaseLatest($destdoctype);
        //eppp_p($newdocpar);
        // ENABLEOVERRIDETAX functionality is not applicable for IC
        // Value 'false' will make sure code is not executed
        $oldenableoverride = $olddocpar['ENABLEOVERRIDETAX'];
        $newenableoverride = $newdocpar['ENABLEOVERRIDETAX'];
        //eppp_p("oldenableoverride:".$oldenableoverride);
        //eppp_p("newenableoverride:".$newenableoverride);
        // If destination document has subscribed to override tax  but source document has not
        // then "Override Tax" tax checkbox value should be defaulted to ITEM.TAXABLE value
        if ( $newenableoverride == 'true' && $oldenableoverride != 'true' ) {
            for ( $i = 0; $i < $countEntries; $i++ ) {
                $new['ENTRIES'][$i]['OVERRIDETAX'] = $old['ENTRIES'][$i]['ITEM']['TAXABLE'];
            }
        }

        return true;
    }


    /**
     * @param string    $srcdoctype
     * @param string    $destdoctype
     * @param string[]|string[][]|string[][][]       $old
     * @param string[]|string[][]|string[][][]       $new
     *
     * @return bool
     */
    protected function PostProcessCopyConvert(/** @noinspection PhpUnusedParameterInspection */ $srcdoctype,
        /** @noinspection PhpUnusedParameterInspection */ $destdoctype,
        /** @noinspection PhpUnusedParameterInspection */ &$old,
        /** @noinspection PhpUnusedParameterInspection */ &$new)
    {
        return true;
    }


    /**
     * @param string         $ownerobject
     * @param string        $type
     *
     * @return array
     */
    protected function GetCustomComponents($ownerobject, $type="all")
    {
        if ( !isset($type) || $type == "" ) {
            $type = "all";
        }
        $cny = GetMyCompany();
        $ret_fields = array();
        $ret_links = array();

        // For SCM owner objects
        $CF_doctypejoin = " ";
        $SL_doctypejoin = " ";
        $custOwnerObj = false;

        $queryArr = array('', $cny, $ownerobject);

        import('DocumentManager');
        $doctype = '';
        if ( $this instanceof self || $this instanceof \RecurDocumentFormEditor ) {
            $doctype = $this->dt;

            $docid = Request::$r->_r;
            if ( $doctype == '' && $docid != '' ) {
                $doctype = GetDocumentType($docid);
            }
            if ( $doctype != '' ) {
                $CF_doctypejoin = " and (cf.doctype = 'ALL' or '#~#'||cf.doctype||'#~#' like '%#~#'||:3||'#~#%') ";
                $SL_doctypejoin = " and (sl.doctype = 'ALL' or '#~#'||sl.doctype||'#~#' like '%#~#'||:3||'#~#%') ";
                $queryArr[] = $doctype;
            }

            if ( $this instanceof \RecurDocumentFormEditor ) {
                $custOwnerObj = true;
            }
        }

        $docMgr = $this->GetManager('document');

        if ( $type == "all" || $type == "customfield" ) {
            // Check whether custom fields exist for this object

            $ownerobject = ($custOwnerObj) ? $this->GetCustomOwnerObject($ownerobject) : $ownerobject;
            $queryArr[2] = $ownerobject;
            $queryArr[4] = 'T';
            $queryArr[5] = getUserLocale();

            $custFldExist = $docMgr->HasCustomFields($ownerobject, $doctype);

            // Do query only if custom fields exist for this object
            if ( $custFldExist ) {
                $qry =
                    "
					select cc.COMPONENTTYPE, cc.PATH, cc.LABEL as OLABEL, cc.HIDDEN, clc.PAGE, 
                                                clc.FIELDSET, cf.OBJECTFIELDID,
                                                cl.LABEL
					from customcomponent cc, customlayoutcomponent clc, customfield cf, customlabel cl
					where
					cf.ownerobject = :2
					$CF_doctypejoin
					and cf.active = :4
					and cc.customfieldkey = cf.record#
					and cc.record# = clc.customcomponentkey
					and cc.cny# = :1
					and clc.cny# = :1
					and cf.cny# = :1
                    and cl.cny#(+) = :1
                    and cl.locale(+) = :5
                    and cl.id(+) = cc.customlabelid                
					order by to_number(substr(cf.OBJECTFIELDID,10))
					";

                $queryArr[0] = $qry;

                $ret_fields = QueryResult($queryArr);

                // TBD :: Let us do a migration for this.
                // After migrating to the new editor, the 'LINE ITEMS' become part of the Header page
                // and the line level custom fields become part of the details window shade section
                // This piece of code is for backward compatibility
                foreach ( $ret_fields as $indx => $value ) {
                    if (isl_strtoupper(isl_trim($value['PAGE'])) === 'LINE ITEMS'
                        || isl_trim($value['PAGE']) === 'IA.LINE_ITEMS'
                        || isl_strtoupper(isl_trim($value['PAGE'])) === 'HEADER'
                        || isl_trim($value['PAGE']) === 'IA.HEADER'
                    ) {
                        if ( $ownerobject === $this->mod . 'document' ) {
                            $ret_fields[$indx]['PAGE'] = I18N::getSingleToken('IA.TRANSACTION');
                        } else if ( $ownerobject === $this->mod . 'documententry' ) {
                            $ret_fields[$indx]['PAGE'] = I18N::getSingleToken('IA.DETAILS');
                        }
                    }
                }
            }
        }
        // Smart Links
        if ( $type === "all" || $type === "smartlink" ) {
            // Check whether smart links exist for this object
            /** @noinspection PhpUndefinedVariableInspection */
            $smartLnkExist = $docMgr->HasSmartLinks($ownerobject, $doctype);

            // Do query only if smart links exist for this object
            if ( $smartLnkExist ) {
                $qry =
                    "
					select cc.COMPONENTTYPE, cc.PATH, cc.LABEL, cc.HIDDEN, clc.PAGE, clc.FIELDSET
					from customcomponent cc, customlayoutcomponent clc, smartlink sl
					where
					sl.ownerobject = :2
					$SL_doctypejoin
					and sl.active = :4
					and cc.smartlinkkey = sl.record#
					and cc.record# = clc.customcomponentkey
					and cc.cny# = :1
					and clc.cny# = :1
					and sl.cny# = :1
					";

                $queryArr[0] = $qry;

                $ret_links = QueryResult($queryArr);

                // TBD :: Let us do a migration for this.
                // After migrating to the new editor, the 'LINE ITEMS' become part of the Header page
                // and the line level custom fields become part of the details window shade section
                // This piece of code is for backward compatibility
                foreach ( $ret_links as $indx => $value ) {
                    if (isl_strtoupper(isl_trim($value['PAGE'])) === 'LINE ITEMS'
                        || isl_trim($value['PAGE']) === 'IA.LINE_ITEMS'
                        || isl_strtoupper(isl_trim($value['PAGE'])) === 'HEADER'
                        || isl_trim($value['PAGE']) === 'IA.HEADER'
                    ) {
                        if ( $ownerobject === $this->mod . 'document' ) {
                            $ret_links[$indx]['PAGE'] = I18N::getSingleToken('IA.TRANSACTION');
                        } else if ( $ownerobject === $this->mod . 'documententry' ) {
                            $ret_links[$indx]['PAGE'] = I18N::getSingleToken('IA.DETAILS');
                        }
                    }
                }
            }
        }
        $ret = INTACCTarray_merge($ret_fields, $ret_links);
        return $ret;
    }


    /**
     * @param array   $obj
     *
     * @return bool
     *
     * @throws Exception
     */
    protected function transformBizObjectToView(&$obj)
    {
        if ( isset($this->dt) ) {
            $obj['DOCPARID'] = $this->dt;
        }
        /**
         * @var DocumentManager $mgr
         */
        $mgr = $this->GetManager($this->getEntity());
        $mgr->prepareForUIEditValues($obj);

        $isnewDoc = ($this->state == $this->kShowNewState) ? true : false;

        $this->getSubTotals($obj, $isnewDoc);

        global $gManagerFactory;

        /**
         * @var DocumentParamsManager   $docparMgr
         */
        $docparMgr =  $gManagerFactory->getManager($this->mod . 'documentparams');
        $docpar = $docparMgr->GetBaseLatest($obj['DOCPARID']);

        $valueFld = 'UIVALUE';
        $totalFld = 'TOTAL';
        if ( $this->ismcpEnabled && $docpar['DISPLAY_BASECURRENCY'] != 'true' ) {
            $valueFld = 'TRX_VALUE';
            $totalFld = 'TRX_TOTAL';
        }
        $itemTotal = 0;
        if ( isset($obj['ENTRIES']) && is_array($obj['ENTRIES']) ) {
            $txnIsVATEnabled = $this->getEntityMgr()->isVATEnabled($obj);
            foreach ($obj['ENTRIES'] as &$entry ) {
                // check if is_numeric and if it is numeric convert to float to fix PHP 8.1 Ticket:166717
                $itemTotal += is_numeric($entry[$valueFld]) ? (float)$entry[$valueFld] : 0;
                if ( $obj['_DOCPAR']['SHOWEXPANDEDTOTALS'] != 'true' ) {
                    $newsubtotalsEntries = array();
                    $subtotalsEntries = $entry['SUBTOTALSENTRY'];
                    if ( isset($subtotalsEntries) && is_array($subtotalsEntries) ) {
                        foreach ( $subtotalsEntries as $subtotalEntry ) {
                            if ( !$subtotalEntry['TAXDETAIL'] || $txnIsVATEnabled) {
                                $newsubtotalsEntries[] = $subtotalEntry;
                            }
                        }
                    }
                    $entry['SUBTOTALSENTRY'] = $newsubtotalsEntries;
                }
            }
            unset($entry);
        }
        $total = $itemTotal;

        $obj['SUMMARY'] = array(
            'TOTAL' => $total,
            'ITEMS' => $itemTotal,
            'WHENDUE' => $obj['WHENDUE'],
            'STATE' => $obj['STATE'],
            'WHENCREATED' => $obj['WHENCREATED'] ?: GetCurrentDate(),
            'PAYSTATE' => $obj['PAYMENTSTATUS'],
        );


        if ( $docpar['SHOW_TOTALS'] == 'true' ) {

            $total = 0;
            $items = 0;

            $subtotals = $obj['SUBTOTALS'];

            foreach ( $subtotals as $subtotal ) {
                if ( $obj['_DOCPAR']['SHOWEXPANDEDTOTALS'] == 'true' || !$subtotal['TAXDETAIL'] ) {
                    if ( $subtotal['DESCRIPTION'] == 'SUBTOTAL' ) {
                        $items = $subtotal[$totalFld];
                    } else if ( $subtotal['DESCRIPTION'] == 'TOTAL' ) {
                        $total = $subtotal[$totalFld];
                    }
                }
            }
            $obj['SUMMARY']['SUBTOTAL'] = $total - $items;
            $obj['SUMMARY']['TOTAL'] = $total;
        }
        $copy = Request::$r->_copymode;
        if( in_array($this->state, array($this->kShowEditState, $this->kShowViewState))
            || ($this->state == $this->kShowNewState && $copy != 'Populate')) {
            global $kSOid, $kPOid, $kINVid;

            $itemMgr = $gManagerFactory->getManager('item');

            $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
            $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');

            GetModulePreferences($modArray[$this->mod], $prefs);
            $appPrecision = ($prefs['ITEMPRECISION']) ?: DEFAULT_INVPRECISION;

            $itemsArr = array();
            foreach ( (($obj['ENTRIES']) ?? []) as $entry ) {
                [$itemid] = explode('--', $entry['ITEMID']);
                $itemsArr[] = $itemid;
            }

            //$uomInfoCache = $itemMgr->GetUOMPrecissionInfo($itemsArr);
            $itemidAsKey = true;
            $uomInfoVals = [];
            if (Util::countOrZero($itemsArr) > 0) {
                $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey, false);
            }

            foreach ( (($obj['ENTRIES']) ?? []) as $key => $entry ) {
                $itemMgr->GetLineEntry_UOMPrecissionInfo($entry, $uomInfoVals, $conversion, $uomPrecission);
                //$conversion 	= $uomInfoVals[$entry['UNIT']]['CONVFACTOR'];
                //$uomPrecission 	= $uomInfoVals[$entry['UNIT']]['NUMDEC'];
                if( !empty($entry['QTY_CONVERTED']) && $entry['QTY_CONVERTED'] != 0) {
                    $obj['ENTRIES'][$key]['QTY_CONVERTED'] = ibcdiv($entry['QTY_CONVERTED'], $conversion, $uomPrecission, true);
                }

                if ( $entry['ITEM'][$precisionFields[$this->mod]] != '' ) {
                    $itemPrecision = $entry['ITEM'][$precisionFields[$this->mod]];
                } else {
                    $itemPrecision = $appPrecision;
                }
                // Ticket: 163688 PHP 8.1 exception
                // For some reason $itemPrecision is setting up as array it should always be numeric
                // so checking if its numeric and if its not defaulting the value to DEFAULT_INVPRECISION
                $itemPrecision = is_numeric($itemPrecision) ? $itemPrecision : DEFAULT_INVPRECISION;

                if(!isset($obj['ENTRIES'][$key]['TEMP_RETAILPRICE'])) {
                    $obj['ENTRIES'][$key]['TEMP_RETAILPRICE'] = $obj['ENTRIES'][$key]['RETAILPRICE'];
                }

                if( $docpar['ENABLE_DISCOUNT_CHARGE'] == 'true') {
                    $obj['ENTRIES'][$key]['RETAILPRICE'] = ibcmul($obj['ENTRIES'][$key]['TEMP_RETAILPRICE'], $conversion, $itemPrecision, false);
                }


                if ( $this->state == $this->kShowViewState ) {
                    $obj['ENTRIES'][$key]['UIPRICE'] = ibcmul($obj['ENTRIES'][$key]['UIPRICE'], '1', $itemPrecision, true);
                    //setting up UIPrice as if the value is 0, it does not respect the itemprecision.
                    if ( $obj['ENTRIES'][$key]['UIPRICE'] == 0 ) {
                        $obj['ENTRIES'][$key]['UIPRICE'] = "0." . str_repeat("0", $itemPrecision);
                    }
                    $obj['ENTRIES'][$key]['UIVALUE'] = ibcmul($obj['ENTRIES'][$key]['UIVALUE'], '1', 2, true);
                    $obj['ENTRIES'][$key]['TRX_PRICE'] = ibcmul($obj['ENTRIES'][$key]['TRX_PRICE'], '1', $itemPrecision, true);
                    if (!is_null($obj['ENTRIES'][$key]['TRX_REVISEDPRICE'])) {
                        $obj['ENTRIES'][$key]['TRX_REVISEDPRICE'] = ibcmul($obj['ENTRIES'][$key]['TRX_REVISEDPRICE'], '1', $itemPrecision, true);
                    }
                }

                if(!empty($obj['ENTRIES'][$key]['TRACKINGENTRIES']['TRACKINGENTRY'])){
                    $obj['ENTRIES'][$key]['TRACKINGENTRIES'] = $obj['ENTRIES'][$key]['TRACKINGENTRIES']['TRACKINGENTRY'];
                }
            }
        }
        if ($this->state === 'showview') {
            $this->encodeIds($obj);
        }
        return true;
    }

    /**
     * @param array $_params
     *
     * @throws Exception
     */
    protected function buildDynamicMetadata(&$_params)
    {
        $mgr = $this->GetManager($this->getEntity());
        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();

        /** @var DocumentManager $docMgr */
        $docMgr = $this->GetManager($this->getEntity());

        $docid = Request::$r->_r;
        $cat = Request::$r->_cat;

        if ( !$this->dt ) {
            if ( $docid ) {
                $rec = $mgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
                $this->dt = $rec[0]['DOCID'];
            } else {
                //the flag _doctypeeditable is used on refresh to decide whether the field is editable
                $this->_doctypeeditable = true;
                $docs = GetDocumentParams($this->mod, $cat);
                $this->dt = $docs[0];
            }
            if ( isset($this->dt) && $this->dt != '' ) {
                Request::$r->_dt = $this->dt;
            }
        }


        // TODO: need to check why this _doctypeeditable is used
        if ($this->dt && !$this->_doctypeeditable) {
            $_params['title'] = htmlspecialchars($this->dt, ENT_QUOTES);
        }

        $action = Request::$r->{$this->kAction};
        $state = Request::$r->_state;

        $isDocEditable = true;
        if ( isset($docid) && $docid != '') {
            $isDocEditable = $docMgr->canEdit($docid);

            // this is set only when the document is fully paid or partially paid
            //$this->_stateEditable = $isDocEditable;
        }

        if ( ($this->do == 'edit' || $this->do == 'view') && !($action == 'new' || $state == 'shownew') ) {
            $this->setAddInfoFieldEditableForConvertedDoc($isDocEditable);
            /** @noinspection PhpUndefinedVariableInspection */
            if ( !$isDocEditable ) {
                Request::$r->_do = 'view';
                $this->do = 'view';
                if ( is_object($this->entityMgr) ) {
                    $this->getEntityMgr()->_canupdate = false;
                }
            }
        }

        $_createdfrom = Request::$r->_createdfrom;
        $isRemoveSrcDocLinkEnabled = ((Request::$r->_removesourcelink ?? '') == '1');
        if(in_array($this->do, array('view','edit')) && !$isRemoveSrcDocLinkEnabled) {
            $r = Request::$r->_r;
            $sourceDocs = $this->getSourceDocs($r);
            if(Util::countOrZero($sourceDocs ?? [])>0) {

                foreach ( $sourceDocs as $sDoc ) {
                    $this->sourceDocsArr[] = $sDoc['DOCID'];
                    $sDocs[] = "['" . $sDoc['DOCID'] . "']";
                }

                $_createdfrom = $multipleSrcDocText;
            } else {
                $params = [
                    'selects' => ['CREATEDFROM'],
                    'filters' => [[
                        ['DOCID', '=', $r],
                        ['CREATEDFROM', 'ISNOTNULL']
                    ]]
                ];

                $result = $docMgr->GetList($params);
                if (Util::countOrZero($result ?? []) > 0) {
                    foreach ($result as $doc) {
                        $this->sourceDocsArr[] = $doc['CREATEDFROM'];
                        $sDocs[] = "['" . $doc['CREATEDFROM'] . "']";
                    }

                    $_createdfrom = $multipleSrcDocText;
                }
            }
        }

        if ( $_createdfrom == $multipleSrcDocText ) {

            global $gManagerFactory;

            $recalledID = Request::$r->{Globals::$g->kId};

            // Copy compatible custom fields from source document to destination document
            $srcdoctype = GetDocumentType($recalledID);

            $srcEntityMgr =  $gManagerFactory->getManager($this->mod . "document", false, array( 'DOCTYPE' => $srcdoctype));

            $objStoreId = Request::$r->_objstoreid;
            /** @var ObjectStoreManager $objectStore */
            $objectStore = $gManagerFactory->getManager('objectstore');
            $objs = $objectStore->get($objStoreId);
            if ( isset($objs['OBJECTDATA']) ) {
                $this->ProcessMultipleSourceTransactions($objs['OBJECTDATA'], $srcEntityMgr);
            }

            $matches = array();
            self::findElements($_params, array('path' => 'CREATEDFROM'), EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches) {
                $propstype = array(
                    'ptype' => 'href',
                    'type' => 'href',
                    'size' => 60,
                    'maxlength' => 60,
                    'multilinecolsepr' => 25,
                    'format' => '/^[\w\s_\-#]{1,60}$/',
                );
                $matches[0]['type'] = $propstype;
                $matches[0]['onclick'] = "ShowSourceDocsMenu();";
                if (Util::countOrZero($this->sourceDocsArr) == 1) {
                    // Source document list popup should not appear in a single document
                    $matches[0]['onclick'] = "LaunchHistoryLink(this);";
                    $matches[0]['value'] = $this->sourceDocsArr[0];
                    $matches[0]['displayValue'] = $this->sourceDocsArr[0];
                }
            }

            $fgrid = array();
            self::findElements($_params, array('id' => 'MULTISOURCES'), EditorComponentFactory::TYPE_SECTION, $fgrid);
            $fgrid = & $fgrid[0];
            if ( $fgrid ) {
                $sDocCnt = count($this->sourceDocsArr);
                //eppp_p($fgrid);dieFL();
                for ( $ix = 0; $ix < $sDocCnt; $ix++ ) {
                    $field = array(
                        'path' => 'SDOCUMENT' . $ix,
                        //'fullname' => $dayLabel,
                        'type' => array(
                            'type' => 'href',
                            'ptype' => 'href',
                            'maxlength' => 6,
                            'size' => '6',
                        ),
                        'onclick' => "LaunchHistoryLink(this);",
                        'value' => $this->sourceDocsArr[$ix],
                        'displayValue' => $this->sourceDocsArr[$ix],
                        'noLabel' => true,
                    );

                    $fgrid['child'][]['field'][] = $field;
                }
            }
        }

        $warehouseFlds = array();
        self::findElements($_params, array('path' => 'WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FIELD, $warehouseFlds);
        if ( $warehouseFlds[0] ) {
            $warehouseFlds[0]['type']['ptype'] = 'ptr';
            $warehouseFlds[0]['type']['type'] = 'text';
            $warehouseFlds[0]['type']['entity'] = 'warehouse';
            $warehouseFlds[0]['type']['addlPickFields'] = array('NAME');
        }

        $unitFld = array();
        self::findElements($_params, array('path' => 'UNIT'), EditorComponentFactory::TYPE_FIELD, $unitFld);
        if ( $unitFld[0] ) {
            $unitFldType = array(
                'ptype' => 'webCombo',
                'type' => 'enum',
                'size' => '5',
            );
            $unitFld[0]['type'] = $unitFldType;
        }

        $priceFld = array();
        self::findElements($_params, array('path' => 'PRICE'), EditorComponentFactory::TYPE_FIELD, $priceFld);
        if ( $priceFld[0] ) {
            $priceFld[0]['type']['type'] = 'decimal';
            $priceFld[0]['type']['ptype'] = 'currency';
            $priceFld[0]['type']['size'] = '16';
        }

        $trxpriceFld = array();
        self::findElements($_params, array('path' => 'TRX_PRICE'), EditorComponentFactory::TYPE_FIELD, $trxpriceFld);
        if ( $trxpriceFld[0] ) {
            $trxpriceFld[0]['type']['type'] = 'decimal';
            $trxpriceFld[0]['type']['ptype'] = 'currency';
            $trxpriceFld[0]['type']['size'] = '16';
            $trxpriceFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $trxpriceFld[0]['nocalc'] = true;
        }

        self::findElements($_params, array('path' => 'TRX_REVISEDPRICE'), EditorComponentFactory::TYPE_FIELD, $trxpriceFld);
        if ( $trxpriceFld[0] ) {
            $trxpriceFld[0]['type']['type'] = 'decimal';
            $trxpriceFld[0]['type']['ptype'] = 'currency';
            $trxpriceFld[0]['type']['size'] = '16';
            $trxpriceFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $trxpriceFld[0]['nocalc'] = true;
        }

        $discMemoFld = array();
        self::findElements($_params, array('path' => 'DISCOUNT_MEMO'), EditorComponentFactory::TYPE_FIELD, $discMemoFld);
        if ( $discMemoFld[0] ) {
            $discMemoFld[0]['type']['type'] = 'text';
            $discMemoFld[0]['type']['showpopup'] = true;
            $discMemoFld[0]['numofrows'] = 3;
        }

        $retailPrcFld = array();
        self::findElements($_params, array('path' => 'RETAILPRICE'), EditorComponentFactory::TYPE_FIELD, $retailPrcFld);
        if ( $retailPrcFld[0] ) {
            $retailPrcFld[0]['type']['ptype'] = 'currency';
            $retailPrcFld[0]['type']['type'] = 'decimal';
            $retailPrcFld[0]['type']['size'] = '16';
            $retailPrcFld[0]['fullname'] = 'IA.SUGGESTED_BR_PRICE';
            $retailPrcFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $retailPrcFld[0]['nocalc'] = true;
        }

        $uipriceFld = array();
        self::findElements($_params, array('path' => 'UIPRICE'), EditorComponentFactory::TYPE_FIELD, $uipriceFld);
        if ( $uipriceFld[0] ) {
            $uipriceFld[0]['type']['type'] = 'decimal';
            $uipriceFld[0]['type']['ptype'] = 'currency';
            $uipriceFld[0]['type']['size'] = '16';
            $uipriceFld[0]['type']['precision'] = $this->lookupAppPrecision();
            $uipriceFld[0]['nocalc'] = true;
        }

        $extendedPrcFld = array();
        self::findElements($_params, array('path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $extendedPrcFld);
        if ( $extendedPrcFld[0] ) {
            $extendedPrcFld[0]['type']['ptype'] = 'currency';
            $extendedPrcFld[0]['type']['type'] = 'decimal';
            $extendedPrcFld[0]['type']['size'] = '16';
            $extendedPrcFld[0]['fullname'] = ($this->mod == 'inv' ? 'IA.EXTENDED_COST' : 'IA.EXTENDED_PRICE');
            $extendedPrcFld[0]['nocalc'] = true;
        }

        $trxextendedPrcFld = array();
        self::findElements($_params, array('path' => 'TRX_VALUE'), EditorComponentFactory::TYPE_FIELD, $trxextendedPrcFld);
        if ( $trxextendedPrcFld[0] ) {
            $trxextendedPrcFld[0]['type']['ptype'] = 'currency';
            $trxextendedPrcFld[0]['type']['type'] = 'decimal';
            $trxextendedPrcFld[0]['type']['size'] = '16';
            $trxextendedPrcFld[0]['nocalc'] = true;
        }

        // Override the function call applyGridDefaults(FormEditor.cls) to applySCMGridDefaults(DocumentFormEditor.cls)  for button 'OK'
        $defgridbutton = array();
        self::findElements($_params, array('name' => 'OK'),  EditorComponentFactory::TYPE_FLOATING_PAGE, $defgridbutton);
        $defgridbutton[0]['events']['click'] =  "applySCMGridDefaults('ENTRIES', 'ENTRIESDefaultsPage', 'ENTRIES_DEFAULTS_PAGE')";

        // Rename warehouse field label
        $defgridwarehouse = array();
        self::findElements($_params, array('path' => 'HEADER_WAREHOUSE.LOCATION_NO'),  EditorComponentFactory::TYPE_FLOATING_PAGE, $defgridwarehouse);
        if( $defgridwarehouse ) {
            $defgridwarehouse[0]['fullname'] = 'IA.WAREHOUSE';
        }

        // add the change event to auto-populate the project information at the line level
        $matches = [];
        self::findElements($_params, array('path' => 'PROJECTID',), EditorComponentFactory::TYPE_FIELD, $matches);
        foreach ( $matches as &$match) {
            $match['events']['change'] .= "onChangeProjectID(this);";
        }

        // add the change event to auto-populate the task information at the line level
        $matches = [];
        self::findElements($_params, array('path' => 'TASKID',), EditorComponentFactory::TYPE_FIELD, $matches);
        foreach ( $matches as &$match ) {
            $match['events']['change'] .= "onChangeTaskID(this);";
        }

        $matches = [];
        self::findElements($_params, array('path' => 'SOURCEDOCID',), EditorComponentFactory::TYPE_FIELD, $matches);
        foreach ( $matches as &$match) {
            $match['events']['change'] .= "onChangeSourceDocID(this);";
        }
        parent::buildDynamicMetadata($_params);
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

    }

    /**
     * Get multiline path, used for platform lookup fields
     *
     * @return string
     */
    protected function getMultilinePath()
    {
        return "ENTRIES";
    }


    /**
     * @param string    $editpolicy
     * @param string[]  $propsval
     * @param string|int|float  $documentTotalPaid
     *
     * @return bool
     */
    protected function isTransactionEditable($editpolicy, $propsval, $documentTotalPaid)
    {

        if ( $editpolicy == 'No Edit' ) {
            return false;
        } else {
            $recalledStates = array("C", "P", "G");
            // if the document is in Converted/Partial state
            $isRecalled = in_array($propsval['STATE'], $recalledStates) ? true : false;

            if ( $isRecalled ) {
                return false;
            }

            // Is Document Printed
            if ( $editpolicy == 'Before Printing' && $propsval['PRINTED'] == 'T' ) {
                return false;
            }

            //Is it paid
            if ( $documentTotalPaid != '' && $documentTotalPaid != 0 ) {
                $this->_stateEditable = true;
                return false;
            }
        }
        return true;
    }

    /**
     * Extract ItemIds and billable ids
     * @param array    $entries     all entries
     * @param number[] $itemIds     out param to collect item IDs
     * @param number[] $billableIds out param to collect all billable IDs
     *
     */
    protected function extractIds($entries,
                                  &$itemIds,
                                  &$billableIds
    )
    {
        $entryCnt = isset($entries) ? count($entries) : 0;
        if ( $entryCnt > 0 ) {
            for ( $i = 0; $i < $entryCnt; $i++ ) {
                $tempItemID = explode("--", $entries[$i]['ITEMID']);
                $itemIds[] = $tempItemID[0];

                if ( isset($entries[$i]['BILLABLETIMEENTRYKEY']) ) {
                    $billableIds['billabletimeentrykeys'][] = $entries[$i]['BILLABLETIMEENTRYKEY'];
                }

                if ( isset($entries[$i]['BILLABLEPRENTRYKEY']) ) {
                    $billableIds['billableprentrykeys'][] = $entries[$i]['BILLABLEPRENTRYKEY'];
                }

                if ( isset($entries[$i]['BILLABLEDOCENTRYKEY']) ) {
                    $billableIds['billabledocentrykeys'][] = $entries[$i]['BILLABLEDOCENTRYKEY'];
                }

                if ( isset($entries[$i]['BILLABLECONTRACTSCHENTRYKEY']) ) {
                    $billableIds['billablecontractschentrykeys'][] =
                        $entries[$i]['BILLABLECONTRACTSCHENTRYKEY'];
                }

                if ( isset($entries[$i]['BILLABLECONTRACTUSAGEBILLINGID']) ) {
                    $billableIds['billablecontractusagebillingids'][] =
                        $entries[$i]['BILLABLECONTRACTUSAGEBILLINGID'];
                }

                if ( isset($entries[$i]['BILLABLEGLENTRYKEY']) ) {
                    $billableIds['billableglentrykeys'][] = $entries[$i]['BILLABLEGLENTRYKEY'];
                }
            }
        }
    }

    /**
     * Finds the header record# and recordtype for line items
     *
     * @param array  $results   out param to get all values for all billable ids
     * @param string $entity    name of the entity
     * @param array  $entrykeys billable IDs
     *
     */
    private function internal_getHdrkeysAndTypes (&$results, $entity, $entrykeys) {
        $select = [];
        $filter = [ 'RECORDNO', 'in', $entrykeys ];

        if ($entity == 'timesheetentry') {
            $select = ['RECORDNO', 'timesheetkey'];
        } else if ($entity == 'prentry') {
            $select = ['RECORDNO', 'recordkey', 'recordtype'];
        } else if ($entity == 'documententry') {
            $select = ['RECORDNO', 'dochdrkey', 'DOCHDRID','SALE_PUR_TRANS'];
        } else if ($entity == 'glentry') {
            $select = ['RECORDNO', 'BATCHNO'];
        }

        $qry = [
            'selects' => $select,
            'filters' => [ [
                               $filter,
                           ] ],
        ];

        $mgr = Globals::$g->gManagerFactory->getManager($entity);
        $results = resultSetToMapByColumn($mgr->GetList($qry),'RECORDNO');
    }

    /**
     * Updates the billable entries/line items with header_record#, recordtype(ei and pi) and
     * showbacklink to help UI to show or hide the "View Source" link.
     *
     * @param array $entries     all entries of the sodocument
     * @param array $billableIds IDs of the billable entries
     *
     */
    protected function updateEntriesWithHdrKeysandTypes (&$entries, $billableIds) {
        $billableTimeRecords = $billablePRRecords = $billableDocRecords = $billableGLRecords = [];
        if (!empty($billableIds)) {
            if (!empty($billableIds['billabletimeentrykeys'])) {
                $this->internal_getHdrkeysAndTypes($billableTimeRecords, 'timesheetentry', $billableIds['billabletimeentrykeys']);
            }
            if (!empty($billableIds['billableprentrykeys'])) {
                $this->internal_getHdrkeysAndTypes($billablePRRecords, 'prentry', $billableIds['billableprentrykeys']);
            }
            if (!empty($billableIds['billabledocentrykeys'])) {
                $this->internal_getHdrkeysAndTypes($billableDocRecords, 'documententry', $billableIds['billabledocentrykeys']);
            }
            if (!empty($billableIds['billableglentrykeys'])) {
                $this->internal_getHdrkeysAndTypes($billableGLRecords, 'glentry', $billableIds['billableglentrykeys']);
            }
            if (!empty($billableIds['billablecontractschentrykeys'])) {}
            if (!empty($billableIds['billablecontractusagebillingids'])) {}

            foreach ($entries as &$entry) {
                $entry['SHOWBACKLINK'] = 0;
                if (isset($entry['BILLABLETIMEENTRYKEY'])) {
                    $entry['BILLABLETIMESHEETKEY'] = $billableTimeRecords[$entry['BILLABLETIMEENTRYKEY']]['TIMESHEETKEY'];
                    $entry['SHOWBACKLINK'] = 1;
                } else if (isset($entry['BILLABLEPRENTRYKEY'])) {
                    $entry['BILLABLEPRRECORDKEY'] = $billablePRRecords[$entry['BILLABLEPRENTRYKEY']]['RECORDKEY'];
                    $entry['BILLABLEPRRECORDTYPE'] = $billablePRRecords[$entry['BILLABLEPRENTRYKEY']]['RECORDTYPE'];
                    $entry['SHOWBACKLINK'] = 1;
                } else if (isset($entry['BILLABLEDOCENTRYKEY'])) {
                    $entry['BILLABLEDOCHDRKEY'] = $billableDocRecords[$entry['BILLABLEDOCENTRYKEY']]['DOCHDRKEY'];
                    $entry['BILLABLEDOCHDRID'] = $billableDocRecords[$entry['BILLABLEDOCENTRYKEY']]['DOCHDRID'];
                    $entry['BILLABLEDOCPARSALEPURTRANS'] = $billableDocRecords[$entry['BILLABLEDOCENTRYKEY']]['SALE_PUR_TRANS'];
                    $entry['SHOWBACKLINK'] = 1;
                } else if (isset($entry['BILLABLECONTRACTSCHENTRYKEY'])) {
                } else if (isset($entry['BILLABLECONTRACTUSAGEBILLINGID'])) {
                } else if (isset($entry['BILLABLEGLENTRYKEY'])) {
                    $entry['BILLABLEGLBATCHNO'] = $billableGLRecords[$entry['BILLABLEGLENTRYKEY']]['BATCHNO'];
                    $entry['SHOWBACKLINK'] = 1;
                }
            }
        }
    }

    /**
     *  Extract ItemIds and billable ids
     *
     * @param string         $entity  entity
     * @param string         $objId   object id
     * @param string         $doctype document type
     * @param string[]|null  $fields  fields
     *
     * @return array
     */
    protected function getEntityData($entity, $objId, $doctype='', $fields=null)
    {

        global $gManagerFactory;

        $obj = parent::getEntityData($entity, $objId, $doctype);

        // this value is needed for the editor in edit mode.
        $qtyConverted = 0;
        $hasPartialConvertedLines = false;
        $noOfConvertedLines = 0;

        // The below code is to avoid the number of queries hitting database.
        // Though we do 3 loops, it is effective than using the oracle resources for query each item.
        $itemIDs = array();
        $entryCnt = isset($obj['ENTRIES']) ? count($obj['ENTRIES']) : 0;
        if ( $entryCnt > 0 ) {
            $billableIds = [];
            $this->extractIds($obj['ENTRIES'], $itemIDs,
                              $billableIds);
            $this->updateEntriesWithHdrKeysandTypes($obj['ENTRIES'], $billableIds);

            if (!empty($itemIDs)) {
                $itemMgr = $gManagerFactory->getManager('item');
                $itemCache = $itemMgr->GetItemsRawCache(array_unique($itemIDs), true);
                $uomInfoVals = $itemMgr->GetUOMInfoCache($itemIDs, true, false);

                for ( $i = 0; $i < $entryCnt; $i++ ) {

                    $tempItemID = explode("--", $obj['ENTRIES'][$i]['ITEMID']);
                    $tempItemID = $tempItemID[0];

                    $itemuoms = array();
                    foreach ( $uomInfoVals[$tempItemID] as $value ) {
                        $itemuoms[] = $value;
                    }

                    $obj['ENTRIES'][$i]['ITEMUOM'] = $itemuoms;
                    $obj['ENTRIES'][$i]['ITEMTYPE'] = $itemCache[$tempItemID]['ITEMTYPE'];
                    $obj['ENTRIES'][$i]['ITEMNAME'] = $itemCache[$tempItemID]['NAME'];
                    $obj['ENTRIES'][$i]['PRODLINE'] = $itemCache[$tempItemID]['PRODUCTLINEKEY'];

                    if($obj['ENTRIES'][$i]['ITEMTYPE'] == 'K') {
                        $obj['ENTRIES'][$i]['ISSERIALIZED'] = $itemMgr->KithasSerializedItems($tempItemID);
                    }else{
                        $obj['ENTRIES'][$i]['ISSERIALIZED'] = $itemCache[$tempItemID]['ISSERIALIZED'];
                    }


                    $precision = null;
                    switch ( $this->mod ) {
                        case 'so':
                            $precision = $itemCache[$tempItemID]['NUMDEC_SALE'];
                            break;

                        case 'po':
                            $precision = $itemCache[$tempItemID]['NUMDEC_PUR'];
                            break;

                        case 'inv':
                            $precision = $itemCache[$tempItemID]['NUMDEC_STD'];
                            break;
                    }
                    if ( $precision || $precision === 0 ) {
                        $obj['ENTRIES'][$i]['ITEM_PRECISION'] = $precision;
                    }
                    if ( $obj['ENTRIES'][$i]['WAREHOUSE']['NAME'] ) {
                        $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] = $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] . '--' . $obj['ENTRIES'][$i]['WAREHOUSE']['NAME'];
                    }

                    if ($this->do!='create' && ($obj['ENTRIES'][$i]['QTY_CONVERTED']) != 0 ) {
                        $hasPartialConvertedLines = true;
                        $noOfConvertedLines += 1;
                        $qtyConverted = $qtyConverted + ibcabs($obj['ENTRIES'][$i]['QTY_CONVERTED']);
                    }
                }
            }
        }

        $obj['HASCONVERTEDLINES'] = ($qtyConverted > 0);
        $obj['HASPARTIALCONVLINES'] = $hasPartialConvertedLines;
        $obj['NOOFCONVERTEDLINES'] = $noOfConvertedLines;

        //$this->getPostingInfo($obj);

        return $obj;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    private function encodeIds(&$obj)
    {
        // Escape these values for the UI before they are displayed, to prevent XSS.
        for ($i = 0, $entryCnt = countArray($obj['ENTRIES']); $i < $entryCnt; $i++) {
            if ($obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']) {
                $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']= isl_htmlspecialchars($obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'], null, null, false);
            }
            if ($obj['ENTRIES'][$i]['ITEMID']) {
                $obj['ENTRIES'][$i]['ITEMID']= isl_htmlspecialchars($obj['ENTRIES'][$i]['ITEMID'], null, null, false);
            }
        }

        return true;
    }

    /**
     * @param array $obj
     *
     * @return array
     */
    protected function getPostingInfo($obj)
    {
        $prrecordkey = $obj['PRRECORDKEY'] ;
        $dochdrkey = $obj['RECORDNO'];
        $showAPARrecs = ( $prrecordkey ? true : false );

        $isGLOperationAllowed = IsOperationAllowed(GetOperationId('gl/lists/glbatch/view'));
        $prglpostingmgr = Globals::$g->gManagerFactory->getManager('prglposting');
        $glLinkReleaseRecords = [];

        // do we have AP/AR posted documents?
        if ( $showAPARrecs ) {
            $viewDetails = I18N::getSingleToken('IA.VIEW_DETAILS');
            $qry1 = "select pr.record# prrecordkey, substr(pr.entity, 2) entity, pr.whencreated, nvl(pr.recordid, '$viewDetails') recordid, pr.docnumber, 
                        pr.trx_totalentered, pr.trx_totalretained, pr.trx_totalreleased, pr.trx_totalpaid, pr.trx_totaldue
                    from prrecordmst pr 
                    where pr.cny# = :1 and pr.record# = :2";
            $prRecord = QueryResult(array($qry1, GetMyCompany(), $prrecordkey));
            if(CRESetupManager::isRetainageBillingEnabled()){
                $qry = "select nvl(sum(de.retainagetobill), 0) retainagebilled
                    from docentry de 
                    where de.cny# = :1 and de.dochdrkey = :2 and de.isretainagerelease = 'T'";
                $retainageBilled = QueryResult(array($qry, GetMyCompany(), $dochdrkey));
                foreach($prRecord as $key=>&$val){
                    if($retainageBilled[$key]){
                        $val += $retainageBilled[$key];
                    }
                }
                unset($val);
            }
            $obj['PR_RECORDS_LIST'] = $prRecord;

            // Include retainage release for Construction-subscribed companies only.
            if ( CRESetupManager::isCREInstalled() ) {
                $qry2 = "select pr.record# PRRECORDKEY, rre.released_prentrykey prentrykey, substr(pr.entity, 2) entity, pr.whencreated, pr.recordid, pr.docnumber, 
                        pr.trx_totalentered, pr.trx_totalretained, sum(rre.trx_amountreleased) trx_totalreleased, pr.trx_totalpaid, pr.trx_totaldue
                    from prrecordmst pr, prentrymst pe, retainagereleaseentry rre
                    where rre.cny# = :1 and rre.dochdrkey = :2
                        and pr.cny# = rre.cny# and pr.record# = rre.released_prrecordkey
                        and pe.cny# = :1 and pe.record# = rre.released_prentrykey
                    group by pr.record#, rre.released_prentrykey, entity, pr.whencreated, pr.recordid, pr.docnumber, 
                             pr.trx_totalentered, pr.trx_totalretained, pr.trx_totalpaid, pr.trx_totaldue
                    order by pr.whencreated";

                $prLinkRecords = QueryResult(array($qry2, GetMyCompany(), $dochdrkey));
                $obj['RELEASED_RECORDS_LIST'] = $prLinkRecords;

                $prentryKeys = [];
                foreach ($prLinkRecords as $prrecord) {
                    if (!isNullOrBlank($prrecord['PRENTRYKEY'])) {
                        $prentryKeys[] = $prrecord['PRENTRYKEY'];
                    }
                }

                // Include offset entries.
                if (!empty($prentryKeys)) {
                    $qry3[0] = "select offsetkey PRENTRYKEY from PRENTRYOFFSETMST 
                            where PRENTRYOFFSETMST.cny# = :1 ";
                    $qry3[] = GetMyCompany();
                    $qry3 = PrepINClauseStmt($qry3, $prentryKeys, " and PRENTRYOFFSETMST.prentrykey ", true, 'prentrykey');

                    $pymtLinkRecords = QueryResult($qry3);

                    foreach ($pymtLinkRecords as $prrecord) {
                        if (!isNullOrBlank($prrecord['PRENTRYKEY'])) {
                            $prentryKeys[] = $prrecord['PRENTRYKEY'];
                        }
                    }
                }

                if (!empty($prentryKeys)) {
                    $releaseGLFilter = [
                        'distinct' => true,
                        'filters' => [[['PRENTRYKEY', 'in', $prentryKeys],]],
                    ];
                    $glLinkReleaseRecords = $prglpostingmgr->GetList($releaseGLFilter);
                    $prglpostingmgr->updateGLPostingDetails($glLinkReleaseRecords, I18N::getSingleToken( 'IA.RETAINAGE_RELEASE'));
                }
            }
        }
        if ( $isGLOperationAllowed ) {
            $glLinkRecords = [];

            if ($showAPARrecs) {
                //get the list of subledger gl postings from shared subledger code
                $invoiceGLFilter = [
                    'distinct' => true,
                    'filters'  => [[[ 'PRRECORDKEY', '=', $prrecordkey ],]],
                ];
                $glLinkRecords = $prglpostingmgr->GetList($invoiceGLFilter);
                $prglpostingmgr->updateGLPostingDetails($glLinkRecords, I18N::getSingleToken('IA.SUBLEDGER_POSTING'));
            }

            //get the list of degl postings
            $deglPostingMgr = Globals::$g->gManagerFactory->getManager('deglposting');
            $deglfilter = [
                'filters'  => [[[ 'DOCHDRKEY', '=', $dochdrkey ],]],
            ];
            $dePostings = $deglPostingMgr->GetList($deglfilter);
            $deglPostingMgr->updateGLPostingDetails($dePostings, I18N::getSingleToken( 'IA.DIRECT_GL'));


            //get the list of prior period cogs adjustments gl postings
            $priorPeriodCOGSPostingMgr = Globals::$g->gManagerFactory->getManager('priorperiodcogsposting');
            $cogsfilter = [
                'filters'  => [[[ 'DOCHDRKEY', '=', $dochdrkey ],]],
            ];
            $cogsPostings = $priorPeriodCOGSPostingMgr->GetList($cogsfilter);
            $priorPeriodCOGSPostingMgr->updateGLPostingDetails($cogsPostings, I18N::getSingleToken('IA.PRIOR_PERIOD_COGS_ADJUSTMENT_POSTING'));

            //get the list of subtotals for gl postings
            $deglSubtotalPostingMgr = Globals::$g->gManagerFactory->getManager('deglsubtotalposting');
            $subtotalPostingfilter = [
                'filters'  => [[[ 'DOCHDRKEY', '=', $dochdrkey ],]],
            ];
            $subtotalPostings = $deglSubtotalPostingMgr->GetList($subtotalPostingfilter);
            $deglSubtotalPostingMgr->updateGLPostingDetails($subtotalPostings, I18N::getSingleToken( 'IA.SUBTOTAL_GL_POSTING'));//khiem search for 'Subtotal GL posting'


            $allpostings  = INTACCTarray_merge($cogsPostings, $glLinkRecords, $dePostings, $subtotalPostings, $glLinkReleaseRecords);
            //sorting
            $sortSymbol = array();
            $sortBatch= array();
            $sortLine= array();
            foreach ($allpostings as $key => $row) {
                $sortSymbol[$key] = $row['SYMBOL'];
                $sortBatch[$key] = $row['GLBATCHNO'];
                $sortLine[$key] = $row['LINENO'];
            }
            array_multisort($sortSymbol, SORT_ASC, $sortBatch, SORT_ASC, $sortLine, SORT_ASC, $allpostings);

            $obj['GL_BATCHES_LIST'] = $allpostings;

            //handle COGS IET properly later
            /*
            if ( $glLinkRecords && ! empty($glLinkRecords) && ! empty($prrecordkey)) {
                $batchRecordNumbers = [];
                foreach ( $glLinkRecords as $key => $glBatch ) {
                    $batchRecordNumbers[] = $glBatch['BATCHNO'];
                }
                //get unique GL batch numbers
                $batchRecordNumbers = array_unique($batchRecordNumbers);
                $glLinkIetRecords = $prglpostingmgr->getIetPostings($batchRecordNumbers, $prrecordkey);

                if ( $glLinkIetRecords ) {
                    $prglpostingmgr->updateGLPostingDetails($glLinkIetRecords,'COGS-IET Posting');
                }
                $obj['GL_BATCHES_IET_LIST'] = $glLinkIetRecords;
            }
            */
        }

        return $obj;
    }

    /**
     * @param string[] $_params
     *
     * @throws Exception
     */
    protected function MergeLayout(&$_params)
    {
        parent::MergeLayout($_params);

        $this->mergeMacroFields($_params);
        $this->mergeMacroHistory($_params);
    }

    /**
     * @param array $_params
     */
    protected function mergeMacroFields(&$_params)
    {
        /**
         * @var DocumentManager $documentManager
         */
        $documentManager = $this->getEntityMgr();
        $macroFields = $documentManager->getMacroFieldInfo();
        $this->macroNames = array();

        if (!empty($macroFields)) {
            $this->macroForDocument = true;
            $this->macroNames = $documentManager->getMacroNames();

            $page =& $_params['view']['child'][0]['pages']['child'][0]['page'];
            foreach ($macroFields as $field) {
                $this->addCustomFieldToLayout($field, $page);
            }

        }

        $entryMgr = $this->getEntryManager();
        $macroFields = $entryMgr->getMacroFieldInfo();
        if (!empty($macroFields)) {
            $this->macroForLines = true;
            $this->macroNames = INTACCTarray_merge($this->macroNames, $entryMgr->getMacroNames());

            $matches = array();
            self::findElements(
                $_params['view'], array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $matches
            );
            $grid = array();
            if (is_array($matches) && count($matches) > 0) {
                $grid = &$matches[0];
            }

            foreach ($macroFields as $field) {
                $field['className'] = 'center';
                $this->translateMacroFieldNames($field);
                $this->addOwnedFieldToLayout($field, $field, $grid, 'ENTRIES');
            }
        }

    }

    /**
     * @param string[] $field passed as reference
     * Translates the Macro field names to the local language
     * @return void
     */
    private function translateMacroFieldNames(&$field) :void
    {
        switch ($field['fullname'] ?? '' ){
            case "Buy to order":
                $field['fullname'] = GT($this->textMap, "IA.BUY_TO_ORDER");
                $field['desc'] = GT($this->textMap, "IA.BUY_TO_ORDER");
                break;
            case "Drop ship":
                $field['fullname'] = GT($this->textMap, "IA.DROP_SHIP");
                $field['desc'] = GT($this->textMap, "IA.DROP_SHIP");
                break;
            default:
                //do nothing;
        }
    }
    /**
     * @return array
     */
    private function getMacroForTargetDoc()
    {
        $macroNames = [];

        // check if the document is created thru macro
        $docType = $this->getEntityMgr()->_docType;

        if ($docType) {
            $qry = 'SELECT DISTINCT name FROM scmmacrohdr sh WHERE cny# = :1 AND priorversionkey IS NULL and EXISTS '
                . ' (SELECT 1 FROM scmmacroentry se, docpar dp WHERE se.cny# = sh.cny# AND '
                . ' se.scmmacrokey = sh.record# AND dp.cny# = se.cny# AND dp.record# = se.targetdocparkey '
                . ' AND dp.docid = :2)';

            $recs = QueryResult(array($qry, GetMyCompany(), $docType));

            if (!empty($recs)) {
                foreach ($recs as $rec) {
                    $macroNames[] = $rec['NAME'];
                }
            }
        }

        return $macroNames;
    }

    /**
     * @param string[]|string[][] $_params
     *
     * @return bool
     * @throws Exception
     */
    protected function mergeMacroHistory(&$_params)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $macroNames = $this->macroNames;

        $targetDocmacros = $this->getMacroForTargetDoc();
        if (!empty($targetDocmacros)) {
            $macroNames = array_merge($macroNames, $targetDocmacros);
        }

        foreach ( $macroNames as $macroName) {
            $forTargetDoc = false;
            if (!in_array($macroName, $this->macroNames)) {
                $forTargetDoc = true;
                $this->docCreatedThruMacro = true;
            }

            $scmResolveManager = $gManagerFactory->getManager('scmmacroresolve');
            $historyFields = $scmResolveManager->getMacroHistoryFields($macroName, $forTargetDoc);
            $macroHistory = 'MACROHISTORY_'.str_replace(" ", "_", $macroName);

            $pages = array();
            self::findElements(
                $_params['view'], array('id' => 'historyPage'), EditorComponentFactory::TYPE_PAGE, $pages
            );

            $page = &$pages[0];
            $page['child'][]['grid'][] = array(
                'path' => $macroHistory, 'readonly' => 'true', 'hidden' => 'true', 'column' => []
            );

            $matches = array();
            self::findElements(
                $_params['view'], array('path' => $macroHistory), EditorComponentFactory::TYPE_GRID, $matches
            );
            $container = &$matches[0];

            foreach ($historyFields as $field) {
                $container['column'][]['field'][] = $field;
            }

        }

        return true;    // php7.1 guessing true is right.  return value is ignored, anyway
    }

    /**
     * Put fields readonly according to the current state of the screen
     *
     * @param EditorField[]   &$fields reference on the view structure
     * @param string $action
     */
    protected function setFieldsReadOnly(&$fields, $action)
    {
        if (isset($fields)) {
            foreach ($fields as &$field) {

                if ($field->getProperty('readonly') || $field->getProperty('disabled')) {
                    continue;
                }

                if ($action == 'readonly') {
                    $field->setProperty('readonly', true);
                } else if ($action == 'readonlyclazz') {
                    $currentClazz = $field->getProperty('clazz', false);

                    if (!$currentClazz || $currentClazz == 'Field') {
                        $field->setProperty('clazz', "MacroLineField");
                    }
                }
            }
        }
    }

    /**
     * @param EditorGrid $grid
     * @param array $line
     * @param string|null $primaryField
     *
     * @return bool
     */
    protected function ignoreLine($grid, $line, $primaryField)
    {
        $action = Request::$r->_action ?? '';
        if (!empty($action) && in_array($action, [self::DRAFT_CREATE, self::DRAFT_SAVE, self::DRAFT_CONTINUE])) {
            $gridPath = $grid->getProperty('path');
            if ($gridPath == 'ENTRIES') {
                // If in Draft mode transaction if primaryField ITEMID is empty we should check for UIQTY value has primaryField to validate and process
                // This required to avaoid the dummy lines from UI
                // Because if we avoid the primary field for draft document, chances of getting the dummy line because of vendor or customer
                // will be their in default for all lines when they select the vendor/customer in header section
                if ($primaryField == 'ITEMID' && (Util::php7eqEmptyStr($line['ITEMID'] ?? ''))) {
                    $primaryField = 'UIQTY';
                }
            }
        }

        return parent::ignoreLine($grid, $line, $primaryField);
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
        $docparmrec = null; // for inspections
        if ( isset($this->dt) && $this->dt != '' ) {
            $docparmrec = $this->GetBaseDocPar();
        }

        if (isset($obj['ENTRIES']) &&
            (isNullOrBlank($obj['_DOCPAR']['ENABLE_RETAINAGE'] ?? null) || ($obj['_DOCPAR']['ENABLE_RETAINAGE'] == 'false'))) {
            // Remove retainage data from non-retainage-enabled documents in case of converting from retainage-enabled documents.
            foreach ($obj['ENTRIES'] as &$entry) {
                if (isset($entry['RETAINAGEPERCENTAGE'])) {
                    $entry['RETAINAGEPERCENTAGE'] = 0;
                }
                if (isset($entry['AMOUNTRETAINED'])) {
                    $entry['AMOUNTRETAINED'] = 0;
                }
                if (isset($entry['TRX_AMOUNTRETAINED'])) {
                    $entry['TRX_AMOUNTRETAINED'] = 0;
                }
            }
        }

        if ($this->affectsOnHandQty === null) {

            // [TR:01/17/2013] affectsOnHandQty is set in documentInitConstants (assuming $this->dt is set).  But to be on the safe side let set it, if it is not set.
            // We should remove this whole block if we never hit this condition in production.

            // In non-live environment, let's just die here.  Please let Tony R or Valer know when this happens.
            dieIfNotLive('affectsOnHandQty is not set in DocumentFormEditor::mediateDataAndMetadata');
            /*
             * We check if a Docparkey Exists for the document to get the Totals Information
             * else we use the base docpar record number to get the Totals Information for
             * the current document that is being Created, Edited or Viewed.
             */
            $recordno = $obj['DOCPARKEY'];
            if ( !$recordno ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $recordno = $docparmrec['RECORDNO'];
            }

            $this->affectsOnHandQty = IsDocumentAffectsOnHandQty($recordno);
        }

        $obj['ARE_ADVANCED_BINS_ON'] = (BinManager::areAdvanedBinsOn() ? 'T' : 'F');
        $obj['IS_INVENTORY_CONFIGED_BIN_CHECKED'] = (BinManager::isInventoryConfigBinChecked() ? 'T' : 'F');

        $isDecrease = (($docparmrec['IN_OUT'] ?? '') == 'Decrease');
        // Sales Quotes are mistakenly marked as INCREASES, like they were a purchase
        if (($docparmrec['SALE_PUR_TRANS'] == "Sale") && ($docparmrec['DOCCLASS'] == "Quote")) {
            $isDecrease = true;  // hack wheeze
        }
        // Retrict the bins shown on the dropdown if this is a sale/outbound/decrease:
        //   only show bins with stuff in them
        $obj['RESTRICT_BINS_BY_QTY'] = ($isDecrease ? 'T' : 'F');

        //Initialize VAT data, this need to happen before header and entries as those functions depend on the VAT data
        $this->mediateDataAndMetadata_VAT($obj);

        $this->mediateDataAndMetadata_Header($obj);

        /** @noinspection PhpUndefinedVariableInspection */
        $this->mediateDataAndMetadata_Entries($obj, $docparmrec);

        $this->mediateDataAndMetadata_Subtotals($obj, $docparmrec);

        $this->mediateDataAndMetadata_History($obj);

        $this->mediateDataAndMetadata_Payments($obj, $docparmrec);

        $this->mediateDataAndMetadata_Macro($obj);

        $this->mediateDataAndMetadata_MacroHistory($obj);

        $this->mediateDataAndMetadata_AdjHistory($obj);

        $this->mediateDataAndMetadata_ConstrictList($obj);

        // handle retainage
        $this->mediateDataAndMetadata_Retainage($obj);

        $this->mediateDataAndMetaData_Additionalinfo($obj);

        $this->mediateDataAndMetaData_fulfillment($obj);

        if ( $this->kShowNewState != $this->state ) {
            if ( $obj['DOCID'] != '' ) {
                $this->setTitleEncoded($obj['DOCID']);
            }
        }

        return parent::mediateDataAndMetadata($obj);
    }


    /**
     * @param array $obj
     * @return true
     */
    protected function removeSrcDocLinkFromDocument(&$obj)
    {
        if(!$this->onChangeSrcDocOptionIsAvailable($obj)){
            return true;
        }

        $isRemoveSrcDocLinkEnabled = ((Request::$r->_removesourcelink ?? '') == '1');
        $createdFrom = $obj['CREATEDFROM'] ?? '';

        if (empty($createdFrom)
            || !$isRemoveSrcDocLinkEnabled
            || (!empty($createdFrom) && $createdFrom == ConversionManager::getmultipleSourceDocsText())) {
            return true;
        }

        $unsetSrcLink = [
            'SOURCE_DOCID',
            'SOURCEDOCPARID',
            'SOURCE_DOCKEY',
            'SOURCE_DOCLINEKEY'
        ];

        $unsetSrcLink[] = 'RECORDNO';
        if (Util::countOrZero($obj['ENTRIES'] ?? []) > 0) {
            foreach ($obj['ENTRIES'] as $key => $entry) {
                foreach ($unsetSrcLink as $field) {
                    if (isset($entry[$field])) {
                        unset($obj['ENTRIES'][$key][$field]);
                    }
                }
            }

            unset($obj['CREATEDFROM']);
        }

        return true;
    }


    /**
     * @param array $obj
     *  To show base currency fields for MCP enabled documents
     */
    protected function mediateDataAndMetaData_handleMultiCurrencyForChangeDocuments(array &$obj)
    {
        $view = $this->getView();
        $entriesView = array();
        if ($this->ismcpEnabled) {
            $view->findAndSetProperty(array('path' => 'ORGDOCORGBASEAMOUNT'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'ORGDOCDRAFTBASEAMT'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'ORGDOCPOSTEDBASEPRICE'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'ORGDOCRVSDBASEVALUE'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'DRAFTEXTBASEPRICE'), array('hidden' => false));
            $view->findAndSetProperty(array('path' => 'POSTEDEXTBASEPRICE'), array('hidden' => false));
            if ($obj['_DOCPAR']['DISPLAY_BASECURRENCY'] === 'true') {
                $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entriesView);
                $entriesView = $entriesView[0];
                $entriesView->findAndSetProperty(array('path' => 'DRAFTCHANGEBASEPRICE'), array('hidden' => false));
                $entriesView->findAndSetProperty(array('path' => 'POSTEDCHANGEEXTBASEPRICE'), array('hidden' => false));
                $entriesView->findAndSetProperty(array('path' => 'REVISEDUNITPRICE'), array('hidden' => false));
                $entriesView->findAndSetProperty(array('path' => 'REVISEDUNITVALUE'), array('hidden' => false));
            }
        } else {
            foreach ($obj['ENTRIES'] as $key => $entry) {
                $obj['ENTRIES'][$key]['TRX_REVISEDPRICE'] = ibcmul($entry['TRX_REVISEDPRICE'], $entry['EXCHRATE'], DEFAULT_INVPRECISION, true);
                $obj['ENTRIES'][$key]['TRX_REVISEDVALUE'] = ibcmul($entry['TRX_REVISEDVALUE'], $entry['EXCHRATE'], DEFAULT_INVPRECISION, true);
                $obj['ENTRIES'][$key]['DRAFTCHANGEPRICE'] = ibcmul($entry['DRAFTCHANGEPRICE'], $entry['EXCHRATE'], DEFAULT_INVPRECISION, true);
                $obj['ENTRIES'][$key]['POSTEDCHANGEEXTPRICE'] = ibcmul($entry['POSTEDCHANGEEXTPRICE'], $entry['EXCHRATE'], DEFAULT_INVPRECISION, true);
            }
        }
    }

    /**
     * @param string[]|string[][]|string[][][]   $obj
     */
    protected function mediateDataAndMetadata_Retainage(&$obj)
    {
        $view = $this->getView();

        // Get the entry grid
        $grid = array();
        $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $grid);
        if (empty($grid) || empty($obj) ) {
            return;
        }
        $grid = $grid[0];

        // retained fields handling..
        if ( $this->isRetainageBeingUsed ) {
            //logStackTraceBrief();
            $view->findAndSetProperty(array('path' => 'RETAINAGEPERCENTAGE'), array('hidden' => false));

            $grid->findAndSetProperty(array('path' => 'RETAINAGEPERCENTAGE'), array('hidden' => false));
            $grid->findAndSetProperty(array('path' => 'AMOUNTRETAINED'), array('hidden' => false));
            $grid->findAndSetProperty(array('path' => 'TRX_AMOUNTRETAINED'), array('hidden' => false, 'readonly' => $view->getProperty('readonly')));

            // For non-MCP we will change the fullname
            if ( !$this->ismcpEnabled ) {
                $grid->findAndSetProperty(array('path' => 'TRX_AMOUNTRETAINED'), array('fullname' => 'IA.AMOUNT_RETAINED'));
            }
        }

    }

    /**
     * @param  array $obj
     */
    protected function mediateDataAndMetaData_Additionalinfo(/** @noinspection PhpUnusedParameterInspection */ &$obj){
        $view = $this->getView();
        if ($this->mod == 'so' || $this->mod == 'po'){
            $docpar = $this->GetBaseDocPar();
            if(in_array($docpar['DOCCLASS'],['Order','Quote'])){
                if($docpar['ENABLEADDINFOSCOPE'] == 'true' || $docpar['ENABLEADDINFOSCOPE'] == 'T' ) {
                    $view->findAndSetProperty([ 'id' => 'scope_section' ], [ 'hidden' => false ],
                                              EditorComponentFactory::TYPE_SECTION);
                }
                if($docpar['ENABLEADDINFOSCHEDULE'] == 'true' || $docpar['ENABLEADDINFOSCHEDULE'] == 'T' ) {
                    $view->findAndSetProperty([ 'id' => 'schedule_section' ], [ 'hidden' => false ],
                                              EditorComponentFactory::TYPE_SECTION);
                }
                if($docpar['ENABLEADDINFOINTERNALREF'] == 'true' || $docpar['ENABLEADDINFOINTERNALREF'] == 'T' ) {
                    $view->findAndSetProperty([ 'id' => 'internalref_section' ], [ 'hidden' => false ],
                                              EditorComponentFactory::TYPE_SECTION);
                }
                if($docpar['ENABLEADDINFOEXTERNALREF'] == 'true' || $docpar['ENABLEADDINFOEXTERNALREF'] == 'T' ) {
                    $view->findAndSetProperty([ 'id' => 'externalref_section' ], [ 'hidden' => false ],
                                              EditorComponentFactory::TYPE_SECTION);
                }
                if($docpar['ENABLEADDINFOBOND'] == 'true' || $docpar['ENABLEADDINFOBOND'] == 'T' ) {
                    $view->findAndSetProperty([ 'id' => 'bond_section' ], [ 'hidden' => false ],
                                              EditorComponentFactory::TYPE_SECTION);
                }
            }
        }
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetaData_fulfillment(/** @noinspection PhpUnusedParameterInspection */ &$obj){
        return true;
    }


    /**
     * @param string[]|string[][]|string[][][]   $obj
     */
    protected function mediateDataAndMetadata_Macro(&$obj)
    {
        // make it non editable if the document has macro link
        if ($this->do == 'edit') {
            if ($this->macroForDocument && $obj['SCMMACROLINK'] == 'T') {

                //Check to see if this is a LC estimate doc and is linked to a LC actual doc. If so, disable fields, otherwise return.
                if (in_array(SCMMacroManager::LCEST, $this->macroNames)) {
                    $isLinkedToLCDoc = false;
                    $obj =& Request::$r->GetCurrentObject();
                    foreach ((($obj['ENTRIESLCEST']) ?? []) as $entry) {
                        if ($entry['LCDOCHDRNO'] || $entry['LCDOCENTRYNO']) {
                            $isLinkedToLCDoc = true;
                            break;
                        }
                    }
                    if (!$isLinkedToLCDoc) {
                        return;
                    }
                }

                $view = $this->getView();

                // Get all the fields
                $allfields = array();
                $view->findComponents(null, EditorComponentFactory::TYPE_FIELD, $allfields);

                $this->setFieldsReadOnly($allfields, 'readonly');
            } else if ($this->macroForLines) {

                $view = $this->getView();

                // Get all the fields from the Grid
                $matches = array();
                $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $matches);

                $allLineFields = array();
                $matches[0]->findComponents(null, EditorComponentFactory::TYPE_FIELD, $allLineFields);

                $this->setFieldsReadOnly($allLineFields, 'readonlyclazz');
            }
        }

    }

    /**
     * @param array   $obj
     *
     * @return bool
     * @throws Exception
     * @throws IAException
     */
    protected function mediateDataAndMetadata_MacroHistory(&$obj)
    {
        if ($this->hideHistoryPage()) {
            return true;
        }

        if ( !$this->macroForDocument && !$this->macroForLines && !$this->docCreatedThruMacro ) {
            return true;
        }

        $macroNames = $this->macroNames;
        $targetDocmacros = $this->getMacroForTargetDoc();
        if (!empty($targetDocmacros)) {
            $macroNames = array_merge($macroNames, $targetDocmacros);
        }

        $gManagerFactory = Globals::$g->gManagerFactory;
        $scmResolveManager = $gManagerFactory->getManager('scmmacroresolve');

        foreach ($macroNames as $macroName) {
            $forTargetDoc = false;
            if (!in_array($macroName, $this->macroNames)) {
                $forTargetDoc = true;
            }

            $macroHistory = 'MACROHISTORY_'.str_replace(" ", "_", $macroName);

            $obj[$macroHistory] = $scmResolveManager->getMacroHistory($macroName, $obj['RECORDNO'], $forTargetDoc);

            if (empty($obj[$macroHistory])) {
                continue;
            }

            $view = $this->getView();

            $historyGrid = array();
            $view->findComponents(array('path' => $macroHistory), EditorComponentFactory::TYPE_GRID, $historyGrid);
            $historyView = $historyGrid[0];

            if ($historyView) {
                $historyView->setProperty('hidden', false);

                $macroTitle = ($macroName == SCMMacroManager::LCEST || $macroName == SCMMacroManager::LCACTANDESTREV
                    || $macroName == SCMMacroManager::LCACTANDEST) ? SCMMacroManager::LANDEDCOST
                    : $macroName;

                $tokens = [
                    [
                        'id'           => 'IA.MACRO_DETAILS',
                        'placeHolders' =>
                            [
                                [ 'name' => 'MACRO', 'value' => $macroTitle ]
                            ],
                    ],
                ];
                $tokenText = I18N::getTokensForArray($tokens);
                $macroTitleText = GT($tokenText, 'IA.MACRO_DETAILS');

                $historyView->setProperty('title', $macroTitleText);
            }

            //Create href links for the cell to the docs in the macro history
            $this->createViewLink_MacroHistory($obj[$macroHistory][0]['SOURCEDOCPARID'], 'SOURCEDOCID', $macroHistory);
            if ($macroName == SCMMacroManager::LANDEDCOST || $macroName == SCMMacroManager::LCACTANDESTREV) {
                $this->createViewLink_MacroHistory($obj[$macroHistory][0]['SOURCEDOCPARID'], 'LANDEDCOSTDOCHDRID', $macroHistory);
            }
            $this->createViewLink_MacroHistory($obj[$macroHistory][0]['TARGETDOCPARID'], 'TARGETDOCID', $macroHistory);

            foreach ($obj[$macroHistory] as &$macroLine) {
                $macroLine['SOURCELINENO']++;
                $macroLine['TARGETLINENO']++;
            }
        }

        return true;
    }

    /**
     * This private function will create an href link for the doc cell passed in.
     *
     * @param string $docParId
     * @param string $docIdFieldName
     * @param string $macroHistory
     *
     */
    private function createViewLink_MacroHistory($docParId, $docIdFieldName, $macroHistory)
    {
        //Make sure we have the ids before we operate
        if (!$docParId || !$docIdFieldName) {
            return;
        }
        $gManagerFactory = Globals::$g->gManagerFactory;
        $docParManager = $gManagerFactory->getManager('documentparams');
        $view = $this->getView();
        $historyGrid = array();
        $view->findComponents(array('path' => $macroHistory), EditorComponentFactory::TYPE_GRID, $historyGrid);
        $historyView = $historyGrid[0];

        $entity = $docParManager->getEntityFromDocType($docParId, $mod);

        $docFields = [];
        $historyView->findComponents(['path' => $docIdFieldName], EditorComponentFactory::TYPE_FIELD, $docFields);

        $docviewop = GetOperationId("$mod/lists/$entity/view");
        foreach ( $docFields as $docidField ) {
            $docidField->setProperty('onclick', "LaunchDocumentLink(this, $docviewop, '$mod');");
        }
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata_AdjHistory(&$obj)
    {
        if ($this->hideHistoryPage()) {
            return true;
        }

        if ($obj['_DOCPAR']['UPDATES_INV'] == 'No' || $obj['_DOCPAR']['UPDATES_INV'] == 'Quantity') {
            return true;
        }

        $gManagerFactory = &Globals::$g->gManagerFactory;
        $invdocMgr = $gManagerFactory->getManager('invdocument');

        $filters = array(
            array(
                array(
                    'RECORDNO', 'CASE_CONDITION', array(
                    ' EXISTS (SELECT 1 FROM docentrymst WHERE cny#=invdocument.cny# AND '.
                    ' dochdrkey=invdocument.record# AND adjdochdrkey=?)',
                    array($obj['RECORDNO']),
                ),
                ),
            ),
        );

        if (in_array(SCMMacroManager::LCEST, $this->macroNames)
            || (in_array(SCMMacroManager::LANDEDCOST, $this->macroNames)
                && !empty($obj['MACROHISTORY']))
        ) {
            $filters[0][] = array('DOCPARID', 'NOT IN', array(InvDocumentManager::LANDEDCOSTESTDOCTYPE));
        }

        $params = array(
            'selects' => array('DOCID', 'WHENCREATED', 'WHENMODIFIED', 'CREATEDUSERID', 'USERID', 'TOTAL'),
            'columnaliases' => array('VIRTUALDOCID', 'WHENCREATED', 'WHENMODIFIED', 'CREATEDUSERID', 'USERID', 'TOTAL'),
            'filters' => $filters,
            'orders' => array(
                array('WHENCREATED', 'asc'), array('DOCID', 'asc')
            )
        );

        $recs = $invdocMgr->GetList($params);

        if (!empty($recs)) {
            $obj['ADJHISTORY'] = $recs;

            $view = $this->getView();

            $historyGrid = array();
            $view->findComponents(array('path' => 'ADJHISTORY'), EditorComponentFactory::TYPE_GRID, $historyGrid);
            $historyView = $historyGrid[0];

            $historyView->setProperty('hidden', false);

            $docFields = array();
            $historyView->findComponents(
                array('path' => 'VIRTUALDOCID'), EditorComponentFactory::TYPE_FIELD, $docFields
            );

            $docviewop = GetOperationId("inv/lists/invdocument/view");
            foreach ( $docFields as $docidField) {
                $docidField->setProperty('onclick', "LaunchDocumentLink(this, $docviewop, 'inv');");
            }

        }
        return true;
    }

    /**
     * If this company has TAXES configured, we need to initialize the VAT data as other logic to follow will need it.
     *
     * @param array $obj the transaction date to get VAT data initializations
     *
     * @throws Exception
     */
    protected function mediateDataAndMetadata_VAT(&$obj)
    {
        $copymode = Request::$r->_copymode;
        $copyConvertStates = ['Update', 'Copy'];

        //Check to see if company has taxes subscribed otherwise just bail out
        if (!TaxSetupManager::isTaxModuleConfigured()) {
            return;
        }
        $obj['COMISVATENABLED'] = TaxSetupManager::isVATEnabled();
        $isPymtTaxSupported = $this->getEntityMgr()->isPaymentTaxCaptureSupported();
        $isPymtTaxEnabled = PaymentUtils::isOEPOPaymentTaxCaptureSupported($obj);

        //Initialize the tax solution fields (TAXSOLUTIONID, TAXSOLUTIONKEY, TAXMETHOD, SHOWMULTILINETAX)
        //base on sliding into entity, single jurisdiction, or single entity company, and TD has at least
        //one ISTAX line. If none, we don't need to initialize the tax solution  fields.
        if ($this->state == $this->kShowNewState
            && DocumentManager::hasTaxSubTotals($obj['_DOCPAR'])) {
            if (TaxSetupManager::isSingleTaxJurisdictionConfigured()) {
                //In single jusrisdiction or standard company, we should only have one tax solution set up, so use that
                TaxSolutionManager::getTaxInfoForSingleJurisdiction(
                    $this->getEntityMgr()->getTaxImplicationTaxMethods(),$obj);
            } else if (!IsRoot()) {
                //At entity level, use the tax solution from the entity, except for new docs created via copy or convert
                if ( in_array($copymode, $copyConvertStates) ) {
                    $obj['TAXSOLUTIONID'] = null;
                }
                TaxSolutionManager::getTaxInfoForCurEntityLevel(
                    $this->getEntityMgr()->getTaxImplicationTaxMethods(), $obj);
            } else {
                //We are at root level so tax solution id is entered by users so we shouldn't need
                //to do anything here. Also, when we press the Calculate Subtotals button on the UI
                //form, we refresh the screen which will reinit all the data in memory. So, DO NOT
                //reinit the fields TAXSOLUTIONID, TAXSOLUTIONKEY, TAXMETHOD, SHOWMULTILINETAX.
            }
        }
        //Reset payment tax capture for not supported transactions
        if ( in_array($copymode, $copyConvertStates)
             && in_array("true", array_column($obj['ENTRIES'], 'PAYMENTTAXCAPTURE'))
             && ! ( $isPymtTaxSupported && $isPymtTaxEnabled ) ) {
            foreach ( $obj['ENTRIES'] as &$entry ) {
                $entry['PAYMENTTAXCAPTURE'] = 'false';
            }
        }
        $obj['TXNISVATENABLED'] = $this->getEntityMgr()->isVATEnabled($obj);
    }

    /**
     * @param array   $obj
     *
     * @throws Exception
     */
    protected function mediateDataAndMetadata_Header(&$obj)
    {

        global $gManagerFactory, $gErr;
        $kAVAid = Globals::$g->kAVAid;

        $view = $this->getView();
        $state = $this->getState();
        $this->mediateDataAndMetadata_DefaultEntries($obj);
        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();

        $headersections = array();
        $view->findComponents(array('id' => 'mainPage'), EditorComponentFactory::TYPE_TAB, $headersections);
        $headersection = $headersections[0];

        $trxSummarySection = array();
        $view->findComponents(array('id' => 'trxSummary'), EditorComponentFactory::TYPE_TAB, $trxSummarySection);
        $trxSummarySection = $trxSummarySection[0];

        if ( $view->getProperty('readonly') && $obj['CUSTVENDNAME'] ) {
            $custId = explode('--', $obj['CUSTVENDID']);
            $trxSummarySection->setProperty('title', isl_htmlspecialchars($obj['CUSTVENDNAME']) . ' (' . isl_htmlspecialchars($custId[0]) . ')');
        }
        $postingdoc = false;

        if(($obj['_DOCPAR']['UPDATES_GL'] == 'A' || $obj['_DOCPAR']['UPDATES_GL'] == 'G') && in_array($obj['STATE'],DocumentManager::POSTED_DOC_STATES)){
            $postingdoc = true;
        }

        // if we dont have any posting data then hide the posting details tab
        if ( $this->state == $this->kShowViewState
            && (!empty($obj['GL_BATCHES_LIST']) || !empty($obj['PR_RECORDS_LIST']) || !empty($obj['RELEASED_RECORDS_LIST']) || !empty($obj['ORGDOCS']) || $postingdoc) )
        {
            $postingTab = array();
            $view->findComponents(array('id' => 'postingDetailsPage'), EditorComponentFactory::TYPE_TAB, $postingTab);
            $postingTab = $postingTab[0];
            if (!isNullOrBlank($postingTab)) {
                $postingTab->setProperty('hidden', false);
                $postingTab->setProperty('readonly', true);
            }


            // unhide prrecord grid
            $glbatchGrid = array();
            $view->findComponents(array('path' => 'PR_RECORDS_LIST'), EditorComponentFactory::TYPE_GRID, $glbatchGrid);
            $glbatchGrid = $glbatchGrid[0];
            if (!isNullOrBlank($glbatchGrid)) {
                if (!empty($obj['PR_RECORDS_LIST']) && count($obj['PR_RECORDS_LIST']) > 0) {
                    $glbatchGrid->setProperty('hidden', false);
                }
            }

            if( CRESetupManager::isCREInstalled() ){
                $changeTab = array();
                $view->findComponents(array('id' => 'changeDocumentsPage'), EditorComponentFactory::TYPE_TAB, $changeTab);
                $changeTab = $changeTab[0];
                $enableDocChange=$obj['_DOCPAR']['ENABLEDOCCHANGE'];
                if (!isNullOrBlank($changeTab) && $enableDocChange !== "No Change") {
                    $changeTab->setProperty('hidden', false);
                    $changeTab->setProperty('readonly', true);
                }

                // unhide released prrecord grid
                $glbatchGrid = array();
                $view->findComponents(array('path' => 'RELEASED_RECORDS_LIST'), EditorComponentFactory::TYPE_GRID, $glbatchGrid);
                $glbatchGrid = $glbatchGrid[0];
                if (!isNullOrBlank($glbatchGrid)) {
                    if (!empty($obj['RELEASED_RECORDS_LIST']) && count($obj['RELEASED_RECORDS_LIST']) > 0) {
                        $glbatchGrid->setProperty('hidden', false);
                    }
                }
            }else{
                $totalRetained = array();
                $view->findComponents(array('path' => 'TRX_TOTALRETAINED'), EditorComponentFactory::TYPE_FIELD, $totalRetained);
                $totalRetained = $totalRetained[0];
                if (isset($totalRetained)) {
                    $totalRetained->setProperty('hidden', true);

                }
                $totalReleased = array();
                $view->findComponents(array('path' => 'TRX_TOTALRELEASED'), EditorComponentFactory::TYPE_FIELD, $totalReleased);
                $totalReleased = $totalReleased[0];
                if (isset($totalReleased)) {
                    $totalReleased->setProperty('hidden', true);

                }
            }
        }

        //parent::Editor_Instantiate($_params);

        if (Request::$r->_popup) {
            $obj = Request::$r->GetCurrentObject();
            $this->dt = $obj['DOCPARID'];
        }

        $error = Request::$r->_errorTimeStamp;
        $entID = Request::$r->_entid;
        $date = Request::$r->_date;
        $recalled = Request::$r->_r;
        $copy = Request::$r->_copymode;

        $this->priceFetchDisabled = ($recalled != '' && $copy == 'Update');


        $docpar = $this->GetBaseDocPar();

        $mgr = $this->GetManager($this->getEntity());

        $billtoPropVals = array();

        $shiptoPropVals = $billtoPropVals;

        // if we have the latest contact version, hide the refresh button
        $billtoPropVals['hiderefresh'] = IsLatestContactVersion($obj['BILLTOKEY'], $obj['BILLTO']['CONTACTNAME']);
        $shiptoPropVals['hiderefresh'] = IsLatestContactVersion($obj['SHIPTOKEY'], $obj['SHIPTO']['CONTACTNAME']);

        $billtoPropVals['disabled'] =
            ('' === $docpar['ALLOWEDITBILLTO'] || 'false' === $docpar['ALLOWEDITBILLTO']);

        // first set Bill to label.
        $billtoPropVals['fullname'] = $docpar['CONTACTTITLE1'];
        $headersection->findAndSetProperty(array('path' => 'BILLTO.CONTACTNAME'), $billtoPropVals);

        //Hide coordinates in billto & shipto if Avalara not enabled or coordinates not enabled
        if($this->state == $this->kShowNewState || $this->state == $this->kShowEditState || $this->state == $this->kShowViewState){
            $avaSubscribed = IsModuleIdInstalled($kAVAid);
            $pickfield = array( 'CONTACTNAME','MAILADDRESS.ADDRESS1', 'MAILADDRESS.ADDRESS2', 'MAILADDRESS.ADDRESS3', 'MAILADDRESS.CITY', 'MAILADDRESS.STATE','MAILADDRESS.ZIP', 'MAILADDRESS.COUNTRY',"EMAIL1");
            //If it is using VAT tax method, we need to display taxid. Call isVATEnabled() method for new or edit state
            if (TaxSetupManager::isVATEnabled()) {
                $pickfield[] = 'TAXID';
            }
            GetModulePreferences($kAVAid, $preferences);
            $pref = 'AVA_ENABLE_'.strtoupper($this->mod);
            if (!$avaSubscribed || !($avaSubscribed && $preferences['AVA_ENABLE_COORDINATES'] == 'T' && $preferences[$pref] == 'T')) {
                $billtoContact = [];
                $view->findComponents(array('path' => 'BILLTO.CONTACTNAME'), EditorComponentFactory::TYPE_FIELD, $billtoContact);
                if (isset($billtoContact[0])) {
                    $billtoContact[0]->setProperty(array('type', 'pickfield'), $pickfield);
                }
                $shiptoContact = [];
                $view->findComponents(array('path' => 'SHIPTO.CONTACTNAME'), EditorComponentFactory::TYPE_FIELD, $shiptoContact);
                if (isset($shiptoContact[0])) {
                    $shiptoContact[0]->setProperty(array('type', 'pickfield'), $pickfield);
                }
            } else {
                //Get & set lat/long values for billto & shipto
                if($this->state == $this->kShowEditState || $this->state == $this->kShowViewState){
                    $contactMgr =  $gManagerFactory->getManager('contact');
                    $billTo = $contactMgr->get($obj['BILLTO']['CONTACTNAME']);
                    $shipTo = ($obj['BILLTO']['CONTACTNAME'] == $obj['SHIPTO']['CONTACTNAME']) ? $billTo: $contactMgr->get($obj['SHIPTO']['CONTACTNAME']);
                    $obj['BILLTO']['MAILADDRESS']['LATITUDE'] = $billTo['MAILADDRESS']['LATITUDE'];
                    $obj['BILLTO']['MAILADDRESS']['LONGITUDE'] = $billTo['MAILADDRESS']['LONGITUDE'];
                    $obj['SHIPTO']['MAILADDRESS']['LATITUDE'] = $shipTo['MAILADDRESS']['LATITUDE'];
                    $obj['SHIPTO']['MAILADDRESS']['LONGITUDE'] = $shipTo['MAILADDRESS']['LONGITUDE'];
                }
            }
        }

        $shiptoPropVals['disabled'] =
            ('' === $docpar['ALLOWEDITSHIPTO'] || 'false' === $docpar['ALLOWEDITSHIPTO']);

        // next set Ship to Label.
        $shiptoPropVals['fullname'] = $docpar['CONTACTTITLE2'];
        $headersection->findAndSetProperty(array('path' => 'SHIPTO.CONTACTNAME'), $shiptoPropVals);
        $billToEmail = '';
        if (!empty($obj['BILLTO']['EMAIL1'])) {
            $billToEmail = isl_htmlspecialchars($obj['BILLTO']['EMAIL1']);
        }

        $obj['BILLTOADDRESS'] = '';
        if ((!empty($obj['BILLTO']['MAILADDRESS'])) || $billToEmail) {
            $obj['BILLTOADDRESS'] .= ( $obj['BILLTO']['MAILADDRESS']['ADDRESS1']) ? isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['ADDRESS1']): '';
            $br = ($obj['BILLTOADDRESS']) ? '<BR>' : '';
            $obj['BILLTOADDRESS'] .= ( $obj['BILLTO']['MAILADDRESS']['ADDRESS2']) ? $br.isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['ADDRESS2']): '';

            if (DocumentManager::isAddressLineThreeEnabled()) {
                $obj['BILLTOADDRESS'] .= ($obj['BILLTO']['MAILADDRESS']['ADDRESS3']) ? $br . isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['ADDRESS3']) : '';
            }

            if ($obj['BILLTO']['MAILADDRESS']['CITY']  ||  $obj['BILLTO']['MAILADDRESS']['STATE']  ||  $obj['BILLTO']['MAILADDRESS']['ZIP'] || $obj['BILLTO']['MAILADDRESS']['COUNTRY']) {
                $obj['BILLTOADDRESS'] .= '<BR>';
            }
            $obj['BILLTOADDRESS'] .= ( $obj['BILLTO']['MAILADDRESS']['CITY']) ? isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['CITY']) . ", " : '';
            $obj['BILLTOADDRESS'] .= ( $obj['BILLTO']['MAILADDRESS']['STATE']) ? isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['STATE']) . " " : '';
            $obj['BILLTOADDRESS'] .= ($obj['BILLTO']['MAILADDRESS']['ZIP']) ? isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['ZIP']) . " " : ' ';
            $obj['BILLTOADDRESS'] .= ($obj['BILLTO']['MAILADDRESS']['COUNTRY']) ? isl_htmlspecialchars($obj['BILLTO']['MAILADDRESS']['COUNTRY']) : '';
            //Display co-ordinates in address
            $br = ($obj['BILLTOADDRESS']) ? '<BR>' : '';
            if( isset($obj['BILLTO']['MAILADDRESS']['LATITUDE']) || isset($obj['BILLTO']['MAILADDRESS']['LONGITUDE']) &&
                IsModuleIdInstalled($kAVAid)){
                GetModulePreferences($kAVAid, $preferences);
                $pref = 'AVA_ENABLE_'.strtoupper($this->mod);
                if ($preferences['AVA_ENABLE_COORDINATES'] == 'T' && $preferences[$pref] == 'T') {
                    $obj['BILLTOADDRESS'] .= ( $obj['BILLTO']['MAILADDRESS']['LATITUDE']) ? $br.isl_htmlspecialchars('Latitude: '.$obj['BILLTO']['MAILADDRESS']['LATITUDE']) : '';
                    $obj['BILLTOADDRESS'] .= ( $obj['BILLTO']['MAILADDRESS']['LONGITUDE']) ? '<BR>'.isl_htmlspecialchars('Longitude: '.$obj['BILLTO']['MAILADDRESS']['LONGITUDE']) : '';
                }
            }

            $obj['BILLTOADDRESS'] .= ( $billToEmail) ? $br.'<A href="mailto:'.isl_htmlspecialchars($billToEmail).'">'.isl_htmlspecialchars($billToEmail).'</A>': '';
        }
        $shipToEmail = '';
        if (!empty($obj['SHIPTO']['EMAIL1'])) {
            $shipToEmail = isl_htmlspecialchars($obj['SHIPTO']['EMAIL1']);
        }

        $obj['SHIPTOADDRESS'] = '';
        if ((!empty($obj['SHIPTO']['MAILADDRESS'])) || $shipToEmail) {
            $obj['SHIPTOADDRESS'] .= ( $obj['SHIPTO']['MAILADDRESS']['ADDRESS1']) ? isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['ADDRESS1']) . "\n" : '';
            $br = ($obj['SHIPTOADDRESS']) ? '<BR>' : '';
            $obj['SHIPTOADDRESS'] .= ( $obj['SHIPTO']['MAILADDRESS']['ADDRESS2']) ? $br.isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['ADDRESS2']) . "\n" : '';

            if (DocumentManager::isAddressLineThreeEnabled()) {
                $obj['SHIPTOADDRESS'] .= ($obj['SHIPTO']['MAILADDRESS']['ADDRESS3']) ? $br . isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['ADDRESS3']) . "\n" : '';
            }

            if ($obj['SHIPTO']['MAILADDRESS']['CITY'] ||  $obj['SHIPTO']['MAILADDRESS']['STATE']  ||  $obj['SHIPTO']['MAILADDRESS']['ZIP'] || $obj['SHIPTO']['MAILADDRESS']['COUNTRY']) {
                $obj['SHIPTOADDRESS'] .= '<BR>';
            }
            $obj['SHIPTOADDRESS'] .= ( $obj['SHIPTO']['MAILADDRESS']['CITY']) ? isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['CITY']) . ", " : '';
            $obj['SHIPTOADDRESS'] .= ( $obj['SHIPTO']['MAILADDRESS']['STATE']) ? isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['STATE']) . " " : '';
            $obj['SHIPTOADDRESS'] .= ($obj['SHIPTO']['MAILADDRESS']['ZIP']) ? isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['ZIP']) . " " : '';
            $obj['SHIPTOADDRESS'] .= ($obj['SHIPTO']['MAILADDRESS']['COUNTRY']) ? isl_htmlspecialchars($obj['SHIPTO']['MAILADDRESS']['COUNTRY']) : '';

            //Display co-ordinates in address
            $br = ($obj['SHIPTOADDRESS']) ? '<BR>' : '';
            if( isset($obj['SHIPTO']['MAILADDRESS']['LATITUDE']) || isset($obj['SHIPTO']['MAILADDRESS']['LONGITUDE']) &&
                IsModuleIdInstalled($kAVAid)){
                GetModulePreferences($kAVAid, $preferences);
                $pref = 'AVA_ENABLE_'.strtoupper($this->mod);
                if ($preferences['AVA_ENABLE_COORDINATES'] == 'T' && $preferences[$pref] == 'T') {
                    $obj['SHIPTOADDRESS'] .= ( $obj['SHIPTO']['MAILADDRESS']['LATITUDE']) ? $br.isl_htmlspecialchars('Latitude: '.$obj['SHIPTO']['MAILADDRESS']['LATITUDE']) : '';
                    $obj['SHIPTOADDRESS'] .= ( $obj['SHIPTO']['MAILADDRESS']['LONGITUDE']) ? '<BR>'.isl_htmlspecialchars('Longitude: '.$obj['SHIPTO']['MAILADDRESS']['LONGITUDE']) : '';
                }
            }

            $obj['SHIPTOADDRESS'] .= ( $shipToEmail) ? $br.'<A href="mailto: '.isl_htmlspecialchars($shipToEmail).'">'.isl_htmlspecialchars($shipToEmail).'</A>': '';

        }

        //Get the tax engine to be used for tax calculation and preserve in $obj for later use
        //Vat fields are enabled for Ava Tax configured company only
        $taxEngineVatOn = false;
        $taxEngineForCalc = GetTaxEngine($this->mod,$obj['TAXSOLUTIONID'],$taxEngineVatOn);
        $obj['_isVatEnabled'] = $taxEngineVatOn;
        $obj['_taxEngine'] = $taxEngineForCalc;

        if ( $recalled && $state == $this->kShowNewState ) {

            // Get the recalled doctype
            // first make sure the source object exists
            $raw = $this->copyToAdapter->getSourceManager($this)->GetRaw($recalled);

            $ok = isset($raw[0]);

            if ( !$ok ) {
                if($copy == 'Update'){
                    $label = 'Convert';
                    $errorCode = 'INV-0362';
                }
                else{
                     $label = 'Copy';
                     $errorCode = 'INV-0363';
                }
                $msg = 'No transaction with the ID ' . $recalled . ' exists.';
                $gErr->addIAError(
                    $errorCode, __FILE__ . ':' . __LINE__,
                    'Unable to ' . $label, [],
                    $msg, ['RECALLED' => $recalled],
                    'Please use a valid transaction as your source.', []
                );
                $ok = false;
            } else {
                $ignore = $obj['IGNORE_STATUS_CHECK'] ?? false;
                if (($copy == 'Update') && ( ! $ignore)) {
                    $ok = ConversionManager::isDocumentConvertable($recalled);
                }
            }

            if ( !$ok ) {
                include_once 'popuperror.phtml';
                exit();
            }
        }

        // 1 - Get the customer/vendor
        $entType = ($this->mod == 'so') ? 'customer' : 'vendor';

        if ( $entID == '' ) {
            $entID = $obj['CUSTVENDID'];
        }

        if ( $entID != '' ) {
            [$entVID] = explode('--', $entID);
            $qry = 'QRY_DOCUMENT_GET_' . isl_strtoupper($entType) . '_FOR_EDIT';
            $entData = $mgr->DoQuery($qry, array($entVID));
            $entData = $entData[0];
        }

        if ( $entType == 'vendor' ) {
            // LOOP all fields
            global $kAPid;
            $billNoPref = GetPreferenceForProperty($kAPid, 'BILLNOREQUIRED');
            $billnorequired = ($billNoPref && $docpar['SALE_PUR_TRANS'] == 'Purchase' && $docpar['UPDATES_GL'] == 'A');
            if ( $billnorequired ) {
                $headersection->findAndSetProperty(array('path' => 'VENDORDOCNO'), array('required' => 'true'));
            }
            $form1099 = '';
            /** @noinspection PhpUndefinedVariableInspection */
            if( $entData && isset($entData['FORM1099TYPE']) && isset($entData['FORM1099BOX'])) {
                $form1099 = $entData['FORM1099TYPE'] .'@'.$entData['FORM1099BOX'];
            }
            $view->setProperty('checkForm1099', $form1099);
            //Used in documenteditor_new.js file to check if vendor is approved state.
            $obj['VENDORSTATE'] = $entData['STATE'];
            $obj['ALWAYSCREATEBILL'] = $entData['ALWAYSCREATEBILL'];
        } else if ( $entType == 'customer' ) {
            $kSFORCE2id = Globals::$g->kSALESFORCE2id;
            if( !IsModuleIdInstalled($kSFORCE2id) ){
                $sfismcp = GetPreferenceForProperty('38.SFDC', 'SFORCEISMCP');
            }else {
                $sfismcp = GetPreferenceForProperty($kSFORCE2id, 'SFORCEISMCP');
            }
        }

        if ( !$obj['WHENCREATED'] && $this->state == $this->kShowNewState ) {
            $obj['WHENCREATED'] = GetCurrentDate();
            $date = $obj['WHENCREATED'];
        } else if ( !$obj['WHENCREATED'] && $date ) {
            $obj['WHENCREATED'] = $date;
        }

        // TODO: For GA move this to ent.
        /** @noinspection PhpUndefinedVariableInspection */
        $headersection->findComponents(array( 'path' => 'MESSAGE'), EditorComponentFactory::TYPE_FIELD, $messageFld);
        /**
         * @var EditorComponent[] $messageFld
         */
        if ( $messageFld[0] ) {
            $messageFldType = $messageFld[0]->getProperty('type');
            $messageFldType['type'] = 'text';
            $messageFldType['showpopup'] = true;
            $messageFld[0]->setProperty('type', $messageFldType);
            $messageFld[0]->setProperty('numofrows', 5);
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $headersection->findComponents(array( 'path' => 'TERM.NAME'), EditorComponentFactory::TYPE_FIELD, $termfld);
        /**
         * @var EditorComponent[] $termfld
         */
        if ( $termfld[0] ) {

            if ( $docpar['SALE_PUR_TRANS'] == 'Internal' ) {
                $termfld[0]->setProperty('hidden', true);
            } else {

                $termfldtype = $termfld[0]->getProperty('type');

                $termmod = ($this->mod == 'so') ? 'ar' : 'ap';
                $termfldtype['entity'] = $termmod . 'term';
                $termfld[0]->setProperty('type', $termfldtype);

                if ( $this->state == $this->kShowNewState ) {
                    if ( $obj['TERM']['NAME'] != '' ) {
                        $termMgr = $gManagerFactory->getManager($termfldtype['entity']);
                        $term = $termMgr->GetRaw($obj['TERM']['NAME']);
                        $term = $term[0];
                    } else {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $termKey = ( $entData['TERMSKEY'] != '') ? $entData['TERMSKEY'] : $docpar['TERMKEY'];
                        if ( $termKey != '' ) {
                            GetTerm($termKey, $term);
                        }
                    }

                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( $term ) {
                        $obj['TERM']['NAME'] = $term['NAME'];

                        if ( !$date ) {
                            $date = $obj['WHENCREATED'];
                        }
                        // Calculate duedate for all type documents OR
                        // If coming from SFDC and term is mapped from SFDC via fieldmap
                        $duedate = CalcDueDate($date, $term['VALUE']);
                    }
                }
            }
        }

        if ( ($docpar['DOCCLASS'] == 'Order' || $docpar['CATEGORY'] == 'Shipping') && $docpar['SALE_PUR_TRANS'] == 'Sale' ) {
             $headersection->findAndSetProperty(array('path' => 'WHENDUE'), array('fullname' => 'IA.SHIP_DATE', 'desc' => 'IA.SHIP_DATE'));
        } else if ( $docpar['DOCCLASS'] == 'Quote' ) {
             $headersection->findAndSetProperty(array('path' => 'WHENDUE'), array('fullname' => 'IA.EXPIRATION_DATE', 'desc' => 'IA.EXPIRATION_DATE'));
        }


        if (!CRESetupManager::isMultiDocumentConversionEnabled()) {
            $headersection->findAndSetProperty(array('path' => 'CREATEDFROM'), array('entity' => $this->getEntity(), 'readonly' => true));
        }
        $headersection->findAndSetProperty(array('path' => 'COPYFROM'), array('entity' => $this->getEntity()));


        if ( $this->state == $this->kShowNewState ) {
            /** @noinspection PhpUndefinedVariableInspection */
            if ( ! $obj['WHENDUE'] && $duedate ) {
                $obj['WHENDUE'] = $duedate;
                $obj['SUMMARY']['WHENDUE'] = $duedate;
            }

            if ( !$obj['SHIPVIA'] ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $obj['SHIPVIA'] = $entData['SHIPPINGMETHOD'];
            }

            // we don't want to show the created by & Modified By label, when we are creating
            // the Purchase order i.e., when we click on the add button to create the purchase order
            $hidefields = array();
            $headersection->findComponents(array('path' => 'USERID'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $headersection->findComponents(array('path' => 'CREATEDUSERID'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $headersection->findComponents(array('path' => 'PRINTEDUSERID'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $headersection->findComponents(array('path' => 'NOTE'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $headersection->findComponents(array('path' => 'BACKORDER'), EditorComponentFactory::TYPE_FIELD, $hidefields);
            $headersection->findComponents(array('path' => 'PRINTED'), EditorComponentFactory::TYPE_FIELD, $hidefields);

            foreach ( $hidefields as $hidefield ) {
                $hidefield->setProperty('hidden', true);
            }

            $ID = Request::$r->_r;
            if ( $ID ) {
                $obj['CREATEDFROM'] = '';
                if ( $copy == 'Update' ) {
                    $obj['CREATEDFROM'] = $ID;
                }
            } else {
                //TODO: when go back error for MULTIPLE_SOURCE_DOCS will be fixed then keep only readonly' => false
                if($obj['CREATEDFROM'] == $multipleSrcDocText || $error != '') {
                    $createdFromProps = array('readonly' => true);
                } else {
                    $createdFromProps = array('readonly' => false);
                }

                if ( $copy == 'Update' ) {
                    $createdFromProps['onchange'] = 'RefreshOnSourceTransSelect(\'Update\', this.value, true);';
                    if ( $this->mod == 'so' || $this->mod == 'po' ) {
                        $createdFromProps['showhash'] = true;
                    }
                }
                $headersection->findAndSetProperty(array('path' => 'CREATEDFROM'), $createdFromProps);

                $headersection->findAndSetProperty(array('path' => 'COPYFROM'), array('onchange' => 'RefreshOnSourceTransSelect(\'Copy\', this.value, true);'));
            }


            $docNoProps = array();
            // when new document is created
            if ((isset($docpar['SEQUENCE']) && '' !== $docpar['SEQUENCE']) || (!$entID && !$recalled) ) {
                $docNoProps['hidden'] = true;
            } else if ( (($copy == 'Update' && $docpar['INHERIT_SOURCE_DOCNO'] != 'true') || $copy == 'Copy' || $copy == 'Populate')
                && !$gErr->hasWarnings() ) {
                // copying/converting
                // when converting
                // if inherit source document number is set to true
                // the converted document carries forward the source document number
                $obj['DOCNO'] = '';
            }


            // if Sequnece Numbering is disabled when creating/copying/converting.
            // User can edit Document Number
            if (!isset($docpar['SEQUENCE']) || '' === $docpar['SEQUENCE']) {
                $docNoProps['hidden'] = false;
                $docNoProps['readonly'] = false;
            }

            if (!empty($docNoProps)) {
                $headersection->findAndSetProperty(array('path' => 'DOCNO'), $docNoProps);
            }
        } else {

            if ( !$obj['PRINTED'] ) {
                $obj['PRINTED'] = "No";
            }

            if ( !$obj['NOTE'] ) {
                $headersection->findAndSetProperty(array('path' => 'NOTE'), array('hidden' => true));
            }

        }
        $convMgr    = new ConversionManager(array('mod' => $this->mod));
        $recallDocCount = $convMgr->GetAllowedDocsToConvertTo($this->dt);

        if (($this->state == $this->kShowNewState && empty($obj['CUSTVENDID']) && $copy != 'Populate' && (!empty($recallDocCount))) || ((CRESetupManager::isMultiDocumentConversionEnabled() && $this->state != $this->kShowViewState) && !in_array($obj['STATE'], [DocumentManager::CONVERTED_STATE, DocumentManager::PARTIALLY_CONVERTED_STATE]))) {
            $headersection->findAndSetProperty(
                array('path' => 'CREATEDFROMLINK'), array('hidden' => false), EditorComponentFactory::TYPE_FIELD
            );
            $obj['CREATEDFROMLINK'] = GT($this->textMap, 'IA.CONVERT_FROM_AN_EXISTING_TRANSACTION');
        }

        // Removing SOURCEDOCID and SOURCEDOCLINEID to avoid pre-populating while copy
        if ($copy == 'Copy') {
            array_walk($obj['ENTRIES'], function(&$entries) {
                unset($entries['SOURCEDOCID']);
                unset($entries['SOURCEDOCLINEID']);
                unset($entries['SOURCE_DOCID']);
                unset($entries['SOURCEDOCLINENO']);
                unset($entries['SOURCEDOCITEM']);
            });
        }

        $this->showCreatedFromLink($obj, $headersection, $copy);

        /** @noinspection PhpUndefinedVariableInspection */
        $headersection->findComponents(array( 'path' => 'STATE'), EditorComponentFactory::TYPE_FIELD, $statefld);
        /**
         * @var EditorComponent[] $statefld
         */
        if ( $statefld[0] ) {

            $convertByLinePage    = Request::$r->_salecon;

            if ($this->state == $this->kShowNewState) {
                $headersection->findAndSetProperty(array('path' => 'STATE'), array('hidden' => true));
            }

            if (
                (in_array($obj['STATE'], array('Draft', 'Declined')) || $this->state == $this->kShowNewState)
                && $this->do != 'view'
            ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $_params['title'] = $_params['title'] . " -- " . 'IA.DRAFT';
            }

            if (
                $convertByLinePage == 'T'
                || ($obj['STATE'] != DocumentManager::PENDING_STATE && $obj['STATE'] != DocumentManager::CLOSED_STATE)
                || $this->state == $this->kShowViewState
            ) {
                $statefld[0]->setProperty('readonly', true);
            } else {
                $statefldtype = $statefld[0]->getProperty('type');
                $statefldtype['validvalues'] = array(
                    DocumentManager::PENDING_STATE, DocumentManager::CLOSED_STATE
                );
                $statefldtype['_validivalues'] = array(
                    DocumentManager::PENDING_RAWSTATE, DocumentManager::CLOSED_RAWSTATE
                );
                $statefldtype['validlabels'] = array(
                    'IA.PENDING', 'IA.CLOSED'
                );
                $statefld[0]->setProperty('type', $statefldtype);
                $statefld[0]->setProperty('readonly', false);

            }
        }
        /*
          $obj['VIRTUAL.DOCPARID'] = $this->dt;
          $obj['VIRTUAL.WHENCREATED'] = (($this->state != 'showview' && Request::$r->_action != 'refresh')? FormatDateForDisplay($date) : $date);
          $obj['VIRTUAL.DOCNO'] = $docno;
         */
        //eppp_p($obj);dieFL();
        // Handle the billto/shipto and also the customer vendor fields
        /** @noinspection PhpUndefinedVariableInspection */
        $headersection->findComponents(array( 'path' => 'CUSTVENDID'), EditorComponentFactory::TYPE_FIELD, $custVendfld);
        /**
         * @var EditorComponent[] $custVendfld
         */
        if ( $custVendfld[0] && ($this->mod == 'so' || $this->mod == 'po') ) {

            //$custVendfld[0]->setProperty('fullname', isl_ucfirst($entType));

            $custVendfldtype = $custVendfld[0]->getProperty('type');
            $field['type']['entity'] = $entType;
            $custVendfld[0]->setProperty('type', $custVendfldtype);

            /** @noinspection PhpUndefinedVariableInspection */
            if ( $entVID ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $obj['CUSTVENDID'] = $entVID . '--' . $entData['NAME'];
            }

            $vendorVisibility = $this->mod == 'po' && IsMultiVisibilitySubscribed('vendor');
            $customerVisibility = $this->mod == 'so' && IsMultiVisibilitySubscribed('customer');


            if ( $vendorVisibility ) {
                $visibility = 'VENDOR';
            } else if ( $customerVisibility ) {
                $visibility = 'CUSTOMER';
            }

            if ( $this->state == $this->kShowNewState && $copy != 'Update' ) {
                if ( $copy == 'Copy' ) {
                    $custVendfld[0]->setProperty('required', true);
                } else {
                    $custVendfld[0]->setProperty('showhash', true);
                }
                $onchange = 'AutoPopulateCustVendID(this.value,\'true\');';
                if ( $this->mod == 'po' ) {
                    $custVendfld[0]->setProperty('primaryDimension', 'VENDORID');
                } elseif ( $this->mod == 'so' ) {
                    $onchange .= "RestrictProjectDimension('" . $field['varname'] . "','CUSTOMER','ENTRIES'," . GetOperationId('ar/lists/project') . ");";
                }
                $custVendfld[0]->setProperty('onchange', $onchange);
            } else {
                $custVendfld[0]->setProperty('readonly', true);
            }

            /** @noinspection PhpUndefinedVariableInspection */
            if ( $visibility ) {
                $restrict = array(
                    'field' => 'CUSTVENDID',
                    'context' => array('CUSTVENDID'),
                    'pickField' => $visibility,
                    'operand' => 'visibility',
                    'entityContext' => true,
                );

                $locationDeptFields = array();
                $this->getView()->findComponents(array('path' => 'LOCATION'), EditorComponentFactory::TYPE_FIELD, $locationDeptFields);
                $this->getView()->findComponents(array('path' => 'HEADER_LOCATION'), EditorComponentFactory::TYPE_FIELD, $locationDeptFields);
                $this->getView()->findComponents(array('path' => 'DEPARTMENT'), EditorComponentFactory::TYPE_FIELD, $locationDeptFields);
                $this->getView()->findComponents(array('path' => 'HEADER_DEPARTMENT'), EditorComponentFactory::TYPE_FIELD, $locationDeptFields);

                foreach ( $locationDeptFields as $locationDeptField ) {
                    $type = $locationDeptField->getProperty('type');
                    if ( ! $type['restrict'] ) {
                        $type['restrict'] = array( $restrict );
                    }
                    else {
                        $type['restrict'][] = $restrict;
                    }
                    $locationDeptField->setProperty('type', $type);
                }
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $headersection->findComponents(array( 'path' => 'GETLATESTSHIPTO'), EditorComponentFactory::TYPE_FIELD, $shiptoCheckbox);
            /** @noinspection PhpUndefinedVariableInspection */
            $headersection->findComponents(array( 'path' => 'GETLATESTBILLTO'), EditorComponentFactory::TYPE_FIELD, $billtoCheckbox);

            $hidecheckboxes = array();
            if ( $this->state != 'showedit' && $copy != 'Update' ) {
                $hidecheckboxes = array($shiptoCheckbox[0], $billtoCheckbox[0]);
            } else {
                $contactMgr =  $gManagerFactory->getManager('contact');
                if ( !$obj['SHIPTOKEY'] || $contactMgr->GetCurrentVersionNo($obj['SHIPTO']['CONTACTNAME']) == $obj['SHIPTOKEY'] ) {
                    $hidecheckboxes[] = $shiptoCheckbox[0];
                }
                if ( !$obj['BILLTOKEY'] || $contactMgr->GetCurrentVersionNo($obj['BILLTO']['CONTACTNAME']) == $obj['BILLTOKEY'] ) {
                    if ( $billtoCheckbox[0] ) {
                        $hidecheckboxes[] = $billtoCheckbox[0];
                    }
                }
            }

            foreach ( $hidecheckboxes as $hidecheckbox ) {
                if ( $hidecheckbox ) {
                    $hidecheckbox->setProperty('hidden', true);
                }
            }

            // Get shipto/billto for the first time as defaults
            if ( $this->state == 'shownew' ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $shipto = ( $obj['SHIPTO']['CONTACTNAME']) ?: $entData['SHIPTONAME'];

                /** @noinspection PhpUndefinedVariableInspection */
                if ( !$shipto && $entData['VISIBLE'] == 'T' ) {
                    $shipto = $entData['DISPLAYCONTACTNAME'];
                }

                /** @noinspection PhpUndefinedVariableInspection */
                $billto = ( $obj['BILLTO']['CONTACTNAME']) ?: $entData['BILLTONAME'];

                /** @noinspection PhpUndefinedVariableInspection */
                if ( !$billto && $entData['VISIBLE'] == 'T' ) {
                    $billto = $entData['DISPLAYCONTACTNAME'];
                }

                if ( !isset($obj['SHIPTO']['CONTACTNAME']) || ($obj['SHIPTO']['CONTACTNAME'] == '' ) || $copy == 'Copy' ) {
                    $obj['SHIPTO']['CONTACTNAME'] = $shipto;
                }

                if ( !isset($obj['BILLTO']['CONTACTNAME']) || ($obj['BILLTO']['CONTACTNAME'] == '' ) || $copy == 'Copy' ) {
                    $obj['BILLTO']['CONTACTNAME'] = $billto;
                }

                /** @noinspection PhpUndefinedVariableInspection */
                $headersection->findComponents(array( 'path' => 'CUSTVENDNAME'), EditorComponentFactory::TYPE_FIELD, $custvendname);
                /**
                 * @var EditorComponent[] $custvendname
                 */
                if ( $custvendname[0] ) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $obj['CUSTVENDNAME'] = $entData['NAME'];
                    $fullname = ($entType == 'customer') ? 'IA.CUSTOMER_NAME' : 'IA.VENDOR_NAME';
                    $custvendname[0]->setProperty('fullname', $fullname);
                    $custvendname[0]->setProperty('readonly', true);
                }
            }
        }//if custvendid
        // Check if the SFDC company is mcp enabled and also intacct company is mcp enabled and set the so document when created from SFDC have the multicurrency fields in view mode.
        /** @noinspection PhpUndefinedVariableInspection */
        if ( $sfismcp == 'true' && $this->ismcpEnabled && Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '' ) {
            $headersection->findAndSetProperty(array('path' => 'CURRENCY'), array('readonly' => true));
        }

        /** @noinspection PhpUndefinedVariableInspection */
        if ( $entVID ) {
            /** @noinspection PhpUndefinedVariableInspection */
            $obj['VIRTUALCUSTVENDID'] = $entVID . '--' . $entData['NAME'];
        }



        //Move focus on the history tab of the document if clicked on the link "SalesContract" in lister
        if ( Request::$r->_issalescontract == 'Y' ) {
            //Request::$r->_currentlayer = 'Layer1';
            $view->getChild(0)->setProperty('activeIndex', 1);
        } else {
            $_hist  = Request::$r->_hist;
            $_popup = Request::$r->_popup;
            if ( $_hist && $_popup ) {
                $tabIndex= $this->getTabId($view->getChild(0),'historyPage');
                $view->getChild(0)->setProperty('activeIndex',$tabIndex );
            }
         }

        //
        // ----------- if multi currency is enabled ---------------
        //
        // show the currency if the 'Allow creating, editing & deleting foreign currency documents'
        // is set to true in OE Configuration
        if ( $this->ismcpEnabled ) {
            if ( $docpar['EXCH_RATE_TYPE_ID'] == '-1' ) {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $docpar['EXCHRATETYPES']['NAME'] = $exchTypeMgr->GetExchangeRateTypeName($docpar['EXCH_RATE_TYPE_ID']);
            }
            $exchratetypename = $docpar['EXCHRATETYPES']['NAME'] ?? '';
            $this->ShowMCPControls($obj, $view, $exchratetypename, $docpar['DISPLAY_BASECURRENCY'], $docpar['OVERRIDE_EXCH_RATE_TYPE']);
        }

        if ( $this->atlas ) {
            $this->ShowAtlasControls($view);
        }

        //hide view Recurring schedule if schopkey is not set
        if ( !isset($obj['SCHOPKEY']) ) {
            $fields = array();
            $view->findComponents(array('path' => 'RECURRINGSCHEDULE'), EditorComponentFactory::TYPE_FIELD, $fields);
            foreach ( $fields as $field ) {
                $field->setProperty('hidden', true);
                $field->setProperty('readonly', true);
                $field->setProperty('hreftxt', '');
            }
        } else {
            $r = Request::$r->_r;

            $recurdocMgr = $gManagerFactory->getManager('recurdocument');
            $result = $recurdocMgr->DoQuery('QRY_RECURDOCUMENT_GET_TEMPLATEID', array($r));
            $docid = $result[0]['DOCID'];

            $recProperties = array();
            if ( isset($docid) && $docid != '' ) {
                $_sess = Session::getKey();

                $op = GetOperationId($this->mod . "/lists/" . $this->mod . "recurdocument/view");

                $url = 'editor.phtml?.sess=' . $_sess . '&.op=' . $op . '&.mod=' . $this->mod . '&.r=' . urlencode($docid) . '&.dt=' . urlencode($this->dt) . '&.popup=1&.viewsch=T';
                $recProperties['onclick'] = "Launch('$url','mywindow','700','500');";
                $recProperties['statusmsg'] = 'IA.VIEW_RECURRING_SCHEDULE';
                $recProperties['href'] = 'IA.VIEW_RECURRING_SCHEDULE';
                $recProperties['hidden'] = false;
                $recProperties['displayValue'] = 'View';
            } else {
                $recProperties['hreftxt'] = "";
            }
            $headersection->findAndSetProperty(array('path' => 'RECURRINGSCHEDULE'), $recProperties);
        }

        foreach ( $this->sourceDocsArr as $idx => $sdoc ) {
            $obj['SDOCUMENT' . $idx] = $sdoc;
        }

        if( $this->ShowGLPostingDate($docpar, $autofill) ) {
            /** @noinspection PhpUndefinedVariableInspection */
            $headersection->findComponents(array( 'path' => 'WHENPOSTED'), EditorComponentFactory::TYPE_FIELD, $whenpostedfld);
            /**
             * @var EditorComponent[] $whenpostedfld
             */
            if ( $whenpostedfld[0] ) {
                $whenpostedfld[0]->setProperty('hidden', false);
                if ( empty($obj['WHENPOSTED']) && $this->state == $this->kShowNewState ) {
                    if ($this->autoBatchFrequency == 'M') { // PHP 7.1 NOTE: Multiple subclassers define this, but it isn't in the base class.  To fix will take coordination with other fixers.
                        $obj['WHENPOSTED'] = GetCompanyLastDayOfCurrentPeriod();
                    }else {
                        $obj['WHENPOSTED'] = GetCurrentDate();
                    }
                }
            }
        }else {
            //There is two dummy space defined in xml, first is hidden so making first visible here to get 'BillTo' & 'ShipTo' align with field 'Customer'.
            /** @noinspection PhpUndefinedVariableInspection */
            $headersection->findComponents(array( 'path' => 'DUMMYSPACE'), EditorComponentFactory::TYPE_FIELD, $dummyspace);
            /**
             * @var EditorComponent[] $dummyspace
             */
            if ( $dummyspace[0] ) {
                $dummyspace[0]->setProperty('hidden', false);
            }
            //Edit action with GL Posting Date field as hidden, no need to send 'GL posting date' through editor
            if( $this->state == $this->kShowEditState ) {
                unset($obj['WHENPOSTED']);
            }
        }

        $isRequired = $this->_isCustVendRequired;
        $isReadonly = true;
        $conversion = false;
        if(isset($obj['CREATEDFROM']) && $obj['CREATEDFROM'] != null){
            $conversion = true;
        }

        if ( ($state == $this->kShowNewState || $state == $this->kShowEditState) && $obj['STATE'] != 'Partially Converted' ) {
            switch ($docpar['ALLOWEDITCUSTVEND']) {
                case 'Always':
                    $isReadonly = false;
                    break;

                case 'Except converted documents':
                    if(!$conversion){
                        $isReadonly = false;
                    }
                    break;

                default:
                    if($state == $this->kShowNewState  && !$conversion){
                        $isReadonly = false;
                    }
            }
        }

        $headersection->findAndSetProperty(['path' => 'CUSTVENDID'],
                                           ['required' => $isRequired, 'readonly' => $isReadonly], EditorComponentFactory::TYPE_FIELD);


        //See if this company has taxes configuration enabled. If so, we need to show/hide VAT tax header fields
        //on this transaction form instance.
        if (TaxSetupManager::isVATEnabled()) {
            $copyConvertStates = ['Update', 'Copy'];
            $hasIsTaxLine = DocumentManager::hasTaxSubTotals($obj['_DOCPAR']);
            //If we are at root level and configured multijurisdiction (have multi tax solutions), we need to show tax
            //tax solution picker to let users choose which tax solutions to write transaction against.
            if (IsRoot() && TaxSetupManager::isMultiTaxJurisdictionConfigured()) {

                //Show/hide the tax solution picker only if we have one subtotal line in TD marked as is taxble
                $hideTaxSolnFld = !$hasIsTaxLine;
                if (!$hideTaxSolnFld && ($this->state != $this->kShowNewState) && !$obj['TAXSOLUTIONID']) {
                    $hideTaxSolnFld = true;
                }

                // enable taxsolution selection only on create, copy or convert of a new document
                $disableTaxSolnFld = $obj['DISABLETAXSOLUTION'] ?? ($this->state != $this->kShowNewState);
                $obj['DISABLETAXSOLUTION'] = $disableTaxSolnFld;
                $headersection->findAndSetProperty(array('path' => 'TAXSOLUTIONID'), array('hidden' => $hideTaxSolnFld, 'required' => true, 'readonly' => $disableTaxSolnFld));

                //Maintain the current tax solution entity's locations so we can restrict on the location picker
                if ($hasIsTaxLine) {
                    $obj['TAXSOLUTIONLOCS'] = $obj['TAXSOLUTIONID']?
                        TaxSolutionManager::getLocnKeysFromTaxSolnIds([$obj['TAXSOLUTIONID']]) :
                        TaxSolutionManager::getLocnKeysFromTaxMethods($this->getEntityMgr()->getNonTaxImplicationTaxMethods());
                }

                //For Avalara enabled company set simple tax fallback if the current module does not have Avalara enabled
                if (IsModuleIdInstalled($kAVAid)) {
                    GetModulePreferences($kAVAid, $preferences);
                    $pref = 'AVA_ENABLE_' . strtoupper($this->mod);
                    if ($preferences['AVA_ENABLE'] == 'T' && $preferences[$pref] != 'T') {
                        $obj['SIMPLETAXFALLBACK'] = true;
                    }
                }
            }

            $txnIsVatEnabled = $this->getEntityMgr()->isVATEnabled($obj);
            if ($txnIsVatEnabled) {
                $headersection->findAndSetProperty(array('path' => 'TAXID'), array('hidden' => false), EditorComponentFactory::TYPE_FIELD);
                $contactType = ($this->mod == 'so') ? 'SHIPTO' : 'BILLTO';
                $contactMgr = Globals::$g->gManagerFactory->getManager('contact');
                $contact = $contactMgr->get($obj[$contactType]['CONTACTNAME']);
                $obj[$contactType]['TAXID'] = $contact['TAXID'];
                $obj['TAXID'] = $contact['TAXID'];
                //Fetch taxdetails filtered by transaction taxsolution for taxdetail picker
                if ($hasIsTaxLine) {
                    $taxType = $this->mod == "po" ? 'P' : 'S';
                    $taxSolnMngr = Globals::$g->gManagerFactory->getManager('taxsolution');
                    $taxSolnResult = $taxSolnMngr->get($obj['TAXSOLUTIONID']);

                    $taxDetailRes = SubLedgerTxnManager::getTaxDetails(null, $taxType, $obj['WHENCREATED'], $taxSolnResult['RECORDNO']);
                    $obj['TAXDETAILSFOROVERRIDE'] = array_column($taxDetailRes, 'DETAILID');
                }
            } else {
                //During conversion/copy, if converted to doc type do not have tax remove tax entries and update
                //total amount for each line
                if ((!empty($obj['CREATEDFROM']) || in_array($copy, $copyConvertStates)) && $this->state == $this->kShowNewState) {
                    $this->getEntityMgr()->resetVatTaxValues($obj);
                }
            }

            //Below logic will update the UI fields event handlers. We need to do this if company is VAT enabled.
            $exchangeRateType = [];
            $headersection->findComponents(array('path' => 'EXCHRATETYPES.NAME'), EditorComponentFactory::TYPE_FIELD, $exchangeRateType);
            $exchangeRateType = $exchangeRateType[0];
            if ($exchangeRateType) {
                $events = $exchangeRateType->getProperty('events');
                $events['change'] = "calculateSubtotalsAjax();";
                $exchangeRateType->setProperty('events', $events);
            }

            $exchangeRate = [];
            $headersection->findComponents(array('path' => 'EXCHRATE'), EditorComponentFactory::TYPE_FIELD, $exchangeRate);
            $exchangeRate = $exchangeRate[0];
            if ($exchangeRate) {
                $events = $exchangeRate->getProperty('events');
                $events['change'] = "calculateSubtotalsAjax();";
                $exchangeRate->setProperty('events', $events);
            }

            $txnCurrency = [];
            $headersection->findComponents(array('path' => 'CURRENCY'), EditorComponentFactory::TYPE_FIELD, $txnCurrency);
            $txnCurrency = $txnCurrency[0];
            if ($txnCurrency) {
                $events = $txnCurrency->getProperty('events');
                $events['change'] .= ";calculateSubtotalsAjax();";
                $txnCurrency->setProperty('events', $events);
            }

            $baseCurrency = [];
            $headersection->findComponents(array('path' => 'BASECURR'), EditorComponentFactory::TYPE_FIELD, $baseCurrency);
            $baseCurrency = $baseCurrency[0];
            if ($baseCurrency) {
                $events = $baseCurrency->getProperty('events');
                $events['change'] .= ";calculateSubtotalsAjax();";
                $baseCurrency->setProperty('events', $events);
            }

            $contact = [];
            $contactType = ( $this->mod === 'po' ) ? 'BILLTO.CONTACTNAME' : 'SHIPTO.CONTACTNAME';
            $headersection->findComponents(array('path' => $contactType), EditorComponentFactory::TYPE_FIELD, $contact);
            $shipToReturnToContact = $contact[0];
            if ($shipToReturnToContact) {
                $events = $shipToReturnToContact->getProperty('events');
                $events['change'] .= ";calculateSubtotalsAjax();";
                $shipToReturnToContact->setProperty('events', $events);
            }
        }

        if($this->mod == "po" || $this->mod == "so"){
            $creinstalled = CRESetupManager::isCREInstalled();
            if(!$creinstalled)
            {
                $view->findAndSetProperty(array('path' => 'CHANGELOGNUMBER'), array('hidden' => true));
            }
            if($this->canEditConvertDoc &&  $creinstalled && in_array($obj['STATE'],[DocumentManager::CONVERTED_STATE,
                                                        DocumentManager::INPROGRESS_STATE])){
                if($obj['_DOCPAR']['ENABLEADDINFOSCOPE'] == 'true'){
                    $scopeFields = DocumentManager::getAdditionalInfoFields('scope');
                    foreach ($scopeFields as $field){
                        $headersection->findAndSetProperty([ 'path' => $field ],
                                                           [ 'readonly' => false ],
                                                           EditorComponentFactory::TYPE_FIELD);
                    }
                }
                if($obj['_DOCPAR']['ENABLEADDINFOSCHEDULE'] == 'true'){
                    $scopeFields = DocumentManager::getAdditionalInfoFields('schedule');
                    foreach ($scopeFields as $field){
                        $headersection->findAndSetProperty([ 'path' => $field ],
                                                           [ 'readonly' => false ],
                                                           EditorComponentFactory::TYPE_FIELD);
                    }
                }
                if($obj['_DOCPAR']['ENABLEADDINFOINTERNALREF'] == 'true'){
                    $scopeFields = DocumentManager::getAdditionalInfoFields('internalref');
                    foreach ($scopeFields as $field){
                        $headersection->findAndSetProperty([ 'path' => $field ],
                                                           [ 'readonly' => false ],
                                                           EditorComponentFactory::TYPE_FIELD);
                    }
                }
                if($obj['_DOCPAR']['ENABLEADDINFOEXTERNALREF'] == 'true'){
                    $scopeFields = DocumentManager::getAdditionalInfoFields('externalref');
                    foreach ($scopeFields as $field){
                        $headersection->findAndSetProperty([ 'path' => $field ],
                                                           [ 'readonly' => false ],
                                                           EditorComponentFactory::TYPE_FIELD);
                    }
                }
                if($obj['_DOCPAR']['ENABLEADDINFOBOND'] == 'true'){
                    $scopeFields = DocumentManager::getAdditionalInfoFields('bond');
                    foreach ($scopeFields as $field){
                        $headersection->findAndSetProperty([ 'path' => $field ],
                                                           [ 'readonly' => false ],
                                                           EditorComponentFactory::TYPE_FIELD);
                    }
                }
                $view->findAndSetProperty(array('path' => 'CHANGELOGNUMBER'), array('readonly' => false));

            }
        }
    }

    /**
     * @param string[]|string[][] $_params
     * @param array   $objRec
     *
     * @return string[]|string[][]
     */
    protected function getGridDefaultsFields(&$_params, $objRec)
    {
        $fields = parent::getGridDefaultsFields($_params, $objRec);
        global $kSOid;
        GetModulePreferences($kSOid, $prefs);

        if ( isset($this->dt) && $this->dt != '' ) {
            $docparmrec = $this->GetBaseDocPar();
            $this->deptOverride = ($docparmrec['DEPTOVERRIDE'] == 'true');
            $this->locOverride = ($docparmrec['LOCOVERRIDE'] == 'true');
            if ( $this->mod == 'so' ) {
                $enablerevrec = $docparmrec['ENABLEREVREC'] != 'None' ? true : false;
                $renewalsEnabled = $docparmrec['ENABLERENEWALS'] != 'None' ? true : false;
            }
        }

        if ( $this->hasInventoryItems ) {
            // For GA clean this up
            $warehouseType = array('ptype' => 'ptr', 'type' => 'text', 'entity' => 'warehouse', 'addlPickFields' => array('NAME'));
            $fields[] = array('path' => 'WAREHOUSE.LOCATION_NO', 'noview' => false, 'type' => $warehouseType);
        }

        if ( $this->deptOverride ) {
            $fields[] = array('path' => 'DEPARTMENT', 'hidden' => false);
        }

        if ( $this->locOverride ) {
            $fields[] = array('path' => 'LOCATION', 'hidden' => false);
        }
        /** @noinspection PhpUndefinedVariableInspection */
        if ( $this->mod == 'so' && ( $prefs['ITEMSHAVESTARTENDDATE'] == 'T' || ( $enablerevrec || $renewalsEnabled))) {
            if ( isset($enablerevrec) && $enablerevrec ) {
                $fields[] = array('path' => 'REVRECTEMPLATE', 'hidden' => false);
            }
            $fields[] = array('path' => 'REVRECSTARTDATE', 'hidden' => false);
            $fields[] = array('path' => 'REVRECENDDATE', 'hidden' => false);
            if ( isset($renewalsEnabled) && $renewalsEnabled ) {
                $fields[] = array('path' => 'RENEWALMACRO', 'hidden' => false);
            }
        }

        //eppp_p($fields);dieFL();
        return $fields;
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Entries(&$obj, $docparmrec)
    {
        $isSupplyRequest = ($docparmrec['DOCID'] === PODocumentManager::SUPPLIESREQUESTDOCTYPE);
        $this->onlySupplies = $isSupplyRequest;
        $this->includeSupplies = $this->mod != 'so';

        $view = $this->getView();
        $comIsVatEnabled = TaxSetupManager::isVATEnabled(); //Specifies this company/entity is VAT tax configured
        $txnIsVatEnabled = $this->getEntityMgr()->isVATEnabled($obj); //Specifies this txn instance is VAT tax configured
        $docpar = $this->GetBaseDocPar();
        $isShipToLineItemEnable = $this->getEntityMgr()->isShipToLineItemEnable();

        $entriesView = array();
        $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entriesView);
        $entriesView = $entriesView[0];
        if ($this->deptOverride) {
            $entriesView->findAndSetProperty(array('path' => 'DEPARTMENT'), array('hidden' => false));
        }
        if ($this->locOverride) {
            $entriesView->findAndSetProperty(array('path' => 'LOCATION'), array('hidden' => false));
        }
        if (IADimensions::IsDimensionEnabled($this->mod, 'task')) {
            $entriesView->findAndSetProperty(array('id' => 'TASKID'), array('hidden' => false));
        }

        // Show Conversion Type column when the Price Conversion feature is enabled.
        $priceConversionTypeEnabled = ($this->isPriceConversionEnabled() && $this->isOverrideTrnxConversionTypeEnabled());
        // CONVERSIONTYPE field shows only when user enabled both price conversion and override transaction on conversion type
        $entriesView->findAndSetProperty(['path' => 'CONVERSIONTYPE'], ['hidden' => (!$priceConversionTypeEnabled)]);

        //In View mode, hide the link used to populate the defaults in the line items.
        if ($this->state == 'showview') {
            $itemDefaultsLink = [];
            $entriesView->findComponents(array('id' => 'ITEMDEFAULTS'), EditorComponentFactory::TYPE_CAPTION, $itemDefaultsLink);
            $itemDefaultsLink = $itemDefaultsLink[0];
            if ($itemDefaultsLink) {
                $itemDefaultsLink->parent->removeChild($itemDefaultsLink);
            }
        }

        //Apply the Item Picker defaults
        $itemID = [];
        $entriesView->findComponents(array('path' => 'ITEMID'), EditorComponentFactory::TYPE_FIELD, $itemID);
        $itemID = $itemID[0];

        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        $IsOverrideAdvancedTaxEnabled = false;
        if($docMgr->isOverrideTaxSchedForEntryConfigAllowed()){
            $scheduleIdMaps = $docMgr->taxScheduleKeyMaps($obj);
            if($docMgr->isAdvancedTaxEnabled()){
                $IsOverrideAdvancedTaxEnabled = true;
            }
        }
        if ($itemID) {
            $itemTypes = $this->getItemPickRestrictParams();
            if ($comIsVatEnabled || $IsOverrideAdvancedTaxEnabled) {
                $unsetOverdeTax   = (!empty($obj['CREATEDFROM']) || $this->state === $this->kShowEditState)
                    ? 'true' : 'false';
                $events           = $itemID->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $itemID->setProperty('events', $events);
            }
            if ($itemTypes && (!empty($itemTypes))) {
                $itemFldType = $itemID->getProperty('type');

                if (!$itemFldType['restrict']) {
                    $itemFldType['restrict'] = array();
                }

                $itemFldType['restrict'][] = array(
                    'pickField' => 'ITEMTYPE',
                    'operand'   => 'NOT IN',
                    'value'     => $itemTypes,
                );

                if ($this->onlySupplies) {
                    $itemFldType['restrict'][] = array(
                        'pickField' => 'ISSUPPLYITEM',
                        'operand'   => '=',
                        'value'     => 'T',
                    );
                } else if ($this->includeSupplies == false) {
                    $itemFldType['restrict'][] = array(
                        'pickField' => 'ISSUPPLYITEM',
                        'operand'   => '<>',
                        'value'     => 'T',
                        'nulls'     => true
                    );
                }

                $itemID->setProperty('type', $itemFldType);
            }
        }
        if ($comIsVatEnabled || $IsOverrideAdvancedTaxEnabled) {
            $unsetOverdeTax = (!empty($obj['CREATEDFROM']) || $this->state === $this->kShowEditState) ? 'true' : 'false';

            $quantity = [];
            $entriesView->findComponents(array('path' => 'UIQTY'), EditorComponentFactory::TYPE_FIELD, $quantity);
            $quantity = $quantity[0];
            if ($quantity) {
                $events           = $quantity->getProperty('events');
                $events['change'] .= "calculateLineTax(this, " . $unsetOverdeTax . ");";
                $quantity->setProperty('events', $events);
            }

            $unit = [];
            $entriesView->findComponents(array('path' => 'UNIT'), EditorComponentFactory::TYPE_FIELD, $unit);
            $unit = $unit[0];
            if ($unit) {
                $events           = $unit->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $unit->setProperty('events', $events);
            }

            $uiPrice = [];
            $entriesView->findComponents(array('path' => 'UIPRICE'), EditorComponentFactory::TYPE_FIELD, $uiPrice);
            $uiPrice = $uiPrice[0];
            if ($uiPrice) {
                $events           = $uiPrice->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $uiPrice->setProperty('events', $events);
            }

            $trxPrice = [];
            $entriesView->findComponents(array('path' => 'TRX_PRICE'), EditorComponentFactory::TYPE_FIELD, $trxPrice);
            $trxPrice = $trxPrice[0];
            if ($trxPrice) {
                $events           = $trxPrice->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $trxPrice->setProperty('events', $events);
            }

            $wareHouseLocation = [];
            $entriesView->findComponents(array('path' => 'WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FIELD, $wareHouseLocation);
            $wareHouseLocation = $wareHouseLocation[0];
            if ($wareHouseLocation) {
                $events           = $wareHouseLocation->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $wareHouseLocation->setProperty('events', $events);
            }

            $uiValue = [];
            $entriesView->findComponents(array('path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $uiValue);
            $uiValue = $uiValue[0];
            if ($uiValue) {
                $events           = $uiValue->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $uiValue->setProperty('events', $events);
            }

            $trxValue = [];
            $entriesView->findComponents(array('path' => 'TRX_VALUE'), EditorComponentFactory::TYPE_FIELD, $trxValue);
            $trxValue = $trxValue[0];
            if ($trxValue) {
                $events           = $trxValue->getProperty('events');
                $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                $trxValue->setProperty('events', $events);
            }

            if ($isShipToLineItemEnable) {
                $lineship = [];
                $entriesView->findComponents(array('path' => 'SHIPTO.CONTACTNAME'), EditorComponentFactory::TYPE_FIELD, $lineship);
                $lineship = $lineship[0];
                if ($lineship) {
                    $events = $lineship->getProperty('events');
                    $events['change'] .= ";calculateLineTax(this, " . $unsetOverdeTax . ");";
                    $lineship->setProperty('events', $events);
                }
            }

            if ($this->getEntityMgr()->isTxnEligibleForVatPartialExempt($obj)) {
                $matches = [];
                $entriesView->findComponents(array('path' => 'PARTIALEXEMPT'), EditorComponentFactory::TYPE_FIELD, $matches);
                if ($matches) {
                    if ($obj['TAXSOLUTIONID'] === TaxSolutionManager::TAXSOLUTION_CA) {
                        $partialExemptionLabel = GT($this->textMap, 'IA.ITC');
                    } elseif ($obj['TAXSOLUTIONID'] === TaxSolutionManager::TAXSOLUTION_AU) {
                        $partialExemptionLabel = GT($this->textMap, 'IA.RITC');
                    } else {
                        $partialExemptionLabel = GT($this->textMap, 'IA.UK_PARTLY_EXEMPT');
                    }
                    $matches[0]->setProperty('hidden', false);
                    $matches[0]->setProperty('fullname', $partialExemptionLabel);
                }

                $view->findAndSetProperty(array('id' => 'taxReclaimSection'), array('hidden' => false), EditorComponentFactory::TYPE_SECTION);
                $matches = [];
                $entriesView->findComponents(array('path' => 'TRX_TAXCLAIMABLE'), EditorComponentFactory::TYPE_FIELD, $matches);
                if ($matches) {
                    $matches[0]->setProperty('hidden', false);
                }
                $matches = [];
                $entriesView->findComponents(array('path' => 'TAXCLAIMABLE'), EditorComponentFactory::TYPE_FIELD, $matches);
                if ($matches) {
                    $matches[0]->setProperty('hidden', false);
                }
                $obj['ISTXNPARTIALEXEMPT'] = true;
                $obj['PARTIALEXEMPTION'] = SubLedgerTxnManager::getTaxPartialExemptDetails();
                $obj['PARTIALEXEMPT_PERCENT'] = $this->getPartialExemptPercentValue($obj);
                $obj['TAXDETAIL_PARTIALEXEMPT_TAXSOLUTIONS'] = TaxSolutionManager::$TAXDETAIL_PARTIALEXEMPT_TAXSOLUTIONS;
            }
        }

        // for VAT enabled txn, tax overrride cannot be used , instead use Zero or Exempt tax details
        if ($docpar['ENABLEOVERRIDETAX'] == 'true' && !$txnIsVatEnabled) {
            $entriesView->findAndSetProperty(array('path' => 'OVERRIDETAX'), array('hidden' => false));
            $overridetaxflds = [];
            $entriesView->findComponents(array('path' => 'OVERRIDETAX'), EditorComponentFactory::TYPE_FIELD, $overridetaxflds);
            foreach ($overridetaxflds as $key => $overridetax) {
                if ($obj['ENTRIES'][$key]['TAXCAPABLE']) {
                    $overridetaxflds[$key]->setProperty('disabled', false);
                } else {
                    $overridetaxflds[$key]->setProperty('disabled', true);
                }
            }
        }

        $warehouseFld = [];
        $entriesView->findComponents(array('path' => 'WAREHOUSE.LOCATION_NO'), EditorComponentFactory::TYPE_FIELD, $warehouseFld);
        $warehouseFld = $warehouseFld[0];
        if (($warehouseFld && $this->hasInventoryItems) || $obj['ENABLEFULFILLMENT'] == 'T') {
            if ($docpar['WAREHOUSESELMETHOD'] == 'Sort by Name') {
                //TODO For GA move this to ent
                if ($warehouseFld) {
                    $warehouseType           = $warehouseFld->getProperty('type');
                    $warehouseType['orders'] = 'NAME:a,LOCATIONID:a';
                    /*
                      $warehouseType = array (
                      'ptype' => 'ptr',
                      'type' => 'text',
                      'entity' => 'warehouse',
                      'orders'	=> 'NAME:a,LOCATIONID:a',
                      );
                     */
                    $warehouseFld->setProperty('type', $warehouseType);
                    $warehouseFld->setProperty('noedit', true);
                    $warehouseFld->setProperty('noview', true);
                }
            }
            if ($this->mod == 'inv') {
                $warehouseFld->setProperty(
                    'fullname',
                    'IA.WAREHOUSE'
                );
            }
        } else {
            $warehouseFld->setProperty('hidden', true);
        }

        if ($this->state != 'showview') {
            $uiPriceAssists = array(
                'customlink' => "SuggestPriceClick(this);",
                'text'       => 'IA.SUGGEST',
                'statusmsg'  => 'IA.SUGGEST_PRICE',
            );
            $entriesView->findAndSetProperty(array('path' => 'UIPRICE'), array('assists' => $uiPriceAssists));
        }


        //to get the view link in the line entry screen level
        $entriesView->findAndSetProperty(array('path' => 'ITEMID'), array('assist' => 'notfat'));

        if (!$this->isTaskDimensionEnabled) {
            $entriesView->findAndSetProperty(array('path' => 'TASKKEY'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'TASKID'), array('hidden' => true));
        }

        // hide the qty_converted field if non of the lines are converted
        if (!$obj['HASCONVERTEDLINES']) {
            $entriesView->findAndSetProperty(array('path' => 'QTY_CONVERTED'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'PRICE_CONVERTED'), array('hidden' => true));
        }

        // PRICE_CONVERTED & CONVERSIONTYPE filed show only when user enabled both price conversion and override transaction on conversion type
        $priceConversionTypeEnabled = ($this->isPriceConversionEnabled() && $this->isOverrideTrnxConversionTypeEnabled());
        if(!$priceConversionTypeEnabled) {
            $entriesView->findAndSetProperty(['path' => 'PRICE_CONVERTED'], ['hidden' => true]);
        }

        $showVatFieldsForAvaTaxEngine  = $this->showVatFieldsForAvaTaxEngine($obj, $docparmrec);
        $vatDataForView = !empty($obj['ENTRIES'][0]['SUBTOTALSENTRY']);

        $isShiptoEnabled = $isShipToLineItemEnable || $txnIsVatEnabled;
        $taxEngineForCal = GetTaxEngine($this->mod,$obj['TAXSOLUTIONID']);
        $isPymtTaxSupported = $this->getEntityMgr()->isPaymentTaxCaptureSupported();
        $isPymtTaxEnabled = PaymentUtils::isOEPOPaymentTaxCaptureSupported($obj);
        //Added for line level tax feature, todo if line level feature is enabled show tax & tax percentage
        $isLineShiptoEnabled = ($isShiptoEnabled && ($taxEngineForCal  == TaxSolutionManager::TAXMETHOD_I_ADVANCED) && isset($docparmrec)
            && ($docparmrec['SHOW_TOTALS'] == 'true') && $vatDataForView);
        if (!$showVatFieldsForAvaTaxEngine && !($txnIsVatEnabled && $docparmrec['SHOW_TOTALS'] == 'true')) {
            $entriesView->findAndSetProperty(array('path' => 'PERCENTVAL'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'TAXABSVAL'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'LINETOTAL'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'OVERRIDETAXVALUE'), array('hidden' => true));
            $entriesView->findAndSetProperty(array('path' => 'OVERRIDENTAXDETAIL'), array('hidden' => true));
        }
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if ($docMgr->isOverrideTaxSchedForEntryEnabled() && ($txnIsVatEnabled || $docMgr->isAdvancedTaxEnabled() || (in_array($obj['TAXMETHOD'], [TaxSolutionManager::TAXMETHOD_LABEL_ADVANCED, TaxSolutionManager::TAXMETHOD_I_ADVANCED]))) && $docparmrec['SHOW_TOTALS'] == 'true') {
            $entriesView->findAndSetProperty(array('path' => 'TAXSCHEDULEID'), array('hidden' => false));
            $entriesView->findAndSetProperty(array('path' => 'PERCENTVAL'), array('hidden' => false));
            $entriesView->findAndSetProperty(array('path' => 'TAXABSVAL'), array('hidden' => false, 'disabled' => true));
            $entriesView->findAndSetProperty(array('path' => 'LINETOTAL'), array('hidden' => false));
            $entriesView->findAndSetProperty(array('path' => 'OVERRIDETAXVALUE'), array('hidden' => false));
            $entriesView->findAndSetProperty(array('path' => 'OVERRIDENTAXDETAIL'), array('hidden' => false, 'disabled' => true));
        }

        if ($this->ismcpEnabled) {
            $entriesView->findAndSetProperty(array('path' => 'TRX_PRICE'), array('hidden' => false, 'fullname' => 'IA.TRANSACTION_PRICE', 'required' => true));
            $entriesView->findAndSetProperty(array('path' => 'TRX_VALUE'), array('hidden' => false, 'fullname' => 'IA.EXTENDED_PRICE'));
            if ($showVatFieldsForAvaTaxEngine || (($txnIsVatEnabled || $docMgr->isOverrideTypeTax($obj)) && $docparmrec['SHOW_TOTALS'] == 'true')) {
                $entriesView->findAndSetProperty(array('path' => 'TRX_TAXABSVAL'), array('hidden' => false, 'fullname' => 'IA.TAX'));
                $entriesView->findAndSetProperty(array('path' => 'TRX_LINETOTAL'), array('hidden' => false, 'fullname' => 'IA.TRANSACTION_GROSS_AMOUNT'));
            }
            if ($docpar['DISPLAY_BASECURRENCY'] != 'true') {
                $entriesView->findAndSetProperty(array('path' => 'UIPRICE'), array('hidden' => true));
                $entriesView->findAndSetProperty(array('path' => 'UIVALUE'), array('hidden' => true));
                if ($showVatFieldsForAvaTaxEngine || $txnIsVatEnabled || $docMgr->isOverrideTypeTax($obj))
                {
                    $entriesView->findAndSetProperty(array('path' => 'TAXABSVAL'), array('hidden' => true));
                    $entriesView->findAndSetProperty(array('path' => 'LINETOTAL'), array('hidden' => true));
                }
            } else {
                $entriesView->findAndSetProperty(array('path' => 'UIPRICE'), array('fullname' => 'IA.BASE_PRICE'));
                $entriesView->findAndSetProperty(array('path' => 'UIVALUE'), array('fullname' => 'IA.EXTENDED_BASE_PRICE'));
                if ($showVatFieldsForAvaTaxEngine || $txnIsVatEnabled || $docMgr->isOverrideTypeTax($obj))
                {
                    $entriesView->findAndSetProperty(array('path' => 'TAXABSVAL'), array('fullname' => 'IA.BASE_TAX'));
                    $entriesView->findAndSetProperty(array('path' => 'LINETOTAL'), array('fullname' => 'IA.GROSS_BASE_AMOUNT'));
                }
            }
        }
        if ($txnIsVatEnabled) {
            $buttons = [];
            $view->findComponents(null, EditorComponentFactory::TYPE_BUTTONS, $buttons);
            $ix = 0;
            while ($ix < count($buttons)) {
                $buttonData = $buttons[$ix]->getProperty('button');
                if (array_key_exists('id', $buttonData[0]) && $buttonData[0]['id'] == 'subtotalCalculateButton') {
                    $buttonData[0]['events']['click'] = "calculateSubtotalsAjax(true);";
                    $buttons[$ix]->setProperty('button', $buttonData);
                    break;
                }
                $ix++;
            }
            // Allocation is not supported in VAT transactions. Hide the allocation column.
            $entriesView->findAndSetProperty(array('path' => 'ALLOCATION'), array('hidden' => true));

            //Enable Payment tax capture
            if ( $isPymtTaxSupported && $isPymtTaxEnabled ) {
                $entriesView->findAndSetProperty([ 'path' => 'PAYMENTTAXCAPTURE' ], [ 'hidden' => false]);
            }
        }
        $valueFields              = array('TRX_VALUE', 'UIVALUE');
        $priceFields              = array('UIPRICE');
        $precision                = $this->lookupAppPrecision();
        $lineLevelSubtotalTaxType = "";

        if (!is_null($obj['ENTRIES'])) {
            foreach ($obj['ENTRIES'] as &$entry) {
                foreach ($valueFields as $costFld) {
                    if (!$entry[$costFld]) {
                        continue;
                    }
                    $entry[$costFld] = ibcmul($entry[$costFld], '1', DEFAULT_INVPRECISION, false);
                }
                foreach ($priceFields as $costFld) {
                    if (!$entry[$costFld]) {
                        continue;
                    }
                    $precision       = ($entry['ITEM_PRECISION']) ?: $precision;
                    $entry[$costFld] = ibcmul($entry[$costFld], '1', $precision, false);
                }

                // fix is to not to carry trx_price to manager since the field name is ui_price in Non MCP
                if (!$this->ismcpEnabled) {
                    $entry['TRX_PRICE'] = '';
                }
                if ($this->state == $this->kShowNewState && $docpar['LINELEVELSIMPLETAX'] != 'true') {
                    $entry['LINELEVELSIMPLETAXTYPE'] = "";
                }
                if ($lineLevelSubtotalTaxType == "" && $this->state != $this->kShowNewState) {
                    $lineLevelSubtotalTaxType = $entry['LINELEVELSIMPLETAXTYPE'] ?? "";
                }

                if(!empty($scheduleIdMaps) && empty($entry['TAXSCHEDULEKEY'])){
                    $entry['TAXSCHEDULEKEY'] = $scheduleIdMaps[$entry['TAXSCHEDULEID']] ?? null;
                }
                unset($entry);
            }
        }
        $this->processCostLink($entriesView);

        $this->processPickLink($entriesView);

        $kModArray = array('so' => Globals::$g->kSOid, 'po' => Globals::$g->kPOid);
        $isTaxScheduleEnabled = GetPreferenceForProperty($kModArray[$this->mod], 'TAXSCHED');
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        //Only for Avalara configured company
        if (($this->state != 'shownew' || $obj['CUSTVENDNAME'] != '') && $showVatFieldsForAvaTaxEngine || $isLineShiptoEnabled
            || ($docparmrec['LINELEVELSIMPLETAX'] == 'true') || ($txnIsVatEnabled && $docparmrec['SHOW_TOTALS'] == 'true') || ($docparmrec['SHOW_TOTALS'] == 'true' && $isTaxScheduleEnabled === 'T' && $docMgr->isOverrideTaxSchedForEntryEnabled())) {
            $entrySubtotalsArr = array();
            $entriesView->findComponents(array('path' => 'SUBTOTALSENTRY'), EditorComponentFactory::TYPE_GRID, $entrySubtotalsArr);
            $entrySubtotalView = $entrySubtotalsArr[0];
            $entrySubtotalView->setProperty('hidden', false);
            if ( $entrySubtotalView ) {
                if ( $this->ismcpEnabled ) {
                    //$entrySubtotalView->findComponents(array('path' => 'TRX_ABSVAL'), EditorComponentFactory::TYPE_FIELD, $trxabsVals);
                    $entrySubtotalView->findAndSetProperty(array('path' => 'TRX_ABSVAL'), array('hidden' => false));
                    $hide = ($docparmrec['DISPLAY_BASECURRENCY'] != 'true');
                    $entrySubtotalView->findAndSetProperty(array('path' => 'ABSVAL'), array('readonly' => true, 'fullname' => 'IA.BASE_VALUE', 'hidden' => $hide));
                    $entrySubtotalView->findAndSetProperty(array('path' => 'TOTAL'), array('fullname' => 'IA.BASE_TOTAL', 'hidden' => $hide));
                    $entrySubtotalView->findAndSetProperty(array('path' => 'TRX_TOTAL'), array('hidden' => false, 'readonly' => true));
                }
                //Only when VAT is subscribed enable this field
                if ($txnIsVatEnabled) {
                    $entrySubtotalView->findAndSetProperty(array('path' => 'OVERRIDETAXVALUE'), array('hidden' => false));
                    $entrySubtotalView->findAndSetProperty(array('path' => 'OVERRIDENTAXDETAIL'), array('hidden' => false));
                }
            }
        }
        $subtotalTaxDesc = [];
        $entriesView->findComponents(array('path' => 'LINELEVELSIMPLETAXTYPE'), EditorComponentFactory::TYPE_FIELD, $subtotalTaxDesc);
        if ((($docpar['LINELEVELSIMPLETAX'] != 'true' || $isTaxScheduleEnabled == 'T') && $lineLevelSubtotalTaxType == "")
            || (($docpar['LINELEVELSIMPLETAX'] != 'true' || $isTaxScheduleEnabled == 'T') && $this->state != $this->kShowViewState)) {
            foreach ((($subtotalTaxDesc) ?? []) as $key => $overridetax) {
                $subtotalTaxDesc[$key]->setProperty('hidden', true);
            }
        } else {
            $lineLevelSimpleTaxField = $subtotalTaxDesc[0]->getProperty('type');
            $lineLevelSimpleTaxField['restrict'][] = array('field' => 'DOCPARNO',
                                                           'pickField' => 'DOCPARNO',
                                                           'operand' => '=',
                                                           'value' => ($this->state == 'shownew' || !empty($obj['_DOCPAR']['RECORDNO'])) ? $obj['_DOCPAR']['RECORDNO'] : $obj['DOCPARKEY']);
            $subtotalTaxDesc[0]->setProperty('type', $lineLevelSimpleTaxField);
        }

        //Hide line level simple tax type column in multitax company
        if (TaxSetupManager::isTaxModuleConfigured() && ($taxEngineForCal != TaxSolutionManager::TAXMETHOD_I_SIMPLE
            || !(DocumentManager::hasTaxSubTotals($obj['_DOCPAR'])))) {
            foreach ((($subtotalTaxDesc) ?? []) as $key => $overridetax) {
                $subtotalTaxDesc[$key]->setProperty('hidden', true);
            }
        }
    }

    /**
     * @param EditorView $entriesView
     * @param string $refType
     */
    protected function processItemAliasID($entriesView, $refType)
    {
        $itemCrossRefMgr = Globals::$g->gManagerFactory->getManager('itemcrossref');

        $recordCount = $itemCrossRefMgr->hasItemCrossReferences([$refType]);

        if ($recordCount <= 0) {
            $entriesView->findAndSetProperty(array('path' => 'ITEMALIASID'),
                                             array('hidden' => true,)
            );
        }
    }

    /**
     * @return string[]
     */
    protected function getItemPickRestrictParams()
    {
        $restrictItemTypes = array();
        $restrictItemTypes[] = 'PS';

        global $kINVid;

        GetModulePreferences($kINVid, $prefs);

        // if Kit is not enabled
        if ( !IsKitEnabled() ) {
            $restrictItemTypes[] = 'K';
        }
        // if Kit is not enabled

        if ( $prefs['LIGHTASSEMBLY'] != 'T' ) {
            $restrictItemTypes[] = 'SK';
        }

        return $restrictItemTypes;
    }

    /**
     * @return bool
     */
    protected function hideHistoryPage()
    {
        $_createdfrom = Request::$r->_createdfrom;

        if ( $this->state == 'shownew' && $_createdfrom != ConversionManager::getmultipleSourceDocsText() ) {
            return true;
        }
        return false;
    }

    /**
     * @param array $obj
     */
    protected function mediateDataAndMetadata_History(&$obj)
    {
        $view = $this->getView();

        $matches = array();
        $view->findComponents(array('id' => 'historyPage'), null, $matches);
        if ( $matches ) {
            $historyTab = $matches[0];
        }

        if ( $this->hideHistoryPage() ) {
            /** @noinspection PhpUndefinedVariableInspection */
            $historyTab->parent->removeChild($historyTab);
            return;
        }

        $docpar = $this->GetBaseDocPar();

        $historyViewArr = array();
        $view->findComponents(array('path' => 'HISTORY'), EditorComponentFactory::TYPE_GRID, $historyViewArr);
        $historyView = $historyViewArr[0];

        //$historyView->setProperty('readonly', true);

        $docidFields = array();
        $historyView->findComponents(array('path' => 'DOCUMENTID'), EditorComponentFactory::TYPE_FIELD, $docidFields);
        // $historyView->findComponents(array('path' => 'SOURCEDOCUMENTID'), EditorComponentFactory::TYPE_FIELD, $docidFields);

        $docStates = array();
        $historyView->findComponents(array('path' => 'DOCSTATE'), EditorComponentFactory::TYPE_FIELD, $docStates);

        $auWhenCreated = array();
        $view->findComponents(array('path' => 'AUWHENCREATED'), EditorComponentFactory::TYPE_FIELD, $auWhenCreated);
        foreach ( $auWhenCreated as $whenCreated ) {
            $whenCreated->setProperty('hidden', false);
            $whenCreated->setProperty('fullname', 'IA.CREATED_DATE');
        }

        foreach ( $docidFields as $docidField ) {
            $docIdValue = $docidField->getProperty('value');
            if ( $docIdValue == ConversionManager::getmultipleSourceDocsText() ) {
                $docidField->setProperty('onclick', "ShowSourceDocsMenu(this, 'SourceDocsMenu_History'); return false;");
            } else {
                $docidField->setProperty('onclick', "LaunchHistoryLink(this);");
            }
        }

        $IsSalecontract = Request::$r->_salecon;

        if ($IsSalecontract == 'T' || $this->dt == BUILD_KIT || $this->dt == DIS_KIT) {
            $entries = $obj['ENTRIES'] ?? [];
            $totalLineCount = count($entries);
            foreach ( (($obj['HISTORY']) ?? []) as $indx => $history ) {
                $this->setHistoryValuesByRow($obj, $indx, $history, $totalLineCount);
            }
        }

        $docConfigFlds = array();
        $historyView->findComponents(array('path' => 'DOCCONFIG'), EditorComponentFactory::TYPE_FIELD, $docConfigFlds);
        foreach ( $docConfigFlds as $docConfigFld ) {
            $docConfigFld->setProperty('displayValue', I18N::getSingleToken('IA.DEFINITION'));
            $docConfigFld->setProperty('onclick', "LaunchDefinitionLink(this);");
        }

        $recurhistoryViewArr = array();
        $view->findComponents(array('path' => 'RECURHISTORY'), EditorComponentFactory::TYPE_GRID, $recurhistoryViewArr);

        $recurhistoryView = $recurhistoryViewArr[0];

        if ( $recurhistoryView ) {
            if ( isset($docpar) && $docpar['ENABLESCHEDULE'] == 'true' ) {
                $recurhistoryView->setProperty('hidden', false);
            }

            if ((!empty($obj['RECURHISTORY'])) && $recurhistoryView ) {
                // Recurring History part

                // Adding Sales contract info, in the history tab, and showing it only if the document is having any contract info

                $recurrecs = array();
                $recurhistoryView->findComponents(array('path' => 'RECURRECNO'), EditorComponentFactory::TYPE_FIELD, $recurrecs);
                /** @noinspection PhpUndefinedVariableInspection */
                $recurhistoryView->findComponents(array( 'path' => 'LINENO'), EditorComponentFactory::TYPE_FIELD, $linenos);
                /** @noinspection PhpUndefinedVariableInspection */
                $recurhistoryView->findComponents(array( 'path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $uivalues);

                foreach ( $recurrecs as $recurrec ) {
                    $recurrec->setProperty('displayValue', GT($this->textMap, 'IA.TEMPLATE'));
                    $recurrec->setProperty('onclick', "LaunchOriginalRecurDocument(this);");
                    $recurrec->setProperty('statusmsg', 'IA.VIEW_DOCUMENT_TEMPLATE');

                    //$linenos[$key]->setProperty('value', $historyData['LINENO']);
                    //$uivalues[$key]->setProperty('value', $historyData['UIVALUE']);
                }

                // Because the path 'UIVALUE' is same as the documententry.ent's UIVALUE, we have to make this hidden false forcefully for mcp companies.
                /**
                 * @var EditorComponent[] $uivalues
                 */
                foreach ( $uivalues as $uivalue ) {
                    $uivalue->setProperty('hidden', false);
                }


                $recurtrxs = array();
                $recurhistoryView->findComponents(array('path' => 'RECURTRANSACTION'), EditorComponentFactory::TYPE_FIELD, $recurtrxs);
                foreach ( $recurtrxs as $recurtrx ) {
                    $recurtrx->setProperty('displayValue', GT($this->textMap, 'IA.TRANSACTIONS'));
                    $recurtrx->setProperty('onclick', "LaunchRecurDocTemplates(this);");
                    $recurtrx->setProperty('statusmsg', 'IA.VIEW_DOCUMENT');
                }
            } else {
                $recurhistoryView->parent->removeChild($recurhistoryView);
            }
        }
        // Recurring History part
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

        // On the off chance the form has ties to Supplies Inventory, show the Supplies history
        // (this is quick if there are no ties)
        if (ItemManager::isSuppliesInventoryEnabled()) {
            $suppliesManager        = Globals::$g->gManagerFactory->getManager('invsupplies');
            $history                = $suppliesManager->suppliesHistory( $obj );
            if (($history !== false) && ( ! empty($history))) {
                $obj['SUPPLIESHISTORY'] = $history;
                $historyGrid = [];
                $view->findComponents(array('path' => 'SUPPLIESHISTORY'), EditorComponentFactory::TYPE_GRID, $historyGrid);
                if (isset($historyGrid[0])) {
                    $historyGrid[0]->setProperty('hidden', false);
                    $fields       = [];
                    $session      = Session::getKey();
                    $docviewPOop  = GetOperationId("po/lists/podocument/view");
                    $docviewINVop = GetOperationId("inv/lists/invdocument/view");
                    $historyGrid[0]->findComponents(array( 'path' => 'SUPPLYDOCUMENT'), EditorComponentFactory::TYPE_FIELD, $fields);

                    foreach ( $fields as $index => $docidField ) {
                        // the document could be a purchase document (supply request, PO) or inventory (Transfer, Issue, Return)
                        $spiField = $history[$index]['SPI'] ?? '';
                        $docId    = $history[$index]['SUPPLYDOCUMENT'] ?? '';
                        $isPO     = ($spiField === 'P');
                        $mod      = $isPO ? 'po' : 'inv';
                        // setup the href link for clicking on DOCID
                        $url      = 'editor.phtml?.sess=' . $session . '&.op=' . ($isPO ? $docviewPOop : $docviewINVop)
                                    . '&.mod=' . $mod . '&.r=' . urlencode($docId) . '&.popup=1';
                        $docidField->setProperty('onclick', "Launch('$url','mywindow','700','500');" );
                    }

                    $invviewop = GetOperationId("inv/lists/item/view");
                    $fields    = [];
                    $historyGrid[0]->findComponents(array( 'path' => 'ITEM'), EditorComponentFactory::TYPE_FIELD, $fields);
                    foreach ( $fields as $index => $docidField ) {
                        // setup the href link for clicking on ITEM
                        $item     = $history[$index]['ITEM'] ?? '';
                        $docidField->setProperty('onclick', "LaunchObjLink(this, , 'inv');");
                        $url      = 'editor.phtml?.sess=' . $session . '&.op=' . $invviewop
                            . '&.mod=inv&.r=' . urlencode($item) . '&.popup=1';
                        $docidField->setProperty('onclick', "Launch('$url','mywindow','700','500');" );
                    }
                }
            }
        }
    }


    /**
     * @param array   $obj
     * @param string $indx
     * @param array  $history
     * @param int   $totalLineCount
     *
     * @return bool
     */
    protected function setHistoryValuesByRow(&$obj, $indx, $history, $totalLineCount)
    {
        if ( $obj['HASPARTIALCONVLINES'] && $obj['NOOFCONVERTEDLINES'] < $totalLineCount  && $history['DOCSTATE'] == 'Pending' ) {
            $obj['HISTORY'][$indx]['DOCSTATE'] = GT($this->textMap, 'IA.PARTIALLY_CONVERTED_BY_LINE');
        }
        return true;
    }

    // Only subclass would override this function.

    /**
     * @param array $obj
     * @param array $docpar
     */
    protected function mediateDataAndMetadata_Payments(&$obj, $docpar)
    {
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_Subtotals(&$obj, $docparmrec)
    {

        $view = $this->getView();

        // subtotals part
        $subtotalsArr = array();
        $view->findComponents(array('path' => 'SUBTOTALS'), EditorComponentFactory::TYPE_GRID, $subtotalsArr);
        $subtotalView = $subtotalsArr[0];

        if (!isset($docparmrec) || !$docparmrec['SHOW_TOTALS'] || $docparmrec['SHOW_TOTALS'] == 'false') {
            $subtotalView->parent->removeChild($subtotalView);
            $view->findComponents(array('path' => 'SUBTOTALSENTRY'), EditorComponentFactory::TYPE_GRID, $subtotalsEntry);
            if ($subtotalsEntry && $subtotalsEntry[0]) {
                $subtotalsEntry[0]->parent->removeChild($subtotalsEntry[0]);
            }
            return;
        }

        if ( $subtotalView ) {
            $subTotalObj = GetSubTotalsHelper($this->mod);
            $allowEditingSubtotalDimensionsAtRoot = $subTotalObj->_overrideDimensionsFromSubtotals;

            /*
             * In View mode, remove the calculate subtotals button
             */
            if ( $this->state == 'showview' ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $subtotalView->findComponents(array( 'id' => 'subtotalCaption'), EditorComponentFactory::TYPE_CAPTION, $subtotalsButton);

                if ( $subtotalsButton && $subtotalsButton[0] ) {
                    $subtotalsButton[0]->parent->removeChild($subtotalsButton[0]);
                }
            }

            $percentEdits = array();
            $percentVals = array();
            $absEdits = array();
            $absVals = array();
            //$taxDetails = array();

            $subtotalView->findComponents(array('path' => 'PERCENTEDIT'), EditorComponentFactory::TYPE_FIELD, $percentEdits);
            $subtotalView->findComponents(array('path' => 'PERCENTVAL'), EditorComponentFactory::TYPE_FIELD, $percentVals);
            $subtotalView->findComponents(array('path' => 'ABSEDIT'), EditorComponentFactory::TYPE_FIELD, $absEdits);
            $subtotalView->findComponents(array('path' => 'ABSVAL'), EditorComponentFactory::TYPE_FIELD, $absVals);

            if ( $this->ismcpEnabled ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $subtotalView->findComponents(array( 'path' => 'TRX_ABSVAL'), EditorComponentFactory::TYPE_FIELD, $trxabsVals);
                $subtotalView->findAndSetProperty(array('path' => 'TRX_ABSVAL'), array('hidden' => false));
                $hide = ($docparmrec['DISPLAY_BASECURRENCY'] != 'true');
                $subtotalView->findAndSetProperty(array('path' => 'ABSVAL'), array('readonly' => true, 'fullname' => 'IA.BASE_VALUE', 'hidden' => $hide));
                $subtotalView->findAndSetProperty(array('path' => 'TOTAL'), array('fullname' => 'IA.BASE_TOTAL', 'hidden' => $hide));
                $subtotalView->findAndSetProperty(array('path' => 'TRX_TOTAL'), array('hidden' => false, 'readonly' => true));
            }

            $subtotalView->findAndSetProperty(array('path' => 'TAXDETAIL'), array('hidden' => true));

            //TODO :: Remove Loc & Dept from XML only.
            //If company is Avalara enabled then hide the Dept and Loc for subtotals
            $showVatFieldsForAvaTaxEngine = $obj['_isVatEnabled']; //If VAT field enabled then no need to show dept & loc
            $subtotalView->findAndSetProperty(array('path' => 'DEPARTMENT'), array('hidden' => !$this->deptOverride || $showVatFieldsForAvaTaxEngine));
            $subtotalView->findAndSetProperty(array('path' => 'LOCATION'), array('hidden' => !$this->locOverride || $showVatFieldsForAvaTaxEngine));

            if ( IsMultiEntityCompany() ) {
                $hideLocDept = !GetContextLocation() || $showVatFieldsForAvaTaxEngine;

                if ($subTotalObj->_overrideLocDeptAtTopLevel
                    && $subTotalObj->_overrideDimensionsFromSubtotals) {
                    $hideLocDept = false;
                    $subtotalView->findAndSetProperty(array('path' => 'DEPARTMENT'), array('clazz' => ''));
                    $subtotalView->findAndSetProperty(array('path' => 'LOCATION'), array('clazz' => ''));
                    $subtotalView->findAndSetProperty(array('path' => 'LOCATION'), array('required' => false));
                }

                $subtotalView->findAndSetProperty(array('path' => 'DEPARTMENT'), array('hidden' => $hideLocDept));
                $subtotalView->findAndSetProperty(array('path' => 'LOCATION'), array('hidden' => $hideLocDept));
            }

            $subtotcount = Util::countOrZero($obj['SUBTOTALS']);
            if ($subtotcount > 0) {
                if ($obj['SUBTOTALS'][0]['DESCRIPTION'] == 'SUBTOTAL') {
                    $obj['SUBTOTALS'][0]['DESCRIPTION'] =  GT($this->textMap,'IA.SUBTOTALS_SECTION_SUBTOTAL_CONSTANT_LABEL');
                }
                if ($obj['SUBTOTALS'][$subtotcount - 1]['DESCRIPTION'] == 'TOTAL') {
                    $obj['SUBTOTALS'][$subtotcount - 1]['DESCRIPTION'] =  GT($this->textMap,'IA.SUBTOTALS_SECTION_TOTAL_CONSTANT_LABEL');
                }
            }

            foreach ( (($obj['SUBTOTALS']) ?? []) as $key => $subTotal ) {

                if ( $obj['SUBTOTALS'][$key]['PERCENTVAL'] != 1 && $percentVals[$key] ) {
                    $percentVals[$key]->setProperty('readonly', true);
                    if ( $percentVals[$key]->getProperty('value') == 0 ) {
                        $percentVals[$key]->setProperty('value', "");
                    }
                }

                // Toggle between ABSVAL/TRX_ABSVAL

                $absFld = $absVals[$key];
                if ( $this->ismcpEnabled ) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $absFld = $trxabsVals[$key];
                    // for a mcp company always make the ABSVAL field as readonly.
                    if ( $absVals[$key] ) {
                        $absVals[$key]->setProperty('readonly', true);
                        if ( $absVals[$key]->getProperty('value') == 0 ) {
                            $absVals[$key]->setProperty('value', "");
                        }
                    }
                }


                if ( $absFld && $absEdits[$key] && $absEdits[$key]->getProperty('value') != 1 ) {
                    $absFld->setProperty('readonly', true);
                    if ( $absFld->getProperty('value') == 0 ) {
                        $absFld->setProperty('value', "");
                    }
                }
            }

            //Only for Avalara configured company
            if($showVatFieldsForAvaTaxEngine) {
                /**
                 * @var EditorComponent[] $subtotalLineDetailsViews
                 */
                $subtotalView->findComponents(array('id' => 'subtotalDimPage'), EditorComponentFactory::TYPE_SECTION, $subtotalLineDetailsViews);
                $subtotalLineDetailsView = $subtotalLineDetailsViews[0];
                $subtotalLineDetailsView->setProperty('hidden', true);
            } else {
                $subTotalDimensions = IADimensions::GetDimensionIDs(!util_isPlatformDisabled());


                // for subtotals section no primary dimension should be displayed.
                $primaryDimension = $this->getEntityMgr()->getPrimaryDimensions();
                foreach ( $primaryDimension as $primaryDim => $primaryDimHdrVal ) {
                    $primaryDimensionFld = array();
                    $subtotalView->findComponents(array('path' => $primaryDim), EditorComponentFactory::TYPE_FIELD, $primaryDimensionFld);
                    if ( $primaryDimensionFld[0] ) {
                        $primaryDimensionFld[0]->parent->removeChild($primaryDimensionFld[0]);
                    }
                }

                if (!$allowEditingSubtotalDimensionsAtRoot) {
                    foreach ($subTotalDimensions as $dimension) {
                        if ($dimension && !isset($primaryDimension[$dimension])) {
                            $subtotalView->findAndSetProperty(array('path' => $dimension),
                                array('clazz' => 'SubtotalDimensionField'));
                        }
                    }
                }

                if ($subTotalObj->_distributeSubtotalsAtEntity) {
                    $subtotalView->findAndSetProperty(array('path' => 'DEPARTMENT'), array('clazz' => 'SubtotalReadOnlyDimension'));
                    $subtotalView->findAndSetProperty(array('path' => 'LOCATION'), array('clazz' => 'SubtotalReadOnlyDimension'));
                }
            }
        } // end subtotals part
    }

    /**
     * @param EditorView    $view
     */
    protected function ShowAtlasControls($view)
    {

        if ( !GetContextLocation() ) {
            $qop = GetOperationId('co/lists/exchangerate/view');
            $_sess = Request::$r->_sess;
            $basecurr = GetBaseCurrency();
            $forma = GetUserDateFormat();

            $atlasfields = array();
            $view->findComponents(array('path' => 'BASECURR'), EditorComponentFactory::TYPE_FIELD, $atlasfields);
            $view->findComponents(array('path' => 'CURRENCY'), EditorComponentFactory::TYPE_FIELD, $atlasfields);

            if ( $this->mod != 'inv' ) {
                $view->findComponents(array('path' => 'LOCATION'), EditorComponentFactory::TYPE_FIELD, $atlasfields);
            }

            foreach ( $atlasfields as $atlasfield ) {
                $fldPath = $atlasfield->getProperty('path');
                if ( $fldPath == 'BASECURR' ) {
                    $atlasfield->setProperty('hidden', false);
                    $atlasfield->setProperty('required', true);
                    if ( $this->state == 'showview' ) {
                        $atlasfield->setProperty('readonly', true);
                    } else {
                        if ( $this->ismcpEnabled ) {
                            $onchange = "UpdateExchangeRate(" . "'$_sess', $qop, '$basecurr', '$forma');";
                            $atlasfield->setProperty('onchange', $onchange);
                        }
                    }
                }
                // ZZZ WW: YOU CANNOT COMPARE AGAINST A USER VISIBLE STRING.
                if ( $fldPath == 'LOCATION' && $atlasfield->getProperty('fullname') == 'IA.LOCATION' ) {
                    $atlasfield->setProperty('required', true);
                }
            }
        } else {
            if ( $this->do == 'view' ) {
                $view->findComponents(array('path' => 'BASECURR'), EditorComponentFactory::TYPE_FIELD, $atlasfields);
                /**
                 * @var EditorComponent[] $atlasfields
                 */
                foreach ( $atlasfields as $fld ) {
                    $fld->setProperty('hidden', false);
                }
            }
        }
    }


    /**
     * @param array           $obj
     * @param EditorView    $view
     * @param string       $docpar_exchratename
     * @param string $displaybaseCurrency
     * @param string $overrideExchRateType
     *
     * @throws Exception
     */
    protected function ShowMCPControls(&$obj, $view, $docpar_exchratename, $displaybaseCurrency='false', $overrideExchRateType='false')
    {
        global $gManagerFactory;

        $copymode = Request::$r->_copymode;

        $basecurr = GetBaseCurrency();

        $currencyfields = array();
        $view->findComponents(array('path' => 'CURRENCY'), EditorComponentFactory::TYPE_FIELD, $currencyfields);
        $view->findComponents(array('path' => 'EXCHRATEDATE'), EditorComponentFactory::TYPE_FIELD, $currencyfields);
        $view->findComponents(array('path' => 'EXCHRATETYPES.NAME'), EditorComponentFactory::TYPE_FIELD, $currencyfields);
        $view->findComponents(array('path' => 'EXCHRATE'), EditorComponentFactory::TYPE_FIELD, $currencyfields);

        if ( $currencyfields ) {
            $exchMgr =  $gManagerFactory->getManager('exchangeratetypes');
            $rtype = $exchMgr->GetDefaultExchangeRateType();
            $currentDate = GetCurrentDate();

            foreach ( $currencyfields as $currencyfield ) {

                $fldPath = $currencyfield->getProperty('path');
                $fldValue = $currencyfield->getProperty('value');

                $currencyfield->setProperty('hidden', false);

                // add QRequest for getting exchange rate
                if ( $fldPath != 'EXCHRATE' ) {
                    $onChange = $currencyfield->getProperty('onchange');
                    $onChange .= "UpdateExchangeRate();";
                    $currencyfield->setProperty('onchange', $onChange);
                } else {
                    if ( $currencyfield->getProperty('value') != '' ) {
                        $currencyfield->setPropety('value', ibcmul($fldValue, '1', 8, false));
                    }
                }

                if ( $this->state == $this->kShowNewState ) {
                    if ( $fldPath == 'CURRENCY' ) {
                        //$currencyfields[$k]['required'] = true;
                        $currencyfield->setProperty('required', true);
                        if ( $obj['CURRENCY'] == '' && !Profile::getProperty('SFORCEKEY') ) {
                            $obj['CURRENCY'] = $basecurr;
                            //$currencyfield->setProperty('value', $basecurr);
                        }
                        if ( $copymode == 'Update' ) {
                            $currencyfield->setProperty('readonly', true);
                        }
                    }

                    if ( $fldPath == 'EXCHRATETYPES.NAME' && $obj['EXCHRATETYPES']['NAME'] == '' ) {
                        if ( isset($docpar_exchratename) && $docpar_exchratename != '' ) {
                            $obj['EXCHRATETYPES']['NAME'] = $docpar_exchratename;
                            //$currencyfield->setProperty('value', $docpar_exchratename);
                        } else {
                            $obj['EXCHRATETYPES']['NAME'] = $rtype[0]['NAME'];
                            //$currencyfield->setProperty('value', $rtype[0]['NAME']);
                        }
                    }
                    if ( $fldPath == 'EXCHRATEDATE' ) {
                        if ( $obj[$fldPath] == '' ) {
                            $obj[$fldPath] = $currentDate;
                        }
                    }
                }

                if ( $fldPath == 'EXCHRATETYPES.NAME' || $fldPath == 'EXCHRATE' ) {
                    if ( isset($overrideExchRateType) && $overrideExchRateType != 'true' ) {
                        $currencyfield->setProperty('disabled', true);
                        $currencyfield->setProperty('nocalc', true);
                    }
                }
            }
        }
        $pricefields = array();
        $view->findComponents(array('path' => 'UIPRICE'), EditorComponentFactory::TYPE_FIELD, $pricefields);
        $view->findComponents(array('path' => 'UIVALUE'), EditorComponentFactory::TYPE_FIELD, $pricefields);
        if ( $pricefields ) {
            $hide = ($displaybaseCurrency == 'true') ? false : true;
            foreach ( $pricefields as $pricefield ) {
                $pricefield->setProperty('disabled', true);
                $pricefield->setProperty('hidden', $hide);
                $pricefield->setProperty('required', $hide);
                $pricefield->setProperty('hasTotal', false);
                /** @noinspection PhpUndefinedVariableInspection */
                if ( $fld['path'] == 'UIVALUE' ) {
                    $pricefield->setProperty('nocalc', true);
                }
            }
        }
    }

    //This function is to hide cost link in any mode other than edit and view
    // function ProcessHideCostLink(&$_params){
    /**
     * @param EditorComponent $entriesView
     */
    protected function processCostLink($entriesView)
    {
        $docid = Request::$r->_r;
        $affectsValue = IsDocumentAffectsValue($docid);

        if ( $affectsValue && $this->state != 'shownew' ) {
            $propVals = array('hidden' => false,
                              'readonly' => false,
                              'hreftxt' => 'Cost',
            );
            $entriesView->findAndSetProperty(array('id' => 'COSTLINK'), $propVals, EditorComponentFactory::TYPE_LINK);
        }
    }

    /**
     * @param EditorComponent $entriesView
     */
    protected function processPickLink($entriesView)
    {

        if ( $this->isAdvancedSetup && $this->affectsOnHandQty && CheckAuthorization(GetOperationId('inv/reports/physicalinventory'), 1) ) {
            $propVals = array('hidden' => false,
                              'readonly' => true,
                              'hreftxt' => 'Pick',
            );
            $entriesView->findAndSetProperty(array('id' => 'PICKLIST'), $propVals, EditorComponentFactory::TYPE_LINK);
        }
    }


    /**
     * @param string[]      $_layout
     * @param array   $obj
     *
     * @return int
     */
    public function FigureOutNumOfRows($_layout, &$obj = null)
    {
        if ($_layout['path'] == 'SUBTOTALS') {
            //$obj =& $gRequest->GetCurrentObject();
            $accessByPath = EntityManager::AccessByPath($obj, $_layout['path']);
            $numOfRowsInTheInstance = is_countable($accessByPath) ? count($accessByPath) : 0;
            //Picking up total no. of subtotal lines to be used later in Autofill() , for populating default dept and loc
            Request::$r->_subtotalCount = $numOfRowsInTheInstance;
            return $numOfRowsInTheInstance;
        } else {

            if ($_layout['path'] == 'ENTRIES' && $obj['ADJDOCHDRID']) {
                $_layout['hasFixedNumOfRows'] = true;
            }
            return parent::FigureOutNumOfRows($_layout, $obj);
        }
    }


    /**
     * @param string $docid
     *
     * @return false|string[][]
     */
    protected function getSourceDocs($docid)
    {
        $cny = GetMyCompany();

        $qry = "SELECT sourcedocument.docid
                      FROM 
                           dochdrmst sourcedocument
                     WHERE 
                       sourcedocument.cny#= :1
                       and exists
                       (select 1 from docentry,
                           dochdrmst document
                          where 
                           document.cny# = :1
                           AND docentry.cny# = :1
                           AND document.docid = :2
                           AND docentry.dochdrkey = document.record#
                           AND docentry.source_dockey = sourcedocument.record#
                       )";

        $result = QueryResult(array($qry, $cny, $docid ));

        return $result;
    }

    /**
     * @return string[]
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles = array(
            '../resources/js/allocation_helper.js',
            '../resources/thirdparty/fancybox/jquery.mousewheel-3.1.13.min.js',
            '../resources/thirdparty/fancybox/fancybox.js',
            '../resources/js/documenteditor_new.js',
            '../resources/js/cre/multidoc.js',
            '../resources/js/mvdocument.js',
            '../resources/js/apar.js',
            '../resources/js/polyfill/promise.js',
            '../resources/js/qrequest.js',
            '../resources/js/project_helper.js',
            '../resources/js/glposting.js',
            '../resources/js/trackingmgr.js',
            '../resources/js/retainagerelease.js',
            '../resources/js/oeinvouttrackinggrid.js'
        );

        if ($this->ismcpEnabled) {
            $jsfiles[] = "../resources/js/mcdoceditor_new.js";
        }
        return $jsfiles;
    }

    /**
     * @return string[]
     */
    protected function getCssFileNames()
    {
        return array( '../resources/thirdparty/fancybox/jquery.fancybox-1.3.4.css' );
    }

    /**
     * @return string
     */
    public function getDocType()
    {
        return $this->dt;
    }

    /**
     * @return string[]
     * @throws Exception
     */
    protected function getEditorGlobals()
    {
        global $gManagerFactory;

        $vars = parent::getEditorGlobals();

        $_op = Request::$r->_op;
        $_sess = Session::getKey();
        $copy = Request::$r->_copymode;

        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
        $baseCurrency = GetBaseCurrency();

        $r = Request::$r->_r;
        $opid = GetOperationId($this->mod . '/lists/' . $this->getEntity() . '/create');

        $sDocs = [];
        if ( $this->sourceDocsArr ) {
            $sDocs = $this->sourceDocsArr;
        } else {
            // in edit mode get the source documents if the document is converted by multiple documents
            $sourceDocs = $this->getSourceDocs($r);
            foreach ( $sourceDocs as $sDoc ) {
                $this->sourceDocsArr[] = $sDoc['DOCID'];
                $sDocs[] = "['" . $sDoc['DOCID'] . "']";
            }
        }
        if (!empty($sDocs)) {
            $sourceDocsjs = '[' . join(',', $sDocs) . ']';
        } else {
            $sourceDocsjs = null;
        }

        // to get the in/out , to be passed to slbinfoclick function
        $docpar = $this->GetBaseDocPar();


        $isReturn = isReturnDocument($docpar);

        $parentid = GetParentID($r, $copy, $isReturn);

        $obj = Request::$r->GetCurrentObject();

        $isBackOrder = false;
        if ( $this->do == 'edit' || $this->do == 'view' ) {
            $docid = $r;

            if ( $obj['BACKORDER'] == 'Yes' ) {
                $isBackOrder = true;
            }
        } else {
            $docid = '';
        }
        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->mod];


        $overrideExchRateType = $docpar['OVERRIDE_EXCH_RATE_TYPE'];
        $in_out = $docpar['IN_OUT'];
        $docparRecno = $docpar['RECORDNO'];
        $enablerevrec = $docpar['ENABLEREVREC'];
        $renewalsEnabled = $docpar['ENABLERENEWALS'];
        $enableoverridetax = $docpar['ENABLEOVERRIDETAX'];
        $discONExtendedPrice = $docpar['DISCOUNT_ON_EXTENDEDPRICE'] == 'true'
            ? 'T' : 'F';

        $updatesInventory = $docpar['UPDATES_INV'];

        $UICacheObjects = GetCacheObjectsForUIValidation($this->mod, $spi, $obj);

        $js_terms = $UICacheObjects['TERM'];

        $js_uoms = $UICacheObjects['UOM'];

        $docparamsArr = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_GET_JSPARAMS', array($spi));
        foreach ((( $docparamsArr) ?? []) as $docrow ) {
            $docjsparams[$docrow['DOCID']] = $docrow;
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $docparjs = $docjsparams;
        //	Get the Fractional Precision related info here
        $appPrecision = $this->lookupAppPrecision();

        $shouldProrate = 'false';
        $IsComingFromSFDC = (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') ? true : false;

        if ( $docpar['OVERRIDE_PRICE'] == 'true' ) {
            if ( $IsComingFromSFDC ) {
                $SFDCPrefMgr = $gManagerFactory->getManager('sforcesetup');
                $SFDCPref = $SFDCPrefMgr->get('');
                if ( $SFDCPref['SFORCEPRICINGOPT'] == 'I' ) {
                    $shouldProrate = 'true';
                }
            } else {
                $shouldProrate = 'true';
            }
        }

        GetModulePreferences('7.INV', $invprefs);
        $defaultUOMGrp = $invprefs['DEFAULT_UOMGRP'];

        // for fulfillment
        $isFulfillmentPrefEnabled = false;
        if ($invprefs['ENABLEFULFILLMENT'] === 'T') {
            $enableFulfillmentFlag = ($docpar['ENABLEFULFILLMENT'] ?? 'false');
            $isFulfillmentPrefEnabled = (($enableFulfillmentFlag === 'T') || ($enableFulfillmentFlag === 'true')) ||
                ($docpar['DOCID'] === SODocumentManager::FULFILLMENTORDERDOCTYPE) ||
                ($docpar['DOCID'] === SODocumentManager::FULFILLMENTINVOICEDOCTYPE) ||
                ($docpar['DOCID'] === SODocumentManager::FULFILLMENTSHIPPERDOCTYPE);
        }

        $isSupplyRequest = ($docpar['DOCID'] === PODocumentManager::SUPPLIESREQUESTDOCTYPE);

        GetUserPreferences($upref);
        $upref_docpar_whse = $upref['DEFAULT_WAREHOUSE'];
        if ( $upref_docpar_whse == '' && $docpar['DEFAULT_WAREHOUSE'] != '' ) {
            $upref_docpar_whse = $docpar['DEFAULT_WAREHOUSE'];
        }

        GetModulePreferences('8.SO', $prefs);
        $isLineDiscountOnSuggestedPrice = $prefs['PRICING.LINEDISCOUNTONSUGGESTEDPRICE'];
        // Used for title
        $dict = Dictionary::getInstance();
        if ( $this->mod == 'po' ) {
            $title = GT($this->textMap, 'IA.VENDOR');
            $objop = GetOperationId('ar/lists/vendor');
        } elseif ( $this->mod == 'so' ) {
            $title = GT($this->textMap, 'IA.CUSTOMER');
            $objop = GetOperationId('ar/lists/customer');
        } else {
            $title = null;
            $objop = null;
        }

        $modulesForFutureDateValidation = $this->getModulesForFutureDateValidation($docpar['UPDATES_GL']);
        foreach ($modulesForFutureDateValidation as $moduleToValidate) {
            /*
             * Only set this global variable if posting to a (sub)ledger, in which case we wish to
             * override the global value determined by our parent with this document-specific one.
             */
            $futureDateAction = GetGLPostingDateCheck($moduleToValidate);
            if ($futureDateAction != '' && $futureDateAction != 'NOCHECK') {
                $vars['glpostingdatecheck'] = $futureDateAction;
                // Since this is for the UI, the first WARN or DISALLOW is sufficient to act on
                break;
            }
        }

        $vars['istrackingenabled'] = IsTrackingEnabled();
        $vars['isAdvancedSetup'] = $this->isAdvancedSetup;
        $vars['affectsOnHandQty'] = $this->affectsOnHandQty;
        $vars['enableCalculate'] = true;
        $vars['discountProratePrice'] = array();
        $vars['isLineDiscountOnSuggestedPrice'] = $isLineDiscountOnSuggestedPrice;
        $vars['sfdcpricing'] = $this->sfdcPricing ?? 'false';
        $vars['copymode'] = $copy;
        $vars['_copymode'] = $copy;
        $vars['datefmt'] = GetUserDateFormat();
        $vars['mod'] = $this->mod;
        $vars['uom_arr'] = $js_uoms;
        $vars['term_arr'] = $js_terms;
        $vars['app_precision'] = $appPrecision;
        $vars['projectop'] = GetOperationId('ar/lists/project');
        $vars['restrictproject'] = (IADimensions::IsDimensionEnabled('so', 'project')) ? 'true' : 'false';
        $vars['isInvModuleSubscribed'] = IsInstalled(Globals::$g->kINVid);
        $vars['isFulfillmentPrefEnabled'] = $isFulfillmentPrefEnabled;
        $vars['isSupplyRequest'] = $isSupplyRequest;

        $vars['menu'] = null;
        //$vars['doctypes'] = $js_doctypes;
        //$vars['doctypesCopy'] = $js_doctypesFull;
        $vars['op'] = $opid;
        $vars['docid'] = $r;
        $vars['overrideExchRateType'] = $overrideExchRateType;
        $vars['newdocid'] = $docid;
        $vars['parentid'] = $parentid;
        $vars['docmode'] = $this->do;
        $vars['docparRecno'] = $docparRecno;
        $vars['prrecordkey'] = $obj['PRRECORDKEY'];
        $vars['dochdrkey'] = $obj['RECORDNO'];
        $vars['docparamsArr'] = $docparjs;
        $vars['done'] = insertDoneUnEnc(Request::$r->_done);
        $vars['priceFetchDisabled'] = $this->priceFetchDisabled ? 1 : 0;

        $vars['tocheck'] = $this->getEntity();
        $vars['creditlimitcheck'] = GetCreditLimitCheck();
        $vars['onholdcheck'] = GetOnHoldCheck();
        $vars['crlimit'] = '';
        $vars['entitydue'] = '';

        if ($IsComingFromSFDC) {
            $vars['crlimit'] = $this->sfcrlimit;
            $vars['entitydue'] = $this->sftotdue;
        }
        $vars['in_out'] = $in_out;
        $vars['ismcpEnabled'] = $this->ismcpEnabled;
        $vars['displayBaseCurrency'] = $docpar['DISPLAY_BASECURRENCY'];
        $vars['baseCurrency'] = $baseCurrency;
        $vars['shouldProrate'] = $shouldProrate;
        $vars['updatesInventory'] = $updatesInventory;
        $vars['isReturn'] = ($isReturn) ?: '';
        $vars['isBackOrder'] = ($isBackOrder) ?: '';

        $vars['enableoverridetax'] = $enableoverridetax;
        $vars['discONExtendedPrice'] = $discONExtendedPrice;

        if ( $copy != 'Update' || $sourceDocsjs ) {
            $vars['sourceDocsArr'] = $sourceDocsjs;
        }
        $vars['wareselmethod'] = $docpar['WAREHOUSESELMETHOD'];
        $vars['atlas'] = $this->atlas;

        $vars['upref_docpar_whse'] = $upref_docpar_whse;

        $vars['_dt'] = $this->dt;
        $vars['max_dummyid'] = MAX_DUMMY_ID;

        // Used for AutoPopulateCustVendID() function.
        $vars['bt'] = $docpar['ALLOWEDITBILLTO'];
        $vars['st'] = $docpar['ALLOWEDITSHIPTO'];

        // For PODocumentOnLoad/SODocumentOnLoad
        /** @noinspection PhpUndefinedVariableInspection */
        $vars['multivisibility'] = ($multivisibility) ? true : false;
        $vars['objop'] = $objop;

        $vars['custvendTitle'] = $title;
        $vars['qop'] = GetOperationId('co/lists/exchangerate/view');

        if ( $this->dt == BUILD_KIT || $this->dt == DIS_KIT ) {
            $docviewop = GetOperationId($this->mod . "/lists/stkitdocument/view");
        } else {
            $docviewop = GetOperationId($this->mod . "/lists/" . $this->mod . "document/view");
        }

        $vars['docviewop'] = $docviewop;

        $vars['recurOp'] = GetOperationId($this->mod . '/lists/' . $this->mod . 'recurdocument/edit');

        // SRAO :: TBD
        //	function WarnOnSaveDocument() {	<? echo $gWarnOnSaveNoCheckJS;  }
        // Used for AutoPopulateCustVendID() function ends.
        //For AvailableClick
        $vars['invstatusop'] = GetOperationId('inv/reports/invstatus');

        //For PickListReport
        $vars['phyinventoryop'] = GetOperationId('inv/reports/physicalinventory');

        //For HdrPickListReport
        $vars['pickinglistop'] = GetOperationId('so/reports/pickinglist');

        //For CostReportClick
        $vars['itemcogsop'] = GetOperationId('inv/reports/itemcogs');

        //for view source click
        $vars['view_eexpenses'] = GetOperationId('ee/lists/eexpenses/view');
        $vars['view_cctransactionentries'] = GetOperationId('cm/lists/cctransaction/view');
        $vars['view_apbill'] = GetOperationId('ap/lists/apbill/view');
        $vars['view_arinvoice'] = GetOperationId('ar/lists/arinvoice/view');
        $vars['view_timesheet'] = GetOperationId('pa/lists/timesheet/view');
        $vars['view_journal'] = GetOperationId('gl/lists/glbatch/view');
        $vars['view_sodocument'] = GetOperationId('so/lists/sodocument/view');
        $vars['view_podocument'] = GetOperationId('po/lists/podocument/view');

        //For SLBInfoClick
        $vars['docentrytrackop'] = GetOperationId($this->mod . '/lists/documententrytrack/create');
        $vars['docentrytrackkitop'] = GetOperationId('so/lists/documententrytrackkit/create');

        //For RespProcesser_ItemID
        $vars['renewalsEnabled'] = ($renewalsEnabled) ? true : false;
        $vars['itemsHaveStartEndDate'] = ($this->itemsHaveStartEndDate) ? true : false;
        $vars['fetchRenewalTermurl'] = "editor.phtml?.op=$_op&.sess=$_sess&_state=init&.action=fetchtermenddate";

        //For RespProcesser_ProratePrice
        $vars['fetchproratepriceURL'] = "editor.phtml?.op=$_op&.sess=$_sess&_state=init&.action=fetchprorateprice";

        $vars['enablerevrec'] = $enablerevrec;
        $vars['fetchdefaultrevrectemplateURL'] = "editor.phtml?.op=$_op&.sess=$_sess&_state=init&.action=fetchdefaultrevrectemplate";

        // This is needed to implement some recur document validations in the documenteditor.js
        $vars['fromRecurDocument'] = false;

        $vars['defaultuomgrp'] = $defaultUOMGrp;
        $vars['qtydensearr'] = '';

        $vars['_kNoWarn'] = Request::$r->_kNoWarn;
        $vars['_kNoDupl'] = Request::$r->_kNoDupl;
        $vars['newWhseAdded'] = '';
        $vars['index'] = '';
        $vars['draftmode'] = '';
        $vars['useVSOE'] = false;

        $vars['exchrateop'] = GetOperationId('co/lists/exchangerate/view');

        $vars['configOp'] = GetOperationId($this->mod . "/activities/" . $this->mod . "documentparams/view");

        $vars['recurop'] = GetOperationId($this->mod . "/lists/" . $this->mod . "recurdocument/view");
        $vars['docop'] = GetOperationId($this->mod . "/lists/" . $this->mod . "document");

        $vars['sodocviewop'] = GetOperationId('so/lists/sodocument/view');
        $vars['podocviewop'] = GetOperationId('po/lists/podocument/view');
        $vars['invdocviewop'] = GetOperationId('inv/lists/invdocument/view');

        $vars['landedCostMacro'] = 'false';
        if ($this->macroNames) {
            if (in_array(SCMMacroManager::LANDEDCOST, $this->macroNames)
                || in_array(SCMMacroManager::LCACTANDESTREV, $this->macroNames)
                || in_array(SCMMacroManager::LCACTANDEST, $this->macroNames)
                || in_array(SCMMacroManager::LCEST, $this->macroNames)
            ) {
                $vars['landedCostMacro'] = 'true';
            }
        }

        $jsobjectcache = $this->collectAutoFillData($docpar);

        $vars = array_merge($vars, $jsobjectcache);

        // ITEMID is not returned as a dimension from IADimension::getModuleDimensions call
        if ( !util_isPlatformDisabled() ) {
            if ( in_array('ITEMID', ($vars['platformPTRNotSupportedDimensionFieldNames']) ?? []) ) {
                $vars['platformPTRNotSupportedDimensionFieldNames'] = array_values(
                    array_diff($vars['platformPTRNotSupportedDimensionFieldNames'], array('ITEMID'))
                );
            }
        }
        $vars['_parentdt'] = Request::$r->_parentdt;
        $vars['isRetainageEnabled'] = $this->isRetainageBeingUsed;

        /** @var DocumentManager $docMngr */
        $docMngr = Globals::$g->gManagerFactory->getManager($this->mod . 'document');
        $isShiptoEnabled = $docMngr->isShipToLineItemEnable();
        //Show line level subtotals on line level advanced tax is enabled
        $vars['isLineShiptoEnabled'] = ($isShiptoEnabled && isset($docpar) && ($docpar['SHOW_TOTALS'] == 'true'));

        $enableChange = $docpar['ENABLEDOCCHANGE'] ?: 'No Change';
        $vars['isChangeDoc'] = Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled() && $enableChange == 'Change Order';
        $vars['entityDetail'] = $this->getEntity();

        //Set $hasAvatax variable to determine whether the document has Avalara enabled subtotal
        $hasAvatax = false;
        foreach ($obj['_DOCPAR']['DOCPAR_SUBTOTAL'] as $subtotal) {
            if ($subtotal['ISAVATAX'] == 'true') {
                $hasAvatax = true;
                break;
            }
        }
        $vars['HASAVATAX'] = $hasAvatax;

        //Set line level subtotal distribution flag from Avalara subscription to display line level subtotal sentry
        $vars['AVASHOWSUBTOTALENTRY'] = GetPreferenceForProperty(Globals::$g->kAVAid, 'AVA_ENABLE_VAT') == 'T';

        //Set line level simple tax is enabled/disabled for the document
        $vars['ISLINELEVELSIMPLETAX'] = $docpar['LINELEVELSIMPLETAX'] == 'true';

        $this->copyToAdapter->getEditorGlobals($vars);

        //Set TD subtotal applied to map for VAT, to use in override tax detail tax calculation
        if (TaxSetupManager::isVATEnabled()) {
            $subtotals = [];
            $isTaxAppliedTo = false;
            foreach ($obj['_DOCPAR']['DOCPAR_SUBTOTAL'] as $subtotal) {
                $subtotals[$subtotal['DESCRIPTION']] = $subtotal['BASELINE'];
                if ($subtotal['ISTAX'] == 'true' && $subtotal['BASELINE'] > 0) {
                    $isTaxAppliedTo = true;
                    $vars['TAX_APPLIEDNO'] = $subtotal['BASELINE'];
                }
            }
            $vars['SUBTOTALS_APPLIEDTOMAP'] = $subtotals;
            $vars['ISTAXAPPLIED_AFTER_DISCOUNT'] = $isTaxAppliedTo;
        }

        $vars['ENABLE_OE_PO_PAYMENT_TAX_CAPTURE_FEATURE_FLAG'] = false;
        if ( $docMngr->isPaymentTaxCaptureSupported() ) {
            $vars['ENABLE_OE_PO_PAYMENT_TAX_CAPTURE_FEATURE_FLAG'] = in_array($docpar['UPDATES_GL'], [ 'A', 'N' ])
                                                                     && FeatureConfigManagerFactory::getInstance()
                                                                                                   ->isFeatureEnabled('ENABLE_PAYMENT_TAX_CAPTURE')
                                                                     && FeatureConfigManagerFactory::getInstance()
                                                                                                   ->isFeatureEnabled('ENABLE_PARTIAL_PAYMENT_TAX')
                                                                     && FeatureConfigManagerFactory::getInstance()
                                                                                                   ->isFeatureEnabled('ENABLE_OE_PO_PAYMENT_TAX_CAPTURE');
        }

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

        // setting to false by default for Po and Inv
        $vars['isPCBEnabled'] = false;

        // setting to false by default for Po and Inv
        $vars['isRetainageBillingEnabled'] = false;

        // This required to handel the change source option hide/show
        $vars['isonChangeSrcDocOptionIsAvailable'] = $this->onChangeSrcDocOptionIsAvailable($obj);
        // to check pomatch is enabled or not
        // PO automation related variables
        $vars['isPOMatchEnabled'] = POSetupManager::isPOMatchEnabled();
        $vars['poMatchDocSource'] = PODocumentManager::POMATCH_SYNC_DOC_SOURCE;

        // This required to handle the conversion type from javascript to auto populate from the item object
        $vars['isPriceConversionEnabled'] = ($this->isPriceConversionEnabled());

        $vars['isReverseConversionAllowed'] = $this->isReverseConversionAllowed;
        return $vars;
    }

    /**
     * @param string $spi
     * @param array $ddlist
     *
     * @return array
     * @throws Exception
     */
    protected function getRecallDocList($spi, $ddlist)
    {
        global $_userid, $gManagerFactory;

        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');

        $t = explode('@', $_userid);
        $userkey = array_shift($t);
        $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($spi, 'T', $this->dt));
        $allowedDocs = upermFilterResult($allowedDocs, $userkey);
        $allowedDocs = filterDocsForUserType($allowedDocs);
        foreach ($allowedDocs as $doc) {
            $val = str_replace("'", "\'", $doc['DOCID']);
            if (!isset($ddlist) || !is_array($ddlist) || !in_array($val, $ddlist)) {
                $ddlist[] = $val;
            }
        }

        return $ddlist;
    }

    /**
     * @param string[] $completeList
     *
     * @return string[]
     */
    protected function getCompleteDocList($completeList)
    {
        $docs = GetDocumentMenuList($this->mod);

        foreach ( $docs as $doc ) {
            // do not include build kits and disassemble kits TD in the list --mmahur
            if ( !in_array(
                $doc['DOCID'], array(BUILD_KIT,DIS_KIT,ICTransferManager::INDOCTYPE,ICTransferManager::OUTDOCTYPE)
            )
            ) {
                $completeList[] = str_replace("'", "\'", $doc['DOCID']);
            }
        }
        return $completeList;
    }

    /**
     *
     * @return array
     */
    protected function getChangeDocList()
    {
        $completeList = [];
        $docs = GetDocumentMenuList($this->mod);
        foreach ( $docs as $doc ) {

            if ( $doc['ENABLEDOCCHANGE'] == 'Change Order') {
                $completeList[] = str_replace("'", "\'", $doc['DOCID']);
            }
        }
        return $completeList;
    }

    /**
     * @param string[] $_params
     *
     * @throws Exception
     */
    protected function fetchDefaultRevRecTemplate(/** @noinspection PhpUnusedParameterInspection */ &$_params)
    {
        $itemlabel = Request::$r->itemlabel;

        global $gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');
        $itemglgrpMgr = $gManagerFactory->getManager('itemglgroup');

        [$ID] = explode('--', $itemlabel);
        $selects = array('ITEMTYPE','REVPOSTING','GLGROUP' );
        $querySpec = array(
            'selects' => $selects,
            'filters' => array(
                array(
                    array('ITEMID', '=', $ID),
                )
            ),
        );
        $itemObj = $itemMgr->GetList($querySpec)[0];

        if (empty($itemObj)) {

            // In the unlikely event that the Get failed, let's try a more lenient search (see ticket 19886) which also matches the logic in ItemManager::FetchItem.
            // We then use the actual ITEMID to do the Get.  I know it is not very efficient, but ItemFetch doesn't return the necesesary fields, and again this is not a common scenario.
            $itemFetched = $itemMgr->ItemFetch($ID);
            if (isset($itemFetched[0]['ITEMID'])) {
                $querySpec = array(
                    'selects' => $selects,
                    'filters' => array(
                        array(
                            array('ITEMID', '=', $itemFetched[0]['ITEMID']),
                        )
                    ),
                );
                $itemObj = $itemMgr->GetList($querySpec)[0];
            }
        }
        $itemGLGroup  = $itemObj['GLGROUP'];
        if ( $itemObj['ITEMTYPE'] == 'Kit' && $itemObj['REVPOSTING'] == 'Component Level' ) {
            echo('Use Kit Revenue Rules');
        } elseif(isset($itemGLGroup) && $itemGLGroup != '') {
            $querySpec = array(
                'selects' => array('REVRECTEMPLID'),
                'filters' => array(
                    array(
                        array('NAME', '=', $itemGLGroup),
                    )
                ),
            );
            $itemglgrpObj = $itemglgrpMgr->GetList($querySpec)[0];
            echo($itemglgrpObj['REVRECTEMPLID']);
        }

        exit;
    }


    /**
     * @param string[] $_params
     * @param array      $_obj
     *
     * @throws Exception
     */
    protected function editorGetSuggestPrice(/** @noinspection PhpUnusedParameterInspection */ &$_params, &$_obj)
    {

        global $gManagerFactory;

        $lineno = $_obj['PRCLINENUM'];

        if ( isset($lineno) && $_obj['ENTRIES'][$lineno]['ITEMID'] ) {

            /**
             * @var DocumentParamsManager $docparMgr
             */
            $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');

            [$ID] = explode('--', $_obj['CUSTVENDID']);
            $_obj['CUSTVENDID'] = $ID;

            $docpar = $docparMgr->GetLatestRaw($_obj['DOCPARID']);
            $docpar = $docpar[0];
            //$docpar = $this->GetBaseDocPar();

            $_document['PRCLISTKEY'] = $docpar['PRCLISTKEY'];
            $_document['SPCLPRCLISTKEY'] = $docpar['SPCLPRCLISTKEY'];
            $_qty = $_obj['ENTRIES'][$lineno]['UIQTY'] * $_obj['ENTRIES'][$lineno]['UNITFACTOR'];

            $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
            $priceParams = $pricingHandler->PrepParams($_obj['CUSTVENDID'], '', '', $_obj['WHENCREATED'], $this->mod);
            $price = $pricingHandler->SuggestPrice($priceParams, $_obj['ENTRIES'][$lineno]['ITEMID'], $_obj['ENTRIES'][$lineno]['PRODLINE'], $_qty, $_document);
            $_obj['ENTRIES'][$lineno]['UIPRICE'] = $price * $_obj['ENTRIES'][$lineno]['UNITFACTOR'];
        }
        unset($_obj['PRCLINENUM']);
    }


    //function getSubtotals(&$_params, &$obj, $newDoc = true) {

    /**
     * @param array   $obj
     * @param bool    $newDoc
     *
     * @throws Exception
     */
    protected function getSubTotals(&$obj, $newDoc = true)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $documentMgr = $this->getEntityMgr();

        /**
         * @var DocumentParamsManager $docparMgr
         */
        $docparMgr =  $gManagerFactory->getManager($this->mod . 'documentparams');

        /**
         * @var DocumentParSubTotalManager $docparsubtotalsMgr
         */
        $docparsubtotalsMgr =  $gManagerFactory->getManager($this->mod . 'documentparsubtotal');

        //$docpar = $this->GetBaseDocPar(true);
        $docpar = $docparMgr->GetBaseLatest($obj['DOCPARID']);

        //eppp_p($docpar);
        $docpar['DOCPAR_SUBTOTAL'] = $docparsubtotalsMgr->getByParent($docpar['RECORDNO']);
        //eppp_p($docpar);

        $subTotalObj = GetSubTotalsHelper($this->mod);
        if ($subTotalObj->_distributeSubtotalsAtEntity) {
            foreach ($docpar['DOCPAR_SUBTOTAL'] as &$subtotal) {
                $subtotal['LOCATION'] = '';
                $subtotal['DEPARTMENT'] = '';

                $subtotal['LOCATIONID'] = '';
                $subtotal['DEPARTMENTID'] = '';
            }
            unset($subtotal);
        }

        $obj['_DOCPAR'] = $docpar;

        // Append dimension field information to the docvalues structure that will be used by the subtotals logic.
        $obj['PRIMARYDIMENSION'] = $documentMgr->getPrimaryDimensions();

        if( $docpar['SHOW_TOTALS'] == 'true' || $documentMgr->isVATEnabled($obj)) {
            if ( $newDoc ) {
                if ($obj['WHENCREATED']) {
                    // In the new editor, the dates are always sent back as System Format, but unfortunately the subtotal code needs it in user format.
                    $obj['WHENCREATED'] = FormatDateForDisplay($obj['WHENCREATED']);
                    $obj['ORIGDOCDATE'] = FormatDateForDisplay($obj['ORIGDOCDATE']);
                }
                $obj['ISEDITORGOBACK'] = true;
                $documentMgr->calcSubTotals($obj);
                if ($obj['WHENCREATED']) {
                    $obj['WHENCREATED'] = FormatDateForStorage($obj['WHENCREATED']);
                    $obj['ORIGDOCDATE'] = FormatDateForStorage($obj['ORIGDOCDATE']);
                }
            }
        }else{
            unset($obj['SUBTOTALS']);
        }

        if ( $obj['_DOCPAR']['SHOWEXPANDEDTOTALS'] != 'true' ) {
            $newsubtotals = array();
            $subtotals = $obj['SUBTOTALS'];
            if ( isset($subtotals) && is_array($subtotals) ) {
                foreach ( $subtotals as $subtotal ) {
                    if ( !$subtotal['TAXDETAIL'] ) {
                        $newsubtotals[] = $subtotal;
                    }
                }
            }
            $obj['SUBTOTALS'] = $newsubtotals;
        }

        $documentMgr->processSubtotalsForDimensions($obj);
    }


    /**
     * @param array $docpar
     *
     * @return array
     * @throws Exception
     */
    protected function collectAutoFillData($docpar)
    {
        StartTimer("AUTOFILL");

        global $gManagerFactory;
        $itemMgr =  $gManagerFactory->getManager('item');

        StartTimer("ITEMS");

        $items = array();
        $itemidArray = array();
        $obj = & Request::$r->GetCurrentObject();

        if ( $obj['ENTRIES'] ) {

            $buildingKit = ($this->dt == BUILD_KIT || $this->dt == DIS_KIT)
                           && StkitDocumentManager::isStockableKitComponentTrackingEnabled();
            $warehouseidArray = array();
            $itemWhsePair = array();
            $jsonVals = array('__dummy' => null);
            foreach ($obj['ENTRIES'] as $entry ) {
                $itemid = explode('--', $entry['ITEMID'] ?? '')[0]; // PHP 8.1 won't allow null
                if (!empty($itemid ?? '')) {
                    $itemUOM = array();
                    foreach ($entry['ITEMUOM'] ?? [] as $key => $val) {
                        $isdefault = ($val['ISBASE'] == 'T') ? true : false;
                        $itemUOM[$key]['unit'] = $val['UNIT'];
                        $itemUOM[$key]['rec'] = $val['RECORD#'];
                        $itemUOM[$key]['factor'] = $val['CONVFACTOR'];
                        $itemUOM[$key]['sel'] = $isdefault;
                        $itemUOM[$key]['numdec'] = $val['NUMDEC'];
                    }
                    $itemidArray[] = $itemid;
                    $jsonVals[$itemid]['uomdetails'] = $itemUOM;
                    $whse = explode('--', $entry['WAREHOUSE']['LOCATION_NO'])[0];
                    $warehouseidArray[] = $whse;
                    $itemWhsePair[] = $itemid."--".$whse;

                    //Get tracking info if in build txn and SK item
                    //TODO: We should have this in a protected method for skbuild txn when we remove the feature flag.
                    if ( $entry['ITEMTYPE'] == 'SK' && $buildingKit ) {
                        //If txn not draft state, we need to get the current tracking entries to pass into fetchSnLotExpirationInternal
                        //below to account for them
                        $existingTrackedEntries = null;
                        if ($obj['STATE'] != 'Draft') {
                            $existingTrackedEntries = $entry['TRACKINGENTRIES'];
                            foreach ($existingTrackedEntries as &$trackedEntry) {
                                if (!isset($trackedEntry['WHSEKEY'])) {
                                    $trackedEntry['WHSEKEY'] = $whse;
                                }
                            }
                        }

                        //Fetch the tracking data so we can store in the itemdensearr when loading up this txn
                        $trackings = $itemMgr->fetchSnLotExpirationInternal($itemid, $whse, '', $entry, false, $existingTrackedEntries);
                        foreach ($trackings['track'] as $tracking) {
                            $itemid = $tracking['itemid'];
                            $wh = $tracking['warehouse'];
                            if (!$this->hasMatching($jsonVals[$itemid]['tracking'][$wh], $tracking)) {
                                $jsonVals[$itemid]['tracking'][$wh][] = $tracking;
                            }
                        }
                    }
                }
            }
            if (!empty($itemidArray)) {
                $qtyDenseArray = [];
                if ($obj['_DOCPAR']['IN_OUT'] == 'Decrease') {
                    $qtyDenseArray = $itemMgr->fetchQuantityTotals($itemidArray , $warehouseidArray);
                }
                foreach($itemWhsePair as $keys) {
                    $denseArray = [];
                    $itemWhseArr = explode('--',$keys);
                    if(empty($qtyDenseArray[$keys])) {
                        $denseArray['itemkey'] = $itemWhseArr[0];
                        $denseArray['qtyleft'] = "0";
                        $denseArray['qtyonhand'] = "0";
                        $denseArray['qtyonhold'] = "0";
                        $denseArray['qtyonorder'] = "0";
                        $denseArray['warehousekey'] = $itemWhseArr[1];
                        $qtyDenseArray[$keys] = $denseArray;
                    }
                }

                $precisionFields = [ 'so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD' ];
                $precFld = $precisionFields[$this->mod];

                $itemstatus = '';
                if ( $this->state == 'shownew' ) {
                    $itemstatus = " and icitem.status = 'T'";
                }

                $stmt = [];
                $stmt[0] = "select icitem.itemid itemid, icitem.name name,icitem.taxable tax,icitem.productlinekey prodline,
                                stduom.unit as stdunit, stduom.convfactor as convfactor, purchaseuom.unit as punit, 
                                purchaseuom.convfactor punit_factor, salesuom.unit as sunit, 
                                salesuom.convfactor sunit_factor, $precFld precision, uomgrp.name as uomgrpname, 
                                icitem.itemtype itemtype,icitem.hasstartenddates, icitem.termperiod,
                                icitem.totalperiods,icitem.computeforshortterm, icitem.cost_method, icitem.enablesno, 
                                icitem.enablebin, icitem.enablelot, icitem.enableexpiration, icitem.enablefulfillment
                from icitem, icuomgrp uomgrp, icuom stduom, icuom purchaseuom, icuom salesuom 
                where  icitem.cny# = :1 and uomgrp.cny#(+)=icitem.cny# and uomgrp.record# (+) = icitem.uomgrpkey
                                and stduom.cny#(+)=uomgrp.cny# and purchaseuom.cny#(+)=uomgrp.cny# 
                                and salesuom.cny#(+)=uomgrp.cny# and uomgrp.record# = stduom.grpkey (+) 
                                and stduom.record# (+) = uomgrp.invdefunitkey and uomgrp.record# = purchaseuom.grpkey (+) 
                                and purchaseuom.record# (+) = uomgrp.podefunitkey and uomgrp.record# = salesuom.grpkey (+) 
                                and salesuom.record# (+) = uomgrp.sodefunitkey " . $itemstatus;

                $stmt[1] = GetMyCompany();
                $stmt = PrepINClauseStmt($stmt, $itemidArray, " and icitem.itemid ");

                $res = QueryResult($stmt);

                //Iterating for getting item record details for the repeated items in the line entries
                foreach ( $res as $value  ) {
                    foreach ( $value as $key => $itemValue ) {
                        $jsonVals[$value['ITEMID']][strtolower($key)] = $itemValue;
                    }

                    $jsonVals[$value['ITEMID']]['isserialized'] =
                        $itemMgr->IsItemSerialized($value['ITEMID'], true, $value);

                    //
                    //Get kit components
                    if ( $value['ITEMTYPE'] == 'K' || ( $value['ITEMTYPE'] == 'SK' && $buildingKit ) ) {
                        $kitcomponents = $this->GetKitComponents($value['ITEMID']);
                        $jsonVals[$value['ITEMID']]['components'] = $kitcomponents;
                    }

                    //
                    //Get warehouse info
                    $warehouseQty = [];
                    foreach ($qtyDenseArray as $key=> $val) {
                        $itemkey = explode('--', $key)[0];
                        if($itemkey == $value['ITEMID']) {
                            $warehouseQty[$key] = $val;
                        }
                    }
                    $jsonVals[$value['ITEMID']]['wh'] = $warehouseQty;
                }
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $items['itemdensearr'] = $jsonVals;


        // There are a very few things we need from the item warehouse records; get them now.....
        // for now, all I need is the default bin
        /* **************************** Temporary Escalation fix
        $stmt    = [];
        $stmt[0] = "select iw.itemkey as itemid, iw.warehousekey as warehouseid, bin.binid as default_bin
                from  icitemwhse iw, icbin bin
                where iw.cny# = :1 and bin.cny# = iw.cny# and iw.binkey IS NOT NULL and bin.record# = iw.binkey";
        $stmt[1] = GetMyCompany();
        $stmt    = PrepINClauseStmt($stmt, $itemidArray, " and iw.itemkey ");
        $iw      = QueryResult($stmt);
        if ($iw !== false) {
            $iwVals = [];
            //Iterating to get item record details for the repeated items in the line entries
            foreach ($iw as $value) {
                foreach ($value as $key => $itemValue) {
                    $iwVals[$value['ITEMID']][$value['WAREHOUSEID']][strtolower($key)] = $itemValue;
                }
            }
            $items['itemwhdensearr'] = $iwVals;
        }
        ************************************* */


        $warehouses = $this->GetWarehouses($docpar['WAREHOUSESELMETHOD']);

        $whseVals = array();
        //Iterating for getting item record details for the repeated items in the line entries
        foreach ( $warehouses as $value ) {
            $whseVals[] = $value['WHSE'];
        }

        $items['whsedensearr'] = $whseVals;


        return($items);
    }

/**
 * This method finds a matching passed $inEntry in the passed in $inEntries, by comparing all the fields in the $inEntry.
 *
 * @param array $inEntries the entries possibly containing the passed in $inEntry
 * @param array $inEntry the entry to look for in the passed in $inEntries
 *
 * @return bool true if a matching $entry is found in $entries
 */
private function hasMatching($inEntries, $inEntry)
{
    foreach ($inEntries as $entry) {
        $foundMatching = false;
        foreach ($inEntry as $key => $fld) {
            if ($fld === $entry[$key]) {
                $foundMatching = true;
            } else {
                $foundMatching = false; //Found a field not matching in the iterating $entry, so don't need to compare other fields
                break;
            }
        }
        if ($foundMatching) {
            return true; //Found a matching entry in $InEntries, no need to look anymore
        }
    }
    return false;
}

    /**
     * @param string $kitID
     *
     * @return string[]
     * @throws Exception
     */
    protected function GetKitComponents($kitID=''){
        if($kitID==''){
            return array();
        }
        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr =  $gManagerFactory->getManager('item');

        $kqry  = 'QRY_ICITEM_SELECT_KITCOMPONENTS';
        $kargs = array (GetMyCompany(), $kitID);
        $kres  = $itemMgr->DoQuery($kqry, $kargs);
        $kitcomponents = array();
        foreach ( $kres as $kitcomp) {
            $isKitItemSerialized = ($kitcomp['ENABLESNO']=='T' || $kitcomp['ENABLELOT']=='T' || $kitcomp['ENABLEBIN']=='T' || $kitcomp['ENABLEEXPIRATION']=='T');
            $kitcomponents[] = array(
                'item' => htmlspecialchars($kitcomp['COMPONENTKEY'], ENT_COMPAT),
                'no_of_units'=>$kitcomp['NO_OF_UNITS'],
                'unit'=>$kitcomp['UNIT'],
                'enablesno'=>$kitcomp['ENABLESNO'],
                'enablelot'=>$kitcomp['ENABLELOT'],
                'enablebin'=>$kitcomp['ENABLEBIN'],
                'enableexpiration'=>$kitcomp['ENABLEEXPIRATION'],
                'isserialized'=>$isKitItemSerialized,
            );
        }

        return $kitcomponents;
    }

    /**
     * Editor_Deliver
     *
     * @param string[]      $_params
     * @param bool          $offline
     * @param string|false  $out       output when Request::$r->_deliverymethod is xmldataraw, pdf (the defautl)
     *                                 or pdfpreview
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        if (empty($this->textMap)) {
            // In case we get called without normal UI setup, resolve labels now.
            $this->loadTokenLabels();
        }

        $xsltemplateid = $_params['xsltemplateid'];

        $method = Request::$r->_deliverymethod;
        if ( !$method ) {
            $method = 'pdf';
        }

        $mod = $this->mod;

        //  If tracking access, mark it as for print.
        AdvAuditTracking::setOperation(AuditTrail::OPID_PRINT);

        $viewData = $this->getViewData();
        if ( $mod == 'so') {
            // Only mark as printed when this document is not in draft state
            if ( $method == 'pdf' && $viewData['STATE'] == 'Draft') {
                // to not upset existing behaviour we added this pref check
                $donotMarkDraft = GetPreferenceForProperty(Globals::$g->kSOid, 'DONOT_MARK_DRAFT') == 'T';
                if ( $donotMarkDraft ) {
                    $method = 'pdfpreview';
                }
            }
        }

        $docid = $viewData['DOCID'] ?: $_params['DOCID'];
        $dt = $viewData['DOCPARID'] ?: $_params['DOCPARID'];

        if ( !$dt ) {
            $docMgr = Globals::$g->gManagerFactory->getManager('document');
            $docpar = $docMgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', [ $docid ]);
            $dt = $values['REC']['DOCPARID'] = $docpar[0]['DOCID'];
        }

        $messagetext = $viewData['MESSAGETEXT'];
        $marketingtext = $viewData['MARKETINGTEXT'];

        if ( !isset($_params['ENTITYID']) || $_params['ENTITYID'] == '' ) {
            [$entityid] = explode('--', $viewData['CUSTVENDID']);
            $_params['ENTITYID'] = $entityid;
            /** @noinspection PhpUndefinedVariableInspection */
            $_params['DOCCLASS'] =
                $viewData['_DOCPAR']['DOCCLASS'] ?: $docpar['DOCCLASS'];
        }

        $iscustomdoc = false;
        if ( $method == 'xmldata' || $method == 'xmldataraw' ) {
            $this->xsltemplateInfo = $this->GetTemplateType($docid, $dt, $xsltemplateid, $_params['ENTITYID'],
                                                            $_params['DOCCLASS']);
            $type = $this->xsltemplateInfo['type'];
            $this->xsltemplateInfo['agingOn'] = $_params['agingOn'];
            $iscustomdoc = ( $type == 'DOC' || $type == 'DOX' ) ? true : false;
        }

        switch ($method) {
            case 'xmldata':
                $printData = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, $iscustomdoc);
                $this->PrintAsXML($printData);
                break;
            case 'xmldataraw':
                $out = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, $iscustomdoc);
                return $out !== '';
            case 'phpdata':
                $this->PrintAsPHP($this->GetDataForPrinting($docid, $dt, $mod));
                break;
            case 'xmlform':
                $t = XMLUtils::PHP2XMLStr($_params);
                $this->PrintAsXML($t);
                break;
            case 'phpform':
                $this->PrintAsPHP($_params);
                break;
            case 'xsl':
                $xslfname1 = $this->getEntity() . '_layout_print.xsl';
                $file = @file($xslfname1, 1);
                if ( ! $file ) {
                    $xslfname2 = $this->getEntity() . '_layout_edit.xsl';
                    $file = @file($xslfname2, 1);
                }
                $xsl = join('', $file);
                $this->PrintAsXML($xsl);
                break;
            case 'fo':
                include_once 'backend_pdf.inc';
                $xsl = $this->GetXSLTemplate($docid, $dt, $xsltemplateid, $_params);
                $xml = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext);
                $ok = XSLTInProcess($xsl, $xml, $fo);
                if ( !$ok ) {
                    Globals::$g->gErr->addIAError('INV-0017', __FILE__ . ":" . __LINE__,
                                                "XSL Translation failed", []);
                    return false;
                }
                $this->PrintAsXML($fo);
                break;

            /*
              case 'html' :
             */

            case 'pdf':
            case 'pdfpreview':
                $out = $this->generatePDFDocument($_params, $docid, $dt, $mod, $messagetext, $marketingtext, $offline,
                                                  $method);

                return $out != '';
        }

        return true;
    }

    /**
     * this function accepts a document details and depending on the docid generates the PDF for it
     * it checks if the template attached to the document is a DOC/DOCX/XSL type and does the conversion to PDF
     * accordingly
     *
     * @param string[]    $_params        the parameters
     * @param string      $docid          the document ID for the document to be converted
     * @param string      $dt             the data for the document
     * @param string      $mod            the module for the document
     * @param string      $messagetext    the message text for the document
     * @param string      $marketingtext  the marketing text for the document
     * @param bool|string $offline        process the document offline or not
     * @param string      $method         pdf or pdfpreview
     *
     * @return false|string
     *
     * @throws Exception
     */
    public function generatePDFDocument(&$_params, $docid, $dt, $mod, $messagetext, $marketingtext, $offline=false, $method='pdf')
    {
        $xsltemplateid = $_params['xsltemplateid'];
        $entityid = $_params['ENTITYID'];
        $docclass = $_params['DOCCLASS'];

        $this->xsltemplateInfo = $this->GetTemplateType($docid, $dt, $xsltemplateid, $entityid, $docclass);

        if ( $this->xsltemplateInfo['type'] == 'DOC' || $this->xsltemplateInfo['type'] == 'DOX' ) {

            $xml = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, true);

            if ( HasErrors() ) {
                return false;
            }

            [$langCode, $countryCode] = explode('-', $this->xsltemplateInfo['LOCALE']);
            $langCode = ( $langCode != '' ? $langCode : 'en' );
            $countryCode = ( $countryCode != '' ? $countryCode : 'US' );

            $template = $this->xsltemplateInfo['template'];

            $params = [
                'LANGCODE'     => $langCode,
                'COUNTRYCODE'  => $countryCode,
                'WHENMODIFIED' => $this->xsltemplateInfo['WHENMODIFIED'],
                'ENCRYPTPDF' => $this->xsltemplateInfo['ENCRYPTPDF'],
            ];
            $out = genPDFFromWORD($xml, $template, !$offline, $params);

        } else {
            $fovar = $this->CreatePdfDocument($docid, $dt, $mod, $messagetext, $marketingtext, $_params);
            $out = genPDF($fovar, !$offline);
        }

        // we are using same function to do PDF and PDFPREVIEW
        // we want to mark the source document as printed only for $method='pdf'...
        if ( $method == 'pdf' ) {
            /** @var DocumentManager $docMgr*/
            $docMgr = Globals::$g->gManagerFactory->getManager('document');
            $docMgr->markDocumentAsPrinted($docid);
        }

        return $out;
    }


    /**
     * @param string $docid
     * @param string $dt
     * @param string $mod
     * @param string $messagetext
     * @param string $marketingtext
     * @param string[] $_params
     *
     * @return string|bool
     * @throws Exception
     */
    protected function CreatePdfDocument($docid, $dt, $mod, $messagetext, $marketingtext, &$_params)
    {
        include_once 'backend_pdf.inc';

        $xsltemplateid = $_params['xsltemplateid'];
        $xsl = $this->GetXSLTemplate($docid, $dt, $xsltemplateid, $_params);
        $xml = $this->GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext);

        if ( !XSLTInProcess($xsl, $xml, $fo) ) {
            $gErr = Globals::$g->gErr;
            $gErr->addIAError('INV-0018', __FILE__ . ":" . __LINE__, "XSL Translation failed", []);
            return false;
        }

        return $fo;
    }

    /**
     * @param string $docid
     * @param string $docparid
     * @param string $xsltemplateid
     * @param string $entityid
     * @param string $docclass
     *
     * @return string[]
     * @throws Exception
     */
    public function GetTemplateType($docid, $docparid, $xsltemplateid='', $entityid='', $docclass='')
    {
        $indexKey = $docparid . '#~#' . $xsltemplateid . '#~#' . $entityid . '#~#' . $docclass;

        if ( !isset($this->printTemplateCache[$indexKey]) ) {

            $gManagerFactory = Globals::$g->gManagerFactory;

            $xslformatMgr = $gManagerFactory->getManager('xslformat');

            //Check the Docpar for the default template to use
            if ( !isset($xsltemplateid) || $xsltemplateid == '' ) {

                // if docpar is not given query it
                if (!$docparid) {
                    if ( !is_object($this->entityMgr) ) {
                        $this->entityMgr = $this->GetManager($this->getEntity());
                    }
                    $res = $this->getEntityMgr()->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
                    $docparid = $res[0]['DOCID'];
                }

                // find the customer and docpar.xsltemplate
                /**
                 * @var DocumentParamsManager   $docparMgr
                 */
                $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
                $docpar = $docparMgr->GetBaseLatest($docparid);
                $xsltemplateid = $docpar['XSLTEMPLATE'];

            } else {
                $args = array(
                    'selects' => array('RECORDNO'),
                    'filters' => array (array (array('DESCRIPTION', '=', $xsltemplateid)))
                );
                $resultSet = $xslformatMgr->GetList($args);
                $xsltemplateid = $resultSet[0]['RECORDNO'];
            }

            if ($xsltemplateid) {
                $this->XSL_Template_Type = 'db'; // remember what type of transform process we are using

                $formatdata = $xslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($xsltemplateid));
                if (isset($formatdata[0]['XSL'])) {
                    $formatdata[0]['XSL'] = databaseStringUncompress($formatdata[0]['XSL']);
                }
                $formatdata = $formatdata[0];

                // transform db value into business value for easy processing of preferences
                DocformatEditor::buildBizView($formatdata);
                $formatdata['type'] = $formatdata['TEMPLATETYPE'];
                $formatdata['template'] = $formatdata['XSL'];
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $this->printTemplateCache[$indexKey] = ( $formatdata ?:  array( 'type' => null, 'template' => null) );
        }

        return $this->printTemplateCache[$indexKey];
    }

    /**
     * @param string                 $docid
     * @param string|string[]|false  $docparid
     * @param string                 $xsltemplateid
     * @param array                  $_params
     *
     * @return string
     * @throws Exception
     */
    function GetXSLTemplate($docid, $docparid, $xsltemplateid, $_params)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $XslformatMgr = $gManagerFactory->getManager('xslformat');

        if ( !isset($xsltemplateid) || $xsltemplateid == '' ) {
            if (!$docparid) {
                $docMgr = $gManagerFactory->getManager('document');
                $docparid = $docMgr->DoQuery('QRY_DOCUMENT_GET_DOCPARID', array($docid));
                $docparid = $docparid[0]['DOCID'];
            }
            //eppp_p($docparid);
            //dieFL();

            //Check the Docpar for the default template to use
            /**
             * @var DocumentParamsManager   $docparMgr
             */
            $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
            $docpar = $docparMgr->GetBaseLatest($docparid);
            //eppp_p($docpar);
            //dieFL();

            $xsltemplateid = $docpar['XSLTEMPLATE'];
        } else {
            $args = array(
                'selects' => array('RECORDNO'),
                'filters' => array (array (array('DESCRIPTION', '=', $xsltemplateid)))
            );
            $resultSet = $XslformatMgr->GetList($args);
            $xsltemplateid = $resultSet[0]['RECORDNO'];
        }

        if ( $xsltemplateid != '' ) {
            $this->XSL_Template_Type = 'db'; // remember what type of transform process we are using

            $formatdata = $XslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($xsltemplateid));

            $file = ($formatdata[0]['XSL']) ? $XslformatMgr->GetXSL(databaseStringUncompress($formatdata[0]['XSL'])) : '';
        }
        //dieFL($file);

        // Go for the old method
        /** @noinspection PhpUndefinedVariableInspection */
        if (!$file) {
            if ($this->mod=='inv') {
                /** @noinspection PhpUndefinedVariableInspection */
                $fileName = $docpar['SALE_PUR_TRANS'] . '_Inventory';
            }else{
                /** @noinspection PhpUndefinedVariableInspection */
                $fileName= $docpar['SALE_PUR_TRANS'] . '_' . $docpar['DOCCLASS'];
            }
            $file=@file(XSLDIR.$fileName.'_layout_print.xsl', 1);
            $this->XSL_Template_Type = 'file_print_layout';
            if (!$file) {
                $this->XSL_Template_Type = 'entity_print_layout';
                $file = @file(XSLDIR.$_params['entity'] . '_layout_print.xsl', 1);
                if (!$file) {
                    $this->XSL_Template_Type = 'entity_edit_layout';
                    $file = @file(XSLDIR.$_params['entity'] . '_layout_edit.xsl', 1);
                }
            }
            // added is_array check to avoid exception for php 8.1
            $file = is_array($file) ? join('', $file) : $file;
        }

        return ($file);
    }


    /**
     * @param int|string|null    $docid
     * @param string        $dt
     * @param string        $mod
     * @param bool          $iscustomdoc
     *
     * @return array
     * @throws Exception
     */
    protected function GetDataForPrinting($docid = 0, $dt = '', $mod = '', $iscustomdoc = false)
    {
        $locale = '';
        $localeDateFormat = '';
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        /**
         * @var DocumentManager $entityMgr
         */
        $entityMgr = $gManagerFactory->getManager($this->getEntity(), true, array( 'DOCTYPE' => $dt));

        if ( !$docid ) {
            $vid = $entityMgr->GetKeyFieldName();
            $docid = Request::$r->{Request::$r->PathToFieldName($vid)};
        }

        if ( $iscustomdoc && $this->xsltemplateInfo['PARAMS'] != '' ) {
            // for custom document association we get document data through different API
            $document = $entityMgr->getPrintableInfo($docid, $this->xsltemplateInfo);
            $locale = $this->xsltemplateInfo['LOCALE'];
            if ((new BackendPdf())->isIAControllerUpgradeEnabled()) {
                $localeDateFormat = (new DatesUtil())->getDateFormatFromLocale($locale);
            }

            // fetch custom relationship attributes...
            $this->fetchRelationshipValues($entityMgr, $document);

        } else {
            // lets just use manager->Get($dodid) method to get document data...
            $document = $entityMgr->Get($docid);

            ContractUtil::reIndexInSubArrayForXMl($document, 'CNCONTRACTINFOS');

            // lets process the document and gather project related information, only for sodocument
            $entityMgr->getProjectInvoiceInfo($document);
        }

        if ( !$document ) {
            $gErr->addIAError(
                'INV-0364', __FILE__ . ":" . __LINE__,
                "ERROR: couldnt fetch the given docid ($docid) information...", ['DOCID' => $docid]
            );
            return array();
        }

        $this->ExpandKitForPrinting($document);

        if ( $iscustomdoc ) {
            // the logic of showing or hiding subtotal details is controlled in below API
            // following line is commented for bug#: 39344
            //$this->getSubtotals($document, false);
            if ( !isset($document['_DOCPAR']['SHOWEXPANDEDTOTALS']) || $document['_DOCPAR']['SHOWEXPANDEDTOTALS'] == 'false' ) {
                $newsubtotals = array();
                $subtotals = $document['SUBTOTALS'];
                foreach ( $subtotals as $subtotal ) {
                    if ( !$subtotal['TAXDETAIL'] ) {
                        $newsubtotals[] = $subtotal;
                    }
                }
                $document['SUBTOTALS'] = $newsubtotals;
            }

            if ( TaxSetupManager::isVATEnabled() ){
                foreach((($document['ENTRIES']) ?? []) as $entry) {
                    if (!is_array($entry)){
                        continue;
                    }
                    $document['TRX_TOTAL_TAX'] +=  $entry['TRX_TAXABSVAL'];
                    $document['TOTAL_TAX'] +=  $entry['TAXABSVAL'];
                }
                // format the total tax for display
                $document['TRX_TOTAL_TAX'] = formatNumberForLocale($document['TRX_TOTAL_TAX'], $locale);

                //If Custom VAT, UK or CA tax then bucket the tax rate for printing
                $taxSolnID = $document['TAXSOLUTIONID'];
                $isTaxSolutionForEU = TaxSolutionManager::isTaxSolutionForEU($taxSolnID);
                if (($isTaxSolutionForEU || $taxSolnID == TaxSolutionManager::TAXSOLUTION_CA)
                    && TaxSolutionManager::isTaxSolutionIdConfigured($taxSolnID)) {
                    // add REVERSECHARGEFLAG to $document for xml output
                    if ($isTaxSolutionForEU && $this->isReverseChargeOn($document['SUBTOTALS'])) {
                        $document['REVERSECHARGEFLAG'] = "true";
                    }

                    // add TAXRATE info to $document for xml output
                    $docValues = $document;
                    $entityMgr->getEntrySubTotals($docValues);
                    $taxRates = $this->getTaxRates($docValues);
                    if (!empty($taxRates)) {
                        $document['TAXRATES'] = $taxRates;
                    }
                }
            }

            // remove field which type is "PASSWORD" in $document.
            foreach ( $entityMgr->customFields as $cField ) {
                $key = $cField->customFieldID;
                $type = $cField->type;
                if ( !is_null($key) && $type == "PASSWORD" ) {
                    unset($document[$key]);
                }
                // reformat the field which type is "DATE" for display
                if ( !is_null($key) && $type == "DATE" ) {
                    $document[$key] = FormatDateForDisplay($document[$key], $localeDateFormat);
                }
            }

            $documententryMgr = $this->getEntryManager();
            foreach ($document['ENTRIES'] as $i => $entry ) {
                foreach ( $documententryMgr->customFields as $cField ) {
                    $key = $cField->customFieldID;
                    $type = $cField->type;
                    // remove field which type is "PASSWORD" in $document['ENTRIES'].
                    if ( !is_null($key) && $type == "PASSWORD" ) {
                        unset($document['ENTRIES'][$i][$key]);
                    }
                    // reformat the field which type is "DATE" for display
                    if ( !is_null($key) && $type == "DATE" ) {
                        $document['ENTRIES'][$i][$key] = FormatDateForDisplay(
                            $document['ENTRIES'][$i][$key],
                            $localeDateFormat
                        );
                    }
                }
            }
        }

        //Split up the itemid and name
        $hasItemsWithMoreLength = false;
        $itemsArr = array();
        $warhsArr = array();
        foreach ( (($document['ENTRIES']) ?? []) as $key => $entry ) {
            if (isset( $entry['ITEMID']) && $entry['ITEMID'] !== '') {
                [$item] = explode('--', $entry['ITEMID']);
                $document['ENTRIES'][$key]['ITEMID'] = $item;
                if (isl_strlen($entry['ITEMID']) > 21 && !$iscustomdoc) {
                    $hasItemsWithMoreLength = true;
                }
                if ($item != '' && !in_array($item, $itemsArr)) {
                    $itemsArr[] = $item;
                }
                $warhsLocation = $entry['WAREHOUSE']['LOCATION_NO'];
                if ($warhsLocation != '' && !in_array($warhsLocation, $warhsArr)) {
                    $warhsArr[] = $warhsLocation;
                }
            }
        }
        if ($mod == 'po') {
            $itemMgr =  $gManagerFactory->getManager('item');
            $vendorStockNoCache = $itemMgr->GetVendorStockNoCache($itemsArr, $document['CUSTVENDID'], $warhsArr);
            foreach ( (($document['ENTRIES']) ?? []) as $key => $entry ) {
                $vendorStockNo = isset($vendorStockNoCache[$entry['ITEMID']][$entry['WAREHOUSE']['LOCATION_NO']]['STOCK_NUMBER'])
                && $vendorStockNoCache[$entry['ITEMID']][$entry['WAREHOUSE']['LOCATION_NO']]['STOCK_NUMBER'] != ''
                    ? $vendorStockNoCache[$entry['ITEMID']][$entry['WAREHOUSE']['LOCATION_NO']]['STOCK_NUMBER']
                    : $vendorStockNoCache[$entry['ITEMID']]['STOCK_NUMBER'];
                $document['ENTRIES'][$key]['STOCK_NUMBER'] = $vendorStockNo;
            }
        }

        // getting the totaldue value for custom invoice
        $totaldue = 0;
        if ( isset($document['PRRECORDKEY']) && $document['PRRECORDKEY'] != '' ) {
            $prrecordMgr =  $gManagerFactory->getManager('prrecord');
            $rec = $prrecordMgr->GetList(
                array(
                    'selects' => array('TOTALDUE'),
                    'filters' => array (array (array('RECORDNO', '=', $document['PRRECORDKEY']))),
                    'donottransform' => true
                )
            );
            if ( $rec ) {
                $totaldue = $rec[0]['TOTALDUE'];
            }
        }
        $document['PRRECORD']['TOTALDUE'] = Currency($totaldue);

        $docparMgr =  $gManagerFactory->getManager($mod . 'documentparams');
        $document['_DOCPAR'] = $docparMgr->get($document['DOCPARKEY']);

        if ( $this->ismcpEnabled ) {
            $document['MULTICURRENCY'] = 'true';
            $trxCurrencyMgr = $gManagerFactory->getManager('trxcurrencies');
            $CurrencyInfo = $trxCurrencyMgr->GetCurrencyInfo($document['CURRENCY']);
            if ( $CurrencyInfo['SYMBOL'] == '�' ) {
                $CurrencyInfo['SYMBOL'] = '&#8364;';
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            } else {
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            }
            $basecurrency = GetBaseCurrency();
            $transactioncurrency = $document['CURRENCY'];

            if ( $basecurrency != $transactioncurrency ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $this->ProcessMultiCurrencyLineEntriesForBlob($document, $iscustomdoc, $locale);
            }
        } else {
            $trxCurrencyMgr = $gManagerFactory->getManager('trxcurrencies');
            $CurrencyInfo = $trxCurrencyMgr->GetCurrencyInfo(GetBaseCurrency());
            if ( !isset($CurrencyInfo['SYMBOL']) ) {
                $CurrencyInfo['SYMBOL'] = "$";
            }
            if ( $CurrencyInfo['SYMBOL'] == '�' ) {
                $CurrencyInfo['SYMBOL'] = '&#8364;';
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            } else {
                $document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL'];
            }
            //$document['TRX_CURRENCY_SYMBOL'] = $CurrencyInfo['SYMBOL']= "$";
        }

        // this is for bug#19977
        if ( $hasItemsWithMoreLength ) {
            foreach ( (($document['ENTRIES']) ?? []) as $key => $entry ) {
                $isWhiteSpaceExists = isl_preg_match("' '", $entry['ITEMID']);
                if (!$isWhiteSpaceExists && isl_strlen($entry['ITEMID']) > 21 ) {
                    $newitemid = isl_substr($entry['ITEMID'], 0, 20) . " " . isl_substr($entry['ITEMID'], 20);
                    $document['ENTRIES'][$key]['ITEMID'] = $newitemid;
                }
            }
        }

        if ( $iscustomdoc ) {
            // for intacct toolbar's fields
            global $kSOid, $kPOid, $kINVid;
            $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
            $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
            GetModulePreferences($modArray[$this->mod], $prefs);
            $appPrecision = ($prefs['ITEMPRECISION']) ?: DEFAULT_INVPRECISION;

            $hasTrackEntries =false;
            foreach ( (($document['ENTRIES']) ?? []) as $key => $entry ) {
                if (!is_array($entry)){
                    continue;
                }
                if (array_key_exists('ITEM',$entry) && is_array($entry['ITEM']) && $entry['ITEM'][$precisionFields[$this->mod]] != '') {
                    $itemPrecision = $entry['ITEM'][$precisionFields[$this->mod]];
                } else {
                    $itemPrecision = $appPrecision;
                }
                // Ticket: 163688 PHP 8.1 exception
                // For some reason $itemPrecision is setting up as array it should always be numeric
                // so checking if its numeric and if its not defaulting the value to DEFAULT_INVPRECISION
                $itemPrecision = is_numeric($itemPrecision) ? $itemPrecision : DEFAULT_INVPRECISION;
                $temp = ibcmul($document['ENTRIES'][$key]['PRICE'], '1', $itemPrecision, false);
                /** @noinspection PhpUndefinedVariableInspection */
                $document['ENTRIES'][$key]['PRICE'] = formatNumberForLocale($temp, $locale, $itemPrecision);

                // format total fields
                if ( array_key_exists('GROUPTOTAL_PRICE', $document['ENTRIES'][$key]) ) {
                    $temp = ibcmul($document['ENTRIES'][$key]['GROUPTOTAL_PRICE'], '1', $itemPrecision, false);
                    $document['ENTRIES'][$key]['GROUPTOTAL_PRICE'] = formatNumberForLocale($temp, $locale, $itemPrecision);
                }

                $document['ENTRIES'][$key]['LINE_NO'] = $document['ENTRIES'][$key]['LINE_NO'] + 1;
                $document['ENTRIES'][$key]['EXCHRATETYPE'] = $document['EXCHRATETYPES']['NAME'];
                $document['ENTRIES'][$key]['TRX_CURRENCY_SYMBOL'] = $document['TRX_CURRENCY_SYMBOL'];
                $document['ENTRIES'][$key]['ITEM']['TAXABLE'] = ($document['ENTRIES'][$key]['ITEM']['TAXABLE'] == 'true') ? 'T' : '';

                $temp = ibcmul($document['ENTRIES'][$key]['EXCHRATE'], '1', 8, true) . '';
                $document['ENTRIES'][$key]['EXCHRATE'] = is_int($temp + 0) ? ibcmul($temp, '1', 2, false) : $temp;

                $temp = ibcmul($document['ENTRIES'][$key]['TOTAL'], '1', 2, true);
                $temp = ibcmul($temp, '1', 2, false);
                $document['ENTRIES'][$key]['TOTAL'] = formatNumberForLocale($temp, $locale);

                // ticket 56616 : adding new fields that needs to be formatted,
                // ticket 58822 : precision dictated by configuration
                $temp = ibcmul($document['ENTRIES'][$key]['TRX_PRICE'], '1', $itemPrecision, false);
                $document['ENTRIES'][$key]['TRX_PRICE'] = formatNumberForLocale($temp, $locale, $itemPrecision);
                $temp = ibcmul($document['ENTRIES'][$key]['TRX_VALUE'], '1', 2, false);
                $document['ENTRIES'][$key]['TRX_VALUE'] = formatNumberForLocale($temp, $locale);


                // format total fields
                if ( array_key_exists('GROUPTOTAL_VALUE', $document['ENTRIES'][$key]) ) {
                    $temp = ibcmul($document['ENTRIES'][$key]['GROUPTOTAL_VALUE'], '1', 2, false);
                    $document['ENTRIES'][$key]['GROUPTOTAL_VALUE'] = formatNumberForLocale($temp, $locale);
                }

                // reformat the dates for display
                $document['ENTRIES'][$key]['WHENCREATED'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['WHENCREATED'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['WHENPOSTED'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['WHENPOSTED'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['WHENDUE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['WHENDUE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['WHENPAID'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['WHENPAID'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['WHENMODIFIED'] = FormatTimestampForDisplay(
                    GMTToUserTZ($document['ENTRIES'][$key]['WHENMODIFIED']),
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['WHENDISCOUNT'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['WHENDISCOUNT'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['EXCHRATEDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['EXCHRATEDATE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['REVRECSTARTDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['REVRECSTARTDATE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['REVRECENDDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['REVRECENDDATE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['SC_REVRECSTARTDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['SC_REVRECSTARTDATE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['SC_REVRECENDDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['SC_REVRECENDDATE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['SC_STARTDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['SC_STARTDATE'],
                    $localeDateFormat
                );
                $document['ENTRIES'][$key]['TIMESHEETENTRY_ENTRYDATE'] = FormatDateForDisplay(
                    $document['ENTRIES'][$key]['TIMESHEETENTRY_ENTRYDATE'],
                    $localeDateFormat
                );
                //formatting date fields in both OE and PO
                $document['ENTRIES'][$key]['NEEDBYDATE'] =
                    FormatDateForDisplay($document['ENTRIES'][$key]['NEEDBYDATE'], $localeDateFormat);
                $document['ENTRIES'][$key]['DONOTSHIPBEFOREDATE'] =
                    FormatDateForDisplay($document['ENTRIES'][$key]['DONOTSHIPBEFOREDATE'], $localeDateFormat);
                $document['ENTRIES'][$key]['DONOTSHIPAFTERDATE'] =
                    FormatDateForDisplay($document['ENTRIES'][$key]['DONOTSHIPAFTERDATE'], $localeDateFormat);
                $document['ENTRIES'][$key]['CANCELAFTERDATE'] =
                    FormatDateForDisplay($document['ENTRIES'][$key]['CANCELAFTERDATE'], $localeDateFormat);

                if ( $mod == 'po' ) {
                    $document['ENTRIES'][$key]['DATECONFIRMED'] =
                        FormatDateForDisplay($document['ENTRIES'][$key]['DATECONFIRMED'], $localeDateFormat);
                    $document['ENTRIES'][$key]['PROMISEDDATE'] =
                        FormatDateForDisplay($document['ENTRIES'][$key]['PROMISEDDATE'], $localeDateFormat);
                }
                if ( $mod == 'so' ) {
                    $document['ENTRIES'][$key]['SHIPBY'] =
                        FormatDateForDisplay($document['ENTRIES'][$key]['SHIPBY'], $localeDateFormat);
                    $document['ENTRIES'][$key]['SHIPPEDDATE'] =
                        FormatDateForDisplay($document['ENTRIES'][$key]['SHIPPEDDATE'], $localeDateFormat);
                    $document['ENTRIES'][$key]['DATEPICKTICKETPRINTED'] =
                        FormatDateForDisplay($document['ENTRIES'][$key]['DATEPICKTICKETPRINTED'], $localeDateFormat);
                }

                $trackingEntries = $document['ENTRIES'][$key]['TRACKINGENTRIES'];
                if (!is_null($trackingEntries)){
                    $trackingEntries = is_array($trackingEntries) ? $trackingEntries : [$trackingEntries];
                    // adding !is_array($trackingEntries[$trackKey]) change to fix PHP 8.1
                    foreach ($trackingEntries as $trackKey => $trackEntry){
                        if( !is_array($trackingEntries[$trackKey]) ||
                            ( isNullOrBlank($trackingEntries[$trackKey]["SERIALNO"]) &&
                                isNullOrBlank($trackingEntries[$trackKey]["LOTNO"]) &&
                                isNullOrBlank($trackingEntries[$trackKey]["EXPIRATION"]) )){
                            unset($trackingEntries[$trackKey]);
                            continue;
                        }
                        //increment the line numbers for the UI by 1
                        $trackingEntries[$trackKey]["LINE_NO"] =  $trackingEntries[$trackKey]["LINE_NO"] + 1;
                    }
                    if(Util::countOrZero($trackingEntries) >0) {
                        $hasTrackEntries =true;
                    }
                    $document['ENTRIES'][$key]['TRACKINGENTRIES'] = array_values($trackingEntries);
                }
            }

            if (($this->mod == 'so' || $this->mod == 'po') && !$hasTrackEntries && is_array($document['ENTRIES'][0])) {
                $document['ENTRIES'][0]['TRACKINGENTRIES'] [] = ["LINE_NO" => null];
            }

            foreach ( (($document['SUBTOTALS']) ?? []) as $key => $entry ) {
                $document['SUBTOTALS'][$key]['TRX_CURRENCY_SYMBOL'] = $document['TRX_CURRENCY_SYMBOL'];
                $abstotal = ($document['SUBTOTALS'][$key]['ABSVAL']) ?: $document['SUBTOTALS'][$key]['TOTAL'];
                $trxabstotal = ($document['SUBTOTALS'][$key]['TRX_ABSVAL']) ?: $document['SUBTOTALS'][$key]['TRX_TOTAL'];
                $mytotal = ($document['SUBTOTALS'][$key]['TOTAL']) ?: $document['SUBTOTALS'][$key]['ABSVAL'];

                $document['SUBTOTALS'][$key]['TOTAL'] = ibcmul($mytotal, '1', 2, true);
                $document['SUBTOTALS'][$key]['TOTAL'] = ibcmul($document['SUBTOTALS'][$key]['TOTAL'], '1', 2, false);
                /** @noinspection PhpUndefinedVariableInspection */
                $document['SUBTOTALS'][$key]['TOTAL'] = formatNumberForLocale($document['SUBTOTALS'][$key]['TOTAL'], $locale);

                $document['SUBTOTALS'][$key]['TRX_TOTAL'] = ibcmul($trxabstotal, '1', 2, true);
                $document['SUBTOTALS'][$key]['TRX_TOTAL'] = ibcmul($document['SUBTOTALS'][$key]['TRX_TOTAL'], '1', 2, false);
                $document['SUBTOTALS'][$key]['TRX_TOTAL'] = formatNumberForLocale($document['SUBTOTALS'][$key]['TRX_TOTAL'], $locale);

                // ticket 56616 : adding new fields that needs to be formatted, precision dictated by $locale
                $document['SUBTOTALS'][$key]['ABSVAL'] = formatNumberForLocale($document['SUBTOTALS'][$key]['ABSVAL'], $locale);
                $document['SUBTOTALS'][$key]['TRX_ABSVAL'] = formatNumberForLocale($document['SUBTOTALS'][$key]['TRX_ABSVAL'], $locale);

            }

            /** @noinspection PhpUndefinedVariableInspection */
            $document['TOTAL'] = $abstotal;
            $temp = ibcmul($document['TOTAL'], '1', 2, true);
            $temp = ibcmul($temp, '1', 2, false);
            /** @noinspection PhpUndefinedVariableInspection */
            $document['TOTAL'] = formatNumberForLocale($temp, $locale);

            $temp = ibcmul($document['SUBTOTAL'], '1', 2, true);
            $temp = ibcmul($temp, '1', 2, false);
            $document['SUBTOTAL'] = formatNumberForLocale($temp, $locale);

            /** @noinspection PhpUndefinedVariableInspection */
            $document['TRX_TOTAL'] = $document['SUBTOTALS'][$key]['TRX_TOTAL'];
            $document['TOTAL_DUE'] = formatNumberForLocale($totaldue, $locale);

            // ticket 56616 : adding new fields that needs to be formatted, precision dictated by $locale
            $document['TOTALENTERED'] = formatNumberForLocale($document['TOTALENTERED'], $locale);
            $document['TOTALPAID'] = formatNumberForLocale($document['TOTALPAID'], $locale);
            $document['TOTALDUE'] = formatNumberForLocale($document['TOTALDUE'], $locale);
            $document['TRX_SUBTOTAL'] = ibcmul($document['TRX_SUBTOTAL'], '1', 2, false);
            $document['TRX_SUBTOTAL'] = formatNumberForLocale($document['TRX_SUBTOTAL'], $locale);
            $document['TRX_TOTALENTERED'] = formatNumberForLocale($document['TRX_TOTALENTERED'], $locale);
            $document['TRX_TOTALPAID'] = formatNumberForLocale($document['TRX_TOTALPAID'], $locale);
            $document['TRX_TOTALDUE'] = formatNumberForLocale($document['TRX_TOTALDUE'], $locale);

            if ( array_key_exists('PROJECT_BUDGETAMOUNT', $document) ) {
                $document['PROJECT_BUDGETAMOUNT'] = formatNumberForLocale($document['PROJECT_BUDGETAMOUNT'], $locale);
            }
            if ( array_key_exists('PROJECT_ACTUALBILLINGS', $document) ) {
                $document['PROJECT_ACTUALBILLINGS'] = formatNumberForLocale($document['PROJECT_ACTUALBILLINGS'], $locale);
            }

            // reformat these fields, like from 5.00000000 to 5.00, 0.73200000 to 0.732
            $document['EXCHRATE'] = ibcmul($document['EXCHRATE'], '1', 8, true) . '';
            $document['EXCHRATE'] = is_int($document['EXCHRATE'] + 0) ? ibcmul($document['EXCHRATE'], '1', 2, false) : $document['EXCHRATE'];

            // reformat the dates for display
            $document['WHENCREATED'] = FormatDateForDisplay($document['WHENCREATED'], $localeDateFormat);
            $document['WHENPOSTED'] = FormatDateForDisplay($document['WHENPOSTED'], $localeDateFormat);
            $document['WHENDUE'] = FormatDateForDisplay($document['WHENDUE'], $localeDateFormat);
            $document['WHENPAID'] = FormatDateForDisplay($document['WHENPAID'], $localeDateFormat);
            $document['WHENMODIFIED'] = FormatTimestampForDisplay(
                GMTToUserTZ($document['WHENMODIFIED']),
                $localeDateFormat
            );
            $document['WHENDISCOUNT'] = FormatDateForDisplay($document['WHENDISCOUNT'], $localeDateFormat);
            $document['EXCHRATEDATE'] = FormatDateForDisplay($document['EXCHRATEDATE'], $localeDateFormat);
            //formatting date fields in both OE and PO
            $document['NEEDBYDATE'] = FormatDateForDisplay($document['NEEDBYDATE'], $localeDateFormat);
            $document['DONOTSHIPBEFOREDATE'] =
                FormatDateForDisplay($document['DONOTSHIPBEFOREDATE'], $localeDateFormat);
            $document['DONOTSHIPAFTERDATE'] = FormatDateForDisplay($document['DONOTSHIPAFTERDATE'], $localeDateFormat);
            $document['CANCELAFTERDATE'] = FormatDateForDisplay($document['CANCELAFTERDATE'], $localeDateFormat);
            $document['SCHEDULESTARTDATE'] = FormatDateForDisplay($document['SCHEDULESTARTDATE'], $localeDateFormat);
            $document['ACTUALSTARTDATE'] = FormatDateForDisplay($document['ACTUALSTARTDATE'], $localeDateFormat);
            $document['SCHEDULEDCOMPLETIONDATE'] =
                FormatDateForDisplay($document['SCHEDULEDCOMPLETIONDATE'], $localeDateFormat);
            $document['REVISEDCOMPLETIONDATE'] =
                FormatDateForDisplay($document['REVISEDCOMPLETIONDATE'], $localeDateFormat);
            $document['SUBSTANTIALCOMPLETIONDATE'] =
                FormatDateForDisplay($document['SUBSTANTIALCOMPLETIONDATE'], $localeDateFormat);
            $document['ACTUALCOMPLETIONDATE'] =
                FormatDateForDisplay($document['ACTUALCOMPLETIONDATE'], $localeDateFormat);

            if ( $mod == 'po' ) {
                $document['CONTRACTSTARTDATE'] =
                    FormatDateForDisplay($document['CONTRACTSTARTDATE'], $localeDateFormat);
                $document['CONTRACTENDDATE'] = FormatDateForDisplay($document['CONTRACTENDDATE'], $localeDateFormat);
                $document['PROMISEDDATE'] = FormatDateForDisplay($document['PROMISEDDATE'], $localeDateFormat);
            }
            if ( $mod == 'so' ) {
                $document['SERVICEDELIVERYDATE'] =
                    FormatDateForDisplay($document['SERVICEDELIVERYDATE'], $localeDateFormat);
                $document['SHIPPEDDATE'] = FormatDateForDisplay($document['SHIPPEDDATE'], $localeDateFormat);
                $document['SHIPBYDATE'] = FormatDateForDisplay($document['SHIPBYDATE'], $localeDateFormat);
            }

            $document['PROJECT_BEGINDATE'] = FormatDateForDisplay($document['PROJECT_BEGINDATE'], $localeDateFormat);
            $document['PROJECT_ENDDATE'] = FormatDateForDisplay($document['PROJECT_ENDDATE'], $localeDateFormat);
        }

        global $kAVAid;
        $avalaraEnabled = GetPreferenceForProperty($kAVAid, 'AVA_ENABLE_SO');
        $ava_disp_detail_taxlines = GetPreferenceForProperty($kAVAid, 'AVA_DISP_DETAIL_TAXLINES');
        if ( $avalaraEnabled == 'T' && $ava_disp_detail_taxlines != 'T' ) {
            $avaSubtotals = array();
            foreach ( (($document['SUBTOTALS']) ?? []) as $val ) {
                if ( isl_substr($val['TAXDETAIL3P'], 0, 6) != 'AVATAX' ) {
                    $avaSubtotals[] = $val;
                }
            }
            $document['SUBTOTALS'] = $avaSubtotals;
        }
        if ($document['STATE'] ==  DocumentManager::DRAFT_STATE ) {
            // Append "DRAFT" to prevent fraud when printing draft document
            if (isset($document['DOCID'])) {
                $document['DOCID'] = ContractUtil::GTP($this->textMap, "IA.DOCUMENT_ID_DRAFT",
                                                        [ 'DOCUMENT_ID' => $document['DOCID']]  );
            }
            if (isset($document['DOCNO'])) {
                $document['DOCNO'] = ContractUtil::GTP($this->textMap, "IA.DOCUMENT_ID_DRAFT",
                                                        [ 'DOCUMENT_ID' => $document['DOCNO'] ] );
            }
        }
    
        $locKey = $document['MELOCATIONKEY'] ?? 0;

        if ( !isset($this->locationArrayCache[$locKey]) ) {
            $this->locationArrayCache[$locKey] =
                $this->GetLocationEntityData($document['MELOCATIONKEY']);
        }

        //Condition if CRE is enabled then copy details from source document for the given change doc.
        if ( CRESetupManager::isCREInstalled() ) {
            $this->updateChangeDocTotals($document, $locale);

        }

        $entityMgr->calculateBalanceToFinish($document);

        $printData = array(
            'COMPANY' => $this->GetCompanyData(true, $iscustomdoc),
            'REC' => $document,
            'LOCATIONENTITY' => $this->locationArrayCache[$locKey],
        );

        // the following credit cardinfo & remitto address are added for
        // custom invoice xls for a client.
        $company = GetCompanyDataForXML();
        $printData['COMPANY']['CreditCardsAccepted'] = $company['CreditCardsAccepted'];
        $printData['COMPANY']['CreditCards'] = $company['CreditCards'];
        $printData['COMPANY']['RemitToAddr'] = $company['RemitToAddr'][0];

        if(!$iscustomdoc){
            $billaddr1 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS1'];
            $billaddr2 = $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS2'];

            $shipaddr1 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS1'];
            $shipaddr2 = $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS2'];

            $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS1'] = MailaddressManager::GetTrimAddress($billaddr1);
            $printData['REC']['BILLTO']['MAILADDRESS']['ADDRESS2'] = MailaddressManager::GetTrimAddress($billaddr2);

            $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS1'] = MailaddressManager::GetTrimAddress($shipaddr1);
            $printData['REC']['SHIPTO']['MAILADDRESS']['ADDRESS2'] = MailaddressManager::GetTrimAddress($shipaddr2);
        }
        if ( $this->mod == 'so' ) {
            $entMgr =  $gManagerFactory->getManager('customer');
        } else {
            $entMgr =  $gManagerFactory->getManager('vendor');
        }
        $custvendEntity = $entMgr->GetRaw($printData['REC']['CUSTVENDID']);

        $printData['REC']['CUSTVENDNAME'] = $custvendEntity[0]['NAME'];
        $printData['REC']['CUSTVEND_TAXID'] = $this->mod == 'so' ? $custvendEntity[0]['TAXID'] : $entMgr->_DoDecrypt($custvendEntity[0]['TAXID'],[]);

        $this->reformatSubtotals($printData['REC'], true);

        $this->tokenizeSubTotals($printData['REC']);

        return $printData;
    }

    /**
     * @param array $obj
     * @param bool $forPrint
     *
     * @return bool
     */

    protected function reformatSubtotals(&$obj, $forPrint = false)
    {
        return true;
    }

    /**
     * Method to check if the document is purchase order and the Change document,
     * fetch the details of source doc and update it for the change doc totals.
     * 
     * @param array $document
     *
     */
    private function updateChangeDocTotals(array &$document, $locale)
    {
        if($this->mod == 'po' && strtolower($document['ENABLEDOCCHANGE']) == 'change order' && !empty($document['RELATEDDOCNO'])){
            $entity = $this->getEntity();
            $gManagerFactory = Globals::$g->gManagerFactory;
            $documentManager = $gManagerFactory->getManager($entity);
            $sourceDoc = $documentManager->get($document['RELATEDDOCNO']);
            $fieldsToBeUpdated = ['POSTEDCHANGESTOTAL', 'TRX_REVISEDTOTAL'];
            foreach ($fieldsToBeUpdated as $field) {
                $document[$field] = $sourceDoc[$field] ?? $document[$field];
            }

            $document['DRAFTCHANGEAMOUNTTOTAL'] = $sourceDoc['DRAFTCHANGES'] ?? null;
            $document['RELATED_INTERNALAPPROVEDBY'] = ($sourceDoc['INTERNALAPPROVEDBY'] ?? '').'--'.($sourceDoc['INTERNALAPPROVEDBYNAME'] ?? '');
            $document['RELATED_EXTERNALAPPROVEDBY'] = $sourceDoc['EXTERNALAPPROVEDBY'] ?? '';
            $sourceDocEntryIndex = [];
            $sourceDocRecordNoField = array_column($sourceDoc['ENTRIES'], 'RECORDNO');
            foreach ($document['ENTRIES'] as $key => $documentEntry){
                $relatedDocLineKey = $documentEntry['RELATEDDOCLINEKEY'] ?? null;

                if($relatedDocLineKey){
                    if(empty($sourceDocEntryIndex[$relatedDocLineKey])) {
                        $index = array_search($relatedDocLineKey, $sourceDocRecordNoField, true);
                        if ($index === false) {
                            continue;
                        }
                        $sourceDocEntryIndex[$relatedDocLineKey] = $index;
                    } else {
                        $index = $sourceDocEntryIndex[$relatedDocLineKey];
                    }
                    $sourceEntry = $sourceDoc['ENTRIES'][$index];

                    $document['ENTRIES'][$key]['POSTEDQTYCHANGES'] = formatNumberForLocale($sourceEntry['POSTEDQTYCHANGES'], $locale);
                    $document['ENTRIES'][$key]['POSTEDCHANGEEXTPRICE'] = formatNumberForLocale($sourceEntry['POSTEDCHANGEEXTPRICE'], $locale);
                    $document['ENTRIES'][$key]['DRAFTCHANGEPRICE'] = formatNumberForLocale($sourceEntry['DRAFTCHANGEPRICE'], $locale);
                    $document['ENTRIES'][$key]['DRAFTCHANGEQTY'] = formatNumberForLocale($sourceEntry['DRAFTCHANGEQTY'], $locale);
                    $document['ENTRIES'][$key]['REVISEDQTY'] = formatNumberForLocale($sourceEntry['REVISEDQTY'], $locale);
                    $document['ENTRIES'][$key]['REVISEDPRICE'] = formatNumberForLocale($sourceEntry['REVISEDPRICE'], $locale);
                    $document['ENTRIES'][$key]['TRX_REVISEDVALUE'] = formatNumberForLocale($sourceEntry['TRX_REVISEDVALUE'], $locale);
                    $document['ENTRIES'][$key]['QTY_CONVERTED'] = formatNumberForLocale($sourceEntry['QTY_CONVERTED'], $locale);
                    $document['ENTRIES'][$key]['PRICE_CONVERTED'] = formatNumberForLocale($sourceEntry['PRICE_CONVERTED'], $locale);
                    $document['ENTRIES'][$key]['TOTAL_AMOUNT_CONVERTED'] = formatNumberForLocale($sourceEntry['TOTAL_AMOUNT_CONVERTED'], $locale);
                    $document['ENTRIES'][$key]['TOTAL_AMOUNT_REMAINING'] = formatNumberForLocale($sourceEntry['TOTAL_AMOUNT_REMAINING'], $locale);
                    $document['ENTRIES'][$key]['QTY_REMAINING'] = formatNumberForLocale($sourceEntry['QTY_REMAINING'], $locale);
                }
            }
        } else if($this->mod == 'po' && strtolower($document['ENABLEDOCCHANGE']) == 'enable change'){
            $entity = $this->getEntity();
            $gManagerFactory = Globals::$g->gManagerFactory;
            $documentManager = $gManagerFactory->getManager($entity);
            $sourceDoc = $documentManager->get($document['RELATEDDOCNO']);
            $document['DRAFTCHANGEAMOUNTTOTAL'] = $sourceDoc['DRAFTCHANGES'] ?? null;
        }

        //update number format
        $formatNumberField = ['ORIGINALAMOUNT', 'TRX_REVISEDTOTAL', 'POSTEDCHANGESTOTAL', 'DRAFTCHANGEAMOUNTTOTAL', 'TOTALQTY_CONVERTED', 'TOTALPRICE_CONVERTED', 'TOTALAMOUNTCONVERTED', 'TOTALAMOUNTREMAINING', 'TOTALQTYREMAINING' ];
        foreach ($formatNumberField as $field){
            if(isset($document[$field])){
                $document[$field] = formatNumberForLocale($document[$field], $locale);
            }
        }

    }

    /**
     * @param $document
     */
    public static function tokenizeSubTotals(&$document)
    {
        //tokenize the Subtotal descriptions
        foreach ( (($document['SUBTOTALS']) ?? []) as $key=>$val ) {
            if (is_null($document['SUBTOTALS'][$key]['DESCRIPTION'])) {
                continue;
            }
            switch (strtoupper($document['SUBTOTALS'][$key]['DESCRIPTION'])) {
                case 'SUBTOTAL' :
                    $document['SUBTOTALS'][$key]['DESCRIPTION'] = I18N::getSingleToken('IA.SUBTOTAL');
                    break;
                case 'TOTAL':
                    $document['SUBTOTALS'][$key]['DESCRIPTION'] = I18N::getSingleToken('IA.TOTAL');
                    break;
                default :
                    //do nothing
            }
        }
    }
    /**
     * @return EntityManager|DocumentEntryManager
     */
    protected function getEntryManager()
    {
        return $this->GetManager($this->getEntity() . 'entry');
    }


    /**
     * @param string $docid
     * @param string $dt
     * @param string $mod
     * @param string $messagetext
     * @param string $marketingtext
     * @param bool $iscustomdoc
     *
     * @return string
     */
    protected function GetXMLForPrinting($docid, $dt, $mod, $messagetext, $marketingtext, $iscustomdoc=false)
    {
        //$gManagerFactory = Globals::$g->gManagerFactory;

        //if ( !is_object($this->entityMgr) ) {
        //    $this->entityMgr =  $this->GetManager($this->getEntity());
        //}

        // build XML for MailMerge Web Service
        if ( $iscustomdoc ) {

            $sodata = $this->GetDataForPrinting($docid, $dt, $mod, true);
            $xml = XMLUtils::BuildWSXML($sodata);

        } else {

            $xml = $this->getXmlFromBlobStore($docid);

            // if we still dont have the xml then lets query and get it...
            if ( !$xml ) {
                $t = $this->GetDataForPrinting($docid, $dt, $mod);
                $xml = XMLUtils::PHP2StdXMLStr($t);
            }
        }

        // add message text, marketing text
        $this->GetMessageAndMarketingTextForPrinting($xml, $messagetext, $marketingtext, $iscustomdoc);

        // For ME shared and entity context, append entity details
        $this->GetEntityDetailsForPrinting($xml, $iscustomdoc);

        // process document XML root
        $this->ProcessXMLRoot($xml, $iscustomdoc);

        //LogToFile($xml . "\n");
        //dieFL($xml);
        return $xml;
    }



    // fetchRelationshipValues
    /**
     * This function fetches all the values for platform relationship fields
     * ideally emgr->getList() should provide these but in absense this functions tries to retrieve
     * this function is heavily inspired from FormEditor->fetchPlatformRels()
     * if we atleast have one custom dimension created...
     *
     * @param EntityManager $entityMgr object entity manager instance
     * @param array         $document  array  array of current document values
     */
    protected function fetchRelationshipValues($entityMgr, &$document)
    {
        // fetch custom relationship attributes...
        if( ! util_isPlatformDisabled() ) {
            $docEntryObjects = array('invdocumententry', 'podocumententry', 'sodocumententry', 'documententry');
            $ownedObjects =& $entityMgr->GetOwnedObjects();

            foreach ($ownedObjects as $objRec) {
                // we want to loop only for docentry entities...
                if ( !in_array($objRec['entity'], $docEntryObjects) ) {
                    continue;
                }

                $mgr = $this->GetManager($objRec['entity']);
                $customEntity = $mgr->GetCustomComponentsEntity();
                $platformDef = Pt_StandardUtil::getObjDef($customEntity);

                // skip loop if no relationship found...
                if ( !$platformDef ) {
                    continue;
                }

                $platformRels = Pt_StandardUtil::getRelationshipFields($platformDef);

                foreach( $document[$objRec['path']] as $idx => $row ) {
                    foreach( $platformRels as $field ) {
                        $fieldName = isl_strtoupper($field->getFieldName());

                        /**
                         * @var Pt_FieldRelationship $uiField
                         */
                        $uiField = $field->getUIField();

                        $value = Pt_RelationshipManagerChoose::getObjectIds(
                            $field->getRelationshipDef(),
                            $field->getObjectDefId(),
                            $row['RECORDNO']
                        );

                        $ids = null;
                        if ($value instanceof Pt_ArrayIds) {
                            $ids = $value->getIds();
                        }

                        if ( isset($ids[0]) ) {
                            $getObjectDef2 = $uiField->getObjectDef2();

                            $lookup2FieldName = '';
                            $lookupTemplateFields = $getObjectDef2->getLookupTemplateFields();
                            if ( $lookupTemplateFields[1] ) {
                                $lookup2FieldName = $lookupTemplateFields[1]->getFieldName();
                            }

                            $data = Pt_DataObjectManager::getById($getObjectDef2, $ids[0]);
                            $allData = $data->getFullFieldMap(false, false);

                            $document[$objRec['path']][$idx][$fieldName] = $allData['name'];
                            if ( $allData[$lookup2FieldName] != '' ) {
                                $document[$objRec['path']][$idx][$fieldName] .= '--' . $allData[$lookup2FieldName];
                            }
                        }
                    }
                }
            }
        }

    }


    /**
     * Expanding the kit line entry to multiple lines for printing
     * @param array   $document
     *
     * @throws Exception
     */
    protected function ExpandKitForPrinting(&$document)
    {
        $docEntryDetailMgr =  Globals::$g->gManagerFactory->getManager('docentrydetail');
        $docID = $document['DOCID'];

        $expandedEntries = null;

        // Check if anything needs to be expanded (i.e. kit with individual components printing).  If so, try to get it from the blob store first.
        foreach ( (($document['ENTRIES']) ?? []) as $entry ) {
            if (!is_array($entry)){
                continue;
            }
            if ( $entry['ITEM']['ITEMTYPE'] == 'Kit' && $entry['ITEM']['REVPRINTING'] == 'Individual Components' ) {
                // See if we can use the XML from blob store
                $xml = $this->getXmlFromBlobStore($docID);
                if (!empty($xml)) {
                    $tree = XMLUtils::XMLStr2XMLCompact($xml);
                    if (isset($tree['ROOT']['REC']['ENTRIES'])) {
                        $expandedEntries = $tree['ROOT']['REC']['ENTRIES'];
                    }
                }
                break;
            }
        }

        if (empty($expandedEntries)) {
            foreach ( (($document['ENTRIES']) ?? []) as $lineNo => $entry ) {
                if (!is_array($entry)){
                    continue;
                }
                if ( $entry['ITEM']['ITEMTYPE'] == 'Kit' && $entry['ITEM']['REVPRINTING'] == 'Individual Components' ) {

                    $kitItemInfos = $docEntryDetailMgr->DoQuery('QRY_DOCENTRYDETAIL_GETKITDETAIL_BY_DOCID_LINENO', array($this->cny, $docID, $lineNo));

                    if ( sizeof($kitItemInfos) > 0 ) {
                        foreach ( $kitItemInfos as $kitItemInfo ) {
                            $newKitItemEntry = $entry;
                            $newKitItemEntry['ITEMID'] = $kitItemInfo['ITEMID'];
                            $newKitItemEntry['ITEMDESC'] = $kitItemInfo['ITEMDESC'];
                            $newKitItemEntry['UNIT'] = $kitItemInfo['ITEMUNIT']; //using the kit component unit
                            $newKitItemEntry['QUANTITY'] = $kitItemInfo['ITEMQUANTITY'] * $newKitItemEntry['QUANTITY']; //the real kit component quantity
                            $newKitItemEntry['PRICE'] = $kitItemInfo['INVOICEPRICE'];
                            $newKitItemEntry['TOTAL'] = $kitItemInfo['INVOICEPRICE'];
                            $newKitItemEntry['UIPRICE'] = $kitItemInfo['INVOICEPRICE'];   //this is displayed in pdf
                            $newKitItemEntry['UIVALUE'] = $kitItemInfo['INVOICEPRICE'];   //this is displayed in pdf

                            $expandedEntries[] = $newKitItemEntry;
                        }
                    } else {
                         $tempExpandedEntries = $this->ExpandKitCompFromDocument($document);
                         $expandedEntries= $tempExpandedEntries['ENTRIES'];
                         break;
                    }
                }
                else {
                    $expandedEntries[] = $entry;
                }
            }
        }

        $document['ENTRIES'] = $expandedEntries;
    }

    /**
     * @param array $document
     * Get the expand Kit for the restricted users who cannot use the stored BLOB unlike admin
     * @return array
     */
    public function ExpandKitCompFromDocument(array $document):array
    {
        $documentMgr = $this->getEntityMgr();
        //Adjustments to call the prepLineItems
        foreach($document['ENTRIES'] as $key=>$entry){
            $document['ENTRIES'][$key]['ITEMID']        = explode('--', $entry['ITEMID'])[0];
            $document['ENTRIES'][$key]['ITEMTYPE']      = $entry['ITEM']['ITEMTYPE']  == 'Kit' ? 'K' : $entry['ITEM']['ITEMTYPE'] ;
            $document['ENTRIES'][$key]['REVPRINTING']   = $entry['ITEM']['REVPRINTING'] == 'Individual Components' ? 'I' : 'K';
            $document['DIMENSIONFIELDS'] = $documentMgr->GetDimensionFields();
            $document['PRIMARYDIMENSION'] = $documentMgr->getPrimaryDimensions();

            $itemId = explode('--', $entry['ITEMID'] ?? '')[0];
            if ($entry['ITEMALIASID'] == $itemId){
                $document['ENTRIES'][$key]['ITEMALIASID'] = '';
            }
        }

        $handlers = array();
        $handlers['TRACKING_HANDLER'] = new TrackingHandler(array('ACTION' => EDIT_ACTION));
        $ok =$documentMgr->PrepLineItems($document,$handlers,false,true);

        //now revert back the values
        foreach($document['ENTRIES'] as $key=>$entry){
            if ($entry['ITEMALIASID'] == ''){
                $itemId = explode('--', $entry['ITEMID'] ?? '')[0];
                $document['ENTRIES'][$key]['ITEMALIASID'] = $itemId;
            }
        }

        if ($ok && $document['PRINTFORMATENTRIES']) {
            $documentMgr->MergeAndReplaceKit($document);
        }
        return $document;
    }

    /**
     * @param string    $xml
     * @param string|null    $docid
     *
     * @return string
     */
    protected function ProcessDateFormatForPrinting(&$xml, $docid)
    {
        $thisEntity = $this->getEntity();
        $entityMgr =  $this->GetManager($thisEntity);

        if ( !$docid ) {
            $vid = $entityMgr->GetKeyFieldName();
            $docid = Request::$r->{Request::$r->PathToFieldName($vid)};
        }

        $dateFlds = array();

        if (empty($entityMgr->_fieldInfoMap)) {
            $entityMgr->GetEntityInfoMap();
        }
        foreach($entityMgr->_fieldInfoMap as $fld){
            if ( $fld['type']['type']=='date' && in_array($fld['path'], $entityMgr->_schemas[$thisEntity]['object']) ) {
                $dateFlds[] = $fld['path'];
            }
        }

        // This is nothing to do with DateFormat. We are adding -DRAFT in DOCID and DOCNO when printing draft documents
        $selects = $dateFlds;
        $selects[] = 'STATE';
        $selects[] = 'DOCNO';

        $querySpec = array(
            'selects' => $selects,
            'filters' => array(
                array(
                    array('DOCID', '=', $docid),
                )
            ),
        );
        $document = $entityMgr->GetList($querySpec);
        $document = $document[0];

        foreach ($dateFlds as $dfld) {
            if ( $document[$dfld] != '' ) {
                preg_match_all(
                    "/<{$dfld}>(0?[1-9]|1[012])\/(0?[1-9]|[12][0-9]|3[01])\/((?:19|20)[0-9][0-9])<\/{$dfld}>/",
                    $xml,
                    $matches,
                    PREG_UNMATCHED_AS_NULL,
                    0
                );

                if (count($matches[0]) > 0) {
                    $patterns = [];
                    $replacements = [];
                    $dates = [];
                    foreach ($matches[0] as $match) {
                        $date = str_replace(["<{$dfld}>", "</{$dfld}>"],['',''], $match);
                        if (false === in_array($date, $dates)) {
                            $dates[] = $date;
                            $formattedDate = FormatDateForDisplay($date);
                            $patterns[] = '/'
                                . preg_quote(
                                    sprintf('<%s>%s</%s>', $dfld, $date, $dfld),
                                    '/'
                                    )
                                . '/';
                            $replacements[] = sprintf('<%s>%s</%s>', $dfld, $formattedDate, $dfld);
                        }
                    }
                    $xml = preg_replace($patterns, $replacements, $xml);
                }
            }
        }

        // This is nothing to do with DateFormat. We are adding -DRAFT in DOCID and DOCNO when printing draft documents
        if (isset($document['STATE']) && $document['STATE'] == DocumentManager::DRAFT_STATE) {
            $xml = str_replace('<DOCID>'.$docid.'</DOCID>', '<DOCID>'.$docid.'-DRAFT</DOCID>', $xml);
            if (isset($document['DOCNO']) && $document['DOCNO'] != '') {
                $docno = $document['DOCNO'];
                $xml = str_replace('<DOCNO>'.$docno.'</DOCNO>', '<DOCNO>'.$docno.'-DRAFT</DOCNO>', $xml);
            }
        }

        return $xml;
    }


    /**
     * @param string    $xml
     * @param string    $messagetext
     * @param string    $marketingtext
     * @param bool      $iscustomdoc
     *
     * @return string
     */
    protected function GetMessageAndMarketingTextForPrinting(&$xml, $messagetext, $marketingtext, $iscustomdoc)
    {
        $hasmsgtxt = isset($messagetext) && $messagetext !== '';
        $hasmkttxt = isset($marketingtext) && $marketingtext !== '';
        //If Marketing text not set then take from company, it has been used in Quench Custom Invoices
        if ( !$hasmsgtxt || !$hasmkttxt ) {
            $companyData = $this->GetCompanyData(true, $iscustomdoc);
            if (!$hasmsgtxt) {
                $messagetext = $companyData['MESSAGE_TEXT'];
            }
            if (!$hasmkttxt) {
                $marketingtext = $companyData['MARKETING_TEXT'];
            }
        }
        //Remove special characters
        $messagetext = XMLUtils::xmlSpecialChars($messagetext);
        $marketingtext = XMLUtils::xmlSpecialChars($marketingtext);

        // stick message text & marketing text within XML
        if ( $iscustomdoc ) {
            $_cmtstart = isl_strpos($xml, "<key>COMPANY_MESSAGE_TEXT</key>\n<value>");
            if ( $_cmtstart != false ) {
                $start = $_cmtstart + 39;
                $end = isl_strpos($xml, '</value>', $start);
                $xml = isl_substr($xml, 0, $start) . $messagetext . isl_substr($xml, $end);
            }
            $_cmtstart = isl_strpos($xml, "<key>COMPANY_MARKETING_TEXT</key>\n<value>");
            if ( $_cmtstart != false ) {
                $start = $_cmtstart + 41;
                $end = isl_strpos($xml, '</value>', $start);
                $xml = isl_substr($xml, 0, $start) . $marketingtext . isl_substr($xml, $end);
            }
        } else {
            $_mtstart = isl_strpos($xml, '<MESSAGE_TEXT>');
            if ( $_mtstart != false ) {
                $start = $_mtstart + 14;
                $end = isl_strpos($xml, '</MESSAGE_TEXT>');
                $xml = isl_substr($xml, 0, $start) . $messagetext . isl_substr($xml, $end);
            }
            $_mtstart = isl_strpos($xml, '<MARKETING_TEXT>');
            if ( $_mtstart != false ) {
                $start = $_mtstart + 16;
                $end = isl_strpos($xml, '</MARKETING_TEXT>');
                $xml = isl_substr($xml, 0, $start) . $marketingtext . isl_substr($xml, $end);
            }
        }

        return $xml;
    }


    /**
     * Adds <ENTITY_INFO> XML struct into XML for printing for ME Shared and at entity context.
     *
     * Constructs structure as below and appends to XML after </COMPANY> tag,
     *   <ENTITY_INFO>
     *         <NAME></NAME>
     *         <ID></ID>
     *         <REPORTPRINTAS></REPORTPRINTAS>
     *         <WEEKSTART></WEEKSTART>
     *         <START_DATE></START_DATE>
     *         <ADDR1></ADDR1>
     *         <ADDR2></ADDR2>
     *         <CITY></CITY>
     *         <STATE></STATE>
     *         <ZIP></ZIP>
     *         <COUNTRY></COUNTRY>
     *         <PRINTAS></PRINTAS>
     *         <PHONE1></PHONE1>
     *         <EMAIL1></EMAIL1>
     *     </ENTITY_INFO>
     *
     * @param string $xml (input XML), $iscustomdoc (if custom document?)
     * @param bool   $iscustomdoc
     *
     * @return string $xml (output XML)
     * @access private
     */
    protected function GetEntityDetailsForPrinting(&$xml, /** @noinspection PhpUnusedParameterInspection */ $iscustomdoc)
    {

        // If not ME Shared or ME Shared but not at entity context, nothing is reqd
        if ( !( IsMultiEntityCompany() && GetContextLocation() ) ) {
            return true;
        }

        $entityXML = '';
        $entInfo = GetContextLocationDetails();
        $renameArr = array('LOCATION_NO' => 'ID');
        foreach ( $entInfo as $key => $val ) {
            $tagName = $key;
            if ( isset($renameArr[$key]) && $renameArr[$key] != '' ) {
                $tagName = $renameArr[$key];
            }
            $start_tag = '<' . $tagName . '>';
            if ( isset($val) && $val != '' ) {
                $valTag = XMLUtils::xmlSpecialChars($val);
            } else {
                $valTag = '<undef/>';
            }
            $end_tag = '</' . $tagName . '>';
            $entityXML .= $start_tag . $valTag . $end_tag . "\n        ";
        }
        $entityXML = isl_rtrim($entityXML, "        ");
        if ($entityXML != '' ) {
            $xml = str_replace("</COMPANY>", "</COMPANY>\n    <ENTITY_INFO>\n        $entityXML   </ENTITY_INFO>", $xml);
        }

        return $xml;
    }


    /**
     * @param string    $xml
     * @param bool      $iscustomdoc
     *
     * @return string
     */
    protected function ProcessXMLRoot(&$xml, $iscustomdoc)
    {

        // we only want to do this replacement if we are going to print via a print_layout and,
        // not an editor_layout
        // editor layouts are going to have a problem when printing multiples.
        if ( $this->XSL_Template_Type != 'entity_edit_layout' ) {
            // make sure DOC/DOX templates won't be processed here but XSL will
            if ( !$iscustomdoc ) {
                // we only want to do this replacement if we are going to print via a print_layout and not an editor_layout
                // editor layouts are going to have a problem when printing multiples.
                $xml = "<DOCUMENT>" . $xml . "</DOCUMENT>";
                $xml = str_replace("<ROOT", "<OLDROOT", $xml);
                $xml = str_replace("</ROOT", "</OLDROOT", $xml);
            }
        }

        return $xml;
    }


    /**
     * @param array         $values
     * @param bool          $iscustomdoc
     * @param string        $locale
     *
     * @throws Exception
     */
    protected function ProcessMultiCurrencyLineEntriesForBlob(&$values, $iscustomdoc, $locale)
    {
        global $kSOid, $kPOid, $kINVid;

        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
        $modEntityArray = array('so' => 'sodocument', 'po' => 'podocument', 'inv' => 'invdocument');

        GetModulePreferences($modArray[$this->mod], $prefs);
        $appPrecision = ($prefs['ITEMPRECISION']) ?: DEFAULT_INVPRECISION;

        if ( isset($values['SUBTOTALS']) ) {
            /**
             * @var DocumentManager $docMgr
             */
            $docMgr = Globals::$g->gManagerFactory->getManager($modEntityArray[$this->mod]);
            if ( !$iscustomdoc ) {
                $docMgr->subtotalsForBlob($values);
            } else {
                $docMgr->subtotalsForCustomDocBlob($values);
            }
        }
        // updating the script on using coding best practices for loop as per PHP 8.1 exception
        for ( $i = 0, $_i_ct = Util::countOrZero($values['ENTRIES']); $i < $_i_ct; $i++ ) {
            if ( $values['ENTRIES'][$i]['ITEM'][$precisionFields[$this->mod]] != '' ) {
                $itemPrecision = $values['ENTRIES'][$i]['ITEM'][$precisionFields[$this->mod]];
            } else {
                $itemPrecision = $appPrecision;
            }
            // Ticket: 163688 PHP 8.1 exception
            // For some reason $itemPrecision is setting up as array it should always be numeric
            // so checking if its numeric and if its not defaulting the value to DEFAULT_INVPRECISION
            $itemPrecision = is_numeric($itemPrecision) ? $itemPrecision : DEFAULT_INVPRECISION;

            $temp = $values['ENTRIES'][$i]['TRX_PRICE'];
            $temp = ibcmul($temp, '1', $itemPrecision, false);
            $values['ENTRIES'][$i]['UIPRICE'] = formatNumberForLocale($temp, $locale, $itemPrecision);

            $temp = $values['ENTRIES'][$i]['TRX_VALUE'];
            $temp = ibcmul($temp, '1', 2, false);
            $values['ENTRIES'][$i]['UIVALUE'] = formatNumberForLocale($temp, $locale);

            // exposing these fields to the toolbar
            $temp = ibcmul($values['ENTRIES'][$i]['PRICE'], '1', $itemPrecision, true);
            $values['ENTRIES'][$i]['PRICE'] = formatNumberForLocale($temp, $locale, $itemPrecision);
        }
    }


    /**
     * @param string[] $docparmrec
     * @param array $_params        it can be 7 levels deep!  Sheesh!
     */
    protected function ChangeContactLabels($docparmrec, &$_params)
    {
        //	Set the Contact Labels from the doc par information here
        $pagecount = count($_params['pages']);

        for ( $i = 0; $i < $pagecount; $i++ ) {
            if ( $_params['pages'][$i]['title'] == "Header" ) {

                $fieldcount = count($_params['pages'][$i]['fields']);

                for ( $j = 0; $j < $fieldcount; $j++ ) {
                    if ( is_array($_params['pages'][$i]['fields'][$j]['columns']) ) {
                        foreach ( $_params['pages'][$i]['fields'][$j]['columns'] as $key => $field ) {
                            if ($field['path'] == 'BILLTO.CONTACTNAME') {
                                $contactTitle1 = ContractUtil::GTP($this->textMap, "IA.CONTACT_TITLE_CONTACT",
                                                                   [ [ 'CONTACT_TITLE' => $docparmrec['CONTACTTITLE1'] ] ]);
                                $_params['pages'][$i]['fields'][$j]['fullname'] =
                                    $contactTitle1;
                                $_params['pages'][$i]['fields'][$j]['columns'][$key]['JSFullname'] = $contactTitle1;
                            }
                            if ($field['path'] == 'SHIPTO.CONTACTNAME') {
                                $contactTitle2 = ContractUtil::GTP($this->textMap, "IA.CONTACT_TITLE_CONTACT",
                                                                   [ [ 'CONTACT_TITLE' => $docparmrec['CONTACTTITLE2'] ] ]);
                                $_params['pages'][$i]['fields'][$j]['fullname'] = $contactTitle2;
                                $_params['pages'][$i]['fields'][$j]['columns'][$key]['JSFullname'] = $contactTitle2;
                            }
                        }
                    }
                }
            }
        }
    }


    /**
     * @return int
     */
    protected function lookupAppPrecision()
    {

        global $kINVid, $kSOid, $kPOid;

        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        GetModulePreferences($modArray[$this->mod], $prefs);

        return ($prefs['ITEMPRECISION']) ?: 2;
    }


    /**
     * @param array       $values
     * @param string    $key
     *
     * @return string[]
     * @throws Exception
     */
    protected function prepSalesforceValues($values, $key)
    {
        $kSFORCE2id = Globals::$g->kSALESFORCE2id;

        if( !IsModuleIdInstalled($kSFORCE2id) ){
            return $this->prepSalesforceValues_v1($values, $key);
        }else {
            GetModulePreferences($kSFORCE2id, $sfpreferences);
            return $this->prepSalesforceValues_v2($values, $key, $sfpreferences);
        }
    }


    /**
     * @param array   $values
     * @param string $key
     *
     * @return array
     * @throws Exception
     */
    protected function prepSalesforceValues_v1($values, $key)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        include_once "ObjectStoreManager.cls";

        // gets the values for the mcp enabled companies.
        $mcpsubscribed = IsMCPSubscribed();
        $sfismcp = GetPreferenceForProperty(Globals::$g->kSFORCEid, 'SFORCEISMCP');
        $isLineShipToEnabled = GetPreferenceForProperty(Globals::$g->kSOid, 'SHIPTO_FOR_LINEITEM') == 'T';

        // get the values out of the object store
        $objstore = new ObjectStoreManager();
        $sfdcvalues = $objstore->get($key);
        $new = $values;

        // need to convert the custvendid.

        $new['CUSTVENDID'] = $sfdcvalues['OBJECTDATA']['CUSTOMERID'] ?: $values['CUSTVENDID'];
        $new['PONUMBER'] = $sfdcvalues['OBJECTDATA']['NAME'] ?: $values['PONUMBER'];
        $new['MESSAGE'] = $sfdcvalues['OBJECTDATA']['DESCRIPTION'] ?: $new['MESSAGE'];
        $new['SFORCEID'] = $sfdcvalues['OBJECTDATA']['SFORCEID'] ?: $new['SFORCEID'];
        $new['SFORCEKEY'] = $sfdcvalues['OBJECTDATA']['SFORCEKEY'] ?: $new['SFORCEKEY'];
        //Get Template definition
        $docType = $sfdcvalues['OBJECTDATA']['DOCTYPE'];
        /**
         * @var DocumentParamsManager   $docparMgr
         */
        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
        $_docpar = $docparMgr->GetLatestRaw($docType);
        $_docpar = $_docpar[0];

        // getting the currency and exchange rate from sales force and populate in the sales document.
        if ( $mcpsubscribed && $sfismcp == 'true' && $sfdcvalues['OBJECTDATA']['CURRENCYISOCODE']) {
            $new['CURRENCY'] = $sfdcvalues['OBJECTDATA']['CURRENCYISOCODE'];
        }
        //Copy Sforce
        if ( !$new['SFORCEID'] && $new['RECORDNO'] ) {   //
            $subscription = $gManagerFactory->getManager('imssubscription');
            $new['SFORCEID'] = $subscription->GetExternalId($new['RECORDNO'], 'SODOCUMENTOPP', 'SFORCE');
        }

        //To get SFDC Opportunity Line Items
        include_once "SforceSynchronizer.cls";
        $sfSync = new SforceSynchronizer();

        // Collect custom field details for SF Opportunity object
        $iaobj = 'SODOCUMENT';
        $iaobjdoctype = $new['DOCPARID'];
        $sfobj = 'Opportunity';
        $sfobjkey = 'Id';
        $sfobjval = $new['SFORCEID'];
        $sfSync->GetSFCustomFieldValues($iaobj, $iaobjdoctype, $sfobj, $sfobjkey, $sfobjval, $new, true, true);
        //eppp_p($new);

        $custMgr = $gManagerFactory->getManager('customer');

        $custParams = array(
            'selects' => array(
                'CUSTMESSAGEID',
                'SHIPTO.CONTACTNAME',
                'BILLTO.CONTACTNAME',
                'CREDITLIMIT',
                'TOTALDUE',
            ),
            'filters'    => array(array(
                                      array('CUSTOMERID', '=', $new['CUSTVENDID'])
                                  )),
        );

        $custInfo = $custMgr->GetList($custParams);
        $this->sfcrlimit = $custInfo[0]['CREDITLIMIT'];
        $this->sftotdue = $custInfo[0]['TOTALDUE'];

        if ( $new['MESSAGE'] == '' || $sfSync->_preferences['SFORCEPRICINGOPT'] != SFORCEPRICING ) {

            if ( $new['MESSAGE'] == '' && isset($custInfo[0]['CUSTMESSAGEID']) && $custInfo[0]['CUSTMESSAGEID'] != '' ) {
                $custMsgMgr = $gManagerFactory->getManager('custmessage');
                $params = array(
                    'selects' => array(
                        'MESSAGE',
                    ),
                    'filters'    => array(array(
                                              array('MESSAGEID', '=', $custInfo[0]['CUSTMESSAGEID']),
                                              array('STATUS', '=', 'active'),
                                          )),
                );

                $custMsgInfo = $custMsgMgr->GetList($params);
                if ( isset($custMsgInfo[0]['MESSAGE']) ) {
                    $new['MESSAGE'] = $custMsgInfo[0]['MESSAGE'];
                }
            }
        }

        if ( $sfSync->ShowOppLineItems() ) {

            // Collect custom field details for SF Opportunity Product object
            $iaobj = 'SODOCUMENTENTRY';
            $iaobjdoctype = $new['DOCPARID'];
            $ret = $sfSync->GetFieldMapStruct($iaobj, $iaobjdoctype);
            $fields = $ret['fields'];
            $fieldDetails = $ret['fieldDetails'];

            //Get Opportunity Product List
            $fldArr = (is_array($fields) && count($fields)) ? $fields : array();
            $ProductItems = $sfSync->GetOppProductItems($fldArr);

            //only if Opportunity have Products
            if ( $ProductItems ) {
                /** @var ItemManager $itemMgr */
                $itemMgr = $gManagerFactory->getManager('item');

                //Handle SFDC Pricing Option
                if ( $sfSync->_preferences['SFORCEPRICINGOPT'] == SFORCEPRICING ) {
                    $this->sfdcPricing = 'true';
                } else {
                    //Handles Intacct Pricing
                    $_shipto = $custInfo[0]['SHIPTO.CONTACTNAME'];
                    $_billto = $custInfo[0]['BILLTO.CONTACTNAME'];
                    $_date = GetCurrentDate();
                    $currency = $new['CURRENCY'];
                }

                $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
                /** @noinspection PhpUndefinedVariableInspection */
                $priceParams = $pricingHandler->PrepParams($new['CUSTVENDID'], $_billto, $_shipto, $_date, $this->mod);

                //Get default warehouse, if it is set
                $docpar = $this->GetBaseDocPar();
                if ( $docpar['WAREHOUSESELMETHOD'] == 'Use the default warehouse' ) {
                    GetUserPreferences($upref, 'DEFAULT_WAREHOUSE');
                    $upref_docpar_whse = $upref['DEFAULT_WAREHOUSE'];
                    if ( $upref_docpar_whse == '' && $docpar['DEFAULT_WAREHOUSE'] != '' ) {
                        $upref_docpar_whse = $docpar['DEFAULT_WAREHOUSE'];
                    }
                    //warehoue key should be good enough to auto-populate the warehouse
                    $whse_location_name = $upref_docpar_whse;
                    //if ( $upref_docpar_whse != '' ) {
                    //    $whse_name = QueryResult(array("select NAME from ICWAREHOUSE where cny# = :1 and LOCATION_NO = :2", $this->cny, $upref_docpar_whse));
                    //    $whse_location_name = $upref_docpar_whse . '--' . $whse_name[0]['NAME'];
                    //}
                }else{
                    $warehouses = $this->GetWarehouses($docpar['WAREHOUSESELMETHOD']);
                    $whse_location_name = $warehouses[0]['WHSE'];
                }

                //Autofill the value for primary dimensions 'CUSTOMER' for SODOCUMENT
                $soDocEntryMgr = $gManagerFactory->getManager($this->mod . "documententry");
                $dimcolumns = $soDocEntryMgr->GetDimensionFields();
                $custDimEnabled = false;
                foreach ( $dimcolumns as $dimcolumn ) {
                    if( $dimcolumn['path'] == 'CUSTOMERID' ) {
                        $custDimEnabled = true;
                    }
                }
                $uomgrpMgr = $gManagerFactory->getManager('uom');
                $itemsArr = array();

                $count = 0;
                foreach ( $ProductItems as $ProductItem ) {
                    //Get Item Unit Measurements
                    $ItemData = $itemMgr->Get($ProductItem['PRODUCTCODE']);
                    if ( $ItemData ) {
                        $itemsArr[] = $ProductItem['PRODUCTCODE'];
                        $uom = $uomgrpMgr->get($ItemData['UOMGRP']);
                        $new['ENTRIES'][$count]['UNIT'] =  $uom['OEUOM'];
                        $new['ENTRIES'][$count]['ITEM']['UOMGRPKEY'] =  $uom['RECORDNO'];
                        //$new['ENTRIES'][$count]['UNIT'] = $ItemData['SALES_UNIT'];
                        $new['ENTRIES'][$count]['ITEMID'] = $ProductItem['PRODUCTCODE'];
                        $new['ENTRIES'][$count]['MEMO'] = $ProductItem['DESCRIPTION'];
                        $new['ENTRIES'][$count]['UIQTY'] = $ProductItem['QUANTITY'] ?? 1;
                        $new['ENTRIES'][$count]['ITEMDESC'] = $ProductItem['NAME'];
                        $new['ENTRIES'][$count]['ITEMTERM'] = $ItemData['TERMPERIOD'];
                        $new['ENTRIES'][$count]['TERMPERIOD'] = $ItemData['TOTALPERIODS'];
                        if ($isLineShipToEnabled) {
                            $new['ENTRIES'][$count]['SHIPTO']['CONTACTNAME'] = $values['SHIPTO']['CONTACTNAME'];
                        }

                        if ( $this->sfdcPricing == 'true' ) {
                            $saleprice = $ProductItem['UNITPRICE'];
                            $new['ENTRIES'][$count]['RETAILPRICE'] = $ProductItem['LISTPRICE'];
                        } else {
                            //Intacct Pricing Rule applied
                            /** @noinspection PhpUndefinedVariableInspection */
                            $price = $pricingHandler->SuggestPrice($priceParams, $new['ENTRIES'][$count]['ITEMID'], $ItemData['PRODUCTLINEID'], $new['ENTRIES'][$count]['UIQTY'], $_docpar, $currency);
                            if ( !$price ) {
                                $price = "0.00";
                            }
                            // Find the OE Conv factor
                            foreach ( $uom['ENTRIES'] as $unitInfo) {
                                if ($unitInfo['UNIT'] == $uom['OEUOM']) {
                                    /** @noinspection PhpUndefinedVariableInspection */
                                    $sfactor = $uomInfo['CONVFACTOR'];
                                }
                            }

                            // by default use sfactor as 1
                            /** @noinspection PhpUndefinedVariableInspection */
                            if (!$sfactor) {
                                $sfactor = 1;
                            }
                            //Calculate price based on Sales Unit  Factor
                            $saleprice = $price * $sfactor;
                            $new['ENTRIES'][$count]['RETAILPRICE'] = $saleprice;
                        }
                        if($saleprice == 0) {
                            $saleprice = '0.00';
                        }
                        if(isset($new['ENTRIES'][$count]['MULTIPLIER']) && $new['ENTRIES'][$count]['MULTIPLIER'] !='') {
                            $uivalue =
                                $saleprice * $new['ENTRIES'][$count]['UIQTY'] * $new['ENTRIES'][$count]['MULTIPLIER'];
                        }
                        else {
                            $uivalue = $saleprice * $new['ENTRIES'][$count]['UIQTY'];
                        }
                        if($uivalue == 0) {
                            $uivalue = '0.00';
                        }

                        if ( $mcpsubscribed ) {
                            $priceField = 'TRX_PRICE';
                            $valueField = 'TRX_VALUE';
                        } else {
                            $priceField = 'UIPRICE';
                            $valueField = 'UIVALUE';
                        }
                        $new['ENTRIES'][$count][$priceField] = $saleprice;
                        $new['ENTRIES'][$count][$valueField] = $uivalue;

                        $new['ENTRIES'][$count]['REVRECSTARTDATE'] = $ProductItem['SERVICEDATE'];
                        $new['ENTRIES'][$count]['REVRECENDDATE'] = $ProductItem['SERVICEENDDATE__C'];
                        $new['ENTRIES'][$count]['ITEMTYPE'] = $ItemData['ITEMTYPE'];
                        $itemType = $ItemData['ITEMTYPE'];
                        //If itemtype is NONINV or NONINV_SO then do not build value for warehouse
                        if(!in_array($itemType, array(NONINV, NONINV_SO))) {
                            //Queries according to the warehouse selection method
                            if ( $docpar['WAREHOUSESELMETHOD'] == 'Warehouse with Available Inventory' ) {
                                $invavailwhse = $itemMgr->DoQuery('QRY_ITEM_INVAVAIL_WHSE', array($ProductItem['PRODUCTCODE'], $this->cny));
                                if(isset($invavailwhse[0]['WAREHOUSEKEY']) && $invavailwhse[0]['WAREHOUSEKEY'] != '') {
                                    $whse_location_name = $invavailwhse[0]['WAREHOUSEKEY'];
                                }
                            }
                            $new['ENTRIES'][$count]['WAREHOUSE']['LOCATION_NO'] = $whse_location_name;
                        } else{
                            $new['ENTRIES'][$count]['WAREHOUSE']['LOCATION_NO'] = '';
                        }
                        if($custDimEnabled) {
                            $new['ENTRIES'][$count]['CUSTOMERID'] = $new['CUSTVENDID'];
                        }


                        // Append SF opportunity product custom fields to intacct document entry line
                        $sfSync->GetOppProductCustomFieldsForEntry(
                            $fieldDetails, $ProductItem, $new['ENTRIES'][$count]
                        );

                        // Apply discount only if the discount percent is provided
                        if (isArrayValueProvided($new['ENTRIES'][$count], 'DISCOUNTPERCENT')) {
                            $discount = 1 - $new['ENTRIES'][$count]['DISCOUNTPERCENT'] / 100.00;

                            if ($new['ENTRIES'][$count][$priceField] && $new['ENTRIES'][$count][$priceField] != 0) {
                                // Apply discount to the price if there is a valid price
                                $new['ENTRIES'][$count][$priceField] = $new['ENTRIES'][$count][$priceField] * $discount;
                            }
                            if ($new['ENTRIES'][$count][$valueField] && $new['ENTRIES'][$count][$valueField] != 0) {
                                // Apply discount to the extended price only if there
                                // is a valid extended price
                                $new['ENTRIES'][$count][$valueField] = $new['ENTRIES'][$count][$valueField] * $discount;
                            }
                        }

                        $count = $count + 1;
                    }
                } // End of foreach
                // Populate item units based on item UOM
                $entryCnt = countArray($new['ENTRIES']);
                if ($entryCnt && $itemsArr) {
                    $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, true);
                    for ( $i = 0; $i < $entryCnt; $i++ ) {
                        if (isset($new['ENTRIES'][$i]['ITEMUOM'])) {
                            continue;
                        }
                        $tempItemID = explode("--", $new['ENTRIES'][$i]['ITEMID']);
                        $tempItemID = $tempItemID[0];

                        $itemuoms = array();
                        foreach ( $uomInfoVals[$tempItemID] as $value ) {
                            $itemuoms[] = $value;
                        }
                        $new['ENTRIES'][$i]['ITEMUOM'] = $itemuoms;
                    }
                }
            }
        }
        //if mcp is enabled and trx currency is different than base currency
        if ( $this->ismcpEnabled ) {
            $new['EXCHRATEDATE'] = GetCurrentDate();
            $basecurr = GetBaseCurrency();
            if ( $new['CURRENCY'] != $basecurr ) {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $exchRateMgr = $gManagerFactory->getManager('exchangerate');

                $new['EXCH_RATE_TYPE_ID'] = $_docpar['EXCH_RATE_TYPE_ID'];
                //Get default Exchange rate for company level
                $rtype = $exchTypeMgr->GetDefaultExchangeRateType();
                if ( $rtype[0]['ID'] != '-1' ) {
                    $new['EXCH_RATE_TYPE_ID'] = $rtype[0]['ID'];
                }

                if ( $new['EXCH_RATE_TYPE_ID'] == '-1' || $new['EXCH_RATE_TYPE_ID'] == '' ) {
                    $exchRate = $exchRateMgr->GetIntacctExchangeRate($new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                } else {
                    $exchRate = $exchRateMgr->GetTrxExchangeRateByTypeID($new['EXCH_RATE_TYPE_ID'], $new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                }
                if ($exchRate !== false) {
                    $new['EXCHRATE'] = $exchRate;
                }
            }
        }

        // Auto-fill on server-side when coming from SFDC
        if (!util_isPlatformDisabled()) {
            foreach ( (($new['ENTRIES']) ?? []) as $idx => $entry) {
                $this->getEntityMgr()->validateAndSetPlatformEnforcedAutoFill($new['ENTRIES'][$idx], true, true);
                $this->setGLDimRelsAttribute($this->getEntityMgr()->_entity, null, $new['ENTRIES'][$idx]);
            }
        }

        return $new;
    }

    /**
     * @param array   $values
     * @param string $key
     * @param string[] $sfpreferences
     *
     * @return array
     * @throws Exception
     */
    protected function prepSalesforceValues_v2($values, $key, $sfpreferences)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        include_once "ObjectStoreManager.cls";
        include_once "SforceConstants.inc";
        $sfNameSpace = isl_strtoupper(SforceNamespaceHandler::getPrefix());
        $isLineShipToEnabled = GetPreferenceForProperty(Globals::$g->kSOid, 'SHIPTO_FOR_LINEITEM') == 'T';

        // gets the values for the mcp enabled companies.
        $mcpsubscribed = IsMCPSubscribed();
        $sfismcp = $sfpreferences['SFORCEISMCP'];

        // get the values out of the object store
        $objstore = new ObjectStoreManager();
        $sfdcvalues = $objstore->get($key);
        $new = $values;

        // need to convert the custvendid.

        $new['CUSTVENDID'] = $sfdcvalues['OBJECTDATA']['CUSTOMERID'] ?: $values['CUSTVENDID'];
        $new['BILLTO']['CONTACTNAME'] = $sfdcvalues['OBJECTDATA']['BILLTO'] ?: $values['BILLTO']['CONTACTNAME'];
        $shipToContact = $sfdcvalues['OBJECTDATA']['CUSTOMERID'] ? $sfdcvalues['OBJECTDATA']['SHIPTO'] : $values['SHIPTO']['CONTACTNAME'];
        $new['SHIPTO']['CONTACTNAME'] = $shipToContact;
        $new['PONUMBER'] = $sfdcvalues['OBJECTDATA']['NAME'] ?: $values['PONUMBER'];
        $new['MESSAGE'] = $sfdcvalues['OBJECTDATA']['DESCRIPTION'] ?: $new['MESSAGE'];
        $new['SFORCEID'] = $sfdcvalues['OBJECTDATA']['SFORCEID'] ?: $new['SFORCEID'];
        $new['SFORCEKEY'] = $sfdcvalues['OBJECTDATA']['SFORCEKEY'] ?: $new['SFORCEKEY'];

        $defaultLocation = $sfdcvalues['OBJECTDATA'][$sfNameSpace.'INTACCT_LOCATION__C'];

        //Get Template definition
        $docType = $sfdcvalues['OBJECTDATA']['DOCTYPE'];
        /**
         * @var DocumentParamsManager   $docparMgr
         */
        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
        $_docpar = $docparMgr->GetLatestRaw($docType);
        $_docpar = $_docpar[0];

        // getting the currency and exchange rate from sales force and populate in the sales document.
        if ( $mcpsubscribed && $sfismcp == 'true' && $sfdcvalues['OBJECTDATA']['CURRENCYISOCODE']) {
            $new['CURRENCY'] = $sfdcvalues['OBJECTDATA']['CURRENCYISOCODE'];
        }
        //Copy Sforce
        if ( !$new['SFORCEID'] && $new['RECORDNO'] ) {
            $subscription = $gManagerFactory->getManager('imssubscription');
            $new['SFORCEID'] = $subscription->GetExternalId($new['RECORDNO'], 'SODOCUMENTOPP', 'SFORCE');
        }
        if ( !empty($defaultLocation) ) {
            if ( !isset($subscription) ) {
                $subscription = $gManagerFactory->getManager('imssubscription');
            }
            $defaultLocation = $subscription->GetIntacctId($defaultLocation, 'LOCATIONENTITY', SforceNamespaceHandler::SUBSCRIBER_NAME);
        }
        $defaultTerm = $sfdcvalues['OBJECTDATA'][$sfNameSpace . 'TERM__C'];
        if ( !empty($defaultTerm) ) {
            if ( !isset($subscription) ) {
                $subscription = $gManagerFactory->getManager('imssubscription');
            }
            $term = $subscription->GetIntacctId($defaultTerm, 'ARTERM', SforceNamespaceHandler::SUBSCRIBER_NAME);
            $new['TERM']['NAME'] = $term ?: $values['TERM']['NAME'];
        }
        //To get SFDC Opportunity Line Items
        //include_once "SforceSynchronizer.cls";
        //$sfSync = new SforceSynchronizer();

        // Collect custom field details for SF Opportunity object
        if($sfpreferences['ISFIELDMAP'] == 'true'){
            SforceSyncProcessorMisc::getOppCustomFieldsValue($new);
        }

        $custMgr = $gManagerFactory->getManager('customer');

        $custParams = array(
            'selects' => array(
                'CUSTMESSAGEID',
                'SHIPTO.CONTACTNAME',
                'BILLTO.CONTACTNAME',
                'CREDITLIMIT',
                'TOTALDUE',
            ),
            'filters'    => array(array(
                                      array('CUSTOMERID', '=', $new['CUSTVENDID'])
                                  )),
        );

        $custInfo = $custMgr->GetList($custParams);
        $this->sfcrlimit = $custInfo[0]['CREDITLIMIT'];
        $this->sftotdue = $custInfo[0]['TOTALDUE'];



        if ( $new['MESSAGE'] == '' || $sfpreferences['SFORCEOEPRICINGOPT'] != 'F' ) {

            if ( $new['MESSAGE'] == '' && isset($custInfo[0]['CUSTMESSAGEID']) && $custInfo[0]['CUSTMESSAGEID'] != '' ) {
                $custMsgMgr = $gManagerFactory->getManager('custmessage');
                $params = array(
                    'selects' => array(
                        'MESSAGE',
                    ),
                    'filters'    => array(array(
                                              array('MESSAGEID', '=', $custInfo[0]['CUSTMESSAGEID']),
                                              array('STATUS', '=', 'active'),
                                          )),
                );

                $custMsgInfo = $custMsgMgr->GetList($params);
                if ( isset($custMsgInfo[0]['MESSAGE']) ) {
                    $new['MESSAGE'] = $custMsgInfo[0]['MESSAGE'];
                }
            }
        }

        //if ( $sfSync->ShowOppLineItems() ) { //TODO:: Doesn't make sense to check product sync is enabled or not

        // Collect custom field details for SF Opportunity Product object
        /*$iaobj = 'SODOCUMENTENTRY';
        $iaobjdoctype = $new['DOCPARID'];
        $customFieldsMap = SforceSyncProcessorMisc::GetCustomFieldsMap($iaobj, $iaobjdoctype, false);
        $ProductItems = SforceSyncProcessorMisc::GetOppProductItems($customFieldsMap);
        */
        $activeStandardFields = [];
        /** @noinspection PhpUndefinedVariableInspection */
        $ProductItems = SforceSyncProcessorMisc::GetOppProductItems($new['DOCPARID'], $activeStandardFields, $subscription);

        //only if Opportunity have Products
        if ( $ProductItems ) {
            /** @var ItemManager $itemMgr */
            $itemMgr = $gManagerFactory->getManager('item');

            //Handle SFDC Pricing Option
            //TODO:: Need name space for 'F' priceing rule
            if ( $sfpreferences['SFORCEOEPRICINGOPT'] == 'F' ) {
                $this->sfdcPricing = 'true';
            } else {
                //Handles Intacct Pricing
                $_shipto = $custInfo[0]['SHIPTO.CONTACTNAME'];
                $_billto = $custInfo[0]['BILLTO.CONTACTNAME'];
                $_date = GetCurrentDate();
                $currency = $new['CURRENCY'];
            }

            $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
            /** @noinspection PhpUndefinedVariableInspection */
            $priceParams = $pricingHandler->PrepParams($new['CUSTVENDID'], $_billto, $_shipto, $_date, $this->mod);

            //Get default warehouse, if it is set
            $docpar = $this->GetBaseDocPar();
            $warehouses = [];
            if ( $docpar['WAREHOUSESELMETHOD'] == 'Use the default warehouse' ) {
                GetUserPreferences($upref, 'DEFAULT_WAREHOUSE');
                $upref_docpar_whse = $upref['DEFAULT_WAREHOUSE'];
                if ( $upref_docpar_whse == '' && $docpar['DEFAULT_WAREHOUSE'] != '' ) {
                    $upref_docpar_whse = $docpar['DEFAULT_WAREHOUSE'];
                }
                //warehoue key should be good enough to auto-populate the warehouse
                $whse_location_name = $upref_docpar_whse;
            }else{
                $warehouses = $this->GetWarehouses($docpar['WAREHOUSESELMETHOD']);
                $whse_location_name = ''; //$warehouses[0]['WHSE'];
            }

            //Autofill the value for primary dimensions 'CUSTOMER' for SODOCUMENT
            $soDocEntryMgr = $gManagerFactory->getManager($this->mod . "documententry");
            $dimcolumns = $soDocEntryMgr->GetDimensionFields();
            $custDimEnabled = false;
            foreach ( $dimcolumns as $dimcolumn ) {
                if( $dimcolumn['path'] == 'CUSTOMERID' ) {
                    $custDimEnabled = true;
                }
            }
            $uomgrpMgr = $gManagerFactory->getManager('uom');
            $itemsArr = array();

            $count = 0;
            foreach ( $ProductItems as $ProductItem ) {
                //Get Item Unit Measurements
                $ItemData = $itemMgr->Get($ProductItem['PRODUCTCODE']);
                if ( $ItemData ) {
                    $itemsArr[] = $ProductItem['PRODUCTCODE'];
                    $uom = $uomgrpMgr->get($ItemData['UOMGRP']);
                    $new['ENTRIES'][$count]['UNIT'] =  $uom['OEUOM'];
                    $new['ENTRIES'][$count]['ITEM']['UOMGRPKEY'] =  $uom['RECORDNO'];
                    //$new['ENTRIES'][$count]['UNIT'] = $ItemData['SALES_UNIT'];
                    $new['ENTRIES'][$count]['ITEMID'] = $ProductItem['PRODUCTCODE'];
                    if (in_array('MEMO', $activeStandardFields)) {
                        $new['ENTRIES'][$count]['MEMO'] = $ProductItem['DESCRIPTION'];
                    }
                    $new['ENTRIES'][$count]['UIQTY'] = $ProductItem['QUANTITY'] ?? 1;
                    $new['ENTRIES'][$count]['ITEMDESC'] = $ProductItem['NAME'];
                    $new['ENTRIES'][$count]['ITEMTERM'] = $ItemData['TERMPERIOD'];
                    $new['ENTRIES'][$count]['TERMPERIOD'] = $ItemData['TOTALPERIODS'];
                    $new['ENTRIES'][$count]['LOCATION'] = $ProductItem[$sfNameSpace.'INTACCT_LOCATION__C'] ?: $defaultLocation;
                    $new['ENTRIES'][$count]['DEPARTMENT'] = $ProductItem[$sfNameSpace.'DEPARTMENT__C'];
                    $new['ENTRIES'][$count]['CLASSID'] = $ProductItem[$sfNameSpace.'CLASS__C'];
                    $new['ENTRIES'][$count]['EMPLOYEEID'] = $ProductItem[$sfNameSpace.'EMPLOYEE__C'];
                    if ($isLineShipToEnabled) {
                        $new['ENTRIES'][$count]['SHIPTO']['CONTACTNAME'] = $ProductItem[$sfNameSpace.'SHIP_TO_CONTACT__C'] ?? $shipToContact;
                    }

                    if ( $this->sfdcPricing == 'true' ) {
                        $saleprice = $ProductItem['UNITPRICE'];
                        $new['ENTRIES'][$count]['RETAILPRICE'] = $ProductItem['LISTPRICE'];
                    } else {
                        //Intacct Pricing Rule applied
                        /** @noinspection PhpUndefinedVariableInspection */
                        $price = $pricingHandler->SuggestPrice($priceParams, $new['ENTRIES'][$count]['ITEMID'], $ItemData['PRODUCTLINEID'], $new['ENTRIES'][$count]['UIQTY'], $_docpar, $currency);
                        if ( !$price ) {
                            $price = "0.00";
                        }
                        // Find the OE Conv factor
                        foreach ( $uom['ENTRIES'] as $unitInfo) {
                            if ($unitInfo['UNIT'] == $uom['OEUOM']) {
                                /** @noinspection PhpUndefinedVariableInspection */
                                $sfactor = $uomInfo['CONVFACTOR'];
                            }
                        }

                        // by default use sfactor as 1
                        /** @noinspection PhpUndefinedVariableInspection */
                        if (!$sfactor) {
                            $sfactor = 1;
                        }
                        //Calculate price based on Sales Unit  Factor
                        $saleprice = $price * $sfactor;
                        $new['ENTRIES'][$count]['RETAILPRICE'] = $saleprice;
                    }
                    if($saleprice == 0) {
                        $saleprice = '0.00';
                    }
                    if(isset($new['ENTRIES'][$count]['MULTIPLIER']) && $new['ENTRIES'][$count]['MULTIPLIER'] !='') {
                        $uivalue =
                            $saleprice * $new['ENTRIES'][$count]['UIQTY'] * $new['ENTRIES'][$count]['MULTIPLIER'];
                    }
                    else {
                        $uivalue = $saleprice * $new['ENTRIES'][$count]['UIQTY'];
                    }
                    if($uivalue == 0) {
                        $uivalue = '0.00';
                    }


                    if ( $mcpsubscribed ) {
                        $priceField = 'TRX_PRICE';
                        $valueField = 'TRX_VALUE';
                    } else {
                        $priceField = 'UIPRICE';
                        $valueField = 'UIVALUE';
                    }
                    $new['ENTRIES'][$count][$priceField] = $saleprice;
                    $new['ENTRIES'][$count][$valueField] = $uivalue;

                    $new['ENTRIES'][$count]['REVRECSTARTDATE'] = $ProductItem['SERVICEDATE'];
                    $new['ENTRIES'][$count]['REVRECENDDATE'] = $ProductItem[$sfNameSpace.'SERVICE_END_DATE__C'];
                    $new['ENTRIES'][$count]['ITEMTYPE'] = $ItemData['ITEMTYPE'];
                    $itemType = $ItemData['ITEMTYPE'];
                    //If itemtype is NONINV or NONINV_SO then do not build value for warehouse
                    if(!in_array($itemType, array(NONINV, NONINV_SO))) {
                        //Queries according to the warehouse selection method
                        if ( $docpar['WAREHOUSESELMETHOD'] == 'Warehouse with Available Inventory' ) {
                            $invavailwhse = $itemMgr->DoQuery('QRY_ITEM_INVAVAIL_WHSE', array($ProductItem['PRODUCTCODE'], $this->cny));
                            if(isset($invavailwhse[0]['WAREHOUSEKEY']) && $invavailwhse[0]['WAREHOUSEKEY'] != '') {
                                $whse_location_name = $invavailwhse[0]['WAREHOUSEKEY'];
                            }
                        }

                        if (isset($ProductItem['LOCATION_NO'])) {
                            $sforceWarehouseId = $ProductItem['LOCATION_NO'];

                            foreach ($warehouses as $ws) {
                                if ($sforceWarehouseId === $ws['WAREHOUSEID']) {
                                    $whse_location_name = $ws['WHSE'];
                                    break;
                                }
                            }
                        }

                        $new['ENTRIES'][$count]['WAREHOUSE']['LOCATION_NO'] = $whse_location_name;
                    } else{
                        $new['ENTRIES'][$count]['WAREHOUSE']['LOCATION_NO'] = '';
                    }
                    if($custDimEnabled) {
                        $new['ENTRIES'][$count]['CUSTOMERID'] = $new['CUSTVENDID'];
                    }

                    //$fieldDetails = array_values($customFieldsMap);
                    // Append SF opportunity product custom fields to intacct document entry line
                    //$sfSync->GetOppProductCustomFieldsForEntry(
                    //    $fieldDetails, $ProductItem, $new['ENTRIES'][$count]
                    //);
                    //TODO:: Crate the map between item fields and $ProductItem fields and perform all transaction and
                    //formatting in GetOppProductItems()
                    //SforceSyncProcessorMisc::getOppProductCustomFieldsForEntry($customFieldsMap,$ProductItem, )
                    $new['ENTRIES'][$count] = array_merge($new['ENTRIES'][$count], $ProductItem);

                    // Apply discount only if the discount percent is provided
                    if (isArrayValueProvided($new['ENTRIES'][$count], 'DISCOUNTPERCENT')) {
                        $discount = 1 - $new['ENTRIES'][$count]['DISCOUNTPERCENT'] / 100.00;
                        if ($new['ENTRIES'][$count][$priceField] && $new['ENTRIES'][$count][$priceField] != 0) {
                            // Apply discount to the price if there is a valid price
                            $new['ENTRIES'][$count][$priceField] = $new['ENTRIES'][$count][$priceField] * $discount;
                        }
                        if ($new['ENTRIES'][$count][$valueField] && $new['ENTRIES'][$count][$valueField] != 0) {
                            // Apply discount to the extended price only if there
                            // is a valid extended price
                            $new['ENTRIES'][$count][$valueField] = $new['ENTRIES'][$count][$valueField] * $discount;
                        }
                    }

                    $count = $count + 1;
                }
            } // End of foreach
            // Populate item units based on item UOM
            $entryCnt = countArray($new['ENTRIES']);
            if ($entryCnt && $itemsArr) {
                $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, true);
                for ( $i = 0; $i < $entryCnt; $i++ ) {
                    if (isset($new['ENTRIES'][$i]['ITEMUOM'])) {
                        continue;
                    }
                    $tempItemID = explode("--", $new['ENTRIES'][$i]['ITEMID']);
                    $tempItemID = $tempItemID[0];

                    $itemuoms = array();
                    foreach ( $uomInfoVals[$tempItemID] as $value ) {
                        $itemuoms[] = $value;
                    }
                    $new['ENTRIES'][$i]['ITEMUOM'] = $itemuoms;
                }
            }
        }
        //}
        //if mcp is enabled and trx currency is different than base currency
        if ( $this->ismcpEnabled ) {
            $new['EXCHRATEDATE'] = GetCurrentDate();
            $basecurr = GetBaseCurrency();
            if ( $new['CURRENCY'] != $basecurr ) {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $exchRateMgr = $gManagerFactory->getManager('exchangerate');

                $new['EXCH_RATE_TYPE_ID'] = $_docpar['EXCH_RATE_TYPE_ID'];
                //Get default Exchange rate for company level
                $rtype = $exchTypeMgr->GetDefaultExchangeRateType();
                if ( $rtype[0]['ID'] != '-1' ) {
                    $new['EXCH_RATE_TYPE_ID'] = $rtype[0]['ID'];
                }

                if ( $new['EXCH_RATE_TYPE_ID'] == '-1' || $new['EXCH_RATE_TYPE_ID'] == '' ) {
                    $exchRate = $exchRateMgr->GetIntacctExchangeRate($new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                } else {
                    $exchRate = $exchRateMgr->GetTrxExchangeRateByTypeID($new['EXCH_RATE_TYPE_ID'], $new['CURRENCY'], $basecurr, $new['EXCHRATEDATE']);
                }
                if ($exchRate !== false) {
                    $new['EXCHRATE'] = $exchRate;
                }
            }
        }

        // Auto-fill on server-side when coming from SFDC
        if (!util_isPlatformDisabled()) {
            foreach ( (($new['ENTRIES']) ?? []) as $idx => $entry) {
                $this->getEntityMgr()->validateAndSetPlatformEnforcedAutoFill($new['ENTRIES'][$idx], true, true);
                $this->setGLDimRelsAttribute($this->getEntityMgr()->_entity, null, $new['ENTRIES'][$idx]);
            }
        }

        return $new;
    }


    /**
     * While convertng document, copy parent's document date to $newDoc
     *
     * @access private
     *
     * @param array   $sourceDoc
     * @param array   $newDoc
     * @param array   $newDocpar
     *
     * @return bool
     */
    function GetOrigDocDate(
        /** @noinspection PhpUnusedParameterInspection */ $sourceDoc,
        /** @noinspection PhpUnusedParameterInspection */ &$newDoc,
        /** @noinspection PhpUnusedParameterInspection */ $newDocpar)
    {
        return true;
    }


    /**
     * This function will give array of warehouses as per selecetd method in TD
     *
     * @param string $selectionMethod
     *
     * @return array[]|false
     * @throws Exception
     *
     */
    protected function GetWarehouses($selectionMethod)
    {
        //Queries according to the warehouse selection method
        $gManagerFactory = Globals::$g->gManagerFactory;
        if ( $selectionMethod == 'Sort by Name') {
            $icwhseMgr = $gManagerFactory->getManager('warehouse');
            $querySpec = array(
                'selects' => array(
                    'LOCATION_NO||\'--\'||NAME', 'LOCATION_NO'
                ),
                'columnaliases' => array('WHSE', 'WAREHOUSEID'),
                'filters' => array(
                    array(array('STATUS', '=', 'active'))
                ),
                'orders' => array( array('NAME', 'asc'), array('LOCATION_NO', 'asc')),
            );

            $warehouses = $icwhseMgr->GetList($querySpec);
        }else{
            $icwhseMgr = $gManagerFactory->getManager('warehouse');
            $querySpec = array(
                'selects' => array(
                    'LOCATION_NO||\'--\'||NAME', 'LOCATION_NO'
                ),
                'columnaliases' => array('WHSE', 'WAREHOUSEID'),
                'filters' => array(
                    array(array('STATUS', '=', 'active'))
                ),
                'orders' => array( array('LOCATION_NO', 'asc')),
            );
            $warehouses = $icwhseMgr->GetList($querySpec);
        }
        return $warehouses;
    }


    /**
     * @param array   $obj
     *
     * @return bool
     */
    function processDefaultDimensionsForSubtotals(&$obj)
    {

        //In old Editor, Header Dimension values are directly under $obj to keep the compactibility copy it from 'GRID_DEFAULTS_PAGE'.
        foreach((($obj['GRID_DEFAULTS_PAGE']) ?? []) as $path => $value) {
            $obj[$path] = $value;
        }
        //Old Editor keep PRIMARYDIMENSION also with Header Dimension structure.
        foreach((($obj['PRIMARYDIMENSION']) ?? []) as $path => $value) {
            $obj['HEADER_'.$path] = $obj[$value];
        }
        return true;
    }

    /**
     * @param array   $obj
     */
    function mediateDataAndMetadata_DefaultEntries(&$obj)
    {
        $dimensions = IADimensions::GetDimensionIDs();
        if(!empty($dimensions)) {
            foreach( $obj as $path => $value) {
                if (isl_strpos($path, "HEADER_") === 0) {
                    $headerDim = isl_substr($path, isl_strlen("HEADER_"));
                    if (in_array($headerDim, $dimensions)) {
                        $obj['GRID_DEFAULTS_PAGE'][$path] = $obj[$path];
                        unset($obj[$path]);
                    }
                }
            }
        }
    }

    /**
     * @param array $obj
     */
    function mediateDataAndMetadata_ConstrictList(&$obj)
    {
    }


    // Subclasses to override this
    /**
     * This function will decide to showup the draft mode for a transaction or not
     *
     * @access protected
     * @return bool
     */
    protected function IsDraftMode()
    {
        return true;
    }

    /**
     * @param string   $copy
     * @param array   &$old
     *
     * @return bool
     */
    protected function processCopyConvert(
        /** @noinspection PhpUnusedParameterInspection */ $copy,
        /** @noinspection PhpUnusedParameterInspection */ &$old)
    {
        return true;
    }


    /**
     * This function will decide the display of GL posting date display.
     *
     * @access protected
     *
     * @param array   $docpar
     * @param bool $autofill
     *
     * @return bool
     */
    protected function ShowGLPostingDate(
        /** @noinspection PhpUnusedParameterInspection */ $docpar,
        /** @noinspection PhpUnusedParameterInspection */ &$autofill=false)
    {
        return false;
    }

    /**
     * @param array   $_params
     * @param array   $objRec
     */
    protected function MergeOwnedDimensions(&$_params, $objRec)
    {
        parent::MergeOwnedDimensions($_params, $objRec);

        $matches = array();
        $itemid = array();
        if ( !util_isPlatformDisabled() ) {
            self::findElements(
                $_params['view'], array('path' => $objRec['path']), EditorComponentFactory::TYPE_GRID,
                $matches
            );

            if ( $matches && $matches[0] ) {
                self::findElements(
                    $matches[0], array('path' => 'ITEMID'), EditorComponentFactory::TYPE_FIELD,
                    $itemid
                );

                if ( $itemid && $itemid[0] ) {
                    $itemid[0]['autofillrelated'] = Pt_StandardUtil::autoFillRelated('item');
                    $itemid[0]['gridPath'] = $objRec['path'];
                }
            }
        }

    }

    /**
     * @param string $docid
     * @return string
     */
    private function getXmlFromBlobStore($docid)
    {
        $xml = null;
        $useBlob = true;

        // decide if we can use the generated blob to the document
        // for mega companies with not owned document or restricted users we will have to regenerate the xml
        if (IsMultiEntityCompany()) {
            $useBlob = ($this->getEntityMgr()->IsOwned($docid) && !IsRestrictedUser() ? true : false);
        }

        if ($useBlob) {
            $blobStoreMgr = Globals::$g->gManagerFactory->getManager('blobstore');
            $xml = (string)$blobStoreMgr->GetByParent($docid, 'INVDOCXML');
            //Remove map of integer array stored in blob to prevent XSL error
            $this->removeBadXmlDataFromBlob($xml);

            //Format date for printing
            $this->ProcessDateFormatForPrinting($xml, $docid);
        }
        return $xml;
    }

    /**
     * @param string $xml
     *
     * @return string
     */
    protected function removeBadXmlDataFromBlob(&$xml)
    {
        //Remove map of integer array stored in blob to prevent XSL error
        $start = isl_strpos($xml, '<SYSTEMTAXDETAILMAP');

        if ($start !== false) {
            $end = isl_strpos($xml, '</SYSTEMTAXDETAILMAP>');
            if ($end !== false && $start < $end) {
                $endpos = $end + strlen('</SYSTEMTAXDETAILMAP>');
                $xml = isl_substr($xml, 0, $start) . "" . isl_substr($xml, $endpos);
            }
        }

        $this->recalculatePcbData($xml);

        return $xml;
    }


    /**
     * ITEMID is also treated like a dimension for use-cases like auto-fill and filtering
     *
     * @return string[]
     */
    protected function getPTNotSupportedDimensionFieldNames()
    {
        $notSupported = parent::getPTNotSupportedDimensionFieldNames();

        return array_values(array_diff($notSupported, array('ITEMID')));
    }

    /**
     * @param string $ownerobject
     *
     * @return string
     */
    function GetCustomOwnerObject(/** @noinspection PhpUnusedParameterInspection */ $ownerobject)
    {
        die("Override this function, please!");
    }

    /**
     * @param array $obj
     * @param array $docparmrec
     *
     * @return bool
     */
    protected function showVatFieldsForAvaTaxEngine($obj, $docparmrec)
    {
        $vatDataForView = $this->state == 'showview' && empty($obj['ENTRIES'][0]['SUBTOTALSENTRY']) ? false : true;
        $showVatFieldsForAvaTaxEngine = $obj['_isVatEnabled']
            && isset($docparmrec)
            && ( $docparmrec['SHOW_TOTALS'] == 'true' )
            && $vatDataForView;

        return $showVatFieldsForAvaTaxEngine;
    }

    /**
     * @return DocumentManager
     */
    function getEntityMgr()
    {
        assert($this->entityMgr instanceof DocumentManager);
        return $this->entityMgr;
    }

    /**
     * Function to identify whether the module supports lister prefernces set in user preferences
     *
     * @return bool
     */
    protected function isListerPrefAllowed()
    {
        return false;
    }

    /**
     * @param array $_params
     *
     * @return bool
     */
    public function processSaveAndPrintAction(&$_params)
    {
        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);
        $originalDocParId = $obj['DOCPARID'];
        if ($this->state == $this->kShowNewState) {
            $ok = $ok && $this->prepareObjectForCreate($obj);
            $ok = parent::innerProcessCreateAction($_params, $obj, $ok);
        } else {
            $ok = $ok && $this->prepareObjectForSave($obj);
            $ok = $this->innerProcessSaveAction($_params, $obj, $ok);
        }

        if ($ok && $this->state != $this->kErrorState && !Globals::$g->gErr->hasErrors()) {
            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowViewState;
            $sess = Session::getKey();
            $viewOp = GetOperationId($this->mod . '/lists/' . $this->mod . 'document/view');
            $listOp = GetOperationId($this->mod . '/lists/' . $this->mod . 'document');
            $url = "editor.phtml?.op=$viewOp&.do=view&.popup=1&.ydialog=1&.action=deliver&.state=deliver&.deliverymethod=pdf&.sess=" . $sess . "&.r=" . $originalDocParId . '-' . str_replace('#', '%23', $obj['DOCNO']);

            GetUserPreferences($upref, 'DOC_POSTING_OPTION');
            $upref_doc_posting = $upref['DOC_POSTING_OPTION'];
            //If document is result of conversion, after saving go to conveted from document lister
            if ($this->isListerPrefAllowed() && isset($upref_doc_posting) && $upref_doc_posting == 'F'
                && isset($obj) && $obj['CREATEDFROM'] != null) {
                $dt = Request::$r->_parentdt;
                if (isset($dt) && $dt != '' && $dt != 'null') {
                    $obj['PARENTDOCPARID'] = $dt;
                }
            }
            $obj['DOCPRINTURL'] = $url;
            $obj['LISTOP'] = $listOp;
        }
        return $ok;
    }

    /**
     * @return bool
     */
    protected function showPostAndPrintButton()
    {
        $modArray = array('so', 'po');
        return in_array($this->mod, $modArray) && ($this->state == $this->kShowNewState || $this->state == $this->kShowEditState);
    }

    /**
     * Ajax to calculate subtotals
     */
    protected function ajaxCalculateSubTotals()
    {
        $obj = $this->getData();
        $ok = true;
        include_once('POSubtotals.cls');
        unset($obj['SPENDINSIGHTCACHE']);

        $resetLineNoForAjaz = (Request::$r->resetLineNoForAjax == 'true');
        if ($resetLineNoForAjaz) {
            $obj['RESET_LINENO_FOR_AJAX_OFFSET'] = 0; //We use offset at 0 because we are calculating for all entries in $obj['ENTRIES']
        }

        $this->handleSimpleTaxSwitch($obj);

        $gManagerFactory = Globals::$g->gManagerFactory;
        $docMgr = $gManagerFactory->getManager('document');
        if($docMgr->isOverrideTaxSchedForEntryEnabled()){
            $taxScheduleIds = array_column($obj['ENTRIES'], 'TAXSCHEDULEID') ?? [];
            $taxDetailIds = $docMgr->fetchTaxDetailsFromScheduleIdArray($taxScheduleIds);

            $ok = $docMgr->prepareValuesForTaxSchedule($obj);
        }

        if($ok){
            foreach ($obj['ENTRIES'] as &$entry) {
                if(!empty($entry['TAXSCHEDULEID'])){
                    $entry['taxDetailIds'] = $taxDetailIds[$entry['TAXSCHEDULEID']] ?? [];
                }
            }
        }

        $this->getEntityMgr()->calcSubTotals($obj);

        if (!is_null($obj['ENTRIES']))
        {
            foreach ($obj['ENTRIES'] as &$entry) {
                if (isset($entry['SUBTOTALSENTRY']) && count($entry['SUBTOTALSENTRY']) > 0) {
                    $lineSubtotals = $entry['SUBTOTALSENTRY'];
                    unset($entry['SUBTOTALSENTRY']);
                    foreach ($lineSubtotals as $subtot) {
                        $entry['SUBTOTALSENTRY'][] = $subtot;
                    }
                }//for UI purpose
                elseif (empty($entry['ITEMID'])){
                    $entry['UIPRICE'] = "";
                    $entry['TAXABSVAL'] = "";
                    $entry['LINETOTAL'] = "";
                }//for UI purpose
                else{
                    $entry['PERCENTVAL'] = "";
                    $entry['TAXABSVAL'] = "";
                }
            }
        }
        if (isset($obj['PARTIALEXEMPTION']) && $obj['PARTIALEXEMPTION']['ISPARTIALEXEMPTSUPPORTED'] === 'true') {
            $this->getEntityMgr()->prepareSubtotalsWithPartialExemption($entries, $obj['SUBTOTALS']);
        }
        $newObj['ENTRIES'] = $obj['ENTRIES'];
        $newObj['SUBTOTALS'] = $obj['SUBTOTALS'];
        $subtotcount = Util::countOrZero($newObj['SUBTOTALS']);
        if ($subtotcount > 0) {
            if ($newObj['SUBTOTALS'][0]['DESCRIPTION'] == 'SUBTOTAL') {
                $newObj['SUBTOTALS'][0]['DESCRIPTION'] =  I18N::getSingleToken('IA.SUBTOTALS_SECTION_SUBTOTAL_CONSTANT_LABEL');
            }
            if ($newObj['SUBTOTALS'][$subtotcount - 1]['DESCRIPTION'] == 'TOTAL') {
                $newObj['SUBTOTALS'][$subtotcount - 1]['DESCRIPTION'] =  I18N::getSingleToken('IA.SUBTOTALS_SECTION_TOTAL_CONSTANT_LABEL');
            }
        }
        $newObj['IS_TAXCALC_SUCCESS'] = $obj['IS_TAXCALC_SUCCESS'];
        if(!$ok){
            $newObj['IS_TAXCALC_SUCCESS'] = false;
        }
        $newObj['ERRORMSG'] = str_replace(' Verify:', '', $obj['ERRORMSG']);
        echo json_encode($newObj);
    }

    /**
     * Ajax to calculate subtotals
     */
    protected function ajaxCalculateLineSubTotals()
    {
        $rowId = Request::$r->rowId;
        $unsetOverTax = Request::$r->unsetOverd;
        $resetLineNoForAjaz = (Request::$r->resetLineNoForAjax == 'true');
        $obj = $this->getData();
        if(!empty(Request::$r->taxDetailIds)){
            $obj['ENTRIES'][$rowId]['taxDetailIds'] = Request::$r->taxDetailIds ?? [];
            $obj['OVERRIDETAXSCHED'] = true;
        }
        $entry = $obj['ENTRIES'][$rowId];
        if (empty($entry)) {
            echo json_encode("");
        }
        unset($obj['SPENDINSIGHTCACHE']);
        unset($obj['ENTRIES']);
        //If VAT releated field is changed, unset overridetax flag
        if($unsetOverTax && !is_null($entry['SUBTOTALSENTRY'])) {
            foreach ($entry['SUBTOTALSENTRY'] as &$subtotal){
                $subtotal['OVERRIDETAXVALUE'] = false;
            }
        }
        if ($resetLineNoForAjaz) {
            $obj['RESET_LINENO_FOR_AJAX_OFFSET'] = $rowId; //We have offset at $rowId because we are calculating for ONLY the $entry, see line right below
        }
        $obj['ENTRIES'] = array($entry); //Note that we only use the line being edited to form the ENTRIES array so we need the offset above
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if($docMgr->isOverrideTaxSchedForEntryEnabled()){
            $taxScheduleIds = array_column($obj['ENTRIES'], 'TAXSCHEDULEID') ?? [];
            $docMgr->fetchTaxDetailsFromScheduleIdArray($taxScheduleIds);

            $docMgr->prepareValuesForTaxSchedule($obj);
        }
        $this->getEntityMgr()->calcSubTotals($obj);
        // not sure what is this doing ?
        $subTotals = $obj['ENTRIES'][0]['SUBTOTALSENTRY'];

        //Calculate partial exemption here only for Canada ITC
        if (TaxSolutionManager::isTaxDetailPartialExemptionEnabled($obj['TAXSOLUTIONID']) && isset($obj['PARTIALEXEMPTION']) &&
            $obj['PARTIALEXEMPTION']['ISPARTIALEXEMPTSUPPORTED'] === 'true' && $obj['ENTRIES'][0]['PARTIALEXEMPT'] == 'true'){
            $trx_taxClaimable = 0;
            $taxClaimable = 0;
            foreach ($obj['SUBTOTALS'] as $subs) {
                if (isset($subs['TAXDETAILS'])) {
                    foreach ($subs['TAXDETAILS'] as $subTaxDetails) {
                        if ($subTaxDetails['ISPARTIALEXEMPT'] === 'T' || $subTaxDetails['PARTIALEXEMPT'] === 'true' ||
                            (!isset($subTaxDetails['ISPARTIALEXEMPT']) && !isset($subTaxDetails['IsNonClaimable']))
                        ) {
                            $trx_taxClaimable = ibcadd($trx_taxClaimable, $subTaxDetails['TRX_ABSVAL'], 4, true);
                            $taxClaimable = ibcadd($taxClaimable, $subTaxDetails['ABSVAL'], 4, true);
                        }
                    }
                }
            }
            $obj['ENTRIES'][0]['TRX_TAXCLAIMABLE'] = $trx_taxClaimable;
            $obj['ENTRIES'][0]['TAXCLAIMABLE'] = $taxClaimable;
        }
        unset($obj['ENTRIES'][0]['SUBTOTALSENTRY']);
        foreach ($subTotals as $subtotalEntry) {
            $obj['ENTRIES'][0]['SUBTOTALSENTRY'][] = $subtotalEntry;
        }

        if ( empty($obj['ENTRIES'][0]['PERCENTVAL']) ) {
            $obj['ENTRIES'][0]['PERCENTVAL'] = '0';
        }
        if ( empty($obj['ENTRIES'][0]['TAXABSVAL']) ) {
            $obj['ENTRIES'][0]['TAXABSVAL'] = '0';
        }
        if ( empty($obj['ENTRIES'][0]['LINETOTAL']) ) {
            $obj['ENTRIES'][0]['LINETOTAL'] = $obj['ENTRIES'][0]['UIVALUE'];
        }
        //If no subtotals found, unset percentval for UI display purpose
        if( empty($obj['ENTRIES'][0]['SUBTOTALSENTRY']) ){
            $obj['ENTRIES'][0]['PERCENTVAL'] = "";
            $obj['ENTRIES'][0]['TAXABSVAL'] = "";
        }

        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if($docMgr->isCalcTaxReleaseRetainageEnabled($obj)){
            $valueField = ($this->ismcpEnabled) ? 'TRX_VALUE' : 'UIVALUE';
            $retainageValueField = ($this->ismcpEnabled) ? 'TRX_AMOUNTRETAINED' : 'AMOUNTRETAINED';
            $obj['ENTRIES'][0]['EXTENDEDPRICENETRETAINAGE'] = $obj['ENTRIES'][0][$valueField] ?? 0.00;
            if(isset($obj['ENTRIES'][0]['TRX_AMOUNTRETAINED'])){
                $obj['ENTRIES'][0]['EXTENDEDPRICENETRETAINAGE'] = ibcsub($obj['ENTRIES'][0]['EXTENDEDPRICENETRETAINAGE'], $obj['ENTRIES'][0][$retainageValueField]);
            }

            if ($obj['_DOCPAR']['DISPLAY_BASECURRENCY'] === 'true') {
                $obj['ENTRIES'][0]['EXTENDEDBASEPRICENETRETAINAGE'] = $obj['ENTRIES'][0]['UIVALUE'] ?? 0.00;
                if(isset($obj['ENTRIES'][0]['AMOUNTRETAINED'])){
                    $obj['ENTRIES'][0]['EXTENDEDBASEPRICENETRETAINAGE'] = ibcsub($obj['ENTRIES'][0]['EXTENDEDBASEPRICENETRETAINAGE'], $obj['ENTRIES'][0]['AMOUNTRETAINED']);
                }
            }
        }

        echo json_encode($obj['ENTRIES'][0]);
    }

    /**
     * Retrieve form data from JSON
     *
     * @return array
     */
    private function getData()
    {
        $jsondata = Request::$r->_data;
        if (isset($jsondata) && $jsondata != '') {
            $data = Util_DataRecordFormatter::jsonToPhp($jsondata);
        } else {
            $data = null;
        }
        return $data;
    }
    /**
     * @param array $docparmrec
     */
    protected function mediateDataAndMetadata_shippingDetails($docparmrec)
    {
        $kINVid = Globals::$g->kINVid;
        $category = $docparmrec['CATEGORY'];
        $inventoryIntalled = IsInstalled($kINVid);
        $IsShipDatesEnabled = $this->IsShipDatesEnabled();

        if( $inventoryIntalled && $IsShipDatesEnabled ) {
            $view = $this->getView();
            $view->findAndSetProperty(array('id' => 'headershippingdates'), array('hidden' => false), EditorComponentFactory::TYPE_SECTION);
            $view->findAndSetProperty(array('id' => 'lineshippingdates'), array('hidden' => false), EditorComponentFactory::TYPE_SECTION);
            if ( $this->mod == 'po'  && $category== 'Return' ){
                //This field is only available for Category type Return in PO transaction details
                $view->findAndSetProperty(array('path' => 'DATESHIPTOSUPPLIER'), array('hidden' => 'false'));
            }

        }
    }

    /**
     * @return bool
     */
    protected function IsShipDatesEnabled()
    {
        global $kINVid;
        $IsShipDatesEnabled= (GetPreferenceForProperty($kINVid, 'ENABLESHIPPINGDATES') == 'T') ? true : false;
        return $IsShipDatesEnabled;
    }

    /**
     * @param array  $fildstoset
     * @param string $module
     * @param string $pref
     */
    protected function getConstrictList($fildstoset, $module, $pref)
    {
        $view = $this->getView();
        foreach ($fildstoset as $fields)
        {
            // find section
            $sections = [];
            $view->findComponents(['id' => $fields['section']], EditorComponentFactory::TYPE_TAB, $sections);
            $section = $sections[0];
            if (is_null($section))
            {
                continue;
            }
            $matches = [];

            // find fields
            $section->findComponents(['path' => $fields['path']], $fields['type'], $matches);
            $restrictionField = $fields['restrictfield'] ?? 'CUSTVENDID';
            foreach ($matches as $property => $value)
            {
                //  this dropdown should have add/find restricted
                $PropVals = [];
                // doing contact constraint
                switch ($pref)
                {
                    case 'none':
                    default:
                        // no constriction
                        $PropVals['nonew'] = false;
                        $PropVals['nopick'] = false;
                        break;
                    case 'dropdown':
                        // constrict list
                        $PropVals['nonew'] = true;
                        $PropVals['nopick'] = true;

                        for ($index = 0; $index < count($matches); $index++)
                        {
                            $matches[$index]->params['type']['restrict'][] = [
                                'field'         => $restrictionField,
                                'pickField'     => $restrictionField,
                                'context'       => [$restrictionField],
                                'entityContext' => true,
                                'operand'       => "constrictlist:$module",
                            ];
                        }
                        break;
                }
                $section->findAndSetProperty(['path' => $fields['path']], $PropVals);
                // exit loop
                break;
            }
        }
    }

    /**
     * This function will check whether or not the document includes a reverse charge
     *
     * @param  array $subtotals the document values
     *
     * @return bool
     */
    private function isReverseChargeOn($subtotals)
    {
        //Loop through the passed in subtotals and collect the taxdetail records to query below
        $reverseChargeFlag = false;
        $taxDetailRecs = '';
        foreach ( $subtotals as $subtotal ) {
            if ($taxDetailRecs != '' && $subtotal['TAXDETAIL']) {
                $taxDetailRecs .=  ',';
            }
            $taxDetailRecs .= $subtotal['TAXDETAIL'];
        }

        //Base on the collected taxdetail records above, query to see if any records has the reverse charge flag on
        if ($taxDetailRecs != '') {
            $sql[0] = "SELECT COUNT(1) COUNT FROM taxdetail WHERE cny# = :1 AND record# IN ({$taxDetailRecs}) AND REVERSECHARGE = 'T'";
            $sql[1] = GetMyCompany();
            $result = QueryResult($sql);
            if ($result) {
                $reverseChargeFlag = ($result[0]['COUNT'] != '0');
            }
        }

        return $reverseChargeFlag;
    }

    /**
     * This function will return the taxrate from the passed in document values
     *
     * @param  array $docValues
     *
     * @return array taxrates
     */
    private function getTaxRates($docValues)
    {
        $taxRates = array();
        $mappedTaxDetails = array();

        //Loop to get the tax records in the txn lines being use so we can look in the DB below to see
        //if it's one of the TAXRATES (standard, reduced, zero, exempt) for us to bucket
        $taxDetailRecs = '';
        foreach ( (($docValues['SUBTOTALS']) ?? []) as $subtotal ) {
            if ($subtotal['TAXDETAIL']) {
                $mappedTaxDetails[$subtotal['TAXDETAIL']] = array('PERCENT' => $subtotal['PERCENTVAL']);
                if ($taxDetailRecs != '') {
                    $taxDetailRecs .=  ',';
                }
                $taxDetailRecs .= $subtotal['TAXDETAIL'];
            }
        }
        if ($taxDetailRecs == '') {
            return null; //No tax records so no need to process
        }

        //Base on the tax records we collected above, check in the DB if it's one of the TAXRATES
        $sql[0] = "SELECT RECORD#, VALUE, TAXRATE FROM taxdetail WHERE cny# = :1 AND record# IN ({$taxDetailRecs}) AND taxrate is not null";
        $sql[1] = GetMyCompany();
        $taxDetailRecs = QueryResult($sql);
        if (!$taxDetailRecs) {
            return null;  //No tax records so no need to process
        } else {
            $taxDetailMap = [];
            foreach ($taxDetailRecs as $taxDetailRec) {
                $taxDetailMap[$taxDetailRec['RECORD#']] = $taxDetailRec['TAXRATE'];
            }
        }

        //Loop to tally the total price of each TAXRATES
        foreach (($docValues['ENTRIES'] ?? []) as $entry) {
            $IncludedTaxRates = [];
            foreach ((($entry['SUBTOTALSENTRY']) ?? []) as $subtotalentry) {
                if ($subtotalentry['TAXDETAIL'] && $taxDetailMap[$subtotalentry['TAXDETAIL']]) {
                    // Add entry line source amount to a specific tax rate bucket only once
                    $taxRate = $taxDetailMap[$subtotalentry['TAXDETAIL']];
                    if (!in_array($taxRate, $IncludedTaxRates)) {
                        $mappedTaxDetails[$subtotalentry['TAXDETAIL']]['NET_TOTAL'] += $entry['TOTAL'];
                        $IncludedTaxRates[] = $taxRate;
                    }
                    $mappedTaxDetails[$subtotalentry['TAXDETAIL']]['VAT_TOTAL'] += $subtotalentry['ABSVAL'];
                    $mappedTaxDetails[$subtotalentry['TAXDETAIL']]['VAT_TRX_TOTAL'] += $subtotalentry['TRX_ABSVAL'];
                }
            }
        }

        //Loop to create the returning taxrate data obj from the info we collected above
        $taxRateMap = TaxDetailManager::getTaxRateMap($docValues['TAXSOLUTIONID']);
        foreach ($taxDetailRecs as $taxDetail) {
            $percent = $mappedTaxDetails[$taxDetail['RECORD#']]['PERCENT'];

            $netTotal = $mappedTaxDetails[$taxDetail['RECORD#']]['NET_TOTAL'];
            $vatTotal = $mappedTaxDetails[$taxDetail['RECORD#']]['VAT_TOTAL'];

            $vatTrxTotal = $mappedTaxDetails[$taxDetail['RECORD#']]['VAT_TRX_TOTAL'];

            $taxRateStr = $taxRateMap[$taxDetail['TAXRATE']];
            if ($taxRates[$taxRateStr]) {
                $netTotal += $taxRates[$taxRateStr]['NET_TOTAL'];
                $vatTotal += $taxRates[$taxRateStr]['VAT_TOTAL'];

                $vatTrxTotal += $taxRates[$taxRateStr]['VAT_TRX_TOTAL'];
            }
            $taxRates[$taxRateStr] = array(
                'PERCENT' => $percent,
                'NET_TOTAL' => $netTotal,
                'VAT_TOTAL' => $vatTotal,
                'VAT_TRX_TOTAL' => $vatTrxTotal,
            );
        }

        return $taxRates;
    }

    /**
     * @param array $sourceEntry
     * @param array $docpar
     **/
    private function computeRetainageWhenConverting(&$sourceEntry, $docpar)
    {
        if ($docpar['ENABLE_RETAINAGE'] == 'true' && !isNullOrBlank($sourceEntry['RETAINAGEPERCENTAGE'])) {
            if ($this->ismcpEnabled) {
                $value = (!empty($sourceEntry['TRX_VALUE'])) ? $sourceEntry['TRX_VALUE'] : $sourceEntry['TRX_REVISEDVALUE'];
            } else {
                $value = (!empty($sourceEntry['UIVALUE'])) ? $sourceEntry['UIVALUE'] : $sourceEntry['REVISEDUNITVALUE'];
            }
            $sourceEntry['TRX_AMOUNTRETAINED'] = ibcdiv(ibcmul($value, $sourceEntry['RETAINAGEPERCENTAGE']), 100, 2, true);
        }
    }


    /**
     * @param array $sourceEntry
     * @param bool  $discountOnExtPrice
     * @param float $exchRate
     * @param int   $precision
     *
     * @return bool
     */
    private function computeExtendedPriceWhenConverting(&$sourceEntry, $discountOnExtPrice, $exchRate, $precision)
    {

        $ok = true;
        // qty and price caluclation
        if ($this->ismcpEnabled) {
             if ($discountOnExtPrice) {
                $sourceEntry['TRX_VALUE']
                    = calcValueOnExtendedPrice(
                    $sourceEntry['UIQTY'], $sourceEntry['TRX_PRICE'],
                    $sourceEntry['MULTIPLIER'],
                    $sourceEntry['DISCOUNTPERCENT']
                );
            } else {
                $sourceEntry['TRX_VALUE'] = ibcmul(
                    $sourceEntry['UIQTY'],
                    $sourceEntry['TRX_PRICE'],
                    DEFAULT_INVPRECISION, true
                );
            }

            $precision = ($sourceEntry['ITEM_PRECISION']) ? intval($sourceEntry['ITEM_PRECISION']) : $precision;
            $sourceEntry['UIVALUE'] = ibcmul(
                $sourceEntry['TRX_VALUE'], $exchRate, DEFAULT_INVPRECISION, true
            );
            $sourceEntry['UIPRICE'] = ibcdiv(
                $sourceEntry['UIVALUE'], $sourceEntry['UIQTY'], $precision, true
            );
        } else {
            if ($discountOnExtPrice) {
                $sourceEntry['UIVALUE']
                    = calcValueOnExtendedPrice(
                    $sourceEntry['UIQTY'],
                    $sourceEntry['UIPRICE'],
                    $sourceEntry['MULTIPLIER'],
                    $sourceEntry['DISCOUNTPERCENT']
                );
            } else {
                $sourceEntry['UIVALUE'] = ibcmul(
                    $sourceEntry['UIQTY'],
                    $sourceEntry['UIPRICE'],
                    DEFAULT_INVPRECISION, true
                );
            }
        }

        return $ok;
    }

    /**
     * Determine whether or not:
     * (i) preferences are configured to honor (sub)ledger restrictions on future posting dates
     * (ii) whether this transaction actually posts to a (sub)ledger
     *
     * If so then return the associated (sub)ledger's module(s). In the case of AP/AR,
     * future date posting can fail when GL is configured to disallow it, even when
     * AP/AR configuration is set to warn, or to do nothing/ignore. So, here we always
     * include GL as a candidate to check so that the warning will be displayed in all
     * cases where at least one module's threshold is 'WARN' or 'DISALLOW'.
     *
     * @param string $updatesGL Indicates whether or not posting to subledger/ledger, and which one
     *
     * @return array The modules, if any, against which future posting dates should be validated
     */
    private function getModulesForFutureDateValidation($updatesGL)
    {
        $postToModule = '';
        $modulesToValidate = [];
        // Check if subledger/ledger future date posting restrictions should be honored
        $follow = GetPreferenceForProperty(GetModuleID($this->mod), 'FOLLOWFPRESTRICTIONS');
        if ($follow == 'T') {
            // Check if actually posting to any subledger/ledger
            switch ($updatesGL) {
                case 'A':
                    if ($this->mod == 'so') {
                        $postToModule = 'ar';
                    } else if ($this->mod == 'po') {
                        $postToModule = 'ap';
                    }
                    $modulesToValidate[] = $postToModule;
                /*
                 * Do not break; always check GL since AP/AR transaction postings honor
                 * the GL DISALLOW configuration regardless of their own configuration.
                 * We will show the warning in the OE/PO UI based on the most restrictive
                 * of the thresholds.
                 */
                case 'G':
                    $postToModule = 'gl';
                    $modulesToValidate[] = $postToModule;
                    break;
                default:
                    // Do nothing
            }
        }
        return $modulesToValidate;
    }

    /**
     * Override for editors that may allow retainage, currently SODocumentFormEditor and PODocumentFormEditor.
     * @return bool
     */
    public function getIsRetainageEnabled()
    {
        return false;
    }

    /**
     * Override for types that allow Price Conversion.
     * @return bool
     */
    public function isPriceConversionEnabled()
    {
        return false;
    }

    /**
     * Override for types that allow Conversion type on transaction.
     * @return bool
     */
    public function isOverrideTrnxConversionTypeEnabled()
    {
        return false;
    }

    /**
     * @param array $new
     * @param array $old
     */
    public function processDateFromSourceTrans(/** @noinspection PhpUnusedParameterInspection */ &$new,
        /** @noinspection PhpUnusedParameterInspection */ &$old)
    {
    }

    /**
     * @param array $obj
     */
    public function mediateDataAndMetadata_changeorder(&$obj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $entity = $this->getEntity();
        /**
         * @var DocumentManager $documentManager
         */
        $documentManager = $gManagerFactory->getManager($entity);
        if ($documentManager->isChangeOrderEnabled()) {
            $view = $this->getView();
            $entries = [];
            $enabledocchange = $obj['_DOCPAR']['ENABLEDOCCHANGE'] ?? 'No Change';
            $feedCopyMode = $obj['__feed_copymode'] ?? "";
            if ($enabledocchange == 'Enable Change' || $enabledocchange == 'Change Order') {// source and change document
                if($obj['_DOCPAR']['SHOW_TOTALS'] == 'false'){
                    $view->findAndSetProperty(array('path' => 'SUMMARY.SUBTOTAL'), array('hidden' => true));
                }
                $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entries);
                if ($entries[0]) {
                    $entriesView = $entries[0];
                    $entriesView->findAndSetProperty(array('path' => 'REVISEDUNITQTY'), array('hidden' => false));
                    $entriesView->findAndSetProperty(array('path' => 'TRX_REVISEDPRICE'), array('hidden' => false));
                    $entriesView->findAndSetProperty(array('path' => 'TRX_REVISEDVALUE'), array('hidden' => false));
                    $entriesView->findAndSetProperty(array('path' => 'DRAFTCHANGEUNITQTY'), array('hidden' => false));
                    $entriesView->findAndSetProperty(array('path' => 'DRAFTCHANGEPRICE'), array('hidden' => false));
                    $entriesView->findAndSetProperty(array('path' => 'POSTEDQTYCHANGES'), array('hidden' => false));
                    $entriesView->findAndSetProperty(array('path' => 'POSTEDCHANGEEXTPRICE'), array('hidden' => false));

                    if ($enabledocchange == 'Change Order') { // change order
                        $entriesView->findAndSetProperty(array('path' => 'RELATEDDOCNO'), array('hidden' => false));
                        $field = [];
                        $entriesView->findComponents(array('path' => 'RELATEDDOCLINENO'), EditorComponentFactory::TYPE_FIELD, $field);
                        if ($field[0]) {
                            $field[0]->setProperty('listAllowed', true);
                            $field[0]->setProperty('hidden', false);

                            if ($this->state == $this->kShowNewState) {
                                $field[0]->setProperty('readonly', false);
                            }
                        }
                    }
                }

                foreach ($obj['ENTRIES'] as &$entry) {
                    if($enabledocchange == 'Enable Change'){
                        $ccoUiQty = $entry['UIQTY'];
                        $ccoTrxValue = $entry['TRX_VALUE'];
                        $ccoUiValue = $entry['UIVALUE'];

                    }else{
                        $ccoUiQty = (isNullOrBlank($entry['RELATEDDOCUIQTY'])) ? $entry['UIQTY'] : ($entry['RELATEDDOCUIQTY']);
                        $ccoTrxValue = (isNullOrBlank($entry['RELATEDDOCTRX_VALUE'])) ? $entry['TRX_VALUE'] : ($entry['RELATEDDOCTRX_VALUE']);
                        $ccoUiValue = (isNullOrBlank($entry['RELATEDDOCUIVALUE'])) ? $entry['UIVALUE'] : ($entry['RELATEDDOCUIVALUE']);
                    }
                    if (!(Request::$r->_createchange && Request::$r->_createchange == 'New') || $feedCopyMode !=  'createChange' ) {
                        $postedQtyChanges = (isNullOrBlank($entry['REVISEDUNITQTY'])) ? $ccoUiQty : ($entry['REVISEDUNITQTY']);
                        $postedChangeextPrice = (isNullOrBlank($entry['TRX_REVISEDVALUE'])) ? $ccoTrxValue : ($entry['TRX_REVISEDVALUE']);
                        $postedChangeExtBasePrice = (isNullOrBlank($entry['REVISEDUNITVALUE'])) ? $ccoUiValue : ($entry['REVISEDUNITVALUE']);
                        $entry['POSTEDQTYCHANGES'] = ibcsub($postedQtyChanges, $ccoUiQty);
                        $entry['POSTEDCHANGEEXTPRICE'] = ibcsub($postedChangeextPrice, $ccoTrxValue);
                        $entry['POSTEDCHANGEEXTBASEPRICE'] = ibcsub($postedChangeExtBasePrice, $ccoUiValue);
                        $entry['DRAFTCHANGEBASEPRICE'] = ibcmul($entry['DRAFTCHANGEPRICE'],$entry['EXCHRATE']);
                    }
                    $entry['POSTEDQTYCHANGES'] = strval($entry['POSTEDQTYCHANGES']);
                    $entry['POSTEDCHANGEEXTPRICE'] = strval($entry['POSTEDCHANGEEXTPRICE']);
                }
                // when pass by reference &$entry used in foreach has to be unset
                unset($entry);
            }
            else{
                $view->findAndSetProperty(array('path' => 'CHANGELOGNUMBER'), array('hidden' => true));

            }

            // Source document
            if ($enabledocchange == 'Enable Change') {
                $this->mediateDataAndMetadata_SourceDoc($obj);
            }

            // Change document
            if ($enabledocchange == 'Change Order') {
                $this->mediateDataAndMetadata_ChangeDoc($obj);
            }

            // Reset fields upon copying from a doc
            if((Request::$r->_copymode == 'Copy' ) && !(Request::$r->_createchange && Request::$r->_createchange == 'New') || $feedCopyMode == 'createChange')
            {
                unset($obj['POSTEDCHANGESTOTAL']);
                unset($obj['REVISEDSUBTOTAL']);
                unset($obj['REVISEDTOTAL']);
                foreach ($obj['ENTRIES'] as &$entry) {
                    // Resetting converted fields so that on converting copied documents, the fields aren't wrongfully picked
                    $entry['PRICE_CONVERTED'] = 0;
                    $entry['QTY_CONVERTED'] = 0;
                    $entry = $documentManager->setRevisedFields($obj['HASCHANGE'],$entry);
                    if($enabledocchange != 'Change Order'){
                        $this->unsetChangeOrderFields($entry);
                        unset($entry['RELATEDDOCKEY']);
                        unset($entry['RELATEDDOCLINEKEY']);
                    }
                    unset($entry['ADDEDBYCHANGE']);

                }
                unset($obj['HASCHANGE']);
                unset($entry);
            }

            if((Request::$r->_copymode !== 'Update')) {
                // To remove change order fields for non change order document especially in copy to
                $documentManager->unsetCCOFields($obj);
            }
            // Set values for convert
            if ((Request::$r->_copymode == 'Update')) {
                $precision = $this->lookupAppPrecision();
                $discountOnExtPrice = (($obj['DOCPAR']['DISCOUNT_ON_EXTENDEDPRICE'] ?? 'false') === 'true');
                $exchRate = isNullOrBlank($obj['EXCHRATE']) ? 1 : $obj['EXCHRATE'];
                $isPrefillConversionZeroAllowed = $documentManager->isPrefillConversionZeroAllowed($this->mod);
                foreach ($obj['ENTRIES'] as &$entry) {

                    if(!$isPrefillConversionZeroAllowed){
                        $conversionType = $entry['CONVERSIONTYPE'] ?? "Quantity";
                        if($conversionType == "Quantity"){
                            if(!isNullOrBlank($entry['TRX_REVISEDPRICE'])){
                                $entry['TRX_PRICE'] = $entry['TRX_REVISEDPRICE'];
                            }
                        }else{
                            if(!isNullOrBlank($entry['TRX_REVISEDPRICE'])){
                                $priceConverted = $entry["PRICE_CONVERTED"] ?? 0;
                                $entry['TRX_PRICE'] = ibcsub($entry['TRX_REVISEDPRICE'], $priceConverted);
                            }
                        }
                    }else{
                        $entry["AMOUNTRETAINED"] = $entry['TRX_AMOUNTRETAINED'] = "0";
                    }

                    $entryExchangeRate = $entry['EXCHRATE'] ?? '';
                    $exchangeRate = ($entryExchangeRate != '' ? $entryExchangeRate : $exchRate);

                    if(!$isPrefillConversionZeroAllowed && floatval($entry['UIPRICE']) == 0 && !empty($entry['REVISEDPRICE']) &&  floatval($entry['REVISEDPRICE']) != 0 && empty($entry['PRICE_CONVERTED']) ) {
                        // if there is a revised price set for the line, we take that for conversion
                        // this is an edge case for non-MCP companies
                        $entry['UIPRICE'] = $entry['REVISEDPRICE'];
                    }
                    $this->computeExtendedPriceWhenConverting($entry, $discountOnExtPrice, $exchangeRate, $precision);

                    $entry['AMOUNTRETAINED'] = ibcmul($entry['TRX_AMOUNTRETAINED'], $exchangeRate, 2, true);
                    $this->unsetChangeOrderFields($entry);
                    unset($entry['ADDEDBYCHANGE']);
                }

                unset($obj['POSTEDCHANGESTOTAL']);
                unset($obj['REVISEDSUBTOTAL']);
                unset($obj['REVISEDTOTAL']);
                unset($obj['HASCHANGE']);
                unset($entry);
            }

            if (in_array($enabledocchange,$documentManager->getChangeOrderStates())) {
                $this->mediateDataAndMetaData_handleMultiCurrencyForChangeDocuments($obj);
            }
        }
    }

    /**
     * we need to unset the change order specific fields when
     * @param array $entry
     */
    private function unsetChangeOrderFields(array &$entry) {
        unset($entry['DRAFTCHANGEUNITQTY']);
        unset($entry['POSTEDQTYCHANGES']);
        unset($entry['REVISEDUNITQTY']);
        unset($entry['POSTEDCHANGEEXTPRICE']);
        unset($entry['POSTEDCHANGEEXTBASEPRICE']);
        unset($entry['DRAFTCHANGEPRICE']);
        unset($entry['REVISEDPRICE']);
        unset($entry['REVISEDUNITPRICE']);
        unset($entry['REVISEDUNITVALUE']);
        unset($entry['TRX_REVISEDVALUE']);
        unset($entry['TRX_REVISEDPRICE']);
        unset($entry['DRAFTCHANGEBASEPRICE']);
    }

    /**
     * @param array $obj
     */
    protected function mediateDataAndMetadata_ChangeDoc(&$obj){
        $view = $this->getView();
        $gManagerFactory = Globals::$g->gManagerFactory;
        $entity = $this->getEntity();

        /**
         * @var DocumentManager $documentManager
         */
        $documentManager = $gManagerFactory->getManager($entity);

        if(isset($obj['ENTRIES'][0]['RELATEDDOCNO']) && !isNullOrBlank($obj['ENTRIES'][0]['RELATEDDOCNO'])) {
            $obj['RELATEDDOCNO'] = $obj['ENTRIES'][0]['RELATEDDOCNO'];
        }
        $feedCopyMode = $obj['__feed_copymode'] ?? "";

        $newChangeFlag = false;
        $sourceDoc = $documentManager->Get($obj['RELATEDDOCNO']);
        if (Request::$r->_createchange && Request::$r->_createchange == 'New') { // new change under more action
            $sourceDocId = Request::$r->_r;
            $obj['DOCNO'] = '';
            $obj['RELATEDDOCNO'] = $sourceDocId;
            $obj['HASCHANGE'] = false;

            $newChangeFlag = true;
            $obj['__feed_copymode'] = 'createChange'; // setting value for Go Back in error pop up

            foreach ($obj['ENTRIES'] as &$entry) {
                    unset($entry['ADDEDBYCHANGE']);
            }

            unset($obj['REVISEDTOTAL']);
            unset($obj['REVISEDSUBTOTAL']);
            unset($obj['TRX_REVISEDTOTAL']);
            unset($obj['TRX_REVISEDSUBTOTAL']);
            unset($obj['SUMMARY']['TOTAL']);
            unset($obj['SUMMARY']['ITEMS']);
            $obj['CHANGELOGNUMBER'] = $sourceDoc['CHANGELOGNUMBER']+1;
        }
        if((Request::$r->_copymode == 'Copy' ) && !(Request::$r->_createchange && Request::$r->_createchange == 'New') || $feedCopyMode == 'createChange')
        {
            $obj['CHANGELOGNUMBER'] = $sourceDoc['CHANGELOGNUMBER']+1;
        }

        if ( $obj['TERM']['NAME'] == '' ) {
            $obj['WHENDUE'] = $sourceDoc['WHENDUE'];
        }
        // Make these fields read only and keep it same as SD for MC type
        if($this->ismcpEnabled)
        {
            $view->findAndSetProperty(array('path' => 'CURRENCY'), array('readonly' => true));
            $view->findAndSetProperty(array('path' => 'EXCHRATEDATE'), array('readonly' => true));
            $view->findAndSetProperty(array('path' => 'EXCHRATE'), array('readonly' => true));
            $view->findAndSetProperty(array('path' => 'EXCHRATETYPES.NAME'), array('readonly' => true));
        }
        foreach ($obj['ENTRIES'] as $key => &$entry) {
            if ($entry['_isNewLine']) {
                continue;
            }
            [$itemkey] = explode("--", $entry['ITEMID']);
            if($this->getFromErrorWarningFlag() && !isNullOrBlank($entry['RELATEDDOCLINENO'])) {
                [$lineNo] = explode("--", $entry['RELATEDDOCLINENO']);
            }else{
                $lineNo = ($entry['RELATEDDOCLINENUM'] ?? $this->getRelatedDocLineNum($entry['RELATEDDOCLINEKEY'], $sourceDoc['ENTRIES'])) + 1;
            }
            if ($newChangeFlag) {
                $lineNo = $entry['LINE_NO'] + 1; // need to override for new change under more action
                $entry['RELATEDDOCKEY'] = $sourceDoc['RECORDNO'];
                $entry['RELATEDDOCLINEKEY'] = $sourceDoc['ENTRIES'][$key]['RECORDNO'];

                unset($entry['REVISEDVALUE']);
                unset($entry['REVISEDVALUE']);

                if ($entry['CONVERSIONTYPE'] === 'Price') {
                    if($entry['UIQTY'] == 0){
                        $entry['UIQTY'] = 1;
                    }
                    //price field should be cleared
                    unset($entry['UIPRICE']);
                    unset($entry['TRX_PRICE']);
                    unset($entry['TRX_VALUE']);
                } else {
                    //qty field should be cleared
                    unset($entry['UIQTY']);
                    $entry['UIPRICE'] = $sourceDoc['ENTRIES'][$key]['REVISEDUNITPRICE'];
                    $entry['TRX_PRICE'] = $sourceDoc['ENTRIES'][$key]['TRX_REVISEDPRICE'];
                }
                unset($entry['ADDEDBYCHANGE']);
            }elseif(Request::$r->_copymode == 'Copy') {
                if ($sourceDoc['ENABLEDOCCHANGE'] != 'No Change') {
                    //In Change Doc case we get the line number from RELATEDDOCLINE NUM OR KEY.So skip getting from Entry line number.
                    if($sourceDoc['ENABLEDOCCHANGE'] != 'Enable Change'){
                        $lineNo = $entry['LINE_NO'] + 1;
                    }
                }
            }
            $entry['RELATEDDOCLINENO'] = "$lineNo--$itemkey";
            if($obj['STATE'] !== 'Closed' && $entry['RELATEDDOCLINEKEY'] == ''){
                $entry['RELATEDDOCLINENO'] = '';
            }
        }

        if($this->getFromErrorWarningFlag()){
            foreach ($obj['ENTRIES'] as &$entry) {
                if(isNullOrBlank($entry['RELATEDDOCLINENO'])) {
                    continue;
                }
                [ $lineNo ] = explode("--", $entry['RELATEDDOCLINENO']);
                $srcKey = (int)$lineNo - 1;
                if ($srcKey < 0) {
                    continue;
                }
                if ( isset($sourceDoc['ENTRIES'][$srcKey]) ) {
                    $entry['POSTEDQTYCHANGES'] = ibcsub($sourceDoc['ENTRIES'][$srcKey]['REVISEDUNITQTY'],
                                                        $sourceDoc['ENTRIES'][$srcKey]['UIQTY']);
                    $entry['POSTEDCHANGEEXTPRICE'] = ibcsub($sourceDoc['ENTRIES'][$srcKey]['TRX_REVISEDVALUE'],
                                                            $sourceDoc['ENTRIES'][$srcKey]['TRX_VALUE']);
                    $entry['POSTEDCHANGEEXTBASEPRICE'] = ibcsub($sourceDoc['ENTRIES'][$srcKey]['REVISEDUNITVALUE'],
                                                                $sourceDoc['ENTRIES'][$srcKey]['UIVALUE']);
                }
            }
        }

        unset($entry);
        if ($this->state == $this->kShowViewState) {
            if(empty($sourceDoc)) {
                $sourceDoc = null;
            }
            $obj = $documentManager->getRelatedDocumentData($obj, $sourceDoc);
            $obj = $documentManager->getOriginalDocumentData($obj, $sourceDoc);
        }

        if($this->state == $this->kShowEditState){
            $view->findAndSetProperty(array('path' => 'RELATEDDOCNO'), array('readonly' => true));
        }

        if ( ! IsRoot() ) {
            $matches = array();
            $view->findComponents(array('path' => 'RELATEDDOCNO'), EditorComponentFactory::TYPE_FIELD, $matches);

            foreach ( $matches as &$match ) {
                $type = $match->getProperty('type');
                $type['restrict'][] = array(
                    'value' => array(GetContextLocation()),
                    'pickField' => 'MEGAENTITYKEY',
                );
                $match->setProperty('type', $type);
            }
        }

    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.LAST_CHANGE_LOG_NUMBER';
        $this->textTokens[] = 'IA.TAXABILITY_OF_LINE_ITEMS_COMPUTED_AGAIN';
        $this->textTokens[] = 'IA.TRANSACTION_PRICE';
        $this->textTokens[] = 'IA.EXTENDED_PRICE';
        $this->textTokens[] = 'IA.TAX';
        $this->textTokens[] = 'IA.TRANSACTION_GROSS_AMOUNT';
        $this->textTokens[] = 'IA.BASE_PRICE';
        $this->textTokens[] = 'IA.EXTENDED_BASE_PRICE';
        $this->textTokens[] = 'IA.BASE_TAX';
        $this->textTokens[] = 'IA.GROSS_BASE_AMOUNT';
        $this->textTokens[] = 'IA.BASE_VALUE';
        $this->textTokens[] = 'IA.BASE_TOTAL';
        $this->textTokens[] = 'IA.CREATED_DATE';
        $this->textTokens[] = 'IA.WARNING_DOCUMENT_NUMBER_ALREADY_USED';
        $this->textTokens[] = 'IA.WARNING_NO_DEFAULT_FAIR_VALUE_PRICE_LIST_DEFINED';
        $this->textTokens[] = 'IA.PLEASE_SELECT_AN_ITEM_FIRST';
        $this->textTokens[] = 'IA.PLEASE_SELECT_AN_ITEM_AND_TRY_AGAIN';
        $this->textTokens[] = 'IA.PLEASE_SELECT_AN_ITEM_FIRST_AND_TRY_AGAIN';
        $this->textTokens[] = 'IA.YOU_MUST_PICK_FAIR_VALUE_PRICE_LIST_FIRST';
        $this->textTokens[] = 'IA.SELECT_LOCATION_FOR_THIS_LINE';
        $this->textTokens[] = 'IA.PLEASE_SELECT_A_WAREHOUSE_FIRST';
        $this->textTokens[] = 'IA.NO_MATCH_FOR_ITEM_FOUND';
        $this->textTokens[] = 'IA.COULD_NOT_FIND_THE_UOM_INFO';
        $this->textTokens[] = 'IA.NO_COMPONENT_OF_KIT_IS_NOT_SET_FOR_TRACKING';
        $this->textTokens[] = 'IA.AN_INVOICE_IN_AR_WITH_SAME_NUMBER_ALREADY_EXISTS';
        $this->textTokens[] = 'IA.AN_INVOICE_IN_AR_WITH_SAME_NUMBER_ALREADY_EXISTS_DO_YOU_WANT_TO_USE_SAME_NUMBER';
        $this->textTokens[] = 'IA.A_BILL_IN_AP_WITH_SAME_REF_NUMER_ALREADY_EXISTS';
        $this->textTokens[] = 'IA.A_BILL_IN_AP_WITH_SAME_REF_NUMER_ALREADY_EXISTS_DO_YOU_WANT_TO_USE_SAME_NUMBER';
        $this->textTokens[] = 'IA.UOM_OF_ITEM_DONT_MATCH_ITEM_CROSS_REFERENCE';
        $this->textTokens[] = 'IA.WARNING_END_DATE_LESS_THAN_START_DATE';
        $this->textTokens[] = 'IA.BROWSER_DOESNT_SUPPORT_THIS_FEATURE';
        $this->textTokens[] = 'IA.ENTER_VALID_NUMBER_IN_FIELD_FOR_ITEM_AND_TRY_AGAIN';
        $this->textTokens[] = 'IA.NO_TRANSACTIONS_FOUND';
        $this->textTokens[] = 'IA.ACTION_SET_EXISTING_AND_SUBSEQUENT_LINE_ENTRIES_TO_DEFAULT_VALUES_YOU_SELECTED';
        $this->textTokens[] = 'IA.PICK_VALID_ENTRY_IN_HIGHLIGHTED_FIELDS';
        $this->textTokens[] = 'IA.ITEM_IS_NOT_ENABLED_FOR_TRACKING_INFO';
        $this->textTokens[] = 'IA.ITEM_NOT_FOUND';
        $this->textTokens[] = 'IA.YOU_ENTER_QTY_BUT_NO_TRACKING_ON_ROW';
        $this->textTokens[] = 'IA.NOTHING_TO_VIEW';
        $this->textTokens[] = 'IA.SOMETHING_WENT_WRONG_TRY_AGAIN';
        $this->textTokens[] = 'IA.INVALID_QTY_VALUE';
        $this->textTokens[] = 'IA.NOT_ENOUGH_QTY_TO_FULFILL_ITEM';
        $this->textTokens[] = 'IA.DOC_IS_IN_FULFILLMENT_IN_AT_LEAST_TWO_DIFFERENT_STATES';
        $this->textTokens[] = 'IA.PRESSING_REPEAT_WILL_TAKE_YOU_TO_RECURRING_TRANSACTION_SCREEN';
        $this->textTokens[] = 'IA.SCHEDULE_CONFIGURED_FOR_DAILY_POSTING_AND_MAY_TAKE_SOME_TIME';
        $this->textTokens[] = 'IA.ARE_YOU_SURE_YOU_WANT_TO_RECALCULATE_THE_FIELDS';
        $this->textTokens[] = 'IA.ARE_YOU_SURE_WANT_TO_RECALCULATED_AMOUNTS_FOR_ALL_LINE_ITEMS';
        $this->textTokens[] = 'IA.CHANGED_TRANSACTION_CURRENCY_WILL_CAUSE_LINE_ITEM_AMOUNTS_TO_RECALCULATE';
        $this->textTokens[] = 'IA.CHANGED_TRANSACTION_CURRENCY_WILL_CAUSE_EXISTING_LINE_ITEM_AMOUNTS_TO_RECALCULATE';
        $this->textTokens[] = 'IA.DEFINITION';
        $this->textTokens[] = 'IA.RETAINAGE_RELEASE';
        $this->textTokens[] = 'IA.DIRECT_GL';
        $this->textTokens[] = 'IA.PRIOR_PERIOD_COGS_ADJUSTMENT_POSTING';
        $this->textTokens[] = 'IA.INVENTORY_POSTING';
        $this->textTokens[] = 'IA.ADDITIONAL_GL_POSTING';
        $this->textTokens[] = 'IA.COGS_POSTING';
        $this->textTokens[] = 'IA.DIRECT_GL_POSTING';
        $this->textTokens[] = 'IA.ITEM_ONLY_QTY_AVAILABLE_IN_WAREHOUSE_WARNING';
        $this->textTokens[] = 'IA.ON_ORDER_EQUALS_QTY';
        $this->textTokens[] = 'IA.ON_HAND_EQUALS_QTY';
        $this->textTokens[] = 'IA.ON_HOLD_EQUALS_QTY';
        $this->textTokens[] = 'IA.AVAILABLE_EQUALS_QTY';
        $this->textTokens[] = 'IA.UNCOMMITTED_EQUALS_QTY';
        $this->textTokens[] = 'IA.MULTIPLE_SOURCE_TRANSACTIONS';
        $this->textTokens[] = 'IA.NEW';
        $this->textTokens[] = 'IA.ENTER_NON_NEGATIVE_NUMBER_IN_FIELD_FOR_ITEM_AND_TRY_AGAIN';
        $this->textTokens[] = 'IA.COSTTYPE_SKIPLIST_MESSAGE';
        $this->textTokens[] = 'IA.MARK_RETAINAGE_RELEASE_LINE';
        $this->textTokens[] = 'IA.RETAINAGE_RELEASE_LINE_MARKED';
        $this->textTokens[] = 'IA.SUBTOTALS_SECTION_SUBTOTAL_CONSTANT_LABEL';
        $this->textTokens[] = 'IA.SUBTOTALS_SECTION_TOTAL_CONSTANT_LABEL';
        $this->textTokens[] = 'IA.TEMPLATE';
        $this->textTokens[] = 'IA.TRANSACTIONS';
        $this->textTokens[] = 'IA.TRANSACTION_TAX';
        $this->textTokens[] = 'IA.APPROVE_PURCHASING_TRANSACTION';
        $this->textTokens[] = 'IA.DECLINE_PURCHASING_TRANSACTION';
        $this->textTokens[] = 'IA.PARTIAL_EXEMPT_NOT_SUPPORTED_WITH_TAX_CAPTURE';
        return parent::getFormTokens();
    }

    /**
     * @param array $obj
     * @return bool
     */
    protected function mediateDataAndMetadata_SourceDoc(&$obj){
        $view = $this->getView();
        $gManagerFactory = Globals::$g->gManagerFactory;
        $entity = $this->getEntity();

        /**
         * @var DocumentManager $documentManager
         */
        $documentManager = $gManagerFactory->getManager($entity);
        if(!in_array($this->mod, $documentManager->getAllowedModules())) {
            return true;
        }

        $view->findAndSetProperty(array('path' => 'POSTEDCHANGESTOTAL'), array('hidden' => false));
        $view->findAndSetProperty(array('path' => 'REVISEDSUBTOTAL'), array('hidden' => false));
        $view->findAndSetProperty(array('path' => 'REVISEDTOTAL'), array('hidden' => false));
        $view->findAndSetProperty(array('path' => 'HASCHANGE'), array('hidden' => false));
        $view->findAndSetProperty(array('path' => 'CHANGELOGNUMBER'), array('hidden' => false));
        $view->findAndSetProperty(array('path' => 'CHANGELOGNUMBER'), array('fullname' => 'IA.LAST_CHANGE_LOG_NUMBER'));


        $obj['CHANGELOGNUMBER'] = $obj['CHANGELOGNUMBER']??'0';
        
        if ($this->state == $this->kShowViewState) {
            if(empty($obj["DRAFTDOCS"]) && empty($obj["POSTEDDOCS"])){
                $obj = $documentManager->getRelatedDocumentData($obj);
            }
            $obj = $documentManager->getOriginalDocumentData($obj);
        }

        // to recalculate the source document header value if it in entity level
        if(!IsRoot()){
            $total = '0';
            $revisedTotal = '0';
            foreach($obj['ENTRIES'] as $entry) {
                if((isset($obj['MELOCATIONKEY']) && !empty($obj['MELOCATIONKEY']) && $obj['MELOCATIONKEY'] == GetContextLocation())
                    || $entry['LOCATIONID'] == GetContextLocation() || $entry['LOCATIONID'] == GetContextLocation(true)){
                    $total = ibcadd($total, $entry['TOTAL'] ?? '0', DEFAULT_INVPRECISION, true);
                    $revisedTotal = ibcadd($revisedTotal, $entry['REVISEDVALUE'] ?? '0', DEFAULT_INVPRECISION, true);
                }
            }
            $postedChangesTotal = ($obj['HASCHANGE'] == "true") ? $revisedTotal :$total ;
            $obj['POSTEDCHANGESTOTAL'] = ibcsub($postedChangesTotal, $total);
            $obj['REVISEDSUBTOTAL'] = $revisedTotal;
            $obj['REVISEDTOTAL'] = $revisedTotal;
        }
        return true;
    }

    /**
     * @param int $relatedDocLineKey
     * @param array $srcEntries
     *
     * @return int
     */
    private function getRelatedDocLineNum($relatedDocLineKey, $srcEntries){
        if (!empty($srcEntries)) {
            $key = array_search($relatedDocLineKey, array_column($srcEntries, 'RECORDNO'));
            if($key !== false){
                return $srcEntries[$key]['LINE_NO'];
            }
        }
        return 0;
    }

    /**
     * @param array $viewData
     *
     * @return bool
     */
    private function hideRepeatForChangeOrder(array $viewData){
        $enableChangeOrder = $viewData['_DOCPAR']['ENABLEDOCCHANGE'] ?? "No Change";
        if($enableChangeOrder == 'Enable Change' || $enableChangeOrder == 'Change Order'){
            return true;
        }
        return false;
    }

    /**
     *
     * @param array $viewData
     *
     * @return bool
     */
    private function hideRepeatForPCB($viewData){
        $enableChangeOrder = isNullOrBlank($viewData['_DOCPAR']['ENABLECONTRACTBILLING']) ? "false" : $viewData['_DOCPAR']['ENABLECONTRACTBILLING'];
        return ($enableChangeOrder == "true");
    }

    /**
     * When multi-tax user selects Simple Tax as tax solution, set tax engine to simple tax
     * @param array $obj
     */
    private function handleSimpleTaxSwitch(&$obj)
    {
        if ($obj['ISSIMPLETAXSWITCH'] == true) {
            if (!empty($obj['TAXSOLUTIONID'])) {
                $obj['_taxEngine'] = GetTaxEngine($this->mod, $obj['TAXSOLUTIONID']);
            }
            if (!TaxSolutionManager::isSimpleTaxTaxMethod($obj['_taxEngine'])) {
                $obj['ISSIMPLETAXSWITCH'] = false;
            }
        }
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

        switch ( $cmd ) {

            case 'getPostingInfo':
                $this->ajaxGLPostingDetails();
                break;

            case 'getTaxDetails':
                $this->ajaxgetTaxDetails();
                break;

            case 'getTaxDetailsForTaxSchedule':
                $this->ajaxGetTaxDetailsForTaxSchedule();
                break;
            default:
                $ok = parent::runAjax($cmd);
                break;
        }

        return $ok;
    }

    /**
     *
     * Get the GL posting details for the transaction
     *
     * @return null
     */
    protected function ajaxGLPostingDetails()
    {
        $obj['RECORDNO'] = Request::$r->{'dochdrkey'};
        $obj['PRRECORDKEY']  = Request::$r->{'prrecordkey'};
        $obj = $this->getPostingInfo($obj);
        echo json_encode([ 'GL_BATCHES_LIST' => $obj['GL_BATCHES_LIST'] ,
                           'GL_BATCHES_IET_LIST' => $obj['GL_BATCHES_IET_LIST'] ,
                           'PR_RECORDS_LIST' => $obj['PR_RECORDS_LIST'] ,
                           'RELEASED_RECORDS_LIST' => $obj['RELEASED_RECORDS_LIST']]);
        return null;
    }

    /**
     * Get the taxdetails filtered by module and tax solution
     *
     */
    protected function ajaxgetTaxDetails()
    {
        $taxSolutionId = empty($taxSolutionId) ? Request::$r->taxSolutionId : $taxSolutionId;
        $txnDate = Request::$r->txnDate;
        $taxType = $this->mod == "po" ? 'P' : 'S';

        $taxSolnMngr = Globals::$g->gManagerFactory->getManager('taxsolution');
        $taxSolnResult = $taxSolnMngr->get($taxSolutionId);
        $taxDetailRes = SubLedgerTxnManager::getTaxDetails(null, $taxType, $txnDate, $taxSolnResult['RECORDNO']);
        $taxDetailIds = array_column($taxDetailRes, 'DETAILID');

        echo json_encode($taxDetailIds);
    }

    /**
     * Method which determines whether the call is from Error or Warning page
     *
     * @return bool
     */
    protected function getFromErrorWarningFlag()
    {
        $errorRecoveryTime = Request::$r->_errorTimeStamp;
        return (isset($errorRecoveryTime) && $errorRecoveryTime !== '') || HasWarnings() ? true : false;
    }

    /**
     * To check any additional information fields are enabled
     * @return bool
     */
    protected function checkAddInfoEnabled(){
        $creinstalled = CRESetupManager::isCREInstalled();
        $docpar = $this->GetBaseDocPar();
        $addInfo = $docpar['ENABLEADDINFOSCOPE'] == 'true' || $docpar['ENABLEADDINFOSCHEDULE'] == 'true' || $docpar['ENABLEADDINFOINTERNALREF'] == 'true' ||
            $docpar['ENABLEADDINFOEXTERNALREF'] == 'true' ||$docpar['ENABLEADDINFOBOND'] == 'true';

        return $creinstalled && ($addInfo ?? false);

    }

    /**
     * To set additional information fields editable in converted, in progress and partial converted stated documents
     * @param bool $isDocEditable
     */
    protected function setAddInfoFieldEditableForConvertedDoc($isDocEditable){
        $creinstalled = CRESetupManager::isCREInstalled();
        if($creinstalled && ($this->mod == "po" || $this->mod == "so")){ // checking for cre and mod for purchase and order entry
            if ( $this->do == 'edit' && !$isDocEditable ) {
                $this->canEditConvertDoc = true; // setting var canEditConvertDoc to true,so that in isDocumentInEditableState it allows converted doc to edit.
            }
        }
    }


    /**
     * To get partial exempt percent value
     *
     * @param array $obj
     *
     * @return float|int
     */
    protected function getPartialExemptPercentValue($obj)
    {
        $partExemption = $obj['PARTIALEXEMPTION'];
        $partExemptDetails = $partExemption['TAXPARTIALEXEMPTDETAILS'] ?? [];
        if (!empty($obj['WHENCREATED'])) {
            $effectiveDateDetails = TaxScheduleManager::findEffectiveTaxDetails($partExemptDetails, $obj['WHENCREATED']);
            return $effectiveDateDetails[0]['PERCENTVALUE'] ?? 100;
        }
        return 0;
    }

    /**
     * ajax to get tax exemption percentage
     */
    public function ajaxGetTaxExemptPercent()
    {
        $txn = $this->getData();
        $txn['WHENCREATED'] = Request::$r->transactionDate;
        $txn['PARTIALEXEMPTION'] = Request::$r->partialExempt;
        $resultPercent['PARTIALEXEMPT_PERCENT'] = $this->getPartialExemptPercentValue($txn);
        echo json_encode($resultPercent);
    }

    /**
     * Override ProcessEditNewAction()
     *
     * @param array &$_params
     *
     * @return bool
     */
    protected function ProcessEditNewAction(&$_params)
    {
        // remember the original entity
        $originalEntity = $_params['entity'];

        // give opportunity for the derived CopyToAdapter to change the entity (base class CopyToAdapter does not change it)
        $this->copyToAdapter->changeEntity($_params);

        // call parent function
        $retVal = parent::ProcessEditNewAction($_params);

        // restore original entity (whether changed or not)
        $_params['entity'] = $originalEntity;

        return $retVal;
    }

    /**
     * @param array $obj
     *
     * @return void
     * @throws Exception
     */
    protected function mediateDataAndMetadata_reverseConversion(&$obj){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $entity = $this->getEntity();
        /**
         * @var DocumentManager $documentManager
         */
        $documentManager = $gManagerFactory->getManager($entity);
        $view = $this->getView();
        $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $entries);
        if($entries[0]){
            $entriesView = $entries[0];

            $convertByline = false;

            if(!empty(Request::$r->_salecon) && Request::$r->_salecon == 'T'){
                $convertByline = true;
            }

            $renewalsEnabled = false;

            if(!empty($obj["_DOCPAR"]["ENABLERENEWALS"]) && $obj["_DOCPAR"]["ENABLERENEWALS"] != 'None'){
                $renewalsEnabled = true;
            }

            if(Request::$r->_copymode == 'Update' && !empty($obj['ENTRIES'][0]['SOURCE_DOCKEY'])){
                $params = [
                    'selects' => ['documentparams.ENABLERENEWALS'],
                    'columnaliases' => ['ENABLERENEWALS'],
                    'filters' => [[['RECORDNO', '=', $obj['ENTRIES'][0]['SOURCE_DOCKEY']]]]
                ];
                $result = $documentManager->GetList($params);
                if(!empty($result[0]["ENABLERENEWALS"]) && $result[0]["ENABLERENEWALS"] != 'F'){
                    $renewalsEnabled = true;
                }
            }

            $rcFieldProperty['hidden'] = true;
            $rcFieldProperty['disabled'] = true;
            if (CRESetupManager::isCREInstalled()) {
                if($documentManager->convertedDocExist($obj['RECORDNO'])) {
                    $entriesView->findAndSetProperty([ 'path' => 'REVERSEPRICECONVERTED' ], [ 'hidden' => false ]);
                    $entriesView->findAndSetProperty([ 'path' => 'REVERSEQTYCONVERTED' ], [ 'hidden' => false ]);
                    $entriesView->findAndSetProperty([ 'path' => 'STDPRICECONVERTED' ], [ 'hidden' => false ]);
                    $entriesView->findAndSetProperty([ 'path' => 'STDQTYCONVERTED' ], [ 'hidden' => false ]);
                }
                $entriesView->findAndSetProperty(array('path' => 'SOURCEDOCID'), array('hidden' => false));
                $entriesView->findAndSetProperty(array('path' => 'SOURCEDOCLINEID'), array('hidden' => false));
                if (CRESetupManager::isMultiDocumentConversionEnabled() && in_array($obj['STATE'], [DocumentManager::CONVERTED_STATE, DocumentManager::PARTIALLY_CONVERTED_STATE])) {
                    $entriesView->findAndSetProperty(array('path' => 'SOURCEDOCID'), array('disabled' => true));
                    $entriesView->findAndSetProperty(array('path' => 'SOURCEDOCLINEID'), array('disabled' => true));
                }
                $rcFieldProperty['hidden'] = false;
            }
            if($documentManager->isReverseConversionAllowed() && !$renewalsEnabled && !$convertByline){
                $this->isReverseConversionAllowed = true;
                if(Request::$r->_copymode != 'Update' && empty($obj["CREATEDFROM"]) && !in_array($obj["STATE"], [DocumentManager::PARTIALLY_CONVERTED_STATE, DocumentManager::CONVERTED_STATE, DocumentManager::INPROGRESS_STATE])){
                    $rcFieldProperty['disabled'] = true;
                }else{
                    $rcFieldProperty['disabled'] = false;
                }
            }
            $entriesView->findAndSetProperty(array('path' => 'REVERSECONVERSION'), $rcFieldProperty);

            $entriesView->findAndSetProperty(array('path' => 'SOURCEDOCID'), array('hidden' => false));
            $entriesView->findAndSetProperty(array('path' => 'SOURCEDOCLINEID'), array('hidden' => false));
        }

        if(Request::$r->_copymode == 'Copy' ){
            foreach($obj['ENTRIES'] as $key => $entry){
                $this->resetReverseConversionFields($obj['ENTRIES'][$key]);
            }
        }

        if(!$this->getFromErrorWarningFlag() && Request::$r->_copymode == 'Update'){
            foreach($obj['ENTRIES'] as $key => $entry){
                $this->resetReverseConversionFields($obj['ENTRIES'][$key]);
            }
        }
    }

    /**
     * @param $entry
     *
     * @return void
     */
    protected function resetReverseConversionFields(&$entry){
        unset($entry['STDQTYCONVERTED']);
        unset($entry['STDPRICECONVERTED']);
        unset($entry['REVERSEQTYCONVERTED']);
        unset($entry['REVERSEPRICECONVERTED']);
        unset($entry["REVERSECONVERSION"]);
    }

    /**
     * Setting SourceDoc related fields
     * @param $entry
     *
     * @return void
     */
    protected function setSourceDocDetails(&$entry){
        $entry['SOURCEDOCID'] = $entry['DOCHDRID'];
        list($itemId) = explode('--', $entry['ITEMID']);
        $entry['SOURCEDOCLINEID'] = (int)$entry['LINE_NO'] + 1 .'--'. $itemId;
    }

    /**
     *
     * @param array $obj
     *
     * @return array
     */
    protected function mediateDataAndMetadata_ExtendedNetRetainage(array $obj) : array
    {
        $valueField = ($this->ismcpEnabled) ? 'TRX_VALUE' : 'UIVALUE';
        $retainageValueField = ($this->ismcpEnabled) ? 'TRX_AMOUNTRETAINED' : 'AMOUNTRETAINED';
        foreach($obj['ENTRIES'] as $index => $entry){
            if(!empty($entry['ITEMID'])){
                $obj['ENTRIES'][$index]['EXTENDEDPRICENETRETAINAGE'] = $obj['ENTRIES'][$index][$valueField] ?? 0.00;
                if(isset($obj['ENTRIES'][$index]['TRX_AMOUNTRETAINED'])){
                    $obj['ENTRIES'][$index]['EXTENDEDPRICENETRETAINAGE'] = ibcsub($obj['ENTRIES'][$index]['EXTENDEDPRICENETRETAINAGE'], $obj['ENTRIES'][$index][$retainageValueField]);
                }

                if ($obj['_DOCPAR']['DISPLAY_BASECURRENCY'] === 'true') {
                    $obj['ENTRIES'][$index]['EXTENDEDBASEPRICENETRETAINAGE'] = $obj['ENTRIES'][$index]['UIVALUE'] ?? 0.00;
                    if(isset($obj['ENTRIES'][$index]['AMOUNTRETAINED'])){
                        $obj['ENTRIES'][$index]['EXTENDEDBASEPRICENETRETAINAGE'] = ibcsub($obj['ENTRIES'][$index]['EXTENDEDBASEPRICENETRETAINAGE'], $obj['ENTRIES'][$index]['AMOUNTRETAINED']);
                    }
                }
            }
        }

        return $obj;
    }

    /**
     * Added the method to handle the historical data and
     * we need to remove the method in next financial year 2024 or 2025,
     * @param string|mixed $xml
     *
     * @return void
     */
    private function recalculatePcbData(&$xml){
        if($this->getIsRetainageEnabled()){

            $obj = simplexml_load_string($xml);

            if(isset($obj->REC)){
                $rec = get_object_vars($obj->REC);
                $revisedContractAmt  = $rec['REVISEDCONTRACTAMT'] ?? 0;
                $totalCompletedToDate  = $rec['TOTALCOMPLETEDTODATE'] ?? 0;
                $retainageBalance  = $rec['RETAINAGEBALANCE'] ?? 0;
                $totalRetainage  = $rec["TOTALRETAINAGE"] ?? 0;
                /** @noinspection PhpUnusedLocalVariableInspection  */
                $BALANCETOFINISH = ibcadd(ibcsub($revisedContractAmt, $totalCompletedToDate), $retainageBalance);
                /** @noinspection PhpUnusedLocalVariableInspection  */
                $TOTALEARNEDLESSRET = ibcsub($totalCompletedToDate, $totalRetainage);
                $fieldList = ['BALANCETOFINISH', 'TOTALEARNEDLESSRET'];
                foreach ($fieldList as $field){
                    if(isset($obj->REC->$field)){
                        $obj->REC->$field = ${$field};
                    }
                }
                $newXml = $obj->saveXML();
                $newXml = (string)isl_preg_replace("/^\<\?xml.*?\?\>\n/", "", $newXml);
                if($newXml !== false){
                    $xml = $newXml;
                }
            }
        }
    }

    /**
     * @param array $new
     * @param array $old
     * @param array $docpar
     * @param array $itemsArr
     * @param EntityManager $itemMgr
     * @param EntityManager $srcEntityMgr
     * @param string $recalledID
     */
    protected function prepareValueFromSourceTrans(&$new, &$old, $docpar, $itemsArr, $itemMgr, $srcEntityMgr, $recalledID)
    {
        //Need to unset PRINVBATCHKEY, ADDGLBATCHKEY and INVBATCHKEY.
        unset($new['PRINVBATCHKEY']);
        unset($new['ADDGLBATCHKEY']);
        unset($new['INVBATCHKEY']);
        unset($new['STATE']);
        unset($new['ENTRIES']);

        //$uomInfoCache = $itemMgr->GetUOMPrecissionInfo($itemsArr);
        $itemidAsKey = true;
        $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey);

        $this->handleMCPValues($new);

        // get the back order line items data if any
        // the source document can be converted again if it is in pending state even though there is a back order.
        // in case of back orders the qty_converted is never updated in case of back orders.
        // when converting the source and if there is a back order get the back orders lines to calculate the quantity below.
        $backOrders = $srcEntityMgr->DoQuery('QRY_DOCUMENT_GET_BACKORDER_IDS', array($old['RECORDNO']));
        if (!empty($backOrders)) {
            $this->processBackOrder($old, $backOrders[0]);
        }

        // $state = ($isNewDocument) ?  CREATE_ACTION : EDIT_ACTION;
        $trackingHandler = new TrackingHandler(array('ACTION' => CREATE_ACTION));
        $availableTrackingDetails = $trackingHandler->GetAvailableTrackingDetails($old['RECORDNO']);
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        $isFullyConvertedLineAllowed = $docMgr->isIncludeFullyConvertedLineAllowed($this->mod);
        $isPrefillConversionZeroAllowed = $docMgr->isPrefillConversionZeroAllowed($this->mod);
        $precision = $this->lookupAppPrecision();
        foreach ((($old['ENTRIES']) ?? []) as $oldEntry) {
            $quantity = $oldEntry['QUANTITY'];
            if (!isNullOrBlank($oldEntry['TRX_PRICE']) && $oldEntry['TRX_PRICE'] !== '0') {
                $price = $oldEntry['TRX_PRICE'];
            } else if (!isNullOrBlank($oldEntry['UIPRICE'])) {
                $price = $oldEntry['UIPRICE'];
            } else {
                $price = $oldEntry['PRICE'];
            }

            if (($oldEntry['TRX_PRICE'] === '0') && !isNullOrBlank($oldEntry['TRX_REVISEDPRICE'])) {
                $oldEntry['TRX_PRICE'] = $oldEntry['TRX_REVISEDPRICE'];
            }

            if ($docMgr->isChangeOrderEnabled()) {
                //if changeorder is enabled, we try to use to revisedqty if it exists
                $revisedQuantity = $oldEntry['REVISEDQTY'] ?? "";
                if ($revisedQuantity !== "") {
                    $quantity = $revisedQuantity;
                }

                if ($oldEntry['CONVERSIONTYPE'] === 'Price') {
                    //if changeorder is enabled, we try to use to revisedprice if it exists
                    $revisedPrice = $oldEntry['REVISEDPRICE'] ?? "";
                    $trxRevisedPrice = $oldEntry['TRX_REVISEDPRICE'] ?? "";
                    if ($revisedPrice !== "") {
                        $price = $revisedPrice;
                    }

                    if ($trxRevisedPrice !== "") {
                        $trxPrice = $trxRevisedPrice;
                    }
                }
            }

            // pick only those entries which are not fully converted
            if (($oldEntry['CONVERSIONTYPE'] === 'Price' && $price != $oldEntry['PRICE_CONVERTED']) ||
                ($quantity != $oldEntry['QTY_CONVERTED']) || $isFullyConvertedLineAllowed) {
                $itemMgr->GetLineEntry_UOMPrecissionInfo(
                    $oldEntry, $uomInfoVals, $conversion, $uomPrecission
                );
                // get the remaining quantity to convert
                if ($oldEntry['CONVERSIONTYPE'] != "Price") {
                    $oldEntry['QUANTITY'] = ibcsub(
                        $quantity, $oldEntry['QTY_CONVERTED'], ItemManager::BASEUNITPRECISION, true
                    );
                } else {
                    $oldEntry['QUANTITY'] = 1;
                    if ($this->ismcpEnabled) {
                        $price = (!isNullOrBlank($trxPrice)) ? $trxPrice : $price;
                    }
                    $oldEntry['TRX_PRICE'] = $oldEntry['PRICE'] = $oldEntry['UIPRICE'] =
                        ibcsub($price, $oldEntry['PRICE_CONVERTED']);
                }
                $oldEntry['UIQTY'] = ibcdiv($oldEntry['QUANTITY'], $conversion, $uomPrecission, true);

                if ($isPrefillConversionZeroAllowed) {
                    if ($oldEntry['CONVERSIONTYPE'] == "Price") {
                        $oldEntry['TRX_PRICE'] = $oldEntry['PRICE'] = $oldEntry['UIPRICE'] = "0";
                    } else {
                        $oldEntry['UIQTY'] = $oldEntry['QUANTITY'] = "0";
                    }

                    $oldEntry["AMOUNTRETAINED"] = $oldEntry["TRX_AMOUNTRETAINED"] = "0";
                }


                // get the source docid & linekey
                $oldEntry['SOURCE_DOCKEY'] = $oldEntry['DOCHDRNO'];
                $oldEntry['SOURCE_DOCLINEKEY'] = $oldEntry['RECORDNO'];
                $oldEntry['SOURCE_DOCID'] = $recalledID;

                if ($docpar['ALLOW_ALLOCATIONS'] == 'true') {
                    // in case of PO document there might be allocations set
                    // carry the source entry splits
                    if (isset($oldEntry['ALLOCATIONKEY']) && $oldEntry['ALLOCATIONKEY'] !== ''
                        && isset($oldEntry['SPLIT']) && is_array($oldEntry['SPLIT'])) {
                        $oldEntry['SOURCE_SPLIT'] = $oldEntry['SPLIT'];
                        $oldEntry['SOURCE_ALLOCATIONKEY'] = $oldEntry['ALLOCATIONKEY'];

                        foreach ($oldEntry['SPLIT'] as $skey => $sEntry) {
                            $oldEntry['SPLIT'][$skey]['SOURCE_DOCKEY'] = $oldEntry['SPLIT'][$skey]['DOCHDRNO'];
                            $oldEntry['SPLIT'][$skey]['SOURCE_DOCLINEKEY'] = $oldEntry['SPLIT'][$skey]['RECORDNO'];

                            $oldEntry['SPLIT'][$skey]['DOCHDRNO'] = '';
                            $oldEntry['SPLIT'][$skey]['RECORDNO'] = '';
                        }
                    }
                } else {
                    unset($oldEntry['SPLIT']);
                }

                unset($oldEntry['RECORDNO']);
                unset($oldEntry['STATE']);
                unset($oldEntry['TRACKINGENTRIES']);
                unset($oldEntry['BILLED']);

                // copy tracking info
                $trackingDetails = $availableTrackingDetails[$oldEntry['SOURCE_DOCLINEKEY']] ?? [];

                foreach ($trackingDetails as $tKey => $avTrack) {
                    $trackingDetails[$tKey]['PRIOR_RECORDNO'] = $avTrack['RECORDNO'];
                    unset($trackingDetails[$tKey]['DOCENTRYNO']);
                    unset($trackingDetails[$tKey]['RECORDNO']);
                }
                if (!empty($trackingDetails)) {
                    $oldEntry['TRACKINGENTRIES'] = $trackingDetails;
                }

                $discountOnExtPrice = ($docpar['DISCOUNT_ON_EXTENDEDPRICE'] === 'true');
                $this->computeExtendedPriceWhenConverting($oldEntry, $discountOnExtPrice, $new['EXCHRATE'], $precision);

                $this->computeRetainageWhenConverting($oldEntry, $docpar);
                // setting SourceDoc details
                if (CRESetupManager::isMultiDocumentConversionEnabled() && Request::$r->_copymode == 'Update') {
                    $this->setSourceDocDetails($oldEntry);
                }
                $new['ENTRIES'][] = $oldEntry;
            }
        }

        $this->GetOrigDocDate($old, $new, $docpar);
    }

    /**
     * @param array $new
     * @param string $copy
     * @param array $docpar
     * @param array $itemsArr
     */
    protected function prepareValueforCopyOrPopulateTrans(&$new, $copy, $docpar, $itemsArr)
    {
        unset($new['ADJDOCHDRID']);
        //Need to unset PRINVBATCHKEY, ADDGLBATCHKEY and INVBATCHKEY.
        unset($new['PRINVBATCHKEY']);
        unset($new['ADDGLBATCHKEY']);
        unset($new['INVBATCHKEY']);
        unset($new['PRIMARYDOCKEY']);
        unset($new['PRIMARYDOCLINEKEY']);

        if ($copy == 'Populate') {
            $new['ADJDOCHDRID'] = $new['DOCID'];
        }

        $this->handleMCPValues($new);

        if ($copy == 'Populate') {
            $newEntries = array();
            $nonInventoryItems = array("NI", "NP", "NS");
            $itemMgr = Globals::$g->gManagerFactory->getManager('item');
            $itemCache = $itemMgr->GetItemsRawCache(array_unique($itemsArr), false);
            foreach ((($new['ENTRIES']) ?? []) as $key => $entry) {
                $itemid = explode('--', $entry['ITEMID']);
                $itemid = $itemid[0];

                // skip including serialized and non-inventory items or zero quantity lines
                if (in_array($itemCache[$itemid]['ITEMTYPE'], $nonInventoryItems)
                    || ($itemCache[$itemid]['ISSERIALIZED'] && $docpar['UPDATES_INV'] != 'Value')
                    || $entry['QUANTITY'] == '0'
                ) {
                    continue;
                }

                $entry['ADJDOCHDRKEY'] = $new['RECORDNO'];
                $entry['ADJDOCENTRYKEY'] = $new['ENTRIES'][$key]['RECORDNO'];
                $entry['UIQTY'] = "0";
                if ($docpar['UPDATES_INV'] == 'Value') {
                    $entry['UIQTY'] = "1";
                }
                $entry['TRX_VALUE'] = "0.00";
                $entry['UIVALUE'] = "0.00";
                $entry['TRX_PRICE'] = "0.00";
                $entry['UIPRICE'] = "0.00";

                $newEntries[] = $entry;
            }
            $new['ENTRIES'] = $newEntries;
        }

        // remove the parent references for line items if this document is copied from a converted document
        foreach ((($new['ENTRIES']) ?? []) as $key => $entry) {
            unset($new['ENTRIES'][$key]['RECORDNO']);
            unset($new['ENTRIES'][$key]['SOURCE_DOCKEY']);
            unset($new['ENTRIES'][$key]['SOURCE_DOCLINEKEY']);
            unset($new['ENTRIES'][$key]['BILLINGSCHEDULEKEY']);
            unset($new['ENTRIES'][$key]['TOTAL']);
            unset($new['ENTRIES'][$key]['BILLED']);
            unset($new['ENTRIES'][$key]['RECURDOCNAME']);
            unset($new['ENTRIES'][$key]['RECURDOCID']);
            unset($new['ENTRIES'][$key]['SCHEDULEID']);
            unset($new['ENTRIES'][$key]['SCHEDULENAME']);
            unset($new['ENTRIES'][$key]['SCMMACROLINK']);
            unset($new['ENTRIES'][$key]['STATE']);
            unset($new['ENTRIES'][$key]['LANDEDCOST']);
            unset($new['ENTRIES'][$key]['TRACKINGENTRIES']);
            unset($new['ENTRIES'][$key]['ALLOCATIONKEY']);
            unset($new['ENTRIES'][$key]['ALLOCATION']);
            unset($new['ENTRIES'][$key]['SPLIT']);

            if ($docpar['DOCCLASS'] != 'Order') {
                unset($new['ENTRIES'][$key]['BILLINGTEMPLATE']);
            }

            if ($copy != 'Populate') {
                unset($entry['ADJDOCHDRKEY']);
                unset($entry['ADJDOCENTRYKEY']);
            }

            unset($new['ENTRIES'][$key]['ORIGDOCKEY']);
            unset($new['ENTRIES'][$key]['ORIGDOCLINEKEY']);
            unset($new['ENTRIES'][$key]['ORIGDOCID']);
            unset($new['ENTRIES'][$key]['ORIGDOCLINEID']);
            unset($new['ENTRIES'][$key]['ORIGDOCLINENUM']);
            unset($new['ENTRIES'][$key]['ORIGDOCLINEITEMID']);
        }
        //while copying from one document to another document, we shouldn't carry the SCHOPKEY to the destination document
        //Hence unsetting the SCHOPKEY
        unset($new['SCHOPKEY']);

        // the contact version might be old
        // unset them to get the new versions
        unset($new['SHIPTOKEY']);
        unset($new['BILLTOKEY']);

        // unset the following they might have copied form sales contract document
        unset($new['SALESCONTRACT']);
        unset($new['USEDASCONTRACT']);
        unset($new['SCMMACROLINK']);
        unset($new['STATE']);
    }

    /**
     * @param array $new
     * @param array $old
     * @param string $copy
     * @param array $docpar
     * @param string $srcdoctype
     * @param string $recalledID
     * @return false|void
     * @throws Exception
     *
     * @return bool
     */
    protected function processToConvertDocument(&$new, &$old, $copy, &$docpar, $srcdoctype, $recalledID)
    {
        global $gManagerFactory;
        //$copy = Request::$r->_copymode;
        $_createdfrom = Request::$r->_createdfrom;
        $destdoctype = Request::$r->_dt;
        $ok = true;
        $srcEntityMgr = $gManagerFactory->getManager($this->mod . "document", true, array('DOCTYPE' => $srcdoctype));
        $destEntityMgr = $gManagerFactory->getManager($this->mod . "document", true, array('DOCTYPE' => $destdoctype));

        // There is a weird mix of recalled doc data and default doc data here.  If there are problems,
        // look here.
        $multipleSrcDocText = ConversionManager::getmultipleSourceDocsText();

        if ($_createdfrom == $multipleSrcDocText && $copy == 'Update' && $this->state != $this->kShowEditState) {
            $objStoreId = Request::$r->_objstoreid;
            $objectStore = $gManagerFactory->getManager('objectstore');
            $objs = $objectStore->get($objStoreId);
            if (isset($objs['OBJECTDATA'])) {
                $new = $this->ProcessMultipleSourceTransactions($objs['OBJECTDATA'], $srcEntityMgr);
            }
        } else if ($recalledID) {

            // Ideally someone in future please use the following code. We should be using the getEntityData that does processing for UI related fields.
            $old = $this->getEntityData($this->getEntity(), $recalledID, $srcdoctype);
            if (!$old) {
                global $gErr;
                $gErr->addIAError(
                    'INV-0359', __FILE__ . ":" . __LINE__,
                    "Fetching transaction '$recalledID' failed. " .
                    "TransactionID '$recalledID' has been defined in the setup as a template for creating new transactions.",
                    ['RECALLEDID' => $recalledID]
                );
                $this->state = $this->kErrorState;
                return false;
            } else {
                $ok = $this->ProcessSingleSourceTransactions($old, $new, $copy, $recalledID, $srcEntityMgr, $destEntityMgr);
            }
        }
        return $ok;
    }

    /**
     * @param array $new
     * @param array $docpar
     *
     * @return bool
     */
    protected function validateConvertDocumentonTD(&$new, $docpar)
    {
        if (isset($docpar)) {
            // Check if the document can be converted into a selected TD
            // and throw an error if it cannot
            if ('F' === $docpar['CREATION_RULE']) {
                global $gErr;
                $gErr->addIAError('INV-0360', __FILE__ . ':' . __LINE__,
                    "The document cannot be converted into " . $docpar['DOCID'] . ". " .
                    "The transaction definition " . $docpar['DOCID'] . " has a 'Create transaction in' field setting set to " . $docpar['TD_CREATION_RULE'] . ".",
                    ['DOCPAR_DOCID' => $docpar['DOCID'], 'DOCPAR_TD_CREATION_RULE' => $docpar['TD_CREATION_RULE']]
                );

                return false;
            }
            $new['DOCPARKEY'] = $docpar['RECORDNO'];
        } else {
            unset($new['DOCPARKEY']);
        }
        return true;
    }

    /**
     * @param array $new
     * @param array $docpar
     *
     * @return array
     */
    protected function prepareSalesforceValuesForCreate($new, $docpar)
    {
        if (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') {
            $copy = Request::$r->_copymode;
            $kSFORCE2id = Globals::$g->kSALESFORCE2id;
            if (IsModuleIdInstalled($kSFORCE2id) && $this->origin != 'sforce') {
                $session = IASessionHandler::getInstance();
                $profileHandler = $session->getProfileHandler();
                $profileHandler->deleteProperty('SFORCEKEY');
                $profileHandler->saveProfile();
                $profileHandler->reload();
            } else if ($copy != 'Update') {
                $new = $this->prepSalesforceValues($new, Profile::getProperty('SFORCEKEY'));
            }
        }
        return $new;
    }

    /**
     * @param array $old
     * @param array $new
     * @param string $copy
     * @param string $recalledID
     * @param EntityManager $srcEntityMgr
     * @param EntityManager $destEntityMgr
     *
     * @return bool
     */
    private function ProcessSingleSourceTransactions(&$old, &$new, $copy, $recalledID, $srcEntityMgr, $destEntityMgr)
    {
        // recalculate subtotals based on new definition.
        if ( ! $this->processCopyConvert($copy, $old)) {
            return false;
        }

        if (!util_isPlatformDisabled()) {
            $srcEntityMgr->getRelationships($old, false, true, true);
        }

        $docpar = $this->GetBaseDocPar();

        $entries = $old['ENTRIES'] ?? [];

        $entryCnt = count($entries);

        $itemsArr = array();
        for ($i = 0; $i < $entryCnt; $i++) {
            [$itemid] = explode('--', $old['ENTRIES'][$i]['ITEMID']);
            $itemsArr[] = $itemid;
        }

        $itemMgr = Globals::$g->gManagerFactory->getManager('item');
        $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, true, false);

        for ($i = 0; $i < $entryCnt; $i++) {

            $tempItemID = explode("--", $old['ENTRIES'][$i]['ITEMID']);
            $tempItemID = $tempItemID[0];

            $itemuoms = array();
            foreach ($uomInfoVals[$tempItemID] as $value) {
                $itemuoms[] = $value;
            }
            $old['ENTRIES'][$i]['ITEMUOM'] = $itemuoms;
        }

        // transform to doc format, if necessary
        $old = $this->copyToAdapter->transformToDocFormat($old, $this->isRetainageBeingUsed);

        $new = $old;

        if (!util_isPlatformDisabled()) {
            $this->setPlatformData($new);
        }

        // when converting
        if ($copy == 'Update') {
            $this->prepareValueFromSourceTrans($new, $old, $docpar, $itemsArr, $itemMgr, $srcEntityMgr, $recalledID);
        } elseif ($copy == 'Copy' || $copy == 'Populate') {
            $this->prepareValueforCopyOrPopulateTrans($new, $copy, $docpar, $itemsArr);
        }

        // Since we're doing convert/copy from source document,
        // We should not carry create date/due date/GL posting date values from source document into converted/copyied document,
        // e.g. source could have been created in past but when we perform convert/copy operation,
        // the converted/copyied document should actually show create date = current date,
        // and due date should be recalculated based on term assigned (if any)
        // unset create date/due date values
        if ($copy != 'Populate') {
            unset($new['WHENCREATED']);
        }
        unset($new['RECORDNO']);
        unset($new['WHENDUE']);
        unset($new['WHENPOSTED']);
        unset($new['PRINTED']);
        unset($new['DATEPRINTED']);
        unset($new['PRINTEDBY']);
        // unset this as this might be converted/copied from backorder
        unset($new['BACKORDER']);

        // Unset the POmatch fields while convert / copy the transactions
        unset($new['DOCSOURCE']);
        unset($new['POMATCHSENDEREMAIL']);
        unset($new['POMATCHRECEIPTEMAIL']);

        $this->ProcessSubtotalsForSave($new);

        // Do not copy 'sequence' field
        foreach ($destEntityMgr->customFields as $fieldid => $details) {
            if ($details->type == 'SEQUENCE') {
                unset($new[$fieldid]);
            }
        }
        EntityManager::SetByPath($new, $destEntityMgr->GetKeyFieldName(), '');
        return true;
    }

    /**
     * @param array $obj
     * @param array $headersection
     * @param string $copy
     */
    protected function showCreatedFromLink(&$obj, &$headersection, $copy)
    {
        $this->removeSrcDocLinkFromDocument($obj);

        // This Change Option will come only for Edit mode in UI for Draft document
        // This onChangeSrcDocOptionIsAvailable contain all pomatch related validation
        if ($this->state == $this->kShowEditState
            && $this->onChangeSrcDocOptionIsAvailable($obj)) {

            // If 'CREATEDFROM' field value is available or not still we need to show the field for this pomatch document
            $headersection->findAndSetProperty(['path' => 'CREATEDFROM'], ['hidden' => false]);


            $isRemoveSrcDocLinkEnabled = ((Request::$r->_removesourcelink ?? '') == '1');
            $changeSrcDocLinkShowHide = (empty($obj['CUSTVENDID'] ?? '') || (!empty($copy) && $copy != 'Update'));
            $headersection->findAndSetProperty(
                ['path' => 'CHANGE_SOURCE_DOC_LINK'], ['hidden' => $changeSrcDocLinkShowHide], EditorComponentFactory::TYPE_FIELD
            );

            $obj['CHANGE_SOURCE_DOC_LINK'] = GT($this->textMap, 'IA.CT_CHANGE');

            $removeSrcDocLinkfieldShowHide = (empty($obj['CREATEDFROM'] ?? '') || $isRemoveSrcDocLinkEnabled);
            $headersection->findAndSetProperty(
                ['path' => 'REMOVE_SOURCE_DOC_LINK'], ['hidden' => $removeSrcDocLinkfieldShowHide], EditorComponentFactory::TYPE_FIELD
            );
            $obj['REMOVE_SOURCE_DOC_LINK'] = GT($this->textMap, 'IA.REMOVE');

            // add the change src event to pomatch document only when vendor is change
            // For vendor on change event we are adding the pomatch validation function
            // This on change event is required to handl below case
            // When Draft document doesn't have vendor field value we are hiding this change option link
            //     Because change option popup list will provide the parent transaction based on the vendor filter
            // If user provide the vendor value we will validate and show the change option link
            $custvendField = [];
            $headersection->findComponents(array('path' => 'CUSTVENDID'), EditorComponentFactory::TYPE_FIELD, $custvendField);
            $custvendField = $custvendField[0];

            if ($custvendField) {
                $events = $custvendField->getProperty('events');
                $events['change'] .= " initChangeSrcOption();";
                $custvendField->setProperty('events', $events);
            }

        } else {
            if (!$obj['CREATEDFROM'] || $obj['CREATEDFROM'] == '' || $copy != 'Update') {
                $headersection->findAndSetProperty(array('path' => 'CREATEDFROM'), array('hidden' => true));
            }
        }
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function onChangeSrcDocOptionIsAvailable($obj)
    {
        return false;
    }

    /**
     * tax details with which the tax schedule id is associated.
     */
    public function ajaxGetTaxDetailsForTaxSchedule()
    {
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        if($docMgr->isOverrideTaxSchedForEntryEnabled()) {
            $taxScheduleId = empty($taxScheduleId) ? Request::$r->taxScheduleId : $taxScheduleId;

            $taxDetailIds = $docMgr->fetchTaxDetailsFromScheduleId($taxScheduleId);

            Request::$r->taxDetailIds = $taxDetailIds ?? [];
            $this->ajaxCalculateLineSubTotals();
        }
    }
}
