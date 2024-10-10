<?
import('InventoryCustVendShipHistReporter');

/**
 * Class InvVendShipHistReport
 */
class InvVendShipHistReport extends InventoryCustVendShipHistReporter
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
                'ops' => array(
                                    'po/lists/vendor/view',
                                    'po/lists/podocument/view',
                                    'po/lists/item/view',
                                    ),
                'reportslide' => true,
                'custvend' => 'vend',
                'reportby' => 'item',
                'qtyheader' => 'Qty Received'
                )
            ) 
        );
    }

}