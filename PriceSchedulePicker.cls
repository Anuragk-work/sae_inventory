<?

/**
 *    FILE: PricePickerPicker.cls
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


import('NPicker');

/**
 * Class PriceSchedulePicker
 */
class PriceSchedulePicker extends NPicker
{
    /**
     * @param array $params
     */
    function __construct($params = [])
    {
        $params['entity'] = $params['entity'] ?? 'priceschedule';
        $params['fields'] = ['SCHEDULE', 'DESCRIPTION', 'STATUS'];
        $params['helpfile'] = 'C018';

        parent::__construct($params);
    }

    /**
     * @return array
     */
    function BuildQuerySpecAll() 
    {
        return($this->BuildQuerySpec());
    }

}
