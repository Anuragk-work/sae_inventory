<?
import('InventoryOrdersReporter');

/**
 * Class InvPickListReport
 */
class InvPickListReport extends InventoryOrdersReporter
{
    /**
     * @param string $params
     */
    function __construct($params='')
    {

        parent::__construct(
            INTACCTarray_merge(
                $params,
                array(    
                'custvend'     => 'cust',
                'reportby'     => 'cust',
                'report'    => 'invpicklist',
                'ops'        => array(
                'so/lists/customer/view',
                'so/lists/item/view',
                'so/lists/sodocument/view',
                            ),
                '2stage'    => 'true',
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
                                'Order Qty Required'=> array( 
                                                        'field'        => 'QUANTITY',
                                                        'fromvalue'    => $fromvalue,
                                                        'tovalue'    => $tovalue,
                                                        ),
                                'Order Number'        => array( 
                                                        'field'        => 'DOCNO', 
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
                                ),
                                '2' =>
                                array(
                                'Whse Qty Required'    => array( 
                                                        'field'        => 'WHSEITEMTOTALQUANTITY', 
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
        '2'     => 
        array(
                        $gInvRptCalcsOrderTotalQuantity,
                        $gInvRptCalcsWhseItemTotalQuantity,
                        $gInvRptCalcsCustItemTotalQuantity
        ),
        );
        //
        // Set up sorting options
        //
        $this->sortModes = array( $sortmode, );
        /** @noinspection PhpUndefinedVariableInspection */
        $default = array (
        'Default'     => $gInvRptSortsShipDate['Ship Date']
        );
        /** @noinspection PhpUndefinedVariableInspection */
        $temp = INTACCTarray_merge(
            $default,
            $gInvRptSortsShipDate,
            $gInvRptSortsCustomer,
            $gInvRptSortsCustomerID,
            $gInvRptSortsWarehouse,
            $gInvRptSortsOrderQuantity,
            $gInvRptSortsOrderNumber,
            $gInvRptSortsWhseItemTotalQuantity,
            $gInvRptSortsAisleBin,
            $gInvRptSortsZIP,
            $gInvRptSortsCity,
            $gInvRptSortsState,
            $gInvRptSortsItem,
            $gInvRptSortsItemID
        );
        $this->sorts = array(
        '2' => $temp
        );

        //
        // Set up the tree options
        //
        $this->treeMode = $summarymode;
        $this->trees = array(
        'Customer Detail' => array(
                        array(
                            array( 
                                'groupby'        => 'ID', 
                                'grouptag'        => 'CUSTOMER',
                                'attributes'    => array( 
                                                    'ID', 
                                                    'IDHREF', 
                                                    'NAME', 
                                                    'VALUEGRANDTOTAL',
                                                    'ADDR1',
                                                    'ADDR2',
                                                    'CITY',
                                                    'STATE',
                                                    'ZIP',
                                                    'COUNTY',
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
                                                    'UOM',
                                                    'QUANTITY',
                                                    'SUBSECTION',
                                                    )
                                ),
                            ),
         ),
        'Customer Summary' => array(
         array(
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
                                                    'COUNTY',
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
                                                    'CUSTITEMTOTALQUANTITY',
                                                    ),
           ),
          ),
         ),
        'Warehouse Summary' => array(
         array(
          array( 
                                'groupby'        => 'WAREHOUSEKEY', 
                                'grouptag'        => 'WAREHOUSES', 
                                'attributes'    => array( 
                                                    'WAREHOUSEKEY',
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
                                                    'WHSEITEMTOTALQUANTITY',
                                                    ),
           ),
          ),
         ),
        'Tabular Detail' => array(
         array(
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
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'WAREHOUSEKEY',
                                                    'SUBSECTION',
                                                    'QUANTITY',
                                                    ),
           ),
          ),
         ),
        );

        $map = InventoryOrdersReporter::DoMap();
        $map['report'][0]['term_Aisle_Bin'] = $map['report'][0]['term_Aisle'] .'/' . $map['report'][0]['term_Bin'] ;
        return $map;
    }


}