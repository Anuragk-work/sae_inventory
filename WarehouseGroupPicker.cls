<?php

/**
 * Picker class for Warehousegroup Picker
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class WarehouseGroupPicker
 */
class WarehouseGroupPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
                'entity' => 'warehousegroup',
                'pickfield' => 'ID',
                'addlPickFields' => array('NAME'),
                'fields' => array('ID', 'NAME', 'GROUPTYPE', 'DESCRIPTION'),
            )
        );
    }

}
