<?php
//===========================================================================
//	FILE: LandedCostCategoryManager.cls
//	AUTHOR: Khiem Nguyen
//	DESCRIPTION:
//
//	(C) 2000,2018 Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	Corporation and is protected by the copyright laws.  Information
//	herein may not be used, copied or disclosed in whole or in part
//	without prior written consent from Intacct Corporation.
//===========================================================================

/**
 *    Class to manage a landed costs category object
 */
class LandedCostCategoryManager extends EntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "landedcostcategory::add";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);
        $values[':record#'] = $values['RECORDNO'] = $nextId;

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Landed Costs Category record!";
            $gErr->addIAError('INV-0756', __FILE__ . ':' . __LINE__, $msg, []);
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
        $source = "landedcostcategory::set";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->PrepValues($values);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Landed Costs Category record!";
            $gErr->addIAError('INV-0693', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param string $ID name or record# of the landed cost category
     * @param null|array $fields
     * @return array|false
     */
    function get($ID, $fields = null)
    {
        $lccatId = $ID;
        if ($lccatId != "" && is_numeric($lccatId)) {
            //Passed in $ID is a record no so we need to get the actual id
            $filter = array(
                'selects' => array('LCCATID'),
                'filters' => array(
                    array(
                        array('RECORDNO', '=', $lccatId),
                    )
                ),
            );
            $res = $this->GetList($filter);
            $lccatId = $res[0]['LCCATID'];
        } else {
            //Passed in $ID is an id, we should parse the name our just incase it's added
            list($lccatId) = explode('--', $lccatId);
        }
        $obj = parent::get($lccatId, $fields);
        if (empty($obj) || count($obj) == 0) {
            return null;
        }

        return $obj;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function PrepValues(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        $ok = true;

        return $ok;
    }

    /**
     * Delete a landed cost category record from the database
     *
     * @param string|int $ID id of landed cost category
     *
     * @return bool true if succeeded
     */
    public function Delete($ID)
    {
        $ok = true;

        //If this passed in LC category is being used on a txn, then we need to show error msg
        $qry = "SELECT count(*) count 
                FROM docentry 
                WHERE cny# = :1 AND lccatkey = (SELECT record# 
                                    FROM landedcostcategory 
                                    WHERE cny# = :1 and LCCATID= :2)";
        $result = QueryResult(array($qry, GetMyCompany(), $ID));
        if ($result[0]['COUNT'] != '0') {
            global $gErr;
            $source = "landedcostcategory::Delete";
            $msg = "\n\nThis landed cost category can't be deleted because it’s been used in a purchasing transaction. If you no longer want to use this landed cost category, change its status to Inactive.";
            $gErr->addIAError('INV-0757', __FILE__ . ':' . __LINE__,'', [], $msg, []);
            epp("$source: Error: $msg");
            $ok = false;
        }

        $ok = $ok && parent::Delete($ID);

        return $ok;
    }
}

