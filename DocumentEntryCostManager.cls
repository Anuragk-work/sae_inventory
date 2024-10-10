<?

/**
 *    FILE:
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */

define('SERIALNO_ENABLED', 1);
define('LOTNO_ENABLED', 2);
define('BINNO_ENABLED', 4);
define('EXPIRATION_ENABLED', 8);

define('BUILD_KIT', 'Build Kits');
define('DIS_KIT', 'Disassemble Kits');

class DocumentEntryCostManager extends EntityManager
{
    /* @var array $sourceDocEntryCostKeys */
    private static $sourceDocEntryCostKeys = array();

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {

        $source = 'DocumentEntryCostManager::Add';
        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            global $gErr;
            $msg = "Could not create transaction line item!";
            $gErr->addIAError('INV-0346', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        // invalidate the cache.  Harsh, but safer.
        self::$sourceDocEntryCostKeys = [];
        return $ok;
    }

    /**
     * @return bool
     */
    public function IsAuditEnabled()
    {
        // disable auditing on this system managed object
        return false;
    }

    /**
     * @param int   $docEntryKey
     * @param array $entry
     * @param bool  $noSource
     * @param bool  $getFirstOnly Return only the first record if true (default)
     *
     * @return array
     */
    public static function getParentDocentryCostDetail($docEntryKey, $entry, $noSource, $getFirstOnly = true)
    {
        $itemID = $entry['ITEMID'];
        $sNo = $entry['SERIALNO'];
        $lNo = $entry['LOTNO'];
        $aisle = $entry['AISLEKEY'];
        $row = $entry['ROWKEY'];
        $bin = $entry['BINKEY'];

        $key = $itemID . '~' . $sNo . '~' . $lNo . '~' . $aisle . '~' . $row . '~' . $bin . '~' . ($noSource ? '1' : '0');
        if ( ! isset(self::$sourceDocEntryCostKeys[$docEntryKey][$key])) {

            $where = "where cny# = :1 AND affects_inventory != 'Q' AND itemkey = :3 ";

            $qry = array();
            $qry[] = '';
            $qry[] = GetMyCompany();
            $qry[] = $docEntryKey;
            $qry[] = $itemID;
            $bind = count($qry);

            if ($sNo) {
                $where .= " AND serialno = :" . $bind++;
                $qry[] = $sNo;
            }

            if ($lNo) {
                $where .= " AND lotno = :" . $bind++;
                $qry[] = $lNo;
            }

            //This check is specific for Advance bin companies, since bin will have all the details
            if (BinManager::areAdvanedBinsOn() == false) {
                if ($aisle) {
                    $where .= " AND aislekey = :" . $bind++;
                    $qry[] = $aisle;
                }
                if ($row) {
                    $where .= " AND rowkey = :" . $bind++;
                    $qry[] = $row;
                }
            }

            if ($bin) {
                $where .= " AND binkey = :" . $bind; // Last instance of $bind so no ++
                $qry[] = $bin;
            }

            if ($noSource) {
                $qry[0] = "select * from docentrycost $where
                    AND docentrykey = :2 order by datein desc, record# desc";
            } else {
                $qry[0] = "select * from docentrycost $where
                    AND docentrykey in (
                      select record# from docentrymst where cny# = :1 START WITH cny# = :1 AND record# = :2  
                      CONNECT BY cny# = :1 and record# = PRIOR source_doclinekey
                    ) order by datein desc, record# desc";
            }

            $res = QueryResult($qry);

            self::$sourceDocEntryCostKeys[$docEntryKey][$key] = $res;
        }

        $rtn = self::$sourceDocEntryCostKeys[$docEntryKey][$key] ?? [];
        if ($getFirstOnly) {
            $rtn = $rtn[0] ?? [];
        }
        return $rtn;
    }

    /**
     * @param array  $recordNos     the record numbers, or docentrycostkey numbers, or whatever
     * @param bool   $kits          is this for kits or not?
     * @param string $column        what are the recordnos?
     * @param string $setNull       what you want set to null, defaults to the docentrycostkey
     *
     * @return bool
     */
    public static function emptyDocentryCostKeys($recordNos, $kits = false, $column = 'record#', $setNull = 'docentrycostkey')
    {
        $table = 'docentrycost';
        if ($kits) {
            $table = 'docentrycostkits';
        }
        $stmt = array();
        $stmt[] = "UPDATE $table SET $setNull = NULL WHERE cny# = :1 ";
        $stmt[] = GetMyCompany();
        $stmt = PrepINClauseStmt($stmt, $recordNos, "AND $column", true);

        $ok = ExecStmt($stmt);

        return $ok;
    }


    /**
     *      Get ready to add or upsert a collection of DocEntryCost records for ONE DocEntry.
     *  This returns a 'context' to be passed into incrementalAddOrUpsert(), below, for each
     *  record that you want to add or upsert.  Call finishAddOrUpsert(), below, when all done
     *  for one DocEntry record.
     *
     *      Note: on advice from Senthil, made these 'static'
     *
     *      Late-breaking news: there were a few defects found in upserting docentrycost records, around
     *          things like the code that looks for source records complaining that there is no qtyleft
     *          because it is still in use by the transaction we are updating.  So...... now in DocumentManager
     *          I delete the docentrycost records using deleteAllforDocHdr(), below.  But, I left the upsert
     *          code here so that some brave soul can attempt this again some day.....
     *
     * @param int|string    $docEntryKey        The docentry record number
     *
     * @return array                            the context to be passed to addOrUpsert(), above
     * @throws Exception
     */
    static function prepareToAddOrUpsert($docEntryKey)
    {
        $docentryCostMgr = Globals::$g->gManagerFactory->getManager('documententrycost');
        DocumentManager::updatingEntity($docentryCostMgr->_entity);
        $matchmaker = new Matchmaker($docentryCostMgr);
        $ok = true;
        if (DocumentManager::$upsertFeaturInUse) {
            $ok = $matchmaker->getCurrentRecords("DOCENTRYKEY", $docEntryKey);
            $matchmaker->setDupMatchesAreOk(true); // allow looser matching
        }
        $context = [];
        $context['Matchmaker']  = $matchmaker;
        $context['DOCENTRYKEY'] = $docEntryKey;
        $context['OK']          = $ok;
        return $context;
    }


    /**
     *      A note about why this is different than the ordinary upsert:
     *  The old/existing code would do an regularAdd() (because the old docentrycost records had been deleted)
     *  and then after the add, use the returned recordno in the tables for future calculations.
     *
     *  So, here, as long as we get a match, we're golden.  Ass soon as we have to ADD() a record, we
     *  delete the remaining existing records to make room for the newly added record(s) and then add
     *  from there on out.  Not great, but without rewriting the code in CostingHandler and Costing,
     *  this seems the easiest.....
     *
     *
     * @param array             $context            The context returned by prepareToAddOrUpsert(), above
     * @param array             $docEntryCost       The new docentrycost record
     *
     * @return bool                                 Are things going well?
     */
    static function incrementalAddOrUpsert(&$context, &$docEntryCost)
    {
        $ok = $context['OK'];
        if ($ok) {
            if (DocumentManager::$upsertFeaturInUse) {
                $match = $context['Matchmaker']->matchRecord($docEntryCost);
                switch ($match) {
                    case Matchmaker::IGNORE_IDENTICAL:
                        break;
                    case Matchmaker::USE_SET:
                        $ok = $context['Matchmaker']->entityManager->set($docEntryCost);
                        break;
                    case Matchmaker::USE_ADD:
                        $context['Matchmaker']->deleteOldRecords(); // sadly, we must abort the upsert....
                        // why? because we otherwise might not be able to add a new record while the old
                        // record still holds onto the qtyleft....
                        $ok = $context['Matchmaker']->entityManager->add($docEntryCost);
                        break;
                }
            } else {
                $ok = $context['Matchmaker']->entityManager->add($docEntryCost);  // just add it, not upserting
            }
        }
        $context['OK']  = $ok;
        return $ok;
    }


    /**
     *      Complete the add-or-upsert processing for one DocEntry record.
     *
     * @param array             $context            The context returned by prepareToAddOrUpsert(), above
     *
     * @return bool
     *
     */
    static function finishAddOrUpsert(&$context)
    {
        $ok = $context['OK'];
        if (DocumentManager::$upsertFeaturInUse) {
            $context['Matchmaker']->deleteOldRecords();
        }
        unset($context['Matchmaker']);  // free up the class instance
        unset($context);

        return $ok;
    }


    /**
     *      Given a series of DocEntry record numbers, remove docentrycost records
     *
     * @param   int[]           $docEntryKeys       Array of docentry record numbers
     *
     * @return  bool
     */
    public static function deleteAllWithTheseDocEntryKeys($docEntryKeys)
    {
        // 1) Get the record numbers so we can clean up other records....
        $ok      = true;
        $decs    = [];  // doc entry costs
        $stmt    = [];
        $stmt[0] = "select record# from docentrycost where cny#=:1 ";
        $stmt[1] = GetMyCompany();
        $stmt    = PrepINClauseStmt($stmt, $docEntryKeys, "AND docentrykey ", true);
        $result  = QueryResult($stmt);
        if ($result === false) {
            return false;
        }
        foreach ($result as $row) {
            $decs[] = $row['RECORD#'];
        }

        // 2) remove references to them....
        if ( ! empty($decs)) {
            $ok      = $ok && self::emptyDocentryCostKeys($decs, false, 'docentrycostkey');
            $ok      = $ok && self::emptyDocentryCostKeys($decs, false, 'adjdocentrycostkey','adjdocentrycostkey');
            $ok      = $ok && self::emptyDocentryCostKeys($decs, true,  'docentrycostkey');

            // 3) now delete them
            $stmt    = [];
            $stmt[0] = "delete docentrycost where cny#=:1 ";
            $stmt[1] = GetMyCompany();
            $stmt    = PrepINClauseStmt($stmt, $decs, "AND record# ", true);
            $ok      = $ok && ExecStmt($stmt);
        }
        return $ok;
    }



    /**
     *      Given a doc header record number, remove any docentrycost records
     *
     * @param   int|string      $docHdrKey          The doc header record # to remove docentrycosts for
     *
     * @return  bool
     */
    public static function deleteAllforDocHdr($docHdrKey)
    {
        // 1) Get the record numbers so we can clean up other records....
        $ok      = true;
        $decs    = [];  // doc entry costs
        $stmt    = [];
        $stmt[0] = "select dec.record# from docentrycost dec, docentry de where dec.cny#=:1 and de.cny#=dec.cny# and dec.docentrykey=de.record# and de.dochdrkey=:2 ";
        $stmt[1] = GetMyCompany();
        $stmt[2] = $docHdrKey;
        $result  = QueryResult($stmt);
        if ($result === false) {
            return false;
        }
        foreach ($result as $row) {
            $decs[] = $row['RECORD#'];
        }

        // 2) remove references to them....
        if ( ! empty($decs)) {
            $ok      = $ok && self::emptyDocentryCostKeys($decs, false, 'docentrycostkey');
            $ok      = $ok && self::emptyDocentryCostKeys($decs, true,  'docentrycostkey');

            // 3) now delete them
            $stmt    = [];
            $stmt[0] = "delete docentrycost where cny#=:1 ";
            $stmt[1] = GetMyCompany();
            $stmt    = PrepINClauseStmt($stmt, $decs, "AND record# ", true);
            $ok      = $ok && ExecStmt($stmt);
        }
        return $ok;
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
        return $this->updateTransactionsForNewBinCommon($binInfo, 'docentrycost');
    }


    /**
     *      Workhorse for the above function so that we can share this code with docentrycostkits....
     *
     * @param string        $table          the actual sql table, so we can share this with docentrycostkits
     * @param string[]      $binInfo        an array with BINKEY (the existing key), WHSEKEY, AISLEKEY, and ROWKEY
     *
     * @return bool
     */
    public function updateTransactionsForNewBinCommon($binInfo, $table)
    {
        $stmt = [];
        $stmt[0] = "UPDATE $table SET ";
        $stmt[1] = GetMyCompany();
        $param   = 1;   // well, we've USED this many parameters

        if (isset($binInfo['NEW_BINKEY'])) {
            $param++;
            $stmt[0] .= "BINKEY = :$param, ";
            $stmt[$param] = $binInfo['NEW_BINKEY'];
        }
        $stmt[0] .= "AISLEKEY=NULL, ROWKEY=NULL ";

            // Now lets construct the where clause
        $stmt[0]  .= "WHERE cny#=:1 AND ";
        if (isset($binInfo['BINKEY']) && ($binInfo['BINKEY'] != 0)) {
            $param++;
            $stmt[0] .= "BINKEY = :$param";
            $stmt[$param] = $binInfo['BINKEY'];
        } else {
            $stmt[0] .= "BINKEY IS NULL";
        }
        $stmt[0] .= ' AND ';
        if (isset($binInfo['WHSEID']) && ($binInfo['WHSEID'] != '')) { // we don't expect this to be null, but....
            $param++;
            $stmt[0] .= "WHSEKEY = :$param";
            $stmt[$param] = $binInfo['WHSEID'];
        } else {
            $stmt[0] .= "WHSEKEY IS NULL";
        }
        $stmt[0] .= ' AND ';
        if (isset($binInfo['AISLEKEY']) && ($binInfo['AISLEKEY'] != 0)) {
            $param++;
            $stmt[0] .= "AISLEKEY = :$param";
            $stmt[$param] = $binInfo['AISLEKEY'];
        } else {
            $stmt[0] .= "AISLEKEY IS NULL";
        }
        $stmt[0] .= ' AND ';
        if (isset($binInfo['ROWKEY']) && ($binInfo['ROWKEY'] != 0)) {
            $param++;
            $stmt[0] .= "ROWKEY = :$param";
            $stmt[$param] = $binInfo['ROWKEY'];
        } else {
            $stmt[0] .= "ROWKEY IS NULL";
        }

        return ExecStmt($stmt);
    }

}
