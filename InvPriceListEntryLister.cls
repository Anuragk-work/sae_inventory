<?

/**
 *    FILE: InvPriceListEntryLister.cls
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


import('NLister');

class InvPriceListEntryLister extends NLister
{
    /**
     * @var string[]
     */
    protected $additionalTokens = [
        'IA.PRICE_LIST_ENTRIES_FOR',
    ];
    /** @var bool $isOwnedObj */
    var $isOwnedObj = true;

    /** @var string $ownerKey */
    var $ownerKey = "";

    /** @var string $ownerID */
    var $ownerID = "";

    /** @var bool $_ismcpEnabled */
    var $_ismcpEnabled=false;

    /** @var string $_basecurrency */
    var $_basecurrency='';

    /** @var string $mod */
    var $mod = 'inv';


    function __construct()
    {
        global $gManagerFactory;

        // get the preference for MCP
        $this->_ismcpEnabled = IsMCPEnabled($this->mod);
        $this->_basecurrency = GetBaseCurrency();

        $plid = urldecode(Request::$r->_plid);
        $d1   = Request::$r->_d1;
        $d2   = Request::$r->_d2;

        //$priceListMgr = $gManagerFactory->GetManager('InvPriceList');
        //$this->isOwnedObj = $priceListMgr->IsOwned($plid, true);

        $invpricelistMgr = $gManagerFactory->getManager($this->mod . 'pricelist');
        $res = $invpricelistMgr->GetRaw($plid);

        $this->isOwnedObj = $invpricelistMgr->IsOwned($plid, false);

        $multientityfilters = $invpricelistMgr->GetMultiEntityFilterFields();

        if( isset($multientityfilters) ) {
            foreach ($multientityfilters as $idx) {
                $this->ownerKey = $res[isl_strtoupper($idx)];
            }
        }

        if ( $this->ownerKey ) {
            $locEntityMgr = $gManagerFactory->getManager('locationentity');
            /** @noinspection PhpUndefinedVariableInspection */
            $this->ownerID = $locEntityMgr->GetRaw($ownerKey);
            /** @noinspection PhpUndefinedVariableInspection */
            $this->ownerID = $ownerID[0]['LOCATION_NO'];
        }

        $listURL = isl_htmlspecialchars(
            ExtendUrl('lister.phtml', '.plid='.urlencode($plid)).'&.d1='.$d1.'&.d2='.$d2
        );


        // we have to do the following to seperate out not owned priclist entries from list by joining the item table
        if ( IsMultiEntityCompany() && GetContextLocation() ) {
            $flds = array('ITEMID', 'ITEMNAME', 'PRODUCTLINEID','DATEFROM','DATETO', 'EMPLOYEEID', 'VALUE','VALUETYPE','ITEM.ITEMID');
        } else {
            $flds = array('ITEMID', 'ITEMNAME', 'PRODUCTLINEID','DATEFROM','DATETO', 'EMPLOYEEID', 'VALUE','VALUETYPE');
        }

        if($this->_ismcpEnabled) {
            array_splice($flds, 4, 0, "CURRENCY");
        }

        parent::__construct(
            array (
            'entity'        =>  $this->mod.'pricelistentry',
            'fields'        =>  $flds,
            'title' =>  [
                'id' => 'IA.PRICE_LIST_ENTRIES_FOR',
                'placeHolders' => [
                                    [ 'name' => 'PRICELIST_ID', 'value' => $plid ]
                                ]
            ],
            'list'         => $listURL,
            'helpfile'  => 'Viewing_and_Managing_the_List_of_Price_List_Entries',
            'enablemultidelete' => true,
            )
        );
    }

    /**
     * @return string
     */
    function calcAddUrl() 
    {
        $p = &$this->_params; //???

        $text =  $p['_addbutton'];
        $dst = $this->calcAddDst();
        $tip = 'Add New Item';
        $do = 'create';
        $op =  $p['_op']['create'];

        $plid = urlencode(Request::$r->_plid);
        $d1 = urlencode(Request::$r->_d1);
        $d2 = urlencode(Request::$r->_d2);


        if ( !$this->isOwnedObj ) {
            return "";
        } else {

            $ret =     "<a href=\"" .
            $this->U($dst, ".do=$do&.op=$op&.plid=$plid&.d1=$d1&.d2=$d2&add=Add&_action=new", $this->LCALL) ."\" " .
            HREFUpdateStatus($tip) . ">" .
            $text .
            "</a>";

        }

        return $ret;
    }

    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        $_plid     = urldecode(Request::$r->_plid);
        $querySpec = parent::BuildQuerySpec();
        $querySpec['filters'][0][] = array('PRICELISTID', '=', $_plid);
        return($querySpec);
    }


    /**
     * @return string
     */
    function genGlobs()    
    {
        $plid = isl_htmlspecialchars(Request::$r->_plid);
        $d1   = Request::$r->_d1;
        $d2   = Request::$r->_d2;

        $ret = NLister::genGlobs();
        $ret .= "<g name='.plid'>"  . $plid. "</g>";
        $ret .= "<g name='.d1'>"    . $d1. "</g>";
        $ret .= "<g name='.d2'>"    . $d2. "</g>";
        return $ret;
    }


    /**
     *
     */
    function BuildTable() 
    {
        parent::BuildTable();
    
        $flds = $this->_params['_fields'];
        $fldnames = $this->_params['_fieldlabels'];

        foreach($this->table as $index => $row) {
            list( , $left) = explode('.', $this->table[$index]['VALUE']);
            if(isl_strlen($left) <= 2) {
                $this->table[$index]['VALUE'] =  glCurrency($row['VALUE']); 
            }else{
                $this->table[$index]['VALUE'] = ibcmul($row['VALUE'], '1', isl_strlen($left), true);
            }

            if($this->_ismcpEnabled) {
                if(!isset($this->table[$index]['CURRENCY'])) {
                    $this->table[$index]['CURRENCY'] = $this->_basecurrency;
                }
            }
        }

        // we have to do the following to seperate out not owned priclist entries from list by joining the item table
        if ( IsMultiEntityCompany() && GetContextLocation() ) {
            $flds = array('ITEMID', 'ITEMNAME', 'PRODUCTLINEID', 'DATEFROM', 'DATETO', 'VALUE', 'VALUETYPE');
            $fldnames = array('Item ID', 'Name', 'Product Line ID', 'Start Date', 'End Date', 'Value', ' Value Type');
            //$this->SetOutputFields($flds, $fldnames);

            if($this->_ismcpEnabled) {
                array_splice($flds, 4, 0, "CURRENCY");
                array_splice($fldnames, 4, 0, "Currency");
            }
        }

        if($this->_ismcpEnabled && in_array('CURRENCY', $flds)) {
            array_splice($fldnames, array_search('CURRENCY', $flds), 1, 'Currency');
        }
        $this->SetOutputFields($flds, $fldnames);
    }


    /**
     * @param int $i
     *
     * @return int
     */
    function GetObjectOwnership($i) 
    {
        return ( GetContextLocation() != '' && !$this->isOwnedObj ? -1 : 1 );
    }

    /**
     * @param int $i
     *
     * @return int
     */
    function GetObjectOwnerLocation($i) 
    {
        return ( $this->isOwnedObj ? 0 : -1 ); 
    }


}
