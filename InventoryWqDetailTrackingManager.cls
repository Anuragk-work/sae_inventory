<?


// **** THIS CLASS IS A SYNONYM FOR THE InventoryWorkQueueDetailsManager (but with a different owner)

class InventoryWqDetailTrackingManager extends OwnedObjectManager   // parent is InventoryWQDetail.ent
{
    /** @var InventoryWorkQueueDetailsManager|null $trackManager */
    protected $trackManager = null;


    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
        $this->trackManager = Globals::$g->gManagerFactory->getManager('inventoryworkqueuedetails');
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        return $this->trackManager->regularAdd($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        return $this->trackManager->regularSet($values);
    }


    /**
     * Get a single record.
     *
     *
     * @param string        $recordNum          A record# (of the inventory work queue record
     * @param string[]|null $fields
     *
     * @return array|false                      one DETAIL LINE
     */
    function get($recordNum, $fields = null)
    {
        return $this->trackManager->get($recordNum, $fields);
    }


    /**
     * Override the Entity Manager GetList() code.
     *
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        return $this->trackManager->GetList($params, $_crosscny, $nocount);
    }

}

