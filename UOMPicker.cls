<?

class UOMPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'UOM',
            'fields'        =>  array('NAME'),
            'helpfile'        => 'Locations_Lister',
            'title'            => 'IA.UNIT_OF_MEASURE_LISTER',
            'pickfield'        => 'NAME',
            'entitynostatus' => 1
            )
        );
    }
}

