<?

/**
 * Class upcpickPicker
 */
class upcpickPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'itempick',
            'pickfield'        =>  'UPC',
            'fields'        =>  array('UPC', 'PRODUCTLINEID', 'STATUS'),
            'sortcolumn'    => 'UPC',
            )
        );
        $this->addLabelMapping("UPC","IA.UPC",true);
    }

    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @param bool $addYuiCss include the YUI css files
     */
    public function showScripts($addYuiCss = true)
    {
        $_refresh = Request::$r->_refresh;
        parent::showScripts($addYuiCss);
        UIUtils::PrintLayerSetupForBrowser();
        UIUtils::PrintSetField($_refresh);
    }

    /**
     * BuildTable
     */
    public function BuildTable()
    {

        parent::BuildTable();

        $flds = array( 'UPC', 'PRODUCTLINEID', 'STATUS');
        $fldlabels = array( 'IA.UPC', 'IA.PRODUCT_LINE_ID', 'IA.STATUS');

        $this->_params['_fields'] = $flds;
        $this->_params['_fieldlabels'] = $fldlabels;
        
    }

    /**
     * @return array
     */
    public function BuildQuerySpecAll()
    {
        $qspec = parent::BuildQuerySpecAll();

        $this->AddFilters($qspec);

        return $qspec;
    }

    /**
     * @return array
     */
    public function BuildQuerySpec()
    {
        $ret = parent::BuildQuerySpec();
        
        $this->AddFilters($ret);

        return $ret;
    }

    /**
     * @param array $qrySpec
     *
     * @return array
     */
    public function AddFilters(&$qrySpec)
    {
        global $kINVid;

        $mod = Request::$r->_mod;
        
        GetModulePreferences($kINVid, $prefs);
        //$itemMgr = $gManagerFactory->GetManager('item');
        //$allowKit = $itemMgr->Enablekitting();
        //$allowLightAssembly = $itemMgr->EnableLightAssembly();

        if ( $mod == 'po' ) {
            // Non Inventory Sales only items are not allowed
            $qrySpec['filters'][0][] = array('itempick.itemtype', '<>', 'NS');
        } elseif( $mod == 'so' ) {
            // Non Inventory Purchase only items are not allowed
            $qrySpec['filters'][0][] = array('itempick.itemtype', '<>', 'NP');            
        } elseif( $mod == 'inv' ) {
            // only Inventory Items are allowed
            //$qrySpec['filters'][0][] = array('itempick.itemtype', '=', 'I' );		
        }
        
        // if kit is not enabled
        if (!IsKitEnabled()) {
            $qrySpec['filters'][0][] = array('itempick.itemtype', '<>', 'K' );
        }
        // if kit is not enabled
        if ($prefs['LIGHTASSEMBLY']!='T') {
            $qrySpec['filters'][0][] = array('itempick.itemtype', '<>', 'SK' );
        }

        // donot pick the items which have UPC value as null
        $qrySpec['filters'][0][] = array('itempick.upc', 'is not null', '' );

        return $qrySpec;
    }

    /**
     * @return string
     */
    public function genGlobs()
    {
        $mod = Request::$r->_mod;
        $ret = parent::genGlobs();
        $ret .= "<g name='.mod'>" . $mod . "</g>";

        return $ret;
    }
}

