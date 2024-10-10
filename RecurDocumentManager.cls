<?php
//
//================================================================================
//	FILE:			RecurDocumentManager.cls
//	AUTHOR:			bharris
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

import('ContactManager');
import('WarehouseManager');
import('ShipMethodManager');
import('DocumentManager');
import('ScheduleManager.cls');
require_once 'backend_supdoc.inc';
require_once 'backend_dates.inc';

/**
 * Class RecurDocumentManager
 */
class RecurDocumentManager extends DocumentManager
{
    /**
     * Contact Manager object ptr.
     *
     * @var ContactManager $ContactMgr
     */
    var $ContactMgr;

    /**
     * Department Manager object ptr.
     *
     * @var  DepartmentManager $DeptMgr
     */
    var $DeptMgr;

    /**
     * Location Manager object ptr.
     *
     * @var  LocationManager $LocMgr
     */
    var $LocMgr;

    /**
     * Operation Manager object ptr.
     *
     * @var  OperationManager $OperMgr
     */
    var $OperMgr;

    /**
     * ScheduledOperation Manager object ptr.
     *
     * @var  ScheduledOperationManager $SchedOperMgr
     */
    var $SchedOperMgr;

    /**
     * ScheduledOperationLog Manager object ptr.
     *
     * @var  ScheduledOperationLogManager $SchedOpLogMgr
     */
    var $SchedOpLogMgr;

    /**
     * Term Manager object ptr.
     *
     * @var  TermManager $TermMgr
     */
    var $TermMgr;

    /**
     * @var ContactManager $contactMgr
     */
    var $contactMgr;

    /**
     * Current execution time 
     *
     * @var     string $_execTime
     */
    var $_execTime;

    /**
     * Variable to indicate flow of control.
     * It tells whether invocation is from an
     * editor or a lister
     *
     * @var     string $_from
     */
    var $_from;

    /**
     * Name reference for line items container
     *
     * @var     string $_li_entity
     */
    var $_li_entity;

    /**
     * Module ID
     *
     * @var     string $_modid
     */
    var $_modid;

    /**
     * topic used by IMS adapter
     *
     * @var     string $_scheduleentity
     */
    var $_scheduleentity;

    /**
     * Contains the default ME Locaton value when in
     * multi-entity environment.
     *
     * @var     string $_defaultMELocation
     */
    var $_defaultMELocation;

    /** @var bool  $_inRecurringMode*/
    var $_inRecurringMode;

    // Is the simulation enable on edit/save ?
    /** @var bool  $enableSimulation */
    protected $enableSimulation = true;

    /** @var bool $applyCreatePolicy */
    private $applyCreatePolicy = true;

    /** @var array $_schedmeta */
    var $_schedmeta = array();

    /** @var bool $enableschedule */
    var $enableschedule = false;

    /** @var I18NEmailToken Object $emailToken */
    var $emailToken = false;

    /**
     * @param bool $applyCreatePolicy
     */
    public function setApplyCreatePolicy($applyCreatePolicy)
    {
        $this->applyCreatePolicy = $applyCreatePolicy;
    }

    /**
     * @return bool
     */
    public function isApplyCreatePolicy() {
        return $this->applyCreatePolicy;
    }


    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        global $gManagerFactory, $kdocumentQueries;
        //$this->EntityManager();
        if( ! array_key_exists('DOCTYPE', $params) ) {
            $docType = Request::$r->_dt;
            if( $docType ) {
                $params['DOCTYPE'] = $docType;
            }
        }
        parent::__construct($params);
        $this->OperMgr                    = $gManagerFactory->getManager('operation');
        $this->SchedOperMgr                = $gManagerFactory->getManager('scheduledoperation');
        $this->LocMgr                    = $gManagerFactory->getManager('location');
        $this->DeptMgr                    = $gManagerFactory->getManager('department');
        $this->SchedOpLogMgr            = $gManagerFactory->getManager('scheduledoperationlog');
        $this->contactMgr                = $gManagerFactory->getManager('contact');
        $this->_execTime                 = GetCurrentDate(); //Current time
        $this->_from                     = '';
        $this->_li_entity                 = 'ENTRIES';
        $this->_inRecurringMode            = false;

        $this->_defaultMELocation         = '';
        if ( IsMultiEntityCompany() ) {
            // retrieve a default location for this rtt
            $this->_defaultMELocation     = DefaultMELocation(true);
        }

        include 'recurdocument.qry';
        if (isset($kdocumentQueries) && ($kdocumentQueries != '')) {
            $this->_QM->LoadQueries($kdocumentQueries);
        }

        /** @var string $mod */
        $mod = $this->getMyInstanceMod();
        $this->mod = $mod;
        $this->_ismcpEnabled = IsMCPEnabled($mod);

        $this->_schedmeta = array('NAME' => 'Recur Global Consolidation',
            'DESCRIPTION' => 'Recurring Global Consolidation'
        );
    }


    /**
     * To get the document params manager object. When called return a documentparameters manager object instance from the ManagerFactory pool of instances.
     *
     * @return DocumentParamsManager instance of DocumentParamsManager.
     */
    function get_docpar_manager()
    {
        if (!isset($this->docParMgr) || $this->docParMgr == "") {
            global $gManagerFactory;
            $this->docParMgr = $gManagerFactory->getManager($this->mod . 'documentparams');
        }
        return $this->docParMgr;
    }


    /**
     * This method creates the SCHEDULE, OPERATION, and SCHEDULEDOPERAITON objects.  The
     * creation of the RecurDocHdr object and associated child elements is pushed to the
     * EntityManager to complete.
     *
     * Returns boolean signifying success or failure.
     *
     * @param  array $values The values to add
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        global $gManagerFactory;

        $source         = "RecurDocumentManager::Add";
        $OperValues     = array();
        $SchedValues     = array();

        $Newvalues        = $values;

        if ($this->isApplyCreatePolicy()) {
            /** @var DocumentParamsManager $docparMgr */
            $docparMgr = Globals::$g->gManagerFactory->getManager($this->mod . 'documentparams');
            $docpar = $docparMgr->GetLatest($values['DOCPARID'], false);
            if (isArrayValueProvided($docpar, 'CREATETYPE') && 'Convert only' === $docpar['CREATETYPE']) {
                $msg = "Error creating recurring transaction. " .
                    "This type of transactions can only be converted from another transaction";
                Globals::$g->gErr->addIAError('INV-0801', __FILE__ . '.' . __LINE__, $msg);
                return false;
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        if(!empty($docpar['CREATION_RULE'] ?? '') && $docpar['CREATION_RULE'] == 'F') {
            $msg = "Error creating recurring transaction. The 'Create transaction in' field setting on the transaction definition prevents creating this type of transaction.";
            Globals::$g->gErr->addIAError('INV-0802', __FILE__ . '.' . __LINE__, $msg, []);
            return false;
        }

        // unsetting the subtotals of the parent
        $salecon = (Request::$r->_salecon == 'T') ? true : false;
        if($salecon) {
            unset($Newvalues['SUBTOTALS']);
        }

        $docMgr = $gManagerFactory->getManager('document');

        // Attempt to make it as modular as possible
        $ok             = $this->_QM->beginTrx($source);
        $ok             = $ok && $docMgr->validateRecurDocForChangeOrder($docpar);
        $ok             = $ok && $docMgr->validateRecurDocForPCB($this->mod, $docpar);
        $ok             = $ok && $this->ValidateObj($Newvalues);
        $ok             = $ok && $this->PrepValues($Newvalues, null, false);

        // Only unconverted line items (that now are tying to convert) should be converted.
        $valuesToConvert = $this->RemoveConvertedLines($Newvalues, $values);
        if ($ok && count($valuesToConvert['ENTRIES']) > 0) {
            $ok = $ok && $this->RemoveRecordNo($valuesToConvert);

            if ($this->IsAppendToExisting($valuesToConvert)) {

                $ok = $ok && $this->AppendToExisting($valuesToConvert['ENTRIES']);
            }
            else {

                if(empty($valuesToConvert['DOCSTATUS'] ?? '')) {
                    $valuesToConvert['DOCSTATUS'] = 'Active';
                }

                $ok = $ok && $this->CreateSchedulerEntries($valuesToConvert, $OperValues, $SchedValues);

                // Adds an entry to the template lister.
                // !! Skipping DocumentManager::add.  Something stinks.
                $ok = $ok && $this->entityManagerAdd($valuesToConvert);

                // For Auditing purpose.
                $values['RECORD#'] = $valuesToConvert['RECORDNO'];
                $values['RECORDNO'] = $valuesToConvert['RECORDNO'];

                // Adds recurring data to the above mentioned lines.
                $ok = $ok && $this->UpdateOperationEntry($valuesToConvert, $OperValues);
                //	eppp_p($ok); exit;
                // Creates recurring schedules.
                if(isset($Newvalues['PARENTDOCHDRKEY'])) {
                    $ok = $ok && $this->CreateRecurSchedule($valuesToConvert);
                }

                // If there is no errors in the template we will simulate the OE transaction creation and see if
                // it get created properly. If it does not we will notify the user about the issues.
                //$ok = $ok && $this->simulateExecution($valuesToConvert);
            }
        }

        // For auditing purpose we need to retain the recordno into the original 'values' array.
        $values['RECORD#'] = $Newvalues['RECORDNO'];

        $mode  = 'ADD';
        $ok             = $ok && $this->UpdateParentQtyConverted($Newvalues, $mode);
        $ok             = $ok && $this->UpdateParentConvertStatus($Newvalues, $mode);
        $warnOnDups     = Request::$r->_kNoWarn;

        $Newvalues['SUPDOCENTITY'] = $this->_schemas[$this->_entity]['supdocentity'];

        //SUPDOCENTITY comes from translate
        if (!empty($Newvalues['SUPDOCID'] ?? '') && $ok) {
            //Create the supporting document - invoice map for this recurring prrecord
            if (!AddSupportingDocumentMap($Newvalues['RECORDNO'] == '' ? $values['RECORDNO'] : $Newvalues['RECORDNO'], $Newvalues['SUPDOCID'], '', $Newvalues['SUPDOCENTITY']) ) {
                $msg = "Could not create document attachment mapping!";
                Globals::$g->gErr->addIAError('INV-0803', __FILE__ . ':' . __LINE__, $msg, []);
            }
        }

        // Cache the values for auditing to avoid an extra read later.
        if ($ok) {
            $auditTrailSession = AuditTrailSession::getInstance();
            $auditTrailSession->cacheAuditRecord($this->getAuditEntity(), $this->GetKeyValue($values), $values);
        }

        //-> commit/rollback
        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if (HasErrors()) {
                if ($warnOnDups != 'true') {
                    $msg =  "Could not create RecurDocument record!";
                    Globals::$g->gErr->addIAError( 'INV-0804', __FILE__ . ':' . __LINE__, $msg, [] );
                }
            }
            $this->_QM->rollbackTrx($source);

            //To avoid creating IMS job in shutdown function
            if ($gManagerFactory->ManagerExists( 'schedule' )) {
                $gManagerFactory->DeleteManager( 'schedule' );
            }
        }
        else {

            $schedMgr = $gManagerFactory->getManager('schedule');
            if($schedMgr->_RunNow($SchedValues)) {
                //add the schedule to the global schedule list so that they can be execute immediately during shutdown
                addRunNowSchedule($SchedValues);
            }
        }

        return $ok;
    }

    /**
     * @param array  $values
     * @param string $defTermKey
     *
     * @return bool
     */
    protected function populateDefaultTermAndDueDate(&$values, $defTermKey)
    {
       // Do nothing for recur documents -- they can have empty due date and term
        return true;
    }

    /**
     * @return string
     */
    public function getMyInstanceMod()
    {
        return '';
    }

    /**
     * @param int  $cny
     * @param bool $withLookup
     */
    function LoadCustomFields($cny = 0, /** @noinspection PhpUnusedParameterInspection */ $withLookup = true)
    {
        if ( ! $this->_docType ) {
            $this->_docType = Request::$r->_dt;
        }
        $mod = $this->getMyInstanceMod();
        $doc = $mod.'document';

        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if( $hasCustomFields && ! $this->enableschedule ) {
            $this->_entity = $mod.'document';
            $this->_schemas[$this->_entity]['ownedobjects'][0]['entity']  = $mod.'documententry';
        }

        parent::LoadCustomFields($cny, false);
    }
    
    /**
     * No macro fields for recurring 
     */
    public function LoadMacroFields()
    {
            
    }    

    /**
     * @return bool
     */
    function ExistCustomFields() 
    {

        if ( ! $this->_docType ) {
            $this->_docType = Request::$r->_dt;
        }
        $mod = $this->getMyInstanceMod();
        $doc = $mod.'document';

        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if(!$hasCustomFields || $this->enableschedule == true) {
            return $hasCustomFields;
        }

        $this->_entity = $mod.'document';
        $this->_schemas[$this->_entity]['ownedobjects'][0]['entity']  = $mod.'documententry';

        return $this->HasCustomFields($this->_entity, $this->_docType);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function ValidateDates($values)
    {
        // Do nothing for recur documents -- they can have empty due date and term
        return true;
    }

    /**
     * NOTE: Because of the (unusual) relationship between DocumentManager and RecurDocumentManager classes
     *   this function must be called by the DocumentManager statically. It would be better to re-architect
     *   RecurDocumentManager to not be a sub-class of DocumentManager (maybe a composition instead?).
     *
     * Remove any custom fields. Purge only for records belonging to this document type
     *
     * @param  string $column  the column that needs to be purged.
     * @param  string $docType the type of document (Sales Order, etc.)
     * @param  array  $values  list of values that should be purged
     *
     * @return bool
     */
    public static function PurgeCustomFieldColumn_static($column, $docType, $values = null)
    {
        $qry = "
			update recurdochdrmst set $column = null where cny# = :1 and record# in (
				select d.record# from recurdochdrmst d, docpar p where d.docparkey = p.record#
				and d.cny# = :1 and p.cny# = :1 and p.docid = :2
			) and ";
        $qry = array($qry, GetMyCompany(), $docType);
        if ( ! $values ) {
            $qry[0] .= "$column is not null";
        } else {
            $qry = PrepINClauseStmt($qry, $values, " $column ");
        }
        return ExecStmt($qry);
    }


    /**
     * MergeTableInfo
     */
    function MergeTableInfo() 
    {

        if( ! $this->_docType ) {
            $this->_docType = Request::$r->_dt;
        }
        $mod = $this->getMyInstanceMod();
        $doc = $mod.'document';
        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if(!$hasCustomFields || $this->enableschedule == true) {
            parent::MergeTableInfo();
        }

        //if(Request::$r->_do != 'edit' || $this->enableschedule == true) return parent::MergeTableInfo();


        $this->_entity = $mod.'recurdocument';
        $this->_schemas[$this->_entity]['ownedobjects'][0]['entity']='recurdocumententry';

        parent::MergeTableInfo();
    }

    /**
     * Returns an array similar to that in $value, with previously converted lines taken out.
     *
     * @param   array $values       A set of all rows (those which should and should not be converted).
     * @param   array $oldValues    Similar to $values except it is not formatted, however it does contain the previously converted data.
     *
     * @return    array similar to that in $value, with previously converted lines taken out.
     */
    function RemoveConvertedLines($values, $oldValues)
    {
        $retVal = $values;
        // updated count to Util::countOrZero to resolve PHP 8.1 issues 165232
        for ($i = 0, $i_count = Util::countOrZero($retVal['ENTRIES']); $i < $i_count; $i++) {
            $retVal['ENTRIES'][$i]['QTY_CONVERTED_PREV'] = $oldValues['ENTRIES'][$i]['QTY_CONVERTED_PREV'];
        }
        for ($i = 0, $i_count = Util::countOrZero($retVal['ENTRIES']); $i < $i_count; $i++) {
            if ($retVal['ENTRIES'][$i]['QTY_CONVERTED'] != $retVal['ENTRIES'][$i]['QTY_CONVERTED_PREV'] && $retVal['ENTRIES'][$i]['QTY_CONVERTED_PREV'] != 0) {
                $retVal['ENTRIES'] = array_merge(array_slice($retVal['ENTRIES'], 0, $i), array_slice($retVal['ENTRIES'], $i + 1));
                $i--;
            }
        }

        return $retVal;
    }


    /**
     * Returns an array containing the sales order rows that (still) contain a converted template.
     *
     * @param string $docId     The document number.
     *
     * @return bool|string[][]  containing the sales order rows that (still) contain a converted template.
     */
    function GetConvertedRowNums($docId)
    {
        global $gManagerFactory;
        $docrecurMgr =  $gManagerFactory->getManager('recurdocument');
        $myCompany = GetMyCompany();
        return $docrecurMgr->DoQuery('QRY_RECURDOCUMENT_GET_CONVERTED_ROWS', array($docId, $myCompany));
    }



    /**
     * Returns true if the $values represent Sales Order rows that are looking to append themselves to
     * an existing schedule..
     *
     *  @access private
     *
     * @param  array $values     A set of order values, containing entries.
     *
     * @return bool indicating whether or not the $values represent append-to-exisiting rows.
     */
    function IsAppendToExisting($values)
    {
        return ($values['ENTRIES'][0]['SC_EXISTINGSCHED'] ?? '') != '';
    }



    /**
     * Appends lines to recurdocumententry and optionally extends the line period.
     *
     * @param  array $lines The line items to append.
     *
     * @return bool  True if the queries run successfully.
     */
    function AppendToExisting($lines)
    {
        global $gManagerFactory;
        $SECONDS_PER_DAY = 60 * 60 * 24;

        $rdeMgr = $gManagerFactory->getManager('recurdocumententry', $this->forcenew, array( 'DOCTYPE' =>$this->_docType));
        $schedMgr = $gManagerFactory->getManager('sorecurschedule');
        $myCompany = GetMyCompany();



        for ($i=0; $i<count($lines); $i++) {

            // Append the line to the existing recurdocumententry.
            $docNo = $lines[$i]['SC_EXISTINGSCHED'];
            $lines[$i]['DOCHDRNO'] = $docNo;

            $rechdrval = $this->Get($docNo);

            //If Template currency is different than line currency then
            if($rechdrval['CURRENCY'] !== $lines[$i]['CURRENCY'] && isset($rechdrval['CURRENCY'])) {
                $msg             = "Line Item cannot add to Different Currency Template ";
                Globals::$g->gErr->addIAError('INV-0805', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }

            //Line no getting repeated
            $query= array(
            'QUERY'    => 'select (max(lineno) + 1 ) as LINENO from recurdocentry where cny#=? and RECURDOCHDRKEY=?',
            'ARGTYPES'     => array('integer','integer')
            );

            $result =$this->DoCustomQuery($query, array($myCompany, $docNo));
            $lines[$i][':lineno'] = $result[0]['LINENO'];
            //By default line status : active
            $lines[$i]['LINESTATUS'] = 'Active';


            // There is a need to modify the sale amount based on the number of remaining occurences
            $queryResult = $schedMgr->DoQuery('QRY_GET_REMAIN_DATA', array($docNo, $myCompany, $myCompany, $myCompany));
            $remainCount = $queryResult[0]['REPEATCOUNT'] - $queryResult[0]['EXECCOUNT'];

            if ($remainCount != 0 && $lines[$i]['SC_INSTALLPRICING'] =='true') {
                $lines[$i]['RETAILPRICE'] =ibcdiv($lines[$i]['RETAILPRICE'], $remainCount, 10, true);
                $lines[$i]['UIPRICE'] = ibcdiv($lines[$i]['UIPRICE'],  $remainCount, 10, true);
                $lines[$i]['UIVALUE'] = ibcdiv($lines[$i]['UIVALUE'],  $remainCount, DEFAULT_INVPRECISION, true);
                $lines[$i]['PRICE'] = ibcdiv($lines[$i]['PRICE'],  $remainCount, 10, true);
                $lines[$i]['TRX_PRICE'] = ibcdiv($lines[$i]['TRX_PRICE'],  $remainCount, 10, true);
                $lines[$i]['TRX_VALUE'] = ibcdiv($lines[$i]['TRX_VALUE'],  $remainCount, DEFAULT_INVPRECISION, true);
            }

            //this case should not be come here but it can be possible from XML gateway
            //			if ($remainCount == 0 && $lines[$i]['SC_INSTALLPRICING'] =='true') {
            //				$msg 			= _("Line Item cannot add to existing Template if there are no open schedule");
            //				Globals::$g->gErr->addError('BL03000021',__FILE__.':'.__LINE__,$msg);
            //				return false;
            //			}

            if (!$rdeMgr->add($lines[$i])) {
                return false;
            }

            // To handle the extend-recur-schedule checkbox:
            $newStartDate = $lines[$i]['REVRECSTARTDATE'];
            $newEndDate   = $lines[$i]['REVRECENDDATE'];
            if ($lines[$i]['SC_EXTENDLINEPERIOD'] == 'true' && isset($newStartDate) && isset($newEndDate)) {
                if (count($queryResult) != 1) {
                    return false;
                }

                // A new, proposed 'remainCount' should be determined, based on the start/end date of the line:
                $newDayDelta    = (strtotime($newEndDate) - strtotime($newStartDate)) / $SECONDS_PER_DAY;
                $repeatCount    = $queryResult[0]['REPEATCOUNT'];
                $execCount      = $queryResult[0]['EXECCOUNT'];
                $nextExecDate    = $queryResult[0]['NEXTEXECDATE'];
                $endDate        = $queryResult[0]['ENDDATE'];
                $daysInRecur    = $this->GetDaysInRecur($queryResult[0]['REPEATBY']);
                $repeatInterval = $queryResult[0]['REPEATINTERVAL'];
                $daysInSched    = $daysInRecur * $repeatInterval;

                if ($daysInSched > 0) {

                    // For occurence-based schedules
                    if (isset($repeatCount)) {
                        $remainCount    = $repeatCount - $execCount;
                        $newRemainCount = floor($newDayDelta / $daysInSched);

                        // If the proposed 'remainCount' is higher than the current value, update the repeatCount.
                        if ($newRemainCount > $remainCount) {
                            $newRepeatCount = $newRemainCount + $execCount;
                            if (!$schedMgr->DoQuery('QRY_UPDATE_REPEATCOUNT', array($newRepeatCount, $docNo, $myCompany, $myCompany, $myCompany))) {
                                return false;
                            }
                        }
                    }

                    // For end-date based schedules
                    else if (isset($nextExecDate) && isset($endDate)) {
                        $dayDelta = (strtotime($endDate) - strtotime($nextExecDate)) / $SECONDS_PER_DAY;

                        // If the newDayDelta is higher than the current dayDelta, update the endDate.
                        if ($newDayDelta > $dayDelta) {
                            $newEndDate = date('m/d/Y', strtotime($nextExecDate) + $newDayDelta * $SECONDS_PER_DAY);
                            if (!$schedMgr->DoQuery('QRY_UPDATE_ENDDATE', array($newEndDate, $docNo, $myCompany, $myCompany, $myCompany))) {
                                return false;
                            }
                        }
                    }

                }

            }
        }

        return true;
    }



    /**
     *  Returns the approximate number of days in the recurrence specified by $char.
     *
     * @param string $char character representing a schedule (day, week, month, or year).
     *                The legitimate possibilities are: 'D', 'W', 'M', 'Y', 'E', and 'N'.
     *                  'E' indicates 'End of the Month'.
     *                'N' indicates 'Non-repeating'.
     *
     * @return int The approximate number of days in the recurrence specified by $char.
     */
    function GetDaysInRecur($char)
    {
        switch ($char) {
        case 'D':
            return 1;
        case 'W':
            return 7;
        case 'M':
            return 30;
        case 'E':
            return 30;
        case 'Y':
            return 365;
        }
        return 0;
    }


    /**
     * This function calculates the total no. of transaction that will vbe created by this template
     *
     * @param array $Newvalues
     *
     * @return bool
     */

    function CreateRecurSchedule($Newvalues)
    {
        global $gManagerFactory;
        $ok = true;

        $nextdate = $Newvalues['ENTRIES'][0]['SC_STARTDATE'];
        $Newvalues['ENDDATE'] = $Newvalues['WHENDUE'];

        $schMgr = $gManagerFactory->getManager('sorecurschedule');
        $recurschedule = $Newvalues['ENTRIES'][0]['SCHEDULENAME'];
        $schObj = $schMgr->GetRaw($recurschedule);
        $schObj = $schObj[0];

        $val['SC_STARTDATE'] = $Newvalues['ENTRIES'][0]['SC_STARTDATE'];
        $sodocMgr = $gManagerFactory->getManager('sodocument');
        $doctotal = $sodocMgr->countInstallment($val, $schObj);
        $doctotal = bcsub($doctotal, '1');

        if(isset($Newvalues['ENDDATE'])) {
            $i = 1;
            $schcount = 0;
            $scharray = array();
            $scharray[$i]['SCHEDULE_NO'] = $i;
            $scharray[$i]['SCHEDULEDATE'] = $Newvalues['ENTRIES'][0]['SC_STARTDATE'];

            while(DateCompare($Newvalues['ENDDATE'], $nextdate)==1 && $doctotal>$schcount){
                $i = $i+1;
                switch (isl_substr($Newvalues['REPEATBY'], 0, 1)) {
                case 'N':
                    $nextdate = 0;
                    break;
                case 'D':
                    $repfactor = bcmul($Newvalues['REPEATINTERVAL'], '1');
                    $nextdate =  AddDays($nextdate, $repfactor);
                    $schcount = bcadd($schcount, '1');
                    $scharray[$i]['SCHEDULE_NO'] = $i;
                    $scharray[$i]['SCHEDULEDATE'] = $nextdate;
                    break;
                case 'W':
                    $repfactor = bcmul($Newvalues['REPEATINTERVAL'], '7');
                    $nextdate =  AddDays($nextdate, $repfactor);
                    $schcount = bcadd($schcount, '1');
                    $scharray[$i]['SCHEDULE_NO'] = $i;
                    $scharray[$i]['SCHEDULEDATE'] = $nextdate;
                    break;
                case 'M':
                    $repfactor = $Newvalues['REPEATINTERVAL'];
                    $nextdate =  AddMonths($nextdate, $repfactor);
                    $schcount = bcadd($schcount, '1');
                    $scharray[$i]['SCHEDULE_NO'] = $i;
                    $scharray[$i]['SCHEDULEDATE'] = $nextdate;
                    break;
                case 'E':
                    /** @noinspection PhpUndefinedVariableInspection */
                    $repfactor = $NewvaluesNewvalues['REPEATINTERVAL'];
                    $newdate = GetLastDateOfMonth($nextdate, IADATE_USRFORMAT);
                    $nextdate =  AddMonths($newdate, $repfactor);
                    $schcount = bcadd($schcount, '1');
                    $scharray[$i]['SCHEDULE_NO'] = $i;
                    $scharray[$i]['SCHEDULEDATE'] = $nextdate;
                    break;
                case 'Y':
                    $repfactor = $Newvalues['REPEATINTERVAL'];
                    $nextdate =  AddYears($nextdate, $repfactor);
                    $schcount = bcadd($schcount, '1');
                    $scharray[$i]['SCHEDULE_NO'] = $i;
                    $scharray[$i]['SCHEDULEDATE'] = $nextdate;

                    break;
                default:
                    $nextdate = 0;
                }
            }
        }
        $ok = $ok && $this->PrepSchValues($scharray, $Newvalues);
        return $ok;
    }

    /**
     * @param array $scharray
     * @param array $Newvalues
     *
     * @return bool
     */
    function PrepSchValues(&$scharray, $Newvalues)
    {
        global $gManagerFactory;
        $ok = true;
        $SCschMgr = $gManagerFactory->getManager('salescontractschedule');

        $totalamt = 0;
        $crubamt = 0;
        foreach( $Newvalues['ENTRIES'] as $val){
            $totalamt = bcadd($totalamt, $val['UIVALUE'], 10);
            $crubamt = bcadd($crubamt, ($val['ROUNDAMT'] ?? 0), 10);
        }
        $lastelement = count($scharray);
        foreach( (($scharray) ?? []) as $key => $val){
            $scharray[$key]['RECURDOCHDRKEY'] = $Newvalues['RECORDNO'];
            $scharray[$key]['SCHEDULENAME'] = $Newvalues['ENTRIES'][0]['SCHEDULENAME'];
            $scharray[$key]['SCHEDULEKEY'] = $Newvalues['ENTRIES'][0]['SCHEDULEID'];

            if($key != $lastelement) {
                $scharray[$key]['AMOUNT'] = $totalamt;
            }else{
                $scharray[$key]['AMOUNT'] = bcadd($totalamt, $crubamt, 10);
            }
            $ok = $ok && $SCschMgr->add($scharray[$key]);
        }

        return $ok;
    }

    /**
     * @param array  $Newvalues
     * @param string $mode
     *
     * @return bool|string[][]
     */
    function UpdateParentQtyConverted($Newvalues,$mode)
    {
        global $gManagerFactory;
        $ok = true;

        if(Util::countOrZero($Newvalues['ENTRIES'])) {
            $docrecurMgr =  $gManagerFactory->getManager('recurdocument');
            $cny = GetMyCompany();
            $isPriceConversionEnabled = $this->isPriceConversionEnabled();
            foreach ($Newvalues['ENTRIES'] as $val) {
                if (!empty($val['DOCENTRYKEY'] ?? '')) {
                    if ($mode == 'ADD') {
                        if (!empty($val['CONVERSIONTYPE'] ?? '') && $val['CONVERSIONTYPE'] == 'Price' & $isPriceConversionEnabled) {
                            $updateQuery = "update docentrymst set qty_converted = quantity, price_converted = trx_price, stdpriceconverted = trx_price where record# = :1 and cny# = :2";
                            $args = array($updateQuery, $val['DOCENTRYKEY'], $cny);
                            $ok = $ok && ExecStmt($args);
                        } else {
                            $code = 'QRY_RECURDOCUMENT_UPDATE_PARENT_QTY_CONVERTED';
                            $ok = $docrecurMgr->DoQuery($code, [$val['DOCENTRYKEY']], false);
                        }
                    } else {
                        $code = 'QRY_RECURDOCUMENT_RESET_PARENT_QTY_CONVERTED';
                        $ok = $docrecurMgr->DoQuery($code, array($val['DOCENTRYKEY']), false);
                    }
                }
            }
        }

        return $ok;
    }


    /**
     * @param array     $Newvalues
     * @param string    $mode
     *
     * @return bool|string[][]
     */
    function UpdateParentConvertStatus($Newvalues,$mode)
    {
        global $gManagerFactory;
        $ok = true;
        $cny = GetMyCompany();
        $docrecurMgr =  $gManagerFactory->getManager('recurdocument');
        if($mode=='ADD') {
            $code = 'QRY_RECURDOCUMENT_UPDATE_PARENT_CONVERT_STATUS';
            if(isset($Newvalues['PARENTDOCHDRKEY'])) {
                $ok = $docrecurMgr->DoQuery($code, array($Newvalues['PARENTDOCHDRKEY'], $cny), false);
            }

        }else {
            $docentrykeys = array();

            //Earlier it was refering only document level but we can append document lines to any existing template i.e. line level please refer RecurDocument.qry (to support Add-on facility for some contracts)
            foreach( $Newvalues['ENTRIES'] as $entry){
                if($entry['DOCENTRYKEY']) {
                    $docentrykeys[] = $entry['DOCENTRYKEY'];
                }
            }
            if($mode=='UPDATE') {
                //get old docentrykeys
                global $gManagerFactory;
                $recurdocentryMgr         =  $gManagerFactory->getManager('recurdocumententry');
                $oldEntries         = $recurdocentryMgr->GetByParent($Newvalues['RECORDNO']);
                //compare against new keys
                $deletedEntries = [];
                foreach( $oldEntries as $entry){
                    if ($entry['DOCENTRYKEY'] && !in_array($entry['DOCENTRYKEY'], $docentrykeys)) {
                        $deletedEntries[] = $entry['DOCENTRYKEY'];
                    }
                }
                $docentrykeys = $deletedEntries;

            }

           if(!empty($docentrykeys)) {
                //Get source document to update the state in dochdr and SFDC
                $qry = "select dochdrkey from docentry where cny#= :1";
                $qry = PrepINClauseStmt($qry, $docentrykeys, " and record# ");
                $qry = "select docid, record# recordno from dochdrmst where record# IN (".$qry.")and cny# =  :1";
                $docids = QueryResult(array($qry, $cny));

                global $gManagerFactory;
                $subscription = $gManagerFactory->getManager('imssubscription');
                if (is_array($docids)) {
                    foreach ($docids as $docid) {
                        //find if there are other recurring templates created out of the same source doc
                        //if yes, then update the state as 'B'(partially converted by line)
                        $childDocQry ='select count(1) COUNT from recurdochdrmst where cny# = :1 and record# in
                                         (select recurdochdrkey from recurdocentrymst where cny# = :1 and docentrykey in 
                                           (select record# from docentrymst where cny# = :1 and dochdrkey = :2))';
                        $res = QueryResult(array($childDocQry, $cny, $docid['RECORDNO']));
                        if ($res[0]['COUNT'] == 1) {
                            $newState = DocumentManager::PENDING_RAWSTATE;
                            $isSalesContract = 'N';
                        } else {
                            $newState = DocumentManager::PARTIALLY_CONVERTED_BY_LINE_RAWSTATE;
                            $isSalesContract = 'Y';
                        }

                        $updateQuery = "update dochdrmst set state = :1 , salescontract= :2  where record# = :3 and cny# = :4";
                        $args = array($updateQuery, $newState, $isSalesContract, $docid['RECORDNO'], $cny);

                        $ok = $ok && ExecStmt($args);

                        $doctype = explode("-", $docid['DOCID']);
                        $subscription->FillSubscriptions('Set', 'sodocument', $docid['DOCID'], $doctype[0]);
                    }
                }
            }

        }


        return $ok;
    }


    /**
     * @param string $ID
     *
     * @return array
     */
    function GetRecurHistoryList($ID)
    {
        $cny = GetMyCompany();
        $recurDocHistoryQry = "SELECT COUNT(de.dochdrkey) AS hassalecontract
                FROM docentry de
                WHERE de.cny# = :1
                    AND de.dochdrkey = :2
                    AND EXISTS (
                        SELECT 1 FROM recurdocentrymst rede 
                        WHERE rede.cny# = de.cny# AND rede.docentrykey = de.record# AND ROWNUM = 1
                    )";
        $recurDocHistory = QueryResult([$recurDocHistoryQry, $cny, $ID]);

        if (($recurDocHistory[0]['HASSALECONTRACT'] ?? 0) == 0) {
            return [];
        }

        $code = 'QRY_RECURDOCUMENT_SELECT_ALL_BASEDOC';
        $result = $this->DoQuery($code, [$cny, $ID, $cny, $cny, $cny, $cny], false);

        $recresult = array();
        foreach((($result) ?? []) as $key => $val){
            $recresult[$key]['RECURRECNO'] = $val[0];
        }


        $newresult = array();

        foreach( $recresult as $val1){
            foreach($result as $key2 => $val2){
                if($val1['RECURRECNO']==$val2[0]) {
                    $newresult[$key2]['RECURRECNO'] = $val2[0];
                    $newresult[$key2]['DOCTYPE'] = $val2[1];
                    $newresult[$key2]['RECURTRANSACTION'] = $val2[6];
                    $newresult[$key2]['LINENO'] = $val2[2];
                    $newresult[$key2]['ITEMKEY'] = $val2[3];
                    $newresult[$key2]['MEMO'] = $val2[4];
                    $newresult[$key2]['UIVALUE'] = $val2[5];
                }
            }
        }

        // This isn't really an error.
        if (!is_array($newresult) || count($newresult) == 0) {
            return array();
        }

        return $newresult;
    }

    /**
     *     When passed a line item entry or a subtotal entry, this method will
     *  perform a lookup of the department and location keys to construct valid
     *    department and location field names for the item passed.
     *
     * @param array $item header, line item or subtotal level array reference.
     */
    function BuildDeptLocation(& $item)
    {
        if(isset($item['DEPARTMENTID']) && isset($item['DEPARTMENT'])) {
            $item['DEPARTMENTNAME'] = $item['DEPARTMENT'];
            $item['DEPARTMENT']     = $item['DEPARTMENTID'].'--'.$item['DEPARTMENT'];
        } elseif (isset($item['DEPTKEY'])) {
            $deptinfo                     = $this->DeptMgr->DoQuery(
                'QRY_DEPARTMENT_SELECT_RAW_REC',
                array(GetMyCompany(),$item['DEPTKEY'])
            );
            if (isset($deptinfo)) {
                $item['DEPARTMENTID']     = $deptinfo[0]['DEPT_NO'];
                $item['DEPARTMENTNAME'] = $deptinfo[0]['TITLE'];
                $item['DEPARTMENT']     = $deptinfo[0]['DEPT_NO'].'--'.$deptinfo[0]['TITLE'];
            }
        }

        if(isset($item['LOCATIONID']) && isset($item['LOCATION'])) {
            $item['LOCATIONNAME'] = $item['LOCATION'];
            $item['LOCATION']     = $item['LOCATIONID'].'--'.$item['LOCATION'];
        } elseif (isset($item['LOCATIONKEY'])) {
            $locinfo                     = $this->LocMgr->DoQuery(
                'QRY_LOCATION_SELECT_RAW_REC',
                array($item['LOCATIONKEY'],GetMyCompany())
            );
            if (isset($locinfo)) {
                $item['LOCATIONID']     = $locinfo[0]['LOCATION_NO'];
                $item['LOCATIONNAME']     = $locinfo[0]['NAME'];
                $item['LOCATION']         = $locinfo[0]['LOCATION_NO'].'--'.$locinfo[0]['NAME'];
            }
        }
    }


    //->function CreateSchedulerEntries(& $values, &$OperValues, &$SchedValues) (((
    /**
     * Loads scheduler array structures and call the scheduleManger and operations
     * managers to create the entries.
     *
     * Updates input array to hold created 'SCHOPKEY'.
     *
     * @param  array $values
     * @param  array $OperValues
     * @param  array $SchedValues
     * @access private
     * @return bool
     */
    function CreateSchedulerEntries(& $values, &$OperValues, &$SchedValues)
    {
        global $gManagerFactory;
        $schedMgr = $gManagerFactory->getManager('schedule');

        $ok                                     = true;
        $cny                                    = GetMyCompany();
        $userid                                 = GetMyLogin(1);

        $SchedValues                             = (array)$this->SetScheduleValues($values, true);
        if (!isset($SchedValues) || $SchedValues == '') {
            $ok = false;
        }

        $ok = $ok && $schedMgr->add($SchedValues);
        //we need to assign the record# back to RECORDNO because the SchedulerService is now using 'RECORDNO'
        //to retrieve this object rather than the old way through NAME. This makes it consistent with
        //using the scheduler script
        $SchedValues['RECORDNO'] = $SchedValues[':record#'];

        //Fill up operation table values
        $SchedKey                                 = $SchedValues[':record#'];    //For use in mapping table scheduledoperation
        $OperValues['CNY#']                     = $SchedValues['CNY#'];
        $OperValues['NAME']                     = $SchedValues['NAME'];        //Same name is used as schedule
        $OperValues['DESCRIPTION']                 = $SchedValues['DESCRIPTION'];
        $OperValues['USERNO']                     = $userid;
        $OperValues['ENTITY']                     = $this->_scheduleentity;
        $OperValues['ACTION']                     = 'RECUR';        //This is API which will be called by scheduler adapter
        $OperValues['STATUS']                     = $values['STATUS'];
        $OperValues['MODULEKEY']                 = $this->_modid;
        $OperValues['LOCATIONKEY']                 = Profile::getProperty('LOCATIONKEY');
        $OperValues['CONTACTEMAIL']             = $values['SCHEDULEDCONTACTEMAIL'] ?? GetMyContactEmail();

        //$OperValues['RETRYLIMITCOUNT'] = $values['SCHEDULEDRETRYLIMITCOUNT'];
        //$OperValues['ALLOWRETRY'] = $values['SCHEDULEDALLOWRETRY'];

        $ok = $ok && $this->OperMgr->add($OperValues);

        //For translate of scheduledoperation manager
        $OperKey                                 = $OperValues[':record#'];    //For use in mapping table scheduledoperation
        $SchedOperValues['NAME']                 = $SchedValues['NAME'];
        $SchedOperValues['OPERATION']['NAME']     = $SchedValues['NAME'];
        $SchedOperValues['SCHEDULE']['NAME']     = $SchedValues['NAME'];
        $SchedOperValues['DESCRIPTION']         = $SchedValues['DESCRIPTION'];
        $SchedOperValues['USERNO']                 = $userid;
        $SchedOperValues['CNY#']                 = $cny;
        $SchedOperValues['STATUS']                 = $values['STATUS'];
        $SchedOperValues['SCHEDULE#']             = $SchedKey;
        $SchedOperValues['OPERATION#']             = $OperKey;
        $SchedOperValues[':schedule#']             = $SchedKey;
        $SchedOperValues[':operation#']         = $OperKey;

        $ok = $ok && $this->SchedOperMgr->add($SchedOperValues);

        //The scheduled operation key is stored in recurring invoice table
        $SchedOperKey                             = $SchedOperValues[':record#'];
        $values['SCHOPKEY']                     = $SchedOperKey;
        return $ok;
    }

    /**
     *  Get the object to delete
     *
     * Need to override this function so it uses the EntityManager function and not
     * the overidden one from DocumentManager
     *
     * @param string $ID  the ID of the object to delete
     *
     * @return array the object to delete
     */
    protected function getForDelete($ID)
    {
        return $this->entityManagerGetForDelete($ID);
    }


    /**
     * Delete logic for RecurDocument object
     *
     * @param  string  $ID
     * @param bool $forceDelete
     *
     * @access public
     * @return bool
     */
    function Delete($ID, $forceDelete = false)
    {
        global $gManagerFactory;
        $source                 = 'RecurDocumentManager::Delete';
        $ok                     = true;

        // Create managers required to get document
        $docparMgr                 =  $gManagerFactory->getManager('documentparams');
        $recurdocMgr            =  $gManagerFactory->getManager('recurdocument');
        $recurdocentryMgr         =  $gManagerFactory->getManager('recurdocumententry');
        $recursubtotalsMgr         =  $gManagerFactory->getManager('recursubtotals');
        $SalesContractSchMgr         =  $gManagerFactory->getManager('salescontractschedule');

        //Retrieve doc header to prep for mega-company check and get schedule details
        $RecurDocumentVal         = $recurdocMgr->GetRaw($ID);
        if (!isset($RecurDocumentVal)) {
            $msg             = "Unable to get recurring transaction record, resubmit the request";
            Globals::$g->gErr->addIAError('INV-0806', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        // check for the child transaction if the template is part of Sales Contract
        if(isset($RecurDocumentVal[0]['DOCHDRKEY']) && $RecurDocumentVal[0]['DOCHDRKEY']!='') {
            $queryItems = array(
            'QUERY'     => "SELECT	count(dh.record#) count FROM dochdr dh, recurdochdr rr
					WHERE	dh.cny# = rr.cny# and dh.schopkey = rr.schopkey 
							and rr.cny# = :1 and rr.record# = :2 ",
            'ARGTYPES'     => array('integer','integer')
            );

            $resultSet = $this->_QM->DoCustomQuery($queryItems, array( GetMyCompany(), $ID), true);

            if ($resultSet[0]['COUNT']>0) {
                $msg = "Recurring Template cannot be deleted as it is part of Sales Contract and referenced by other transactions.";
                Globals::$g->gErr->addIAError('INV-0807', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }
        }

        $ok                     = $ok && $this->IsDeletable($ID); // MAKE SURE THE OBJ IS DELETEABLE FOR MEGA COMPANIES

        //Everything is fine at this point....ok to start deleting things
        $ok                     = $ok && $this->_QM->beginTrx($source);
        if (!$ok) {
            return $ok;
        }

        $docObj = $this->BaseGet($ID);
        $docObj['_DOCPAR']         = $docparMgr->BaseGet($docObj['DOCPARKEY']);
        $docObj['ENTRIES']         = $recurdocentryMgr->GetByParent($docObj['RECORDNO']);
        $docObj['SUBTOTALS']     = $recursubtotalsMgr->getByParent($docObj['RECORDNO']);

        //reverse the status of qty in parent document
        $mode  = 'DELETE';
        $ok = $ok && $this->UpdateParentQtyConverted($docObj, $mode);
        $ok = $ok && $this->UpdateParentConvertStatus($docObj, $mode);

        //delete sales contract schedule entries
        $ok = $ok && $SalesContractSchMgr->Delete($docObj['RECORDNO']);

        // No need to delete the corresponding schedule records -- that is handled by a trigger
        $ok                     = $ok && $this->_IsTransactionDeletable($docObj, $forceDelete, false);
        $ok                     = $ok && $this->entityManagerDelete($ID);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg                 = "Could not delete recurring transaction template record with ID $ID!";
            Globals::$g->gErr->addIAError('INV-0808', __FILE__ . ':' . __LINE__, $msg, ['ID' => $ID]);
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }


    /**
     * @param array $raw
     *
     * @return bool
     */
    protected function beforeDelete(&$raw)
    {
        global $gManagerFactory;
        $documententryMgr = $gManagerFactory->getManager('recurdocumententry');
        return $documententryMgr->deleteByParent($raw[0]['RECORD#'], DELETE_FOR_DELETE);
    }


    /**
     * Locates scheduler entries and calls the
     * scheduleManger and operations managers
     * to delete the entries.
     * @param string $pSchopKey
     *
     * @return bool
     */
    function DeleteSchedulerEntries($pSchopKey)
    {
        global $gManagerFactory;
        $source                 = 'RecurDocumentManager::DeleteSchedulerEntries';
        $ok                     = true;
        $cny                     = GetMyCompany();

        //Get SchduledOperation info
        //Custom query since scheduled operation name is not known at this time
        $queryItems             = array(
        'QUERY'     => 'SELECT * FROM scheduledoperation WHERE cny# = ? AND record# = ?',
        'ARGTYPES'     => array('integer','integer')
        );

        $SchedOpVal             = $this->_QM->DoCustomQuery($queryItems, array($cny,$pSchopKey), true);
        if (!isset($SchedOpVal)) {
            $msg             = "Unable to get scheduled operation record, resubmit the request";
            Globals::$g->gErr->addIAError('INV-0809', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        $SchedOpVal             = $SchedOpVal[0];
        $ok                     = $ok && $this->SchedOperMgr->Delete($SchedOpVal['NAME']);
        if (!$ok) {
            $msg             = "Unable to delete scheduled operation, resubmit the request";
            Globals::$g->gErr->addIAError('INV-0810', __FILE__ . ':' . __LINE__, $msg, []);
            $this->_QM->rollbackTrx($source);
            return false;        /* Since there might be other sched. operations not belonging to current */
        }

        //Check whether any foreign key dependencies exist
        $queryItems                = array(
        'QUERY'     => 'SELECT COUNT(*) FROM scheduledoperation WHERE cny# = ? AND schedule# = ?',
        'ARGTYPES'     => array('integer','integer')
        );

        $ok                     = $ok && $count = $this->_QM->DoCustomQuery(
            $queryItems,
            array($cny,$SchedOpVal['SCHEDULE#']),
            true
        );
        /** @noinspection PhpUndefinedVariableInspection */
        $count                     = $count[0]['COUNT(*)'];
        if ($count > 1) {
            $msg             = "Unable to delete schedule, this schedule is in use by some other operation";
            Globals::$g->gErr->addIAError('INV-0811', __FILE__ . ':' . __LINE__, $msg, [], 'Resubmit the request', []);
            $this->_QM->rollbackTrx($source);
            return false;
        }

        $schedMgr = $gManagerFactory->getManager('schedule');
        $ok = $ok && $schedMgr->Delete($SchedOpVal['NAME']);
        //To avoid creating IMS job in shutdown function
        $gManagerFactory->DeleteManager('schedule');

        if (!$ok) {
            $msg             = "Unable to delete schedule, this schedule is in use by some other operation";
            Globals::$g->gErr->addIAError('INV-0812', __FILE__ . ':' . __LINE__, $msg, []);
            $this->_QM->rollbackTrx($source);
            return false;
        }

        //Check whether any foreign key dependencies exist
        $queryItems             = array(
        'QUERY'     => 'SELECT COUNT(*) FROM scheduledoperation WHERE cny# = ? AND operation# = ?',
        'ARGTYPES'     => array('integer','integer')
        );

        $ok                     = $ok && $count = $this->_QM->DoCustomQuery(
            $queryItems,
            array($cny,$SchedOpVal['OPERATION#']),
            true
        );
        $count                     = $count[0]['COUNT(*)'];

        if ($count > 1) {
            $msg             = "Unable to delete operation, this operation is in use by some other schedule";
            Globals::$g->gErr->addIAError('INV-0813', __FILE__ . ':' . __LINE__, $msg, [], 'Resubmit the request', []);
            $this->_QM->rollbackTrx($source);
            return false;
        }

        $ok                     = $ok && $this->OperMgr->Delete($SchedOpVal['NAME']);

        if (!$ok) {
            $msg             = "Unable to delete operation, resubmit the request";
            Globals::$g->gErr->addIAError('INV-0814', __FILE__ . ':' . __LINE__, $msg, []);
            $this->_QM->rollbackTrx($source);
            return false;
        }

        return $ok;
    }



    /**
     * Called in conjunction with IMS processing in the event that a new document
     * generated errors during creation.
     *
     * Call must be implemented in child class to format proper data from $values array.
     *
     * @param  array $values
     * @return string
     */
    function FormatEmailDocumentDetails(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
         return $this->emailToken->applyPlaceholders(
             'body.defaultDocDetails',
             []
         );
    }

    /**
     * Retrieve a RecurDocument object
     * @param string $ID
     * @param array    $fields
     *
     * @return array|false
     */
    function Get($ID, $fields=null)
    {
        $ok = true;
        $res = $this->entityManagerGet($ID);
        if ($res === false) {
            return false;
        }

        $this->BuildDeptLocation($res);
        // the summarized subtotals will be shown for Root level and not owned documents only
        // ideally this should be a document preference
        //for($j=0; $j<count($res['SUBTOTALS']); $j++){
        foreach($res['SUBTOTALS'] as & $subtotal){
            $this->BuildDeptLocation($subtotal);
        }
        unset($subtotal);

        $this->showSubTotals($res);

        $this->processSubtotalsForDimensions($res);

        //		$ok = $this->GetScheduledDetails($res);

        for ($i=0;$i<count($res['ENTRIES']);$i++ ) {

            $itemid = $res['ENTRIES'][$i]['ITEMID'];

            $qry = "select name from icitem where itemid=:1 and cny#=:2";
            $result =  QueryResult(array($qry,$itemid,GetMyCompany()));
            $itemname = $result[0]['NAME'];
            $res['ENTRIES'][$i]['ITEMID'] = $res['ENTRIES'][$i]['ITEMID'].'--'.$itemname;

            //Only specific to the XML 2.1 request changes for get and get_list, since the REPEATBY values are
            // 'None', 'Days', 'Weeks', 'Months', 'EndOfMonth', 'Years' we need to convert them to
            // 'N', 'D', 'W', 'M', 'E', 'Y'. So that there will not be any change in response
            // and integration  due to FormEditor enhancement.
            if( ($this->fromGateway || $this->_fromAPI) && isset($res['REPEATBY']) && $res['REPEATBY'] != ''){
                $res['REPEATBY'] = isl_substr($res['REPEATBY'], 0, 1);
            }

        }

        if (!$ok) {
            return false;
        }

        if (isset($res) && $res != '') {
            return $res;
        } else {
            return false;
        }
    }

    /**
     * @param array  &$obj
     */
    public function processSubtotalsForDimensions(&$obj)
    {
        if (!isset($obj['RECORDNO']) || empty($obj['RECORDNO'] ?? '')) {
            return;
        }

        $mod = $this->getMyInstanceMod();
        $subTotObj = GetSubTotalsHelper($mod);

        $mayHaveCommonDims = ($subTotObj->_copyDimensionsFromLineitem
            || $subTotObj->_overrideDimensionsFromSubtotals
            || $subTotObj->_distributeSubtotalsAtEntity);

        if (!$mayHaveCommonDims) {
            return;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;
        $docSubTotalsMgr = $gManagerFactory->getManager($mod . 'recursubtotals');
        $dochdrkey = $obj['RECORDNO'];

        $subtotalParams = array(
            'selects' => array(
                'DOCHDRNO',
                'DESCRIPTION',
                'LOCATIONID',
                'DEPARTMENTID',
            ),
        );

        $allDimFieldIDs = ['LOCATIONID', 'DEPARTMENTID'];
        $allDimFieldNames = ['LOCATIONID' => 'LOCATION',
            'DEPARTMENTID' => 'DEPARTMENT'];

        $dimFields = $docSubTotalsMgr->GetDimensionFields();

        if (is_array($dimFields)) {
            foreach ($dimFields as $field) {
                if (!$field['standard']) {
                    continue;
                }

                $fieldid = isl_strtoupper($field['path']);
                $subtotalParams['selects'][] = $fieldid;
                $subtotalParams['selects'][] = $field['dimdbkey'];
                $allDimFieldIDs[] = $fieldid;

                if ($field['dimNameField'] ?? null) {
                    foreach ($field['dimNameField'] as $key => $value) {
                        $allDimFieldNames[$fieldid] = isl_strtoupper($key);
                        $subtotalParams['selects'][] = isl_strtoupper($key);
                    }
                }
            }
        }

        if (!util_isPlatformDisabled()) {
            $custdim_fields_map = $docSubTotalsMgr->customDimFields;

            foreach ($custdim_fields_map as $custFieldId => $custField) {
                $subtotalParams['selects'][] = $custFieldId;
                $allDimFieldIDs[] = $custFieldId;
                $allDimFieldNames[$custFieldId] = isl_strtoupper($custFieldId);
                $allDimFieldNames[$custFieldId.'_disp'] = isl_strtoupper($custFieldId).'_disp';

                $rel = Pt_RelationshipDefManager::getById($custField['id']);
                if ($rel) {
                    $relName = $rel->getRelationshipName();
                    $subtotalParams['selects'][] = $relName;
                    $allDimFieldIDs[] = $relName;
                    $allDimFieldNames[$relName] = isl_strtoupper($relName);
                }
            }
        }

        $subtotalParams['filters'] = [[['DOCHDRNO', '=', $dochdrkey]]];
        $subtotals = $docSubTotalsMgr->GetList($subtotalParams);
        $subtotalsByDisc = [];
        foreach ($subtotals as $subtotal) {
            $docSubTotalsMgr->TransformDimensionValues($subtotal, $nullObj, true);
            $subtotalsByDisc[$subtotal['DESCRIPTION']][] = $subtotal;
        }

        $subtotalsWithCommonDims = [];
        foreach ($subtotalsByDisc as $dispKey => $subtotal) {
            if (count($subtotal) > 0) {
                $firstSubtotal = $subtotal[0];

                for ($i = 1; $i < count($subtotal); $i++) {
                    $tmp = array_intersect_assoc($firstSubtotal, $subtotal[$i]);
                    $firstSubtotal = $tmp;
                }

                $subtotalsWithCommonDims[$dispKey] = $firstSubtotal;
            }
        }

        foreach ($obj['SUBTOTALS'] as &$subtoal) {
            if ($subtotalsWithCommonDims[$subtoal['DESCRIPTION']]) {
                foreach ($allDimFieldIDs as $dimFieldID) {
                    $dimFeildName = $allDimFieldNames[$dimFieldID];

                    if (!array_key_exists($dimFieldID, $subtotalsWithCommonDims[$subtoal['DESCRIPTION']])) {
                        $subtoal[$dimFieldID] = '';
                        if ($dimFeildName != '') {
                            $subtoal[$dimFeildName] = '';
                        }
                        if (array_key_exists($dimFieldID.'_disp', $subtoal)) {
                            $subtoal[$dimFieldID.'_disp'] = '';
                        }
                    } else {
                        $subtoal[$dimFieldID] = $subtotalsWithCommonDims[$subtoal['DESCRIPTION']][$dimFieldID];
                        $subtoal[$dimFeildName] = $subtotalsWithCommonDims[$subtoal['DESCRIPTION']][$dimFeildName];

                        if (array_key_exists($dimFieldID . '_disp', $allDimFieldNames)) {
                            if ((isset($subtoal[$dimFieldID]) && $subtoal[$dimFieldID] != '')) {
                                $data = Pt_DataObjectManager::getById2($subtoal[$dimFieldID]);
                                $subtoal[$dimFieldID . '_disp'] = $data->getName();
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * Get a single record no lineitems
     *
     * @param string $ID
     * @param string[]|null $fields
     *
     * @return array|false
     */
    function BaseGet($ID, $fields=null)
    {
        $mod = $this->getMyInstanceMod();
        $docIDRes = $this->DoQuery('QRY_RECURDOCUMENT_GET_DOCPARID_FOR_THIS_RECURDOC', array($ID));
        $this->_docType = $docIDRes[0]['DOCID'];

        $doc = $mod.'document';
        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        // Enable this 2 lines and the MergeQueries call on the else clause to make API READ work on recurdoc
        //$this->removeCustomFields();
        //$this->invalidateQueries();
        if($hasCustomFields) {

            $this->_entity = $mod.'document';

            $this->LoadFields();

            $this->_entity = $mod.'recurdocument';

            $this->MergeTableInfo();  // add schema information to $kTables

            $this->MergeObjectSchema();  // build the paths

            // MERGE kSchemas['object']
            $this->MergeObjectFieldList(); // add the custom fields to the object field list.

        } else {
            // we have to force merge queries here because a previous Get() in the same UOW could have been for
            // different doc type that mgiht have had custom fields
            // if the current doctype also has custom fields, the parent::BaseGet would redo the queries
            //$this->MergeQueries();
        }

        return parent::BaseGet($ID);
    }



    /**
     * Retrieve associated scheduler details
     *
     * @param  array $res this array is updated with scheduler details
     *
     * @return bool
     */
    function GetScheduledDetails(& $res)
    {
        $cny                 = GetMyCompany();
        $ok                 = true;

        //Only one record is expected since different schedules are created for
        //different recurring transaction templates and they are not reused.
        //
        //All schedules are selected irrespective of status since user is allowed
        //to reactivate expired schedules, hence status is not part of query
        $qString              = '';
        $qString             .= 'SELECT startdate, enddate, repeatby, repeatcount, repeatinterval ';
        $qString             .= 'FROM schedule ';
        $qString             .= 'WHERE cny# = ? AND ';
        $qString             .= 'RECORD# IN (SELECT schedule# FROM scheduledoperation WHERE cny# = ? AND record# = ?)';

        $queryItems = array(
        'QUERY'     => $qString,
        'ARGTYPES'     => array('integer','integer','integer')
        );

        //Get the schedule information for this entity (vendor or customer)
        $result             = $this->_QM->DoCustomQuery($queryItems, array($cny,$cny,$res['SCHOPKEY']), true);

        if (!isset($result)) {
            $msg             = "Could not retrieve schedule record, please resubmit the request";
            Globals::$g->gErr->addIAError('INV-0815', __FILE__ . ':' . __LINE__, $msg, []);
            return false;    //Since recurring transaction templates must have a schedule
        }

        //Set the fields on second tab
        //Ending on option
        $result             = $result[0];
        $res['STARTDATE']     = $result['STARTDATE'];
        $res['ENDDATE']     = $result['ENDDATE'];
        $res['REPEATCOUNT'] = $result['REPEATCOUNT'];        //No of occurrences is repeat count
        $res['REPEATBY']     = $result['REPEATBY'];
        $res['INTERVAL']     = $result['REPEATINTERVAL'];

        return $ok;
    }


    /**
     * Prepare the Line Item values of the document. Validates the line items of the $values array structure.
     * Initialize dictionary values. Needed in case of exception to throw the proper error text.
     * Gather the department, location, glaccount informations.
     * Instantiate the various managers [Item, DocEntry, Warehouse, UOM]
     * Cache the values of Item, Warehouse, UOM
     * Loop through the entries of the values array and Validate for Item, Warehouse, Department, Location.
     * Append item information into the ENTRIES array like precision, desc etc.
     * Calculate the pricing values by using the suggestprice method of PricingHandler.
     *
     * @param  array             &$values values of the document.
     * @param  TrackingHandler[] $handlers
     * @param  bool $newdoc
     *
     * @return bool $ok returns if the method execution was success or not.
     */
    function PrepLineItems(&$values, $handlers=[], $newdoc = true, bool $forPrinting=false)
    {
        global $gManagerFactory;

        $ok = true;
        $dict = Dictionary::getInstance();
        BuildPRMaps();
        global $deptmapno, $locmapno;

        $itemMgr = $gManagerFactory->getManager('item');

        $updatesInv = $values['_DOCPAR']['UPDATES_INV'];

        //splitting warehouseid-name and passing warehouseid
        for ($i=0; $i<(count($values['ENTRIES'])); $i++){
            $itemid = explode('--', $values['ENTRIES'][$i]['ITEMID']);
            $values['ENTRIES'][$i]['ITEMID']=$itemid[0] ;
            $warehouseid = explode('--', $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']);
            $values['ENTRIES'][$i]['WAREHOUSE']['LOCATION_NO']=$warehouseid[0] ;

            $values['ENTRIES'][$i]['BASECURR'] = $values['BASECURR'];

            $IsitemSerialized = $itemMgr->IsItemSerialized($itemid[0]);
            if($IsitemSerialized && ($updatesInv =='Quantity' || $updatesInv =='Quantity and Value')) {
                $ok = false;
                $msg = "Items which are enabled for serial, lot , aisle-row-bin tracking can not be used in recurring transactions";
                Globals::$g->gErr->addIAError('INV-0816', __FILE__ . ':' . __LINE__, $msg, []);
                /** @noinspection PhpUndefinedVariableInspection */
                epp("$source: Error: $msg");
            }
        }
        //splitting warehouse id and provide warehousekey for $values['WAREHOUSE']['LOCATION_NO']
        $wareid = explode('--', ($values['WAREHOUSE']['LOCATIONID'] ?? ''));
        $values['WAREHOUSE']['LOCATIONID']=$wareid[0] ;

        $ok = $ok && parent::PrepLineItems($values, $handlers,$newdoc,$forPrinting);

        // ENABLE_OVERRIDE_TRANSACTION_CONVERSIONTYPE validation is not required for the recurring templete
        // This validation used only for OE/PO transaction validation.
        $priceConversionPrefs = [
            'ENABLE_PRICECONVERSION' => $this->isPriceConversionEnabled(),
            'ENABLE_OVERRIDE_TRANSACTION_CONVERSIONTYPE' => false
        ];

        foreach($values['ENTRIES'] as $key => $line) {
            //check to skip undefined entries
            if (!isset($line) || !isset($line['ITEMID'])) {
                continue;
            }

            $lineno = $line['LINENO'];
            if (!empty($line['DEPARTMENT'])) {
                $dept                     = explode('--', $line['DEPARTMENT']);
                $deptkey                 = $deptmapno[$dept[0]];
                $values['ENTRIES'][$key][':deptkey'] = $deptkey;
                if (!$deptkey) {
                    Globals::$g->gErr->addIAError('INV-0817', __FILE__ . '.' . __LINE__, null,
                                                  [ 'LINENO' => $lineno, 'DEPT_0' => $dept[0] ]);
                    $ok = false;
                }
            }

            if (!empty($line['LOCATION'])) {
                $loc = explode('--', $line['LOCATION']);
                $lockey = $locmapno[$loc[0]];
                $values['ENTRIES'][$key][':locationkey'] = $lockey;
                if (!$lockey) {
                    Globals::$g->gErr->addIAError('INV-0818', __FILE__ . '.' . __LINE__, null,
                                                  [ 'LINENO' => $lineno, 'LOC_0' => $loc[0] ]);
                    $ok = false;
                }
            }

            //create the item entry query replacement values
            $entry_line                     = &$values['ENTRIES'][$key];
            $entry_line[':lineno']             = $key+1;
            $entry_line[':itemdescr']         = $entry_line['ITEMDESC'] ?: '';
            $entry_line[':unit']             = $line['UNIT']?:'';
            $entry_line[':warehousekey']     = $line['WAREHOUSE']['LOCATION_NO'] ?: $values['WAREHOUSE']['LOCATIONID'];
            $entry_line[':whenmodified']     = GetCurrentDate();
            $entry_line[':state']             = 'T';

            //for mapping docentry.record# to recurdocentry.docentrykey
            if(isset($entry_line['PARENTDOCENTRYKEY'])) {
                $entry_line['DOCENTRYKEY'] = $entry_line['PARENTDOCENTRYKEY'];
            }

            $enableOverrideTax =  $values['_DOCPAR']['ENABLEOVERRIDETAX'];
            if( $enableOverrideTax != 'true' && isset($line['OVERRIDETAX'])) {
                $ok = false;
                $msg = "Override line item tax is not enabled for this Transaction Definition.";
                Globals::$g->gErr->addIAError('INV-0819', __FILE__ . ':' . __LINE__, $msg, []);
                /** @noinspection PhpUndefinedVariableInspection */
                epp("$source: Error: $msg");
            }

            //Prepare & validate the price conversion for the line item
            $ok = $ok && $this->processPriceConversionForLine($values, $key, $priceConversionPrefs, $newdoc);
        }

        return $ok;
    }


    /**
     * @param array $entry
     * @param int $index
     * @param array $priceConversionPrefs
     * @param bool $isConvertByLine
     * @param bool $newdoc
     * @return bool
     */
    private function processPriceConversionForLine(&$values, $key, $priceConversionPrefs, $newdoc)
    {
        $ok = true;
        $isConvertByLine = ((Request::$r->_salecon ?? '') == 'T' || ($values['SALESCON'] ?? '') == 'T');
        // If this is regular add and convert by line time crearting the templete
        if ($isConvertByLine) {
            $ok = $ok && $this->prepareConversionTypeForConvertByLine($values, $key, $priceConversionPrefs);
        } else {
            $ok = $ok && $this->prepareConversionTypeForRecurTemplate($values, $key, $priceConversionPrefs);
        }

        // In the time of convert by line recurring template, the line item will have recordno value even for a new line item
        // Only new line in edit or add action and convert by line recurring template need to validate the price conversion
        // We need to skip for existing line items
        if (empty($values['ENTRIES'][$key]['RECORDNO'] ?? '') || $isConvertByLine) {
            //Validate that Price conversion.
            $ok = $ok && $this->validatePriceConversion($values, $values['ENTRIES'][$key], $priceConversionPrefs, $newdoc);
        }

        return $ok;
    }

    /**
     * @param array $entry
     * @param int $index
     * @param array $priceConversionPrefs
     *
     * @return bool
     */
    protected function prepareConversionTypeForConvertByLine(&$values, $index, $priceConversionPrefs)
    {
        $entry = &$values['ENTRIES'][$index] ?? [];
        // PARENTDOCENTRYKEY value will be of the parent line entry recordno this will be present only for convert by line recurring temple only
        if (empty($entry['PARENTDOCENTRYKEY'] ?? '')) {
            return true;
        }

        // PARENTDOCENTRYKEY value will be set for convert by line recurring temple only
        // Conversion type value should be from the source document line item conversiontype.
        $entry['CONVERSIONTYPE'] = $entry['SOURCE_CONVERSIONTYPE'] ?? 'Quantity';

        return true;
    }


    /**
     * @param array $entry
     * @param int $index
     * @param array $priceConversionPrefs
     *
     * @return bool
     */
    protected function prepareConversionTypeForRecurTemplate(&$values, $index, $priceConversionPrefs)
    {
        $entry = &$values['ENTRIES'][$index] ?? [];
        // PARENTDOCENTRYKEY value will be of the parent line entry recordno this will be present only for convert by line recurring temple only
        // SALESCON or Request::$r->_salecon value will be set for convert by line recurring template only
        // Because convert by line recurring template has recordno value in the line item even for a new line item
        // $isConvertByLine = ((Request::$r->_salecon ?? '') == 'T' || ($values['SALESCON'] ?? '') == 'T');
        if (!empty($entry['RECORDNO'] ?? '')) {
            return true;
        }

        // When price conversion doesn't enable, conversion type should always quantity by default
        if (($priceConversionPrefs['ENABLE_PRICECONVERSION'] ?? false) == false) {
            $entry['CONVERSIONTYPE'] = 'Quantity';
            return true;
        }

        $itemid = explode('--', ($entry['ITEMID'] ?? ''))[0] ?? '';
        $item = $this->itemRawCache[$itemid] ?? [];

        // Conversion type value should be from the Item Object.
        $itemConversionType = (!empty($entry['ITEMID'])
            && !empty($item['DEFAULTCONVERSIONTYPE'] ?? '')) ? $item['DEFAULTCONVERSIONTYPE'] : 'Q';
        $entry['CONVERSIONTYPE'] = (($itemConversionType == 'P') ? 'Price' : 'Quantity');

        return true;
    }

    /**
     * @param array $entry
     * @param int $index
     * @param array $priceConversionPrefs
     *
     * @return bool
     */
    protected function prepareConversionType(&$values, $index, $priceConversionPrefs)
    {
        return true;
    }

    /**
     * @param array         $values
     * @param TrackingHandler[] $handlers
     * @param bool          $newdoc
     * @param array|null         $getTaxRequest
     * @param string|null        $entityTaxable
     *
     * @return bool
     */
    function PrepValues(&$values, $handlers, $newdoc = true, &$getTaxRequest = null, &$entityTaxable = null)
    {
        global $gManagerFactory;

        $source = "RecurDocumentManager::PrepValues()";
        $mod = $this->getMyInstanceMod();
        if (is_null($mod)) {
            throw new InvalidArgumentException(
                "RecurDocumentManager::PrepValues: Required mod parameter is not provided.");
        }

        /** @var DocumentParamsManager $docparMgr */
        $docparMgr            = $gManagerFactory->getManager($mod . 'documentparams');
        $shipmethodMgr        = $gManagerFactory->getManager('shipmethod');

        $ok = $this->_QM->beginTrx($source);

        // Set WHENMODIFIED to current date for both Add and Set
        $values['WHENMODIFIED'] = GetCurrentDate();

        $defaultdeptkey             = '';
        $defaultlockey                 = '';

        $basecurr = ($values['BASECURR'] ?: GetBaseCurrency());
        if (!$values['BASECURR'] && !$basecurr) {
            Globals::$g->gErr->addIAError('INV-0220', __FILE__ . ":" . __LINE__, "The record requires the field base currency", []);
            return false;
        } elseif (!$values['BASECURR']) {
            $values['BASECURR'] = $basecurr;
        }

        if(isset($values['PARENTDOCHDRKEY'])) {
            $values['DOCHDRNO'] = $values['PARENTDOCHDRKEY'];
        }
        if (isset($values['DEPARTMENT'])) {
            $dept                     = explode('--', $values['DEPARTMENT']);
            $deptinfo                 = $this->DeptMgr->GetRaw($dept[0]);
            if ($deptinfo) {
                $defaultdeptkey     = $deptinfo[0]['RECORD#'];
            }
            else {
                Globals::$g->gErr->addIAError('INV-0820', __FILE__ . '.' . __LINE__, null, [ 'DEPT_0' => $dept[0] ]);
                $ok                 = false;
            }
        }

        if (isset($values['LOCATION'])) {
            $loc                     = explode('--', $values['LOCATION']);
            $locinfo                 = $this->LocMgr->GetRaw($loc[0]);
            if ($locinfo) {
                $defaultlockey         = $locinfo[0]['RECORD#'];
            }
            else {
                Globals::$g->gErr->addIAError('INV-0821', __FILE__ . '.' . __LINE__, null, [ 'LOC_0' => $loc[0] ]);
                $ok = false;
            }
        }

        if (!$values['DOCPARID'] && !$values['ENTRIES'][0]['SC_EXISTINGSCHED']) {
            // ******* ADD ERROR
            Globals::$g->gErr->addIAError('INV-0221', GetFL(), 'Missing DOCPARID', []);
            $ok = false;
        }

        if ($ok) {
            $docpar = $docparMgr->GetLatest($values['DOCPARID'], false);
            $ok = $ok && isset($docpar);

            $values[':docparkey'] = $docpar['RECORDNO'];

            // need extra processing for location in mega companies if the document is converted by line
            $salecon = (Request::$r->_salecon == 'T') ? true : false;
            if($salecon) {
                $this->ProcessDepartmentLocationfor_DocparSubtotals($docpar, $values['DOCHDRNO']);
            }

            $values['_DOCPAR'] = $docpar;

            $iscustomer = ($docpar['CUST_VEND'] == 'Customer');
        }

        if ($ok && $mod != 'inv') {
            $ok = $ok && $this->ValidEntityID($values['CUSTVENDID']);
            if (!$ok) {
                Globals::$g->gErr->addIAError(
                    'INV-0822', GetFL(),
                    'The entity id ' . $values['CUSTVENDID'] . ' is invalid.',
                    ['VALUES_CUSTVENDID' => $values['CUSTVENDID']]
                );
            }
        }
        // ************************** verify and/or create DOCID (docno)

        //$ok = $ok && $this->ValidateDates($values);
        if ($ok ) {
            if ($values['TERM']['NAME'] ) {
                /** @noinspection PhpUndefinedVariableInspection */
                $termMgr = $gManagerFactory->getManager(( $iscustomer ? 'ar' : 'ap' ) . 'term');
                $term = $termMgr->GetRaw($values['TERM']['NAME']);
                if ( ! $values['ENTRIES'][0]['SC_EXISTINGSCHED'] ) {
                    $ok = $ok && isset($term[0]);
                }
                if ( ! $ok ) {
                    Globals::$g->gErr->addIAError('INV-0222', __FILE__ . ':' . __LINE__, "The Term Name is invalid.", []);
                }
                GetStaticTermRecNo($term[0]['RECORD#'], $termKey);

                $values['TERMKEY'] = $termKey; // to match with parent class we should use the object property rather than the db fields
            } else {
                $values['TERMKEY'] = null; // on edit if we remove the term we should reset the termkey
            }
        }

        if ($ok && $values['SHIPVIA']) {
            $method = $shipmethodMgr->GetRaw($values['SHIPVIA']);
            $ok = $ok && isset($method[0]);
            $values[':shipviakey'] = $method[0]['RECORD#'];
        }

        //Always Get the latest Bill To and Ship To addresses
        $values['GETLATESTBILLTO'] = 'true';
        $values['GETLATESTSHIPTO'] = 'true';

        global $_userid;
        $arrExplode = explode('@', $_userid);
        $values['USER'] = array_shift($arrExplode);

        /** @noinspection PhpUndefinedVariableInspection */
        $ok = $ok && $this->PrepareEntityValues($values, $docpar);

        foreach( $values['ENTRIES'] as $line) {
            // 1. in case of convert by line 'LINESELECT' is not set
            // 2. in case of Repeate process 'LINESELECT' is set to true
            // filters all the line which are not selected in case of Repeat process
            if (!isset($line['LINESELECT']) || $line['LINESELECT'] == 'true') {
                $entries[]=$line;
            }
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $values['ENTRIES']=$entries;

        if ( $ok && (! isset($values['ENTRIES']) || count($values['ENTRIES']) < 1 )) {
            $ok = false;
            $msg = "There must be at least one line item!";
            Globals::$g->gErr->addIAError('INV-0823', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
        }

        if($this->_ismcpEnabled) {
            //
            // The exchange rate will be calculated when transaction is created from this template
            // recurring templates created from XML & CVS may not have these fields
            if(!isset($values['EXCHRATEDATE']) || $values['EXCHRATEDATE']=='') {
                $values['EXCHRATEDATE'] = (isset($values['WHENCREATED']) && $values['WHENCREATED']!='') ? $values['WHENCREATED'] : GetCurrentDate();
            }

            if((!isset($values['EXCHRATE']) || empty($values['EXCHRATE']?? '')) && ($values['CURRENCY']?? '') != $basecurr) {
                $gManagerFactory = Globals::$g->gManagerFactory;
                $exchangeRateMgr = $gManagerFactory->getManager('exchangerate');
                //
                // calculate the exchange rate
                $values['EXCHRATE'] = $exchangeRateMgr->GetTrxExchangeRate(
                    $values['EXCHRATETYPES']['NAME'],
                    $values['CURRENCY'],
                    $basecurr,
                    $values['EXCHRATEDATE']
                );
            }

            $ok = $ok && $this->validateMCPFields($values);
        }

        //We need to prep values for VAT fields. This prep needs to be done before PrepLineItems
        //as it depends on the values this call will set
        $ok = $ok && $this->PrepValuesForTaxSolution($values);

        // setting up of line numbers here is very much required for functionalities like PO allocations
        $this->setLineNumbers($values);
        $ok = $ok && $this->PrepLineItems($values, $handlers);

        // this validation must be done after preplineitems since PO allocations split entries and sets locations
        $ok = $ok && $this->checkForValidTaxLocations($values);

        //		// calculate subtotals if any that this document produce
        //		if ( $ok && $values['_DOCPAR']['SHOW_TOTALS'] == 'true' ) {
        //			$this->CalcSubTotals($values);
        //		}

        // Append dimension field information to the docvalues structure that will be used by the subtotals logic.
        $values['DIMENSIONFIELDS'] = $this->GetDimensionFields();
        $values['PRIMARYDIMENSION'] = $this->getPrimaryDimensions();

        $ok =  $ok && $this->PrepareSubTotalsValues($values);

        if(!isset($values['SUBTOTALS'])) {
            // for document Subtotal & Total
            $this->CollectTotalValuesFromEntries($values);
        }

        //			if ( $this->_needDistributeSubtotals($values) ) {
        //				$this->DistributeSubTotals($values);
        //			}

        $ok = $ok && $this->ValidateSubTotals($values['SUBTOTALS']);

        //if ( $ok && $values['_DOCPAR']['SHOW_TOTALS'] == 'true' ) {
        //$ok = $ok && $this->CalculateDocTotal(&$values);
        //}

        // setup the proper entity field for 'so' or 'po' templates
        if ((isset($values[':entity'])) && ($mod!='inv')) {
            $values['VENDENTITY']     = $mod=='po' ? $values[':entity'] : '';
            $values['CUSTENTITY']     = $mod=='so' ? $values[':entity'] : '';
        }

        //create the header entry query replacement values
        $values[':sourcedocument']    = $values['SOURCEDOCUMENT']?? '';
        $values[':whenmodified']     = $values['WHENMODIFIED'];
        $values[':venddocno']         = $values['VENDORDOCNO'] ?? '';
        $values[':userkey']         = $values['USERKEY'] ?? '';
        $values[':vendentity']         = $values['VENDENTITY'] ?? '';
        $values[':custentity']         = $values['CUSTENTITY'] ?? '';
        $values[':message']         = $values['MESSAGE'] ?? '';
        $values[':warehousekey']     = $values['WAREHOUSE']['LOCATIONID']?:'';
        $values[':deptkey']         = $defaultdeptkey ?? '';
        $values[':locationkey']     = $defaultlockey ?? '';
        $values[':subtotal']         = $values['SUBTOTAL'] ?? 0.00;
        $values[':total']             = $values['TOTAL'] ?? 0.00;
        $values[':schopkey']         = $values['SCHOPKEY'] ?? '';

        //if ($ok) {
        //	$ok = $ok && $this->PrepLineItems($values);
        //}
        epp("E:$ok");

        //if($this->_ismcpEnabled){
        //	$values['TRX_SUBTOTAL'] = $values['SUBTOTAL'];
        //	$values['TRX_TOTAL'] = $values['TOTAL'];
        //	$values['SUBTOTAL'] = ibcmul($values['TRX_SUBTOTAL'], $values['EXCHRATE'], DEFAULT_INVPRECISION, true);
        //	$values['TOTAL'] = ibcmul($values['TRX_TOTAL'], $values['EXCHRATE'], DEFAULT_INVPRECISION, true);
        //}

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Error preparing values!";
            Globals::$g->gErr->addIAError('INV-0696', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }


    /**
     * Prepare doc header info for submitting to database.
     * This function is used to prepare multi currency values when a transaction is created from a recurring template.
     *
     * @param array  $values  recurring template values for creating docuemnt
     * @param array  $msg     message from the scheduler
     */
    function PrepareTransactionMCPValues(&$values, $msg)
    {
        //
        // if it is a foreign currency transaction
        if($values['CURRENCY'] != $values['BASECURR']) {

            if(isset($msg['AUTOPOSTUSEEXRATETYPE'])) {
                $values['EXCHRATETYPES']['NAME'] = $msg['AUTOPOSTUSEEXRATETYPE'];
            }

            $gManagerFactory = Globals::$g->gManagerFactory;
            $exchangeRateMgr = $gManagerFactory->getManager('exchangerate');
            //
            // the exchange rate should be of the transaction creation date
            $values['EXCHRATEDATE'] = $values['WHENCREATED'];
            //
            // calculate the exchange rate
            $values['EXCHRATE'] = $exchangeRateMgr->GetTrxExchangeRate(
                $values['EXCHRATETYPES']['NAME'],
                $values['CURRENCY'],
                $values['BASECURR'],
                $values['EXCHRATEDATE']
            );
        }else{
            //
            // Exchangerate should be 1 if the basecurrency and transaction currency is same
            unset($values['EXCHRATEDATE']);
            unset($values['EXCHRATETYPES']);
            $values['EXCHRATE'] = 1;
        }
    }

    /**
     * To process the docpar for recurring template
     *
     * @param array     &$docpar       docpar values
     * @param string    $source_dockey source document docpar key
     *
     * @return bool
     */
    private function ProcessDepartmentLocationfor_DocparSubtotals(&$docpar, $source_dockey)
    {
        $ismega = IsMultiEntityCompany();
        $contextLocation = GetContextLocation();

        // get the parent document subtotals
        global $gManagerFactory;
        /** @var DocumentSubTotalsManager $subtotalMgr */
        $subtotalMgr            = $gManagerFactory->getManager($this->mod . 'documentsubtotals');
        $source_subtot_values    = $subtotalMgr->GetByParent($source_dockey);

        if ($ismega && ( $contextLocation == '' || $this->IsOwnedEntity() == false ) ) {
            $copyDepartmentLocation = false;
        }else {
            if($docpar['LOCATIONKEY']=='') {
                $copyDepartmentLocation = true;
                global $acctmapno;
            }
        }

        $subtotval = 0;
        // copy the dept/location for the matching subtotals
        foreach((($source_subtot_values) ?? []) as $srcsubtotal){
            foreach($docpar['DOCPAR_SUBTOTAL'] as &$trgsubtotal){
                if($srcsubtotal['DESCRIPTION'] == $trgsubtotal['DESCRIPTION']) {
                    //
                    /** @noinspection PhpUndefinedVariableInspection */
                    if($copyDepartmentLocation) {
                        // copy Location values
                        if(isset($srcsubtotal['LOCATIONID']) && !empty($srcsubtotal['LOCATIONID'] ?? '')) {
                            $trgsubtotal['LOCATIONID'] = $srcsubtotal['LOCATIONID'];
                            $trgsubtotal['LOCATION'] = $srcsubtotal['LOCATION'];
                        }else {
                            //check is location required
                            /** @noinspection PhpUndefinedVariableInspection */
                            if( $acctmapno[$trgsubtotal['GLACCTID']]['REQUIRELOC'] == 'T' ) {
                                // default to the entity if for the rest of the subtotals which did not match with parent document
                                $locinfo = $this->LocMgr->DoQuery('QRY_LOCATION_SELECT_RAW_REC', array($contextLocation,GetMyCompany()));
                                if (isset($locinfo)) {
                                    $trgsubtotal['LOCATIONID']         = $locinfo[0]['LOCATION_NO'];
                                    $trgsubtotal['LOCATIONNAME']     = $locinfo[0]['NAME'];
                                    $trgsubtotal['LOCATION']         = $locinfo[0]['LOCATION_NO'].'--'.$locinfo[0]['NAME'];
                                }
                            }
                        }
                        // copy Department values
                        $trgsubtotal['DEPARTMENTID'] = $srcsubtotal['DEPARTMENTID'];
                        $trgsubtotal['DEPARTMENT'] = $srcsubtotal['DEPARTMENT'];
                    }

                    // copy subtotal value (ie Amount/Percent) only if the subtotal value type matches
                    if ($trgsubtotal['AMT_PERC'] == 'Amount' && $srcsubtotal['ABSEDIT']=='1') {
                        //In case of multi-entity at root, subtotal may be distributed so need to get summary
                        $subtotval = bcadd($subtotval, $srcsubtotal['ABSVAL']);
                        $trgsubtotal['VALUE']  = $subtotval;
                    } elseif($trgsubtotal['AMT_PERC'] == 'Percent' && $srcsubtotal['PERCENTEDIT' ]=='1') {
                        $trgsubtotal['VALUE'] = $srcsubtotal['PERCENTVAL'];
                    }
                    break;
                }
            }
        }
        unset($trgsubtotal);

        return true;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function CalculateDocTotal(&$values)
    {
        $ok = true;

        $doctotal = $values['TOTAL'] ?? 0.00;
        foreach( $values['SUBTOTALS'] as $val){
            $doctotal = bcadd($doctotal, $val['TOTAL'], 2);
        }

        $values['TOTAL'] = $doctotal;
        return $ok;
    }


    /**
     * Helper function for derived class recurxx functions
     * This function is invoked by child classes in response to the scheduler IMS adapter being executed.
     *
     * @param  array $msg    IMS package
     * @param  array $result Document structure ready for saving
     *
     * @return bool
     */
    function RecurDocument($msg, &$result)
    {
        global $gManagerFactory, $gNoUIWarn;

        $ok                     = true;

        // Setting gNoUIWarn true here converts warnings to errors.  I.e.,
        // if a duplicate document is detected, a warning is
        // displayed in the UI and the user has the ability to react.  This
        // user reaction is not possible in automated API invocations, so
        // warnings have to be converted to errors.
        $gNoUIWarn     = true;
        $schopKey = $msg['OPERATION']['SCHEDOPRECORD'];

        if ( isset($msg['RECURDOCUMENTDATA']) ) {

            $result = $msg['RECURDOCUMENTDATA'];

        } else {
            if (!isset($msg['OPERATION']['BODYDATA'])) {
                $message = "Did not receive operation message body, , resubmit the recurring transaction";
                Globals::$g->gErr->addIAError('INV-0824', __FILE__ . ':' . __LINE__, $message, []);
                return false;
            }

            //IMS sends pointer to recurdocument record#
            $r                         = $msg['OPERATION']['BODYDATA']['RECORD#'];

            // Get the RECURDOCUMENT object via EntityMgr
            $result = (array)$this->Get($r);
            $this->processDetailSubtotals($result);

            $schopKeyRecord = $result['SCHOPKEY'];
            // Check to see if the scheduled operation key of the prrecord matches this schedule
            if ( isset($schopKey) && isset($schopKeyRecord) && intval($schopKey) != intval($schopKeyRecord) ) {
                // The prrecord points to a different schedule, this is a rogue, disable it.
                SchedulerService::handleRogueSchedule($schopKey, GetMyCompany(), __CLASS__.'::'.__METHOD__);
                return false;
            }
        }

        // also fetch the paltform relationship FKs - these are needed so the code will propagate them
        // to the generated documents
        if ( ! util_isPlatformDisabled() ) {
            $this->getRelationships($result, true);
        }

        // if there is no result, the scheduled operation is pointing to a recurring tx that no longer exists.
        if (!array_key_exists('RECORDNO', $result)) {
            // Just in case this is a rogue schedule
            SchedulerService::handleRogueSchedule($schopKey, GetMyCompany(), __CLASS__.'::'.__METHOD__);
            return false;
        }

        if ($result['STATUS'] == 'inactive') {
            return true;            //Do not generate transaction if recurring document is inactive
        }

        //Fill up record for create document
        //Get when created past date for document
        $result['WHENCREATED']     = $msg['STARTDATE'] ?? GetCurrentDate();

        //Always Get the latest Bill To and Ship To addresses
        $result['GETLATESTBILLTO'] = 'true';
        $result['GETLATESTSHIPTO'] = 'true';

        //if first recurring transaction then post the amount = amount + roundoff amt
        //----------------starts here -------------------
        if (isset($result['STARTDATE']) && $result['STARTDATE'] !== ''
            && isset($result['REPEATCOUNT']) && $result['REPEATCOUNT'] !== ''
        ) {
            $startdate = $result['STARTDATE'];
            $repeatcount = $result['REPEATCOUNT'];
        } else {
            $cny = GetMyCompany();
            $recurMgr = $gManagerFactory->getManager('recurdocument');
            $qry = 'QRY_RECURDOCUMENT_GET_SCHEDULE_STARTDATE';
            $res = $recurMgr->DoQuery($qry, array($cny , $cny, $msg['SCHEDOPRECORD']));
            $res = $res[0];
            $startdate = $res['STARTDATE'];
            $repeatcount = $res['REPEATCOUNT'];
        }

        if(SysDateCompare($result['WHENCREATED'], $startdate)==0) {
            $this->mod = $this->getMyInstanceMod();
            $itemMgr = $gManagerFactory->getManager('item');
            foreach($result['ENTRIES'] as $key => $val){
                if(isset($result['ENTRIES'][$key]['ROUNDAMT'])) {
                    list($itemid)  = explode('--', $val['ITEMID']);
                    $row = $itemMgr->GetRaw($itemid);
                    $item = $row[0];

                    $values['ENTRIES'][$key]['PRECISION'] = $itemMgr->_lookUpItemPrecision($item, $this->mod);
                    $precision = $values['ENTRIES'][$key]['PRECISION'];

                    $result['ENTRIES'][$key]['UIVALUE'] =  iround(ibcadd($result['ENTRIES'][$key]['UIVALUE'], ibcdiv($result['ENTRIES'][$key]['ROUNDAMT'], $repeatcount), 10), $precision);
                    $result['ENTRIES'][$key]['UIPRICE'] =  iround(ibcdiv($result['ENTRIES'][$key]['UIVALUE'], $result['ENTRIES'][$key]['UIQTY'], 10), $precision);
                }
            }
        }
        //---------ends here-----------------------------

        //Get the due date from start date which is passed by the scheduler (not same as run date)
        $termarr                 = array();
        GetTerm($result['TERMKEY'], $termarr);
        $duedate                 = CalcDueDate($result['WHENCREATED'], $termarr['VALUE']);

        $result['WHENDUE']     = $duedate;

        //Perform cleanup on key fields....
        unset($result['RECORDNO']);
        // Cleanup ENTRIES structure
        foreach($result[$this->_li_entity] as $key => $line) {
            if (!isset($line) || !isset($line['ITEMID'])) {
                continue;
            }

            // kill the RECORDNO field so that a new value will be assigned
            // in EntityManager.
            if (!empty($result[$this->_li_entity][$key]['RECORDNO'] ?? '')) {
                unset($result[$this->_li_entity][$key]['RECORDNO']);
            }
            if (!empty($result[$this->_li_entity][$key]['DOCHDRNO'] ?? '')) {
                unset($result[$this->_li_entity][$key]['DOCHDRNO']);
            }
        }

        // Cleanup Subtotals structure
        foreach($result['SUBTOTALS'] as $key => $line) {
            if (!isset($line)) {
                continue;
            }

            // kill the RECORDNO field so that a new value will be assigned
            // in EntityManager.
            if (!empty($result['SUBTOTALS'][$key]['RECORDNO'] ?? '')) {
                unset($result['SUBTOTALS'][$key]['RECORDNO']);
            }
            if (!empty($result['SUBTOTALS'][$key]['DOCHDRNO'] ?? '')) {
                unset($result['SUBTOTALS'][$key]['DOCHDRNO']);
            }
            // epp(__FILE__.':'.__LINE__.' ... '."RecurDocument"); epp($key); eppp($result['SUBTOTALS'][$key]); //??remove bharris
        }

        if($this->_ismcpEnabled) {
            $this->validateMCPValues($result);
        }

        //mark this as system generated.
        $result['SYSTEMGENERATED'] = 'true';

        return $ok;
    }



    /**
     * @param array $result
     */
    private function processDetailSubtotals(&$result)
    {
        $mod = $this->getMyInstanceMod();
        $subTotObj = GetSubTotalsHelper($mod);

        $needDetailSubtotals = $subTotObj->_copyDimensionsFromLineitem || $subTotObj->_overrideDimensionsFromSubtotals;
        if (!$needDetailSubtotals) {
            return;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;
        $docSubTotalsMgr = $gManagerFactory->getManager($mod . 'recursubtotals');
        $detailSubtotals = $docSubTotalsMgr->getByParent($result['RECORDNO']);
        if (!$detailSubtotals) {
            return;
        }

        $result['SUBTOTALS'] = $detailSubtotals;
        foreach ($result['SUBTOTALS'] as & $subtotal) {
            $this->BuildDeptLocation($subtotal);
            $subtotal['RECURDOCHDRKEY'] = $result['RECORDNO'];
        }
        unset($subtotal);
    }

    /**
     * To pass _validatenew in EntityManager for custom field of type checkboxes.
     *
     * @param  array $result
     *
     * @return bool
     */
    function ConvertCustomFieldCheckBoxValue(&$result)
    {
        $mod = $this->getMyInstanceMod();

        $templateDocid = $result['DOCID'];
        $cny = GetMyCompany();
        $qry = "select customfieldid 
                from customfield 
                where cny# = :1 
                  and type = :2 
                  and ownerobject = :3 
                  and '#~#'||doctype||'#~#' like '%#~#'||:4||'#~#%' 
                  and active='T'";
        $soDocCustField = QueryResult(array($qry, $cny, 'CHECKBOX', $mod.'document', $templateDocid));

        if(count($soDocCustField) > 0) {
            foreach($soDocCustField as $custval){
                foreach($result as $key => $val){
                    if($custval['CUSTOMFIELDID'] == $key) {
                        // for backward compatibility -- I'm not sure if this is still needed
                        $result[$key] = ($val == 'T' || $val == 'true') ? 'true' : 'false';
                    }
                }
            }
        }

        $soDocEntryCustField = QueryResult(array($qry, $cny, 'CHECKBOX', $mod.'documententry', $templateDocid));
        if(count($soDocEntryCustField) > 0) {
            foreach($soDocEntryCustField as $cusentrytval){
                foreach($result['ENTRIES'] as $entrykey => $entryval){
                    foreach($entryval as $key => $val){
                        if($cusentrytval['CUSTOMFIELDID'] == $key) {
                            // for backward compatibility -- I'm not sure if this is still needed
                            $result['ENTRIES'][$entrykey][$key] = ($val == 'T' || $val == 'true') ? 'true' : 'false';
                        }
                    }
                }
            }
        }

        return true;
    }

    /**
     * @param array $result
     */
    function validateMCPValues(&$result)
    {
        global $gManagerFactory;
        $basecurr = ($result['BASECURR'] ?: GetBaseCurrency());

        $result['EXCH_RATE_DATE'] = $result['WHENCREATED'];

        $exchRateMgr = $gManagerFactory->getManager('exchangerate');

        if ($result['CURRENCY'] == $basecurr) {
            $exchrate = 1;
        } elseif($result['EXCH_RATE_TYPE_ID'] == -1) {
            $exchrate = $exchRateMgr->GetIntacctExchangeRate($result['CURRENCY'], $basecurr, $result['WHENCREATED']);
        } else {
             $exchrate = $exchRateMgr->GetTrxExchangeRateByTypeID($result['EXCH_RATE_TYPE_ID'], $result['CURRENCY'], $basecurr, $result['WHENCREATED']);
        }

        $result['EXCHANGE_RATE'] = $exchrate;
    }


    /**
     * Insure that any Add or Set operation has Line Item and Subtotal
     * items that do not contain the field RECORDNO.
     *
     * @param  array $values
     *
     * @return bool
     */
    function RemoveRecordNo(&$values)
    {
        // we need to remove any pre-existing RECORDNO values in the line
        // items and subtotals array.
        //------Clean up ENTRIES by removing existing RECORDNO fields
        foreach( $values['ENTRIES'] as $key => $line) {
            // kill the RECORDNO field so that a new value will be assigned
            // in EntityManager.
            if ($values['ENTRIES'][$key]['RECORDNO']) {
                unset($values['ENTRIES'][$key]['RECORDNO']);
            }
        }

        //------Clean up SUBTOTALS by removing existing RECORDNO fields
        foreach( ($values['SUBTOTALS'] ?? []) as $key => $line) {
            // kill the RECORDNO field so that a new value will be assigned
            // in EntityManager.
            if ($values['SUBTOTALS'][$key]['RECORDNO']) {
                unset($values['SUBTOTALS'][$key]['RECORDNO']);
            }
        }
        return true;
    }



    /**
     * This function is called by the ims scheduler process in the event an email messages
     * has to be sent out. This method should retrieve, format and return data expected
     * to be appended in the email message text.
     *
     * @param   int     $entityKey
     * @param   array   $info
     *
     * @return bool
     */
    function ScheduledEntityEmailDetails($entityKey, &$info)
    {

        //retrieve required records... using Get() because of the
        // need for associated object level details that are required.
        /** @var array $obj */
        $obj = $this->Get($entityKey);
        if (!$obj) {
            return false;
        }

        //Construct the document details for this transaction
        $info['msg'] = $this->FormatEmailDocumentDetails($obj);

        return true;
    }



    /**
     * Called in conjunction with IMS processing in the envent that a new document
     * generated errors during creation.
     *
     * Send error notification to designated recipient in the event the scheduled
     * recurring transaction fails to get created. This method will only send errors
     * designated with 'BL' in the error number and there must be an email address
     * value configured with the scheduler for the message to be created and sent.
     *
     * @param  array $values
     *
     * @return bool
     */
    function SendErrorNotification($values)
    {

        $cnt = 0;
        $errlines = '';
        $errary = array();
        //Get Email token object
        $this->emailToken = I18NEmailToken::buildFromResource('IA.EMAIL.INVENTORY.SCHEDULED_RECUR_DOC_CREATION_ERROR_NOTIFICATION');

        //Construct the list of error messages in this transaciton for email.
        $emailBodyErrorList = "";
        Globals::$g->gErr->GetErrList($errary);
        if (count($errary) > 0) {
            foreach ($errary as $item) {
                //report only business/process layer errors...
                if ((isl_stristr($item['NUMBER'], 'BL')) || (isl_stristr($item['NUMBER'], 'PL'))) {
                    $cnt++;
                    //Building error lines
                    $errlines .= $this->emailToken->applyPlaceholders(
                        'body.errorList',
                        [
                            'ERR_NUMBER' => $item['NUMBER'],
                            'CDESCRIPTION'     => $item['CDESCRIPTION']
                        ]
                    );
                }
            }
            if ($cnt > 0) {
                //Build Error header message and concatenate with Error list that are found above.
                $emailBodyErrorList = $this->emailToken->applyPlaceholders(
                    'body.errorListHeaderMsg',
                    []
                );
                $emailBodyErrorList .= $errlines;
            }
        }

//         if business/process layer errors were not generated, do not send email.
        if ($cnt <= 0) {
            return true;
        }

        // if the email address is not set, do nothing
        $emailAddress = $values['SCHEDULEDCONTACTEMAIL'];
        if (!isset($emailAddress) || ($emailAddress == '')) {
            return true;
        }

        // Build the email initial text body from body.text
        $emailBodyText = $this->emailToken->applyPlaceholders(
            'body.text',
            [
                'DOCID' => $values['DOCID'],
                'IADATE_USRFORMAT'     => GetCurrentDate(IADATE_USRFORMAT)
            ]
        );

        //Build the Document details for the email body, based on the subclass the document details will be formed,
        //possible doc detail formats are defaultDocDetails or oepoDocDetails or invDocDetails.
        $emailBodyDocDetails = $this->FormatEmailDocumentDetails($values);

        //Build message end part that closing message and signature.
        $emailBodyMsgEnd = $this->emailToken->applyPlaceholders(
            'body.msgEnd',
            [
            ]
        );

        // Construct the final body message
        $msg = $emailBodyText
            .$emailBodyDocDetails
            .$emailBodyErrorList
            . $emailBodyMsgEnd;

        // Build the subject
        $subject = $this->emailToken->applyPlaceholders(
            'subject.text',
            [
                'DOCID' => $values['DOCID']
            ]
        );

        $emailobj = I18NEmail::constructFromToken($this->emailToken, $emailAddress); // for diagnostics
        $emailobj->setFrom( FROMCONST);
        $emailobj->setSubject($subject);
        $emailobj->setBody($msg);
        $res = $emailobj->send();
        if ($res) {
            return true;
        }
        else {
            return false;
        }
    }



    /**
     * Process an update action on this object
     *
     * @param  array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {

        global $gManagerFactory;

        $source                 = "RecurDocumentManager::Set";
        $userid                 = GetMyUserid(1);
        $curdate                 = GetCurrentDate();

        //if parent is Sales Contract, only update the status field
        $ok = $this->_QM->beginTrx($source);

        //Start all validations
        //$ok 					= $this->_QM->beginTrx($source);
        $ok                     = $ok && $this->ValidateObj($values);
        $ok                     = $ok && $this->Translate($values);

        $values['RECORDNO']     = Request::$r->_r;
        $values['USERKEY']         = $userid;
        $values['MODULEKEY']     = $this->_modid;
        $values['WHENMODIFIED'] = $curdate;

        //Get the current record and update changed values
        $ok                     = $ok && $RecurDocumentVal = $this->GetRaw($values['RECORDNO']);
        /** @noinspection PhpUndefinedVariableInspection */
        $values['SCHOPKEY']     = $RecurDocumentVal[0]['SCHOPKEY'];    //This value is not passed from the screen
        $Newvalues =$values;
        //execute updates to the scheduled objects...
        $docMgr = $gManagerFactory->getManager('document');
        $ok                     = $ok && $this->SetScheduledEntries($Newvalues);
        $ok                     = $ok && $docMgr->validateRecurDocForPCB($this->mod, $Newvalues['_DOCPAR']);
        $ok                     = $ok && $this->PrepValues($Newvalues, null);
        $ok                     = $ok && $this->RemoveRecordNo($Newvalues);
        $ok                     = $ok && $this->UpdateParentConvertStatus($Newvalues, 'UPDATE');

        $Newvalues['SUPDOCENTITY'] = $this->_schemas[$this->_entity]['supdocentity'];
        //SUPDOCENTITY comes from translate
        if ($Newvalues['SUPDOCENTITY'] != '' && $ok) {
            //Update the supporting document - prrecord map for this recurring prrecord
            if (!SetSupportingDocumentMap($Newvalues['RECORDNO'], $Newvalues['SUPDOCID'], '', $Newvalues['SUPDOCENTITY']) ) {
                $msg = "Could not update the document attachment mapping. Please check the values";
                Globals::$g->gErr->addIAError('INV-0825', __FILE__ . ':' . __LINE__, $msg, []);
            }
        }

        $ok = $ok && $this->entityManagerSet($Newvalues);

        // If there is no errors in the template we will simulate the OE transaction creation and see if
        // it get created properly. If it does not we will notify the user about the issues.
        //$ok = $ok && $this->simulateExecution($Newvalues);

        $warnOnDups = Request::$r->_kNoWarn;

        // Cache the values for auditing to avoid an extra read later.
        if ($ok) {
            $auditTrailSession = AuditTrailSession::getInstance();
            $auditTrailSession->cacheAuditRecord($this->getAuditEntity(), $this->GetKeyValue($Newvalues), $Newvalues);
        }

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok ) {
            if (HasErrors()) {
                if ($warnOnDups != 'true') {
                    $msg =  "Could not Set Document record!" ;
                    Globals::$g->gErr->addIAError( 'INV-0697', __FILE__ . ':' . __LINE__, $msg, [] );
                }
            }
            $this->_QM->rollbackTrx( $source );

            //To avoid creating IMS job in shutdown function
            if ($gManagerFactory->ManagerExists( 'schedule' )) {
                $gManagerFactory->DeleteManager( 'schedule' );
            }
        }

        return $ok;
    }



    /**
     * Updates scheduled operation entry associatedto current Recurring Transaction Template
     *
     * @param  array $values
     *
     * @return bool
     */
    function SetScheduledEntries($values)
    {
        global $gManagerFactory;
        $schedMgr = $gManagerFactory->getManager('schedule');
        $ok = true;
        $cny = GetMyCompany();
        $userid = GetMyLogin(1);

        // Can not use EM for scheduled operation since it searches by name,
        //	hence custom query, and we have only schopkey
        // Even inactive schedules are selected, since user can activate them
        $queryItems = array(
        'QUERY' => 'SELECT * FROM scheduledoperation WHERE cny# = ? AND record# = ?',
        'ARGTYPES' => array('integer','integer')
        );

        /* @var array $SchedOpVal */
        $ok = $ok && $SchedOpVal = $this->_QM->DoCustomQuery($queryItems, array($cny, $values['SCHOPKEY']), true);
        /** @noinspection PhpUndefinedVariableInspection */
        $SchedOpVal                         = $SchedOpVal[0];
        $SchedOpVal['OPERATION']['NAME']     = $SchedOpVal['NAME'];     //All names are identical
        $SchedOpVal['SCHEDULE']['NAME']     = $SchedOpVal['NAME'];
        $SchedOpVal['DESCRIPTION']             = $this->_schedmeta['DESCRIPTION']
        . ' '
        . $values[$this->_schedmeta['ENTITYFIELD']];
        $SchedOpVal['USERNO']                 = $userid;
        $SchedOpVal['STATUS']                 = $values['STATUS'];
        $SchedOpVal[':operation#']             = $SchedOpVal['OPERATION#'];
        $ok = $ok && $this->SchedOperMgr->set($SchedOpVal);

        $SchedValues = $this->SetScheduleValues($values, false);  //we are doing updating

        if (!isset($SchedValues) || $SchedValues == '') {
            $ok = false;
        }

        $SchedValues['NAME']                 = $SchedOpVal['NAME'];        //Use same name as sched. operation
        $SchedValues['DESCRIPTION']         = $SchedOpVal['DESCRIPTION'];

        $ok = $ok && $schedMgr->set($SchedValues);

        $ok = $ok && $OperValues             = $this->OperMgr->GetRaw($SchedOpVal['NAME']);
        /** @noinspection PhpUndefinedVariableInspection */
        $OperValues                         = $OperValues[0];
        $OperValues['RECORDNO']             = $OperValues['RECORD#'];
        $OperValues['NAME']                 = $SchedOpVal['NAME'];
        $OperValues['DESCRIPTION']             = $SchedValues['DESCRIPTION'];
        $OperValues['USERNO']                 = $userid;
        $OperValues['ENTITY']                 = $this->_scheduleentity;    //This is topic used by IMS adapter
        $OperValues['ACTION']                 = 'RECUR';
        $OperValues['WHENCREATED']             = GetCurrentDate();
        $OperValues['STATUS']                 = $values['STATUS'];                    //Operation is activated
        $OperValues['MODULEKEY']             = $this->_modid;
        $OperValues['LOCATIONKEY']             = Profile::getProperty('LOCATIONKEY');
        $OperValues['CONTACTEMAIL']         = $values['SCHEDULEDCONTACTEMAIL' ];

        //$OperValues['RETRYLIMITCOUNT'] 	= $values['SCHEDULEDRETRYLIMITCOUNT' ];
        //$OperValues['ALLOWRETRY'] 		= $values['SCHEDULEDALLOWRETRY' ];

        $ok = $ok && $this->OperMgr->set($OperValues);

        return $ok;
    }


    /**
     * @param array $values
     * @param bool  $isCreate
     *
     * @access private
     *
     * @return array|bool
     */
    function SetScheduleValues($values, $isCreate)
    {
        $cny                             = GetMyCompany();
        $userid                         = GetMyLogin(1);
        $curdate                         = GetCurrentDate();

        //For generating unique name for operation, schedule, scheduledoperation
        srand((double)microtime()*10000000);
        list($msec, $sec)                 = explode(' ', microtime());
        $date                             = getdate($sec);
        extract($date);
        /** @noinspection PhpUndefinedVariableInspection */
        $timestamp                         = "$year.$mon.$mday $hours:$minutes:$seconds $msec";
        $timestamp                         = isl_substr($timestamp, 0, isl_strlen($timestamp)-4);

        //Fill up schedule table values
        $SchedValues['NAME']             = $this->_schedmeta['NAME'] . " - $timestamp";
        $SchedValues['CNY#']             = $cny;
        $SchedValues['USERNO']             = $userid;
        $SchedValues['WHENCREATED']     = $curdate;
        $SchedValues['DESCRIPTION']     = $this->_schedmeta['DESCRIPTION'] . ' ' . $values[$this->_schedmeta['ENTITYFIELD']];
        $SchedValues['STATUS']             = $values['STATUS'];
        $SchedValues['STARTDATE']         = $values['STARTDATE'];
        $SchedValues['REPEATBY']         = $values['REPEATBY'];

        if (!empty($values['ENDDATE'] ?? '')) {
            $SchedValues['ENDDATE']     = $values['ENDDATE'];
        }

        if($isCreate) {
            $values['EXECCOUNT'] = 0;
            $SchedValues['EXECCOUNT'] = 0;
            $SchedValues['LASTEXECDATE']     = '';
            $SchedValues[':nextexecdate']     = $SchedValues['STARTDATE'];    //Next execution starts from start date
        }
        else
        {
            $values['EXECCOUNT'] = $values['EXECCOUNT'] ?? 0;
            $SchedValues['EXECCOUNT'] = $values['EXECCOUNT'];
            $SchedValues['LASTEXECDATE'] = $values['LASTEXECDATE'];         //keep the old value

            //if we haven't started yet, then the user can change the start date, so we need to recalculate the NED
            if($values['EXECCOUNT'] == 0) {
                $values['NEXTEXECDATE'] = $SchedValues['STARTDATE'];
            }

            $SchedValues[':nextexecdate']     = $values['NEXTEXECDATE'];

            //if we've already started execution, then we need to do the following validation.
            if($values['EXECCOUNT'] > 0) {
                if(DateCompare($values['LASTEXECDATE'], $values['NEXTEXECDATE']) >= 0) {
                    $formatDate = FormatDateForDisplay($values['LASTEXECDATE']);
                    $msg = "Next execution date must be later than the last execution date " .$formatDate ;
                    Globals::$g->gErr->addIAError('INV-0826', __FILE__ . ':' . __LINE__, $msg, ['FORMAT_DATE' => $formatDate]);
                    return false;
                }
            }

            if(isl_strtolower($values['ENDING']) == isl_strtolower('End date') && DateCompare($values['NEXTEXECDATE'], $values['ENDDATE']) > 0) {
                $msg = "End date must be later than the next execution date";
                Globals::$g->gErr->addIAError('INV-0827', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }
        }

        if (isset($values['REPEATCOUNT']) && $values['REPEATCOUNT'] != '') {    //No of occurrences
            $SchedValues['REPEATCOUNT'] = $values['REPEATCOUNT'] + $values['EXECCOUNT'];

            if (is_numeric($values['REPEATCOUNT']) && +$values['REPEATCOUNT'] == 0) {                //Done so that for zero occurrences, no invoices will be created
                $SchedValues['STATUS']     = 'inactive';
            }
        }
        else {
            $SchedValues['REPEATCOUNT'] = '';    //Clear repeat count
        }

        if (is_numeric($values['INTERVAL'])) {
            $SchedValues['REPEATINTERVAL'] = $values['INTERVAL'];        //Repeat interval for frequency
        }
        else {
            $SchedValues['REPEATINTERVAL'] = '1';        //Default interval is 1 unit
        }

        $SchedValues['REPEATINTERVAL'] = '';

        if (isset($values['REPEATBY'])) {
            switch (isl_substr($values['REPEATBY'], 0, 1)) {
            case SCHEDULE_REPEAT_NONE :
                $SchedValues['REPEATBY'] = 'None';
                $SchedValues['REPEATCOUNT'] = 1;        //None is repeat once
                break;
            case SCHEDULE_REPEAT_DAY :
                $SchedValues['REPEATBY'] = 'Day';
                $SchedValues['REPEATINTERVAL'] = $values['INTERVAL'];  //Daily interval
                break;
            case SCHEDULE_REPEAT_WEEK :
                $SchedValues['REPEATBY'] = 'Week';
                $SchedValues['REPEATINTERVAL'] = $values['INTERVAL'];
                break;
            case SCHEDULE_REPEAT_MONTH :
                $SchedValues['REPEATBY'] = 'Month';
                $SchedValues['REPEATINTERVAL'] = $values['INTERVAL'];
                break;
            case SCHEDULE_REPEAT_ENDOFMONTH :
                $SchedValues['REPEATBY'] = 'EndOfMonth';
                $SchedValues['REPEATINTERVAL'] = $values['INTERVAL'];
                break;
            case SCHEDULE_REPEAT_YEAR :
                $SchedValues['REPEATBY'] = 'Year';
                $SchedValues['REPEATINTERVAL'] = $values['INTERVAL'];
                break;
            default :
                $SchedValues['REPEATBY'] = 'None';
                $SchedValues['REPEATCOUNT'] = 1;

            }

        }

        //For end of month
        if($isCreate) {
            $date_arr = explode('/', $SchedValues['STARTDATE']);
            $month = $date_arr[0];
            $year  = $date_arr[2];
            if ($SchedValues['REPEATBY'] == 'EndOfMonth' && $SchedValues['EXECCOUNT']==0) {
                $SchedValues[':nextexecdate'] = $month.'/'.cal_days_in_month(CAL_GREGORIAN, $month, $year).'/'.$year;
                $SchedValues['STARTDATE'] = $SchedValues[':nextexecdate'];  //For EOM, execution will start from end of start date's month
            }
        }
        else
        {
            //calculate the next execution date for EOM
            if ($SchedValues['REPEATBY'] == 'EndOfMonth') {
                $date_arr = explode('/', $values['NEXTEXECDATE']);
                $month = $date_arr[0];
                $year  = $date_arr[2];
                $SchedValues[':nextexecdate'] = $month.'/'.cal_days_in_month(CAL_GREGORIAN, $month, $year).'/'.$year;
            }
        }

        $SchedValues['EXECTYPE'] = 'Automatic';        //Scheduled to run by daily script
        if (SysDateCompare($values['STARTDATE'], $this->_execTime) <= 0) {
            //When start date is in past, scheduler runs in nonblocking mode immediately, hence mode is immediate
            $SchedValues['EXECTYPE'] = 'Immediate';
        }

        //adjustment based on DOCSTATUS
        if(($values['DOCSTATUS'] ?? '') == 'Ended') {
            $SchedValues[':nextexecdate'] = '';   //this will effecitively ended the schedule. Scheduled job will not be picked up.
        }
        else if(($values['DOCSTATUS'] ?? '') == 'Inactive') {
            $SchedValues['STATUS'] = 'inactive';  //this will make sure we can still edit it but scheduled job will not be picked up.
        }

        $duedate = $this->CalculateDueDate($SchedValues, $values, $cny);
        $SchedValues['DUEDATE'] = $duedate;
        return $SchedValues;
    }


    /**
     * @param array  $SchedValues
     * @param array  $values
     * @param string $cny
     *
     * @return array
     */
    function CalculateDueDate($SchedValues,$values,$cny)
    {
        global $gManagerFactory;

        $termMgr = $gManagerFactory->getManager('term');
        $terms = $termMgr->GetRaw($values['TERM']['NAME']);

        $queryItems                = array(
        'QUERY'     => "select APAR_UTILS.CalcDueDateFromTerm(to_date(?,'MM/DD/YY'), ?) duedate from company where record#= ?",
        'ARGTYPES'     => array('date','integer','integer')
        );

        $result = $this->_QM->DoCustomQuery(
            $queryItems,
            array($SchedValues[':nextexecdate'],$terms[0]['VALUE'], $cny),
            true
        );

        return $result[0]['DUEDATE'];
    }


    /**
     * This function will show subtotals and append SUBTOTAL
     * item at the beginning and TOTAL item at the end.
     *
     * @param  array $obj
     *
     * @return bool
     */
    function showSubTotals(&$obj)
    {
        global $gManagerFactory;

        $ok = true;

        $Subtotals = $obj['SUBTOTALS'];
        unset($obj['SUBTOTALS']);
        $ismega = IsMultiEntityCompany();
        $i=0;

        foreach( $obj['ENTRIES'] as $entry){
            if($this->_ismcpEnabled) {
                /** @noinspection PhpUndefinedVariableInspection */
                $tottrxval = ibcadd($tottrxval, $entry['TRX_VALUE'], DEFAULT_INVPRECISION, true);
            }
            /** @noinspection PhpUndefinedVariableInspection */
            $totalval =  ibcadd($totalval, $entry['UIVALUE'], DEFAULT_INVPRECISION, true);
        }
        $obj['SUBTOTALS'][$i]['DESCRIPTION'] = 'SUBTOTAL';
        $obj['SUBTOTALS'][$i]['STATUS'] = 'ACTIVE';
        /** @noinspection PhpUndefinedVariableInspection */
        $obj['SUBTOTALS'][$i]['TOTAL'] = $totalval;
        /** @noinspection PhpUndefinedVariableInspection */
        $obj['SUBTOTALS'][$i]['TRX_TOTAL'] = $tottrxval;

        // the summarized subtotals will be shown for Root level and not owned documents only
        // ideally this should be a document preference
        $contextLocation = GetContextLocation();
        if ($ismega && ( $contextLocation == '' || $this->IsOwnedEntity() == false ) ) {
            //Get subtotals
            $subTotalMgr     = $gManagerFactory->getManager('recursubtotals');
            $dochdrno         = $obj['RECORDNO'];
            $qry             = 'QRY_SUBTOTALS_BY_RECURDOCHDRNO_DESC';
            $args             = array ($dochdrno,$this->_cny);
            $taxData         = $subTotalMgr->DoQuery($qry, $args);
            $taxDataCnt     = count($taxData);
            $subtottrxval = 0;
            for($j=0; $j<$taxDataCnt; $j++){
                $obj['SUBTOTALS'][$j+1] = $taxData[$j];
                /** @noinspection PhpUndefinedVariableInspection */
                $subtotval = bcadd($subtotval, $taxData[$j]['TOTAL']);
                $subtottrxval = bcadd($subtottrxval, $taxData[$j]['TRX_TOTAL']);
            }
        }
        else{
            $subtottrxval = 0;
            $subtotval = 0;
            for($j=0; $j<count($Subtotals); $j++){
                $this->BuildDeptLocation($Subtotals[$j]);
                $obj['SUBTOTALS'][$j+1] = $Subtotals[$j];
                $subtotval = bcadd($subtotval, $Subtotals[$j]['TOTAL']);
                $subtottrxval = bcadd($subtottrxval, $Subtotals[$j]['TRX_TOTAL']);
            }
        }

        $obj['SUBTOTALS'][$j+1]['DESCRIPTION']     = 'TOTAL';
        $obj['SUBTOTALS'][$j+1]['STATUS']         = 'ACTIVE';
        //$obj['SUBTOTALS'][$j+1]['TOTAL'] 		= $obj['TOTAL'];
        /** @noinspection PhpUndefinedVariableInspection */
        $obj['SUBTOTALS'][$j + 1]['TOTAL'] = $subtotval + $totalval; //$obj['TOTAL'];
        $obj['SUBTOTALS'][$j+1]['TRX_TOTAL'] = $subtottrxval+$tottrxval;

        return $ok;
    }



    /**
     * Convert user visible keys to system keys.
     * Conversions are stored in values argument
     *
     * This was derived from ARAP Recur classes
     *
     * @param  array $values Structure containing RECURDOCUMENT values.
     *
     * @return bool
     */
    function Translate(&$values)
    {
        $ok = true;

        //Validate & Get the termkey
        if (isset($values['TERMNAME']) && $values['TERMNAME'] != '') {
            $ok = $ok && $terms = $this->TermMgr->GetRaw($values['TERMNAME']);
            if(!$ok) {
                Globals::$g->gErr->addIAError('INV-0223', __FILE__ . ':' . __LINE__, "The Term Name field is not valid, correct the term name", []);
            }else{
                /** @noinspection PhpUndefinedVariableInspection */
                $values['TERMKEY'] = $terms[0]['RECORD#'];
            }
        }

        //Get term keys
        if ((!isset($values['TERMKEY']) || $values['TERMKEY'] == '')
            && (isset($values['TERMNAME']) && $values['TERMNAME'] != '')
        ) {

            $ok = $ok && $terms = $this->TermMgr->GetRaw($values['TERMNAME']);
            /** @noinspection PhpUndefinedVariableInspection */
            $values['TERMKEY'] = $terms[0]['RECORD#'];
        }
        return $ok;
    }



    /**
     * Translate the contact vids to systems keys.
     *
     * Structure is like this:
     * <code>aryContacts = array('CONTACTFIELDNAME' => ':contactfieldkey')</code>
     *
     * This was derived from ARAP Recur classes
     *
     * @param  array $aryContacts list of contactfields to translate.
     * @param  array $values      the RECURDOCUMENT structure
     *
     * @return bool
     */
    function _TranslateContacts($aryContacts, &$values)
    {
        $ok = true;

        $contactcache = array();

        foreach((($aryContacts) ?? []) as $contactfieldname => $contactfieldkey) {

            if (!isset($values[$contactfieldname]) && $values[$contactfieldname] == '') {
                continue;
            }

            if (in_array($values[$contactfieldname], array_keys($contactcache))) {
                $values[$contactfieldkey] = $contactcache[$values[$contactfieldname]];
                continue;
            }

            $contactobj = $this->contactMgr->GetRaw($values[$contactfieldname]);
            $values[$contactfieldkey] = $contactobj[0]['RECORD#'];
            $contactcache[$values[$contactfieldname]] = $contactobj[0]['RECORD#'];

            if (!$contactobj[0]['RECORD#']) {

                Globals::$g->gErr->addIAError(
                    'INV-0698',
                    __FILE__.'.'.__LINE__,
                    "The contact " . $values[$contactfieldname] . " is invalid.",
                    ['VALUES_SHIPTO_CONTACTNAME' => $values[$contactfieldname]]
                );
                $ok = false;
            }

        }

        return $ok;
    }



    /**
     * This method updates the created Operation entry with the record
     * number of the recurdocument entry.
     *
     * @param  array $values
     * @param  array $OperValues
     * 
     * @return bool
     */
    function UpdateOperationEntry(&$values, &$OperValues)
    {
        $ok = true;

        // Operation table BODYDATA column has pointer to
        // this recurring transaction template record
        $RecurDocumentKey = $this->GetKeyValue($values);
        $OperValues['BODYDATA'] = array('RECORD#' => $RecurDocumentKey);
        $ok = $ok && $this->OperMgr->set($OperValues);
        return $ok;
    }



    /**
     * Validate schedule settings and the line item's
     * dept & location within the entity object.
     *
     * This was derived from ARAP Recur classes.
     *
     * @param  array $obj
     *
     * @return bool
     */
    function ValidateObj($obj)
    {
        $ok = $this->ValidateSchedule($obj);

        $entry = $obj[$this->_li_entity];
        foreach ((($entry) ?? []) as $item) {
            $dept = explode('--', $item['DEPARTMENT']);
            if (isset($dept[0]) && $dept[0] != '') {
                $dept = $dept[0];
                $res = $this->DeptMgr->GetRaw($dept);
                $res = $res[0];
                if (!isset($res) || $res == '') {
                    Globals::$g->gErr->addIAError('INV-0828', __FILE__ . ":" . __LINE__, "Department $dept is invalid", ['DEPT' => $dept]);
                    $ok = false;
                }
            }
            $loc = explode('--', $item['LOCATION']);
            if (isset($loc[0]) && $loc[0] != '') {
                $loc = $loc[0];
                $res = $this->LocMgr->GetRaw($loc);
                $res = $res[0];
                if (!isset($res) || $res == '') {
                    Globals::$g->gErr->addIAError('INV-0829', __FILE__ . ":" . __LINE__, "Location $loc is invalid", ['LOC' => $loc]);
                    $ok = false;
                }
            }
        }
        return $ok;
    }



    /**
     * Validate the schedule requested for this recurring transaction template.
     *
     * @param  array $obj The entity object containing the schedule to validate.
     *
     * @return bool
     */
    function ValidateSchedule($obj)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        $noOfOccurences = $obj['ENDING'];
        $noOfOccurences = substr($noOfOccurences, 0, 21);

        if (isset($obj['SC_EXISTINGSCHED'])) {
            if (!isset($obj['STARTDATE']) || $obj['STARTDATE'] == '') {
                //Start date must be specified
                $gErr->addIAError('INV-0224', __FILE__ . ":" . __LINE__, 'Please specify a start date for the schedule.', []);
                $ok = false;
            } else {
                if (!ValidateInputDate($obj['STARTDATE'])) {
                    $gErr->addIAError('INV-0225', __FILE__ . ":" . __LINE__, 'Start date is invalid', []);
                    $ok = false;
                }
            }

            if (isset($obj['ENDDATE'])) {
                if (!ValidateInputDate($obj['ENDDATE'])) {
                    $gErr->addIAError('INV-0226', __FILE__ . ":" . __LINE__, 'End date is invalid', []);
                    $ok = false;
                }
                if (DateCompare($obj['STARTDATE'], $obj['ENDDATE']) > 0) {
                    //Start date can not be beyond end date
                    $gErr->addIAError('INV-0227', __FILE__ . ":" . __LINE__, 'Modify the dates', []);
                    $ok = false;
                }
                if (isset($obj['REPEATCOUNT'])) {
                    //If end date is specified, number of occurrences should not be specified
                    $gErr->addIAError('INV-0228', __FILE__ . ":" . __LINE__, 'Specify only end date or number of occurrences', []);
                    $ok = false;
                }
            }
        }


        // added is_numeric check to resolve PHP 8.1 issue 165246
        if (is_numeric($obj['REPEATCOUNT']) && +$obj['REPEATCOUNT'] < 0) {
            //Number of occurrences can not be negative
            $gErr->addIAError('INV-0229', __FILE__ . ":" . __LINE__, 'Specify whole number for number of occurrences', []);
            $ok = false;
        }

        if (is_numeric($obj['INTERVAL']) && +$obj['INTERVAL'] < 0) {
            //Repeat interval can not be negative
            $gErr->addIAError('INV-0230', __FILE__ . ":" . __LINE__, 'Specify positive repeat interval', []);
            $ok = false;
        }

        if (isl_strtolower($noOfOccurences) == isl_strtolower('Number of occurrences') && !empty($obj['ENDDATE'] ?? '')) {
            //If number of occurrences is selected, end date should not be specified
            $gErr->addIAError('INV-0231', __FILE__ . ":" . __LINE__, 'Specify only end date or number of occurrences', []);
            $ok = false;
        }

        if (isl_strtolower($obj['ENDING']) == isl_strtolower('End date') && empty($obj['ENDDATE'] ?? '')) {
            //If end date option is selected, end date should be specified
            $gErr->addIAError('INV-0232', __FILE__ . ":" . __LINE__, 'End date is required if end date option is selected', []);
            $ok = false;
        }
        if ($obj['REPEATBY'] == 'None') {
            if($obj['ENDING'] == 'Never'){
                //If repeat is once, ending on can not be never
                $gErr->addIAError('INV-0233', __FILE__ . ":" . __LINE__, 'If Ending On option is never, Repeat option should not be none', []);
                $ok = false;
            }
        } else if ($obj['ENDING'] == 'Number of occurrences' && $obj['REPEATCOUNT'] == '') {
            //If number of occurrences option is selected, occcurrences should be specified
            $gErr->addIAError('INV-0234', __FILE__ . ":" . __LINE__, 'Specify number of occurrences', []);
            $ok = false;
        }

        return $ok;

    }



    /**
     * Validates department and location SubTotal fields.
     *
     * This method is included to override parent method which
     * performs additional validation on GL related entries not
     * used in this entity.
     *
     * @param  array $subtotals
     *
     * @return bool
     */
    function ValidateSubTotals(&$subtotals)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $dict = Dictionary::getInstance();

        BuildPRMaps();
        global $deptmapno, $locmapno;

        foreach((($subtotals) ?? []) as $key => $line) {
            $description = $line['DESCRIPTION'];
            $dept = $line['DEPARTMENT'] ?? '';
            if ($dept != '') {
                $dept = explode('--', $line['DEPARTMENT']);
                $deptkey = $deptmapno[$dept[0]];
                $subtotals[$key][':deptkey'] = $deptkey;

                if (!$deptkey) {
                    Globals::$g->gErr->addIAError('INV-0830', __FILE__ . '.' . __LINE__, null,
                                                  [ 'DESCRIPTION' => $description, 'DEPT_0' => $dept[0] ], '(A)', []);
                    $ok = false;
                }
            }

            // defaulting for MEGA entity Context
            if (isset($line['LOCATION'])) {
                $lc = explode('--', $line['LOCATION']);
                if ($lc[0] == '') {
                    $line['LOCATION'] = ( ($line['LOCATION']=='--' || $line['LOCATION'] == '') && IsMultiEntityCompany() ? $this->_defaultMELocation : $line['LOCATION'] );
                    $subtotals[$key]['LOCATION'] = $line['LOCATION'];
                }

                if ( $line['LOCATION'] != '' || $line[':locationkey'] == '' ) {
                    $loc = explode('--', $line['LOCATION']);
                    $lockey = $locmapno[$loc[0]];
                    $subtotals[$key][':locationkey'] = $lockey;
                    if (!$lockey) {
                        Globals::$g->gErr->addIAError('INV-0907', __FILE__ . '.' . __LINE__, null,
                                                      [ 'DESCRIPTION' => $description, 'LOC_0' => $loc[0] ]);
                        $ok = false;
                    }
                }
            }
        }
        foreach( (($subtotals) ?? []) as $line) {
            $description = $line['DESCRIPTION'];
            $dept = $line['DEPARTMENT'] ?? '';
            if ($dept != '') {
                $dept = explode('--', $line['DEPARTMENT']);
                $deptkey = $deptmapno[$dept[0]];

                if (!$deptkey) {
                    $gErr->addIAError('INV-0831', __FILE__ . '.' . __LINE__, null,
                                      [ 'DESCRIPTION' => $description, 'DEPT_0' => $dept[0] ], '(B)', []);
                    $ok = false;
                }
            }
        }
        return $ok;
    }


    /**
     * @param string $status
     *
     * @return string
     */
    function GetStatusCode($status)
    {

        if($status == 'Active') {
            $statuscode = 'A';
        }
        if($status == 'Inactive') {
            $statuscode = 'I';
        }
        if($status == 'Ended') {
            $statuscode = 'E';
        }

        /** @noinspection PhpUndefinedVariableInspection */
        return $statuscode;
    }

    /**
     * For transactions that were created from a schedule, this function
     * finds the parent document's record#
     * @param string $docid ID for the child document
     *
     * @return string docid for the parent document, empty string for no parent found
     */
    function GetRecurParentRecordNo($docid)
    {
        $res = $this->DoQuery('QRY_RECURDOCUMENT_GET_RECURPARENT_ID', array($docid));
        if (is_array($res) && isset($res[0]) && array_key_exists('RECORD#', $res[0])) {
            return $res[0]['RECORD#'];
        } else {
            return '';
        }
    }

    /**
     * Get a list of filled out objects (with lines) OLD
     *
     * @param array $params, the list params
     *
     * @return array|bool the list
     */
    function GetListFull($params)
    {

        unset($params['selects']);
        $params['selects'][] = 'RECORDNO';

        $recurdocs = $this->GetList($params);

        $numDocs = count($recurdocs);

        // If there are no documents to process, return
        if (!$numDocs) {
            return false;
        }

        $result = array();

        for($i = 0; $i < $numDocs; $i++)
        {
            $result[] = $this->Get($recurdocs[$i]['RECORDNO']);
        }

        return $result;
    }

    /**
     * @param bool $forPlatform
     *
     * @return array|string
     */
    public function GetPrintAs( $forPlatform = false)
    {
        $name = parent::GetPrintAs();
        if ( $forPlatform && isset($this->_docType) && $this->_docType != '') {
            $name = 'Recurring ' . $name;
        }
        return $name;
    }

    /**
     * @param bool   $forPlatform
     *
     * @return string
     */
    public function GetPluralPrintAs($forPlatform = false)
    {
        $name = parent::GetPluralPrintAs();
        if ( $forPlatform && isset($this->_docType) && $this->_docType != '') {
            $name = 'Recurring ' . $name;
        }
        return $name;
    }

    /**
     * Setter for enableSimulation variable
     *
     * @param bool $value true if simulation is enabled else false;
     */
    public function SetEnableSimulation($value)
    {
        $this->enableSimulation = $value;
    }

    /**
     * @param EntityManager $mgr
     * @param array         &$values
     */
    protected static function cleanupDimensionFieldIDs($mgr, &$values)
    {
        $dimFields = $mgr->GetDimensionFields();
        foreach ((($dimFields) ?? []) as $dimField) {
            $path = $dimField['path'];
            if (isset($values[$path])) {
                $values[$path] = Util::getIDPart($values[$path]);
            }
        }
        $ownedObjects = $mgr->GetOwnedObjects();
        foreach ((($ownedObjects) ?? []) as $ownedObject) {
            $objPath = $ownedObject['path'];
            if (isset($values[$objPath]) && is_array($values[$objPath])) {
                $ownedObjMgr = $mgr->GetOwnedObjectManager($ownedObject['entity']);
                foreach ($values[$objPath] as &$ownedObj) {
                    self::cleanupDimensionFieldIDs($ownedObjMgr, $ownedObj);
                }
                unset($ownedObj);
            }
        }
    }


    /** @noinspection PhpUnusedPrivateMethodInspection
     * 
     * Simulate the Recuring document transaction creation
     *
     * @param array $values, the recurring template data
     *
     * @return bool  false if error else true
     */
    private function simulateExecution(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        $ok = true;
        return $ok;
/*
        // For now we will simulate only if the user is creating the template directly
        // from the recuring transaction UI
        if ( $this->enableSimulation !== true ) {
            return $ok;
        }

        // Build the parameters we need for the RecurDocument function
        $objectMsg = array(
            'RECURDOCUMENTDATA' => $values
        );

        $args = array(
            // The function and entity name are the same for all the sub transaction as of now
            'entityName' => $this->_entity,
            'functionName' => $this->_entity,
            'msg' => $objectMsg
        );

        // We will execute an ims process that will simulate the OE transaction creation.
        // From the result of this process execution we will know if we can create AS OF NOW a transaction
        // from this schedule successfully
        include_once 'ims_publish_1.cls';
        $ims_response = array();
        $publish = new ims_publish_1(IMS_MODE_BLOCKING, IMS_PROCESS_REMOTE, IMS_MODE_QUEUED);
        $assertTest = $publish->PublishMsg(
            'SIMULATE_RECURDOCUMENT',
            'INTACCT',
            'SIMULATE_RECURDOCUMENT',
            IMS_PRIORITY_DEFAULT,
            $args,
            [],
            $ims_response
        );
        assert($assertTest);

        // If we have any errors then the execution will be considered as a failure.
        if ( count($ims_response['errors']) ) {
            $ok = false;
        }

        return $ok;
*/
    }

     /**
     * Submit an action
      *
     * @param string $_verb, the action
     * @param array  $_object the object to process
     * @param bool   $multiselect
     *
     * @return bool
     */
    public function Submit($_verb, $_object, $multiselect = false)
    {

        switch ( $_verb ) {
            case 'updaterecur':
                $ok = $this->updateRecurStatus($_object['shopKey'], $_object['status'], $_object['r']);
                break;
            default:
                $ok = parent::Submit($_verb, $_object, $multiselect);
        }

        return $ok;
    }

    /**
     * Updates the status of the recurring transaction to either T/F based on the current status
     *
     * @param   int     $shopKey key field specifying the recurring transaction
     * @param   string  $status current status of the recurring transaction to be changed
     * @param   int   $recurDocRecordNo record number of the recur document.
     *
     * @return bool
     */
    function updateRecurStatus($shopKey, $status, $recurDocRecordNo)
    {
        $ok = true;
        $cny = GetMyCompany();
        $newStatus = $status == 'T' ? 'F' : 'T';
        $docStatus = $newStatus == 'T' ? 'A' : 'I';

        $updateQuery = "UPDATE recurdochdrmst SET status = :1, docstatus = :2 WHERE cny# = :3 and schopkey = :4";
        $args = array($updateQuery, $newStatus, $docStatus, $cny, $shopKey);

        $ok = $ok && ExecStmt($args);

        $updateQuery = "UPDATE scheduledoperation SET status = :1 WHERE cny# = :2 and record# = :3";
        $args = array($updateQuery, $newStatus, $cny, $shopKey);

        $ok = $ok && ExecStmt($args);

        $updateQuery = "UPDATE schedule SET status = :1 WHERE cny# = :2 and record# = (select schedule# from scheduledoperation where cny# = :2 and record# = :3)";
        $args = array($updateQuery, $newStatus, $cny, $shopKey);

        $ok = $ok && ExecStmt($args);

        $updateQuery = "UPDATE operation SET status = :1 WHERE cny# = :2 and record# = (select operation# from scheduledoperation where cny# = :2 and record# = :3)";
        $args = array($updateQuery, $newStatus, $cny, $shopKey);

        $ok = $ok && ExecStmt($args);

        if ($ok) {
            $ok = $ok
                && AuditTrailSession::getInstance()->addAuditEvent(
                    $this->getAuditEntity(), $recurDocRecordNo, AuditTrail::AUDITTRAIL_EVENT_UPDATE,
                    new AuditTrailPayload($this->getAuditEntity(), $recurDocRecordNo, ['STATUS' => $newStatus])
                );
        }

        return $ok;
    }

    /**
     * @return bool
     */
    public function hasNonEditableFields()
    {
        return true;
    }

    /**
     * @param array $values
     *
     * @return string[]
     */
    public function getNonEditableFields($values)
    {
        $nonEditableFields = array('DOCID');

        return array_values($nonEditableFields);
    }

    /**
     * If line is generated from contract usage or billing schedule
     *
     * @param   array   $values     Line attributes in DB
     *
     * @return  bool
     */
    public function recordHasNonEditableFields($values)
    {
        return true;
    }

    /**
     * @param string      $docID
     * @param bool        $throwError
     *
     * @return bool
     */
    public function canEdit($docID, $throwError = false)
    {
        $ok = false;
        $filter = array(
            'selects' => array('NEXTEXECDATE'),
            'filters' => array(
                array(
                    array('RECORDNO', '=', $docID)
                )
            )
        );
        $res = $this->GetList($filter);

        if(isset($res[0]['NEXTEXECDATE']) && $res[0]['NEXTEXECDATE'] != '') {
            $ok = true;
        }

        return $ok;
    }

    /**
     * Return a list of entities
     *
     * @param array  $params     a structure used to build the custom query
     * @param bool   $_crosscny  if true do not add the var.cny# = ... code
     * @param bool   $nocount
     *
     * @return array $newResult  - result of query
     */
    public function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        $resSet = parent::GetList($params, $_crosscny, $nocount);
        //Only specific to the XML 2.1 request changes for get and get_list, since the REPEATBY values are
        // 'None', 'Days', 'Weeks', 'Months', 'EndOfMonth', 'Years' we need to convert them to
        // 'N', 'D', 'W', 'M', 'E', 'Y'. So that there will not be any change in response
        // and integration  due to FormEditor enhancement.
        if( ($this->fromGateway || $this->_fromAPI) && !empty($resSet)) {
            foreach ($resSet as &$res){
                if( isset($res['REPEATBY']) && $res['REPEATBY'] != '' ) {
                    $res['REPEATBY'] = isl_substr($res['REPEATBY'], 0, 1);
                }

            }
        }
        return $resSet;
    }
}

