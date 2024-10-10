<?
import('ApproverpickPicker');
class AdminApproverpickPicker extends ApproverpickPicker
{

    function __construct()
    {
        // TODO: Why are we skipping over constructors?
        NPicker::__construct(
            array(
            'entity'        =>  'adminapproverpick',
            'pickfield'    =>  'PICKID',
            'fields'        =>  array('PICKID'),
                                'disablesort'    =>  true,
                                'disablefilter' =>  true,
            )
        );
    }
}

