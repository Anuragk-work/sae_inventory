<?
import('InventoryReorderReporter');

/**
 * Class InvReorderReport
 */
class InvReorderReport extends InventoryReorderReporter
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
                'custvend' => 'vend',
                'reportby' => 'item',
                '2stage'         => true,
                ) 
            )
        );
        if(IsMCMESubscribed()) {
            $this->params['NOREPORTLOCCHECK'] = true;
        }
    }

}


