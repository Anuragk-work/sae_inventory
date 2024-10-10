<?php

/**
 * Class InventoryWQOrderManager - Inventory Work Queue 'orders' view of data.
 *
 *  The idea is: we have dochdr records, docentry records, and InventoryWorkQueue records, and we want to
 *      have UI/API queries of summary information from each of those.
 *
 * Normally, you'd need a sql table that describes all this so that the 'filter framework', picklist sorting/searching,
 * and other functionality would work.
 *
 * Here, we're limited to view-only, plus some VERY LIMITED writes, mostly "commands" ("Create pick list").
 *
 * Roger Collins, April 2021
 *
 */
class InventoryWQOrderManager extends EntityManager
{
    const       GET_CACHE_SIZE              = 100;  // we cache up to 100 'get()' at a time; not too much ram/burden...

    const       FEATURE_FLAG_ONLY           = 0;    // just check the feature flag
    const       FEATURE_FLAG_FF             = 1;    // feature flag + Fulfilment
    const       FEATURE_FLAG_RA             = 2;    // feature flag + Reserve/Allocate
    const       FEATURE_FLAG_EITHER         = 3;    // feature flag + Reserve/Allocate OR Fulfilment
    const       FEATURE_FLAG_BOTH           = 4;    // feature flag + Reserve/Allocate AND Fulfilment


    /** @var InventoryWorkQueueManager  $workQueueManager The InventoryWorkQueueManager  */
    private           $workQueueManager   = null;       // holds the InventoryWorkQueueManager

    /** @var array    $getCache */
    private           $getCache           = null;       // up to GET_CACHE_SIZE get() requests.


    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);

        $this->workQueueManager   = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");
    }


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  Internal Utilities
    //
    //  **********************************************************************************
    //  **********************************************************************************



    /**
     *      Are the special ship-dates enabled in inventory setup?
     *
     * @return bool
     */
    public static function areShipDatesEnabled()
    {
        static $shipDatesEnabled = null;
        if ($shipDatesEnabled === null) {
            global $kINVid;
            $shipDatesEnabled = (GetPreferenceForProperty($kINVid, 'ENABLESHIPPINGDATES') === 'T') ? true : false;
        }
        return $shipDatesEnabled;
    }




    /**
     *      is this feature enabled?
     *
     *  These are the possible flags:
     *      FEATURE_FLAG_ONLY           check the feature flag only
     *      FEATURE_FLAG_FF             feature flag + fulfillment (requires a document tree)
     *      FEATURE_FLAG_RA             feature flag + reserve/allocate (requires a document tree)
     *      FEATURE_FLAG_EITHER         feature flag + either of the above (requires a document tree for R/A)
     *      FEATURE_FLAG_BOTH           feature flag + both of the above (requires a document tree)
     *
     * @param   bool    $whichFlagToCheck   which flag to check
     * @param   array   $documentTree       a SODocumentManager document tree
     *
     * @return bool
     */
    public static function featureEnabled($whichFlagToCheck = self::FEATURE_FLAG_EITHER, $documentTree = [])
    {
        //Check the ENABLE_FULFILLMENT_FEATURE flag first and returns that if caller only want that
        static $ffFeatureEnabled = null;     // cache because this can be called MANY TIMES by the search framework
        if ($ffFeatureEnabled === null) {
            $ffFeatureEnabled = FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_FULFILLMENT_FEATURE')
                                && (BinManager::areClassicBinsOn() === false);
        }

        if (($whichFlagToCheck === self::FEATURE_FLAG_ONLY) || !$ffFeatureEnabled) {
            return $ffFeatureEnabled;
        }

        $emptyTree = empty($documentTree);
        if ($emptyTree && ($whichFlagToCheck !== self::FEATURE_FLAG_FF)) {
            throw new Exception("[Code bug] no document for feature flag check.");
        }

        //Check the fullfillment pref flag also since this is what the user want
        static $ffEnabled = null;
        if ($ffEnabled === null) {
            global $kINVid;
            GetModulePreferences($kINVid, $prefs);
            $ffEnabled = ($prefs['ENABLEFULFILLMENT']  === 'T');
        }
        $reserveAllocateEnabled = (($documentTree['_DOCPAR']['ENABLEALLOCRESERVE'] ?? 'false') === 'true') ||
                                  (($documentTree['_DOCPAR']['ENABLEALLOCRESERVE'] ?? 'F')     === 'T');

        // maybe it would be worth yet more flags?
        //  For now not supplying a document means just the inventory config flag.
        $enableFulfillmentFlag  = $ffEnabled;
        if ($enableFulfillmentFlag && ( ! $emptyTree)) {
            $enableFulfillmentFlag  = (($documentTree['_DOCPAR']['ENABLEFULFILLMENT']  ?? 'false') === 'true') ||
                                      (($documentTree['_DOCPAR']['ENABLEFULFILLMENT']  ?? 'F')     === 'T');
        }

        switch ($whichFlagToCheck) {
            case self::FEATURE_FLAG_ONLY:   // already checked above, but...
                $rtn = $ffFeatureEnabled;
                break;

            case self::FEATURE_FLAG_FF:
                $rtn = $enableFulfillmentFlag;
                break;

            case self::FEATURE_FLAG_RA:
                $rtn = $reserveAllocateEnabled;
                break;

            case self::FEATURE_FLAG_EITHER:
                $rtn = $enableFulfillmentFlag || $reserveAllocateEnabled;
                break;

            case self::FEATURE_FLAG_BOTH:
                $rtn = $enableFulfillmentFlag && $reserveAllocateEnabled;
                break;

            default:
                throw new Exception("[Code bug] bad flag passed to featureEnabled(): $whichFlagToCheck");
        }
        return $rtn;
    }


    /**
     *      Given an employee name, return the employee recordnumber (key).
     *  We expect many of these to be null, empty, or the same as one recently fetched....
     *
     * @param   string  $employeeID     The employee ID
     *
     * @return  int                     The Key/record#
     */
    protected function getEmployeeKey($employeeID)
    {
        static $employeePick = [];        // small cache

        $employeeID = trim($employeeID ?? '');
        if ($employeeID == '') {
            return 0;   // nothing to look up
        }
        list($employeeID)      = explode("--", $employeeID);    // get just the id, not the name
        if ( ! isset($employeePick[$employeeID])) {
            $sql = [];
            $sql[] = "select record# from v_employeepick where cny# = :1 and employeeid = :2 ";
            $sql[] = GetMyCompany();
            $sql[] = $employeeID;       // well, really, the result from the picker
            $result = QueryResult($sql);
            $employeePick[$employeeID] = 0; // so we don't query again
            if (($result !== false) && ( ! empty($result))) {
                $employeePick[$employeeID] = $result[0]['RECORD#'];
            }
        }
        return $employeePick[$employeeID] ?? 0;
    }


    /**
     *      This breaks up a 'bulk action' into pieces.  One function is passed in to be callde on EACH ROW.
     *  Another is called every once in a while, so you can, say, write results out a chunk at a time.
     *  A context array is used to pass data to the callees.
     *
     *      Format for the callable routines:
     *
     *      bool = callForEach( $oneRow, $dataForRow, & $context )
     *      bool = callOnInterval( & $context )
     *
     * @param      array            $rows               rows with at least an array of the ICWQORDERIDs
     * @param      callable         $callForEach        call this for each row
     * @param      callable         $callOnInterval     call this periodically (two write out collected rows)
     * @param      array            $context            context to pass into the callable routines (optional)
     *
     * @return      bool                                how are things going?
     */
    private function bulkProcess($rows, $callForEach, $callOnInterval, $context = null)
    {
        static  $recursionLevel = -1;   // not being recursed through yet
        $source                 = "bulkProcess";
        $ok                     = true;

        // validate
        $rows = $this->clientRowsToInternalRows($rows);
        if (empty($rows)) {
            return false;
        }

        // is this the top-most call to this routine?
        //  In that case, the rows are the entire set of all possible rows.
        // But when we recurse we assume the rows are a SUBSET (maybe the entire subset)
        // of the rows from the outer level....
        $recursionLevel++;
        if ($recursionLevel === 0) {
            $ok = $this->_QM->beginTrx($source);
            if ($ok === false) {
                return $ok;
            }
            $ok = $ok && $this->bulkGetRows($rows, 0, self::GET_CACHE_SIZE);
        }

        $count = 0;
        foreach ($rows as $index => $row) {
            $ok = $ok && $callForEach( $row, $this->getCache[$row['ICWQORDERID']], $context );
            if ($count++ === self::GET_CACHE_SIZE) {
                if ($recursionLevel > 0) {
                    throw new Exception("[Code bug]recursion level $recursionLevel and we need more than $count rows starting at index $index.");
                }
                $ok = $ok && $callOnInterval( $context );
                $ok = $ok && $this->bulkGetRows($rows, $index, self::GET_CACHE_SIZE);
                $count = 0;
            }
        }
        $ok = $ok && $callOnInterval( $context );   // MAY NOT BE ANYTHING TO DO

        // All done
        if ($recursionLevel === 0) {
            if (($ok !== false) && !HasErrors()) {
                $this->_QM->commitTrx($source);
            } else {
                $this->_QM->rollbackTrx($source);
                $ok = false;
            }
        }
        $recursionLevel--;  // done with this assignment
        return $ok;
    }


    /**
     *      We build a small cache of document bundles to save (A LOT of) time get/setting bundles.
     *  This is used above in bulk processing
     *
     * @param  string[][]     $rows     An array of array of ICWQORDERIDs (and maybe other stuff)
     * @param  int            $start    Where to start in the rows array
     * @param  int            $count    How many to get
     *
     * @return bool                     Any problems?
     */
    private function bulkGetRows($rows, $start, $count)
    {
        $this->getCache = [];       // clear any prior cache
        $getThese       = [];
        $last           = $start + $count;
        $total          = count($rows);
        if ($last > $total) {
            $last = $total;
        }

        // which rows are we getting this time?
        for ($i = $start; $i < $last; $i++) {
            $getThese[$rows[$i]['ICWQORDERID']] = false;   // remove any dups
        }

        if (empty($getThese)) {
            return true;
        }

        // get the summary records
        $query = [
            'filters' => [ [ [ 'ICWQORDERID', 'IN', array_keys($getThese) ] ] ]
        ];
        $orders = $this->GetList($query);
        if ($orders === false) {
            return false;
        }

        // Index the order header records by order id
        $orderIndexes = [];
        foreach ($orders as $orderIndex => $order) {
            $id                 = $order['ICWQORDERID'];
            $orderIndexes[$id]  = $orderIndex;
            $orders[$orderIndex]['ENTRIES'] = [];
        }

        // get the detail records with tracking
        $iwqdetails  = Globals::$g->gManagerFactory->getManager("inventorywqdetail");
        $details     = $iwqdetails->getMany( array_keys($getThese) , true);

        // Attach the details and tracking to the order rows
        foreach ($details as $detailRow) {
            $id         = $detailRow['ICWQORDERID'];
            $orderIndex = $orderIndexes[$id];
            $orders[$orderIndex]['ENTRIES'][] = $detailRow; // add to the list
        }

        // now, DID we get everything we wanted, or has some other user moved stuff around
        // before we got here (i.e. while OUR user was staring at the screen)
        foreach ($orders as $order) {
            if (empty($order['ENTRIES'])) {
                Globals::$g->gErr->addIAError('INV-0142', __FILE__ . ':' . __LINE__,
                    "At least one of the items you are trying to change has been altered by someone else.  Please refresh the screen and try again.",
                    []
                );
                return false;
            }
            $id                  = $order['ICWQORDERID'];
            $this->getCache[$id] = $order;
        }
        return true;
    }


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  CRUD
    //
    //  **********************************************************************************
    //  **********************************************************************************


    /**
     *      add - not allowed
     *
     * @param array $values     fields to add
     *
     * @return bool             always throws an error and returns false
     */
    protected function regularAdd(&$values)
    {
        Globals::$g->gErr->addIAError('INV-0143', __FILE__ . ':' . __LINE__,
            'Add is not allowed on this object',
            []
        );
        return false;
    }


    /**
     * This function is responsible for transforming the inbound values to a suitable PHP structure.
     *
     * @param array $values
     *
     * @return array formatted structure
     */
    public function API_FormatObject($values)
    {
        if (isset($values['ENTRIES'])) {
            foreach ($values['ENTRIES'] as $index => $entry) {
                // prepare the tracking info if it has any
                if (isset($entry['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'])) {
                    if (isset($entry['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'][0])) {
                        $values['ENTRIES'][$index]['TRACKINGENTRIES'] = $entry['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'];
                    } else {
                        $values['ENTRIES'][$index]['TRACKINGENTRIES'] = [ $entry['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'] ];
                    }
                }
            }
        }
        return parent::API_FormatObject($values);
    }


    /**
     *      set - update a single or group of items
     *
     * The items are EACH in the format returned by get(), that is
     *      'ICWQORDERID'   the order id
     *      'ENTRIES'       the details returned by InventoryWQDetailManager::get()
     *                      you can only update certain specific fields, just as in the UI
     *                      changing other things might seem to work, but ultimately you will
     *                      be sadly disappointed in the results.
     *
     * @param array $values     fields to add
     *
     * @return bool             always throws an error and returns false
     */
    protected function regularSet(&$values)
    {
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        $groupOfValues  = $this->clientRowsToInternalRows($groupOfValues, 'SET');

        // for each passed-in bundle, do this:
        $callForEach = function( $row, $oldValues, & $context ) {

            $oldOverallStatus = $this->workQueueManager->statusForName($oldValues['STATUS']);
            $newOverallStatus = $this->workQueueManager->statusForName($row['STATUS'] ?? $oldValues['STATUS']); // may not have specified a STATUS
            $statusChange     = ($oldOverallStatus !== $newOverallStatus);

            // did the client pass in any entries?
            if ( ! isset($row['ENTRIES'])) {
                // No, they JUST changed the status and didn't bother to send any entries, so just take
                // the old entries and update the status and save them.
                if ($statusChange) {
                    foreach ($oldValues['ENTRIES'] as $oldEntry) {
                        $oldEntry['STATUS'] = $row['STATUS'];
                        $context['updateThese'][] = $oldEntry;
                    }
                }
                return true;    // nothing to do
            }

            // Index the old entries by record number
            $oldEntries = [];
            foreach ($oldValues['ENTRIES'] as $oldEntry) {
                $oldEntries[$oldEntry['RECORDNO']] = $oldEntry;
            }

            foreach ($row['ENTRIES'] as $index => $entry) {

                // get the old entry to compare to
                $oldEntry = $oldEntries[$entry['RECORDNO'] ?? 0] ?? [];
                if (empty($oldEntry)) {
                    if ($entry['RECORDNO']) {
                        Globals::$g->gErr->addIAError(
                            'INV-0851', __FILE__ . ':' . __LINE__,
                            sprintf('The record number %2s provided for line number %1s does not exist. Read the records again and provide the correct record number for each line ', $index, $entry['RECORDNO']),
                            ['INDEX' => $index, 'ENTRY_RECORDNO' => $entry['RECORDNO']]
                        );
                    } else {
                        Globals::$g->gErr->addIAError(
                            'INV-0852', __FILE__ . ':' . __LINE__,
                            sprintf('The record number %2s provided for line number %1s does not exist. Read the records again and provide the correct record number for each line ', $index, 0),
                            ['INDEX' => $index]
                        );
                    }
                    //TODO:i18N-INV-Error-Message
                    return false;
                }

                // if the header status changed, change all the entries.
                // if it did not change, let the individual rows have changes
                if ($statusChange) {
                    $entry['STATUS'] = $row['STATUS'];
                }

                if ($this->applyFieldsToSave($oldEntry, $entry)) {
                    // Are we drawing down the quantity to zero, essentially deleting the record?
                    $isSet = (isset($oldEntry['IWQKEY']) && ($oldEntry['IWQKEY'] != 0));
                    if ($oldEntry['QUANTITY'] === 0) {
                        if ($isSet) {
                            $context['deleteThese'][] = $oldEntry['IWQKEY'];
                        }
                    } else {
                        if ($isSet) {
                            $context['updateThese'][] = $oldEntry; // yes, we update the OLD ENTRY because ENTRY
                        } else {                        //    may be sparse (just what they wanted to change)
                            $context['addThese'][] = $oldEntry;
                        }
                    }
                }
            }
            return true;
        };

        // periodically, and at the end, do this:
        $callOnInterval = function( & $context ) {
            $ok = true;
            $iwqdetails = Globals::$g->gManagerFactory->getManager("inventorywqdetail");
            if (!empty($context['deleteThese'])) {
                $ok  = $ok && $this->workQueueManager->Delete($context['deleteThese']);
            }
            if (!empty($context['addThese'])) {
                $ok = $ok && $iwqdetails->add($context['addThese']);
            }
            if (!empty($context['updateThese'])) {
                $ok = $ok && $iwqdetails->set($context['updateThese']);
            }
            $context['addThese']    = [];   // clear out for next time
            $context['updateThese'] = [];
            $context['deleteThese'] = [];
            return $ok;
        };

            // do the bulk action:
        $context                = [];
        $context['addThese']    = [];
        $context['updateThese'] = [];
        $context['deleteThese'] = [];
        $ok = $this->bulkProcess($groupOfValues, $callForEach, $callOnInterval, $context);

        return $ok;
    }


    /**
     * Get a single record
     *
     * @param string        $ID         an ICWQORDERID, or multiples of them
     * @param string[]|null $fields
     *
     * @return array|false              the DETAIL LINES for this order
     */
    function get($ID, $fields = null)
    {
        // when printing, the form editor is being helpful and getting our data with something
        // other than the ID (it sends us the action).
        if (strpos($ID, '--') === false) {
            return null;
        }

        return parent::get($ID);
    }


    /**
     * Delete a record from the database
     *
     * Not allowed on this entity
     *
     * @param string|int $ID vid of entity
     *
     * @return bool
     */
    public function Delete($ID)
    {
        Globals::$g->gErr->addIAError('INV-0144', __FILE__ . ':' . __LINE__,
            'Delete is not allowed on this object',
            []
        );
        return false;
    }


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  OTHER ENTITY MANAGER OVERRIDES AND HELPERS
    //
    //  **********************************************************************************
    //  **********************************************************************************

    /**
     *      While processing a 'GetList()', this is called just before the parameters are processed.  It
     *  allows us to tinker with the parameters.  This is instead of/in addition to catching the outer GetList() function.
     *
     * NOTE: GetList() from the MANAGER is different than GetList() from the LISTER, but BOTH go through here....
     *
     * @param array $params
     */
    function processParamsHook(&$params)
    {
        if ( ! self::featureEnabled(self::FEATURE_FLAG_ONLY)) {
            return;
        }

        // Sometimes, the 'orders' field is "" and not [] or null.  In those cases, fix it/remove it.  If you don't,
        // then the ORDER BY clause has a comma as the first thing: "ORDER BY ,a,b"
        if (isset($params['orders']) && ($params['orders'] === '')) {
            $params['orders'] = [];
        }

        // Get stuff for the window shade, and the id:
        $getThese = [
                'DOCPARID',     // so we can figure out the targets for convert
                'ICWQORDERID',
                'DOCUMENTTYPE',
            ];
        if (self::areShipDatesEnabled()) {
            $getThese[] = 'SHIPBYDATE';
            $getThese[] = 'NEEDBYDATE';
            $getThese[] = 'DONOTSHIPBEFOREDATE';
            $getThese[] = 'DONOTSHIPAFTERDATE';
            $getThese[] = 'CANCELAFTERDATE';
            $getThese[] = 'SHIPPEDDATE';
        }
        $selects = $params['selects'] ?? '';
        foreach ($getThese as $field) {
            if (!in_array($field, $selects)) {
                $params['selects'][] = $field; // we want this
            }
        }

        // and the filter tree can be broken (i.e. no filter but causes an empty paren), so remove it:
        if (isset($params['filters'][0]['filters']) && (count($params['filters']) == 1) && (empty($params['filters'][0]['filters']))) {
            $params['filters'] = [];
        }
    }


    /**
     *  client rows to internal rows
     *
     *      The client (API/UI) sent us what we hope are valid ICWQORDERID and other data.
     *  Here, let's parse/validate that data.  Then we can return trusted data.
     *  Public so the Editor can use it too.
     *
     * @param   array   $rows       the client-provided rows of data
     * @param   string  $action     optional global action
     *
     * @return  array               validated and digested rows of data
     */
    public function clientRowsToInternalRows($rows, $action = null)
    {
        $rtn        = [];
        $iwqManager = $this->workQueueManager;

        // sort into bundle, then docentry, then iwqkey order
        usort($rows, function ($a, $b) {
            $ai  = $a['ICWQORDERID'] ?? '';
            $bi  = $b['ICWQORDERID'] ?? '';
            $cmp = strcmp($ai, $bi);
            if ($cmp === 0) {
                $adeKey      = $a['DOCENTRYKEY'] ?? 0; // is this a request for a specific row?
                $bdeKey      = $b['DOCENTRYKEY'] ?? 0;
                if ($adeKey < $bdeKey) {
                    $cmp = -1;
                } else if ($adeKey > $bdeKey) {
                    $cmp = +1;
                } else {
                    // save docentry record.  What about the work queue records?
                    $aiwqKey = $a['IWQKEY']      ?? 0;
                    $biwqKey = $b['IWQKEY']      ?? 0;
                    if ($aiwqKey < $biwqKey) {
                        $cmp = -1;
                    } else if ($aiwqKey > $biwqKey) {
                        $cmp = +1;
                    }
                }
            }
            return $cmp;
        });

        foreach ($rows as $row) {

            if (isset($row['ASSIGNED'])) {
                $assigned = $row['ASSIGNED'];
                if ($assigned != '') {
                    $row['ASSIGNKEY'] = $this->getEmployeeKey($assigned);
                } else {
                    $row['ASSIGNKEY'] = 0;
                }
            }

            // check required fields
            if (!isset($row['ICWQORDERID']) || ($row['ICWQORDERID'] == '')) {
                Globals::$g->gErr->addIAError('INV-0145', __FILE__ . ':' . __LINE__,
                    'Provide the work queue ID for each entry in your request.',
                    []
                );
                return [];
            }
            if (!isset($row['ACTION'])) {
                $row['ACTION'] = $action;   // use the optional action?
            }
            if (!isset($row['ACTION'])) {
                Globals::$g->gErr->addIAError('INV-0146', __FILE__ . ':' . __LINE__,
                    'Provide the action, such as ‘save’, for each entry in your request.',
                    []
                );
                return [];
            }

            // now validate and decompose the ICQWORDERID field
            list($dochdr, $warehouse, $shipto, $state) = explode(Util::INTACCTID_SEPARATOR, $row['ICWQORDERID']);

            // the not numeric check is to avoid sql injection
            if (($dochdr == 0) || ($warehouse == 0) || ($state == '') || ($shipto == 0) ||
                (!is_numeric($dochdr)) || (!is_numeric($warehouse)) || (!is_numeric($shipto)) ||
                    ($iwqManager->queueForAction($state) == '')) {
                Globals::$g->gErr->addIAError('INV-0147', __FILE__ . ':' . __LINE__,
                    'The work queue ID for one or more of the entries is formatted incorrectly.',
                    [],
                    "Make sure you pass in IDs that are returned by a query.",
                    []
                );
                return [];
            }

            $row['DOCHDRKEY']    = $dochdr;
            $row['WAREHOUSEKEY'] = $warehouse;
            $row['SHIPTOKEY']    = $shipto;
            $row['CURRENTSTATE'] = $state;

            if (isset($row['DOCENTRYKEY'])) {
                if (($row['DOCENTRYKEY'] === 0) || ($row['DOCENTRYKEY'] === '')) {
                    unset($row['DOCENTRYKEY']);
                    unset($row['IWQKEY']);
                } else {
                    $row['IWQKEY'] = $row['IWQKEY'] ?? 0;   // so it does exist if DOCENTRYKEY exists, but might be 0
                }
            }

            // status field is optional
            if (isset($row['STATUS'])) {
                if ($row['STATUS'] == '') {
                    unset($row['STATUS']);  // make it null
                } else {
                    $status = $this->workQueueManager->statusForName($row['STATUS']);
                    if ($status == '') {
                        Globals::$g->gErr->addIAError(
                            'INV-0703', __FILE__ . ':' . __LINE__,
                            sprintf("The status '%1s' is not valid.", $row['STATUS']), ['ROW_STATUS' => $row['STATUS']],
                            "Change the status to a valid status and try again.",[]
                        );
                        return [];
                    }
                    $row['STATUS'] = $this->workQueueManager->enumForStatus($status);  // reconstitute it with correct case and such
                }
            }


            $rtn[] = $row;
        }
        return $rtn;
    }


    /**
     *      In a 'save' command, we save any fields the customer gave us to save in 'fieldsToAdd'
     *  Well, fields we allow them to change.  The new entry can be very sparse (just the changed fields)
     *  and the old entry is assumed to be complete and we can update it.
     *
     *  Yes, the OLD entry gets updated as it was whole and the new entry may be just a couple of fields.
     *
     * @param array     $oldEntry               one DETAIL entry (not the order-level, but one ENTRIES entry)
     * @param array     $newEntry               what to change (or keep the same)
     *
     * @return bool     did the old entry change?
     */
    private function applyFieldsToSave( & $oldEntry, $newEntry )
    {
        $iwqManager               = $this->workQueueManager;
        $changed                  = false;
        $fieldsThatCanBeChanged   = InventoryWorkQueueManager::userChangeableFields();
        $fieldsThatCanBeChanged[] = 'ASSIGNKEY';        // these are handled in the work queue manager
        $fieldsThatCanBeChanged[] = 'SHIPTRACKING';
        $fieldsThatCanBeChanged[] = 'HOLDPROGRESS';     // handled locally
        $fieldsThatCanBeChanged[] = 'STATUS';           // on the details screen, a synonym for action

        foreach ($fieldsThatCanBeChanged as $field) {
            if (isset($newEntry[$field])) {
                $value = $newEntry[$field];
                $now   = $oldEntry[$field] ?? '';
                if ($field === 'STATUS') {
                    $value      = $iwqManager->statusForName($value);   // normalize them to their INTERNAL form (like an ACTION)
                    $now        = $iwqManager->statusForName($now);
                }
                // PHP8_NUMERIC_STRING_COMPARE; Priority: low; Behavior: strict, Risk: low, Solution: strict equality
                if ($now !== $value) {
                    $oldEntry[$field] = $value;
                    $changed          = true;   // but keep going
                }
            }
        }

        $newHasTracking = isset($newEntry['TRACKINGENTRIES']) && ! empty($newEntry['TRACKINGENTRIES']);
        if ( ! $changed) {
            $oldHasTracking = isset($oldEntry['TRACKINGENTRIES']) && ! empty($oldEntry['TRACKINGENTRIES']);
            $changed        = ($oldHasTracking != $newHasTracking);
            if ( ! $changed && $oldHasTracking) {   // then new has tracking as well....
                $oldTracking    = $oldEntry['TRACKINGENTRIES'];
                $newTracking    = $newEntry['TRACKINGENTRIES'];
                $changed = count($oldTracking) != count($newTracking);
                if ( ! $changed) {
                    foreach ($oldTracking as $trackIndex => $oldTrack) {
                        $newTrack = $newTracking[$trackIndex];
                        $diff     = array_diff($oldTrack, $newTrack);
                        $changed  = ! empty($diff);
                        if ($changed) {
                            break;
                        }
                    }
                }
            }
        }

        // Save the new tracking, changed or not.
        // i.e. we may not have checked tracking to see if IT changed, but SOMETHING changed....
        if ($newHasTracking) {
            // Don't let the UI/API pull some shenanigans!
            InvBizLogicForWD::fixupTrackingEntries($oldEntry, $newEntry['TRACKINGENTRIES']);
        }

        //Only check for isset as when users delete the tracking, it will be set but empty. So we can't check for empty.
        if (isset($newEntry['TRACKINGENTRIES'])) {
            $oldEntry['TRACKINGENTRIES'] = $newEntry['TRACKINGENTRIES'];
        }

        return $changed;
    }


    /**
     *      Take actions on entire orders, or on a set of lines
     *  This allows for the UI to use BULK orders.  The API has to do that on their own
     *  (i.e. do one/more GET, then a bulk SET)
     *
     * @param  string[][]     $rows       the rows of data, including their ICWQORDERID
     *
     * @return bool
     */
    public function takeActionOnOrders($rows)
    {

        // for each passed in bundle, do this:
        $callForEach = function( $row, $docEntries, & $context )
        {
            $deKey      = $row['DOCENTRYKEY'] ?? 0; // is this a request for a specific row?
            $iwqkey     = $row['IWQKEY'] ?? 0;
            $action     = $row['ACTION'];

            // NOTE: We could be doing a per-order update, OR a per-line update.
            //      i.e. if you pop up a details screen and hit save, we get all the rows on that screen with the fields
            //          that can be changed.  In THAT case, they all have the same order, and so one get() and we'd have
            //          all the current records.  To indicate it is for a unique row, we get the DOCENTRYKEY and the IWQKEY
            $entries = [];
            if ($deKey) {
                foreach ($docEntries['ENTRIES'] as $entry) {
                    if ($entry['DOCENTRYKEY'] === $deKey) {
                        if (($iwqkey == 0) || ($iwqkey === $entry['IWQKEY'])) {
                            $entries[] = $entry;
                            break;
                        }
                    }
                }
            } else {
                $entries = $docEntries['ENTRIES'];  // change all
            }

            // now take action and maybe save the record
            foreach ($entries as $docEntry) {
                $key        = $docEntry['ICWQORDERID'];

                // NOTE ABOUT STATUS VS ACTION:
                // Except for the 'SAVE' action, which is NOT a status,
                // all other actions are IDENTICAL to status'.
                // so, to make something be in the Ready to Pick status (RPI),
                //  the action is RPI and the resulting status is RPI
                // also note the below are in the 'internal' names like RPI not "Ready to pick".
                if ($action === 'SAVE') {
                    // maybe nothing changed, or just HOLDPROGRESS changed, for example
                    // or all the tracking data!
                    if ($this->applyFieldsToSave($docEntry, $row)) {
                        $context[$key][] = $docEntry;
                    }
                } else {
                    $internalStatus      = $this->workQueueManager->statusForName($docEntry['STATUS']);
                    if ($internalStatus != $action) {
                        $docEntry['STATUS'] = $action;    // where we're going
                        $context[$key][] = $docEntry;
                    }
                }
            }
            return true;
        };

        // flush any collected lines (use set() )
        $callOnInterval = function( & $context )
        {
            $updateThese = [];
            foreach ($context as $oneKey => $des) {
                $updateThese[] = ['ICWQORDERID' => $oneKey, 'ENTRIES' => $des];
            }
            // bulk set these
            $ok = true;
            if (!empty($updateThese)) {
                $ok = $this->set($updateThese); // bulk update
            }
            $context = [];
            return $ok;
        };

        // do the bulk action:
        $context                = [];
        $ok = $this->bulkProcess($rows, $callForEach, $callOnInterval, $context);

        return $ok;
    }


    /**
     * Handle the Platform relationships
     *
     *      Well, here, I don't want any, and it slows things down constantly changing contexts for mega views.....
     *
     * @param array $values
     * @param bool  $doBulk
     * @param array $stmtCollections
     * @param array $bulkRelCollection
     *
     * @return bool success or failure
     */
    function handleCustomRelationships($values, $doBulk = false, &$stmtCollections = null, &$bulkRelCollection = null)
    {
        return true;
    }

    /**
     * Override the Entity Manager GetList() code.
     *
     *   - if an error is generated, throw it as an exception.  The caller only responds to exceptions, not errors.
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        if ( ! self::featureEnabled(self::FEATURE_FLAG_ONLY)) {
            return [];
        }

        if ( IsMultiEntityCompany() && (! GetContextLocation())) {
            $_sess = Session::getKey();
            // we need to turn off mega views if we are root level
            SetUserContext($_sess, 'T', GetContextLocation(), 'T');
        }

        $isALLtab= (is_array($params['filters']) && is_array($params['filters'][0]) && is_array($params['filters'][0]['filters'])
                    && Util::countOrZero($params['filters'][0]['filters']) ==0) ;

        if($isALLtab){
            //check the module features enabled and filter the disabled statuses
            global $kINVid;
            GetModulePreferences($kINVid, $prefs);
            $pick = ( $prefs['PICK'] == 'T' );
            $pack = ( $prefs['PACK'] == 'T' );
            $ship = ( $prefs['SHIP'] == 'T' );;
            $invoice = ( $prefs['INVOICE'] == 'T' );

            $notInStatuses = [];
            if ( ! $pick) {
                $notInStatuses[] = 'ready to pick';
                $notInStatuses[] = 'picked';
            }

            if ( ! $pack) {
                $notInStatuses[] = 'ready to pack';
                $notInStatuses[] = 'packed';
            }

            if ( ! $ship) {
                $notInStatuses[] = 'ready to ship';
                $notInStatuses[] = 'shipped';
            }

            if ( ! $invoice) {
                $notInStatuses[] = 'ready to invoice';
                $notInStatuses[] = 'invoiced';
            }

            if (count($notInStatuses) > 0) {
                $params['filters'][0]['filters'][] = array( 'STATUS', 'NOT IN', $notInStatuses );
            }
        }
        $rtn = parent::GetList($params, $_crosscny, $nocount );   // DO THE QUERY (cross your fingers!)
        $this->getConvertToForList( $rtn);
        return $rtn;
    }


    /**
     *      For the UI, we want the list of what each bundle can convert to if you did a one-off conversion
     *  (not a bulk conversion).  Get the list of targets here....
     *
     * @param array|bool     $list           The list returned from GetList()
     *
     */
    private function getConvertToForList( & $list)
    {
        if (($list === false) || empty($list)) {
            return;     // nothing to do
        }

        // Step one: get the docpar id's, if any
        $docparids = [];
        foreach ($list as $row) {
            $docparid = $row['DOCPARID'] ?? '';
            if ($docparid != '') {
                $docparids[$docparid] = [];   // weed out dups
            }
        }

        // Now ask the conversion manager to get the targets
        if ( ! empty($docparids)) {
            $conversionManager = new ConversionManager(['mod' => 'so']);
            $graph = $conversionManager->bulkConvertTo(array_keys($docparids), true); // false is NOT just fulfillment only
            foreach ($graph as $docparid => $oneDocPar) {
                $targets = $oneDocPar['TARGETS'] ?? [];
                if (isset($docparids[$docparid]) && ! empty($targets)) {
                    $docparids[$docparid] = [];
                    foreach ($targets as $target) {
                        $docparids[$docparid][] = $target['DOCID'];
                    }
                }
            }
        }

        // And put the targets back into the list, if any
        if ( ! empty($docparids)) {
            foreach ($list as $index => $row) {
                $docparid = $row['DOCPARID'] ?? '';
                if (($docparid != '') && (!empty($docparids[$docparid]))) {
                    $list[$index]['CONVERT_TO'] = $docparids[$docparid];
                }
            }
        }
    }

}
