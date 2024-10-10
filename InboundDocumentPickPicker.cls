<?php
/**
 * picker for Inbound Documents
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

class InboundDocumentPickPicker extends NPicker {

    function __construct()
    {
        parent::__construct(
            array(
                'entity'        => 'document',
                'fields'        => array(
                    'DOCID', 'SALE_PUR_TRANS', 'PONUMBER', 'DOCPARID', 'WHENCREATED', 'CURRENCY', 'TOTAL'
                ),
                'pickfield'     => array('DOCID', 'SALE_PUR_TRANS', 'DOCPARID'),
                'title'         => 'IA.INBOUND_TRANSACTION',
                'sortcolumn'    => 'SALE_PUR_TRANS, WHENCREATED:d',
            )
        );
    }

    /**
     * @return array
     */
    function BuildQuerySpec()
    {
        $querySpec = parent::BuildQuerySpec();
        $querySpec['filters'][0][] = array('DOCPAR_IN_OUT', '=', "Increase");
        $querySpec['filters'][0][] = array('STATUS', '=', "active");

        return $querySpec;
    }

    /**
     * @return array
     */
    function BuildQuerySpecAll()
    {
        return $this->BuildQuerySpec();
    }

    /**
     * @param int    $i
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
        $pick = isl_str_to_js($t[$i]['DOCID']);
        $ret = "<a id=\"select\" href=\"javascript:SetField('" . $pick . "', '', '$refr')\" >"    . $text . "</a>";

        return $ret;
    }
}