<?
/**
 * class TaxGroupLister extends Lister
 */
class InvTotalLister extends NLister
{

    public function __construct()
    {
        parent::__construct(
            array (
                'entity'    =>  'invtotal',
                'title'     =>  'IA.INVENTORY_TOTALS',
                'fields'    =>  array( 'NAME', 'UPDATETYPE', 'STATUS' ),
                'helpfile'  => 'Viewing_and_Managing_the_List_of_Inventory_Totals'
            )
        );
    }
}

