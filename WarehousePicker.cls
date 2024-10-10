<?

/**
 * Class WarehousePicker
 */
class WarehousePicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'warehouse',
            'fields'        =>  array('LOCATIONID', 'NAME', 'STATUS'),
            'pickfield'        =>  'LOCATIONID',
            'helpfile'        => 'Locations_Lister'
            )
        );
        $this->xssEncode=true;
    }
}

