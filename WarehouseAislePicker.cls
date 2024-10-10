<?php

/**
 * Class WarehouseAislePicker
 */
class WarehouseAislePicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
                'entity'         => 'warehouseaisle',
                'fields'         => array( 'AISLEID', 'AISLEDESC', 'LOCATIONID' ),
                'helpfile'       => 'Locations_Lister',
                'title'          => 'IA.AISLE',
                'pickfield'      => 'AISLEID',
                'entitynostatus' => 1,
            )
        );
    }

    /**
     * @return array
     */
    function BuildQuerySpecAll() 
    {
        $ret = parent::BuildQuerySpecAll();
        $this->AddFilters($ret);
        return $ret;
    }

    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        $ret = parent::BuildQuerySpec();
        $this->AddFilters($ret);
        return $ret;
    }


    /**
     * @param array $qrySpec
     */
    function AddFilters(&$qrySpec) 
    {
        $whsekey = Request::$r->_whsekey;
        if($whsekey) {
            // only Inventory items are allowed
            $qrySpec['filters'][0][] = array('LOCATIONID', "IN ('".$whsekey."')", '' );        
        }

    }


}


