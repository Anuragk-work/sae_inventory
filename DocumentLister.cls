<?
/**
 * class DocumentLister extends NLister
 */
define('BUILD_KIT', 'Build Kits');
define('DIS_KIT', 'Disassemble Kits');

/**
 * Class DocumentLister
 */
class DocumentLister extends NLister
{

    /** @var string[][] $docparCache */
    protected $docparCache = array();
    
    /** @var array $upermAllowedDocsCache */
    var $upermAllowedDocsCache = array();

    /** @var array $docHdrTotalCache */
    var $docHdrTotalCache = array();

    /** @var array $docPars */
    var $docPars  = array();

    /** @var string[] $docHdrKeys */
    var $docHdrKeys = array();

    /** @var string $mod */
    var $mod = '';

    /** @var  string $_deletePolicy */
    protected $_deletePolicy;

    /** @var  string $_editPolicy */
    protected $_editPolicy;

    /** @var string $_createPolicy */
    protected $_createPolicy;

    /** @var string $_creationRule */
    protected $_creationRule;

    /** @var bool $approvePurchasesLister */
    var $approvePurchasesLister = false;

    /**
     * @var bool $isReverseConversionEnabled
     */
    private $isReverseConversionEnabled = false;

    /**
     * User info specific tokens
     * @var string[]
     */
    protected const additionalTokens = [
        'IA.PRINT',
        'IA.CONVERT_BY_LINE',
        'IA.CONVERT',
        'IA.PENDING',
        'IA.PARTIALLY_CONVERTED',
        'IA.PARTIALLY_CONVERTED_BY_LINE',
        'IA.CONVERTED'
        ];

    /**
     * @param array $_params
     */
    function __construct($_params = [])
    {
        global $gManagerFactory;
        $docMgr = $gManagerFactory->getManager('document');

        $this->mod = Request::$r->_mod;
        $this->doctype = Request::$r->_dt;
        if ($this->_createPolicy == 'C') {
            $_params['disableadd'] = true;
        }
        // Remove the Add button if the creation rule is set to 'F'
        if ('F' === $this->_creationRule) {
            $_params['disableadd'] = true;
        }

        $_params['showDateFilter'] = true;
        $_params['dateFilterField'] = 'WHENCREATED';

        $this->additionalTokens = array_merge($this->additionalTokens, self::additionalTokens);

        parent::__construct($_params);

        $ok = $docMgr->IsTranAllowedforUser();
        if (!$ok) {
            include 'popuperror.phtml';
            exit();
        }
    }

    /**
     * ShowPreListerEditorInfo
     */
      function ShowPreListerEditorInfo()
    {
        // Does nothing allow to override
        $msg = Request::$r->_msg;
        if ($msg) {
        ?>
         <center>
         <table border="0" cellpadding="1" cellspacing="0" width="70%" bgcolor="#999966">
          <tr>
        <td valign="top">

        <table border="0" cellpadding="4" cellspacing="0" width="100%" bgcolor="#FFFFCC">
         <tr>
          <td valign="middle" align="center">
          <font face="Verdana, Arial, Helvetica" size="2"><b><? echo $msg; ?></b></font>
          </td>
         </tr>
        </table>

        </td>
       </tr>
         </table>
         </center>
        <?
        }
    }

    /**
     * @param string $documentType
     */
    function GetEditDeletePolicy($documentType)
    {
        global $gManagerFactory;
        /** @var DocumentParamsManager $docparMgr */
        $docparMgr = $gManagerFactory->getManager($this->mod . 'documentparams');

        $docpar['CREATION_RULE'] = $docparMgr->getCreationRuleForDocid($documentType);

        $policy = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_GET_EDITDEL_POLICY', array ($documentType));
        $this->_deletePolicy = $policy[0]['DELTYPE'];
        $this->_editPolicy = $policy[0]['EDITTYPE'];
        $this->_createPolicy = $policy[0]['CREATETYPE'];
        $this->_creationRule = $docpar['CREATION_RULE'];
        
        $this->checkForAdditionalPolicy($policy[0]['UPDGL'], $this->_editPolicy, $this->_deletePolicy);
    }

    /**
     * @param string $updGL
     * @param string $editPolicy
     * @param string $deletePolicy
     */
    protected function checkForAdditionalPolicy($updGL, &$editPolicy, &$deletePolicy)
    {
        $kAFRid = Globals::$g->kAFRid;
        if ( IsModuleIdInstalled($kAFRid) ) {
            if ( $updGL !== 'N' ) {
                $pref = GetPreferenceForProperty($kAFRid, 'DISABLEEDIT');
                if ( $pref === "true" ) {
                    $editPolicy = 'D';
                }

                $pref = GetPreferenceForProperty($kAFRid, 'DISABLEDELETE');
                if ( $pref === "true" ) {
                    $deletePolicy = 'D';
                }
            }
        }
    }

    /**
     * @return string
     */
    function calcAddUrl()
    {
        $p = &$this->_params; //???

        $dt = Request::$r->_dt;
        $schopkey = Request::$r->_schopkey;
        $op = $p['_op']['create'];

        $text =  $p['_addbutton'];
        $dst = $this->calcAddDst();
        $tip = 'Add New Item';
        $do = 'create';

        $ret =     "<a href=\"" .
        $this->U($dst, ".do=$do&.schopkey=$schopkey&.dt=" . isl_trim($dt) . "&.r=&.op=$op&add=Add&_action=new", $this->LCALL) ."\" " .
        HREFUpdateStatus($tip) . ">" .
        $text .
        "</a>";

        return $ret;
    }

    /**
     * @return string
     */
    function genGlobs()
    {
        $dt = Request::$r->_dt;
        $schopkey = Request::$r->_schopkey;
        $ret = parent::genGlobs();
        $ret .= "<g name='.dt'>" . $dt. "</g>";
        $ret .= "<g name='.schopkey'>" . $schopkey. "</g>";
        return $ret;
    }

    /**
     * @param int   $i
     * @param array $vals
     *
     * @return array|string
     */
    function calcEditUrlParms($i, $vals)
    {
        $table = &$this->table;
        // Ignore items with the No Edit ('N') policy
        if ($this->_editPolicy == 'N') {
            return [];
        }
        // Ignore items with the Edit in Draft Only ('D') policy that aren't drafts
        else if ($this->_editPolicy == 'D' && $this->values[$i]['STATE'] != 'I') {
            return [];
        }
        return parent::calcEditUrlParms($i, $vals);
    }

    /**
     * @return array
     */
    function BuildQuerySpec()
    {
        $dt = Request::$r->_dt;
        $schopkey = Request::$r->_schopkey;

        $batch = Request::$r->_batch;

        $initial = parent::BuildQuerySpec();

        if ($dt) {
            $initial['filters'][0][] = array ( 'documentparams.docid', '=', $dt);
        }else{
            // if common lister is selected
            $permittedDocs = GetDocumentMenuList($this->mod, "", $this->approvePurchasesLister, !$this->_params['_showstatus']);

            $initial['filters'][0][] = array('documentparams.docid', 'IN', array_keys(AssociateArray($permittedDocs, 'DOCID')));
        }

        if (isset($schopkey) && $schopkey!='') {
            $initial['filters'][0][] = array ( $this->mod.'document.schopkey', '=', $schopkey);
        }
        //Set Report View Context for MEGA downward
        if($this->showPrivate ) {
            SetReportViewContext();
        }

        //Reset ViewContext to Transaction following MEGA downward query
        if($this->showPrivate ) {
            SetTransactionViewContext();
        }

        // Unless this is a Build/Disassemble Kit lister, explicitly avoid listing build/disassemble objects.
        if (!in_array($dt, array(BUILD_KIT, DIS_KIT))) {
            $initial['filters'][0][] = array(
            'documentparams.docid', 'NOT IN', array(BUILD_KIT, DIS_KIT));
        }

        if ($batch) {
            $initial['filters'][0][] = array('INVBATCHKEY', '=', $batch, 'r');
            $initial['filters'][0][] = array('ADDGLBATCHKEY', '=', $batch, 'r');
            $initial['filters'][0][] = array('PRINVBATCHKEY', '=', $batch);
        }

        if (!in_array('RECORDNO', $initial['selects'])) {
            $initial['selects'][] = 'RECORDNO';
        }

        return $initial;
    }

    /**
     * BuildTable
     */
    function BuildTable()
    {

        $dt = Request::$r->_dt;

        $docMGR = Globals::$g->gManagerFactory->getManager('document');
        $this->isReverseConversionEnabled = $docMGR->isReverseConversionAllowed($this->mod);

        // This is NOT KOSHER, but I daren't change NLister or Lister, so here I trim $this->additionalTokens....
        $additionalTokens = array_unique($this->additionalTokens);
        $this->additionalTokens = [];
        foreach ($additionalTokens as $token) {
            if (is_array($token)) {
                $this->additionalTokens[] = $token;     // save it
            } else if ( (! empty($token)) && ( is_string($token))) {
                if (strpos($token, '.') !== false) {  // may not be IA. but some other leading thingy....
                    $this->additionalTokens[] = $token;     // save it
                }
            }
        }

        NLister::BuildTable();
        $id = GetOperationId($this->mod . '/lists/' . $this->mod . 'document/view');

        $tablecnt = count($this->table);
        for ( $i=0; $i < $tablecnt;  $i++ ) {
            if (!in_array($this->table[$i]['DOCPARID'], $this->docPars)) {
                $this->docPars[] = $this->table[$i]['DOCPARID'];
            }

            // We need a cache of dochdrkeys for checking if the line item has a salescontract used, to display the convert link.
            if (!in_array($this->table[$i]['RECORDNO'], $this->docHdrKeys)) {
                $this->docHdrKeys[] = $this->table[$i]['RECORDNO'];
            }
        }
        
        // Any docpar related information, please use this API
        $this->setDocParCache();

        $hasTotalColumns = [];
        if (count($this->docHdrKeys) > 0) {
            $hasTotalColumns = array_intersect(array('TOTAL','TRX_TOTAL','SUBTOTAL','TRX_SUBTOTAL'), $this->_params['_fields']);
            if (!empty($hasTotalColumns)) {
                $this->SetDocumentTotals();
            }
        }

        if (count($this->docHdrKeys) > 0) {
            $this->SetDocumentRowAdditionalInfo();
        }

        $flds = $this->_params['_fields'];
        $fldnames = $this->_params['_fieldlabels'];

        for ($i = 0; $i < count($this->table); $i++) {
            $rec = $this->table[$i];

            $contextLocation = GetContextLocation();
            $owner = $this->GetObjectOwnership($i);
            $ownerloc = $this->GetObjectOwnerLocation($i);

            if ($dt == BUILD_KIT) {
                if ($rec['STATE'] == StkitDocumentLister::IA_CONVERTED) {
                    $this->table[$i]['STATE'] = GT($this->textMap, StkitDocumentLister::IA_DISASSEMBLED);
                }
                if ($rec['STATE'] == StkitDocumentLister::IA_PENDING) {
                    $this->table[$i]['STATE'] = GT($this->textMap, StkitDocumentLister::IA_BUILT);
                }
            }elseif ($dt == DIS_KIT) {
                if ($rec['STATE'] == StkitDocumentLister::IA_PENDING) {
                    $this->table[$i]['STATE'] = GT($this->textMap, StkitDocumentLister::IA_DISASSEMBLED);
                }
            }
            $this->table[$i]['STATETEMP'] = $this->table[$i]['STATE'];
            $this->table[$i]["'CONVERT'"] = $this->getConvertURL($this->table[$i], $contextLocation, $owner, $ownerloc);

            $this->_calcPrintURL($i, $id, $contextLocation, $owner, $ownerloc);

            $this->_calcHistoryURL($i, $id, $this->mod);

            foreach ( $hasTotalColumns as $total_column) {
                $this->table[$i][$total_column] = $this->docHdrTotalCache[$this->table[$i]['RECORDNO']][$total_column];
            }
        }
        $flds[] = 'VIEWPDF';
        $fldnames[] = '';
        $this->SetOutputFields($flds, $fldnames);

    }

    /**
     * setting docpar cache
     */
    protected function setDocParCache()
    {
        if(count($this->docPars) > 0) {
            $stmt[0] = "select record#, docclass, docid, enableschedule, enablerevrec, psaimport, category, userperm, 
                        description, enablepayments, deltype, edittype, create_type createtype, updgl 
                        from docpar where cny# = :1 and latestversionkey is null";
            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, $this->docPars, " and docid ");
            $res = QueryResult($stmt);
            foreach ( $res as $value) {
                $this->docparCache[$value['DOCID']] = $value;
            }
        }
    }
    /**
     * @param int $i index into lister table of displaying objects
    
     * @return bool true if the object at index $i can be edited
     */
    protected function canEdit($i)
    {
        $ok = parent::canEdit($i);
        if ($ok) {
            $doctype = $this->values[$i]['DOCPARID'];
            $editPol = $this->docparCache[$doctype]['EDITTYPE'];
            $delPol = $this->docparCache[$doctype]['DELTYPE'];
            $this->checkForAdditionalPolicy($this->docparCache[$doctype]['UPDGL'], $editPol, $delPol);
            if ($editPol === 'N') {
                $ok = false;
            } else if ($editPol === 'D') {
                $ok = ($this->values[$i]['STATE'] == 'I');
            }
        }

        return $ok;
    }
    
    /**
     *
     * @param int $i index into lister table of displaying objects
     *
     * @return bool true if the object at index $i can be deleted
     */
    protected function canDelete($i)
    {
        $ok = parent::canDelete($i);
        if ($ok) {
            $doctype = $this->values[$i]['DOCPARID'];
            $editPol = $this->docparCache[$doctype]['EDITTYPE'];
            $delPol = $this->docparCache[$doctype]['DELTYPE'];
            $this->checkForAdditionalPolicy($this->docparCache[$doctype]['UPDGL'], $editPol, $delPol);
            if ($delPol === 'N') {
                $ok = false;
            } else if ($delPol === 'D') {
                $ok = ($this->values[$i]['STATE'] == 'I');
            }
        }

        return $ok;
    }

    /**
     * @param array  $record
     * @param int    $contextLocation
     * @param string $owner
     * @param string $ownerloc
     *
     * @return string
     */
    protected function getConvertURL($record, $contextLocation,
        /** @noinspection PhpUnusedParameterInspection */ $owner, $ownerloc)
    {
        //From entity don't allow conversion unless the entity owns the document
        if (IsMultiEntityCompany() && $contextLocation != '' && $contextLocation != $record['ENTITY#']) {
            $convertUrl = "";
        } else if (I18N::getSingleToken( $record['STATE']) != I18N::getSingleToken('IA.PENDING')
            && I18N::getSingleToken($record['STATE']) != I18N::getSingleToken('IA.PARTIALLY_CONVERTED')
            && I18N::getSingleToken($record['STATE']) != I18N::getSingleToken('IA.PARTIALLY_CONVERTED_BY_LINE')
            && !$this->isReverseConversionEnabled) {
            $convertUrl = "";
        } else {
            $convertLinkTxt = I18N::getSingleToken('IA.CONVERT');

            $quotedId = XMLUtils::xmlSpecialChars(str_replace('\'', '\\\'', $record['DOCID']));
            $convertUrl = '<a href="#" onclick="showMenu(event, \'' . $record['DOCPARID'] . '\', \''
                . $quotedId . '\',\'' . $ownerloc . '\', this); return false;"  ONMOUSEOVER=\'window.status="'
                . statusdisp('Convert To') . '"; return true;\' onfocus=\'window.status="' 
                . statusdisp('Convert To') . '"; return true;\' onblur=\'window.status=""\' '
                . 'ONMOUSEOUT=\'setTimeout("hideMenu()", 100);window.status=""\''.'>'.$convertLinkTxt.'</a>';
        }

        if($this->isReverseConversionEnabled && I18N::getSingleToken($record['STATE']) == I18N::getSingleToken('IA.CONVERTED_BY_LINE') ){
            $convertUrl = "";
        }

        return $convertUrl;
    }

    /**
     * SetDocumentRowAdditionalInfo
     */
    function SetDocumentRowAdditionalInfo() {
    }


    /**
     * @param int $rowno
     *
     * @return string
     */
    function GetRowState($rowno)
    {
        return I18N::getSingleToken($this->table[$rowno]['STATE']);
    }


    /**
     * @param int       $rowno
     * @param int       $id
     * @param string    $mod
     */
    function _calcHistoryURL($rowno, $id, $mod)
    {
        $_sess = Session::getKey();

        $owner = $this->GetObjectOwnership($rowno);
        $ownerloc = $this->GetObjectOwnerLocation($rowno);
        $Uid = $this->table[$rowno]['DOCID'];

        $rowstate =  $this->GetRowState($rowno);

        $dt = Request::$r->_dt;

        if(!in_array($dt, array(BUILD_KIT, DIS_KIT))) {
            $stateUrl = 'editor.phtml?.sess='.$_sess.'&.op='.$id.'&.mod='.$mod.'&.r='.urlencode($Uid).'&.popup=1&.hist=1';
            if($owner > 0 && $ownerloc ) {
                $this->table[$rowno]['STATE'] = "<a href=\"" . $this->_calcSlideUrl($stateUrl, $ownerloc, true) . "\" ".HREFUpdateStatus('Pending').">".$rowstate."</a>";
            } else{
                if (QXCommon::isQuixote()) {
                    $this->table[$rowno]['STATE'] = "<a href='#skip' onclick=\"showQxDialog('" . $rowstate . "','" . $stateUrl . "','','form','url','')\">" . $rowstate . "</a>";
                } else {
                    $this->table[$rowno]['STATE'] = '<a href="javascript:Launch(\''.urlencode($stateUrl).'\',\'mywindow\',700,500)" ' .
                    HREFUpdateStatus('View Transaction History'). '>'.$rowstate.'</a>';
                }
            }
        }
    }


    /**
     * @param int    $i
     * @param int    $id
     * @param string $contextLocation
     * @param int    $owner
     * @param string $ownerloc
     */
    function _calcPrintURL($i, $id, $contextLocation, $owner, $ownerloc )
    {
        $Uid = $this->table[$i]['DOCID'];

        if (IsMultiEntityCompany() && $contextLocation == '') {

            //$pdfurl had to be written seperately because in the later case which uses Launch doesn't escape
            //special characters like # and lands in login page so urlencode twice has to be used (it seems stupid but works)
            if ($owner > 0 && $ownerloc) {
                $pdfurl = 'editor.phtml?.action=deliver&.state=deliver&.op=' . Request::$r->_op . '&.r=' . urlencode($Uid) . '&.ppdf=1&.deliverymethod=pdfpreview&';
                $url = "<a href=\"" . $this->_calcSlideUrl($pdfurl, $ownerloc, true) . "\" >" . GT($this->textMap, 'IA.PRINT') . "</a>";
            } else {
                $pdfurl = 'editor.phtml?.action=deliver&.state=deliver&.op=' . Request::$r->_op . '&.r=' . urlencode(urlencode($Uid)) . '&.ppdf=1&.deliverymethod=pdfpreview&';
                $url = "<a href=\"javascript:Launch('" . $pdfurl . "','Invoice',450,300);\" >" . GT($this->textMap, 'IA.PRINT') . "</a>";
            }
        } else {
            $url = '<a href="editor.phtml?.action=deliver&.state=deliver&.op=' . $id . '&.r=' . urlencode($Uid) . '&.ppdf=1&.deliverymethod=pdfpreview&' . OptDone(ScriptRequest()) . '" ONMOUSEOVER=\'window.status="' .
                statusdisp('Print') . '"; return true;\' onfocus=\'window.status="' .
                statusdisp('Print') . '"; return true;\' onblur=\'window.status=""\'  ONMOUSEOUT=\'window.status=""\'>' . GT($this->textMap, 'IA.PRINT') . '</a>';
        }

        $this->table[$i]["'URL'"] = $url;
    }


    /**
     *      Run the equivelent of the query QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO, but with many doctypes.
     *  Before this was run once per doctype and that can be a LOT of times.
     *  This fills in the (existing) cache with the results
     *
     * @param string        $userkey        user key
     * @param string        $spi            sale/purchase/inventory
     * @param string[]      $doctypes       array of doctype strings
     *
     * @return bool
     */
    protected function getManyAllowedRecallTo($userkey, $spi, $doctypes)
    {
        if (empty($doctypes)) {
            return true;    // nothing to do
        }
        foreach ($doctypes as $doctype) {
            $this->upermAllowedDocsCache[$doctype] = [];    // so even if there's nothing to do we don't re-query
        }

        $sql   = [];
        $sql[] = "SELECT docpar.record#, docpar.userperm, docpar.docid, docpar.locationkey, docpar.docclass, recdpr.docid as fromdocid
                  FROM docpar, docrecalls, docpar recdpr
                 WHERE docpar.latestversionkey is null
                   and docpar.sale_pur_trans = :2 and docpar.status = 'T'
                   and docpar.RECORD# = docrecalls.DOCPARKEY (+)
                   and docrecalls.RECDOCPARKEY = recdpr.record#
                   and recdpr.record# = docrecalls.recdocparkey 
                   and recdpr.cny# (+) = :1 and docpar.cny# = :1 and docrecalls.CNY# (+) = :1 and nvl(docpar.enable_contract_billing,'F') != 'T' ";
        $sql[] = GetMyCompany();
        $sql[] = $spi;
        $sql   = PrepINClauseStmt($sql, $doctypes, 'and recdpr.docid ');
        $sql[0] .= " order by docpar.docid ";
        $recs  = QueryResult($sql);
        if ($recs === false) {
            return false;
        }

        if ( ! empty($recs)) {
            $recs = upermFilterResult($recs, $userkey);
            $recs = filterDocsForUserType($recs);
            foreach ($recs as $rec) {
                $this->upermAllowedDocsCache[$rec['FROMDOCID']][] = $rec;
            }
        }
        return true;
    }


    /**
     * @return string
     */
    function CalcHeadIsland()
    {
        global $_userid, $gManagerFactory;
        $_sess = Session::getKey();

        $opid    = GetOperationId($this->mod . '/lists/' . $this->mod . 'document/create');
        $docparMgr    = $gManagerFactory->getManager('documentparams');

        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->mod];

        //Set Report View Context for MEGA downward
        if($this->showPrivate ) {
            SetReportViewContext();
        }
        $docs = GetDocumentMenuList($this->mod);

        //Dont show build kits and disassemble kits in the common lister -- mmahur
        $doctypes = [];
        foreach($docs as $key => $val){
            if ($val['DOCID'] == BUILD_KIT || $val['DOCID'] == DIS_KIT) {
                unset($docs[$key]);
            } else {
                $doctypes[] = $val['DOCID'];
            }
        }

        //$allowedDocsCache = array();
        $arrExplode = explode('@', $_userid);
        $userkey = array_shift($arrExplode);

        // fill in the cache with the doctypes to save individual calls below
        $this->getManyAllowedRecallTo($userkey, $spi, $doctypes);

        $doctypejsArr = [];
        $doctypelocjsArr = [];
        foreach ($docs as $doc) {
            $doctype = $doc['DOCID'];

            $ddlist = array($doctype);
            $ddLocList = array('');//array($doc['LOCATIONKEY']);

            $allowedDocs = $this->upermAllowedDocsCache[$doctype];
            if (!isset($allowedDocs)) {
                $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($spi, 'T', $doctype));
                $allowedDocs = upermFilterResult($allowedDocs, $userkey);
                $allowedDocs = filterDocsForUserType($allowedDocs);
                $this->upermAllowedDocsCache[$doctype] = $allowedDocs;
            }

            $allowedDocs = ( $allowedDocs ?: array() );
            foreach ($allowedDocs as $doc2) {
                $ddlist[] = str_replace("'", "\'", $doc2['DOCID']);
                $ddLocList[] = str_replace("'", "\'", $doc2['LOCATIONKEY']);
            }
            $doctypejsArr[] = "['" . join("', '", $ddlist) . "']";
            $doctypelocjsArr[] = "['" . join("', '", $ddLocList) . "']";
        }
          //Set Report View Context for MEGA downward
        if($this->showPrivate ) {
            SetTransactionViewContext();
        }

        $js_doctypes = "[" . join(", ", $doctypejsArr) . "]";
        $js_docLocTypes = "[" . join(", ", $doctypelocjsArr) . "]";

        $getMyLayoutType = GetMyLayoutType();
        $pageLayoutType = QXCommon::getPageLayoutType();

        $headTag = "

		<script type=\"text/javascript\" language=\"text/javascript\">

		var menu; 
		var doctypes = ".$js_doctypes.";
		var docLocTypes = ".$js_docLocTypes.";
		var sess = '".$_sess."';
		var theOpId = '".$opid."';
		var cny = '".GetMyCompany()."';
		var contextLocation = '".GetContextLocation()."';
		var isMega = '".IsMultiEntityCompany()."';
		var currScript = '".insertDoneUnEnc(ScriptRequest())."';
		var MYLAYOUTTYPE = '" . $getMyLayoutType . "';
		var PAGE_LAYOUT_TYPE = '" . $pageLayoutType . "';
		var parentdt = '" . $this->doctype . "';

		function getDivText(currType, docid, slideContext) {

			var currTypeArr;
			var numRec = doctypes.length;
			var hrefHTML = '';
			var index = '';
			var url = '';

			if ( numRec == 0 ) { return hrefHTML; }

			for (i=0; i<numRec; i++) {
				if (doctypes[i] != null && currType == doctypes[i][0]){
					index = i;
				}
			}

			//if ( index == '' ) { return hrefHTML; }

			currTypeArr = doctypes[index];			
			
			//This has to be done for Mega company because there was a possiblity of converting a document
			//created from one entity to a TD of another entity
			if(isMega && contextLocation == ''){
				if(typeof(currTypeArr) == 'object'){
					
					var newcurtypearr = [];
					len = (currTypeArr.length ? currTypeArr.length : -1);

					//Populate the array with only those TD's that either is owned by the transaction owner
					//or belongs to root.
					for (j=0; j<len; j++) {
						if (docLocTypes[index][j] == slideContext || docLocTypes[index][j] == ''){
							newcurtypearr[newcurtypearr.length] = currTypeArr[j];
						}
					}

					currTypeArr = newcurtypearr;
				}
			}

			var currTypeNum = currTypeArr.length;
			var urlAction;
 		
			if (currTypeNum > 1) {
			    if ( PAGE_LAYOUT_TYPE === 'Q' ) {
			        hrefHTML = '<ul class=\"dropdown-menu qx-convert-menu\" >';
			    } else {
				    hrefHTML = '<TABLE BORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"1\"><tr><td><table>';
				}
			}

			for (i=1; i<currTypeNum; i++) {
				if (currTypeArr[i] != null) {
					dt = currTypeArr[i];

                    url = 'editor.phtml?.op='+theOpId+'&.sess='+sess+'&.copymode=Update&.r='+encodeURIComponent(docid)+'&.done='+encodeURIComponent(currScript)+'&.dt='+encodeURIComponent(dt)+'&.parentdt='+encodeURIComponent(parentdt);

					// From root for mega not owned obj do a slide for conversion
					if ( slideContext != '' && contextLocation == '' ) { 
						url += '&.popup=1';
						url = \"javascript:SlideLaunch('mereportslide',1,cny,'','\" + url + \"',\" + slideContext + ', 1)';
						urlAction = 'HREF=\"#\" onClick=\"' + url + '\"';
					}
					   else
                           {
                               urlAction = 'HREF=\"' + url + '\"';
                         
                           }
        
                    if ( PAGE_LAYOUT_TYPE === 'Q' ) {
	    		        hrefHTML += '<li class=\"dropdown-item\" >';
	    		        hrefHTML += '<a class=\"Result2\"'+ urlAction +
                                    'onmouseover=\'window.status=\"Convert to '+dt+'\";return true;\''+
                                    'onmouseout=\'window.status=\"\"; return true;\''+
                                    '>'+dt+'</a></li>';
		    	    } else {
					    hrefHTML += '<TR><TD><A CLASS=\"Result2\"'+ urlAction +
                                    'onmouseover=\'window.status=\"Convert to '+dt+'\";return true;\''+
                                    'onmouseout=\'window.status=\"\"; return true;\''+
                                    '><font size=1>'+dt+'</font></A></TD></tr>';
                    }
				}
			}
			if (hrefHTML) {
				hrefHTML += '</table></td></tr></table>';
			}
			return hrefHTML;
		}

		var onMousedLayer = '';

		function showMenu (evt, currType, docid, slideContext, obj) {

		  var hrefHTML = getDivText(currType, docid, slideContext);
		  if (!hrefHTML) {
			  alert('No recall information found for '+currType);
			  return true;
		  }

		  menuExpand = document.getElementById('convertMenu');
		  
		  menuExpand.style.left = (baseGetObjectLeft(obj) + obj.offsetWidth) + 'px';
		  menuExpand.style.top = baseGetObjectTop(obj) + 'px';
		  menuExpand.style.position = 'absolute';
		  menuExpand.style.visibility = 'visible';
		  menuExpand.innerHTML = hrefHTML;
		  
		  if ( PAGE_LAYOUT_TYPE === 'Q' ) { 
		      var convertMenuList = document.getElementsByClassName('qx-convert-menu')[0];  
		      convertMenuList.style.display = 'block';
		  }
		  
		  return false;
		}
        
		function hideMenu() {
			if (onMousedLayer == 'set') {
				return;
			}
			onMousedLayer = '';
			
            menuExpand = document.getElementById('convertMenu');
            menuExpand.style.visibility = 'hidden';

			 if ( PAGE_LAYOUT_TYPE === 'Q' ) { 
		        var convertMenuList = document.getElementsByClassName('qx-convert-menu')[0];
		        if (convertMenuList) {
                    convertMenuList.style.display = 'none';
                }
		    }
		}

		</script>
		<script type=\"text/javascript\" src=\"" . URLReplace::replaceRelativeURL("../resources/thirdparty/milonic/milonic_src.js") . "\"></script>	
		<script type=\"text/javascript\" src=\"" . URLReplace::replaceRelativeURL("../resources/thirdparty/milonic/mmenudom.js") . "\"></script>	
		<script type=\"text/javascript\" src=\"" . URLReplace::replaceRelativeURL("../resources/thirdparty/milonic/menu_data.js") . "\"></script>
		";

        return $headTag;
    }

    /**
     * @return string
     */
    function CalcBodyIsland()
    {
        if (QXCommon::isQuixote()) {
            $divTag = "<div id=\"convertMenu\" class=\"Task\" 
				style=\"position: absolute; 
					  visibility: hidden;\" 
				onmouseout=\"menu = this; onMousedLayer=''; this.tid = setTimeout ('hideMenu()', 100);\" 
				ONMOUSEOVER=\"onMousedLayer = 'set';clearTimeout(this.tid);\">
			</div>";
        } else {
            $divTag = "<DIV ID=\"convertMenu\" CLASS=\"Task\" 
				STYLE=\"position: absolute; 
					  visibility: hidden; 
					  background-color: white; 
					  layer-background-color: white; 
					  border: 2px outset white;\" 
				ONMOUSEOUT=\"menu = this; onMousedLayer=''; this.tid = setTimeout ('hideMenu()', 100);\" 
				ONMOUSEOVER=\"onMousedLayer = 'set';clearTimeout(this.tid);\">
			</DIV>";
        }

        return $divTag;
    }

    /**
     *  Used to construct base url parms
     *
     * @param int   $i    row index
     * @param array $vals input params of the format:
     *                      $val['dst'] => destination script
     *                      $val['urlargs'] => array of key=>value parms to be emitted in the 'urlargstring' output
     *                      $val['text'] => href text that is to be displayed
     *                      $val['tip'] => mousover tip
     *
     * @return array the output arguments to be used to generate an href of the format:
     *             $dst['dst'] => Destination script
     *             $args['urlstring'] => string in the form "key1=value1&key2=value2&key3=value3...."
     *                                   where key,value[1..n] come from $val['urlargs'] array
     *             $args['text'] => text of the href
     *             $args['tip'] => mouseover tip
     */
    function _calcUrlParms($i, $vals )
    {
        $doctype = $this->table[$i]['DOCPARID'];
        $vals['urlargs']['.dt'] = (!empty($doctype))? $doctype : $this->doctype;
        $vals['urlargs']['.parentdt'] = $this->doctype;
        return parent::_calcUrlParms($i, $vals);
    }

    /**
     * @return string
     */
    function calcUserViewCreateUrl()
    {
        $uvCreateURL = parent::calcUserViewCreateUrl();
        $uvCreateURL .= "&DOCTYPE=".$this->doctype;
        return $uvCreateURL;
    }

    /**
     * @param string $userviewid
     *
     * @return string
     */
    function calcUserViewEditUrl($userviewid)
    {
        $uvEditURL = parent::calcUserViewEditUrl($userviewid);
        $uvEditURL .= "&DOCTYPE=".$this->doctype;
        return $uvEditURL;
    }

    /*	function calcDeleteUrl($i) {
    if ($this->table[$i]['STATE'] == 'Deleted') {
    return "";
    }
    return parent::calcDeleteUrl($i);
    }*/


    /**
     * This function is overriden to pass the proper entity = "glbudget" for the import proces.
     *  block txn creation for multi jurisdiction
     * @return string
     */
    function addImportURL()
    {
        $ret = '';

        if ( 'C' !== $this->_createPolicy && 'F' !== $this->_creationRule ) {
            $ret =  parent::addImportURL();
        }
        return $ret;
    }



    /**
     * SetDocumentTotals
     */
    function SetDocumentTotals()
    {
        if(count($this->docHdrKeys) > 0) {
            $cny = GetMyCompany();

            $stmt[0] = "select dochdrkey, NVL(SUM(UIVALUE),0) AS SUBTOTAL, NVL(SUM(TRX_VALUE),0) AS TRX_SUBTOTAL from docentry docentry, dochdrmst dochdr where dochdr.record# = docentry.dochdrkey and dochdr.cny# = docentry.cny# and docentry.cny# = :1";
            $stmt[1] = $cny;
            $stmt = PrepINClauseStmt($stmt, $this->docHdrKeys, " and docentry.dochdrkey ");
            $stmt[0] .= " group by dochdrkey ";
            $res = QueryResult($stmt);
            foreach ($res as $value) {
                $this->docHdrTotalCache[$value['DOCHDRKEY']]['SUBTOTAL'] = $value['SUBTOTAL'];
                $this->docHdrTotalCache[$value['DOCHDRKEY']]['TRX_SUBTOTAL'] = $value['TRX_SUBTOTAL'];
                $this->docHdrTotalCache[$value['DOCHDRKEY']]['TOTAL'] = $value['SUBTOTAL'];
                $this->docHdrTotalCache[$value['DOCHDRKEY']]['TRX_TOTAL'] = $value['TRX_SUBTOTAL'];
            }

            $stmt2[0] = "select dochdrkey, NVL(SUM(dochdrsubtotals.TOTAL),0) AS TOTAL, NVL(SUM(dochdrsubtotals.TRX_TOTAL),0) AS TRX_TOTAL from DOCHDRSUBTOTALS dochdrsubtotals, dochdrmst dochdr where dochdr.record# = dochdrsubtotals.dochdrkey and dochdr.cny# = dochdrsubtotals.cny# and dochdrsubtotals.cny# = :1";
            $stmt2[1] = $cny;
            $stmt2 = PrepINClauseStmt($stmt2, $this->docHdrKeys, " and dochdrsubtotals.dochdrkey ");
            $stmt2[0] .= " group by dochdrkey ";
            $res2 = QueryResult($stmt2);
            foreach ($res2 as $value2) {
                $this->docHdrTotalCache[$value2['DOCHDRKEY']]['TOTAL'] += $value2['TOTAL'];
                $this->docHdrTotalCache[$value2['DOCHDRKEY']]['TRX_TOTAL'] += $value2['TRX_TOTAL'];
            }
        }
    }
}
