<?

/**
 * Class DocumentParPRGLManager
 */
class DocumentParPRGLManager extends OffsetAcctManager
{
    /**
     * Wrapper for php5.4 conversion.  Provides by-value wrapper for Add.  Can be removed, and AddByRef renamed to Add,
     * when it's verified that it's safe to call this class' Add by-reference.
     *
     * @param array &$values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        return $this->addByValue($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function addByValue($values)
    {
        return $this->addByRef($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function addByRef(&$values)
    {
        $values['MODULE'] = 'AP/AR';
        return parent::regularAdd($values);
    }

    /**
     * Wrapper for php5.4 conversion.  Provides by-value wrapper for Set.  Can be removed, and SetByRef renamed to Set,
     * when it's verified that it's safe to call this class' Set by-reference.
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        return $this->setByValue($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function setByValue($values)
    {
        return $this->setByRef($values);
    }
    /**
     * @param array $values
     *
     * @return bool
     */
    function setByRef(&$values)
    {
        $values['MODULE'] = 'AP/AR';
        return parent::regularSet($values);
    }

    /**
     * @param array $docpar
     * @param array $offsetAccts
     * @param array $itemGLGrp
     *
     * @return bool
     */
    function RecreateItemGrpValues($docpar, $offsetAccts, $itemGLGrp = array()) 
    {
        $offsetAccts['MODULE'] = 'PR';        
        return parent::RecreateItemGrpValues($docpar, $offsetAccts, $itemGLGrp);
    }

    /**
     * @return bool
     */
    function MergeQueries() 
    {
        // don't ever recompute the queries.
        return true;
    }
}