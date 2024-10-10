<?
import('InventoryReporter');

/**
 * Class InvRegisterReport
 */
class InvRegisterReport extends InventoryReporter
{

    /** @var array $_balfwd */
    var $_balfwd = array();

    /** @var array $_curract */
    var $_curract = array();

    /**
     * @param array $params
     */
    function __construct($params)
    {

        parent::__construct(
            INTACCTarray_merge(
                $params, array(   
                'report' => 'invregister', 
                'ops'    => array(
                'inv/lists/item/view',
                'inv/lists/warehouse/view',
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
        global $kINVid;

        $ok = false;
        // 		$params = $this->params;
        $this->ValidateReport();
        // reload after the validate report
        $params = $this->params['safe'];

        $fromwarehouseid        = $params['FROMWAREHOUSEID'];
        $towarehouseid            = $params['TOWAREHOUSEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $dt1                    = $params['dt1'];
        $dt2                    = $params['dt2'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];

        $filterlocation = $this->_getLocationClause($params, 'documententry');
        $filterdept = $this->_getDeptClause($params, 'documententry');
    
        $companyid=GetMyCompany();

        // check whether light assembly is enabled
        //$itemMgr = $gManagerFactory->GetManager('item');
        GetModulePreferences($kINVid, $prefs);
        //$allowLightAssembly = $itemMgr->EnableLightAssembly();

        $begbalargs = array();
        $begbalargtypes = array();

        $curractargs = array();
        $curractargtypes = array();

        $itemargs = array();
        $itemargtypes = array();
        //$ReportOn = 'ITEMID';

        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues);
                array_push($begbalargs, $itemupcargs);
                array_push($begbalargtypes, 'text');

                array_push($curractargs, $itemupcargs);
                array_push($curractargtypes, 'text');

                array_push($itemargs, $itemupcargs);
                array_push($itemargtypes, 'text');
            } else {
                $filterItemorUPC = " icitem.itemid >= ? and icitem.itemid <= ? ";

                array_push($begbalargs, $fromitemid, $toitemid);
                array_push($begbalargtypes, 'text', 'text');

                array_push($curractargs, $fromitemid, $toitemid);
                array_push($curractargtypes, 'text', 'text');

                array_push($itemargs, $fromitemid, $toitemid);
                array_push($itemargtypes, 'text', 'text');

            }
        }else {
            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues);
                array_push($begbalargs, $itemupcargs);
                array_push($begbalargtypes, 'text');

                array_push($curractargs, $itemupcargs);
                array_push($curractargtypes, 'text');

                array_push($itemargs, $itemupcargs);
                array_push($itemargtypes, 'text');

            } else {
                $filterItemorUPC = " icitem.upc >= ? and icitem.upc <= ? ";

                array_push($begbalargs, $fromupc, $toupc);
                array_push($begbalargtypes, 'text', 'text');

                array_push($curractargs, $fromupc, $toupc);
                array_push($curractargtypes, 'text', 'text');

                array_push($itemargs, $fromupc, $toupc);
                array_push($itemargtypes, 'text', 'text');

            }
        }
        
        array_push($begbalargs, $fromwarehouseid, $towarehouseid, $dt1, $companyid);
        array_push($begbalargtypes, 'text', 'text', 'date', 'integer');

        array_push($begbalargs, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, $dt1, $companyid);
        array_push($begbalargtypes, 'text', 'text', 'text', 'text', 'date', 'integer');

        array_push($curractargs, $fromwarehouseid, $towarehouseid, $dt1, $dt2, $companyid);
        array_push($curractargtypes, 'text', 'text', 'date', 'date', 'integer');

        array_push($curractargs, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, $dt1, $dt2, $companyid);
        array_push($curractargtypes, 'text', 'text', 'text', 'text', 'date', 'date', 'integer');

        if ($prefs['LIGHTASSEMBLY'] =='T') {
            //arguments for balance forward query
            array_push($begbalargs, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, $dt1, $companyid);
            array_push($begbalargtypes, 'text', 'text', 'text', 'text', 'date', 'integer');            
            
            $qrybegbalstkit = " UNION ALL
						SELECT 
								documententrycost.itemkey, 
								documententrycost.whsekey warehouseid, 
								wh.name warehousename,
								documententrycost.in_out in_out,
								docpar.sale_pur_trans, 
								sum(documententrycost.quantity) qty,
								sum(documententrycost.value) value,
								dochdr.whencreated,
								docpar.updinv, icitem.upc, sum(documententrycost.cost) dec_cost,
								null adjdocentrycostkey
								FROM 
									docentrycostkits documententrycost,
									docentry documententry, 
									dochdrmst dochdr, 
									docparmst docpar, 
									icwarehouse wh,
									docpartotals totals,
									ictotal,icitemmst icitem
								WHERE
								documententrycost.cny# = documententry.cny# and
								documententrycost.docentrykey = documententry.record# and
								(documententrycost.itemkey >= ? and documententrycost.itemkey <=? ) and 
								(documententrycost.whsekey >= ? and documententrycost.whsekey <= ?)
								$filterdept  $filterlocation
								and icitem.cny# = documententry.cny#
								and icitem.itemid = documententry.itemkey and
								dochdr.cny# = documententry.cny# and 
								dochdr.record# = documententry.dochdrkey and 
								dochdr.whencreated < ? and 
								dochdr.state not in ('I','S','A', 'X', 'R') and
								dochdr.adj = 'F' and
								docpar.cny# (+) = dochdr.cny# and
								docpar.record# (+) = dochdr.docparkey and 
								(docpar.in_out = 'I' or docpar.in_out = 'D') and 
								(docpar.updinv != 'F' and docpar.updinv is not null) and
								wh.cny# (+) = documententrycost.cny# 
								and wh.location_no (+) = documententrycost.whsekey and
								totals.cny# = docpar.cny# and
								totals.docparkey = docpar.record# and
								ictotal.cny# = totals.cny# and
								ictotal.record# = totals.totalkey and 
								ictotal.name = 'ONHAND' and
								icitem.itemtype='SK' and
								documententry.cny# = ?
						group by documententrycost.itemkey,documententrycost.whsekey,wh.name,documententrycost.in_out, 
								docpar.sale_pur_trans, dochdr.whencreated, docpar.updinv, icitem.upc ";
            
            //arguments for Current activity query
            array_push($curractargs, $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, $dt1, $dt2, $companyid);
            array_push($curractargtypes, 'text', 'text', 'text', 'text', 'date', 'date', 'integer');
            $qrycurractstkit = " 	UNION ALL
							SELECT 
								documententrycost.itemkey, 
								documententrycost.whsekey warehouseid, 
								wh.name warehousename,
								documententrycost.in_out in_out, 
								docpar.sale_pur_trans, 
								sum(documententrycost.quantity) qty,
								sum(documententrycost.value) value,
								dochdr.whencreated,
								docpar.updinv, icitem.upc, sum(documententrycost.cost) dec_cost,
								null as adjdocentrycostkey
								FROM 
									docentrycostkits documententrycost,
									docentry documententry, 
									dochdrmst dochdr, 
									docparmst docpar, 
									icwarehouse wh,
									docpartotals totals,
									ictotal,icitemmst icitem
								WHERE
								documententrycost.cny# = documententry.cny# and
								documententrycost.docentrykey  = documententry.record# and
								documententry.cny# =icitem.cny# and	
								documententry.itemkey =icitem.itemid and
								(documententrycost.itemkey >= ? and documententrycost.itemkey <=? ) and 
								(documententrycost.whsekey >= ? and documententrycost.whsekey <= ?)
								$filterdept  $filterlocation
								and wh.cny# (+) = documententrycost.cny# 
								and wh.location_no (+) = documententrycost.whsekey and
								dochdr.cny# = documententry.cny# and 
								dochdr.record# = documententry.dochdrkey and 
								(dochdr.whencreated >= ? and dochdr.whencreated <= ? ) and 
								dochdr.state not in ('I', 'S','A', 'X', 'R') and
								dochdr.adj = 'F' and
								docpar.cny# (+) = dochdr.cny# and
								docpar.record# (+) = dochdr.docparkey and 
								(docpar.in_out = 'I' or docpar.in_out = 'D') and 
								(docpar.updinv != 'F' and docpar.updinv is not null) and
								totals.cny# = docpar.cny# and
								totals.docparkey = docpar.record# and
								ictotal.cny# = totals.cny# and
								ictotal.record# = totals.totalkey and 
								ictotal.name = 'ONHAND' and
								icitem.itemtype='SK' and
								documententry.cny# = ?
						group by documententrycost.itemkey,documententrycost.whsekey,wh.name, documententrycost.in_out, 
								docpar.sale_pur_trans, dochdr.whencreated, docpar.updinv, icitem.upc ";
        }else{
            $qrybegbalstkit  = "";
            $qrycurractstkit = "";
        }

        $begbalcode =  array(
        'QUERY'=> "SELECT	
	 	documententry.itemkey itemkey,
		documententry.warehousekey warehouseid, 
		wh.name warehousename,
		documententrycost.in_out, 
		docpar.sale_pur_trans, 
		sum(documententrycost.quantity) qty,
		sum(documententrycost.cost) value,
		dochdr.whencreated,
		docpar.updinv, icitem.upc, sum(documententrycost.cost) dec_cost,
		documententrycost.adjdocentrycostkey
		FROM	
            docentry documententry
            inner join dochdrmst dochdr on dochdr.cny# = documententry.cny# and dochdr.record# = documententry.dochdrkey
            inner join docparmst docpar on docpar.cny# = dochdr.cny# and docpar.record# = dochdr.docparkey
            inner join docpartotals totals on totals.cny# = docpar.cny# AND totals.docparkey = docpar.record#
            inner join ictotal on ictotal.cny# = totals.cny# and ictotal.record# = totals.totalkey and ictotal.name = 'ONHAND'
            inner join icitemmst icitem on icitem.cny#=documententry.cny# and icitem.itemid=documententry.itemkey
            inner join docentrycost documententrycost on documententrycost.cny#=documententry.cny# and documententrycost.docentrykey=documententry.record#
            and documententrycost.docentrykey=documententry.record# and documententrycost.affects_inventory in ('V', 'QV')         
            inner join icwarehouse wh on wh.cny#=documententry.cny# AND wh.location_no=documententry.warehousekey
		WHERE
			($filterItemorUPC ) and 
			(documententry.warehousekey >= ? and documententry.warehousekey <= ? )
			$filterdept  $filterlocation
			and
			dochdr.whencreated < ? and
			dochdr.state not in ('I','S','A', 'X', 'R') and
			docpar.in_out in ('I', 'D') and
			docpar.updinv != 'F' and
			dochdr.adj = 'F' and
			icitem.itemtype != 'K' and
			documententry.cny# = ?
        group by documententry.record#, documententry.itemkey, documententry.warehousekey, wh.name, 
        documententrycost.in_out, docpar.sale_pur_trans, dochdr.whencreated, 
        docpar.updinv, icitem.upc, documententrycost.adjdocentrycostkey
UNION ALL
SELECT 
	 	documententrycost.itemkey, 
		documententrycost.whsekey warehouseid, 
		wh.name warehousename,
		documententrycost.in_out ,  
		docpar.sale_pur_trans, 
		sum(documententrycost.quantity) qty,
		sum(documententrycost.cost) value,
		dochdr.whencreated,
		docpar.updinv, icitem.upc, sum(documententrycost.cost) dec_cost,
		documententrycost.adjdocentrycostkey
		FROM 
			docentrycost documententrycost,
			docentry documententry, 
			dochdrmst dochdr, 
			docparmst docpar, 
			icwarehouse wh,
			icitemmst icitem
		WHERE
		documententrycost.cny# = documententry.cny# and
		documententrycost.docentrykey = documententry.record# and
		--
		(documententrycost.itemkey >= ? and documententrycost.itemkey <=? ) and 
		(documententrycost.whsekey >= ? and documententrycost.whsekey <= ?) and 
		documententrycost.affects_inventory in ('V', 'QV') 
		$filterdept  $filterlocation
		--
		and icitem.cny# = documententry.cny#
		and icitem.itemid = documententry.itemkey and
		--
		dochdr.cny# = documententry.cny# and 
		dochdr.record# = documententry.dochdrkey and 
		dochdr.whencreated < ? and 
		dochdr.adj = 'F' and
		dochdr.state not in ('I','S','A', 'X', 'R') and
		--
		docpar.cny# = dochdr.cny# and
		docpar.record# = dochdr.docparkey and
		docpar.in_out in ('I', 'D') and
		docpar.updinv != 'F' and
		--
		wh.cny# (+) = documententrycost.cny# 
		and wh.location_no (+) = documententrycost.whsekey and
		--
		icitem.itemtype='K' and
		--
		documententry.cny# = ?
group by documententrycost.itemkey,documententrycost.whsekey,wh.name,documententrycost.in_out, 
		docpar.sale_pur_trans, dochdr.whencreated, docpar.updinv, icitem.upc, documententrycost.adjdocentrycostkey
$qrybegbalstkit
ORDER BY itemkey, warehouseid",
        'ARGTYPES' => $begbalargtypes
        );

        /** @noinspection PhpUndefinedVariableInspection */
        $curractcode = array(
        'QUERY'=> "SELECT	
	 	documententry.itemkey itemkey,
		documententry.warehousekey warehouseid, 
		wh.name warehousename,
		documententrycost.in_out, 
		docpar.sale_pur_trans, 
		sum(documententrycost.quantity) qty,
		sum(documententrycost.cost) value,
		dochdr.whencreated,
		docpar.updinv, icitem.upc, sum(documententrycost.cost) dec_cost,
		documententrycost.adjdocentrycostkey
		FROM	
          docentry documententry
          inner join dochdrmst dochdr on dochdr.cny# = documententry.cny# and dochdr.record# = documententry.dochdrkey
          inner join docparmst docpar on docpar.cny# = dochdr.cny# and docpar.record# = dochdr.docparkey
          inner join icitemmst icitem on icitem.cny#=documententry.cny# and icitem.itemid=documententry.itemkey
          inner join docentrycost documententrycost on documententrycost.cny#=documententry.cny# and documententrycost.docentrykey=documententry.record#
          and documententrycost.docentrykey=documententry.record# and documententrycost.affects_inventory in ('V', 'QV')         
          inner join icwarehouse wh on wh.cny#=documententry.cny# AND wh.location_no=documententry.warehousekey
		WHERE	
			($filterItemorUPC ) and 
			(documententry.warehousekey >= ? and documententry.warehousekey <= ? )
			$filterdept  $filterlocation
			and
			(dochdr.whencreated >= ? and dochdr.whencreated <= ? ) and
			dochdr.state not in ('I','S','A', 'X', 'R') and
			docpar.in_out in ('I', 'D') and
			docpar.updinv != 'F' and
			dochdr.adj = 'F' and
			icitem.itemtype != 'K' and
			documententry.cny# = ?
		group by documententry.record#, documententry.itemkey, documententry.warehousekey, wh.name, 
		documententrycost.in_out, docpar.sale_pur_trans, dochdr.whencreated, docpar.updinv, 
		icitem.upc, documententrycost.adjdocentrycostkey
	UNION ALL
	SELECT 
	 	documententrycost.itemkey, 
		documententrycost.whsekey warehouseid, 
		wh.name warehousename,
		documententrycost.in_out, 
		docpar.sale_pur_trans, 
		sum(documententrycost.quantity) qty,
		sum(documententrycost.cost) value,
		dochdr.whencreated,
		docpar.updinv, icitem.upc, sum(documententrycost.cost) dec_cost,
		documententrycost.adjdocentrycostkey
		FROM 
			docentrycost documententrycost,
			docentry documententry, 
			dochdrmst dochdr, 
			docparmst docpar, 
			icwarehouse wh,
			icitemmst icitem
		WHERE
		documententrycost.cny# = documententry.cny# and
		documententrycost.docentrykey  = documententry.record# and
		documententrycost.affects_inventory in ('V', 'QV') and 
		--
		documententry.cny# =icitem.cny# and	
		documententry.itemkey =icitem.itemid and
		--
		(documententrycost.itemkey >= ? and documententrycost.itemkey <=? ) and 
		(documententrycost.whsekey >= ? and documententrycost.whsekey <= ?)
		$filterdept  $filterlocation
		--
		and wh.cny# (+) = documententrycost.cny# 
		and wh.location_no (+) = documententrycost.whsekey and
		--
		dochdr.cny# = documententry.cny# and 
		dochdr.record# = documententry.dochdrkey and 
		(dochdr.whencreated >= ? and dochdr.whencreated <= ? ) and 
		dochdr.state not in ('I','S','A', 'X', 'R') and
		dochdr.adj = 'F' and
		--
		docpar.cny# = dochdr.cny# and
		docpar.record# = dochdr.docparkey and
		docpar.in_out in ('I', 'D') and
		docpar.updinv != 'F' and
		--
		icitem.itemtype='K' and
		--
		documententry.cny# = ?
group by documententrycost.itemkey,documententrycost.whsekey,wh.name,documententrycost.in_out, 
		docpar.sale_pur_trans, dochdr.whencreated, docpar.updinv,documententrycost.value, icitem.upc, documententrycost.adjdocentrycostkey
	$qrycurractstkit
ORDER BY itemkey, warehouseid",
        'ARGTYPES' => $curractagrtypes
        );        

        //	
        //	dochdr.state = 'C' and 
        
        //$code = 'QRY_' .  $upperreportname . '_SELECT_ITEMS';
        $code = array(
             'QUERY'=>"SELECT  rownum, icitem.itemid itemid, icitem.name description, icitem.productlinekey||pl.description productline,
					uom.unit uom,icitem.std_uom, icitem.locationkey itownerloc,
					decode(icitem.cost_method, 'S','IA.STANDARD','A','IA.AVERAGE','F','IA.FIFO', 'L','IA.LIFO','O','IA.LOT','#','IA.SERIAL_NUMBER', NULL) cost_method, icitem.upc
				FROM	icitem , icprodline pl, icuom uom, icuomgrp uomgrp
				WHERE	($filterItemorUPC )and pl.productlineid (+) = icitem.productlinekey 
					and pl.cny# (+) = icitem.cny# 
					and uomgrp.cny# = icitem.cny#
					and uomgrp.record# = icitem.uomgrpkey					
					and	uom.cny# = uomgrp.cny#
					and uom.isbase = 'T'
					and	uom.grpkey = uomgrp.record#  
					and icitem.cny# = ? and
					icitem.itemtype NOT IN ('NI', 'NP','NS')
				ORDER BY  icitem.itemid",
        'ARGTYPES'=> $itemargtypes
        );
        
        $items = $this->_QM->DoCustomQuery($code, $itemargs, true);
        $this->_items = $items;

        //  if no items found return false
        if( is_array($items[0]) ) {
            //  balance forward
            $balfwd = $this->_QM->DoCustomQuery($begbalcode, $begbalargs, true);
            $this->_balfwd = $balfwd;

            // current activity
            $curract = $this->_QM->DoCustomQuery($curractcode, $curractargs, true);

            $this->_curract = $curract;
            $ok = true;
        }
        return $ok;
    }


    /**
     * @return array
     */
    function DoMap()
    {
        $ItemMap = array();
        foreach ($this->_items as $it) {
            $it['ITEMHREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($it['ITEMID']))
                . "', '$it[WHOWNERLOC]');";
            $ItemMap[$it['ITEMID']] = $it;
        }

        $uomPref = INVSetupManager::getUOMPreference();
        if ($uomPref) {
            $defaultUOMCache = $this->GetUOMCache(true);
        }
        
        $round = ItemManager::BASEUNITPRECISION;
        $BalFwdMap = array();
        foreach ($this->_balfwd as $row) {
            $BalFwdMap[$row['ITEMKEY']][] = $row;
        }

        $ActMap = array();
        foreach ($this->_curract as $row) {
            $ActMap[$row['ITEMKEY']][] = $row;
        }

        $RepMap = array();
        foreach ($ItemMap as $item) {
            $key = $item['ROWNUM'];
            $itemkey = $item['ITEMID'];

            $qtybbtot = 0;
            $qtyintot = 0;
            $qtyouttot = 0;
            $qtyacttot = 0;
            $qtyendtot = 0;

            $prcbbtot = 0;
            $prcintot = 0;
            $prcouttot = 0;
            $prcacttot = 0;
            $prcendtot = 0;
            
            $balance = $BalFwdMap[$itemkey];
            $current = $ActMap[$itemkey];

            $bq = array();
            $bp = array();
            $cq = array();
            $cp = array();
            $whselist = array();
            $whsenamelist = array();

            if ($balance) {
                foreach ($balance as $bal) {
                    $whse = $bal['WAREHOUSEID'];
                    $whsename = $bal['WAREHOUSENAME'];
                    $this->computeParams($bal, $qty, $value, $inout);
                    $tbq = ($bal['UPDINV'] == 'V'
                        && ($bal['SALE_PUR_TRANS'] == 'I'
                            || !empty($bal['ADJDOCENTRYCOSTKEY']))) ? 0 : $qty;
                    $bq[$whse][$inout] = ibcadd($bq[$whse][$inout], $tbq, $round);
                    
                    $tbp = ($bal['UPDINV'] == 'Q') ? 0 : $value;
                    $bp[$whse][$inout] = ibcadd($bp[$whse][$inout], $tbp, ItemManager::AVERAGE_COST_DECIMALS);

                    $whselist[$whse] = $whse;
                    $whsenamelist[$whse] = $whsename;
                }
            }
            if ($current) {
                foreach ($current as $cur) {

                    $whse = $cur['WAREHOUSEID'];
                    $whsename = $cur['WAREHOUSENAME'];
                    $this->computeParams($cur, $qty, $value, $inout);

                    $tcq = ($cur['UPDINV'] == 'V'
                        && ($cur['SALE_PUR_TRANS'] == 'I'
                            || !empty($cur['ADJDOCENTRYCOSTKEY']))) ? 0 : $qty;
                    $cq[$whse][$inout] = ibcadd($cq[$whse][$inout], $tcq, $round);
                    
                    $tcp = ($cur['UPDINV'] == 'Q') ? 0 : $value;
                    $cp[$whse][$inout] = ibcadd($cp[$whse][$inout], $tcp, ItemManager::AVERAGE_COST_DECIMALS);
                    
                    $whselist[$whse] = $whse;
                    $whsenamelist[$whse] = $whsename;
                }
            }

            $i = 0;
            if ($whselist) {
                $RepMap[$key] = $item;
                foreach ($whselist as $whse) {

                    //bq = beginning quantity
                    //cq = current quantity

                    $begbal1 = iround(
                        iround($bq[$whse]['IP'], $round)
                        + iround($bq[$whse]['II'], $round)
                        + iround($bq[$whse]['IS'], $round)
                        - iround($bq[$whse]['OP'], $round)
                        - iround($bq[$whse]['OI'], $round)
                        - iround($bq[$whse]['OS'], $round), $round
                    );

                    $in1 = iround(
                        iround($cq[$whse]['IP'], $round)
                        + iround($cq[$whse]['II'], $round)
                        + iround($cq[$whse]['IS'], $round), $round
                    );

                    $out1 = iround(
                        iround($cq[$whse]['OS'], $round)
                        + iround($cq[$whse]['OI'], $round)
                        + iround($cq[$whse]['OP'], $round), $round
                    );
                    $act1 = ibcsub($in1, $out1, $round);
                    $endbal1 = ibcadd($begbal1, $act1, $round);

                    $begbal2 = iround(
                        iround($bp[$whse]['IP'], 2)
                        + iround($bp[$whse]['II'], 2)
                        + iround($bp[$whse]['IS'], 2)
                        - iround($bp[$whse]['OP'], 2)
                        - iround($bp[$whse]['OI'], 2)
                        - iround($bp[$whse]['OS'], 2), 2
                    );

                    $in2 = iround(
                        iround($cp[$whse]['IP'], 2)
                        + iround($cp[$whse]['II'], 2)
                        + iround($cp[$whse]['IS'], 2), 2
                    );
                    $out2 = iround(
                        iround($cp[$whse]['OS'], 2)
                        + iround($cp[$whse]['OI'], 2)
                        + iround($cp[$whse]['OP'], 2), 2
                    );
                    $act2 = ibcsub($in2, $out2, 2);
                    $endbal2 = ibcadd($begbal2, $act2, 2);

                    //epp("Beginning balance was " . $begbal1);					
                    $i++;

                    // include it in the totals
                    /** @noinspection PhpUndefinedVariableInspection */
                    $qtybbtot = ibcadd($qtybbtot, $begbal1, $round);
                    $qtyintot = ibcadd($qtyintot, $in1, $round);
                    $qtyouttot = ibcadd($qtyouttot, $out1, $round);
                    $qtyacttot = ibcadd($qtyacttot, $act1, $round);
                    $qtyendtot = ibcadd($qtyendtot, $endbal1, $round);
                    $prcbbtot = ibcadd($prcbbtot, $begbal2, 2);
                    $prcintot = ibcadd($prcintot, $in2, 2);
                    $prcouttot = ibcadd($prcouttot, $out2, 2);
                    $prcacttot = ibcadd($prcacttot, $act2, 2);
                    $prcendtot = ibcadd($prcendtot, $endbal2, 2);

                    // put the record into the output
                    //$RepMap[$key] = $item;
                    $RepMap[$key]['TRANS'][$i]['WAREHOUSEID'] = $whse;
                    $RepMap[$key]['TRANS'][$i]['WAREHOUSENAME'] = $whsenamelist[$whse];
                    /** @noinspection PhpUndefinedVariableInspection */
                    $RepMap[$key]['TRANS'][$i]['WAREHOUSEHREF'] = "javascript:drilldown(1,'" . urlencode($whse)
                        . "', '$row[WHOWNERLOC]');";
                    $RepMap[$key]['TRANS'][$i]['BIGBAL1'] = $begbal1;
                    $RepMap[$key]['TRANS'][$i]['IN1'] = $in1;
                    $RepMap[$key]['TRANS'][$i]['OUT1'] = $out1;
                    $RepMap[$key]['TRANS'][$i]['ACT1'] = $act1;
                    $RepMap[$key]['TRANS'][$i]['ENDBAL1'] = $endbal1;

                    $RepMap[$key]['TRANS'][$i]['BIGBAL2'] = $begbal2;
                    $RepMap[$key]['TRANS'][$i]['IN2'] = $in2;
                    $RepMap[$key]['TRANS'][$i]['OUT2'] = $out2;
                    $RepMap[$key]['TRANS'][$i]['ACT2'] = $act2;
                    $RepMap[$key]['TRANS'][$i]['ENDBAL2'] = $endbal2;
                    if ($this->params['REPORTON'] == 'UPC') {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $RepMap[$key]['TRANS'][$i]['ENDBAL1HREF'] = $this->BuildItemActivityURL(
                            $item['UPC'], $whse, $dt1, $dt2, $item['ITOWNERLOC'], 'UPC'
                        );
                    } else {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $RepMap[$key]['TRANS'][$i]['ENDBAL1HREF'] = $this->BuildItemActivityURL(
                            $item['ITEMID'], $whse, $dt1, $dt2, $item['ITOWNERLOC']
                        );
                    }
                    $RepMap[$key]['ITEMTOTAL'][0]['ITEMID'] = $item['ITEMID'] . ' - ' . $item['DESCRIPTION'];
                    $RepMap[$key]['ITEMTOTAL'][0]['UPC'] = $item['UPC'];
                    $RepMap[$key]['ITEMTOTAL'][0]['PRCBBTOT'] = $prcbbtot;
                    $RepMap[$key]['ITEMTOTAL'][0]['PRCINTOT'] = $prcintot;
                    $RepMap[$key]['ITEMTOTAL'][0]['PRCOUTTOT'] = $prcouttot;
                    $RepMap[$key]['ITEMTOTAL'][0]['PRCACTTOT'] = $prcacttot;
                    $RepMap[$key]['ITEMTOTAL'][0]['PRCENDTOT'] = $prcendtot;

                    $RepMap[$key]['ITEMTOTAL'][0]['QTYBBTOT'] = $qtybbtot;
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYINTOT'] = $qtyintot;
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYOUTTOT'] = $qtyouttot;
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYACTTOT'] = $qtyacttot;
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYENDTOT'] = $qtyendtot;

                    if ($uomPref) {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $uomInfo = $defaultUOMCache[$itemkey];
                        $round = $uomInfo['NUMDEC'];
                        $RepMap[$key]['UOM'] = $uomInfo['UNIT'];
                        $RepMap[$key]['TRANS'][$i]['BIGBAL1'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['BIGBAL1']
                        );
                        $RepMap[$key]['TRANS'][$i]['IN1'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['IN1']
                        );
                        $RepMap[$key]['TRANS'][$i]['OUT1'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['OUT1']
                        );
                        $RepMap[$key]['TRANS'][$i]['ACT1'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['ACT1']
                        );
                        $RepMap[$key]['TRANS'][$i]['ENDBAL1'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['ENDBAL1']
                        );

                        $RepMap[$key]['TRANS'][$i]['BIGBAL2'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['BIGBAL2']
                        );
                        $RepMap[$key]['TRANS'][$i]['ACT2'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['ACT2']
                        );
                        $RepMap[$key]['TRANS'][$i]['ENDBAL2'] = UOMManager::getQuantityByDefaultUOM(
                            $uomInfo, $RepMap[$key]['TRANS'][$i]['ENDBAL2']
                        );
                    }
                }
                if ($uomPref) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $uomInfo = $defaultUOMCache[$itemkey];
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYBBTOT'] = UOMManager::getQuantityByDefaultUOM(
                        $uomInfo, $RepMap[$key]['ITEMTOTAL'][0]['QTYBBTOT']
                    );
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYINTOT'] = UOMManager::getQuantityByDefaultUOM(
                        $uomInfo, $RepMap[$key]['ITEMTOTAL'][0]['QTYINTOT']
                    );
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYOUTTOT'] = UOMManager::getQuantityByDefaultUOM(
                        $uomInfo, $RepMap[$key]['ITEMTOTAL'][0]['QTYOUTTOT']
                    );
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYACTTOT'] = UOMManager::getQuantityByDefaultUOM(
                        $uomInfo, $RepMap[$key]['ITEMTOTAL'][0]['QTYACTTOT']
                    );
                    $RepMap[$key]['ITEMTOTAL'][0]['QTYENDTOT'] = UOMManager::getQuantityByDefaultUOM(
                        $uomInfo, $RepMap[$key]['ITEMTOTAL'][0]['QTYENDTOT']
                    );

                    $qtybbtot = $RepMap[$key]['ITEMTOTAL'][0]['QTYBBTOT'];
                    $qtyintot = $RepMap[$key]['ITEMTOTAL'][0]['QTYINTOT'];
                    $qtyouttot = $RepMap[$key]['ITEMTOTAL'][0]['QTYOUTTOT'];
                    $qtyacttot = $RepMap[$key]['ITEMTOTAL'][0]['QTYACTTOT'];
                    $qtyendtot = $RepMap[$key]['ITEMTOTAL'][0]['QTYENDTOT'];
                }
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $grnqtybbtot = ibcadd($grnqtybbtot, $qtybbtot, $round);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnqtyintot = ibcadd($grnqtyintot, $qtyintot, $round);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnqtyouttot = ibcadd($grnqtyouttot, $qtyouttot, $round);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnqtyacttot = ibcadd($grnqtyacttot, $qtyacttot, $round);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnqtyendtot = ibcadd($grnqtyendtot, $qtyendtot, $round);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnprcbbtot = ibcadd($grnprcbbtot, $prcbbtot, 2);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnprcintot = ibcadd($grnprcintot, $prcintot, 2);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnprcouttot = ibcadd($grnprcouttot, $prcouttot, 2);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnprcacttot = ibcadd($grnprcacttot, $prcacttot, 2);
            /** @noinspection PhpUndefinedVariableInspection */
            $grnprcendtot = ibcadd($grnprcendtot, $prcendtot, 2);

        }
        if (count($RepMap) == 0) {
            $RepMap['NODATA'][0] = array('NODATA' => '1');
        } else {
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNQTYBBTOT'] = $grnqtybbtot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNQTYINTOT'] = $grnqtyintot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNQTYOUTTOT'] = $grnqtyouttot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNQTYACTTOT'] = $grnqtyacttot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNQTYENDTOT'] = $grnqtyendtot;

            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNPRCBBTOT'] = $grnprcbbtot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNPRCINTOT'] = $grnprcintot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNPRCOUTTOT'] = $grnprcouttot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNPRCACTTOT'] = $grnprcacttot;
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNPRCENDTOT'] = $grnprcendtot;
        }
        // eppp($RepMap);
        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $RepMap);

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC'
            : $lines['report'][0]['term_Item'];
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
        foreach( $this->_items as $val) {
            array_push($itemArray,$val['ITEMID'] );
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
     * Compute parameters based on $rec. This function does the following:
     * columns reversal negative quantity
     * value determination whether to use COGS or transaction value
     *
     * @param array         $rec
     * @param int|string    $qty
     * @param string        $value
     * @param string        $inout
     *
     * @return string
     */
    private function computeParams($rec, &$qty, &$value, &$inout)
    {
        $qty = $rec['QTY'];
        $recValue = $rec['VALUE'];
        /** @var string $decCost */
        $decCost = $rec['DEC_COST'] ?? null;
        $saleOrPurchase = $rec['SALE_PUR_TRANS'];
        $increaseOrDecrease = $rec['IN_OUT'];

        // Always try to use COGS whenever possible, unless for incoming purchases we need to include apportioned subtotal which is included in recValue
        if ($decCost !== null && !($saleOrPurchase == 'P' and $increaseOrDecrease == 'I')) {
            $value = $decCost;
        } else {
            // ... otherwise get the docentry value
            $value = $recValue;
        }

        if ($qty < 0) {
            // invert the in/out, i.e. Increase to Decrease, Decrease to Increase
            $inout = ($increaseOrDecrease == 'I' ? 'O' : 'I');
            $qty = -$qty;
            /** @noinspection CallableParameterUseCaseInTypeContextInspection - https://youtrack.jetbrains.com/issue/WI-38845 */
            $value = -$value;
        } else {
            $inout = $increaseOrDecrease;
        }

        $inout .= $saleOrPurchase;

        return $inout;
    }

}
