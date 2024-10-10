<?php

/**
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 * 
 * @author    Manoj Mahur <mmahur@intacct.com>
 * @desc      AisleManager.cls
 * @copyright 2000-2009 Intacct Corporation
 */

import('EntityManager');
/*
 * class AisleManager extends EntityManager
 */
class AisleManager extends EntityManager
{
    /**
     * Overridden to to API specific validation
     *  
     * @param array $values Array Set of values to update
     *
     * @return bool signifying success or failuure
     */
    public function API_Set(&$values)
    {
        // Check if API is intentionally trying to change the EMPLOYEEID of an employee
        $ok   = true;
        $gErr = Globals::$g->gErr;
        $aisleData = $this->API_Get($values['RECORDNO']);

        if ( !empty($aisleData[0]) ) {
            if ( $aisleData[0]['AISLEID'] != $values['AISLEID'] ) {
                $gErr->addIAError('INV-0001', __FILE__ . ':' . __LINE__, "AISLEID cannot be updated or modified.", []); 
                $ok = false;
            }
        }

        return $ok && parent::API_Set($values);
    }


    /**
     *      Sometimes, we have an aisle record number (aisleKEY) and want the ID
     *
     * @param int|string    $aisleKey     The aisle record#
     *
     * @return string                   The aisle name
     */
    public static function IdForKey($aisleKey)
    {
        $result = QueryResult([ "SELECT aisleid FROM icaisle  WHERE cny#=:1 AND record#=:2", GetMyCompany(), $aisleKey]);
        if (($result !== false) && ( ! empty($result))) {
            return $result[0]['AISLEID'];
        }
        return '';
    }
}
