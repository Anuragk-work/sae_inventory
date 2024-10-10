<?php
//===========================================================================
//	FILE: uommanager.cls
//	AUTHOR: John P. Campbell
//	DESCRIPTION:
//
//	(C) 2000, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	Corporation and is protected by the copyright laws.  Information
//	herein may not be used, copied or disclosed in whole or in part
//	without prior written consent from Intacct Corporation.
//===========================================================================
import('EntityManager');

/**
 *    Class to manage a Unit of Manager 
 *
 *    Table:
 *        CNY#         NUMBER 
 *      UNIT         VARCHAR2(10)
 *      STATUS       CHAR(1)
 */
class UOMDetailManager extends OwnedObjectManager
{
    /**
     * @var array $unitCache
     */

    public $unitCache;

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "UOMDetail::Add";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->ValidateUOM($values);
        
        $ok = $ok && OwnedObjectManager::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create UOM record!";
            $gErr->addError('INV-0928', __FILE__ . ':' . __LINE__, $msg);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
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
        $source = "UOMDetail::Set";

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->ValidateUOM($values);
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not set UOM record!";
            Globals::$g->gErr->addError('INV-0929', __FILE__ . ':' . __LINE__, $msg);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }


    /** 
     * Validating the decimal digits for unit of measure, max value is 4
     *
     * @access private
     * @param array $values
     *
     * @return bool
     */
    public function ValidateUOM(&$values)
    {
        global $gErr;
        $ok = true;

        // removing the more than one white space
        $values['UNIT'] = isl_preg_replace('/\s\s+/', ' ', trim($values['UNIT']));

        if ($values['ABBREVIATION'] !== '') {
            // removing the more than one white space
            $values['ABBREVIATION'] = isl_preg_replace('/\s\s+/', ' ', trim($values['ABBREVIATION']));
        }

        if ($values['NUMDECIMALS'] > 4) {
            $gErr->addError(
                'INV-0263', __FILE__.':'.__LINE__,
                "Maximum number of decimal places is 4."
            );
            $ok = false;
        }
        
        if ($values['ISBASE'] != 'true') {
            $values['ISBASE'] = 'false';
        }

        return $ok;
    }

    /**
     * @param array $unitsArr
     * @param bool $refresh
     *
     * @return array
     */
    public function GetUOMRawCache($unitsArr, $refresh = false)
    {
        
        if ($refresh || count($this->unitCache) == 0) {
            $stmt = array();
            $stmt[0] = 'SELECT * FROM icuom WHERE cny# = :1 ';
            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, $unitsArr, " and icuom.unit ");
            $res = QueryResult($stmt);

            $this->unitCache = array();
            $unitcnt = count($res);
            if ($unitcnt > 0) {
                for ($j = 0; $j < $unitcnt ; $j++) {
                    $this->unitCache[strval($res[$j]['UNIT'])] = $res[$j];
                }
            }       
        }
        return $this->unitCache;        
    } 

    /**
     * @param array $UOMDetailsList
     * @param       $uomGroupKey
     * returns only the list of  UOM used in Transactions among the given list of UOM details
     * @return false|string[][]
     */
    public static function getUsedUOMDetails(array $UOMDetailsList, $uomGroupKey,bool $ignoreDraftState=false) : array|false
    {
        $subQuery = "SELECT 1
                        FROM docentrymst de
                        INNER JOIN dochdrmst dh ON dh.cny# = de.cny# AND dh.record# = de.dochdrkey
                        INNER JOIN icitemmst it ON it.cny# = de.cny# AND it.itemid = de.itemkey AND it.uomgrpkey = :2
                        WHERE de.cny# = uom.cny# and de.unit =uom.unit
                          ";
        if ($ignoreDraftState){
            $subQuery .= " AND dh.state <> 'I'";
        }

        $uomDetailQry[0] = "SELECT uom.unit
                                FROM icuom uom
                                WHERE uom.cny# = :1
                                AND uom.grpkey = :2
                                 ";
        $uomDetailQry[0] = PrepINClauseStmt($uomDetailQry[0], $UOMDetailsList,
                                            " AND uom.unit ", false, '', true);

        $uomDetailQry[0] .= " AND EXISTS ( $subQuery )";
        $uomDetailQry[1] = GetMyCompany();
        $uomDetailQry[2] = $uomGroupKey;

        $res = QueryResult($uomDetailQry);

        return $res;
    }

    /**
     * @param $newUOM
     * @param $OldUOM
     * Returns true if 2 UOMs are requal in value
     * @return bool
     */
    public static function areUOMsEqual($newUOM, $OldUOM) : bool
    {
        return (       ($newUOM['UNIT'] == $OldUOM['UNIT'])
                    && ($newUOM['ISBASE'] == $OldUOM['ISBASE'])
                    && ($newUOM['CONVFACTOR'] == $OldUOM['CONVFACTOR'])
                    && ($newUOM['ABBREVIATION'] == $OldUOM['ABBREVIATION'])
                    && ($newUOM['NUMDECIMALS'] == $OldUOM['NUMDECIMALS'])) ;
    }
}

