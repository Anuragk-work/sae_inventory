<?php
import('InventoryReporter');

/**
 * Class InvLocationReport
 */
class InvLocationReport extends InventoryReporter
{
    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                    'report' => 'invlocation',
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
    }


    /**
     * @return bool
     */
    function DoQuery()
    {
        global $_userid;

        list( , $cny) = explode('@', $_userid);
        $this->ValidateReport();
        $params = $this->params['safe'];
        $prodlineid = $params['PRODLINEID'];
        $fromitemid = $params['FROMITEMID'];
        $toitemid = $params['TOITEMID'];
        $fromwarehouseid = $params['FROMWAREHOUSEID'];
        $towarehouseid = $params['TOWAREHOUSEID'];
        $hideqty = $this->params['SHOWZERO'];
        $dt2 = $this->params['ASOFDATE'];  //As of date is considered as end date
        $gReport['ROUNDING'] = 'C';

        // If we have been given a prodlineid, then include that in the query.  We don't do a like, because that will exclude
        // items that have no product line
        if ($prodlineid != '%') {
            //Get all child productlines
            $bindIndex = (isset($dt2) && $dt2 != '') ? 7 : 6;
            $prodlineqry = " ip.productlineid in ( select productlineid from icprodline where cny# = ip.cny# 
                start with cny# = ip.cny# and productlineid= $bindIndex
                connect by cny# = ip.cny# and parentlineid = PRIOR productlineid) and ";
        }

        if ($params['REPORTGROUPINGS'] == 'Item ID') {
            $headercol = "item.itemid";
        } elseif ($params['REPORTGROUPINGS'] == 'Warehouse') {
            $headercol = "icwarehouse.NAME warehouse";
        } elseif ($params['REPORTGROUPINGS'] == 'Warehouse') {
            $headercol = "icwarehouse.NAME warehouse";
        } elseif ($params['REPORTGROUPINGS'] == 'Warehouse') {
            $headercol = "icwarehouse.NAME warehouse";
        }

        switch ($params['REPORTGROUPINGS']) {
            case 'Item ID':
                $headercol = "item.itemid";
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

        if (isset($dt2) && $dt2 != '') {
            $asofdateclause = "and docentry.whencreated <= to_date(:6, 'mm/dd/yyyy')";
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $query = "select distinct " . $headercol . "
		 from icitemmst item, icprodline ip,docentrycost doccost , docentry, dochdrmst dochdr, docparmst docpar, whseaisle, whserow, whsebin, icuom,icwarehouse ,docpartotals,ictotal
		 where
				 item.cny#=doccost.cny# and
				 item.itemid=doccost.itemkey and
				 item.cny# = ip.cny#(+) and "
                 . $prodlineqry .
                 "item.productlinekey = ip.productlineid (+) and
				 item.cny#=icuom.cny# and
				 item.std_uom=icuom.record# and	 
				 doccost.cny#=docentry.cny# and
				 doccost.docentrykey=docentry.record# and
				 docentry.cny#=dochdr.cny# and
				 docentry.dochdrkey=dochdr.record# and	
				 dochdr.cny#=docpar.cny# and
				 dochdr.docparkey=docpar.record# and	
				 docentry.cny#=icwarehouse.cny# and
				 docentry.warehousekey=icwarehouse.location_no and		 
				 doccost.cny#=whseaisle.cny#(+) and
				 doccost.aislekey=whseaisle.record#(+) and
				 doccost.cny#=whserow.cny#(+) and
				 doccost.rowkey=whserow.record#(+) and	 	
				 doccost.cny#=whsebin.cny#(+) and
				 doccost.binkey=whsebin.record#(+) and
				 docpar.in_out = 'I' and
				 doccost.qtyleft > 0 and
			     docpar.cny#=docpartotals.cny# and 
			     docpar.record# = docpartotals.docparkey and
			     docpartotals.cny#=ictotal.cny# and 
			     docpartotals.totalkey = ictotal.record#	and
			     ictotal.name ='ONHAND' and
				 doccost.cny# = :1 and
				 doccost.itemkey between :2 and :3 and
				 docentry.warehousekey between :4 and :5 $asofdateclause";

        //$args = array($query, $cny, $fromwarehouseid, $towarehouseid);
        if (isset($dt2) && $dt2 != '') {
            $args = array($query, $cny, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, $dt2);
        } else {
            $args = array($query, $cny, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid);
        }

        if ($prodlineid != '%') {
            $args[] = isl_trim($prodlineid);
        }

        $headerelement = QueryResult($args);

        $this->_headerstatus = $headerelement;

        if ($hideqty == 'true') {
            $Showqtyclause = ' ';
        } else {
            $Showqtyclause = ' ,doccost.qtyleft quantity';
        }

        $query = "select dochdr.docid,item.itemid,item.name,icuom.UNIT,doccost.serialno,doccost.lotno,whseaisle.aisleid ,
		whserow.rowkey ,whsebin.binid" . $Showqtyclause . " ,icwarehouse.location_no warehouse
		 from icitemmst item, icprodline ip,docentrycost doccost , docentry, dochdrmst dochdr, docparmst docpar, whseaisle, whserow, whsebin, icuom,icwarehouse  ,docpartotals,ictotal
		 where
				 item.cny#=doccost.cny# and
				 item.itemid=doccost.itemkey and
				 item.cny# = ip.cny#(+) and "
            . $prodlineqry .
            "item.productlinekey = ip.productlineid (+) and
				 item.cny#=icuom.cny# and
				 item.std_uom=icuom.record# and	 
				 doccost.cny#=docentry.cny# and
				 doccost.docentrykey=docentry.record# and
				 docentry.cny#=dochdr.cny# and
				 docentry.dochdrkey=dochdr.record# and	
				 dochdr.cny#=docpar.cny# and
				 dochdr.docparkey=docpar.record# and	
				 docentry.cny#=icwarehouse.cny# and
				 docentry.warehousekey=icwarehouse.location_no and		 
				 doccost.cny#=whseaisle.cny#(+) and
				 doccost.aislekey=whseaisle.record#(+) and
				 doccost.cny#=whserow.cny#(+) and
				 doccost.rowkey=whserow.record#(+) and	 	
				 doccost.cny#=whsebin.cny#(+) and
				 doccost.binkey=whsebin.record#(+) and
				 docpar.in_out = 'I' and
				 doccost.qtyleft > 0 and
				 docpar.cny#=docpartotals.cny# and 
				 docpar.record# = docpartotals.docparkey and
				 docpartotals.cny#=ictotal.cny# and 
				 docpartotals.totalkey = ictotal.record#	and
				 ictotal.name ='ONHAND' and
				 doccost.cny# = :1 and
				 doccost.itemkey between :2 and :3 and
				 docentry.warehousekey between :4 and :5 $asofdateclause";

        if (isset($dt2) && $dt2 != '') {
            $args = array($query, $cny, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, $dt2);
        } else {
            $args = array($query, $cny, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid);
        }

        if ($prodlineid != '%') {
            $args[] = isl_trim($prodlineid);
        }

        $itemdetails = QueryResult($args);

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
        $totals = array();
        $params = $this->params['safe'];
        $hideqty = $this->params['SHOWZERO'];

        if ($params['REPORTGROUPINGS'] == 'Item ID') {
            $headercol = "ITEMID";
        } elseif ($params['REPORTGROUPINGS'] == 'Warehouse') {
            $headercol = "WAREHOUSE";
        }

        switch ($params['REPORTGROUPINGS']) {
            case 'Item ID':
                $headercol = "ITEMID";
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

        foreach ($this->_headerstatus as $row) {
            $newrow = array();
            /** @noinspection PhpUndefinedVariableInspection */
            $newrow['GRPID'] = $row[$headercol];
            if ($headercol == 'ITEMID') {
                $newrow['GRPHREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($row[$headercol])) . "');";
            } elseif ($headercol == 'WAREHOUSE') {
                $newrow['GRPHREF'] = "javascript:drilldown(1,'" . urlencode(addslashes($row[$headercol])) . "');";
            }
            $newrow['GRPNAME'] = $headercol;
            $qty = 0;
            foreach ($this->_status as $detailrow) {
                if ($row[$headercol] == $detailrow[$headercol]) {
                    $detailrow['ITEMHREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($detailrow['ITEMID'])) . "');";

                    $detailrow['WHSEHREF'] = "javascript:drilldown(1,'" . urlencode(addslashes($detailrow['WAREHOUSE'])) . "');";

                    $detailrow['DOCHREF'] = "javascript:drilldown(4,'" . urlencode($detailrow['DOCID']) . "');";

                    $detailrow['SERIALHREF'] = $this->BuildSerialTrackingURL($detailrow['SERIALNO'], $detailrow['WAREHOUSE']);

                    $detailrow['LOTHREF'] = $this->BuildlotTrackingURL($detailrow['LOTNO'], $detailrow['WAREHOUSE']);

                    $detailrow['QUANTITY'] = bcdiv($detailrow['QUANTITY'], '1', 2);

                    $qty = bcadd($detailrow['QUANTITY'], $qty);

                    $newrow['DETAILS'][] = $detailrow;
                }
            }
            $newrow['TOTALS'][0]['QUANTITY'] = $qty;
            if ($hideqty == 'true') {
                $newrow['TOTALS'][0]['HIDEQTY'] = 'T';
            } else {
                $newrow['TOTALS'][0]['HIDEQTY'] = 'F';
            }
            $itemsMap[$i++] = $newrow;
        }

        if (count($itemsMap) == 0) {
            $itemsMap['NODATA'][0] = array('NODATA' => '1');
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $itemsMap);
        $lines = $this->InvCommonTotals($lines, $totals);

        return $lines;
    }

    /**
     * @param   string   $serial
     * @param   string   $whse
     *
     * @return string
     */
    function BuildSerialTrackingURL($serial, $whse = '')
    {

        $op = GetOperationId("inv/reports/serialtracking");

        $serial = urlencode(addslashes($serial));
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

        $op = GetOperationId("inv/reports/lottracking");

        $lot = urlencode(addslashes($lot));
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
}
