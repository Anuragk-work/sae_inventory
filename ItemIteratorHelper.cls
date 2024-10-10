<?php
/**
 * Class ItemIteratorHelper
 *
 * Implements specifics for reading an Item record using the result set iterator
 *
 * @author    samvel <smirijanyan@intacct.com>
 * @copyright 2000-2018 Intacct Corporation
 *
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 */

class ItemIteratorHelper extends ResultSetIteratorHelper
{

    /**
     * Completes reading routine of the Item record.
     *
     * @param array $record
     * @param bool  $isRecordReadPartial If set to true skips some reading steps
     *
     * @throws Exception
     */
    public function afterRecordRead(&$record, $isRecordReadPartial = false)
    {
        parent::afterRecordRead($record);

        /* @var ItemManager $manager */
        $manager = $this->manager;


        if (in_array($record['ITEMTYPE'], array(STOCKABLE_KIT, KIT))) {
            $itemrec = $manager->Get($record['ITEMID']);

            $record['COMPONENT_INFO'] = $itemrec['COMPONENT_INFO'];
        } else {
            $record['REVPOSTING'] = null;
        }
        $record['BASEPRICE'] = $manager->GetBasePrice($record['ITEMID'], 1);
    }

}