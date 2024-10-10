<?php
/**
 * Manager file for the standard object InvHlthRun
 *
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * @category  Cls
 * @package   Source/common
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000-2009 Intacct Corporation, All Rights Reserved
 */

/**
 * Class InvHlthRunManager
 */
class InvHlthRunManager extends EntityManager
{
    // NOTE: THESE ARE ENGLISH TEXT, PLEASE UPDATE AS NEEDED (and _() doesn't work here, sadly)
    const QuickAnalyzed     = 'Quick Analyzed';
    const QuickUpdated      = 'Costing updated';  // [C]ogs
    const ThoroughAnalyzed  = 'Analyzed';
    const ThoroughUpdated   = 'Updated';
    const SCHEDULE          = 'Schedule';

    // NOTE: THESE ARE INTERNAL VALUES, PLEASE LEAVE AS IS
    const QuickAnalyze      = 'Q';
    const QuickUpdate       = 'C';  // [C]ogs
    const ThoroughAnalyze   = 'A';
    const ThoroughUpdate    = 'U';

    const ScheduleNamePrefix = "Recalc Tool ";

    /** @var bool $fromAPI   Did we get here from the API?  */
    private $fromAPI        = false;



    /**
     * @param array $params List of parameters for specific to this object
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }



    /* *********************
        XML API:

    <invhlthrun>
        <Analyze>C</Analyze>                                            <!-- true for doing an analyze, false for doing an UPDATE, C for FAST UPDATE -->
        <Notes>Unique Name</Notes>
        <Module>Inventory</Module>
        <Description>My First Run</Description>                         <!-- of the run -->
        <ItemGLGroup></ItemGLGroup>                                     <!-- group name, if one -->
        <FromItemID></FromItemID>                                       <!-- from and two item name, if any (expect id dash dash name format) -->
        <ToItemID></ToItemID>
        <WarehouseID></WarehouseID>                                     <!-- warehouse, if one -->
        <LocationID></LocationID>                                       <!-- Location, if one (NOT ON THE UI, UNTESTED) -->
        <CostMethodCheck>Average,Standard,FIFO,LIFO</CostMethodCheck>   <!-- one or more of these -->
        <FixAsOfDate>01/01/1970</FixAsOfDate>                           <!-- if given, the updates start on the given date or after closed periods, whichever is later -->
        <ShowAll>AT</ShowAll>                                           <!-- show ALL transactions(AT), or just the ones with problems(ET) -->
    </invhlthrun>

    ************************
     */

    /**
     * Prepare the incoming parameters and populate keys and formats expected by the backend.
     *
     * @param array &$values The input values for this MIV operation or schedule
     *
     * @return void
     */
    private static function prepareParameterValues(array &$values) : void
    {
        static $dateParameters = [
            'PARAMETERREPEATSTARTDATE',
            'PARAMETERREPEATENDDATE',
            'PARAMETERASOFDATE',
        ];

        static $parameterKeyNameMap = [
            'PARAMETERREPEATPERIOD' => 'REPEAT_PERIOD',
            'PARAMETERREPEATINTERVAL' => 'REPEAT_INTERVAL',
            'PARAMETERREPEATSTARTDATE' => 'REPEAT_START_DATE',
            'PARAMETERREPEATENDDATE' => 'REPEAT_END_DATE',
            'PARAMETERREPEATREPETITION' => 'REPEAT_REPETITION',
            'PARAMETERREPEATOCCURRENCES' => 'REPEAT_OCCURRENCES',
            'PARAMETERREPEATWEEKDAY' => 'REPEAT_WEEK_DAY',
            'PARAMETERREPEATENDTYPE' => 'REPEAT_END_TYPE',
            'PARAMETERISSCHEDULE' => 'SCHEDULE_SCHEDULETHIS',
            'PARAMETERFROMITEMID' => 'FROMITEMID',
            'PARAMETERTOITEMID' => 'TOITEMID',
            'PARAMETERWAREHOUSEID' => 'WAREHOUSEID',
            'PARAMETERCOSTMETHODCHECK' => 'COSTMETHODCHECK',
            'PARAMETERITEMGROUPID' => 'ITEMGLGROUP',
            'PARAMETERASOFDATE' => 'FIXASOFDATE',
            'PARAMETERANALYZEORUPDATE' => 'ANALYZE_OR_UPDATE',
            'PARAMETERSHOWALL' => 'SHOWALL',
            'PARAMETERCLOSEDNOGL' => 'CLOSED_NO_GL',
            'PARAMETERNOGL' => 'NO_GL',
        ];

        static $parameterKeyNamesWithDefaults = [
            'PARAMETERREPEATPERIOD' => 'DAY',
            'PARAMETERISSCHEDULE' => 'false',
            'PARAMETERCOSTMETHODCHECK' => 'Average,Standard,FIFO,LIFO',
            'PARAMETERANALYZEORUPDATE' => 'A',
            'PARAMETERSHOWALL' => 'ET',
            'PARAMETERCLOSEDNOGL' => 'OP',
            'PARAMETERNOGL' => 'true',
        ];

        // Special handling for dates: internal format vs REST API canonical format
        foreach ($dateParameters as $dateParameter) {
            if (isset($values[$dateParameter]) && !empty($values[$dateParameter])) {
                // Rewrite date in expected internal format
                $values[$dateParameter] = date_format(date_create($values[$dateParameter]), "m/d/Y");
            }
        }

        // Map to internal parameter names expected by the backend
        $isAPIRequest = false;
        foreach ($values as $key => $value) {
            if (array_key_exists($key, $parameterKeyNameMap)) {
                // Yep, need to rewrite this one with the expected key
                $isAPIRequest = true;
                // Note: ensure that even numbers get cast to strings, so that SQL formula's unserialization works
                $values[$parameterKeyNameMap[$key]] = strval($value);
                unset($values[$key]);
            }
        }

        // Handle defaults as needed
        if ($isAPIRequest) {
            // Set any defaults, only if needed
            foreach ($parameterKeyNamesWithDefaults as $parameterName => $default) {
                if (!isset($values[$parameterKeyNameMap[$parameterName]])
                    || $values[$parameterKeyNameMap[$parameterName]] == '') {
                    $values[$parameterKeyNameMap[$parameterName]] = strval($parameterKeyNamesWithDefaults[$parameterName]);
                }
            }
            // And append additional parameters not specified by user
            $values['UPDATE_BUILDKITS'] = 'true';
            $values['UPDATE_TRANSFERS'] = 'true';
        }

        // Lastly, just in case
        if (!($values['FROM_UI'] ?? false)) {
            $values['SHOWALL'] = $values['SHOWALL'] ?? $parameterKeyNamesWithDefaults['PARAMETERSHOWALL'];
            $values['CLOSED_NO_GL'] = $values['CLOSED_NO_GL'] ?? $parameterKeyNamesWithDefaults['PARAMETERCLOSEDNOGL'];
        }
        foreach (['PARAMETERFROMITEMKEY', 'PARAMETERTOITEMKEY', 'PARAMETERWAREHOUSEKEY',
                  'PARAMETERITEMGROUPKEY'] as $syntheticKey) {
            // These keys will have been mapped to the Ids already and are no longer needed
            unset($values[$syntheticKey]);
        }
    }

    /**
     * Add new class object
     *
     * @param array     &$values    Class object details in the form of array
     *
     * @return bool True|False based on Success or Failure of the method call
     */
    protected function regularAdd(&$values)
    {
        $msg = "Could not create HlthRun record!";   // default
        $ok = true;
        $errorcode = 'INV-0650';
        $placeholder = [];
        $pData = Globals::$g->perfdata;
        $fromUI = ($values['FROM_UI'] === true);

        self::prepareParameterValues($values);

        if (!$fromUI && $values['NO_GL'] == '') { // quirk: because of backwards compatibility, this switch needs to be set to 'NO_GL' when you WANT the GL (I know, I know), so set it for the API.
            $values['NO_GL'] = 'true';             // set 'NO_GL' to 'true' or something to actually get NO GL POSTINGS
        }
        $values['TRACKINGID'] = $pData->getSerialnbr();
        $values['WEBSERVER']  = getenv("IA_SERVER_NAME");
        $values['CHANGES']    = [];             // Remove any that might have been left over from a prior read
        $values['RECORDNO']   = null;           // make darn sure this isn't seen as an update.....

        $isASchedule = (isset($values['SCHEDULE_SCHEDULETHIS']) && $values['SCHEDULE_SCHEDULETHIS'] === 'true');
        // Set some defaults in case the XML API doesn't:
        if (!isset($values['ANALYZE_OR_UPDATE'])) {
            if (!isset($values['ANALYZE'])) {
                $values['ANALYZE_OR_UPDATE'] = self::ThoroughAnalyze;
            } else if ($values['ANALYZE'] == 'true') {
                $values['ANALYZE_OR_UPDATE'] = self::ThoroughAnalyze;   // backwards compatibility
            } else if ($values['ANALYZE'] == 'false') {
                $values['ANALYZE_OR_UPDATE'] = self::ThoroughUpdate;   // backwards compatibility
            } else {
                $values['ANALYZE_OR_UPDATE'] = $values['ANALYZE'];
            }
        }
        // are we using the new, 'Quick' flavor of update?
        if (in_array($values['ANALYZE_OR_UPDATE'], [self::QuickAnalyze, self::QuickUpdate ])) {
            $kINVid = &Globals::$g->kINVid;
            GetModulePreferences($kINVid, $invPrefs);
            $asondate         =   "01/01/1970";
            if ($invPrefs['INVSTARTDATE'] != "") {
                $asondate = $invPrefs['INVSTARTDATE'];
            }
            $values['FIXASOFDATE'] = $asondate; // start of time
            $values['CLOSED_NO_GL'] = 'OP'; // update inventory in open periods only (change from 09/2020; before was open and closed)
            $values['NO_GL'] = 'true';      // remember because of backwards compatibility, this actually means YES GL.  :-(

        } else if (! in_array($values['ANALYZE_OR_UPDATE'], [self::QuickAnalyze, self::ThoroughAnalyze, self::QuickUpdate, self::ThoroughUpdate ])) {
            $msg = "ANALYZE_OR_UPDATE value not one of the expected values: " . $values['ANALYZE_OR_UPDATE'];
            $errorcode = 'INV-0653';
            $placeholder = ['VALUES_ANALYZE_OR_UPDATE'=>$values['ANALYZE_OR_UPDATE']];
            $ok = false;
        }
        if ( ! isset($values['COSTMETHODCHECK'])) {
            $values['COSTMETHODCHECK'] = 'Average,Standard,FIFO,LIFO';
        }
        if ( ! isset($values['NOTES'])) {
            $values['NOTES'] = GetCurrentDate();
        }
        if ( ! isset($values['MODULE'])) {
            $values['MODULE'] = 'Inventory';
        }

        // Validate email
        $ok = ($ok && $this->validateValues($values));

        $reReadChanges = false;

            // Do the work prior to saving the data to disk
        if ($ok) {
            if ($isASchedule) {
                $ok = $this->CreateHlthRunSchedule($values);
            } else {
                if (($values['ANALYZE_OR_UPDATE'] === self::QuickAnalyze) || ($values['ANALYZE_OR_UPDATE'] === self::ThoroughAnalyze)) {
                    $ok = $this->runHealthCheckInner($values);
                } else {
                    $ok = $this->fixHealthInner($values);
                    $reReadChanges = true;
                }
            }
        }

        $values['CHANGES']     = [];            // costchangehistory records were written on the fly, so shouldn't be here.  Just in case....
        $values['CHANGES_MAX'] = 'F';

            // The 'parameters' field will store stuff not already in the record (hack!)
        $parameters = $values;
        $removeThese = [
            // some are in the base record, some are junk, some just come from the UI as a matter of course.....
            'std_buttons', 'DYNAMIC_HELP_INFORMATION', 'INFO', 'OBJECT', 'DESCRIPTION', 'NOTES', 'MODULE',
            'ERRORDATA', 'WHENCREATED', 'WHENMODIFIED', 'CREATEDBY', 'MODIFIEDBY', 'WEBSERVER', 'TRACKINGID',
            'RECORDNO', 'DETAIL', 'CHANGES', 'PARAMETERS', 'SUMMARY_CHILDREN_ONLY', 'MIV_ANALYZE_OR_UPDATE',
            'RECORD_URL', 'CHANGESMADE', 'DEFAULT_EMAIL', 'MAX_EVENTS', 'CHANGES_MAX', 'MAX_CHANGES',
        ];
        foreach ($removeThese as $removeThis) {
            unset($parameters[$removeThis]);
        }
        if ( ! $isASchedule) {
            foreach ($values as $key => $value) {
                if (strpos($key,"REPEAT_") !== false) {   // not a schedule; remove schedule fields
                    unset($parameters[$key]);
                }
            }
        }

        $values['PARAMETERS'] = serialize($parameters);

        $ok = $ok && parent::regularAdd($values);  // This writes data to disk

        if ( $ok && $reReadChanges && isset($values['RECORDNO']) && ($values['RECORDNO'] > 0)) {
            // Discussion: Because of memory pressure, I opted to write the cost change history records as we went,
            //      and so they aren't already in the values I want to return.  They ARE on disk, though.
            //      here I re-read the hlthrun record so we can get the whole owned-object tree.
            //      IS this better than saving the records as we go?  Not 100% sure, because I don't know when
            //      the VAST amount of ram used by the InvCostToolManager is released; hopefully after the end of
            //      the runHealthCheckInner() / fixHealthInner() call above.
            $cchManager = Globals::$g->gManagerFactory->getManager('costchangehistory');
            $cchManager->returnSummariesOnly = true;

            $newValues = $cchManager->getByParent($values['RECORDNO']);
            if ($newValues !== false) {
                $values['CHANGES']     = (array)$newValues;
                $values['CHANGES_MAX'] = (count($newValues) >= CostChangeHistoryManager::MAXIMUM_RETURNED_SUMMARIES) ? 'T' : 'F';
            }
        }

        if (!$ok) {
            $gErr = Globals::$g->gErr;
            $gErr->addIAError($errorcode, __FILE__ . ':' . __LINE__, $msg, $placeholder);
            // i18N::TODO - (Code Change Review)
            if ($fromUI) { //Popup error and exit for UI only
                include 'popuperror.phtml';
                exit();
            }
            return $ok;
        }
        $this->cleanupSchedules();
        return $ok;
    }


    /**
     * Get a single record
     *
     * @param string        $ID
     * @param string[]|null $fields
     *
     * @return array|false
     */
    function get($ID, $fields = null)
    {
        $rtn = parent::BaseGet($ID, $fields);   // just the base record
        $rtn['CHANGES']     = [];
        $rtn['CHANGES_MAX'] = 'F';

        $getChanges = (($rtn['ANALYZE_OR_UPDATE'] !== self::QuickAnalyze) && ($rtn['ANALYZE_OR_UPDATE'] !== self::ThoroughAnalyze));
        if ($getChanges) {
            $cchManager = Globals::$g->gManagerFactory->getManager('costchangehistory');
            $cchManager->returnSummariesOnly = true;

            $newValues = $cchManager->getByParent($ID);
            if ($newValues !== false) {
                $rtn['CHANGES'] = (array)$newValues;
                $rtn['CHANGES_MAX'] = (count($newValues) >= CostChangeHistoryManager::MAXIMUM_RETURNED_SUMMARIES) ? 'T' : 'F';
            }

            // the ACTIONLOG records are not exported via the API, so here we pretend they are part of my 'owned object' chain
            if ($this->fromAPI) {
                $logMgr = Globals::$g->gManagerFactory->getManager('actionlog');
                $params = array(
                    'selects' => array(
                        'LOG_BLOB'
                    ),
                    'filters' => array(
                        array(
                            array('MODULE', '=', 'Inventory'),
                            array('LOGTYPE', '=', 'INVHEALTHCHK'),
                            array('OBJECT', '=', 'InvHlthRun'),
                            array('LOG_BLOB', 'ISNOTNULL'),
                            array('ACTION', '=', 'Fetch MIV Plan'),
                            array('OBJECTKEY', '=', $ID),
                        ),
                    ),
                );
                $log = $logMgr->GetList($params);
                if (($log !== false) && (isset($log[0]['LOG_BLOB']))) {
                    $rtn['PLAN'] = databaseStringUncompress($log[0]['LOG_BLOB']);
                }
            }
        }
        return $rtn;
    }


        /**
         * API access to the Get method
         * WARNING: entities with GET_BY_GET == true & vid != 'RECORDNO' should override API_Get and use API_GetByVid
         * to translate RECORDNOs to VIDs
         *
         * @param int|string|int[]|string[] $ids    Array list of IDs (RECORDNO) for the record to get
         * @param string[]|null             $fields Array list of fields to return
         *
         * @return array|false Array of records to return or failure code
         */
    public function API_Get($ids, $fields = null)
    {
        $this->fromAPI = true;
        return parent::API_Get($ids,$fields);
    }


        /**
     *      What transactions that affect COGS may need changing by the costing code?
     *
     * @param  string[] $values     Parameters to the routine
     *
     * @return array                The 'CHANGES' records
     */
    public function getListOfPotentialChanges(&$values)
    {
        $gManageFactory = Globals::$g->gManagerFactory;
        $eMgr = $gManageFactory->getManager('invcosttool');
        $ret = $eMgr->getListOfPotentialChanges($values);
        return $ret;
    }


    /**
     * runHealthCheckInner
     *
     *  called from within the add() function BEFORE the record is saved to disk
     *
     * @param array &$values Class object details in the form of array
     *
     * @return bool
     */
    public function runHealthCheckInner(&$values)
    {
        $gManageFactory = Globals::$g->gManagerFactory;
        $eMgr = $gManageFactory->getManager('invcosttool');

        $ok = $eMgr->fetchAction($values);

        // i18n
        $tokens = [
            [
                'id' => 'IA.COSTING_ISSUES'
            ],
            [
                'id' => 'IA.NEGATIVE_INVENTORY_WARNINGS'
            ],
        ];
        I18N::addTokens($tokens);
        $translatedText = I18N::getText();
        $costingIssues = GT($translatedText, 'IA.COSTING_ISSUES');
        $negativeInv   = GT($translatedText, 'IA.NEGATIVE_INVENTORY_WARNINGS');

        $values['ERRORDATA'] = "$costingIssues: " . $values['ERRORSDFOUND']
                             . "; $negativeInv: " . $values['ERRORSQTY0'];

        if ($values['ANALYZE_OR_UPDATE'] == self::QuickAnalyze) {
            $values['ACTION'] = self::QuickAnalyzed;
            $values['OBJECT'] = self::QuickAnalyzed;
        } else {
            $values['ACTION'] = self::ThoroughAnalyzed;
            $values['OBJECT'] = self::ThoroughAnalyzed;
        }

        return $ok;
    }


    /**
     * runHealthCheck
     *
     * @param array &$values Class object details in the form of array
     *
     * @return bool
     */
    public function runHealthCheck(&$values)
    {
        $values['FROM_UI'] = true;  // not from the api
        $ok = $this->add( $values );

        return $ok;
    }

    /**
     * fixHealthInner
     *
     *  called from within the add() function BEFORE the record is saved to disk
     *
     * @param array &$values Class object details in the form of array
     *
     * @return bool
     */
    public function fixHealthInner(&$values)
    {
        $gManageFactory = Globals::$g->gManagerFactory;
        $eMgr = $gManageFactory->getManager('invcosttool');

        $ok = $eMgr->fixAction($values);

        // i18n
        $tokens = [
            [ 'id' => 'IA.COSTING_ISSUES' ],
            [ 'id' => 'IA.NO_OF_NEG_QTY_FOUND' ],
            [ 'id' => 'IA.NUMBER_FIXED' ],
            [ 'id' => 'IA.GL_ENTRIES_NOT_UPDATED_BECAUSE_OF' ],
        ];
        I18N::addTokens($tokens);
        $translatedText = I18N::getText();
        $costingIssues = GT($translatedText, 'IA.COSTING_ISSUES');
        $negativeInv   = GT($translatedText, 'IA.NO_OF_NEG_QTY_FOUND');
        $fixed         = GT($translatedText, 'IA.NUMBER_FIXED');
        $GLNotUpdated  = GT($translatedText, 'IA.GL_ENTRIES_NOT_UPDATED_BECAUSE_OF');
        $GLNotUpdated  = str_replace('${QUANTITY}', $values['ERRORSNOGL'] ?? '', $GLNotUpdated);
        $GLNotUpdated  = str_replace('${REASONS}',  $values['GLERRORS'] ?? '',   $GLNotUpdated);

        $values['ERRORDATA'] = "$costingIssues: "  . $values['ERRORSDFOUND']
                             . "; $negativeInv: "  . $values['ERRORSQTY0']
                             . "; $fixed: "        . $values['ERRORSDFIXED'];
        if (isset($values['ERRORSNOGL']) && $values['ERRORSNOGL'] > 0) {
            $values['ERRORDATA'] .= "; $GLNotUpdated ";
        }

        if ($values['ANALYZE_OR_UPDATE'] == self::QuickUpdate) {
            $values['ACTION'] = self::QuickUpdated;
            $values['OBJECT'] = self::QuickUpdated;
        } else {
            $values['ACTION'] = self::ThoroughUpdated;
            $values['OBJECT'] = self::ThoroughUpdated;
        }

        return $ok;
    }

    /**
     * fixHealth
     *
     * @param array &$values Class object details in the form of array
     *
     * @return bool
     */
    public function fixHealth(&$values)
    {
        $values['FROM_UI'] = true;  // not from the api
        $ok = $this->add($values );

        return $ok;
    }


    /**
     * Update a HlthRun object info
     *
     * @param array &$values HlthRun object details in the form of array
     *
     * @return false
     */
    protected function regularSet(&$values)
    {
        $gErr = Globals::$g->gErr;

        $msg = "Set method not allowed on this object...";
        $gErr->addIAError('INV-0509', __FILE__ . ':' . __LINE__,
            $msg,
            []
        );

        return false;
    }

    /**
     * Delete a HlthRun object
     *
     * @param int $id   VID of the object
     *
     * @return bool
     */
    function delete($id)
    {
        global $gManagerFactory;

        $raw = $this->getForDelete($id);
        $raw = $raw[0]; // get the first (only) record

        $parameters = unserialize($raw['PARAMETERS']);
        $raw = array_merge($raw, $parameters);

        $isASchedule = (isset($raw['SCHEDULE_SCHEDULETHIS']) && $raw['SCHEDULE_SCHEDULETHIS'] === 'true');

        // The lister should prevent this from firing, but just in case:
        if (($raw['ANALYZE_OR_UPDATE'] !== self::QuickAnalyze) &&
            ($raw['ANALYZE_OR_UPDATE'] !== self::ThoroughAnalyze) &&
            !$isASchedule) {
            $gErr = Globals::$g->gErr;

            $msg = "Delete not allowed on runs of this type ";
            $gErr->addIAError('INV-0510', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );

            return false;
        }

        $this->deleteChatter($id);  // is this needed?  Dunno...

            // Remove the schedule records if there are some
        if ($isASchedule) {
            if (isset($raw['SCHEDULE_NAME'])) {
                $schedopMgr = $gManagerFactory->getManager('scheduledoperation');
                $schedopMgr->DeleteScheduledTransaction($raw['SCHEDULE_NAME']);
            } else {
                $this->cleanupSchedules();  // old problem where the schedule name wasn't saved with the hlthrun record....
            }
        }
        return parent::Delete($id);
    }


    /**
     * email log
     *
     * @param string $addresses addresses
     * @param array  $obj       the object record
     */

    public function emailLog($addresses, $obj )
    {

        $companyTitle = GetMyCompanyTitle();
        // loading tokens for menu names these instructions are needed in email subject so forced to get them before email body localization
        $tokens = [
            [
                'id' => 'IA.INVENTORY_CONTROL'
            ],
            [
                'id' => 'IA.ALL'
            ],
            [
                'id' => 'IA.MAINTAIN_INVENTORY_VALUATION'
            ]

        ];
        I18N::addTokens($tokens);
        $translatedText = I18N::getText();
        $inventoryControlMenuToken = GT($translatedText, 'IA.INVENTORY_CONTROL');
        $allMenuToken = GT($translatedText, 'IA.ALL');
        $mivMenuToken = GT($translatedText, 'IA.MAINTAIN_INVENTORY_VALUATION');
        // loading tokens for MIV localization email Header, Subject & Body
        $tokens = [
            [
                'id' => 'IA.INVENTORY_HEALTH_RUN_EMAIL_HEADER'
            ],
            [
                'id' => 'IA.INVENTORY_HEALTH_RUN_EMAIL_SUBJECT',
                'placeHolders' => [
                    ['name' => 'COMPANY_TITLE', 'value' => $companyTitle]
                ]
            ],
            [
                'id' => 'IA.INVENTORY_HEALTH_RUN_EMAIL_BODY',
                'placeHolders' => [
                    ['name' => 'COMPANY_TITLE', 'value' => $companyTitle],
                    ['name' => 'RECALCULATION_NAME', 'value' => $obj['NOTES']],
                    ['name' => 'RECALCULATION_TYPE', 'value' => $obj['OBJECT']],
                    ['name' => 'RECALCULATION_DATE', 'value' => date('m/d/Y g:i:s A', time())],
                    ['name' => 'RECALCULATION_COST_ERRORS', 'value' => $obj['ERRORSDFOUND']],
                    ['name' => 'RECALCULATION_NEGATIVE_INVENTORY_WARNINGS', 'value' => $obj['ERRORSQTY0']],
                    ['name' => 'INVENTORY_CONTROL_MENU', 'value' => $inventoryControlMenuToken],
                    ['name' => 'ACTIVITIES_MENU', 'value' => $allMenuToken],
                    ['name' => 'MAINTAIN_INVENTORY_VALUATION_MENU', 'value' => $mivMenuToken]
                ]
            ]
        ];

        I18N::addTokens($tokens);
        $translatedText =  I18N::getText();
        $subject = GT( $translatedText, 'IA.INVENTORY_HEALTH_RUN_EMAIL_SUBJECT');
        $body = GT( $translatedText, 'IA.INVENTORY_HEALTH_RUN_EMAIL_BODY');
        $header = GT( $translatedText, 'IA.INVENTORY_HEALTH_RUN_EMAIL_HEADER');

        $emailArray = preg_split("/\s*,\s*/", $addresses);
        foreach ($emailArray as $address) {
            EmailHelper::ia_mail(
                $address,
                $subject,
                $body,
                $header);
        }
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    function downloadCSV($obj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        /** @var ActionLogManager $logMgr */
        $logMgr = $gManagerFactory->getManager('actionlog');
        $logs = $logMgr->Get($obj[$obj['DOWNLOAD'] . '_CSV']);
        $title = $logs['ACTION'] . ' ' . $logs['WHENCREATED'];

        // I'm scared to change the actions, but Patti wanted to remove the word 'Fetch'
        // and replace it with 'Inspect' or 'Fix'.
        $title = str_replace( "Fetch ", $obj['OBJECT'] . ' ', $title );

        // From reporter.cls:
        // Ticket 41964 : Excel exports working as 'web page' and in 'read only mode'
        if (isl_stristr($_SERVER['HTTP_USER_AGENT'], "msie")
            || isl_stristr($_SERVER['HTTP_USER_AGENT'], "Trident/7.0; rv:11.0")
        ) {
            $dispHeader = "attachment;";
        } else {
            $dispHeader = "";
        }
        header("Content-Disposition: $dispHeader filename=\"$title.csv\"");
        header("Content-type: application/vnd.ms-excel");

        echo $logs['LOG_BLOB'];

        return true;
    }



    //  ************************************************************************************
    //  ************************************************************************************
    //
    //      SCHEDULING
    //
    //  ************************************************************************************
    //  ************************************************************************************
    /**
     * @param array $obj
     *
     * @return bool
     */
    public function runScheduled( $obj )
    {
        $ok = false;
        if (isset($obj['OBJECT'])) {
            if (isset($obj['SCHEDULE_SCHEDULETHIS']) && $obj['SCHEDULE_SCHEDULETHIS'] === 'true') {
                $obj['SCHEDULE_SCHEDULETHIS'] = 'false';  // so we don't think it is a schedule
                $obj['NOTES']                 .= "; " . GTFromOneToken("IA.SCHEDULED_RUN_ON",[['name' => 'DATE_TIME', 'value'=>date('n/d/Y h:i:s A')]]) ;    //_("; Scheduled run on ") . date('n/d/Y h:i:s A');
                $obj[':RECORDNO'] = 0;                  // so we don't update THIS record
                $obj['RECORDNO'] = 0;
                $inspect = ($obj["ANALYZE_OR_UPDATE"] == self::QuickAnalyze) || ($obj["ANALYZE_OR_UPDATE"] == self::ThoroughAnalyze);

                // Tracy decided we DON"T want to update closed periods on the quick runs in September 2020, so catch prior schedules....
                if (($obj["ANALYZE_OR_UPDATE"] == self::QuickAnalyze) || ($obj["ANALYZE_OR_UPDATE"] == self::QuickUpdate)) {
                    $obj['CLOSED_NO_GL'] = 'OP'; // update inventory in open periods only (change from 09/2020; before was open and closed)
                }

                $gManageFactory = Globals::$g->gManagerFactory;
                $eMgr = $gManageFactory->getManager('invcosttool');
                $eMgr->Init();      // do init in case we're called more than once

                if ($inspect) {
                    $ok = $this->runHealthCheck($obj);
                } else {
                    $ok = $this->fixHealth($obj);
                }
                    // All done; send mail?
                if ($obj['EMAILTO']) {
                    $this->emailLog($obj['EMAILTO'], $obj);
                }
            } else {
                $t = var_export($obj, true);
                logFL("**** CODE BUG: Scheduled Recalc Tool run is not from a SCHEDULE, but from {$obj['OBJECT']}.\n$t");
            }
        } else {
            logFL("**** CODE BUG: Scheduled Recalc Tool run with no data.");
        }
        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */

    private function CreateHlthRunSchedule(&$values)
    {
        $quickRun       =   ($values['ANALYZE_OR_UPDATE'] == self::QuickUpdate);

        if (($values['EMAILTO'] == '') && ! $quickRun) {
             $values['EMAILTO']  = GetEmailForNotification();    // let's make sure we have an email address to send to.
        }

        $description    =   "Cost Recalc Automatic Runs";
        $Entity         =   "INVHLTHRUN";
        $Action         =   'RUN';
        $EventDate      =   self::defaultValue($values['REPEAT_START_DATE'], GetCurrentDate(IADATE_USRFORMAT));
        $status         =   'active';
        $schedule       =   array();
        $operation      =   array();
        $scheduledOperation = array();

        $values['OBJECT'] = self::SCHEDULE;
        $values['ACTION'] = self::SCHEDULE;
        $values['SCHEDULE_SCHEDULETHIS'] = 'true';
        // i18n
        $tokens = [
            [ 'id' => 'IA.SCHEDULED_TO_RUN_DELETE_TO_STOP' ],
        ];
        I18N::addTokens($tokens);
        $translatedText = I18N::getText();
        $schedledToRun = GT($translatedText, 'IA.SCHEDULED_TO_RUN_DELETE_TO_STOP');
        $values['ERRORDATA'] = $schedledToRun;


        //------------------------------------------------------------------

        $ok =           $this->CreateSchedule(           $status, $values, $description, $EventDate, $schedule);
        $ok =    $ok && $this->CreateOperation(          $status, $values, $Entity, $Action, $schedule, $operation );
        $ok =    $ok && $this->CreateScheduledOperation( $status, $schedule, $operation, $scheduledOperation);
        $values['SCHEDULE_NAME'] = $schedule['NAME'];
        return $ok;
    }


    /**
     * @param string $value
     * @param string $alternate
     *
     * @return string
     */
    static function defaultValue( $value, $alternate )
    {
        $rtn = trim($value);
        if ($rtn == '') {
            $rtn = trim($alternate);
        }
        return $rtn;
    }

    /**
     * @param string    $status
     * @param array     $values
     * @param string    $description
     * @param string    $EventDate
     * @param array     $schedule
     *
     * @return bool
     */
    function CreateSchedule($status, $values, $description, $EventDate, &$schedule)
    {
        $userid     =    GetMyUserid(1);
        $curdate    =    GetCurrentDate();
        $UniqueName =    self::GenerateUniqueName($values['ANALYZE_OR_UPDATE'] == self::QuickUpdate);
        $startDate  =    self::defaultValue($values['REPEAT_START_DATE'], $curdate);


        $schedule['CNY#']       = GetMyCompany();
        $schedule['NAME']       = $UniqueName;
        $schedule['DESCRIPTION']= $description;
        $schedule['USERNO']     = $userid;
        $schedule['WHENCREATED']= $curdate;
        $schedule['STARTDATE']  = $startDate;
        $schedule['STARTON']    = '';
        $schedule['EXECTYPE']   = 'Automatic';

        if (DateCompare($EventDate, $curdate) <= 0) {
            // When Event Date is in past, scheduler runs in nonblocking mode immediately,
            // hence mode is immediate
            $schedule['EXECTYPE']   =   'Immediate';
        }

        // NOTE: I don't see any schedule field that takes the "REPEAT_REPETITION" values (DOW, DOM, EOM)

        $schedule['REPEATBY']       = ucfirst( strtolower( trim($values['REPEAT_PERIOD'] )));         // 'Day', 'Week', 'Month', 'Year', 'EndOfMonth'
        $schedule['REPEATDAYS']     = ucfirst( strtolower( trim($values['REPEAT_WEEK_DAY'])));        // Repeat Days ( Monday,Tuesday,...)
        // $schedule['REPEATMONTH'] = $values['??'];    // Repeat Month (1,2,3,4,5,6,7,8,9,10,11,12)
        // $schedule['REPEATWEEK']  = $values['??'];    // Repeat Week (F,S,T,H,L)
        $schedule['REPEATINTERVAL'] = (0 + self::defaultValue( $values['REPEAT_INTERVAL'], 1 ));   // make sure it is a number
        $schedule['REPEATCOUNT']    = (0 + ( ($values['REPEAT_END_TYPE'] == 'OCCURENCES') ? self::defaultValue($values['REPEAT_OCCURRENCES'], 1) : 0)); // make sure it is a number
        $schedule['ENDDATE']        = (      ($values['REPEAT_END_TYPE'] == 'DATE')       ? self::defaultValue($values['REPEAT_END_DATE'], $startDate) : '');
        $schedule['ENDON']          = ''; // ???

        $schedule['NEXTEXECDATE']	= $startDate;
        $schedule['LASTEXECDATE']   = "";   // hasn't executed yet
        $schedule['STATUS']         = $status;

        global $gManagerFactory;
        $SchedMgr   = $gManagerFactory->getManager('schedule');
        $ok         = $SchedMgr->add($schedule);
        return $ok;
    }

    /**
     * @param string    $status
     * @param array     $values
     * @param string    $Entity
     * @param string    $Action
     * @param array     $schedule
     * @param array     $operation
     *
     * @return bool
     */
    function CreateOperation($status, $values, $Entity, $Action, $schedule, &$operation )
    {
        $bodydata                   =    $values;           // save UI values
        unset($bodydata['std_buttons']);                    // but not these
        unset($bodydata['DYNAMIC_HELP_INFORMATION']);
        unset($bodydata['INFO']);

        // and not the schedule itself
        foreach( $bodydata as $field ) {
            if (is_string($field) && (substr( $field, 0, 9) == 'SCHEDULE_')) {
                unset( $bodydata[ $field ]);    // don't keep the schedule info; we want the other stuff
            }
        }

        $operation['CNY#']          =    $schedule['CNY#'];
        $operation['NAME']    
              =    $schedule['NAME'];
        $operation['DESCRIPTION']   =    $schedule['DESCRIPTION'];
        $operation['USERNO']        =    $schedule['USERNO'];
        $operation['ENTITY']        =    $Entity;
        $operation['ACTION']        =    $Action;
        $operation['BODYDATA']      =    $bodydata;
        $operation['STATUS']        =    $status;
        $operation['CONTACTEMAIL']  =    $values['EMAILTO'];
        $operation['MODULEKEY']     =    '3.AP';        // I guess....

        global $gManagerFactory;
        $OperMgr    =   $gManagerFactory->getManager('operation');
        $ok =    $OperMgr->add($operation);

        return $ok;
    }

    /**
     * @param string    $status
     * @param array     $schedule
     * @param array     $operation
     * @param array     $scheduledOperation
     *
     * @return bool
     */
    function CreateScheduledOperation($status, $schedule, $operation, &$scheduledOperation)
    {
        $schedKey   =   $schedule[':record#'];
        $operKey    =   $operation[':record#'];

        $scheduledOperation['NAME']              = $schedule['NAME'];
        $scheduledOperation['OPERATION']['NAME'] = $schedule['NAME'];
        $scheduledOperation['SCHEDULE']['NAME']  = $schedule['NAME'];
        $scheduledOperation['DESCRIPTION']       = $schedule['DESCRIPTION'];
        $scheduledOperation['USERNO']            = $schedule['USERNO'];
        $scheduledOperation['CNY#']              = $schedule['CNY#'];
        $scheduledOperation['STATUS']            = $status;
        $scheduledOperation['SCHEDULE#']         = $schedKey;
        $scheduledOperation['OPERATION#']        = $operKey;
        $scheduledOperation[':schedule#']        = $schedKey;
        $scheduledOperation[':operation#']       = $operKey;

        global $gManagerFactory;
        $SchedOperMgr    =   $gManagerFactory->getManager('scheduledoperation');
        $ok =    $SchedOperMgr->add($scheduledOperation);

        return $ok;

    }

    /**
     * The scheduler routines like a unique name
     *
     * @param  bool    $quickrun   is this a 'quickrun' schedule?
     * @return string
     */
    static function GenerateUniqueName($quickrun)
    {
        return self::ScheduleNamePrefix . GetMyCompany() . ' ' . ($quickrun ? 'QuickRun' : microtime( true ));
    }


    /**
     *      We store the schedule for Quick MIV Runs in the hlthrun file, just like
     *  any other invhlthrun schdule.  Delete any such record(s) here.
     *
     * @return bool    Did all go well?  (whether there was a record or not)
     *
     */
    public function deleteMIVQuickSchedule()
    {
        $ok         = true;
        $uniqueName = self::GenerateUniqueName(true);  // there is one unique name per company for quickruns

        $query   = [];
        $query[] = "SELECT record#, parameters FROM hlthrun WHERE cny#=:1 AND object=:2 ";
        $query[] = GetMyCompany();
        $query[] = self::SCHEDULE;
        $result = QueryResult($query);
        if ($result !== false) {

            foreach ($result as $row) {
                $parameters = unserialize($row['PARAMETERS']);
                if ($parameters['SCHEDULE_NAME'] == $uniqueName) {
                    $ok = $this->delete((int)$row['RECORD#']);
                    // we don't EXPECT dups, but let's keep going just in case.
                }
            }
        }

        // finally, as a super-last-gasp-effort, remove the schedule if it exists:
        if ($this->doesMIVQuickScheduleExist()) {
            $schedopMgr = Globals::$g->gManagerFactory->getManager('scheduledoperation');
            $schedopMgr->DeleteScheduledTransaction($uniqueName);
        }
        return $ok;
    }


    /**
     * @return bool    Does a schedule exist for QuickUpdate?
     */
    public function doesMIVQuickScheduleExist()
    {
        $uniqueName = self::GenerateUniqueName(true);  // there is one unique name per company for quickruns
        $schedopMgr = Globals::$g->gManagerFactory->getManager('scheduledoperation');
        $isThere = $schedopMgr->get($uniqueName, ['NAME']);
        if (($isThere !== false) && isset($isThere['NAME'])) {
            return true;
        }
        return false;
    }


    /**
     *  there are two conditions here:
     *  1) a schedule has expired and we want to delete the corresponding 'Schedule' record in the HLTHRUN table
     *  2) there was a bug for a whule where the HLTHRUN record did not have the schedyle name in it, and so the
     *      schedule was never deleted
     */
    private function cleanupSchedules()
    {
        // Step one: get the list of schedules from the schdule manager
        $schedopMgr        = Globals::$g->gManagerFactory->getManager('scheduledoperation');
        $nameTemplateL     = self::ScheduleNamePrefix;
        $nameTemplateH     = self::ScheduleNamePrefix . "z";    // something larger than the company number or U:<user name>
        $search            = [
                                'selects' => ['NAME'],
                                'filters' => [[['NAME', '>', $nameTemplateL], ['NAME', '<', $nameTemplateH]]]
                             ];

        $existingSchedules = $schedopMgr->GetList( $search );
        //logFL("************* Schedules found:" . var_export($existingSchedules,true));
        $schedules = [];
        if ($existingSchedules !== false) {
            foreach ($existingSchedules as $row) {
                $schedules[$row['NAME']] = false;   // false --> not accounted for yet
            }
        }

        // Step two: get the list of schedules from the HLTHRUN file:
        $query = [];
        $query[] = "SELECT record#, parameters FROM hlthrun WHERE cny#=:1 AND object=:2";
        $query[] = GetMyCompany();
        $query[] = self::SCHEDULE;
        $result = QueryResult($query);
        if ($result !== false) {
            foreach ($result as $hlthrunRecord) {
                $parameters = unserialize($hlthrunRecord['PARAMETERS']);
                if (isset( $schedules[ $parameters['SCHEDULE_NAME']])) {
                    $schedules[ $parameters['SCHEDULE_NAME']] = true;   // found!
                } else {
                    // There is a HLTHRUN schedule record but the schedule has expired
                    // (like it was for two days, say).
                    // delte the hlthrun record....
                    // Athreya says no: parent::Delete($hlthrunRecord['RECORD#']);
                    //logFL("[DEBUG] Expired hlthrun schdule being removed");
                }
            }
        }

        // So now, if there are schedules NOT found, that means that the hlthrun record
        //  went away but the schedule lingered.  Yes, that is a bug.  Yes, it has been fixed.
        foreach ($schedules as $name => $found) {
            if (! $found) {
                $schedopMgr->DeleteScheduledTransaction($name);
                //logFL("[DEBUG] Schedule for MIV tool without a corresponding HLTHRUN record:$name; cleaned up.");
            }
        }

    }

    /**
     * @param  array $values
     *      *
     * @return bool
     */
    private function validateValues($values) {
        $ok = true;
        // Validating email address
        if ($values['EMAILTO'] && !CheckEmailList($values['EMAILTO'])) {
            $gErr = Globals::$g->gErr;
            $gErr->addIAError('INV-0148', __FILE__ . ":" . __LINE__,
                "Email address is invalid.",
                []
            );
            $ok = false;
        }
        return $ok;
    }



}
