<?
require_once 'Dictionary.cls';

class LotPickPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'lotpick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID'),
            'suppressPrivate' =>true,
            )
        );
    }
}

