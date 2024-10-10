<?php
import('InventoryReporter');

/**
 * Class PhysicalInventoryReport
 */
class PhysicalInventoryReport extends InventoryReporter
{
    /** @var int $serialTrackingOp */
    private $serialTrackingOp = 0;

    /** @var int $lotTrackingOp */
    private $lotTrackingOp = 0;

    /** @var bool $simpleReport is this report simple enough to optimize the XSL? */
    private $simpleReport = false;

    /** @var string $XSLReplacementText what text are we generating to speed up the XSL? */
    public static $XSLReplacementText;

    /** @var int $detailsCountLastPass how many detail records did the PREVIOUS pass have? */
    private $detailsCountLastPass = 0;

    /** @var string $columnConcatinationString */
    private $columnConcatinationString = '-&-';


    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                    'report' => 'physicalinventory',
                    'ops'    => array(
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
        self::$XSLReplacementText = '';
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

        $this->serialTrackingOp = GetOperationId("inv/reports/serialtracking");
        $this->lotTrackingOp = GetOperationId("inv/reports/lottracking");

        list(, $cny) = explode('@', $_userid);
        $this->ValidateReport();
        $params = $this->params['safe'];
        $prodlineid = $params['PRODLINEID'];
        $fromitemid = $params['FROMITEMID'];
        $toitemid = $params['TOITEMID'];
        $fromwarehouseid = $params['FROMWAREHOUSEID'];
        $towarehouseid = $params['TOWAREHOUSEID'];
        $hideqty = $this->params['SHOWZERO'];
        $asofDate = '';
        if ($this->params['ASOFDATE'] && SysDateCompare($this->params['ASOFDATE'], GetCurrentDate())) {
            $asofDate = $this->params['ASOFDATE'];
        }
        $includeInactiveWhse = $params['INCLUDE_INACTIVE_WHSE'];
        $ReportOn = $this->params['REPORTON'];
        $fromupc = $params['FROMUPC'];
        $toupc = $params['TOUPC'];
        $ItemOperator = $this->params['ITEMOPERATOR'];
        $itemValues = $this->params['ITEMVALUES'];
        $UPCOperator = $this->params['UPCOPERATOR'];
        $upcValues = $this->params['UPCVALUES'];
        $WhseOperator = $this->params['WHSEOPERATOR'];
        $whseValues = $this->params['WHSEVALUES'];
        $args = array('sql', $cny, '', '', '', '', '', '');

        // If we have been given a prodlineid, then include that in the query.  We don't do a like, because that will exclude
        // items that have no product line
        $prodlineqry = '';
        if ($prodlineid != '%') {

            $bindIndex = ':5';
            $prodlineqry
                = " ip.productlineid in ( select productlineid from icprodline where cny# = ip.cny# 
                start with cny# = ip.cny# and productlineid= $bindIndex
                connect by cny# = ip.cny# and parentlineid = PRIOR productlineid) and ";
            $args[5] = isl_trim($prodlineid);
        }

        if ($params['SUMMARYMODE'] == 'Summary by warehouse') {
            $params['REPORTGROUPINGS'] = 'Warehouse';
            $this->params["safe"]['REPORTGROUPINGS'] = 'Warehouse';
        }

        $headercol = "item.itemid";    // to avoid inspection errors and in case none were set
        if ($params['REPORTGROUPINGS'] == 'Item ID') {
            $headercol = "item.itemid";
        } elseif ($params['REPORTGROUPINGS'] == 'Warehouse') {
            $headercol = "icwarehouse.NAME warehouse";
        }

        switch ($params['REPORTGROUPINGS']) {
            case 'Item ID':
                //$headercol = ($this->params['REPORTON'] == 'ITEMID') ? "item.itemid itemid" : "item.upc itemid";
                $headercol = "item.itemid, item.upc";
                break;
            case 'Warehouse':
                $headercol = "icwarehouse.location_no warehouse";
                break;
            case 'Serial Number':
                $headercol = "doccost.serialno";
                break;
            case 'Lot Number':
                $headercol = "doccost.lotno";
                break;
            case 'Zone':
                $headercol = "whsezone.zoneid";
                break;
            case 'Aisle':
                $headercol = "whseaisle.aisleid";
                break;
            case 'Row':
                $headercol = "whserow.rowkey";
                break;
            case 'Bin':
                $headercol = "whsebin.binid";
                break;
            default:
                dieFL('Critical Error in Physical Inventory Report');
                break;
        }

        $filterItemorUPCforDocentrycost = '';
        $filterItemorUPCforDocentrycostkits = '';
        if ($ReportOn == 'ITEMID') {
            if ($fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'item', 'itemid', $itemValues, 2);
                $this->GetFilterArgs(
                    $filterItemorUPCforDocentrycost, $itemupcargs, $ItemOperator, 'docentrycost', 'itemkey',
                    $itemValues, 2
                );
                $this->GetFilterArgs(
                    $filterItemorUPCforDocentrycostkits, $itemupcargs, $ItemOperator, 'docentrycostkits', 'itemkey',
                    $itemValues, 2
                );

                $args[2] = $itemupcargs;
            } else {
                $filterItemorUPC = " item.itemid  >= :2 and item.itemid  <= :3 ";
                $filterItemorUPCforDocentrycost = " docentrycost.itemkey >= :2 and docentrycost.itemkey <= :3 ";
                $filterItemorUPCforDocentrycostkits
                    = " docentrycostkits.itemkey >= :2 and docentrycostkits.itemkey <= :3 ";
                //array_push($args, $fromitemid, $toitemid);
                $args[2] = $fromitemid;
                $args[3] = $toitemid;
            }
            $filterItemorUPCforDocentrycost = $filterItemorUPCforDocentrycost != '' ? ' AND '
                . $filterItemorUPCforDocentrycost : '';
            $filterItemorUPCforDocentrycostkits = $filterItemorUPCforDocentrycostkits != '' ? ' AND '
                . $filterItemorUPCforDocentrycostkits : '';
        } else {

            if ($fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'item', 'upc', $upcValues, 2);
                $args[2] = $itemupcargs;
            } else {
                $filterItemorUPC = " item.upc  >= :2 and item.upc  <= :3 ";
                $args[2] = $fromupc;
                $args[3] = $toupc;
            }
        }
        if ($fromwarehouseid == VARCHAR2_MIN && $towarehouseid == VARCHAR2_MAX && $whseValues != '') {
            $this->GetFilterArgs($filterWhse, $whseargs, $WhseOperator, 'docentry', 'warehousekey', $whseValues, 6);
            $args[6] = $whseargs;
        } else {
            $filterWhse = " docentry.warehousekey between :6 and :7 ";
            $args[6] = $fromwarehouseid;
            $args[7] = $towarehouseid;

        }
        $icwarehouseclause = '';
        if ($includeInactiveWhse == 'false') {
            $icwarehouseclause = "icwarehouse.status = 'T' and";
        }
        $selectfield = "item.itemid, item.upc";

        $asofdateclause = '';
        $salesdetailsstr = '';
        if (isset($asofDate) && $asofDate != '') {

            $asofdateclause = "and docentry.whencreated <= to_date(:4, 'mm/dd/yyyy')";
            $args[4] = $asofDate;

            $salesdetailsstr
                = ", (SELECT SUM(so.quantity) quantity, so.cny#,
                                so.docentrycostkey
                                FROM
                                    (SELECT SUM (docentrycost.quantity) quantity, docentrycost.cny#,
                                      docentrycost.docentrycostkey
                                    FROM docentrycost
                                      WHERE docentrycost.cny#             = :1
                                     $filterItemorUPCforDocentrycost
                                    AND docentrycost.in_out             = 'O'
                                    And Docentrycost.Docentrycostkey   Is Not Null
                                    AND ((docentrycost.affects_inventory = 'QV') 
                                            or  ((docentrycost.affects_inventory = 'V') and (docentrycost.systemgenerated = 'T'))  )
                                    AND EXISTS
                                      (select 1 from docentry de, dochdrmst dh
										where
										de.cny#=docentrycost.cny#
										and de.record# = docentrycost.docentrykey
										and de.cny# = dh.cny#
										and de.dochdrkey = dh.record#
										and dh.whencreated <=TO_DATE (:4, 'mm/dd/yyyy')
                                      )
                                    GROUP BY docentrycost.cny#,docentrycost.docentrycostkey
                                    UNION ALL 
                                    SELECT SUM (docentrycostkits.quantity) quantity, docentrycostkits.cny#,
                                      docentrycostkits.docentrycostkey
                                    FROM docentrycostkits
                                       WHERE docentrycostkits.cny#             = :1
                                     $filterItemorUPCforDocentrycostkits
                                    AND docentrycostkits.in_out             = 'O'
                                    AND docentrycostkits.docentrycostkey   IS NOT NULL
                                    AND EXISTS
                                      (select 1
										from docentry de, dochdrmst dh
										where
										de.cny# = docentrycostkits.cny#
										and de.record# = docentrycostkits.docentrykey
										and de.cny# = dh.cny#
										and de.dochdrkey = dh.record#
										and dh.whencreated <= TO_DATE (:4, 'mm/dd/yyyy')
												  )
                                    AND docentrycostkits.record# NOT IN
                                      (SELECT docentrycostkits.docentrycostkey
                                        FROM docentrycostkits

                                        WHERE docentrycostkits.cny#             = :1
                                         $filterItemorUPCforDocentrycostkits
                                        AND docentrycostkits.in_out             = 'I'
                                        AND Docentrycostkits.Docentrycostkey   IS NOT NULL
                                        and exists (select 1
											from docentry de, dochdrmst dh
											where
											de.cny# = docentrycostkits.cny#
											and de.record# = docentrycostkits.docentrykey
											and de.cny# = dh.cny#
											and de.dochdrkey = dh.record#
											and dh.whencreated <= TO_DATE (:4, 'mm/dd/yyyy')
                                        )
                                    )
                                    GROUP BY docentrycostkits.cny#,docentrycostkits.docentrycostkey
                                    ) So
                                  GROUP BY so.cny#, so.docentrycostkey
                                  ) salesdetails";


        }

        $selectclause = 'select distinct ' . $headercol;
        // Note: ZONE does not fit yet, though we hope to add it 'soon'.  I've left breadcrumbs to put back ZONE when the time comes....
        $fromclause
            = " from icitem item,
                                     icprodline ip,
                                     docentrycost doccost,
                                     docentry,
                                     dochdrmst dochdr,
                                     docpar,
                                     icaisle whseaisle,
                                     icrow whserow,
                                     icbin whsebin,
									 icuomgrp,
									 icuom,
									 icwarehouse";
        // , iczone  whsezone

        if (BinManager::areAdvanedBinsOn()) {
            $binLinkage = "doccost.binkey=whsebin.record#(+) and 
                       whsebin.aislekey=whseaisle.record#(+) and 
                       whsebin.rowkey=whserow.record#(+) and ";
            // whsebin.zonekey=whsezone.record#(+) and doccost.cny#=whsezone.cny#(+) and ";
        } else {
            $binLinkage = "doccost.aislekey=whseaisle.record#(+) and
                        doccost.rowkey=whserow.record#(+) and
                        doccost.binkey=whsebin.record#(+) and ";
        }
        $whereclause
            = " where item.cny#=doccost.cny# and
                                     item.itemid=doccost.itemkey and
									  item.cny# = ip.cny#(+) and "
            . $prodlineqry .
            "item.productlinekey = ip.productlineid (+) and 	 
                					 item.cny#=icuomgrp.cny# and
									 item.uomgrpkey=icuomgrp.record# and 
									 icuomgrp.cny# = icuom.cny# and                         				
				                	 icuom.isbase = 'T' and
					                 icuom.grpkey = icuomgrp.record#  and
				                     item.itemtype in ('I','SK') and
                                     doccost.cny#=docentry.cny# and
                                     doccost.docentrykey=docentry.record# and
                                     docentry.cny#=dochdr.cny# and
                                     docentry.dochdrkey=dochdr.record# and
									 dochdr.cny#=docpar.cny# and
                                     dochdr.docparkey=docpar.record# and
                                     dochdr.state not in ('I','S','A', 'X', 'R') and
                                     docentry.cny#          =icwarehouse.cny# and
                                     docentry.warehousekey  =icwarehouse.location_no and
                                     $icwarehouseclause
                                     doccost.cny#=whseaisle.cny#(+) and
                                     doccost.cny#=whserow.cny#(+) and
                                     doccost.cny#=whsebin.cny#(+) and
                                     $binLinkage
                                     doccost.in_out = 'I' and
                                     ((doccost.affects_inventory = 'QV') 
                                        or  ((doccost.affects_inventory = 'V') and (doccost.systemgenerated = 'T'))  ) and
                                     doccost.cny# = :1 and
									$filterItemorUPC $asofdateclause and
				                    $filterWhse";

        if (isset($asofDate) && $asofDate != '') {
            $query = $selectclause . $fromclause . $salesdetailsstr . $whereclause
                . "and doccost.record# = salesdetails.docentrycostkey(+) and doccost.cny# = salesdetails.cny#(+) and
									(CASE
										WHEN salesdetails.quantity > 0
										THEN doccost.quantity - salesdetails.quantity
										WHEN salesdetails.quantity IS NULL
										THEN doccost.quantity
										ELSE doccost.quantity
								     END )!=0";
        } else {
            $query = $selectclause . $fromclause . $whereclause;
        }

        $args[0] = $query;
        $headerelement = QueryResult($args);

        $this->_headerstatus = $headerelement;


        if ($hideqty == 'true') {
            $Showqtyclause = ' ';
            $showSummaryQtyClause = '';
        } else {
            if (isset($asofDate) && $asofDate != '') {
                $Showqtyclause
                    = ' ,case when salesdetails.quantity > 0
												then doccost.quantity - salesdetails.quantity
                                            else 
												doccost.quantity
                                            end quantity';
            } else {
                $Showqtyclause = ' ,doccost.qtyleft quantity';
            }
            $showSummaryQtyClause = ' sum(quantity) quantity,';
        }

        $zoneSource = ""; // ( BinManager::areAdvanedBinsOn() ? "whsezone.zoneid as zoneid, " : "'' as zoneid, "); // in classic mode, no zone
        $zoneFrom = ""; // "iczone  whsezone,"
        $query = "select dochdr.docid, dochdr.melocationkey DOCOWNERLOC,
                                 $selectfield ,
                                 item.name,
                                 item.locationkey ITOWNERLOC,
                                 icw.locationkey WHOWNERLOC,
                                 icuom.UNIT,
                                 doccost.serialno,
                                 doccost.lotno,
                                 doccost.expirationdate,
                                 $zoneSource
                                 whseaisle.aisleid ,
                                 whserow.rowkey ,
                                 whsebin.binid
                                 " . $Showqtyclause . " ,
                                 docentry.warehousekey warehouse,
                                 docpar.sale_pur_trans as transactionmodule
                            from icitem item,
                                 icprodline ip,
                                 docentrycost doccost,
                                 docentry,
                                 dochdrmst dochdr,
                                 docpar,
                                 $zoneFrom
                                 icaisle whseaisle,
                                 icrow whserow,
                                 icbin whsebin,
                                 icuomgrp,
                                 icwarehouse icw,
                                 icuom $salesdetailsstr
                       where
                                 item.cny#=doccost.cny# and
                                 icw.cny#=doccost.cny# and
                                 icw.location_no=docentry.warehousekey and
                                 item.itemid=doccost.itemkey and
                                 item.cny#=icuomgrp.cny# and
                                 item.uomgrpkey=icuomgrp.record# and 
                                 icuomgrp.cny# = icuom.cny# and                                    
                                 icuom.isbase = 'T' and
                                 icuom.grpkey = icuomgrp.record#  and
                                 item.cny# = ip.cny#(+) and "
            . $prodlineqry .
            "item.productlinekey = ip.productlineid (+) and
                                 item.itemtype in ('I','SK') and
                                 ((doccost.affects_inventory = 'QV') 
                                    or ((doccost.affects_inventory = 'V') and (doccost.systemgenerated = 'T')) ) and
                                 doccost.cny#=docentry.cny# and
                                 doccost.docentrykey=docentry.record# and
                                 docentry.cny#=dochdr.cny# and
                                 docentry.dochdrkey=dochdr.record# and
                                 dochdr.cny#=docpar.cny# and
                                 dochdr.docparkey=docpar.record# and
                                 dochdr.state not in ('I','S','A', 'X', 'R') and
                                 doccost.cny#=whseaisle.cny#(+) and
                                 doccost.cny#=whserow.cny#(+) and
                                 doccost.cny#=whsebin.cny#(+) and
                                 $binLinkage
                                 doccost.in_out = 'I' and                               
                                doccost.cny# = :1  and
                                 $filterItemorUPC $asofdateclause and $filterWhse";

        if (isset($asofDate) && $asofDate != '') {
            $query
                .= "and doccost.record# = salesdetails.docentrycostkey(+) and doccost.cny# = salesdetails.cny#(+) and
									(CASE
										WHEN salesdetails.quantity > 0
										THEN doccost.quantity - salesdetails.quantity
										WHEN salesdetails.quantity IS NULL
										THEN doccost.quantity
										ELSE doccost.quantity
								     END )!=0";
        }

        $query .= " order by dochdr.record# ";

        if ($params['SUMMARYMODE'] == 'Summary by warehouse') {
            $prefix = "select itemid, upc, name, unit," . $showSummaryQtyClause . " warehouse from (";
            $suffix = ')group by itemid, upc, name, UNIT, warehouse order by itemid, upc';
            $query = $prefix . $query . $suffix;
        }
        $args[0] = $query;

        // if query is malformed QueryResult method is handling it and showing an error
        // so we dont need to add extra validation for query errors
        $itemdetails = QueryResult($args);
        if ($itemdetails === false) {
            return false;
        }

        // check if there are any orphaned Sales transactions
        if (Util::countOrZero($itemdetails) > 0) {
            $this->checkForNegativeQuantitySalesInvoice($itemdetails, $prodlineqry, $binLinkage, $asofdateclause, $filterItemorUPC, $filterWhse, $args);
        }
        $this->_status = $itemdetails;
        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $itemsMap = array();
        $i = 0;
        $Grandtotal = 0;
        $totals = array();
        $params = $this->params['safe'];
        $hideqty = $this->params['SHOWZERO'];
        $headercol = "";

        switch ($params['REPORTGROUPINGS']) {
            case 'Item ID':
                $headercol = "ITEMID";
                //$headercol = ($this->params['REPORTON'] == 'ITEMID') ? "ITEMID" : "UPC";
                break;
            case 'Warehouse':
                $headercol = "WAREHOUSE";
                break;
            case 'Serial Number':
                $headercol = "SERIALNO";
                break;
            case 'Lot Number':
                $headercol = "LOTNO";
                break;
            case 'Zone':
                $headercol = "ZONEID";
                break;
            case 'Aisle':
                $headercol = "AISLEID";
                break;
            case 'Row':
                $headercol = "ROWKEY";
                break;
            case 'Bin':
                $headercol = "BINID";
                break;
            default:
                dieFL('Critical Error in Physical Inventory Report');
                break;
        }

        $uomPref = INVSetupManager::getUOMPreference();
        if ($uomPref) {
            $defaultUOMCache = $this->GetUOMCache();
        }

        // Index the status array for speed
        $statusForHeaderCol = [];
        foreach ($this->_status as $detailrow) {
            $statusForHeaderCol[$detailrow[$headercol]][] = $detailrow;
        }

        // Is this a 'simple' report?  I.e. simple to generate?
        // if so, we generate the table of warehouses and details here in PHP
        // and not in XSL, which save a HUGE amount of time.....
        $this->simpleReport = (($headercol === 'WAREHOUSE')                                 // GROUP BY WAREHOUSE
                           && ($hideqty !== 'true')                                         // DO NOT HIDE QUANTITIES
                           && ($this->params['SUMMARYMODE'] !== 'Summary by warehouse') );  // DETAIL MODE

        foreach ($this->_headerstatus as $row) {
            $newrow = array();
            $newrow['GRPID'] = $row[$headercol];
            $newrow['GRPNAME'] = $headercol;

            if ($headercol == 'ITEMID' || $headercol == 'UPC') {
                $headercol = 'ITEMID';
                $newrow['GRPID'] = ($this->params['REPORTON'] == 'ITEMID') ? $row['ITEMID'] : $row['UPC'];
                //$newrow['GRPNAME'] = ($this->params['REPORTON'] == 'ITEMID') ? 'Item Id' : 'UPC';
                $newrow['GRPHREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($row['ITEMID'])) . "');";
            } elseif ($headercol == 'WAREHOUSE') {
                $newrow['GRPHREF'] = "javascript:drilldown(1,'" . urlencode(addslashes($row[$headercol])) . "');";
            }

            $qty = 0;
            // look only at the status records with this row's headercol
            if (isset($statusForHeaderCol[$row[$headercol]])) {
                foreach ($statusForHeaderCol[$row[$headercol]] as $detailrow) {
                    $detailrow['EXPIRATIONDATE'] = FormatDateForDisplay($detailrow['EXPIRATIONDATE']);
                    $itemid = $detailrow['ITEMID'];
                    $newrow['NAME'] = $detailrow['NAME'];

                    $detailrow['ITEMID'] = $this->params['REPORTON'] == 'ITEMID' ? $itemid : $detailrow['UPC'];
                    $detailrow['ITEMHREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($itemid)) . "', '$detailrow[ITOWNERLOC]');";

                    $detailrow['WHSEHREF'] = "javascript:drilldown(1,'" . urlencode(addslashes($detailrow['WAREHOUSE'])) . "', '$detailrow[WHOWNERLOC]');";

                    if ($detailrow['TRANSACTIONMODULE'] == 'I') {
                        $detailrow['DOCHREF'] = "javascript:drilldown(2,'" . urlencode($detailrow['DOCID']) ."', '$detailrow[DOCOWNERLOC]');";
                    } elseif ($detailrow['TRANSACTIONMODULE'] == 'S') {
                        $detailrow['DOCHREF'] = "javascript:drilldown(3,'" . urlencode($detailrow['DOCID']) ."', '$detailrow[DOCOWNERLOC]');";
                    } elseif ($detailrow['TRANSACTIONMODULE'] == 'P') {
                        $detailrow['DOCHREF'] = "javascript:drilldown(4,'" . urlencode($detailrow['DOCID']) ."', '$detailrow[DOCOWNERLOC]');";
                    }

                    $detailrow['SERIALHREF'] = $this->BuildSerialTrackingURL($detailrow['SERIALNO'], $detailrow['WAREHOUSE']);

                    $detailrow['LOTHREF'] = $this->BuildlotTrackingURL($detailrow['LOTNO'], $detailrow['WAREHOUSE']);

                    if ($hideqty != 'true') {
                        //$detailrow['QUANTITY'] = bcdiv($detailrow['QUANTITY'],1,2);
                        if ($uomPref) {
                            /** @noinspection PhpUndefinedVariableInspection */
                            $uomInfo = $defaultUOMCache[$itemid];
                            $detailrow['UNIT'] = $uomInfo['UNIT'];
                            $detailrow['QUANTITY'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $detailrow['QUANTITY']);
                        }
                        $qty = ibcadd($detailrow['QUANTITY'], $qty, 4);
                    }
                    $newrow['DETAILS'][] = $detailrow;
                }
            }
            $newrow['TOTALS'][0]['QUANTITY'] = $qty;
            $Grandtotal = ibcadd($Grandtotal, $qty, 4);
            if ($hideqty == 'true') {
                $newrow['TOTALS'][0]['HIDEQTY'] = 'T';
            } else {
                $newrow['TOTALS'][0]['HIDEQTY'] = 'F';
            }

            if ($this->simpleReport) {
                $this->generateXmlForSimpleReport($newrow);
            } else {
                $itemsMap[$i] = $newrow;
            }
            $i++;
        }

        if ($this->params['SUMMARYMODE'] == 'Summary by warehouse') {
            $wh = [];
            foreach ($itemsMap as $key => $row) {
                $wh[$key] = $row['GRPID'];
            }
            if (count($wh) > 0) {
                array_multisort($wh, SORT_ASC, $itemsMap);
            }
        }

        if ($i == 0) {
            $itemsMap['NODATA'][0] = array('NODATA' => '1');
        } else {
            // if this is a simple report, 'ALL_ITEMS' will trigger the replacement text
            if ($this->simpleReport) {
                $allItems = [];
                $allItems['GRPNAME'] = $headercol;  // this makes the header work
                $allItems['ALL_ITEMS'][0]['GRPNAME'] = $headercol;
                $itemsMap[] = $allItems;
            }
            $newGtotal['GRANDTOTAL'][0]['QUANTITY'] = $Grandtotal;
            if ($hideqty == 'true') {
                $newGtotal['GRANDTOTAL'][0]['HIDEQTY'] = 'T';
            } else {
                $newGtotal['GRANDTOTAL'][0]['HIDEQTY'] = 'F';
            }
            $itemsMap[] = $newGtotal;
        }

        $lines = $this->InvCommonHeader();
        $lines['report'][0]['REPORTON'] = ($this->params['REPORTON'] == 'ITEMID') ? 'ITEMID' : 'UPC';
        $lines['report'][0]['MODE'] = ($this->params['SUMMARYMODE'] == 'Summary by warehouse') ? 'SUMMARY' : 'DETAIL';

        if ($hideqty == 'true') {
            $lines['report'][0]['HIDEQTY'] = 'T';
        } else {
            $lines['report'][0]['HIDEQTY'] = 'F';
        }
        $lines = $this->DrawHeader($lines);
        $lines = $this->InvCommonBody($lines, $itemsMap);
        $lines = $this->InvCommonTotals($lines, $totals);

        return $lines;
    }

    /**
     * @return array
     */
    function GetUOMCache(){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');

        $itemArray = array();
        foreach ($this->_status as $val1) {
            array_push($itemArray,$val1['ITEMID']);
        }
        $itemArray = array_unique($itemArray);
        $defaultUOMCache = $itemMgr->GetDefaultUOMInfoCache($itemArray, true, true);

        return $defaultUOMCache;
    }

    /**
     * @param string $serial
     * @param string $whse
     *
     * @return string
     */
    function BuildSerialTrackingURL($serial, $whse = '')
    {

        $op = $this->serialTrackingOp; // GetOperationId("inv/reports/serialtracking");

        $serial = urlencode(urlencode(addslashes($serial)));
        $whse = urlencode($whse);

        $url = "reporteditor.phtml?.type=_html&amp;.op=$op" .
            "&amp;FROMSERIAL=$serial&amp;TOSERIAL=$serial" .
            "&amp;FROMWAREHOUSEID=$whse&amp;TOWAREHOUSEID=$whse" .
            "&amp;";

        return "javascript:DoDrill('$url',true);";
    }

    /**
     * @param string $lot
     * @param string $whse
     *
     * @return string
     */
    function BuildlotTrackingURL($lot, $whse = '')
    {

        $op = $this->lotTrackingOp; // GetOperationId("inv/reports/lottracking");

        $lot = urlencode(urlencode(addslashes($lot)));
        $whse = urlencode($whse);

        $url = "reporteditor.phtml?.type=_html&amp;.op=$op" .
            "&amp;FROMLOT=$lot&amp;TOLOT=$lot" .
            "&amp;FROMWAREHOUSEID=$whse&amp;TOWAREHOUSEID=$whse" .
            "&amp;";

        return "javascript:DoDrill('$url',true);";
    }

    /**
     * @return bool
     */
    function ValidateReport()
    {
        // we don't require a date, so don't verify the dates
        $this->ParamTweaks();
        return true;
    }

    /**
     * @return bool
     */
    function ParamTweaks()
    {
        parent::ParamTweaks();
        $params = $this->params;
        $p['INCLUDE_INACTIVE_WHSE'] = $params['INCLUDE_INACTIVE_WHSE'] ? isl_trim(isl_htmlspecialchars($params['INCLUDE_INACTIVE_WHSE'])) : 'false';
        if (HasErrors()) {
            if (Globals::$g->gErr->ErrorCount) {
                return false;
            }
        }
        $params['safe'] = INTACCTarray_merge($this->params['safe'], $p);
        $this->params = $params;

        return true;
    }

    /**
     * @param array $lines
     *
     * @return array
     */
    function DrawHeader($lines)
    {
        $dict = Dictionary::getInstance();
        $lines['report']["0"]['Aisle'] = $dict->GetRenamedText('Aisle');
        $lines['report']["0"]['Bin'] = $dict->GetRenamedText('Bin');
        $lines['report']["0"]['Row'] = $dict->GetRenamedText('Row');
        $lines['report']["0"]['Item'] = $dict->GetRenamedText('Item');
        $lines['report']["0"]['Warehouse'] = $dict->GetRenamedText('Warehouse');
        return $lines;
    }


    /**
     * First stage XSLT transformation parameters
     *
     * @return string[]|int[]
     */
    function GetFirstStageXSLTParams()
    {
        $params = parent::GetFirstStageXSLTParams();
        $params['supportsPHPCode'] =
            "physInventoryReport_ProcessNodes"; // function below that will take nodes and generate XML
        return $params;
    }



    /**
     *  up in DoMap(), we generated the data for one warehouse.  Here, we emit the resulting XML,
     *  AS IF the XSL did it.
     *
     *      **** DANGER *** This routine mimics what the xsl does in this limited case, and so
     *                      IF YOU CHANGE THE XSL, CHANGE THIS FILE, AND VICE VERSA
     *
     * @param array     $warehouse      The warehouse and all its details
     */
    private function generateXmlForSimpleReport($warehouse)
    {
        $generated = "";

        // The old emitted XSL looked like this:
        //  <ITEMS GRPID="ST_46954969" GRPNAME="WAREHOUSE" GRPHREF="javascript:drilldown(1,&apos;ST_46954969&apos;);" NAME="Breaker | Homeline 2 Pole 50A GFCI | HOM250GFI - I">
        //       <DETAILS DOCID="Receiver-ST_103100856" ITEMID="ST_103088447" UPC="" NAME="Breaker | Homeline 2 Pole 50A GFCI | HOM250GFI - I" UNIT="Each" SERIALNO="" LOTNO="" EXPIRATIONDATE="" AISLEID="" ROWKEY="" BINID="" QUANTITY="0" WAREHOUSE="ST_46954969" TRANSACTIONMODULE="P" SIMPLE="Y" ITEMHREF="javascript:drilldown(0,&apos;ST_103088447&apos;);" WHSEHREF="javascript:drilldown(1,&apos;ST_46954969&apos;);" DOCHREF="javascript:drilldown(4,&apos;Receiver-ST_103100856&apos;);" SERIALHREF="javascript:DoDrill(&apos;reporteditor.phtml?.type=_html&amp;amp;.op=2993&amp;amp;FROMSERIAL=&amp;amp;TOSERIAL=&amp;amp;FROMWAREHOUSEID=ST_46954969&amp;amp;TOWAREHOUSEID=ST_46954969&amp;amp;&apos;,true);" LOTHREF="javascript:DoDrill(&apos;reporteditor.phtml?.type=_html&amp;amp;.op=2995&amp;amp;FROMLOT=&amp;amp;TOLOT=&amp;amp;FROMWAREHOUSEID=ST_46954969&amp;amp;TOWAREHOUSEID=ST_46954969&amp;amp;&apos;,true);"/>
        //       <posibly more details records here>
        //       <TOTALS QUANTITY="0.0000" HIDEQTY="F"/>
        // </ITEMS>

        // and the ITEMS template just calls the DETAILS template, then optionally generates a blank line....

        $detailsCount = Util::countOrZero($warehouse['DETAILS']);

        // The ITEMS template says, at the end of each ITEMS entry,
        // "if count details > 1 OR count next entry's details > 1,
        //     then emit a newline".  At the bottom of this function
        // I check for count details > 1.  But I don't know the next
        // item's details count.  So, here, if THIS has >1 detail record
        // and the PRIOR entry had only 1, then emit a blank line.
        // what we DON'T want is two blank lines for the case of
        // details > 1 on two adjacent warehouses....
        if (($detailsCount > 1) && ($this->detailsCountLastPass === 1)) {
            $generated .= '<row><col> </col></row>';
        }

        // some helpful strings:
        $row12      = '<row s="12">';
        $row14      = '<row s="14">';
        $endRow     = '</row>';

        $col22      = '<col id="0" s="22"/>';   // this does not
        $col22Open  = '<col id="0" s="22" ';    // needs a > and an end col
        $col24      = '<col id="0" s="24"/>';   // this does not
        $col24Open  = '<col id="0" s="24" ';    // needs a > and an end col
        $col26Open  = '<col id="0" s="26" ';    // needs a > and an end col
        $col59      = '<col id="0" s="59">';    // needs an end col
        $col62      = '<col id="0" s="62">';    // note this needs an 'end col'
        $endCol     = '</col>';

        $grpId      = ($warehouse['GRPID']   != '') ? $warehouse['GRPID'] : _("None"); // TODO: IA.NONE for R4
        $grpHref    = ($warehouse['GRPHREF'] != '') ? ( 'href="' . $warehouse['GRPHREF'] . '"') : '';

        // For each detail record, emit the details.  urlencode has already been done on the hrefs.
        foreach ($warehouse['DETAILS'] as $detail) {
            // see the DETAILS section of the XSL for this:
            $body       = $col24Open . $grpHref . '>' . htmlspecialchars($grpId) . $endCol . ' '
                        . $col24Open . 'href="' . $detail['ITEMHREF'] . '">' . htmlspecialchars($detail['ITEMID']) . $endCol . ' '
                        . $col24Open . '>' . htmlspecialchars($detail['NAME']) . $endCol . ' '
                        . $col24Open . '>' . htmlspecialchars($detail['UNIT']) . $endCol . ' '
                        . $col24Open . 'href="' . $detail['DOCHREF'] . '">' . htmlspecialchars($detail['DOCID']) . $endCol . ' '
                        . $col22Open . '>' . urlencode($detail['QUANTITY']) . $endCol . ' '
                        . $col26Open . 'href="' . $detail['SERIALHREF'] . '">' . htmlspecialchars($detail['SERIALNO']) . $endCol . ' '
                        . $col26Open . 'href="' . $detail['LOTHREF'] . '">' . htmlspecialchars($detail['LOTNO']) . $endCol . ' '
                        . $col26Open . '>' . htmlspecialchars($detail['AISLEID']) . $endCol . ' '
                        . $col26Open . '>' . htmlspecialchars($detail['ROWKEY']) . $endCol . ' '
                        . $col26Open . '>' . htmlspecialchars($detail['BINID']) . $endCol . ' '
                        . $col24Open . '>' . htmlspecialchars($detail['EXPIRATIONDATE']) . $endCol . ' '
                        ;
             $generated .= "$row14 $body $endRow \n";
        }

        // if there is more than one detail record,
        // then emit a TOTALS record AND a blank line
        if ($detailsCount > 1) {
            $qty        = $warehouse['TOTALS'][0]['QUANTITY'] ?? 0;
            $qtyXml     = $col62 . $qty . $endCol;
            $subtotal   = 'IA.SUBTOTAL';
            $generated .= " $row12 $col24 $col24 $col24 $col24 $col59 $subtotal $endCol $qtyXml $col22 $col22 $col22 $col22 $col22 $col22 $endRow \n";

            // and a newline
            $generated .= '<row><col> </col></row>';
        }

        // add this row to the cumulative rowsbeing saved
        self::$XSLReplacementText  .= $generated;
        $this->detailsCountLastPass = $detailsCount;

    }


    /**
     *  Function will query Sales transactions that are effecting quantity on hand but dont have source docentrykey key and
     *  balance the $itemdetails quantity by looping through all the records.
     *
     *  This should fix the issue of credit notes (sales return) transactions having quantity left populated
     *  even in case of source incoming transactions are reversed or deleted.
     *
     * @param array  &$itemdetails Item details records that are
     * @param string $prodlineqry Productline query string
     * @param string $binLinkage binLinkage query string
     * @param string $asofdateclause As of date query string
     * @param string $filterItemorUPC filterItemorUPC query string
     * @param string $filterWhse filterWhse query string
     * @param array $args arguments to query
     */
    private function checkForNegativeQuantitySalesInvoice(&$itemdetails, $prodlineqry, $binLinkage, $asofdateclause, $filterItemorUPC, $filterWhse, $args)
    {
        $selectStrings = '(item.itemid || \'' . $this->columnConcatinationString . '\' ||
                                 item.upc || \'' . $this->columnConcatinationString . '\' ||
                                 icuom.UNIT || \'' . $this->columnConcatinationString . '\' ||
                                 doccost.serialno || \'' . $this->columnConcatinationString . '\'  ||
                                 doccost.lotno || \'' . $this->columnConcatinationString . '\'  ||
                                 doccost.expirationdate || \'' . $this->columnConcatinationString . '\' ||                               
                                 whseaisle.aisleid || \'' . $this->columnConcatinationString . '\'  ||
                                 whserow.rowkey || \'' . $this->columnConcatinationString . '\'  ||
                                 whsebin.binid || \'' . $this->columnConcatinationString . '\'  ||
                                 docentry.warehousekey) as ItemsRecord,';

        $queryQuantityNegativeSalesOrders = "select "
            . $selectStrings . "
                                 sum(doccost.quantity) quantity
                                 
                            from icitem item,
                                 icprodline ip,
                                 docentrycost doccost,
                                 docentry,
                                 dochdrmst dochdr,
                                 docpar,
                                 icaisle whseaisle,
                                 icrow whserow,
                                 icbin whsebin,
                                 icuomgrp,
                                 icuom
                       where
                                 item.cny#=doccost.cny# and
                                 item.itemid=doccost.itemkey and
                                 item.cny#=icuomgrp.cny# and
                                 item.uomgrpkey=icuomgrp.record# and 
                                 icuomgrp.cny# = icuom.cny# and                                    
                                 icuom.isbase = 'T' and
                                 icuom.grpkey = icuomgrp.record#  and
                                 item.cny# = ip.cny#(+) and "
            . $prodlineqry .
            "item.productlinekey = ip.productlineid (+) and
                                 item.itemtype in ('I','SK') and
                                 ((doccost.affects_inventory = 'QV') 
                                    or  ((doccost.affects_inventory = 'V') and (doccost.systemgenerated = 'T'))  ) and
                                 doccost.cny#=docentry.cny# and
                                 doccost.docentrykey=docentry.record# and
                                 docentry.cny#=dochdr.cny# and
                                 docentry.dochdrkey=dochdr.record# and
                                 dochdr.cny#=docpar.cny# and
                                 dochdr.docparkey=docpar.record# and
                                 dochdr.state not in ('I','S','A', 'X', 'R') and
                                 doccost.cny#=whseaisle.cny#(+) and
                                 doccost.cny#=whserow.cny#(+) and
                                 doccost.cny#=whsebin.cny#(+) and
                                 $binLinkage
                                 doccost.in_out = 'O' and
                                 docpar.sale_pur_trans = 'S' and                              
                                 doccost.cny# = :1  and
                                 doccost.Docentrycostkey IS NULL and 
                                 $filterItemorUPC $asofdateclause and $filterWhse 
                        GROUP BY item.itemid, 
                                 item.upc,
                                 icuom.UNIT,
                                 doccost.serialno,
                                 doccost.lotno,
                                 doccost.expirationdate,                                
                                 whseaisle.aisleid ,
                                 whserow.rowkey ,
                                 whsebin.binid,
                                 docentry.warehousekey";

        $args[0] = $queryQuantityNegativeSalesOrders;

        // if query is malformed QueryResult method is handling it and showing an error
        // so we dont need to add extra validation for query errors
        $salesOrderWithNegativeQuantity = QueryResult($args);

        //if there are sales invoices with docentrykeys null (i.e. -ve quantity sales orders)
        //loop all the entries and balance the quantity to fix the physical inventory quantity left for incoming transactions $itemdetails
        if (Util::countOrZero($salesOrderWithNegativeQuantity) > 0) {

            $itemWithTotalNegativeQuantity = [];
            foreach ($salesOrderWithNegativeQuantity as $orderWithNegativeQuantity) {
                $itemWithTotalNegativeQuantity [$orderWithNegativeQuantity['ITEMSRECORD']] = $orderWithNegativeQuantity['QUANTITY'];
            }

            if (Util::countOrZero($itemWithTotalNegativeQuantity) > 0) {
                for ($i = 0, $_i_ct = Util::countOrZero($itemdetails); $i < $_i_ct; $i++) {
                    // pairing the item, bin, warehouse, lot, row, aisle, serial mapping
                    $key = $itemdetails[$i]["ITEMID"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["UPC"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["UNIT"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["SERIALNO"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["LOTNO"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["EXPIRATIONDATE"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["AISLEID"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["ROWKEY"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["BINID"];
                    $key .= $this->columnConcatinationString . $itemdetails[$i]["WAREHOUSE"];

                    if ($itemdetails[$i]['QUANTITY'] > 0 &&
                        key_exists($key, $itemWithTotalNegativeQuantity) &&
                        $itemWithTotalNegativeQuantity[$key] > 0) {
                        if ($itemdetails[$i]['QUANTITY'] >= $itemWithTotalNegativeQuantity[$key]) {
                            $itemdetails[$i]['QUANTITY'] = $itemdetails[$i]['QUANTITY'] - $itemWithTotalNegativeQuantity[$key];
                            $itemWithTotalNegativeQuantity[$key] = 0;
                        } else {
                            $itemWithTotalNegativeQuantity[$key] = $itemWithTotalNegativeQuantity[$key] - $itemdetails[$i]['QUANTITY'];
                            $itemdetails[$i]['QUANTITY'] = 0;
                        }
                    }
                }
            }
        }

    }
}



/**
 *      Process nodes function, called by the xsl_interface, and used to greatly improve speed in the
 *  common case of:
 *  - DETAIL mode
 *  - Don't hide quantities
 *  - Group by WAREHOUSE
 *
 *      **** DANGER *** This routine mimics what the xsl does in this limited case, and so
 *                      IF YOU CHANGE THE XSL, CHANGE THIS FILE, AND VICE VERSA
 *
 *  NOTE: This function is global and not part of the above class....
 *
 * @param mixed    $xslpath
 * @param DOMXPath $xmlpath
 * @param string[] &$replaceList    this is what we return
 */
function physInventoryReport_ProcessNodes(/** @noinspection PhpUnusedParameterInspection */ $xslpath, $xmlpath, &$replaceList)
{
    // This text gets replaced in the finished XML with the contents of $rtn
    $replaceList['REPLACE_ALL_ITEMS_HERE'] = PhysicalInventoryReport::$XSLReplacementText;
}


