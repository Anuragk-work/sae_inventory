<?php

/**
 * Manager class for scm macro entry object
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class SCMMacroEntryManager
 */
class SCMMacroEntryManager extends OwnedObjectManager
{

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }

}
