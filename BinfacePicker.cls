<?

class BinfacePicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'binface',
            'fields'        =>  array('FACEID', 'FACEDESC'),
            'pickfield'        =>  'FACEID',
            )
        );
        $this->xssEncode=true;
    }
}

