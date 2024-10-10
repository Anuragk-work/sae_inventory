<?
require_once 'Dictionary.cls';

class AislepickPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'aislepick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID'),
            )
        );
    }
}

