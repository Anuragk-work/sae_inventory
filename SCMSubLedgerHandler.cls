<?

/**
 *    FILE: SCMSubLedgerHandler.cls
 *    AUTHOR: Sudeendra Rao
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 *  Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


import('ManagerFactory');
import('Dictionary');

require_once 'util.inc';
// temporary, hopefully
require_once 'backend_prbatch.inc';
require_once 'backend_invoice.inc';
require_once 'backend_supdoc.inc';
require_once 'DePrEntryResolveManager.cls';     // NOT an ENTITY MANAGER manager!

//PPV/IPV definitions
define('PO', 'PO');
define('POReceiver', 'POReceiver');
define('VendorInvoice', 'VendorInvoice');
define('POReturn', 'POReturn');
define('VendorReturn', 'VendorReturn');
define('IPV', 'IPV');
define('PPV', 'PPV');


/**
 * @package    source
 * @subpackage inventory
 */

/**
 * Class SCMSubLedgerHandler
 */
class SCMSubLedgerHandler
{
    use ComplianceTrait;
    
    /** @var array $_offsetaccts */
    var $_offsetaccts           = array();

    /** @var bool $_usingTaxSchedules */
    var $_usingTaxSchedules     = false;

    /** @var string $_contactTaxGrpKey */
    var $_contactTaxGrpKey;

    /** @var array $_itemLines */
    var $_itemLines             = array();

    /** @var array $_taxLines */
    var $_taxLines              = array();

    /** @var array $_getSubTotalsResult */
    var $_getSubTotalsResult    = array();

    /** @var array $_simpletaxLines */
    var $_simpletaxLines        = array();

    /** @var array $_prtaxEntries */
    var $_prtaxEntries          = array();

    /** @var array $_itemPREntrykeys */
    var $_itemPREntrykeys       = array();

    /** @var array $_taxPREntrykeys */
    var $_taxPREntrykeys        = array();

    /** @var array $_simpletaxPREntrykeys */
    var $_simpletaxPREntrykeys    = array();

    /** @var array  $_revenueAccts*/
    var $_revenueAccts          = array();

    /** @var array $_prglLineFromTD */
    var $_prglLineFromTD        = array();

    /** @var array $customFields */
    var $customFields            = array();

    /** @var array $_discountPREntrykeys */
    var $_discountPREntrykeys   = array();

    /** @var array $_chargePREntrykeys */
    var $_chargePREntrykeys     =array();

    /** @var array $baseCurrencies */
    private $baseCurrencies     = array();

    /** @var array $deGlResolves    The deglresolves to add/update  */
    private $deGlResolves       = [];

    /** @var array $subtotalResolves   The subtotal gl resolve records to add/update */
    private $subtotalResolves   = [];

    /** @var array $cachedHasResolveMaps */
    private /** @noinspection PhpUnusedPrivateFieldInspection */ $cachedHasResolveMaps = [];   // We want to compute the hasResolveMaps before docentrydetail entries got deleted to take into account 0 amount VSOE allocations

    /** @var array $_itemTaxGroupCache */
    var $_itemTaxGroupCache             = array();

    function __construct()
    {
        $this->baseCurrencies      = [];
        $this->deGlResolves        = [];
        $this->subtotalResolves    = [];
    }

    /**
     * @param string $docentrykey
     * @param string $itemid
     * @param string $accountsType
     *
     * @return string
     */
    public static function getRevAcctMapKey($docentrykey, $itemid, $accountsType = 'PR')
    {
        return "$docentrykey-$itemid-".$accountsType;
    }


    /**
     * @access private
     */
    /**
     * @return CostingHandler
     */
    function get_costing_handler()
    {
        /** @var CostingHandler $costingHandler */
        $costingHandler = Globals::$g->gManagerFactory->_getObjectInstance('CostingHandler');
        return $costingHandler;
    }


    /**
     * @param string $mod
     * @param array  $docvalues
     *
     * @return SCMSubtotals|POSubtotals|InvSubtotals|SCMSubtotals
     */
    function GetSubTotalsHelper($mod = '', $docvalues = array())
    {
        $mod = isl_strtoupper($mod);
        switch ($mod) {
            case 'SO' :
                $subTotalsHelper = 'SOSubtotals';
                break;
            case 'PO' :
                $subTotalsHelper = 'POSubtotals';
                break;
            case 'INV' :
                $subTotalsHelper = 'InvSubtotals';
                break;
            default  :
                $subTotalsHelper = 'SCMSubtotals';
                break;
        }

        $subTotalsObj = Globals::$g->gManagerFactory->_getObjectInstance($subTotalsHelper);
        $subTotalsObj->Initialize($docvalues);

        /** @var SCMSubtotals|POSubtotals|InvSubtotals|SCMSubtotals $subTotalsObj */
        return $subTotalsObj;
    }

    /**
     * @param array $nvalues
     * @param array $prglLineFromTD
     * @param array $revenueAccts
     *
     * @return bool
     */

    function ProcessInventoryTransaction(&$nvalues, &$prglLineFromTD, &$revenueAccts)
    {
        // Get an array of accounts and amounts
        $ok = $this->FindEntries($nvalues, $nvalues['ENTGLGROUP'], $nvalues['_DOCPAR']['RECORDNO'], 'INV', $glentries, $prglLineFromTD, $revenueAccts);
        $mod = $nvalues['_mod'];

        $ok = $ok && $this->ProcessInvSubtotals($nvalues, $glentries, $mod);
        $glentries = $this->SummarizeEntries($glentries, $mod);

        if (isset($glentries) && count($glentries) > 0) {
            // Stick those entries in a transaction
            $ok = $ok && $this->ValidateGLEntries($glentries);

            $batchDate = $nvalues['WHENPOSTED'] ?: $nvalues['WHENCREATED'];
            $ok = $ok && $this->CreateInventoryTransaction($batchDate, $glentries,    $nvalues['_DOCPAR'], $nvalues['INVBATCHKEY']);
            $ok = $ok && $this->GetInventoryGLInfo($nvalues, $glentries);
            $ok = $ok && $this->UpdateDoc_INVBatchReference($nvalues);
        }

        return $ok;
    }

    /**
     * @param array $nvalues
     *
     * @return bool
     */
    function DeleteInventoryTransaction(&$nvalues)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $nvalues['COGS_GLENTRIES'] = [];
        $glentries = [];
        $needToSwitchToRootContext = false;
        $invBatchMgr = Globals::$g->gManagerFactory->getManager('invbatch');
        if ($nvalues['INVBATCHKEY'] != '') {
            $dochdrkey = $nvalues['RECORDNO'];

            // In case of COGS there might be IET's, In such case the GL Batch may belong to root.
            $needToSwitchToRootContext = $invBatchMgr->needToSwitchToRootContext($nvalues['INVBATCHKEY']);

            // If user in entity level and glbatch belong to top level then we should set the context to featch all the records
            // Because IET entires records should always having different entity informations
            if ($needToSwitchToRootContext) {
                Database::switchToNonMegaContext();
            }

            // Get the Glentries for this document's cogs entries
            $docentryGLResolveMgr = Globals::$g->gManagerFactory->getManager('documententryglresolve');

            $nvalues['COGS_GLENTRIES'] = $docentryGLResolveMgr->GetGLEntries($dochdrkey, true);

            if (!empty($nvalues['COGS_GLENTRIES'])) {
                $glentries = array($nvalues['COGS_GLENTRIES']);
            } else {
                // Various escalations such as P3 13840315: Unable to edit/delete OE transaction - Error "could not find existing GL entries"
                // show that it IS possible to have an INVBATCHKEY but no deglresolves or deglsubtotalresolves.
                // happens with sales of non-inventory items, but we haven't been able to completely replicate it.
                // still, doesn't seem to mean the transaction is broken.....

                // $ok = false;
            }

            if (!$ok) {
                $docparid = $nvalues['DOCPARID'];
                $msg = 'Transaction ' . $nvalues['DOCID']
                    . ' has posted COGS to GL and could not find existing GL entries.';
                $gErr->addIAError(
                    'INV-0833', __FILE__ . ':' . __LINE__,
                    'Error Editing/Deleting ' . $docparid, ['DOCPARID' => $docparid],
                    $msg, ['DOCID' => $nvalues['DOCID']],
                    'Invalid Operation', []
                );
                return $ok;
            }
        }

        $mod = $nvalues['_mod'];

        if ($mod == 'inv') {
            $ok = $ok && $this->DeleteInvSubtotals($nvalues, $glentries);
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $glentries = $this->SummarizeEntries($glentries, $mod);

        if (isset($glentries) && count($glentries) > 0) {
            if (IsMCMESubscribed()) {
                foreach ($glentries as $k => $glentry) {
                    //
                    // when editing/deleting the COGS glentries are prepared again
                    // in which case the BaseCurrency & Currency values are missed out
                    // the currency & base currency will be same as the COGS is always posted in Base Currency
                    $glentries[$k]['BASECURR'] = ($glentries[$k]['BASECURR'] == '') ? $nvalues['BASECURR']
                        : $glentries[$k]['BASECURR'];
                    $glentries[$k]['CURRENCY'] = $glentries[$k]['BASECURR'];
                    $glentries[$k]['EXCHANGE_RATE'] = 1;
                }
            }

            // upsert note: upserting glentries is way too hard, so just let them be deleted.
            $ok = $ok && $invBatchMgr->RemoveGLEntries($nvalues, $glentries);
        }

        // Shifting back to entity context
        if ($needToSwitchToRootContext) {
            Database::switchBackToMegaContext();
        }

        return $ok;
    }

    /**
     * @param array $nvalues
     * @param array $glentries
     *
     * @return bool
     */
    function DeleteInvSubtotals($nvalues, &$glentries)
    {
        if ($nvalues['_DOCPAR']['UPDATES_GL'] == 'G' && $nvalues['_DOCPAR']['SHOW_TOTALS'] == 'true') {
            /** @var SubtotalGLResolveManager $subtotalResolveMgr */
            $subtotalResolveMgr = Globals::$g->gManagerFactory->getManager('subtotalglresolve');

            /** @var SubtotalGLResolveManager $subtotalResolveMgr */
            $subtot_glentries = $subtotalResolveMgr->Get($nvalues['RECORDNO']);
            $subtot_glentries = [$subtot_glentries];

            $glentries = INTACCTarray_merge($glentries, $subtot_glentries);
        }

        return true;
    }

    /**
     * @param array $nvalues
     * @param array $glentries
     *
     * @return bool
     */
    private function processLandedCost(/** @noinspection PhpUnusedParameterInspection */ &$nvalues, &$glentries)
    {
        if (!$nvalues['MACRONAME'] || $nvalues['MACRONAME'] == SCMMacroManager::LCACTANDESTREV) {
            $property = 'LANDEDCOSTACCOUNT';
        } else if ($nvalues['MACRONAME'] == SCMMacroManager::LCEST) {
            $property = 'LANDEDCOSTACCOUNTESTIMATE';
        } else {
            $msg = "Not supported - SCMSubLedgerHandler::processLandedCost.";
            Globals::$g->gErr->addIAError('INV-0834', __FILE__ . ":" . __LINE__,
             "Invalid user action",[], $msg,[], "",[]);
            return false;
        }

        $landedCostAccount = GetPreferenceForProperty(Globals::$g->kINVid, $property);
        list($landedCostAccountID) = explode('--', $landedCostAccount);

        if (!empty($landedCostAccountID)) {
            foreach ($glentries as &$glentry) {
                if ($glentry['DR_CR'] == '1') {
                    $glentry['GLACCOUNTKEY'] = $landedCostAccountID;
                }
            }
        }

        return true;
    }

    /**
     * @param array $nvalues
     * @param array $glentries
     *
     * @return bool
     */
    private function processBuildKits(&$nvalues, &$glentries)
    {
        $buildKits = ($nvalues['_DOCPAR']['DOCID'] == StkitDocumentManager::BUILDKIT);
        $disKits = ($nvalues['_DOCPAR']['DOCID'] == StkitDocumentManager::DISKIT);

        if (!$buildKits && !$disKits) {
            return true;
        }

        // build kits all credits should be for components
        if ($buildKits) {
            $trType = -1;
        } else {
            $trType = 1;
        }

        foreach ( $glentries as &$glentry) {
            if ($glentry['DR_CR'] == $trType) {
                $glentry['ITEMDIMKEY'] = $glentry['COMPONENTDIMKEY'];
            }
        }

        return true;
    }

    /**
     * @param array $nvalues
     * @param array $glentries
     *
     * @return bool
     */
    private function processTransferIET(&$nvalues, &$glentries)
    {
        if (!IsMultiEntityCompany() || empty($nvalues['IETDETAIL'])) {
            return true;
        }

        $isReceivable = ($nvalues['_DOCPAR']['DOCID'] == ICTransferManager::OUTDOCTYPE);
        $isPayable = ($nvalues['_DOCPAR']['DOCID'] == ICTransferManager::INDOCTYPE);

        if (!$isReceivable && !$isPayable) {
            return true;
        }

        if ($isReceivable) {
            $trType = 1;
            $acct = 'IERECEIVABLEACCTKEY';
        } else {
            $trType = -1;
            $acct = 'IEPAYABLEACCTKEY';
        }

        $gManagerFactory = Globals::$g->gManagerFactory;

        foreach ( $glentries as &$glentry) {
            if ($glentry['DR_CR'] == $trType) {
                $locDetail = $nvalues['IETDETAIL'];

                $acctMgr = $gManagerFactory->getManager('glaccount');
                $params = array(
                    'selects' => array('ACCOUNTNO'),
                    'filters' => array(array(array('RECORDNO', '=', $locDetail[$acct]))),
                );
                $acctRecs = $acctMgr->GetList($params);

                $glentry['GLACCOUNTKEY'] = $acctRecs[0]['ACCOUNTNO'];
            }
        }
        unset($glentry);

        return true;
    }

    /**
     * @param array $entry
     * @param array $glCouplets
     *
     * @return bool
     */
    private function processIETOnCOGS($entry, &$glCouplets)
    {
        if (!isset($entry['BASELOCATION'])) {
            return true;
        }

        $locMgr = Globals::$g->gManagerFactory->getManager('locationentity');
        $map = $locMgr->GetEntityLocationMapbyID();

        foreach ($glCouplets as &$glentry) {
            if ($glentry['DR_CR'] == -1) {
                // upate base location in case warehouse location is not matching with the lineitem location
                $glentry['BASELOCATION'] = $map[$glentry['LOCATION#']]['LOCATION#'];

                // now switch the location to that of the warehouse
                $glentry['LOCATION#'] = $entry['BASELOCATION'];
            }
        }

        return true;
    }

    /**
     * @param array     $nvalues
     * @param array     $glentries
     * @param string    $mod
     *
     * @return bool
     */
    function ProcessInvSubtotals(&$nvalues,&$glentries,$mod)
    {
        global $gErr;
        $ok=true;

        // Post subtotal gl entries
        if($nvalues['_DOCPAR']['SHOW_TOTALS'] == 'true' && $mod == 'inv') {
            $subtotals=$nvalues['SUBTOTALS'];
            $doctotal = 0;
            $lineentries = $nvalues['ENTRIES'];
            foreach ($lineentries as $entry) {
                $doctotal = bcadd($doctotal, $entry['VALUE']);
            }
            $docHdrRecordNumber = $nvalues['RECORDNO'];

            foreach($subtotals as $subtotal) {
                if ($subtotal['APPORTIONED'] == 'true') {
                    continue;
                }
                $subtotalglentries = $subtotal['GLENTRIES'];
                $subTotalKey = $subtotal['RECORDNO'];
                foreach($subtotalglentries as $subtotalglentry) {
                    if(!$subtotalglentry['GLACCOUNTKEY']) {
                        $gErr->addIAError(
                            'INV-0835', __FILE__ . ":" . __LINE__,
                            "A GL account is required for posting the subtotal '" . $subtotal['DESCRIPTION'] . "' , Please contact the administrator for configuring the transaction type - " . $nvalues['DOCPARID'] . ".",
                            ['SUBTOTAL_DESCRIPTION' => $subtotal['DESCRIPTION'], 'NVALUES_DOCPARID' => $nvalues['DOCPARID']]
                        );
                        return false;
                    }
                    if($subtotalglentry['VALUE'] == 0) {
                        continue;
                    }
                    if($subtotalglentry['GLOFFSETACCOUNTKEY']) {
                        $glentry1 = array (
                            'GLACCOUNTKEY' => $subtotalglentry['GLACCOUNTKEY'],
                            'DEPT#' => $subtotalglentry['DEPT#'],
                            'LOCATION#' => $subtotalglentry['LOCATION#'],
                            'ISOFFSET' => 'F',
                            'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '-1' : '1',
                            'AMOUNT' => $subtotalglentry['VALUE'],
                            'DOCHDRNO' => $docHdrRecordNumber,
                            'SUBTOTALKEY' => $subTotalKey,
                        );

                        $glentry2 = array (
                            'GLACCOUNTKEY' => $subtotalglentry['GLOFFSETACCOUNTKEY'],
                            'DEPT#' => $subtotalglentry['DEPT#'],
                            'LOCATION#' => $subtotalglentry['LOCATION#'],
                            'ISOFFSET' => 'T',
                            'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '1' : '-1',
                            'AMOUNT' => $subtotalglentry['VALUE'],
                            'DOCHDRNO' => $docHdrRecordNumber,
                            'SUBTOTALKEY' => $subTotalKey,
                        );

                        if($subtotal['CUSTOMDIMENSIONS'] != '') {
                            $glentry1['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                            $glentry2['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                        }
                        IADimensions::CopyIADimensionValues($subtotal, $glentry1, !util_isPlatformDisabled());
                        IADimensions::CopyIADimensionValues($subtotal, $glentry2, !util_isPlatformDisabled());

                        $glentries[] = array (
                            $glentry1,
                            $glentry2,
                        );
                    }
                    else {
                        $thisentry = array();
                        $glentry1 =  array (
                            'GLACCOUNTKEY' => $subtotalglentry['GLACCOUNTKEY'],
                            'DEPT#' => $subtotalglentry['DEPT#'],
                            'LOCATION#' => $subtotalglentry['LOCATION#'],
                            'ISOFFSET' => 'F',
                            'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '-1' : '1',
                            'AMOUNT' => $subtotalglentry['VALUE'],
                            'DOCHDRNO' => $docHdrRecordNumber,
                            'SUBTOTALKEY' => $subTotalKey,
                        );
                        if($subtotal['CUSTOMDIMENSIONS'] != '') {
                            $glentry1['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                        }
                        IADimensions::CopyIADimensionValues($subtotal, $glentry1, !util_isPlatformDisabled());

                        $thisentry[] = $glentry1;
                        // Prorate offset amoung line item offset accounts
                        $entries = $nvalues['ENTRIES'];
                        $entryCount = count($entries);
                        for($entry_no = 0; $entry_no < $entryCount; $entry_no++) {
                            if(!$this->_offsetaccts['INV'][$entry_no]) {
                                $gErr->addIAError(
                                    'INV-0836', __FILE__ . ":" . __LINE__,
                                    "A GL offset account could not determined for '" . $entries[$entry_no]['ITEMID'] . "' , Please contact the administrator for configuring the transaction type - " . $nvalues['DOCPARID'] . ".",
                                    ['ENTRIES_ENTRY_NO_ITEMID' => $entries[$entry_no]['ITEMID'], 'DOCPARID' => $nvalues['DOCPARID']]
                                );
                                return false;
                            }
                            // $doctotal/$entries[$entry_no]['COST'] * $subtotalglentry['VALUE']
                            /** @noinspection PhpUndefinedVariableInspection */
                            $offset_amt=ibcdiv(ibcmul($entries[$entry_no]['VALUE'], $subtotalglentry['VALUE'], DEFAULT_INVPRECISION, true), $doctotal, DEFAULT_INVPRECISION, true);
                            $glentry2 =  array (
                                'GLACCOUNTKEY' => $this->_offsetaccts['INV'][$entry_no],
                                'DEPT#' => $subtotalglentry['DEPT#'],
                                'LOCATION#' => $subtotalglentry['LOCATION#'],
                                'ISOFFSET' => 'T',
                                'DR_CR' => $subtotalglentry['DEBIT_CREDIT'] == 'Credit' ? '1' : '-1',
                                'AMOUNT' => $offset_amt,
                                'DOCHDRNO' => $docHdrRecordNumber,
                                'SUBTOTALKEY' => $subTotalKey,
                            );
                            if($subtotal['CUSTOMDIMENSIONS'] != '') {
                                $glentry2['CUSTOMDIMENSIONS'] = $subtotal['CUSTOMDIMENSIONS'];
                            }
                            IADimensions::CopyIADimensionValues($subtotal, $glentry2, !util_isPlatformDisabled());
                            $thisentry[] = $glentry2;
                        }
                        $glentries[] = $thisentry;
                    }
                }
            }
        }
        return $ok;
    }


    /**
     * function GetInventoryGLEntrykeys
     *
     * @param array $nvalues
     * @param array $glentries
     *
     * @return bool
     */
    function GetInventoryGLInfo(&$nvalues,/** @noinspection PhpUnusedParameterInspection */ &$glentries)
    {
        $ok=true;
        $i=0;
        foreach ( (($nvalues['ENTRIES']) ?? []) as $val) {
            foreach ( (($val['ITEMDETAILS']) ?? []) as $costEntry) {
                foreach ( (($costEntry['COSTDETAILS']) ?? []) as $costkeyEntry) {
                    if ($costkeyEntry['COST'] != 0) {
                        $entries[$i] = $costkeyEntry;
                        $i=$i+1;
                    }
                }
            }
        }

        return $ok;
    }


    /**
     * Create an inventory transaction
     *
     * @param string    $whencreated
     * @param array     $glentries
     * @param array     $docpar
     * @param int       $invbatchno
     * @param bool      $directGLPosting
     *
     * @return bool
     */
    function CreateInventoryTransaction($whencreated, &$glentries,
                                        $docpar,&$invbatchno, $directGLPosting=false
    )
    {

        global $gManagerFactory;
        $invBatchMgr = $gManagerFactory->getManager('invbatch');
        // create invbatch
        $invbatch = array();

        // We are using class variable to check while preparing the batch title in top level
        // If user in entity level and glbatch belong to top level then we should set the context to top level to get all the records
        // Because IET entires records should always having different entity informations
        if ($invBatchMgr->hasEntityLevelIETEntries($glentries)) {
            // Switching back to Top level context
            Database::switchToNonMegaContext();
        }

        // if batch doesnt exist it creates new batch
        // if batch exists for the given params it returns the existing batch.
        $ok = $invBatchMgr->GetBatch($whencreated, $docpar['DOCID'], $invbatch, $directGLPosting);

        // if failed to create / fetch existig batch then throw error
        if (!$ok || count($invbatch) == 0) {
            if (!$directGLPosting) {
                $batchtitle = "COGS";
            }
            // ******* ADD ERROR
            /** @noinspection PhpUndefinedVariableInspection */
            Globals::$g->gErr->addIAError(
                'INV-0837', __FILE__ . ':' . __LINE__,
                "Faild to create or find $batchtitle GL batch for " . $docpar['DOCID'],
                ['BATCHTITLE' => $batchtitle, 'DOCPAR_DOCID' => $docpar['DOCID']]
            );

            epp("unable to get an inventory batch.");
            $ok = false;
        } else {
            $invbatchno = $invbatch['RECORDNO'];
        }

        // Add glentries to batch
        $ok = $ok && $invBatchMgr->AddGLEntries($glentries, $invbatch, $directGLPosting);
        $ok = $ok && $this->CreateGLResolveMAP($glentries);

        // Switching back to Entity level context
        if ($invBatchMgr->hasEntityLevelIETEntries($glentries)) {
            Database::switchBackToMegaContext();
            unset($invBatchMgr->_hasEntityLevelCOGSIETEntries);
        }

        return $ok;
    }

    /**
     * @param array $glentries
     *
     * @return bool
     */
    function CreateGLResolveMAP($glentries)
    {
        if (empty($glentries)) {
            return true;
        }

        $cny = GetMyCompany();
        $ok = true;

        foreach ( $glentries as $glentry) {
            //
            // create maping entries in DEGLRESOLVE
            //
            if (isset($glentry['DOCENTRYCOST_INFO'])) {
                foreach ($glentry['DOCENTRYCOST_INFO'] as $docentrycost) {
                    if ($glentry['GLKEY'] != '') {
                        $values = array(
                            'DOCHDRKEY' => $docentrycost['DOCHDRNO'],
                            'DOCENTRYKEY' => $docentrycost['DOCENTRYKEY'],
                            // 'DOCENTRYCOSTKEY' => $docentrycost['DOCENTRYCOSTKEY'],
                            'GLENTRYKEY' => $glentry['GLKEY'],
                            'AMOUNT' => iround($docentrycost['AMOUNT'], 2),
                            'CURRENCY' => $glentry['BASECURR'],
                            'TRX_AMOUNT' => $docentrycost['TRX_AMOUNT'] ? iround($docentrycost['TRX_AMOUNT'], 2)
                                : iround($docentrycost['AMOUNT'], 2),
                            'ORIG_TRTYPE' => $glentry['DR_CR'],
                            'COGSPOSTING' => 'true',
                            'CNY#' => $cny,
                        );

                        $this->deGlResolves[$docentrycost['DOCENTRYKEY']][] = $values;
                    }
                }
            }
            if (isset($glentry['DOCENTRY_INFO'])) {
                foreach ( $glentry['DOCENTRY_INFO'] as $docentry) {
                    if ($glentry['GLKEY'] != '') {
                        $values = array(
                            'DOCHDRKEY' => $docentry['DOCHDRNO'],
                            'DOCENTRYKEY' => $docentry['DOCENTRYKEY'],
                            'GLENTRYKEY' => $glentry['GLKEY'],
                            'AMOUNT' => $docentry['AMOUNT'],
                            'CURRENCY' => $glentry['CURRENCY'],
                            'TRX_AMOUNT' => $docentry['TRX_AMOUNT'] ? iround($docentry['TRX_AMOUNT'], 2)
                                : iround($docentry['AMOUNT'], 2),
                            'ORIG_TRTYPE' => $docentry['ORIG_TRTYPE'],
                            'COGSPOSTING' => 'F',
                            'CNY#' => $cny,
                        );

                        $this->deGlResolves[$docentry['DOCENTRYKEY']][] = $values;
                    }
                }
            }
            //
            // create mapping entries in DEGLSUBTOTRESOLVE
            //
            if (isset($glentry['SUBTOTAL_INFO'])) {
                foreach ( $glentry['SUBTOTAL_INFO'] as $subtotal) {
                    $values = array(
                        'DOCHDRKEY' => $subtotal['DOCHDRNO'],
                        'SUBTOTKEY' => $subtotal['SUBTOTALKEY'],
                        'GLENTRYKEY' => $glentry['GLKEY'],
                        'AMOUNT' => $subtotal['AMOUNT'],
                        'CURRENCY' => $glentry['CURRENCY'],
                        'TRX_AMOUNT' => $subtotal['TRX_AMOUNT'] ? iround($subtotal['TRX_AMOUNT'], 2)
                            : iround($subtotal['AMOUNT'], 2),
                        'ORIG_TRTYPE' => $subtotal['ORIG_TRTYPE'],
                        'CNY#' => $cny,
                    );

                    $this->subtotalResolves[] = $values;
                }
            }
        }
        // This routine can get called multiple times.
        // when upserting, that causes us to delete existing entries each time, which is "bad".
        // but, when not upserting, and given that this routine is called from a number of places,
        // we'll just update each time....
        if ( ! DocumentManager::$upsertFeaturInUse) {
            $this->flushGLResolveMAP();
        }
        return $ok;
    }


    // If we called CreateResolveMAP(), above, with upsert ON, then we collected entries,
    // but did NOT write them to disk.  This is because CreateResolveMAP() might be called
    // TWICE, and the upsert logic will cause the existing records to be lost and, worse, cause
    // the FIRST upsert to be lost via the SECOND upsert.
    //
    //  So, here, we do the write if upsert is in use.
    /**
     * @return bool   did it work?
     */
    public function flushGLResolveMAP()
    {
        $ok = true;
        if ( ! empty($this->deGlResolves)) {
            $ok = $ok && DocumentEntryGLResolveManager::addOrUpsert($this->deGlResolves);
            $this->deGlResolves = [];   // in case we are called again, we don't re-do stuff
        }
        if ( ! empty($this->subtotalResolves)) {
            $ok = $ok && SubtotalGLResolveManager::addOrUpsert($this->subtotalResolves);
            $this->subtotalResolves = [];   // in case we are called again, we don't re-do stuff
        }
        return $ok;
    }


    /**
     * @param array     $entries
     * @param string    $mod
     * @param bool      $remove
     *
     * @return array
     */
    function SummarizeEntries($entries, /** @noinspection PhpUnusedParameterInspection */ $mod, $remove=false)
    {
        $newEntries = array();

        $count = 0;

        // BASELOCATION mapping is needed For IET purpose
        $newEntryKeyMap = array(
            'GLACCOUNTKEY',
            'DEPT#',
            'LOCATION#',
            'DR_CR',
            'BASELOCATION'
        );

        $entryKeyMap = array(
            'GLACCOUNTKEY',
            'DEPT#',
            'LOCATION#',
            'DR_CR',
            'BASELOCATION'
        );

        // when called before removeglentries
        // need to summarize the entries which are having same tr_type in TD and item gl group
        if ($remove) {
            $newEntryKeyMap[] = 'ORIG_TRTYPE';
            $entryKeyMap[] = 'ORIG_TRTYPE';
        }

        $dimensionKeys = IADimensions::GetDimensionKeys();

        if (!util_isPlatformDisabled() && IADimensions::isCustomDimensionsEnabled()) {
            $uddMap = Pt_StandardUtil::getGLDimensionFieldNames();
            if (count($uddMap) > 0) {
                $uddFields = array_values($uddMap);
                $dimensionKeys = array_merge($dimensionKeys, $uddFields);
            }
        }

        // we need to append gl dimensions to $currEntryKeyMap & $entryKeyMap
        if (isset($dimensionKeys) && count($dimensionKeys) > 0) {
            $newEntryKeyMap = array_merge($newEntryKeyMap, $dimensionKeys);
            $entryKeyMap = array_merge($entryKeyMap, $dimensionKeys);
        }

        if (empty($entries)) {
            $entries = [];
        }
        foreach ( $entries as $pair) {
            foreach ( $pair as $entry) {
                $foundIt = 0;

                foreach ($newEntries as $key => $newEntry) {

                    GetKeysByDimensionKeys(
                        $newEntryKeyMap, $entryKeyMap, $newEntry, $entry, $newEntrymapKey, $entrymapKey
                    );

                    if ($newEntrymapKey != '' && $entrymapKey != '' && ($newEntrymapKey == $entrymapKey)) {
                        if (isset($entry['TRX_AMOUNT']) && $entry['TRX_AMOUNT'] != '') {
                            $newEntries[$key]['TRX_AMOUNT'] = ibcadd(
                                iround($newEntries[$key]['TRX_AMOUNT'], 2), iround($entry['TRX_AMOUNT'], 2), 2
                            );
                        }

                        $newEntries[$key]['AMOUNT'] = ibcadd(
                            iround($newEntries[$key]['AMOUNT'], 2), iround($entry['AMOUNT'], 2), 2, true
                        );
                        $newEntries[$key]['DOCLINES'][] = $count;

                        $this->populateResolveMapInfo($entry, $newEntries[$key]);

                        $foundIt = 1;
                    }
                }
                if (!$foundIt) {
                    $entry['AMOUNT'] = iround($entry['AMOUNT'], 2);
                    $entry['DOCLINES'][] = $count;
                    if (is_numeric($entry['TRX_AMOUNT'])) {
                        $entry['TRX_AMOUNT'] = iround($entry['TRX_AMOUNT'], 2);
                    }

                    $this->populateResolveMapInfo($entry, $entry);

                    $newEntries[] = $entry;
                }
            }
            $count++;
        }

        return $newEntries;
    }


    /**
     * Populate $entryToPopulate with docentry or docentrycost details (record#, amount, trx_amount).
     * This information will be used in creating glentry resolve map
     *
     * @param array $entry
     * @param array $entryToPopulate
     */
    private function populateResolveMapInfo($entry, &$entryToPopulate)
    {
        $entry['AMOUNT'] = iround($entry['AMOUNT'], 2);
        $entry['TRX_AMOUNT'] = iround($entry['TRX_AMOUNT'], 2);

        if($entry['COGSPOSTING']) {
            $entryToPopulate['DOCENTRYCOST_INFO'][] = array(
                'DOCHDRNO'            => $entry['DOCHDRNO'],
                'DOCENTRYKEY'        => $entry['DOCENTRYKEY'],
                'AMOUNT'            => $entry['AMOUNT'],         // TODO: ask Jaggu
                'TRX_AMOUNT'        => $entry['TRX_AMOUNT'],     // TODO: ask Jaggu
            );
        } else if(isset($entry['DOCENTRYKEY']) && $entry['DOCENTRYKEY'] != '') {
            $entryToPopulate['DOCENTRY_INFO'][] = array(
                'DOCHDRNO'    => $entry['DOCHDRNO'],
                'DOCENTRYKEY'    => $entry['DOCENTRYKEY'],
                'AMOUNT'        => $entry['AMOUNT'],
                'TRX_AMOUNT'    => $entry['TRX_AMOUNT'],
            );
        }

        if(isset($entry['SUBTOTALKEY']) && $entry['SUBTOTALKEY'] != '') {
            $entryToPopulate['SUBTOTAL_INFO'][] = array(
                'DOCHDRNO'    => $entry['DOCHDRNO'],
                'SUBTOTALKEY'    => $entry['SUBTOTALKEY'],
                'AMOUNT'        => $entry['AMOUNT'],
                'TRX_AMOUNT'    => $entry['TRX_AMOUNT'],
                'TAXDETAILKEY'      => $entry['TAXDETAILKEY'] ?? '',
                'TAXABLEAMOUNT'     => $entry['TAXABLEAMOUNT'],
                'TRX_TAXABLEAMOUNT' => $entry['TRX_TAXABLEAMOUNT'],
                'PARTIALEXEMPT' => !empty($entry['PARTIALEXEMPT']) ? $entry['PARTIALEXEMPT'] : ''
            );
        }
    }

    /**
     * @param array $nvalues
     * @param array $glentries
     */
    function ProcessMCPGLEntries($nvalues, &$glentries)
    {
        $basecurr = (isset($nvalues['BASECURR']) && $nvalues['BASECURR'] != '') ? $nvalues['BASECURR']
            : GetBaseCurrency();

        if (!empty($glentries)) {
            $trx_currency = $nvalues['CURRENCY'] ?: $basecurr;

            foreach ( $glentries as &$glentry) {
                $glentry['CURRENCY'] = $trx_currency;
                $glentry['BASECURR'] = $basecurr;
                $glentry['EXCHANGE_RATE'] = $nvalues['EXCHRATE'];
                $glentry['EXCH_RATE_DATE'] = $nvalues['EXCHRATEDATE'];
                $glentry['EXCH_RATE_TYPE_ID'] = $nvalues['EXCH_RATE_TYPE_ID'];
            }
            unset($glentry);
        }
    }

    /**
     * Populate COGS / Additional GL posting entries
     *
     * @param array $nvalues
     * @param array $entries
     *
     * @return bool
     */
    private function processCOGSGLEntries($nvalues, &$entries)
    {
        $ok = true;

        /** @var DocumentManager $docMgr */
        $docMgr = Globals::$g->gManagerFactory->getManager($nvalues['_mod'] . 'document');
        $isIETOnCOGSPrefEnabled = $docMgr->isIETOnCOGSRequired();

        $isME = IsMultiEntityCompany();
        $map = [];
        if ($isME) {
            $locMgr = Globals::$g->gManagerFactory->getManager('locationentity');
            $map = $locMgr->GetEntityLocationMap();
        }

        foreach ((($nvalues['ENTRIES']) ?? []) as $docEntry) {
            $ok = $ok && $docMgr->setCustomDimensionsCache($docEntry);

            $isIETOnCOGSrequiredForGL = false;
            if ($isME) {
                $targetLocation = $map[$docEntry['WAREHOUSE']['LOCATIONREFKEY']]['ENTITY#'];
                $sourceLocation = $map[$docEntry['LOCATION#']]['ENTITY#'];
                if ($isIETOnCOGSPrefEnabled
                    && !empty($docEntry['WAREHOUSE']['LOCATIONREFKEY'])
                    && $targetLocation != $sourceLocation) {
                    $isIETOnCOGSrequiredForGL = true;
                }
            }

            foreach ((($docEntry['ITEMDETAILS']) ?? []) as $costEntry) {
                $entry = array();

                foreach ((($costEntry['COSTDETAILS']) ?? []) as $costkeyEntry) {

                    if (empty($entry)) {
                        $costkeyEntry['DOCENTRYNO'] = $docEntry['RECORDNO'];
                        $costkeyEntry['DOCHDRNO'] = $docEntry['DOCHDRNO'];

                        if ($docEntry['CUSTOMDIMENSIONS'] != '') {
                            $costkeyEntry['CUSTOMDIMENSIONS'] = $docEntry['CUSTOMDIMENSIONS'];
                        }
                        // copy Dimensions & Userdefined Dimensions
                        IADimensions::CopyIADimensionValues(
                            $docEntry, $costkeyEntry, !util_isPlatformDisabled()
                        );
                        if ($docEntry['ITEMTYPE'] == 'K'
                            && ($docEntry['ITEM']['REVPOSTING'] == 'Component Level' || $docEntry['REVPOSTING'] == 'I')
                        ) {
                            $costkeyEntry['ITEMDIMKEY'] = $costEntry['COMPONENTDIMKEY'];
                        } else if ($docEntry['ITEMTYPE'] == 'SK') {
                            $costkeyEntry['COMPONENTDIMKEY'] = $costEntry['COMPONENTDIMKEY'];
                            $costkeyEntry['SKITEMGLGROUP'] = $docEntry['SKITEMGLGROUP'];
                        }
                        $entry = $costkeyEntry;
                    } else {
                        $entry['COST'] = ibcadd($entry['COST'], $costkeyEntry['COST'], 14);
                        $entry['TRX_COST'] = ibcadd($entry['TRX_COST'], $costkeyEntry['TRX_COST'], 14);
                    }
                }

                if (!empty($entry)) {
                    if ($isIETOnCOGSrequiredForGL && in_array($costEntry['ITEMTYPE'], ['I', 'SK'])) {
                        // This will use for IETOnCOGS in GL entries to reassign the location#
                        $entry['BASELOCATION'] = $map[$docEntry['WAREHOUSE']['LOCATIONREFKEY']]['LOCATION_NO'];
                    }

                    $entries[] = $entry;
                }
            }
        }

        return $ok;
    }

    /**
     * @param array  $nvalues
     * @param string $entityGLGroup
     * @param string $docparkey DOCPARKEY of the parent documentparams
     * @param string $mod
     * @param array  $glentries
     * @param array  $prglLineFromTD
     * @param array  $revenueAccts
     *
     * @return bool
     * @throws Exception
     */
    function FindEntries(&$nvalues, $entityGLGroup, $docparkey, $mod, &$glentries, &$prglLineFromTD, &$revenueAccts)
    {
        global $gManagerFactory, $gErr;
        $ok = true;
        $spi = $nvalues['_DOCPAR']['SALE_PUR_TRANS'];

        $cny = GetMyCompany();

        $isMCPEnabled = IsMCPEnabled($nvalues['_mod']);
        $basecurr = GetBaseCurrency();

        $docMgr = $gManagerFactory->getManager('document');

        $isRetainageEnabled = false;
        if ( $mod == 'PR' && $nvalues['_mod'] === 'po' ) {
            $isRetainageEnabled = CRESetupManager::isAPRetainageEnabled();
        } else if ( $mod == 'PR' && $nvalues['_mod'] === 'so' ) {
            $isRetainageEnabled = CRESetupManager::isARRetainageEnabled();
        }

        // Cost
        $entries = [];
        if ($mod == 'INV') {
            $ok = $ok && $this->processCOGSGLEntries($nvalues, $entries);
        } else {

            // Revenue part

            $itemMgr = $gManagerFactory->getManager('item');

            foreach ( (($nvalues['ENTRIES']) ?? []) as $k => $unused) {
                $bundleNumber = $nvalues['ENTRIES'][$k]['BUNDLENUMBER'];
                if (!isset($nvalues['ENTRIES'][$k]['ITEMTYPE']) || $nvalues['ENTRIES'][$k]['ITEMTYPE'] == '') {
                    $ItemTypeValues = array(
                        'Inventory' => 'I', 'Non-Inventory' => 'NI', 'Non-Inventory (Purchase only)' => 'NP',
                        'Non-Inventory (Sales only)' => 'NS', 'Kit' => 'K', 'Stockable Kit' => 'SK'
                    );

                    $nvalues['ENTRIES'][$k]['ITEMTYPE'] = $ItemTypeValues[$nvalues['ENTRIES'][$k]['ITEM']['ITEMTYPE']];
                }

                if (!isset($nvalues['ENTRIES'][$k]['REVPOSTING']) || $nvalues['ENTRIES'][$k]['REVPOSTING'] == '') {
                    $revpostingValues = array('Component Level' => 'I', 'Kit Level' => 'K');
                    $nvalues['ENTRIES'][$k]['REVPOSTING']
                        = $revpostingValues[$nvalues['ENTRIES'][$k]['ITEM']['REVPOSTING']];
                }
    
                $isContractItem = (!empty($nvalues['ENTRIES'][$k]['BILLABLECONTRACTSCHENTRYKEY'])
                                   || !empty($nvalues['ENTRIES'][$k]['BILLABLECONTRACTUSAGEBILLINGID']));

                //when line item is kit and set for revenue split on components and not a contract kit
                if ($nvalues['ENTRIES'][$k]['ITEMTYPE'] == 'K'
                    && $nvalues['ENTRIES'][$k]['REVPOSTING'] == 'I'
                    && !$isContractItem
                ) {
                    $item['ITEMID'] = $nvalues['ENTRIES'][$k]['ITEMID'];
                    $docentrykey = $nvalues['ENTRIES'][$k]['RECORDNO'];
                    $dochdrkey = $nvalues['ENTRIES'][$k]['DOCHDRNO'];

                    $RevPosting = 'T';

                    if ($nvalues['ENTRIES'][$k]['LINEENTRYALLOCATION'] && isset($bundleNumber)
                        && $nvalues['_DOCPAR']['ENABLEREVREC'] == 'Post') {
                        $RevenueItems = $itemMgr->CollectItemCostDetailsVSOE(
                            $item, $nvalues['ENTRIES'][$k]['QUANTITY'],
                            $nvalues['ENTRIES'][$k]['LINEENTRYALLOCATION']
                        );
                    } else {
                        //these are the values we start with
                        $kitrevenue = $nvalues['ENTRIES'][$k]['ENDVALUE'];
                        if ($isMCPEnabled && $basecurr != $nvalues['CURRENCY']) {
                            $kitrevenue_trx = $nvalues['ENTRIES'][$k]['TRX_ENDVALUE'];
                        }

                        $RevenueItems = $itemMgr->CollectItemCostDetails(
                            $item, $nvalues['ENTRIES'][$k]['QUANTITY'], $RevPosting
                        );

                        foreach ($RevenueItems as $key => $val) {
                            /**
                             * Adjusting the VSOEREVRECACTION flag, this flag is used during rev. rec. schedule creation
                             * after the document is saved and posted to subledger and gl.
                             * A kit with component level posting is not part of the bundle and this transaction
                             * is vsoe enabled,
                             */
                            if (isset($nvalues['ENTRIES'][$k]['LINEENTRYALLOCATION'])) {
                                //there is a guard on the whole transaction level or within this kit there is undelivered bundle item
                                if ($nvalues['ENTRIES'][$k]['LINEENTRYALLOCATION']['KITHOLDALL']) {
                                    $RevenueItems[$key]['VSOEREVRECACTION'] = 'hold';
                                } else //otherwise, we need to look at the delivery status for itself. we don't have nested kit!!!
                                {
                                    //since the sequence we get might be different from the sequence we defined for the delivery status,
                                    //we need to find based on the item name
                                    $itemAllocations = $nvalues['ENTRIES'][$k]['LINEENTRYALLOCATION']['ITEMALLOCATION'];
                                    foreach ($itemAllocations as $itemAllocation) {
                                        if ($itemAllocation['ITEMCOMPONENTKEY'] == $val['ITEMID']) {
                                            if ($itemAllocation['DLVRSTATUS'] == 'Undelivered') {
                                                $RevenueItems[$key]['VSOEREVRECACTION'] = 'hold';
                                            } else {
                                                $RevenueItems[$key]['VSOEREVRECACTION'] = 'proceed';
                                            }
                                        }
                                    }
                                }
                            } else {
                                $RevenueItems[$key]['VSOEREVRECACTION'] = 'proceed';    //the existing logic pre-VSOE
                            }
                        }

                        $sumkitcomprevenue = 0;
                        $sumkitcomprevenue_trx = 0;

                        //now, based on the percentage we get, set the ENDVALUE for each component entry and get the sum
                        foreach ( $RevenueItems as $key => $val) {
                            $kitcomprevenue = bcmul(
                                $nvalues['ENTRIES'][$k]['ENDVALUE'], bcdiv($RevenueItems[$key]['REVPERCENT'], '100', 10),
                                2
                            );
                            $RevenueItems[$key]['ENDVALUE'] = $kitcomprevenue;
                            $sumkitcomprevenue += $kitcomprevenue;

                            if ($isMCPEnabled && $basecurr != $nvalues['CURRENCY']) {
                                $kitcomprevenue_trx = bcmul(
                                    $nvalues['ENTRIES'][$k]['TRX_ENDVALUE'],
                                    bcdiv($RevenueItems[$key]['REVPERCENT'], '100', 10), 2
                                );
                                $RevenueItems[$key]['TRX_ENDVALUE'] = $kitcomprevenue_trx;
                                $sumkitcomprevenue_trx += $kitcomprevenue_trx;
                            }
                        }

                        //now, do the rounding
                        $this->CorrectRoundOffError($kitrevenue, $sumkitcomprevenue, $RevenueItems, 'ENDVALUE');
                        if ($isMCPEnabled && $basecurr != $nvalues['CURRENCY']) {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $this->CorrectRoundOffError(
                                $kitrevenue_trx, $sumkitcomprevenue_trx, $RevenueItems, 'TRX_ENDVALUE'
                            );
                        }
                    }

                    $itemIDList = INTACCTarray_unique(
                        INTACCTarray_project($RevenueItems, 'ITEMID', false)
                    );
                    $itemList = $itemMgr->GetList(
                        [
                            'selects' => ['RECORDNO', 'ITEMID', 'GLGRPKEY'],
                            'filters' => [[['ITEMID', 'in', $itemIDList]]]
                        ]
                    );
                    $itemMap = resultSetToMapByColumn($itemList, 'ITEMID');

                    foreach ($RevenueItems as $key => $val) {

                        $RevenueItems[$key]['WAREHOUSE']['LOCATION_NO']
                            = $nvalues['ENTRIES'][$k]['WAREHOUSE']['LOCATION_NO'];

                        $RevenueItems[$key]['DEPARTMENT'] = $nvalues['ENTRIES'][$k]['DEPARTMENT'];
                        $RevenueItems[$key]['LOCATION'] = $nvalues['ENTRIES'][$k]['LOCATION'];

                        $row = $itemMap[$val['ITEMID']];
                        $RevenueItems[$key]['ITEMGLGROUP'] = $row['GLGRPKEY'];

                        $RevenueItems[$key]['MEMO'] = $nvalues['ENTRIES'][$k]['MEMO'];
                        $RevenueItems[$key]['LINENO'] = $nvalues['ENTRIES'][$k]['LINEKEY'];
                        $RevenueItems[$key]['LINEKEY'] = $nvalues['ENTRIES'][$k]['LINEKEY'];

                        // keep track of the docentrykey
                        $RevenueItems[$key]['RECORDNO'] = $docentrykey;
                        $RevenueItems[$key]['DOCHDRNO'] = $dochdrkey;

                        // the dimention should be of component
                        $RevenueItems[$key]['ITEMDIMKEY'] = $RevenueItems[$key]['COMPONENTDIMKEY'];

                        /*
                         * Allowing locationkey & deptkey to be avalaible in this array, So that while creating a row in
                         * prtaxentry will keep locatinokey, departmentkey
                         */
                        $RevenueItems[$key][':locationkey'] = $nvalues['ENTRIES'][$k]['LOCATIONKEY'];
                        $RevenueItems[$key][':deptkey'] = $nvalues['ENTRIES'][$k]['DEPTKEY'];

                        // copy dimension fields from nvalues array to RevenueItems
                        IADimensions::CopyIADimensionValues(
                            $nvalues['ENTRIES'][$k], $RevenueItems[$key], !util_isPlatformDisabled()
                        );

                        if ($nvalues['ENTRIES'][$k]['CUSTOMDIMENSIONS'] != '') {
                            $RevenueItems[$key]['CUSTOMDIMENSIONS'] = $nvalues['ENTRIES'][$k]['CUSTOMDIMENSIONS'];
                        }

                        $entries[] = $RevenueItems[$key];
                    }
                } // Item or Kit with kit level revenue posting
                else {
                    $vsoeAllocation = $nvalues['ENTRIES'][$k]['LINEENTRYALLOCATION'];
                    if ($vsoeAllocation && $nvalues['_DOCPAR']['ENABLEREVREC'] == 'Post') {
                        //if we are part of bundle, set ENDVALUE to our calculated VSOEALLOCATION value. Otherwise, use the
                        //existing ENDVALUE already set.
                        if (isset($bundleNumber) && isset($vsoeAllocation['ITEMALLOCATION'][0]['VSOEALLOCATION'])) {
                            $nvalues['ENTRIES'][$k]['ENDVALUE']
                                = $vsoeAllocation['ITEMALLOCATION'][0]['VSOEALLOCATION'];
                            $nvalues['ENTRIES'][$k]['TRX_ENDVALUE']
                                = $vsoeAllocation['ITEMALLOCATION'][0]['TRX_VSOEALLOCATION'];
                        }

                        if ($vsoeAllocation['KITHOLDALL']) {
                            $nvalues['ENTRIES'][$k]['VSOEREVRECACTION']
                                = 'hold';   //always book to def. rev. account. Schedule status
                            //is "On Hold" if Schedule is created(template are found)
                        } else {
                            if ($vsoeAllocation['ITEMALLOCATION'][0]['DLVRSTATUS'] == 'Undelivered') {
                                //always book to def. rev. account.
                                //Schedule status is "On Hold" if Schedule is created(template are found)
                                $nvalues['ENTRIES'][$k]['VSOEREVRECACTION'] = 'hold';
                            }
                            else {
                                $nvalues['ENTRIES'][$k]['VSOEREVRECACTION'] = 'proceed';   //the existing logic
                            }
                        }
                    }

                    $entries[] = $nvalues['ENTRIES'][$k];
                }
            }
        }

        $this->_offsetaccts[$mod] = array();
        $glentries = array();
    
        $debitItemGLGroup = '';
        $creditItemGLGroup = '';
        $contextLocation = GetContextLocation(true);
        $isME = IsMultiEntityCompany();
        $offsetCache = [];
        //  THIS IS RUNNING FOR EACH LINE
        $lineCount = Util::countOrZero($entries);
        for ( $i = 0; $i < $lineCount; $i++) {

            // $amount = $cost if INV or $price if PR

            // FOR NOW WE GET THE LATEST OFFSET ACCTS,
            // BUT WE SHOULD REALLY BE LOOKING AT THE DOCPAR STORED WITH THE DOCUMENT
            // THIS SHOULD BE FIXED THE MOMENT the BLOBS ARE MOVED TO THE DB.
            $itemid = $entries[$i]['ITEMID'];
            $whsekey = $entries[$i]['WAREHOUSE']['LOCATION_NO'];
            $itemGLGroup = $entries[$i]['ITEMGLGROUP'];
            $SkItemGLGroup = $entries[$i]['SKITEMGLGROUP'];
            $ok = $ok && $this->overrideItemGlGroups($nvalues, $entries[$i], $itemGLGroup, $creditItemGLGroup, $debitItemGLGroup);
            $memo = $entries[$i]['MEMO'];
            $allocation = $entries[$i]['ALLOCATION'];

            $departmentID = explode('--', $entries[$i]['DEPARTMENT']);
            $departmentID = array_shift($departmentID);
            $locationID   = explode('--', $entries[$i]['LOCATION']);
            $locationID   = array_shift($locationID);

            // defaulting for MEGA entity Context

            $locationID = (($locationID == '' && $isME && $contextLocation != '' && $allocation == '') ? $contextLocation : $locationID);

            if ($mod == 'INV') {
                $cogsposting = true;
                $docentrykey = $entries[$i]['DOCENTRYNO'];
                $dochdrkey = $entries[$i]['DOCHDRNO'];
                $amount = $entries[$i]['COST'];
                $trxamount = $entries[$i]['TRX_COST'] ?: $amount;
                if ($spi != 'Sale') {
                    $entityGLGroup = '';
                }
            } else {
                $cogsposting = false;
                $docentrykey = $entries[$i]['RECORDNO'];
                $dochdrkey = $entries[$i]['DOCHDRNO'];
                $amount = $entries[$i]['ENDVALUE'];
                // TRX_ENDVALUE is a processed data (extra processing like subtotals after it gets assigned from TRX_VALUE)
                // if this is missing in the structure the TRX_ENDVALUE should be TRX_VALUE
                // Ex: when we run the RecalcDirectGLResolve tool for fixing data corruption cases.
                if (isset($entries[$i]['TRX_ENDVALUE']) && $entries[$i]['TRX_ENDVALUE'] !== '') {
                    $trxamount = $entries[$i]['TRX_ENDVALUE'];
                } else {
                    $trxamount = $entries[$i]['TRX_VALUE'];
                }
            }


            // Contract has own account mappings
            if (!empty($entries[$i]['BILLABLECONTRACTSCHENTRYKEY']) || !empty($entries[$i]['BILLABLECONTRACTUSAGEBILLINGID'])) {
                $ok = $this->getContractGLlines($entries[$i], $nvalues, $glines);
                if (!$ok) {
                    break;
                }
            } else {
                $offsetString = $cny. '~' .$docparkey. '~' . $debitItemGLGroup . '~' . $creditItemGLGroup . '~'
                                .$whsekey. '~' .$entityGLGroup. '~' .$mod;
                if(!isset($offsetCache[$offsetString])){
                    //for build kits we need to take the Item GL group of the st kit for the debit side
                    if($nvalues["DOCPARID"] == StkitDocumentManager::BUILDKIT ){
                        $debitItemGLGroup = $SkItemGLGroup;
                    }else{
                        $debitItemGLGroup = $itemGLGroup;
                    }
                    //for disassemble kits we need to take the Item GL group of the st kit for the credit side
                    if($nvalues["DOCPARID"] == StkitDocumentManager::DISKIT ){
                        $creditItemGLGroup = $SkItemGLGroup;
                    }else{
                        $creditItemGLGroup = $itemGLGroup;
                    }
                    $args = array(
                        'F', $cny, $docparkey, $debitItemGLGroup, $whsekey, $entityGLGroup, 1, $mod, 1,
                        'F', $cny, $docparkey, $creditItemGLGroup, $whsekey, $entityGLGroup, -1, $mod, 1
                    );
                    $offsetCache[$offsetString] = $docMgr->DoQuery('QRY_DOCUMENT_FIND_OFFSETACCTS', $args);
                }
                $glines = $offsetCache[$offsetString];
            }
            // Find Debit Credits for the item group
            if (Util::countOrZero($glines) == 2) {
                $glines[0]['AMOUNT'] = $amount;
                $glines[1]['AMOUNT'] = $amount;

                $glines[0]['TRX_AMOUNT'] = $trxamount;
                $glines[1]['TRX_AMOUNT'] = $trxamount;
                if ($mod == 'PR' || $mod == 'ADD') {
                    // VAGUE CODE HERE -> Tag item's gl account for use in prtaxentry
                    if ($glines[0]['ISOFFSET'] != 'T') {
                        $glines[0]['ITEMID'] = $itemid;
                        $glines[0]['DESC'] = $memo;
                    } else {
                        $glines[1]['ITEMID'] = $itemid;
                        $glines[1]['DESC'] = $memo;
                    }
                }
                if ($nvalues['_DOCPAR']['LOCOVERRIDE'] == 'true') {
                    $glines[0]['LOCATION#'] = $locationID;
                    $glines[1]['LOCATION#'] = $locationID;
                }

                if ($nvalues['_DOCPAR']['DEPTOVERRIDE'] == 'true') {
                    $glines[0]['DEPT#'] = $departmentID;
                    $glines[1]['DEPT#'] = $departmentID;
                }

                // get the dochdr, docentry, docentrycost keys which will be used in generating glentry resolve maps
                if (isset($dochdrkey) && $dochdrkey != '') {
                    $glines[0]['DOCHDRNO'] = $dochdrkey;
                    $glines[1]['DOCHDRNO'] = $dochdrkey;
                }
                if (isset($docentrykey) && $docentrykey != '') {
                    $glines[0]['DOCENTRYKEY'] = $docentrykey;
                    $glines[1]['DOCENTRYKEY'] = $docentrykey;
                }
                $glines[0]['COGSPOSTING'] = $cogsposting;
                $glines[1]['COGSPOSTING'] = $cogsposting;

                // copy dimension fields from entry array to newEntry
                IADimensions::CopyIADimensionValues($entries[$i], $glines[0], !util_isPlatformDisabled());
                IADimensions::CopyIADimensionValues($entries[$i], $glines[1], !util_isPlatformDisabled());

                if ($entries[$i]['CUSTOMDIMENSIONS'] != '') {
                    $glines[0]['CUSTOMDIMENSIONS'] = $entries[$i]['CUSTOMDIMENSIONS'];
                    $glines[1]['CUSTOMDIMENSIONS'] = $entries[$i]['CUSTOMDIMENSIONS'];
                }

                if ($entries[$i]['ALLOCATION'] != '') {
                    $glines[0]['ALLOCATION'] = $entries[$i]['ALLOCATION'];
                    $glines[1]['ALLOCATION'] = $entries[$i]['ALLOCATION'];
                }

                if ($entries[$i]['ALLOCATIONKEY'] !== '') {
                    $glines[0]['ALLOCATIONKEY'] = $entries[$i]['ALLOCATIONKEY'];
                    $glines[1]['ALLOCATIONKEY'] = $entries[$i]['ALLOCATIONKEY'];

                    $glines[0]['SPLITNO'] = $entries[$i]['SPLITNO'];
                    $glines[1]['SPLITNO'] = $entries[$i]['SPLITNO'];
                }

                $linenofield = 'LINEKEY';

                $glines[0]['DOC_LINENO'] = $entries[$i][$linenofield];
                $glines[1]['DOC_LINENO'] = $entries[$i][$linenofield];

                $glines[0]['LINE_NO'] = $entries[$i]['LINE_NO'];
                $glines[1]['LINE_NO'] = $entries[$i]['LINE_NO'];

                $glines[0]['ITEMGLGROUP'] = $itemGLGroup;
                $glines[1]['ITEMGLGROUP'] = $itemGLGroup;

                $glines[1]['VSOEREVRECACTION'] = $entries[$i]['VSOEREVRECACTION'];

                // Collect resolved revenue gl lines value for each doc entry
                if ($mod == 'PR') {

                    // for landed cost debit account should be changed from inventory to landed cost account
                    if ($entries[$i]['LANDEDCOST'] == "true") {
                        $ok = $ok && $this->processLandedCost($nvalues, $glines);
                    }

                    // Collecting above lines in $this->_prglLineFromTD
                    $prglLineFromTD['GLLINES_' . $i] = $glines;
                }

                if ($mod == 'INV') {
                    $glines[0]['COMPONENTDIMKEY'] = $entries[$i]['COMPONENTDIMKEY'];
                    $glines[1]['COMPONENTDIMKEY'] = $entries[$i]['COMPONENTDIMKEY'];

                    foreach ( $glines as &$glentry) {
                        $glentry['BASECURR'] = $entries[$i]['BASECURR'];
                        $glentry['CURRENCY'] = $entries[$i]['CURRENCY'] ?: $entries[$i]['BASECURR'];
                        $glentry['EXCHANGE_RATE'] = $entries[$i]['EXCHANGE_RATE'];
                        $glentry['EXCH_RATE_DATE'] = $entries[$i]['EXCH_RATE_DATE'];
                        $glentry['EXCH_RATE_TYPE_ID'] = $entries[$i]['EXCH_RATE_TYPE_ID'];
                    }

                    $ok = $ok && $this->processTransferIET($nvalues, $glines);
                    $ok = $ok && $this->processIETOnCOGS($entries[$i], $glines);
                    $ok = $ok && $this->processBuildKits($nvalues, $glines);
                }

                if ( $isRetainageEnabled ) {
                    $glines[0]['RETAINAGEPERCENTAGE'] = $entries[$i]['RETAINAGEPERCENTAGE'];
                    $glines[0]['TRX_AMOUNTRETAINED'] = $entries[$i]['TRX_AMOUNTRETAINED'];
                    $glines[0]['AMOUNTRETAINED'] = $entries[$i]['AMOUNTRETAINED'];

                    $glines[1]['RETAINAGEPERCENTAGE'] = $entries[$i]['RETAINAGEPERCENTAGE'];
                    $glines[1]['TRX_AMOUNTRETAINED'] = $entries[$i]['TRX_AMOUNTRETAINED'];
                    $glines[1]['AMOUNTRETAINED'] = $entries[$i]['AMOUNTRETAINED'];
                }

                // Collecting $glines in $glentries
                $glentries[] = $glines;
                //  collecting offset a/c numbers into $this->_offsetaccts
                $this->_offsetaccts[$mod][$i] = $glines[0]['ISOFFSET'] == 'T' ? $glines[0]['GLACCOUNTKEY']
                    : $glines[1]['GLACCOUNTKEY'];

                if ($mod == 'PR' || $mod == 'ADD') {
                    //  THIS CODE IS NOT FOR SUBTOTALS, SO NO NEED TO TRANSFER IT TO SUBTOTALS
                    //  THIS CODE COLLECTS POSTING INFORMATION  REQUIRED FOR AR/GL
                    //  THE OBJECT VARIABLES USED HERE ARE NOT EXCLUSIVELY USED
                    //  EITHER FOR SUBTOTALS OR PRTAXENTRY
                    if ($this->_itemLines[$entries[$i]['ITEMID']]) {
                        //Creating a new varibale 'SALEAMT' inside a new variable $this->_itemLines
                        $this->_itemLines[$entries[$i]['ITEMID']]['SALEAMT']
                            = $this->_itemLines[$entries[$i]['ITEMID']]['SALEAMT'] + $entries[$i]['UIVALUE'];
                    } else {
                        $taxgrp = $this->getItemTaxGroup($entries[$i]['ITEMID']);
                        $linekey = $entries[$i]['ITEMID'] . '--' . $entries[$i]['LINEKEY'];

                        $this->_itemLines[$linekey] = array(
                            'ITEMID' => $entries[$i]['ITEMID'],
                            'SALEAMT' => $entries[$i]['ENDVALUE'],
                            //  these 2 lines are taken from $glines
                            //  assigning GLACCOUNTKEY & DR_CR for non-OFFSET entries.
                            'GLACCOUNTKEY' => $glines[0]['ISOFFSET'] != 'T' ? $glines[0]['GLACCOUNTKEY']
                                : $glines[1]['GLACCOUNTKEY'],
                            'DR_CR' => $glines[0]['ISOFFSET'] != 'T' ? $glines[0]['DR_CR'] : $glines[1]['DR_CR'],
                            //------------------------------------------------
                            'ITEMTAXGRPKEY' => $taxgrp[0]['TAXGROUPKEY'],
                            'TAXABLE' => $entries[$i]['TAXABLE'] ?? 'false',
                            'LOCATION' => $entries[$i]['LOCATION'],
                            'DEPARTMENT' => $entries[$i]['DEPARTMENT'],
                            'DEPTKEY' => $entries[$i]['DEPTKEY'],
                            'LOCATIONKEY' => $entries[$i]['LOCATIONKEY'],

                        );
                    }

                    // Collect revenue account for a docentry-item combination
                    if ($glines[0]['ISOFFSET'] == 'T'
                        && ($glines[1]['ISOFFSET'] == 'F'
                            || $glines[1]['ISOFFSET'] == '')) {
                        $revacct = $glines[1]['GLACCOUNTKEY'];
                        $tr_type = $glines[1]['DR_CR'];
                    } elseif ($glines[1]['ISOFFSET'] == 'T'
                        && ($glines[0]['ISOFFSET'] == 'F'
                            || $glines[1]['ISOFFSET'] == '')) {
                        $revacct = $glines[0]['GLACCOUNTKEY'];
                        $tr_type = $glines[0]['DR_CR'];
                    } else {
                        // Either both are offset or none
                        // Take 'Credit' account
                        if ($glines[0]['DR_CR'] == '-1') {
                            $revacct = $glines[0]['GLACCOUNTKEY'];
                            $tr_type = $glines[0]['DR_CR'];
                        } else {
                            $revacct = $glines[1]['GLACCOUNTKEY'];
                            $tr_type = $glines[1]['DR_CR'];
                        }
                    }

                    $revAcctMapKey = self::getRevAcctMapKey($docentrykey, $itemid, $mod);
                    if (isset($revenueAccts[$revAcctMapKey]) && $revenueAccts[$revAcctMapKey] !== '') {

                        if (($revenueAccts[$revAcctMapKey]['ACCOUNTNO'] != $revacct) ||
                            ($revenueAccts[$revAcctMapKey]['TR_TYPE']   != $tr_type)) {
                            throw new Exception(
                                'Internal error in SCMSubledgerHandler::FindEntries: revenueAccts for ' . $revAcctMapKey
                                . ' is already set to: ' . var_export($revenueAccts[$revAcctMapKey], true)
                            );
                        }
                    }

                    $revenueAccts[$revAcctMapKey] = [
                        'ACCOUNTNO' => $revacct,
                        'TR_TYPE' => $tr_type
                    ];
                }
            } else {
                $this->getGLAccountMappingErrorMessage($entries[$i],
                    $nvalues['_DOCPAR'],
                    $mod,
                    $errNo,
                    $description1,
                    $description2,
                    $correction,
                    $description1Placeholder,
                    $description2Placeholder,
                    $correctionPlaceholder);

                if (!empty($errNo)) {
                    $gErr->addIAError(
                        $errNo, __FILE__ . ':' . __LINE__,
                        $description1, $description1Placeholder,
                        $description2, $description2Placeholder,
                        $correction, $correctionPlaceholder
                    ); //TODO:i18N-INV-Error-Message (code change review)
                    $ok = false;
                }

            }
        }

        return $ok;
    }

    /**
     * @param array $entry
     * @param array $docpar
     * @param string $mod
     * @param string $errNo
     * @param string $description1
     * @param string $description2
     * @param string $correction
     */
    private function getGLAccountMappingErrorMessage($entry, $docpar, $mod, &$errNo, &$description1, &$description2, &$correction, &$description1Placeholder, &$description2Placeholder, &$correctionPlaceholder)
    {
        $errNo = '';
        $description1 = '';
        $description2 = '';
        $correction = '';
        $description1Placeholder = [];
        $description2Placeholder = [];
        $correctionPlaceholder = [];

        $spi = $docpar['SALE_PUR_TRANS'];
        $itemid = $entry['ITEMID'];
        $whsekey = $entry['WAREHOUSE']['LOCATION_NO'];
        $itemType = $entry['ITEMTYPE'];
        $templateId = $docpar['DOCID'];

        if ($mod == 'PR') {
            $subledger = ($docpar['UPDATES_GL'] == 'G') ? 'GL'
                : (($spi == 'Sale') ? 'AR' : 'AP');
            $sbl = ($spi == 'Sale') ? 'AR' : 'AP';

            if (IsAdvancedConfiguration()) {
                $errNo = 'INV-0854';
                $description1 = "Your $templateId transaction definition is configured to affect $subledger. " .
                    "However, no GL Accounts were found in the $sbl GL Information tab for itemid " .
                    "'$itemid' and warehouse '$whsekey'.";
                $description1Placeholder = ['TEMPLATE_ID' => $templateId, 'SUBLEDGER' => $subledger, 'SBL' => $sbl, 'ITEMID' => $itemid, 'WHSEKEY' => $whsekey];
            } else {
                $errNo = 'INV-0855';
                $description1 = "Your $templateId transaction definition is configured to affect $subledger. " .
                    "You must define the posting account for this transaction";
                $correction = 'Please select the offset accounts in the setup screen and/or the item information';
                $description1Placeholder = ['TEMPLATE_ID' => $templateId, 'SUBLEDGER' => $subledger];
            }
        }

        if ($mod == 'ADD' && $docpar['POSTTOGL'] == 'true' && $spi == 'Sale') {
            if (IsAdvancedConfiguration()) {
                $errNo = 'INV-0856';
                $description1 = "Your $templateId transaction definition has enabled 'Additional GL posting' ".
                    "However, no GL Accounts were found in the Additional GL posting account mapping tab for itemid " .
                    "'$itemid' and warehouse '$whsekey'.";
                $description1Placeholder = ['TEMPLATE_ID' => $templateId, 'ITEMID' => $itemid, 'WHSEKEY' => $whsekey];
            }
        }

        if ($mod == 'INV'
            && ($itemType == 'I' || $itemType == 'SK')) {
            $errNo = 'INV-0857';
            $description1 = "Your $templateId transaction definition is configured to affect COGS" .
                " However, no GL Accounts were found in the COGS GL Information tab for itemid " .
                "'$itemid' and warehouse '$whsekey'.";
            $description1Placeholder = ['TEMPLATE_ID' => $templateId, 'ITEMID' => $itemid, 'WHSEKEY' => $whsekey];
        }

    }

    /**
     * Returns gl lines in expected format
     *
     * @param   array     $entry          Doc entry attributes
     * @param   array   $nvalues        Document attributes
     * @param   array   $glLines        Return gl lines
     *
     * @return bool
     */
    protected function getContractGLlines($entry, &$nvalues, &$glLines)
    {
        // Force override
        $nvalues['_DOCPAR']['LOCOVERRIDE'] = 'true';
        $nvalues['_DOCPAR']['DEPTOVERRIDE'] = 'true';

        $ok = true;
        if ($entry['BILLABLECONTRACTSCHENTRYKEY']) {

            $ok = $this->getContractGLlinesFromScheduleEntry($entry, $nvalues, $glLines);

        } else if ($entry['BILLABLECONTRACTUSAGEBILLINGID']) {

            $ok = $this->getContractGLlinesFromUsage($entry, $nvalues, $glLines);

        }

        return $ok;
    }

    /**
     * Returns gl lines in expected format from schedule entry
     *
     * @param   array   $entry          Doc entry attributes
     * @param   array   $nvalues        Document attributes
     * @param   array   $glLines        Return gl lines
     *
     * @return bool
     */
    protected function getContractGLlinesFromScheduleEntry($entry, /** @noinspection PhpUnusedParameterInspection */ &$nvalues, &$glLines)
    {
        $ok = true;

        // This is update scenario
        if (!($entry['ARBILLEDACCTNO'] && $entry['DRBILLEDACCTNO'])) {
            $cnDetailKey = $this->getContractDetailKeyFromScheduleEntry($entry['BILLABLECONTRACTSCHENTRYKEY']);

            if (!$cnDetailKey) {
                Globals::$g->gErr->addIAError('INV-0838', '',
                    sprintf("Could not find Contract Detail for Billing schedule entry: %s", $entry['BILLABLECONTRACTSCHENTRYKEY']),
                    ['ENTRY_BILLABLECONTRACTSCHENTRYKEY' => $entry['BILLABLECONTRACTSCHENTRYKEY']]
                );
            }

            $accts = EntityManager::GetListQuick(
                'contractdetail',
                ['ARBILLEDACCTNO', 'DRBILLEDACCTNO'],
                ['RECORDNO' => $cnDetailKey]
            );

            $entry['ARBILLEDACCTNO'] = $accts[0]['ARBILLEDACCTNO'];
            $entry['DRBILLEDACCTNO'] = $accts[0]['DRBILLEDACCTNO'];
        }

        if (!$entry['ARBILLEDACCTNO']) {
            Globals::$g->gErr->addIAError('INV-0255', '', 'AR Billed account is not set.',[]);
            $ok = false;
        }

        if (!$entry['DRBILLEDACCTNO']) {
            Globals::$g->gErr->addIAError('INV-0256', '', 'Deferred Billed account is not set.',[]);
            $ok = false;
        }

        if ($ok) {
            $dbAcct = $entry['ARBILLEDACCTNO'];
            $crAcct = $entry['DRBILLEDACCTNO'];

            $glLines = $this->constructContractGLlines($dbAcct, $crAcct);
        }

        return $ok;
    }

    /**
     * Returns gl lines in expected format from usage
     *
     * @param   array   $entry          Doc entry attributes
     * @param   array   $nvalues        Document attributes
     * @param   array   $glLines        Return gl lines
     *
     * @return bool
     */
    protected function getContractGLlinesFromUsage($entry, /** @noinspection PhpUnusedParameterInspection */ &$nvalues, &$glLines)
    {
        $ok = true;

        // This is update scenario
        if (!($entry['ARBILLEDACCTNO'] && $entry['SALESBILLEDACCTNO'])) {
            $cnDetailKey = $this->getContractDetailKeyFromUsage($entry['BILLABLECONTRACTUSAGEBILLINGID']);

            if (!$cnDetailKey) {
                Globals::$g->gErr->addIAError('INV-0839', '',
                    sprintf("Could not find Contract Detail for Usage billing id: %s", $entry['BILLABLECONTRACTUSAGEBILLINGID']),
                    ['ENTRY_BILLABLECONTRACTUSAGEBILLINGID' => $entry['BILLABLECONTRACTUSAGEBILLINGID']]
                );
            }

            $accts = EntityManager::GetListQuick(
                'contractdetail',
                ['ARBILLEDACCTNO', 'SALESBILLEDACCTNO'],
                ['RECORDNO' => $cnDetailKey]
            );

            $entry['ARBILLEDACCTNO'] = $accts[0]['ARBILLEDACCTNO'];
            $entry['SALESBILLEDACCTNO'] = $accts[0]['SALESBILLEDACCTNO'];
        }

        if (!$entry['ARBILLEDACCTNO']) {
            Globals::$g->gErr->addIAError('INV-0257', '', 'AR Billed account is not set.',[]);
            $ok = false;
        }

        if (!$entry['SALESBILLEDACCTNO']) {
            Globals::$g->gErr->addIAError('INV-0258', '', 'Sales Billed account is not set.',[]);
            $ok = false;
        }

        if ($ok) {
            $dbAcct = $entry['ARBILLEDACCTNO'];
            $crAcct = $entry['SALESBILLEDACCTNO'];

            $glLines = $this->constructContractGLlines($dbAcct, $crAcct);
        }

        return $ok;
    }

    /**
     * Constructs gl lines structure
     *
     * @param   string  $dbAcct     DB account
     * @param   string  $crAcct     CR account
     *
     * @return array
     */
    private function constructContractGLlines($dbAcct, $crAcct)
    {
        $glLines = [
            [
                'GLACCOUNTKEY' => $crAcct,
                'ISOFFSET' => 'F',
                'DR_CR' => -1
            ],
            [
                'GLACCOUNTKEY' => $dbAcct,
                'ISOFFSET' => 'T',
                'DR_CR' => 1
            ]
        ];

        return $glLines;
    }

    /**
     * Returns contract detail key from billing schedule entry
     *
     * @param  int  $schEntryKey        Billing Schedule Entry key
     *
     * @return null|string
     */
    protected function getContractDetailKeyFromScheduleEntry($schEntryKey)
    {
        $schEntry = EntityManager::GetListQuick(
            'contractbillingscheduleentry',
            ['CONTRACTDETAILKEY'],
            ['RECORDNO' => $schEntryKey]
        );

        return $schEntry[0]['CONTRACTDETAILKEY'];
    }

    /**
     * Returns contract detail key for usage billing id
     *
     * @param  int  $usageBillingId     Usage billing id
     *
     * @return null|string
     */
    protected function getContractDetailKeyFromUsage($usageBillingId)
    {
        $usageBilling = EntityManager::GetListQuick(
            'contractusagebilling',
            ['CONTRACTDETAILKEY'],
            ['USAGEBILLINGID' => $usageBillingId]
        );

        return $usageBilling[0]['CONTRACTDETAILKEY'];
    }


    /**
     * @param int|float $totalamt       Amount to be prorated or Original amount
     * @param int|float $distamt        distamt Sum of prorated amounts
     * @param array     $amounts        array with AMOUNT field to be corrected
     * @param string    $amtfield
     */
    function CorrectRoundOffError($totalamt,$distamt,&$amounts,$amtfield='AMOUNT')
    {
        //eppp_p("totalamt:".$totalamt);
        //eppp_p("distamt:".$distamt);

        // nothing to fix
        if($totalamt == 0) {
            return;
        }

        // nothing to fix
        if(!count($amounts)) {
            return;
        }

        // This can happen when 0.01 is to be distributed amoung more than 1 line item.
        // In case of 2 line items distributed amount will be 0.005 and 0.005, round(0.005, 2) = 0.00
        // Total amount needs to be very small for this to happen.
        // Any thing > 1 is potentially invalid input

        if($distamt == 0 && $totalamt > 1) {
            return;
        }

        if($distamt == 0 && $totalamt < 1) {
            $sign = 1;
            if($totalamt < 0) {
                $sign = -1;
            }

            $penny = 0.01 * $sign;
            //eppp_p("penny:".$penny);

            // Give out total amount penny by penny
            while($totalamt != 0) {
                foreach( $amounts as $key => $amount) {
                    // Give
                    $amounts[$key][$amtfield] = ibcadd($amounts[$key][$amtfield], $penny, DEFAULT_INVPRECISION, true);

                    // Take out
                    /** @var float $totalamt */
                    $totalamt =(float) ibcsub($totalamt, $penny, DEFAULT_INVPRECISION, true);
                    //eppp_p("totalamt:".$totalamt);

                    // All done
                    if($totalamt == 0) {
                        break;
                    }
                }
            }

            return;
        }

        // When distamt and totalamt are not 0

        // Check for rounding differences
        $diff = ibcsub($totalamt, $distamt, DEFAULT_INVPRECISION, true);
        //eppp_p("diff:".$diff);

        // Sign represents -ve for roundup and +ve for rounddown
        $sign = 1;
        if ($diff != 0) {
            $sign = ibcdiv($diff, ibcabs($diff), DEFAULT_INVPRECISION, true);
        }
        //eppp_p("sign:".$sign);
        //dieFL();

        while ($diff != 0) {
            foreach( $amounts as $key => $amount) {
                // penny at a time
                if($amounts[$key][$amtfield] == 0) {
                    continue;
                }
                //$amounts[$key][$amtfield] = ibcadd($amounts[$key][$amtfield], ibcmul($sign,0.01,DEFAULT_INVPRECISION,true),DEFAULT_INVPRECISION,true);
                $amounts[$key][$amtfield] = ibcadd($amounts[$key][$amtfield], ibcmul($sign, '0.01', DEFAULT_INVPRECISION, true), DEFAULT_INVPRECISION, true);
                $diff = ibcsub($diff, ibcmul($sign, '0.01', DEFAULT_INVPRECISION, true), DEFAULT_INVPRECISION, true);
                if ((($sign > 0) && ($diff <= 0)) || (($sign < 0) && $diff >= 0)) {
                    break;
                }
            }
        }
    }


    /**
     * @param DocumentManager   $docMgr
     * @param array             $nvalues
     * @param array             $prglLineFromTD
     * @param array             $revenueAccts
     * @param string            $accountsType
     *
     * @return bool
     */
    function CreatePRInvBatch(DocumentManager $docMgr, &$nvalues, &$prglLineFromTD, &$revenueAccts, $accountsType = 'PR')
    {
        global $gErr;
        $mod = $nvalues['_mod'];
        $ok = true;

        $subTotalsObj = $this->GetSubTotalsHelper($mod);

        $ok = $ok && $this->validateOnHold($nvalues);

        if(!$ok) {
            return false;
        }
        
        $glentries = [];
        // Get an array of accounts and amounts
        $ok = $ok && $this->FindEntries($nvalues, $nvalues['ENTGLGROUP'], $nvalues['_DOCPAR']['RECORDNO'], $accountsType, $glentries, $prglLineFromTD, $revenueAccts);
        if(!$ok) {
            return false;
        }

        //posting variance of ppv-ipv
        if ($ok && $mod == 'po') {
            $values = GetAllPreferenceForProperty('9.PO', 'AUTO_PPV_POSTING');
            $autoppvpref = ($values['']['AUTO_PPV_POSTING'] == 'true' || $values['']['AUTO_PPV_POSTING'] == 'T') ? true : false;
            if ($autoppvpref) {
                $ok = $ok && $this->calcPriceVariance($nvalues, $glentries);
            }
        }

        // Add subtotal entries to $glentries
        // in case of additional GL posting in OE skip subtotals glentries
        if ($accountsType != 'ADD') {
            if (!$subTotalsObj->ProcessAPARSubtotals($nvalues, $glentries, $this->_offsetaccts)) {
                return false;
            }
        }

        $errcnt = 0;
        foreach( $glentries as $ivalitem) {
            if(!$this->ValidateGLEntries($ivalitem)) {
                $errcnt++;
            }
        }

        if($errcnt > 0 ) {
            return false ;
        }

        // Bases class can provide additional processing
        $ok = $ok && $docMgr->PreprocessDirectGLPosting($glentries, $nvalues);

        $glentries = $this->SummarizeEntries($glentries, $mod);

        $directGLPosting = ($nvalues['_DOCPAR']['UPDATES_GL'] == 'G'
            || ($nvalues['_DOCPAR']['UPDATES_GL'] != 'G' && $nvalues['_DOCPAR']['POSTTOGL'] == 'true'))
            ? true : false ;

        if ($ok && isset($glentries) && count($glentries) > 0) {
            global $gManagerFactory;
            $this->ProcessMCPGLEntries($nvalues, $glentries);

            // get the inv batch to post glentries
            $invbatch = array();

            $invBatchMgr = $gManagerFactory->getManager('invbatch');

            // default the GL batch date to transaction date
            $batchDate = $nvalues['WHENCREATED'];

            // in case of Additional GL posting in OE
            // pick the GL posting date if provided else transaction date
            if ($accountsType == 'ADD') {
                $batchDate = $nvalues['WHENPOSTED'] ?: $nvalues['WHENCREATED'];
            }

            $ok = $ok && $invBatchMgr->GetBatch($batchDate,
                    $nvalues['_DOCPAR']['DOCID'],
                    $invbatch,
                    $directGLPosting
                );

            if (!$ok || count($invbatch) == 0 ) {
                // ******* ADD ERROR
                $msg = 'Unable to get Inventory Batch';
                $gErr->addIAError('INV-0840', __FILE__ . ':' . __LINE__, $msg,[]);
                return false;
            }
            else {
                switch ($accountsType) {
                    // Direct GL Posting
                    case 'PR' :
                        $nvalues['PRINVBATCHKEY'] = $invbatch['RECORDNO'];
                        break;

                    // Additional GL posting
                    case 'ADD' :
                        $nvalues['ADDGLBATCHKEY'] = $invbatch['RECORDNO'];
                        break;
                }
            }

            $ok = $ok && $invBatchMgr->AddGLEntries($glentries, $invbatch, $directGLPosting);

            $ok = $ok && $this->CreateGLResolveMAP($glentries);

            switch ($accountsType) {
                //	Direct L posting
                case 'PR' :
                    $ok = $ok && $this->UpdateDoc_PRINVBatchReference($nvalues);
                    break;

                // Additional L posting
                case 'ADD' :
                    $ok = $ok && $this->UpdateDoc_AdditionalGLBatchReference($nvalues);
                    break;
            }
        }
        // write the tax lines to tax ledger if VAT/GST is enabled for direct GL posting only and 'Disable tax capture' is false
        if($ok && $this->addTaxEntriesCheck($docMgr, $nvalues)) {
            $taxrecordManager = Globals::$g->gManagerFactory->getManager("documenttaxrecord");
            // update deletes old taxentries in DeletePRInvBatch so we can just re-add the tax entries,
            $ok = $taxrecordManager->addTaxEntries($nvalues, $glentries);
        }

        return $ok;
    }

    /**
     * @param DocumentManager   $docMgr
     * @param array $values
     *
     * @return bool
     */
    function addTaxEntriesCheck($docMgr, $values)
    {
        // write the tax lines to tax ledger if VAT/GST is enabled for direct GL posting only and 'Disable tax capture' is false
       if( $docMgr->isVATEnabled($values) && $values['_DOCPAR']['UPDATES_GL'] == 'G' && $values['_DOCPAR']['DISABLEVAT'] == 'false' ){
           return true;
       }
       return false;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function validateOnHold($values)
    {
        $ok = true;
        $mod = $values['_mod'];

        //  Validate the onhold preference.
        if( $mod == 'po') {
            $entity = 'apbill';
            $custvendentity = 'vendor';
            $filterField = 'VENDORID';
            $errorId = 'INV-0841';
        }else{
            $entity = 'arinvoice';
            $custvendentity = 'customer';
            $filterField = 'CUSTOMERID';
            $errorId = 'INV-1441';
        }

        /** @var SubLedgerTxnManager $trxManager */
        $trxManager = Globals::$g->gManagerFactory->getManager($entity);
        $trxManager->setWarningValidation();

        $customerMgr = Globals::$g->gManagerFactory->getManager($custvendentity);
        $filter = array(
            'selects' => array(
                'RECORDNO', 'ONHOLD',
            ),
            'filters' => array(
                array(
                    array($filterField, '=', $values['CUSTVENDID'])
                )
            )
        );
        $custvendObj = $customerMgr->GetList($filter);
        $custvendObj = $custvendObj[0];

        // $ok = $trxManager->validateOnHold($custvendObj['ONHOLD'], $custvendtext, $values['CUSTVENDID']);

        $gErr = Globals::$g->gErr;

        if ( $custvendObj['ONHOLD'] == 'true') {
            $onHoldPref = GetPreferenceForProperty($trxManager->getModuleKey(), 'ONHOLDCHECK');

            if ( $onHoldPref == 'DISALLOW' || ( $trxManager->getValidateWarnings() && $onHoldPref == 'WARN' ) ) {
                $ok = false;
                $gErr->addIAError($errorId, __FILE__ . ':' . __LINE__, null, [ 'CUSTVENDID' => $values['CUSTVENDID'] ]);
            }
        }

        return $ok;
    }

    /**
     * @param array $glentries
     * @param array $docvalues
     * @param string $mod
     *
     * @return mixed
     */
    function PreprocessDirectGLPosting(&$glentries, &$docvalues, $mod)
    {
        global $gManagerFactory;
        /** @var DocumentManager $docMgr */
        $docMgr = $gManagerFactory->getManager($mod . "document");
        return $docMgr->PreprocessDirectGLPosting($glentries, $docvalues);
    }

    /**
     * @param array $nvalues
     *
     * @return bool
     */
    function DeletePRInvBatch(&$nvalues)
    {
        //eppp_p('DocumentManager::DeletePRInvBatch');
        global $gManagerFactory;
        $invBatchMgr = $gManagerFactory->getManager('invbatch');
        $ok     =   true;
        $directGLPosting = true;

        $glentries = array($nvalues['GLENTRIES']);

        $mod = $nvalues['_mod'];
        $glentries = $this->SummarizeEntries($glentries, $mod, true);

        if (isset($glentries) && count($glentries) > 0) {
            $ok = $ok && $invBatchMgr->RemoveGLEntries($nvalues, $glentries, $directGLPosting);
        }

        // delete the tax records for these document if VAT/GST is enabled for direct GL posting only
        if($ok && TaxSetupManager::isVATEnabled() && $nvalues['PRINVBATCHKEY']) {
            $taxrecordManager = Globals::$g->gManagerFactory->getManager("documenttaxrecord");
            // this delete may not be required since cascade delete probably cleaned it up already
            $ok = $taxrecordManager->deleteTaxEntries($nvalues['RECORDNO']);
        }

        return $ok;
    }

    /**
     * @param array $docObj
     *
     * @return bool
     */
    function ProcessDeleteOrSet(&$docObj)
    {
        global $gManagerFactory;

        $ok = true;

        $directGLPosting = false;

        if ($docObj['_DOCPAR']['SALE_PUR_TRANS'] == 'Sale'
            && $docObj['_DOCPAR']['UPDATES_GL'] != 'G'
            && $docObj['_DOCPAR']['POSTTOGL'] == 'true') {
            $directGLPosting = true;
        } else if ($docObj['_DOCPAR']['UPDATES_GL'] == 'G') {
            $directGLPosting = true;
        }

        //
        //
        if ($directGLPosting && ($docObj['PRINVBATCHKEY'] != '' || $docObj['ADDGLBATCHKEY'] != '')) {
            //
            // Get the Glentries for this document
            // -- gets the glentries through resolve maps of documententries & dochdrsubtotals
            // -- the resolve entries of this document will get deleted when the document is deleted before the handling subledger posting
            // -- this is because of the FK constraint on docentrykey & subtotkey in resolve tables.
            //
            $docentryGLResolveMgr = $gManagerFactory->getManager('documententryglresolve');
            /** @var SubtotalGLResolveManager $subtotalResolveMgr */
            $subtotalResolveMgr = $gManagerFactory->getManager('subtotalglresolve');

            $dochdrkey = $docObj['RECORDNO'];
            $de_glentries = $docentryGLResolveMgr->GetGLEntries($dochdrkey, false);
            /** @var SubtotalGLResolveManager $subtotalResolveMgr */
            $subtot_glentries = $subtotalResolveMgr->Get($dochdrkey);

            $glentries = INTACCTarray_merge($de_glentries, $subtot_glentries);

            $docObj['GLENTRIES'] = $glentries;

        }

        return $ok;
    }

    /**
     * Base classes can provide addition processing before GL Batch is affected
     * @param array $nvalues
     * @param array $glentries
     * @param array $directGLPosting
     * @param string $mod
     *
     * @return array
     */
    // TODO: RIP
    // function PreprocessDeletePRInvGLEntries(&$nvalues, &$glentries, $directGLPosting, $mod)
    // {
    //     global $gManagerFactory;
    //     $docMgr = $gManagerFactory->GetManager($mod."document");
    //     return $docMgr->PreprocessDeletePRInvGLEntries($nvalues, $glentries, $directGLPosting);
    // }

    /**
     * @param array  $glentries
     * @param int    $translate
     * @param string $recordtype
     * @param bool   $checkForCash
     *
     * @return bool
     */
    function ValidateGLEntries($glentries, $translate=1, /** @noinspection PhpUnusedParameterInspection */ $recordtype = '', $checkForCash = false)
    {
        global $gErr, $qbupload;

        // global maps
        global $acctmaprec, $acctmapno;
        global $deptmapno;
        global $allocMap;
        global $kARid;

        // We need this here because its moved out from DocumentManager.cls
        BuildPRMaps();

        $useTaxSchedules = GetPreferenceForProperty($kARid, 'USETAXSCHEDULES');

        $errcnt = 0;

        $isME            = IsMultiEntityCompany();
        $ctxLocation    = GetContextLocation();

        if ($isME) {
            $locMgr = Globals::$g->gManagerFactory->getManager('locationentity');
            $maprec = $locMgr->GetEntityLocationMap();
            $mapno = $locMgr->GetEntityLocationMapbyID();
        } else {
            global $locmapno, $locmaprec;
            $maprec = $locmaprec;
            $mapno = $locmapno;
        }

        $dict = Dictionary::getInstance();

        if ($translate) {
            foreach( $glentries as $item) {

                // Make sure the account key is valid
                if($item['GLACCOUNTKEY'] != '') {
                    if (!isset($acctmapno[$item['GLACCOUNTKEY']])) {
                        $gErr->addIAError(
                            'INV-0842', __FILE__.__LINE__, "Account no. " .
                            $item['GLACCOUNTKEY'] . " is invalid.",
                            ['GLACCOUNTNO' => $item['GLACCOUNTKEY']]
                        );
                        $errcnt++;
                    }
                }

                //Make sure whether the account requires dept & loc
                // validate a/c's require loc setting with respect to MEGL Context location since there will be defaulting at BL level
                $reqLocation = ( $acctmapno[$item['GLACCOUNTKEY']]['REQUIRELOC'] == 'T' );
                $reqLocation = $reqLocation && ( $isME && $ctxLocation != '' ? false : true );

                if((!isset($item['LOCATION#']) || $item['LOCATION#'] == '') && $reqLocation ) {
                    if(($isME && isset($item['SUBTOTAL'])) || ($item['SUBTOTAL'] == 'T' && $useTaxSchedules =='true')) {
                        if (isset($labmap[$item['ACCOUNTLABELKEY']])) {
                            $errorCode = 'INV-0858';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY'], 'ACCOUNTLABELKEY' => $labmap[$item['ACCOUNTLABELKEY']]];
                        } else {
                            $errorCode = 'INV-0859';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY']];
                        }
                    } else {
                        if (isset($labmap[$item['ACCOUNTLABELKEY']])) {
                            $errorCode = 'INV-0860';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY'], 'ACCOUNTLABELKEY' => $labmap[$item['ACCOUNTLABELKEY']]];
                        } else {
                            $errorCode = 'INV-0861';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY']];
                        }
                    }
                    $gErr->addIAError($errorCode, __FILE__ . '.' . __LINE__, null, $msgPlaceholder);
                    $errcnt++;
                }

                if((!isset($item['DEPT#']) || $item['DEPT#'] == '') && $acctmapno[$item['GLACCOUNTKEY']]['REQUIREDEPT'] == 'T') {
                    // User is not allowed to provide loc/dept from advance taxes.
                    // They take these values from line on which they apply

                    if(($isME && isset($item['SUBTOTAL'])) || ($item['SUBTOTAL'] == 'T' && $useTaxSchedules == 'true')) {
                        if (isset($labmap[$item['ACCOUNTLABELKEY']])) {
                            $errorCode = 'INV-0862';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY'], 'ACCOUNTLABELKEY' => $labmap[$item['ACCOUNTLABELKEY']]];
                        } else {
                            $errorCode = 'INV-0863';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY']];
                        }
                    } else {
                        if (isset($labmap[$item['ACCOUNTLABELKEY']])) {
                            $errorCode = 'INV-0864';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY'], 'ACCOUNTLABELKEY' => $labmap[$item['ACCOUNTLABELKEY']]];
                        } else {
                            $errorCode = 'INV-0865';
                            $msgPlaceholder = ['GLACCOUNTKEY' => $item['GLACCOUNTKEY']];
                        }
                    }
                    $gErr->addIAError($errorCode, __FILE__ . '.' . __LINE__, null, $msgPlaceholder);
                    $errcnt++;
                }

                //checking for required dimensions
                $mod = Request::$r->_mod;
                list($modnumber, $modid) = explode('.', $mod);
                $module = !isset($modid) ? $modnumber : isl_strtolower($modid);

                if(isset($module) && $module != '') {

                    $dimInfo = IADimensions::getDimensionObjectsInfo($module);

                    foreach($dimInfo as $key => $val) {
                        $dimFieldText = $dict->GetRenamedText($val['label']);
                        if(!$item[$val['dimdbkey']] && ($acctmapno[$item['GLACCOUNTKEY']]['REQUIRE'.isl_strtoupper($key)]) == 'T') {
                            $gErr->addIAError(
                                'INV-0843', __FILE__.'.'.__LINE__,
                                'Required information missing. ', [],
                                "The GL Account " . $item['GLACCOUNTKEY'] . " is set as Require ".$dimFieldText, ['GLACCOUNTKEY' => $item['GLACCOUNTKEY'], 'DIM_FIELD_TEXT' => $dimFieldText],
                                'Please enter a valid '.$dimFieldText.' for this line item.', ['DIM_FIELD_TEXT' => $dimFieldText]
                            );
                            $errcnt++;
                        }
                    }
                }


                // If location is provided, is it valid?
                if (isset($item['LOCATION#']) && $item['LOCATION#'] != '') {
                    if (!isset($mapno[$item['LOCATION#']])) {
                        $gErr->addIAError('INV-0844', __FILE__ . '.' . __LINE__, null,
                                          [ 'ITEM_LOCATION' => $item['LOCATION#'] ]);
                        $errcnt++;
                    }
                }

                // If department is provided, is it valid?
                if (isset($item['DEPT#']) && $item['DEPT#'] != '') {
                    if(!isset($deptmapno[$item['DEPT#']])) {
                        $gErr->addIAError('INV-0845', __FILE__ . '.' . __LINE__, null,
                                          [ 'ITEM_DEPT' => $item['DEPT#'] ]);
                        $errcnt++;
                    }
                }

                // If allocation is provided, is it valid?
                if ((isset($item['ALLOCATION']) && $item['ALLOCATION'] != '') && !($item['ALLOCATION'] == 'Custom')) {
                    if (!isset($allocMap[$item['ALLOCATION']])) {
                        $gErr->addIAError(
                            'INV-0846', __FILE__ . '.' . __LINE__, "Allocation ID " .
                            $item['ALLOCATION'] . " is invalid.",
                            ['ITEM_ALLOCATION' => $item['ALLOCATION']]
                        );
                        $errcnt++;
                    }
                }

                // Check only if Not Null
                // Issue: Oracle insert might due to NULL field for AMOUNT in glentry
                if(isset($item['AMOUNT']) && !is_numeric($item['AMOUNT']) ) {
                    $gErr->addIAError(
                        'INV-0847', __FILE__.'.'.__LINE__,
                        "The amount " . $item['AMOUNT'] . " is in an invalid amount format",
                        ['ITEM_AMOUNT' => $item['AMOUNT']]
                    );
                    $errcnt++;
                }
            }
        } else {
            /** @noinspection PhpUndefinedVariableInspection */
            if( $item['GLACCOUNTKEY'] != '') {
                if ($checkForCash && !$qbupload && $acctmapno[$acctmaprec[$item['GLACCOUNTKEY']]]['ISCASHACCT'] == 'T') {
                    $gErr->addIAError(
                        'INV-0848', __FILE__.':'.__LINE__,
                        "GL Account no. '".$acctmaprec[$item['GLACCOUNTKEY']]."' is associated to a Bank Account '". $acctmapno[$item['ACCOUNTKEY']]['CASHACCTID']. "' and cannot be used in the line items.",
                        ['ACCTMAPREC_ITEM_GLACCOUNTKEY' => $acctmaprec[$item['GLACCOUNTKEY']], 'ACCTMAPNO_ITEM_ACCOUNTKEY_CASHACCTID' => $acctmapno[$item['ACCOUNTKEY']]['CASHACCTID']],
                        "Please select another GL account.",
                        []
                    );
                    $errcnt++;
                }
            }
        }
        // To create IET, valid location specification is mandatory for MEGA
        // in case, we're not in location context and
        // we're not in working root entity context
        if( $isME && !$ctxLocation && !GetRootContextLocation() ) {
            import('IETManager');
            $ietMgr = new IETManager();
            /** @noinspection PhpUndefinedVariableInspection */
            $location = ( $translate == 1 ? $mapno[$item['LOCATION#']]['LOCATION#'] : $item['LOCATION#']);
            $locName = ($translate == 1 ? $item['LOCATION#'] : $maprec[$item['LOCATION#']]['LOCATION_NO']);

            if($ietMgr->GetEntityLocationRelationInfo($location) == null) {
                if (!isset($location) || $location == '') {
                    $errorCode = 'INV-0875';
                } else {
                    $errorCode = 'INV-0849';
                }
                $gErr->addIAError($errorCode, __FILE__ . '.' . __LINE__, null, [ 'LOC_NAME' => $locName ]);
                $errcnt++;
            }
        }

        return (!$errcnt);
    }

    /**
     * @param DocumentManager $docMgr
     * @param array     $nvalues
     * @param array     $customFields
     * @param array     $prglLineFromTD
     * @param array     $revenueAccts
     * @param array     $taxLines
     * @param array     $getSubTotalsResult
     * @param string    $contactTaxGrpKey
     * @param array     $simpletaxLines
     *
     * @return bool
     */
    function ProcessAPARDocument(DocumentManager $docMgr, &$nvalues, &$customFields, &$prglLineFromTD, &$revenueAccts, &$taxLines, &$getSubTotalsResult, &$contactTaxGrpKey, &$simpletaxLines)
    {

        $benchmark = Globals::$g->gIABenchmark;
        $mod = $nvalues['_mod'];

        $subTotalsObj = $this->GetSubTotalsHelper($mod, $nvalues);

        $ok = true;
        $follow = GetPreferenceForProperty(GetModuleID($mod), 'FOLLOWFPRESTRICTIONS');
        if ($follow == 'T') {
            $moduleToCheck = $mod == 'so' ? 'ar' : 'ap';
            $ok = ValidateGLPostingDate($nvalues['WHENPOSTED'], $moduleToCheck, true);
        }

        // Get an array of accounts and amounts
        //  FindEntries:-

        //  This function generated Dr/CR to be posted entries to GL for LINE ITEMS into $glentries
        $ok = $ok && $this->FindEntries($nvalues, $nvalues['ENTGLGROUP'], $nvalues['_DOCPAR']['RECORDNO'], 'PR', $glentries, $prglLineFromTD, $revenueAccts);

        //posting variance of ppv-ipv
        $mod = $nvalues['_mod'];
        if ($ok && $mod == 'po') {
            $values = GetAllPreferenceForProperty('9.PO', 'AUTO_PPV_POSTING');
            $autoppvpref = ($values['']['AUTO_PPV_POSTING'] == 'true' || $values['']['AUTO_PPV_POSTING'] == 'T') ? true : false;
            if ($autoppvpref) {
                $benchmark->startTimer('calcPriceVariance', $this, $this);
                $ok = $this->calcPriceVariance($nvalues, $glentries);
                $benchmark->stopTimer();
            }
        }

        //posting variance of Match Tolerances (Formerly known as Three way match)
        if ($ok && $mod == 'po') {
            $threeWayMatchEnabled = ThreeWayMatchHandler::checkIfThreeWayMatchEnabled($nvalues['DOCPARID'],
                                                                                      $threeWayMatchGridPref, $threeWayMatchGLAccount);
                if ($threeWayMatchEnabled && !empty($threeWayMatchGLAccount)) {
                 ThreeWayMatchHandler::calcThreewayVariance($nvalues, $glentries, $threeWayMatchGLAccount);
            }
        }

        //  This function generated Dr/CR to be posted entries to GL for SUBTOTAL LINES into $glentries
        $benchmark->startTimer('ProcessAPARSubtotals', $this, $subTotalsObj);
        $processSubtotalsOk = $subTotalsObj->ProcessAPARSubtotals($nvalues, $glentries, $this->_offsetaccts);
        $benchmark->stopTimer();
        if ( !$processSubtotalsOk) {
            return false;
        }

        if ($customFields) {
            $this->customFields = $customFields;
        }
        if (isset($glentries) && count($glentries) > 0) {
            $this->_getAccountingRules($nvalues, $accounting_rules, $recordtype);

            // Stick those entries in a transaction
            $benchmark->startTimer('CreateAPARDocumentValues', $this, $this);
            $ok = $ok && $this->CreateAPARDocumentValues($nvalues, $glentries, $matureValues, $accounting_rules, $recordtype);
            $benchmark->stopTimer();
            //  Create PRTAXENTRIES
            $subTotalsObj->GeneratePRTaxEntries(
                $this->_itemLines,
                $taxLines,
                $this->_prtaxEntries,
                $taxableitems,
                $simpletaxLines,
                $contactTaxGrpKey,
                $getSubTotalsResult
            );

            $subTotalsObj->ApplyAcountingRuleToPRTaxEntries($this->_prtaxEntries, $accounting_rules, $recordtype);

            $subTotalsObj->MarkTaxableLines($matureValues, $taxableitems);

            $ok = $ok && $docMgr->PreprocessInvoice($matureValues, $nvalues);

            // stuff metadata to taxlines for later storing into the taxrecords
            if($docMgr->isVATEnabled($nvalues)) {
                $subTotalsObj->processTaxlinesforVAT($matureValues);
            }

            $entity = ( $mod == 'po' ) ? 'apbill' : 'arinvoice';
            /** @var SubLedgerTxnManager|ARInvoiceManager $trxManager */
            $trxManager = Globals::$g->gManagerFactory->getManager($entity);
            if($docMgr->fromGateway){
                $trxManager->disableWarningValidation();
                $trxManager->setValidateWarnings(false);
            }
            else{
                $trxManager->setWarningValidation();
                $trxManager->setValidateWarnings(true);
            }
            $trxManager->setShowWarningsAsWarnings(true); // Show the warnings as warnings
            $trxManager->setHasAcctLabel(false); // No account label
            $trxManager->setHasUserSpecifiedBatch(false); // Batch come from OE/PO txn
            $trxManager->setHasSequenceNumbering(false); // Trx Number will be the same as OE
            $trxManager->setHasOverrideOffsetPermission(false, false); // should not override the offset account
            if ( $entity == 'arinvoice' ) {
                $trxManager->setTaxEngineForCalc(GetTaxEngine($mod,$nvalues['TAXSOLUTIONID'])); //We use the tax engine of this OE to calculate tax for AR invoice
                // Set the rev rec info but do not create the schedules
                $trxManager->setHasRevRec(true);
                $trxManager->setCreateRevRecSchedule(false);
            } else {
                // 2.1 request will have FROMAPI_2.1 and 3.0 request will have _fromAPI set
                if ($nvalues['FROMAPI_2.1'] || $docMgr->_fromAPI) {
                    $trxManager->fromGateway = true;
                }
            }

            $trxManager->prepTaxSolutionFieldsForSCMPosting($nvalues, $matureValues);

            $ok = $ok && $this->addOrUpsertApAr($trxManager, $nvalues, $matureValues);
            
            $ok = $ok && $this->createComplianceRecordsAtSave($nvalues, $matureValues);

            $ok = $ok && $subTotalsObj->CollectPREntrykeys(
                    $matureValues,
                    $this->_itemPREntrykeys,
                    $this->_simpletaxPREntrykeys,
                    $this->_taxPREntrykeys,
                    $this->_discountPREntrykeys,
                    $this->_chargePREntrykeys
                );
            $ok = $ok && $subTotalsObj->CreatePRTaxEntries(
                    $matureValues,
                    $this->_prtaxEntries,
                    $this->_itemPREntrykeys,
                    $this->_simpletaxPREntrykeys,
                    $this->_taxPREntrykeys
                );
            $nvalues['PRRECORDKEY'] = $matureValues['RECORDNO'];

            $subTotalsObj->AssignPREntryKeyBackToItems(
                $this->_itemPREntrykeys,
                $nvalues,
                $this->_taxPREntrykeys,
                $this->_simpletaxPREntrykeys,
                $this->_discountPREntrykeys,
                $this->_chargePREntrykeys
            );

            $ok = $ok && $this->SetDocAPARReference($nvalues);

            $ok = $ok && $this->SetSubtotalsAPARReference($nvalues);

            $ok = $ok && $this->setAssetDimKeys($matureValues);
        }

        return $ok;
    }


    /**
     * This function posts the variance (for standard cost method line items) of Standard cost vs purchase Order and Receiver price vs Vendor Invoice
     *
     * @param array $nvalues
     * @param array $glentries
     *
     * @return bool
     */
    function calcPriceVariance(&$nvalues, &$glentries)
    {
        $ok = true;

        $gManagerFactory = Globals::$g->gManagerFactory;
        /** @var PODocumentManager $poDocMgr */
        $poDocMgr = $gManagerFactory->getManager('podocument');
        $ParentRec = $poDocMgr->Get($nvalues['CREATEDFROM']);

        $thisTxnClass= self::classifyPurchaseTxn($nvalues['_DOCPAR']);
        $parentTxnClass= self::classifyPurchaseTxn($ParentRec['_DOCPAR']);

        $priceVarianceType = $this->getPriceVarianceType($thisTxnClass, $parentTxnClass);

        switch ($priceVarianceType) {
            case IPV :
                $this->calcInvoicePriceVariance($nvalues, $ParentRec, $parentTxnClass, $glentries);
                break;

            case PPV :
                $this->calcPurchasePriceVariance($nvalues, $thisTxnClass, $parentTxnClass, $glentries);
                break;
        }

        return $ok;
    }

    /**
     * @param string $thisTxnClass
     * @param string $parentTxnClass
     *
     * @return string
     */
    private function getPriceVarianceType($thisTxnClass, $parentTxnClass)
    {
        if (($thisTxnClass == VendorInvoice && ($parentTxnClass == POReceiver || $parentTxnClass == null))
            || ($thisTxnClass == VendorReturn && $parentTxnClass == POReturn)
        ) {
            return IPV;
        } else if ($thisTxnClass == POReceiver
            || ($thisTxnClass == POReturn && $parentTxnClass == VendorInvoice)
        ) {
            return PPV;
        }

        return 'NA';
    }

    /**
     * @param array  $nvalues
     * @param array  $parentRec
     * @param string $parentTxnClass
     * @param array  $glentries
     */
    private function calcInvoicePriceVariance($nvalues, $parentRec, $parentTxnClass, &$glentries)
    {
        //Fetch the gl account from po subscription for posting variance amount
        $MatIVglacct = GetAllPreferenceForProperty('9.PO', 'MAT_IV_GLACCT');
        list($IVGLAccount) = explode("--", $MatIVglacct['']['MAT_IV_GLACCT']);

        $parentRec['ENTRIES'] = $parentRec['ENTRIES'] ?? [];
        $newglentries = array();
        $nonInventoryType = array('NI', 'NP', 'NS');
        $isMCPEnabled = IsMCPEnabled($nvalues['_mod']);

        //creating a sturcture so that line entry can be mapped to sourcelinekey, required in case of parial conversion.
        $parent_arr = array();
        foreach ((($parentRec['ENTRIES']) ?? []) as $pval) {
            $parent_arr[$pval['RECORDNO']] = $pval;
        }

        //When receiver and vendor invoive both posts to gl/ap, we have to compare diff between receiver and invoice price and post as variance
        //In case where we dont have a parent document, we have to IPV = pur price - std cost
        foreach ((($nvalues['ENTRIES']) ?? []) as $entry) {
            $detailEntry = $entry['ITEMDETAILS'][0];
            //if the Item cost method is standard
            if ($detailEntry['COST_METHOD'] == 'S' && !in_array($detailEntry['ITEMTYPE'], $nonInventoryType)) {
                // Qty included in current doc uivalue (converted qty) can be < Qty for parent doc uivalue
                // Get po rcvr price for qty converted and use that to calculate variance for converted qty
                if ($parentTxnClass == null) {
                    $convQtyToOrigQtyRatio = $entry['QUANTITY'];
                } else {
                    $parentQty = $parent_arr[$entry['SOURCE_DOCLINEKEY']]['UIQTY'];
                    $convQtyToOrigQtyRatio = ibcdiv($entry['UIQTY'], $parentQty, 10);
                }

                if ($parentTxnClass == null) {
                    $parentValForConvQty = ibcmul(
                        $detailEntry['COSTDETAILS'][0]['WHSE_STANDARD_COST'], $convQtyToOrigQtyRatio, 10
                    );
                } else {
                    $parentValForConvQty = ibcmul(
                        $parent_arr[$detailEntry['SOURCE_DOCLINEKEY']]['UIVALUE'], $convQtyToOrigQtyRatio, 10
                    );
                }

                $diffamt = ibcsub($entry['UIVALUE'], $parentValForConvQty, 2);

                if ($isMCPEnabled) {
                    if ($parentTxnClass == null) {
                        $parentTrxValForConvQty = ibcmul(
                            $detailEntry['COSTDETAILS'][0]['WHSE_STANDARD_COST'], $convQtyToOrigQtyRatio, 10
                        );
                    } else {
                        $parentTrxValForConvQty = ibcmul(
                            $parent_arr[$detailEntry['SOURCE_DOCLINEKEY']]['TRX_VALUE'], $convQtyToOrigQtyRatio, 10
                        );
                    }
                    $difftrxamt = ibcsub($entry['TRX_VALUE'], $parentTrxValForConvQty, 2);
                } else {
                    $difftrxamt = $diffamt;
                }

                if ($diffamt != 0) {
                    foreach ($glentries as $glkey => $glEntry) {
                        if ($glEntry[0]['DOC_LINENO'] == $entry['LINEKEY']) {
                            //hardcoded need to change
                            if ($glEntry[0]['DR_CR'] == '1') {
                                $line1 = 0;
                                $line2 = 1;
                            } else {
                                $line1 = 1;
                                $line2 = 0;
                            }
                            $glEntry[$line1]['GLACCOUNTKEY'] = $IVGLAccount;
                            $glentries[$glkey][$line1]['AMOUNT'] = ibcsub(
                                $glentries[$glkey][$line1]['AMOUNT'], $diffamt, 2
                            );
                            $glentries[$glkey][$line2]['AMOUNT'] = ibcsub(
                                $glentries[$glkey][$line2]['AMOUNT'], $diffamt, 2
                            );
                            $glEntry[$line1]['AMOUNT'] = ibcabs($diffamt);
                            $glEntry[$line2]['AMOUNT'] = ibcabs($diffamt);

                            if ($isMCPEnabled) {
                                $glentries[$glkey][$line1]['TRX_AMOUNT'] = ibcsub(
                                    $glentries[$glkey][$line1]['TRX_AMOUNT'], $difftrxamt, 2
                                );
                                $glentries[$glkey][$line2]['TRX_AMOUNT'] = ibcsub(
                                    $glentries[$glkey][$line2]['TRX_AMOUNT'], $difftrxamt, 2
                                );
                                $glEntry[$line1]['TRX_AMOUNT'] = ibcabs($difftrxamt);
                                $glEntry[$line2]['TRX_AMOUNT'] = ibcabs($difftrxamt);
                            }
                            if ($diffamt < 0) {
                                //Since negative amounts, reverse the DR_CR indicator
                                $glEntry[$line1]['DR_CR'] = -1 * $glEntry[$line1]['DR_CR'];
                                $glEntry[$line2]['DR_CR'] = -1 * $glEntry[$line2]['DR_CR'];
                            }
                            unset($glEntry[$line1]['LINE_NO']);
                            unset($glEntry[$line2]['LINE_NO']);
                            $newglentries[] = $glEntry;
                        }
                    } // $glentries loop
                } // $diffamt condition
            } // ['COST_METHOD'] condition
        } // ['ENTRIES'] loop

        if (count($newglentries) > 0) {
            $glentries = array_merge($glentries, $newglentries);
        }
    }

    /**
     * @param array  $nvalues
     * @param string $thisTxnClass
     * @param string $parentTxnClass
     * @param array  $glentries
     */
    private function calcPurchasePriceVariance($nvalues, $thisTxnClass, $parentTxnClass, &$glentries)
    {
        //Fetch the gl account from po subscription for posting variance amount
        $MatPVglacct = GetAllPreferenceForProperty('9.PO', 'MAT_PV_GLACCT');
        list($PVGLAccount) = explode("--", $MatPVglacct['']['MAT_PV_GLACCT']);

        $newglentries = array();
        $nonInventoryType = array('NI', 'NP', 'NS');
        $isMCPEnabled = IsMCPEnabled($nvalues['_mod']);

        foreach ((($nvalues['ENTRIES']) ?? []) as $entry) {
            foreach ((($entry['ITEMDETAILS']) ?? []) as $detailEntry) {

                //if the Item cost method is standard
                if ($detailEntry['COST_METHOD'] == 'S'
                    && !in_array($detailEntry['ITEMTYPE'], $nonInventoryType)) {

                    foreach ((($detailEntry['COSTDETAILS']) ?? []) as $costEntry) {
                        if (!isset($costEntry['QTY'])) {
                            $costEntry['QTY'] = $costEntry['QUANTITY'];
                        }

                        //normal case
                        if ($thisTxnClass == POReturn && $parentTxnClass == VendorInvoice) {
                            $diffamt = ibcsub(ibcmul($costEntry['WHSE_STANDARD_COST'], $costEntry['QTY'], 10), $costEntry['COST'], 2);
                        } else {
                            $diffamt = ibcsub($costEntry['VALUE'], ibcmul($costEntry['WHSE_STANDARD_COST'], $costEntry['QTY'], 10), 2);
                        }

                        if ($isMCPEnabled) {
                            $difftrxamt = ibcdiv($diffamt, $entry['EXCHRATE'], DEFAULT_INVPRECISION, true);
                        } else {
                            $difftrxamt = $diffamt;
                        }

                        if ($diffamt != 0) {
                            foreach ($glentries as $glkey => $glEntry) {

                                if ($glEntry[0]['DOC_LINENO'] === $entry['LINEKEY']) {

                                    if ($thisTxnClass == POReturn && $parentTxnClass == VendorInvoice) {
                                        if ($glEntry[0]['DR_CR'] == '-1') {
                                            $line1 = 0;
                                            $line2 = 1;
                                        } else {
                                            $line1 = 1;
                                            $line2 = 0;
                                        }
                                    } else {
                                        if ($glEntry[0]['DR_CR'] == '1') {
                                            $line1 = 0;
                                            $line2 = 1;
                                        } else {
                                            $line1 = 1;
                                            $line2 = 0;
                                        }
                                    }

                                    //hardcoded need to change
                                    if ($diffamt < 0) {
                                        $diffamt = ibcmul($diffamt, -1, 2);
                                        $difftrxamt = ibcmul($difftrxamt, -1, 2);

                                        $glEntry[$line2]['GLACCOUNTKEY'] = $PVGLAccount;

                                        $glEntry[$line2]['AMOUNT'] = $diffamt;
                                        $glEntry[$line1]['AMOUNT'] = $diffamt;

                                        $glEntry[$line2]['TRX_AMOUNT'] = $difftrxamt;
                                        $glEntry[$line1]['TRX_AMOUNT'] = $difftrxamt;

                                        $glEntry[$line2]['ISOFFSET'] = 'F';
                                        $glEntry[$line1]['ISOFFSET'] = 'T';
                                    } else {
                                        $glEntry[$line1]['GLACCOUNTKEY'] = $PVGLAccount;

                                        $glentries[$glkey][$line1]['AMOUNT'] = ibcsub($glentries[$glkey][$line1]['AMOUNT'], $diffamt, 2);
                                        $glentries[$glkey][$line2]['AMOUNT'] = ibcsub($glentries[$glkey][$line2]['AMOUNT'], $diffamt, 2);
                                        $glEntry[$line1]['AMOUNT'] = $diffamt;
                                        $glEntry[$line2]['AMOUNT'] = $diffamt;

                                        $glentries[$glkey][$line1]['TRX_AMOUNT'] = ibcsub($glentries[$glkey][$line1]['TRX_AMOUNT'], $difftrxamt, 2);
                                        $glentries[$glkey][$line2]['TRX_AMOUNT'] = ibcsub($glentries[$glkey][$line2]['TRX_AMOUNT'], $difftrxamt, 2);
                                        $glEntry[$line1]['TRX_AMOUNT'] = $difftrxamt;
                                        $glEntry[$line2]['TRX_AMOUNT'] = $difftrxamt;

                                    }
                                    unset($glEntry[$line1]['LINE_NO']);
                                    unset($glEntry[$line2]['LINE_NO']);
                                    $newglentries[] = $glEntry;
                                }
                            } // $glentries loop
                        } // $diffamt condition
                    } // ['COSTDETAILS'] loop
                } // ['COST_METHOD'] condition
            } // ['ITEMDETAILS'] loop
        } // ['ENTRIES'] loop

        if (count($newglentries) > 0) {
            $glentries = array_merge($glentries, $newglentries);
        }
    }


    /**
     * @param array $docpar
     *
     * @return null|string
     */
    private static function classifyPurchaseTxn($docpar)
    {
        $txnClass = null;
        $updatesInv = $docpar['UPDATES_INV'];
        $affectsInventory = array('Value', 'Quantity and Value');
        $incDec = $docpar['IN_OUT'];
        $updatesGL = $docpar['UPDATES_GL'];
        $spi = $docpar['SALE_PUR_TRANS'];

        if ($spi != 'Purchase') {
            return null;
        }

        if ($updatesInv == 'Quantity' && $updatesGL == 'G') {
            if ($incDec == 'Increase') {
                $txnClass = POReceiver;
            } else {
                $txnClass = POReturn;
            }
        } else if (in_array($updatesInv, $affectsInventory) && $updatesGL != 'N') {
            if ($incDec == 'Increase') {
                $txnClass = VendorInvoice;
            } else {
                $txnClass = VendorReturn;
            }
        }

        return $txnClass;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function SetDocAPARReference($values)
    {
        global $gManagerFactory;
        $ok = true;
        $mod = $values['_mod'];

        $qry = 'QRY_DOCUMENT_UPDATE_PRRECORDKEY';
        $docMgr = $gManagerFactory->getManager($mod . "document");

        $args = array($values['PRRECORDKEY'], $values['PRINVBATCHKEY'], $values['DOCID'], GetMyCompany());
        //
        // not sure about ADDLBATCHKEY
        //
        $ok = $ok && $docMgr->DoQuery($qry, $args);

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function SetSubtotalsAPARReference($values)
    {
        if (!isset($values['SUBTOTALS']) || !is_array($values['SUBTOTALS'])) {
            return true;    // I guess?
        }
        global $gManagerFactory;
        $ok = true;
        $qry = 'QRY_SUBTOTOALS_UPD_PRENTRYKEY';
        $docSubtotalsMgr = $gManagerFactory->getManager('documentsubtotals');

        foreach( (($values['SUBTOTALS']) ?? []) as $subtotal) {
            if( (isset($subtotal['PRENTRYKEY']) && $subtotal['PRENTRYKEY']!='') && (isset($subtotal['RECORDNO']) && $subtotal['RECORDNO']!='')) {
                $args = array($subtotal['PRENTRYKEY'], $subtotal['RECORDNO'], GetMyCompany());
                $ok = $ok && $docSubtotalsMgr->DoQuery($qry, $args);
            }
        }

        return $ok;
    }

    /**
     * @param array $matureValues
     *
     * @return bool
     */
    function setAssetDimKeys($matureValues)
    {
        global $gManagerFactory;
        $ok = true;
        $qry = 'QRY_DOCUMENTENTRY_SET_ASSET_DIM_KEY';
        $docEntryMgr = $gManagerFactory->getManager("documententry");

        foreach ((($matureValues['ITEMS']) ?? []) as $item) {
            if (isArrayValueProvided($item, 'DOCENTRYKEY') && isArrayValueProvided($item, 'ASSETDIMKEY')) {
                $args = array($item['ASSETDIMKEY'], $item['DOCENTRYKEY'], GetMyCompany());
                $ok = $ok && $docEntryMgr->DoQuery($qry, $args);
            }
        }
        return $ok;
    }

    /**
     * @param array $docvalues
     * @param array $glentries
     * @param array $prrecord
     * @param array $accounting_rules
     * @param string $recordtype
     *
     * @return bool
     */
    function CreateAPARDocumentValues($docvalues, $glentries, &$prrecord, $accounting_rules, $recordtype)
    {
        // THIS IS THE FUNCTION TO CREATE $prrecord

        global $gManagerFactory, $acctmapno;
        $ok = true;

        if ( IsMultiEntityCompany() && GetContextLocation() ) {
            $bankaccttbl = 'bankaccount';
        } else {
            $bankaccttbl = 'bankaccountmst';
        }
        if ( empty($acctmapno) ) {
            BuildAccMap($bankaccttbl);
        }

        $mod = $docvalues['_mod'];
        $isMCPEnabled = IsMCPEnabled($mod);
        $cny = GetMyCompany();
        $isVatEnabled = $docvalues['_isVatEnabled'] ?? false;

        $docbatchMgr = $gManagerFactory->getManager('invbatch');

        // If we had an inventory transaction, use that batch title
        $batchPostdate = $docvalues['WHENPOSTED'] ?: $docvalues['WHENCREATED'];

        // In case of COGS Entries their might be IET's, In such case the GL Batch may belong to root.
        $needToSwitchToRootContext = $docbatchMgr->needToSwitchToRootContext($docvalues['INVBATCHKEY']);

        if ($docvalues['INVBATCHKEY'] && !(IsMCMESubscribed() && !GetContextLocation()) && !$needToSwitchToRootContext) {
            $qry = 'QRY_INVBATCH_SELECT_RAW_UID';
            $args = array ($docvalues['INVBATCHKEY'],$cny);
            $row = $docbatchMgr->DoQuery($qry, $args);
            $title = $row[0]['TITLE'] ?? null;
            $ok = $ok && isset($title);
        } else {
            $title = $docbatchMgr->GetBatchTitle($docvalues['DOCPARID'], $batchPostdate, false, $docvalues['BASECURR']);
        }

        // =====================================================
        // Temporary code until prbatch is fully retrofitted
        // =====================================================
        if ($ok) {
            $tmpqry = " select RECORD# from prbatch where title = :1  AND cny# = :2 and recordtype = :3 ";

            $prbatch = QueryResult(array($tmpqry, $title, $cny, $recordtype));
            $prbatch = $prbatch[0] ?? false;

            if (!$prbatch) {
                $batchdate = $docbatchMgr->GetBatchDate($docvalues['DOCPARID'], $batchPostdate);
                $prbatch = array(
                    'TITLE'       => $title,
                    'RECORDTYPE'  => $recordtype,
                    'CREATED'     => $batchdate,
                    'AUTOCREATED' => 'T',
                );

                if (!CreatePRBatch($prbatch)) {
                    epp("CreatePRBatch Failed");
                    $ok = false;
                }
            }
        }

        // figure out the entity
        $entityEntity = ($docvalues['_DOCPAR']['CUST_VEND'] == 'Vendor') ? 'vendor' : 'customer';
        $entityMgr = $gManagerFactory->getManager($entityEntity);
        $raw = $entityMgr->GetRaw($docvalues['CUSTVENDID']);
        $ok = $ok && isset($raw[0]);

        if ($ok) {
            $entityIDPAth = isl_strtoupper($entityEntity)."ID";
            $entity = $raw[0][$entityIDPAth];
        }

        $recid = ($mod == 'so') ? $docvalues['DOCNO'] : $docvalues['VENDORDOCNO'] ;

        /** @noinspection PhpUndefinedVariableInspection */
        $prrecord = array(
            'PRBATCHKEY' => $prbatch['RECORD#'],
            'RECORDID' => $recid,
            'DOCNUMBER' => $docvalues['PONUMBER'],
            'DESCRIPTION2' => $docvalues['DOCID'],
            'BILLTOPAYTOCONTACTNAME' => $docvalues['BILLTO']['CONTACTNAME'],
            'SHIPTORETURNTOCONTACTNAME' => $docvalues['SHIPTO']['CONTACTNAME'],
            'TERMNAME' => $docvalues['TERM']['NAME'],
            $entityIDPAth => $entity,
            'MODULEKEY'        =>  ModuleSymbolToId($mod),
            'WHENCREATED' => $docvalues['WHENCREATED'],
            'DESCRIPTION' => isl_substr($docvalues['MESSAGE'], 0, 1000),
            'WHENDUE' => $docvalues['WHENDUE'],
            'BASECURR' => $docvalues['BASECURR'],
            'CURRENCY' => $docvalues['CURRENCY'],
            'EXCHANGE_RATE' => $docvalues['EXCHRATE'],
            'EXCH_RATE_DATE' => $docvalues['EXCHRATEDATE'],
            'EXCH_RATE_TYPE_ID' => $docvalues['EXCHRATETYPES']['NAME'] ?? null,
            'SUPDOCID' => $docvalues['SUPDOCID'],
            'PROJECTCONTRACTID' => $docvalues['PROJECTCONTRACTID'],
            'PROJECTCONTRACTKEY' => $docvalues['PROJECTCONTRACTKEY'],
            '_isVatEnabled' => $isVatEnabled,
            'INVOICERUNKEY' => $docvalues['INVOICERUNKEY'],

        );

        if ( TaxSetupManager::isVATEnabled() ) {
            // we need to store the transaction type and transaction id in taxrecords
            // ticket 90804 docid/description2 is not parseable to figure that out bcoz '-' can in docid and docparid
            $prrecord['TXNTYPE'] = $docvalues['DOCPARID'];
            $prrecord['TXNID'] = $docvalues['DOCNO'];
        }

        $moduleKey = ( $docvalues['_mod'] === 'so' ) ? Globals::$g->kARid : Globals::$g->kAPid;
        //Set module key as module of the transaction to check copy parent child relation or not
        $docvalues['MODULEKEY'] = $docvalues['_mod'];
        $copyLineTaxRelation = TaxSolutionManager::shouldCopyParentChildRelationship($docvalues, $moduleKey);
        $docMgr = Globals::$g->gManagerFactory->getManager($docvalues['_mod'] . 'document', false,
                                                           [ 'DOCTYPE' => $docvalues['DOCPARID'] ]);
        $isPymtTaxSupported = $docMgr->isPaymentTaxCaptureSupported();
        $isPymtTaxEnabled = PaymentUtils::isOEPOPaymentTaxCaptureSupported($docvalues);

        $isRetainageEnabled = ( $mod == 'po' ? CRESetupManager::isAPRetainageEnabled() : CRESetupManager::isARRetainageEnabled() );
        if ( $isRetainageEnabled ) {
            $prrecord['RETAINAGEPERCENTAGE'] = $docvalues['RETAINAGEPERCENTAGE'];
        }

        $trx_currency = $docvalues['CURRENCY'];
        $basecurrency = GetBaseCurrency();

        $form1099flag = false;

        $mergeTaxDetailKey=[];
        $lineNo=0;

        $docEntries = $this->getMappedDocumentEntries($docvalues);

        // used for retainage only.
        $docEntryKeyValue = [];
        $docEntryKey = 0;
        $remainingRetainageForKit = [];
        $remainingPercentageOfKit = [];
        $processedDocEntryKeysForFixedAssets = [];

        foreach ( $glentries as $entry) {
            foreach ( $entry as $line) {
                if ( $isRetainageEnabled) {
                    $docEntryKey = ibcmul($line['DOCENTRYKEY'], $line['DR_CR']);

                    if (is_null($docEntryKeyValue[$docEntryKey])) {
                        $docEntryKeyValue[$docEntryKey] = $docEntries[$line['DOCENTRYKEY']]['TRX_VALUE'];
                        $remainingPercentageOfKit[$docEntryKey] = 100;
                        if (isNullOrBlank($docEntries[$line['DOCENTRYKEY']]['TRX_AMOUNTRETAINED'])) {
                            $remainingRetainageForKit[$docEntryKey] =
                                ibcmul($docEntries[$line['DOCENTRYKEY']]['RETAINAGEPERCENTAGE'], $docEntries[$line['DOCENTRYKEY']]['TRX_VALUE']);
                            $remainingRetainageForKit[$docEntryKey] = ibcdiv($remainingRetainageForKit[$docEntryKey], 100, 2, true);
                        }
                        else {
                            $remainingRetainageForKit[$docEntryKey] = $docEntries[$line['DOCENTRYKEY']]['TRX_AMOUNTRETAINED'];
                        }
                    }
                }

                $factor = $line['DR_CR'] * $accounting_rules[$recordtype];

                if ($line['ISOFFSET'] == 'T' ) {
                    continue;
                }

                $offsetAcctKey = $entry[0]['ISOFFSET'] == 'T' ? $entry[0]['GLACCOUNTKEY'] : $entry[1]['GLACCOUNTKEY'];
                if($isMCPEnabled && $trx_currency != $basecurrency) {
                    $amount = $line['TRX_AMOUNT'];
                } else {
                    $amount = $line['AMOUNT'];
                }

                $nonoffset = array (
                    'ACCOUNTNO'       =>    $line['GLACCOUNTKEY'],
                    'DESCRIPTION'    =>  $line['DESC'],
                    'TRX_AMOUNT'    =>    ibcmul($amount, $factor, 2, true),
                    'AMOUNT'        =>    ibcmul($line['AMOUNT'], $factor, 2, true),
                    'DEPARTMENTID'    =>    $line['DEPT#'],
                    'LOCATIONID'    =>    $line['LOCATION#'],
                    'ITEMID'        =>    $line['ITEMID'],
                    'TAXDETAILKEY'    =>    $line['TAXDETAILKEY'],
                    'SUBTOTAL'        =>    $line['SUBTOTAL'],
                    'TAXABLE'        =>    $line['TAXABLE'] ?? 'false',
                    'DOC_LINENO'    =>    $line['DOC_LINENO'],
                    'ITEMGLGROUP'    =>    $line['ITEMGLGROUP'],
                    'VSOEREVRECACTION' => $line['VSOEREVRECACTION'],
                    'GLOFFSETKEY' => $acctmapno[$offsetAcctKey]['RECORD#'],
                    'DOCHDRNO'      => $line['DOCHDRNO'],

                    // TODO fix this in R1 as new documents doesn't have docentrykey populated
                    //'DOCENTRYKEY'   => $line['DOCENTRYKEY'],
                    //'SUBTOTALKEY'   => $line['SUBTOTALKEY'],

                    // DOC_LINENO is used to map the following
                    // the prentries and docentries
                    // the docentry and subtotals
                    // prentry and prtaxentries
                );

                //Set claimable or non claimable flag for partial exemption cases
                if(!empty($line['ISNONCLAIMABLE']) && $line['ISNONCLAIMABLE'] === 'true'){
                    $nonoffset['ISNONCLAIMABLE'] = 'true';
                }
                if (!empty($line['PARTIALEXEMPT']) && $line['PARTIALEXEMPT'] === 'true') {
                    $nonoffset['ISRECLAIMABLE'] = 'true';
                }
                $docLine = array();
                //If vat enabled then need to copy dimensions for subtotals lines too
                if(!isset($line['SUBTOTAL']) || $isVatEnabled) {
                    $docLine = $docvalues['ENTRIES' ][$line['DOC_LINENO']];

                    if ( CRESetupManager::isPrimaryDocEnabled() && isset($docLine['PRIMARYDOCKEY'])) {
                        // Populate the downstream docs primary doc keys if the current doc has them populated
                        $nonoffset['PRIMARYDOCKEY'] = $docLine['PRIMARYDOCKEY'];
                        $nonoffset['PRIMARYDOCLINEKEY'] = $docLine['PRIMARYDOCLINEKEY'];
                    }
                }

                if (isset($docLine['ORIGDOCKEY'])) {
                    // Populate the downstream docs originating doc reference keys if the current doc has them populated
                    $nonoffset['ORIGDOCKEY'] = $docLine['ORIGDOCKEY'];
                    $nonoffset['ORIGDOCLINEKEY'] = $docLine['ORIGDOCLINEKEY'];
                }

                if(!isset($line['SUBTOTAL'])) {
                    // in AP/AR the line number is not set it starts from 1 and keep incrementing
                    // when the line is allocated (for now in PO) the line number should remain same.
                    // like [0,0,1,2] if LINE_NO is not set here it will be like [1,2,3,4] instead of [1,1,2,3] in AP/AR
                    // as line number starts from 1 in AP/AR add 1 to the line number (in SCM it starts with 0)
                    if(isset($line['LINE_NO']) && $line['LINE_NO'] !== '') {
                        $lineNo = $line['LINE_NO'];
                    }

                    if(isset($line['ALLOCATION']) && $line['ALLOCATION'] != '') {
                        $nonoffset['ALLOCATION'] = $line['ALLOCATION'];
                        $nonoffset['ALLOCATIONKEY'] = $line['ALLOCATIONKEY'];
                    }

                    $nonoffset['DOCENTRYKEY'] = $line['DOCENTRYKEY'];
                }

                // This block to add FORM1099 element to nonoffset and subtotal line item
                /**
                 * Note:
                 *
                 * 'FORM1099' should be assigned to either 'true' or 'false' of type string
                 * as even though this field appears as a check box in the UI, at the backend, this field
                 * is converted into a string and then saved in the database
                 * For ex: if the checkbox is checked, 'true' should be passed as the 'FORM1099' will be translated
                 * to the right vendor or the selected 1099 type and box values like <<type>>@<<box>> and
                 * if the checkbox is unchecked, specifically 'false' should be passed as subledger
                 * should not re-translate the FORM1099 to true as boolean false will make a condition fail in
                 * SubledgerTxnManager -> translateEntry1099 method
                 */
                if( (   isset($docLine['FORM1099']) && $docLine['FORM1099'] == 'true'
                        && !empty($docvalues['FORM1099FORMAT'])
                        && empty($line['SUBTOTAL']))
                    || ( $form1099flag && !empty($line['SUBTOTAL']) )
                ) {
                    $nonoffset['FORM1099'] = 'true';
                    $form1099flag = true;
                } else {
                    $nonoffset['FORM1099'] = 'false';
                }
                $nonoffset['FORM1099TYPE'] = $nonoffset['FORM1099'] === 'false' ? '' : $docLine['FORM1099TYPE'];
                $nonoffset['FORM1099BOX'] = $nonoffset['FORM1099'] === 'false' ? '' :  $docLine['FORM1099BOX'];

                // copy dimension fields from line array to nonoffset
                IADimensions::CopyIADimensionFKIDs($docLine, $nonoffset, !util_isPlatformDisabled());

                // Copy the key for the subtotal line...ID's should be passed ultimately but the subtotal
                // logic expect the keys...
                IADimensions::CopyIADimensionValues($line, $nonoffset, !util_isPlatformDisabled());

                // Copy contract attributes (only if not a subtotal line)
                if (!in_array($line['SUBTOTAL'], ['T', 'S']) && $docvalues['PREVIEWHEADERKEY'] && $docLine
                    && ($docLine['BILLABLECONTRACTSCHENTRYKEY'] || $docLine['BILLABLECONTRACTUSAGEBILLINGID'])) {

                    $nonoffset['BILLABLECONTRACTSCHENTRYKEY'] = $docLine['BILLABLECONTRACTSCHENTRYKEY'];
                    $nonoffset['BILLABLECONTRACTUSAGEBILLINGID'] = $docLine['BILLABLECONTRACTUSAGEBILLINGID'];

                }

                if ( $isVatEnabled ) {
                    //$pr_sub_lineno will be used to create line_no for distributed subtotals lines.
                    $key = null;
                    if (isset($line['SUBTOTAL']) || isset($line['DESC'])) {
                        $key = $line['SUBTOTAL'] . '_' . $line['DESC'];
                    }

                    if ($key==null) {
                        $pr_sub_lineno = ++$lineNo;
                    } else {
                        if (isset($mergeTaxDetailKey[$key])) {
                            $pr_sub_lineno = $mergeTaxDetailKey[$key];
                        }
                        else {
                            $pr_sub_lineno = ++$lineNo;
                            $mergeTaxDetailKey[$key] = $pr_sub_lineno;
                        }
                    }

                    $nonoffset['LINE_NO'] = $pr_sub_lineno;

                } else {
                    $nonoffset['LINE_NO'] = ++$lineNo;
                }

                if($copyLineTaxRelation && !empty($line['TAXDETAILKEY'])){
                    $nonoffset['TAXDETAIL#'] = $line['TAXDETAILKEY'];
                }

                if($isPymtTaxSupported && $isPymtTaxEnabled && $line['SUBTOTAL'] != 'S'){
                    $nonoffset['PAYMENTTAXCAPTURE'] = $docvalues['ENTRIES' ][$line['DOC_LINENO']]['PAYMENTTAXCAPTURE'];
                }
                // copy docentry.retainage fields to prentry.retainage fields
                // retainage does not apply to subtotal line item
                // we may need to figure out retainage for VAT taxes in international scenarios.....
                if ( $isRetainageEnabled && empty($nonoffset['SUBTOTAL']) && !isNullOrBlank($remainingRetainageForKit[$docEntryKey]) && $remainingRetainageForKit[$docEntryKey] != 0) {
                    $itemDetailIndex = $this->GetItemDetailIndex($docLine['ITEMDETAILS'], $line['ITEMID']);
                    if ($itemDetailIndex >= 0 && !isNullOrBlank($docLine['ITEMDETAILS'][$itemDetailIndex]['REVPERCENT'])) {
                        $itemPercentOfKit = $docLine['ITEMDETAILS'][$itemDetailIndex]['REVPERCENT'];
                    }
                    else {
                        $itemPercentOfKit = ibcmul(ibcdiv($nonoffset['TRX_AMOUNT'], $docEntries[$line['DOCENTRYKEY']]['TRX_VALUE'], 4, true), '100');
                    }
                    $itemPercentOfTotal = ibcdiv($itemPercentOfKit, $remainingPercentageOfKit[$docEntryKey], 4, true);

                    $nonoffset['RETAINAGEPERCENTAGE'] = $docLine['RETAINAGEPERCENTAGE'];
                    $nonoffset['TRX_AMOUNTRETAINED'] = ibcmul($remainingRetainageForKit[$docEntryKey], $itemPercentOfTotal, 2, true);
                    $nonoffset['AMOUNTRETAINED'] = ibcmul($nonoffset['TRX_AMOUNTRETAINED'], $docvalues['EXCHRATE'], 2, true);
                    if (CRESetupManager::isProjectContractEnabled()) {
                        $nonoffset['PROJECTCONTRACTKEY'] = $docLine['PROJECTCONTRACTKEY'];
                        $nonoffset['PROJECTCONTRACTLINEKEY'] = $docLine['PROJECTCONTRACTLINEKEY'];
                    }

                    // Update running totals for properly allocating retainage across kit items.
                    $remainingPercentageOfKit[$docEntryKey] = ibcsub($remainingPercentageOfKit[$docEntryKey], $itemPercentOfKit, 4, true);
                    $remainingRetainageForKit[$docEntryKey] = ibcsub($remainingRetainageForKit[$docEntryKey], $nonoffset['TRX_AMOUNTRETAINED'], 2, true);
                }

                // map the fields related to Fixed Assets from PO to AP
                if (isset($nonoffset['DOCENTRYKEY']) && !isset($processedDocEntryKeysForFixedAssets[$nonoffset['DOCENTRYKEY']])) {
                    // only do it for the primary line; not for the taxes or discount lines - the assumption is that it will be the first lines.
                    $thisDocLine = $docvalues['ENTRIES'][$line['DOC_LINENO']];
                    $nonoffset['NAMEOFACQUIREDASSET'] = $thisDocLine['NAMEOFACQUIREDASSET'] ?? '';
                    $nonoffset['INCLUDETAXINASSETCOST'] = $thisDocLine['INCLUDETAXINASSETCOST'] ?? '';
                    $processedDocEntryKeysForFixedAssets[$nonoffset['DOCENTRYKEY']] = true;
                }

                if ($mod == 'so' && CRESetupManager::isCREInstalled()) {
                    $nonoffset['PROJECTCONTRACTID'] = $docLine['PROJECTCONTRACTID'];
                    $nonoffset['PROJECTCONTRACTLINEID'] = $docLine['PROJECTCONTRACTLINEID'];
                    $nonoffset['ISRETAINAGERELEASE'] = $docLine['ISRETAINAGERELEASE'];
                    $nonoffset['RETAINAGETOBILL'] = $docLine['RETAINAGETOBILL'];
                    $nonoffset['RETAINAGEBALANCE'] = $docLine['RETAINAGEBALANCE'];

                    if (CRESetupManager::isSummarizedBillingEnabled()) {
                        $nonoffset['ISSUMMARIZED'] = $docLine['ISSUMMARIZED'];
                    }
                    if(!empty($docLine['__SUPPORTING_BILLING']) && $docLine['__SUPPORTING_BILLING'] == 'true'){
                        continue;
                    }
                }
                if ( $mod == 'po' || empty($nonoffset['SUBTOTAL']) ) {
                    $prrecord['ITEMS'][] = $nonoffset;
                } else {
                    // We need those for the subtotal lines as we take them as they are given and we do not call
                    // any translate function in AR Invoice Manager
                    $itemLine = $docvalues['ENTRIES'][$line['DOC_LINENO']] ?? [];
                    if(!empty($itemLine['__SUPPORTING_BILLING']) && $itemLine['__SUPPORTING_BILLING'] == 'true'){
                        continue;
                    }
                    $nonoffset['BASECURR'] = $docvalues['BASECURR'];
                    $nonoffset['CURRENCY'] = $docvalues['CURRENCY'];
                    $nonoffset['EXCHANGE_RATE'] = $docvalues['EXCHRATE'];
                    $nonoffset['EXCH_RATE_DATE'] = $docvalues['EXCHRATEDATE'];
                    $nonoffset['EXCH_RATE_TYPE_ID'] = $docvalues['EXCH_RATE_TYPE_ID'];
                    if(CRESetupManager::isCREInstalled() && !empty($itemLine['PROJECTCONTRACTLINEID'])){
                        $nonoffset['PROJECTCONTRACTLINEID'] = $itemLine['PROJECTCONTRACTLINEID'];
                        $nonoffset['PROJECTCONTRACTLINEKEY'] = $itemLine['PROJECTCONTRACTLINEKEY'];
                    }
                    $prrecord['SUBTOTALS'][] = $nonoffset;
                }
            }
        }

        // We should call this to copy the custom fields from line item level also.
        $this->CopyCustomFields($mod, $docvalues, $docEntries, $prrecord);

        return $ok ;
    }

    /**
     * @param array $detailsArray
     * @param string $itemid
     *
     * @return int
     */
    private function GetItemDetailIndex($detailsArray, $itemid)
    {
        $index = 0;
        foreach ($detailsArray as $detailRow) {
            if ($itemid == $detailRow['ITEMID']) {
                return $index;
            }
            ++$index;
        }

        return -1;
    }

    /**
     * @param array $docvalues
     *
     * @return array
     */
    private function getMappedDocumentEntries($docvalues)
    {
        $mappedDocEntries = [];
        foreach ((($docvalues['ENTRIES']) ?? []) as $entry) {
            $mappedDocEntries[$entry['RECORDNO']] = $entry;
        }

        return $mappedDocEntries;
    }

    /**
     * @param string $mod
     * @param array  $docvalues
     * @param array  $docEntries
     * @param array  $prrecord
     */
    function CopyCustomFields($mod, $docvalues, $docEntries, &$prrecord)
    {
        global $gManagerFactory;
        if($mod == 'so') {
            $aparmgr = $gManagerFactory->getManager('arinvoice');
            $aparlinemgr = $gManagerFactory->getManager('arinvoiceitem');
            $doclinemgr = $gManagerFactory->getManager('sodocumententry', false, array( 'DOCTYPE' => $docvalues['DOCPARID']));
        }
        else if($mod == 'po') {
            $aparmgr = $gManagerFactory->getManager('apbill');
            $aparlinemgr = $gManagerFactory->getManager('apbillitem');
            $doclinemgr = $gManagerFactory->getManager('podocumententry', false, array( 'DOCTYPE' => $docvalues['DOCPARID']));
        } else {
            // we should not come here
            return;
        }

        // Document Custom Fields
        $docCFIds = array_keys($this->customFields);
        $aparCFIds = array_keys($aparmgr->customFields);

        // Document Entry Custom Fields
        $doclineCFIds = array_keys($doclinemgr->customFields);
        $aparlineCFIds = array_keys($aparlinemgr->customFields);

        // Common CustomFields
        $commonFields = array_intersect($docCFIds, $aparCFIds);
        $commonlineFields = array_intersect($doclineCFIds, $aparlineCFIds);

        // Common Custom Fields with same TYPE
        $copyFields = array();
        foreach($commonFields as $cfID) {
            if($this->customFields[$cfID]->type == $aparmgr->customFields[$cfID]->type) {
                $copyFields[] = $cfID;
            }
        }
        $copylineFields = array();
        foreach($commonlineFields as $cfID) {
            if($doclinemgr->customFields[$cfID]->type == $aparlinemgr->customFields[$cfID]->type) {
                $copylineFields[] = $cfID;
            }
        }
        // Copy Compatible Document Custom Fields
        foreach($copyFields as $cfID) {
            $prrecord[$cfID] = $docvalues[$cfID];
        }
        // Copy Compatible Document Entry Custom Fields
        if(!empty($copylineFields) && (!empty($prrecord['ITEMS']))) {
            foreach ( $prrecord['ITEMS'] as &$item ) {
                $docEntrykey = $item['DOCENTRYKEY'];
                foreach($copylineFields as $cfID) {
                    $item[$cfID] = $docEntries[$docEntrykey][$cfID];
                }
            }
            unset($item);
        }
    }


    /**
     *      Common helper for DeleteAPARDocument() and CleanupAPARDocument()
     *
     * @param int       $prrecordkey
     * @param string    $docNo
     *
     * @return SubLedgerTxnManager   or null on failure
     */
    private function prepareToDeleteAPARDocument($prrecordkey, $docNo)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        // You just need the basic prrecord details and that too only for prbatchkey, so translate = false;
        //Chenge to get list
        $prrecordManager = $gManagerFactory->getManager('prrecord');
        $filter = array(
            'selects' => array('RECORDTYPE'),
            'filters' => array(array(array('RECORDNO', '=', $prrecordkey)))
        );
        $prrecordInfo = $prrecordManager->GetList($filter);
        $recordType = $prrecordInfo[0]['RECORDTYPE'];

        //To do delete only if the flow is coming from contract
        if (IsInstalled(Globals::$g->kCNid) && SubLedgerPymtManager::hasOnlyInlineCreditPayment($prrecordkey)) {// change to static function
            if ( ! ContractPaymentHandler::deleteContractInlinePaymentReclass($prrecordkey, $docNo)) {
                return null;
            }
        }

        $entity = SubLedgerTxnManager::$recordTypeToManager[$recordType];
        /** @var SubLedgerTxnManager $entityManager */
        $entityManager = $gManagerFactory->getManager($entity) ;

        return $entityManager;
    }


    /**
     * @param int       $prrecordkey
     * @param string    $deleteOrUpdate
     * @param string    $docNo
     *
     * @return bool
     */
    function DeleteAPARDocument($prrecordkey, $deleteOrUpdate, $docNo)
    {
        $ownerid = "SCMSubLedgerHandler:deleteinvoice";
        XACT_BEGIN($ownerid);

        $entityManager = $this->prepareToDeleteAPARDocument($prrecordkey, $docNo);
        $ok            = ($entityManager != null);

        // Need to triger Delete DoEvent before deleting anything so IMS package can get record to lookup
        if ($ok && $deleteOrUpdate == DELETE_FOR_UPDATE) {
            $entityManager->setSkipDoEvent(true);
        }
        $ok = $ok && $entityManager->delete($prrecordkey);
        if ($ok) {
            $entityManager->setSkipDoEvent(false);
        }

        if($ok){
            XACT_COMMIT($ownerid);
        }else{
            XACT_ABORT($ownerid);
        }

        return $ok;
    }


    /**
     *  When upserting the AR/AP document, we need to delete everything BUT the document, like
     *      the GL entries.  Fortunately, that can be done by calling the "BeforeDelete()" and
     *      AfterDelete() calls, which allow us to be resiliant when other things are added to
     *      AR/AP documents
     *
     *  THIS LOGIC MIMICS THE ABOVE DeleteAPARDocument()
     *
     * @param array       $values
     *
     * @return bool
     */
    public function CleanupAPARDocument( & $values)
    {
        // this is an UPSERT ONLY function
        if ( ! DocumentManager::$upsertFeaturInUse) {
            return false;
        }

        $entityManager = $this->prepareToDeleteAPARDocument($values['PRRECORDKEY'], $values['DOCNO']);

        return ($entityManager != null);
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function UpdateDoc_PRINVBatchReference($values)
    {

        $qry = " update dochdrmst set prinvbatchkey = :1 where docid = :2 and cny# = :3 ";
        return ExecStmt(array($qry, $values['PRINVBATCHKEY'], $values['DOCID'], GetMyCompany()));

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function UpdateDoc_AdditionalGLBatchReference($values)
    {

        $qry = " update dochdrmst set addglbatchkey = :1 where docid = :2 and cny# = :3 ";
        return ExecStmt(array($qry, $values['ADDGLBATCHKEY'], $values['DOCID'], GetMyCompany()));

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function UpdateDoc_INVBatchReference($values)
    {

        $qry = " update dochdrmst set invbatchkey = :1 where docid = :2 and cny# = :3 ";
        return ExecStmt(array($qry, $values['INVBATCHKEY'], $values['DOCID'], GetMyCompany()));

    }

    /**
     * @param array $docvalues
     * @param array $accounting_rules
     * @param string $recordtype
     */
    private function _getAccountingRules($docvalues, &$accounting_rules, &$recordtype)
    {
        $recordtype = ($docvalues['_DOCPAR']['SALE_PUR_TRANS'] == 'Purchase') ? 'pi' : 'ri';
        if (!defined("DEBIT")) {
            define("DEBIT", 1);
        }
        if (!defined("CREDIT")) {
            define("CREDIT", -1);
        }
        // accounts payable are debits, receivables are credits
        $accounting_rules = array(
            'pi' => DEBIT,
            'pa' => DEBIT,
            'pp' => CREDIT,
            'pd' => DEBIT,
            'ri' => CREDIT,
            'ra' => CREDIT,
            'rp' => DEBIT,
            'ro' => DEBIT,
            'rd' => CREDIT,
            'ei' => DEBIT,
            'hi' => DEBIT,
            'hp' => CREDIT,
            'ep' => CREDIT
        );
    }


    /**
     *      From within set(), this is called when upserting.  We don't do this sooner because we need
     *  the [OFFSETS] array to have been filled in, and it isn't when addOrUpsertApAr() is called.
     *
     *      If we are upserting a SCM document, let's see if we can assign
     * the right existing record numbers to the right new records
     * (before here, the ITEM and OFFSET records have no record number,
     * so if we call regularSet below, all old records would be removed
     * and the records without record numbers would be added.  If we
     * can match some/all of the new with the old, then we would update
     * and not delete/recoreate)

     *
     * @param BasePRRecordManager    $trxManager     The appropriate transaction manager
     * @param array                  $values         the new PRRECORD (ARInvoice or APBill record)
     *
     */
    static function resolveRecordNumbersForUpsert($trxManager, &$values)
    {
        // we only expect to be called under this circumstance, but be sure....
        if (DocumentManager::$upsertFeaturInUse && DocumentManager::$upsertPRRecordToo && isset($values['RECORDNO'])) {
            $ownedObjects = $trxManager->GetOwnedObjects();
            if (count($ownedObjects) === 1) {
                $lineManager = $trxManager->GetOwnedObjectManager($ownedObjects[0]['entity']);
                $matchmaker  = new Matchmaker($lineManager, true, false, [], [] /* , false */);
                $matchmaker->matchWithMatchFieldsOnly();
                $existing = [];
                foreach ($values['EXISTING_ENTRIES'] as $oldEntry) {
                    // weed out offsets, they won't match ITEMS and in the new values they usually have record numbers
                    if ( ! isset($oldEntry['ISOFFSET']) || ($oldEntry['ISOFFSET'] !== true)) {
                        $existing[] = $oldEntry;    // this eliminates a bunch of the existing records to match against
                    }
                }
                $matchmaker->setCurrentRecords($existing);
                foreach ($values['ITEMS'] as $index => $item) {
                    if ( ! isset($item['RECORDNO']) && ! isset($item['RECORD#'])) {
                        $matchmaker->matchRecord($values['ITEMS'][$index]);
                        if (isset($values['ITEMS'][$index]['RECORDNO'])) {
                            $values['ITEMS'][$index]['RECORD#'] = $values['ITEMS'][$index]['RECORDNO'];
                        }
                    }
                }
                $trxManager->setUpsertEntries(true);              // tell the Entity Manager we want to upsert
            } else {
                Matchmaker::additionalLogging("Unexpected: BasePRRecordManager has more than one owned object: " . count($ownedObjects));
            }
        }
    }


    /**
     *      When upserting from an SCM Document save, this is called to save the PRRecord
     *
     * @param APBillManager|ARInvoiceManager    $trxManager     The appropriate transaction manager
     * @param array                 $nvalues        the document being saved
     * @param array                 $newValues      the new PRRECORD (ARInvoice or APBill record)
     *
     * @return bool                                 true means 'yes, upsert' and false means 'no, add'
     */
    private function addOrUpsertApAr($trxManager, $nvalues, &$newValues)
    {
        //  Set fromGenerateInvoices, due to validation necessary downstream from ProjectContractBillingTrait.validatePCB
        $newValues['fromGenerateInvoices'] = $nvalues['fromGenerateInvoices'];
        $newValues['INVOICEBY'] = $nvalues['INVOICEBY'] ?? '';
        $newValues['WHENPOSTED'] = $nvalues['WHENPOSTED'];
        if (DocumentManager::$upsertFeaturInUse && DocumentManager::$upsertPRRecordToo && isset($nvalues['PRRECORDKEY'])) {
            DocumentManager::updatingEntity('prrecord');
            DocumentManager::updatingEntity('prentry');      // well, the whole tree!

            $newValues['RECORDNO']   = $nvalues['PRRECORDKEY'];           // we already know this record#
            // set() will eventually call back into resolveRecordNumbersForUpsert(), above
            return $trxManager->set($newValues);                      // let the EntityManager set the owned object tree
        }
        // if we aren't upserting just add the new values
        return $trxManager->add($newValues);
    }

    /**
     * For a kit and stockable kit, the debit/credit posting might be different
     *
     * @param array  $nvalues array of the document data
     * @param array  $entry  line details
     * @param string $itemGLGroup line items item gl group(default)
     * @param string $creditItemGLGroup credit item gl group to be returned
     * @param string $debitItemGLGroup debit item gl group to be returned
     *
     * @return bool always true
     */
    private function overrideItemGlGroups($nvalues, $entry, $itemGLGroup, &$creditItemGLGroup, &$debitItemGLGroup)
    {
        $SkItemGLGroup = $entry['SKITEMGLGROUP'];
        if ( $nvalues["DOCPARID"] == StkitDocumentManager::BUILDKIT ) {
            //for build kits we need to take the Item GL group of the st kit for the debit side
            $debitItemGLGroup = $SkItemGLGroup;
        } else if ( array_key_exists('DEBITITEMGLGROUP', $entry) ) {
            //for COGS of return of Kits with component level posting
            $debitItemGLGroup = $entry['DEBITITEMGLGROUP'];
        } else {
            $debitItemGLGroup = $itemGLGroup;
        }
        if ( $nvalues["DOCPARID"] == StkitDocumentManager::DISKIT ) {
            //for disassemble kits we need to take the Item GL group of the st kit for the credit side
            $creditItemGLGroup = $SkItemGLGroup;
        } else if ( array_key_exists('CREDITITEMGLGROUP', $entry) ) {
            //for COGS of sale of Kits with component level posting
            $creditItemGLGroup = $entry['CREDITITEMGLGROUP'];
        } else {
            $creditItemGLGroup = $itemGLGroup;
        }
     return true;
    }

    /**
     * @param String $itemID
     *
     * @return bool|mixed|string[][]
     */
    protected function getItemTaxGroup($itemID){
        if(!isset($this->_itemTaxGroupCache[$itemID])){
            global $gManagerFactory;
            $docMgr = $gManagerFactory->getManager('document');
            $cny = GetMyCompany();
            $taxgrpargs = array($cny, $itemID);
            $this->_itemTaxGroupCache[$itemID] = $docMgr->DoQuery('QRY_DOCUMENT_FIND_ITEMTAXGROUP', $taxgrpargs);
        }
        return $this->_itemTaxGroupCache[$itemID];
    }



}

