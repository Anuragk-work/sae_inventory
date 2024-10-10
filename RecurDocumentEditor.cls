<?php
//
//================================================================================
//	FILE:			RecurDocumentEditor.CLS
//	AUTHOR:			bharris
//	DESCRIPTION:	Recurring document editor base class.
//					Manager of functionality for editing recurring transaction templates.
//
//	(C)2008, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//

require_once 'util.inc';
require_once 'backend_module.inc';
require_once 'backend_dates.inc';
require_once 'backend_megl.inc';

import('ScheduledDocumentEditor');
import('Editor');
/**
 * Editor base class for managing common functionality of all IV/PO/SO recurring
 * document objects.
 */
class RecurDocumentEditor extends ScheduledDocumentEditor
{
    /**
     * State flag used in copy-new mode
     * when cloning an existing doc to rtt...
     *
     * @var bool $isCopyNew
     */
    var $isCopyNew;


    /**
     * @param array $_params
     */
    function __construct($_params)
    {
        $this->isCopyNew = false;
        parent::__construct($_params);

        $mod = Request::$r->_mod;
        $this->_ismcpEnabled = IsMCPEnabled($mod);
        $this->atlas = IsMCMESubscribed();
    }




    /*
    function CollectAutoFillData($docpar) {
    StartTimer("AUTOFILL");
    global $gManagerFactory,$gRequest;

    $docMgr		= $gManagerFactory->GetManager('recurdocument');

    $inout		= $docpar['IN_OUT'];
    $items 		= array();

    StartTimer("ITEMS");

    $itemidArray = array();
    $obj 		= &$gRequest->GetCurrentObject();
    if ($obj['ENTRIES']) {
    foreach ($obj['ENTRIES'] as $entry) {
				$entry['ITEMID'] = explode('--',$entry['ITEMID']);
				$entry['ITEMID'] =$entry['ITEMID'][0] ;
				$itemidArray[] = $entry['ITEMID'];
    }
    }

    $itemIDList = "'". join("', '",$itemidArray) ."'";

    $mod	= Request::$r->_mod;
    $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');
    $precFld = $precisionFields[$mod];

    if ($this->state ==1){
    $itemstatus = " and icitem.status = 'T'";
    }

    $stmt = array();
    $stmt[0] = "select icitem.itemid, chr('39')|| replace(itemid,chr('39'),'\'||chr('39'))||chr('39')||','||chr('39')|| replace(name,chr('39'),'\'||chr('39'))||chr('39')||','||chr('39')|| taxable||chr('39')||','||chr('39')|| replace(productlinekey,chr('39'),'\'||chr('39')) || chr('39')||',['||chr('39')|| replace(stduom.unit,chr('39'),'\'||chr('39')) || chr('39')||',1],['||chr('39') || replace(purchaseuom.unit,chr('39'),'\'||chr('39')) || chr('39') || ',' || punit_factor || '],[' || chr('39')|| replace(salesuom.unit,chr('39'),'\'||chr('39')) || chr('39')||',' || sunit_factor || ']' || ',' || chr('39') || ".$precFld." || chr('39') || ',' || chr('39')|| chr('39') || ',' || chr('39')|| chr('39') || ',' || chr('39')|| icitem.itemtype  || chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| chr('39')|| ',' || chr('39')|| icitem.hasstartenddates || chr('39')|| ',' || chr('39')|| icitem.termperiod || chr('39')|| ',' || chr('39')|| icitem.totalperiods || chr('39')|| ',' || chr('39')|| icitem.computeforshortterm || chr('39') as JSROW from icitem, icuom stduom, icuom purchaseuom, icuom salesuom where  icitem.cny# = :1 and stduom.cny#(+)=icitem.cny# and purchaseuom.cny#(+)=icitem.cny# and salesuom.cny#(+)=icitem.cny# and icitem.uomgrpkey = stduom.grpkey and stduom.module = 'A' and icitem.uomgrpkey = purchaseuom.grpkey and purchaseuom.module = 'P' and icitem.uomgrpkey = salesuom.grpkey and salesuom.module = 'P' ".$itemstatus;
    $stmt[1] = GetMyCompany();
    $stmt = PrepINClauseStmt($stmt, $itemidArray, " and icitem.itemid ");
    //$stmt[0] .= ' order by itemid ';
    $res = QueryResult($stmt);


    $jsitemCnt = count($res);

    $tempJSItems = array();
    //Iterating for getting item record details for the repeated items in the line entries
    for ($i=0;$i<$jsitemCnt;$i++){
    $tempJSItems[$res[$i]['ITEMID']] = '['.$res[$i]['JSROW'].']';
    }

    // The items needs to be in the same order as in the line nos, for the autofill logic to work
    $itemCnt = count($itemidArray);
    for ($i=0;$i<$itemCnt;$i++){
    $items['ITEMS'][] = $tempJSItems[$itemidArray[$i]];
    }

    $items_time 	= StopTimer("ITEMS");
    if ($docpar['WAREHOUSESELMETHOD']=='Sort by Name') {
    $qry = "SELECT location_no, name FROM icwarehouse WHERE status = 'T' and cny# =:1 order by name,location_no";
		    $warehouses 	= QueryResult(array($qry,GetMyCompany()));
    } else {
    $qry = "SELECT location_no, name FROM icwarehouse WHERE status = 'T' and cny# =:1 order by location_no";
		    $warehouses 	= QueryResult(array($qry,GetMyCompany()));
    }
    $items['WHSES'] = $warehouses;

    if ($inout == 'Decrease') {
    StartTimer("TOTAL");
    $items['QTYS'] = array();
    $availability 	= $docMgr->DoQuery('QRY_DOCUMENT_GET_TOTALS',array());
    foreach ($availability as $qtyitem) {
				$items['QTYS'][] = '['.$qtyitem[JSROW].']';
    }
    $tot_time = StopTimer("TOTAL");
    }
    else{
    $items['QTYS'] = -1;
    }

    $af_time = StopTimer("AUTOFILL");
    #epp("TIMING: AUTOFILL->$af_time,ITEMS->$items_time,TOTAL->$tot_time");
    return($items);
    }

    */

    /**
     * @param string    $_msg
     * @param string[]  $obj
     */
    function SetMessageWithObject($_msg, $obj)
    {
        if ($obj['DOCID']) {

            $this->message = "Your Recurring Template '".$obj['DOCID']."' has been Created";
            if (isl_strstr($this->done, "lister")) {
                $outputstr = '';
                $parms = explode('&', $this->done);
                foreach ($parms as $parm) {

                    if (isl_substr($parm, 0, 4) == '_msg') {
                        $parm = '_msg='.urlencode($this->message);
                        $msgset = true;
                    }
                    if (isl_substr($parm, 0, 13) == '.queryfromend') {
                        $parm = '.queryfromend=1';
                        $qryset = true;
                    }
                    if (isl_substr($parm, 0, 3) == '.dt') {
                        $parm = '.dt='.urlencode($obj['DOCPARID']);
                        $dtset = true;
                    }
                    $outputstr .= $parm.'&';
                }

                /** @noinspection PhpUndefinedVariableInspection */
                if ( $msgset != true) {
                    $outputstr .= '_msg='.urlencode($this->message).'&';
                }
                /** @noinspection PhpUndefinedVariableInspection */
                if ( $qryset != true) {
                    $outputstr .= '.queryfromend=1&';
                }
                /** @noinspection PhpUndefinedVariableInspection */
                if ( $dtset != true) {
                    $outputstr .= '.dt='.urlencode($obj['DOCPARID']).'&';
                }

                $this->done = $outputstr;
            }
        }else{
            parent::SetMessage($_msg);
        }
    }


    /**
     * @param array $ownerobject
     *
     * @return string
     */

    function GetCustomOwnerObject($ownerobject)
    {
        $mod = Request::$r->_mod;


        $recurCustomOwnerObject = array(
        $mod.'recurdocument' => $mod.'document',
        'recurdocumententry' => $mod.'documententry',
        );

        foreach($recurCustomOwnerObject as $key => $value){
            if($ownerobject == $key) {
                $ownerobject = $value;
                break;
            }
        }

        return $ownerobject;
    }

    /**
     * This is a hack to get back the original entity **recurdocument as entity is set to **document to retrieve custom fields
     * Check ExistCustomFields function in RecurDocumentManager.cls
     *
     * @param array  $mfield
     * @param string $ownedObjectEntity
     *
     * @return bool true or false from parents method
     */
    function IsOwnedObject($mfield, &$ownedObjectEntity)
    {
        $mod = Request::$r->_mod;
        $this->_params['entity'] = $mod.'recurdocument';
        return parent::IsOwnedObject($mfield, $ownedObjectEntity);
    }



    /**
     * @param array $_params
     *
     * @return array $_params
     */
    function Editor_Expand($_params)
    {
        global $gCurrencyFormat, $gManagerFactory;

        //$docparMgr = $gManagerFactory->GetManager('documentparams');
        //$doctype = Request::$r->_dt;
        $mod   = Request::$r->_mod;
        $cat   = Request::$r->_cat;
        $r     = Request::$r->_r;
        $val   = Request::$r->_val;

        //if there is no _r value in the url, try the _val value.
        if(!$r) {
            $r = $val;
        }

        $entityMgr = $gManagerFactory->getManager($_params['entity']);
        if (!$this->dt) {
            if($r) {
                $rec = $entityMgr->DoQuery('QRY_RECURDOCUMENT_GET_DOCPAR_RECORDNO', array($r));
                $this->dt = $rec[0]['DOCID'];
            }else{
                //the flag _doctypeeditable is used on refresh to decide whether the field is editable
                $this->_doctypeeditable = true;
                $docs = GetDocumentParams($mod, $cat);
                $this->dt = $docs[0]; //arbitrally sets the first entry as the default
            }
        }
        if (isset($this->dt) && $this->dt != '') {
            Request::$r->_dt = $this->dt;
        }

        if (isset($this->dt) && $this->dt != '') {
            $docparmrec = $this->GetBaseDocPar();
        }

        $this->MatchTemplates($_params, array('path' => 'OVERRIDETAX'), $foundFld);
        foreach ( $foundFld as $i => $x ) {
            /** @noinspection PhpUndefinedVariableInspection */
            if ( $docparmrec['ENABLEOVERRIDETAX'] == 'true' ) {
                $foundFld[$i]['hidden'] = false;
                $foundFld[$i]['disabled'] = false;
            } else {
                $foundFld[$i]['hidden'] = true;
                $foundFld[$i]['disabled'] = true;
            }
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $this->_deptOverride     = ( $docparmrec['DEPTOVERRIDE'] == 'true');
        $this->_locOverride     = ($docparmrec['LOCOVERRIDE'] == 'true');

        //call the change contact labels method here
        $this->ChangeContactLabels($docparmrec, $_params);

        if (isset($docparmrec) && $docparmrec['SHOW_TOTALS'] == 'true') {
            /**** This guy should be ideally done in an XML w'll need to figure out some way ****/
            $scolumns = array();
            $absval = array(
            'path'=>'ABSVAL',
            'fullname'=>_('Value'),
            'type'=> array(
            'ptype' => 'currency',
            'multilinecolsepr'=>30,
            ),
            'size' => 5,
            'subtotal'=>1,
            );
            $total = array(
            'path'=>'TOTAL',
            'fullname'=>_('Total'),
            'size' => 10,
            'type'=> array(
            'ptype'=> 'currency',
            'type' => $gCurrencyFormat,
            'multilinecolsepr'=>50,
            'blankwhenzero' => true
            ),
            'readonly'=>1,
            'subtotal'=>1,
            );
            $trxabsval = array(
            'path'=>'TRX_ABSVAL',
            'fullname'=>_('Value'),
            'type'=> array(
                        'ptype' => 'currency',
                        'type' => $gCurrencyFormat,
                        'multilinecolsepr'=>30,
            ),
            //'onchange' => 'UpdateBase_absval(this);',
            'size' => 5,
            'subtotal'=>1
            );
            $trxtotal = array(
            'path'=>'TRX_TOTAL',
            'fullname'=>_('Total'),
            'size' => 10,
            'type'=> array(
                        'ptype'=> 'currency',
                        'type' => $gCurrencyFormat,
                        'multilinecolsepr'=>50,
                        'blankwhenzero' => true
            ),
            'readonly'=>1,
            'subtotal'=>1
            );
            if($docparmrec['DISPLAY_BASECURRENCY'] == 'true') {
                $trxabsval['fullname'] = _('Transaction value');
                $trxtotal['fullname'] = _('Transaction total');
            }

            $scolumns[] = array(
            'path'=>'DESCRIPTION',
            'fullname'=>_('Description'),
            'size' => 10,
            'readonly' => 1,
            'subtotal'=>1
            );
            $scolumns[] = array(
            'path'=>'PERCENTVAL',
            'fullname'=>_('Percent'),
            'type'=> array(
            'multilinecolsepr'=>30,
            ),
            'size' => 5,
            'subtotal'=>1
            );

            if($this->_ismcpEnabled) {
                $absval['hidden']=1;
                $total['hidden'] =1;

                $scolumns[] = $trxabsval;
                if($docparmrec['DISPLAY_BASECURRENCY'] == 'true') {
                    $absval['fullname'] = _('Base value');
                    $absval['hidden']=0;
                    $scolumns[] = $absval;
                }
                $scolumns[] = $trxtotal;
                if($docparmrec['DISPLAY_BASECURRENCY'] == 'true') {
                    $total['fullname'] = _('Base total');
                    $total['hidden'] =0;
                    $scolumns[] = $total;
                }
            }else{
                $scolumns[]=$absval;
                $scolumns[]=$total;
            }

            if ($this->_deptOverride) {
                $onchange = null;
                if ( !util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('department') ) {
                    $onchange = 'pt_editor_defaultRelated(this, null);';
                }

                $scolumns[] = array(
                'path'=>'DEPARTMENT',
                'subtotal'=>1,
                'renameable' => 1,
                    'onchange' => $onchange
                );
            }

            if ($this->_locOverride) {
                $showLoc = true;
                if (IsMultiEntityCompany() && !GetContextLocation()) {
                    $showLoc = false;
                }
                if($showLoc) {
                    $onchange = null;
                    if ( !util_isPlatformDisabled() && Pt_StandardUtil::autoFillRelated('location') ) {
                        $onchange = 'pt_editor_defaultRelated(this, null);';
                    }

                       $scolumns[] = array(
                    'path'=>'LOCATION',
                    'subtotal'=>1,
                    'renameable' => 1,
                        'onchange' => $onchange
                       );
                }
            }

            if($this->_ismcpEnabled && $docparmrec['DISPLAY_BASECURRENCY'] != 'true') {
                $scolumns[]=$absval;
                $scolumns[]=$total;
            }

            // ---- Subtotal Dimensions starts
            //Fix me for the module based dimension ent's, mgrs
            $lineitementity = $mod.'recursubtotals';

            // merge in dimensions
            $sdimcolumns = $this->getDimensionFieldsInfo($lineitementity);
            if (count($sdimcolumns) > 0 ) {
                $primaryDim = $this->getEntityMgr()->getPrimaryDimensions();

                foreach ($sdimcolumns as $key => $sdimcolumn) {

                    if ( isset($primaryDim[$sdimcolumn['path']]) ) {
                        // Hide those dimensions that are not part of the module.
                        $sdimcolumns[$key]['hidden'] = true;
                    } else if(IsMultiEntityCompany() && !GetContextLocation()) {
                        // For a MEGA root context, this value is readonly and will inherit from the document header
                        $sdimcolumns[$key]['readonly'] = true;
                    }

                    if ( !util_isPlatformDisabled() ) {

                        if ( !$sdimcolumns[$key]['hidden'] && !$sdimcolumns[$key]['readonly'] ) {
                            $entity = $sdimcolumns[$key]['entity'];

                            if ( Pt_StandardUtil::autoFillRelated($entity) ) {
                                $sdimcolumns[$key]['onchange'] = 'pt_editor_defaultRelated(this, null);';
                            }
                        }

                    }
                }

                $scolumns = INTACCTarray_merge($scolumns, $sdimcolumns);
            }

            if (!util_isPlatformDisabled()) {
                $this->mergeSubtotalCustomDimensions($scolumns);
            }
            // ---- Subtotal Dimensions ends

            $scolumns[] = array('path'=>'PERCENTEDIT', 'fullname'=>_('Percent edit'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'ABSEDIT', 'fullname'=>_('Absolute edit'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'BASELINE', 'fullname'=> _('BaseLine'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'DISC_CHARGE', 'fullname'=>_('Discount charge'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'APPORTIONED', 'fullname'=>_('Apportioned'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'GLACCOUNTKEY', 'fullname'=>_('GL account'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'DEB_CRED' , 'fullname'=>_('Debit/Credit'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'ISTAX', 'fullname'=>_('Is tax'),'size' => 0,'subtotal'=>1,'hidden'=>1);
            $scolumns[] = array('path'=>'TAXDETAIL', 'fullname'=>_('Tax detail'),'size' => 0,'subtotal'=>1,'hidden'=>1);

            $sfield = array(
                'path'        => 'SUBTOTALS',
                'title'       => 'IA.SUB_TOTALS',
                'fullname'    => 'IA.SUB_TOTALS',
                '_func'       => 'MultilineLayout',
                'varpath'     => 'SUBTOTALS',
                'varname'     => '_obj__SUBTOTALS',
                'maxvertical' => 1,
                'columns'     => $scolumns,
                'subtotal'    => 1
            );

            $_params['SHOWTOTALS'] = 1;

            for ($i=0;$i< count($_params['pages']);$i++) {
                if (!strcmp($_params['pages'][$i]['title'], "Line Items")) {
                    $_params['pages'][$i]['fields'][] = $sfield;
                    break;
                }
            }
        }

        if ($this->dt) {
            $_params['title'] = 'Recurring ' . $this->dt;
        }

        return parent::Editor_Expand($_params);
    }



    /**
     * @param array $_params
     *
     */
    function Editor_Instantiate(&$_params)
    {
        global $gManagerFactory;
        
        $_sess = Session::getKey();

        parent::Editor_Instantiate($_params);
        $term = [];
        //$doctype 	= Request::$r->_dt;
        $mod = Request::$r->_mod;
        $entID = Request::$r->_entid;
        $date = Request::$r->_date;
        $r = Request::$r->_r;
        $copy = Request::$r->_copymode;
        $_action = Request::$r->_action;
        $_do = Request::$r->_do;
        $this->priceFetchDisabled = 0;

        $docparMgr            = $gManagerFactory->getManager('documentparams');
        $docMgr                = $gManagerFactory->getManager('recurdocument');
        $docpar             = $this->GetBaseDocPar();
        $num_fields         = count($_params['allfields']);

        //$docpar = $this->GetBaseDocPar();

        if ($docpar['ENABLE_DISCOUNT_CHARGE']  == 'false' ) {
            $this->MatchTemplates($_params, array('path' => 'DISCOUNTPERCENT'), $_foundarray);
            foreach ( $_foundarray as $i => $x) {
                $_foundarray[$i]['path'] = 'DISCOUNTPERCENT';
                $_foundarray[$i]['hidden'] = true;
            }
        }

        if ('' === $docpar['ALLOWEDITBILLTO'] || 'false' === $docpar['ALLOWEDITBILLTO']) {
            $this->MatchTemplates($_params, array('path' => 'BILLTO.CONTACTNAME'), $billtoarr);
            foreach ( $billtoarr as $i => $x) {
                $billtoarr[$i]['noview'] = true;
                $billtoarr[$i]['nonew'] = true;
                $billtoarr[$i]['nopick'] = true;

            }
        }
        if ('' === $docpar['ALLOWEDITSHIPTO'] || 'false' === $docpar['ALLOWEDITSHIPTO']) {
            $this->MatchTemplates($_params, array('path' => 'SHIPTO.CONTACTNAME'), $shiptoarr);
            foreach ( $shiptoarr as $i => $x) {
                $shiptoarr[$i]['noview'] = true;
                $shiptoarr[$i]['nonew'] = true;
                $shiptoarr[$i]['nopick'] = true;
            }
        }

        //to get the view link in the line entry screen level
        $this->MatchTemplates($_params, array('path' => 'ITEMID'), $itemidarr);
        foreach ( $itemidarr as $i => $x) {
            $itemidarr[$i]['assist'] = 'notfat';
        }
        //Set the customer/vendor
        $entType             = ($mod == 'so') ? 'customer' : 'vendor';

        if (($entID == '') && ($mod == 'so' || $mod == 'po')) {
            // find it in the array ...
            for ($num=0; $num < $num_fields; $num++) {
                if ($_params['allfields'][$num]['path'] == 'CUSTVENDID') {
                    $entID = $_params['allfields'][$num]['value'] ;
                    break;
                }
            }
        }

        if ($entID != '') {
            // load the entData array....
            list($entVID) = explode('--', $entID);
            $qry = 'QRY_RECURDOCUMENT_GET_'.isl_strtoupper($entType).'_FOR_EDIT';
            $entData = $docMgr->DoQuery($qry, array($entVID));
            $entData = $entData[0];
        }

        // Get recall info
        if ($this->state != $this->kShowNewState) {
            $valarray = array ('so' => 'S', 'po' => 'P', 'inv' => 'I');
            $spt = $valarray[$mod];
            global $_userid;
            $arrExplode = explode('@', $_userid);
            $userkey = array_shift($arrExplode);
            /** @var array $allowedDocs */
            $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($spt, 'T', $this->dt));
            upermFilterResult($allowedDocs, $userkey);
        }

        //LOOP all fields
        global $kAPid;
        $billNoPref = GetPreferenceForProperty($kAPid, 'BILLNOREQUIRED');
        for ($num=0; $num < $num_fields; $num++) {

            // Plug in the id to the tree
            $field =& $_params['allfields'][$num];
            if ($this->_deptOverride && $field['path'] == 'DEPARTMENT') {
                $field['hidden'] = false;
            }

            if ($this->_locOverride && $field['path'] == 'LOCATION') {
                $field['hidden'] = false;
            }

            if ($field['path'] == 'DOCPARID') {
                if ($this->dt) {
                    $field['value'] = $this->dt;
                }
            }

            if ($field['path'] == 'VENDORDOCNO') {
                $billnorequired    = ($billNoPref && $docpar['SALE_PUR_TRANS'] == 'Purchase' && $docpar['UPDATES_GL'] == 'A');
                if ($billnorequired) {
                    $_params['allfields'][$num]['required'] = true;
                }
                if ($docpar['SALE_PUR_TRANS'] != 'Purchase') {
                    $field['hidden'] = true;
                }
            }

            if ($field['path'] == 'SHIPVIA') {
                if ($this->state == $this->kShowNewState) {
                    if (!$field['value']) {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $field['value'] = $entData['SHIPPINGMETHOD'];
                    }
                }
            }

            if ($field['path'] == 'LINESELECT') {
                if ($_action == 'copy' || ($_action =='' && $_params['_func']=='Creator' && $_do=='edit')) {
                }
                else{
                    $field['disabled'] = true;
                    //$field['value'] = 'true';
                }
            }

            if ($field['path'] == 'WHENCREATED') {
                if (!$field['value'] || ($this->state == $this->kShowNewState && Request::$r->_action == '') ) {
                    $field['value'] = GetCurrentDate();
                } elseif ($date) {
                    $field['value'] = $date;
                }
                $date = $field['value'];
            }

            if ($field['path'] == 'LINESTATUS' && $field['value'] == 'Ended') {
                $field['readonly'] = true;
            }

            if ($this->state == $this->kShowNewState) {
                if ($field['path'] == 'DOCNO') {
                    if (!$entID && !$r) {
                        $field['hidden'] = true;
                    }

                }

                if ($field['path'] == 'NOTE' || $field['path'] == 'BACKORDER' || $field['path'] == 'PRINTED') {
                    $field['hidden'] = true;
                }
            } else {
                if ($field['path'] == 'PRINTED' && !$field['value']) {
                    $field['value'] = "No";
                }
                if ($field['path'] == 'NOTE' && !$field['value']) {
                    $field['hidden'] = true;
                }
            }

            if ($field['path'] == 'STATE') {
                for ($i = 0; $i < count($field['type']['validvalues']); $i++) {
                    if ($field['type']['validvalues'][$i] == 'Converted') {
                        $fieldPos = $i;
                    }
                }

                /** @noinspection PhpUndefinedVariableInspection */
                array_splice($field['type']['validvalues'], $fieldPos, 1);
                array_splice($field['type']['_validivalues'], $fieldPos, 1);
                if ($this->_stateEditable) {
                    $field['readonly'] = false;
                }
            }

            $virtual_term='';
            if ($field['path'] == 'TERM.NAME' ) {
                if ($docpar['SALE_PUR_TRANS'] == 'Internal') {
                    $field['hidden'] = true;
                    continue;
                }

                $termmod = ($mod == 'so') ? 'ar' : 'ap';
                $field['type']['entity'] = $termmod.'term';

                if ($this->state == $this->kShowNewState) {
                    if ($field['value'] != '') {
                        $termMgr = $gManagerFactory->getManager($field['type']['entity']);
                        $term = $termMgr->GetRaw($field['value']);
                        $term = $term[0];
                    } else {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $termKey = ( $entData['TERMSKEY'] != '') ? $entData['TERMSKEY'] : $docpar['TERMKEY'];
                        if ($termKey != '') {
                            GetTerm($termKey, $term);
                        }
                    }

                    $virtual_term     = $term['NAME'];

                    if ($term) {
                        $field['value'] = $term['NAME'];
                        if (!$date) {
                            for ($n=0; $n < $num_fields; $n++) {
                                if ($_params['allfields'][$n]['path'] == 'WHENCREATED') {
                                    $date = $_params['allfields'][$n]['value'] ;
                                }
                            }
                        }
                    }
                }
            }


            if ($field['path'] == 'CUSTVENDID' && ($mod == 'so' || $mod == 'po')) {

                if ($entType == 'vendor') {
                    $field['fullname'] = _('Vendor ID');
                } else {
                    $field['fullname'] = isl_ucfirst($entType) . " ID";
                }

                $field['type']['entity'] = $entType;

                $field['primaryDimension'] = ( $mod == 'po' ? 'VENDORID' : 'CUSTOMERID' );

                if ($this->state == $this->kShowNewState && $copy != 'Update') {

                    if ($copy == 'Copy') {
                        $field['required']    = true;
                        /** @noinspection PhpUndefinedVariableInspection */
                        $field['value'] = $entVID . '--' . $entData['NAME'];
                    } else {
                        $field['showhash']    = true;
                    }

                    $field['onchange'] .= 'AutoPopulateCustVendID(this.value,\'true\');';

                    if ($mod == 'po') {
                        if (IsMultiVisibilitySubscribed('vendor')) {
                            $qop = GetOperationId('ap/lists/vendor');
                            $field['onchange'] .= "FilterRestrictions('vendor', this.value, 'locationpick', '$_sess', '$qop'); FilterRestrictions('vendor', this.value, 'departmentpick', '$_sess', '$qop');";
                        }
                    } elseif ($mod == 'so') {
                        $field['onchange'] .= "RestrictProjectDimension('".$field['varname']."','CUSTOMER','ENTRIES'," . GetOperationId('ar/lists/project') . ");";
                        if (IsMultiVisibilitySubscribed('customer')) {
                            $qop = GetOperationId('ar/lists/customer');
                            $field['onchange'] .= "FilterRestrictions('customer', this.value, 'locationpick', '$_sess', '$qop'); FilterRestrictions('customer', this.value, 'departmentpick', '$_sess', '$qop');";
                        }
                    }
                }
                else {
                    $field['readonly'] = true;
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ($entVID) {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $field['value'] = $entVID . '--' . $entData['NAME'];
                    }
                }

                for ($n=0; $n < $num_fields; $n++) {

                    // Extract out values of certain fields
                    // This is to check  if the contactversion has changed, if not, then don't display the checkbox
                    $field =& $_params['allfields'][$n];
                    switch($field['path']) {
                    case 'SHIPTO.CONTACTNAME':
                        $shiptoName = $field['value'];
                        break;
                    case 'SHIPTOKEY':
                        break;
                    case 'BILLTO.CONTACTNAME':
                        $billtoName = $field['value'];
                        break;
                    case 'BILLTOKEY':
                        break;
                    }
                }



                // Get shipto/billto for the first time as defaults
                if ($this->state == $this->kShowNewState) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $shipto = ($shiptoName) ?: $entData['SHIPTONAME'];
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( !$shipto && $entData['VISIBLE'] == 'T') {
                        $shipto = $entData['DISPLAYCONTACTNAME'];
                    }

                    /** @noinspection PhpUndefinedVariableInspection */
                    $billto = ($billtoName) ?: $entData['BILLTONAME'];
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ( !$billto && $entData['VISIBLE'] == 'T') {
                        $billto = $entData['DISPLAYCONTACTNAME'];
                    }

                    for ($n=0; $n < $num_fields; $n++) {
                        if ($_params['allfields'][$n]['path'] == 'SHIPTO.CONTACTNAME') {
                            if ( !isset($_params['allfields'][$n]['value'])
                                || $_params['allfields'][$n]['value'] == '' || $copy == 'Copy'
                            ) {
                                $_params['allfields'][$n]['value'] = $shipto;
                            }
                        }

                        if ($_params['allfields'][$n]['path'] == 'BILLTO.CONTACTNAME') {

                            if ( !isset($_params['allfields'][$n]['value'])
                                || $_params['allfields'][$n]['value'] == ''  || $copy == 'Copy'
                            ) {
                                $_params['allfields'][$n]['value'] = $billto;
                            }
                        }

                        if ($_params['allfields'][$n]['path'] == 'CUSTVENDNAME') {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $_params['allfields'][$n]['value'] = $entData['NAME'];
                            $_params['allfields'][$n]['fullname'] = isl_ucfirst($entType) . " Name";
                            $_params['allfields'][$n]['readonly'] = true;
                        }
                    }
                }
            }

            if ($mod != 'inv') {
                if ($field['path'] == 'VIRTUAL.CUSTOMER') {
                    /** @noinspection PhpUndefinedVariableInspection */
                    if ($entVID) {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $field['value'] = $entVID . '--' . $entData['NAME'];
                    }
                }

                if ($field['path'] == 'VIRTUAL.TERM') {
                    if ( isset($virtual_term) && ($virtual_term!='')) {
                        $field['value'] = $virtual_term;
                    }
                    else {
                        $field['value'] = $term['NAME'];
                    }
                }
            }

            if ($field['path'] == 'DOCID') {
                $field['value'] = $this->dt;
            }

            if ($field['path'] == 'VIRTUAL.DOCPARID') {
                $field['value'] = $this->dt;
            }

            $hideFlds = array('UIPRICE', 'UIVALUE');
            if($this->_ismcpEnabled) {
                array_push($hideFlds, 'TRX_PRICE');
                array_push($hideFlds, 'TRX_VALUE');
            }
            if (in_array($field['path'], $hideFlds) && $docpar['OVERRIDE_PRICE']!='true') {
                $field['disabled'] = true;

                if($field['path'] =='UIVALUE') {
                    unset($field['type']['ptype']);
                }

                if($this->_ismcpEnabled && $field['path'] =='TRX_VALUE') {
                    unset($field['type']['ptype']);
                }
            }
        }

        if (Request::$r->_viewsch=='T') {
            Request::$r->_currentlayer = $this->scheduleLayer;

        } else {
            if ($this->state == $this->kShowNewState) {
                if (!Request::$r->_currentlayer) {
                    Request::$r->_currentlayer = 'Layer0';
                }
            } else {
                //This is not explicitly set by default, which causes js issues as a
                //lot of code is built upon the reliance of this layer value
                Request::$r->_currentlayer = 'Layer1';
            }
        }


        $hideLocDept = 0;
        $contextLocation = GetContextLocation();
        if( $docpar['LOCOVERRIDE'] == 'true' ) {
            //checking if the params has subtotals set $hideLocDept to 1
            $f = array();
            $this->MatchTemplates($_params, array('path' => 'SUBTOTALS'), $f);
            foreach ( $f as $i => $x) {
                if($f[$i]['subtotal'] == 1) {
                    $hideLocDept = 1;
                }
            }
        }

        if( IsMultiEntityCompany() && !$contextLocation && $hideLocDept == 1) {
            //only if params has subtotals do the hiding of location/dept
            $fields = array();
            $this->MatchTemplates($_params, array('path' => 'LOCATION'), $fields);
            foreach ( $fields as $i => $x) {
                if($fields[$i]['entity'] == 'recursubtotals') {
                    $fields[$i]['fullname'] = '';
                    $fields[$i]['readonly'] = 1;
                }
            }
            $fields = array();
            $this->MatchTemplates($_params, array('path' => 'DEPARTMENT'), $fields);
            foreach ( $fields as $i => $x) {
                if($fields[$i]['entity'] == 'recursubtotals') {
                    $fields[$i]['fullname'] = '';
                    $fields[$i]['readonly'] = 1;
                }
            }
        }

        If( IsMultiEntityCompany() && $contextLocation && $hideLocDept == 1) {
            //Get the total number of rows in subtotals section
            $fields = array();
            $this->MatchTemplates($_params, array('title' => 'Sub Totals', 'path' => 'SUBTOTALS'), $fields);
            foreach ( $fields as $i => $x) {
                $subtotalRows = ibcsub($fields[$i]['actualnumofrows'], '1', 0);
            }

            //Since location is defaulted while creating transactions from entity,
            //set location is null for the first and last row in subtotals
            $fields = array();
            $this->MatchTemplates($_params, array('path' => 'LOCATION'), $fields);
            foreach ( $fields as $i => $x) {
                /** @noinspection PhpUndefinedVariableInspection */
                if( $fields[$i]['entity'] == 'recursubtotals'
                    && ($fields[$i]['rownum'] == 0 ||  $fields[$i]['rownum'] == $subtotalRows)
                ) {
                    $fields[$i]['value'] = '';
                }
            }
        }

        //hide view Recurring schedule if schopkey is not set
        $this->MatchTemplates($_params, array('path' => 'DOCHDRNO'), $dochdrfields);
        if(!isset($dochdrfields[0]['value'])) {
            $this->MatchTemplates($_params, array('path' => 'SALESCONTRACT'), $scfields);
            foreach ( $scfields as $i => $x) {
                $scfields[$i]['hidden'] = true;
                $scfields[$i]['readonly'] = 1;
                $scfields[$i]['hreftxt'] = '';
            }
        }

        //
        // ----------- if multi currency is enabled ---------------
        //
        // show the currency if the 'Allow creating, editing & deleting foreign currency documents'
        // is set to true in OE Configuration
        if($docpar && $this->_ismcpEnabled) {
            if($docpar['EXCH_RATE_TYPE_ID']=='-1') {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $docpar['EXCHRATETYPES']['NAME'] = $exchTypeMgr->GetExchangeRateTypeName($docpar['EXCH_RATE_TYPE_ID']);
            }
            $this->ShowMCPControls($_params, $docpar['EXCHRATETYPES']['NAME'], $docpar['DISPLAY_BASECURRENCY'], $docpar['OVERRIDE_EXCH_RATE_TYPE']);
        }

        if($this->atlas && !GetContextLocation()) {
            $this->ShowAtlasControls($_params);
        }
        if ($docpar['UPDATES_GL'] == 'A') {
            $this->MatchTemplates($_params, array('path' => 'FORM1099'), $form1099Fields);
            foreach ( $form1099Fields as $i => $x) {
                $form1099Fields[$i]['hidden'] = false;
            }
        }
        $pref_value = AP1099Preference();
        $form1099Fields = array();
        $this->MatchTemplates($_params, array('path' => 'FORM1099'), $form1099Fields);

        /** @noinspection PhpUndefinedVariableInspection */
        if ($entVID) {
            $vendor1099 = Get1099FromVendor($entVID);
        }
        foreach ( $form1099Fields as $i => $x) {
            $form1099Fields[$i]['disabled'] = ($pref_value == 'N' || empty($vendor1099) ? true : false);
            /** @noinspection PhpUndefinedVariableInspection */
            if ( $vendor1099 && empty($form1099Fields[$i]['value'])) {
                $form1099Fields[$i]['value'] = 'true';
            }
        }
    }



    /**
     * Used in populating the department field
     *
     * @return array List of departments
     */
    function GetDeptAutoFillArray()
    {
        global $gManagerFactory;
        $departmentMgr = $gManagerFactory->getManager('department');

        $params = array( 'filters' => array (array (array( 'STATUS', 'in', array('active')))));
        $depts = $departmentMgr->GetList($params);
        return $depts;
    }



    /**
     * Retrieves a list of customers that can be vendor/customer
     *
     * @return array List of customer/vendors
     */
    function GetEntityAutoFillArray()
    {
        global $gManagerFactory;
        $entMgr = $gManagerFactory->getManager('customer');

        $params = array(
        'selects' => array(
        'CUSTOMERID',
        'NAME',
        'ARACCOUNT',
        'ARACCOUNTTITLE',
        'ACCOUNTLABEL',
        'TERMNAME',
        'DISPLAYCONTACT.CONTACTNAME',
        'BILLTO.CONTACTNAME',
        'SHIPTO.CONTACTNAME',
        'CREDITLIMIT',
        'TOTALDUE',
        'ONHOLD',
        ),
        'filters' => array (array (array( 'STATUS', 'in', array('active')))),
        'orders' => array(array('CUSTOMERID', 'asc')),
        );
        $entList = $entMgr->GetList($params);
        return $entList;
    }



    /**
     * Used in populating the location field
     *
     * @return array List of locations
     */
    function GetLocAutoFillArray()
    {
        global $gManagerFactory;
        $location = $gManagerFactory->getManager('location');

        $params = array( 'filters' => array (array (array( 'STATUS', 'in', array('active')))));
        $locs = $location->GetList($params);
        return $locs;
    }



    /**
     * Used in populating the term field
     *
     * @return array List of terms
     */
    function GetTermAutoFillArray()
    {
        global $gManagerFactory;
        $termMgr = $gManagerFactory->getManager('arterm');

        $params = array( 'filters' => array (array (array( 'STATUS', 'in', array('active')))));
        $terms = $termMgr->GetList($params);
        return $terms;
    }


    /**
     * @param  string    $recno
     * @param  string    $docparid
     * @param  string    $xsltemplateid
     * @param array      $unusedParams   for signature compatibility with DocumentFormEditor
     *
     * @return string
     * @throws Exception
     */
    function GetXSLTemplate($recno, $docparid, $xsltemplateid, /** @noinspection PhpUnusedParameterInspection */ $unusedParams)
    {
        global $gManagerFactory;

        //$docparid = Request::$r->_dt;
        $docMgr = $gManagerFactory->getManager('recurdocument');
        $docid = $docMgr->DoQuery('QRY_RECURDOCUMENT_GET_DOCPAR_RECORDNO', array($recno));
        $docid = $docid[0]['DOCID'];

        //Check the Docpar for the default template to use
        //$docparMgr = $gManagerFactory->GetManager('documentparams');
        //$docpar = $this->GetBaseDocPar();

        $docparMgr    = $gManagerFactory->getManager('documentparams');
        $docpar = $docparMgr->GetBaseLatest($docid, false);
        if ($docpar['XSLTEMPLATE']) {
            $this->XSL_Template_Type = 'db'; // remember what type of transform process we are using

            $XslformatMgr = $gManagerFactory->getManager('xslformat');
            $formatdata = $XslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($docpar['XSLTEMPLATE']));
            $file = ($formatdata[0]['XSL']) ? $XslformatMgr->GetXSL(databaseStringUncompress($formatdata[0]['XSL'])) : '';
        }

        // Go for the old method
        /** @noinspection PhpUndefinedVariableInspection */
        if (!$file) {
            $fileName=$docpar['SALE_PUR_TRANS'].'_'.$docpar['DOCCLASS'];
            $file=@file(XSLDIR.$fileName.'_layout_print.xsl', 1);
            $this->XSL_Template_Type = 'file_print_layout';
            if (!$file) {
                $this->XSL_Template_Type = 'entity_print_layout';
                $file = @file(XSLDIR.$this->_params['entity'] . '_layout_print.xsl', 1);
                if (!$file) {
                    $this->XSL_Template_Type = 'entity_edit_layout';
                    $file = @file(XSLDIR.$this->_params['entity'] . '_layout_edit.xsl', 1);
                }
            }
            $file = join('', $file);
        }

        return ($file);
    }



    /**
     * This function overrides the DocumentEditor method.
     *
     * It allowed defining special handler rules so that
     * the code will work properly when returning from an
     * error condition.
     */
    function InitConstants()
    {
        Editor::InitConstants();
        $this->kActionHandlers[$this->kDeriveDocumentAction] =
        array (
        'handler' => 'ProcessDeriveDocumentAction',
        'states' => array(
        $this->kShowNewState,
        $this->kShowEditState,
        $this->kShowViewState
        )
        );

        $this->kActionHandlers[$this->kFetchForNewAction] =
        array (
        'handler' => 'ProcessEditNewAction',
        'states' => array(
                    $this->kInitState,
                    $this->kShowNewState
        )
        );

        //change was made here to add $this->kShowNewState to
        // the list of valid states...
        //
        // Action=edit & state=shownew is a valid condition
        // for recurring transactions.
        $this->kActionHandlers[$this->kFetchForEditAction] =
        array ( 'handler' => 'ProcessEditAction',
        'states' => array($this->kInitState,
                    $this->kShowViewState,
                    $this->kShowNewState,
                    $this->kShowEditState
        )
        );

        $this->DocumentInitConstants();
    }



    /**
     * Method to allow setup interaction with data or
     * display elements when mode is copy.
     *
     * @param  array $_params
     * @return bool
     */
    function ProcessCopyNewAction(&$_params)
    {
        global $gErr, $gManagerFactory;
        $ok = true;
        $this->isCopyNew = true;

        //Get the object current screen or from transaction screen
        //when repeat action is done from document transaction screen
        $obj =& Request::$r->GetCurrentObject();

        // For new editor we do not have the current object structure. The right way is to query the current document.
        if ( !$obj || count($obj['ENTRIES']) == 0 ) {

            $orgTrxID = Request::$r->_origTrxID;

            if ($orgTrxID) {
                $mod = Request::$r->_mod;
                $docMgr =  $gManagerFactory->getManager($mod . 'document', false, array( 'DOCTYPE' => $this->dt));
                $obj = $docMgr->get($orgTrxID);
                $docMgr->getRelationships($obj, false);
                $this->prepareObjectForCopyNew($obj);
                Request::$r->_currentlayer = 'Layer1';
            }
        } else {
            $from = $_REQUEST['_from'];
            if ( $from && $from == 'document' ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $docMgr =  $gManagerFactory->getManager($mod . 'document', false, array( 'DOCTYPE' => $this->dt));
                $docMgr->getRelationships($obj, false);
            } else {
                $entityMgr = $this->GetManager($_params['entity']);
                $entityMgr->getRelationships($obj, false);
            }
        }
        unset($obj['RECORDNO']);
        if ( isset($this->dt) && $this->dt != '' ) {
            $docparmrec = $this->GetBaseDocPar();
            if ( $docparmrec['ENABLEOVERRIDETAX'] != 'true' ) {
                for ( $i = 0; $i < count($obj['ENTRIES']); $i++ ) {
                    unset($obj['ENTRIES'][$i]['OVERRIDETAX']);
                }
            }
        }
        $this->setPlatformData($obj);

        foreach( $obj['ENTRIES'] as $key => $val){
            $obj['ENTRIES'][$key]['LINESELECT'] = 'true';
                        unset($obj['ENTRIES'][$key]['DOCENTRYKEY']);
        }
        if (!isset($obj) || $obj == '') {
            //Unable to get transaction information
            $gErr->addIAError('INV-0214', __FILE__ . ':' . __LINE__, 'Please resubmit the request', []);
            $this->state = $this->kErrorState;
            $ok = false;
            return $ok;
        }

        if (isset($obj['DOCID'])&& isset($obj['DOCNO'])) {
            $obj['SOURCEDOCUMENT'] = $obj['DOCID'].'--'.$obj['DOCNO'];
        }

        //		if (!isset($obj['SCHEDULEDALLOWRETRY']) || $obj['SCHEDULEDALLOWRETRY']=='') {
        //			$obj['SCHEDULEDALLOWRETRY'] = 'true';
        //		}
        //
        //		if (!isset($obj['SCHEDULEDRETRYLIMITCOUNT']) || $obj['SCHEDULEDRETRYLIMITCOUNT']=='') {
        //			$obj['SCHEDULEDRETRYLIMITCOUNT'] = 10;
        //		}

        if (!isset($obj['SCHEDULEDCONTACTEMAIL']) || $obj['SCHEDULEDCONTACTEMAIL']=='') {
            $obj['SCHEDULEDCONTACTEMAIL'] = '';
        }

        //The information from document screen contains ENTRIES array so we do not need
        // to copy or transfer that detail.
        if ($this->state != $this->kErrorState) {
            Request::$r->SetCurrentObject($obj);
            $this->state = $this->kShowNewState;
        }

        parent::ProcessCopyNewAction($_params);

        return $ok;
    }


    /**
     * Method to allow setup interaction with object data or
     * display elements when user has clicked save button.
     *
     * @param array $_params
     *
     * @return bool
     *
     */
    function ProcessCreateAction(&$_params)
    {
        global $gManagerFactory;
        /** @var URLS $gURLs */
        global $gURLs;

        $entityMgr = $gManagerFactory->getManager($_params['entity']);

        $obj =& Request::$r->GetCurrentObject();
        $obj = $this->DoRefreshAction($_params, $obj);
        $ok = $this->PrepareInputValues($_params, $obj);

        $temp_obj=$obj;
        $this->EditorGetSubTotals($_params, $temp_obj);

        //Add recurring invoices and related objects
        $ok = $ok && $entityMgr->add($obj);

        // Save platform relationship info here
        if (!util_isPlatformDisabled()) {
            /** @noinspection PhpUndefinedVariableInspection */
            Pt_StandardUtil::savePlatformRelationships($_params['entity'], $objId, TYPE_NEW);
        }

        $entityDesc = ($_params['entityDesc']) ?: "Recurring Document" ;

        if (!$ok) {
            $warnmessage = HasErrors();
            if ($warnmessage) {
                global $gErr;
                $gErr->addIAError('INV-0779', __FILE__ . ":" . __LINE__, "Creating $entityDesc failed", ['ENTITY_DESC' => $entityDesc]);
                $this->state = $this->kErrorState;
            }
            else {
                $obj =& Request::$r->GetCurrentObject();
                //					foreach($obj['ENTRIES'] as $key => $val){
                //						$obj['ENTRIES'][$key]['LINESELECT'] = 'true';
                //					}
                Request::$r->SetCurrentObject($obj);
                Request::$r->_kNoWarn = true;
                Request::$r->_action = $this->kCreateAction;
                $this->state = $this->kShowNewState;
            }
        }
        else {

            //Give the message to show the document was just created
            $confirmation = _("The ".$entityDesc." was created successfully");
            $this->SetMessageWithObject($confirmation, $obj);

            $after = Request::$r->after;

            if ($after == 1) {
                Request::$r->_currentlayer = '';
                Request::$r->_changed = 'false';
                $obj =& Request::$r->GetCurrentObject();
                //				foreach($obj['ENTRIES'] as $key => $val){
                //					$obj['ENTRIES'][$key]['LINESELECT'] = 'true';
                //				}
                $nobj['RECORDID'] = $obj['RECORDID'];
                if ($this->state != $this->kErrorState) {
                    Request::$r->SetCurrentObject($nobj);
                    $this->state = $this->kShowNewState;
                }
            }elseif ($this->GetPreference($_params, "Create.RequireConfirmation")) {
                $this->state = $this->kConfirmState;
            }
            elseif ($gURLs->HasReturnPath()) {
                $this->state = $this->kGoBackState;
            }
            elseif ($_params['popup']) {
                $this->state = $this->kCloseState;
            }
            else {
                $this->state = $this->kGoHomeState;
            }

        }

        $mod = Request::$r->_mod;
        //$dt = Request::$r->_dt;
        $docid = Request::$r->_r;
        $list_op = GetOperationId($mod . '/lists/' . $mod . 'recurdocument');
        $_done = Request::$r->_done;
        $_sess = Session::getKey();

        if (isl_strstr($_done, "sforcekey") === false) {
            $this->done = 'lister.phtml?.op='.$list_op.'&.r='.urlencode($docid).'&.dt='.urlencode($this->dt).'&.sess='.$_sess;
        }
        return $ok;
    }

    /**
     * @param array $_params
     */
    function ProcessRefreshAction(&$_params)
    {
        $obj =& Request::$r->GetCurrentObject();

        $obj['DOCPARID'] = $obj['DOCID'];
        parent::ProcessRefreshAction($_params);
    }


    /**
     * PrintOnLoad
     */
    function PrintOnLoad()
    {
        if($this->_ismcpEnabled) {
            $disableExchRateType = "DisableExchRateType();";
        }

        if ($this->state != 'showview') {
            /** @noinspection PhpUndefinedVariableInspection */
            echo " SetupSavedItems('Layer1','Layer1_form'); SetTabDispAttributes();" . $disableExchRateType;
        } elseif (Request::$r->_viewsch == 'T') {
            echo " ToggleLayer('$this->scheduleLayer');";
        } else {
            echo " ToggleLayer('$this->scheduleLayer');";echo " ToggleLayer('Layer1');";
        }
        if ($this->alertonload) {
            echo "alert('".$this->onloadmesg."');";
        }
        Editor::PrintOnLoad();

        $_sess = Session::getKey();

        //$doctype 	= Request::$r->_dt;
        //$docparMgr	= $gManagerFactory->GetManager('documentparams');
        $docpar = $this->GetBaseDocPar();

        if ('' === $docpar['ALLOWEDITBILLTO'] || 'false' === $docpar['ALLOWEDITBILLTO']) {
            echo "document.forms[1].elements['_obj__BILLTO__CONTACTNAME'].disabled=true;";

        }
        if ('' === $docpar['ALLOWEDITSHIPTO'] || 'false' === $docpar['ALLOWEDITSHIPTO']) {
            echo "document.forms[1].elements['_obj__SHIPTO__CONTACTNAME'].disabled=true;";
        }

        $mod = Request::$r->_mod;
        $action = ($this->state == 'shownew') ? 'create' : 'save';

        $copy = Request::$r->_copymode;
        if($mod == 'so' && $this->itemsHaveStartEndDate == true) {
            $disableProrateButton = "DisableProrateButtons();";
        }
        if ($this->state != 'showview') {
            /** @noinspection PhpUndefinedVariableInspection */
            echo $disableProrateButton;
        }

        if ( $mod != 'inv' && isset($copy) && $copy != '') {

            echo "AutoPopulateCustVendID(document.forms[0].elements['_obj__CUSTVENDID'].value, 'false');";
        }

        //If there is a warning then show the warning and decide to continue or not based on the response
        echo "if(document.forms[0]._kNoWarn.value == 'true') {";
        if ($mod == 'po') {
            $dict = Dictionary::getInstance();
            $vendorTitle = $dict->GetRenamedText(_('Vendor'));
            echo " if(confirm('A Bill in Accounts Payable with the same ".$vendorTitle." Reference Number already exists. Do you want to use the same number?')) { ";
        } else {
            echo " if(confirm('" . _('An Invoice in Accounts Receivable with the same number already exists. Do you want to use the same number?') . "')) { ";
        }
        echo " if(BeforeSubmit()){ document.forms[0]._action.value='".$action."';document.forms[0]._kNoWarn.value = 'true'; document.forms[0].submit();}";
        echo " } else { ";
        echo " document.forms[0]._kNoWarn.value = ''; ";
        echo " } ";
        echo "}";

        if ($this->state != $this->kShowViewState) {
            if ($mod == 'po' && IsMultiVisibilitySubscribed('vendor')) {
                $qop = GetOperationId('ap/lists/vendor');
                echo "if(document.forms[1].elements['_obj__CUSTVENDID'].value != '') {";
                echo " FilterRestrictions('vendor', document.forms[1].elements['_obj__CUSTVENDID'].value, 'locationpick', '$_sess', '$qop');";
                echo " FilterRestrictions('vendor', document.forms[1].elements['_obj__CUSTVENDID'].value, 'departmentpick', '$_sess', '$qop');";
                echo "} ";
            } elseif ($mod == 'so' && IsMultiVisibilitySubscribed('customer')) {
                $qop = GetOperationId('ar/lists/customer');
                echo "if(document.forms[1].elements['_obj__CUSTVENDID'].value != '') {";
                echo " FilterRestrictions('customer', document.forms[1].elements['_obj__CUSTVENDID'].value, 'locationpick', '$_sess', '$qop');";
                echo " FilterRestrictions('customer', document.forms[1].elements['_obj__CUSTVENDID'].value, 'departmentpick', '$_sess', '$qop');";
                echo "} ";
                if(IADimensions::IsDimensionEnabled('so', 'project')) {
                    $qop = GetOperationId('ar/lists/project');
                    echo " if (document.forms[1].elements['_obj__CUSTVENDID'].value != '') { ";
                    echo "RestrictProjectDimension('_obj__CUSTVENDID','CUSTOMER','ENTRIES',$qop);";
                    echo "} ";
                }
            }
        }
    }



    /**
     * Method to allow setup interaction with data or
     * display elements when state is showedit.
     *
     * @param  array $_params
     *
     * @return bool
     */
    function ProcessEditAction(&$_params)
    {
        global $gManagerFactory;
        parent::ProcessEditAction($_params);

        $ok = true;

        $entityMgr = $gManagerFactory->getManager($_params['entity']);
        if ($this->ProcessErrorRetrivalAction($entityMgr)) {
            return true;
        }

        $obj = Request::$r->GetCurrentObject();
        if (!isset($obj) || $obj == '') {
            $ok = false;
        }

        $mode = Request::$r->_do;
        $IsChanged = Request::$r->_changed;
        if($mode=='edit' && (!isset($IsChanged) || $IsChanged=='')) {
            foreach( $obj['ENTRIES'] as $key => $val){
                $obj['ENTRIES'][$key]['LINESELECT'] = 'true';
            }
        }

        $docparmrec = array();
        if ( isset($this->dt) && $this->dt != '' ) {
            $docparmrec = $this->GetBaseDocPar();
        }

        for ($i=0;$i<count($obj['ENTRIES']);$i++){
            if (isset($obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'])) {
                list($ln) = explode('--', $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']);
                $qry = "select name from icwarehouse where location_no=:1 and cny#=:2";
                $result =  QueryResult(array($qry,$ln,GetMyCompany()));
                $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']=$ln.'--'.$result[0]['NAME'];
            }
            if ( $docparmrec['ENABLEOVERRIDETAX'] != 'true' ) {
                unset($obj['ENTRIES'][$i]['OVERRIDETAX']);
            }
        }

        Request::$r->_changed = false;

        //$doctype = Request::$r->_dt;
        $obj['DOCPARID'] = $this->dt;
        $this->EditorGetSubTotals($_params, $obj);

        if (!$ok) {
            global $gErr;
            //Fetching recurring invoice failed, try request again
            $gErr->addIAError('INV-0215', __FILE__ . ":" . __LINE__, 'Could not retrieve recurring transaction template', []);
            $this->state = $this->kErrorState;
        }
        else {

            Request::$r->SetCurrentObject($obj);
            $this->state = $this->CalcEditorState($entityMgr);
        }
        return $ok;
    }



    /**
     * Method to allow setup interaction with data or
     * display elements when state is shownew.
     *
     * @param  array $_params
     *
     * @return bool
     */
    function ProcessEditNewAction(&$_params)
    {
        //epp('TRACELINE IN ...RecurDocumentEditor::ProcessEditNewAction **Entered ** @'.__LINE__); //??remove bharris
        global $gManagerFactory;
        $this->state = 'shownew';

        if ($this->_fromError) {
            return true;
        }

        //$doctype = Request::$r->_dt;
        $entityMgr = $gManagerFactory->getManager($_params['entity']);

        if ($this->ProcessErrorRetrivalAction($entityMgr)) {
            $this->state = $this->kShowNewState;
            return true;
        }
        Request::$r->_changed = false;
        $recalledID = Request::$r->{Globals::$g->kId};

        // There is a weird mix of recalled doc data and default doc data here.  If there are problems,
        // look here.
        if ($recalledID) {
            $old =  $entityMgr->get($recalledID);

            if (!$old) {
                global $gErr;
                $gErr->addIAError(
                    'INV-0780', __FILE__.":".__LINE__,
                    "Fetching transaction '$recalledID' failed. " .
                    "TransactionID '$recalledID' has been defined in the setup as a template for creating new transactions.",
                    ['RECALLEDID' => $recalledID]
                );
                $this->state = $this->kErrorState;
            }
            else {

                // recalculate subtotals based on new definition.
                $new = $old;
                EntityManager::SetByPath($new, $entityMgr->GetKeyFieldName(), '');
            }
        }
        if (empty($this->dt)) {
            $docs = GetDocumentParams(Request::$r->_mod, Request::$r->_cat);
            if (empty($docs)) {
                $gErr = Globals::$g->gErr;
                if(IsMultiEntityCompany() && !GetContextLocation()) {
                    $gErr->addIAError(
                        'INV-0216', __FILE__.':'.__LINE__,
                        'No active transaction definitions found', [],
                        'No active transaction definitions were found at root level', [],
                        'Create a transaction defintion at root level or create the recurring template within an entity', []
                    );
                } else {
                    $gErr->addIAError(
                        'INV-0217', __FILE__.':'.__LINE__,
                        'No active transaction definitions found', [],
                        'No active transaction definitions were found', [],
                        'Create a transaction defintion', []
                    );
                }
                $this->state = $this->kErrorState;
            }
        }

        $new['DOCPARID'] = $this->dt;

        // ------------------ commented out for later retrylimit work. - bharris
        //		if (!isset($new['SCHEDULEDALLOWRETRY']) || $new['SCHEDULEDALLOWRETRY']=='') {
        //			$new['SCHEDULEDALLOWRETRY'] = 'true';
        //		}
        //
        //		if (!isset($new['SCHEDULEDRETRYLIMITCOUNT']) || $new['SCHEDULEDRETRYLIMITCOUNT']=='') {
        //			$new['SCHEDULEDRETRYLIMITCOUNT'] = 10;
        //		}

        if (!isset($new['SCHEDULEDCONTACTEMAIL']) || $new['SCHEDULEDCONTACTEMAIL']=='') {
            $new['SCHEDULEDCONTACTEMAIL'] = '';
        }

        //epp('TRACELINE...RecurDocumentEditor::ProcessEditNewAction @'.__LINE__); //??remove bharris
        $this->EditorGetSubTotals($_params, $new);

        if ($this->state != $this->kErrorState) {
            Request::$r->SetCurrentObject($new);
            $this->state = $this->kShowNewState;
        }
        return true;
    }



    /**
     * Method to allow final modifications prior to
     * updating object data.
     *
     * @param array $_params
     */
    function ProcessSaveAction(&$_params)
    {
        $obj =& Request::$r->GetCurrentObject();

        $obj['RECORDNO'] = Request::$r->_r;
        $obj['WHENMODIFIED'] = GetCurrentDate(IADATE_USRFORMAT);

        Request::$r->SetCurrentObject($obj);

        //Update recurring document and associated objects
        Editor::ProcessSaveAction($_params);

    }


    /**
     * Method to allow updates to document display values when
     * state is set to 'showview'.
     *
     * @param array $_params
     *
     * @return bool
     */
    function ProcessViewAction(&$_params)
    {
        global $gManagerFactory;

        parent::ProcessViewAction($_params);

        $ok = true;

        $obj = Request::$r->GetCurrentObject();
        if (!isset($obj) || $obj == '') {
            $ok = false;
        }

        $obj['DOCPARID'] = $this->dt;
        $this->EditorGetSubTotals($_params, $obj);

        $this->GetBaseDocPar();
        $itemMgr    = $gManagerFactory->getManager('item');

        for ($i=0;$i<count($obj['ENTRIES']);$i++){
            list($itemid) = explode('--', $obj['ENTRIES'][$i]['ITEMID']);

            $itemraw = $itemMgr->GetRaw($itemid);
            if ($itemraw[0]['ITEMTYPE']=='I' || $itemraw[0]['ITEMTYPE']=='K') {
                if (isset($obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'])) {
                    $ln = $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'];
                    $qry = "select name from icwarehouse where location_no=:1 and cny#=:2";
                    $result =  QueryResult(array($qry,$ln,GetMyCompany()));
                    $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']=$obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'].'--'.$result[0]['NAME'];
                }
            }
        }

        if (!$ok) {
            global $gErr;
            //Fetching recurring invoice failed, try request again
            $gErr->addIAError('INV-0218', __FILE__ . ":" . __LINE__, 'Could not retrieve recurring transaction template', []);
            $this->state = $this->kErrorState;
        }
        else {
            $this->PreprocessViewAction($obj);
            Request::$r->SetCurrentObject($obj);
        }
        return $ok;
    }

    /**
     * @param array $_params
     *
     * @return mixed
     */
    function MergeLayout($_params)
    {
        $mod = Request::$r->_mod;
        $action = Request::$r->_action;

        if ($action == 'copy') {
            $this->_params['entity'] = $mod.'document';
        }
        return parent::MergeLayout($_params);
    }



    /**
     * Prevents Editor from trying to display scheduling fields
     *
     * @param array  $_field
     * @param string $layout used only in some descendants of Editor class
     * @param bool   $first  used only in some descendants of Editor class
     */
    function ShowFieldsRow(&$_field, $layout = "", $first = false)
    {
        parent::ShowFieldsRow($_field);
    }


    /**
     * Places the configured buttons on the form.
     *
     * @param array $_params
     * @param bool  $isApprovalEnabled
     */
    function ShowFormButtons( $_params, $isApprovalEnabled = false)
    {
        Editor::ShowFormButtons($_params);
    }



    /**
     * Adds hidden fields to the displayed documents html
     */
    function ShowGeneralHiddenFields()
    {
        parent::ShowGeneralHiddenFields();
        ?>
     <INPUT type="hidden" name="_kNoWarn" value="<? echo Request::$r->_kNoWarn; ?>">
     <INPUT type="hidden" name="_r" value="<? echo Request::$r->_r; ?>">
        <?
    }

    /**
     * @param array $_params
     *
     * @return array
     */
    function Buttons_Instantiate($_params)
    {
        $_params = Editor::Buttons_Instantiate($_params);

        if($_params['state'] == Editor_ShowViewState) {
            /** @var Security $gSecurity */
            global $gSecurity;
            if ($gSecurity->IsOperationAllowed($_params['entity'], 'create')) {
                $copybutton = 'Duplicate';
                $copyaction = 'copy';

                $_params['copybutton'] = $copybutton;
                $_params['copyaction'] = $copyaction;
            }
        }

        return $_params;
    }


    /**
     * Adds the 'Save and New' button to the form
     *
     * @param array $_params
     */
    function ShowSaveAndNewButtons($_params)
    {

        $saveandnewbutton     = $_params['saveandnewbutton'];
        $saveandnewaction     = $_params['saveandnewaction'];

        $cssClass = $this->isQuixote ? 'btn btn-primary' : 'nosavehistory';

        if ($saveandnewbutton) { ?>
         <INPUT type="hidden" name="after" value=''>
         <INPUT id="saveandnewbuttid" type="button" class="<?= $cssClass; ?>" name="saveandnewbutton" value="<?= $saveandnewbutton ?>"
          onclick="document.forms[0].<? echo Editor_Action ; ?>.value = '<?= $saveandnewaction ?>';document.forms[0].after.value = 1;if ( BeforeSubmit() && beforeSubmitJS() ) { document.forms[0].submit(); };" disableonsubmit="true">
        <?
        }
    }


    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @param bool $addYuiCss
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);
        ?>
     <script language="Javascript">
     var fromRecurDocument = true;
     </script>
     <script src="../resources/js/recurdocumenteditor.js"></script>
        <?
    }

    /**
     * @return EntityManager
     */
    protected function getEntryManager()
    {
        return $this->GetManager('recurdocumententry');
    }

    /**
     * @param array $obj
     */
    function prepareObjectForCopyNew(&$obj)
    {
        if ($obj['CUSTVENDNAME'] && $obj['CUSTVENDNAME'] != '') {
            $obj['CUSTVENDID'] = $obj['CUSTVENDID'] . "--" .$obj['CUSTVENDNAME'];
        }

        if ($obj['EXCHRATETYPES']['NAME'] == CUSTOM_RATE) {
            unset($obj['EXCHRATETYPES']['NAME']);
        }

        $dateFields = array('WHENCREATED', 'WHENPOSTED', 'WHENDUE', 'WHENPAID', 'WHENMODIFIED','WHENDISCOUNT','EXCHRATEDATE');
        foreach($dateFields as $fld){
            if($obj[$fld] != '') {
                  $obj[$fld] = FormatDateForDisplay($obj[$fld]);
            }
        }

        $entityMgr = $this->GetManager($this->_params['entity']);
        foreach ($entityMgr->customFields as $cField) {
            $key = $cField->customFieldID;
            $type = $cField->type;
            if(!is_null($key) && isl_strtoupper($type) == "DATE") {
                $obj[$key]  = FormatDateForDisplay($obj[$key]);
            }
        }
        $documententryMgr = $this->getEntryManager();
        for ($i=0; $i < count($obj['ENTRIES']); $i++) {
            $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO'] = $obj['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']."--".$obj['ENTRIES'][$i]['WAREHOUSE']['NAME'];

            //This include custom fields also
            foreach($documententryMgr->_fieldInfoMap as $Field){
                $key = $Field['path'];
                $type = $Field['type']['ptype'];
                if(!is_null($key) && isl_strtoupper($type) == "DATE") {
                     $obj['ENTRIES'][$i][$key]  = FormatDateForDisplay($obj['ENTRIES'][$i][$key]);
                }
            }
        }

    }


    /**
     * Function to get the subtotal entity for current record
     *
     * @return string Subtotal entity
     */
    function getSubtotalsDefName()
    {
        return $this->mod.'recursubtotals';
    }

}    // finish class RecurDocumentEditor

