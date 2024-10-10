<?
import('InventoryReporter');
define('DEFAULT_INVPRECISION', 2);

/**
 * Class SerialTrackingReport
 */
class SerialTrackingReport extends InventoryReporter
{
    /** @var array $_serialactivity */
    var $_serialactivity = array();

    /** @var string $prodlineid */
    protected $prodlineid = '';

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                'report' => 'serialtracking',
                'ops'    => array(
                                            'inv/lists/item/view',
                                            'inv/lists/warehouse/view',
                                            'inv/lists/invdocument/view',
                                            'so/lists/sodocument/view',
                                            'po/lists/podocument/view',
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
        global $_userid;

        list( , $cny) = explode('@', $_userid);

        $this->ValidateReport();

        // reload after the validate report
        $params = $this->params['safe'];

        $fromwarehouseid        = $params['FROMWAREHOUSEID'];
        $towarehouseid            = $params['TOWAREHOUSEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];

        $ReportOn                = $this->params['REPORTON'];
        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];
        $WhseOperator            = $this->params['WHSEOPERATOR'];
        $whseValues                = $this->params['WHSEVALUES'];

        //		$varfromserial =Request::$r->FROMSERIAL;
        //		if(isset($varfromserial) && $varfromserial!=''){
        //			$this->params['FROMSERIAL']= $varfromserial;
        //		}
        $fromserial     = $this->params['FROMSERIAL'];

        //		$vartoserial =Request::$r->TOSERIAL;
        //		if(isset($vartoserial) && $vartoserial!=''){
        //			$this->params['FROMSERIAL']=$vartoserial;
        //		}
        $toserial = $this->params['TOSERIAL'];
        $this->prodlineid			= $params['PRODLINEID'];

        /*
         * Prepare the Product Line QRY string to use it to filter items by product line info
         */
        if ($this->prodlineid != '%') {
            $this->prepareProductLineMapQry($this->prodlineid,'icitem');
        }

        $fromserial        = explode('--', $fromserial);
        $fromserial        = $fromserial[0];
        $fromserial        = $fromserial ? isl_trim(isl_htmlspecialchars($fromserial)) : VARCHAR2_MIN;
        $toserial        = explode('--', $toserial);
        $toserial        = $toserial[0];
        $toserial        = $toserial ? isl_trim(isl_htmlspecialchars($toserial)) : VARCHAR2_MAX;

        $ictotalsLocationFilter = $this->_getLocationClause($params, 'docentry');
        $ictotalsDeptFilter = $this->_getDeptClause($params, 'docentry');

        $args = array('sql',$cny,$fromserial,$toserial,'','','','');

        if ( $ReportOn == 'ITEMID') {
            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues, 4);
                // itemupcargs will be blank in case of include/excludes operator
                if( $itemupcargs !='') {
                    //array_push($args, $itemupcargs);
                    $args[4]=$itemupcargs;
                }
            } else {
                $filterItemorUPC = " icitem.itemid  >= :4 and icitem.itemid  <= :5 ";
                //array_push($args, $fromitemid, $toitemid);
                $args[4]=$fromitemid;
                $args[5]=$toitemid;
            }
        }else {

            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues, 4);
                // itemupcargs will be blank in case of include/excludes operator
                if( $itemupcargs !='') {
                    //array_push($args, $itemupcargs);
                    $args[4]=$itemupcargs;
                }
            } else {
                $filterItemorUPC = " icitem.upc  >= :4 and icitem.upc  <= :5";
                //array_push($args, $fromupc, $toupc);
                $args[4]=$fromupc;
                $args[5]=$toupc;
            }
        }
        if ( $fromwarehouseid == VARCHAR2_MIN && $towarehouseid == VARCHAR2_MAX && $whseValues != '') {
            $this->GetFilterArgs($filterWhse, $whseargs, $WhseOperator, 'docentrycost', 'whsekey', $whseValues, 6);
            $args[6]=$whseargs;
        }else{
            $filterWhse = "docentrycost.whsekey between :6 and :7";
            $args[6]=$fromwarehouseid;
            $args[7]=$towarehouseid;
        }

        // 'Zone' should be here but causes the text to go off the end of the page :-(  So for now.....
        if (BinManager::areAdvanedBinsOn()) {
            $zoneSelect = ""; // "whsezone.zoneid, ";
            $zoneFrom   = ""; // "iczone whsezone,"
            $zoneWhere  = ""; // "docentrycost.cny#=whsezone.cny#(+) and whsebin.zonekey=whsezone.record#(+) and"
            $serialqry = "select icitem.name, docentrycost.serialno,dochdr.docid,docentry.whencreated datein,docentrycost.lotno,docentrycost.whsekey,
                    $zoneSelect whseaisle.aisleid aislekey,whserow.rowkey,whsebin.binid binkey,
                    docentrycost.itemkey, decode(docentrycost.in_out, 'I', 1, -1) * docentrycost.quantity as quantity, docentrycost.expirationdate, dochdr.melocationkey ownerloc, dr.sale_pur_trans as transactionmodule, icitem.upc 
                from 
                    docentrycost,docentry,dochdrmst dochdr, icaisle whseaisle, icrow whserow, icbin whsebin, $zoneFrom icitem, docparmst dr
                where
                   docentrycost.cny#= :1 and
                   docentry.cny# = :1 and
                   docentrycost.docentrykey=docentry.record# and 
                   dochdr.cny# = :1 and 
                   dochdr.state not in ('I','S','A', 'X', 'R') and
                   docentry.dochdrkey=dochdr.record#  and
                   docentrycost.cny#=whsebin.cny#(+) and
                   docentrycost.cny#=whseaisle.cny#(+) and
                   docentrycost.cny#=whserow.cny#(+) and
                   $zoneWhere
                   docentrycost.binkey=whsebin.record#(+) and 
                   whsebin.aislekey=whseaisle.record#(+) and 
                   whsebin.rowkey=whserow.record#(+) and 
                   docentrycost.serialno is not null and
                   docentrycost.affects_inventory in ('V', 'QV') and
                   docentrycost.adjdocentrycostkey is null and
                   icitem.cny# = :1 and
                   docentrycost.itemkey=icitem.itemid and 
                   dochdr.docparkey=dr.record# and
                   dr.cny# = :1 and              
                   docentrycost.serialno between :2 and :3 and 
                   {$this->prodlineChildMapQry}
                   $filterItemorUPC  $ictotalsLocationFilter $ictotalsDeptFilter 
                   and $filterWhse order by docentrycost.serialno,docentry.whencreated, dochdr.record#
                    ";
        } else {
            $zoneSelect = ""; // "'' as zoneid, ";
            $serialqry = "select icitem.name, docentrycost.serialno,dochdr.docid,docentry.whencreated datein,docentrycost.lotno,docentrycost.whsekey,
                $zoneSelect whseaisle.aisleid aislekey,whserow.rowkey,whsebin.binid binkey,
                docentrycost.itemkey, decode(docentrycost.in_out, 'I', 1, -1) * docentrycost.quantity as quantity, docentrycost.expirationdate, dochdr.melocationkey ownerloc, dr.sale_pur_trans as transactionmodule, icitem.upc 
                from 
                    docentrycost,docentry,dochdrmst dochdr, icaisle whseaisle, icrow whserow, icbin whsebin, icitem, docparmst dr
                where
                   docentrycost.cny#= :1 and
                   docentry.cny# = :1 and
                   docentrycost.docentrykey=docentry.record# and 
                   dochdr.cny# = :1 and 
                   dochdr.state not in ('I','S','A', 'X', 'R') and
                   docentry.dochdrkey=dochdr.record#  and
                   docentrycost.cny#=whseaisle.cny#(+) and
                   docentrycost.aislekey=whseaisle.record#(+) and
                   docentrycost.cny#=whserow.cny#(+) and
                   docentrycost.rowkey=whserow.record#(+) and
                   docentrycost.cny#=whsebin.cny#(+) and
                   docentrycost.binkey=whsebin.record#(+) and 
                   docentrycost.serialno is not null and
                   docentrycost.affects_inventory in ('V', 'QV') and
                   docentrycost.adjdocentrycostkey is null and
                   icitem.cny# = :1 and
                   docentrycost.itemkey=icitem.itemid and 
                   dochdr.docparkey=dr.record# and
                   dr.cny# = :1 and              
                   docentrycost.serialno between :2 and :3 and 
                   {$this->prodlineChildMapQry}
                   $filterItemorUPC  $ictotalsLocationFilter $ictotalsDeptFilter 
                   and $filterWhse order by docentrycost.serialno,docentry.whencreated, dochdr.record# ";
        }
        $args[0] = $serialqry;
        $this->_serialactivity = QueryResult($args);

        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $lineMap = $this->_serialactivity;
        $serialMap = array();
        $itemMap = array();
        foreach ( $lineMap as $lineval) {
            $serialNo = $lineval['SERIALNO'];
            $itemID = $lineval['ITEMKEY'];
            $serialMap[$serialNo]['SERIALNO'] = $serialNo;
            $lineval['ITEMKEY'] = $this->params['REPORTON'] == 'ITEMID' ? $itemID : $lineval['UPC'];
            $lineval['ITEMHREF'] = "javascript:drilldown(0,'$itemID', '$lineval[OWNERLOC]');";

            $Docid = urlencode(addslashes($lineval['DOCID']));

            $lineval['DATEIN'] = FormatDateForDisplay($lineval['DATEIN']);
            $lineval['EXPIRATIONDATE'] = FormatDateForDisplay($lineval['EXPIRATIONDATE']);

            if($lineval['TRANSACTIONMODULE']=='I') {
                $lineval['DOCHREF'] = "javascript:drilldown(2,'$Docid', '$lineval[OWNERLOC]');";
            }elseif($lineval['TRANSACTIONMODULE']=='S') {
                $lineval['DOCHREF'] = "javascript:drilldown(3,'$Docid', '$lineval[OWNERLOC]');";
            }elseif($lineval['TRANSACTIONMODULE']=='P') {
                $lineval['DOCHREF'] = "javascript:drilldown(4,'$Docid', '$lineval[OWNERLOC]');";
            }
            $itemMap[$serialNo][$itemID]['ITEM'] = $itemID;
            $itemMap[$serialNo][$itemID]['ITEMHREF'] = "javascript:drilldown(0,'$itemID', '$lineval[OWNERLOC]');";
            $itemMap[$serialNo][$itemID]['TOTITEMQUANTITY'] = ibcadd($lineval['QUANTITY'], $itemMap[$serialNo][$itemID]['TOTITEMQUANTITY'] , 2, true);
            $itemMap[$serialNo][$itemID]['TRANS'][] = $lineval;

        }
        foreach ($itemMap as $serialKey => $serial) {
            foreach ( $serial as $item) {
                $serialItems = $item;
                $serialMap[$serialKey]['SERIALITEMS'][] = $serialItems;
            }
        }
        foreach ( $serialMap as $serialKey => $serial) {
            $finalMap['SERIAL'][] = $serialMap[$serialKey];
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $finalMap = $finalMap ?? [];
        if ( count($finalMap) == 0) {
            $finalMap['NODATA'][0] = array('NODATA' => '1');
        }
        $lines = $this->InvCommonHeader();
        $lines = $this->InvCommonBody($lines, $finalMap);
        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];
        return $lines;
    }

    /**
     * @param array $lines
     *
     * @return array
     */
    function DrawHeader($lines)
    {
        $dict = Dictionary::getInstance();
        $lines['report']["0"]['Aisle'] = $dict->GetRenamedText('Aisle')  ;
        $lines['report']["0"]['Bin'] = $dict->GetRenamedText('Bin')  ;
        $lines['report']["0"]['Row'] = $dict->GetRenamedText('Row')  ;
        $lines['report']["0"]['Item'] = $dict->GetRenamedText('Item')  ;
        $lines['report']["0"]['Warehouse'] = $dict->GetRenamedText('Warehouse')  ;
        return $lines;
    }

}
