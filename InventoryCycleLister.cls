<?

class InventoryCycleLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'inventorycycle',
            'helpfile'        =>     'Viewing_and_Managing_the_List_of_Inventory_Cycles' // Gokul 10-24-2001
            )
        );
    }
}

