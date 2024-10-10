<?

/**
 * Class ItemsAllPickPicker
 */
class ItemsAllPickPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'itemsallpick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID', 'PRODUCTLINEID', 'STATUS'),
            'sortcolumn'    => 'ITEMID',
            )
        );
    }

    /**
     * @param bool $addYuiCss
     */
    function showScripts($addYuiCss = true)
    {
        $_refresh = Request::$r->_refresh;
        parent::showScripts($addYuiCss);
        UIUtils::PrintLayerSetupForBrowser();
        UIUtils::PrintSetField($_refresh);
    }

    /**
     * @return array
     */
    function BuildQuerySpecAll() 
    {
        $qspec = parent::BuildQuerySpecAll();

        $this->AddFilters($qspec);

        return $qspec;
    }


    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        $ret = parent::BuildQuerySpec();
        
        $this->AddFilters($ret);
        return $ret;
    }


    /**
     * @param array $qrySpec
     */
    function AddFilters(&$qrySpec) 
    {
        global $kINVid;

        $mod = Request::$r->_mod;
        
        GetModulePreferences($kINVid, $prefs);
        //$itemMgr = $gManagerFactory->GetManager('item');
        //$allowKit = $itemMgr->Enablekitting();
        //$allowLightAssembly = $itemMgr->EnableLightAssembly();

        if ( $mod == 'po' ) {
            // Non Inventory Sales only & Kit items are not allowed
            if ($prefs['LIGHTASSEMBLY'] === 'T') {
                $qrySpec['filters'][0][] = array('itemsallpick.itemtype', 'IN', array('I', 'NI', 'NP', 'SK' ));
            } else {
                $qrySpec['filters'][0][] = array('itemsallpick.itemtype', 'IN', array('I', 'NI', 'NP' ));
            }
            
        } elseif( $mod == 'so' ) {
            // Non Inventory Purchase only items are not allowed
            $qrySpec['filters'][0][] = array('itemsallpick.itemtype', '<>', 'NP');    
        }
        //To filter serivice types in T&B and to have only items in the Report
        $qrySpec['filters'][0][] = array('itemsallpick.itemtype', '<>', 'PS' );    

        // if Kit is not enabled
        if (!IsKitEnabled()) {
            $qrySpec['filters'][0][] = array('itemsallpick.itemtype', '<>', 'K' );
        }
        // if Kit is not enabled
        if ($prefs['LIGHTASSEMBLY'] != 'T') {
            $qrySpec['filters'][0][] = array('itemsallpick.itemtype', '<>', 'SK' );
        }
    }

    /**
     * @return string
     */
    function genGlobs() 
    {
        $ret = parent::genGlobs();
        if ( Request::$r->_mod == "cerp" ) {
            // for custom reports -> items filter selection, propagate the module param as a hidden input field
            $ret .= "<g name='.mod'>cerp</g>";
        }
        return $ret;
    }

}

