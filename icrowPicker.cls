<?

class icrowPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'icrow',
            'fields'        =>  array('ROWKEY', 'ROWDESC'),
            'pickfield'        =>  'ROWKEY',
            'helpfile'        => 'Locations_Lister', // NOT SURE ABOUT THIS ONE
            )
        );
        $this->xssEncode=true;
    }
}

