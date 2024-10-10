<?
class ZoneLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'zone',
            'fields'        =>  array('ZONEID', 'ZONEDESC'),
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL'),
            'helpfile'        => 'Viewing_and_Managing_the_Zone_List',
            'enablemultidelete' => true,
            )
        );
    }

}


