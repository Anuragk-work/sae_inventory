<?php

/**
 * Manager for landed cost history object
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class LandedCostHistory
 */
class LandedCostHistoryManager extends SCMMacroResolveManager
{
    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }
    
}