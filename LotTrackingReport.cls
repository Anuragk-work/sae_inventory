<?php
import('InventoryReporter');
define('DEFAULT_INVPRECISION', 2);

class LotTrackingReport extends InventoryReporter
{
    /**
     * @var string[][]|false $_lotactivity
     */
    private $_lotactivity;

    /**
     * @var string[][]|false $_lothdr
     */
    private $_lothdr;

    /** @var string $prodlineid */
    protected $prodlineid = '';

    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array( 
                'report' => 'lottracking', 
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
     * Get additional filter to use based on table in question.
     *
     * @param string $table Table being queried
     *
     * @return string Additional filter to limit results
     */
    private static function getAdditionalFilter(string $table) : string
    {
        if ($table === 'docentrycost') {
            // Ignore adjustments while querying docentrycost
            return "{$table}.adjdocentrycostkey is null and";
        } else {
            return "";
        }
    }

    /**
     * Get lot subquery based on the specified table.
     *
     * @param string $table                  Table: should be one of 'docentrycost' or 'docentrycostkits'
     * @param string $zoneSelect             Zone select clause
     * @param string $zoneFrom               Zone from clause
     * @param string $zoneWhere              Zone where clause
     * @param string $prodlineChildMapQry    Product line filter specification
     * @param string $filterItemorUPC        Item/UPC filter
     * @param string $ictotalsLocationFilter Location filter
     * @param string $ictotalsDeptFilter     Department filter
     *
     * @return string Subquery for the given table
     */
    private static function getLotSubquery(string $table, string $zoneSelect, string $zoneFrom, string $zoneWhere,
                                           string $prodlineChildMapQry, string $filterItemorUPC,
                                           string $ictotalsLocationFilter, string $ictotalsDeptFilter):string
    {
        $lotSubQuery = "select
                    icitem.name, {$table}.serialno, dochdr.docid, dochdr.record# dochdr_recordno,
                    docentry.whencreated datein, {$table}.lotno, {$table}.whsekey, $zoneSelect
                    whseaisle.aisleid aislekey, whserow.rowkey, whsebin.binid binkey, {$table}.itemkey,
                    {$table}.quantity*decode({$table}.in_out, 'O', '-1', 'I', '1') raw_quantity,
                    {$table}.expirationdate, dochdr.melocationkey ownerloc, dr.sale_pur_trans as transactionmodule,
                    icitem.upc
                from 
                     {$table}, docentrymst docentry, dochdrmst dochdr, icaisle whseaisle, icrow whserow, icbin whsebin,
                     $zoneFrom icitem, docparmst dr
                where
                    {$table}.cny#=docentry.cny# and {$prodlineChildMapQry}
                    {$table}.docentrykey=docentry.record# and 
                    {$table}.cny#=dochdr.cny# and 
                    docentry.dochdrkey=dochdr.record#  and
                    {$table}.cny#=whsebin.cny#(+) and
                    {$table}.cny#=whseaisle.cny#(+) and
                    {$table}.cny#=whserow.cny#(+) and
                    $zoneWhere
                    {$table}.binkey=whsebin.record#(+) and 
                    whsebin.aislekey=whseaisle.record#(+) and 
                    whsebin.rowkey=whserow.record#(+) and 
                    {$table}.cny#=icitem.cny# and
                    {$table}.itemkey=icitem.itemid and 
                    {$table}.lotno is not null and
                    dochdr.docparkey=dr.record# and
                    dochdr.cny#=dr.cny# and
                    {$table}.cny#=:1 and 
                    {$table}.lotno between :2 and :3 and 
                    {$table}.whsekey between :4 and :5 and 
                    {$table}.affects_inventory in ('V', 'QV') and " .
                       self::getAdditionalFilter($table) .
                       " $filterItemorUPC $ictotalsLocationFilter $ictotalsDeptFilter";

        return $lotSubQuery;
    }

    /**
     * Get lot query: combines docentrycostkits with docentrycost in order to include lot tracked
     * components' consumption.
     *
     * @param string $zoneSelect             Zone select clause
     * @param string $zoneFrom               Zone from clause
     * @param string $zoneWhere              Zone where clause
     * @param string $prodlineChildMapQry    Product line filter specification
     * @param string $filterItemorUPC        Item/UPC filter
     * @param string $ictotalsLocationFilter Location filter
     * @param string $ictotalsDeptFilter     Department filter
     *
     * @return string
     */
    private static function getLotQuery(string $zoneSelect, string $zoneFrom, string $zoneWhere,
                                        string $prodlineChildMapQry, string $filterItemorUPC,
                                        string $ictotalsLocationFilter, string $ictotalsDeptFilter):string
    {
        $docCostSubQuery = self::getLotSubquery('docentrycost', $zoneSelect, $zoneFrom, $zoneWhere, $prodlineChildMapQry,
                                               $filterItemorUPC, $ictotalsLocationFilter, $ictotalsDeptFilter) ;
        $docCostKitsSubQuery = self::getLotSubquery('docentrycostkits', $zoneSelect, $zoneFrom, $zoneWhere, $prodlineChildMapQry,
                                                   $filterItemorUPC, $ictotalsLocationFilter, $ictotalsDeptFilter) ;
        $lotQuery = "select
                        name, serialno, docid, datein, lotno, whsekey, $zoneSelect aislekey, rowkey, binkey,
                        itemkey, sum(raw_quantity) quantity, expirationdate, ownerloc, transactionmodule, upc
                    from (  
                            $docCostSubQuery
                            union all 
                            $docCostKitsSubQuery
                     ) 
                    group by docid, dochdr_recordno, serialno, datein, lotno, whsekey, $zoneSelect aislekey, rowkey,
                        binkey, itemkey, expirationdate, ownerloc, transactionmodule, upc, name 
                    order by dochdr_recordno";

        return $lotQuery;
    }

    /**
     * Get lot total subquery based on the specified table.
     *
     * @param string $table                  Table: should be one of 'docentrycost' or 'docentrycostkits'
     * @param string $prodlineChildMapQry    Product line filter specification
     * @param string $filterItemorUPC        Item/UPC filter
     * @param string $ictotalsLocationFilter Location filter
     * @param string $ictotalsDeptFilter     Department filter
     *
     * @return string Lot total subquery for the specified table
     */
    private static function getLotTotalSubquery(string $table, string $prodlineChildMapQry, string $filterItemorUPC,
                                                string $ictotalsLocationFilter, string $ictotalsDeptFilter) : string
    {
        $lotTotalSubquery = "select {$table}.lotno,
                {$table}.quantity*decode({$table}.in_out, 'O', '-1', 'I', '1') raw_quantity_available
			from 
				{$table}, docentrymst docentry, dochdrmst dochdr, icitem
			where
				{$table}.cny#=docentry.cny# and {$prodlineChildMapQry}
				{$table}.docentrykey=docentry.record# and 
				docentry.cny#=dochdr.cny# and 
				docentry.dochdrkey=dochdr.record#  and
				{$table}.cny#=icitem.cny# and
				{$table}.itemkey=icitem.itemid and 				
				{$table}.lotno is not null and
				{$table}.cny#=:1 and 
				{$table}.lotno between :2 and :3 and 
				{$table}.whsekey between :4 and :5 and 
				{$table}.affects_inventory in ('V', 'QV') and " .
                            self::getAdditionalFilter($table) .
                            " $filterItemorUPC $ictotalsLocationFilter $ictotalsDeptFilter";

        return $lotTotalSubquery;
    }

    /**
     * Get lot total query: combines docentrycostkits with docentrycost in order to include lot tracked
     * components' consumption.
     * =
     *
     * @param string $prodlineChildMapQry    Product line filter specification
     * @param string $filterItemorUPC        Item/UPC filter
     * @param string $ictotalsLocationFilter Location filter
     * @param string $ictotalsDeptFilter     Department filter
     *
     * @return string
     */
    private static function getLotTotalQuery(string $prodlineChildMapQry, string $filterItemorUPC,
                                             string $ictotalsLocationFilter, string $ictotalsDeptFilter) : string
    {
        $docCostSubQuery = self::getLotTotalSubquery('docentrycost', $prodlineChildMapQry, $filterItemorUPC,
                                                   $ictotalsLocationFilter,
                                                   $ictotalsDeptFilter);
        $docCostKitsSubQuery = self::getLotTotalSubquery('docentrycostkits', $prodlineChildMapQry, $filterItemorUPC,
                                                        $ictotalsLocationFilter,
                                                        $ictotalsDeptFilter);
        $lotTotalQuery = "select 
                            lotno, sum(raw_quantity_available) quantity_available
                          from ( 
                                 $docCostSubQuery
                                 union all 
                                 $docCostKitsSubQuery
                            ) 
                          group by lotno 
                          order by lotno";

        return $lotTotalQuery;
    }

    /**
     * @return bool
     */
    public function DoQuery()
    {
        global $_userid;

        list( , $cny) = explode('@', $_userid);

        $this->ValidateReport();

        // reload after the validate report
        $params = $this->params['safe'];

        $fromwarehouseid        = $params['FROMWAREHOUSEID'];
        $towarehouseid            = $params['TOWAREHOUSEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        
        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];
        $this->prodlineid			= $params['PRODLINEID'];

        /*
         * Prepare the Product Line QRY string to use it to filter items by product line info
         */
        if ($this->prodlineid != '%') {
            $this->prepareProductLineMapQry($this->prodlineid,'icitem');
        }
        //		$varfromlot =Request::$r->FROMLOT;
        //		if(isset($varfromlot) && $varfromlot!=''){
        //			$this->params['FROMLOT']= $varfromlot;
        //		}
        $fromlot     = $this->params['FROMLOT'];
    
        //		$vartolot =Request::$r->TOLOT;
        //		if(isset($vartolot) && $vartolot!=''){
        //			$this->params['TOLOT']=$vartolot;
        //		}
        $tolot = $this->params['TOLOT'];

        $fromlot                = explode('--', $fromlot);
        $fromlot                = $fromlot[0];
        $fromlot        = $fromlot ? isl_trim(isl_htmlspecialchars($fromlot)) : VARCHAR2_MIN;
        $tolot                    = explode('--', $tolot);
        $tolot                = $tolot[0];
        $tolot            = $tolot ? isl_trim(isl_htmlspecialchars($tolot)) : VARCHAR2_MAX;

        $ictotalsLocationFilter = $this->_getLocationClause($params, 'docentry');
        $ictotalsDeptFilter = $this->_getDeptClause($params, 'docentry');

        $args = array('sql',$cny,$fromlot,$tolot,$fromwarehouseid,$towarehouseid,); 
        // 
        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues, 6);
                // itemupcargs will be blank in case of include/excludes operator
                if( $itemupcargs !='') {
                    array_push($args, $itemupcargs);
                }
            } else {
                $filterItemorUPC = " icitem.itemid  >= :6 and icitem.itemid  <= :7 ";
                array_push($args, $fromitemid, $toitemid);
            }
        }else {

            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues, 6);
                // itemupcargs will be blank in case of include/excludes operator
                if( $itemupcargs !='') {
                    array_push($args, $itemupcargs);
                }
            } else {
                $filterItemorUPC = " icitem.upc  >= :6 and icitem.upc  <= :7 ";
                array_push($args, $fromupc, $toupc);
            }
        }


        $lothdrqry = self::getLotTotalQuery($this->prodlineChildMapQry, $filterItemorUPC, $ictotalsLocationFilter,
                                            $ictotalsDeptFilter);

        $args[0] = $lothdrqry;
        $this->_lothdr = QueryResult($args);

        // 'Zone' should be here but causes the text to go off the end of the page :-(  So for now.....
        if (!BinManager::areClassicBinsOn()) { //advanced bins and no bins should be handled here
            $zoneSelect = ""; // "whsezone.zoneid, ";
            $zoneFrom   = ""; // "iczone whsezone,"
            $zoneWhere  = ""; // "docentrycost.cny#=whsezone.cny#(+) and whsebin.zonekey=whsezone.record#(+) and"
            $lotqry =
                self::getLotQuery($zoneSelect, $zoneFrom, $zoneWhere, $this->prodlineChildMapQry, $filterItemorUPC,
                                  $ictotalsLocationFilter, $ictotalsDeptFilter);
        } else {
            $zoneSelect = ""; // "'' as zoneid, ";
            $lotqry = "select icitem.name, docentrycost.serialno,dochdr.docid,docentry.whencreated datein ,docentrycost.lotno,docentrycost.whsekey,
                    $zoneSelect whseaisle.aisleid aislekey,whserow.rowkey,whsebin.binid binkey,
                    docentrycost.itemkey,sum(docentrycost.quantity*decode(docentrycost.in_out, 'O', '-1', 'I', '1')) quantity ,docentrycost.expirationdate, dochdr.melocationkey ownerloc, dr.sale_pur_trans as transactionmodule, icitem.upc
                from 
                     docentrycost,docentry,dochdrmst dochdr,whseaisle,whserow,whsebin,icitem, docparmst dr
                where
                    docentrycost.cny#=docentry.cny# and {$this->prodlineChildMapQry}
                    docentrycost.docentrykey=docentry.record# and 
                    docentry.cny#=dochdr.cny# and 
                    docentry.dochdrkey=dochdr.record#  and
                    docentrycost.cny#=whseaisle.cny#(+) and
                    docentrycost.aislekey=whseaisle.record#(+) and
                    docentrycost.cny#=whserow.cny#(+) and
                    docentrycost.rowkey=whserow.record#(+) and
                    docentrycost.cny#=whsebin.cny#(+) and
                    docentrycost.binkey=whsebin.record#(+) and 
                    docentrycost.cny#=icitem.cny# and
                    docentrycost.itemkey=icitem.itemid and 
                    docentrycost.lotno is not null and
                    dochdr.docparkey=dr.record# and
                    dochdr.cny#=dr.cny# and
                    docentrycost.cny#=:1 and 
                    docentrycost.lotno between :2 and :3 and 
                    docentrycost.whsekey between :4 and :5 and 
                    docentrycost.affects_inventory in ('V', 'QV') and
                    docentrycost.adjdocentrycostkey is null and				
                    $filterItemorUPC $ictotalsLocationFilter $ictotalsDeptFilter 
                    group by dochdr.docid,dochdr.record#,docentrycost.serialno,docentry.whencreated,docentrycost.lotno, docentrycost.whsekey,
                    $zoneSelect whseaisle.aisleid,whserow.rowkey, whsebin.binid,docentrycost.itemkey,docentrycost.expirationdate,
                    dochdr.melocationkey,dr.sale_pur_trans,icitem.upc, icitem.name 
                    order by dochdr.record#";
        }
        $args[0] = $lotqry;
        $this->_lotactivity = QueryResult($args);

        return true;
    }

    /**
     * @return mixed
     */
    public function DoMap()
    {
        
        $HdrMap = $this->_lothdr;
        $lineMap = $this->_lotactivity;

        foreach ($HdrMap as $hdrkey => $hdrval) {
            $trans = array();
            foreach ( $lineMap as $lineval) {
                $lineval['DATEIN'] = FormatDateForDisplay($lineval['DATEIN']);
                $lineval['EXPIRATIONDATE'] = FormatDateForDisplay($lineval['EXPIRATIONDATE']);
                if($hdrval['LOTNO']==$lineval['LOTNO']) {
                    $itemID = $lineval['ITEMKEY'];
                    $lineval['ITEMKEY'] = $this->params['REPORTON'] == 'ITEMID' ? $itemID : $lineval['UPC'];
                    $lineval['ITEMHREF'] = "javascript:drilldown(0,'$itemID', '$lineval[OWNERLOC]');";

                    $Docid = urlencode(addslashes($lineval['DOCID']));
            
                    if($lineval['TRANSACTIONMODULE']=='I') {
                        $lineval['DOCHREF'] = "javascript:drilldown(2,'$Docid', '$lineval[OWNERLOC]');";
                    }elseif($lineval['TRANSACTIONMODULE']=='S') {
                        $lineval['DOCHREF'] = "javascript:drilldown(3,'$Docid', '$lineval[OWNERLOC]');";
                    }elseif($lineval['TRANSACTIONMODULE']=='P') {
                        $lineval['DOCHREF'] = "javascript:drilldown(4,'$Docid', '$lineval[OWNERLOC]');";
                    }
                    //$lineval['DOCHREF'] = "javascript:drilldown(2,'$Docid', '$lineval[OWNERLOC]');";

                    $trans[] = $lineval;
                }

            }
            $HdrMap[$hdrkey]['DETAILS']=$trans;
        }

        if (empty($HdrMap)) {
            $HdrMap['NODATA'][0]= array('NODATA'=>'1');
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $HdrMap); 

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        return $lines;
    }

    /**
     * @param array $lines
     *
     * @return array
     */
    function DrawHeader($lines)
    {
        $dict = Dictionary::getInstance();
        $lines['report']["0"]['Aisle'] = $dict->GetRenamedText('Aisle')  ;
        $lines['report']["0"]['Bin'] = $dict->GetRenamedText('Bin')  ;
        $lines['report']["0"]['Row'] = $dict->GetRenamedText('Row')  ;
        $lines['report']["0"]['Item'] = $dict->GetRenamedText('Item')  ;
        $lines['report']["0"]['Warehouse'] = $dict->GetRenamedText('Warehouse')  ;
        return $lines;
    }

}
