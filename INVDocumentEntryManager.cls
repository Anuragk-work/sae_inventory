<?
class INVDocumentEntryManager extends DocumentEntryManager
{
    /**
     * @param array $params
     */
    function __construct($params=array())
    {
        $params['_mod'] = 'inv';
        parent::__construct($params);
    }



    /**
     *      Is the passed PODocument line from a supply transaction?
     *
     * @param array $entry  one PODocument line
     *
     * @return bool         true --> is supply transaction
     */
    public static function isSupplyTransaction($entry)
    {
        return PODocumentEntryManager::isSupplyTransaction($entry);
    }


    /**
     *      Does the passed PODocument line contain a Supplies item?
     *
     * @param array $entry  one PODocument line
     *
     * @return bool         true --> is supply item
     */
    public static function isSupplyItem($entry)
    {
        return PODocumentEntryManager::isSupplyItem($entry);
    }



    /**
     * Validate record
     *
     *
     * @param array &$values Array of values
     *
     * @return bool true if valid
     */
    protected function ValidateRecord(&$values)
    {
        $ok = parent::ValidateRecord($values);
        if ($ok && ItemManager::isSuppliesInventoryEnabled()) {
            // on Add() we don't have the docparid set in the values yet....
            if ( ! isset($values['DOCPARID'])) {
                $values['DOCPARID'] = $this->_docType ?? '';
            }
            if (self::isSupplyTransaction($values)) {
                if ( ! self::isSupplyItem($values)) {
                    $itemID = $values['ITEMID'];
                    $lineno = $values['LINE_NO'] + 1;
                    Globals::$g->gErr->addIAError('PO-0179', __FILE__ . ':' . __LINE__,
                        "Must have a Supplies item: $itemID / $lineno ",
                        ['ITEMID' =>$itemID ,'LINENO' => $lineno]);
                    $ok = false;
                }
            }
        }
        return $ok;
    }


}
