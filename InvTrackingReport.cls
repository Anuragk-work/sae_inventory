<?php
import('InventoryReporter');

/**
 * Class InvTrackingReport
 */
class InvTrackingReport extends InventoryReporter
{

    /**
     * @var array $_itemswhse
     */
    var $_itemswhse = array();

    /**
     * @var array $_std
     */
    var $_std = array();

    /**
     * @var array $_avg
     */
    var $_avg = array();
    
    /**
     * @var array $_fifo
     */
    var $_fifo = array();

    /**
     * @var array $_lifo
     */
    var $_lifo = array();


    /**
     * @param array $params
     */
    function __construct ($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params,
                array(
                'report' => 'invtracking',
                'title'  => 'IA.INVENTORY_TRACKING',
                'ops'    => array(
                                    'inv/lists/item/view',
                                    'inv/lists/invdocument/view',
                                    'inv/lists/warehouse/view',
                                        ),
                '2stage' => true,
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

        // reload after the validate report
        $params = $this->params['safe'];

        $fromwarehouseid        = $params['FROMWAREHOUSEID'];
        $towarehouseid            = $params['TOWAREHOUSEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $prodlineid                = $params['PRODLINEID'];


        if ($prodlineid != '%') {
            global $prodlineChildMapQry;
            $prodlineChildMapQry = " it.productlinekey in ( select productlineid from icprodline where cny# = it.cny#
                start with cny# = it.cny# and productlineid= ?
                connect by cny# = it.cny# and parentlineid = PRIOR productlineid) and ";

            $itemargs = array( $fromitemid, $toitemid, $prodlineid);
            $itemargtypes = array( 'text', 'text', 'text', 'integer' );

            $itemwhseargs = array($fromitemid,$toitemid,$fromwarehouseid,$towarehouseid, $prodlineid);
            $itemwhseargtypes = array( 'text', 'text', 'text', 'text', 'text', 'integer' );
        } else {
            $itemargs = array( $fromitemid, $toitemid);
            $itemargtypes = array( 'text', 'text', 'integer' );

            $itemwhseargs = array($fromitemid,$toitemid,$fromwarehouseid,$towarehouseid);
            $itemwhseargtypes = array( 'text', 'text', 'text', 'text', 'integer' );
        }

        //$filterlocation = $this->_getLocationClause($params, 'docentry');
        //$filterdept = $this->_getDeptClause($params, 'docentry');

        $WHOwnershipFilter = ( IsMultiEntityCompany() && GetContextLocation() ? $this->_getLocationClause($params, 'wh') : '' );

        /** @noinspection PhpUndefinedVariableInspection */
        $itemcode = array(
        'QUERY'=> "SELECT
							rownum,
							it.itemid itemid,
							it.locationkey ITOWNERLOC,
							it.name description,
							it.itemid||' - '||it.name as item,
							it.productlinekey||' - '||pl.description productline,
							uom.unit uom,
							it.std_uom,
							it.whenlastsold as itemwhenlastsold,
							it.whenlastreceived as itemwhenlastreceived,
							decode(it.cost_method, 'S','IA.STANDARD','A','IA.AVERAGE','F','IA.FIFO',	'L','IA.LIFO','O','IA.LOT','#','IA.SERIAL_NO', NULL) cost_method
				FROM	icitem it, icprodline pl, icuom uom
				WHERE	it.itemid between ? and ?  and it.itemtype='I' and 
						".$prodlineChildMapQry."
						it.producttype <> 'PROFSERVICE' and
						it.cny# = ? and
						pl.productlineid (+) = it.productlinekey  and
						uom.record# (+)= it.std_uom and
						pl.cny# (+) = it.cny# and
						uom.cny# (+)= it.cny#   
				ORDER BY  itemid",
        'ARGTYPES' => $itemargtypes
        );
        $items = $this->_QM->DoCustomQuery($itemcode, $itemargs, true);
        $this->_items = ( $items ?: array() );

        $itemwhsecode = array(
        'QUERY'=> "SELECT
							rownum,
							itw.itemkey itemid,
							itw.warehousekey warehouseid,
							itw.warehousekey||' - '||wh.name warehouse,
							itw.whenlastsold as whsewhenlastsold,
							itw.whenlastreceived as whsewhenlastreceived,
							itw.last_cost,
							pl.productlineid,
							it.locationkey ITOWNERLOC,
							wh.locationkey WHOWNERLOC
				FROM	icitemwhse itw, icwarehouse wh, icitem it, icprodline pl 
				WHERE	(it.itemid between ? and ? and it.itemtype='I' and itw.warehousekey between ? and ?) and 
						".$prodlineChildMapQry."
						itw.cny# = ? and
						wh.location_no = itw.warehousekey and
						wh.cny# = itw.cny# and
						itw.cny# = it.cny# and
						it.itemid = itw.itemkey and
						it.producttype <> 'PROFSERVICE' and
						pl.cny# (+) = it.cny# and
						pl.productlineid (+) = it.productlinekey $WHOwnershipFilter 
				ORDER BY  warehouseid",
        'ARGTYPES' => $itemwhseargtypes
        );
        $itemswhse = $this->_QM->DoCustomQuery($itemwhsecode, $itemwhseargs, true);
        $this->_itemswhse = ( $itemswhse ?: array() );


        if ($prodlineid != '%') {
            $avgcodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'A', $prodlineid);
            $avgcodeargtypes = array('text','text','text','text', 'text','text','integer','integer','integer','integer','integer','integer');

            $stdcodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'S', $prodlineid);
        } else {
            $avgcodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'A');
            $avgcodeargtypes = array('text','text','text','text', 'text','integer','integer','integer','integer','integer','integer');

            $stdcodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'S');
        }

        $avgcode = array(
        'QUERY' =>
        "SELECT
				it.itemid,
				it.name,
				it.std_uom,
				itmwhse.average_cost,
				itmwhse.standard_cost,
				itmwhse.warehousekey,
				it.cost_method,
				wh.name as warehousename,
				it.locationkey ITOWNERLOC,
				wh.locationkey WHOWNERLOC,
				itmtots.qtyonhand as quantity,
				(itmtots.qtyonhand * itmwhse.average_cost) as avgvalue,
				(itmtots.qtyonhand * itmwhse.standard_cost) as stdvalue
			FROM
				icitem it,
				v_itemavail itmtots,
				icitemwhse itmwhse,
				icwarehouse wh,
				icprodline pl
			WHERE
				it.itemid between ? and ? and it.itemtype='I'  and
				it.producttype <> 'PROFSERVICE' and 
				itmwhse.warehousekey between ? and ? and
				it.cost_method = ? and 
				".$prodlineChildMapQry."
				itmtots.qtyonhand != 0 and
				itmwhse.warehousekey = wh.location_no and
				itmwhse.itemkey = it.itemid and
				itmtots.warehousekey = itmwhse.warehousekey and
				it.itemid = itmtots.itemkey and
				pl.productlineid (+) = it.productlinekey and
				pl.cny# (+) = ? and
				itmwhse.cny# = ? and
				wh.cny# = ? and
				itmtots.cny# = ? and
				it.cny# = ? $WHOwnershipFilter
			",
        'ARGTYPES' => $avgcodeargtypes
        );

        $this->_avg = $this->_QM->DoCustomQuery($avgcode, $avgcodeargs, true);
        $this->_std = $this->_QM->DoCustomQuery($avgcode, $stdcodeargs, true);

        if ($prodlineid != '%') {
            $fifocodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'F', $prodlineid);
            $lifocodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'L', $prodlineid);

            $fifolifocodeargtypes = array('text','text','text','text','text', 'text', 'integer','integer','integer','integer','integer','integer','integer','integer');

        } else {
            $fifocodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'F');
            $lifocodeargs = array( $fromitemid, $toitemid, $fromwarehouseid, $towarehouseid, 'L');

            $fifolifocodeargtypes = array('text','text','text','text','text','integer','integer','integer','integer','integer','integer','integer','integer');
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $fifolifocode = array(
        'QUERY' =>
        "SELECT
				it.itemid,
				it.name,
				it.std_uom,
				it.cost_method,
				itmwhse.warehousekey,
				wh.name as warehousename,
				it.locationkey ITOWNERLOC,
				wh.locationkey WHOWNERLOC,
				dochdr.melocationkey DOCOWNERLOC,
				itmtots.qtyonhand as quantity,
				dochdr.docno,
				dochdr.whencreated,
				docentry.quantity as originalquantity,
				docentry.lineno,
				docpar.updinv,
				docpar.docclass,
				docpar.description,
				dochdr.docid as transdescription,
				doccost.cost,
				doccost.qtyleft,
				(doccost.cost / doccost.quantity * doccost.qtyleft) as value,
				(doccost.cost / doccost.quantity) as costeach
			FROM
				icitem it,
				v_itemavail itmtots,
				icitemwhse itmwhse,
				icwarehouse wh,
				docentrycost doccost,
				docentry docentry,
				docpar docpar,
				dochdrmst dochdr,
				icprodline pl
			WHERE
				it.itemid between ? and ? and it.itemtype='I' and
				it.producttype <> 'PROFSERVICE' and 
				itmwhse.warehousekey between ? and ? and
				it.cost_method = ? and
				".$prodlineChildMapQry."
				itmtots.qtyonhand != 0 and
				doccost.qtyleft != 0 and 
				docpar.in_out = 'I' and
				itmtots.warehousekey = itmwhse.warehousekey and
				itmwhse.warehousekey = wh.location_no and
				itmwhse.itemkey = it.itemid and
				it.itemid = itmtots.itemkey and
				doccost.cny# = docentry.cny# and
				doccost.docentrykey = docentry.record# and
				doccost.whsekey = itmwhse.warehousekey and
				doccost.itemkey = itmwhse.itemkey and
				docentry.dochdrkey = dochdr.record# and
				dochdr.docparkey = docpar.record# and
				pl.productlineid (+) = it.productlinekey and
				pl.cny# (+) = it.cny# and
				itmwhse.cny# = ? and
				wh.cny# = ? and
				itmtots.cny# = ? and
				it.cny# = ? and
				dochdr.cny# = ? and
				docpar.cny# = ? and
				docentry.cny# = ?
				$filterdept
				$filterlocation	$WHOwnershipFilter ",
        'ARGTYPES' => $fifolifocodeargtypes
        );

        $this->_fifo = $this->_QM->DoCustomQuery($fifolifocode, $fifocodeargs, true);
        $this->_lifo = $this->_QM->DoCustomQuery($fifolifocode, $lifocodeargs, true);

        // epp("Leaving DoQuery");
        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $params = $this->params['safe'];
        $sortmode        = $params['SORTMODE'];
        $valuemode        = $params['VALUEMODE'];
        $dlamode        = $params['DLAMODE'];
        $smode            = $params['SUMMARYMODE'];
        $zeros            = $params['SHOWZEROQUANTITIES'];
        $fromvalue        = $params['FROMVALUE'];
        $tovalue        = $params['TOVALUE'];

        if ( $smode == 'Default' ) {
            $smode = 'Detail';
        }
        $a = array();
        // Fill in the header array here
        // epp("Dla mode is $dlamode");
        $thedlamodes = array(
         'Days since Last Sold/Rcvd'     => array( 'max','days' ),
         'Days since Last Sold'             => array( 'sold','days' ),
         'Days since Last Rcvd'            => array( 'rcvd','days' ),
         'Date Last Sold/Rcvd'            => array( 'max','date' ),
         'Date Last Sold'                => array( 'sold','date' ),
         'Date Last Rcvd'                => array( 'rcvd','date' ),
                        );
        $thisdlamode = $thedlamodes[$dlamode];
        $thisdla_calculate = $thisdlamode[0];
        $thisdla_display = $thisdlamode[1];

        //Walk item array
        foreach($this->_items as $item){
            // initialize item totals to zero
            $id = $item['ITEMID'];
            $a[$id]['ITEMID']         = $id;
            $a[$id]['ITOWNERLOC'] = $item['ITOWNERLOC'];
            $a[$id]['ITEM']         = $item['ITEM'];
            $a[$id]['DESCRIPTION']    = $item['DESCRIPTION'];
            $a[$id]['COST_METHOD']     = $item['COST_METHOD'];
            $a[$id]['UOM']             = $item['UOM'];
            $a[$id]['PRODUCTLINE']    = $item['PRODUCTLINE'];
            $a[$id]['QUANTITY']     = 0;
            $a[$id]['VALUE']         = 0;
            $a[$id]['COSTEACH']        = 0;
            $a[$id]['LASTCOST']        = 0;
            $a[$id]['LASTCOSTDLA']    = MAX_NUMBER_OF_DAYS; // obviously bogus value, so our compare will work int he warehouse loop
            $a[$id]['LASTSOLD']        = $item['ITEMWHENLASTSOLD'];
            $a[$id]['LASTRCVD']        = $item['ITEMWHENLASTRECEIVED'];

            if ( $thisdla_calculate == 'max' ) {
                $sold = $this->DateToDays($item['ITEMWHENLASTSOLD']);
                $rcvd = $this->DateToDays($item['ITEMWHENLASTRECEIVED']);

                if (         ( $sold != MAX_NUMBER_OF_DAYS and $rcvd != MAX_NUMBER_OF_DAYS and $sold > $rcvd )
                    or ( $sold == MAX_NUMBER_OF_DAYS and $rcvd != MAX_NUMBER_OF_DAYS )
                ) {
                    // epp("using rcvd");
                    $days    = $rcvd;
                    $date    = $item['ITEMWHENLASTRECEIVED'];
                } else {
                    // epp("Using sold");
                    $days    = $sold;
                    $date    = $item['ITEMWHENLASTSOLD'];
                }
            }

            if ( $thisdla_calculate == 'sold' ) {
                $days    = $this->DateToDays($item['ITEMWHENLASTSOLD']);
                $date    = $item['ITEMWHENLASTSOLD'];
            }

            if ( $thisdla_calculate == 'rcvd' ) {
                $days    = $this->DateToDays($item['ITEMWHENLASTRECEIVED']);
                $date    = $item['ITEMWHENLASTRECEIVED'];
            }
            /** @noinspection PhpUndefinedVariableInspection */
            if ( !is_numeric($days) || $days == MAX_NUMBER_OF_DAYS ) {
                $days = -1; // this will give us a flag that the date is bogus.
            }

            $a[$id]['DLADAYS']        = $days;
            /** @noinspection PhpUndefinedVariableInspection */
            $a[$id]['DLA']            = $date;
        }

        //Walk warehouse array
        foreach($this->_itemswhse as $whse) {
            $id = $whse['ITEMID'];
            $whseid = $whse['WAREHOUSEID'];

            // Check this warehouse's last cost to see if we should promote it to the item level
            $thiswhselastcostdla = $this->DateToDays($whse['WHSEWHENLASTRECEIVED']);

            if ( $thiswhselastcostdla < $a[$id]['LASTCOSTDLA'] ) {

                // since this is a newer last cost, use it
                $a[$id]['LASTCOST'] = $whse['LAST_COST'];
                $a[$id]['LASTCOSTDLA'] = $whse['WHSEWHENLASTRECEIVED'];

            } elseif ($thiswhselastcostdla == $a[$id]['LASTCOSTDLA'] ) {

                // it's the same age, use it if it's higher
                if ($a[$id]['LASTCOST'] < $whse['LAST_COST']) {
                    $a[$id]['LASTCOST'] = $whse['LAST_COST'];
                    $a[$id]['LASTCOSTDLA'] = $whse['WHSEWHENLASTRECEIVED'];
                }
            }

            // If the user wants warehouse level info, fill in the array.
            if (! ($smode=='Item Summary') ) {
                $a[$id]['WAREHOUSE'][$whseid]['NAME']         = $whseid;
                $a[$id]['WAREHOUSE'][$whseid]['QUANTITY']     = 0;
                $a[$id]['WAREHOUSE'][$whseid]['VALUE']         = 0;

                if ( $thisdla_calculate == 'max' ) {

                    $sold = $this->DateToDays($whse['WHSEWHENLASTSOLD']);
                    $rcvd = $this->DateToDays($whse['WHSEWHENLASTRECEIVED']);

                    if (          ( $sold != MAX_NUMBER_OF_DAYS and $rcvd != MAX_NUMBER_OF_DAYS and $sold > $rcvd )
                        or ( $sold == MAX_NUMBER_OF_DAYS and $rcvd != MAX_NUMBER_OF_DAYS )
                    ) {
                        $days    = $rcvd;
                        $date    = $whse['WHSEWHENLASTRECEIVED'];
                    } else {
                        $days    = $sold;
                        $date    = $whse['WHSEWHENLASTSOLD'];
                    }
                }

                if ( $thisdla_calculate == 'sold' ) {
                    $days    = $this->DateToDays($whse['WHSEWHENLASTSOLD']);
                    $date    = $whse['WHSEWHENLASTSOLD'];
                }

                if ( $thisdla_calculate == 'rcvd' ) {
                    $days    = $this->DateToDays($whse['WHSEWHENLASTRECEIVED']);
                    $date    = $whse['WHSEWHENLASTRECEIVED'];
                }
                /** @noinspection PhpUndefinedVariableInspection */
                if ( !is_numeric($days) || MAX_NUMBER_OF_DAYS ) {
                    $days = -1; // this will give us a flag that the date is bogus.
                }
                $a[$id]['WAREHOUSE'][$whseid]['DLADAYS']    = $days;
                /** @noinspection PhpUndefinedVariableInspection */
                $a[$id]['WAREHOUSE'][$whseid]['DLA']        = $date;
                $a[$id]['WAREHOUSE'][$whseid]['LASTSOLD']    = $whse['WHSEWHENLASTSOLD'];
                $a[$id]['WAREHOUSE'][$whseid]['LASTREC']    = $whse['WHSEWHENLASTRECEIVED'];
                $a[$id]['WAREHOUSE'][$whseid]['LASTCOST']    = $whse['LAST_COST'];
            }
        }
        $stdavg[] = $this->_std;
        $stdavg[] = $this->_avg;

        $fieldnames = array(
        'Standard'     => 'STDVALUE',
        'Average'     => 'AVGVALUE',
        );

        foreach($stdavg as $thisstdavg){
            foreach($thisstdavg as $trans){
                $id = $trans['ITEMID'];
                $thecostingmethod = $a[$id]['COST_METHOD'];
                $thevaluestring = $fieldnames[$thecostingmethod];

                $a[$id]['QUANTITY'] += $trans['QUANTITY'];
                $a[$id]['VALUE']     += $trans[$thevaluestring];

                if ( $smode=='Warehouse Summary' or $smode=='Detail' ) {
                    $whseid = $trans['WAREHOUSEKEY'];
                    // Update warehouse totals
                    $a[$id]['WAREHOUSE'][$whseid]['QUANTITY']     += $trans['QUANTITY'];
                    $a[$id]['WAREHOUSE'][$whseid]['VALUE']         += $trans[$thevaluestring];
                }
            }
        }

        $fifolifo[] = $this->_fifo;
        $fifolifo[] = $this->_lifo;

        foreach($fifolifo as $thisfifolifo) {
            foreach($thisfifolifo as $trans){
                $id = $trans['ITEMID'];
                $updatesInv = $trans['UPDINV'];
                $class = $trans['DOCCLASS'];
                $qtyzero = $updatesInv == 'V' && $class == 'ADJ';

                $whseid = $trans['WAREHOUSEKEY'];

                $trans['QTYLEFT'] = ($qtyzero) ? 0 : $trans['QTYLEFT'];
                $trans['COSTEACH'] = ($qtyzero) ? 0 : $trans['COSTEACH'];

                $a[$id]['QUANTITY'] += $trans['QTYLEFT'];
                $a[$id]['VALUE']     += $trans['VALUE'];
                if ($trans['QTYLEFT'] == '') {
                    //There was no quantity left, therefore it's an uncosted amount.
                    $a[$id]['UNCOSTEDQUANTITY'] += $trans['ORIGINALQUANTITY'];
                }

                if ( $smode=='Warehouse Summary' or $smode=='Detail' ) {
                    // Update warehouse totals
                    $a[$id]['WAREHOUSE'][$whseid]['QUANTITY']     += $trans['QTYLEFT'];
                    $a[$id]['WAREHOUSE'][$whseid]['VALUE']         += $trans['VALUE'];
                    if ($trans['QTYLEFT'] == '') {
                        $a[$id]['WAREHOUSE'][$whseid]['UNCOSTEDQUANTITY']     += $trans['ORIGINALQUANTITY'];
                    }
                }
                if ($smode=='Detail' ) {
                    $t = array();
                    $t['DOCNO']                 = $trans['DOCNO'];
                    $t['TRANSDESCRIPTION']     = $trans['TRANSDESCRIPTION'];
                    $t['DATE']                 = $trans['WHENCREATED'];
                    $t['QUANTITY']             = $trans['QTYLEFT'];
                    $t['COSTEACH']             = $trans['COSTEACH'];
                    $t['VALUE']             = $trans['VALUE'];
                    $t['DOCOWNERLOC']         = $trans['DOCOWNERLOC'];
                    // 	$t['QUANTITY'] 			= $trans['QTYLEFT'];
                    // put transaction into array
                    $a[$id]['WAREHOUSE'][$whseid]['TRANSACTION'][] = $t;
                }
            }
        }
        reset($a);

        /* Since we'll be sorting by things in the array, we need to calc the unitcost here, before the sorting.
        We cant wait until we move the array to the xmlish array anymore.
        */
        foreach ($a as $item){
            // avoid divide by zero error.
            $key = $item['ITEMID'];
            if ($item['QUANTITY'] != 0) {    
                $item['COSTEACH'] = $item['VALUE']/$item['QUANTITY'];
                $a[$key]['COSTEACH'] = $item['VALUE']/$item['QUANTITY'];
            } else {
                $item['COSTEACH'] = $a[$key]['COSTEACH'] = 0;
            }
        }
        /* Now we will build a simple array from the base array.
        This array will be used for sorting the results.
        It will have the same number of elements as we have items
        The field we want to sort on will be pulled into the simple array
        Then we'll do a array_multisort.

        */
        $sorts = array(
        'Default'                => array('ITEMID','SORT_STRING','SORT_ASC'),
        'Item'                     => array('ITEMID','SORT_STRING','SORT_ASC'),
        'Value'                     => array('VALUE','SORT_NUMERIC','SORT_ASC'),
        'Value Desc'            => array('VALUE','SORT_NUMERIC','SORT_DESC'),
        'Unit Cost'             => array('COSTEACH','SORT_NUMERIC','SORT_ASC'),
        'Unit Cost Desc'        => array('COSTEACH','SORT_NUMERIC','SORT_DESC'),
        'Quantity'                 => array('QUANTITY','SORT_NUMERIC','SORT_ASC'),
        'Quantity Desc'            => array('QUANTITY','SORT_NUMERIC','SORT_DESC'),
        'Last Cost'             => array('LASTCOST','SORT_NUMERIC','SORT_ASC'),
        'Last Cost Desc'        => array('LASTCOST','SORT_NUMERIC','SORT_DESC'),
        'DLA'                     => array('DLADAYS','SORT_NUMERIC','SORT_ASC'),
        'DLA Desc'                => array('DLADAYS','SORT_NUMERIC','SORT_DESC'),
        'DLA Internal'            => array('DLADAYS','SORT_NUMERIC','SORT_DESC'),
        'DLA Desc Internal'        => array('DLADAYS','SORT_NUMERIC','SORT_ASC'),
        );

        // If they are displaying DLA as a date, then we need to sort the opposite way on the days field
        if ( $thisdla_display == 'date' ) {
            if ( $sortmode == 'DLA' or $sortmode == 'DLA Desc' ) {
                $sortmode .= ' Internal';
            }
        }

        $sortentry = $sorts[$sortmode];
        $sortfield = $sortentry[0];
        $sorttype = $sortentry[1];
        $sortorder = $sortentry[2];

        $ids = array();
        foreach ($a as $item){
            if ($sorttype == 'SORT_STRING') {
                $s[] = self::upperCaseFieldForArraySort($item[$sortfield]);
            } else {
                $s[] = $item[$sortfield];
            }
            $ids[] = $item['ITEMID'];
        }
        if ($sortorder=="SORT_DESC") {
            array_multisort($s, SORT_DESC, $ids);
        } else {
            array_multisort($s, SORT_ASC, $ids);
        }

        $b['GRANDTOTALTOP'][0]['VALUE'] = 0;
        $b['GRANDTOTALTOP'][0]['ITEMCOUNT'] = 0;
        //Move to another array
        $itemcounter = 0;
        // calc the grand total in this loop since we may exclude due to value filters
        $grandtotal = 0;

        $thevaluefields = array(
          'Default'             => 'VALUE',
          'Item Value'         => 'VALUE',
          'Item Quantity'     => 'QUANTITY',
          'Item Unit Cost'     => 'COSTEACH',
          'Item Last Cost'    => 'LASTCOST',
          'DLA days'            => 'DLADAYS'
                            );

        $thisvaluefield = $thevaluefields[$valuemode];

        foreach ($ids as $thisid){
            $item = $a[$thisid];
            $whsecounter = 0;
            $itemvalue = $item[$thisvaluefield];
            
            if ( ($zeros == 'true' or ($zeros == 'false' and $item['QUANTITY'] != 0)) 
                and ($itemvalue >= $fromvalue and $itemvalue <= $tovalue) 
            ) {

                $itemcounter ++;
                $grandtotal += $item['VALUE'];

                $b['ITEMS'][$itemcounter]['ITEMID']         = $item['ITEMID'];
                //$b['ITEMS'][$itemcounter]['HREF'] 			= "javascript:drilldown(0,'" . urlencode(addslashes($item['ITEMID'])) . "');";
                $itemInc = urlencode(addslashes($item['ITEMID']));
                $itemOWLOC = $item['ITOWNERLOC'];
                $b['ITEMS'][$itemcounter]['HREF']             = "javascript:drilldown(0,'$itemInc', '$itemOWLOC');";

                $b['ITEMS'][$itemcounter]['ITEM']             = $item['ITEM'];
                $b['ITEMS'][$itemcounter]['DESCRIPTION']     = $item['DESCRIPTION'];
                $b['ITEMS'][$itemcounter]['COST_METHOD']     = $item['COST_METHOD'];
                $b['ITEMS'][$itemcounter]['UOM']             = $item['UOM'];
                $b['ITEMS'][$itemcounter]['PRODUCTLINE']    = $item['PRODUCTLINE'];
                $b['ITEMS'][$itemcounter]['QUANTITY']         = $item['QUANTITY'];
                $b['ITEMS'][$itemcounter]['VALUE']             = glFormatCurrency($item['VALUE']);
                $b['ITEMS'][$itemcounter]['COSTEACH']        = $this->roundUnitCost($item['ITEMID'], $item['COSTEACH']);
                $b['ITEMS'][$itemcounter]['LASTCOST']        = $this->roundUnitCost($item['ITEMID'], $item['LASTCOST']);
                $b['ITEMS'][$itemcounter]['LASTSOLD']        = $item['LASTSOLD'];
                $b['ITEMS'][$itemcounter]['LASTRCVD']         = $item['LASTRCVD'];

                if ($thisdla_display == 'date' ) {
                    $b['ITEMS'][$itemcounter]['DLA']    = FormatDateForDisplay($item['DLA']);
                } else {
                    $b['ITEMS'][$itemcounter]['DLA']    = $item['DLADAYS'];
                }

                if (isset($item['WAREHOUSE'])) {
                    foreach ($item['WAREHOUSE'] as $whse){
                        if ( $zeros == 'true' or ($zeros == 'false' and $whse['QUANTITY'] != 0) ) {
                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['NAME']         = $whse['NAME'];
                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['QUANTITY']     = $whse['QUANTITY'];
                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['VALUE']         = glFormatCurrency($whse['VALUE']);

                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['COSTEACH']    =
                            ($whse['QUANTITY'] == 0) ? 0 : $this->roundUnitCost($item['ITEMID'], $whse['VALUE']/$whse['QUANTITY']);

                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['LASTCOST']     = $this->roundUnitCost($item['ITEMID'], $whse['LASTCOST']);
                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['LASTSOLD']     = $whse['LASTSOLD'];
                            $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['LASTREC']     = $whse['LASTREC'];
                            if ($thisdla_display == 'date' ) {
                                $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['DLA']         = FormatDateForDisplay($whse['DLA']);
                            } else {
                                $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['DLA']        = $whse['DLADAYS'];
                            }

                            $transcounter = 0;
                            if (isset($whse['TRANSACTION'])) {
                                foreach ($whse['TRANSACTION'] as $trans){
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['DOCNO']             = $trans['DOCNO'];
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['TRANSDESCRIPTION']     = $trans['TRANSDESCRIPTION'];
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['DATE']                 = FormatDateForDisplay($trans['DATE']);
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['QUANTITY']             = $trans['QUANTITY'];
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['COSTEACH']             = $this->roundUnitCost($item['ITEMID'], $trans['COSTEACH']);
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['VALUE']             = glFormatCurrency($trans['VALUE']);
                                    $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['HREF']                 = "javascript:drilldown(1,'" . urlencode($trans['TRANSDESCRIPTION']) . "', '$trans[DOCOWNERLOC]');";

                                    //"javascript:drilldown(0,'" . urlencode(addslashes($item['ITEMID'])) . "');";
                                    //					glFormatCurrency($trans['VALUE']);
                                    //"javascript:drilldown(0,'" . urlencode(addslashes($item['ITEMID'])) . "');";
                                    //$b['ITEMS'][$itemcounter]['HREF'] = "javascript:drilldown(0,'" . urlencode(addslashes($item['ITEMID'])) . "');";

                                    $itemInc = urlencode(addslashes($item['ITEMID']));
                                    $itemOWLOC = $item['ITOWNERLOC'];
                                    $b['ITEMS'][$itemcounter]['HREF'] = "javascript:drilldown(0,'$itemInc', '$itemOWLOC');";

                                    $transcounter ++;
                                }
                            }
                            $whsecounter ++;
                        }
                    }
                }
            }
        }
        $displaygrandtotal = glFormatCurrency($grandtotal);
        $b['GRANDTOTAL'][0]['VALUE'] = $displaygrandtotal;
        $b['GRANDTOTAL'][0]['ITEMCOUNT'] = $itemcounter;
        $b['GRANDTOTALTOP'][0]['VALUE'] = $displaygrandtotal;
        $b['GRANDTOTALTOP'][0]['ITEMCOUNT'] = $itemcounter;
        // epp("Exiting Do Map");

        $lines = $this->InvCommonHeader();

        $lines['report'][0]['summary'] = $smode;
        $lines['report'][0]['showzeros'] = $zeros;

        $lines = $this->InvCommonBody($lines, $b);
        return $lines;
    }

}
