<?php
/**
 * Trait for logic related to reposting of the document
 *
 * @author    Jagadish <mjagadish@intacct.com>
 * @copyright 2015 Intacct Corporation All, Rights Reserved
 */

/**
 * Trait for all codes related to reposting of the document
 */
trait DocumentRepostTrait
{

    /**
     * @param array $values
     *
     * @return bool
     */
    private function isRepostingRequired($values)
    {
        $hasChange = $values['HASCHANGE'] ?? 'false';
        if($this->isChangeOrderEnabled()){
            if($hasChange === 'true' || $values['__feed_From'] === 'System') {
                //we dont want to repost if it is a source document with changes, the change document will post it
                //if it is a system change (like a flag change internally), we do not want to repost.
                return false;
            }
        }

        // return true if the document has to repost
        $__taxEngine = $values['_taxEngine'] ?? '';
        if (
            (
                IsModuleIdInstalled(Globals::$g->kAVAid) ||
                $__taxEngine == 'AvaTax' ||
                $__taxEngine == 'AdvancedTax'
            ) &&
            ($values['_DOCPAR']['SHOW_TOTALS'] ?? 'false') == 'true'
        ) {
            $msg = "The transaction uses either Avalara or Advanced Tax and must be reposted.";
            $this->_reasonsForRePost['TaxEngine'] = $msg;
            $this->_reasonsForRePostIADetails['TaxEngine'] = ['errorCode' => 'INV-1421', 'placeholder' => []];
            return true;
        }
        unset($__taxEngine);

        if($this->areCustomFieldsCompatible($values)){
            $msg = "The transaction includes compatible custom fields that are defined in the respective subledger and must be reposted.";
            $this->_reasonsForRePost['CompatibleCustomFieldsFound'] = $msg;
            $this->_reasonsForRePostIADetails['CompatibleCustomFieldsFound'] = ['errorCode' => 'INV-1422', 'placeholder' => []];
            return true;
        }

        if($this->checkForExternalChanges($values)){
            return true;
        }

        // if the count of current lines and the existing lines is different then $this->upsertEntries = false;
        if ((!is_array($values['EXISTING_ENTRIES']) ? 0 : count($values['EXISTING_ENTRIES'] ?? [])) !=
            (!is_array($values['ENTRIES']) ? 0 : count($values['ENTRIES'] ?? []))) {
            $msg = "The transaction includes new line items or deleted line items and must be reposted.";
            $this->_reasonsForRePost['AddOrDeleteLineItems'] = $msg;
            $this->_reasonsForRePostIADetails['AddOrDeleteLineItems'] = ['errorCode' => 'INV-1423', 'placeholder' => []];
            return true;
        }

        $ok = $this->Compare($values);

        // if $ok is true, this means the old and new values match.
        // there is no need to repost the document
        if (!$ok) {
            return true;
        }

        // if $ok is true then there is no change in the values.
        // this function should return false (no repost required)
        return false;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function Compare($values)
    {
        $ok = true;

        // translatedimensions is required
        $this->TranslateDimensions($values);

        $oldValues = $values['EXISTING_DOC'];
        $newValues = $values;

        // PhpStorm thinks $this is a DocumentRepostTrait and there's no way to convince it it's an EntityManager.
        $thisAsManager = $this;
        assert($thisAsManager instanceof EntityManager);
        $fieldPaths = $this->getFieldListToCompare($thisAsManager);
        $entityFieldMap =& $this->GetEntityInfoMap();
        $ok = $ok && $this->compareValues($oldValues, $newValues, $fieldPaths, $entityFieldMap);

        if (!$ok) {
            return $ok;
        }

        //
        $ownedObjects =& $this->GetOwnedObjects();

        if ($ok && is_array($ownedObjects)) {
            $ok = $this->compareOwnedObject($values, $thisAsManager, $ownedObjects);
        }

        return $ok;
    }

    /**
     * @param array           $values
     * @param EntityManager   $mgr
     * @param array           $ownedObjects
     *
     * @return bool
     */
    private function compareOwnedObject($values, $mgr, $ownedObjects)
    {
        //
        // return false if the values are not matching

        foreach ($ownedObjects as $objRec) {
            $ownedObject = $mgr->GetOwnedObject($objRec['path']);
            $lineManager = $mgr->GetOwnedObjectManager($ownedObject['entity']);
            $fieldPaths = $this->getFieldListToCompare($lineManager);

            if (count($fieldPaths) == 0) {
                continue;
            }

            $oldValues = array();
            $newValues = array();
            $lineManager->getMappedEntries($values, $oldValues, $newValues);
            //
            // if the count of current lines and the existing lines is different repost;
            $oldcount = empty($oldValues) ? 0 :count($oldValues);
            $newcount = empty($newValues) ? 0 :count($newValues);
            if  ($oldcount != $newcount) {
                return false;
            }

            $ok = true;
            $entityFieldMap =& $lineManager->GetEntityInfoMap();
            foreach (($oldValues ?? []) as $recNo => $oldRec) {
                $newRec = $newValues[$recNo];
                $ok = $ok && $this->compareValues($oldRec, $newRec, $fieldPaths, $entityFieldMap);

                if (!$ok) {
                    return false;
                }
            }

            $thisOwnedObjects =& $lineManager->GetOwnedObjects();
            if ( $ok && is_array($thisOwnedObjects)) {
                $ok = $this->compareOwnedObject($values, $lineManager, $thisOwnedObjects);
                if (!$ok) {
                    return false;
                }
            }
        }

        //
        // if all the comparisions are successfull, this means there is no change in the data.
        // reposting the document is not required.
        return true;
    }

    /**
     * @param array $oldValues
     * @param array $newValues
     * @param array $compareFields
     * @param array $fieldInfo
     *
     * @return bool
     */
    private function compareValues($oldValues, $newValues, $compareFields, $fieldInfo)
    {
        $oldValues = EntityManager::StructuredToFlat($oldValues);
        $newValues = EntityManager::StructuredToFlat($newValues);

        //
        // check each updatable field
        // if the old and new value are different set upsertEntries = false;
        foreach ($compareFields as $fieldPath) {
            $oldValue = $oldValues[$fieldPath];
            $newValue = $newValues[$fieldPath];
            $fieldType = $fieldInfo[$fieldPath]['type']['ptype'];

            if (in_array($fieldType, array('ptr', 'text', 'supdocptr'))) {
                list($oldValue) = explode('--', $oldValue);
                list($newValue) = explode('--', $newValue);
            }

            if (!$this->isEqual($oldValue, $newValue, $fieldInfo[$fieldPath])) {
                $fieldName = I18N::getSingleToken($fieldInfo[$fieldPath]['fullname'] ?? $fieldPath);
                $msg = "The field value for '$fieldName' was changed from $oldValue to $newValue";

                //eppp_p('### --- Not matching --> PATH: '.$fieldPath.'     OLD: '.$oldValue.'  ------ NEW: '.$newValue);
                if (!array_key_exists($fieldPath, $this->_reasonsForRePost)) {
                    $this->_reasonsForRePost[$fieldPath] = $msg;
                    $this->_reasonsForRePostIADetails[$fieldPath] = [
                                                                        'errorCode' => 'INV-1424',
                                                                        'placeholder' => [
                                                                           'FIELD_NAME' => $fieldName,
                                                                           'OLD_VALUE' => $oldValue,
                                                                           'NEW_VALUE' => $newValue
                                                                        ]
                                                                     ];
                }

                return false;
            }

        }

        return true;
    }

    /**
     * @param EntityManager   $mgr
     * @param bool            $ignoreDimensions
     *
     * @return array
     */
    private function getFieldListToCompare($mgr, /** @noinspection PhpUnusedParameterInspection */ $ignoreDimensions = false)
    {
        // Get the fields which need to be ignored to compare
        $ignoreFieldList = $mgr->getIgnoreFields();
        //
        // get the custom field id and merge with ignore field list
        $customFieldIds = self::getEntityCustomFieldIds($mgr);
        $ignoreFieldList = INTACCTarray_merge($ignoreFieldList, $customFieldIds);

        if (!is_array($ignoreFieldList) || count($ignoreFieldList) == 0) {
            return array();
        }

        // Get the dbfields list
        $dbFields = $mgr->GetUpdateDBFields();
        $flatmap = array_flip($mgr->_GetFlatSchemaMap());

        $objects = array();
        foreach ($dbFields as $dbField) {
            if (in_array($dbField, $ignoreFieldList)) {
                continue;
            }
            $valuePath = $flatmap[$dbField];
            if (!empty($valuePath)) {
                $objects[] = $valuePath;
            }
        }

        $customDims = $mgr->GetCustomDimFields();
        if (!empty($customDims)) {
            $customDimsPath = array_keys($customDims);
            $objects = INTACCTarray_merge($objects, $customDimsPath);
        }


        $externalFieldList = $mgr->getExternalFieldsList();
        if (!empty($externalFieldList)) {
            $objects = INTACCTarray_merge($objects, $externalFieldList);
        }


        return $objects;
    }


    /**
     * Returns EntityCustomFieldIds
     *
     * @param EntityManager $entryManager transaction entry manager
     *
     * @return string[]
     */
    private static function getEntityCustomFieldIds($entryManager)
    {
        $customFields = $entryManager->GetCustomFields();

        $customFieldIds = [];
        foreach ($customFields as $field) {
            $customFieldIds[] = $field->GetRawObjField('OBJECTFIELDID');
        }

        return $customFieldIds;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function areCustomFieldsCompatible($values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $mod = $values['_mod'];
        if ($values['_DOCPAR']['UPDATES_GL'] != 'A') {
            return false;
        }

        if ($mod == 'so') {
            $aparmgr = $gManagerFactory->getManager('arinvoice');
            $aparlinemgr = $gManagerFactory->getManager('arinvoiceitem');
            $doclinemgr = $gManagerFactory->getManager('sodocumententry', false, array('DOCTYPE' => $values['DOCPARID']));
        } else if ($mod == 'po') {
            $aparmgr = $gManagerFactory->getManager('apbill');
            $aparlinemgr = $gManagerFactory->getManager('apbillitem');
            $doclinemgr = $gManagerFactory->getManager('podocumententry', false, array('DOCTYPE' => $values['DOCPARID']));
        } else {
            // we should not come here
            return false;
        }

        // Document Custom Fields
        $docCFIds = array_keys($this->customFields);
        $aparCFIds = array_keys($aparmgr->customFields);

        // Document Entry Custom Fields
        $doclineCFIds = array_keys($doclinemgr->customFields);
        $aparlineCFIds = array_keys($aparlinemgr->customFields);

        // Common CustomFields
        $commonFields = array_intersect($docCFIds, $aparCFIds);
        $commonlineFields = array_intersect($doclineCFIds, $aparlineCFIds);

        return (count($commonFields) > 0 || count($commonlineFields) > 0);
    }


}