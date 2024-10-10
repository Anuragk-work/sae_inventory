<?php
import('InventoryReporter');
//  class InventoryOrdersReporter extends InventoryReporter 
class InventoryOrdersReporter extends InventoryReporter
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct($params);

        $mod = Request::$r->_mod;
        $this->_ismcpEnabled = IsMCPEnabled($mod);
    }

    /**
     * @return bool
     */
    public function DoQuery()
    {
        $this->ValidateReport();
        $this->params['safe']['FILTERTRANSACTIONS'] = $this->params['FILTERTRANSACTIONS'];
        $params = $this->params['safe'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $fromcustid                = $params['FROMCUSTOMERID'];
        $tocustid                = $params['TOCUSTOMERID'];
        $dt1                    = $params['dt1'];
        $dt2                    = $params['dt2'];
        $fromwhseid                = $params['FROMWAREHOUSEID'];
        $towhseid                = $params['TOWAREHOUSEID'];
        $orderstate                = $params['ORDERSTATE'];
        $gReport['ROUNDING']    = 'C';
        $excludebackorder        = $this->params['EXCLBACKORDER'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];

        $cny = GetMyCompany();

        $filterlocation = $this->_getLocationClause($params, 'docentry');
        $filterdept = $this->_getDeptClause($params, 'docentry');

        if (!isset($orderstate) ) {
            $orderstate = "Posted Open Orders";
        }

        switch ($orderstate){
        case 'Draft Orders':
             $stateclause = "dochdr.state = 'I' and ";
            break;
        case 'Posted Open Orders':
            $stateclause = "dochdr.state in('O', 'P', 'B') and ";
            break;

        case 'Closed Orders':
            $stateclause = "dochdr.state in ('C', 'L') and ";

            break;

        case 'All Orders':
            // if both states, we don't need any clause
            // This will need to change for Sameer's stuff!!!! tgw
            $stateclause = "";
            break;
        default:
            $stateclause = "";
        }

        $backorderclause = "";
        if ($excludebackorder == 'true') {
            $backorderclause = "(dochdr.backorder != 'T' or dochdr.backorder is null) and";
        }
        
        $fromcustvendid = $fromcustid;
        $tocustvendid = $tocustid;

        $args = array('sql', $cny, $fromcustvendid, $tocustvendid, $fromwhseid, $towhseid);
        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues, 6);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                //}

            } else {
                $filterItemorUPC = " icitem.itemid  >= :6 and icitem.itemid  <= :7 ";
                array_push($args, $fromitemid, $toitemid);
            }
        }else {

            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues, 6);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                //}
            } else {
                $filterItemorUPC = " icitem.upc  >= :6 and icitem.upc  <= :7 ";
                array_push($args, $fromupc, $toupc);
            }
        }
        array_push($args, $dt1, $dt2);

        $currencyfilter="";
        if($this->_ismcpEnabled) {
            $baseCurrency = GetBaseCurrency();

            $selectpricevalue = "docentry.currency, (docentry.price / nvl(docentry.exchange_rate,1)) price, (docentry.value / nvl(docentry.exchange_rate,1)) value,";
            if($this->params['CURRENCY']!='') {
                $currencyfilter = " and DECODE(docentry.currency, NULL, '$baseCurrency', docentry.currency) = '".$this->params['CURRENCY']."'";
            }
        }else{
            $selectpricevalue="docentry.price, docentry.value,";
        }
        //Here we will not pick the docentries  which doesn't have any warehouse (Ex: non-inventory items) if we are viewing the report with any 'To Warehouse'.

        $filterWarehouse = ($towhseid != VARCHAR2_MAX) ? " (docentry.warehousekey between :4 and :5) and " : " (docentry.warehousekey between :4 and :5 or docentry.warehousekey is null) and ";
        //$selectpricevalue="docentry.price, docentry.value,";
        $whereclause = "WHERE
						docentry.cny# = :1 and
						icitem.cny# = :1 and
						docpar.cny# = :1 and
						customer.cny# = :1 and
						contactversion.cny# (+) = :1 and
						mailaddress.cny# (+) = :1 and
						shipmethod.cny# (+) = :1 and
						dochdr.cny# = :1 and
						docentry.dochdrkey = dochdr.record# and
						icitem.itemid = docentry.itemkey and
						docpar.record# = dochdr.docparkey and
						dochdr.custentity = customer.entity and
						contactversion.record# (+) = dochdr.shiptokey and
						mailaddress.record# (+) = contactversion.mailaddrkey and
						shipmethod.record# (+) = dochdr.shipviakey and
						docpar.category = 'O' and
						docpar.sale_pur_trans = 'S' and
						" . $stateclause . $backorderclause . "
						customer.customerid between :2 and :3 and
						
						$filterWarehouse
						$filterItemorUPC and
						dochdr.whendue between :8 and :9
						$currencyfilter 
						";

        $qryselect1 = "SELECT DISTINCT	dochdr.record# as hdrrec,
							customer.customerid as id,
							customer.name as name,
							dochdr.docno,
							dochdr.docid,
							docpar.updinv,
							dochdr.whendue,
							dochdr.shipviakey,
							dochdr.melocationkey,
							shipmethod.name as shipmethodname,
							mailaddress.addr1,
							mailaddress.addr2,
							mailaddress.city,
							mailaddress.state,
							mailaddress.zip,
							mailaddress.country,
							to_char(to_date(dochdr.whendue)-SYSDATE,'9999999') as daystodue
							FROM docpar, dochdr, docentry, customer, contactversion, mailaddress, shipmethod, icitem 
							$whereclause $filterdept $filterlocation
							ORDER BY customer.name, dochdr.docno";


        $qryselect2 = "SELECT docentry.dochdrkey,
								docentry.record#,
								docentry.itemkey,
								docentry.itemdescr,
								docentry.quantity,
								$selectpricevalue
								docentry.warehousekey,
								decode(dept.dept_no, null, '', dept.dept_no || '--' || dept.title) as department,
								decode(loc.location_no, null, '', loc.location_no ||'--' || loc.name) as location,
								icitemwhse.default_subsection,
								icitemtotals.qtyonhand as quantityonhand,
								icuom.unit as uom, icitem.upc
							FROM docentry, icitemwhse, v_itemavail icitemtotals, icuom, icuomgrp, icitem, location loc, department dept
							WHERE
								docentry.dochdrkey in (
									SELECT DISTINCT dochdr.record# as dochdrkey
									FROM docpar, dochdr, docentry, customer, contactversion, mailaddress, shipmethod, icitem
									" . $whereclause . ") and								
								icuomgrp.cny# (+) = icitem.cny# and 
								icuomgrp.record# (+) = icitem.uomgrpkey and
								icuom.grpkey (+) = icuomgrp.record# and
								icuom.cny# (+) = icuomgrp.cny# and
								icuom.isbase (+) = 'T'	and
								icitem.cny# = :1 and
								docentry.cny# = :1 and
								icitemwhse.cny#(+) = :1 and
								icitemtotals.cny# (+) = :1 and
								loc.cny# (+) = :1 and
								dept.cny# (+) = :1 and 
								$filterItemorUPC and
								docentry.locationkey = loc.record#(+) and
								docentry.deptkey = dept.record#(+) and
								$filterWarehouse
								icitemtotals.itemkey (+) = docentry.itemkey and
								icitemtotals.warehousekey (+) = docentry.warehousekey and
								icitemwhse.itemkey(+) = docentry.itemkey and
								icitemwhse.warehousekey(+) = docentry.warehousekey and								
								icitem.itemid = docentry.itemkey 
								$filterdept $filterlocation 
								ORDER BY
									docentry.warehousekey,
									icitemwhse.default_subsection,
									docentry.itemkey,
									docentry.dochdrkey";


        $args[0]    = $qryselect1;
        $dochdr     = QueryResult($args);

        $args[0]    = $qryselect2;
        $docentry     = QueryResult($args);

        $docs = array();
        /** @noinspection PhpUndefinedVariableInspection */
        $locref = $locs[0];
        // It should be working with this to fix the inspection, but needs further investigation to make sure it does work
        //$locref = $params['locs'][0];

        foreach($dochdr as $row){
            $thisdoc = $row['HDRREC'];
            $loclink = $row['MELOCATIONKEY'] ?? $locref;
            $docs[$thisdoc] = array(
            'HDRREC'        => $thisdoc,
            'ID'             => $row['ID'],
            'IDHREF'        => "javascript:drilldown(0,'" . urlencode($row['ID']) . "');",
            'NAME'             => $row['NAME'],
            'DOCNO'            => $row['DOCNO'],
            'DOCID'            => $row['DOCID'],
            'DOCIDHREF'        => "javascript:drilldown(2,'" . urlencode($row['DOCID']) . "','$loclink');",
            'WHENDUE'         => $row['WHENDUE'],
            'DAYSTODUE'        => trim($row['DAYSTODUE']),
            'SHIPVIAKEY'    => $row['SHIPVIAKEY'],
            'SHIPMETHODNAME'=> $row['SHIPMETHODNAME'],
            'ADDR1'            => $row['ADDR1'],
            'ADDR2'            => $row['ADDR2'],
            'CITY'            => $row['CITY'],
            'STATE'            => $row['STATE'],
            'ZIP'            => $row['ZIP'],
            'COUNTRY'        => $row['COUNTRY'],
                                );

            if ( strtotime($row['WHENDUE'])<time() ) {
                // the date was in the past, note this so the xsl can format things if they want
                $docs[$thisdoc]['INPAST'] = "yes";
            } else {
                $docs[$thisdoc]['INPAST'] = "no";
            }
        }

        foreach( $docentry as $entryrow ){
            $dockey         = $entryrow['DOCHDRKEY'];
            $recordno        = $entryrow['RECORD#'];
            $itemkey         = $entryrow['ITEMKEY'];

            $warehousekey     = $entryrow['WAREHOUSEKEY'];
            if ($warehousekey == "") {
                $warehousekey = "No Warehouse";
            }

            $entry = array(
            'DOCHDRKEY'     => $dockey,
            'RECORDKEY'        => $recordno,
            'ITEMKEY'        =>  $this->params['REPORTON'] == 'ITEMID' ? $itemkey : $entryrow['UPC'],
            'ITEMKEYHREF'    => "javascript:drilldown(1,'" . urlencode(addslashes($itemkey)) . "');",
            'ITEMDESCR'        => $this->params['REPORTON'] == 'ITEMID' ?$entryrow['ITEMDESCR'] : '',
            'WAREHOUSEKEY'    => $warehousekey,
            'UOM'            => $entryrow['UOM'],
            'QUANTITY'        => $entryrow['QUANTITY'],
            'QUANTITYONHAND'=> $entryrow['QUANTITYONHAND'],
            'SUBSECTION'    => $entryrow['DEFAULT_SUBSECTION'],
            'PRICE'            => $this->roundUnitCost($itemkey, $entryrow['PRICE']),
            'VALUE'            => $entryrow['VALUE'],
            'DEPARTMENT'    => $entryrow['DEPARTMENT'],
            'LOCATION'        => $entryrow['LOCATION'],
            );
            if ( $entry['QUANTITYONHAND'] == '' ) {
                $entry['QUANTITYONHAND'] = 0;
            }
            $docs[$dockey]['WAREHOUSES'][$warehousekey]['WAREHOUSEKEY'] = $warehousekey;
            //$docs[$dockey]['WAREHOUSES'][$warehousekey]['ENTRIES'][$itemkey] = $entry;
            $docs[$dockey]['WAREHOUSES'][$warehousekey]['ENTRIES'][$recordno] = $entry;

        }

        $movethesefields = array(
        'HDRREC',
        'ID',
        'IDHREF',
        'NAME',
        'DOCNO',
        'DOCID',
        'DOCIDHREF',
        'WHENDUE',
        'DAYSTODUE',
        'SHIPVIAKEY',
        'SHIPMETHODNAME',
        'ADDR1',
        'ADDR2',
        'CITY',
        'STATE',
        'ZIP',
        'COUNTRY',
        'INPAST',
        );

        $movethesefields2 = array(
        'DOCHDRKEY',
        'RECORDKEY',
        'ITEMKEY',
        'ITEMKEYHREF',
        'ITEMDESCR',
        'WAREHOUSEKEY',
        'UOM',
        'QUANTITY',
        'QUANTITYONHAND',
        'QTYREQUIRED',
        'SUBSECTION',
        'PRICE',
        'VALUE',
        'DEPARTMENT',
        'LOCATION',
        );

        // now that we've built our nice tree structure, flatten it so the filtering and sorting on any field becomes easy.

        $flat = array();
        $rowkey = 0; // rowkey gives each row a unique key that we use for sorting purposes.
        foreach ($docs as $doc){
            $whses = $doc['WAREHOUSES'];
            foreach ($whses as $whse){
                $entry = $whse['ENTRIES'];
                foreach ($entry as $thisentry){
                    $row = array();
                    foreach ($movethesefields as $field){
                        $row[$field] = $doc[$field];
                    }
                    foreach ($movethesefields2 as $field){
                        $row[$field] = $thisentry[$field];
                    }
                    $row['intacctsortkey'] = 'A' . $rowkey++;

                    $flat[] = $row;
                }
            }
        }
        $this->flat = $flat;
        return true;

    }

    /**
     * @return array|bool
     */
    public function DoMap()
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
        if ( count($totalsMap ?? []) != 0 ) {
            $lines = $this->InvCommonBody($lines, $totalsMap);
        }
        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];
        
        return $lines;

    }
}

