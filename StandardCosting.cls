<?
/**
 * class for standard costing logic in SCM
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

class StandardCosting extends Costing
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
        &$useSourceCost
    )
    {
        if ($isReturn && $sourceDocEntryKey) {
            return parent::findUnitCost(
                $spi, $unitcost, $lastcost, $kitentry, $isReturn, $sourceDocEntryKey, $effectiveDate, $warehouse,
                $useSourceCost
            );
        } else {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $itemMgr = $gManagerFactory->getManager('item');

            $unitcost = $itemMgr->GetStandardCost($kitentry['ITEMID'], $warehouse, $effectiveDate);
            $lastcost = $unitcost;
            $kitentry['WHSE_STANDARD_COST'] = $unitcost;
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
    function calculateCost(&$qtyCostArray, $costEntry, $currentCost, $useSourceCost)
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
        //nothing for standard cost
    }

}
