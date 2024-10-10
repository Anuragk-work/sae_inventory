<?php

/**
 *    FILE:
 *    AUTHOR: M. Jagadish
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */
class DocumentEntryTrackDetailManager extends OwnedObjectManager
{
    /** @var array $_salepurtrans */
    var $_salepurtrans = array();

    /** @var int $useGetByParentCacheForID              cache the records from GetByParent() (well, DocHdr record# */
    protected $useGetByParentCacheForID = -1;       // -1 means 'DONT use the cache'

    /** @var array $getByParentCache                    if the above is set, use this, else don't */
    protected $getByParentCache = null;


    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $this->_docType = $params['DOCTYPE'] ?? '';
        parent::__construct($params);
        $this->_salepurtrans = array(
            'so' => 'Sale',
            'po' => 'Purchase',
            'inv' => 'Internal',
        );
    }


    // Merge queries override of the base....
    function MergeQueries()
    {
        // if advanced, get our data slightly differently.
        // ya, clunky.  Should be something like GetQueryName() to allow this!
        if (BinManager::areAdvanedBinsOn()) {
            $this->_QM->_queryList['QRY_DOCUMENTENTRYTRACKDETAIL_SELECT_SINGLE_VID'] = $this->_QM->_queryList[ 'QRY_DOCUMENTENTRYTRACKDETAIL_SELECT_SINGLE_VID_ADV' ];
        }

        parent::MergeQueries();
    }



    /**
     * Override useOwnedObject to prevent documententrysubtotals, sodocumententrysubtotals and podocumententrysubtotals
     * ownedobjects from being loaded or modified because these are readonly objects.
     * documentsubtotals, sodocumentsubtotals and podocumentsubtotals are the main object to write the data.
     */
    /**
     * @param array $objRec
     * @param bool  $validateReadOnly
     *
     * @return bool
     */
    protected function useOwnedObject($objRec, $validateReadOnly)
    {
        // only use upsert with the tracking details if the document manager and document entry manager are using them
        $this->setUpsertEntries(DocumentManager::$upsertFeaturInUse);

        return parent::useOwnedObject($objRec, $validateReadOnly);
    }


    /**
     *      use Cache For DocHdr  - when calling GetByParent(), keep a cache for the passed-in doc hdr record#.
     *              if no parameter is passed then it means "DO NOT CACHE", which is the default state.
     *
     *
     * @param int $ID           Optional; the DocHdr# to cache
     */
    public function useCacheForDocHdr( $ID = -1 )
    {
        if ($this->useGetByParentCacheForID != $ID) {
            $this->getByParentCache         = null;     // invalidate the cache
            $this->useGetByParentCacheForID = $ID;      // and set it to this docHdr record #
        }
    }


    /**
     *      flush Cache For DocHdr - reset the cache so the next time someone calls getByParent(), it
     *                  reads a fresh set of records.
     */
    public function flushCacheForDocHdr()
    {
        $this->getByParentCache         = null;     // invalidate the cache
    }


    /**
     *  Handle ADD or SET.  The infrastructure doesn't always know if it should add or not, here we base it on having
     *  a record number
     *
     * @param array $values
     * @param bool  $add             true --> add, false --> set
     *
     * @return bool
     */
    protected function regularAddOrSet(&$values, $add)
    {
        if (empty($values)) {
            return true;    // someone had an empty array when saving, which is ok
        }

        // we may get an array of values, or a single value.
        //  This is what the Entity Manager does.....
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        $ok             = true;
        $addThese       = [];
        $setThese       = [];
        foreach ($groupOfValues as $groupIndex => $oneValue) {
            if ($add) {
                unset($oneValue['RECORDNO']); // the Entity manager is not always clear here
            }
            if ($this->hasTrackingDetails($oneValue)) {
                $ok = $ok && $this->prepValues($oneValue);
                $oneValue['GROUP_INDEX'] = $groupIndex;
                if (isset($oneValue['RECORD#']) || isset($oneValue['RECORDNO'])) {
                    $setThese[]  = $oneValue;
                } else {
                    $addThese[]  = $oneValue;
                }
            }
        }

        if ( ! empty($addThese)) {
            $ok = $ok && parent::regularAdd($addThese);
            foreach ($addThese as $oneValue) {
                $groupIndex = $oneValue['GROUP_INDEX'];
                $groupOfValues[$groupIndex] = $oneValue;   // put it back in case caller wants record# and the like
            }
        }

        if ( ! empty($setThese)) {
            $ok = $ok && parent::regularSet($setThese);
            foreach ($setThese as $oneValue) {
                $groupIndex = $oneValue['GROUP_INDEX'];
                $groupOfValues[$groupIndex] = $oneValue;   // ditto
            }
        }
        $this->flushCacheForDocHdr();

        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        return $this->regularAddOrSet($values, true);   // true --> add
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        return $this->regularAddOrSet($values, false); // false--> set
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function prepValues(&$values){
        $mod    = Request::$r->_mod;
        $values['SALE_PUR_TRANS'] = $this->_salepurtrans[$mod];

        list($itemid) = explode('--', $values['ITEMID']);
        $values['ITEMID'] = $itemid;

        if(isset($values['COMPONENTID']) && $values['COMPONENTID'] != '') {
            list($compId) = explode('--', $values['COMPONENTID']);
            $values['COMPONENTID'] = $compId;
        }

        // ***************************************
        // THE REST OF THIS FUNCTION IS ABOUT BINS
        // ****************************************

        // Is this the special 'empty bin' from Warehouse Transfer?
        $emptyBin = (isset($values['BINID']) && (($values['BINID'] == TrackingHandler::TRACK_EMPTY_FIELD)
                                                 || ($values['BINID'] == I18N::getSingleToken(TrackingHandler::NO_BIN_ID_TOKEN))));
        if ($emptyBin) {
            $values['BINID']    = null;
            $values['BINKEY']   = null;
            $values['AISLEKEY'] = null;
            $values['ROWKEY']   = null;
            return true;
        }

        // look these up if supplied:
        if (isset($values['AISLEID']) && ($values['AISLEID'] != '')) {
            $manager = Globals::$g->gManagerFactory->getManager("aisle");
            $result  = $manager->get($values['AISLEID']);
            if (($result === false) || empty($result)) {
                Globals::$g->gErr->addIAError('INV-0349', __FILE__ . '.' . __LINE__,
                    sprintf("The AISLEID '%1s' does not exist.", $values['AISLEID']),
                    ['VALUES_AISLEID' => $values['AISLEID']]
                );
                return false;
            } else {
                $values['AISLEKEY'] = $result['RECORDNO'];
            }
        }

        if (isset($values['ROWID']) && ($values['ROWID'] != '')) {
            $manager = Globals::$g->gManagerFactory->getManager("icrow");
            $result  = $manager->get($values['ROWID']);
            if (($result === false) || empty($result)) {
                Globals::$g->gErr->addIAError('INV-0350', __FILE__ . '.' . __LINE__,
                    sprintf("The ROWID '%s' does not exist.", $values['ROWID']),
                    ['VALUES_ROWID' => $values['ROWID']]
                );
                return false;
            } else {
                $values['ROWKEY'] = $result['RECORDNO'];
            }
        }

        $binId = '';
        if (isset($values['BINID']) && ($values['BINID'] != '')) {
            $binId = $values['BINID'];
            $manager = Globals::$g->gManagerFactory->getManager("bin");
            $result = $manager->get($values['BINID']);
            if (($result === false) || empty($result)) {
                Globals::$g->gErr->addIAError('INV-0351', __FILE__ . '.' . __LINE__,
                    sprintf("The BINID '%s' does not exist.", $values['BINID']),
                    ['VALUES_BINID' => $values['BINID']]
                );
                return false;
            } else {
                $values['BINKEY'] = $result['RECORDNO'];
            }
        }

        // Check the length of Aisle/Row/Bin
        $checkThese = ['AISLEKEY', 'ROWKEY', 'BINKEY'];
        $inUse      = [];
        foreach ($checkThese as $field) {
            $inUse[$field] = false;
            if (isset($values[$field]) && ($values[$field] != '')) {
                $inUse[$field] = true;
            }
        }

        // In advanced mode, they are allowed to still send us the AISLE and ROW, but
        //      (A) we must have a bin that exists, and
        //      (B) the aisle and row must match what is on file
        if (BinManager::areAdvanedBinsOn()) {
            if ($inUse['AISLEKEY'] || $inUse['ROWKEY']) {
                // bin must exist
                if ( ! $inUse['BINKEY']) {
                    Globals::$g->gErr->addIAError('INV-0015', __FILE__ . '.' . __LINE__,
                        "An AISLEKEY or ROWKEY was specified, but not a BINKEY.  A BINKEY is required if you specify AISLEKEY or ROWKEY.", []);
                    return false;
                }
                $manager = Globals::$g->gManagerFactory->getManager("bin");
                $bin = $manager->getByRecordNumber($values['BINKEY']);
                if (($bin === false) || empty($bin)) {
                    if ($binId != '') {
                        Globals::$g->gErr->addIAError('INV-0281', __FILE__ . '.' . __LINE__,
                            sprintf("The BINID '%s' does not exist.", $values['BINID']), ['VALUES_BINID' => $values['BINID']]);
                    } else {
                        Globals::$g->gErr->addIAError('INV-0352', __FILE__ . '.' . __LINE__,
                            sprintf(_("The Bin with key %s does not exist."), $values['BINKEY']), ['VALUES_BINKEY' => $values['BINKEY']]);
                    }
                    return false;
                }
                $binId = $bin['BINID'];

                // aisle/row must match bin
                $checkThese = ['AISLEKEY' => 'AISLEID', 'ROWKEY' => 'ROWID'];
                foreach ($checkThese as $vfield => $bfield) {
                    $v = $values[$vfield] ?? '';
                    if ($v != '') {     // them omitting it is fine.
                        $b = $bin[$vfield] ?? '';
                        if ($v != $b) {
                            $v1 = $values[$bfield] ?? _('(none)');
                            $b1 = $bin[$bfield]    ?? _('(none)');
                            Globals::$g->gErr->addIAError('INV-0353', __FILE__ . '.' . __LINE__,
                                sprintf('The Bin with ID %1$s has %4$s of %2$s, but %3$s was given.', $binId, $b1, $v1, $bfield),
                                ['BIN_ID' => $binId, 'B1' => $b1, 'V1' => $v1, 'BFIELD' => $bfield]
                            );
                            return false;
                        }
                    }
                    unset($values[$vfield]);    // after all that work, we don't want this field anyway
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
    function hasTrackingDetails($values){
        $trackDetails = ($values['SERIALNO'] ?? '') . ($values['LOTNO'] ?? '') . ($values['EXPIRATION'] ?? '') .
                        ($values['ROWKEY'] ?? '') . ($values['AISLEKEY'] ?? '') . ($values['BINKEY'] ?? ($values['BINID'] ?? ''));
        return strlen($trackDetails) > 0;
    }


    /**
     *      Get Query Name - supply one or the other query for 'get by parent', depending on
     * the mode of bins (classic/advanced)
     *
     * @return string
     */
    function GetQueryName()
    {
        if (BinManager::areAdvanedBinsOn()) {
            return 'QRY_DOCUMENTENTRYTRACKDETAIL_SELECT_BY_PARENT_ADV';
        }
        return parent::GetQueryName();
    }


    /**
     * @param array $values
     * @param array $oldEntries
     * @param array $newEntries
     */
    function getMappedEntries($values, &$oldEntries, &$newEntries)
    {
        $oEntries = $values['EXISTING_ENTRIES'];
        $nEntries = $values['ENTRIES'];

        foreach ( $oEntries as $entry) {
            $eRecNo = $entry['RECORDNO'];
            $tEntries = $entry['EXISTING_TRACKINGENTRIES'];

            foreach (($tEntries ?? []) as $tEntry) {
                $tRecNo = $tEntry['RECORDNO'];
                $oldEntries[$eRecNo.'|'.$tRecNo] = $tEntry;
            }
        }

        foreach ( $nEntries as $entry) {
            $eRecNo = $entry['RECORDNO'];
            $tEntries = $entry['TRACKINGENTRIES'];

            foreach (($tEntries ?? []) as $tEntry) {
                $tRecNo = $tEntry['RECORDNO'];
                $newEntries[$eRecNo.'|'.$tRecNo] = $tEntry;
            }
        }
    }

    /**
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        static $ignoreFields = [
            'record#',
            'docentrykey',
            'sale_pur_trans',
            'whencreated',
            'whenmodified',
            'createdby',
            'modifiedby',
        ];

        return $ignoreFields;
    }

    /**
     * @return string[]
     */
    protected function getExternalFieldsList()
    {
        return [];
    }


    /**
     *      Like GetByParent(), but gets for not just one parent (one docentry), but many.
     *  This saves effort when doing a bulk read....
     *
     * @param int[]   $docEntryKeys             array of docentrykey values (integers)
     *
     * @return bool|string[][]
     * @throws Exception
     */
    public function getManyByParent($docEntryKeys)
    {
        // Step one: got the list of docentrykeys?
        if (empty($docEntryKeys)) {
            return [];       // none to be found
        }

        // A little weird: we can't use DoQuery because ONE parameter has to match the field and can't be something clever like a list of fields.....
        $query    = BinManager::areAdvanedBinsOn() ? 'QRY_DOCUMENTENTRYTRACKDETAIL_SELECT_BY_MANY_PARENTS_ADV' : 'QRY_DOCUMENTENTRYTRACKDETAIL_SELECT_BY_MANY_PARENTS';
        $qryArray = $this->_QM->getQuery($query);
        $qry      = $qryArray['QUERY'];
        $qry = PrepINClauseStmt($qry, $docEntryKeys, " AND d.docentrykey ",true,'trackdetailgetParent', true);
        $result   = QueryResult([$qry, GetMyCompany()],  0, '', null,  false);
        if ($result !== false) {
            $rtn = [];
            foreach ($result as $rec) {
                $externalRec = $this->_ProcessResult($rec);
                $docentry    = $externalRec['DOCENTRYNO'];
                $rtn[$docentry][$externalRec['RECORDNO']] = $externalRec;   // index by parent, then by record#
            }
            $result = $rtn;
        }
        return $result;
    }


    /**
     *      During a set() operation, get any existing tracking entries
     *
     * @param array     $values     the document tree prior to add() or set()
     */
    public function getExistingTrackingEntries(&$values)
    {
        if (isset($values['EXISTING_ENTRIES'])) {
            // Are we using a cache for this?
            if (($this->useGetByParentCacheForID == $values['RECORDNO']) &&
                ($this->getByParentCache !== NULL)) {
                $trackingEntries = $this->getByParentCache;
            } else {
                $docEntryKeys = [];
                foreach ($values['EXISTING_ENTRIES'] as $entry) {
                    $docEntryKeys[] = $entry['RECORDNO'];
                }
                $trackingEntries = $this->getManyByParent($docEntryKeys);
                // Are we cacheing these?
                if ($this->useGetByParentCacheForID == $values['RECORDNO']) {
                    $this->getByParentCache = $trackingEntries;
                }
            }

            // now attach the entries to the docentry records.....
            foreach ($values['EXISTING_ENTRIES'] as $key => $entry) {
                if (isset($trackingEntries[$entry['RECORDNO']])) {
                    $values['EXISTING_ENTRIES'][$key]['EXISTING_TRACKINGENTRIES'] = $trackingEntries[$entry['RECORDNO']];
                }
            }
        }
    }


    /**
     *      During the conversion from bins to advanced-bins, we need to update existing docentrycost records
     *  to have NO aisle and row, and maybe change the bin record# itself.
     *
     * @param string[]      $binInfo        an array with BINKEY (the existing key), WHSEKEY, AISLEKEY, and ROWKEY
     *
     * @return bool
     */
    public function updateTransactionsForNewBin($binInfo)
    {
        // Find the existing record, and then update it....
        // This is only used for upgrading bins, which is a CS tool, so I think the cache here is pretty safe.
        static $cache = null;

        if ($cache == null) {
            $cache = [];
            $stmt  = [];
            $stmt[0] = "SELECT det.record#, det.binkey, de.warehousekey as WHSEID, det.aislekey, det.rowkey
                    FROM  docentrytrackdetail det, docentry de
                    WHERE det.cny#=:1 AND de.cny#=:1
                     AND (det.binkey IS NOT NULL OR det.aislekey IS NOT NULL OR det.rowkey IS NOT NULL)
                     AND det.docentrykey = de.record#";
            $stmt[1] = GetMyCompany();
            $result = QueryResult($stmt);
            if ($result === false) {
                return false;
            }
            foreach ($result as $row) {
                $key = ($row['WHSEID'] ?? '') . '--' . ($row['BINKEY'] ?? '') . '--' . ($row['AISLEKEY'] ?? '') . '--' . ($row['ROWKEY'] ?? '');
                $cache[$key][] = $row['RECORD#'];
            }
        }

        $stmt = [];
        $stmt[0] = "UPDATE docentrytrackdetail SET ";
        $stmt[1] = GetMyCompany();
        $param   = 1;   // well, we've USED this many parameters

        // THIS table uses record#s and not IDs.
        if (isset($binInfo['NEW_BINKEY'])) {
            $param++;
            $stmt[0] .= "BINKEY = :$param, ";
            $stmt[$param] = $binInfo['NEW_BINKEY'];
        }
        $stmt[0] .= "AISLEKEY=NULL, ROWKEY=NULL ";

        // Now lets construct the where clause
        $stmt[0]  .= "WHERE cny#=:1 AND ";
        $param++;
        $stmt[0]  .= " RECORD# = :$param";
        $ok  = true;
        $key = ($binInfo['WHSEID'] ?? '') . '--' . ($binInfo['BINKEY'] ?? '') . '--' . ($binInfo['AISLEKEY'] ?? '') . '--' . ($binInfo['ROWKEY'] ?? '');
        if (isset($cache[$key])) {
            foreach ($cache[$key] as $rec) {
                $stmt[$param] = $rec;
                $ok = $ok && ExecStmt($stmt);
            }
        }

        // nothing to update for this iteration
        return $ok;
    }



}
