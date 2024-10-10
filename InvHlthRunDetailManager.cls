<?php
/**
 * Manager file for the standard object InvHlthRunDetail
 *
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * @category  Cls
 * @package   Source/common
 * @author    rpn <ravi@intacct.com>
 * @copyright 2000-2009 Intacct Corporation, All Rights Reserved
 */
class InvHlthRunDetailManager extends OwnedObjectManager
{

    /**
     * Overridden function to support IMS events
     *
     * @param string $verb Action of the entity
     * @param string $key  VID of the object
     * @param array  $param1
     * @param array  $param2
     * @param array  $values
     *
     * @param bool   $fastUpdate
     *
     * @return bool
     */
    function doEvent($verb, $key, $param1 = null, $param2 = null, $values = [], $fastUpdate = false)
    {
        // so far no event support yet...
        return true;
    }
}
