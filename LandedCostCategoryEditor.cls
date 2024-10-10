<?php
/**
 * =============================================================================
 *
 * FILE:        LandedCostCategoryEditor.cls
 * AUTHOR:      Khiem Nguyen
 * DESCRIPTION: Editor class for handelling landed costs category object
 *
 * (C)2000,2018 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

/**
 * Editor class for LandedCostCategoryEditor object
 */
class LandedCostCategoryEditor extends FormEditor
{
    /**
     * Constructor
     *
     * @param array $_params Initial params
     */
    public function __construct($_params)
    {
        parent::__construct($_params);
    }

    /**
     * Override to intialize data
     *
     * @param array &$obj   the data
     *
     * @return bool         true on success and false on failure
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $ok = parent::mediateDataAndMetadata($obj);

        //Default new LC category with weight
        if ($this->state == $this->kShowNewState) {
            $obj['LANDEDCOSTDISTMETHOD'] = 'Weight';
        } else {
            //We are in edit state if we get here so we need to disable the distribution method field if this lc category has been used in a txn
            $lccatId = $obj['LCCATID'];
            $qry = "SELECT count(*) count FROM docentry WHERE lccatkey = '$lccatId' AND cny# = :1";
            $result = QueryResult(array($qry, GetMyCompany()));
            if ($result[0]['COUNT'] != '0') {
                $this->getView()->findAndSetProperty(array('path' => 'LANDEDCOSTDISTMETHOD'), array('readonly' => true));
            }
        }

        return $ok;
    }

    /**
     * CanSaveAndNew - show the 'Save and New' button
     *
     * @return bool true
     */
    protected function CanSaveAndNew()
    {
        return true;
    }
}

