<?
/**
*   FILE: AdminApproverPickManager.cls
*   AUTHOR: srao
*   DESCRIPTION:
*
*   (C) 2000, Intacct Corporation, All Rights Reserved
*
*   This document contains trade secret data that belongs to Intacct
*   Corporation and is protected by the copyright laws.  Information
*   herein may not be used, copied or disclosed in whole or in part
*   without prior written consent from Intacct Corporation.
*/

class AdminApproverPickManager extends ApproverPickManager
{

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $params['isadmin'] = true;
        parent::__construct($params);
    }


    /**
     * @return null
     */
    public static function GetSystemApprovers()
    {
        return null;
    }
}


