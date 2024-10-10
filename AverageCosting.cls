<?
/**
 * class for average costing logic in SCM
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

class AverageCosting extends Costing
{
    /**
     * @param string $spi
     * @param float  $unitcost
     * @param float  $lastcost
     * @param array  $kitentry
     * @param bool   $isReturn
     * @param int    $sourceDocEntryKey
     * @param string $effectiveDate
     * @param string $warehouse
     * @param bool   $useSourceCost
     *
     * @return bool
     */
    protected function findUnitCost(
        $spi, &$unitcost, &$lastcost, &$kitentry, $isReturn, $sourceDocEntryKey, $effectiveDate, $warehouse,
        &$useSourceCost)
    {
        // purchase return or return from converting document go to parent
        if ($isReturn && ($spi == 'Purchase' || $sourceDocEntryKey)) {
            return parent::findUnitCost(
                $spi, $unitcost, $lastcost, $kitentry, $isReturn, $sourceDocEntryKey, $effectiveDate, $warehouse,
                $useSourceCost);
        } else {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $itemMgr = $gManagerFactory->getManager('item');

            $itemid = $kitentry['ITEMID'];

            $unitcost = $itemMgr->GetAverageCost($itemid, $warehouse, $effectiveDate, $lastcost);
        }

        return true;
    }

    /**
     * @param array $qtyCostArray
     * @param array $costEntry
     * @param float $currentCost
     * @param bool  $useSourceCost
     *
     * @return bool
     */
    protected function calculateCost(&$qtyCostArray, $costEntry, $currentCost, $useSourceCost)
    {
        if ($useSourceCost) {
            return parent::calculateCost($qtyCostArray, $costEntry, $currentCost, $useSourceCost);
        }

        $qtyCostArray['UNITCOST'] = $currentCost;
        $qtyCostArray['COST'] = ibcmul(
            $qtyCostArray['UNITCOST'], $qtyCostArray['QTY'], ItemManager::AVERAGE_COST_DECIMALS, true
        );

        return true;
    }

    /**
     * @param array $costEntry
     */
    protected function calculateSalesUnitCost(&$costEntry)
    {
        //nothing for average cost
    }

}
