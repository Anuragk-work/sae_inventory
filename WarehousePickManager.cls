<?

/**
 * Manager class for Warehouse Picker
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */
/**
 * Class WarehousePickManager
 */
class WarehousePickManager extends HierarchicalEntityManager
{
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
