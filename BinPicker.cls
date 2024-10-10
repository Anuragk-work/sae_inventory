<?

class BinPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'bin',
            'fields'        =>  array('BINID', 'BINDESC'),
            'pickfield'        =>  'BINID',
            'helpfile'        => 'Locations_Lister', // NOT SURE ABOUT THIS ONE
            )
        );
        $this->xssEncode=true;
    }

}
