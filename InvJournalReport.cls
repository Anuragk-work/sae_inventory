<?php
import('InventoryReporter');

/**
 * Class InvJournalReport
 */
class InvJournalReport extends InventoryReporter
{
    /** @var string $prodlineid */
    protected $prodlineid = '';

    /**
     * @param array $params
     */
    function __construct($params)
    {
        //
        // Don't change the order of the 'ops' as its indices are used to fetch the required op
        // params['ops'] is used in DoMap()
        parent::__construct(
            INTACCTarray_merge(
                $params, 
                array(
                'report' => 'invjournal',
                'fields' =>  array ('FROMITEMID','TOITEMID','FROMWAREHOUSEID',
                                        'TOWAREHOUSEID', 'START_DATE','END_DATE'),
                'helpfile' => 'Adding_Editing_and_Viewing_Journals',
                'ops'    => array(
                                    "inv/lists/invdocument/view",
                                    "inv/lists/item/view",
                                    "inv/lists/warehouse/view",
                                    "so/lists/sodocument/view",
                                    "po/lists/podocument/view",
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
        $this->ValidateReport();
        $params = $this->params['safe'];

        $dt1    = $params['dt1'];
        $dt2    = $params['dt2'];
        $trans    = $params['trans'];
        $fromitemid        = $params['FROMITEMID'];
        $toitemid        = $params['TOITEMID'];
        $fromwhid        = $params['FROMWAREHOUSEID'];
        $towhid        = $params['TOWAREHOUSEID'];
        $ReportOn        = $this->params['REPORTON'];
        $fromupc        = $params['FROMUPC'];
        $toupc            = $params['TOUPC'];
        $ItemOperator    = $this->params['ITEMOPERATOR'];
        $itemValues        = $this->params['ITEMVALUES'];
        $UPCOperator    = $this->params['UPCOPERATOR'];
        $upcValues        = $this->params['UPCVALUES'];
        $this->prodlineid			= $params['PRODLINEID'];
        $gReport['ROUNDING']    = 'C';

        $doctype_clause = " and docpar.updinv in ('V', 'T') ";
        if ($trans != '%') {
            $doctypes = explode('#~#', $trans);
            $doctype_clause = PrepINClauseStmt($doctype_clause.' and ', $doctypes, ' docpar.docid ', false, 'dummy', true);
        }
        $doctype_clause .= ' and ';

        $cny = GetMyCompany();
        $docentryargtypes = array();
        $docentryargs      = array();

        /*
         * Prepare the Product Line QRY string to use it to filter items by product line info
         */
        if ($this->prodlineid != '%') {
            $this->prepareProductLineMapQry($this->prodlineid,'it');
        }

        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'it', 'itemid', $itemValues);
                if($itemupcargs!='') {
                    array_push($docentryargtypes, 'text');
                    array_push($docentryargs, $itemupcargs);
                }
            } else {
                $filterItemorUPC = " it.itemid  >= ? and it.itemid  <= ? ";
                array_push($docentryargtypes, 'text', 'text');
                array_push($docentryargs, $fromitemid, $toitemid);
            }
        }else {
            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'it', 'upc', $upcValues);
                if($itemupcargs!='') {
                    array_push($docentryargtypes, 'text');
                    array_push($docentryargs, $itemupcargs);
                }
            } else {
                $filterItemorUPC = " it.upc  >= ? and it.upc  <= ? ";
                array_push($docentryargtypes, 'text', 'text');
                array_push($docentryargs, $fromupc, $toupc);
            }
        }
        $filterWarehouse = '';
        if ( !($fromwhid == VARCHAR2_MIN && $towhid == VARCHAR2_MAX) ) {
            $filterWarehouse = " documententry.warehousekey  >= ? and documententry.warehousekey  <= ? and";
            array_push($docentryargtypes, 'text', 'text');
            array_push($docentryargs, $fromwhid, $towhid);
        }

           //  transaction document header query
           $dochdrselect = "SELECT dochdr.record#
											dochdrkey, 
											to_char(dochdr.whencreated, 'mm/dd/yyyy') whencreated, 
											dochdr.docid, 
											docpar.updinv,
											docpar.locationkey DOCPAROWNERLOC,
											dochdr.melocationkey DOCOWNERLOC,
											docpar.sale_pur_trans
									FROM	dochdrmst dochdr, docparmst docpar
									WHERE	docpar.record# (+) = dochdr.docparkey
											$doctype_clause
											(dochdr.whencreated >= ? and dochdr.whencreated <=? )
											and dochdr.cny# = ? 
											and docpar.cny# = dochdr.cny#
									order by dochdr.whencreated, docpar.docclass ";
           $dochdrargtypes = array('date', 'date', 'integer' );
           $dochdrargs     = array($dt1, $dt2, $cny);

           $code = array( 'QUERY' => $dochdrselect, 'ARGTYPES' => $dochdrargtypes);
        $dochdr = $this->_QM->DoCustomQuery($code, $dochdrargs, true);
        //eppp($dochdr);
        $this->_dochdr = $dochdr;
        //  got to add the productline join to get the productline description

        $filterlocation = $this->_getLocationClause($params, 'documententry');
        $filterdept = $this->_getDeptClause($params, 'documententry');
        
           $docentryselect = "SELECT dochdrkey, itemkey, item_description, unit, numdec, productlinekey, prodline,
                              warehousekey, warehouse, updinv, uom, docclass, SUM(qty) qty, price,
                              DOCPAROWNERLOC, DOCOWNERLOC, ITOWNERLOC, WHOWNERLOC
                            FROM (SELECT documententry.dochdrkey, documententry.itemkey, it.name item_description,
										icuom.unit, icuom.numdec, it.productlinekey, it.productlinekey||' - '||pl.description prodline, 
										documententry.warehousekey, documententry.warehousekey||' - '||wh.name warehouse, docpar.updinv, 
										documententry.unit uom, docpar.docclass, docentrycost.quantity qty,
										CASE
										  WHEN docpar.IN_OUT = 'D' OR (docpar.IN_OUT = 'I' AND docpar.SALE_PUR_TRANS = 'S')
		                                    THEN (docentrycost.cost/nullif(docentrycost.quantity, 0))
	                                      ELSE documententry.price
                                        END price,
										docpar.locationkey DOCPAROWNERLOC, dochdr.melocationkey DOCOWNERLOC, 
										it.locationkey ITOWNERLOC, wh.locationkey WHOWNERLOC
									FROM	docentry documententry,
									        docentrycost docentrycost,
											dochdrmst dochdr, 
											docparmst docpar, 
											icitemmst it, 
											icuom icuom,
											icuomgrp uomgrp, 
											icwarehouse wh, 
											icprodline pl
									WHERE	{$this->prodlineChildMapQry}
									        $filterItemorUPC
									        $filterlocation 
									        $filterdept
											$doctype_clause
											$filterWarehouse
											dochdr.whencreated >= ? and
											dochdr.whencreated <= ? and
											dochdr.record# (+) = documententry.dochdrkey and
											documententry.record# (+) = docentrycost.docentrykey and
                                            docentrycost.cny#= ? and
											documententry.cny# = ? and
											dochdr.cny# = ? and
											docpar.cny# = ? and
											it.cny# = $cny and 
											docpar.record# (+) = dochdr.docparkey and 
											it.itemid (+) = documententry.itemkey and
											uomgrp.cny# = it.cny# and
											uomgrp.record# = it.uomgrpkey and					
											icuom.cny# = uomgrp.cny# and
											icuom.isbase = 'T' and
											icuom.grpkey = uomgrp.record# and  
											pl.productlineid (+) = it.productlinekey and 
											pl.cny# (+) = $cny and 
											wh.location_no (+) = documententry.warehousekey and 
											wh.cny# (+) = $cny)
									group by dochdrkey, itemkey, item_description, unit, numdec, productlinekey, prodline,
                                      warehousekey, warehouse, updinv, uom, docclass,  price,
                                      DOCPAROWNERLOC, DOCOWNERLOC, ITOWNERLOC, WHOWNERLOC
                                    ORDER BY dochdrkey, itemkey, warehousekey";
           array_push($docentryargtypes, 'date', 'date', 'integer', 'integer', 'integer', 'integer');
           array_push($docentryargs, $dt1, $dt2, $cny, $cny, $cny, $cny);

           $code = array( 'QUERY' => $docentryselect, 'ARGTYPES' => $docentryargtypes);
        $docentry = $this->_QM->DoCustomQuery($code, $docentryargs, true);

        $this->_docentry = $docentry;

        return true;
    }

    /**
     * @return string[]
     */
    function DoMap()
    {
        $DocHdrMap = array();
        foreach($this->_dochdr as $row){
            $row['WHENCREATED'] = FormatDateForDisplay($row['WHENCREATED']);
            $DocHdrMap[$row['DOCHDRKEY']] = $row;
        }
        //eppp($DocHdrMap);

        $DocEntryMap = array();
        foreach($this->_docentry as $row){
            $DocEntryMap[$row['DOCHDRKEY']][] = $row;
        }

        $RepMap = array();
        foreach($DocHdrMap as $doc){
            $key        = $doc['DOCHDRKEY'];
            $entry      = $DocEntryMap[$key] ?? [];
            $entryCnt   = count($entry);
            if (!$entryCnt) {
                continue;
            }
            
            //$doc['DOCHREF'] = "javascript:drilldown(0,'" . urlencode($doc['DOCID']) . "');";
            $docInc = urlencode(addslashes($doc['DOCID']));

            //
            // The document respective ops are defined in $this->params['ops'];
            // Indices are in the order of the elements defined. Refer params['ops'] in the constructor.
            $modopIndex = array('I'=>0, 'S'=>3, 'P'=>4);
            $modop = $modopIndex[$doc['SALE_PUR_TRANS']];

            /** @noinspection PhpUndefinedVariableInspection */
            $doc['DOCHREF'] = "javascript:drilldown($modop,'$docInc', '$row[DOCOWNERLOC]');";

            $RepMap[$key] = $doc;
            $qtytot        = 0;
            $prctot        = 0;
            $costtot    = 0;
            
            for( $i=0; $i < $entryCnt; $i++ ){
                $round    = ($entry[$i]['NUMDEC'] ?: DEFAULT_INVPRECISION);

                //$RepMap[$key]['ENTRY'][$i]['ITEMHREF']	= "javascript:drilldown(1,'" . urlencode(addslashes($entry[$i]['ITEMKEY'])) . "');";
                $itemInc = urlencode(addslashes($entry[$i]['ITEMKEY']));
                $ItemOwnerLoc = $entry[$i]['ITOWNERLOC'];
                $RepMap[$key]['ENTRY'][$i]['ITEMHREF'] = "javascript:drilldown(1,'$itemInc', '$ItemOwnerLoc');";

                $RepMap[$key]['ENTRY'][$i]['ITEMKEY']        = $entry[$i]['ITEMKEY'];
                $RepMap[$key]['ENTRY'][$i]['ITEM_DESCRIPTION']            = $entry[$i]['ITEM_DESCRIPTION'];
                $RepMap[$key]['ENTRY'][$i]['UOM']            = $entry[$i]['UNIT'];

                $RepMap[$key]['ENTRY'][$i]['WAREHOUSEKEY']    = $entry[$i]['WAREHOUSEKEY'];
                //$RepMap[$key]['ENTRY'][$i]['WAREHOUSEHREF']	 = "javascript:drilldown(2,'" . urlencode($entry[$i]['WAREHOUSEKEY']) . "');";
                $whInc = urlencode(addslashes($entry[$i]['WAREHOUSEKEY']));
                $WHOwnerLoc = $entry[$i]['WHOWNERLOC'];
                $RepMap[$key]['ENTRY'][$i]['WAREHOUSEHREF']     = "javascript:drilldown(2,'$whInc', '$WHOwnerLoc');";

                $RepMap[$key]['ENTRY'][$i]['WAREHOUSE']        = $entry[$i]['WAREHOUSE'];
                $RepMap[$key]['ENTRY'][$i]['PRODUCTLINE']    = $entry[$i]['PRODUCTLINEKEY'];

                //if( $entry[$i]['UPDINV'] == 'T' || $entry[$i]['UPDINV'] == 'Q' ){
                //Show qty for all transactions irrespective of the templates effect on qty

                $qty                                    = $entry[$i]['QTY'];
                $qtytot                                    = bcadd($qtytot, $qty, $round);
                $RepMap[$key]['ENTRY'][$i]['QTY']        = $qty;
                    
                //}
                //if( $entry[$i]['UPDINV'] == 'T' || $entry[$i]['UPDINV'] == 'V' ){
                //Show value for all transactions irrespective of the templates effect on value

                $price                                    = bcadd($entry[$i]['PRICE'], '0', 10);
                $prctot                                    = bcadd($prctot, $price, 10);
                //$RepMap[$key]['ENTRY'][$i]['PRICE']		= glFormatCurrency(round($price,2));
                $RepMap[$key]['ENTRY'][$i]['PRICE']        = round($price, 2);
                    
                //}
                //if( $entry[$i]['UPDINV'] == 'T' ){

                $cost                                        = bcmul($qty, $price, 10);
                $costtot                                    = bcadd($costtot, $cost, 10);
                //$RepMap[$key]['ENTRY'][$i]['COST']			= glFormatCurrency(round($cost,2));
                $RepMap[$key]['ENTRY'][$i]['COST']            = round($cost, 2);
                    
                //}
            }
            $RepMap[$key]['DOCTOTAL'][0]['DOCID']    = $doc['DOCID'];
            // $RepMap[$key]['DOCTOTAL'][0]['QTYTOT']	= $qtytot;		
            //$RepMap[$key]['DOCTOTAL'][0]['COSTTOT']	= glFormatCurrency(round($costtot,2));
            $RepMap[$key]['DOCTOTAL'][0]['COSTTOT']    = round($costtot, 2);

            // $grnqtytot	= bcadd($grnqtytot, $qtytot, $round);
            /** @noinspection PhpUndefinedVariableInspection */
            $grncosttot    = bcadd($grncosttot, $costtot, 2);
        }

        $params = $this->params['safe'];
        $trans    = $params['trans'];
    
        // Display totals only if it is not All. % indicates All.
        if ($trans != '%') {
            //$RepMap['GRANDTOTAL'][0]['GRNCOSTTOT']	= glFormatCurrency($grncosttot);
            /** @noinspection PhpUndefinedVariableInspection */
            $RepMap['GRANDTOTAL'][0]['GRNCOSTTOT']    = $grncosttot;
        }

        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $RepMap); 

        return $lines;
    }

}
