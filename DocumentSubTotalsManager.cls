<?
import('OwnedObjectManager');
class DocumentSubTotalsManager extends OwnedObjectManager
{

    /**
     * @param array $params
     */
    function __construct($params=array())
    {
        $this->_docType = $params['DOCTYPE'] ?? '';
        parent::__construct($params);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        if (isset($values['TAXDETAIL']) && !is_numeric($values['TAXDETAIL'])) {
            $values['TAXDETAIL3P'] = $values['TAXDETAIL'];
            $values['TAXDETAIL'] = '';
        }
        if(IsMultiEntityCompany() && GetContextLocation() && ( !isset($values['LOCATIONKEY']) || $values['LOCATIONKEY'] == '' ) ) {
            $values['LOCATIONKEY'] = GetContextLocation();
        }
        unset($values['RECORDNO']);

        $ok = parent::regularAdd($values);

        // we need to fake the customdimensions cache string for GL posting code to work
        if ( $ok ) {
            parent::setCustomDimensionsCache($values);
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        if (isset($values['TAXDETAIL']) && !is_numeric($values['TAXDETAIL'])) {
            $values['TAXDETAIL3P'] = $values['TAXDETAIL'];
            $values['TAXDETAIL'] = '';
        }
        if (IsMultiEntityCompany() && GetContextLocation() && ( !isset($values['LOCATIONKEY']) || $values['LOCATIONKEY'] == '' ) ) {
            $values['LOCATIONKEY'] = GetContextLocation();
        }

        $ok = parent::regularSet($values);

        // we need to fake the customdimensions cache string for GL posting code to work
        if ( $ok ) {
            parent::setCustomDimensionsCache($values);
        }

        return $ok;
    }

    /**
     * @param string $_parent
     *
     * @return array|false
     * @throws Exception
     */
    function GetByParent($_parent)
    {
        $newResult = parent::getByParent($_parent);

        foreach ($newResult as $key  => $value) {
            if (!isset($value['TAXDETAIL']) && isset($value['TAXDETAIL3P'])) {
                $newResult[$key]['TAXDETAIL'] = $value['TAXDETAIL3P'];
            }
            $newResult[$key]['DEPARTMENT'] = (isset($value['DEPARTMENT']) && $value['DEPARTMENT'] != '') ? $value['DEPARTMENTID']."--".$value['DEPARTMENT'] : $value['DEPARTMENTID'];
            $newResult[$key]['LOCATION'] = (isset($value['LOCATION']) && $value['LOCATION'] != '') ? $value['LOCATIONID']."--".$value['LOCATION'] : $value['LOCATIONID'];
            $this->TransformDimensionValues($newResult[$key], $nullObj, true);
            $this->setCustomDimensionsCache($newResult[$key]);

            // unsetting :customdimensions as it causes trouble in xml
            // system needs only CUSTOMDIMENSIONS for business logic
            unset($newResult[$key][':customdimensions']);

            $newResult[$key]['ABSVAL'] = (isset($value['ABSVAL']) && $value['ABSVAL'] != '') ? $value['ABSVAL'] : 0;
            $newResult[$key]['TOTAL'] = (isset($value['TOTAL']) && $value['TOTAL'] != '') ? $value['TOTAL'] : 0;
            $newResult[$key]['TRX_ABSVAL'] = (isset($value['TRX_ABSVAL']) && $value['TRX_ABSVAL'] != '') ? $value['TRX_ABSVAL'] : 0;
            $newResult[$key]['TRX_TOTAL'] = (isset($value['TRX_TOTAL']) && $value['TRX_TOTAL'] != '') ? $value['TRX_TOTAL'] : 0;
        }

        return $newResult;
    }


    /**
     *      Override of GetQueryName, takes into account whether we want ALL subtotals or only the summaries
     *
     * @return string       the name of the query to use to read all records by parent
     */
    function GetQueryName()
    {
        // Does the caller REALLY want ALL the records?
        // We do if we are upserting.  Otherwise we just get the view, which is a summary.
        if (DocumentManager::$upsertFeaturInUse) {
            // Matchmaker::additionalLogging("Querying subtotals for upsert, NOT USING THE VIEW (to get ALL records)");
            $standardGetByParent = 'QRY_'     . strtoupper($this->_entity) . '_SELECT_BY_PARENT';
            $myGetByParent       = 'QRY_ALL_' . strtoupper($this->_entity) . '_SELECT_BY_PARENT';

            // Note: there's magic in the air!  The Entity Manager generates a SelectByParent query and adds
            //          fields for dimensions.  What *I* want is the EXACT SAME QUERY, but without the use of
            //          the VIEW.....
            $this->_QM->_queryList[$myGetByParent] = str_replace( 'v_dochdrsubtotals', 'dochdrsubtotals', $this->_QM->_queryList[$standardGetByParent]);

            return $myGetByParent;
        }
        return parent::GetQueryName();
    }

    /**
     * @param array|int|string $_id
     *
     * @return bool|string[][]
     */
    public function GetRaw($_id)
    {
        $obj = $this->DoQuery('QRY_DOCUMENTSUBTOTALS_SELECT_RAW_VID', [$_id]);

        if (\is_array($obj) && isset($obj[0])) {
            $this->_ProcessResultForOwnership($obj[0]);
        } else {
            $result = null;
            $this->processMultiEntityFilterFields($result);
        }

        return $obj;
    }

    /**
     *      Some DocHdrSubtotals records contain a link to a PRENTRY record.  Here, we null those out until later.
     *
     * @param int   $docHdr             the doc hdr record number
     *
     * @return bool                     did it work?
     *
     */
    public function clearPREntryLinks($docHdr)
    {
        return $this->DoQuery('QRY_SUBTOTOALS_CLEAR_ALL_PRENTRYKEY', [$docHdr]);
    }


    /**
     * returns the module preference used for numbering sequence
     *
     * @return string module preference
     */
    protected function getSequenceKey()
    {
        return 'DOCHDRSUBTOTALS';
    }

    /**
     * @param int $cny
     * @param string $entity
     * @param string $module
     * @param bool   $followgldimensions
     * @param array   $ignoreList
     *
     * @return array|bool
     */
    public static function LoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList)
    {
        $newDims = parent::LoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList);
        //Copy the item dimension stature from iadimensions.cls
        if(empty($newDims['item'])) {
            $newDims['item'] = array(
                'path' => 'ITEMID',
                'fullname' => 'Item',
                'type' => array(
                    'ptype' => 'ptr',
                    'type' => 'ptr',
                    'pickentity' => 'itempick',
                    'entity' => 'item',
                    'size' => 28,
                    'maxlength' => 30,
                ),
                'dimfieldid' => 'itemdimkey',
                'entity' => 'item',
                'table' => 'icitem',
                'dimdbkey' => 'ITEMDIMKEY',
                'dimNameField' => array(
                    'ITEMNAME' => 'item.name',
                ),
                'dimfkid' => 'ITEMID',
                'object_relation' => array(
                    'fkey' => 'itemdimkey', 'invfkey' => 'record#', 'table' => 'icitem', 'join' => 'outer'
                ),
                'security_key' => 'inv/lists/item',
                'pickentity_key' => 'inv/lists/itempick',
                'mod' => 'so',
                'standard' => true,
                'isDimension' => true,
                'default' => false,
                'enabled' => false,
                'required' => false,
                'renameable' => true,
                'reclass' => true,
                'nohierarchy' => true,
                'id' => 824,
                'keyid' => 825,
                'nameid' => 826
            );
        }
        return $newDims;
    }


    /**
     * @param array $values
     *
     * @return true
     */
    function mapSubtotalsRecordNo(&$values)
    {
        // do mapping only if
        // 1. its is simple tax
        // and
        // 2. mega company and root level transaction
        // but do it if we are just upserting
        if ( ! DocumentManager::$upsertFeaturInUse) {
            $doMaping = ($values['_taxEngine'] == 'SimpleTax');
            $doMaping = $doMaping && (IsMultiEntityCompany() && !GetContextLocation());
            if (!$doMaping) {
                return true;
            }
        }

        $entriesMap = [];
        foreach ($values['ENTRIES'] as $entry) {
            $lineNo = $entry['LINEKEY'];
            $entryRecNo = $entry['RECORDNO'];
            if ($entryRecNo != '') {
                $entriesMap[$lineNo] = $entryRecNo;
            }
        }

        $subtotalMap = [];
        if (isset($values['EXISTING_SUBTOTALS'] )) {
            foreach ($values['EXISTING_SUBTOTALS'] as $recordNumber => $oldSubTot) {
                $deDesckey = $oldSubTot['DOCENTRYKEY'] . '|' . $oldSubTot['DESCRIPTION'];
                $subtotalMap[$deDesckey] = $recordNumber;
            }
        }

        if (isset($values['SUBTOTALS'] )) {
            foreach ($values['SUBTOTALS'] as $skey => $subTot) {
                if (in_array($subTot['DESCRIPTION'], array('SUBTOTAL', 'TOTAL'))) {
                    continue;
                }

                $lineNo = $subTot['ENTRY_LINENO'];
                $subTotDesc = $subTot['DESCRIPTION'];
                $docEntryKey = $entriesMap[$lineNo];

                $key = $docEntryKey . '|' . $subTotDesc;
                $recNo = $subtotalMap[$key];

                $values['SUBTOTALS'][$skey]['DOCENTRYKEY'] = $docEntryKey;  // always set the right docentrykey
                unset($values['SUBTOTALS'][$skey]['RECORDNO']);
                if ($recNo != '') {
                    $values['SUBTOTALS'][$skey]['RECORDNO'] = $recNo;
                }
            }
        }

        return true;
    }

    /**
     * @param array $values
     * @param array $oldEntries
     * @param array $newEntries
     */
    function getMappedEntries($values, &$oldEntries, &$newEntries)
    {
        $oldEntries = $values['EXISTING_SUBTOTALS'];
        $entries = $values['SUBTOTALS'];
        $this->tweakSubtotals($entries);

        foreach ( ($entries ?? []) as $entry) {
            $recNo = $entry['RECORDNO'];
            if ($recNo != '') {
                $newEntries[$recNo] = $entry;
            }
        }
    }

    /**
     * @param array $subtotals
     */
    private function tweakSubtotals(&$subtotals)
    {
        //
        // remove the first and the last entry as these are for UI display
        if (isset($subtotals)) {
            $subtotcount = count($subtotals);
            if ($subtotals[0]['DESCRIPTION'] == 'SUBTOTAL') {
                unset($subtotals[0]);
            }
            if ($subtotals[$subtotcount - 1]['DESCRIPTION'] == 'TOTAL') {
                unset($subtotals[$subtotcount - 1]);
            }
        }
    }

    /**
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        static $ignoreFields = [
            'dochdrkey',
            'description',
            'absedit',
            'percentval',
            'percentedit',
            'status',
            'taxdetail',
            'prentrykey',
            'taxdetail3p',
            'docentrykey',
            'whencreated',
            'whenmodified',
            'createdby',
            'modifiedby',
            'docparsubtotalkey',
        ];

        return $ignoreFields;
    }

    /**
     * @return string[]
     */
    protected function getExternalFieldsList()
    {
        static $externalFields = [];

        if (IsMultiEntityCompany() && GetContextLocation() != '') {
            $externalFields = ['LOCATION', 'DEPARTMENT'];
        }

        return $externalFields;
    }

    /**
     * This function updates the line entry key to subtotals lines.
     *
     * @param array $entries array of docentry lines from a document update
     * @param array $subtotals array set of subtotal values from a docment update
     *
     * @return bool true on success, false otherwise
     */
    public function updateDocentrySubtotals($entries, $subtotals)
    {
        $ok = true;
        $query   = [];
        DocumentManager::updatingEntity('subtotals');
        $query[0] = "update dochdrsubtotalsmst set docentrykey = :1 WHERE record# = :2  AND cny# = :3 ";
        $query[3] = GetMyCompany();

        $entryRec = [];
        foreach ($entries as $entry) {
            $entryRec[$entry['LINEKEY']] = $entry['RECORDNO'];   // line number --> record number
        }

        foreach ($subtotals as $subtotal) {
            if (isset($entryRec[$subtotal['ENTRY_LINENO']])) {
                $entryRecno = $entryRec[$subtotal['ENTRY_LINENO']];
                if ($entryRecno != ($subtotal['DOCENTRYKEY'] ?? 0)) {
                    $query[1] = $entryRecno;
                    $query[2] = $subtotal['RECORDNO'];
                    $ok = $ok && ExecStmt($query);
                }
            }
        }
        return $ok;
    }


    /**
     *      When a document is POSTed, the subtotals records may already have record numbers in them as a side
     *  effect of how they are created (copied).  In some cases, there will be DUPLICATE record numbers.  We want
     * to preserve ONE of the records, but on the dups, make them 'new' records by removing the record number.
     *
     * @param array     $values         The document tree values, prior to set() call
     */
    static function removeDuplicateRecordNumbersPriorToUpsert(&$values)
    {
        if (!isset($values['SUBTOTALS'])) {
            return;
        }

        // Remove duplicate record#s from the subtotals; back when we did not use upsert all the records were
        // delted and re-added, so the duplicate record numbers were not an issue.  Here's we'll update some
        // and not others
        $recordNumbersInSubtotals = [];
        foreach ($values['SUBTOTALS'] as $key => $subtotal) {
            if (isset($subtotal['RECORDNO'])) {
                $rec = $subtotal['RECORDNO'];
                if (isset($recordNumbersInSubtotals[$rec])) {
                    unset($values['SUBTOTALS'][$key]['RECORDNO']);
                } else {
                    $recordNumbersInSubtotals[$rec] = true;
                }
            }
        }
    }

}
