<?
require_once 'Dictionary.cls';

/**
 * Class ItemPicker
 */
class ItemPicker extends NPicker
{

    function __construct()
    {
        $mod = Request::$r->_mod;
        $vendorid = Request::$r->_vendorid;

        $dict = Dictionary::getInstance();

        $displayStockNumber = $mod == 'po' && isset($vendorid) && $vendorid != '';

        parent::__construct(
            array(
            'entity'        =>  'item',
            'fieldlabels'   => ($displayStockNumber) ? array('Item',$dict->GetRenamedText(_('Vendor Stock #')),'Name', 'Product Line ID', 'Item Type') : array('Item','Name', 'Product Line ID', 'Item Type'),
            'fields'        =>  ($displayStockNumber) ? array('ITEMID', 'itemvendor.stock_number','NAME', 'PRODUCTLINEID', 'ITEMTYPE') : array('ITEMID','NAME', 'PRODUCTLINEID', 'ITEMTYPE'),
            'pickfield'        =>  'ITEMID',
            'helpfile'        => 'Locations_Lister' // NOT SURE ABOUT THIS ONE
            )
        );
    }

    /**
     * @return array
     */
    function BuildQuerySpecAll() 
    {
        $vendorid = Request::$r->_vendorid;
        $qspec = parent::BuildQuerySpecAll();

        if (isset($vendorid) && $vendorid != '') {
            $qspec['filters'][0][] = array('itemvendor.vendorid', 'OUTER', $vendorid);
        }

        $this->AddFilters($qspec);

        return $qspec;

    }


    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        $ret = parent::BuildQuerySpec();
        $vendorid = Request::$r->_vendorid;
        if (isset($vendorid) && $vendorid != '') {
            $ret['filters'][0][] = array('itemvendor.vendorid', 'OUTER', $vendorid);
        }
        
        $this->AddFilters($ret);

        return $ret;
    }


    /**
     * @param array $qrySpec
     */
    function AddFilters(&$qrySpec) 
    {
        global $kINVid;

        if($this->vsoepricelist || Request::$r->_vsoepricelist == 1) {
            $qrySpec['filters'][0][] = array('item.revposting', " NOT IN ('I') ", "" );

            //filter out only items of SVR/PCS category type.
            $valueType = Request::$r->_obj__VALUEBASE;
            if($valueType == 'Percent') {
                $qrySpec['filters'][0][] = array('item.vsoecategory', "IN ('SVR', 'PCS')", '' ); 
            }        
        }
        
        $mod = Request::$r->_mod;
        $it = Request::$r->_it;

        // this is set when coming here from the picker on item components tab
        $itemType= Request::$r->_itemType;

        GetModulePreferences($kINVid, $prefs);
        //$itemMgr = $gManagerFactory->GetManager('item');
        //$allowKit = $itemMgr->Enablekitting();
        //$allowLightAssembly = $itemMgr->EnableLightAssembly();

        $itemId = Request::$r->_itemId;
        if (!isset($itemType) || $itemType==='') {
            $itemType= Request::$r->_obj__ITEMTYPE;
        }
        if (!isset($itemId) || $itemId==='') {
            $itemId= Request::$r->_obj__ITEMID;
        }
        
        $companyid=GetMyCompany();
        
        if ($itemType == 'Kit') {
            $qrySpec['filters'][0][] = array('item.itemtype', " NOT IN ('NP') ", "" );
        }
        if ($itemType == 'Stockable Kit') {
            $qrySpec['filters'][0][] = array('item.itemtype', " NOT IN ('NP') ", "" );
            /* 
            * For duplicate (copy) action, the copy does not have any itemid assigned yet - so itemid comes as ''
            * In that case, we cannot constrain the item lister popup values list, so skip these filters
            */
            if ($mod == 'inv' && $it=='item' && $itemId!='') {
                // for stockable kits itemeditor, do not allow circular references
                // 1. do not allow picking same item as component of itself
                $qrySpec['filters'][0][] = array('item.itemid', " != ", $itemId );
                // 2. do not allow picking parents as components
                $qrySpec['filters'][0][] = array('item.itemid', "NOT IN ( SELECT ic.ITEMKEY
																		  from icitemcomponent ic, icitem it
																		  WHERE	IT.CNY#=IC.CNY# 
																		    AND IC.COMPONENTKEY = IT.ITEMID 
																		    AND IT.CNY# = ".$companyid." 
																		    AND IT.STATUS = 'T' 
																		  START WITH IC.COMPONENTKEY= '".$itemId."'
																		          AND IC.CNY# = ".$companyid." 
																		CONNECT BY IC.COMPONENTKEY = PRIOR IC.ITEMKEY
																		          and ic.cny# = ".$companyid." )" );
            }
        } else
        if ( $mod == 'po' ) {
            // Kits & Non Inventory Sales only items are not allowed
            $qrySpec['filters'][0][] = array('item.itemtype', " IN ('I', 'NI', 'NP')", '' );

            //			if (($it!='item' || ($it=='item' && $do=='list')) && $allowKit!='T' ) {
            //					$qrySpec['filters'][0][] = array('item.itemtype', '<>', 'K' );
            //			}

        } elseif( $mod == 'so' ) {
            // only Non Inventory items of type Purchase Only are not allowed
            $qrySpec['filters'][0][] = array('item.itemtype', '<>', 'NP');
            
            // if kit is not enabled 
            if (!IsKitEnabled()) {
                $qrySpec['filters'][0][] = array('item.itemtype', '<>', 'K' );
            }

            // if stockable kit is not enabled 
            if ($prefs['LIGHTASSEMBLY'] != 'T') {
                $qrySpec['filters'][0][] = array('item.itemtype', '<>', 'SK' );
            }

        } elseif( $mod == 'inv' ) {
            // only Inventory and kit items are allowed
            $qrySpec['filters'][0][] = array('item.itemtype', "IN ('I', 'K', 'SK')", '' );
        }

        //if request coming from SFDC check for Pricing Option 
        if (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '' &&  $mod == 'so') {

            include_once 'SforceSynchronizer.cls';
            $sfSynchronizer = new SforceSynchronizer();

            if ($sfSynchronizer->_preferences['SFORCEPRICINGOPT'] == SFORCEPRICING && $sfSynchronizer->ShowOppLineItems()) {
                $Items = $sfSynchronizer->GetOppProdCodes();
                //get only SFDC synced line items which are available for that Opportunity
                if($Items) {
                    if(count($Items) > kINClauseLimit ) {
                        $entitytype = 'item';
                        DumpRecsToTempTable($Items, $tablename, $entitytype);
                        $itemFilter = array("select ENTITYNO from $tablename where entitytype = '$entitytype'");
                    } else {
                        $itemFilter = $Items; 
                    }
                    $qrySpec['filters'][0][] = array('item.itemid', "IN", $itemFilter);            
                }
            }
        }
    }


    /**
     * @return string
     */
    function genGlobs()    
    {
        $vendorid = Request::$r->_vendorid;
        $isKit    =  Request::$r->_isKit;
        $isSTKit  =  Request::$r->_isSTKit;
        $itemType = Request::$r->_itemType;
        $itemId   = Request::$r->_itemId;
        $ret      = parent::genGlobs();
        $ret     .= "<g name='.vendorid'>" . $vendorid . "</g>";
        $ret     .= "<g name='.isKit'>" . $isKit . "</g>";
        $ret     .= "<g name='.isSTKit'>" . $isSTKit . "</g>";
        $ret     .= "<g name='.itemType'>" . $itemType . "</g>";
        // Passing itemId here so that picker can constrain the display list appropriately for all pages 
        $ret     .= "<g name='.itemId'>" . $itemId . "</g>";
        return $ret;
    }


}
