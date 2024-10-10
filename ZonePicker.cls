<?

class ZonePicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'zone',
            'fields'        =>  array('ZONEID', 'ZONEDESC'),
            'pickfield'        =>  'ZONEID',
            )
        );
        $this->xssEncode=true;
    }
}

