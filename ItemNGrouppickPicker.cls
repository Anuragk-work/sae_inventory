<?php

/**
 * Picker item for Item and Group Picker
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation, All Rights Reserved
 */

/**
 * Picker item for Item and Group Picker
 */

/**
 * Class ItemNGrouppickPicker
 */
class ItemNGrouppickPicker extends ItempickPicker
{
    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $params['entity'] = 'itemngrouppick';
        $params['sortcolumn'] = 'type:a,pickid:a';
        parent::__construct($params);
        $this->canFilterSupplies = false;
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