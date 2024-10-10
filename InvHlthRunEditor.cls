<?php /** @noinspection SuspiciousLoopInspection */

/**
 * Class InvHlthRunEditor
 *
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000-2009 Intacct Corporation, All Rights Reserved
 */

include_once 'InvHlthRunManager.cls';

/**
 * @category  Cls
 * @package   Source/common
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000-2009 Intacct Corporation, All Rights Reserved
 */

/**
 * Class InvHlthRunEditor
 */
class InvHlthRunEditor extends FormEditor
{
    // Class variables
    /** @var null|string  $module*/
    private $module;

    /** @var null|string $sourceobject */
    private $sourceobject;

    /**
     * @param array $_params
     */

    public function __construct($_params)
    {
        //server side tokens
        $localTokens =[
            "IA.RUN_ON_DATE_TIME",
            "IA.PARTIAL_RESULTS",
            "IA.RUN_NOW",
            "IA.LOADING",
            "IA.ALL",
            "IA.IN_OPEN_PERIODS_ONLY",
            "IA.IN_OPEN_AND_CLOSED_PERIODS",
            "IA.YES",
            'IA.SCHEDULED_TO_RUN_DELETE_TO_STOP',
            'IA.COSTING_ISSUES',
            'IA.NEGATIVE_INVENTORY_WARNINGS',
            'IA.NO_OF_NEG_QTY_FOUND',
            'IA.NUMBER_FIXED',
            'IA.GL_ENTRIES_NOT_UPDATED_BECAUSE_OF',
            'IA.SHOW_ALL_TRANSACTIONS',
            'IA.COSTING_ERROR_TRANSACTIONS_ONLY',
            'IA.QUICK_ANALYZED',
            'IA.COSTING_UPDATED',
            'IA.ANALYZED',
            'IA.UPDATED',
            'IA.SCHEDULED',
            'IA.STD_COST_CHANGE'
        ];
        $this->additionalTokens = array_merge($this->additionalTokens, $localTokens);
        parent::__construct($_params);
        $this->sourceobject = &Request::$r->sourceobject;
        $this->module = &Request::$r->module;

        $this->addRunHealthCheckAction();
        $this->addFixHealthAction();
    }

    /**
     * @return InvHlthRunManager
     */
    public function getEntityMgr()
    {
        assert($this->entityMgr instanceof InvHlthRunManager);
        return $this->entityMgr;
    }

    /**
     * JS tokens
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        array_push( $this->textTokens
            , "IA.INVENTORY_VALUATION_RECENT_EVENTS"
            ,"IA.SAVE_SCHEDULE"
            ,"IA.RUN_NOW"
            ,"IA.NO_COST_CHANGE_PENDING"
            ,"IA.MIV_CHANGE_PUR_ADJ_BK_TI"
            ,"IA.MIV_CHANGE_SK_DISASSEM"
            ,"IA.MIV_CHANGE_STD_COST_CHANGE"
            ,"IA.MIV_CHANGE_TRANS_DELETE"
            ,"IA.MIV_CHANGE_COST_NOT_RUN"
            ,"IA.MIV_CHANGE_INV_START_DATE"
            ,"IA.WAREHOUSE_TRANSFER_IN"
            ,"IA.PARTIAL_RESULTS"
            ,"IA.MIV_UPDATE_ENTITY_HEALTH_CHECK_CONFIRM"
            ,"IA.MIV_FIX_HEALTH_CHECK_CONFIRM"
            ,"IA.DOWNLOAD"
            ,"IA.LOADING");
        return parent::getFormTokens();
    }
    /**
     * transformBizObjectToView
     *
     * @param array &$obj parameters
     *
     * @return bool  true on success and false on failure - make sure an error is raised in case of failure
     */
    protected function transformBizObjectToView(&$obj)
    {
            // default the as-of date to the start of the first open date
        if ($obj['FIXASOFDATE'] == '') {
            $obj['FIXASOFDATE'] = GetCompanyOpenDate(); // as-of the first open date
        }

        // Turn on all the options by default
        if ($obj['COSTMETHODCHECK'] == '') {
            $obj['COSTMETHODCHECK'] = 'Average,Standard,FIFO,LIFO';
        }

        if ($obj['SELECTTOFIX'] == '') {
            $obj['SELECTTOFIX'] = 'INVVALDATA, COGSDATA';  // ,VERBOSE
        }

        if ( $this->kShowNewState === $this->getState() ) {
            if (($obj['NOTES'] == '')) { //Suggested name for the user on their local language
                $obj['NOTES']  = ContractUtil::GTP($this->textMap, "IA.RUN_ON_DATE_TIME", ['DATE_TIME' => date('n/d/Y h:i:s A')] );
            }
        }
        $obj['DEFAULT_EMAIL'] = GetEmailForNotification();  // in case they want to schedule
        $obj['INTACCTUSER']   = (GetMyLogin() == SUPPORTUSER_LOGINID) ? 'Y' : 'N';
        $obj['ATROOT']        = (( ( ! IsMultiEntityCompany()) || IsRoot()) ? 'Y' : 'N');

        return parent::transformBizObjectToView($obj);
    }

    /**
     * @param array     $_params
     * @param array     $obj
     * @param bool      $ok
     *
     * @return bool
     */
    protected function innerProcessCreateAction(&$_params, &$obj, $ok)
    {
        // $obj['OBJECT'] = $this->sourceobject;
        $obj['MODULE'] = $this->module;
        return parent::innerProcessCreateAction($_params, $obj, $ok);
    }

    /**
     * can print
     *
     * @return bool
     */
    protected function canPrint()
    {
        return false;
    }

    /**
     * can save
     *
     * @return bool
     */
    protected function canSave()
    {
        return false;
    }

    /**
     * canSaveAndNew
     *
     * @return bool
     */
    protected function canSaveAndNew()
    {
        return false;
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $buttons = parent::getStandardButtons($state);
        $state   = $this->getState();

        if ( $this->kShowNewState === $state ) {
            $buttons1 = array();
            $this->setButtonDetails($buttons1, 'runnow',  'runnow', GT($this->textTokens,"IA.RUN_NOW"),  'RUNNOW', true, 'runHealthCheck(this)',false);
            $buttons = array_merge($buttons1, $buttons);
        }
        return $buttons;
    }


    /**
     * @param string $field
     * @param string $toThis
     */
    protected function setHelpText( $field, $toThis )
    {
        $view = $this->getView();
        $fields = array();
        $view->findComponents(array('path' => $field), EditorComponentFactory::TYPE_FIELD, $fields);
        foreach ($fields as $field) {
            $field->setProperty('helpText', $toThis);
        }
    }


    /**
     * @param string    $field          the field name
     * @param bool      $isASection     true if a section, false if an individual field.  Defaults to false
     */
    private function hide( $field, $isASection = false )
    {
        $this->setProperty( $field, 'hidden', true, $isASection );
    }


    /**
     * @param  string   $field
     * @param  string   $property
     * @param  string   $to
     * @param  bool     $isASection
     */
    private function setProperty( $field, $property, $to, $isASection = false )
    {
        $view = $this->getView();
        $fields = array();
        if ($isASection == true) {
            $view->findComponents(array('id' => $field), EditorComponentFactory::TYPE_SECTION, $fields);
        } else {
            $view->findComponents(array('path' => $field), EditorComponentFactory::TYPE_FIELD, $fields);
        }
        foreach ($fields as $field) {
            $field->setProperty($property, $to);
        }
    }


    /**
     * @param array &$obj the data
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        parent::mediateDataAndMetadata($obj);
        $view = $this->getView();
        $state = $this->getState();

        $schedule = ( $obj['OBJECT'] == InvHlthRunManager::SCHEDULE);
        $displayAll = "(".GT($this->textMap,"IA.ALL") . ")";

            // not really fields; used by javascript
        $this->hide('DEFAULT_EMAIL');
        $this->hide('INTACCTUSER');
        $this->hide('ATROOT');

        $obj['MAX_CHANGES'] = (($obj['CHANGES_MAX'] ?? 'F') == 'T') ? GT($this->textMap,"IA.PARTIAL_RESULTS"): "   ";

        // Touch up the title a bit....
        $this->setTitle( ($this->kShowNewState === $state) ? "IA.MAINTAIN_INVENTORY_VALUATION" : "IA.INVENTORY_VALUATION_MAINT_RESULTS" );

        if ( !IsMultiEntityCompany() ) {
            $this->hide( 'LOCATIONID' );
        }

            // hide sections in add mode...
        if ( $this->kShowNewState === $state ) {
            $fieldPaths = array('OBJECT', 'MODULE', "SELECTTOFIXRO1", "SELECTTOFIXRO2", "SELECTTOFIXRO3", "SELECTTOFIXRO4",
                                'SHOWALLRO', 'CLOSED_NO_GL_RO', 'NO_GL_RO', 'ANALYZE_OR_UPDATERO', 'UPDATE_BUILDKITS_RO',
                                'FIXASOFDATE_RO', 'UPDATE_TRANSFERS_RO' );   // fields
            foreach ( $fieldPaths as $path ) {
                $this->hide( $path );
            }

            $sids = array('DOWNLOADS','DOWNLOADS2','PARAMETERS', 'ERRORDATA', 'AUDITSECTION', 'CHANGES');   // sections
            foreach ( $sids as $sid ) {
                $this->hide( $sid, true );  // true means these are SECTIONS, not FIELDS
            }

            $obj['UPDATE_BUILDKITS'] = 'true';      // default to on, there's a hidden checkbox if that becomes interesting....
            $obj['UPDATE_TRANSFERS'] = 'true';
            $obj['CLOSED_NO_GL']     = 'OP';        // default to open periods

            // make sure some values have initial values...
            if ($obj['REPEAT_START_DATE'] == '') {
                $obj['REPEAT_START_DATE'] = GetCurrentDate();  // today
            }

            if ($obj['REPEAT_END_DATE'] == '') {
                $obj['REPEAT_END_DATE'] = GetCurrentDate();  // today
            }

            if ($obj['REPEAT_INTERVAL'] == '') {
                $obj['REPEAT_INTERVAL'] = '1';
            }

            if ($obj['REPEAT_OCCURRENCES'] == '') {
                $obj['REPEAT_OCCURRENCES'] = '1';
            }
            $obj['MIV_ANALYZE_OR_UPDATE'] = InvHlthRunManager::ThoroughAnalyze;
            if (($obj['ANALYZE_OR_UPDATE'] != InvHlthRunManager::QuickAnalyze) && ($obj['ANALYZE_OR_UPDATE'] != InvHlthRunManager::QuickUpdate)) {
                $obj['MIV_ANALYZE_OR_UPDATE'] = $obj['ANALYZE_OR_UPDATE'];
            }
            $obj['ANALYZE_OR_UPDATE']     = '';
        }
        $obj['SELECTTOFIX'] = 'INVVALDATA, COGSDATA';  // ,VERBOSE

        // hide buttons in view mode...
        if ( $this->kShowViewState === $state ) {
            $parameters = unserialize($obj['PARAMETERS']);
            unset($obj['PARAMETERS']);
            unset($parameters['RECORDNO']);
            unset($parameters['DETAIL']);  // just in case
            unset($parameters['CHANGES']);
            $parameters = is_array($parameters) ? $parameters : array();
            $obj = array_merge($obj, $parameters);

            if ($schedule) {
                $this->hide('DOWNLOADS', true);  // true means these are SECTIONS, not FIELDS
                $this->hide('DOWNLOADS2', true);
                $this->hide( 'SCHEDULE_SCHEDULETHIS' );
                $this->hide( "CHANGES", true );
            } else {
                $this->hide( 'SCHEDULING', true );
            }
            $fieldPaths = array( "SELECTTOFIX", "NONE", "SHOWALL", "CLOSED_NO_GL", "NO_GL", "MIV_ANALYZE_OR_UPDATE", 'UPDATE_BUILDKITS', 'UPDATE_TRANSFERS' );
            foreach ($fieldPaths as $path) {
                $this->hide( $path );
            }

            $this->setHelpText( 'NOTES',    "" );
            $this->setHelpText( 'EMAILTO', "" );

            //For Action UI
            $this->setProperty('NOTES',"infoText","");
            $this->setProperty('EMAILTO',"infoText","");

            if ($obj['ANALYZE_OR_UPDATE'] == InvHlthRunManager::ThoroughUpdate) {
                $this->setHelpText('FIXASOFDATE', "The costs were updated starting from this date.");
            } else {
                $this->hide( 'FIXASOFDATE' );
                $this->setHelpText('FIXASOFDATE', "");
            }

            // These fields don't notmally have help text, but if empty, lets remind the customer that that means 'all'
            $fieldPaths = array( "FROMITEMID", "TOITEMID", "WAREHOUSEID", "LOCATIONID" );
            foreach ($fieldPaths as $path) {
                if ($obj[ $path ] == "") {
                    $obj[ $path ] = $displayAll;
                        //This is to disable picker if no values selected, since we are adding dummy value (All).
                        $viewFields = [];
                        $view->findComponents(
                            [ 'path' => $path ], EditorComponentFactory::TYPE_FIELD, $viewFields
                        );
                        $viewField = $viewFields[0];
                        $viewField->setProperty('noview', true);
                }
            }

            $obj['SHOWALLRO']      = "";
            if (isset($obj['SHOWALL']) && $obj['SHOWALL'] === 'AT' ) {
                $obj['SHOWALLRO'] = I18N::getSingleToken('IA.SHOW_ALL_TRANSACTIONS');
            } else if(isset($obj['SHOWALL']) && $obj['SHOWALL'] === 'ET' )  {
                $obj['SHOWALLRO'] = I18N::getSingleToken("IA.COSTING_ERROR_TRANSACTIONS_ONLY");
            } else if(isset($obj['SHOWALL']) && $obj['SHOWALL'] === 'SHOWALL' )  {
                $obj['SHOWALLRO'] =  I18N::getSingleToken('IA.SHOW_ALL_TRANSACTIONS');
            } else {
                $this->hide( "SHOWALLRO" );
            }

            $obj['ANALYZE_OR_UPDATERO']      = "";
            $analyzeRun = false;
            switch ($obj['ANALYZE_OR_UPDATE']) {
                case InvHlthRunManager::QuickAnalyze    :
                    $obj['ANALYZE_OR_UPDATERO'] = I18N::getSingleToken('IA.QUICK_ANALYZED');
                    $this->hide( "INVVALDATA" );
                    // $this->hide( "COSTDATA" );
                    $analyzeRun = true;
                    break;

                case InvHlthRunManager::QuickUpdate    :
                    $obj['ANALYZE_OR_UPDATERO'] = I18N::getSingleToken('IA.COSTING_UPDATED');
                    $this->hide( "INVVALDATA" );
                    //$this->hide( "COSTDATA" );
                    break;

                case InvHlthRunManager::ThoroughAnalyze    :
                    $obj['ANALYZE_OR_UPDATERO'] = I18N::getSingleToken('IA.ANALYZED');
                    $analyzeRun = true;
                    break;

                case InvHlthRunManager::ThoroughUpdate    :
                    $obj['ANALYZE_OR_UPDATERO'] = I18N::getSingleToken('IA.UPDATED');
                    break;

                default:
                    $this->hide( "ANALYZE_OR_UPDATERO" );
                    break;
            }

            $obj['CLOSED_NO_GL_RO']      = "";
            if ( isset($obj['CLOSED_NO_GL']) && $obj['CLOSED_NO_GL'] === 'OP' ) {
                $obj['CLOSED_NO_GL_RO'] = GT($this->textMap,"IA.IN_OPEN_PERIODS_ONLY");
            } else if( isset($obj['CLOSED_NO_GL']) && $obj['CLOSED_NO_GL'] === 'CP' ) {
                $obj['CLOSED_NO_GL_RO'] = GT($this->textMap,"IA.IN_OPEN_AND_CLOSED_PERIODS");
            } else if( isset($obj['CLOSED_NO_GL']) && $obj['CLOSED_NO_GL'] === 'CLOSED_NO_GL' ) {
                $obj['CLOSED_NO_GL_RO'] = GT($this->textMap,"IA.IN_OPEN_AND_CLOSED_PERIODS");
            } else {
                $this->hide( "CLOSED_NO_GL_RO" );
            }

            $obj['NO_GL_RO']      = "";
            if (isset($obj['NO_GL']) && $obj['NO_GL'] === 'true') {
                $obj['NO_GL_RO'] = GT($this->textMap,"IA.IN_OPEN_PERIODS_ONLY");
            } else if (isset($obj['NO_GL']) && $obj['NO_GL'] === 'NO_GL') {
                $obj['NO_GL_RO'] = GT($this->textMap,"IA.IN_OPEN_PERIODS_ONLY");
            } else {
                $this->hide( "NO_GL_RO" );
            }

            if ($obj['ANALYZE_OR_UPDATE'] == InvHlthRunManager::ThoroughUpdate) {
                $obj['FIXASOFDATE_RO'] = $obj['FIXASOFDATE'];
            } else {
                $this->hide( 'FIXASOFDATE_RO' );
            }


            $obj['UPDATE_BUILDKITS_RO'] = "No";
            if (($obj['UPDATE_BUILDKITS'] ?? 'false') === 'true') {
                $obj['UPDATE_BUILDKITS_RO'] = GT($this->textMap,"IA.YES");
            }

            $obj['UPDATE_TRANSFERS_RO'] = "No";
            if (($obj['UPDATE_TRANSFERS'] ?? 'false') === 'true') {
                $obj['UPDATE_TRANSFERS_RO'] = GT($this->textMap,"IA.YES");
            }

            $e  = $obj['ERRORDATA']; // like "Cost errors: 3; Negative inventory warnings: 17" or "Scheduled to Run"
            if ( ! Globals::$g->islive) {
                // in dev, sometimes someone saves the file with no translation, so lets translate here (shouldn't be needed
                // in production)....
                $search = [
                    'IA.COSTING_ISSUES',
                    'IA.NEGATIVE_INVENTORY_WARNINGS',
                    'IA.NO_OF_NEG_QTY_FOUND',
                    'IA.NUMBER_FIXED',
                ];
                $replace = [];
                foreach ($search as $token) {
                    $replace[] = GT($this->textMap, $token);
                }
                $e = str_replace($search, $replace, $e);
            }
            if (strpos( $e, ':' ) === false) {
                $obj['ERRORDATA1'] = $e;
                $obj['ERRORDATA2'] = "";
            } else {
                $c1 = strpos($e, ':') + 1;    // skip the colon
                $c2 = strpos($e, ':', $c1) + 1;
                $s = strpos($e, ';');
                $obj['ERRORDATA1'] = substr($e, $c1, $s - $c1);
                $obj['ERRORDATA2'] = substr($e, $c2);
            }

            // When reading from the database, these are filled in.
            // but when we JUST CREATED the record, they aren't.
            // Since we just created the record, use the current date/user.
            if ($obj['WHENCREATED'] == '') {
                $obj['WHENCREATED'] = GetCurrentDate();  // today
            }

            if ($obj['CREATEDBY'] == '') {
                $obj['CREATEDBY'] = GetMyLogin();
            }

            if ($analyzeRun) {
                $this->hide( "CHANGES", true );
            }
            else{
                foreach ($obj['CHANGES'] as &$changeRecord) {
                   if ($changeRecord['TRANSACTIONNAME'] == "STANDARD COST CHANGE"){
                       $changeRecord['TRANSACTIONNAME']= I18N::getSingleToken("IA.STD_COST_CHANGE");
                   }
                }
                unset($changeRecord);
            }
            self::translateStateValues($obj);

        } else {
            // For these fields if the value is (All) then make it blank. Since (All) displayed only in View mode
            $fieldPaths = array( "FROMITEMID", "TOITEMID", "WAREHOUSEID", "LOCATIONID" );
            foreach ($fieldPaths as $path) {
                if (($obj[ $path ] ?? '') === $displayAll ) {
                    $obj[ $path ] = "";
                }
            }
        }
        $this->fetchLog($obj);

        // tell them we're still loading the changes...
        $obj['CHANGESMADE'] = [[
            'ITEM'      => '',
            'WAREHOUSE' => '',
            'DATE'      => '',
            'IMPACT'    => '',
            'CHANGE'    =>  GT($this->textMap,"IA.LOADING"),
            'DETAILS'   => '',
        ]];

        return true;
    }

    /**
     * @param $row
     *  Translate the MIV state to the local langauge
     * @return void
     */
   static function translateStateValues(&$row)
   {
           switch ($row['OBJECT']){
               case InvHlthRunManager::QuickAnalyzed:
                   $row['OBJECT'] = I18N::getSingleToken('IA.QUICK_ANALYZED');
                   break;
               case InvHlthRunManager::ThoroughAnalyzed:
                   $row['OBJECT'] = I18N::getSingleToken('IA.ANALYZED');
                   break;
               case InvHlthRunManager::QuickUpdated:
                   $row['OBJECT'] = I18N::getSingleToken('IA.COSTING_UPDATED');
                   break;
               case InvHlthRunManager::ThoroughUpdated:
                   $row['OBJECT'] = I18N::getSingleToken('IA.UPDATED');
                   break;
               case InvHlthRunManager::SCHEDULE:
                   $row['OBJECT'] = I18N::getSingleToken('IA.SCHEDULED');
                   break;
               default:  //Do nothing if none of the above
                   break;
           }
   }


    /**
     * Get the list of JS files to include in the editor screen
     *
     * @return array    the list of JS files to include
     */
    protected function getJavaScriptFileNames()
    {
        return array('../resources/js/invhlthrun.js');
    }

    /**
     * addRunHealthCheckAction
     */
    protected function addRunHealthCheckAction()
    {
        $this->kActionHandlers['runhealthcheck'] = array(
            'handler' => 'runHealthCheckAction',
            'states' => array(
                $this->kShowNewState,
                $this->kShowViewState,
            )
        );
    }


    /**
     * addFixHealthAction
     */
    protected function addFixHealthAction()
    {
        $this->kActionHandlers['fixhealth'] = array(
            'handler' => 'fixHealthAction',
            'states' => array(
                $this->kShowNewState,
                $this->kShowViewState,
            )
        );
    }


    /**
     * @param array $_params the metadata
     *
     * @return bool
     */
    protected function runOrFixHealth(&$_params )
    {
        $ok = $this->retrieveObjectFromView($_params, $obj);
        $obj = $this->DoRefreshAction($_params, $obj);

        if ($obj['ANALYZE_OR_UPDATE'] == '') {
            $obj['ANALYZE_OR_UPDATE'] = $obj['MIV_ANALYZE_OR_UPDATE']; // screen has fewer options than the full analye_or_update, so I use MIV_ANALYZE_OR_UPDATE
        }
        $obj['MIV_ANALYZE_OR_UPDATE'] = null;

        $inspect = ($obj["ANALYZE_OR_UPDATE"] == InvHlthRunManager::QuickAnalyze) || ($obj["ANALYZE_OR_UPDATE"] == InvHlthRunManager::ThoroughAnalyze);


        // Special 'run offline once' mode?
        $cookie = (isset($_COOKIE['RUN_MIV_OFFLINE']) && ($_COOKIE['RUN_MIV_OFFLINE'] == 'true'));
        if (( ! $inspect) && $cookie) {
            $pub = new ims_publish_1( IMS_MODE_NONBLOCKING , IMS_PROCESS_REMOTE , IMS_MODE_QUEUED);

            $msgBody = array(
                'params' => $obj, // Util_DataRecordFormatter::jsonToPhp($obj),
                'action' => 'runmivoffline' );

            $ok = $pub->PublishMsg(
                'RUNMIVOFFLINE',
                'INTACCT',
                'RUN_OFFLINEACTION',
                IMS_PRIORITY_DEFAULT,
                $msgBody,
                '',
                $response
            );
            return $ok;
        }


        if ($inspect) {
            $ok = $ok && $this->getEntityMgr()->runHealthCheck($obj);
        } else {
            $ok = $ok && $this->getEntityMgr()->fixHealth($obj);
        }

        if ($ok && $obj['EMAILTO'] && ( $obj['OBJECT'] != InvHlthRunManager::SCHEDULE) ) {
            $this->getEntityMgr()->emailLog( $obj['EMAILTO'], $obj );
        }
        $this->state = $this->kShowViewState;   // now we can view this action

        return $ok;
    }


    /**
     * @param array &$_params the metadata
     *
     * @return bool
     */
    protected function runHealthCheckAction(&$_params)
    {
        return $this->runOrFixHealth( $_params );
    }


    /**
     * @param array &$_params the metadata
     *
     * @return bool
     */
    protected function fixHealthAction(&$_params)
    {
        return $this->runOrFixHealth( $_params );
    }



    /**
     * @param string    $entity
     * @param string    $objId
     * @param string    $doctype
     * @param array     $fields
     *
     * @return array|false
     */
    protected function getEntityData($entity, $objId, $doctype='', $fields=null)
    {
        $retVal = parent::getEntityData($entity, $objId, $doctype, $fields);
        // do we have XML tags in the log?
        // if so our current UI controls wont show them instead it will get parsed at the browser
        // so lets push the XML contents into a textarea...
        if ( strstr($retVal['PARAMETERS'], "</") ) {
            $retVal['PARAMETERS'] = '<textarea style="width: 800px;height: 320px;
            border: 0px solid #cccccc;" readonly wrap>' . $retVal['PARAMETERS']
                . '</textarea>';
        }

        if ( strstr($retVal['ERRORDATA'], "</") ) {
            $retVal['ERRORDATA'] = '<textarea style="width: 800px;height: 320px;
            border: 0px solid #cccccc;" readonly wrap>' . $retVal['ERRORDATA']
                . '</textarea>';
        }

        return $retVal;
    }

    /**
     * @param array         $_params
     * @param bool          $offline
     * @param string|false  $out
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        $obj = $this->getViewData();
        $method = Request::$r->_deliverymethod;

        if ($obj['DOWNLOAD']) {
            $method = 'csv';
        } else if (!$method) {
            $method = 'pdf';
        }

        switch ($method) {
            case 'csv' :
                $this->downloadCSV($obj);
                break;
            case 'xmldata' :
            case 'phpdata' :
            case 'xmlform' :
            case 'phpform' :
            case 'xsl' :
            case 'fo' :
            case 'pdf' :
                parent::Editor_Deliver($_params, $offline, $out);
                break;

        }
        return true;
    }


    /**
     * @param array $obj
     */
    protected function downloadCSV(&$obj)
    {
        if ($obj['DOWNLOAD']) {
            $this->getEntityMgr()->downloadCSV($obj);
            unset($obj['DOWNLOAD']);
        }
    }

    /**
     * @param array $obj
     *
     * @return array|array[]  log records (potentially 3) in an array
     */
    private function fetchLog(&$obj)
    {
        $obj['MIVPLAN_CSV'] = -1;    // no plan yet
        if (isset($obj['RECORDNO']) && $obj['RECORDNO'] !== '') {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $logMgr = $gManagerFactory->getManager('actionlog');
            $params = array(
                'selects' => array(
                    'RECORDNO', 'ACTION'
                ),
                'filters' => array(
                    array(
                        array('MODULE', '=', 'Inventory'),
                        array('LOGTYPE', '=', 'INVHEALTHCHK'),
                        array('OBJECT', '=', 'InvHlthRun'),
                        array('LOG_BLOB', 'ISNOTNULL'),
                        array('OBJECTKEY', '=', $obj['RECORDNO']),
                    ),
                ),
                'orders' => array(
                    array('RECORDNO', 'desc'),
                ),
            );
            $logs = $logMgr->GetList($params);

            $keys = array(
                InvCostToolManager::CSV_COGSDATA    => 'COGSDATA_CSV',
                InvCostToolManager::CSV_VALUATION   => 'INVVALDATA_CSV',
                InvCostToolManager::CSV_ITEM        => 'COSTDATA_CSV',
                InvCostToolManager::CSV_MIVPlan     => 'MIVPLAN_CSV',
            );
            // for some reason, we occasionally get extra records for this run;
            //  just take the first (highest) numbers
            foreach ($keys as $key ) {
                $obj[$key] = '0';    // set to zero
            }
            foreach ($logs as $log ) {
                if ($obj[$keys[$log['ACTION']]] == '0') {
                    $obj[$keys[$log['ACTION']]]  = $log['RECORDNO'];
                }
            }
            return $logs;   // return the array
        }
        return array();
    }

}
