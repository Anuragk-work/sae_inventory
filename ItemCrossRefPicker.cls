<?

class ItemCrossRefPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
                'entity' => 'itemcrossref',
                'fields' => array('RECORDNO', 'REFTYPE', 'ITEMALIASID', 'ITEMID', 'CUSTOMERID', 'VENDORID', 'UNIT'),
                'pickfield' => array('ITEMALIASID', 'REFTYPE', 'RECORDNO', 'ITEMID', 'CUSTOMERID', 'VENDORID', 'UNIT'),
                'helpfile' => '', // NOT SURE ABOUT THIS ONE
                'sortcolumn' => 'ITEMID, ITEMALIASID',
            )
        );
    }

    /**
     * @param int $i
     * @param string $refr
     *
     * @return string
     */
    function calcSelectUrl($i, $refr = "")
    {
        $p = &$this->_params;
        $t = &$this->table;

        $text = $p['_selectbutton'];

        if ($refr) {
            $refr = '1';
        }

        //  Properly encode to JS-ready (e.g. UTF-8 chars).
        $pick = isl_str_to_js($t[$i]['ITEMALIASID']);
        $ret = "<a id=\"select\" href=\"javascript:SetField('" . $pick . "', '', '$refr')\" >" . $text . "</a>";

        return $ret;
    }

    /**
     * @return string
     */
    function genGlobs()
    {
        $ret = parent::genGlobs();
        return $ret;
    }
}
