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
 * class BinsizeManager extends EntityManager
 */
class BinsizeManager extends EntityManager
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
        $binsizeData = $this->API_Get($values['RECORDNO']);

        if ( !empty($binsizeData[0]) ) {
            if ( $binsizeData[0]['SIZEID'] != $values['SIZEID'] ) {
                $gErr->addIAError('INV-0003', __FILE__ . ':' . __LINE__, "SIZEID cannot be updated or modified.", []);
                $ok = false;
            }
        }

        return $ok && parent::API_Set($values);
    }

}
