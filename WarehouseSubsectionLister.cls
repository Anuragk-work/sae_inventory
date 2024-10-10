<?php

/**
 * Class WarehouseSubsectionLister
 */
class WarehouseSubsectionLister extends NLister
{

    function __construct()
    {
        parent::__construct(
            array(
                'entity'   =>   'warehousesubsection',
                'title'    =>   'IA.WAREHOUSE_SUBSECTION_LISTING',
                'helpfile' =>   'Locations_Lister'
            )
        );
    }
}


