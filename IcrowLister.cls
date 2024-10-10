<?

class IcrowLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'icrow',
            'fields'        =>  array('ROWKEY', 'ROWDESC'),
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL'),
            'title'            => 'IA.ROWS',
            'helpfile'        => 'Viewing_and_Managing_the_Row_List',
            'enablemultidelete' => true,
            )
        );
    }
}


