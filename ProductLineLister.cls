<?

/**
 * Class ProductLineLister
 */
class ProductLineLister extends NLister
{

    function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_the_Product_Lines_List',              
        'po' => 'Viewing_and_Managing_the_Product_Lines_List',                           
        'so' => 'Viewing_and_Managing_the_Product_Lines_List',                                   
        );
        $helpfile = $helpIDs[Request::$r->_mod];

        parent::__construct(
            array (
            'entity'        =>  'productline',
            'fields'        =>  array('PRODUCTLINEID','PARENTLINE'),
            'importtype'    => 'productline',
            'helpfile'        => $helpfile,
            'enablemultidelete' => true,
            )
        );
    }
}


