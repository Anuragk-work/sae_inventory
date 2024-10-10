<?
/**
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 * 
 * @author    Manoj Mahur <mmahur@intacct.com>
 * @desc      IcrowManager.cls
 * @copyright 2000-2009 Intacct Corporation
 */

import('EntityManager');
/*
 * class icrowManager extends EntityManager 
 */
class icrowManager extends EntityManager
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
        $ok           = true;
        $gErr         = Globals::$g->gErr;
        $rowData = $this->API_Get($values['RECORDNO']);

        if ( $rowData !== false && is_array($rowData) ) {
            if ( $rowData[0]['ROWKEY'] != $values['ROWKEY'] ) {
                $gErr->addIAError('INV-0131', __FILE__ . ':' . __LINE__,
                    "ROWKEY cannot be updated or modified.",
                    []
                );
                $ok = false;
            }
        }

        return $ok && parent::API_Set($values);
    }


    /**
     *      Sometimes, we have a row record number (rowKEY) and want the ID
     *
     * @param int|string    $rowKey     The row record#
     *
     * @return string                   The row name
     */
    public static function IdForKey($rowKey)
    {
        $result = QueryResult([ "SELECT rowkey FROM icrow  WHERE cny#=:1 AND record#=:2", GetMyCompany(), $rowKey]);
        if (($result !== false) && ( ! empty($result))) {
            return $result[0]['ROWKEY'];
        }
        return '';
    }
}

