<?php

/**
 *      Inventory Business Logic for Wholesale Distribution
 *
 *  I thought about burying this into some place like Inventory Work Queue or InventoryWQDetails,
 *  but in the future there will be other applications like work orders that will have different
 *  business logic than Fulfillment, so let's isolate these....
 *
 *  This is the logic for moving things around the Work Queues for Fulfillment or any other WD app
 *  that moves stuff around using InventoryWorkQueue
 *
 * Roger Collins, August, 2021
 */

class InvBizLogicForWD
{
    // These sorta align with the UI tabs
    const CATEGORY_UNKNOWN              = -1;
    const CATEGORY_NOT_IN_FULFILLMENT   = 0;
    const CATEGORY_PICKING              = 1;
    const CATEGORY_PACKING              = 2;
    const CATEGORY_SHIPPING             = 3;
    const CATEGORY_INVOICING            = 4;


    // types of TD's
    const TD_TYPE_OTHER                 = '?';
    const TD_TYPE_SALESORDER            = 'O';
    const TD_TYPE_SHIPPER               = 'S';
    const TD_TYPE_INVOICE               = 'I';
    const TD_TYPE_SHIP_AND_INVOICE      = 'X';
    const TD_TYPE_SHIP_DRAFT            = 'D';
    const TD_TYPE_HIDDEN_SALESORDER     = 'H';  // a sales order with NO fulfillment, but WITH 'enable reserve/allocate'

    // for bundlesInFulfillment():
    const BUNDLES_IN_FULFILLMENT_ALL             = 1;
    const BUNDLES_IN_FULFILLMENT_OPEN_ONLY       = 2;
    const BUNDLES_IN_FULFILLMENT_OTHER_THAN_OPEN = 3;



    /** @var array      $totalsData  item/warehouse totals from the Item Manager */
    private  static     $totalsData = [];

    /** @var array      $itemsAreTracked  is a given item tracked or not? */
    private  static     $itemsAreTracked = [];

    /** @var bool       $allowNegativeUncommitted  checkbox on inventory config: can we allow negative uncommitted? */
    private  static     $allowNegativeUncommitted = null;   // signal that it has not yet been set up

    /** @var string[]   $docStateByDocHdrKey    for a given document header record#, what is the STATE of that document?  */
    private  static     $docStateByDocHdrKey = [];

    /** @var int[]      $docParKeyByDocHdrKey    Given a doc hdr record#, what is its docpar key? */
    private  static     $docParKeyByDocHdrKey = [];

    /** @var array      $docParByDocParKey         The DOCPAR for the docparkeys  */
    private  static     $docParByDocParKey = [];

    /** @var array      $quantitiesWhenOpen        saved DocEntry quantities from when it was open  */
    private  static     $quantitiesWhenOpen = [];

    /** @var array      $docEntriesWithReserveAllocOn      what doc entries are we likely to change that care about R/A? */
    private  static     $docEntriesWithReserveAllocOn = [];

    /** @var array      $docHdrsWithReserveAllocOn         which doc hdrs enable reserve/alloc? */
    private  static     $docHdrsWithReserveAllocOn = [];


    // if we are computing availability for an item/warehouse, we rely on the get-before-put to return
    //   the latest availability (i.e. before this commit).  BUT, if you have, say, TWO rows with Item A,
    //   they both think there are, say, 10 available.  But the first one might take 6 of them, or all 10.
    //   so this very tiny cache tracks how much has already been consumed in this interaction by item/warehouse
    /** @var array      $runningItemWarehouseTotals  for running values of allocated/available/etc */
    private  static     $runningItemWarehouseTotals = [];

    /** @var bool[]     $docEntriesToSaveRestoreReserveAllocate */
    private             $docEntriesToSaveRestoreReserveAllocate;

    /** @var InventoryWorkQueueManager  $workQueueManager The InventoryWorkQueueManager  */
    private             $workQueueManager   = null;       // holds the InventoryWorkQueueManager

    /** @var SODocumentManager $soDocumentManager */
    private             $soDocumentManager = null;


    // Constructor
    function __construct()
    {
        $this->docEntriesToSaveRestoreReserveAllocate   = [];
        $this->workQueueManager                         = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");

    }


    //  ***********************************************************************************
    //  ***********************************************************************************
    //
    //  PUBLIC BIZ LOGIC
    //
    //  ***********************************************************************************
    //  ***********************************************************************************


    /**
     *      Fulfillment Details Update: the API/UI has changed things in a detail
     *  record and wants to save it.  Do we let them?  Do we alter some fields for them?
     *
     *      These are both InventoryWQDetail records.  The CURRENT record is fresh
     *  off SQL, and so we can see what the old data was (the STATUS, for example).
     *  The UPDATED record may have been generated milliseconds ago, or an API user
     *  might have been staring at it for hours.  So, it can be 'stale' in the fields
     *  like ONHAND/RESERVED/ALLOCATED/etc.  On the other hand, if the caller reads
     *  a bunch of records, they'll all have the same amounts available, and so we need
     *  to get our own data.
     *
     *  The updated record may be updated further to include, for example, a new RESERVED value.
     *
     * @param array     $currentRec         The current, pre-update, record
     * @param array     $updatedRec         The updated record from the API/UI; we may further change it.
     * @param array     $splitValue         If we need to split, then this is set to the NEW record/values
     *
     * @return bool                         Everything ok?
     */
    public function fulfillmentDetailsUpdate($currentRec, & $updatedRec, & $splitValue)
    {
        $iwqManager = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");
        $splitValue = [];   // empty means 'not used'

        // Normalize the status to the internal, non-English format (like 'RPI')
        // (statusForName() will allow an internal status to be passed as the external name, so, no worries)
        $currentRec['STATUS'] = $iwqManager->statusForName($currentRec['STATUS']);
        $updatedRec['STATUS'] = $iwqManager->statusForName($updatedRec['STATUS']);
        if ( ! isset($currentRec['DOCUMENTTYPE']) || ($currentRec['DOCUMENTTYPE'] == '')) {
            $currentRec['DOCUMENTTYPE'] = self::typeOfTD($currentRec['DOCHDRKEY']);
        }
        InventoryWorkQueueManager::clearNote($updatedRec);


        // Check fields that should not be changed by user
        $ok =        $this->checkForFieldsThatCantChange($currentRec, $updatedRec);

        // Is the document on hold?  Are they trying to move?
        $ok = $ok && $this->checkForHold($currentRec, $updatedRec);

        // Are they moving but, for example, are already converted?  That limits their options
        $ok = $ok && $this->movementOkGivenState($currentRec, $updatedRec);

        // Do we need to save off or restore the reserve/allocate values in docentry?
        // (do this before we update alloc/reserve)
        $ok = $ok && $this->checkForReserveAllocationStorage($currentRec, $updatedRec);

        // Do they need allocations?
        $ok = $ok && $this->maybeAllocate($currentRec, $updatedRec);

        // what about reservations?
        $ok = $ok && $this->maybeReserve($currentRec, $updatedRec);

        // do we need to split the record?
        $ok = $ok && $this->maybeSplit($currentRec, $updatedRec, $splitValue);

        return $ok && $this->markDocEntriesNeedingUpdate($currentRec, $updatedRec);
    }


    /**
     *  The above routine was called in a loop for all the records being added/saved.  Here,
     *  do we have any leftover work to do?  Specifically:
     *
     *  - any doc entry records that need their 'saved' reserve/allocate numbers saved or restored
     *  - same for tracking records
     *  - some tracking records may be DELETED if they weren't there at the time of moving to OPEN
     *
     * @return bool                             Everything ok?
     */
    public function bizLogicCleanup()
    {
        $ok           = true;
        $cny          = GetMyCompany();
        $saveThese    = [];
        $restoreThese = [];

        // which, if any, need cleanup?
        foreach ($this->docEntriesToSaveRestoreReserveAllocate as $deRecordNumber => $save) {
            if ($save) {
                $saveThese[]    = $deRecordNumber;
            } else {
                $restoreThese[] = $deRecordNumber;
            }
        }

        // Cleanup 1: save the current reserved/allocated values for when we go BACK to open
        if (!empty($saveThese)) {
            $sql   = [];
            $sql[] = "UPDATE docentrymst 
                        SET quantityreservedwhenopen  = quantityreserved,
                            quantityallocatedwhenopen = quantityallocated
                       WHERE cny# = :1 
                         AND ((quantityreserved is not null) OR (quantityallocated is not null)) ";
            $sql[] = $cny;
            $sql   = PrepINClauseStmt($sql, $saveThese, ' and record# ');
            $ok    = $ok && ExecStmt($sql);

            // Note: I think these were just written as part of saving the InventoryWorkQueue records?
            /* ***********************
            $sql2   = [];
            $sql2[] = "UPDATE docentrytrackdetail 
                        SET quantityreservedwhenopen  = quantityreserved,
                            quantityallocatedwhenopen = quantityallocated
                       WHERE cny# = :1 
                         AND ((quantityreserved is not null) OR (quantityallocated is not null)) ";
            $sql2[] = $cny;
            $sql2   = PrepINClauseStmt($sql2, $saveThese, ' and docentrykey ');
            $ok    = $ok && ExecStmt($sql2);
            ***************************** */
        }

        // docentry reserve/alloc may need updating
        // DO THIS AFTER SAVING THE ABOVE (which was pre-update)
        // also, docentry records moving back to OPEN can use the same code.

        foreach (self::$docEntriesWithReserveAllocOn as $de => $tracked) {
            if ( ! in_array($de, $restoreThese)) {
                $restoreThese[] = $de;
            }
        }
        $ok = $ok && $this->updateDocEntryWithAlloc($restoreThese);

        $this->docEntriesToSaveRestoreReserveAllocate = []; // so we don't try again
        return $ok;
    }



    //  ***********************************************************************************
    //  ***********************************************************************************
    //
    //  CACHE ROUTINES AND UTILITIES
    //
    //  ***********************************************************************************
    //  ***********************************************************************************




    /**
     *  We create a work queue record per docentry that needs one here
     *
     * @param array     $documentTree           DocumentManager's document tree
     * @param string    $place                  What 'place' (queue/status) do we put the records in?
     * @param string    $why                    Why are we creating this (optional)
     *
     * @return bool
     */
    private function createNewWorkRecords( & $documentTree, $place, $why = '')
    {
        $getWarehouse = function($docEntry) {
            $wh     = $docEntry['WAREHOUSE']['LOCATION_NO'] ?? ($docEntry['WAREHOUSEID'] ?? '');
            [ $wh ] = explode('--', $wh);
            return $wh;
        };


        $newIwqs      = [];
        $deKeyToIndex = [];
        $documentType = self::documentTypeFromDocTree($documentTree);
        $enableFulfillmentFlag  = (($documentTree['_DOCPAR']['ENABLEFULFILLMENT'] ?? 'false') === 'true');

        $itemIds = [];
        foreach ($documentTree['ENTRIES'] as $index => $entry) {
            [ $itemID ] = explode( '--', $entry['ITEMID']);
            $documentTree['ENTRIES'][$index]['ITEMID'] = $itemID;
            $itemIds[$itemID] = true;
        }

        $trackingNeededByItemId = self::getTrackedStatusOfItems(array_keys($itemIds));

        // each row that should have a work queue entry gets one....
        foreach ($documentTree['ENTRIES'] as $index => $docEntry) {

            // should it have a work queue record?
            if ($this->docEntryShouldHaveAWorkQueue($docEntry, $reservableItem, $trackingNeededByItemId, $enableFulfillmentFlag)) {
                $itemID                 = $docEntry['ITEMID'];
                $canRunOut              = ($trackingNeededByItemId[ $itemID ]['CANRUNOUT'] ?? true);               // non-inventory item?

                // work queue records call things slightly differently than docentry.
                // fix that up now....
                $deKeyToIndex[$docEntry['WORKKEY']] = $index;
                $docEntry['DOCENTRYKEY']            = $docEntry['RECORDNO'];
                $docEntry['DOCHDRKEY']              = $docEntry['DOCHDRNO'];
                $docEntry['UOM']                    = $docEntry['UNIT'];
                $docEntry['CONVFACTOR']             = $docEntry['MULTIPLIER'];
                $docEntry['ORDERDATE']              = $documentTree['WHENCREATED'];
                $docEntry['STATUS']                 = $place;
                $docEntry['WAREHOUSEID']            = $getWarehouse($docEntry);
                $docEntry['LINENO']                 = $docEntry['LINE_NO'] + 1;        // make 1-based, not 0 based
                $docEntry['QUANTITYINRESERVE']      = $docEntry['QUANTITYRESERVED']  ?? 0;
                $docEntry['QUANTITYPICKED']         = $docEntry['QUANTITYALLOCATED'] ?? 0;
                $docEntry['QUANTITYPACKED']         = 0;
                $docEntry['QUANTITYINALLOCATION']   = $docEntry['QUANTITYALLOCATED'] ?? 0;
                $docEntry['DOCUMENTTYPE']           = $documentType;

                // an item or stockable kit?  Not a non-inventory item
                if ($canRunOut) {
                    $docEntry['DELTARESERVE']    = $docEntry['QUANTITYINRESERVE']    ?? 0;  // since we're starting from zero....
                    $docEntry['DELTAALLOCATION'] = $docEntry['QUANTITYINALLOCATION'] ?? 0;
                }

                $rtn = $this->workQueueManager->createWorkQueueRecordFromDocEntry($docEntry, false); // false means 'new record'
                if ($rtn === false) {
                    return false;
                }
                $tokens = [
                    [
                        'id' => 'IA.CREATED_WHY',
                        'placeHolders' => [
                            ['name' => 'WHY', 'value' => $why]
                        ]
                    ]
                ];
                $text_map = getLocalizedTextWithThrow($tokens);
                $text = GT($text_map,'IA.CREATED_WHY');
                InventoryWorkQueueManager::addNote($rtn, $text);
                $rtn['GROUP'] = "1"; // starting out, before any splits
                $newIwqs[] = $rtn;
            }
        }
        $ok = true;
        if ( ! empty($newIwqs)) {
            $ok = $this->workQueueManager->add($newIwqs);
            if ($ok) {
                // save the created record numbers
                foreach ($newIwqs as $oneIwq) {
                    $oneIwq['OLD_QUANTITYINRESERVE']    = $oneIwq['QUANTITYINRESERVE']    ?? 0; // so we can use it to compute the deltas
                    $oneIwq['OLD_QUANTITYINALLOCATION'] = $oneIwq['QUANTITYINALLOCATION'] ?? 0;
                    $oneIwq['DELTARESERVE']    = 0; // let's not increment again unless we need to
                    $oneIwq['DELTAALLOCATION'] = 0;
                    $deKey = $oneIwq['WORKKEY'];
                    $index = $deKeyToIndex[$deKey];
                    if (!isset($documentTree['ENTRIES'][$index]['IWQS'])) {
                        $documentTree['ENTRIES'][$index]['IWQS'] = [];  // first time?
                    }
                    $documentTree['ENTRIES'][$index]['IWQS'][$oneIwq['RECORDNO']] = $oneIwq;    // save them here
                }
            }
        }
        return $ok;
    }


    /**
     *      add an error with some standard fields added
     *
     * @param string    $text           English text (well, text in _() )
     * @param array     $rec            A record to get things like the docid from
     * @param int       $trackingRow    Optional tracking row the error occurred on (zero based)
     *
     * @return bool                 return false, for ease of calling (i.e. return addError() )
     */
    private function addError( $text, $rec, $trackingRow = -1 )
    {
        $docId      = $rec['DOCID'];
        $lineno     = $rec['LINENO'] ?? ''; // one-based
        $item       = $rec['ITEMID'] ?? '';
        $quantity   = $rec['QUANTITY'] ?? '';

        $text2      = sprintf('For document %1s, item %2s, quantity %3s, line number %4s ', $docId, $item, $quantity, $lineno);
        $errorCode = 'INV-0659';
        $placeholder = ['DOC_ID' => $docId, 'ITEM'=>$item, 'QUANTITY'=>$quantity, 'LINENO'=>$lineno];
        if ($trackingRow >= 0) {
            $errorCode = 'INV-0660';
            $trackingrowplusone = ($trackingRow + 1);
            $placeholder = array_merge($placeholder,['TRACKINGROWPLUSONE' => $trackingrowplusone]);
            $text2 .= sprintf("on tracking row %d", $trackingrowplusone);
        }
        $text2 .= '.';

        Globals::$g->gErr->addIAError(
            $errorCode, __FILE__ . ':' . __LINE__,
            $text,['MESSAGE_VALUE'=>$text],
            $text2,$placeholder,
            'Correct the issue.  Then, try again. ',[]
        );
        // i18N::TODO - (Code Change Review)
        return false;
    }


    /**
     *      Before you call the biz logic routines below, call this first with the array of
     * records you intend on using in the biz logic.  This is not required, but allows us to
     * cache data more quickly because we can do a bulk request for data.
     *
     * It is ok to call this more-than-once, so the individual routines can all this and we can
     * incrementally build the cache if we have to.
     *
     *
     * @param array[]   $records            The InventoryWQDetail records you will be passing to biz logic routines below
     *
     * @return array                        The running totals, same as from the item manager's fetchQuantityTotals()
     */
    public static function updateTotalsCache($records)
    {
        $itemIDs     = [];
        $whses       = [];
        $docHdrs     = [];
        $openDocHdrs = [];
        // collect records to look up
        foreach ($records as $row) {
            $item                               = $row['ITEMID'];
            $warehouse                          = $row['WAREHOUSEID'];
            $keyIndx                            = $item. "--" . $warehouse;
            if ( ! isset(self::$totalsData[$keyIndx])) {
                $itemIDs[$item]    = true;    // weeds out dups
                $whses[$warehouse] = true;
            }
            $docHdrs[$row['DOCHDRKEY']]         = true; // eliminate dups

            // if this record is in OPEN state, we may be MOVING to open,
            // so we'll want some more data.  If we're updating without moving,
            // then maybe getting the data isn't needed, but......
            if ($row['STATUS'] === 'O') {
                $openDocHdrs[$row['DOCHDRKEY']]  = true;
            }
        }

        //  ******************************************************
        //  Get tracking status of the items
        //  Get the current totals from the item/warehouses
        //  ******************************************************
        if (!empty($itemIDs)) {
            $itemIDs     = array_keys($itemIDs);        // make the keys BE the array
            $whses       = array_keys($whses);

            self::getTrackedStatusOfItems($itemIDs);    // does this item track sn/lot/exp?

            $itemManager = Globals::$g->gManagerFactory->getManager('item');
            $totalsData  = $itemManager->fetchQuantityTotals($itemIDs, $whses);
            foreach ($totalsData as $key => $td) {
                self::$totalsData[$key] = $td;
            }
        }

        //  ******************************************************
        //  Get the STATE of the relevant documents (to see if it is a draft)
        //  Get the DOCPAR for looking that up later
        //  ******************************************************
        $docParsNeeded = [];
        if ( ! empty($docHdrs)) {
            $querySpec = array(
                'selects' => array('RECORDNO', 'STATE', 'DOCPARKEY'),
                'usemst'  => true,
                'filters' => array(
                    array(
                        array('RECORDNO', 'IN', array_keys($docHdrs)),
                    )
                ),
            );
            $soDocMgr   = Globals::$g->gManagerFactory->getManager('sodocument');
            $resultSet  = $soDocMgr->GetList($querySpec);
            if ($resultSet !== false) {
                foreach ($resultSet as $row) {
                    $docParsNeeded[$row['DOCPARKEY']] = true;  // eliminate dups
                    self::$docStateByDocHdrKey[$row['RECORDNO']]  = $row['STATE']; // already translated
                    self::$docParKeyByDocHdrKey[$row['RECORDNO']] = $row['DOCPARKEY'];
                }
            }
        }

        //  ******************************************************
        //  Get the DOCPARs of the relevant documents
        //  if the ENABLEALLOCRESERVE flag is ON, get the DOCHDRs that affects
        //  ******************************************************
        $docHdrsOpenWithReserveAlloc = [];
        if ( ! empty($docParsNeeded)) {
            $querySpec = array(
                'usemst'  => true,
                'filters' => array(
                    array(
                        array('RECORDNO', 'IN', array_keys($docParsNeeded)),
                    )
                ),
            );
            $soDocParamsMgr = Globals::$g->gManagerFactory->getManager('sodocumentparams');
            $resultSet      = $soDocParamsMgr->GetList($querySpec);
            foreach ($resultSet as $row) {
                self::$docParByDocParKey[$row['RECORDNO']] = $row;

                // let's also track which doc headers have the enable-reserve flag on
                $enableReserveAllocFlag = ($row['ENABLEALLOCRESERVE'] ?? 'false');
                if (($enableReserveAllocFlag === 'true') || ($enableReserveAllocFlag === 'T')) {
                    foreach (self::$docParKeyByDocHdrKey as $docHdrKey => $docParKey) {
                        self::$docHdrsWithReserveAllocOn[$docHdrKey] = true;
                        if (($row['RECORDNO'] === $docParKey) && ($openDocHdrs[$docHdrKey] ?? false)) {
                            $docHdrsOpenWithReserveAlloc[] = $docHdrKey;
                            break;
                        }
                    }
                }
            }
        }

        //  ******************************************************
        //  Given 'OPEN' documents where the ENABLEALLOCRESERVE flag is ON,
        //  get their current saved open values, in case we're MOVING to OPEN
        //  (this won't happen often, we hope)
        //  ******************************************************
        if ( ! empty($docHdrsOpenWithReserveAlloc)) {
            $sql = [];
            $sql[] = "SELECT record#, nvl(quantityreservedwhenopen, 0) QUANTITYRESERVEDWHENOPEN, 
                                      nvl(quantityallocatedwhenopen, 0) QUANTITYALLOCATEDWHENOPEN, 
                                      itemkey
                        FROM docentrymst 
                        WHERE cny# = :1 ";
            // AND ((quantityreservedwhenopen is not null) OR (quantityallocatedwhenopen is not null))
            $sql[] = GetMyCompany();
            $sql   = PrepINClauseStmt($sql, $docHdrsOpenWithReserveAlloc, ' and dochdrkey ');
            $result = QueryResult($sql);
            if ($result !== false) {
                foreach ($result as $row) {
                    if ($row['QUANTITYRESERVEDWHENOPEN'] || $row['QUANTITYALLOCATEDWHENOPEN']) {
                        self::$quantitiesWhenOpen[$row['RECORD#']] = $row;
                    }
                }
            }
        }
        return self::$totalsData;
    }


    /**
     *  Do the items have tracking enabled?
     *
     *  The returned array has, by itemID, a set of keys: BIN, SN, LOT, EXP.
     *  Also, for ease, there is 'TRACKED' and that is true/false
     *  And CANRUNOUT ( "can run out" ), meaning 'should you check for allocation/reserve/qty available...'
     *  A MISSING entry means no tracking, OR you didn't ask for the tracking status of the item.
     *  i.e. if (isset(tracking[$itemID]) then there is tracking data.
     *  If there IS tracking, then there are separate values for each of BIN SN LOT and EXP:
     *  if (tracking[$itemID]['BIN'])
     *
     * @param string[] $itemIds         the items to get the tracked status of
     *
     * @return array                    the array of tracking, by item, or an empty array
     */
    public static function getTrackedStatusOfItems($itemIds)
    {
        $getThese = [];
        foreach ($itemIds as $itemId) {
            [ $itemId ] = explode('--', $itemId);
            if (!isset(self::$itemsAreTracked[$itemId])) {
                $getThese[] = $itemId;
                self::$itemsAreTracked[$itemId] = []; // in case we don't find it (and so we don't look again)
            }
        }

        // getThese is the list of items we do not yet track; might be empty!
        if ( ! empty($getThese)) {
            $qry   = [];
            $qry[] = "select itemid, itemtype, enablesno, enablelot, enablebin, enableexpiration, enablefulfillment from icitemmst where cny# = :1 ";
            $qry[] = GetMyCompany();
            $qry   = PrepINClauseStmt($qry, $getThese, " and itemid ");
            $resp  = QueryResult($qry);
            if ($resp !== false) {
                foreach ($resp as $row) {
                    $itemId             = $row['ITEMID'];
                    $itemType           = $row['ITEMTYPE'];
                    $checkQuantities    = (($itemType === 'I') || ($itemType === 'SK'));
                    $enableBIN          = (($row['ENABLEBIN'] ?? 'F') === 'T');
                    $enableSN           = (($row['ENABLESNO'] ?? 'F') === 'T');
                    $enableLOT          = (($row['ENABLELOT'] ?? 'F') === 'T');
                    $enableEXP          = (($row['ENABLEEXPIRATION'] ?? 'F') === 'T');
                    $track              = ($enableBIN || $enableSN || $enableLOT || $enableEXP);
                    $enableFulfillment  = (($row['ENABLEFULFILLMENT'] ?? 'F') === 'T');
                    // save for later
                    self::$itemsAreTracked[$itemId] =
                        ['TRACKED' => $track, 'CANRUNOUT' => $checkQuantities, 'ITEMTYPE' => $itemType, 'ENABLEFULFILLMENT' => $enableFulfillment,
                         'BIN' => $enableBIN, 'SN' => $enableSN, 'LOT' => $enableLOT, 'EXP' => $enableEXP];
                }
            }
        }
        return self::$itemsAreTracked;
    }


    /**
     *      Is the item un-tracked, and do we allow un-tracked items to go negative?
     *
     * @param string $itemId
     *
     * @return bool             TRUE means allow reserve to go negative, FALSE means no
     */
    public static function allowNegativeUncommitted($itemId)
    {
        $tracking = self::getTrackedStatusOfItems([$itemId]);               // likely already in the cache, but...

        // non-inventory item?  Sure!  Use as many as you want!!
        if ($tracking[$itemId]['CANRUNOUT'] === false) {
            return true;
        }

            // one time, fetch the preferences
        if (self::$allowNegativeUncommitted === null) {
            global $kINVid;
            GetModulePreferences($kINVid, $prefs);
            self::$allowNegativeUncommitted = ($prefs['NEGATIVEFULFILLMENT'] === 'T') && ($prefs['DISALLOW_NEGINV'] === 'F');
        }

        // now we do NOT allow negative if
        //  - the preferences were not set in the way above, OR
        //  - if the item is tracked
        $allow = false;
        if (self::$allowNegativeUncommitted) {
            $allow    = (($tracking[$itemId]['TRACKED'] ?? false) === false);    // if they are tracked we don't allow negative uncommitted
        }
        return $allow;
    }


    /**
     *  Categorize a document's TYPE from the doc tree.  Types are:
     *    const TD_TYPE_OTHER                 = '?';  NOT IN FULFILLMENT OR RESERVE / ALLOCATE
     *    const TD_TYPE_SALESORDER            = 'O';
     *    const TD_TYPE_SHIPPER               = 'S';
     *    const TD_TYPE_INVOICE               = 'I';
     *    const TD_TYPE_SHIP_AND_INVOICE      = 'X';
     *    const TD_TYPE_SHIP_DRAFT            = 'D';
     *    const TD_TYPE_HIDDEN_SALESORDER     = 'H';  NOT FULFILLMENT, BUT RESERVE / ALLOCATE
     *
     * @param array     $documentTree       Document tree from SODocument
     *
     * @return string                       Document type in our crude iternal format
     */
    public static function documentTypeFromDocTree($documentTree)
    {
        // is it fulfillment enabled AND just a sales order?
        $enableFulfillmentFlag = ($documentTree['_DOCPAR']['ENABLEFULFILLMENT'] ?? 'false');
        $fulfillmentEnabled    = (($enableFulfillmentFlag === 'T') || ($enableFulfillmentFlag === 'true')) ||
            ($documentTree['DOCPARID'] === SODocumentManager::FULFILLMENTORDERDOCTYPE) ||
            ($documentTree['DOCPARID'] === SODocumentManager::FULFILLMENTINVOICEDOCTYPE) ||
            ($documentTree['DOCPARID'] === SODocumentManager::FULFILLMENTSHIPPERDOCTYPE);

        $enableReserveAllocFlag = ($documentTree['_DOCPAR']['ENABLEALLOCRESERVE'] ?? 'false');
        $reserveAllocateEnabled = ($enableReserveAllocFlag === 'true') ||
                                  ($enableReserveAllocFlag === 'T');

        if ($fulfillmentEnabled === false) {
            if ($reserveAllocateEnabled) {
                return self::TD_TYPE_HIDDEN_SALESORDER;    // must be an SO because the TD's validate that.
            }
            return self::TD_TYPE_OTHER;
        }

        // is it a draft?
        $draft = $documentTree['STATE'] === DocumentManager::DRAFT_STATE;

        // does it affect on-hand?
        if (isset($documentTree['_DOCPAR']['DOCPAR_TOTALS'])) {
            foreach ($documentTree['_DOCPAR']['DOCPAR_TOTALS'] as $total) {
                if (($total['TOTALID'] ?? '') === 'ONHAND') {
                    switch ($total['Q_QV'] ?? 'NOPE') {
                        case 'Value':
                            return self::TD_TYPE_INVOICE;

                        case 'Quantity':
                            return $draft ? self::TD_TYPE_SHIP_DRAFT : self::TD_TYPE_SHIPPER;

                        case 'Quantity & Value':
                            return $draft ? self::TD_TYPE_SHIP_DRAFT : self::TD_TYPE_SHIP_AND_INVOICE;

                        default:
                            break;  // nothing to see here, and no special DRAFT state for orders
                    }
                }
            }
        } else {
            $updatesInv = $documentTree['_DOCPAR']['UPDATES_INV'] ?? '';
            switch ($updatesInv) {
                case 'Value':
                    return self::TD_TYPE_INVOICE;

                case 'Quantity':
                    return $draft ? self::TD_TYPE_SHIP_DRAFT : self::TD_TYPE_SHIPPER;

                case 'Quantity & Value':
                case 'Quantity and Value':
                    return $draft ? self::TD_TYPE_SHIP_DRAFT : self::TD_TYPE_SHIP_AND_INVOICE;
            }
        }
        return self::TD_TYPE_SALESORDER;
    }


    /**
     *  Given just a dochdr record#, return the internal type of the transaction, as above
     *
     * @param int   $docHdrKey      The doc header record#
     *
     * @return string               One of the TD_TYPE_ constants, above
     */
    public static function typeOfTD($docHdrKey)
    {
        $documentTree               = [];
        $docParKey                  = self::$docParKeyByDocHdrKey[$docHdrKey] ?? 0; // cache not set properly??
        $documentTree['STATE']      = self::$docStateByDocHdrKey[$docHdrKey]  ?? 0;
        $documentTree['_DOCPAR']    = self::$docParByDocParKey[$docParKey]    ?? [];
        $documentTree['DOCPARID']   = $documentTree['_DOCPAR']['DOCID']       ?? '';

        if ($docParKey === 0) {
            throw new Exception("[Code bug]Cache not set properly for document $docHdrKey");
        }
        return self::documentTypeFromDocTree($documentTree);
    }


    //  ***********************************************************************************
    //  ***********************************************************************************
    //
    //  INDIVIDUAL CHECKS
    //
    //  ***********************************************************************************
    //  ***********************************************************************************

    /**
     *      Is the API/UI trying to change a field they shouldn't?
     *  We don't really care about the read-only calculated fields that aren't
     *  persisted into the InventoryWorkQueue data.
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    private function checkForFieldsThatCantChange($currentRec, & $updatedRec)
    {
        $cantChangeThese = [
            'RECORDNO', 'ICWQORDERID', 'DOCHDRKEY', 'DOCENTRYKEY',
            'LINENO', 'WAREHOUSEKEY', 'WAREHOUSEID', 'SHIPVIAKEY',
            'TERMKEY', 'SHIPTOKEY', 'SHIPTOCONTACT', 'CUSTOMERKEY',
            'ITEMID', 'UOM', 'CONVFACTOR', 'WHENCREATED', 'CREATEDBY',
            // Note: CALLER CAN'T CHANGE THESE, but I can....
            // 'QUANTITYINRESERVE', 'QUANTITYINALLOCATION',
        ];

        foreach ($cantChangeThese as $field) {
            $current    = $currentRec[$field] ?? 0;
            $updated    = $updatedRec[$field] ?? 0;
            if ($current != $updated) {
                if ( ! isset($updatedRec[$field])) {    // don't penalize them for not specifying
                    $tokens = [
                        [
                            'id' => 'IA.FIELD_CANNOT_BE_CHANGED',
                            'placeHolders' => [
                                ['name' => 'FIELD', 'value' => $field]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    return $this->addError(GT($text, 'IA.FIELD_CANNOT_BE_CHANGED'), $currentRec);
                }
            }
        }

        // heck, as long as we're here lets check for other bad entry fields.
        $quantity = $updatedRec['QUANTITY'] ?? 0;
        $checkForNegative = [
            'QUANTITYPICKED', 'QUANTITYPACKED', '', 'QUANTITYINALLOCATION', 'QUANTITYINRESERVE'
        ];
        foreach ($checkForNegative as $field) {
            $updated    = $updatedRec[$field] ?? 0;
            if ($updated < 0) {
                $tokens = [
                    [
                        'id' => 'IA.FIELD_CANNOT_BE_NEGATIVE',
                        'placeHolders' => [
                            ['name' => 'FIELD', 'value' => $field]
                        ]
                    ]
                ];
                $text = getLocalizedTextWithThrow($tokens);
                return $this->addError(GT($text, 'IA.FIELD_CANNOT_BE_NEGATIVE'), $currentRec);
            }
            if ($updated > $quantity) {
                // correct past mistakes
                if ($currentRec[$field] === $updated) {
                    $updatedRec[$field] = $quantity;    // so they can get past the error
                } else {
                    $tokens = [
                        [
                            'id' => 'IA.FIELD_CANNOT_BE_MORE_THAN_QTY',
                            'placeHolders' => [
                                ['name' => 'FIELD', 'value' => $field]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    return $this->addError(GT($text, 'IA.FIELD_CANNOT_BE_MORE_THAN_QTY'), $currentRec);
                }
            }
        }

        // now for tracking rows
        if (isset($updatedRec['TRACKINGENTRIES']) && ! empty($updatedRec['TRACKINGENTRIES'])) {
            foreach ($updatedRec['TRACKINGENTRIES'] as $index => $row) {
                $quantity = $row['QUANTITY'] ?? 0;
                $updatedRec['TRACKINGENTRIES'][$index]['QUANTITYRESERVED'] = 0;    // will be fixed later; customer cannot change this
                $row['QUANTITYRESERVED'] = 0;
                $checkForNegativeTrack = [
                    'QUANTITY', 'QUANTITYPICKED', 'QUANTITYPACKED',
                ];
                foreach ($checkForNegativeTrack as $field) {
                    $updated = $row[$field] ?? 0;
                    if ($updated < 0) {
                        $tokens = [
                            [
                                'id' => 'IA.TRACKING_FIELD_CANNOT_BE_NEGATIVE',
                                'placeHolders' => [
                                    ['name' => 'FIELD', 'value' => $field]
                                ]
                            ]
                        ];
                        $text = getLocalizedTextWithThrow($tokens);
                        return $this->addError(GT($text, 'IA.TRACKING_FIELD_CANNOT_BE_NEGATIVE'), $currentRec, $index);
                    }
                    if ($updated > $quantity) {
                        $tokens = [
                            [
                                'id' => 'IA.TRACKING_FIELD_CANNOT_BE_MORE_THAN_QTY',
                                'placeHolders' => [
                                    ['name' => 'FIELD', 'value' => $field]
                                ]
                            ]
                        ];
                        $text = getLocalizedTextWithThrow($tokens);
                        return $this->addError( GT($text, 'IA.TRACKING_FIELD_CANNOT_BE_NEGATIVE'), $currentRec, $index);
                    }
                }
            }
        }
        return true;
    }


    /**
     *  Is the document in 'hold progress' state?
     * If so, they can save things, but they cannot change state/queue
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    private function checkForHold($currentRec, & $updatedRec)
    {
        $oldQueue           = $currentRec['STATUS'];
        $newQueue           = $updatedRec['STATUS'];
        $documentOnHold     = $updatedRec['HOLDPROGRESS'] ?? 'false';
        $documentWasOnHold  = $currentRec['HOLDPROGRESS'] ?? 'false';

        if ($oldQueue !== $newQueue) {
            if (($documentOnHold === 'true') || ($documentOnHold === 'T')) {
                $text = getLocalizedTextWithThrow([['id' => 'IA.ON_HOLD_TRANSACTIONS_STATUS_CANNOT_BE_MOVED']]);
                return $this->addError(GT($text, 'IA.ON_HOLD_TRANSACTIONS_STATUS_CANNOT_BE_MOVED'), $currentRec);
            }
        }

        if ($documentOnHold !== $documentWasOnHold) {
            $text_map = getLocalizedTextWithThrow([['id' => 'IA.PUT_ON_HOLD']]);
            $text = GT($text_map, 'IA.PUT_ON_HOLD');
            if ($documentOnHold === 'false') {
                $text_map = getLocalizedTextWithThrow([['id' => 'IA.TAKEN_OFF_HOLD']]);
                $text = GT($text_map, 'IA.TAKEN_OFF_HOLD');
            }


            InventoryWorkQueueManager::addNote($updatedRec, $text);
        }
        return true;
    }


    /**
     *      Given a bundle's status, what is the 'stage', like 'picking'?
     *
     * @param string   $status      current document state/status
     *
     * @return int                  current document 'stage'
     */
    private static function categoryOfStatus($status)
    {
        switch ($status) {
            case 'O':       return self::CATEGORY_NOT_IN_FULFILLMENT;
            case 'RPI':
            case 'PI':      return self::CATEGORY_PICKING;
            case 'RPA':
            case 'PA':      return self::CATEGORY_PACKING;
            case 'RS':
            case 'S':       return self::CATEGORY_SHIPPING;
            case 'RI':
            case 'I':       return self::CATEGORY_INVOICING;
            default:        return self::CATEGORY_UNKNOWN;
        }
    }

    /**
     *  If they are changing state (moving from queue to queue), is that ok?  For example, if you already converted
     *  to a Shipper, you can ONLY be in the Invoice queue
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    private function movementOkGivenState($currentRec, & $updatedRec)
    {
        $oldQueue       = $currentRec['STATUS'];
        $newQueue       = $updatedRec['STATUS'];

        if ($oldQueue !== $newQueue) {
            $tdType         = $currentRec['DOCUMENTTYPE'];
            $trouble        = false;
            $msg            = '';
            switch ($tdType) {
                case self::TD_TYPE_SHIPPER:
                    $trouble = ($newQueue !== 'S') && ($newQueue !== 'RI');
                    $msg = I18N::getSingleToken('IA.SHIPPER_INVOICE_CAN_ONLY_BE_MOVE_TO_READY_TO_INVOICE');
                    break;
            }
            if ($trouble) {
                return $this->addError($msg, $currentRec);
            }
            $text = I18N::getSingleToken('IA.MOVE_FROM_TO',[
                ['name' => 'FROM'   , 'value' => $this->workQueueManager->nameForStatus($oldQueue)],
                ['name' => 'TO'     , 'value' => $this->workQueueManager->nameForStatus($newQueue)]
            ]);
            InventoryWorkQueueManager::addNote($updatedRec, $text);
        }
        return true;
    }




    /**
     *  we may have made changes to the iwq records, so lets make sure we update the docentry
     *  records reserved and allocated numbers if so.
     *  actuall updates are done in bulk in bizLogicCleanup()
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    private function markDocEntriesNeedingUpdate($currentRec, $updatedRec)
    {
        $docHdr         = $currentRec['DOCHDRKEY'];

        // which doc entry records need to be updated?
        if (self::$docHdrsWithReserveAllocOn[$docHdr]) {
            $itemId = $currentRec['ITEMID'];

            // note there may be several records referring to one docentry; so we just want the
            // update to happen once per docentry.....
            $changed = (($currentRec['QUANTITYPICKED']    !== $updatedRec['QUANTITYPICKED']) ||
                        //  ($currentRec['QUANTITYPACKED']    !== $updatedRec['QUANTITYPACKED']) || // packed does not affect the docentry
                        ($currentRec['QUANTITYINRESERVE'] !== $updatedRec['QUANTITYINRESERVE']));
            if ($changed) {
                self::$docEntriesWithReserveAllocOn[$currentRec['DOCENTRYKEY']] = self::$itemsAreTracked[$itemId]['TRACKED'] ?? false;
            }
        }
        return true;
    }


    /**
     *  If we are moving from OPEN to <anything else>, or from <anything else> to OPEN, we may need
     *  to save or restore the reserve and allocate numbers in the docentry record.  The updates are
     *  actually done in bulk in bizLogicCleanup()
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    private function checkForReserveAllocationStorage($currentRec, & $updatedRec)
    {
        $oldQueue       = $currentRec['STATUS'];
        $newQueue       = $updatedRec['STATUS'];

        if (($oldQueue !== $newQueue) && (($oldQueue === 'O') || ($newQueue === 'O'))) {
            $saveRA = ($oldQueue === 'O');  // true means save reserve/allocated, false means restore
            if (isset($updatedRec['TRACKINGENTRIES'])) {
                $needIndexReset = false;
                foreach ($updatedRec['TRACKINGENTRIES'] as $trackIndex => $oneTrack) {
                    if ($saveRA) {
                        $updatedRec['TRACKINGENTRIES'][$trackIndex]['QUANTITYRESERVEDWHENOPEN']  = $oneTrack['QUANTITYRESERVED']  ?? 0;
                        $updatedRec['TRACKINGENTRIES'][$trackIndex]['QUANTITYALLOCATEDWHENOPEN'] = $oneTrack['QUANTITYALLOCATED'] ?? 0;
                    } else { // restore
                        // Note: if the whenOpen fields are both NULL, then this tracking entry was not
                        //       in existance when the bundle moved from OPEN (it was added later).
                        //       So, when we go back we want to DELETE it....
                        if ( ! isset($oneTrack['QUANTITYRESERVEDWHENOPEN'] ) && ! isset($oneTrack['QUANTITYALLOCATEDWHENOPEN'])) {
                            unset($updatedRec['TRACKINGENTRIES'][$trackIndex]);
                            $needIndexReset = true;
                        } else {
                            $updatedRec['TRACKINGENTRIES'][$trackIndex]['QUANTITYRESERVED']  = $oneTrack['QUANTITYRESERVEDWHENOPEN'] ?? 0;
                            $updatedRec['TRACKINGENTRIES'][$trackIndex]['QUANTITYALLOCATED'] = $oneTrack['QUANTITYALLOCATEDWHENOPEN'] ?? 0;
                        }
                    }
                }

                // Did we delete something from the middle?
                if ($needIndexReset) {
                    $updatedRec['TRACKINGENTRIES'] = array_values($updatedRec['TRACKINGENTRIES']);
                }
            }

            // now the main record, so we save it to the work queues...
            $docEntryKey            = $currentRec['DOCENTRYKEY'];
            if ( ! $saveRA) {

                $updatedRec['QUANTITYINALLOCATION'] = 0;
                $updatedRec['QUANTITYINRESERVE']    = 0;
                $updatedRec['QUANTITYPICKED']       = 0;
                $updatedRec['QUANTITYPACKED']       = 0;

                if (isset(self::$quantitiesWhenOpen[$docEntryKey])) {
                    $updatedRec['QUANTITYPICKED']       = self::$quantitiesWhenOpen[$docEntryKey]['QUANTITYALLOCATEDWHENOPEN'];
                    $updatedRec['QUANTITYINALLOCATION'] = $updatedRec['QUANTITYPICKED']; // max packed, which is zero
                    $updatedRec['QUANTITYINRESERVE']    = self::$quantitiesWhenOpen[$docEntryKey]['QUANTITYRESERVEDWHENOPEN'];
                }
            }

            // is this the LAST bundle in OPEN/NOT OPEN?
            if ($saveRA) {
                // if we are moving from OPEN to NOT OPEN, and this is the LAST bundle in OPEN state, we need to SAVE the docentry
                $bundles = self::bundlesInFulfillment($updatedRec['WORKKEY'], false, self::BUNDLES_IN_FULFILLMENT_OPEN_ONLY);
            } else {
                // if we are moving from NOT OPEN to OPEN, and there is only ONE NOT OPEN bundle, we need to RESTORE the docentry
                $bundles = self::bundlesInFulfillment($updatedRec['WORKKEY'], false, self::BUNDLES_IN_FULFILLMENT_OTHER_THAN_OPEN);
            }
            if ($bundles == 1) { // may be a string, don't use ===
                $this->docEntriesToSaveRestoreReserveAllocate[$docEntryKey] = $saveRA;
            }
        }
        return true;
    }


    /**
     *  Does this record need allocation?  Is there enough to allocate?
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    public function maybeAllocate($currentRec, & $updatedRec)
    {
        $ok                 = true;

        // Only sales orders and drafts can allocate.
        $isASalesOrder       = (($currentRec['DOCUMENTTYPE'] === self::TD_TYPE_SALESORDER)
                             || ($currentRec['DOCUMENTTYPE'] === self::TD_TYPE_SHIP_DRAFT)
                             || ($currentRec['DOCUMENTTYPE'] === self::TD_TYPE_HIDDEN_SALESORDER));
        if ( ! $isASalesOrder) {
            return $ok;
        }

        $oldQueue           = $currentRec['STATUS'];
        $newQueue           = $updatedRec['STATUS'];
        $movingToOpen       = ($oldQueue != $newQueue) && ($newQueue === 'O');

        $this->sumUpTracking($currentRec, $updatedRec, $movingToOpen);

        $ok = $ok && $this->resolveTrackingData( $updatedRec);

        return $ok;
    }


    /**
     *  If this item has tracking, sum up the tracking records into the parent.  Otherwise, we take the parent
     *  record 'at its word'.  If moving into the OPEN state, there are special rules around the tracking records.
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     * @param bool      $movingToOpen   Are we moving into open state
     *
     */
    private function sumUpTracking($currentRec, & $updatedRec, $movingToOpen = false)
    {
        $itemID                 = $updatedRec['ITEMID'];
        $tracking               = self::getTrackedStatusOfItems( [ $itemID ] );     // likely already IN the cache
        $tracked                = ($tracking[ $itemID ]['TRACKED']   ?? false);
        $canRunOut              = ($tracking[ $itemID ]['CANRUNOUT'] ?? true);
        $currentAllocated       = $currentRec['QUANTITYINALLOCATION'];
        $currentReserved        = $currentRec['QUANTITYINRESERVE'];
        $stateNow               = $updatedRec['STATUS'];

        if ($tracked === false) {
            unset($updatedRec['TRACKINGENTRIES']); // not tracked
            $quantityallocated                  = max($updatedRec['QUANTITYPICKED'], $updatedRec['QUANTITYPACKED']);
            $updatedRec['QUANTITYINALLOCATION'] = $quantityallocated;
            // we may ignore the ENTERED reserved here, but it still figures into the allocation formulas in V_INVTRACKINGALLOCATED
            $maxReserve = ibcsub($updatedRec['QUANTITY'], $quantityallocated, ItemManager::AVERAGE_COST_DECIMALS, true);
            if (($stateNow !== 'O') || ($updatedRec['QUANTITYINRESERVE'] > $maxReserve)) {
                $updatedRec['QUANTITYINRESERVE'] = $maxReserve; // just fix it for them
            }
        } else { // A TRACKED ITEM
            // ANY allocation/reserve must come from tracking entries.....
            $quantityreserved           = 0;    // this is the ENTERED reserved number!
            $quantitypicked             = 0;
            $quantitypacked             = 0;
            if (isset($updatedRec['TRACKINGENTRIES'])) {
                self::fixupTrackingEntries($currentRec, $updatedRec['TRACKINGENTRIES']);
                foreach ($updatedRec['TRACKINGENTRIES'] as $index => $row) {
                    // quantity and track_quantity are synonyms in the dbm but somehow they get out of sync!
                    if (($row['QUANTITY'] ?? 0) && ($row['TRACK_QUANTITY'] ?? 0) && ($row['QUANTITY'] != $row['TRACK_QUANTITY'])) {
                        $row['QUANTITY'] = $row['TRACK_QUANTITY'] ?? 0; // trust the track_quantity
                    }

                    // Never let a PM influence your designs..... :-(
                    if ( ! isset($row['QUANTITYALLOCATED']) || ($row['QUANTITYALLOCATED'] == 0)) {
                        $row['QUANTITYALLOCATED'] = $row['QUANTITYPICKED'] ?? 0;    // assume they filled in picked
                    } else if ( ! isset($row['QUANTITYPICKED'])) {
                        $row['QUANTITYPICKED'] = $row['QUANTITYALLOCATED'] ?? 0;
                    }

                    if ($movingToOpen) {
                        $row['QUANTITYRESERVED']  = ($row['QUANTITYRESERVEDWHENOPEN']  ?? 0);
                        $row['QUANTITYALLOCATED'] = ($row['QUANTITYALLOCATEDWHENOPEN'] ?? 0);
                        $row['QUANTITYPICKED']    = $row['QUANTITYALLOCATED'];  // depending on where this tracking came from
                        $row['QUANTITYPACKED']    = 0;

                        if (($row['QUANTITYRESERVED'] === 0) && ($row['QUANTITYALLOCATED'] === 0)) {
                            unset($updatedRec['TRACKINGENTRIES'][$index]);
                            continue;
                        }
                    }
                    $allocatedThisRow = max( $row['QUANTITYPICKED'] ?? 0, $row['QUANTITYPACKED'] ?? 0);
                    $maxReserve       = ibcsub($row['QUANTITY'], $allocatedThisRow, ItemManager::AVERAGE_COST_DECIMALS, true);
                    if (($stateNow !== 'O') || ($row['QUANTITYRESERVED'] > $maxReserve)) {
                        $row['QUANTITYRESERVED'] = $maxReserve;
                    }
                    $updatedRec['TRACKINGENTRIES'][$index] = $row;
                    $quantityreserved  += ($row['QUANTITYRESERVED'] ?? 0);
                    $quantitypicked    += ($row['QUANTITYPICKED'] ?? 0);
                    $quantitypacked    += ($row['QUANTITYPACKED'] ?? 0);
                }
            }
            $quantityallocated                  = max($quantitypicked, $quantitypacked);
            $maxReserve                         = ibcsub($updatedRec['QUANTITY'], $quantityallocated, ItemManager::AVERAGE_COST_DECIMALS, true);
            if (($stateNow !== 'O') || ($quantityreserved > $maxReserve)) {
                $quantityreserved = $maxReserve;
            } else {
                $quantityreserved = min($maxReserve,
                    max($quantityreserved, $updatedRec['QUANTITYINRESERVE'] ?? 0));
            }
            $updatedRec['QUANTITYINALLOCATION'] = $quantityallocated;
            // we have tried to preserve the ENTERED reserved here
            $updatedRec['QUANTITYINRESERVE']    = iround($quantityreserved, ItemManager::AVERAGE_COST_DECIMALS);
            $updatedRec['QUANTITYPICKED']       = iround($quantitypicked, ItemManager::AVERAGE_COST_DECIMALS);
            $updatedRec['QUANTITYPACKED']       = iround($quantitypacked, ItemManager::AVERAGE_COST_DECIMALS);
        }

        // no deltas for non-inventory items
        if ($canRunOut) {
            $updatedRec['DELTAALLOCATION'] = ibcsub($updatedRec['QUANTITYINALLOCATION'], $currentAllocated, ItemManager::AVERAGE_COST_DECIMALS, true);
            $updatedRec['DELTARESERVE']    = ibcsub($updatedRec['QUANTITYINRESERVE'],    $currentReserved, ItemManager::AVERAGE_COST_DECIMALS, true);
        }
    }


    /**
     *      The tracking entries were designed for docentry records, not for us.  So, here we clean up
     *  any fields the tracking entries need that may have been overlooked by the API or UI.
     *
     * @param array     $currentRec         One InventoryWQDetail record fresh off sql
     * @param array     $trackingEntries    Tracing entries being saved
     */
    public static function fixupTrackingEntries($currentRec, &$trackingEntries)
    {
        foreach ($trackingEntries as $index => $row) {
            $trackingEntries[$index]['DOCENTRYKEY']     = $currentRec['DOCENTRYKEY'];
            $trackingEntries[$index]['DOCENTRYNO']      = $currentRec['DOCENTRYKEY'];
            $trackingEntries[$index]['ITEMKEY']         = $currentRec['ITEMID'];
            $trackingEntries[$index]['ITEMID']          = $currentRec['ITEMID'];
            $trackingEntries[$index]['WORKQUEUEKEY']    = $currentRec['RECORDNO'] ?? 0; // may not yet be assigned?
            $trackingEntries[$index]['SALE_PUR_TRANS']  = 'Sale';

            // UI tends to deal in the string, not the record number:
            if ( ! isset($row['BINKEY']) || ($row['BINKEY'] == 0)) {
                if (isset($row['BINID']) && ($row['BINID'] != '')) {
                    $trackingEntries[$index]['BINKEY'] = BinManager::binKeyFromBinID($row['BINID']);
                }
            }
        }
    }


    /**
     *  Given some tracking data, is there enough available for it?
     *  This can be called with a docentry record or a InventoryWQDetail record, so be wary!
     *
     * Note that here we are NOT a non-inventory item, but a tracked item
     *
     * @param array     $updatedRec     One InventoryWQDetail or DocumentEntry record, untrusted, from UI/API
     *
     * @return bool
     */
    private function resolveTrackingData( & $updatedRec)
    {
        // match, allowing for missing fields and nulls
        $matches = function($availTable, $leftField, $tracking, $rightField) {
            if (isset($availTable[$leftField])) {
                $left = $availTable[$leftField];
                if ($left != '') {                         // left field specified and not ''
                    $right = $tracking[$rightField] ?? ''; // so a missing right field can't match
                    return ($left == $right);
                }
            }
            return true;
        };


        $updatedTracking    = $updatedRec['TRACKINGENTRIES'] ?? [];
        $itemID             = $updatedRec['ITEMID'];
        $tracking           = self::getTrackedStatusOfItems( [ $itemID ] ); // likely already IN the cache
        $tracked            = ($tracking[ $itemID ]['TRACKED']   ?? false);
        $canRunOut          = ($tracking[ $itemID ]['CANRUNOUT'] ?? true);              // do we NEED to track stuff?

        if (!$canRunOut) {
            return true;    // nothing to do
        }

        // 1) If there IS tracking data, roll it up and compare:
        if ($tracked) {
            if (!empty($updatedTracking)) {
                $warehouseId = $updatedRec['WAREHOUSEID'] ?? ($updatedRec['WAREHOUSE']['LOCATION_NO'] ?? '');
                $availQtys   = $this->getAvailableQuantities($itemID, $warehouseId, $tracking[$itemID], $updatedTracking);
                if (empty($availQtys)) {
                    $availQtys['track'] = [];   // simplify the code below
                }

                foreach ($updatedTracking as $index => $oneTracking) {
                    $qpi = ($oneTracking['QUANTITYPICKED'] ?? 0);       // sumUpTracking() normalized picked/allocated
                    $qpa = $oneTracking['QUANTITYPACKED'] ?? ($oneTracking['QUANTITYALLOCATED'] ?? 0);
                    $res = $oneTracking['QUANTITYRESERVED'] ?? 0;       // tracking records' RESERVED has teeth
                    $needQty = ibcadd($res, max($qpi, $qpa), ItemManager::AVERAGE_COST_DECIMALS, true);
                    if ($needQty) {
                        $enough = false;
                        foreach ($availQtys['track'] as $oneAvail) {

                            // sometimes the tracking has binkey, sometimes binid, sometimes neither
                            // the avail has both if it has one.  the tracking would have one or the other or neither
                            $same = $matches($oneAvail, 'binkey', $oneTracking, 'BINKEY') ||
                                    $matches($oneAvail, 'binid',  $oneTracking, 'BINID');

                            $same = $same
                                && $matches($oneAvail, 'serialno', $oneTracking, 'SERIALNO')
                                && $matches($oneAvail, 'lotno', $oneTracking, 'LOTNO')
                                && $matches($oneAvail, 'expiration', $oneTracking, 'EXPIRATION');

                            if ($same) {
                                $qtyAvail = $oneAvail['qtyleft'];
                                if ($qtyAvail >= $needQty) {
                                    $enough = true;
                                    $oneAvail['qtyleft'] -= $needQty;   // lower for the next pass
                                }
                                break;
                            }
                        }
                        if ( ! $enough) {
                            $tokens = [
                                [
                                    'id' => 'IA.NOT_ENOUGH_AVAILABLE_QUANTITY_FOR_LINE',
                                    'placeHolders' => [
                                        ['name' => 'LINE_NO', 'value' => ($updatedRec['LINE_NO'] + 1)],
                                        ['name' => 'TRACKING_LINE', 'value' => ($index + 1)]
                                    ]
                                ],
                                ['id' => 'IA.REDUCE_THE_QUANTITY_TO_RESERVE_PICK_OR_PACK']
                            ];
                            $text = getLocalizedTextWithThrow($tokens);
                            // i18N::TODO - (Code Change Review)
                            $desc1 = GT($text, 'IA.NOT_ENOUGH_AVAILABLE_QUANTITY_FOR_LINE');
                            $desc2 = GT($text, 'IA.REDUCE_THE_QUANTITY_TO_RESERVE_PICK_OR_PACK');
                            Globals::$g->gErr->addIAError(
                                'INV-0651', __FILE__ . ':' . __LINE__,
                                $desc1,['MESSAGE_VALUE'=>$desc1],
                                $desc2,['MESSAGE_VALUE'=>$desc2]
                            );
                            return false;
                        }
                    }
                }
            }
        }
        return true;
    }


    /**
     *  Ask the item manager for what is available, minus what we're looking at now.
     *
     * @param string    $itemID                 The item we're checking
     * @param string    $warehouseId            The warehouse we're checking
     * @param string[]  $tracking               The tracking info (like 'enablebin')
     * @param array     $trackingDetails        The entered array of details to be checked
     *
     * @return array
     */
    private function getAvailableQuantities($itemID, $warehouseId, $tracking, $trackingDetails)
    {
        $trackingForFetch = $tracking;
        $trackingForFetch['ENABLEBIN']          = $tracking['BIN'] ? 'T' : 'F';
        $trackingForFetch['ENABLESNO']          = $tracking['SN'] ? 'T' : 'F';
        $trackingForFetch['ENABLELOT']          = $tracking['LOT'] ? 'T' : 'F';
        $trackingForFetch['ENABLEEXPIRATION']   = $tracking['EXP'] ? 'T' : 'F';

        $itemManager = Globals::$g->gManagerFactory->getManager('item');
        return $itemManager->fetchSnLotExpirationInternal(
                $itemID, $warehouseId, '', $trackingForFetch, false, $trackingDetails );
    }


    /**
     *  Does this record need reserve?  Is there enough to reserve?
     *  sumUpTracking() has been called to do the mechanical work of summing the totals already.
     *  it also adjusted the reserved quantities based on whether we are MOVING to open or not.
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     *
     * @return bool
     */
    public function maybeReserve($currentRec, & $updatedRec)
    {
        // Only sales orders (and draft shippers) can reserve.
        $isASalesOrder       = (($currentRec['DOCUMENTTYPE'] === self::TD_TYPE_SALESORDER)
                            || ($currentRec['DOCUMENTTYPE'] === self::TD_TYPE_SHIP_DRAFT)
                            || ($currentRec['DOCUMENTTYPE'] === self::TD_TYPE_HIDDEN_SALESORDER));
        if ( ! $isASalesOrder) {
            return true;
        }

        $itemID             = $updatedRec['ITEMID'];
        $warehouseID        = $updatedRec['WAREHOUSEID'];
        $tracking           = self::getTrackedStatusOfItems( [ $itemID ] );             // likely already IN the cache
        $canRunOut          = ($tracking[ $itemID ]['CANRUNOUT'] ?? true);              // do we NEED to track stuff?

        if ( ! $canRunOut) {
            $updatedRec['DELTARESERVE']    = 0;
            $updatedRec['DELTAALLOCATION'] = 0;
            return true;    // non-inventory items....
        }

        $effectiveDelta     = ($updatedRec['DELTARESERVE'] ?? 0) + ($updatedRec['DELTAALLOCATION'] ?? 0);   // did THIS go up?

        // if the amount we want went down, that is always ok (allocations verified it)
        //  But if it went UP, then we need to see if enough is available.....
        if ($effectiveDelta > 0) {
            if ( ! self::allowNegativeUncommitted($updatedRec['ITEMID'])) {
                // if, in the list of things we're looking at this session, we have a duplicate item/warehouse,
                // we track the difference in the quantity REALLY uncommitted....
                $previouslyCommittedThisSession = self::$runningItemWarehouseTotals[$itemID][$warehouseID] ?? 0;
                $uncommitted = $currentRec['QUANTITYUNCOMMITTED'] - $previouslyCommittedThisSession;
                if ($effectiveDelta > $uncommitted) {
                    $tokens = [
                        [
                            'id' => 'IA.CANNOT_BE_SAVED_NOT_ENOUGH_UNCOMMITTED_QTY',
                            'placeHolders' => [
                                ['name' => 'QTY', 'value' => $uncommitted],
                                ['name' => 'REQUIRED_QTY', 'value' => $effectiveDelta]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    return $this->addError(GT($text,'IA.CANNOT_BE_SAVED_NOT_ENOUGH_UNCOMMITTED_QTY'), $currentRec);
                }
            }
        }
        self::$runningItemWarehouseTotals[$itemID][$warehouseID] += $effectiveDelta;   // positive or negative

        return true;
    }



    /**
     *  Does this record need to split?
     *
     * @param array     $currentRec     One InventoryWQDetail record fresh off sql
     * @param array     $updatedRec     One InventoryWQDetail record, untrusted, from UI/API
     * @param array     $splitValue         If we need to split, then this is set to the NEW record/values
     *
     * @return bool
     */
    private function maybeSplit($currentRec, & $updatedRec, & $splitValue)
    {
        $ok             = true;
        $splitValue     = [];
        $oldQueue       = self::categoryOfStatus($currentRec['STATUS']);
        $newQueue       = self::categoryOfStatus($updatedRec['STATUS']);

        if (($oldQueue > self::CATEGORY_NOT_IN_FULFILLMENT) &&
            ($newQueue > $oldQueue)) {

            $quantityPicked = $updatedRec['QUANTITYPICKED'] ?? 0;
            $quantityPacked = $updatedRec['QUANTITYPACKED'] ?? 0;
            $quantity       = $updatedRec['QUANTITY'] ?? 0;

            // some cases to think about:
            // QTY   PICKED   PACKED  FROM   TO   QTY LEFT  QTY MOVED  ALLOCATE LEFT   ALLOCATE MOVED
            // ===   ======   ======  ====  ====  ========  =========  =============   ==============
            //  10     8        0     pick  pack+     2        8            0                8          (happy path)
            //  10     8        2     pick  pack      2        8            0                8
            //  10     6        8     pick  pack    <no split> (you packed > picked)
            //  10     0        0     pick  pack    <no split> (no picked)
            //  10     10       8     pick  pack    <no split> (picked all)
            //  10     8        10    pick  pack    <no split> (packed > picked)
            //
            //  10     8        0     pack  ship+   <no split> (no packed)
            //  10     8        10    pack  ship+   <no split> (all packed)
            //  10     10       8     pack  ship+     2        8            2                8          (happy path)
            //  10     0        8     pack  ship+     2        8            0                8
            //
            // Notes:
            //   if pick --> pack+, then
            //     - if packed > picked, no split
            //     - if picked = quantity, no split
            //     - if picked = 0, no split
            //     - else split into (quantity - picked) stays put, and (picked) moves.
            //          - packed moves, leaving behind 0 packed
            //          - allocated = 0 for stays put part, picked for moved part
            //          - reserved  = resulting quantity - resulting allocated
            //          - delta reserved and allocated is as relates to $currentRec
            //   if pack --> ship+, then
            //     - if packed = 0, no split (and ignore picked)
            //     - if packed = quantity, no split (and ignore picked)
            //     - else split into (quantity - packed) stays put, and (packed) moves.
            //          - picked left behind is max( 0, picked - packed )
            //          - picked moved is picked - picked-left-behind
            //          - allocated left behind is picked-left-behind
            //          - allocated moved is packed
            //          - reserved  = resulting quantity - resulting allocated
            //          - delta reserved and allocated is as relates to $currentRec

            // is this pick --> pack+ or pack --> ship+
            $pickToPack = ($oldQueue === self::CATEGORY_PICKING);  // and we know that the new queue is >
            $packToShip = ($oldQueue === self::CATEGORY_PACKING);  // and we know that the new queue is >

            // or is this something else, like ship --> invoice?
            if (($pickToPack === false) && ($packToShip === false)) {
                return $ok;
            }

            // refer to the above notes....
            // DO we need to split?
            if ($pickToPack) {
                // if they already packed the same or more than picked, no point splitting
                // if they picked nothing or the full quantity, no point splitting
                // (so they picked some, not all, and less than the packed amount)
                if (($quantityPacked >= $quantityPicked) ||
                    ($quantityPicked == 0) ||
                    ($quantityPicked == $quantity)) {
                    return $ok;
                }
            } else if (($quantityPacked == 0) ||
                       ($quantityPacked == $quantity)) {
                // this is pack-->ship, so we skip it if they pack nothing or everything.
                // (so they packed some, but not all)
                return $ok;
            }

            // so now we need to split...  Again, refer to the above notes
            $qtyToMove = ($pickToPack) ? $quantityPicked : $quantityPacked;
            $newQty    = ($quantity - $qtyToMove);
            $tracking  = $updatedRec['TRACKINGENTRIES'] ?? [];
            $updatedRec['TRACKINGENTRIES'] = [];

            // $splitValue is the new split record, the one STAYING PUT, not moving on.
            $splitValue = $updatedRec;
            $splitValue['STATUS'] = $currentRec['STATUS'];    // make the split stay in the old place
            unset($splitValue['IWQKEY'], $splitValue['RECORDNO'], $splitValue['RECORD#']); // and it needs to be added
            $splitValue['QUANTITY'] = $newQty;                // the 'new' (non-moving) quantity
            $splitValue['QUANTITYPICKED'] = ($pickToPack) ? 0 : max(0, $quantityPicked - $qtyToMove);
            $splitValue['QUANTITYPACKED'] = 0; // ($pickToPack) ? 0 : 0;
            $splitValue['QUANTITYINALLOCATION'] = ($pickToPack) ? 0 : $splitValue['QUANTITYPICKED'];
            $splitValue['QUANTITYINRESERVE'] = $newQty - $splitValue['QUANTITYINALLOCATION'];
            $splitValue['DELTARESERVE'] = 0; // between the two records, the total reserve is the same
            $splitValue['DELTAALLOCATION'] = 0; // ditto for the allocations
            $splitValue['GROUP'] = InventoryWorkQueueManager::GROUP_FROM . $currentRec['RECORDNO'];

            // Now the record moving forward
            $updatedRec['QUANTITY'] = $qtyToMove;               // the moving record has less quantity
            $updatedRec['QUANTITYPICKED'] = ($pickToPack) ? $quantityPicked : ($quantityPicked - $splitValue['QUANTITYPICKED']);
            $updatedRec['QUANTITYPACKED'] = $quantityPacked;  // ($pickToPack) ? $quantityPacked : $quantityPacked;
            $updatedRec['QUANTITYINALLOCATION'] = $qtyToMove;       // ($pickToPack) ? $qtyToMove : $qtyToMove;
            $updatedRec['QUANTITYINRESERVE'] = $qtyToMove - $updatedRec['QUANTITYINALLOCATION'];
            $updatedRec['GROUP'] = InventoryWorkQueueManager::INCREMENT_GROUP; // don't know the group is now, but increment it

            // note: if there was a delta, keep it and just assign it to the new, moved, record,
            //       even if technically it might belong to the split value.  This will move the needle
            //       on the totals fields which is all we care about.
            //$updatedRec['DELTARESERVE'] = 0; // between the two records, the total reserve is the same
            //$updatedRec['DELTAALLOCATION'] = 0; // ditto for the allocations

            // Tracking records are now in $tracking, and their work queue keys are all assigned to the record MOVING ON,
            //  which likely does not apply to all of them.
            // Also, note that some records may need to be split themselves, like if you have picked AND packed.
            // ALLOCATED === PICKED
            // so, the pivot is SOME, but not ALL the quantity
            $pivot     = $pickToPack ? 'QUANTITYALLOCATED' : 'QUANTITYPACKED';
            $antiPivot = ($pivot === 'QUANTITYPACKED') ? 'QUANTITYALLOCATED' : 'QUANTITYPACKED';
            foreach ($tracking as $oneTrack) {

                // if pick-->pack, we don't want packed > picked and vice versa
                // example: pick 2, then pack 1, then move to shipper
                //      we will ship 1, so we don't want pick to still be 2
                //      and we don't want the quantity to be > the amount moving
                $setTo      = ($oneTrack[$pivot]     ?? 0);
                $other      = ($oneTrack[$antiPivot] ?? 0);
                $otherTrack = null;
                if (($other > $setTo) && ($setTo > 0)) {
                    // split the record into two parts
                    $otherTrack                   = $oneTrack;
                    $remainder                    = ibcsub($other, $setTo, ItemManager::AVERAGE_COST_DECIMALS, true);
                    $otherTrack[$antiPivot]       = $remainder;
                    $otherTrack[$pivot]           = 0;
                    $otherTrack['QUANTITY']       = $remainder;
                    $otherTrack['TRACK_QUANTITY'] = $remainder;
                    unset($otherTrack['RECORDNO'], $otherTrack['RECORD#']);
                    $otherTrack['QUANTITYPICKED'] = $otherTrack['QUANTITYALLOCATED'];

                    $oneTrack[$antiPivot]        = $setTo;
                    $oneTrack['QUANTITY']        = $setTo;
                    $oneTrack['TRACK_QUANTITY']  = $setTo;
                    $oneTrack['QUANTITYPICKED']  = $oneTrack['QUANTITYALLOCATED'];
                }

                if (($oneTrack[$pivot] ?? 0) > 0) {
                    $updatedRec['TRACKINGENTRIES'][] = $oneTrack;
                    if ($otherTrack !== null) {
                        unset($otherTrack['WORKQUEUEKEY']); // needs to be assigned when slit value's key is assigned
                        $splitValue['TRACKINGENTRIES'][] = $otherTrack;
                    }
                } else {
                    unset($oneTrack['WORKQUEUEKEY']);       // needs to be assigned when slit value's key is assigned
                    $splitValue['TRACKINGENTRIES'][] = $oneTrack;
                    if ($otherTrack !== null) {
                        $updatedRec['TRACKINGENTRIES'][] = $otherTrack;
                    }
                }
            }

            // tell each record what happened to the OTHER record
            $tokens = [
                [
                    'id' => 'IA.SPLIT_QUANTITY_MOVED_TO',
                    'placeHolders' => [
                        ['name' => 'QTY', 'value' => $qtyToMove],
                        ['name' => 'STATUS', 'value' => $this->workQueueManager->nameForStatus($updatedRec['STATUS'])]
                    ]
                ],
                [
                    'id' => 'IA.SPLIT_QUANTITY_LEFT_IN',
                    'placeHolders' => [
                        ['name' => 'QTY', 'value' => $newQty],
                        ['name' => 'STATUS', 'value' => $this->workQueueManager->nameForStatus($splitValue['STATUS'])]
                    ]
                ]
            ];
            $text_map = getLocalizedTextWithThrow($tokens);
            $text = GT($text_map,'IA.SPLIT_QUANTITY_MOVED_TO');
            InventoryWorkQueueManager::addNote($splitValue, $text);
            $text = GT($text_map,'IA.SPLIT_QUANTITY_LEFT_IN');
            InventoryWorkQueueManager::addNote($updatedRec, $text);
        }
        return $ok;
    }


    /**
     *      Are there multiple Bundles (well, PLACES) for a document?
     *
     * @param  int   $sourceDocHdrOrWorkKey         The document header, or the workkey, to search
     * @param  bool  $isDocHdr                      For the whole document (otherwise the workkey)
     * @param  int   $whichBundles                  One of these:
     *                                                  BUNDLES_IN_FULFILLMENT_ALL (default)
     *                                                  BUNDLES_IN_FULFILLMENT_OPEN_ONLY
     *                                                  BUNDLES_IN_FULFILLMENT_OTHER_THAN_OPEN
     *
     * @return int                                  How many bundles are in Fulfillment?
     */
    public static function bundlesInFulfillment($sourceDocHdrOrWorkKey, $isDocHdr = true, $whichBundles = self::BUNDLES_IN_FULFILLMENT_ALL)
    {
        // for now, lets assume that different WAREHOUSEs can be in the same PLACEs
        $field    = ($isDocHdr) ? 'dochdrkey' : 'workkey';
        $distinct = ($whichBundles == self::BUNDLES_IN_FULFILLMENT_ALL) ? 'distinct' : '';
        $sql      = [];
        $sql[] = "SELECT  count($distinct place) qty
                 FROM  icworkqueue 
                WHERE  cny# = :1
                  AND  $field = :2
                  AND  completed != 'T'
                ";
         if ($whichBundles == self::BUNDLES_IN_FULFILLMENT_OTHER_THAN_OPEN) {
             $sql[0] .= "AND place != '" . InventoryWorkQueueManager::QUEUE_OPEN . "' ";
         } else if ($whichBundles == self::BUNDLES_IN_FULFILLMENT_OPEN_ONLY) {
             $sql[0] .= "AND place = '" . InventoryWorkQueueManager::QUEUE_OPEN . "' ";
         }
        $sql[] = GetMyCompany();
        $sql[] = $sourceDocHdrOrWorkKey;
        $rtn   = QueryResult($sql);
        $bundles = ($rtn === false) ? -1 : ($rtn[0]['QTY'] ?? 0);    // can be zero
        return $bundles;
    }


    /**
     *      Across all bundles, get the allocation and update the docentry.
     *
     * @param  int[]   $docEntryRecordNumbers      The document records to update
      *
     * @return bool                                Did it work?
     */
    private function updateDocEntryWithAlloc($docEntryRecordNumbers)
    {
        if (empty($docEntryRecordNumbers)) {
            return true;
        }
        $sql   = [];
        $sql[] = "UPDATE docentrymst 
                    SET QUANTITYALLOCATED = 
                        ( SELECT sum(nvl(QUANTITYPICKED, 0)) as allocated 
                           FROM v_invwqdetail WHERE  cny# = :1 and docentrykey = docentrymst.record# ),
                    QUANTITYRESERVED = 
                        ( SELECT sum(nvl(QUANTITYINRESERVE, 0)) as reserved 
                           FROM v_invwqdetail WHERE  cny# = :1 and docentrykey = docentrymst.record# )
                    WHERE cny# = :1 ";
        $sql[] = GetMyCompany();
        $sql   = PrepINClauseStmt( $sql, $docEntryRecordNumbers, ' and record# ');
        return ExecStmt($sql);
    }



    // *****************************************************************************************
    // *****************************************************************************************
    //
    //  BULK CONVERSION
    //
    // *****************************************************************************************
    // *****************************************************************************************


    /**
     *      Bulk Convert main routine.  Given a list of order id's to convert, convert them.
     *
     *  Notes:
     *      - at this time, we sort in order by document
     *          - for converting to a shipper, we group by document + target ship to,
     *              so the target is just for one document and one ship-to
     *
     *      - Note that we start and end a transaction at the boundary of ONE target document.
     *          That way we can succeed or fail per-document and not totally unwrap everything if
     *          one document fails.
     *
     *
     * @param string[][]    $rows          The ICWQORDERIDs to convert
     * @param array         $whatHappened  What action was taken, PER the above order ids.
     *                                      $whatHappened['ICWQORDERID'] is the same as was passed for $rows, above
     *                                      ['OK']                     is true or false, did the convert happen
     *                                      ['TEXT']                   other details as we decide what they are
     *
     * @return bool                         did it fail for meta reasons (i.e. not one specific convert)
     */
    public function bulkConvert($rows, & $whatHappened)
    {
        if ( ! InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) { // just being sure.....
            return true;    // thanks, but no thanks.
        }
        $whatHappened       = [];

        // First, did they pass in some reasonable IDs?
        $iwqorder       = Globals::$g->gManagerFactory->getManager('inventorywqorder');
        $rows           = $iwqorder->clientRowsToInternalRows($rows, 'CONVERT');
        if (empty($rows)) {
            return false;
        }

        // Sort into order.  At this time we don't care about warehouses or states
        usort($rows, function($a, $b) {
            $adh = $a['DOCHDRKEY'];
            $bdh = $b['DOCHDRKEY'];
            if ($adh < $bdh) {
                return -1;
            }
            if ($adh > $bdh) {
                return +1;
            }
            $ast = $a['SHIPTOKEY'] ?? 0;
            $bst = $b['SHIPTOKEY'] ?? 0;
            if ($ast < $bst) {
                return -1;
            }
            if ($ast > $bst) {
                return +1;
            }
            return 0;   // same
        });

        // We want to combine those records with the same document and maybe ship-to
        // then we want a collection of documents AND the things-to-do-with-each-line,
        // and we'll call the bulk converter over in ConversionManager......
        $wqIdToDocId        = [];
        $docEntrysForDocId  = [];
        $UOMValues          = [];
        foreach ($rows as $row) {
            $shipTo                     = $row['SHIPTOKEY'] ?? 0;
            $rowID                      = $row['ICWQORDERID'];
            if ( ! isset($whatHappened[$rowID])) {
                $whatHappened[$rowID] = [];
            }
            $whatHappened[$rowID]['OK'] = 'true';
            $order                      = $iwqorder->get($rowID);   // one header/warehouse/shipto
            if (($order === false) || empty($order)) {
                $text = getLocalizedTextWithThrow([['id' => 'IA.THE_DOCUMENT_WAS_MOVED_BY_ANOTHER_USER']]);
                $whatHappened[$rowID]['OK']   = 'false';
                $whatHappened[$rowID]['TEXT'] = GT($text,'IA.THE_DOCUMENT_WAS_MOVED_BY_ANOTHER_USER');
                $whatHappened[$rowID]['CONVERTED']  = 'false';
                continue;
            }

            //If we have a location, it means the row (document) was created a entity level and so we cannot bulk convert it
            if ($order['MELOCATIONKEY'] ?? false) {
                $text = getLocalizedTextWithThrow([['id' => 'IA.THE_DOCUMENT_WAS_CREATED_AT_ENTITY_LEVEL']]);
                $whatHappened[$rowID]['OK']   = 'false';
                $whatHappened[$rowID]['TEXT'] = GT($text,'IA.THE_DOCUMENT_WAS_CREATED_AT_ENTITY_LEVEL');
                $whatHappened[$rowID]['CONVERTED']  = 'false';
                continue;
            }

            // save the docid for this row
            $docID               = $order['DOCID'];
            $docIdKey            = $docID . '--' . $shipTo;
            $wqIdToDocId[$rowID] = $docID;

            $this->getUOMValues($order,$UOMValues);

            // is this doc part ok?
            $issues              = $this->validateWQDetailsForConvert($order['ENTRIES']);
            if ($issues != '') {
                $whatHappened[$rowID]['OK']   = 'false';
                $whatHappened[$rowID]['TEXT'] = $issues;
                $whatHappened[$rowID]['CONVERTED']  = 'false';
            } else {
                if ( ! isset($docEntrysForDocId[$docIdKey])) {
                    $docEntrysForDocId[$docIdKey] = [];
                }
                $docEntrysForDocId[$docIdKey] = $this->lineMergeForConvert($docEntrysForDocId[$docIdKey], $order);
            }
        }

        // PHEW!  Now, with all that behind us, we have the list of documents to convert...
        $documentsToConvert = [];
        $bulkConvertContext = [ 'DE' => $docEntrysForDocId, 'IQW' => [], 'UOM' => $UOMValues ];
        foreach ($rows as $row) {
            $rowID = $row['ICWQORDERID'];

            // ok false means we didn't even get to conversion and already filled in the values
            if ($whatHappened[$rowID]['OK'] === 'true') {
                $docId      = $wqIdToDocId[$rowID];
                $shipTo     = $row['SHIPTOKEY'] ?? 0;
                $docIdKey   = $docId . '--' . $shipTo;
                $documentsToConvert[$docIdKey] = $docId; // weeds out dups by doc hdr and ship to
                $bulkConvertContext['IQW'][$docIdKey][] = $rowID;
            }
        }

        $converted                 = [];
        $whatHappenedInBulk        = [];
        $localBulkConvertCallback  = function($sourceDocKey, $sourceDocID, $sourceDocType, $targetDocType, &$docTree, &$context) {
            return $this->bulkConvertCallback($sourceDocKey, $sourceDocID, $sourceDocType, $targetDocType, $docTree, $context);
        };
        $conversionManager = new ConversionManager(['mod' => 'so']);
        $ok = $conversionManager->bulkConvert( $documentsToConvert,
                            $converted, $whatHappenedInBulk, true,
                                $localBulkConvertCallback, $bulkConvertContext);

        foreach ($rows as $row) {
            $rowID = $row['ICWQORDERID'];
            if ($whatHappened[$rowID]['OK'] === 'true') {
                $docId      = $wqIdToDocId[$rowID];
                $shipTo     = $row['SHIPTOKEY'] ?? 0;
                $docIdKey   = $docId . '--' . $shipTo;
                $whatHappened[$rowID]['CONVERTED']  = $converted[$docIdKey];
                $whatHappened[$rowID]['TEXT']       = $whatHappenedInBulk[$docIdKey];
            }
        }
        return $ok;
    }


    /**
     *      This is the callback, called by the ConversionManager's bulkConvert, and passed in by the above
     *  bulkConvert() routine.
     *
     *  Here, we edit the docentry rows to maybe change quantities and maybe remove entries in other bundles.
     *
     * @param string        $sourceDocKey           source doc id's key; like 0, 1, 2, or, in my case, like 'Sales Order 1234--123'
     *                                              where the --nnn is the ship-to-key, so one source doc creates two or more target docs
     * @param string        $sourceDocID            source doc id, like 'Sales Order 1234'
     * @param string        $sourceDocType          source doc type, like 'Sales Order'
     * @param string        $targetDocType          target doc type, like 'Shipper'
     * @param array         $docTree                results of get() on the document header
     * @param array         $bulkConvertContext     the context for this routine, passed by the above bulkConvert()
     *
     * @return string                       the error text, or empty or null if no errors
     *
     */
    private function bulkConvertCallback($sourceDocKey, /** @noinspection PhpUnusedParameterInspection */ $sourceDocID,
                                         /** @noinspection PhpUnusedParameterInspection */ $sourceDocType,
                                         /** @noinspection PhpUnusedParameterInspection */ $targetDocType,
                                         &$docTree, &$bulkConvertContext)
    {
        // just pick the lines that we want to convert and only for the quantity to convert.
        $lineItemsForTarget = $bulkConvertContext['DE'][$sourceDocKey];
        $UOMValues          = $bulkConvertContext['UOM'];

        if (( ! empty($lineItemsForTarget)) && ( ! empty($docTree['ENTRIES']))) {

            $docTree['ICWQORDERID'] = $bulkConvertContext['IQW'][$sourceDocKey]; // could be many

            foreach ($docTree['ENTRIES'] as $index => $row) {
                // is it in our array?  Then that's easy...
                $docEntryKey = $row['SOURCE_DOCLINEKEY'] ?? 0;  // the SOURCE/FROM doc record#
                if (isset($lineItemsForTarget[$docEntryKey])) {

                    [ $itemID ] = explode( '--', $row['ITEMID']);
                    $unit       = $row['UNIT'];
                    $quantity   = $lineItemsForTarget[$docEntryKey]['QUANTITY'];
                    $convfactor = $UOMValues[$itemID][$unit]['CONVFACTOR'] ?? 1;

                    $docTree['ENTRIES'][$index]['QUANTITY'] = iround($quantity, ItemManager::AVERAGE_COST_DECIMALS);
                    $docTree['ENTRIES'][$index]['UIQTY']    = ibcdiv($quantity,  $convfactor, ItemManager::DEFAULT_UOM_PRECISION, true);

                    $tracking = $lineItemsForTarget[$docEntryKey]['TRACKINGENTRIES'] ?? [];
                    $docTree['ENTRIES'][$index]['TRACKINGENTRIES'] = [];
                    foreach ($tracking as $trackRow) {
                        $docTree['ENTRIES'][$index]['TRACKINGENTRIES'][] = $trackRow;
                    }
                } else {
                    // is the item a type we don't use in fulfillment?
                    // if so, include it always, but otherwise remove it
                    if ($row['INVFF_NEEDS_WORKQUEUE']) {
                        unset($docTree['ENTRIES'][$index]);
                    }
                }
            }
        }

        // wait, did we remove EVERYTHING??
        if (empty($docTree['ENTRIES'])) {
            $text = getLocalizedTextWithThrow([['id' => 'IA.THERE_ARE_NO_LINE_ITEMS_TO_BE_CONVERTED']]);
            return GT($text,'IA.THERE_ARE_NO_LINE_ITEMS_TO_BE_CONVERTED');
        }
        return null;    // no error text
    }


    /**
     *      When you read a document tree, you do not get the UOM data.  So if the UOM is DOZEN, then
     *  the quantity of N would yield a UIQTY of (N / 12).  Here, we fetch the UOM data in a way similar
     *  to the way that the SODocumentFormEditor does, but we are getting the item UOM for a collection
     *  of documents, not just one.
     *
     * @param array         $order                  An ItemWQOrder record
     * @param array         $existingUOMValues      Zero or more unit-of-measure values for the collection of orders
     */
    private function getUOMValues($order, & $existingUOMValues)
    {
        $itemsToGet = [];
        foreach ($order['ENTRIES'] as $row) {
            $itemID = $row['ITEMID'];
            if ( ! isset($existingUOMValues[$itemID])) {
                $itemsToGet[$itemID] = true;    // eliminate dups
            }
        }

        if ( ! empty($itemsToGet)) {
            $itemMgr     = Globals::$g->gManagerFactory->getManager('item');
            $uomInfoVals = $itemMgr->GetUOMInfoCache(array_keys($itemsToGet), true, false);
            if ($uomInfoVals !== false) {
                foreach ($uomInfoVals as $key => $unit) {
                    $existingUOMValues[$key] = $unit;
                }
            }
        }
    }



/**
     *      validate these lines for convert to make sure we're dealing with proper data (like, no hold)
     *
     * @param array     $lineItems      One or more InventoryWorkQueue records, maybe with tracking details
     *
     * @return string                   empty, or an error message
     */
    private function validateWQDetailsForConvert($lineItems)
    {
        $message = '';
        // remember, these are all for the same document, just different line items
        foreach ($lineItems as $row) {
            // on hold?
            if (($row['HOLDPROGRESS'] === 'true') || ($row['HOLDPROGRESS'] === 'T')) {
                $text = getLocalizedTextWithThrow([['id' => 'IA.ONE_OR_MORE_LINES_ARE_ONHOLD_CANNOT_CONVERT']]);
                return GT($text, 'IA.ONE_OR_MORE_LINES_ARE_ONHOLD_CANNOT_CONVERT');
            }

        }
        return $message;
    }


    /**
     *      This adds InventoryWorkQueue records from multiple bundles together,
     *  combining data for one docentry record into one row
     *
     * @param array       $lineItemsForTarget     One or more InventoryWorkQueue records, maybe with tracking details, may be empty
     * @param array|bool  $iwqorder               One IWQOrder bundle with header and detail records
     *
     * @return array                              The updated list of InventoryWorkQueue records from combining the two sets.
     */
    private function lineMergeForConvert( $lineItemsForTarget, $iwqorder)
    {
        // Bundles contain fragments of doc entry lines.  Here, we want to collapse those lines if they refer
        // to the SAME docentry....
        foreach ($iwqorder['ENTRIES'] as $row) {
            $key = $row['DOCENTRYKEY'];
            if (isset($lineItemsForTarget[$key])) {
                $lineItemsForTarget[$key]['QUANTITY'] += $row['QUANTITY'];  // note: NOT the UIQTY....
                if (isset($row['TRACKINGENTRIES'])) {
                    foreach ($row['TRACKINGENTRIES'] as $trackRow) {
                        $lineItemsForTarget[$key]['TRACKINGENTRIES'][] = $trackRow;
                    }
                }
            } else {
                if ( ! isset($row['TRACKINGENTRIES'])) {
                    $row['TRACKINGENTRIES'] = [];
                }
                $lineItemsForTarget[$key] = $row;
            }
        }
        return $lineItemsForTarget;
    }


    //  *****************************************************************************************
    //  *****************************************************************************************
    //
    //  REGULAR CONVERSION HELPERS (on save in SODocumentManager)
    //
    //  *****************************************************************************************
    //  *****************************************************************************************


    /**
     *  Before converting a document, call this to see if there is an error
     *  to be shown to the customer: there are different states in fulfillment
     *
     * @param array     $documentTree           The DocumentManager document tree
     *
     * @return bool                             Is it safe to convert?
     */
    public function amAboutToConvert($documentTree)
    {
        // should we be here at all?  Did we already check?
        $bundlesInFF   = $documentTree['CONVERSION_BUNDLES_IN_FF'] ?? 0;
        $isAConversion = ($bundlesInFF > 0);
        $beHere        = ($documentTree['CONVERSION_SHOULD_BE_FF'] ?? $this->convertShouldIBeHere($documentTree, $isAConversion));
        if ($beHere) {
            // is this an external convert (not one from within fulfillment?)
            if ($isAConversion && ( ! isset($documentTree['ICWQORDERID']))) {
                // Is this a multi-bundle convert?
                if ($bundlesInFF > 1) {
                    $tokens = [
                        ['id' => 'IA.CANNOT_CONVERT_SALE_ORDER_THAT_IS_IN_MORE_STATE'],
                        ['id' => 'IA.IN_FULFILLMENT_UI_EITHER_COMBINE_OR_CONVERT']
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    // i18N::TODO - (Code Change Review)

                    $desc1 = GT($text,'IA.CANNOT_CONVERT_SALE_ORDER_THAT_IS_IN_MORE_STATE');
                    $desc2 =  GT($text,'IA.IN_FULFILLMENT_UI_EITHER_COMBINE_OR_CONVERT');
                    Globals::$g->gErr->addIAError(
                        'INV-0652', __FILE__ . ':' . __LINE__,
                        $desc1,['MESSAGE_VALUE'=>$desc1],
                        $desc2,['MESSAGE_VALUE'=>$desc2]
                    );

                    return false;
                }
            }
        }
        return true;
    }


    /**
     *  While converting from a Sales Order to Shipper, or Shipper to Invoice, call this.
     *  This will 'clean up' (delete) all the fulfillment records related to the passed document,
     *  thus releasing any allocated or reserved items.  This is assumed to be part of the caller's transaction.
     *
     *  Note: do this before SAVE of the new document
     *
     * @param array  $documentTree      The document tree as found in DocumentManager
     * @param array  $context           The context to be passed to convertDocumentInFulfillmentAfterSave()
     *
     * @return bool                     Everything ok?
     */
    public function convertDocumentInFulfillmentBeforeSave(& $documentTree, & $context)
    {
        $context            = [];
        $context['INUSE']   = false;    // should we even be here?

        $targetIsFulfillment = $this->convertShouldIBeHere($documentTree, $isAConversion);
        if (! $isAConversion) {
            return true;  // no work to do, no error.
        }

        // Is it possible to convert?
        $ok = $this->amAboutToConvert($documentTree);
        if ( ! $ok) {
            return false;
        }

        // Is the source document NOT in fulfillment / not alloc/reserve?
        // Then the new document may get fulfillment stuff if it is an order, but not from us here....
        $sourceIsInFulfillment = ($documentTree['CONVERSION_BUNDLES_IN_FF'] > 0);
        if ( ! $sourceIsInFulfillment ) {
            return true;
        }

        // NOTE: here, we are converting a document that had work queue records.
        //      - so we need to clean up (delete) those records
        //  We may-or-may-not be converting TO a fulfillment-enabled or reserve/allocate-enabled transaction.
        //  - if so, we may or may not want to create work queue records for them.
        //  - and we may or may not want to SAVE the reserve/allocate vales (like SO-->SO or SO-->DRAFT)

        // what do we need to do?  Gather some data....
        // Note that the line items still show the source docpar info, but the dochdr shows the target stuff
        $iwqManager             = $this->workQueueManager;
        $needToGetTrackingData  = true; // what the heck, get it always

        // we KNOW there are records out there; get them.
        // These are from the SOURCE document, not the saving document.
        $workQueueRecords       = $this->convertGetWorkQueueRecords($documentTree, $needToGetTrackingData);
        if ($workQueueRecords === false) {
            return false;
        }
        $targetStatus           = '?';
        $targetName             = '';
        $clearAllocReserved     = true;
        if ($targetIsFulfillment) {
            switch ($documentTree['CONVERSION_TARGET_DOCTYPE']) {
                case self::TD_TYPE_SALESORDER:
                    $clearAllocReserved = false;
                    // if you convert to a DRAFT ORDER, we don't want to have anything to do with it
                    if (($documentTree['STATE'] ?? DocumentManager::DEFAULT_STATE) === 'Draft') {
                        $targetStatus = 'I'; // just so it drops off fulfillment
                    } else {
                        $targetStatus = 'O';
                    }
                    break;

                case self::TD_TYPE_SHIPPER:
                    $targetStatus = 'RI';
                    break;

                case self::TD_TYPE_SHIP_DRAFT:      // also includes invoice draft
                    $clearAllocReserved = false;
                    $targetStatus = 'RS';
                    break;

                case self::TD_TYPE_INVOICE:
                    $targetStatus = 'I';
                    break;

                case self::TD_TYPE_SHIP_AND_INVOICE:
                    $targetStatus = 'I'; // just so it drops off fulfillment
                    break;

                case self::TD_TYPE_HIDDEN_SALESORDER:
                    $targetStatus = 'H';
                    break;
            }
            $targetName = $iwqManager->nameForStatus($targetStatus);    // this gets the ENGLISH NAME

            // Make sure we only get the tracking records we need, not others, from the source document
            // (if we are converting to a fulfillment document)
            $ok = $ok && $this->conversionUpdateTracking($documentTree);
        }

        if ($clearAllocReserved) {
            $this->clearAllocReserveInDocument($documentTree);
        }

        // erase any work key so it doesn't pollute the new doc
        foreach ($documentTree['ENTRIES'] as $index => $row) {
            unset($documentTree['ENTRIES'][$index]['WORKKEY']);
            $documentTree['ENTRIES'][$index]['ALLOCRESERVEISENABLED'] = $documentTree['_DOCPAR']['ENABLEALLOCRESERVE'];
        }

        // Complete all the relevant work queue records
        // do this BEFORE save because this releases any tracking data like Serial Numbers.
        $ok = $ok && $this->convertCompleteRecordsBeforeSave($workQueueRecords);


        // save stuff in the context for the next part
        if ($ok) {
            $context['INUSE']               = true;             // Yes, we should be here
            $context['TARGET']              = $targetName;
            $context['TARGETISFULFILLMENT'] = $targetIsFulfillment;
            $context['TARGETSTATUS']        = $targetStatus;
            $context['IWQ']                 = $workQueueRecords;
        }
        return $ok;
    }


    /**
     *      Clear out any allocated/reserved from the document
     *
     * @param array     $documentTree       The SODocument document
     *
     */
    private function clearAllocReserveInDocument( & $documentTree)
    {
        foreach ($documentTree['ENTRIES'] as $index => $row) {
            unset($documentTree['ENTRIES'][$index]['QUANTITYALLOCATED']);
            unset($documentTree['ENTRIES'][$index]['QUANTITYRESERVED']);
            unset($documentTree['ENTRIES'][$index]['QUANTITYRESERVEDWHENOPEN']);
            unset($documentTree['ENTRIES'][$index]['QUANTITYALLOCATEDWHENOPEN']);

            if (isset($row['TRACKINGENTRIES'])) {
                foreach ($row['TRACKINGENTRIES'] as $trackIndex => $ignore) {
                    unset($documentTree['ENTRIES'][$index]['TRACKINGENTRIES'][$trackIndex]['QUANTITYALLOCATED']);
                    unset($documentTree['ENTRIES'][$index]['TRACKINGENTRIES'][$trackIndex]['QUANTITYRESERVED']);
                    unset($documentTree['ENTRIES'][$index]['TRACKINGENTRIES'][$trackIndex]['QUANTITYPACKED']);
                }
            }
        }
    }

    /**
     *      Given a set of work queue records, mark them as completed.
     *  This releases any allocations and reservations, and updates the item records and such.
     *
     * @param array     $workQueueRecords       The work queue records
     *
     * @return bool                             Did it work?
     */
    private function convertCompleteRecordsBeforeSave($workQueueRecords)
    {
        // Deleting the records really marks them as not-active.
        // we MUST do this before we save or allocations will be in effect
        // when we need to see if tracking data is available
        $IDs = [];
        foreach ($workQueueRecords as $iwq) {
            $IDs[] = $iwq['RECORDNO'];
        }
        return (empty($IDs) || $this->workQueueManager->Delete($IDs));
    }


    /**
     *      Given a set of work queue records, that were previously 'deleted'
     * (marked completed), update them with information needed for resurrection when
     * the thing we converted to is deleted.
     *
     * @param array     $workQueueRecords       the records to complete
     * @param array     $documentTree           the DocumentManager document tree
     *
     * @return bool                             Did it work?
     */
    private function convertCompleteRecordsAfterSave($workQueueRecords, $documentTree)
    {
        $IDs = [];
        foreach ($workQueueRecords as $iwq) {
            $IDs[] = $iwq['RECORDNO'];
        }

        if (empty($IDs)) {
            return true;
        }

        $query = [
            'filters' => [[ [ 'RECORDNO',   'IN', $IDs],
                            [ 'COMPLETED',  '=', 'true']]]
        ];
        $records = $this->workQueueManager->GetList($query);  // we don't want owned records like the tracking....
        if ($records === false) {
            $records = [];
        }

        $updateTheseIWQs = [];
        foreach ($records as $iwq) {
            $iwq['CONVERTEDTO'] = $documentTree['RECORDNO'];                    // now this is filled in, before it wasn't.
            $tokens = [
                [
                    'id' => 'IA.CONVERTED_TO',
                    'placeHolders' => [
                        ['name' => 'DOC', 'value' => $documentTree['DOCID']]
                    ]
                ]
            ];
            $text_map = getLocalizedTextWithThrow($tokens);
            $text = GT($text_map,'IA.CONVERTED_TO');
            InventoryWorkQueueManager::addNote($iwq, $text);
            $updateTheseIWQs[] = $iwq;
        }

        $ok = true;
        if ( ! empty($updateTheseIWQs)) {
            $ok = $this->workQueueManager->setCompleted($updateTheseIWQs);   // bulk set for completed records
        }
        return $ok;
    }


    /**
     *  While converting from a Sales Order to Shipper, or Shipper to Invoice, call this.
     *  This will create new work queue records for the new document, if any are needed.
     *
     *  This is assumed to be part of the caller's transaction
     *
     * Note: do this after SAVE of the new document
     *
     * @param array  $documentTree      The document tree as found in DocumentManager
     * @param array  $context           The context returned from convertDocumentInFulfillmentBeforeSave()
     *
     * @return bool                     Everything ok?
     */
    public function convertDocumentInFulfillmentAfterSave(& $documentTree, $context)
    {
        if ($context['INUSE'] === false) {
            return true;    // nothing to do
        }

        $ok = $this->convertCompleteRecordsAfterSave($context['IWQ'], $documentTree);

        // Track the originating transaction
        foreach ($documentTree['ENTRIES'] as $index => $row) {
            $documentTree['ENTRIES'][$index]['ORIGINALDOCID'] = $documentTree['CONVERSION_SOURCE_DOCID'];

            // did someone change the quantity (non-bulk convert)?
            if (isset($row['QUANTITY_BEFORE_CONVERT']) && ($row['QUANTITY_BEFORE_CONVERT'] != $row['QUANTITY'])) {
                $tokens = [
                    ['id' => 'IA.THE_QTY_IN_THE_CONVERTED_CANNOT_BE_CHANGED'],
                    ['id' => 'IA.CHANGE_THE_STATUS_TO_READY_TO_PACK_OR_PICK']
                ];
                $text = getLocalizedTextWithThrow($tokens);
                // i18N::TODO - (Code Change Review)
                $desc1 =  GT($text,'IA.THE_QTY_IN_THE_CONVERTED_CANNOT_BE_CHANGED');
                $desc2 =  GT($text,'IA.CHANGE_THE_STATUS_TO_READY_TO_PACK_OR_PICK');
                Globals::$g->gErr->addIAError(
                    'INV-0682', __FILE__ . ':' . __LINE__,
                    $desc1,['MESSAGE_VALUE'=>$desc1],
                    $desc2,['MESSAGE_VALUE'=>$desc2]
                );
                return false;
            }
        }

        // We don't show invoice transactions in fulfillment, so no point in
        // creating records or anything.
        // (same for draft orders being created)
        // and if it isn't a fulfillment target, then we stop here too
        if (( ! $context['TARGETISFULFILLMENT']) || ($context['TARGETSTATUS'] === 'I')) {
            return $ok;
        }

        $ok = $ok && $this->workQueueManager->assignWorkKeysToDocEntries($documentTree['ENTRIES']);

        // Create new records in the right place for the new transaction
        $isDraft = ($documentTree['DRAFT'] === 'Draft');
        $text    = ($isDraft) ? _("on convert as DRAFT") : _("on convert");
        $ok = $ok && $this->createNewWorkRecords($documentTree, $context['TARGET'], $text);

        return $ok;
    }



    /**
     *  The transaction may have tracking records that came from the source transaction.  Great.
     *  But, maybe we aren't converting the WHOLE line item:
     *  - want 10 hammers
     *  - picked/packed 6 of them
     *  - 4 are still waiting to be picked
     *  - now convert the 6 to a shipper
     *
     *  So, if there were tracking records in the work queue records, USE THOSE.
     *
     * @param array     $documentTree           The Document Manager document tree
     *
     * @return bool                             All ok?
     *
     */
    private function conversionUpdateTracking( & $documentTree)
    {
        $documentType          = $documentTree['CONVERSION_TARGET_DOCTYPE'];
        $rollupReserveAllocate = (($documentType === self::TD_TYPE_SALESORDER) ||
            ($documentType === self::TD_TYPE_SHIP_DRAFT) ||
            ($documentType === self::TD_TYPE_HIDDEN_SALESORDER));

        // assume the new tracking entries still have their old references to
        // the OLD work queue.
        // 1) Remove the tracking record if it doesn't reference one of our work queue records
        // 2) Clear out the reference to the work queue record, as it is no longer valid
        // 3) Maybe roll up the reserve and allocated numbers, if any, into the SO
        $reserved  = 0;
        $allocated = 0;
        foreach ($documentTree['ENTRIES'] as $entryIndex => $docEntry) {

            // if no tracking, lets use the stuff in the docentry record
            if ($rollupReserveAllocate) {
                $reserved  = $docEntry['QUANTITYRESERVED'] ?? 0;
                $allocated = $docEntry['QUANTITYALLOCATED'] ?? 0;
            } else {
                $docEntry['QUANTITYRESERVED']  = 0;
                $docEntry['QUANTITYALLOCATED'] = 0;
            }

            // but if there IS tracking, maybe roll up reserve and allocated from the tracking
            if (isset($docEntry['TRACKINGENTRIES']) && ! empty($docEntry['TRACKINGENTRIES'])) {
                $reserved  = 0;
                $allocated = 0;
                foreach ($docEntry['TRACKINGENTRIES'] as $trackIndex => $tracking) {
                    // keep the tracking record, but remove the reference
                    $documentTree['ENTRIES'][$entryIndex]['TRACKINGENTRIES'][$trackIndex]['WORKQUEUEKEY'] = null;

                    if ($rollupReserveAllocate) {
                        $reserved  += $tracking['QUANTITYRESERVED'] ?? 0;
                        $allocated += $tracking['QUANTITYALLOCATED'] ?? 0;
                    } else {
                        $documentTree['ENTRIES'][$entryIndex]['TRACKINGENTRIES'][$trackIndex]['QUANTITYRESERVED']  = 0;
                        $documentTree['ENTRIES'][$entryIndex]['TRACKINGENTRIES'][$trackIndex]['QUANTITYALLOCATED'] = 0;
                    }
                }
            }

            // set these to zero or more, based on the $rollupReserveAllocate flag
            $documentTree['ENTRIES'][$entryIndex]['QUANTITYRESERVED']  = $reserved;
            $documentTree['ENTRIES'][$entryIndex]['QUANTITYALLOCATED'] = $allocated;
        }
        return true;
    }


    /**
     *      When being called for conversion, is this even something that should concern Fulfillment?
     *
     * @param array     $documentTree       The DocumentManager document tree
     * @param bool      $isAConversion      This IS a conversion
     *
     * @return bool                         Is the target in Fulfillment?  false isn't BAD, just means "it isn't"
     *
     */
    private function convertShouldIBeHere( & $documentTree, & $isAConversion)
    {
        $isAConversion = false;

        // Is this feature enabled?
        $shouldBeHere = InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_EITHER, $documentTree);

        // ARE there any details lines?
        $shouldBeHere = $shouldBeHere && isset($documentTree['ENTRIES']) && ( ! empty($documentTree['ENTRIES']));

        // Is this a conversion, and from what-to-what?
        // this is the TO document:
        $docType      = self::documentTypeFromDocTree($documentTree);
        $shouldBeHere = $shouldBeHere && ($docType !== self::TD_TYPE_OTHER);

        $sourceDocs = [];
        $source     = '';
        foreach ($documentTree['ENTRIES'] as $docEntry) {
            $deDocpar      = $docEntry['DOCPARID'] ?? '';  // not yet reset???
            $source        = $docEntry['SOURCE_DOCID'] ?? '';
            $apiConversion = (($deDocpar == '') && ($source != '') &&
                            (($documentTree['FROMAPI_2.1'] ?? false) === true) &&
                            (($docEntry['SOURCE_DOCKEY'] ?? 0) > 0));
            if ( ! $apiConversion && (($deDocpar == '') || ($deDocpar === $documentTree['DOCPARID']))) { // and it is different
                $shouldBeHere = false;  // oops, it has a source, but it isn't a convert....
                break;
            }
            $isAConversion = true;
            if ($source != '') {
                $sourceDocs[$source] = $docEntry['DOCHDRNO'] ?? ($docEntry['SOURCE_DOCKEY'] ?? 0);
            }
        }

        // no source? no conversion.  Too many sources?  Not the kind of conversion I can deal with yet
        // TODO: what happens when you multi-convert?
        $shouldBeHere = $shouldBeHere && (count($sourceDocs) === 1);

        // the target may not be in fulfillment, but perhaps the source is......
        $documentTree['CONVERSION_SOURCE_DOCID']     = $source;
        $documentTree['CONVERSION_SOURCE_DOCHDRKEY'] = $isAConversion ? $sourceDocs[$source] : '';
        $documentTree['CONVERSION_TARGET_DOCTYPE']   = $docType;
        $documentTree['CONVERSION_BUNDLES_IN_FF']    = $isAConversion ? self::bundlesInFulfillment($documentTree['CONVERSION_SOURCE_DOCHDRKEY']) : 0;
        $documentTree['CONVERSION_SHOULD_BE_FF']     = $shouldBeHere;

        return $shouldBeHere;
    }


    /**
     *      Get the right set of work queue records for the document.
     * If ICWQORDERID is present, then just get those records.  Otherwise get them all for the document.
     *
     * @param  array   $documentTree            The document tree from DocumentManager
     * @param  bool    $needToGetTrackingData   include getting tracking data
     *
     * @return array|bool                       Work Queue records, may be empty
     */
    private function convertGetWorkQueueRecords($documentTree, $needToGetTrackingData)
    {
        $iwqManager             = $this->workQueueManager;
        $wqOrderManager         = Globals::$g->gManagerFactory->getManager("inventorywqorder");
        $dochdrs = [];
        $rows    = [];
        $dochdrs[ $documentTree['CONVERSION_SOURCE_DOCHDRKEY']] = true;

        if (isset($documentTree['ICWQORDERID'])) {

            if (is_array($documentTree['ICWQORDERID'])) {
                foreach ($documentTree['ICWQORDERID'] as $row) {
                    $rows[] = ['ICWQORDERID' => $row, 'ACTION' => 'GET' ];
                }
            } else {
                $rows[] = ['ICWQORDERID' => $documentTree['ICWQORDERID'], 'ACTION' => 'GET' ];
            }
            $rows  = $wqOrderManager->clientRowsToInternalRows($rows);
            if (empty($rows)) {
                return [];  // error?
            }

            foreach ($rows as $row) {
                $dochdrs[$row['DOCHDRKEY']] = true;    // weed out dups, likely the same as above
            }
        }

        // Just find the record numbers we want
        $sql   = [];
        $iwqs  = [];
        $sql[] = "SELECT  IWQKEY, DOCHDRKEY, WAREHOUSEKEY, STATUS, SHIPTOKEY, HOLDPROGRESS
                    FROM   v_invwqdetail
                    WHERE  cny# = :1 ";
        $sql[] = GetMyCompany();
        $sql   = PrepINClauseStmt($sql, array_keys($dochdrs), ' and DOCHDRKEY ');
        $rtn = QueryResult($sql);
        if ($rtn === false) {
            return false;
        }
        if ( ! empty($rtn)) {
            $getThese = [];
            foreach ($rtn as $oneRec) {
                if ($oneRec['HOLDPROGRESS'] === 'T') {
                    Globals::$g->gErr->addIAError('INV-0133', __FILE__ . ':' . __LINE__,
                        'Cannot convert a transaction that is on hold in fulfillment.',
                        [],
                        "In the fulfillment UI, remove the HOLD status and try again.",
                        []
                    );
                    return false;
                }
                if (empty($rows)) {
                    $getThese[] = $oneRec['IWQKEY'];
                } else {
                    // it must match at least one of our rows....
                    // but we don't expect a LOT of rows per record fetched, and we don't
                    // expect a lot of records fetched for this document.
                    $found = false;
                    foreach ($rows as $row) {
                        if (($row['DOCHDRKEY'] === $oneRec['DOCHDRKEY']) &&
                            ($row['WAREHOUSEKEY'] === $oneRec['WAREHOUSEKEY']) &&
                            ($row['SHIPTOKEY'] === $oneRec['SHIPTOKEY']) &&
                            ($row['CURRENTSTATE'] === $oneRec['STATUS'])) {
                            $found = true;
                            break;
                        }
                    }
                    if ($found) {
                        $getThese[] = $oneRec['IWQKEY'];
                    }
                }
            }

            // get the full records
            if ( ! empty($getThese)) {
                $ok = $iwqManager->getByRecordNumber($getThese, $iwqs, $needToGetTrackingData);
                if ($ok === false) {
                    return false;
                }
            }
        }
        return $iwqs;
    }




    //  *****************************************************************************************
    //  *****************************************************************************************
    //
    //  DOCUMENT GET/ADD/UPDATE HELPERS
    //
    //      When a document is added or updated over in SODocumentManager, these gets called.
    //  They may need to add a record to fulfillment or to the 'HIDDEN' place in fulfillment.
    //
    //  *****************************************************************************************
    //  *****************************************************************************************


    /**
     *  Is this document entry record something we should create work queue records for?
     *  (assuming the enclosing document is the right type)
     *  - Item or Stockable Kit
     *  - OR non-inventory-item but with the Enable Fulfillment flag on
     *  - has quantity
     *  - not a drop ship
     *
     * @param array     $dcEntry                    Document entry record
     * @param bool      $reservableItem             (output) is the item 'reservable'
     * @param array     $trackingNeededByItemId     Info about the items
     * @param bool      $enableFulfillmentFlag      Is fulfillment ON for the document?  (If false, then ONLY Reserve/Allocate is on)
     *
     * @return bool
     */
    private function docEntryShouldHaveAWorkQueue($dcEntry, & $reservableItem, $trackingNeededByItemId, $enableFulfillmentFlag)
    {
        [ $itemID ] = explode( '--', $dcEntry['ITEMID']);
        $reservableItem = $trackingNeededByItemId[$itemID]['CANRUNOUT'] ?? false;
        // non-reservable, i.e. non-inventory, are allowed if this is a fulfillment document, but not if only reserve/allocate
        $rowOk = $reservableItem || (($trackingNeededByItemId[$itemID]['ENABLEFULFILLMENT'] ?? false) && $enableFulfillmentFlag);
        $rowOk = $rowOk && ((($dcEntry['QUANTITY'] ?? 0) > 0) || (($dcEntry['UIQTY'] ?? 0) > 0)); // before SET, sometimes quantity is not filled in yet
        $rowOk = $rowOk && (($dcEntry['DROPSHIP'] ?? 'false') === 'false');

        return $rowOk;
    }


    /**
     *      When in SODocument there is a get(), this is called so we can do any fixups of the data for
     *  fulfillment/alloc reserve stuff.
     *
     *  THIS IS THE MAIN ENTRY POINT FROM GET SODOCUMENT
     *
     * @param array        $documentTree    The whole document tree from SODocumentManager
     *
     * @return bool                         Everything ok?
     */
    public function documentGet( & $documentTree)
    {
        if ($this->documentGetAddUpdateShouldWeBeHere($documentTree, $badState, true) === false) {
            return true;    // shouldn't be here but nothing is wrong....
        }

        // remember the state when we READ the document, so we can see if it changes
        $documentTree['STATE_ON_READ'] = $documentTree['STATE'];

        // Hold the phone!  On a COPY we want to make sure and remove
        // reserve and allocated, and any tracking entries
        $copyMode = Request::$r->_copymode ?? '';
        if ($copyMode === 'Copy') {
            foreach ($documentTree['ENTRIES'] as $index => $entry) {
                $documentTree['ENTRIES'][$index]['QUANTITYRESERVED'] = 0;
                $documentTree['ENTRIES'][$index]['QUANTITYALLOCATED'] = 0;
                $documentTree['ENTRIES'][$index]['QUANTITYRESERVEDWHENOPEN'] = 0;
                $documentTree['ENTRIES'][$index]['QUANTITYALLOCATEDWHENOPEN'] = 0;
                $documentTree['ENTRIES'][$index]['INVFF_NEEDS_WORKQUEUE'] = false;    // may be copying to a non-FF txn
                $documentTree['ENTRIES'][$index]['INVFF_WORKQUEUE_PLACE'] = "?";      // ditto
                $documentTree['ENTRIES'][$index]['TRACKINGENTRIES'] = [];       // this is done for copies anyway, but....
            }
        }
        return true;
    }


    /**
     *      When converting a shipper or invoice from DRAFT to not-DRAFT, call this
     *
     * @param array     $documentTree       SODocument's document tree
     * @param string    $docType            Current doc type
     *
     * @return bool
     * @throws Exception
     */
    private function convertDraftToNonDraft( & $documentTree, $docType)
    {
        $ok = true;

        // erase reserve/allocate data
        $this->clearAllocReserveInDocument($documentTree);
        $workQueueRecords       = $this->workQueueManager->getMany($documentTree['RECORDNO'], InventoryWorkQueueManager::GET_MANY_DOCHDR);
        if ($workQueueRecords === false) {
            return false;
        }
        // and update the work queue records, so we don't hold onto reserve/allocate.
        // (we don't expect any for invoice or ship_and_invoice)
        $setThese = [];
        foreach ($workQueueRecords as $row) {
            InventoryWorkQueueManager::clearNote($row);
            $text = getLocalizedTextWithThrow([['id' => 'IA.POSTED_AS_NON_DRAFT']]);
            InventoryWorkQueueManager::addNote(  $row, GT($text,'IA.POSTED_AS_NON_DRAFT'));
            $row['DELTARESERVE']         = - ($row['QUANTITYINRESERVE']    ?? 0);
            $row['DELTAALLOCATION']      = - ($row['QUANTITYINALLOCATION'] ?? 0);
            $row['QUANTITYINRESERVE']    = 0;
            $row['QUANTITYINALLOCATION'] = 0;
            $row['DOCUMENTTYPE']         = $docType;    // update it so we don't think it is still in draft state
            // let's hope this is a shipper; move it to 'to be invoiced'
            if ($docType === self::TD_TYPE_SHIPPER) {
                $row['PLACE'] = InventoryWorkQueueManager::QUEUE_PREFIX_FULFILLMENT . "TOBEINVOICED";
            }
            $setThese[] = $row;
        }
        if ( ! empty($setThese)) {
            $ok = $this->workQueueManager->set($setThese);
        }
        return $ok;
    }


    /**
     *      A 'Closed' transaction should not have any Reserve/Allocate numbers.  This can happen
     *  when someone creates an SO for Reserve/Allocate, but they do not have anywhere it can convert to.
     *  Because there's no conversion possible, the transaction is 'Closed'.
     *
     * When this is called, documentGetAddUpdateShouldWeBeHere() has said 'no', but indicated the state was bad.
     * That means we passed other tests ok, like the right kind of transaction, there ARE entries, and the EA flag being on.
     *
     * @param array     $documentTree   The SODocument's document tree
     *
     * @return bool                     true if no error
     */
    private function checkForClosedTransactionWithRA($documentTree)
    {
        $stateNow      = $documentTree['STATE'] ?? DocumentManager::DEFAULT_STATE;
        if ($stateNow === 'Closed') {
            foreach ($documentTree['ENTRIES'] as $docEntry) {
                $newPicked              = $docEntry['QUANTITYALLOCATED'] ?? 0;
                $newReserved            = $docEntry['QUANTITYRESERVED']  ?? 0;
                // we COULD check tracking records, but ... I won't :-)
                if ($newPicked || $newReserved) {
                    Globals::$g->gErr->addIAError('INV-0134', __FILE__ . ':' . __LINE__,
                        "The reserved or picked quantities that you entered cannot be recorded because
                        the order cannot be converted to another transaction.",
                        [],
                        "Remove any values entered for quantity reserved and quantity picked (allocated).
                        Then, try again.",
                        []
                    );
                    return false;
                }
            }
        }
        return true;
    }


    /**
     *  Just before we Update a document in SODocumentManager, check for things where we need access to the data
     *  BEFORE it changes.
     *
     * This is also called in Add(), before the add.  There, there's not much to do but bookkeeping.
     *
     *     If one converts an ORDER into a DRAFT SHIPPER, or a SHIPPER into a DRAFT INVOICE,
     *  then the draft goes through our conversion code, called on SODocument::Add().
     *
     *  But, then, when the DRAFT is POSTED (and so no longer a draft), it comes through
     *  SODocument::Set() and does not look like a conversion (because it is not).
     *
     *  So, even though it is not a conversion, it may have had allocated/reserved amounts
     *  to hold the items until we could post.  Now, when posting, we need to remove the
     *  allocated/reserve amounts
     *
     *      Also, if a row is DELETED, take it out of fulfillment entirely.
     *
     * @param   array                   $documentTree       The whole document tree from SODocumentManager
     * @param   SODocumentManager       $soDocumentManager  The SO document manager instance we are being called from
     *
     * @return bool                                     Everything ok?
     */
    public function documentBeforeUpdate( & $documentTree, $soDocumentManager)
    {
        $this->soDocumentManager = $soDocumentManager;
        if ($this->documentGetAddUpdateShouldWeBeHere($documentTree, $badState, true) === false) {
            // maybe trying to update a closed transaction with a reserved/allocated value?
            return ($badState) ? $this->checkForClosedTransactionWithRA($documentTree) : true;
        }

        // since we are called before save, it is possible the quantity has not been set yet....
        $UOMValues = [];
        foreach ($documentTree['ENTRIES'] as $index => $docEntry) {
            if ($docEntry['INVFF_NEEDS_WORKQUEUE']) {
                if ( ! isset($docEntry['QUANTITY'])) {
                    if (empty($UOMValues)) {
                        $this->getUOMValues($documentTree, $UOMValues);
                    }
                    [ $itemID ] = explode( '--', $docEntry['ITEMID']);
                    $documentTree['ENTRIES'][$index]['ITEMID'] = $itemID;
                    $unit       = $docEntry['UNIT'];
                    $convfactor = $UOMValues[$itemID][$unit]['CONVFACTOR'] ?? 1;

                    $docEntry['QUANTITY'] = ibcmul($docEntry['UIQTY'],  $convfactor, ItemManager::DEFAULT_UOM_PRECISION, true);
                    $documentTree['ENTRIES'][$index]['QUANTITY'] = $docEntry['QUANTITY'];
                }
            }
        }


        $docType    = self::documentTypeFromDocTree($documentTree);

        // have we gone from DRAFT to NON-DRAFT?
        $stateNow   = $documentTree['STATE'] ?? DocumentManager::DEFAULT_STATE;
        if (($stateNow !== 'Draft') && (($documentTree['STATE_ON_READ'] ?? '') === 'Draft')) {
            // is it now a shipper or invoice?
            // Orders that were drafts were not in Fulfillment before, so nothing to do for them
            if (($docType === self::TD_TYPE_SHIPPER) ||
                ($docType === self::TD_TYPE_INVOICE) ||
                ($docType === self::TD_TYPE_SHIP_AND_INVOICE)) {
                return $this->convertDraftToNonDraft($documentTree, $docType);
            }
        }

        // if NOT being converted from draft to posting,
        //    then we only want to worry about sales orders
        if (($docType !== self::TD_TYPE_SALESORDER) &&
            ($docType !== self::TD_TYPE_HIDDEN_SALESORDER)) {
            return true;
        }

        // get any existing work queue records into memory
        $ok = $this->getWorkQueueRecordsIntoExistingDocentrys($documentTree);

        // Do edit checks on the pre-save data
        $ok = $ok && $this->verifyBeforeOESave($documentTree);

        return $ok;
    }


    /**
     *      When adding or updating a document, we check the TD for whether fulfillment is enabled or whether the
     *  Reserve/Allocate feature is enabled.  If so, we make sure there's a record in the Work Queue
     *  to support these, tracking records point to the right place, and do other fixups as needed.
     *
     *  THIS IS THE MAIN ENTRY POINT FROM ADD/UPDATE SODOCUMENT
     *
     * @param   array                   $documentTree   The whole document tree from SODocumentManager
     *
     * @return bool                                     Everything ok?
     */
    public function documentAddedOrUpdated( & $documentTree )
    {
        // Is this a fulfillment transaction?
        if ($this->documentGetAddUpdateShouldWeBeHere($documentTree, $badState ) === false) {
            // if not caught earlier, then this is maybe a NEW transaction with RA values but is closed?
            return ($badState) ? $this->checkForClosedTransactionWithRA($documentTree) : true;
        }

        // if any docentry records don't have work keys, assign them
        // (by now they should have record numbers)
        $ok = $this->workQueueManager->assignWorkKeysToDocEntries($documentTree['ENTRIES']);

        // Add work queue records for new docentry records that just got a RECORDNO.
        // Read all work queue records into docentry's ['IWQS'] array.
        $ok = $ok && $this->documentAUFindOrAddWorkQueueRecords($documentTree);

        // Update any work queue records, if needed, because the docentry records changed.
        $ok = $ok && $this->maybeUpdateWorkQueueForDocument($documentTree);


        // cleanup: sum the tracking records if any,
        //        delete or update work queue records if needed
        $updateIwqs = [];
        $deleteIwqs = [];
        $addIwqs    = [];
        $updatedTracking = [];
        $updatedEntries  = [];
        foreach ($documentTree['ENTRIES'] as $index => $row) {

            if ($row['INVFF_NEEDS_WORKQUEUE']) {

                $ok = $ok && $this->addUpTrackingReserveAllocated($row);
                $documentTree['ENTRIES'][$index] = $row; // so everything is in sync

                // this should be unusual, like if they raise or lower the quantity on the line
                if ($row['FFINV_NEEDSUPDATE']) {
                    $updatedEntries[] = $row; // can't do these in bulk, sadly
                }

                // this should also be unusual, like if we recompute reserved quantity for them
                if (isset($row['TRACKINGENTRIES'])) {
                    foreach ($row['TRACKINGENTRIES'] as $track) {
                        if ($track['FFINV_NEEDSUPDATE'] ?? false) {
                            $updatedTracking[] = $track;
                        }
                    }
                }

                if (isset($row['IWQS'])) {
                    foreach ($row['IWQS'] as $recordNumber => $iwq) {
                        if ($iwq['FFINV_NEEDSUPDATE'] ?? false) {
                            if (($iwq['RECORDNO'] ?? 0) == 0) {
                                $addIwqs[] = $iwq;
                            } else {
                                if ($iwq['QUANTITY'] <= 0) {
                                    $deleteIwqs[] = $recordNumber;   // dropped to zero, delete it AND ORPHAN ANY TRACKING
                                } else {
                                    $updateIwqs[] = $iwq;   // update this one
                                }
                            }
                        }
                    }
                }
            }
        }

        // update docentry rows if need be, this shouldn't be often
        if ($ok && ! empty($updatedEntries)) {
            $sql = [];
            $sql[] = "Update docentrymst set QUANTITYRESERVED = :3, QUANTITYALLOCATED = :4
                                    where cny# = :1 and record# = :2 ";
            $sql[] = GetMyCompany();
            foreach ($updatedEntries as $row) {
                $sql[] = $row['RECORDNO'];
                $sql[] = $row['QUANTITYRESERVED'];
                $sql[] = $row['QUANTITYALLOCATED'];
                $ok    = $ok && ExecStmt($sql);
            }
        }

        // update any tracking rows if need be
        if ( ! empty($updatedTracking)) {
            $trackMan = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
            $trackMan->set($updatedTracking);
        }

        // and any IWQ records that were updated or deleted
        if ( ! empty($updateIwqs)) {
            $ok = $ok && $this->workQueueManager->set($updateIwqs);
        }
        if ( ! empty($deleteIwqs)) {
            $ok = $ok && $this->workQueueManager->Delete($deleteIwqs);
        }
        if ( ! empty($addIwqs)) {
            $ok = $ok && $this->workQueueManager->add($addIwqs);
        }

        // ok, one last check.  We've updated all the databases, the caller already saved the document, we're
        // really just about done.  BUT, is the total allocated/reserved MORE THAN ONHAND?
        $ok = $ok && $this->checkAllocateReserveIsNotMoreThanOnHand($documentTree);

        return $ok;
    }


    /**
     *  Is the sum of allocate and reserve more than onhand for each item/warehouse?
     *
     * @param  array    $documentTree   The whole document tree from SODocumentManager
     *
     * @return bool                     true if there is enough ONHAND to match ALLOCATE/RESERVE
     */
    private function checkAllocateReserveIsNotMoreThanOnHand($documentTree)
    {
        $getWarehouse = function($docEntry) {
            $wh     = $docEntry['WAREHOUSE']['LOCATION_NO'] ?? '';
            [ $wh ] = explode('--', $wh);
            return $wh;
        };


        // get the list of items/warehouses
        $items      = [];
        $warehouses = [];
        $itemWH     = [];
        foreach ($documentTree['ENTRIES'] as $row) {
            if ($row['INVFF_NEEDS_WORKQUEUE']) {
                $inUse = ibcadd($row['QUANTITYRESERVED'] ?? 0, $row['QUANTITYALLOCATED'] ?? 0, ItemManager::AVERAGE_COST_DECIMALS, true );
                if ($inUse != 0) {
                    $itemID = $row['ITEMID'];
                    if ( ! self::allowNegativeUncommitted($itemID)) {
                        $items[$itemID] = true;                        // avoid dups
                        $warehouseID = $getWarehouse($row);
                        $warehouses[$warehouseID] = true;
                        $itemWH[$itemID][$warehouseID] = $inUse;    // in case we can't find it in the warehouse
                    }
                }
            }
        }

        $ok = true;
        $count = 0;
        if ( ! empty($items) && ! empty($warehouses)) {
            $iwInfoManager = Globals::$g->gManagerFactory->getManager('itemwarehouseinfo');
            $query = [
                'select' => ['ITEMID', 'WAREHOUSEID', 'WONHAND', 'WRESERVED', 'WALLOCATED'],
                'filters' => [ [ [ 'ITEMID', 'IN', array_keys($items) ], [ 'WAREHOUSEID', 'IN', array_keys($warehouses) ] ] ]
            ];
            $rows = $iwInfoManager->GetList($query);
            if ($rows === false) {
                return false;
            }

            // here we get more combinations of items/warehouses than we want.  For example, we want
            // Hammers from WH1 and Nails from WH2, here we may get Hammers from both WH1 and WH2.
            // so, we filter the results to the ones we wanted.
            foreach ($rows as $row) {
                $wonhand     = $row['WONHAND'] ?? 0;
                $reserved    = $row['WRESERVED'] ?? 0;
                $allocated   = $row['WALLOCATED'] ?? 0;
                $itemID      = $row['ITEMID'];
                $warehouseID = $row['WAREHOUSEID'];
                if (isset($itemWH[$itemID][$warehouseID])) {
                    unset($itemWH[$itemID][$warehouseID]);  // seen this one, no need to worry
                    if ($wonhand < ($reserved + $allocated)) {
                        Globals::$g->gErr->addIAError(
                            'INV-0626', __FILE__ . ':' . __LINE__,
                            sprintf("Reserved (%1s) + Allocated (%2s) exceeds the quantity on
                            hand (%3s) for item '%4s' and warehouse '%5s'.",
                            $reserved, $allocated, $wonhand, $itemID, $warehouseID),
                            ['RESERVED' => $reserved, 'ALLOCATED' => $allocated, 'WONHAND' => $wonhand, 'ITEMID' => $itemID, 'WAREHOUSEID' => $warehouseID],
                            "Lower the reserved or allocated amounts and try again.",[]);
                        $ok = false;
                        $count++;
                        if ($count > 4) {
                            break;  // don't do this 1000 times!
                        }
                    }
                }
            }

            // Ok, but wait!  If there were no purchases from a warehouse of an item, then there IS NO RECORD
            // in the itemwarehouse table!  So, here, the $itemWH will still exist, meaning ON HAND is ZERO!!
            // (and we do not know the total reserve/allocate, but the fact that we have some here is bad....)
            if ($ok) {
                foreach ($itemWH as $itemID => $whs) {
                    if ( ! self::allowNegativeUncommitted($itemID)) {
                        foreach ($whs as $whID => $inUse) {
                            Globals::$g->gErr->addIAError('INV-0627', __FILE__ . ':' . __LINE__,
                                sprintf("Reserved + Allocated (%1s) exceeds the quantity on hand (%2s)
                                for item '%3s' and warehouse '%4s'.",
                                $inUse, '0', $itemID, $whID),
                                ['IN_USE'=>$inUse,'ITEMID'=>$itemID,'WHID'=>$whID],
                                "Lower the reserved or allocated amounts and try again.",[]);
                            $ok = false;
                            $count++;
                            if ($count > 4) {
                                break;  // don't do this 1000 times!
                            }
                        }
                    }
                }
            }
        }
        return $ok;
    }


    /**
     *      While geting/adding/updating a record, do we need any fulfillment/reserve/allocate treatment?
     *  - TD must be enabled for fulfillment or reserve/allocate
     *  - txn must be in the right state (turns out DRAFT orders shouldn't be here as per QA)
     *     - state is NULL if coming in FROM a draft to a real post
     *  - Must be an order (shippers are handled as part of conversion)
     *  - txn must have entries
     *  - at least one entry must be type I, SK, or non-inventory but enabled for fulfillment
     *      - with quantity greater than quantity converted
     *      - not drop-ship
     *
     *
     * @param array     $documentTree               The add or update document tree from SODocumentManager
     * @param bool      $badState                   Transaction is oterwise likely ok, but in the wrong state.
     * @param bool      $allowAllDocTypes           if true, any FF doc type is good, false means only orders and hidden
     *
     * @return bool                                 Should we be here?
     */
    private function documentGetAddUpdateShouldWeBeHere( & $documentTree, & $badState, $allowAllDocTypes = false )
    {
        $badState = false;

        // requests from the API go through the xml gateway not the form editor.  Because of that,
        // the DOCPAR is not always fetched.  Take care of that here.
        if ($this->soDocumentManager && (($documentTree['FROMAPI_2.1'] ?? false) === true) && ( ! isset($documentTree['_DOCPAR']))) {
            $docparMgr = $this->soDocumentManager->get_docpar_manager();
            $documentTree['_DOCPAR'] = $docparMgr->GetBaseLatest($documentTree['DOCPARID']);
        }

        // Is this feature enabled?
        $shouldBeHere = InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_EITHER, $documentTree);
        if ( ! $shouldBeHere) {
            return false;    // nothing to see here, move along
        }
        $allowedStates = ['Approved', 'Pending', 'Partially Converted', 'Partially Converted By Line' /* , 'Draft' */ ];

        $docType       = self::documentTypeFromDocTree($documentTree);
        if ($allowAllDocTypes) {
            $shouldBeHere = $shouldBeHere && ($docType !== self::TD_TYPE_OTHER);
            $allowedStates[] = 'Draft';
        } else {
            $shouldBeHere = $shouldBeHere &&
                (($docType === self::TD_TYPE_SALESORDER) ||
                    ($docType === self::TD_TYPE_HIDDEN_SALESORDER));
        }
        $shouldBeHere  = $shouldBeHere && isset($documentTree['ENTRIES']) && ( ! empty($documentTree['ENTRIES']));
        $stateNow      = $documentTree['STATE'] ?? DocumentManager::DEFAULT_STATE;
        if ($shouldBeHere) {
            $shouldBeHere = $shouldBeHere && in_array($stateNow, $allowedStates);
            if (!$shouldBeHere) {
                $badState = true;   // everything above here is fine, but we are in the wrong state, maybe 'Closed'.
            }
        }

        // and what about the line items?  Should THEY be here?
        if ($shouldBeHere) {
            $foundOne               = false;
            $reserveAllocateEnabled = (($documentTree['_DOCPAR']['ENABLEALLOCRESERVE'] ?? 'false') === 'true');
            $enableFulfillmentFlag  = (($documentTree['_DOCPAR']['ENABLEFULFILLMENT']  ?? 'false') === 'true');

            // we know from above that there is at least one entry
            // Get the tracking status of the items
            // TODO: This gets tracking status for kits and stockable kit builds,
            //      BUT nothing else supports that yet, so this is a tease...
            $itemIds = [];
            foreach ($documentTree['ENTRIES'] as $entry) {
                [ $itemID ] = explode( '--', $entry['ITEMID']);
                $itemIds[$itemID] = true;
                // get components, if there (not really neded yet by FF/RA, but...)
                if (isset($entry['ITEMDETAILS'])) {
                    foreach ($entry['ITEMDETAILS'] as $row) {
                        [ $itemID ] = explode( '--', $row['ITEMID']);
                        $itemIds[$itemID] = true;
                    }
                }
            }

            $trackingNeededByItemId = self::getTrackedStatusOfItems(array_keys($itemIds));

            foreach ($documentTree['ENTRIES'] as $index => $row) {

                $documentTree['ENTRIES'][$index]['INVFF_NEEDS_WORKQUEUE'] = false;  // assume

                $rowOk = $this->docEntryShouldHaveAWorkQueue($row, $reservableItem, $trackingNeededByItemId, $enableFulfillmentFlag);
                if ($rowOk) {
                    $foundOne               = true;   // at least one is ok

                    [ $itemID ] = explode( '--', $row['ITEMID']);
                    $isTracked = $trackingNeededByItemId[$itemID]['TRACKED'];
                    if ($isTracked) {
                        if (! isset($row['TRACKINGENTRIES'])) {
                            $documentTree['ENTRIES'][$index]['TRACKINGENTRIES'] = [];   // so the rest of the code just checks for this
                        }
                    } else {
                        unset($documentTree['ENTRIES'][$index]['TRACKINGENTRIES']); // so we don't assume it is tracked
                    }

                    // does this row get a record in the work queue? (tracked or not)
                    $documentTree['ENTRIES'][$index]['INVFF_NEEDS_WORKQUEUE'] = true;   // so we create one if needed
                    $documentTree['ENTRIES'][$index]['INVFF_WORKQUEUE_PLACE'] =
                        (($docType === self::TD_TYPE_HIDDEN_SALESORDER) ? 'H' : 'O'); // Hidden or Open?

                    // do we need to set the allocreserve enabled flag?
                    if ($reserveAllocateEnabled && $reservableItem &&
                        (($row['ALLOCRESERVEISENABLED'] ?? 'false') !== 'T') &&
                        (($row['ALLOCRESERVEISENABLED'] ?? 'false') !== 'true')) {
                        $documentTree['ENTRIES'][$index]['ALLOCRESERVEISENABLED'] = 'true'; // we will save this record soon....
                    }
                } else if ((($row['ALLOCRESERVEISENABLED'] ?? 'false') === 'T') || (($row['ALLOCRESERVEISENABLED'] ?? 'F') === 'true')) {
                    // they changed the item type and it no longer deserves alloc/reserve treatment
                    $documentTree['ENTRIES'][$index]['ALLOCRESERVEISENABLED'] = 'false'; // we will save this record soon....
                }
            }
            $shouldBeHere = $shouldBeHere && $foundOne; // no line items to care about?
        }
        return $shouldBeHere;
    }


    /**
     *      Each eligible docentry in the document must have a corresponding work queue record.
     *  - IF there is no record, we need to add one
     *  - If there are records,
     *      - if the quantity on a line exceeds the sum of what is currently in the work queue,
     *          - we need to add or update one
     *          - we add to the work queue record HIDDEN or OPEN
     *          - documententrytrackdetail records with no workkey get assigned to that closest work queue
     *
     * @param array       $documentTree     The whole document tree from the SODocumentManager
     *
     * @return bool                         everything ok?
     */
    private function documentAUFindOrAddWorkQueueRecords( & $documentTree )
    {
        // get the work keys for this document that have work queue records
        $workKeys = $this->workQueueManager->documentEntriesInFFByDocHdrKey($documentTree['RECORDNO'] ?? 0);
        if ($workKeys === false) {
            return false;
        }

        // if any docentry has no work queue records, we need to add one.
        $newRecordsNeeded = [];
        foreach ($documentTree['ENTRIES'] as $index => $docEntry) {
            // ignore docentry rows that don't participate in our goodness
            if ($docEntry['INVFF_NEEDS_WORKQUEUE']) {
                $workKey            = $docEntry['WORKKEY'];  // should be there....
                $iwqCount           = $workKeys[$workKey] ?? 0;
                $openRecordNumber   = $docEntry['IWQ_OPEN'] ?? 0;   // leftover from before the docyment save
                // If there is an existing open record, we can increase that record by what we need.
                // Otherwise, create one.  For examples: new line? create.  Existing line? depends!
                if ($openRecordNumber === 0) {
                    // do we need more? less?
                    // delta > 0 means we need delta MORE
                    //       < 0 means we need to lower one of them
                    $delta = ibcsub($docEntry['QUANTITY'] ?? 0, $iwqCount, ItemManager::AVERAGE_COST_DECIMALS, true);
                    if ($delta > 0) {
                        $newRecordsNeeded[$index] = $delta; // add a new IWQ for this additional amount
                    }
                }
            }
        }

        $ok = true;
        // if we need to add records, do so now
        if ( ! empty($newRecordsNeeded)) {
            $ok = $this->createWorkQueueRecordsWithQuantity($documentTree, $newRecordsNeeded);
        }

        // Assign any new tracking data to the open work queue
        foreach ($documentTree['ENTRIES'] as $deIndex => $docEntry) {

            if ($docEntry['INVFF_NEEDS_WORKQUEUE']) {

                if (isset($docEntry['TRACKINGENTRIES'])) {

                    $unassignedTracking = false;
                    foreach ($docEntry['TRACKINGENTRIES'] as $oneTrack) {
                        if (!isset($oneTrack['WORKQUEUEKEY']) || ($oneTrack['WORKQUEUEKEY'] == 0)) {
                            $unassignedTracking = true;
                            break;
                        }
                    }

                    if ($unassignedTracking) {

                        // we verified before save that there was an open record for any existing row with new entries
                        $openRecordNumber = $docEntry['IWQ_OPEN'] ?? 0;

                        // are there un-assigned tracking records but no open record?
                        if ($openRecordNumber === 0) {
                               $docEntryPlusOne = $docEntry['LINE_NO'] +1;
                               Globals::$g->gErr->addIAError('INV-0628', __FILE__ . ':' . __LINE__,
                               sprintf('This row is in Fulfillment and does not support new tracking
                               rows on line %s.', $docEntryPlusOne),
                               ['DOC_ENTRY_LINE_NO_PLUS_1'=>$docEntryPlusOne],
                               "Remove the new tracking and try again.",[]);
                                return false;
                        }

                        // by here, we may need and can support new tracking....
                        $this->assignNewTrackingToWorkQueue($documentTree['ENTRIES'][$deIndex]['TRACKINGENTRIES'],
                                    $documentTree['ENTRIES'][$deIndex]['IWQS'][$openRecordNumber],
                                    $openRecordNumber);
                    }
                }
            }
        }

        // re-fetch all the work queue records so we have the proper tracking and such
        $ok = $ok && $this->getWorkQueueRecordsIntoExistingDocentrys($documentTree);

        return $ok;
    }


    /**
     *      We need new work queue records added in either the OPEN or HIDDEN place, so do that here.
     * Note: this would happen on all new sales orders and could happen for each I or SK line, so we do this in bulk.
     * Note: if you INCREASE an existing line, this may be called to add the extra quantity
     *
     * @param array                     $documentTree               The SODocument tree
     * @param float[]                   $newRecordsNeeded           The by index into ENTRIES, how much quantity do we need?
     *
     * @return bool
     */
    private function createWorkQueueRecordsWithQuantity( &$documentTree, $newRecordsNeeded)
    {
        // Do a Funky Chicken to make createNewWorkRecords work....
        $tempDocTree = $documentTree;
        $tempDocTree['ENTRIES'] = [];
        $place = null;
        foreach ($newRecordsNeeded as $index => $quantity) {
            $de = $documentTree['ENTRIES'][$index];

            // ARE there any work queue records already?
            $iwqReserved                   = 0;
            $iwqAllocated                  = 0;
            foreach ($de['IWQS'] as $iwq) {
                $iwqReserved              += $iwq['QUANTITYINRESERVE']  ?? 0;
                $iwqAllocated             += max($iwq['QUANTITYPICKED'] ?? 0, $iwq['QUANTITYPACKED'] ?? 0);
            }

            // when we create the record, lets get the right reserved and allocated so that
            // when we update it with tracking entries we update it and don't create a new record
            $reserved                   = $de['QUANTITYRESERVED']  ?? 0;
            $allocated                  = $de['QUANTITYALLOCATED'] ?? 0;
            $origReserved               = $reserved;
            if (isset($de['TRACKINGENTRIES'])) {
                $reserved               = 0;
                $allocated              = 0;
                foreach ($de['TRACKINGENTRIES'] as $tracking) {
                    $reserved  = ibcadd( $reserved,  $tracking['QUANTITYRESERVED']  ?? 0, ItemManager::AVERAGE_COST_DECIMALS, true);
                    $allocated = ibcadd( $allocated, $tracking['QUANTITYALLOCATED'] ?? 0, ItemManager::AVERAGE_COST_DECIMALS, true);
                }
            }
            $de['QUANTITYRESERVED']     = (($origReserved > $reserved) ? $origReserved : $reserved) - $iwqReserved;
            $de['QUANTITYALLOCATED']    = $allocated - $iwqAllocated;

            $de['TRACKINGENTRIES']      = []; // since this is a NEW entry, don't try to save any existing tracking data; that may come later
            $de['QUANTITY']             = $quantity;    // which may be less than what was there before
            $de['INVFF_ORIGINAL_INDEX'] = $index;

            $tempDocTree['ENTRIES'][]   = $de;

            // place is the same for every record, so just get it the first time
            $place = $place ?: $this->workQueueManager->nameForStatus($de['INVFF_WORKQUEUE_PLACE']);
        }

        $ok = $this->createNewWorkRecords($tempDocTree, $place, _("for new line item"));
        if ($ok) {
            foreach ($tempDocTree['ENTRIES'] as $de) {
                $index = $de['INVFF_ORIGINAL_INDEX'];
                // restore the old and new iwq records
                foreach ($de['IWQS'] as $recordNumber => $iwq) {
                    $documentTree['ENTRIES'][$index]['IWQS'][$recordNumber] = $iwq;
                    $documentTree['ENTRIES'][$index]['IWQ_OPEN']            = $recordNumber;
                    $documentTree['ENTRIES'][$index]['IWQ_QUANTITY']        = $iwq['QUANTITY'];
                    if (isset($documentTree['ENTRIES'][$index]['TRACKINGENTRIES'])) {
                        $this->assignNewTrackingToWorkQueue($documentTree['ENTRIES'][$index]['TRACKINGENTRIES'],
                            $documentTree['ENTRIES'][$index]['IWQS'][$recordNumber],
                            $recordNumber);
                    }
                }
            }
        }
        return $ok;
    }


    /**
     *      If you have tracking records without an owning work queue, assign them through this.
     *
     * @param   array   $trackingEntries                Tracking entries that may not have a WORKKEY
     * @param   array   $workQueueRecord                The work queue record to attach the entry to
     * @param   int     $workQueueRecordNumber          The WORKKEY to assign
     *
     * @return bool
     */
    private function assignNewTrackingToWorkQueue( & $trackingEntries, & $workQueueRecord, $workQueueRecordNumber)
    {
        // who needs a work queue key assigned?
        $ok = true;

        // does this work queue record already have the tracking records in it?
        // for example, on a convert
        $wqTracking     = [];
        if (isset($workQueueRecord['TRACKINGENTRIES'])) {
            foreach ($workQueueRecord['TRACKINGENTRIES'] as $index => $oneTrack) {
                $wqTracking[$oneTrack['RECORDNO'] ?? 0] = $index;
            }
        }

        // now fix the tracking entries and assign to the work queue record as needed
        $fixMe = [];
        foreach ($trackingEntries as $index => $oneTrack) {
            // tracking records may not have the work queue key they need to attach themselves
            // to the passed work queue record.  Fix that now:
            if ( ! isset($oneTrack['WORKQUEUEKEY']) || ($oneTrack['WORKQUEUEKEY'] == 0)) {
                $trackingEntries[$index]['WORKQUEUEKEY'] = $workQueueRecordNumber;
                if ( ! isset($workQueueRecord['TRACKINGENTRIES'])) {
                    $workQueueRecord['TRACKINGENTRIES'] = [];
                }
                $workQueueRecord['FFINV_NEEDSUPDATE']   = true;

                $existingIndex = $wqTracking[$oneTrack['RECORDNO']] ?? -1;

                // at this moment, the tracking entries have been written to disk through the docentry record.
                // however, they have no work queue key.  And without one, the upsert mechanism in Entity Manager
                // will not be able to find the current records.  So, we must add this to the disk.
                if ($existingIndex >= 0) {
                    $workQueueRecord['TRACKINGENTRIES'][$existingIndex] = $trackingEntries[$index]; // update it
                } else {
                    $workQueueRecord['TRACKINGENTRIES'][] = $trackingEntries[$index];  // add to this work queue record
                }
                $fixMe[] = $oneTrack['RECORDNO'];
            }
            if ( ! $this->maybeUpdateWorkQueueFromTracking($workQueueRecord)) {
                return false;   // error already reported
            }
        }

        // bulk update
        if ( ! empty($fixMe)) {
            $qry   = [];
            $qry[] = "UPDATE docentrytrackdetail SET workqueuekey = :2 where cny# = :1  ";
            $qry[] = GetMyCompany();
            $qry[] = $workQueueRecordNumber;
            $qry   = PrepINClauseStmt($qry, $fixMe, ' and record# ');
            $ok    = $ok && ExecStmt($qry);
        }
        return $ok;
    }


    /**
     *  When you assign new tracking records to a work queue record, call this to update the work queue totals
     *
     * @param array         $workQueueRecord        One work queue record, perhaps with tracking
     *
     * @return bool
     *
     */
    private function maybeUpdateWorkQueueFromTracking(&$workQueueRecord)
    {
        // add numbers with rounding
        $add = function(&$left, $right) {
            $left = ibcadd($left, $right, ItemManager::AVERAGE_COST_DECIMALS, true);
        };

        $trackQuantity  = 0;
        $trackReserve   = 0;
        $trackPicked    = 0;
        $trackPacked    = 0;
        $trackingExists = false;

        if (isset($workQueueRecord['TRACKINGENTRIES'])) {
            foreach ($workQueueRecord['TRACKINGENTRIES'] as $oneTrack) {
                $trackingExists = true;
                $add($trackQuantity,  $oneTrack['TRACK_QUANTITY']    ?? 0);
                $add($trackReserve,   $oneTrack['QUANTITYRESERVED']  ?? 0);
                $add($trackPicked,    $oneTrack['QUANTITYALLOCATED'] ?? 0);
                $add($trackPacked,    $oneTrack['QUANTITYPACKED']    ?? 0);
            }
        }

        // maybe update the work queue record?
        // note the docentry line sets the quantity
        if ($trackingExists) {
            $updateRecord = false;
            // if ($workQueueRecord['QUANTITY'] != $trackQuantity) {
            //     $workQueueRecord['QUANTITY']  = $trackQuantity;
            //     $updateRecord                 = true;
            // }
            if ($workQueueRecord['QUANTITY'] < $trackQuantity) {
                Globals::$g->gErr->addIAError('INV-0135', __FILE__ . ':' . __LINE__,
                    'The tracking has changed, but the tracking is in Fulfillment and cannot be changed.',
                    [],
                    "Remove the new tracking and try again.",
                    []
                );
                return false;
            }
            // reserve at the line level can be more than at the tracking level
            if ($workQueueRecord['QUANTITYINRESERVE'] < $trackReserve) {
                $workQueueRecord['QUANTITYINRESERVE'] = $trackReserve;
                $updateRecord                         = true;
            }
            if ($workQueueRecord['QUANTITYPICKED'] != $trackPicked) {
                $workQueueRecord['QUANTITYPICKED']  = $trackPicked;
                $updateRecord                       = true;
            }
            if ($workQueueRecord['QUANTITYPACKED']  != $trackPacked) {
                $workQueueRecord['QUANTITYPACKED']   = $trackPacked;
                $updateRecord                        = true;
            }
            if ($updateRecord) {
                $workQueueRecord['FFINV_NEEDSUPDATE'] = true;   // caller does the actual save
            }
        }
        return true;
    }


    /**
     *      Get existing work queue records into the current document tree.
     *  This may be called when some records are NEW, and called AGAIN later.
     *
     * @param array             $documentTree       SODocument's document tree
     *
     * @return bool                                 did it work?
     *
     */
    private function getWorkQueueRecordsIntoExistingDocentrys(&$documentTree)
    {
        $getWarehouse = function($docEntry) {
            $wh     = $docEntry['WAREHOUSE']['LOCATION_NO'] ?? '';
            [ $wh ] = explode('--', $wh);
            return $wh;
        };


        $ok = true;

        // What records have work keys already?
        // Remember that here, some records may not even be saved and have no record#
        $workKeys = [];
        $trackingRecordIndexByRecordno = [];
        foreach ($documentTree['ENTRIES'] as $index => $docEntry) {
            // ignore docentry rows that don't participate in our goodness
            if ($docEntry['INVFF_NEEDS_WORKQUEUE']) {

                $documentTree['ENTRIES'][$index]['IWQS']          = [];
                $documentTree['ENTRIES'][$index]['IWQ_QUANTITY']  = 0;
                $documentTree['ENTRIES'][$index]['IWQ_OPEN']      = 0;    // not one yet
                $documentTree['ENTRIES'][$index]['IWQ_OPEN_QTY']  = 0;

                $totalTracked = 0;
                if (isset($docEntry['TRACKINGENTRIES'])) {
                    foreach ($docEntry['TRACKINGENTRIES'] as $trackIndex => $tracking) {
                        $quantity     = $tracking['QUANTITY'] ?? ($tracking['TRACK_QUANTITY'] ?? 0);
                        $totalTracked = ibcadd($totalTracked, $quantity, ItemManager::AVERAGE_COST_DECIMALS, true);
                        if (isset($tracking['RECORDNO'])) {
                            $trackingRecordIndexByRecordno[$index][$tracking['RECORDNO']] = $trackIndex;
                        }
                    }
                }
                $documentTree['ENTRIES'][$index]['FF_TRACKING_QUANTITY'] = $totalTracked; // might be zero

                // IS there a work key already, or is this new?
                if ($docEntry['WORKKEY'] ?? false) {
                    $workKeys[$docEntry['WORKKEY']] = $index; // work key was added already before here
                }
            }
        }

        // is this a new document?
        if ( ! isset($documentTree['RECORDNO'])) {
            return true;    // all we needed was the bookkeeping above
        }

        // Get any current work queue records and match them to the line items
        // note this fetches the tracking records as well, redundantly
        $result = $this->workQueueManager->getMany( $documentTree['RECORDNO'], InventoryWorkQueueManager::GET_MANY_DOCHDR);
        if ($result === false) {
            return false;
        }

        // now match, and add, the work queue records to the document tree
        $deleteMe = [];
        $updateMe = [];
        foreach ($result as $row) {
            InventoryWorkQueueManager::clearNote($row);
            $workKey = $row['WORKKEY'];
            $index   = $workKeys[$workKey] ?? -1;

            // found the match between work queue record and docentry
            if ($index >= 0) {
                $docEntry = $documentTree['ENTRIES'][$index];
                // Quantity might also be changing, so consider existing quantity if not a new line
                $existingEntry = $documentTree['EXISTING_ENTRIES'][$docEntry['RECORDNO']];
                $existingQuantity = empty($existingEntry) ? $docEntry['QUANTITY'] : $existingEntry['QUANTITY'];

                // did the item or warehouse change? (rare)
                if (($row['WAREHOUSEID'] !== $getWarehouse($docEntry)) ||
                    ($row['ITEMID']      !== $docEntry['ITEMID'])) {
                    if (($row['PLACE'] !== 'OPEN' || $row['QUANTITY'] != $existingQuantity)) {
                        // Some or all of this entry is already in process in Fulfillment; no can do.
                        Globals::$g->gErr->addIAError('INV-0629', __FILE__ . ':' . __LINE__,
                                                      sprintf('You have changed the item or warehouse for line %s, but the current
                        work in Fulfillment will not support this.', $row['LINENO']),
                                                      ['ROW_LINENO' => $row['LINENO']],
                                                      "Remove this line, add a new line with the new item or warehouse,
                        and try again.", []);

                        return false;
                    } else {
                        // This is ok, since the entry is entirely OPEN.
                        $row['ITEMID'] = $docEntry['ITEMID'];
                        $row['WAREHOUSEID'] = $getWarehouse($docEntry);
                        $updateMe[$row['RECORDNO']] = $row;
                    }
                }

                if ($row['UOM'] !== $docEntry['UNIT']) {
                    if ($row['PLACE'] != 'OPEN' || $row['QUANTITY'] != $existingQuantity) {
                        // This is not permitted.
                        Globals::$g->gErr->addIAError('INV-1445', __FILE__ . ':' . __LINE__, '',
                                                      ['ROW_LINENO' => $row['LINENO']]);

                        return false;
                    } else {
                        $row['UOM'] = $docEntry['UNIT'];
                        $row['UOMFACTOR'] = $docEntry['UNITFACTOR'];
                        $row['QUANTITY'] =
                            ibcmul($docEntry['UIQTY'], $row['UOMFACTOR'], ItemManager::DEFAULT_UOM_PRECISION, true);
                        $updateMe[$row['RECORDNO']] = $row;
                    }
                }

                // this is also rare, but maybe they inserted, moved around, or whatever...
                $newLineNo = $docEntry['LINE_NO'] + 1;
                if ($row['LINENO'] != $newLineNo) {
                    $tokens = [
                        [
                            'id' => 'IA.LINE_NUMBER_CHANGED_FROM_TO',
                            'placeHolders' => [
                                ['name' => 'LINE_NO', 'value' => $row['LINENO']],
                                ['name' => 'NEW_LINE_NO', 'value' => $newLineNo]
                            ]
                        ]
                    ];
                    $text_map = getLocalizedTextWithThrow($tokens);
                    $text = GT($text_map,'IA.LINE_NUMBER_CHANGED_FROM_TO');
                    InventoryWorkQueueManager::addNote($row, $text);
                    $row['LINENO'] = $newLineNo;
                    $updateMe[$row['RECORDNO']]    = $row;
                }

                // update and roll up tracking; did that change the totals?
                if (isset($row['TRACKINGENTRIES'])) {
                    // these may be newer than what is on disk.
                    foreach ($row['TRACKINGENTRIES'] as $trackIndex => $trackingRecord) {
                        if (isset($trackingRecord['RECORDNO'],
                                  $trackingRecordIndexByRecordno[$index][$trackingRecord['RECORDNO']])) {
                            $deTrackingIndex = $trackingRecordIndexByRecordno[$index][$trackingRecord['RECORDNO']];
                            $row['TRACKINGENTRIES'][$trackIndex] = $docEntry['TRACKINGENTRIES'][$deTrackingIndex];
                        }
                    }
                }
                if ( ! $this->maybeUpdateWorkQueueFromTracking($row)) {
                    return false;   // error already reported
                }
                if ($row['FFINV_NEEDSUPDATE']) {
                    unset($row['FFINV_NEEDSUPDATE']); // because it will be updated BEFORE the big save to EntityManager
                    $updateMe[$row['RECORDNO']]    = $row;
                }

                // save the row in the document tree
                $row['OLD_QUANTITYINRESERVE']    = $row['QUANTITYINRESERVE'] ?? 0; // so we can use it to compute the deltas
                $row['OLD_QUANTITYINALLOCATION'] = $row['QUANTITYINALLOCATION'] ?? 0;
                InventoryWorkQueueManager::clearNote($row);    // maybe we won't update the record, but if we do, we get a fresh note
                $documentTree['ENTRIES'][$index]['IWQS'][$row['RECORDNO']] = $row;
                if (($row['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN) ||
                    ($row['PLACE'] === InventoryWorkQueueManager::QUEUE_HIDDEN)) {
                    if ($docEntry['IWQ_OPEN_QTY'] < $row['QUANTITY']) {
                        $documentTree['ENTRIES'][$index]['IWQ_OPEN']     = $row['RECORDNO']; // biggest so far
                        $documentTree['ENTRIES'][$index]['IWQ_OPEN_QTY'] = $row['QUANTITY'];
                    }
                }

                $documentTree['ENTRIES'][$index]['IWQ_QUANTITY'] = ibcadd($docEntry['IWQ_QUANTITY'], $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);

            } else {
                // so we have a work key for this document that has
                // no docentry anymore.  Delete it!
                $tokens = [
                    [
                        'id' => 'IA.LINE_WAS_REMOVED',
                        'placeHolders' => [
                            ['name' => 'LINE_NO', 'value' => $row['LINENO']]
                        ]
                    ]
                ];
                $text_map = getLocalizedTextWithThrow($tokens);
                $text = GT($text_map,'IA.LINE_WAS_REMOVED');
                InventoryWorkQueueManager::addNote($row, $text);
                $updateMe[$row['RECORDNO']] = $row;
                $deleteMe[] = $row['RECORDNO'];  // it was there, but no more.
            }
        }

        // did we make changes?
        if (!empty($updateMe)) {
            $updateMe = array_values($updateMe);
            $ok = $ok && $this->workQueueManager->set($updateMe);
        }
        if (!empty($deleteMe)) {
            $ok = $ok && $this->workQueueManager->Delete($deleteMe);  // it was there, but no more.
        }
        return $ok;
    }


    /**
     *  CALLED BEFORE SAVE OF SODOCUMENT TREE
     *
     *      Verify the relevant fields for Fulfillment and/or Reserve/Allocate BEFORE we save the document.
     *  So, here, new rows in the document, or new rows in tracking, have no record#.
     *
     *  The reason to do these here is to save writing everything to SQL if there are errors.  Also, minor
     *  fixups can be done before the documententry lines or tracking lines are written (so we don't have
     *  to RE-write them).
     *
     *      Other verifications/modifications happen after write, because then everything has a record number,
     *  work queue records can be assigned/created, etc.
     *
     * @param array     $documentTree       The SODocumentManager document tree
     *
     * @return bool
     */
    private function verifyBeforeOESave(&$documentTree)
    {
        // ************ INTERNAL FUNCTIONS *****************

        // add numbers with rounding
        $add = function(&$left, $right) {
            $left = ibcadd($left, $right, ItemManager::AVERAGE_COST_DECIMALS, true);
        };

        // is the passed number zero or one?
        $zeroOrOne = function($n) {
            $n = $n + 0;    // force it to be numeric
            return ($n == 0) || ($n == 1); //flex compare to support float numbers
        };

        // is this tracking record OPEN or in a non-open state?
        $trackingIsOpen = function($docEntry, $trackRecord) {
            $rtn = true;
            if (isset($trackRecord['WORKQUEUEKEY'])) {
                $iwq = $docEntry['IWQS'][$trackRecord['WORKQUEUEKEY']];
                $rtn = ($iwq['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN) ||
                       ($iwq['PLACE'] === InventoryWorkQueueManager::QUEUE_HIDDEN);
            }
            return $rtn;
        };

        // Mark the original record as having been seen, so we can detect deleted rows
        $sawTrackRecord = function(&$docEntry, $trackRecord) {
            if (isset($trackRecord['WORKQUEUEKEY'])) {
                $docEntry['IWQS'][$trackRecord['WORKQUEUEKEY']]['TRACKINGENTRIES'][$trackRecord['RECORDNO']]['STILL_HERE'] = true;
            }
        };

        // are there any tracking records in non-open state that were there before but are now missing?
        $anyDeletedTrackingInFF = function($docEntry) {
            foreach ($docEntry['IWQS'] as $iwq) {
                $open = ($iwq['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN) ||
                        ($iwq['PLACE'] === InventoryWorkQueueManager::QUEUE_HIDDEN);

                if ( ! $open && isset($iwq['TRACKINGENTRIES'])) {
                    foreach ($iwq['TRACKINGENTRIES'] as $oneTrack) {
                        if ( ! isset($oneTrack['STILL_HERE'])) {
                             return true;
                        }
                    }
                }
            }
            return false;
        };

        // did the tracking record change?
        $trackingChanged = function($docEntry, $trackRecord) {
            if (isset($trackRecord['WORKQUEUEKEY'])) {
                $iwq = $docEntry['IWQS'][$trackRecord['WORKQUEUEKEY']];
                $old = $iwq['TRACKINGENTRIES'][$trackRecord['RECORDNO']];
                $fields = ['TRACK_QUANTITY', 'QUANTITYRESERVED', 'QUANTITYALLOCATED', 'SERIALNO', 'LOTNO', 'BINID', 'EXPIRATION' ];
                foreach ($fields as $field) {
                    $o = $old[$field]         ?? '';
                    $n = $trackRecord[$field] ?? '';
                    if ($o != $n) {
                        return true;    // this changed
                    }
                }
            }
            return false;
        };

        $hasWarehouse = function($docEntry) {
            $wh     = $docEntry['WAREHOUSEKEY'] ?? '';   // from disk it is here
            if ($wh == '') {
                $wh = $docEntry['WAREHOUSE']['LOCATION_NO'] ?? '';  // from the UI it is here
            }
            return ($wh != '');
        };

        // numbers come from the UI in '' format sometimes
        $cleanNumber = function(&$table, $field) {
            $n = $table[$field] ?? 0;
            if ((!is_numeric($n) && ($n == '')) || (is_numeric($n) && +$n === 0)) {
                $n = 0;
            }
            $table[$field] = $n;
        };


        // ********** MAIN ROUTINE ***********

        // ** NOTE: You can alter docentry or docentrytrackdetail records here because they have not yet been written.
        //      But you CANNOT change the Work Queue records (['IWQS']) here because that can mess up tracking and other
        //      things (they SHARE tracking records with docentry!).  Alter them POST writing the SODocument to disk

        $errorCount = 0;
        $maxErrors  = 5;   // don't let the error list get TOO long
        $ok         = true;

        foreach ($documentTree['ENTRIES'] as $index => $docEntry) {

            // ignore docentry rows that don't participate in our goodness
            if ($docEntry['INVFF_NEEDS_WORKQUEUE'] && ($errorCount < $maxErrors)) {

                $lineNo                 = $docEntry['LINE_NO'] + 1;
                $itemID                 = $docEntry['ITEMID'];
                $tracking               = self::getTrackedStatusOfItems( [ $itemID ] );  // should be IN the cache
                $newPicked              = $docEntry['QUANTITYALLOCATED'] ?? 0;
                $newReserved            = $docEntry['QUANTITYRESERVED']  ?? 0;
                $quantity               = $docEntry['QUANTITY'];

                // Does it have a warehouse?
                if ($hasWarehouse($docEntry) === false) {
                    Globals::$g->gErr->addIAError('INV-0630', __FILE__ . ':' . __LINE__,
                    sprintf("The row must have a warehouse, on line %1s.", $lineNo),
                    ['LINE_NO'=>$lineNo],
                    "Select a warehouse  Then, try again.",[]);
                    return false;
                }

                // DON'T ALLOW NEGATIVE NUMBERS
                if ( ($newPicked < 0) || ($newReserved < 0) || ($quantity < 0)) {
                    Globals::$g->gErr->addIAError('INV-0631', __FILE__ . ':' . __LINE__,
                    sprintf("The quantity fields on line %1s cannot be negative.", $lineNo),
                    ['LINE_NO'=>$lineNo],
                    "Set the quantities to 0 or greater.  Then, try again.",[]);
                    return false;
                }

                // these are the latest entries from the SODocument
                // they may or may NOT have a workkey record and corresponding InventoryWorkQueue record,
                $trackQuantity  = 0;
                $trackReserve   = 0;
                $trackAllocated = 0;
                $itemTracked    = $tracking[$itemID]['TRACKED'] ?? false;
                $itemSN         = $itemTracked && $tracking[$itemID]['SN'];

                if (isset($docEntry['TRACKINGENTRIES']) && ! empty($docEntry['TRACKINGENTRIES'])) {

                    // Wait, is the item even tracked?
                    if ($itemTracked === false) {
                        Globals::$g->gErr->addIAError('INV-0632', __FILE__ . ':' . __LINE__,
                        sprintf("Tracking information was entered for the item on line %1s,
                        which is a non-tracked item.", $lineNo),['LINE_NO'=>$lineNo],
                        "Remove the tracking information. Then, try again.",[]);
                        $ok = false;
                        break;
                    }

                    // is there enough quantity for these?
                    $ok = $this->resolveTrackingData($docEntry);
                    if ( ! $ok) {
                        break;
                    }

                    // For each track record, see if it is ok and roll up the values.....
                    foreach ($docEntry['TRACKINGENTRIES'] as $trackIndex => $oneTrack) {

                        if ($errorCount >= $maxErrors) {
                            break;   // don't flood the UI with errors
                        }

                        // Coming from the UI, these may be '' which doesn't let you add to anything (PhP 8.1)
                        $cleanNumber( $oneTrack, 'TRACK_QUANTITY');
                        $cleanNumber( $oneTrack, 'QUANTITYRESERVED');
                        $cleanNumber( $oneTrack, 'QUANTITYALLOCATED');
                        $cleanNumber( $oneTrack, 'QUANTITYPACKED');

                        // mark this one as having been seen so we can see if any have been deleted later
                        $sawTrackRecord($docEntry, $oneTrack);

                        $entryQuantity = ($oneTrack['TRACK_QUANTITY']    ?? 0) + 0; // turn into a real number, not a string number
                        $entryReserve  = ($oneTrack['QUANTITYRESERVED']  ?? 0) + 0;
                        $entryAllocate = max(($oneTrack['QUANTITYALLOCATED'] ?? 0), ($oneTrack['QUANTITYPACKED'] ?? 0)) + 0;

                        if ( ($entryAllocate < 0) || ($entryReserve < 0) || ($entryQuantity < 0)) {
                            Globals::$g->gErr->addIAError('INV-0633', __FILE__ . ':' . __LINE__,
                            sprintf("For the item on line %1s, the value of the quantity fields for
                            the rows in the tracking table cannot be negative.", $lineNo),
                            ['LINE_NO'=>$lineNo],
                            "Set the quantities to 0 or greater. Then, try again.",[]);
                            $ok = false;
                            $errorCount++;
                            continue;
                        }

                        if ( ($entryAllocate + $entryReserve) > $entryQuantity) {
                            Globals::$g->gErr->addIAError('INV-0634', __FILE__ . ':' . __LINE__,
                                sprintf("For the item on line %1s, the sum of the quantity reserved and
                                quantity picked (allocated) for each row in the tracking table must be
                                equal to or less than the quantity to fulfill.", $lineNo),
                                ['LINE_NO'=>$lineNo],
                                "Set the quantities for each tracking row so that the sum of quantity
                                reserved and quantity picked does not exceed the quantity to fulfill.
                                Then, try again.",[]);
                            $ok = false;
                            $errorCount++;
                            continue;
                        }

                        // if we're IN FF, you cannot change reserved and allocated
                        $isOpen        = (($oneTrack['QUANTITYPACKED'] ?? 0) == 0) && $trackingIsOpen($docEntry, $oneTrack);
                        if (! $isOpen) {
                            if ($trackingChanged($docEntry, $oneTrack)) {
                                $trackindexplusone = ($trackIndex + 1);
                                Globals::$g->gErr->addIAError(
                                    'INV-0635', __FILE__ . ':' . __LINE__,
                                    sprintf('For the item on line %1s, row %2s in the tracking table is
                                    currently in fulfillment and cannot be changed.',$lineNo, $trackindexplusone),
                                    ['LINE_NO'=>$lineNo,'TRACK_INDEX_PLUS_1'=>$trackindexplusone],
                                    "Restore the tracking row with its original values. Then,try again.",[]
                                );
                                $ok = false;
                                $errorCount++;
                                continue;
                            }
                        }

                        // let's verify this is a well-formed track row:
                        if ( ($entryAllocate != 0) || ($entryReserve != 0) ) {
                            $trackingKey = ($oneTrack['SERIALNO'] ?? '') . ($oneTrack['LOTNO'] ?? '') . ($oneTrack['BINKEY'] ?? ($oneTrack['BINID'] ?? '')) . ($oneTrack['EXPIRATION'] ?? '') . ($oneTrack['EXPIRATIONDATE'] ?? '');
                            if ($trackingKey == '') {
                                $trackindexplusone = ($trackIndex + 1);
                                Globals::$g->gErr->addIAError(
                                    'INV-0636', __FILE__ . ':' . __LINE__,
                                    sprintf("For the item on line %1s, row %2s in the tracking table is
                                    missing tracking details, such as serial number, lot number, expiration
                                    date, or bin.",$lineNo, $trackindexplusone),
                                    ['LINE_NO'=>$lineNo,'TRACK_INDEX_PLUS_1'=>$trackindexplusone],
                                    "Either enter the tracking details for the row or set the tracked
                                    reserved or picked quantities to 0. Then, try again.",[]
                                );
                                $ok = false;
                                $errorCount++;
                                continue;
                            }
                        }

                        $add($trackQuantity,  $entryQuantity);
                        $add($trackReserve,   $entryReserve);
                        $add($trackAllocated, $entryAllocate);
                        if (($trackQuantity > $quantity) ||
                            (($trackReserve + $trackAllocated) > $quantity)) {
                            Globals::$g->gErr->addIAError('INV-0645', __FILE__ . ':' . __LINE__,
                                sprintf('For the item on line %1s, the total of the reserved and
                                picked quantities entered in the tracking table exceeds the quantity on
                                the line.', $lineNo),['LINE_NO'=>$lineNo],
                                "Decrease the tracked quantities or increase the line quantity.
                                Then, try again.",[]);
                            $ok = false;
                            $errorCount++;
                            continue;
                        }

                        // if this is a serial number, make sure the numbers are 0 or 1
                        if ($itemSN) {
                            if ( ! ($zeroOrOne($entryQuantity) &&
                                    $zeroOrOne($entryReserve) &&
                                    $zeroOrOne($entryAllocate) &&
                                    $zeroOrOne($entryReserve + $entryAllocate))) {

                                Globals::$g->gErr->addIAError('INV-0644', __FILE__ . ':' . __LINE__,
                                    sprintf('The item on line %1s is tracked by serial number.
                                    The sum of the reserved and picked quantity that is entered for each
                                    row in the tracking table must be 0 or 1.', $lineNo),
                                    ['LINE_NO'=>$lineNo],
                                    "Change the tracked quantities. Then, try again.",[]);
                                $ok = false;
                                $errorCount++;
                                continue;
                            }
                        }
                    }

                    // tracking reserve can be less than, but not more than, line reserved
                    // if we can, just bump up the reserved
                    if ($newReserved < $trackReserve) {
                        $newReserved = $trackReserve;   // so we can check this below
                        $documentTree['ENTRIES'][$index]['QUANTITYRESERVED'] = $trackReserve;
                    }

                    // tracking allocated must match line allocated or line allocated can be zero
                    if ($newPicked != $trackAllocated) {
                        if ($newPicked === 0) {
                            $newPicked = $trackAllocated;   // so we can check this below
                            $documentTree['ENTRIES'][$index]['QUANTITYALLOCATED'] = $trackAllocated;    // give 'em benefit of the doubt
                        } else {
                            Globals::$g->gErr->addIAError('INV-0643', __FILE__ . ':' . __LINE__,
                                sprintf("For the item on line %1s, the quantity picked needs to equal
                                the total quantity picked that is specified in the tracking table.",
                                $lineNo),['LINE_NO'=>$lineNo],
                                "Change the quantities so that they match. Then, try again.",[]);
                            $ok = false;
                            $errorCount++;
                        }
                    }

                    if ($anyDeletedTrackingInFF($docEntry)) {
                        Globals::$g->gErr->addIAError('INV-0642', __FILE__ . ':' . __LINE__,
                            sprintf("For the item on line %1s, one or more rows in the tracking
                            table were deleted. The tracking information is in fulfillment and cannot
                            be changed.", $lineNo),['LINE_NO'=>$lineNo],
                            "Cancel the changes to the transaction.",[]);
                        $ok = false;
                        $errorCount++;
                   }
                } else if ($itemTracked) {
                    if ($newPicked != 0) {
                        Globals::$g->gErr->addIAError('INV-0641', __FILE__ . ':' . __LINE__,
                            sprintf("A value of %1s was entered for the quantity picked (allocated)
                            on line %2s, but no tracking information was entered.",
                            $newPicked, $lineNo),['NEW_PICKED'=>$newPicked,'LINE_NO'=>$lineNo],
                            "Either set the quantity picked (allocated) to 0 or enter tracking
                            information. Then, try again.",[]);
                        $ok = false;
                        $errorCount++;
                    }
                }

                // CAN'T HAVE TOO MANY
                // (and these may have been updated from the tracking records)
                if (($newPicked + $newReserved) > $quantity) {
                    Globals::$g->gErr->addIAError('INV-0683', __FILE__ . ':' . __LINE__,
                        sprintf("For the item on line %1s, the sum of the quantity reserved
                        and quantity picked (allocated) for each row in the tracking table must be
                        equal to or less than the quantity to fulfill.", $lineNo),['LINE_NO'=>$lineNo],
                        "Set the quantities for each tracking row so that the sum of quantity
                        reserved and quantity picked does not exceed the quantity to fulfill. Then,
                         try again.",[]);
                    return false;
                }

                // Check stuff specific to the work queue records
                // This is separate because it can be called AFTER writing the document too
                $ok = $ok && $this->checkWorkQueueRecordsForDocument( $documentTree, $docEntry);
            }
        }
        return $ok;
    }


    /**
     *  CALLED BEFORE DOCUMENT SAVE, AND DOES NOT CHANGE ANY RECORDS (so can be called anytime)
     *
     * Let's make sure the work queue records, if any, can handle the changes to the document entry record.
     * The actual changes happen AFTER document save, in maybeUpdateWorkQueueForDocument(), below.
     *
     * @param   array   $documentTree   the whole SODocument tree
     * @param   array   $docEntry       One line item from the SODocumentManager's doument tree
     *
     * @return bool
     */
    private function checkWorkQueueRecordsForDocument($documentTree, &$docEntry)
    {
        // add numbers with rounding
        $add = function(&$left, $right) {
            $left = ibcadd($left, $right, ItemManager::AVERAGE_COST_DECIMALS, true);
        };


        $noWorkQueues = empty($docEntry['IWQS']);

        // For new records, not yet saved, there are no work queue records
        if ($noWorkQueues) {
            return true;
        }

        $lineNo             = $docEntry['LINENO'] + 1;
        $openRecordNumber   = $docEntry['IWQ_OPEN'] ?? 0;  // is there at least one open record?
        $quantity           = $docEntry['QUANTITY'] ?? 0;
        $countInWQ          = iround($docEntry['IWQ_QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS); // must be there - set above
        $countInDE          = iround($quantity, ItemManager::AVERAGE_COST_DECIMALS);
        $deltaQuantity      = ($countInDE - $countInWQ);
        // if an existing open, add delta to the open quantity.
        // otherwise we'll create a NEW record with the given quantity
        $openIwq            = (($openRecordNumber) ? $docEntry['IWQS'][$openRecordNumber] : null);
        $avaiableQuantity   = (($openIwq) ? ($openIwq['QUANTITY'] + $deltaQuantity) : $deltaQuantity);

        // does the existing open record have tracking already?  How much does IT need?
        $trackedQuantity = 0;
        $trackedReserve  = 0;
        $trackedPicked   = 0;
        $trackingRecords = [];

        if ($openIwq && isset($openIwq['TRACKINGENTRIES']) && ! empty($openIwq['TRACKINGENTRIES'])) {

            // what is now in the line item?
            foreach ($docEntry['TRACKINGENTRIES'] as $deIndex => $deTracking) {
                if (isset($deTracking['RECORDNO'])) {
                    $trackingRecords[$deTracking['RECORDNO']] = $deIndex;
                }
            }

            // was a trcking row removed?  If not, roll up the [new] tracked amounts in the OPEN entry
            foreach ($openIwq['TRACKINGENTRIES'] as $openTracking) {
                if (isset($trackingRecords[$openTracking['RECORDNO']])) {
                    $deRecIndex        = $trackingRecords[$openTracking['RECORDNO']];
                    $newestTrackingRec = $docEntry['TRACKINGENTRIES'][$deRecIndex]; // the one from the de may be fresher
                    $add($trackedQuantity, $newestTrackingRec['QUANTITY']);
                    $add($trackedReserve,  $newestTrackingRec['QUANTITYRESERVED']);
                    $add($trackedPicked,   $newestTrackingRec['QUANTITYPICKED']);
                }
            }
        }

        // lower the 'available' OPEN quantity by what the tracking needs....
        // $avaiableQuantity -= $trackedQuantity;

        // Maybe they lowered the quantity in the docentry.  And there are already records out there in Fulfillment.
        // We have the 'open record' (maybe); does that have enough room in it to lower the quantity?
        if ($avaiableQuantity < $trackedQuantity) {
            Globals::$g->gErr->addIAError('INV-0640', __FILE__ . ':' . __LINE__,
                sprintf('On line %1s, the quantity ordered cannot be decreased because the order is
                 not in an Open status in fulfillment.', $lineNo),
                 ['LINE_NO'=>$lineNo],
                "Either restore the quantity of the line to its original value or, in fulfillment,
                move the line to Open status. Then, try again.",[]);
            return false;
        }

        // was there a change in reserve/allocate?  Can we accomidate it?
        $oldPicked              = 0;
        $oldReserved            = 0;
        if (isset($docEntry['IWQS'])) {
            foreach ($docEntry['IWQS'] as $iwq) {
                $add($oldPicked,   $iwq['QUANTITYPICKED']);   // don't worry about packed?
                $add($oldReserved, $iwq['QUANTITYINRESERVE']);
            }
        }

        $newPicked              = $docEntry['QUANTITYALLOCATED'] ?? 0;
        $newReserved            = $docEntry['QUANTITYRESERVED']  ?? 0;
        $deltaReserve           = $newReserved - $oldReserved;
        $deltaPicked            = $newPicked   - $oldPicked;

        // if there was a change, it MUST happen in the OPEN record, if one
        // Note: maybe we will create a new OPEN record and it could fit there
        if ($deltaReserve || $deltaPicked) {

            if ($openRecordNumber == 0) {
                Globals::$g->gErr->addIAError(
                    'INV-0639', __FILE__ . ':' . __LINE__,
                    sprintf("On line %1s, the quantity reserved or quantity picked cannot be changed
                    because the order is not in an Open status in fulfillment.", $lineNo),
                    ['LINE_NO'=>$lineNo],
                    "Restore the quantity reserved or quantity picked to its original value.Then, try again.",[]
                );
                return false;
            }

            $openQuantity  = $avaiableQuantity; // MAY BE ZERO OR NEGATIVE
            // these are the quantities available to be lowered
            $openReserved  = ($openIwq['QUANTITYINRESERVE'] ?? 0);
            $openAllocated = ($openIwq['QUANTITYPICKED']    ?? 0);
            $fits          = true;

            // can we lower it enough?
            if ((($deltaPicked  < 0) && ( ( - $deltaPicked)  > $openAllocated)) ||
                (($deltaReserve < 0) && ( ( - $deltaReserve) > $openReserved))) {
                $fits = false;
            }

            // can we raise it enough?
            // I believe that at this point the allocate and reserve
            if ((($deltaPicked  > 0) && ( $deltaPicked  > $openQuantity)) ||
                (($deltaReserve > 0) && ( $deltaReserve > $openQuantity))) {
                $fits = false;
            }

            if (($openReserved + $deltaReserve) + ($openAllocated + $deltaPicked) > $openQuantity) {
                $fits = false;
            }

            if ( ! $fits) {
                Globals::$g->gErr->addIAError(
                    'INV-0684', __FILE__ . ':' . __LINE__,
                    sprintf("On line %1s, the quantity reserved or quantity picked cannot be changed
                    because the order is not in an Open status in fulfillment.", $lineNo),
                    ['LINE_NO'=>$lineNo],
                    "Restore the quantity reserved or quantity picked to its original value.Then, try again.",[]
                );
                return false;
            }
        }
        return true;
    }


    /**
     *  CALLED AFTER DOCUMENT SAVE
     *
     *  In the document tree, some work queue records may need updating or adding to accomidate
     *  changes to the docentry lines.  Do this AFTER we save the document and its tracking,
     *  and after fetching the work queue records with the right tracking attached.....
     *
     * @param   array   $documentTree   SODocumentManager's doument tree
     *
     * @return bool                     did it work?
     */
    private function maybeUpdateWorkQueueForDocument(&$documentTree)
    {
        // add numbers with rounding
        $add = function(&$left, $right) {
            $left = ibcadd($left, $right, ItemManager::AVERAGE_COST_DECIMALS, true);
        };

        $ok  = true;

        foreach ($documentTree['ENTRIES'] as $index => $docEntry) {

            if ($docEntry['INVFF_NEEDS_WORKQUEUE']) {

                // Repeat the check we made before saving the document, in case the OPEN record changed
                $ok = $ok && $this->checkWorkQueueRecordsForDocument($documentTree, $docEntry);
                if ( ! $ok) {
                    return $ok;
                }

                $openRecordNumber   = $docEntry['IWQ_OPEN'] ?? 0;  // is there at least one open record?
                $openIwq            = (($openRecordNumber) ? $docEntry['IWQS'][$openRecordNumber] : null);

                // Were any tracking records deleted?
                // Rollup the tracking if any
                if ($openIwq && isset($openIwq['TRACKINGENTRIES']) && ! empty($openIwq['TRACKINGENTRIES'])) {

                    $trackedQuantity = 0;
                    $trackedReserve  = 0;
                    $trackedPicked   = 0;

                    // what is now in the line item?
                    foreach ($docEntry['TRACKINGENTRIES'] as $deTracking) {
                        if (isset($deTracking['RECORDNO'])) {
                            $trackingRecords[$deTracking['RECORDNO']] = true;
                        }
                    }

                    // was a trcking row removed?
                    foreach ($openIwq['TRACKINGENTRIES'] as $trackIndex => $openTracking) {
                        if (isset($trackingRecords[$openTracking['RECORDNO']])) {
                            $add($trackedQuantity, $openTracking['QUANTITY']);
                            $add($trackedReserve,  $openTracking['QUANTITYRESERVED']);
                            $add($trackedPicked,   $openTracking['QUANTITYPICKED']);
                        } else {
                            unset($openIwq['TRACKINGENTRIES'][$trackIndex]);
                            $openIwq['FFINV_NEEDSUPDATE']    = true;
                        }
                    }
                }


                // Note about work queue quantity vs line quantity:
                //  If the line quantity went UP,
                //      If there was an OPEN record,
                //          we did not change the quantity, and need to here.
                //      Otherwise there was NO OPEN record, so we ADDED a new work queue record already
                //          so the delta should be zero.
                //  If the line quantity went DOWN,
                //      There had to have been an OPEN record with enough quantity to support that,
                //          and here we need to lower the quantity of that record.


                $lineNo             = $docEntry['LINENO'] + 1;
                $quantity           = $docEntry['QUANTITY'] ?? 0;
                $countInWQ          = iround($docEntry['IWQ_QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS); // must be there - set above
                $countInDE          = iround($quantity, ItemManager::AVERAGE_COST_DECIMALS);
                $deltaQuantity      = ($countInDE - $countInWQ);
                $openQuantity       = (($openIwq) ? $openIwq['QUANTITY'] : 0);


                // line quantity changed upward or downward
                // (remember the note above: if the quantity went UP and we added a new work queue record for it,
                //      the delta here will be zero)
                if ($deltaQuantity != 0) {
                    // Note the delta could be negative!
                    $openQuantity = ibcadd($openQuantity, $deltaQuantity, ItemManager::AVERAGE_COST_DECIMALS, true); // qty may go DOWN, to ZERO!
                    // trust, but verify: (these aren't user errors but code bugs, so we don't expect them)
                    if (($openIwq === null) || ($openQuantity < 0)) {
                        throw new Exception("[Code bug]Not enough quantity in OPEN work queue for line $lineNo.");
                    }
                    $tokens = [
                        [
                            'id' => 'IA.LINE_QUANTITY_CHANGED_BY',
                            'placeHolders' => [
                                ['name' => 'QTY', 'value' => $deltaQuantity]
                            ]
                        ]
                    ];
                    $text_map = getLocalizedTextWithThrow($tokens);
                    $text = GT($text_map,'IA.LINE_QUANTITY_CHANGED_BY');
                    InventoryWorkQueueManager::addNote(  $openIwq, $text);
                    $openIwq['QUANTITY']             = $openQuantity;
                    $openIwq['FFINV_NEEDSUPDATE']    = true;
                }


                // handle case where reserve/allocate changed on the line; apply it to the open record....
                // no old record? then the open record was just created with the right amounts reserved/allocated
                $oldPicked              = 0;
                $oldReserved            = 0;
                if (isset($docEntry['IWQS'])) {
                    foreach ($docEntry['IWQS'] as $iwq) {
                        $add($oldPicked,   $iwq['QUANTITYPICKED']);   // don't worry about packed?
                        $add($oldReserved, $iwq['QUANTITYINRESERVE']);
                    }
                }

                $newPicked      = $docEntry['QUANTITYALLOCATED'] ?? 0;
                $newReserved    = $docEntry['QUANTITYRESERVED'] ?? 0;
                $deltaReserve   = $newReserved - $oldReserved;
                $deltaPicked    = $newPicked   - $oldPicked;

                // if there was a change, it MUST happen in the OPEN record
                if ($deltaReserve || $deltaPicked) {

                    // we checked that there must be an open record above!  What gives???
                    if ($openIwq === NULL) {
                        throw new Exception("[Code bug]No open work queue for line $lineNo.");
                    }

                    $openReserved  = $openIwq['QUANTITYINRESERVE'] ?? 0;
                    $openAllocated = $openIwq['QUANTITYPICKED']    ?? 0;   // I don't think we want PACKED here....

                    if ($deltaPicked != 0) {
                        // Note the delta could be negative!
                        $openAllocated = ibcadd($openAllocated, $deltaPicked, ItemManager::AVERAGE_COST_DECIMALS, true); // qty may go DOWN, to ZERO!
                        // trust, but verify: (these aren't user errors but code bugs, so we don't expect them)
                        if ($openAllocated < 0) {
                            Globals::$g->gErr->addIAError('INV-0638', __FILE__ . ':' . __LINE__,
                                sprintf("On line %1s, the quantity picked cannot be changed because the
                                order is not in an Open status in fulfillment.", $lineNo),
                                ['LINE_NO'=>$lineNo],
                                "Restore the quantity picked to its original value. Then, try again.",[]);
                            return false;
                        }
                        $openIwq['QUANTITYPICKED'] = $openAllocated;
                        $openIwq['FFINV_NEEDSUPDATE'] = true;
                    }

                    if ($deltaReserve != 0) {
                        // Note the delta could be negative!
                        $openReserved = ibcadd($openReserved, $deltaReserve, ItemManager::AVERAGE_COST_DECIMALS, true); // qty may go DOWN, to ZERO!
                        // trust, but verify: (these aren't user errors but code bugs, so we don't expect them)
                        if ($openReserved < 0) {
                            Globals::$g->gErr->addIAError('INV-0637', __FILE__ . ':' . __LINE__,
                            sprintf("On line %1s, the quantity reserved cannot be changed because
                            the order is not in an Open status in fulfillment.", $lineNo), ['LINE_NO' => $lineNo],
                            "Restore the quantity reserved to its original value. Then, try again.",[]);
                            return false;
                        }
                        $openIwq['QUANTITYINRESERVE'] = $openReserved;
                        $openIwq['FFINV_NEEDSUPDATE'] = true;
                    }
                }
                if ($openIwq) {
                    // just in case we changed it, put it back
                    $documentTree['ENTRIES'][$index]['IWQS'][$openRecordNumber] = $openIwq;
                }
            }
        }
        return $ok;
    }


    /**
     *  The passed docentry has tracking records, and they have been annotated with the relevant work queue records.
     *  Here, we see if the numbers add up ok, and, if they do, do we need to update the work queue records or not?
     *
     *
     * @param array     $docEntry           One document entry line
     *
     * @return bool                         All ok?
     */
    private function addUpTrackingReserveAllocated( & $docEntry)
    {
        // Here, all the numbers added up.  Yay!  Do we need to update the work queue records?
        $totalAllocated = 0;
        $totalReserved = 0;
        foreach ($docEntry['IWQS'] as $iwqIndex => $iwq) {
            $place         = $iwq['PLACE'];
            $isOpen        = ($place === InventoryWorkQueueManager::QUEUE_OPEN) || ($place === InventoryWorkQueueManager::QUEUE_HIDDEN);
            $nowAllocated  = max($iwq['QUANTITYPICKED'], $iwq['QUANTITYPACKED']);
            $deltaAllocted = $nowAllocated - $iwq['OLD_QUANTITYINALLOCATION'];
            $nowReserved   = (($isOpen) ? $iwq['QUANTITYINRESERVE'] : ($iwq['QUANTITY'] - $nowAllocated));
            $deltaReserved = $nowReserved - $iwq['OLD_QUANTITYINRESERVE'];

            if ($deltaAllocted || $deltaReserved) {
                $docEntry['IWQS'][$iwqIndex]['QUANTITYINRESERVE']    = $nowReserved;
                $docEntry['IWQS'][$iwqIndex]['QUANTITYINALLOCATION'] = $nowAllocated;
                $docEntry['IWQS'][$iwqIndex]['FFINV_NEEDSUPDATE']    = true;
            }

            $totalAllocated         = ibcadd($totalAllocated, $nowAllocated, ItemManager::AVERAGE_COST_DECIMALS, true );
            $totalReserved          = ibcadd($totalReserved,  $nowReserved, ItemManager::AVERAGE_COST_DECIMALS, true );

            // no deltas for non-inventory items
            $itemID                 = $docEntry['ITEMID'];
            $canRunOut              = ($trackingNeededByItemId[ $itemID ]['CANRUNOUT'] ?? true);               // non-inventory item?
            if ( ! $canRunOut) {
                $deltaReserved = 0;
                $deltaAllocted = 0;
            }
            $docEntry['IWQS'][$iwqIndex]['DELTARESERVE']            = $deltaReserved;
            $docEntry['IWQS'][$iwqIndex]['DELTAALLOCATION']         = $deltaAllocted;

            $docEntry['IWQS'][$iwqIndex]['FFINV_NEEDSUPDATE']       =
                ($docEntry['IWQS'][$iwqIndex]['FFINV_NEEDSUPDATE'] ?? false) || ($deltaReserved || $deltaAllocted);
        }
        return true;
    }

}
