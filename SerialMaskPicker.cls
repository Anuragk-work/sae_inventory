<?php

/**
 * Class SerialMaskPicker
 */
class SerialMaskPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'serialmask',
            'fields'        =>  array('MASK'),
            'helpfile'        => 'Locations_Lister',
            'title'            => "IA.SERIAL_MASK",
            'pickfield'        => 'MASK',
            'entitynostatus' => 1
            )
        );
    }
}


