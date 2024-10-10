<?php
import('InventoryReporter');

/**
 * Class InvStatusReport
 */
class InvStatusReport extends InventoryReporter
{
    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array( 
                'report' => 'invstatus', 
                'ops'    => array(
                                'inv/lists/item/view',
                                'inv/lists/warehouse/view'
                                ),
                '2stage'    => true,
                ) 
            )
        );
        if(IsMCMESubscribed()) {
            $this->params['NOREPORTLOCCHECK'] = true;
        }
    }

    /**
     * @return bool
     */
    function DoQuery() 
    {
        $_userid = Globals::$g->_userid;

        list( , $cny) = explode('@', $_userid);
        $this->ValidateReport();
        $params = $this->params['safe'];
        $prodlineid = $params['PRODLINEID'];
        $fromitemid = $params['FROMITEMID'];
        $toitemid = $params['TOITEMID'];
        $fromwarehouseid = $params['FROMWAREHOUSEID'];
        $towarehouseid = $params['TOWAREHOUSEID'];
        $dt2 = $this->params['ASOFDATE'];  //As of date is considered as end date
        $gReport['ROUNDING'] = 'C';

        $ReportOn = $this->params['REPORTON'];
        $fromupc = $params['FROMUPC'];
        $toupc = $params['TOUPC'];
        $ItemOperator = $this->params['ITEMOPERATOR'];
        $itemValues = $this->params['ITEMVALUES'];
        $UPCOperator = $this->params['UPCOPERATOR'];
        $upcValues = $this->params['UPCVALUES'];

        // If we have been given a prodlineid, then include that in the query.  We don't do a like, because that will exclude
        // items that have no product line
        if ($prodlineid != '%') {
            if (isset($dt2) && $dt2 != '') {
                $prodlineqry = " ip.productlineid in ( select productlineid from icprodline where cny# = :1
                start with cny# = :1 and productlineid= :7
                connect by cny# = :1 and parentlineid = PRIOR productlineid) and ";
            } else {
                $prodlineqry = " ip.productlineid in ( select productlineid from icprodline where cny# = :1 
                start with cny# = :1 and productlineid= :6
                connect by cny# = :1 and parentlineid = PRIOR productlineid) and ";
            }
        }
        
        /*
         * The filters will only be added when an item or warehouse is provided respectively.
         * Else we need not have any query condition to use the min max limits when there are no filters available
         * Filter conditions like Item ID, UPC and Warehouse are handled here
         */
        if($ReportOn == 'UPC') {
            $from = $fromupc;
            $to = $toupc;
            $fld = 'upc';
            $values = $upcValues;
            $operator = $UPCOperator;
        } else {
            $from = $fromitemid;
            $to = $toitemid;
            $fld = 'itemid';
            $values = $itemValues;
            $operator = $ItemOperator;
        }
        
        $itemqry = '';
        if ($from == VARCHAR2_MIN && $to == VARCHAR2_MAX && $values != '') {
            $this->GetFilterArgs($itemqry, $itemupcargs, $operator, 'i', $fld, $values, 2);
            $from = $itemupcargs;
            $to = '';
            $itemqry .= ' AND ';
        } else {
            if (!empty($from) && $from != VARCHAR2_MIN) {
                $itemqry .= "i.{$fld} >= :2 AND ";
            }
            if (!empty($to) && $to != VARCHAR2_MAX) {
                $itemqry .= "i.{$fld} <= :3 AND ";
            }
        }
        
        $warehouseqry = '';
        if (!empty($fromwarehouseid) && $fromwarehouseid != VARCHAR2_MIN) {
            $warehouseqry .= "it.warehousekey >= :4 AND ";
        }
        if (!empty($towarehouseid) && $towarehouseid != VARCHAR2_MAX) {
            $warehouseqry .= "it.warehousekey <= :5 AND ";
        }
        
        // If AsOfDate is set then fetch the query based on date filter else fetch without date filters
        if (isset($dt2) && $dt2 != '') {
            $itemavail = "(SELECT it.cny#,
                it.itemkey,
                it.warehousekey,
                SUM(NVL(DECODE(ict.name,'ONORDER',NVL(it.quantity,0)),0)) AS qtyonorder,
                SUM(NVL(DECODE(ict.name,'ONHAND', NVL(it.quantity,0)),0)) AS qtyonhand,
                SUM(NVL(DECODE(ict.name,'ONHOLD', NVL(it.quantity,0)),0)) AS qtyonhold,
                SUM(NVL(DECODE(ict.name,'INTRANSIT', NVL(it.quantity,0)),0)) AS qtyintransit,
                SUM(NVL(DECODE(ict.name,'RESERVED', NVL(it.quantity,0)),0)) AS qtyreserved,
                SUM(NVL(DECODE(ict.name,'ALLOCATED', NVL(it.quantity,0)),0)) AS qtyallocated,
                i.name,
                i.productlinekey,
                i.upc,
                i.uomgrpkey    
              FROM icitemactivity it,
                ictotal ict,
                icitem i
              WHERE it.cny#       = :1
                AND ict.cny#         = :1
                AND it.totalkey     = ict.record#
                AND it.whencreated <= to_date(:6, 'mm/dd/yyyy')
                AND it.itemkey = i.itemid
                AND i.cny# = :1
                AND $itemqry $warehouseqry
                i.itemtype IN ('I','SK')
              GROUP BY it.cny#, it.itemkey, it.warehousekey, i.name, i.productlinekey, i.upc, i.uomgrpkey)";
        } else {
            $itemavail = "v_itemavail";
        }

        /*
          For All Non-Activity Items
          Their Ids Are Displayed With All The Active Warehouses With All Quantity As 0.
         */
        $allzeros = $params['WITH_NO_ACTIVITY'];

        /* When Checkbox With-No-Activity[x] is selected
          this query extracts the items which does not have any transctions
         */
        if ($allzeros == 'true') {
            /** @noinspection PhpUndefinedVariableInspection */
            $query1 = "SELECT  it.itemid,
                    i.name as item,
                    it.warehousekey,
                    uom.unit as uom_unit,
                    uom.numdec as uom_no,
                    ip.productlineid as selectprodlineid,
                    ip.description as selectprodlinedescription,
                    0 as qtyonorder,
                    0 as qtyonhand,
                    0 as qtyonhold,
                    0 as qtyintransit,
                    0 as qtyreserved,
                    0 as qtyallocated,
                    0 as qtyavailable, i.upc 
                FROM 
                    icitem i,
                    ( SELECT l.cny#,
                            l.itemid,
                            r.location_no AS warehousekey,
                            l.upc
                      FROM icitem l,
                            icwarehouse r
                      WHERE l.cny# =:1
                            AND l.cny#   =r.cny#
                            AND ( 
                                NOT EXISTS ( 
                                    SELECT 1 FROM icitemactivity WHERE cny#=:1 AND itemkey = l.itemid
                                )
                                OR NOT EXISTS (
                                    SELECT 1 FROM v_itemavail v
                                    WHERE v.itemkey   =l.itemid
                                    AND v.warehousekey=r.location_no
                                    AND v.cny#        = :1
                                ) 
                            )
                            ORDER BY itemid,
                            warehousekey
                            ) it,
                    icprodline ip, 
                    icuomgrp uomgrp, 
                    icuom uom 
                WHERE 
                    it.cny#=:1 and 
                    $itemqry
                    $warehouseqry
                    it.itemid = i.itemid and 
                    i.itemtype in ('I','SK') and
                    i.cny#= :1 and
                    ip.cny# (+) = :1 and 
                    " . $prodlineqry . "
                    i.productlinekey = ip.productlineid (+) and
                    uomgrp.cny# (+)  = :1 and
                    uomgrp.record# (+) = i.uomgrpkey and
                    uom.cny# (+) = :1 and
                    uom.grpkey (+) = uomgrp.record# and
                    uom.isbase (+) = 'T'";
        }

        $qtyAvalableFormula = $this->calculateAvailableQtystring();

        //This is executed when inv status report is called from avail link. 
        $kit = Request::$r->_KIT;
        if ($kit == 'T') {
            /* One query by UNION ALL
              this will take care of kit items, which does not have any transctions
             */

            //to get rid of that even number of quota character problem in parameters
            //better replace them with a format acceptable by oracle below function is created for this 
            $fromitemid = convertQuoteForQuery($fromitemid);

            /** @noinspection PhpUndefinedVariableInspection */
            $query = "SELECT it.itemkey, 
                    i.name as item,
                    it.warehousekey,
                    uom.unit as uom_unit,
                    uom.numdec as uom_no,
                    ip.productlineid as selectprodlineid,
                    ip.description as selectprodlinedescription,
                    it.qtyonorder,
                    it.qtyonhand,
                    it.qtyonhold,
                    it.qtyintransit,
                    it.qtyreserved,
                    it.qtyallocated,
                    $qtyAvalableFormula as qtyavailable, i.upc
                FROM icitem i, " . "$itemavail" . " it, icprodline ip, icuomgrp uomgrp, icuom uom
                WHERE
                    it.cny# = :1 and
                    it.itemkey in (" . $fromitemid . ") and
                    $warehouseqry
                    it.itemkey = i.itemid and
                    i.itemtype in ('I','SK') and
                    i.cny#	= :1 and
                    ip.cny# (+) = :1 and "
                     . $prodlineqry .
                     "i.productlinekey = ip.productlineid (+) and
                    uomgrp.cny# (+)  = :1 and
                    uomgrp.record# (+) = i.uomgrpkey and
                    uom.cny# (+) = :1 and
                    uom.grpkey (+) = uomgrp.record# and
                    uom.isbase (+) = 'T' "
                     . "\n UNION ALL \n"
                     . "SELECT  b.itemid,
                    a.name as item,
                    b.warehousekey,
                    uom.unit as uom_unit,
                    uom.numdec as uom_no,
                    ip.productlineid as selectprodlineid,
                    ip.description as selectprodlinedescription,
                    0 as qtyonorder,
                    0 as qtyonhand,
                    0 as qtyonhold,
                    0 as qtyintransit,
                    0 as qtyreserved,
                    0 as qtyallocated,
                    0 as qtyavailable, a.upc 
                FROM 
                    icitem a,
                    ( SELECT l.cny#,
                            l.itemid,
                            r.location_no AS warehousekey,
                            l.upc
                      FROM icitem l,
                            icwarehouse r
                      WHERE l.cny# =:1
                            AND r.cny# = :1
                            AND ( 
                                NOT EXISTS ( 
                                    SELECT 1 FROM icitemactivity WHERE cny#=:1 AND itemkey = l.itemid
                                )
                                OR NOT EXISTS (
                                    SELECT 1 FROM v_itemavail v
                                    WHERE v.itemkey   =l.itemid
                                    AND v.warehousekey=r.location_no
                                    AND v.cny#        = :1
                                ) 
                            )
                            AND l.itemid in (" . $fromitemid . ")
                            ORDER BY itemid,
                            warehousekey
                            ) b,
                    icprodline ip, 
                    icuomgrp uomgrp, 
                    icuom uom 
                WHERE 
                    b.cny#=:1 and 
                    b.itemid = a.itemid and 
                    a.itemtype in ('I','SK') and
                    a.cny#= :1 and
                    ip.cny# (+) = :1 and "
                     . $prodlineqry .
                     "a.productlinekey = ip.productlineid (+) and
                    uomgrp.cny# (+)  = :1 and
                    uomgrp.record# (+) = a.uomgrpkey and
                    uom.cny# (+) = :1 and
                    uom.grpkey (+) = uomgrp.record# and
                    uom.isbase (+) = 'T'";
            $args = array($query, $cny, $fromwarehouseid, $towarehouseid);
        } else {
            if (isset($dt2) && $dt2 != '') {
                $selectclause = "select it.itemkey, 
                    it.name as item ,
                    it.warehousekey,
                    uom.unit as uom_unit,
                    uom.numdec as uom_no,
                    ip.productlineid as selectprodlineid,
                    ip.description as selectprodlinedescription,
                    it.qtyonorder,
                    it.qtyonhand,
                    it.qtyonhold,
                    it.qtyintransit,
                    it.qtyreserved,
                    it.qtyallocated,
                    $qtyAvalableFormula as qtyavailable, it.upc ";
                $fromclause = "from " . "$itemavail" . " it, icprodline ip, icuomgrp uomgrp, icuom uom ";
                /** @noinspection PhpUndefinedVariableInspection */
                $whereclause = "where it.cny# = :1 and			
                    ip.cny# (+) = :1 and
                    " . $prodlineqry . "
                    it.productlinekey = ip.productlineid (+) and
                    uomgrp.cny#(+)  = :1 and
                    uomgrp.record# (+) = it.uomgrpkey and
                    uom.cny# (+) = :1 and
                    uom.grpkey (+) = uomgrp.record# and
                    uom.isbase (+) = 'T'";
            } else {
                $selectclause = "select it.itemkey,
                    i.name as item ,
                    it.warehousekey,
                    uom.unit as uom_unit,
                    uom.numdec as uom_no,
                    ip.productlineid as selectprodlineid,
                    ip.description as selectprodlinedescription,
                    it.qtyonorder,
                    it.qtyonhand,
                    it.qtyonhold,
                    it.qtyintransit,
                    it.qtyreserved,
                    it.qtyallocated,
                    $qtyAvalableFormula as qtyavailable, i.upc ";
                $fromclause = "from icitem i, " . "$itemavail" . " it, icprodline ip, icuomgrp uomgrp, icuom uom ";
                /** @noinspection PhpUndefinedVariableInspection */
                $whereclause = "where
                    it.cny# = :1 and
                    $itemqry $warehouseqry
                    it.itemkey = i.itemid and
                    i.itemtype in ('I','SK') and
                    i.cny#	= :1 and
                    ip.cny# (+) = :1 and "
                               . $prodlineqry .
                               "i.productlinekey = ip.productlineid (+) and
                    uomgrp.cny# (+)  = :1 and
                    uomgrp.record# (+) = i.uomgrpkey and
                    uom.cny# (+) = :1 and
                    uom.grpkey (+) = uomgrp.record# and
                    uom.isbase (+) = 'T' ";
            }

            $query = $selectclause . $fromclause . $whereclause;

            /* If  the Checkbox With-No-Activity[x]  is checked then the output of 
              both With-Activity and With-No-Activity will be merged.
             */
            if ($allzeros == 'true') {
                /** @noinspection PhpUndefinedVariableInspection */
                $final_query = $query . "\n UNION ALL \n " . $query1 . "\n order by 1,2,3";
            } else {
                $final_query = $query . "\n order by 1,2,3";
            }
            
            $query = $final_query;
            $args = array($query, $cny, $from, $to, $fromwarehouseid, $towarehouseid);
        }
        
        if (isset($dt2) && $dt2 != '') {
            $args[] = $dt2;
        }

        if ($prodlineid != '%') {
            $args[] = isl_trim($prodlineid);
        }
        $items = QueryResult($args);

        $this->_status = $items;
        return true;
    }


    // TODO: this function is duplicate. The same is defined in Reporter.cls
    // TODO: the call to this function in $this->>DoMap should be replaced with call to function in Reporter.cls
    // TODO: commenting for now
    /**
     * @param string $id
     * @param string $asofdate
     * @param string &$sdate
     * @param string &$edate
     */
    /**
    function GetStartAndEndDates($id, $asofdate, &$sdate, &$edate)
    {
        global $gManagerFactory,$gErr;
        $periodMgr =  $gManagerFactory->GetManager('reportingperiod');
        $period = $periodMgr->GetRaw($id);
        if (!count($period) || !isset($period[0])) {
            //ADD ERROR HERE
            epp("could not get raw reporting period");
        } else {
            GetReportingDateRange($period[0], $asofdate, $start, $end);
            $sdate  = $start;
            $edate  = $end;
        }
    }
*/

    /**
     * @return array
     */
    function DoMap()
    {
        $itemsMap = array();
        $i = 0;
        $totals = array();
        $params = $this->params['safe'];
        /*
        When checkbox With-No-Activity is checked, The the value of WITH_ACTIVITY parameter will be ignored,
        Otherwise the value of WITH_ACTIVITY parameter will be considered
        */
        $zeros=$params['WITH_NO_ACTIVITY'];
        if ($zeros == 'false') {            
            $zeros    = $params['WITH_ACTIVITY'];
        }


        //		$dt1					= $params['dt1'];
        // If AsOfDate is set then set end date to AsOfDate 
        if(isset($this->params['ASOFDATE'])) {
            GetStartAndEndDates('Current Month', $this->params['ASOFDATE'], $start, $end);
            $dt1 = $start;
            $dt2 = $this->params['ASOFDATE'];
        } else {
            $dt2 = $params['dt2'];
        }
        $gReport['ROUNDING']    = 'C';

        // find start date as first of the month based on AsOfDate
        //		$DateTmpl = new DateTemplates();
        //		$dates = $DateTmpl->GetDateRange(DATETMPL_CURRENTMONTH,$dt2);
        //		$date1=$dates[0];
        //		$startdate = FormatDateForDisplay($date1);
        //		$startdate = $date1;
        //		$dt1		= $startdate;
        $uomPref = INVSetupManager::getUOMPreference();
        if($uomPref) {
            $defaultUOMCache = $this->GetUOMCache(true);
        }

        foreach($this->_status as $row){
            if ($zeros == 'false' && $row['QTYONHAND'] == 0 && $row['QTYONORDER'] == 0 && $row['QTYONHOLD'] == 0
                && $row['QTYINTRANSIT'] == 0 && $row['QTYRESERVED'] == 0 && $row['QTYALLOCATED'] == 0) {
                continue;
            }
            $round = ($row['UOM_NO'] ?: 0);
            if( $round > 0 ) {
                $row['QTYONHAND']           = bcadd($row['QTYONHAND'], '0', $round);
                $row['QTYONORDER']          = bcadd($row['QTYONORDER'], '0', $round);
                $row['QTYONHOLD']           = bcadd($row['QTYONHOLD'], '0', $round);
                $row['QTYINTRANSIT']        = bcadd($row['QTYINTRANSIT'], '0', $round);
                $row['QTYRESERVED']         = bcadd($row['QTYRESERVED'], '0', $round);
                $row['QTYALLOCATED']        = bcadd($row['QTYALLOCATED'], '0', $round);
                $row['QTYAVAILABLE']        = bcadd($row['QTYAVAILABLE'], '0', $round);
            }
	    $item = $row['ITEMKEY'];
            if($uomPref) {
                /** @noinspection PhpUndefinedVariableInspection */
                $uomInfo = $defaultUOMCache[$item];
                $row['UOM_UNIT'] =  $uomInfo['UNIT'];
                $row['QTYONHAND'] = UOMManager::getQuantityByDefaultUOM($uomInfo,  $row['QTYONHAND']);
                $row['QTYONORDER'] = UOMManager::getQuantityByDefaultUOM($uomInfo,  $row['QTYONORDER']);
                $row['QTYONHOLD'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $row['QTYONHOLD']);
                $row['QTYINTRANSIT'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $row['QTYINTRANSIT']);
                $row['QTYRESERVED'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $row['QTYRESERVED']);
                $row['QTYALLOCATED'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $row['QTYALLOCATED']);
                $row['QTYAVAILABLE'] = UOMManager::getQuantityByDefaultUOM($uomInfo, $row['QTYAVAILABLE']);
            }
            $row['ITEM_DESCRIPTION'] = $row['ITEM'];
            $row['ITEMHREF']             = "javascript:drilldown(0,'" . urlencode(addslashes($row['ITEMKEY'])) . "');";
            $row['PRODLINE']             = $row['SELECTPRODLINEID'] . ($row['SELECTPRODLINEDESCRIPTION'] ? " - " : "") . $row['SELECTPRODLINEDESCRIPTION'];
            // Providing start and end dates for drilldown, existing bug
            if($this->params['REPORTON'] == 'UPC') {
                /** @noinspection PhpUndefinedVariableInspection */
                $row['QTYHREF'] = $this->BuildItemActivityURL($row['UPC'], $row['WAREHOUSEKEY'], $dt1, $dt2, '', 'UPC');
            }else{
                /** @noinspection PhpUndefinedVariableInspection */
                $row['QTYHREF'] = $this->BuildItemActivityURL($row['ITEMKEY'], $row['WAREHOUSEKEY'], $dt1, $dt2);
            }
            if ($row['WAREHOUSEKEY'] == '0') {
                $row['WAREHOUSEKEY'] = '-';
            }
            $itemsMap[$i++] = $row;
        }

        if (count($itemsMap)==0) {
            $itemsMap['NODATA'][0]= array('NODATA'=>'1');
        }
        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $itemsMap); 
        $lines = $this->InvCommonTotals($lines, $totals); 
        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        $addnlColumns = 0;
        $totalcolsize = 7;
        $prodLineSize = 25;

        if ($this->params['INCLUDEINTRANSIT'] =='true') {
            $lines['report'][0]['INCLUDEINTRANSIT'] = 1;
            $addnlColumns += 1;
        }
        if ($this->params['INCLUDERESERVED'] =='true') {
            $lines['report'][0]['INCLUDERESERVED'] = 1;
            $addnlColumns += 1;
        }
        if ($this->params['INCLUDEALLOCATED'] =='true') {
            $lines['report'][0]['INCLUDEALLOCATED'] = 1;
            $addnlColumns += 1;
        }
        if($addnlColumns > 0){
            $totalcolsize = 6;
            $tobetakenfromPL= ibcsub(ibcmul($addnlColumns , 6,0,1),4,0,1) ;
            $prodLineSize   = ibcsub($prodLineSize, $tobetakenfromPL,0,1);
        }

        $lines['report'][0]['productlinesize'] = $prodLineSize;
        $lines['report'][0]['totalcolsize'] = $totalcolsize;

        return $lines;
    }

    /**
     * @param bool $defaultUom
     *
     * @return array
     */
    function GetUOMCache($defaultUom=false){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr     = $gManagerFactory->getManager('item');

        $itemArray = array();
        foreach( $this->_status as $val1) {
            array_push($itemArray,$val1['ITEMKEY']);
        }
        $itemArray = array_unique($itemArray);
        if($defaultUom){
            $uomCache = $itemMgr->GetDefaultUOMInfoCache($itemArray, true, true);
        } else{
            $uomCache = $itemMgr->GetUOMInfoCache($itemArray, true, true);
        }
        return $uomCache;
    }

    /**
     * ValidateReport
     */
    function ValidateReport()
    {
        // we don't require a date, so don't verify the dates
        $this->ParamTweaks();
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
/**
 * @return string
 */
    protected function calculateAvailableQtystring()
    {
        global $kINVid;
        $includeIntransit = '';

        //if the preference is not set, then default is taken as false for INCLUDEONORDER
        $includeOrders = (GetPreferenceForProperty($kINVid, 'INCLUDEONORDER') === 'F') ? false : true;
        //if the preference is not set, then default is taken as false for INCLUDEINTRANSIT
        if($this->params['INCLUDEINTRANSIT']=='true'){
            $includeIntransit = (GetPreferenceForProperty($kINVid, 'INCLUDEINTRANSIT') == 'T') ? true : false;
        }
        $string = " (it.qtyonhand - it.qtyonhold ";

        if($includeOrders){
            $string .= " + it.qtyonorder " ;
        }
        if($includeIntransit){
            $string .= " + it.qtyintransit " ;
        }
        $string .= ") ";
        return $string;
    }
}


