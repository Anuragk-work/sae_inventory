<?

/**
 *    FILE: DocumentEntrysubtotalsManager.cls
 *    AUTHOR: Sanjay Kumar
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 *  Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */

/**
 * Class DocumentEntrySubTotalsManager
 */
class DocumentEntrySubTotalsManager extends OwnedObjectManager
{
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
        if(IsMultiEntityCompany() && GetContextLocation() && ( !isset($values['LOCATIONKEY']) || $values['LOCATIONKEY'] == '' ) ) {
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
     */
    public function GetByParent($_parent)
    {
        $newResult = parent::getByParent($_parent);

        foreach ($newResult as $key  => $value) {
            if (!isset($value['TAXDETAIL']) && isset($value['TAXDETAIL3P'])) {
                $newResult[$key]['TAXDETAIL'] = $value['TAXDETAIL3P'];
            }
            $newResult[$key]['DEPARTMENT'] = (isset($value['DEPARTMENT']) && $value['DEPARTMENT'] != '') ? $value['DEPARTMENTID']."--".$value['DEPARTMENT'] : $value['DEPARTMENTID'];
            $newResult[$key]['LOCATION'] = (isset($value['LOCATION']) && $value['LOCATION'] != '') ? $value['LOCATIONID']."--".$value['LOCATION'] : $value['LOCATIONID'];
            $this->TransformDimensionValues($newResult[$key], $nullObj, true);
            $newResult[$key]['ABSVAL'] = (isset($value['ABSVAL']) && $value['ABSVAL'] != '') ? $value['ABSVAL'] : 0;
            $newResult[$key]['TOTAL'] = (isset($value['TOTAL']) && $value['TOTAL'] != '') ? $value['TOTAL'] : 0;
            $newResult[$key]['TRX_ABSVAL'] = (isset($value['TRX_ABSVAL']) && $value['TRX_ABSVAL'] != '') ? $value['TRX_ABSVAL'] : 0;
            $newResult[$key]['TRX_TOTAL'] = (isset($value['TRX_TOTAL']) && $value['TRX_TOTAL'] != '') ? $value['TRX_TOTAL'] : '0';
        }
        return $newResult;
    }

    /**
     * @param int      $cny
     * @param string   $entity
     * @param string   $module
     * @param bool     $followgldimensions
     * @param string[] $ignoreList
     *
     * @return array|null
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
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        return [];
    }

    /**
     * @return string[]
     */
    protected function getExternalFieldsList()
    {
        return [];
    }


    //  *****************************************************************************************************
    //  *****************************************************************************************************
    //
    // IMPORTANT NOTE:
    //
    //  The 'Docentrysubtotals' record is very small (four fields) and is NOT the same as the record
    //  being referred to by the rest of this manager, which is the 'dochdrsubtotals' record, even though
    //  the ENTITY is called 'documententrysubtotals'.  Go figure.  Anyway, the below entries deal with
    //  the smaller record, used as a link between subtotals and document entry records.
    //
    //  *****************************************************************************************************
    //  *****************************************************************************************************


    /**
     *      Given a document tree (DocHdr and all its children), construct docentry subtotals and save them.
     *  NOTE this is NOT the same as the docemententrysubtotals entity!  These are the four-field linking entries.
     *  There is no entity for the documententrysubtotals table; THIS entity manager is for 'dochdrsubtotals'.
     *
     * @param array     $values         The values from a SAVE/POST from the UI or API (of the whole document tree)
     *
     * @return bool
     */
    public function CreateDocentrySubtotalsFromDocValues($values)
    {
        $docentrySubtotals = array();
        if (isset($values['SUBTOTALS'])) {
            $entries   = $values['ENTRIES'];
            $subtotals = $values['SUBTOTALS'];

            $entriesByLineNo = [];
            foreach ( $entries as $entry) {
                $entriesByLineNo[$entry['LINEKEY']] = $entry['RECORDNO'];
            }

            foreach ( $subtotals as $subtotal) {
                $ineNo = $subtotal['ENTRY_LINENO'];
                if (isset($entriesByLineNo[$ineNo])) {
                    $docentrySubtotals[] = array(
                        'DOCHDRKEY'    => $subtotal['DOCHDRNO'],
                        'DOCENTRYKEY'  => $entriesByLineNo[$ineNo],
                        'SUBTOTALSKEY' => $subtotal['RECORDNO'],
                        // 'LOCATIONKEY'  => $subtotal['LOCATIONKEY'],  // these don't appear in the table...
                        // 'DEPTKEY'      => $subtotal['DEPTKEY'],
                    );
                }
            }
        }
        if (isset($docentrySubtotals[0]['DOCHDRKEY'])) {
            return $this->AddOrUpsertDocEntrySubtotals($docentrySubtotals, $docentrySubtotals[0]['DOCHDRKEY']);
        }
        return true;
    }




    /**
     *      Do the upserting, which is bulky and sorta-unreleated to computing what the subtotals should be.
     *  NOTE this is NOT the same as the docemententrysubtotals entity!  These are the four-field linking entries.
     *  There is no entity for the documententrysubtotals table; THIS entity manager is for 'dochdrsubtotals'.
     *
     *  So, if we are NOT upserting, just add the records.  If we ARE upserting, then preserve the existing records
     *  if and only if there is an exact match between the saved and new reords.  Otherwise, delete the old and add
     *  the new.
     *
     * @param array  $docentrySubtotals
     * @param int    $docHdrKey
     *
     * @return bool
     */
    protected function AddOrUpsertDocEntrySubtotals(&$docentrySubtotals, $docHdrKey)
    {
        $cny = GetMyCompany();
        DocumentManager::updatingEntity($this->_entity);
        if (DocumentManager::$upsertFeaturInUse) {
            Matchmaker::additionalLogging("Attempting upsert of DocEntrySubtotals");

            // Get existing records
            $query = "SELECT * FROM docentrysubtotals WHERE cny#=:1 and dochdrkey=:2";
            $existingRecords = QueryResult(array($query, $cny, $docHdrKey));
            if ($existingRecords === false) {
                $existingRecords = [];
            }

            if ( ! empty($existingRecords)) {
                // index the new records for quicker lookup
                $index = [];
                foreach ($docentrySubtotals as $key => $row) {
                    $index[ $row['DOCENTRYKEY']][ $row['SUBTOTALSKEY']] = $key;
                }

                // Now do an exact match on the existing and new, or delete the new.
                Matchmaker::additionalLogging("Matching existing records to new; no update if a match, but delete existing if no match.....");
                foreach ($existingRecords as $row) {
                    $deKey = $row['DOCENTRYKEY'];
                    $stKey = $row['SUBTOTALSKEY'];
                    if (isset($index[ $deKey ][ $stKey ])) {
                        unset( $docentrySubtotals[$index[ $deKey ][ $stKey ]]); // exact match
                    } else {
                        $this->deleteDocEntrySubtotal($row);    // not a match
                    }
                }
            }
        }

        // ok, any records not handled above need to be added.
        // This includes if we aren't using upsert.
        if (DocumentManager::$upsertFeaturInUse &&  ! empty($docentrySubtotals)) {
            Matchmaker::additionalLogging("New docentrysubtotals that don't match existing being added...");
        }
        $query = "insert into docentrysubtotals (cny#,dochdrkey,docentrykey,subtotalskey) values (:1, :2, :3, :4)";

        // add records still in the array
        foreach ($docentrySubtotals as $docentrySubtotal) {
            if (! ExecStmt([$query, $cny, $docentrySubtotal['DOCHDRKEY'], $docentrySubtotal['DOCENTRYKEY'], $docentrySubtotal['SUBTOTALSKEY']])) {
                return false;
            }
        }
        return true;
    }


    /**
     *      Delete an existing DocEntrySubtotals record.
     *  NOTE this is NOT the same as the docemententrysubtotals entity!
     *
     * @param string[]      $existing           an existing record
     *
     * @return bool         Did it work?
     */
    public function deleteDocEntrySubtotal($existing)
    {
        // any existing records we haven't used get deleted....
        $query = "DELETE docentrysubtotals WHERE cny#=:1 and dochdrkey=:2 and docentrykey=:3 and subtotalskey=:4";
        if (!ExecStmt(array($query, GetMyCompany(), $existing['DOCHDRKEY'], $existing['DOCENTRYKEY'], $existing['SUBTOTALSKEY']))) {
            return false;
        }
        return true;
    }

}
