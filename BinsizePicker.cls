<?

class BinsizePicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'binsize',
            'fields'        =>  array('SIZEID', 'SIZEDESC'),
            'pickfield'        =>  'SIZEID',
            )
        );
        $this->xssEncode=true;
    }

}

