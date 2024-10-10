<?

/**
 * Class ProductLinePicker
 */
class ProductLinePicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'productline',
            'fields'        =>  array('PRODUCTLINEID'),
            'pickfield'        =>  'PRODUCTLINEID',
            'helpfile'        => 'Locations_Lister', // NOT SURE ABOUT THIS ONE
            'renameable' => 1,
            )
        );
    }
}

