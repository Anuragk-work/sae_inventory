<?

// TODO: I think this file is obsolete

import('Editor');

define("AISLEINFO_TAB", 1);
define("ROWINFO_TAB",  2);
define("BININFO_TAB", 3);

/**
 * Class WarehouseEditor
 */
class WarehouseEditor extends Editor
{
    /**
     *
     */
    function ShowPopupClose() 
    {
        $obj =& Request::$r->GetCurrentObject();
        $key = $obj['LOCATIONID'].'--'.$obj['NAME'];
        //$key = addslashes($this->getEntityMgr()->GetKeyValue($obj));
        $appendAutoFillData = Request::$r->_appendnew;
        list($whid) = explode('--', $key);
        if ($appendAutoFillData) {
            $onload = "window.opener.AppendWhseData('$key');";
        }
        ?>
     <HTML>
        <? $this->showScripts();?>

     <BODY onload="<?= /** @noinspection PhpUndefinedVariableInspection */
     $onload?>SetField('<? echo $whid; ?>'); "></BODY></HTML>
        <?
    }


    /**
     * @param bool $addYuiCss
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);
        $_sess = Session::getKey();
        ?>
     <script src="../resources/js/polyfill/promise.js"></script>
     <script src="../resources/js/qrequest.js"></script>
     <SCRIPT language=javascript>
     <!--
     var tocheck = '<? echo $this->_params['entity']; ?>';
     var sess = escape('<?echo $_sess;?>');

     function Aisle_Bin_Row_Fetch(id, from) {
		    var strLoc = "aisle_row_bin_fetch.phtml?.sess="+sess+"&.id="+escape(id)+"&.from="+escape(from);
		    output = baseLoadXMLHTTP(strLoc,true);
		    nodes = output.getElementsByTagName("rec");
      newId = nodes.item(0).getAttribute("id");

      if (newId) {
				desc = nodes.item(0).getAttribute("desc");
				Append_Aisle_Row_Bin_Data(newId, desc, from);
				return AutoFillLookUpID(newId, from);
      }
     }

     function Append_Aisle_Row_Bin_Data(ID, Desc, from) {
      var newRec = Array(ID, Desc);
      if(from == 'AISLE') {
				aisledensearr[aisledensearr.length] = newRec;
      }else if(from == 'ROW'){
				rowdensearr[rowdensearr.length] = newRec;
      }else if(from == 'BIN'){
				bindensearr[bindensearr.length] = newRec;
      }
     }

     function AutoFill(_layer, _form, from, rownum,fieldid) {
      _form = (_form == null) ? 0 : _form;
      page = GetLayerDoc(_layer);
      layer = document.forms[0]._currentlayer.value;

      AisleId = page.forms[_form].elements['_obj__AISLE_INFO('+rownum+')__AISLEID'];
      AisleDesc =  page.forms[_form].elements['_obj__AISLE_INFO('+rownum+')__AISLE__AISLEDESC'];

      RowKey = page.forms[_form].elements['_obj__ROW_INFO('+rownum+')__ROWKEY'];
      RowDesc =  page.forms[_form].elements['_obj__ROW_INFO('+rownum+')__ICROW__ROWDESC'];

      BinId = page.forms[_form].elements['_obj__BIN_INFO('+rownum+')__BINID'];
      BinDesc =  page.forms[_form].elements['_obj__BIN_INFO('+rownum+')__BIN__BINDESC'];
      //BinDesc.disabled = true;

      if (from == 'AISLEID') {
				if(AisleId.value == ''){ 
					AisleDesc.value='';
					return;
				}
				rec = AutoFillLookUpID(AisleId.value, 'AISLE');
				if (rec != null ){
					AisleDesc.value = rec[1];
				}else{
					rec = Aisle_Bin_Row_Fetch(AisleId.value, 'AISLE');
					if(rec != null ) {
						AisleDesc.value = rec[1];
					}
				}
      }else if (from == 'ROWKEY') {
				if(RowKey.value == ''){ 
					RowDesc.value='';
					return;
				}
				rec = AutoFillLookUpID(RowKey.value, 'ROW');
				if (rec != null ){
					RowDesc.value = rec[1];
				} else {
					rec = Aisle_Bin_Row_Fetch(RowKey.value, 'ROW');
					if(rec != null ) {
						RowDesc.value = rec[1];
					}
				}

      }else if (from == 'BINID') {
				if(BinId.value == ''){ 
					BinDesc.value='';
					return;
				}
				rec = AutoFillLookUpID(BinId.value, 'BIN');
				if(rec != null) {
					BinDesc.value = rec[1];
				}else {
					rec = Aisle_Bin_Row_Fetch(BinId.value, 'BIN');
					if(rec != null ) {
						BinDesc.value = rec[1];
					}
				}
      }
     }

     function AutoFillLookUpID(id, from) {
      var rec;
      var index;
			
      if(from == 'AISLE'){
				numRec = aisledensearr.length;
				for (i=0; i<numRec; i++) {
					if (aisledensearr[i] != null && aisledensearr[i][0] == id) {
						index = i;
						break;
					}
				}
				if (index!=null) {
					rec = aisledensearr[index];
				}
      }else if(from == 'BIN'){
				numRec = bindensearr.length;
				for (i=0; i<numRec; i++) {
					if (bindensearr[i] != null && bindensearr[i][0] == id) {
						index = i;
						break;
					}
				}
				if (index!=null) {
					rec = bindensearr[index];
				}
      } else if(from == 'ROW'){
				numRec = rowdensearr.length;
				for (i=0; i<numRec; i++) {
					if (rowdensearr[i] != null && rowdensearr[i][0] == id) {
						index = i;
						break;
					}
				}
				if (index!=null) {
					rec = rowdensearr[index];
				}
      }

      return rec;
     }

     // -->
     </SCRIPT>
     <script src="../resources/js/apar.js"></script>
        <?
    }


    /**
     * @return array
     */
    function CollectAutoFillData() 
    {
        global $gManagerFactory;

        $docMgr        = $gManagerFactory->getManager('document');

        // ------- AISLES
        $myqry = array (
        'QUERY' => "select 
					chr('39')|| replace(aisleid,chr('39'),'\'||chr('39'))||chr('39')||','||
					chr('39')|| replace(aisledesc,chr('39'),'\'||chr('39'))||chr('39') 
					from icaisle where icaisle.cny# = ? order by aisleid",
        'ARGTYPES'    => array ('integer'),
        );
        $jsAisles = $docMgr->_QM->DoCustomQuery($myqry, array());
        foreach ($jsAisles as $jsAisle) {
            $items['AISLES'][] = '['.$jsAisle[0].']';
        }

        // ------ BINS
        $myqry = array (
        'QUERY' => "select 
					chr('39')|| replace(binid,chr('39'),'\'||chr('39'))||chr('39')||','||
					chr('39')|| replace(bindesc,chr('39'),'\'||chr('39'))||chr('39') 
					from icbin where icbin.cny# = ? order by binid",
        'ARGTYPES'    => array ('integer'),
        );
        $jsBins = $docMgr->_QM->DoCustomQuery($myqry, array());
        foreach ($jsBins as $jsBin) {
            $items['BINS'][] = '['.$jsBin[0].']';
        }
            
        // ------ ROWS
        $myqry = array (
        'QUERY' => "select 
					chr('39')|| replace(rowkey,chr('39'),'\'||chr('39'))||chr('39')||','||
					chr('39')|| replace(rowdesc,chr('39'),'\'||chr('39'))||chr('39')
					from icrow where icrow.cny# = ? order by rowkey",
        'ARGTYPES'    => array ('integer'),
        );
        $jsRows = $docMgr->_QM->DoCustomQuery($myqry, array());
        foreach ($jsRows as $jsRow) {
            $items['ROWS'][] = '['.$jsRow[0].']';
        }

        /** @noinspection PhpUndefinedVariableInspection */
        return($items);
    }


    /**
     *
     */
    function ShowHiddenFields() 
    {
        Editor::ShowHiddenFields();
        
        $aisle_bin_row_data = $this->CollectAutoFillData();

        $aisles = $aisle_bin_row_data['AISLES'];
        $bins = $aisle_bin_row_data['BINS'];
        $rows = $aisle_bin_row_data['ROWS'];

        $aisles = '['.join(',', $aisles).']';
        $bins = '['.join(',', $bins).']';
        $rows = '['.join(',', $rows).']';

        $js_aisles= "<SCRIPT> aisledensearr = ".$aisles."; </SCRIPT>";
        $js_bins= "<SCRIPT> bindensearr = ".$bins."; </SCRIPT>";
        $js_rows = "<SCRIPT> rowdensearr = ".$rows."; </SCRIPT>";

        echo $js_aisles;
        echo $js_bins;
        echo $js_rows;

    }


    /**
     *
     */
    function ShowGeneralHiddenFields() 
    {
        parent::ShowGeneralHiddenFields();

        ?><INPUT type="hidden" name=".appendnew" value="<? echo Request::$r->_appendnew; ?>"><?
    }


    /**
     * @param array $_params
     */
    function Editor_Instantiate(&$_params) 
    {
        global $kINVid;

        parent::Editor_Instantiate($_params);
        
        // For an atlas (Multi-currency, Multi Entity) company these validations are very important.
        // For atlas, user has to associate a warehouse to a parent location and which is always associated to an entity. This is to derive the base currency of the warehouse 
        // when we create transactions by that warehouse.	
        // One other validation is to make sure the same warehouse is not modified to point to many entities and has transactions across the entities. This would messup the costing by warehouse etc.
        if (IsMCMESubscribed()) {
            $obj = Request::$r->GetCurrentObject();
            $whseHasTransactions = $this->getEntityMgr()->WarehouseHasTransactions($obj['LOCATIONID']);
            $this->MatchTemplates($_params, array('path' => 'LOC.LOCATIONID'), $ifields);
            foreach ( $ifields as $i => $field) {

                // check if warehouse has no transactions (or) they have not yet selected a parent location, then force them to select. 
                if (!$whseHasTransactions || !$obj['LOC']['LOCATIONID']) {
                    $ifields[$i]['required'] = true;
                } else {
                    $ifields[$i]['readonly'] = true;
                }
            }
        } 
        
        
        //check whether enable bin is set to true in inventory setup screen. 
        GetModulePreferences($kINVid, $prefs);
        
        //Show bins option only if enable bin is set to true in inventory setup screen.
        if($prefs['ENABLEBIN']=='T') {
            //$this->ProcessSetTabs($_params);
        }else{
            $this->ProcessHideControls($_params);
        }
    }


    /**
     * this function hide controls related to bins if enable bin is false
     *
     * @param array $_params
     *
     * @return array
     */
    function ProcessHideControls(&$_params)
    {
        //enable bin is false, Hide all tabs and the checkboxes for aisle,row,bin

        unset($_params['layout']['pages'][AISLEINFO_TAB]);
        unset($_params['layout']['pages'][ROWINFO_TAB]);
        unset($_params['layout']['pages'][BININFO_TAB]);

        return $_params;
    }


    /**
     * To sort the tab order in alphabetic order and to avoid any UI problem of tabs
     *
     */
    function ShowLayout() 
    { 
        asort($this->_params['layout']['pages']);
        reset($this->_params['layout']['pages']);
        $this->_params['layout']['pages'] = array_values($this->_params['layout']['pages']);
        parent::ShowLayout();
    }

    /**
     * @return WarehouseManager
     */
    public function getEntityMgr()
    {
        /** @var WarehouseManager $whseMgr */
        $whseMgr = $this->getEntityMgr();
        return $whseMgr;
    }


}

