<?

/**
 * Picker class for Warehouse
 *
 * @author    Viveksuriyan Subramani <vsubramani@intacct.com>
 * @copyright 2018 Sage Intacct Inc., All Rights Reserved
 *
 * This document contains trade secret data that belongs to Intacct Corporation and is protected by the copyright laws.
 * Information herein may not be used, copied or disclosed in whole or in part without prior written consent from
 * Intacct Corporation.
 *
 */

/**
 * Class WarehouselocationpickPicker
 */
class WarehouselocationpickPicker extends NPicker
{
    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $nparams = array(
            'entity' => 'warehouselocationpick',
            'pickfield' => 'PICKID',
            'fields' => array('PICKID'),
        );

        if (count($params)) {
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
