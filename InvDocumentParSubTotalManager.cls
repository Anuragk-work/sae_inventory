<?
/**
 * No special behavior for Purchasing Order TD. But the framework needs a class
 * named InvDocumentParSubTotalManager to behave correctly.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */

class InvDocumentParSubTotalManager extends DocumentParSubTotalManager
{
    /**
     * @param array $params
     */
    public function __construct($params=array())
    {
        $invDoc =  Globals::$g->gManagerFactory->getManager('invdocument');
        $invSubTot = $invDoc->getSubtotalsInstance();

        $this->_overrideDimensionsFromSubtotals = $invSubTot->_overrideDimensionsFromSubtotals;
        $this->_overrideLocDeptAtTopLevel = $invSubTot->_overrideLocDeptAtTopLevel;

        parent::__construct($params);
    }
}