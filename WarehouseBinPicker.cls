<?php

/**
 * Class WarehouseBinPicker
 */
class WarehouseBinPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array (
                'entity'         =>     'warehousebin',
                'fields'         =>     array( 'BINID', 'BINDESC', 'WAREHOUSEID' ),
                'helpfile'       =>     'Locations_Lister',
                'title'          =>     'IA.BIN',
                'pickfield'      =>     'BINID',
                'entitynostatus' =>     1,
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
            $qrySpec['filters'][0][] = array('WAREHOUSEID', "IN ('".$whsekey."')", '' );
        }

    }


}


