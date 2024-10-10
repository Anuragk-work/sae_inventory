<?

/**
 * Class DocumentParTotalsPicker
 */
class DocumentParTotalsPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
                'entity'        =>  'documentparams',
                'fields'        =>  array('NAME', 'DOCTYPE'),
                'pickfield'     =>  'NAME',
                'helpfile'      => 'Locations_Lister'
            )
        );
    }
}

