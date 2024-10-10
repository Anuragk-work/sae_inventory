<?php

/**
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 *
 * @filesource ItemCrossRefFormEditor.cls
 * @author     Jagadish <jagadish.muthyala@sage.com>
 * @copyright  2000-2009 Intacct Corporation
 */

/**
 * Class ItemCrossRefFormEditor
 */
class ItemCrossRefFormEditor extends FormEditor
{
    /**
     * @param array $_params
     */
    function __construct($_params = array())
    {
        parent::__construct($_params);
    }

    /**
     * Removing unwanted values while duplicating record
     *
     * @param array $obj Object details
     *
     * @access protected
     * @return bool True or False based on the status of the call
     */
    protected function prepareObjectForCopyNew(&$obj)
    {
        parent::prepareObjectForCopyNew($obj);

        $unsetThese = ['ITEMALIASID', 'ITEMALIASDESC', 'UNIT', 'ALTERNATEITEMID',
            'WHENCREATED', 'WHENMODIFIED', 'CREATEDBY', 'MODIFIEDBY'];
        foreach ($unsetThese as $field) {
            unset($obj[$field]);
        }

        return true;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        parent::mediateDataAndMetadata($obj);

        $_mod = Request::$r->_mod;
        $view = $this->getView();

        $updateProperty = 'disabled';
        if ($this->state == 'shownew') {
            if ($obj['REFTYPE'] == '') {
                $obj['REFTYPE'] = $_mod == 'po' ? 'Vendor' : 'Customer';
            }
        } else {
            // disable the following fields
            // in edit mode the following fields are not allowed to edit
            $view->findAndSetProperty(['path' => 'REFTYPE'], ['disabled' => 'true']);
            $view->findAndSetProperty(['path' => 'VENDORID'], ['disabled' => 'true']);
            $view->findAndSetProperty(['path' => 'CUSTOMERID'], ['disabled' => 'true']);
            $view->findAndSetProperty(['path' => 'ITEMID'], ['disabled' => 'true']);

            // hide customer/vendor in PO/OE modules
            // in 'po' hide custmoer
            // in 'oe' hide vendor
            // in 'inv' show both, but disable based on reftype
            $updateProperty = $_mod != 'inv' ? 'hidden' : $updateProperty;
        }

        switch ($obj['REFTYPE']) {
            case 'Customer':
                $view->findAndSetProperty(['path' => 'VENDORID'], [$updateProperty => 'true']);
                $view->findAndSetProperty(['path' => 'CUSTOMERID'], ['required' => true]);
                $view->findAndSetProperty(['path' => 'ALTERNATEITEMID'], ['disabled' => 'true']);
                break;

            case 'Vendor':
                $view->findAndSetProperty(['path' => 'CUSTOMERID'], [$updateProperty => 'true']);
                $view->findAndSetProperty(['path' => 'VENDORID'], ['required' => true]);
                $view->findAndSetProperty(['path' => 'ALTERNATEITEMID'], ['disabled' => 'true']);
                break;

            case 'Substitute':
            case 'Upgrade':
            case 'Downgrade':
            case 'Complement':
                $view->findAndSetProperty(['path' => 'CUSTOMERID'], [$updateProperty => 'true']);
                $view->findAndSetProperty(['path' => 'VENDORID'], [$updateProperty => 'true']);
                $view->findAndSetProperty(['path' => 'ITEMALIASID'], ['disabled' => 'true']);
                $view->findAndSetProperty(['path' => 'ITEMALIASDESC'], ['disabled' => 'true']);

                $view->findAndSetProperty(['path' => 'ALTERNATEITEMID'], ['required' => true]);
                break;
        }

        return true;
    }

    /**
     * @param string $entity
     * @param string $objId
     * @param string $doctype
     * @param string[] $fields
     *
     * @return array|false
     */
    protected function getEntityData($entity, $objId, $doctype = '', $fields = null)
    {
        if (isset(Request::$r->_r) && Request::$r->_r != '') {
            $objId = Request::$r->_r;
        }
        return parent::getEntityData($entity, $objId, $doctype, $fields);
    }

    /**
     * @return array
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles[] = "../resources/js/itemcrossref.js";
        return $jsfiles;
    }
}

