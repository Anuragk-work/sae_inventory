<?php
import('InventoryOrdersReporter');

/**
 * Class InvOrderAnalysisReport
 */
class InvOrderAnalysisReport extends InventoryOrdersReporter
{
    /**
     * @param array $params
     */
    function __construct($params)
    {

        parent::__construct(
            INTACCTarray_merge(
                $params,
                array(
                    'custvend' => 'cust',
                    'reportby' => 'cust',
                    'report'   => 'invorderanalysis',
                    'ops'      => array(
                        'so/lists/customer/view',
                        'so/lists/item/view',
                        'so/lists/sodocument/view',
                    ),
                    '2stage'   => 'true',
                ) 
            )
        );
    }

    /**
     * @return array
     */
    function DoMap()
    {

        include "globals.ent";
        if ($this->params['safe']['SUMMARYMODE'] == 'Default' ) {
            $this->params['safe']['SUMMARYMODE'] = 'Customer Detail';
        }

        $params = $this->params['safe'];
        $fromvalue                = $params['FROMVALUE'];
        $tovalue                = $params['TOVALUE'];
        $filtermode                = $params['VALUEMODE'];
        $sortmode                = $params['SORTMODE'];
        $summarymode            = $params['SUMMARYMODE'];

        //
        // Set up the filtering options
        //
        $this->filterModes = array( $filtermode, );
        $this->filters = array(
         '1' => 
                                array(
                                'Order Quantity'    => array( 
                                                        'field'        => 'QUANTITY',
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Order Value'         => array( 
                                                        'field'        => 'ORDERTOTALVALUE',
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Order Number'        => array( 
                                                        'field'        => 'DOCNO', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Whse Qty on Hand'    => array( 
                                                        'field'        => 'QUANTITYONHAND', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Aisle/Bin'            => array( 
                                                        'field'        => 'SUBSECTION', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'ZIP'                => array( 
                                                        'field'        => 'ZIP', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'City'                => array( 
                                                        'field'        => 'CITY', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'State'                => array( 
                                                        'field'        => 'STATE', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Ship Method'        => array( 
                                                        'field'        => 'SHIPMETHODNAME', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Days to Ship Date'    => array( 
                                                        'field'        => 'DAYSTODUE',
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                ),
                                '2' => 
                                array(
                                'Item Qty Required'    => array( 
                                                        'field'        => 'ITEMTOTALQUANTITY', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Whse Qty Required'    => array( 
                                                        'field'        => 'WHSEITEMTOTALQUANTITY', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Default'            => array( 
                                                        'field'        => 'WHSEITEMQUANTITYLEFT', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Whse Qty Left'        => array( 
                                                        'field'        => 'WHSEITEMQUANTITYLEFT', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                ),
                                '3' =>
                                array(
                                'Customer Total Value'    => array( 
                                                        'field'        => 'CUSTTOTAL', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Order Count'    => array( 
                                                        'field'        => 'ITEMORDERCOUNT', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Avg Qty'        => array( 
                                                        'field'        => 'ITEMAVGQUANTITY', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Min Qty'        => array( 
                                                        'field'        => 'ITEMMINQUANTITY', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Max Qty'        => array( 
                                                        'field'        => 'ITEMMAXQUANTITY', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Qty Range'    => array( 
                                                        'field'        => 'ITEMQTYVARIANCE', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Avg Price'    => array( 
                                                        'field'        => 'ITEMAVGPRICE', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Min Price'    => array( 
                                                        'field'        => 'ITEMMINPRICE', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Max Price'    => array( 
                                                        'field'        => 'ITEMMAXPRICE', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item Price Range'    => array( 
                                                        'field'        => 'ITEMPRICEVARIANCE', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Item % of Total Value'    => array( 
                                                        'field'        => 'ITEMPERCENTOFGRANDTOTAL', 
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                ),
                            );

        //
        // Set up the calculation options
        //
        /** @noinspection PhpUndefinedVariableInspection */
        $this->calcs = array (
        '1'     => 
        array(
                        $gInvRptCalcsOrderTotalValue,
                        $gInvRptCalcsOrderTotalQuantity,
                        $gInvRptCalcsWhseItemTotalQuantity,
                        $gInvRptCalcsItemTotalQuantity,
                        $gInvRptCalcsCustItemTotalQuantity,
                        $gInvRptCalcsItemQOH,
         ),
        '2' =>
        array(
         $gInvRptCalcsWhseItemQtyLeft,
         $gInvRptCalcsItemQtyLeft,
         ),
        '3' =>
        array(
         $gInvRptCalcsValueGrandTotal,
         $gInvRptCalcsCustValueGrandTotal,
         $gInvRptCalcsCustItemValueGrandTotal,
         $gInvRptCalcsCustWhseValueGrandTotal,
         $gInvRptCalcsItemValueGrandTotal,
         $gInvRptCalcsWhseValueGrandTotal,
         $gInvRptCalcsWhseItemValueGrandTotal,
         $gInvRptCalcsWhseValuePercentofGrandTotal,
         $gInvRptCalcsItemTotalValue,
         $gInvRptCalcsItemAvgPrice,
         $gInvRptCalcsItemMinPrice,
         $gInvRptCalcsItemMaxPrice,
         $gInvRptCalcsItemPriceVariance,
         $gInvRptCalcsItemPriceVarPercent,
         $gInvRptCalcsItemAvgQty,
         $gInvRptCalcsItemMinQty,
         $gInvRptCalcsItemMaxQty,
         $gInvRptCalcsItemQtyVariance,
         $gInvRptCalcsItemQtyVarPercent,
         $gInvRptCalcsItemOrderCount,
         $gInvRptCalcsItemValuePercentofGrandTotal,
         $gInvRptCalcsWhseItemValuePercentofWhseGrandTotal,
         ),
        );
        //
        // Set up sorting options
        //
        $this->sortModes = array( $sortmode, );
        /** @noinspection PhpUndefinedVariableInspection */
        $default = array (
        'Default'   => $gInvRptSortsShipDate['Ship Date']
        );
        /** @noinspection PhpUndefinedVariableInspection */
        $temp = INTACCTarray_merge(
            $default,
            $gInvRptSortsShipDate,
            $gInvRptSortsCustomer,
            $gInvRptSortsCustomerID,
            $gInvRptSortsWarehouse,
            $gInvRptSortsWhseQOH,
            $gInvRptSortsWhseItemTotalQuantity,
            $gInvRptSortsWhseQuantityLeft,
            $gInvRptSortsCustomerValue,
            $gInvRptSortsOrderQuantity,
            $gInvRptSortsOrderValue,
            $gInvRptSortsOrderNumber,
            $gInvRptSortsItemOrderCount,
            $gInvRptSortsItemValue,
            $gInvRptSortsItemQOH,
            $gInvRptSortsItemTotalQuantity,
            $gInvRptSortsItemAvgQuantity,
            $gInvRptSortsItemMinQuantity,
            $gInvRptSortsItemMaxQuantity,
            $gInvRptSortsItemQuantityRange,
            $gInvRptSortsItemQuantity,
            $gInvRptSortsWhseItemTotalQuantity,
            $gInvRptSortsItemAvgPrice,
            $gInvRptSortsItemMinPrice,
            $gInvRptSortsItemMaxPrice,
            $gInvRptSortsItemPriceRange,
            $gInvRptSortsAisleBin,
            $gInvRptSortsZIP,
            $gInvRptSortsCity,
            $gInvRptSortsState,
            $gInvRptSortsItem,
            $gInvRptSortsItemID
        );
        $this->sorts =  array(
        '3' => $temp 
        );
        //
        // Set up the tree options
        //
        $this->treeMode = $summarymode;
        $this->trees = array(
        'Customer Detail' => array(
                        array(
                            array( 
                                'groupby'        => 'VALUEGRANDTOTAL', 
                                'grouptag'        => 'TOTALS', 
                                'attributes'    => array(
                                                    'VALUEGRANDTOTAL',
                                                ),
                                ),
                            array( 
                                'groupby'        => 'ID', 
                                'grouptag'        => 'CUSTOMER',
                                'attributes'    => array( 
                                                    'ID', 
                                                    'IDHREF', 
                                                    'NAME', 
                                                    'CUSTTOTAL',
                                                    'ADDR1',
                                                    'ADDR2',
                                                    'CITY',
                                                    'STATE',
                                                    'ZIP',
                                                    'COUNTRY',
                                                    ) 
                                ),
                            array( 
                                'groupby'        => 'DOCID', 
                                'grouptag'        => 'ORDERS',
                                'attributes'    => array( 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'DOCNO',
                                                    'WHENDUE',
                                                    'DAYSTODUE',
                                                    'ORDERTOTALVALUE',
                                                    'ORDERTOTALQUANTITY',
                                                    'SHIPVIAKEY',
                                                    'SHIPMETHODNAME',
                                                    'INPAST',
                                                    ) 
                                ),
                            array( 
                                'groupby'        => 'WAREHOUSEKEY', 
                                'grouptag'        => 'WAREHOUSES', 
                                'attributes'    => array( 'WAREHOUSEKEY', ) 
                                ),
                            array(
                                'groupby'        => 'RECORDKEY',
                                'grouptag'        => 'ENTRIES',
                                'attributes'    => array(
                                                    'ITEMKEY',
                                                    'RECORDKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'DEPARTMENT',
                                                    'LOCATION',
                                                    'UOM',
                                                    'QUANTITY',
                                                    'QUANTITYONHAND',
                                                    'SUBSECTION',
                                                    'PRICE',
                                                    'VALUE',
                                                    )
                                ),    
                            ),
         ),
        'Customer Summary' => array(
         array(
          array( 
                                'groupby'        => 'VALUEGRANDTOTAL', 
                                'grouptag'        => 'TOTALS', 
                                'attributes'    => array(
                                                    'VALUEGRANDTOTAL',
                                                ),
           ),
          array( 
           'groupby'        => 'ID', 
           'grouptag'        => 'CUSTOMER',
           'attributes'    => array( 
                                                    'ID', 
                                                    'IDHREF', 
                                                    'NAME', 
                                                    'ADDR1',
                                                    'ADDR2',
                                                    'CITY',
                                                    'STATE',
                                                    'ZIP',
                                                    'COUNTRY',
                                                    'CUSTTOTAL',
                                                    ),
           ),
          array(
           'groupby'        => 'ITEMKEY',
           'grouptag'        => 'ENTRIES',
           'attributes'    => array(
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'ITEMTOTALQUANTITYONHAND',
                                                    'ITEMTOTALQUANTITY',
                                                    'ITEMQUANTITYLEFT',
                                                    'CUSTITEMTOTALQUANTITY',
                                                    'CUSTITEMTOTAL',
                                                    ),
           ),
          ),
         ),
        'Item Summary' => array(
         array(
          array( 
                                'groupby'        => 'VALUEGRANDTOTAL', 
                                'grouptag'        => 'TOTALS', 
                                'attributes'    => array(
                                                    'VALUEGRANDTOTAL',
                                                ),
           ),
          array( 
           'groupby'        => 'ITEMKEY', 
           'grouptag'        => 'ENTRIES', 
           'attributes'    => array(
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'ITEMAVGPRICE',
                                                    'ITEMMINPRICE',
                                                    'ITEMMAXPRICE',
                                                    'ITEMPRICEVARIANCE',
                                                    'ITEMPRICEVARIANCEPERCENT',
                                                    'ITEMTOTALVALUE',
                                                    'ITEMAVGQUANTITY',
                                                    'ITEMMINQUANTITY',
                                                    'ITEMMAXQUANTITY',
                                                    'ITEMQTYVARIANCE',
                                                    'ITEMQTYVARIANCEPERCENT',
                                                    'ITEMTOTALQUANTITY',
                                                    'ITEMTOTALQUANTITYONHAND',
                                                    'ITEMQUANTITYLEFT',
                                                    'ITEMORDERCOUNT',
                                                    'ITEMPERCENTOFGRANDTOTAL',
                                                    'VALUEGRANDTOTAL',
                                                    ),
           ),
          ),
         ),
        'Warehouse Summary' => array(
         array(
          array( 
                                'groupby'        => 'VALUEGRANDTOTAL', 
                                'grouptag'        => 'TOTALS', 
                                'attributes'    => array(
                                                    'VALUEGRANDTOTAL',
                                                ),
           ),
          array( 
           'groupby'        => 'WAREHOUSEKEY', 
           'grouptag'        => 'WAREHOUSES', 
           'attributes'    => array( 
                                                    'WAREHOUSEKEY',
                                                    'WHSEGRANDTOTAL',
                                                    'WHSEPERCENTOFGRANDTOTAL',
                                                    ) 
           ),
          array(
           'groupby'        => 'ITEMKEY',
           'grouptag'        => 'ENTRIES',
           'attributes'    => array(
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'SUBSECTION',
                                                    'QUANTITYONHAND',
                                                    'WHSEITEMTOTALQUANTITY',
                                                    'WHSEITEMQUANTITYLEFT',
                                                    'WHSEITEMTOTAL',
                                                    'WHSEITEMPERCENTOFWHSEGRANDTOTAL',
                                                    ),
           ),
          ),
         ),
        'Tabular Detail' => array(
         array(
          array( 
                                'groupby'        => 'VALUEGRANDTOTAL', 
                                'grouptag'        => 'TOTALS', 
                                'attributes'    => array(
                                                    'VALUEGRANDTOTAL',
                                                ),
           ),
          array( 
           'groupby'        => 'intacctsortkey', 
           'grouptag'        => 'ENTRIES',
           'attributes'    => array( 
                                                    'ID', 
                                                    'IDHREF', 
                                                    'NAME', 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'DOCNO',
                                                    'WHENDUE',
                                                    'DAYSTODUE',
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'DEPARTMENT',
                                                    'LOCATION',
                                                    'UOM',
                                                    'WAREHOUSEKEY',
                                                    'SUBSECTION',
                                                    'QUANTITY',
                                                    'QUANTITYONHAND',
                                                    'PRICE',
                                                    'VALUE',
                                                    ),
           ),
          ),
         ),
        );

        $map = InventoryOrdersReporter::DoMap();
        return $map;

    }
}
