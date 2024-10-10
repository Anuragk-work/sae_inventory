<?php

/**
 * Manager class for Item Group
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Manager class for Item Group
 */

/**
 * Class ItemGroupManager
 */
class ItemGroupManager extends DimensionGroupManager
{

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * to set the dimension name (vendor, customer, etc)
     */
    protected function setDimensionEntity()
    {
        $this->dimEntity = 'item';
    }

    /**
     * to set the name of the dimension ID (VENDORID, CUSTOMERID, etc)
     */
    protected function setDimensionEntityID()
    {
        $this->dimEntityID = 'ITEMID';
    }

    /**
     * to set the dimension's DB field (VENDORKEY, CUSTOMERID, etc)
     */
    protected function setDimensionEntityKey()
    {
        $this->dimEntityKey = 'ITEMKEY';
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "ItemGroupManager::Add";
        $uiValues = $values;

        $this->setDefaultValues($values);

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->TranslateValues($values);
        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if ( !HasWarnings() || HasErrors() ) {
                $msg = "Could not create Item Group record!";
                $gErr->addIAError('INV-0733', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
            }

            $this->_QM->rollbackTrx($source);
        }

        $recordNo= $values['RECORDNO'];
        // assigning back $uiValues as MEMBERFILTERS are converted to jason array
        $values = $uiValues;
        //add the new record no back to the array
        $values['RECORDNO'] =$recordNo;

        return $ok;
    }

    /**
     * @param $values
     *  Set the default values for the API add
     * @return void
     */
    private function setDefaultValues(&$values)
    {
        // Add default as per the group type
        if ($values['GROUPTYPE'] == 'ALL') {
            $values['SORTFIELD'] =  $values['SORTFIELD'] ?? $this->dimEntityID;
            $values['SORTORDER'] = $values['SORTORDER'] ?? 'ASC';
        }
    }

    /**
     * @param string        $ID
     * @param null|array    $fields
     *
     * @return array
     */
    function Get($ID, $fields=null)
    {
        $obj = parent::Get($ID);
        $obj['MEMBERFILTERS'] = $obj['MEMBERFILTERS'] ?? [];
        $obj['CONDITIONTYPE'] = $obj['CONDITIONTYPE'] ?? 'AND';
        $obj['CONDITION'] = $obj['CONDITION'] ?? '';
        $obj['CREATEDIMCOMP'] = isset($obj['DIMGRPCOMP']);
        return $obj;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "ItemGroupManager::Set";
        $uiValues = $values;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->TranslateValues($values);
        
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if ( !HasWarnings() || HasErrors() ) {
                $msg = "Could not update Item Group record!";
                $gErr->addIAError('INV-0734', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
            }

            $this->_QM->rollbackTrx($source);
        }
        // assigning back $uiValues as MEMBERFILTERS are converted to jason array
        $values = $uiValues;

        return $ok;
    }

}