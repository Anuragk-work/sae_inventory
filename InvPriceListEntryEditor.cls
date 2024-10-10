<?
/**
 * =============================================================================
 *
 * @filesource InvPriceListEditor.cls
 * @author     Sandeep Pasunuri <spasunuri@intacct.com>
 * @copyright  2000,2009, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

import('FormEditor');
/**
 *  class InvPriceListEntryEditor extends FormEditor {
 */
class InvPriceListEntryEditor extends FormEditor
{
    /**
     * @param array $_params
     */
    function __construct($_params=array())
    {
        parent::__construct($_params);
    }
    
    /**
     * Function to Include JS Files
     *
     * @return array
     */
    protected function getJavaScriptFileNames()
    {
            return array('../resources/js/invpricelist.js');
    }
    
    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $plid = &Request::$r->_plid;
        $obj['PRICELISTID'] = (empty($obj['PRICELISTID'])) ? $plid : $obj['PRICELISTID'];
        
        $mod = &Request::$r->_mod;

        $view = $this->getView();
        //eppp_p($obj);
        $fields = array(
            'RECORDNO'=> array('hidden'=>'true')
        );
    
        // show the currency field if creating, editing & deleting foreign currency documents 
        // is allowed in OE Preference.
        $ismcpEnabled = IsMCPEnabled($mod);
        
        if($ismcpEnabled) {
            // get the default Base Currency
            $basecurr = GetBaseCurrency();
            $fields['CURRENCY'] = array(
                'value' =>  (empty($obj['CURRENCY'])) ? $basecurr : $obj['CURRENCY'],
                'hidden'=>  false,
            );
        }
        foreach ($fields as $path=>$properties) {
            $matches = array();
            $view->findComponents(array('path' => $path), EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches) {
                foreach ( $properties as $prop => $value ) {
                    $matches[0]->setProperty($prop,  $value);
                }
                if (isset($properties['value'])) {
                    $obj[$path] = $properties['value'];
                }
            }
        }

        return true;
    }
}


