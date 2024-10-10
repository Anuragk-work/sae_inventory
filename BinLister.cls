<?

class BinLister extends NLister
{

    public function __construct()
    {
        if (BinManager::areAdvanedBinsOn()) {
            $fieldList = ['BINID', 'BINDESC', 'ZONEID', 'AISLEID', 'ROWID', 'WAREHOUSEID'];
        } else {
            $fieldList = ['BINID', 'BINDESC'];
        }
        parent::__construct(
            array(
            'entity'           =>  'bin',
            'fields'           =>  $fieldList,
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL'),
            'helpfile'         => 'Viewing_and_Managing_the_Bin_List',
            'importtype'       =>  'bin',
            'enablemultidelete' => true,
            )
        );
        $this->xssEncode=true;
    }

}

