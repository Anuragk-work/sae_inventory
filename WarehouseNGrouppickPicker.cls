<?php

/**
 * Picker class for Warehouse and Group Picker
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class WarehouseNGrouppickPicker
 */
class WarehouseNGrouppickPicker extends WarehousepickPicker
{

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $params['entity'] = 'warehousengrouppick';
        $params['sortcolumn'] = 'type:d,pickid:a';
        parent::__construct($params);
    }

    /**
     * add fields for group picker    
     * 
     * @param array $params picker param
     */
    protected function addGrpFields(&$params)
    {
        $params['fields'][] = 'TYPE';
    }     
}
