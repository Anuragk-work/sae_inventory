<?

/**
 * Class ItemsAllPickManager
 */
class ItemsAllPickManager extends HierarchicalEntityManager
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


