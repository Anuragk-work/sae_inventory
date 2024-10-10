<?

class ItemCrossRefLister extends NLister
{
    public function __construct()
    {

        $fieldList = ['REFTYPE', 'ITEMID', 'ALTERNATEITEMID', 'VENDORID', 'CUSTOMERID', 'ITEMALIASID', 'ITEMALIASDESC', 'UNIT'];

        parent::__construct(
            [
                'entity'           =>  'itemcrossref',
                'fields'           =>  $fieldList,
                // the list of fields which need special encoding
                'nonencodedfields' => array('RECORD_URL'),
                'helpfile'         => 'Viewing_and_Managing_the_ItemCrossRef_List',
                'importtype'       =>  'itemcrossref',
                'enablemultidelete' => true,
            ]
        );
    }

}

