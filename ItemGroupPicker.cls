<?php

/**
 * Picker class for Itemgroup Picker
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Picker class for Itemgroup Picker
 */

/**
 * Class ItemGroupPicker
 */
class ItemGroupPicker extends NPicker
{

    function __construct()
 {
        parent::__construct(
            array(
            'entity'        =>  'itemgroup',
            'pickfield'        =>  'ID',
                'addlPickFields'=> array('NAME'),
            'fields'        =>  array('ID', 'NAME', 'GROUPTYPE', 'DESCRIPTION'),
            )
        );
    }
}
