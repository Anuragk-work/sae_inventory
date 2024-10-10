<?

/**
 * Class PriceScheduleLister
 */
class PriceScheduleLister extends NLister
{
    /**
     * @param array $params
     */
    function __construct($params = [])
    {
        $mod = Request::$r->_mod;
        $helpIDs = array(
            'so' => 'Viewing_and_Managing_the_Price_Schedule_List_for_Vendors',
            'po' => 'Viewing_and_Managing_the_Price_Schedule_List_for_Vendors',
        );
        $params['entity'] = $params['entity'] ?? 'priceschedule';
        $params['fields'] = ['SCHEDULE', 'DESCRIPTION', 'DISCOUNT', 'PRICELISTID', 'STATUS'];
        $params['helpfile'] = $helpIDs[$mod];
        $params['enablemultidelete'] = true;

        parent::__construct($params);
    }

}