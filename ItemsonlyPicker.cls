<?
require_once 'Dictionary.cls';

/**
 * Class ItemsonlyPicker
 */
class ItemsonlyPicker extends NPicker
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
            'fieldlabels'   => ($displayStockNumber) ? array('Item',$dict->GetRenamedText(_('Vendor Stock #')),'Name', 'Product Line ID') : array('Item','Name', 'Product Line ID'),
            'fields'        =>  ($displayStockNumber) ? array('ITEMID', 'itemvendor.stock_number','NAME', 'PRODUCTLINEID') : array('ITEMID','NAME', 'PRODUCTLINEID'),
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

        return $ret;

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
