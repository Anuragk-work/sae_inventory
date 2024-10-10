<?
/**
 *   FILE: RenewalMacroPickManager.cls
 *   AUTHOR:    Nirmal
 *   DESCRIPTION:
 *
 *   (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *   This document contains trade secret data that belongs to Intacct
 *   Corporation and is protected by the copyright laws.  Information
 *   herein may not be used, copied or disclosed in whole or in part
 *   without prior written consent from Intacct Corporation.
 */

class replenishforecastitempickManager extends ItemPickManager
{

    /**
     * @param array $params
     */
    function __construct($params = [])
    {
        $params['entity'] = 'replenishforecastitemepick';
        parent::__construct($params);
    }



}



