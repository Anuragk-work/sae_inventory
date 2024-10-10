<?php
import('GroupReporter');
require_once 'Dictionary.cls';

define('MAX_NUMBER_OF_DAYS', '9999999');
//  class InventoryReport extends GroupReporter
class InventoryReporter extends GroupReporter
{
    /** @var bool  $_ismcpEnabled*/
    var $_ismcpEnabled;

    /** @var int[]|string[] $itemprecision  */
    var $itemprecision;

    /** @var  bool|string[][] $_docs */
    var $_docs;

    /** @var  array $_dochdr */
    var $_dochdr;

    /** @var  array $_docentry */
    var $_docentry;

    /** @var  array $_headerstatus */
    var $_headerstatus;

    /** @var  array $_status */
    var $_status;

    /** @var  array $totals */
    var $totals;

    /**
     * @var array $_items
     */
    var $_items = array();

    /**
     * @var bool $isatlas
     */
    var $isatlas = false;

    /**
     * @var array $_itemlist
     */
    var $_itemlist = array();

    /** @var string $prodlineChildMapQry */
    protected $prodlineChildMapQry = '';

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(INTACCTarray_merge($params, array('reportslide' => true)));

        $mod = Request::$r->_mod;
        $this->_ismcpEnabled = IsMCPEnabled($mod);
        $this->isatlas = IsMCMESubscribed();
    }

    /**
     * @return bool
     */
    function DoQuery() 
    {
        if(!$this->ValidateReport()) {
            return false;
        }

        $this->params['safe']['FILTERTRANSACTIONS'] = $this->params['FILTERTRANSACTIONS'];
        $params = $this->params['safe'];

        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];
        $fromcustid                = $params['FROMCUSTOMERID'];
        $tocustid                = $params['TOCUSTOMERID'];
        $fromvendorid            = $params['FROMVENDORID'];
        $tovendorid                = $params['TOVENDORID'];
        $dt1                    = $params['dt1'];
        $dt2                    = $params['dt2'];

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

        $whereclause = $this->params['whereclause'][$this->params['custvend']];
        $datefilter = $this->params['whereclause']['datefilter'];

        $args = array('sql', $cny, ); //$fromitemid, $toitemid, $dt1, $dt2, $fromcustvendid, $tocustvendid);

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
            $orderBy = "itemkey";
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

            $orderBy = "upc";
        }

        $selectmcp="";
        $currencyfilter="";

        if ($this->params['custvend'] == 'vend') {
            $casewhen_convertbyline='';
        }else{
            $casewhen_convertbyline = $this->params['whereclause']['licselect'];
            $casewhen_convertbyline = ($casewhen_convertbyline != '' )? $casewhen_convertbyline :'';

        }

        if($this->_ismcpEnabled) {
            $baseCurrency = GetBaseCurrency();
            $selectmcp = ", docentry.currency,
							CASE WHEN (dochdr.state='P' $casewhen_convertbyline) THEN
								round(((docentry.quantity - docentry.qty_converted)*(docentry.price / nvl(docentry.exchange_rate,1))),3)
							ELSE
                                docentry.trx_value
							END trx_value,
							((docentry.uiqty*docentry.trx_price) / docentry.quantity) trxprice";
            //$selectmcp = ", docentry.currency, (docentry.uiqty * docentry.trx_price) trxprice, docentry.trx_value";
            if($this->params['CURRENCY']!='') {
                //$currencyfilter = ($currency!='') ? " and docentry.currency='".$currency."'" : "";
                $currencyfilter = " and DECODE(docentry.currency, NULL, '$baseCurrency', docentry.currency) = '".$this->params['CURRENCY']."'";
            }
        }

        if ($this->params['custvend'] == 'vend') {

            $qryselect = "SELECT
							vendor.vendorid as id,
							vendor.name as name,
							vendor.locationkey as ENOWNERLOC,
							dochdr.record# as hdrrec,
							dochdr.docno,
							dochdr.docid,
							dochdr.whencreated,
							dochdr.whendue,
							dochdr.melocationkey,
							to_char(to_date(dochdr.whendue)-SYSDATE,'9999999') as daystodue,
							icitem.itemid as itemkey,
							icitem.locationkey as ITOWNERLOC,
							icitem.name as itemdescr,
							docentry.dochdrkey,
							CASE WHEN (dochdr.state='P') THEN
                                docentry.quantity - docentry.qty_converted
                            ELSE
                                docentry.quantity
                            END quantity,
							docentry.price,
							CASE WHEN (dochdr.state='P') THEN
								(docentry.quantity - docentry.qty_converted)*docentry.price
							ELSE
								(docentry.quantity*docentry.price)
							END value,
							icitem.upc $selectmcp
						FROM docentry, docpar, dochdr, vendor, icitem, docpar latestversion
						WHERE
							icitem.cny# = :1 and
							". $filterItemorUPC ." and
							----
							docentry.cny# = icitem.cny# and
							docentry.itemkey = icitem.itemid and
							--
							docentry.dochdrkey = dochdr.record# and
							docentry.cny# = dochdr.cny# and
							docentry.quantity != 0 and
							((docentry.quantity != docentry.qty_converted and dochdr.state='P') or dochdr.state in ('O','C','D')) and
							--- external datefilter contains :4 and :5
							". $datefilter . "
							---
							dochdr.vendentity = vendor.entity and
							vendor.cny# = dochdr.cny# and
							vendor.vendorid >= :6 and
							vendor.vendorid <= :7 and
							---
							dochdr.docparkey = docpar.record# and
							dochdr.cny# = docpar.cny# and
							--
							docpar.cny# = latestversion.cny#(+) and
							docpar.latestversionkey = latestversion.record#(+) and
							--external where section
							$whereclause
							$filterdept
							$filterlocation
							$currencyfilter
							-- end external where
						ORDER BY $orderBy, id, dochdrkey";
            $fromcustvendid = $fromvendorid;
            $tocustvendid = $tovendorid;

        } else {
            $LICfilter =  $this->params['whereclause']['licfilter'];
            $LICfilter = ($LICfilter != '' )? $LICfilter :'';

            $qryselect = "SELECT
							customer.customerid as id,
							customer.name as name,
							customer.locationkey as ENOWNERLOC,
							dochdr.docno,
							dochdr.docid,
							dochdr.whencreated,
							dochdr.whendue,
							dochdr.melocationkey,
							dochdr.record# as hdrrec,
							to_char(to_date(dochdr.whendue)-SYSDATE,'9999999') as daystodue,
							icitem.itemid as itemkey,
							icitem.locationkey as ITOWNERLOC,
							icitem.name as itemdescr,
							docentry.dochdrkey,
							CASE WHEN (dochdr.state='P' $casewhen_convertbyline) THEN
                                docentry.quantity - docentry.qty_converted
                            ELSE
                                docentry.quantity
                            END quantity,
							docentry.price,
							CASE WHEN (dochdr.state='P' $casewhen_convertbyline) THEN
								(docentry.quantity - docentry.qty_converted)*docentry.price
							ELSE
								(docentry.quantity*docentry.price)
                            END value,
							icitem.upc $selectmcp
						FROM docentry, docpar, dochdr, customer, icitem, docpar latestversion
						WHERE
							icitem.cny# = :1 and
							". $filterItemorUPC . " and
							----
							docentry.cny# = icitem.cny# and
							docentry.itemkey = icitem.itemid and
							--
							docentry.dochdrkey = dochdr.record# and
							docentry.cny# = dochdr.cny# and
							docentry.quantity != 0 and
							$LICfilter
							((docentry.quantity != docentry.qty_converted and dochdr.state='P') or dochdr.state in ('O','C','D', 'L', 'B')) and
							--- external datefilter contains :4 and :5
							". $datefilter . "
							---
							dochdr.custentity = customer.entity and
							customer.cny# = dochdr.cny# and
							customer.customerid >= :6 and
							customer.customerid <= :7 and
							---
							dochdr.docparkey = docpar.record# and
							dochdr.cny# = docpar.cny# and
							--
							docpar.cny# = latestversion.cny#(+) and
							docpar.latestversionkey = latestversion.record#(+) and
							--external where section
							$whereclause $filterdept $filterlocation $currencyfilter
							-- end external where
						ORDER BY $orderBy, id, dochdrkey";
            $fromcustvendid = $fromcustid;
            $tocustvendid = $tocustid;
        }
        array_push($args, $dt1, $dt2, $fromcustvendid, $tocustvendid);
        $args[0] = $qryselect;

        //$this->_itemlist = QueryResult(array($qryselect, $cny, $fromitemid, $toitemid, $dt1, $dt2, $fromcustvendid, $tocustvendid));
        $this->_itemlist = QueryResult($args);
        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {

        $params = $this->params['safe'];
        $fromvalue                = $params['FROMVALUE'];
        $tovalue                = $params['TOVALUE'];
        $valuemode                = $params['VALUEMODE'];
        $sortmode                = $params['SORTMODE'];

        $itemsMap = array();
        $i = 0;


        $itemlist = $this->_itemlist;

        if ($this->params['reportby'] == 'vend' || $this->params['reportby'] == 'cust') {

            // go through each line and create an indexed map
            $docs = array();
            $locref = $params['locs'][0];

            foreach($itemlist as $row) {

                $thisdoc = $row['HDRREC'];
                $loclink = $row['MELOCATIONKEY'] ?? $locref;

                //Initialization
                if (!$docs[$thisdoc]) {
                    $docs[$thisdoc] = array(
                    'HDRREC'        => $thisdoc,
                    'ID'             => $row['ID'],
                    'HREF'            => "javascript:drilldown(0,'" . urlencode($row['ID']) . "', '$row[ENOWNERLOC]');",
                    'NAME'             => $row['NAME'],
                    'DOCNO'            => $row['DOCNO'],
                    'DOCID'            => $row['DOCID'],
                    'DOCHREF'         => "javascript:drilldown(1,'" . urlencode($row['DOCID']) . "','$loclink');",
                    'WHENDUE'         => $row['WHENDUE'],
                    'WHENCREATED'     => $row['WHENCREATED'],
                    'DAYSTODUE'        => $row['DAYSTODUE'],
                    'TOTALUNITCOST'    => 0,
                    'TOTALQUANTITY'    => 0,
                    'TOTALVALUE'    => 0,
                    'INPAST'        => (strtotime($row['WHENDUE']) < time() ) ? "yes" : "no",
                    'ENTRIES'        => array(),
                    'DEPARTMENT'    =>    $row['DEPARTMENT'],
                    'LOCATION'        =>    $row['LOCATION'],
                    'SHDEPT'        =>    $row['SHDEPT'],
                    'SHLOC'            =>    $row['SHLOC'],
                    );
                }
                $rvalue = ($this->_ismcpEnabled) ? iround($row['VALUE'], 2) : $row['VALUE'];
                //Line items
                /** @noinspection PhpUndefinedVariableInspection */
                $docs[$thisdoc]['ENTRIES'][] = array(
                'DOCHDRKEY' => $dockey,
                'ITEMKEY'    => $row['ITEMKEY'],
                'UPC'        => $row['UPC'],
                'ITEMHREF'     => "javascript:drilldown(2,'" . urlencode(addslashes($row['ITEMKEY'])) . "', '$row[ITOWNERLOC]');",
                'ITEMDESCR'    => $row['ITEMDESCR'],
                'QUANTITY'    => $row['QUANTITY'],
                'PRICE'        => $this->roundUnitCost($row['ITEMKEY'], $row['PRICE']),
                //	'VALUE'		=> glFormatCurrency($rvalue),
                'VALUE'        => $rvalue,
                'CURRENCY'    => $row['CURRENCY'],
                'TRXPRICE'    => $this->roundUnitCost($row['ITEMKEY'], $row['TRXPRICE']),
                //'TRX_VALUE' => glFormatCurrency(iround($row['TRX_VALUE'],2))
                'TRX_VALUE' => $row['TRX_VALUE']
                );

                $docs[$thisdoc]['TOTALVALUE'] += $row['VALUE'];
                $docs[$thisdoc]['TOTALQUANTITY'] += $row['QUANTITY'];
            }

            if ($this->params['reportby']=='vend') {

                $sorts = array(
                'Default'                => array('DAYSTODUE','SORT_NUMERIC','SORT_ASC'),
                'Ship Date'                => array('DAYSTODUE','SORT_NUMERIC','SORT_ASC'),
                'Ship Date Desc'        => array('DAYSTODUE','SORT_NUMERIC','SORT_DESC'),
                'Vendor'                => array('ID','SORT_STRING','SORT_ASC'),
                'Vendor Desc'            => array('ID','SORT_STRING','SORT_DESC'),
                'Order Number'            => array('DOCNO','SORT_NUMERIC','SORT_ASC'),
                'Order Number Desc'        => array('DOCNO','SORT_NUMERIC','SORT_DESC'),
                'Order Price'            => array('TOTALVALUE','SORT_NUMERIC','SORT_ASC'),
                'Order Price Desc'        => array('TOTALVALUE','SORT_NUMERIC','SORT_DESC'),
                );
            } else {

                // now sort things according to user's input.
                $sorts = array(
                'Default'                => array('DAYSTODUE','SORT_NUMERIC','SORT_ASC'),
                'Ship Date'                => array('DAYSTODUE','SORT_NUMERIC','SORT_ASC'),
                'Ship Date Desc'        => array('DAYSTODUE','SORT_NUMERIC','SORT_DESC'),
                'Customer'                => array('ID','SORT_STRING','SORT_ASC'),
                'Customer Desc'            => array('ID','SORT_STRING','SORT_DESC'),
                'Order Number'            => array('DOCNO','SORT_NUMERIC','SORT_ASC'),
                'Order Number Desc'        => array('DOCNO','SORT_NUMERIC','SORT_DESC'),
                'Order Price'            => array('TOTALVALUE','SORT_NUMERIC','SORT_ASC'),
                'Order Price Desc'        => array('TOTALVALUE','SORT_NUMERIC','SORT_DESC'),
                );
            }
            $keyfield = "HDRREC";

            $ids = $this->DoSort($sorts, $keyfield, $sortmode, $docs);

            $thevaluefields = array(
            'Default'             => 'TOTALVALUE',
            'Order Price'         => 'TOTALVALUE',
            'Order Number'        => 'DOCNO',
            'Days to Ship Date'    => 'DAYSTODUE',
            );

            $thisvaluefield = $thevaluefields[$valuemode];

            foreach (($ids ??[]) as $thisid) {

                $thisdata = $docs[$thisid];
                // only include this in the output if it has entries....
                if ( isset($thisdata['ENTRIES']) ) {
                    $itemvalue = $thisdata[$thisvaluefield];

                    if ($itemvalue >= $fromvalue and $itemvalue <= $tovalue ) {

                        /** @noinspection PhpSillyAssignmentInspection */
                        $thisdata['TOTALQUANTITY'] = $thisdata['TOTALQUANTITY'];
                        $totval = $thisdata['TOTALVALUE'];
                        /** @noinspection PhpSillyAssignmentInspection */
                        $thisdata['TOTALVALUE'] = $thisdata['TOTALVALUE'];

                        if ($thisdata['TOTALQUANTITY'] > 0) {
                            $thisdata['TOTALUNITCOST'] = $totval/$thisdata['TOTALQUANTITY'];
                        } else {
                            $thisdata['TOTALUNITCOST'] = 0;
                        }

                        //						$thisdata['TOTALUNITCOST'] = glFormatCurrency($thisdata['TOTALUNITCOST']);
                        /** @noinspection PhpSillyAssignmentInspection */
                        $thisdata['TOTALUNITCOST'] = $thisdata['TOTALUNITCOST'];

                        $itemsMap[] = $thisdata;
                    }
                }
            }

        } else {

            // go through each line and create an indexed map
            $itemsArr = array();
            $locref = $params['locs'][0];

            foreach($itemlist as $item) {

                $itemkey = $item['ITEMKEY'];

                //Initialization
                if (!$itemsArr[$itemkey]) {
                    $itemsArr[$itemkey]['ITEMKEY'] = $item['ITEMKEY'];
                    $itemsArr[$itemkey]['UPC'] = $item['UPC'];
                    $itemsArr[$itemkey]['ITEMDESCR'] = $item['ITEMDESCR'];

                    $itemsArr[$itemkey]['ITEMHREF'] = "javascript:drilldown(2,'" . urlencode(addslashes($item['ITEMKEY'])) . "', '$item[ITOWNERLOC]');";

                    $itemsArr[$itemkey]['TOTALVALUE'] = 0;
                    $itemsArr[$itemkey]['TOTALUNITCOST'] = 0;
                    $itemsArr[$itemkey]['TOTALQUANTITY'] = 0;

                    $itemsArr[$itemkey]['ENTRIES'] = array();
                }
                $loclink = $item['MELOCATIONKEY'] ?? $locref;

                $value = ($this->_ismcpEnabled) ? iround($item['VALUE'], 2) : $item['VALUE'];

                $itemsArr[$itemkey]['ENTRIES'][] = array(
                'ID' => $item['ID'],
                'HREF' => "javascript:drilldown(0,'" . urlencode($item['ID']) . "', '$item[ENOWNERLOC]');",
                'NAME' => $item['NAME'],
                'WHENDUE' => $item['WHENDUE'],
                'WHENCREATED' => $item['WHENCREATED'],
                'DOCNO' => $item['DOCNO'],
                'DOCID' => $item['DOCID'],
                'DOCIDHREF' => "javascript:drilldown(1,'" . urlencode($item['DOCID']) . "','$loclink');",
                'QUANTITY' => $item['QUANTITY'],
                'PRICE' => $this->roundUnitCost($item['ITEMKEY'], $item['PRICE']),
                'WAREHOUSE' => $item['WAREHOUSEKEY'],
                'DEFAULT_SUBSECTION' => $item['DEFAULT_SUBSECTION'],
                //					'VALUE' => glFormatCurrency($value),
                'VALUE' => $value,
                'CURRENCY' =>    $item['CURRENCY'],
                'TRXPRICE'    => $this->roundUnitCost($item['ITEMKEY'], $item['TRXPRICE']),
                //					'TRX_VALUE' => glFormatCurrency(iround($item['TRX_VALUE'],2))
                'TRX_VALUE' => $item['TRX_VALUE']
                );

                $itemsArr[$itemkey]['TOTALVALUE'] += $item['VALUE'];
                $itemsArr[$itemkey]['TOTALQUANTITY'] += $item['QUANTITY'];
            }

            //We could have used array_values, but we need to format the numbers
            foreach ( $itemsArr as $itemUnit) {
                if ($itemUnit['TOTALQUANTITY'] > 0) {
                    $itemUnit['TOTALUNITCOST'] = $this->roundUnitCost($itemUnit['ENTRIES']['ID'], $itemUnit['TOTALVALUE']/$itemUnit['TOTALQUANTITY']);
                }
                $itemUnit['TOTALVALUE'] = ($this->_ismcpEnabled) ? iround($itemUnit['TOTALVALUE'], 2) : $itemUnit['TOTALVALUE'];
                //				$itemUnit['TOTALVALUE'] = glFormatCurrency($itemUnit['TOTALVALUE']);
                //				$itemUnit['TOTALQUANTITY'] = glFormatCurrency($itemUnit['TOTALQUANTITY']);
                /** @noinspection PhpSillyAssignmentInspection */
                $itemUnit['TOTALVALUE'] = $itemUnit['TOTALVALUE'];
                /** @noinspection PhpSillyAssignmentInspection */
                $itemUnit['TOTALQUANTITY'] = $itemUnit['TOTALQUANTITY'];

                $itemsMap[$i++] = $itemUnit;
            }
        }

        $lines = $this->DrawHeader($this->params);

        if (count($itemsMap)==0) {
            $itemsMap['NODATA'][0]= array('NODATA'=>'1');
        }

        $lines['report'][0]['ismcpEnabled'] = $this->_ismcpEnabled;
        $lines = $this->InvCommonBody($lines, $itemsMap);

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        return $lines;

    }

    /**
     * @param array $params
     *
     * @return array
     */
    function DrawHeader(/** @noinspection PhpUnusedParameterInspection */ $params)
    {
        return $this->InvCommonHeader();
    }

    /**
     * @param string $value
     * @param string $reportFormat
     * @param string $labelPrefix
     *
     * @return string
     */
    function getLabelPrefixForReportHeader($value, $reportFormat, $labelPrefix = "")
    {
        $labelValue = '';
        // This function will add the prefix label to value for all export format report except excel format.
        if (!empty($value)) {
            $labelValue = $value;
            if ($reportFormat != kShowExcel) {
                $labelValue = $labelPrefix . $value;
            }
        }

        return $labelValue;
    }

    /**
     * @return array
     */
    function InvCommonHeader()
    {
        // this function handles setting up the basic report header
        $_op = Request::$r->_op;
        $_sess = Session::getKey();
        
        // epp("The thisparams were ");
        // eppp($this->params);
        $params = $this->params['safe'];

        $lines['report']["0"]['title']    = $this->title;
        $lines['report']["0"]['title2']    = $this->title2;
        $lines['report']["0"]['titlecomment']    = $this->titlecomment;

        if ($params['backhere']=='' || !isset($params['backhere']) ) {
            // if they didn't spec any backhere, lets default it to everything under the sun.
            $params['backhere'] =
                 "reportor.phtml?.op=$_op&.type=" . $params['type'] 
                 ."&_obj__FROMVENDORID="   
                 . URLCleanParams::insert('_obj__FROMVENDORID', $params['FROMVENDORID']) 
                 ."&_obj__TOVENDORID="   
                 . URLCleanParams::insert('_obj__TOVENDORID', $params['TOVENDORID']) 
                 ."&_obj__FROMCUSTOMERID="
                 . URLCleanParams::insert('_obj__FROMCUSTOMERID', $params['FROMCUSTOMERID']) 
                 ."&_obj__TOCUSTOMERID="
                 . URLCleanParams::insert('_obj__TOCUSTOMERID', $params['TOCUSTOMERID'])
                 ."&_obj__FROMWAREHOUSEID="
                 . URLCleanParams::insert('_obj__FROMWAREHOUSEID', $params['FROMWAREHOUSEID'])
                 ."&_obj__TOWAREHOUSEID="
                 . URLCleanParams::insert('_obj__TOWAREHOUSEID', $params['TOWAREHOUSEID'] )
                 ."&_obj__FROMITEMID="    
                 . URLCleanParams::insert('_obj__FROMITEMID', $params['FROMITEMID']) 
                 ."&_obj__TOITEMID="     
                 . URLCleanParams::insert('_obj__TOITEMID', $params['TOITEMID']) 
                 ."&_obj__FROMDOCID="
                 . URLCleanParams::insert('_obj__FROMDOCI', $params['FROMDOCID'])
                 ."&_obj__TODOCID="       
                 . URLCleanParams::insert('_obj__TODOCID', $params['TODOCID'] )
                 ."&_obj__PRODLINEID="   
                 . URLCleanParams::insert('_obj__PRODLINEID', $params['PRODLINEID']) 
                 ."&_obj__ITEM="           
                 . URLCleanParams::insert('_obj__ITEM', $params['ITEM']) 
                 ."&_obj__CUSTOMER="
                 . URLCleanParams::insert('_obj__CUSTOMER', $params['CUSTOMER'])
                 ."&_obj__VENDOR="      
                 . URLCleanParams::insert('_obj__VENDOR', $params['VENDOR'])
                 ."&_obj__UICATEGORY="
                 . URLCleanParams::insert('_obj__UICATEGORY', $params['UICATEGORY'] )
                 ."&_obj__PRCLSTNAME="    
                 . URLCleanParams::insert('_obj__PRCLSTNAME', $params['PRCLSTNAME'])
                 ."&_obj__DOCTYPE="        
                 . URLCleanParams::insert('_obj__DOCTYPE', $params['DOCTYPE']) 
                 ."&_obj__DOCCLASS="        
                 . URLCleanParams::insert('_obj__DOCCLASS', $params['DOCCLASS'])
                 ."&_obj__UICATEGORY="
                 . URLCleanParams::insert('_obj__UICATEGORY', $params['UICATEGORY'])
                 ."&_obj__START_DATE="   
                 . URLCleanParams::insert('_obj__START_DATE', $params['dt1']) 
                 ."&_obj__END_DATE="       
                 . URLCleanParams::insert('_obj__END_DATE', $params['dt2'])
                 ."&_obj__SORTMODE="       
                 . URLCleanParams::insert('_obj__SORTMODE', $params['SORTMODE'])
                 ."&_obj__VALUEMODE="        
                 . URLCleanParams::insert('_obj__VALUEMODE', $params['VALUEMODE'])
                 ."&_obj__FROMVALUE="       
                 . URLCleanParams::insert('_obj__FROMVALUE', $params['FROMVALUE'])
                 ."&_obj__TOVALUE="       
                 . URLCleanParams::insert('_obj__TOVALUE', $params['TOVALUE'])
                 ."&_obj__DLAMODE="        
                 . URLCleanParams::insert('_obj__DLAMODE', $params['DLAMODE'])
                 ."&_obj__SUMMARYMODE="
                 . URLCleanParams::insert('_obj__SUMMARYMODE', $params['SUMMARYMODE'])
                 ."&_obj__SHOWZEROQUANTITIES="
                 . URLCleanParams::insert('_obj__SHOWZEROQUANTITIES', $params['SHOWZEROQUANTITIES'])
                 ."&_obj__HIDEINACTIVEWH="
                 . URLCleanParams::insert('_obj__HIDEINACTIVEWH', $params['HIDEINACTIVEWH'])
                 ."&_obj__HIDEINACTIVEITEM="
                 . URLCleanParams::insert('_obj__HIDEINACTIVEITEM', $params['HIDEINACTIVEITEM'])
                 ."&_obj__HIDEITEMWITHOUTACTIVITY="
                 . URLCleanParams::insert('_obj__HIDEITEMWITHOUTACTIVITY', $params['HIDEITEMWITHOUTACTIVITY'])
                 ."&_obj__SHOWZERO="
                 . URLCleanParams::insert('_obj__SHOWZERO', $params['SHOWZERO'])
                 ."&_obj__ASOFDATE="
                 . URLCleanParams::insert('_obj__ASOFDATE', $params['ASOFDATE']);
        }
        // epp("Params was ");
        // eppp($params);
        $lines['report']["0"]['op']                = $_op;


        $lines['report']["0"]['sess']            = $_sess;
        $lines['report']["0"]['co']                = GetMyCompanyName();
        $lines['report']['0']['asofdate'] = $this->getLabelPrefixForReportHeader(
            FormatDateForDisplay($params['ASOFDATE']),
            $params['type'],
            'IA.AS_OF_DATE : ');
        $lines['report']['0']['dt1'] = $this->getLabelPrefixForReportHeader(
            FormatDateForDisplay($params['dt1']),
            $params['type'],
            'IA.START_DATE : ');
        $lines['report']['0']['dt2'] = $this->getLabelPrefixForReportHeader(
            FormatDateForDisplay($params['dt2']),
            $params['type'],
            'IA.END_DATE : ');
        $lines['report']["0"]['mode']            = $params['mode'];
        $lines['report']["0"]['summarymode']    = $params['SUMMARYMODE'];
        $lines['report']["0"]['sortmode']        = $params['SORTMODE'];
        $lines['report']["0"]['sendersemail']    = $params['SENDERSEMAIL'];
        $lines['report']["0"]['xslformat']        = $params['XSLFORMAT'];
        $lines['report']["0"]['emailtemplate']    = $params['EMAILTEMPLATE'];
        $lines['report']["0"]['sendersphone'] = htmlspecialchars($params['SENDERSPHONE'], ENT_QUOTES);
        $lines['report']["0"]['sendersname']  = htmlspecialchars($params['SENDERSNAME'], ENT_QUOTES);
        $lines['report']["0"]['messagetext']    = $params['MESSAGETEXT'];
        $lines['report']["0"]['marketingtext']    = $params['MARKETINGTEXT'];
        $lines['report']["0"]['location']        = ($params['LOCATION'])? 'IA.LOCATION : ' . $params['LOCATION'][0] : '';
        $lines['report']["0"]['department']        = ($params['DEPARTMENT'])? 'IA.DEPARTMENT : ' . $params['DEPARTMENT'][0] : '';
        $lines['report']["0"]['shdept']            = $params['SHDEPT'];
        $lines['report']["0"]['shloc']            = $params['SHLOC'];

        $lines['report']['0']['ismegl'] = (IsMultiEntityCompany())? 'Y' : 'N';
        $lines['report']['0']['locationcontext'] = (GetContextLocation())?: '';
        $lines['report']['0']['companyid'] = GetMyCompany();

                $lines['report']["0"]['reportdate']     = GetCurrentDate(IADATE_USRFORMAT);
        //              $lines['report']["0"]['reporttime']     = date("g:i A T");
        if(Profile::getUserCacheProperty('USERPREF', 'TIMEFORMAT') == 'HH24:MI:SS') {
                    $lines['report']["0"]['reporttime']     = date("G:i T");
        } else {
            $lines['report']["0"]['reporttime']     = date("g:i A T");
        }

        $terms = $this->GenerateRelabeledTerms();
        foreach ($terms as $key => $val) {
            $lines['report']["0"][$key] = $val;
        }
        if ($params['ops']) {
            if (is_numeric($params['ops'][0])) {
                $the_ops = $params['ops'];
            } else {
                $the_ops = array();
                foreach ($params['ops'] as $op){
                    $the_ops[] = GetOperationId($op);
                }
            }
            $params['joinedops'] = \implode(',', $the_ops);
            $lines['report']["0"]['ops']    = $params['joinedops'];
        }
        // deliverop is used in bulk printing so we know what editor to use
        if ($params['deliverop']) {
            $lines['report']["0"]['deliverop']        = GetOperationId($params['deliverop']);
        } else {
            $lines['report']["0"]['deliverop']        = '';
        }

        $lines['report']["0"]['backhere']= $params['backhere'];
        $lines['report']["0"]['qtyheader']= $params['qtyheader'];

        switch($params['custvend']){

        case 'cust':
            $lines['report']["0"]['custvend']= 'IA.CUSTOMER';
            break;

        case 'vend':
            $lines['report']["0"]['custvend']= 'IA.VENDOR';
            break;

        case 'inv':
            $lines['report']["0"]['custvend']= 'IA.INVENTORY';
            break;

            default:
            $lines['report']["0"]['custvend']= $params['custvend']; // pass thru if inv
            break;

        }
        $lines['report']["0"]['custvendnoi18n']= $params['custvend'];

        $lines['report']["0"]['javascript']= $this->GenerateJavascript($params);
        // optional parameters here.  Try to set them intelligently
        if (isset($params['START_DATE'])) {
            $lines['report']["0"]['date']    = FormatDateForDisplay($params['START_DATE']).' - '.
                                                FormatDateForDisplay($params['END_DATE']);

        }
        if($this->isatlas) {
            $this->DisplayBaseCurrHeader($lines);
        }

        $lines['report']['0']['report_format'] = $this->params['type'];

        //eppp($lines);
        return $lines;
    }


    /**
     * @param array $params
     *
     * @return string
     */
    function GenerateJavascript($params)
    {
        $popupflag = $params['DRILLDOWN_POPUP'] ?? "false";

        $stkitop = GetOperationId("inv/lists/stkitdocument/view");

        return "
			function drilldown(which, rec, ownerloc) {

				if ( !rec ) { return ; }

				var popup = " . $popupflag . ";
				var allowed_ids = Array( " . $params['joinedops']  . ");
				var URL;

				var opid = allowed_ids[which];

				var strkits = rec.split('-');
				if (strkits[0] == 'Build+Kits' || strkits[0] == 'Disassemble+Kits') {
					opid = " . $stkitop . ";
				}

				if( opid ){
					URL = 'editor.phtml?.op=' + opid + '&.do=view' + '&.r=' + escape(rec);
				}
				else{
					URL = '#';
				}

				/*
				    Some forms may contain .op as their hidden fields.
				    if they are not set the .op passed with URL doesn't take effect.
                */
				if (document.f && document.f.elements && document.f.elements['.op']) {
				    var op_code=document.f.elements['.op'];
                    if(op_code){
                        op_code.value = opid;
                    }
				}

				DoDrill(URL, popup, ownerloc);
			}
		";
    }

    /**
     * @param array $lines
     * @param array $morelines
     *
     * @return array
     */
    function InvCommonBody($lines,$morelines)
    {
        if (count($morelines)==0) {
            $lines['report']["0"]['NODATA'][0]= array('NODATA'=>'1');
        } else {
            $lines['report']["0"]['ITEMS']    = $morelines;
        }
        return $lines;
    }


    /**
     * @param array $lines
     * @param array $morelines
     *
     * @return array
     */
    function InvCommonTotals($lines,$morelines)
    {
        $lines['report']["0"]['TOTALS']    = $morelines;
        return $lines;
    }


    /**
     * @return bool
     */
    function ValidateReport()
    {
        // override this function if you don't need all the checks for your report
        if(!$this->ParamTweaks()) {
            return false;
        }

        return true;
    }


    /**
     * @return bool
     */
    function ParamTweaks()
    {
        global $gErr;

        // epp("Into INVReporter ParamTweaks");
        // this is more validation, defaulting, and making the strings html safe.  Is there any reason why setting them back to the params is going to be a problem?
        // if params gets reused to reload the page, then it might be an issue, in which case we should put all these under a "safe" heading of the params array
        // i.e. this->params['safe'] = $newparamarray

        $params = $this->params;

        $fromterritory = explode('--', $params['FROMTERRITORYID']);
        $fromterritory = $fromterritory[0];
        $p['FROMTERRITORYID'] = $fromterritory ? isl_htmlspecialchars($fromterritory) : VARCHAR2_MIN;

        $toterritory = explode('--', $params['TOTERRITORYID']);
        $toterritory = $toterritory[0];
        $p['TOTERRITORYID'] = $toterritory ? isl_htmlspecialchars($toterritory) : VARCHAR2_MAX;

        $fromvendor                = explode('--', $params['FROMVENDORID']);
        $fromvendorid            = $fromvendor[0];
        $p['FROMVENDORID']        = $fromvendorid ? isl_htmlspecialchars($fromvendorid) : VARCHAR2_MIN;
        $tovendor                = explode('--', $params['TOVENDORID']);
        $tovendorid                = $tovendor[0];
        $p['TOVENDORID']        = $tovendorid ? isl_htmlspecialchars($tovendorid) : VARCHAR2_MAX;
        $p['FROMVALUE']            = $params['FROMVALUE'] ?: -100000000000;
        $p['TOVALUE']            = $params['TOVALUE'] ?: 100000000000 ; // one hundred billion should do it.

        $fromcust                = explode('--', $params['FROMCUSTOMERID']);
        $fromcustid                = $fromcust[0];
        $p['FROMCUSTOMERID']    = $fromcustid ? isl_htmlspecialchars($fromcustid) : VARCHAR2_MIN;
        $tocust                    = explode('--', $params['TOCUSTOMERID']);
        $tocustid                = $tocust[0];
        $p['TOCUSTOMERID']        = $tocustid ? isl_htmlspecialchars($tocustid) : VARCHAR2_MAX;

        $p['FROMWAREHOUSEID']    = ($params['FROMWAREHOUSEID']!='') ? isl_htmlspecialchars($params['FROMWAREHOUSEID']) : VARCHAR2_MIN;
        $p['TOWAREHOUSEID']        = ($params['TOWAREHOUSEID']!='') ? isl_htmlspecialchars($params['TOWAREHOUSEID']) : VARCHAR2_MAX;
        $p['FROMDOCID']    = ($params['FROMDOCID']!='') ? isl_htmlspecialchars($params['FROMDOCID']) : VARCHAR2_MIN;
        $p['TODOCID']        = ($params['TODOCID']!='') ? isl_htmlspecialchars($params['TODOCID']) : VARCHAR2_MAX;
        $fromitem                = explode('--', $params['FROMITEMID']);
        $fromitemid                = $fromitem[0];
        $p['FROMITEMID']        = $fromitemid ? isl_trim($fromitemid) : VARCHAR2_MIN;
        $toitem                    = explode('--', $params['TOITEMID']);
        $toitemid                = $toitem[0];
        $p['TOITEMID']            = $toitemid ? isl_trim($toitemid) : VARCHAR2_MAX;
        $p['ITEMVALUES']                = $params['ITEMVALUES'] ? isl_trim(isl_htmlspecialchars($params['ITEMVALUES'])) : '%';

        $p['FROMUPC']            = $params['FROMUPC'] ? isl_trim(isl_htmlspecialchars($params['FROMUPC'])) : VARCHAR2_MIN;
        $p['TOUPC']            = $params['TOUPC'] ? isl_trim(isl_htmlspecialchars($params['TOUPC'])) : VARCHAR2_MAX;
        $p['UPCVALUES']                = $params['UPCVALUES'] ? isl_trim(isl_htmlspecialchars($params['UPCVALUES'])) : '%';

        $p['PRODLINEID']        = $params['PRODLINEID'] ? isl_htmlspecialchars($params['PRODLINEID']) : '%';
        $p['ITEM']                = $params['ITEM'] ? isl_trim(isl_htmlspecialchars($params['ITEM'])) : '%';
        $p['CUSTOMER']            = $params['CUSTOMER'] ? isl_trim(isl_htmlspecialchars($params['CUSTOMER'])) : '%';
        $p['VENDOR']            = $params['VENDOR'] ? isl_trim(isl_htmlspecialchars($params['VENDOR'])) : '%';
        $p['PRCLSTNAME']        = $params['PRCLSTNAME'] ? isl_trim($params['PRCLSTNAME']) : '%';
        $p['type']                = isl_trim($params['type']);
        $p['trans']                = ($params['DOCTYPE'] == 'All' || $params['DOCTYPE'] == '') ? '%' : $params['DOCTYPE'];

        $p['SORTMODE']                = $params['SORTMODE'] ? isl_trim(isl_htmlspecialchars($params['SORTMODE'])) : 'Default';
        $p['VALUEMODE']                = $params['VALUEMODE'] ? isl_trim(isl_htmlspecialchars($params['VALUEMODE'])) : 'Default';
        $p['DLAMODE']                = $params['DLAMODE'] ? isl_trim(isl_htmlspecialchars($params['DLAMODE'])) : 'Date Last Sold/Rcvd';
        $p['ORDERSTATE']            = $params['ORDERSTATE'] ? isl_trim(isl_htmlspecialchars($params['ORDERSTATE'])) : 'All';
        $p['SUMMARYMODE']            = $params['SUMMARYMODE'] ? isl_trim(isl_htmlspecialchars($params['SUMMARYMODE'])) : 'Default';
        $p['SHOWZEROQUANTITIES']    = $params['SHOWZEROQUANTITIES'] ? isl_trim(isl_htmlspecialchars($params['SHOWZEROQUANTITIES'])) : 'true';
        $p['HIDEINACTIVEITEM']    = $params['HIDEINACTIVEITEM'] ? isl_trim(isl_htmlspecialchars($params['HIDEINACTIVEITEM'])) : 'true';
        $p['HIDEINACTIVEWH']    = $params['HIDEINACTIVEWH'] ? isl_trim(isl_htmlspecialchars($params['HIDEINACTIVEWH'])) : 'true';
        $p['SHOWNEGVALUES']    = $params['SHOWNEGVALUES'] ?: 'false';
        $p['SHOWVALUEONLY']    = $params['SHOWVALUEONLY'] ?: 'false';
        $p['SHOWQTYWITHVALUE']    = $params['SHOWQTYWITHVALUE'] ?: 'false';
        $p['SHOWLOCALWAREHOUSES'] = $params['SHOWLOCALWAREHOUSES'] ?: 'false';
        $p['HIDEITEMWITHOUTACTIVITY']    = $params['HIDEITEMWITHOUTACTIVITY'] ? isl_trim(isl_htmlspecialchars($params['HIDEITEMWITHOUTACTIVITY'])) : 'true';
        $p['SHOWZERO']    = $params['SHOWZERO'] ? isl_trim(isl_htmlspecialchars($params['SHOWZERO'])) : 'true';
        $p['WITH_ACTIVITY']    = $params['WITH_ACTIVITY'] ? isl_trim(isl_htmlspecialchars($params['WITH_ACTIVITY'])) : 'true';
        $p['WITH_NO_ACTIVITY']    = $params['WITH_NO_ACTIVITY'] ? isl_trim(isl_htmlspecialchars($params['WITH_NO_ACTIVITY'])) : 'true';

        $p['REPORTGROUPINGS']    = $params['REPORTGROUPINGS'] ? isl_trim(isl_htmlspecialchars($params['REPORTGROUPINGS'])) : 'Default';
        $p['SHOWTHE']            = $params['SHOWTHE'] ? isl_trim(isl_htmlspecialchars($params['SHOWTHE'])) : 'Default';

        $p['DRILLDOWN_POPUP']        = $params['drilldown_popup'] ?: 'false';
        $docclass                = isl_trim(isl_htmlspecialchars($params['DOCCLASS']));
        $p['DOCCLASS']            = ($docclass == 'All' ? '%' : $docclass);
        $uicategory                = isl_trim(isl_htmlspecialchars($params['UICATEGORY']));
        $p['UICATEGORY']        = ($uicategory == 'All' ? '%' : $uicategory);
        $p['DEPARTMENT']        = $params['DEPARTMENT'];
        $p['LOCATION']            = $params['LOCATION'];
        $p['SHDEPT']            = $params['SHDEPT'];
        $p['SHLOC']                = $params['SHLOC'];
        $p['CUSTOMERTYPEID'] = $params['CUSTOMERTYPEID']
            ? isl_htmlspecialchars($params['CUSTOMERTYPEID'])
            : '';
        $p['SORTINGPREFERENCE']    = $params['SORTINGPREFERENCE'];
        $p['CUSTOMERID'] = $params['CUSTOMERID']
            ? isl_htmlspecialchars($params['CUSTOMERID'])
            : '';


        // dt1 and dt2 are dates values assigned with start_date and end_date

        $p['dt1'] = $this->startdate;
        $p['dt2'] = $this->enddate;
        $p['ASOFDATE'] = $params['ASOFDATE'];

        if (HasErrors()) {
            if($gErr->ErrorCount) {
                return false;
            }
        }

        $p['ops']             = $params['ops'];  // pass these thru untweaked for now
        $p['deliverop']     = $params['deliverop'];  // pass these thru untweaked for now
        $p['mode']             = $params['mode']; // pass thru
        $p['custvend']         = $params['custvend']; // pass thru
        $p['javascript']     = $params['javascript']; // pass thru

        $p['SENDERSEMAIL'] = $params['SENDERSEMAIL'];
        $p['XSLFORMAT'] = $params['XSLFORMAT'];
        $p['EMAILTEMPLATE'] = $params['EMAILTEMPLATE'];
        $p['SENDERSPHONE'] = $params['SENDERSPHONE'];
        $p['SENDERSNAME'] = $params['SENDERSNAME'];
        $p['MARKETINGTEXT'] = $params['MARKETINGTEXT'];
        $p['MESSAGETEXT'] = $params['MESSAGETEXT'];

        // remember our tweaked values
        $params['safe'] = $p;
        $this->params = $params;

        return true;
    }


    /**
     * @param string $item
     * @param string $whse
     * @param string $dt1
     * @param string $dt2
     * @param string $ownerloc
     * @param string $reporton
     *
     * @return string
     */
    function BuildItemActivityURL($item, $whse = '', $dt1 = '', $dt2 = '', $ownerloc='', $reporton = '')
    {

        $op = GetOperationId("inv/reports/itemactivity");

        $item = urlencode(addslashes($item));
        $whse = urlencode($whse);

        if ( $dt1 == '' && $dt2 = '' ) {
            $dt1 = urlencode($this->startdate);
            $dt2 = urlencode($this->enddate);
        }
        if($reporton == 'UPC') {
            $itemUPCstr = "&FROMUPC=$item&amp;TOUPC=$item&amp;REPORTON=$reporton";
        }else{
            $itemUPCstr = "&FROMITEMID=$item&amp;TOITEMID=$item";
        }
        $url = "reporteditor.phtml?.type=_html&amp;.op=$op".
                "&amp;FROMWAREHOUSEID=$whse&amp;TOWAREHOUSEID=$whse".
                "&amp;START_DATE=$dt1&amp;END_DATE=$dt2&amp;.drillfilter=1".
                "&amp;HIDEINACTIVEITEM=false&amp;HIDEINACTIVEWH=false&amp;SHOWZEROQUANTITIES=false&amp;HIDEITEMWITHOUTACTIVITY=false".
                $itemUPCstr;
        return "javascript:DoDrill('$url',true, '$ownerloc');";
    }

    /**
     * @param string    $itemid
     * @param string    $value
     *
     * @return float|string
     */
    function roundUnitCost($itemid, $value)
    {
        global $kINVid, $kSOid, $kPOid;
        
        $mod = &Request::$r->_mod;
        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        if (!array_key_exists($mod, $modArray)) {
            unset($mod);
        }
        //For memorized reports $mod is null here.So we are getting mod value from params.
        if(!isset($mod) or !$mod) {
            $module = array_flip($modArray);
            $mod = $module[$this->params['modulekey']];
        }
        $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');

        if ($mod == 'inv') {
            $this->itemprecision[$mod] = ItemManager::AVERAGE_COST_DECIMALS;
        } else if ($this->itemprecision[$mod] == '') {
            GetModulePreferences($modArray[$mod], $prefs);
            $this->itemprecision[$mod] = ($prefs['ITEMPRECISION']) ?: 2;

            $field = $precisionFields[$mod];
            $results = QueryResult(array("select itemid, NUMDEC_SALE, NUMDEC_PUR, NUMDEC_STD from icitem where cny# = :1 and $field != :2 ", GetMyCompany(), $this->itemprecision[$mod]));
            foreach ($results as $res) {
                $this->itemprecision[$res['ITEMID']] = $res[$field];
            }
        } 

        if (($this->itemprecision[$itemid] ?? '') != '') {
            $degree = $this->itemprecision[$itemid];
        } else {
            $degree = $this->itemprecision[$mod] ?? 0;
        }
        $roundedValue    = round($value, $degree);
        // a number like 0.000001 comes out as 1.0E-6.
        // iround treats the number as a printable number and not a scientific value.
        // however, it may have other ramifications we don't want to run into, so I
        // only use iround() here if the result was scientific notation.  Roger.
        if (strpos($roundedValue, 'E') !== false) {
            $roundedValue    = iround($value, $degree);
        }


        if ($degree == 0) {
            return $roundedValue;
        }

        $fraction    = isl_strstr((string)$roundedValue, '.');  // force to string or you get "PHP8.1Error: isl_strstr first argument must be string but given: double"
        $suffixStr    = '';

        if (isl_strlen($fraction) <= $degree) {
            $diff = (isl_strlen($fraction) > 0) ? $degree - isl_strlen($fraction) + 1 : $degree - isl_strlen($fraction);

            for($k=0; $k<$diff; $k++  ) {
                $suffixStr .= '0';
            }

            if ( isl_strlen($fraction) > 0 ) {
                $roundedValue .= $suffixStr;
            } else {
                $roundedValue .= '.'.$suffixStr;
            }
        }

        return $roundedValue;
    }

    //


    /**
     * @param array     $params
     * @param string    $tableName
     * @param string    $locationField
     *
     * @return bool|string
     */
    function _getLocationClause($params, $tableName='docentry', $locationField = 'locationkey')
    {

        $filterlocation = "";

        $cny = GetMyCompany();

        if ($params['LOCATION'] != '' && count($params['LOCATION'])) {

            global $_userid;
            $locs = array();

            foreach ($params['LOCATION'] as $loc) {
                list($loc_no) = explode("--", $loc);
                GetRecordNo($_userid, 'location', $loc_no, $locrec);

                if( !isset($locrec) || $locrec =='' ) {
                    global $gErr;
                    $gErr->addIAError(
                        'INV-0701', __FILE__." : ".__LINE__,
                        "Location ID '$loc_no' is invalid.",
                        ['LOC_NO' => $loc_no]
                    );
                    return false;
                }

                $locs[] = $locrec;

            }

            // Use the FilterLocations control to get the users selection to get the location list to filter by
            if ($params['FILTERTRANSACTIONS'] == 'CHILDREN') {
                $filterlocation = " and $tableName.$locationField in
					(SELECT  distinct(RECORD#)
						FROM LOCATIONMST
						WHERE  CNY#=$cny start with " .
                        PrepINClauseStmt("", $locs, " PARENTKEY ") .
                        " and CNY#=$cny connect by prior RECORD#=PARENTKEY and CNY#=$cny) ";
            }
            else if($params['FILTERTRANSACTIONS'] == 'SELF') {
                $filterlocation = PrepINClauseStmt("", $locs, " and $tableName.$locationField ");
            }
            else { // All locations
                $filterlocation = " and $tableName.$locationField in
					(SELECT  distinct(RECORD#)
						FROM LOCATIONMST
						WHERE  CNY#=$cny start with " .
                        PrepINClauseStmt("", $locs, " RECORD# ") .
                        " and CNY#=$cny connect by prior RECORD#=PARENTKEY and CNY#=$cny) ";
            }

        }

        return $filterlocation;

    }


    /**
     * @param array     $params
     * @param string    $tableName
     *
     * @return bool|string
     */
    function _getDeptClause($params, $tableName='docentry')
    {

        $filterdept = "";

        $cny = GetMyCompany();

        if ($params['DEPARTMENT'] != '' && count($params['DEPARTMENT'])) {

            global $_userid;
            $depts = array();

            foreach ($params['DEPARTMENT'] as $dept) {
                list($dept_no) = explode("--", $dept);
                GetRecordNo($_userid, 'department', $dept_no, $deptrec);

                if( !isset($deptrec) || $deptrec =='' ) {
                    global $gErr;
                    $gErr->addIAError(
                        'INV-0702', __FILE__." : ".__LINE__,
                        "Department ID '$dept_no' is invalid.",
                        ['DEPT_NO' => $dept_no]
                    );
                    return false;
                }

                $depts[] = $deptrec;

            }

            // All locations
            $filterdept = " and $tableName.deptkey in 
				(SELECT  distinct(RECORD#)
					FROM DEPARTMENTMST
					WHERE  CNY#=$cny start with " .
                    PrepINClauseStmt("", $depts, " RECORD# ") .
                    " and CNY#=$cny connect by prior RECORD#=PARENT# and CNY#=$cny)";
        }

        return $filterdept;

    }

    /**
     * @param string        $filterItemorUPC
     * @param string        $itemupcargs
     * @param string        $operator
     * @param string        $tablealias
     * @param string        $field
     * @param array|string  $values
     * @param string        $argPosition
     */

    function GetFilterArgs(&$filterItemorUPC, &$itemupcargs, $operator='=', $tablealias='icitem', $field='itemid', $values=array(), $argPosition='')
    {

        $itemupcargs = isl_trim(isl_htmlspecialchars($values));
        $field = $tablealias.".".$field;
        $arg = ($argPosition != '') ? ":".$argPosition : "?" ;

        switch ($operator) {
        case 'Equals':
            $filterItemorUPC = " $field = $arg ";
            break;

        case 'Not equal to':
            $filterItemorUPC = " $field != $arg ";
            break;

        case 'Less than':
            $filterItemorUPC = " $field < $arg ";
            break;

        case 'Greater than':
            $filterItemorUPC = " $field > $arg ";
            break;

        case 'Less than or equal':
            $filterItemorUPC = " $field <= $arg ";
            break;

        case 'Greater than or equal':
            $filterItemorUPC = " $field >= $arg ";
            break;

        case 'Contains':

            $values = isl_strtoupper($values);
            $itemupcargs = "%".isl_trim(isl_htmlspecialchars($values))."%";
            $filterItemorUPC = " UPPER($field) LIKE $arg ";
            break;

        case 'Does not contain':

            $values = isl_strtoupper($values);
            $itemupcargs = "%".isl_trim(isl_htmlspecialchars($values))."%";
            $filterItemorUPC = " UPPER($field) NOT LIKE $arg ";
            break;

        case 'Starts with':

            $itemupcargs = isl_trim(isl_htmlspecialchars($values))."%";
            $filterItemorUPC = " $field LIKE $arg ";
            break;

        case 'Ends with':

            $itemupcargs = "%".isl_trim(isl_htmlspecialchars($values));
            $filterItemorUPC = " $field LIKE $arg ";
            break;

        case 'Includes':
        case 'Excludes':
            $opr = ($operator == 'Includes') ? ' IN ' : ' NOT IN ';

            $values = explode(',', $values);
            foreach( $values  as $key => $val){
                $val = isl_trim($val);
                if($val == '') {
                    unset($values[$key]);
                    continue;
                }
                $values[$key] = str_pad($val, isl_strlen($val)+2, "'", STR_PAD_BOTH);
            }

            $itemupcargs = "(". join(" , ", $values). ")";

            $filterItemorUPC = " $field $opr $itemupcargs ";
            $itemupcargs='';
            break;
        }
    }

    /**
     * @param string $adate
     *
     * @return int
     */
    function DateToDays($adate)
    {
        // this func will convert a given date in mm/dd/yyyy to the number of days it is in the past
        // first go to unix time stamp
        if( ! isset($adate) || $adate == '' ) {
            return MAX_NUMBER_OF_DAYS;
        }

        static $cache = [];

        if ( ! isset($cache[$adate])) {
            $then = strtotime($adate);
            $now  = time();
            $days = intval(($now - $then) / (60 * 60 * 24));
            $cache[$adate] = $days;
        }
        return $cache[$adate];
    }

    /**
     * function to prepare Product Line Map QRY to filter the items
     * @param int $ProdLineId
     * @param string $tableAlias
     */
    function prepareProductLineMapQry($ProdLineId, $tableAlias)
    {
        $prodLineQuerySpec = array(
            'QUERY' => "select productlineid from icprodline where cny# = ?
                          start with cny# = ? and productlineid= '{$ProdLineId}'
                          connect by cny# = ? and parentlineid = PRIOR productlineid",
            'ARGTYPES' => array('integer', 'integer', 'integer')
        );
        $prodLineQueryArgs = array(GetMyCompany(), GetMyCompany(), GetMyCompany());
        $prodLineQueryResults = $this->_QM->DoCustomQuery($prodLineQuerySpec, $prodLineQueryArgs);

        $prodLines = INTACCTarray_project($prodLineQueryResults, 0);
        $count = count($prodLines);
        if ($count == 0) {
            // should not happen, but just in case ...
            $this->prodlineChildMapQry = '';
        } else {
            $this->prodlineChildMapQry = PrepINClauseStmt('', $prodLines, $tableAlias . '.productlinekey', false, 'dummy', true);
            $this->prodlineChildMapQry .= ' and ';
        }

    }

    /**
     * Called from itemactivity.rpt and invstatus.rpt to see if we RESERVE and ALLOCATION inventory totals
     *
     * @return bool
     */
    public static function hasReserveAndAllocateTotals()
    {
        //Determine if there are both RESERVE and ALLOCATION inventory totals
        $totalManager = Globals::$g->gManagerFactory->getManager('invtotal');
        $filter = array(
            'selects' => array('NAME'),
            'filters' => array(
                array(
                    array('NAME', 'IN', ['ALLOCATED', 'RESERVED']),
                )
            ),
        );
        $rows = $totalManager->GetList($filter);
        $totals = [];
        foreach($rows as $row){
            $totals[$row['NAME']] = true;
        }
        $retVal = false;
        if (isset($totals['ALLOCATED']) && isset($totals['RESERVED'])) {
            $retVal = true;
        }
        return $retVal;
    }

}

