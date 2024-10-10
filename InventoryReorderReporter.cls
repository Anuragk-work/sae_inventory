<?php
import('InventoryReporter');

/**
 * Class InventoryReorderReporter
 */
class InventoryReorderReporter extends InventoryReporter
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        $params['report'] = 'invreorder';
        $params['ops'] = array(
                                    'inv/lists/item/view',
                                    'inv/lists/warehouse/view',
                                    'inv/lists/vendor/view'
                                    );
        $params['whereclause']['vend'] = "WHERE 
								docpar.cny# = dochdr.cny# and
								vendor.cny# = dochdr.cny# and 
								dochdr.vendentity = vendor.entity and 
								docpar.docclass = 'ORDER' and 
								docpar.sale_pur_trans = 'P' and
								docpar.in_out = 'I' and 
								state = 'O' and 
								vendor.vendorid >= ? and
								vendor.vendorid <= ? and
								dochdr.whendue >= ? and 
								dochdr.whendue <= ? and 
								dochdr.cny# = ? ";

        $params['whereclause']['cust'] = "WHERE 
								docpar.cny# = dochdr.cny# and
								vendor.cny# = dochdr.cny# and 
								dochdr.custentity = customer.entity and 
								docpar.docclass = 'ORDER' and 
								docpar.sale_pur_trans = 'P' and
								docpar.in_out = 'I' and 
								state = 'O' and 
								vendor.customerid >= ? and
								vendor.customerid <= ? and
								dochdr.whendue >= ? and 
								dochdr.whendue <= ? and 
								dochdr.cny# = ? ";
        parent::__construct($params);
    }


    /**
     * @return bool
     */
    public function DoQuery()
    {
        $this->ValidateReport();

        $params = $this->params['safe'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];

        $fromvendorid            = $params['FROMVENDORID'];
        $tovendorid                = $params['TOVENDORID'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];
        $gReport['ROUNDING']    = 'C';


        $cny = GetMyCompany();

        $itemlistargtypes = array( 'integer');
        $itemlistargs        = array($cny);

        $whselistargtypes = array( 'integer','integer','text', 'text');
        $whselistargs        = array($cny,  $cny, $fromvendorid, $tovendorid);

        $vendlistargtypes   = array('integer','text', 'text', 'integer','text', 'text');
        $vendlistargs        = array($cny, $fromvendorid, $tovendorid, $cny, $fromvendorid, $tovendorid);

        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues);

                if ( $itemupcargs != '' ) {
                    array_push($itemlistargtypes, 'text');
                    array_push($itemlistargs, $itemupcargs);

                    array_push($whselistargtypes, 'text');
                    array_push($whselistargs, $itemupcargs);

                    array_push($vendlistargtypes, 'text');
                    array_push($vendlistargs, $itemupcargs);
                }
            } else {
                $filterItemorUPC = " icitem.status='T' and icitem.itemid >= ? and icitem.itemid <= ? ";
                
                array_push($itemlistargtypes, 'text', 'text');
                array_push($itemlistargs, $fromitemid, $toitemid);

                array_push($whselistargtypes, 'text', 'text');
                array_push($whselistargs, $fromitemid, $toitemid);

                array_push($vendlistargtypes, 'text', 'text');
                array_push($vendlistargs, $fromitemid, $toitemid);
            }
        }else {
            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues);

                if ( $itemupcargs != '' ) {
                    array_push($itemlistargtypes, 'text');
                    array_push($itemlistargs, $itemupcargs);

                    array_push($whselistargtypes, 'text');
                    array_push($whselistargs, $itemupcargs);

                    array_push($vendlistargtypes, 'text');
                    array_push($vendlistargs, $itemupcargs);
                }
            } else {
                $filterItemorUPC = " icitem.status='T' and icitem.upc >= ? and icitem.upc <= ? ";

                array_push($itemlistargtypes, 'text', 'text');
                array_push($itemlistargs, $fromupc, $toupc);

                array_push($whselistargtypes, 'text', 'text');
                array_push($whselistargs, $fromupc, $toupc);

                array_push($vendlistargtypes, 'text', 'text');
                array_push($vendlistargs, $fromupc, $toupc);
            }
        }

        $qryselect3 = "SELECT DISTINCT icitem.itemid as itemkey, 
									icitem.name as itemdescr, icitem.upc
							FROM icitem WHERE icitem.cny# = ? and 
								$filterItemorUPC ";
            
        if ($fromvendorid === VARCHAR2_MIN || $tovendorid === VARCHAR2_MAX) {
            $whseClause = ' or icitemvendor.vendorid is null';
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $qryselect5 = "SELECT  icitem.itemid as itemkey
							FROM icitem, icitemvendor 
							WHERE icitem.cny# = ? and 
							icitemvendor.cny# (+)= icitem.cny# and
							icitemvendor.itemkey (+)= icitem.itemid and
							((icitemvendor.vendorid >= ? and icitemvendor.vendorid <= ?) $whseClause) and
							$filterItemorUPC "; 

        $qryselect4 = "SELECT	icitemwhse.itemkey as whseitemkey,
									icitemwhse.warehousekey,
									icwarehouse.name as warehousename,
									icitemwhse.default_subsection,
									icitemwhse.cycle,
									icitemwhse.reorder_method,
									icitemwhse.economic_order_qty,
									icitemwhse.reorder_point,
									icitemwhse.min_order_qty,
									icitemwhse.max_order_qty,
									icitemwhse.min_stock,
									icitemwhse.max_stock,
									icitemwhse.last_cost
									FROM icitemwhse, icwarehouse
							WHERE 
								icitemwhse.cny# = icitemwhse.cny# and 
								icitemwhse.cny# = ? and
								icitemwhse.warehousekey = icwarehouse.location_no and
								icwarehouse.cny# = icitemwhse.cny# and 
								icitemwhse.itemkey in ( " . $qryselect5 . ")";
            
        $qryselect6 = "SELECT	icitemvendor.itemkey as venditemkey,
									vendor.name as vendorname,
									vendor.vendorid,
									icitemvendor.priority,
									icitemvendor.stock_number,
									icitemvendor.lead_time,
									icitemvendor.economic_order_qty,
									icitemvendor.min_order_qty,
									icitemvendor.max_order_qty,
									icitemvendor.best_cost,
									icitemvendor.last_cost
									from vendormst vendor, icitemvendor WHERE vendor.cny# = icitemvendor.cny# and 
									vendor.vendorid = icitemvendor.vendorid and 
									icitemvendor.cny# = ? and 
									((icitemvendor.vendorid >= ? and icitemvendor.vendorid <= ?) $whseClause) and
									icitemvendor.itemkey in ( " . $qryselect5 . ")";
    
        $itemlistcode = array( 'QUERY' => $qryselect3, 'ARGTYPES' => $itemlistargtypes);
        $whselistcode = array( 'QUERY' => $qryselect4, 'ARGTYPES' => $whselistargtypes);
        $vendlistcode = array( 'QUERY' => $qryselect6, 'ARGTYPES' => $vendlistargtypes);

        $itemlist = $this->_QM->DoCustomQuery($itemlistcode, $itemlistargs, true);
        $whselist = $this->_QM->DoCustomQuery($whselistcode, $whselistargs, true);
        $vendlist = $this->_QM->DoCustomQuery($vendlistcode, $vendlistargs, true);

        $this->_items = array('itemlist' => $itemlist, 'whselist' => $whselist, 'vendlist' => $vendlist);

        return true;
    }


    /**
     * @return array|bool
     */
    public function DoMap()
    {
        $qrysaleqty = "SELECT sum(posquantity)+sum(negquantity) as salequantity
				FROM icitemtotals, ictotal
				WHERE
					icitemtotals.totalkey = ictotal.record# and
					ictotal.name = 'ONHOLD' and
					icitemtotals.cny# = ? and
					icitemtotals.cny# = ictotal.cny# and
					icitemtotals.itemkey = ? and 
					icitemtotals.warehousekey = ?";

        $qrypurchqty = "SELECT sum(posquantity)+sum(negquantity) as purchquantity
				FROM icitemtotals, ictotal
				WHERE
					icitemtotals.totalkey = ictotal.record# and
					ictotal.name = 'ONORDER' and
					icitemtotals.cny# = ? and
					icitemtotals.cny# = ictotal.cny# and
					icitemtotals.itemkey = ? and 
					icitemtotals.warehousekey = ?";
                    
        $qryonhandqty = "SELECT sum(posquantity)+sum(negquantity) as onhandquantity
				FROM icitemtotals, ictotal
				WHERE
					icitemtotals.totalkey = ictotal.record# and
					ictotal.name = 'ONHAND' and
					icitemtotals.cny# = ? and
					icitemtotals.cny# = ictotal.cny# and
					icitemtotals.itemkey = ? and
					icitemtotals.warehousekey = ?";

        $cny = GetMyCompany();

        $itemsMap = array();

        $itemlist = $this->_items['itemlist'];
        $whselist = $this->_items['whselist'];
        $vendlist = $this->_items['vendlist'];

        // for each different item that we found
        foreach($itemlist as $item){

            $item['ITEMHREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($item['ITEMKEY'])) . "');";

            $flag = 0; // set flag to zero, assume we don't need to reorder this item
            $itemkey = $item['ITEMKEY'];            
            $item['ITEMKEY'] = $this->params['REPORTON'] == 'ITEMID' ? $item['ITEMKEY'] : $item['UPC'];
            $item['ITEMDESCR'] = $this->params['REPORTON'] == 'ITEMID' ? $item['ITEMDESCR'] : '';

            $thisline = $item;
            // 			$thisline['TOTALVALUE'] = $itemtotal;
            // 			$thisline['TOTALQUANTITY'] = $itemquantity;

            $thisline['HASVENDORS']="no";
            // look thru all the warehouses
            $numofentries=0;
            foreach($whselist as $whse){
                // for this item/whse
                if ($whse['WHSEITEMKEY']==$itemkey) {
                    $whsekey = $whse['WAREHOUSEKEY'];
                    $econreorder = $whse['ECONOMIC_ORDER_QTY'];
                    $reorderpoint = $whse['REORDER_POINT'];
                    $minstock = $whse['MIN_STOCK'];
                    $maxstock = $whse['MAX_STOCK'];
                    $method = $whse['REORDER_METHOD'];
                    $minorder = $whse['MIN_ORDER_QTY'];
                    $maxorder = $whse['MAX_ORDER_QTY'];
                    
                    // 					If the item's warehouse info doesn't have 'REORDER_METHOD', then get it from Inventory Setup, else go with item's warehouse 'REORDER_METHOD'
                    // 					Especially this is for existing items - Bug #32499

                    if (!isset($method) && $method=='') {
                        global $kINVid;
        
                        GetModulePreferences($kINVid, $invPrefs);

                        if (isset($invPrefs['REORDER_METHOD'])) {
                            $method = $invPrefs['REORDER_METHOD'];
                            $whse['REORDER_METHOD'] = $method;

                        }

                    }

                    $purchlistcode = array( 'QUERY' => $qrypurchqty, 'ARGTYPES' => array( 'integer','text','text'));
                    $purchlist = $this->_QM->DoCustomQuery($purchlistcode, array($cny, $itemkey, $whsekey), true);
                    $purch = $purchlist[0];
                    $onpurchaseorder = 0 + $purch['PURCHQUANTITY'];

                    $salelistcode = array( 'QUERY' => $qrysaleqty, 'ARGTYPES' => array( 'integer','text','text'));
                    $salelist = $this->_QM->DoCustomQuery($salelistcode, array($cny, $itemkey, $whsekey), true);
                    $sale = $salelist[0];
                    $onsaleorder = 0 + $sale['SALEQUANTITY'];


                    $onhandlistcode = array( 'QUERY' => $qryonhandqty, 'ARGTYPES' => array( 'integer','text','text'));
                    $onhandlist = $this->_QM->DoCustomQuery($onhandlistcode, array($cny, $itemkey, $whsekey), true);
                    $onhand = $onhandlist[0];
                    $onhandorder = 0 + $onhand['ONHANDQUANTITY'];

                    
                    $totalavail = $onhandorder + $onpurchaseorder - $onsaleorder;
                    // decide if we need to order more
                    if ($totalavail <= $reorderpoint) {


                        // yes, how shouls we calc the amount of reorder?
                        switch($method){
                        case 'ECONOMIC':
                            $sugorder = $maxstock - $totalavail;                            
                            $minorder = $econreorder; //override the min order with the econ ordery
                            break;
                        case 'MAX_LEVEL':
                            $sugorder = $maxstock - $totalavail;
                            break;
                        case 'REORDER_POINT':
                            $sugorder = $minstock - $totalavail;                                
                            break;
                        }
                        
                        // now make sure we're not ordering more or less than the min/max order qty, if they are set
                        // these apply *regardless* of reorder methods!
                        if ($minorder != '') {
                            /** @noinspection PhpUndefinedVariableInspection */
                            if ( $sugorder < $minorder) {
                                $sugorder = $minorder;
                            }
                        }
                        if ($maxorder != '') {
                            /** @noinspection PhpUndefinedVariableInspection */
                            if ( $sugorder > $maxorder) {
                                $sugorder = $maxorder;
                            }
                        }
                        // one final sanity check - we can't suggest ordering a negative amount
                        /** @noinspection PhpUndefinedVariableInspection */
                        if ( $sugorder <= 0) {
                            $sugorder = 0;
                        }
                        // now make sure we would not exceed our stock levels with the suggested order
                        if ($sugorder > 0 && $sugorder + $totalavail <= $maxstock) {
                        
                            $flag = 1; // set flag, yes we need to reorder this
                        
                            $whse['WAREHOUSEHREF'] = "javascript:drilldown(1,'" . urlencode($whse['WAREHOUSEKEY']) . "');";
                            $whse['ON_ORDER'] = $onpurchaseorder;
                            $whse['ON_SALES_ORDER'] = $onsaleorder;
                            $whse['ON_HAND'] = $onhandorder;
                            $whse['TOTAL_AVAIL'] = $totalavail; 
                            $whse['SUGGESTED_ORDER'] = $sugorder;
                            $thisline['WAREHOUSES'][$numofentries] = $whse;
                            $numofentries++;
                        }
                    } 
                }
            }
            // look thru all the vendors
            $numofentries=0;
            foreach($vendlist as $vend){
                if ($vend['VENDITEMKEY']==$itemkey) {
                    $thisline['HASVENDORS']="yes";    
                    $vend['BEST_COST'] = glFormatCurrency($vend['BEST_COST']);
                    $vend['LAST_COST'] = glFormatCurrency($vend['LAST_COST']);
                    $vend['VENDORHREF'] = "javascript:drilldown(2,'" . urlencode($vend['VENDORID']) . "');";
                    $thisline['VENDORS'][$numofentries] = $vend;
                    $numofentries++;
                }
            }
            
            if ($flag==1) { // only put this line in the report if we need to reorder it!
                $itemsMap[] = $thisline;
            }
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $itemsMap); 
        // $lines = $this->InvCommonTotals($lines,$totalsMap); 
        //eppp_p($lines);dieFL();
        //eppp_p($itemsMap);
        return $lines;
    }


    /**
     *
     */
    public function ValidateReport()
    {
        // we don't require a date, so don't verify the dates
        $this->ParamTweaks();
    }
}

