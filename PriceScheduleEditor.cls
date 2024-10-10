<?php
/**
 * =============================================================================
 *
 * FILE:        PriceScheduleEditor.cls
 * AUTHOR:      Sri Vidya
 * DESCRIPTION: Editor class for PriceSchedule object
 *
 * (C)2000,2009 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

/**
 * Editor class for PriceSchedule object
 */
class PriceScheduleEditor extends FormEditor
{
    /**
     * @param array $_params Initial params
     */
    public function __construct($_params = array())
    {         
        parent::__construct($_params); 
    }
    /**
    * mediateDataAndMetadata
    *
    * @param array &$obj Initial params
    *
    * @return bool
    */
    protected function mediateDataAndMetadata(&$obj)
    {
        parent::mediateDataAndMetadata($obj);

        $mod = Request::$r->_mod;

        $view = $this->getView();
        $fields = array();
        $view->findComponents(array('path' => 'SCHEDTYPE'), EditorComponentFactory::TYPE_FIELD, $fields);
        if ($fields) {
            foreach ( $fields as $field) {
                $val = ($mod == 'so' || $mod == 'ar' || $mod=='co') ? 'Sales' : 'Purchasing' ;
                $field->setProperty('value', $val);
                $field->setProperty('hidden', true);
            }
            /** @noinspection PhpUndefinedVariableInspection */
            $obj['SCHEDTYPE'] = $val;
        }

        return true;
    }

    /**
     * SetHelpID
     *
     * @param array &$_params Initial params
     *
     * @return true
     */
    protected function SetHelpID(&$_params)
    {
        $_params['view']['helpfile'] = 'Adding_Editing_and_Viewing_Vendor_Price_Schedule_Information';

        return true;
    }
}

