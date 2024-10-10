<?php

/**
 * Class ItempickPicker
 */
class ItempickPicker extends NPicker
{
     private   bool $isPlatformContext = false;
     protected bool $onlySupplies      = false;    // true means ONLY show supply items
     protected bool $includeSupplies   = false;    // true means include supply items
     protected bool $canFilterSupplies   = true;   // true means we will add a filter for supply items


    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        $nparams = array(
            'entity'        =>  'itempick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID', 'PRODUCTLINEID', 'STATUS'),
            'sortcolumn'    => 'ITEMID',
        );         
        
        if ( count($params) ) {
            $nparams = INTACCTarray_merge($nparams, $params);
            $this->addGrpFields($nparams);
        }        
        
        parent::__construct($nparams);
    }
    
    /**
     * add fields for group picker    
     * 
     * @param array $params picker param
     */
    protected function addGrpFields(&$params)
    {
        //override to add group fields
    }    

    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
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
     * @return string
     */
    function genGlobs()
    {
        $ret = parent::genGlobs();
        $ret .= "<g name='.mod'>" . Request::$r->_mod . "</g>";
        return $ret;
    }

    /**
     * @return array
     */
    function BuildQuerySpec() 
    {
        $this->isPlatformContext=  $this->_params['isPlatformContext'] ?? false;

        $ret = parent::BuildQuerySpec();
        
        $this->AddFilters($ret);

        return $ret;
    }

    /**
     * @param array $qrySpec
     *
     * @return mixed
     */
    function AddFilters(&$qrySpec) 
    {
        global $kINVid;

        $mod = Request::$r->_mod;
        
        GetModulePreferences($kINVid, $prefs);

        if ( $mod == 'po' ) {
            // Non Inventory Sales only items are not allowed
            $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'NS');

            if($this->isPlatformContext)
            {
                if(!IsKitEnabled()) {
                    $qrySpec['filters'][0][] = array( $this->_params['_entity'] . '.itemtype', '<>', 'K' );
                }
                if ($prefs['LIGHTASSEMBLY']!='T') {
                    $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'SK' );
                }
            }else{
                $qrySpec['filters'][0][] = array( $this->_params['_entity'] . '.itemtype', '<>', 'K' );
                $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'SK' );
            }

            if ($this->canFilterSupplies) {
                if ($this->onlySupplies) {
                    $qrySpec['filters'][0][] = array($this->_params['_entity'] . '.ISSUPPLYITEM', '=', 'T');
                } else if ($this->includeSupplies == false) {
                    $qrySpec['filters'][0][] = array(
                        'operator' => 'OR',
                        'filters' => array(
                            [$this->_params['_entity'] . '.ISSUPPLYITEM', 'is NULL'],
                            [$this->_params['_entity'] . '.ISSUPPLYITEM', '<>', 'T']
                        )
                    );
                }
            }
        } elseif( $mod == 'so' ) {
            // Non Inventory Purchase only items are not allowed
            $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'NP');        

            // if kit is not enabled
            if (!IsKitEnabled()) {
                $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'K' );
            }

            // if kit is not enabled
            if ($prefs['LIGHTASSEMBLY']!='T') {
                $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'SK' );
            }

            // supplies are not allowed in SO

        } elseif( $mod == 'inv' ) {
            // only Inventory Items are allowed
            $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', 'IN', array('I','NI','NS','NP','SK') );

            if ($this->canFilterSupplies) {
                if ($this->onlySupplies) {
                    $qrySpec['filters'][0][] = array($this->_params['_entity'] . '.ISSUPPLYITEM', '=', 'T');
                } else if ($this->includeSupplies == false) {
                    $qrySpec['filters'][0][] = array(
                        'operator' => 'OR',
                        'filters' => array(
                            [$this->_params['_entity'] . '.ISSUPPLYITEM', 'is NULL'],
                            [$this->_params['_entity'] . '.ISSUPPLYITEM', '<>', 'T']
                        )
                    );
                }
            }
        }

        //To filter serivice types in T&B and to have only items in the Report
        $qrySpec['filters'][0][] = array($this->_params['_entity'].'.itemtype', '<>', 'PS' );    

        return $qrySpec;
    }

}

