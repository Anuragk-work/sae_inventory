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

class replenishforecastwarehousepickManager extends replenishforecastitemwarehpickManager
{

    /**
     * @param array $params
     */
    function __construct($params = [])
    {
        $params['entity'] = 'replenishforecastwarehousepick';
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
//        $params['filters'][0] [] = ['enable_replenishment', '= ', 'T'];
        $token = ['IA.NO_WAREHOUSE_INDICATED'];
        $textMap = getLocalizedText(I18N::tokenArrayToObjectArray($token), $errMsg);

        $list = parent::GetList($params, $_crosscny, $nocount);
        $novalue[]  = [
            'PICKID' => GT($textMap, 'IA.NO_WAREHOUSE_INDICATED'),
        ];
        $newlist = array_merge($novalue, $list);

        return $newlist;
    }




}



