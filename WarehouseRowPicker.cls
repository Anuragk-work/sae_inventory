<?php

/**
 * Class WarehouseRowPicker
 */
class WarehouseRowPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array (
                'entity'         => 'warehouserow',
                'fields'         => array( 'ROWKEY', 'ROWDESC', 'LOCATIONID' ),
                'helpfile'       => 'Locations_Lister',
                'title'          => "IA.ROW",
                'pickfield'      => 'ROWKEY',
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


