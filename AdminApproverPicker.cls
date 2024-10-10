<?
class AdminApproverPicker extends Picker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'adminapproverpicker',
            'pickfield'    =>  'PICKID',
            'fields'        =>  array('PICKID'),
            )
        );
                             
    }
}

