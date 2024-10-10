<?php

/**
 * Class InvDocumentParamsPicker
 */
class InvDocumentParamsPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
                'entity'        => 'invdocumentparams',
                'fields'        => array('DOCID'),
                'pickfield'     => 'DOCID',
                'helpfile'      => 'Locations_Lister',
                'title'         => 'IA.INVENTORY_TRANSACTION_DEFINITIONS'
            )
        );
    }

    /**
     * @param array $qrySpec
     */
    function AddFilters(&$qrySpec) 
    {
        $qrySpec['filters'][0][] = array('DOCID', " NOT IN ('Build Kits','Disassemble Kits') ", "");
    }


    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        $initial = parent::BuildQuerySpec();
        $initial['filters'][0][] = array('DOCID', " NOT IN ('Build Kits','Disassemble Kits') ", "");
        return $initial;
    }

}