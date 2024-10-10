<?

/**
 * Class InvPriceListPicker
 */
class InvPriceListPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'invpricelist',
            'fields'        =>  array('NAME'),
            'pickfield'        =>  'NAME',
            'helpfile'        => 'Locations_Lister' // NOT SURE ABOUT THIS ONE
            )
        );
    }
}
