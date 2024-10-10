<?
import('editor');

/**
 * Class DocumententryTrackEditor
 */
class DocumententryTrackEditor extends Editor
{
    /** @var array $itemDetails */
    var $itemDetails;

    /** @var  bool $isSerialTrackingEnabled */
    var $isSerialTrackingEnabled;

    /** @var  bool $isBinTrackingEnabled */
    var $isBinTrackingEnabled;

    /** @var  bool $isLotTrackingEnabled */
    var $isLotTrackingEnabled;

    /** @var  bool $hasExpirationDate */
    var $hasExpirationDate;

    /** @var  string $itemID */
    var $itemID;

    /** @var string $whseID */
    var $whseID;

    /**
     * @param array $_params
     */
    function __construct($_params)
    {
        parent::__construct($_params);
        $this->initItemDetails(); 
    }

    /**
     * initItemDetails
     */
    function initItemDetails()
    {
        global $gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');

        $this->itemID = Request::$r->_initemid;
        $this->whseID = Request::$r->_whsekey;

        // if there is no valid $cny then we can not find the pref
        // this happens at least in the make process.
        $cny = GetMyCompany();
        if(!isset($this->itemDetails) && isset($cny) && $cny != '') {
            $this->itemDetails = $itemMgr->GetList(
                array(
                'selects' => array('ENABLE_LOT_CATEGORY', 'ENABLE_SERIALNO', 'ENABLE_BINS', 'ENABLE_EXPIRATION'),
                'filters' => array (array (array('ITEMID', '=', $this->itemID))),
                'donottransform' => true
                )
            );
            $this->itemDetails = $this->itemDetails[0];
        }
        $this->isLotTrackingEnabled        = (isl_strtoupper($this->itemDetails['ENABLE_LOT_CATEGORY']) == 'T') ? true : false;
        $this->isSerialTrackingEnabled    = (isl_strtoupper($this->itemDetails['ENABLE_SERIALNO']) == 'T') ? true : false;
        $this->isBinTrackingEnabled        = (isl_strtoupper($this->itemDetails['ENABLE_BINS']) == 'T') ? true : false;
        $this->hasExpirationDate        = (isl_strtoupper($this->itemDetails['ENABLE_EXPIRATION']) == 'T') ? true : false;
        
        
    }

    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @param bool $addYuiCss  include the YUI css files
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);
        $mod = Request::$r->_mod;
        $sess = Request::$r->_sess;
        $op = Request::$r->_op;
        $do = Request::$r->_do;
        $it = Request::$r->_it;
        $in_out = Request::$r->_in_out;
        $inquantity = Request::$r->_inquantity;
        //$kititems = Request::$r->_kititems;
        $parentid     = Request::$r->_parentid;
        $isreturn     = Request::$r->_isreturn;
        $isbackorder = Request::$r->_isbackorder;
        $transdocmode = Request::$r->_docmode;
        Request::$r->_transdocmode = $transdocmode;

        $listOp = GetOperationId($mod . '/lists/' . $it . '/edit');

    ?>
     <script src="../resources/js/polyfill/promise.js"></script>
     <script src="../resources/js/qrequest.js"></script>
     <script language=javascript>

     var mod  = '<?= $mod ?>';
     var sess  = '<?= $sess ?>';
     var _do  = '<?= $do ?>';
     var it  = '<?= $it ?>';
     var op  = '<?= $op ?>';
     var listOp  = '<?= $listOp ?>';
     var reStripSpaces = /^\s+(.*)\s*$/m;
     var in_out = '<?= $in_out ?>';
     var inquantity = '<?= $inquantity ?>';
     var parentid = '<?= $parentid ?>';
     var isreturn = '<?= $isreturn ?>';
     var isbackorder = '<?= $isbackorder ?>';
     var isLotTrackingEnabled = '<?= $this->isLotTrackingEnabled ?>';		
     var isSerialTrackingEnabled = '<?= $this->isSerialTrackingEnabled    ?>';
     var isBinTrackingEnabled = '<?= $this->isBinTrackingEnabled ?>';		
     var hasExpirationDate = '<?= $this->hasExpirationDate ?>';	

     function DisableFields(){
      _layer0= 'Layer0';
      _form0 = 'Layer0_form';
      page0 = GetLayerDoc('Layer0');
      multi_line_name = '';
      if(isSerialTrackingEnabled){
				numrec = inquantity;
      }else{
				numrec = page0.forms[_form0].elements['_obj__' + multi_line_name + '_numofrows_top'].value;
      }

      for (var m=0; m<numrec; m++) {
				 refcount = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__REFCOUNT'];	
			
				//fetch the refcount if any for this serial no.
				 if(refcount || isbackorder){
					 //if count > 0 ie. serial num is consumed by sales, disable line's controls
					 if(refcount.value > 0 || isbackorder){ 
						 //disable serial number
						 serialno = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__SERIALNO'];	
						serialno.disabled =true;

						 //disable lot number
						 lotno = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__LOTNO'];	
						lotno.disabled =true;

						 //disable expiration date
						 expiration = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__EXPIRATION'];	
						expiration.disabled =true;

						 //disable aisle key
						 aislekey = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__AISLEKEY'];	
						aislekey.disabled =true;

						 //disable row key
						 rowkey = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__ROWKEY'];	
						rowkey.disabled =true;

						 //disable bin key
						 binkey = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__BINKEY'];	
						binkey.disabled =true;
					 }
				 }
      }
     }

     function CheckQuantity(){
      if(in_out=='Decrease'){
				_form0 = 'Layer0_form';
				page0 = GetLayerDoc('Layer0');
				multi_line_name = '';
				numrec = page0.forms[_form0].elements['_obj__' + multi_line_name + '_numofrows_top'].value;

				for (var m=0; m<numrec; m++) {
					 qty = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__QUANTITY'];	
					 qtystore = 	page0.forms[_form0].elements['_obj__'+multi_line_name+'('+m+')__QUANTITYSTORE'];
					 if( parseInt(qty.value) > parseInt(qtystore.value)){
						 alert('Quantity can not be greater than '+qtystore.value );
						 qty.value=qtystore.value;
					 }
				}
      }
     }
     /**
      *
      * @param string   $_layer
      * @param string   $_form
      * @param string   $from
      * @param string   $rownum
      * @param int      $fieldid
      *
      */

     function AutoFill(_layer, _form, from, rownum,fieldid) {

      if (from == 'LOTNO' || from == 'EXPIRATION' || from == 'AISLEKEY' || from == 'ROWKEY' || from == 'BINKEY') {
				_form	= (_form == null) ? 0 : _form;
				_form0	= 'Layer0_form';

				page = GetLayerDoc(_layer);

				layer	= document.forms[0]._currentlayer.value;
				_layer0	= 'Layer0';

				//total number of rows
				_form0 = 'Layer0_form';
				page0 = GetLayerDoc('Layer0');
				multi_line_name = '';
				numrec = page0.forms[_form0].elements['_obj__' + multi_line_name + '_numofrows_top'].value;
				fromObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__'+from];

				for(var i = rownum; i < numrec; i++) {
					toObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+i+')__'+from];
					if(toObj.value==''){
						toObj.value = fromObj.value;
					}
				}				

				fromObj.focus();
				fromObj.select();
      }
     }

     /**
      *
      * param array    serialnoObj
      * param array    lotObj
      * param string   itemid
      * param string   whsekey
      * param string   itemlineno
      * param int      rownum
      *
      */
     function FillAisleBinRowData(serialnoObj, lotObj, itemid, whsekey, itemlineno, rownum){
      if(serialnoObj){
				serialno = serialnoObj.value;
      }else{
				serialno='';
      }

      if(lotObj){
				lotno = lotObj.value;
      }else{
				lotno = '';
      }
      var qrequest = new QRequest;
			
      var url = 'qrequest.phtml?.function=GetAisleBinRow&.handler=QRequest&.entity=documententrytrack&.sess='+sess+'&.otherparams=itemid,serialno,lotno,whsekey,itemlineno&.itemid='+escape(itemid)+'&.serialno='+escape(serialno)+'&.lotno='+escape(lotno)+'&.whsekey='+escape(whsekey)+'&.itemlineno='+escape(itemlineno);
						
      var updateFunc = "RespProcesserAisleBinRow";
      var updateArgs = "'"+rownum+"'";
			
      qrequest.quickRequest(url, updateFunc, updateArgs, true);
     }

     /**
      *
      * @param  int     $rownum
      * @param  string  $m_response
      *
      */
     function RespProcesserAisleBinRow(rownum, m_response){
      layer = document.forms[0]._currentlayer.value;
      _form = 'Layer0_form';
      page = GetLayerDoc('Layer0');
      multi_line_name = '';

      rowObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__ROWKEY'];
      aisleObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__AISLEKEY'];
      binObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__BINKEY'];
      expirationObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__EXPIRATION'];
      componentkeyObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__DOCCOMPONENTKEY'];

      nodes	 = m_response.getElementsByTagName("entrytrack");
      itemid	 = nodes.item(0).getAttribute("itemid");
      serialno = nodes.item(0).getAttribute("serialno");
      lotno	 =  nodes.item(0).getAttribute("lotno");
      whsekey  = nodes.item(0).getAttribute("whsekey");
      aislekey = nodes.item(0).getAttribute("aislekey");
      rowkey   = nodes.item(0).getAttribute("rowkey");
      binkey   = nodes.item(0).getAttribute("binkey");
      expirationdate  = nodes.item(0).getAttribute("expirationdate");
      doccomponentkey = nodes.item(0).getAttribute("doccomponentkey");
			
      if(rowObj){
				rowObj.value = rowkey;
      }
      if(aisleObj){
				aisleObj.value = aislekey;
      }
      if(binObj){
				binObj.value = binkey;
      }
      if(expirationObj){
				expirationObj.value = expirationdate;
      }
      if(componentkeyObj){
				componentkeyObj.value = doccomponentkey;
      }

     }

     /**
      * @constructor
      */
     function DisableAisleRowBinFields(){
      layer = document.forms[0]._currentlayer.value;
      _form = 'Layer0_form';
      page = GetLayerDoc('Layer0');
      multi_line_name = '';
      if(isSerialTrackingEnabled){
				numrec = inquantity;
      }else{
				numrec = page.forms[_form].elements['_obj__' + multi_line_name + '_numofrows_top'].value;
      }
      for (var rownum=0; rownum<numrec; rownum++) {
				rowObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__ROWKEY'];
				aisleObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__AISLEKEY'];
				binObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__BINKEY'];
				expirationObj = page.forms[_form].elements['_obj__'+multi_line_name+'('+rownum+')__EXPIRATION'];

				if(isSerialTrackingEnabled && isBinTrackingEnabled){
					rowObj.disabled		= true;
					aisleObj.disabled	= true;
					binObj.disabled		= true;
				}
				if(isSerialTrackingEnabled && hasExpirationDate){
					expirationObj.disabled = true;
				}
				if(isLotTrackingEnabled && hasExpirationDate){
					expirationObj.disabled = true;
				}
      }
     }

       </script>
    <?
    }

    /**
     * @param array $_layout
     *
     * @return array|null|string
     */
    function FigureOutNumOfRows($_layout) 
    { 
        $quantity = Request::$r->_inquantity;
        if($this->isSerialTrackingEnabled) {
            return $quantity;
        }else if ($this ->isLotTrackingEnabled || $this->isBinTrackingEnabled) {
            return Editor::FigureOutNumOfRows($_layout);
        } else{
            return Editor::FigureOutNumOfRows($_layout);
        }
    }


    /**
     * @param array $_params
     *
     */

    function Editor_Instantiate(&$_params) 
    {
        global $gManagerFactory;
        parent::Editor_Instantiate($_params);

        $itemid = Request::$r->_initemid;
        $whsekey = Request::$r->_whsekey;
        $itemlineno = Request::$r->_itemlineno;
        $in_out = Request::$r->_in_out;
        $docmode = Request::$r->_docmode;

        // make itemid field as readonly
        $this->MatchTemplates($_params, array('path' => 'ITEMID'), $itemfields);
        foreach ( $itemfields as $i => $x) {
            $itemfields[$i]['value'] = $itemid;
            $itemfields[$i]['readonly'] = 1;    
        }

        global $kINVid;
        //check whether enable bin is set to true in inventory setup screen. 
        GetModulePreferences($kINVid, $prefs); 

        //hide column if serialization is set to false
        if ($prefs['ENABLESERIAL']!='T' || !$this->isSerialTrackingEnabled) {
            $this->SetTrackFieldsByPath($_params, 'SERIALNO', 1, '', '', null, null);
        }else{
            $this->SetTrackFieldsByPath($_params, 'QUANTITY', 1, null, 1, 1, null);
            $this->SetTrackFieldsByPath($_params, 'SERIALNO', null, null, null, null, 1);
        }

        //hide column if Lot Tracking is set to false
        if ($prefs['ENABLELOT']!='T' || !$this->isLotTrackingEnabled) {
            $this->SetTrackFieldsByPath($_params, 'LOTNO', 1, '', '', null, null);
        }else{
            $this->SetTrackFieldsByPath($_params, 'LOTNO', null, null, null, null, 1);
        }

        //hide column if expiration tracking is set to false
        if ($prefs['ENABLE_EXPIRATION']!='T' || !$this->hasExpirationDate) {
            $this->SetTrackFieldsByPath($_params, 'EXPIRATION', 1, '', '', null, null);
        }else{
            $this->SetTrackFieldsByPath($_params, 'EXPIRATION', null, null, null, null, 1);
        }

        //hide column if Bin Tracking is set to false
        if ($prefs['ENABLEBIN']!='T' || !$this->isBinTrackingEnabled) {
            $this->SetTrackFieldsByPath($_params, 'AISLEKEY', 1, '', '', null, null);
            $this->SetTrackFieldsByPath($_params, 'ROWKEY', 1, '', '', null, null);
            $this->SetTrackFieldsByPath($_params, 'BINKEY', 1, '', '', null, null);
        }else{
            /*if there is no error restore the old values else populate the default aisle/row/bin			*/
            $haserror     = Request::$r->_errorTimeStamp;
            if(!(isset($haserror) && isl_strlen($haserror)>0)) {
                $trackMgr    = $gManagerFactory->getManager('documententrytrack');
                $query        = (BinManager::areAdvanedBinsOn()) ? 'QRY_DOCUMENTENTRYTRACK_DEFAULT_BINS_ADV' : 'QRY_DOCUMENTENTRYTRACK_DEFAULT_BINS';
                $trackDetails = $trackMgr->DoQuery($query, array($itemid,$whsekey));

                if ( ! BinManager::areAdvanedBinsOn()) {
                    $this->MatchTemplates($_params, array('path' => 'AISLEKEY'), $aislefields);
                    foreach ($aislefields as $i => $x) {
                        //$aislefields[$i]['required'] ='true';
                        if (isset($trackDetails[0]['AISLEID']) && ($docmode != 'view' && $docmode != 'edit') && $in_out == 'Increase') {
                            if ($aislefields[$i]['value'] == '') {
                                $aislefields[$i]['value'] = $trackDetails[0]['AISLEID'];
                            }
                        }
                    }

                    $this->MatchTemplates($_params, array('path' => 'ROWKEY'), $rowfields);
                    foreach ($rowfields as $i => $x) {
                        //$rowfields[$i]['required'] ='true';
                        if (isset($trackDetails[0]['ROWKEY']) && ($docmode != 'view' && $docmode != 'edit') && $in_out == 'Increase') {
                            if ($rowfields[$i]['value'] == '') {
                                $rowfields[$i]['value'] = $trackDetails[0]['ROWKEY'];
                            }
                        }
                    }
                }

                $this->MatchTemplates($_params, array('path' => 'BINKEY'), $binfields);
                foreach ( $binfields as $i => $x) {
                    //$binfields[$i]['required'] ='true';
                    if(isset($trackDetails[0]['ROWKEY']) && ($docmode!='view' && $docmode!='edit') && $in_out=='Increase') {
                        if($binfields[$i]['value'] =='') {
                            $binfields[$i]['value'] = $trackDetails[0]['BINID'];
                        }
                    }
                }
            }
        }
            
        $this->SetTrackFieldsByPath($_params, 'ITEMLINENO', null, null, $itemlineno, 1, null);
        $this->SetTrackFieldsByPath($_params, 'QUANTITYSTORE', 1, '', null, 0, null);

        //--------------------------------------------------
        $parentid = Request::$r->_parentid;
        //-------------------------------------------------
        if($parentid!='' || $in_out=='Decrease') {
            $this->ProcessDisableFields($_params);
            if($this->isSerialTrackingEnabled || $this->isLotTrackingEnabled) {
                if($this->isBinTrackingEnabled || $this->hasExpirationDate) {
                    $this->ProcessSerialTrackingFields($_params);
                }
            }
        }
    }

    /**
     * @param array $_params
     */
    function ProcessSerialTrackingFields(&$_params)
    {
        $itemlineno = Request::$r->_itemlineno;

        $this->MatchTemplates($_params, array('path' => 'AISLEKEY'), $fields);
        $this->MatchTemplates($_params, array('path' => 'ROWKEY'), $fields);
        $this->MatchTemplates($_params, array('path' => 'BINKEY'), $fields);
        $this->MatchTemplates($_params, array('path' => 'EXPIRATION'), $fields);

        foreach ( $fields as $i => $x) {
            $fields[$i]['disabled'] = true;
        }
        
        $this->MatchTemplates($_params, array('path' => 'SERIALNO'), $slno);
        $this->MatchTemplates($_params, array('path' => 'LOTNO'), $ltno);
        foreach ( $slno as $i => $x) {
            $rownum = $slno[$i]['rownum'] ?? -1;
            $slno[$i]['onchange'] = "FillAisleBinRowData(this,'', '".$this->itemID."', '".$this->whseID."', '".$itemlineno."', '".$rownum."');";
        }
        foreach ( $ltno as $i => $x) {
            $rownum = $ltno[$i]['rownum'] ?? -1;
            $ltno[$i]['onchange'] = "FillAisleBinRowData('',this, '".$this->itemID."', '".$this->whseID."', '".$itemlineno."', '".$rownum."');";
        }
    }

    /**
     * @param array $_params
     */

    function ProcessDisableFields(&$_params)
    {
        /** @noinspection PhpUndefinedVariableInspection */
        if( $docmode == 'view') {
            $serialnomode = 1;
            $lotmode=1;
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $this->SetTrackFieldsByPath($_params, 'SERIALNO', $serialnomode, null, null, null, null);
        /** @noinspection PhpUndefinedVariableInspection */
        $this->SetTrackFieldsByPath($_params, 'LOTNO', $lotmode, null, null, null, null);
        $this->SetTrackFieldsByPath($_params, 'EXPIRATION', null, null, null, null, null);
    }


    /**
     * @param array         $_params
     * @param string        $pathList
     * @param int|null      $readonly
     * @param string|null   $fullname
     * @param string|null   $value
     * @param bool|null     $hidden
     * @param bool|null     $required
     */
    function SetTrackFieldsByPath(&$_params, $pathList, $readonly, $fullname, $value, $hidden, $required) 
    {
        $this->MatchTemplates($_params, array('path' => $pathList), $fields);
        if ($fields) {
            foreach ( $fields as $k => $field) {
                if(isset($readonly)) {
                    $fields[$k]['readonly'] = $readonly;
                }
                if ( isset($fullname) ) {
                    $fields[$k]['fullname'] = $fullname;
                }
                if ( isset($value) ) {
                    $fields[$k]['value'] = $value;
                }
                if ( isset($hidden) ) {
                    $fields[$k]['hidden'] = $hidden;
                }
                if ( isset($required) ) {
                    $fields[$k]['required'] = $required;
                }
            }
        }
    }

    /**
     * @param array $_params
     */
    function SelectProcess(&$_params) 
    { 
        $this->initItemDetails();
        parent::SelectProcess($_params);
    }

    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessEditNewAction(&$_params) 
    { 
        Editor::ProcessEditNewAction($_params);
        $this->PopulateTrackingData();
        $this->state = $this->kShowNewState;
        return true;
    }

    /**
     * @param array $_params
     */
    function ProcessViewAction(&$_params) 
    {
        Editor::ProcessViewAction($_params);

        $this->PopulateTrackingData();
        $this->state = $this->kShowViewState;
    }

    /**
     *PopulateTrackingData
     */
    function PopulateTrackingData()
    {
        global $gManagerFactory;
        
        $_sess = Session::getKey();

        $in_out = Request::$r->_in_out;
        $docid = Request::$r->_docid;
        $docmode = Request::$r->_docmode;
        $haserror = Request::$r->_errorTimeStamp;
        $cny = GetMyCompany();
        $parentid = Request::$r->_parentid;

        $itemid = Request::$r->_initemid;
        $whsekey = Request::$r->_whsekey;
        $date = Request::$r->_date;
        $itemlineno = Request::$r->_itemlineno;
        $isReturn = Request::$r->_isreturn;
        
        $docentryMgr    = $gManagerFactory->getManager('documententrycost');
        $docentrytrackMgr    = $gManagerFactory->getManager('documententrytrack');

        if(isset($haserror) && isl_strlen($haserror)>0) {
            $obj =& Request::$r->GetCurrentObject();
            $aa['']= $obj[''];
            Request::$r->SetCurrentObject($aa);
        }else{
            //Parent id is set, when the document is converted another doc(which is having tracking info) 
            if($parentid!='') {
                if($isReturn) {
                    if($docmode=='view' || $docmode=='edit') {
                        $trackParams = array($_sess,$itemlineno,$itemid,$cny, $docid);
                       }else {
                        $trackParams = array($_sess,$itemlineno,$itemid,$cny,' ');
                        }
                          $trackingDetails[''] = $docentrytrackMgr->DoQuery('QRY_DOCUMENTENTRYTRACK_SELECT_SESSIONID_EDIT', $trackParams);
                          Request::$r->SetCurrentObject($trackingDetails);
                          return;
                }

                if($docmode=='view' || $docmode=='edit') {
                    $trackingDetails[''] = $docentryMgr->DoQuery('QRY_DOCUMENTENTRYCOST_SELECT_ITEMID_PARENT_EDIT', array($itemid,$whsekey,$date,$parentid,$cny,$cny,$itemid,$itemlineno,$itemid,$whsekey,$cny,$itemlineno,$docid,$cny,$itemid ,$itemlineno ,$_sess,$itemlineno,$itemid,$cny,$docid));
                }
                Request::$r->SetCurrentObject($trackingDetails);

            }elseif(($docmode=='view' || $docmode=='edit') && $in_out!='Decrease') {
                $trackingDetails[''] = $docentrytrackMgr->DoQuery('QRY_DOCUMENTENTRYTRACK_SELECT_SESSIONID_EDIT', array($_sess, $itemlineno, $itemid, $cny, $docid));
                Request::$r->SetCurrentObject($trackingDetails);
            }elseif(($docmode=='view' || $docmode=='edit') && $in_out=='Decrease') {
                if($docmode=='edit') {
                    $trackingDetails[''] = $docentryMgr->DoQuery('QRY_DOCUMENTENTRYCOST_SELECT_ITEMID_EDIT', array($_sess,$itemlineno,$itemid,$cny,$docid));
                }elseif($docmode=='view') {
                    $trackingDetails[''] = $docentrytrackMgr->DoQuery('QRY_DOCUMENTENTRYTRACK_SELECT_SESSIONID_EDIT', array($_sess,$itemlineno,$itemid,$cny,$docid));
                }
                Request::$r->SetCurrentObject($trackingDetails);
            }else{
                $trackingDetails[''] = $docentrytrackMgr->DoQuery('QRY_DOCUMENTENTRYTRACK_SELECT_SESSIONID_EDIT', array($_sess,$itemlineno,$itemid,$cny,' '));
                Request::$r->SetCurrentObject($trackingDetails);
            }
        }
    }

    /**
     * @param   array     $_params
     * @param   string    $disable
     */
    function ShowDoButtons($_params, $disable = "")
    {
        $dobutton             = $_params['dobutton'];
        $doaction             = $_params['doaction'];

        if ($dobutton) { ?>
         <INPUT id="savebuttid" type="button" name="savebutton" class="nosavehistory" value="<? echo $dobutton;  ?>"
          onclick="document.forms[0].<? echo Editor_Action ; ?>.value = '<?  echo $doaction; ?>'; if(BeforeSubmit()){ document.forms[0].submit(); }" disableonsubmit="true">
        <? 
        }
    }


    /**
     * @param array     $_fields
     * @param string    $_pos
     */
    function ShowMultilineRefresh(&$_fields, $_pos) 
    {
        if($this->isSerialTrackingEnabled) {
            $quantity         = Request::$r->_inquantity;
            ?>
          <INPUT type="hidden" name="_obj___numofrows_top" value="<? echo $quantity; ?>">
       <INPUT type="hidden" name="_obj___numofrows_bottom" value="<? echo $quantity; ?>">
            <?
            $_fields['norefreshlink'] = true;
        }
        parent::ShowMultilineRefresh($_fields, $_pos);
    }


    /**
     * @param array $_params
     *
     * @return array
     */
    function Buttons_Instantiate($_params) 
    {
        switch ($_params['state']) {
        case Editor_ShowNewState:
            $dobutton = 'Save';
            $doaction = 'create';
            break;
        case Editor_ShowEditState:
            $dobutton = 'Save';
            $doaction = 'save';
            $cancelbutton = 'Cancel';
            $cancelaction = 'cancel';
            $deliverbutton = 'Print To...';
            $deliveraction = 'deliver';
            break;
        case Editor_ShowViewState:
            $cancelbutton = 'Done';
            $cancelaction = 'cancel';
            break;
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $_params['dobutton']             = $dobutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['doaction']             = $doaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['saveandnewbutton']    = $saveandnewbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['saveandnewaction']    = $saveandnewaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['deliverbutton']         = $deliverbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['deliveraction']         = $deliveraction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['cancelbutton']         = $cancelbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['cancelaction']         = $cancelaction;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['editbutton']             = $editbutton;
        /** @noinspection PhpUndefinedVariableInspection */
        $_params['editaction']             = $editaction;
        return $_params;
    }


    /**
     * ShowGeneralHiddenFields
     */
    function ShowGeneralHiddenFields() 
    {
        parent::ShowGeneralHiddenFields(); 
        ?>
     <INPUT type="hidden" name=".inquantity" value="<? echo Request::$r->_inquantity; ?>">
     <INPUT type="hidden" name=".initemid" value="<? echo Request::$r->_initemid; ?>">
     <INPUT type="hidden" name=".whsekey" value="<? echo Request::$r->_whsekey; ?>">
     <INPUT type="hidden" name=".itemlineno" value="<? echo Request::$r->_itemlineno; ?>">
     <INPUT type="hidden" name=".in_out" value="<? echo Request::$r->_in_out; ?>">
     <INPUT type="hidden" name=".date" value="<? echo Request::$r->_date; ?>">
     <INPUT type="hidden" name=".itemtype" value="<? echo Request::$r->_itemtype; ?>">
     <INPUT type="hidden" name=".kitid" value="<? echo Request::$r->_kitid; ?>">
     <INPUT type="hidden" name=".docid" value="<? echo Request::$r->_docid; ?>">
     <INPUT type="hidden" name=".popup" value="<? echo Request::$r->_popup; ?>">
     <INPUT type="hidden" name=".parentid" value="<? echo Request::$r->_parentid; ?>">
     <INPUT type="hidden" name=".docmode" value="<? echo Request::$r->_docmode; ?>">
     <INPUT type="hidden" name=".transdocmode" value="<? echo Request::$r->_transdocmode; ?>">
     <INPUT type="hidden" name=".docparRecno" value="<? echo Request::$r->_docparRecno; ?>">
     <INPUT type="hidden" name=".isreturn" value="<? echo Request::$r->_isreturn; ?>">
     <INPUT type="hidden" name=".isbackorder" value="<? echo Request::$r->_isbackorder; ?>">
        <?
    }


    /**
     * PrintOnLoad
     */
    function PrintOnLoad() 
    { 
        $in_out = Request::$r->_in_out;

        if($in_out=='Decrease' && $this->state!='showview') {
            echo "DisableAisleRowBinFields();";
        }
        if ($this->state != 'showview') {
            echo "DisableFields();";
        }
        parent::PrintOnLoad();
    }

    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessCreateAction(&$_params) 
    {
        Editor::ProcessCreateAction($_params);
        return true;
    }

    /**
     * ShowPopupClose
     */
    function ShowPopupClose() 
    {
        global $gErr;
        //Close the window if there is no error while saving
        if (!$gErr->hasErrors()) {
            ?>
         <HTML><BODY onload="window.close();"></BODY></HTML>
            <?
        }
    }

    /**
     * @param   array   $_fields
     * @param   string  $_mode
     * @param   int     $_actualcols
     * @param   int     $line
     */
    function ShowMultiLineRow($_fields, $_mode, $_actualcols, $line = 0) 
    {
        global $kINVid;
        GetModulePreferences($kINVid, $prefs); 

        // If the serial traking is enabled all lines have to be filled in.
        if ($prefs['ENABLESERIAL'] == 'T' && $this->isSerialTrackingEnabled) {
            $quantity = Request::$r->_inquantity;

            // Modify the minimun number of lines required for the JS validation
            $_fields['minLinesRequired'] = $quantity;
        }

        parent::ShowMultiLineRow($_fields, $_mode, $_actualcols, $line);
    }

    /**
     * @param array $_params
     * @param array $_obj
     *
     * @return bool
     */
    function PrepareInputValues(&$_params, &$_obj)
    {
        global $gManagerFactory, $gErr;
        $entityMgr = $gManagerFactory->getManager($_params['entity']);
        $object = $entityMgr->_schemas[$_params['entity']]['basefieldinfo'];
        $ok = true;
        
        foreach ($object as $fldinfo) 
        {
            if (is_array($fldinfo) && $fldinfo['type']['ptype'] == 'date') { 
                foreach($_obj[''] as $key => $value)
                {
                    if($value[$fldinfo['path']] != '') {
                        if (!ValidateInputDate($value[$fldinfo['path']])) {
                            $ok = false;
                            $gErr->addIAError(
                                'INV-0453', __FILE__.":".__LINE__,
                                "The date ".$fldinfo['path']." '".$value[$fldinfo['path']]."' is invalid",
                                ['FLDINFO_PATH' => $fldinfo['path'], 'VALUE_FLDINFO_PATH' => $value[$fldinfo['path']]]
                            );
                        }
                    }
                    $_obj[''][$key][$fldinfo['path']] = FormatDateForStorage($value[$fldinfo['path']]);
                }
            }
        }
    
        return $ok;
    }

}
