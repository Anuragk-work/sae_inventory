<?
class AisleLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'aisle',
            'fields'        =>  array('AISLEID', 'AISLEDESC'),
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL'),
            'helpfile'        => 'Viewing_and_Managing_the_Aisle_List',
            'enablemultidelete' => true,
            )
        );
    }

}


