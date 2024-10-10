<?
define('BUILD_KIT', 'Build Kits');
define('DIS_KIT', 'Disassemble Kits');

/**
 * Class DocumentPicker
 */
class DocumentPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'document',
            'fields'        =>  array('DOCID', 'WHENCREATED','NOTE','CUSTVENDID'),
            'pickfield'        =>  'DOCID',
            'helpfile'        => 'Locations_Lister' // NOT SURE ABOUT THIS ONE
            )
        );
    }

    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        global $gManagerFactory;

        $docID         = Request::$r->_dt;
        $entID        = Request::$r->_id;
        $mod		= Request::$r->_cmod;
        $copymode    = Request::$r->_mode;
        $report     = Request::$r->_it;

        if (!isset($mod) || $mod == '') {
            global $gElementMap;
            $op = Request::$r->_op;
            $entitymod = $gElementMap[$op]['module'];
            if ($entitymod) {
                $mod = $entitymod;
            }
        }

        $entityID = '';
        if ($mod != 'inv' && $entID) {
            $enttype         = ($mod == 'so') ? 'customer' : 'vendor';
            $entityMgr         = $gManagerFactory->getManager($enttype);
            $raw             = $entityMgr->GetRaw($entID);
            $entityID         = $raw[0]['ENTITY'];
        }

        $initial = parent::BuildQuerySpec();
        $docparMgr = $gManagerFactory->getManager('documentparams');

        global $_userid;
        $arrExplode = explode('@', $_userid);
        $userkey = array_shift($arrExplode);

        if ($copymode == 'Update') {
            $valarray = array ('so' => 'S', 'po' => 'P', 'inv' => 'I');
            $spt = $valarray[$mod];
            $docs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_FROM', array($spt,$docID)); 
            $docs = filterDocsForUserType($docs);
        } else {
            if ( !in_array($mod, array('so','po','inv')) ) {
                logToFileWarning("$mod is not mapped to TD type. Default of 'S' will be used in this case");
                $mod = 'so';
            }
            $docs = GetDocumentMenuList($mod);

            //Dont show build kits and disassemble kits in the common lister -- mmahur
            foreach($docs as $key => $val){
                if ($val['DOCID'] == BUILD_KIT || $val['DOCID'] == DIS_KIT) {
                    unset($docs[$key]);
                }
            }

        }

        // Filter the result.
        $docs = upermFilterResult($docs, $userkey);

        if ($entID) {
            $initial['filters'][0][] = array ( $mod . 'document.entity', '=', $entityID);
        }
        if($mod != '') {
            if ($docs) {
                $docArray = array();
                foreach ($docs as $doc) {
                    $docArray[] = $doc['DOCID'];
                }
                if ($copymode == 'Update') {
                    // get only Pending/Partially connvertd documents
                    $docStatesIn = "in('O', 'P', 'B')";
                    //if reverse conversion feature is enabled then include converted doc as well
                    if($mod == 'po'){
                        $docMgr = Globals::$g->gManagerFactory->getManager('document');
                        if($docMgr->isPOReverseConversionAllowed()){
                            $docStatesIn = "in('O', 'P', 'B', 'C')";
                        }
                    }
                    $initial['filters'][0][] = array ($mod.'document.state', $docStatesIn, "");
                }
                $initial['filters'][0][] = array ('documentparams.docid','in',$docArray);
            }
            else {
                $initial['filters'][0][] = array ('documentparams.record#','=',"-1");
            }
            if(in_array($mod,['so','po']) && isset($this->path) && $this->path != ""){
                $pathArr = explode(".", $this->path);
                $fieldName = end($pathArr);
                if($fieldName == "RELATEDDOCNO"){ //Report filter
                    $initial['filters'][0][] = array ('documentparams.enabledocchange','=',"Enable Change");
                }
            }
        }else{
            $cny = GetMyCompany();
            if (!$report == 'pickinglist') {
                $subquery = array("
					select distinct dh.docid 
					from 
						dochdr dh, docentry de, docentrycost dc, docpar dp
					where
						 dh.cny# = $cny and
						 de.cny# = $cny and
						 dc.cny# = $cny and
						 dp.cny# = $cny and
						 dp.record# = dh.docparkey and
						 dh.record# = de.dochdrkey and 
						 de.record# = dc.docentrykey and
						 dc.in_out = 'O' and
						 dp.in_out = 'D' and
						 dp.UPDINV != 'F'"
                );
            }else{
                $subquery = array("
					select distinct dh.docid 
					from 
						dochdr dh, docentry de, docentrycost dc, docpar dp,docpartotals dpt,ictotal tot
					where
						 dh.cny# = $cny and
						 de.cny# = $cny and
						 dc.cny# = $cny and
						 dp.cny# = $cny and
						 dpt.cny#= $cny and
                         tot.cny#= $cny and
						 dp.record# = dh.docparkey and
						 dh.record# = de.dochdrkey and 
						 de.record# = dc.docentrykey and
						 dc.in_out = 'O' and
						 dp.in_out = 'D' and
						 dp.UPDINV != 'F' and
					     dpt.docparkey = dp.record# and
						 dpt.totalkey = tot.record# and 
						 tot.name = 'ONHAND'"
                );
            }
            $initial['filters'][0][] = array('DOCID', 'INSUBQUERY', $subquery);
        }
        return $initial;
    }

    /**
     * BuildTable
     */
    function BuildTable() 
    {

        $this->Init();

        //To Show Private records in the picker
        if(Request::$r->_showprivate ) {
            SetReportViewContext();
        }

        $querySpec = $this->BuildQuerySpec();
        $resultCount = $this->getEntityMgr()->GetCount($querySpec);

        //echo $resultCount;
        $this->SetDomainSize($resultCount);
        $table = $this->getEntityMgr()->GetList($querySpec);
        if ($this->params['_queryfromend']) {
            $table = array_reverse($table);
        }

        $mod = $this->entityMgr->mod;
        $docviewop = GetOperationId("$mod/lists/$this->entity/view");
        for ($i = 0; $i < count($table); $i++) {
            $table[$i]["'LINES'"] = '<a href="#" onclick="toggle(\'blah'.$i.'\', this)">[+]</a>';
            $rowDocid = $table[$i]['DOCID'];
            $table[$i]['DOCUMENTID'] = $rowDocid;
            $url = URLEncryption::buildUrl("editor.phtml",
                [
                    '.mod' => $mod,
                    '.op' => $docviewop,
                    '.r' => urlencode($rowDocid),
                    '.sess' => Request::$r->_sess,
                    '.popup' => 1,
                ]);
            $table[$i]['DOCID'] = "<a href=\"javascript:Launch('$url','mywindow',600,400)\">" . $rowDocid . "</a>";
        }
        $this->table = $table;
    }

    /**
     * @param int $i
     * @param string $refr
     *
     * @return string
     */
    function calcSelectUrl($i, $refr = "")
    {
        $params = $this->_params;
        $table = $this->table;
        $text = $params['_selectbutton'];
        $refr = $refr ? '1' : '';

        //  Properly encode to JS-ready (e.g. UTF-8 chars).
        $pick = (!empty($table[$i]['DOCUMENTID'] ?? '')) ? isl_str_to_js($table[$i]['DOCUMENTID']) : isl_str_to_js($table[$i]['DOCID']);
        $result = "<a id=\"select\" href=\"javascript:SetField('" . $pick . "', '', '$refr')\" >" . $text . "</a>";

        return $result;
    }

    /**
     * @return string
     */

    function genGlobs()    
    {
        $dt = Request::$r->_dt;
        $entID        = Request::$r->_id;
        $mod		 = Request::$r->_cmod;
        $copymode    = Request::$r->_mode;

        $ret = parent::genGlobs();
        $ret .= "<g name='.dt'>" . $dt. "</g>";
        $ret .= "<g name='.id'>" . $entID. "</g>";
        $ret .= "<g name='.cmod'>" . $mod. "</g>";
        $ret .= "<g name='.mode'>" . $copymode. "</g>";
        $ret .= "<g name='.it'>" . $this->_params['_entity'] . "</g>";

        if(Request::$r->_changeorder){
            $changeorder    = Request::$r->_changeorder;
            $ret .= "<g name='.changeorder'>" . $changeorder . "</g>";
        }

        return $ret;
    }


    /**
     * Method called on construct
     */
    protected function changeOrderConstruct(){
        if(Request::$r->_changeorder){
            $this->_params['nosysview'] = false;
            $this->_params['userviews'] = CustomListerManager::GetListerViews($this->entity, $this->doctype);
            $this->_params['globalviews'] = IACustomReportManager::getListerViews($this->entity, $this->doctype);
        }
    }
}
