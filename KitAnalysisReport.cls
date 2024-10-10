<?php
import('InventoryReporter');
require_once 'Dictionary.cls';
const STOCKABLE_KIT = 'SK';
const INVENTORY_ITEM=  'I';
const REGULAR_KIT= 'K';


/**
 * Class KitAnalysisReport
 */
class KitAnalysisReport extends InventoryReporter
{

    /** @var array $KitItems */
    protected $KitItems = array();  // Array of kits, indexed with Kit IDs and value holding the individual kit components

    /** @var  int $_numdec */
    var $_numdec;

    /** @var  array $_warehouseInfo */
    var $_warehouseInfo;

    /** @var  int|float $_avgcost */
    var $_avgcost;

    /** @var  string $_warehouse */
    var $_warehouse;

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(INTACCTarray_merge($params,  array('report' => 'kit',  '2stage' => 'true')));
        if(IsMCMESubscribed()) {
            $this->params['NOREPORTLOCCHECK'] = true;
        }
        $this->params['orientation'] = 'L';
        $this->params['NOLOCCHECKREQUIRED'] = true; //Kit analysis don't have location UI field, so we need to bypass validation in FilterEditor::ValidateLocationFilter
    }

    /**
     * @return bool
     */
    function DoQuery() 
    {
        $this->ValidateReport();
        
        $companyid=GetMyCompany();

        /** @noinspection PhpUndefinedVariableInspection */
        $numdec= ( isset($row[0]['NUMDEC_STD']) && $row[0]['NUMDEC_STD'] != null) ? $row[0]['NUMDEC_STD'] : 4;
        $this->_numdec=$numdec;
        $params = $this->params['safe'];
        $fromwarehouseid = $params['FROMWAREHOUSEID'];
        $towarehouseid = $params['TOWAREHOUSEID'];
        $fromkitid = $params['FROMITEMID'];
        $tokitid = $params['TOITEMID'];
        $this->params['SHOWCOMPUTEDCOLS'] = '0';
        if (isset($this->params['FROMVALUE'])) {
            $maxqty    = ibcmul($this->params['FROMVALUE'], '1', $numdec);
            if ( (isset($fromkitid) && isset($tokitid)) && strcmp($fromkitid, $tokitid) ) {
                global $gErr;
                $gErr->addIAError('INV-0209', __FILE__ . ':' . __LINE__, "Warning!", [],"FYI, to filter for quantity needed or cost option, select 1 kit at a time.", []);
                return false;
            }                
        } else {
            $maxqty    = ibcmul('1', '1', $numdec);
        }
        if ($maxqty < 0) {
            global $gErr;
            $gErr->addIAError('INV-0210', __FILE__ . ':' . __LINE__, "Warning!", [],"Quantity Needed field must be equal to or greater than 0.", []);
            return false;
        }

        $showcostoption    = $this->params['SHOWCOST'];
        if ($showcostoption == 'true') {
            if ( (isset($fromkitid) && isset($tokitid)) && strcmp($fromkitid, $tokitid) ) {
                global $gErr;
                $gErr->addIAError('INV-0211', __FILE__ . ':' . __LINE__, "Warning!", [], "FYI, to filter for quantity needed or cost option, select 1 kit at a time.", []);
                return false;
            }
        }
        if ( (isset($fromkitid) && isset($tokitid)) && !strcmp($fromkitid, $tokitid) ) {
            $this->params['SHOWCOMPUTEDCOLS'] = '1';
        }
        $rval = $this->PopulateKitComponents($companyid, $fromkitid, $tokitid, $fromwarehouseid, $towarehouseid, $numdec, $showcostoption, $maxqty);
        return $rval;
        
    }

    /**
     * @param string    $companyid
     * @param string    $fromkitid
     * @param string    $tokitid
     * @param string    $fromwarehouseid
     * @param string    $towarehouseid
     * @param int       $numdec
     * @param string    $showcostoption
     * @param float|int $maxqty
     *
     * @return bool
     */
    function PopulateKitComponents($companyid, $fromkitid, $tokitid, $fromwarehouseid, $towarehouseid, $numdec, $showcostoption, $maxqty) 
    {
        //main query for picking kit and its components using recursion
        $KitItem = $this->getKitComponents($companyid, $fromkitid, $tokitid);
        
        $warehouse = $this->getWarehouseIds($fromwarehouseid, $towarehouseid, $companyid);
        
        $warehouse=$this->mergeKitComponentsDataIntoWhse($companyid, $this->KitItems, $warehouse);
        
        $whseqty = array();
        $componentArgs = [];
        foreach ($this->KitItems as $itemskey => $itemsval) {
            $componentArgs = $this->prepareComponentsListForQueries($itemskey, $itemsval, $componentArgs);
            $itemskey = $itemskey ? isl_htmlspecialchars($itemskey) : '';
            //fetch the qty details of the given components
            $whseqty[$itemskey] = $this->getComponentWarehouseQtys($companyid, $fromwarehouseid, $towarehouseid, $componentArgs);
        }
        //proces array to embed extra information required in the xsl
        foreach($warehouse as $warekey => $wareval) {
            
            $whseKey=$wareval['WAREHOUSEKEY'];
            
            foreach($wareval['KIT'] as $kitkey => $kitval) {
                // Update possible units for top level stkit and possible units and other data for the children in the calculatePossibleQty call
                $stKit=$kitval['OBJECT'];
                $this->updateQtyData(
                    $whseKey, $whseqty[$kitval['ITEMID']],
                    $warehouse[$warekey]['KIT'][$kitkey]['COMPONENT'], $stKit, $maxqty
                );
                if (isset($whseqty[$kitval['ITEMID']][$warehouse[$warekey]['WAREHOUSEKEY']][$kitval['ITEMID']])) {
                    $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYONHOLD'] = $whseqty[$kitval['ITEMID']][$warehouse[$warekey]['WAREHOUSEKEY']][$kitval['ITEMID']]['QUANTITYONHOLD'];
                    $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYONHAND'] = $whseqty[$kitval['ITEMID']][$warehouse[$warekey]['WAREHOUSEKEY']][$kitval['ITEMID']]['QUANTITYONHAND'];
                    $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYAVAILABLE'] = $whseqty[$kitval['ITEMID']][$warehouse[$warekey]['WAREHOUSEKEY']][$kitval['ITEMID']]['QUANTITYAVAILABLE'];
                } else {
                    $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYONHOLD'] = 0;
                    $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYONHAND'] = 0;
                    $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYAVAILABLE'] = 0;
                }
                
                $curQtyAvail = array();
                $warehouse[$warekey]['KIT'][$kitkey]['POSSIBLE_UNITS'] = $this->calculatePossibleQty(
                    $whseqty[$kitval['ITEMID']],
                    $warehouse[$warekey]['KIT'][$kitkey]['COMPONENT'], $stKit, -1, $curQtyAvail
                );
                if ($maxqty>0) {
                    $warehouse[$warekey]['KIT'][$kitkey]['HASPREF']='yes';
                    $warehouse[$warekey]['KIT'][$kitkey]['PREFERRED_UNITS'] = $maxqty;
                    if ( ($maxqty) > ($warehouse[$warekey]['KIT'][$kitkey]['POSSIBLE_UNITS'] + $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYAVAILABLE']) ) {
                        $warehouse[$warekey]['KIT'][$kitkey]['QUANTITY_REQUIRED'] = ibcmul($maxqty - $warehouse[$warekey]['KIT'][$kitkey]['POSSIBLE_UNITS'] - $warehouse[$warekey]['KIT'][$kitkey]['QUANTITYAVAILABLE']
                            , '1', $this->_numdec);
                    } else {
                        $warehouse[$warekey]['KIT'][$kitkey]['QUANTITY_REQUIRED'] = ibcmul('0', '1', $this->_numdec);
                    }
                }else{
                    $warehouse[$warekey]['KIT'][$kitkey]['HASPREF']='no';
                }
                if ($showcostoption=='true') {
                    $warehouse[$warekey]['KIT'][$kitkey]['HASCOSTOPTION']='yes';
                }else{
                    $warehouse[$warekey]['KIT'][$kitkey]['HASCOSTOPTION']='no';
                }
                if ($this->params['type'] == '_html') {
                    $warehouse[$warekey]['KIT'][$kitkey]['TREEITEM'] = Util::getListTreeString('0', $warehouse[$warekey]['KIT'][$kitkey]['ITEMID'], false, true);
                } else {
                    $warehouse[$warekey]['KIT'][$kitkey]['TREEITEM'] = $warehouse[$warekey]['KIT'][$kitkey]['ITEMID'];
                }

                $curQtyAvail = array();
                $this->updateAdditionalUnits($warekey, $kitkey, $whseqty[$kitval['ITEMID']], $warehouse[$warekey]['KIT'][$kitkey]['COMPONENT'], $stKit
                    , $curQtyAvail);
            }
        }
            
        if (Util::countOrZero($this->KitItems) > 0) {
            // moved the query into here because the one in qry file is putting an or between the item and product line ids
            $avgcost = $this->getKitComponentsStdAvgCosts($companyid, $componentArgs);
            $this->_avgcost = $avgcost;
        }

        foreach( $warehouse as $k => $v){
            foreach($warehouse[$k]['KIT'] as $kitkey => $kitval){
                //$totalcost=0;
                $prevlevel=0;
                //$subtotalcost=0;
                $kititemids=array($kitval[0]['ITEMID']);
                $subtotals=array(0);
                //$kititemndx=array(-1);
                $skipComponent = false;
                $skipLevel = 0;

                foreach( $warehouse[$k]['KIT'][$kitkey]['COMPONENT'] as $kc => $vc){
                    $currlevel=$warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['ITEMLEVEL'];
                    if ($this->params['type'] == '_html') {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['TREEITEM'] = Util::getListTreeString($currlevel, $warehouse[$warekey]['KIT'][$kitkey]['COMPONENT'][$kc]['COMPONENT_ID'], false, true);
                    } else {
                        /** @noinspection PhpUndefinedVariableInspection */
                        $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['TREEITEM'] = $warehouse[$warekey]['KIT'][$kitkey]['COMPONENT'][$kc]['COMPONENT_ID'];
                    }
                    if ( ($currlevel > $skipLevel) && ($skipComponent == true) ) {
                         continue;
                    }
                    
                    $itemtotalcost=0;
                    /** @noinspection PhpUndefinedVariableInspection */
                    foreach( $avgcost as $key => $val){
                        if(($warehouse[$k]['WAREHOUSEKEY']==$avgcost[$key]['WAREHOUSEKEY'] || !isset($avgcost[$key]['WAREHOUSEKEY'])) && $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['COMPONENT_ID']==$avgcost[$key]['ITEMKEY']) {
                            $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['AVERAGE_COST']=ibcmul($avgcost[$key]['AVERAGE_COST'], '1', $numdec);
                            if($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['QUANTITY_FORMAX'] >0 && ( ( ($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['ITEMTYPE'] == STOCKABLE_KIT) || ($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['ITEMTYPE'] == KIT) ) && ($avgcost[$key]['AVERAGE_COST'] > 0) ) ) {
                                $itemtotalcost=ibcmul($avgcost[$key]['AVERAGE_COST'], $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['QUANTITY_FORMAX'], $numdec);
                                $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['TOTALCOST']=$itemtotalcost;
                                $skipComponent = true;
                                $skipLevel = $currlevel;
                            } else if($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['QUANTITY_FORMAX'] >0 && $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['ITEMTYPE']!=STOCKABLE_KIT) {
                                $itemtotalcost=ibcmul($avgcost[$key]['AVERAGE_COST'], $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['QUANTITY_FORMAX'], $numdec);
                                $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['TOTALCOST']=$itemtotalcost;
                            }
                        }
                    }
                    if ($currlevel>1 && $currlevel > $prevlevel) {
                        //Prev row started a new kit
                        array_push($subtotals, $itemtotalcost);
                        array_push($kititemids, $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc-1]['COMPONENT_ID']);
                    } else if ($currlevel<$prevlevel) {
                        //kit ended with the previous component iteration save its subtotals
                        for ($i=$prevlevel;$i>$currlevel;$i--) {
                            $prevkitsubtotal=array_pop($subtotals);
                            $prevkitid=array_pop($kititemids);
                            $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc-1]['TOTALS'][]=array('KITTOTAL' => ibcmul($prevkitsubtotal, '1', $numdec),
                                         'KITNAME_FOR_KITTOTAL'=>'IA.SUBTOTAL ('.$prevkitid.')');
                            $subtotals[Util::countOrZero($subtotals)-1]+=$prevkitsubtotal;
                            $subtotals[Util::countOrZero($subtotals)-1]+=$itemtotalcost;
                        }
                    } else {
                        //Same kit continuing, accumulate totals
                        $subtotals[Util::countOrZero($subtotals)-1]+=$itemtotalcost;
                    }
                    if ($showcostoption=='true') {
                        $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['SHOW_COST']='yes';
                    } else{
                        $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['SHOW_COST']='no';
                    }
                    $prevlevel=$currlevel;
                }                
                
                //Create subtotal entries for any stkits that ended along with the main stkit
                while (Util::countOrZero($subtotals) > 0 && Util::countOrZero($kititemids) > 0) {
                    $prevkitsubtotal = array_pop($subtotals);
                    $prevkitid = array_pop($kititemids);
                    // Ticket:165057 PHP 8.1 replaced count with Util::countOrZero in case $warehouse[$k]['KIT'][$kitkey]['COMPONENT'] is string
                    $lastCompNdx = Util::countOrZero($warehouse[$k]['KIT'][$kitkey]['COMPONENT']);
                        
                    if (Util::countOrZero($subtotals)>0) {
                        $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$lastCompNdx-1]['TOTALS'][]=array('KITTOTAL' => ibcmul($prevkitsubtotal, '1', $numdec),
                                                                                        'KITNAME_FOR_KITTOTAL'=>'IA.SUBTOTAL ('.$prevkitid.')');
                        //Prev kit cost should also be included as it contributes to its parent kit
                        $subtotals[Util::countOrZero($subtotals)-1]+=$prevkitsubtotal;
                    } else {
                        $warehouse[$k]['KIT'][$kitkey]['KITTOTAL']=ibcmul($prevkitsubtotal, '1', $numdec);
                        $warehouse[$k]['KIT'][$kitkey]['KITNAME_FOR_KITTOTAL']='IA.TOTAL ('.$warehouse[$k]['KIT'][$kitkey]['ITEMID'].')';
                    }
                }
            }
        }

        foreach( $warehouse as $k => $v){
            foreach( $warehouse[$k]['KIT'] as $kitkey => $kitval){
                foreach( $warehouse[$k]['KIT'][$kitkey]['COMPONENT'] as $kc => $vc){
                    if(!isset($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['AVERAGE_COST'])) {
                        if ($showcostoption=='true') {
                            $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['SHOW_COST']='yes';
                        }else{
                            $warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc]['SHOW_COST']='no';
                        }
                    }
                }
            }
        }
        
        // Separate out subtotal lines from the rows
        foreach( $warehouse as $k => $v){
            foreach( $warehouse[$k]['KIT'] as $kitkey => $kitval){
                $totalsAddedSoFar=0;
                foreach($warehouse[$k]['KIT'][$kitkey]['COMPONENT'] as $kc => $vc){
                    // Since we are splicing (changing) the components array as we loop through it, $kc still refers to the original index before the insertion of totals
                    // So we splice(insert) the elements at the correct location, we need to keep track of howmany component elements have been added
                    if(isset($vc['TOTALS'])) {
                        $totalArr=$vc['TOTALS'];
                        unset($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc+$totalsAddedSoFar]['TOTALS']);
                        $currComp=array($warehouse[$k]['KIT'][$kitkey]['COMPONENT'][$kc+$totalsAddedSoFar]);
                        foreach( $totalArr as $totalRow) {
                            $currComp[]=array('KITTOTAL' => $totalRow['KITTOTAL'],'KITNAME_FOR_KITTOTAL'=>$totalRow['KITNAME_FOR_KITTOTAL']);
                        }
                        array_splice($warehouse[$k]['KIT'][$kitkey]['COMPONENT'], $kc+$totalsAddedSoFar, 1, $currComp);
                        $totalsAddedSoFar+=Util::countOrZero($totalArr);
                    }
                }
            }
        }
        
        $this->cleanUpObjects($warehouse);
        
        //final array
        $warehouseInfo[0]['WAREHOUSE']=$warehouse;
        $items=$KitItem;

        $this->_items = $items;
        $this->_warehouse = $warehouse;
        $this->_warehouseInfo = $warehouseInfo;
        
        return true;
    }

    /**
     * @return array
     */
    function DoMap() 
    {
        $numdec=$this->_numdec;

        $RepMap = array();
        
        if (Util::countOrZero($this->_warehouseInfo[0]['WAREHOUSE']) > 0) {
            $warehouseinfoMap=$this->_warehouseInfo;

            for($i = 0; $i < Util::countOrZero($warehouseinfoMap); $i++){
                $warehouseinfoMap[$i]['HASITEMS']    ='no';
                $warehouseinfoMap[$i]['ITEMSCOUNT']    =0;
            }

            if (isset($this->params['FROMVALUE'])) {
                $maxqty    = ibcmul($this->params['FROMVALUE'], '1', $numdec);
            } else {
                $maxqty    = ibcmul('1', '1', $numdec);
            }
            $showcostoption    = $this->params['SHOWCOST'];
            $itemsMap=$this->_items;

            foreach($warehouseinfoMap as $pr){
                $pr['HASITEMS']="no";
                $pr['ITEMSCOUNT']=0;
                $pitems = "";
                $display = 0; //default to no-show
                $items = $itemsMap;

                if( Util::countOrZero($items) > 0 ) {
                    $display = 1;
                    $pr['HASITEMS']="yes";
                    $pr['ITEMSCOUNT']=Util::countOrZero($items);
                }
                if ($pitems != "") {
                    $pr['ITEMS']=$pitems;
                }
                if ($display==1) {
                    $RepMap[0] = $pr;
                }
            }
        }

        if (Util::countOrZero($RepMap)==0) {
            $RepMap['NODATA'][0]= array('NODATA'=>'1');
        }

        $lines = $this->InvCommonHeader();
        /** @noinspection PhpUndefinedVariableInspection */
        if( $maxqty > 0) {
            $lines['report'][0]['HASMAXQTY'] = 1;
        }else{
            $lines['report'][0]['HASMAXQTY'] = 0;
        }
        /** @noinspection PhpUndefinedVariableInspection */
        if( $showcostoption == 'true') {
            $lines['report'][0]['SHOWCOSTOPTION'] = 'yes';
        }else{
            $lines['report'][0]['SHOWCOSTOPTION'] = 'no';
        }
        $lines['report'][0]['WRAP'] = 'N';
        $lines['report'][0]['SHOWCOMPUTEDCOLS'] = $this->params['SHOWCOMPUTEDCOLS'];
        $lines = $this->InvCommonBody($lines, $RepMap);
        return $lines;
    }

    /**
     * Gets all components (incl those which are stkits themselves) down to the lowest level
     *
     * @param string    $companyid
     * @param string    $fromkitid
     * @param string    $tokitid
     *
     * @return array
     */
    function getKitComponents($companyid,$fromkitid, $tokitid) 
    {
        $code = array(
        'QUERY' =>"select	CONNECT_BY_ROOT itemkey as itemroot, icitemcomponent.itemkey as parentid,
								icitemcomponent.componentkey as component_id,
						        icitem.name as component_description,
								icitemcomponent.quantity AS quantity,
								icitemcomponent.quantity AS quantityperkit,
								icitemcomponent.unit as uom,
								icitem.standard_COST as std_cost,
		                        CASE
									when icitem.COST_METHOD='S' then 'IA.STANDARD'
									when icitem.COST_METHOD='A' then 'IA.AVERAGE'
									when icitem.COST_METHOD='L' then 'IA.LIFO'
									when icitem.COST_METHOD='F' then 'IA.FIFO'
								END  as cost_method,
								ICITEM.itemtype as itemtype,
						        glgroup.name as itemglgrp,
								level as itemlevel
						from icitemcomponent, icitem
						   , icitemglgrp glgroup
						where	icitem.cny#=icitemcomponent.cny# and 
								icitemcomponent.componentkey = icitem.itemid and 
								icitem.cny# = ? and 
								icitem.status = 'T' and
						        icitem.cny# = glgroup.cny#(+) and 
						        icitem.glgrpkey = glgroup.record#(+)
						        
						start with icitemcomponent.itemkey in 
	                            (select distinct itemkey from icitemcomponent toplevelkit where toplevelkit.cny#=? and itemkey between ? and ?)
		                         and icitemcomponent.cny# = ? 
						connect by icitemcomponent.itemkey = PRIOR icitemcomponent.componentkey and icitemcomponent.cny# = ?
		                order siblings by icitemcomponent.itemkey",
        'ARGTYPES' => array('integer','text'),
        );
        
        $args = array ($companyid, $companyid, $fromkitid, $tokitid, $companyid, $companyid);
        $kitComponents = $this->_QM->DoCustomQuery($code, $args, true);
        $kitId = '';
        
        // Generate the array indexed using kit IDs
        foreach($kitComponents as $keykey) {
            if (is_array($keykey)) {
                if ($kitId != $keykey['ITEMROOT']) {
                     $kitId = $keykey['ITEMROOT'];
                }
                $keykey['ITEMROOT'] = $keykey['ITEMROOT'] ? isl_trim(isl_htmlspecialchars($keykey['ITEMROOT'])) : '';
                $keykey['PARENTID'] = $keykey['PARENTID'] ? isl_trim(isl_htmlspecialchars($keykey['PARENTID'])) : '';
                $keykey['COMPONENT_ID'] = $keykey['COMPONENT_ID'] ? isl_trim(isl_htmlspecialchars($keykey['COMPONENT_ID'])) : '';
                $keykey['COMPONENT_DESCRIPTION'] = $keykey['COMPONENT_DESCRIPTION'] ? isl_trim(isl_htmlspecialchars($keykey['COMPONENT_DESCRIPTION'])) : '';
                $keykey['ITEMTYPE_DESC']= self::getTokenForItemTypeDesc($keykey['ITEMTYPE']);
                $this->KitItems[$kitId][] = $keykey;
                $kitId = $keykey['ITEMROOT'];
            }
        }
        return $kitComponents;
        
    } 
    
    /**
     * Gets the topmost stkit properties and attached $itemArray as its COMPONENT array
     *
     * @param string    $companyId
     * @param array     $kitItems
     *
     * @return array
     */
    function attachKitPropertiesToItems(/** @noinspection PhpUnusedParameterInspection */ $companyId,$kitItems) 
    {
        $kitComps = array();
        
        /*
        * Collect all the kit and nested kits as comma separated clause
        * Actually - this only collects the top level kit 
        */

        //get kit details which will be used in the header section of the array
        $stmt[0] = "select 	icitem.itemid,
								icitem.name,
								uom.unit,
								ICITEM.itemtype as itemtype,
								case
									when COST_METHOD='S' then 'IA.STANDARD'
									when COST_METHOD='A' then 'IA.AVERAGE'
									when COST_METHOD='L' then 'IA.LIFO'
									when COST_METHOD='F' then 'IA.FIFO'
								END  as COST_METHOD, 
								0 as POSSIBLE_UNITS, 
								'no' as HASPREF, 
								'no' as HASCOSTOPTION, 
								'' as PREFERRED_UNITS, 
								0 as itemlevel 
					   from 	icitem, icuom uom, icuomgrp uomgrp 
					   where 	uomgrp.cny# = icitem.cny#
						and 	uomgrp.record# = icitem.uomgrpkey					
						and		uom.cny# = uomgrp.cny#
						and 	uom.isbase = 'T'
						and		uom.grpkey = uomgrp.record#
					   and 		icitem.status = 'T' 
					   and 		icitem.cny#= :1";
        $stmt[1] = GetMyCompany();
        $stmt = PrepINClauseStmt($stmt, array_keys($kitItems), " and itemid");
        $kits = QueryResult($stmt, 0, '', null, true);
            
        foreach($kits as $kitval) {
            $itemval = $kitItems[$kitval['ITEMID']];
            $kitval['ITEMID'] = $kitval['ITEMID'] ? isl_trim(isl_htmlspecialchars($kitval['ITEMID'])) : '';
            $itemkey = $kitval['ITEMID'];
            $kitval['ITEMTYPE_DESC']= self::getTokenForItemTypeDesc($kitval['ITEMTYPE']);
            $stkit=new StockableKitItemDataObject($kitval);
            $stkit->addComponentsArray($itemval);
            $kitComps[$itemkey] = $kitval;
            $kitComps[$itemkey]['COMPONENT'] = $itemval;
            $kitComps[$itemkey]['OBJECT'] = $stkit;
        }
        return $kitComps;
    }
    private static function getTokenForItemTypeDesc(string $itemType): string
    {
        //need to show itemtype only for k and sk
        $itemTypeDesc="";
        switch($itemType){
            case 'K' :
                $itemTypeDesc= 'IA.KIT' ;
                break;
            case 'SK':
                $itemTypeDesc='IA.STOCKABLE_KIT' ;
                break;
       }
        return $itemTypeDesc;
    }
    /**
     * @param string $kitname
     * @param array $itemsArray
     * @param array $componentArgs
     *
     * @return array
     */
    function prepareComponentsListForQueries($kitname, &$itemsArray, &$componentArgs)
    {
        foreach ($itemsArray as $key => $val) {
            if ($itemsArray[$key]['ITEMTYPE'] == REGULAR_KIT) {
                unset($itemsArray[$key]);
            } else {
                // Why are these unsets required
                //unset($itemsArray[$key]['PARENTID']);
                //unset($itemsArray[$key]['ITEMTYPE']);
                $componentArgs[] = $itemsArray[$key]['COMPONENT_ID'];
            }
        }
        $componentArgs[] = $kitname;

        return $componentArgs;
    }

    /**
     * @param string    $companyId
     * @param string    $fromWarehouseId
     * @param string    $toWarehouseId
     * @param array     $componentArgs
     *
     * @return array
     */
    function getComponentQuantities($companyId, $fromWarehouseId, $toWarehouseId, $componentArgs)
    {
        //fetch the qty details of the given components
        $stmt[0] = "select 	warehousekey,
		                        itemkey,
		 						qtyonhand as QUANTITY,
		 						qtyonhold as QUANTITYONHOLD, 
                                qtyonhand AS QUANTITYONHAND,
                                qtyonhand - qtyonhold AS QUANTITYAVAILABLE
		 			  from 		v_itemavail 
		 			  where  	cny#= :1 
		 			  and 	    warehousekey between :2 and  :3";
        $stmt[1] = $companyId;
        $stmt[2] = $fromWarehouseId;
        $stmt[3] = $toWarehouseId;
        $stmt = PrepINClauseStmt($stmt, $componentArgs, " and itemkey");
        $itemsqty = QueryResult($stmt, 0, '', null, true);

        return $itemsqty;

    }

    /**
     * @param string    $fromwarehouseid
     * @param string    $towarehouseid
     * @param string    $companyid
     *
     * @return array
     */
    function getWarehouseIds($fromwarehouseid,$towarehouseid,$companyid) 
    {
        
        $warehouseargs = array($fromwarehouseid,$towarehouseid,$companyid);
        $warehouseargtypes = array( 'text', 'text', 'integer');
        $warehousecode = array('QUERY'=> "select icitemwhse.warehousekey 
											from icitemwhse, icwarehouse 
										   where icitemwhse.warehousekey=icwarehouse.location_no 
											 and  icitemwhse.warehousekey between ? and  ?  
											 and icitemwhse.cny# = icwarehouse.cny# 
											 and icitemwhse.cny#=? 
											 and icwarehouse.status = 'T' 
										group by icitemwhse.warehousekey
		                                order by icitemwhse.warehousekey",
                           'ARGTYPES' => $warehouseargtypes);
        $warehouse = $this->_QM->DoCustomQuery($warehousecode, $warehouseargs, true);
        return $warehouse;
    }

    /**
     * @param string    $companyid
     * @param string $fromwarehouseid
     * @param string $towarehouseid
     * @param array $componentArgs
     *
     * @return array
     */
    function getComponentWarehouseQtys($companyid,$fromwarehouseid,$towarehouseid,$componentArgs)
    {

        //fetch the qty details of the given components
        $itemsqty = $this->getComponentQuantities($companyid, $fromwarehouseid, $towarehouseid, $componentArgs);
        // Does not seem like this is used - commenting it for now
        //$this->_itemsqty = $itemsqty;

        $whseqty = array();
        //insert the qty information back to the array
        for ($i = Util::countOrZero($itemsqty) - 1; $i >= 0; $i--) {
            $whseqty[$itemsqty[$i]['WAREHOUSEKEY']][$itemsqty[$i]['ITEMKEY']]['QUANTITY'] = $itemsqty[$i]['QUANTITY'];
            $whseqty[$itemsqty[$i]['WAREHOUSEKEY']][$itemsqty[$i]['ITEMKEY']]['QUANTITYONHOLD'] = $itemsqty[$i]['QUANTITYONHOLD'];
            $whseqty[$itemsqty[$i]['WAREHOUSEKEY']][$itemsqty[$i]['ITEMKEY']]['QUANTITYAVAILABLE'] = $itemsqty[$i]['QUANTITYAVAILABLE'];
            $whseqty[$itemsqty[$i]['WAREHOUSEKEY']][$itemsqty[$i]['ITEMKEY']]['QUANTITYONHAND'] = $itemsqty[$i]['QUANTITYONHAND'];
        }

        return $whseqty;
    }

    /**
     * @param string    $companyid
     * @param array     $kitItems
     * @param array     $warehouse
     *
     * @return array
     */
    function mergeKitComponentsDataIntoWhse($companyid,$kitItems,$warehouse) 
    {
    
        $kitComps = $this->attachKitPropertiesToItems($companyid, $kitItems);
        //remove keys from the array
        foreach( $kitComps as $kit => $kitcomp){
            foreach( $warehouse as $k => $v){
                 $warehouse[$k]['KIT'][] = $kitComps[$kit];
            }
        }
        return $warehouse;
    }

    /**
     * @param string    $companyId
     * @param array     $componentArgs
     *
     * @return bool|string[][]
     */
    function getKitComponentsStdAvgCosts($companyId,$componentArgs)
    {

        $currDate = GetCurrentDate();
        $avgcostargs = array($companyId, $currDate, $companyId);

        $avgcostcode = array(
        'QUERY'=> "select icitemwhse.warehousekey, icitem.itemid itemkey, 
			                       (case 
			                       		when icitem.itemtype in ('I','SK') then
					                       	(case 
					                            when icitem.cost_method = 'S' then
					                            	(case 
                                          when stdcost.standard_cost is not null then stdcost.standard_cost
					                            		when icitemwhse.standard_cost is not null then icitemwhse.standard_cost
					                            		else icitem.standard_cost
					                            	end)
					                            else 
					                            	(
                                                     select cost from
                                                      ( select cost from itmhistcost
                                                          where cny# = :1 and itemkey = icitem.itemid and whsekey = icitemwhse.warehousekey
                                                          order by ason desc ,  whencreated desc )
                                                      where ROWNUM = 1					                            	
                                                    )  
					                        end)
			                        	else icitem.standard_cost
			                        end) average_cost
						from icitem
                        left outer join icitemwhse on icitemwhse.cny# = icitem.cny# and icitemwhse.itemkey = icitem.itemid
                        left outer join icitemwhsestdcost stdcost on stdcost.cny# = icitemwhse.cny# and stdcost.itemwhsekey = icitemwhse.record# 
                                                and stdcost.effective_start_date = (select max(effective_start_date) 
                                                                                    from icitemwhsestdcost itws 
                                                                                    where itws.cny# = icitemwhse.cny# and itws.itemwhsekey = icitemwhse.record# 
                                                                                    and itws.effective_start_date <= TO_DATE (:2, 'mm/dd/yyyy'))
						where icitem.status = 'T' and 
							  icitem.cny# = :3 
					"
        );
        $avgcostcode['QUERY'] = PrepINClauseStmt($avgcostcode['QUERY'], $componentArgs, " AND icitem.itemid ",true,'kitanalysis', true);
        // moved the query into here because the one in qry file is putting an or between the item and product line ids
        $avgcost = $this->_QM->DoCustomQuery($avgcostcode, $avgcostargs, true);
        return $avgcost;
    }

    /**
     * @param string                        $whseKey
     * @param array                         $whseqty
     * @param array                         $compsArr
     * @param StockableKitItemDataObject    $stKit
     * @param float|int                     $maxqty
     */
    function updateQtyData($whseKey,&$whseqty,&$compsArr,$stKit, $maxqty) 
    {
        $comps=$stKit->getComponents();
        foreach($comps as $compId => $compObj) {
            $compIndex=$stKit->getArrayIndex($compId);
            $compval=&$compsArr[$compIndex];
            if (Util::countOrZero($whseqty) != 0) {
                if (Util::countOrZero(($whseqty[$whseKey][$compId] ?? [])) != 0) {
                      LogToFile("QUANTITYONHAND[" . $compId . "] = " . $whseqty[$whseKey][$compId]['QUANTITYONHAND'] . "\n");
                      LogToFile("QUANTITYONHOLD[" . $compId . "] = " . $whseqty[$whseKey][$compId]['QUANTITYONHOLD'] . "\n");
                      LogToFile("QUANTITY[" . $compId . "] = " . $whseqty[$whseKey][$compId]['QUANTITY'] . "\n");
                    if (isset($whseqty[$whseKey][$compId]['QUANTITYONHOLD'])) {
                        $compval['QUANTITYONHOLD'] = $whseqty[$whseKey][$compId]['QUANTITYONHOLD'];
                        $compval['QUANTITYONHAND'] = $whseqty[$whseKey][$compId]['QUANTITYONHAND'];
                        $compval['QUANTITYAVAILABLE'] = $whseqty[$whseKey][$compId]['QUANTITYAVAILABLE'];
                    } else {
                        $compval['QUANTITYONHOLD'] = 0;
                        $compval['QUANTITYONHAND'] = 0;
                        $compval['QUANTITYAVAILABLE'] = 0;
                    }
                } else {
                    $compval['QUANTITYONHOLD'] = 0;
                    $compval['QUANTITYONHAND'] = 0;
                    $compval['QUANTITYAVAILABLE'] = 0;
                }
            } else {
                $compval['QUANTITYONHOLD'] = 0;
                $compval['QUANTITYONHAND'] = 0;
                $compval['QUANTITYAVAILABLE'] = 0;
            }
            $compval['QUANTITYPERKIT']=ibcmul($compval['QUANTITYPERKIT'], '1', $this->_numdec);
            $compval['QUANTITY_FORMAX']=ibcmul($compval['QUANTITYPERKIT'], $maxqty, $this->_numdec);
            $compval['QUANTITY_REQUIRED'] =$compval['QUANTITY_FORMAX'];
            if ( ($compval['ITEMTYPE'] == STOCKABLE_KIT) || ($compval['ITEMTYPE'] == REGULAR_KIT) ) {
                $this->updateQtyData($whseKey, $whseqty, $compsArr, $compObj, $compval['QUANTITY_FORMAX']);
            }
        }
    }

    /**
     * @param string                        $warekey
     * @param string                        $kitkey
     * @param float|int                     $whseqty
     * @param array                         $compsArr
     * @param StockableKitItemDataObject    $stKit
     * @param array                         $currentQtyAvail
     */
    function updateAdditionalUnits($warekey, $kitkey, &$whseqty,&$compsArr,$stKit, &$currentQtyAvail)
    {
        $comps = $stKit->getComponents();
        foreach($comps as $compId => $compObj) {
            $compIndex=$stKit->getArrayIndex($compId);
            $compval=&$compsArr[$compIndex];
            $maxqtyRequired = $compval["QUANTITY_FORMAX"];

            if ( isset($currentQtyAvail[$compId]) ) {
                if ($currentQtyAvail[$compId] != 0) {
                    if ($currentQtyAvail[$compId] < $maxqtyRequired) {
                        $compval['QUANTITY_REQUIRED'] = ibcadd($maxqtyRequired - $currentQtyAvail[$compId], '0', $this->_numdec);
                        $currentQtyAvail[$compId] = 0;
                    } else {
                        $currentQtyAvail[$compId] = $currentQtyAvail[$compId] - $maxqtyRequired;
                        $compval['QUANTITY_REQUIRED']  = ibcadd('0', '0', $this->_numdec);
                     }
                } else {
                    $compval['QUANTITY_REQUIRED'] = ibcadd($maxqtyRequired, '0', $this->_numdec);
                }
            } else if ( $compval['QUANTITYAVAILABLE'] >= 0 ) {
                if ( $compval['QUANTITYAVAILABLE'] < $maxqtyRequired ) {
                    $compval['QUANTITY_REQUIRED'] = ibcadd($maxqtyRequired - $compval['QUANTITYAVAILABLE'], '0', $this->_numdec);
                    $currentQtyAvail[$compId] = 0;
                } else {
                    $currentQtyAvail[$compId] = $compval['QUANTITYAVAILABLE'] - $maxqtyRequired;
                    $compval['QUANTITY_REQUIRED']  = ibcadd('0', '0', $this->_numdec);
                }
            }
            if ( ($compval['ITEMTYPE'] == STOCKABLE_KIT) || ($compval['ITEMTYPE'] == REGULAR_KIT)){
                $this->updateAdditionalUnits($warekey, $kitkey, $whseqty, $compsArr, $compObj, $currentQtyAvail);
            }
        }
    }

    /**
     * @param array                         $compsArr
     * @param StockableKitItemDataObject    $stKit
     * @param array                         $currentQtyAvail
     * @param float|int                     $possibleUnits
     */
    function updateCurrentQtyAvailable(&$compsArr,$stKit,&$currentQtyAvail, $possibleUnits) 
    {
        $comps=$stKit->getComponents();

        foreach( $comps as $compId => $compObj) {
            $compIndex=$stKit->getArrayIndex($compId);
            $compval=$compsArr[$compIndex];
            
            if ( ($compval['ITEMTYPE'] != STOCKABLE_KIT) && ($compval['ITEMTYPE'] != REGULAR_KIT) && ($compval['ITEMTYPE'] == INVENTORY_ITEM) ) {
                if ( isset($currentQtyAvail[$compId]) ) {
                    if ($currentQtyAvail[$compId] != 0) {
                        if ($currentQtyAvail[$compId] < ($compval['QUANTITYPERKIT']*$possibleUnits)) {
                            $currentQtyAvail[$compId] = 0;
                        } else {
                            $currentQtyAvail[$compId] = $currentQtyAvail[$compId] - ($compval['QUANTITYPERKIT']*$possibleUnits);
                        }
                    }
                } else {
                    if ( $compval['QUANTITYAVAILABLE'] < ($compval['QUANTITYPERKIT']*$possibleUnits) ) {
                        $currentQtyAvail[$compId] = 0;
                    } else {
                        $currentQtyAvail[$compId] = $compval['QUANTITYAVAILABLE'] - ($compval['QUANTITYPERKIT']*$possibleUnits);
                    }
                }
            }             
        }
    }

    /**
     * @param float|int                     $whseqty
     * @param array                         $compsArr
     * @param StockableKitItemDataObject    $stKit
     * @param int                           $parentIndex
     * @param array                         $currentQtyAvail
     *
     * @return float|int
     */
    function calculatePossibleQty(&$whseqty,&$compsArr,$stKit,$parentIndex, &$currentQtyAvail)
    {
        $numdec=$this->_numdec;
        $comps=$stKit->getComponents();

        foreach($comps as $compId => $compObj) {
            $compIndex=$stKit->getArrayIndex($compId);
            $compval=&$compsArr[$compIndex];
            if ( ($compval['ITEMTYPE'] == STOCKABLE_KIT) || ($compval['ITEMTYPE'] == REGULAR_KIT) ) {
                $compval['POSSIBLE_UNITS'] = ibcdiv($this->calculatePossibleQty( $whseqty, $compsArr, $compObj,  $compIndex, $currentQtyAvail), '1', $numdec);
                $this->updateCurrentQtyAvailable($compsArr, $compObj, $currentQtyAvail, $compval['POSSIBLE_UNITS']);
            }
        }
        $comps = $stKit->getComponents();

        foreach( $comps as $compId => $compObj) {
            $compIndex=$stKit->getArrayIndex($compId);
            $compval=&$compsArr[$compIndex];
            $compval['PARENT_INDEX']=$parentIndex;
            $compval['QUANTITY']=ibcmul($compval['QUANTITY'], '1', $numdec);
            $compval['QUANTITYPERKIT']=ibcmul($compval['QUANTITYPERKIT'], '1', $numdec);
            if ($compval['QUANTITY']>0) {
                $qtyavail=$compval['QUANTITYAVAILABLE'];
                if (!isset($qtyavail)) {
                    $qtyavail = 0;
                }
                $compval['QTYAVAIL'] = $qtyavail;
                if ( ($compval['ITEMTYPE'] == STOCKABLE_KIT) || ($compval['ITEMTYPE'] == REGULAR_KIT) ) {
                    $possibleUnitsOfParentKitWithCompInventory=$compval['POSSIBLE_UNITS'];
                } else if ($compval['ITEMTYPE'] == INVENTORY_ITEM) {
                    if ( isset($currentQtyAvail[$compId]) ) {
                        if ($currentQtyAvail[$compId] > 0) {
                            $compval['POSSIBLE_UNITS'] = ibcadd($currentQtyAvail[$compId], '0', $numdec);
                            $possibleUnitsOfParentKitWithCompInventory=ibcdiv($compval['POSSIBLE_UNITS'], $compval['QUANTITYPERKIT'], $numdec);
                            $compval['POSSIBLE_UNITS'] = ibcdiv($compval['POSSIBLE_UNITS'], $compval['QUANTITYPERKIT'], $numdec);
                        } else {
                            $compval['POSSIBLE_UNITS'] = ibcadd('0', '0', $numdec);
                            $possibleUnitsOfParentKitWithCompInventory = $compval['POSSIBLE_UNITS'];
                        }
                    } else {
                        if ($compval['QTYAVAIL'] > 0) {
                            $compval['POSSIBLE_UNITS'] = ibcadd($compval['QTYAVAIL'], '0', $numdec);
                        } else {
                            $compval['POSSIBLE_UNITS'] = ibcadd('0', '0', $numdec);
                        }
                        $possibleUnitsOfParentKitWithCompInventory = ibcdiv($compval['POSSIBLE_UNITS'], $compval['QUANTITYPERKIT'], $numdec);
                        $compval['POSSIBLE_UNITS'] = ibcdiv($compval['POSSIBLE_UNITS'], $compval['QUANTITYPERKIT'], $numdec);
                    }
                }

                if (isset($minval)) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $minval=min($minval, $possibleUnitsOfParentKitWithCompInventory);
                } else {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $minval=$possibleUnitsOfParentKitWithCompInventory;
                }
            }
            $compval['MAXQTY_CHILD'] = 'yes';
            $compval['QUANTITY'] = ibcmul($compval['QUANTITY'], '1', $numdec);
        }
    
        if (!isset($minval)) {
            $minval=0;
        }
        return $minval;
    }

    /**
     * @param array $warehouse
     */
    function cleanUpObjects(&$warehouse) 
    {
        foreach( $warehouse as $k => $v){
            foreach( $warehouse[$k]['KIT'] as &$kitval){
                unset($kitval['OBJECT']);
            }
        }
    }
    
    
    /**
     * @return string
     */
    function GetFirstStageXSLFile() 
    {
        if ( isset($this->params['type']) && $this->params['type']=='_pdf' ) {
            return $this->_report . '_stdxml_pdf.xsl';
            //} else if ( isset($this->params['type']) && ( ($this->params['type']=='_excel') || ($this->params['type']=='_csv') ) ) {
            //	return $this->_report . '_stdxml_excel.xsl';
        } else {
            return $this->_report . '_stdxml.xsl';
        }

    }

    
}

