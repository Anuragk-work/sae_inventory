<?

/**
 * Class InventoryWQDetailManager - Inventory Work Queue 'details' view of data.
 *
 *  The idea is: we have dochdr records, docentry records, and InventoryWorkQueue records, and we want to
 *      have UI/API queries of detailed information from each of those.
 *
 * Normally, you'd need a sql table that describes all this so that the Custom Reports, 'filter framework', grid sorting/searching,
 * and other functionality would work.  We use a global temporary table for this.
 *
 * Here, we're limited to view-only, plus some VERY LIMITED writes, mostly "commands" ("Move to state <state>") and specific
 * writable fields (like tracking data)
 *
 * Roger Collins, July 2021
 *
 */
class InventoryWQDetailManager extends OwnedObjectManager
{

    /** @var array  $recordCache */
    private         $recordCache              = [];        // cache of records, when appropriate

    /** @var array|null $workQueueKeys  */
    private             $workQueueKeys        = null;      // cache of the work queue keys we just read in a getByParent()

    /** @var array|null $trackingRecordCache */
    private             $trackingRecordCache  = null;       // cache of tracking records if needed

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);

        // do not create short URLs for the temporary global table
        $this->canCreateRecordUrl = false;
    }


    /**
     *      We sometimes want to translate external status to internal status
     *
     * @param string $externalStatus        external form of the status like 'ready to pick' (all lower case)
     *
     * @return string                       internal form of the status like 'RPI'
     */
    public function translateExternalToInternalStatus($externalStatus)
    {
        // we do this a LOT, so make a tiny cache of the values.....
        static $translate = null;
        if ($translate === null) {
            $fi = $this->_schemas[$this->_entity]['fieldinfo'];
            foreach ($fi as $field) {
                if ($field['path'] == 'STATUS') {
                    foreach ($field['type']['validvalues'] as $index => $external) {
                        $translate[ $external ] = $field['type']['_validivalues'][$index];
                    }
                    break;
                }
            }
        }

        // now translate external to internal
        return $translate[ $externalStatus ] ?? $externalStatus; // just in case it was already in internal format.....
    }



    //  ********************************************************************
    //  ********************************************************************
    //
    //  CRUD OPERATIONS
    //
    //  ********************************************************************
    //  ********************************************************************



    /**
     *      Get many records: like get(), but ... er.. gets MANY.
     *
     * Gets tracking data too.
     *
     * @param  int[]|string[]            $records               bunch-o-record numbers, OR IcWq
     * @param  bool                      $recordsAreOrderIDs    are the record#'s really ICWQORDERIDs?
     *
     * @return bool|array                                       returned records, or false
     */
    public function getMany($records, $recordsAreOrderIDs = false)
    {
        $recs = [];
        if ( ! empty($records)) {
            $query       = [
                'filters' => [ [ [ ($recordsAreOrderIDs ? 'ICWQORDERID' : 'RECORDNO'), 'IN', array_unique($records) ] ] ]
            ];
            $recs = $this->GetList($query);
            if ($recs === false) {
                return false;
            }

            $getTrackingFor = [];
            foreach ($recs as $index=> $oneRec) {
                $recs[$index]['TRACKINGENTRIES'] = [];
                $getTrackingFor[$oneRec['RECORDNO']] = $index;   // remove dups, though we don't expect any
            }

            // get tracking details, if any
            if ( ! empty($getTrackingFor)) {
                $iwqtracking = Globals::$g->gManagerFactory->getManager("inventorywqdetailtracking");
                $query = [
                    'filters' => [[['WORKQUEUEKEY', 'IN', array_keys($getTrackingFor)]]]
                ];
                $tracking = $iwqtracking->GetList($query);
                if ($tracking === false) {
                    return false;
                }
                foreach ($tracking as $oneTrack) {
                    $iwq   = $oneTrack['WORKQUEUEKEY'];
                    $index = $getTrackingFor[$iwq];
                    $recs[$index]['TRACKINGENTRIES'][] = $oneTrack;
                }
            }
        }
        return $recs;
    }


    /**
     * Get a single record.
     *
     *
     * @param string        $recordNum          A record# (of the inventory work queue record
     * @param string[]|null $fields
     *
     * @return array|false                      one DETAIL LINE
     */
    function get($recordNum, $fields = null)
    {
        // is it in the cache?
        if (isset( $this->recordCache[$recordNum])) {
            return $this->recordCache[$recordNum];
        }

        // Is the record already there?
        $rec = parent::get($recordNum, $fields);
        if (($rec !== false) && ( ! empty($rec))) {
            InventoryWorkQueueManager::fixTimestampsInRecord($rec);
        }
        return $rec;
    }


    /**
     * @param  array        $groupOfValues      bunch-o-records, with 'RECORDNO' in them for what we'll get
     *
     * @return bool
     */
    private function getSmallCacheOfRecords($groupOfValues)
    {

        // Let's create a cache of records if we can
        $this->recordCache = [];    // flush any prior cache, so it doesn't get too big
        $getThese          = [];
        foreach ($groupOfValues as $oneValue) {
            $getThese[$oneValue['RECORDNO']] = true;    // remove dups (unlikely, but)
        }

        // get the records, with tracking
        $recs = $this->getMany(array_keys($getThese));
        if ($recs === false) {
            return false;
        }

        // index and save
        foreach ($recs as $oneRec) {
            $this->recordCache[$oneRec['RECORDNO']] = $oneRec;  // only expect one per id
        }

        return true;
    }


    /**
     * Common code for add and set, below
     * Note: needs the VERY SPECIAL FORMAT of values created by the InventoryWQDetailManager!
     *
     * @param array $values             one array of values returned by the get(), above
     * @param bool  $forSet             is this a set()?  (if not it is an add)
     *
     * @return bool                     did we set it?
     */
    protected function addOrSet( & $values, $forSet )
    {
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        $iwqManager = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");
        $bizLogic   = Globals::$g->gManagerFactory->_getObjectInstance("InvBizLogicForWD");
        InvBizLogicForWD::updateTotalsCache($groupOfValues);
        $iwqs       = [];
        $iwqsAdd    = [];
        $ok         = true;

        $this->getSmallCacheOfRecords($groupOfValues);

        foreach ($groupOfValues as $oneValue) {
            $current    = $this->get($oneValue['RECORDNO']);
            $ok         = $ok && ($current !== false);
            $splitValue = [];
            $ok         = $ok && $bizLogic->fulfillmentDetailsUpdate($current, $oneValue, $splitValue);
            $iwq        = [];
            $iwqSplit   = null;
            if ($ok) {
                $iwq    = $iwqManager->createWorkQueueRecordFromDocEntry($oneValue, $forSet);
                $ok     = $ok && ($iwq !== false);
                if ($ok && ( ! empty($splitValue))) {
                    $iwqSplit  = $iwqManager->createWorkQueueRecordFromDocEntry($splitValue, false); // this one is new always
                    $ok        = $ok && ($iwqSplit !== false);
                }
            }
            if ( ! $ok) {
                break;
            }
            $iwqs[]     = $iwq;
            if ($iwqSplit !== null) {
                $iwqsAdd[] = $iwqSplit;
            }
        }

        // all done thinking, lets start DOING....
        if ($ok && !empty($iwqsAdd))
        {
            $ok = $iwqManager->add($iwqsAdd);
        }
        if ($ok && !empty($iwqs))
        {
            // bulk add or set
            $ok = $forSet ? $iwqManager->set($iwqs) : $iwqManager->add($iwqs);
        }

        $ok = $ok && $bizLogic->bizLogicCleanup();

        return $ok;
    }


    /**
     * Create one or a set of underlying Inventory Work Queue records
     * Note: needs the VERY SPECIAL FORMAT of values created by the InventoryWQDetailManager!
     *
     * @param array $values             one array of values returned by the get(), above
     *                                  or multiples of them
     *
     * @return bool                     did we set it?
     */
    function regularAdd( & $values)
    {
        return $this->addOrSet($values, false);
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
        // prepare the tracking info if it has any
        if (isset($values['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'])) {
            if (isset($values['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'][0])) {
                $values['TRACKINGENTRIES'] = $values['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'];
            } else {
                $values['TRACKINGENTRIES'] = [ $values['TRACKINGENTRIES']['INVENTORYWQDETAILTRACKING'] ];
            }
        }
        return parent::API_FormatObject($values);
    }


    /**
     * Update one or a set of underlying Inventory Work Queue records
     * Note: needs the VERY SPECIAL FORMAT of values created by the InventoryWQDetailManager!
     *
     * Also note: The API user will use UPDATE, which comes here, even when the record has no
     *      Inventory Work Queue record, because this record has a recordno.  Here, I need to
     *      sort out the Inventory Work Queue Adds from Updates, based on whether there is a
     *      IWQKey field.
     *
     * @param array $values             one array of values returned by the get(), above
     *                                  or multiples of them
     *
     * @return bool                     did we set it?
     */
    function regularSet( & $values)
    {
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        $adds    = [];
        $updates = [];
        // a true ADD has no IWQKEY, but an UPDATE does have one.
        foreach ($groupOfValues as $row) {
            $iwqkey = $row['IWQKEY'] ?? 0;
            if ($iwqkey != 0) {
                $updates[] = $row;
            } else {
                $adds[] = $row;
            }
        }
        $ok = true;
        // bulk update as possible
        if ( ! empty($adds)) {
            $ok = $this->addOrSet($adds, false);
        }
        if ( ! empty($updates)) {
            $ok = $this->addOrSet($updates, true);
        }
        return $ok;
    }


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
        if ( ! InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            return;
        }

        // Sometimes, the 'orders' field is "" and not [] or null.  In those cases, fix it/remove it.  If you don't,
        // then the ORDER BY clause has a comma as the first thing: "ORDER BY ,a,b"
        if (isset($params['orders']) && ($params['orders'] === '')) {
            $params['orders'] = [];
        }

        // and the filter tree can be broken (i.e. no filter but causes an empty paren), so remove it:
        if (isset($params['filters'][0]['filters']) && (count($params['filters']) == 1) && (empty($params['filters'][0]['filters']))) {
            $params['filters'] = [];
        }
    }



    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  Support for external callers: Filter Framework, Custom Reports, GetList(), etc.
    //
    //  **********************************************************************************
    //  **********************************************************************************

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
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        if ( ! InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            return [];
        }
        $return = parent::GetList($params, $_crosscny, $nocount );   // DO THE QUERY (cross your fingers!)
        if ($return !== false) {
            foreach ($return as $index => $row) {
                InventoryWorkQueueManager::fixTimestampsInRecord($return[$index]);
            }
        }
        return $return;
    }


    /**
     * Get all objects owned by a parent (This is an EntityManager override)
     *
     *  Overridden so we can more easily (i.e. faster) read the tracking records.  Otherwise, if there are
     *  1000 lines on a transaction, we'd do 1000 getOwnedObjectData() on the tracking records!
     *
     * @param  string $_parent id of the parent
     *
     * @return array|false
     */
    function getByParent($_parent)
    {
        $recs = parent::getByParent($_parent);

        // collect the work queue keys....
        $this->workQueueKeys = [];
        $this->trackingRecordCache = null;  // not yet fetched, may never be
        if ($recs !== false) {
            foreach ($recs as $rec) {
                $this->workQueueKeys[ $rec['RECORDNO']] = true;
            }
        }
        return $recs;
    }

    /**
     *  Entity Manager override of GetOwnedObjectData
     *
     *      When doing a get() on an order, GetOwnedObjectData for the ORDER does a single
     *  getByParent.  That can fetch 1..1000 records.  But, when it then recurses down to these detail records,
     *  there will be one getByParent for EVERY detail record; meaning there can be 1000 or more sql calls!
     *  This will stop that because above we saved all the work queue keys, so here we can do a fetch for many
     *  parents and sort it out, turning 1000 queries into 1.
     *
     * @param array $obj
     * @param array $ownedObjects
     *
     * @return bool success or failure
     */
    function GetOwnedObjectData(&$obj, $ownedObjects)
    {
        $key = $obj['RECORDNO'];
        // if conditions change, go back to the default mechanism
        $useCache = (count($ownedObjects) === 1) && ($ownedObjects[0]['path'] === 'TRACKINGENTRIES');
        if ($useCache && isset($this->workQueueKeys[$key])) {

            // did we already get the cache of tracking records?
            // If not, fetch them
            if ($this->trackingRecordCache === null) {
                $this->trackingRecordCache = [];

                $iwqtracking = Globals::$g->gManagerFactory->getManager("inventorywqdetailtracking");
                $query = [
                    'filters' => [[['WORKQUEUEKEY', 'IN', array_keys($this->workQueueKeys)]]]
                ];
                $tracking = $iwqtracking->GetList($query);
                if ($tracking === false) {
                    return false;
                }
                foreach ($tracking as $oneTrack) {
                    $iwq   = $oneTrack['WORKQUEUEKEY'];
                    if ( ! isset($this->trackingRecordCache[$iwq])) {
                        $this->trackingRecordCache[$iwq] = [];
                    }
                    $this->trackingRecordCache[$iwq][] = $oneTrack;
                }
            }
            $obj['TRACKINGENTRIES'] = $this->trackingRecordCache[$key] ?? [];   // many will likely have no tracking records
            return true;
        }
        return parent::GetOwnedObjectData($obj, $ownedObjects);
    }

}

