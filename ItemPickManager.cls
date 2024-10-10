<?

/**
 * Class ItemPickManager
 */
class ItemPickManager extends HierarchicalEntityManager
{
    /**
     * Table to join for platform_visiblity
     *
     * @return string
     */
    function GetPlatformContextJoinTable()
    {
        return "ICITEM";
    }
}


