<?
require_once 'Dictionary.cls';

/**
 * Class StkitpickPicker
 */
class StkitpickPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'stkitpick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID', 'PRODUCTLINEID', 'STATUS'),
            'sortcolumn'    => 'ITEMID',
            )
        );
    }
}
