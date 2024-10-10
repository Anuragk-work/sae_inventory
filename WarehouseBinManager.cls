<?php

/***	FILE:
*	AUTHOR: Manoj Mahur
*	DESCRIPTION:
*
*	(C) 2000, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/


import('OwnedObjectManager');

/**
 * Class WarehouseBinManager
 */
class WarehouseBinManager extends OwnedObjectManager
{
    /** @var string[][] $cache   The cache of AISLES, ROWS, SIZES, FACES, and ZONES */
    private $cache = null;


    const idForKey = [
        'AISLEKEY'  => 'AISLEID',
        'ROWKEY'    => 'ROWID',
        'ZONEKEY'   => 'ZONEID',
        'FACEKEY'   => 'FACEID',
        'BINSIZEKEY'=> 'SIZEID',
        ];

    const tableForKey = [
        'AISLEKEY'  => 'icaisle',
        'ROWKEY'    => 'icrow',
        'ZONEKEY'   => 'iczone',
        'FACEKEY'   => 'icbinface',
        'BINSIZEKEY'=> 'icbinsize',
    ];

    const idFieldForKey = [
        'AISLEKEY'  => 'aisleid',   // most are normal
        'ROWKEY'    => 'rowkey',    // but rows are wacky
        'ZONEKEY'   => 'zoneid',
        'FACEKEY'   => 'faceid',
        'BINSIZEKEY'=> 'sizeid',
    ];

    /** @var int[] $countOfLastPickListQuery */
    private $countOfLastPickListQuery = [];

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        if (BinManager::areAdvanedBinsOn()) {
            // We're just a proxy for the bin manager now
            $binMgr = Globals::$g->gManagerFactory->getManager('bin');
            $ok = $binMgr->add($values);
        } else {
            // old format, classic mode
            $ok = parent::regularAdd($values); // miraculously, this works.
        }
        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        if (BinManager::areAdvanedBinsOn()) {
            // We're just a proxy for the bin manager now
            $binMgr = Globals::$g->gManagerFactory->getManager('bin');
            $binMgr->enableCache();         // leap of faith here: there will be a LOT of updates on warehouse SAVE
            $ok = $binMgr->set($values);
        } else {
            // old format, classic mode
            $ok = parent::regularSet($values); // miraculously, this works.
        }
        return $ok;
    }


    /**
     * Get a single record
     *
     * @param string        $ID     (was BINID, but that wasn't right, so now its RECORDNO)
     * @param string[]|null $fields
     *
     * @return array|false
     */
    function get($ID, $fields = null)
    {
        if (BinManager::areAdvanedBinsOn()) {
            // We're just a proxy for the bin manager now
            $binMgr = Globals::$g->gManagerFactory->getManager('bin');
            $rtn = $binMgr->getByRecordNumber($ID, $fields);
        } else {
            // old format, classic mode
            $rtn = ExecStmt(["SELECT whsebin.record#,whsebin.whsekey,whsebin.binid,icbin.BINDESC 
                                FROM whsebin, icbin
                                WHERE whsebin.cny#=:1 and icbin.cny#=:1 and whsebin.record#=:2
                                    and whsebin.binid = icbin.binid",
                            GetMyCompany(), $ID]);
        }
        return $rtn;
    }


    /**
     * Delete a record from the database
     *
     * Redirect Advanced requests to the bin manager
     *
     * @param string|int $ID vid of entity
     *
     * @return bool
     */
    public function Delete($ID)
    {
        if (BinManager::areAdvanedBinsOn()) {
            // when warehouse upsert wants to delete reords, it deletes by record# and NOT by vid.
            // so, $ID is likely a record number; look up the vid for the bin manager....
            if (is_numeric($ID)) {
                $result = QueryResult(["select binid from icbin where cny#=:1 and record#=:2", GetMyCompany(), $ID]);
                if (($result !== false) && ( ! empty($result))) {
                    $ID = $result[0]['BINID'];
                }
            }
            // We're just a proxy for the bin manager now
            $binMgr = Globals::$g->gManagerFactory->getManager('bin');
            $ok = $binMgr->Delete($ID);
        } else {
            // old format, classic mode
            $ok = parent::Delete($ID); // miraculously, this works.
        }
        return $ok;
    }


    /**
     * Get all objects owned by a parent (OVERRIDE)
     *
     *  Proxy to the BinManager...
     *
     * @param  string $_parent id of the parent
     *
     * @return array            the bin list, may be empty on error
     */
    function getByParent($_parent)
    {
        if (BinManager::areAdvanedBinsOn()) {
            // hopefully this works in classic mode too!
            $binMgr = Globals::$g->gManagerFactory->getManager('bin');
            $rtn = $binMgr->getByWarehouse($_parent);
       } else {
            // the default generated get-by-parent does not work because of the fields I can't get to...
            $query = $this->_QM->_queryList['QRY_WAREHOUSEBIN_SELECT_BY_PARENT'];
            $fixThese = ['aisleid','row_id','zoneid','faceid','sizeid'];
            foreach ($fixThese as $field) {
                $query = str_replace("DUMMY.$field", "' ' as $field", $query);
            }
            $this->_QM->_queryList['QRY_WAREHOUSEBIN_SELECT_BY_PARENT'] = $query;    // REPLACE THIS

            $rtn = parent::getByParent($_parent);
            if ($rtn !== false) {
                foreach ($rtn as $index => $row) {
                    $rtn[$index]['BINIDCLASSIC'] = $row['BINID'];
                }
            }
        }
        return $rtn;
    }


    /**
     *      Get an ID field, given a KEY field.  For example, get the SIZEID from the SIZEKEY
     *
     *  Now, it is likely that MOST customers will not use ALL of these a ton.  And, for example, there are
     *  lilely to be just a handful of ZONEIDs and FACEIDs and SIZEids.  Though, there could be a lot of AISLEs and ROWS.
     *
     *  We cache these so as to not spend lots of time fetching things.
     *
     *
     * @param string    $field  the KEY we want the ID for, like AISLEKEY
     * @param string    $value  what is the record number for the key?
     *
     * @return string   The ID if found
     */
    protected function getIdForKey($field, $value)
    {
        // have we set up the cache at all?
        if ($this->cache === null) {
            $this->cache = [];
            foreach (self::idForKey as $key => $id) {
                $this->cache[$key] = null;  // so we know we have not tried to fetch them
            }
        }

        // have we fetched THIS cache?
        if ($this->cache[$field] == null) {
            // build the cache
            $this->cache[$field] = [];  // so we know we tried, and don't try again
            $table = self::tableForKey[$field];
            $idField = self::idFieldForKey[$field];
            $result = QueryResult(["select record#, $idField id from $table where cny#=:1", GetMyCompany()]);   // get them ALL
            if (($result !== false) && ( ! empty($result))) {
                foreach ($result as $row) {
                    $this->cache[$field][$row['RECORD#']] = $row['ID'];
                }
            }
        }

        // It is unlikely to NOT be in the list here, but just in case....
        return ($this->cache[$field][$value] ?? '');
    }


    /**
     * Return a list of entities
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        // Hack hack wheeze wheeze:
        //  when filling the picker, we want to do a query to get the bins for this warehouse.
        //  fine.
        //  but, we also want to show the COUNT of items IN that bin, and, sometimes, ONLY show bins with
        //  counts in them.
        if (isset($params['filters'][0][0][2][0]) && (strpos($params['filters'][0][0][2][0], '--') !== false)) {
            $warehoueItemRestrict = $params['filters'][0][0][2][0];
            // format is <warehouseID> -- <itemID> -- ['NO'] 'RESTRICT'
            list($warehouse, $itemID, $restrict) = explode('--', $warehoueItemRestrict);
            if (BinManager::areAdvanedBinsOn()) {
                $binMgr = Globals::$g->gManagerFactory->getManager('bin');
                $addlFilters= array_slice($params['filters'][0],1);
                $table = $binMgr->getBinPicklist($warehouse, $itemID, ($restrict == 'RESTRICT'),$addlFilters );
                if ($table !== false) {
                    $this->countOfLastPickListQuery[$warehoueItemRestrict] = (int)count($table);    // to save time on the count
                }
                return $table;
            }
            // othrewise put back just the warehouse, like we used to use.....
            $params['filters'][0][0][2][0] = $warehouse;
        }
        return parent::GetList( $params, $_crosscny, $nocount );
    }

    /**
     * Get count based on criteria
     *
     * @param array $params parameters for the query
     *
     * @return int
     */
    function GetCount($params)
    {
        // Hack hack wheeze wheeze:
        //  same issue as above
        if (isset($params['filters'][0][0][2][0]) && (strpos($params['filters'][0][0][2][0], '--') !== false)) {

            // The combo picker asks this question right after doing the query, so save a little time.....
            // (the query is non-trivial)
            $warehoueItemRestrict = $params['filters'][0][0][2][0];
            if (isset($this->countOfLastPickListQuery[$warehoueItemRestrict])) {
                return $this->countOfLastPickListQuery[$warehoueItemRestrict];
            }
            $table = $this->GetList($params);
            if (($table === false) || empty($table)) {
                return 0;
            }
            return count($table);
        }
        return parent::GetCount($params);
    }



}
