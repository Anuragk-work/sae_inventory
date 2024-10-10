<?
import('InventoryCustVendReporter');
require_once 'Dictionary.cls';

/**
 * Class InvVendBacklogReport
 *
 */
class InvVendBacklogReport extends InventoryCustVendReporter
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
                'report'    => 'invbacklog',
                'custvend'     => 'vend',
                'reportby'     => 'vend'
                )
            ) 
        );
    }

}