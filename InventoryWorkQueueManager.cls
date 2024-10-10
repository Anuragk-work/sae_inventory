<?php


class InventoryWorkQueueManager extends EntityManager   // was OwnedObjectManager parent was InventoryTaskList, now is up for grabs
{
    // This functionality will work for different kinds of workflows.
    // The FIRST one is 'fulfillment', but we may add things like Cycle Counts and
    // Stockable Kit Builds and others.
    //
    //  To keep the queues separate, there are prefixes per KIND of subsystem we're looking at.....
    // (note: don't use underscore because it is an oracle matching char...)

    const   QUEUE_OPEN                      = 'OPEN';
    const   QUEUE_HIDDEN                    = 'HIDDEN'; // i.e. not shown on fulfillment ui
    const   QUEUE_PREFIX_FULFILLMENT        = "FF-";
    const   QUEUE_PREFIX_CYCLECOUNT         = "CC-";    // future use?
    const   QUEUE_POSITIONS_ARE_LESS_THAN   = 100000;   // arbitrary, but larger than the max # of places we will ever have (ha ha ha)
    // ... and so on ...

    const   NOTES_FIELD_LENGTH              = 4000;
    const   REFERENCE2_FIELD_LENGTH         = 100;
    const   CONVERTEDTO_FIELD_NAME          = 'SUGGESTEDSEQUENCE'; // someday we'll rename this field, but until then....
    const   INCREMENT_GROUP                 = 'INCREMENT';
    const   GROUP_FROM                      = 'FROM ';  // and then the record number of the source

    // when calling getMany(), what are you passing it?
    // (skip 0 and 1 in case someone passes a boolean)
    const   GET_MANY_RECORD_NUMBER          = 2;    // record# of the InventoryWorkQueue record
    const   GET_MANY_WORKKEYS               = 3;    // record# of the DocEntry it refers to
    const   GET_MANY_DOCHDR                 = 4;    // dochdr record#




    /** @var array $staticQueueInformationTable */
    public      $staticQueueInformationTable = [];

    /** @var int $cachedDocHeader */
    protected   $cachedDocHeader = '';        // Doc hdr record

    /** @var array $cachedReserved */
    protected   $cachedReserved  = [];       // indexed by docentry record#, if the cache is going



    /** @var int[] $okToChange  the public can change these */
    protected static   $okToChange = [
                    'PLACE'                 => 1,
                    'QUANTITY'              => 2,        // positive means 'create new record', negative no

                    'QUANTITYINRESERVE'     => 2,       // the quantity isn't as important as the DELTA
                    'QUANTITYINALLOCATION'  => 2,
                    'DELTARESERVE'          => 2,       // or if the old record had a delta
                    'DELTAALLOCATION'       => 2,
                    'QUANTITYPICKED'        => 2,
                    'QUANTITYPACKED'        => 2,
                    'HOLDPROGRESS'          => 1,
                    'DOCUMENTTYPE'          => 1,

                    'NOTES'                 => -1,        // these fields can change without marking the record as COMPLETED
                    'PICKCONTAINER'         => -1,
                    'PACKCONTAINER'         => -1,
                    'REFERENCE'             => -1,
                    'REFERENCE2'            => -1,
                    'ASSIGNEDTO'            => -2,
                    'PICKLISTPRINTED'       => -3,
                    'PACKLISTPRINTED'       => -3,
                    'LINENO'                => -2,       // the SO may have had its lines reordered
                    'WAREHOUSEID'           => -2,       // ...or its entries' warehouse(s)...
                    'ITEMID'                => -2,       // ...or itemIds...
                    'UOM'                   => -2,       // ...or UOMs, which imply...
                    'UOMFACTOR'             => -2,       // ...their corresponding UOMFACTORs...
                    'ORDERDATE'             => -4,
                    'CONVERTEDTO'           => -1,
                    'GROUP'                 => -1,
                    'ORIGINALDOCID'         => -1,
                    'WHENMODIFIED'          => -1,
                ];

    private array $textMap =[];
    /**
     *      Constructor
     *
     * @param array $params
     */
    function __construct($params=array())
    {
        parent::__construct($params);

        $tokens = [
            [ 'id' => 'IA.OPEN' ],
            [ 'id' => 'IA.READY_TO_PICK' ],
            [ 'id' => 'IA.PICKED' ],
            [ 'id' => 'IA.READY_TO_PACK' ],
            [ 'id' => 'IA.PACKED' ],
            [ 'id' => 'IA.READY_TO_SHIP' ],
            [ 'id' => 'IA.SHIPPED' ],
            [ 'id' => 'IA.READY_TO_INVOICE' ],
            [ 'id' => 'IA.INVOICED' ],
            [ 'id' => 'IA.HIDDEN_FROM_UI' ],
            [ 'id' => 'IA.RECOVERED_WHEN_DOC_DELETED']
        ];
        $this->textMap = getLocalizedTextWithThrow($tokens);

        // I would have made this a const at the top of the class, but you can't have function calls, and I need
        // those for the English translations.....
        $this->staticQueueInformationTable = [
            self::QUEUE_OPEN                                => ['STATUS' => 'O',  'ENUM' => "open",             'NAME' => GT($this->textMap, 'IA.OPEN')],       // NOT IN FULFILLMENT
            self::QUEUE_PREFIX_FULFILLMENT . "TOBEPICKED"   => ['STATUS' => 'RPI','ENUM' => "ready to pick",    'NAME' => GT($this->textMap, 'IA.READY_TO_PICK')],
            self::QUEUE_PREFIX_FULFILLMENT . "PICKED"       => ['STATUS' => 'PI', 'ENUM' => "picked",           'NAME' => GT($this->textMap, 'IA.PICKED')],
            self::QUEUE_PREFIX_FULFILLMENT . "TOBEPACKED"   => ['STATUS' => 'RPA','ENUM' => "ready to pack",    'NAME' => GT($this->textMap, 'IA.READY_TO_PACK')],
            self::QUEUE_PREFIX_FULFILLMENT . "PACKED"       => ['STATUS' => 'PA', 'ENUM' => "packed",           'NAME' => GT($this->textMap, 'IA.PACKED')],
            self::QUEUE_PREFIX_FULFILLMENT . "TOBESHIPPED"  => ['STATUS' => 'RS', 'ENUM' => "ready to ship",    'NAME' => GT($this->textMap, 'IA.READY_TO_SHIP')],
            self::QUEUE_PREFIX_FULFILLMENT . "SHIPPED"      => ['STATUS' => 'S',  'ENUM' => "shipped",          'NAME' => GT($this->textMap, 'IA.SHIPPED')],
            self::QUEUE_PREFIX_FULFILLMENT . "TOBEINVOICED" => ['STATUS' => 'RI', 'ENUM' => "ready to invoice", 'NAME' => GT($this->textMap, 'IA.READY_TO_INVOICE')],
            self::QUEUE_PREFIX_FULFILLMENT . "INVOICED"     => ['STATUS' => 'I',  'ENUM' => "invoiced",         'NAME' => GT($this->textMap, 'IA.INVOICED')],
            self::QUEUE_HIDDEN                              => ['STATUS' => 'H',  'ENUM' => "hidden",           'NAME' => GT($this->textMap, 'IA.HIDDEN_FROM_UI')],
        ];
    }

    /**
     * @return array
     */
    public static function userChangeableFields()
    {
        return array_keys(self::$okToChange);
    }




    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    //      UTILITIES TO SUPPORT CRUD AND OTHER STUFF
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************


    /**
     * @param string    $fromSql        a timestamp returned from sql select statement without any formatting
     *
     * @return string                   a timestamp as we want internally
     */
    public static function SqlTimestampToIntacctTimestamp($fromSql)
    {
        if ($fromSql == null) { // no timestamp yet?
            return null;
        }

        /* *******************
        static $interval = null;
        if ($interval === null) {
            $offsets  = ProcessUserTimeZoneOffsets();    // this could be slow and we do this A LOT
            $hours    = $offsets[0] ?? 0;
            $mins     = $offsets[1] ?? 0;
            $relative = "";
            if ($hours != 0) {
                $relative = "$hours hours ";
            }
            if ($mins != 0) {
                $relative = "$mins minutes ";
            }
            if ($relative == '') {
                $relative = "0 minutes";    // not really useful, only applies to folks in GMT
            }
            $interval = DateInterval::createFromDateString($relative);
        }
        *********************** */

        $rtn = $fromSql;
        // from: 2021-08-05 18:11:51.694169
        // to  : MM-DD-YYYY HH24:MI:SS
        $timestamp = DateTime::createFromFormat('Y-m-d H:i:s.u', $fromSql, Globals::$g->utcDateTimeZone);
        if ($timestamp !== false) {
            // $timestamp->add($interval);
            $rtn = $timestamp->format('m/d/Y H:i:s'); // 'm-d-Y H:i:s'
        }
        return $rtn;
    }


    /**
     *      Fix timestamps: the plain read gets timestamps in a format writing does not want!
     *              It gets YYYY-MM-DD HH:MM:SS.nnnn, but later we'll want MM/DD/YYYY HH:MM:SS
     *              Fix here.
     *
     * @param array   $row      in and out: one read record (from get() or getList())
     */
    public static function fixTimestampsInRecord(& $row)
    {
        static $fixTheseTimestamps = [
            'PICKLISTPRINTED', 'PACKLISTPRINTED', 'WHENCREATED', 'WHENMODIFIED'
        ];

        foreach ($fixTheseTimestamps as $field) {
            if (isset($row[$field])) {
                $row[$field] = self::SqlTimestampToIntacctTimestamp($row[$field]);
            }
        }
    }


    /**
     *  Add a note to the record that a customer can see (or us on an escalation!)
     *
     * @param array     $iwqRecord      An InventoryWorkQueue record or an InventoryWQDetail record
     * @param string    $textToAdd      What to add to notes
     */
    public static function addNote(& $iwqRecord, $textToAdd)
    {
        $noteNow = $iwqRecord['REFERENCE2'] ?? '';
        if ($noteNow != '') {
            $noteNow .= "; ";
        }
        $noteNow .= $textToAdd;
        if (strlen($noteNow) < self::REFERENCE2_FIELD_LENGTH) {
            $iwqRecord['REFERENCE2'] = $noteNow;
        }
    }


    /**
     *  Clear the note, if any
     *
     * @param array     $iwqRecord      An InventoryWorkQueue record or an InventoryWQDetail record
     *
     */
    public static function clearNote(& $iwqRecord)
    {
        $iwqRecord['REFERENCE2'] = '';
    }


    /**
     *      Get a bunch of records by work key; this gets the raw data, not the external form (use get() for that)
     *
     * @param int[]         $workKeys           The array of docentry record's "workkey" field
     * @param array|false   $iwqs               The relevant record per docentry
     * @param bool          $includeCompleted   Shall I include 'completed' records or not?
     *
     * @return bool                             Did it work?
     */
    public function getByWorkKey($workKeys, & $iwqs, $includeCompleted = false)
    {
        $qry   = [];
        $qry[] = "select * from icworkqueue where cny# = :1 ";
        $qry[] = GetMyCompany();
        if ( ! $includeCompleted) {
            $qry[0] .= " and ((completed is null) or (completed = 'F')) ";
        }
        $qry  = PrepINClauseStmt($qry, $workKeys, " and workkey ");
        $iwqs = QueryResult($qry);
        if ($iwqs === false) {
            return false;
        }

        foreach ($iwqs as $i => $iwq) {
            $iwqs[$i]['RECORDNO']           = $iwq['RECORD#'];        // internal-->external
            $iwqs[$i]['COMPLETED']          = ($iwq['COMPLETED']    === 'T') ? 'true' : 'false';
            $iwqs[$i]['HOLDPROGRESS']       = ($iwq['HOLDPROGRESS'] === 'T') ? 'true' : 'false';
            self::fixTimestampsInRecord($iwqs[$i]);
        }
        return true;
    }


    /**
     *      Get a bunch of records by work key; this gets the raw data, not the external form (use get() for that)
     *
     * @param int[]         $records            The array of docentry record's "workkey" field
     * @param array         $iwqs               The relevant record per docentry (returned)
     * @param bool          $includeTracking    Include tracking data?
     *
     * @return bool                             Did it work?
     */
    public function getByRecordNumber($records, & $iwqs, $includeTracking = false)
    {
        $iwqs  = [];
        if (empty($records)) {
            return true;
        }
        $qry   = [];
        $qry[] = "select * from icworkqueue where cny# = :1 ";
        $qry[] = GetMyCompany();
        $qry   = PrepINClauseStmt($qry, $records, " and record# ");
        /** @var array|bool $iwqs    otherwise it is defined as string[][] from QueryResult */
        $iwqs  = QueryResult($qry);
        if ($iwqs === false) {
            return false;
        }

        $index = [];
        foreach ($iwqs as $i => $iwq) {
            // clean up like the entity manager would have
            $iwqs[$i]['RECORDNO']           = $iwq['RECORD#'];        // internal-->external
            $iwqs[$i]['COMPLETED']          = ($iwq['COMPLETED']    === 'T') ? 'true' : 'false';
            $iwqs[$i]['HOLDPROGRESS']       = ($iwq['HOLDPROGRESS'] === 'T') ? 'true' : 'false';
            $iwqs[$i]['TRACKINGENTRIES']    = [];
            self::fixTimestampsInRecord($iwqs[$i]);
            $index[$iwq['RECORD#']]         = $i;   // on the chance we're including tracking
        }

        if ($includeTracking) {
            $query = [
                'filters' => [[[ 'WORKQUEUEKEY', 'IN', array_unique($records)]]]
            ];

            $trackingManager = Globals::$g->gManagerFactory->getManager('inventoryworkqueuedetails');
            $iwqds           = $trackingManager->GetList($query);

            // put the records onto the right parent
            foreach ($iwqds as $iwqd) {
                $idx = $index[$iwqd['WORKQUEUEKEY']];   // must be there
                $iwqs[$idx]['TRACKINGENTRIES'][] = $iwqd;
            }
        }
        return true;
    }


    /**
     * @param array  $docEntries        doc entry records; on return may have an ['IWQ'] entry
     *                                      with an array of Inventory Work Queue records
     * @param bool   $includeCompleted  optional flag to include the completed records or not, default is to NOT include them.
     *
     * @return bool
     */
    public function getIWQsForDocEntries(&$docEntries, $includeCompleted = false)
    {
        // the de records may have been exploded into separate records because of kits.
        // here, match on item/warehouse to disambiguate them.

        // Step 1) figure out what to get
        $workKeys = [];
        $deIndexes = [];
        foreach ($docEntries as $i => $row) {
            if (isset($row['WORKKEY'])) {
                $itemId      = $row['ITEMID'];
                $warehouseId = $row['WAREHOUSEID'];
                $workKey     = $row['WORKKEY'];
                $workKeys[$workKey] = true; // weed out dups from kits
                $deIndexes[$workKey][$itemId][$warehouseId][] = $i;
            }
        }

        // Step 2) if there ARE Work Queue records to get, get them
        if (!empty($workKeys)) {
            $ok = $this->getByWorkKey(array_keys($workKeys), $iwqs, $includeCompleted);
            if (!$ok) {
                return false;
            }

            // Step 3) now match the Work Queue records to the Doc Entry records
            foreach ($iwqs as $iwq) {
                $itemId      = $iwq['ITEMID'];
                $warehouseId = $iwq['WAREHOUSEID'];
                $workKey     = $iwq['WORKKEY'];
                $indexes     = $deIndexes[$workKey][$itemId][$warehouseId] ?? [];
                foreach ($indexes as $deIndex) {
                    $docEntries[$deIndex]['IWQ'][] = $iwq;  // save it, there can be multiples
                }
            }
        }
        return true;
    }


    /**
     *      A document was updated (not deleted) and the ROWS may have changed record#s, and, in general,
     *  the RESERVE or COMMITTED item activity records may have been deleted.
     *  Add any missing records.
     *
     * @param int  $dochdrkey       The document that changed
     *
     * @return bool
     * @noinspection PhpUnusedParameterInspection
     */
    public static function documentWasUpdated($dochdrkey)
    {
        return true;

        // for now I'm commenting this out.
        // A) I improved the dochdr trigger to not remove our item activity records
        // B) Things have changed since I originally wrote this.  When I wrote this,
        //    each change had a separate record.  Now the HISTORY has new record numbers,
        //    but the active records live on.
        //
        //  So, if this is still needed, the new plan should be:
        //  1) See if there are ANY reserved/allocated for this document (or line items?); if so nothing to do.
        //  2) Read all the relevant inventory work queue records and reconstruct the sequence of events
        //     that had been in the item activity table, and then write THOSE.

        /*
        $cny       = GetMyCompany();
        $dochdrkey = (int)$dochdrkey + 0;   // just make absolutely sure it is an integer to avoid sql injection

        // We want to get work queue records that have a delta reserve or allocation,
        //      where there are not corresponding item activity records
        //      and then we want to ADD those item activity records
        $sql   = [];
        $sql[] = "
            DECLARE
                v_cny               NUMBER(15,0);
                v_dochdrkey         NUMBER(15,0);
                v_totalkeyReserve   NUMBER(15,0);
                v_totalkeyAllocate  NUMBER(15,0);
                v_firstTime         CHAR(1);
            BEGIN
                v_cny       := $cny;
                v_dochdrkey := $dochdrkey;
                v_firstTime := 'T';
                

                FOR addrec IN (
                    SELECT  q.record# qrecno, q.itemid, q.warehouseid, q.deltareserve, q.deltaallocation,
                            q.whenmodified, d.whenmodified as ddate, d.record# as docentrykey, d.locationkey, d.deptkey
                      FROM  icworkqueue q, docentrymst d
                      WHERE q.cny#    = v_cny  AND q.dochdrkey = v_dochdrkey
                      AND   d.cny#    = q.cny# AND d.dochdrkey = q.dochdrkey
                      AND   d.workkey = q.workkey
                      AND   (((q.deltareserve IS NOT NULL) AND (q.deltareserve != 0)) OR ((q.deltaallocation IS NOT NULL) AND (q.deltaallocation != 0))) 
                      AND   NOT EXISTS ( 
                                SELECT 1 
                                FROM icitemactivity i 
                                WHERE i.cny# = v_cny AND i.parentdochdrkey = v_dochdrkey AND i.reference = q.record#
                            )
                ) LOOP
                    -- do this once, and only if there are records to add.....
                    IF (v_firstTime  = 'T') THEN
                        v_firstTime := 'F';
                        
                        SELECT record# INTO v_totalkeyReserve FROM ictotal
                        WHERE
                                cny# = v_cny
                          AND   name = 'RESERVED';
                          
                        SELECT record# INTO v_totalkeyAllocate FROM ictotal
                        WHERE
                                cny# = v_cny
                          AND   name = 'ALLOCATED';
                    END IF;

	                IF (addrec.deltareserve != 0) THEN
                        INSERT INTO icitemactivity (
                            cny#,
                            docentrykey,
                            parentdochdrkey,
                            itemkey,
                            warehousekey,
                            totalkey,
                            quantity,
                            value,
                            whencreated,
                            reference,
                            auwhencreated,
                            locationkey,
                            deptkey
                        ) VALUES (
                            v_cny, addrec.docentrykey, v_dochdrkey, addrec.itemid, addrec.warehouseid, v_totalkeyReserve,
                            addrec.deltareserve, 0, addrec.ddate, addrec.qrecno, addrec.whenmodified, addrec.locationkey, addrec.deptkey
                        );
	                END IF;
 	                IF (addrec.deltaallocation != 0) THEN
                        INSERT INTO icitemactivity (
                            cny#,
                            docentrykey,
                            parentdochdrkey,
                            itemkey,
                            warehousekey,
                            totalkey,
                            quantity,
                            value,
                            whencreated,
                            reference,
                            auwhencreated,
                            locationkey,
                            deptkey
                        ) VALUES (
                            v_cny, addrec.docentrykey, v_dochdrkey, addrec.itemid, addrec.warehouseid, v_totalkeyAllocate,
                            addrec.deltaallocation, 0, addrec.ddate, addrec.qrecno, addrec.whenmodified, addrec.locationkey, addrec.deptkey
                        );
	                END IF;
                END LOOP;
            END; ";
        $iwqs  = ExecStmt($sql);
        return ($iwqs !== false);
        */
    }


    /**
     *      Add the document type to the record if not already there.  Let's hope it IS already there....
     *
     * @param array     $oneRec     One inventoryworkqueue record
     *
     * @return bool
     */
    private function addDocType( & $oneRec)
    {
        $docHdrKey = $oneRec['DOCHDRKEY'] ?? 0;
        return InvBizLogicForWD::typeOfTD($docHdrKey);
    }


    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    //      CRUD ROUTINES
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************


    /**
     *      override of EntityManager regularAdd()
     *
     * Note: if the docentry record you are building these from has no 'WORKKEY', fill in the
     *      docentry RECORDNO into the WORKKEY field
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = $this->validate($values, true);

        // set the group for each value if need be
        if (!isset($values[0]) || !is_array($values[0])) {
            $this->setGroup($values);
        } else {
            foreach ($values as $index => $oneValue) {
                $this->setGroup($values[$index]);
            }
        }

        $ok = $ok && parent::regularAdd($values);

        return $ok;
    }


    /**
     *      override of Entity Manager regularSet()
     *
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        // must have these by this point!
        $ok = $this->validate($values, false);
        if ( ! $ok) {
            return $ok;
        }

        // we may get an array of values, or a single value.
        //  This is what the Entity Manager does.....
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }
        $ok = $ok && $this->cacheTaskListItems($groupOfValues);

        // we will be updating the groupOfValues, so don't foreach() on it
        $addThese = [];
        $limit = count($groupOfValues);
        for ($key = 0; $key < $limit; $key++) {
            // the record SHOULD BE THERE in the cache
            $rec = $groupOfValues[$key]['RECORDNO'] ?? ($groupOfValues[$key]['RECORD#'] ?? 0);
            if ($rec) {
                if ( ! isset($this->cachedReserved[$rec])) {
                    throw new Exception("[Code Bug] cache does not have $rec");
                }
                // If the record changed, perhaps we need to COMPLETE this record and ADD a new record?
                $ok = $ok && $this->maybeCloneRecord( $groupOfValues[$key], $this->cachedReserved[$rec], $addThese );
            } else {
                throw new Exception("[Code Bug] Calling Set() with no RECORDNO");
            }
        }
        if ( ! empty($addThese)) {
            $ok = $ok && parent::regularAdd($addThese); // add before set so the timestamp works better
        }
        $ok = $ok && parent::regularSet($values);
        return $ok;
    }


    /**
     *      A more direct set, that allows updating completed records
     *  with no other checking.  BE CAREFUL!
     *
     * @param array $values     same as set()
     *
     * @return bool
     */
    public function setCompleted(&$values)
    {
        return parent::regularSet($values);
    }


    /**
     * Delete a record (or records) from the database
     *
     * Well, hold on a minute there!  We want to keep these for history.  Also, the records are 'chained' together
     * so active records point back to deleted records.
     *
     * Any currently allocated or reserve quantities are backed out
     *
     * @param int|int[] $ID(s) vid of entity
     *
     * @return bool
     */
    function Delete($ID)
    {
        if (is_array($ID)) {
            $IDs = $ID;
        } else {
            $IDs = [ $ID ];
        }

        $source = "Delete";
        $ok     = $this->_QM->beginTrx($source);
        if ($ok === false) {
            return $ok;
        }

        // You can't actually DELETE them, but you can mark them as COMPLETED.
        // Doing so should take any allocated or reserved quantity OUT.
        // Because we want to remove any reserve/allocated amounts, we need to change the deltas FIRST,
        //  as the DB trigger ignores completed records.
        $sql = [];
        // first back out the quantities
        $sql[] = "UPDATE icworkqueue SET deltareserve = - quantityinreserve, deltaallocation = - quantityinallocation
                        WHERE cny# = :1 AND completed != 'T' and 
                              ((quantityinreserve is not null and quantityinreserve != 0) OR (quantityinallocation is not null and quantityinallocation != 0))
                              AND ((Select itemtype from icitemmst i where i.cny#=:1 and i.itemid = icworkqueue.itemid) IN ('I', 'SK'))";
        $sql[] = GetMyCompany();
        $sql   = PrepINClauseStmt($sql, $IDs, ' and record# ' );
        $ok    = ExecStmt($sql);
        if ($ok === true) {
            // now mark it completed, with the same parameters as above
            $sql2   = [];
            $sql2[] = "UPDATE icworkqueue SET completed = 'T'
                          WHERE cny# = :1 AND completed != 'T' ";
            $sql2[] = GetMyCompany();
            $sql2   = PrepINClauseStmt($sql2, $IDs, ' and record# ' );
            $ok     = ExecStmt($sql2);
        }
        if (($ok !== false) && !HasErrors()) {
            $this->_QM->commitTrx($source);
        } else {
            $this->_QM->rollbackTrx($source);
            $ok = false;
        }
        return $ok;
    }


    /**
     *      Did required fields get passed?
     *
     * @param bool  $isAnAdd
     * @param array $values
     *
     * @return bool
     */
    protected function validate(&$values, $isAnAdd)
    {
        $ok    = true;
        $error = '';

        $requireOnAdd = [
            'WORKKEY'       => 0,
            'DOCHDRKEY'     => 0,
            'PLACE'         => '',
            'ITEMID'        => '',
            'WAREHOUSEID'   => '',
            'QUANTITY'      => -1,         // it CAN be zero
            'UOM'           => '',
            'UOMFACTOR'     => 0,
        ];

        $requireOnSet = [   // require everything from $requireOnAdd, AND.....
            'RECORDNO'   => 0,
        ];

        // we may get an array of values, or a single value.
        //  This is what the Entity Manager does.....
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        foreach ($groupOfValues as $key => $row) {
             // On both add and set, we need the 'require on add' fields.....
            foreach ($requireOnAdd as $field => $cantBe) {
                if ((!isset($row[$field])) || ($row[$field] == $cantBe)) {
                    $ok = false;
                    $error = sprintf('The %1s field on row %2s is required.', $field, $key+1);
                    $errorCode = 'INV-0850';
                    $placeholder = ['FIELD' => $field, 'KEY_PLUS_1' => $key + 1];
                    break;
                }
            }

            if ($ok) {
                if ($isAnAdd) {
                    unset($groupOfValues[$key]['RECORDNO']); // just in case
                } else {
                    foreach ($requireOnSet as $field => $cantBe) {
                        if ((!isset($row[$field])) || ($row[$field] == $cantBe)) {
                            $ok = false;
                            $error = sprintf('The %1s field on row %2s is required.', $field, $key+1);
                            $errorCode = 'INV-1005';
                            $placeholder = ['FIELD' => $field, 'KEY_PLUS_1' => $key + 1];
                            break;
                        }
                    }
                }
            }
            if ( ! $ok) {
                break;
            }
            // in case the client forgot, get the internal doc type
            if ( ! isset($row['DOCUMENTTYPE'])) {
                $this->addDocType($groupOfValues[$key]);
            }
        }
        if (!$ok) {
            Globals::$g->gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $error, $placeholder, '', [], '', []);
        }
        return $ok;
    }


    /**
     *  On an add, what GROUP should this be?
     * - it can be set by the caller
     * - it can be set to the magic value 'FROM <record#>'
     * - if null, it will be set to 1.
     *
     * @param array $values             An InventoryWorkQueue record
     */
    private function setGroup( & $values)
    {
        $group = $values['GROUP'] ?? 1;
        if (substr($group, 0, strlen(self::GROUP_FROM)) === self::GROUP_FROM) {
            $source = substr($group, strlen(self::GROUP_FROM) );
            $query = [
                'select' => ['GROUP'],
                'filters' => [[[ 'RECORDNO', '=', $source]]]
            ];
            $results = $this->GetList($query);
            if ($results !== false) {
                $group  = $results[0]['GROUP'] ?? 1;
            }
        }
        $values['GROUP'] = $group;
    }


    /**
     *      Did we get all the data we need/expect?
     *  Some entry points into InventoryWQDetailManager will end up creating an
     *  InventoryWorkQueue record from one of his records.  Here, lets make sure
     *  we have all the fields we need/expect
     *
     * @param array     $docEntry       One InventoryWQDetail record
     * @param bool      $forSet         for updating a record, not creating it
     *
     * @return bool                     is it ok?
     */
    private function validateIWQDetailRecord($docEntry, $forSet)
    {
        $neededForAdd = [
            'DOCHDRKEY', 'STATUS', // in its internal format
            'ITEMID', 'WAREHOUSEID', 'QUANTITY', 'UOM', 'CONVFACTOR',
            'LINENO', 'ORDERDATE', 'WORKKEY',
        ];

        $neededForSet = [   // In ADDITION to the add
            'IWQKEY',
        ];

        foreach ($neededForAdd as $field) {
            if ( ! isset($docEntry[$field]) || ($docEntry[$field] === '') || ($docEntry[$field] === 0)) {
                Globals::$g->gErr->addIAError(
                    'INV-0704', __FILE__ . ':' . __LINE__,
                    sprintf('Set the %s field when writing an inventory work queue record', $field),
                    ['FIELD' => $field]
                );
                return false;
            }
        }
        if ($forSet) {
            foreach ($neededForSet as $field) {
                if (!isset($docEntry[$field]) || ($docEntry[$field] === '') || ($docEntry[$field] === 0)) {
                    Globals::$g->gErr->addIAError(
                        'INV-0705', __FILE__ . ':' . __LINE__,
                        sprintf('Expected field %s to be set when updating an Inventory Work Queue record', $field),
                        ['FIELD' => $field]
                    );
                    return false;
                }
            }
        }
        return true;
    }


    /**
     *  get many records, by record number.  Or by the work key records they belong to (sort of like getByParent)
     *
     *  Same as get(), but for many records!  Gets tracking records as well!
     *      (And, maybe not by the work queue record numbers, but by their work key from the docentry records)
     *
     *
     * @param int[]     $records                    work queue record numbers, docentry record numbers, or dochdr record#
     * @param int       $recordNumbersOfType        Docentry record numbers, Work Keys, or DocHdr record#??
     *                                              see constants starting with GET_MANY_xxxxx
     *
     * @return bool|array                           did it work?  if so, the array of fetched records, with tracking
     *
     */
    public function getMany($records, $recordNumbersOfType)
    {
        if ( ! is_array($records)) {
            $records = [ $records ];
        }
        $recs = [];
        if ( ! empty($records)) {

            // what kind of record did they pass us?
            switch ($recordNumbersOfType) {
                case self::GET_MANY_RECORD_NUMBER:
                    $recordField = 'RECORDNO';
                    break;

                case self::GET_MANY_WORKKEYS:
                    $recordField = 'WORKKEY';
                    break;

                case self::GET_MANY_DOCHDR:
                    $recordField = 'DOCHDRKEY';
                    break;

                default:
                    throw new Exception("[Code bug] wrong record type passed to getMany()");
            }

            // get the records
            $query = [
                'filters' => [[[ $recordField, 'IN', array_unique($records)],
                               ['COMPLETED', '=', 'false']]]
            ];
            $recs = $this->GetList($query);
            if ($recs === false) {
                return false;
            }

            // index them and get ready for tracking entries
            $trackingParents = [];
            foreach ($recs as $index => $oneRec) {
                $recs[$index]['TRACKINGENTRIES'] = [];
                $trackingParents[ $oneRec['RECORDNO']] = $index;
            }

            if ( ! empty($trackingParents)) {
                // get the tracking details
                $query = [
                    'filters' => [[['WORKQUEUEKEY', 'IN', array_keys($trackingParents)]]]
                ];
                $iwqtracking = Globals::$g->gManagerFactory->getManager("inventoryworkqueuedetails");
                $tracking = $iwqtracking->GetList($query);
                if ($tracking === false) {
                    return false;
                }

                foreach ($tracking as $oneTrack) {
                    $iwq = $oneTrack['WORKQUEUEKEY'];
                    $index = $trackingParents[$iwq];
                    $recs[$index]['TRACKINGENTRIES'][] = $oneTrack;
                }
            }
        }
        return $recs;
    }


    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    //      CRUD HELPERS
    //
    //          - Maybe mark an existing record as 'COMPLETED'
    //          - MOVE some quantity to another queue (kind of a duplicate)
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************


    /**
     *      when a record is SET() it may need to be cloned.....
     *
     *  - the PLACE changes and so the current record is changed to COMPLETE and a new record is created.
     *  - the QUANTITY changes and so the current record is still active, but a new record is created in the same place.
     *  - Both the PLACE and quantity changes, so the new record is elsewhere
     *
     * @param array     $row                One row being set
     * @param array     $existingRow        What it was before the UI/API changed it
     * @param array     $addThese           Records to be added after updates.
     *
     * @return bool
     */
    protected function maybeCloneRecord( & $row, $existingRow, & $addThese )
    {
        // What changed?
        $changed            = $this->whatChanged($existingRow, $row);
        if (empty($changed)) {
            return true;    // gosh, NOTHING changed
        }

        if ($existingRow['COMPLETED'] === 'true') {
            // you cannot change a completed row; the UI won't do this, only the API
            throw new Exception("Cannot update a record that is already marked as completed ");
        }

        // Discussion: we want to keep records around for history.  But we don't normally want to fetch
        //      the old records.  So we mark old records as 'completed' and they don't show up unless you
        //      explicitly ask for them.  So, when are they completed?  Let's look at some scenarios....
        //  Change quantity, place, qty allocated, or qty reserved: yes, complete existing and create new
        //  Other changes   - we update the new record, if one, else the old record
        //
        // Now for a funky chicken: we want the record number to live for as long as possible, rather than
        // getting a new record number all the time (causing havoc elsewhere).  So, when we 'complete' a record,
        // we'll actually create the NEW record as the completed one, and the OLD record will be updated and move
        // on as not-completed.  To make this work, the trigger has to change to not force new records to have a
        // new when-created, etc.
        //
        // also, at this time, the DETAILS, if any, can live with just the ongoing record, and we don't have to
        // make copies of it in the completed state.  For now anyway....

        // do we clone the record, or just update it?
        $needNewRecord     = $changed['CLONE'] ?? false;
        $completeOldRecord = $needNewRecord;   // if we move on to a new record, then we need to complete the old one

        // if we need a new record, we'll update the existing one, so we PRESERVE THE RECORDNO
        // (it is in any tracking records and others may refer to this briefly)

        // therefore, the NEW record is the completed one.  I know, sounds backwards, but....
        if ($completeOldRecord) {
            // mark it completed and point forward to the running record number
            $newButCompletedRecord              = $existingRow;
            $newButCompletedRecord['COMPLETED'] = 'true';         // it is completed
            $recNo                              = $row['RECORDNO'] ?? $row['RECORD#'];  // and sometimes we get both
            $newButCompletedRecord['SOURCEKEY'] = $recNo;         // where we went
            unset($newButCompletedRecord['RECORDNO']);            // we're making it a new record, though
            unset($newButCompletedRecord['RECORD#']);
            unset($newButCompletedRecord['WHENCREATED'],  $newButCompletedRecord['CREATEDBY']);
            unset($newButCompletedRecord['WHENMODIFIED'], $newButCompletedRecord['MODIFIEDBY']);
            unset($newButCompletedRecord['TRACKINGENTRIES']);
            $addThese[]                         = $newButCompletedRecord;
        }
        return true;
    }


    /**
     *      What changed in the record?  ONLY CERTAIN CHANGES ARE ALLOWED
     *
     *  Note that the UI may get some fields but not all, as in the case of a LISTER, and so we
     *      want to fill in fields from the existing record into the UI record if they are missing
     *      (not empty, but missing.  e.g., if PLACE is '' that is not missing, but empty)
     *
     * @param array     $rowBefore      the record from sql (the EXISTING record)
     * @param array     $rowAfter       the record from the ui
     *
     * @return int[]                    what changed? 1 = notes or quantity, 2 = other, less important stuff
     */
    protected function whatChanged($rowBefore, &$rowAfter)
    {
        $changed = [];

        // Another hack: GROUP didn't make the cut before we had to be done with the view changes,
        //       so it doesn't normally get read with reading InventoryWQDetail records.
        //       They ARE in the InventoryWorkGroup records, which we just read ($rowBefore),
        //       so fill in the rowAfter, which may have come from InventoryWQDetail, if need be
        $groupNow    = $rowAfter['GROUP'] ?? null;
        $groupBefore = $rowBefore['GROUP'] ?? 1;
        if ($groupNow === null) {
            $groupNow = $groupBefore;
        } else if ($groupNow === self::INCREMENT_GROUP) {    // didn't know the old group, but add one to it
            $groupNow = $groupBefore + 1;
        }
        $rowAfter['GROUP'] = $groupNow;
        // ***** END OF HACK *****

        $checkThese = $this->GetGetFields();
        foreach ($checkThese as $field) {

            $changeType      = self::$okToChange[$field] ?? 0;
            $allowedToChange = ($changeType != 0);
            // $cloneRecord  = ($changeType > 0);
            $defaultType     = (($changeType == 2) || ($changeType == -2)) ? 0 : '';

            // fill in MISSING fields from the UI
            $beforeExists = isset($rowBefore[$field]);
            $afterExists  = isset($rowAfter[ $field]);
            if ($beforeExists && ( ! $afterExists)) {
                $rowAfter[ $field] = $rowBefore[$field];    // assume UI didn't read this field from SQL
            }

            $before = $rowBefore[$field] ?? $defaultType;
            $after  = $rowAfter[ $field] ?? $defaultType;
            if ($before != $after) {
                if ( ! $allowedToChange) {
                    throw new Exception("Field <$field> cannot be changed from <$before> to <$after> ");
                }
                $changed[$field] = $changeType;
                if ($changeType > 0) {
                    $changed['CLONE'] = true;
                }
            }
        }

        $oldDeltas = (($rowBefore['DELTARESERVE'] ?? 0) != 0) || (($rowBefore['DELTAALLOCATION'] ?? 0) != 0);
        if ($oldDeltas) {
            $changed['CLONE'] = true;
        }
        return $changed;
    }




    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    //      CACHE ROUTINES
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************

    /**
     *      clear Cache     - clear the cache, if one
     */
    public function clearCache()
    {
        $this->cachedDocHeader = 0;
        $this->cachedReserved  = [];
    }


    /**
     *  cache an array of work queue records
     *
     * @param array     $records            work queue records to cache from disk (not what is passed in)?
     *
     * @return bool                         did it work?
     *
     */
    private function cacheTaskListItems($records)
    {
        $ok                   = true;
        $this->cachedReserved = []; // clean out the cache
        $recordsToGet         = [];
        foreach ($records as $row) {
            $recordNumber = $row['RECORDNO'] ?? ($row['RECORD#'] ?? 0);
            $recordsToGet[$recordNumber] = true;    // eliminate dups
        }

        // get the records and index them in the cache
        $recs = $this->getMany(array_keys($recordsToGet), self::GET_MANY_RECORD_NUMBER);  // get records and tracking
        if ($recs === false) {
            return false;
        }

        foreach ($recs as $oneRec) {
            $this->cachedReserved[$oneRec['RECORDNO']] = $oneRec;
        }
        return $ok;
    }


    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    //      FULFILLMENT HELPERS
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************



    /**
     *      Assign work key records to docentries that don't have them
     *
     * @param array $docEntries     the doc entry records
     *
     * @return bool
     */
    public function assignWorkKeysToDocEntries(&$docEntries)
    {
        $ok = true;
        $assignThese = [];
        foreach ($docEntries as $index => $docEntry) {
            $recordNo = $docEntry['RECORDNO'] ?? 0;
            if ($recordNo > 0) {
                if (($docEntry['WORKKEY'] ?? 0) === 0) {
                    $assignThese[]                 = $recordNo;
                    $docEntries[$index]['WORKKEY'] = $recordNo;   // update the caller
                }
            } else {
                // remember this is called AFTER the update to EntityManager, so if it was a new
                // line it now should have a record#
                throw new Exception("[Code bug]Missing docentry recordno in assignWorkKeysToDocEntries");
            }
        }

        if ($ok && ( ! empty($assignThese))) {
            $sql   = [];
            $sql[] = "UPDATE docentrymst SET workkey = record# WHERE cny# = :1 and workkey is null ";
            $sql[] = GetMyCompany();
            $sql   = PrepINClauseStmt($sql, $assignThese, ' and record# ');
            $ok    = ExecStmt($sql);
        }
        return $ok;
    }


    /**
     *  Using the VERY SPECIFIC FORMAT of a set of values from the InventoryWQDetailManager, generate an UWQ record.
     *
     * @param   array       $docEntry       the detail record FROM InventoryWQDetailManager
     * @param   bool        $forSet         for updating a record, not creating it
     *
     * @return array|bool                   An InventoryWorkQueue record
     */
    public function createWorkQueueRecordFromDocEntry($docEntry, $forSet)
    {
        $workKey = $docEntry['WORKKEY']     ?? 0;
        $deKey   = $docEntry['DOCENTRYKEY'] ?? 0;
        if (($deKey > 0) && ($workKey == 0)) {  // first time?  save the dekey as the workkey
            $docEntry['WORKKEY'] = $docEntry['DOCENTRYKEY'];
        }
        if (!$this->validateIWQDetailRecord($docEntry, $forSet)) {
            return false;
        }

        self::fixTimestampsInRecord($docEntry); // they're probably great, but just in case.

        $IWQ = [
            'RECORDNO'          => $docEntry['IWQKEY'] ?? null,
            'SOURCEKEY'         => null,    // filled in on set()
            'WORKKEY'           => $docEntry['WORKKEY'],
            'DOCHDRKEY'         => $docEntry['DOCHDRKEY'],
            'PLACE'             => $this->queueForName($docEntry['STATUS']),
            'COMPLETED'         => 'false',
            'ITEMID'            => $docEntry['ITEMID'],
            'WAREHOUSEID'       => $docEntry['WAREHOUSEID'],
            'QUANTITY'          => $docEntry['QUANTITY'],
            'UOM'               => $docEntry['UOM'] ?? '',
            'UOMFACTOR'         => $docEntry['CONVFACTOR'] ?? 1, // different names!
            'NOTES'             => $docEntry['NOTES'] ?? null,
            'PACKCONTAINER'     => $docEntry['PACKCONTAINER'] ?? null,
            'REFERENCE'         => $docEntry['SHIPTRACKING'] ?? null,
            'PICKCONTAINER'     => $docEntry['PICKCONTAINER'] ?? null,
            'REFERENCE2'        => $docEntry['REFERENCE2'] ?? null,
            'HOLDPROGRESS'      => $docEntry['HOLDPROGRESS'] ?? 'false',
            'ASSIGNEDTO'        => $docEntry['ASSIGNKEY'] ?? null,        // this is an employee record#
            'LINENO'            => $docEntry['LINENO'],
            'ORDERDATE'         => $docEntry['ORDERDATE'],
            'PICKLISTPRINTED'   => $docEntry['PICKLISTPRINTED'] ?? null,
            'PACKLISTPRINTED'   => $docEntry['PACKLISTPRINTED'] ?? null,
            'QUANTITYINRESERVE'     => $docEntry['QUANTITYINRESERVE'] ?? null,
            'QUANTITYINALLOCATION'  => $docEntry['QUANTITYINALLOCATION'] ?? null,
            'DELTARESERVE'          => $docEntry['DELTARESERVE'] ?? null,
            'DELTAALLOCATION'       => $docEntry['DELTAALLOCATION'] ?? null,
            'QUANTITYPICKED'        => $docEntry['QUANTITYPICKED'] ?? null,
            'QUANTITYPACKED'        => $docEntry['QUANTITYPACKED'] ?? null,
            'ORIGINALDOCID'         => $docEntry['ORIGINALDOCID'] ?? null,
            'DOCUMENTTYPE'          => $docEntry['DOCUMENTTYPE'] ?? null,
            'GROUP'                 => $docEntry['GROUP'] ?? null,  // if not there, it gets fixed up on save

            // the tracking entries BELONG to the inventory work queue records, but
            // they are 'borrowed' by the inventorywqdetail records so the UI and API can see
            // them and update them.
            'TRACKINGENTRIES'       => $docEntry['TRACKINGENTRIES'] ?? [],
        ];
        return $IWQ;
    }


    /**
     *      Resurrect The Dead
     *
     *  When a shipper or invoice is deleted, we want the prior transaction to be re-instated in Fulfillment
     *  in the same places it was before the conversion.
     *
     *  For example,
     *      You have a Sales Order with two bundles, one in Ready to Ship and one in Ready to Pack.
     *      You convert the bundle in Ready to Ship, leaving behind the other bundle.
     *      Now the SO is partially converted, with just one bundle left in Ready to Pack state.  The
     *          Ready to Ship bundle is gone.
     *
     *      Then you delete the shipper.
     *      We want to restore the Ready to Ship bundle back in Fulfillment just as it was.
     *      Which means, any bundles that had been converted to this new transaction and left as 'completed'
     *          should be put back as 'not completed' and any DELTA allocated/reserved is REVERSED (sign change).
     *
     *
     * @param array     $sourceDocHdr           just the doc hdr fields (from BaseGet()) for the new document
     * @param array     $docBeingDeleted        which document is being deleted?
     *
     * @return bool
     */
    public function ResurrectTheDead($sourceDocHdr, $docBeingDeleted) {

        //  ******************************************************
        //  ******************************************************
        //
        //  Helpers (sub-functions)
        //
        //  ******************************************************
        //  ******************************************************

        /**
         *  Should we even be here?
         *
         * @param array  $sourceDocHdr      just the doc hdr fields (from BaseGet()) for the new document
         *
         * @return bool
         */
        $weShouldBeHere = function($sourceDocHdr) {
            // are we enabled?  Is there a record number?
            if (isset($sourceDocHdr['RECORDNO']) && ($sourceDocHdr['RECORDNO'] != 0)) {
                return InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_EITHER, $sourceDocHdr);
            }
            return false;
        };


        /**
         *      Given a doc header record number, get all the relevant, if any, work queue records to recover
         *
         * @param int   $docHdrRecordNumber     the record number of the document the records were CONVERTED TO
         *
         * @return array|bool
         */
        $getPriorTransactionWorkQueueRecords = function($docHdrRecordNumber, $deletedDocRecordNumber) {
            // we want completed records that were converted to this document and belong to the original document
            $query = [
                'filters' => [[ [ 'DOCHDRKEY',   '=', $docHdrRecordNumber],
                                [ 'CONVERTEDTO', '=', $deletedDocRecordNumber],
                                [ 'COMPLETED',   '=', 'true']]]
            ];
            $records = $this->GetList($query);  // we don't want owned records like the tracking....
            if ($records === false) {
                $records = [];
            }
            return $records;    // may be empty!
        };


        /**
         *  Simulate 'maybeCloneRecord()', above, but work in the case where the old record is COMPLETED,
         *  which it is, and not complain.  Yes, this is very unusual, but, heck, we're raising the dead.
         *
         * @param array  $existingRow
         *
         * @return array mixed
         */
        $funkyChickenClone = function( & $existingRow) {
            // simulate the cloning in maybeCloneRecord(), above
            $newButCompletedRecord              = $existingRow;
            $newButCompletedRecord['COMPLETED'] = 'true';         // it is completed
            $recNo                              = $existingRow['RECORDNO'] ?? $existingRow['RECORD#'];  // and sometimes we get both
            $newButCompletedRecord['SOURCEKEY'] = $recNo;         // where we went
            unset($newButCompletedRecord['RECORDNO']);            // we're making it a new record, though
            unset($newButCompletedRecord['RECORD#']);
            unset($newButCompletedRecord['TRACKINGENTRIES']);
            return $newButCompletedRecord;
        };


        /**
         *  Take the old completed work queue records, polish them, put on a new coat of paint,
         *  so they can be saved as new records.
         *
         * @param array     $workQueueRecords       completed old work queue records in,
         *                                          shiny new work queue records back out!
         * @param array     $docBeingDeleted        document tree of the doc being deleted
         *
         * @return array                            the NEW, old record (archive of what it was before revival)
         *                                          (similar to what 'maybeCloneRecord' will do)
         */
        $reviveOldRecords = function( & $workQueueRecords, $docBeingDeleted) use ($funkyChickenClone) {

            $rowsToAdd = [];
            $text = ContractUtil::GTP($this->textMap, 'IA.RECOVERED_WHEN_DOC_DELETED', ['DOC_ID' => $docBeingDeleted['DOCID']]);
            foreach ($workQueueRecords as $index => $row) {

                // save off a copy of the record to be written AS IF we went through 'maybeCloneRecord'
                $rowsToAdd[] = $funkyChickenClone($workQueueRecords[$index]);

                // let's assume we were taken down to allocation/reserve of zero
                //    by using the deltas.  Here, we reverse them out.
                // note by setting completed to false, we effectively turn ON any
                //    reservations and allocations in tracking records assigned to this record
                $workQueueRecords[$index]['COMPLETED']       = 'false';
                $workQueueRecords[$index]['DELTAALLOCATION'] = - $row['DELTAALLOCATION'];
                $workQueueRecords[$index]['DELTARESERVE']    = - $row['DELTARESERVE'];
                $workQueueRecords[$index]['CONVERTEDTO']     = 0;
                InventoryWorkQueueManager::clearNote($workQueueRecords[$index]);
                InventoryWorkQueueManager::addNote(  $workQueueRecords[$index], $text);
            }
            // return the rows to be added as the ARCHIVE of the row we are resurrecting
            return $rowsToAdd;
        };



        //  ******************************************************
        //  ******************************************************
        //
        //  Main code for the routine
        //
        //  ******************************************************
        //  ******************************************************

        $ok = true;
        if ($weShouldBeHere($sourceDocHdr)) {
            $workQueueRecords = $getPriorTransactionWorkQueueRecords($sourceDocHdr['RECORDNO'], $docBeingDeleted['RECORDNO']);
            // often, there won't be ANY old records!!
            // like, the prior transaction wasn't in fulfilment, for example.
            if ( ! empty($workQueueRecords)) {
                $rowsToAdd = $reviveOldRecords($workQueueRecords, $docBeingDeleted);

                // Discussion:
                // Normally, one would go through set(), above, and get all the good edit checks and such.
                // AND it would go through 'maybeCloneRecord', which keeps a copy of the record for archival
                // purposes.  We've done that above in $funkyChickenClone(), because set() also expects the
                // existing records to be NOT completed and other issues.  This is an unusual situation, so,
                // I'm taking shortcuts....
                $ok = $ok && parent::regularAdd($rowsToAdd);        // add the old records before we save the new ones so the timestamps work
                $ok = $ok && parent::regularSet($workQueueRecords);
            }
        }
        return $ok;
    }


    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    //      HELPER ROUTINES
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************


    /**
     *      counts per queue
     *
     *  Each PLACE and STATUS is returned along with the count.  This indicates how many 'bundles' are in each place.
     *
     * @return array
     */
    public function countsPerQueue()
    {
        $sql    = [];
        $sql[]  = "select place, count(DISTINCT (DOCHDRKEY || '--' || WAREHOUSEID)) as count
                    from icworkqueue WHERE cny# = :1 and ((completed = 'F') or (completed is NULL)) 
                    group by place order by place ";
        $sql[]  = GetMyCompany();
        $result = QueryResult($sql);
        if ($result === false) {
            $result = [];
        }
        foreach ($result as $index => $row) {
            $result[$index]['STATUS'] = $this->statusForQueue($row['PLACE']);
        }
        return $result;
    }


    /**
     *  Given a document, which docentry records have work queue records?
     *  (and docentry is represented NOT by the docentry record#, but by
     *  its WORKKEY)
     *
     * Returns an array, indexed by WORKKEY, with the COUNT of how many work queue records there are in it.
     *
     * @param int   $dochdrkey      The dochdr record#
     *
     * @return array[]|false
     */
    public function documentEntriesInFFByDocHdrKey($dochdrkey)
    {
        $ret = [];
        if ($dochdrkey) {
            // get the work keys for this document that have work queue records
            $query = [
                'select'  => ['WORKKEY', 'QUANTITY'],
                'filters' => [[['DOCHDRKEY', '=', $dochdrkey],
                    ['COMPLETED', '=', 'false']]]
            ];
            $recs = $this->GetList($query);
            if ($recs === false) {
                return false;
            }

            foreach ($recs as $rec) {
                $workKey = $rec['WORKKEY'];
                if (!isset($ret[$workKey])) {
                    $ret[$workKey] = 0; // first one found!
                }
                $ret[$workKey] = ibcadd($ret[$workKey], $rec['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
            }
        }
        return $ret;
    }


    /**
     *  An arbitrary value roughly meaning 'distance from open'
     *
     * @param string    $place          The place
     *
     * @return int|bool                 Numeric place rank, lower is "closer to OPEN"
     */
    public function placeValue($place)
    {
        $status = $this->statusForQueue($place);
        return array_search($status, ['H', 'O', 'RPI', 'PI', 'RPA', 'PA', 'RS', 'S', 'RI', 'I']);
    }


    /**
     *  static queue information: given a queue name, return STATIC info about that queue.
     *
     * Someday we'll want some better management of what queues are in which subsystem.  For example,
     * a customer may be able to define their own queues in a TD.  But, for now, we're hardcoded....
     *
     *
     * @param string    $queueName  the name of the queue
     *
     * @return string[]             the data about the queue
     */
    public function staticQueueInformation($queueName)
    {
        return $this->staticQueueInformationTable[$queueName] ?? [];
    }


    /**
     *      Given an action like 'RS', what queue would that put things on?  (Ready To SHIP)
     *
     * @param   string          $action     Which action are you looking for?
     *
     * @return  string                      Queue name or empty
     */
    public function queueForAction($action)
    {
        foreach ($this->staticQueueInformationTable as $queue => $row) {
            if ($row['STATUS'] == $action) {
                return $queue;
            }
        }
        return '';
    }


    /**
     *      Given a name like 'Readt to ship' or 'ready to ship', what queue would that put things on?
     *
     * @param   string          $name       Which English/translated name are you looking for?
     *
     * @return  string                      Queue name or empty
     */
    public function queueForName($name)
    {
        // there is the ENUM value, which looks like English and doesn't change,
        // and there is the NAME, which is internationalized and could change.
        // handle both here
        foreach ($this->staticQueueInformationTable as $queue => $row) {
            if (($row['ENUM'] === $name) || ($row['NAME'] === $name)) {
                return $queue;
            }
        }
        // not found?  maybe they passed in an INTERNAL name, like 'RPI'?
        return $this->queueForAction($name);
    }


    /**
     *      Given a queue like 'OPEN', what is the action/status name for that ?
     *
     * @param   string          $queueToFind     Which queue are you looking for?
     *
     * @return  string                           status or action or empty
     */
    public function statusForQueue($queueToFind)
    {
        foreach ($this->staticQueueInformationTable as $queue => $row) {
            if ($queueToFind == $queue) {
                return $row['STATUS'];
            }
        }
        return '';
    }


    /**
     *      Given a name like 'open', what is the action/status name for that ?
     *
     * @param   string          $name            Which name are you looking for?
     *
     * @return  string                           status or action or empty
     */
    public function statusForName($name)
    {
        // there is the ENUM value, which looks like English and doesn't change,
        // and there is the NAME, which is internationalized and could change.
        // handle both here
        $passes = 0;
        while ($passes < 2) {
            foreach ($this->staticQueueInformationTable as $row) {
                if (($name == $row['ENUM']) || ($name == $row['NAME'])) {
                    return $row['STATUS'];
                }
                if ($name == $row['STATUS']) {
                    return $name;   // gee, it was already a status
                }
            }
            $name = strtolower($name);  // from the API and case-wrong?
            $passes++;
        }
        return '';
    }


    /**
     *      Given a queue like 'OPEN', what is the human name for that ?
     *
     * @param   string          $queueToFind     Which queue are you looking for?
     *
     * @return  string                           status or action or empty
     */
    public function nameForQueue($queueToFind)
    {
        foreach ($this->staticQueueInformationTable as $queue => $row) {
            if ($queueToFind === $queue) {
                return $row['NAME'];
            }
        }
        return '';
    }


    /**
     *      Given a queue like 'OPEN', what is the enum (not the English name) for that ?
     *
     * @param   string          $queueToFind     Which queue are you looking for?
     *
     * @return  string                           status or action or empty
     */
    public function enumForQueue($queueToFind)
    {
        foreach ($this->staticQueueInformationTable as $queue => $row) {
            if ($queueToFind == $queue) {
                return $row['ENUM'];
            }
        }
        return '';
    }


    /**
     *      Given a status like 'O', what is the human (e.g., English) name for that ?
     *
     * @param   string          $status     Which status are you looking for?
     *
     * @return  string                       name or empty
     */
    public function nameForStatus($status)
    {
        foreach ($this->staticQueueInformationTable as $row) {
            if ($status == $row['STATUS']) {
                return $row['NAME'];
            }
        }
        return '';
    }


    /**
     *      Given a status like 'O', what is the internal enum name for that ?
     *
     * @param   string          $status     Which status are you looking for?
     *
     * @return  string                       name or empty
     */
    public function enumForStatus($status)
    {
        foreach ($this->staticQueueInformationTable as $row) {
            if ($status == $row['STATUS']) {
                return $row['ENUM'];
            }
        }
        return '';
    }


    /**
     *      Given a status like 'O', what is the internal enum name for that ?
     *
     * @param   string          $enum     Which status are you looking for?
     *
     * @return  string                       name or empty
     */
    public function nameForEnum($enum)
    {
        foreach ($this->staticQueueInformationTable as $row) {
            if ($enum == $row['ENUM']) {
                return $row['NAME'];
            }
        }
        return '';
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
     * @return array[]          result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        $result = parent::GetList($params, $_crosscny, $nocount);

        // The timestamps come out in a format we don't want.  Fix them.
        if (($result !== false) && ( ! empty($result))) {
            foreach ($result as $index => $row) {
                self::fixTimestampsInRecord($result[$index]);
            }
        }
        return $result;
    }

}

