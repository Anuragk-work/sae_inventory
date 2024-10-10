<?
require_once 'Dictionary.cls';

/**
 * Class StkitPicker
 */
class StkitPicker extends NPicker
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

}
