<?
require_once 'Dictionary.cls';

/**
 * Class ItemsonlyPickPicker
 */
class ItemsonlyPickPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'itempick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID', 'PRODUCTLINEID', 'STATUS'),
            'sortcolumn'    => 'ITEMID',
            )
        );
    }

    /**
     * @return array
     */
    function BuildQuerySpecAll() 
    {
        $qspec = parent::BuildQuerySpecAll();
        
        $vendorid = Request::$r->_vendorid;

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

        $mod = Request::$r->_mod;

        if ( $mod == 'inv' ) {
            $qrySpec['filters'][0][] = array('itempick.itemtype', "IN ('I', 'SK')", '');
        }
        if ( $mod == 'po' ) {
            // Non Inventory Sales only & Kit items are not allowed
            $qrySpec['filters'][0][] = array('itempick.itemtype', "IN ('I', 'NI', 'NP')", '' );
        }
    }


    /**
     * @return string
     */
    function genGlobs()    
    {
        $vendorid = Request::$r->_vendorid;
        $ret = parent::genGlobs();
        $ret .= "<g name='.vendorid'>" . $vendorid . "</g>";
        return $ret;
    }


}
