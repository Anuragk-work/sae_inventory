<?

class LotcatPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'lotcategory',
            'fields'        =>  array('LOTID','LOTNAME'),
            'helpfile'        => 'Locations_Lister',
            'title'            => 'IA.LOT_CATEGORY',
            'pickfield'        => 'LOTID',
            )
        );
    }
}


