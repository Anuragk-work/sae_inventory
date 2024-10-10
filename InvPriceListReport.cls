<?
import('PriceListReporter');

/**
 * Class InvPriceListReport
 */
class InvPriceListReport extends PriceListReporter
{

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params,
                array( 
                'report' => 'pricelistrep', 
                'ops'    => array(
                                'inv/lists/invpricelistentry/view',
                                'inv/lists/item/view',
                                'inv/lists/productline/view',
                                ),
                '2stage' => true,
                ) 
            )
        );
    }

}
