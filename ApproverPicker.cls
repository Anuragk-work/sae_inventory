<?
class ApproverPicker extends Picker
{

    function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'approverpicker',
            'pickfield'        =>  'EMPLOYEEID',
            'fields'        =>  array('EMPLOYEEID', 'PERSONALINFO.CONTACTNAME'),
            )
        );
                             
    }

    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @bool $addYuiCss  include the YUI css files
     * @param bool $addYuiCss
     */
    function showScripts($addYuiCss = true)
    {
        $_refresh = Request::$r->_refresh;
        parent::showScripts($addYuiCss);
        UIUtils::PrintIncListerCSS();
        UIUtils::PrintLayerSetupForBrowser();
        UIUtils::PrintSetField($_refresh);
    }
}

