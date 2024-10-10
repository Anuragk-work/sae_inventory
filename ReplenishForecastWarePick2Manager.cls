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

class replenishforecastwarepick2Manager extends replenishforecastitemwarehpickManager
{

    /**
     * @param array $params
     */
    function __construct($params = [])
    {
        $params['entity'] = 'replenishforecastwarepick2';
        parent::__construct($params);
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
        // only warehouses that have replenishment enabled
        $params['filters'][0] [] = ['enable_replenishment', '= ', 'T'];
        $list = parent::GetList($params, $_crosscny, $nocount);
        return $list;
    }




}



