<?php
import('InventoryReporter');
require_once 'Dictionary.cls';

/**
 * Class ItemListReport
 */
class ItemListReport extends InventoryReporter
{

    /**
     * @param array $_params
     */
    function __construct($_params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $_params, array( 
                                'report' => 'itemlist', 
                                'ops'    => array(
                                            'inv/lists/item/view',
                                            'inv/lists/productline/view'
                                            ),
                                '2stage'    => true,
                                'reportslide' => true,
                                ) 
            )
        );
        // No need to check for location filter as we don't show any amount flds
        $this->params['NOREPORTLOCCHECK'] = true;
    }



    /**
     * this function is overriden here only for the purpose of
     * at entity level if user doesnt give location we should see root as well as entities items
     *
     * @param array     $params
     * @param string    $loc
     *
     * @return string
     */
    function _getReportParamsLocationFilter(&$params, $loc)
    {
        return $loc;
    }


    /**
     * @return bool
     */
    function DoQuery() 
    {
        //$itemMgr = $gManagerFactory->GetManager('item');
        //$allowKit = $itemMgr->Enablekitting();

        $this->ValidateReport();
        $params                    = $this->params['safe'];
        $prodlineid                = $params['PRODLINEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];

        // column selectors
        $InvPrecision            = $this->params['INVPREC'];
        $SalesPrecision            = $this->params['SALESPREC'];
        $PurchasePrecision        = $this->params['PURSPREC'];
        $BasePrice                = $this->params['BASEPRICE'];
        $ItemGLGroup            = $this->params['ITEMGLGROUP'];
        $TaxGLGroup                = $this->params['TAXGLGROUP'];
        $Taxable                = $this->params['TAXABLE'];
        $DateLastSold            = $this->params['DATELASTSOLD'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];

        // filter records based on ItemType
        $Inventory    = $this->params['INVENTORY'];
        $NonInv        = $this->params['NON_INV'];
        $NonInvPO    = $this->params['NON_INV_PO'];
        $NonInvSO    = $this->params['NON_INV_SO'];
        $Kit        = $this->params['KIT'];
        $Stockable_Kit = $this->params['STKIT'];
        $gReport['ROUNDING']    = 'C';
        $itemupcargs = array();
        $itemargtypes = array();

        $filterlocation = $this->_getLocationClause($params, 'it');
        $filterdept = $this->_getDeptClause($params, 'it');

        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'it', 'itemid', $itemValues);
                $itemargtypes = array(  'text', 'integer');

            } else {
                $itemupcargs = array($fromitemid, $toitemid, );
                $filterItemorUPC = " it.itemid >= ? and it.itemid <= ? ";
                $itemargtypes = array( 'text', 'text', 'integer');
            }
        }else {
            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'it', 'upc', $upcValues);
                $itemargtypes = array( 'text', 'integer');
            } else {
                $itemupcargs = array($fromupc,$toupc);
                $filterItemorUPC = " it.upc >= ? and it.upc <= ? ";
                $itemargtypes = array( 'text', 'text', 'integer');
            }
        }

        if ($prodlineid != '%') {
            //Get all child productlines
            $qryStr = " and it.productlinekey in ( select productlineid from icprodline where cny# = it.cny# 
                start with cny# = it.cny# and productlineid= ?
                connect by cny# = it.cny# and parentlineid = PRIOR productlineid)";
            // if $itemupcargs is not array check if its not empty and create a array
            // and set to $itemupcargs
            if (!is_array($itemupcargs)) {
                if ($itemupcargs != null && $itemupcargs != '') {
                    $itemupcargs = array($itemupcargs);
                } else {
                    $itemupcargs = array();
                }
            }
            array_push($itemupcargs, $prodlineid);
            array_push($itemargtypes, 'text');
        } 

        //
        $InvPrecisionQry = ( $InvPrecision == 'true' ) ? 'it.numdec_std,' : '' ;
        $SalesPrecisionQry = ( $SalesPrecision == 'true' ) ? 'it.numdec_sale,' : '' ;
        $PurchasePrecisionQry = ( $PurchasePrecision == 'true' ) ? 'it.numdec_pur,' : '' ;

        // Base Price
        $cny = GetMyCompany();
        $BasePriceTable = ", (SELECT	price.value, price.DATEFROM, price.DATETO, it.itemid 
			FROM icitem it,oeprclstitems  price
			WHERE	it.itemid >= '".$fromitemid."' and it.itemid <= '".$toitemid."' and it.cny# = ".$cny." and price.cny# = it.cny# 
			and price.itemkey = it.itemid and price.prclstkey = 1
			group by price.value, price.datefrom, price.dateto, it.itemid) price";
        $BasePriceqry = ( $BasePrice == 'true' ) ? 'price.value as baseprice,' : '' ;
        $BasePriceCondition = ( $BasePrice == 'true' ) ? " and price.itemid (+)= it.itemid " : '' ;
        $includePriceListTable = ( $BasePrice == 'true' ) ? $BasePriceTable : '' ;
        // 

        $ItemGLGroupQry = ( $ItemGLGroup == 'true' ) ? 'itemglgrp.name as glgrpname,' : '' ;
        $TaxGLGroupQry = ( $TaxGLGroup == 'true' ) ? 'itemtaxgrp.name as taxgrpname,' : '' ;
        $TaxableQry = ( $Taxable == 'true' ) ? "decode(it.taxable,'T','IA.YES','IA.NO') as Taxable," : '';
        $DateLastSoldQry = ( $DateLastSold == 'true' ) ? 'it.whenlastsold,' : '' ;
        
        // filter records based on ItemType
        $itemtypesin = '';
        $itemtypesin.= $Inventory == 'true' ? "'I'," : '' ;
        $itemtypesin.= $NonInv == 'true' ? "'NI'," : '' ;
        $itemtypesin.= $NonInvPO == 'true' ? "'NP'," : '' ;
        $itemtypesin.= $NonInvSO == 'true' ? "'NS'," : '' ;
        $itemtypesin.= $Kit == 'true' ? "'K'," : '' ;
        $itemtypesin.= $Stockable_Kit == 'true' ? "'SK'," : '' ;
        $itemtypesin.= "''";
        $ItemTypeQry = "and  it.itemtype IN (".$itemtypesin.")";

        // 7523: Add new column "Item Description" to output. The Item ID is already populated in the query (it.itemid). However, the "Item" field was
        // concatenating the Item ID and Item Description into one field separated by a "-". Instead, we now use field, ITEM_DESCRIPTION which is populated 
        // with the Item Description.
        /** @noinspection PhpUndefinedVariableInspection */
        $itemcode = array(
        'QUERY'=> "SELECT  
				it.itemid, 
				it.upc,
				$InvPrecisionQry
				$SalesPrecisionQry
				$PurchasePrecisionQry
				$BasePriceqry
				$ItemGLGroupQry
				$TaxGLGroupQry
				$TaxableQry
				$DateLastSoldQry
				it.name item_description, 
				uom.unit uom, 
				it.productlinekey productlineid,
				it.productlinekey||' - '||pl.description prodline,
				it.ship_weight, 
				decode(it.cost_method, 'S','IA.STANDARD','A','IA.AVERAGE','F','IA.FIFO', 'L','IA.LIFO','O','IA.LOT','#','IA.SERIAL', NULL) cost_method,
				decode(it.status, 'T', 'IA.ACTIVE', 'F', 'IA.INACTIVE', NULL) status,
				it.locationkey itownerloc,
				pl.locationkey plownerloc
			FROM icitem it, icprodline pl, icuom uom, icuomgrp uomgrp, icitemglgrp itemglgrp, taxgrp itemtaxgrp ". $includePriceListTable ."
			WHERE	$filterItemorUPC
				$filterlocation $filterdept
				$ItemTypeQry
				$qryStr
				--and uom.record# (+)= it.std_uom 
				and it.producttype <> 'PROFSERVICE' 
				and	pl.productlineid (+) = it.productlinekey 
				and 	uomgrp.cny# (+) = it.cny#
				and 	uomgrp.record# (+) = it.uomgrpkey					
				and		uom.cny# (+) = uomgrp.cny#
				and 	uom.isbase (+) = 'T'
				and		uom.grpkey (+) = uomgrp.record# 
				and pl.cny# (+) = it.cny# 
				and it.cny# = ?
				and itemglgrp.record# (+)= it.glgrpkey
				and itemglgrp.cny# (+)= it.cny#
				and itemtaxgrp.record# (+)= it.taxgroupkey
				and itemtaxgrp.cny# (+)= it.cny#
				$BasePriceCondition
			ORDER BY  1", 
        'ARGTYPES' => $itemargtypes
        );

        // moved the query into here because the one in qry file is putting an or between the item and product line ids
        $items = $this->_QM->DoCustomQuery($itemcode, $itemupcargs, true);
        $this->_items = $items;
        return true;
    }


    /**
     * @return array
     */
    function DoMap()
    {
        $itemsMap = array();
        $i = 0;

        foreach($this->_items as $row){
            $itemID = urlencode(addslashes($row['ITEMID']));
            $prodlineID = urlencode($row['PRODUCTLINEID']);
            $row['ITEMHREF']         = "javascript:drilldown(0,'$itemID', '$row[ITOWNERLOC]');";
            $row['PRODLINEHREF']     = "javascript:drilldown(1,'$prodlineID', '$row[PLOWNERLOC]');";

            if ($this->params['DATELASTSOLD']=='true') { 
                $row['WHENLASTSOLD'] = FormatDateForDisplay($row['WHENLASTSOLD']); 
            }

            $itemsMap[$i++] = $row;
        }
        $lines = $this->InvCommonHeader();

        $colSelected=0;        
        // Inventory Precision
        if ($this->params['INVPREC']=='true') {
            $lines['report'][0]['InvPrecision'] = 1;
            $colSelected++;
        }
        // Sales Precision
        if ($this->params['SALESPREC']=='true') {
            $lines['report'][0]['SalesPrecision'] = 1;
            $colSelected++;
        }
        // Purchase Precision
        if ($this->params['PURSPREC']=='true') {
            $lines['report'][0]['PurchasePrecision'] = 1;
            $colSelected++;
        }
        // Base Price
        if ($this->params['BASEPRICE']=='true') {
            $lines['report'][0]['BasePrice'] = 1;
            $colSelected++;
        }
        // Item GL Group
        if ($this->params['ITEMGLGROUP']=='true') {
            $lines['report'][0]['ItemGLGroup'] = 1;
            $colSelected++;
        }
        // Tax GL Group
        if ($this->params['TAXGLGROUP']=='true') {
            $lines['report'][0]['TaxGLGroup'] = 1;
            $colSelected++;
        }
        //  Taxable 
        if ($this->params['TAXABLE']=='true') {
            $lines['report'][0]['Taxable'] = 1;
            $colSelected++;
        }
        // Date Last Sold
        if ($this->params['DATELASTSOLD']=='true') {
            $lines['report'][0]['DateLastSold'] = 1;
            $colSelected++;
        }

        //We will reduce the font if we have more than 6 additional columns selected
        $lines['report'][0]['ColSelected'] = $colSelected;

        $lines = $this->InvCommonBody($lines, $itemsMap); 

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        return $lines;
    }


    /*	function ValidateReport(){
    // override this function if you don't need all the checks for your report
		
    // put the various validations into seperate calls, so the sub classes don't have to override everything to get something
    #		$this->ValidateDates();
		
    // Do any tweaks here that we need, like min/max vals, isl_htmlspecialchars, etc.
    $this->ParamTweaks();
    }*/


}


