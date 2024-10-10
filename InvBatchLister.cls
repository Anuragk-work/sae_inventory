<?php

/**
 * Class InvBatchLister
 */
class InvBatchLister extends NLister
{
    function __construct()
    {
        parent::__construct(
            array (
            'entity'        => 'InvBatch',
            'fields'        =>  array('TITLE'),
            'helpfile'      => 'Locations_Lister',
            'title'         => 'IA.INVENTORY_BATCHES'
            )
        );
    }
}


