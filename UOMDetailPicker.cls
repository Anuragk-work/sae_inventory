<?

class UOMDetailPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'UOMDETAIL',
            'fields'        =>  array('UNIT'),
            'helpfile'        => 'Locations_Lister',
            'title'            => 'IA.UNIT_OF_MEASURE_LISTER',
            'pickfield'        => 'UNIT',
            'entitynostatus' => 1
            )
        );
    }
}


