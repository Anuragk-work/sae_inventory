<?

class LandedCostCategoryLister extends NLister
{
    /**
     * LandedCostCategoryLister constructor.
     */
    public function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_a_List_of_Landed_Cost_Categories',
        );
        $helpfile = $helpIDs[Request::$r->_mod];

        parent::__construct(
            array (
            'entity'        =>  'landedcostcategory',
            'fields'        =>  array('LCCATID','LCCATNAME', 'LANDEDCOSTDISTMETHOD'),
            'helpfile'        => $helpfile,
            'title'            => 'IA.LANDED_COST_CATEGORIES',
            'enablemultidelete' => false,
            'importtype'    => 'landedcostcategory',
            )
        );
    }
}


