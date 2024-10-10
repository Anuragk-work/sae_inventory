<?
import('GroupReporter');
import('DateTemplates');
require_once 'Dictionary.cls';

/**
 * Class RecurReport
 */
class RecurReport extends GroupReporter
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct($params);
    }


    /**
     * @return bool
     */
    public function ValidateParams()
    {
        // override this function if you don't need all the checks for your report	
        $ok = parent::ValidateParams();

        return $ok;
    }

    /**
     * @return bool
     */
    public function ParamTweaks()
    {
        global $gErr;

        // Do the validations for all the common fields here 
        $params = $this->params;
        $p['PERIOD']            = $params['PERIOD'] ? isl_htmlspecialchars($params['PERIOD']) : VARCHAR2_MIN;
        /** @noinspection PhpUndefinedVariableInspection */
        $p['ASOFDATE']            = $params['ASOFDATE'] ? isl_trim(isl_htmlspecialchars($params['ASOFDATE'])) : date($gStandardDate);
        $p['STARTDATE']            = $params['STARTDATE'] ? FormatDateForStorage(isl_trim(isl_htmlspecialchars($params['STARTDATE']))) : '';
        $p['ENDDATE']            = $params['ENDDATE'] ? FormatDateForStorage(isl_trim(isl_htmlspecialchars($params['ENDDATE']))) : '';
        $p['BASEDON']            = $params['BASEDON'] ? isl_trim(isl_htmlspecialchars($params['BASEDON'])) : '';
        $p['ORIENTATION']        = $params['ORIENTATION'] ? isl_trim(isl_htmlspecialchars($params['ORIENTATION'])) : 'Portrait';    
        $p['SORTMODE']            = $params['SORTMODE'] ? isl_trim(isl_htmlspecialchars($params['SORTMODE'])) : 'Default';
        $p['LOCATION']            = $params['LOCATION'];
        $p['DEPARTMENT']        = $params['DEPARTMENT'];
        $p['FILTERTRANSACTIONS']= $params['FILTERTRANSACTIONS'];        
        
        //To validate Start date and end date
        if (!ValidateDate($p['STARTDATE'])) {            
            $gErr->addIAError('INV-0235', __FILE__ . ":" . __LINE__, "Invalid start date format.", []);
            include 'popuperror.phtml';
        }
        if (!ValidateDate($p['ENDDATE'])) {            
            $gErr->addIAError('INV-0236', __FILE__ . ":" . __LINE__, "Invalid end date format.", []);
            include 'popuperror.phtml';            
        }

        if (HasErrors()) { 
            if($gErr->ErrorCount) {
                return false;
            }
        }

        $p['ops']             = $params['ops'];  // pass these thru untweaked for now
        $p['mode']             = $params['mode']; // pass thru		
        $p['javascript']     = $params['javascript']; // pass thru	
        
        // remember our tweaked values
        $params['safe'] = $p;
        $this->params = $params;
        
        return true;
    }

    /**
     * @param string $id
     * @param string $asofdate
     */
    public function GetStartAndEndDates($id, $asofdate)
    {
        global $gManagerFactory;

        $periodMgr =  $gManagerFactory->getManager('reportingperiod');
        $period = $periodMgr->GetRaw($id);
        if (!count($period) || !isset($period[0])) {
            //ADD ERROR HERE
            epp("could not get raw reporting period");
        } else {
            GetReportingDateRange($period[0], $asofdate, $start, $end);
            $this->startdate  = $start;
            $this->enddate    = $end;
        }
    }

    /**
     * @return array
     */
    public function ReportHeader()
    {
        // this function handles setting up the basic report header

        $_op = Request::$r->_op;

        $_sess = Session::getKey();
        global $gElementMap;
        $dict = Dictionary::getInstance();
        $params = $this->params['safe'];

        // Update the Title of the Report to have Date Range
        if ($this->params['type']!=kShowExcel) {
            $this->title  = $this->title . " (" .
              FormatDateForDisplay($this->startdate) . " - " . FormatDateForDisplay($this-> enddate) . ")" ;
        }

        $lines['report']["0"]['title']    = $this->title;
        $lines['report']["0"]['title2']    = $this->title2;
        $lines['report']["0"]['titlecomment']    = $this->titlecomment;
        $lines['report']["0"]['reportdate']  = FormatDateForDisplay(GetCurrentDate(IADATE_USRFORMAT));
        $lines['report']["0"]['op']        = $_op;
        $lines['report']["0"]['sess']    = $_sess;
        $lines['report']["0"]['co']        = GetMyCompanyName();
        $lines['report']["0"]['orientation'] = $params['ORIENTATION'];
        $lines['report']["0"]['today']    = GetCurrentDate(IADATE_USRFORMAT);
        $lines['report']["0"]['location']    = ($params['LOCATION'])? $dict->GetRenamedText('Location: ') . $params['LOCATION'][0] : '';
        $lines['report']["0"]['department']    = ($params['DEPARTMENT'])? $dict->GetRenamedText('Department: ') . $params['DEPARTMENT'][0] : '';
        
        if ($params['ops']) {
            if (is_numeric($params['ops'][0])) {
                $the_ops = $params['ops'];
            } else {
                foreach ($params['ops'] as $op){
                    $the_ops[] = GetOperationId($op);
                }
            }
            /** @noinspection PhpUndefinedVariableInspection */
            $params['joinedops'] = \implode(',', $the_ops);
            $lines['report']["0"]['ops']    = $params['joinedops'];
        }

        $lines['report']['0']['ismegl'] = (IsMultiEntityCompany())? 'Y' : 'N';
        $lines['report']['0']['locationcontext'] = (GetContextLocation())?: '';
        $lines['report']['0']['companyid'] = GetMyCompany();        
        
        $lines['report']["0"]['reportdate']     = GetCurrentDate(IADATE_USRFORMAT);

        if(Profile::getUserCacheProperty('USERPREF', 'TIMEFORMAT') == 'HH24:MI:SS') {
            $lines['report']["0"]['reporttime']     = date("G:i T");
        } else {
            $lines['report']["0"]['reporttime']     = date("g:i A T");
        }
        
        //For Offline reports $_op will not work. So taking Op ID from params directly.
        $opForMod = GetOperationId($this->params['ops'][0]);
        $mod = $gElementMap[$opForMod]['module'] ; 

        $dict = Dictionary::getInstance();

        if ($mod == 'po') {
            $ent = 'vendor';
            $entity = 'Vendor';
            $entitytype = 'vendor';
            $tmplentity = 'porecurdocument';
            $entityLabel = $dict->GetRenamedText($entity);
        }
        else if ($mod == 'so') {
            $ent = 'customer';
            $entity = 'Customer';
            $entitytype = 'customer';
            $tmplentity = 'sorecurdocument';
            $entityLabel = $dict->GetRenamedText($entity);
        }
        else if ($mod == 'inv') {
            $ent = 'customer';
            $entity = '';
            $entitytype = 'customer';
            $tmplentity = 'invrecurdocument';
            $entityLabel = $dict->GetRenamedText($entity);
        }

        if( $this->params['type'] == kShowHTML || $this->params['type'] == kShowBackground ) {
            /** @noinspection PhpUndefinedVariableInspection */
            $entity_view_op        = GetOperationId("$mod/lists/$ent/view");
            /** @noinspection PhpUndefinedVariableInspection */
            $entitytype_view_op    = GetOperationId("$mod/lists/$entitytype/view");
            /** @noinspection PhpUndefinedVariableInspection */
            $tmpl_view_op    = GetOperationId("$mod/lists/$tmplentity/view");

            $op1 = IsOperationAllowed($entity_view_op) ? $entity_view_op : '';
            $op2 = IsOperationAllowed($entitytype_view_op) ? $entitytype_view_op : '';
            $op3 = IsOperationAllowed($tmpl_view_op) ? $tmpl_view_op : '';

            $lines['report']["0"]['drillops'] = "$op1,$op2,$op3";
            /** @noinspection PhpUndefinedVariableInspection */
            $lines['report']["0"]['entity']    = $entity;
        }
        if(IsMCMESubscribed()) {
            $this->DisplayBaseCurrHeader($lines);            
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $lines['report']["0"]['headings'] = array(
        array(
        'col1'    => $entityLabel,
        'col2'    => _('Reference#'),
        'col3'    => _('Contract ID'),
        'col4'    => _('Frequency'),
        'col5'    => _('Start date'),
        'col6'    => _('Amount'),
        'col7'    => _('Next date'),
        'col8'    => _('Term'),
        'col9'    => _('Due date'),
        'col10' => _('Doc count'),
        'col11' => _('Document type'),
        )
        );        
        return $lines;
    }

    /**
     * @param array $lines
     * @param array $morelines
     */
    public function ReportBody(&$lines, $morelines)
    {
        $lines['report']["0"]['ITEM']    = $morelines;
    }

    /**
     * @param array $lines
     * @param string[][]|false $total
     */
    public function ReportTotal(&$lines, $total)
    {
        $lines['report']["0"]['TOTAL']    = $total;
    }

    /**
     * @return array
     */
    public function calcFilters()
    {

        $params                    = $this->params['safe'];
        $asofdate                = $params['ASOFDATE'];
        $basedon                = $params['BASEDON'];

        // Process 'based on' start/due/next date,
        // for backward compatibility (memorized reports etc.), 
        // we still may need to allow whitelisted SQL column names for 'based on',
        // At least they dont show up on URL when running the report now,
        // Even if attempt to pass this over URL as XSS, its only whitelist values we allow now
        
        if ($basedon == 'Start Date' || $basedon == 'dochdr.STARTDATE') {
            $basedon = 'dochdr.STARTDATE';
        }
        else if ($basedon == 'Due Date' 
            || $basedon == 'decode(dochdr.NEXTEXECDATE, NULL,NULL,APAR_UTILS.CalcDueDateFromTerm(dochdr.NEXTEXECDATE, term.value) )'
        ) {
            $basedon = 'decode(dochdr.NEXTEXECDATE, NULL,NULL,APAR_UTILS.CalcDueDateFromTerm(dochdr.NEXTEXECDATE, term.value) )';
        }
        else if ($basedon == 'Next Date' || $basedon == 'dochdr.NEXTEXECDATE') {
            $basedon = 'dochdr.NEXTEXECDATE';
        }
        else {
            // If unsupported value found for 'based on', empty it,
            $basedon = '';
        }

        // Build reporting period filter
        if($params['STARTDATE'] == '' && $params['ENDDATE'] == '') { 
            $this->GetStartAndEndDates($params['PERIOD'], $asofdate);
        }
        else {
            $this->startdate        = $params['STARTDATE'];
            $this->enddate            = $params['ENDDATE'];
        }    

        $date_filter = '';
        if(isset($this->startdate) && $this->startdate != '' && $basedon != '') {            
            $date_filter .= " AND $basedon >= to_date('".$this->startdate." 00:00:00','mm/dd/yyyy hh24:mi:ss') ";
        }

        if(isset($this->enddate) && $this->enddate != '' && $basedon != '') {            
            $date_filter .= " AND $basedon <= to_date('".$this->enddate." 23:59:59','mm/dd/yyyy hh24:mi:ss') ";
        }



        $filters = array();

        if ($date_filter) {
            $filters[] = $date_filter; 
        }


        return $filters;
    }

    /**
     * @return string
     */
    public function GetFirstStageXSLFile()
    {
        return 'recur_stdxml.xsl';
    }
}

