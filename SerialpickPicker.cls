<?
require_once 'Dictionary.cls';

/**
 * Class SerialPickPicker
 */
class SerialPickPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'serialpick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID'),
            'suppressPrivate' =>true,
            )
        );
    }

}
