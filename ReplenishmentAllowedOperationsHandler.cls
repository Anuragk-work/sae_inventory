<?php
/**
 * AllowedOperationsHandler
 *
 * @author    Ravindra Kumar
 * @copyright Copyright (C)2024 Sage Intacct Corporation, All Rights Reserved
 *
 */

class ReplenishmentAllowedOperationsHandler extends AllowedOperationsHandler
{
    /**
     * @inheritDoc
     */
    public function __construct(EntityManager $entManager)
    {
        parent::__construct($entManager);
    }

    /**
     * Return menu entry for the object
     * for example, 'lists', 'setup', 'activities'...
     * and the security keys can be: inv/activities/replenishment
     *
     * @return string
     */
    protected function getMenuEntry() : string
    {
        return AllowedOperations::ENTRY_ACTIVITIES;
    }
}