<?php
/**
 * =============================================================================
 *
 * @filesource InvPriceListEditor.cls
 * @author
 * @copyright  2000,2009, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */


/**
 * class InvPriceListEditor extends FormEditor
 */
class InvPriceListEditor extends FormEditor
{
    /**
     * @param array $_params
     */
    function __construct($_params=array())
    {
        parent::__construct($_params);
    }
    
    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $mod = Request::$r->_mod;
        $view = $this->getView();
        $applicationArr = array(
            'so'    => 'Sales',
            'po'    => 'Purchasing'
        );
        
        $viewonlyfields = array('SALEPURCHASE');
        if (!empty($applicationArr[$mod])) {
            foreach ($viewonlyfields as $path) {
                $matches = array();
                $view->findComponents(array('path' => $path), EditorComponentFactory::TYPE_FIELD, $matches);
                if ($matches) {
                    $matches[0]->setProperty('value',  $applicationArr[$mod]);
                }
            }
        }

        return true;
    }

}
