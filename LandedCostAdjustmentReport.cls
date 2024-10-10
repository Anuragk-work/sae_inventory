<?
/**
 * =============================================================================
 *
 * @file    LandedCostAdjustmentReport.cls
 * @author    Shone Chacko
 * @description   LandedCostAdjustment Reporter class
 *
 * @copyright (C)2000,2009 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

import('InventoryReporter');

/**
 * Class LandedCostAdjustment
 */
class LandedCostAdjustmentReport extends InventoryReporter
{
    /**
     * @var array $_activity
     */
    var $_landedcostadjustment = array();

    /**
     * @param array $params
     */
    function __construct($params)
    {

        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                    'report' => 'landedcostadjustment',
                    'ops' => array(
                        'inv/lists/item/view',
                        'inv/lists/warehouse/view',
                        'inv/lists/invdocument/view',
                        'so/lists/sodocument/view',
                        'po/lists/podocument/view',
                        'so/lists/customer/view',
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
        $cny = GetMyCompany();

        $this->ValidateReport();

        // reload after the validate report
        $params = $this->params['safe'];

        $vardt1 = Request::$r->START_DATE;
        $vardt2 = Request::$r->END_DATE;

        $fromwarehouseid = $params['FROMWAREHOUSEID'];
        $towarehouseid = $params['TOWAREHOUSEID'];
        $fromitemid = $params['FROMITEMID'];
        $toitemid = $params['TOITEMID'];

        $ReportOn = $this->params['REPORTON'];
        $fromupc = $params['FROMUPC'];
        $toupc = $params['TOUPC'];
        $ItemOperator = $this->params['ITEMOPERATOR'];
        $itemValues = $this->params['ITEMVALUES'];
        $UPCOperator = $this->params['UPCOPERATOR'];
        $upcValues = $this->params['UPCVALUES'];
        $includeAll = $this->params['INCLUDEALL'];


        if (isset($vardt1) && $vardt1 != '') {
            $params['dt1'] = $vardt1;
        }
        $dt1 = $params['dt1'];

        if (isset($vardt2) && $vardt2 != '') {
            $params['dt2'] = $vardt2;
        }
        $dt2 = $params['dt2'];


        $locationFilter = $this->_getLocationClause($params, 'de');
        $deptFilter = $this->_getDeptClause($params, 'de');

        $dt1 = ($dt1 == '' ? GetCompanyOpenDate() : $dt1);

        // following 'sql' is a querystmt place holder
        $reportArgs = array('sql', $cny,);

        if ($ReportOn == 'ITEMID') {
            if ($fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'it', 'itemid', $itemValues, 2);
                array_push($reportArgs, $itemupcargs, '');
            } else {
                $filterItemorUPC = " it.itemid  >= :2 and it.itemid  <= :3 ";
                array_push($reportArgs, $fromitemid, $toitemid);
            }
        } else {
            if ($fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'it', 'upc', $upcValues, 2);
                array_push($reportArgs, $itemupcargs, '');
            } else {
                $filterItemorUPC = " nvl(it.upc, 'XXXX')  >= :2 and nvl(it.upc, 'XXXX')  <= :3 ";
                array_push($reportArgs, $fromupc, $toupc);
            }
        }
        $docparID = InvDocumentManager::LANDEDCOSTDOCTYPE;

        $havingClause = '';
        if ($includeAll == 'false') {
            $havingClause = " having degl.amount != round(sum(dc.cost),2) ";
        }
        $reportQry =
            "select dh.docid docid, de.itemkey, de.warehousekey, it.upc, round(sum(dc.cost),2) as amount,
                    degl.amount degl_amount, dc.sale_pur_trans as transactionmodule, c.customerid, g.entry_date, 
                    g.tr_type, a.acct_no, d.dept_no, l.location_no
            from
                    dochdrmst dh, docentry de, docentrycost dc, deglresolve degl, icitemmst it, customermst c, glentrymst g, 
                    baseaccountmst a, departmentmst d, locationmst l 
            where 
                    dh.cny# = :1 and de.cny# = :1 and dh.record# = de.dochdrkey 
                    and dc.cny# = :1  and dc.docentrykey = de.record# 
                    and degl.cny# = :1 and degl.docentrykey = dc.docentrykey 
                    and it.cny# = :1 and it.itemid  = de.itemkey
                    and c.cny# = :1 and c.entity = dh.entity
                    and de.warehousekey between :4 and :5 
                    and g.entry_date >= to_date(:6, 'MM/DD/YYYY') and g.entry_date <= to_date(:7, 'MM/DD/YYYY') 
                    and g.cny# = :1 and g.record# = degl.glentrykey
                    and a.cny# = :1 and a.record# = g.account#
                    and l.cny# (+)= :1 and l.record# (+)= g.location#
                    and d.cny# (+)= :1 and d.record# (+)= g.dept# and 
                    $filterItemorUPC  $locationFilter $deptFilter
                    and exists
                      (select 1 from docentrycost dc2, docentrymst de2, docentrymst de3, dochdrmst dh3, docparmst dp 
                      WHERE 
                        dc2.cny# = :1 and  dc2.record# = dc.docentrycostkey
                        and de2.cny# = :1 and de2.record# = dc2.docentrykey 
                        and de3.cny# = :1 and de3.adjdocentrykey = de2.record# 
                        and dh3.cny# = :1 and dh3.record# = de3.dochdrkey 
                        and dp.cny# = :1 and dp.record# = dh3.docparkey 
                        and dp.docid  = '$docparID'
                    )
            group by 
                      dh.docid, de.itemkey, de.warehousekey, it.upc, degl.amount, dc.sale_pur_trans, 
                     c.customerid, g.entry_date, g.tr_type, a.acct_no, d.dept_no, l.location_no
                     $havingClause
            order by g.entry_date, dh.docid, de.itemkey, g.tr_type";

        array_push($reportArgs, $fromwarehouseid, $towarehouseid, $dt1, $dt2);

        $reportArgs[0] = $reportQry;
        $this->_landedcostadjustment = QueryResult($reportArgs);

        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $resMap = array();

        foreach ($this->_landedcostadjustment as $trans) {
            $tItemid = $trans['ITEMKEY'];
            $whse = ($trans['WAREHOUSEKEY']) ?: '-';

            $itemEnc = urlencode(addslashes($tItemid));
            $trans['ITEMHREF'] = "javascript:drilldown(0,'$itemEnc', '$trans[ITOWNERLOC]');";
            $trans['ITEM'] = ($this->params['REPORTON']) == 'ITEMID' ? $tItemid : $trans['UPC'];

            $trans['WHSEHREF'] = "javascript:drilldown(1,'" . urlencode($whse) . "', '$trans[WHOWNERLOC]');";

            if ($trans['TRANSACTIONMODULE'] == 'I') {
                $trans['HREF'] = "javascript:drilldown(2,'" . urlencode($trans['DOCID']) . "', '$trans[DOCOWNERLOC]');";
            } elseif ($trans['TRANSACTIONMODULE'] == 'S') {
                $trans['HREF'] = "javascript:drilldown(3,'" . urlencode($trans['DOCID']) . "', '$trans[DOCOWNERLOC]');";
            } elseif ($trans['TRANSACTIONMODULE'] == 'P') {
                $trans['HREF'] = "javascript:drilldown(4,'" . urlencode($trans['DOCID']) . "', '$trans[DOCOWNERLOC]');";
            }
            $trans['CUSTHREF'] = "javascript:drilldown(5,'" . urlencode($trans['CUSTOMERID']) . "', '$trans[CUSTOWNERLOC]');";

            $trans['DOCID'] = (isset($trans['DOCOWNERLOC'])) ? $trans['DOCID'] . ' - ' . $trans['DOCOWNERLOC'] : $trans['DOCID'];
            $trans['ENTRY_DATE'] = FormatDateForDisplay($trans['ENTRY_DATE']);

            $trans['DIFFERENCE'] = ibcsub($trans['AMOUNT'], $trans['DEGL_AMOUNT'], 2);

            if ($trans['TR_TYPE'] == 1) {
                $trans['DEBIT'] = $trans['DIFFERENCE'];
                $trans['CREDIT'] = '0.00';
            } else {
                $trans['CREDIT'] = $trans['DIFFERENCE'];
                $trans['DEBIT'] = '0.00';
            }

            $resMap['TRANS'][] = $trans;

        }


        if (count($resMap) == 0) {
            $resMap['NODATA'][0] = array('NODATA' => '1');
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $resMap);

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];
        //eppp_p($lines);
        return $lines;
    }

}
