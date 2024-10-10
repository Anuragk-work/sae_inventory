<?
class BinsizeLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'binsize',
            'fields'        =>  array('SIZEID', 'SIZEDESC'),
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL'),
            'helpfile'        => 'Viewing_and_Managing_the_Binsize_List',
            'title'             => 'IA.BIN_SIZES',
            'enablemultidelete' => true,
            )
        );
        $this->xssEncode=true;
    }

}


