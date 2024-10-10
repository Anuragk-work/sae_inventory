<?
require_once 'Dictionary.cls';

/**
 * Class SerialPicker
 */
class SerialPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'serialpick',
            'pickfield'        =>  'PICKID',
            'helpfile'        => 'Locations_Lister' // NOT SURE ABOUT THIS ONE
            )
        );
    }

}
