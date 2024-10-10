<?
import('InventoryReporter');
define('DEFAULT_INVPRECISION', 2);

/**
 * Class ItemCogsReport
 */
class ItemCogsReport extends InventoryReporter
{
    /**
     * @var array $_linecogs
     */
    var $_linecogs = array();

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
                'report' => 'itemcogs',
                'ops'    => array(
                                            'inv/lists/item/view',
                                            'inv/lists/warehouse/view',
                                            'inv/lists/invdocument/view',
                                            'so/lists/sodocument/view',
                                            'po/lists/podocument/view',
                                        ),
                '2stage'    => true,
                        )
            )
        );
    }

    /**
     * @return bool
     */
    function DoQuery()
    {
        global $_userid;
        list( , $cny) = explode('@', $_userid);

        //validate report
        $this->ValidateReport();

        // reload after the validate report
        $params = $this->params['safe'];

        // Note: sometimes dates are not passed in, as in the case of
        //       the 'Cost' report from a sales invoice window.  See ticket
        //       98876: "Cost link in sales invoice does not fetch any data"

        $dt1                    = $params['dt1'] ?: '';
        $dt2                    = $params['dt2'] ?: '';
        $skipDates              = (($dt1 == '') || ($dt2 == ''));

        $fromwarehouseid        = $params['FROMWAREHOUSEID'];
        $towarehouseid            = $params['TOWAREHOUSEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $fromdocid                = $params['FROMDOCID'];
        $todocid                = $params['TODOCID'];
        $this->prodlineid			= $params['PRODLINEID'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];

        if ($fromwarehouseid == '0' || $towarehouseid == '0') {
            $whseClause = ' or de.warehousekey is null';
        }

        if ($fromdocid == '0' || $todocid == '0') {
            $docClause = ' or dh.docid is not null';
        }
        /*
         * Prepare the Product Line QRY string to use it to filter items by product line info
         */
        if ($this->prodlineid != '%') {
            $this->prepareProductLineMapQry($this->prodlineid,'icitem');
        }

        $DocEntryLocationFilter = $this->_getLocationClause($params, 'de');
        $DocEntryDeptFilter = $this->_getDeptClause($params, 'de');

        // following 'sql' is a querystmt place holder
        $costargs = array('sql', $cny,$cny,$cny,$cny,$cny,);

        if ( $ReportOn == 'UPC') {
            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues, 6);
                // itemupcargs will be blank in case of include/excludes operator
                array_push($costargs, $itemupcargs, '');

            } else {
                $filterItemorUPC = " icitem.upc  >= :6 and icitem.upc  <= :7 ";
                array_push($costargs, $fromupc, $toupc);
            }
        }else {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues, 6);
                // itemupcargs will be blank in case of include/excludes operator
                array_push($costargs, $itemupcargs, '');

            } else {
                $filterItemorUPC = " icitem.itemid  >= :6 and icitem.itemid  <= :7 ";
                array_push($costargs, $fromitemid, $toitemid);
            }
        }

        /*
        The main query to fetch the records for sales document from docentrycost table. This maps the sales document to the correspoding purchase document from where the cost for each line item is picked
        */
        $dateWhere = $skipDates ? '' : "dh.whencreated >= to_date(:16, 'mm/dd/yyyy') and dh.whencreated <= to_date(:17, 'mm/dd/yyyy') and";
        /** @noinspection PhpUndefinedVariableInspection */
        $costqry = "select dh.docid, dh.whencreated, de.lineno +1 lineno, dc.itemkey, item2.name , sum(dc.quantity) as quantity, sum(dc.cost) as cost, dp.docid parentid, dc.costmethod,
		dp.plineno, dp.pcost, de.warehousekey,dr.sale_pur_trans as transactionmodule, dp.sale_pur_trans as ptransactionmodule, dc.in_out, dh.melocationkey DOCOWNERLOC, 
		dp.PARENTDOCOWNERLOC, item2.locationkey ITOWNERLOC
        from
            dochdrmst dh, docentrymst de, icitemmst icitem , docentrycost dc, docparmst dr, icitemmst item2,
            (
            select dh.docid, de.lineno +1 as plineno, dc.itemkey , case when dc.quantity >0  then dc.cost / dc.quantity else 0 end  pcost , dc.record# , 
            dc.sale_pur_trans, dh.melocationkey PARENTDOCOWNERLOC
        from
            dochdrmst dh, docentrymst de , docentrycost dc -- , docparmst dr
        where
            dh.cny# = :1 and
            de.cny#= :2 and
            dc.cny# = :3 and
            -- dr.cny# = :4 and
            -- dr.record# = dh.docparkey and
            dh.record# = de.dochdrkey(+) and
	    dh.state NOT IN ('I','S','A', 'X', 'R') and
            de.record# = dc. docentrykey(+) and
            ((dc.in_out = 'I') or (dc.sale_pur_trans = 'S')) and
            dc.affects_inventory in ('V', 'QV') and
            dc.systemgenerated <> 'T' -- and
		    -- dc.costmethod in ('L','F')
            ) dp
        where
            {$this->prodlineChildMapQry}
            dh.cny# = :5 and $filterItemorUPC and
            de.cny#= :8 and
            dc.cny# = :9 and
            dr.cny# = :10 and
            icitem.cny# = :11 and
			item2.cny# = :11 and
            dr.record# = dh.DOCPARKEY and 
            dh.record# = de.dochdrkey(+) and
	    dh.state NOT IN ('I','S','A', 'X', 'R') and
            de.record# = dc. docentrykey(+) and
			de.itemkey = icitem.ITEMID and
            dc.itemkey = item2.ITEMID and
            ((dc.in_out = 'O') or (dc.sale_pur_trans = 'S')) and
            dc.affects_inventory in ('V', 'QV') and
            dc.systemgenerated <> 'T' and
			(de.warehousekey between :12 and :13 $whseClause) and
			(dh.docid between :14 and :15 $docClause) and
			$dateWhere
            dc.docentrycostkey = dp.record#(+) $DocEntryLocationFilter $DocEntryDeptFilter
            
        group by 
        dh.docid, dh.whencreated,de.lineno , dc.itemkey, item2.name , dp.docid , dc.costmethod,
		dp.plineno, dp.pcost, de.warehousekey,dr.sale_pur_trans, dp.sale_pur_trans, dc.in_out, dh.melocationkey, item2.locationkey,dp.PARENTDOCOWNERLOC 
        order by dh.whencreated,dh.docid, de.lineno 
		";

        array_push($costargs, $cny, $cny, $cny, $cny, $fromwarehouseid, $towarehouseid, $fromdocid, $todocid);
        if ( ! $skipDates) {
            $costargs[] = $dt1;
            $costargs[] = $dt2;
        }
        $costargs[0] = $costqry;
        $this->_linecogs = QueryResult($costargs);
        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $lineMap = $this->_linecogs;

        //setting the initial values
        $totalqty = 0;
        $totalcost = 0;
        $totalpcost = 0;

        //defining the arrays to be used in the for loop
        $docarr = array();

        //variable to hold document id for last line, used for comparision
        $PreDocNo = '';
        $trans = array();
        $lineqty = 0 ;
        $linecost = 0 ;
        $linepcost = 0 ;

        //variable used to show/hide the unit cost totals
        //$IsLifoFifo = false;

        //starting the for loop for all the docentrycost record found by the query
        foreach ( $lineMap as $lineval) {

            //resetting the variables for each document, if last document is not same as current one
            if($PreDocNo != $lineval['DOCID']) {
                $trans = array();
                $lineqty = 0 ;
                $linecost = 0 ;
                $linepcost = 0 ;

                //				if($IsLifoFifo == false){
                //					unset($docarr[$PreDocNo]['TPCOST']);
                //				}
                //				$IsLifoFifo = false;
            }

            $itemID = $lineval['ITEMKEY'];
            $lineval['ITEMKEY'] =  $itemID;
            $lineval['ITEMHREF'] = "javascript:drilldown(0,'$itemID', '$lineval[ITOWNERLOC]');";

            //$lineval['PITEMKEY'] = $lineval['ITEMKEY'];
            //$lineval['PITEMHREF'] = $lineval['ITEMHREF'];

            // if a sale return, make things negative
            $negatePCost = false;
            if (($lineval['IN_OUT']=='I') && ($lineval['TRANSACTIONMODULE']=='S')) {
                $lineval['COST']     = - ($lineval['COST'] ?? 0);
                $lineval['QUANTITY'] = - ($lineval['QUANTITY'] ?? 0);
                //$lineval['PCOST']    = - ($lineval['PCOST'] ?? 0);
                $negatePCost = true;
            }

            $lineval['COST'] = iround($lineval['COST'], 2);
            //$lineval['PCOST'] = iround($lineval['PCOST'], 2);

            $Docid = urlencode(addslashes($lineval['PARENTID']));

            //drill down for source docid column
            if($lineval['PTRANSACTIONMODULE']=='I') {
                $lineval['PARENTHREF'] = "javascript:drilldown(2,'$Docid', '$lineval[PARENTDOCOWNERLOC]');";
            }elseif($lineval['PTRANSACTIONMODULE']=='S') {
                $lineval['PARENTHREF'] = "javascript:drilldown(3,'$Docid', '$lineval[PARENTDOCOWNERLOC]');";
            }elseif($lineval['PTRANSACTIONMODULE']=='P') {
                $lineval['PARENTHREF'] = "javascript:drilldown(4,'$Docid', '$lineval[PARENTDOCOWNERLOC]');";
            }

            //changing the cost method for db to UI representation
            if($lineval['COSTMETHOD'] == 'A') {
                $lineval['COSTMETHOD'] = 'IA.AVERAGE';
                unset($lineval['PARENTID'], $lineval['PLINENO']);
                //unset($lineval['PITEMKEY']);
            }elseif($lineval['COSTMETHOD'] == 'S') {
                $lineval['COSTMETHOD'] = 'IA.STANDARD';
                unset($lineval['PARENTID'], $lineval['PLINENO']);
                //unset($lineval['PITEMKEY']);
            }elseif($lineval['COSTMETHOD'] == 'L') {
                $lineval['COSTMETHOD'] = 'IA.LIFO';
                //$IsLifoFifo = true;   //used for show/hide of unit cost total
            }elseif($lineval['COSTMETHOD'] == 'F') {
                $lineval['COSTMETHOD'] = 'IA.FIFO';
                //$IsLifoFifo = true;   //used for show/hide of unit cost total
            }
            $lineval['PCOST'] = ibcdiv($lineval['COST'], $lineval['QUANTITY'], 2, true);
            if ($negatePCost) {
                $lineval['PCOST'] = - $lineval['PCOST'];    // aready computed above, but then wiped out just above here....
            }
            //add the current line to common array for each document
            $trans[] = $lineval;

            //save the documnet id, used for compairing old and new document
            $PreDocNo = $lineval['DOCID'];

            $docarr[$lineval['DOCID']]['DOCID']=$lineval['DOCID'];
            $docarr[$lineval['DOCID']]['WHENCREATED'] = FormatDateForDisplay($lineval['WHENCREATED']);
            $docarr[$lineval['DOCID']]['ASOFDATE']   = FormatDateForDisplay($lineval['ASOFDATE']);
            $docarr[$lineval['DOCID']]['STARTDATE']   = FormatDateForDisplay($lineval['START_DATE']);
            $docarr[$lineval['DOCID']]['ENDDATE']     = FormatDateForDisplay($lineval['END_DATE']);
            $Docid = urlencode(addslashes($lineval['DOCID']));

            //drill down for document id column
            if($lineval['TRANSACTIONMODULE']=='I') {
                $docarr[$lineval['DOCID']]['DOCHREF'] = "javascript:drilldown(2,'$Docid', '$lineval[DOCOWNERLOC]');";
            }elseif($lineval['TRANSACTIONMODULE']=='S') {
                $docarr[$lineval['DOCID']]['DOCHREF'] = "javascript:drilldown(3,'$Docid', '$lineval[DOCOWNERLOC]');";
            }elseif($lineval['TRANSACTIONMODULE']=='P') {
                $docarr[$lineval['DOCID']]['DOCHREF'] = "javascript:drilldown(4,'$Docid', '$lineval[DOCOWNERLOC]');";
            }

            //line totals
            $lineqty = ibcadd($lineqty, $lineval['QUANTITY'], 2, true);
            $linecost = ibcadd($linecost, $lineval['COST'], 2, true);
            $linepcost = ibcadd($linepcost, $lineval['PCOST'], 2, true);

            //maps to subtotals for quantity, cost and unit cost columns
            $docarr[$lineval['DOCID']]['TQTY'] = iround($lineqty, 2);
            $docarr[$lineval['DOCID']]['TCOST'] = iround($linecost, 2);
            $docarr[$lineval['DOCID']]['TPCOST'] = iround($linepcost, 2);

            //add array to common array for each document
            $docarr[$lineval['DOCID']]['DETAILS']=$trans;

            $totalqty = ibcadd($totalqty, $lineval['QUANTITY'], 2, true);
            $totalcost = ibcadd($totalcost, $lineval['COST'], 2, true);
            $totalpcost = ibcadd($totalpcost, $lineval['PCOST'], 2, true);
        }

        // to remove the unit cost total from the last line
        //		if($IsLifoFifo == false){
        //			unset($docarr[$PreDocNo]['TPCOST']);
        //		}
        $finalarr = array_values($docarr);

        if (count($finalarr)==0) {
            $finalarr['NODATA'][0]= array('NODATA'=>'1');
        }else{
            //grand totals maps to quantity, cost and unit cost columns
            $finalarr['TOTALS'][0]['GRANDTOTALQTY'] = iround($totalqty, 2);
            $finalarr['TOTALS'][0]['GRANDTOTALCOST'] = iround($totalcost, 2);
            $finalarr['TOTALS'][0]['GRANDTOTALPCOST'] = iround($totalpcost, 2);
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $finalarr);

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        return $lines;
    }

}
