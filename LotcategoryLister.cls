<?

class LotcategoryLister extends NLister
{

    public function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_a_List_of_Lot_Categories',
        );
        $helpfile = $helpIDs[Request::$r->_mod];

        parent::__construct(
            array (
            'entity'        =>  'lotcategory',
            'fields'        =>  array('LOTID','LOTNAME'),
            'helpfile'        => $helpfile,
            'title'            => 'IA.LOT_CATEGORIES',
            )
        );
    }
}


