<?
import('editor');

/**
 * Class DocumententryTrackkitEditor
 */
class DocumententryTrackkitEditor extends Editor
{

    /**
     * @param array $_params
     *
     * @return array
     */
    function Buttons_Instantiate($_params)
    {
        return $_params;
    }


    /**
     * @param array $_field
     */
    function ShowSimpleFieldValue(&$_field)
    {
        global $kINVid;

        if ($_field['path'] == 'SLBINFO' && IsInstalled($kINVid)) {
            $_field['onclick'] = "javascript: if (this.disabled) return false; SLBInfoClick('" . $_field['layer'] . "','" . $_field['form'] . "','" . $_field['rownum'] . "');";
        }
        Editor::ShowSimpleFieldValue($_field);
    }


    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @param bool $addYuiCss
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);
        $_sess = Session::getKey();
        $op = Request::$r->_op;
        $docid = Request::$r->_docid;
        $parentid = Request::$r->_parentid;
        $docmode = Request::$r->_docmode;
        $date = Request::$r->_date;
        $whsekey = Request::$r->_whsekey;
        $in_out = Request::$r->_in_out;
        $itemlineno = Request::$r->_itemlineno;
        $isReturn = Request::$r->_isreturn;
        $isBackOrder = Request::$r->_isbackorder;
        $docparRecno = Request::$r->_docparRecno;
        ?>
        <SCRIPT language=javascript>

            var sess = escape('<?echo $_sess;?>');
            var op = '<?echo $op;?>';
            var newdocid = '<?echo $docid;?>';
            var parentid = '<?echo $parentid;?>';
            var docmode = '<?echo $docmode;?>';
            var date = '<?echo $date;?>';
            var whsekey = '<?echo $whsekey;?>';
            var in_out = '<?echo $in_out;?>';
            var itemlineno = '<?echo $itemlineno;?>';
            var docparRecno = '<? echo $docparRecno;?>';
            var isReturn = '<? echo $isReturn;?>';
            var isBackOrder = '<? echo $isBackOrder;?>';


            //function SLBInfoClick(_layer, _form, linenum)
            function SLBInfoClick(_layer, _form, linenum) {
                _form = (_form == null) ? 0 : _form;
                page = GetLayerDoc(_layer);

                op = <? echo GetOperationId('so/lists/documententrytrack/create'); ?>;
                itemId = page.forms[_form].elements['_obj__(' + linenum + ')__ITEMID'];
                quantity = page.forms[_form].elements['_obj__(' + linenum + ')__QUANTITY'];

                if (itemId.value == null || itemId.value == '') {
                    alert('Please select an Item first.');
                    return;
                }
                if (docmode == 'view') {
                    _do = 'view';
                } else {
                    _do = '';
                }

                url = 'editor.phtml?.sess=' + escape(sess) + '&.op=' + escape(op) + '&.inquantity=' + escape(quantity.value) + '&.initemid=' + escape(itemId.value) + '&.kitid=' + escape(itemId.value) + '&.popup=1&.itemtype=I&.docid=' + escape(newdocid) + '&.docmode=' + escape(docmode) + '&.do=' + escape(_do) + '&.date=' + escape(date) + '&.whsekey=' + escape(whsekey) + '&.in_out=' + escape(in_out) + '&.itemlineno=' + escape(itemlineno) + '&.docparRecno=' + escape(docparRecno) + '&.parentid=' + escape(parentid) + '&.isreturn=' + escape(isReturn) + '&.isbackorder=' + escape(isBackOrder) + '&.type=_html';

                Launch(url, 'mywindow', '900', '400');
            }

        </SCRIPT>

        <?

    }


    /* Walked through the code below, we are safe to remove this, right now commenting.

    function Editor_Instantiate(&$_params) {

    $source = "DocumententryTrackEditor::Editor_Instantiate";

    global $gRequest, $gManagerFactory, $gErr;
    parent::Editor_Instantiate($_params);

    $this->MatchTemplates($_params, array('path' => 'numofrows_top'), $itemfields);
    foreach ($itemfields as $i => $x) { 
    //$itemfields[$i]['value'] = $itemid;
    //$itemfields[$i]['readonly'] = 1;	
    }
    }
    */
    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessEditNewAction(&$_params)
    {
        global $gManagerFactory;

        Editor::ProcessEditNewAction($_params);

        $quantity = Request::$r->_inquantity;
        $kitid = Request::$r->_kitid;

        $itemMgr = $gManagerFactory->getManager('item');

        $item['ITEMID'] = $kitid;

        $KitItem = $itemMgr->CollectItemCostDetails($item, $quantity);

        foreach ( $KitItem as $key => $val) {
            $item = $itemMgr->GetRaw($KitItem[$key]['ITEMID']);
            if ($item[0]['ENABLELOT'] == 'T' || $item[0]['ENABLESNO'] == 'T' || $item[0]['ENABLEBIN'] == 'T' || $item[0]['ENABLEEXPIRATION'] == 'T') {
                $rec[''][$key]['ITEMID'] = $KitItem[$key]['ITEMID'];
                $rec[''][$key]['QUANTITY'] = bcmul($quantity, $KitItem[$key]['QUANTITY'], 0);
            }
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $rec1[''] = array_reverse($rec['']);
        Request::$r->SetCurrentObject($rec1);
        $this->state = $this->kShowNewState;
        return true;
    }

}