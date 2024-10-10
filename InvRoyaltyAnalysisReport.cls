<?
import('inventoryroyaltyreporter');

/**
 * Class InvRoyaltyAnalysisReport
 */
class InvRoyaltyAnalysisReport extends InventoryRoyaltyReporter
{

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                array(    
                'custvend'     => 'inv',
                'reportby'     => 'inv',
                'report'    => 'invroyaltyanalysis',
                'ops'        => array(
                'inv/lists/warehouse/view',
                'inv/lists/item/view',
                'inv/lists/invdocument/view',
                'inv/lists/productline/view',
                'inv/lists/warehouse/view',
                'po/lists/vendor/view',
                'po/lists/item/view',
                'po/lists/podocument/view',
                'po/lists/productline/view',
                        ),
                '2stage'    => 'true',
                ),
                $params
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
            $this->params['safe']['SUMMARYMODE'] = 'Tabular Detail Order Summary';
        }

        $params = $this->params['safe'];
        $filtermode                = $params['VALUEMODE'];
        $summarymode            = $params['SUMMARYMODE'];

        // since so many of these have the same fields in different orders, let's define them and use the short names

        $fields['grandtotal'] = 
          array( 
                                'groupby'        => 'VALUEGRANDTOTAL', 
                                'grouptag'        => 'TOTALS', 
                                'attributes'    => array(
                                                    'VALUEGRANDTOTAL',
                                                    'COSTGRANDTOTAL',
                                                    'MARGINGRANDTOTAL',
                                                    'QUANTITYGRANDTOTAL',
                                                ),
          );
        $fields['Sales Rep'] = 
          array( 
                                'groupby'        => 'SALESREP', 
                                'grouptag'        => 'SALESREP', 
                                'attributes'    => array( 
                                                    'SALESREP',
                                                    'SALESREPNAME',
                                                    'SALESREPHREF',
                                                    'SALESREPTOTALVALUE',
                                                    'SALESREPTOTALCOST',
                                                    'SALESREPTOTALMARGIN',
                                                    'SALESREPTOTALQUANTITY',
                                                    ) 
          );
        $fields['Prod Line'] = 
          array( 
                                'groupby'        => 'PRODUCTLINEKEY', 
                                'grouptag'        => 'PRODUCTLINEKEY', 
                                'attributes'    => array( 
                                                    'PRODUCTLINEKEY',
                                                    'PRODUCTLINEKEYHREF',
                                                    'PRODUCTLINEKEYTOTALVALUE',
                                                    'PRODUCTLINEKEYTOTALCOST',
                                                    'PRODUCTLINEKEYTOTALMARGIN',
                                                    'PRODUCTLINEKEYTOTALQUANTITY',
                                                    ) 
          );
        $fields['Warehouse'] = 
          array( 
                                'groupby'        => 'WAREHOUSEKEY', 
                                'grouptag'        => 'WAREHOUSE', 
                                'attributes'    => array( 
                                                    'WAREHOUSEKEY',
                                                    'WAREHOUSEKEYHREF',
                                                    'WAREHOUSEKEYTOTALVALUE',
                                                    'WAREHOUSEKEYTOTALCOST',
                                                    'WAREHOUSEKEYTOTALMARGIN',
                                                    'WAREHOUSEKEYTOTALQUANTITY',
                                                    ) 
          );
        $fields['Territory'] = 
          array( 
                                'groupby'        => 'TERRITORY', 
                                'grouptag'        => 'TERRITORY', 
                                'attributes'    => array( 
                                                    'TERRITORY',
                                                    'TERRITORYHREF',
                                                    'TERRITORYTOTALVALUE',
                                                    'TERRITORYTOTALCOST',
                                                    'TERRITORYTOTALMARGIN',
                                                    'TERRITORYTOTALQUANTITY',
                                                    ) 
          );
        $fields['Customer'] = 
          array( 
                                'groupby'        => 'ID', 
                                'grouptag'        => 'CUSTOMER', 
                                'attributes'    => array( 
                                                    'ID',
                                                    'IDHREF',
                                                    'NAME',
                                                    'IDTOTALVALUE',
                                                    'IDTOTALCOST',
                                                    'IDTOTALMARGIN',
                                                    'IDTOTALQUANTITY',
                                                    ) 
          );
        $fields['Vendor'] = 
          array( 
                                'groupby'        => 'ID', 
                                'grouptag'        => 'VENDOR', 
                                'attributes'    => array( 
                                                    'ID',
                                                    'IDHREF',
                                                    'NAME',
                                                    'IDTOTALVALUE',
                                                    'IDTOTALCOST',
                                                    'IDTOTALMARGIN',
                                                    'IDTOTALQUANTITY',
                                                    ) 
          );
        $fields['Orders'] = 
          array( 
                                'groupby'        => 'DOCID', 
                                'grouptag'        => 'ORDERS',
                                'attributes'    => array( 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'HDRSTATE',
                                                    'DOCNO',
                                                    'PONUMBER',
                                                    'WHENCREATED',
                                                    'ORDERTOTALVALUE',
                                                    'ORDERTOTALCOST',
                                                    'ORDERTOTALMARGIN',
                                                    'ORDERTOTALQUANTITY',
                                                    ) 
          );
        $fields['Items'] = 
          array( 
                                'groupby'        => 'ITEMKEY', 
                                'grouptag'        => 'ITEMS',
                                'attributes'    => array( 
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'PRODUCTLINEKEY',
                                                    'UOM',
                                                    'ITEMTOTALQUANTITY',
                                                    'ITEMTOTALPRICE',
                                                    'ITEMTOTALVALUE',
                                                    'ITEMTOTALCOST',
                                                    'ITEMTOTALMARGIN',
                                                    ),
          );
        $fields['Items Detail'] = 
          array( 
                                'groupby'        => 'intacctsortkey', 
                                'grouptag'        => 'ORDERS',
                                'attributes'    => array( 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'WAREHOUSEKEY',
                                                    'WAREHOUSEKEYHREF',
                                                    'DOCNO',
                                                    'HDRSTATE',
                                                    'PONUMBER',
                                                    'WHENCREATED',
                                                    'ORDERTOTALVALUE',
                                                    'ORDERTOTALQUANTITY',
                                                    'UOM',
                                                    'QUANTITY',
                                                    'PRICE',
                                                    'VALUE',
                                                    'COST',
                                                    'MARGIN',
                                                    'DEPARTMENT',
                                                    'LOCATION'
                                                    ) 
          );
        $fields['Orders Detail'] = 
          array( 
                                'groupby'        => 'intacctsortkey', 
                                'grouptag'        => 'ITEMS',
                                'attributes'    => array( 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'DOCNO',
                                                    'HDRSTATE',
                                                    'PONUMBER',
                                                    'WAREHOUSEKEY',
                                                    'WAREHOUSEKEYHREF',
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'QUANTITY',
                                                    'PRICE',
                                                    'VALUE',
                                                    'COST',
                                                    'MARGIN',
                                                    'DEPARTMENT',
                                                    'LOCATION'
                                                    ),
          );
        $fields['None Summary'] = "";
        $fields['None Detail'] = "";



        $groups['Prod Line']     = 'PRODUCTLINEKEY';
        $groups['Warehouse']     = 'WAREHOUSEKEY';
        $groups['Customer']     = 'ID';
        $groups['Vendor']         = 'ID';
        $groups['Territory']     = 'TERRITORY';
        $groups['Sales Rep']     = 'SALESREP';


        $sorts['Prod Line'] =
                                    array(
                                        'field'        => 'PRODUCTLINEKEY',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Warehouse'] =
                                    array(
                                        'field'        => 'WAREHOUSEKEY',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Customer'] =
                                    array(
                                        'field'        => 'ID',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Vendor'] =
                                    array(
                                        'field'        => 'ID',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Territory'] =
                                    array(
                                        'field'        => 'TERRITORY',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Sales Rep'] =
                                    array(
                                        'field'        => 'SALESREP',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Items'] =
                                    array(
                                        'field'        => 'ITEMKEY',
                                        'datatype'    => 'SORT_STRING',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['Orders'] =
                                    array(
                                        'field'        => 'DOCNO',
                                        'datatype'    => 'SORT_NUMERIC',
                                        'order'        => 'SORT_ASC',
                                        );
        $sorts['None'] = "";








        // This is a custom loop to dynamically set the calcs, filters, sorts, and trees
        $themode = $summarymode; // get our long string to parse
        $temp = explode(" ", $themode); // break on spaces
        $templen = count($temp); //how many pieces?

        $sumdet = $temp[$templen-1]; // sum/det is the last item
        $orderitem = $temp[$templen-2]; // order/item is the next to last item

        $thegroupings = str_replace($orderitem . " " . $sumdet, "", $themode); // remove the sumdet and orderitem strings leaving just the gorupings
        $thegroups = explode("-", $thegroupings); // explode based on dash separator

        $thefields[] = $fields['grandtotal'];
        $calcstring = array();
        foreach ( $thegroups as $thisgroup ){
            $cleanedgroup = isl_trim($thisgroup);
            // take the group, and set the required arrays
            // calculation arrays
            // epp("The group was " . $cleanedgroup);

            if ( isset($groups[ $cleanedgroup ])) {
                $calcstring[] = $groups[$cleanedgroup];
                $calclist[$cleanedgroup] = $calcstring;
            }

            if ( is_array($sorts[ $cleanedgroup ])) {
                $sortarray[] = $sorts[$cleanedgroup];
            }

            if ( is_array($fields[ $cleanedgroup ])) {
                $thefields[] = $fields[ $cleanedgroup ];
            }
        }

        // First, the order and item need to group by all the report groupings the user picke
        $ordergroupfields = $calcstring;
        $itemgroupfields = $calcstring;


        // if we are doing a detail, then add one more field
        if ( $sumdet == 'Detail' ) {
            // Detail mode
            switch( $orderitem ){
            case 'Items':
                $ordergroupfields[] = 'ITEMKEY';
                $sortarray[] = $sorts['Items'];
                $sortarray[] = $sorts['Orders'];
                break;
            case 'Orders':
                $itemgroupfields[] = 'DOCID';
                $sortarray[] = $sorts['Orders'];
                $sortarray[] = $sorts['Items'];
                break;
            case 'None':
                break;
            }
        } else {
            // Summary mode
            switch( $orderitem ){

            case 'Items':
                $sortarray[] = $sorts['Items'];
                break;
            case 'Orders':
                $sortarray[] = $sorts['Orders'];
                break;
            case 'None':
                break;
            }
        }
        if ( $orderitem != 'None'  && $summarymode ) {
            $ordergroupfields[] = 'DOCID';
            $itemgroupfields[]     = 'ITEMKEY';
        }


        if (isset($fields[ $orderitem ])) {
            if ( is_array($fields[ $orderitem ]) ) {
                $thefields[] = $fields[ $orderitem ];
            }
        }
        if (isset($fields[ $orderitem . " " . $sumdet ])) {
            if ( is_array($fields[ $orderitem . " " . $sumdet ]) ) {
                $thefields[] = $fields[ $orderitem . " " . $sumdet ];
            }
        }

        //
        // Set up the filtering options
        //
        $this->filterModes = array( $filtermode, );
        $this->filters = array(
                            );

        //
        // Set up the calculation options
        //

        // need to dynamically set the "groupfields" so that the orders get summed up right.
        // normally we have a separate output name for each type of calc, but in our case, we 
        // want to have a single tag name in the output that has the appropriate amount for the 
        // hierarchy we have established.

        $OrderTotalValue = 
        array(     'name'             => 'OrderTotalValue',
                            'groupfields'    => $ordergroupfields,
                            'inputfield'     => array( 'VALUE', ),
                            'outputfield'    => 'ORDERTOTALVALUE',
                            'action'        => 'sum',
        );
        $OrderTotalCost = 
                    array(     'name'             => 'OrderTotalCost',
                            'groupfields'    => $ordergroupfields,
                            'inputfield'     => array( 'COST', ),
                            'outputfield'    => 'ORDERTOTALCOST',
                            'action'        => 'sum',
                            );
        $OrderTotalMargin = 
                    array(     'name'             => 'OrderTotalMargin',
                            'groupfields'    => $ordergroupfields,
                            'inputfield'     => array( 'MARGIN', ),
                            'outputfield'    => 'ORDERTOTALMARGIN',
                            'action'        => 'sum',
                            );
        $OrderTotalQuantity = 
                    array(     'name'             => 'OrderTotalQuantity',
                            'groupfields'    => $ordergroupfields,
                            'inputfield'     => array( 'QUANTITY', ),
                            'outputfield'    => 'ORDERTOTALQUANTITY',
                            'action'        => 'sum',
                            );
        $ItemTotalValue = 
                    array(     'name'             => 'ItemTotalValue',
                            'groupfields'    => $itemgroupfields,
                            'inputfield'     => array( 'VALUE', ),
                            'outputfield'    => 'ITEMTOTALVALUE',
                            'action'        => 'sum',
                            );
        $ItemTotalCost = 
                    array(     'name'             => 'ItemTotalCost',
                            'groupfields'    => $itemgroupfields,
                            'inputfield'     => array( 'COST', ),
                            'outputfield'    => 'ITEMTOTALCOST',
                            'action'        => 'sum',
                            );
        $ItemTotalMargin = 
                    array(     'name'             => 'ItemTotalMargin',
                            'groupfields'    => $itemgroupfields,
                            'inputfield'     => array( 'MARGIN', ),
                            'outputfield'    => 'ITEMTOTALMARGIN',
                            'action'        => 'sum',
                            );
        $ItemTotalQty = 
                    array(     'name'             => 'ItemTotalQty',
                            'groupfields'    => $itemgroupfields,
                            'inputfield'     => array( 'QUANTITY', ),
                            'outputfield'    => 'ITEMTOTALQUANTITY',
                            'action'        => 'sum',
                            );
        $GrandTotalValue = 
                    array(     'name'             => 'GrandTotalValue',
                            'groupfields'    => array(),
                            'inputfield'     => array( 'VALUE', ),
                            'outputfield'    => 'VALUEGRANDTOTAL',
                            'action'        => 'sum',
                            );
        $GrandTotalCost = 
                    array(     'name'             => 'GrandTotalCost',
                            'groupfields'    => array(),
                            'inputfield'     => array( 'COST', ),
                            'outputfield'    => 'COSTGRANDTOTAL',
                            'action'        => 'sum',
                            );
        $GrandTotalMargin = 
                    array(     'name'             => 'GrandTotalMargin',
                            'groupfields'    => array(),
                            'inputfield'     => array( 'MARGIN', ),
                            'outputfield'    => 'MARGINGRANDTOTAL',
                            'action'        => 'sum',
                            );
        $GrandTotalQuantity = 
                    array(     'name'             => 'QuantityTotalMargin',
                            'groupfields'    => array(),
                            'inputfield'     => array( 'QUANTITY', ),
                            'outputfield'    => 'QUANTITYGRANDTOTAL',
                            'action'        => 'sum',
                            );
        $this->calcs['1'][] = $OrderTotalValue;
        $this->calcs['1'][] = $OrderTotalCost;
        $this->calcs['1'][] = $OrderTotalMargin;
        $this->calcs['1'][] = $OrderTotalQuantity;
        $this->calcs['1'][] = $ItemTotalValue;
        $this->calcs['1'][] = $ItemTotalCost;
        $this->calcs['1'][] = $ItemTotalMargin;
        $this->calcs['1'][] = $ItemTotalQty;
        $this->calcs['1'][] = $GrandTotalValue;
        $this->calcs['1'][] = $GrandTotalCost;
        $this->calcs['1'][] = $GrandTotalMargin;
        $this->calcs['1'][] = $GrandTotalQuantity;
            
        // we want to sum up value, cost and margin	
        $totalsfields = array( 'VALUE','COST','MARGIN','QUANTITY' );
        /** @noinspection PhpUndefinedVariableInspection */
        foreach( $calclist as $key=> $value ){
            foreach( $totalsfields as $field ){
                $this->calcs['1'][] = array(
                'name'             => 'Auto',
                'groupfields'    => $value,
                'inputfield'     => array( $field ),
                'outputfield'    => $groups[$key] . 'TOTAL' . $field,
                'action'        => 'sum',
                                );
            }
        }
        //
        // Set up sorting options
        //
        // we should also dynamically set our sort options to match the hierarchy they've chosen.
        //
        $this->sortModes = array( $summarymode, );
        /** @noinspection PhpUndefinedVariableInspection */
        $this->sorts =  array(
        '1' => array(
        $summarymode => $sortarray
        )
        );
        //
        // Set up the tree options
        //
        $this->treeMode = $summarymode;
        // since so many of these have the same fields in different orders, let's define them and use the short names
        $stock_tabular_customer=
                        array(
                            $fields['grandtotal'],
                            array( 
                                'groupby'        => 'intacctsortkey', 
                                'grouptag'        => 'ENTRIES',
                                'attributes'    => array( 
                                                    'ID', 
                                                    'IDHREF', 
                                                    'NAME', 
                                                    'TERRITORY', 
                                                    'SALESREP', 
                                                    'PRODUCTLINEKEY', 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'HDRSTATE',
                                                    'DOCNO',
                                                    'PONUMBER',
                                                    'WHENCREATED',
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'WAREHOUSEKEY',
                                                    'QUANTITY',
                                                    'PRICE',
                                                    'VALUE',
                                                    'COST',
                                                    'MARGIN',
                                                    'DEPARTMENT',
                                                    'LOCATION'
                                                    ),
                                ),
                        );
        $stock_tabular_vendor=
                        array(
                            $fields['grandtotal'],
                            array( 
                                'groupby'        => 'intacctsortkey', 
                                'grouptag'        => 'ENTRIES',
                                'attributes'    => array( 
                                                    'ID', 
                                                    'IDHREF', 
                                                    'NAME', 
                                                    'PRODUCTLINEKEY', 
                                                    'DOCID',
                                                    'DOCIDHREF',
                                                    'DOCNO',
                                                    'HDRSTATE',
                                                    'WHENCREATED',
                                                    'ITEMKEY',
                                                    'ITEMKEYHREF',
                                                    'ITEMDESCR',
                                                    'UOM',
                                                    'WAREHOUSEKEY',
                                                    'QUANTITY',
                                                    'PRICE',
                                                    'VALUE',
                                                    'COST',
                                                    'MARGIN',
                                                    'DEPARTMENT',
                                                    'LOCATION'
                                                    ),
                                ),
                        );
        $stock_tabular_inventory = $stock_tabular_vendor; // for now, they are  the same
        $this->tree = array();
        $this->trees = array(
        $summarymode => array(
                        $thefields
         ),
        'Customer Tabular Orders Summary' => array(
          $stock_tabular_customer,
         ),
        'Customer Tabular Orders Detail' => array(
          $stock_tabular_customer,
         ),
        'Customer Tabular Items Summary' => array(
          $stock_tabular_customer,
         ),
        'Customer Tabular Items Detail' => array(
          $stock_tabular_customer,
         ),
        'Customer Tabular None Summary' => array(
          $stock_tabular_customer,
         ),
        'Customer Tabular None Detail' => array(
          $stock_tabular_customer,
         ),
        'Vendor Tabular Orders Summary' => array(
          $stock_tabular_vendor,
         ),
        'Vendor Tabular Orders Detail' => array(
          $stock_tabular_vendor,
         ),
        'Vendor Tabular Items Summary' => array(
          $stock_tabular_vendor,
         ),
        'Vendor Tabular Items Detail' => array(
          $stock_tabular_vendor,
         ),
        'Vendor Tabular None Summary' => array(
          $stock_tabular_vendor,
         ),
        'Vendor Tabular None Detail' => array(
          $stock_tabular_vendor,
         ),
        'Inventory Tabular Orders Summary' => array(
          $stock_tabular_inventory,
         ),
        'Inventory Tabular Orders Detail' => array(
          $stock_tabular_inventory,
         ),
        'Inventory Tabular Items Summary' => array(
          $stock_tabular_inventory,
         ),
        'Inventory Tabular Items Detail' => array(
          $stock_tabular_inventory,
         ),
        'Inventory Tabular None Summary' => array(
          $stock_tabular_inventory,
         ),
        'Inventory Tabular None Detail' => array(
          $stock_tabular_inventory,
         ),
        );
        $map = InventoryRoyaltyReporter::DoMap();    
        return $map;
    }


    /**
     * @return string
     */
    function GetFirstStageXSLFile() 
    {
        $type = $this->params['type'];
        if ($this->params['type'] == '_background' || $this->params['type'] == '_email'
            || $this->params['offline_mode']) {
            $type = $this->params['offreporttype'];
        }

        if ( $type == '_pdf' || $type == '_rtf') {
            return $this->_report . '_stdxml_pdf.xsl';
        }
        return $this->_report . '_stdxml.xsl';
    }

}


