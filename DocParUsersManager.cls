<?

/**
 * Class DocParUsersManager
 */
class DocParUsersManager extends OwnedObjectManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $this->PrepValues($values);
        return OwnedObjectManager::regularAdd($values);
        
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {

        $this->PrepValues($values);
        return parent::regularSet($values);
        
    }


    /**
     * @param array $values
     *
     */
    function PrepValues(&$values) 
    {
        global $gManagerFactory;
        $userMgr = $gManagerFactory->getManager('userinfo');

        $raw = $userMgr->GetRaw($values['USER']);
        $userhash = $raw[0]['RECORD#'];
        $values[':userkey'] = $userhash;
        
    }

}