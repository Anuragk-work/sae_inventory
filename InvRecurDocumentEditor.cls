<?php
//
//================================================================================
//	FILE:			InvRecurDocumentEditor.CLS
//	AUTHOR:			bharris
//	DESCRIPTION:	Recurring document editor class. 
//					Manager of functionality for editing Inventory (iv) recurring transaction templates.
//
//	(C)2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//

import('RecurDocumentEditor');

/**
 * Class InvRecurDocumentEditor
 */
class InvRecurDocumentEditor extends RecurDocumentEditor
{
    /**
     * The id tag for this documents helpfile reference
     *
     * @var string $helpfile_ref
     * @access public
     */
    var $helpfile_ref;
    

    /**
     * @param array $_params
     */
    function __construct($_params)
    {
        $this->helpfile_ref = 'Adding_Editing_Viewing_Recurring_Templates_for_Inventory';                //??incomplete bharris
        parent::__construct($_params);
    }



    /**
     * @param array $_params
     */
    function Editor_Instantiate(&$_params) 
    {
        Request::$r->_mod = 'inv';
        $_params['ENTRIES_numofrows_top']         = '3';
        $_params['ENTRIES_numofrows_bottom']     = '3';

        parent::Editor_Instantiate($_params);

        // do our own customizations...
        $_params['DOCPARID']     = Request::$r->_dt;
        $_params['DOCID']         = $_params['DOCPARID'];

        $num_fields = count($_params['allfields']);


        for ($num=0; $num < $num_fields; $num++) {
            if ($_params['allfields'][$num]['path'] == 'AMOUNT') {
                if (isset($_params['allfields'][$num]['value'])) {
                    //Removing any formatting if present
                    $_params['allfields'][$num]['value'] = str_replace(',', '', $_params['allfields'][$num]['value']);
                }
            }

            if ($_params['allfields'][$num]['path'] == 'PONUMBER') {
                $ponum = $_params['allfields'][$num]['value'];    //for showing on second tab
            }

            if ($_params['allfields'][$num]['path'] == 'VIRTUAL.PONUMBER') {
                /** @noinspection PhpUndefinedVariableInspection */
                $_params['allfields'][$num]['value'] = $ponum;
            }
        }
    }

    function PrintOnLoad() 
    {
        parent::PrintOnLoad();
        echo "DisableCostFields();";
    }
    

    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessCopyNewAction(&$_params) 
    {
        $obj =& Request::$r->GetCurrentObject();
        $obj['SOURCEDOCUMENT']     = $obj['DOCPARID'].'--'.$obj['DOCNO'];
        $obj['DOCPARID']         = Request::$r->_dt;
        $obj['DOCID']             = $obj['DOCPARID'];
        
        //remove history details
        unset($obj['HISTORY']);
        
        //cleanup code for invalid ENTRIES items...
        $myEntries = array();
        foreach( $obj['ENTRIES'] as $line) {
            if ((!isset($line)) || (!isset($line['ITEMID']))) {
                continue;
            }
            else {
                $myEntries[] = $line;
            }
        }
        
        $obj['ENTRIES']         = $myEntries;
        $_params['helpfile']     = $this->helpfile_ref;
        return parent::ProcessCopyNewAction($_params);
    }    



    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessCreateAction(&$_params) 
    {
        $obj =& Request::$r->GetCurrentObject();
        $obj['DOCPARID']     = Request::$r->_dt;
        $obj['DOCID']         = $obj['DOCPARID'];

        //cleanup code for invalid ENTRIES items...
        $myEntries = array();
        foreach( $obj['ENTRIES'] as $line) {
            if ((!isset($line)) || (!isset($line['ITEMID']))) {
                continue;
            }
            else {
                $myEntries[] = $line;
            }
        }

        $obj['ENTRIES'] =$myEntries;
        $_params['helpfile'] = $this->helpfile_ref;

        return parent::ProcessCreateAction($_params);
    }



    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessEditAction(&$_params) 
    {
        $ok = parent::ProcessEditAction($_params);
        $_params['helpfile'] = $this->helpfile_ref;
        return $ok;
    }

        

    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessEditNewAction(&$_params) 
    {
        if ($this->atlas && !GetContextLocation()) {
            global $gErr;
            $gErr->addIAError('INV-0150', __FILE__ . ":" . __LINE__,
                "Cannot create Inventory documents at root for multiple base currency companies.",
                []
            );
            $this->state = $this->kErrorState;
            $ok = false;
        } else {
            $ok = parent::ProcessEditNewAction($_params);
        }

        $_params['helpfile'] = $this->helpfile_ref;

        // When a new document is being created because the user clicked on
        // the 'Add' button in the RTT Lister we need to make the document
        // type selectable for them.
        $doctype = Request::$r->single;
        if (!isset($doctype) || ($doctype=='')) {
            $fields = array();
            $this->MatchTemplates($_params, array('path' => 'DOCID'), $fields);
            foreach ( $fields as $i => $x) {
                $fields[$i]['noedit']             = false;
                $fields[$i]['readonly']         = false;
                $fields[$i]['required']         = true;
                $fields[$i]['hidden']             = false;
                $fields[$i]['autofill']         = true;
                $fields[$i]['afterfunction']     = 'AutoFill';
                $fields[$i]['type']             = array (
                'type'                 => 'enum',
                'ptype'             => 'enum',
                'validvaluesfunc'    =>    "return GetDocumentParams('inv', '', true);",
                'format'             => '/^[\w\s_\-]{0,30}$/'
                );
                $fields[$i]['onchange'] = 'AutoPopulatedocparID(this.value);';
            }
        }

        return $ok;
    }

    

    /**
     * Method to allow final modifications prior to
     * saving object data.
     *
     * @param array $_params
     */
    function ProcessSaveAction(&$_params) 
    {
        $_params['helpfile'] = $this->helpfile_ref;
        parent::ProcessSaveAction($_params);
    }



    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessViewAction(&$_params) 
    {
        $ok = parent::ProcessViewAction($_params);
        $_params['helpfile'] = $this->helpfile_ref;

        return $ok;
    }


    /**
     * @param bool $addYuiCss
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);

        ?>
     <script type="text/javascript" language="javascript">
     <!--
     //to fillup dummy customer/term values on second tab
     function PopulateLayer() {
      layer1frm = GetForm('Layer1', 'Layer1_form');
      layer2frm = GetForm('Layer2', 'Layer2_form');
      fromfrm = GetForm('Layer0','Layer0_form');
      layer1frm.elements['_obj__VIRTUAL__DOCPARID'].value = fromfrm.elements['_obj__DOCPARID'].value;
      layer2frm.elements['_obj__VIRTUAL__DOCPARID'].value = fromfrm.elements['_obj__DOCPARID'].value;
      layer1frm.elements['_obj__VIRTUAL__PONUMBER'].value = fromfrm.elements['_obj__PONUMBER'].value;
      layer2frm.elements['_obj__VIRTUAL__PONUMBER'].value = fromfrm.elements['_obj__PONUMBER'].value;
     }

     function Disable() {
      document.forms['Layer0_form'].elements['_obj__DOCPARID'].disabled 			= true;
      document.forms['Layer0_form'].elements['_obj__DOCPARID'].readonly 			= true;
      document.forms['Layer1_form'].elements['_obj__VIRTUAL__DOCPARID'].disabled 	= true;
      document.forms['Layer1_form'].elements['_obj__VIRTUAL__DOCPARID'].readonly 	= true;
      document.forms['Layer2_form'].elements['_obj__VIRTUAL__DOCPARID'].disabled 	= true;
      document.forms['Layer2_form'].elements['_obj__VIRTUAL__DOCPARID'].readonly 	= true;
      document.forms['Layer1_form'].elements['_obj__VIRTUAL__PONUMBER'].disabled 	= true;
      document.forms['Layer1_form'].elements['_obj__VIRTUAL__PONUMBER'].readonly 	= true;
      document.forms['Layer2_form'].elements['_obj__VIRTUAL__PONUMBER'].disabled 	= true;
      document.forms['Layer2_form'].elements['_obj__VIRTUAL__PONUMBER'].readonly 	= true;
      PopulateLayer(); //insure field values are copied over.
     }
     // -->
     </script>
        <?
    }

}    // finish class InvRecurDocumentEditor
