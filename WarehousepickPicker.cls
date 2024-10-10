<?

/**
 * Picker class for Warehouse
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class WarehousepickPicker
 */
class WarehousepickPicker extends NPicker
{
    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $nparams = array(
            'entity' => 'warehousepick',
            'pickfield' => 'PICKID',
            'fields' => array('PICKID'),
        );

        if ( count($params) ) {
            $nparams = INTACCTarray_merge($nparams, $params);
            $this->addGrpFields($nparams);
        }

        parent::__construct($nparams);
    }
    
    /**
     * add fields for group picker    
     * 
     * @param array $params picker param
     */
    protected function addGrpFields(&$params)
    {
        //override to add group fields
    }    

}
