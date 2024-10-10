<?php

/**
 * Picker item for Supplies Inventory screens
 *
 * @author    Roger
 * @copyright 2023 Intacct Corporation, All Rights Reserved
 */



/**
 * Class SupplypickPicker
 */
class SupplypickPicker extends ItempickPicker
{
    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
        $this->onlySupplies      = true;    // true means ONLY show supply items
        $this->includeSupplies   = true;    // true means include supply items (redundant here, but clearer)
    }
}
