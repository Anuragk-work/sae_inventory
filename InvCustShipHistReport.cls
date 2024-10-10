<?
import('InventoryCustVendShipHistReporter');

/**
 * Class InvCustShipHistReport
 */
class InvCustShipHistReport extends InventoryCustVendShipHistReporter
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params,
                array(    
                'ops' => array(
                                    'so/lists/customer/view',
                                    'so/lists/sodocument/view',
                                    'so/lists/item/view',
                                    ),
                'reportslide' => true,
                'custvend' => 'cust',
                'reportby' => 'item',
                'qtyheader' => 'Ship Qty'
                )
            ) 
        );
    }

}

