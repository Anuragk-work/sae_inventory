<?
import('RecurReport');
import('DateTemplates');
require_once 'Dictionary.cls';

/**
 * Class INVRecurReport
 */
class INVRecurReport extends RecurReport
{
    /**
     * @var array $arg
     */
    public $arg;

    /**
     * @var string $sortmode
     */
    public $sortmode;

    /**
     * @var string[][]|false $recurinvs
     */
    private $recurinvs;

    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, 
                array( 
                'report' => 'invrecur', 
                'ops'     => array("inv/reports/invrecur"),
                '2stage' => 'true',
                'reportslide' => true,
                ) 
            )
        );        
    }

    /**
     * @return bool
     */
    public function DoQuery()
    {
        // Do any tweaks here that we need, like min/max vals, isl_htmlspecialchars, etc.
        $ok = $this->ParamTweaks();
        if (!$ok) {
            return false;
        }

        $selList = "
							dochdr.record# RECORDNO		,
							'' ENTITY		,         
							'' ENTITYID,
							'' ENTITYLOCATION,
							dochdr.LOCATIONKEY LOCATION,
							dochdr.docid,
							dochdr.STATUS          ,       
							dochdr.WHENCREATED     ,       
							dochdr.TERMKEY         ,       
							term.name	TERMNAME		,
							dochdr.RECORD# Recordid       ,       
							dochdr.DOCNUMBER       ,
							dochdr.docname,
							decode(	dochdr.FREQUENCY,
									'N', 'None', 'D', 'Days', 'W', 'Weeks', 'M', 'Months', 'Y', 'Years', 'E', 'End Of Month'
								) FREQUENCY,       
							dochdr.EXECCOUNT       ,       
							dochdr.STARTDATE       ,       
							dochdr.nextexecdate NEXTEXECDATE    ,       
							dochdr.TOTALENTERED    ,       
							dochdr.CONTRACTID	CONTRACT,
							(select count(schopkey) from dochdr doc where doc.cny# = 	dochdr.cny# 
								and doc.schopkey = dochdr.schopkey) DOCSCOUNT,
							'' DUEDATE						
		";
        
        $fromClause = "
						(SELECT 
						recurdochdr.cny#, recurdochdr.RECORD# docid, recurdochdr.record# record#, schedule.record# schedrec, scheduledoperation.record# schedoprec, 
						'' customerid,'' CUSTOMERNAME, '' custtypekey, '' custloc, recurdochdr.status STATUS,'' WHENCREATED, 
						recurdochdr.TERMKEY, 
						recurdochdr.RECORD# Recordid, 
						recurdochdr.PONUMBER docnumber,
						schedule.startdate STARTDATE,schedule.enddate ENDDATE, recurdochdr.entity, 
						 schedule.repeatby FREQUENCY, schedule.execcount EXECCOUNT, schedule.nextexecdate NEXTEXECDATE, 
						case when recurdochdr.total > 0 then
						   recurdochdr.total
						else 
						   (select sum(uivalue) from recurdocentry where cny# = recurdochdr.cny# and recurdochdrkey = recurdochdr.record#) 
						end TOTALENTERED  , 
						recurdochdr.schopkey SCHOPKEY, 
						recurdochdr.contractid CONTRACTID, 
						recurdochdr.locationkey, recurdochdr.deptkey, 
						recurdochdr.BILLTOKEY, recurdochdr.SHIPTOKEY, 
						docpar.docid docname, schedule.duedate
					FROM 
						recurdochdr, docpar ,scheduledoperation scheduledoperation,schedule schedule 
					WHERE 
						scheduledoperation.cny# = recurdochdr.cny#  
						and schedule.cny# = recurdochdr.cny#  and 
						recurdochdr.cny# = docpar.cny# and
						recurdochdr.docparkey = docpar.record# and
						docpar.sale_pur_trans = 'I' and
						scheduledoperation.record# = recurdochdr.schopkey and scheduledoperation.schedule# = schedule.record#) dochdr,
							term
		";

        $whereClause = " dochdr.cny# = :1";

        $termJoin = " 
						AND dochdr.cny# = term.cny#(+) 
						AND	dochdr.termkey = term.record# (+) 
					";

        $filters = $this->calcFilters();
        $addFilters = join(' ', $filters);

        $where = $whereClause.$termJoin.$addFilters;

        $qry = "select $selList from $fromClause where $where";

        $order = " order by " . $this->sortmode;

        $stmt[0] = $qry . $order;        

        $stmt = INTACCTarray_merge($stmt, $this->arg);

        $this->recurinvs = QueryResult($stmt);

        foreach( $this->recurinvs as $key => $row)
        {
            $this->recurinvs[$key]['WHENCREATED'] = FormatDateForDisplay($this->recurinvs[$key]['WHENCREATED']);
            $this->recurinvs[$key]['STARTDATE'] = FormatDateForDisplay($this->recurinvs[$key]['STARTDATE']);
            $this->recurinvs[$key]['NEXTEXECDATE'] = FormatDateForDisplay($this->recurinvs[$key]['NEXTEXECDATE']);
        }

        if (count($this->recurinvs)) {
            $selList = "sum(dochdr.TOTALENTERED) total";
            $qry = "select $selList from $fromClause where $where";
            $stmt[0] = $qry;
            /** @noinspection PhpUndefinedVariableInspection */
            $stmt = INTACCTarray_merge($stmt, $arg);        
            $this->totals = QueryResult($stmt); 
        }

        return true;

    }

    /**
     * @return mixed
     */
    public function DoMap()
    {
        //Establish the Report Header
        $lines = $this->ReportHeader();

        //Establish the Body
        if(count($this->recurinvs) > 0 ) { 
            $this->ReportBody($lines, $this->recurinvs); 
            $this->ReportTotal($lines, $this->totals); 
        }
        else {
            $bodylines['NODATA'][0]= array('NODATA'=>'1');
            $this->ReportBody($lines, $bodylines); 
        }

        return $lines;
    }

    /**
     * @return bool
     */
    public function ParamTweaks()
    {        
        global $gErr;
        
        parent::ParamTweaks(); 
        $params = $this->params;
        $p['CUSTOMERTYPE']        = $params['CUSTOMERTYPE'] ? isl_htmlspecialchars($params['CUSTOMERTYPE']) : '';
        $p['FROMCUSTOMER']            = $params['FROMCUSTOMER'] ? isl_trim(isl_htmlspecialchars($params['FROMCUSTOMER'])) : '';    

        $p['FROMDERIVEDOCTYPE']            = $params['FROMDERIVEDOCTYPE'] ? isl_trim(isl_htmlspecialchars($params['FROMDERIVEDOCTYPE'])) : '';    
        $p['TODERIVEDOCTYPE']            = $params['TODERIVEDOCTYPE'] ? isl_trim(isl_htmlspecialchars($params['TODERIVEDOCTYPE'])) : '';    

        $params = $this->params;
        if (HasErrors()) { 
            if($gErr->ErrorCount) {
                return false;
            }
        }

        // remember our tweaked values
        $params['safe'] = INTACCTarray_merge($this->params['safe'], $p);
        $this->params = $params;

        return true;
    }

    /**
     * @return array
     */
    public function calcFilters()
    {
        $params                    = $this->params['safe'];
        $this->sortmode                = $params['SORTMODE'];        
        $cny = GetMyCompany();

        // Determine filters ! 
        $this->arg = array($cny);
        $args = 1;

        $filters = array();
        if ($params['FROMDERIVEDOCTYPE']) {
            list($custid) = explode(PICK_RECVAL_SEP, isl_trim($params['FROMDERIVEDOCTYPE']));
            $filters[]  = " AND dochdr.docname >= :".++$args;
            $this->arg[] = $custid;
        }
        if ($this->params['TODERIVEDOCTYPE']) {
            list($custid) = explode(PICK_RECVAL_SEP, isl_trim($params['TODERIVEDOCTYPE']));
            $filters[] = " AND dochdr.docname <= :".++$args;
            $this->arg[] = $custid;
        }

        return INTACCTarray_merge($filters, parent::calcFilters());
    }
}


