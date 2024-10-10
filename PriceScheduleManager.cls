<?
/**
*    FILE:
*    AUTHOR: John P. Campbell
*    DESCRIPTION:
*
*    (C) 2000, Intacct Corporation, All Rights Reserved
*
*    This document contains trade secret data that belongs to Intacct
*    Corporation and is protected by the copyright laws.  Information
*    herein may not be used, copied or disclosed in whole or in part
*    without prior written consent from Intacct Corporation.
*/
class PriceScheduleManager extends EntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "PriceScheduleManager::Add";
        global $gErr;
        
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->Translate($values);
        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create Price Schedule record!";
            $gErr->addIAError('INV-0769', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
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
        $source = "PriceScheduleManager::Set";
        global $gErr;

        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->Translate($values);
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not update Price Schedule record!";
            $gErr->addIAError('INV-0770', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function Translate(&$values) 
    {
        
        global $gErr, $gManagerFactory;
        $plMgr = $gManagerFactory->getManager('invpricelist');

        $ok = true;

        if ($values['PRICELISTID'] && $values['DISCOUNT']) {
            $ok = false;
            $msg = "Please select a price list or a discount for this schedule, but not both.";
            $gErr->addIAError(
                'INV-0771', __FILE__.':'.__LINE__,
                'Invalid Discount', [],
                $msg, []
            );
        }
        if ($values['DISCOUNT'] > 100) {
            $ok = false;
            $msg = "Discount Value cannot be greater than 100!";
            $gErr->addIAError('INV-0772', __FILE__ . ':' . __LINE__, $msg, []);
        }

        if ( $ok && $values['PRICELISTID']) {
            $row = $plMgr->GetRaw($values['PRICELISTID']);
            if (!isset($row[0])) {
                $ok = false;
                $gErr->addIAError(
                    'INV-0773', __FILE__ . ':' . __LINE__,
                    "Invalid price list entered", [],
                    "The price list '" . $values['PRICELISTID'] . "' does not exist.", ['PRICELISTID' => $values['PRICELISTID']],
                    "Choose a valid price list.", []
                );
            }
            else {
                $values[':pricelistkey'] = $row[0]['RECORD#'];
            }
        }

        return $ok;
    }

}
