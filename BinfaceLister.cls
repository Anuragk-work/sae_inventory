<?
class BinfaceLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'binface',
            'fields'        =>  array('FACEID', 'FACEDESC'),
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL'),
            'helpfile'        => 'Viewing_and_Managing_the_Binface_List',
            'title'             => 'IA.BIN_FACES',
            'enablemultidelete' => true,
            )
        );
        $this->xssEncode=true;
    }

}


