<?
import('InventoryReporter');

/**
 * Class ItemActivityReport
 */
class ItemActivityReport extends InventoryReporter
{
    /**
     * @var array $_begbalance
     */
    var $_begbalance = array();

    /**
     * @var array $_activity
     */
    var $_activity = array();

    /** @var string $prodlineid */
    protected $prodlineid = '';

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                    'report' => 'itemactivity',
                    'ops' => array(
                        'inv/lists/item/view',
                        'inv/lists/warehouse/view',
                        'inv/lists/invdocument/view',
                        'so/lists/sodocument/view',
                        'po/lists/podocument/view',
                    ),
                    '2stage' => true,
                )
            )
        );
        $this->setOtherParams();
    }

    /**
     * To set the other parameters as needed by reporter class
     */
    protected function setOtherParams()
    {
        if (IsMCMESubscribed() && Request::$r->APPLYLOCATIONRESTRICTION == 'false') {
            $this->params['NOREPORTLOCCHECK'] = true;
        }
    }

    /**
     * @return bool
     */
    function DoQuery()
    {
        global $_userid;
        [, $cny] = explode('@', $_userid);

        $this->ValidateReport();

        // reload after the validate report
        $params                     = $this->params['safe'];

        $vardt1                     = Request::$r->START_DATE;
        $vardt2                     = Request::$r->END_DATE;

        $fromwarehouseid            = $params['FROMWAREHOUSEID'];
        $towarehouseid              = $params['TOWAREHOUSEID'];
        $fromitemid                 = $params['FROMITEMID'];
        $toitemid                   = $params['TOITEMID'];

        $ReportOn                   = $this->params['REPORTON'];
        $fromupc                    = $params['FROMUPC'];
        $toupc                      = $params['TOUPC'];
        $ItemOperator               = $this->params['ITEMOPERATOR'];
        $itemValues                 = $this->params['ITEMVALUES'];
        $UPCOperator                = $this->params['UPCOPERATOR'];
        $upcValues                  = $this->params['UPCVALUES'];
        $showValueOnly              = $this->params['SHOWVALUEONLY'];
        $hideinactiveitem           = $this->params['HIDEINACTIVEITEM'];
        $hideinactivewh             = $this->params['HIDEINACTIVEWH'];
        $this->prodlineid			= $params['PRODLINEID'];
        $includeIntrasit	        = $this->params['INCLUDEINTRANSIT'];
        $includeReserved	        = $this->params['INCLUDERESERVED'];
        $includeAllocated	        = $this->params['INCLUDEALLOCATED'];

        /*
         * Prepare the Product Line QRY string to use it to filter items by product line info
         */
        if ($this->prodlineid != '%') {
           $this->prepareProductLineMapQry($this->prodlineid,'it');
        }


        if (isset($vardt1) && $vardt1 != '') {
            $params['dt1'] = $vardt1;
        }
        $dt1 = $params['dt1'];

        if (isset($vardt2) && $vardt2 != '') {
            $params['dt2'] = $vardt2;
        }
        $dt2 = $params['dt2'];


        if ($fromwarehouseid == '0' || $towarehouseid == '0') {
            $whseClause = ' or ia.warehousekey is null';
        }

        $itemFilter = '';
        $itemFilter2 = '';
        if ($hideinactiveitem == 'true') {
            $itemFilter = " and i.status  = 'T' ";
            $itemFilter2 = " and it.status  = 'T' ";
        }

        $whSelect = '';
        $whFilter = '';
        $whFilter2 = '';
        if ($hideinactivewh == 'true') {
            $whSelect = ", icwarehouse icwh ";
            $whFilter = " and icwh.cny# = ia.cny# and icwh.warehouseid = ia.warehousekey and icwh.status  = 'T' ";
            $whFilter2 = " and icw.status  = 'T' ";
        }


        $ictotalsLocationFilter = $this->_getLocationClause($params, 'ia');
        $ictotalsDeptFilter = $this->_getDeptClause($params, 'ia');

        $dt1 = ($dt1 == '' ? GetCompanyOpenDate() : $dt1);

        $from = Date2Period($dt1);

        // get latest month timeperiod no
        $maxPeriod = max(0, $from - 1);
        $firstdayofmonth = isFirstDayofMonth($dt1) ? true : false;

        [$totals_start_date] = Period2Dates($from);

        // following 'sql' is a querystmt place holder
        $args = array('sql', $cny,);
        $activityargs = array('sql', $cny,);

        /*
         * This will be used to prefetch the standalone value documents which are
         * part of a hierarchy--i.e., which refer to others, or are referred to by others,
         * via source_doclinekey.
         *
         * It's only included in the query when standalone value documents are requested in
         * the report.
         */
         $cte = 'with cte as (
            select
                distinct record#, starting_doclinekey
            from (
                select
                    record#,
                    CONNECT_BY_ROOT de.record# starting_doclinekey
                from
                    docentrymst de
                where
                    de.cny# = :1
                    start with
                        de.cny# = :1
                        and de.record# in (
                            select
                                distinct source_doclinekey
                            from
                                docentrymst
                            where
                                cny# = :1
                                and source_doclinekey is not null )
                    connect by
                        de.record# = prior de.source_doclinekey
                        and de.cny# = :1
                union all
                select
                    record#,
                    CONNECT_BY_ROOT de.source_doclinekey starting_doclinekey
                from
                    docentrymst de
                where
                    de.cny# = :1
                    start with
                        de.cny# = :1
                        and de.source_doclinekey in (
                            select
                                distinct record#
                            from
                                docentrymst
                            where
                                cny# = :1 )
                    connect by
                        de.source_doclinekey = prior de.record#
                        and de.cny# = :1 ) hierarchies
                where hierarchies.record# in ( select distinct docentrykey from docentrycost where cny# = :1) ) ';

        $ctePrefix = ($showValueOnly === 'true') ? $cte : '';

        if ($ReportOn == 'ITEMID') {
            if ($fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'it', 'itemid', $itemValues, 2);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                array_push($activityargs, $itemupcargs, '');
                //}

            } else {
                $filterItemorUPC = " it.itemid  >= :2 and it.itemid  <= :3 ";
                array_push($args, $fromitemid, $toitemid);
                array_push($activityargs, $fromitemid, $toitemid);
            }
        } else {

            if ($fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'it', 'upc', $upcValues, 2);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                array_push($activityargs, $itemupcargs, '');
                //}
            } else {
                $filterItemorUPC = " it.upc  >= :2 and it.upc  <= :3 ";
                array_push($args, $fromupc, $toupc);
                array_push($activityargs, $fromupc, $toupc);
            }
        }


        // accumulate totals from icitemtotals before the start date
        /** @noinspection PhpUndefinedVariableInspection */
        $balFrwdQry = " select ia.cny#, ia.itemkey, ia.warehousekey, null as whencreated, null as parentdochdrkey,
					nvl(ia.posquantity,0) + nvl(ia.negquantity,0) as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, 
					it.upc, 0 as reservedqty, 0 as allocatedqty
					from icitemtotals ia, ictotal onorderictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.timeperiod <= :6 and
						ia.cny# = onorderictotal.cny# and
						ia.totalkey = onorderictotal.record# and
						onorderictotal.name = 'ONORDER' $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2
					UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey, null as whencreated, null as parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, nvl(ia.posquantity,0) + nvl(ia.negquantity,0) as onhandqty, 0 as onholdqty, 
					it.upc, 0 as reservedqty, 0 as allocatedqty 
					from icitemtotals ia, ictotal onhandictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry}  ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.timeperiod <= :6 and
						ia.cny# = onhandictotal.cny# and
						ia.totalkey = onhandictotal.record# and
						onhandictotal.name = 'ONHAND'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2
					UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey,  null as whencreated, null as parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, nvl(ia.posquantity,0) + nvl(ia.negquantity,0) as onholdqty, 
					it.upc, 0 as reservedqty, 0 as allocatedqty 
					from icitemtotals ia, ictotal onholdictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.timeperiod <= :6 and
						ia.cny# = onholdictotal.cny# and
						ia.totalkey = onholdictotal.record# and
						onholdictotal.name = 'ONHOLD'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2";

        if ($includeIntrasit == 'true') {
            $balFrwdQry .= " UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey, null as whencreated, null as parentdochdrkey,
					0 as onorderqty, 0 as onhandqty, nvl(ia.posquantity,0) + nvl(ia.negquantity,0) as intransitqty, 
					0 as onholdqty, it.upc, 0 as reservedqty, 0 as allocatedqty
					from icitemtotals ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry}  ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.timeperiod <= :6 and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ictotal.name = 'INTRANSIT'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2	";
        }
        if ($includeReserved == 'true') {
            $balFrwdQry .= " UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey, null as whencreated, null as parentdochdrkey,
					0 as onorderqty, 0 as onhandqty, 0 as intransitqty, 0 as onholdqty, it.upc, 
					nvl(ia.posquantity,0) + nvl(ia.negquantity,0) as reservedqty, 0 as allocatedqty
					from icitemtotals ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry}  ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.timeperiod <= :6 and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ictotal.name = 'RESERVED'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2	";
        }
        if ($includeAllocated == 'true') {
            $balFrwdQry .= " UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey, null as whencreated, null as parentdochdrkey,
					0 as onorderqty, 0 as onhandqty, 0 as intransitqty, 0 as onholdqty, it.upc, 0 as reservedqty, 
					nvl(ia.posquantity,0) + nvl(ia.negquantity,0) as allocatedqty
					from icitemtotals ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry}  ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.timeperiod <= :6 and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ictotal.name = 'ALLOCATED'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2	";
        }
        if ($showValueOnly == 'true') {
            $balFrwdQry .= " UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.dochdrkey,
					0 as onorderqty, 0 as intransitqty, decode(dc.in_out, 'I', dc.quantity, dc.quantity * -1) as onhandqty,
					0 as onholdqty, it.upc, 0 as reservedqty, 0 as allocatedqty 
					from docentrymst ia, icitem it, docentrycost dc $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated < to_date(:7, 'mm/dd/yyyy') and
						dc.systemgenerated = 'F' and
						dc.cny#=ia.cny# and dc.affects_inventory = 'V' and 
						dc.docentrykey = ia.record# and 
						--exclude docs which have a child DC layer(hopefully Q)
                        not exists (
						    select 1 from cte where ia.record# = cte.starting_doclinekey
						) 
						--exclude docs which have a parent DC layer(hopefully Q)
						and not exists (
						    select 1 from cte where ia.source_doclinekey = cte.starting_doclinekey
						        and ia.record# = cte.record#
						)
						 $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2";
        }

        //get the total by considering activity between last total ending date and start_date.
        // NOTE: ALLOCATED and RESERVED entires' whencreated has time-of-day (because we track WHEN it was allocated/reserved)
        $balFrwdPlusActivityQry = " select ia.cny#, ia.itemkey, ia.warehousekey, ia.whencreated, ia.parentdochdrkey,
					nvl(ia.quantity,0) as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					0 as reservedqty , 0 as allocatedqty
					from icitemactivity ia, ictotal onorderictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and 
						ia.whencreated >= to_date(:7, 'mm/dd/yyyy') and ia.whencreated < to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = onorderictotal.cny# and
						ia.totalkey = onorderictotal.record# and
						onorderictotal.name = 'ONORDER'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2
					UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, nvl(ia.quantity,0) as onhandqty, 0 as onholdqty, it.upc, 
					0 as reservedqty , 0 as allocatedqty 
					from icitemactivity ia, ictotal onhandictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated >= to_date(:7, 'mm/dd/yyyy') and ia.whencreated < to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = onhandictotal.cny# and
						ia.totalkey = onhandictotal.record# and
 						onhandictotal.name = 'ONHAND'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2					
					UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey, ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, nvl(ia.quantity,0) as onholdqty, it.upc, 
					0 as reservedqty , 0 as allocatedqty 
					from icitemactivity ia, ictotal onholdictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated >= to_date(:7, 'mm/dd/yyyy') and ia.whencreated < to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = onholdictotal.cny# and
						ia.totalkey = onholdictotal.record# and
						onholdictotal.name = 'ONHOLD'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2";

        if ($includeIntrasit == 'true') {
            $balFrwdPlusActivityQry .= " UNION ALL
                    select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, nvl(ia.quantity,0) as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					0 as reservedqty , 0 as allocatedqty   
					from icitemactivity ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated >= to_date(:7, 'mm/dd/yyyy') and ia.whencreated < to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ictotal.name = 'INTRANSIT' $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2	";
        }
        if ($includeReserved == 'true') {
            $balFrwdPlusActivityQry .= " UNION ALL
                    select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					nvl(ia.quantity,0) as reservedqty ,0 as allocatedqty 
					from icitemactivity ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						TRUNC(ia.whencreated, 'DD') >= to_date(:7, 'mm/dd/yyyy') and TRUNC(ia.whencreated, 'DD') < to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ictotal.name = 'RESERVED' $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2	";
        }
        if ($includeAllocated == 'true') {
            $balFrwdPlusActivityQry .= " UNION ALL
                    select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					0 as reservedqty , nvl(ia.quantity,0) as allocatedqty  
					from icitemactivity ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						TRUNC(ia.whencreated, 'DD') >= to_date(:7, 'mm/dd/yyyy') and TRUNC(ia.whencreated, 'DD') < to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ictotal.name = 'ALLOCATED' $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2	";
        }

        if ($showValueOnly == 'true') {
            $balFrwdPlusActivityQry .= " UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.dochdrkey,
					0 as onorderqty, 0 as intransitqty, decode(dc.in_out, 'I', dc.quantity, dc.quantity * -1) as onhandqty, 
					0 as onholdqty, it.upc , 0 as reservedqty, 0 as allocatedqty
					from docentrymst ia, icitem it, docentrycost dc $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						TRUNC(ia.whencreated, 'DD') >= to_date(:7, 'mm/dd/yyyy') and TRUNC(ia.whencreated, 'DD') < to_date(:8, 'mm/dd/yyyy') and
						dc.systemgenerated = 'F' and
						dc.cny#=ia.cny# and 
						dc.affects_inventory = 'V' and 
						dc.docentrykey = ia.record#  and 
						--exclude docs which have a child DC layer(hopefully Q)
                        not exists (
						    select 1 from cte where ia.record# = cte.starting_doclinekey
						) 
						--exclude docs which have a parent DC layer(hopefully Q)
						and not exists (
						    select 1 from cte where ia.source_doclinekey = cte.starting_doclinekey
						        and ia.record# = cte.record#
						)
						$ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2";
        }

        $subtable_activity = " select ia.cny#, ia.itemkey, ia.warehousekey, ia.whencreated, ia.parentdochdrkey,
					nvl(ia.quantity,0) as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					null as vonly,0 as reservedqty, 0 as allocatedqty
					from icitemactivity ia, ictotal onorderictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and 
						ia.whencreated between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = onorderictotal.cny# and
						ia.totalkey = onorderictotal.record# and
						onorderictotal.name = 'ONORDER' $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2
					UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, nvl(ia.quantity,0) as onhandqty, 0 as onholdqty, it.upc, 
					null as vonly, 0 as reservedqty, 0 as allocatedqty
					from icitemactivity ia, ictotal onhandictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = onhandictotal.cny# and
						ia.totalkey = onhandictotal.record# and
						ia.quantity <> 0 and
						onhandictotal.name = 'ONHAND'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2
					UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey, ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, nvl(ia.quantity,0) as onholdqty, it.upc, 
					null as vonly, 0 as reservedqty, 0 as allocatedqty
					from icitemactivity ia, ictotal onholdictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = onholdictotal.cny# and
						ia.totalkey = onholdictotal.record# and
						onholdictotal.name = 'ONHOLD' $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2";

        if ($includeIntrasit == 'true') {
            $subtable_activity .= " UNION ALL
                    select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, nvl(ia.quantity,0) as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					null as vonly, 0 as reservedqty, 0 as allocatedqty
					from icitemactivity ia, ictotal intransitictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = intransitictotal.cny# and
						ia.totalkey = intransitictotal.record# and
						ia.quantity <> 0 and
						intransitictotal.name = 'INTRANSIT'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2 ";
        }
        if ($includeReserved == 'true') {
            // note math with end date to accommodate times up to, but not including, midnight
            $subtable_activity .= " UNION ALL
                    select ia.cny#, ia.itemkey, ia.warehousekey, ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					null as vonly, nvl(ia.quantity,0) as reservedqty, 0 as allocatedqty
					from icitemactivity ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						TRUNC(ia.whencreated,'DD') between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ia.quantity <> 0 and
						ictotal.name = 'RESERVED'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2 ";
        }
        if ($includeAllocated == 'true') {
            // note math with end date to accommodate times up to, but not including, midnight
            $subtable_activity .= " UNION ALL
                    select ia.cny#, ia.itemkey, ia.warehousekey, ia.whencreated, ia.parentdochdrkey,
					0 as onorderqty, 0 as intransitqty, 0 as onhandqty, 0 as onholdqty, it.upc, 
					null as vonly, 0 as reservedqty, nvl(ia.quantity,0)  as allocatedqty
					from icitemactivity ia, ictotal, icitem it $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						--ia.itemkey between :2 and :3 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						TRUNC(ia.whencreated,'DD') between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						ia.cny# = ictotal.cny# and
						ia.totalkey = ictotal.record# and
						ia.quantity <> 0 and
						ictotal.name = 'ALLOCATED'  $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2 ";
        }



        if ($showValueOnly == 'true') {
            $subtable_activity .= " UNION ALL
					select ia.cny#, ia.itemkey, ia.warehousekey,ia.whencreated, ia.dochdrkey,
					0 as onorderqty, 0 as intransitqty, decode(dc.in_out, 'I', dc.quantity, dc.quantity * -1) as onhandqty, 
					0 as onholdqty, it.upc, 'T' as vonly, 0 as reservedqty, 0 as allocatedqty
					from docentrymst ia, icitem it, docentrycost dc $whSelect
					where {$this->prodlineChildMapQry} ia.cny# = :1 and
						it.cny# = ia.cny# and
						it.itemid = ia.itemkey and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						ia.whencreated between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						dc.cny#=ia.cny# and dc.affects_inventory = 'V' and
						dc.systemgenerated = 'F' and 
						dc.docentrykey = ia.record#  and 
						--exclude docs which have a child DC layer(hopefully Q)
                        not exists (
						    select 1 from cte where ia.record# = cte.starting_doclinekey
						) 
						--exclude docs which have a parent DC layer(hopefully Q)
						and not exists (
						    select 1 from cte where ia.source_doclinekey = cte.starting_doclinekey
						        and ia.record# = cte.record#
						)
						 $ictotalsLocationFilter $ictotalsDeptFilter $whFilter $itemFilter2";
        }
        array_push($args, $fromwarehouseid, $towarehouseid, $maxPeriod);
        if (!$firstdayofmonth) {

            $balFrwdQry .= ' UNION ALL ' . $balFrwdPlusActivityQry;
            $args[] = $totals_start_date;
            $args[] = $dt1;
        } else if ($showValueOnly == 'true') {
            $args[] = $totals_start_date;
        }

        $balFrwdSummaryqry = $ctePrefix . "select 
					it.itemkey,
					i.name,
					i.locationkey ITOWNERLOC,
					it.warehousekey,
					icw.locationkey WHOWNERLOC,
					uom.unit as selectuom,
					uom.numdec as uom_no,
					sum(it.onorderqty) as begonorderqty, 
					sum(it.intransitqty) as begintransitqty, 
					sum(it.onhandqty) as begonhandqty,
					sum(it.onholdqty) as begonholdqty, i.upc,
                    sum(it.reservedqty) as begreservedqty,
					sum(it.allocatedqty) as begallocatedqty
				FROM ( $balFrwdQry ) it, icitem i, icwarehouse icw, icuom uom
				WHERE  it.cny# = i.cny# and 
					it.itemkey = i.itemid and
					i.itemtype in ('I','SK') and
					icw.cny# = it.cny# and
					icw.location_no = it.warehousekey and				
					uom.cny# = i.cny# and
					uom.grpkey = i.uomgrpkey and
					uom.isbase = 'T'
					$whFilter2 $itemFilter
				GROUP BY it.itemkey, i.name, i.locationkey, it.warehousekey, icw.locationkey, uom.unit, uom.numdec, i.upc
				ORDER BY it.itemkey, it.warehousekey";

        $args[0] = $balFrwdSummaryqry;

        $this->_begbalance = QueryResult($args);

        //Reusing the query subtable2, hence keeping whencreated as 7 and 8 and introducing the redundand bind variable 6
        $activityqry = $ctePrefix . "SELECT
						ia.itemkey,
						it.name,
						it.locationkey ITOWNERLOC,
						ia.warehousekey,
						icw.locationkey WHOWNERLOC,
						dh.docid,
						dh.melocationkey DOCOWNERLOC,
						ia.whencreated,
						dh.record# as recordno,
						uom.unit as selectuom,
						uom.numdec as uom_no,
						ia.vonly,
						sum(ia.onorderqty) as onorderqty,
						sum(ia.intransitqty) as intransitqty,
						sum(ia.onhandqty) as onhandqty,
						sum(ia.onholdqty) as onholdqty,
						sum(ia.reservedqty) as reservedqty,
						sum(ia.allocatedqty) as allocatedqty,
						dr.sale_pur_trans as transactionmodule, it.upc
					FROM icitem it, icwarehouse icw, ($subtable_activity) ia, dochdr dh, icuom uom, docpar dr
					WHERE {$this->prodlineChildMapQry} ia.cny# = :1 and
						$filterItemorUPC and
						(ia.warehousekey between :4 and :5 $whseClause) and
						TRUNC(ia.whencreated, 'DD') between to_date(:7, 'mm/dd/yyyy') and to_date(:8, 'mm/dd/yyyy') and
						it.cny# = :6 and
						it.itemid = ia.itemkey and
						it.itemtype in ('I','SK') and
						icw.cny# = :6 and
						icw.location_no = ia.warehousekey and
						uom.cny# = it.cny# and
						uom.grpkey = it.uomgrpkey and
						uom.isbase = 'T' and
						dh.cny# = it.cny# and
						dh.record# = ia.parentdochdrkey	and	
						dh.cny#=dr.cny# and
						dh.docparkey=dr.record#
						$whFilter2 $itemFilter2
					GROUP BY ia.itemkey, it.name, it.locationkey, ia.warehousekey, icw.locationkey, dh.docid, 
					dh.melocationkey, ia.whencreated, dh.record#, uom.unit, uom.numdec, dr.sale_pur_trans, it.upc, 
					ia.vonly
					ORDER BY ia.itemkey, ia.warehousekey, ia.whencreated, dh.record#, dr.sale_pur_trans";

        array_push($activityargs, $fromwarehouseid, $towarehouseid, $cny, $dt1, $dt2);
        $activityargs[0] = $activityqry;
        $this->_activity = QueryResult($activityargs);

        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {

        $itemMap = array();
        $whseMap = array();
        $resMap = array();
        $uomPref = INVSetupManager::getUOMPreference();
        $round = ItemManager::BASEUNITPRECISION;
        $hideitemwithoutactivity    = $this->params['HIDEITEMWITHOUTACTIVITY'];

        if ($uomPref) {
            $defaultUOMCache = $this->GetUOMCache(true);
        }

        foreach ($this->_begbalance as $it) {

            if ($hideitemwithoutactivity == 'true' && $it['BEGONORDERQTY'] == 0
                 && $it['BEGONHANDQTY'] == 0 && $it ['BEGONHOLDQTY'] == 0 && $it ['BEGINTRANSITQTY'] == 0
                 && $it ['BEGINRESERVEDQTY'] == 0 && $it ['BEGALLOCATEDQTY'] == 0) {
                continue;
            }
            $itemid = $it['ITEMKEY'];
            $whse = ($it['WAREHOUSEKEY']) ?: '-';

            //$itemMap[$itemid]['ITEMHREF'] 	= "javascript:drilldown(0,'" . urlencode(addslashes($itemid)) . "');";
            $itemBeg = urlencode(addslashes($itemid));
            $itemMap[$itemid]['ITEMHREF'] = "javascript:drilldown(0,'$itemBeg', '$it[ITOWNERLOC]');";

            $itemMap[$itemid]['ITEM'] = ($this->params['REPORTON']) == 'ITEMID' ? $itemid : $it['UPC'];
            $itemMap[$itemid]['UOM'] = $it['SELECTUOM'];
            $itemMap[$itemid]['NAME'] = $it['NAME'];

            if ($uomPref) {
                /** @noinspection PhpUndefinedVariableInspection */
                $uomInfo = $defaultUOMCache[$it['ITEMKEY']];
                $itemMap[$itemid]['UOM'] = $uomInfo['UNIT'];
                $it['BEGONORDERQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $it['BEGONORDERQTY']);
                $it['BEGINTRANSITQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $it['BEGINTRANSITQTY']);
                $it['BEGONHANDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $it['BEGONHANDQTY']);
                $it['BEGONHOLDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $it['BEGONHOLDQTY']);
                $it['BEGINRESERVEDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $it['BEGINRESERVEDQTY']);
                $it['BEGALLOCATEDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $it['BEGALLOCATEDQTY']);
            }

            $itemMap[$itemid]['TOTONORDERQTY'] = ibcadd($it['BEGONORDERQTY'], $itemMap[$itemid]['TOTONORDERQTY'], $round, true);
            $itemMap[$itemid]['TOTINTRANSITQTY'] = ibcadd($it['BEGINTRANSITQTY'], $itemMap[$itemid]['TOTINTRANSITQTY'], $round, true);
            $itemMap[$itemid]['TOTONHANDQTY'] = ibcadd($it['BEGONHANDQTY'], $itemMap[$itemid]['TOTONHANDQTY'], $round, true);
            $itemMap[$itemid]['TOTONHOLDQTY'] = ibcadd($it['BEGONHOLDQTY'], $itemMap[$itemid]['TOTONHOLDQTY'], $round, true);
            $itemMap[$itemid]['TOTRESERVEDQTY'] = ibcadd($it['BEGRESERVEDQTY'], $itemMap[$itemid]['TOTRESERVEDQTY'], $round, true);
            $itemMap[$itemid]['TOTALLOCATEDQTY'] = ibcadd($it['BEGALLOCATEDQTY'], $itemMap[$itemid]['TOTALOCATEDQTY'], $round, true);


            $whseMap[$itemid][$whse] = $it;
            $whseMap[$itemid][$whse]['WAREHOUSEKEY'] = $whse;
            $whseMap[$itemid][$whse]['WHSEHREF'] = "javascript:drilldown(1,'" . urlencode($whse) . "', '$it[WHOWNERLOC]');";

            $whseMap[$itemid][$whse]['TOTONORDERQTY'] = ibcadd($it['BEGONORDERQTY'], '0', $round, true);
            $whseMap[$itemid][$whse]['TOTINTRANSITQTY'] = ibcadd($it['BEGINTRANSITQTY'], '0', $round, true);
            $whseMap[$itemid][$whse]['TOTONHANDQTY'] = ibcadd($it['BEGONHANDQTY'], '0', $round, true);
            $whseMap[$itemid][$whse]['TOTONHOLDQTY'] = ibcadd($it['BEGONHOLDQTY'], '0', $round, true);
            $whseMap[$itemid][$whse]['TOTRESERVEDQTY'] = ibcadd($it['BEGRESERVEDQTY'], '0', $round, true);
            $whseMap[$itemid][$whse]['TOTALLOCATEDQTY'] = ibcadd($it['BEGALLOCATEDQTY'], '0', $round, true);
        }

        foreach ($this->_activity as $trans) {
            $tItemid = $trans['ITEMKEY'];
            $whse = ($trans['WAREHOUSEKEY']) ?: '-';

            if (!$itemMap[$tItemid]) {
                $itemEnc = urlencode(addslashes($tItemid));
                $itemMap[$tItemid]['ITEMHREF'] = "javascript:drilldown(0,'$itemEnc', '$trans[ITOWNERLOC]');";
                $itemMap[$tItemid]['ITEM'] = ($this->params['REPORTON']) == 'ITEMID' ? $tItemid : $trans['UPC'];
                $itemMap[$tItemid]['UOM'] = $trans['SELECTUOM'];
                $itemMap[$tItemid]['NAME'] = $trans['NAME'];
            }

            if (!$whseMap[$tItemid][$whse]) {
                $whseMap[$tItemid][$whse]['WAREHOUSEKEY'] = $whse;
                $whseMap[$tItemid][$whse]['WHSEHREF'] = "javascript:drilldown(1,'" . urlencode($whse) . "', '$trans[WHOWNERLOC]');";

                $whseMap[$tItemid][$whse]['BEGONORDERQTY'] = 0;
                $whseMap[$tItemid][$whse]['BEGINTRANSITQTY'] = 0;
                $whseMap[$tItemid][$whse]['BEGONHANDQTY'] = 0;
                $whseMap[$tItemid][$whse]['BEGONHOLDQTY'] = 0;
                $whseMap[$tItemid][$whse]['BEGRESERVEDQTY'] = 0;
                $whseMap[$tItemid][$whse]['BEGALLOCATEDQTY'] = 0;
            }

            if ($trans['TRANSACTIONMODULE'] == 'I') {
                $trans['HREF'] = "javascript:drilldown(2,'" . urlencode($trans['DOCID']) . "', '$trans[DOCOWNERLOC]');";
            } elseif ($trans['TRANSACTIONMODULE'] == 'S') {
                $trans['HREF'] = "javascript:drilldown(3,'" . urlencode($trans['DOCID']) . "', '$trans[DOCOWNERLOC]');";
            } elseif ($trans['TRANSACTIONMODULE'] == 'P') {
                $trans['HREF'] = "javascript:drilldown(4,'" . urlencode($trans['DOCID']) . "', '$trans[DOCOWNERLOC]');";
            }
            $trans['DOCID'] = (isset($trans['DOCOWNERLOC'])) ? $trans['DOCID'] . ' - ' . $trans['DOCOWNERLOC'] : $trans['DOCID'];
            $trans['WHENCREATED'] = FormatDateForDisplay($trans['WHENCREATED']);

            if ($uomPref) {
                /** @noinspection PhpUndefinedVariableInspection */
                $uomInfo = $defaultUOMCache[$trans['ITEMKEY']];
                $itemMap[$tItemid]['UOM'] = $uomInfo['UNIT'];
                $trans['ONORDERQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $trans['ONORDERQTY']);
                $trans['INTRANSITQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $trans['INTRANSITQTY']);
                $trans['ONHANDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $trans['ONHANDQTY']);
                $trans['ONHOLDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $trans['ONHOLDQTY']);
                $trans['RESERVEDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $trans['RESERVEDQTY']);
                $trans['ALLOCATEDQTY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $trans['ALLOCATEDQTY']);
            }

            $whseMap[$tItemid][$whse]['TOTONORDERQTY'] = ibcadd($trans['ONORDERQTY'], $whseMap[$tItemid][$whse]['TOTONORDERQTY'], $round, true);
            $whseMap[$tItemid][$whse]['TOTINTRANSITQTY'] = ibcadd($trans['INTRANSITQTY'], $whseMap[$tItemid][$whse]['TOTINTRANSITQTY'], $round, true);
            $whseMap[$tItemid][$whse]['TOTONHANDQTY'] = ibcadd($trans['ONHANDQTY'], $whseMap[$tItemid][$whse]['TOTONHANDQTY'], $round, true);
            $whseMap[$tItemid][$whse]['TOTONHOLDQTY'] = ibcadd($trans['ONHOLDQTY'], $whseMap[$tItemid][$whse]['TOTONHOLDQTY'], $round, true);
            $whseMap[$tItemid][$whse]['TOTRESERVEDQTY'] = ibcadd($trans['RESERVEDQTY'], $whseMap[$tItemid][$whse]['TOTRESERVEDQTY'], $round, true);
            $whseMap[$tItemid][$whse]['TOTALLOCATEDQTY'] = ibcadd($trans['ALLOCATEDQTY'], $whseMap[$tItemid][$whse]['TOTALLOCATEDQTY'], $round, true);

            $itemMap[$tItemid]['TOTONORDERQTY'] = ibcadd($trans['ONORDERQTY'], $itemMap[$tItemid]['TOTONORDERQTY'], $round, true);
            $itemMap[$tItemid]['TOTINTRANSITQTY'] = ibcadd($trans['INTRANSITQTY'], $itemMap[$tItemid]['TOTINTRANSITQTY'], $round, true);
            $itemMap[$tItemid]['TOTONHANDQTY'] = ibcadd($trans['ONHANDQTY'], $itemMap[$tItemid]['TOTONHANDQTY'], $round, true);
            $itemMap[$tItemid]['TOTONHOLDQTY'] = ibcadd($trans['ONHOLDQTY'], $itemMap[$tItemid]['TOTONHOLDQTY'], $round, true);
            $itemMap[$tItemid]['TOTRESERVEDQTY'] = ibcadd($trans['RESERVEDQTY'], $itemMap[$tItemid]['TOTRESERVEDQTY'], $round, true);
            $itemMap[$tItemid]['TOTALLOCATEDQTY'] = ibcadd($trans['ALLOCATEDQTY'], $itemMap[$tItemid]['TOTALLOCATEDQTY'], $round, true);

            $whseMap[$tItemid][$whse]['TRANS'][] = $trans;

        }

        foreach ($whseMap as $itemkey => $item) {
            $itemwhses = array();
            foreach ($item as $whse) {
                $itemwhses[] = $whse;
            }
            $itemMap[$itemkey]['WAREHOUSE'] = $itemwhses;
            $resMap['ITEMS'][] = $itemMap[$itemkey];
        }

        if (count($resMap) == 0) {
            $resMap['NODATA'][0] = array('NODATA' => '1');
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $resMap);

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        $colspanHeaderPDFFirstRow = 6;
        $colspanHeaderPDFThirdRow = 4;
        $colspanTotalPDF = 6;
        $addnlColumns = 0;
        $lines['report'][0]['INCLUDEINTRANSIT'] = 0;
        $lines['report'][0]['INCLUDERESERVED'] = 0;
        $lines['report'][0]['INCLUDEALLOCATED'] = 0;

        if ($this->params['INCLUDEINTRANSIT']=='true') {
            $lines['report'][0]['INCLUDEINTRANSIT'] = 1;
            $addnlColumns += 1;
        }
        if ($this->params['INCLUDERESERVED']=='true') {
            $lines['report'][0]['INCLUDERESERVED'] = 1;
            $addnlColumns += 1;
        }
        if ($this->params['INCLUDEALLOCATED']=='true') {
            $lines['report'][0]['INCLUDEALLOCATED'] = 1;
            $addnlColumns += 1;
        }
        $lines['report'][0]['ADDNLCOLUMNS'] = $addnlColumns;
        $lines['report'][0]['COLSPANHEADERPDFFIRSTROW'] = $colspanHeaderPDFFirstRow + $addnlColumns;
        $lines['report'][0]['COLSPANHEADERPDFTHIRDROW'] = $colspanHeaderPDFThirdRow - $addnlColumns;
        $lines['report'][0]['COLSPANTOTALPDF'] = $colspanTotalPDF - $addnlColumns;

        return $lines;
    }

    /**
     * @param bool $defaultUom
     *
     * @return array
     */
    function GetUOMCache($defaultUom = false)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');

        $itemArray = array();
        foreach ($this->_begbalance as $val1) {
            array_push($itemArray, $val1['ITEMKEY']);
        }
        foreach ($this->_activity as $val2) {
            array_push($itemArray, $val2['ITEMKEY']);
        }
        $itemArray = array_unique($itemArray);

        if ($defaultUom) {
            $uomCache = $itemMgr->GetDefaultUOMInfoCache($itemArray, true, true);
        } else {
            $uomCache = $itemMgr->GetUOMInfoCache($itemArray, true, true);
        }
        return $uomCache;

    }

    /**
     * @return bool
     */
    public function canSaveReportPref()
    {
        $cansave = true;
        $drillfilter = Request::$r->_drillfilter;
        if ( isset($drillfilter) && $drillfilter == '1' ) {
            // incase of drilldown, we should not save the preference on the fly.
            $cansave = false;
        }
        return $cansave;
    }

}
