<?

/**
 * Class DocParWizMOManager
 */
class DocParWizMOManager extends EntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        return true;
    }
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values) 
    {
        return $this->add($values);
    }

}
