<?php

/**
 * Lister class for Warehouse Group
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class WarehouseGroupLister
 */
class WarehouseGroupLister extends DimensionGroupLister
{

    public function __construct()
    {

        $params = array(
            'entity' => 'warehousegroup',
            'fields' => array('ID', 'NAME', 'GROUPTYPE', 'DIMGRPCOMP', 'DESCRIPTION'),
            'helpfile' => 'Viewing_and_Managing_Warehouse_Groups',
        );
        $this->addLabelMapping('MEMBERS', 'IA.MEMBERS', true);
        parent::__construct($params);
    }

}


