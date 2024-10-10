<?
class AislePicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'aisle',
            'fields'        =>  array('AISLEID', 'AISLEDESC'),
            'pickfield'        =>  'AISLEID',
            'helpfile'        => 'Locations_Lister', // NOT SURE ABOUT THIS ONE
            )
        );
        $this->xssEncode=true;
    }
}
