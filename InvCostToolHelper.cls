<?php
/**
 * A collection of useful costing routines that are shared by the InvCostToolManager and other, similar functions.
 *
 * User: rcollins
 * Date: 12/27/2018
 * Time: 11:04 AM
 */




class InvCostToolHelper
{
    const       DEBUGGING   = true; // turn off to turn off the assertions

    const       NO_EFFECTIVE_DATE  = "01/01/2999";  // so we can compare dates against it

    const       MAX_ROWS_TO_RETURN_FOR_UI = 500;    // something reasonable; more than that gets too cumbersome

    const       MAX_SQL_ARRAY_SIZE = 200;        // only do up to 200 at a time....

    const       PRECISION       = 8;


    // These identify the kind of Cost Change History record entry, and is currently VISIBLE to the customer
    //      (so when we internationalize, we need to translate these)
    const       Type_Inbound    = 'INBOUND';
    const       Type_Updated    = 'UPDATED';
    const       Type_Added      = 'ADDED';
    const       Type_Deleted    = 'DELETED';
    const       Type_Seen       = 'SEEN';
    const       Type_Summary    = 'SUMMARY';

    const       EarliestDate    = "01-01-2000 01:01:01";

    // sql query cases.  See also invhlthrun.js::RespProcessor_Populate
    const       query_purchase          = 0;    //  _("Purchase, adjustment increase, build kit, or transfer in")
    const       query_disassembly       = 1;    //  _("Stockable kit disassembly")
    const       query_stdcost_change    = 2;    // _("Standard cost changed")
    const       query_deleted           = 3;    // _("Transaction(s) were deleted") (from whole txn delete (old))
    const       query_deleted2          = 4;    // _("Transaction(s) were deleted") (from delete log)
    const       query_never_ran_costing = 5;    // _("Costing not yet run on this item/warehouse")
    const       query_start_date_changed= 6;    // _("Inventory start date changed")



    /** @var string $runStartedAtOracleTime    The starting timestamp of the run according to oracle */
    private     $runStartedAtOracleTime = '';

    /** @var Lock $featureLock */
    private     $featureLock = null;            // will release when this object is destroyed

    /** @var string $costingMethods  Which costing methods do we want?  Average/Standard/Lifo/Fifo */
    private     $costingMethods = "'A', 'S', 'L', 'F'";

    /** @var array $currentItemWarehouseContext */
    private     $currentItemWarehouseContext = [];

    /** @var DateTime $startOftime */
    public     $startOftime = null;

    /** @var DateTime $startDateChangedOn */
    public     $startDateChangedOn;

    /** @var bool $invStartDateKnown  */
    public     $invStartDateKnown;

    /** @var CostChangeHistoryManager $costChangeHistoryManager */
    private     $costChangeHistoryManager;

    /** @var array $itemWarehouseInfo   stuff about the item/warehouse record */
    public     $itemWarehouseInfo = [];

    /** @var array $whatNeedsUpdating   stuff about the COGS sales/returns that can be effected */
    public     $whatNeedsUpdating = [];

    /** @var bool $quickRun   is this a quick or thorough run? */
    private    $quickRun = false;

    /** @var array $stockableKitsNeedingUpdate  has the item and docid by docentry */
    private     $stockableKitsNeedingUpdate;

    /** @var array $kitsWithKitsAsAComponent   given a kit, does it have one or more components that are kits? */
    private     $kitsWithKitsAsAComponent;

    /** @var string[]   $stockableKitsSortOrder  higher numbers means it should be recalc'd later than lower numbers */
    public      $stockableKitsSortOrder = [];


    /**
     * Constructor
     *
     * @param array $params
     */
    function __construct($params = array())
    {
        if ( ! isset($params['COSTMETHODCHECK'])) {
            $params['COSTMETHODCHECK'] = 'Average,Standard,FIFO,LIFO';
        }
        $this->costingMethods = '';
        $costingArray = [];

        if (strpos($params['COSTMETHODCHECK'], "Average") !== false) {
            $costingArray[] = "'A'";
        }
        if (strpos($params['COSTMETHODCHECK'], "Standard") !== false) {
            $costingArray[] = "'S'";
        }
        if (strpos($params['COSTMETHODCHECK'], "LIFO") !== false) {
            $costingArray[] = "'L'";
        }
        if (strpos($params['COSTMETHODCHECK'], "FIFO") !== false) {
            $costingArray[] = "'F'";
        }
        $this->costingMethods = implode(",", $costingArray); // like 'A','S'

        $invPrefs = array();
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
        if (($invPrefs['INVSTARTDATE'] ?? "") != "") {
            $this->startOftime        = DateTime::createFromFormat( 'm/d/Y', $invPrefs['INVSTARTDATE'] );
            $this->startDateChangedOn = DateTime::createFromFormat( 'm/d/Y', $invPrefs['INVSTARTDATECHANGEDON'] ?? GetCurrentDate(IADATE_SYSFORMAT) );
            $this->invStartDateKnown  = isset($invPrefs['INVSTARTDATECHANGEDON']);
        } else {
            $this->startOftime        = DateTime::createFromFormat( 'm/d/Y',"01/01/1970");
            $this->startDateChangedOn = DateTime::createFromFormat( 'm/d/Y',"01/01/1970");
            $this->invStartDateKnown  = true; // ya, known that we don't care....
        }
        // create assigns current time....
        $this->startOftime->setTime(0,0,1);
        $this->startDateChangedOn->setTime(23,59,59);   // last second of the day

        $this->runStartedAtOracleTime   = $this->getOracleTimeStamp();
        $this->costChangeHistoryManager = Globals::$g->gManagerFactory->getManager('costChangeHistory');

        $this->quickRun   = (($params['ANALYZE_OR_UPDATE'] == InvHlthRunManager::QuickAnalyze) || ($params['ANALYZE_OR_UPDATE'] == InvHlthRunManager::QuickUpdate));

        $this->stockableKitsNeedingUpdate = [];
        $this->kitsWithKitsAsAComponent   = null;
    }


    /**
     *      The MIV tool is starting to work on a new item/warehouse pair.
     *      Clear out and set up any caches or other support state.
     *
     *      Preconditions:
     *          This is either the FIRST time being called, or doneHandlingItemWarehouse() has been called
     *              prior to this
     *          An item/warehouse record exists for the given item/warehouse pair
     *
     * @param string    $itemId             the Item ID
     * @param string    $warehouseId        the Warehouse ID
     *
     * @return string
     */
    public function startHandlingNewItemWarehouse($itemId, $warehouseId)
    {
        if (self::DEBUGGING) {
            // note: I could call doneHandlingItemWarehouse() myself, but I don't have the right parameters for it!
            assert(empty($this->currentItemWarehouseContext), "doneHandlingItemWarehouse() should be called");
        }

        $this->currentItemWarehouseContext = [];    // free any old state (not strictly nescessary, but clearer)
        if (isset($this->itemWarehouseInfo[$itemId][$warehouseId])) {
            $this->currentItemWarehouseContext['ITEMID']              = $itemId;
            $this->currentItemWarehouseContext['WAREHOUSEID']         = $warehouseId;
            $this->currentItemWarehouseContext['TXNS']                = [];   // tracking for records
            $this->currentItemWarehouseContext['COST_METHOD']         = $this->itemWarehouseInfo[$itemId][$warehouseId]['COST_METHOD'];
            $this->currentItemWarehouseContext['COSTINGLASTRANONSQL'] = $this->itemWarehouseInfo[$itemId][$warehouseId]['COSTINGLASTRANONSQL'];
            $this->currentItemWarehouseContext['COSTINGLASTRANON']    = $this->itemWarehouseInfo[$itemId][$warehouseId]['COSTINGLASTRANON'];
            $this->currentItemWarehouseContext['TRACK']               = true;
        } else {
            $this->currentItemWarehouseContext['TRACK'] = false;
        }
        return $this->startDateForItemWarehouse($itemId, $warehouseId);
    }


    /**
     *  For this item and warehouse, when did costing last run?
     *  If it didn't run, then return null
     *
     * @param string      $itemId
     * @param string      $warehouseId
     * @param bool        $asTimestamp
     *
     * @return bool|string  the time, or false
     */
    public function costingLastRanOn($itemId, $warehouseId, $asTimestamp = false)
    {
        $format         = $asTimestamp ? 'm-d-Y H:i:s' : 'm/d/Y';
        $whenLastRan    = $this->itemWarehouseInfo[$itemId][$warehouseId]['COSTINGLASTRANON'] ?? null;
        // if this is a warehouse that didn't have changes, lets ASS-U-ME that the costing code last ran
        // at the same time as it ran on another warehouse for this item
        if (($whenLastRan === null) && (isset($this->itemWarehouseInfo[$itemId]))) {
            foreach ($this->itemWarehouseInfo[$itemId] as $warehouse) {
                $whenLastRan    = $warehouse['COSTINGLASTRANON'] ?? null;
                break;
            }
        }
        return ($whenLastRan === null) ? false : $whenLastRan->format($format);
    }


    /**
     *      What date should a given item/warehouse pair START on.
     *      Handles closed periods and customer-asked-for-start date
     *
     *
     * @param string    $itemId             the Item ID
     * @param string    $warehouseId        the Warehouse ID
     *
     * @return string                       the date
     */
    public function startDateForItemWarehouse($itemId, $warehouseId)
    {
        $startDate = '';
        if (isset($this->itemWarehouseInfo[$itemId][$warehouseId])) {

            // Escalation fix: (IA-120880 and others)
            // A changed purchase or sale could affect EARLIER documents in the case of
            // negative inventory, or other source/target settings that should be fixed.
            // The EARLIEST_EFFECTIVE_DATE is the date of earliest change, but STARTON is
            // the start of the open period (or other starting date)

            $startDate = $this->itemWarehouseInfo[$itemId][$warehouseId]['STARTON'] ?? '';
        } else {
            if (isset($this->itemWarehouseInfo[$itemId])) {
                foreach ($this->itemWarehouseInfo[$itemId] as $warehouseRec) {
                    $startOn = $warehouseRec['STARTON'] ?? '';
                    if (($startDate === '') || (MyCompareDate($startOn, $startDate) < 0)) {
                        $startDate = $startOn;  // take the earliest
                    }
                }
            }
        }
        return ($startDate === '') ? $this->startOftime->format('m/d/Y') : $startDate;
    }


    /**
     *      As the MIV tool is rippling through database rows (docentrycost records), and it ran the costing logic,
     *      this docentrycost record that affects COGS was altered in some way.
     *      Preconditions:
     *          startHandlingNewItemWarehouse(), above, has been called for the item/warehouse on this row
     *          the 'key' is the index into the table of rows, and is always POSITIVE
     *          the transaction affects COGS (even if this docentrycost record doesn't have a specific
     *              deglresolve for it, the docentry does)
     *
     *      Note: this is a local helper function
     *
     * @param int      $key            the key, or index, into the table inside InvCostToolManager
     * @param array    $row            the row that the key refers to
     * @param string   $type           How should this be saved as?  NEW, DELETED, UPDATED, what?
     *
     */
    private function saveThisLine($key, $row, $type)
    {
        if (self::DEBUGGING) {
            assert( ! empty($this->currentItemWarehouseContext), "startHandlingNewItemWarehouse() should be called");
            assert($key >= 0, "key is not a positive number");
        }

        if ($this->currentItemWarehouseContext['TRACK']) {

            $deRec      = $row['DEREC'];
            $rec        = ['KEY' => $key, 'TYPE' => $type];
            if (!isset($this->currentItemWarehouseContext['TXNS'][$deRec])) {   // on first rec only
                $rec['QOH']      = $row['SAVED_WHSE_QTY'];                             // the running quantity on hand
                $rec['QOH_COGS'] = $row['SAVED_WHSE_QTY_COGS'];
            }
            $decrec = $row['DECREC'];
            if ($type == self::Type_Added) {
                $decrec = $row['NEW_DECS'][0]['DECREC'];    // pick one that won't collide with existing records
            }
            $this->currentItemWarehouseContext['TXNS'][$deRec][$decrec] = $rec;   // using DECREC insures no dups
        }
    }


    /**
     *      As the MIV tool is rippling through database rows (docentrycost records), it came across this one.
     *      Preconditions:
     *          startHandlingNewItemWarehouse(), above, has been called for the item/warehouse on this row
     *          the 'key' is the index into the table of rows, and is always POSITIVE
     *          the date of last update on this row is ON OR AFTER the 'costing last ran on' date
     *
     *      We don't want to save a lot, because there can be 10,000+ transactions here....
     *
     *      Save references to INBOUND VALUE transactions only (assumption: caller has insured this)
     *
     * @param int      $key                 the key, or index, into the table inside InvCostToolManager
     * @param string[] $row                 the row that the key refers to
     *
     */
    public function noticeThisInboundLine($key, $row)
    {
        if (self::DEBUGGING) {
            assert( ($row['INOUT'] == 'I'), "expecting inbound value transactions only."); // can't check value here, have to trust the caller....
        }

        // Standard Cost items are NOT dependent on the inbound value transactions, but on changes to the standard costs.
        // so, here, we collect these transactions if this is NOT standard cost and was updated 'recently'
        if ($this->currentItemWarehouseContext['COST_METHOD'] != 'S') {

            // The first time you run a quick-run, we'll see EVERY inbound transaction.  Let's not bother
            //   to collect all those inbound transactions until you've run the tool at least once for this
            //   item/warehouse combo.  Otherwise we'll save thousands of non-important inbound transactions....
            if (($this->currentItemWarehouseContext['COSTINGLASTRANON'] != self::EarliestDate) &&
                ($this->dateIsGE( $row['LASTUPDATED'], $this->currentItemWarehouseContext['COSTINGLASTRANON'] ))) {
                $this->saveThisLine($key, $row, self::Type_Inbound);
            }
            // Note: if this is, say, a Sales Return with COGS, it may also be 'changed'/'added'/'deleted'
        }
    }


    /**
     *      As the MIV tool is rippling through database rows (docentrycost records), and it ran the costing logic,
     *      this docentrycost record was found to have changed.
     *      Preconditions:
     *          startHandlingNewItemWarehouse(), above, has been called for the item/warehouse on this row
     *          the 'key' is the index into the table of rows, and is always POSITIVE
     *          the transaction affects COGS (even if this docentrycost record doesn't have a specific
     *              deglresolve for it, the docentry does)
     *
     *      Note: this may be a NEW entry, where the prior entry was deleted
     *
     * @param int      $key                 the key, or index, into the table inside InvCostToolManager
     * @param string[] $row                 the row that the key refers to
     * @param bool     $newRecord           true means the record is new, false means it was just updated
     *
     */
    public function thisLineChanged($key, $row, $newRecord)
    {
        $this->saveThisLine($key, $row, $newRecord ? self::Type_Added : self::Type_Updated );

        // If the changed record is a docentrycostkits record,
        //      then we should update the stockabe kit too
        //      Note: we do NOT update disassembles
        if (($row['DECREC'] < 0) && ($row['DOCPARID'] == BUILD_KIT)) {
            $this->stockableKitsNeedingUpdate[$row['DEREC']] = [ $row['ITEM'], $row['DOCID'] ]; // the docentry item, not the cost item
        }
    }


    /**
     *      After costing was run on a directory, we found a record that should be in the cost change history table
     *          but it was DELETED by costing (and likely replaced by one or more docentrycosts)
     *
     *      Preconditions:
     *          startHandlingNewItemWarehouse(), above, has been called for the item/warehouse on this row
     *          the 'key' is the index into the table of rows, and is always POSITIVE
     *          the transaction affects COGS (even if this docentrycost record doesn't have a specific
     *              deglresolve for it, the docentry does)
     *
     * @param int       $key
     * @param string[]  $row     the row of the DELETED decrec
     */
    public function thisLineWasDeleted($key, $row)
    {
        $this->saveThisLine($key, $row, self::Type_Deleted );
    }


    /**
     *      After costing was run on a directory, we found a record that MAYBE should be in the cost change history table
     *          as it has COGS, but maybe it didn't change at all.
     *
     *      Preconditions:
     *          startHandlingNewItemWarehouse(), above, has been called for the item/warehouse on this row
     *          the 'key' is the index into the table of rows, and is always POSITIVE
     *          the transaction affects COGS (even if this docentrycost record doesn't have a specific
     *              deglresolve for it, the docentry does)
     *
     *  Here: the record MAY have already been seen by the ADDED/CHANGED logic above, but may not have been changed at all.
     *      The PURPOSE of this is so that we catch all docentrycosts for a docentry where something changed (so that the 'summary' record
     *      has all the data in it)
     *
     * @param int       $key
     * @param string[]  $row     the row of the DELETED decrec
     */
    public function thisLineWasSeen($key, $row)
    {
        $this->saveThisLine($key, $row, self::Type_Seen );
    }


    /**
     *      We have come to the end of a set of docentrycost records that all refer to the same item/warehouse
     *      combo.  So, now, we know if we need to write out some Cost Change History records, and we can take
     *      the time to get whatever additional information we may need.
     *
     *      Preconditions:
     *          The $rows is the SAME TABLE that was used to pass in the individual rows to
     *              noticeThisLine() and thisLineChanged() and thisLineWasDeleted(), above
     *              (meaning the '$key' values are still valid)
     *
     * @param array $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                              and thisLineWasDeleted()  refer to
     * @param callable $docPar      Information about the TD's (DOCPAR)
     * @param int[] $drecsToKeys    per doc header record number, the INDEX (key) into $rows
     * @param int[] $decrecsToKeys  per docentrycost record number, the INDEX (key) into $rows
     * @param array $deglresolveAmounts info about the past and planned deglresolve amounts
     * @param int   $hlthrunRecordNo the record# of the hlthrun record we will be saving
     * @param bool  $saveData       Should we save the data we collected to disk?
     *
     * @return bool                 did the writes go ok?
     *
     */
    public function doneHandlingItemWarehouse(&$rows, $docPar, $drecsToKeys, $decrecsToKeys, $deglresolveAmounts, $hlthrunRecordNo, $saveData)
    {
        $ok = true;

        // Are we even tracking this item and warehouse?
        if ($saveData && ($this->currentItemWarehouseContext['TRACK'] ?? false)) {

            // Did any records change?
            if (empty($this->currentItemWarehouseContext['TXNS']) == false) {   // faster than count > 0

                $item      = $this->currentItemWarehouseContext['ITEMID'];
                $warehouse = $this->currentItemWarehouseContext['WAREHOUSEID'];

                // We don't want the saved data to be overwhelming; we want stuff that REALLY CHANGED
                $this->removeSeenOnlyDocEntrys();
                $this->removePairedAddsAndDeletes($rows);

                // For FIFO and LIFO, we only need to show inbound value transactions that the changed COGS
                // refer to, either before the change or after the change.
                // And for standard, we only care about transactions IN THE WINDOW of changes
                $costMethod = $this->currentItemWarehouseContext['COST_METHOD'];
                if ($costMethod !== 'S') {
                    $this->reduceInboundForFifoLifo($rows); // well, AND average
                } else if (($costMethod == 'S') && isset($this->itemWarehouseInfo[$item][$warehouse]['CHANGE'])) {
                    if ($this->reduceStandardCost($rows, $this->itemWarehouseInfo[$item][$warehouse]['CHANGE'])) {
                        $ok = $ok && $this->writeOneStandardCostChangeRecord($this->itemWarehouseInfo[$item][$warehouse]['CHANGE'], $hlthrunRecordNo);
                    }
                }

                // If all we had were inbound then we're done.
                if ( ! $this->onlyInbound() ) {

                    // And, the whole reason we're here: cogs-affecting records
                    $ok = $ok && $this->writeOneDerecsRecord($rows, $docPar, $this->currentItemWarehouseContext['TXNS'], $drecsToKeys, $decrecsToKeys, $deglresolveAmounts, $hlthrunRecordNo);
                 }
            }
        }
        $this->currentItemWarehouseContext = [];    // free any old state

        if (!$ok) {
            // the caller doesn't check results and it would be akward for it to, so throw in the towel.
            throw new Exception("Cannot save the cost history records.");
        }
        return $ok;
    }


    /**
     *      Remove entries with only 'Type_Seen' entries.  Ya, we SAW the records, but nothing changed!
     */
    private function removeSeenOnlyDocEntrys()
    {
        $removeThese = [];
        foreach ($this->currentItemWarehouseContext['TXNS'] as $deRec => $oneDeRec) {
            $found = false;
            foreach ($oneDeRec as $entry) {
                if ($entry['TYPE'] != self::Type_Seen) {
                    $found = true;
                    break;
                }
            }
            if ($found == false) {
                $removeThese[] = $deRec;
            }
        }
        // now get rid of those records we SAW but did not change.
        foreach ($removeThese as $remove) {
            unset($this->currentItemWarehouseContext['TXNS'][$remove]);
        }
    }


    /**
     *      After all our pruning, are there only inbound records left?
     *
     * @return bool         are there ONLY inbound records left?
     */
    private function onlyInbound()
    {
        foreach ($this->currentItemWarehouseContext['TXNS'] as $oneDeRec) {
            foreach ($oneDeRec as $entry) {
                if ($entry['TYPE'] != self::Type_Inbound) {
                    return false;
                }
            }
        }
        if (self::DEBUGGING && !empty($this->currentItemWarehouseContext['TXNS'])) {
            logFL("There were only inbound transactions left, so not saving any");
        }
        return true;
    }


    /**
     *      If an entry is ONLY adds and deletes and they sum to zero, then remove them.
     *  This is not complete, and we'll do more later, but if we get, say, 80% here, then
     *  we can remove lots of otehr stuff as well.
     *
     * @param array  $rows          The data under consideration over in InvCostToolManager
     */
    private function removePairedAddsAndDeletes($rows)
    {
        $removeThese = [];
        foreach ($this->currentItemWarehouseContext['TXNS'] as $deRec => $oneDeRec) {
            $cogsBefore = 0;
            $cogsAfter  = 0;
            $inbound    = false;
            foreach ($oneDeRec as $rec) {
                $type = $rec['TYPE'];
                $row  = $rows[$rec['KEY']];

                switch ($type) {
                    case self::Type_Inbound:
                        $inbound    = true;
                        break;

                    case self::Type_Added:
                        foreach($row['NEW_DECS'] as $after) {
                            $cogsAfter = ibcadd($cogsAfter, $after['COGS'], self::PRECISION, true);
                        }
                        $inbound    = false;
                        break;

                    case self::Type_Seen:
                        $inbound    = false;
                        // fall through
                    case self::Type_Updated:
                        $before = $row;
                        $after  = $row['FIXES'];
                        $cogsBefore = ibcadd($cogsBefore, $before['COGS'], self::PRECISION, true);
                        $cogsAfter  = ibcadd($cogsAfter,  $after[ 'COGS'], self::PRECISION, true);
                        break;

                    case self::Type_Deleted:
                        $before     = $row;  // stuff was there before, but not after
                        $cogsBefore = ibcadd($cogsBefore, $before['COGS'], self::PRECISION, true);
                        $inbound    = false;
                        break;
                }
            }

            // If the COGS have not changed, then let's remove this
            if ( ! $inbound && ($cogsBefore == $cogsAfter)) {
                $removeThese[] = $deRec;
            }
        }

        // now get rid of those records we SAW but did not really change.
        foreach ($removeThese as $remove) {
            unset($this->currentItemWarehouseContext['TXNS'][$remove]);
        }
    }


    /**
     *      With standard cost items, we looked for standard costs that changed since the last costing run.
     *          And that may have gotten us LOTS of changes (especially the very first time we run costing)
     *          Many of the entries may not directly impact COGS sales, and so we want to trim down the
     *          list of changes to those that could possibly have changed COGS sales that were updated in this run.
     *
     *      So if a COGS sale happened on 3/7, we don't care about changes made after that OR changes made prior
     *      to the effective date that includes the date of the sale.
     *
     * Assumption: we KNOW that there is at least one standard cost change for the current item/warehouse
     * Assumption: the list is in effective date order, ascending
     *
     * @param array $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                              and thisLineWasDeleted()  refer to
     * @param array $scChange       static stuff about this standard cost's change entry in the itemwarehouse record
     *
     * @return bool                 are there any transactions within the band of changes to standard costs?
     */
    private function reduceStandardCost(&$rows, $scChange)
    {
        $deRecsToRemove = [];
        $anyFound       = false;
        foreach ($this->currentItemWarehouseContext['TXNS'] as $deRec => $deRecInfo) {
            foreach($deRecInfo as $rec) {
                $date  = $rows[$rec['KEY']]['DOCDATE'];     // There's at least one, and they all have the same docdate
                $found = false;
                foreach ($scChange as $change) {
                    if ((MyCompareDate($change['DATE'], $date) <= 0) &&
                        (MyCompareDate($change['MAX_DATE'], $date) > 0)) {
                        $found    = true;
                        $anyFound = true;
                        break;
                    }
                }
                // is this transaction in a time range that changed?
                if ( ! $found) {
                    $deRecsToRemove[] = $deRec;
                }
                break;  // all records for this derec have the same docdate, so only need one per derec
            }
        }

        // The following transactions were NOT affected by the changes to the standard costs
        foreach ($deRecsToRemove as $deRec) {
            unset($this->currentItemWarehouseContext['TXNS'][$deRec]);
        }
        return $anyFound;
    }


    /**
     *      When in FIFO/LIFO, we care about the inbound transactions ONLY if they affected one or more of the
     *          changed COGS transactions.
     *
     *      For example, you backdate receipt of 100 new hammers and that causes a subsequent sale to change.
     *      We want to see that.  But if it wasn't the source transaction for one of the changed transactions,
     *      then we don't need to see that.
     *
     * @param array $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                              and thisLineWasDeleted()  refer to
     */
    private function reduceInboundForFifoLifo(&$rows)
    {
        // I think it would be confusing if we remove some docentrycost records but not others for a given inbound
        // transaction, so lets remove the entire docentry with all its docentrycosts, or keep them all.

        // Step one is to make an index of the docentrycost records we have ....
        $inputDecrecs = [];
        foreach ($this->currentItemWarehouseContext['TXNS'] as $inputRecs) {
            foreach ($inputRecs as $decRec => $rec) {
                if ($rec['TYPE'] == self::Type_Inbound) {
                    $inputDecrecs[$decRec] = false;   // false means we have not seen it in the outbound yet....
                }
            }
        }

        foreach ($this->currentItemWarehouseContext['TXNS'] as $derecEntries) {
            foreach ($derecEntries as $rec) {
                switch ($rec['TYPE']) {
                    case self::Type_Added:
                        foreach ($rows[$rec['KEY']]['NEW_DECS'] as $added) {
                            $source = $added['DECREF'] ?? 0;
                            if (isset($inputDecrecs[$source])) {
                                $inputDecrecs[$source] = true; // found you!
                            }
                        }
                        break;

                    case self::Type_Updated:

                        $source = $rows[$rec['KEY']]['FIXES']['DECREF'] ?? 0;    // after the update (might be the same)
                        if (isset($inputDecrecs[$source])) {
                            $inputDecrecs[$source] = true; // found you!
                        }
                        break;

                    case self::Type_Deleted:
                    case self::Type_Inbound:
                    case self::Type_Seen:
                        break;
                }
            }
        }

        // Finally, go back to the inbound and remove any that are not referenced.
        $derecsToRemove = [];
        foreach ($this->currentItemWarehouseContext['TXNS'] as $derec => $inputRecs) {
            $saveInbound = false;
            $isInbound   = false;
            foreach ($inputRecs as $decrec => $rec) {
                $isInbound   = false;
                if ($rec['TYPE'] == self::Type_Inbound) {
                    $isInbound = true;  // this derec is inbound
                    if ($inputDecrecs[$decrec] === true) {
                        $saveInbound = true;
                        break;
                    }
                }
            }

            // if ANY docentrycost is being saved, we save the whole docentry.  But, if NONE are, we can delete it.
            if ($isInbound && ($saveInbound === false)) {
                $derecsToRemove[] = $derec; // remove them outside this loop just to avoid any problems with links
            }
        }

        // do this outside the above loop so as to not cause insanity on the loop/copy on write/etc.
        foreach ($derecsToRemove as $derec) {
            unset($this->currentItemWarehouseContext['TXNS'][$derec]);   // remove the derec from the list
        }
    }


    /**
     *      We have come to the end of a set of docentrycost records that all refer to the same item/warehouse
     *      combo.  So, now, we know if we need to write out some Cost Change History records, and we can take
     *      the time to get whatever additional information we may need.
     *
     *      Preconditions:
     *          The $rows is the SAME TABLE that was used to pass in the individual rows to
     *              noticeThisLine() and thisLineChanged() and thisLineWasDeleted(), above
     *              (meaning the '$key' values are still valid)
     *
     * @param array $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                              and thisLineWasDeleted()  refer to
     * @param callable  $docPar     Information about the TD's (DOCPAR)
     * @param array $derecs         the array of DEREC's docentrycost records
     *                                  (format is [derec][]['KEY'=>key, 'TYPE'=>type])
     * @param int[] $drecsToKeys    per doc header record number, the INDEX (key) into $rows
     * @param int[] $decrecsToKeys  per docentrycost record number, the INDEX (key) into $rows
     * @param array $deglresolveAmounts info about the past and planned deglresolve amounts
     * @param int   $hlthrunRecordNo the hlthrun record# we will be saving
     *
     * @return bool                 did the writes go ok?
     *
     */
    private function writeOneDerecsRecord(&$rows, $docPar, $derecs, $drecsToKeys, $decrecsToKeys, $deglresolveAmounts, $hlthrunRecordNo)
    {
        // outer index is the docentry record number
        foreach ($derecs as $inputRecs) {
            // all of this loop belong to the same docentry:
            $cchRecs   = [];
            $summary   = [];
            $firstTime = true;
            $closed    = true;
            $inboundUpdatedSinceLastRun = false;
            foreach ($inputRecs as $rec) {  // key is the index into the $rows array above
                $key        = $rec['KEY'];
                $row        = $rows[$key];
                if ($firstTime) {
                    $summary    = $this->buildSummaryCostChangeHistoryRecord($rows, $rec, $docPar, $drecsToKeys, $deglresolveAmounts);
                    $firstTime  = false;
                    $closed     = $row['NOGLCHANGES'];    // is this a closed period?
                }
                // both the first and subsequent times, handle the details portion of the record....
                $type = $rec['TYPE'];
                switch ($type) {

                    case self::Type_Inbound:
                        $inboundUpdatedSinceLastRun = true; // we filtered out other inbounds
                        $before = $row;  // before and after are the same
                        $after  = $row;
                        $cchRecs[]     = $this->buildDetailCostChangeHistoryRecord($rows, $before, $after, $summary, $decrecsToKeys, $type, $key);
                        break;

                    case self::Type_Added:
                        $before = [];   // one entry represents all added recs
                        foreach($row['NEW_DECS'] as $after) {
                            $cchRecs[] = $this->buildDetailCostChangeHistoryRecord($rows, $before, $after, $summary, $decrecsToKeys, $type, $key);
                        }
                        break;

                    case self::Type_Updated:
                        $before = $row;
                        $after  = $row['FIXES'];
                        $cchRecs[]     = $this->buildDetailCostChangeHistoryRecord($rows, $before, $after, $summary, $decrecsToKeys, $type, $key);
                        break;

                    case self::Type_Deleted:
                        $before = $row;  // stuff was there before, but not after
                        $after  = [];
                        $cchRecs[]     = $this->buildDetailCostChangeHistoryRecord($rows, $before, $after, $summary, $decrecsToKeys, $type, $key);
                        break;

                    case self::Type_Seen:
                        $before = $row;  // before and after are the same
                        $after  = $before;
                        $cchRecs[]     = $this->buildDetailCostChangeHistoryRecord($rows, $before, $after, $summary, $decrecsToKeys, $type, $key);
                        break;

                    default:
                        assert(false);  // something is very wrong
                        // break;
                }
            }

            // Do this final calculation if we're in a closed period
            if (($summary['COGSPOSTEDAFTER'] !== null) && $closed) {
                $summary['COGSADJUSTMENTNEEDED'] = $this->formatForGL($summary['VALUEAFTER'] - $summary['COGSPOSTEDAFTER'] - $summary['COGSADJUSTMENTSPOSTED']);
            }

            // If there is only one record, then the summary and detail record is the same.
            // if there is more than one record, there is a summary and a collection of details.
            //      in that case the first record that we made into the summary is really a detail record too.
            //      since we saved it above in its 'detail' form (not summed from all the other records),
            //      save again as a summary record.
            if (count($cchRecs) == 1) { // if there are no detail records beyond the summary,
                $cchRecs[0]['ISASUMMARY']            = 'true';   // mark that first record as a summary record too
                $cchRecs[0]['COGSADJUSTMENTNEEDED']  = $summary['COGSADJUSTMENTNEEDED'];    // copy these over from the summary record we built
                $cchRecs[0]['COGSADJUSTMENTSPOSTED'] = $summary['COGSADJUSTMENTSPOSTED'];
                $cchRecs[0]['COGSPOSTEDBEFORE']      = $summary['COGSPOSTEDBEFORE'];
                $cchRecs[0]['COGSPOSTEDAFTER']       = $summary['COGSPOSTEDAFTER'];
                $cchRecs[0]['STATE']                 = $summary['STATE'];
            } else {
                $summary['ISASUMMARY'] = 'true';
                $summary['ISADETAIL']  = 'false';
                array_unshift($cchRecs,$summary);   // insert the summary before the rest
            }

            // NOTE: cost change history is an OWNED OBJECT of hlthrun, so normally we'd add this to the CHANGES array
            //      of the hlthrun record and let the EntityManager take care of everything.
            //  BUT
            //      There could be thousaands of records here and, with everything else in the MIV tool, I'm worried
            //      that we'll run out of ram.  When the UI wants to READ these records, at least it isn't doing
            //      anything else, so that should work better.
            //  ALSO
            //      we're in a transaction, so everything gets saved or nothing, so we won't have orphaned records here
            //
            // Keep all inbound, and only outbound where the summary changed.
            if ( !empty($cchRecs) && ($inboundUpdatedSinceLastRun || $this->summaryRecordHasCostChanges($cchRecs[0]))) {

                // Record that this item/warehouse record had significan updates, and so we can set the 'last recalc' time.
                $item      = $this->currentItemWarehouseContext['ITEMID'];
                $warehouse = $this->currentItemWarehouseContext['WAREHOUSEID'];
                $this->itemWarehouseInfo[$item][$warehouse]['HAD_UPDATES'] = true;
                foreach ($cchRecs as &$cchRec) {
                    $cchRec['HLTHRUNKEY'] = $hlthrunRecordNo;   // this is the hlthrun record# we intend to write
                    $this->DoRounding($cchRec);
                    if (!$this->costChangeHistoryManager->add($cchRec)) {
                        return false;
                    }
                    $key = $cchRec['KEY'] ?? -1;
                    if ($key >= 0) {
                        $rows[$key]['CCH_SAVED'] = true;
                    }
                }
            }
        }
        return true;
    }


    /**
     *      Changing a standard cost is not a transaction, but I want to record it in the table anyway.  So.... take some liberties....
     *
     * @param string[]       $change          What was the change?
     *                                        $change is: COST, DATE, WHENCREATED, WHENMODIFIED, CREATEDBY, MODIFIEDBY
     * @param int   $hlthrunRecordNo the record# of the hlthrun record we will be saving
     *
     * @return bool         Did the write go ok?
     */
    private function writeOneStandardCostChangeRecord($change, $hlthrunRecordNo)
    {
        // These came from the database directly; convert them into their EXTERNAL form so the Entity Manager
        // can convert them back to their INTERNAL form.
        global $gCostMethodValues, $gCostMethodInternalValues;
        $method                         = array_search( $this->currentItemWarehouseContext['COST_METHOD'], $gCostMethodInternalValues );
        if ($method !== false) {
            $method                     = $gCostMethodValues[$method];
        }

        // fill in the costChangeHistory record; most things will be null.
        $cchRow = [
            'COSTINGUPDATEDON'          => $this->runStartedAtOracleTime,                       // the time range in which the costing changed for the item/warehouse
            'PRIORCOSTINGUPDATEDON'     => $this->currentItemWarehouseContext['COSTINGLASTRANONSQL'],
            'ISASUMMARY'                => 'true',               // so it shows on both summary and detail reports
            'ISADETAIL'                 => 'true',

            'TRANSACTIONEFFECTIVEDATE'  => $change['DATE'],                                     // the transaction's AS OF date
            'TRANSACTIONNAME'           => _("STANDARD COST CHANGE"),
            'TRANSACTIONID'             => "",
            'ITEMID'                    => $this->currentItemWarehouseContext['ITEMID'],
            'WAREHOUSEID'               => $this->currentItemWarehouseContext['WAREHOUSEID'],
            'UNITCOSTAFTER'             => $change['COST'],
            'COSTMETHOD'                => $method,

            'TXNCREATEDDATE'            => $change['WHENCREATED'],           // when the transaction was created
            'TXNCREATEDBY'              => $change['CREATEDBY'],             // who created it
            'TXNMODIFIEDDATE'           => $change['WHENMODIFIED'],          // when the transaction was modified
            'TXNMODIFIEDBY'             => $change['MODIFIEDBY'],            // who modified it
            'STATE'                     => 'STDCOSTCHANGE',
            'NOTES'                     => _("Period ends on ") . $change['MAX_DATE'],

            'HLTHRUNKEY'                => $hlthrunRecordNo,
            ];
        $this->DoRounding($cchRow);
        return (bool)$this->costChangeHistoryManager->add($cchRow);
    }


    /**
     *      Once in a while, one of the numbers we're trying to save is in E format because it has a tiny tiny
     *  fraction.  Here we round things to a reasonable size....
     *
     * @param array $cchRow     A Cost Chnge History record, ready to be saved to sql
     *
     */
    protected function DoRounding(&$cchRow)
    {
        $numericFields = [
            'QUANTITYBEFORE',
            'QUANTITYAFTER',
            'QUANTITYQOH',
            'VALUEQOH',
            'UNITCOSTBEFORE',
            'UNITCOSTAFTER',
            'VALUEBEFORE',
            'VALUEAFTER',
            'COGSPOSTEDBEFORE',
            'COGSPOSTEDAFTER',
            'COGSADJUSTMENTSPOSTED',
            'COGSADJUSTMENTNEEDED',
        ];

        foreach ($numericFields as $numericField) {
            $cchRow[$numericField] = iround($cchRow[$numericField], self::PRECISION);
        }
    }


    /**
     *      Does the summary record have COSTING changes?
     *
     *      The idea is that if we have found, say, an ADD and a DELETE that, in summary, don't change the costs,
     *  well, then why do we care?  That is the mechanics of the costing logic at work.  You can always look at the
     *  COGS report to see those details.
     *
     * @param array   $summary          The summary cost change history record
     *
     * @return bool                     Are there changes to the costing?
     *
     */
    private function summaryRecordHasCostChanges($summary)
    {
        // pairs of fields we care about; if the pair doesn't match there was a change.
        $changesWeCareAbount = [
            ['QUANTITYBEFORE',   'QUANTITYAFTER'],
            ['UNITCOSTBEFORE',   'UNITCOSTAFTER'],
            ['VALUEBEFORE',      'VALUEAFTER'],
            ['COGSPOSTEDBEFORE', 'COGSPOSTEDAFTER'],
        ];

        foreach ($changesWeCareAbount as $change) {
            if ($summary[$change[0]] != $summary[$change[1]]) {
                return true;
            }
        }
        return false;
    }


    /**
     * @param array     $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                                  and thisLineWasDeleted()  refer to
     * @param array     $row            current row from the above table
     * @param int[]     $decrecsToKeys  per docentrycost record number, the INDEX (key) into $rows
     *
     * @return string|null          the document id name, like 'Sales Invoice-abc123'
     */
    private function getSourceName($rows, $row, $decrecsToKeys)
    {
        $sourceTxn    = null;
        $sourceTxnKey = $row['DECREF'] ?? 0;  // the doc entry cost we came from
        if ($sourceTxnKey) {
            $rowKey = $decrecsToKeys[$sourceTxnKey] ?? -1;    // turn record number into index
            if ($rowKey >= 0) {
                $sourceTxn = $rows[$rowKey]['DOCID'];   // the full name, like 'Sales Invoice-abc123'
            }
        }
        return $sourceTxn;
    }


    /**
     *      Take a record in the costToolManager format and map it to the costChangeHistory format.
     *      This will be a summary record, and so entails a little more work than a detail record.
     *
     * @param array     $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                                  and thisLineWasDeleted()  refer to
     * @param string[]  $derecInfo      the info for the DEREC (where in $rows, type of entry, and QOH values)
     * @@param callable $docParCallable Information about the TD's (DOCPAR)
     * @param int[]     $drecsToKeys    per doc header record number, the INDEX (key) into $rows
     * @param array $deglresolveAmounts info about the past and planned deglresolve amounts
     *
     * @return string[]                 The resulting record, a summary record.
     *
     */
    private function buildSummaryCostChangeHistoryRecord(&$rows, $derecInfo, $docParCallable, $drecsToKeys, $deglresolveAmounts)
    {
        global $gCostMethodValues, $gCostMethodInternalValues;

        $costToolRow = $rows[$derecInfo['KEY']];
        $docpar      = $docParCallable($costToolRow['DOCPARKEY']);

        $updinv = $docpar['UPDINV'];
        if ($updinv == 'T') {
            $updinv = 'QV'; // so it is easier to explain and looks like other areas of the product
        }

        // If there is a created-from, get the name.  Rather than re-look up from sql, see if it is in our cache....
        $createdFrom    = '';
        $createdFromKey = $costToolRow['CREATEDFROM'] ?? 0;  // the record number of the docheader
        if ($createdFromKey > 0) {
            $rowKey = $drecsToKeys[$createdFromKey] ?? -1;  // turn dochdr record number into an index
            if ($rowKey >= 0) {
                $createdFrom = $rows[$rowKey]['DOCID'];   // the full name, like 'Sales Invoice-abc123'
            }
        }

        $derec       = $costToolRow['DEREC'];
        $item        = $this->currentItemWarehouseContext['ITEMID'];
        $cogsBefore  = null;
        $cogsAfter   = null;
        if (isset($deglresolveAmounts[$derec][$item])) {
            $cogsBefore = $this->formatForGL($deglresolveAmounts[$derec][$item]['AMOUNT']       ?? '0.00');
            $cogsAfter  = $cogsBefore;
            if ($deglresolveAmounts[$derec][$item]['COST_UPDATED']) {
                $cogsAfter = $this->formatForGL($deglresolveAmounts[$derec][$item]['CURRENT_COST'] ?? '0.00');
            }
        }

        $whencreated = $costToolRow['AUWHENCREATED'];

        // These came from the database directly; convert them into their EXTERNAL form so the Entity Manager
        // can convert them back to their INTERNAL form.
        $method                         = array_search( $this->currentItemWarehouseContext['COST_METHOD'], $gCostMethodInternalValues );
        if ($method !== false) {
            $method                     = $gCostMethodValues[$method];
        }

        $state = self::Type_Summary;
        if ($docpar['SPI'] == 'S') {
            $state = ($docpar['IN_OUT'] != 'I') ?_("Sale") : _("Return");
        } elseif ($docpar['SPI'] == 'P') {
            $state = ($docpar['IN_OUT'] != 'I') ?_("Purch rtn") : _("Purchase");
        }

        // fill in the costChangeHistory record
        $cchRow = [
            'COSTINGUPDATEDON'          => $this->runStartedAtOracleTime,                       // the time range in which the costing changed for the item/warehouse
            'PRIORCOSTINGUPDATEDON'     => $this->currentItemWarehouseContext['COSTINGLASTRANONSQL'],

            'TRANSACTIONEFFECTIVEDATE'  => $costToolRow['DOCDATE'],                                     // the transaction's AS OF date
            'TRANSACTIONNAME'           => $docpar['DOCPARID'],                                   // the TD name, like 'Sales Invoice'
            'TRANSACTIONID'             => $costToolRow['DOCNO'],                                       // the transaction ID part of the name, like 'ABC123'
            'ITEMID'                    => $item,
            'WAREHOUSEID'               => $this->currentItemWarehouseContext['WAREHOUSEID'],

            // the detail records will ADD these to this summary
            'QUANTITYBEFORE'            => 0.0,                     // BEFORE values are BEFORE costing code ran; AFTER are after it ran
            'QUANTITYAFTER'             => 0.0,
            'QUANTITYQOH'               => $derecInfo['QOH'],       // running quantity on hand for quantity transactions
            'VALUEQOH'                  => $derecInfo['QOH_COGS'],  // same for value transactions
            'UNITCOSTBEFORE'            => '0.00',                  // base unit cost, not transaction unit cost
            'UNITCOSTAFTER'             => '0.00',
            'VALUEBEFORE'               => '0.00',                  // QUANTITYBEFORE * UNITCOSTBEFORE if a value transaction
            'VALUEAFTER'                => '0.00',                  // QUANTITYAFTER  * UNITCOSTAFTER  if a value transaction
            'COGSPOSTEDBEFORE'          => $cogsBefore,             // what had been posted
            'COGSPOSTEDAFTER'           => $cogsAfter,              // what we HOPE will be posted

            // back to stuff filled in once
            'COGSADJUSTMENTSPOSTED'     => $this->formatForGL( $this->cogsAdjustments($derec)), // adjustments made through the Cogs Closed Adjustments tool
            'COGSADJUSTMENTNEEDED'      => '0.00',                                              // Adjustments needed through COGS CLOSED JE tool (Value After -  COGS Posted After - COGS Adjustments Posted) (SUMMARY ONLY)
            'COGSCLOSED'                => (($costToolRow['NOGLCHANGES']) ? 'true' : 'false'),  // is the period or COGS batch closed (and so not updateable)?
            'SALEPURCHASEORINTERNAL'    => $docpar['SPI'],                                      // S, P, or I for Sales, Purchase, or Internal transaction (like a transfer or adjustment)
            'INCREMENTORDECREMENT'      => (($docpar['IN_OUT'] == 'I') ? 'I' : 'D'),            // I or D; I increases QOH, D decreases QOH
            'QUANTITYORVALUE'           => $updinv,                                             // N, Q, V, or QV (this mimics the existing transaction records), (N means NONE)
            'COSTMETHOD'                => $method,                                             // (A)verage, (F)IFO, (L)IFO, or (S)tandard
            'CONVERTEDFROMTRANSACTION'  => $createdFrom,                                        // transaction this transaction was converted FROM (like Sales Invoice-ABC1234)

            'TXNCREATEDDATE'            => $whencreated,                         // when the transaction was created
            'TXNCREATEDBY'              => $costToolRow['CREATEDBY'],            // who created it
            'TXNMODIFIEDDATE'           => $costToolRow['WHENMODIFIED'],         // when the transaction was modified
            'TXNMODIFIEDBY'             => $costToolRow['MODIFIEDBY'],           // who modified it
            'NOTES'                     => "",
            'STATE'                     => $state,

            // These will be the 'running' quantity on hands, and are NOT saved in the database
            // They are only useful to the detail records.
            'RUNNING_QUANTITYQOH'       => $derecInfo['QOH'],       // running quantity on hand for quantity transactions
            'RUNNING_VALUEQOH'          => $derecInfo['QOH_COGS'],  // same for value transactions
        ];

        // removing this because of the shenanigans with Q and V layers
        /* ******
        if ($costToolRow['AFFECTS_INVENTORY'] != $updinv) {
            $this->addToNote( $cchRow['NOTES'], "UPDATES INVENTORY used to be " . $costToolRow['AFFECTS_INVENTORY'] . ", but now is " . $updinv );
        }
        ********** */

        $this->addToNote($cchRow['NOTES'], "DeRec: $derec");   // for escalation debugging

        return $cchRow;
    }


    /**
     *      Take a record in the costToolManager format and map it to the costChangeHistory format.
     *      This will be a detail record, and so entails work than a summary record.
     *      Update the summary record with sums where appropriate.
     *
     * @param array     $rows           the table that the keys from noticeThisLine(), thisLineChanged(),
     *                                  and thisLineWasDeleted()  refer to
     * @param string[]  $beforeRow      the cost tool manager data row from before the change (may be EMPTY)
     * @param string[]  $afterRow       the cost tool manager data row from after the change (may be EMPTY)
     * @param string[]  $summaryRecord  The running summary, in costChangeHistory format.
     * @param int[]     $decrecsToKeys  per docentrycost record number, the INDEX (key) into $rows
     * @param string    $state          is the record ADDED/DELETD/what?
     * @param int       $key            the index into the rows array for this change
     *
     * @return string[]                 The resulting record, a summary record.
     *
     */
    private function buildDetailCostChangeHistoryRecord(&$rows, $beforeRow, $afterRow, &$summaryRecord, $decrecsToKeys, $state, $key)
    {

        // If there is a source transaction, let's get the name.
        $sourceTxnBefore = $this->getSourceName($rows, $beforeRow, $decrecsToKeys);
        $sourceTxnAfter  = $this->getSourceName($rows, $afterRow,  $decrecsToKeys);
        $qoh             = $summaryRecord['RUNNING_QUANTITYQOH'];
        $valueQoh        = $summaryRecord['RUNNING_VALUEQOH'];

        // Make the quantites positive, or leave them empty/null
        if (isset($beforeRow['QUANTITY'])) {
            $beforeRow['QUANTITY'] = ibcabs($beforeRow['QUANTITY']);
        }
        if (isset($afterRow['QUANTITY'])) {
            $afterRow['QUANTITY'] = ibcabs($afterRow['QUANTITY']);
        }


        // Get common things from the summary record, so we don't need to get them again.
        // Then things that are different, some of which 'roll up' to the summary record.
        $cchRow = array_merge( $summaryRecord, [

            'ISASUMMARY'                => 'false',               // summary means the SUM(docentrycost); if one docentrycost, then is both SUMMARY AND DETAIL
            'ISADETAIL'                 => 'true',                // one docentrycost record

            'QUANTITYBEFORE'            => $beforeRow['QUANTITY'] ?? null,          // BEFORE values are BEFORE costing code ran; AFTER are after it ran
            'QUANTITYAFTER'             => $afterRow['QUANTITY']  ?? null,
            'QUANTITYQOH'               => $qoh,                                    // running quantity on hand for quantity transactions using QUANTITYBEFORE
            'VALUEQOH'                  => $valueQoh,                               // same for value transactions using QUANTITYBEFORE
            'UNITCOSTBEFORE'            => $beforeRow['UNITCOST'] ?? null,          // base unit cost, not transaction unit cost
            'UNITCOSTAFTER'             => $afterRow['UNITCOST']  ?? null,
            'VALUEBEFORE'               => $beforeRow['COGS'] ?? null,              // QUANTITYBEFORE * UNITCOSTBEFORE if a value transaction
            'VALUEAFTER'                => $afterRow['COGS']  ?? null,              // QUANTITYAFTER  * UNITCOSTAFTER  if a value transaction

            'SOURCETRANSACTIONBEFORE'   => $sourceTxnBefore,                        // like Purchase Receiver-ABX123
            'SOURCETRANSACTIONAFTER'    => $sourceTxnAfter,                         // like Purchase Receiver-ABX123

            'STATE'                     => $state,

            // we DON'T want these in detail records:
            'COGSADJUSTMENTNEEDED'      => null,
            'COGSADJUSTMENTSPOSTED'     => null,
            'COGSPOSTEDBEFORE'          => null,
            'COGSPOSTEDAFTER'           => null,
            'KEY'                       => $key,

        ]);   // the costChangeHistory row

        $summaryRecord['QUANTITYBEFORE'] += $cchRow['QUANTITYBEFORE'];
        $summaryRecord['QUANTITYAFTER']  += $cchRow['QUANTITYAFTER'];
        $summaryRecord['VALUEBEFORE']    += $cchRow['VALUEBEFORE'];
        $summaryRecord['VALUEAFTER']     += $cchRow['VALUEAFTER'];

        // Compute the overall unit costs
        $summaryRecord['UNITCOSTBEFORE'] = (($summaryRecord['QUANTITYBEFORE'] != 0) ? iround($summaryRecord['VALUEBEFORE'] / $summaryRecord['QUANTITYBEFORE'],self::PRECISION) : 0.0);
        $summaryRecord['UNITCOSTAFTER']  = (($summaryRecord['QUANTITYAFTER']  != 0) ? iround($summaryRecord['VALUEAFTER']  / $summaryRecord['QUANTITYAFTER'], self::PRECISION) : 0.0);

        // Compute the running quantity on hand
        $change = ($afterRow['QUANTITY'] ?? ($beforeRow['QUANTITY'] ?? 0.0));
        if ($state == self::Type_Deleted) {
            $change = - ($change);
        }
        if (($summaryRecord['QUANTITYORVALUE'] == 'Q') || ($summaryRecord['QUANTITYORVALUE'] == 'QV')) {
            $qoh += $change;
        }
        if (($summaryRecord['QUANTITYORVALUE'] == 'V') || ($summaryRecord['QUANTITYORVALUE'] == 'QV')) {
            $valueQoh += $change;
        }

        $summaryRecord['RUNNING_QUANTITYQOH'] = $qoh; // so these get paseed onto the next detail record
        $summaryRecord['RUNNING_VALUEQOH']    = $valueQoh;

        $decrec = $beforeRow['DECREC'] ?? $afterRow['DECREC'];  // one or the other should have the docentrycost record#
        $this->addToNote( $cchRow['NOTES'], "DecRec: $decrec");       // for escalation debugging

        return $cchRow;
    }




    //  ******************************************************************************************
    //  ******************************************************************************************
    //
    //      GATHER INFO ABOUT WHAT ITEM/WAREHOUSES NEED TO BE UPDATED
    //
    //  ******************************************************************************************
    //  ******************************************************************************************




    /**
     *      Get data for the client.  There are two 'modes' we operate under here:
     *  QUICK - the 'new' update-only-things-that-have-changed mechanism, and
     *  THOROUGH - the 'old' update-everthing-nuder-the-sun mechanism.
     *
     *      And, within QUICK, there are two clients:
     *  MIV - we want to run costing code against the item/warehouses that need checking, and
     *  UI - we want to show the customer WHAT COGS transactions (sales/returns) may change
     *
     *  THOROUGH mode gets ALL item/warehouse records so we can track what changes and save it in our cost history table
     *
     *  QUICK MIV mode gets the list of item/warehouse records where there has been a change since the last MIV run
     *          (or there wasn't a run, or the 'costing must run' flag is on) AND there are subsequent COGS transactions.
     *          The item/warehouse table is the same format ias the THOROUGH mode above.
     *
     *  QUICK UI mode ('return sales details' == true) does the same kind if query as the above, but we don't want the
     *          item/warehouse data so much as we want the list of COGS transactions!  So, same basic query, but different
     *          results to be returned.
     *
     *
     *
     * @param string    $itemGLGroup                The item group
     * @param string    $item                       optional item name for the BOTTOMN of the item range
     * @param string    $toItem                     optional item name for the TOP of the item range
     * @param string    $warehouse                  optional warehouse name
     * @param bool      $runAsIfQuick               Caller wants to simulate a quick run
     * @param string    $dateToStartReadingRecords  In --> earliest date, Out ---> updated earliest date
     *
     * @return bool                                 Did this work?
     *
     *  assumption: if $item is not empty, then $toItem is not empty
     */
    public function getItemWarehouseTimers($itemGLGroup, $item, $toItem, $warehouse, $runAsIfQuick, &$dateToStartReadingRecords)
    {
        if (self::DEBUGGING) {
            // assumption: if $item is not empty, then $toItem is not empty
            assert((($item != '') === ($toItem != '')), "item and to-item must both be empty or both not empty");
        }

        if ($this->costingMethods == "") {
           return true;    // not sure it is an ERROR, but there is nothing to do.
        }


        $this->itemWarehouseInfo = [];

        $query      = [];
        $query[]    = "";
        $query[]    = GetMyCompany();
        $argCounter = 2;    // the NEXT argument is [2]

        $whereExtras = "";
        $whereQuery  = [];

        // item gl group specified?
        if ($itemGLGroup != '') {
            $whereExtras = " AND i.record# IN " . $itemGLGroup;   // pre-sanitized (record numbers)
        }

        // either item and toItem are both empty or both full
        if ($item != '') {
            $whereExtras .= " AND iw.itemkey >= :" . $argCounter++;
            $query[] = $item;
            $whereQuery[] = $item;
            $whereExtras .= " AND iw.itemkey <= :" . $argCounter++;
            $query[] = $toItem;
            $whereQuery[] = $toItem;
        }

        if ($warehouse != '') {
            $whereExtras .= " AND iw.warehousekey=:" . $argCounter++;
            $query[] = $warehouse;
            $whereQuery[] = $warehouse;
        }

        // what fields do we need to populate the table?
        $select = " iw.record# as recordno,
                    to_char(iw.costinglastranon,'MM-DD-YYYY HH24:MI:SS') as costinglastranon,
                    iw.itemkey itemid, iw.warehousekey warehouseid,
                    i.cost_method ";

        // same as the select, but without the names (just the raw fields)
        $groupBy = " iw.record#,
                    to_char(iw.costinglastranon,'MM-DD-YYYY HH24:MI:SS'),
                    iw.itemkey, iw.warehousekey,
                    i.cost_method ";

        // Different queries for quick runs vs thorough
        if ($runAsIfQuick) {

            $this->composeQuickRunIWQuery($query, $select, $whereExtras, $groupBy);

        } else {
            $query[0] = "SELECT distinct $select,
                                to_date(:$argCounter, 'MM/DD/YYYY') as effectivedate, 'slow' as type
                         FROM   icitemwhse  iw, icitemmst i
                         WHERE  iw.cny#=:1
                         AND    i.cny#=iw.cny#
                         AND    i.itemid=iw.itemkey  -- and get ALL warehouses
                         AND    i.cost_method IN ({$this->costingMethods})
                         AND    i.itemtype in ('I','K','SK')
                         $whereExtras
            ";
            $query[] = $dateToStartReadingRecords;  // effective start date
        }

        $result = QueryResult($query);
        $ok = ($result !== false);
        if ($ok) {
            $this->gatherIWRecordsFromQuery((array)$result, $whereExtras, $whereQuery, $dateToStartReadingRecords);
        }
        return $ok;
    }


    /**
     *      The 'DELETE_LOG' table is not really set up for what we want.  Hoewver, I recently added the
     *  warehouse id to the obj_def_id field.  Prior to that, that field was NULL and so
     *  the record had the ITEM but not the WAREHOUSE.
     *
     *  Here, when NULL, we need all the warehouses, because we don't know WHICH ONE it was!
     *  When not NULL, the warehouse record# is here, so we need to lookup the warehouse id
     *
     *  If the warehouse is there, we may have multiple records for warehouses we do not need,
     *  and so we return FALSE to signal skipping the row.
     *
     * @param string[]      $row                The 'quick run' query row for a DELETED item
     * @param string[][]    $warehouseCache     the cache of warehouses
     *
     * @return bool                             Keep the row?
     *
     */
    private function keepQuickRunQueryDeletedRow($row, $warehouseCache)
    {
        $warehouseRecord = $row['DETAILS'] ?? 0;
        $warehouseName   = $warehouseCache[$warehouseRecord] ?? '';

        // we want to KEEP this record if
        // A) the warehouse wasn't specified
        // B) the warehouse WAS specified and MATCHES the one from the item/warehouse recor
        //      (otherwise we got a false hit on a warehouse we don't need)
        return ($warehouseName == '') || ($warehouseName == $row['WAREHOUSEID']);
    }


    /**
     *      The DELETE_LOG file is primitive and I managed to stash the warehoue RECORD NUMBER into the
     * OBJ_DEF_ID field, but we want the warehouse NAME.  So, here, we get all the names we'll need.
     *
     * @param array             $queryResult        result of sql query that is NOT false
     *
     * @return array                                array of names, by record#
     */
    private function generateDeletedRowWarehouseCache($queryResult)
    {
        // Get the warehouse cache:
        $warehousesNeeded = [];
        $cache            = [];
        foreach ($queryResult as $row) {
            if (($row['TYPE'] == self::query_deleted2) && (($row['DETAILS'] ?? 0) > 0)) { // 'DELETED'
                $warehousesNeeded[$row['DETAILS']] = true;  // eliminate dups
            }
        }
        if ( ! empty($warehousesNeeded)) {
            $stmt = [];
            $stmt[0] = 'SELECT record#, location_no FROM icwarehouse WHERE cny# = :1 ';
            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, array_keys($warehousesNeeded), " and record# ");
            $res = QueryResult($stmt);
            if ($res !== false) {
                foreach ($res as $row) {
                    $cache[$row['RECORD#']] = $row['LOCATION_NO'];
                }
            }
        }
        return $cache;
    }


    /**
     *  Internal helper to build a 'sort tree', specifically $this->stockableKitsSortOrder .
     * The 'tree' has, for each stockable kit we should recalc, a number meaning 'sort this
     * BEFORE numbers that are higher and AFTER numbers that are lower'.
     *
     * This will be used later for sorting query results prior to recalcing.
     *
     * Danger: protective eyeware required: recursion in use!
     *
     * @param array     $componentKit       array by component, by SK
     * @param string    $componentId        name of component (itemid)
     */
    private function _gatherStockableKitsFromParts_buildSortTree($componentKit, $componentId)
    {
        // is the component also a stockable kit?  If not, nothing to do here.
        $componentOrder = $this->stockableKitsSortOrder[$componentId] ?? -1;
        if ($componentOrder >= 0) {
            // it IS a Stockable Kit!
            foreach ($componentKit[$componentId] as $stockableKit => $dummy) {                  // COULD BE EMPTY!
                $stockableKitOrder = $this->stockableKitsSortOrder[$stockableKit];
                if ($componentOrder >= $stockableKitOrder) {
                    $this->stockableKitsSortOrder[$stockableKit] = ($componentOrder + 1);    // do this item a little later in the list

                    // now recurse 'up the tree' of stockable kits; is THIS sk a component in another?
                    $this->_gatherStockableKitsFromParts_buildSortTree($componentKit, $stockableKit); // Curses!  He Recurses!
                }
            }
        }
    }


    /**
     *      Given the results of the Quick Run (or full) query to find things that changed,
     *  see if anything in the change window-of-time was a stockable-kit-build PART.
     *  Add the stockable kit itself to the list of things to recalc if it is not already there.
     *
     *      Additionally, and this is critical, provide a 'sort helper' for sorting a set of items
     *  into order, such that the Stockable Kit comes AFTER the components, even if a component
     *  is itself a stockable kit.
     *
     *  For example,
     *      SK1 includes C1 and C2
     *      SK2 includes SK1 and SK3
     *      SK3 includes SK1
     *
     *      The resulting order in this sort helper should be C1/C2 --> 0, SK1 --> 1, SK2 --> 3, and SK3 --> 2
     *
     *  For another example:
     *      Stockable Kit 'porch' includes lumber and nails.
     *      If the lumber or the nails are about to be recalc'd,
     *          add 'porch' to the list of things to be recalc'd if not already there.
     *
     * @param array  $queryResult               On INPUT:  the searched-for list of items and warehouses
     *                                          On OUTPUT: above, augmented by any Stockable Kit item/warehouses
     * @param string $dateToStartReadingRecords The start date
     *
     * @return bool                             DB ok?
     */
    private function gatherStockableKitsFromParts( & $queryResult, $dateToStartReadingRecords)
    {
        // **** HELPER ROUTINES ****

        /** @var callable $getKitItemsForPartsAlreadyInQuery */
        $getKitItemsForPartsAlreadyInQuery = function($items, &$queryResult, $dateToStartReadingRecords, & $componentKit) {
            if (empty($items)) {
                return [];    // nothing to do
            }

            $qry = [];
            $qry[] = "SELECT de.itemkey as deitem, de.warehousekey, parts.itemkey as partitem, iw.record#
                    FROM docentrymst de, docentrycostkits parts, icitemwhse iw          -- find Stockable Kit BUILDS
                   WHERE de.cny# = :1 AND parts.cny# = de.cny# AND iw.cny# = de.cny# 
                    AND  de.record# = parts.docentrykey
                     AND iw.itemkey = de.itemkey AND iw.warehousekey = de.warehousekey  -- the KIT itemwarehouse record, not the PART
                     AND parts.datein >= :2
                   ";
            $qry[] = GetMyCompany();
            $qry[] = $dateToStartReadingRecords;
            $qry = PrepINClauseStmt($qry, array_keys($items), ' AND parts.itemkey ');   // look for PARTS being built into SKs
            $results = QueryResult($qry);
            if ($results === false) {
                return false;
            }

            // did we find any parts in the item list that reference kits NOT in the list?
            $newItems = [];
            foreach ($results as $row) {                        // RESULTS COULD BE EMPTY, SO NO BUILDS
                $kitItem   = $row['DEITEM'];
                $component = $row['PARTITEM'];

                // track these as our 'tree' of builds
                $componentKit[$component][$kitItem]     = true;
                $this->stockableKitsSortOrder[$kitItem] = 1;

                // if SK not included, include it now
                $warehouse = $row['WAREHOUSEKEY'];
                $index     = $items[$component][$warehouse] ?? -1;  // it SHOULD be there, but....
                if (($index >= 0) && !isset($items[$kitItem][$warehouse])) {
                    // replicate the query results
                    $qr                 = $queryResult[$index];
                    $qr['COST_METHOD']  = 'F';                      // sks are all FIFO, but not nescessarily their parts
                    $qr['RECORDNO']     = $row['RECORD#'];          // replace the PART item-warehouse record number with the KIT's
                    $qr['ITEMID']       = $kitItem;                 // and warehouse would be redundant
                    $index              = count($queryResult);      // the just-added index
                    $queryResult[]      = $qr;
                    $newItems[$kitItem][$warehouse] = $index;       // brand new item/wh combo
                    $items[$kitItem][$warehouse] = $index;          // in case there's another like it (unlikely?)....
                }
            }
            return $newItems;   // only the new items
        };


        // ********************
        // **** MAIN CODE *****
        // ********************
        $this->stockableKitsSortOrder = [];

        $items = [];
        foreach ($queryResult as $index => $row) {
            $items[ $row['ITEMID'] ][ $row['WAREHOUSEID'] ] = $index;  // gather a unique list of items to look at, referencing ALL entries they're in
        }

        // get kits for parts.  Handle kits within kits....
        $limit = 10;
        $componentKit = [];   // array BY component, BY SK
        while ( ! empty($items)) {
            $items = $getKitItemsForPartsAlreadyInQuery($items, $queryResult, $dateToStartReadingRecords, $componentKit);
            if ($items === false) {
                return false;
            }

            $limit--;
            if ($limit <= 0) {
                break;              // in case something goes wrong or TOO deeply nested
            }
        }

        // Now, make the 'sort order tree' for later;
        foreach ($componentKit as $componentId => $dummy) {                  // COULD BE EMPTY!
            $this->_gatherStockableKitsFromParts_buildSortTree($componentKit, $componentId);
        }
        return true;
    }


    /**
     *  Sort the query result of things we want to recalc into proper order.  We'll sort again later, but we want
     *  Stockable Kits to come last, and later we may split up the queries because of the huge number of records,
     *  so lets make sure when we DO split them up, the stockable kits are last.
     *
     * @param array $queryResult
     *
     */
    private function sortQueryResultsInOrder( & $queryResult)
    {
        // now sort the original query results into ITEM order where stockable kits come in the above computed order....
        // sort even if there were no stockable kits, as otherwise we might not be in item/wh order
        usort($queryResult, function ($a, $b) {
            $itemidA = $a['ITEMID'];
            $itemidB = $b['ITEMID'];

            $orderA  = $this->stockableKitsSortOrder[$itemidA] ?? 0;    // zero means its a part, not a kit
            $orderB  = $this->stockableKitsSortOrder[$itemidB] ?? 0;

            // non-SKs are zero, SKs are 1+
            if ($orderA > $orderB) {
                return +1;
            } else if ($orderA < $orderB) {
                return -1;
            }

            // same level, sort by itemid
            $i = strcmp($itemidA, $itemidB);
            if ($i !== 0) {
                return $i;
            }

            // same level, sort by warehouse
            $whA = $a['WAREHOUSEID'];
            $whB = $b['WAREHOUSEID'];
            return strcmp($whA, $whB);

        });
    }


    /**
     *      After querying to see what item/warehouses need re-costing, lets put them into a table for later use.
     * In the case of stockable kits there can be dups
     *
     * @param array             $queryResult        result of sql query that is NOT false
     * @param string            $whereExtras        filtering for where clause (item, warehouse, date, ...)
     * @param string[]          $whereQuery         query array extras for using the 'whereExtras' parameter
     * @param string            $dateToStartReadingRecords  the start date, maybe updated
     *
     * @return bool             everything ok?
     */
    private function gatherIWRecordsFromQuery($queryResult, $whereExtras, $whereQuery, &$dateToStartReadingRecords)
    {
        $warehouseCache = $this->generateDeletedRowWarehouseCache($queryResult);

        // Now process the records....
        $gmt = new DateTimeZone("GMT");

        // do we need to expand the reach of a run to include stockable kits?
        if ($this->gatherStockableKitsFromParts($queryResult, $dateToStartReadingRecords) === false) {
            return false;
        }

        // Order the results
        $this->sortQueryResultsInOrder($queryResult);

        // now break into items and warehouses
        foreach ($queryResult as $row) {

            // cleanup deleted item entries:
            if ($row['TYPE'] == self::query_deleted2) { // 'DELETED'
                if ( ! $this->keepQuickRunQueryDeletedRow($row, $warehouseCache)) {
                    continue;  // skip this row
                }
            }

            $rawCostingLastRanOn = $row['COSTINGLASTRANON'] ?? self::EarliestDate;
            $item                = $row['ITEMID'];
            $warehouse           = $row['WAREHOUSEID'];

            // stockable kits can cause a second entry; like a purchase of a hammer
            // and a disassemble of a kit with a hammer in it
            // warehouse transfer ins aren't nescessarily in the time period we care about (as they
            // may be processed after this query), but at least we'll get an item/warehouse record out of it.
            if (isset($this->itemWarehouseInfo[$item][$warehouse])) {
                // the ONLY thing that would be different would be the effective date and maybe why
                // note the why values are in reverse order of importance
                $thisDate = ($row['EFFECTIVEDATE'] ?? $dateToStartReadingRecords);
                $diff     = MyCompareDate($thisDate, $this->itemWarehouseInfo[$item][$warehouse]['EARLIEST_EFFECTIVE_DATE']);

                // if this record is earlier, OR if the same date but a lower 'type' value, then it is more important.....
                if (($diff < 0) || (($diff == 0) && ($row['TYPE'] < $this->itemWarehouseInfo[$item][$warehouse]['WHY'])) ) {
                    $this->itemWarehouseInfo[$item][$warehouse]['EARLIEST_EFFECTIVE_DATE']  = $thisDate;
                    $this->itemWarehouseInfo[$item][$warehouse]['WHY']                      = $row['TYPE'];
                    $this->itemWarehouseInfo[$item][$warehouse]['DETAILS']                  = $row['DETAILS'];
                    $this->itemWarehouseInfo[$item][$warehouse]['AFFECTED']                 = $row['AFFECTED'];
                }
            } else {
                $this->itemWarehouseInfo[$item][$warehouse] = array(
                    'RECORDNO'                => $row['RECORDNO'],
                    'COSTINGLASTRANONSQL'     => $rawCostingLastRanOn,                       // format good for SQL
                    'COSTINGLASTRANON'        => DateTime::createFromFormat('m-d-Y H:i:s', $rawCostingLastRanOn, $gmt),    // internal format
                    'COST_METHOD'             => $row['COST_METHOD'],
                    'EARLIEST_EFFECTIVE_DATE' => ($row['EFFECTIVEDATE'] ?? $dateToStartReadingRecords),
                    'HAD_UPDATES'             => false,
                    'WHY'                     => $row['TYPE'],
                    'AFFECTED'                => $row['AFFECTED'],
                    'DETAILS'                 => $row['DETAILS'],
                    'STARTON'                 => $dateToStartReadingRecords,
                );
            }

            // we want to read records starting at the earliest date
            if (MyCompareDate($this->itemWarehouseInfo[$item][$warehouse]['EARLIEST_EFFECTIVE_DATE'], $dateToStartReadingRecords) < 0) {
                $this->itemWarehouseInfo[$item][$warehouse]['EARLIEST_EFFECTIVE_DATE'] = $dateToStartReadingRecords;
            }
        }

        // For standard costs where we don't want details about sales, we DO want details about the effective date changes here....
        if (strpos($this->costingMethods,"S") !== false) {
            $this->gatherStandardCostChanges($whereExtras, $whereQuery);
        }
        return true;
    }


    /**
     * @param string            $whereExtras        filtering for where clause (item, warehouse, date, ...)
     * @param string[]          $whereQuery         query array extras for using the 'whereExtras' parameter
     *
     * @return bool
     */
    private function gatherStandardCostChanges($whereExtras, $whereQuery)
    {
        // we only care about the records we fetched already, so lets limit ourselves to those if not too many
        $itemWarehouseInfoRecords = $this->generateArrayOfItemWarehouseRecordNos( false, 'S' );

        // if there are some standard cost entries
        if ( ! empty($itemWarehouseInfoRecords)) {
            $query = [];
            $query[] = "SELECT sc.standard_cost, sc.effective_start_date, iw.itemkey itemid, iw.warehousekey warehouseid, sc.whencreated, sc.whenmodified, sc.createdby, sc.modifiedby
                     FROM   icitemwhsestdcost sc, icitemwhse iw, icitemmst i
                     WHERE  sc.cny#=:1
                     AND    sc.cny#=iw.cny#
                     AND    sc.cny#=i.cny#
                     AND    sc.itemwhsekey = iw.record#
                     AND    i.itemid=iw.itemkey
                     AND    i.cost_method = 'S'
                     AND   ((iw.costingmustrun is null)   OR (iw.costingmustrun != 'T'))
                     AND   ((iw.costinglastranon is null) OR (sc.lastupdated >= iw.costinglastranon))
                     AND    i.itemtype in ('I','K','SK')
                     $whereExtras
                    ";
            $query[]    = GetMyCompany();
            $query      = array_merge($query, $whereQuery);
            $query      = PrepINClauseStmt($query, $itemWarehouseInfoRecords, " and iw.record# ");
            $query[0]  .= " ORDER BY itemid, warehouseid, effective_start_date";
            $result     = QueryResult($query);
            if ($result === false) {
                return false;
            }
            foreach ($result as $row) {
                $item = $row['ITEMID'];
                $warehouse = $row['WAREHOUSEID'];
                if (isset($this->itemWarehouseInfo[$item][$warehouse])) {           // we may have too many and don't need them all
                    $this->itemWarehouseInfo[$item][$warehouse]['CHANGE'][] = [
                        'COST'         => $row['STANDARD_COST'],
                        'DATE'         => $row['EFFECTIVE_START_DATE'],     // table will be in order by these
                        'MAX_DATE'     => self::NO_EFFECTIVE_DATE,
                        'WHENCREATED'  => $row['WHENCREATED'],
                        'WHENMODIFIED' => $row['WHENMODIFIED'],
                        'CREATEDBY'    => $row['CREATEDBY'],
                        'MODIFIEDBY'   => $row['MODIFIEDBY'],
                    ];
                }
            }


            // now we want the intervals between the changed record and the next record.  For example,
            // I recently changed the June 3 record to have a new standard cost.  But, when does that expire?
            // so now I need to query ALL the effective start dates and then see how long any above records last.
            $query = [];
            $query[0] = "SELECT sc.effective_start_date, iw.itemkey itemid, iw.warehousekey warehouseid
                     FROM   icitemwhsestdcost sc, icitemwhse iw, icitemmst i
                    WHERE  sc.cny#=:1
                     AND    sc.cny#=iw.cny#
                     AND    sc.cny#=i.cny#
                     AND    sc.itemwhsekey = iw.record#
                     AND    i.itemid=iw.itemkey
                     AND    i.cost_method = 'S'
                     AND    i.itemtype in ('I','K','SK')
                     $whereExtras
                      ";
            $query[1]    = GetMyCompany();
            $query      = array_merge($query, $whereQuery);
            $query      = PrepINClauseStmt($query, $itemWarehouseInfoRecords, " and iw.record# ");
            $query[0]  .= " ORDER BY itemid, warehouseid, effective_start_date";
            $result     = QueryResult($query);
            if ($result === false) {
                return false;
            }
            foreach ($result as $row) {
                $item      = $row['ITEMID'];
                $warehouse = $row['WAREHOUSEID'];
                $effective = $row['EFFECTIVE_START_DATE'];  // table is in order by these
                if (isset($this->itemWarehouseInfo[$item][$warehouse]['CHANGE'])) {
                    foreach ($this->itemWarehouseInfo[$item][$warehouse]['CHANGE'] as $index => $change) {
                        if ((MyCompareDate($change['DATE'],     $effective) < 0) &&  // new effective > recently-changed?
                            (MyCompareDate($change['MAX_DATE'], $effective) > 0)) {  // and less than the 'max date'?
                            $this->itemWarehouseInfo[$item][$warehouse]['CHANGE'][$index]['MAX_DATE'] = $effective;
                            break; // the first to fit both above is the best we'll get, as they're both in order
                        }
                    }
                }
            }
        }
        return true;
    }


    /**
     *      Build the 'Quick' query for the item/warehouse list.
     *  This will return a bunch-o item/warehouse records where one inbound-value transaction has
     *  changed since the last MIV run, or a standard-cost item has changed,
     *  AND there is at least one COGS sale after the effective date of the above earliest transaction.
     *
     * @param array         $query          The query array so far (to be filled in)
     * @param string        $select         The fields we want to select, at least
     * @param string        $whereExtras    The filtering where clause (for item, warehouse, etc)
     * @param string        $groupBy        The group by clause (a trimmed down select list)
     *
     */
    private function composeQuickRunIWQuery(&$query, $select, $whereExtras, $groupBy)
    {
        $startOfTime     = $this->startOftime->format( 'm/d/Y' );
        $startDateChange = $this->startDateChangedOn->format('m/d/Y G:i:s');

        // Do we search for Standard Cost changes as well?
        $standardCostsToo = (strpos($this->costingMethods, "'S'" ) !== false);

        // We do separate queries to find WHY it hit (like a purchase, deleted record, whatnot), so we end up with several simple queries...
        // Catch the 'costing never ran' case:
        $query[0] = "
            SELECT $select, nvl(to_char(iw.costinglastranon,'MM/DD/YYYY'), ' ') as details,
                                '$startOfTime' as effectivedate, " . self::query_never_ran_costing . " as type
                           FROM icitemwhse iw, icitemmst i
                          WHERE iw.cny# = :1 AND i.cny# = iw.cny#
                            AND i.itemid = iw.itemkey
                            AND i.itemtype in ('I','K','SK')
                            AND ((iw.costinglastranon IS NULL) OR (to_date('$startDateChange','MM/DD/YYYY HH24:MI:SS') >= iw.costinglastranon))
                            AND ((iw.costingmustrun is null) OR (iw.costingmustrun != 'T'))
                            $whereExtras
                            GROUP BY $groupBy, nvl(to_char(iw.costinglastranon,'MM/DD/YYYY'), ' ')
            UNION ALL ";

        // This query gets records where there were transactions created/altered after the last MIV run
        //      (if one).  Note that the EFFECTIVE DATE could be before the
        //      last MIV run, but the date the transaction was ALTERED is after the last MIV run.
        $query[0] .= "
                 SELECT $select, d.docid as details,
                         to_char(min(d.whencreated),'MM/DD/YYYY') as effectivedate, " . self::query_purchase . " as type
                 FROM  icitemwhse iw, dochdrmst d, docentrymst de, docentrycost dec, icitemmst i
                 WHERE iw.cny# = :1
                 AND   d.cny# = iw.cny#
                 AND   de.cny# = iw.cny#
                 AND   dec.cny# = iw.cny#
                 AND   i.cny#  = iw.cny#
                 AND   de.dochdrkey=d.record#
                 AND   dec.docentrykey=de.record#
                 AND   dec.itemkey = iw.itemkey             -- for a stockable kit, this is the KIT not the PART
                 AND   dec.whsekey = iw.warehousekey
                 AND   dec.affects_inventory IN ('Q', 'V', 'QV')
                 AND   iw.costinglastranon IS NOT NULL
                 AND   ((iw.costingmustrun is null) OR (iw.costingmustrun != 'T'))
                 AND   d.lastupdated >= iw.costinglastranon
                 AND   i.itemid = iw.itemkey
                 AND   i.cost_method IN ($this->costingMethods)
                 AND   i.itemtype in ('I','K','SK')
                 $whereExtras
                 GROUP BY $groupBy, d.docid
                
                 UNION ALL
                 -- one or more transaction lines were deleted
                 SELECT $select, to_char(DECODE(dl.OBJ_DEF_ID,NULL,0,dl.OBJ_DEF_ID)) as details,
                        to_char(min(dl.whencreated),'MM/DD/YYYY') as effectivedate, " . self::query_deleted2 . " as type
                   FROM delete_log dl, icitemwhse iw, icitemmst i
                  WHERE iw.cny# = :1 AND i.cny# = iw.cny# AND dl.cny# = iw.cny#
                    AND dl.object in ('podocumententry', 'sodocumententry', 'invdocumententry')
                    AND dl.doctype is not null
                    AND i.itemid = iw.itemkey
                    AND dl.doctype = iw.itemkey
                    AND iw.costinglastranon IS NOT NULL
                    AND dl.whendeleted >= iw.costinglastranon
                    AND i.cost_method IN ($this->costingMethods)
                    AND ((iw.costingmustrun is null) OR (iw.costingmustrun != 'T'))
                    AND i.itemtype in ('I','K','SK')
                    $whereExtras
                    GROUP BY $groupBy, to_char(DECODE(dl.OBJ_DEF_ID,NULL,0,dl.OBJ_DEF_ID))
                    ";

        if ($standardCostsToo !== false) {
            // Standard costs care about changes in standard costs too, not just txns
            $query[0] .= " UNION ALL 
                     SELECT $select, iw.warehousekey as details,
                            to_char(min(sc.effective_start_date),'MM/DD/YYYY') as effectivedate, " . self::query_stdcost_change . " as type
                     FROM  icitemwhse iw, icitemwhsestdcost sc, icitemmst i
                     WHERE iw.cny# = :1
                     AND   sc.cny# = iw.cny#
                     AND   i.cny#  = iw.cny#
                     AND   sc.itemwhsekey = iw.record#
                     AND   iw.costinglastranon IS NOT NULL
                     AND   ((iw.costingmustrun is null) OR (iw.costingmustrun != 'T'))
                     AND   sc.lastupdated >= iw.costinglastranon
                     AND   i.itemid = iw.itemkey
                     AND   i.cost_method = 'S'
                     AND   i.itemtype in ('I') -- can't be a kit or stockable kit
                     $whereExtras
                     GROUP BY $groupBy, iw.warehousekey
                     ";
        }
    }


    /**
     *      Now that the itemWarehouseInfo array has been built,
     *          return items for a specified cost method, or for 'ALL'
     *
     * @param  string           $costMethod     one of 'A', 'F', 'L', 'S', or 'ALL'
     *
     * @return string[]                         If not empty, it is suitible for PrepInClause() call for itemIDs
     *
     */
    public function getIitemsForMethod($costMethod)
    {
        // Gather the items for the given cost type
        $rtn = [];
        foreach ($this->itemWarehouseInfo as $item => $items) {
            foreach ($items as $warehouses) {
                if (($costMethod === 'ALL') || ($warehouses['COST_METHOD'] === $costMethod)) {
                    $rtn[] = $item;
                }
                break;  // only need to check the first warehouse for the cost method
            }
        }
        return $rtn;
    }


    /**
     *      Make a list of the record numbers of the item/warehouses in our list.
     *
     * @param  bool         $hadUpdates         Do we only want the records that have updates?
     * @param  bool|string  $specificCostType   Do we restrict to one cost type?  optional
     *
     * @return int[]
     */
    private function generateArrayOfItemWarehouseRecordNos($hadUpdates, $specificCostType = false)
    {
        // Gather the item/warehouse records where we saw changes in their docentrycosts.....
        $itemWarehouseInfoRecords = [];
        foreach ($this->itemWarehouseInfo as $items) {
            foreach ($items as $warehouses) {
                if ($hadUpdates && ! $warehouses['HAD_UPDATES']) {
                    continue;
                }
                if ($specificCostType !== false) {
                    if ($specificCostType != $warehouses['COST_METHOD']) {
                        continue;
                    }
                }
                $itemWarehouseInfoRecords[] = (int)$warehouses['RECORDNO'];
            }
        }
        return $itemWarehouseInfoRecords;
    }

    /**
     *  Save the STARTING timestamp, Oracle style, to the list of item/warehouse info records, if we're in
     *  QUICK mode.
     *
     * @param  bool  $force         Do the save even if not a 'quick' run.  Caller guarentees that we updated in closed
     *                              periods AND update cogs in open periods
     *
     * @return bool
     *
     */
    public function saveItemWarehouseTimers($force)
    {
        $ok = true;

        if ($this->quickRun || $force) {

            // Gather the item/warehouse records where we saw changes in their docentrycosts.....
            // September 2020: I changed this to false, because it throws off the calculations of what NEEDS to be done.
            //               i.e. the customer would see the same things over and over
            $itemWarehouseInfoRecords = $this->generateArrayOfItemWarehouseRecordNos( false );  // true is 'had updates'

            if ( ! empty($itemWarehouseInfoRecords)) {
                $query = [];
                $query[] = "UPDATE icitemwhse set costinglastranon = to_timestamp( :1, 'MM-DD-YYYY HH24:MI:SS' ), costingmustrun = 'F' where cny# = :2 ";
                $query[] = $this->runStartedAtOracleTime;
                $query[] = GetMyCompany();
                $query   = PrepINClauseStmt($query, $itemWarehouseInfoRecords, " and record# ");

                // timestamp format: 14-JAN-19 10.12.26.871977000 PM GMT
                $ok = ExecStmt($query);
            }
        }

        // If there is not already a INVSTARTDATECHANGEDON parameter, set it now
        // so next time we run we don't think it has run AGAIN.
        if ( ! $this->invStartDateKnown) {

            // Update manually so as to not possibly change the location.
            // Did someone add it WHILE we were running it?  Unlikely.
            $exists   = false;
            $query    = [];
            $query[0] = "select cny#, value from modulepref where cny# = :1 and modulekey = :2 and property = :3 and locationkey is null ";
            $query[1] = GetMyCompany();
            $query[2] = Globals::$g->kINVid;
            $query[3] = 'INVSTARTDATECHANGEDON';
            $result   = QueryResult($query);
            if ($result !== false) {
                $exists = isset($result[0]['CNY#']);    // was 'VALUE', but P3 14390316: Maintain Inventory Valuation Error #DL02000001
            }                                           // in that case VALUE was null somehow!
            if ($exists) {
                $update = "update MODULEPREF set value = :1 where cny# = :2 and modulekey = :3 and property = 'INVSTARTDATECHANGEDON'";
                $ok = ExecStmt( [$update, GetCurrentDate(IADATE_SYSFORMAT), GetMyCompany(), Globals::$g->kINVid] );
            } else {
                $update = 'insert into MODULEPREF ( CNY#, MODULEKEY, PROPERTY, VALUE, LOCATIONKEY) values ( :1, :2, :3, :4, NULL )';
                $ok = ExecStmt( [$update, GetMyCompany(), Globals::$g->kINVid, 'INVSTARTDATECHANGEDON', GetCurrentDate(IADATE_SYSFORMAT)] );
            }
        }

        return $ok;
    }


    // ------------------------------ UTILITY ROUTINES ----------------------------------


    /**
     *      What time is it right now, according to Oracle?
     *
     * @return string       oracle timestamp in GMT
     */
    public function getOracleTimeStamp()
    {
        $rtn = '';
        $query = [];
        $query[] = "SELECT to_char(CURRENT_TIMESTAMP at TIME ZONE 'GMT','MM-DD-YYYY HH24:MI:SS') now FROM DUAL";
        $result = QueryResult($query);

        if ($result !== false) {
            $rtn = $result[0]['NOW'];   // return from first row
        }
        return $rtn;
    }


    /**
     *      Get a 'feature lock', which says "I am using this feature and you cannot"
     *  According to Rich P, this isn't 100% foolproof, as it is local to a POD of servers,
     *  but it is the best we have unless we want to also do a sql lock.
     *
     * @return bool         did we get the lock, or is someone else using this now?
     */
    public function getFeatureLock()
    {
        $this->featureLock = new Lock();
        $this->featureLock->setClearLockOnDestroy(true);    // so when we go away we release the lock

        $lockName = GetMyCompany() . "_MaintainInventoryValuationTool";  // just our company

        $gotIt = $this->featureLock->setLock($lockName,
                                   60 * 15,       // how long to hold the lock, in seconds (or until I release it)
                                         false);      // should I WAIT for someone else to be done?  (no, fail!)
        if ( ! $gotIt) {
            $this->releaseFeatureLock();    // just so it goes to null
        }

        return $gotIt;
    }


    /**
     *   release any aquired lock, though that happens anyway when this class is released.
     */
    public function releaseFeatureLock()
    {
        unset( $this->featureLock );
    }


    /**
     * Is the first date greater-or-equal to the second date?
     * The parameters can be strings or DateTimes; where DateTimes are faster....
     * note: I do not expect booleans, but DateTime::createFromFormat returns tham, so inspections insist.
     *
     * @param string|DateTime|bool  $earlierDate
     * @param string|DateTime|bool  $laterDate
     *
     * @return bool
     */
    public function dateIsGE ($earlierDate, $laterDate)
    {
        static $gmt = null;

        if ($gmt === null) {
            $gmt = new DateTimeZone("GMT");
        }

        if (!$earlierDate instanceof DateTime) {
            $earlierDate = DateTime::createFromFormat( "d-m-Y G:i:s", $earlierDate, $gmt);
        }
        if (!$laterDate instanceof DateTime) {
            $laterDate = DateTime::createFromFormat( "d-m-Y G:i:s", $laterDate, $gmt);
        }

        if (($earlierDate === false) || ($laterDate === false)) {
            return false;   // not sure what else to do here.
        }
        return ($earlierDate >= $laterDate);
    }


    /**
     *      Add to a string (the 'note').  Include a separator if there was already a string there.  So the result is
     *          some text; some other text; some other text
     *
     * @param string $note         the existing note, if any.  This is added to as a reference parameter.
     * @param string $addThis      the string to add to the note
     *
     */
    private function addToNote(&$note, $addThis)
    {
        if (strlen($note) > 0) {
            $note .= '; ';
        }
        $note .= $addThis;
    }


    /**
     *  cogs Adjustments    the adjustments made using the Cogsresolve table
     *
     * @param int   $derec          The DocEntry record number
     * @param bool  $returnAmount   Do we return the AMOUNT or the TRX_AMOUNT?
     *
     * @return float                The total adjustments made, or 0.0
     *
     */
    public function cogsAdjustments($derec, $returnAmount = true)
    {
        static $cache = NULL;
        if ($cache === NULL) {
            $cache = [];
            $query = array();
            $query[0] = "select docentrykey, (sum(amount) / 2) as adjustments, (sum(trx_amount) / 2) as trx_adj from cogsresolve where cny# = :1 group by docentrykey ";
            $query[] = GetMyCompany();

            $cogsresolves = QueryResult($query);
            if ($cogsresolves !== false) {
                foreach ($cogsresolves as $oneEntry) {
                    $cache[$oneEntry['DOCENTRYKEY']]['AMOUNT'] = (float)$oneEntry['ADJUSTMENTS'];
                    $cache[$oneEntry['DOCENTRYKEY']]['TRX']    = (float)$oneEntry['TRX_ADJ'];
                }
            }
        }
        if (isset( $cache[$derec])) {
            return ($returnAmount ? $cache[$derec]['AMOUNT'] : $cache[$derec]['TRX']);
        }
        return null;
    }


    /**
     *      Format a number (or string that contains a number) into a two decimal place string
     *
     * Note: both round() and iround() can sometimes return -0.00, which is awful, or n.nn0000000000001
     *
     * @param string|float  $n    A number or string representing a number, with arbitrary precision
     *
     * @return string             A string like "1234.56".  Rounded to two decimal places, the way the GL likes it.
     */
    public function formatForGL($n)
    {
        if ($n !== null) {
            // the GL likes two decimal places.  When we go international, we can change this one spot....
            $n = number_format((float)$n, 2, '.', '');
        }
        return $n;
    }


    /**
     * @param int[]     $docentrycostRecordnumbers      Which records should we check?
     * @param callable  $callback                       client callback
     * @param array     $callbackContext                passed to the client callback
     *
     * @return bool
     */
    private function adjustStockableKits($docentrycostRecordnumbers, $callback, &$callbackContext)
    {
        $ok          = true;
        if (empty($docentrycostRecordnumbers)) {
            return $ok;
        }

        // What SHOULD the kits cost?
        $deCosts     = $this->getCurrentTrueCostsForStockableKits($docentrycostRecordnumbers);
        $deRecCosts  = [];
        $decRecCosts = [];
        if ($deCosts === false) {
            $ok = false;
        } else {
            // this is the list that actually need updating because costs have changed....
            foreach ($deCosts as $derec => $row) {

                // update docentry if need be
                if ($row['DECOST'] != $row['NEWDECOST']) {

                    $deRecCosts[$derec] = $row['NEWDECOST'];

                    $callback($derec, $callbackContext);
                }

                // update docentrycosts if need be
                foreach ($row['DEC'] as $decrec => $decrecRow) {

                    if ($decrecRow['DECCOST'] != $decrecRow['NEWDECCOST']) {
                        $decRecCosts[$decrec] = $decrecRow['NEWDECCOST'];
                    }
                }
            }
            // Update in bulk
            $ok = $ok && $this->updateSpecificStockableKits($deRecCosts);   // ok if empty

            // update in bulk
            $ok = $ok && $this->updateSpecificStockableKitParts($decRecCosts);  // ok if empty
        }

        // touch on of the kit part records to restore any lost item activity data
        if ( ! empty($deRecCosts)) {
            $query   = [];
            $query[] = "UPDATE docentrycostkits SET quantity = quantity WHERE cny#=:1 ";
            $query[] = GetMyCompany();
            $query   = PrepINClauseStmt($query, array_keys($deRecCosts), ' and docentrykey ');
            $ok      = $ok && ExecStmt($query);
        }
        return $ok;
    }


    /**
     *      Adjust stockable kits from parts we updated above.
     *  When we updated records, if the record was a docentrycostkits record, then it was a PART to a stockable kit
     *  build or disassemble.  We recorded the docentry records of the kit itself into
     *
     *      $this->stockableKitsNeedingUpdate[]
     *
     *  So, here, lets get the cost for each of these docentry records, make sure they are BUILD and not DISASSEMBLEs,
     *  and then update the build kit cost with the new cost.
     *
     *  Now, note that if we HAPPEN to be updating the build kits as part of regular updates, then we'll remove this
     *  kit from the array above.
     *
     *  This happens after all other items are processed, and so we can't record things in the normal flow of the
     *  COGS CSV file.  Anything we put in will be at the end.
     *
     * @param string    $messages        Any text we want put at the bottom of the CSV COGS report
     *
     * @return bool
     */
    public function adjustStockableKitsFromUpdatedParts(&$messages)
    {
        $ok = true;
        if ( ! empty($this->stockableKitsNeedingUpdate)) {
            $stockableKitsByRec = array_keys($this->stockableKitsNeedingUpdate);
            $context            = ['MESSAGE' => $messages, 'SKNU' => $this->stockableKitsNeedingUpdate];
            $ok = $this->adjustStockableKits($stockableKitsByRec, function ($derec, &$context) {
                $item  = $context['SKNU'][$derec][0];
                $docid = $context['SKNU'][$derec][1];
                $docid = str_replace(_(' (Part)'), '', $docid);
                // DO NOT TRANSLATE; THIS IS MOSTLY USEFUL FOR US SUPPORT AND DEV
                $context['MESSAGE'] .= "$docid item $item was updated from its parts.\n";
            }, $context);

            $messages = $context['MESSAGE'];
        }
        return $ok;
    }


    /**
     *      Adjust Stockable Kits - fix any SK BUILD KIT transactions to have the same cost as the sum of the parts.
     * This is called in the normal course of MIV recalculating.  See the notes above for the 'last minute' cleanup
     * from parts that were updated.
     *
     * A note about **** how this works **** .....
     *
     *      1) we are processing items and warehouses in alpha order
     *      2) here we have a 'Stockable Kit' item, so this routine is called
     *          2.5) for each BUILD, maybe update the docentrycost from the docentrycostkits if the costs differ
     *
     *  Separately from this, if we encounter a PART (docentrycostkit) that has
     *  changed values (in thisLineChanged(), above),
     *      We record that part's kit (the docentry in the build kit)
     *      and, if that kit isn't recomputed here, it is recomputed
     *      in adjustStockableKitsFromUpdatedParts() above.  Simple, no?
     *
     * @param array $lineItems              The list of transactions
     * @param int   $startHere              Where to start in the list
     *
     * @return bool
     */
    public function adjustStockableKitsFromTransactionStream(&$lineItems, $startHere)
    {
        $ok = true;
        $item_key = $lineItems[$startHere]['COMP'];
        $warehouse_key = $lineItems[$startHere]['WAREHOUSEKEY'];
        $stockableKitsByLine = [];

        // ********** STEP ONE: Collect ANY BUILD KITS? **************
        $countOfLines = count($lineItems);
        $key = $startHere;
        while ($key < $countOfLines) {

            $line = $lineItems[$key];   // current line

            // Are we done for this item/warehouse?
            if (($line['COMP'] != $item_key) || ($line['WAREHOUSEKEY'] != $warehouse_key)) {
                break;
            }

            // IS this row a build kit?
            // And is this a docentrycost, NOT a docentrycostkits?   (kits are negative)
            if (($line['DOCPARID'] == BUILD_KIT) && ($line['DECREC'] > 0) && ($line['QUANTITY'] > 0)) {
                $deRec = (int)$line['DEREC'];
                $stockableKitsByLine[$deRec][] = $key;  // remember the line this came from
                // Did we update a part?  If so, we don't need to update this kit later
                if (isset($this->stockableKitsNeedingUpdate[$deRec])) {
                    unset($this->stockableKitsNeedingUpdate[$deRec]);   // we are about to take care of it
                }
            }
            $key++;
        }

        // ****************** STEP TWO: GET CURRENT KIT COSTS *******************
        if (!empty($stockableKitsByLine)) {

            $stockableKitsByRec = array_keys($stockableKitsByLine);
            $context = ['SKITSBYLINE' => $stockableKitsByLine, 'UPDATEKEYS' => []];

            $ok = $this->adjustStockableKits($stockableKitsByRec, function ($derec, &$context) {
                foreach ( $context['SKITSBYLINE'][$derec] as $lineKey) {
                    $context['UPDATEKEYS'][] = $lineKey;
                }
            }, $context);

            foreach ($context['UPDATEKEYS'] as $lineKey) {
                $lineItems[$lineKey]['NOTES'] .= "Cost updated from parts";
                if ($lineItems[$lineKey]['STATE'] === InvCostToolManager::GOOD) {
                    $lineItems[$lineKey]['STATE'] =   InvCostToolManager::BAD;
                }
            }
        }
        return $ok;
    }


    /**
     *      While seeing if we need to update BUILD KIT transactions, we gather the current costs and the new costs.
     *   The current costs are in the docentry and docentrycost records.  There can be multiple docentrycost records if,
     *   for example, you are using serial numbers.
     *
     *      The docentrycostkit records may have been updated, and so we compare the sum of their costs to their
     *  relevent docentrycost records and the overall docentry record.
     *
     *      This routine ONLY returns rows that need updating.  Rows that were the same do not need to be updated.
     *
     *
     * @param int[]         $stockableKitDocEntryRecordNumbers      The docentry record#s or the build-kits to recost
     *
     * @return bool|array                                           returns an array costs by docentrycost
     */
    private function getCurrentTrueCostsForStockableKits($stockableKitDocEntryRecordNumbers)
    {
        // Step 1: Get the existing costs for the kit (not the parts)
        //   but don't get them if there is a disassemble (convertedfrom)
        $query   = [];
        $query[] = "SELECT  de.record#  as derec,  de.cost  as decost,  de.quantity  as deqty,
                            dec.record# as decrec, dec.contributedcost as deccost, dec.contributedqty as decqty
                    FROM    docentrymst de, docentrycost dec
                   WHERE    de.cny# = :1 AND dec.cny# = de.cny#
                     AND    dec.docentrykey = de.record#
                     AND    de.quantity > 0
                     AND NOT EXISTS 
                        (
                            SELECT 1 FROM dochdrmst WHERE cny# = :1 AND createdfrom = de.dochdrkey
                        ) ";
        $query[]  = GetMyCompany();
        $query    = PrepINClauseStmt($query, $stockableKitDocEntryRecordNumbers, " and de.record# ");
        $result  = QueryResult($query);
        if ($result === false) {
            return false;
        }

        // Step 2: organize these in a more-useful way
        $deCosts = [];
        $stockableKitDocEntryRecordNumbers = [];    // rebuild this without the disassembled entries
        foreach ($result as $row) {
            $derec  = $row['DEREC'];
            $decrec = $row['DECREC'];
            $stockableKitDocEntryRecordNumbers[$derec] = true;
            if ( ! isset($deCosts[$derec])) {
                $deCosts[$derec] = [];
            }
            $deCosts[$derec]['DEQTY']                      = $row['DEQTY'];
            $deCosts[$derec]['DECOST']                     = iround($row['DECOST'],  ItemManager::AVERAGE_COST_DECIMALS);
            $deCosts[$derec]['NEWDECOST']                  = $deCosts[$derec]['DECOST'];  // assume no change yet
            $deCosts[$derec]['DEC'][$decrec]['DECCOST']    = iround($row['DECCOST'], ItemManager::AVERAGE_COST_DECIMALS);
            $deCosts[$derec]['DEC'][$decrec]['NEWDECCOST'] = $deCosts[$derec]['DEC'][$decrec]['DECCOST'];    // assume new = old
            $deCosts[$derec]['DEC'][$decrec]['DECQTY']     = $row['DECQTY'];
        }

        // Step 3: Now get the CURRENT COSTS of the parts
        //     (If the build-kit has been DISASSEMBLED, then it has no docentrycostkeys anymore, nor buildcostkeys)
        //
        //  *** NOTE as of Aug22 ***
        //
        //      docentrycostkits.buildcostkey is supposed to point to the docentrycost layer so you know, say,
        //  which source serial number went into which target serial number (though the customer doesn't really
        //  have to follow that).  Anyway, regular costing in MIV will possibly REASSIGN, in extreme cases, all
        //  of the docentrycostkits to the FIRST docentry of the build.  So, for now, we cannot rely on that.
        //
        $query   = [];
        $query[] = "SELECT  docentrykey as derec, sum(cost) as deckcost
                    FROM    docentrycostkits
                   WHERE    cny# = :1
                     AND    quantity > 0
                  ";
        $query[]  = GetMyCompany();
        $query    = PrepINClauseStmt($query, array_keys($stockableKitDocEntryRecordNumbers), " and docentrykey ");
        $query[0] .= " GROUP BY docentrykey ORDER BY docentrykey ";
        $result = QueryResult($query);
        if ($result === false) {
            return false;
        }

        if (empty($result)) {
            return false;   // disassembled or other error
        }

        // Step 4: Add the current costs to the existing costs
        foreach ($result as $row) {
            $derec  = $row['DEREC'];
            if ( ! isset($deCosts[$derec])) {
                continue;   // nope, don't want it
            }

            // save the overall cost of the build
            $deCosts[$derec]['NEWDECOST']  = iround($row['DECKCOST'], ItemManager::AVERAGE_COST_DECIMALS);
        }

        // Step 5: compute the new costs
        $removeThese = [];
        foreach ($deCosts as $derec => $derecRow) {

            $totalCost = $derecRow['NEWDECOST']; // if disassembled, same as original cost
            $deQty     = $derecRow['DEQTY'];     // must be > zero because of the sql query
            $unitCost  = ibcdiv($totalCost, $deQty, ItemManager::AVERAGE_COST_DECIMALS, true);

            $deCostNow = $derecRow['DECOST'];
            $changed   = ($totalCost != $deCostNow);

            foreach ($deCosts[$derec]['DEC'] as $decrec => $decRecRecord) {
                // spread the total cost evenly across the build's docentrycost records
                $decQty     = $decRecRecord['DECQTY'];
                $decCostNow = $decRecRecord['DECCOST'];   // cost as currently on disk
                $newDecCost = ibcmul($unitCost, $decQty, ItemManager::AVERAGE_COST_DECIMALS, true); // apportion it
                $deCosts[$derec]['DEC'][$decrec]['NEWDECCOST'] = $newDecCost;
                $changed    = $changed || ($decCostNow != $newDecCost);
            }
            if ( !$changed) {
                $removeThese[] = $derec;    // no need to update the record
            }
        }

        // Step 6:  remove records that do not need updating
        foreach ($removeThese as $derec) {
            unset($deCosts[$derec]);    // NOTHING TO DO HERE, SAME COST (unlikely decs changed but not the total)
        }

        return $deCosts;
    }


    /**
     *  Given new costs, update the docentry record for the kits
     *
     * @param  float[]      $costByDeRec          The cost the record should be, by record#
     *
     * @return bool
     */
    private function updateSpecificStockableKits($costByDeRec)
    {
        $ok    = true;
        $count = count($costByDeRec);
        if ($count === 0) {
            return $ok;
        }

        // let's not go too heavy on the poor Oracle server.
        // If the array is too big, cut it down.
        // The second call might cut down further (e.g., 1000 entries)
        if ($count > self::MAX_SQL_ARRAY_SIZE) {
            // Curses!  He recurses!
            $ok = $ok && $this->updateSpecificStockableKits( array_slice( $costByDeRec, 0, self::MAX_SQL_ARRAY_SIZE, true));  // true --> preserve keys
            $ok = $ok && $this->updateSpecificStockableKits( array_slice( $costByDeRec, self::MAX_SQL_ARRAY_SIZE, $count - self::MAX_SQL_ARRAY_SIZE,true));
            return $ok;
        }

        $query       = [];
        $recordArray = [];
        $costArray   = [];
        foreach ($costByDeRec as $deKey => $cost) {
            $recordArray[] = $deKey;
            $costArray[]   = $cost;
        }
        $arraySize   = count($recordArray);     // both arrays are the same size
        $records     = implode(',', $recordArray);
        $costs       = implode(',', $costArray);

        // do this in an array to reduce round-trips to Oracle
        $query[] =
            "DECLARE
                var_cny      NUMBER;
                type records IS VARRAY($arraySize) OF NUMBER; 
                type costs   IS VARRAY($arraySize) OF NUMBER; 
                var_keys     records;
                var_costs    costs;
                var_key      NUMBER;
                var_cost     NUMBER;
            BEGIN
                var_cny   := :1;
                var_keys  := records($records);
                var_costs := costs($costs);
                
                FOR i in 1 .. var_keys.count LOOP
                    var_key  := var_keys(i);
                    var_cost := var_costs(i);
                    
                    UPDATE   docentrymst 
                       SET   cost      = var_cost, value     = ROUND(var_cost,2), price = (var_cost / quantity),
                             uivalue   = var_cost, uiprice   = (var_cost / quantity),
                             trx_value = var_cost, trx_price = (var_cost / quantity)
                    WHERE   cny#        = var_cny
                    AND     record#     = var_key
                    AND     quantity    > 0;
                END LOOP;
            END;";

        $query[] = GetMyCompany();
        $ok      = ExecStmt($query);
        return $ok;
    }


    /**
     *  When docentrycost records need updating for a build kit...
     *
     * @param  float[]  $deccosts       costs by documententrycost record#s that we want
     *
     * @return bool
     */
    private function updateSpecificStockableKitParts($deccosts)
    {
        if (empty($deccosts)) {
            return true;
        }

        $query       = [];
        $recordArray = [];
        $costArray   = [];
        foreach ($deccosts as $decKey => $cost) {
            $recordArray[] = $decKey;
            $costArray[]   = $cost;
        }
        $arraySize   = count($recordArray);     // both arrays are the same size
        $records     = implode(',', $recordArray);
        $costs       = implode(',', $costArray);

        $query[] =
            "DECLARE
                var_cny      NUMBER;
                type records IS VARRAY($arraySize) OF NUMBER; 
                type costs   IS VARRAY($arraySize) OF NUMBER; 
                var_keys     records;
                var_costs    costs;
                var_key      NUMBER;
                var_cost     NUMBER;
            BEGIN
                var_cny   := :1;
                var_keys  := records($records);
                var_costs := costs($costs);
                
                FOR i in 1 .. var_keys.count LOOP
                    var_key  := var_keys(i);
                    var_cost := var_costs(i);
                    
                    UPDATE  docentrycost SET cost = var_cost, value = ROUND(var_cost,2), contributedcost = ROUND(var_cost,2), 
                            unitcost = (var_cost / quantity)
                    WHERE   cny#    = var_cny
                    AND     record# = var_key
                    AND     quantity    > 0;
                END LOOP;

                -- refresh any adjustments (there usually aren't any)
                UPDATE docentrycost SET quantity=quantity 
                WHERE  cny#               = var_cny
                AND    ADJDOCENTRYCOSTKEY IN ($records);
            END;";
        $query[] = GetMyCompany();
        $ok      = ExecStmt($query);
        return $ok;
    }




    //  *****************************************************************************************
    //  *****************************************************************************************
    //
    //  TRANSFERS
    //
    //      When the OUT side of a transfer changes, we need to update the IN side
    //      and re-apply any adjustments like landed costs.
    //      Also, there may be an exchange rate between OUT and IN.
    //
    //      Finally, we want the docentry record updated to reflect the changed costs.
    //      Many transactions don't display the costs, but transfers do.
    //
    //      Also, unlike MOST transactions, transfers can have many docentry records per source
    //      line on the transfer.  This was, I'm guessing, an attempt at preserving cost layers.
    //      however, with the new strategy of updates, cost layers may drift, which we should
    //      address at some point.
    //
    //  *****************************************************************************************
    //  *****************************************************************************************



    /**
     *      Given an array of unit costs and docentrykeys, update the docentry records to be that unit cost.
     *  We assume caller found that it needed updating.  We do it by unit cost on the theory that lots of costs
     *  for an item/warehouse will be the same.
     *
     *
     * @param array     $decentrykeysByUnitCost     array of unit costs as keys, array of docentrykeys as values
     * @param bool      $changed                    Were any changes made?  (only set on TRUE)
     *
     * @return bool                                 any sql errors?
     */
    private function updateDocentryWithNewUnitCost( $decentrykeysByUnitCost, &$changed)
    {
        if (empty($decentrykeysByUnitCost)) {
            return true;
        }
        $ok = true;
        foreach ($decentrykeysByUnitCost as $unitCost => $deRecs) { // array could be empty
            $query = [];
            $query[] = "UPDATE  docentrymst
                                SET cost      = (:2 * quantity),
                                    value     = ROUND((:2 * quantity),2), 
                                    price     = :2,
                                    uivalue   = ((:2 * quantity) / nvl( exchange_rate, 1)), 
                                    uiprice   = (:2 / nvl( exchange_rate, 1)), 
                                    trx_value = ((:2 * quantity) / nvl( exchange_rate, 1)), 
                                    trx_price = (:2 / nvl( exchange_rate, 1))
                            WHERE   cny#      = :1 ";
            $query[] = GetMyCompany();
            $query[] = $unitCost;
            $query   = PrepINClauseStmt($query, $deRecs, ' and record# ');
            $ok      = $ok && ExecStmt($query);
            $changed = true;
        }
        return $ok;
    }


    /**
     *  If you update a docentry cost, call this to re-apply any adjustments.
     * Adjustments update the cost and maybe quantity, but not the contributedcost or contributedqty, nor the value
     *
     *
     * @param int[]     $docentrykeys                       An array of docentry keys you want adjusted
     * @param int[]     $validAdjustmentDocentrycostkeys    docentry keys by docentrycost keys of those with adjustments
     * @param bool      $changed                            Were any changes made?  (only set on TRUE)
     *
     * @return bool                 sql problems?
     */
    private function applyAdjustments($docentrykeys, $validAdjustmentDocentrycostkeys, &$changed)
    {
        if (empty($docentrykeys) || empty($validAdjustmentDocentrycostkeys)) {
            return true;
        }

        // filter the docentrys by those that have adjustments
        $docentrykeys = array_flip($docentrykeys);
        $adjdocentrycostkeys = [];
        foreach ($validAdjustmentDocentrycostkeys as $docentrycostkey => $docentrykey) {
            if (isset($docentrykeys[$docentrykey])) {
                $adjdocentrycostkeys[] = $docentrycostkey;
            }
        }

        $ok = true;

        // now update any adjustments so they re-adjust their target document
        // (quantity = quantity will fire the trigger to update it)
        if ( ! empty($adjdocentrycostkeys)) {
            $changed  = true;
            $query    = [];
            $query[0] = "UPDATE  docentrycost SET quantity = quantity
                          WHERE   cny# = :1 ";
            $query[1] = GetMyCompany();
            $query    = PrepINClauseStmt($query, $adjdocentrycostkeys, " and adjdocentrycostkey ", false);
            $ok       = ExecStmt($query);
        }

        return $ok;
    }


    /**
     *      Given an array of unit costs and docentrykeys, update the docentry records to be that unit cost.
     *  We assume caller found that it needed updating.
     *
     *
     * @param array     $decentrykeysByUnitCost     array of unit costs as keys, array of docentrykeys as values
     * @param int[]     $targetAdjusted             array of docentrycosts that may need adjustments applied
     * @param bool      $changed                    Were any changes made?  (only set on TRUE)
     *
     * @return bool                                 any sql errors?
     */
    private function updateCostingWithNewUnitCost($decentrykeysByUnitCost, $targetAdjusted, $changed)
    {
        if (empty($decentrykeysByUnitCost)) {
            return true;
        }
        $ok = true;
        // note: part of the query below is invariant, so it might seem faster to NOT rebuild it each time,
        //       but lets do that later.
        $allDeKeys = [];
        foreach ($decentrykeysByUnitCost as $unitCost => $deKeys) { // array could be empty
            $query = [];
            // note: 'contributed cost' is the NON-ADJUSTED cost.  Starts out the same as cost,
            //       then an adjustment changes cost but NOT contributed cost.....
            $query[]   = "UPDATE  docentrycost
                                SET cost            = :2 * quantity, 
                                    contributedcost = :2 * quantity,
                                    contributedqty  = quantity,
                                    value           = ROUND(:2 * quantity,2), 
                                    unitcost        = :2, 
                                    lastunitcost    = :2
                            WHERE   cny#            = :1 ";
            $query[]   = GetMyCompany();
            $query[]   = $unitCost;
            $query     = PrepINClauseStmt($query, $deKeys, ' and docentrykey ');
            $ok        = $ok && ExecStmt($query);
            $changed   = true;
            $allDeKeys = array_merge($allDeKeys, $deKeys);   // remember ALL the docentrycosts we updated....
        }

        // now, re-apply any adjustments (like Landed Costs)....
        // (there may not be any, that's ok)
        // as stated above, this changes the costs, but not the adjusted costs
        // if we do not do this, then the adjustment is lost!  (i.e. no-one else will apply)
        // we want to apply adjustments to things we changed that HAVE adjustments.....

        $ok = $ok && $this->applyAdjustments($allDeKeys, $targetAdjusted, $changed); // ok if array is empty

        return $ok;
    }


    /**
     *  Given some OUT transaction docentry records, find the corresponding IN transactions.
     *  For 'Immediate' transfers, the source just has a source-doclinekey of the out.
     *  But for 'Intransit' transfers, the source-doclinekey is on the INTERMEDIATE transaction,
     *  and we want IT's source!
     *
     *  And, since we don't already know the appropriate entries to adjust for the Intransit types,
     *  add those onto the 'targetAdjusted' array
     *
     *
     * @param array     $deKeys                 Docentry keys of the OUT transaction we want to find INs for
     * @param array     $targetAdjusted         (IN and OUT) - the list of docentry records with adjustments
     *
     * @return array|bool                       false on failure, otherwise an array
     */
    private function getTheSourceOfOutTransaction($deKeys, &$targetAdjusted)
    {
        /** @var callable $findSource */
        $findSource = function($docentryKeys) {
            if (empty($docentryKeys)) {
                return [];
            }
            $query   = [];
            $query[] = "SELECT  de.record# as source, de.source_doclinekey as docentrykey, dp.docid
                        FROM    docentrymst de, dochdrmst dh, docparmst dp
                        WHERE   de.cny# = :1 and dh.cny# = de.cny# and dp.cny# = dh.cny# 
                            AND de.dochdrkey = dh.record# and dh.docparkey = dp.record# ";
            $query[] = GetMyCompany();
            $query   = PrepINClauseStmt($query, array_unique($docentryKeys), " and de.source_doclinekey ");

            return     QueryResult($query);
        };


        /** @var callable $colateSources */
        $collateSources = function($sourceQueryResult, &$rtn, $inTransit = null) {
            $getSourceForThese = [];
            foreach ($sourceQueryResult as $oneSource) {
                $docEntryKey = $oneSource['DOCENTRYKEY'];
                // first pass inTransit is null and we just take what is in the query results.
                // second pass the inTransit array has
                if ($inTransit !== null) {
                    $docEntryKey = $inTransit[$docEntryKey]; // so we have the OUT document's docentry rec
                }
                if ($oneSource['DOCID'] !== ICTransferManager::INDOCTYPE) {
                    $getSourceForThese[$oneSource['SOURCE']] = $docEntryKey;
                } else {
                    $rtn[$docEntryKey] = $oneSource['SOURCE'];
                }
            }
            return $getSourceForThese;
        };


        /** @var callable $areInTransitSourcesAdjusted */
        $areInTransitSourcesAdjusted = function($deRecs, &$targetAdjusted) {

            // Look at the docentry recs and see which ones have adjustments
            $query    = [];
            // we want the docentrycost attached to the docentry, if it has an adjustment.
            $query[0] = "SELECT de.record# as docentrykey, dc.record# as docentrycostkey
                          FROM  docentrymst de, docentrycost dc
                         WHERE  de.cny# = :1 and dc.cny# = de.cny#
                           AND  dc.docentrykey = de.record#
                           AND  EXISTS (
                                    SELECT
                                        1
                                    FROM
                                        docentrycost adj
                                    WHERE
                                        adj.cny# = dc.cny#
                                        AND   dc.record# = adj.adjdocentrycostkey
                           )";
            $query[1] = GetMyCompany();
            $query    = PrepINClauseStmt($query, $deRecs, " and de.record# ", false);
            $results  = QueryResult($query);
            if ($results === false) {
                return false;
            }
            foreach ($results as $row) {
                $targetAdjusted[$row['DOCENTRYCOSTKEY']] = $row['DOCENTRYKEY'];
            }
            return true;
        };


        // **********************************************************
        // **********************************************************
        //
        //  MAIN CODE
        //
        // **********************************************************
        // **********************************************************

        $rtn = [];

        // Step 1: find the source for these docentrys:
        $sources = $findSource($deKeys);
        if ($sources === false) {
            return false;
        }

        // collect the IN transactions, return in-transit transactions
        $inTransit = $collateSources($sources, $rtn);

        // Step 2: look for the source of the in-transit transactions
        $sources = $findSource(array_keys($inTransit));
        if ($sources === false) {
            return false;
        }

        // collect the IN transactions, return in-transit transactions (don't expect them this time)
        $inTransit2 = $collateSources($sources, $rtn, $inTransit);
        if ( ! empty($inTransit2)) {
            logFL("[DEBUG] In transit's source is not IN?");
        }

        if ($areInTransitSourcesAdjusted(array_values($rtn), $targetAdjusted) === false) {
            return false;
        }
        return $rtn;
    }


    /**
     *      This routine gets the docentry's SOURCES and updates the docentry's costing records with their
     *  source's value.  Then it returns the docentrycost values (perhaps updated)
     *
     *      Background: over in R_PKGBODY_INVCOST_UTILS.sql, in resetcostingtodate(), for FIFO, it specifically
     *          does NOT disconnect the costing records of a warehouse transfer OUT from their source in order to
     *          protect the costing layer.  Fine, except that it is the re-connecting that updates the cost!
     *          I think this works for Purchases, but not for SPI = I records.
     *
     *
     * @param int[]                 $deKeys             List of docentrykeys for the docentrys we want to update
     *
     * @return array|false                              array of unit costs by docentrykey, or false
     */
    private function updateCostsFromDocentrySource($deKeys)
    {
        // not all records will HAVE a source, and many won't be the wrong unit cost....
        $keyList = PrepINClauseStmt('', array_unique($deKeys), " and dec.docentrykey ", false ); // no binding, these are record numbers
        $query   = [];
        $query[] = "BEGIN
        FOR entry IN (
            SELECT  dec.cny#, dec.record# as docentrycostkey, sourcedec.unitcost
                    FROM    docentrycost dec, docentrycost sourcedec
                    WHERE   dec.cny# = :1
                      and   sourcedec.cny# = dec.cny# and sourcedec.record# = dec.docentrycostkey
                      and   sourcedec.unitcost != dec.unitcost
                      and   dec.costmethod in ('F','L')
                      $keyList
            ) LOOP
            UPDATE docentrycost
                SET
                    lastunitcost    = entry.unitcost,
                    cost            = round(quantity * entry.unitcost,10),
                    contributedcost = round(quantity * entry.unitcost,10)
                WHERE cny# = entry.cny# and record# = entry.docentrycostkey;
            END LOOP;
        END;";
        $query[] = GetMyCompany();
        $ok      = ExecStmt($query);
        return $ok;
    }


    /**
     *  Simple question, it would seem: what is the cost of a docentry?  And it's costing layers?
     *  They may not be the same, but this just returns them in formats consumers want....
     *
     *
     * @param int[]             $deKeys                 List of docentrykeys
     * @param bool              $getUnadjustedCost      get the 'contributed cost', i.e. the non-adjusted cost?
     * @param bool              $gettingINCostsFromOUT  getting the costs for which the passed docentrykeys are the SOURCE_DOCLINE?
     *
     * @return array|false                              array of unit costs by docentrykey, or false
     */
    private function getCostsOfDocEntries($deKeys, $getUnadjustedCost = false, $gettingINCostsFromOUT = false)
    {
        $rtn = [];
        if (empty($deKeys)) {
            return $rtn;
        }
        // get the current costs and docentry cost
        // docentry should reflect any adjustments, and so is not always the same as the GL, which should be the contributed cost
        if ($getUnadjustedCost) {
            $decCostField     = "dec.contributedcost";
            $decQuantityField = "dec.contributedqty";
        } else {
            $decCostField     = "dec.cost";
            $decQuantityField = "dec.quantity";
        }
        $query   = [];
        $query[] = "SELECT  de.record# as docentrykey, de.price as deunitcost, de.currency,
                            (sum(nvl($decCostField,0)) / sum(nvl($decQuantityField,0))) as decunitcosts,
                            (sum(nvl(dec.cost,0)) / sum(nvl(dec.quantity,0))) as decadjustedcosts
                    FROM    docentrymst de, docentrycost dec
                    WHERE   de.cny# = :1 and dec.cny# = de.cny# and dec.docentrykey = de.record#
                      AND   de.quantity > 0 and $decQuantityField > 0 
                      AND   dec.affects_inventory in ('Q', 'QV')";
        $query[] = GetMyCompany();
        $query   = PrepINClauseStmt($query, array_unique($deKeys), " and de.record# " );
        $query[0] .= " GROUP BY de.record#, de.price, de.source_doclinekey, de.currency ";
        $result  = QueryResult($query);
        if ($result === false) {
            return false;
        }

        // now, we have the de costs and the dec costs, lets return this data in useful ways
        foreach ($result as $row) {
            // cost might be null
            $unitCostDe   = iround($row['DEUNITCOST']       ?? '0', ItemManager::AVERAGE_COST_DECIMALS);
            $unitCostDecs = iround($row['DECUNITCOSTS']     ?? '0', ItemManager::AVERAGE_COST_DECIMALS);
            $unitCostAdj  = iround($row['DECADJUSTEDCOSTS'] ?? '0', ItemManager::AVERAGE_COST_DECIMALS);
            $currency     = $row['CURRENCY'];

            // GUARDRAIL!!  If we're getting out costs, not in costs FROM out costs,
            //  If the docentrycosts are ZERO or NEGATIVE, that is bad news, so skip it so we don't force things to zero
            // (if the out is not zero and the in IS zero, we'll fix it)
            if ( ( ! $gettingINCostsFromOUT) &&
                    (ibccomp($unitCostDecs, '0', ItemManager::AVERAGE_COST_DECIMALS) <= 0)) {
                continue;
            }
            $rtn[$row['DOCENTRYKEY']] =
                        ['DEUNITCOST'   => $unitCostDe,
                         'DECUNITCOSTS' => $unitCostDecs,
                         'OTHERCOST'    => $unitCostAdj,
                         'CURRENCY'     => $currency ];
        }
        return $rtn;
    }


    /**
     *      When we update costs in docentrycost records, we do not automatically update the docentry record.
     * Much of our UI does not show the costing information and so it isn't a big deal.  But in transfers we do.
     * So, explicitly update docentry to match its underlying costs if they do not agree.
     *
     *
     * @param int[]     $deKeys             The docentrykeys to match with their costs
     * @param bool      $changed            Were any changes made?  (only set on TRUE)
     *
     * @return array|bool                   Array of docentrykeys with unit costs, or false
     *                                      (the format of getCostsOfDocEntries)
     */
    private function updateDocEntryToMatchCosts($deKeys, &$changed)
    {
        $rtn     = [];
        if (empty($deKeys)) {
            return $rtn;
        }

        // Make sure this OUT transaction has the correct cost from its source(s)

        if ( ! $this->updateCostsFromDocentrySource($deKeys)) {
            return false;
        }

        // get the costs of the docentries, with adjustments
        $rtn = $this->getCostsOfDocEntries($deKeys);
        if ($rtn === false) {
            return false;
        }

        // see if we need to fix anything
        $fixThese = [];
        foreach ($rtn as $docentrykey => $row) {
            $unitCostDe   = $row['DEUNITCOST']; // already rounded
            $unitCostDecs = $row['DECUNITCOSTS'];
            if (ibccomp($unitCostDe, $unitCostDecs, ItemManager::AVERAGE_COST_DECIMALS) != 0) {
                $fixThese[$unitCostDecs][] = $docentrykey; // this one needs fixing, by unit cost
            }
        }

        // update the docentry from its costs if need be
        // (hopefully this doesn't happen a lot)
        if ( ! $this->updateDocentryWithNewUnitCost($fixThese, $changed)) {   // array can be empty
            return false;
        }
        return $rtn;    // return ALL the costs we got above, not just fixed costs
    }


    /**
     *  A warehouse transfer can include an exchange rate.  If you look at the ictransferhdr record, and then data,
     *  and stare at the ictransfermanager code, and have some coffee, you'll learn that:
     *
     *      - ictransferhdr has three interesting fields here:
     *      - CURRENCY          This is the BASE currency of the OUT warehouse
     *      - BASECURR          This is the BASE currency of the IN  warehouse
     *      - EXCHANGE_RATE     This TIMES the OUT is the IN
     *
     *  BASECURR = CURRENCY * EXCHANGE_RATE
     *    IN     =    OUT   * EXCHANGE_RATE
     *
     * Most transfers won't have an exchange rate other than 1.
     *
     * @param array   $deKeysINWithUnitCost    array of unit costs indexed by docentry for the IN docentry with the OUT's cost!
     *
     * @return bool                            any sql error?
     */
    private function applyExchangeRates( & $deKeysINWithUnitCost)
    {
        $ok = true;
        if (empty($deKeysINWithUnitCost)) {
            return $ok;
        }

        // ARE there exchange rates we need to worry about?
        // the dekey should always be for the IN warehouse, or indochdrkey, but lets just be sure
        // Often, this will return NO records (i.e. no exchange rates other than 1)
        $query   = [];
        $query[] = "SELECT de.record# as docentrykey, x.exchange_rate
                      FROM ictransferhdrmst x, docentrymst de
                      WHERE x.cny# = :1 and de.cny# = x.cny# 
                        AND de.dochdrkey = x.indochdrkey
                        AND x.exchange_rate IS NOT NULL and x.exchange_rate != 1 ";
        $query[] = GetMyCompany();
        $query   = PrepINClauseStmt($query, array_keys($deKeysINWithUnitCost), " and de.record# ");
        $result  = QueryResult($query);
        if ($result === false) {
            return false;
        }

        // Anything to do?  Most customers don't do transfers between currencies
        // Now, assume the unit costs are correct, but in the OUT warehouse's currency.
        foreach ($result as $row) { // could be empty!
            $deKey          = $row['DOCENTRYKEY'];
            $exchangeRate   = $row['EXCHANGE_RATE'];
            if (isset($deKeysINWithUnitCost[$deKey])) {  // Really should be there, but be paranoid
                // we are given OUTs costs, want to convert inline to INs costs
                //    IN                      =                  OUT       *          EXCHANGE_RATE
                $deKeysINWithUnitCost[$deKey] = ibcmul($deKeysINWithUnitCost[$deKey], $exchangeRate, ItemManager::AVERAGE_COST_DECIMALS, true);
            }
        }
        return $ok;
    }


    /**
     *      For an IN document, you may want to update its costs from its source OUT document, if it has one.
     * Passed in is the list of the SOURCE (OUT) costs and docentrykeys.  Find the IN records and see if they match.
     * If they don't, force them to match.
     *
     *
     * @param int[]     $deKeysOfOutWithUnitCost        the format returned by getCostsOfDocEntries
     * @param int[]     $targetAdjusted                 the IN docentrycosts that have adjustments
     * @param bool      $changed                        Were any changes made?  (only set on TRUE)
     *
     * @return bool                                     did sql succeed?
     */
    private function updateCostsToMatchSource($deKeysOfOutWithUnitCost, $targetAdjusted, &$changed)
    {
        $ok = true;
        if (empty($deKeysOfOutWithUnitCost)) {
            return $ok;
        }

        // Make sure we have the right source documents, and maybe update the target adjusted cost layers
        $sources = $this->getTheSourceOfOutTransaction(array_keys($deKeysOfOutWithUnitCost), $targetAdjusted);

        // get the costs of the IN, WITHOUT adjustments
        // we know the OUT docentrykeys, but not the IN
        // Source is OUT-->IN, but we prefer IN-->OUT
        $sources  = array_flip($sources);
        $inCosts = $this->getCostsOfDocEntries(array_keys($sources), true, true);
        if ($inCosts === false) {
            return false;
        }

        // First, do currency conversion if need be....
        $convertCurrency = [];
        foreach ($inCosts as $docentrykeyIn => $row) {
            // result are the IN values, compare with OUT
            $docentrykeyOut = $sources[$docentrykeyIn] ?? 0; // the source; why would it be missing its original value?
            if ($docentrykeyOut) {
                $outCosts       = $deKeysOfOutWithUnitCost[$docentrykeyOut] ?? [];
                $inCurrency     = $row['CURRENCY'] ?? 'USD';
                $outCurrency    = $outCosts['CURRENCY'] ?? $inCurrency;
                if ($inCurrency !== $outCurrency) {     // like USD to NZD
                    $convertCurrency[$docentrykeyIn] = $outCosts['DECUNITCOSTS']; // we'll convert this one
                }
            }
        }
        // is there an exchange rate?
        // if so, update the IN-sides unit cost
        $ok = $this->applyExchangeRates($convertCurrency);    // ok if empty

        // see if we need to fix anything
        $fixThese = [];
        $otherAdjustments = [];
        foreach ($inCosts as $docentrykeyIn => $row) {

            // result are the IN values, compare with OUT
            $docentrykeyOut = $sources[$docentrykeyIn] ?? 0;
            if ($docentrykeyOut) {
                $outCosts = $deKeysOfOutWithUnitCost[$docentrykeyOut] ?? [];
                // odd that the out couldn't be found because we specifically looked for it,
                // but maybe it was zero.....
                if (empty($outCosts)) {
                    continue;   // we'll skip it.
                }

                // does the out already agree with the in?
                // remember we are comparing FULL COST OUT with NON-ADJUSTED COST IN
                // and maybe in the OUT-->IN exchange rate units
                // also, we converted the OUT cost using the IN's exchange rate!  Confusing, I know!
                // but because of that use the IN docentrykey to get the (modified) OUT cost
                $unitCostOut  = $convertCurrency[$docentrykeyIn] ?? $outCosts['DECUNITCOSTS']; // already rounded
                $unitCostIn   = $row['DECUNITCOSTS'];
                $unitCostInDe = $row['DEUNITCOST'];

                // if they do not match, we want to set the IN to the cost of the OUT (and then re-apply adjustments)
                $deDecCostIsDifferent = (ibccomp($unitCostIn, $unitCostInDe, ItemManager::AVERAGE_COST_DECIMALS) != 0);
                if ((ibccomp($unitCostOut, $unitCostIn, ItemManager::AVERAGE_COST_DECIMALS) != 0) || $deDecCostIsDifferent) {
                    $fixThese[$docentrykeyIn] = $unitCostOut; // the IN needs the OUTs unit cost
                    $changed = true;
                } else {  // UC ok and adjusted the same?
                    // the contributed cost and the regular cost are almost the same; maybe we still need to apply adjustments?
                    // (this is a fix for back when we weren't applying adjustments)
                    $otherAdjustments[] = $docentrykeyIn;   // note these are docentry, not docentrycost
                }
            }
        }

        // if there are costs to fix, fix them now
        if ( ! empty($fixThese)) {
            // Now flip so the unit costs are the key and docentrykeys are the values...
            // only use the docentrycost value as that is accurrate
            $updateThese = [];
            foreach ($fixThese as $deKey => $unitCost) {
                $updateThese[$unitCost][] = $deKey;
            }

            // fix both the cost layers and the docentry; ok if arrays are empty
            $ok = $ok && $this->updateCostingWithNewUnitCost($updateThese, $targetAdjusted, $changed) &&
                         $this->updateDocentryWithNewUnitCost($updateThese, $changed);
        }

            // Note that these are docentry keys, not docentrycost keys....
        $ok = $ok && $this->applyAdjustments($otherAdjustments, $targetAdjusted, $changed); // ok if array is empty

        return $ok;
    }


    /**
     *  Occasionally a transfer in without a source gets crushed down to zero for reasons I don't yet understand,
     *  but when it is, the 'contribited cost' is still there, so we can restore it to that cost.
     *
     *
     * @param int[]      $deKeys            an array of docentrykeys to restore if need be
     * @param int[]      $targetAdjusted    an array of docentrycostkeys to adjust if need be
     * @param bool       $changed           Were any changes made?  (only set on TRUE)
     *
     * @return bool
     */
    private function recoverOrphanedZeroTransferIns($deKeys, $targetAdjusted, &$changed)
    {
        $ok = true;
        if (empty($deKeys)) {
            return $ok;
        }

        // we know the cost is zero, but get the CONTRIBUTED cost and see if it is not zero.....
        $costsByDeRec = $this->getCostsOfDocEntries($deKeys, true, false);
        if ($costsByDeRec === false) {
            return false;
        }

        $fixThese = [];
        foreach ($costsByDeRec as $deKey => $costs) {   // might be empty!
            $decUnitCost = $costs['DECUNITCOSTS'];  // already rounded
            if (ibccomp($decUnitCost, '0') != 0) {
                $fixThese[$decUnitCost][] = $deKey;
            }
        }

        // fix both the cost layers and the docentry
        // (ok if array is empty)
        $ok = $this->updateCostingWithNewUnitCost($fixThese, $targetAdjusted, $changed) &&
              $this->updateDocentryWithNewUnitCost($fixThese, $changed);

        return $ok;
    }


    /**
     *      Adjust transfers - Transfer INs can be updated from their OUTs
     *
     * Note: This ONLY works if you create the OUT first and then the IN and tie the IN to the OUT
     *      Doing it the other way around doesn't seem to set up the links we need
     *
     * @param array     $lineItems          The list of transactions
     * @param int       $startHere          Where to start in the list
     * @param string    $costMethod         Current cost method
     * @param bool      $changed            Were there any changes?  (only set if TRUE)
     *
     * @return bool
     */
    public function adjustTransfers(&$lineItems, $startHere, $costMethod, &$changed)
    {
        // ***** HELPER FUNCTIONS *****

        /** @var callable $isZero */
        $isZero = function($n) {
            // PHP 8.1....
            return (($n === '') || ($n === '0') || ($n === 0));
        };


        // ********************
        // **** MAIN CODE *****
        // ********************
        if ($costMethod === 'S') {
            return true;    // nothing to do
        }
        $ok                             = true;
        $anyFound                       = false;
        $item_key                       = $lineItems[$startHere]['COMP'];
        $warehouse_key                  = $lineItems[$startHere]['WAREHOUSEKEY'];
        $updateTransferOuts             = [];
        $updateOrphanTransferIns        = [];
        $targetCostsAreAdjusted         = [];
        $costsAreAdjusted               = [];

        // ********** STEP ONE: Collect TRANSFERs to maybe update **************
        $countOfLines = count($lineItems);
        $key          = $startHere;
        while ($key < $countOfLines) {

            $line = $lineItems[$key];   // current line

            // Are we done for this item/warehouse?
            if (($line['COMP'] != $item_key) || ($line['WAREHOUSEKEY'] != $warehouse_key)) {
                break;
            }

            // is this a transfer out?  or in?
            $isATransferOut = (($line['DOCPARID'] == ICTransferManager::OUTDOCTYPE) || ($line['DOCPARID'] == 'Inventory Transfer Out'));
            $isATransferIn  = (($line['DOCPARID'] == ICTransferManager::INDOCTYPE)  || ($line['DOCPARID'] == 'Inventory Transfer In'));
            $isATransferIn  = $isATransferIn  && ($line['QUANTITY'] != 0);
            $isATransferOut = $isATransferOut && ($line['QUANTITY'] != 0);

            // we care about transfer OUTs....
            if ($isATransferOut) {
                // update the docentry from its costs
                $deRec                      = $line['DEREC'];
                $updateTransferOuts[$deRec] = true;
                $anyFound                   = true;

                // If this OUT has an IN that is adjusted,
                // collect all the docentrycost record numbers for adjustment
                if (isset($line['TARGET_ADJUSTED'])) {  // is the IN adjusted?
                    foreach ($line['TARGET_ADJUSTED'] as $targetDec => $targetDe) {
                        $targetCostsAreAdjusted[$targetDec] = $targetDe;    // so we know who the docentrycost belongs to
                    }
                }
            }

            // and orphaned transfer ins with no source
            if ($isATransferIn) {
                $deRef   = ($line['DEREF']  ?? 0);  // does it have a source_doclinekey?
                $decRef  = ($line['DECREF'] ?? 0);  // or a source docentrycost?
                $cost    = ($line['COGS']   ?? 0);  // or any cost?
                // if it has a reachable source, then we don't care about it (its OUT will update it)
                if ($isZero($deRef) && $isZero($decRef) && $isZero($cost)) {
                    $deRec                           = $line['DEREC'];
                    $updateOrphanTransferIns[$deRec] = true;
                    $anyFound                        = true;

                    // if this IN is adjusted, remember to re-apply the adjustment
                    if (isset($line['ADJUSTED_BY'])) {  // is this IN adjusted?
                        $costsAreAdjusted[$line['DECREC']] = $deRec;    // so we know who the docentrycost belongs to
                    }
                }
            }
            $key++;
        }

        if ($anyFound) {

            // ****************** STEP TWO: UPDATE ORPHANED TRANSFER INS *******************
            $ok = $ok && $this->recoverOrphanedZeroTransferIns(array_keys($updateOrphanTransferIns), $costsAreAdjusted, $changed);

            // ****************** STEP THREE: UPDATE TRANSFER OUTS *******************
            if ($ok) {
                $costsOfOuts = $this->updateDocEntryToMatchCosts(array_keys($updateTransferOuts), $changed);
                if ($costsOfOuts === false) {
                    $ok = false;
                }
                // and now update the OUT's IN records, if reachable
                $ok = $ok && $this->updateCostsToMatchSource($costsOfOuts, $targetCostsAreAdjusted, $changed);
            }
        }
        return $ok;
    }




    /**
     *  Update the docentry cost to be the same as sum(docentrycost) costs.  Ignore the docentrycostkits, as this
     *  is not applied to Build transactions.
     *
     * This is called from InvCotToolManager::findUpdates(), when we discover things out of whack.  Here, we don't
     * rely on what that routine found except for the list of doc entry record#s to update.
     *
     * @param array      $fixDocEntry   an array of DocEntry record#s to fix
     *
     * @return bool                     did it work?
     */
    public function updateDocEntrysCostFieldToMatchDocEntryCost($fixDocEntry)
    {
        if (empty($fixDocEntry)) {
            return true;    // no error, but nothing to do
        }

        // one time, get the INI clause.  Don't bother with binding; the fields are record#s
        $records = PrepINClauseStmt('', $fixDocEntry, ' and record# ', false);

        $qry   = [];
        $qry[] =
            "DECLARE
                var_cny NUMBER;
            BEGIN
                var_cny := :1;
                
                -- set the cost, fix any bad exchange rates
                UPDATE docentrymst docentry SET cost = 
                    (select sum(cost) from docentrycost where docentrycost.cny# = var_cny and docentrycost.docentrykey = docentry.record#),
                     exchange_rate = decode( exchange_rate, 0, 1, null, 1, exchange_rate)
                  WHERE cny# = var_cny AND (quantity != 0) $records;
                  
                -- now set everything else from the cost
                UPDATE  docentrymst SET 
                     value     = ROUND(cost,2), 
                     price     = (cost  / quantity),
                     uivalue   = (cost  / exchange_rate),
                     uiprice   = ((cost / quantity) / exchange_rate),
                     trx_value = (cost  / exchange_rate), -- should I round?
                     trx_price = ((cost / quantity) / exchange_rate)
                  WHERE cny# = var_cny AND (quantity != 0) $records;
            END;";
        $qry[] = GetMyCompany();

        return ExecStmt($qry);
    }


}