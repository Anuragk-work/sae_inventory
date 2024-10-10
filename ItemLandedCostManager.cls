<?php

/**
 * Manager class for item landed cost object
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class ItemLandedCostManager
 */
class ItemLandedCostManager extends OwnedObjectManager
{

    const LANDEDCOSTMETHODS = array('Count', 'Value', 'Volume', 'Weight');
    
    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * Validate the data entered
     * Function to override validateRecordForAdd
     *
     * @param array $values the data
     *
     * @return false if error else true
     */
    protected function validateRecordForAdd($values)
    {
        $ok = $this->validateInput($values);
        // If the Landed Cost Value is valid
        if ($ok) {
            $ok = parent::validateRecordForAdd($values);
        }
        return $ok;
    }


    /**
     * Validate the data entered
     * Function to override validateRecordForUpdate
     *
     * @param array $values the data
     *
     * @return false if error else true
     */
    protected function validateRecordForUpdate($values)
    {
        $ok = $this->validateInput($values);
        // If the Landed Cost Value is valid
        if ($ok) {
            $ok = parent::validateRecordForUpdate($values);
        }

        return $ok;
    }

    /**
     * API Add overwritten to check
     * Validate Input on ADD
     *
     * @param array &$values the data
     *
     * @return false if error else true
     */
    function API_Add(&$values)
    {
        $ok = $this->validateInput($values);
        // If the Landed Cost Value is valid
        if ($ok) {
            $ok = parent::API_Add($values);
        }

        return $ok;
    }

    /**
     * API Add overwritten to check
     * Validate Input on SET
     *
     * @param array &$values the data
     *
     * @return false if error else true
     */
    function API_Set(&$values)
    {
        $ok = $this->validateInput($values);
        // If the Landed Cost Value is valid
        if ($ok) {
            $ok = parent::API_Set($values);
        }

        return $ok;
    }

    /**
     * Validate the data entered to check if
     * landed cost value is empty when Active
     * is checked.
     * @param array $values the data
     *
     * @return false if error else true
     */
    private function validateInput(array $values): bool
    {
        $ok   = true;
        $gErr = Globals::$g->gErr;
        if ( $values['ACTIVE'] != "false" && ($values['VALUE'] == '' || (float) $values['VALUE'] < 0)) {
            $gErr->addIAError('INV-0170', __FILE__ . ':' . __LINE__, "Enter a positive number in the Value field.", []);
            $ok = false;
        }
        return $ok;
    }

}
