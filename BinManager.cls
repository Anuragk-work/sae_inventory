<?php
/**
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 * 
 * @author    Manoj Mahur <mmahur@intacct.com>
 * @desc      BinManager.cls
 * @copyright 2000-2009 Intacct Corporation
 */


/*
 * class BinManager extends EntityManager
 */
class BinManager extends EntityManager
{
    const   BINID_LENGTH = 30;      // in the sql tables

    const   ADVANCED_FIELDS = [
        'WAREHOUSEKEY',
        'WAREHOUSEID',
        'SEQUENCENO',
        'STATUS',
        'PORTABLE',
        'AISLEKEY',
        'AISLEID',
        'ROWKEY',
        'ROWID',
        'ZONEKEY',
        'ZONEID',
        'FACEKEY',
        'FACEID',
        'BINSIZEKEY',
        'SIZEID',
    ];

    /** @var bool $permissiveCreate should we create AISLE/ROW/etc if they don't exist? */
    private $permissiveCreate = false;

    /** @var array $cache       a cace of bins, aisles, rows, etc.  Used for bulk operations */
    private $cache = null;      // null means 'no cache'

    /** @var bool $temporarilyAssumeAdvancedMode   for upgrade.... */
    private static $temporarilyAssumeAdvancedMode = false;

    /** @var bool $fromAPI */
    private $fromAPI = false;

    /** @var bool $useAuditTrailVid */
    public $useAuditTrailVid = false;  // off means "use normal Vid" (BinId)  public so BinEditor can set it


    /**
     * @param array $params
     */
    function __construct($params = [])
    {
        $this->permissiveCreate = false;
        $this->cache = null;
        self::$temporarilyAssumeAdvancedMode = false;
        $this->fromAPI = false;
        $this->useAuditTrailVid = false;
        parent::__construct($params);
        $this->loadTokenLabels();
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = $this->translate($values);
        $ok = $ok && $this->validate($values, true);
        $ok = $ok && parent::regularAdd($values);

        return $ok;
    }


    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Add(&$values)
    {
        $this->fromAPI = true;
        return parent::API_Add($values);
    }


    /**
     *  The UI will give us the RECORDNO and the BINID, which may be a NEW BINID.
     *  The API could do the same, but what people can do instead is this odd mix:
     *
     *  <update>
     *      <BIN>
     *          <BINID>BinID</BINID>
     *          <BINID>BinID6789012345687901234567890</BINID>
     *      </BIN>
     *  </update>
     *
     *  Where the FIRST BINID is the vid of the current record, and the SECOND is the new BIND!
     *
     *  Here we make that happen....
     *
     * @param array $values     record to be saved
     *
     * @return bool
     */
    protected function handleMultipleBins(&$values)
    {
        $binIDs = $values['BINID'] ?? '';

        // if it is an array, we go further...
        // if not, there's no more to do here.
        if (is_array($binIDs)) {
            $existingBin     = $values['BINID'][0] ?? '';
            $newBin          = $values['BINID'][1] ?? '';
            $values['BINID'] = $existingBin;    // make sure we do not return the array, which causes trouble later
            $binRecordNumber = $this->keyForId('BINID', $existingBin);
            // does this exist? (if not we'll complain later)
            if ($binRecordNumber > 0) {
                if (isset($values['RECORDNO'])) {
                    // if the record# is passed, we assume it is the same as the looked-up name.
                    if ($values['RECORDNO'] != $binRecordNumber) {
                        return true;    // it is NOT the same, later code will complain
                    }
                } else {
                    $values['RECORDNO'] = $binRecordNumber; // didn't pecify it, now have it
                }

                // by now, we have a record number, which is good, and we want to change the BINID
                // to be the NEW one, so that the rename code works
                $values['BINID'] = $newBin;

                // at this point we have RECORDNO and the new BINID, just as the UI does it....
            }
        }
        return true;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        // on the odd chance the API sends two bins, fix it to be like the UI:
        $ok = $this->handleMultipleBins($values);

        $source = 'BinManager::Set';
        $ok = $ok && $this->translate($values);
        $ok = $ok && $this->validate($values, false);
        if ($this->hasRecordChanged($values)) {
            $ok = $ok && $this->_QM->beginTrx($source);
            if ($ok) {
                $ok = $this->maybeRenameBinID($values) && parent::regularSet($values);
                if ($ok) {
                    $ok = $this->_QM->commitTrx($source);
                } else {
                    $this->_QM->rollbackTrx($source);
                }
            }
        }
        return $ok;
    }


    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Set(&$values)
    {
        $this->fromAPI = true;
        return parent::API_Set($values);
    }



    /**
     *      Has this record changed?  Only works when the cache is on, otherwise it says all records have changed...
     *
     * @param array $values
     *
     * @return bool             true if it did not change, false if it did.
     */
    protected function hasRecordChanged($values)
    {
        $existingRecordNumber = $values['RECORDNO'] ?? 0;
        if (($existingRecordNumber > 0) && ($this->cacheIsOn() == true)) {
            $existingRecord = $this->cache['BIN'][$values['BINID']] ?? null;
            if ($existingRecord !== null) { // well, it SHOULD be there....
                $changes = false;   // well, not YET
                if (self::areAdvanedBinsOn()) {
                    global $kSchemas;
                    $schema = $kSchemas['bin']['schema'];

                    foreach (self::ADVANCED_FIELDS as $field) {
                        if (isset($schema[$field]) && (strpos($schema[$field], '.') === false)) {
                            // bindesc, sequenceno, status, portable, warehousekey, zonekey, facekey, aislekey, rowkey, binsizekey
                            if (($existingRecord[$field] ?? '') != ($values[$field] ?? '')) {
                                $changes = true;
                                break;
                            }
                        }
                    }
                }
                if ($changes == false) {
                    $changes = (($existingRecord['BINDESC'] ?? '') != ($values['BINDESC'] ?? ''));  // not an 'advanced' field
                }
                if ($changes == false) {
                    return false;    // no changes, not worth writing to disk.
                }
            }
        }
        return true;
    }


    /**
     * Delete a record from the database
     *
     * Is this bin in use?  If so ---> error
     *
     * @param string|int $ID vid of entity
     *
     * @return bool
     */
    function Delete($ID)
    {
        $key = $this->keyForId('BINID', $ID);
        $qry = [];
        $qry[] = "SELECT 1 itexists FROM dual WHERE 
                        exists (select 1 from docentrycost          where cny#=:1 AND binkey=:2) OR
                        exists (select 1 from docentrycostkits      where cny#=:1 AND binkey=:2) OR
                        exists (select 1 from docentrytrackdetail   where cny#=:1 AND binkey=:2) OR 
                        exists (select 1 from docentrytrack         where cny#=:1 AND binkey=:3)
                 ";
        $qry[] = GetMyCompany();
        $qry[] = $key;
        $qry[] = $ID;
        $result = QueryResult($qry);
        $ok = ($result !== false);
        if ($ok && isset($result[0]['ITEXISTS'])) {
            Globals::$g->gErr->addIAError(
                'INV-0301',
                __FILE__ . '.' . __LINE__,
                sprintf("The bin %s cannot be deleted because it is used in one or more transactions.", $ID), ['ID' => $ID]
            );
            return false;
        }
        return parent::Delete($ID);
    }


    /**
     * Get a single record
     *
     * @param string        $ID
     * @param string[]|null $fields
     *
     * @return array|false
     */
    function getByRecordNumber($ID, $fields = null)
    {
        $result = QueryResult(["select binid from icbin where cny#=:1 and record#=:2", GetMyCompany(), $ID]);
        if (($result !== false) && ( ! empty($result))) {
            return parent::get($result[0]['BINID'], $fields);
        }
        return false;
    }


    /**
     * Override of the EntityManager function.  Adds to the 'don't return' list the advanced fields if you
     *     are in 'Classic' mode.
     *
     * This protects the API and any other get() calls.
     *
     * @return array
     */
    public function getQueryRestrictedFields()
    {
        $rtn = parent::getQueryRestrictedFields();

        // in CLASSIC mode you shouldn't get any of the new fields found in ADVANCED mode.
        // it is unlikely that these should be there, but just in case....
        if (!self::areAdvanedBinsOn()) {
            $rtn = array_merge($rtn, self::ADVANCED_FIELDS);
        }
        return $rtn;
    }


    /**
     *      get By Warehouse - this is the moral equivelent of 'getByParent()' for
     * Owned Objects.  We are NOT an Owned Object for historical / hysterical reasons,
     * but here we act like one.  Must be in Advanced mode (otherwuse there are no warehouses in the table)
     *
     *
     * @param string $warehouse     the warehouse to get all records by
     *
     * @return array                the array of records
     */
    public function getByWarehouse($warehouse)
    {
        $rtn = [];
        $warehouse = trim($warehouse ?? '');   // a little self defence
        if ($warehouse != '') {
            $result = $this->DoQuery('QRY_BIN_SELECT_BY_PARENT', [$warehouse], false);
            if ($result !== false) {
                foreach ($result as $rec) {
                    // $rtn[] = $this->_ProcessResult($rec);
                    $externalRec = $this->_ProcessResult($rec);
                    $rtn[]        = $externalRec;
                }
                // sort the results by bin
                usort($rtn, function ($a, $b) {
                    return strcoll($a['BINID'], $b['BINID']);   // case-sensitive, localle based compare
                });
            }
        }
        return $rtn;
    }


    /**
     *  The bins picklists used to show just bin id, sorted.  We want them to show the COUNT of items IN
     *  the bin, and, for outbound transactions, ONLY show those bins (on inbound you can pick any bin in the warehouse)
     *
     * @param   string $warehouse        the warehouse ID
     * @param   string $item             the item ID
     * @param   bool   $excludeEmptyBins ONLY show bins with the item in them
     * @param   array  $addlFilters      Additional filters
     *
     * @return array|bool                   the resulting list
     */
    public function getBinPicklist($warehouse, $item, $excludeEmptyBins ,array $addlFilters=[])
    {
        $return = [];

        // first, get the bins with items; there are likely FEW of these....
        $addlFilterStr=[];
        $orderByClause= " ORDER BY UPPER(binid) Asc";

        //Add additional load filters
        if( count($addlFilters) > 0){
            foreach ( $addlFilters as $filter){
                if($filter[1] ==  'NOT LIKE' || $filter[1] ==   '>'){
                    $addlFilterStr[]    = " AND UPPER(binid) ";
                    $addlFilterStr[]    = $filter[1];
                    $addlFilterStr[]    = " '" .isl_strtoupper($filter[2]) . "' ";
                }elseif ($filter[1] == 'ILIKE'){
                    if (count($filter)>3) { //first condition on the like
                        $addlFilterStr[]    = " AND ( UPPER(binid) ";
                        $addlFilterStr[]    = " LIKE ";
                        $addlFilterStr[]    = " '" .isl_strtoupper($filter[2]) . "' ";
                    }else{  //last condition on the like
                        $addlFilterStr[]    = " OR  UPPER(binid) ";
                        $addlFilterStr[]    = " LIKE ";
                        $addlFilterStr[]    = " '" .isl_strtoupper($filter[2]). "' )";
                    }
                }
            }
        }

        // so, I'm guessing that these are the entire list and I don't need docentrytrack or docentrytrackdetail records.  Ok?
        $queryString  = "SELECT b.binid, sum(de.qtyleft) totalQty 
                        FROM docentrycost de, icbin b
                        WHERE de.cny#=:1 AND de.cny#=b.cny# AND de.binkey IS NOT NULL AND de.whsekey = :2 and de.itemkey = :3 and de.binkey = b.record#
                        AND de.in_out = 'I' AND de.affects_inventory in ('V', 'QV') and de.adjdocentrycostkey IS NULL AND b.status = 'T'
                   ";
        if (count($addlFilterStr)>0){
            $queryString .=  join(' ', $addlFilterStr);
        }
        $queryString .= " GROUP BY b.binid ";
        $queryString .= $orderByClause;

        $qry    = [];
        $qry[]  =  $queryString;
        $qry[]  = GetMyCompany();
        $qry[]  = $warehouse;
        $qry[]  = $item;
        $result = QueryResult($qry);
        if ($result === false) {
            return $return;
        }
        $txns   = [];
        foreach ($result as $row) {
            $binid = $row['BINID'];
            if ( ! isset($txns[$binid])) {
                $txns[$binid] = 0;
            }
            $txns[$binid] += (int)$row['TOTALQTY'];
        }

        if ($excludeEmptyBins) {
            foreach ($txns as $id => $count) {
                $return[] = ['BINID' => $id . '-- ' . $count . ' '. I18N::getSingleToken('IA.AVAILABLE'), 'COUNT' => $count];
            }
        } else {
            if (self::areAdvanedBinsOn()) {
                $queryString = "SELECT binid 
                        FROM icbin, icwarehouse 
                        WHERE icbin.cny#=:1 and icbin.cny#=icwarehouse.cny# and icbin.warehousekey = icwarehouse.record# and icwarehouse.location_no=:2 AND icbin.status = 'T' ";
            } else {
                $queryString = "SELECT binid 
                        FROM whsebin 
                        WHERE cny#=:1 AND whsekey=:2 ";
            }
            if (count($addlFilterStr)>0){
                $queryString .=  join(' ', $addlFilterStr);
            }
            $queryString .= $orderByClause;
            $qry    = [];
            $qry[]  = $queryString;
            $qry[]  = GetMyCompany();
            $qry[]  = $warehouse;
            $result = QueryResult($qry);
            if ($result !== false) {
                foreach ($result as $row) {
                    $binid = $row['BINID'];
                    $count = $txns[$binid] ?? 0;
                    $paramCount = $count ?  ('-- ' . $count . ' '. I18N::getSingleToken('IA.PRESENT')) : '';
                    $return[] = ['BINID' => $binid . $paramCount, 'COUNT' => $count];
                }
            }
        }
        return $return;
    }


    /**
     *      Get the list of bins in use in transactions.  Not in the list?  Then not in a transaction.
     *
     * @param string      $warehouseId       which warehouse is this for?
     * @return array|bool                    an array of BINKEY (record#) --> true ('in use')
     */
    public function whichBinsAreInUse($warehouseId)
    {
        $rtn = [];
        $warehouseId = trim($warehouseId ?? '');   // a little self-defence
        if ($warehouseId != '') {
            // I'm assuming that I don't need to check docentrytrack
            $qry = [];
            $qry[] = "SELECT distinct binkey
                        FROM 
                            (
                                SELECT distinct binkey FROM  docentrycost WHERE cny#=:1 AND binkey IS NOT NULL AND whsekey = :2
                                UNION
                                SELECT distinct binkey FROM  docentrycostkits WHERE cny#=:1 AND binkey IS NOT NULL AND whsekey = :2
                                UNION
                                -- SELECT distinct binkey FROM  docentrytrack WHERE cny#=:1 AND binkey IS NOT NULL AND whsekey = :2
                                -- UNION
                                SELECT distinct det.binkey FROM  docentrytrackdetail det, docentry de
                                        WHERE det.cny#=:1 AND de.cny#=:1 AND det.binkey IS NOT NULL 
                                        AND det.docentrykey = de.record# AND de.warehousekey = :2
                            )
                        ORDER BY binkey ";
            $qry[] = GetMyCompany();
            $qry[] = $warehouseId;
            $result = QueryResult($qry, 0, '', NULL, false); // NO HEADERS
            $ok = ($result !== false);
            if ($ok) {
                foreach ($result as $row) {
                    $rtn[$row[0]] = true;   // remember, no headers, so [0] IS the binkey
                }
            }
        }
        return $rtn;
    }


    /**
     *      For csv or other 'permissive create' actions, either add OR update the values.
     * If the BINID exists, then update, else add.
     *
     * Note: in THIS mode, we allow creation of aisle/row/zone/face/etc "on the fly" for
     *      convienience.
     *
     * Note: We expect BULK UPDATE here, so we cache existing ids and the like to speed things up.
     *      If no changes are made, we don't write the record.
     *
     * @param string[]   $values
     *
     * @return bool
     */
    public function csvAddOrUpdate(&$values)
    {
        if (array_isnull($values)) {    // empty line?
            return true;
        }

        $this->permissiveCreate = true;
        $this->enableCache();   // harmless to call this multiple times

        // any fields that are empty can just go away
        foreach ($values as $key => $value) {
            $value = trim($value);
            if (($value == '') || ($key == 'DONOTIMPORT')) {
                unset($values[$key]);
            } else {
                $values[$key] = $value; // so we get the trimmed value
            }
        }

        $existingRecordNumber = $this->keyForId('BINID', $values['BINID']);
        if ($existingRecordNumber) {
            $values['WAREHOUSEKEY'] = $this->cache['BIN'][$values['BINID']]['WAREHOUSEKEY']; //The cache should be available as we called enableCache above
            $values['RECORDNO'] = $existingRecordNumber;
            return $this->set($values);
        }
        return $this->add($values);
    }


    /**
     *      If the customer fills in optional ID fields, look up the KEY values (record#) for them.
     *
     * @param array $values
     *
     * @return bool
     */
    function translate(&$values)
    {
        $ok = true;

        $values['BINID_RECORD#'] = $this->keyForId('BINID', $values['BINID']);   // does it exist?  (cleans up the ID too)
        if ($values['BINID'] == '') {
            return $this->error($values, "Specify a BINID.",['errorCode' => 'INV-0470']);
        }

        $advanced = self::areAdvanedBinsOn();
        if ($advanced) {
            //We need to preserve the DB warehouse key before we translate it to the new user enterred one.
            //We will use it in validate function to make sure it did not change as it cannot be changed.
            $values['DBWAREHOUSEKEY'] = $values['WAREHOUSEKEY'];

            // Transalate WAREHOUSE, ZONE, AISLE, FACE and SIZE values to their KEY repspectively.
            // if 'permissive create' mode, then add them if not there.
            // Note these are OPTIONAL on the caller's part
            $binObjectArr = array(
                'WAREHOUSE' => 'warehouse',
                'ZONE'      => 'zone',
                'AISLE'     => 'aisle',
                'FACE'      => 'binface',
                'SIZE'      => 'binsize',
                'ROW'       => 'icrow',
            );
            foreach ($binObjectArr as $key => $manager) {
                $binId  = $key . 'ID';
                $binKey = $key . 'KEY';
                if ($key === 'SIZE') {
                    $binKey = 'BIN' . $binKey;  // BINSIZEKEY
                }
                $field = ($binId == 'WAREHOUSEID') ? 'LOCATIONID' : $binId;
                $field = ($binId == 'ROWID')       ? 'ROWKEY'     : $field;     // non-standard key/id confusion

                if (isset($values[$binId]) && $values[$binId] != '') {

                    $recordNumber = $this->keyForId($binId, $values[$binId]);

                    if ($recordNumber) {
                        $values[$binKey] = $recordNumber;
                    } else if ($this->permissiveCreate && ($key != 'WAREHOUSE')) { // can't create a warehouse on the fly
                        $addValues = [$field => $values[$binId]];
                        $objectMgr = Globals::$g->gManagerFactory->getManager($manager);
                        $ok = $objectMgr->add($addValues);
                        if ($ok) {
                            $values[$binKey] = $addValues['RECORDNO'];
                            // If the cache is on, add this to the cache too
                            if ($this->cacheIsOn()) {
                                $this->cache[$binId][$values[$binId]] = $addValues['RECORDNO'];
                            }
                        }
                    } else {
                        $tokenParam = array(
                            'errorCode' => 'INV-0471',
                            'placeHolder' => array(
                                   'BIN_ID' => $binId,
                                  'VALUES_BIN_ID' => $values[$binId]
                            )
                        );
                        $ok = $this->error($values, sprintf('The %1$s called "%2$s" does not exist.', $binId, $values[$binId]),$tokenParam);
                    }
                }
            }
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
        $ok = true;
        $advanced = self::areAdvanedBinsOn();

        // since translate() comes before validate, if they specified WAREHOUSEID it was converted into a key by now.
        // if not advanced, we errored above if they specified it
        if ($advanced) {
            if (!isset($values['WAREHOUSEKEY']) || ((int)$values['WAREHOUSEKEY'] == 0)) {
                $ok = $this->error($values, "Specify a WAREHOUSEKEY or WAREHOUSEID field.", ['errorCode' => 'INV-0472']);
            } else if (isset($values['SEQUENCENO']) && ($values['SEQUENCENO'] != '') &&
                (! is_numeric($values['SEQUENCENO']) || ((float)$values['SEQUENCENO'] < 0))) {
                $ok = $this->error($values, "The SEQUENCENO must be numeric and not negative", ['errorCode' => 'INV-0473']);
            } else if ($ok && isset($values['SEQUENCENO']) && ($values['SEQUENCENO'] != '') && strlen($values['SEQUENCENO']) > 10 ){
                $ok = $this->error($values, "The SEQUENCENO must be less than or equal to 10 characters",['errorCode' => 'INV-0474']);
            } else if (!$isAnAdd) {
                //We need to make sure we are not changing the warehouseid of a bin during update
                $originalWhKey = $values['DBWAREHOUSEKEY'];
                $newWhKey = $values['WAREHOUSEKEY'];
                if ($originalWhKey !== $newWhKey) {
                    $ok = $this->error($values, "The WAREHOUSEID for a bin cannot be changed",['errorCode' => 'INV-0475']);
                }
            }
        } else { // NOT advanced
            foreach (self::ADVANCED_FIELDS as $field) {
                // The UI fills in default fields like STATUS and PORTABLE....
                if (( ! $this->fromAPI) && (($field == 'STATUS') || ($field == 'PORTABLE'))) {
                    continue;  // likely filled in by the UI
                }
                if (isset($values[$field])) {
                    $tokenParam = array(
                        'errorCode' => 'INV-0476',
                        'placeHolder' => array('FIELD' => $field)
                    );
                    $ok = $this->error($values, sprintf('The field %s cannot be specified in "Classic" Bins', $field), $tokenParam);
                }
            }
        }

        $recordNumber = (int)$values['BINID_RECORD#'];   // set in translate, may be zero
        $msg = 'The BINID "%s" already exists.  Enter a name that is unique across all warehouses.';
        $tokenParam = [
            'errorCode' => 'INV-0477',
            'placeHolder' => ['VALUES_BINID' => $values['BINID']]
        ];
        if ($isAnAdd) {
            if ($recordNumber > 0) {
                $ok = $ok && $this->error($values, sprintf($msg, $values['BINID']), $tokenParam);
            }
        } else if ($recordNumber != 0) { // an update; does the binid exist already?
            if ($recordNumber != (int)$values['RECORDNO']) { // binid already in use elsewhere
                $ok = $ok && $this->error($values, sprintf($msg, $values['BINID']), $tokenParam);
            }
        }
        return $ok;
    }


    /**
     * Did customer want to change the name of the bin during set()?
     *
     * @param array $values Array Set of values to update
     *
     * @return bool signifying success or failuure
     */
    public function maybeRenameBinID(&$values)
    {
        $ok       = true;

        // in validate we caught whether this is a dup or not.
        // so if the record# for this bin is ZERO, that means the
        // BINID is a new BINID, and we want to rename it.
        //
        // BUT!  Since we are called from set(), if the binid is the same as it was in the add(), then
        //       the BINID_RECORD# will be the same as the record# we're setting, so we're ONLY going to
        //       do the extra work if (A) this is set(), and (B) the BINID is new
        if ((int)$values['BINID_RECORD#'] == 0) {
            if (! self::areAdvanedBinsOn()) {
                $ok = $this->error($values, 'The BINID can be renamed only after you’ve migrated from classic mode to the new bin tracking behavior.', ['errorCode' => 'INV-0478']);
            } else {
                // if you do a get() you do a BUNCH of lookups, potentially
                // here, we have ther record# and the NEW ID, we want the existing/old ID
                $binData = QueryResult(["select BINID from icbin where cny#=:1 and record#=:2", GetMyCompany(), $values['RECORDNO']]); // get existing record
                if ($binData !== false && !empty($binData)) { // bin CAN be read, right?
                    $oldBin = $binData[0]['BINID'] ?? $values['BINID'];
                    if ($oldBin != $values['BINID']) {  // double check, just to make sure!
                        // Note: the QRY_BIN_UPDATE does NOT update the ID, since the ID is the vid!
                        //     And, because the BINID is the vid, it uses it to READ the record.  So, change it now...
                        $ok = ExecStmt(["update icbin set binid=:1 where cny#=:2 and record#=:3", $values['BINID'], GetMyCompany(), $values['RECORDNO']]);
                        // note that documententrytrack has the record# in a 50-char text field, so it doesn;t need to change....
                    }
                }
            }
        }
        return $ok;
    }




    /**
     *      upgrade to Advanced Bins is the one-time process that converts from the old Aisle/Row/Bin system to
     *  the new unique-Bin system.  Well, new as of Q1 2020.
     *
     *  Classic Bins: The combination of Warehouse/Aisle/Row/Bin togeather identified a unique location.  Every
     *      warehouse could have a "Bin 1", in fact could have a "Bin 1" in every Aisle/Row.
     *
     *  Advanced Bins: The Bin ID is a unique identifier for a specific bin in a specific place.  The Bin now contains
     *      the Warehouse/Aisle/Row and other information.
     *
     *  Why?  External systems prefer a unique Bin ID so they don't have to carry around other information.
     *
     *  Note: as of December, 2019, this process is launched by a CSTool, and is not directly available to customers.
     *
     * @param  string[]  $stats    interesting statistics
     * @return bool
     */
    public function upgradeToAdvancedBins(&$stats)
    {
        $ok = true;
        $stats = [];
        $preferences = [];
        GetModulePreferences(Globals::$g->kINVid, $preferences);
        // if the preference for bins is off, then defer the advanced decision until later.
        if  ($preferences['ENABLEBIN'] != 'T') {
            $this->error([],"This company file is not using bin tracking. To enable the enhanced bin tracking feature, select the bin tracking checkbox on the Configure Inventory page.", ['errorCode' => 'INV-0479']);
            $ok = false;
            return $ok;
        }

        if (self::areAdvanedBinsOn(true)) {
            $this->error([],"This company file is now using the enhanced bin tracking feature. ", ['errorCode' => 'INV-0480']);
            $ok = true; // this is just a warning
        } else {
            $binArray = [];

            // 1) Get the warehouse, aisle, row, and bin keys and id's for use later
            $tables   = $this->getTableIdsAndKeys();
            $stats[]  = "Number of bins in the company: "   . count($tables['BIN_BYKEY'] ?? []);
            $stats[]  = "Number of aisles in the company: " . count($tables['AISLE_BYKEY'] ?? []);
            $stats[]  = "Number of rows in the company: "   . count($tables['ROW_BYKEY'] ?? []);

            if ($tables['FIRST_WAREHOUSE'] == 0) {
                $this->error([],"This company file has no warehouses and can’t be migrated from classic bin tracking to the enhanced bin tracking feature.", ['errorCode' => 'INV-0481']);
                $ok = false;
            }

            // 2) Make unique bin IDs as needed
            $ok = $ok && $this->buildUniqueBinsFromWhseBinTable($tables, $binArray);
            if ($ok) {
                $stats[]  = "Number of unique (distinct) bin references in transactions: " . count($binArray ?? []);
                $source = 'binManager::upgradeBins';
                $ok = $ok && $this->_QM->beginTrx($source);

                // 3) Add warehouses, aisles, and rows into the bin table.  Create new bin records as needed
                $ok = $ok && $this->updateBinTable($tables, $binArray);

                // 4) Update transaction references to refer to the new bin IDs/record#s, and NOT to the aisles/rows
                $ok = $ok && $this->updateTransactions($binArray);

                // 4.5) did it all work?
                if ($ok) {
                    $on = self::areAdvanedBinsOn(true); // force the preferences to be updated
                    if (!$on) {
                        $stats[]  = "The migration failed and the company file is still in classic bin tracking mode. Report the problem to Product Development and Engineering.";
                        $ok = false;
                    }
                }

                // 5) All done!  Save the modules and finish the transaction
                if ($ok) {
                    $ok = $this->_QM->commitTrx($source);
                } else {
                    $this->_QM->rollbackTrx($source);
                }
            }
        }
        return $ok;
    }


    /**
     *      Get the IDs and Keys of the warehouse, bin, aisle, and row tables.
     *  I do this once rather than while fetching transactions because there can be tables not referenced by any
     *  transaction, and they may need changing too.  Also, it makes all the other queries simpler.
     *
     * @return array
     */
    private function getTableIdsAndKeys()
    {
        // Apparently we can import non-ASCII strings and they somehow get saved in the DB.
        // However, in other cases they will generate a failure when saving as a key value,
        // so if we detect UTF-8, change it to ASCII
        $cleanNonUTF8Strings = function($s) {
            if ($s != '') {
                $encoding = mb_detect_encoding($s, [ "UTF-8", "ISO-8859-1", "ASCII"] );
                if ($encoding != 'ASCII') {
                    $s = iconv($encoding, 'ASCII//TRANSLIT', $s);
                }
            }
            return $s;
        };


        $tables = [];
        $qry = [];
        // Note how the row table uses 'xxxKey' rather than 'xxxID'
        $qry[] = "SELECT 'WAREHOUSE' as type, record# as key, location_no as id, ''      as description FROM icwarehouse WHERE cny#=:1
                  UNION ALL
                  SELECT 'BIN'       as type, record# as key, binid       as id, bindesc as description FROM icbin       WHERE cny#=:1
                  UNION ALL
                  SELECT 'AISLE'     as type, record# as key, aisleid     as id, ''      as description FROM icaisle     WHERE cny#=:1
                  UNION ALL
                  SELECT 'ROW'       as type, record# as key, rowkey      as id, ''      as description FROM icrow       WHERE cny#=:1
                  ORDER BY type, key, id";
        $qry[] = GetMyCompany();

        $result = QueryResult($qry);
        if ($result !== false) {
            $lowestWarehouseName = null;
            $lowestWarehouseKey  = 0;
            foreach ($result as $row) {
                $id = $cleanNonUTF8Strings($row['ID']);
                $tables[$row['TYPE'] . '_BYKEY'][$row['KEY']] = $id;  // indexed by record#
                $tables[$row['TYPE'] . '_BYID' ][$id] = $row['KEY'];  // indexed by the string ID
                // and we only care about descriptions of bins, nothing else.
                if ($row['TYPE'] == 'BIN') {
                    $desc = $cleanNonUTF8Strings($row['DESCRIPTION'] ?? '');
                    $tables['BINDESC'][$row['KEY']] = $desc;
                } else if ($row['TYPE'] == 'WAREHOUSE') {
                    if (($lowestWarehouseName == null) || (strcoll($lowestWarehouseName , $id) > 0)) {
                        $lowestWarehouseName = $id;
                        $lowestWarehouseKey  = $row['KEY'];
                    }
                }
            }
            $tables['FIRST_WAREHOUSE'] = $lowestWarehouseKey;
        }
        return $tables;
    }


    /**
     *      Scan for the Warehouse/Bin combinations, and build a table in RAM of the unique bins.
     *  return the table of unique bins in the parameter
     *
     * @param array     $tables         information about the various tables; their key and id
     * @param array     $binArray       output: the bins in use
     *
     * @return bool
     */
    private function buildUniqueBinsFromWhseBinTable(&$tables, &$binArray)
    {
        $binArray = [];
        $qry      = [];

        // I'm not looking at docentrytrack records, only docentrytrackdetail and costing records and item/warehouse
        $qry[] = "SELECT distinct binkey, WHSEID, aislekey, rowkey
                        FROM 
                            (
                                SELECT binkey, whsekey as WHSEID, aislekey, rowkey
                                 FROM  docentrycost 
                                 WHERE cny#=:1 AND whsekey IS NOT NULL
                                  AND (binkey IS NOT NULL OR aislekey IS NOT NULL OR rowkey IS NOT NULL)
                                
                                UNION
                                
                               SELECT binkey, whsekey as WHSEID, aislekey, rowkey
                                FROM  docentrycostkits
                                WHERE cny#=:1 AND whsekey IS NOT NULL
                                 AND (binkey IS NOT NULL OR aislekey IS NOT NULL OR rowkey IS NOT NULL)

                                UNION
                                
                               SELECT det.binkey, de.warehousekey as WHSEID, det.aislekey, det.rowkey
                                FROM  docentrytrackdetail det, docentry de
                                WHERE det.cny#=:1 AND de.cny#=:1
                                 AND (det.binkey IS NOT NULL OR det.aislekey IS NOT NULL OR det.rowkey IS NOT NULL)
                                 AND det.docentrykey = de.record#
                                 
                               UNION
                               
                              SELECT binkey, warehousekey as WHSEID, aislekey, rowkey 
                               FROM icitemwhse i
                               WHERE cny#=:1 AND 
                                     warehousekey IS NOT NULL AND 
                                    (binkey IS NOT NULL OR aislekey IS NOT NULL OR rowkey IS NOT NULL)
                            )
                        ORDER BY binkey, WHSEID, aislekey, rowkey ";

        // where's the warehouse??????  record#, location_no from icwarehouse
        //                    SELECT b.record# as binkey, de.warehousekey as whsekey, a.record# as aislekey, r.record# as rowkey, 'docentrytrack' as table, det.record#
        //                    FROM  docentrytrack det, icaisle a, icrow r, icbin b
        //                    WHERE det.cny#=:1 AND a.cny#=:1 AND r.cny#=:1 AND b.cny#=:1
        //                     AND det.aislekey=a.aisleid(+) AND det.rowkey=r.rowkey(+) AND det.binkey=b.binid(+)
        //
        //                    UNION



        $qry[]  = GetMyCompany();
        $result = QueryResult($qry);
        $ok = ($result !== false);
        if ($ok) {
            $newBinIDs = [];
            foreach ($result as $row) {
                $binKey = $row['BINKEY'] ?? 0;
                $binID  = $binKey ? $tables['BIN_BYKEY'][$binKey] : '';
                $row['WHSEKEY'] = $tables['WAREHOUSE_BYID'][$row['WHSEID']] ?? 0;
                if ($row['WHSEKEY'] == 0) {
                    continue;
                }

                // Case one: no bin, but there are aisles and/or rows (binkey is zero)
                // Case two: more than one occurance of the bin; since the query is 'distinct' it means
                //      that there may be, say, bin 1, aisle 1, row 1 and bin 1, aisle 2, row 1.  Now, those
                //      should be two separate, unique, bins
                $newBin = $this->makeUniqueBinID( $row, $tables, $newBinIDs );
                if ($newBin != $binID) {
                    // so make a new, unique bin and assign to this row
                    $row['NEW_BINID'] = $newBin;
                }
                // save the row into the bin array, including the new bin id if one
                $binArray[ $newBin ] = $row;
            }
        }
        return $ok;
    }


    /**
     *      Given a bin, warehouse, aisle and row, make a new bin id that is unique.  This may get akward if:
     *  - they are clever and name things in a way that makes it hard for me
     *  - the names get long and overflow the string.
     *  However, this will work in any case (though with a hard-to-read name in the worst case)
     *
     * @param array    $row               the 'ditinct' Bin, Warehouse, Aisle, and Row keys
     * @param array    $tables            conversions between IDs and KEYs
     * @param array    $newBinIDs         a table of unique bin names I've created inside here
     *
     * @return string                     the unique id
     */
    private function makeUniqueBinID($row, &$tables, &$newBinIDs)
    {
        $binID          = $row['BINKEY']   ? $tables['BIN_BYKEY'][$row['BINKEY']] : '';
        $warehouseID    = $row['WHSEKEY']  ? $tables['WAREHOUSE_BYKEY'][$row['WHSEKEY']] : '';
        $aisleID        = $row['AISLEKEY'] ? $tables['AISLE_BYKEY'][$row['AISLEKEY']] : '';
        $rowID          = $row['ROWKEY']   ? $tables['ROW_BYKEY'][$row['ROWKEY']] : '';

        // add the various IDs togeather
        $newBinID = 'W' . $warehouseID;   // bin might be empty, warehouse cannot be
        if ($aisleID != '') {
            $newBinID .= '-A' . $aisleID;
        }
        if ($rowID != '') {
            $newBinID .= '-R' . $rowID;
        }
        if ($binID != '') {
            $newBinID .= '-B' . $binID;
        }

        // THE RULES
        // 1) if this is the FIRST time we've seen this bin configuration, and there is a bin id,
        //      AND the bin ID is not numeric (so the old and new audit trails don't collide),
        //      then just use the bin ID
        // Uses of $newBinIDs, which is passed to us from above as our local context...
        //  - 'BIN' the raw bin id, if it exists, "is it in use?"  (true/not-defined)
        //  - 'FULL' the entire new bin id with all the pieces, assembled above
        //  - 'PART' the amount of FULL that fits in the BIN ID LENGTH (30); i.e. if, say, WAREHOUSEID is 20
        //          and AISLE is 10 and BIN is 10, this is the 'chopped' version.  These are dis-ambiguated
        //          by prepending a 1-, 2-, ... until they're unique.
        if (($binID != '') && ( ! is_numeric($binID)) && ( ! isset($newBinIDs['BIN'][$binID]))) {
            $newBinIDs['BIN'][$binID]     = true;
            $newBinIDs['FULL'][$newBinID] = $binID; // first one gets to use the original bin id
            $trimmedID = substr($newBinID, 0, self::BINID_LENGTH);   // chop it to the right length
            $newBinIDs['PART'][$trimmedID] = true;
        }

        // 2) if this configureation of bin/aisle/row is already there, use that....
        if (isset( $newBinIDs['FULL'][$newBinID])) {
            return $newBinIDs['FULL'][$newBinID];   // yay!
        }

        // 3) No, this is new.  But, will it fit in the length allowed?
        $tieBreaker = 0;
        while (true) {
            $trimmedID = ($tieBreaker == 0) ? '' : ((string)$tieBreaker . '-');
            $tieBreaker++;

            $trimmedID .= $newBinID;

            // but if we have to chop it down, is it NOW an existing bin ID?
            $trimmedID = substr($trimmedID, 0, self::BINID_LENGTH);   // chop it to the right length
            $trimmedID = rtrim($trimmedID, '- ');    // but remove trailing whitespace and dashes

            // Does this name exist as a bin already?
            // like, someone happens to name a bin 'W1-A1' and we generate that here.
            // Ya, likely only QA would do that....
            if (isset($tables['BIN_BYID'][$trimmedID])) {
                continue;
            }

            // If the trimmed id has not yet been seen,
            // then we're good.  Otherwise the TRIMMED and FULL ids are different, and we have
            // NOT seen the full id, but we HAVE seen the trimmed id....
            // (like Wmylongwarehousenametoday-Amylongaislename1-Rmylongrowname1-Bmylongbinname1)
            if ( ! isset($newBinIDs['PART'][$trimmedID])) {
                // yay!  it is unique!
                break;
            }
        }
        $newBinIDs['PART'][$trimmedID] = true;
        $newBinIDs['FULL'][$newBinID]  = $trimmedID;   // save for next time
        return $trimmedID;
    }


    /**
     *      Given the table of unique bins, update the Bin table to have the unique names and the other
     *  attributes (warehouse/Aisle/Row).
     *
     * @param array     $tables         information about the various tables; their key and id
     * @param array     $binArray       the bins by key with their warehouse, aisle, and row
     *
     * @return bool
     */
    private function updateBinTable(&$tables, &$binArray)
    {
        $ok   = true;
        $warehousesUsed = [];

        // Remember the ID might be brand new and not exist in sql yet...
        foreach ($binArray as $id => $row) {
            $warehouse = $row['WHSEKEY'] ?? 0;
            if ($warehouse == 0) {  // we expect this to be there
                throw new Exception("[Code Bug]Missing warehouse in InventoryBins::updateBinTable");
            }
            $values = [
                'RECORDNO'      => $row['BINKEY']   ?? null, // this may be the OLD record number
                'BINID'         => $id,
                'BINDESC'       => $row['DESC']     ?? null,
                'WAREHOUSEKEY'  => $warehouse,
                'AISLEKEY'      => $row['AISLEKEY'] ?? null,
                'ROWKEY'        => $row['ROWKEY']   ?? null,
            ];
            if ( ! isset($warehousesUsed[$warehouse])) {
                $warehousesUsed[$warehouse] = 0;
            }
            $warehousesUsed[$warehouse]++;

            // Does this bin exist already?
            $tempAssumePriorValue = self::$temporarilyAssumeAdvancedMode;
            self::$temporarilyAssumeAdvancedMode = true;
            $exists = (isset($tables['BIN_BYID'][$id]));
            if ($exists) {
                $values['RECORDNO'] = $tables['BIN_BYID'][$id]; // should match
                $ok = $this->set($values);
            } else {
                unset($values['RECORDNO']); // any recordno is the old one, not the new one
                $ok = $this->add($values);
                if ($ok) {
                    $recordNo = $values[':RECORDNO'] ?? $values['RECORDNO'];
                    $binArray[$id]['NEW_BINKEY'] = $recordNo;
                    $tables['BIN_BYID'][$id] = $recordNo;    // update the table
                    $tables['BIN_BYKEY'][$recordNo] = $id;
                }
            }
            self::$temporarilyAssumeAdvancedMode = $tempAssumePriorValue;
            if (!$ok) {
                break;
            }
        }

        // Finally, make the bin table entries with no transactions point to one warehouse, just to keep them
        if (empty($warehousesUsed)) {
            $warehousesUsed[$tables['FIRST_WAREHOUSE']] = 1;  // get the first warehouse record#
        }

        if ($ok && !empty($warehousesUsed)) {
            rsort($warehousesUsed, SORT_NUMERIC);   // get 'MOST USED' warehouse
            $commonWarehouse = $warehousesUsed[0];
            $qry    = [];
            $qry[]  = "UPDATE icbin SET warehousekey = :1 where cny# = :2 and warehousekey IS NULL";
            $qry[]  = $commonWarehouse;
            $qry[]  = GetMyCompany();
            $result = ExecStmt($qry);
            $ok     = ($result !== false);
        }

        // remove warehouse aisles and warehouse rows; delete and recreate the bins
        if ($ok) {
            $qry = [];
            $qry[] = "DELETE whsebin where cny# = :1 ";
            $qry[] = GetMyCompany();
            $result = ExecStmt($qry);
            $ok = ($result !== false);
            if ($ok) {
                $qry[0] = "DELETE whserow where cny# = :1 ";
                $result = ExecStmt($qry);
                $ok = ($result !== false);
                if ($ok) {
                    $qry[0] = "DELETE whseaisle where cny# = :1 ";
                    $result = ExecStmt($qry);
                    $ok = ($result !== false);
                }
            }
        }

        return $ok;
    }


    /**
     *      Now we have the Bin table with all the unique bin names.  Go back to the transactions and change them
     *  to refer to the correct names, where needed.
     *
     *  Note that the whsebin table has names of the warehouse and bin, but those don't CHANGE; we added new ones
     *      above in updateBinTable().
     *
     * @param array     $binArray       the bins by key with their warehouse, aisle, and row
     *
     * @return bool
     */
    private function updateTransactions(&$binArray)
    {
        // These tables hold the keys (record#s)
        $ok =        $this->updateDocEntryCost('documententrycost',     $binArray);
        $ok = $ok && $this->updateDocEntryCost('stkitdocumententrycost',$binArray);

        // This table has ids but no warehouse so we'll have to look those up
        // TODO: $ok = $ok && $this->updateDocEntryTrack($tables, $binArray, 'documententrytrack');

        // Theis table holds the IDs (names), but again no warehouse
        $ok = $ok && $this->updateDocEntryTrack($binArray, 'documententrytrackdetail');

        // update the item/warehouse default bins
        $manager = Globals::$g->gManagerFactory->getManager('itemwarehouseinfo');
        $ok = $ok && $manager->updateForNewBins($binArray);

        return $ok;
    }


    /**
     *      Time to update docentrycost/docentrycostkits.  Currently they have a non-null warehouse key, and they
     *  have fields for binkey, aislekey, and rowkey.  Any, but not all, can be null.  Also, the binkey may have
     *  been changed, so we want to FIND the existing binkey and maybe UPDATE it to the new one.
     *
     *
     * @param string    $entityName     the entity name, suitible for looking up the manager
     * @param array     $binArray       the bins by key with their warehouse, aisle, and row
     *
     * @return bool
     */
    private function updateDocEntryCost($entityName, &$binArray)
    {
        $ok = true;
        $manager = Globals::$g->gManagerFactory->getManager($entityName);
        foreach ($binArray as $id => $row) {
            /** @noinspection PhpUndefinedMethodInspection */
            $ok = $ok && $manager->updateTransactionsForNewBin($row);
        }
        return $ok;
    }


    /**
     *      Time to update doc entry track records.  They don't have record#s, but they use the IDs.
     *  Also, the record doesn't refer to the warehouse, but we need that to figure out WHICH bin....
     *
     * @param array     $binArray       the bins by key with their warehouse, aisle, and row
     * @param string    $table          which entity to update
     *
     * @return bool
     */
    private function updateDocEntryTrack($binArray, $table)
    {
        $ok = true;
        $manager = Globals::$g->gManagerFactory->getManager($table);
        foreach ($binArray as $row) {
            /** @noinspection PhpUndefinedMethodInspection */
            $ok = $ok && $manager->updateTransactionsForNewBin($row);
        }
        return $ok;
    }


    /**
     *      Are Classic Bins ON?  If this returns false, either Advanced Bins are ON, or
     *  BINS are off.
     *
     * @return bool     Are they ON?
     */
    public static function areClassicBinsOn()
    {
        if (self::areAdvanedBinsOn()) {
            return false;
        }
        $preferences = [];
        GetModulePreferences(Globals::$g->kINVid, $preferences);
        return ($preferences['ENABLEBIN'] === 'T');
    }


    /**
     *      Are Advanced Bins On?  For this to be true, BINS must also be on.
     *  However there is an option here to test for ADVANCED vs CLASSIC.  In that case,
     *  if BINS are off, it still tells you if it is classic or advanced mode.
     *
     *  This sets the bins 'ADVANCEDBINTRACKING' flag if it is not yet set, and returns it.
     *
     * On first use (i.e. right after this code is released), ADVANCEDBINTRACKING will be NULL, and
     * so we want to see if it should be ON or OFF.  Otherwise, we trust it unless the caller wants
     * to check exhaustively again.  For example, when converting from OLD to NEW bins.
     *
     * @param bool    $forceCheck                       MUST I check exhaustively, or can I trust the preferences?
     *
     * @return bool     are advanced bins on? true if ADVANCEDBINTRACKING is on and ENABLEBIN is checked
     */
    public static function areAdvanedBinsOn( $forceCheck = false )
    {
        if (self::$temporarilyAssumeAdvancedMode) {
            return true;
        }
        static $areTheyOnCache = null;
        if (($areTheyOnCache === null) || $forceCheck) {
            // hand-get so we don't have to get ALL preferences for both location NULL and whatever location we're slid into
            $query    = [];
            $query[0] = "select property, value from modulepref where cny# = :1 and modulekey = :2 and (property = :3 OR property = :4) and locationkey is null ";
            $query[1] = GetMyCompany();
            $query[2] = Globals::$g->kINVid;
            $query[3] = 'ADVANCEDBINTRACKING';
            $query[4] = 'ENABLEBIN';
            $result = QueryResult($query);
            $preference = '';
            $exists     = false;
            foreach ($result as $row) {
                if ($row['PROPERTY'] === 'ADVANCEDBINTRACKING') {
                    $exists     = true; // but it might be a null value
                    $preference = $row['VALUE'] ?? '';
                }
                if (($row['VALUE'] === 'F') && ($row['PROPERTY'] === 'ENABLEBIN')) {
                    $areTheyOnCache = false;
                    return false;   // no, and there's no point in checking further.....
                }
            }

            if ($forceCheck || (!$exists) || ($preference == "")) {
                $preference = (self::setAdvancedBinTrackingFlagTo() ? "T" : "F");
                // update this 'by hand' since SetModulePreferences doesn't know how to deal with sliding into entities
                if ($exists) {
                    $update = 'update MODULEPREF SET VALUE = :1 WHERE cny#=:2 AND MODULEKEY=:3 AND PROPERTY=:4 AND LOCATIONKEY IS NULL';
                } else {
                    $update = 'insert into MODULEPREF ( CNY#, MODULEKEY, PROPERTY, VALUE, LOCATIONKEY) values ( :2, :3, :4, :1, NULL )';
                }
                ExecStmt( [$update, $preference, GetMyCompany(), Globals::$g->kINVid, 'ADVANCEDBINTRACKING'] );
            }
            $areTheyOnCache = ($preference === 'T');
        }
        return $areTheyOnCache;
    }

    /**
     * Returns true if bin tracking is checked in inventory config.
     *
     * @return bool true if bin checkbox is checked in inventory config
     */
    public static function isInventoryConfigBinChecked()
    {
        $query = [];
        $query[0] = "select property, value from modulepref where cny# = :1 and modulekey = :2 and property = :3 and locationkey is null";
        $query[1] = GetMyCompany();
        $query[2] = Globals::$g->kINVid;
        $query[3] = 'ENABLEBIN';
        $result = QueryResult($query);
        return ($result[0]['VALUE'] == 'T');
    }

    /**
     *      Advanced bin tracking should be OFF if
     *  - there ARE bins, but they have no warehouses in them yet (not yet converted)
     *  - there are transactions with ausle and/or row in them (not yet converted)
     *
     *  Otherwise it should be ON.
     *
     * @return bool         is it on or off?  OFF --> need conversion if you turn on bins
     */
    protected static function setAdvancedBinTrackingFlagTo()
    {
        $query   = [];
        $query[] = "SELECT  count(*) howmany from icbin where cny#=:1 and warehousekey is null
                    UNION
                    SELECT  count(*) howmany from docentrycost where cny#=:1 and (aislekey is not null or rowkey is not null)
                    UNION
                    SELECT  count(*) howmany from docentrycostkits where cny#=:1 and (aislekey is not null or rowkey is not null)
                    UNION
                    SELECT  count(*) howmany from docentrytrackdetail where cny#=:1 and (aislekey is not null or rowkey is not null)
                    ";
        $query[] = GetMyCompany();
        $found   = QueryResult($query);
        if ($found !== false) {
            foreach ($found as $row) {
                if ($row['HOWMANY'] > 0) {
                    return false;    // we are NOT advanced!
                }
            }
        }
        return true;
    }


    /**
     *      Is the cache on or not?  (it could be on but EMPTY if there are no bins)
     *
     * @return bool             is it on?
     */
    public function cacheIsOn()
    {
        return ($this->cache !== null);
    }


    /**
     *      Enable a cache for bulk operations.  Pass FALSE to disable the cache.
     *
     * @param bool $on
     */
    public function enableCache($on = true)
    {
        if ($on == false) {
            $this->cache = null;
        }

        // Don't turn it on over and over, that would be expensive.  BUT, if you want to 'flush' or refresh the caceh,
        // then call this function with false and it will be turned OFF.
        if ($on && ($this->cache === null)) {
            $this->cache = [];
            $result = QueryResult(["select record#, binid, bindesc, sequenceno, status, portable, warehousekey, zonekey, facekey, aislekey, rowkey, binsizekey from icbin where cny#=:1", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['BINID'][$row['BINID']] = $row['RECORD#'];
                    // externalize the values
                    if (isset($row['PORTABLE']) && ($row['PORTABLE'] == 'T')) {
                        $row['PORTABLE'] = 'true';
                    } else {
                        $row['PORTABLE'] = 'false';
                    }
                    if (isset($row['STATUS']) && ($row['STATUS'] == 'F')) {
                        $row['STATUS'] = 'inactive';
                    } else {
                        $row['STATUS'] = 'active';
                    }
                    $this->cache['BIN'][$row['BINID']]   = $row;    // this could be huge!
                }
            }
            $result = QueryResult(["select record#, location_no from icwarehouse where cny#=:1 ", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['WAREHOUSEID'][$row['LOCATION_NO']] = $row['RECORD#'];
                }
            }
            $result = QueryResult(["select record#, zoneid from iczone where cny#=:1", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['ZONEID'][$row['ZONEID']] = $row['RECORD#'];
                }
            }
            $result = QueryResult(["select record#, faceid from icbinface where cny#=:1", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['FACEID'][$row['FACEID']] = $row['RECORD#'];
                }
            }
            $result = QueryResult(["select record#, aisleid from icaisle where cny#=:1", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['AISLEID'][$row['AISLEID']] = $row['RECORD#'];
                }
            }
            $result = QueryResult(["select record#, rowkey from icrow where cny#=:1", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['ROWID'][$row['ROWKEY']] = $row['RECORD#'];    // note incorrect use of KEY vs ID!!
                }
            }
            $result = QueryResult(["select record#, sizeid from icbinsize where cny#=:1", GetMyCompany()]);
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache['SIZEID'][$row['SIZEID']] = $row['RECORD#'];
                }
            }
        }
    }


    /**
     *      This will lookup the RECORD# (key) of a given ID.  For example, you can get the AISLE RECORD#
     * from the AISLEID.  This works whether or not we're cached.  Also cleans up the id for later use
     *
     * @param string        $type         one of SIZEID, ROWID, AISLEID, FACEID, ZONEID, WAREHOUSEID, or BINID.
     * @param string        $id           the id of the record
     *
     * @return int                        the record# (key); 0 if no such record
     */
    private function keyForId($type, &$id)
    {
        $keyForTable = [
            'AISLEID'            => ['icaisle',     'aisleid'],
            'BINID'              => ['icbin',       'binid'],
            'FACEID'             => ['icbinface',   'faceid'],
            'SIZEID'             => ['icbinsize',   'sizeid'],
            'ROWID'              => ['icrow',       'rowkey'],          // non-standard
            'WAREHOUSEID'        => ['icwarehouse', 'location_no'],     // ditto
            'ZONEID'             => ['iczone',      'zoneid'],
        ];

        $type = strtoupper(trim($type));
        $id   = trim($id);
        if ($id == '') {
            return 0;       // not specified?  then not found.
        }
        if ( ! isset($keyForTable[$type])) {
            throw new Exception("[Code bug]bad TYPE parameter for keyForId: $type");
        }

        // are we using the cache?  Is this id IN the cache?
        if (($this->cache !== null) && isset($this->cache[$type][$id])) {
            return $this->cache[$type][$id];
        }

        $table  = $keyForTable[$type][0];
        $column = $keyForTable[$type][1];

        // oterwise, sadly, look it up
        $result = QueryResult(["select record# from $table where cny# = :1 and $column = :2", GetMyCompany(), $id]);
        if (($result !== false) && ( ! empty($result))) {
            $recordNumber = $result[0]['RECORD#'] ?? 0;
            $this->cache[$type][$id] = $recordNumber;   // in case we happen to want this again
            return $recordNumber;
        }
        return 0;   // not found
    }


    /**
     *      Sometimes, we have a bin record number (BinKEY) and want the ID
     *
     * @param int|string    $binKey     The bin record#
     *
     * @return string                   The bin name
     */
    public static function IdForKey($binKey)
    {
        static $cachedIds = [];
        if ( ! isset($cachedIds[$binKey])) {
            $result = QueryResult(["SELECT binid FROM icbin  WHERE cny#=:1 AND record#=:2", GetMyCompany(), $binKey]);
            if (($result !== false) && (!empty($result))) {
                $cachedIds[$binKey] = $result[0]['BINID'];
            }
        }
        return $cachedIds[$binKey] ?? '';
    }




    /**
     *      Sometimes, we have a bin record number (BinKEY) and want the ID
     *
     * @param int[]       $binKeys      The bin record#s
     *
     * @return string[]                 The bin names, by record#
     */
    public static function BinIdsForKeys($binKeys)
    {
        $rtn    = [];
        if ( ! empty($binKeys)) {
            $qry = [];
            $qry[0] = "SELECT record#, binid FROM icbin  WHERE cny#=:1 ";
            $qry[1] = GetMyCompany();
            $qry = PrepINClauseStmt($qry, $binKeys, " AND record# ");
            $result = QueryResult($qry);
            if ($result !== false) {
                foreach ($result as $row) {
                    $rtn[$row['RECORD#']] = $row['BINID'];
                }
            }
        }
        return $rtn;
    }


    /**
     *      Sometimes, we have a binID from the UI/API, and want the record#
     *
     * @param string    $binID      The bin ID
     *
     * @return int                   The bin record#
     */
    public static function binKeyFromBinID($binID)
    {
        static $cachedIds = [];
        if ( ! isset($cachedIds[$binID])) {
            $result = QueryResult(["SELECT record# FROM icbin  WHERE cny#=:1 AND binid = :2", GetMyCompany(), $binID]);
            if (($result !== false) && (!empty($result))) {
                $cachedIds[$binID] = $result[0]['RECORD#'];
            }
        }
        return $cachedIds[$binID] ?? 0;
    }


    /**
     * Return user key field name (EntityManager override)
     *
     *      We use the standard EntityManager code except when in advanced mode getting the audit object id,
     *  there we return RECORDNO, so the audit trail doesn't freak out when we rename BinId
     *
     * @return string
     */
    function GetKeyFieldName()
    {
        if ($this->useAuditTrailVid == true) {
            return 'RECORDNO';
        }
        return parent::GetKeyFieldName();
    }


    /**
     *      Override of the parent; this is called to add Audit Trail recods and other things;
     *  if we are in Advanced Mode we pretend the vid is record#, and not BinId
     *
     * @param array  $values
     * @param string $action
     * @param bool   $fastUpdate
     *
     * @return bool
     */
    protected function postProcessValues(&$values, $action, $fastUpdate = false)
    {
        $priorUseAuditTrailVid = $this->useAuditTrailVid;   // in case we nest
        if (self::areAdvanedBinsOn()) {
            $this->useAuditTrailVid = true;
        }
        $ok = parent::postProcessValues($values, $action, $fastUpdate);
        $this->useAuditTrailVid = $priorUseAuditTrailVid;
        return $ok;
    }


    /**
     * getAuditObjId - Get the key value for the audit trail record. (EntityManager override)
     *
     *  For Advanced Mode
     *
     *  The audit trail uses the VID, which in our case is the BinID, but when we rename the BinId, the
     *  audit trail is lost.  So, for Advanced Bins we will use the record# for the audit trail
     *
     * @return string Audit record key value.
     */
    public function getAuditObjId()
    {
        $priorUseAuditTrailVid = $this->useAuditTrailVid;   // in case we nest
        if (self::areAdvanedBinsOn()) {
            $this->useAuditTrailVid = true;
        }
        $ok = parent::getAuditObjId();
        $this->useAuditTrailVid = $priorUseAuditTrailVid;
        return $ok;
    }



    /**
     *      Output an error message with an optional ROW (from the importer)
     *
     * @param array     $values         where I might find 'ROW'
     * @param string    $message        error message
     *
     * @return bool                     false, in case that is useful
     */
    private function error($values, $message, $param = [])
    {
        $placeHolder = [];
        $placeHolderText = '';
        if(isset($param['placeHolder'])){
             $placeHolder = $param['placeHolder'];
        }
        $row = $values['ROW'] ?? 0;
        if ($row) {
            $message .= sprintf(", on row %1s", $row);
            $placeHolderText = I18N::getSingleToken("IA.ON_ROW", ['ROW' => $row]);
        }
        $placeHolder = array_merge($placeHolder,['MSG' => $placeHolderText]);

        // Get the line and file of the CALLER
        $stack = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 2);
        $arr = array_shift($stack); // get the file which called this function
        $file = $arr['file'];
        $line = $arr['line'];

        Globals::$g->gErr->addIAError($param['errorCode'], $file . ':' . $line,  $message, $placeHolder);
        return false;   // in case that's useful
    }


    /**
     * @param int $binKey
     *
     * @return array
     */
    public function getBinInventory($binKey)
    {
        $binInventory = [];
        if ($binKey == null) {
            return $binInventory;
        }

        $binInvDetails = QueryResult(
            array(
                " SELECT
                     availinv.item_id           AS itemid,
                     availinv.bin_id            AS bin,
                     availinv.serial_no         AS serialno,
                     availinv.lot_no            AS lotno,
                     availinv.expiration_date   AS expiration,
                     availinv.qty_left          AS qoh,
                     it.extended_description    AS itemdesc,
                     icuom.unit                 AS unit            
                     
                 FROM
                     v_availableinventory availinv
                     INNER JOIN icitem it ON it.cny# = availinv.cny#
                                             AND it.itemid = availinv.item_id
                     INNER JOIN icuomgrp ON icuomgrp.cny# = it.cny# 
                                            AND icuomgrp.record# = it.uomgrpkey
                     INNER JOIN icuom ON icuom.cny# = icuomgrp.cny# 
                                            AND icuom.grpkey = icuomgrp.record#
                WHERE
                    availinv.cny# = :1
                    AND icuom.isbase = 'T'
                    AND availinv.bin_key = :2 ",
                GetMyCompany(),
                $binKey,
            )
        );

        foreach (($binInvDetails ?? []) as $key => $row) {
            $binInvDetails[$key]['EXPIRATION'] = FormatDateForDisplay($row['EXPIRATION']);
        }

        return $binInvDetails;
    }


    /**
     *      for a list of item id's, get a corresponding list of bins to use when getting data.
     *
     *
     * @param string[]      $items      The list of items
     *
     * @return array                    returned value, indexed by item ids.
     *                                  return includes BINID, ZONEID, and SEQUENCENO for now, add others if needed.
     */
    public function getSuggestedBin($items)
    {
        $rtn = [];
        if ( ! empty($items)) {
            $qry   = [];
            $qry[] = " SELECT
                             availinv.item_id           AS itemid,
                             availinv.whse_id           as warehouseid,
                             availinv.bin_id            AS binid,
                             availinv.zone_id           as zoneid,
                             bin.sequenceno             AS sequenceno,
                             sum(availinv.qty_left)     AS qoh     
                         FROM
                             v_availableinventory availinv,
                             icbin                bin
                        WHERE
                            availinv.cny#   = :1
                            AND bin.cny#    = availinv.cny#
                            AND bin.record# = availinv.bin_key ";
            $qry[]          = GetMyCompany();
            $qry            = PrepINClauseStmt($qry, $items, ' and availinv.item_id ');
            $qry[0] .= " GROUP BY availinv.item_id, availinv.whse_id, availinv.bin_id, availinv.zone_id, bin.sequenceno 
                            ORDER BY availinv.item_id, availinv.whse_id, qoh";

            $binInvDetails  = QueryResult($qry);
            if ($binInvDetails !== false) {
                foreach ($binInvDetails as $row) {
                    $rtn[$row['ITEMID']][$row['WAREHOUSEID']][] = $row;
                }
            }
        }
        return $rtn;
    }

    private function loadTokenLabels()
    {
        I18N::addToken('IA.AVAILABLE');
        I18N::addToken('IA.PRESENT');
        I18N::getText();
    }
}

