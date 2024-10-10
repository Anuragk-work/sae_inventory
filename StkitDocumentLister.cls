<?
//
//================================================================================
//	FILE:			StkitDocumentLister.cls
//	AUTHOR:			Manoj Mahur
//	DESCRIPTION:	This class manages all activities associated to a RecurDocument objects.
//
//	(C)2000-2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//


/**
 * Class StkitDocumentLister
 */
class StkitDocumentLister extends DocumentLister
{

    public const IA_BUILT = 'IA.BUILT';

    public const IA_CONVERTED = 'IA.CONVERTED';

    public const IA_DISASSEMBLE = 'IA.DISASSEMBLE';

    public const IA_DISASSEMBLED = 'IA.DISASSEMBLED';

    public const IA_DRAFT = 'IA.DRAFT';

    public const IA_PENDING = 'IA.PENDING';

    /**
     * @var string[] $stkitDocumentListerTokens Tokens used here
     */
    private static $stkitDocumentListerTokens = [
        self::IA_BUILT,
        self::IA_CONVERTED,
        self::IA_DISASSEMBLE,
        self::IA_DISASSEMBLED,
        self::IA_DRAFT,
        self::IA_PENDING,
    ];

    function __construct()
    {
        $dt = Request::$r->_dt;
        $batchtitle = Request::$r->_batchtitle;
        $skTransactionType = !empty($batchtitle) ? $batchtitle : $dt;
        $title = [
            'id' => 'IA.INVENTORY_TRANSACTIONS_TYPE',
            'placeHolders' => [
                [
                    'name'  => 'SK_TRANSACTION_TYPE',
                    'value' => $skTransactionType,
                ]
            ]
        ];
        if (isset($batchtitle)) {

            $bmenu = array(
                'DOCPARID',
                'DOCNO',
                'PONUMBER',
                'WHENCREATED',
                'STATE',
                "'URL'",
                "'DISASSEMBLE'",
            );
        } else {
            $bmenu = array(
                'DOCPARID',
                'DOCNO',
                'PONUMBER',
                'INVBATCH',
                'WHENCREATED',
                'STATE',
                "'URL'",
                "'DISASSEMBLE'",
            );
        }
        if ($dt == StkitDocumentManager::BUILDKIT) {
            $helpfile = 'Viewing_and_Managing_the_List_of_Built_Kits';
        } elseif ($dt == StkitDocumentManager::DISKIT) {
            $helpfile = 'Viewing_and_Managing_the_List_of_Disassembled_Kits';
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $params = array(
            'entity' => 'stkitdocument',
            'title' => $title,
            'fields' => $bmenu,
            'sortcolumn' => 'WHENCREATED:d, DOCNO:d',
            'helpfile' => $helpfile,
            'defaultview' => 'Recently viewed',
            'nofilteronthesefields' => array('STATE'),
            'enablemultidelete' => false,
        );

        if ($dt) {
            $this->GetEditDeletePolicy($dt);
            if ($this->_deletePolicy == 'N') {
                $params['disabledelete'] = 1;
                unset($params['enablemultidelete']);
            }
            //Edit is set in CalcEditUrl in parent class
        } else {
            //No add link in common lister
            $params['disableadd'] = true;
        }

        //added for csv import functionality for build kits only
        if ( $dt == StkitDocumentManager::BUILDKIT ) {
            $params['importtype'] = 'stkitdocument';
            $params['importperm'] = 'inv/lists/stkitdocument/create';
        }

        $this->additionalTokens = array_merge($this->additionalTokens, self::$stkitDocumentListerTokens);
        parent::__construct($params);

        $this->mod = 'inv';
        $this->xssEncode=true;
    }

    /**
     *	This method overrides the base function and adds a query filter to the array.
     *  this filters rows which have glentrykey as current glkey from url.
     *
     * @return array
     */
    function BuildQuerySpec() 
    {
        $queryStr = parent::BuildQuerySpec();
        $batch = Request::$r->_batch;
        if( !empty($batch) ) {            
            $fltrs = array('INVBATCHKEY','=',"$batch");
            if( !empty($queryStr['filters'][0]) ) { 
                $queryStr['filters'][0][] = $fltrs; 
            }
            else{ 
                $queryStr['filters'][0][0]  = $fltrs;
            }            
        }
        return $queryStr;
    }

    /**
     * @return string
     */
    function genGlobs()
    {
        $batch = Request::$r->_batch;
        $ret = parent::genGlobs();
        if( !empty($batch) ) {
            $batchtitle = Request::$r->_batchtitle;            
            $ret .= "<g name='.batch'>" . $batch . "</g>";
            $ret .= "<g name='.batchtitle'>" . URLCleanParams::insert('.batchtitle', $batchtitle) . "</g>";
        }
        return $ret;
    }

    /**
     *
     */
    function BuildTable() 
    {
        $_sess = Session::getKey();

        DocumentLister::BuildTable();
        $disassemblekitop = GetOperationId($this->mod . '/lists/' . 'stkitdocument/create');

        $gManagerFactory = Globals::$g->gManagerFactory;
        $docParMgr = $gManagerFactory->getManager('invdocumentparams');
        $querySpec = array(
            'selects' => array(
                'DOCID','USERPERM'
            ),
            'filters' => array(array(array('DOCID', '=', DIS_KIT),),),
        );
        $resultSet = $docParMgr->GetList($querySpec);
        $disassembleNotAllowed = false;
        if ($resultSet[0]['USERPERM'] == 'true') {
            global $MODNAME, $POLNAME;
            $userkey = GetMyUserid();
            $fs = new FSEntityManager();
            if ( ! $fs->IsPathAllowedForUser(DIS_KIT, $userkey, $MODNAME, $POLNAME) ) {
                $disassembleNotAllowed = true;
            }
        }

        $flds = $this->_params['_fields'];
        $fldnames = $this->_params['_fieldlabels'];

        for ($i = 0; $i < count($this->table); $i++) {
            $rec = $this->table[$i];

            $Uid = $this->table[$i]['DOCID'];

            if ($rec['STATETEMP'] != GT($this->textMap, 'IA.BUILT') || $disassembleNotAllowed) {
                $convertUrl = '';
            } else {
                $convertUrl = '<a href="editor.phtml?.op=' . $disassemblekitop . '&.sess=' . $_sess
                    . '&.dt=Disassemble Kits&.copymode=Update&.r=' . urlencode($Uid) . '" ONMOUSEOVER=\'window.status="'
                    .
                    statusdisp('Disassemble') . '"; return true;\' onfocus=\'window.status="' .
                    statusdisp('Disassemble')
                    . '"; return true;\' onblur=\'window.status=""\'  ONMOUSEOUT=\'window.status=""\'>' .
                              GT($this->textMap, self::IA_DISASSEMBLE) . '</a>';
            }

            if ($this->_params['_op']['create'] != '') {
                $this->table[$i]["'DISASSEMBLE'"] = $convertUrl;
            } else {
                $this->table[$i]["'DISASSEMBLE'"] = '';
            }

        }
        $flds[] = 'VIEWPDF';
        $fldnames[] = '';
        $this->SetOutputFields($flds, $fldnames);

    }

    /**
     * @return string|null
     */
    function calcAddUrl() 
    {
        $p = &$this->_params; //???

        $dt = Request::$r->_dt;
        
        if ($dt == StkitDocumentManager::DISKIT) {
            return null;
        }
        $schopkey = Request::$r->_schopkey;
        $op = $p['_op']['create'];

        $text =  $p['_addbutton'];
        $dst = $this->calcAddDst();
        $tip = 'Add New Item';
        $do = 'create';

        $ret =     "<a href=\"" .     
        $this->U($dst, ".do=$do&.schopkey=$schopkey&.dt=" . urlencode(isl_trim($dt)) . "&.r=&.op=$op&add=Add&_action=new", $this->LCALL) ."\" " . 
        ">" .
        $text . 
        "</a>";
        
        return $ret;
    }
    
    /**
     * @param int   $i
     * @param array $vals
     *
     * @return array
     */
    function calcDeleteUrlParms($i, $vals)
    {
        $table = &$this->table;
        // Ignore items with the No Edit ('N') policy
        if ($this->_deletePolicy == 'N') {
            return [];
        }
        // Ignore items with the Edit in Draft Only ('D') policy that aren't drafts
        else if ($this->_deletePolicy == 'D' && $this->values[$i]['STATE'] != 'I') {
            return [];
        }
        return parent::calcDeleteUrlParms($i, $vals);
    }

    /**
     * @param int   $i
     * @param array $vals
     *
     * @return array
     */
    function _calcUrlParms($i, $vals )
    {
        $doctype = $this->table[$i]['DOCPARID'];
        $vals['urlargs']['.dt'] = $doctype;
        return parent::_calcUrlParms($i, $vals);
    }

    /**
     * @return string
     */
    function CalcHeadIsland() 
    {
        global $_userid, $gManagerFactory;

        $_sess = Session::getKey();

        $opid    = GetOperationId($this->mod . '/lists/' . 'stkitdocument/create');
        $docparMgr    = $gManagerFactory->getManager('documentparams');

        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->mod];

        //Set Report View Context for MEGA downward
        if($this->showPrivate ) {
            SetReportViewContext();
        }
        $docs = GetDocumentMenuList($this->mod);
        foreach ($docs as $doc) {
            $doctype = $doc['DOCID'];

            $ddlist = array($doctype);
            $ddLocList = array('');//array($doc['LOCATIONKEY']);
            $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($spi, 'T', $doctype));
            $arrExplode = explode('@', $_userid);
            $userkey = array_shift($arrExplode);
            $allowedDocs = upermFilterResult($allowedDocs, $userkey);
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

        /** @noinspection PhpUndefinedVariableInspection */
        $js_doctypes = "[" . join(", ", $doctypejsArr) . "]";
        /** @noinspection PhpUndefinedVariableInspection */
        $js_docLocTypes = "[" . join(", ", $doctypelocjsArr) . "]";

        $headTag = "

		<SCRIPT language=javascript>

		var menu; 
		var doctypes = ".$js_doctypes.";
		var docLocTypes = ".$js_docLocTypes.";
		var sess = '".$_sess."';
		var op = '".$opid."';
		var cny = '".GetMyCompany()."';
		var contextLocation = '".GetContextLocation()."';
		var isMega = '".IsMultiEntityCompany()."';

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
					
					var newcurtypearr = new Array();
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
 		
			if (currTypeNum > 1) {
				hrefHTML = '<TABLE BORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"1\"><tr><td><table>';
			}

			for (i=1; i<currTypeNum; i++) {
				if (currTypeArr[i] != null) {
					dt = currTypeArr[i];

					url = 'editor.phtml?.op='+op+'&.sess='+sess+'&.dt='+escape(dt)+'&.copymode=Update&.r='+escape(docid);

					// From root for mega not owned obj do a slide for conversion
					if ( slideContext != '' && contextLocation == '' ) { 
						url += '&.popup=1';
						url = \"javascript:SlideLaunch('mereportslide',1,cny,'','\" + url + \"',\" + slideContext + ', 1)';
					}

					hrefHTML += '<TR><TD><A CLASS=\"Result2\"  HREF=\"' + url + '\"'+
								'onmouseover=\'window.status=\"Convert to '+dt+'\";return true;\''+
								'onmouseout=\'window.status=\"\"; return true;\''+
								'><font size=1>'+dt+'</font></A></TD></tr>';

				}
			}
			if (hrefHTML) {
				hrefHTML += '</table></td></tr></table>';
			}
			return hrefHTML;
		}


		</SCRIPT>";

        return $headTag;
    }
}


