<?
require_once 'Dictionary.cls';

class LotPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'lotpick',
            'pickfield'        =>  'PICKID',
            'helpfile'        => 'Locations_Lister' // NOT SURE ABOUT THIS ONE
            )
        );
    }
}

