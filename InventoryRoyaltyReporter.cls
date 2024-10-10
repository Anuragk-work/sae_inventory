<?php
define("BUILD_KIT", 'Build Kits');
define("DIS_KIT", 'Disassemble Kits');

import('InventoryReporter');

/**
 * Class InventoryRoyaltyReporter
 */
class InventoryRoyaltyReporter extends InventoryReporter
{

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct($params);
    }


    /**
     * @return bool
     */
    function DoQuery()
    {

        $this->ValidateReport();

        $this->params['safe']['FILTERTRANSACTIONS'] = $this->params['FILTERTRANSACTIONS'];
        $params = $this->params['safe'];

        $fromterritoryid        = $params['FROMTERRITORYID'];
        $toterritoryid            = $params['TOTERRITORYID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $fromcustid                = $params['FROMCUSTOMERID'];
        $tocustid                = $params['TOCUSTOMERID'];
        $fromvendorid            = $params['FROMVENDORID'];
        $tovendorid                = $params['TOVENDORID'];
        $prodlineid                = $params['PRODLINEID'];
        $dt1                    = $params['dt1'];
        $dt2                    = $params['dt2'];
        $fromwhseid                = $params['FROMWAREHOUSEID'];
        $towhseid                = $params['TOWAREHOUSEID'];
        $orderstate                = $params['ORDERSTATE'];
        $summarymode            = $params['SUMMARYMODE'];
        $reportgroupings        = $params['REPORTGROUPINGS'];
        $showthe                = $params['SHOWTHE'];
        $doctype                = $params['trans'];
        $docclass                = $params['DOCCLASS'];
        $custvend                = $params['custvend'];
        $gReport['ROUNDING']    = 'C';
        $excludebackorder        = $this->params['EXCLBACKORDER'];

        $Inventory    = $this->params['INVENTORY'];
        $NonInv        = $this->params['NON_INV'];
        $NonInvPO    = $this->params['NON_INV_PO'];
        $NonInvSO    = $this->params['NON_INV_SO'];
        $Kit        = $this->params['KIT'];
        $Stockable_Kit        = $this->params['STKIT'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];

        $cny = GetMyCompany();

        //		$args = array('sql', $cny, $fromitemid, $toitemid, $dt1, $dt2);
        $args = array('sql', $cny,);
        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues, 2);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                //}

            } else {
                $filterItemorUPC = " icitem.itemid  >= :2 and icitem.itemid  <= :3 ";
                array_push($args, $fromitemid, $toitemid);
            }
        }else {

            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues, 2);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                //}
            } else {
                $filterItemorUPC = " icitem.upc  >= :2 and icitem.upc  <= :3 ";
                array_push($args, $fromupc, $toupc);
            }
        }

        array_push($args, $dt1, $dt2);


        $empcontacttable='';
        $empcontact_select_clause='';
        $empcontact_clause='';

        switch( $custvend ){
        case 'cust':
            $custvendtable = 'customer';

            $SPT_flag = 'S';
            $custvendid_clause = "	customer.customerid >= :6 and
										customer.customerid <= :7 and ";

            $custvendcny_clause = "	customer.cny# = :1 and	";

            $custvend_select_clause = "	customer.customerid as id,
											customer.name as name,
											customer.locationkey as ENOWNERLOC,
											customer.territorykey as territory,
											customer.custrepkey as salesrep, ";

            $custvend_entity = "custentity";

            $empcontacttable = 'employee, contact';
            $empcontact_select_clause = ' contact.name salesrepname, ';
            $empcontact_clause =  ' customer.cny# = employee.cny#(+) and ';
            $empcontact_clause .= ' customer.custrepkey = employee.employeeid (+) and ';
            $empcontact_clause .= ' employee.cny# = contact.cny# (+) and ';
            $empcontact_clause .= ' employee.contactkey = contact.record#(+) and ';

            $where_custvendselect = " dochdr.$custvend_entity = $custvendtable.entity and ";
            $args[] = $fromcustid;
            $args[] = $tocustid;

            break;
        case 'vend':
            $custvendtable = 'vendor';
            $SPT_flag = 'P';
            $custvend_entity = "vendentity";

            if($fromvendorid == VARCHAR2_MIN || $tovendorid==VARCHAR2_MAX) {
                $custvendid_clause = "	((vendor.vendorid >= :6 and
										vendor.vendorid <= :7) or dochdr.entity is null) and ";

                $custvendcny_clause = "	vendor.cny# (+) = :1 and ";

                $where_custvendselect = " dochdr.$custvend_entity = $custvendtable.entity (+) and ";

            }else {
                $custvendid_clause = "	vendor.vendorid >= :6 and
										vendor.vendorid <= :7 and ";

                $custvendcny_clause = "	vendor.cny# = :1 and ";

                $where_custvendselect = " dochdr.$custvend_entity = $custvendtable.entity and ";
            }

            $custvend_select_clause = "	vendor.vendorid as id,
										vendor.name as name,
										vendor.locationkey as ENOWNERLOC,
										'' as territory,
										'' as salesrep,	";
            $args[] = $fromvendorid;
            $args[] = $tovendorid;
            break;
        case 'inv':
            $custvendtable = '';
            $SPT_flag = 'I';

            $custvendid_clause = " docentry.warehousekey between :6 and :7 and	";
            $args[] = $fromwhseid;
            $args[] = $towhseid;

            $custvendcny_clause = "";
            $custvend_select_clause = "";
            $where_custvendselect = "";
            break;
        }

        $SPT_flag_clause = " docpar.sale_pur_trans = :8 and ";
        /** @noinspection PhpUndefinedVariableInspection */
        $args[] = $SPT_flag;

        $argIndex = 8;

        // in this report, the 'summarymode' is split into three controls
        // this simplifies the UI, but makes it simple to have many many permutations
        if ($reportgroupings == 'Default' ) {
            switch( $custvend){
            case 'cust':
                $reportgroupings = 'Customer';
                break;
            case 'vend':
                $reportgroupings = 'Vendor';
                break;
            case 'inv':
                $reportgroupings = 'Warehouse';
            }
        }

        if ($showthe == 'Default' ) {
            $showthe = 'Orders';
        }
        if ($summarymode == 'Default' ) {
            $summarymode = 'Summary';
        }
        $summarymode = $reportgroupings . ' ' . $showthe . ' ' . $summarymode;

        $this->params['safe']['SUMMARYMODE'] = $summarymode;


        if ( !isset($orderstate) ) {
            $orderstate = "All";
        }

        switch ($orderstate){
        case 'Draft Orders':
            $state_clause = "dochdr.state = 'I' and ";
            break;
        case 'Posted Open Orders':
            $state_clause = "dochdr.state = 'O' and ";
            break;
        case 'Closed Orders':
            $state_clause = "dochdr.state = 'D' and ";
            break;
        case 'Converted Orders':
            $state_clause = "dochdr.state in ( 'C', 'L') and ";
            break;
        case 'All':
            $state_clause = "";
            break;
        }

        if( $docclass != '' && $docclass != '%' ) {
            $docclass_clause = "docpar.docclass = :".++$argIndex." and ";
            $args[] = $docclass;
        } else {
            $docclass_clause = "";
        }

        if ($fromterritoryid == VARCHAR2_MIN && $toterritoryid == VARCHAR2_MAX) {
            $territory_where_clause = "";
        } else {
            $territory_where_clause = "	customer.territorykey >= :".++$argIndex." and
						customer.territorykey <= :".++$argIndex." and ";
            $args[] = $fromterritoryid;
            $args[] = $toterritoryid;
        }

        if ($doctype != '%') {
            $pieces = explode('#~#', $doctype);
            $useInClause = count($pieces) > 1;
            $doctype_clause = 'docpar.docid ';
            $doctype_clause .= $useInClause ? 'in (' : '= ';

            $first = true;
            foreach($pieces as $onedoctype)
            {
                if (!$first) {
                    $doctype_clause .= ', ';
                }
                $doctype_clause .= ':'.++$argIndex;
                $args[] = $onedoctype;
                $first = false;
            }

            if ($useInClause) {
                $doctype_clause .= ')';
            }
            $doctype_clause .= ' and ';
        } else {
            $doctype_clause = '';
        }

        if ($prodlineid == '%') {
            $prodline_clause = "";
        } else {
            $prodline_clause = "  icitem.productlinekey in ( select productlineid from icprodline where cny# = icitem.cny# 
                start with cny# = icitem.cny# and productlineid= :".++$argIndex."
                connect by cny# = icitem.cny# and parentlineid = PRIOR productlineid) and ";
            //$prodline_clause = " icitem.productlinekey = :9 and ";
            $args[] = $prodlineid;
        }

        if ($excludebackorder == 'true') {
            $backorderclause = "(dochdr.backorder != 'T' or dochdr.backorder is null) and";
        }

        $filterlocation = $this->_getLocationClause($params);
        $filterdept = $this->_getDeptClause($params);

        /** @noinspection PhpUndefinedVariableInspection */
        if ( $custvendtable != '') {
            $qry_custvendtable = ", " . $custvendtable;
        } else {
            $qry_custvendtable = "";
        }

        if ($empcontacttable !='') {
            $qry_custvendtable = $qry_custvendtable. ", ". $empcontacttable;
        }

        //global $gRequest;
        //$mod = Request::$r->_mod;
        $mod = $this->params['mod'];

        //When run for dashboard, mod is not set. So checking for modulekey
        $modkey = $this->params['modulekey'];

        $itemtypeqry = ' ';
        // filter records based on ItemType
        if ( $mod == 'inv' || $modkey == '7.INV') {
            $itemtypeqry = ' ';
        } else {
            $itemtypesin = '';
            $itemtypesin.= $Inventory == 'true' ? "'I'," : '' ;
            $itemtypesin.= $NonInv == 'true' ? "'NI'," : '' ;
            $itemtypesin.= $NonInvPO == 'true' ? "'NP'," : '' ;
            $itemtypesin.= $NonInvSO == 'true' ? "'NS'," : '' ;
            $itemtypesin.= $Stockable_Kit == 'true' ? "'SK'," : '' ;
            //$itemtypesin.= $Kit == 'true' ? "'K'," : '' ;
            //$itemtypesin.= "''";
            if (!($itemtypesin==='')) {
                $itemtypesin=chop($itemtypesin, ',');
                $itemtypeqry=" icitem.itemtype IN (".$itemtypesin.") and ";
            }
        }

        //do not show following TDs in the report -- mmahur
        $StKitclause = " docpar.docid not in ('".BUILD_KIT."','".DIS_KIT."') and ";

        /** @noinspection PhpUndefinedVariableInspection */
        $qryselect3 = "SELECT distinct docentry.record#,
							dochdr.record# as hdrrec,
							" . $custvend_select_clause . "
							" . $empcontact_select_clause . "
							docpar.sale_pur_trans,
							docpar.category,
							dochdr.docno,
							dochdr.docid,
							docpar.updinv,
							dochdr.whencreated,
							dochdr.shipviakey,
							dochdr.ponumber,
							decode(dochdr.state, 'O', 'IA.PENDING', 'G', 'IA.IN_PROGRESS', 'D', 'IA.CLOSED', 'I', 'IA.DRAFT', 'C', 'IA.CONVERTED',
							'L', 'IA.CONVERTED_BY_LINE', 'P', 'IA.PARTIALLY_CONVERTED', 'B', 'IA.PARTIALLY_CONVERTED_BY_LINE', 
							'E', 'IA.EXCEPTION', dochdr.state) as hdrstate,
							docentry.warehousekey,
							docentry.dochdrkey,
							docentry.itemkey,
							docentry.itemdescr,
							case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									(docentry.quantity ) * -1
								else
									(docentry.quantity )
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									(docentry.quantity )
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										(docentry.quantity) * -1
									else
										(docentry.quantity )
									end									
								end
							end quantity,
							decode(dept.dept_no, null, '', dept.dept_no || '--' || dept.title) as department,
							decode(loc.location_no, null, '', loc.location_no ||'--' || loc.name) as location,
							docentry.price,
							case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									docentry.value * -1
								else
									docentry.value
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									docentry.value
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										docentry.value * -1
									else
										docentry.value
									end									
								end
							 end value,
								case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									sum(nvl(docentrycost.cost,0)) * -1
								else
									sum(nvl(docentrycost.cost, 0))
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									sum(nvl(docentrycost.cost,0))
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										sum(nvl(docentrycost.cost,0)) * -1
									else
										sum(nvl(docentrycost.cost,0))
									end									
								end
							 end cost, 
								case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									(docentry.value - sum(nvl(docentrycost.cost,0))) * -1
								else
									(docentry.value - sum(nvl(docentrycost.cost,0)))
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									(docentry.value - sum(nvl(docentrycost.cost,0)))
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										(docentry.value - sum(nvl(docentrycost.cost,0))) * -1
									else
										(docentry.value - sum(nvl(docentrycost.cost,0)))
									end									
								end
							 end margin, 
							
							icuom.unit as uom,
							icitem.productlinekey as productlinekey,
							dochdr.melocationkey DOCOWNERLOC,
							docpar.locationkey DOCPAROWNERLOC,
							icitem.locationkey ITOWNERLOC,
							icw.locationkey WHOWNERLOC, icitem.upc
						FROM dochdrmst dochdr,docparmst docpar, docentry, docentrycost, icuom, icuomgrp, icitemmst icitem, docpartotals,ictotal, icwarehouse icw, locationmst loc, department dept $qry_custvendtable
						WHERE							
							icitem.cny# = :1 and
							icitem.itemid = docentry.itemkey and
							icuomgrp.cny# (+) = icitem.cny# and 
							icuomgrp.record# (+) = icitem.uomgrpkey and
							icuom.grpkey (+) = icuomgrp.record# and
							icuom.cny# (+) = icuomgrp.cny# and
							icuom.isbase (+) = 'T'	and			  
							docentry.cny# = :1 and
							icw.cny# (+) = :1 and
							loc.cny# (+) = :1 and
							dept.cny# (+) = :1 and
							docpar.cny# = :1 and
							dochdr.cny# = :1 and
							docentry.locationkey = loc.record#(+) and
							docentry.deptkey = dept.record#(+) and
							docentry.cny# = docentrycost.cny#(+) and
							docentry.record# = docentrycost.docentrykey(+) and							
							icitem.itemid = docentry.itemkey and
							icw.location_no (+) = docentry.warehousekey and
							docentry.dochdrkey = dochdr.record# and
							docpar.record# = dochdr.docparkey and
							docpar.cny# = docpartotals.cny#(+) and
							docpar.record# = docpartotals.docparkey(+) and
							docpartotals.cny# = ictotal.cny#(+) and
							docpartotals.totalkey = ictotal.record#(+) and
							icitem.itemtype<>'K' and " .
                      $itemtypeqry . " " .
                      $where_custvendselect . " " .
                      $SPT_flag_clause . " " .
                      $state_clause . " " .
                      $docclass_clause . " " .
                      $doctype_clause . " " .
                      $prodline_clause . " " .
                      $custvendid_clause . " " .
                      $empcontact_clause . " " .
                      $territory_where_clause . " " .
                      $custvendcny_clause . " " .
                      $backorderclause . " " .
                      $StKitclause . " " .
                      $filterItemorUPC . " and
							dochdr.whencreated >= :4 and
							dochdr.whencreated <= :5 and
							dochdr.state not in ('S','A', 'X', 'R')
							$filterdept
							$filterlocation	";

        $groupbyClause =" Group By 
							dochdr.record#,docentry.record# ,";

          switch( $custvend ){
        case 'cust':
            $grpcustvend = "	customer.customerid,
																customer.name,
																customer.locationkey,
																customer.territorykey,
																customer.custrepkey, ";
            break;
        case 'vend':
            $grpcustvend = "	vendor.vendorid,
															vendor.name,
															vendor.locationkey, ";
            break;
        case 'inv':
            $grpcustvend = "";
            break;
          }
        /** @noinspection PhpUndefinedVariableInspection */
        $groupbyClause = $groupbyClause . $grpcustvend;

            if(isset($empcontact_select_clause) && $empcontact_select_clause!='') {
                $groupbyClause = $groupbyClause . "contact.name , ";
            }

            $groupbyClause = $groupbyClause .
            " docpar.sale_pur_trans,
							docpar.category,
							dochdr.docno,
							dochdr.docid,
							docpar.updinv,
							dochdr.whencreated,
							dochdr.shipviakey,
							dochdr.ponumber,
							dochdr.state,
							docentry.warehousekey,
							docentry.dochdrkey,
							docentry.itemkey,
							docentry.itemdescr,
							docentry.quantity,
							dept.dept_no,dept.title ,
							loc.location_no,loc.name ,							
							docentry.price,
							icuom.unit,
							icitem.productlinekey,
							dochdr.melocationkey ,
							docpar.locationkey ,
							icitem.locationkey ,
							icw.locationkey,
							docpar.in_out,docentry.value, icitem.upc";

            $qryselect3=$qryselect3 . " " . $groupbyClause . ",docpartotals.sign,ictotal.name";
            // if Item Type is checked for kit, fetch the details for kits only
            if($Kit == 'true') {
                // This query is picking up cost for kit from sum of cost of individual components from docentrycost.
                $qrykitcost=" Union all
							SELECT distinct
							docentry.record#, 
							dochdr.record# as hdrrec,
							" . $custvend_select_clause . "
							" . $empcontact_select_clause. "
							docpar.sale_pur_trans,
							docpar.category,
							dochdr.docno,
							dochdr.docid,
							docpar.updinv,
							dochdr.whencreated,
							dochdr.shipviakey,
							dochdr.ponumber,
							decode(dochdr.state, 'O', 'IA.PENDING', 'G', 'IA.IN_PROGRESS', 'D', 'IA.CLOSED', 'I', 'IA.DRAFT', 'C', 'IA.CONVERTED',
							'L', 'IA.CONVERTED_BY_LINE', 'P', 'IA.PARTIALLY_CONVERTED', 'B', 'IA.PARTIALLY_CONVERTED_BY_LINE', 
							'E', 'IA.EXCEPTION', dochdr.state) as hdrstate,
							docentry.warehousekey,
							docentry.dochdrkey,
							docentry.itemkey,
							docentry.itemdescr,
							case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									(docentry.quantity ) * -1
								else
									(docentry.quantity )
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									(docentry.quantity )
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										(docentry.quantity) * -1
									else
										(docentry.quantity )
									end									
								end
							end quantity,
							decode(dept.dept_no, null, '', dept.dept_no || '--' || dept.title) as department,
							decode(loc.location_no, null, '', loc.location_no ||'--' || loc.name) as location,
							docentry.price,
							case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									docentry.value * -1
								else
									docentry.value
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									docentry.value
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										docentry.value * -1
									else
    									docentry.value
									end									
								end
							 end value,
                             case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									sum(nvl(docentrycost.cost,0)) * -1
								else
									sum(nvl(docentrycost.cost, 0))
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									sum(nvl(docentrycost.cost,0))
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										sum(nvl(docentrycost.cost,0)) * -1
									else
										sum(nvl(docentrycost.cost,0))
									end									
								end
							 end cost, 
                             case when docpar.in_out = 'D' then 
								case when docpar.sale_pur_trans != 'S' then 
									(docentry.value - sum(nvl(docentrycost.cost,0))) * -1
								else
									(docentry.value - sum(nvl(docentrycost.cost,0)))
								end
							else 
								case when docpar.sale_pur_trans = 'P' then 
									(docentry.value - sum(nvl(docentrycost.cost,0)))
								else
									case when docpar.sale_pur_trans = 'S' and docpartotals.sign = 1 and ictotal.name='ONHAND' then 
										(docentry.value - sum(nvl(docentrycost.cost,0))) * -1
									else
										(docentry.value - sum(nvl(docentrycost.cost,0)))
									end									
								end
							 end margin, 
							icuom.unit as uom,
							icitem.productlinekey as productlinekey,
							dochdr.melocationkey DOCOWNERLOC,
							docpar.locationkey DOCPAROWNERLOC,
							icitem.locationkey ITOWNERLOC,
							icw.locationkey WHOWNERLOC, icitem.upc
						FROM dochdrmst dochdr, docparmst docpar, docentry,docentrycost, icuom, icuomgrp, icitemmst icitem, docpartotals,ictotal, icwarehouse icw, locationmst loc, department dept $qry_custvendtable
						WHERE							
							icitem.cny# = :1 and
							icuomgrp.cny# (+) = icitem.cny# and 
							icuomgrp.record# (+) = icitem.uomgrpkey and
							icuom.grpkey (+) = icuomgrp.record# and
							icuom.cny# (+) = icuomgrp.cny# and
							icuom.isbase (+) = 'T'	and		
							docentry.cny# = :1 and
							icw.cny# (+) = :1 and
							loc.cny# (+) = :1 and
							dept.cny# (+) = :1 and
							docpar.cny# = :1 and
							dochdr.cny# = :1 and
							docentry.locationkey = loc.record#(+) and
							docentry.deptkey = dept.record#(+) and
							docentry.cny# = docentrycost.cny#(+) and
							docentry.record# = docentrycost.docentrykey(+) and							
							icitem.itemid = docentry.itemkey and
							icw.location_no (+) = docentry.warehousekey and
							docentry.dochdrkey = dochdr.record# and
							docpar.record# = dochdr.docparkey and
							docpar.cny# = docpartotals.cny#(+) and
							docpar.record# = docpartotals.docparkey(+) and
							docpartotals.cny# = ictotal.cny#(+) and
							docpartotals.totalkey = ictotal.record#(+) and
							icitem.itemtype='K' and " .
                $where_custvendselect . " " .
                $SPT_flag_clause . " " .
                $state_clause . " " .
                $docclass_clause . " " .
                $doctype_clause . " " .
                $prodline_clause . " " .
                $custvendid_clause . " " .
                $empcontact_clause . " " .
                $territory_where_clause . " " .
                $custvendcny_clause . " " .
                $backorderclause . " " .
                "docentry.itemkey  >= :2 and
							docentry.itemkey  <= :3 and
							dochdr.whencreated >= :4 and
							dochdr.whencreated <= :5
							$filterdept
							$filterlocation	";

                $qryselect3=$qryselect3 . " " . $qrykitcost;
                $qryselect3=$qryselect3 . " " . $groupbyClause. ",docpartotals.sign,ictotal.name";
            }

            $args[0] = $qryselect3;

            $docnew = QueryResult($args);
            $this->flat = array();

            $rowkey = 1;

            foreach ($docnew as $entry){
                $entry['intacctsortkey'] = 'A' . $rowkey++;
                $entry['IDHREF'] = "javascript:drilldown(0,'" . urlencode($entry['ID']) . "', '$entry[ENOWNERLOC]');";
                $entry['ITEMKEYHREF'] = "javascript:drilldown(1,'" . urlencode($entry['ITEMKEY']) . "', '$entry[ITOWNERLOC]');";
                $entry['DOCIDHREF'] = "javascript:drilldown(2,'" . urlencode($entry['DOCID']) . "','$entry[DOCOWNERLOC]');";
                $entry['PRODUCTLINEKEYHREF'] = "javascript:drilldown(3,'" . urlencode($entry['PRODUCTLINEKEY']) . "');";
                $entry['WAREHOUSEKEYHREF'] = "javascript:drilldown(4,'" . urlencode($entry['WAREHOUSEKEY']) . "', '$entry[ITOWNERLOC]');";

                $entry['ITEMKEY'] = $this->params['REPORTON'] == 'ITEMID' ? $entry['ITEMKEY'] : $entry['UPC'];
                $entry['ITEMDESCR'] = $this->params['REPORTON'] == 'ITEMID' ? $entry['ITEMDESCR'] :'';

                if (!$this->_ismcpEnabled) {
                    $entry['VALUE'] = iround($entry['VALUE'], 2);
                }
                $this->flat[] = $entry;
            }
            return true;
    }


    /**
     * @return array
     */

    function DoMap()
    {
        //
        // Now do the filtering, calculating, sorting, and exploding...
        //
        $this->DoCalcFilterSort();
        $this->DoTreeMangle();

        $itemsMap = $this->tree;
        $totalsMap = $this->totals;

        $lines = $this->DrawHeader($this->params);

        if (count($itemsMap)==0) {
            $itemsMap['NODATA'][0]= array('NODATA'=>'1');
        }
        $lines = $this->InvCommonBody($lines, $itemsMap);
        if ( !empty($totalsMap) ) {
            $lines = $this->InvCommonBody($lines, $totalsMap);
        }
        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        return $lines;

    }


}
