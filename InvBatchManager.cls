<?

/**
 *    FILE:
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */

/**
 * Class InvBatchManager
 */
class InvBatchManager extends EntityManager
{

    /** @var bool $_ismcpEnabled */
    var $_ismcpEnabled;

    /** @var bool $_hasEntityLevelCOGSIETEntries */
    var $_hasEntityLevelCOGSIETEntries;

    /**
     * @param array $params
     */
    function __construct($params = array())
    { 
        parent::__construct($params);
        $this->_ismcpEnabled = IsMCPEnabled(Request::$r->_mod);
        unset($this->_hasEntityLevelCOGSIETEntries);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {
        global $gErr;

        $source = "InvBatch::Add";

        $ok = $this->_QM->beginTrx($source);

        $nextID = $this->GetNextRecordKey();

        if (!isset($nextID) ) {
            $msg = "Could not fetch next system key!";
            $gErr->addIAError('INV-0520', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            $ok = false;
        }

        $values[':record#'] = $values['RECORDNO'] = $nextID;

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create InvBatch record!";
            $gErr->addIAError('INV-0521', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param string $batchTitle
     *
     * @return bool
     */
    private function applyLockOnBatch($batchTitle)
    {

        if (!FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_LOCK_ON_ICBATCH')) {
            return true;
        }

        $ok = true;

        // Select the batch to lock to avoid concurrent updates.
        // oracle will release the lock once the final commit/rollback happens.
        $qry = [];
        $qry[0] = "SELECT record#, total FROM icbatch WHERE cny# =:1 AND title =:2 FOR UPDATE OF total";
        $qry[1] = GetMyCompany();
        $qry[2] = $batchTitle;
        $result = QueryResult($qry);

        if ($result) {
            logToFileDebug('-- ICBatch -- successfully accquired lock for batch -- ' . $batchTitle . ' @ ' . __FILE__ . __FUNCTION__);
        }

        return $ok;
    }

    /**
     * @param array     $glentries
     * @param array     $invbatch
     * @param bool      $directGLPosting
     *
     * @return bool
     */
    function AddGLEntries(&$glentries,&$invbatch, $directGLPosting=false) 
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $glbatchMgr = $gManagerFactory->getManager('glbatch');
        
        // Do we have a glbatch?
        $glbatch = $this->GetGLBatch($invbatch['GLBATCHNO'], $glEntriesMap);

        if (!$glbatch) {
            // Create the batch
            // Get the values
            $ok = $ok && $this->CreateGLBatch($invbatch, $glbatch, $directGLPosting);
        }

        if ($ok) {
            $currEntries = [];
            // Escaping IET entries not needed for computing further
            foreach ($glbatch['ENTRIES'] AS $key => $glentry) {
                if (isset($glentry['PARENTGLENTRYKEY']) && isset($glentry['IETYPE'])
                    && in_array($glentry['IETYPE'], ['p', 'r'])) {
                    continue;
                }
                $currEntries[$key] = $glentry;
            }

            $glbatch['ENTRIES'] = $currEntries;

            $locMgr = $gManagerFactory->getManager('location');
            $deptMgr = $gManagerFactory->getManager('department');
            $acctMgr = $gManagerFactory->getManager('glaccount');

            $locationMap = array();
            $departmentMap = array();
            $accountMap = array();
            
            $newEntries = array();
            foreach ($glentries as $key => $entry) {

                $glentries[$key]['DOCENTRY_INFO'] = $glentries[$key]['DOCENTRY_INFO'] ?? [];
                // requires translation            
                if ( $entry['GLACCOUNTKEY'] ) {
                    list($acctId) = explode('--', $entry['GLACCOUNTKEY']);

                    if ( !$accountMap[$acctId] ) {
                        $params = array(
                            'selects' => array('RECORDNO'),
                            'filters' => array(array(array('ACCOUNTNO', '=', $acctId))),
                        );
                        $recs = $acctMgr->GetList($params);

                        if ( !isset($recs[0]['RECORDNO']) ) {
                            $msg = "Invalid Account " . $acctId . " selected";
                            $corr = "Pick a valid account.";
                            $gErr->addIAError('INV-0522', __FILE__ . ':' . __LINE__,
                             $msg,['ACCT_ID'=>$acctId],
                             '', [],
                             $corr,[]);
                            $ok = false;
                        }
                        $accountMap[$acctId] = $recs[0]['RECORDNO'];
                    }

                    $entry['ACCOUNTKEY'] = $accountMap[$acctId];                    
                }
            
                if (  isset($entry['LOCATION#'] ) && $entry['LOCATION#']!=='') {
                    list($locId) = explode('--', $entry['LOCATION#']);

                    if ( !$locationMap[$locId] ) {
                        $params = array(
                            'selects' => array('RECORD#'),
                            'filters' => array(array(array('LOCATIONID', '=', $locId), array('STATUS', '=', 'active'))),
                            'usemst' => true,
                        );
                        $recs = $locMgr->GetList($params);

                        if ( !isset($recs[0]['RECORD#']) ) {
                            $msg = "Invalid Location " . $locId . " selected";
                            $corr = "Pick a valid Location.";
                            $gErr->addIAError('INV-0523', __FILE__ . ':' . __LINE__,
                             $msg,['LOC_ID'=>$locId],
                              '',[],
                              $corr,[]);
                            $ok = false;
                        }
                        $locationMap[$locId] = $recs[0]['RECORD#'];
                    }

                    $entry['LOCATION#'] = $locationMap[$locId];                                    
                }
                
                if ( isset($entry['DEPT#']) && $entry['DEPT#'] !=='' ) {
                    list($deptId) = explode('--', $entry['DEPT#']);

                    if ( !$departmentMap[$deptId] ) {
                        $params = array(
                            'selects' => array('RECORD#'),
                            'filters' => array(array(array('DEPARTMENTID', '=', $deptId), array('STATUS', '=', 'active'))),
                        );
                        $recs = $deptMgr->GetList($params);

                        if ( !isset($recs[0]['RECORD#']) ) {
                            $msg = "Invalid Department " . $deptId . " selected";
                            $corr = "Pick a valid Department.";
                            $gErr->addIAError('INV-0524', __FILE__ . ':' . __LINE__,
                            $msg,['DEPT_ID'=>$deptId],
                            '',[],
                            $corr,[]);
                            $ok = false;
                        }
                        $departmentMap[$deptId] = $recs[0]['RECORD#'];
                    }

                    $entry['DEPT#'] = $departmentMap[$deptId];                    
                    
                }
                
                $sign = ($entry['AMOUNT']<0) ? -1 : 1;
                
                // populate original transaction type
                if ( is_array($glentries[$key]['DOCENTRY_INFO']) ) {
                    foreach ($glentries[$key]['DOCENTRY_INFO'] as $dekey => $dentry) {
                        $glentries[$key]['DOCENTRY_INFO'][$dekey]['ORIG_TRTYPE'] = $entry['DR_CR'];
                    }
                }

                if ( is_array($glentries[$key]['SUBTOTAL_INFO']) ) {
                    foreach ($glentries[$key]['SUBTOTAL_INFO'] as $dekey => $dentry) {
                        $glentries[$key]['SUBTOTAL_INFO'][$dekey]['ORIG_TRTYPE'] = $entry['DR_CR'];
                    }
                }
                
                $entry['DR_CR'] = $entry['DR_CR'] * $sign;

                /** @var string $glBatchDate */
                $glBatchDate = $glbatch['BATCH_DATE'];
                GLBatchManager::buildGLEntryValues($glBatchDate, $entry, $newEntry);

                $i = 0;
                $found = false;
                while (isset($glEntriesMap[$newEntry['GLGROUPKEY']][$i])) {
                    
                    $currkey = $glEntriesMap[$newEntry['GLGROUPKEY']][$i]['RECORDNO'];

                    // lets not touch existing entries with -ve values
                    if ( $currEntries[$currkey]['LEGACY'] == 'T') {
                        $i++;
                        continue;
                    }
                    
                    $currEntries[$currkey]['LINE_NO'] = $glEntriesMap[$newEntry['GLGROUPKEY']][$i]['LINE_NO'];
                    
                    $currEntries[$currkey]['AMOUNT'] = ibcadd(
                        $currEntries[$currkey]['AMOUNT'],
                        $newEntry['AMOUNT'], 2, true
                    );
                    $currEntries[$currkey]['TRX_AMOUNT'] = ibcadd(
                        $currEntries[$currkey]['TRX_AMOUNT'],
                        $newEntry['TRX_AMOUNT'], 2, true
                    );
                    
                    $found = true;
                    break;
                    
                }
                
                if ( !$found ) {// not found                 
                    $newEntries[] = $newEntry;                                        
                }
                
                $glentries[$key]['GLGROUPKEY'] = $newEntry['GLGROUPKEY'];
            }    
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $currEntries =  INTACCTarray_merge($currEntries, $newEntries);

        $currEntries = $this->AggregateByGLGroupKey($currEntries);
        $glbatch['ENTRIES'] = $currEntries;

        // Enforce platform relationships
        if ( $ok && !util_isPlatformDisabled() ) {
            $glentryMgr = $gManagerFactory->getManager('glentry');
            foreach( $glbatch['ENTRIES'] as $index => $glentry) {
                if (!$glentryMgr->validateAndUpdateDimensionRelationships($glbatch['ENTRIES'][$index])) {
                    $ok = false;
                }
            }
            $tdPeriod = $this->GetBatchPeriod($invbatch['DOCTYPE']);
            if (!$ok && ($tdPeriod !== 'E')) {
                $gErr->addIAError(
                    'INV-0132',
                    __FILE__ . ':' . __LINE__,
                    "The dimension relationship error could be resulting from the associated GL
                    transaction summary rather than this individual transaction.",
                    [],
                    "Either adjust the dimension relationships or change the summary frequency to
                    one-per-transaction, then try again.",
                    []
                );
            }
        }

        $ok = $ok && $glbatchMgr->set($glbatch);
        
        // --------------------- NEW CODE
        $invbatch['_GLBATCH'] = $glbatch;
        
        $glentryrecs = &$glbatch['GLGROUPMAP']; 
        foreach ($glentries as $key => $entry) {
            $i = 0;
            while (isset($glentryrecs[$entry['GLGROUPKEY']][$i])) {
                // skip existing entries which has -ve amounts
                if ( $glentryrecs[$entry['GLGROUPKEY']][$i]['LEGACY'] == 'T') {
                    $i++;
                    continue;
                }
                $glentries[$key]['GLKEY'] = $glentryrecs[$entry['GLGROUPKEY']][$i]['RECORD#'];
                break;
            }
        }
                
        return $ok;
    }

    
    /**
    * function to summarize GL entries
    *
    * @param  array &$entries GL entries
     *
    * @return array $newEntries
    */
    function AggregateByGLGroupKey(&$entries) 
    {

        $groupKeys = array();
        $newEntries = array();
        $legacyEntries = array();
        foreach ($entries as $entry) {
            if($entry['LEGACY'] == 'T') {
                $legacyEntries[] = $entry;
                continue;
            }
            if (!$groupKeys[$entry['GLGROUPKEY']]) {
                $groupKeys[$entry['GLGROUPKEY']] = true;
                $newEntries[$entry['GLGROUPKEY']] = $entry;
            } else {
                $newEntries[$entry['GLGROUPKEY']]['TRX_AMOUNT'] = ibcadd(
                    $entry['TRX_AMOUNT'], 
                    $newEntries[$entry['GLGROUPKEY']]['TRX_AMOUNT'], 2, true
                );
                $newEntries[$entry['GLGROUPKEY']]['AMOUNT'] = ibcadd(
                    $entry['AMOUNT'], 
                    $newEntries[$entry['GLGROUPKEY']]['AMOUNT'], 2, true
                );               
            }            
        }
        $newEntries = array_values($newEntries);        
        // 
        // always first param must be newEntries followed by legacy entries 
        $newEntries =  INTACCTarray_merge($newEntries, $legacyEntries);
        return $newEntries;
    }


    /**
     * Generate the batch date
     *
     * @param string $doctype
     * @param string $docdate
     *
     * @return string
     */
    function GetBatchDate($doctype, $docdate)
    {

        $per = $this->GetBatchPeriod($doctype);
                
        // GET THE CORRECT BATCH FOR DATE
        $batchDateFunctions = array(
            'E' => '',
            'D' => 'GetBatchNameToday',
            'W' => 'GetBatchNameWeek',
            'M' => 'GetBatchNameMonth'
        );

        $function = $batchDateFunctions[$per];

        if (!$function) {
            // Create new batchdate
            $batchdate = $docdate;
        }
        else {
            // Calculate the batchdate
            include_once 'backend_autobatch.inc';
            /** @noinspection PhpUndefinedVariableInspection */
            $function($docdate, $batchdate);
        }

        return $batchdate;
    }
    

    /**
     * Generate the batch title
     *
     * @param string    $doctype
     * @param string    $docdate
     * @param bool      $directGLPosting
     * @param string    $currency
     *
     * @return string
     */
    function GetBatchTitle($doctype,$docdate, $directGLPosting=false, $currency = '') 
    {

        $per = $this->GetBatchPeriod($doctype);
        
        // GET THE CORRECT BATCH FOR DATE
        $batchDateFunctions = array(
        'E' => '',
        'D' => 'GetBatchNameToday',
        'W' => 'GetBatchNameWeek',
        'M' => 'GetBatchNameMonth'
        );

        $mod = Request::$r->_mod;

        if ( $directGLPosting ) {
            if ( $mod == 'so' ) {
                $batchText = ' Sales';

                //
                // for additional GL posting create new batch title
                //
                $mgr = Globals::$g->gManagerFactory->getManager('documentparams');
                $res = $mgr->GetList([
                    'selects' => ['RECORDNO', 'POSTTOGL', 'UPDGL'],
                    'filters' => [[['DOCID', '=', $doctype]]],
                ]);
                $res = $res[0];

                if (!empty($res)) {
                    // In Order Entry 'Additional GL posting is enabled only if Direct GL Posting is not selected
                    // return the Journal for additional GL posting with porperty ends with '_ADDJOURNAL'
                    if ($res['UPDGL'] != 'G'
                        && $res['POSTTOGL'] == 'true') {
                        $batchText = $batchText . ' Additional';
                    }
                }

            }elseif ( $mod == 'po' ) {
                $batchText = ' Purchase';
            }
        }

        $function = $batchDateFunctions[$per];

        // In entity level transaction If we have the IET entries then we should not genrate the title in Entity level
        if( IsMultiEntityCompany() && GetContextLocation() && !$this->hasEntityLevelIETEntries() ) {
            $location = GetContextLocationDetails();
            $doctype .= " - " . $location['LOCATION_NO'] ;
        }
        
        // Only for a Atlas company and that too a batch created at the root append the currency to the batch title.
        if ($currency != '' && IsMCMESubscribed() && !GetContextLocation() ) {
            $doctype .= " (".$currency.")";    
        }
        

        if (!$function) {
            // Create new
            $time = time();
            /** @noinspection PhpUndefinedVariableInspection */
            $title = "$doctype: " . FormatDateForDisplay(date('m/d/Y', $time)) . " " . date('H:i:s', $time) . ":" . rand(0, 9999) . $batchText . " Batch";
        }
        else {
            // Calculate the title
            include_once 'backend_autobatch.inc';
            /** @noinspection PhpUndefinedVariableInspection */
            $title = $doctype . ': ' . $function($docdate, $batchdate) . $batchText;
        }
        return $title;
    }


    /**
     * @param string    $docdate
     * @param string    $doctype
     * @param array|bool     $invbatch
     * @param bool      $directGLPosting
     *
     * @return bool
     */
    function GetBatch($docdate, $doctype, &$invbatch, $directGLPosting=false)
    {

        $title = $this->GetBatchTitle($doctype, $docdate, $directGLPosting);
        $glbatch = array();

        // Does that batch exist?
        $invbatch = $this->get($title);

        if (isset($invbatch) && $invbatch) {
            //epp("I already exist");
            //eppp($invbatch);
            $this->applyLockOnBatch($title);

            return true;
        }
        else {

            // It doesn't exist, so create the batch
            $batchdate = $this->GetBatchDate($doctype, $docdate);
            $ok = $this->BuildNewBatchValues($title, $doctype, $batchdate, $invbatch);
            $ok = $ok && $this->CreateGLBatch($invbatch, $glbatch, $directGLPosting);

            if ($ok && !$this->add($invbatch)) {
                return false;
            }
        }
        $invbatch['RECORDNO'] = $invbatch[':record#'];

        return $ok;
    }


    /**
     * @param array $invbatch
     * @param array $glbatch
     * @param bool  $directGLPosting
     *
     * @return bool
     */
    function CreateGLBatch(&$invbatch,&$glbatch, $directGLPosting=false) 
    {
        $gErr = Globals::$g->gErr;

        
        $glBatchMgr = Globals::$g->gManagerFactory->getManager('glbatch');
        //$glBatchMgr->dontvalidate = true;
        $ok = true;

        $journal = $this->GetJournalFromDocID($invbatch['DOCTYPE'], $directGLPosting);

        if ($journal == '') {
            $msg = "Unable to get Journal for transaction type: " . $invbatch['DOCTYPE'];
            $gErr->addIAError(
                'INV-0525',
                __FILE__.':'.__LINE__,
                $msg,['INVBATCH_DOCTYPE'=>$invbatch['DOCTYPE']],
                'Please specify a journal for '. $invbatch['DOCTYPE'] . ' in Activities > Setup',
                ['INVBATCH_DOCTYPE'=>$invbatch['DOCTYPE']],
                'A valid journal is required to post gl entries for this transaction.',
                []);
            $ok = false;
        }

        // getting mod from request should be cleaned up with SCM refactor
        $mod = Request::$r->_mod;
        $str = 'k' . isl_strtoupper($mod) . 'id';
        global ${$str};
        $module = $$str;
        
        $glBatchValues = array(
            'BATCH_TITLE' => $invbatch['TITLE'],            
            'JOURNAL' => $journal,
            'BATCH_DATE' => $invbatch['WHENCREATED'],
            'MODULE' => $module,                        
            'ENTRIES' => array()
        );                
        
        $ok = $ok && $glBatchMgr->add($glBatchValues);

        if ($ok) {
            $glbatch = $glBatchValues;
            $invbatch['GLBATCHNO'] = $glBatchValues['RECORDNO'];
        }

        return $ok;
    }

    /**
     * @param int       $glbatchnumber
     * @param array     $glEntriesMap
     *
     * @return array
     */
    function GetGLBatch($glbatchnumber, &$glEntriesMap=array())
    {
        
        $glbatchMgr = Globals::$g->gManagerFactory->getManager('glbatch');
        
        $params = array(
            'filters' => array(
                array(
                    array(
                        'RECORDNO', '=', $glbatchnumber
                    ),
                 )
             ),            
             'SUBS_TABLE' => array(
                 'glbatch' => 'glbatchmst'
             ),
         );
         
         $existing_batch = $glbatchMgr->GetList($params); 
         $existing_batch = $existing_batch[0];
         
        // getting glentry map with dimension keys     
        if ( isset($existing_batch['RECORDNO']) && $existing_batch['RECORDNO'] != '' ) {           
            $glbatchMgr->getExistingGLGroupMap($existing_batch, $glEntriesMap);
            $existing_batch['ENTRIES'] = $existing_batch['EXISTING_ENTRIES'];
        }
        
         return $existing_batch;

    }


    /**
     * @param string    $title
     * @param string    $doctype
     * @param string    $docdate
     * @param array     $values
     *
     * @return bool
     */
    function BuildNewBatchValues($title, $doctype,$docdate,&$values) 
    {
        global $kINVid;
        $values = array (
        'TITLE'            => $title,
        'DOCTYPE'         => $doctype,
        'WHENCREATED'     => $docdate,
        'STATUS'        => 'active',
        'MODULEKEY'        => $kINVid,
        ':open'            => 'T'
        );
        return true;
    }

    /**
     * @param string    $doctype
     *
     * @return string
     */
    function GetBatchPeriod($doctype) 
    {
        // Get my preference
        $doc4path = str_replace(' ', '_', $doctype);
        
        $preference = "DOCUMENT.${doc4path}_BATCH";

        $mod = &Request::$r->_mod;
        if ($mod == '') {
            $mod = 'SO';
        }
        $str = 'k' . isl_strtoupper($mod) . 'id';
        global ${$str};
        $module= $$str;

        $period = $this->_MM->GetPreference($preference, $module);
        if ($period === false || $period == null) {
            $period = 'D';  // default is daily
        }
        return $period;
    }

    /**
     * @param string    $doctype
     * @param bool      $directGLPosting
     *
     * @return string
     */
    function GetJournalFromDocID($doctype, $directGLPosting=false) 
    {
        // Create the GLBatch
        $doc4path = str_replace(' ', '_', $doctype);

        // $directGLPosting is true in following cases
        // 1. Order Entry TD > Transaction Posting is configured
        //      a. General Ledger
        //      b. Enable additional posting is True (Enabled)
        //
        //  2. Purchasing TD > Transaction Posting > General Ledger
        if ( $directGLPosting ) {
            //
            // Journal can be either General Ledger -- or -- Additional L posting
            $prop = 'DOCUMENT.' . $doc4path . '_PRINVJOURNAL';

            $mgr = Globals::$g->gManagerFactory->getManager('documentparams');
            $res = $mgr->GetList([
                'selects' => ['RECORDNO', 'POSTTOGL', 'UPDGL', 'SALE_PUR_TRANS'],
                'filters' => [[['DOCID', '=', $doctype]]],
            ]);
            $res = $res[0];

            if (!empty($res)) {
                // In Order Entry 'Additional GL posting is enabled only if Direct GL Posting is not selected
                // return the Journal for additional GL posting with porperty ends with '_ADDJOURNAL'
                if ($res['SALE_PUR_TRANS'] == 'Sale'
                    && $res['UPDGL'] != 'G'
                    && $res['POSTTOGL'] == 'true') {
                    $prop = 'DOCUMENT.' . $doc4path . '_ADDJOURNAL';
                }
            }
        } else {
            $prop = 'DOCUMENT.'.$doc4path.'_JOURNAL';
        }

        $mod = Request::$r->_mod;
        $str = 'k' . isl_strtoupper($mod) . 'id';
        global ${$str};
        $module= $$str;

        // Get my preference
        $journal = $this->_MM->GetPreference($prop, $module);
        return $journal;
    }


    /**
     * @param array $docValues
     * @param array $glentries
     * @param bool  $directGLPosting
     *
     * @return bool
     */
    function RemoveGLEntries(&$docValues, $glentries, $directGLPosting=false) 
    {

        $ok = true;

        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $batchType       = '';
        $invbatchno      = 0;
        $documentArray   = [];
        $glentryKey      = [];

        if ( $directGLPosting ) {
            if (($docValues['PRINVBATCHKEY'] ?? '') != '') {
                $invbatchno = $docValues['PRINVBATCHKEY'];
                $batchType = 'DIRECTGL';
            } elseif (($docValues['ADDGLBATCHKEY'] ?? '') != '') {
                $invbatchno = $docValues['ADDGLBATCHKEY'];
                $batchType = 'ADDGL';
            } else {
                $invbatchno = $docValues['INVBATCHKEY'] ?? '';
                $batchType = 'INVGL';
            }
        } else {
            $invbatchno = $docValues['INVBATCHKEY'];
            $batchType = 'INVGL';
        }

        $invbatch = $this->DoQuery('QRY_INVBATCH_SELECT_RAW_UID', array($invbatchno));
        $invbatch = $invbatch[0];

        if ($invbatch) {
            $title = $invbatch['TITLE'];
            $this->applyLockOnBatch($title);

            $glbatchMgr = $gManagerFactory->getManager('glbatch');

            $glbatch = $this->GetGLBatch($invbatch['GLBATCHKEY'], $glEntriesMap);

            if ($glbatch) {

                $zeroAmtEntries = [];

                $locMgr = $gManagerFactory->getManager('location');
                $deptMgr = $gManagerFactory->getManager('department');
                $acctMgr = $gManagerFactory->getManager('glaccount');
                $locationMap = array();
                $departmentMap = array();
                $accountMap = array();


                $currEntries = [];
                // Escaping IET entries not needed for computing further
                foreach ($glbatch['ENTRIES'] AS $key => $glentry) {
                    if (isset($glentry['PARENTGLENTRYKEY']) && isset($glentry['IETYPE'])
                        && in_array($glentry['IETYPE'], ['p', 'r'])) {
                        continue;
                    }
                    $currEntries[$key] = $glentry;
                }

                $glbatch['ENTRIES'] = $currEntries;

                foreach ( $glentries as $entry) {
                    if (isset($entry['RECORD#']) && ($entry['RECORD#'] != 0)) {
                        $glentryKey[] = $entry['RECORD#'];
                    }
                }

                foreach ( $glentries as $entry) {

                    // requires translation            
                    if ( $entry['GLACCOUNTKEY'] ) {
                        list($acctId) = explode('--', $entry['GLACCOUNTKEY']);

                        if ( !$accountMap[$acctId] ) {
                            $params = array(
                                'selects' => array('RECORDNO'),
                                'filters' => array(array(array('ACCOUNTNO', '=', $acctId))),
                            );
                            $recs = $acctMgr->GetList($params);

                            if ( !isset($recs[0]['RECORDNO']) ) {
                                $msg = "Invalid Account " . $acctId . " selected";
                                $corr = "Pick a valid account.";
                                $gErr->addIAError('INV-0526', __FILE__ . ':' . __LINE__,
                                 $msg,['ACCT_ID'=>$acctId],
                                 '',[],
                                 $corr,[]);
                                $ok = false;
                            }
                            $accountMap[$acctId] = $recs[0]['RECORDNO'];
                        }

                        $entry['ACCOUNTKEY'] = $accountMap[$acctId];                    
                    }

                    if ( $entry['LOCATION#'] ) {
                        list($locId) = explode('--', $entry['LOCATION#']);

                        if ( !$locationMap[$locId] ) {
                            $params = array(
                                'selects' => array('RECORD#'),
                                'filters' => array(
                                    array(array('LOCATIONID', '=', $locId), array('STATUS', '=', 'active'))
                                ),
                                'usemst' => true,
                            );
                            $recs = $locMgr->GetList($params);

                            if ( !isset($recs[0]['RECORD#']) ) {
                                $msg = "Invalid Location " . $locId . " selected";
                                $corr = "Pick a valid Location.";
                                $gErr->addIAError('INV-0680', __FILE__ . ':' . __LINE__,
                                $msg,['LOC_ID'=>$locId],
                                '',[], $corr,[]);
                                $ok = false;
                            }
                            $locationMap[$locId] = $recs[0]['RECORD#'];
                        }

                        $entry['LOCATION#'] = $locationMap[$locId];                                    
                    }

                    if ( $entry['DEPT#'] ) {
                        list($deptId) = explode('--', $entry['DEPT#']);

                        if ( !$departmentMap[$deptId] ) {
                            $params = array(
                                'selects' => array('RECORD#'),
                                'filters' => array(
                                    array(array('DEPARTMENTID', '=', $deptId), array('STATUS', '=', 'active'))
                                ),
                            );
                            $recs = $deptMgr->GetList($params);

                            if ( !isset($recs[0]['RECORD#']) ) {
                                $msg = "Invalid Department " . $deptId . " selected";
                                $corr = "Pick a valid Department.";
                                $gErr->addIAError('INV-0681', __FILE__ . ':' . __LINE__,
                                $msg,['DEPT_ID'=>$deptId],
                                '',[],
                                $corr,[]);
                                $ok = false;
                            }
                            $departmentMap[$deptId] = $recs[0]['RECORD#'];
                        }

                        $entry['DEPT#'] = $departmentMap[$deptId];                    
                        

                    }
                    
                    $sign = ($entry['AMOUNT']<0) ? -1 : 1;  

                    if(!$directGLPosting) {
                        $entry['DR_CR'] = $entry['DR_CR'] * $sign;
                    }

                    /** @var string $glBatchDate */
                    $glBatchDate = $glbatch['BATCH_DATE'];
                    GLBatchManager::buildGLEntryValues($glBatchDate, $entry, $oldEntry);
                    
                    $currkey = '';
                    if ( $entry['RECORD#']) {
                        $currkey = $entry['RECORD#'];
                    } else {
                         // costing entries
                        if ($glEntriesMap[$oldEntry['GLGROUPKEY']]) {
                            $currkey = $glEntriesMap[$oldEntry['GLGROUPKEY']][0]['RECORDNO'];
                        }
                    }
                    
                    if ($currkey) {// found          
                        
                        // handle old entries before gl refactor
                        if ( $currEntries[$currkey]['LEGACY'] == 'T') {
                            $oldEntry['AMOUNT'] = $oldEntry['AMOUNT'] * $sign;
                            $oldEntry['TRX_AMOUNT'] = $oldEntry['TRX_AMOUNT'] * $sign;
                        }
                        // $currEntries[$currkey]['LINE_NO'] = $glEntriesMap[$oldEntry['GLGROUPKEY']]['LINE_NO'];

                        // Does the amount go negative?  Is there an alternate amount?
                        // NOTE: It is rare to go negative!!  But it does happen, because sometimes tax amounts
                        //      round poorly.  see InvSubtotals::DeleteInvSubtotals()
                        $t = ibcsub(
                            $currEntries[$currkey]['AMOUNT'],
                            $oldEntry['AMOUNT'], 2, true
                        );

                        if (($t < 0) && isset($entry['ALTERNATE']) && ($entry['ALTERNATE'] > 0)) {
                            $t = ibcsub(
                                $currEntries[$currkey]['AMOUNT'],
                                $entry['ALTERNATE'], 2, true
                            );
                        }
                        $currEntries[$currkey]['AMOUNT'] = $t;

                        // Same for trx_amount.  If there IS an alternate, it works for both amount and trx_amount
                        $t = ibcsub(
                            $currEntries[$currkey]['TRX_AMOUNT'],
                            $oldEntry['TRX_AMOUNT'], 2, true
                        );
                        if (($t < 0) && isset($entry['ALTERNATE']) && ($entry['ALTERNATE'] > 0)) {
                            $ta = $entry['ALTERNATE'];
                            if (isset($oldEntry['EXCHANGE_RATE']) && ($oldEntry['EXCHANGE_RATE'] != 1) && ($oldEntry['EXCHANGE_RATE'] != 0)) {
                                $ta = ibcdiv($entry['ALTERNATE'], $oldEntry['EXCHANGE_RATE'], 2, true);
                            }
                            $t = ibcsub(
                                $currEntries[$currkey]['TRX_AMOUNT'],
                                $ta, 2, true
                            );
                        }
                        $currEntries[$currkey]['TRX_AMOUNT'] = $t;
                        
                        if ($currEntries[$currkey]['AMOUNT'] == 0) {
                            $zeroAmtEntries[] = $currEntries[$currkey];
                            if(empty($documentArray)){
                                $qry = "select  COUNT(1) documentcount, glentrykey from (";
                                $qry .= "select dochdrkey, glentrykey, count(1) from deglresolve where cny#=:1 ";
                                $qry = PrepINClauseStmt($qry, $glentryKey, " AND glentrykey ");
                                $qry = $qry." GROUP BY glentrykey, dochdrkey ) GROUP BY glentrykey";
                                $stmt = array($qry, GetMyCompany());
                                $documentResult = QueryResult($stmt);
                                foreach (($documentResult ?? []) as $doc){
                                    $documentArray[$doc['GLENTRYKEY']]  = $doc['DOCUMENTCOUNT'];
                                }
                            }
                            if(!isset($documentArray[$currkey]) || $documentArray[$currkey] <= 1){
                                unset($currEntries[$currkey]);
                            }
                        }

                    }
                    else {
                        // should not reach here                        
                        $msg = "Could not find the Existing GL Entry";
                        $corr = "Please Contact Customer Support.";
                        $gErr->addIAError('INV-0527', __FILE__ . ':' . __LINE__,
                            $msg,
                            [],
                            '',
                            [],
                            $corr,
                            []
                        );
                        $ok = false;
                    }

                } 

                if (count($currEntries) > 0) {

                    $glbatch['ENTRIES'] = $currEntries;

                    $ok = $ok && $glbatchMgr->set($glbatch);
                    
                } else {

                    $qry1 = '';
                    $qry2 = '';
                    switch($batchType){
                        case 'DIRECTGL' :
                            $qry1 = 'QRY_DOCUMENT_SET_PRINVBATCHKEY_NULL';
                            $qry2 = 'QRY_DOCUMENT_CNT_BY_PRINVBATCHKEY';
                            break;

                        case 'ADDGL' :
                            $qry1 = 'QRY_DOCUMENT_SET_ADDGLBATCHKEY_NULL';
                            $qry2 = 'QRY_DOCUMENT_CNT_BY_ADDGLBATCHKEY';
                            break;

                        case 'INVGL' :
                            $qry1 = 'QRY_DOCUMENT_SET_INVBATCHKEY_NULL';
                            $qry2 = 'QRY_DOCUMENT_CNT_BY_INVBATCHKEY';
                            break;
                    }

                    $ok = $ok && $this->DoQuery($qry1, array($docValues['DOCID']));

                    //Get all dochdr id's
                    $cnt = $this->DoQuery($qry2, array($invbatchno));

                    if ($cnt[0]['CNT'] == 0) {
                        $ok = $ok && $this->Delete($title);
                        $docValues['INVBATCHKEY'] = '';
                        $ok = $ok && $glbatchMgr->Delete($invbatch['GLBATCHKEY'], true);
                    } else if ($cnt[0]['CNT'] > 0) {
                        $glbatch['ENTRIES'] = $zeroAmtEntries;
                        $ok = $ok && $glbatchMgr->set($glbatch);
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * @param array $glentries
     *
     * @return bool
     */
    public function hasEntityLevelIETEntries($glentries = [])
    {
        if (IsMultiEntityCompany() && GetContextLocation()
            && count($glentries) > 0
            && empty($this->_hasEntityLevelCOGSIETEntries)) {
            $this->_hasEntityLevelCOGSIETEntries = false;
            $locMgr = Globals::$g->gManagerFactory->getManager('locationentity');
            $map = $locMgr->GetEntityLocationMap();
            $mapbyID = $locMgr->GetEntityLocationMapbyID();

            // Check if their is any need to create IET's
            foreach ($glentries as $glentry) {
                // IET entries should be created only if BASELOCATION is set.
                // for now BASELOCATION is set only in case of COGS.
                // refer to SCMSubLedgerHandler::processCOGSGLEntries
                if (isset($glentry['BASELOCATION']) && !empty($glentry['BASELOCATION'])) {
                    $targetLocation = $map[$glentry['BASELOCATION']]['ENTITY#'];
                    $sourceLocation = $mapbyID[$glentry['LOCATION#']]['ENTITY#'];

                    // IET entries will be created if,
                    // warehouse->location->baselocation and glentry->location->baselocation is different
                    if (!empty($targetLocation) && !empty($sourceLocation) && $targetLocation != $sourceLocation) {
                        $this->_hasEntityLevelCOGSIETEntries = true;
                        break;
                    }
                }
            }
        }

        return $this->_hasEntityLevelCOGSIETEntries;
    }

    /**
     * @param int $invBatchKey
     *
     * @return bool
     */
    public function needToSwitchToRootContext($invBatchKey)
    {
        $needToSwitchToRootContext = false;

        if (empty($invBatchKey)) {
            return $needToSwitchToRootContext;
        }

        if (IsMultiEntityCompany() && GetContextLocation()) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $params = [
                'selects' => ['GLBATCHNO'],
                'filters' => [[['RECORDNO', '=', $invBatchKey]]],
            ];
            $invBatchMgr = $gManagerFactory->getManager('invbatch');
            $invbatch = $invBatchMgr->GetList($params);
            $invbatch = $invbatch[0] ?? [];

            if (isset($invbatch['GLBATCHNO']) && !empty($invbatch['GLBATCHNO'])) {
                $params = [
                    'selects' => ['LOCATIONKEY'],
                    'filters' => [[['RECORDNO', '=', $invbatch['GLBATCHNO']]]],
                    'usemst' => true,
                ];
                $glBatchMgr = $gManagerFactory->getManager('glbatch');
                $existing_batch = $glBatchMgr->GetList($params);
                $existing_batch = $existing_batch[0] ?? [];

                if (empty($existing_batch['LOCATIONKEY'])) {
                    $needToSwitchToRootContext = true;
                }
            }
        }

        return $needToSwitchToRootContext;
    }

}
