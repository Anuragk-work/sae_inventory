<?

/**
 * Class InvDocumentParInvGLManager
 */
class InvDocumentParInvGLManager extends OffsetAcctManager
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
        return $this->addByRef($values);
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
        $values['ISOFFSET'] = false;
        $values['MODULE'] = 'INV';
        $ok = self::translateGLAccountNumberToRecordNumber($values);
        return $ok && parent::regularAdd($values);
    }

    /**
     * Wrapper for php5.4 conversion.  Provides by-value wrapper for Set.  Can be removed, and SetByRef renamed to Set,
     * when it's verified that it's safe to call this class' Set by-reference.
     *
     * @param array &$values
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
        $values['ISOFFSET'] = false;
        $values['MODULE'] = 'INV';
        $ok = self::translateGLAccountNumberToRecordNumber($values);
        return $ok && parent::regularSet($values);
    }

    /**
     * Populate GLACCOUNTRECORDNO based on the incoming ACCOUNTNO.
     *
     * @param array $values Offset account attributes
     *
     * @return bool True if successful, false otherwise
     */
    private static function translateGLAccountNumberToRecordNumber(&$values) : bool
    {
        $glAccount = '';
        $ok = false;
        if (isset($values['GLACCOUNT'])) {
            $glAccount = explode(BaseAccountManager::ACCT_NO_TITLE_SEPERATOR, $values['GLACCOUNT'])[0];
        }
        if (!empty($glAccount)) {
            $glAccountMgr = Globals::$g->gManagerFactory->getManager("glaccount");
            $filters = [ 'selects' => [ 'RECORDNO', 'ACCOUNTNO' ],
                         'filters' => [ [ [ 'ACCOUNTNO', '=', $glAccount ] ] ] ];
            $result = $glAccountMgr->GetList($filters);
            if (!Util::isEmptyCountable($result)) {
                $values['GLACCOUNTRECORDNO'] = $result[0]['RECORDNO'];
                $ok = true;
            } else {
                // GLACCOUNT not found
                Globals::$g->gErr->addIAError('INV-1444', __FILE__ . ':' . __LINE__, '',
                                              [ 'ACCOUNTNO' => $values['GLACCOUNT'] ]);
            }
        } else {
            // GLACCOUNT is required
            Globals::$g->gErr->addIAError('INV-1443', __FILE__ . ':' . __LINE__);
        }

        return $ok;
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
        $offsetAccts['MODULE'] = 'INV';        
        return parent::RecreateItemGrpValues($docpar, $offsetAccts, $itemGLGrp);
    }

    /**
     * @return bool
     */
    function MergeQueries() 
    {
        // don't ever recompute the queries -- they're hand crafted.
        return true;
    }
}