<?

/**
 * Manager class for Warehouse Picker
 *
 * @author    Viveksuriyan Subramani <vsubramani@intacct.com>
 * @copyright 2018 Sage Intacct Inc., All Rights Reserved
 *
 * This document contains trade secret data that belongs to Intacct Corporation and is protected by the copyright laws.
 * Information herein may not be used, copied or disclosed in whole or in part without prior written consent from
 * Intacct Corporation.
 *
 */

/**
 * Class WarehouseLocationPickManager
 */
class WarehouseLocationPickManager extends HierarchicalEntityManager
{
    /**
     * @return string
     */
    function GetPlatformContextPickId()
    {
        return "A.WAREHOUSEID || '--' || A.NAME";
    }

    /**
     * PickID clause
     *
     * @return string
     */
    function GetPlatformContextPickIdSql()
    {
        return $this->GetPlatformContextPickId();
    }

    /**
     * Table to join for platform_visiblity
     *
     * @return string
     */
    function GetPlatformContextJoinTable()
    {
        return "ICWAREHOUSE";
    }
}