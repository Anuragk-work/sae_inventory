<?php
/**
 * Manager class for health check cost computation
 *
 * @author Sandeep Pasunuri <spasunuri@intacct.com>
 * @copyright 2015 Intacct Corporation, All Rights Reserved
 */

// Until we put this on a diet, companies like GreatMinds run out of ram....
ini_set('memory_limit', '40960M');


/**
 * @param string[] $a
 * @param string[] $b
 *
 * @return int
 */
function compareItemWarehouseAsof($a, $b)
{
    if ($a['ITEMKEY'] < $b['ITEMKEY']) {
        return -1;
    }
    if ($a['ITEMKEY'] > $b['ITEMKEY']) {
        return +1;
    }

    if ($a['WHSEKEY'] < $b['WHSEKEY']) {
        return -1;
    }
    if ($a['WHSEKEY'] > $b['WHSEKEY']) {
        return +1;
    }

    $adate = cachedStrToTime($a['ASON']);
    $bdate = cachedStrToTime($b['ASON']);
    if ($adate    < $bdate) {
        return -1;
    }
    if ($adate    > $bdate) {
        return +1;
    }

    return 0;   // the same
}

/**
 * @param string $date
 *
 * @return string
 */
function cachedStrToTime( $date )
{
    if (!isset($date) || !is_string($date)) {
        return '';
    }
    static $cache = array();

    if ( ! isset($cache[ $date ])) {
        $cache[ $date ] = strtotime( $date );   // this is slow and many dates are the same over and over
    }
    return $cache[ $date ];
}


/**
 * @param string $d1
 * @param string $d2
 *
 * @return int
 */
function MyCompareDate( $d1, $d2 )
{
    $c1 = cachedStrToTime($d1);
    $c2 = cachedStrToTime($d2);
    if ($c1 > $c2) {
        return +1;
    }
    if ($c1 < $c2) {
        return -1;
    }
    return 0;
}



/**
 * @param string[] $a
 * @param string[] $b
 * @param string $aDate
 * @param string $bDate
 *
 * @return int
 */
function compareDateCommon( $a, $b, $aDate, $bDate )
{
    // FIRST: compare items
    $c = strcmp( $a['COMP'], $b['COMP'] );  // ITEM is the kit, COMP is the component (for kits)
    if ($c) {
        return $c;
    }

    // SECOND: compare waurehouse
    $c = strcmp( $a['WAREHOUSEKEY'], $b['WAREHOUSEKEY'] );
    if ($c) {
        return $c;
    }

    // THIRD: compare the 'transaction as-of date'
    if ($aDate == "") {
        $aDate = $a['DOCDATE'];
    }
    if ($bDate == "") {
        $bDate = $b['DOCDATE'];
    }

    $aTime = cachedStrToTime( $aDate );
    $bTime = cachedStrToTime( $bDate );

    if ($aTime < $bTime) {
        return -1;
    }
    if ($aTime > $bTime) {
        return +1;
    }

    // FOURTH: In vs Out (in before out)
    $aIO = ($a['INOUT'] == 'I' ? 0 : 1);
    $bIO = ($b['INOUT'] == 'I' ? 0 : 1);
    if ($aIO < $bIO) {
        return -1;
    }
    if ($aIO > $bIO) {
        return +1;
    }

    // FIFTH: use the record number to disambiguate
    if ($a['DEREC']  < $b['DEREC']) {
        return -1;
    }
    if ($a['DEREC']  > $b['DEREC']) {
        return +1;
    }
    if (abs($a['DECREC']) < abs($b['DECREC'])) {
        return -1;
    }   // abs because I use negative decrecs for docentrycostkit records
    if (abs($a['DECREC']) > abs($b['DECREC'])) {
        return +1;
    }
    return 0;
}


/**
 * @param string[] $a
 * @param string[] $b
 *
 * @return int
 */
function compareCreateDate( $a, $b )
{
    return compareDateCommon( $a, $b, $a['AUWHENCREATED'],  $b['AUWHENCREATED']);
}


/**
 * @param string[] $a
 * @param string[] $b
 *
 * @return int
 */
function compareModifiedDate( $a, $b )
{
    return compareDateCommon( $a, $b, $a['WHENMODIFIED'],  $b['WHENMODIFIED']);
}


/**
 * @param string[] $a
 * @param string[] $b
 *
 * @return int
 */
function compareDocDate( $a, $b )
{
    return compareDateCommon( $a, $b, "", "" );
}






/**
 * Class InvCostToolManager
 */
class InvCostToolManager extends EntityManager
{
    const GOOD          = 'Same';
    const BAD           = 'Different';
    const NEGQTY        = 'Neg Qty';
    const NEGQTY_LAST   = 'Neg Qty; using LAST COST of '; // plus the cost
    const TO_BE_DELETED = 'Will be deleted';
    const FIXED         = 'Fixed';
    const FIXED_NOT_COGS = 'Fixed, but not GL';
    const NOTFIXED      = "Not Fixed - Closed or before 'fix' date";
    const NOTTOBEFIXED  = "Not Fixable - Closed or before 'fix' date";
    const CLOSEDBAD     = "Closed, but Different";
    const DELETED       = 'Deleted';
    const CLOSED        = 'Closed';
    const ADDED         = 'Added';
    const FATAL_ERROR   = "ERROR FOR THIS ITEM/WAREHOUSE";
    const TXN_SOURCE    = "InvCostToolManager";
    const MAX_EVENTS_XML= 200;  // the max XML rows we return with recent events; see invhlthrun.js if you change this!

    const COST_AVERAGE  = "Average Cost";
    const COST_FIFO     = "FIFO";
    const COST_LIFO     = "LIFO";
    const COST_STANDARD = "Standard Cost";

    const CSV_COGSDATA  = 'Fetch COGS Data';
    const CSV_VALUATION = 'Fetch Valuation Data';
    const CSV_ITEM      = 'Fetch Item Data';
    const CSV_MIVPlan   = 'Fetch MIV Plan';

    const MAX_ITEM_GROUP_SIZE = 25000;  // how many transactions do we want in a group of items being read?

    const    VERSION    = "Version: Jul 2023";



    /**
     * @var int $_health_run_id
     */
    private $_health_run_id;

    /**
     * @var bool $reboot   alter data in closed periods EXCEPT FOR GL
     */
    private $reboot;

    /**
     * @var int $docentrycostRecords
     */
    private $docentrycostRecords = -1;   // to speed up reading of records

    /**
     * @var array $glBatches
     */
    private $glBatches = array();   // an index into gl batches

    /**
     * @var array $glBatchCache
     */
    private $glBatchCache = array();    // a cache of gl batches

    /**
     * @var InvBatchManager $invBatchMgr
     */
    private $invBatchMgr = null;

    /**
     * @var GLBatchManager $glBatchMgr
     */
    private $glBatchMgr = null;

    /**
     * @var bool $updateGL
     */
    private $updateGL = false;

    /**
     * @var bool $updateBuildKits
     */
    private $updateBuildKits = true;

    /**
     * @var bool $updateTransfers
     */
    private $updateTransfers = true;

    /**
     * @var bool $fixingData
     */
    private $fixingData;

    /**
     * @var array $lineItemsByDecRec
     */
    private $lineItemsByDecRec = array();        // the most-recently-read line items by their docentrycost record#

    /**
     * @var array $lineItemsByDeRec
     */
    private $lineItemsByDeRec = array();        // the most-recently-read line items by their docentry record#

    /**
     * @var array $lineItemsByDRec
     */
    private $lineItemsByDRec = array();         // the most-recently-read line items by their dochdr record#

    /**
     * @var InvCache $docparKeys
     */
    private $docparKeys;               // Contains the docpar table's sales-or-purchase column where updates-cost is true or (update inventory is True or Value)

    /**
     * @var InvCache $cogs_computed
     */
    private $cogs_computed;           // CSV average-cost COGS data (verbose!)

    /**
     * @var array $beginning_costs
     */
    private $beginning_costs = array();         // Begining average costs for items (cost and quantity by item and warehouse)

    /**
     * @var array $docEntryCostRecords
     */
    private $docEntryCostRecords = array();     // cache of docentry records, which are fetched ONE AT A TIME

    /**
     * @var array $closedBatches
     */
    private $closedBatches = array();           // closed batches so we know if we can change a transaction.  key is the PRBATCH number

    /**
     * @var array $disassemblies
     */
    private $disassemblies = array();           // disassemblies by DocRec record number

    /**
     * @var array $deglresolveAmounts
     */
    private $deglresolveAmounts = array();      // amount and trx_amount from deglresolve by docentry record#

    /**
     * @var string $itemGroup
     */
    private $itemGroup;                         // input parameter: optional item group

    /**
     * @var string $fromItem
     */
    private $fromItem;                          // input parameter: from item.  if empty, means 'all'

    /**
     * @var string $toItem
     */
    private $toItem;                            // input parameter: to item. if empty, from-item is also empty

    /**
     * @var string $warehouse
     */
    private $warehouse;                         // input parameter: optional warehouse id

    /**
     * @var string $asondate
     */
    private $asondate;                          // input parameter: optional start date to fetch transactions

    /**
     * @var string $fixdate
     */
    private $fixdate;                           // input parameter: start date to FIX transactions; defaults to current open period, is not in a closed period

    /**
     * @var bool $COGS
     */
    private $COGS;                              // input parameter: what should be checked/fixed: COGS                (from 'SELECTTOFIX')

    /**
     * @var bool $verbose
     */
    private $verbose;                           // input parameter: should we dump lots of extra data to the CSV files?


    /**
     * @var string $locationID
     */
    private $locationID;                        // input parameter: optional location/entity id

    /**
     * @var int $errorsFound
     */
    private $errorsFound;                       // how many errors were found?

    /**
     * @var int $negQtyFound
     */
    private $negQtyFound;                       // how many qty < 0 were found?

    /**
     * @var int $errorsFixed
     */
    private $errorsFixed;                       // how many were fixed?

    /**
     * @var int $errorsNoGl
     */
    private $errorsNoGl;                        // how many transactions did not have DeGlResolve records?

    /**
     * @var bool $fixAverageCost
     */
    private $fixAverageCost;                    // what kinds of costs are we fixing?

    /**
     * @var bool $fixFIFO
     */
    private $fixFIFO;

    /**
     * @var bool $fixLIFO
     */
    private $fixLIFO;

    /**
     * @var  bool $fixStandard
     */
    private $fixStandard;

    /**
     * @var bool $processFifoLifo
     */
    private $processFifoLifo;                   // should we process fifo and lifo records?  (default is NO for initial release)

    /**
     * @var bool $extraCSVOutput
     */
    private $extraCSVOutput;                    // for testing and debugging, should we put out more info?

    /**
     * @var bool $obeyDocparQandV
     */
    private $obeyDocparQandV;                   // should costing pay attention to the Q and V values in the docpar record?

    /**
     * @var bool $roundOnOutput
     */
    private $roundOnOutput;                     // should we round on output??

    /**
     * @var bool $dontRoundOnSave
     */
    private $dontRoundOnSave;                   // should we round on save?  Default for the whole product is ROUND; here we can override that if we want

    /**
     * @var bool $sortModified
     */
    private $sortModified;                      // sort by the modified date, not the as-of date

    /**
     * @var bool $sortCreate
     */
    private $sortCreate;                        // sort by the create date, not the as-of date

    /**
     * @var bool $glImpact
     */
    private $glImpact;                          // show the GL impact?

    /**
     * @var int $onHandHoldOrderRecordNumber
     */
    private $onHandHoldOrderRecordNumber;       // from ICTOTAL

    /**
     * @var DocumentEntryCostManager $decMgr
     */
    private $decMgr;

    /**
     * @var StkitDocumentEntryCostManager $decMgrKits
     */
    private $decMgrKits;

    /**
     * @var array $kitsByWarehouseItem
     */
    private $kitsByWarehouseItem = array();

    /**
     * @var array $startDatePerLocation     the start of the OPEN PERIOD per location
     */
    private $startDatePerLocation = [];

    /**
     * @var InvCostToolHelper  $invCostToolHelper
     */
    private $invCostToolHelper = null;

    /**
     * @var bool $quickRun          Are we running QUICK or THOROUGH?
     */
    private $quickRun = false;

    /** @var InvBitmap $reportOnThisLine */
    private $reportOnThisLine = null;


    /**
     * Constructor
     *
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
        $gManagerFactory   = Globals::$g->gManagerFactory;
        $this->decMgr      = $gManagerFactory->getManager('documententrycost');
        $this->decMgrKits  = $gManagerFactory->getManager('stkitdocumententrycost');
        $this->invBatchMgr = $gManagerFactory->getManager('invbatch');
        $this->glBatchMgr  = $gManagerFactory->getManager('glbatch');

        // 2017 R2
        $this->processFifoLifo = true; // (isset($_COOKIE['COGSTOOL_FIFO_LIFO']) && ($_COOKIE['COGSTOOL_FIFO_LIFO'] != ''));

            // We collect more data than we dump for users;
            // this will allow us to dump extra data interesting for testing/debugging
        $this->extraCSVOutput = (isset($_COOKIE['COGSTOOL_DEBUG']) && ($_COOKIE['COGSTOOL_DEBUG'] != ''));

            // There is some debate as to whether the product pays attention to the 'docpar' record's Q/V/Both/Neither values.
            // set this flag to true to pay attention to those values, false to ignore them.
        $this->obeyDocparQandV = true;

        // should we round results on CSV files?  Default: no
        $this->roundOnOutput =
            ( isset($_COOKIE['COGSTOOL_ROUND']) && ( $_COOKIE['COGSTOOL_ROUND'] != '' ) );   // so defaults off

        // should we round results on CSV files?  Default: no
        $this->dontRoundOnSave = ( isset($_COOKIE['COGSTOOL_DONT_ROUND_ON_SAVE'])
                                   && ( $_COOKIE['COGSTOOL_DONT_ROUND_ON_SAVE'] != '' ) );   // so defaults off

        $this->Init();
    }

    public function Init()
    {
        $this->lineItemsByDecRec = array();        // the most-recently-read line items by their docentrycost record#
        $this->lineItemsByDeRec = array();         // the most-recently-read line items by their docentry record#
        $this->lineItemsByDRec = array();          // ditto for doc header

        $this->cogs_computed = new InvCache();    // CSV average-cost COGS data (verbose!)
        $this->beginning_costs = array();         // Begining average costs for items (cost and quantity by item and warehouse)
        $this->docEntryCostRecords = array();     // cache of docentry records, which are fetched ONE AT A TIME

        $this->closedBatches = array();           // closed batches so we know if we can change a transaction.  key is the PRBATCH number
        $this->disassemblies = array();           // list of disassemblies by SOURCE (i.e. Build) docrec record number
        $this->deglresolveAmounts = array();      // anmount and trx_amount by docentrycost record# from deglresolve table
        $this->glBatches = array();               // gl batches index
        $this->glBatchCache = array();            // gl batches cached
        $this->docentrycostRecords = -1;          // are there so many we should optimize queries?

        $this->onHandHoldOrderRecordNumber = array();            // from ICTOTAL
        $this->kitsByWarehouseItem = array();
        $this->reportOnThisLine = new InvBitmap();
        CostingHandler::initializeCosting();
    }



    /**
     * @param array     $params
     * @param string    $unitName
     * @param string    $groupName
     * @param string    $manager
     *
     * @return bool
     */
    private function changeUnitIntoGroup( &$params, $unitName, $groupName, $manager )
    {
        if ($params[ $unitName ] != '') {
            /**
             * @var DimensionGroupManager $groupMgr
             */
            $gManagerFactory    = Globals::$g->gManagerFactory;
            $groupMgr           = $gManagerFactory->getManager($manager);
            $members            = $groupMgr->getGroupMembersById($params[$unitName]);

            if (is_array($members) && (!empty($members)) && (!empty($members['MEMBERRECS']))) {
                //logFL("Found group for $unitName " . $params[$unitName] . "; " . var_export($members,true));
                $params[$groupName] = $members['MEMBERRECS'];
            } else {
                //i18N::TODO - (Input from File owner (Blank Legacy code added in definition file))
                Globals::$g->gErr->addIAError(
                    'INV-0646', __FILE__ . ':' . __METHOD__,
                    "Invalid item group: " . $params[ $unitName ],['PARAMS_UNIT_NAME'=>$params[ $unitName ]]
                );
                return false;
            }
        }
        return true;
    }

    /**
     * @param array $values
     *
     * @param bool  $isLocking If true, acquire feature lock, else don't.
     *
     * @return bool
     */
    private function initParams(&$values, $isLocking = false)
    {
        $this->itemGroup = null;

        if (! $this->changeUnitIntoGroup($values, 'ITEMGLGROUP', 'ITEMGLGROUP_MEMBERS', 'itemgroup' )) {
            return false;
        }
        if (isset($values['ITEMGLGROUP_MEMBERS']) && is_array($values['ITEMGLGROUP_MEMBERS'])) {
            $comma = '';
            $this->itemGroup = '(';
            foreach($values['ITEMGLGROUP_MEMBERS'] as $one) {
                $this->itemGroup .= $comma . $one;  // first time, $comma is empty
                $comma = ',';
            }
            $this->itemGroup .= ')';    // now this is all set for an 'IN ' clause
        }

        list($item)             =   explode("--", $values['FROMITEMID'] ?? '');
        $this->fromItem         =   $item;
        list($item)             =   explode("--", $values['TOITEMID'] ?? '');
        $this->toItem           =   $item;
        $this->warehouse        =   $values['WAREHOUSEID'] ?? '';
        $this->locationID       =   $values['LOCATIONID']  ?? '';

        $invPrefs = array();
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
            // we used to ask the customer for the start-to-search date.  However, the wrong value
            // could profoundly change results if, for example, you set the date AFTER purchases were made
            // that still have qtyleft.
            // BUT, we have a date in preferences we want to check; that is the date the inventory system STARTED
            // if, for example, a customer converted items from non-inventory to inventory.
        $this->asondate         =   "01/01/1970"; // $values['ASOFDATE'];
        if (isset($invPrefs['INVSTARTDATE']) && ($invPrefs['INVSTARTDATE'] != "")) {
            $this->asondate = $invPrefs['INVSTARTDATE'];
        }

        $costingMethods         =   $values['COSTMETHODCHECK'];  // some combo of these: 'Average,Standard,FIFO,LIFO';
        $this->fixAverageCost   =   (strpos($costingMethods, "Average") !== false);
        $this->fixFIFO          =   ($this->processFifoLifo && (strpos($costingMethods, "FIFO") !== false));
        $this->fixLIFO          =   ($this->processFifoLifo && (strpos($costingMethods, "LIFO") !== false));
        $this->fixStandard      =   ($this->processFifoLifo && (strpos($costingMethods, "Standard") !== false));

        $values['SELECTTOFIX']  = 'INVVALDATA,COGSDATA';   // in older versions, there was also 'VERBOSE' and that's illegal now.  Force it off.

        $values[':RECORDNO']    = 0;                  // so we don't update THIS record
        $values['RECORDNO']     = 0;

        // find RECORDNO; we haven't saved the data yet
        $gManageFactory = Globals::$g->gManagerFactory;
        $eMgr = $gManageFactory->getManager('invhlthrun');
        $this->_health_run_id = $eMgr->GetNextRecordKey();
        $values['RECORDNO']   = $this->_health_run_id;      // save the record we found

        $this->quickRun           = ($values['ANALYZE_OR_UPDATE'] == InvHlthRunManager::QuickAnalyze) ||
                                    ($values['ANALYZE_OR_UPDATE'] == InvHlthRunManager::QuickUpdate);

        // 'reboot' is the awful name given to updating the inventory subledger in closed periods
        //     I guess, like you're rebooting your costing.  No need to do this in a quick run (for now)
        $this->reboot = false;
        if (( ! $this->quickRun) && isset($values['CLOSED_NO_GL']) && ($values['CLOSED_NO_GL'] === 'CP' )) {
            $this->reboot = true;
        }

        // The FIX as-of-date must be in an open period.
        $this->fixdate = $values['FIXASOFDATE'];
        $openDate = ($this->reboot ? $this->asondate : GetCompanyOpenDate());
        if (($this->fixdate == '') ||
            (MyCompareDate($openDate, $this->fixdate) > 0)) {
            $this->fixdate = $openDate;
            $values['FIXASOFDATE'] = $this->fixdate;    // in case caller cares
        }

        // Get open dates PER LOCATION, if we have locations
        if (IsMultiEntityCompany() && !GetContextLocation()) {
            $res = QueryResult(array("SELECT STARTOPEN, record# LOCATIONKEY FROM locationmst WHERE cny#=:1 ", GetMyCompany()));
            if ($res !== false) {
                foreach ($res as $oneRecord) {
                    // take the later of the customer/system 'fix date' and the actual start of the open period
                    $this->startDatePerLocation[ $oneRecord['LOCATIONKEY']] = ((MyCompareDate( $oneRecord['STARTOPEN'], $this->fixdate) > 0) ? $oneRecord['STARTOPEN'] : $this->fixdate);
                }
            }
        }

            // There is a FROM ITEM and a TO ITEM.  Make sure if one is populated, both are, and make sure FROM < TO
        if ($this->fromItem == '') {
            $this->fromItem = $this->toItem;
        }
        if ($this->toItem == '') {
            $this->toItem = $this->fromItem;
        }
        // now they are both empty or both have something in them....
        if (($this->fromItem != '') && (strcmp( $this->fromItem , $this->toItem) > 0)) {
            // swap them; from > to
            $t               = $this->fromItem;
            $this->fromItem  = $this->toItem;
            $this->toItem    = $t;
        }

        $this->COGS               = $this->quickRun;    // or it can be set below for non-quick runs
        $this->verbose            = false;
        $this->sortModified       = false;
        $this->sortCreate         = false;
        $this->glImpact           = true;  // $this->quickRun;    // or it can be set below for non-quick runs

        // But this is our main output, so lets keep it for a while
        if (strpos($values['SELECTTOFIX'], "COGSDATA") !== false) {
            $this->COGS = true;
        }
        $this->extraCSVOutput = true;     // in case it wasn't on before
        $this->roundOnOutput = false;
        $this->dontRoundOnSave = true;

       if (isset($values['SHOWALL']) && $values['SHOWALL'] === 'AT' ) {
            $this->verbose = true;
            $this->glImpact = true; // only valid when showing all transactions
        }

        // Hack hack, wheeze wheeze!
        // For escalations, we may want to reset qtyLeft even for Average Cost records.
        //  We may want to fold this into the usual work, but for now it is special.
        if (GetMyLogin() == SUPPORTUSER_LOGINID) {
             if (strpos( $values['DESCRIPTION'], "SORT MODIFIED") !== false ) {
                $this->sortModified = true;
            }
            if (strpos( $values['DESCRIPTION'], "SORT CREATE") !== false ) {
                $this->sortCreate = true;
            }
        }

         // *** DANGER DANGER DANGER *****
        // *** THIS SWITCH CHANGED SENSE; THE TEXT IS NOW "Post to the GL (OPEN periods)"
        // *** which is the OPPOSITE of 'no gl'.
        $this->updateGL = false;
        if ( isset($values['NO_GL']) && $values['NO_GL'] === 'true') { // default is true, post to the GL
            $this->updateGL = true;         // so normally we get this
        }

        // Default to TRUE if not specified
        $this->updateBuildKits = true;
        /*
        if (($values['UPDATE_BUILDKITS'] ?? 'true') === 'true') {
            $this->updateBuildKits = true;
        }
        */

        // Default to TRUE if not specified
        $this->updateTransfers = true;
        /*
        if (($values['UPDATE_TRANSFERS'] ?? 'true') === 'true') {
            $this->updateTransfers = true;
        }
        */

        $this->errorsFound          = 0;
        $this->negQtyFound          = 0;
        $this->errorsFixed          = 0;
        $this->errorsNoGl           = 0;

        $this->invCostToolHelper    = new InvCostToolHelper($values);

        if ($isLocking && ! $this->invCostToolHelper->getFeatureLock()) {
            Globals::$g->gErr->addIAError(
                'INV-0136',
                __FILE__ . ":" . __LINE__,
                'Concurrent request for your company in process',
                [],
                'Another Maintain Inventory Valuation is in process.',
                [],
                'Wait for the system to finish processing the original request, and then try again.',
                []
            );
            return false;
        }

        return true;
    }



    /**
     * fputcsv() demands a a file, addslashes() doesn't do what I want.
     *  Excel and Google Docs use "" around strings with commas, and escape " with " before it ("")
     *
     * @param bool|string $s
     *
     * @return string
     */
    private function escapeForCSV( $s )
    {
        if ($s === null) {
            $s = '';
        }
        if (is_bool($s)) {
            $rtn = ($s ? "Yes" : "No");
        } else if (is_numeric($s)) {
            $rtn = (($s != 0) ? ($s . '') : "0");
        } else {
            $rtn = ($s === '') ? '' : str_replace('"', '""', $s);    // escape double quotes
            if ((strpos($rtn, '"') !== false) ||
                (strpos($rtn, "\n") !== false) ||
                (strpos($rtn, ',') !== false)) {
                $rtn = '"' . $rtn . '"';
            }
        }
        return $rtn;
    }


    /**
     * @param string[] $values
     *
     * @return bool
     */
    public function fetchAction(&$values)
    {
        $this->fixingData = false;
        $this->quickRun   = ($values['ANALYZE_OR_UPDATE'] == InvHlthRunManager::QuickAnalyze);

        $ok             = $this->initParams($values, true);
        if ($ok) {
            $source = __METHOD__;
            if (IsMultiEntityCompany()) {
                $_sess = Session::getKey();
                SetUserContext($_sess, '', '', 'F');
            }

            $ok = $ok && $this->_QM->beginTrx($source);
            $ok = $ok && $this->healthCheck();
            $this->_QM->rollbackTrx($source);           // roll back so no changes made by the sql routines are recorded.

            $this->createActionLogRecords('', $values['MIVPLAN_XML']);                // generate CSV
            $values['ERRORSDFOUND'] = $this->errorsFound;
            $values['ERRORSDFIXED'] = $this->errorsFixed;   // should be zero
            $values['ERRORSQTY0'] = $this->negQtyFound;

            if (IsMultiEntityCompany()) {
                $_sess = Session::getKey();
                SetUserContext($_sess, GetScriptType(), GetContextLocation(), 'T');
            }
        }
        return $ok;
    }

    /**
     * @param string[] $values
     *
     * @return bool
     */
    public function fixAction(&$values)
    {
        $this->fixingData = true;
        $this->quickRun   = ($values['ANALYZE_OR_UPDATE'] == InvHlthRunManager::QuickUpdate);

        // kinda late, but better late than never.
        if ($this->sortModified || $this->sortCreate) {
            $gErr = Globals::$g->gErr;

            $msg = "When sorting by true-create date or by modified-date, you cannot update...";
            $gErr->addIAError('INV-0513', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );

            return false;
        }

        if (IsMultiEntityCompany()) {
            $_sess = Session::getKey();
            SetUserContext($_sess, '', '', 'F');
        }

        $source = self::TXN_SOURCE;

        $ok = $this->initParams($values, true);
        if ($ok) {

            $ok = $ok && $this->_QM->beginTrx($source);

            $ok = $ok && $this->healthCheck();

            $messages = '';

            // Any last stockable kit updates based on parts updating?
            $this->invCostToolHelper->adjustStockableKitsFromUpdatedParts($messages);

            if ($this->updateGL) {
                // After all the updates, save all the dirty batches
                $ok = $ok && $this->saveBatches($messages);
            }

            $this->createActionLogRecords($messages, $values['MIVPLAN_XML']);                // Create CSV *after* fixing stuff

            $force = false;
            // 'CP' is "update in closed periods"
            if ($this->updateGL /* && isset($values['CLOSED_NO_GL']) && $values['CLOSED_NO_GL'] === 'CP' */) {
                $force = true;
            }
            $this->invCostToolHelper->saveItemWarehouseTimers($force);        // update the item/warehouses

            if (IsMultiEntityCompany()) {
                $_sess = Session::getKey();
                SetUserContext($_sess, GetScriptType(), GetContextLocation(), 'T');
            }

            if ($ok && !HasErrors()) {
                $ok = $this->_QM->commitTrx($source);
            } else {
                $this->_QM->rollbackTrx($source);
                include 'popuperror.phtml';
                exit();
            }

            $values['ERRORSDFOUND'] = $this->errorsFound;
            $values['ERRORSDFIXED'] = $this->errorsFixed;
            $values['ERRORSQTY0'] = $this->negQtyFound;
            $values['ERRORSNOGL'] = $this->errorsNoGl;
            $values['GLERRORS'] = $messages;
        }
        return $ok;
    }


    /**
     *      What transactions that affect COGS may need changing by the costing code?
     *
     * @param  string[] $qparams     Parameters from JavaScript's 'otherparams' section
     *
     * @return string                The 'CHANGES' records in XML format
     */
    public function getListOfPotentialChanges(&$qparams)
    {
        $ret                    = "";
        $valuesInternal         = [];

        // Is the UI asking for an EXISTING plan, or a brand new one?
        $existingPlan           = $qparams['existing'] ?? -1;
        if ($existingPlan == 0) {
            $text = I18N::getSingleToken("IA.NO_DATA_FOUND") ;
            $ret = "<change item='' warehouse='' effective='' impact='' change='$text' details=''></change> ";
        } else if ($existingPlan > 0) {
            /** @var ActionLogManager $logMgr */
            $logMgr = Globals::$g->gManagerFactory->getManager('actionlog');
            $logs = $logMgr->Get($existingPlan);
            $ret = $logs['LOG_BLOB'];   // it is already in XML format
        } else {

            $valuesInternal['CLOSED_NO_GL'] = (($qparams['openonly'] ?? true) == 'true') ? 'OP' : 'CP';
            $valuesInternal['FROMITEMID'] = $qparams['from'] ?? '';
            $valuesInternal['TOITEMID'] = $qparams['to'] ?? '';
            $valuesInternal['ITEMGLGROUP'] = $qparams['glg'] ?? '';
            $valuesInternal['WAREHOUSEID'] = $qparams['whse'] ?? '';
            $valuesInternal['COSTMETHODCHECK'] = $qparams['costmethod'] ?? 'Average,Standard,FIFO,LIFO';
            $valuesInternal['ANALYZE_OR_UPDATE'] = InvHlthRunManager::QuickUpdate;  // to get the right results
            if ($valuesInternal['ITEMGLGROUP'] == 'undefined') {
                $valuesInternal['ITEMGLGROUP'] = '';    // seems to happen in the JS in DUPLICATE
            }
            $ok = $this->initParams($valuesInternal);

            if ($ok) {
                // Is this needed?  Dunno!
                if (IsMultiEntityCompany()) {
                    $_sess = Session::getKey();
                    SetUserContext($_sess, '', '', 'F');
                }

                $dateToStartReadingRecords = $this->startReadingFromThisDate();
                $ok = $this->invCostToolHelper->getItemWarehouseTimers($this->itemGroup, $this->fromItem, $this->toItem, $this->warehouse, true, $dateToStartReadingRecords);
                if ($ok) {
                    $ret = $this->formatWhatNeedsUpdatingAsXML($this->invCostToolHelper->itemWarehouseInfo);    // The results of the above
                }

                if (IsMultiEntityCompany()) {
                    $_sess = Session::getKey();
                    SetUserContext($_sess, GetScriptType(), GetContextLocation(), 'T');
                }
            }
        }
        return $ret;
    }


    /**
     *      We have a list of things that need updating and the client has asked for it.
     *  Here, we format it as XML to return to the qrequest....
     *
     *
     * @param array $whatNeedsUpdating       the list of things needing updating
     *
     * @return string                               The XML reply to the client
     */
    private function formatWhatNeedsUpdatingAsXML($whatNeedsUpdating)
    {
        $xmlStr    = "";
        $itemOrder = [];
        foreach ($whatNeedsUpdating as $item => $itemArray) {
            foreach ($whatNeedsUpdating[ $item ] as $warehouse => $warehouseArray) {
                $itemOrder[] = [$item, $warehouse];
            }
        }
        // sort the items and warehouses into order (item, then warehouse)
        usort($itemOrder, function ($a, $b) {
            $diff = strcoll($a[0], $b[0]);  // compare item
            if ($diff == 0) {
                $diff = strcoll($a[1], $b[1]);  // compare warehouse
            }
            return $diff;
        } );

        $count = 0;
        foreach ($itemOrder as $itemWh) {

            $item           = $itemWh[0];
            $warehouse      = $itemWh[1];
            $htmlItem       = isl_htmlspecialchars($item);
            $htmlWhse       = isl_htmlspecialchars($warehouse);
            $row            = $whatNeedsUpdating[ $item ][ $warehouse ];
            $htmlDate       = isl_htmlspecialchars($row['EARLIEST_EFFECTIVE_DATE']);
            $htmlImpact     = isl_htmlspecialchars($row['AFFECTED']);
            $details        = isl_htmlspecialchars($row['DETAILS']);
            $change         = isl_htmlspecialchars($row['WHY']);
            $xmlStr        .= "<change item='$htmlItem' warehouse='$htmlWhse' effective='$htmlDate' impact='$htmlImpact' change='$change' details='$details'></change> ";
            $count++;
            if ($count > self::MAX_EVENTS_XML) {     // arbitrary max so as to not swamp the ui
                break;
            }
        }
        return $xmlStr;
    }


    /**
     *  What is the ONE earliest date to start reading records.
     *  - if we're reading both open AND CLOSED periods, then it is the 'beginning of time' (like, the inventory start date)
     *  - if we're reading only OPEN periods, then we find the earliest open period over all items.
     *
     *
     * @return string           The earliest date to start.
     */
    private function startReadingFromThisDate()
    {
        // if we're doing open AND closed periods, then start on the inventory start date or 1970.
        if ($this->reboot) {
            $earliestDateToStart = $this->fixdate;  // not the ason date, which is the start of time

            // otherwise if there are location-based dates, use those
        } else if (isset($this->startDatePerLocation)) {
            // open dates start at 01/01/1970, but if you close a period then it is larger.
            // closing, say, USA also closes AZ and other locations below the USA.
            $earliestDateToStart = '12/31/2099'; // max so we can find the smallest
            foreach ($this->startDatePerLocation as $oneLocationsDate) {
                if (MyCompareDate($earliestDateToStart, $oneLocationsDate) > 0) {
                    $earliestDateToStart = $oneLocationsDate; // find min of the dates
                }
            }
        } else {
            // if we're not the admin, take the generic open date
            $earliestDateToStart = GetCompanyOpenDate();
        }
        return $earliestDateToStart;
    }


    /**
     *  Some large companies will have over a million docentrycost records and that takes a LOT of ram.
     *  Here, we see how many docentrycost records there are PER ITEM we intend to read, and then split up
     *  groups of items so we don't read 'too many' at a time.
     *
     * @param string    $dateToStartReadingRecords          start date
     *
     * @return bool|array                                   false for sql error, otherwise
     *                                                      an array BY method BY groups OF items
     */
    private function getGroupsOfItemsToProcess($dateToStartReadingRecords)
    {
        // put FIFO last, as Stockable Kits are FIFO, and are at the END of the FIFOs....
        $rtn     = ['A' => [], 'L' => [], 'S' => [], 'F' => []];
        $methods = [];
        if ($this->fixAverageCost) {
            $methods[] = 'A';
        }
        if ($this->fixLIFO) {
            $methods[] = 'L';
        }
        if ($this->fixStandard) {
            $methods[] = 'S';
        }
        if ($this->fixFIFO) {
            $methods[] = 'F';
        }

        foreach ($methods as $method) {
            $items = $this->invCostToolHelper->getIitemsForMethod($method);
            if ( ! empty($items)) {
                // here we don't bother looking for kits because we don't need to be super exact and there are likely
                // not that many kit records anyway.  Occasionally I'll be wrong and there WILL be a lot, but that would
                // not be common, I think.
                $qry    = [];
                $qry[0] = "SELECT itemkey, count(*) as count FROM docentrycost WHERE cny# = :1 AND datein >= to_date(:2, 'MM/DD/YYYY') ";
                $qry[1] = GetMyCompany();
                $qry[2] = $dateToStartReadingRecords;
                $qry    = PrepINClauseStmt($qry,$items,' and itemkey ', true, 'items', true);
                $qry[0] .= " GROUP BY itemkey";
                $result = QueryResult($qry);
                if ($result === false) {
                    return false;
                }

                $group        = [];
                $countInGroup = 0;
                foreach ($result as $row) {
                    $group[]       = $row['ITEMKEY'];
                    $countInGroup += (int)$row['COUNT'];    // could be zero, thats ok
                    if ($countInGroup > self::MAX_ITEM_GROUP_SIZE) {
                        $countInGroup   = 0;
                        $rtn[$method][] = $group;   // another group of items
                        $group          = [];
                    }
                }

                if ( ! empty($group)) {
                    $rtn[$method][] = $group;   // ex: $rtn['A'][ [group1], [group2], ... ]
                }
            }
        }
        return $rtn;
    }


    /**
     *
     * @return bool
     */
    private function healthCheck()
    {
        $ok = true;
        $this->deglresolveAmounts = array();           // we'll fill these in later

        $this->collectDocparInfo();
        $this->getStockableKitDisassemblies();  // so we can track them

        $dateToStartReadingRecords = $this->startReadingFromThisDate();

        // Figure out which batches are 'closed' within our time period
        if ($this->updateGL) {
            $ok = $ok && $this->fetchClosedBatches($dateToStartReadingRecords);
        }

        // Get the COGS amounts for all records
        $this->getDeGlResolveAmounts($dateToStartReadingRecords);

        // get the list of items that need updating; this feeds into the $itemGroupsByMethod, below, AND the beginning costs below
        $ok = $ok && $this->invCostToolHelper->getItemWarehouseTimers($this->itemGroup, $this->fromItem, $this->toItem, $this->warehouse, $this->quickRun,$dateToStartReadingRecords);

        $ok = $ok && $this->getBeginningCosts($dateToStartReadingRecords);

        $itemGroupsByMethod = [];
        if ($ok) {
            // We want to only fetch a reasonable number of records at a time, so based
            // on the above routine's list of items to update, break those into groups
            // based on the number of transactions in each item
            //  example: $itemGroupsByMethod['A'][ [group1], [group2], ... ]
            $itemGroupsByMethod = $this->getGroupsOfItemsToProcess($dateToStartReadingRecords);
            if ($itemGroupsByMethod === false) {
                $ok = false;
            }
        }

        $costMethods = ['A' => self::COST_AVERAGE, 'F' => self::COST_FIFO, 'L' => self::COST_LIFO, 'S' => self::COST_STANDARD];
        foreach ($itemGroupsByMethod as $method => $groups) {
            foreach ($groups as $group) {
                $lineItems = $this->fetchItemLines($group, $dateToStartReadingRecords);
                $this->seeWhatSqlEmbeddedRoutinesChange( $lineItems, $this->fixingData, $method );
                $this->processCosts($lineItems, $costMethods[$method]);

                if ($this->fixingData) {
                    $ok = $ok && $this->fixDocEntryCostData($lineItems);
                }
                $this->lineItemsByDecRec = [];
                $this->lineItemsByDeRec  = [];
                $this->lineItemsByDRec   = [];
                $this->reportOnThisLine  = new InvBitmap();  // reset for the next group
                unset($lineItems);
            }
        }

        $this->disassemblies = array(); // free space

        return $ok;
    }

    /**
     *  create action log records - generate the CSV files
     *
     * @param string $glMessages    any error messages to log from saving to the GL
     * @param string $mivPlanXml    xml from the plan on what to do
     *
     */
    public function createActionLogRecords( $glMessages, $mivPlanXml )
    {
        if ($this->COGS) {
            $this->logCOGSDataAsCSV( $glMessages );
        }

        if ($mivPlanXml != '') {
            $this->processOffline(self::CSV_MIVPlan, 'Inventory MIV Plan', $mivPlanXml);
        }
    }

    /**
     * @param string $action
     * @param string $description
     * @param string $csv
     *
     * @return bool
     */
    function processOffline($action, $description, $csv)
    {
        $logValues = array(
            'MODULE'      => 'Inventory',
            'ACTION'      => $action,
            'LOGTYPE'     => 'INVHEALTHCHK',
            'DESCRIPTION' => $description,
            'OBJECT'      => 'InvHlthRun',
            'OBJECTKEY'   => $this->_health_run_id,
            'LOG_BLOB'    => $csv,
            'OBJECTID'    => '',
            'OBJECTNAME'  => '',
        );
        $ok = self::storeCSVInLog($logValues); // static function

        return $ok;
    }


    /**
     *   Fetch the open batches, so we can see if records should be updateable or not.
     *
     * @param string    $dateToStartReadingRecords      The start date for reading; no point in looking earlier than this.
     *
     * @return bool
     */
    private function fetchClosedBatches($dateToStartReadingRecords)
    {
        // get the record numbers of the PR BATCH records that are CLOSED (not open)
        // documents are tied to PRRECORD via PRRECORDKEY, and PRRECORD is tied to batch via PRBATCHKEY
        $query = array();
        $query[0] = "
            select 
                prrecordmst.record# 
            from 
                prrecordmst, prbatchmst
            where 
                prrecordmst.cny#=:1 
            AND prbatchmst.cny#=:1 
            AND prrecordmst.prbatchkey = prbatchmst.record# 
            AND prbatchmst.open='F'
            AND prrecordmst.whencreated >= to_date(:2,'MM/DD/YYYY') ";
        $query[] = GetMyCompany();
        $query[] = $dateToStartReadingRecords;

        $result = QueryIterable($query);
        if ($result === false) {
            return false;
        }

        foreach ($result as $prrecord) {
            $this->closedBatches[ $prrecord['RECORD#'] ] = true;    // true meaning it is closed
        }
        $result->close();
        unset($result);
        return true;
    }


    /**
     * Fetch Line Items
     *
     * @param string[]  $itemGroup                  The array of items to be read
     * @param string    $dateToStartReadingRecords  Earliest date to return
     *
     * @return array|bool            The collection of records read from SQL, or false if sql error
     */
    private function fetchItemLines($itemGroup, $dateToStartReadingRecords)
    {
        $rtn = array();
        $this->lineItemsByDecRec = array(); // works for only the most recently read.....
        $this->lineItemsByDeRec  = array();
        $this->lineItemsByDRec   = array();

        $dec = "docentrycost";
        $sysgen = "dec.systemgenerated"; // not avail for kits
        $adjdocentrycostkey = "adjdocentrycostkey,";
        $docentrycostkitkey = "0 as docentrycostkitkey,";   // docentrycost has no docentrycostkitkey, so for this pass, return 0

        for ($i = 0; $i < 2; $i++) {
            $query   = [];
            $query[] = "
            select
                d.whencreated AS docdate,
                d.record# AS drec,
                de.record# AS derec,
                de.source_doclinekey AS deref,
                dec.record# AS decrec,
                dec.docentrycostkey AS decref,
                to_char(d.lastupdated,'DD-MM-YYYY HH24:MI:SS') as lastupdated,
                d.docid,
                d.docno,
                d.docparkey,
                d.createdfrom,
                dec.IN_OUT AS inout,
                i.itemtype,
                de.itemkey item,
                dec.itemkey comp,           -- can be different from item if this is a kit build/disassemble
                dec.whsekey warehousekey,   -- get the component warehousekey
                decode(dec.in_out, 'I', 1, -1) * dec.quantity AS quantity,
                de.quantity as dequantity,  -- hopefully sum(quantity) over DE matches this quantity
                d.subtotal,
                d.total,
                dec.UNITCOST,
                dec.cost as COGS,
                de.value as devalue,
                dec.serialno,
                dec.lotno,
                dec.aislekey,
                dec.rowkey,
                dec.binkey,
                dec.cost,  -- does NOT carry the apportioned costs, ever
                to_char( d.auwhencreated, 'MM/DD/YYYY') as auwhencreated, -- treat as a date
                d.createdby,
                d.prrecordkey,
                d.whenmodified,
                d.modifiedby,
                dec.qtyleft,
                de.uiprice,
                de.exchange_rate,
                dec.expirationdate,
                dec.affects_inventory,
                de.locationkey,
                de.deptkey,
                d.docparid,
                $sysgen ,
                $adjdocentrycostkey
                $docentrycostkitkey
                '$dec' as SOURCE -- so we know if this is a kit part or not
            from
                dochdrmst d, docentrymst de, $dec dec, icitemmst i
            where
                d.cny#=:1
                AND dec.cny#=d.cny#
                AND i.cny#=dec.cny#
                AND de.cny#=d.cny#
                AND i.itemid=dec.itemkey
                AND dec.docentrykey=de.record#
                AND de.dochdrkey=d.record#
                AND dec.whsekey is not null
                AND i.itemtype in ('I','K','SK')
                AND d.whencreated >= to_date(:2, 'MM/DD/YYYY')
           ";

            $query[] = GetMyCompany();
            $query[] = $dateToStartReadingRecords;
            $query   = PrepINClauseStmt($query, $itemGroup, ' and dec.itemkey ');

            //  *************************************************************
            //  DO THE QUERY
            //  *************************************************************
            $result = QueryResult($query);
            if ($result === false) {
                return false;
            }

            $companyOpenDate = GetCompanyOpenDate();

            //  *************************************************************
            //  ADD THE RESULTS TO THE RETURNED VALUE
            //
            //  Remember we're making two passes: one for docentrycost records and one for
            //  docentrycostkits.  The kits are the PARTS, not the main item being assembled/dis-assembled.
            //
            //  Initialize some values here, rather than later, because we want to be sure they are there
            //  when we refer to them.  For example, when looking at record N, we may find it refers to
            //  record N+M, and so we want N+M's values to be initialized.....
            //  *************************************************************
            foreach ($result as $row) {

                //  *************************************************************
                //  INIT SOME VALUES
                //  *************************************************************
                $row['NOTES'] = "";
                $row['STATE'] = self::GOOD;
                $row["NOGLCHANGES"] = false; // assume
                $row["CLOSED"]      = false; // ditto

                // opendate = startDatePerLocation for entity companies, GetCompanyOpenDate() for non-entity
                // select the max of openDate or fixdate
                $openDate   = $this->startDatePerLocation[$row['LOCATIONKEY']] ?? $companyOpenDate;
                $openPeriod = (MyCompareDate($openDate, $this->fixdate) > 0) ? $openDate : $this->fixdate;

                // is this line from a closed batch?
                // that is, the date is before the open period, AND the batch is not CLOSED
                // (so the date can be fine but someone may have closed the batch)
                // failsafe: if we try to update the batch and it isn't right, the batch code will stop us.
                $dateCompare = MyCompareDate($row['DOCDATE'], $openPeriod);
                if (($dateCompare < 0)
                   || isset($this->closedBatches[ $row['PRRECORDKEY'] ])) {
                    if ($this->reboot == false) {
                        $row['STATE'] = self::CLOSED;
                        $row["CLOSED"] = true;   // is the prrecord in a batch that is closed?
                    }
                    $row["NOGLCHANGES"] = true;
                    // for escalations, determine if the problem is the PERIOD CLOSED, or BATCH CLOSED.
                    if ($dateCompare < 0) {
                        $this->addToNote($row['NOTES'], "Before open period of $openDate");
                    } else {
                        $this->addToNote($row['NOTES'], "GL Batch is closed, but period opened on $openDate");
                    }
                }

                // I'd like to know when the txn was ENTERED; is that different than the as-of date?
                $row['ENTERED_DATE'] = $row['DOCDATE'];
                if (isset($row['AUWHENCREATED']) && ($row['AUWHENCREATED'] != '')) {
                    $row['ENTERED_DATE'] = $row['AUWHENCREATED'];
                }

                if ($row['ITEM'] != $row['COMP']) {
                    $this->addToNote($row['NOTES'], _("Part of kit ") . $row['ITEM']);
                }

                //  *************************************************************
                //  FIGURE OUT IF THERE ARE DISASSEMBLY RECORDS FOR THE ASSEMBLIES (There sometimes are, sometimes aren't!)
                //  *************************************************************
                if ($dec == "docentrycostkits") {
                    $this->kitsByWarehouseItem[$row['WAREHOUSEKEY']][$row['COMP']] = true;

                    $row['DOCID'] .= _(' (Part)'); // This is not the kit itself, but a PART of the kit
                    $row['DECREC'] = -$row['DECREC'];  // make negative so we don't overlap number spaces
                    if (($row['INOUT'] !== 'I') && (isset($this->disassemblies[ $row['DEREC'] ]))) {   // was this build UN-BUILT (Disassembled)? (index is build docentry)

                        $this->addToNote($row['NOTES'], _("This BUILD was Disassembled on ") . $this->disassemblies[ $row['DEREC'] ]['DISASEMBLE_DATE']);
                        $this->disassemblies[ $row['DEREC'] ]['BUILT_ON'] = $row['DOCDATE'];
                    }
                }
                $rtn[] = $row;
            }
            $dec = "docentrycostkits";  // FOR SECOND PASS, GET THE RECORDS FROM THE KITS
            $sysgen = "'F' as systemgenerated"; // not avail for kits
            $adjdocentrycostkey = "";
            $docentrycostkitkey = "docentrycostkitkey,";
        }

        // now that we have all the records, sort into order
        usort($rtn, function($a,$b) {
            // if stockable kits, put them after everything else, including kits-as-parts
            $orderA = $this->invCostToolHelper->stockableKitsSortOrder[$a['COMP']] ?? 0;
            $orderB = $this->invCostToolHelper->stockableKitsSortOrder[$b['COMP']] ?? 0;
            if ($orderA === $orderB) {
                return compareDocDate($a, $b);  // most-common case: orders are identical (usually 0)
            }
            return ($orderA > $orderB) ? +1 : -1;   // A is a Kit, B a component
        });

        //  *************************************************************
        // now build a record-to-key index
        // and merge in activity data
        //  *************************************************************
        $deRec = 0;
        $priorKey = -1;
        $item_key = null;
        $warehouse_key = null;
        $qoh = 0;
        $valueQoh = 0;
        $itemid = '';
        $adjustmentRows = [];
        $allDeRecCosts  = [];

        foreach ($rtn as $key => &$row) {

            $itemOrWarehouseChanged = (($row['COMP'] != $item_key) || ($row['WAREHOUSEKEY'] != $warehouse_key));
            if ($itemOrWarehouseChanged) {
                $item_key       = $row['COMP'];
                $warehouse_key  = $row['WAREHOUSEKEY'];
                $qoh            = $this->beginning_costs[ $item_key ][ $warehouse_key ][1] ?? 0;  // 1 is QOH
                $valueQoh       = $this->beginning_costs[ $item_key ][ $warehouse_key ][0] ?? 0;  // 0 is QOH with value
            }

            $updinv             = $row['AFFECTS_INVENTORY'];
            $affectsQuantity    = (($updinv == 'Q') || ($updinv == 'QV'));
            $affectsValue       = (($updinv == 'V') || ($updinv == 'QV'));
            $systemGenerated    = ($row['SYSTEMGENERATED'] ?? 'F') == 'T';

            // note: normally the QOH numbers are computed much later, but I need them here for the
            //       cost history table.  So, compute them quickly (and save them) here.
            $row['RUNNING_QTY'] = $qoh; // the saved qoh is from BEFORE this transaction had effect (the QOH when this txn was evaluated)
            if ($affectsQuantity) {
                // quantity has already been made negative if outbound
                $qoh = ibcadd($qoh, $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true );
                if (ibccomp($qoh, '0', ItemManager::AVERAGE_COST_DECIMALS) < 0) {
                    $this->negQtyFound++;   // eeek!   Gone negative!
                    if ($row['STATE'] === self::GOOD) {
                        $row['STATE'] =   self::NEGQTY;
                    }
                }
            }
            $row['RUNNING_QTY_VALUE'] = $valueQoh;
            if ($affectsValue && !$systemGenerated) {   // system-generated value layers are placeholders; the subsequent invoice will have quantity too
                $valueQoh = ibcadd($valueQoh, $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true );
            }

            //  *************************************************************
            //  BUILD DECREC-TO-INDEX KEY FOR FAST FINDING OF DECRECS
            //  *************************************************************
            $this->lineItemsByDecRec[ $row['DECREC'] ] = $key;  // which is the KEY into the returned array. (and docentrycostKITS records have a negative DECREC here so as to not conflict)
            $this->lineItemsByDeRec[  $row['DEREC'] ]  = $key;  // get the LAST record with this docentry record
            $this->lineItemsByDRec[   $row['DREC'] ]   = $key;  // get the LAST record with this dochdr record
            $allDeRecCosts[$row['DEREC']][]            = $key;  // temporary for work below

            //  *************************************************************
            //  MARK DISASSEMBLIES WITH WHEN THEY WERE BUILT, IF WE CAN (may not have read the assembly yet if it is a different cost type)
            //  *************************************************************
            if ($row['DECREC'] < 0) { // < 0 means it is a docentrycostkit record
                if (isset($this->disassemblies[$row['DEREF']])) {   // remember, index is the index of the BUILD
                    if (isset($this->disassemblies[$row['DEREF']]['BUILT_ON'])) {
                        $docdateOfAssembly = $this->disassemblies[$row['DEREF']]['BUILT_ON'];
                        $this->addToNote($rtn[$key]['NOTES'], _("This was Built on ") . $docdateOfAssembly);
                    }
                }
            }

            // If we're on to a new line item (i.e. not splits), then mark the prior entry as the last one.
            if ((($row['DEREC'] != $deRec) || ($row['COMP'] != $itemid)) && ($priorKey >= 0)) {
                if (isset($this->deglresolveAmounts[$deRec][$itemid])) { // old derec,  old item
                    $rtn[ $priorKey ]['GLAMOUNT'] = $this->deglresolveAmounts[ $deRec ][$itemid]['AMOUNT'];
                }
            }
            $priorKey = $key;
            $deRec = $row['DEREC'];
            $itemid  = $row['COMP'];

            if (isset($row['ADJDOCENTRYCOSTKEY']) && ($row['ADJDOCENTRYCOSTKEY'] != 0)) {
                $adjustmentRows[] = $key;   // so we can fix these up
            }
        }
        // last entry:
        if (($priorKey >= 0)) {
            if (isset($this->deglresolveAmounts[$deRec][$itemid])) {
                $rtn[$priorKey]['GLAMOUNT'] = $this->deglresolveAmounts[$deRec][$itemid]['AMOUNT'];
            }
        }

        // for adjustments, identify any targets and let them know they were adjusted....
        foreach ($adjustmentRows as $key) {
            $adjCostEntrySource          = $this->findDocEntryCost( $rtn[$key]['ADJDOCENTRYCOSTKEY'] );
            if (($adjCostEntrySource >= 0) && isset($rtn[ $adjCostEntrySource ])) {   // found the adjusted transaction
                $adjSource = $rtn[$adjCostEntrySource];
                $rtn[$adjCostEntrySource]['ADJUSTED_BY'][] = $key;
                $this->addToNote($rtn[$key]['NOTES'], "Adjustment to " . $this->identify( $adjSource) . ", Adj DEC:" . $adjSource['DECREC']);

                // Does the adjusted entry have a source?
                // example: a warehouse transfer IN is adjusted, so does it have a corresponding warehouse transfer OUT???
                if (isset($adjSource['DEREF'])) {
                    // we may be looking at a warehouse transfer IN that has a source_doclinekey of the OUT
                    // mark the OUT saying the IN has an adjustment
                    // we don't know which source layer to mark, so mark them all as 'likely an adjustment'
                    $costsForDe = $allDeRecCosts[$adjSource['DEREF']] ?? [];
                    foreach ($costsForDe as $keyOfSource) {
                        // usually one adjustment adjusts one docentrycost, so this list will usually have
                        // one-per-de.  But tracking can change the numbers....
                        $rtn[$keyOfSource]['TARGET_ADJUSTED'][$adjSource['DECREC']] = $adjSource['DEREC'];   // so we know
                    }
                }
            } else {
                $this->addToNote($rtn[$key]['NOTES'], "Adjusted record not in this list or warehouse" );
            }
        }

        return $rtn;
    }


    /**
     *
     *  Fetch the line items again, but return very small amounts of info; specifically things the embedded sql fix routine will change.....
     *
     * @param string  $item         The 'from' item name without the '--description' part; may be empty meaning 'all items'
     * @param string  $warehouse    The optional warehouse name; empty means 'all warehouses'
     * @param string  $ason         The date to gether data from; empty means 'from the earliest date'
     *
     * @return InvCache|bool
     */
    private function reFetchPartialItemLines( $item, $warehouse, $ason )
    {
        $rtn      = new InvCache();

        $query    = [];
        $query[0] = "
            select
                d.record# AS drec,
                de.record# AS derec,
                dec.record# AS decrec,
                dec.docentrycostkey AS decref,
                decode(dec.in_out, 'I', 1, -1) * dec.quantity AS quantity,
                dec.cost as COGS,
                dec.qtyleft,
                dec.unitcost,
                dec.itemkey as comp,
                de.cost as DECOST,
                dec.in_out,
                de.basecurr,
                dec.sale_pur_trans as spi,
                0 as docentrycostkitkey,
                dec.contributedcost,
                'docentrycost' as SOURCE -- so we know if this is a kit part or not
            from
                dochdrmst d, docentrymst de, docentrycost dec
            where
                d.cny#=:1
                AND de.cny#=d.cny#
                AND dec.cny#=de.cny#
                AND dec.docentrykey=de.record#
                AND de.dochdrkey=d.record#
                AND dec.itemkey = :2
                AND dec.whsekey = :3
                AND d.whencreated >= TO_DATE(:4,'mm/dd/yyyy')
        UNION ALL
            select
                d.record# AS drec,
                de.record# AS derec,
                dec.record# AS decrec,
                dec.docentrycostkey AS decref,
                decode(dec.in_out, 'I', 1, -1) * dec.quantity AS quantity,
                dec.cost as COGS,
                dec.qtyleft,
                dec.unitcost,
                dec.itemkey as comp,
                de.cost as DECOST,
                dec.in_out,
                de.basecurr,
                'I' as spi,
                docentrycostkitkey,
                0 as contributedcost,
                'docentrycostkits' as SOURCE -- so we know if this is a kit part or not
            from
                dochdrmst d, docentrymst de, docentrycostkits dec
            where
                d.cny#=:1
                AND de.cny#=d.cny#
                AND dec.cny#=de.cny#
                AND dec.docentrykey=de.record#
                AND de.dochdrkey=d.record#
                AND dec.itemkey = :2
                AND dec.whsekey = :3
                AND d.whencreated >= TO_DATE(:4,'mm/dd/yyyy')
            ";

        $query[] = GetMyCompany();
        $query[] = $item;
        $query[] = $warehouse;
        $query[] = $ason;

        $ok = $rtn->QueryResult($query, function($row) {
            if ($row['SOURCE'] === "docentrycostkits") {
                $row['DECREC'] = -$row['DECREC'];  // make negative so we don't overlap number spaces (we do this above too)
            }
            return $row;
        });

        if ($ok === false) {
            return false;
        }

        return $rtn;
    }


    /**
     * Answers the musical question: "Is this row a real DocEntryCost record, or is it a fake from a Stockable Kit?"
     *
     * @param array $line
     *
     * @return bool
     */
    private function realDecRec($line)
    {
        return ($line['SOURCE'] == "docentrycost"); // not docentrycostkits
    }


    /**
     *  fiundUpdates - what are the differences between what we HAD and what was CHANGED?
     *
     * @param array     $lineItems          all the lines we're updating costs for
     * @param InvCache  $updates            the possibly changed line items for the given item/wh/date
     * @param bool      $fixTheData         is this an update or just an analyze?
     *
     * @return bool
     */
    private function findUpdates(&$lineItems, $updates, $fixTheData) {

        $updated = false;
        $listing = false;

        $deRecCosts = [];

        foreach ($updates as $updateIndex => $update) {
            $decrec = $update['DECREC'];
            $derec  = $update['DEREC'];
            $item   = $update['COMP'];
            $spiOut = ($update['SPI'] === 'I') && ($update['IN_OUT'] === 'O');
            $currency = $update['BASECURR'];

            // Does the doc entry cost match the sum(doc entry cost costs)?
            // kits are dealt with separately; here we want outbound (sales, etc)
            // and, so far, the requirement is for outbound inventory transactions only.
            // we could loosen that up in the future if need be
            if ($fixTheData && $spiOut && $this->realDecRec($update)) {

                // What is the current DocEntry cost, and also we add up the
                // DocEntryCost costs so we can see if they changed.
                if (! isset($deRecCosts[$derec])) {
                    $deRecCosts[$derec]['DECOST'] = $update['DECOST'] ?? 0;
                    $deRecCosts[$derec]['COGS'] = 0;
                }
                $deRecCosts[$derec]['COGS'] = ibcadd($deRecCosts[$derec]['COGS'], $update['COGS'] ?? 0, ItemManager::AVERAGE_COST_DECIMALS, true);
            }

            $existingRec = $this->lineItemsByDecRec[ $decrec ] ?? -1;
            if ($existingRec >= 0) {
                $lineItems[$existingRec]['FOUND'] = true;   // so we know this record still exists

                // for transfers and such, remember the base currencies so we know the amounts SHOULD be different
                if (($currency != 'USD') && ($update['SPI'] === 'I')) {
                    $this->addToNote( $lineItems[$existingRec]['NOTES'], "($currency)");
                }

                $line          = $lineItems[$existingRec];
                $needsFixes    = false;
                $fixMeansError = false; // if we fixed it, was that an error?
                $fields = ['DECREF', 'QUANTITY', 'COGS', 'QTYLEFT', 'UNITCOST', 'DOCENTRYCOSTKITKEY' ];
                foreach ($fields as $field) {
                    if ($line[$field] != $update[$field]) {
                        $needsFixes = true;
                        $updated    = true;
                        $listing    = true;
                        $fixMeansError = ($field != 'QTYLEFT');  // not really a 'fix' in the usual sense

                        if (($field == 'DECREF') || ($field == 'DOCENTRYCOSTKITKEY')) {
                            if (($line[$field] == '') || ($line[$field] == 0)) {
                                $b4 = "NONE";
                            } else {
                                $b4 = "{$line[$field]} (" . $this->identifyByDecRef($lineItems,$line[$field]) . ")";
                                // include the source in the listing
                                if ($listing) {
                                    $decRefKey   = $this->findDocEntryCost( $line[$field] );
                                    if ($decRefKey >= 0) {
                                        $this->reportOnThisLine->set($decRefKey, true);
                                    }
                                }
                            }
                            if (($update[$field] == '') || ($update[$field] == 0)) {
                                $after = "NONE";
                            } else {
                                $after = "{$update[$field]} (" . $this->identifyByDecRef($lineItems,$update[$field]) . ")";
                                // include the source in the listing
                                if ($listing) {
                                    $decRefKey   = $this->findDocEntryCost( $update[$field] );
                                    if ($decRefKey >= 0) {
                                        $this->reportOnThisLine->set($decRefKey, true);
                                    }
                                }
                            }
                            $this->addToNote( $lineItems[$existingRec]['NOTES'], "Field $field changed from $b4 to $after");
                        } else {
                            $this->addToNote( $lineItems[$existingRec]['NOTES'], "Field $field changed from {$line[$field]} to {$update[$field]}");
                        }
                    }
                }

                // if we are NOT listing all records on the CSV output, record the 'important'
                // lines.  In this case, we want any lines that change, and then the ones that come AFTER them.
                if ($listing) {
                    $this->reportOnThisLine->set($existingRec, true);
                }

                // Does this transaction have COGS?
                if (isset($this->deglresolveAmounts[$derec][$item])) {

                    $amt     = $this->getAdjustedCogsAmount($lineItems, $existingRec,
                                $update['COGS'] ?? '0', $update['CONTRIBUTEDCOST'] ?? '0');

                    $this->deglresolveAmounts[$derec][$item]['CURRENT_COST'] += $amt; // may go into the gl
                    $this->deglresolveAmounts[$derec][$item]['COST_UPDATED']  = true; // saw a change
                }

                if ($needsFixes) {
                    $fixes = array(
                        'DECREF'                => $update['DECREF'],
                        'QUANTITY'              => $update['QUANTITY'],
                        'COGS'                  => $update['COGS'],
                        'QTYLEFT'               => $update['QTYLEFT'],
                        'UNITCOST'              => $update['UNITCOST'],
                        'DOCENTRYCOSTKITKEY'    => $update['DOCENTRYCOSTKITKEY'],
                    );
                    $lineItems[$existingRec]['FIXES'] = $fixes; // something is different
                    if ($fixMeansError) {
                        $lineItems[$existingRec]['STATE'] = (($line['NOGLCHANGES'] === true) ? self::CLOSEDBAD : self::BAD);
                        $this->errorsFound++;
                        if ($fixTheData) {
                            $lineItems[$existingRec]['STATE'] = (($line['NOGLCHANGES'] === true) ? self::FIXED_NOT_COGS : self::FIXED);
                            $this->errorsFixed++;
                        }
                    }
                }

            } else {
                $existingRec = $this->lineItemsByDeRec[ $derec ] ?? -1;    // get ONE line to represent the group
                if ($existingRec >= 0) {
                    if (isset($this->deglresolveAmounts[$derec][$item])) { // affects COGS

                        $amt     = $this->getAdjustedCogsAmount($lineItems, $existingRec,
                            $update['COGS'] ?? '0', $update['CONTRIBUTEDCOST'] ?? '0');

                        $this->deglresolveAmounts[$derec][$item]['CURRENT_COST'] += $amt; // may go into the gl
                        $this->deglresolveAmounts[$derec][$item]['COST_UPDATED']  = true; // saw a change
                    }
                    $lineItems[$existingRec]['NEW_DECS'][] = $update;   // get the whole thing; this won't work for kit parts :-(
                    $this->lineItemsByDecRec[ $decrec ] = $existingRec; // so we can find it for display purposes
                    // $this->reportOnThisLine->set($existingRec, true); // don't bother with ADDED if not verbose mode
                } else {
                    logFL("DEBUG: Can't find parent of new record ($updateIndex) for item $item: " . var_export($update,true));
                }
                $updated    = true; // one way or another; we lost the original ....
            }
        }

        // Are there docentry records where the COST field does not match the sum(doc entry cost)'s COST/COGS field?
        // (often they start out NULL)
        if ($fixTheData) {
            $fixDocEntry = [];
            foreach ($deRecCosts as $deRecordNumber => $fields) {
                if (ibccomp($fields['DECOST'], $fields['COGS'], ItemManager::AVERAGE_COST_DECIMALS) !== 0) {
                    $fixDocEntry[] = $deRecordNumber;
                }
            }
            if ( ! empty($fixDocEntry)) {
                if ($this->invCostToolHelper->updateDocEntrysCostFieldToMatchDocEntryCost($fixDocEntry) === true) {
                    $updated    = true; // so we commit the changes
                }
            }
        }
        return $updated;
    }


    /**
     *      get Adjusted Cogs Amount - try to get the CORRECT GL amount for this item.
     *         Inbound Inventory transactions may have 'COGS', but they are not really COGS, but the GL account.
     *
     *  Landed Costs will make adjustments to things, and we want to separate out the ADJUSTMENTS from
     *  true changes to the GL.
     *
     * @param array     $lineItems          All line items for this costing type
     * @param int       $existingRec        The line index we're currently playing with
     * @param string    $amt                The COGS amount
     * @param string    $contributedCost    The not-adjusted, or 'contributed' cost.
     *
     * @return string                       The (perhaps adjusted) COGS amount
     */
    private function getAdjustedCogsAmount(&$lineItems, $existingRec, $amt, $contributedCost)
    {
        $line = $lineItems[$existingRec];
        $updatesQV = ($this->docPar($line['DOCPARKEY'],'UPDINV') == 'T');
        if ($updatesQV && ($line['INOUT'] == 'I') && ($this->docPar($line['DOCPARKEY'],'SPI') == 'I')) {
            if (isset($line['ADJUSTED_BY'])) {
                $baseCost = $contributedCost;
                // Php 8 and 'gaurd rails'....
                if (($baseCost !== '') && ($baseCost !== 0) && ($baseCost !== '0')) {
                    // is it different than amount to 2 places??
                    if (ibccomp($amt, $baseCost, 2) != 0) {
                        $amt = $baseCost;
                        $this->addToNote($lineItems[$existingRec]['NOTES'], "Unadjusted cost of $baseCost used for GL");
                    } else {
                        $this->addToNote($lineItems[$existingRec]['NOTES'], "(Unadjusted?)");
                    }
                }
            }
        }
        return $amt;
    }


    /**
     *  see what SQL embedded routines chante - what do the costing routines do to our data?
     *
     * @param array $lineItems              the original line items
     * @param bool $fixTheData              are we updating the disk?
     * @param string $costMethod            'A', 'S', 'L', or 'F'
     *
     */
    private function seeWhatSqlEmbeddedRoutinesChange(&$lineItems, $fixTheData, $costMethod)
    {

        //  ****************************************************
        //  HELPERS TO FIND CHANGES AND UPDATE THE COST HISTORY
        //
        //  Do this ONCE after an entire item is processed,
        //  so that Warehouse Transfers transfering FROM
        //  warehouse Z to warehouse A get A examined for changes
        //  *****************************************************

        // This updates the cost change history after we have checked for any updates....
        /** @var callable $updateCostChangeHistory */
        $updateCostChangeHistory = function(&$lineItems, $key, $item_key) {

            // inbound?
            $theLine         = $lineItems[$key];
            $inbound         = ($theLine['INOUT'] == 'I');
            $updinv          = $this->docPar($theLine['DOCPARKEY'],'UPDINV');
            $affectsValue    = (($updinv == 'V') || ($updinv == 'T'));
            if ($inbound && $affectsValue) {
                $this->invCostToolHelper->noticeThisInboundLine($key, $theLine);
            }
            // COGS-affecting?  Might include sales returns, which are inbound
            if (isset($this->deglresolveAmounts[$theLine['DEREC']][$item_key])) {
                // was it changed?
                if (isset($theLine['FIXES'])) {
                    $this->invCostToolHelper->thisLineChanged($key, $theLine, false);   // record was updated
                }
                if (isset($theLine['NEW_DECS'])) {
                    $this->invCostToolHelper->thisLineChanged($key, $theLine, true);     // record(s) were added
                }
                if (isset($theLine['FOUND'])) {
                    if ( ! isset($theLine['FIXES'])) {
                        $this->invCostToolHelper->thisLineWasSeen($key, $theLine);  // not updated, not deleted, and is not new
                    }
                } else {
                    $this->invCostToolHelper->thisLineWasDeleted($key, $theLine);                  // nope, deleted
                }
            }
        };

        // This checks for changes
        /** @var callable $checkForChanges */
        $checkForChanges = function(&$lineItems, &$checkTheseForChanges, $fixTheData) use ($updateCostChangeHistory) {
            $changed = false;

            // If any, there is ONE for each item/warehouse pair
            foreach ($checkTheseForChanges as $row) {   // MAY BE EMPTY
                $item_key       = $row['ITEM'];
                $warehouse_key  = $row['WAREHOUSE'];
                $startDate      = $row['STARTDATE'];
                $startKey       = $row['STARTKEY'];
                $endKey         = $row['ENDKEY'];

                // then signal the start of a new item warehouse
                // Note: The 'starting date' available from this routine is for the first changed inbound-value
                //      transaction, or the earliest change to standard costs.  For cost methods other than
                //      standard costs, sales may be affected if their SOURCE is the purchase, even if the source
                //      comes before the purchase (in negative inventory cases)
                $this->invCostToolHelper->startHandlingNewItemWarehouse($item_key,$warehouse_key);


                // Go back and get the data for this item/warehouse combo, starting on the date we might have changed stuff
                $updates = $this->reFetchPartialItemLines($item_key, $warehouse_key, $startDate);
                if ($updates === false) {
                    break;
                }
                // Did the data change?  Record the changes for reporting, and tell us if there were any changes
                if ($this->findUpdates($lineItems, $updates, $fixTheData)) {
                    $changed = true;
                }
                unset($updates);    // save the ram

                // Now go back and update the cost change history records,
                // and mark new-since-last-run as needing to be printed
                $lastRun        = $this->invCostToolHelper->costingLastRanOn($item_key, $warehouse_key);
                while ($startKey < $endKey) {
                    if ($fixTheData) {
                        $updateCostChangeHistory($lineItems, $startKey, $item_key);
                    }
                    if (($lastRun !== false) && (MyCompareDate($lineItems[$startKey]['WHENMODIFIED'], $lastRun) >= 0)) {
                        $this->reportOnThisLine->set($startKey, true);
                    }
                    $startKey++;
                }

                // finally, finish off the item/warehouse that was being processed.
                $docPar = function($record) {
                    return $this->docPar($record);
                };
                $this->invCostToolHelper->doneHandlingItemWarehouse($lineItems,
                    $docPar, $this->lineItemsByDRec, $this->lineItemsByDecRec, $this->deglresolveAmounts,
                    $this->_health_run_id,
                    $fixTheData);

            }

            // commit?
            if ($fixTheData && $changed) {
                // Commit it in case the next go-around causes errors.
                // then start a new transaction for the next pass (or caller)
                // idea is not to commit a bazillion times, but just whenever a real change happens
                $this->_QM->commitTrx(self::TXN_SOURCE);
                $this->_QM->beginTrx(self::TXN_SOURCE);
            }
            $checkTheseForChanges = [];
        };

        /** @var callable $findEndOfItemWarehouse */
        $findEndOfItemWarehouse = function(&$lineItems, $lineItemsCount, $key, $item_key, $warehouse_key) {
            // TODO: could be faster!
            $endKey = $key;
            while ($endKey < $lineItemsCount) {
                $theLine = $lineItems[$endKey];
                $itemOrWarehouseChanged = (($theLine['COMP'] != $item_key) || ($theLine['WAREHOUSEKEY'] != $warehouse_key));
                if ($itemOrWarehouseChanged) {
                    break;
                }
                $endKey++;
            }
            return $endKey; // actually, one PAST the end
        };



        //  *************************************
        //  MAIN CODE
        //  *************************************

        $checkTheseForChanges = [];
        $lineItemsCount       = count($lineItems);
        $source               = self::TXN_SOURCE;
        $sql                  = array();

        // param 1: cny#, param 2 warehouse, param 3 item, param 4 date
        $sql[0] = " BEGIN 
                        invcost_utils.fixcostingfromdate_part_n_of_3(:1, :2, :3, :4, :5, :6);
                    END;";

        $sql[1] = GetMyCompany();

        $item_key               = NULL;
        $warehouse_key          = NULL;
        $needAFix               = false;
        $errorOnThisIW          = false;
        $errorCheckpoint        = Globals::$g->gErr->Checkpoint();
        $errorDate              = '';
        $startingDate           = $this->fixdate;   // so the inspector doesn't notice that it MIGHT be un-initialized

        // Call the sql routine ONCE per item/warehouse combo.
        // Any date earlier than the first txn date will do.
        foreach ($lineItems as $key => $line) {

            $itemChanged            = ($line['COMP'] != $item_key);
            $itemOrWarehouseChanged = ($itemChanged || ($line['WAREHOUSEKEY'] != $warehouse_key));
            $item_key               = $line['COMP'];
            $warehouse_key          = $line['WAREHOUSEKEY'];

            if ($itemChanged) {
                // see if the prior item had updates: (ok if first time)
                $checkForChanges($lineItems, $checkTheseForChanges, $fixTheData);
            }

            if ($itemOrWarehouseChanged) {
                $needAFix       = true;
                $errorOnThisIW  = false;
                $startingDate   = $this->invCostToolHelper->startDateForItemWarehouse($item_key, $warehouse_key);
            }

            if ($needAFix) {

                // **** Do we start costing here? ****

                // CLOSED means that (A) we're paying attention to closed periods, and (B) this txn is in one.  So, ignore!
                $startHere = ($line['CLOSED'] !== true);
                if ($startHere) {
                    // ok, we're not in a closed period or not honoring closed periods.
                    // Is the doc date on or after the starting date?
                    $startHere = (MyCompareDate($line['DOCDATE'], $startingDate) >= 0);

                    if ($startHere == false) {
                        // not yet.  But wait!  One more test: is the SOURCE of this transaction inside the starting date?
                        $decref     = $line['DECREF'] ?? 0;
                        $whichEntry = ($decref     >  0) ? $this->lineItemsByDecRec[ $decref ] : -1;
                        $startHere  = ($whichEntry >= 0) && (MyCompareDate($lineItems[$whichEntry]['DOCDATE'], $startingDate) >= 0);
                    }
                }

                if ($startHere) {
                    $ok = true;
                    if ($this->updateBuildKits && ($line['ITEMTYPE'] == 'SK')) {
                        // adjust stockable kits BEORE we run the costing code, to affect subsequent sales.
                        $ok   = $this->invCostToolHelper->adjustStockableKitsFromTransactionStream($lineItems, $key);
                        $line = $lineItems[$key];
                    }
                    $trouble = ! $ok;
                    if ($ok) {
                        $needAFix = false;
                        $sql[2] = $warehouse_key;
                        $sql[3] = $item_key;
                        $sql[4] = $line['DOCDATE'];
                        $sql[5] = $costMethod;
                        $sql[6] = 1;    // which part: 1..3, in order!
                        $ok     = $ok && ExecStmt($sql);    // call the embedded procedure one step at a time to help avoid CPU timeouts
                        $sql[6] = 2;    // part two
                        $ok     = $ok && ExecStmt($sql);
                        $sql[6] = 3;    // part three
                        $ok     = $ok && ExecStmt($sql);

                        $trouble = (!$ok) || (Globals::$g->gErr->Checkpoint() != $errorCheckpoint);
                    }

                    if ($trouble) {
                        logFL("*** DEBUG: Exec failed on $item_key / $warehouse_key {$sql[4]}!");
                        // are there error messaages?
                        if (! Globals::$g->gErr->isEmpty()) {
                            $errors = Globals::$g->gErr->myToString(true, 20 );
                            $lineItems[$key]['NOTES'] = self::FATAL_ERROR . ":\n" . $errors;
                            $lineItems[$key]['STATE'] = self::BAD;
                            $this->errorsFound++;
                            $errorOnThisIW = true;
                            $errorDate     = $line['DOCDATE'];
                            Globals::$g->gErr->Restore($errorCheckpoint);   // reset the error table back to what it was before we called this.
                            logFL("*** DEBUG: Exec error: $errors");
                        }
                        // if we are updating, toss this change and then start a new transaction for the next item/warehouse combo
                        if ($fixTheData) {
                            $this->_QM->rollbackTrx($source);   // roll back this one
                            $this->_QM->beginTrx($source);      // and start a new one for next time
                        }
                    }

                    // Note: even though we may have failed, and rolled back, the above changes, we'll press ahead
                    //       on warehouse transfers and see if anything changed there.  This way, if we timeout
                    //       in the costing code, we still can fix any broken transfers
                    // hopefully not much to do!
                    $wtChanged = false;
                    if ($this->updateTransfers) {
                        // adjust transfers AFTER we run the costing code, becase the OUT side may have changed.
                        // TODO: how serious is any error?
                        $this->invCostToolHelper->adjustTransfers($lineItems, $key, $costMethod, $wtChanged);
                    }

                    // if costing ran ok, OR there were transfers adjusted, commit the transaction.
                    if ( $fixTheData && ((! $trouble) || $wtChanged)) {
                        // Commit it in case the next go-around causes errors.
                        // then start a new transaction for the next pass (or caller)
                        // idea is not to commit a bazillion times, but just whenever a real change happens
                        $this->_QM->commitTrx($source);
                        $this->_QM->beginTrx($source);
                    }

                    // Defer checking for changes until we see all warehouses for this item
                    // so that warehouse transfers changing a different warehouse get updated properly
                    // Escalation fix: the doc date is the transaction we found that has changed,
                    //          but its change might trigger earlier documents to change, such as when
                    //          a purchase is added but the item/wh was in negative inventory at the time.
                    //          So, more work, but more accurate
                    $checkTheseForChanges[] = ['ITEM' => $item_key, 'WAREHOUSE' => $warehouse_key,
                                               'STARTDATE' => $startingDate, /* $line['DOCDATE'] */
                                               'STARTKEY' => $key,
                                               'ENDKEY' => $findEndOfItemWarehouse($lineItems, $lineItemsCount, $key, $item_key, $warehouse_key) ];
                }
            } else if ($errorOnThisIW) {
                $lineItems[$key]['NOTES'] = self::FATAL_ERROR . " ON $errorDate.";
            }
        }
        // check for last item/warehouse changes, if any
        $checkForChanges($lineItems, $checkTheseForChanges, $fixTheData);
    }


    // At this time, May 2017, a Stockable Kit BUILD puts the parts into DocEntryCostKits with the opposite direction of the part itself.
    //      i.e. the kit is inbound, the parts are outbound.  We also update the itemcosthistory and GL.
    //      but here's the thing: On a disassemble we do none of that.  So, what I want to do here is
    //      Get a list of the disassembles' source docentry #s (which is the build)
    private function getStockableKitDisassemblies()
    {
        $disassemble = DIS_KIT;
        $query = array();
        $query[0] = "
            select
                docentry.source_doclinekey AS build_derec, docentry.whencreated
            from
                docentrymst docentry, dochdrmst dochdr
            where
                docentry.cny#=:1
                AND docentry.cny# = dochdr.cny#
                AND docentry.dochdrkey = dochdr.record#
                AND dochdr.docparid = '$disassemble'
        ";
        $query[1] = GetMyCompany();
        $rows = QueryResult($query);

        $this->disassemblies = array();
        if ($rows !== false) {
            foreach ($rows as $row) {
                $this->disassemblies[$row['BUILD_DEREC']]["DISASEMBLE_DATE"] = $row['WHENCREATED'];   // note the index was the BUILD transaction
            }
        }
    }


    /**
     *      This is a helper for getDeGlResolveAmounts().  When fetching stockable kit transactions (the BUILD and
     *  DISASSEMBLE, specifically), the inbound items don't match the outbound items.  For our purposes, we want:
     *  - the kit itslef shouldn't have COGS entries (it will on a SALE or RETURN, but not on BUILD/DISASSEMBLE)
     *  - the kit PARTS should have COGS entries, so we need the PART ITEMID to match on both the DEBIT and CREDIT.
     *
     *  Here, we assume this is called:
     *  - For build/disassemble docid's
     *  - on the FIRST entry for the current docentry set and only once per docentry
     *  - the sort order has docentry first
     *
     * @param array         $deglresolves   The list of fetched deglresolves from getDeGlResolveAmounts().
     * @param int           $index          The first index into the table of resolves for this docentry
     *
     * @return bool                         keep entries or not
     */
    private function matchDeGlResolvesForKits(&$deglresolves, $index)
    {
        $row = $deglresolves[$index];
        if ( ! isset($row['DOCID'])) {
            return true;
        }
        if (in_array($row['DOCID'], [BUILD_KIT, DIS_KIT])) {    // just to be sure

            $docentry = $row['DOCENTRYKEY'];    // we will examine only these

            // build kits all credits should be for components
            if ($row['DOCID'] == BUILD_KIT) {
                $trType = -1;
            } else {
                $trType = 1;
            }

            // Loop through the rows for this docentry and collect both the items needing a match,
            // and the KIT entries that we will overwrite.....
            $ok = true;
            $componentsNeedingMatch = [];
            $kitEntriesNeedingMatch = [];
            while (isset($deglresolves[$index]) && ($docentry == $deglresolves[$index]['DOCENTRYKEY'])) {
                $row = $deglresolves[$index];
                if ($row['TR_TYPE'] == $trType) {
                    $componentsNeedingMatch[] = $index;
                    // it is ok for the kit itself to have a null itemdimkey, but NOT for the parts...
                    // note: as of 4/2020 we don't yet fetch the null itemdimkey values
                    if ($row['NULLENTRY'] == 'T') {
                        $ok = false;
                    }
                } else {
                    $kitEntriesNeedingMatch[] = $index;
                }
                $index++;
            }

            // A bit of sanity checking:
            $c1 = count($componentsNeedingMatch);
            $c2 = count($kitEntriesNeedingMatch);
            if ($c1 != $c2) {
                logFL("[DEBUG] KITS: DeGlResolves for COMPONENTS ($c1) don't match DeGlResolves for KITS ($c2)");
                $ok = false;
            }
            if ( ! $ok) {
                foreach ($componentsNeedingMatch as $i) {
                    $deglresolves[$i]['DONTUSE'] = true;
                }
                foreach ($kitEntriesNeedingMatch as $i) {
                    $deglresolves[$i]['DONTUSE'] = true;
                }
                return false;
            }

            // Now lets try to match the components with the kit entries.
            // All we really care about is that the deglresolve's ITEMID matches the COMPONENT, not the KIT
            // 1) Match on amount if you can
            // Note: sometimes I've seen that the KIT deglresolve entries have some random dollar amount that is NOT
            //      the same as the parts.  That's because, i think, that there are N deglresolve entries referring
            //      to a single GLENTRY (the kit, not the part glentry).  The glentries are correct, and I think the
            //      kit entry should be the sum, but it isn't always, due to some error somewhere.
            foreach ($componentsNeedingMatch as $compomemtIndex => $component) {
                foreach ($kitEntriesNeedingMatch as $kitEntryIndex => $kitEntry) {
                    if (($kitEntry >= 0) && ($deglresolves[$kitEntry]['AMOUNT'] == $deglresolves[$component]['AMOUNT'])) {
                        $deglresolves[$kitEntry]['ITEMID']  = $deglresolves[$component]['ITEMID'];
                        $kitEntriesNeedingMatch[$kitEntryIndex]  = -1; // so we don't use it on the next pass
                        $componentsNeedingMatch[$compomemtIndex] = -1; // nor this
                        break;
                    }
                }
            }
            // 2) take any remaining if you can't match amount
            foreach ($componentsNeedingMatch as $compomemtIndex => $component) {
                if ($component >= 0) {
                    foreach ($kitEntriesNeedingMatch as $kitEntryIndex => $kitEntry) {
                        if ($kitEntry >= 0) {
                            $deglresolves[$kitEntry]['ITEMID'] = $deglresolves[$component]['ITEMID'];
                            $deglresolves[$kitEntry]['AMOUNT'] = $deglresolves[$component]['AMOUNT'];   // they didn't match before, now they do (component is right)
                            $kitEntriesNeedingMatch[$kitEntryIndex]  = -1; // so we don't use it on the next pass
                            $componentsNeedingMatch[$compomemtIndex] = -1; // not really needed, but symetrical
                            break;
                        }
                    }
                }
            }
        }
        return true;
    }


    /**
     *      Fetch the current COGS postings for all transactions.
     * Note: there can be a LOT of these and it can be SLOOOWWWW to get them....
     *
     * @param string $dateToStartReadingRecords  the date to start reading
     */
    private function getDeGlResolveAmounts($dateToStartReadingRecords)
    {
        // This is so we do not need to join to docpar (which is super slow) ...
        $purchaseTDs = [];
        foreach ($this->docparKeys as $docPar) {
            if ($docPar['SPI'] === 'P') {
                $purchaseTDs[] = $docPar['RECORD#'];
            }
        }

        // find the resolve maps in deglresolve table
        // EXCEPT those attached to purchases, which we don't change
        $query = array();
        $query[] = "
                select  a.docentrykey, a.amount, a.trx_amount, a.glentrykey, c.itemid, a.cost_adj_needed, 
                        b.batch# batchno, dh.docparid as docid, a.orig_trtype as tr_type, a.record#, 'F' as nullentry
                from    deglresolve a, glentrymst b, docentrymst de, dochdrmst dh, icitemmst c
                where       a.cny#=:1 
                        AND a.COGSPOSTING = 'T' 
                        and b.cny#=a.cny# 
                        and c.cny#=a.cny#
                        and a.glentrykey=b.record# 
                        and b.itemdimkey is not null
                        and b.itemdimkey=c.record#
                        AND de.cny#=a.cny#  
                        AND a.docentrykey=de.record#
                        AND dh.cny#=a.cny#  
                        AND dh.record#=de.dochdrkey 
                        AND dh.whencreated >= to_date(:2, 'MM/DD/YYYY') ";

        // NOTE THE SORT ORDER IS IMPORTANT FOR THE LOGIC BELOW AND FOR matchDeGlResolvesForKits(), ABOVE.
        $query[] = GetMyCompany();  // 1 - the company
        $query[] = $dateToStartReadingRecords;
        $query = PrepINClauseStmt($query, $purchaseTDs, ' and NOT docparkey ');
        $query[0] .= " ORDER BY docentrykey ";
        $deglresolves = QueryResult($query);
        if ($deglresolves === false) {
            return;
        }

        // Normalize build/disassemble kits:
        $lastKey = 0;
        foreach ($deglresolves as $index => $row) {
            // For BUILD KITS and DISASSEMBLE KITS we have the situation that the ITEM DIMENSION, and therefore
            // the ITEMID here, is different between the IN and OUT directions.  So, we can't match up the ITEMIDs as
            // we would for any other transaction type.  Fix that here:
            $key   = $row['DOCENTRYKEY'];
            if (($key != $lastKey) && in_array($row['DOCID'], [BUILD_KIT, DIS_KIT])) {
                // call this ONCE for each docentry record
                $this->matchDeGlResolvesForKits($deglresolves, (int)$index);
            }
            $lastKey  = $key;
        }

        // Now process and save the records
        $badKey = 0;
        $lastKey = 0;
        $lastKeyWasKitBuild = false;
        foreach ($deglresolves as $row) {
            $key    = $row['DOCENTRYKEY'];
            $glkey  = $row['GLENTRYKEY'];
            $item   = $row['ITEMID'];
            $amount = $row['AMOUNT'];
            if ($amount < 0) {
                $amount = 0;    // *** GUARDRAIL; GL WONT GO NEGATIVE BUT DEGLRESOLVE DID *****
            }
            $trxAmount = $row['TRX_AMOUNT'];
            if ($trxAmount < 0) {
                $trxAmount = 0;     // *** GUARDRAIL; GL WONT GO NEGATIVE BUT DEGLRESOLVE DID *****
            }

            // If something is wrong with this deglresolve, don't collect more data
            if (($key == $badKey) || isset($row['DONTUSE'])) {
                continue;           // we no longer want things from this docentrykey
            }

            // If damaged deglresolves don't have two glentrykeys (paired deglresolve records),
            //   then don't act on those records
            if (($key != $lastKey) && ($lastKey > 0)) {
                foreach ($this->deglresolveAmounts[$lastKey] as $tmpItem => $tmpRow) {
                    if ($tmpRow['GLENTRYKEY2'] == 0) {
                        if ($lastKeyWasKitBuild && ($this->fromItem != '')) {
                            logFL("[DEBUG] COGS can't be computed for kit build with item specified for docentry $lastKey, item $tmpItem, amt " . $tmpRow['AMOUNT']);
                        } else {
                            logFL("[DEBUG] Missing GLENTRY2 for docentry $lastKey, item $tmpItem:" . var_export($tmpRow, true));
                        }
                        unset($this->deglresolveAmounts[$lastKey][$tmpItem]);
                    }
                }
            }
            $lastKey            = $key;
            $lastKeyWasKitBuild = in_array($row['DOCID'], [BUILD_KIT, DIS_KIT]);

            if (isset($this->deglresolveAmounts[$key][$item])) {

                // Turns out LOTS can make several deglresolves for one docentry...
                if ($glkey == $this->deglresolveAmounts[$key][$item]['GLENTRYKEY1']) {

                    $this->deglresolveAmounts[$key][$item]['AMOUNT']          = ibcadd($this->deglresolveAmounts[$key][$item]['AMOUNT'],     $amount,    2, true);         // accumulate the amounts
                    $this->deglresolveAmounts[$key][$item]['TRX_AMOUNT']      = ibcadd($this->deglresolveAmounts[$key][$item]['TRX_AMOUNT'], $trxAmount, 2, true);
                    $this->deglresolveAmounts[$key][$item]['RECORD#1'][]      = $row['RECORD#'];
                    $this->deglresolveAmounts[$key][$item]['COUNT']++;              // another pair?

                } else if ($this->deglresolveAmounts[$key][$item]['GLENTRYKEY2'] == 0) {

                    $this->deglresolveAmounts[$key][$item]['GLENTRYKEY2'] = $glkey; // now we have both keys
                    $this->deglresolveAmounts[$key][$item]['BATCHNO2']    = $row['BATCHNO'];
                    $this->deglresolveAmounts[$key][$item]['RECORD#2'][]  = $row['RECORD#'];

                } else if (($this->deglresolveAmounts[$key][$item]['GLENTRYKEY2'] == $glkey) && ($this->deglresolveAmounts[$key][$item]['BATCHNO2'] == $row['BATCHNO'])) {

                    $this->deglresolveAmounts[$key][$item]['RECORD#2'][]  = $row['RECORD#'];

                } else {   // wait, is this ANOTHER key?
                    // if damaged data has MORE glentries (multiple deglresolves with 3+ glentrykeys), that's bad
                    logFL("**** DEBUG: DeGlResolve records for one docentry ($key) have more than two GLENTRYKEYS: " . var_export($row, true) . " on top of " . var_export($this->deglresolveAmounts[$key][$item], true));
                    $badKey = $key;
                    unset($this->deglresolveAmounts[$key][$item]);
                }
            } else {
                $this->deglresolveAmounts[$key][$item] =
                    array(
                        'AMOUNT'       => iround($amount,2),
                        'TRX_AMOUNT'   => iround($trxAmount, 2),
                        'GLENTRYKEY1'  => $glkey,
                        'BATCHNO1'     => $row['BATCHNO'],
                        'RECORD#1'     => [$row['RECORD#']],
                        'RECORD#2'     => [],
                        'GLENTRYKEY2'  => 0,
                        'COUNT'        => 1,
                        'CURRENT_COST' => 0.0,
                        'COST_UPDATED' => false,
                        'COST_ADJ_NEEDED' => $row['COST_ADJ_NEEDED']); // this is what we want the gl amounts to BE
            }
        }
    }


    /**
     *  What is the docPar information for the given record#
     *
     * @param int      $recordNo
     * @param string   $field           optional.  If omitted, the whole row is returned.
     *
     * @return mixed|string
     * @throws Exception
     */
    private function docPar($recordNo, $field = null)
    {
        static $priorRecordNo = 0;
        static $row           = [];
        // is this a new request, and not a repeat?
        if ($recordNo !== $priorRecordNo) {
            $priorRecordNo = $recordNo;
            $row           = $this->docparKeys->getByKey('RECORD#', $recordNo);
        }
        return isset($field) ? ($row[$field] ?? '') : $row;
    }


    /**
     *  Read every TD so we can refer to it....
     *
     * @return bool
     */
    private function collectDocparInfo()
    {
        $query_string = "
            select
                record#,updinv,sale_pur_trans spi, docid, description, in_out, updgl
            from
              docparmst
            where
                cny#=:1
        ";

        // Note use of InvCache....
        $this->docparKeys = new InvCache();
        $this->docparKeys->defineKey('RECORD#', true);
        $result = $this->docparKeys->QueryResult(array($query_string, GetMyCompany()), function($row) {
            $origDocId = $row['DOCID'];
            $row['ORIGINAL_DOCID'] = $origDocId;
            // $row['UPDGL']          = (($row['UPDGL'] == 'A') || ($row['UPDGL'] == 'G'));  // so it can be A or G, not 'N' or EMPTY
            if ($row['DOCID'] == substr($row['DESCRIPTION'], 0, strlen($row['DOCID']))) {  // often the id is the same as, or a shortened version of, the description
                $row['DOCID'] = '';
            } else {
                $row['DOCID'] .= ':';
            }
            $row['XACTION'] = $row['DOCID'] . $row['DESCRIPTION'] . ', Upd Inv:' . $row['UPDINV'] . ', SPI:' . $row['SPI'] . ', INC/DEC:' . $row['IN_OUT'] . ', Upd GL:' . $row['UPDGL'];
            return $row;
        });

        return $result;
    }


    // Find a specific docEntryCost record, by its record number

    /**
     * @param string|int $decrec
     *
     * @return int
     */
    private function findDocEntryCost($decrec)
    {
        return ($this->lineItemsByDecRec[ $decrec ] ?? -1);
    }


    /**
     * for logging or notes, identify a transaction
     *
     * @param array $line
     *
     * @return string
     */
    private function identify($line)
    {
        $rtn = sprintf(' %s:\'%s\'', $line['DOCDATE'] ?? '', $line['DOCID'] ?? '');
        if (isset($line['SYSTEMGENERATED']) && ($line['SYSTEMGENERATED'] == 'T')) {
            $rtn .= "(a system-generated entry)";
        }
        return $rtn;
    }



    /**
     * @param array $costLineItems
     * @param string $decref
     *
     * @return string
     */
    private function identifyByDecRef( &$costLineItems, $decref )
    {
        $decRefKey   = $this->findDocEntryCost( $decref );
        if ($decRefKey >= 0) {
            $line = $costLineItems[$decRefKey];
            $text = $this->identify($line);
            if ($line['STATE'] == self::DELETED) {
                $text .= "(deleted)";
            }
            $text .= ", DECREF is $decref";
        } else if (($decref == '') || ($decref == 0)) {
            $text = "NO SOURCE";
        } else {
            $text = "(source $decref not found)";
        }
        return $text;
    }



    /**
     * @param array $data
     *
     * @return bool
     * @throws Exception
     */
    public static function storeCSVInLog($data)
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        /**
         * @var ActionLogManager $mgr
         */
        $mgr = $gManagerFactory->getManager('actionlog');
        $mgr->setAddSwitch(true);
        $ok = $ok && $mgr->add($data);

        return $ok;
    }


    // ******************************************************************************************
    //
    //                  PROCESSING
    //
    // ******************************************************************************************


    /**
     *      processItemWarehouseChange - when looping through line items, the item OR warehouse changed.
     *
     * @param array     $costLineItems
     * @param string    $costMethod   one of the cost method costants, like 'self::COST_FIFO'
     * @param array     $itemWarehouseContext   an array of context information that this function maintains
     */
    private function processItemWarehouseChange(&$costLineItems, $costMethod, &$itemWarehouseContext)
    {
        // Now, at the end, we can show the COGS.  It gets all in and outbound transactions, in the original order.
        if (isset($itemWarehouseContext["ITM_WHS_TXN_KEYS"])) {
            foreach ($itemWarehouseContext["ITM_WHS_TXN_KEYS"] as $key) {
                $this->processCOGS($costMethod, $costLineItems, $costLineItems[$key], $itemWarehouseContext, $key);
            }
        }

        if (isset($itemWarehouseContext["INCOMING_TXNS"]) && !empty($itemWarehouseContext["INCOMING_TXNS"])) { // remaining inbound not dumpped yet?
            $this->processCOGSInbound($itemWarehouseContext["INCOMING_TXNS"], $costMethod, $costLineItems);  // any final inbound
        }

        $itemWarehouseContext["SKIPPED_COGS"]     = 0;
        $itemWarehouseContext["INCOMING_TXNS"]    = [];
        $itemWarehouseContext["ITM_WHS_TXN_KEYS"] = [];
    }


    /**
     * @param string        $note
     * @param string        $docdate
     * @param string        $enteredDate
     * @param string        $type
     * @param string        $afterDate
     *
     * @return string
     */
    private function NoteAboutDateChange($note, $docdate, $enteredDate, $type = "Entered", $afterDate = null)
    {
        if (($docdate != "") && ($enteredDate != "")) {
            $asOf = cachedStrToTime($docdate);
            $ent = $enteredDate;   // could be 10/02/16 or 28-JAN-16 11:52:0000PM
            $pos = strpos($ent, ' ');
            $entTime = "";
            if ($pos !== false) {
                $entTime = substr($ent, $pos);    // everyting from the space on
                $ent = substr($ent, 0, $pos);
            }
            $entered = cachedStrToTime($ent);

            if (($entered < $asOf) || (abs($entered - $asOf) > (24 * 60 * 60))) {   // entered date is not the same day!
                if (!empty($note)) {
                    $note .= "; ";
                }
                $note .= "$type on: " . $enteredDate;  // entered on a different date than the as-of
            }

            // Sometimes, a purchase is entered AFTER a sale, but in the tool we sort all purchases to be BEFORE the sales.
            //  so, here, if the date/time fields are set properly (they weren't in the past), then see if the day is the same
            //  and the time is before the sale, otherwise complain.
            if ($afterDate && ($entTime != '')) {
                $pos = strpos($afterDate, ' ');
                if ($pos !== false) {
                    if ($ent == substr($afterDate, 0, $pos)) {  // same day>
                        $afterTime = substr($afterDate, $pos);   // everyting from the space on

                        $dateBefore = date_parse($entTime);
                        $dateAfter = date_parse($afterTime);

                        if (is_array($dateBefore) && is_array($dateAfter)) {

                            if (stripos($entTime, ' PM') !== false) {  // is one of them in the PM?
                                $dateBefore['hour'] += 12;              // make it military time
                            }
                            if (stripos($afterTime, ' PM') !== false) {
                                $dateAfter['hour'] += 12;
                            }

                            $timeBefore = ($dateBefore['hour'] * 60 * 60) + ($dateBefore['minute'] * 60) + $dateBefore['second'];
                            $timeAfter = ($dateAfter['hour'] * 60 * 60) + ($dateAfter['minute'] * 60) + $dateAfter['second'];
                            if ($timeBefore > $timeAfter) {
                                if (!empty($note)) {
                                    $note .= "; ";
                                }
                                $note .= "Entered AFTER sale";
                            }
                        }
                    }
                }
            }
        }

        return $note;
    }


    /**
     * @param array $costLineItems
     * @param array $incomingTxns
     *
     * @return bool
     */
    private function anyErrors(&$costLineItems, &$incomingTxns)
    {
        foreach ($incomingTxns as $purchaseKey) {
            $purchase = $costLineItems[ $purchaseKey ];
            if (($purchase['STATE'] != self::GOOD) && ($purchase['STATE'] != self::CLOSED)) {
                $this->reportOnThisLine->set($purchaseKey, true); // so it shows up on the output
                return true;
            }
        }

        return false;
    }


    /**
     * @param string $note
     * @param string $whatToAdd
     */
    private function addToNote(&$note, $whatToAdd)
    {
        if (strpos($note, self::FATAL_ERROR) === false) {
            if ($note != "") {
                $note .= "; ";
            }
            $note .= $whatToAdd;
        }
    }


    /**
     * @param int|float $original
     * @param string $sqlName
     * @param array $line
     *
     * @return int|float
     */
    private function compareSqlChangeToMyChange( $original, $sqlName, &$line )
    {
        $rtn = $original;
        if (isset($line['FIXES'])) {
            $rtn = $line['FIXES'][$sqlName];
        }
        return $rtn;
    }



    /**
     * @param string $key
     * @param array $line
     * @param array $itemWarehouseContext
     */
    private function preProcessCogs($key, &$line, &$itemWarehouseContext)
    {
         if ($line['INOUT'] == 'I') {
            $itemWarehouseContext["INCOMING_TXNS"][] = $key;
        } else {
            $line["INCOMING_TXNS"] = $itemWarehouseContext["INCOMING_TXNS"];
            $itemWarehouseContext["INCOMING_TXNS"] = [];
        }
    }


    /**
     * Show the inbound records in the COGS report, if verbose
     *
     * @param array      $incoming  an array of transactions
     * @param string     $costMethod
     * @param array      $costLineItems all transactions of this cost method
     * @param string     $afterDate
     */
    private function processCOGSInbound($incoming, $costMethod, &$costLineItems, $afterDate = NULL) // $line['ENTERED_DATE']
    {
        // dump purchases
        foreach ($incoming as $key) {

            $reportOnLine = $this->verbose || $this->reportOnThisLine->get($key);

            if ($reportOnLine) {

                $purchase       = $costLineItems[$key];
                $note2          = $purchase['NOTES'];
                $affectsCogsQty = $purchase['UPDATE_COST']; // may not actually affect cogs, as there may be no cogs
                $affectsQty     = $purchase['UPDATE_QUANTITY'];
                $unitCost       = $purchase['UNITCOST'];   // sales returns seem to use itemavgwhsecost/unitcost

                // report on date differences (i.e. was it modified?)
                $note2 = $this->NoteAboutDateChange($note2, $purchase["DOCDATE"], $purchase['ENTERED_DATE'], "Entered", $afterDate);
                $note2 = $this->NoteAboutDateChange($note2, $purchase["DOCDATE"], $purchase['WHENMODIFIED'], "Modified");

                $purchase['NOTES'] = $note2;    // save the notes changes

                // do this for the note side effects.
                $price         = $this->compareSqlChangeToMyChange($unitCost, 'UNITCOST', $purchase);
                if (isset($purchase['FIXES'])) {
                    $cogs_computed = $purchase['FIXES']['COGS'];    // use Senthil's, not mine
                } else {
                    $cogs_computed = $purchase['COGS'];             // use original
                }
                if (($purchase[ "CLOSED" ] === true) &&
                    (strpos($purchase['STATE'], self::BAD) !== false)) {
                    $purchase['STATE'] = self::NOTFIXED;
                }
                $this->addToNote($purchase['NOTES'], "QtyLeft:" . $purchase['QTYLEFT']);
                $this->addToNote($purchase['NOTES'], ($purchase['DECREF'] ? "References " . $this->identifyByDecRef($costLineItems, $purchase['DECREF']) : ""));
                $this->cogs_computed->add( [
                    'DATE'          => $purchase['DOCDATE'],
                    'DOCUMENT'      => $purchase['DOCID'],
                    'ITEM'          => $purchase['COMP'],
                    'WAREHOUSE'     => $purchase['WAREHOUSEKEY'],
                    'QUANTITY'      => $affectsQty ? $purchase['QUANTITY'] + 0 : 0,
                    'COGS_QUANTITY' => $affectsCogsQty ? $purchase['QUANTITY'] + 0 : 0,  // T is both quantity AND affects costs
                    'ON_HAND'       => $purchase['RUNNING_QTY'],
                    'COGS_ON_HAND'  => $purchase['RUNNING_QTY_VALUE'],
                    'UNIT_COST'     => $unitCost,
                    'COST_COMPUTED' => $price,
                    'COGS_POSTED'   => $purchase['COGS'] + 0.0,
                    'COGS_COMPUTED' => $cogs_computed,
                    'COST_METHOD'   => $costMethod,
                    'STATE'         => (($purchase['STATE'] == self::GOOD) ? "" : $purchase['STATE']),
                    'N_XACTION'     => $this->docPar($purchase['DOCPARKEY'],'XACTION'),
                    'NOTE'          => $purchase['NOTES'],
                    'N_PURCHASE'    => true,        // so we know it isn't a sale
                    'GLIMPACT0'     => (($this->glImpact && $this->reboot) ? ($purchase['MYGLIMPACT0'] ?? '') : 'SKIP'),
                    'GLIMPACT1'     =>  ($this->glImpact ? ($purchase['MYGLIMPACT1'] ?? '') : ''),
                    'GLIMPACT2'     => (($this->glImpact && $this->reboot) ? ($purchase['MYGLIMPACT2'] ?? '') : 'SKIP'),
                    'GLIMPACT3'     =>  ($this->glImpact ? ($purchase['MYGLIMPACT3'] ?? '') : ''),
                    'GLIMPACT4'     => (($this->glImpact && $this->reboot) ? ($purchase['MYGLIMPACT4'] ?? '') : 'SKIP'),
                    'GLIMPACT5'     =>  ($this->glImpact ? ($purchase['MYGLIMPACT5'] ?? '') : ''),
                    'GLIMPACT6'     =>  ($this->glImpact ? ($purchase['MYGLIMPACT6'] ?? '') : ''),
                    'GLIMPACT7'     =>  ($this->glImpact ? ($purchase['MYGLIMPACT7'] ?? '') : ''),
                ] );

                if (isset($purchase['NEW_DECS'])) {
                    foreach ($purchase['NEW_DECS'] as $row) {
                        $note = ($row['NOTES'] ?? '') . ($row['DECREF'] ? "References " . $this->identifyByDecRef($costLineItems, $row['DECREF']) . "; " : "");
                        $note .= "DocEntry:{$purchase['DEREC']}, DocEntryCost:{$row['DECREC']}";

                        $this->cogs_computed->add( [
                            'DATE'          => "",
                            'DOCUMENT'      => "",
                            'ITEM'          => "",
                            'WAREHOUSE'     => "",
                            'QUANTITY'      => $affectsQty ? ($row['QUANTITY'] + 0.0) : 0,
                            'COGS_QTY'      => $affectsCogsQty ? ($row['QUANTITY'] + 0.0) : 0,  // T is both quantity AND affects costs
                            'ON_HAND'       => "",
                            'COGS_ON_HAND'  => "",
                            'UNIT_COST'     => "",
                            'COST_COMPUTED' => $row['UNITCOST'],
                            'COGS_POSTED'   => "",
                            'COGS_COMPUTED' => $row['COGS'],
                            'COST_METHOD'   => "",
                            'STATE'         => self::ADDED,
                            'N_XACTION'     => "",
                            'NOTE'          => $note,
                            'N_PURCHASE'    => true,        // so we know it is a purchase
                        ]);
                    }
                }
            }
        }
    }


    /**
     *  processCOGS - Add one record to the COGS table for CSV output, regardless of cost method, but only if the entry is BAD
     *              (a Cookiue controls whether we add all or just bad records)
     *
     * @param string $costMethod              the cost method being used
     * @param array $costLineItems            all transactions for this cost method
     * @param array  $line                    The current line item being processed (one docentrycost record)
     * @param array  $itemWarehouseContext    warehouse context, so I can ask the warehouse routines questions.  Not nmodified in here
     * @param int    $lineIndex               What is the index into the costLineItems array?
     */
    private function processCOGS($costMethod, &$costLineItems, &$line, &$itemWarehouseContext, $lineIndex)
    {
        $reportOnLine = $this->verbose || $this->reportOnThisLine->get($lineIndex);
        $qty = $line['QUANTITY'];         // negative for outbound
        $whse_cost = $line['UNITCOST'];

        $note = $line['NOTES'];

        $cogs_computed = (isset($line['COGS']) ? ibcmul($qty, $whse_cost, 12, true) : 0);

        //  ************************************************************
        //
        //  Add helpful data to balance COGS and the Valuation Report....
        //
        //  ************************************************************
        if ($this->glImpact) {

            $closed = ($line["NOGLCHANGES"] == true);
            $offset = ($closed ? 0 : 1);

            $costToUse = $line['COGS'];
            if (isset($line['FIXES'])) {
                $costToUse = $line['FIXES']['COGS'];    // use Senthil's, not mine
            }
            $derec = $line['DEREC'];
            $item  = $line['COMP'];

            if (isset($this->deglresolveAmounts[ $derec ][$item])) {
                if ($this->deglresolveAmounts[$derec][$item]['COST_UPDATED']) {
                    $costToUse = $this->deglresolveAmounts[$derec][$item]['CURRENT_COST'];
                } else if ( ! $closed) {
                    $this->addToNote($note, "COST NOT UPDATED?");
                }
            }
            $costToUse = iround($costToUse,2);

            if (isset($line['GLAMOUNT'])) { // last line for this DEREC, has GL impact

                // Inbound Inventory transactions may have 'COGS', but they are not really COGS, but the GL account.
                //  Landed Costs will make adjustments to things, and we want to separate out the ADJUSTMENTS from
                //  true changes to the GL.
                $inboundInventory = false;
                if (($line['INOUT'] == 'I') && ($line['SPI'] == 'I')) {
                    $inboundInventory = true;
                }

                $realGL             = iround($line['GLAMOUNT'], 2); // what it should be
                $delta              = $realGL - $line['GLAMOUNT'];  // remove any old fractional amounts
                $priorAdjustments   = $this->invCostToolHelper->cogsAdjustments($derec);
                $delta             += iround($costToUse - ($realGL + $priorAdjustments), 2);
                if ($delta != 0.0) {
                    if ($inboundInventory) {
                        $line['MYGLIMPACT' . (0 + $offset)] = $delta;    // GL repost amount
                    } else {
                        $line['MYGLIMPACT' . (2 + $offset)] = $delta;   // COGS repost amount
                    }
                    $this->addToNote($note, "GL Amount:" . $line['GLAMOUNT'] . ", should be " . ($line['GLAMOUNT'] + $delta) );
                    if ($line['STATE'] == self::GOOD) {
                        $line['STATE']  = ($closed ? self::NOTTOBEFIXED : self::BAD);
                        $this->errorsFound++;
                        if ($this->fixingData) {
                            if ($closed) {
                                $line['STATE'] = self::NOTFIXED;  // well, we assume....
                            } else {
                                $line['STATE'] = self::FIXED;  // well, we assume....
                                $this->errorsFixed++;
                            }
                        }
                    }
                }

                // record prior COGS adjustments:
                if ($priorAdjustments) {
                    $line['MYGLIMPACT' . (4 + $offset)] = $priorAdjustments;
                }

                if ($inboundInventory) {
                    $line['MYGLIMPACT7'] = $line['GLAMOUNT'];   // NOT COGS, but GL
                } else {
                    $line['MYGLIMPACT6'] = $line['GLAMOUNT'];   // COGS
                }
            }
         }

        // *****************************************************
        // DONE WITH INBOUND FOR NOW
        // *****************************************************
        if ($line['INOUT'] == 'I') {
            $line['NOTES'] = $note;
            return; // nothing more to do here
        }

        $cogs_computed = -$cogs_computed;

        // input items have cost already, with the burden
        $line['COST']  = $cogs_computed;

        // Now: do we show this record in the CSV file?
        if ($this->COGS) {

            $showThis  = $reportOnLine || (! in_array($line['STATE'], [self::GOOD, self::CLOSED, self::DELETED, self::ADDED]));
            $showPrior = $reportOnLine || $this->anyErrors($costLineItems, $line["INCOMING_TXNS"]);

            if ($showPrior) {
                $this->processCOGSInbound($line["INCOMING_TXNS"], $costMethod, $costLineItems, $line['ENTERED_DATE']);
            }

            // If a customer has 100k transactions and average 10 lines per transactions, we'll have a MILLION COGS lines for the CSV file,
            //      of which there will usually be zero-a dozen or so bad.  So.... maybe we should only store BAD entries by default
            if ($showThis) {
                $note = $this->NoteAboutDateChange($note, $line["DOCDATE"], $line['ENTERED_DATE']);
                $note = $this->NoteAboutDateChange($note, $line["DOCDATE"], $line['WHENMODIFIED'], "Modified");

                // Is there a good reason for COGS to change?

                if (!$showPrior) {
                    $c = count($line["INCOMING_TXNS"]);
                    if ($c > 0) {
                        $this->addToNote($note, "Prior incoming transactions:$c");
                    }
                }

                $affectsCogsQty = $line['UPDATE_COST'];
                $affectsQty = $line['UPDATE_QUANTITY'];

                $originalPrice = $line['UNITCOST'];
                $line['NOTES'] = $note;
                if (isset($line['FIXES'])) {
                    $line['FIXES']['QUANTITY'] = - $line['FIXES']['QUANTITY'];  // flip sign to be positive
                    $this->addToNote($line['NOTES'],"(**)"); // modified
                }
                $qty            = $this->compareSqlChangeToMyChange( - $line['QUANTITY'], 'QUANTITY', $line );
                if ($qty != (- $line['QUANTITY'])) {
                    $this->addToNote($line['NOTES'],  "QTY was " . (- $line['QUANTITY']) );
                }
                $whse_cost      = $this->compareSqlChangeToMyChange( $originalPrice, 'UNITCOST', $line );
                $cogs_computed  = $this->compareSqlChangeToMyChange( $line['COGS'], 'COGS', $line );
                $this->addToNote($line['NOTES'], $line['DECREF'] ? ("Source " . $this->identifyByDecRef($costLineItems, $line['DECREF'])) : "No Source");
                if (($line[ "CLOSED" ] === true) &&
                    (strpos($line['STATE'], self::BAD) !== false)) {
                    $line['STATE'] = self::NOTFIXED;
                }

                $this->cogs_computed->add( [
                    'DATE'          => $line['DOCDATE'],
                    'DOCUMENT'      => $line['DOCID'],
                    'ITEM'          => $line['COMP'],
                    'WAREHOUSE'     => $line['WAREHOUSEKEY'],
                    'QUANTITY'      => $affectsQty ? ($qty + 0.0) : 0,
                    'COGS_QTY'      => $affectsCogsQty ? ($qty + 0.0) : 0,  // T is both quantity AND affects costs
                    'ON_HAND'       => $line['RUNNING_QTY'],
                    'COGS_ON_HAND'  => $line['RUNNING_QTY_VALUE'],
                    'UNIT_COST'     => $originalPrice,
                    'COST_COMPUTED' => $whse_cost,
                    'COGS_POSTED'   => $line['COGS'] + 0.0,
                    'COGS_COMPUTED' => $cogs_computed,
                    'COST_METHOD'   => $costMethod,
                    'STATE'         => $line['STATE'],
                    'N_XACTION'     => $this->docPar($line['DOCPARKEY'],'XACTION'),
                    'NOTE'          => $line['NOTES'],
                    'N_PURCHASE'    => false,        // so we know it is a sale
                    'N_SKIPPED'     => $itemWarehouseContext["SKIPPED_COGS"],
                    'GLIMPACT0'     => (($this->glImpact && $this->reboot) ? ($line['MYGLIMPACT0'] ?? '') : 'SKIP'),
                    'GLIMPACT1'     =>  ($this->glImpact ? ($line['MYGLIMPACT1'] ?? '') : ''),
                    'GLIMPACT2'     => (($this->glImpact && $this->reboot) ? ($line['MYGLIMPACT2'] ?? '') : 'SKIP'),
                    'GLIMPACT3'     =>  ($this->glImpact ? ($line['MYGLIMPACT3'] ?? '') : ''),
                    'GLIMPACT4'     => (($this->glImpact && $this->reboot) ? ($line['MYGLIMPACT4'] ?? '') : 'SKIP'),
                    'GLIMPACT5'     =>  ($this->glImpact ? ($line['MYGLIMPACT5'] ?? '') : ''),
                    'GLIMPACT6'     =>  ($this->glImpact ? ($line['MYGLIMPACT6'] ?? '') : ""),
                    'GLIMPACT7'     =>  ($this->glImpact ? ($line['MYGLIMPACT7'] ?? '') : ""),
                ] );
                $itemWarehouseContext["SKIPPED_COGS"] = 0; // didn't skip this one, did we?

                if (isset($line['NEW_DECS'])) {
                    foreach ($line['NEW_DECS'] as $row) {
                        $note = ($row['NOTES'] ?? '') . ($row['DECREF'] ? "Source " . $this->identifyByDecRef($costLineItems, $row['DECREF']) : "No Source");
                        $note .= "; DocEntry:{$line['DEREC']}, DocEntryCost:{$row['DECREC']}";
                        $this->cogs_computed->add( [
                            'DATE'          => "",
                            'DOCUMENT'      => "",
                            'ITEM'          => "",
                            'WAREHOUSE'     => "",
                            'QUANTITY'      => $affectsQty ? (-$row['QUANTITY'] + 0.0) : 0,    // qty from senthil is negative
                            'COGS_QTY'      => $affectsCogsQty ? (-$row['QUANTITY'] + 0.0) : 0,
                            'ON_HAND'       => "",
                            'COGS_ON_HAND'  => "",
                            'UNIT_COST'     => "",
                            'COST_COMPUTED' => $row['UNITCOST'],
                            'COGS_POSTED'   => "",
                            'COGS_COMPUTED' => $row['COGS'],
                            'COST_METHOD'   => "",
                            'STATE'         => self::ADDED,
                            'N_XACTION'     => "",
                            'NOTE'          => $note,
                            'N_PURCHASE'    => false,        // so we know it is a sale
                        ] );
                    }
                }

            } else {
                $itemWarehouseContext["SKIPPED_COGS"]++;
            }
        }
        $line['NOTES'] = $note;
     }


    /**
     *  processCosts - for each cost method this will generate COGS records and do other checks
     *
     *      Loop through the lines; they are in item, warehouse, date, txntype order
     *          (txntype === incoming purchases, then sales returns, then purchase returns, then sales)
     *
     *  If a sale doccostentry record is for a specific serial or line number, attempt to 'link' it to the purchase of that specific item
     *  Otherwise, try to 'link' it to the earliest/latest available purchase, so as to hopefully resolve negative inventory values
     *
     *  Keep a record of the problems (only) in the COGS array so we can save that as CSV for the customer to print later.  Why only the BAD records?
     *  because NOTMALLY, there could be a million GOOD records and zero to a dozen BAD records; why keep all the GOOD records?
     *
     *  At this time, the quantities only come from VALUE transactions (or Value+Quantity), not Quantity-only transactions.  That seems wrong, but that's
     *  what the rest of the product does, so....
     *
     *
     * @param array  $costLineItems      array of line items read by 'fetchXxxxLineItems()' (all the transactions for this cost method)
     * @param string $costMethod         one of the cost method costants, like 'self::COST_FIFO'
     *
     */
    private function processCosts(&$costLineItems, $costMethod)
    {
        $item_key               = NULL;
        $warehouse_key          = NULL;
        $date_key               = NULL;
        $itemWarehouseContext   = array();  // stuff to know about an item/warehouse combo

        foreach ($costLineItems as $key => &$line) {
            // **********************************************************
            //  SET UP CURRENT DOCPAR VALUES
            // **********************************************************
            $docpar                 = $this->docPar($line['DOCPARKEY']);
            $line['SPI']            = $docpar['SPI'];      // sale, purchase, inventory
            $line['UPDGL']          = $docpar['UPDGL'];
            $line['UPDINV']         = $docpar['UPDINV'];   // updates inventory: Q[uantity], V[alue], T[q+v], F or empty
            $line['COSTMETHOD']     = $costMethod;
            $this->addToNote($costLineItems[$key]['NOTES'], "DocEntry:{$line['DEREC']}, DocEntryCost:{$line['DECREC']}");
            if ((! isset($line['FOUND'])) && ($line['CLOSED'] !== true)) {
                if (strpos($line['NOTES'], self::FATAL_ERROR) === false) {
                    $line['STATE'] = self::DELETED; // removed by sql routines
                }
            }

            // This is why we handled ADJDOCENTRYCOSTKEY in a pre-loop; we want the adjustees to know they were adjusted.
            if (isset($line['SYSTEMGENERATED']) && ($line['SYSTEMGENERATED'] == 'T')) {
                $this->addToNote($costLineItems[$key]['NOTES'], "System Generated");
                if (($line['AFFECTS_INVENTORY'] == 'V') && ($line['UPDINV'] == 'Q') && isset($line['ADJUSTED_BY'])) {
                    if (isset($line['ADJUSTED_BY'])) {
                        foreach ($line['ADJUSTED_BY'] as $adjustmentLine) {
                            $adjSource = $costLineItems[$adjustmentLine] ?? [];
                            $this->addToNote($costLineItems[$key]['NOTES'], "Q txn V layer adjusted by " . $this->identify( $adjSource) );
                        }
                    }
                }
            }

            $updateInventory        = $line['AFFECTS_INVENTORY'];
            $updateQty              = (($updateInventory == 'Q') || ($updateInventory == 'QV'));
            $updateCost             = (($updateInventory == 'V') || ($updateInventory == 'QV'));
            $line['UPDATE_QUANTITY']= $updateQty;
            $line['UPDATE_COST']    = $updateCost;

            // **********************************************************
            //  HAS DATE, WAREHOUSE, OR ITEM CHANGED?
            // **********************************************************
            // note: the query, and so this array, is in order by item key and warehouse key
            // Has the item changed?
            $itemOrWarehouseChanged = (($line['COMP'] != $item_key) || ($line['WAREHOUSEKEY'] != $warehouse_key));

            // Has the DATE changed?
            if ($itemOrWarehouseChanged || ($line['DOCDATE'] != $date_key)) {
                $date_key = $line['DOCDATE'];
            }

            if  ($itemOrWarehouseChanged) {

                // note: the item or warehouse has changed, finish off the previous item/warehouse
                $this->processItemWarehouseChange( $costLineItems, $costMethod, $itemWarehouseContext);
                $warehouse_key = $line['WAREHOUSEKEY'];

                // Was it the item key that changed?
                if ($line['COMP'] != $item_key) {
                    $item_key = $line['COMP'];
                }
            }

            // **********************************************************
            //  SAVE TRANSACTION FOR LATER PROCESSING FOR COGS (once we've seen all the rows for this item/warehouse)
            // **********************************************************
            $itemWarehouseContext["ITM_WHS_TXN_KEYS"][] = $key;

            $this->preProcessCogs( $key, $line, $itemWarehouseContext );
        }

        if ($item_key == null) {
            return; // we processed nothing
        }

        // finish up with the remaining items that didn't get processed with an item, warehouse, or date change
        $this->processItemWarehouseChange( $costLineItems, $costMethod, $itemWarehouseContext );
    }


    /**
     *  Get the ONHAND and ONHAND WITH VALUE quantities, as starting values, from the itmhistcost table
     *
     * @param string $ason
     *
     * @return bool
     *
     */
    private function getBeginningCosts($ason)
    {
        $items   = $this->invCostToolHelper->getIitemsForMethod('ALL');
        $qry     = [];
        $qry[0]  = "with high_dates as 
                          (select  /*+ materialize */  whsekey, itemkey, max(ason) ason from itmhistcost 
                          where cny# = :1 and ason < to_date(:2, 'MM/DD/YYYY') ";
        $qry[1]  = GetMyCompany();
        $qry[2]  = $ason;
        $qry     = PrepINClauseStmt($qry, $items, ' and itemkey ');
        $qry[0] .= " group by whsekey, itemkey)
                     SELECT i.whsekey, i.itemkey, i.qtywithvalue, i.qtyonhand
                        FROM
                            itmhistcost i, high_dates h
                        WHERE
                            i.cny#           = :1
                            AND i.whsekey    = h.whsekey       
                            AND i.itemkey    = h.itemkey
                            AND i.ason       = h.ason       
                            AND	i.qtyonhand != 0 ";
        $result  = QueryResult($qry);
        if ($result === false) {
            return false;
        }

        foreach ($result as $row) {
            $this->beginning_costs[$row['ITEMKEY']][$row['WHSEKEY']] = [ $row['QTYWITHVALUE'], $row['QTYONHAND'] ];
        }
        return true;
    }


    /**
     *      Log COGS Data As CSV - log the potentially giant COGS report
     *
     * @param string $glMessages    error messages from saving to the GL, if any
     *
     */
    private function logCOGSDataAsCSV( $glMessages )
    {
        $csv  = "";

        $csv .= implode(',', array( 'TXN_DATE', 'DOCUMENT', 'ITEM', 'WAREHOUSE',
                                    'QTY_ON_TXN', 'COGS_QTY_ON_TXN',
                                    'QOH', 'COGS_QOH',
                                    'COST_EA_POSTED', 'COST_EA_RECALCULATED',
                                    'COGS_POSTED', 'COGS_RECALCULATED'));
        $csv .= ",COST_METHOD, STATE";

        if ($this->extraCSVOutput) {
            $csv .= ",TRANSACTION";   // extra debugging info
        }
        $csv .= ",NOTES";
        if ($this->glImpact && $this->reboot) {
            $csv .= ",GL CHANGE CLOSED,GL CHANGE OPEN,COGS CHANGE CLOSED,COGS CHANGE OPEN,GL ADJUSTMENTS CLOSED,GL ADJUSTMENTS OPEN,CURRENT COGS AMT,CURRENT GL AMT";
        } else if ($this->glImpact) {
            $csv .= ",GL CHANGE,COGS CHANGE,GL ADJUSTMENTS,CURRENT COGS AMT,CURRENT GL AMT";
        }

        $secrets = ($this->fixingData) ? "Fixing " : "Analyzing ";
        $secrets .= ($this->quickRun)  ? "(Quick); " : "; ";

        if ($this->reboot) {
            $secrets .= "CHANGE CLOSED PERIODS BUT NOT GL; ";
        }
        if ( ! $this->updateGL) {
            $secrets .= "NO GL UPDATES; ";
        }
        if ($this->sortCreate) {
            $secrets .= "CREATE date order; ";
        }
        if ($this->sortModified) {
            $secrets .= "MODIFIED date order; ";
        }
        $csv .= ",$secrets Report: Cost of Goods Sold per Transaction; " . self::VERSION . PHP_EOL;

        $inPurchases = false;

        foreach ($this->cogs_computed as $row) {
            $comma = '';
            $purchase = $row['N_PURCHASE'];
            if (($row['N_SKIPPED'] ?? 0) > 0) {
                $s = $row['N_SKIPPED'];
                $csv .= PHP_EOL . "(skipping past $s sales/outgoing where the recomputed values matched the original values)" .  PHP_EOL;
            }
            if ($purchase != $inPurchases) {
                if ($purchase) {
                    $csv .= PHP_EOL . "PURCHASES/INCOMING:";
                } else {
                    $csv .= PHP_EOL . "SALES/OUTGOING:";
                }
                $csv .= PHP_EOL;    // blank line
                $inPurchases = $purchase;
            }
            foreach ($row as $key => $field) {
                if ($key == '__row__') {
                    continue;
                }
                if (strpos($key,"GLIMPACT") !== false) {
                    if (!$this->glImpact) {
                        continue;
                    } else if ($field === 'SKIP') {
                        continue;
                    }
                }
                if (($key != 'N_PURCHASE') && ($key != 'N_SKIPPED')) { // skip this column
                    if ($this->extraCSVOutput || substr($key, 0, 2) != 'N_') {
                        $csv .= $comma . $this->escapeForCSV($field);
                        $comma = ',';
                    }
                }
            }
            $csv .= PHP_EOL;
        }

        unset($this->cogs_computed); // free up the potentially huge amount of ram

        $csv .= PHP_EOL . str_replace( '<br>', "\n", $glMessages);

        $this->processOffline(self::CSV_COGSDATA, 'COGS Data', $csv);
    }

    /**
     * @param array  $obj
     * @throws Exception
     */
    public function fetchLog(&$obj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $logMgr = $gManagerFactory->getManager('actionlog');
        $params = array(
            'selects' => array(
                'RECORDNO', 'WHENCREATED', 'ACTION', 'DESCRIPTION'
            ),
            'filters' => array(
                array(
                    array('MODULE', '=', 'Inventory'),
                    array('LOGTYPE','=', 'INVHEALTHCHK'),
                    array('OBJECT', '=', 'Costing'),
                    array('LOG_BLOB', 'ISNOTNULL'),
                ),
            ),
            'orders' => array(
                array('RECORDNO', 'desc'),
            ),
        );
        $logs = $logMgr->GetList($params);

        $obj['LOG'] = $logs;
    }

    /**
     * @param  array $obj
     *
     * @return bool
     * @throws Exception
     */
    function downloadCSV($obj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        /** @var ActionLogManager $logMgr */
        $logMgr = $gManagerFactory->getManager('actionlog');
        $logs = $logMgr->Get($obj[$obj['DOWNLOAD'] . '_CSV']);
        $title = $logs['ACTION'] . ' ' . $logs['WHENCREATED'];

            // I'm scared to change the actions, but Patti wanted to remove the word 'Fetch'
            // and replace it with 'Inspect' or 'Fix'.
        $title = str_replace( "Fetch ", $obj['OBJECT'] . ' ', $title );

        // From reporter.cls:
        // Ticket 41964 : Excel exports working as 'web page' and in 'read only mode'
        if (isl_stristr($_SERVER['HTTP_USER_AGENT'], "msie")
            || isl_stristr($_SERVER['HTTP_USER_AGENT'], "Trident/7.0; rv:11.0")
        ) {
            $dispHeader = "attachment;";
        } else {
            $dispHeader = "";
        }
        header("Content-Disposition: $dispHeader filename=\"$title.csv\"");
        header("Content-type: application/vnd.ms-excel");

        echo $logs['LOG_BLOB'];

        return true;
    }

    /**
     * @param array $costLineItems
     *
     * @return bool
     * @throws Exception
     */
    private function fixDocEntryCostData( &$costLineItems )
    {
        $ok         = true;

        $deGlResolvesNeedingAdjustment = [];

        foreach ($costLineItems as &$line) {

            //  ************************************************************
            //
            //  Ignore items in closed periods or before the customer-chosen fix date
            //
            //  ************************************************************
            if ($this->reboot || ($line[ "CLOSED" ] !== true)) {
                 $this->RepostCOGS($line, $deGlResolvesNeedingAdjustment);    // synch to the OLD value: the posted COGS number
            }
        }

        // Do we need to mark some deglresolves as needing manual adjustment?
        if ( ! empty($deGlResolvesNeedingAdjustment)) {
            $query = [];
            $query[] = "UPDATE deglresolve set COST_ADJ_NEEDED = 'T' where cny# = :1 ";
            $query[] = GetMyCompany();
            $query   = PrepINClauseStmt($query, $deGlResolvesNeedingAdjustment, " and record# ");
            $ok = ExecStmt($query);
        }

        return $ok;
    }

    /**
     * Get a batch, though it may have been fetched/cached before.
     *
     * @param array $line
     * @param string $batchNumber
     *
     * @return bool
     *
     * @throws Exception
     */
    function getABatch(&$line, $batchNumber)
    {
        $whencreated = $line['DOCDATE'];
        $docID       = $this->docPar($line['DOCPARKEY'], 'ORIGINAL_DOCID');
        $ok          = true;

        if ( ! isset($this->glBatches[$batchNumber])) {

            if ($batchNumber) {

                if ( ! isset($this->glBatchCache[ $batchNumber ])) {
                    $glEntriesMap = array();
                    $glbatch = $this->invBatchMgr->GetGLBatch( $batchNumber, $glEntriesMap);
                    if ($glbatch) {
                        $glbatch['record#']  = $glbatch['RECORDNO'];
                        $glbatch['JOURNAL#'] = $glbatch['JOURNALKEY'];

                        $this->glBatchCache[$batchNumber] = $glbatch;
                    } else {
                        $ok = false;
                    }
                }
                if ($ok) {
                    $this->glBatches[$batchNumber] = $batchNumber;
                } else {
                    $ok = false;
                }
            } else {
                $ok = false;
            }
        }

        if ($ok) {
            $batchNumber      = $this->glBatches[$batchNumber];
            if (isset($this->glBatchCache[$batchNumber]['IRT_DOCID'])) {
                if (strpos( $this->glBatchCache[$batchNumber]['IRT_DOCID'] , $line['DOCID']) === false) {   // not already there?
                    $this->glBatchCache[$batchNumber]['IRT_DOCID'] .= " and " . $line['DOCID'];    // save the doc id we changed into the batch for later error messages.
                }
            } else {
                $this->glBatchCache[$batchNumber]['IRT_DOCID'] = $line['DOCID'];
            }
        } else {
            $this->addToNote( $line['NOTE'], "COULD NOT FIND BATCH $whencreated / $docID TO UPDATE");
            logFL("**** DEBUG NO BATCH FOR $whencreated / $docID");
        }
        return $ok;
    }


    /**
     *  While we are saving the batch, save the relevent DeGlResolve records (in the same transaction)
     *
     * @param array $deglresolveArray
     *
     * @return bool
     */
    private function saveDeGlResolve(&$deglresolveArray)
    {
        $cny     = GetMyCompany();
        $ok      = true;

        // For each batch there may be several doc-entry-recs with changes.
        // we were passed the array of such recs....
        foreach ($deglresolveArray as $oneDeGlResolve) {

            $new_cost   = $oneDeGlResolve['NEW_COST'];
            $new_trx    = $oneDeGlResolve['NEW_TRX'];

            // We want one record per glentrykey.  If more than that, we need to delete records!
            $count      = count($oneDeGlResolve['RECORD#']);

            if ($count > 1) {
                $in        = '';
                $firstTime = true;
                $comma     = '';
                foreach ($oneDeGlResolve['RECORD#'] as $rec) {
                    if ($firstTime) {
                        $firstTime = false;
                        continue;   // the first record is the one we will KEEP and UPDATE
                    }
                    $in .= $comma . $rec;
                    $comma = ',';
                }
                $ok = $ok && ExecStmt(array("DELETE deglresolve WHERE cny#= :1 and record# in ($in)", $cny));
            }

            // now update the first record
            $ok = $ok && ExecStmt(array("UPDATE deglresolve set amount= :1, trx_amount= :2, COST_ADJ_NEEDED = 'F' where cny#= :3 and record# = :4",
                                    iround($new_cost, 2), iround($new_trx, 2), $cny, $oneDeGlResolve['RECORD#'][0]));
        }
        return $ok;
    }


    /**
     * saveBatches - save all the cached batches we updated.
     *
     * @param string $glMessages
     *
     * @return bool
     */
    function saveBatches( &$glMessages )
    {
        $source = self::TXN_SOURCE;
        $ok = true;
        $errorCheckpoint = Globals::$g->gErr->Checkpoint();

        foreach ($this->glBatchCache as &$oneBatch) {

            $docID = $oneBatch['IRT_DOCID'];    // maybe this doc ID will help with error tracking
            unset($oneBatch['IRT_DOCID']);

            if (($this->glBatchMgr->set($oneBatch) == true) && ($this->saveDeGlResolve($oneBatch['DEGLRESOLVE']) == true)) {
                // we changed something.  Commit it in case the next go-around causes errors.
                // then start a new transaction for the next pass
                $this->_QM->commitTrx($source);
            } else {
                $this->errorsFound++;
                $this->errorsNoGl++;
                // help caller figure out what txn went wrong
                //i18N::TODO - (Input from File owner (Blank Legacy code added in definition file))
                Globals::$g->gErr->addIAError(
                    'INV-0647', __FILE__ . ':' . __METHOD__,
                    "Transaction(s) updated in this batch: " . $docID,
                    ['DOCID'=>$docID]
                );

                // Now get ALL the errors for this batch and reset the error stack so we can keep going.
                $glMessages .= Globals::$g->gErr->myToString(true, 20) . "\n\n";

                Globals::$g->gErr->Restore($errorCheckpoint);   // reset the error table back to what it was before we called this.
                $this->_QM->rollbackTrx($source);               // roll back this one
            }
            $this->_QM->beginTrx($source);                     // and start a new one for next time
        }

        $this->glBatches = array();
        $this->glBatchCache = array();  // so we can't do this again, and save space

        return $ok;
    }


    /**
     *  Update the batch IN CACHE; we'll actually write the batches a little later.  This way, if multiple entries
     *  are in the same batch we only update the batch once on disk.
     *
     *  Also, record that the DeGlResolve records need to be updated, and we will update those in the same transaction
     *  as we update the batch.
     *
     * @param array $line
     * @param int $glEntryKey           gl entry record# of the underlying deglresolve record
     * @param string $batchNumber       batch# of the underlying deglresolve record
     * @param string $recordnos         record# of the underlying deglresolve record
     * @param string $amountDelta
     * @param string $trxDelta
     * @param string $new_cost
     * @param string $new_trx
     *
     * @return bool
     */
    function updateBatch(&$line, $glEntryKey, $batchNumber, $recordnos, $amountDelta, $trxDelta, $new_cost, $new_trx)
    {
        $ok = $this->getABatch($line, $batchNumber);   // maybe from the cache

        if ($ok) {

            // save info for later update of DEGLRESOLVE records....
            $this->glBatchCache[$batchNumber]['DEGLRESOLVE'][] =
                ['ITEM' => $line['COMP'], 'DEREC' => $line['DEREC'], 'GLENTRY' => $glEntryKey, 'NEW_COST' => $new_cost, 'NEW_TRX' => $new_trx, 'RECORD#' => $recordnos];

            if (isset( $this->glBatchCache[ $batchNumber ]['ENTRIES'][$glEntryKey])) {
                $amt = $this->glBatchCache[ $batchNumber ]['ENTRIES'][$glEntryKey]['AMOUNT'] + $amountDelta;
                if ($amt < 0) {
                    $amt = 0;   // don't go negative
                }
                $this->glBatchCache[ $batchNumber ]['ENTRIES'][$glEntryKey]['AMOUNT'] = iround( $amt, 2 );

                $amt = $this->glBatchCache[ $batchNumber ]['ENTRIES'][$glEntryKey]['TRX_AMOUNT'] + $trxDelta;
                if ($amt < 0) {
                    $amt = 0;   // don't go negative
                }
                $this->glBatchCache[ $batchNumber ]['ENTRIES'][$glEntryKey]['TRX_AMOUNT'] = iround( $amt, 2);
            } else {
                $ok = false;
                logFL("*** DEBUG couldn't find record in batch!" );
            }
        }

        return $ok;
    }




    /**
     * update the DeGlResolve records and report to the GL.
     *
     * @param array $cogsValues
     * @param int[] $deGlResolvesNeedingAdjustment      a list of deglresolve records that we think need manual adjustment
     *
     * @return bool
     */
    function RepostCOGS(&$cogsValues, &$deGlResolvesNeedingAdjustment)
    {
        $ok       = true;
        $item     = $cogsValues['COMP'];
        $derec    = $cogsValues['DEREC'];

        // Are there no COGS postings?
        if (!isset($cogsValues['GLAMOUNT'], $this->deglresolveAmounts[$derec][$item]) || !$this->updateGL) {
            return $ok;    // nothing to do
        }

        // we collected the rolled-forward COGS amounts, fixed and unfixed, into here.
        $old_cost = iround($cogsValues['GLAMOUNT'],2);
        $new_cost = $old_cost;
        if (isset($this->deglresolveAmounts[$derec][$item]) && $this->deglresolveAmounts[$derec][$item]['COST_UPDATED']) {
            $new_cost = iround($this->deglresolveAmounts[$derec][$item]['CURRENT_COST'], 2);
        }
        $costDelta = iround($new_cost - ($old_cost + $this->invCostToolHelper->cogsAdjustments($derec)), 2);

        // never never change the GL in a closed period
        if ($cogsValues[ "NOGLCHANGES" ] === true) {
            if (($costDelta != 0) && ($this->deglresolveAmounts[$derec][$item]['COST_ADJ_NEEDED'] == 'F')) {   // not already flagged as needing changes
                // ok, so, here, we have a GL-OUT-OF-BALANCE situation, but we can't update the GL.
                // but we CAN change the DEGLRESOLVE records to note that an update is needed later
                // by the Nov, 2018 "CogsClosedJe" tool....
                $this->deglresolveAmounts[$derec][$item]['COST_ADJ_NEEDED'] = 'T';                             // so we do this ONCE per derec
                $deGlResolvesNeedingAdjustment = array_merge($deGlResolvesNeedingAdjustment, $this->deglresolveAmounts[$derec][$item]['RECORD#1'], $this->deglresolveAmounts[$derec][$item]['RECORD#2']);
            }
            return $ok;
        }

        if ($cogsValues['EXCHANGE_RATE'] != 0) {
            $new_trx = ibcdiv($new_cost, $cogsValues['EXCHANGE_RATE'], 2, 1);   // round to 2 because THIS number matches the GL
        } else {
            $new_trx = $new_cost;
        }

        $old_trx  = $this->deglresolveAmounts[$derec][$item]['TRX_AMOUNT'];
        $trxDelta  = iround($new_trx - ($old_trx + $this->invCostToolHelper->cogsAdjustments($derec,false)),  2);  // false means 'return the TRX_AMOUNT, not the AMOUNT'

        // if things are the same, skip reading the old records.....
        if (($costDelta == 0) && ($trxDelta == 0)) {
            return $ok;
        }

        $d = $this->deglresolveAmounts[$derec][$item];
        $ok = $ok && $this->updateBatch($cogsValues, $d['GLENTRYKEY1'], $d['BATCHNO1'], $d['RECORD#1'], $costDelta, $trxDelta, $new_cost, $new_trx );
        $ok = $ok && $this->updateBatch($cogsValues, $d['GLENTRYKEY2'], $d['BATCHNO2'], $d['RECORD#2'], $costDelta, $trxDelta, $new_cost, $new_trx );
        return $ok;
    }

}
