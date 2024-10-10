<?php

class SerialMaskLister extends NLister
{

    function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_the_Serial_Mask_List',
        );
        $helpfile = $helpIDs[Request::$r->_mod];

        parent::__construct(
            array (
            'entity'        =>  'serialmask',
            'fields'        =>  array('LENGTH','MASK'),
            'helpfile'        => $helpfile,
            'entitynostatus' => 1
            )
        );
    }
}

