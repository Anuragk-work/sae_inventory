<?php
//
//================================================================================
//	FILE:			RecurDocumentLister.cls
//	AUTHOR:			bharris
//	DESCRIPTION:	Recurring Document Lister base class.
//
//	(C)2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//

import('NLister');

/**
 * Class RecurDocumentLister
 */
class RecurDocumentLister extends NLister
{
    /** @var bool  $_showAddButton*/
    var $_showAddButton;

    /** @var  int $editRec */
    var $editRec;

    /** @var int $viewRec  */
    var $viewRec;
    /**
     * @var string[]
     */
    protected $additionalTokens = [];
    
    /**
     * @param array $params Initialization values for this Lister
     */
    function __construct($params = [])
    {
        $this->additionalTokens[] = 'IA.TURN_ON';
        $this->additionalTokens[] = 'IA.TURN_OFF';
        $this->additionalTokens[] = 'IA.LAST_RESULT';
        $this->additionalTokens[] = 'IA.SCHEDULE';
	
        $this->_showAddButton = $params['templatename']==''?true:true;

        /** @noinspection PhpUndefinedVariableInspection */
        parent::__construct(
            array(
            'entity'                    =>  $params['entity'],
            'title' => [
                'id' => 'IA.RECURRING_TRANSACTIONS_TEMPLATES',
                'placeHolders' => [
                    ['name' => 'TEMPLATE_NAME', 'value' => $params['templatename']]
                ]
            ],
            'fields'                    =>  $params['fields'],
            'nofilteronthesefields'     =>  array ('ENDDATE','SUCCESS','EXECCOUNT'),
            'helpfile'                  =>  $params['helpfile'],
            'list'                      =>     'lister.phtml?.dt='. util_encode($dt),
            'importtype'                =>  $params['importtype'],
            'format'                    =>  array(
                                                'EXECCOUNT' => array(
                                                    'calign'=> 'center'
                                                ),
                                            ),
            //'entitynostatus'		=> 	true,
            )
        );

        //Lister uses table and Editor used updatetable
        $this->getEntityMgr()->_from = 'L'; //Determines whether to use updatetable ot table for query generation

    }

    /**
     * @return RecurDocumentManager
     */
    public function getEntityMgr()
    {
        assert($this->entityMgr instanceof RecurDocumentManager);
        return $this->entityMgr;
    }

    /**
     *  Method whic allows adding addition content to the data to be displayed
     * in the Lister's table area.
     *  Override parents to add unique value.
     *
     */
    function BuildTable() 
    {    
        parent::BuildTable();

        $mod    = Request::$r->_mod;
        $op_key = GetOperationId($this->params['opkey']);  // could be SO/PO/IV
        $op_err = GetOperationId('co/lists/scheduledoperationlog');
        $sess     = Request::$r->_sess;
        $docid    = Request::$r->_dt;
        $table    = &$this->table;

        //Set Report View Context for MEGA downward
        if($this->showPrivate ) {
            SetReportViewContext();
        }

        $allSchopKeys            = array();
        $resultSet_schedoplog    = array();
        $resultSet_docrec        = array();
        $resultSet_recurdoc        = array();
        
        // COLLECT ALL THE SCHOPKEYS FROM THE LISTER TABLE
        foreach ( $table as $values ) {
            $allSchopKeys[] = $values['RECORDNO'];
        }

        if ( isset($allSchopKeys) && count($allSchopKeys) > 0 ) {
            $innerQuery = "SELECT	so.schedop# sop, max(so.record#) record#
					FROM	scheduledoperationlog so, recurdochdr rr
					WHERE	so.cny# = rr.cny# and so.schedop# = rr.schopkey
							and rr.cny# = :1 ";

            $innerQuery = PrepINClauseStmt($innerQuery, $allSchopKeys, " and rr.record# ");

            $innerQuery .= " GROUP BY so.schedop#";
            $qry = "
			SELECT so.schedop# sop, so.state success from scheduledoperationlog so where (so.schedop#, so.record#) in
			(". $innerQuery . ") and cny#=:1";

            $args = array($qry, GetMyCompany());
            $args = INTACCTarray_merge($args, $allSchopKeys);
            $resultSet = QueryResult($args);

            foreach ( $resultSet as $values ) {
                $resultSet_schedoplog[$values['SOP']] = $values;
            }

            //Count of successful record
            $qry = "SELECT	dh.schopkey, count(1) count FROM dochdrmst dh, recurdochdrmst rr
					WHERE	dh.cny# = rr.cny# and dh.schopkey = rr.schopkey 
							and rr.cny# = :1";
            $args = PrepINClauseStmt($qry, $allSchopKeys, " and rr.record# ");
            $args .= " GROUP BY dh.schopkey ";
            $args = array($args, GetMyCompany());
            $resultSet = QueryResult($args);

            foreach ( $resultSet as $values ) {
                $resultSet_docrec[$values['SCHOPKEY']] = $values;
            }

            // GETRAW VALUES FROM RECURDOCHDR
            $args = array("SELECT * FROM recurdochdr WHERE cny# = :1 ", GetMyCompany());
            $args[0] = PrepINClauseStmt($args[0], $allSchopKeys, " and record# ");
            

            $resultSet = QueryResult($args);

            foreach ( $resultSet as $values ) {
                $resultSet_recurdoc[$values['RECORD#']] = $values;
            }

        }

        for ($i = 0; $i < count($table); $i++) {

            $recurStatus = $table[$i]['STATUS'] == 'IA.INACTIVE' ? 'F' : 'T';
            $res_recurpr = $resultSet_recurdoc[$table[$i]['RECORDNO']];
            $schopKey = $res_recurpr['SCHOPKEY'];
            $recurDocRecordNo = $table[$i]['RECORDNO'];

            $table[$i]['SUCCESS'] = '';

            $owner = $this->GetObjectOwnership($i);
            $ownerloc = $this->GetObjectOwnerLocation($i);

            if (isset($res_recurpr['SCHOPKEY']) && $res_recurpr['SCHOPKEY'] != '') {
                $schedoplog = $resultSet_schedoplog[$schopKey];
                $statUrl = URLEncryption::buildUrl('lister.phtml',
                    [
                        '.sess' => $sess,
                        '.do' => 'view',
                        '.op' => $op_err,
                        'schopkey' => $schopKey,
                        '.done' => insertDone(ScriptRequest())
                    ]);
                if( $owner > 0 && $ownerloc ) {
                    $statUrl = $this->_calcSlideUrl($statUrl, $ownerloc);
                }
                if (isset($schedoplog) && $schedoplog!='') {
                    $status = ScheduledOperationLogManager::getFriendlyState($schedoplog['SUCCESS']);
                    $table[$i]['SUCCESS'] = "<a href=\"" . $statUrl ."\" >$status</a>";
                }
            }

            $table[$i]['EXECCOUNT'] = '0';
            $docrec = $resultSet_docrec[$schopKey]['COUNT'];
            if ($docrec > 0) {
                $table[$i]['EXECCOUNT'] = 
                    "<a href=\"lister.phtml?.op=$op_key&.userviewid=" . URLCleanParams::insert('.userviewid', Lister::SYSVIEW_ALL)
                    . "&.dt=". urlencode($docid)
                    . "&.showprivate=" . $this->showPrivate
                    . "&.schopkey=$schopKey&_done="
                    . insertDone(URLS::ScriptRequest())
                    . "&.sess=".urlencode($sess)
                    . "\" >$docrec</a>";

            }

            $cancelRequest = $recurStatus == 'T' ? I18N::getSingleToken('IA.TURN_OFF') : I18N::getSingleToken( 'IA.TURN_ON');

            $executionStatus = $this->checkExecutionURLStatus($table[$i], $owner);
            
            if ($executionStatus) {

                $table[$i]['SCHEDULE'] = "<a href='". $this->calcStatusAndReloadCurrentURL($schopKey, $recurStatus, $mod, $recurDocRecordNo) ."'>".$cancelRequest."</a>";
            }
        }

        $this->_params['_fields'][] = $this->_params['_fieldorders'][] = 'SCHEDULE';
        $this->_params['_fieldlabels'][] = I18N::getSingleToken( 'IA.SCHEDULE');

        $this->_params['_fields'][] = 'SUCCESS';
        $this->_params['_fieldlabels'][] = I18N::getSingleToken( 'IA.LAST_RESULT');
        $this->_params['_nosort'] = array ('SUCCESS' => 1, 'EXECCOUNT' => 1, 'SCHEDULE' => 1);
        $this->_params['_nofilteronthesefields'][] = 'SCHEDULE';
    }

    /**
     *  Used to submit on click of the Activate/Deactivate link in the recurring transaction screen.
     *
     * @param int    $shopKey   key field specifying the recurring transaction
     * @param string $status
     * @param string $mod
     * @param int $recurDocRecordNo record number of the recur document.
     *
     * @return string
     */
    function calcStatusAndReloadCurrentURL($shopKey, $status, $mod, $recurDocRecordNo)
    {
        $_sess = Session::getKey();
        $opid = GetOperationId($mod . '/lists/' . $mod . 'recurdocument');
        $it = $this->_params['_entity'];

        // Build the target URL
        $targetURL = "submit.phtml?.do=updaterecur&.it=" . $it . "&.op=".$opid 
            . "&_obj__status=" . URLCleanParams::insert('_obj__status', $status) 
            . "&_obj__shopKey=" . URLCleanParams::insert('_obj__shopKey', $shopKey)
            . "&_obj__r=" . URLCleanParams::insert('_obj__r', $recurDocRecordNo)
            . "&.sess=".$_sess;
        $targetURL = CallUrl($targetURL);

        //Generate the CSRF token that will be passed as a post parameter
        $urlPostArgs = array();
        $urlPostArgs[CsrfUtils::DOT_CSRF_PARAM_NAME] = $this->calcCSRFToken($opid);

        $resetURL = XMLUtils::xmlSpecialChars("javascript:doPost('" . urlencode($targetURL) . "'," . json_encode($urlPostArgs) . ");");

        return $resetURL;
    }

    /**
     * @param array $row
     * @param int   $owner
     *
     * @return bool
     */
    function checkExecutionURLStatus($row, $owner) 
    {
        if ($row['NEXTEXECDATE'] == '' || $owner < 0) {
            return false;
        }

        return true;
    }

    /**
     * @return string
     */
    function genTopPanel() 
    {
        $ret = NLister::genTopPanel();
        $ret = "<b id='send'/>".$ret;
        return $ret;        
    }

    /**
     * @return string
     */
    function genBotPanel() 
    {
        $ret = NLister::genBotPanel();
        $ret = "<b id='send'/>".$ret;
        return $ret;        
    }
    /**
     * @return array
     */
    function BuildQuerySpec() 
    {

        $mod = Request::$r->_mod;

        $initial = parent::BuildQuerySpec();
        
        $docpars = GetDocumentMenuList($mod);

        // The following filter is not in the else clause for the above if 
        // to avoid someone trying to put dt in the url when he doesn't have permission to do so.
        $initial['filters'][0][] = array(
        'documentparams.docid', 'IN', array_keys(AssociateArray($docpars, 'DOCID'))
        );

        return $initial;
    }    

    /**
     * Constructs the content of the Add Button's URL
     * Override parents to add unique value.
     * 
     * @return string
     */
    function calcAddUrl() 
    {
        
        $p         = &$this->_params;
        $text     = $p['_addbutton'];
        $dst     = $this->calcAddDst();
        $do     = 'create';
        $op     = $p['_op']['create'];
        $dt     = Request::$r->_dt;
        
        //Package up the arguments to the url 
        /** @noinspection PhpUndefinedVariableInspection */
        $urlargs = array( '.do'     => $do,
                          '.r'      => $r,
                          '.dt'     => urlencode($dt),
                          '.op'     => $op,
                          'add'     => GT($this->textMap, 'IA.ADD'),
                          'single'  => $dt!=''?urlencode($dt):'',
                          '_action' => 'new');
                            
        $vals = array(    'dst'         => $dst, 
         'urlargs'     => $urlargs, 
         'text'         => $text 
         );

        //Generate the URL argument string and override the $tip, $text as needed
        $urlp = $this->calcAddUrlParms($vals);

        //Check if href is not indicated
        if($urlp['nolink']) {
            return $urlp['text']; 
        }

        //Generate the base Edit URL
        $url = $this->U($urlp['dst'], $urlp['urlargstring'], $this->LCALL);

        $ret =     "<a href=\"" .     
        $url ."\" >" . 
        $urlp['text'] . 
        "</a>";
        
        return $ret;
    }



    /**
     * Constructs the Edit URL content for a specific line entry
     * Override parents to add unique value.
     *
     * @param   int $i
     *
     * @return  string
     */
    function calcEditUrl($i) 
    {

        $p         = &$this->_params; //???
        $t         = &$this->table;                                
        $key     = $p['_key'];
        $keyval = $t[$i][$key];
        $dt     = Request::$r->_dt;
        
        // For RecurDocumentLister the table can contain a unique
        // document type designated on the URL or it can contain
        // a mixture of the types available so...
        //   get name from current table entry
        //	if name is blank on URL...
        if (!isset($dt) || ($dt=='')) {
            $dt = $t[$i]['DOCID'];
        }

        
        $r             = urlencode($keyval);
        $it         = $p['_entity'];
        $dst         = $this->calcEditDst();
        $rt         = urlencode(ServeCurrentTimestamp());
        $owner         = $this->GetObjectOwnership($i);
        $ownerloc     = $this->GetObjectOwnerLocation($i);
        $noeditview = true;
        if ( $p['_op']['edit'] !='' && $owner >= 0) {
            $text =  $p['_editbutton'];
            $do = 'edit';
            $op = $p['_op']['edit'];

            //Package up the arguments to the url 
            $editurlargs = array(    '.do'         => $do, 
            '.r'         => $r, 
            '.dt'         => urlencode($dt), 
            '.it'         => $it, 
            '.readtime' => $rt, 
            '.op'         => $op);
                                    
            $editvals = array(    'dst'         => $dst, 
              'urlargs'     => $editurlargs, 
              'text'         => $text 
              );
                                
            $noeditview = false;
        } 
        if ( $p['_op']['view'] != '' ) {
            $text     =  GT($this->textMap, 'IA.VIEW');
            $do     = 'view';
            $op     = $p['_op']['view'];
           

            //Package up the arguments to the url 
            $viewurlargs = array(    '.do'         => $do, 
            '.r'         => $r, 
            '.dt'         => urlencode($dt), 
            '.it'        => $it, 
            '.readtime' => $rt, 
            '.op'         => $op);
                                    
            $viewvals = array(    'dst'         => $dst, 
              'urlargs'     => $viewurlargs, 
              'text'         => $text 
              );
                                
            $noeditview = false;
        } 
        if ($noeditview) {
            return " "; // No permission to View or Edit - 'List' perm only.
        }
        //Generate the URL argument string and override the $tip, $text as needed
        /** @noinspection PhpUndefinedVariableInspection */
        $editurlp = $this->calcEditUrlParms($i, $editvals);
        /** @noinspection PhpUndefinedVariableInspection */
        $viewurlp = $this->calcViewUrlParms($i, $viewvals);


        //Generate the base Edit URL
        $editurl = $this->U($editurlp['dst'], $editurlp['urlargstring'], $this->LCALL);
        $viewurl = $this->U($viewurlp['dst'], $viewurlp['urlargstring'], $this->LCALL);

        //Mega Override of base URL for downward slide in as necessary
        if($owner > 0 && $ownerloc) {
            $editurl = $this->_calcSlideUrl($editurl, $ownerloc);
            $viewurl = $this->_calcSlideUrl($viewurl, $ownerloc);
        }

        //Construct the final url to be emitted 
        //Check if href is not indicated
        if ($editurlp['nolink']) {
            $editret = " edittext=\"".$editurlp['text']."\" ";
        }
        else {
            $editret = " edithref=\"" 
            . $editurl 
            . "\" edittext=\""
            . $editurlp['text']
            . "\" ";
        }

        if ($viewurlp['nolink']) {
            $viewret = " viewtext=\"".$viewurlp['text']."\" ";
        }
        else {
            $viewret = " viewhref=\"" 
            . $viewurl 
            . "\" viewtext=\""
            . $viewurlp['text']
            . "\" ";
        }

        //Update the edit and view indexes
        if(isl_strpos($editret, '.do=edit')) {
            $this->editRec = $i;
        }
        if(isl_strpos($viewret, '.do=view')) {
            $this->viewRec = $i;
        }

        //hide the edit link when the NEXTEXECDATE is null
        if($this->table[$i]['NEXTEXECDATE'] == '') {
            $editret = ''; 
        }

        $ret =     "<ev_a tabIndex=\"-1\" ". $editret . $viewret ." > </ev_a>";
        return $ret;
    }

    
    //->function CalcFiltersLite()
    /**
     * Filter for table content to list only 
     * the selected DOCID types.
     * Override parents to add unique value.
     *
     * @return array
     */
    function CalcFiltersLite() 
    {
        $filters = parent::CalcFiltersLite();
        global $gManagerFactory;

        $mod = $this->getEntityMgr()->mod;
        if (is_null($mod)) {
            throw new InvalidArgumentException(
                "RecurDocumentLister::CalcFiltersLite: Required mod parameter is not provided.");
        }
        /** @var DocumentParamsManager $docparMgr */
        $docparMgr = $gManagerFactory->getManager($mod . 'documentparams');
        $doctype = Request::$r->_dt;
        $docpar = $docparMgr->GetBaseLatest($doctype);

        //Added for recurring transactions
        if ($docpar['RECORDNO'] != '') {
            $filters[] = array ('documentparams.docid', '=', $doctype );
        }

        return $filters;
    }



    /**
     * This function overrides the parent function which is used to generate XML
     * candidates for hidden fields. Needed to pass same template name to next
     * invocation of constructors when user clicks next page link.
     *
     * Override parents to add unique value.
     * 
     * @return string An XML structure of the hidden fields.
     */
    function genGlobs() 
    {
        $ret     = parent::genGlobs();        
        $ret     .= "<g name='.dt'>" . util_encode(Request::$r->_dt) . "</g>";
        return $ret;
    }

}    // finish class RecurDocumentLister

