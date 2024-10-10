<?php

/**
 *    FILE: DocumentManager.cls
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 *  Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


/**
 * import the files necessary for document manager code.
 */
import('ContactManager');
import('WarehouseManager');
import('ShipMethodManager');
import('DocHistoryManager');
import('ManagerFactory');


define('DOCUMENT_WORKFLOW_FILE', 'document.wfl');


/**
 * All required files for Document Manager.NSO
 */
// temporary, hopefully
require_once 'backend_prbatch.inc';
require_once 'backend_invoice.inc';
require_once 'backend_supdoc.inc';

// All scm utility functions.
require_once 'scm_util.inc';

/**
 * The class that manages the Supply Chain Management (SCM) transaction documents.
 * Inherited from EntityManager and subclassed by module level document managers.
 * Uses various handlers that help to perform the functional tasks.
 *
 * @package    source
 * @subpackage inventory
 */
class DocumentManager extends EntityManager
{
    use ComplianceTrait;

    const ALLOWED_DOCS_COUNT = '_allowed_docs_count';

    const DEFAULT_STATE = 'Pending';
    const DRAFT_STATE = 'Draft';
    const SUBMITTED_STATE = 'Submitted';
    const PARTIALLY_APPROVED_STATE = 'Partially Approved';
    const APPROVED_STATE = 'Approved';
    const DECLINED_STATE = 'Declined';
    const PENDING_STATE = 'Pending';
    const CONVERTED_STATE = 'Converted';
    const PARTIALLY_CONVERTED_STATE = 'Partially Converted';
    const CLOSED_STATE = 'Closed';
    const INPROGRESS_STATE = 'In Progress';
    const PARTIALLY_CONVERTED_BY_LINE_STATE = 'Partially Converted By Line';
    const CONVERTED_BY_LINE_STATE = 'Converted By Line';
    const EXCEPTION_STATE = 'Exception';
    const ANALYZING_STATE = 'Analyzing';
    const BUILT_STATE = 'Built';
    const DISASSEMBLED_STATE = 'Disassembled';
    const AR_POSTING_METHOD_ADDITION = 'Addition';
    const AR_POSTING_METHOD_NONE = 'None';

    //raw states
    const DRAFT_RAWSTATE = 'I';
    const SUBMITTED_RAWSTATE = 'S';
    const PARTIALLY_APPROVED_RAWSTATE = 'X';
    const APPROVED_RAWSTATE = 'A';
    const DECLINED_RAWSTATE = 'R';
    const PENDING_RAWSTATE = 'O';
    const CONVERTED_RAWSTATE = 'C';
    const PARTIALLY_CONVERTED_RAWSTATE = 'P';
    const CLOSED_RAWSTATE = 'D';
    const INPROGRESS_RAWSTATE = 'G';
    const PARTIALLY_CONVERTED_BY_LINE_RAWSTATE = 'B';
    const CONVERTED_BY_LINE_RAWSTATE = 'L';
    const EXCEPTION_RAWSTATE = 'E';
    const ANALYZING_RAWSTATE = 'Z';

    const POSTED_DOC_STATES = [
            DocumentManager::PENDING_STATE,
            DocumentManager::CONVERTED_STATE,
            DocumentManager::PARTIALLY_CONVERTED_STATE,
            DocumentManager::CLOSED_STATE,
            DocumentManager::PARTIALLY_CONVERTED_BY_LINE_STATE,
            DocumentManager::CONVERTED_BY_LINE_STATE,
            DocumentManager::BUILT_STATE,
            DocumentManager::DISASSEMBLED_STATE
    ];

    // When upserting, the KEY demands that the VALUE has already been upserted.  If not, error!
    // i.e. if something depends on DocEntry, then <thing> => 'docentry', (case is lower case, same as in getManager())
    // MAYBE ALWAYS GO THROUGH THE MATCHMAKER AND CHECK THE FLAG INSIDE IT
    // IN SUBLEDGER CODE SEE HOW THEY ARE ORGANIZED
    const UPSERT_ORDER = [
        'dochdr'                    => '',                      // empty because we're first
        'docentry'                  => 'dochdr',
        'prrecord'                  => 'docentry',
        'prentry'                   => 'prrecord',
        'prentryresolve'            => 'docentry', // ['prentry', 'docentry'], // ADD PRENTRY WHEN $upsertPRRecordToo IS TRUE
        'stkitdocumententrycost'    => 'docentry',
        'documententrycost'         => 'docentry',
        'documententryglresolve'    => 'docentry',
        'documententrysubtotals'    => 'docentry',
        'subtotals'                 => 'docentry',
        'subtotalglresolve'         => 'subtotals',
    ];

    // Matchmaker match fields can go here or in the .ent file as 'matchmaker_match_fields'.
    // Senthil recommended that for now, since this is the only module upserting in this way,
    // we just put the entries here.  The KEY is the manager name, the values are the fields to match.
    // Also, note that the Matchmaker adds dimension fields, including custom dimensions
    const MATCHMAKER_MATCH_FIELDS = [
        // There is only one record possible, and we actually have the record#, so these aren't critical
        'apbill'     => ['RECORDNO', 'RECORDID'],
        'arinvoice'  => ['RECORDNO', 'RECORDID'],

        // see SCMSubLedgerHandler::CreateAPARDocumentValues() for the ITEMS entries
        // also BasePRRecordManager::buildOffsetEntry() for the OFFSET entries (handled differently)
        'apbillitem'    => ['ITEMDIMKEY', 'WAREHOUSEDIMKEY', 'ACCOUNTNO', 'LINE_NO'],
        'arinvoiceitem' => ['ITEMDIMKEY', 'WAREHOUSEDIMKEY', 'ACCOUNTNO', 'LINE_NO'],

        'documententry'             => ['RECORDNO'],  // use the record #.  No record#?  No match.
        'sodocumententry'           => ['RECORDNO'],
        'podocumententry'           => ['RECORDNO'],
        'invdocumententry'          => ['RECORDNO'],
        'documententrysubtotals'    => ['RECORDNO'],
        'podocumententrysubtotals'  => ['RECORDNO'],
        'sodocumententrysubtotals'  => ['RECORDNO'],
        'documententrytrackdetail'  => ['RECORDNO'],

        // see SCMSubLedgerHandler::CreateGLResolveMAP()
        'documententryglresolve' => ['DOCHDRKEY', 'DOCENTRYKEY', 'ORIG_TRTYPE', 'COGSPOSTING'],

        // see SCMSubLedgerHandler::CreateGLResolveMAP()
        'subtotalglresolve'      => ['DOCHDRKEY', 'SUBTOTKEY', 'GLENTRYKEY', 'ORIG_TRTYPE'],

        // see Costing::UpdateDocEntryCostEntries()
        'documententrycost'      => ['DOCENTRYNO', 'ITEMID', 'WAREHOUSEID', 'SERIALNO', 'LOTNO', 'AISLEKEY', 'ROWKEY', 'BINKEY', 'EXPIRATIONDATE', 'SYSTEMGENERATED', 'AFFECTS_INVENTORY'],

        // see StkitDocumentManager::processComponents()
        'stkitdocumententrycost' => ['DOCENTRYNO', 'ITEMID', 'WAREHOUSEID', 'SERIALNO', 'LOTNO', 'AISLEKEY', 'ROWKEY', 'BINKEY', 'EXPIRATIONDATE', 'AFFECTS_INVENTORY'],
    ];
    const INVOICE_UPLOAD = 'Invoice upload';
    const EMAIL = 'Email';
    const EMAIL_DBVALUE = 'email';


    /**
     * private variables
     */

    /**
     * @var mixed $_recalledDoc
     */
    var $_recalledDoc;

    /**
     * @var string[][] $_offsetaccts
     */
    var $_offsetaccts = array();

    /**
     * Not used, passed through to CalcSubTotals in the $taxLines parameter which itself isn't used.
     *
     * @var bool|null    $_usingTaxSchedules
     */
    var $_usingTaxSchedules = null;

    /**
     * @var string  $_contactTaxGrpKey
     */
    var $_contactTaxGrpKey;

    /**
     * @var string[]|string[][]|string[][][]   $_itemLines
     */
    var $_itemLines = array();

    /**
     * @var string[]|string[][]|string[][][]   $_taxLines
     */
    var $_taxLines = array();

    /**
     * @var string[]|string[][]   $_getSubTotalsResult
     */
    var $_getSubTotalsResult = array();

    /**
     * @var array   $_simpletaxLines
     */
    var $_simpletaxLines = array();

    /**
     * @var array   $_prtaxEntries
     */
    var $_prtaxEntries = array();

    /**
     * @var array   $_itemPREntrykeys
     */
    var $_itemPREntrykeys = array();

    /**
     * @var array   $_taxPREntrykeys
     */
    var $_taxPREntrykeys = array();

    /**
     * @var array   $_simpletaxPREntrykeys
     */
    var $_simpletaxPREntrykeys = array();

    /**
     * @var string[][] $_revenueAccts
     */
    var $_revenueAccts = array();

    /**
     * @var array[][] $_prglLineFromTD
     */
    var $_prglLineFromTD = array();

    /**
     * @var bool    $_ismcpEnabled
     */
    var $_ismcpEnabled;

    /**
     * @var bool    $_fromAPI
     */
    var $_fromAPI = false; // Was operation initiated from the API?

    /**
     * @var string  $mod
     */
    var $mod = "";

    /**
     * @var bool    $_isCachable
     */
    var $_isCachable = true;

    /**
     * @var bool    $replaceDOCNO       TRUE if DOCNO generation is postponed
     */
    var $replaceDOCNO = false;

    /**
     * @var bool    $postponeSmartRules Flag to indicate document smart rules are postponed
     */
    var $postponeSmartRules = false;

    /**
     * @var bool    $postponeEvents Flag to indicate document events are postponed till the complete transaction is ready to be commited
     */
    var $postponeEvents = false;

    /**
     * @var string|DocumentParamsManager  $docParMgr  We cache the docParMgr as we do a lot of calls in the logic.  (Note: seems not to be used)
     */
    var $docParMgr = "";

    /**
     * @var array   $itemRawCache
     */
    var $itemRawCache = array();

    /**
     * @var array   $contactVersionCache
     */
    var $contactVersionCache = array();

    /**
     * @var bool   $_isCustVendRequired
     */
    var $_isCustVendRequired = true;

    /**
     * @var array $_itemCrossRefrencesCache
     */
    var $_itemCrossRefrencesCache = [];

    /**
     * This was a coding error.  The code should have used $_isCustVendRequired
     * but had a typo and ended up using an undefined, null, property instead.
     * Fixing the code to behave as intended, unfortunately breaks the
     * Sanity_XML2.1/test_icoe_create_potransaction_v7 test so we'll leave this
     * here until the correct team an properly deal with it.
     *
     * @var bool    $_IsCustVendRequired
     */
    var     $_IsCustVendRequired = null;

    /**
     * @var array   $macroUIFieldInfo
     */
    private $macroUIFieldInfo = array();

    /**
     * @var array   $macroFields
     */
    protected $macroFields = array();

    /**
     * @var string[] $shipToKeyMap
     */
    protected $shipToKeyMap = [];

    /**
     * @var string[] $taxGroupKeyMap
     */
    private $taxGroupKeyMap = [];

    /**
     * @var string[] $shipToTaxableMap
     */
    private $shipToTaxableMap = [];

    /**
     * @var string[] $itemTaxableMap
     */
    private $itemTaxableMap = [];

    /**
     * @var string[] $itemTaxGroupMap
     */
    private $itemTaxGroupMap = [];

    // trait that handles all logic related to state
    use DocumentStateTrait;

    // trait that decides to repost logics
    use DocumentRepostTrait {
        getFieldListToCompare as traitGetFieldListToCompare;
    }

    //add change order behavior to the document
    use ChangeOrderTrait;

    //  this var will be used to store the document
    //  before doign a full ditribution for subtotals in PrepareSubTotals()
    //var $_oldDocumentValues = array();

    /**
     * @var string  $defaultLineLevelSimpleTaxType
     */
    var $defaultLineLevelSimpleTaxType = "";

    /**
     * @var bool $systemUpdate
     */
    private $systemUpdate = false;

    /**  Tokens used in the base class     */
    private const LOCAL_TOKENS = [
        "IA.BILL_TO",
        "IA.SHIP_TO",
        "IA.CUSTOMER"
     ];

    /**
     * This var MUST BE LEFT EMPTY. It should be populated in child classes
     * @var array
     */
    protected array $additionalTokens = [];

    /** @var bool $isInventoryIntalled */
    protected $isInventoryIntalled;

    /** @var bool $isShipDatesEnabled */
    protected $isShipDatesEnabled;

    /* @var bool $skipAllocations */
    protected $skipAllocations;

    /** @var bool $upsertFeaturInUse                 And are we actually USING upsert in the new way? */
    public static $upsertFeaturInUse = false;       // static so other code can see if it is in use when it isn't.

    /** @var bool $upsertConservatively             Only valid when $upsertFeatureInUse */
    public static $upsertConservatively = true;     // be conservative when upserting: don't skip identical records

    /** @var string $upsertDocType */
    public static $upsertDocType = '';              // IF we are upserting, what doc type is this?

    /** @var array $upsertedEntities */
    private static $upsertedEntities = [];          // while upserting, which entities have been upserted?

    /** @var bool $upsertPRRecordToo */
    public static $upsertPRRecordToo = false;       // set with the SCM_UPSERT_ARAP_TOO feature flag for now

    /** @var array $dynamicIgnoreFields */
    public array $dynamicIgnoreFields = [];

    //Trait compare document values
    use DocumentCompareTrait;

    /**
     * @var array $listOfCREDocStates
     */
    var $listOfCREDocStates = [];

    /**
     * @var array $_reasonsForRePost
     */
    var $_reasonsForRePost = [];

    /**
     * @var array $_reasonsForRePostIADetails
     */
    var $_reasonsForRePostIADetails = [];

    /** @var array $_unlinkedComplianceRecords */
    private array $_unlinkedComplianceRecords = [];

    /** @var bool $isDigitalNetworkSyncEnabled */
    protected $isDigitalNetworkSyncEnabled = false;

    /** @var bool $isTargetDocument */
    protected  $isTargetDocument = false;

    /** @var bool $usedInBothSourceTarget */
    protected  $usedInBothSourceTarget = false;

    protected $isPOAutomationWorkflow = false;

    //Project Contract Billing Trait, used by derived classes.
    use ProjectContractBillingTrait;

    use RetainageBillingTrait;

    use ReverseConversionTrait;

    //Retainage tax trait, used to perform the retainage tax related methods.
    use RetainageTaxTrait;

    //Retainage tax trait, used to perform the retainage tax related methods.
    use OverrideTaxScheduleTrait;

    /**
     * @var bool $isSourceDocumentChanged
     */
    protected $isSourceDocumentChanged = false;

    /**
     * @var bool $_forDoEvent
     */
    var $_forDoEvent = false; // Is this call intended for the DoEvent function

    /**
     * initialize the Document Manager instance with parameters passed as $params array
     *
     * @param  array $params Initial parameters of the transaction
     */
    function __construct($params = array())
    {
        $this->_docType = $params['DOCTYPE'];

        parent::__construct($params);
        include 'document.qry';
        /** @noinspection PhpUndefinedVariableInspection */
        $this->_QM->LoadQueries($kdocumentQueries);

        $this->mod = self::getMyModID($params['_mod']);
        $this->_ismcpEnabled = IsMCPEnabled($this->mod);
        $this->atlas = IsMCMESubscribed();

        // This code never worked before entity manager refactor (27884)
        // Now that it is enabled, it affects the behavior of the documents
        // See ticket: 38377; this code allows 'Approve' and 'Decline' as smart event triggers,
        // however, these are not yet implemented (we can re-enable this code once we implement them)
        /*
        if ( ! isset($this->_docType) || $this->_docType == "" ) {
            $this->_schemas[strtolower($this->_entity)]['customerp'] = null;
        }
        */

        $this->_isCustVendRequired = $this->IsCustVendRequired(array('DOCID' => $this->_docType));

        $this->skipAllocations = is_null($params['skipAllocations']) ? false : $params['skipAllocations'];

        //For the shipping date configuration, we have added this perticular code.
        $kINVid = Globals::$g->kINVid;
        $this->isInventoryIntalled = IsInstalled($kINVid);
        $this->isShipDatesEnabled = (self::GetPreferenceForProperty($kINVid, 'ENABLESHIPPINGDATES') == 'T') ? true : false;
        $this->loadTokenLabels();
    }

    /**
     * translates the language tokens and loads them to the textmap
     * @return void
     */
    protected function loadTokenLabels(): void
    {
        try {
            $tokens = array_merge($this->additionalTokens, self::LOCAL_TOKENS);
            I18N::getTokensForArray(I18N::tokenArrayToObjectArray($tokens));
        } catch (I18NException $ex) {
            LogManager::getInstance()->logErrorMessage( "loadTokenLabels- Labels could not be loaded from text service. Error message: " . $ex->getMessage());
        }
    }

    /**
     *  This works like the one in backend_prefs.inc but caches the preferences rather than read them OVER and OVER
     *
     * @param string $modid
     * @param string $property
     *
     * @return string
     */
    public static function GetPreferenceForProperty($modid, $property)
    {
        // while GetModulePreferences() caches some results, it also does a bunch
        // of other work and so I think this is just faster
        static $preferences = [];
        if ( ! isset($preferences[$modid])) {
            $preferences[$modid] = GetModulePreferences($modid);
        }
        return ($preferences[$modid][$property] ?? null) ?: '';
    }

    /**
     * @param string $userType
     * @param array $values
     *
     * @return bool
     */
    public function validateUserAndDocClass($userType,  $values)
    {
        $ok = true;
        $docClass = $values['_DOCPAR']['DOCCLASS'];
        if ( ( $userType == 'E' || $userType == 'T' ) && $docClass != '' && isl_strtoupper($docClass) != 'QUOTE' ) {
            $ok = false;
            global $gErr;
            $msg = "The user does not have the permission to do this operation";
            $gErr->addIAError('INV-1251', __FILE__ . ':' . __LINE__, $msg, []);
        }
        return $ok;
    }

    /**
     * @param array $docvalues
     *
     * @return string
     */
    protected function getShipToLineItemArrKey(/** @noinspection PhpUnusedParameterInspection */$docvalues)
    {
        return 'SHIPTO';
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function setShipToKeyMap($values)
    {
        $headerKey = $this->getShipToLineItemArrKey($values);
        $contactnames = [];
        $itemIDs = [];
        //In PO, BILLTO is used for tax calculation. so explicitly adding DELIVERTO in VAT companies here to find
        // and add its record# to shipToKeyMap, to use it in prepDeliverToContact method
        if (($values['TXNISVATENABLED'] ?? false) && ($values['ISHEADERDELIVERTOENABLED'] ?? false) && !empty($values['DELIVERTO']['CONTACTNAME'])) {
            $contactnames[] = $values['DELIVERTO']['CONTACTNAME'];
        }
        foreach ((($values['ENTRIES']) ?? []) as $line) {
            $contactnames[] = empty($line[$headerKey]['CONTACTNAME']) ? $values[$headerKey]['CONTACTNAME'] : $line[$headerKey]['CONTACTNAME'];
            if (!empty($line['BTOSHIPTOCONTACTNAME'])) {
                $contactnames[] = $line['BTOSHIPTOCONTACTNAME'];
            }
            //Find line level Deliverto key values
            if (($values['TXNISVATENABLED'] ?? false) && ($values['ISLINEDELIVERTOENABLED'] ?? false) && !empty($line['DELIVERTO']['CONTACTNAME'])) {
                $contactnames[] = $line['DELIVERTO']['CONTACTNAME'];
            }
            $itemIDs[] = explode('--', $line['ITEMID'])[0];
        }
        $contactnames[] = $values[$headerKey]['CONTACTNAME'];
        $contactnames = array_unique($contactnames);
        $itemIDs = array_unique($itemIDs);
        // due to performance problems we want to query the contact view rather than the entire contactversion table
        $contact = Globals::$g->gManagerFactory->getManager('contact');
        $filter = array(
            'selects' => array('CONTACTNAME', 'VERSIONKEY', 'TAXGROUPKEY', 'TAXABLE'),
            'filters' => array(
                array(
                    array('CONTACTNAME', 'in', $contactnames),
                )
            ),
            'usemst' => true
        );
        $result = $contact->GetList($filter);

        foreach ($result as $row) {
            $this->shipToKeyMap[$row['CONTACTNAME']] = $row['VERSIONKEY'];
            $this->taxGroupKeyMap[$row['CONTACTNAME']] = $row['TAXGROUPKEY'];
            $this->shipToTaxableMap[$row['CONTACTNAME']] = $row['TAXABLE'];
        }
        //Check for values not in DB
        $inValidContacts = array_filter(array_diff($contactnames, array_keys($this->shipToKeyMap)));

        //Validation for invalid ship to contacts
        if (!empty($inValidContacts)) {
            // TODO:  When the following error logging function addError is converted to addIAError special attention
            //  should be paid to the generation of the error message.  The implode function can produce strings which
            //  exceed 4K in length.  This is bad for error messages as they are not useful to the user.  I recommend
            //  That an error message like "Line level contacts(s) is not valid" be provided to the first message in
            //  addIAError.  Then a string which can be truncated to limit be provided to the second message parameter.
            //  This would allow the first message to be translatable. - Mike Henniger, 24 Feb 2023
            $strInValidContacts = implode(", ", $inValidContacts);
            $msg = "Line level contact(s) " . $strInValidContacts . " is not valid!";
            Globals::$g->gErr->addIAError('INV-1252', __FILE__ . ':' . __LINE__, $msg, ['IN_VALID_CONTACTS' => $strInValidContacts]);
            return false;
        }

        if( !empty($itemIDs) ){
            $itemFilter = array(
                'selects' => array('ITEMID', 'RECORDNO', 'TAXABLE', 'TAXGROUPKEY'),
                'filters' => array(
                    array(
                        array('ITEMID', 'in', $itemIDs),
                    )
                ),
                'orders' => array(
                    array('RECORDNO', 'asc')
                )
            );
            $itemMngr = Globals::$g->gManagerFactory->getManager('item');
            $itemResults = $itemMngr->GetList($itemFilter);
            foreach ($itemResults as $item) {
                $this->itemTaxableMap[$item['ITEMID']] = $item['TAXABLE'];
                $this->itemTaxGroupMap[$item['ITEMID']] = $item['TAXGROUPKEY'];
            }
        }
        return true;
    }

    /**
     * @param string $mod
     *
     * @return string
     */
    public static function getMyModID($mod)
    {
        return ($mod == 'pa' ? 'so' : $mod);
    }

    /**
     * Get the doctype for this document.
     *
     * @return string
     */
    function getDocType()
    {
        return $this->_docType;
    }

    /**
     * @param string $keyField
     * @param int $recordno
     *
     * @return array
     */
    protected function getParamsForVidFromRecordNo($keyField, $recordno)
    {
        $params = parent::getParamsForVidFromRecordNo($keyField, $recordno);
        if ( $this->_docType ) {
            $params['filters'][0][] = [ 'DOCPARID', '=', $this->_docType ];
        }

        return $params;
    }

    /**
     * Get the values for the document using the id of the document.
     *
     * @param  string $ID ID of the document.
     * @param  array|null $fields Array of names of requested fields
     *
     * @return array|false $obj Array of the document values in the ent structure with child values.
     */
    function Get($ID, $fields = null)
    {

        global $gManagerFactory;

        $obj = parent::get($ID, $fields);
        if ($obj === false) {
            return false;
        }

        $itemMgr =  $gManagerFactory->getManager('item');
        // The below code is to avoid the number of queries hitting database.
        // Though we do 3 loops, it is effective than using the oracle resources for query each item.
        $itemIDs = array();
        $entryCnt = countArray($obj['ENTRIES']);
        if ($entryCnt > 0) {
            for ($i = 0; $i < $entryCnt; $i++) {
                $itemIDs[] = $obj['ENTRIES'][$i]['ITEMID'];
            }

            if ((!empty($itemIDs))) {
                StartTimer('ItemCache');
                $itemFieldList = array('ITEMID', 'NAME', 'ITEMTYPE', 'ENABLELOT', 'ENABLESNO', 'ENABLEBIN', 'ENABLEEXPIRATION');
                $itemCache = $itemMgr->GetItemsRawCache(array_unique($itemIDs), true, $itemFieldList);
                StopTimer('ItemCache');

                for ($i = 0; $i < $entryCnt; $i++) {
                    $itemid = $obj['ENTRIES'][$i]['ITEMID'];
                    $obj['ENTRIES'][$i]['ITEMID'] = $itemid . '--' . $itemCache[$itemid]['NAME'];
                    $obj['ENTRIES'][$i]['ITEMNAME'] = $itemCache[$itemid]['NAME'];
                }
            }
        }

        if (isset($this->_schemas[$this->_entity]['supdocentity'])) {
            GetSupDocId($obj, $this->_schemas[$this->_entity]['supdocentity']);
        }

        $this->getEntrySubTotals($obj);

        $this->showSubTotals($obj);

        $this->processSubtotalsForDimensions($obj);

        $this->GetDocHistory($obj);

        //$this->GetGLPostingDate($obj);

        //fetch document definition to see if it is enabled for sales contract
        $docparMgr = $this->get_docpar_manager();
        $obj['_DOCPAR'] = $docparMgr->GetBaseLatest($obj['DOCPARID']);

        //fetch document values for the document record#
        if ($obj['_DOCPAR']['ENABLESCHEDULE'] == 'true' && $obj['RECORDNO'] != '') {
            import('RecurDocumentManager.cls');
            $RecurdocMgr = new RecurDocumentManager(array('enableSchedule' => true));
            $obj['RECURHISTORY'] = $RecurdocMgr->GetRecurHistoryList($obj['RECORDNO']);
        }

        $this->formatCCOGetData($obj);
        $this->calculateBalanceToFinish($obj);

        return $obj;
    }

    /**
     * This function will build the document entry with entrysubtotals
     *
     * @param  array &$obj the document values
     * @return bool
     */
    public function getEntrySubTotals(&$obj)
    {
        //Is company enabled for line level subtotals?
        $isTxnVATEnabled = $this->isVATEnabled($obj);
        GetTaxEngine($this->mod, ($obj['TAXSOLUTIONID'] ?? ''),$isAvaVATEnabled);
        $docparMgr = $this->get_docpar_manager();
        $docPar = $docparMgr->GetBaseLatest($obj['DOCPARID']);
        if (!($isAvaVATEnabled
            || $this->isShipToLineItemEnable()
            || $isTxnVATEnabled
            || $docPar['LINELEVELSIMPLETAX'] == 'true'
            || $this->isOverrideTaxSchedForEntryEnabled())) {
            return true;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;

        $entrysubtotalsentity = $this->getEntrySubtotalsEntity();
        if(!isset($entrysubtotalsentity) || $entrysubtotalsentity == null){
            return true;
        }
        $docEntrySubTotalsMgr = $gManagerFactory->getManager($entrysubtotalsentity);

        //optimization: match the subtotals with their parents in a single pass
        $entrysubtotalsParams = array (
            'selects' => array (
                'DOCHDRNO',
                'DESCRIPTION',
                'TOTAL',
                'TRX_TOTAL',
                'ABSVAL',
                'TRX_ABSVAL',
                'PERCENTVAL',
                'DOCENTRYKEY',
                'TAXDETAIL',
                'OVERRIDETAXVALUE',
                'ISPARTIALEXEMPT'
            ),
        );
        //TO sort subtotal entries to display properly for UI
        if($isTxnVATEnabled){
            $entrysubtotalsParams['selects'][] = 'OVERRIDENTAXDETAIL';
            $entrysubtotalsParams['selects'][] = 'SYSTEMTAXDETAILKEY';
            $entrysubtotalsParams['orders'] = array(array('RECORDNO', 'asc'));
        }

        $entrysubtotalsParams['filters'] = array(array(array('DOCHDRNO', '=', $obj['RECORDNO'])));
        $entrysubtotals = $docEntrySubTotalsMgr->GetList($entrysubtotalsParams);

        if(!empty($entrysubtotals))
        {
            //Build array bases on docentrykey
            $entrysubtotalsArr = [];

            foreach ($entrysubtotals as $entrysubtotal)
            {
                //Set overriden tax field value of the subtotal entry
                if (!empty($entrysubtotal['OVERRIDETAXVALUE']) && $entrysubtotal['OVERRIDETAXVALUE'] == 'T')
                {
                    $entrysubtotal['OVERRIDETAXVALUE'] = 'true';
                }
                //Set transaction value to zero if null to display 0 instead of -- in UI
                if ($isTxnVATEnabled)
                {
                    $entrysubtotal['TRX_ABSVAL'] = empty($entrysubtotal['TRX_ABSVAL']) ? '0' : $entrysubtotal['TRX_ABSVAL'];
                }
                $entrysubtotalsArr[$entrysubtotal['DOCENTRYKEY']][] = $entrysubtotal;
            }

            //Assign the documententrysubtotals to documententry
            if(!is_null($obj['ENTRIES']))
            {
                foreach ($obj['ENTRIES'] as &$entry)
                {
                    if ($entrysubtotalsArr[$entry['RECORDNO']] != '')
                    {
                        if (($entry['PARTIALEXEMPT'] ?? null) === 'true') {
                            $this->prepareSubtotalsWithPartialExemption($entry, $entrysubtotalsArr[$entry['RECORDNO']]);
                        }
                        $entry['SUBTOTALSENTRY'] = $entrysubtotalsArr[$entry['RECORDNO']];
                    }
                }
            }
            unset($entry);
        }
        return true;
    }

    /**
     * @param array $obj
     */
    public function processSubtotalsForDimensions(&$obj)
    {
        if (!isset($obj['RECORDNO']) || $obj['RECORDNO'] == '') {
            return;
        }

        if (!in_array($this->_entity, ['podocument', 'sodocument', 'invdocument'])) {
            return;
        }

        $subTotObj = $this->getSubtotalsInstance();
        $mayHaveCommonDims = ($subTotObj->_copyDimensionsFromLineitem
            || $subTotObj->_overrideDimensionsFromSubtotals
            || $subTotObj->_distributeSubtotalsAtEntity
            || $this->isVATEnabled($obj));

        if (!$mayHaveCommonDims) {
            return;
        }

        $dochdrkey = $obj['RECORDNO'];
        $docSubTotalsMgr = $this->getDocSubTotalsManager(true);

        $subtotalParams = array(
            'selects' => array(
                'DOCHDRNO',
                'DESCRIPTION',
                'LOCATIONID',
                'DEPARTMENTID',
            ),
        );

        $allDimFieldIDs = ['LOCATIONID', 'DEPARTMENTID'];
        $allDimFieldNames = ['LOCATIONID' => 'LOCATION',
            'DEPARTMENTID' => 'DEPARTMENT'];

        $dimFields = $docSubTotalsMgr->GetDimensionFields();
        if (is_array($dimFields)) {
            foreach ($dimFields as $field) {
                if (!$field['standard']) {
                    continue;
                }

                $fieldid = isl_strtoupper($field['path']);
                $subtotalParams['selects'][] = $fieldid;
                $allDimFieldIDs[] = $fieldid;

                if ($field['dimNameField'] ?? null) {
                    foreach ($field['dimNameField'] as $key => $value) {
                        $allDimFieldNames[$fieldid] = isl_strtoupper($key);
                        $subtotalParams['selects'][] = isl_strtoupper($key);
                    }
                }
            }
        }

        if (!util_isPlatformDisabled()) {
            $custdim_fields_map = GLEntryManager::getPTFieldsMap();
            foreach ($custdim_fields_map as $field_name) {
                $subtotalParams['selects'][] = $field_name;
                $allDimFieldIDs[] = $field_name;
                $allDimFieldNames[$field_name] = isl_strtoupper($field_name);
            }
        }
        $subtotalParams['filters'] = [[['DOCHDRNO', '=', $dochdrkey]]];
        $subtotals = $docSubTotalsMgr->GetList($subtotalParams);
        $subtotalsByDisc = [];
        foreach ($subtotals as $subtotal) {
            $subtotalsByDisc[$subtotal['DESCRIPTION']][] = $subtotal;
        }

        $subtotalsWithCommonDims = [];
        foreach ($subtotalsByDisc as $dispKey => $subtotal) {
            if (count($subtotal) > 0) {
                $firstSubtotal = $subtotal[0];

                for ($i = 1; $i < count($subtotal); $i++) {
                    $tmp = array_intersect_assoc($firstSubtotal, $subtotal[$i]);
                    $firstSubtotal = $tmp;
                }

                $subtotalsWithCommonDims[$dispKey] = $firstSubtotal;
            }
        }

        foreach ($obj['SUBTOTALS'] as &$subtoal) {
            if ($subtotalsWithCommonDims[$subtoal['DESCRIPTION']]) {
                foreach ($allDimFieldIDs as $dimFieldID) {
                    $dimFeildName = $allDimFieldNames[$dimFieldID];

                    if (!array_key_exists($dimFieldID, $subtotalsWithCommonDims[$subtoal['DESCRIPTION']])) {
                        $subtoal[$dimFieldID] = '';
                        if ($dimFeildName != '') {
                            $subtoal[$dimFeildName] = '';
                        }

                        if (array_key_exists($dimFieldID.'_disp', $subtoal)) {
                            $subtoal[$dimFieldID.'_disp'] = '';
                        }
                    }
                }
            }
        }
        unset($subtotal);
    }

    /**
     * @param array $obj
     *
     * @return bool
     * @throws Exception
     */
    function GetDocHistory(&$obj)
    {
        global $gManagerFactory;
        $docHistMgr =    $gManagerFactory->getManager('dochistory');
        // history per transaction is always 1 record unless it is created from multiple source documents
        $basedoc = $obj['HISTORY'];

        // CCO -  source doc to show history for change doc
        $creinstalled = CRESetupManager::isCREInstalled();
        if ($creinstalled && isset($obj['HASCHANGE']) && $obj['HASCHANGE'] === "true") { // checking for CRE and Source Document with haschange (having change document)
            //To avoid multiple times calling the query and to improve the perforamnce as well. kind of getting the value from cache
            $currentObject = Request::$r->GetCurrentObject();
            if(empty($currentObject['HISTORY'])){
                $changeHistory= $docHistMgr->GetChangeDocList($obj['RECORDNO']);
                $otherHistory = $docHistMgr->GetHistoryList($basedoc[0]['BASEDOCKEY']);
                $fullHistory=array_merge($changeHistory,$otherHistory);
                $obj['HISTORY'] = $fullHistory;
            }
        } else {
            // if the document is converted from multiple transactions
            if ($this->checkIsCreatedFromMultipleSourceDocuments($obj, $sourceDockeys)) {
                $currentDocID = $obj['DOCID'];
                $currDocCount = 1;
                $docsInHistory = [];
                $baseDocKeys = [];

                foreach ($basedoc as $bDoc) {
                    if(!empty($bDoc['BASEDOCKEY'])) {
                        $baseDocKeys[] = $bDoc['BASEDOCKEY'];
                    }
                }
                $fullHistory = $docHistMgr->GetHistoryList($baseDocKeys);

                //
                // filter out the current document history details from history list as they are multiple
                // we will keep the first occurance and remove others and assign the text 'Multiple source transactions'
                foreach ($fullHistory as &$nHistory) {
                    if ($nHistory['DOCUMENTID'] == $currentDocID) {
                        if ($currDocCount > 1) {
                            continue;
                        }
                        $nHistory['SOURCEDOCUMENTID'] = ConversionManager::getmultipleSourceDocsText();
                        $currDocCount++;
                    }
                    $docsInHistory[] = $nHistory;
                }
                $fullHistory = $docsInHistory;
            } else {
                $fullHistory = $docHistMgr->GetHistoryList($basedoc[0]['BASEDOCKEY']);
            }
            $obj['HISTORY'] = $fullHistory;
        }

        return true;
    }

    /**
     * @param array $obj
     *
     * @throws Exception
     */
    public function prepareForUIEditValues(&$obj)
    {

        $obj['VIRTUALDOCPARID'] = $obj['DOCPARID'];
        $obj['VIRTUALWHENCREATED'] = ($obj['WHENCREATED']) ?: GetCurrentDate();
        $obj['VIRTUALDOCNO'] = $obj['DOCNO'];

        if ($obj['_DOCPAR']['ENABLEOVERRIDETAX']) {

            global $gManagerFactory;

            $shiptoname = $obj['SHIPTO']['CONTACTNAME'];

            $contactMgr = $gManagerFactory->getManager('contact');
            $shiptoraw = $contactMgr->GetRaw($shiptoname);
            $shiptoraw = $shiptoraw[0];

            $shiptotaxable = $shiptoraw['TAXABLE'];
            $shiptotaxgroupkey = $shiptoraw['TAXGROUPKEY'];

            $docparkey = $obj['_DOCPAR']['RECORDNO'];

            $entries = & $obj['ENTRIES'];

            $entryCnt = !is_array($entries) ? 0 : count($entries);

            $itemMgr = $gManagerFactory->getManager('item');

            $itemsArr = array();
            for ($j = 0; $j < $entryCnt; $j++) {
                if ($entries[$j]['ITEMID'] != '') {
                    [$itemid] = explode('--', $entries[$j]['ITEMID']);
                    if (!in_array($itemid, $itemsArr, true)) {
                        $itemsArr[] = $itemid;
                    }
                }
            }

            $itemRawCache = $itemMgr->GetItemsRawCache($itemsArr);

            for ($j = 0; $j < $entryCnt; $j++) {
                //eppp_p("ITEMID:".$entries[$j]['ITEMID']);

                if ($entries[$j]['ITEMID'] != '') {
                    [$itemid] = explode('--', $entries[$j]['ITEMID']);

                    if ($itemRawCache[$itemid] != '') {
                        $itemtaxgroupkey = $itemRawCache[$itemid]['TAXGROUPKEY'];

                        $obj['ENTRIES'][$j]['TAXCAPABLE'] = $itemMgr->IsTaxCapable(
                            $this->mod, $docparkey, $itemtaxgroupkey,
                            $shiptotaxable, $shiptotaxgroupkey
                        );
                    } else {
                        $obj['ENTRIES'][$j]['OVERRIDETAX'] = 'false';
                    }
                }
            }
        }
    }

    /**
     * Translate the custom field path to custom column name
     * This function is used in csvimport_scmdocument to translate the custom field values.
     *
     * @param  array $values the document values
     * @param array $pkgkeys
     *
     * @return bool
     */
    function TranslateCustomFields(&$values, &$pkgkeys)
    {
        if (!parent::TranslateCustomFields($values, $pkgkeys)) {
            return false;
        }

        // Convert line item custom field path to custom column name
        $ownedObjects = $this->GetOwnedObjects();
        foreach ($ownedObjects as $ownedObject) {
            $docentryMgr = $this->GetOwnedObjectManager($ownedObject['entity']);
            foreach ($values[$ownedObject['path']] as &$docentry) {
                if (!$docentryMgr->TranslateCustomFields($docentry, $pkgkeys)) {
                    return false;
                }
            }
        }
        return true;
    }


    /**
     * @param   bool    $details        do you want the DETAIL manager or the SUMMARY manager?
     *
     * @return DocumentSubTotalsManager
     */
    protected function getDocSubTotalsManager($details)
    {
        $subtotalentity = 'invdocumentsubtotals'; // note: there IS NO 'invdocumententrysubtotals'

        //Here we need detail level data for OE/PO subtotals and sodocumentsubtotals/podocumentsubtotals has summarized
        //view on top so detailed data can be fetched from sodocumententrysubtotals/podocumententrysubtotals
        //TODO:: Need to check with GA of PDLC-0531-13 that how the subtotals need to be displayed
        //If summarized for all then need to use sodocumentsubtotals/podocumentsubtotals
        //else @ MegaRoot -> sodocumentsubtotals/podocumentsubtotals & for rest sodocumentsubtotals/podocumentsubtotals
        if ($this instanceof SODocumentManager) {
            $subtotalentity = $details ? 'sodocumententrysubtotals' : 'sodocumentsubtotals';
        } else if ($this instanceof PODocumentManager) {
            $subtotalentity = $details ? 'podocumententrysubtotals' : 'podocumentsubtotals';
        }

        /** @var DocumentSubTotalsManager $dst */
        $dst = Globals::$g->gManagerFactory->getManager($subtotalentity);
        return $dst;
    }
    /**
     * Get a list of filled out objects (with lines) OLD
     *
     * @param  array $params the list params
     * @return array|null  $docs    the list
     */
    function GetListFull_OLD($params)
    {
        global $gManagerFactory;

        // for XML.  Look into somehow specifying this in the entity file.
        if (!isset($params['selects'])) {
            $params['selects'] = $this->GetGetFields();
        }
        if (!in_array('RECORDNO', $params['selects'])) {
            // this one is mandatory.
            // I guess I could remove it after the select
            $params['selects'][] = 'RECORDNO';
        }
        if ($this->mod === 'po') {
            $poMngr = $gManagerFactory->getManager('podocument', false, array( 'DOCTYPE' => $this->_docType));
            if ($poMngr->isDeliverToHeaderItemEnable()) {
                $params['selects'][] = 'DELIVERTO.CONTACTNAME';
            }
        }

        $docs = $this->GetList($params);

        // If there are no documents to process, return
        if (!count($docs)) {
            return null;
        }

        $docIDs = array();
        $docsByRecordNo = array();
        foreach ($docs as $doc) {
            $docsByRecordNo[$doc['RECORDNO']] = $doc;
            $docIDs[] = $doc['RECORDNO'];
        }

        /**
         * @var DocumentEntryManager    $docEntryMgr
         */
        $docEntryMgr = $gManagerFactory->getManager(
            $this->mod . 'documententry', false, array('DOCTYPE' => $this->_docType)
        );

        $docEntryMgr->fromGateway = $this->fromGateway;


        // added new fields to match getlist_metadata.2.1.inc request TM 02.13.08
        $entryParams = array(
            'selects' => array(
                'RECORDNO',
                'DOCHDRNO',
                'DOCUMENT.DOCID',
                'ITEMID',
                'ITEMDESC',
                'LINE_NO',
                'WAREHOUSE.LOCATION_NO',
                'QUANTITY',
                'UNIT',
                'LINELEVELSIMPLETAXTYPE',
                'PRICE',
                'TOTAL',
                'UIQTY',
                'UIPRICE',
                'RETAILPRICE',
                'UIVALUE',
                'PERCENTVAL',
                'TAXABSVAL',
                'LINETOTAL',
                'LOCATIONID',
                'DEPARTMENTID',
                'MEMO',
                'DISCOUNT_MEMO',
                'REVRECTEMPLATE',
                'REVRECSTARTDATE',
                'REVRECENDDATE',
                'RENEWALMACRO',
                'CURRENCY',
                'EXCHRATEDATE',
                'EXCHRATETYPE',
                'EXCHRATE',
                'TRX_PRICE',
                'TRX_VALUE',
                'TRX_LINETOTAL',
                'TASKKEY',
                'BILLINGTEMPLATE',
                'DISCOUNTPERCENT',
                'MULTIPLIER',
            ),
        );
        if ($this->mod == 'so') {
            $entryParams['selects'][] = 'NEEDBYDATE';
            $entryParams['selects'][] = 'SHIPBY';
            $entryParams['selects'][] = 'DONOTSHIPBEFOREDATE';
            $entryParams['selects'][] = 'DONOTSHIPAFTERDATE';
            $entryParams['selects'][] = 'DATEPICKTICKETPRINTED';
            $entryParams['selects'][] = 'CANCELAFTERDATE';
            $entryParams['selects'][] = 'SHIPPEDDATE';
            $entryParams['selects'][] = 'ITEMALIASID';
        }else if ($this->mod == 'po'){
            $entryParams['selects'][] = 'NEEDBYDATE';
            $entryParams['selects'][] = 'DONOTSHIPBEFOREDATE';
            $entryParams['selects'][] = 'DONOTSHIPAFTERDATE';
            $entryParams['selects'][] = 'PROMISEDDATE';
            $entryParams['selects'][] = 'DATECONFIRMED';
            $entryParams['selects'][] = 'CANCELAFTERDATE';
            $entryParams['selects'][] = 'DATESHIPTOSUPPLIER';
            $entryParams['selects'][] = 'ALLOCATION';
            $entryParams['selects'][] = 'ITEMALIASID';

            if($this->isReverseConversionAllowed()){
                $entryParams['selects'][] = 'REVERSECONVERSION';
                $entryParams['selects'][] = 'REVERSEPRICECONVERTED';
                $entryParams['selects'][] = 'REVERSEQTYCONVERTED';
                $entryParams['selects'][] = 'STDPRICECONVERTED';
                $entryParams['selects'][] = 'STDQTYCONVERTED';
            }

            if(CRESetupManager::isCREInstalled()){
                $entryParams['selects'][] = 'SOURCEDOCID';
                $entryParams['selects'][] = 'SOURCEDOCLINEID';
            }
        }
        //This method is no longer used so doing this to silence phpstorm warnings
        $taxEngine = GetTaxEngine($this->mod,null,$isVatEnabled);

        if ($taxEngine == 'AvaTax'){
            switch ($this->mod) {
                case 'so':
                    if ($this->isShipToLineItemEnable()) {
                        $entryParams['selects'][] = 'SHIPTO.CONTACTNAME';
                    }
                    break;
                case 'po':
                    $entryParams['selects'][] = 'TAXVALOVERRIDE';
                    if ($this->isShipToLineItemEnable()) {
                        $entryParams['selects'][] = 'DELIVERTO.CONTACTNAME';
                    }
                    break;
            }
        }

        $dimFields = $docEntryMgr->GetDimensionFields();
        if (is_array($dimFields)) {
            foreach ( $dimFields as $field) {
                if (!$field['standard']) {
                    continue;
                }
                $fieldid = isl_strtoupper($field['path']);
                $entryParams['selects'][] = $fieldid;
            }
        }
        $entryParams['selects'][] = 'BILLABLE';

        if (!util_isPlatformDisabled()) {
            $custdim_fields_map = GLEntryManager::getPTFieldsMap();
            foreach ( $custdim_fields_map as $field_name) {
                $entryParams['selects'][] = $field_name;
            }
        }

        $lineMacroFieldInfo = $docEntryMgr->getMacroFieldInfo();
        foreach ($lineMacroFieldInfo as $macroField) {
            $entryParams['selects'][] = $macroField['path'];
        }


        $entryParams['filters'] = array(array(array('DOCHDRNO', 'IN', $docIDs)));
        $entries = $docEntryMgr->GetList($entryParams);

        foreach ( $entries as $entry) {
            $docid = $entry['DOCHDRNO'];
            $this->formatCCOAPI21Entry($docsByRecordNo[$docid], $entry);
            $docsByRecordNo[$docid]['ENTRIES'][] = $entry;
        }

        $docSubTotalsMgr = $this->getDocSubTotalsManager(true);

        $subtotalParams = array(
            'selects' => array(
                'DOCHDRNO',
                'DESCRIPTION',
                'TOTAL',
                'ABSVAL',
                'PERCENTVAL',
                'LOCATIONID',
                'DEPARTMENTID',
                'DOCENTRYKEY'
            ),
        );

        $dimFields = $docSubTotalsMgr->GetDimensionFields();
        if (is_array($dimFields)) {
            foreach ( $dimFields as $field) {
                if (!$field['standard']) {
                    continue;
                }
                $fieldid = isl_strtoupper($field['path']);
                $subtotalParams['selects'][] = $fieldid;
            }
        }

        if (!util_isPlatformDisabled()) {
            $custdim_fields_map = GLEntryManager::getPTFieldsMap();
            foreach ( $custdim_fields_map as $field_name) {
                $subtotalParams['selects'][] = $field_name;
            }
        }

        $subtotalParams['filters'] = array(array(array('DOCHDRNO', 'IN', $docIDs)));
        $subtotals = $docSubTotalsMgr->GetList($subtotalParams);

        foreach ( $subtotals as $subtotal) {
            $docid = $subtotal['DOCHDRNO'];
            $docsByRecordNo[$docid]['SUBTOTALS'][] = $subtotal;
            if ($subtotal['DOCENTRYKEY'] != '') {
                //If DOCENTRYKEY exits then prepare value for line subtotals
                $docsByRecordNo[$docid]['SUBTOTALSENTRY'][] = $subtotal;
            }
        }

        $docs = array_values($docsByRecordNo);
        return $docs;
    }

    /**
     * Get a list of filled out objects (with lines)
     *
     * @param  array  $params the list params
     *
     * @return array    $docs    the list
     */
    function GetListFull($params)
    {
        if (!isset($params['selects'])) {
            $params['selects'] = $this->GetGetFields();
        }
        if (!in_array('RECORDNO', $params['selects'])) {
            // this one is mandatory.
            // I guess I could remove it after the select
            $params['selects'][] = 'RECORDNO';
        }

        $entryFields = array(
            'entry.itemkey', 'entry.itemdescr', 'entry.warehousekey', 'entry.uiqty',
            'entry.unit', 'entry.uiprice', 'entry.uivalue'
        );
        $params['selects'] = INTACCTarray_merge($params['selects'], $entryFields);

        $docs = $this->GetList($params);

        $docsByRecNo = array();
        foreach ( $docs as $doc) {
            $recno = $doc['RECORDNO'];
            if (!isset($docsByRecNo[$recno])) {
                $docsByRecNo[$recno] = $doc;
            }
            $newEntry = array(
                'ITEMID' => $doc['entry.itemkey'],
                'ITEMDESC' => $doc['entry.itemdescr'],
                'WAREHOUSE.LOCATION_NO' => $doc['entry.warehousekey'],
                'UIQTY' => $doc['entry.uiqty'],
                'UNIT' => $doc['entry.unit'],
                'UIPRICE' => $doc['entry.uiprice'],
                'UITOTAL' => $doc['entry.uivalue'],
            );
            $docsByRecNo[$recno]['ENTRIES'][] = $newEntry;
        }
        return $docsByRecNo;
    }

    /**
     * @var bool $canEditConvertDoc
     */
    var $canEditConvertDoc = false;



    /**
     *    This function provides ability to set query massaging if any needed onto the GetList of EM
     *    and here we use the same to bypass MEGA views for DOCHDR to get better
     *    performance at root level for unrestricted users only for lister script
     *    Here we change dochdr to its corresponding MSTs
     *
     * @access private
     *
     * @param array $params
     * @param string $_querytype
     * @param array  $qryarray
     *
     */
    function _ProcessFromClause($params, $_querytype, &$qryarray)
    {
        parent::_ProcessFromClause($params, $_querytype, $qryarray);

        if (ScriptName() == 'lister.phtml' && IsMultiEntityCompany()) {
            $fromTable = (GetContextLocation() || IsRestrictedUser()) ? 'dochdrlite' : 'dochdrmst';
            $qryarray['FROM']['STR'] = str_replace('dochdr ', "$fromTable ", $qryarray['FROM']['STR']);
        }
    }



    /**
     *    This function provides ability to set final conditions if any onto the GetList of EM
     *    and here we use the same to bypass MEGA views for DOCHDR to get better
     *    performance at root level for unrestricted users only for lister script with show private turned off
     *
     * @access private
     * @param  string $whereClause
     *
     * @return string
     * @throws
     */
    function _PostProcessWhereClause($whereClause)
    {
        $isLister = (ScriptName() == 'lister.phtml' ? true : false);

        if ($isLister && Request::$r->_showprivate != '1' && IsMultiEntityCompany() && !GetContextLocation() && !IsRestrictedUser()) {
            $whereClause .= " AND " . $this->_entity . ".MELOCATIONKEY IS NULL ";
        }

        return $whereClause;
    }

    /**
     *  to check the field is required
     *
     * @param array $values
     * @param array $fldinfo field info
     *
     * @return bool
     **/
    protected function isFieldRequired($values, $fldinfo)
    {
        //For Draft Mode we need to skip this
        if ( $this->isDraftDocument($values) ){
            return false;
        }
        return parent::isFieldRequired($values, $fldinfo);
    }

    /**
     * @param array $srcValues
     * @param array $values
     *
     * @return bool
     * @throws Exception
     */
    protected function postMacro($srcValues, &$values)
    {
        // don't post macro for documents in draft state
        if ( $this->isDraftDocument($values) ) {
            return true;
        }

        $ok = true;
        $postMacro = false;
        $macroPaths = $this->getMacroPaths();
        $macroNames = $this->getMacroNames();

        if (!empty($macroPaths)) {
            $postMacro = true;
        }

        $ownedObjects = $this->GetOwnedObjects();

        foreach ($ownedObjects as $ownedObject) {

            $this->_schemas[$ownedObject['entity']]['parententity'] = $this->_entity;
            $lineManager = $this->GetOwnedObjectManager($ownedObject['entity']);

            if ($lineManager instanceof DocumentEntryManager) {
                $macroPaths = INTACCTarray_merge($macroPaths, $lineManager->getMacroPaths());
                $macroNames = INTACCTarray_merge($macroNames, $lineManager->getMacroNames());
                if (!empty($macroPaths)) {
                    $postMacro = true;
                    break;
                }
            }
        }

        if ($postMacro)
        {
            $upsertStatus = self::$upsertFeaturInUse; // macro may reset the upsert status, so save it and restore it below

            // destroy subledger_handler, costing_handler etc
            ManagerFactory::PurgeObjectInstances();

            $gManagerFactory = Globals::$g->gManagerFactory;
            $scmMacroMgr     = $gManagerFactory->getManager('scmmacro');

            //collecting values that are assigned inside the manager
            $srcValues['EXISTING_DOC']      = $values['EXISTING_DOC'];
            $srcValues['EXISTING_ENTRIES']  = $values['EXISTING_ENTRIES'];
            $srcValues['SRCDOCPARRECORDNO'] = $values['_DOCPAR']['RECORDNO'];
            $srcValues['SRCDOCRECORDNO']    = $values['RECORDNO'];
            $srcValues['DOCID']             = $values['DOCID'];
            $srcValues['BILLTO']            = $values['BILLTO'];
            $srcValues['SHIPTO']            = $values['SHIPTO'];

            /**
             * The source transaction (most likly its sales document) may have posted COGS and to Subledger/ directly to GL
             * unset the references to any of the above before sending to DocumentManager::regularAdd();
             */
            unset($srcValues['INVBATCHKEY']);
            unset($srcValues['PRINVBATCHKEY']);
            unset($srcValues['ADDGLBATCHKEY']);
            unset($srcValues['PRRECORDKEY']);

            if (!is_null($srcValues['ENTRIES']))
            {
                foreach ($srcValues['ENTRIES'] as $key => &$entry)
                {
                    $entry['SRCDOCENTRYRECORDNO'] = $values['ENTRIES'][$key]['RECORDNO'];
                    $entry['TRX_PRICE']           = $values['ENTRIES'][$key]['TRX_PRICE'];
                    $entry['UIPRICE']             = $values['ENTRIES'][$key]['UIPRICE'];
                    $entry['TOTAL']               = ibcmul($values['ENTRIES'][$key]['PRICE'], $values['ENTRIES'][$key]['QUANTITY'], 2, true);
                    // If SO & PO line level is enabled then assign Line level SHIPTO to Line level DELIVERTO Dropship
                    if (self::GetPreferenceForProperty(Globals::$g->kSOid, 'SHIPTO_FOR_LINEITEM') == 'T')
                    {
                        if (self::GetPreferenceForProperty(Globals::$g->kPOid, 'DELIVERTO_FOR_LINEITEM') == 'T')
                        {
                            $entry['DELIVERTO'] = $entry['SHIPTO'];
                        }
                    }
                    //Remove overriden taxes
                    unset($entry['SUBTOTALSENTRY']);
                }
            }
            unset($entry);

            foreach ($macroPaths as $macrokey => $macroPath) {
                $macroName = $macroNames[$macrokey];
                $ok = $ok && $this->prepareMacroValues($macroName, $macroPath, $srcValues, $values);
                $ok = $ok && $scmMacroMgr->postMacro($srcValues['DOCPARID'], $srcValues, $macroName, $macroPath);
            }

            self::$upsertFeaturInUse = $upsertStatus;   // restore the existing upsert status
        }

        return $ok;
    }

    /**
     * @param string $macroName
     * @param string $macroPath
     * @param array  $srcValues
     * @param array  $values
     *
     * @return bool
     */
    protected function prepareMacroValues(
        /** @noinspection PhpUnusedParameterInspection */ $macroName,
        /** @noinspection PhpUnusedParameterInspection */ $macroPath,
        /** @noinspection PhpUnusedParameterInspection */ &$srcValues,
        /** @noinspection PhpUnusedParameterInspection */ $values
    )
    {
        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function afterPostings(&$values)
    {
        $ok = $this->CreateDocumentPDF($values);
        return $ok;
    }

    /**
     * Figure out if the document is a draft document
     *
     * @param array $values the transaction data
     *
     * @return bool true if the document is a draft else false
     */
    protected function isDraftDocument($values)
    {
        return ( in_array($values['STATE'], [ self::DRAFT_STATE, self::ANALYZING_STATE ]) );
    }

    /**
     * Validate dimension values for all owned objects
     *
     * @param array $values the object values
     *
     * @return bool  true on success and false on failure
     */
    public function ValidateDimensions(&$values)
    {
        //We should skip this validation for Draft document
        if ($this->isDraftDocument($values)) {
            return true;
        }

        return parent::ValidateDimensions($values);
    }

    /**
     * Validate dimension values for all owned objects for draft document
     *
     * @param array $values the object values
     *
     * @return bool  true on success and false on failure
     */
    protected function subtotalvalidationForDraft(array $values): bool
    {
        $ok = true;

        // For draft documents, it is essential to validate on dimension visibility restrictions.
        // This validation will determining whether to skip the 'PrepareSubTotalsValues' calculation or not.
        if ($this->isDraftDocument($values)) {
            $ownedObjects = $this->GetOwnedObjects();
            if (is_array($ownedObjects)) {
                foreach ($ownedObjects as $objRec) {
                    $ok = $ok && $this->ValidateDimensionsMultiVisibility($values, $objRec['entity'], $objRec['path']);
                    $ok = $ok && $this->ValidateDimensionsOnOwnedObject($values, $objRec['entity'], $objRec['path']);

                    if (!$ok) {
                        return false;
                    }
                }
            }
        }

        return $ok;
    }

    /**
     * Add the document transaction.
     * Prepares the values, validates the values, advanced processing on the values, Add the values.
     * Post process document, Process the document history in the dochistory table and cleanup the template version if no transaction are avbl.
     *
     * @param  array &$values array of the values of the document.
     *
     * @return bool returns if the method execution was success or not.
     */
    protected function regularAdd(&$values)
    {
        self::$upsertFeaturInUse = false;   // just to be clear

        $benchmark = Globals::$g->gIABenchmark;
        $benchmark->startTimer('DocumentManager::Add', $this);

        $values['DOCPARID'] = $values['DOCPARID'] ?? $this->getDocType();
        $postedValues = $values;
        $source = "DocumentManager::Add";

        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $handlers = array();

        $this->_substatecache['SFORCEID'] = $values['SFORCEID'];

        if (!$this->acquireLocksIfNecessary($locks, $values)) {
            return false;
        }

        if (!$values['_mod'] && isset($this->mod)) {
            $values['_mod'] = $this->mod;
        }

        if (!$this->getDocumentParams($values)){
            return false;
        }

        if (!$this->validateAuthorization($values)) {
            return false;
        }

        // validate analyzing state only for PO match enabled documents
        if ( ! $this->validateAnalyzingState($values) ) {
            return false;
        }

        $this->setSCMTrigger(true);
        // Attempt to make it as modular as possible
        $ok = $this->_QM->beginTrx($source);

        if (($values['BACKORDER'] ?? '') != 'Yes') {
            $ok = $ok && ConversionManager::validateConversion($values);
        }

        ProjectManager::enableDeferredProjectTotals();

        $ok = $ok && $this->ValidateAfterFormat($values);

        $benchmark->startTimer('PrepValues', $this, $this);
        $ok = $ok && $this->PrepValues($values, $handlers, true, $getTaxRequest, $entityTaxable);
        if (isNonEmptyArray($values['SUMMARIZEDENTRIES_TOCONVERT']) &&
            isNonEmptyArray($values['SUMMARIZEDENTRIES_TOCONVERT']['ENTRIES'])
        ) {
            $ok = $ok && $this->PrepValues($values['SUMMARIZEDENTRIES_TOCONVERT'], $handlers, true, $getTaxRequest, $entityTaxable);
        }
        $benchmark->stopTimer();

        $ok = $ok && $this->processChangeOrder($values, false);
        $ok = $ok && $this->convertAdditionalInfoVidtoKey($values);
        $ok = $ok && $this->processPCB($values);
        $ok = $ok && $this->processReverseConversion($values);

        if (VendorComplianceSetupManager::isVendorComplianceV2Enabled()) {
            //uset the fuctnin isDraftDocument
            if ( ! $this->isDraftDocument($values) ){
                $ok = $ok && $this->validateVendorCompliance_DocSave($values, $values['_DOCPAR']['UPDATES_GL'] != 'N');
            }
        }
        $ok = $ok && $this->checkForNegativeInventory($values, 'A', true);    // about to 'go negative'?

        $benchmark->startTimer('EntityManager::Add', $this);
        $ok = $ok && parent::regularAdd($values);
        $ok = $ok && $this->updateDocumentCalcRetainageType($values);
        $benchmark->stopTimer();

        $otherParams = [];
        $otherParams['POSTEDVALUES'] = $postedValues;
        $otherParams['ISUPDATE'] = false;
        /** @noinspection PhpUndefinedVariableInspection */
        $otherParams['TAX_REQUEST'] = $getTaxRequest;
        /** @noinspection PhpUndefinedVariableInspection */
        $otherParams['ENTITY_TAXABLE'] = $entityTaxable;

        $ok = $ok && $this->PostProcessDocument($values, $otherParams);

        if (self::isDocumentInPostingState($values['STATE'])) {
            $benchmark->startTimer('Post', $this, $this);
            $ok = $ok && $this->Post($values, $otherParams);
            $benchmark->stopTimer();
        }

        if (self::shouldWeCreateComplianceRecordsForPrimaryDoc($values['STATE'])) {
            $ok = $ok && $this->createComplianceRecordsForPrimaryDoc($values, $this->_unlinkedComplianceRecords);
        }

        $this->releaseLocksIfNecessary($locks);

        $ok = $ok && $this->afterPostings($values);

        $ok = $ok && $this->checkForNegativeInventory($values, 'A', false);    // did we just 'go negative'?

        //***NEED TO BE SET TO NOT DEQUEUE IMS REQUEST IN CASE OF ERROR.
        $subscription =  $gManagerFactory->getManager('imssubscription');

        // do *not* add error if it has only warnings
        if (!$ok && !HasErrors() && HasWarnings()) {
            $this->_QM->rollbackTrx($source);
            $subscription->noDequeue = true;
            $ok = false;
        } else {
            // cache the values for auditing to avoid an extra read
            $auditTrailSession = AuditTrailSession::getInstance();
            $auditTrailSession->cacheAuditRecord($this->getAuditEntity(), $this->GetKeyValue($values), $values);


            $ok = $ok && $this->_QM->commitTrx($source);
            if (!$ok) {
                if (Request::$r->_kNoWarn != 'true' && Request::$r->_kNoDupl != 'true') {
                    $msg = "Could not create Document record!";
                    $gErr->addIAError('INV-1253', __FILE__ . ':' . __LINE__, $msg, []);
                    epp("$source: Error: $msg");
                }
                $subscription->noDequeue = true;
                $this->_QM->rollbackTrx($source);
                $values = $postedValues;
            } else {

                // Add a return message for SFORCE derived creations
                ProcessSforceResult("created", $values);
            }

        }


        $benchmark->stopTimer();
        return $ok;
    }

    /**
     * @param [] $values
     *
     * @return bool
     */
    private function convertAdditionalInfoVidtoKey(&$values){
        $ok = true;
        $gErr = Globals::$g->gErr;
        $removeFields = false;
        if($this->mod == 'po' || $this->mod == 'so'){
            $copyMode = Request::$r->_copymode;
            if(($values['CREATEDFROM']  && $values['CREATEDFROM'] != '') || ($copyMode && $copyMode == 'Copy')){
                $removeFields = true;
            }
            $docId = $values['DOCID'];
            $docClass = $values['_DOCPAR']['DOCCLASS'];
            if(CRESetupManager::isCREInstalled()){
                if(in_array($values['_DOCPAR']['DOCCLASS'],['Order','Quote'])){
                    $enableAddInfoScope = $values['_DOCPAR']['ENABLEADDINFOSCOPE'] ?? 'false';
                    if($enableAddInfoScope != 'true' && $enableAddInfoScope != 'T' ){
                        $addInfoFields = self::getAdditionalInfoFields('SCOPE');
                        foreach($addInfoFields as $field){
                            if($values[$field] && $values[$field] != ''){
                                if($removeFields){
                                    unset($values[$field]);
                                }else{
                                    $msg = "Please enable scope in $docId to use the $field";
                                    $gErr->addIAError('INV-1254', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                    return false;
                                }

                            }
                        }
                    }
                    $enableAddInfoSchedule = $values['_DOCPAR']['ENABLEADDINFOSCHEDULE'] ?? 'false';
                    if($enableAddInfoSchedule != 'true' && $enableAddInfoSchedule != 'T' ){
                        $addInfoFields = self::getAdditionalInfoFields('SCHEDULE');
                        foreach($addInfoFields as $field){
                            if($values[$field] && $values[$field] != ''){
                                if($removeFields){
                                    unset($values[$field]);
                                }else {
                                    $msg = "Please enable schedule in $docId to use the $field";
                                    $gErr->addIAError('INV-1255', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                    return false;
                                }
                            }
                        }
                    }
                    $enableAddInfoInternalRef = $values['_DOCPAR']['ENABLEADDINFOINTERNALREF'] ?? 'false';
                    if($enableAddInfoInternalRef== 'true' || $enableAddInfoInternalRef == 'T'){
                        $transArr = ['INTERNALINITIATEDBYKEY' => 'INTERNALINITIATEDBY','INTERNALVERBALBYKEY' => 'INTERNALVERBALBY','INTERNALISSUEDBYKEY' => 'INTERNALISSUEDBY',
                            'INTERNALAPPROVEDBYKEY' => 'INTERNALAPPROVEDBY', 'INTERNALSIGNEDBYKEY' => 'INTERNALSIGNEDBY'];
                        $ok = $this->translateFromVidToKey('employeeid', 'employee', $transArr, $values);
                        if(!$ok){
                            return false;
                        }
                    }
                    else{
                        $addInfoFields = self::getAdditionalInfoFields('INTERNALREF');
                        foreach($addInfoFields as $field){
                            if($values[$field] && $values[$field] != ''){
                                if($removeFields){
                                    unset($values[$field]);
                                }else {
                                    $msg = "Please enable internal reference in $docId  to use the $field";
                                    $gErr->addIAError('INV-1256', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);

                                    return false;
                                }
                            }
                        }
                    }

                    $enableAddInfoExternalRef = $values['_DOCPAR']['ENABLEADDINFOEXTERNALREF'] ?? 'false';
                    if($enableAddInfoExternalRef == 'true' || $enableAddInfoExternalRef == 'T' ){
                        $transArr = ['EXTERNALVERBALBYKEY' => 'EXTERNALVERBALBY','EXTERNALAPPROVEDBYKEY' => 'EXTERNALAPPROVEDBY','EXTERNALSIGNEDBYKEY' => 'EXTERNALSIGNEDBY'];
                        $ok = $this->translateFromVidToKey('name', 'contact', $transArr, $values);
                        if(!$ok){
                            return false;
                        }
                    }
                    else{
                        $addInfoFields = self::getAdditionalInfoFields('EXTERNALREF');
                        foreach($addInfoFields as $field){
                            if($values[$field] && $values[$field] != ''){
                                if($removeFields){
                                    unset($values[$field]);
                                }else {
                                    $msg = "Please enable external reference in $docId to use the $field";
                                    $gErr->addIAError('INV-1257', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);

                                    return false;
                                }
                            }
                        }
                    }

                    $enableAddInfoBond = $values['_DOCPAR']['ENABLEADDINFOBOND'] ?? 'false';
                    if($enableAddInfoBond == 'true' || $enableAddInfoBond == 'T' ){
                        $pattern = '/^(-{0,1}[0-9]{0,21})(([,.]{1})([0-9]{0,2}))?$/';
                        $transArr = ['PERFORMANCESURETYCOMPANYKEY' => 'PERFORMANCESURETYCOMPANY','PAYMENTSURETYCOMPANYKEY' => 'PAYMENTSURETYCOMPANY'];
                        if(isset($values['PAYMENTBONDAMOUNT']) && $values['PAYMENTBONDAMOUNT'] != ''){
                            if (!isl_preg_match($pattern, $values['PAYMENTBONDAMOUNT'])) {
                                $msg = "Exceeding max limit in PAYMENTBONDAMOUNT, allowed limit is 21 digits with 2 decimal digits";
                                $gErr->addIAError('INV-1258', __FILE__ . ':' . __LINE__, $msg, []);
                                return false;
                            }
                        }
                        if(isset($values['PERFORMANCEBONDAMOUNT']) && $values['PERFORMANCEBONDAMOUNT'] != ''){
                            if (!isl_preg_match($pattern, $values['PERFORMANCEBONDAMOUNT'])) {
                                $msg = "Exceeding max limit in PERFORMANCEBONDAMOUNT, allowed limit is 21 digits with 2 decimal digits";
                                $gErr->addIAError('INV-1259', __FILE__ . ':' . __LINE__, $msg, []);
                                return false;
                            }
                        }
                        $ok = $this->translateFromVidToKey('vendorid', 'vendor', $transArr, $values);
                        if(!$ok){
                            return false;
                        }
                    }
                    else{
                        $addInfoFields = self::getAdditionalInfoFields('BOND');
                        foreach($addInfoFields as $field){
                            if($values[$field] && ($values[$field] != '' && $values[$field] != 'false')){
                                if($removeFields){
                                    unset($values[$field]);
                                }else {
                                    $msg = "Please enable bond in $docId to use the $field";
                                    $gErr->addIAError('INV-1260', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);

                                    return false;
                                }
                            }
                        }
                    }
                }else{
                    $addInfoFields = self::getAdditionalInfoFields();
                    foreach($addInfoFields as $field){
                        if($values[$field] && ($values[$field] != '' && $values[$field] != 'false')){
                            if($removeFields){
                                unset($values[$field]);
                            }else {
                                $msg = "you cannot use $field in $docClass document type";
                                $gErr->addIAError('INV-1261', __FILE__ . ':' . __LINE__, $msg, ['FIELD' => $field, 'DOC_CLASS' => $docClass]);

                                return false;
                            }
                        }
                    }
                }
            }
            else{
                $addInfoFields = self::getAdditionalInfoFields();
                foreach($addInfoFields as $field){
                    if(isset($values[$field]) && ($values[$field] != '' && $values[$field] != 'false')){
                        $gErr->addIAError('INV-1321', __FILE__ . ':' . __LINE__,
                            " Construction subscription required", [],
                            "The $field field are valid only when you have a subscription to Construction.", ['VALUE' => $field],
                            "Either remove these fields or subscribe to the Construction application and try again", []
                        );
                        return false;
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * @param array $values
     * @param array $oldValues
     *
     * @return bool
     */
    protected function convertAdditionalInfoVidtoKeyUpdate(&$values,$oldValues){
        $ok = true;
        $gErr = Globals::$g->gErr;
        if($this->mod == 'po' || $this->mod == 'so'){
            $docId = $values['DOCID'];
            $docClass = $values['_DOCPAR']['DOCCLASS'];
            if(CRESetupManager::isCREInstalled()){
                if(in_array($values['_DOCPAR']['DOCCLASS'],['Order','Quote'])){
                    $addInfoScopeFields = self::getAdditionalInfoFields('SCOPE');
                    $enableAddInfoScope = $values['_DOCPAR']['ENABLEADDINFOSCOPE'] ?? 'false';
                    foreach($addInfoScopeFields as $field){
                        if($values[$field] && $values[$field] != ''){
                            if($oldValues[$field] == '' && $enableAddInfoScope == 'false'){
                                $msg = "Please enable scope in $docId to use the $field";
                                $gErr->addIAError('INV-1262', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                return false;
                            }
                        }
                    }

                    $addInfoScheduleFields = self::getAdditionalInfoFields('SCHEDULE');
                    $enableAddInfoSchedule = $values['_DOCPAR']['ENABLEADDINFOSCHEDULE'] ?? 'false';
                    foreach($addInfoScheduleFields as $field){
                        if($values[$field] && $values[$field] != ''){
                            if($oldValues[$field] == '' && $enableAddInfoSchedule == 'false'){
                                $msg = "Please enable schedule in $docId to use the $field";
                                $gErr->addIAError('INV-1263', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                return false;
                            }
                        }
                    }

                    $addInfoInternalRefFields = self::getAdditionalInfoFields('INTERNALREF');
                    $enableAddInfoInternalRef = $values['_DOCPAR']['ENABLEADDINFOINTERNALREF'] ?? 'false';
                    $addInfoIntRef = [];
                    foreach($addInfoInternalRefFields as $field){
                        if($values[$field] && $values[$field] != ''){
                            if($oldValues[$field] == '' && $enableAddInfoInternalRef == 'false'){
                                $msg = "Please enable internal reference in $docId to the $field";
                                $gErr->addIAError('INV-1264', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                return false;
                            }else{
                                $addInfoIntRef[] = $field;
                            }
                        }
                    }
                    if(count($addInfoIntRef) > 0){
                        $transArr = ['INTERNALINITIATEDBYKEY' => 'INTERNALINITIATEDBY','INTERNALVERBALBYKEY' => 'INTERNALVERBALBY','INTERNALISSUEDBYKEY' => 'INTERNALISSUEDBY',
                            'INTERNALAPPROVEDBYKEY' => 'INTERNALAPPROVEDBY', 'INTERNALSIGNEDBYKEY' => 'INTERNALSIGNEDBY'];
                        $ok = $this->translateFromVidToKey('employeeid', 'employee', $transArr, $values);
                        if(!$ok){
                            return false;
                        }
                    }

                    $addInfoExternalRefFields = self::getAdditionalInfoFields('EXTERNALREF');
                    $enableAddInfoExternalRef = $values['_DOCPAR']['ENABLEADDINFOEXTERNALREF'] ?? 'false';
                    $addInfoExtRef = [];
                    foreach($addInfoExternalRefFields as $field){
                        if($values[$field] && $values[$field] != ''){
                            if($oldValues[$field] == '' && $enableAddInfoExternalRef == 'false'){
                                $msg = "Please enable external reference in $docId to use the $field";
                                $gErr->addIAError('INV-1265', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                return false;
                            }else{
                                $addInfoExtRef[] = $field;
                            }
                        }
                    }

                    if(count($addInfoExtRef) > 0){
                        $transArr = ['EXTERNALVERBALBYKEY' => 'EXTERNALVERBALBY','EXTERNALAPPROVEDBYKEY' => 'EXTERNALAPPROVEDBY','EXTERNALSIGNEDBYKEY' => 'EXTERNALSIGNEDBY'];
                        $ok = $this->translateFromVidToKey('name', 'contact', $transArr, $values);
                        if(!$ok){
                            return false;
                        }
                    }

                    $addInfoBondFields = self::getAdditionalInfoFields('BOND');
                    $enableAddInfoBond = $values['_DOCPAR']['ENABLEADDINFOBOND'] ?? 'false';
                    $addInfoBond = [];
                    $pattern = '/^(-{0,1}[0-9]{0,21})(([,.]{1})([0-9]{0,2}))?$/';
                    foreach($addInfoBondFields as $field){
                        if($values[$field] && ($values[$field] != '' && $values[$field] != 'false')){
                            if(($oldValues[$field] == '' || $oldValues[$field] == 'false' ) && $enableAddInfoBond == 'false'){
                                $msg = "Please enable bond in $docId to use the $field";
                                $gErr->addIAError('INV-1266', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId, 'FIELD' => $field]);
                                return false;
                            }
                            if($field == 'PAYMENTBONDAMOUNT' && $values['PAYMENTBONDAMOUNT'] && $values['PAYMENTBONDAMOUNT'] != ''){
                                if (!isl_preg_match($pattern, $values['PAYMENTBONDAMOUNT'])) {
                                    $msg = "Exceeding max limit in PAYMENTBONDAMOUNT, allowed limit is 21 digits with 2 decimal digits";
                                    $gErr->addIAError('INV-1267', __FILE__ . ':' . __LINE__, $msg, []);
                                    return false;
                                }
                            }
                            if($field == 'PERFORMANCEBONDAMOUNT' &&  $values['PERFORMANCEBONDAMOUNT'] && $values['PERFORMANCEBONDAMOUNT'] != ''){
                                if (!isl_preg_match($pattern, $values['PERFORMANCEBONDAMOUNT'])) {
                                    $msg = "Exceeding max limit in PERFORMANCEBONDAMOUNT, allowed limit is 21 digits with 2 decimal digits";
                                    $gErr->addIAError('INV-1268', __FILE__ . ':' . __LINE__, $msg, []);
                                    return false;
                                }
                            }
                            $addInfoBond[] = $field;
                        }
                    }

                    if(count($addInfoBond) > 0){
                        $transArr = ['PERFORMANCESURETYCOMPANYKEY' => 'PERFORMANCESURETYCOMPANY','PAYMENTSURETYCOMPANYKEY' => 'PAYMENTSURETYCOMPANY'];
                        $ok = $this->translateFromVidToKey('vendorid', 'vendor', $transArr, $values);
                        if(!$ok){
                            return false;
                        }
                    }
                }else{
                    $addInfoFields = self::getAdditionalInfoFields();
                    foreach($addInfoFields as $field){
                        if($values[$field] && ($values[$field] != '' && $values[$field] != 'false')){
                            $msg = "you cannot use $field in $docClass document type";
                            $gErr->addIAError('INV-1269', __FILE__ . ':' . __LINE__, $msg, ['FIELD' => $field, 'DOC_CLASS' => $docClass]);
                            return false;
                        }
                    }
                }
            }
            else{
                $addInfoFields = self::getAdditionalInfoFields();
                foreach($addInfoFields as $field){
                    if($values[$field] && ($values[$field] != '' && $values[$field] != 'false')){
                        $gErr->addIAError('INV-0282', __FILE__ . ':' . __LINE__,
                            " Construction subscription required", [],
                            "The $field field are valid only when you have a subscription to Construction.", ['VALUE' => $field],
                            "Either remove these fields or subscribe to the Construction application and try again", []
                        );
                        return false;
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * @param string $vid
     * @param string $table
     * @param array $transArr
     * @param array $values
     *
     * @return bool
     */
    function translateFromVidToKey($vid, $table, $transArr, &$values){
        $ok = true;
        $gErr = Globals::$g->gErr;
        $cny = GetMyCompany();
        $table = strtoupper($table);
        $vid = strtoupper($vid);
        $emp = [];
        $sql = [];
        $fieldID = false;
        if(isl_substr($vid,-2) == 'ID'){
            $fieldID = true;
        }

        $sql[0] = "SELECT  RECORD#, $vid, STATUS FROM $table WHERE CNY# = :1";
        $sql[1] = $cny;

        foreach ($transArr as $tranVal) {
            if(isset($values[$tranVal]) && !in_array($values[$tranVal],$emp,TRUE)) {
                if($fieldID){
                    [$id] = explode('--',$values[$tranVal]);
                    $emp[] = $id;
                }else{
                    $emp[] = $values[$tranVal];
                }
            }
        }

        if($emp) {
            $stmt = PrepINClauseStmt($sql, $emp, " AND $vid ");
            $result = QueryResult($stmt);
            $vidList = array_column($result, $vid);
            foreach ($transArr as $trankey =>  $tranVal) {
                if(isset($values[$tranVal]) && $values[$tranVal] != ''){
                    if($fieldID){
                        [$id] = explode('--',$values[$tranVal]);
                        $val = $id;
                    }else{
                        $val = $values[$tranVal];
                    }
                    $key = array_search($val, $vidList, TRUE);
                    if($key !== false) {
                        if($result[$key]['STATUS'] == 'T'){
                            $values[$trankey] = $result[$key]['RECORD#'];
                        }
                        else{
                            $msg = "Inactive $vid is given in $tranVal";
                            $gErr->addIAError('INV-1270', __FILE__ . ':' . __LINE__, $msg, ['VID' => $vid, 'TRAN_VAL' => $tranVal]);
                            return false;
                        }
                    }
                    else{
                        $msg = "Invalid $vid is given in $tranVal";
                        $gErr->addIAError('INV-1271', __FILE__ . ':' . __LINE__, $msg, ['VID' => $vid, 'TRAN_VAL' => $tranVal]);
                        return false;
                    }
                }
            }
        }

        return $ok;

    }

    /**
     * @param string|null $section
     *
     * @return array
     */
    public static function getAdditionalInfoFields($section = null){

        switch(strtolower($section)){
            case 'scope':
                $addInfoFields = ['SCOPE','INCLUSIONS','EXCLUSIONS','TERMS'];
                break;
            case 'schedule':
                $addInfoFields = ['SCHEDULESTARTDATE','ACTUALSTARTDATE','SCHEDULEDCOMPLETIONDATE','REVISEDCOMPLETIONDATE','SUBSTANTIALCOMPLETIONDATE','ACTUALCOMPLETIONDATE','NOTICETOPROCEED',
                    'RESPONSEDUE','EXECUTEDON','SCHEDULEIMPACT'];
                break;
            case 'internalref':
                $addInfoFields = ['INTERNALREFNO','INTERNALINITIATEDBYKEY','INTERNALINITIATEDBY','INTERNALINITIATEDBYNAME','INTERNALVERBALBYKEY','INTERNALVERBALBY','INTERNALVERBALBYNAME','INTERNALISSUEDBYKEY','INTERNALISSUEDBY',
                    'INTERNALISSUEDBYNAME','INTERNALISSUEDON','INTERNALAPPROVEDBYKEY','INTERNALAPPROVEDBY','INTERNALAPPROVEDBYNAME','INTERNALAPPROVEDON','INTERNALSIGNEDBYKEY','INTERNALSIGNEDBY','INTERNALSIGNEDBYNAME',
                    'INTERNALSIGNEDON','INTERNALSOURCE','INTERNALSOURCEREFNO'];
                break;
            case 'externalref':
                $addInfoFields = ['EXTERNALREFNO','EXTERNALVERBALBYKEY','EXTERNALVERBALBY','EXTERNALVERBALBYNAME','EXTERNALAPPROVEDBYKEY','EXTERNALAPPROVEDBY','EXTERNALAPPROVEDBYNAME','EXTERNALAPPROVEDON','EXTERNALSIGNEDBYKEY',
                    'EXTERNALSIGNEDBY','EXTERNALSIGNEDBYNAME','EXTERNALSIGNEDON'];
                break;
            case 'bond':
                $addInfoFields = ['PERFORMANCEBONDREQUIRED','PERFORMANCEBONDRECEIVED','PERFORMANCEBONDAMOUNT','PERFORMANCESURETYCOMPANYKEY','PERFORMANCESURETYCOMPANY','PERFORMANCESURETYCOMPANYNAME','PAYMENTBONDREQUIRED','PAYMENTBONDRECEIVED',
                    'PAYMENTBONDAMOUNT','PAYMENTSURETYCOMPANYKEY','PAYMENTSURETYCOMPANY','PAYMENTSURETYCOMPANYNAME'];
                break;
            case 'dbfields':
                $addInfoFields = ['scope','inclusions','exclusions','terms','schedule_start_date','actual_start_date','scheduled_completion_date','revised_completion_date','substantial_completion_date','actual_completion_date',
                                  'notice_to_proceed','response_due','executed_on','schedule_impact','internal_ref_no','internal_initiatedby_key','internal_verbalby_key','internal_issuedby_key','internal_issuedon','internal_approvedby_key',
                                  'internal_approvedon','internal_signedby_key','internal_signedon','internal_source','internal_source_refno','external_refno','external_verbalby_key','external_approvedby_key','external_approvedon',
                                  'external_signedby_key','external_signedon','per_bond_required','per_bond_received','per_bond_amount','per_surety_companykey',
                                  'pay_bond_required','pay_bond_received','pay_bond_amount','pay_surety_companykey'];
                break;
            default:
                $addInfoFields = ['SCOPE','INCLUSIONS','EXCLUSIONS','TERMS','SCHEDULESTARTDATE','ACTUALSTARTDATE','SCHEDULEDCOMPLETIONDATE','REVISEDCOMPLETIONDATE','SUBSTANTIALCOMPLETIONDATE','ACTUALCOMPLETIONDATE','NOTICETOPROCEED',
                    'RESPONSEDUE','EXECUTEDON','SCHEDULEIMPACT','INTERNALREFNO','INTERNALINITIATEDBYKEY','INTERNALINITIATEDBY','INTERNALVERBALBYKEY','INTERNALVERBALBY','INTERNALISSUEDBYKEY','INTERNALISSUEDBY','INTERNALISSUEDON',
                    'INTERNALAPPROVEDBYKEY','INTERNALAPPROVEDBY','INTERNALAPPROVEDON','INTERNALSIGNEDBYKEY','INTERNALSIGNEDBY','INTERNALSIGNEDON','INTERNALSOURCE','INTERNALSOURCEREFNO','EXTERNALREFNO','EXTERNALVERBALBYKEY',
                    'EXTERNALVERBALBY','EXTERNALAPPROVEDBYKEY','EXTERNALAPPROVEDBY','EXTERNALAPPROVEDON','EXTERNALSIGNEDBYKEY','EXTERNALSIGNEDBY','EXTERNALSIGNEDON','PERFORMANCEBONDREQUIRED','PERFORMANCEBONDRECEIVED',
                    'PERFORMANCEBONDAMOUNT','PERFORMANCESURETYCOMPANYKEY','PERFORMANCESURETYCOMPANY','PAYMENTBONDREQUIRED','PAYMENTBONDRECEIVED','PAYMENTBONDAMOUNT','PAYMENTSURETYCOMPANYKEY','PAYMENTSURETYCOMPANY',
                    'INTERNALINITIATEDBYNAME','INTERNALVERBALBYNAME','INTERNALISSUEDBYNAME','INTERNALAPPROVEDBYNAME','INTERNALSIGNEDBYNAME','EXTERNALVERBALBYNAME','EXTERNALAPPROVEDBYNAME','EXTERNALSIGNEDBYNAME',
                    'PERFORMANCESURETYCOMPANYNAME','PAYMENTSURETYCOMPANYNAME','CHANGELOGNUMBER'];
                break;
        }

        return $addInfoFields;
    }


    /**
     * @return array
     */
    public function GetDimensionFields()
    {
        $dimFields = parent::GetDimensionFields();

        if (!isNullOrBlank($dimFields['task'] ?? null)) {
            $dimFields['task']['dimdbkey'] = 'TASKKEY';
        }

        return $dimFields;
    }

    /**
     * @return array
     */
    protected function getDimensionFieldName2RecordNoFieldNameMap()
    {
        $map = parent::getDimensionFieldName2RecordNoFieldNameMap();
        $map['TASKID'] = 'TASKKEY';

        return $map;
    }


    /**
     *  Are there allocation entries in the list of entries?
     *
     * @param array $entries        the entries from the document
     *
     * @return bool                 yes or no?
     */
    public function anyAllocationEntries($entries)
    {
        foreach ($entries as $line) {
            if((isset($line['ALLOCATIONKEY']) && $line['ALLOCATIONKEY'] == 0)) {
                return true;
            }

            if ((isset($line['ALLOCATION']) && $line['ALLOCATION'] != '')) {
                return true;
            }
        }
        return false;
    }


    /**
     *  Do certain changes in the document header imply that the line items should be written and not ignored if
     *  they are identical?  Like if you change the state or document TD.
     *
     * @param array     $values     the document tree
     *
     * @return bool
     */
    protected function doChangesSuggestUpdatingAllLines($values)
    {
        // can we NOT update docentrys and others that are identical?
        // If the DOCPAR changes, let's make sure we at least write out all the docentry's
        $newDocidRecordNumber = $values['_DOCPAR']['RECORDNO'] ?? 0;    // current number
        $oldDocidRecordNumber = $values['EXISTING_DOC']['DOCPARKEY'] ?? 0;    // number from the existing txn
        if ($oldDocidRecordNumber != $newDocidRecordNumber) {
            return true;
        }

        $riskyChanges = [
            'STATE',            // when the state changes (from DRAFT to NOT DRAFT, say)
            'CREATEDFROM',      // why would this change?  Dunno
            'SHIPTOKEY',        // may affect line items shipto??
            'BILLTOKEY',
            'ENTGLGROUP',
            'CURRENCY',         // these could change TRX_ values
            'EXCHRATEDATE',
            'EXCHRATE',
            'EXCH_RATE_TYPE_ID',
            'TAXSOLUTIONKEY',
            'TAXSOLUTIONID',
            'TAXMETHOD',
            'WHENPOSTED',
        ];
        foreach ($riskyChanges as $riskyChange) {
            $before = $values['EXISTING_DOC'][$riskyChange] ?? '';
            $now    = $values[$riskyChange] ?? '';
            if ($before != $now) {
                return true;
            }
        }
        return false;
    }


    /**
     *  Does THIS company use upsert?
     *
     * There are THREE Upsert flags:
     * SCM_UPSERT_PRODUCTION - if this is on or on for this CNY#, we're good to go
     * SCM_UPSERT            - otherwise, if this is on, then upsert is on for all
     *                          NON-LIVE or NON-PRODUCTION companies
     *                          (i.e. everyone but live production)
     * SCM_UPSERT_ARAP_TOO   - do we attempt to upsert AR/AP?
     *
     * @return bool     Does it?
     */
    private function doesThisCompanyUseUpsert()
    {
        static $on = null;
        if ($on === null) {
            $on = FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('SCM_UPSERT');
            if ($on) {

                // Are we in production?  Is this a production company (as opposed to a sandbox)?
                // We can CNY# these if we need to....
                if (Globals::$g->islive && companyIsOfType(false, COMPANY_TYPE_PRODUCTION)) {
                    $on = FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('SCM_UPSERT_PRODUCTION');
                }

                if ($on) {
                    // Do we do AR/AP too?
                    self::$upsertPRRecordToo = FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('SCM_UPSERT_ARAP_TOO');
                }
            }
        }
        return $on;
    }


    /**
     *      When using set(), should we upsert?
     *
     * @param array $values             the document
     * @param bool  $doReposting        should we re-POST or just save?
     *
     * @return bool
     */
    private function shouldWeUpsert($values, &$doReposting)
    {
        $useUpsert                  = false;
        $doReposting                = true;
        self::$upsertConservatively = true;

        // Stockable kits affect item activity, and there's special code to handle the kit PARTS.
        //      we'd have to re-create this for upsert, but it is in tringgers, so, until some
        //      brave soul wants to tinker with it....
        if (($this->_docType != BUILD_KIT) && ($this->_docType != DIS_KIT ) && isset($values['ENTRIES'])) {

            // this will check if we need to POST, or just save the dochdr/docentries
            $doReposting = $this->isRepostingRequired($values);

            // Some changes make things much harder.  If the version of the DocPar changes, for example
            //      from 'gl posting' to 'ar/ap posting' or whatnot,
            //      Or if the created From or When created change, then the UPDATE TRIGGER in DocHdr will
            //          delete all icitemactivity records.
            //
            //  If allocations are in use here, strange things happen with upsert!  For one thing, the allocation
            //      records have their record#s stripped.  But!  See
            //       127976: "Automation failure: Subtotal department populated after changing allocation"
            //      For a reason I could never figure out, the SUBTOTALS get department ids when they don't without upsert!
            //      If you can fix that, then you could try enabling upsert when allocations are used.....

            // PHP 8.1 fix 163968
            $newCreatedFrom = isset($values['CREATEDFROM']) ? (string)$values['CREATEDFROM'] : "0";
            $oldCreatedFrom = isset($values['EXISTING_DOC']['CREATEDFROM']) ? (string)$values['EXISTING_DOC']['CREATEDFROM'] : "0";
            if ($doReposting &&
                ($oldCreatedFrom === $newCreatedFrom)) {

                if ( ! $this->anyAllocationEntries($values['ENTRIES'])) {

                    // After all that, is the feature even ENABLED?
                    $companyUsesUpsert  = $this->doesThisCompanyUseUpsert();
                    $changeOrderEnabled = $this->isChangeOrderEnabledForTD($values);
                    $upsertIsEnabled    = $companyUsesUpsert || $changeOrderEnabled;
                    if ($upsertIsEnabled) {
                        $useUpsert = true;  // well, ok, then, lets try to upsert

                        // if upsert is not on but CRE needs it, lets act conservatively
                        $highRisk = ($changeOrderEnabled === true) && ($companyUsesUpsert === false);
                        if ($highRisk) {
                            Matchmaker::additionalLogging("High Risk Upsert starting!");
                        }

                        $postAllDocentry = $highRisk || $this->doChangesSuggestUpdatingAllLines($values);

                        self::$upsertConservatively = $postAllDocentry;
                    }
                }
            }
        }

        // we need the doc type even if we aren't using upsert, because
        // the Matchmaker wants it for Custom Fields.
        self::$upsertDocType = $this->_docType ?? ($values['DOCPARID'] ?? '');
        if (self::$upsertDocType == '') {
            throw new Exception('[Code bug] No doc type for upsert.');
        }

        // what was the decision?
        if ($useUpsert) {
            Matchmaker::additionalLogging("UPSERTING OF SCM DOCUMENT STARTING");
        } else if (!$doReposting) {
            Matchmaker::additionalLogging("CLASSIC-MODE UPSERT STARTING");
        }
        return $useUpsert;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function validateOnChangeOfSourceDocument($values)
    {
        return true;
    }

    /**
     * @param bool $isSourceDocumentChanged
     *
     * @return void
     */
    protected function setIsSourceDocumentChanged(bool $isSourceDocumentChanged)
    {
        $this->isSourceDocumentChanged = $isSourceDocumentChanged;
    }

    /**
     * @return bool
     */
    protected function getIsSourceDocumentChanged()
    {
        return $this->isSourceDocumentChanged;
    }

    /**
     * Update/Set the document transaction.
     * Prepares the values, validates the values, advanced processing on the values, Add the values.
     * Post process document, Process the document history in the dochistory table and cleanup the template version if no transaction are avbl.
     *
     * @param  array &$values array of the values of the document.
     *
     * @return bool returns if the method execution was success or not.
     */
    protected function regularSet(&$values)
    {
        $values['DOCPARID'] = $values['DOCPARID'] ?? $this->getDocType();
        $postedValues = $values;
        $source = "DocumentManager::regularSet";

        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $handlers = array();

        if (!$this->acquireLocksIfNecessary($locks, $values)) {
            return false;
        }

        if (!$this->getDocumentParams($values)){
            return false;
        }

        if(!$this->validateAuthorization($values, true)){
            return false;
        }

        if (!$values['_mod'] && isset($this->mod)) {
            $values['_mod'] = $this->mod;
        }

        $oldValues = $this->getExistingValues($values);

        // In edit mode if they perform print/email action and then post without reload the page
        // This will be useful to update the correct value of DATEPRINTED, PRINTED
        $values['DATEPRINTED'] = $values['EXISTING_DOC']['DATEPRINTED'];
        $values['PRINTED'] = $values['EXISTING_DOC']['PRINTED'];

        // Validate change source document
        if(!$this->validateOnChangeOfSourceDocument($values)){
            return false;
        }

        // validate analyzing state only for PO match enabled documents
        if ( ! $this->validateAnalyzingState($values) ) {
            return false;
        }

        $this->setSCMTrigger(true);
        $ok = $this->_QM->beginTrx($source);
        ProjectManager::enableDeferredProjectTotals();

        // this TrackingHandler object is again in PrepValues & DeleteOldValuesForUpdate
        $handlers['TRACKING_HANDLER'] = new TrackingHandler(array('ACTION' => EDIT_ACTION));

        // TO BE SAFER Side:  should not allow to change doctype while edit mode .
        // doctype can be declared at the time of document creation only.
        if ($oldValues['DOCPARID'] != $values['DOCPARID']) {
            $msg = "Document Type can not be changed from " . $oldValues['DOCPARID'] . " to " . $values['DOCPARID'] . " for Existing Document";
            $gErr->addIAError(
                'INV-1322', __FILE__ . ":" . __LINE__,
                "Invalid User Action", [],
                $msg, ['OLD_VALUES_DOCPARID' => $oldValues['DOCPARID'], 'VALUES_DOCPARID' => $values['DOCPARID']],
                "", [],
                ""
            );
            $ok = false;
        }

        if (isset($oldValues['CREATEDFROM']) && $oldValues['CREATEDFROM'] != '') {
            // If current document has source document then set forcenew to true to get new instance of object
            $this->forcenew = true;
        }

        $ok = $ok && $this->ValidateAfterFormat($values);

        $ok = $ok && $this->PrepValues($values, $handlers,false, $getTaxRequest, $entityTaxable);

        $ok = $ok && $this->validateCCOUpdate($values);
        $ok = $ok && $this->validateChangeOrderProject($values);
        $ok = $ok && $this->processChangeOrder($values, true);
        $ok = $ok && $this->processPCB($values, true);

        if (VendorComplianceSetupManager::isVendorComplianceV2Enabled()) {
            if ( ! $this->isDraftDocument($values) ) {
                $ok = $ok && $this->validateVendorCompliance_DocSave($values, $values['_DOCPAR']['UPDATES_GL'] != 'N');
            }
        }

        $ok = $ok && $this->processReverseConversion($values);
        if (in_array($values['STATE'], [self::PARTIALLY_CONVERTED_STATE, self::CONVERTED_STATE])) {
            $ok = $ok && $this->validateConversionTypeChange($values['ENTRIES'], $values['EXISTING_ENTRIES']);
        }

        $ok = $ok && $this->convertAdditionalInfoVidtoKeyUpdate($values,$oldValues);

        // set private variable $allowInactiveDim to true in EntityManager to allow inactive dimensions(bug#33579)
        parent::SetAllowInactiveDimensions(true);

        // cache the values for auditing later
        $auditTrailSession = AuditTrailSession::getInstance();
        $auditTrailSession->cacheAuditRecord($this->getAuditEntity(), $this->GetKeyValue($values), $values);
        $this->allowPartiallyAndConvertedAsEditable($values);

        if($ok && $this->isCREConvertedDoc($values) && empty($values['__skip_Converted_Update_Validation'])){
            $ok = $ok && $this->validateAdditionalInfoForConvertedDoc($values);
            if($ok){
                $addInfoUpdate = $this->updateAdditionalInfoFieldValues($values);
                $this->releaseLocksIfNecessary($locks);
                $addInfoUpdate = $addInfoUpdate && $this->_QM->commitTrx($source);
                if (!$addInfoUpdate) {
                    if (Request::$r->_kNoWarn != 'true' && Request::$r->_kNoDupl != 'true') {
                        $msg = "Could not Set Document record!";
                        $gErr->addIAError('INV-1272', __FILE__ . ':' . __LINE__, $msg, []);
                        epp("$source: Error: $msg");
                    }
                    $this->_QM->rollbackTrx($source);
                } else {

                    // Add a return message for SFORCE derived creations
                    ProcessSforceResult("updated", $values);
                }
                return $addInfoUpdate;
            }
        }

        self::$upsertFeaturInUse = $this->shouldWeUpsert($values, $doReposting);
        self::$upsertedEntities  = [];   // haven't upserted nothin' yet (and may NOT)

        $existingEntries  = $values['EXISTING_ENTRIES'];

        //temporary fix and has to be removed once upsert is live
        if (!self::$upsertFeaturInUse && IsRestrictedUser()) {
            $cntRes = QueryResult(
                [
                    "SELECT count(1) cnt FROM docentrymst WHERE cny#=:1 AND dochdrkey=:2", GetMyCompany(),
                    $values['RECORDNO']
                ]
            );

            if (count($existingEntries) != $cntRes[0]['CNT']) {
                $msg = "This document has lines that the restricted user does not have access to";
                $gErr->addIAError('INV-1323', __FILE__ . ":" . __LINE__, "Modifying this document is not allowed", [], $msg, [], "", []);
                $ok = false;
            }
        }

        /** @var DocumentEntryManager  $documententryMgr */
        $documententryMgr =  $gManagerFactory->getManager($this->mod . 'documententry', false, array('DOCTYPE' => $this->_docType));

        if ($doReposting) {
            // check the document edit policy and the document is paid/converted
            $ok = $ok && $this->validateDocumentRepost($values['DOCID'], true);
            $ok = $ok && $this->checkForNegativeInventory($values, 'U', true);    // about to 'go negative'?

            // deleting old values
            $ok = $ok && $this->DeleteOldValuesForUpdate($values, $oldValues, $handlers);

            if (self::$upsertFeaturInUse) {
                $this->setUpsertEntries(true);              // tell the Entity Manager we want to upsert

                $ok = $ok && $this->getExistingSubtotals($values);  // fetch existing subtotals....
                $ok = $ok && $this->getDocSubTotalsManager(false)->mapSubtotalsRecordNo($values);
                // Remove duplicate record#s from the subtotals; back when we did not use upsert all the records were
                // delted and re-added, so the duplicate record numbers were not an issue.  Here's we'll update some
                // and not others
                DocumentSubTotalsManager::removeDuplicateRecordNumbersPriorToUpsert($values);

                // deleting docentry records used to delete all related item activity records.
                // since we don't do that anymore, delete the item activity 'by hand'....
                $ok = $ok && $documententryMgr->removeItemActivity($values);
            }
        } else {
            DocumentSubTotalsManager::removeDuplicateRecordNumbersPriorToUpsert($values);
            $this->setUpsertEntries(true);
            $this->setSCMTrigger(false);
        }

        if (! Globals::$g->islive) {
            logFL("Calling EntityManager set() with upsert " . (self::$upsertFeaturInUse ? 'ON' : ((!$doReposting) ? "CLASSIC" : "OFF")));
        }

        $tempUpsert = self::$upsertFeaturInUse;
        self::updatingEntity('dochdr');     // we just did both of these
        self::updatingEntity('docentry');

        $this->prepOwnedObjectData($values);
        
        $ok = $ok && parent::regularSet($values);
        
        self::$upsertFeaturInUse = $tempUpsert;   // this gets lost somewhere, I think in a call to  ManagerFactory::PurgeObjectInstances()...
        $values['EXISTING_ENTRIES'] = $existingEntries; // put these back, they got overwritten by EM

        // set back the variable $allowInactiveDim to false to avoid any side effects.
        parent::SetAllowInactiveDimensions(false);

        // The DocEntry triggers do not deal well with upsert, so here's some code to help make up for that:
        if (self::$upsertFeaturInUse) {
            $ok = $ok && $documententryMgr->maybeUpdateItemActivity($values);
        }

        unset($values['HISTORY']);

        // repost entries if the document entries are deleted and reinserted
        if ($doReposting) {
            $otherParams = [];
            $otherParams['POSTEDVALUES'] = $postedValues;
            $otherParams['OLDVALUES'] = $oldValues;
            $otherParams['ISUPDATE'] = true;
            /** @noinspection PhpUndefinedVariableInspection */
            $otherParams['TAX_REQUEST'] = $getTaxRequest;
            /** @noinspection PhpUndefinedVariableInspection */
            $otherParams['ENTITY_TAXABLE'] = $entityTaxable;

            //The PostProcessDocument below can update another record which calls back to DocumentManager::regularAdd
            //and sets self::$upsertFeaturInUse to false, which breaks our logic which depends on the flag
            $tempUpsert = self::$upsertFeaturInUse;

            $ok = $ok && $this->PostProcessDocument($values, $otherParams);

            self::$upsertFeaturInUse = $tempUpsert; //Put back

            if ( self::isDocumentInPostingState($values['STATE'])) {
                $ok = $ok && $this->Post($values, $otherParams);
            }
        }

        $this->releaseLocksIfNecessary($locks);

        $ok = $ok && $this->afterPostings($values);

        $ok = $ok && $this->checkForNegativeInventory($values, 'U', false);    // did we just 'go negative'?

        // Explicitly turn OFF upserting.  During commit, smart events fire and they might
        // try to update stuff and we don't want THAT code to think we're upserting,
        // because we aren't (or might be, but then it will be reset to true/false here)
        if (self::$upsertFeaturInUse) {
            self::$upsertFeaturInUse = false;
            self::$upsertedEntities = [];

            // subtotals are currently reflecting the records under them, but for compatibility
            // we need them to look like when you did a get().....  (mostly for SMART EVENTS)
            $values['SUBTOTALS'] = [];
            $this->getEntrySubTotals($values);
            $this->showSubTotals($values);
        }
        $documententryMgr->flushCacheForDocHdr();  // done with the cache
        $docEntryTrackMgr = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
        $docEntryTrackMgr->flushCacheForDocHdr();  // done with the cache


        //***NEED TO BE SET TO NOT DEQUEUE IMS REQUEST IN CASE OF ERROR.
        $subscription =  $gManagerFactory->getManager('imssubscription');

        // do *not* add error if it has only warnings
        if (!$ok && !HasErrors() && HasWarnings()) {
            $this->_QM->rollbackTrx($source);
            $subscription->noDequeue = true;
        } else {
            $ok = $ok && $this->_QM->commitTrx($source);
            if (!$ok) {
                if (Request::$r->_kNoWarn != 'true' && Request::$r->_kNoDupl != 'true') {
                    $msg = "Could not Set Document record!";
                    $gErr->addIAError('INV-1273', __FILE__ . ':' . __LINE__, $msg, []);
                    epp("$source: Error: $msg");
                }
                $subscription->noDequeue = true;
                $this->_QM->rollbackTrx($source);
                $values = $postedValues;
            } else {
                // Add a return message for SFORCE derived creations
                ProcessSforceResult("updated", $values);
            }
        }

        $this->setSCMTrigger(true);


        return $ok;
    }

    /**
     * @param array &$values
     */
    protected function prepOwnedObjectData(&$values)
    {
        foreach ($values['ENTRIES'] as $key => $entry) {
            $recno = $entry['RECORDNO'] ?? 0; // 0 means it is a new record
            if ($recno > 0
                && Util::countOrZero($values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'] ?? []) > 0) {
                $values['ENTRIES'][$key]['EXISTING_TRACKINGENTRIES'] = $values['EXISTING_ENTRIES'][$recno]['EXISTING_TRACKINGENTRIES'];
            }
        }
    }

    /**
     * @param array $sourceEntries
     * @param array $newEntries
     *
     * @return bool
     */
    public function validateConversionTypeChange($sourceEntries, $newEntries)
    {
        $ok = true;

        // Validate a change in conversiontype prior to other validations regarding quantity or price.
        foreach($sourceEntries as $entry) {
            foreach ($newEntries as $newentry) {
                if ($entry['RECORDNO'] == $newentry['RECORDNO']) {
                    // Treat a blank CONVERSIONTYPE as "Quantity" by default.
                    $ctSource = $entry['CONVERSIONTYPE'];
                    if ($ctSource == '') {
                        $ctSource = 'Quantity';
                    }
                    if ((isset($newentry['CONVERSIONTYPE']) && $ctSource != $newentry['CONVERSIONTYPE']) || !isset($newentry['CONVERSIONTYPE'])) {
                        $msg = sprintf('While converting %1$s, the conversion type changed to %2$s.', $entry['ITEMDESC'], ($newentry['CONVERSIONTYPE'] === 'Price') ? 'Price' : 'Quantity');
                        $correction = 'When converting a document, conversion types cannot be changed.';
                        if(isset($newentry['CONVERSIONTYPE']) && $newentry['CONVERSIONTYPE'] === 'Price'){
                            $errorCode = 'INV-1274';
                        }else{
                            $errorCode = 'INV-1316';
                        }
                        Globals::$g->gErr->addIAError(
                            $errorCode, __FILE__ . ':' . __LINE__,
                            $msg, ['ENTRY_ITEMDESC' => $entry['ITEMDESC']],
                            '', [],
                            $correction, []
                        );
                        $ok = false;
                    }
                }
            }
        }

        return $ok;
    }

    /**
     * Determine if this transaction is executing under a vat context
     * this method assumed translate tax solution is already called so that taxsolution is set in the $values
     *
     * @param array|null $values
     *
     * @return bool
     */
    protected function isTransactionVATEnabled(array $values = null)
    {
        // if the tax module is not configured then there can;t be any vat
        if ( !TaxSetupManager::isTaxModuleConfigured() ) {
            return false;
        }

        // if TD does not have atleast 1 subtotal tax line then treat it as if its non-vat
        if ( !empty($values['_DOCPAR']) && !self::hasTaxSubTotals($values['_DOCPAR']) ) {
            return false;
        }

        if ( TaxSetupManager::isMultiTaxJurisdictionConfigured() ) {
            // at root only if a tax solution is configured we can determine if vat is enabled
            if ( empty($values) || empty($values['TAXSOLUTIONID']) ) {
                // if tax solution is not present, treat it as non-vat
                // ideally at entity level we should check the tax solution in entity for new documents
                // but since translate is called before calling this it should be ok unless $values is send as null
                $isUsingVat = false;
            } else {
                if ( empty($values['TAXMETHOD'])) {
                    // if tax method is not set, try to find it from taxsolution (happens for API calls)
                    $mgr = Globals::$g->gManagerFactory->getManager('taxsolution');
                    $taxSoln = $mgr->get(($values['TAXSOLUTIONID'] ?? ''));
                    $isUsingVat = TaxSolutionManager::isVatTaxMethod($taxSoln['TAXMETHOD']);
                } else {
                    $isUsingVat = TaxSolutionManager::isVatTaxMethod($values['TAXMETHOD']);
                }
            }
        } else {
            // for singletax jurisdictions , we assume its vat since we only allow VAT tax solutoins now
            $isUsingVat = true;
        }

        return $isUsingVat;
    }

    /**
     * Implement this method in the documents VAT/GST must be enabled
     *
     * @param array|null $values
     *
     * @return bool true is VAT/GST is enabled for the module
     */
    public function isVATEnabled(/** @noinspection PhpUnusedParameterInspection */ array $values = null)
    {
        return false;
    }

    /**
     * Implement this method to support payment tax capture
     *
     *
     * @return false
     */
    public function isPaymentTaxCaptureSupported()
    {
        return false;
    }

    /**
     * @param array &$values
     *
     * @return bool
     */
    protected function checkForExternalChanges(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return false;
    }

    /**
     * @param array  $objRec
     * @param bool   $validateReadOnly
     *
     * @return bool
     */
    protected function useOwnedObject($objRec, $validateReadOnly)
    {
        if ($objRec['entity'] == 'dochistory' && $validateReadOnly) {
            return false;
        }

        return parent::useOwnedObject($objRec, $validateReadOnly);
    }

    /**
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        static $ignoreFields = [
            'docno',
            'createdfrom',
            'invbatchkey',
            'prinvbatchkey',
            'addglbatchkey',
            'closed',
            'auwhencreated',
            'createdby',
            'modifiedby',
            'status',
            'whenmodified',
            'memokey',
            'warehousekey',
            'shipviakey',
            'userkey',
            'createduserkey',
            'entity',
            'note',
            'prrecordkey',
            'printed',
            'backorder',
            'locationkey',
            'deptkey',
            'entglgroup',
            'schopkey',
            'salescontract',
            'contractid',
            'contractdesc',
            'usedascontract',
            'trx_subtotal',
            'trx_total',
            'reneweddoc',
            'systemgenerated',
            'origdocdate',
            'hasadvbilling',
            'dateprinted',
            'printedby',
        ];

        return $ignoreFields;
    }

    /**
     * @return string[]
     */
    protected function getExternalFieldsList()
    {
        static $externalFields = [ 'SUPDOCID' ];

        return $externalFields;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function validateForReApproval(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        return false;
    }

    /**
     * @param string $sourceDocLineKey
     * @param array  $entry
     *
     */

    public function getSourceDocLinePrimaryKeys($sourceDocLineKey, &$entry)
    {
        global $gManagerFactory;

        $filter = array(
            'selects' => ['PRIMARYDOCKEY', 'PRIMARYDOCLINEKEY'],
            'filters' => [[['RECORDNO', '=', $sourceDocLineKey]]]
        );


        $docentryManager = $gManagerFactory->getManager($this->mod . 'documententry', false, array('DOCTYPE' => $this->_docType));
        $res = $docentryManager->GetList($filter);

        if(isset($res[0]['PRIMARYDOCKEY']) && $res[0]['PRIMARYDOCKEY'] != '') {
            $entry['PRIMARYDOCKEY'] = $res[0]['PRIMARYDOCKEY'];
            $entry['PRIMARYDOCLINEKEY'] = $res[0]['PRIMARYDOCLINEKEY'];
        }
    }


    /**
     * @param array      $docObj
     * @param array      $sourceDockeys
     * @param null|array  $sourcedocids
     *
     * @return bool
     */
    function checkIsCreatedFromMultipleSourceDocuments(&$docObj, &$sourceDocKeys, &$sourceDocIds=null)
    {
        $retVal = false;
        if (!isset($docObj['ENTRIES'])) {
            return $retVal;
        }
        $sourceDocIds = [];

        // check if the document is created from multiple source transactions
        $sourceDocKeys = array();
        $docLinesWithoutOrigDetails = [];

        // --- get all the source documents
        foreach ($docObj['ENTRIES'] as &$entry) {
            if (isset($entry['ISSUMMARIZED_ENTRY']) && $entry['ISSUMMARIZED_ENTRY'] == 'true' ||
                isset($entry['ISSUMMARIZED']) && $entry['ISSUMMARIZED'] == 'true') {
                $this->processSummarizedEntry($docObj, $entry, $sourceDocKeys, $sourceDocIds);
            }
            else {
                $sourceDocKey = $entry['SOURCE_DOCKEY'] ?? ($entry['SOURCE_DOCHDRKEY'] ?? '');
                $sourceDocId = $entry['SOURCEDOCID'] ?? '';
                if ($sourceDocKey != '') {
                    if (!in_array($sourceDocKey, $sourceDocKeys)) {
                        $sourceDocKeys[] = $sourceDocKey;
                        $sourceDocIds[$sourceDocKey] = $entry['SOURCE_DOCID'];
                    }

                    if ( CRESetupManager::isPrimaryDocEnabled()) {
                        // The primarydockeys are already set when converting via UI but we need to set it for API
                        if (( ! isset($entry['PRIMARYDOCKEY']) || $entry['PRIMARYDOCKEY'] == '' ) && isset($entry['SOURCE_DOCLINEKEY'])) {
                            $this->getSourceDocLinePrimaryKeys($entry['SOURCE_DOCLINEKEY'], $entry);
                        }
                    }
                } else if($sourceDocId !== ''){
                    if (!in_array($sourceDocId, $sourceDocKeys)) {
                        $sourceDocKeys[] = $sourceDocId;
                        $sourceDocIds[$sourceDocId] = $entry['SOURCE_DOCID'];
                    }
                }
            }

            // The primarydockeys are already set when converting via UI but we need to set it for API
            if (( ! isset($entry['ORIGDOCKEY']) || $entry['ORIGDOCKEY'] == '' )
                && (isset($entry['SOURCE_DOCLINEKEY']) && $entry['SOURCE_DOCLINEKEY'] != '')) {
                $docLinesWithoutOrigDetails[] = $entry['SOURCE_DOCLINEKEY'];
            }
        }

        if(countArray($docLinesWithoutOrigDetails) > 0) {
            $origDocsCache = $this->prepOriginatingDocumentsCache($docLinesWithoutOrigDetails);
            $this->prepOriginatingDocumentsDetails($docObj, $origDocsCache);
        }

        if (count($sourceDocKeys) == 1) {
            $docObj['CREATEDFROM'] = $sourceDocIds[$sourceDocKeys[0]];
        } elseif (count($sourceDocKeys) > 1) {
            $docObj['CREATEDFROM'] = ConversionManager::getmultipleSourceDocsText();
            $retVal = true;
        }
        return $retVal;
    }

    /**
     * @param array $docLineKeys
     *
     * @return array
     */
    public function prepOriginatingDocumentsCache($docLineKeys)
    {
        if (countArray($docLineKeys) <= 0) {
            return [];
        }

        $gManagerFactory = Globals::$g->gManagerFactory;
        $docentryManager = $gManagerFactory->getManager($this->mod . 'documententry', false, array('DOCTYPE' => $this->_docType));

        $filter = [
            'selects' => ['RECORDNO', 'ORIGDOCKEY', 'ORIGDOCLINEKEY', 'SOURCE_DOCKEY', 'SOURCE_DOCLINEKEY'],
            'filters' => [[['RECORDNO', 'IN', $docLineKeys]]]
        ];

        $origDocEntries = $docentryManager->GetList($filter);

        $origDocEntriesCache = [];
        foreach ($origDocEntries as $origDocEntry) {
            $mappingKey = $origDocEntry['RECORDNO'];
            $origDocEntriesCache[$mappingKey] = $origDocEntry;
        }

        return $origDocEntriesCache;
    }

    /**
     * @param array $docObj
     * @param array $origDocsCache
     */
    public function prepOriginatingDocumentsDetails(&$docObj, $origDocsCache)
    {
        foreach ($docObj['ENTRIES'] as &$entry) {
            if ((!isset($entry['ORIGDOCKEY']) || $entry['ORIGDOCKEY'] == '')
                && (isset($entry['SOURCE_DOCLINEKEY']) && $entry['SOURCE_DOCLINEKEY'] != '')) {

                $mappingKey = $entry['SOURCE_DOCLINEKEY'];
                $origDocEntryDetails = $origDocsCache[$mappingKey];

                if (isset($origDocEntryDetails['ORIGDOCKEY']) && $origDocEntryDetails['ORIGDOCLINEKEY'] != '') {
                    $entry['ORIGDOCKEY'] = $origDocEntryDetails['ORIGDOCKEY'];
                    $entry['ORIGDOCLINEKEY'] = $origDocEntryDetails['ORIGDOCLINEKEY'];
                } else {
                    $entry['ORIGDOCKEY'] = $entry['SOURCE_DOCKEY'] ?? '';
                    $entry['ORIGDOCLINEKEY'] = $entry['SOURCE_DOCLINEKEY'] ?? '';
                }
            }
        }
    }

    /**
     * @param array       $docObj
     * @param array       $entryParam
     * @param array       &$sourceDockeys
     * @param null|array  &$sourceDocIds
     *
     */
    private function processSummarizedEntry($docObj, $entryParam, &$sourceDocKeys, &$sourceDocIds)
    {
        if (isNonEmptyArray($docObj['SUMMARIZEDENTRIES_TOCONVERT']) &&
            isNonEmptyArray($docObj['SUMMARIZEDENTRIES_TOCONVERT']['ENTRIES'])
        ) {
            // the summarized entry info is in memory, in SUMMARIZEDENTRIES_TOCONVERT
            foreach ($docObj['SUMMARIZEDENTRIES_TOCONVERT']['ENTRIES'] as $entry) {
                $sourceDocKey = $entry['SOURCE_DOCKEY'] ?? ($entry['SOURCE_DOCHDRKEY'] ?? '');
                if ($sourceDocKey != '') {
                    if (!in_array($sourceDocKey, $sourceDocKeys)) {
                        $sourceDocKeys[] = $sourceDocKey;
                        $sourceDocIds[$sourceDocKey] = $entry['SOURCE_DOCID'];
                    }
                }
            }
        }
        elseif (isset($entryParam['ISSUMMARIZED_ENTRY']) && $entryParam['ISSUMMARIZED_ENTRY'] == 'true') {
            // the summarized entry info is in memory, in SOURCE_DOCHDRKEY
            $sourceDocKey = $entryParam['SOURCE_DOCHDRKEY'];
            $sourceDocKeys = array_unique(array_merge($sourceDocKeys, [ $sourceDocKey ]));
            $sourceDocIds[$sourceDocKey] = $entryParam['SOURCE_DOCID'];
        }
        else {
            // the summarized entry info is in the summary billed detail table
            getSourceDocKeysFromSummBillDet($entryParam, $sourceDocKeys, $sourceDocIds);
        }
    }

    /**
     * @param array  $values
     * @param string $defTermKey
     *
     * @return bool
     */
    protected function populateDefaultTermAndDueDate(&$values, $defTermKey)
    {

        if (empty($values['WHENDUE']) && $defTermKey) {
            $values['WHENDUE'] = $values['WHENCREATED'];
            GetStaticTermRecNo($defTermKey, $termKey);
            $values['TERMKEY'] = $termKey;

            GetTerm($termKey, $term);
            $values['WHENDUE'] = CalcDueDate($values['WHENCREATED'], $term['VALUE']);
            $values['TERM']['NAME'] = $term['NAME'];
        }

        return true;
    }


    /**
     * afterUpdateEntries
     *
     * @param string              $path           the path of the owned object
     * @param OwnedObjectManager  $lineManager   line item manager object
     * @param int                 $parentKey      parent record number
     * @param array               &$values        new values
     * @param array               &$oldRecNumbers existing record numbers
     * @param array               &$newRecNumbers updated record numbers
     *
     * @return bool
     */
    protected function afterUpdateEntries($path, $lineManager, &$parentKey, &$values, &$oldRecNumbers, &$newRecNumbers)
    {
        $ok = true;
        $macroNames = [];

        if (method_exists($lineManager, 'getMacroNames')) {
            $macroNames = $lineManager->getMacroNames();
        }

        if ( InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_EITHER, $values) ) {
            $dmFulfillmentHelper = new DocumentManagerFulfillmentHelper($values);
            $ok = $ok && $dmFulfillmentHelper->updateFulfillment();
        }

        if ($ok && !empty($macroNames)) {

            $gManagerFactory = Globals::$g->gManagerFactory;
            $gErr = Globals::$g->gErr;

            $scmMacroResolveMgr = $gManagerFactory->getManager('scmmacroresolve');

            // Get the source doc par key
            $params = array(
                'selects' => array(
                    'MACRONAME',
                    'SOURCEDOCENTRYKEY',
                ),
                'filters' => array(
                    array(array('SOURCEDOCKEY', '=', $values['RECORDNO']))
                ),
            );

            $recs = $scmMacroResolveMgr->GetList($params);
            $entries = array();
            foreach ((($values['ENTRIES']) ?? []) as $entry) {
                if ($entry['RECORDNO']) {
                    $entries[$entry['RECORDNO']] = true;
                }
            }

            foreach ($recs as $rec) {
                if (!isset($entries[$rec['SOURCEDOCENTRYKEY']])) {
                    SCMMacroManager::getMacroErrorMessage($rec['MACRONAME'], "MACRO004", $msg, $corr, [], $errorCode, $placeholder);
                    $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, 'Unable to delete', [], $msg, $placeholder['desc2'], $corr, $placeholder['corr']);
                    $ok = false;
                }
            }
        }

        $ok = $ok && parent::afterUpdateEntries($path, $lineManager, $parentKey, $values, $oldRecNumbers, $newRecNumbers);

        return $ok;
    }

    /**
     * Hook function for the sub classes to perform specific tasks right before the record is deleted
     *
     * @param array  &$raw  the raw record
     *
     * @return bool  true on success and false on failure
     */
    protected function beforeDelete(&$raw)
    {
        global $gManagerFactory;

        /**
         * @var OwnedObjectManager $documententryMgr
         */
        $documententryMgr =  $gManagerFactory->getManager(
            $this->mod . 'documententry', false,
            array('DOCTYPE' => $this->_docType)
        );
        $preDelDocEntries = $documententryMgr->deleteByParent($raw[0]['RECORD#'], DELETE_FOR_DELETE);

        $preDelDocSubTotals = $this->getDocSubTotalsManager(false)->deleteByParent($raw[0]['RECORD#'], DELETE_FOR_DELETE);
        return $preDelDocEntries && $preDelDocSubTotals;
    }

    /**
     * @param array $docObj
     *
     * @return bool
     */
    protected function checkForAdjustmentEntries(&$docObj)
    {
        $gManagerFactory = &Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;
        $res = array();

        if ($docObj['RECORDNO']) {
            $entryMgr = $gManagerFactory->getManager('documententry', false, array( 'DOCTYPE' => $this->_docType));

            $params = array(
                'selects' => array('RECORDNO'),
                'filters' => array(
                    array(
                        array(
                            'ADJDOCHDRKEY', '=', $docObj['RECORDNO'],
                        ),
                    ),
                ),
            );
            $res = $entryMgr->GetList($params);
        }

        if (!empty($res)) {
            $msg  = "An inventory adjustment document is linked to an item in this document";
            $corr = "To update this document, first delete the linked inventory adjustment.";
            $gErr->addIAError('INV-1275', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr, []);
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $docObj
     *
     * @return bool
     */
    protected function checkForCOGSClosedJEEntries(&$docObj)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        if ($docObj['RECORDNO']) {
            $res = QueryResult(
                [
                    "SELECT COUNT (1) count FROM cogsresolve WHERE cny# = :1 AND dochdrkey = :2 ",
                    GetMyCompany(),
                    $docObj['RECORDNO'] ]
            );
            $ok = ($res !== false);
            if ($ok && ($res[0]['COUNT'] > 0)) {
                $msg  = "Prior period COGS adjustments are linked to this transaction.";
                $corr = "To update or delete the transaction, delete the posted prior period COGS adjustments. Then, try again.";
                $gErr->addIAError('INV-1276', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr, []);

                $ok = false;
            }
        }
        return $ok;
    }


    /**
     *      For two routines below, we want to 'normalize' document line items before seeing if there is
     *  enough quantity on hand for them to be removed/deleted.
     *
     *      Used by enoughQuantityOnHand() and canIRemoveDocEntryCosts(), below
     *
     *
     * @param array             $docentrycosts              in: docentrycost records
     * @param array             $itemWarehouseQuantities    returned: array of quantities by item/warehouse
     * @param array             $items                      returned: array of items
     * @param array             $warehouses                 returned: array of warehouses
     * @param int[]             $allRecords                 returned: all record#s in the entries (including those that don't need checking)
     * @param bool              $onlyInbound                ony check inbound txns?  If false, check both
     *
     * @return int[]                                        array of the record numbers that DO need checking
     */
    private function normalizeEntriesForNegativeCheck($docentrycosts, &$itemWarehouseQuantities, &$items, &$warehouses, &$allRecords, $onlyInbound = false)
    {
        $records                    = [];
        $itemWarehouseQuantities    = [];
        $items                      = [];
        $warehouses                 = [];
        $allRecords                 = [];
        $warehouseMgr               = Globals::$g->gManagerFactory->getManager('warehouse');

        foreach ($docentrycosts as $entry) {
            $itemID      = $entry['ITEMKEY']     ?? ''; // unlikely to have a docentrycost without these, but.....
            $warehouseID = $entry['WHSEKEY']     ?? '';
            $quantity    = $entry['QUANTITY']    ?? 0;
            $recordNo    = $entry['RECORD#']     ?? ($entry['RECORDNO'] ?? 0);
            $adj         = $entry['ADJDOCENTRYCOSTKEY'] ?? 0;
            $recordNo    = (int)$recordNo;

            //If the warehouse on the $entry allows negative inventory, no need to check for negative below for this $entry
            if ($warehouseMgr->isNegativeInventoryAllowed($warehouseID)) {
                continue;
            }

            if ($recordNo > 0) {
                $allRecords[] = $recordNo; // ALL the records, so we don't find them when looking for replacements
            }

            // An empty or quantity zero/negative entry?  Skip it.
            if (( $onlyInbound && ($entry['IN_OUT'] !== 'I')) ||
                ($recordNo    === 0)  ||
                ($itemID      === '') ||
                ($warehouseID === '') ||
                ($quantity     <= 0)  ||  // yes, <= for quantity to catch empty as well
                ($adj           > 0)) {
                continue;
            }

            // If quantity left >= quantity, then it is golden.  I.e. none of it sold.
            // why?  because if you just LOWER the amount, but you lower it to something
            // still >= than quantity left, we're still golden
            $reduceTo          = $entry['REDUCETO'] ?? 0;   // default to reducing to zero
            $reduceBy          = ($quantity - $reduceTo);   // e.g., reduce to 8 from 10, so reduce-by is 2
            $qtyLeft           = $onlyInbound ? ($entry['QTYLEFT'] ?? 0) : 0;    // if qtyleft is at least reduce-by, we're good
            if (($reduceBy === 0) || ($qtyLeft >= $reduceBy)) {
                continue;   // nothing to check
            }
            $items[$itemID]             = true;
            $warehouses[$warehouseID]   = true;
            $itemWarehouseQuantities[$itemID][$warehouseID] =
                round(($itemWarehouseQuantities[$itemID][$warehouseID] ?? 0.0) + $reduceBy, ItemManager::AVERAGE_COST_DECIMALS);
            $records[]                  = $recordNo;
        }
        return $records;
    }


    /**
     *  If you are about to delete a transaction, or entries from a transaction, or reduce the quantity on
     *  a transaction line, call this to see if that is ok.
     *
     * This is less specific than canIRemoveDocEntryCosts(), below, as it does not check tracking data.  However,
     * this works in some cases where canIRemoveDocEntryCosts() does not.  Specifically if you, say,
     *  Purchase 1
     *  Purchase 1
     *  Sell 1, attaches to first purchase
     *  Delete first purchase; now the sale has no source.  MIV would connect it to the second purchase
     *  Delete second purchase: if MIV wasn't run, the above code would succeed but we'd be in trouble,
     *
     * So, not perfect, but using these two routines togeather gets pretty close.
     *
     *  Goal: prevent the transaction items from going negative.
     *
     *  This is protected and is intended to be called from special routines such as checkForNegativeInventory(), below.
     *
     *  Preconditions:
     *      - the caller has determined that we want to reduce the quantity of an item/warehouse pair
     *          - maybe because we're deleting one or more lines from a purchase, for example
     *      - the caller determined the transaction updates ON HAND (Q or QV)
     *      - the transaction is not a draft
     *
     *  Supplied:
     *      - series of docentrycost records with at least
     *      -   RECORD# or RECORDNO
     *      -   ITEMKEY                (really an ITEMID)
     *      -   WHSEKEY                (really a WAREHOUSEID)
     *      -   QUANTITY
     *      -   QTYLEFT                (maybe > quantity, see below)
     *      -   IN_OUT
     *
     *  Return on NO ERROR but nothing wrong:
     *      empty array
     *
     *  Return on error:
     *      - If SQL error, false
     *      - Array of
     *          ITEMKEY, WHSEKEY, DATEIN (date of failure), QUANTITY (the portion we could not find)
     *
     * @param array     $entries            line items from a document that you want to check
     * @param string    $whencreated        date of txn/date to start searching
     * @param bool      $postSave           Are we pre-save or post-save?  I.e. look for qty or >= 0?
     *
     * @return bool|array                   false or an array of errors, perhaps empty meaning 'no errors'
     */
    protected function enoughQuantityOnHand($entries, $whencreated, $postSave)
    {
        // figure out what we need to do here, if anything
        // for this, pretend there's nothing left so we see if we can remove the entries
        foreach ($entries as $index => $entry) {
            $entries[$index]['QTYLEFT'] = 0;
        }
        $this->normalizeEntriesForNegativeCheck($entries, $itemWarehouseQuantities, $items, $warehouses, $allRecords);
        if (Util::countOrZero($itemWarehouseQuantities) === 0) {
            return [];
        }
        return $this->_enoughQuantityOnHandInternal($itemWarehouseQuantities, $items, $warehouses, $whencreated, $postSave);
    }


    /**
     * Internal helper for the above routine, or for specific, careful callers
     *
     * @param array    $itemWarehouseQuantities      in the format returned by normalizeEntriesForNegativeCheck
     * @param array    $items                        item array (with items as keys)
     * @param array    $warehouses                   warehouse array (with warehouseIDs as keys)
     * @param string   $whencreated                  date to start searching from
     * @param bool     $postSave                     is this pre or post save (i.e. check for 0 QOH or Qty QOH?)
     *
     * @return array|false
     */
    private function _enoughQuantityOnHandInternal($itemWarehouseQuantities, $items, $warehouses, $whencreated, $postSave)
    {
        $rtn     = [];
        $qry     = [];
        $qry[]   = "SELECT itemkey, whsekey, qtyonhand, ason
                     FROM  itmhistcost
                     WHERE cny# = :1
                       AND ason >= to_date(:2,'MM/DD/YYYY') ";
        $qry[]   = GetMyCompany();
        $qry[]   = $whencreated;
        $qry     = PrepINClauseStmt($qry, array_keys($items),      ' and itemkey ', true, 'items');
        $qry     = PrepINClauseStmt($qry, array_keys($warehouses), ' and whsekey ', true, 'warehouses');
        $qry[0] .= " ORDER BY ason ";
        $result = QueryResult($qry);
        if ($result === false) {
            return false;
        }
        foreach ($result as $row) {
            // this may return item/warehouses we don't care about, so filter out those....
            $itemID      = $row['ITEMKEY'];
            $warehouseID = $row['WHSEKEY'];
            if (isset($itemWarehouseQuantities[$itemID][$warehouseID])) {
                $qtyNeeded = $postSave ? 0.0 : $itemWarehouseQuantities[$itemID][$warehouseID];
                if ($qtyNeeded  > $row['QTYONHAND']) {
                    $qtyNeeded -= $row['QTYONHAND'];
                    $key        = "$itemID~$warehouseID";
                    if ( ! isset($rtn[$key])) { // only one error per item/warehouse
                        $rtn[$key] = ['ITEMKEY' => $itemID, 'WHSEKEY' => $warehouseID, 'QUANTITY' => $qtyNeeded,
                                      'DATEIN' => $row['ASON'], 'DOCID' => '', 'ISWTOUT' => false];
                    }
                }
            }
        }
        return $rtn;
    }


    /**
     *      Negative Inventory Check Internals: find outbound tied to specific inbound via Docentrycostkeys
     *
     * @param int[]         $records    docentrycostkey record numbers to find dependant records on
     *
     * @return array|bool               DB error --> false, else list of found records by key
     */
    private function _NIC_findOutboundByDECK($records)
    {
        // if nothing passed, then nothing to do (but not an error)
        if ( ! is_array($records) || empty($records)) {
            return [];
        }

        // Bulk get the sales / output records tied to the passed-in records
        $qry       = [];
        $qry[0]    = 'sql goes here';
        $qry[1]    = GetMyCompany();
        $qry[0]    = "SELECT datein, itemkey, whsekey, serialno, lotno, binkey, expirationdate, record#, docid, docparid, quantity as totalToFind
                        FROM 
                        (
                            SELECT dec.datein, dec.itemkey, dec.whsekey, 
                                   dec.serialno, dec.lotno, dec.binkey, dec.expirationdate, 
                                   dec.record#, dec.quantity, dh.docid, dh.docparid
                                FROM docentrycost dec, docentrymst de, dochdrmst dh
                                WHERE dec.cny# = :1 and de.cny# = dec.cny# and dh.cny# = de.cny#
                                  AND dec.affects_inventory IN ('Q','QV')
                                  AND dec.in_out = 'O'
                                  AND dec.adjdocentrycostkey IS NULL 
                                  AND de.record# = dec.docentrykey
                                  AND dh.record# = de.dochdrkey ";
        $qry = PrepINClauseStmt($qry, $records, ' and dec.docentrycostkey ' );

        $qry[0]    .= " UNION ALL
                              SELECT dec.datein, dec.itemkey, dec.whsekey, 
                                   dec.serialno, dec.lotno, dec.binkey, dec.expirationdate, 
                                   0 as record#, dec.quantity, dh.docid, dh.docparid
                                FROM docentrycostkits dec, docentrymst de, dochdrmst dh
                                WHERE dec.cny# = :1 and de.cny# = dec.cny# and dh.cny# = de.cny#
                                  AND in_out = 'O'
                                  AND de.record# = dec.docentrykey
                                  AND dh.record# = de.dochdrkey ";
            $qry = PrepINClauseStmt($qry, $records, ' and dec.docentrycostkey ' ); // unbuilding a kit?

        $qry[0]    .= " )
                        ORDER BY datein desc ";
        $result = QueryResult($qry);

        return $result;
    }


    /**
     *      Negative Inventory Check Internals: find un-sourced outbound tied to specific items and warehouses
     *  This is used AFTER updating an outbound record, and we want to see if there is still enough inbounds
     *  on-or-before the date of this and any other outbounds that have no source.  Why 'any other'?  Because
     *  if MIV has not run, you might move one sale and then another and the second move may affect the first.
     *  (because the first ended up with dangling outbound records that we previously tied to inbound, but now
     *  we have MORE outbound)
     *
     *      Note you can't move kit builds, so they won't have un-sourced docentrycostkit records.  So no point
     *  looking for those.
     *
     * @param int[]         $records            array of source records to look for too
     * @param array         $items              array of 'true' BY items
     * @param array         $warehouses         array of 'true' BY warehouses
     * @param string        $earliestDate       earliest date to find
     *
     * @return array|bool                       DB error --> false, else list of found records by key
     */
    private function _NIC_findOutboundByItemWarehouse($records, $items, $warehouses, $earliestDate)
    {
        // if nothing passed, then nothing to do (but not an error)
        if (empty($items) || empty($warehouses)) {
            return [];
        }

        // Bulk get the records; we may get more than we want because we can't ask for
        // a speciic item/warehouse pair, but, usually, all the items would have the same warehouse
        $qry    = [];
        $qry[0]    = 'sql goes here';
        $qry[1]    = GetMyCompany();
        $qry[2]    = $earliestDate;
        $qry[0]    = "SELECT dec.datein, dec.itemkey, dec.whsekey, 
                                   dec.serialno, dec.lotno, dec.binkey, dec.expirationdate, 
                                   dec.record#, dec.quantity, dh.docid, dh.docparid
                                FROM docentrycost dec, docentrymst de, dochdrmst dh
                                WHERE dec.cny# = :1 and de.cny# = dec.cny# and dh.cny# = de.cny#
                                  AND dec.affects_inventory IN ('Q','QV')
                                  AND dec.in_out = 'O'
                                  AND dec.adjdocentrycostkey IS NULL
                                  AND de.record# = dec.docentrykey
                                  AND dh.record# = de.dochdrkey 
                                  AND dh.whencreated >= :2 ";
        // note: the docentrycostkey is not turned to null or whatever until the txn is saved and triggers fire,
        //        so look for records with no source or records with these specific sources
        if ( ! empty($records)) {
            $qry = PrepINClauseStmt($qry, $records, ' and ((dec.docentrycostkey IS NULL) or (dec.docentrycostkey ', true, 'decsbyrecs');
            $qry[0] .= ')) ';
        } else {
            $qry[0] .= ' and dec.docentrycostkey IS NULL ';
        }
        $qry    = PrepINClauseStmt($qry, array_keys($items),      ' and dec.itemkey ', true, 'decsbyitems' );
        $qry    = PrepINClauseStmt($qry, array_keys($warehouses), ' and dec.whsekey ', true, 'decsbywarehouses' );
        $qry[0]    .= " UNION ALL
                        SELECT dec.datein, dec.itemkey, dec.whsekey, 
                                   dec.serialno, dec.lotno, dec.binkey, dec.expirationdate, 
                                   dec.record#, dec.quantity, dh.docid, dh.docparid
                                FROM docentrycostkits dec, docentrymst de, dochdrmst dh
                                WHERE dec.cny# = :1 and de.cny# = dec.cny# and dh.cny# = de.cny#
                                  AND dec.affects_inventory IN ('Q','QV')
                                  AND dec.in_out = 'O'
                                  AND de.record# = dec.docentrykey
                                  AND dh.record# = de.dochdrkey 
                                  AND dh.whencreated >= :2 ";
        if ( ! empty($records)) {
            $qry = PrepINClauseStmt($qry, $records, ' and ((dec.docentrycostkey IS NULL) or (dec.docentrycostkey ', true, 'decsbyrecs');
            $qry[0] .= ')) ';
        } else {
            $qry[0] .= ' and dec.docentrycostkey IS NULL ';
        }
        $qry    = PrepINClauseStmt($qry, array_keys($items),      ' and dec.itemkey ', true, 'decsbyitems' );
        $qry    = PrepINClauseStmt($qry, array_keys($warehouses), ' and dec.whsekey ', true, 'decsbywarehouses' );
        $result = QueryResult($qry);
        return $result;
    }


    /**
     *  Negative Inventory Check helper
     *  Generate a key unique to an item/warehouse/tracking set of values
     *      Used to combine like docentrycosts
     *
     * @param string[]      $dec                            a docentrycost record (or documententrytrackdetail record)
     * @param bool          $generateItemIDForErrorMessage  optional: true means return just the decorated item id
     *
     * @return string                   the 'key'
     */
    private function _NIC_generateKey($dec, $generateItemIDForErrorMessage = false)
    {
        $itemID      = $dec['ITEMKEY'];
        $warehouseID = $dec['WHSEKEY']      ?? '';
        $sn          = $dec['SERIALNO']     ?? '';
        $lot         = $dec['LOTNO']        ?? '';
        $bin         = $dec['BINKEY']       ?? '';
        $exp         = $dec['EXPIRATION']   ?? '';

        // if desired, build a cheap international-ok string for error messages.
        // IF there is tracking, it decortes the item id with the tracking.
        if ($generateItemIDForErrorMessage) {
            $tracking = '';
            if ($sn !== '') {
                $tracking .= $sn;
            }
            if ($lot !== '') {
                $tracking .= ' ' . $lot;
            }
            if ($bin !== '') {
                $tracking .= ' ' . $bin;
            }
            if ($exp !== '') {
                $tracking .= ' ' . $exp;
            }
            $tracking = trim($tracking); // so, say LOT was the only tracking, this takes the extra leading space off.
            if ($tracking !== '') {
                $itemID = "$itemID ($tracking)";
            }
            return $itemID;
        }
        return "$itemID~$warehouseID~$sn~$lot~$bin~$exp"; // everything but quantity
    }


    /**
     *   Negative Inventory Check helper
     *      Given a set of docentrycost records that represent OUTBOUND (sales) transactions we need to
     *      find INBOUND (purchases) for, put them into the 'errors' format we will use to complain about.
     *
     *      Later we may find INBOUND to satisfy these OUTBOUND, but for now massage them into a good format.
     *
     *      Keep an eye out for Warehouse Transfer Out records as we can't move their source.
     *
     * @param string[][]    $docentrycosts      docentrycost records
     * @param bool          $wtOutFound         outbound: did we find warehouse-transfer OUTBOUND transactions?
     * @param int[]         $notDECs            record numbers of the docentrycost records to avoid when reading
     *                                          potential sources for these records (i.e. avoid RETURNS)
     *
     * @return array                            the list of potential errors (well, records we need sources for)
     */
    private function _NIC_reformatOutboundInNeedOfNewInbound($docentrycosts, &$wtOutFound, &$notDECs)
    {
        // if any are warehouse transfer outs, we won't need further checking.
        // you cannot change the source for a warehouse transfer
        $wtOutFound = false;
        foreach ($docentrycosts as $row) {
            $wtOut = ($row['DOCPARID'] === 'SYS-Warehouse Transfer Out');
            if ($wtOut) {
                $wtOutFound = true;
                break;
            }
        }

        $notDECs    = [];
        $rtn        = [];
        foreach ($docentrycosts as $row) {
            $key                           = $this->_NIC_generateKey($row);
            $date                          = DateTime::createFromFormat( 'm/d/Y', $row['DATEIN'] );
            $date                          = $date->setTime(0,0,1,0);
            $timestamp                     = $date->getTimestamp();
            $wtOut                         = ($row['DOCPARID'] === 'SYS-Warehouse Transfer Out');
            unset($date);
            $recordNo                      = $row['RECORD#'];

            // if there ARE warehouse transfer outs, and this is NOT one,
            // then don't save the record as a possible error since we're not going to check.....
            if ($wtOutFound && ($wtOut === false)) {
                continue;
            }

            // don't find a new inbound with this record as a descendent (i.e. a RETURN)
            if ($recordNo > 0) { // but exclude kits
                $notDECs[] = $recordNo;
            }
            // lets assume these all fail, when we get new inbounds we can clean these up.....
            $itemID      = $this->_NIC_generateKey($row, true); // encode tracking if present.
            $warehouseID = $row['WHSEKEY'];
            $quantity    = $row['TOTALTOFIND'] ?? $row['QUANTITY'];
            $docid       = $row['DOCID'];
            $rtn[$key][] = ['ITEMKEY' => $itemID, 'WHSEKEY' => $warehouseID, 'QUANTITY' => $quantity,
                              'DATEIN' => $row['DATEIN'], 'DOCID' => $docid, 'ISWTOUT' => $wtOut, 'TIMESTAMP' => $timestamp];
        }
        return $rtn;
    }


    /**
     *   Negative Inventory Check helper
     *      Given a set of OUTBOUND (sales) and INBOUND (purchases), see if we can find enough quantity for
     *      the outbounds from the inbounds, including tracking.
     *
     * @param string[][][]    $inbound        inbound docentrycosts in their record format; indexed by key
     * @param string[][][]    $outbound       outbound docentrycosts in the ERRORS format (not the same as
     *                                        a docentrycost record); indexed by key
     *
     *                                        Note: the index key is from _NIC_generateKey() and is used to
     *                                          collate item/warehouse/tracking, but NOT quantity, time, or docid
     *
     * @return mixed
     */
    private function _NIC_matchInboundToOutbound($inbound, $outbound)
    {
        $rtn = [];

        // Step 4: for each of the found OUTBOUND (sale) records, see if we have enough room in the NEW INBOUND records...
        //     (in other words, when this txn goes away, will MIV be able to find new homes for the sales?)
        foreach ($outbound as $key => $outs) {
            // are there any inbounds with the same item/wh/tracking?
            if (isset($inbound[$key])) {
                // then, for each of the outbound (sale), look for an earlier inbound (purchase)
                // we walk UP from the most recent date to pack things better
                foreach ($outs as $outIndex => $out) {
                    $outtimestamp   = $out['TIMESTAMP'];
                    $quantityToFind = $out['TOTALTOFIND'] ?? $out['QUANTITY'];
                    foreach ($inbound[$key] as $inIndex => $in) {
                        $intimestamp    = $in['TIMESTAMP'];
                        $totalFound     = $in['TOTALFOUND'];
                        if (($intimestamp <= $outtimestamp) && ($totalFound > 0)) {
                            if ($totalFound >= $quantityToFind) {
                                $totalFound     = ibcsub($totalFound, $quantityToFind, ItemManager::AVERAGE_COST_DECIMALS, true);
                                $quantityToFind = 0;
                            } else {
                                $quantityToFind = ibcsub($quantityToFind, $totalFound, ItemManager::AVERAGE_COST_DECIMALS, true);
                                $totalFound     = 0;
                            }
                            $inbound[$key][$inIndex]['TOTALFOUND'] = $totalFound; // so we don't double count later
                            $outs[$outIndex]['QUANTITY'] = $quantityToFind;   // need to find less, but still need SOME
                            $outs[$outIndex]['DATEIN']   = $in['DATEIN'];     // last date we saw something
                        }
                    }
                }
            }

            // after all that, are we still in need of quantity?  If so, then that is an error.
            foreach ($outs as $out) {
                if ($out['QUANTITY'] > 0) {
                    $rtn[] = $out;
                }
            }
        }
        return $rtn;
    }


    /**
     *   Negative Inventory Check helper
     *  Given items and warehouses, and optional lists of records NOT to get, fetch all inbound with
     *  quantity left.
     *
     * @param   string[]        $items                  The items we are finding inbound for
     * @param   string[]        $warehouses             Ditto the warehouses
     * @param   int[]           $notTheseInbound        [optional] ignore THESE records
     * @param   int[]           $notTheseSources        [optional] ignore THESE docentrycostkeys
     *
     * @return array|false
     */
    private function _NIC_GetInboundsToSatisfyOutbounds($items, $warehouses, $notTheseInbound, $notTheseSources)
    {
        if (empty($items)) {
            return [];
        }

        // See if we can find new sources for the items and warehouses,
        //      NOT including optional inbound transactions (e.g. deleting an inbound, don't find the same inbound!)
        //      NOT including optional sources (e.g. a RETURN being the source for the sale)
        //      This can return more transactions than we need, because we specify a list of items and warehouses, but not THIS item for THIS warehouse
        //
        //   Note that we don't care HERE about the transaction date, nor ocentrycostkits

        // This could yield a LOT of records, though we hope not usually....
        $qry = [];
        $qry[] = "select datein, itemkey, whsekey, serialno, lotno, binkey, expirationdate, sum(qtyLeft) as totalFound
                    from docentrycost 
                    where cny# = :1 
                      and affects_inventory IN ('Q','QV')
                      and in_out = 'I'
                      and adjdocentrycostkey IS NULL
                      and qtyLeft > 0
                      ";
        $qry[] = GetMyCompany();
        if ( ! empty($notTheseSources)) { // maybe all the records are stockable kits
            $qry = PrepINClauseStmt($qry, $notTheseSources, ' and ((docentrycostkey is null) or (docentrycostkey NOT ', true,'docentrycostkey');
            $qry[0] .= "))";
        }
        if ( ! empty($notTheseInbound)) { // maybe we didn't start with returns or purchases
            $qry = PrepINClauseStmt($qry, $notTheseInbound, ' and record# NOT ', true, 'recordno');
        }

        $qry = PrepINClauseStmt($qry, array_keys($items),      ' and itemkey ', true, 'itemkey');
        $qry = PrepINClauseStmt($qry, array_keys($warehouses), ' and whsekey ', true, 'whsekey');
        $qry[0] .= " group by datein, itemkey, whsekey, serialno, lotno, binkey, expirationdate";
        $result = QueryResult($qry);
        if ($result === false) {
            return false;
        }

        // index the new inbound records so we can find them easier....
        // (could be empty!)
        $newInbound = [];
        foreach ($result as $row) {
            $key                            = $this->_NIC_generateKey($row);
            $date                           = DateTime::createFromFormat( 'm/d/Y', $row['DATEIN'] );
            $date                           = $date->setTime(0,0,1,0);
            $timestamp                      = $date->getTimestamp();
            unset($date);
            $row['TIMESTAMP']               = $timestamp;
            $newInbound[$key][]             = $row;
        }
        return $newInbound;
    }


    /**
     *  If you are about to delete a transaction, or entries from a transaction, or reduce the quantity on
     *  a transaction line, call this to see if that is ok.
     *
     *  Goal: prevent the transaction items from going negative.
     *
     *  This is protected and is intended to be called from special routines such as checkForNegativeInventory(), below.
     *
     *  Preconditions:
     *      - the caller has determined that we want to reduce the quantity of an item/warehouse pair
     *          - maybe because we're deleting one or more lines from a purchase, for example
     *      - the caller determined the transaction updates ON HAND (Q or QV)
     *      - the transaction is not a draft
     *      - If an item needs tracking data, that tracking data is supplied
     *
     *  Return on NO ERROR but nothing wrong:
     *      empty array
     *
     *  Return on error:
     *      - If SQL error, false
     *      - Array of
     *          ITEMKEY, WHSEKEY, DATEIN (date of failure), QUANTITY (the portion we could not find)
     *
     * @param array  $entries           the docentrycost records to act on
     *
     * @return bool|array               if false, sql error, otherwise for each item there is an error or no error
     *
     */
    protected function canIRemoveDocEntryCosts($entries)
    {
        // figure out what we need to do here, if anything
        $records    = $this->normalizeEntriesForNegativeCheck($entries, $itemWarehouseQuantities, $items, $warehouses, $allRecords, true);

        // did we filter them all out?  Like, they all had plenty of quantity left?
        if (empty($records)) {
            return [];
        }

        // Step 2: Bulk get the sales (output) tied to these purchase (input) costing records
        $result = $this->_NIC_findOutboundByDECK($records);
        if (($result === false) || empty($result)) {
            return $result;
        }

        // Step 2b get the error returns setup and ready for further checks:
        $outbound = $this->_NIC_reformatOutboundInNeedOfNewInbound($result, $wtOutFound, $notDECs);
        if ($wtOutFound === true) {
            return $outbound;        // eeek!  Can't delete the source of a warehouse transfer out
        }

        unset($result);     // maybe save some ram

        // Step 3 find inbound records with quantity left
        $newInbound = $this->_NIC_GetInboundsToSatisfyOutbounds($items, $warehouses, $allRecords, $notDECs);
        if ($newInbound === false) {
            return false;
        }

        // Step 4: for each of the found OUTBOUND (sale) records, see if we have enough room in the NEW INBOUND records...
        //     (in other words, when this txn goes away, will MIV be able to find new homes for the sales?)
        $errors = $this->_NIC_matchInboundToOutbound($newInbound, $outbound);

        // what's left is nothing but failure....
        // ("if it wasn't for bad luck, I'd have no luck at all")
        return $errors; // could be empty
    }


    /**
     *  Negative Inventory Check Helper
     *  We have SAVED an outbound record (sale/purchase return/adjust down/etc)
     *  Can all of its records find a new home?
     *
     * @param array     $docentrycosts  The records to make sure we have sources for
     * @param string    $earliestDate   Don't look prior to this
     *
     * @return array|bool
     */
    protected function _NIC_postSaveOutboundNotNegative($docentrycosts, $earliestDate)
    {
        // **** HELPERS *****
        $findItemWarehouses = function($docentrycosts, &$items, &$warehouses, &$records) {
            $items = [];
            $warehouses = [];
            $records = [];

            foreach ($docentrycosts as $entry) {
                $itemID = $entry['ITEMKEY'] ?? '';
                $warehouseID = $entry['WHSEKEY'] ?? '';
                $quantity = $entry['QUANTITY'] ?? 0;
                $recordNo = $entry['RECORD#'] ?? ($entry['RECORDNO'] ?? 0);

                // An empty or quantity zero/negative entry?  Skip it.
                if (($recordNo === 0) ||
                    ($itemID === '') ||
                    ($warehouseID === '') ||
                    ($quantity <= 0)) {
                    continue;
                }

                $items[$itemID] = true;
                $warehouses[$warehouseID] = true;
                // if this entry was in a txn before but it now missing, add it to the pile
                if (isset($entry['MISSING'])) {
                    $records[] = $recordNo;
                }
            }
        };

        // ***** MAIN ****
        $findItemWarehouses($docentrycosts, $items, $warehouses, $records);

        // Step 1: Here we get ALL outbounds with no source, not just the ones for the saved transaction.
        // Why?  Because MIV may not have run in a while and we need to make sure ALL outbounds
        // have a matching inbound.  This returns all outbound costs with no source
        // (on or after the given date, so we don't go back into closed periods)
        $result = $this->_NIC_findOutboundByItemWarehouse($records, $items, $warehouses, $earliestDate);
        if (($result === false) || empty($result)) {
            return $result;
        }

        // Step 2 get the error returns setup and ready for further checks:
        $outbound = $this->_NIC_reformatOutboundInNeedOfNewInbound($result, $wtOutFound, $notDECs);
        if ($wtOutFound === true) {
            return $outbound;        // eeek!  Can't delete the source of a warehouse transfer out
        }

        unset($result);     // maybe save some ram

        // Step 3 find inbound records with quantity left
        $newInbound = $this->_NIC_GetInboundsToSatisfyOutbounds($items, $warehouses, [], []);
        if ($newInbound === false) {
            return false;
        }

        // Step 4: for each of the found OUTBOUND (sale) records, see if we have enough room in the NEW INBOUND records...
        //     (in other words, will MIV be able to find new homes for the sales?)
        $errors = $this->_NIC_matchInboundToOutbound($newInbound, $outbound);

        // what's left is nothing but failure....
        // ("if it wasn't for bad luck, I'd have no luck at all")
        return $errors; // could be empty
    }


    /**
     *      Negative Inventory Check
     *
     * Assuming a purchase being updated, collate old and new docentrycost records to see what additional sales
     * we should look for to see if they were affected.  For example, if they deleted a row that purchased
     * 5 hammers, there may be sales dependant on those hammers.
     *
     * @param array     $old        docentrycosts from before we saved the transaction (especially ones that we think are different)
     * @param array     $new        docentrycosts from after we saved the transaction
     *
     * @return array                Additional (fake) docentrycosts to see if there are sales depending on
     */
    private function _NIC_collateOldAndNewDocentrycosts($old, $new)
    {
        $keys = [];
        $rtn  = [];

        // add up all the tracking values in old and then subtract equivelent new so we can compare.
        // if the resulting number is POSITIVE, then thats how much we need to find, but if
        // the resulting number is zero or less, then we're good.
        //
        //  Remember that, because of cost layers, there can be multiple records for, say, the same lot
        //
        //  Example:  Assume a purchase being updated:
        //          OLD:  LOT A, Quantity 3
        //          NEW:  LOT A, Quantity 2 <-- result will be +1, which is what we need to find
        //
        //          OLD:  LOT A, Quantity 3
        //          NEW:  (not found)       <-- we need to find 3
        //
        //          OLD:  LOT A, Quantity 3
        //          NEW:  LOT A, Quantity 3 (or more) <-- fine as is
        foreach ($old as $row) {
            $key      = $this->_NIC_generateKey($row);
            $quantity = $row['QUANTITY'] ?? 0;
            if (isset($keys[$key])) {
                $keys[$key]['Q'] = ibcadd($keys[$key], $quantity, ItemManager::BASEUNITPRECISION, true);
            } else {
                $keys[$key]['Q'] = $quantity;
                $keys[$key]['R'] = $row;    // only need one, as a proxy for all similar ones
            }
        }
        foreach ($new as $row) {
            $key      = $this->_NIC_generateKey($row);
            $quantity = $row['QUANTITY'] ?? 0;
            // if the key is not in the array then this is something new, which is ok
            if (isset($keys[$key])) {
                $keys[$key]['Q'] = ibcsub($keys[$key], $quantity, ItemManager::BASEUNITPRECISION, true);
            }
        }

        // now run through to see what we still need to find
        foreach ($keys as $row) {
            $quantity = $row['Q'];
            if (ibccomp($quantity, '0') > 0) {  // something in OLD but not NEW?
                $addThisRow = $row['R'];
                $addThisRow['TOTALTOFIND'] = $quantity;
                $addThisRow['QUANTITY'] = $quantity;
                $addThisRow['MISSING'] = true;
                $rtn[] = $addThisRow;
            }
        }
        return $rtn;
    }


    /**
     *      If we are about to add/update/delete a transaction that would make ONHAND go negative, and we don't allow
     *  going negative, then don't let the customer delete this transaction.
     *
     * For deletes, call this BEFORE calling EntityManager::Delete()
     * For the others, call this AFTER calling EntityManager::RegularAdd/Set()
     *
     *  IMPORTANT: make sure the direction is correct (i.e. are you deleting items or disassembling things?)
     *      The default error message is for deleting items, pass in another routine for other uses, such
     *      as Disassembling kits
     *
     * @param array     $docObj
     * @param string    $addUpdateOrDelete    'A' - adding a txn, 'U' - updating, 'D' - deleting
     * @param bool      $beforeSave           Are we being called BEFORE or AFTER the EntityManager save?
     * @param callback  $errorReporter        callback to display the error, so this can be used by more than just delete.
     *                                        call with the docid, item and warehouse in error and quantity needed
     *
     * @return bool
     */
    protected function checkForNegativeInventory(&$docObj, $addUpdateOrDelete, $beforeSave, $errorReporter = null)
    {
        //  *****************************
        //  HELPER ROUTINES
        //  *****************************

        /** @var callable $getCurrentDocEntryCosts  get all the docentrycost records that affect quantity and/or value */
        $getCurrentDocEntryCosts = function($entries, &$result, &$tracked) {
            $docentries = [];
            $tracked = false;
            foreach ($entries as $entry) {
                $recordno = $entry['RECORD#'] ?? ($entry['RECORDNO'] ?? 0);
                if ($recordno > 0) {
                    $docentries[] = $recordno;
                }
            }

            // Get any existing docentrycost records?  Note that if we ask for a non-inventory item, we won't get it...
            $result = [];
            if ( ! empty($docentries)) {
                $qry   = [];
                $qry[] = "select record#, datein, itemkey, whsekey, quantity, qtyleft, in_out, docentrycostkey,
                                serialno, lotno, binkey, expirationdate
                          from docentrycost 
                          where cny# = :1 
                          and affects_inventory IN ('Q','QV')";
                $qry[]  = GetMyCompany();
                $qry    = PrepINClauseStmt($qry, $docentries, ' and docentrykey ');
                $result = QueryResult($qry);
            }
            if (($result !== false) && ! empty($result)) {
                $sn  = $result[0]['SERIALNO'] ?? '';
                $lot = $result[0]['LOTNO'] ?? '';
                $bin = $result[0]['BINKEY'] ?? '';
                $exp = $result[0]['EXPIRATIONDATE'] ?? '';
                if (($sn !== '') || ($lot !== '') || ($bin !== '') || ($exp !== '')) {
                    $tracked = true;
                }
            }
            return ($result !== false);
        };


        /** @var callable $findEarliestTransactionDate */
        $findEarliestTransactionDate = function($docObj) {
            // this is the txn date, but if we CHANGED the date, then we want the date in the existing entries....
            $earlyDate = $docObj['WHENCREATED'];
            foreach ($docObj['ENTRIES'] as $entry) {
                $recno = $entry['RECORDNO'] ?? 0; // 0 means it is a new record
                if (($recno > 0) && isset($docObj['EXISTING_ENTRIES'][$recno])) {
                    if (DateCompare($earlyDate, $docObj['EXISTING_ENTRIES'][$recno]['WHENCREATED']) > 0) {
                        $earlyDate = $docObj['EXISTING_ENTRIES'][$recno]['WHENCREATED'];
                    }
                }
            }
            return $earlyDate;
        };


        /** @var callable $reportErrors  given the error list, format and print the errors. */
        $reportErrors = function($errors, $errorReporter) {
            if ($errors === false) {
                return false; // prior error, likely a DB problem
            }
            $errorsReported = 0;
            $ok             = true;
            foreach ($errors as $error) {
                $itemID      = $error['ITEMKEY'];
                $warehouseID = $error['WHSEKEY'];
                $datein      = $error['DATEIN'];
                $quantity    = $error['QUANTITY'];
                $docid       = $error['DOCID'];
                $wtOut       = $error['ISWTOUT'] ?? false;
                $ok          = false;  // found an error

                // TODO: There may be many errors in the array, but we currently only report a few of them....
                if ($wtOut) {
                    $msg = "This transaction is the source for Warehouse Transfer '$docid', and so cannot be deleted or changed.";
                    $corr = "Remove the warehouse transfer first, then try again.";
                    Globals::$g->gErr->addIAError(
                        'INV-1277', __FILE__ . ':' . __LINE__,
                        $msg, ['DOCID' => $docid],
                        '', [],
                        $corr, []
                    );
                } else if ($errorReporter !== null) {
                    $errorReporter( $itemID, $warehouseID, $quantity, $datein, $docid );
                } else {
                    $msg = "Posting this transaction will cause ON-HAND to be negative for item '$itemID' in warehouse '$warehouseID'.";
                    $addl = '';
                    $errorCode = 'INV-1324';
                    $corrPlaceholder = ['QUANTITY' => $quantity, 'DATEIN' => $datein];
                    if ($docid !== '') {
                        $addl = "or delete '$docid',";
                        $errorCode = 'INV-1325';
                        $corrPlaceholder = array_merge($corrPlaceholder, ['DOCID' => $docid]);
                    }
                    $corr = "Receive at least $quantity more of the items into inventory as of $datein, $addl then try again.";
                    Globals::$g->gErr->addIAError(
                        $errorCode, __FILE__ . ':' . __LINE__,
                        $msg, ['ITEMID' => $itemID, 'WAREHOUSEID' => $warehouseID],
                        '', [],
                        $corr, $corrPlaceholder
                    );
                }
                $errorsReported++;
                if ($errorsReported >= 4) { // lets try putting out four errors at most
                    break;
                }
            }
            return $ok;
        };


        //  *****************************
        //  MAIN CODE
        //  *****************************
        $ok = true;

        // we care about inbound value transactions; they affect on-hand.
        //     Deleteing them could cause one or more items to go negative.
        // Likewise we care abut Purchase Returns and other outbound transactions.
        //     Adding new outbound sales could cause subsequent sales to fail
        //     Adding a new Purchase Return could cause subsequent sales to fail (same as delete)
        $updatesInv         = $docObj['_DOCPAR']['UPDATES_INV'];
        $affectsInventory   = array('Quantity', 'Value', 'Quantity and Value');   // affects on-hand?
        $inOut              = $docObj['_DOCPAR']['IN_OUT'];
        $draft              = ($docObj['STATE'] == self::DRAFT_STATE);

        // Not a draft.  Inbound.  Affects Inventory.  Has entries.  We don't want negative inventory.
        $shouldBeHere       = (( ! $draft) &&
                                in_array($updatesInv, $affectsInventory) &&
                                (! IsNegativeInventoryAllowed()) &&
                                (Util::countOrZero($docObj['ENTRIES']) > 0));

        // not one of those?
        if ( ! $shouldBeHere) {
            return $ok;     // no error, but nothing more to do
        }

        switch ($addUpdateOrDelete) {
            case 'A':
                // Note: the add has been saved before we're called
                // adding a purchase return or sale?
                // (Adding MORE to inventory is always welcome)
                if ($inOut === 'Increase') {
                    break;
                }
                // ELSE FALL THROUGH

            case 'U':
                // after we save, see if there are dangling outbounds with no possible source inbounds....
                if ($beforeSave) {
                    $docObj['_NIC_PriorDocEntryCosts']        = [];
                    $docObj['_NIC_PriorDocEntryCostsTracked'] = false;
                    // for purchases/inbound, lets see if the user removed or decreased line items, including tracking
                    if  ($inOut === 'Increase') {
                        if (isset($docObj['EXISTING_ENTRIES'])) {
                            $ok = $getCurrentDocEntryCosts($docObj['EXISTING_ENTRIES'], $docObj['_NIC_PriorDocEntryCosts'], $tracked);
                            $docObj['_NIC_PriorDocEntryCostsTracked'] = $tracked;
                        }
                    }
                } else {
                    // if a purchase moves, take the earlier of the before and after dates...
                    $effectiveDate = ($inOut === 'Increase') ? $findEarliestTransactionDate($docObj) : $docObj['WHENCREATED'];
                    $ok = $getCurrentDocEntryCosts($docObj['ENTRIES'], $result, $tracked);
                    if ($ok && ! empty($result)) {
                        $errors = [];
                        if  ($inOut === 'Increase') {
                            // Did user remove entries or significantly alter them?
                            $tracked  = $tracked || $docObj['_NIC_PriorDocEntryCostsTracked'];
                            $leftover = $this->_NIC_collateOldAndNewDocentrycosts($docObj['_NIC_PriorDocEntryCosts'], $result);   // include any deleted entries
                            unset($docObj['_NIC_PriorDocEntryCosts']); // free up the ram
                            $result = array_merge($result, $leftover);
                        }
                        if ($tracked) {
                            $errors = $this->_NIC_postSaveOutboundNotNegative($result, $effectiveDate);
                        }

                        // do a general-purpose, non-tracking-aware check
                        if (($errors !== false) && empty($errors)) {
                            $errors = $this->enoughQuantityOnHand($result, $effectiveDate, true);   // true == after save
                        }
                        $ok = $ok && $reportErrors($errors, $errorReporter);
                    }
                }
               break;

            case 'D':
                // deleting something that brought IN inventory?
                if ($beforeSave && ($inOut === 'Increase')) {
                    $ok = $getCurrentDocEntryCosts($docObj['ENTRIES'], $result, $tracked);
                    if ($ok && ! empty($result)) {
                        // will there be enough QOH when we delete (not respecting tracking, but faster)
                        $errors = $this->enoughQuantityOnHand($result, $docObj['WHENCREATED'], false);  // false == before save
                        if (($errors !== false) && empty($errors) && $tracked) {
                            // Ok so far, but what about tracking?
                            $errors = $this->canIRemoveDocEntryCosts($result);
                        }
                        $ok = $reportErrors($errors, $errorReporter);
                    }
                }
                break;
            default:
                throw new Exception("[CODE BUG]Expected 'A', 'U', or 'D', but got $addUpdateOrDelete .");
        }
        return $ok;
    }


    /**
     *      For each child docentry, we want to update the item/warehouse record as 'needs update' so the next time
     * costing runs, it catches this delete.  If, later on, we DON'T delete this record, well, thats ok but it can cost
     * extra time the next time we run costing.
     *
     * @param array $docObj
     *
     * @return bool
     *
     *   UPDATE: We now use the DELETE_LOG, so this isn't nescessary.  Maybe there will be other uses in the future?
    protected function markItemWarehousesAsNeedsUpdate(&$docObj)
    {
        $ok = true;
        if (isset($docObj['RECORDNO']) && ($docObj['RECORDNO'] > 0)) {
            $query = [];

            // Find all the item/warehouse combos in this transaction and mark their item/warehouse records
            //      as 'costing must run'.  I suppose we could have a 'on or after' date in the iw record, but
            //      for now we're just brute force.
            // Note: We do not care about standard cost entries, they aren't changed by a transaction delete
            //      also, merging two 'distinct' entries may give SOME dups but oh well.
            $query[] = "UPDATE icitemwhse set costingmustrun = 'T'
                        WHERE  cny# = :1
                        AND    record# in (
                            SELECT distinct iw.record# 
                            FROM    icitemwhse iw, icitemmst i, dochdrmst d, docentrymst de, docentrycost dec
                            WHERE
                                    iw.cny# = :1
                                AND i.cny# = iw.cny#
                                AND d.cny# = iw.cny#
                                AND de.cny# = iw.cny#
                                AND dec.cny# = iw.cny#
                                AND d.record# = :2
                                AND de.dochdrkey=d.record#
                                AND dec.docentrykey=de.record#
                                AND dec.itemkey = iw.itemkey
                                AND dec.whsekey = iw.warehousekey
                                AND dec.in_out = 'I'
                                AND ((dec.affects_inventory = 'V') OR (dec.affects_inventory = 'QV'))
                                AND i.itemid = dec.itemkey
                                AND i.cost_method IN ('F','L','A')  -- not standard costs
                                AND i.itemtype in ('I','K','SK') 
                            
                            UNION ALL    
                                
                            SELECT distinct iw.record# 
                            FROM    icitemwhse iw, icitemmst i, dochdrmst d, docentrymst de, docentrycostkits dec
                            WHERE
                                    iw.cny# = :1
                                AND i.cny# = iw.cny#
                                AND d.cny# = iw.cny#
                                AND de.cny# = iw.cny#
                                AND dec.cny# = iw.cny#
                                AND d.record# = :2
                                AND de.dochdrkey=d.record#
                                AND dec.docentrykey=de.record#
                                AND dec.itemkey = iw.itemkey
                                AND dec.whsekey = iw.warehousekey
                                AND dec.in_out = 'I'
                                AND ((dec.affects_inventory = 'V') OR (dec.affects_inventory = 'QV'))
                                AND i.itemid = dec.itemkey
                                AND i.cost_method IN ('F','L','A')  -- not standard costs
                                AND i.itemtype in ('I','K','SK') 
                        )
                        ";
            $query[] = GetMyCompany();
            $query[] = $docObj['RECORDNO'];

            $ok = ExecStmt($query);
        }
        return $ok;

    }
    *************************** */

    /**
     * @param array $docObj
     *
     * @return bool
     * @throws Exception
     */
    protected function checkMacroLinks(&$docObj)
    {
        $ok = $this->checkForMacroChildDoc($docObj);
        $ok = $ok && $this->checkForMacroParentDoc($docObj);

        return $ok;
    }

    /**
     * @param array $docObj
     *
     * @return bool
     */
    protected function checkForMacroChildDoc(&$docObj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;

        if ($docObj['SCMMACROLINK'] == 'T') {
            $macroNames = $this->getMacroNames();
            foreach ($macroNames as $macroName) {
                $ok = $this->deleteMacroLinks($docObj, $macroName);
                if (!$ok) {
                    SCMMacroManager::getMacroErrorMessage($macroName, "MACRO002", $msg, $corr, [], $errorCode, $placeholder);
                    $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
                }
            }
        } else {
            foreach ((($docObj['ENTRIES']) ?? []) as $entry) {
                if ($entry['SCMMACROLINK'] == 'T') {

                    /**
                     * @var DocumentEntryManager $entryMgr
                     */
                    $entryMgr = $gManagerFactory->getManager(
                        $this->mod . 'documententry', false, array('DOCTYPE' => $docObj['DOCPARID'])
                    );

                    $macroNames = $entryMgr->getMacroNames();

                    foreach ($macroNames as $macroName) {
                        $ok = $this->deleteMacroLinks($docObj, $macroName);
                        if (!$ok) {
                            SCMMacroManager::getMacroErrorMessage($macroName, "MACRO002", $msg, $corr, [], $errorCode, $placeholder);
                            $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
                        }
                    }

                    break;
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $docObj
     *
     * @return bool
     */
    protected function checkForMacroParentDoc(&$docObj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ok = true;

        $scmMacroResolveMgr = $gManagerFactory->getManager('scmmacroresolve');

        $params = array(
            'selects' => array(
                'MACRONAME',
                'SOURCEDOCENTRYKEY',
                'SOURCEDOCKEY'
            ),
            'filters' => array(
                array(array('TARGETDOCKEY', '=', $docObj['RECORDNO']))
            ),
        );

        $sourceMacroRecs = $scmMacroResolveMgr->GetList($params);

        if (!empty($sourceMacroRecs)) {
            $ok = $ok && $this->updateMacroParentDoc($sourceMacroRecs);
        }

        return $ok;
    }

    /**
     * @param array $sourceMacroRecs
     *
     * @return bool
     */
    protected function updateMacroParentDoc(/** @noinspection PhpUnusedParameterInspection */ $sourceMacroRecs)
    {
        return true;
    }

    /**
     * @param array  $docObj
     * @param string $macroName
     *
     * @return bool
     */
    protected function deleteMacroLinks(
        /** @noinspection PhpUnusedParameterInspection */$docObj,
        /** @noinspection PhpUnusedParameterInspection */ $macroName
    )
    {
        return false;
    }

    /**
     * Delete the values for the document using the id of the document.
     *
     * @param string $ID ID of the document.
     *
     * @return bool method execution was success or not.
     */
    public function Delete($ID)
    {
        $priorValue = ConversionManager::$documentIsBeingDeleted;
        ConversionManager::$documentIsBeingDeleted = true;

        $tmp = self::$upsertFeaturInUse;    // in case any smart events cause us to re-enter this code
        self::$upsertFeaturInUse = false;
        $ok = $this->deleteWithOverride($ID, false);
        self::$upsertFeaturInUse = $tmp;

        ConversionManager::$documentIsBeingDeleted = $priorValue;
        return $ok;
    }

    /**
     * Delete the values for the document using the id of the document with the option to override the delete policy in transaction defintion
     *
     * @param string $ID                ID of the document.
     * @param bool   $forceDelete       ignore delete policy in transaction definition
     * @param bool   $checkNegInventory true if we want to check for negative inventory before we can delete
     *
     * @return bool method execution was success or not.
     */
    public function deleteWithOverride($ID, $forceDelete, $checkNegInventory=false)
    {
        $source = 'DocumentManager::Delete()';

        global $gErr, $gManagerFactory;
        $docparMgr = $this->get_docpar_manager();

        $this->setSCMTrigger(true);
        $ok = $this->_QM->beginTrx($source);

        $docObj = $this->BaseGet($ID);

        /**
         * @var DocumentEntryManager $documententryMgr
         */
        $documententryMgr =  $gManagerFactory->getManager($this->mod . 'documententry', false, array( 'DOCTYPE' => $docObj['DOCPARID']));

        if (!$this->_docType && $docObj['DOCPARID']) {
            $this->_docType = $documententryMgr->_docType = $docObj['DOCPARID'];
        }

        $docObj['_DOCPAR'] = $docparMgr->BaseGet($docObj['DOCPARKEY']);

        $docObj['ENTRIES'] = $documententryMgr->GetByParent($docObj['RECORDNO']);

        $ok = $ok && $this->checkMacroLinks($docObj);

        // check if the document is created from multiple source transactions
        $this->checkIsCreatedFromMultipleSourceDocuments($docObj, $sourceDockeys);

        // Do not allow deleting source documents that have had retainage released
        if ( self::isRetainageReleased($docObj['DOCID']) ) {
            $msg = "This document can not be deleted because retained invoices have been created against the original invoice.  In order to edit or delete this document, all released retainage invoices must be deleted.";
            $gErr->addIAError('INV-1278', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }

        $docObj['_do'] = 'delete';
        $docObj['_mod'] = $this->mod;

        $ok = $ok && $this->validateCCODelete($docObj);

        $ok = $ok && $this->handlePostedChangeDocDelete($docObj);

        $ok = $ok && $this->ProcessDeleteOrSet($docObj);

        $ok = $ok && $this->_IsTransactionDeletable($docObj, $forceDelete, $checkNegInventory);

        $ok = $ok && $this->updateDeliveryLog($docObj['RECORDNO']);

        $this->ProcessSmartEventForAPAR('Delete', $docObj);

        // Below lines override the corresponding variables IMSSubscriptionManager::FillSubscriptions
        // If these are missing then get added, this will help integration keep working for mega company
        $this->_substatecache['RECORDNO'] = $docObj['RECORDNO'];
        $this->_substatecache['DOCPARID'] = $docObj['DOCPARID'];
        $this->_substatecache['CUSTVENDID'] = $docObj['CUSTVENDID'];

        $ok = $ok && $this->deletePostings($docObj, DELETE_FOR_DELETE);

        // since the costing code won't find this transaction in the list as having been updated,
        // lets explicitly tell it what happened.
        // Update: we now use the DELETE_LOG, so this is not as useful....
        // $ok = $ok && $this->markItemWarehousesAsNeedsUpdate($docObj);

        $ok = $ok && CostingHandler::initializeCosting();

        $ok = $ok && parent::Delete($ID);

        $ok = $ok && $docparMgr->CleanupTemplateVersion($docObj['_DOCPAR']);

        //delete supporting document as the supdocmaps manager cannot get the value from id we //send
        if (isset($this->_schemas[$this->_entity]['supdocentity'])) {
            DeleteSupDocId($docObj, $this->_schemas[$this->_entity]['supdocentity']);
        }

        // Delete XML blob from BLOBSTORE.
        $blobStoreMgr = $gManagerFactory->getManager('blobstore');
        $ok = $ok && $blobStoreMgr->DeleteByParent($ID, 'INVDOCXML');

        // Delete record from the Sales Tax partner is one exists

        $ok = $ok && $this->DeletePartnerRecord($docObj);

        $ok = $ok && $this->postHandleChangeDocDelete($docObj);

        //***NEED TO BE SET TO NOT DEQUEUE IMS REQUEST IN CASE OF ERROR.
        $subscription =  $gManagerFactory->getManager('imssubscription');

        // we've deleted a transaction.  If it had any traces of Supplies Inventory in it,
        // remove any links to other transactions.
        if ($ok && ItemManager::isSuppliesInventoryEnabled()) {
            $suppliesManager = Globals::$g->gManagerFactory->getManager('invsupplies');
            $suppliesManager->documentIsBeingDeleted($docObj);
        }

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not delete Inventory transaction record with ID $ID!";
            $gErr->addIAError('INV-1279', __FILE__ . ':' . __LINE__, $msg, ['ID' => $ID]);
            epp("$source: Error: $msg");
            $subscription->noDequeue = true;
            $this->_QM->rollbackTrx($source);

        }

        return $ok;
    }

    /**
     * Get the object to delete
     *
     * @param string $id the ID of the object to dete
     *
     * @return array the object to delete
     */
    protected function getForDelete($id)
    {
        $obj = QueryResult(
            array(
                "SELECT * FROM dochdrmst WHERE docid = :1  AND cny# = :2",
                $id,
                GetMyCompany()
            )
        );
        $this->_ProcessResultForOwnership($obj[0]);
        return $obj;
    }

    /**
     * This function needs to be overridden by the child classes.
     *
     * @param  string $verb contains operation to be performed E.g., Add, Set, etc
     * @param  array &$values values of the transaction
     */
    function ProcessSmartEventForAPAR(
        /** @noinspection PhpUnusedParameterInspection */ $verb,
        /** @noinspection PhpUnusedParameterInspection */ $values)
    {
    }

    /**
     * Method to find out if the passed in docpar transaction definition has at least one subtotal line with
     * ISTAX turned on as 'true'.
     *
     * @param  array $docpar values of the transaction definition
     *
     * @return bool
     */
    public static function hasTaxSubTotals($docpar)
    {
        if( $docpar['SHOW_TOTALS'] ) {
            foreach ($docpar['DOCPAR_SUBTOTAL'] as $docparSubTotal) {
                if ($docparSubTotal['ISTAX'] == 'true') {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @param array $values
     * @param int $index
     * @param array $uomInfoVals
     *
     * @return bool
     */
    private function prepareEntryitemUOM(&$values, $index, $uomInfoVals)
    {
        $entry = &$values['ENTRIES'][$index] ?? [];
        if (Util::countOrZero($entry['ITEMUOM'] ?? []) == 0 || Util::countOrZero($uomInfoVals ?? []) > 0) {
            // When line item has a price conversiontype we should have the ITEMUOM values to valiate the base unit
            $itemid = explode('--', ($entry['ITEMID'] ?? ''))[0] ?? '';
            $itemuoms = [];
            $entry['ITEMUOM'] = $uomInfoVals[$itemid];
        }

        return true;
    }

    /**
     * @param array $values
     * @param int $index
     * @param array $priceConversionPrefs
     *
     * @return bool
     */
    protected function prepareConversionType(&$values, $index, $priceConversionPrefs)
    {
        $entry = &$values['ENTRIES'][$index] ?? [];
        if (!empty($entry['CONVERSIONTYPE'] ?? '')) {
            return true;
        }

        // When price conversion doesn't enable, conversion type should always quantity by default
        if (!$priceConversionPrefs['ENABLE_PRICECONVERSION']) {
            $entry['CONVERSIONTYPE'] = 'Quantity';
            return true;
        }

        $itemid = explode('--', ($entry['ITEMID'] ?? ''))[0] ?? '';
        $item = $this->itemRawCache[$itemid] ?? [];

        // If the conversion type value is empty, we should retrieve it from the Item Object or from source document line item if any.
        if (empty($entry['SOURCE_DOCLINEKEY'] ?? '')) {
            $itemConversionType = (!empty($entry['ITEMID'])
                && !empty($item['DEFAULTCONVERSIONTYPE'] ?? '')) ? $item['DEFAULTCONVERSIONTYPE'] : 'Q';
            $entry['CONVERSIONTYPE'] = (($itemConversionType == 'P') ? 'Price' : 'Quantity');
        } else {
            $entry['CONVERSIONTYPE'] = $entry['SOURCE_CONVERSIONTYPE'];
        }

        return true;
    }

    /**
     * method to validate the line entries
     *
     * @param  array &$values values of the transaction
     *
     * @return bool denotes if the method execution had any error or not.
     */
    function validateLineEntries(&$values)
    {
        global $gErr;

        $ok = true;
        $entries = array();
        $lineLevelSimpleTax = $values['_DOCPAR']['LINELEVELSIMPLETAX'];
        $validSimpleTaxes = array();
        if ($lineLevelSimpleTax == 'true') {
            foreach ($values['_DOCPAR']['DOCPAR_SUBTOTAL'] as $docparSubTotals) {
                if ($docparSubTotals['ISTAX'] == 'true' && $docparSubTotals['ISAVATAX'] != 'true') {
                    $validSimpleTaxes[] = $docparSubTotals['DESCRIPTION'];
                    if ($this->defaultLineLevelSimpleTaxType == "") {
                        $this->defaultLineLevelSimpleTaxType = $docparSubTotals['DESCRIPTION'];
                    }
                }
            }
        }

        $isDraft = $this->isDraftDocument($values);
        $isPaymtTaxCapture = $this->isVATEnabled($values) && $this->isPaymentTaxCaptureSupported()
                             && PaymentUtils::isOEPOPaymentTaxCaptureSupported($values);
        $isPartialExempt = $this->isTxnEligibleForVatPartialExempt($values);

        $hasTaxableSubtotal = $this->hasTaxableSubtotal($values['_DOCPAR']['DOCPAR_SUBTOTAL']);
        foreach ((($values['ENTRIES']) ?? []) as $key => $entry) {
            if ($isDraft) {
                // Draft document is required atleast one line item with LOCATION and UIQTY value to add in document
                $this->prepDraftEntry($values['ENTRIES'][$key]);
            }

            if (isset($entry['ITEMID']) && $entry['ITEMID'] != '') {
                [$itemid, $itemname] = explode('--', $entry['ITEMID']);
                $values['ENTRIES'][$key]['ITEMID'] = $itemid;
                $values['ENTRIES'][$key]['ITEMNAME'] = $itemname;
                $entries[] = $values['ENTRIES'][$key];
            }else if($isDraft && is_numeric(trim($entry['UIQTY']))){
                    $entries[] = $values['ENTRIES'][$key];
            }

            if ($lineLevelSimpleTax == 'true' && !empty($entry['LINELEVELSIMPLETAXTYPE']) && !in_array($entry['LINELEVELSIMPLETAXTYPE'], $validSimpleTaxes)) {
                $msg = sprintf('The Line level simple tax type \'%1$s\' is not valid', $entry['LINELEVELSIMPLETAXTYPE']);
                Globals::$g->gErr->addIAError(
                    'INV-1327', __FILE__ . ':' . __LINE__,
                    'Please correct the line level simple tax type', [],
                    $msg, ['ENTRY_LINELEVELSIMPLETAXTYPE' => $entry['LINELEVELSIMPLETAXTYPE']]
                );
                return false;
            }

            //Do not allow to set payment tax capture flag for other than Fr VAT
            if ( ! ( $isPaymtTaxCapture && $hasTaxableSubtotal )
                 && isset($entry['PAYMENTTAXCAPTURE'])
                 && ( $entry['PAYMENTTAXCAPTURE'] == 'true' || $entry['PAYMENTTAXCAPTURE'] == 'T' ) ) {
                Globals::$g->gErr->addError('TAX-0269', GetFL(),
                                            _("Please correct the line level payment tax capture."));

                return false;
            }

            //KITs not allowed with payment tax capture
            if ( $isPaymtTaxCapture && ! isNullOrBlank($entry['ITEMTYPE']) && $entry['ITEMTYPE'] === 'K' ) {
                Globals::$g->gErr->addError('TAX-0277', GetFL(),
                                            _("Please correct the line level payment tax capture."));

                return false;
            }

            if ( $isPaymtTaxCapture && $isPartialExempt && isset($entry['PARTIALEXEMPT'])
                 && isset($entry['PAYMENTTAXCAPTURE'])
                 && $entry['PARTIALEXEMPT'] === 'true'
                 && $entry['PAYMENTTAXCAPTURE'] === 'true' ) {
                Globals::$g->gErr->addError('TAX-0269', GetFL(),
                                            _("Please correct the line level payment tax capture."));

                return false;
            }
      }

        // do not allow the user to save the document with out line entries
        if ( !empty($entries) ) {
            $values['ENTRIES']  =   $entries;
        } else {
            $msg = "Document must contain atleast one line entry!";
            $gErr->addIAError('INV-1280', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }

        return $ok;
    }

    /***
     * @param array $entry
     */
    protected function prepDraftEntry(&$entry){
        //$entry['UIQTY'] = ($entry['UIQTY'] == '') ? 0 : $entry['UIQTY'];
        // This header state field value is required in entry to validate required/mandatory fields in entryManager
        // This DOCSTATE value is using in DocumentEntryManager::isFieldRequired to skip/Relax the validation for draft document
        $entry['DOCSTATE'] = self::DRAFT_STATE;
    }

    /**
     * @param array $docparSubtotals
     *
     * @return bool
     */
    protected function hasTaxableSubtotal($docparSubtotals)
    {
        if ( ! empty($docparSubtotals) ) {
            foreach ( $docparSubtotals as $subtotal ) {
                if ( $subtotal['ISTAX'] == 'true' ) {
                    return true;
                }
            }
        }

        return false;
    }


    /**
     * @param array $values
     * @param array $entry
     * @param array $priceConversionPrefs
     * @param bool $newdoc
     * @return bool
     */
    protected function validatePriceConversion($values, $entry, $priceConversionPrefs, $newdoc)
    {
        $ok = true;

        if (($entry['CONVERSIONTYPE'] ?? '') != 'Price') {
            return true;
        }

        global $gErr;
        $lineno = $entry['LINE_NO'] + 1;
        $item = $this->itemRawCache[$entry['ITEMID']] ?? [];

        if (Util::countOrZero($item) > 0) {
            if (($item['DROPSHIP'] ?? 'F') == 'T') {
                $msg = 'Drop-ship items use quantity conversion types, not price conversion types.';
                $gErr->addIAError('INV-1351', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, []);
                $ok = false;
            }

            if (($item['ENABLELANDEDCOST'] ?? 'F') == 'T') {
                $msg = 'Landed Cost items use quantity conversion types, not price conversion types.';
                $gErr->addIAError('INV-1352', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, []);
                $ok = false;
            }
        }

        // This logic to check base unit conversion factor is required for price conversion type
        $unitConvfactor = '';
        if (Util::countOrZero($entry['ITEMUOM']) > 0) {
            foreach ($entry['ITEMUOM'] as $row) {
                if ($row['UNIT'] == $entry['UNIT']) {
                    $unitConvfactor = $row['CONVFACTOR'];
                    break;
                }
            }
        }

        if (!$this->isDraftDocument($values)
            && (empty($entry['UNIT'] ?? '') || Util::countOrZero($entry['ITEMUOM']) == 0)) {
            $msg = "Please select a valid Unit in line no : $lineno";
            $gErr->addIAError('INV-1359', __FILE__ . ':' . __LINE__, 'Missing Unit', [], $msg, ['LINENO' => $lineno]);
            $ok = false;
        }

        if ($unitConvfactor != 1) {
            $msg = sprintf('Line %1$s has a unit conversion with Price conversion type.', $lineno);
            $correction = 'For lines with a unit conversion and price conversion type, enter a base unit (such as, "each" or "seconds").';
            $gErr->addIAError(
                'INV-1301', __FILE__ . ':' . __LINE__,
                $msg, ['LINENO' => $lineno],
                '', [],
                $correction, []
            );
            $ok = false;
        }

        if (!isNullOrBlank($entry['DISCOUNTPERCENT'])
            && $entry['DISCOUNTPERCENT'] != 0) {
            $msg = sprintf('Lines with discounts can only use a conversion type of Quantity. Select Quantity for line %1$s.', $lineno);
            $gErr->addIAError('INV-1302', __FILE__ . ':' . __LINE__, $msg, ['LINENO' => $lineno]);
            $ok = false;
        }

        if (!isNullOrBlank($entry['BUYTOORDER'])
            && $entry['BUYTOORDER'] == 'true') {
            $msg = sprintf('\"Buy to order\" lines can only use a conversion type of Quantity. Select Quantity for line %1$s.', $lineno);
            $gErr->addIAError('INV-1303', __FILE__ . ':' . __LINE__, $msg, ['LINENO' => $lineno]);
            $ok = false;
        }

        if ($values['_DOCPAR']['ENABLERENEWALS'] === 'Generate'
            || $values['_DOCPAR']['ENABLERENEWALS'] === 'Display Only') {
            $msg = sprintf('Transaction definitions with renewals enabled can only use a conversion type of Quantity. Select Quantity for line %1$s.', $lineno);
            $gErr->addIAError('INV-1305', __FILE__ . ':' . __LINE__, $msg, ['LINENO' => $lineno]);
            $ok = false;
        }

        if ($priceConversionPrefs['ENABLE_PRICECONVERSION']) {
            if ($this->isValidPriceValue($values, $entry)) {
                $msg = 'Price was specified as the conversion type, and Quantity is not 1.';
                $corrmsg = 'If you select a price conversion type, you must specify Quantity as 1.';
                $gErr->addIAError('INV-1284', __FILE__ . ':' . __LINE__, $msg, [], "", [], $corrmsg, []);
                $ok = false;
            }

            $nonInventoryItems = $this->GetNonInventoryItems();
            if (!isNullOrBlank($entry['ITEMTYPE']) && !in_array($entry['ITEMTYPE'], $nonInventoryItems)) {
                $msg = sprintf('Price was specified as the conversion type for %1$s', $entry['ITEMDESC']);
                $corrmsg = 'Inventory items use quantity conversion types, not price conversion types.';
                $gErr->addIAError(
                    'INV-1285', __FILE__ . ':' . __LINE__,
                    $msg, ['ENTRY_ITEMDESC' => $entry['ITEMDESC']],
                    "", [],
                    $corrmsg, []
                );
                $ok = false;
            }

            if (!isNullOrBlank($entry['COST_METHOD']) && $entry['COST_METHOD'] != 'S') {
                $msg = sprintf('Price was specified as the conversion type for %1$s.', $entry['ITEMDESC']);
                $corrmsg = 'Items that use the standard cost method use quantity conversion types, not price conversion types.';
                $gErr->addIAError(
                    'INV-1286', __FILE__ . ':' . __LINE__,
                    $msg, ['ENTRY_ITEMDESC' => $entry['ITEMDESC']],
                    "", [],
                    $corrmsg, []
                );
                $ok = false;
            }

            if (!isNullOrBlank($entry['ALLOCATION'])) {
                $msg = sprintf('Price was specified as the conversion type for %1$s', $entry['ITEMDESC']);
                $corrmsg = 'Transactions that use allocations use quantity conversion types, not price conversion types.';
                $gErr->addIAError(
                    'INV-1287', __FILE__ . ':' . __LINE__,
                    $msg, ['ENTRY_ITEMDESC' => $entry['ITEMDESC']],
                    "", [],
                    $corrmsg, []
                );
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * method to prepare the transaction values that will be used in the Add/Set methods.
     * Gets new record# in case its a new document, Validates EntityInfo, Dates,  Prepares Entity Values,
     * Validates MCP Fields and calls the PrepLineItems method.
     *
     * @param array             &$values   values of the transaction
     * @param TrackingHandler[] $handlers  only used as $handlers['TRACKING_HANDLER'] as of now, generalize when u need it
     * @param bool              $newdoc    to denote if its a new document
     * @param array             $getTaxRequest
     * @param string            $entityTaxable
     *
     * @return bool denotes if the method execution had any error or not.
     */
    function PrepValues(&$values, $handlers, $newdoc = true, &$getTaxRequest = null, &$entityTaxable = null)
    {
        $source = "DocumentManager::PrepValues()";

        global $gErr, $gManagerFactory;
        $gNonStandardPeriods = &Globals::$g->gNonStandardPeriods;

        //$mod            =   $this->mod;
        // Ideally the mod value should be set from the editor level. Here we try to set the value of mod in the values array if it does not have a value.
        // This is to avoid the gRequest calls in helper files or core logic files.
        if (!$values['_mod'] && isset($this->mod)) {
            $values['_mod'] = $this->mod;
        }

        $docparMgr = $this->get_docpar_manager();
        $shipmethodMgr =    $gManagerFactory->getManager('shipmethod');
        $docpar = [];

        $ok = $this->_QM->beginTrx($source);

        if ($gNonStandardPeriods && !VerifyDateRange($values['WHENCREATED'])) {
            $ok = false;
        }

        $values['SALESCONTRACT'] = 'N';

        // Note is currently used only to represent backorders,
        // But converting a backorder carries over the value of NOTE, unset it for now.
        if (($values['BACKORDER'] ?? '') != 'Yes') {
            $values['NOTE'] = '';
        }

        if (!$values['DOCPARID']) {
            $msg = "There is no transaction definition associated with this document";
            $gErr->addIAError('INV-1281', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }

        if ($ok) {
            if (!isset($values['_DOCPAR']) || $values['_DOCPAR'] == '') {
                $docpar = $docparMgr->GetLatest($values['DOCPARID'], false);
                if (empty($docpar)) {
                    $msg = sprintf("Invalid transaction definition %s given with this document", $values['DOCPARID']);
                    $gErr->addIAError('INV-1282', __FILE__ . ':' . __LINE__, $msg, ['VALUES_DOCPARID' => $values['DOCPARID']]);
                    $ok = false;
                }
                $values['DOCPARKEY'] = $docpar['RECORDNO'];
                $values['_DOCPAR'] = $docpar;
            } else {
                $docpar = $values['_DOCPAR'];
                $values['DOCPARKEY'] = $values['_DOCPAR']['RECORDNO'];

                $this->assignDocParTotals($values['_DOCPAR'], $values['DOCPARKEY']);
            }


            $ok = $ok && $this->validateMCPFields($values);

            $iscustomer = ($docpar['CUST_VEND'] == 'Customer');

            $docparspi = $docparMgr->_TransformExternalValue('SALE_PUR_TRANS', $docpar['SALE_PUR_TRANS']);
            $values['SPI'] = $docparspi;

            $allowedDocs = $docparMgr->getRecallDocs($values['_DOCPAR']['DOCID']);
            $values[self::ALLOWED_DOCS_COUNT] = Util::countOrZero($allowedDocs);
            $ok = $ok && $this->PrepDocumentSequenceNo($values,$newdoc);
        }

        if ($this->fromGateway == false && (!isset($values['FROMAPI_2.1']) && $values['FROMAPI_2.1'] == false)) {
            $this->unsetCCOFields($values);
        }

        // Very important that this is after the $docparMgr->GetLatest(), because code in validateLineEntries rely on DOCPAR value
        $ok = $ok && $this->validateLineEntries($values);

        if ($values['_DOCPAR']['UPDATES_GL'] == 'A'
            || $values['_DOCPAR']['DOCID'] == InvDocumentManager::LANDEDCOSTDOCTYPE
            || $values['_DOCPAR']['DOCID'] == InvDocumentManager::LANDEDCOSTESTDOCTYPE
            || $values['_DOCPAR']['DOCID'] == InvDocumentManager::LANDEDCOSTESTREVDOCTYPE) {
            if((!isset($values['WHENPOSTED']) || $values['WHENPOSTED'] == '')){
                $values['WHENPOSTED'] = $values['WHENCREATED'];
            }
        }
        else{
            $values['WHENPOSTED'] = '';
        }

        // ************************** verify and/or create DOCID (docno)
        if ($ok && (empty($values['DOCNO']))) {
            $msg = "The Document Number field is missing a value.";
            $corr = sprintf("Enter a value. To have the system automatically generate a document number, edit the transaction definition for '%s' and select a numbering sequence.",
                $values['DOCPARID']);
            $gErr->addIAError('INV-1283', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr, ['VALUES_DOCPARID' => $values['DOCPARID']]);
            $ok = false;
        }

        if (!$this->isDraftDocument($values)
            && $this->_IsCustVendRequired && !$this->ValidEntityID($values['CUSTVENDID'])) {
            $gErr->addIAError(
                'INV-1328', __FILE__ . ':' . __LINE__,
                sprintf('The customer-vendor id %s is invalid.', $values['CUSTVENDID']), ['VALUES_CUSTVENDID' => $values['CUSTVENDID']]
            );
            $ok = false;
        }

        if ($ok && $values['TERM']['NAME']) {
            /** @noinspection PhpUndefinedVariableInspection */
            $termMgr =    $gManagerFactory->getManager(($iscustomer ? 'ar' : 'ap') . 'term');
            //$term       =   $termMgr->GetRaw($values['TERM']['NAME']);
            $fields = array('RECORD#');
            $term = $termMgr->GetList(
                array('selects' => $fields,
                    'filters' => array(array(
                        array('NAME', '=', $values['TERM']['NAME'])))
                )
            );
            $ok = $ok && isset($term[0]);
            if (!$ok) {
                $gErr->addIAError('INV-0019', __FILE__ . ':' . __LINE__, "The Term Name is invalid.", []);
            }

            GetStaticTermRecNo($term[0]['RECORD#'], $termKey);
            $values['TERMKEY'] = $termKey;
        }
        
        $ok = $ok && $this->PrepareEntityValues($values, $docpar);

        if ($ok && $values['SHIPVIA']) {
            $method = $shipmethodMgr->GetRaw($values['SHIPVIA']);
            $ok = $ok && isset($method[0]);
            if (!$ok) {
                $gErr->addIAError(
                    'INV-1329', __FILE__ . ':' . __LINE__,
                    sprintf("The shipping method '%s' is invalid.", $values['SHIPVIA']), ['VALUES_SHIPVIA' => $values['SHIPVIA']]
                );
            } else {
                $values['SHIPVIAKEY'] = $method[0]['RECORD#'];
            }
        }

        $benchmark = Globals::$g->gIABenchmark;
        //$values['USER'] =   array_shift(explode('@', $_userid));
        $values['USER'] = GetMyUserid();

		if ($ok && ($values['CREATEDFROM'] ?? false)) {
            if(!$this->checkIsCreatedFromMultipleSourceDocuments($values, $sourceDockeys)) {
                // ticket 65893 : ignore employee user access restriction on parentDoc as its used to find currency only
                $parentDoc = array();
                $parentDoc['selects'] = array('RECORDNO', 'CURRENCY');
                $parentDoc['usemst'] = true;
                $parentDoc['ignoreMypurchases'] = true;
                $parentDoc['filters'] = array(array(array('DOCID', '=', $values['CREATEDFROM'])));
                $parentDocRes = $this->GetList($parentDoc);
                $ok = $ok && isset($parentDocRes[0]);
                $values[':createdfrom'] = $parentDocRes[0]['RECORDNO'];
                //commenting below after discussing with multiple PMs.. They want to come back to this later
                /*if ($values['CURRENCY'] != $parentDocRes[0]['CURRENCY']) {
                    $gErr->addIAError(
                        'INV-1330', __FILE__ . ":" . __LINE__,
                        "Transaction Currency should be same as parent transaction Currency", []
                    );
                    $ok = false;
                }*/
            }
            // We should not be carrying the schopkey value from the source document.
            unset($values['SCHOPKEY']);
        } else {
            unset($values['HISTORY']);
            if ( InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_EITHER, $values) ) {
                DocumentManagerFulfillmentHelper::sanitizeCopy($values);
            }
        }

        // Append dimension field information to the docvalues structure that will be used by the subtotals logic.
        $values['DIMENSIONFIELDS'] = $this->GetDimensionFields();
        $values['PRIMARYDIMENSION'] = $this->getPrimaryDimensions();

        //We need to prep values for VAT fields. This prep needs to be done before PrepLineItems as it depends on the values
        // this call will set. But we only need to call it for new documents as older ones will have this set already
        $ok = $ok && $this->PrepValuesForTaxSolution($values);

        $benchmark->startTimer('PrepLineItems', $this, $this);
        // setting up of line numbers here is very much required for functionalities like PO allocations
        $this->setLineNumbers($values);
        $ok = $ok && $this->PrepLineItems($values, $handlers, $newdoc);
        $benchmark->stopTimer();

        $ok = $ok && $this->validateLineEntriesPostPrepLineItems($values);

        // this validation must be done after preplineitems since PO allocations split entries and sets locations
        $ok = $ok && $this->checkForValidTaxLocations($values);

        $nonInventoryItems = $this->GetNonInventoryItems();
        if ($this->getIsRetainageEnabled()) {
            $retainageIsWithheldForInventoryItem = false;
            foreach ($values['ENTRIES'] as $entry) {
                if ((isset($entry['TRX_AMOUNTRETAINED']) && is_numeric($entry['TRX_AMOUNTRETAINED']) && +$entry['TRX_AMOUNTRETAINED'] != 0) ||
                    (isset($entry['RETAINAGEPERCENTAGE']) && is_numeric($entry['RETAINAGEPERCENTAGE']) && +$entry['RETAINAGEPERCENTAGE'] != 0) ||
                    (isset($entry['AMOUNTRETAINED']) && is_numeric($entry['AMOUNTRETAINED']) && +$entry['AMOUNTRETAINED'] != 0)
                ) {
                    if (!isNullOrBlank($entry['ITEMTYPE']) && !in_array($entry['ITEMTYPE'], $nonInventoryItems)) {
                        $retainageIsWithheldForInventoryItem = true;
                        break;
                    }
                }
            }

            if ($retainageIsWithheldForInventoryItem &&
                $values['_DOCPAR']['UPDATES_GL'] == 'A' &&
                'Invoice' === $values['_DOCPAR']['DOCCLASS'] && IsInstalled(Globals::$g->kINVid)
            ) {
                $found = false;
                if (is_array($values['_DOCPAR']['DOCPAR_TOTALS'])) {
                    foreach ($values['_DOCPAR']['DOCPAR_TOTALS'] as $total) {
                        if (!isNullOrBlank($total['TOTALID']) &&
                            $total['TOTALID'] === 'ONHAND' &&
                            ($total['Q_QV'] === 'Value' || $total['Q_QV'] === 'Quantity & Value')) {
                            $found = true;
                            break;
                        }
                    }
                }

                if (!$found) {
                    $gErr->addIAError(
                        'INV-0020', __FILE__ . ':' . __LINE__,
                        "To use retainage with inventory items requires at least one 'ONHAND' total affecting 'Value' or 'Quantity and Value' on the transaction definition.", []
                    );
                    $ok = false;
                }
            }
        }
        $retainageBillingLines = 0;

        $priceConversionPrefs = [
            'ENABLE_PRICECONVERSION' => $this->isPriceConversionEnabled(),
            'ENABLE_OVERRIDE_TRANSACTION_CONVERSIONTYPE' => $this->isOverrideTrnxConversionTypeEnabled()
        ];
        foreach ($values['ENTRIES'] as &$entry) {

            //get the total count of retainage billing lines
            if(CRESetupManager::isRetainageBillingEnabled() &&  $this->mod == 'so'){
                if($entry['ISRETAINAGERELEASE'] == "true"){
                    $retainageBillingLines++;
                }else{
                    $retainageBillingLines--;
                }
            }

            // If the primary doc feature is enabled then pre-fill in the primary doc keys
            if ( CRESetupManager::isPrimaryDocEnabled()) {

                if ( !isset($entry['RECORDNO']) && isset($docpar['PRIMARYDOC']) && $docpar['PRIMARYDOC'] == "true" && (!isset($values['BACKORDER']) || $values['BACKORDER'] != 'Yes')) {

                    $entry['DOCHDRNO'] = $entry['PRIMARYDOCKEY'] = $values['RECORDNO'];
                    $docEntryMgr = $gManagerFactory->getManager($this->mod . 'documententry', false,
                                                                [ 'DOCTYPE' => $this->_docType ]);
                    $nextId = $docEntryMgr->GetNextRecordKey();

                    if ( ! isset($nextId) ) {
                        return false;
                    }
                    $entry[':record#'] = $entry['PRIMARYDOCLINEKEY'] = $nextId;
                }
            }

            //Validate that Price conversion is not used for inventory items.
            $ok = $ok && $this->validatePriceConversion($values, $entry, $priceConversionPrefs, $newdoc);
            if($ok && !empty($entry['CONVERSIONTYPE'] ?? '')
                && $entry['CONVERSIONTYPE'] === 'Price'
                && $priceConversionPrefs['ENABLE_PRICECONVERSION']){
                //Price Conversion entries always are rounded to 2 digits past the decimal place.
                $entry['PRICE'] = iround($entry['PRICE'], 2);
                $entry['TRX_PRICE'] = iround($entry['TRX_PRICE'], 2);
                $entry['UIPRICE'] = iround($entry['UIPRICE'], 2);
            }
        }

        //Copy overriden tax details for VAT
        $ok && $this->copyOverridenTaxValues($values, $newdoc);

        //Reset Overriden TaxValues for back orders
        $ok && $this->isVATEnabled($values) && $newdoc && $values['BACKORDER'] === 'Yes' && $this->resetOverridenTaxValues($values);

        $benchmark->startTimer('PrepareSubTotalsValues', $this, $this);
        $ok = $ok && $this->PrepareSubTotalsValues($values, $getTaxRequest, $entityTaxable);
        if($ok && !$newdoc){
            $ok = $ok && $this->getDocSubTotalsManager(false)->mapSubtotalsRecordNo($values);
        }
        $benchmark->stopTimer();

        // validate the state of document
        $ok = $ok && $this->validateDocumentState($values);

        /*If invoiced by project contract and TRX_TOTAL value is zero and coming from generate invoices, then calculate and update the TRX_TOTAL value*/
        $fromGenerateInvoices = false;

        if (empty($values['TRX_TOTAL'])) {
            if (!empty($values["fromGenerateInvoices"]) && $values["fromGenerateInvoices"] == 'true' && $values["INVOICEBY"] == 'Project contract') {
                $fromGenerateInvoices = true;
            } elseif (!$newdoc && !empty($values["INVOICERUNKEY"])) {
                $fromGenerateInvoices = true;
            }
        }

        /*check if all the lines are billed for retainage and TRX_TOTAL is empty, then calculate and update the TRX_TOTAL value*/
        $retainageBilling = (count($values['ENTRIES']?? []) == $retainageBillingLines) && empty($values['TRX_TOTAL']);

        if (!isset($values['SUBTOTALS']) || $fromGenerateInvoices || $retainageBilling) {
            // for document Subtotal & Total
            $this->CollectTotalValuesFromEntries($values);
        }

        // we need to validate customer credit limit after the subtotal calculation only
        $ok = $ok && $this->validateCustomerCreditLimit($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if (HasErrors()) { //adding the error message only if has error
                $msg = "Error preparing values!";
                $gErr->addIAError('INV-1288', __FILE__ . ':' . __LINE__, $msg, []);
            }
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param array $values
     * @return bool
     */
    protected function prepSourceLinesInfo(&$entries)
    {
        if (Util::countOrZero($entries) == 0) {
            return true;
        }

        $sourceLines = [];
        foreach ($entries as $entry) {
            if (!empty($entry['SOURCE_DOCLINEKEY'] ?? '')) {
                $sourceLines[] = $entry['SOURCE_DOCLINEKEY'];
            }
        }

        if (Util::countOrZero($sourceLines) == 0) {
            return true;
        }

        $docEntryMgr = Globals::$g->gManagerFactory->getManager($this->mod . 'documententry');
        $filters = [
            'selects' => ['RECORDNO', 'CONVERSIONTYPE'],
            'filters' => [[['RECORDNO', 'IN', $sourceLines]]],
        ];
        $sourceDocEntries = $docEntryMgr->GetList($filters);

        if (Util::countOrZero($sourceDocEntries ?? []) > 0) {
            $sourceEntries = [];
            foreach ($sourceDocEntries as $srcEntry) {
                $sourceEntries[$srcEntry['RECORDNO']] = $srcEntry;
            }

            if (Util::countOrZero($sourceEntries) > 0) {
                foreach ($entries as &$newEntry) {
                    if (!empty($newEntry['SOURCE_DOCLINEKEY'] ?? '')) {
                        $srcEntry = $sourceEntries[$newEntry['SOURCE_DOCLINEKEY']] ?? [];
                        if (!empty($srcEntry['CONVERSIONTYPE'] ?? '')) {
                            // prepare SOURCE_CONVERSIONTYPE for the source CONVERSIONTYPE entry
                            $newEntry['SOURCE_CONVERSIONTYPE'] = $srcEntry['CONVERSIONTYPE'];
                        }
                    }
                }
            }
        }

        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function validateLineEntriesPostPrepLineItems(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return true;
    }

    /**
     * Returns the internal/external tax methods which have tax implications on PO/OE transactions.
     *
     * @return array
     */
    public function getTaxImplicationTaxMethods()
    {
        $taxMethods = [
            TaxSolutionManager::TAXMETHOD_LABEL_VAT,
            TaxSolutionManager::TAXMETHOD_LABEL_AVALARA,
            TaxSolutionManager::TAXMETHOD_LABEL_ADVANCED,
            TaxSolutionManager::TAXMETHOD_I_VAT,
            TaxSolutionManager::TAXMETHOD_I_AVALARA,
            TaxSolutionManager::TAXMETHOD_I_ADVANCED,
            TaxSolutionManager::TAXMETHOD_LABEL_SIMPLE,
            TaxSolutionManager::TAXMETHOD_I_SIMPLE
        ];
        return $taxMethods;
    }

    /**
     * Returns the internal tax methods which DON'T have tax implications on PO/OE transactions.
     *
     * @return array
     */
    public function getNonTaxImplicationTaxMethods()
    {
        return [TaxSolutionManager::TAXMETHOD_I_NONE];
    }

    /**
     * For PO/OE transactions TAXSOLUTIONID field is set to VAT, Avalara, Advanced tax, and no tax tax solutions
     *
     * @return array
     */

    public static function getTaxMethodsHelper()
    {
        $taxMethods = [ TaxSolutionManager::TAXMETHOD_LABEL_VAT,
                        TaxSolutionManager::TAXMETHOD_LABEL_AVALARA,
                        TaxSolutionManager::TAXMETHOD_LABEL_ADVANCED,
                        TaxSolutionManager::TAXMETHOD_LABEL_SIMPLE,
                        TaxSolutionManager::TAXMETHOD_LABEL_NONE
                      ];
        return $taxMethods;
    }

    /**
     * Prepare this transaction values with relation to VAT is enabled
     *
     * @param array $values the transaction data
     *
     * @return bool false if error else true
     */
    protected function PrepValuesForTaxSolution(&$values)
    {
        $ok = true;
        // we want to set the tax solution values for vat and nonVat tax solutions
        if (TaxSetupManager::isTaxModuleConfigured()) {
            if (!self::hasTaxSubTotals($values['_DOCPAR'])) {
                //If the TD being used for this PO/OE doesn't have at least one ISTAX line, we will ignore the
                //taxsolution when saving. This case should not happen in UI but it can in API/CSV.
                $values['TAXSOLUTIONID'] = null;
            } else if ( TaxSetupManager::isSingleTaxJurisdictionConfigured() ) {
                //In singletax jusrisdiction or standard company, we should only have one tax solution set up, so use that
                $ok = TaxSolutionManager::getTaxInfoForSingleJurisdiction(
                    $this->getTaxImplicationTaxMethods(),$values);
            } else if (GetContextLocation()) {
                // at entity level, for new transactions use the tax solution from the entity
                $ok = TaxSolutionManager::getTaxInfoForCurEntityLevel(
                    $this->getTaxImplicationTaxMethods(),$values);
            } else {
                //We are at root level so tax solution id is entered by users
                $ok = TaxSolutionManager::getTaxInfoForRootLevel(
                    $this->getTaxImplicationTaxMethods(),$values);
            }

            // Validate the transaction taxsolution, locations and terms etc
            $ok = $ok && TaxSolutionManager::validateTaxSetup($values);

            //Validation for VAT companies, TDs cannot have more than one taxable subtotal for other than Simple tax
            $ok = $ok && $this->validateTDSubtotals($values);

        }

        return $ok;
    }

    /**
     * Validation for VAT companies, TDs cannot have more than one taxable subtotal for other than Simple tax
     * this method assumes you are calling it for taxes companies
     *
     * @param array $values the document object
     *
     * @return bool
     */
    protected function validateTDSubtotals($values)
    {
        // allow multiple isTax = true lines in subtotals only for simle tax and no tax solution transactions
        $taxSolutionID = $values['TAXSOLUTIONID'] ?? '';
        $taxMethod = GetTaxEngine($this->mod, $taxSolutionID);
        if ( !empty($taxMethod)
             && !in_array($taxMethod,
                          [TaxSolutionManager::TAXMETHOD_I_SIMPLE, TaxSolutionManager::TAXMETHOD_I_NONE]) )
        {
            $isTaxCount = 0;
            $isSimpleTaxfallback = ($taxMethod == TaxSolutionManager::TAXMETHOD_I_AVALARA) ? true : false;

            // if you are using avatax then we do not support line level simple tax fallback
            if ( $isSimpleTaxfallback && $values['_DOCPAR']['LINELEVELSIMPLETAX'] == 'true') {
                $msg = "Document cannot use 'Line Level Simple tax' if tax method is {$taxMethod}";
                Globals::$g->gErr->addIAError('INV-1289', __FILE__ . ':' . __LINE__, $msg, ['TAX_METHOD' => $taxMethod]);
                return false;
            }

            // loop to find how many tax lines are present in the subtotals of the TD
            foreach ($values['_DOCPAR']['DOCPAR_SUBTOTAL'] as $docparSubTotals) {
                if ($docparSubTotals['ISTAX'] == 'true') {
                    $isTaxCount++;
                }
                if ($taxMethod == TaxSolutionManager::TAXMETHOD_I_AVALARA && $docparSubTotals['ISAVATAX'] == 'true') {
                    $isSimpleTaxfallback = false;
                }
            }

            // if tax engine is advanced tax or vat or avalara (but not simple tax fallback), then we allow only 1 tax line
            if ( ! $isSimpleTaxfallback && $isTaxCount > 1) {
                $msg = "Document cannot have more than one taxable subtotal if tax method is {$taxMethod}";
                Globals::$g->gErr->addIAError('INV-1290', __FILE__ . ':' . __LINE__, $msg, ['TAX_METHOD' => $taxMethod]);
                return false;
            }
        }

        return true;
    }

    /**
     * for multitple tax companies when creating transactions at root level,
     * check all the locations match the tax solution provided by the user
     *
     * @param array $values
     *
     * @return bool
     */
    protected function checkForValidTaxLocations(array $values) : bool
    {

        // check location and tax solution match for root level multitax jurisdiction transactions with tax
        $validateEntryLocation = (!empty($values['ENTRIES'])
                                  && TaxSetupManager::isMultiTaxJurisdictionConfigured()
                                  && IsRoot()
                                  && self::hasTaxSubTotals($values['_DOCPAR']));

        if ( $validateEntryLocation ) {
            // before we check if locations match the tax solution provided by the user, we should validate the tax solution provided
            if ( $values['TAXSOLUTIONID'] ?? false ) {
                $isValidTaxSolution = TaxSolutionManager::isTaxSolutionIdConfigured($values['TAXSOLUTIONID']);
                if ( ! $isValidTaxSolution ) {
                    $msg = sprintf('Invalid tax solution %1$s provided', $values['TAXSOLUTIONID']);
                    $corrmsg = "Specify a tax solution that is installed and configured";
                    Globals::$g->gErr->addIAError(
                        'INV-1291', GetFL(),
                        $msg, ['VALUES_TAXSOLUTIONID' => $values['TAXSOLUTIONID']],
                        "", [],
                        $corrmsg, []
                    );
                    return false;
                }
            }

            //Get the entities and its locations for the current tax solution provided.
            $locationIds = ($values['TAXSOLUTIONID'] ?? false) ?
                TaxSolutionManager::getLocnIdsFromTaxSolnIds([$values['TAXSOLUTIONID']]) :
                TaxSolutionManager::getLocnIdsFromTaxMethods($this->getNonTaxImplicationTaxMethods());

            foreach ( $values['ENTRIES'] as $entry ) {
                $location = explode('--', $entry['LOCATION'])[0];
                $splits = $entry['SPLIT'];
                $lineNo = $entry['LINENO'] + 1;
                // TODO looping thru entries when using allocations is inefficient since entries are expanded and splits repeated
                if (!empty($splits)) {
                    // deal with allocation splits first for better error handling ( only possible in PO )
                    foreach ( $splits as $spEntry ) {
                        $spLocation = explode('--', $spEntry['LOCATIONID'])[0];
                        if ( $spLocation ) {
                            // check to make sure all locations of the entry's split are part of the tax solution
                            if ( ! in_array($spLocation, $locationIds) ) {
                                if($values['TAXSOLUTIONID'] ?? false) {
                                    $msg = "Location {$spEntry['LOCATIONID']} used in allocation {$entry['ALLOCATION']} in line $lineNo does not use tax solution {$values['TAXSOLUTIONID']}.";
                                    $corrmsg = "Specify a location that belongs to an entity that uses tax solution {$values['TAXSOLUTIONID']}.";
                                    Globals::$g->gErr->addIAError(
                                        'INV-1398', GetFL(),
                                        $msg, ['SP_ENTRY_LOCATIONID' => $spEntry['LOCATIONID'], 'ENTRY_ALLOCATION' => $entry['ALLOCATION'], 'LINE_NO' => $lineNo, 'VALUES_TAXSOLUTIONID' => $values['TAXSOLUTIONID']],
                                        "", [],
                                        $corrmsg, ['VALUES_TAXSOLUTIONID' => $values['TAXSOLUTIONID']]
                                    );
                                }else{
                                    $msg = "Location {$spEntry['LOCATIONID']} used in allocation {$entry['ALLOCATION']} in line $lineNo does not use a non taxable tax solution.";
                                    $corrmsg = "Specify a location that belongs to an entity that uses a non taxable tax solution.";
                                    Globals::$g->gErr->addIAError(
                                        'INV-1399', GetFL(),
                                        $msg, ['SP_ENTRY_LOCATIONID' => $spEntry['LOCATIONID'], 'ENTRY_ALLOCATION' => $entry['ALLOCATION'], 'LINE_NO' => $lineNo],
                                        "", [],
                                        $corrmsg, []
                                    );
                                }
                                return false;
                            }
                        }
                    } // end check for allocations splits
                } else if ( $location ) {
                    // for non-allocations, check to make sure this entry's line location is part of the tax solution
                    if ( ! in_array($location, $locationIds) ) {
                        if(($values['TAXSOLUTIONID'] ?? false)) {
                            $msg = "Location {$entry['LOCATION']} for line $lineNo does not use tax solution {$values['TAXSOLUTIONID']}.";
                            $corrmsg = "Specify a location that belongs to an entity that uses tax solution {$values['TAXSOLUTIONID']}.";
                            Globals::$g->gErr->addIAError(
                                'INV-1400', GetFL(),
                                $msg, ['ENTRY_LOCATION' => $entry['LOCATION'], 'LINE_NO' => $lineNo, 'VALUES_TAXSOLUTIONID' => $values['TAXSOLUTIONID']],
                                "", [],
                                $corrmsg, ['VALUES_TAXSOLUTIONID' => $values['TAXSOLUTIONID']]
                            );
                        }else{
                            $msg = "Location {$entry['LOCATION']} for line $lineNo does not use a non taxable tax solution.";
                            $corrmsg = "Specify a location that belongs to an entity that uses a non taxable tax solution.";
                            Globals::$g->gErr->addIAError(
                                'INV-1401', GetFL(),
                                $msg, ['ENTRY_LOCATION' => $entry['LOCATION'], 'LINE_NO' => $lineNo],
                                "", [],
                                $corrmsg, []
                            );
                        }
                        return false;
                    }
                } // end check for non allocations entries

            } // end loop over the entries

        } // end check

        return true;
    }

    /**
     * Assign the DOCPAR_SUBTOTAL and DOCPAR_TOTALS arrays in $docpar for the given $docparkey
     *
     * @param array $docpar   the array where the totals will be appended to
     * @param int $docparkey  the record# of the docpar
     */
    private function assignDocParTotals(&$docpar, $docparkey)
    {
        // The docpar total information would be populated in previous docpar caching. We should try get only if there is no total info.
        if (!isset($docpar['DOCPAR_SUBTOTAL'])) {
            $docparsubtotalsMgr = Globals::$g->gManagerFactory->getManager('documentparsubtotal');
            $docpar['DOCPAR_SUBTOTAL'] = $docparsubtotalsMgr->getByParent($docparkey);
        }
        if (!isset($docpar['DOCPAR_TOTALS'])) {
            $docpartotalsManager = Globals::$g->gManagerFactory->getManager('documentpartotals');
            $docpar['DOCPAR_TOTALS'] = $docpartotalsManager->getByParent($docparkey);
        }
    }

    /**
     * @param array $values
     */
    function CollectTotalValuesFromEntries(&$values)
    {
        $totalValue = '0';
        $trxTotalValue = '0';

        $entries = $values['ENTRIES'];
        // added is_array check to avoid exception for php 8.1
        $entriesCount = is_array($entries) ? count($entries) : 0 ;
        for ($i = 0; $i < $entriesCount; $i++) {
            $totalValue = ibcadd($totalValue, $entries[$i]['VALUE'] ?? '0', DEFAULT_INVPRECISION, true);
            $trxTotalValue = ibcadd($trxTotalValue, $entries[$i]['TRX_VALUE'] ?? '0', DEFAULT_INVPRECISION, true);
        }

        $values['SUBTOTAL'] = $totalValue;
        $values['TOTAL'] = $totalValue;

        $values['TRX_SUBTOTAL'] = $trxTotalValue;
        $values['TRX_TOTAL'] = $trxTotalValue;
    }

    /**
     *   This is required only in PO and SO,
     *   So, Overriden in PO and SO and supplied necessary logic
     *   In case of applications it should return true
     *
     * @param string $entity
     *
     * @return true
     */
    function ValidEntityID(/** @noinspection PhpUnusedParameterInspection */ $entity)
    {
        return true;
    }

    /**
     * Validate the dates of the document values array.
     *
     * @param  array $values values of the document.
     *
     * @return true|false $ok returns if the method execution was success or not.
     */
    function ValidateDates($values)
    {
        global $gErr;
        $ok = true;

        $dateText = 'Date Due';
        $custVend = 'vendor';
        if ($values['_DOCPAR']['SALE_PUR_TRANS'] == 'Sale') {
            $custVend = 'customer';
            if ($values['_DOCPAR']['DOCCLASS'] == 'Order') {
                $dateText = 'Ship Date';
            } else if ($values['_DOCPAR']['DOCCLASS'] == 'Quote') {
                $dateText = 'Expiration Date';
            }
        }

        if (!ValidateDate(isl_trim($values['WHENCREATED']))) {
            $gErr->addIAError(
                'INV-1331', __FILE__ . ':' . __LINE__,
                "The transaction date '" . $values['WHENCREATED'] . "' is invalid.", ['VALUES_WHENCREATED' => $values['WHENCREATED']]
            );
            $ok = false;
        }

        if (!$this->isDraftDocument($values)
            && empty($values['WHENDUE']) && $this->mod != 'inv') {
            $msg = "The $dateText field is missing a value.";
            $corr = "Enter a value. To have the system automatically determine a value for the $dateText field, ".
                "add terms to either the $custVend or to the transaction definition.";
            $gErr->addIAError(
                'INV-1292', __FILE__ . ':' . __LINE__,
                $msg, ['DATE_TEXT' => $dateText],
                '', [],
                $corr, ['DATE_TEXT' => $dateText, 'CUST_VEND' => $custVend]
            );
            $ok = false;
        }

        if (!ValidateDate(isl_trim($values['WHENDUE']))) {
            $gErr->addIAError(
                'INV-1332', __FILE__ . ':' . __LINE__,
                "The $dateText '" . $values['WHENDUE'] . "' is invalid.", ['DATE_TEXT' => $dateText, 'VALUES_WHENDUE' => $values['WHENDUE']]
            );
            $ok = false;
        }

        //creation date should be before due date
        // If the document is draft, we should ignore the validation.
        if ($ok && !empty($values['WHENDUE'] ?? '') && SysDateCompare($values['WHENDUE'], $values['WHENCREATED']) < 0
            && !$this->isDraftDocument($values)) {
            $gErr->addIAError(
                'INV-1333', __FILE__ . ':' . __LINE__,
                "$dateText cannot be earlier than the date of the transaction.", ['DATE_TEXT' => $dateText]
            );
            $ok = false;
        }

        return $ok;
    }

    /**
     * Prepare the Entity Values by passing the values as a reference.
     * Applicable only for PO/SO modules and uses sub methods to populate the actual values.
     *
     * @param  array &$values values of the document.
     * @param   array $docpar
     * @return true|false $ok returns if the method execution was success or not.
     */
    function PrepareEntityValues(&$values, $docpar)
    {

        $ok = true;
        $ok = $ok && $this->PrepCustVendValues($values);
        $ok = $ok && $this->ValidateDates($values);
        $ok = $ok && $this->ValidateVendorDocNumber($values, $docpar);
        $ok = $ok && $this->ValidateShiptoBilltoValues($values);
        $ok = $ok && $this->PrepShiptoValues($values);
        $ok = $ok && $this->PrepBilltoValues($values);
        $ok = $ok && $this->prepDeliverToContact($values);

        return $ok;
    }

    /**
     *   This is required only in SO,
     *  So, Overriden in SO and supplied necessary logic
     *   In case of applications it should return true
     *
     * @param array $values
     *
     * @return bool
     */
    protected function validateCustomerCreditLimit(
        /** @noinspection PhpUnusedParameterInspection */ $values)
    {
        return true;
    }

    /**
     * Prepare the Customer/Vendor values of the document. Make use of CUSTVENDID of the $values to look up to the customer/vendor
     * based on the module SO/PO
     *
     * @param  array &$values values of the document.
     * @param  array $custVendRec                       
     *
     * @return true|false $ok returns if the method execution was success or not.
     */
    function PrepCustVendValues(&$values, &$custVendRec=[])
    {
        // TODO: Should be _isCustVendRequired
        if (!$this->_IsCustVendRequired && $values['CUSTVENDID'] == '') {
            return true;
        }

        $ok = true;
        global $gErr, $gManagerFactory;

        $contactMgr =  $gManagerFactory->getManager('contact');
        $contactversionMgr =  $gManagerFactory->getManager('contactversion');

        if ($ok && $values['CUSTVENDID']) {
            [$ID] = explode('--', $values['CUSTVENDID']);
            $values['CUSTVENDID'] = $ID;

            $cv = $values['_DOCPAR']['CUST_VEND'];
            $mgr = $gManagerFactory->getManager(( $cv == 'Customer') ? 'customer' : 'vendor');
            //$custVendRec = $mgr->GetRaw($values['CUSTVENDID']);

            $fields = array('NAME', 'ENTITY', 'DISPLAYCONTACTKEY', 'GLGRPKEY', 'TERMSKEY');
            if ($cv != 'Customer') {
                $custVendFilter = 'VENDORID';
                array_push($fields, 'FORM1099TYPE', 'FORM1099BOX', 'PAYTO.CONTACTNAME', 'RETURNTO.CONTACTNAME');

            } else {
                $custVendFilter = 'CUSTOMERID';
                array_push($fields, 'CUSTREPKEY', 'SHIPTO.CONTACTNAME', 'BILLTO.CONTACTNAME', 'VSOEPRICELIST',
                           'SHIPPINGMETHOD');
            }

            $custVendRec = $mgr->GetList(
                array('selects' => $fields,
                    'filters' => array(array(
                        array($custVendFilter, '=', $values['CUSTVENDID'])))
                )
            );

            // There is no need to prep for customer vend values when appending to an existing schedule.
            $ok = $ok && (isset($custVendRec[0]) || $values['ENTRIES'][0]['SC_EXISTINGSCHED']);

            if (!$ok) {
                $msg = "Invalid Customer " . $values['CUSTVENDID'] . ".";
                $gErr->addIAError('INV-1293', __FILE__ . ':' . __LINE__, $msg, ['VALUES_CUSTVENDID' => $values['CUSTVENDID']]);
            }

            $custVendRec = $custVendRec[0];
            $values['CUSTVENDNAME'] = $custVendRec['NAME'];

            // populate default term and due date
            if (!empty($values['TERMKEY'])) {
                $defTermKey = $values['TERMKEY'];
            } else if (!empty($custVendRec['TERMSKEY'])) {
                $defTermKey = $custVendRec['TERMSKEY'];
            } else {
                $defTermKey = $values['_DOCPAR']['TERMKEY'];
            }

            $ok = $ok && $this->populateDefaultTermAndDueDate($values, $defTermKey);

            $values[':entity'] = $custVendRec['ENTITY'];
            $head = $contactMgr->GetHeadByRecordNo($custVendRec['DISPLAYCONTACTKEY']);
            $values['CONTACTKEY'] = $head['VREC#'];

            if(!isset($this->contactVersionCache[$values['CONTACTKEY']])){
                    $this->contactVersionCache[$values['CONTACTKEY']] = $contactversionMgr->get($values['CONTACTKEY']);
                }
            $values['CONTACT'] = $this->contactVersionCache[$values['CONTACTKEY']] ; // For PrintXML


            $values['ENTGLGROUP'] = $custVendRec['GLGRPKEY'];
            $values['CUSTREPID'] = $custVendRec['CUSTREPKEY'];

            if ($values['_DOCPAR']['UPDATES_GL'] == 'A' && !empty($custVendRec['FORM1099TYPE']) && !empty($custVendRec['FORM1099BOX'])) {
                $values['FORM1099FORMAT'] = $custVendRec['FORM1099TYPE'] . '@' . $custVendRec['FORM1099BOX'];
            }

            if ($cv != 'Customer') {
                $billTo = $custVendRec['PAYTO.CONTACTNAME'];
                $shipTo = $custVendRec['RETURNTO.CONTACTNAME'];
            } else {
                $billTo = $custVendRec['BILLTO.CONTACTNAME'];
                $shipTo = $custVendRec['SHIPTO.CONTACTNAME'];
            }
        }

        // assume shipto/billto as custvend contact [displycontact ], if it is empty.,
        if (!isset($values['BILLTO']['CONTACTNAME']) || $values['BILLTO']['CONTACTNAME'] == '') {
            if(!is_array($values['BILLTO'])){
                $values['BILLTO'] = ["CONTACTNAME"=> $billTo ?? $values['CONTACT']['CONTACTNAME']];
            }else {
                $values['BILLTO']['CONTACTNAME'] =
                    $billTo ?? $values['CONTACT']['CONTACTNAME'];
            }
        }
        if ($values['SHIPTO']['CONTACTNAME'] == '') {
            $values['SHIPTO']['CONTACTNAME'] =
                $shipTo ?? $values['CONTACT']['CONTACTNAME'];
        }

        return $ok;
    }

    /**
     *   This is required only in PO,
     *  So, Overriden in PO and supplied necessary logic
     *   In case of applications it should return true
     *
     * @param array $values
     * @param array $docpar
     *
     * @return bool
     */
    function ValidateVendorDocNumber(
        /** @noinspection PhpUnusedParameterInspection */ $values,
        /** @noinspection PhpUnusedParameterInspection */ $docpar)
    {
        return true;
    }

    /**
     * Validate the BillTo/ShipTo Values of the document.
     *
     * @param  array &$values values of the document.
     * @return true|false $ok returns if the method execution was success or not.
     */
    function ValidateShiptoBilltoValues(&$values)
    {
        $ok = true;
        global $gErr, $gManagerFactory;

        $isDraft = $this->isDraftDocument($values);
        // check for shipto/billto
        if ($values['_DOCPAR']['SALE_PUR_TRANS'] != 'Internal')
        {
            $errorCode = 'INV-1326';
            if($values['_DOCPAR']['SALE_PUR_TRANS'] == 'Purchase'){
                $errorCode = 'INV-1294';
            }

            if (!$isDraft
                && $this->_isCustVendRequired && !$values['CUSTVENDID'])
            {
                $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__);
                $ok = false;
            }

            if (!$isDraft
                && $this->_isCustVendRequired
                && ((!isset($values['SHIPTO']['CONTACTNAME']) || !$values['SHIPTO']['CONTACTNAME'])
                    || (!isset($values['BILLTO']['CONTACTNAME']) || !$values['BILLTO']['CONTACTNAME']))
            )
            {
                $msg = "Missing required address in Header tab.";
                $gErr->addIAError('INV-1295', __FILE__ . ':' . __LINE__, $msg, []);
                $ok = false;
            }
        }


        // check bill to / ship to
        $contactMgr = $gManagerFactory->getManager('contact');
        $args = [
            'selects' => ['CONTACTNAME',],
            'filters' => [[['status', '=', 'T']]],
        ];
        $customerid = $values['CUSTVENDID'];
        $customername = $values['CUSTVENDNAME'];
        $constrictvalues = $this->getConstrictValues();

        $billtolabel = $constrictvalues['billtolabel'];
        $shiptolabel = $constrictvalues['shiptolabel'];
        $custlabel = $constrictvalues['custlabel'];


        if ($constrictvalues['pref'] == 'dropdown' && isset($values['CUSTVENDID']) && $values['CUSTVENDID'] != '')
        {
            //  constrict the list
            $constrictfilter = $contactMgr->getConstrictQuery($customerid, $constrictvalues['prefix']);
            $args['filters'][0][] = $constrictfilter;

            // get the list of contacts
            $list = $contactMgr->GetList($args);

            // create local function for checking list
            $searchForId = (function ($id, $array)
            {
                foreach ($array as $key => $val)
                {
                    if ($val['CONTACTNAME'] === $id)
                    {
                        return $key;
                    }
                }
                return null;
            });

            // check contact
            $contact = $values['BILLTO']['CONTACTNAME'];
            $found = $searchForId($contact, $list);
            if (is_null($found))
            {
                // error
                // send some error message
                $gErr->addIAError(
                    'INV-1334', __FILE__ . ':' . __LINE__,
                    sprintf('The %1$s contact %2$s is not associated with %3$s. If you want to use this contact here, assign the contact to the %4$s and then try again. Otherwise select a different %4$s contact.', $billtolabel, $contact, $customername, $custlabel),
                    ['BILLTOLABEL' => $billtolabel, 'CONTACT' => $contact, 'CUSTOMERNAME' => $customername, 'CUSTLABEL' => $custlabel]
                );
                $ok = false;
            }

            $contact = $values['SHIPTO']['CONTACTNAME'];
            $found = $searchForId($contact, $list);
            if (is_null($found))
            {
                // error
                // send some error message
                $gErr->addIAError(
                    'INV-1335', __FILE__ . ':' . __LINE__,
                    sprintf('The %1$s contact %2$s is not associated with %3$s. If you want to use this contact here, assign the contact to the %4$s and then try again. Otherwise select a different %4$s contact.', $shiptolabel, $contact, $customername, $custlabel),
                    ['SHIPTOLABEL' => $shiptolabel, 'CONTACT' => $contact, 'CUSTOMERNAME' => $customername, 'CUSTLABEL' => $custlabel]
                );
                $ok = false;
            }

            if ($constrictvalues['so'] && $constrictvalues['soline'])
            {
                // do only for so
                foreach ((($values['ENTRIES']) ?? []) as $entry)
                {
                    $contact = $entry['SHIPTO']['CONTACTNAME'];
                    $found = $searchForId($contact, $list);
                    if (is_null($found) && !empty($contact))
                    {
                        // error
                        // send some error message
                        $gErr->addIAError(
                            'INV-1336', __FILE__ . ':' . __LINE__,
                            sprintf('The line level %1$s contact %2$s is not associated with %3$s. If you want to use this contact here, assign the contact to the %4$s and then try again. Otherwise select a different %4$s contact.', $shiptolabel, $contact, $customername, $custlabel),
                            ['SHIPTOLABEL' => $shiptolabel, 'CONTACT' => $contact, 'CUSTOMERNAME' => $customername, 'CUSTLABEL' => $custlabel]
                        );
                        $ok = false;
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * @return array
     */
    function getConstrictValues()
    {
        $value = [];
        $value['prefix'] = 'C';
        $value['pref'] = 'none';
        $value['billtolabel'] = I18N::getSingleToken("IA.BILL_TO");
        $value['shiptolabel'] = I18N::getSingleToken("IA.SHIP_TO");
        $value['custlabel'] = I18N::getSingleToken("IA.CUSTOMER");
        $value['so'] = true;
        $value['soline'] = false;
        return $value;

    }


    /**
     * Prepare the Ship To Values of the document. Always get the latest contact info by looking to the contactversion table.
     *
     * @param  array &$values values of the document.
     * @return true|false $ok returns if the method execution was success or not.
     */
    function PrepShiptoValues(&$values)
    {
        $ok = true;

        if ($values['SHIPTO']['CONTACTNAME']) {
            global $gErr, $gManagerFactory;
            $contactMgr =  $gManagerFactory->getManager('contact');
            $contactversionMgr =  $gManagerFactory->getManager('contactversion');

            if ((isl_trim($values['SHIPTO']['CONTACTNAME']) === isl_trim($values['CONTACT']['CONTACTNAME'])) && ($values['GETLATESTSHIPTO'] == 'true')) {

                $values['SHIPTO'] = $values['CONTACT'];
                $vrec = $values['CONTACTKEY'];

            } else {

                $oldShipto = $contactversionMgr->get($values['SHIPTOKEY']);


                if ($values['GETLATESTSHIPTO'] != 'true' && isl_trim($oldShipto['CONTACTNAME']) == isl_trim($values['SHIPTO']['CONTACTNAME'])) {


                    $vrec = $values['SHIPTOKEY'];
                    $values['SHIPTO'] = $oldShipto;

                } else {

                    $vrec = $contactMgr->GetCurrentVersionNo($values['SHIPTO']['CONTACTNAME']);

                    if (!isset($vrec)) {
                        $gErr->addIAError(
                            'INV-1337', __FILE__ . ":" . __LINE__,
                            "The contact " . $values['SHIPTO']['CONTACTNAME'] . " is invalid", ['VALUES_SHIPTO_CONTACTNAME' => $values['SHIPTO']['CONTACTNAME']]
                        );
                        $ok = false;
                    }

                    // Latest contactversion will be same as contact, so don't bother about getting from version table.
                    if(!isset($this->contactVersionCache[$vrec])){
                            $this->contactVersionCache[$vrec] = $contactversionMgr->get($vrec);
                        }
                    $values['SHIPTO'] = $this->contactVersionCache[$vrec] ;
                }
            }
            $values['SHIPTOKEY'] = $vrec;
        }
        return $ok;
    }


    /**
     * Prepare the Bill To Values of the document. Always get the latest contact info by looking to the contactversion table.
     *
     * @param  array &$values values of the document.
     * @return true|false $ok returns if the method execution was success or not.
     */
    function PrepBilltoValues(&$values)
    {
        $ok = true;

        if ($values['BILLTO']['CONTACTNAME']) {
            global $gErr, $gManagerFactory;
            $contactMgr =  $gManagerFactory->getManager('contact');
            $contactversionMgr =  $gManagerFactory->getManager('contactversion');

            // An attempt to reduce a number of redundant queries here.
            if (isl_trim($values['BILLTO']['CONTACTNAME']) === isl_trim($values['CONTACT']['CONTACTNAME']) && $values['GETLATESTBILLTO'] == 'true') {

                $values['BILLTO'] = $values['CONTACT'];
                $vrec = $values['CONTACTKEY'];

            } else if ((isl_trim($values['BILLTO']['CONTACTNAME']) === isl_trim($values['SHIPTO']['CONTACTNAME'])) && $values['GETLATESTSHIPTO'] == 'true') {

                $values['BILLTO'] = $values['SHIPTO'];
                $vrec = $values['SHIPTOKEY'];

            } else {

                $oldBillto = $contactversionMgr->get($values['BILLTOKEY']);

                if ($values['GETLATESTBILLTO'] != 'true' && isl_trim($oldBillto['CONTACTNAME']) == isl_trim($values['BILLTO']['CONTACTNAME'])) {

                    $vrec = $values['BILLTOKEY'];
                    $values['BILLTO'] = $oldBillto;

                } else {

                    $vrec = $contactMgr->GetCurrentVersionNo($values['BILLTO']['CONTACTNAME']);

                    if (!isset($vrec)) {
                        $gErr->addIAError(
                            'INV-1338', __FILE__ . ":" . __LINE__,
                            "The contact " . $values['BILLTO']['CONTACTNAME'] . " is invalid", ['VALUES_BILLTO_CONTACTNAME' => $values['BILLTO']['CONTACTNAME']]
                        );
                        $ok = false;
                    }

                    // Latest contactversion will be same as contact, so don't bother about getting from version table.
                    if(!isset($this->contactVersionCache[$vrec])){
                            $this->contactVersionCache[$vrec] = $contactversionMgr->get($vrec);
                        }
                    $values['BILLTO'] = $this->contactVersionCache[$vrec] ;
                }
            }
            $values['BILLTOKEY'] = $vrec;
        }

        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function prepDeliverToContact(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return true;
    }

    /**
     * @param array $qparams
     *
     * @return false|string
     * @throws Exception
     */
    public function updateDocumentContactVersion($qparams)
    {

        global $gManagerFactory;

        $contact = $qparams['contact'];
        $contactType = $qparams['contacttype'];

        $contactMgr = $gManagerFactory->getManager('contact');
        $vrec = $contactMgr->GetCurrentVersionNo($contact);

        if (!isset($vrec)) {
            /** @noinspection PhpUndefinedVariableInspection */
            Globals::$g->gErr->addIAError(
                'INV-1339', __FILE__ . ":" . __LINE__,
                "The contact " . $values['BILLTO']['CONTACTNAME'] . " is invalid", ['VALUES_BILLTO_CONTACTNAME' => $values['BILLTO']['CONTACTNAME']]
            );
        }

        $contactUpdateQry = '';
        if ($contactType == 'BILLTO') {
            $contactUpdateQry = "update dochdrmst set billtokey = :1 where cny# = :2 and record# = :3 ";
        } else if ($contactType == 'SHIPTO') {
            $contactUpdateQry = "update dochdrmst set shiptokey = :1 where cny# = :2 and record# = :3 ";
        }
        if ($contactUpdateQry != '' && $vrec) {

            /*
            XACT_BEGIN("UpdateDocumentContactVersion");

            $ok = $ok && ExecStmt(array($contactUpdateQry, $vrec, GetMyCompany(), $dockey));

            if (!$ok) {
            XACT_ABORT("UpdateDocumentContactVersion");
            $xmlStr = "<updateDocumentContactVersion></updateDocumentContactVersion>";
            return $xmlStr;
            } else {
            XACT_COMMIT("UpdateDocumentContactVersion");
            }
            */
            $contactversionMgr = $gManagerFactory->getManager('contactversion');
            $contactRecord = $contactversionMgr->get($vrec);
            LogToFile(pp($contactRecord));

            $address1 = isl_htmlspecialchars($contactRecord['MAILADDRESS']['ADDRESS1']);
            $address2 = isl_htmlspecialchars($contactRecord['MAILADDRESS']['ADDRESS2']);
            $address3XmlFragment = "";
            if (self::isAddressLineThreeEnabled()) {
                $address3 = isl_htmlspecialchars($contactRecord['MAILADDRESS']['ADDRESS3']);
                $address3XmlFragment = "address3=\"$address3\"";
            }
            $city = isl_htmlspecialchars($contactRecord['MAILADDRESS']['CITY']);
            $state = isl_htmlspecialchars($contactRecord['MAILADDRESS']['STATE']);
            $zip = isl_htmlspecialchars($contactRecord['MAILADDRESS']['ZIP']);
            $email = isl_htmlspecialchars($contactRecord['EMAIL1']);
            $xmlStr = "<updateDocumentContactVersion>
						<contact contacttype=\"$contactType\">
							<mailaddress address1=\"$address1\"
								address2=\"$address2\"
								" . $address3XmlFragment . "
								city=\"$city\"
								state=\"$state\"
								zip=\"$zip\">
							</mailaddress>
						</contact>
						<email1>$email
						</email1>
					</updateDocumentContactVersion>";

            return $xmlStr;
        }
        return false;

    }


    /**
     * method to validate the MCP fields.
     *
     * @param  array &$values values of the transaction
     *
     * @return true|false denotes if the method execution had any error or not.
     */
    function validateMCPFields(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $ok = true;
        $this->setExchangeRateFieldsForChangeOrder($values);

        $baseCurr = GetBaseCurrency();
        if (empty($baseCurr)) {
            $baseCurr = GetLocationBaseCurrency($values['ENTRIES'][0]['LOCATION']);
        }

        if (empty($values['BASECURR'])) {
            $values['BASECURR'] = $baseCurr;
        }

        $isDraft = $this->isDraftDocument($values);

        if (!$isDraft
            && (empty($values['BASECURR']) || (!empty($baseCurr) && $baseCurr != $values['BASECURR']))) {
            $errorCode = 'INV-1344';
            if ($this->atlas) {
                $errorCode = 'INV-1345';
            }
            $gErr->addIAError($errorCode, __FILE__ . ":" . __LINE__);
            $ok = false;
        }

        if (empty($values['CURRENCY'])) {
            $values['CURRENCY'] = $values['BASECURR'];
        }

        if (!$isDraft
            && empty($values['CURRENCY'])) {
            $gErr->addIAError('INV-0021', __FILE__ . ":" . __LINE__, "The record requires the field 'Currency'", []);
            $ok = false;
        } else {
            $trxcurrenciesMgr = Globals::$g->gManagerFactory->getManager('trxcurrencies');
            $currencyInfo = $trxcurrenciesMgr->GetCurrencyInfo($values['CURRENCY']);
            if ( empty($currencyInfo) ) {
                $gErr->addIAError(
                    "CO-0648", GetFL(), "This transaction currency does not exist for this company.", [],
                    "Please select the \"Currency\" from the existing transaction currencies"
                );
                $ok = false;
            }
        }

        // Make sure we have no MCP transactions is MCP is not subscribed
        if (!IsMCPSubscribed() && $values['BASECURR'] != $values['CURRENCY']) {
            $ok = false;
            $gErr->addIAError(
                'INV-0022', __FILE__ . ':' . __LINE__, 'Enable foreign-currency transactions, and try again.', []
            );
        }

        $baseCurTrans = ($values['CURRENCY'] === $values['BASECURR']);
        if ($baseCurTrans) {
            $values['EXCHRATE'] = 1;
            $exchangeRate = 1;
            unset($values['EXCH_RATE_TYPE_ID']);
            unset($values['EXCHRATETYPES']['NAME']);
        }

        $curRate = 0;
        if ($values['_DOCPAR']['OVERRIDE_EXCH_RATE_TYPE'] === 'false' && !$baseCurTrans) {

            if($values['_DOCPAR']['EXCH_RATE_TYPE_ID']=='-1') {
                $values['_DOCPAR']['EXCHRATETYPES']['NAME'] = 'Intacct Daily Rate';
            }

            if (
                !empty($values['EXCHRATETYPES']['NAME'])
                && !empty($values['_DOCPAR']['EXCHRATETYPES']['NAME'])
                && $values['_DOCPAR']['EXCHRATETYPES']['NAME'] != $values['EXCHRATETYPES']['NAME']
            ) {
                $gErr->addIAError(
                    'INV-1340', __FILE__ . ":" . __LINE__,
                    "Transaction Definition '" . $values['_DOCPAR']['DOCID'] .
                    "' does not allow to override Exchange Rate Type", ['VALUES_DOCPAR_DOCID' => $values['_DOCPAR']['DOCID']],
                    "Do not provide the value for Exchange Rate Type", []
                );
                $ok = false;
            }

            if (!empty($values['EXCHRATE'])) {
                $curRate = $values['EXCHRATE'];
                unset($values['EXCHRATE']);
            }
        }

        if (empty($values['EXCHRATETYPES']['NAME']) && !$baseCurTrans) {
            if ($values['EXCHRATE']) {
                $values['EXCHRATETYPES']['NAME'] = CUSTOM_RATE;
            } else if ($values['_DOCPAR']['EXCHRATETYPES']['NAME'] != '') {
                $values['EXCHRATETYPES']['NAME'] = $values['_DOCPAR']['EXCHRATETYPES']['NAME'];
            } else {
                $values['EXCHRATETYPES']['NAME'] = INTACCT_RATE;
            }
        }

        if ($ok && !empty($values['EXCHRATETYPES']['NAME'])) {

            $exchratetypeMgr = $gManagerFactory->getManager('exchangeratetypes');
            $exchrateid = $exchratetypeMgr->GetExchangeRateTypeID($values['EXCHRATETYPES']['NAME']);

            if (empty($exchrateid)) {
                $gErr->addIAError(
                    'INV-0023', __FILE__ . ":" . __LINE__,
                    "This Exchange Rate Type does not exist for this company.", [],
                    "Please select the \"Exchange Rate Type\" from the existing Exchange Rate Types", []
                );
                $ok = false;
            } else {
                $values['EXCH_RATE_TYPE_ID'] = $exchrateid;
            }
        }

        $values['EXCHRATEDATE'] = !empty($values['EXCHRATEDATE']) ? $values['EXCHRATEDATE'] : $values['WHENCREATED'];

        if ($ok && $values['EXCH_RATE_TYPE_ID'] && $values['EXCH_RATE_TYPE_ID'] != CUSTOM_RATE_ID) {

            $trxexchrateMgr = $gManagerFactory->getManager('exchangerate');
            $exchangeRate = $trxexchrateMgr->GetTrxExchangeRateByTypeID(
                $values['EXCH_RATE_TYPE_ID'], $values['CURRENCY'], $values['BASECURR'], $values['EXCHRATEDATE']
            );
        }

        if ($ok && empty($values['EXCHRATE'])) {

            if ($values['EXCH_RATE_TYPE_ID'] && $values['EXCH_RATE_TYPE_ID'] != CUSTOM_RATE_ID) {
                /** @noinspection PhpUndefinedVariableInspection */
                $values['EXCHRATE'] = $exchangeRate;
            }

            if (!isset($values['EXCHRATE']) || $values['EXCHRATE'] == '') {
                $gErr->addIAError(
                    'INV-0024', __FILE__ . ":" . __LINE__,
                    "Exchange rate is empty.", []
                );
                $ok = false;
            }

            if ($curRate && $values['EXCHRATE'] != $curRate) {
                $gErr->addIAError(
                    'INV-1341', __FILE__ . ":" . __LINE__,
                    "Transaction Definition '" . $values['_DOCPAR']['DOCID']
                    . "' does not allow to override Exchange Rate", ['VALUES_DOCPAR_DOCID' => $values['_DOCPAR']['DOCID']],
                    "Do not provide the value for Exchange Rate", []
                );
                $ok = false;

            }
        }
        /** @noinspection PhpUndefinedVariableInspection */
        elseif ( $values['EXCHRATE'] != $exchangeRate) {
            $values['EXCH_RATE_TYPE_ID'] = CUSTOM_RATE_ID;
        }

        return $ok;
    }

    /**
     * Go through each line entries, if the line entry is a kit with component level printing setup, then
     * we get all the leaf items under it and add them to the 'ENTRIES' array so that the existing logic of
     * PrepLineItems takes care of expanding them as normal.
     *
     * @param array $values
     *
     * @return bool
     */
    function ExpandKitItem(&$values)
    {
        global $gManagerFactory;

        $itemMgr = $gManagerFactory->getManager('item');

        $lineitemCnt = count($values['ENTRIES']);

        $priceElements = array('RETAILPRICE', 'TRX_PRICE', 'UIPRICE', 'TRX_VALUE', 'UIVALUE');
        $unitPriceElements = array('TRX_PRICE', 'UIPRICE');
        $replaceElements = array('ITEMID', 'ITEMDESC', 'ITEMNAME', 'UIQTY', 'UNIT', 'ITEMCURRENT');
        $otherElements = ['ITEMALIASKEY', 'ITEMALIASID'];
        $itemsArr = [];

        for ($i = 0; $i < $lineitemCnt; $i++) {
            if ( $values['ENTRIES'][$i]['ITEMID'] != '' && !in_array($values['ENTRIES'][$i]['ITEMID'], $itemsArr, true)) {
                $itemsArr[] = $values['ENTRIES'][$i]['ITEMID'];
            }
        }

        $this->itemRawCache = $itemMgr->GetItemsRawCache($itemsArr, true);

        $isKitsExpanded = false;

        //go through all the existing line entries.
        for ($i = 0; $i < $lineitemCnt; $i++) {
            $currentItemID = $values['ENTRIES'][$i]['ITEMID'];

            //$itemObj = $itemMgr->Get($currentItemID);
            $itemObj = $this->itemRawCache[$currentItemID];

            if ($itemObj['ITEMTYPE'] == 'K' && $itemObj['REVPOSTING'] == 'I') {
                $RevenueItems = $itemMgr->CollectItemPrintingDetails(
                    array('ITEMTYPE' => 'K',
                        'ITEMID' => $currentItemID)
                );

                foreach ($priceElements as $priceName) {
                    //now calculate the relative values based on the percentage.
                    $price = $values['ENTRIES'][$i][$priceName] ?? null;
                    if (isset($price) && is_numeric($price)) {
                        $kitValue = bcmul($values['ENTRIES'][$i][$priceName], '1', 2);
                        $sumValue = 0;
                        foreach ($RevenueItems as $key => $expandedEntry) {
                            $RevenueItems[$key][$priceName] = ibcmul($kitValue, bcdiv($expandedEntry['REVPERCENT'], '100', 10), 2, true);
                            $sumValue = bcadd($sumValue, $RevenueItems[$key][$priceName], 2);
                        }

                        //doing rounding
                        if (($kitValue - $sumValue) != 0) {
                            if ($kitValue > $sumValue) {
                                $unit = 0.01;
                            } else {
                                $unit = -0.01;
                            }

                            foreach ( $RevenueItems as $key => $expandedEntry) {
                                $proposed = bcadd($RevenueItems[$key][$priceName], $unit, 2);
                                if ($proposed >= 0) {
                                    $RevenueItems[$key][$priceName] = $proposed;

                                    $sumValue = bcadd($sumValue, $unit, 2);

                                    //now, we are equal, break
                                    if (($kitValue - $sumValue) == 0) {
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }

                //adjust the unit price, really for QUANTITY not 1.
                foreach ($unitPriceElements as $priceName) {
                    foreach ($RevenueItems as $key => $expandedEntry) {
                        $RevenueItems[$key][$priceName] = bcdiv($RevenueItems[$key][$priceName], $expandedEntry['QUANTITY'], 2);
                    }
                }

                //now create the new expanded component entries
                foreach ($RevenueItems as $expandedEntry) {
                    $newEntry = array();

                    $newEntry['ITEMID'] = $expandedEntry['ITEMID'];


                    $args = array(
                        'selects' => array('ITEMID','NAME','UOM.SOUOMDETAIL.UNIT','UOM.POUOMDETAIL.UNIT','UOM.INVUOMDETAIL.UNIT'),
                        'filters' => array (array (array('ITEMID', '=', $expandedEntry['ITEMID'])))
                    );
                    $expandedItemObj = $itemMgr->GetList($args)[0];

                    $newEntry['ITEMDESC'] = $expandedItemObj['NAME'];
                    $newEntry['ITEMNAME'] = $expandedItemObj['NAME'];
                    $newEntry['ITEMCURRENT'] = $expandedItemObj['ITEMID'] . '--' . $expandedItemObj['NAME'];

                    if ($this->mod == 'so') {
                        $newEntry['UNIT'] = $expandedItemObj['UOM.SOUOMDETAIL.UNIT'];
                    } elseif ($this->mod == 'po') {
                        $newEntry['UNIT'] = $expandedItemObj['UOM.POUOMDETAIL.UNIT'];
                    } else {
                        $newEntry['UNIT'] = $expandedItemObj['UOM.INVUOMDETAIL.UNIT'];
                    }

                    //stick the calculated price based on percentage.
                    foreach ($priceElements as $priceName) {
                        $newEntry[$priceName] = bcmul($expandedEntry[$priceName], '1', 2);
                    }

                    //if UNITFACTOR not set in values, default it to 1, otherwise UIQTY value will go wrong for kit items
                    if ( ! isset($values['ENTRIES'][$i]['UNITFACTOR']) ) {
                        $values['ENTRIES'][$i]['UNITFACTOR'] = 1;
                    }

                    //the real quantity for the component.
                    // replacing with ibcmul to fix php 8.1 IA-128489
                    $newEntry['UIQTY'] = (float) ibcmul(ibcmul($expandedEntry['QUANTITY'], $values['ENTRIES'][$i]['UIQTY'], 14, false), $values['ENTRIES'][$i]['UNITFACTOR'], 14, false);

                    foreach ((($values['ENTRIES']) ?? [])[$i] as $key => $value) {
                        //copy everything there.
                        if (!in_array($key, array_merge($priceElements, $replaceElements, $otherElements))) {
                            $newEntry[$key] = $value;
                        }
                    }

                    //we need to save the total price into another variable since the existing logic overwrites it.
                    $newEntry['TRX_VALUE_OLD'] = $newEntry['TRX_VALUE'];
                    $newEntry['UIVALUE_OLD'] = $newEntry['UIVALUE'];

                    //mark who is my parent in the previous elements in this array
                    $newEntry['EXPANDEDENTRY'] = true;
                    $newEntry['PARENTENTRY'] = $i;

                    //now, add it to the end of array
                    $values['ENTRIES'][] = $newEntry;

                    $isKitsExpanded = true;
                }
            }
        }

        // Once the item has been expanded we should invalidate the raw cache, because the $values['ENTRIES'] is new and should be expanded again in PrepLineItems
        if ($isKitsExpanded) {
            $this->itemRawCache = array();
        }

        return true;
    }


    /**
     * Go through each line entries, collect expanded items that are created for the purpose of print format and save them
     * in another array
     *
     * @param array $values
     *
     * @return bool
     */
    function CollapseKitItem(&$values)
    {
        $lineitemCnt = count($values['ENTRIES']);

        $printFormatEntries = array();
        //go through all the existing line entries.
        for ($i = 0; $i < $lineitemCnt; $i++) {
            //if we are the expanded items for the purpose of print format, then remove it from the ENTRIES array
            if ($values['ENTRIES'][$i]['EXPANDEDENTRY']) {
                //restore these values.
                $values['ENTRIES'][$i]['TRX_VALUE'] = $values['ENTRIES'][$i]['TRX_VALUE_OLD'];
                $values['ENTRIES'][$i]['TRX_ENDVALUE'] = $values['ENTRIES'][$i]['TRX_VALUE_OLD'];
                $values['ENTRIES'][$i]['UIVALUE'] = $values['ENTRIES'][$i]['UIVALUE_OLD'];

                $printFormatEntries[] = $values['ENTRIES'][$i];
                unset($values['ENTRIES'][$i]);
            }
        }

        $values['PRINTFORMATENTRIES'] = $printFormatEntries;

        return true;
    }

    /**
     * @return bool
     */
    public function isShipToLineItemEnable(){
        return false;
    }

    /**
     * @param string $headerShipToContactName
     * @param array  $line
     * @param array $docvalues
     */
    protected function setShipToForLine($headerShipToContactName, &$line, $docvalues)
    {
        $itemId = explode('--', $line['ITEMID'])[0];
        if (!empty($itemId))
        {
            // $tag can be SHIPTO/DELIVERTO
            $tag = $this->getShipToLineItemArrKey($docvalues);
            // $this->overrideLineContactWithHeader($docvalues) condition is needed for PO VAT transaction
            // as there header always override line value
            if ( $this->overrideLineContactWithHeader($docvalues) || empty($line[$tag]['CONTACTNAME'])) {
                $line[$tag]['CONTACTNAME'] = $headerShipToContactName;
            }
            $contactName = $line[$tag]['CONTACTNAME'];
            $line[$tag . 'KEY'] = $this->shipToKeyMap[$contactName];
            $line['SHIPTOTAXGROUPKEY'] = $this->taxGroupKeyMap[$contactName];
            $line['SHIPTOTAXABLE'] = $this->shipToTaxableMap[$contactName];

            //Set line level deliverto keys for VAT companies
            if (($docvalues['TXNISVATENABLED'] ?? false) && $docvalues['ISLINEDELIVERTOENABLED']) {
                if (empty($line['DELIVERTO']['CONTACTNAME'])) {
                    $line['DELIVERTOKEY'] = $this->shipToKeyMap[$line['HEADER']['DELIVERTO']];
                } else {
                    $line['DELIVERTOKEY'] = $this->shipToKeyMap[$line['DELIVERTO']['CONTACTNAME']];
                }
            }

            $line['LINEITEMTAXABLE'] = $this->itemTaxableMap[$itemId];
            $line['LINEITEMTAXGROUPKEY'] = $this->itemTaxGroupMap[$itemId];
        }
    }

    /**
     * determines if line level contact needs to be overridden with header values
     *
     * @param array $values document object
     *
     * @return bool true means yes override line value with header
     */
    protected function overrideLineContactWithHeader(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        return false;
    }

    /**
     * @param array $values
     * @param int $index
     *
     * @return bool
     */
    protected function validateAdjDocuments(
        /** @noinspection PhpUnusedParameterInspection */ &$values,
        /** @noinspection PhpUnusedParameterInspection */ $index)
    {
        return true;
    }

    /**
     * @param array $values
     * @param int $index
     *
     * @return bool
     */
    protected function validateAllocation(
        /** @noinspection PhpUnusedParameterInspection */ $values,
        /** @noinspection PhpUnusedParameterInspection */ $index)
    {
        return true;
    }

    /**
     * @return string
     */
    protected function getEntityID()
    {
        return '';
    }

    /**
     * @param array $itemIDs
     * @param string $entity
     *
     * @return array
     */
    protected function getItemCrossRefCache($itemIDs, $entity)
    {
        $itemCrossRefrences = [];
        $entityID = $this->getEntityID();
        $refTypeArr = ['VENDORID' => 'Vendor', 'CUSTOMERID' => 'Customer'];

        if(empty($entity) || (count($itemIDs) <= 0 ) || $entityID == '') {
            return $itemCrossRefrences;
        }

        $itemCrossRefMgr = Globals::$g->gManagerFactory->getManager('itemcrossref');
        $params = array(
            'selects' => array('RECORDNO', 'REFTYPE', 'ITEMID', 'ITEMALIASID', 'UNIT'),
            'filters' => array(
                array(
                    array('REFTYPE', '=', $refTypeArr[$entityID]),
                    array($entityID, '=', $entity),
                    array('ITEMID', 'IN', $itemIDs),
                )
            ),
        );
        $res = $itemCrossRefMgr->GetList($params);

        foreach($res as $rec) {
            $itemId = $rec['ITEMID'];
            $itemAliasID = $rec['ITEMALIASID'];

            $itemCrossRefrences[$entity][$itemId][$itemAliasID] = $rec;
        }

        return $itemCrossRefrences;
    }

    /**
     * @param array $values
     * @param int $index
     *
     * @return bool
     */
    protected function validateItemCrossReference(&$values, $index)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $line = $values['ENTRIES'][$index];
        $lineno = $index + 1;

        unset($values['ENTRIES'][$index]['ITEMALIASKEY']);
        if ((isset($values['CUSTVENDID']) && $values['CUSTVENDID'] != '') &&
            (isset($line['ITEMALIASID']) && $line['ITEMALIASID'] != '')
        ) {
            $custVendID = $values['CUSTVENDID'];
            $itemID = $line['ITEMID'];
            $itemAliasId = $line['ITEMALIASID'];
            $crossRef = $this->_itemCrossRefrencesCache[$custVendID][$itemID][$itemAliasId];

            if(empty($crossRef['RECORDNO'])) {
                $gErr->addIAError('INV-1296', __FILE__ . '.' . __LINE__, null,
                                  [ 'ITEMID' => $itemID, 'LINENO' => $lineno ]);
                $ok = false;
            } else {
                $values['ENTRIES'][$index]['ITEMALIASKEY'] = $crossRef['RECORDNO'];
            }

            // check if line item unit and the external item unit matches;
            if($ok && $crossRef['UNIT'] != '' && $line['UNIT'] != $crossRef['UNIT']) {
                $gErr->addIAError('INV-1297', __FILE__ . '.' . __LINE__, null,
                                  [ 'ITEM_ALIAS_ID' => $itemAliasId, 'ITEM_ID' => $itemID, 'LINENO' => $lineno ]);
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     */
    protected function setLineNumbers(&$values)
    {
        foreach ($values['ENTRIES'] as $key => $line) {
            $values['ENTRIES'][$key]['L_NO'] = $key;
            $values['ENTRIES'][$key]['LINENO'] = $key;
            $values['ENTRIES'][$key]['LINE_NO'] = $key;
            $values['ENTRIES'][$key]['LINEKEY'] = $key;
        }
    }

    /**
     * Description: validate the LC estimate adjustment documents
     * @param array $values
     *
     * @return bool
     */
    protected function validateEstAdjDocuments(
        /** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return true;
    }

    /**
     * @param int $adjDocHdrKey
     * @param bool $detail
     *
     * @return array
     */
    protected function getAdjDocumentDetails($adjDocHdrKey, $detail)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $adjDocValues = array();

        $params = array(
            'selects' => array('DOCID', 'UPDATES_INV', 'SALE_PUR_TRANS', 'DOCPAR_IN_OUT'),
            'filters' => array(
                array(
                    array('RECORDNO', '=', $adjDocHdrKey),
                )
            ),
            'nodbfilters' => true
        );

        $adjDocPar = $this->GetList($params);
        $adjDocPar = $adjDocPar[0];

        if (
            !empty($adjDocPar)
            && $adjDocPar['UPDATES_INV'] != 'Quantity'
            && $adjDocPar['SALE_PUR_TRANS'] != 'Sales'
            && $adjDocPar['DOCPAR_IN_OUT'] == 'Increase'
        ) {

            if ($detail) {

                $lineManager = $gManagerFactory->getManager($this->mod . 'documententry', false, array( 'DOCTYPE' => $this->_docType));
                $params = array(
                    'selects' => array('RECORDNO', 'ITEMID', 'WAREHOUSE.LOCATION_NO', 'WHENCREATED', 'ADJDOCENTRYKEY'),
                    'filters' => array(
                        array(
                            array('DOCHDRNO', '=', $adjDocHdrKey),
                        )
                    ),
                    'nodbfilters' => true
                );

                $res = $lineManager->GetList($params);
                foreach ($res as $r) {
                    $r['_DOCPAR'] = $adjDocPar;
                    $adjDocValues[$adjDocHdrKey][$r['RECORDNO']] = $r;
                }
            } else {
                $adjDocValues[$adjDocHdrKey] = $adjDocPar;
            }

        }

        return $adjDocValues;
    }

    /**
     * @param array $values
     */
    public function prepareLineLevelContact(&$values)
    {
    }

    /**
     * @return string[]
     */
    protected function GetNonInventoryItems()
    {
        return array("NI", "NP", "NS");
    }


    /**
     * Prepare the Line Item values of the document. Validates the line items of the $values array structure.
     * Initialize dictionary values. Needed in case of exception to throw the proper error text.
     * Gather the department, location, glaccount informations.
     * Instantiate the various managers [Item, DocEntry, Warehouse, UOM]
     * Cache the values of Item, Warehouse, UOM
     * Loop through the entries of the values array and Validate for Item, Warehouse, Department, Location.
     * Append item information into the ENTRIES array like precision, desc etc.
     * Calculate the pricing values by using the suggestprice method of PricingHandler.
     *
     * @param  array             &$values values of the document.
     * @param  TrackingHandler[] $handlers
     * @param  bool $newdoc
     *
     * @return bool $ok returns if the method execution was success or not.
     * @noinspection UnsupportedStringOffsetOperationsInspection
     */
    function PrepLineItems(&$values, $handlers=[], /** @noinspection PhpUnusedParameterInspection */ $newdoc = true, bool $forPrinting=false)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $ok = true;

        if ( ! isset($values['ENTRIES'])) {
            $values['ENTRIES'] = [];
        }

        //expand kit components and add to the end of 'ENTRIES' if kit print format is set to print kit component.
        $ok = $ok && $this->ExpandKitItem($values);

        // Instantiate the sub entity managers.
        $itemMgr =  $gManagerFactory->getManager('item');
        $warehseMgr =  $gManagerFactory->getManager('warehouse');
        $locMgr = $gManagerFactory->getManager('location');
        $deptMgr = $gManagerFactory->getManager('department');
        $timeTypeMgr = $gManagerFactory->getManager('timetype');
        $eeAcctLabelMgr = $gManagerFactory->getManager('eeaccountlabel');
        $taskMgr = $gManagerFactory->getManager('task');
        $taxDetailMgr = $gManagerFactory->getManager(TaxDetailManager::getTaxDetailTypeByModule($this->mod));
        $mod = $this->mod;
        $isInvModuleSubscribed = IsInstalled(Globals::$g->kINVid);

        $basecurr = ($values['BASECURR'] ?: GetBaseCurrency());
        $currency = ($values['CURRENCY'] ?: $basecurr);

        // Cache all the object values needed for validation and entries processing. This saves a lot of individual queries to the database to pick values.
        // The values to cache are items, unitinfo, warehouse and uominfo.
        $itemsArr = array();
        $unitsArr = array();
        $warhsArr = array();
        $deptArr = array();
        $locArr = array();
        $timeTypeArr = array();
        $eeAcctLabelArr = array();
        $dropShipItems = array();
        $btoItems = array();
        $taxdetails = array();
        $defaultLocCache = array();

        $warehouseExist = WarehouseManager::warehouseExist();
        $invSupplies    = ($values['DOCPARID'] === PODocumentManager::SUPPLIESISSUEDOCTYPE) ||
                          ($values['DOCPARID'] === PODocumentManager::SUPPLIESRETURNDOCTYPE);

        //Get the primary Dimension
        //OE and PO have only one PRIMARYDIMENSION and Nothing for Inv
        if(!empty($values['PRIMARYDIMENSION'])) {
            $primaryDimensionMap = array_keys($values['PRIMARYDIMENSION']);
            $primaryDimension = $primaryDimensionMap[0];
            $primaryDimensionVal = $values[$values['PRIMARYDIMENSION'][$primaryDimension]];
        }

        $nonInventoryItems = $this->GetNonInventoryItems();
        $lineitemCnt = count($values['ENTRIES']);

        $values['TXNISVATENABLED'] = $this->isVATEnabled($values);
        $headerKey=$this->getShipToLineItemArrKey($values);
        $isShipToLineItemEnable=$this->isShipToLineItemEnable() || $values['TXNISVATENABLED'];
        if ($isShipToLineItemEnable) {
            if (!isset($this->shipToKeyMap[$values['SHIPTO']['CONTACTNAME']])) {
                $this->shipToKeyMap[$values['SHIPTO']['CONTACTNAME']] = $values['SHIPTOKEY'];
            }
        }
        $headerShipToContact=$values[$headerKey]['CONTACTNAME'];
        $this->prepareLineLevelContact($values);

        $isLineLevelSimpleTaxEnabled = $values['_DOCPAR']['LINELEVELSIMPLETAX'];
        $kModArray = array('so' => Globals::$g->kSOid, 'po' => Globals::$g->kPOid);
        $isTaxScheduleEnabled = self::GetPreferenceForProperty($kModArray[$this->mod], 'TAXSCHED');

        $linesHaveSameDelieverTo = $isShipToLineItemEnable;
        $deliverToKey = '';
        $tag = $this->getShipToLineItemArrKey($values);
        $isDraft = $this->isDraftDocument($values);

        for ($i = 0; $i < $lineitemCnt; $i++) {
            $entry = $values['ENTRIES'][$i];

            $values['ENTRIES'][$i]['WHENCREATED'] = $values['WHENCREATED']; //bring in the date from the parent.
            $values['ENTRIES'][$i]['DOCHDRID'] = $values['DOCID']; //bring in the nexus VID field from the parent.
            $locId = '';
            $locName = '';

            //splitting warehouseid-name and passing warehouseid
            if (isset($values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']) && $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] != '') {
                [$locId, $locName] = explode('--', $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']);
            }
            //For Fulfillment we added extra condition
            if (in_array($values['ENTRIES'][$i]['ITEMTYPE'], $nonInventoryItems) && $values['ENTRIES'][$i]['ENABLEFULFILLMENT'] !== 'T') {
                $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] = '';
                $values['ENTRIES'][$i]['WAREHOUSE']['NAME'] = '';
            } else {
                if(!is_array($values['ENTRIES'][$i]['WAREHOUSE'])){
                    $values['ENTRIES'][$i]['WAREHOUSE'] = array();
                }
                $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] = $locId;
                $values['ENTRIES'][$i]['WAREHOUSE']['NAME'] = $locName;
            }

            if ($values['ENTRIES'][$i]['ITEMID'] != '' && !in_array($values['ENTRIES'][$i]['ITEMID'], $itemsArr, true)) {
                $itemsArr[] = $values['ENTRIES'][$i]['ITEMID'];
            }

            if ($values['ENTRIES'][$i]['UNIT'] != '' && !in_array($values['ENTRIES'][$i]['UNIT'], $unitsArr)) {
                $unitsArr[] = $values['ENTRIES'][$i]['UNIT'];
            }

            $warhsLocation = $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'];
            if ($warhsLocation != '' && !in_array($warhsLocation, $warhsArr)) {
                $warhsArr[] = $warhsLocation;
            }

            $lineDept = $values['ENTRIES'][$i]['DEPARTMENT'];
            $lineDeptId = $values['ENTRIES'][$i]['DEPARTMENTID'];
            $dept = is_string($lineDept) ? explode('--', $lineDept) : [];
            if (isset($dept[0]) && $dept[0] !== '' && !isset($deptArr[$dept[0]])) {
                $deptArr[$dept[0]] = 1;
            } else if ( isset($lineDeptId) && $lineDeptId !== '' && ! isset($deptArr[$lineDeptId]) ) {
                $deptArr[$lineDeptId] = 1;
            }

            $lineLoc = $values['ENTRIES'][$i]['LOCATION'];
            $lineLocId = $values['ENTRIES'][$i]['LOCATIONID'];
            $loc = is_string($lineLoc) ? explode('--', $lineLoc) : [];
            if (isset($loc[0]) && $loc[0] !== '' && !isset($locArr[$loc[0]])) {
                $locArr[$loc[0]] = 1;
            } else if ( isset($lineLocId) && $lineLocId !== '' && ! isset($locArr[$lineLocId]) ) {
                $locArr[$lineLocId] = 1;
            }

            if($isShipToLineItemEnable){
                // DELIVERTO line level feature being enabled, if deliverto at line level is set blank,
                // then don't set header level value for calculating tax
                $hasNoLineDeliverContact = empty($values['ENTRIES'][$i]['DELIVERTO']['CONTACTNAME']);
                $supplyRequisition = (($values['DOCPARID'] === PODocumentManager::SUPPLIESREQUESTDOCTYPE) && ItemManager::isSuppliesInventoryEnabled());
                if (
                    $mod != "po" ||
                    $supplyRequisition ||
                    !$hasNoLineDeliverContact ||
                    TaxSolutionManager::TAXMETHOD_I_AVALARA != GetTaxEngine($mod, ($values['TAXSOLUTIONID'] ?? ''))
                ) {
                    $this->setShipToForLine($headerShipToContact, $values['ENTRIES'][$i],$values);
                    if (!empty($deliverToKey) && ($deliverToKey != $values['ENTRIES'][$i][$tag.'KEY'])) {
                        $linesHaveSameDelieverTo = false;
                    }
                    $deliverToKey = $values['ENTRIES'][$i]['DELIVERTOKEY'];
                }
            }

            if (isset($entry['TIMETYPENAME'])) {
                $timeType = $entry['TIMETYPENAME'];
                if ($timeType != '' && !in_array($timeType, $timeTypeArr)) {
                    $timeTypeArr[] = $timeType;
                }
            }

            if (isset($entry['EEACCOUNTLABEL'])) {
                $eeAccountLabel = $entry['EEACCOUNTLABEL'];
                if ($eeAccountLabel != '' && !in_array($eeAccountLabel, $eeAcctLabelArr)) {
                    $eeAcctLabelArr[] = $eeAccountLabel;
                }
            }

            $values['ENTRIES'][$i]['BASECURR'] = $basecurr;
            if (!$values['ENTRIES'][$i]['CURRENCY']) {
                $values['ENTRIES'][$i]['CURRENCY'] = $currency;
                $values['ENTRIES'][$i]['EXCHANGE_RATE'] = 1;
            }
            //bug#41192
            //In Case of XML, if <taxable> is passed as null, then OVERRIDETAX is stored as null in DOCENTRY
            //As a result, when we edit this kind of transaction and and save, the override functionality is not working, hence we are making it as false
            if (isset($values['ENTRIES'][$i]['OVERRIDETAX']) && $values['ENTRIES'][$i]['OVERRIDETAX'] == '') {
                $values['ENTRIES'][$i]['OVERRIDETAX'] = 'false';
            }

            if ($values['ENTRIES'][$i]['DROPSHIP'] == 'true') {
                $dropShipItems[] = $values['ENTRIES'][$i]['ITEMID'];
            }

            if ($values['ENTRIES'][$i]['BUYTOORDER'] == 'true') {
                $btoItems[] = $values['ENTRIES'][$i]['ITEMID'];
            }

            //Get the primary Dimension
            //OE and PO have only one PRIMARYDIMENSION and Nothing for Inv
            /** @noinspection PhpUndefinedVariableInspection */
            $this->prepLinePrimaryDimensions($primaryDimension, $primaryDimensionVal, $values['ENTRIES'][$i]);
            if ($isLineLevelSimpleTaxEnabled != 'true' || $isTaxScheduleEnabled != 'F') {
                unset($values['ENTRIES'][$i]['LINELEVELSIMPLETAXTYPE']);
            } else if ($isLineLevelSimpleTaxEnabled == 'true' && $isTaxScheduleEnabled == 'F') {
                $values['ENTRIES'][$i]['LINELEVELSIMPLETAXTYPE'] = (isset($entry['LINELEVELSIMPLETAXTYPE']) && $entry['LINELEVELSIMPLETAXTYPE'] != "") ? $entry ['LINELEVELSIMPLETAXTYPE'] : $this->defaultLineLevelSimpleTaxType;
            }

            //Prepare overriden VAT taxdetails
            if (!empty($values['ENTRIES'][$i]['SUBTOTALSENTRY'])) {
                $taxGrpKeyArray[] = "(" . $values['ENTRIES'][$i]['LINEITEMTAXGROUPKEY'] . "," . $values['ENTRIES'][$i]['SHIPTOTAXGROUPKEY'] . " )";
                $subtotalEntries = $values['ENTRIES'][$i]['SUBTOTALSENTRY'];
                $overrideTaxdetails = array_column($subtotalEntries, 'OVERRIDENTAXDETAIL');
                if (!empty($overrideTaxdetails)) {
                    $taxdetails = INTACCTarray_merge($taxdetails, array_values(array_filter($overrideTaxdetails)));
                }
            }
        }

        // if all line level deliverTo are same then copy the same to header level deliver to if it is empty
        if ($linesHaveSameDelieverTo && empty($values[$tag.'KEY'])) {
            $values[$tag.'KEY'] = $deliverToKey;
        }

        if (!$values['CURRENCY']) {
            $values['CURRENCY'] = $basecurr;
            $values['EXCHANGE_RATE'] = 1;
        }

        if (!isset($this->itemRawCache) || empty($this->itemRawCache)) {
            $this->itemRawCache = $itemMgr->GetItemsRawCache($itemsArr, true);
        }

        // Preparing the source entries details for the line items
        $this->prepSourceLinesInfo($values['ENTRIES']);

        $this->_itemCrossRefrencesCache = $this->getItemCrossRefCache($itemsArr, $values['CUSTVENDID']);

        $itemidAsKey = true;
        $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey, true, true);

        if (!empty($warhsArr)) {
            $warhsRawCache = $warehseMgr->GetWareHouseRawCache($warhsArr, true,$forPrinting);
            ItemManager::AddToWarehouseCache($warhsArr, $warhsRawCache);
        }

        $indexedDepts = [];
        if ((!empty($deptArr))) {
            $deptParams['selects'] = array('RECORDNO', 'DEPARTMENTID', 'TITLE');
            $deptParams['filters'] = array(array(array('DEPARTMENTID', 'IN', array_keys($deptArr))));
            $allDepts = $deptMgr->GetList($deptParams);
            foreach ( $allDepts as $value) {
                $indexedDepts[$value['DEPARTMENTID']] = $value;
            }
        }

        $indexedLocRecs = array();
        $indexedLocs = array();
        if ((!empty($locArr))) {
            $locParams['selects'] = array('RECORDNO', 'LOCATIONID', 'NAME');
            $locParams['filters'] = array(array(array('LOCATIONID', 'IN', array_keys($locArr))));
            $allLocs = $locMgr->GetList($locParams);
            foreach ( $allLocs as $value) {
                $indexedLocs[$value['LOCATIONID']] = $value;
                $indexedLocRecs[$value['RECORDNO']] = $value['LOCATIONID'];
            }
        }

        if ((!empty($timeTypeArr))) {
            $querySpec = array(
                'selects' => array('RECORDNO', 'NAME'),
                'filters' => array(array(array('NAME', 'IN', $timeTypeArr)))
            );
            $allObjs = $timeTypeMgr->GetList($querySpec);
            $timeTypeCache = array();
            foreach ($allObjs as $value) {
                $timeTypeCache[$value['NAME']] = $value;
            }
        }

        if ((!empty($eeAcctLabelArr))) {
            $querySpec = array(
                'selects' => array('RECORDNO', 'ACCOUNTLABEL'),
                'filters' => array(array(array('ACCOUNTLABEL', 'IN', $eeAcctLabelArr)))
            );
            $allObjs = $eeAcctLabelMgr->GetList($querySpec);
            $eeAcctLabelCache = array();
            foreach ($allObjs as $value) {
                $eeAcctLabelCache[$value['ACCOUNTLABEL']] = $value;
            }
        }

        $dropShipItemsMap = array();
        if (!empty($dropShipItems)) {
            // may alredy be in the fetched raw items cache.....
            foreach ($dropShipItems as $dsiIndex => $dsi) {
                if (isset($this->itemRawCache[$dsi]['DROPSHIP'])) {
                    // the cache is in internal format, GetList() returns external format.....
                    $dropShipItemsMap[$dsi] = ($this->itemRawCache[$dsi]['DROPSHIP'] === 'T') ? 'true' : 'false';
                    unset($dropShipItems[$dsiIndex]);
                }
            }
            if (!empty($dropShipItems)) {
                $itemParams['selects'] = array('ITEMID', 'DROPSHIP');
                $itemParams['filters'] = array(array(array('ITEMID', 'IN', $dropShipItems)));
                $allItems = $itemMgr->GetList($itemParams);
                foreach ($allItems as $value) {
                    $dropShipItemsMap[$value['ITEMID']] = $value['DROPSHIP'];
                }
            }
        }

        $btoItemsMap = array();
        if (!empty($btoItems)) {
            // may alredy be in the fetched raw items cache.....
            foreach ($btoItems as $b2iIndex => $b2i) {
                if (isset($this->itemRawCache[$b2i]['BUYTOORDER'])) {
                    // the cache is in internal format, GetList() returns external format.....
                    $btoItemsMap[$b2i] = ($this->itemRawCache[$b2i]['BUYTOORDER'] === 'T') ? 'true' : 'false';
                    unset($btoItems[$b2iIndex]);
                }
            }
            if (!empty($btoItems)) {
                $itemParams['selects'] = array('ITEMID', 'BUYTOORDER');
                $itemParams['filters'] = array(array(array('ITEMID', 'IN', $btoItems)));
                $allItems = $itemMgr->GetList($itemParams);
                foreach ($allItems as $value) {
                    $btoItemsMap[$value['ITEMID']] = $value['BUYTOORDER'];
                }
            }
        }

        //Validate overriden VAT tax details
        $taxdetailsMap = array();
        if (!empty($taxdetails)) {
            $taxdetails = array_unique($taxdetails);
            $taxdetailParams['selects'] = array('DETAILID', 'DESCRIPTION', 'VALUE', 'RECORDNO');
            $taxdetailParams['filters'] = array(array(
                array('DETAILID', 'IN', $taxdetails),
                array('TAXSOLUTIONID', '=', ($values['TAXSOLUTIONID'] ?? '')),
                array('TAXTYPE', '=', $this->mod == 'so' ? 'Sale' : 'Purchase'),
            ));
            $taxDetailResult = $taxDetailMgr->GetList($taxdetailParams);
            foreach ($taxDetailResult as $taxDetail) {
                $taxdetailsMap[$taxDetail['DETAILID']] = array(
                    'DESCRIPTION' => $taxDetail['DESCRIPTION'],
                    'PERCENTVAL' => $taxDetail['VALUE'],
                    'RECORDNO' => $taxDetail['RECORDNO'],
                );
            }
            $detailIDsResult = array_column($taxDetailResult, 'DETAILID');
            $detailDiff = INTACCTarray_diff($taxdetails, $detailIDsResult);
            if (!empty($detailDiff)) {
                $strDetails = implode(", ", $detailDiff);
                $msg = "Invalid tax details found: " . $strDetails;
                $gErr->addIAError(
                    'INV-1342', __FILE__ . ':' . __LINE__,
                    "Unable to save Document", [],
                    $msg, ['DETAILS' => $strDetails]
                );
                return false;
            }
        }

        $vendorStockNoCache = array();
        if ($values['_DOCPAR']['SALE_PUR_TRANS'] == 'Purchase') {
            $vendorStockNoCache = $itemMgr->GetVendorStockNoCache($itemsArr, $values['CUSTVENDID'], $warhsArr);
        }

        //FETCH THE LATEST ROW FROM THE DOCPAR
        $pl_docparMgr = $this->get_docpar_manager();
        $pl_docpar = $pl_docparMgr->GetLatestRaw($values['DOCPARID']);
        $pl_docpar = $pl_docpar[0];

        // do we need to check multi-visible objects?
        $_needMultiVisibilityCheck = false;
        $mvcheck = '';

        if (isset($values['CUSTVENDID'])) {
            $mvcheck = ($mod == 'po') ? 'vendor' : 'customer';
        }

        if ($mvcheck != '' && IsMultiVisibilitySubscribed($mvcheck)) {
            /** @noinspection PhpUndefinedVariableInspection */
            $_needMultiVisibilityCheck = ( $entity != '');
        }

        $mvobjs = [];
        if ($_needMultiVisibilityCheck) {
            $mventities = GetMultiOwnershipObjects($mvcheck);
            foreach ($mventities as $mvent) {
                $mvobjs[$mvent] = GetRestrictedObjectMembers(
                    $mvent, $mvcheck,
                    $values['CUSTVENDID']
                );
            }
            $mvDeptObjCnt = count($mvobjs['oda']);
            $mvLocObjCnt = count($mvobjs['ola']);
        }

        $enableOverrideTax = $values['_DOCPAR']['ENABLEOVERRIDETAX'];

        // Needed for SuggestPrice method
        $pricingHandler = $this->get_pricing_handler();
        $priceParams = $pricingHandler->PrepParams($values['CUSTVENDID'], $values['BILLTO']['CONTACTNAME'], $values['SHIPTO']['CONTACTNAME'], $values['WHENCREATED'], $mod);

        // defaulting for MEGA entity Context
        $contextLocation = GetContextLocation(true);

        $atlasWhseBaseCurr = "";

        // Resetting adj. System will decide and change if it is an adjustment document
        $values['ADJ'] = 'false';

        $locationbasecurrCache = array();

        //$totval = 0;
        $hasBinEnabledItems = false;
        $hasTrackingEnabledItems = false;

        $isContractDoc = (SODocumentManager::isContractDocument($values) || SODocumentEntryManager::isContractEntry($values));
        $isShipToContactTaxable = ($values['SHIPTO']['TAXABLE'] == 'true');

        $priceConversionPrefs = [
            'ENABLE_PRICECONVERSION' => $this->isPriceConversionEnabled(),
            'ENABLE_OVERRIDE_TRANSACTION_CONVERSIONTYPE' => $this->isOverrideTrnxConversionTypeEnabled()
        ];
        // Now sit back, get a cup of coffee, let the machines do the work....
        foreach ($values['ENTRIES'] as $key => $line) {

            $lineno = $key + 1;

            $ok = $ok && $this->prepareConversionType($values, $key, $priceConversionPrefs);
            $ok = $ok && $this->prepareEntryitemUOM($values, $key, $uomInfoVals);

            // Store the previously converted line amount, to mark this line as converted.
            $values['ENTRIES'][$key]['QTY_CONVERTED_PREV'] = $values['ENTRIES'][$key]['QTY_CONVERTED'];
            $values['ENTRIES'][$key]['QTY_CONVERTED'] = 0;
            $values['ENTRIES'][$key]['PRICE_CONVERTED_PREV'] = $values['ENTRIES'][$key]['PRICE_CONVERTED'];
            $values['ENTRIES'][$key]['PRICE_CONVERTED'] = 0;
            $values['ENTRIES'][$key]['QUANTITY_PREV'] = $values['ENTRIES'][$key]['QUANTITY'];
            $values['ENTRIES'][$key]['BILLINGSCHEDULEKEY_PREV'] = $values['ENTRIES'][$key]['BILLINGSCHEDULEKEY'];
            $values['ENTRIES'][$key]['DEPARTMENTID'] = '';
            $values['ENTRIES'][$key]['LOCATIONID'] = '';

            $item = $this->itemRawCache[$line['ITEMID']];
            $values['ENTRIES'][$key]['ENABLELANDEDCOST'] = $item['ENABLELANDEDCOST'];
            // $item['PRODUCTLINEKEY'] => This is same as PRODUCTLINEID. Which is VID.
            // itemRawCache is prepared using Select * from ICITEM. In such cases PRODUCTLINEKEY is fetched.
            if ((!isset( $values['ENTRIES'][$key]['PRODUCTLINEID'] ) && $values['ENTRIES'][$key]['PRODUCTLINEID'] == '')
                && (isset( $item['PRODUCTLINEKEY'] ) && $item['PRODUCTLINEKEY'] != '')
            ) {
                $values['ENTRIES'][$key]['PRODUCTLINEID'] = $item['PRODUCTLINEKEY'];
            }

            //Getting values for UOM
            if (!$isDraft && empty($item)) {
                $gErr->addIAError('INV-1343', __FILE__ . '.' . __LINE__, null,
                                  [ 'LINENO' => $lineno, 'ITEM_ITEMID' => $line['ITEMID'] ]);
                $ok = false;
            } else {
                if ($mod == 'inv' && ( ! $invSupplies) && (in_array($item['ITEMTYPE'], array("NI", "NP", "NS", "K")))) {
                    $gErr->addIAError('INV-0664', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'ITEM_ITEMID' => $item['ITEMID'] ]);
                    $ok = false;
                } elseif ($mod == 'po' && $item['ITEMTYPE'] == 'NS') {
                    $gErr->addIAError('INV-0665', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'ITEM_ITEMID' => $item['ITEMID'] ]);
                    $ok = false;
                } elseif ($mod == 'so' && $item['ITEMTYPE'] == 'NP') {
                    $gErr->addIAError('INV-0666', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'ITEM_ITEMID' => $item['ITEMID'] ]);
                    $ok = false;
                }
            }

            $isWarehouseRequired = $item['ITEMTYPE'] == 'I' || $item['ITEMTYPE'] == 'SK' ||
                ($item['ITEMTYPE'] == 'K' && isInventoryRequiredForKit($item['ITEMID']));
            if ($isWarehouseRequired) {

                if ($isInvModuleSubscribed && (!Util::php7eqEmptyStr($line['UIQTY'])) && (Util::php7lt0($line['UIQTY'])) && ($values['_DOCPAR']['ENABLEDOCCHANGE'] !== 'Change Order')) {
                    $msg = "Line $lineno : Transaction for item ".$line['ITEMID'].", has a negative number for Quantity. ".
                        "Change the quantity to a non-negative number, and try again.";
                    $gErr->addIAError('INV-1298', __FILE__ . ':' . __LINE__, $msg, ['LINENO' => $lineno, 'LINE_ITEMID' => $line['ITEMID']]);
                    $ok = false;
                }

                if (!$warehouseExist && (isset($line['WAREHOUSE']['LOCATION_NO']))) {
                    $line['WAREHOUSE']['LOCATION_NO'] = '';
                }

                if ($warehouseExist && $line['WAREHOUSE']['LOCATION_NO'] != '') {
                    $warehse = $warhsRawCache[$line['WAREHOUSE']['LOCATION_NO']];
                    if (!$warehse) {
                        $gErr->addIAError('INV-1346', __FILE__ . '.' . __LINE__, null,
                                          [ 'LINENO' => $lineno, 'WAREHSE' => $warehse ]);
                        $ok = false;
                    }
                }

                // warehouse is mandatory only if following are true
                // Inventroy module is subscribed
                // transaction definiton has defined totals like ONHAND, ONHOLD, ONORDER, DAMAGED, etc..
                if ( $isInvModuleSubscribed
                     && ( isset($values['_DOCPAR']['DOCPAR_TOTALS']) && count($values['_DOCPAR']['DOCPAR_TOTALS']) > 0 )
                     && $line['WAREHOUSE']['LOCATION_NO'] == '' ) {
                    $msg = "Required field warehouse is missing.";
                    $gErr->addIAError('INV-1299', __FILE__ . ':' . __LINE__, $msg, []);
                    $ok = false;
                }

            }
            //
            // this is required data and is missing when transactions are created from XML / CSV / QB Import
            if (!isset($values['ENTRIES'][$key]['COST_METHOD']) || $values['ENTRIES'][$key]['COST_METHOD'] == '') {
                $values['ENTRIES'][$key]['COST_METHOD'] = $item['COST_METHOD'];
            }

            // lets keep the items recordno also in the lineitem structure for future reference
            $values['ENTRIES'][$key]['ITEMDIMKEY'] = $item['ITEMRECORDNO'];
            // Populating the Item Description for SO, PO and IC Transactions

            //Since warehouse is not a dimension in SCM, EntityManager will not translate the value. Lets do it here
            if ( $warhsRawCache[$line['WAREHOUSE']['LOCATION_NO']] ) {
                $values['ENTRIES'][$key]['WAREHOUSEDIMKEY'] = $warhsRawCache[$line['WAREHOUSE']['LOCATION_NO']]['RECORD#'];
            }

            //Copy the warehouse dimension
            if ( $values['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO'] ) {
                $values['ENTRIES'][$key]['WAREHOUSEID'] = $values['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO'];
            }

            if (!isset($values['ENTRIES'][$key]['ITEMDESC'])) {
                if ($item['EXTENDED_DESCRIPTION'] != '') {
                    $values['ENTRIES'][$key]['ITEMDESC'] = $item['EXTENDED_DESCRIPTION'];
                } else {
                    $values['ENTRIES'][$key]['ITEMDESC'] = $item['NAME'];
                }
            }

            // Description & Memeo should not be more than 400 charecters
            if (isl_strlen($values['ENTRIES'][$key]['ITEMDESC']) > 400) {
                $msg = "The Line Item 'Description' field in Line#$lineno cannot contain more than 400 characters ";
                $gErr->addIAError('INV-1347', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, ['LINENO' => $lineno]);
                $ok = false;
            }

            if (isl_strlen($values['ENTRIES'][$key]['MEMO']) > 400) {
                $msg = "The Line Item 'Memo' field in Line#$lineno cannot contain more than 400 characters ";
                $gErr->addIAError('INV-1348', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, ['LINENO' => $lineno]);
                $ok = false;
            }

            // warehouse should be blank for Non-Inventory items
            if ((in_array($item['ITEMTYPE'], $nonInventoryItems)) && $line['WAREHOUSE']['LOCATION_NO'] != ''
                && $values['ENTRIES'][$key]['ENABLEFULFILLMENT'] != 'T') {
                unset($values['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO']);
            }

            if (
                $values['ENTRIES'][$key]['DROPSHIP'] == 'true'
                && $dropShipItemsMap[$values['ENTRIES'][$key]['ITEMID']] != 'true'
            ) {
                $msg = "Deselect the Drop Ship checkbox for '".$values['ENTRIES'][$key]['ITEMID']."' on ".
                    "line $lineno, which is not available for drop ship. Then try again.";
                $gErr->addIAError(
                    'INV-1349', __FILE__ . ':' . __LINE__,
                    "Unable to save Document", [],
                    $msg, ['VALUES_ENTRIES_KEY_ITEMID' => $values['ENTRIES'][$key]['ITEMID'], 'LINENO' => $lineno]);
                $ok = false;
            }

            if (
                $values['ENTRIES'][$key]['DROPSHIP'] == 'true'
                && empty($values['ENTRIES'][$key]['VENDORID'])
            ) {
                $msg = "Select a 'Vendor' for the dropship line item at line $lineno.";
                $gErr->addIAError(
                    'INV-1350', __FILE__ . ':' . __LINE__,
                    "Unable to save Document", [],
                    $msg, ['LINENO' => $lineno]
                );
                $ok = false;
            }
            if (
                $values['ENTRIES'][$key]['BUYTOORDER'] == 'true'
                && $btoItemsMap[$values['ENTRIES'][$key]['ITEMID']] != 'true'
            ) {
                $msg = "Deselect 'Buy to order' checkbox for '".$values['ENTRIES'][$key]['ITEMID']."' on ".
                    "line $lineno, which is not available for 'Buy to order'. Then try again.";
                $gErr->addIAError(
                    'INV-1353', __FILE__ . ':' . __LINE__,
                    "Unable to save Document", [],
                    $msg, ['VALUES_ENTRIES_KEY_ITEMID' => $values['ENTRIES'][$key]['ITEMID'], 'LINENO' => $lineno]
                );
                $ok = false;
            }

            if (
                $values['ENTRIES'][$key]['BUYTOORDER'] == 'true'
                && empty($values['ENTRIES'][$key]['VENDORID'])
            ) {
                $msg = "Select a 'Vendor' for the buy-to-order line item at line $lineno.";
                $gErr->addIAError('INV-1354', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, ['LINENO' => $lineno]);
                $ok = false;
            }

            if (
                $values['ENTRIES'][$key]['BUYTOORDER'] == 'true'
                && empty($values['ENTRIES'][$key]['BTOSHIPTOCONTACTNAME'])
            ) {
                $msg = "Select a 'Buy-to-order deliver to' for the buy-to-order line item at line $lineno.";
                $gErr->addIAError('INV-1355', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, ['LINENO' => $lineno]);
                $ok = false;
            }

            if (
                $values['ENTRIES'][$key]['DROPSHIP'] == 'true'
                && $values['ENTRIES'][$key]['BUYTOORDER'] == 'true'
            ) {
                $msg = "For line $lineno, select either drop ship or buy to order, but not both.";
                $gErr->addIAError('INV-1356', __FILE__ . ':' . __LINE__, "Unable to save Document", [], $msg, ['LINENO' => $lineno]);
                $ok = false;
            }

            $values['ENTRIES'][$key]['CURRENCY'] = $values['CURRENCY'];
            $values['ENTRIES'][$key]['EXCHRATEDATE'] = $values['EXCHRATEDATE'];
            $values['ENTRIES'][$key]['EXCHRATETYPE'] = $values['EXCH_RATE_TYPE_ID'];
            $values['ENTRIES'][$key]['EXCHRATE'] = $values['EXCHRATE'];

            // Preparing value for creating IET's on COGS
            if ($isWarehouseRequired) {
                $warehseLorefkey = $warhsRawCache[$line['WAREHOUSE']['LOCATION_NO']]['LOCATIONREFKEY'];
                // This is required for creating IET's on COGS
                $values['ENTRIES'][$key]['WAREHOUSE']['LOCATIONREFKEY'] = $warehseLorefkey;
            }

            if ($this->atlas && $isWarehouseRequired) {
                $warehse = $warhsRawCache[$line['WAREHOUSE']['LOCATION_NO']];

                if (!isset($warehse['LOCATIONREFKEY']) || $warehse['LOCATIONREFKEY'] === '') {
                    $gErr->addIAError('INV-1357',__FILE__ . ":" . __LINE__, null, ['LINENO' => $lineno]);
                    $ok = false;
                }

                $whseLocationKey = $indexedLocRecs[$warehse['LOCATIONREFKEY']];

                // In case where it is a sublocation of a warehouse location we query that separately rather than getting all records.
                if (!$whseLocationKey) {
                    $locinfo = $locMgr->DoQuery('QRY_LOCATION_SELECT_RAW_REC', array($warehse['LOCATIONREFKEY'], GetMyCompany()));
                    $whseLocationKey = $locinfo[0]['LOCATION_NO'];
                    $indexedLocRecs[$locinfo[0]['RECORDNO']] = $locinfo[0]['LOCATION_NO'];
                }

                if (!isset($locationbasecurrCache[$whseLocationKey])) {
                    $locationbasecurrCache[$whseLocationKey] = GetLocationBaseCurrency($whseLocationKey);
                }

                $atlasWhseBaseCurr = $locationbasecurrCache[$whseLocationKey];

                if (!$this->isDraftDocument($values) && $values['BASECURR'] != $atlasWhseBaseCurr) {
                    $gErr->addIAError('INV-1358', __FILE__ . ":" . __LINE__, null, ['LINENO' => $lineno]);
                    $ok = false;
                }

                // The posting transactions are always in basecurrency of the warehouse location and it has to match the document's base currency.
                if ($this->mod == 'inv') {
                    $values['ENTRIES'][$key]['CURRENCY'] = $atlasWhseBaseCurr;
                    $values['ENTRIES'][$key]['EXCHANGE_RATE'] = 1;
                }
            }

            $values['ENTRIES'][$key]['ITEMTYPE'] = $item['ITEMTYPE'];
            $ok = $ok && $this->validateAdjDocuments($values, $key);

            $ok = $ok && $this->validateAllocation($values, $key);

            $ok = $ok && $this->validateItemCrossReference($values, $key);

            $itemprecision = $itemMgr->_lookUpItemPrecision($item, $mod);

            // defaulting for MEGA entity Context
            /** @noinspection PhpUndefinedVariableInspection */
            $line['LOCATION'] = ( $line['LOCATION'] == '' && $isME && $contextLocation != '' ? $contextLocation : $line['LOCATION']);
            $values['ENTRIES'][$key]['LOCATION'] = $line['LOCATION'];

            $values['ENTRIES'][$key]['PRECISION'] = $itemprecision;

            // round quanity to 4 decmials
            if (is_numeric($values['ENTRIES'][$key]['UIQTY'])) {
                $values['ENTRIES'][$key]['UIQTY'] = iround($values['ENTRIES'][$key]['UIQTY'], 4);
            }

            $values['ENTRIES'][$key]['QUANTITY'] = $values['ENTRIES'][$key]['UIQTY'];
            if (isset($values['ENTRIES'][$key]['MULTIPLIER']) && $values['ENTRIES'][$key]['MULTIPLIER'] !='') {
                /** @noinspection PhpSillyAssignmentInspection */
                $values['ENTRIES'][$key]['MULTIPLIER'] = $values['ENTRIES'][$key]['MULTIPLIER'];
            } else {
                $values['ENTRIES'][$key]['MULTIPLIER'] = 1;
            }

            // Get the line UOM Values for validation and passing it to PricingHandler to get the right converted quantity and value.
            $lineUOMValues = $uomInfoVals[$item['ITEMID']][$line['UNIT']] ?? [];
            if (empty($lineUOMValues) && isset($line['UOMKEY']) && is_numeric($line['UOMKEY'])) {
                // Might it be a record# incoming from the REST API?
                $lineUOMValues = $uomInfoVals['UNIT_RECORDNOS'][$line['UOMKEY']] ?? [];
                if (!empty($lineUOMValues)) {
                    // And if it was, make sure that the UNIT wasn't mistakenly set to the KEY
                    $values['ENTRIES'][$key]['UNIT'] = $lineUOMValues['UNIT'];
                }
            }

            if (!$this->isDraftDocument($values)
                && (!$line['UNIT'] || !isset($lineUOMValues) || count($lineUOMValues) == 0)) {
                $msg = "Please select a valid Unit in line no : $lineno";
                $gErr->addIAError('INV-1359', __FILE__ . ':' . __LINE__, 'Missing Unit', [], $msg, ['LINENO' => $lineno]);
                $ok = false;
            }
            if ($values['_DOCPAR']['SALE_PUR_TRANS'] == 'Purchase') {
                $values['ENTRIES'][$key]['STOCK_NUMBER'] = isset( $vendorStockNoCache[$line['ITEMID']][$line['WAREHOUSE']['LOCATION_NO']]['STOCK_NUMBER'] )
                && $vendorStockNoCache[$line['ITEMID']][$line['WAREHOUSE']['LOCATION_NO']]['STOCK_NUMBER'] != ''
                    ? $vendorStockNoCache[$line['ITEMID']][$line['WAREHOUSE']['LOCATION_NO']]['STOCK_NUMBER']
                    : $vendorStockNoCache[$line['ITEMID']]['STOCK_NUMBER'];
            }

            $priceParams['FROMAPI'] = $this->_fromAPI;
            $values['ENTRIES'][$key] = $pricingHandler->PrepDocPriceLineItems(
                $values,
                $values['ENTRIES'][$key],
                $priceParams,
                $pl_docpar,
                $lineUOMValues
            );

            if ($isWarehouseRequired) {

                if ($isInvModuleSubscribed && is_numeric($values['ENTRIES'][$key]['UIPRICE']) && +$values['ENTRIES'][$key]['UIPRICE'] < 0) {
                    $msg = "Line $lineno : Transaction for item " . $line['ITEMID']
                        . ", has a negative price. " .
                        "Change the price to a non-negative, and try again.";
                    $gErr->addIAError('INV-1300', __FILE__ . ':' . __LINE__, $msg, ['LINENO' => $lineno, 'LINE_ITEMID' => $line['ITEMID']]);
                    $ok = false;
                }
            }

            $ok = $ok && $this->ValidateDiscountMemo($values, $key, $pl_docpar, $item['ITEMID']);

            // When "Enable Override Tax" is On, do *not* use raw item's taxable flag ($item['TAXABLE'])

            if ($enableOverrideTax == 'true') {

                // If SHIPTO contact is not taxable, OVERRIDETAX should be false
                // NOTE: We are skipping this condition check for contract documents in edit mode,
                // because this field is not editable in edit mode, the value provided at the time of creation should persist
                if (!$isContractDoc
                    && $values['ENTRIES'][$key]['OVERRIDETAX'] == 'true'
                    && !$isShipToContactTaxable) {
                    $values['ENTRIES'][$key]['OVERRIDETAX'] = 'false';
                }

                //  Check for the ':use_item_taxable' value, which forces OVERRIDETAX and TAXABLE to have the
                //   same value as the items TAXABLE setting.  It is currently used by the API.
                if (($values['ENTRIES'][$key][':use_item_taxable'] ?? null) === true) {
                    $values['ENTRIES'][$key]['OVERRIDETAX'] = ($item['TAXABLE'] == 'T') ? 'true' : 'false';
                    $values['ENTRIES'][$key]['TAXABLE'] = $item['TAXABLE'];
                } else {
                    $values['ENTRIES'][$key]['TAXABLE'] = ($values['ENTRIES'][$key]['OVERRIDETAX'] == 'true') ? 'T' : 'F';
                }
            } else {
                $values['ENTRIES'][$key]['TAXABLE'] = $item['TAXABLE'];
            }

            $values['ENTRIES'][$key]['EXTENDED_DESCRIPTION'] = $item['EXTENDED_DESCRIPTION'];
            $values['ENTRIES'][$key]['ENABLESNO'] = $item['ENABLESNO'];
            $values['ENTRIES'][$key]['SERIALMASKKEY'] = $item['SERIALMASKKEY'];
            $values['ENTRIES'][$key]['ENABLELOT'] = $item['ENABLELOT'];
            $values['ENTRIES'][$key]['LOTCATKEY'] = $item['LOTCATKEY'];
            $values['ENTRIES'][$key]['ENABLEBIN'] = $item['ENABLEBIN'];
            $values['ENTRIES'][$key]['ENABLEEXPIRATION'] = $item['ENABLEEXPIRATION'];
            $values['ENTRIES'][$key]['ITEMGLGROUP'] = $item['GLGRPKEY'];
            if($item['ITEMTYPE'] == 'SK'){
                $values['ENTRIES'][$key]['SKITEMGLGROUP'] = $item['GLGRPKEY'];
            }
            $values['ENTRIES'][$key]['REVPOSTING'] = $item['REVPOSTING'];
            $values['ENTRIES'][$key]['REVPRINTING'] = $item['REVPRINTING'];
            $values['ENTRIES'][$key]['COGS'] = $item['REVPOSTING'];
            $values['ENTRIES'][$key]['VSOECATEGORY'] = $item['SFW'];
            $values['ENTRIES'][$key]['VSOEDLVRSTATUS'] = $item['VSOEDLVRSTATUS'];
            $values['ENTRIES'][$key]['VSOEREVDEFSTATUS'] = $item['VSOEREVDEFSTATUS'];
            $hasBinEnabledItems = $hasBinEnabledItems || ($item['ENABLEBIN'] == 'T');
            $hasTrackingEnabledItems = $hasTrackingEnabledItems || $item['ISSERIALIZED'];

            if (!empty($item)) {
                $ok = $ok && $this->PopulateItemCostDetails($values, $item, $key);
            }

            // donot assign the warehouse if it is a non inventory item
            if (!$line['WAREHOUSE']['LOCATION_NO'] && !(in_array($item['ITEMTYPE'], $nonInventoryItems))) {
                $values['ENTRIES'][$key]['WAREHOUSE']['LOCATION_NO'] = $values['WAREHOUSE']['LOCATIONID'];
            }

            $departmentId = $line['DEPARTMENTID'] ?? '';
            if ( $departmentId != '' && ( ! isset($line['DEPARTMENT']) || $line['DEPARTMENT'] === '' ) ) {
                $deptIdName = $departmentId . '--' . $indexedDepts[$departmentId]['TITLE'];
                $line['DEPARTMENT'] = $deptIdName;
                $values['ENTRIES'][$key]['DEPARTMENT'] = $deptIdName;
            }
            $locationId = $line['LOCATIONID'] ?? '';
            if ( $locationId != '' && ( ! isset($line['LOCATION']) || $line['LOCATION'] === '' ) ) {
                $locationIdName = $locationId . '--' . $indexedLocs[$locationId]['NAME'];
                $line['LOCATION'] = $locationIdName;
                $values['ENTRIES'][$key]['LOCATION'] = $locationIdName;
            }
            if (isset($line['DEPARTMENT']) && $line['DEPARTMENT'] != '') {

                $dept = explode('--', $line['DEPARTMENT']);
                // Keeping UI path for smart conditions to work correctly
                // Additional values in the array will not harm any thing
                //BEGIN
                $values['ENTRIES'][$key]['DEPARTMENTID'] = $dept[0];
                $values['ENTRIES'][$key]['DEPARTMENTNAME'] = $dept[1];
                //END
                //$deptkey = $deptmapno[$dept[0]];
                /** @noinspection PhpUndefinedVariableInspection */
                $deptkey = $indexedDepts[$dept[0]]['RECORDNO'];
                $values['ENTRIES'][$key]['DEPTKEY'] = $deptkey;
                $values['ENTRIES'][$key]['DEPT#'] = $deptkey;

                if (!$deptkey) {
                    $gErr->addIAError('INV-1360', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'DEPT_0' => $dept[0] ]);
                    $ok = false;
                } /** @noinspection PhpUndefinedVariableInspection */
                elseif ( $mvobjs['oda'] && $mvDeptObjCnt > 0 && !in_array($deptkey, $mvobjs['oda'])) {
                    $gErr->addIAError('INV-1361', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'DEPT_0' => $dept[0] ]);
                    $ok = false;
                }
            // check if the user has department restriction enable -> don't allow saving with empty department
            } elseif (hasHiddenDepartment()){
                $gErr->addIAError('INV-1362', __FILE__ . '.' . __LINE__, null, [ 'LINENO' => $lineno ]);
                $ok = false;
            }

            if (isset($line['LOCATION']) && $line['LOCATION'] !== '') {

                $loc = explode('--', $line['LOCATION']);
                //$lockey = $locmapno[$loc[0]];
                /** @noinspection PhpUndefinedVariableInspection */
                $lockey = $indexedLocs[$loc[0]]['RECORDNO'];
                // Keeping UI path for smart conditions to work correctly
                // Additional values in the array will not harm any thing
                //BEGIN
                $values['ENTRIES'][$key]['LOCATIONID'] = $loc[0];
                $values['ENTRIES'][$key]['LOCATIONNAME'] = $loc[1];
                //END
                $values['ENTRIES'][$key]['LOCATIONKEY'] = $lockey;
                $values['ENTRIES'][$key]['LOCATION#'] = $lockey;

                if (!$lockey) {
                    $gErr->addIAError('INV-1363', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'LOC_0' => $loc[0] ]);
                    $ok = false;
                } /** @noinspection PhpUndefinedVariableInspection */
                elseif ( $mvobjs['ola'] && $mvLocObjCnt > 0 && !in_array($lockey, $mvobjs['ola'])) {
                    $gErr->addIAError('INV-1364', __FILE__ . '.' . __LINE__, null,
                                      [ 'LINENO' => $lineno, 'LOC_0' => $loc[0] ]);
                    $ok = false;
                }

                if ($this->atlas) {

                    $whseLocationKey = $loc[0];
                    if (!isset($locationbasecurrCache[$whseLocationKey])) {
                        $locationbasecurrCache[$whseLocationKey] = GetLocationBaseCurrency($whseLocationKey);
                    }
                    $lbasecurr = $locationbasecurrCache[$whseLocationKey];


                    if (!$this->isDraftDocument($values)
                        && $lbasecurr != $basecurr) {
                        $gErr->addIAError(
                            'INV-1365', __FILE__ . ":" . __LINE__, null, [ 'LINENO' => $lineno ]);
                        $ok = false;
                    }

                    if (!$this->isDraftDocument($values)
                        && ($lbasecurr != $atlasWhseBaseCurr) && $isWarehouseRequired) {
                        $gErr->addIAError('INV-1366', __FILE__ . ":" . __LINE__, null, [ 'LINENO' => $lineno ]);
                        $ok = false;
                    }
                }
            } else {
                if (IsMultiEntityCompany()) {

                    // default the location if empty
                    $this->setDefaultLocation($values['ENTRIES'][$key], 'LOCATIONKEY', false);

                    if (!isset($values['ENTRIES'][$key]['LOCATIONKEY'])
                        || $values['ENTRIES'][$key]['LOCATIONKEY'] == '') {
                        $gErr->addIAError('INV-1377', __FILE__ . '.' . __LINE__);
                        $ok = false;
                    }else{
                        $defaultLocKey = $values['ENTRIES'][$key]['LOCATIONKEY'];
                        if (!isset($defaultLocCache[$defaultLocKey])) {
                            $params = [
                                'selects' => ['LOCATIONID', 'NAME'],
                                'filters' => [[['RECORDNO', '=', $defaultLocKey]]]
                            ];
                            $defaultLocCache[$defaultLocKey] = $locMgr->GetList($params);
                        }
                        $defaultLoc = $defaultLocCache[$defaultLocKey][0] ?? null;
                        if ($defaultLoc) {
                            // Setting this LOCATION field because, in the direct GL posting, we validate this field before posting to GL.
                            $values['ENTRIES'][$key]['LOCATIONID'] = $defaultLoc['LOCATIONID'];
                            $values['ENTRIES'][$key]['LOCATION'] = $defaultLoc['LOCATIONID']."--".$defaultLoc['NAME'];
                        }
                    }
                }
            }

            if ($values['ENTRIES'][$key]['TASKID'] && $values['ENTRIES'][$key]['PROJECTID']) {
                $taskObj = $taskMgr->getTaskKey($values['TASKID'], null, $values['PROJECTID']);
                if ($taskObj) {
                    $values['ENTRIES'][$key]['TASKKEY'] = $taskObj[0]['RECORDNO'];
                }
            }

            if (isset($line['TIMETYPENAME'])) {
                if ($line['TIMETYPENAME'] != '') {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $values['ENTRIES'][$key]['TIMETYPEKEY'] = $timeTypeCache[$line['TIMETYPENAME']]['RECORDNO'];
                } else {
                    $values['ENTRIES'][$key]['TIMETYPEKEY'] = null;
                }
            }

            if (isset($line['EEACCOUNTLABEL'])) {
                if ($line['EEACCOUNTLABEL'] != '') {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $values['ENTRIES'][$key]['EEACCOUNTLABELKEY'] = $eeAcctLabelCache[$line['EEACCOUNTLABEL']]['RECORDNO'];
                } else {
                    $values['ENTRIES'][$key]['EEACCOUNTLABELKEY'] = null;
                }
            }

            // any module specific data preparation for each entry should be done in here
            if (!$this->PrepareModuleData($values['ENTRIES'][$key], $values)) {
                return false;
            }

            // prepare retainage fields
            // First, trx_amountretained is used.  If it is not specified, then
            // RetainagePercentage is used.  If that is not specified, AmountRetained is used.
            if ( $this->getIsRetainageEnabled()) {
                $lineTrxValue = $this->getRetainageLineTrxValue($values, $key);
                $this->recalculateRetainageValues($values, $key);

                // Update the AmountRetained, calculating from EXCHRATE.
                $exchRate = ($values['ENTRIES'][$key]['EXCHRATE'] != '' ? $values['ENTRIES'][$key]['EXCHRATE'] : $values['EXCHRATE']);
                if (
                    (isset($line['RETAINAGEPERCENTAGE']) && !isNullOrBlank($line['RETAINAGEPERCENTAGE'])) ||
                    (isset($line['TRX_AMOUNTRETAINED']) && !isNullOrBlank($line['TRX_AMOUNTRETAINED']))
                ) {
                    $line['AMOUNTRETAINED'] = ibcmul($values['ENTRIES'][$key]['TRX_AMOUNTRETAINED'], $exchRate, 2, true);
                    $values['ENTRIES'][$key]['AMOUNTRETAINED'] = $line['AMOUNTRETAINED'];
                }
                else if (isset($line['AMOUNTRETAINED']) && !isNullOrBlank($line['AMOUNTRETAINED'])) {
                    // No other values were specified, so update TrxAmountRetained and RetainagePercentage from AmountRetained.
                    $line['TRX_AMOUNTRETAINED'] = ibcdiv($line['AMOUNTRETAINED'], $exchRate, 2, true);
                    $values['ENTRIES'][$key]['TRX_AMOUNTRETAINED'] = $line['TRX_AMOUNTRETAINED'];
                    $line['RETAINAGEPERCENTAGE'] = ibcmul(ibcdiv($line['TRX_AMOUNTRETAINED'], $lineTrxValue, 4, true), 100, 2);
                    $values['ENTRIES'][$key]['RETAINAGEPERCENTAGE'] = $line['RETAINAGEPERCENTAGE'];
                }

                if (isset($line['TRX_AMOUNTRETAINED']) && !isNullOrBlank($line['TRX_AMOUNTRETAINED'])) {
                    $line['TRX_AMOUNTRETAINED'] = iround($line['TRX_AMOUNTRETAINED'], 2);
                    $values['ENTRIES'][$key]['TRX_AMOUNTRETAINED'] = $line['TRX_AMOUNTRETAINED'];
                }
            } else {
                $values['ENTRIES'][$key]['TRX_AMOUNTRETAINED'] = $line['TRX_AMOUNTRETAINED'] = '';
                $values['ENTRIES'][$key]['AMOUNTRETAINED'] = $line['AMOUNTRETAINED'] = '';
                $values['ENTRIES'][$key]['RETAINAGEPERCENTAGE'] = $line['RETAINAGEPERCENTAGE'] = '';
            }

            //Validate overridden subtotals if VAT is subscribed
            if ((($values['TXNISVATENABLED'] ?? false) || ($this->isOverrideTaxSchedForEntryEnabled() && $values['OVERRIDETAXSCHED'] === true)) && !empty($line['SUBTOTALSENTRY'])) {
                $subtotalsEntries = array();
                foreach ($line['SUBTOTALSENTRY'] as $linesubtotal) {
                    if (!empty($taxdetailsMap[$linesubtotal['OVERRIDENTAXDETAIL']]) && $linesubtotal['OVERRIDETAXVALUE'] == 'true') {
                        $subtotalEntry['DESCRIPTION'] = $taxdetailsMap[$linesubtotal['OVERRIDENTAXDETAIL']]['DESCRIPTION'];
                        $subtotalEntry['PERCENTVAL'] = $taxdetailsMap[$linesubtotal['OVERRIDENTAXDETAIL']]['PERCENTVAL'];
                        $subtotalEntry['OVERRIDENTAXDETAIL_RECORDNO'] = $taxdetailsMap[$linesubtotal['OVERRIDENTAXDETAIL']]['RECORDNO'];
                        $subtotalEntry['OVERRIDENTAXDETAIL'] = $linesubtotal['OVERRIDENTAXDETAIL'];
                        $subtotalEntry['TAXDETAIL'] = $linesubtotal['TAXDETAIL'];
                        $subtotalEntry['SYSTEMTAXDETAILKEY'] = $linesubtotal['SYSTEMTAXDETAILKEY'];
                        $subtotalEntry['OVERRIDETAXVALUE'] = $linesubtotal['OVERRIDETAXVALUE'];
                        $subtotalEntry['TRX_ABSVAL'] = $linesubtotal['TRX_ABSVAL'];
                        if (!$this->_ismcpEnabled) {
                            $subtotalEntry['ABSVAL'] = $linesubtotal['ABSVAL'];
                        }
                        $subtotalsEntries[] = $subtotalEntry;
                    } else {
                        $subtotalsEntries[] = $linesubtotal;
                    }
                }
                $values['ENTRIES'][$key]['SUBTOTALSENTRY'] = $subtotalsEntries;
                $ok = $ok && $this->validateOverriddenTax($line);
            }
        }

        //Give the LC est adj doc a chance to validate itself
        $ok = $ok && $this->validateEstAdjDocuments($values);

        //move the expanded kit components out of ENTRIES into a new structure so that the rest of other all logic can be handled as normal
        $ok = $ok && $this->CollapseKitItem($values);

        //
        // check if there are any serialized items
        if ($ok) {
            $trackParams['ISNEWDOC'] = ($values['_do'] == 'create');
            $trackParams['TRACKING_HANDLER'] = $handlers['TRACKING_HANDLER'];
            $trackParams['HAS_TRACKING_ENABLED_ITEMS'] = $hasTrackingEnabledItems;
            $trackParams['HAS_BIN_ENABLED_ITEMS'] = $hasBinEnabledItems;

            $ok = $ok && $this->ProcessTrackingInfo($values, $trackParams);
        }

        return $ok;
    }

    /**
     * Override for types that may allow retainage.  Currently PODocumentManager and SODocumentManager.
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
     * Override for types that allow ovverride Conversion type on transaction.
     * @return bool
     */
    public function isOverrideTrnxConversionTypeEnabled()
    {
        return false;
    }

    /**
     * @param array $values
     * @param array $trackParams
     *
     * @return bool
     */
    function ProcessTrackingInfo(&$values, $trackParams){
        $ok = true;
        $state = ($trackParams['ISNEWDOC']) ?  CREATE_ACTION : EDIT_ACTION;
        $trackingHandler = $trackParams['TRACKING_HANDLER'];
        $hasBinEnabledItems = $trackParams['HAS_BIN_ENABLED_ITEMS'];

        if (empty($trackingHandler)) {
            $trackingHandler = new TrackingHandler(array('ACTION' => $state));
        }

        $this->processTrackingRecordsForREST($values['ENTRIES']);

        if ($values['STATE'] == self::DRAFT_STATE) {
            // check if there are any bin tracking enabled items
            // we need to prepare the aisle, row, bin keys from ID's else the data will not be stored
            if ($hasBinEnabledItems) {
                $ok = $ok && $this->PrepBinTrackingForDraft($values, $trackingHandler);
            }

            // returning from here as rest of the processing isn ot required for draft
            return $ok;
        }

        //
        // this prepares the tracing info
        // validate only the basic data validations
        // prepare only if the document affects any of the Inventory Totals (ONHAND, ONORDER, ONHOLD)
        // and affects Quantity or Quantity & Value
        // or if it is draft mode
        $ok = $ok && $trackingHandler->PrepareTrackingInfo($values);

        //
        // this is advance preparation of tracking info
        // validate the business use cases
        // call this only if the document is affecting ONHAND Quantity or Quantity & Value
        if (self::isDocumentInPostingState($values['STATE'])) {
            // Process Tracking information.
            $ok = $ok && $trackingHandler->ProcessTrackingInfo($values);
        }

        return $ok;
    }

    /**
     * @param array $values
     * @param TrackingHandler $trackingHandler
     *
     * @return bool
     */
    function PrepBinTrackingForDraft(&$values, $trackingHandler){
        $ok = true;
        //
        // prepare aisle, row & bin cache
        $trackingHandler->PrepAllWarehouseAislesCache();
        $trackingHandler->PrepAllWarehouseRowsCache();
        $trackingHandler->PrepAllWarehouseBinsCache();

        if (!empty($values['ENTRIES']))
        {
            foreach($values['ENTRIES'] as &$entry)
            {
                $itemWarehouseID = $entry['WAREHOUSE']['LOCATION_NO'];
                $whseAisles      = $trackingHandler->_whaeARBcache[$itemWarehouseID]['AISLES'];
                $whseRows        = $trackingHandler->_whaeARBcache[$itemWarehouseID]['ROWS'];
                $whseBins        = $trackingHandler->_whaeARBcache[$itemWarehouseID]['BINS'];

                if (is_array($entry['TRACKINGENTRIES'])) {
                    foreach ($entry['TRACKINGENTRIES'] as &$trackEntry) {
                        $aisleID = $trackEntry['AISLEID'] ?? '';
                        if ($ok && $aisleID != '' && isset($whseAisles[$aisleID])) {
                            $trackEntry['AISLEKEY'] = $whseAisles[$aisleID]['RECORD#'];
                        }

                        $rowID = $trackEntry['ROWID'] ?? '';
                        if ($ok && $rowID != '' && isset($whseRows[$rowID])) {
                            $trackEntry['ROWKEY'] = $whseRows[$rowID]['RECORD#'];
                        }

                        $binID = $trackEntry['BINID'] ?? '';
                        if ($ok && $binID != '' && isset($whseBins[$binID])) {
                            $trackEntry['BINKEY'] = $whseBins[$binID]['RECORD#'];
                        }
                    }
                }
            }
        }

        return $ok;
    }

    /**
     * Processing the TRACKINGENTRIES for REST if ITEMID is not set check
     * ENTRYITEMID and get value for it.
     * @param [] $entries
     */
    private static function processTrackingRecordsForREST(&$entries)
    {
        foreach ( $entries ?? [] as $line => $entry ) {
            $trackDetails = $entry['TRACKINGENTRIES'] ?? [];
            if (is_array($trackDetails)) {
                for ( $i = count($trackDetails) - 1 ; $i >= 0; --$i ) {
                    if(!isset($trackDetails[$i]['ITEMID']) && isset($trackDetails[$i]['ENTRYITEMID'])){
                        $entries[$line]['TRACKINGENTRIES'][$i]['ITEMID'] = $trackDetails[$i]['ENTRYITEMID'];
                    }
                    else if (!isset($trackDetails[$i]['ITEMID']) && isset($trackDetails[$i]['KITCOMPONENTID'])){
                        $entries[$line]['TRACKINGENTRIES'][$i]['ITEMID'] = $trackDetails[$i]['KITCOMPONENTID'];
                    }
                    if (!isset($trackDetails[$i]['TRACK_QUANTITY'])) {
                        $entries[$line]['TRACKINGENTRIES'][$i]['TRACK_QUANTITY'] = $trackDetails[$i]['QUANTITY'];
                    }
                }
            }
        }
    }

    /**
     * If needed override in subclasses.
     *
     * @param array $entry
     * @param array $values
     *
     * @return true
     */
    function PrepareModuleData(
        /** @noinspection PhpUnusedParameterInspection */ &$entry,
        /** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return true;
    }

    /**
     * @param array $values
     * @param array $item
     * @param int $key
     *
     * @return bool
     */
    function PopulateItemCostDetails(&$values, $item, $key)
    {
        global $gManagerFactory;

        $itemMgr =  $gManagerFactory->getManager('item');

        $qty = $values['ENTRIES'][$key]['QUANTITY'];
        $kitItems = $itemMgr->CollectItemCostDetails($item, $qty, '', true);
        $values['ENTRIES'][$key]['ITEMDETAILS'] = $kitItems;

        return true;
    }


    /**
     * Validate the Discount memo. If needed override in subclasses.
     *
     * @param string[]|string[][]|string[][][] $values
     * @param string $key
     * @param array $pl_docpar
     * @param string $itemID
     *
     * @return bool
     */
    function ValidateDiscountMemo(
        /** @noinspection PhpUnusedParameterInspection */ &$values,
        /** @noinspection PhpUnusedParameterInspection */ $key,
        /** @noinspection PhpUnusedParameterInspection */ $pl_docpar,
        /** @noinspection PhpUnusedParameterInspection */ $itemID)
    {
        return true;
    }

    /**
     * Gather the customer and vendor information from the $values structure.
     *
     * @param  array &$values array of the values of the document.
     * @param  array $docpar docpar values of the document.
     * @param  string $mod module information of the document.
     *
     * @return bool returns if the method execution was success or not.
     */
    function CustVendInformation(&$values, $docpar, $mod)
    {
        $ok = true;
        global $gErr, $gManagerFactory;

        $entity = ($mod == 'so') ? 'customer' : 'vendor';

        $deliverto = '';
        $custvendid = $values['CUSTVENDID'];

        [$custvendid] = explode('--', $custvendid); //splitting the cust/vend id from the values coming from UI

        // we don't need to do any validation unless we have an entity and the transaction defintion doesn't allow the user
        // to overwrite the bill to or ship to contacts
        if ($custvendid != ''
            && ($docpar['ALLOWEDITBILLTO'] == 'F' || $docpar['ALLOWEDITSHIPTO'] == 'F')
        ) {

            if ($mod == 'so') {
                $selects = array('DISPLAYCONTACT.CONTACTNAME', 'DISPLAYCONTACT.VISIBLE', 'SHIPTO.CONTACTNAME', 'BILLTO.CONTACTNAME');
            } else {
                $selects = array('DISPLAYCONTACT.CONTACTNAME', 'DISPLAYCONTACT.VISIBLE', 'RETURNTO.CONTACTNAME', 'PAYTO.CONTACTNAME');
            }

            $qry = array(
                'selects' => $selects,
                'columnaliases' => array('DISPLAYCONTACTNAME', 'VISIBLE', 'SHIPTONAME', 'BILLTONAME'),
                'filters' => array(array(array($mod == 'so' ? 'CUSTOMERID' : 'VENDORID', '=', $custvendid))),
            );
            $cvMgr = $gManagerFactory->getManager($entity);
            $entData = $cvMgr->GetList($qry);

            if (!$entData) {
                $gErr->addIAError(
                    'INV-1367', __FILE__ . ':' . __LINE__,
                    'The ' . $entity . ' with id ' . $values['CUSTVENDID'] . ' is not found.',
                    ['ENTITY' => $entity, 'VALUES_CUSTVENDID' => $values['CUSTVENDID']]
                );
                $ok = false;
            } else {
                $entData = $entData[0];

                $shipto = $entData['SHIPTONAME'];
                if (!$shipto && $entData['VISIBLE'] == 'true') {
                    $shipto = $entData['DISPLAYCONTACTNAME'];
                }

                $billto = $entData['BILLTONAME'];
                if (!$billto && $entData['VISIBLE'] == 'true') {
                    $billto = $entData['DISPLAYCONTACTNAME'];
                }

                if (isset($values['DELIVERTO']['CONTACTNAME'])) {
                    $deliverto = $values['DELIVERTO']['CONTACTNAME'];
                }

                $shipto = isl_htmlspecialchars($shipto);
                $billto = isl_htmlspecialchars($billto);
                $deliverto = isl_htmlspecialchars($deliverto);

                if ($docpar['ALLOWEDITBILLTO'] == 'F') {
                    $billtocontactname = (isset($values['BILLTO']['CONTACTNAME'])) ? isl_htmlspecialchars($values['BILLTO']['CONTACTNAME']) : '';
                    if ((isl_trim($billtocontactname) !== isl_trim($billto)) && isset($values['BILLTO']['CONTACTNAME'])
                        && $values['BILLTO']['CONTACTNAME'] != '') {
                        if ($mod == 'so') {
                            $msg = " Bill to Contact is configured as non-editable in Transaction Definition.You cannot change the Bill to Contact";
                            $errorCode = 'INV-1386';
                        } else {
                            $msg = " Pay to Contact is configured as non-editable in Transaction Definition.You cannot change the Pay to Contact";
                            $errorCode = 'INV-1387';
                        }
                        $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, []);
                        $ok = false;
                    }
                }

                if ($docpar['ALLOWEDITSHIPTO'] == 'F') {
                    $shiptocontactname = isl_htmlspecialchars($values['SHIPTO']['CONTACTNAME']);
                    if ((isl_trim($shiptocontactname) !== isl_trim($shipto)) && $values['SHIPTO']['CONTACTNAME'] != '') {
                        if ($mod == 'so') {
                            $msg = "Ship to Contact is configured as non-editable in Transaction Definition.You cannot change the Ship to Contact";
                            $errorCode = 'INV-1388';
                        } else {
                            $msg = "Return to Contact is configured as non-editable in Transaction Definition.You cannot change the Return to Contact";
                            $errorCode = 'INV-1389';
                        }
                        $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, []);
                        $ok = false;
                    }
                }

                if ($docpar['ALLOWEDITDELIVERTO'] == 'F') {
                    $delivertocontactname = isl_htmlspecialchars($values['DELIVERTO']['CONTACTNAME'] ?? '');
                    if ((isl_trim($delivertocontactname) !== isl_trim($deliverto)) && $values['DELIVERTO']['CONTACTNAME'] != '') {
                        $msg = "Deliver to Contact is configured as non-editable in Transaction Definition. You cannot change the Deliver to Contact";
                        $gErr->addIAError('INV-1306', __FILE__ . ':' . __LINE__, $msg, []);
                        $ok = false;
                    }
                }
            }
        }

        return $ok;
    }


    /**
     * Process the sequence number of the document.
     *
     * @param  array &$values array of the values of the document.
     *
     * @return bool returns if the method execution was success or not.
     */
    function ProcessSequenceNumber(&$values)
    {
        global $gManagerFactory, $gErr;

        $ok = true;

        // Get the next suquence for this type of document
        if (!$values['_DOCPAR']['SEQUENCE'] && $values['_DOCPAR']['ENABLE_SEQNUM'] == 'true') {
            $templateId = $values['_DOCPAR']['DOCID'];
            $gErr->addIAError(
                'INV-1368', __FILE__ . ':' . __LINE__,
                "Numbering Sequence is missing in the transaction definition of $templateId.", ['TEMPLATE_ID' => $templateId]
            );
            $ok = false;
        } else {

            //If it is a backorder, we are not going to get the next sequence but use the parents value
            if ($values['BACKORDER'] == 'Yes') {

                $parentValues = $this->DoQuery('QRY_DOCUMENT_GET_CREATEDFROM_INFO', array($values['CREATEDFROM']));
                $parentValues = $parentValues[0];

                if ($parentValues['BACKORDER'] == 'T') {
                    $lastBOCounter = isl_substr($parentValues['DOCNO'], -1);

                    //if lastcharacter was B, it was the first backorder
                    if ($lastBOCounter == 'B') {
                        $values['DOCNO'] = $parentValues['DOCNO'] . '1';
                    } else {
                        // isolate the numeric suffix, increment it, then replace the entire original suffix
                        $suffixStart = isl_strrpos($parentValues['DOCNO'], 'B') + 1;
                        $lastBOCounter = isl_substr($parentValues['DOCNO'], $suffixStart);
                        $nextCounter = $lastBOCounter + 1;
                        $values['DOCNO'] = isl_substr($parentValues['DOCNO'], 0, $suffixStart) . $nextCounter;
                    }
                } else {
                    $values['DOCNO'] = $parentValues['DOCNO'] . "-B";
                }
            } else if ($values['_DOCPAR']['PRESERVE_SEQNUM'] == 'false') {
                // Generate temporay DOCNO to allow DOCHDR and other dependent records to be created
                $values['DOCNO'] = "Temp " . $values[':record#'];
                //eppp_p("### Temp. DOCNO: " . $values['DOCNO']);

                $this->replaceDOCNO = true;
                $this->postponeSmartRules = true;
                $this->postponeEvents = true;

            } else {
                $seqMgr = $gManagerFactory->getManager('seqnum');
                $values['DOCNO'] = $seqMgr->GetNextSequence($values['_DOCPAR']['SEQUENCE']);

                if ($this->isDocumentNumberDuplicate($values['_DOCPAR']['DOCID'], $values['DOCNO'])) {
                    $docno = $values['DOCNO'];
                    $seq = $values['_DOCPAR']['SEQUENCE'];
                    $gErr->addIAError(
                        'INV-1369', __FILE__ . ':' . __LINE__,
                        "Document Number  '" . $docno . "'  already used", ['DOCNO' => $docno],
                        '', [],
                        "Check sequence  '" . $seq . "'  and try again.", ['SEQ' => $seq]
                    );
                    $ok = false;
                }
            }

            $values['DOCID'] = $values['_DOCPAR']['DOCID'] . "-" . $values['DOCNO'];
            $ok = $ok && isset($values['DOCNO']) && isset($values['DOCID']);
        }
        return $ok;
    }

    /**
     * check if document number is a duplicate one.
     *
     * @param  string $docparid docpar ID of document.
     * @param  string $docno document number.
     *
     * @return bool returns if the method execution was success or not.
     */
    function isDocumentNumberDuplicate($docparid, $docno)
    {
        $qry = 'QRY_DOCUMENT_IS_DOCNUM_DUP';
        $docid = $docparid . "-" . $docno;

        $args = array($docid, $this->_cny);

        $row = $this->DoQuery($qry, $args);
        $dupdocid = $row[0]['DOCID'];
        $ok = isset($dupdocid);

        return $ok;
    }

    /**
     * to get existing values from DB
     *
     * @param array $values current values
     *
     * @return array old values
     */
    protected function getExistingValues(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        if (empty($values['EXISTING_DOC'])) {
            $values['EXISTING_DOC'] = $this->BaseGet($values['DOCID']);

            if (isset($this->_schemas[$this->_entity]['supdocentity'])) {
                GetSupDocId($values['EXISTING_DOC'], $this->_schemas[$this->_entity]['supdocentity']);
            }

            /**
             * @var DocumentEntryManager $lineManager
             */
            $lineManager = $gManagerFactory->getManager(
                $this->mod . 'documententry', false,
                array('DOCTYPE' => $this->_docType)
            );

            // is the upsert switch on?  (we may not be USING upsert, but that is ok)
            $upsertIsEnabled = $this->doesThisCompanyUseUpsert() || $this->isChangeOrderEnabledForTD($values);
            if ($upsertIsEnabled) {// though we may not be DOING a real upsert, still. the flag is on...
                $lineManager->useCacheForDocHdr($values['RECORDNO']);  // do this before getting the existing values
                $docEntryTrackMgr = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
                $docEntryTrackMgr->useCacheForDocHdr($values['RECORDNO']);
            }

            // Getting the existing entries in $values array
            // this will be useful outside documentmanager after upsert logic implemented
            $oldRecNumbers = array();
            $ok = $this->getExistingEntries($lineManager, $values['RECORDNO'], $values, $oldRecNumbers);

            $docparMgr = $this->get_docpar_manager();
            $values['EXISTING_DOC']['_DOCPAR'] = $docparMgr->BaseGet($values['EXISTING_DOC']['DOCPARKEY']);

            if($values['EXISTING_DOC']['_DOCPAR']['SHOW_TOTALS'] == 'true' && $ok) {
                $this->getExistingSubtotals($values);
            }
        }

        return $values['EXISTING_DOC'];
    }

    /**
     * @param OwnedObjectManager $lineManager
     * @param int                $parentKey
     * @param array              $values
     *
     * @return mixed
     */
    protected function getEntriesByParent($lineManager, $parentKey, $values)
    {
        if ( (! self::$upsertFeaturInUse) && (!empty($values['EXISTING_SUBTOTALS'])) &&
            in_array($lineManager->_entity, ['sodocumentsubtotals', 'podocumentsubtotals', 'invdocumentsubtotals'])) {
            return $values['EXISTING_SUBTOTALS'];
        }

        return $lineManager->getByParent($parentKey);
    }

    /**
     * Get existing entries
     *
     * @param OwnedObjectManager &$lineManager line item manager object
     * @param int                $parentKey parent record number
     * @param array              &$values new values
     * @param array              &$oldRecNumbers existing record numbers
     *
     * @return bool
     */
    protected function getExistingEntries(&$lineManager, &$parentKey, &$values, &$oldRecNumbers)
    {
        $ok = true;

        $oldEntries = $this->getEntriesByParent($lineManager, $parentKey, $values);

        $values['EXISTING_ENTRIES'] = [];

        foreach ($oldEntries as $oldEntry) {

            // Keep the list of old recordno
            $oldRecNumbers[$oldEntry['RECORDNO']] = $oldEntry['RECORDNO'];

            // We will keep the old entries data for post processing
            $values['EXISTING_ENTRIES'][$oldEntry['RECORDNO']] = $oldEntry;
        }

        // Get the document tracking records if we are getting the docentry records.
        // not sure why we have to do this, why doesn't the Entity Manager do it?
        if (strpos($lineManager->_entity,'documententry') !== false) {
            $docEntryTrackMgr = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
            $docEntryTrackMgr->getExistingTrackingEntries($values);
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return true
     */
    protected function getExistingSubtotals(&$values)
    {
        $parentKey = $values['RECORDNO'];

        $readFromMaster = (
            IsMultiEntityCompany() &&
            !GetContextLocation() &&
            TaxSolutionManager::TAXMETHOD_I_SIMPLE == GetTaxEngine($this->mod,($values['TAXSOLUTIONID'] ?? ''))
        );
        if ($readFromMaster) {
            $documentsubtotalMgr = Globals::$g->gManagerFactory->getManager('documentsubtotals'); // not SO or PO or INV, just the base class!
            $subtotals = $documentsubtotalMgr->DoQuery('QRY_DOCUMENTSUBTOTALS_SELECT_BY_PARENT_MASTER', array($parentKey));
        } else {
            $subtotals = $this->getDocSubTotalsManager(false)->GetByParent($parentKey);
        }

        $values['EXISTING_SUBTOTALS'] = [];
        if (($subtotals !== false) && !empty($subtotals)) {
            foreach ($subtotals as $oldSubtotal) {
                // We will keep the old entries data for post processing

                //DOCPARSUBTOTALNO
                // need to recheck this
                if ($readFromMaster) {
                    $docentrykey = $oldSubtotal['DOCENTRYKEY'];
                    $lineEntry = $values['EXISTING_ENTRIES'][$docentrykey] ?? [];
                    if (!empty($lineEntry)) {
                        IADimensions::CopyIADimensionValues($lineEntry, $oldSubtotal, !util_isPlatformDisabled());
                    }
                }
                $recordNumber = $oldSubtotal['RECORDNO'] ?? ($oldSubtotal['RECORD#'] ?? 0);  // one of those should be there
                $oldSubtotal['RECORDNO'] = $recordNumber;                                    // normalize
                $values['EXISTING_SUBTOTALS'][$recordNumber] = $oldSubtotal;
            }
        }
        return true;
    }


    /**
     * Clear the old values before processing update. Any transaction on update deletes the existing child records and then creates new child records.
     *
     * @param  array &$values array of the values of the document.
     * @param  array &$oldValues
     * @param  array $handlers
     *
     * @return bool returns if the method execution was success or not.
     */
    function DeleteOldValuesForUpdate(&$values, &$oldValues, $handlers)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ok = true;

        if ( ! self::$upsertFeaturInUse || (self::$upsertPRRecordToo == false)) {
            unset($values['PRRECORDKEY']);
            unset($values['PRINVBATCHKEY']);
            unset($values['ADDGLBATCHKEY']);
            unset($values['INVBATCHKEY']);
        } else if ( ! isset($values['PRRECORDKEY']) || ($values['PRRECORDKEY'] == '')) {
            $values['PRRECORDKEY'] = $oldValues['PRRECORDKEY'];
        }

        $trackingHandler = &$handlers['TRACKING_HANDLER'];
        $isTrackingRequired = IsDocumentSerialized($values['DOCID']);
        if($isTrackingRequired){
            $trackingHandler->PrepParentChildTrackingEntriesMap($values['RECORDNO']);
        }

        $values['_mod'] = self::getMyModID($values['_mod']);

        /**
         * @var DocumentEntryManager $documententryMgr
         */
        $documententryMgr =  $gManagerFactory->getManager($this->mod . 'documententry', false, array( 'DOCTYPE' => $this->_docType));

        if (self::$upsertFeaturInUse) {

            // for any entry that did not change we could skip writing it.
            // unless there's some reason we shouldn't do that....
            if ( ! self::$upsertConservatively) {
                $documententryMgr->didEntriesChange($values, $this);
            }

            // I tried to upsert docentrycost records, but there were a number of defects around it; some I
            // fixed then we decided to back off from these records.  The main issue is that the PHP code
            // tries to find qtyleft but it is in use by the transaction we are updating.  i.e. buy 1 hammer,
            // sell 1 hammer, update the sale: no hammers found!  So, rather than rat-hole on this,
            // I backed off for now.  See code in Costing.cls and CostingHandler.cls and DocumentEntryCostManager
            // for the upsert code, which I left in place for the future for a brave soul to try....
            //
            // [was: But we only need to do this for docentry's that are NOT 'unchanged' (i.e. HAS changed)]
            $ok = $ok && $documententryMgr->deleteDocEntryCostsForChangedRecords($values);
        }

        // getExistingValues is already called and the $values has the oldValues in EXISTING_DOC & EXISTING_ENTRIES
        // need to clean up this code.
        $oldValues = $this->getExistingValues($values);

        // The existing entries already have the mark of being unchanged or not from didEntriesChange(), above
        $oldValues['ENTRIES'] = $values['EXISTING_ENTRIES']; // $documententryMgr->GetByParent($oldValues['RECORDNO']);
        $oldValues['_mod']    = $values['_mod'];
        $oldValues['_do']     = $values['_do'];

        $this->checkIsCreatedFromMultipleSourceDocuments($oldValues, $sourceDockeys);

        // Created User's old values are sent to the database once again when we are
        // updating the database
        $values['CREATEDUSER'] = $oldValues['CREATEDUSER'];

        $ok = $ok && $this->BeforeProcessDeleteForUpdate($values, $oldValues);

        $ok = $ok && $this->ProcessDeleteOrSet($oldValues);

        $ok = $ok && $this->deletePostings($oldValues, DELETE_FOR_UPDATE);

        // This is needed to set prinvbatchkey & addglbatchkey to NULL to avoid duplicate entries in GL.
        // It will be re populated later if requires
        $invBatchMgr = $gManagerFactory->getManager('invbatch');
        $ok = $ok && $invBatchMgr->DoQuery('QRY_DOCUMENT_SET_PRINVBATCHKEY_NULL', array($values['DOCID']));
        $ok = $ok && $invBatchMgr->DoQuery('QRY_DOCUMENT_SET_ADDGLBATCHKEY_NULL', array($values['DOCID']));

        $values['RECORDNO'] = $oldValues['RECORDNO'];
        $values['BACKORDER'] = $oldValues['BACKORDER'];
        $values['INVBATCHKEY'] = $oldValues['INVBATCHKEY'];
        $values['__DELETE_FOR_UPDATE'] = $oldValues['__DELETE_FOR_UPDATE'] ?? '';
        if (isset($oldValues['EXISTING_PRRECORD'])) {
            $values['EXISTING_PRRECORD'] = $oldValues['EXISTING_PRRECORD'];
        }

        return $ok;

    }



    /**
     * Method to create an instance of InvSubtotals
     *
     * @return SCMSubtotals|null
     */
    function getSubtotalsInstance()
    {
        dieFL("getSubtotalsInstance: subclass must override");
        return null;
    }

    /**
     * @param  array $values array of the values of the document in memory that is edited.
     * @param  array $oldValues array of the values of the document in DB.
     *
     * @return bool base class method, so just return true
     */
    protected function BeforeProcessDeleteForUpdate(/** @noinspection PhpUnusedParameterInspection */$values, /** @noinspection PhpUnusedParameterInspection */$oldValues)
    {
        return true;
    }


    /**
     * Process the advanced delete of the document.
     * Delete inventory transaction if any.
     * Update the item costing and totals and quantity information that has reverse effect on deleting a document.
     * Delete the subledger document.
     *
     * @param  array $docObj        array of the values of the document.
     *
     * @return bool returns if the method execution was success or not.
     */
    function ProcessDeleteOrSet(&$docObj)
    {
        $ok = true;
        $upserting = self::$upsertFeaturInUse;

        // If we ARE upserting then the COGSClosedJEEntries will be preserved,
        // as will the DocEntry records that adjustment transactions are linked to
        if ( ! $upserting) {
            $ok = $ok && $this->checkForAdjustmentEntries($docObj);
            $ok = $ok && $this->checkForCOGSClosedJEEntries($docObj);
        }

        // set prrecordkey to null
        if ( ! $upserting || (self::$upsertPRRecordToo == false)) {
            $ok = $ok && $this->DoQuery('QRY_DOCUMENT_UPDATE_PRRECORDKEY_NULL', array($docObj['DOCID']));
            if ($this->entriesHaveAssetNameAndDimKey($docObj)) {
                $ok = $ok && $this->DoQuery('QRY_DOCUMENTENTRY_RESET_ASSET_DIM_KEY', array($docObj['RECORDNO']));
            }
        }

        // Assign the doc par subtotals and totals
        $this->assignDocParTotals($docObj['_DOCPAR'], $docObj['DOCPARKEY']);

        //----------Collect subtotal for this transaction------------
        $documentsubtotalMgr = $this->getDocSubTotalsManager(false);
        $docObj['SUBTOTALS'] = $subtotals = $documentsubtotalMgr->GetByParent($docObj['RECORDNO']);

        /*
         * This change is explicitly to handle the ENDVALUE for each element on $docObj['ENTRIES']
         * We need this only when the transaction affects cost and there are any subtotals.
         *
         * Only Apportioned subtotals do impact the ENDVALUE
         */
        $updatesCost = $docObj['_DOCPAR']['UPDATES_COST'];
        if ($updatesCost && !empty($docObj['SUBTOTALS'])) {
            $this->getSubtotalsInstance()->prepareEndValuesForDelete($docObj);
            $docObj['SUBTOTALS'] = $subtotals;
        }

        // If this is a document created from a recalled document, update the
        // totals of the recalled document and create a backorder if needed.
        $forceConvert = false;
        foreach ($docObj['ENTRIES'] as $entry) {
            if ($entry['ISSUMMARIZED'] == 'true') {
                // If there are entries that are summarized, always convert.
                $forceConvert = true;
            }
        }
        $enableDocChange = isNullOrBlank($docObj["_DOCPAR"]["ENABLEDOCCHANGE"]) ? "No Change" : $docObj["_DOCPAR"]["ENABLEDOCCHANGE"];
        if ($ok && (($docObj['CREATEDFROM'] && $docObj['BACKORDER'] != 'Yes') || $enableDocChange == "Change Order" ||
                    $forceConvert)
        ) {
            $reverse = true;
            //$ok = $this->UpdateRecall( $docObj['CREATEDFROM'], $docObj, $reverse);
            include_once 'ConversionManager.cls';
            $convMgr = new ConversionManager(array('mod' => $this->mod));
            $ok = $ok && $convMgr->ProcessUpdateRecall($docObj, $reverse);
        }

        // Transform the sale_pur_trans to external value to be passed to DeleteDETotals procedure.
        $docparMgr = $this->get_docpar_manager();
        $docObj['SPI'] = $docparMgr->_TransformExternalValue('SALE_PUR_TRANS', $docObj['_DOCPAR']['SALE_PUR_TRANS']);

        // upsert note: this does not appear to actually delete the totals records, and I don't know where they get
        //              recreated, so I'm leaving them as-is for now
        $ok = $ok && DeleteDETotals($docObj);

        $savePRRecord = $upserting && self::$upsertPRRecordToo; // this is when we save the PR record
        if (!$savePRRecord) {
            $prEntryResolveManager = new DePrEntryResolveManager(); // note: this is NOT an EntityManager subclass
            $ok = $ok && $prEntryResolveManager->deleteAllForDocId($docObj['DOCID']);
        }
        return $ok;
    }

    /**
     * Search for Fixed Assets reference in the document.
     *
     * @param  array $docObj        array of the values of the document.
     *
     * @return bool returns if the method found asset references or not.
     */
    protected function entriesHaveAssetNameAndDimKey($docObj)
    {
        $ok = false;
        foreach ($docObj['ENTRIES'] as $entry) {
            if (isArrayValueProvided($entry, 'NAMEOFACQUIREDASSET') &&  isArrayValueProvided($entry, 'ASSETDIMKEY')) {
                $ok = true;
                break;
            }
        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function deleteCOGSGLPosting(&$values)
    {
        $ok = true;

        if ($this->needsCOGSPosting($values)) {
            $subledgerhandler = $this->get_subledger_handler();
            $ok = $subledgerhandler->DeleteInventoryTransaction($values);
        }

        return $ok;
    }

    /**
     * @param array  $values
     * @param string $deleteOrUpdate
     *
     * @return bool
     */
    protected function deleteSubledgerPosting(&$values, $deleteOrUpdate)
    {
        $subledgerhandler = $this->get_subledger_handler();

        $ok = $subledgerhandler->ProcessDeleteOrSet($values);

        if ($ok && $values['PRRECORDKEY']) {
            if (self::$upsertFeaturInUse && ($deleteOrUpdate == DELETE_FOR_UPDATE) && self::$upsertPRRecordToo) {
                Matchmaker::additionalLogging("NOT Deleting Ap/Ar document, but cleaning up...");
                $dsmgr = Globals::$g->gManagerFactory->getManager('documentsubtotals');
                $dsmgr->clearPREntryLinks($values['RECORDNO']);
                $ok = $subledgerhandler->CleanupAPARDocument($values);
            } else {
                if (self::$upsertFeaturInUse) {
                    Matchmaker::additionalLogging("Deleting Ap/Ar document...");
                    $dsmgr = Globals::$g->gManagerFactory->getManager('documentsubtotals');
                    $dsmgr->clearPREntryLinks($values['RECORDNO']);
                }
                $tmp = self::$upsertFeaturInUse;    // in case any smart events cause us to re-enter this code
                self::$upsertFeaturInUse = false;
                $this->ProcessSmartEventForAPAR('Delete', $values);
                self::$upsertFeaturInUse = $tmp;

                $ok = $subledgerhandler->DeleteAPARDocument($values['PRRECORDKEY'], $deleteOrUpdate, $values['DOCNO']);

                if(CRESetupManager::isRetainageBillingEnabled() &&  $this->mod == 'so'){
                    $entries = $values['ENTRIES'] ?? [];
                    $isRetainageRelease = false;
                    foreach ($entries as $entry){
                        if($entry['ISRETAINAGERELEASE'] == "true"){
                            $isRetainageRelease = true;
                            break;
                        }
                    }
                    if($isRetainageRelease){
                        if($deleteOrUpdate == DELETE_FOR_UPDATE){
                            $values['EXISTING_DOC'] = $values;
                            $values['__DELETE_FOR_UPDATE'] = $deleteOrUpdate;
                            $ok = $ok && $this->updateProjectContractTotals($values, true);
                            unset($values['EXISTING_DOC']);
                        }
                        $prKeys = $this->getRetainageBillingInvoiceKeys($values['DOCID']);
                        if(!empty($prKeys)){
                            $ok = $ok && $this->preDeleteRetainageInvoices($prKeys);
                            foreach($prKeys as $key){
                                if($key['RECORDNO'] == $values['PRRECORDKEY']){
                                    continue;
                                }
                                $ok = $ok && $subledgerhandler->DeleteAPARDocument($key['RECORDNO'], $deleteOrUpdate, $values['DOCNO']);
                                if(!$ok){
                                    break;
                                }
                            }
                            $ok = $ok && $this->postDeleteRetainageInvoices($prKeys, $deleteOrUpdate);
                        }
                    }
                }
            }
            if (self::$upsertFeaturInUse) {
                Matchmaker::additionalLogging("Done deleting Ap/Ar document...");
            }

            if ($ok &&  $values['ADDGLBATCHKEY']) {
                // upsert note: upserting the GLBATCH entries is way too hard, so just delete them.
                $ok = $subledgerhandler->DeletePRInvBatch($values);
            }
        } else if ($ok && $values['PRINVBATCHKEY']) {
            // upsert note: upserting the GLBATCH entries is way too hard, so just delete them.
            $ok = $subledgerhandler->DeletePRInvBatch($values);
        }

        return $ok;
    }

    /**
     * @param array  $values
     * @param string $deleteOrUpdate
     *
     * @return bool
     * @throws Exception
     */
    protected function deletePostings(&$values, $deleteOrUpdate)
    {
        $ok = true;
        $systemStates = array(
            self::DRAFT_STATE,
            self::SUBMITTED_STATE,
            self::APPROVED_STATE,
            self::PARTIALLY_APPROVED_STATE,
            self::DECLINED_STATE,
            self::ANALYZING_STATE
        );

        // For a draft document, we do not have subledger posting.
        if (in_array($values['STATE'], $systemStates)) {
            return true;
        }

        // delete cogs posting
        // upsert note: does not appear to delete anything, just prep values
        $ok = $ok && $this->deleteCOGSGLPosting($values);

        if (VendorComplianceSetupManager::isVendorComplianceV2Enabled()) {
            if (isset($values['PRRECORDKEY'])) {
                $unlinkedComplianceRecords = [];

                $ok = $ok && $this->deleteComplianceRecords($values['PRRECORDKEY'], $values['RECORDNO'], $unlinkedComplianceRecords, $deleteOrUpdate);
                $this->_unlinkedComplianceRecords = $unlinkedComplianceRecords;
            }
        }
        
        // delete subledger posting
        $ok = $ok && $this->deleteSubledgerPosting($values, $deleteOrUpdate);

        return $ok;

    }


    /**
     * Process the addiotional create, during the add/set of the document. This is advanced add/set and should handle only additional functionalities like costing, tracking etc.
     * Prepares the advanced line item values.
     * Collect the Average cost, Process Tracking information, Prepare the subtotal values.
     * update the item quantity values. Update the item costing based on the setup.
     * Post to the subledger if the document affects the subledger and/or gl.
     * Update recall information if this document was recalled from another document.
     *
     * @param  array &$values values of the document passed as reference.
     * @param  array $otherParams
     *
     * @return bool $ok returns if the method execution was success or not.
     */
    protected function Post(&$values, $otherParams)
    {
        $ok = true;

        $ok = $ok && $this->postCostingEntries($values);

        $ok = $ok && $this->postCOGSGLPosting($values);

        $ok = $ok && $this->postToSubLedger($values);

        $ok = $ok && $this->get_subledger_handler()->flushGLResolveMAP();

        $ok = $ok && $this->updateItemPrice($values);

        $ok = $ok && UpsertDETotals($values);

        $postedValues = $otherParams['POSTEDVALUES'];
        $ok = $ok && $this->postMacro($postedValues, $values);

        $getTaxRequest = $otherParams['TAX_REQUEST'];
        $entityTaxable = $otherParams['ENTITY_TAXABLE'];
        $ok = $ok && $this->postToAvalara($values, $getTaxRequest, $entityTaxable);

        if (VendorComplianceSetupManager::isVendorComplianceV2Enabled()) {
            if (is_array($this->_unlinkedComplianceRecords) && isNonEmptyArray($this->_unlinkedComplianceRecords)) {
                $ok = $ok && $this->updateVoidedComplianceRecords($values, $this->_unlinkedComplianceRecords);
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function updateItemPrice(&$values)
    {
        $pricingHandler = $this->get_pricing_handler();
        $ok = $pricingHandler->UpdateItemPrice($values);    // this will invalidate any caches too

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function postCOGSGLPosting(&$values)
    {
        $ok = true;

        if ($this->needsCOGSPosting($values)) {
            $subledgerhandler = $this->get_subledger_handler();
            $ok = $subledgerhandler->ProcessInventoryTransaction($values, $this->_prglLineFromTD, $this->_revenueAccts);
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function needsCOGSPosting($values)
    {
        $updatesInv = $values['_DOCPAR']['UPDATES_INV'];
        $affectsInventory = array('Value', 'Quantity and Value');

        return in_array($updatesInv, $affectsInventory);
    }

    /**
     * @return bool
     */
    public function isIETOnCOGSRequired()
    {
        return false;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function postCostingEntries(&$values)
    {
        $costingHandler = $this->get_costing_handler();

        $ok =  $costingHandler->PostCostingEntries($values);

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function processConvert(&$values)
    {
        $ok = true;
        $enableDocChange = (!isset($values["_DOCPAR"]["ENABLEDOCCHANGE"]) || isNullOrBlank($values["_DOCPAR"]["ENABLEDOCCHANGE"])) ? "No Change" : $values["_DOCPAR"]["ENABLEDOCCHANGE"];
        $convMgr = null;
        // If this is a document created from a recalled (has a source document) document,
        // update the totals of the recalled document and create a backorder if needed.
        $doProcessUpdateRecall = ($values['CREATEDFROM'] && $values['BACKORDER'] != 'Yes') || $enableDocChange == "Change Order";
        if (!$doProcessUpdateRecall) {
            // see if any entries were summarized.  If so, we need to update the source documents
            foreach ($values['ENTRIES'] ?? [] as $entry) {
                if (isset($entry['ISSUMMARIZED']) && $entry['ISSUMMARIZED'] == 'true') {
                    $doProcessUpdateRecall = true;
                    break;
                }
            }
        }
        if ($doProcessUpdateRecall) {
            $convMgr = new ConversionManager(array('mod' => $this->mod, '_warningValidation' => $this->_warningValidation));
            $ok = $ok && $convMgr->ProcessUpdateRecall($values);
        }
        if (isNonEmptyArray($values['SUMMARIZEDENTRIES_TOCONVERT']) &&
            isNonEmptyArray($values['SUMMARIZEDENTRIES_TOCONVERT']['ENTRIES'])
        ) {
            if (!isset($convMgr)) {
                $convMgr = new ConversionManager(array('mod' => $this->mod, '_warningValidation' => $this->_warningValidation));
            }
            $ok = $ok && $convMgr->ProcessUpdateRecall($values['SUMMARIZEDENTRIES_TOCONVERT']);
        }

        return $ok;
    }

    /**
     * To clear the static object instances for the given handler objects. When called destroys the handler object instances from the ManagerFactory pool of instances.
     *
     * @param array  $handlers Array of object handler names
     */
    function purgeObjectHandlers($handlers)
    {
        foreach ($handlers ?? [] as $handler) {
            Globals::$g->gManagerFactory->_getObjectInstance($handler, true);
        }
    }


    /**
     * To get the document params manager object. When called return a documentparameters manager object instance from the ManagerFactory pool of instances.
     *
     * @return DocumentParamsManager|true instance of DocumentParamsManager.
     */
    function get_docpar_manager()
    {
        //global $gManagerFactory;
        //return $gManagerFactory->GetManager('documentparams');
        // Ideally this method should be instantiated by the sub classes to return the module specific documentparams object. So implementing dummy here.
        if (!isset($this->mod)) {
            global $gManagerFactory;
            return $gManagerFactory->getManager('documentparams');
        }
        return true;
    }

    /**
     * @param string $docparid
     *
     * @return bool
     */
    public function IsDocParApprovalEnabled(/** @noinspection PhpUnusedParameterInspection */ $docparid) {
        return false;
    }

    /**
     * To get the document subscriptions wizard manager object.
     *
     * @return DocumentParamsManager|true instance of SubscriptionsWizManager.
     */
    function get_subscriptionwiz_manager()
    {
        //global $gManagerFactory;
        //return $gManagerFactory->GetManager('documentparams');
        // Ideally this method should be instantiated by the sub classes to return the module specific documentparams object. So implementing dummy here.
        if (!isset($this->mod)) {
            global $gManagerFactory;
            return $gManagerFactory->getManager('documentparams');
        }
        return true;
    }


    /**
     * @return DocumentEventManager|object
     */
    function get_event_manager()
    {
        // PhpStorm's metadata overrides doesn't work with defined constants  :(
        return Globals::$g->gManagerFactory->_getObjectInstance('DocumentEventManager');
    }


    /**
     * @return false|DocumentApprovalManager
     */
    function get_documentapproval_manager()
    {
        // sub classes to implement this.
        return false;
    }


    /**
     * @return array
     */
    function get_workflow()
    {
        include DOCUMENT_WORKFLOW_FILE;

        /** @noinspection PhpUndefinedVariableInspection */
        return $kDocumentWorkflow['document'];
    }



    /**
     * To get the pricing handler object. When called return a pricing handler object instance from the ManagerFactory pool of instances.
     *
     * @return object|PricingHandler
     */
    function get_pricing_handler()
    {
        // PhpStorm's metadata overrides doesn't work with defined constants  :(
        $ph = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
        if (self::$upsertFeaturInUse) {
            $ph->CacheQueries(true);    // large transactions can call the price handler a LOT.
        }
        return $ph;
    }

    /**
     * To get the costing handler object. When called return a costing handler object instance from the ManagerFactory pool of instances.
     *
     * @return CostingHandler|object
     */
    function get_costing_handler()
    {
        // PhpStorm's metadata overrides doesn't work with defined constants  :(
        return Globals::$g->gManagerFactory->_getObjectInstance('CostingHandler');
    }

    /**
     * To get the subledger handler object. When called return a subledger handler object instance from the ManagerFactory pool of instances.
     *
     * @return object|SCMSubledgerHandler
     */
    function get_subledger_handler()
    {
        // PhpStorm's metadata overrides doesn't work with defined constants  :(
        return Globals::$g->gManagerFactory->_getObjectInstance('SCMSubledgerHandler');
    }

    /**
     * To get the document blobstore handler object. When called return a document blobstore handler object instance from the ManagerFactory pool of instances.
     *
     * @return DocumentBlobStoreHandler|object
     */
    function get_docblobstore_handler()
    {
        // PhpStorm's metadata overrides doesn't work with defined constants  :(
        return Globals::$g->gManagerFactory->_getObjectInstance('DocumentBlobStoreHandler');
    }


    /**
     *  To be implemented by sub class that inherits the document manager.
     * @param array  $values
     * @param array  $getTaxRequest
     * @param string $entityTaxable
     *
     * @return bool
     */
    function PrepareSubTotalsValues(
        /** @noinspection PhpUnusedParameterInspection */ &$values,
        /** @noinspection PhpUnusedParameterInspection */ &$getTaxRequest=null,
        /** @noinspection PhpUnusedParameterInspection */ &$entityTaxable=null)
    {
        return true;
    }


    /**
     * To be implemented by sub class that inherits the document manager.
     *
     * @param array $values
     *
     * @return bool
     */
    function CreateDocentrySubtotals(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        return true;
    }

    /**
     * To be implemented by sub class that inherits the document manager.
     *
     * @param array $docObj
     *
     * @return bool
     */
    function showSubTotals(/** @noinspection PhpUnusedParameterInspection */ &$docObj)
    {
        return true;
    }


    /**
     * Handles Revenue Deferment
     *
     * @param array $matureValues
     * @param array $docvalues
     *
     * @return bool
     */
    public function PreprocessInvoice(
        /** @noinspection PhpUnusedParameterInspection */ &$matureValues, &$docvalues)
    {
        return true;
    }

    /**
     * Handles allocation splits
     *
     * @param array $values
     *
     * @return bool
     */
    public function applyAllocationForGet(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return true;
    }

    /**
     * Post the values to subledger based of the module preferences as well the document params [docpar or Transaction Definition] preferences.
     *
     * @param  array &$values values of the document.
     * @return bool returns if the method execution was success or not.
     */
    protected function postToSubLedger(&$values)
    {
        // no posting for back order
        if ($values['BACKORDER'] == 'Yes') {
            return true;
        }

        $ok = true;

        $updatesGL = $values['_DOCPAR']['UPDATES_GL'];

        $subledgerhandler = $this->get_subledger_handler();

        switch ($updatesGL) {
            //	Create the AP/AR Transaction, if applicable
            case 'A' :
                $ok = $subledgerhandler->ProcessAPARDocument(
                    $this,
                    $values,
                    $this->customFields,
                    $this->_prglLineFromTD,
                    $this->_revenueAccts,
                    $this->_taxLines,
                    $this->_getSubTotalsResult,
                    $this->_contactTaxGrpKey,
                    $this->_simpletaxLines
                );

                $ok = $ok && $this->PreprocessAdditionalGLPosting($values);
                break;

            case 'G' :
                $ok = $subledgerhandler->CreatePRInvBatch(
                    $this,
                    $values,
                    $this->_prglLineFromTD,
                    $this->_revenueAccts
                );
                break;
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function PreprocessAdditionalGLPosting(
        /** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        return true;
    }

    /**
     * @param array $glentries
     * @param array $docvalues
     *
     * @return bool
     */
    function PreprocessDirectGLPosting(
        /** @noinspection PhpUnusedParameterInspection */ &$glentries,
        /** @noinspection PhpUnusedParameterInspection */ &$docvalues)
    {
        return true;
    }

    /**
     * Merge the expanded kit components into the original ENTRIES array and replace the kit
     *
     * @param string[]|string[][]|string[][][] $values
     *
     */
    function MergeAndReplaceKit(&$values)
    {
        $printEntries = array();

        $childIndex = 0;

        foreach ((($values['ENTRIES']) ?? []) as $key => $entry) {
            if ($entry['ITEMTYPE'] == 'K' && $entry['REVPRINTING'] == 'I') {
                for (; $childIndex < count($values['PRINTFORMATENTRIES']); $childIndex++) {
                    //its my parent, replace
                    if ($values['PRINTFORMATENTRIES'][$childIndex]['PARENTENTRY'] == $key) {
                        $printEntries[] = $values['PRINTFORMATENTRIES'][$childIndex];
                    } else {
                        break;
                    }
                }
            } else {
                $printEntries[] = $entry;
            }
        }

        $values['ENTRIES'] = $printEntries;
    }

    /**
     * @param array $values
     * @param array $otherParams
     *
     * @return bool
     */
    protected function PostProcessDocument(&$values, $otherParams = [])
    {
        $ok = true;
        $isUpdate = $otherParams['ISUPDATE'];

        if ($isUpdate && ! self::$upsertFeaturInUse) {
            // remove the little 'glue' records for docentry and subtotals
            $ok = $ok && $this->DoQuery('QRY_DOCENTRYSUBTOTALS_DELETE', array($values['RECORDNO']));
        }

        // create document entry subtotals
        if (isset($values['SUBTOTALS'])) {
            $ok = $ok && $this->CreateDocentrySubtotals($values);
            $mgr = $this->getDocSubTotalsManager(false);
            $mgr->updateDocentrySubtotals($values['ENTRIES'], $values['SUBTOTALS']);
        }

        // set the supporting document ID
        $ok = $ok && SetSupDocId($values, $this->_schemas[$this->_entity]['supdocentity']);

        // required only when Creating / Add
        // Fire postponed smart rules now
        if (!$isUpdate) {

            // Process dochistory based on whether its recalled or not.
            $ok = $ok && ProcessDocHistory($values);

            if ($values['_DOCPAR']['PRESERVE_SEQNUM'] == 'false' && $this->replaceDOCNO) {
                $ok = $ok && $this->GenerateAndReplaceDOCNO($values);
            }

            if ($ok && $this->postponeSmartRules) {
                $this->postponeSmartRules = false;
                $ok = $ok && $this->smartlinkValidate([ 'add', 'addset' ], $values);
            }

            if ($ok && $this->postponeEvents) {
                $this->postponeEvents = false;
                $this->DoEvent('Add', $this->GetKeyValue($values), false);
            }
        } else {

            // This required for update the dochistory for pomatch change source source document
            // This we need to handle for update document
            $ok = $ok && $this->processDocHistoryForUpdate($values);

            $oldValues = $otherParams['OLDVALUES'];
            // required only when updating the documet
            // clean up the document template/transaction definition version
            $docparMgr = $this->get_docpar_manager();
            $ok = $ok && $docparMgr->CleanupTemplateVersion($oldValues['_DOCPAR']);
        }

        $ok = $ok && $this->processConvert($values);

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function processDocHistoryForUpdate($values)
    {
        $ok = true;

        // Currently we are supporting only for PO match document on change source option
        if (!$this->getIsSourceDocumentChanged()) {
            return true;
        }

        // For now we are not handling changing of multiple source document
        if ($values['CREATEDFROM'] == ConversionManager::getmultipleSourceDocsText()) {
            return true;
        }

        $oldsrcDockey = $values['EXISTING_DOC']['SOURCEDOCKEY'] ?? '';
        $newsrcDockey = $values[':createdfrom'] ?? '';

        $docHistoryMrg = Globals::$g->gManagerFactory->getManager('dochistory');

        // update => Dockey remain same, sourcedockey => change to new source dockey, basedockey => change to sourcekey of basedockey
        $ok = $ok && $docHistoryMrg->updateOnChangeOfSourceDocument(
                $values['RECORDNO'],
                $newsrcDockey,
                $oldsrcDockey
            );

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function CreateDocumentPDF($values)
    {
        $ok = true;

        unset($values['EXISTING_ENTRIES']);
        unset($values['EXISTING_DOC']);
        unset($values['EXISTING_SUBTOTALS']);
        unset($values['SOURCEDOCPARDETAIL']);
        unset($values['SOURCEDOCDETAIL']);
        unset($values['SYSTEMTAXDETAILMAP']);

        foreach ($values['ENTRIES'] as $key=>$entry ){
            unset($values['ENTRIES'][$key]['EXISTING_ENTRIES']);
            unset($values['ENTRIES'][$key]['EXISTING_TRACKINGENTRIES']);
            unset($values['ENTRIES'][$key]['UPSERT_EXISTING']);
            if (!empty($values['ENTRIES'][$key]['ITEMUOM'])) {
                $values['ENTRIES'][$key]['ITEMUOM'] = array_values($values['ENTRIES'][$key]['ITEMUOM']);
            }
        }


        //Append description 'SUBTOTAL' and 'TOTAL' as the first and last element in subtotals
        //array before storing it in blob
        $docBlobStoreMgr = $this->get_docblobstore_handler();

        //merge the expanded kit for printing if necessary
        if ($values['PRINTFORMATENTRIES']) {
            $this->MergeAndReplaceKit($values);
        }

        $benchmark = Globals::$g->gIABenchmark;
        $benchmark->startTimer('SaveXMLDataAsBlob', $this, $docBlobStoreMgr);
        $ok = $ok && $docBlobStoreMgr->SaveXMLDataAsBlob($values, $this->mod, $this->IsOwnedEntity());
        $benchmark->stopTimer();

        return $ok;
    }

    /**
     * Overriden function from parent class
     * Process a record for update
     *
     * @param string[]|string[][]|string[][][] $values         array of fields
     * @param bool                             $transformPaths true/false
     * @param array                            $transformed
     *
     * @return string[]|string[][]|string[][][] $internalStructure processed values array
     */
    function _PreProcessForUpdate($values, $transformPaths = false, &$transformed = null)
    {
        unset($values['EXISTING_ENTRIES']);
        unset($values['EXISTING_DOC']);
        unset($values['SCMMACROLINK']);
        if (!empty($this->macroFields)) {
            unset($values[$this->macroFields[0]['path']]);
        }

        $internalStructure = parent::_PreProcessForUpdate($values, $transformPaths, $transformed);

        return $internalStructure;
    }

    /**
     * @param array  $values
     *
     * @return bool
     * @throws Exception
     */
    protected function GenerateAndReplaceDOCNO(& $values)
    {
        $source = "DocumentManager::GenerateAndReplaceDOCNO";
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok =true;

        // Generate real DOCNO in a non-blocking manner
        // Overwrite temp. DOCNO and DOCID generated in previous steps
        $seqMgr = $gManagerFactory->getManager('seqnum');

        //eppp_p("### Getting nextval for " . $values['_DOCPAR']['SEQUENCE']);
        $newDocNo = $seqMgr->GetNextSequenceNonBlocking($values['_DOCPAR']['SEQUENCE']);

        //eppp_p("### newDocNo: " . $newDocNo);

        if (!$newDocNo) {
            return false;
        }

        if ($this->isDocumentNumberDuplicate($values['_DOCPAR']['DOCID'], $newDocNo)) {
            $seq = $values['_DOCPAR']['SEQUENCE'];
            $gErr->addIAError(
                'INV-1370', __FILE__ . ':' . __LINE__,
                "Document Number  '" . $newDocNo . "'  already used", ['DOCNO' => $newDocNo],
                '', [],
                "Check sequence  '" . $seq . "'  and try again.", ['SEQ' => $seq]

            );
            $ok = false;
        }

        // Overwrite temp. DOCNO and DOCID values in in-memory datastructure
        $values['DOCNO'] = $newDocNo;
        $values['DOCID'] = $values['_DOCPAR']['DOCID'] . "-" . $values['DOCNO'];
        //eppp_p("values['DOCID']: " . $values['DOCID']);

        // Correct DOCHDRID attribute in each row
        $entries = & $values['ENTRIES'];
        for ($i = 0; $i < count($entries); $i++) {
            $entries[$i]['DOCHDRID'] = $values['DOCID'];
        }

        // Overwrite temp. DOCNO and DOCID values in DOCHDR table
        $ok = $ok && $this->_QM->beginTrx($source);

        // Disable UPD_DOCHDR_ENTITY and ARIU_DOCHDR triggers on DOCHDR table
        // we do not want modified date to be set while we are updating correct DOCNO
        $ok = $ok && ExecSimpleStmt("BEGIN acct_Utils. Trigger_Enabled := 'F'; END;");
        //eppp_p("### Trigger_Enabled := 'F' ok: " . $ok);

        $ok = $ok && ExecStmt(
                array("UPDATE dochdrmst SET docno = :1, DOCID = :2 WHERE record# = :3 AND cny# = :4 ",
                    $values['DOCNO'], $values['DOCID'], $values['RECORDNO'], GetMyCompany())
            );
        //eppp_p("### dochdr SET docno = :1, DOCID = :2 ok: " . $ok);

        $ok = $ok && ExecSimpleStmt("BEGIN acct_Utils. Trigger_Enabled := 'T'; END;");
        //eppp_p("### Trigger_Enabled := 'T' ok: " . $ok);


        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Problem retrieving next document sequence number";
            $gErr->addIAError('INV-1307', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * Check if the transaction is deletable.
     * Lookup docpar to check for the edit permissions for the user.
     * If the docpar affects quantity, then check for the quantity totals.
     *
     * @param array $docObj      values of the document.
     * @param bool  $forceDelete ignore delete policy in transaction definition
     * @param bool $checkNegInventory true if we want to check for negative inventory before we can delete
     *
     * @return bool $ok returns if the method execution was success or not.
     */
    function _IsTransactionDeletable($docObj, $forceDelete, $checkNegInventory)
    {
        global $gErr, $gManagerFactory;
        $ok = true;

        $docparid = $docObj['DOCPARID'];

        $ok = $ok && $this->IsTranAllowedforUser($docObj, $docObj['BACKORDER']);

        if ($docObj['STATE'] == self::CONVERTED_STATE || $docObj['STATE'] == self::CONVERTED_BY_LINE_STATE) {
            $msg = 'Transaction ' . $docObj['DOCID'] . ' is converted. Cannot delete converted transactions.';
            $gErr->addIAError(
                'INV-1371', __FILE__ . ':' . __LINE__,
                'Error deleting ' . $docparid, ['DOCPARID' => $docparid],
                $msg, ['DOC_OBJ_DOCID' => $docObj['DOCID']],
                'Invalid Operation', []
            );
            $ok = false;
        }

        $docparMgr = $this->get_docpar_manager();
        $ret = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_GET_EDITDEL_POLICY', array($docparid));
        self::checkForAdditionalPolicy($ret);
        $type = $ret[0]['DELTYPE'];

        if (
            !$forceDelete
            && ( $type == 'N'
                || ( $type == 'D' && $docObj['STATE'] != self::DRAFT_STATE )
            )
        ) {
            $msg = 'The Delete Policy for ' . $docparid . ' does not allow deleting.';
            $gErr->addIAError(
                'INV-1372', __FILE__ . ':' . __LINE__,
                'Error deleting ' . $docparid, ['DOCPARID' => $docparid],
                $msg, ['DOCPARID' => $docparid],
                'Please contact the administrator.', []
            );
            $ok = false;
        }

        if ($type == 'P' && $docObj['PRINTED'] == 'Yes') {
            $msg = 'The Delete Policy for ' . $docparid . ' does not allow deleting printed documents.';
            $gErr->addIAError(
                'INV-1373', __FILE__ . ':' . __LINE__,
                'Error deleting ' . $docObj['DOCID'], ['DOCPARID' => $docObj['DOCID']],
                $msg, ['DOCPARID' => $docparid],
                'Please contact the administrator.', []
            );
            $ok = false;
        }

        // if the items in this document are enabled for serial/lot tracking then
        // check that there are no documents which refer to this.
        $affects_OnHandQty = false;

        if ($ok) {
            //if in TD , totals are affeacting ONHAND qty then
            foreach ( $docObj['_DOCPAR']['DOCPAR_TOTALS'] ?? [] as $val) {
                if ($val['TOTALID'] == 'ONHAND' && ($val['Q_QV'] == 'Quantity' || $val['Q_QV'] == 'Quantity & Value')) {
                    $affects_OnHandQty = true;
                }
            }
        }

        if ($ok && $affects_OnHandQty && ( ! empty($docObj['ENTRIES']))) {
            // preparing unique items list
            $itemMgr = $gManagerFactory->getManager('item');
            $itemsArr = array();
            foreach ($docObj['ENTRIES'] as $entry) {
                $itemid = $entry['ITEMID'];
                if (!in_array($itemid, $itemsArr, true)) {
                    $itemsArr[] = $itemid;
                }
            }

            $itemRawCache = $itemMgr->GetItemsRawCache($itemsArr);

            $itemsList = array();
            foreach ($docObj['ENTRIES'] as $entry) {
                if (!in_array($entry['ITEMID'], $itemsList, true)) {
                    $itemSerialized = $itemRawCache[$entry['ITEMID']]['ISSERIALIZED'];
                    if ($itemSerialized) {
                        $itemsList[] = $entry['ITEMID'];
                    }
                }
            }

            // if negative inventory is NOT allowed, we handle that below, but here we do this
            //    if negative inventory IS allowed.  Eventually, we'd like to be more fine-grained
            //    because, for example, if a sale refers to this purchase but there are other purchases
            //    that could handle it, that should be ok.
            if (!empty($itemsList) && IsNegativeInventoryAllowed()) {

                //Prepare the inner statement with the IN Clause for the items.
                $outerStmt = array();
                $outerStmt[0] = " SELECT documententrycost.record#
								FROM docentrycost documententrycost, docentry, dochdr
							   WHERE documententrycost.cny# = docentry.cny#(+)
								 AND documententrycost.docentrykey = docentry.record#(+)
								 AND docentry.cny# = dochdr.cny#(+)
								 AND docentry.dochdrkey = dochdr.record#(+)
								 AND dochdr.docid = :2
								 AND documententrycost.qtyleft != documententrycost.quantity
								 AND documententrycost.cny#(+) = :1 ";

                // The following two values are dummy, but essential to form the IN Clause properly.
                $outerStmt[1] = GetMyCompany();
                $outerStmt[2] = $docObj['DOCID'];
                $outerStmt = PrepINClauseStmt($outerStmt, $itemsList, " and documententrycost.itemkey ");

                //Prepare the outer statement with the values appended from the inner query
                $outerStmt[0] = " SELECT COUNT (1) count
								  FROM docentrycost
								 WHERE cny# = :1
								   AND docentrycostkey IN ( $outerStmt[0] ) ";

                $childCount = QueryResult($outerStmt);
                $childCount = $childCount[0];

                if ($childCount['COUNT'] > 0) {
                    $ok = false;
                    $msg = "This Document has item(s) enabled for Serial/Lot/Bin tracking which are referenced by other document(s)";
                    $gErr->addIAError(
                        'INV-1374', __FILE__ . ':' . __LINE__,
                        'Error deleting ' . $docObj['DOCID'], ['DOCPARID' => $docObj['DOCID']],
                        $msg, []
                    );
                }
            }

            if ($forceDelete === false || $checkNegInventory === true) {
                // forceDelete is true when we really really really want to delete this record.
                // 'normal' deletes from the UI pass in 'false', so we can do this check....
                //Client like WH transfer want to force delete but also want to check for negative inventory, so pass in true for $checkNegInventory
                $ok = $ok && $this->checkForNegativeInventory($docObj, 'D', true);
            }
        }

        return $ok;
    }


    /**
     * This function needs to be overridden by the child classes.
     * This function is used to check if the Customer/Vendor is required.
     *
     * @param  string[]|string[][]|string[][][] $docpar has values to check if cust/vendor is required
     * @return true
     */
    function IsCustVendRequired(/** @noinspection PhpUnusedParameterInspection */ $docpar)
    {
        return true;
    }

    /**
     * @param array   $values
     * @param string $action
     *
     * @return bool
     */
    function IsTranAllowedforUser($values = [], /** @noinspection PhpUnusedParameterInspection */ $action = "")
    {
        $docClass = $values['_DOCPAR']['DOCCLASS'];
        $userType = GetMyUserType();
        if ($docClass == null) {
            $dt = Request::$r->_dt;
            if ($dt != '') {
                $res = QueryResult(array("SELECT docclass FROM docpar WHERE docid = :1 and status = 'T' and latestversionkey is null and cny# = :2 ", $dt, GetMyCompany()));
                $values['_DOCPAR']['DOCCLASS'] = $res[0]['DOCCLASS'];
            }
        }

        $ok = $this->validateUserAndDocClass($userType, $values);

        return $ok;
        }


    /**
     * Partial Set of the document. This is to set the state of the document and based on the event call the DoEvent
     *
     * @param  string[]|string[][]|string[][][] $obj array of the values of the document.
     *
     * @return bool returns if the method execution was success or not.
     */
    function PartialSet($obj)
    {
        $source = "DocumentManager::Set";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $docid = $obj['DOCID'];
        $state = $obj['STATE'];

        $info =& $this->GetFieldInfo('STATE');
        $values = array_flip($info['type']['validvalues']);
        $ivalues = $info['type']['_validivalues'];

        $index = $values[$state];
        $val = $ivalues[$index];

        $ok = $ok && $this->DoQuery('QRY_DOCUMENT_SETSTATE', array($val, $docid));

        $hasChange = $obj['HASCHANGE'] ?? 'false';
        $hasChangeInfo = &$this->GetFieldInfo('HASCHANGE');
        $hasChangeValues = array_flip($hasChangeInfo['type']['validvalues']);
        $hasChangeIvalues = $hasChangeInfo['type']['_validivalues'];

        $hasChangeIndex = $hasChangeValues[$hasChange];
        $hasChangeVal = $hasChangeIvalues[$hasChangeIndex];
        $ok = $ok && $this->DoQuery('QRY_DOCUMENT_SETHASCHANGE', array($hasChangeVal, $docid));

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not Set Document record!";
            $gErr->addIAError('INV-1308', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        } else {
            // call the DoEvent with update
            $this->DoEvent('Set', $this->GetKeyValue($obj), false);
        }
        return $ok;
    }


    /**
     * @param null|string[] $types
     * @param bool $showInactive
     *
     * @return bool
     */
    function LoadSmartlinks($types = null, $showInactive = false)
    {
        if ($types == null) {
            $types = self::$defaultLinkTypes;
        }

        $typesNotLoaded = [];
        $showInactiveStr = $showInactive ? 'T' : 'F';
        foreach ($types as $type) {
            if (!isset($this->loadedSmartLinkTypes[$type][$showInactiveStr])) {
                $typesNotLoaded[] = $type;
                $this->loadedSmartLinkTypes[$type][$showInactiveStr] = true;
            }
        }

        if (empty($typesNotLoaded)) {
            return true;
        }

        //$keyfield = Request::PathToFieldName($this->_schemas[$this->_entity]['vid']);
        $keyfield = $this->_schemas[$this->_entity]['vid'];

        $qry = "select sl.RECORD#, sl.SMARTLINKID, sl.TYPE 
				from smartlink sl
				where sl.ownerobject = :1
				and (sl.doctype = 'ALL' or '#~#'||sl.doctype||'#~#' like '%#~#'||:3||'#~#%')
				and sl.cny# = :2";
        $stmt = [ &$qry, $this->_entity, GetMyCompany(), $this->_docType ];

        if (!$showInactive) {
            /** @noinspection PhpUnusedLocalVariableInspection - $qry is updated by reference */
            $stmt[0] .= " and sl.active = :4";
            $stmt[] = 'T';
        }
        $stmt = PrepINClauseStmt($stmt, $typesNotLoaded, ' and sl.type');
        $ret = QueryResult($stmt);

        foreach ($ret as $smartlinkraw) {
            // CREATE THE CLASS INSTANCE
            $classname = self::$linkTypes[$smartlinkraw['TYPE']];
            $includefile = $classname . ".cls";
            include_once $includefile;

            $class = new $classname($smartlinkraw['RECORD#'], $keyfield);

            //			eppp(var_export($class, true)); exit;

            // ADD TO THE SMART LINKS ARRAY
            $this->smartLinks[$smartlinkraw['SMARTLINKID']] = $class;
        }

        return true;
    }

    /**
     * @return string
     */
    protected function getSubLedgerEntity()
    {
        return '';
    }    
    
    /**
     * to update sub ledger transactions
     *
     * @param array $values the input values to update opeartion
     *
     * @return bool 
     */
    protected function setFastSubledgerTxn($values)
    {
        $ok = true;
        $params = [
            'selects' => ['PRRECORDKEY'],
            'filters' => [
                [
                    ['DOCID', '=', $values['DOCID']],
                ],
            ],
        ];

        $subLedgerDet = $this->GetList($params) ?? [];

        if (!empty($subLedgerDet[0]['PRRECORDKEY'])) {
            $trxManager = Globals::$g->gManagerFactory->getManager($this->getSubLedgerEntity());
            $subLedgerTxnValues = [];
            
            foreach ($values as $path => $value) {
                $fieldInfo = $trxManager->GetFieldInfo($path);
                
                if ($fieldInfo[self::FAST_UPDATE_FLAG] !== true) {
                    continue;
                }
                
                $subLedgerTxnValues[$path] = $value;
            }
            
            if (!empty($subLedgerTxnValues)) {
                $subLedgerTxnValues['RECORDNO'] = $subLedgerDet[0]['PRRECORDKEY'];
                $ok = $ok && $trxManager->set($subLedgerTxnValues);
            }
        }
        
        return $ok;
    }      

    /**
     * This function validates the values against all the smartlinks
     *
     * @param array $actions
     * @param array $values
     * @param bool  $fromFastUpdate
     *
     * @return bool
     */

    function smartlinkValidate($actions, $values, $fromFastUpdate = false)
    {
        // we need to skip the smart rules for Draft document
        if ($this->isDraftDocument($values)
            && FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_POMATCH')
            && POSetupManager::isPOMatchEnabled()) {
            return true;
        }

        // Report success if postponed
        if ($this->postponeSmartRules) {
            return true;
        }

        // If this is a global object, there are no smart links, return
        if ($this->_schemas[$this->_entity]['globalschema'] ?? false) {
            return true;
        }

        // Validate smart links
        $ok = true;
        if ($this->LoadSmartlinks(array(CUSTOMERP_SMARTLINKVALIDATE))) {
            if (!$this->smartLinks) {
                return true;
            }


            foreach ($this->smartLinks as $smartlink) {
                /**
                 * @var SmartlinkValidate $smartlink
                 */
                $smartlink->SetDocType($this->_docType);
                //if (ENTITYMANAGERDEBUG) {
                //    eppp($smartlink);
                //}
                if (!$smartlink->operationPermissible($actions, $this->_entity, $values, $this->_warningValidation,
                    $fromFastUpdate)) {
                    if ($smartlink->getErrorType() == SMARTLINK_VALIDATE_ERROR_STRING) {    // TODO: PHP 7.1: where does this come from SmartLinkXML defines it, but that class says it is unused!
                        return false; // if an error return
                    }
                    $ok = false; // it is a warning
                }
            }
        }
        return $ok;
    }


    /**
     * @return bool
     */
    function ExistCustomFields()
    {


        $entity = $this->_entity;
        $doctype = $this->_docType;

        return $this->HasCustomFields($entity, $doctype);
    }


    /**
     * @return bool
     */
    function ExistSmartLinks()
    {

        $entity = $this->_entity;
        $doctype = $this->_docType;
        return $this->HasSmartLinks($entity, $doctype);
    }


    /**
     * @return bool
     */
    protected function needToMergeQueries()
    {
        if (!empty($this->macroFields)) {
            return true;
        }

        return parent::needToMergeQueries();
    }

    /**
     * @return array
     */
    public function getMacroFieldInfo()
    {
        return $this->macroUIFieldInfo;
    }

    /**
     * @return array
     */
    public function getMacroNames()
    {
        $names = array();
        foreach ($this->macroFields as $field) {
            $names[] = $field['name'];
        }

        return $names;
    }

    /**
     * @return array
     */
    public function getMacroPaths()
    {
        $paths = array();
        foreach ($this->macroFields as $field) {
            $paths[] = $field['path'];
        }

        return $paths;
    }

    /**
     *
     */
    public function MergeObjectFieldList()
    {
        parent::MergeObjectFieldList();

        if (!empty($this->macroFields)) {
            $schemaobject = &$this->_schemas[$this->_entity]['object'];
            $publish = &$this->_schemas[$this->_entity]['publish'];

            foreach ($this->macroFields as $macroField) {
                if (SCMMacroManager::hasMacroLinkFieldInDB($macroField['name'])) {
                    $schemaobject[] = $macroField['path'];
                    $publish[] = $macroField['path'];
                }
            }
            $schemaobject[] = "SCMMACROLINK";

            $api = &$this->_schemas[$this->_entity]['api'];
            $api['LESS_GET_FIELDS'][] = "SCMMACROLINK";
        }
    }

    public function MergeObjectSchema()
    {
        parent::MergeObjectSchema();

        if (!empty($this->macroFields)) {
            $schema = &$this->_schemas[$this->_entity]['schema'];
            foreach ($this->macroFields as $macroField) {
                if (SCMMacroManager::hasMacroLinkFieldInDB($macroField['name'])) {
                    $schema[$macroField['path']] = strtolower($macroField['path']);
                }
            }
            $schema['SCMMACROLINK'] = "state";
        }
    }

    /**
     * @return array
     */
    protected function getMacroFields()
    {
        global $gBooleanType;
        $fields = array();

        foreach ($this->macroFields as $key => $macroField) {
            $fields[] = array(
                'fullname' => $macroField['name'],
                'type' => $gBooleanType,
                'default' => 'false',
                'desc' => $macroField['name'],
                'path' => $macroField['path'],
                'macroField' => true,
                'id' => 1000+$key
            );
        }

        return $fields;
    }


    /**
     *
     */
    function MergeTableInfo()
    {
        parent::MergeTableInfo();

        $table = $this->_schemas[$this->_entity]['table'];
        $dbfieldinfo = &$this->tables[$table]['db_fieldinfo'];

        foreach ($this->macroFields as $macroField) {
            if (SCMMacroManager::hasMacroLinkFieldInDB($macroField['name'])) {
                $dbfieldinfo[strtolower($macroField['path'])] = ['type' => 'text'];
            }
        }
    }

    public function MergeFieldInfo()
    {
        parent::MergeFieldInfo();
        $this->macroUIFieldInfo = array();

        if (!empty($this->macroFields)) {

            $fieldInfo = &$this->_schemas[$this->_entity]['fieldinfo'];
            $baseFieldInfo = &$this->_schemas[$this->_entity]['basefieldinfo'];

            $macroFields = $this->getMacroFields();

            foreach ($macroFields as $macroField) {
                $fieldInfo[] = $macroField;
                $baseFieldInfo[] = $macroField;
                $this->macroUIFieldInfo[] = $macroField;

            }

            $macroLinkField = array(
                'fullname' => $this->macroFields[0]['name'].' link',
                'hidden'  => true,
                'readonly' => true,
                'path' => 'SCMMACROLINK',
                'formula' => array(
                    'typeOf' => 'STATE',
                    'fields' => array(
                        'CNY#',
                        'RECORDNO',
                    ),
                    'function' => "
                            case when (
                                select 1 from scmmacroresolve scmr
                                where scmr.cny# = \${1} and scmr.sourcedockey = \${2} and rownum = 1
                            ) > 0 then 'T' else 'F' end",
                ),
                'calculated' => true,
                'macroField' => true,
            );

            $fieldInfo[] = $macroLinkField;
            $baseFieldInfo[] = $macroFields[0];
            $this->macroUIFieldInfo[] = $macroLinkField;
        }
    }

    /**
     * @throws Exception
     */
    public function LoadMacroFields()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $scmMacroMgr =  $gManagerFactory->getManager('scmmacro');
        $this->macroFields = array();
        $docType = $this->_docType;

        if (empty($docType)) {
            return;
        }

        $params = array(
            'selects' => array('RECORDNO', 'NAME', 'TARGETDOCFROM'),
            'filters' => array(
                array(
                    array('SOURCEDOCPARID', '=', $docType),
                    array('PRIORVERSIONKEY', 'ISNULL'),
                )
            ),
        );

        $recs = $scmMacroMgr->GetList($params);

        if (!empty($recs)) {
            foreach ($recs as $rec) {
                if (!empty($rec['RECORDNO'])) {
                    if ($rec['TARGETDOCFROM'] == 'document') {
                        $this->macroFields[] = SCMMacroManager::getMacroFields($rec['NAME']);
                    }
                }
            }
        }

    }

    /**
     * @param int  $cny
     * @param bool $withLookup
     */
    function LoadCustomFields($cny = 0, $withLookup = true)
    {
        ////////////////////////////////////////////////////////////////////////////////
        // GET ALL THE FIELDS FROM THE DB
        ////////////////////////////////////////////////////////////////////////////////

        if (!$cny) {
            $cny = (int) GetMyCompany();
        }

        // if we dont have $cny we are not in any company context
        if (!isset($cny) || $cny == '') {
            return;
        }

        // load macro fields
        $this->LoadMacroFields();

        $queryArr = [ '', $cny, $this->_entity, 'T' ];
        $doctypeClause = ' ';

        if ( $this->_docType !== '%' && $this->_docType != BUILD_KIT && $this->_docType != DIS_KIT ) {
            $doctypeClause = " and (cf.DOCTYPE = :4 or :5||cf.DOCTYPE||:5 like :6) ";
            //$doctypeClause = " and (cf.DOCTYPE = 'ALL' or '#~#'||cf.DOCTYPE||'#~#' like '%#~#'||:3||'#~#%') ";
            $queryArr[] = 'ALL';//:4
            $queryArr[] = '#~#';//:5
            $queryArr[] = '%#~#' .$this->_docType . '#~#%';//:6
        }
        $idx = count($queryArr);
        if ( !$withLookup ) {
            $idx2 = $idx + 1;
            $lookupClause = " AND cf.TYPE != :$idx AND cf.TYPE != :$idx2 ";
            $queryArr[] = CUSTOMERP_RELATIONSHIPFIELDTYPE;
            $queryArr[] = CUSTOMERP_RELATIONSHIPFIELDTYPE_DIMENSION;
        } else {
            $lookupClause = " AND cf.TYPE != :$idx ";
            $queryArr[] = CUSTOMERP_RELATIONSHIPFIELDTYPE;
        }
        $qry = "select 
					cf.RECORD# as RECORDNO, cf.CUSTOMFIELDID, cf.TYPE, cf.OBJECTFIELDID, cf.DATA DATADESCRIPTION, cf.REQUIRED, cf.PACKAGEKEY,
					cf.DESCRIPTION, cc.RECORD# as CUSTOMCOMPONENTKEY,
					cc.COMPONENTTYPE, cc.PATH, cc.LABEL, cc.HIDDEN, cf.DOCTYPE
					from CUSTOMFIELD cf, CUSTOMCOMPONENT cc
					where cf.RECORD# = cc.CUSTOMFIELDKEY
                        and cf.CNY# = :1
                        and cc.CNY# = :1
                        and cf.OWNEROBJECT = :2  
                        $doctypeClause
                        $lookupClause
                        and cf.ACTIVE = :3
                    order by to_number(substr(cf.OBJECTFIELDID,10)) ";

        $queryArr[0] = $qry;

        $res = QueryResult($queryArr);

        ////////////////////////////////////////////////////////////////////////////////
        // INSTANTIATE AN OBJECT FOR EACH RECORD
        ////////////////////////////////////////////////////////////////////////////////


        if ($res === false || !count($res)) {
            return;
        }

        foreach ($res as $object) {
            if (isset($object['DATADESCRIPTION'])) {
                $object['DATADESCRIPTION'] = databaseStringUncompress($object['DATADESCRIPTION']);
            }
            // CREATE A CLASS INSTANCE
            $classname = "CustomField" . isl_ucfirst(isl_strtolower($object['TYPE']));
            $includefile = $classname;
            import($includefile);

            /**
             * @var CustomField $class
             */
            $class = new $classname($object);

            //  If there is a previous custom field with the same id, remember the doctype.
            $prevDocType = array();
            if (isset($this->customFields[$object['CUSTOMFIELDID']])) {
                /**
                 * @var CustomField $prevObj
                 */
                $prevObj = $this->customFields[$object['CUSTOMFIELDID']];
                $prevDocType = $prevObj->GetRawObjField('DOCTYPE');
            }

            // ADD TO THE ARRAY
            $this->customFields[$object['CUSTOMFIELDID']] = $class;

            //  Figure the custom field index (i.e. 'custfield1' to '1').
            $this->_SearchExtractCustomFieldInfo($object['OBJECTFIELDID'], $cfNum, $cfAlias);

            //  Merge the new doc type with any previous doc types, and set that array as the 'DOCTYPE' raw value.
            if ($prevDocType == '') {
                $docArray = array($class->GetRawObjField('DOCTYPE') => $cfNum);
            } else {
                $docArray = array_merge($prevDocType, array($class->GetRawObjField('DOCTYPE') => $cfNum));
            }
            $class->SetRawObjField('DOCTYPE', $docArray);
        }
    }


    ////////////////////
    //   SearchGetCustomFieldCalc
    //    This function returns the calculation needed for a custom field value as it is added to
    //   a search summary.  The information returned by this function determines if additional processing
    //   of the custom field value is needed and, if so, the metadata for that calculation.

    /**
     * @param string $custFieldName
     *
     * @return string[]
     */
    function SearchGetCustomFieldCalc($custFieldName)
    {

        //  DocumentManager custom fields are dependant on their doctype.  A custom field only
        //   makes sense if the rows doctype matches the custom field doctype.  So, pass metadata
        //   that will be interpreted by Global Search to do this matching.
        /**
         * @var CustomField $obj
         */
        $obj = $this->customFields[$custFieldName];
        $doctype = $obj->GetRawObjField('DOCTYPE');
        return array('DOCPARID', '==', $doctype);
    }


    /**
     * @param string $entity
     * @param string $doctype
     *
     * @return bool
     */
    function HasCustomFields($entity, $doctype)
    {

        // If no ownerobject specified, return
        if (!isset($entity) || $entity == '') {
            return false;
        }


        // If this is a global/ims object, there are no custom fields, return
        if (!EntityManager::isCompanySchema($entity)) {
            return false;
        }

        // If entity not in global map, return
        global $gCustomFieldMap;

        if (!isset($gCustomFieldMap) || !is_array($gCustomFieldMap) || !in_array($entity, $gCustomFieldMap)) {
            return false;
        }

        $lookup = $entity . '--' . $doctype;

        // Special 'ALL' type customfields lookup
        // We may have customfield.DOCTYPE marked as 'ALL',
        // This may have been done by custom package upload,
        // wherein the uploaded customfields should appear on ALL document types
        $spllookup = $entity . '--ALL';

        // Check in cache for existence of customfields for this entity
        global $disableCustomERPCache;

        if (!$disableCustomERPCache) {

            $custFld = Profile::getCompanyCacheProperty('CUSTOMFIELDS');
            if (is_array($custFld)) {
                if (in_array($lookup, $custFld) || in_array($spllookup, $custFld)) {
                    return true;
                }
                return false;
            }
        }

        $cny = GetMyCompany();

        static $customFieldCache = [];

        if (array_key_exists($entity . "::" . $cny, $customFieldCache)) {
            return $customFieldCache[$entity . "::" . $cny];
        }

        // If somehow we reach this point, use DB query to find out
        $qry = " select count(*) as COUNT 
                  from CUSTOMFIELD 
                  where cny# = :1 
                    and OWNEROBJECT = :2 
                    and (DOCTYPE = 'ALL' or '#~#'||DOCTYPE||'#~#' like '%#~#'||:3||'#~#%' ) ";
        $res = QueryResult(array($qry, $cny, $entity, $doctype));

        $customFieldCache[$entity . "::" . $cny] = ($res[0]['COUNT'] > 0) ? true : false;

        return $customFieldCache[$entity . "::" . $cny];
    }


    /**
     * @param string  $entity
     * @param string $doctype
     *
     * @return bool
     */
    function HasSmartLinks($entity, $doctype)
    {

        // If no ownerobject specified, return
        if (!isset($entity) || $entity == '') {
            return false;
        }

        // If this is a global object, there are no smart links, return
        if (!parent::isCompanySchema($entity)) {
            return false;
        }

        // If entity not in global map, return
        global $gSmartLinkMap;
        if (!isset($gSmartLinkMap) || !is_array($gSmartLinkMap) || !in_array($entity, $gSmartLinkMap)) {
            return false;
        }


        $lookup = $entity . '--' . $doctype;

        // Special 'ALL' type smartlinks lookup
        // We may have smartlink.DOCTYPE marked as 'ALL',
        // This may have been done by custom package upload,
        // wherein the uploaded smartlinks should appear on ALL document types
        $spllookup = $entity . '--ALL';

        // Check in cache for existence of smartlinks for this entity
        global $disableCustomERPCache;

        if (!$disableCustomERPCache) {

            $smartLnk = Profile::getCompanyCacheProperty('SMARTLINKS');
            if (is_array($smartLnk)) {
                if (in_array($lookup, $smartLnk) || in_array($spllookup, $smartLnk)) {
                    return true;
                }
                return false;
            }
        }

        // If somehow we reach this point, use DB query to find out
        $qry = "select count(*) as COUNT 
                from SMARTLINK 
                where cny# = :1 
                  and OWNEROBJECT = :2 
                  and (DOCTYPE = 'ALL' or '#~#'||DOCTYPE||'#~#' like '%#~#'||:3||'#~#%' ) ";
        $res = QueryResult(array($qry, GetMyCompany(), $entity, $doctype));
        return ($res[0]['COUNT'] > 0);
    }



    /**
     * Remove any custom fields. Purge only for records belonging to this document type
     *
     * @param  string $column the column that needs to be purged.
     * @param   array|null  $values
     *
     * @return bool
     */
    final public function PurgeCustomFieldColumn($column, $values = null)
    {
        $qry = "
			update dochdrmst set $column = null where cny# = :1 and record# in (
				select d.record# from dochdrmst d, docpar p where d.docparkey = p.record#
				and d.cny# = :1 and p.cny# = :1 and p.docid = :2
			) and ";
        $qry = array($qry, GetMyCompany(), $this->_docType);
        if (!$values) {
            $qry[0] .= "$column is not null";
        } else {
            $qry = PrepINClauseStmt($qry, $values, " $column ");
        }
        // Must purge recurring documents as well. This is an ugly hack
        // Long term task: refactor RecurDocumentManager to not be a sub-class of DocumentManager
        return RecurDocumentManager::PurgeCustomFieldColumn_static($column, $this->_docType, $values)
            && ExecStmt($qry);
    }

    /**
     * Determine how many records have the specified values for a custom field
     *
     * @param string $column  the custom field column name
     * @param array  $values  the values to look for
     *
     * @return int  the cound of records found matching the specified values
     */
    public function countForCustomFieldColumnValues($column, $values)
    {
        $qry = "select count(1) cnt from dochdrmst where cny# = :1 and record# in (
				select d.record# from dochdrmst d, docpar p where d.docparkey = p.record#
				and d.cny# = :1 and p.cny# = :1 and p.docid = :2
			) and ";
        $qry = array($qry, GetMyCompany(), $this->_docType);
        $qry = PrepINClauseStmt($qry, $values, "$column ");
        $res = QueryResult($qry);
        if (is_array($res) && array_key_exists(0, $res)) {
            return $res[0]['CNT'];
        }

        return 0;
    }

    /**
     * Get the OwnedObjectManager
     *
     * @param  string $entity the entity for which the owned object is required.
     *
     * @return EntityManager|OwnedObjectManager $entManager entity manager instance of the owned object.
     */
    function GetOwnedObjectManager($entity)
    {
        if ($this->_isCachable) {
            $entManager = Globals::$g->gManagerFactory->getManager($entity, false, array( 'DOCTYPE' => $this->_docType));
        } else {
            $mgr = class_lookup($entity . 'manager');
            $entManager = Globals::$g->gManagerFactory->_getObjectInstance($mgr, false, array('DOCTYPE' => $this->_docType));

        }
        return $entManager;
    }

    /**
     * do event called based on add/set and mostly used for handling salesforce events.
     *
     * @param  string $verb the action mode verb [create/update].
     * @param  string $key the recordkey [VID] of the document.
     * @param string $param1 if populated will be used as entity while invoking FillSubscriptions()
     * @param bool   $param2
     * @param   array   $values
     *
     * @param bool   $fastUpdate
     *
     * @return bool True means success, false means failure.
     */
    function DoEvent($verb, $key, $param1 = null, $param2 = null, $values = [], $fastUpdate = false)
    {
        $isPOmatchEnabled = (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_POMATCH')
                                && POSetupManager::isPOMatchEnabled());
        // we need to skip the smart event for Draft document only for POmatch enabled company
        if(!($this->isDraftDocument($values) && $isPOmatchEnabled)) {
            // Postpone events till real DOCNO is in place or for any other reasons
            if ($this->postponeEvents) {
                return true;
            }

            if ($param2 === null) {
                $param2 = true;  // PHP 7.1 the base class defines the parameter as defaulting to null; we want it to default to true.
            }

            if ($verb == 'Delete') {
                $this->deleteChatter($key);
            }

            global $gManagerFactory;
            $param1 = (($param1 == '') ? $this->_entity : $param1);

            $subscription = $gManagerFactory->getManager('imssubscription');
            $subscription->substatecache = $this->_substatecache;

            if ($param1 == 'arinvoice' || $param1 == 'apbill') {
                $subscription->FillSubscriptions($verb, $param1, $key, '', false);
            } else {
                $subscription->FillSubscriptions($verb, $param1, $key, $this->_docType ?? '', $param2);
            }
        }

        if(empty($param1 ?? '')){
            $param1 = $this->_entity;
        }
        $auditTrailSession = AuditTrailSession::getInstance();
        $auditPayload = null;
        if ($verb != 'Delete') {
            $auditPayload = new AuditTrailPayload($param1, $key, null);
        }
        $mode = AuditTrailSession::eventToAccessMode($verb);
        if ($mode === null) {
            return false;
        }
        $auditTrailSession->addAuditEvent($param1, $key, $mode, $auditPayload);
        return true;
    }

    /**
     * Its used to call when document converted to create renewals based on TD.
     * This function has been inherited to SO only,
     *
     * @param array $values the document values.
     *
     * @return bool
     */
    function CreateDocConvRenewals(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        return true;

    }

    /**
     * @param array $nvalues
     * @param array[] $glentries
     * @param array $directGLPosting
     *
     * @return bool
     *
     */
    function PreprocessDeletePRInvGLEntries(
        /** @noinspection PhpUnusedParameterInspection */ &$nvalues,
        /** @noinspection PhpUnusedParameterInspection */ &$glentries,
        /** @noinspection PhpUnusedParameterInspection */ $directGLPosting)
    {
        return true;
    }


    /**
     * @param array $values
     * @param mixed $event
     *
     * @return bool
     */
    function ProcessEvent(&$values, $event)
    {
        $docEventMgr = $this->get_event_manager();
        $workflow = $this->get_workflow();
        $docEventMgr->Init($workflow, $this);
        return $docEventMgr->ProcessEvent($values, $event);
    }


    /**
     * @param string[]|string[][]|string[][][]  $values
     *
     * @return bool
     */
    function SubmitDocument(&$values)
    {
        $docApprovalMgr = $this->get_documentapproval_manager();
        // not require below line as it is already called in parent constructor
        // $docApprovalMgr->InitConstants();
        $this->applyAllocationForGet($values);
        $ok = $docApprovalMgr->SubmitDocumentApproval($values);
        // if the entry was auto-approved (completely or partialy), let's update its state in the DB
        if ($values['APPROVAL_STATE'] != self::SUBMITTED_RAWSTATE) {
            $ok = $ok && $this->processStateUpdate($values, $docApprovalMgr, true);
        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function isPartiallyApproving($values)
    {
        $ok = false;
        if (IsMultiEntityCompany() && (IsUserLocRestricted() || IsUserDepRestricted())) {

            $docMgr = Globals::$g->gManagerFactory->getManager(
                $this->mod . "documententry", false, array( 'DOCTYPE' => $this->_docType)
            );

            $getListVars = array(
                'selects' => array(
                    array(
                        'fields' => array('LINE_NO'),
                        'function' => 'count(${1})'
                    )
                ),
                'columnaliases' => array('CNT'),
                'filters' => array(
                    array(
                        array('DOCHDRID', '=', $values['DOCID'])
                    ),
                ),
            );
            $withRestrictionsRes = $docMgr->GetList($getListVars);

            // get document entries without user restrictions on location/department
            $getListVars['SUBS_TABLE'] = ['docentry' => 'docentrymst'];
            $withoutRestrictionsRes = $docMgr->GetList($getListVars);

            if ($withRestrictionsRes['0']['CNT'] != $withoutRestrictionsRes['0']['CNT']) {
                $ok = true;
            }

        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function ApproveInternal(&$values)
    {
        $ok = $this->CleanupEditorValues($values);

        $docApprovalMgr = $this->get_documentapproval_manager();
        $docApprovalMgr->InitConstants();

        // We need this to fetch the particular document from approvalhistory, to fetch the approval rules of that dochdrkey reference.
        $document = $this->Get($values['DOCID']);
        $values['RECORDNO'] = $document['RECORDNO'];

        $this->disableWarningValidation();

        if ($this->isPartiallyApproving($values)) {
            $ok = false;
            Globals::$g->gErr->addIAError('INV-1375', __FILE__ . '.' . __LINE__);
        }

        $ok = $ok && $docApprovalMgr->ApproveDocument($values);
        if ($docApprovalMgr->update_state) {
            $ok = $ok && $this->processStateUpdate($values, $docApprovalMgr, true);
        }

        if (Request::$r->_approveSubLedgerPostErr != '') {
            $ok = false;
            Globals::$g->gErr->addError('BL01001973', __FILE__ . ':' . __LINE__, Request::$r->_approveSubLedgerPostErr);
        }

        return $ok;
    }

    /**
     * @param array                   $values
     * @param DocumentApprovalManager $docApprovalMgr
     * @param bool                    $notify
     *
     * @return bool
     */
    private function processStateUpdate(&$values, $docApprovalMgr, $notify = true)
    {
        $ok = $this->setDocumentState($values, $values['APPROVAL_STATE']);

        if ($ok && $values['APPROVAL_STATE'] == 'A') {
            $values['STATE'] = $this->getFinalState($values);

            // We have to force the document to use the latest docpar information from the docpar. If we unset this value here,
            // the latest would be picked up from the PrepValues API.
            unset($values['_DOCPAR']);
            unset($values['EXISTING_ENTRIES']);
            unset($values['EXISTING_DOC']);

            //If VAT subscribed unset Taxdetails to build subtotals again
            if (
                ($values['TXNISVATENABLED'] ?? false) &&
                ($values['ENTRIES'] ?? false)
            ) {
                foreach ($values['ENTRIES'] as &$entry) {
                    unset($entry['TAXDETAILS']);
                }
            }
            $this->setSystemUpdate(true);
            $ok = $ok && $this->set($values);
            $this->setSystemUpdate(false);

            // Notify the submitter only if the set goes through
            if ($ok && $notify) {
                $docApprovalMgr->NotifySubmitter($values, "approved");
            }
        }

        return $ok;
    }

    /**
     * @param bool $state
     */
    public function setSystemUpdate($state)
    {
        $this->systemUpdate = $state;
    }

    /**
     * @param string[]|string[][]|string[][][]  $values
     * @param string $state
     *
     * @return bool
     */
    function setDocumentState($values, $state)
    {
        $setQry = " update dochdrmst set state = :1 where cny# = :2 and record# = :3 ";
        return ExecStmt(array($setQry, $state, GetMyCompany(), $values['RECORDNO']));
    }

    /**
     * @param string[]|string[][]|string[][][]  $values
     *
     * @return bool
     */
    function DeclineInternal(&$values)
    {
        $docApprovalMgr = $this->get_documentapproval_manager();
        $docApprovalMgr->InitConstants();

        // We need this to fetch the particular document from approvalhistory, to fetch the approval rules of that dochdrkey reference.
        $document = $this->Get($values['DOCID']);
        $values['RECORDNO'] = $document['RECORDNO'];

        $ok = $docApprovalMgr->DeclineDocument($values);

        $ok = $ok && $this->setDocumentState($values, $values['APPROVAL_STATE']);

        // Notify the submitter only if the set goes through
        if ($ok) {
            $docApprovalMgr->NotifySubmitter($values, "declined");
        }

        return $ok;
    }

    /**
     * @param string[]|string[][]|string[][][]  $values
     *
     * @return bool
     */
    public function API_Add(&$values)
    {
        $this->_fromAPI = true;
        $this->API_CleanupDerivedFields($values);

        return parent::API_Add($values);
    }

    /**
     * @param string[]|string[][]|string[][][]  $values
     *
     * @return bool
     */
    public function API_Set(&$values)
    {
        $this->_fromAPI = true;
        $this->API_CleanupDerivedFields($values);
        return parent::API_Set($values);
    }

    /** Perform Construction Vendor Compliance validation during create or edit of a Purchasing document.
     * @param [] $values
     * @param bool $isPosting
     * @return bool
     * @noinspection PhpUnusedParameterInspection
     */
    protected function validateVendorCompliance_DocSave($values, $isPosting = false)
    {
        // Default implementation.  Override is in PODocumentManager
        return true;
    }

    /**
     * @param []  $values
     *
     * @return bool
     */
    public function ValidateAfterFormat(&$values)
    {
        $ok = true;
        foreach ($values['ENTRIES'] as $entry) {
            if (isset($entry['CONVERSIONTYPE']) && $entry['CONVERSIONTYPE'] == 'Price') {
                $error = false;
                if (isset($entry['TRX_PRICE']) && !isNullOrBlank($entry['TRX_PRICE'])) {
                    if ($entry['TRX_PRICE'] != iround($entry['TRX_PRICE'], 2)) {
                        $error = true;
                    }
                }
                else if (isset($entry['PRICE']) && !isNullOrBlank($entry['PRICE'])) {
                    if ($entry['PRICE'] != iround($entry['PRICE'], 2)) {
                        $error = true;
                    }
                }
                else if (isset($entry['UIPRICE']) && !isNullOrBlank($entry['UIPRICE'])) {
                    if ($entry['UIPRICE'] != iround($entry['UIPRICE'], 2)) {
                        $error = true;
                    }
                }

                if ($error) {
                    global $gErr;
                    $msg = 'When using Price conversion, the price amount must be limited to 2 digits after the decimal point.';
                    $gErr->addIAError('INV-1309', __FILE__ . ':' . __LINE__, $msg, []);
                    $ok = false;
                }
            }
        }

        return $ok;
    }

    /**
     * @param int|int[]|string|string[]    $ids
     * @param string[]|null                $fields
     *
     * @return array|false
     */
    public function API_Get($ids, $fields=null)
    {
        //  Validate operation.
        if (!$this->API_Validate(API_READ, $values)) {
            return false;
        }

        // need to convert the IDs (recordno) to vids
        $keyfields = array($this->GetKeyFieldName());
        $filter = array(array(array('RECORDNO', 'IN', explode(",", $ids))));
        $params = array('selects' => $keyfields,
            'filters' => $filter);
        $retIds = $this->GetList($params);

        //  If there were supplied recordnos but no keys were found, then return null.  This is
        //   a different condition than being supplied with an empty recordno array, which means
        //   fetch the first 100 records.
        if (!empty($ids) && count($retIds) == 0) {
            return false;
        }

        $idsArr = array();
        foreach ($retIds as $id) {
            $idsArr[] = $id[strtoupper($this->GetKeyFieldName())];
        }

        $results = $this->_API_GetMasterDetail($idsArr, $fields);

        //  If requested, do a query to find the originating source recurring template key.
        if ( (!is_null($fields)) && (in_array('SOURCERECURKEY', $fields))) {
            foreach ($results as &$obj) {
                $res = $this->DoQuery('QRY_DOCUMENT_GET_SOURCERECUR', array($obj['RECORDNO']));
                $obj['SOURCERECURKEY'] = empty($res) ? null : $res[0]['RECORDNO'];
            }
        }

        //  Allow classes to rename output structures.
        $results = $this->API_UnformatObject($results);
        return $results;
    }

    /**
     * @param array $values
     *
     * @return array
     */
    function API_UnformatObject($values)
    {
        //$itemsAliases = $this->API_GetSetting('ITEMS_ALIAS');
        $itemAlias = $this->API_GetSetting('ITEM_ALIAS');
        $itemAlias = strtolower($itemAlias[0]);

        foreach ($values as &$value) {
            if (is_array($value['ENTRIES'][$itemAlias][0])) {
                foreach ($value['ENTRIES'][$itemAlias] as &$docentry) {
                    if(isset($docentry['TRACKINGENTRIES']) && !isEmptyArray($docentry['TRACKINGENTRIES'])){
                        $trackEntries = $docentry['TRACKINGENTRIES'];
                        unset($docentry['TRACKINGENTRIES']);
                        $docentry['TRACKINGENTRIES']['TRACKINGENTRY'] = $trackEntries;
                    }
                }
            }
        }

        $values = parent::API_UnformatObject($values);
        return $values;
    }

    /**
     *  API_GetByName
     *    This function overrides (but utilizes) the parent API_GetByName in order to add the
     *   retrieval of the SOURCERECURKEY field.
     *
     * @param array $ids        Array    Array of object record names
     * @param array $fields    Array    Array of field names to retrieve (empty means retrieve all fields)
     *
     * @return array    Array of found objects.
     */
    public function API_GetByName($ids, $fields=null)
    {

        //  Resolve the field names here, we need to see if SOURCERECURKEY is there.
        if ($fields == null) {
            $fields = $this->GetGetFields();
        }

        //  Remove the SOURCERECURKEY if given, otherwise parent API_GetByName will fail.
        $idx = array_search('SOURCERECURKEY', $fields);
        if ($idx !== false) {
            $doSourceRecur = true;
            unset($fields[$idx]);
        }

        $objs = parent::API_GetByName($ids, $fields);

        //  If requested, do a query to find the originating source recurring template key.
        /** @noinspection PhpUndefinedVariableInspection */
        if ($doSourceRecur) {
            foreach ($objs as &$obj) {
                $res = $this->DoQuery('QRY_DOCUMENT_GET_SOURCERECUR', array($obj['RECORDNO']));
                $obj['SOURCERECURKEY'] = empty($res) ? null : $res[0]['RECORDNO'];
            }
        }

        return $objs;
    }

    /**
     * This is a base function but it will be used only in sodocument instance
     *
     * @param array  $document
     *            - an array of sodocument record with all sub object values, this argument is passed by reference.
     */
    public function getProjectInvoiceInfo(/** @noinspection PhpUnusedParameterInspection */ &$document)
    {
    }

    /**
     * If a derived class needs more printable info for the header than BaseGet provides, override this method
     *
     * @param string $docid
     *
     * @return array of $docid attributes
     */
    public function getPrintableHeaderInfo($docid)
    {
        $obj = $this->BaseGet($docid);
        return $obj;
    }

    /**
     * Get all details about the document for printing
     *
     */
    /**
     * @param string $docid
     * @param array  $xsltemplateInfo
     *
     * @return array|bool
     * @throws Exception
     * @noinspection UnsupportedStringOffsetOperationsInspection
     */
    public function getPrintableInfo($docid, &$xsltemplateInfo)
    {
        $gErr = Globals::$g->gErr;

        $obj = $this->getPrintableHeaderInfo($docid);

        if (!$obj) {
            return false;
        }

        $ownedObjects =& $this->GetOwnedObjects();

        // find the line item fields grouping preferences from docparpref
        $displayFieldsList = $groupingFieldsList = array();
        $entriesDisplay = 'DETAILED';

        if (isset($xsltemplateInfo) && $xsltemplateInfo['PARAMS'] != '') {
            $entriesDisplay = $xsltemplateInfo['GROUPFIELDS_FLOATPAGE']['ENTRIES_DISPLAY'];
            $entriesDisplay = ($entriesDisplay == 'SUMMARIZED' ? $entriesDisplay : 'DETAILED');

            // DEBUG
            //$t = $xsltemplateInfo;
            //$t['GROUPFIELDS_FLOATPAGE'] = $t['template'] = $t['XSL'] = '';
            //LogToFile("xsltemplateInfo => \n" . pp($t). "\n");

            $displayFieldsList = $xsltemplateInfo['DISPLAYFIELDSLIST'];
            $groupingFieldsList = $xsltemplateInfo['GROUPINGFIELDSLIST'];
        }

        //fetch document definition to see if it is enabled for sales contract
        $docparMgr = $this->get_docpar_manager();
        $obj['_DOCPAR'] = $docparMgr->GetBaseLatest($obj['DOCPARID']);

        $isContractBillingEnabled = $this->isProjectContractEnabledInDoc($obj);

        if (is_array($ownedObjects)) {

            foreach ($ownedObjects as $ownedObject) {
                $cnt = count($gErr->errors);

                $this->_schemas[$ownedObject['entity']]['parententity'] = $this->_entity;

                /**
                 * @var OwnedObjectManager $lineManager
                 */
                $lineManager = $this->GetOwnedObjectManager($ownedObject['entity']);
                $dimFields = $lineManager->GetDimensionFields();
                // lets set the parententity attribute, if one was supplied dynamically in the ownedobjects structure
                if ($ownedObject['parententity'] != '') {
                    $lineManager->SetParentEntity($ownedObject['parententity']);
                }

                $ent = $ownedObject['entity'];
                $invfkey = $lineManager->GetInvFKey();
                $parentKey = EntityManager::AccessByPath($obj, $invfkey);

                // its not valid to issue a query for owned objects without parentkey
                if (!isset($parentKey) || $parentKey == '') {
                    continue;
                }

                // sub entities other sodocumententry or podocumententry needs to use GetByParent
                // instead of GetList, since there are already code munging the resultsets
                if (!in_array($lineManager->_entity, array('sodocumententry', 'podocumententry', 'invdocumententry'))) {
                    $obj[$ownedObject['path']] = $lineManager->getByParent($parentKey);

                    // we need to transform dimension field values were appropriate
                    if ($lineManager->HasDimensions()) {
                        for ($i = 0; $i < count($obj[$ownedObject['path']]); $i++) {
                            $row =& $obj[$ownedObject['path']][$i];
                            foreach ($dimFields as $dimid => $field) {
                                $dimID = $dimFields[$dimid]['path'];
                                if (isset($row[$dimID])) {
                                    $row[$dimID] = explode("--", $row[$dimID])[0];
                                }
                            }
                            // $temp_obj below is dummy array
                            $lineManager->TransformDimensionValues($row, $temp_obj);
                        }
                    }

                    // skip to next object since we are done with current one...
                    continue;
                }

                $columnaliases = $groupBy = array();

                // define the number columns which needs to be summed up
                $sumColumns = array('UIQTY', 'UIVALUE', 'QUANTITY', 'VALUE', 'TRX_VALUE');
                $sumPartitionColumns = array ('UIQTY', 'UIPRICE', 'UIVALUE', 'QUANTITY', 'PRICE', 'VALUE', 'TRX_PRICE', 'TRX_VALUE');

                $orders = array(array('DOCHDRNO', 'asc'));

                // collect all fields for the current object
                $fields = $lineManager->GetGetFields();

                // we need additional fields for invoices generated from projacct
                // grab additional fields from schema structure definition
                // this is required so that we get the projacct relationship fields
                if ($obj['INVOICERUNKEY'] != '' || isArrayValueProvided($obj, 'PREVIEWHEADERKEY')
                    || ( (!empty($groupingFieldsList)) ) ) {
                    $schema = $lineManager->_schemas[$lineManager->_entity]['schema'];

                    foreach ($schema as $external => $internal) {
                        if (!is_array($internal) && !in_array($external, $fields)) {
                            $fields[] = $external;
                        }
                    }
                }

                // define the entrytype special field, ideally calculated field should work
                // but for some reason its not working...
                $entryType = array(
                    'fields' => array('BILLABLETIMEENTRYKEY', 'BILLABLEPRENTRYKEY', 'BILLABLEDOCENTRYKEY'),
                    'function' => " (CASE WHEN \${1} is not null THEN 'Time' " .
                        " WHEN \${2} is not null AND $ent.employeedimkey is not null THEN 'Expense' " .
                        " WHEN \${2} is not null AND $ent.employeedimkey is null THEN 'Bills' " .
                        " WHEN \${3} is not null AND $ent.vendordimkey is not null THEN 'Purchases' " .
                        " WHEN \${3} is not null AND $ent.vendordimkey is null THEN 'Orders' " .
                        " ELSE '' END) "
                );

                $entryTypeTxt = "(CASE 
				WHEN $ent.billabletimeentrykey is not null THEN 'Time'
				WHEN $ent.billableprentrykey is not null AND $ent.employeedimkey is not null THEN 'Expense'
				WHEN $ent.billableprentrykey is not null AND $ent.employeedimkey is null THEN 'Bills'
				WHEN $ent.billabledocentrykey is not null AND $ent.vendordimkey is not null THEN 'Purchases'
				WHEN $ent.billabledocentrykey is not null AND $ent.vendordimkey is null THEN 'Orders'
				ELSE '' END)";

                // if the first grouping field is not ITEMID but we have TASK as one of
                // the grouping item then lets force ITEMID to the beginning
                $grpPartitionStr = " $ent.cny#, $ent.dochdrkey ";
                $firstGroupingField = $groupingFieldsList[0];

                // we need to set project contract line id to be first group field for PCB enabled documents with PCB fields in field preference setting
                if($isContractBillingEnabled && $lineManager->_entity == 'sodocumententry' && is_array($groupingFieldsList) && in_array("PROJECTCONTRACTLINEID", $groupingFieldsList) ){
                    $firstGroupingField = "PROJECTCONTRACTLINEID";
                }

                if ($firstGroupingField != "ITEMID" && in_array('TIMESHEETENTRY_TASKNAME', ($groupingFieldsList ?? []))) {
                    $groupingFieldsList = array_merge(array("ITEMID"), $groupingFieldsList);
                    $firstGroupingField = $groupingFieldsList[0];
                }

                // default first grouping to itemid if none found
                if (!isset($firstGroupingField) || $firstGroupingField == '' || $firstGroupingField == 'ITEMID') {
                    $firstGroupingField = "$ent.itemkey";
                    $groupingFieldsList[0] = 'ITEMID';
                } else if ($firstGroupingField == 'ENTRYTYPE') {
                    $firstGroupingField = $entryTypeTxt;
                } else {
                    $firstGroupingField = $lineManager->_ConvertExternalPath($firstGroupingField);
                }

                if ($entriesDisplay == 'SUMMARIZED') {
                    // if we are going to query for grouped results we need to reset
                    // the fields list to what the user selected in template params...
                    $allFields = $fields;
                    $columnaliases[count($fields)] = 'DOCHDRNO';
                    $fields = array("DOCHDRNO");

                    // lets add the displayFieldsList
                    foreach ($displayFieldsList as $displayFld) {

                        if ($displayFld == 'ENTRYTYPE') {
                            $columnaliases[count($fields)] = 'ENTRYTYPE';
                            $fields[] = $entryType;
                        } else {
                            // we may have dummy fields in the incoming groupingFieldsList structure
                            // need to validate those and ignore them so that query runs fine...
                            if (!in_array($displayFld, $allFields)) {
                                continue;
                            }

                            // if this field is not in the query select list add it...
                            if (!in_array($displayFld, $fields)
                                && !in_array($displayFld, $sumColumns)) {
                                $columnaliases[count($fields)] = (strpos($displayFld, '.') ? '' : $displayFld);
                                $fields[] = $displayFld;
                            }
                        }
                    }

                    // lets add the groupingFieldsList
                    foreach ($groupingFieldsList as $groupFld) {

                        if ($groupFld == 'ENTRYTYPE') {
                            // since oracle doesnt allow analytical func in group by clause
                            // so we need to ignore this field
                            continue;
                        } else {
                            $tmppath = $lineManager->_ConvertExternalPath($groupFld);
                            $grpPartitionStr .= ", $tmppath ";
                        }

                        // we may have dummy fields in the incoming groupingFieldsList structure
                        // need validate those and ignore them to make sure query runs fine...
                        if (!in_array($groupFld, $allFields)) {
                            continue;
                        }

                        $orders[] = array($groupFld, 'asc');
                        if (!in_array($groupFld, $fields)) {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $columnaliases[count($fields)] = (strpos($displayFld, '.') ? '' : $groupFld);
                            $fields[] = $groupFld;
                        }
                    }

                    // so far identified fields will also be the grouping fields...
                    $groupBy = $fields;

                    // we need to define 2 sets of sum columns
                    // 1: for the summarizeable number columns like QTY, PRICE etc
                    // 2: for the same summarizeable column provide another sum value
                    //		groupedby the first groupby field selected in the list (computed subtotal)...
                    foreach ($sumColumns as $col) {
                        $columnaliases[count($fields)] = $col;
                        $fields[] = array(
                            'fields' => array($ent . '.' . $col),
                            'function' => 'SUM(NVL(${1}, 0))',
                        );
                    }

                    foreach ($sumPartitionColumns as $col) {
                        $columnaliases[count($fields)] = 'GROUPTOTAL_' . $col;
                        $fields[] = array(
                            'fields' => array($ent . '.' . $col),
                            'function' => "SUM(SUM(NVL(\${1}, 0))) OVER (PARTITION BY $ent.dochdrkey, $firstGroupingField) ",
                        );
                    }

                    if($isContractBillingEnabled && $lineManager->_entity == 'sodocumententry'){
                        $this->processPCBSummarizeForDocTemp($ent,$fields, $orders, $groupBy, $columnaliases, $groupingFieldsList) ;
                    }

                } else {

                    // default order for detail mode should be dochdrkey + line_no and then any other sorting fields...
                    // this is to keep the backward compatibility with customdocs...
                    $orders[] = array('LINE_NO', 'asc');

                    // lets add the groupingFieldsList
                    foreach ($groupingFieldsList as $groupFld) {

                        if (!in_array($groupFld, $fields)) {
                            if ($groupFld == 'ENTRYTYPE') {
                                $columnaliases[count($fields)] = 'ENTRYTYPE';
                                $fields[] = $entryType;

                                // since oracle doesnt allow analytical func in group by clause
                                // we need to ignore this field
                                continue;
                            } else {
                                $fields[] = $groupFld;
                            }
                        }

                        $tmppath = $lineManager->_ConvertExternalPath($groupFld);
                        $orders[] = array($tmppath, 'asc');
                        $grpPartitionStr .= ", $tmppath ";
                    }

                    // we need to define total columns for the number columns like QTY, PRICE etc
                    // these values will be computed for the selected grouping fields
                    foreach ($sumPartitionColumns as $col) {
                        $columnaliases[count($fields)] = 'GROUPTOTAL_' . $col;
                        $fields[] = array(
                            'fields' => array($ent . "." . $col),
                            'function' => "SUM(NVL(\${1}, 0)) OVER (PARTITION BY $grpPartitionStr ORDER BY $grpPartitionStr ) ",
                        );
                    }

                }

                if ($firstGroupingField == 'ENTRYTYPE') {
                    $firstGroupingField = $entryType;
                }

                // lets add the show_grouptotal, group identifier column (line level subtotal splitter)
                $columnaliases[count($fields)] = 'SHOW_GROUPTOTAL';
                $fields[] = array(
                    'fields' => array($firstGroupingField),
                    'function' => " (CASE WHEN LEAD(\${1}, 1) OVER (PARTITION BY $ent.dochdrkey ORDER BY $ent.dochdrkey) = \${1} THEN 'F' ELSE 'T' END ) "
                );

                $querySpec = array(
                    'selects' => $fields,
                    'columnaliases' => $columnaliases,
                    'filters' => array(
                        array(
                            array($ownedObject['fkey'], '=', $parentKey),
                        )
                    ),
                    'orders' => $orders,
                    'options' => array('noDBSorts' => true),
                );

                if ($entriesDisplay == 'SUMMARIZED' &&  (!empty($groupBy))) {
                    $querySpec['groupby'] = $groupBy;
                }

                $resultSet = $lineManager->GetList($querySpec);

                if(in_array($lineManager->_entity, array('sodocumententry', 'podocumententry'))) {

                    $docEntySubTotalsMgr = $this->GetOwnedObjectManager($lineManager->_entity.'subtotals');


                    $entrySubtotalParams = array (
                        'selects' => array (
                            'RECORDNO',
                            'DOCHDRNO',
                            'DESCRIPTION',
                            'TOTAL',
                            'ABSVAL',
                            'PERCENTVAL',
                            'TRX_TOTAL',
                            'TRX_ABSVAL',
                            'DOCENTRYKEY',
                            'TAXDETAIL'
                        ),
                    );

                    $entrySubtotalParams['filters'] = array(
                        array(
                            array('DOCHDRNO', '=', $parentKey),
                            array('DOCENTRYKEY', 'IS NOT NULL' )
                        )
                    );
                    $entrySubtotalParams['orders'] = array(array('RECORDNO', 'asc'));
                    $entrySubtotalParams['options'] = array('noDBSorts' => true);


                    $entrySubtotals = $docEntySubTotalsMgr->GetList($entrySubtotalParams);

                    foreach ( $entrySubtotals as $subtotal) {
                        $entrySubtotalsSet[$subtotal['DOCENTRYKEY']][] = $subtotal;
                    }
                }

                $hasDocEntry = in_array($lineManager->_entity, array('sodocumententry', 'podocumententry', 'invdocumententry'));
                foreach ($resultSet as $rec) {
                    if ($hasDocEntry) {
                        // ITEMALIASID is an alias for ITEMID. It would have been defined or may not.
                        // feven if it was defined customer/user may have not used it.
                        // In such cases default it to ITEMID (only item ID no name included like itemId.'--'.itemName)
                        if(!isset($rec['ITEMALIASID']) || $rec['ITEMALIASID'] == '') {
                            $rec['ITEMALIASID'] =  $rec['ITEMID'];
                            //$rec['ITEMALIASDESC'] = $rec['ITEMDESC'];
                        }

                        $rec['ITEMID'] = $rec['ITEMID'] . ($rec['ITEMNAME'] != '' ? '--' . $rec['ITEMNAME'] : '');

                        if ($rec['LOCATIONID'] != '') {
                            $rec['LOCATION'] = $rec['LOCATIONID'] . ($rec['LOCATIONNAME'] != '' ? '--' . $rec['LOCATIONNAME'] : '');
                        }

                        if ($rec['DEPARTMENTID'] != '') {
                            $rec['DEPARTMENT'] = $rec['DEPARTMENTID'] . ($rec['DEPARTMENTNAME'] != '' ? '--' . $rec['DEPARTMENTNAME'] : '');
                        }

                        if (!array_key_exists('UIVALUE', $rec)
                            && array_key_exists('GROUPTOTAL_VALUE', $rec)
                        ) {
                            $rec['UIVALUE'] = $rec['GROUPTOTAL_VALUE'];
                        }

                        if ($lineManager->mcpEnabled
                            && !array_key_exists('TRX_VALUE', $rec)
                            && array_key_exists('GROUPTOTAL_TRX_VALUE', $rec)
                        ) {
                            $rec['TRX_VALUE'] = $rec['GROUPTOTAL_TRX_VALUE'];
                        }

                        foreach ($dimFields as $field) {
                            if (!$field['standard']) {
                                continue;
                            }
                            $fieldid = strtoupper($field['path']);

                            if (!isset($obj['HEADER_' . $fieldid])) { // will be executed for the first time
                                $obj['HEADER_' . $fieldid] = $rec[$fieldid];
                            } elseif ($obj['HEADER_' . $fieldid] != $rec[$fieldid]) { // if value is not common then unset
                                $obj['HEADER_' . $fieldid] = '';
                            }
                        }
                        //Merge subtotalentry to entry/line
                        if(isset($entrySubtotalsSet[$rec['RECORDNO']])) {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $rec['SUBTOTALSENTRY'] = $entrySubtotalsSet[$rec['RECORDNO']];
                        }
                    }

                    $obj[$ownedObject['path']][] = $lineManager->FlatToStructured($rec);
                }

                if ($lineManager->_entity == 'sodocumententry' || $lineManager->_entity == 'podocumententry') {
                    $deOwnedObjects = $lineManager->GetOwnedObjects();
                    if (is_array($deOwnedObjects) && count($deOwnedObjects)>0) {
                        foreach ($obj[$ownedObject['path']]as &$deline) {
                            $lineManager->GetOwnedObjectData($deline, $deOwnedObjects);
                        }
                    }
                    unset($deline);
               }

                if (count($gErr->errors) > $cnt) {
                    return false;
                }
            }
        }

        if (isset($this->_schemas[$this->_entity]['supdocentity'])) {
            GetSupDocId($obj, $this->_schemas[$this->_entity]['supdocentity']);
        }

        $this->showSubTotals($obj);
        $this->GetDocHistory($obj);

        $obj = $this->LoadSmartlinkCalculateValues($obj);

        return $obj;
    }

    /**
     * Return a list of entities
     *
     * @param array  $params     a structure used to build the custom query
     * @param bool   $_crosscny  if true do not add the var.cny# = ... code
     * @param bool   $nocount
     *
     * @return array $newResult  - result of query
     */
    public function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        /*
         * SUPDOCID was not part of the original entity object. The create/update methods populated the supdocid field
         * by calling the SetSupDocId method using the optional supdocid parameter passed at entity creation/updation.
         * The correct way is to make SUPDOCID part of the object. However, this will require changes to all the existing
         * create/update methods for sotransaction and potransaction objects. Hence, chosing to use a similar approach
         * to populate the SUPDOCID parameter while retrieving the sotransaction/potransaction objects
         * and similar case with the WHENPOSTED.
         */
        $selectSupDocId = false;
        //$getGLPostingDate = false;
        // Fields RECORDNO, PRRECORDKEY are required to populate values for SUPDOCID and WHENPOSTED respectively.
        //This is specific changes  for XML API 2.1 get_list when only WHENPOSTED/ SUPDOCID fields passed along with
        //the request.
        $requiredSelectFields = array('RECORDNO', 'PRRECORDKEY');
        // Remove SUPDOCID & WHENPOSTED parameter if present in the input request as we do not have this field in the DB.
        if ( isset($params['selects']) && is_array($params['selects']) ) {
            foreach ($params['selects'] as $key => $val ) {
                /*if ($val == 'WHENPOSTED') {
                    unset($params['selects'][$key]);
                    $getGLPostingDate = true;
                }*/
                if ( $val == 'SUPDOCID' ) {
                    unset($params['selects'][$key]);
                    $selectSupDocId = true;
                }
            }
        }

        if ( $selectSupDocId ) {
            //Push RECORDNO, PRRECORDKEY  as part of select.
            $params['selects'] = array_unique(array_merge($params['selects'], $requiredSelectFields));
            $params['selects'] = array_values($params['selects']);
        }
        
        if ($params['doctypeRestriction'] && $this->_docType) {
            $params['filters'][0][] = [ 'DOCPARID', '=', $this->_docType ];
        }

        $resSet = parent::GetList($params, $_crosscny, $nocount);

        if ($selectSupDocId) {

            foreach ($resSet as &$rObj) {

                //collect DocID & PRRECORDKEY in temp Variable
                $tempDocIds[] = $rObj['RECORDNO'];
                $tempPrKeys[] = $rObj['PRRECORDKEY'];

            }

            if ($selectSupDocId) {
                $SupDocMapMgr = Globals::$g->gManagerFactory->getManager('supdocmaps');
                /** @noinspection PhpUndefinedVariableInspection */
                $supMaps = $SupDocMapMgr->GetListSupDocIDs($tempDocIds, $this->_schemas[$this->_entity]['supdocentity']);
            }
            /*if ($getGLPostingDate) {
                $datepostMaps = $this->GetGLPostingDateArray($tempPrKeys);
            }*/
        }

        $supIdKeys = array();
        $dateIdKeys = array();
        //Build array with
        if (!empty($supMaps)) {
            foreach ($supMaps as $val) {
                $supIdKeys[$val['RECORDID']] = $val['DOCUMENTID'];
            }

        }


        if (!empty($datepostMaps)) {
            foreach ($datepostMaps as $val) {
                $dateIdKeys[$val['RECORD#']] = $val['CREATED'];
            }
        }

        //Set the SUPPORT DOC ID & WHENPOSTED into obj
        foreach ($resSet as &$rObj) {
            if (!empty($supIdKeys)) {
                if (isset($supIdKeys[$rObj['RECORDNO']])) {
                    [$id] = explode('--', $supIdKeys[$rObj['RECORDNO']]);
                    $supIdKeys[$rObj['RECORDNO']] = $id;
                }
                $rObj['SUPDOCID'] = $supIdKeys[$rObj['RECORDNO']];
            }
            if (!empty($dateIdKeys)) {
                $rObj['WHENPOSTED'] = $dateIdKeys[$rObj['PRRECORDKEY']];
            }
            $this->calculateBalanceToFinish($rObj);
        }
        $this->formatCCOGetData($resSet);

        return $resSet;
    }

    /**
     * Hack to unset the SCMMACROLINK field to be 'SCMMACROLINK', anything other than 'STATE' else, LC estimate will fail
     * to delete old LC est adjustments on edit posting. This is to fix issue below.
     * IA-140310 - Landed cost adjustments are being posted three times
     *
     * @param array       $processed
     * @param array|false $firstRow
     *
     * @return array
     */
    public function runGetList($processed, &$firstRow = null)
    {
        foreach ($processed['COLUMN_MAP'] as $key => $columnMap) {
            foreach ($columnMap as $ckey => $val) {
                if (is_string($ckey) && $ckey == 'SCMMACROLINK') {
                    $processed['COLUMN_MAP'][$key][$ckey] = 'SCMMACROLINK';
                }
            }
        }

        return parent::runGetList($processed, $firstRow);
    }

    /**
     * @param array $values
     * @param array $getTaxRequest
     * @param string $entityTaxable
     *
     * @return bool
     */
    private function postToAvalara($values, $getTaxRequest, $entityTaxable)
    {
        $postToAvalara = ($values['_taxEngine'] ?? '') == 'AvaTax'
            && $values['_DOCPAR']['SHOW_TOTALS'] == 'true'
            && self::isDocumentInPostingState($values['STATE']);

        if (!$postToAvalara) {
            return true;
        }

        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $subtotals = $values['SUBTOTALS'];
        // if do not have at least one subtotal line that is a tax we do not need to post to Avalara
        $haveTax = false;
        foreach ($subtotals as $subtotal) {
            if ($subtotal['ISTAX'] == 'true') {
                $haveTax = true;
            }
        }

        if (!$haveTax) {
            return true;
        }

        // if for any other reason we did not compute a tax request then do not post to Avalara
        // ideally this should not happen and we could have a development error only
        if (empty($getTaxRequest)) {
            return true;
        }

        $getTaxRequest['DocNo'] = $values['DOCNO'];
        $getTaxRequest['DocRef'] = $values['DOCID'];
        $simpleFound = false;
        $avaFound = false;
        foreach ($subtotals as $subtotal) {
            foreach ($subtotal['GLENTRIES'] as $glentry) {
                if (substr($glentry['TAXDETAILKEY'], 0, strlen('SIMPLETAX')) === 'SIMPLETAX') {
                    $simpleFound = true;
                }
                if (substr($glentry['TAXDETAILKEY'], 0, strlen('AVATAX')) === 'AVATAX') {
                    $avaFound = true;
                }
            }
        }
        if ($simpleFound || !$avaFound) {
            $gErr->addIAError(
                'INV-1376', __FILE__ . ':' . __LINE__,
                'Error while sending tax data to Avalara for customer ID ' . $values['CUSTVENDID'] . '.', ['VALUES_CUSTVENDID' => $values['CUSTVENDID']],
                'Avalara was not used to calculate taxes and yet we are attempting to send invoice data to Avalara.', [],
                'Contact customer support and provide the steps followed to get this error message.', []
            );
            $ok = false;
        } else {
            // save invoice in Avalara
            import('AvaTaxEngine');
            $taxEngine = new AvaTaxEngine();
            $ok = $taxEngine->GetTax($getTaxRequest, $getTaxResult, ( $entityTaxable == 'F'), true, true, true);
            foreach ($taxEngine->errors as $error) {
                $gErr->addError($error['err_no'], __FILE__ . ':' . __LINE__, $error['msg']);
            }
            if ($ok) {
                $subscription = $gManagerFactory->getManager('imssubscription');
                $subscription->SetExternalId($values['DOCID'], $getTaxRequest['Mod'] . 'document', 'AVALARA', $getTaxResult['DocType'] . '-' . $getTaxResult['DocCode']);
            }
        }

        return $ok;
    }


    /**
     * @param string $_schema
     *
     * @return string
     */
    public function GetPrintAs( $_schema = '' )
    {
        if (isset($this->_docType) && $this->_docType != '') {
            return $this->_docType;
        } else {
            return parent::GetPrintAs($_schema);
        }
    }

    /**
     * @param  string $_schema
     *
     * @return string
     */
    public function GetPluralPrintAs( $_schema = '' )
    {
        if (isset($this->_docType) && $this->_docType != '') {
            return $this->_docType . "s";
        } else {
            return parent::GetPluralPrintAs($_schema);
        }
    }


    /**
     * This function will give the GL posting date display.
     *
     * @param   array $obj
     * @return bool
     */
    protected function GetGLPostingDate(&$obj)
    {

        if (isset($obj['PRRECORDKEY']) && $obj['PRRECORDKEY'] != '') {
            $postdate = QueryResult(
                array(
                    "SELECT CREATED FROM prbatch prbatch, prrecordmst prrecord WHERE 
                prbatch.record# = prrecord.prbatchkey AND 
                prrecord.record# = :1 AND
                prbatch.cny# = prrecord.cny# AND 
                prrecord.cny# = :2",
                    $obj['PRRECORDKEY'],
                    GetMyCompany()
                )
            );
            if (!empty($postdate[0]) && $postdate[0]['CREATED'] != '') {
                $obj['WHENPOSTED'] = $postdate[0]['CREATED'];
            }
        }

        return true;

    }


    /**
     * @param array $prRecordKeys
     *
     * @return false|string|string[][]
     */
    protected function GetGLPostingDateArray($prRecordKeys)
    {

        $datepostMap = '';
        if (!empty($prRecordKeys)) {
            $query = array('SELECT PRRECORD.RECORD#,CREATED FROM prbatch prbatch, prrecordmst prrecord WHERE
					prbatch.record# = prrecord.prbatchkey AND
					prbatch.cny# = prrecord.cny# AND
					prrecord.cny# = :1', GetMyCompany());
            $stmt = PrepINClauseStmt($query, $prRecordKeys, " AND  prrecord.record# ");
            $datepostMap = QueryResult($stmt);

        }

        return $datepostMap;

    }

    /**
     * @param array $filterAtom
     *
     * @return string
     * @throws Exception
     */
    function GetFieldTypeForFilter($filterAtom)
    {
        [ , $filterField] = explode(".", $filterAtom[0]);
        $filterField = ($filterField == $filterAtom[0] || $filterField == '' ? $filterAtom[0] : $filterField);

        switch (isl_strtoupper($filterField)) {
            case 'WHENPOSTED':
                //a hack to ensure we have data type for WHENPOSTED without adding the field to the dbschema
                $ret = 'date';
                break;
            case 'PRRECORDKEY':
            case 'INVBATCHKEY':
            case 'PRINVBATCHKEY':
            case 'ADDGLBATCHKEY':
                $ret = 'integer';
                break;
            default:
                $ret = parent::GetFieldTypeForFilter($filterAtom);
                break;
        }
        return $ret;
    }

    /**
     * @param string[] $atom
     * @param string   $_querytype
     * @param array    $qryarray
     *
     * @return string
     */
    function _ProcessWhereClause($atom, $_querytype, &$qryarray)
    {
        $whereClauseRet = parent::_ProcessWhereClause($atom, $_querytype, $qryarray);

        if (($atom[0] ?? null) == 'WHENPOSTED') {
            $doc = ($this->mod == 'po') ? 'podocument' : 'sodocument';

            $str = "(CASE
						WHEN $doc.prrecordkey IS NOT NULL
							THEN
							  (SELECT prb.created
							  FROM prrecordmst pr,
								prbatchmst prb
							  WHERE pr.cny#     = prb.cny#
							  AND pr.cny#       = $doc.cny#
							  AND pr.record#    = $doc.prrecordkey
							  AND pr.prbatchkey = prb.record#
							  )
						ELSE NULL
					END)";

            $whereClauseRet = str_replace("WHENPOSTED", $str, $whereClauseRet);
        }
        return $whereClauseRet;
    }

    /**
     * @param array $values
     * @param string $objectName   do you KNOW the object name?  Is it sodocument, say, or sodocumentENTRY?
     */
    static function getDocTypeFromValues(&$values, $objectName = '')
    {
        if (empty($values['RECORDNO']) && empty($values['DOCID'])) {
            return;
        }

        $checkForDocEntry = false;
        if (!empty($values['RECORDNO'])) {
            $where = ' dh.record# = :2 ';
            $param = $values['RECORDNO'];
            $checkForDocEntry = true;
        } else {
            $where = ' dh.docid = :2 ';
            $param = $values['DOCID'];
        }

        // assume this is for a doc header
        // but wait!  Is it really for a docENTRY record?
        if (    $checkForDocEntry &&
                in_array( $objectName, [ 'SODOCUMENTENTRY', 'PODOCUMENTENTRY', 'STKITDOCUMENTENTRY', 'RECURDOCUMENTENTRY', 'INVDOCUMENTENTRY' ]) ) {
            $qry = "SELECT 
                    dp.docid DOCTYPE 
                FROM
                    docpar   dp,
                    dochdr   dh,
                    docentry de
                WHERE
                    dh.cny#      = :1 AND
                    dp.cny#      = :1 AND
                    de.cny#      = :1 AND
                    dh.docparkey = dp.record# AND
                    de.dochdrkey = dh.record# AND
                    de.record#   = :2";
        } else {
            $qry = "SELECT 
                    dp.docid DOCTYPE 
                FROM
                    docpar dp,
                    dochdr dh 
                WHERE
                    dh.cny# = :1 AND
                    dp.cny# = :1 AND
                    dh.docparkey = dp.record# AND
                    {$where}";
        }

        $doc_type = QueryResult( [$qry, GetMyCompany(), $param] );

        $values['DOCPARID'] = $doc_type[0]['DOCTYPE'] ?? '';
    }


    /**
     * This function takes the existing values for a given object, and then clear the fields that are derived ONLY for API.
     * We can't use the standard CleanupDerivedFields method, as some of the fields marked derived are not re-populate by the Manager during an update.
     * This method clear fields on case-by-case basis, only the ones we know are causing issues and safe to clear.
     * See tickets: 33077 and 34819 in TicketMaster
     *
     * @param array  $values array set of object values (associative name/value pairs)
     *
     * @return bool true on success, false otherwise
     */
    public function API_CleanupDerivedFields(&$values)
    {
        unset($values['INTERNALINITIATEDBYKEY']);
        unset($values['INTERNALVERBALBYKEY']);
        unset($values['INTERNALISSUEDBYKEY']);
        unset($values['INTERNALAPPROVEDBYKEY']);
        unset($values['INTERNALSIGNEDBYKEY']);
        unset($values['EXTERNALVERBALBYKEY']);
        unset($values['EXTERNALAPPROVEDBYKEY']);
        unset($values['EXTERNALSIGNEDBYKEY']);
        unset($values['PERFORMANCESURETYCOMPANYKEY']);
        unset($values['PAYMENTSURETYCOMPANYKEY']);
        unset($values['PRINVBATCHKEY']);
        unset($values['ADDGLBATCHKEY']);
        return true;
    }


    /**
     * Verifies if the TD has valid create policy for creating a transaction.
     * Returns false if the TD is marked as Convert Only
     *
     * @param array  $values
     *
     * @return bool
     */
    protected function validateCreatePolicy($values)
    {
        $ok = true;
        if (!isArrayValueProvided($values, 'SCHOPKEY')) {
            $convertOnly = $values['_DOCPAR']['CREATETYPE'] == 'Convert only';
            $isConverting = (isset($values['CREATEDFROM']) && $values['CREATEDFROM'] !== '');
            $isBackOrder = $values['BACKORDER'] == 'Yes';
            if($convertOnly && !$isConverting && !$isBackOrder) {
                $msg = "Error creating transaction. This type of transactions can only be converted from another transaction.";
                Globals::$g->gErr->addIAError('INV-1310', __FILE__ . '.' . __LINE__, $msg, []);
                $ok = false;
            }
        }
        if ($ok) {
            $creationRuleConstraint = $values['_DOCPAR']['CREATION_RULE'] == 'F';
            /** @noinspection PhpUndefinedVariableInspection */
            if( $creationRuleConstraint && !$isBackOrder) {
                $msg = "Error creating transaction. The 'Create transaction in' field setting prevents creating this type of transaction.";
                Globals::$g->gErr->addIAError('INV-1311', __FILE__ . '.' . __LINE__, $msg, []);
                $ok = false;
            }
        }
        return $ok;
    }

    /**
     * To get the tax engine
     *
     * @param array $obj document values
     * @param bool &$isVatEnabled pass by reference variable
     * @param bool &$isAvaEnabled
     *
     * @return string
     */
    protected function getTaxEngine(
        /** @noinspection PhpUnusedParameterInspection */ $obj,
        /** @noinspection PhpUnusedParameterInspection */ &$isVatEnabled,
        /** @noinspection PhpUnusedParameterInspection */ &$isAvaEnabled)
    {
        return '';
    }


    /**
     * To delete the transactions from partner/Avalara
     *
     * @param array $docObj document values
     *
     * @return bool
     */
    protected function DeletePartnerRecord(/** @noinspection PhpUnusedParameterInspection */ $docObj)
    {
        return true;
    }

    /**
     * @param Lock[]  $locks
     * @param array $values
     *
     * @return bool
     */
    private function acquireLocksIfNecessary(&$locks, $values)
    {
        $ok = true;
        $locks = [];

        // Acquire lock for editing
        if ($values['RECORDNO']) {
            $editlock = new Lock();
            $lockName = GetMyCompany() . '_DOCUMENT_' . $values['RECORDNO'];
            if ($editlock->lockHeld($lockName) || !$editlock->setLock($lockName, 10800, false)) {
                $gErr = Globals::$g->gErr;
                $msg = "Another user is currently working on this transaction. Wait a few minutes, and then try again";
                $gErr->addIAError('INV-1378', __FILE__ . '.' . __LINE__, "Unable to access transaction", [], $msg, []);
                return false;
            }
            $locks[] = $editlock;
        }

        $this->checkIsCreatedFromMultipleSourceDocuments($values, $sourceDocKeys, $sourceDocIds);
        if ((!empty($sourceDocKeys)) && $values['BACKORDER'] != 'Yes') {
            sort($sourceDocKeys);   // sort to avoid deadlocks
            $baseLockName = GetMyCompany() . '_DOCUMENT_';
            foreach ($sourceDocKeys as $sourceDocKey) {
                $lock = new Lock();
                $lockName = $baseLockName . $sourceDocKey;
                if (!$lock->setLock($lockName, 10800, false)) {
                    $msg = "Error processing request. "
                        ."Two simultaneous Conversion process on same document being performed "
                        . $sourceDocIds[$sourceDocKey];
                    Globals::$g->gErr->addIAError('INV-1312', __FILE__ . '.' . __LINE__, $msg, ['SOURCE_DOC_IDS_SOURCE_DOC_KEY' => $sourceDocIds[$sourceDocKey]]);
                    LogToFile("\n\n\$msg\n" . "Sourcedockey: " . $sourceDocKey . "\n\n");
                    $ok = false;
                    break;
                }
                $locks[] = $lock;
            }
        }
        if (!$ok) {
            $this->releaseLocksIfNecessary($locks);
        }
        return $ok;
    }

    /**
     * @param Lock[] $locks
     */
    private function releaseLocksIfNecessary($locks)
    {
        foreach ($locks as $lock) {
            $lock->releaseLock();
        }
    }

    /**
     * Get the Manager class for entry subtotals
     *
     * @return string|null
     */
    protected function getEntrySubtotalsEntity()
    {
        return null;
    }


    /**
     * Get the primary Dimension
     * OE and PO have only one PRIMARYDIMENSION and Nothing for Inv
     *
     * @param  string $primaryDimension    primary dimension.
     * @param  string $primaryDimensionVal value collected from transaction for primary dimension.
     * @param  array  $entryPart           element of entry array.
     */
    protected function prepLinePrimaryDimensions($primaryDimension, $primaryDimensionVal, &$entryPart)
    {
    }


    /**
     * Update GL Posting date from API 2.1
     *
     * @param  array $values values.
     *
     * @return bool
     */
    function PartialUpdateDocument(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        return true;
    }

    /**
     * @param array $values
     * @param bool  $newdoc
     *
     * @return bool
     */
    function PrepDocumentSequenceNo(&$values, $newdoc)
    {
        global $gErr;
        $ok = true;
        // If this is an Add, get the next record#
        if ($newdoc) {
            $nextId = $this->GetNextRecordKey();
            $ok = $ok && isset($nextId);
            $values[':record#'] = $values['RECORDNO'] = $nextId;
            $values['CREATEDUSER'] = GetMyUserid(); // added for createdby
            $values['AUWHENCREATED'] = IADateTime::getCurrentUTCTimestamp();

            // Get next sequence number for this type for document
            if ($values['BACKORDER'] == 'Yes' || (isset($values['_DOCPAR']['SEQUENCE']) && '' !== $values['_DOCPAR']['SEQUENCE']) || $values['_DOCPAR']['SALE_PUR_TRANS'] == 'TimeBill') {
                $ok = $ok && $this->ProcessSequenceNumber($values);
            } else {
                if ($this->isDocumentNumberDuplicate($values['_DOCPAR']['DOCID'], $values['DOCNO'])) {
                    $docno = $values['DOCNO'];
                    $gErr->addIAError(
                        'INV-1379', __FILE__ . ':' . __LINE__,
                        "Document Number $docno already used", ['DOCNO' => $docno],
                        '', [],
                        "Make desired changes and press Save to continue.", []
                    );
                    $ok = false;
                } else {
                    $values['DOCID'] = $values['_DOCPAR']['DOCID'] . "-" . $values['DOCNO'];
                    $ok = $ok && isset($values['DOCNO']) && isset($values['DOCID']);
                    if (!$ok) {
                        $gErr->addIAError('INV-0025', __FILE__ . ':' . __LINE__, "Document Number Missing", [], '', [], "Make desired changes and press Save to continue.", []);
                    }
                }
            }
        }else {
            //Does not allow to update docno.
            if($values['DOCNO'] !=  $values['EXISTING_DOC']['DOCNO']) {
                $msg = "Document number can not be changed from " . $values['EXISTING_DOC']['DOCNO'] . " to " . $values['DOCNO'] . " for Existing Document";
                $gErr->addIAError(
                    'INV-1380', __FILE__ . ":" . __LINE__,
                    "Invalid User Action", [],
                    $msg, ['VALUES_EXISTING_DOC_DOCNO' => $values['EXISTING_DOC']['DOCNO'], 'VALUES_DOCNO' => $values['DOCNO']]
                );
                $ok = false;
            }
        }

        return $ok;

    }

    /**
     * Purpose :   wrapper function to execute soSubtotals->CalcSubTotals
     *
     * @param array $docvalues
     */
    function calcSubTotals(/** @noinspection PhpUnusedParameterInspection */ &$docvalues)
    {
        throw new Exception(__METHOD__ . " must be overridden");
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function subtotalsForBlob(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        // PhpStorm inspection workaround
        if (1) {
            throw new Exception(__METHOD__ . " must be overridden");
        }
        /** @noinspection PhpUnreachableStatementInspection */
        return false;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function subtotalsForCustomDocBlob(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        // PhpStorm inspection workaround
        if (1) {
            throw new Exception(__METHOD__ . " must be overridden");
        }
        /** @noinspection PhpUnreachableStatementInspection */
        return false;
    }

    /**
     * @param string $docID
     *
     * @return bool
     */
    private static function isRetainageReleased($docID)
    {
        if(!CRESetupManager::isCREInstalled()) {
            return false;
        }
        $stmt = array();
        $stmt[] = "SELECT prrecord.recordtype, prrecord.trx_totalreleased from prrecord, dochdrmst dochdr where dochdr.cny# = :1 and dochdr.docid = :2 and prrecord.cny# = :1 and prrecord.record# = dochdr.prrecordkey";
        $stmt[] = GetMyCompany();
        $stmt[] = $docID;

        $res = QueryResult($stmt);
        $res = $res[0];

        if (!empty($res)) {
            if ($res['RECORDTYPE'] == 'pi' && !CRESetupManager::isAPRetainageEnabled()){
                return false;
            }
            if ($res['RECORDTYPE'] == 'ri' && !CRESetupManager::isARRetainageEnabled()){
                return false;
            }
            if (!isNullOrBlank($res['TRX_TOTALRELEASED']) && $res['TRX_TOTALRELEASED'] > 0) {
                return true;
            }
        }

        return false;
    }

    /**
     * @param string $docID
     *
     * @return bool
     */
    public static function isDocumentPrinted($docID)
    {
        $stmt = array();
        $stmt[] = "SELECT printed from dochdr where cny# = :1 and docid = :2";
        $stmt[] = GetMyCompany();
        $stmt[] = $docID;

        $res = QueryResult($stmt);
        $res = $res[0];

        if (!empty($res) && $res['PRINTED'] == 'T') {
            return true;
        }

        return false;
    }

    /**
     * @param string $docID
     *
     * @return bool
     */
    public static function isDocumentPaid($docID)
    {
        $stmt = array();
        $stmt[] = "SELECT NVL(pr.trx_totalpaid, 0) totalpaid
                 FROM dochdr dh
                 INNER JOIN prrecord pr ON pr.cny# = dh.cny# AND pr.record# = dh.prrecordkey
                 WHERE dh.cny# = :1 AND docid = :2";
        $stmt[] = GetMyCompany();
        $stmt[] = $docID;

        $res = QueryResult($stmt);
        $res = $res[0];

        if (!empty($res) && $res['TOTALPAID'] != 0) {
            return true;
        }

        return false;
    }

    /**
     * @param bool $enable
     */
    protected function setTrigger( $enable )
    {
        // ExecStmt("BEGIN acct_Utils. Trigger_Enabled := 'F'; END;");
        /* disable or enable trigger for this session */
        $f = ($enable ? 'T' : 'F');
        $stmtstr = "begin DBMS_APPLICATION_INFO.SET_CLIENT_INFO('$f'); end;";
        $ret = ExecStmt([ $stmtstr ], 0);
        if ($ret == 0) {
            $msg = "Cannot disable triggers.";
            logDBACopy($msg);
            Globals::$g->gErr->addIAError('INV-1313', __FILE__ . ':' . __LINE__, $msg, []);
        }
    }

    /**
     * @param bool $enable
     */
    protected function setSCMTrigger($enable)
    {
        /* disable or enable trigger for this session */
        $f = ($enable ? 'T' : 'F');
        $res = ExecSimpleStmt("BEGIN INV_UTILS.IsDocReposting := '$f'; END;");
        if (!$res) {
            $msg = "Cannot disable SCM triggers.";
            logDBACopy($msg);
            Globals::$g->gErr->addIAError('INV-1429', __FILE__ . ':' . __LINE__, $msg, []);
        }
    }

    /**
     * Mark the document as printed
     *
     * @param string $docid
     *
     * @return bool  true if success and false otherwise
     *
     * @see EmailPrintHandler::markDocumentAsPrinted()
     */
    public function markDocumentAsPrinted($docid)
    {
        global $_userid;
        $source = "DocumentManager::markDocumentAsPrinted";
        [$currentUserRec] = explode('@', $_userid);
        // Get current sysdate with time in GMT
        $currentDate = GetTimestampGMT();

        $ok = $this->_QM->beginTrx($source);
        // Need to disable the trigger 'IsDocReposting' flag to avoid the LASTUPDATED, requestid fields update from TRIGGER BRDU_DOCHDR
        // Avoiding these two case related to edit mode print/email and smart event email to include attachment asynchronous
        // Because when a user try to print the document in edit mode and in same window without refreshing
        // user try to modify the document fields and post this will end up with an error due to version changes
        // Still these whenmodified, modifiedby fields will update from TRIGGER BRU_DOCHDR
        $this->setSCMTrigger(false);
        $ok = $ok && $this->DoQuery('QRY_DOCUMENT_MARK_AS_PRINTED', [$currentUserRec, $currentDate, $docid]);
        $this->setSCMTrigger(true);
        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function preSetFast(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        $this->setSCMTrigger(false);
        return true;
    }

    /**
     * For applications to determine the post fast update condition
     * Fast Update will be aborted and rolled back if return false
     *
     * @param array $values the input values to update opeartion
     *
     * @return bool true if the current record supports fast updates given the input $values
     * @see EntityManager::entityManagerSetFull
     */
    protected function postSetFast(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        $this->setSCMTrigger(true);
        return true;
    }

    /**
     * @param string $docID
     *
     * @return bool
     */
    /**
     * @param string   $docID
     * @param string   $docstate
     * @param string[] $additionalEditableStates
     *
     * @return bool
     */
    private function isDocumentInEditableState($docID, &$docstate, $additionalEditableStates = array())
    {
        $params = array();
        $params['selects'] = array('STATE', 'HASCHANGE');
        $params['usemst'] = true;
        $params['filters'] = array(array(array('DOCID', '=', $docID)));
        $params['nodbfilters'] = true;

        $res = $this->GetList($params);
        $res = $res[0];

        $docstate = $res['STATE'];
        $editableStates = array(
            self::PENDING_STATE,
            self::PARTIALLY_CONVERTED_BY_LINE_STATE,
            self::DRAFT_STATE,
            self::CLOSED_STATE,
            self::DECLINED_STATE,
            self::APPROVED_STATE,
            self::EXCEPTION_STATE,
            self::ANALYZING_STATE,
        );
        $editableStates = array_merge($editableStates, $additionalEditableStates);

        if (!empty($res) && in_array($res['STATE'], $editableStates)) {
            return true;
        }

        $creinstalled = CRESetupManager::isCREInstalled();
        if($creinstalled && $this->canEditConvertDoc == true){
            if($this->mod == "po" || $this->mod == "so"){
                $editableStates = array_merge($editableStates, [self::CONVERTED_STATE,self::PARTIALLY_CONVERTED_STATE,self::CONVERTED_BY_LINE_STATE, self::INPROGRESS_STATE]);
                if (!empty($res) && in_array($res['STATE'], $editableStates)) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * @param string $docID
     *
     * @return string[][]
     */
    private static function getDocumentEditDeletePolicies($docID)
    {
        $stmt = array();
        $stmt[] = "SELECT nvl(dplatest.edittype, dp.edittype) edittype, nvl(dplatest.deltype, dp.deltype) deltype, 
                    nvl(dplatest.updgl, dp.updgl) updgl
                  FROM dochdr dh
                  INNER JOIN docpar dp ON dp.cny# = dh.cny# AND dp.record# = dh.docparkey
                  LEFT OUTER JOIN docpar dplatest ON dplatest.cny# = dp.cny# AND dplatest.record# = dp.latestversionkey
                  WHERE dh.cny# = :1 AND dh.docid = :2 ";

        $stmt[] = GetMyCompany();
        $stmt[] = $docID;

        $res = QueryResult($stmt);
        self::checkForAdditionalPolicy($res);
        $res = $res[0];

        return $res;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function getDocumentParams(&$values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        $docparMgr = $this->get_docpar_manager();

        if (!isset($values['_DOCPAR']) || $values['_DOCPAR'] == '') {
            
            $docpar = $docparMgr->GetLatest($values['DOCPARID'], false);

            if (empty($docpar)) {
                $msg = "Invalid transaction definition " . $values['DOCPARID'] . " given with this document";
                $gErr->addIAError('INV-1314', __FILE__ . ':' . __LINE__, $msg, ['VALUES_DOCPARID' => $values['DOCPARID']]);
                $ok = false;
            }
            $values['DOCPARKEY'] = $docpar['RECORDNO'];
            $values['_DOCPAR'] = $docpar;
        }

        return $ok;
    }

    /**
     * @param array $values
     * @param bool  $isUpdate
     *
     * @return bool
     */
    protected function validateAuthorization(&$values, $isUpdate = false)
    {
        if ($this->systemUpdate) {
            return true;
        }

        $ok = $this->isDocTypeAllowed($values['_DOCPAR']);

        $ok = $ok && MESetupManager::validateAllowTopLevel();

        if ($isUpdate) {

            $creinstalled = CRESetupManager::isCREInstalled();
            if($creinstalled && ($this->mod == "po" || $this->mod == "so")){ // checking for cre and mod for purchase and order entry
                $this->canEditConvertDoc = true; // setting var canEditConvertDoc to true,so that in isDocumentInEditableState it allows converted doc to edit.
            }

            if ($values['__feed_From'] !== "System") {
                $ok = $ok && $this->canEdit($values['DOCID'], true);
            }
            $ok = $ok && $this->IsTranAllowedforUser($values, $values['REVIEWACTION']);
        } else {
            if (!$this->validateCreatePolicy($values)) {
                return false;
            }

            $ok = $ok && $this->IsTranAllowedforUser($values, $values['BACKORDER']);
        }

        return $ok;
    }

    /**
     * Additional validation check for ownership
     * @param string $docID
     *
     * @return bool
     */
    public function checkOwnership($docID)
    {
        $query = "SELECT B.LOCLEVEL, B.LOCATION_NO, B.ENTITY#, B.ENTITY_NO
                  FROM dochdr A, SESSIONLOC B
                  WHERE A.cny#                  = B.CNY#
                    AND NVL(A.MELOCATIONKEY,0)  = B.LOCATIONKEY
                    AND A.cny#                  = :1
                    AND A.docid                 = :2";

        $resultSet = QueryResult([$query, GetMyCompany(), $docID]);

        if (IsMultiEntityCompany()) {
            if (sizeof($resultSet) == 0) {
                Globals::$g->gErr->addIAError('INV-0026', __FILE__ . ":" . __LINE__, "You can not edit document owned by another entity.", []);
                return false;
            } else if ($resultSet[0]['LOCLEVEL'] == -1) {
                Globals::$g->gErr->addIAError('INV-0027', __FILE__ . ":" . __LINE__, "You can not edit document owned at the root level.", []);
                return false;
            }
        }

        return true;
    }

    /**
     * Check if the Document is allowed to create.
     * This function checks whether a document is active or
     * inactive and if user is having permission to create a transaction
     *
     * @param array $docpar
     *
     * @return bool
     */
    function isDocTypeAllowed($docpar)
    {
        $transactionType = $docpar['DOCID'];

        $isTransTypeActive = ($docpar['STATUS'] == 'active');

        if (!$isTransTypeActive) {
            Globals::$g->gErr->addIAError(
                'INV-1381', __FILE__ . ":" . __LINE__,
                "The transaction definition Status for " . $transactionType . " is inactive .", ['TRANSACTION_TYPE' => $transactionType]
            );
            return false;

        } else {
            if ($docpar['USERPERM'] == 'true') {
                global $MODNAME, $POLNAME, $_userid;
                $t = explode('@', $_userid);
                $userkey = array_shift($t);
                $isSystemUser = (isset($userkey) && $userkey == -1) ?? false;
                $fs = new FSEntityManager();
                if (!$isSystemUser && !$fs->IsPathAllowedForUser($transactionType, $userkey, $MODNAME, $POLNAME)) {
                    Globals::$g->gErr->addIAError(
                        'INV-1382', __FILE__ . ":" . __LINE__,
                        "The user does not have permission to create or update " . $transactionType . " transaction .", ['TRANSACTION_TYPE' => $transactionType]
                    );
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * @param array $policy
     */
    protected static function checkForAdditionalPolicy(&$policy)
    {
        $kAFRid = Globals::$g->kAFRid;
        if ( IsModuleIdInstalled($kAFRid) ) {
            if ( isset($policy[0]['UPDGL']) && $policy[0]['UPDGL'] !== 'N' ) {
                $pref = GetPreferenceForProperty($kAFRid, 'DISABLEEDIT');
                if ( $pref === "true" ) {
                    $policy[0]['EDITTYPE'] = 'D';
                }

                $pref = GetPreferenceForProperty($kAFRid, 'DISABLEDELETE');
                if ( $pref === "true" ) {
                    $policy[0]['DELTYPE'] = 'D';
                }
            }
        }
    }
    
    /**
     * @param string      $docID
     * @param bool        $throwError
     *
     * @return bool
     */
    public function canEdit($docID, $throwError = false)
    {
        $ok = true;
        $errMsg = '';
        $errorCode = '';
        $placeholder = [];
        $docstate = null;

        // get Edit policy of the document
        $editPolicies = self::getDocumentEditDeletePolicies($docID);

        // 'N' => 'No Edit'
        // donot allow to edit document if document type edit policy is 'No Ediit'
        if ( $editPolicies['EDITTYPE'] == 'N' ) {
            $errMsg = "This document is not editable because the edit policy is set to 'No Edit'.";
            $errorCode = 'INV-1392';
            $ok = false;
        }

        // allow editing
        // if document is in editable state
        $additionalEditableStates = array(self::PARTIALLY_CONVERTED_STATE, self::SUBMITTED_STATE);
        if ( $ok && !$this->isDocumentInEditableState($docID, $docstate, $additionalEditableStates) ) {
            $errMsg = "Can not update a document that is '" . $docstate . "' state.";
            $errorCode = 'INV-1393';
            $placeholder = ['DOCSTATE' => $docstate];
            $ok = false;
        }

        // allow editing
        // if document is not 'Printed' and the edit policy is 'Before Printing'
        // 'P' => 'Before Printing'
        if ( $ok && $editPolicies['EDITTYPE'] == 'P' && self::isDocumentPrinted($docID) ) {
            $errMsg = "This document is not editable because it is in printing state and the edit policy is set to 'Before Printing'.";
            $errorCode = 'INV-1394';
            $ok = false;
        }

        // Do not allow editing source documents that have had retainage released
        if ( $ok && self::isRetainageReleased($docID) && !$this->hasChangeFlagIsSet($docID)) {
            $errMsg = "This document is not editable because retained invoices have been created against the original invoice.  In order to edit or delete this document, all released retainage invoices must be deleted.";
            $errorCode = 'INV-1395';
            $ok = false;
        }

        // Only allow editing if document is in the "Draft" state and the edit policy is "Edit in Draft Only"
        // This checks for the negative since the default return of this function is to allow editing
        if ($ok && $editPolicies['EDITTYPE'] == "D" && !$this->isDraftDocument(['STATE' => $docstate])) {
            $errMsg = "This document is not editable because it isn't in the draft state and the edit policy is set to 'Edit in Draft Only'.";
            $errorCode = 'INV-1396';
            $ok = false;
        }

        if (!$ok && $throwError && $errMsg != '') {
            Globals::$g->gErr->addIAError($errorCode, __FILE__ . ":" . __LINE__, $errMsg, $placeholder);
        }

        return $ok;
    }

    /**
     * @param string      $docID
     * @param bool        $throwError
     *
     * @return bool
     */
    public function validateDocumentRepost($docID, $throwError = false)
    {
        $ok = true;
        $errMsg = '';
        $errorCode = '';
        $placeholder = [];

        if ($this->systemUpdate) {
            return true;
        }

        // get Edit policy of the document
        $editPolicies = self::getDocumentEditDeletePolicies($docID);
        // 'N' => 'No Edit'
        // donot allow to edit document if document type edit policy is 'No Ediit'
        if ( $editPolicies['EDITTYPE'] == 'N' ) {
            $errMsg = "This document is not editable because the edit policy is set to 'No Edit'.";
            $errorCode = 'INV-1008';
            $ok = false;
        }

        // check the additional preferences in the Document Type
        // RESTRICT_EDITING_IN_UI

        // allow editing
        // if document is in editable state
        $additionalEditableStates = [self::SUBMITTED_STATE];

        if ( $ok && !$this->isDocumentInEditableState($docID, $docstate, $additionalEditableStates) ) {
            $errMsg = "Can not update a document that is '" . $docstate . "' state.";
            $errorCode = 'INV-1009';
            $placeholder = ['DOCSTATE' => $docstate];
            $ok = false;
        }

        // Do not allow editing source documents that have had retainage released
        if ( $ok && self::isRetainageReleased($docID) && !$this->hasChangeFlagIsSet($docID)) {
            $errMsg = "This document is not editable because retained invoices have been created against the original invoice.  In order to edit or delete this document, all released retainage invoices must be deleted.";
            $errorCode = 'INV-1011';
            $ok = false;
        }

        // allow editing
        // if document is not 'Printed' and the edit policy is 'Before Printing'
        // 'P' => 'Before Printing'
        if ( $ok && $editPolicies['EDITTYPE'] == 'P' && self::isDocumentPrinted($docID) ) {
            $errMsg = "This document is not editable because it is in printing state and the edit policy is set to 'Before Printing'.";
            $errorCode = 'INV-1010';
            $ok = false;
        }

        // allow editing
        // if document is not paid
        if ( $ok && self::isDocumentPaid($docID)) {
            $errMsg = "Invalid Document State. Can not update a document that is paid.";
            $errorCode = 'INV-1397';
            $ok = false;
        }

        if (!$ok && $throwError && $errMsg != '') {
            Globals::$g->gErr->addIAError($errorCode, __FILE__ . ":" . __LINE__, $errMsg, $placeholder);

            if (!empty($this->_reasonsForRePost)) {
                //'Transaction is re-posting because of the following reason',
                foreach ($this->_reasonsForRePost as $key => $reason) {
                    Globals::$g->gErr->addIAError(
                        $this->_reasonsForRePostIADetails[$key]['errorCode'],
                        __FILE__ . ":" . __LINE__,
                        'Updates are prevented because the transaction needs reposting.', [],
                        $reason, $this->_reasonsForRePostIADetails[$key]['placeholder']
                    );
                }
            }
        }

        return $ok;
    }

    /**
     * If a document is updated from API, copy old overridden tax values if no tax related changes
     * If a document is converted from API, copy converted from overridden tax values if no tax related changes
     *
     * @param array $values
     * @param bool $newdoc
     */
    protected function copyOverridenTaxValues(&$values, $newdoc){

        //IF there is no change in tax affecting fields, copy existingoverridetax value
        //For documents created from Process transactions
        $isVATSubscribed = $this->isVATEnabled($values);
        if ( $isVATSubscribed && $newdoc && !empty($values['CREATEDFROM'])
            && $values['CREATEDFROM'] == 'Multiple Source Documents')
        {
            $sourceDocIds = array();
            foreach ((($values['ENTRIES']) ?? []) as $entry)
            {
                $sourceDocIds[] = $entry['SOURCE_DOCKEY'];
            }
            $documentsubtotalMgr = $this->getDocSubTotalsManager(true);
            $filter              = array(
                'filters' => array(
                    array(
                        array('DOCHDRNO', 'IN', $sourceDocIds),
                        array('OVERRIDETAXVALUE', '=', 'true'),
                    )
                ),
            );
            $subtotalList        = $documentsubtotalMgr->GetList($filter);
            if (!empty($subtotalList))
            {
                $subtotalMap = $this->prepareSubtotalsMap($subtotalList);
                $filter      = array(
                    'filters' => array(
                        array(
                            array('DOCHDRNO', 'IN', $sourceDocIds),
                        )
                    ),
                );
                $oldValues   = Globals::$g->gManagerFactory
                    ->getManager('documententry', false, array( 'DOCTYPE' => $this->_docType))
                    ->GetList($filter);
                if (!is_null($values['ENTRIES']))
                {
                    foreach ($values['ENTRIES'] as &$entry)
                    {
                        foreach ($oldValues as $oldentry)
                        {
                            if ($entry['SOURCE_DOCKEY'] == $oldentry['DOCHDRNO']
                                && $entry['SOURCE_DOCLINEKEY'] == $oldentry['RECORDNO']
                                && $entry['UIQTY'] == $oldentry['UIQTY']
                                && $entry['UIPRICE'] == $oldentry['UIPRICE']
                                && $entry['TRX_PRICE'] == $oldentry['TRX_PRICE']
                                && $entry['UIVALUE'] == $oldentry['UIVALUE']
                                && $entry['TRX_VALUE'] == $oldentry['TRX_VALUE']
                            )
                            {
                                $entry['SUBTOTALSENTRY'] = $this->copyOverridenSubtotal($subtotalMap[$oldentry['DOCHDRNO']][$oldentry['RECORDNO']]);
                            }
                        }
                    }
                }
            }
        }//IF there is no change in tax affecting fields, copy existingoverridetax value
        else if ($isVATSubscribed && (!$newdoc || ($newdoc && !empty($values['CREATEDFROM'])))) {
            $contact = $this->mod == 'so' ? 'SHIPTO' : 'BILLTO';
            //If conversion get converted from doc values else get existing values of the doc itself
            if ($newdoc && !empty($values['CREATEDFROM'])) {
                $oldValues = $this->Get($values['CREATEDFROM']);
            } else {
                $oldValues = $values['EXISTING_DOC'];
                $oldValues['ENTRIES'] = $values['EXISTING_ENTRIES'];
            }
            //Check for header values change
            $isValuesChanged = true;
            if ($values['CUSTVENDID'] == $oldValues['CUSTVENDID'] &&
                $values['EXCHRATE'] == $oldValues['EXCHRATE'] &&
                $values['EXCHRATEDATE'] == $oldValues['EXCHRATEDATE'] &&
                $values['CURRENCY'] == $oldValues['CURRENCY'] &&
                $values['BASECURR'] == $oldValues['BASECURR'] &&
                $values[$contact]['CONTACTNAME'] == $oldValues[$contact]['CONTACTNAME']
            ) {
                $isValuesChanged = false;
            }
            if (!$isValuesChanged) {
                $documentsubtotalMgr = $this->getDocSubTotalsManager(true);
                $filter = array(
                    'filters' => array(
                        array(
                            array('DOCHDRNO', '=', $oldValues['RECORDNO']),
                            array('OVERRIDETAXVALUE', '=', 'true'),
                        )
                    ),
                );
                $subtotalList = $documentsubtotalMgr->GetList($filter);
                if (!empty($subtotalList)) {
                    $subtotalMap = $this->prepareSubtotalsMap($subtotalList);
                    //Check for line level values change
                    if (!is_null($values['ENTRIES'])) {
                        foreach ($values['ENTRIES'] as &$lineItem) {
                            $lineNo = !empty($lineItem['SOURCE_DOCLINEKEY']) ? $lineItem['SOURCE_DOCLINEKEY'] :
                                $lineItem['LINE_NO'];
                            $lineVar = !empty($lineItem['SOURCE_DOCLINEKEY']) ? 'RECORDNO' : 'LINE_NO';
                            foreach ((($oldValues['ENTRIES']) ?? []) as $oldLineItem) {
                                if ($lineNo == $oldLineItem[$lineVar]) {
                                    //Check if the overridden tax value is changed
                                    $isOverrideFromUI = $this->isOverriddenTaxChanged($lineItem['SUBTOTALSENTRY'],
                                        $subtotalMap[$oldLineItem['DOCHDRNO']][$oldLineItem['RECORDNO']]);
                                    if (explode("--", $oldLineItem['ITEMID'])[0] == $lineItem['ITEMID'] &&
                                        $lineItem['UIQTY'] == $oldLineItem['UIQTY'] &&
                                        $lineItem['UNIT'] == $oldLineItem['UNIT'] &&
                                        $lineItem['UIPRICE'] == $oldLineItem['UIPRICE'] &&
                                        $lineItem['TRX_PRICE'] == $oldLineItem['TRX_PRICE'] &&
                                        $lineItem['UIVALUE'] == $oldLineItem['UIVALUE'] &&
                                        $lineItem['TRX_VALUE'] == $oldLineItem['TRX_VALUE']
                                        && ($this->_fromAPI || !$isOverrideFromUI)
                                    ) {
                                        $lineItem['SUBTOTALSENTRY'] = $this->copyOverridenSubtotal($subtotalMap[$oldLineItem['DOCHDRNO']][$oldLineItem['RECORDNO']]);
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * Method to reset overridden tacflag to flase
     *
     * @param array $values
     */
    private function resetOverridenTaxValues(&$values)
    {
        if(!is_null($values['ENTRIES']))
        {
            foreach ($values['ENTRIES'] as &$entry)
            {
                foreach ($entry['SUBTOTALSENTRY'] as &$subtotal)
                {
                    $subtotal['OVERRIDETAXVALUE'] = false;
                }
            }
        }

    }

    /**
     * Method to reset overridden taxes
     *
     * @param array $values
     */
    public function resetVatTaxValues(&$values)
    {
        $hasTax = false;
        if (!empty($values['_DOCPAR']['DOCPAR_SUBTOTAL'])) {
            foreach ($values['_DOCPAR']['DOCPAR_SUBTOTAL'] as $subtotal) {
                if ($subtotal['ISTAX'] == 'true') {
                    $hasTax = true;
                    break;
                }
            }
        }
        if (!$hasTax) {
            if (!is_null($values['ENTRIES'])) {
                foreach ($values['ENTRIES'] as &$entry) {
                    unset($entry['SUBTOTALSENTRY']);
                    unset($entry['PERCENTVAL']);
                    unset($entry['TRX_TAXABSVAL']);
                    unset($entry['TAXABSVAL']);
                    $entry['TRX_LINETOTAL'] = $entry['TRX_VALUE'];
                    $entry['LINETOTAL'] = $entry['VALUE'];
                }
            }
            $taxFields = ['TAXSOLUTIONKEY', 'TAXSOLUTIONID', 'SHOWMULTILINETAX', 'TAXMETHOD', '_taxEngine'];
            foreach ($taxFields as $taxField) {
                if (isset($values[$taxField])) {
                    unset($values[$taxField]);
                }
            }
        }
    }

    /**
     * @param array $oldSubTotals
     *
     * @return array
     */
    private function copyOverridenSubtotal($oldSubTotals)
    {
        $subtotalEntry = array();
        foreach ($oldSubTotals as $subtotal) {
            if (!empty($subtotal['TAXDETAIL'])) {
                $subtotalEnt['TRX_ABSVAL'] = $subtotal['TRX_ABSVAL'];
                $subtotalEnt['ABSVAL'] = $subtotal['ABSVAL'];
                $subtotalEnt['TAXDETAIL'] = $subtotal['TAXDETAIL'];
                $subtotalEnt['PERCENTVAL'] = $subtotal['PERCENTVAL'];
                if (!empty($subtotal['OVERRIDENTAXDETAIL'])) {
                    $subtotalEnt['OVERRIDETAXVALUE'] = 'true';
                    $subtotalEnt['OVERRIDENTAXDETAIL'] = $subtotal['OVERRIDENTAXDETAIL'];
                    $subtotalEnt['SYSTEMTAXDETAILKEY'] = $subtotal['SYSTEMTAXDETAILKEY'];
                    $subtotalEnt['SYSTEMTAXDETAILID'] = $subtotal['SYSTEMTAXDETAILID'];
                }
                $subtotalEntry[] = $subtotalEnt;
            }
        }
        return $subtotalEntry;
    }

    /**
     * Checks whether overriden tax values are changed
     *
     * @param array $newSubtotals
     * @param array $oldSubtotals
     *
     * @return bool
     */
    private function isOverriddenTaxChanged($newSubtotals, $oldSubtotals)
    {
        $taxField = $this->_ismcpEnabled ? 'TRX_ABSVAL' : 'ABSVAL';
        foreach ($newSubtotals as $newSubtotal) {
            if (empty($oldSubtotals[$newSubtotal['TAXDETAIL']]) || (!empty($newSubtotal['TAXDETAIL'])
                    && !empty($oldSubtotals[$newSubtotal['TAXDETAIL']])
                    && $oldSubtotals[$newSubtotal['TAXDETAIL']][$taxField] != $newSubtotal[$taxField])) {
                return true;
            }
        }
        return false;
    }

    /**
     * @param array $subtotals
     *
     * @return array
     */
    private function prepareSubtotalsMap($subtotals)
    {
        $subTotalMap = array();
        foreach ($subtotals as $subtotal) {
            $subTotalMap[$subtotal['DOCHDRNO']][$subtotal['DOCENTRYKEY']][$subtotal['TAXDETAIL']] = $subtotal;
        }
        return $subTotalMap;
    }

    /**
     * @param array $line
     *
     * @return bool
     */
    private function validateOverriddenTax($line)
    {
        $lineNo = $line['_isNewLine'] ? $line['LINENO'] + 1 : $line['LINE_NO'] + 1;
        foreach ($line['SUBTOTALSENTRY'] as $subtotal) {
            $taxAmt = $this->_ismcpEnabled ? $subtotal['TRX_ABSVAL'] : $subtotal['ABSVAL'];
            //Should not use empty for taxAmt validation, '0' tax is possible
            if (!empty($subtotal['TAXDETAIL']) && $subtotal['OVERRIDETAXVALUE'] === 'true'
                && (!isset($taxAmt) || $taxAmt == '')) {
                Globals::$g->gErr->addIAError(
                    'INV-1384', __FILE__.':'.__LINE__,
                    "Override tax error", [],
                    "To override the tax amount in the line # " . $lineNo. ", enter a value in the 'Transaction value' field, which is currently blank", ['LINE_NO' => $lineNo]
                );
                return false;
            }
        }
        return true;
    }

    /**
     * @param [] $fields
     * @param string $docId
     */
    function removeCustomListerFields(&$fields,$docId){
        if($docId != null){
            $mgr = Globals::$g->gManagerFactory->getManager('documentparams');
            $docpar = $mgr->GetLatest($docId, false);
            $creinstalled = CRESetupManager::isCREInstalled();
            if($creinstalled && in_array($docpar['DOCCLASS'], ['Order','Quote'])){
                $enableAddInfoScope = $docpar['ENABLEADDINFOSCOPE'] ?? 'false';
                if( $enableAddInfoScope != 'true' && $enableAddInfoScope != 'T'){
                    $addInfoFields = self::getAdditionalInfoFields('SCOPE');
                    foreach ($fields as $key => $value){
                        if(in_array($value['path'],$addInfoFields)){
                            unset($fields[$key]);
                        }
                    }
                }
                $enableAddInfoSchedule = $docpar['ENABLEADDINFOSCHEDULE'] ?? 'false';
                if($enableAddInfoSchedule != 'true' && $enableAddInfoSchedule != 'T' ){
                    $addInfoFields = self::getAdditionalInfoFields('SCHEDULE');
                    foreach ($fields as $key => $value){
                        if(in_array($value['path'],$addInfoFields)){
                            unset($fields[$key]);
                        }
                    }
                }
                $enableAddInfoInternalRef = $docpar['ENABLEADDINFOINTERNALREF'] ?? 'false';
                if($enableAddInfoInternalRef != 'true' && $enableAddInfoInternalRef != 'T'){
                    $addInfoFields = self::getAdditionalInfoFields('INTERNALREF');
                    foreach ($fields as $key => $value){
                        if(in_array($value['path'],$addInfoFields)){
                            unset($fields[$key]);
                        }
                    }
                }

                $enableAddInfoExternalRef = $docpar['ENABLEADDINFOEXTERNALREF'] ?? 'false';
                if($enableAddInfoExternalRef != 'true' && $enableAddInfoExternalRef != 'T' ){
                    $addInfoFields = self::getAdditionalInfoFields('EXTERNALREF');
                    foreach ($fields as $key => $value){
                        if(in_array($value['path'],$addInfoFields)){
                            unset($fields[$key]);
                        }
                    }
                }

                $enableAddInfoBond = $docpar['ENABLEADDINFOBOND'] ?? 'false';
                if($enableAddInfoBond != 'true' && $enableAddInfoBond != 'T' ){
                    $addInfoFields = self::getAdditionalInfoFields('BOND');
                    foreach ($fields as $key => $value){
                        if(in_array($value['path'],$addInfoFields)){
                            unset($fields[$key]);
                        }
                    }
                }
            }
            else{
                $addInfoFields = self::getAdditionalInfoFields();
                foreach ($fields as $key => $value){
                    if(in_array($value['path'],$addInfoFields)){
                        unset($fields[$key]);
                    }
                }
            }
        }
    }

    /**
     * @noinspection PhpUnusedPrivateMethodInspection
     * @param EntityManager   $mgr
     * @param bool            $ignoreDimensions
     *
     * @return array
     */

    private function getFieldListToCompare($mgr, /** @noinspection PhpUnusedParameterInspection */ $ignoreDimensions = false)
    {
        $objects = $this->traitGetFieldListToCompare($mgr, $ignoreDimensions);
        if($this->isChangeOrderEnabled()){
            if($this->dynamicIgnoreFields){
                foreach($objects as $key => $obj){
                    if(in_array($obj, $this->dynamicIgnoreFields)){
                        unset($objects[$key]);
                    }
                }
            }

            if ($mgr instanceof PODocumentEntryManager) {
                if(isset($this->dynamicFieldsToCompare['PODocumentEntryManager']) && $objects){
                    $objects = array_merge($objects, $this->dynamicFieldsToCompare['PODocumentEntryManager']);
                }
            }
            if ($mgr instanceof SODocumentEntryManager) {
                if(isset($this->dynamicFieldsToCompare['SODocumentEntryManager']) && $objects){
                    $objects = array_merge($objects, $this->dynamicFieldsToCompare['SODocumentEntryManager']);
                }
            }
        }
        return $objects;
    }


    /**
     * needToUpdateLine - called before UPSERTING our child entries (like document entry records)
     *
     * @param array &$line line items
     *
     * @return bool
     */
    protected function needToUpdateLine(&$line)
    {
        return Matchmaker::needToUpdateLine($line);
    }


    /**
     *      This helper makes sure we upsert in the RIGHT ORDER.  Specifically, we want to update tables that
     *  depend on some other table AFTER that table is updated.  This is governed by the constant UPSERT_ORDER.
     *  So, if some table depends on DocEntry, then there should be an entry in UPSERT_ORDER of
     *          <table> => 'docentry',
     *   or
     *          <table> => ['docentry', 'dochdr'],  // depends on more than one record going before it
     *  so that we can check if docentry has already been upserted.  Why?  Because if the table has NOT been upserted,
     *  and the upsert code runs into an error or other issue, then we need to match the upserted <table> with the
     *  potentially NEW record#'s in docentry (in this example).
     *
     * @param string    $entityName     The name of the entity being upserted
     *
     * @throws Exception
     */
    public static function updatingEntity($entityName)
    {
        if ( ! self::$upsertFeaturInUse) {
            return;
        }
        $entityName = strtolower($entityName);
        // called more than once for the same entity?  Code bug!
        // On second thought, likely not.  You might be called in a loop for each entry
        //if (isset(self::$upsertedEntities[$entityName])) {
        //    throw new Exception("[Code Bug]DocumentManager::updatingEntity calld more than once for $entityName");
        //}

        // Needs to be in the UPSERT_ORDER list.  If not, code bug!
        if ( ! isset(self::UPSERT_ORDER[$entityName])) {
            throw new Exception("[Code Bug]DocumentManager::updatingEntity calld with an entity NOT in the UPSERT_ORDER tree: $entityName");
        }

        // Ok, who comes before me?  (empty array is ok)
        // Might be an array, might be a single entry
        $comesBefore = self::UPSERT_ORDER[$entityName];
        if ($comesBefore !== '') {  // empty means 'I'm first'
            if (!is_array($comesBefore)) {
                $comesBefore = [$comesBefore];  // NOW it is an array of one
            }

            // For each entity that should have come before, have we already seen it?  We better have!
            foreach ($comesBefore as $cameBefore) {
                if (!isset(self::$upsertedEntities[strtolower($cameBefore)])) {
                    logFL("[Code Bug]DocumentManager::updatingEntity: $cameBefore not upserted before $entityName, but it must be");
                }
            }
        }
        // remember that we've been here; everything is fine
        Matchmaker::additionalLogging("Upserting $entityName " . ((self::$upsertedEntities[$entityName] ?? false) ? "AGAIN!" : ""));
        self::$upsertedEntities[$entityName] = true;
    }

    /**
     * @param array $values
     *
     *
     */
    private function allowPartiallyAndConvertedAsEditable($values){
        $creDoc = $this->allowedCREDocStates($values);
        if($creDoc){
            if(in_array($this->mod, ["po" , "so"])){
                if (in_array($values['STATE'], $this->listOfCREDocStates)) {
                    // $docparmgr = $gManagerFactory->getManager('podocumentparams');
                    // $this->dynamicIgnoreFields = array_merge($this->dynamicIgnoreFields, $docparmgr->GetUpdateDBFields());
                    $this->dynamicIgnoreFields = array_merge($this->dynamicIgnoreFields, ['DOCPARKEY', 'PRICE_CONVERTED']);
                }
            }
        }

    }

    /** To validate additional information fields only to be edited in converted document
     * @param array $values
     *
     * @return bool
     */
    private function validateAdditionalInfoForConvertedDoc($values){
        $ok = true;
        $gErr = Globals::$g->gErr;
        $ignoreFieldLists = [];
        $creinstalled = CRESetupManager::isCREInstalled();
        $curState = $values['EXISTING_DOC']['STATE'];

        if($creinstalled && $curState == self::CONVERTED_STATE && in_array($this->mod, ["po","so"])) {
            $entity = ($this->mod == "po") ? "podocument" : "sodocument";
            $lineEntryEntity = ($this->mod == "po") ? "podocumententry" : "sodocumententry";
            $ignoreFieldLists[$entity] = array_tolower($this->getAdditionalInfoFields('dbfields'));
            $ignoreFieldLists[$entity] = array_merge($ignoreFieldLists[$entity], ['userkey', 'docparkey', 'whenposted','billtokey','shiptokey','haschange','changelognumber']);
            $ignoreFieldLists[$lineEntryEntity] = $this->getEntryFieldsListToIgnore();
            $this->setDctSkipNewValueIsEmpty(true);
            $this->setDctIgnoreFields($ignoreFieldLists);
            $ok = $ok && $this->dctCompareDocValues($values);
            if(!$ok){
                $msg = 'Transaction ' . $values['EXISTING_DOC']['DOCID'] . ' is ' . $values['EXISTING_DOC']['STATE']
                       . '. Cannot edit ' . $values['EXISTING_DOC']['STATE'] . ' transactions.';
                $gErr->addIAError(
                    'INV-1385', __FILE__ . ':' . __LINE__,
                    'Error on editing ' . $values['EXISTING_DOC']['DOCID'], ['VALUES_EXISTING_DOC_DOCID' => $values['EXISTING_DOC']['DOCID']],
                    $msg, ['VALUES_EXISTING_DOC_DOCID' => $values['EXISTING_DOC']['DOCID'], 'VALUES_EXISTING_DOC_STATE' => $values['EXISTING_DOC']['STATE']],
                    'Invalid Operation', []
                );
                return false;
            }
        }
        return $ok;
    }

    /**
     * To check  CRE doc is converted state or not
     * @param array $values
     *
     * @return bool
     */
    protected function isCREConvertedDoc($values){
        $creinstalled = CRESetupManager::isCREInstalled();
        $curState = $values['EXISTING_DOC']['STATE'];

        $hasChange = $values['HASCHANGE'] ?? 'false';
        // for change order purpose, to skip iscreconverteddoc for source doc
        $hasChangeFlag = ($hasChange == 'true') ? true : false;

        if($creinstalled && $curState == self::CONVERTED_STATE && in_array($this->mod, ["po","so"]) && !$hasChangeFlag) {
            return true;
        }
        return false;
    }

    /**
     * update additional information field values in dochdrmst
     * @param array $values
     *
     * @return bool
     */
    private function updateAdditionalInfoFieldValues($values){
        $ok = true;
        $addinfoFields = $this->getAdditionalInfoFields();
        $dbFields = $this->_schemas[$this->_entity]['schema'];
        $bind = 1;
        $stmt[0] = "update dochdrmst set ";
        $params = [];
        $copyValues = [];

        foreach ($addinfoFields as $aiField){
            if($values[$aiField] && $dbFields[$aiField]){
                $dbFieldArr = explode(".", $dbFields[$aiField]);
                if(count($dbFieldArr) == 1){ // to remove the children table and column
                    $copyValues[$aiField] = $values[$aiField];
                    $params[] = $dbFields[$aiField]." = :$bind";
                    $transVal = $this->TransformValue($aiField, $values[$aiField], 0);
                    $stmt[] = $transVal;
                    $bind++;
                }
            }
        }

        if(count($params) > 0){
            $source = 'DocumentManager::updateAdditionalInfoFieldValues()';

            $ok = $this->beginTrx($source);

            /** @noinspection PhpUnusedLocalVariableInspection */
            $stmt[0] .= implode(", ",$params) ." where record# = :". $bind++ ." and cny# = :". $bind++ ;
            $stmt[] = $values['RECORDNO'];
            $stmt[] = GetMyCompany();

            $ok = $ok && $this->smartlinkValidate([ 'set', 'addset' ], $copyValues);
            $ok = $ok && ExecStmt($stmt);

            $ok = $ok && $this->commitTrx($source);

            if (!$ok) {
                // do *not* add error, if it has only warnings
                if (!HasErrors() && HasWarnings()) {
                    $this->rollbackTrx($source);
                    return false;
                }
                /** @noinspection PhpUndefinedVariableInspection */
                $msg = "Could not create $entity record!";
                Globals::$g->gErr->addIAError('INV-1315', __FILE__ . ':' . __LINE__, $msg, ['ENTITY' => $entity]);
                Globals::$g->gErr->AddEntityDBError($source, $this->_entity);
                $this->rollbackTrx($source);
            } else {
                $ok = $ok && $this->postProcessValues($values, 'set', false);
            }

        }
        return $ok;
    }

    /**
     * @param array $values
     * @param string $key
     *
     * @return mixed
     */
    private function getRetainageLineTrxValue($values, $key){
        $enableDocChange = $values['_DOCPAR']['ENABLEDOCCHANGE'] ?? "No Change";
        if($enableDocChange == "Enable Change" && $values['HASCHANGE'] == 'true') {
            $lineTrxValue = !isNullOrBlank($values['ENTRIES'][$key]['TRX_REVISEDVALUE'])
                ? $values['ENTRIES'][$key]['TRX_REVISEDVALUE'] : $values['ENTRIES'][$key]['TRX_VALUE'];
        } else {
            $lineTrxValue = $values['ENTRIES'][$key]['TRX_VALUE'];
        }
        return $lineTrxValue;
    }

    /**
     * If TRX_AmountRetained is specified without RetainagePercentage, calculate RetainagePercentage. or
     *  RetainagePercentage is specified - Calculate TRX_AmountRetained.
     * @param array  $values
     * @param string $key
     *
     * @return array
     */
    protected function recalculateRetainageValues(array &$values,string $key){
        $lineTrxValue = $this->getRetainageLineTrxValue($values, $key);

        $line = $values['ENTRIES'][$key];
        // If TRX_AmountRetained is specified without RetainagePercentage, calculate RetainagePercentage.
        if (isset($line['TRX_AMOUNTRETAINED']) && !isNullOrBlank($line['TRX_AMOUNTRETAINED']) && is_numeric($line['TRX_AMOUNTRETAINED']) && $line['TRX_AMOUNTRETAINED'] != 0) {
            //Only update amountretained when it is not specified, otherwise use amountretained as the rule.
            $lineTrxAmountRetained = $values['ENTRIES'][$key]['TRX_AMOUNTRETAINED'];
            $calculatedRetained = 0;
            if (!isNullOrBlank($line['RETAINAGEPERCENTAGE'])) {
                $calculatedRetained = ibcdiv(ibcmul($lineTrxValue, $line['RETAINAGEPERCENTAGE'], 2, true), '100', 2, true);
            }
            else {
                $line['RETAINAGEPERCENTAGE'] = 0;
            }
            if ($calculatedRetained != $lineTrxAmountRetained) {
                $calculatedPercentage = ibcmul(ibcdiv($lineTrxAmountRetained, $lineTrxValue, 4, true), 100, 2);
                $newCalculatedRetained = ibcdiv(ibcmul($lineTrxValue, $calculatedPercentage, 2, true), '100', 2, true);
                if (abs(ibcsub($newCalculatedRetained, $lineTrxAmountRetained)) < abs(ibcsub($calculatedRetained, $lineTrxAmountRetained))) {
                    $line['RETAINAGEPERCENTAGE'] = $calculatedPercentage;
                }
            }
            $values['ENTRIES'][$key]['RETAINAGEPERCENTAGE'] = $line['RETAINAGEPERCENTAGE'];
        }
        else if (isset($line['RETAINAGEPERCENTAGE']) && !isNullOrBlank($line['RETAINAGEPERCENTAGE']) && is_numeric($line['RETAINAGEPERCENTAGE']) && $line['RETAINAGEPERCENTAGE'] != 0) {
            // RetainagePercentage is specified - Calculate TRX_AmountRetained.
            $lineRetainagePercentage = $values['ENTRIES'][$key]['RETAINAGEPERCENTAGE'];
            $line['TRX_AMOUNTRETAINED'] = ibcdiv(ibcmul($lineTrxValue, $lineRetainagePercentage, 2, true), '100', 2, true);
            $values['ENTRIES'][$key]['TRX_AMOUNTRETAINED'] = $line['TRX_AMOUNTRETAINED'];
        }

        return $values;
    }

    /**
     *      Can this document be fulfilled?
     *
     * @param array $document       The document fields, including the line items
     *
     * @return bool                 Can this document entry participate in fulfillment?
     */
    public function canBeFulfilled(/** @noinspection PhpUnusedParameterInspection */ $document)
    {
        // SUBCLASSES SHOULD OVERRIDE THIS
        return false;
    }
    /**
     * @param string|null $type
     *
     * @return array $fields
     */
    protected function getAdditionalInfoKeyFields($type = null){
        switch (strtoupper($type)){
            case 'INTERNALREF':
                $fields = ['INTERNALINITIATEDBYKEY' => 'INTERNALINITIATEDBY','INTERNALVERBALBYKEY' => 'INTERNALVERBALBY','INTERNALISSUEDBYKEY' => 'INTERNALISSUEDBY',
                           'INTERNALAPPROVEDBYKEY' => 'INTERNALAPPROVEDBY', 'INTERNALSIGNEDBYKEY' => 'INTERNALSIGNEDBY'];
                break;
            case 'EXTERNALREF':
                $fields = ['EXTERNALVERBALBYKEY' => 'EXTERNALVERBALBY','EXTERNALAPPROVEDBYKEY' => 'EXTERNALAPPROVEDBY','EXTERNALSIGNEDBYKEY' => 'EXTERNALSIGNEDBY'];
                break;
            case 'BOND':
                $fields = ['PERFORMANCESURETYCOMPANYKEY' => 'PERFORMANCESURETYCOMPANY','PAYMENTSURETYCOMPANYKEY' => 'PAYMENTSURETYCOMPANY'];
                break;
            default:
                $fields = ['INTERNALINITIATEDBYKEY' => 'INTERNALINITIATEDBY','INTERNALVERBALBYKEY' => 'INTERNALVERBALBY','INTERNALISSUEDBYKEY' => 'INTERNALISSUEDBY',
                           'INTERNALAPPROVEDBYKEY' => 'INTERNALAPPROVEDBY', 'INTERNALSIGNEDBYKEY' => 'INTERNALSIGNEDBY', 'EXTERNALVERBALBYKEY' => 'EXTERNALVERBALBY',
                           'EXTERNALAPPROVEDBYKEY' => 'EXTERNALAPPROVEDBY','EXTERNALSIGNEDBYKEY' => 'EXTERNALSIGNEDBY',
                           'PERFORMANCESURETYCOMPANYKEY' => 'PERFORMANCESURETYCOMPANY','PAYMENTSURETYCOMPANYKEY' => 'PAYMENTSURETYCOMPANY'];
        }
        return $fields;
    }

    /**
     * @return bool
     */
    protected function isObjectEligibleForVatPartialExempt()
    {
        return false;
    }

    /**
     *
     * @param array $values
     *
     * @return bool
     */
    public function isTxnEligibleForVatPartialExempt(&$values)
    {
        if (!TaxSolutionManager::isPartialExemptEligibleTaxSolution(($values['TAXSOLUTIONID'] ?? ''))) {
            return false;
        }
        if (!$this->isObjectEligibleForVatPartialExempt()) {
            return false;
        }
        if (IsMultiEntityCompany()) {
            $entityKey = GetContextLocation();
            if ($entityKey == '') {
                return false;
            } else {
                $locationMgr = Globals::$g->gManagerFactory->getManager('locationentity');
                $filter = [
                    'selects' => ['PARTIALEXEMPT'],
                    'filters' => [[['RECORDNO', '=', $entityKey]]]
                ];
                $locationEntity = $locationMgr->GetList($filter);
                if (isset($locationEntity[0]) && ($locationEntity[0]['PARTIALEXEMPT'] ?? null) === 'true') {
                    return true;
                } else {
                    return false;
                }
            }
        } else {
            $taxPref = self::GetPreferenceForProperty(Globals::$g->kTAXid, 'PARTIALEXEMPT');
            return $taxPref === 'T';
        }
    }

    /**
     *
     * @param array $entry
     * @param array $subtotals
     *
     */
    public function prepareSubtotalsWithPartialExemption(&$entry, &$subtotals)
    {
        $trx_taxClaimable = 0;
        $taxClaimable = 0;
        $partialExemptSubtotalsMap = array();
        //Prepare subtotals map to group partialexemption and non-partialexemption subtotals
        foreach ($subtotals as $subtotal) {
            $partialExemptSubtotalsMap[$subtotal['DOCENTRYKEY'] . '--' . $subtotal['DESCRIPTION']][] = $subtotal;
        }

        //Merge partialexemption and non-partialexemption subtotals , identify recoverable amount
        $newSubtotals = array();
        foreach ($partialExemptSubtotalsMap as $partialExemptSubtotals) {
            if (count($partialExemptSubtotals) === 1) {
                if (($partialExemptSubtotals[0]['ISPARTIALEXEMPT'] ?? null) === 'T' || ($partialExemptSubtotals[0]['PARTIALEXEMPT'] ?? null) === 'true') {
                    $trx_taxClaimable = ibcadd($trx_taxClaimable, $partialExemptSubtotals[0]['TRX_ABSVAL'], 4, true);
                    $taxClaimable = ibcadd($taxClaimable, $partialExemptSubtotals[0]['ABSVAL'], 4, true);
                    unset($partialExemptSubtotals[0]['ISPARTIALEXEMPT']);
                }
                $newSubtotals[] = $partialExemptSubtotals[0];
            } else {
                $subTotalTemp = array();
                foreach ($partialExemptSubtotals as $partSubtotals) {
                    if (empty($subTotalTemp)) {
                        $subTotalTemp = $partSubtotals;
                    } else {
                        $subTotalTemp['TRX_ABSVAL'] = ibcadd($subTotalTemp['TRX_ABSVAL'], $partSubtotals['TRX_ABSVAL'], 4, true);
                        $subTotalTemp['ABSVAL'] = ibcadd($subTotalTemp['ABSVAL'], $partSubtotals['ABSVAL'], 4, true);
                    }
                    if (($partSubtotals['ISPARTIALEXEMPT'] ?? null) === 'T' || ($partSubtotals['PARTIALEXEMPT'] ?? null) === 'true') {
                        $trx_taxClaimable = ibcadd($trx_taxClaimable, $partSubtotals['TRX_ABSVAL'], 4, true);
                        $taxClaimable = ibcadd($taxClaimable, $partSubtotals['ABSVAL'], 4, true);
                    }
                }
                unset($subTotalTemp['ISPARTIALEXEMPT']);
                $newSubtotals[] = $subTotalTemp;
            }
        }
        $subtotals=$newSubtotals;
        $entry['TRX_TAXCLAIMABLE'] = $trx_taxClaimable;
        $entry['TAXCLAIMABLE'] = $taxClaimable;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function allowedCREDocStates($values)
    {
        $ok = false;
        $validStates = [self::DRAFT_STATE, self::PENDING_STATE, self::CLOSED_STATE,
                        self::PARTIALLY_CONVERTED_BY_LINE_STATE,self::EXCEPTION_STATE];

        if(!CRESetupManager::isCREInstalled()){
            return false;
        }

        if($this->checkAddInfoEnabled($values) || $this->isChangeOrderDoc($values)){
            $validStates = array_merge($validStates, [self::PARTIALLY_CONVERTED_STATE, self::CONVERTED_STATE, self::INPROGRESS_STATE, self::DECLINED_STATE]);
            $ok = true;
        }

        if($ok){
            $this->listOfCREDocStates = array_unique($validStates);
        }

        return $ok;

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function checkAddInfoEnabled($values){
        $creinstalled = CRESetupManager::isCREInstalled();
        $docpar = $values['_DOCPAR'] ?? [];
        $addInfo = ((isset($docpar['ENABLEADDINFOSCOPE']) && $docpar['ENABLEADDINFOSCOPE'] == 'true') ||
                    (isset($docpar['ENABLEADDINFOSCHEDULE']) && $docpar['ENABLEADDINFOSCHEDULE'] == 'true') ||
                    (isset($docpar['ENABLEADDINFOINTERNALREF']) && $docpar['ENABLEADDINFOINTERNALREF'] == 'true') ||
                    (isset($docpar['ENABLEADDINFOEXTERNALREF']) && $docpar['ENABLEADDINFOEXTERNALREF'] == 'true') ||
                    (isset($docpar['ENABLEADDINFOBOND']) && $docpar['ENABLEADDINFOBOND'] == 'true'));

        return $creinstalled && ($addInfo ?? false);

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function validateAddInfoFieldsInNonCRE($values){
        $gErr = Globals::$g->gErr;
        $addInfoFields = self::getAdditionalInfoFields();
        foreach($addInfoFields as $field){
            if($values[$field] && ($values[$field] != '' && $values[$field] != 'false')){
                $gErr->addIAError('INV-0283', __FILE__ . ':' . __LINE__,
                                " Construction subscription required", [],
                                "The $field field are valid only when you have a subscription to Construction.", ['VALUE' => $field],
                                "Either remove these fields or subscribe to the Construction application and try again", []
                );
                return false;
            }
        }
        return true;
    }

    /**
     * @param string $recordNo
     *
     * @return bool
     */
    private function updateDeliveryLog($recordNo){
        $query = "update deliverylogmst set dochdrkey=null where cny#=:1 and dochdrkey=:2 and object=:3";
        $qparams = [ $query, GetMyCompany(), $recordNo, 'invoice' ];
        $ok = ExecStmt($qparams);

        return $ok;
    }

    /**
     * @return array
     */
    public function getDBTranslatedFieldsForEditor(): array
    {
        // Translate EXCHRATETYPES.NAME field explicitely in formeditor
        // exchangeratetypesall is used in document and recurdocument ent and its ownedobjects
        return ['EXCHRATETYPES.NAME', 'EXCHRATETYPE'];
    }

    /**
     * @return bool
     * @throws Exception
     */
    public static function isAddressLineThreeEnabled() : bool
    {
        static $isAddressLineThreeEnabledFlag = null;
        if ($isAddressLineThreeEnabledFlag === null) {
            $isAddressLineThreeEnabledFlag = FeatureConfigManagerFactory::getInstance()
                                                                        ->isFeatureEnabled('ENABLE_ADDRESS_LINE_3');
        }

        return $isAddressLineThreeEnabledFlag;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function validateAnalyzingState(array $values): bool
    {
        if (!$this->getIsPOAutomationWorkflow()
            && ($values['STATE'] == self::ANALYZING_STATE
                || (Util::countOrZero($values['EXISTING_DOC']) > 0
                    && ($values['EXISTING_DOC']['STATE'] ?? '') == self::ANALYZING_STATE))) {
            $msg = " Document can not create or update for the document state " . self::ANALYZING_STATE;
            Globals::$g->gErr->addIAError('INV-1442', __FILE__ . ':' . __LINE__, $msg,
                                          [  'STATE' => self::ANALYZING_STATE ]);

            return false;
        }

        return true;
    }

    /**
     * @param bool $isPOAutomationWorkflow
     *
     * @return void
     */
    public function setIsPOAutomationWorkflow(bool $isPOAutomationWorkflow)
    {
        $this->isPOAutomationWorkflow = $isPOAutomationWorkflow;
    }

    /**
     * @return bool
     */
    public function getIsPOAutomationWorkflow()
    {
        return $this->isPOAutomationWorkflow;
    }

    /**
     * @param array $values
     *
     * @return true
     */
    protected function subtotalForDraftDocRequired(array &$values): bool
    {
        if (!$this->isDraftDocument($values)) {
            return true;
        }

        // This validation should check for only POMatch draft document
        $isPOMatchDocument = (in_array(($values['DOCSOURCE'] ?? ''), [self::INVOICE_UPLOAD, self::EMAIL]));

        // This logic should go through only for pomatch document of Draft document
        if ($values['_DOCPAR']['SHOW_TOTALS'] == 'true' && $isPOMatchDocument) {

            // Based on this result, we will decide to skip the PrepareSubTotalsValues calculation or not
            if (!$this->subtotalvalidationForDraft($values)) {
                // If the dimension is restricted, we should remove the subtotal value
                unset($values['SUBTOTALS']);
                return false;
            }

            // Check If customer or vendor is taxable or respective contacts are taxable
            $custVendID = explode('--', $values['CUSTVENDID'])[0] ?? '';
            $contact = $this->getCustVendContactNameForSubtotal($values);
            $custVendTaxable = false;
            if (!empty($custVendID) || !empty($contact)) {
                $custVendTaxable = $this->getTaxabilityOfCustVend($custVendID, $contact);
            }

            if (!$custVendTaxable) {
                // If custvend or contact is taxable, we should remove the subtotal value
                unset($values['SUBTOTALS']);
                return false;
            }

            // Check if any of the line items are taxable
            $hasTaxableLineItems = false;
            if (Util::countOrZero($values['ENTRIES']) > 0) {
                $itemIDs = [];
                foreach ($values['ENTRIES'] as $entry) {
                    $itemID = explode("--", $entry['ITEMID'])[0] ?? '';
                    if (!empty($itemID)) {
                        $itemIDs[] = $itemID;
                    }
                }

                $itemIDs = array_unique($itemIDs);
                if (Util::countOrZero($itemIDs) > 0) {
                    $query = [
                        "select count(taxable) AS taxableitemcnt from icitemmst  
                            where cny# = :1 and status = :2 AND taxable = :3 AND producttype != :4 ",
                        GetMyCompany(),
                        'T',
                        'T',
                        'PROFSERVICE'
                    ];
                    $query = PrepINClauseStmt($query, $itemIDs, " and ITEMID ");
                    $result = QueryResult($query);
                    $hasTaxableLineItems = (Util::countOrZero($result[0]) > 0 && $result[0]['TAXABLEITEMCNT'] > 0);
                }
            }

            if (!$hasTaxableLineItems) {
                // If none of the line item is taxable, we should remove the subtotal value
                unset($values['SUBTOTALS']);
                return false;
            }
        }

        return true;
    }


    /**
     * @param string $custID
     * @param string $shipToContact
     *
     * @return bool
     */
    private function getTaxabilityOfCustVend(string $custID, string $shipToContact): bool
    {
        if (isset($shipToContact) && $shipToContact != '') {
            $qry = "select taxable from contact where cny# = :1  and name = :2";
            $args = array($qry, GetMyCompany(), $shipToContact);
        } else {
            $qry = "SELECT contact.taxable
					FROM customermst c,
						 contact contact
					WHERE c.cny#     = :1
					AND c.cny#       = contact.cny#
					AND c.displaycontactkey  = contact.record#
					AND c.customerid = :2";
            $args = array($qry, GetMyCompany(), $custID);
        }
        $res = QueryResult($args);
        $isTaxable = (isset($res[0]['TAXABLE']) && $res[0]['TAXABLE'] == 'T');

        return $isTaxable;
    }

    /**
     * @param array $values
     *
     * @return string
     */
    protected function getCustVendContactNameForSubtotal(array $values): string
    {
        return $values['SHIPTO']['CONTACTNAME'] ?? '';
    }


    /**
     *  Call this before a regularAdd() or regularSet() call.
     *
     *      If supplies is enabled, and this is a conversion, it sets things up to track
     *  the new transaction from a Supplies Issue
     *
     * @param array     $documentTree       The document tree in Add or Update
     *
     * @return bool
     */
    protected function suppliesBeforeAddorUpdate(&$documentTree)
    {
        $ok = true;
        if (ItemManager::isSuppliesInventoryEnabled()) {
            $suppliesManager = Globals::$g->gManagerFactory->getManager('invsupplies');
            $ok = $suppliesManager->createLinksInDocumentFromConvertSource($documentTree);
        }
        return $ok;
    }


    /**
     *  Call this AFTER a regularAdd() or regularSet() call.
     *
     *      If supplies is enabled, and this is a conversion, it sets things up to track
     *  the new transaction from a Supplies Issue
     *
     * @param array     $documentTree       The document tree in Add or Update
     *
     * @return bool
     */
    protected function suppliesAfterAddorUpdate(&$documentTree)
    {
        $ok = true;
        if (ItemManager::isSuppliesInventoryEnabled()) {
            $suppliesManager = Globals::$g->gManagerFactory->getManager('invsupplies');
            $ok = $suppliesManager->conversionSaved($documentTree);
        }
        return $ok;
    }




}

/**
 * Get the document template params.
 *
 * @param  string $mod the module id.
 * @param  string $cat the category/clas of the document template.
 * @param  bool   $eliminateRestrictedDocpars
 *
 * @return array $retval return the document templates of a given module
 */
function GetDocumentParams($mod, $cat = '', $eliminateRestrictedDocpars = false)
{
    $docparams = 'k'.$mod.$cat.$eliminateRestrictedDocpars.'DocumentParams';
    global ${$docparams};

    // If it already exists avoid the additional query.
    if ($$docparams) {
        return $$docparams;
    }

    $docs = GetDocumentMenuList($mod, $cat);

    //This function is used extensively in many reports for showing the document name, removing Build Kits and Disassemble Kits -- mmahur
    foreach ($docs as $key => $val) {
        if (in_array($val['DOCID'], array(BUILD_KIT, DIS_KIT))) {
            Unset($docs[$key]);
        }
        if ($eliminateRestrictedDocpars) {
            if (!DocumentSetupUtil::isDocparCreatable($docs[$key], $mod)) {
                Unset($docs[$key]);
            }
        }
    }

    $retval = array();
    foreach ($docs as $doc) {
        $retval[] = $doc['DOCID'];
    }

    $$docparams = $retval;

    return $retval;
}

/**
 * Get the document template params.  This is a temporary function because there are duplicate DOCIDs in the docpar table (with latestversionkey equals null).  Once we fix the data
 * and the constraint to guarantee unique DOCID we should delete this function and replace the callers to call GetDocumentParams.
 *
 * @param  string $mod the module id.
 * @param  string $cat the category/clas of the document template.
 *
 * @return array $retval return the document templates of a given module
 */
function GetDistinctDocumentParams($mod, $cat = '')
{
    $retval = GetDocumentParams($mod, $cat);
    if (is_array($retval) && count($retval) > 1) {
        $retval = INTACCTarray_unique($retval);
    }
    return $retval;
}

/**
 * Get the non change order document template params.
 *
 * @param  string $mod the module id.
 * @param  string $cat the category/clas of the document template.
 * @param  bool   $eliminateRestrictedDocpars
 *
 * @return array $retval return the document templates of a given module
 */
function GetNonCCODocumentParams($mod, $cat = '', $eliminateRestrictedDocpars = false)
{
    $docparams = 'k'.$mod.$cat.$eliminateRestrictedDocpars.'DocumentParams';
    global ${$docparams};

    // If it already exists avoid the additional query.
    if ($$docparams) {
        return $$docparams;
    }

    $docs = GetDocumentMenuList($mod, $cat);

    //This function is used extensively in many reports for showing the document name, removing Build Kits and Disassemble Kits -- mmahur
    foreach ($docs as $key => $val) {
        $enableDocChange = $val['ENABLEDOCCHANGE'] ?? "No Change";
        if($enableDocChange != "No Change"){
            Unset($docs[$key]);
        }
        $enablePCB = $val['ENABLECONTRACTBILLING'] ?? "F";
        if($mod == 'so' && $enablePCB == "T" ){
            Unset($docs[$key]);
        }
        if (in_array($val['DOCID'], array(BUILD_KIT, DIS_KIT))) {
            Unset($docs[$key]);
        }
        if ($eliminateRestrictedDocpars) {
            if (!DocumentSetupUtil::isDocparCreatable($docs[$key], $mod)) {
                Unset($docs[$key]);
            }
        }
    }

    $retval = array();
    foreach ($docs as $doc) {
        $retval[] = $doc['DOCID'];
    }

    $$docparams = $retval;

    return $retval;
}
