<?
import('InventoryReporter');

/**
 * Class PriceListReporter
 */
class PriceListReporter extends InventoryReporter
{

    /** @var string $_baseCurrency */
    var $_baseCurrency;

    /**
     * @var array $_prclst
     */
    var $_prclst = array();

    /**
     * @var array $_prodlines
     */
    var $_prodlines = array();


    /**
     * @param array $_params
     */
    function __construct($_params)
    {
        parent::__construct($_params);

        $mod = Request::$r->_mod;
        $this->_ismcpEnabled = IsMCPEnabled($mod);
        if($this->_ismcpEnabled) {
            $this->_baseCurrency = GetBaseCurrency();
        }
    }

    /**
     * @return bool
     */
    function DoQuery() 
    {
        $this->ValidateReport();
        $params = $this->params['safe'];
        $prclstname                = $params['PRCLSTNAME'];
        $prodlineid                = $params['PRODLINEID'];
        $fromitemid                = $params['FROMITEMID'];
        $toitemid                = $params['TOITEMID'];

        $fromupc                = $params['FROMUPC'];
        $toupc                    = $params['TOUPC'];
        $ReportOn                = $this->params['REPORTON'];
        $ItemOperator            = $this->params['ITEMOPERATOR'];
        $itemValues                = $this->params['ITEMVALUES'];
        $UPCOperator            = $this->params['UPCOPERATOR'];
        $upcValues                = $this->params['UPCVALUES'];

        $mod = $this->params['mod'];

        $location_filter = '';        
        if ($params['LOCATION'] != '' && count($params['LOCATION'])) {
            global $_userid;
            $locs = array();
            foreach ($params['LOCATION'] as $loc) {
                list($loc_no) = explode("--", $loc);
                GetRecordNo($_userid, 'location', $loc_no, $locrec);
                $locs[] = $locrec;
            }
            // Use the FilterLocations control to get the users selection to get the location list to filter by
            if ($params['FILTERTRANSACTIONS'] == 'CHILDREN') {
                $location_filter .= 
                " and (pr.locationkey is null or pr.locationkey in (
							SELECT  distinct(RECORD#) 
							FROM LOCATIONMST
							WHERE  CNY#=:1 start with PARENTKEY in (". implode(', ', $locs) .") and CNY#=:1 
							connect by prior RECORD#=PARENTKEY and CNY#=:1) 
						) ";
            }
            else if($params['FILTERTRANSACTIONS'] == 'SELF') {
                $location_filter =" and pr.locationkey is null or pr.locationkey in (".implode(', ', $locs).") and ";
            }
            else { // All locations
                $location_filter .=
                " and pr.locationkey is null or pr.locationkey in ( 
							SELECT  distinct(RECORD#) 
							FROM LOCATIONMST
							WHERE  CNY#=:1 start with RECORD# in (". implode(', ', $locs) .") and CNY#=:1 
							connect by prior RECORD#=PARENTKEY and CNY#=:1 
						) ";
            }
        }

        $department_filter = "";
        if ( $params['DEPARTMENT'] != '' && count($params['DEPARTMENT']) ) {
            foreach($params['DEPARTMENT'] as $dept) {
                list($deptid) = explode("--", $dept);
                global $_userid;
                GetRecordNo($_userid, 'department', $deptid, $deptrec);
                $deptrecs[] = $deptrec;
            }
            /** @noinspection PhpUndefinedVariableInspection */
            $department_filter =
            " and pr.deptkey in (
						SELECT  distinct(RECORD#) FROM DEPARTMENTMST
						WHERE CNY#=:1
						start with RECORD# in (".join(', ', $deptrecs).") and CNY# = :1
						connect by prior RECORD# = PARENT# and CNY# = :1
					) ";
        }
        
        $salepur_filter='';
        if($mod == 'so' ) {
            $salepur_filter = " and pr.salepur = 'S'";
        }elseif($mod == 'po' ) {
            $salepur_filter = " and pr.salepur = 'P'";
        }

        $cny = GetMyCompany();
        $qry = "SELECT	DISTINCT pr.name, pr.record# prclstkey, pr.datefrom, pr.dateto, pr.locationkey prownerloc
						FROM    oeprclst pr 
						WHERE	 pr.cny# = :1 AND pr.name like :2 $salepur_filter $location_filter $department_filter ORDER BY  name ";

        $prclst = QueryResult(array($qry, $cny, $prclstname));

        $this->_prclst = $prclst;

        if ( $ReportOn == 'ITEMID') {

            if ( $fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'it', 'itemid', $itemValues);
                if($itemupcargs!='') {
                    $itemscodearray = array($itemupcargs);
                }
                $argtypesarray = array('text');
            } else {
                $itemscodearray = array($fromitemid, $toitemid, );
                $filterItemorUPC = " it.itemid >= ? and it.itemid <= ? ";
                $argtypesarray = array('text','text');
            }
            $orderBy = "it.itemid";
        }else {

            if ( $fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'it', 'upc', $upcValues);
                if($itemupcargs!='') {
                    $itemscodearray = array($itemupcargs);
                }
                $argtypesarray = array('text');
            } else {
                $itemscodearray = array($fromupc,$toupc);
                $filterItemorUPC = " it.upc >= ? and it.upc <= ? ";
                $argtypesarray = array('text', 'text');
            }
            $orderBy = "it.upc";
        }

        if ($prodlineid != '%') {
            //Get all child productlines
            $prodlinestring = " and it.productlinekey in ( select productlineid from icprodline where cny# = it.cny#
                start with cny# = it.cny# and productlineid= ?
                connect by cny# = it.cny# and parentlineid = PRIOR productlineid)";

            $itemscodearray[] = $prodlineid;
            $argtypesarray[] = 'text';
        } 
        
        $itemscodearray[] = $cny;
        $argtypesarray[] = 'integer';

        if ($prclstname != '%') {
            $prclstQrystring = " and pr.name = ? ";
            $itemscodearray[] = $prclstname;
            $argtypesarray[] = 'text';

            $prodlineargs        = array($cny, $prodlineid, $prclstname);
            $prodlineargtypes    = array( 'integer', 'text', 'text');
        } else {
            $prodlineargs = array($cny, $prodlineid);
            $prodlineargtypes    = array( 'integer', 'text');
        }


        if ($mod=='po') { 
            $itemsonlystring =" and it.itemtype <>'NS' ";
        }else if($mod=='so') {
            $itemsonlystring =" and it.itemtype <>'NP' ";
        }else {
            $itemsonlystring =" and it.itemtype in('I', 'SK' , 'K') ";
        }

        //$currencyfilter = ($this->_ismcpEnabled && $currency!='') ? " and pri.currency='".$currency."' " : "";
        $currencyfilter='';
        if($this->_ismcpEnabled) {
            if($this->params['CURRENCY']!='') {
                $currencyfilter = " and DECODE(pri.currency, NULL, '".$this->_baseCurrency."', pri.currency)='".$this->params['CURRENCY']."'";
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $itemscode = array(
        'QUERY' => "SELECT  IT.ITEMID, it.name item_description, it.productlinekey prodline, pr.record# prclstkey,
					pri.prclstkey, pri.QTYLIMITMIN, pri.QTYLIMITMAX, pri.QTYVAL, pri.VALUETYPE, pri.VALUE, 
					pri.DATEFROM, pri.DATETO, uom.unit as uomunit, it.locationkey itownerloc, it.upc, pri.CURRENCY 
				FROM oeprclst pr, oeprclstitems pri, icitem it, icuom uom, icuomgrp uomgrp
				WHERE
				$filterItemorUPC " . $prodlinestring . "
				and pri.prclstkey = pr.record#
				   and pr.cny# = ?
					and     pr.cny# = pri.cny#
					and     pr.record# = pri.prclstkey
					". $prclstQrystring."
					and     pri.cny# = it.cny#
					and     pri.itemkey = it.itemid
					and     pr.status = 'T'
					and     pri.status = 'T'
					and 	uomgrp.cny# = it.cny#
					and 	uomgrp.record# = it.uomgrpkey					
					and		uom.cny# = uomgrp.cny#
					and 	uom.isbase = 'T'
					and		uom.grpkey = uomgrp.record# 
					". $itemsonlystring.$currencyfilter."
					ORDER BY $orderBy",
        'ARGTYPES' => $argtypesarray,
        );

        if ($prodlineid != '%') {
            //Get all child productlines
            $prodlinestring = " and pri.productlinekey in ( select productlineid from icprodline where cny# = pri.cny#
                start with cny# = pri.cny# and productlineid= ?
                connect by cny# = pri.cny# and parentlineid = PRIOR productlineid)";

        } else {
            $prodlinestring = "and pri.productlinekey like ?";
        }

        $prodlinecode = array(
        'QUERY' => "SELECT  pri.*
					from oeprclst pr, oeprclstitems pri, icprodline ip
					WHERE
					 pr.cny# = ?
					" . $prodlinestring . "
					and     pr.cny# = pri.cny#
					and     pr.record# = pri.prclstkey
					" . $prclstQrystring . "
					and     pri.cny# = ip.cny#
					and     pri.productlinekey = ip.productlineid
					ORDER BY pri.productlinekey",
        'ARGTYPES' => $prodlineargtypes
        );

        $items         = $this->_QM->DoCustomQuery($itemscode, $itemscodearray, true);
        $prodlines     = $this->_QM->DoCustomQuery($prodlinecode, $prodlineargs, true);
        $this->_items = $items;
        $this->_prodlines = $prodlines;

        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $mod = Request::$r->_mod;
        
        // this convertypes array really duplicates data in the .rpt file, but I'm not sure how to grab the data right now
        // kludge
        $converttypes = array (
        'ACTUAL' => 'IA.ACTUAL',
        'DLR_MARKUP' => 'IA.DOLLAR_MARKUP',
        'DLR_DISC' => 'IA.DOLLAR_DISCOUNT',
        'PCT_MARKUP' => 'IA.PERCENT_MARKUP',
        'PCT_DISC' => 'IA.PERCENT_DISCOUNT'
        );

        $RepMap = array();
        $prclstMap = array();

        foreach($this->_prclst as $row){
            $row['HASITEMS']    ='no';
            $row['HASPRODS']    ='yes';
            $row['ITEMSCOUNT']    =0;
            $row['PRODSCOUNT']    =0;
            $row['NAMEHREF']    =
            "javascript:drilldown('lister',0,'" . urlencode($row['NAME']) . "', '$row[PROWNERLOC]');";
            $prclstMap[$row['PRCLSTKEY']] = $row;
        }

        //eppp($prclstMap);
        $prclstitemsMap = array();
        foreach($this->_items as $row){
            $prclstitemsMap[$row['PRCLSTKEY']][] = $row;
        }
        //eppp($prclstitemsMap);
        $prclstprodMap = array();
        foreach($this->_prodlines as $row){
            $prclstprodMap[$row['PRCLSTKEY']][] = $row;
        }

        foreach($prclstMap as $pr){
            $pr['HASITEMS']="no";
            $pr['HASPRODS']="no";
            $pr['ITEMSCOUNT']=0;
            $pr['PRODSCOUNT']=0;
            $pitems = [];
            $pprods = [];
            $display = 0; //default to no-show
            $key = $pr['PRCLSTKEY'];
            $items = $prclstitemsMap[$key] ?? [];

            if( count($items) > 0 ) {
                $display = 1;
                $pr['HASITEMS']="yes";
                $pr['ITEMSCOUNT']=count($items);
                for( $i=0; $i < count($items); $i++ ){
                    $itownerloc = $items[$i]['ITOWNERLOC'];
                    $plownerloc = $items[$i]['PLOWNERLOC'];

                    $pitems[$i]['PRCLSTITEMS_ITEMID']        = $items[$i]['ITEMID'];
                    $pitems[$i]['PRCLSTITEMS_ITEMHREF']        =
                    "javascript:drilldown('editor',1,'" . urlencode(addslashes($items[$i]['ITEMID'])) . "', '$itownerloc');";
                    //$pitems[$i]['PRCLSTITEMS_ITEM']			= $items[$i]['ITEM'];
                    // 7524: Rename output field to PRCLSTITEMS_ITEM_DESCRIPTION since we now display only Item Description in this field
                    $pitems[$i]['PRCLSTITEMS_ITEM_DESCRIPTION'] = $items[$i]['ITEM_DESCRIPTION'];
                    $pitems[$i]['PRCLSTITEMS_UPC'] = $items[$i]['UPC'];
                    $pitems[$i]['PRCLSTITEMS_PRODLINE']        = $items[$i]['PRODLINE'];
                    $pitems[$i]['PRCLSTITEMS_PRODLINEHREF']        =
                    "javascript:drilldown('editor',2,'" . urlencode($items[$i]['PRODLINE']) . "', '$plownerloc');";
                    $pitems[$i]['PRCLSTITEMS_QTYFROM']        = $items[$i]['QTYLIMITMIN'];
                    $pitems[$i]['PRCLSTITEMS_QTYTO']        = $items[$i]['QTYLIMITMAX'];
                    $pitems[$i]['PRCLSTITEMS_UOMUNIT']        = $items[$i]['UOMUNIT'];
                    $pitems[$i]['PRCLSTITEMS_VALTYPE']        = $converttypes[$items[$i]['VALUETYPE']];
                    $pitems[$i]['PRCLSTITEMS_VALUE']        = $this->roundUnitCost($items[$i]['ITEMID'], $items[$i]['VALUE']);
                    if($this->_ismcpEnabled) {
                        $pitems[$i]['CURRENCY']    = (!isset($items[$i]['CURRENCY']) || $items[$i]['CURRENCY']=='') ? $this->_baseCurrency : $items[$i]['CURRENCY'];
                    }else{
                        $pitems[$i]['CURRENCY']='';
                    }
                    if(    $pr['DATEFROM']     != $items[$i]['DATEFROM'] 
                        || $pr['DATETO']     != $items[$i]['DATETO']        
                    ) {
                        $pitems[$i]['PRCLSTITEMS_DATEFROM']    = $items[$i]['DATEFROM'];
                        $pitems[$i]['PRCLSTITEMS_DATETO']    = $items[$i]['DATETO'];
                    }
                }
            }

            $items = $prclstprodMap[$key];
            if( count($items ?? []) > 0 ) {
                $pr['HASPRODS']="yes";
                $pr['PRODSCOUNT']=count($items);
                $display = 1;
                for( $i=0; $i < count($items); $i++ ){
                    $plownerloc = $items[$i]['PLOWNERLOC'];
                    $pprods[$i]['PRCLSTPROD_PRODLINE']        = $items[$i]['PRODUCTLINEKEY'];
                    $pprods[$i]['PRCLSTPROD_PRODLINEHREF']        =
                    "javascript:drilldown('editor',2,'" . urlencode($items[$i]['PRODUCTLINEKEY']) . "', '$plownerloc');";
                    $pprods[$i]['PRCLSTPROD_QTYFROM']        = $items[$i]['QTYLIMITMIN'];
                    $pprods[$i]['PRCLSTPROD_QTYTO']            = $items[$i]['QTYLIMITMAX'];
                    $pprods[$i]['PRCLSTPROD_VALTYPE']        = $converttypes[$items[$i]['VALUETYPE']];
                    $pprods[$i]['PRCLSTPROD_VALUE']            = glFormatCurrency($items[$i]['VALUE']);
                    $pprods[$i]['CURRENCY']                    = $items[$i]['CURRENCY'];
                    if(    $pr['DATEFROM']     != $items[$i]['DATEFROM'] 
                        || $pr['DATETO']     != $items[$i]['DATETO']        
                    ) {
                        $pprods[$i]['PRCLSTPROD_DATEFROM']    = $items[$i]['DATEFROM'];
                        $pprods[$i]['PRCLSTPROD_DATETO']    = $items[$i]['DATETO'];

                    }
                }
            }

            // Have to format these dates and not the others as the report can only change date format for the entire cell
            $pr['DATEFROM'] = FormatDateForDisplay($pr['DATEFROM']);
            $pr['DATETO'] = FormatDateForDisplay($pr['DATETO']);

            if ($pitems != "") {
                $pr['PRCLSTITEMS']=$pitems;
            }
            if ($pprods != "") {
                $pr['PRCLSTPROD']=$pprods;
            }
            if ($display==1) {
                $RepMap[$key] = $pr;
            }
        }

        if (count($RepMap)==0) {
            $RepMap['NODATA'][0]= array('NODATA'=>'1');
        }

        
        $lines = $this->InvCommonHeader();

        $lines['report'][0]['ismcpEnabled'] = $this->_ismcpEnabled;
        $lines['report'][0]['mod'] = $mod; 

        $lines = $this->InvCommonBody($lines, $RepMap);
        
        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];

        return $lines;
    }

    /**
     * @return bool
     */
    function ValidateReport()
    {
        // override this function if you don't need all the checks for your report

        // put the various validations into seperate calls, so the sub classes don't have to override everything to get something
        // 		$this->ValidateDates();

        // Do any tweaks here that we need, like min/max vals, isl_htmlspecialchars, etc.
        $this->ParamTweaks();
        return true;
    }


    /**
     * @param array $params
     *
     * @return string
     */
    function GenerateJavascript($params)
    {
        // this is overridden because we need to go to a lister from the price list reports, not an editor

        return "
	function drilldown(page, which, rec, ownerloc) {
		popup = false;
		var allowed_ids = Array( " . $params['joinedops']  . ");
		var URL;
		if( allowed_ids[which] ){
			if (page == 'editor'){
				URL = 'editor.phtml?.op=' + allowed_ids[which] + '&.do=view' + '&.r=' + escape(rec);
			}
			if (page == 'lister'){
				URL = 'lister.phtml?.op=' + allowed_ids[which] + '&.plid=' + escape(rec);
			}
		}
		else{
			URL = '#';
		}
		DoDrill(URL, popup, ownerloc);

	}
			";
    }

}
