<?php

/**
 * Manager class for Warehouse Group
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class WarehouseGroupManager
 */
class WarehouseGroupManager extends DimensionGroupManager
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
        $this->dimEntity = 'warehouse';
    }

    /**
     * to set the name of the dimension ID (VENDORID, CUSTOMERID, etc)
     */
    protected function setDimensionEntityID()
    {
        $this->dimEntityID = 'WAREHOUSEID';
    }

    /**
     * to set the dimension's DB field (VENDORKEY, CUSTOMERID, etc)
     */
    protected function setDimensionEntityKey()
    {
        $this->dimEntityKey = 'WAREHOUSEKEY';
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "WarehouseGroupManager::Add";
        $uiValues = $values;

        $this->setDefaultValues($values);

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->TranslateValues($values);
        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if ( !HasWarnings() || HasErrors() ) {
                $msg = "Could not create Warehouse Group record!";
                $gErr->addError('INV-0942', __FILE__ . ':' . __LINE__, $msg);
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
     *  Add default values for the API
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
        $source = "WarehouseGroupManager::Set";
        $uiValues = $values;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->TranslateValues($values);
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if ( !HasWarnings() || HasErrors() ) {
                $msg = "Could not update Warehouse Group record!";
                $gErr->addError('INV-0941', __FILE__ . ':' . __LINE__, $msg);
                epp("$source: Error: $msg");
            }

            $this->_QM->rollbackTrx($source);
        }

        // assigning back $uiValues as MEMBERFILTERS are converted to jason array
        $values = $uiValues;

        return $ok;
    }

}
