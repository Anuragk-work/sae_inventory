<?

/**
 *    FILE:    StkitDocumentEntryCostManager
 *    AUTHOR: Manoj Mahur
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */

define('DIS_KIT', 'Disassemble Kits');

/**
 * Class StkitDocumentEntryCostManager
 */
class StkitDocumentEntryCostManager extends EntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        
        $source = 'StkitDocumentEntryCostManager::Add';
        $ok = $this->_QM->beginTrx($source);

        $nextId = $this->GetNextRecordKey();
        $ok = $ok && isset($nextId);
        $values[':record#'] = $nextId;

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            global $gErr;
            $msg = "Could not create stockable kit costing record!";
            $gErr->addIAError('INV-0920', __FILE__ . ':' . __LINE__, $msg,[]);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }


    /**
     *      Given a list of docentrycostkit records to add or update, do so.  We may or may not be using upsert.
     *
     * Note: on advice from Senthil, made this 'static'
     *
     * @param string|int        $docEntryKey               The record# of the docentry record to use
     * @param string[][]        $docEntryCostKitEntries    The entries to add/upsert for this docentry
     *
     * @return bool
     */
    static function addOrUpsert($docEntryKey, $docEntryCostKitEntries)
    {
        $docentryCostMgr = Globals::$g->gManagerFactory->getManager('stkitdocumententrycost');
        DocumentManager::updatingEntity($docentryCostMgr->_entity);

        $useExisting = DocumentManager::$upsertFeaturInUse; // do we want to use existing records or just Add()?

        // Use the 'matchmaker' so we can Upsert when the records already exist.
        // There may not be any current records, but that's ok, we'll just ADD ....
        // (not passing the parent key name or number means 'don't use existing records')
        $matchmaker = new Matchmaker($docentryCostMgr);
        return $matchmaker->upsert($docEntryCostKitEntries, ($useExisting ? "DOCENTRYKEY" : ''), $docEntryKey);
    }


    /**
     *      During the conversion from bins to advanced-bins, we need to update existing docentrycost records
     *  to have NO aisle and row, and maybe change the bin record# itself.
     *
     * @param string[]      $binInfo        an array with BINKEY (the existing key), WHSEKEY, AISLEKEY, and ROWKEY
     *
     * @return bool
     */
    public function updateTransactionsForNewBin($binInfo)
    {
        $manager = Globals::$g->gManagerFactory->getManager('documententrycost');
        return $manager->updateTransactionsForNewBinCommon($binInfo, 'docentrycostkits');
    }

}

