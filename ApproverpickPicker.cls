<?
class ApproverpickPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'approverpick',
            'pickfield'    =>  'PICKID',
            'fields'        =>  array('PICKID'),
                                'disablesort'    =>  true,
                                'disablefilter' =>  true,
            )
        );
    }

}

