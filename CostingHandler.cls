<?
/**
 * handler for all costing logic in SCM
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

require_once 'scm_util.inc';

class CostingHandler
{
    /**
     * @var bool $isInvInstalled
     */
    var $isInvInstalled;

    function __construct()
    {
        $this->isInvInstalled = IsInstalled(Globals::$g->kINVid);
    }
    
    /**
     * @param string|null $costmethod
     *
     * @return Costing
     */
    public function GetCostingObject($costmethod = '')
    {
        switch ($costmethod) {
            case 'S' :
                $costHelper = 'StandardCosting';
                break;
            case 'A' :
                $costHelper = 'AverageCosting';
                break;
            case 'L' :
            case 'F' :
            case 'LF' :
                $costHelper = 'LIFOFIFOCosting';
                break;
            default  :
                $costHelper = 'Costing';
                break;
        }

        /* @var Costing $costingObj */
        $costingObj = Globals::$g->gManagerFactory->_getObjectInstance($costHelper);
        return $costingObj;
    }

    /**
     * @return bool
     */
    public static function initializeCosting()
    {
        $ok = ExecStmt(array("begin invcost_utils.initializecosting; end;"));
        return $ok;
    }

    /**
     * This method should handle the Preparation of Costing line items and insert into docentrycost.
     *
     * @param array $values
     *
     * @return bool
     */
    public function PostCostingEntries(&$values)
    {
        $updatesInv = $values['_DOCPAR']['UPDATES_INV'];
        $inOut      = $values['_DOCPAR']['IN_OUT'];
        $category   = $values['_DOCPAR']['CATEGORY'];
        $spi        = $values['_DOCPAR']['SALE_PUR_TRANS'];
        $docid      = $values['_DOCPAR']['DOCID'];

        // if not updating inventory then no cogs posting
        // if inventory is not subscribed then look for enable_costing to post cogs
        if ($this->isInvInstalled)
        {
            if ($updatesInv == 'No')
            {
                return true;
            }
        }
        else
        {
            if ($values['_DOCPAR']['ENABLE_COSTING'] !== 'true')
            {
                return true;
            }
        }

        $gManagerFactory = Globals::$g->gManagerFactory;

        $itemMgr    = $gManagerFactory->getManager('item');
        $costingObj = $this->GetCostingObject();

        $ok = self::initializeCosting();

        // collect all item information
        $itemsArr = array();
        if ( ! isset($values['ENTRIES'])) {
            return true;        // nothing to generate
        }

        foreach ($values['ENTRIES'] as $entry)
        {
            if ( ! isset($entry['ITEMDETAILS'])) {
                continue;
            }
            foreach ($entry['ITEMDETAILS'] as $kitEntry) {

                if (isset($kitEntry['ITEMID']) && !in_array($kitEntry['ITEMID'], $itemsArr, true)) {
                    $itemsArr[] = $kitEntry['ITEMID'];
                }
            }
        }
        $itemRawCache      = $itemMgr->GetItemsRawCache($itemsArr, true);
        $nonInventoryItems = array('NI', 'NP', 'NS');

        $isReturn = false;
        if ($spi == 'Sale')
        {
            $isReturn = ($inOut == 'Increase');
        }
        else
        {
            if ($spi == 'Purchase')
            {
                $isReturn = ($inOut == 'Decrease');
            }
        }

        $skipUnchangedDocEntryCostRecords = DocumentManager::$upsertFeaturInUse;
        if (($values['BACKORDER'] ?? 'No') == 'Yes')
        {
            //creating back order for the document that affects value cannot be supported
            if ($updatesInv == 'Value' || $updatesInv == 'Quantity and Value')
            {
                return true;
            }
            // Backorders mess with docentrycostkeys and make it too hard to upsert for now.....
            if (DocumentManager::$upsertFeaturInUse) {
                DocumentEntryCostManager::deleteAllforDocHdr($values['RECORDNO']);
                $skipUnchangedDocEntryCostRecords = false;
            }
            $ok = $this->adjustCostingForBackOrder($values, $itemRawCache);
        }

        // If we may skip some docentrycost settings, that means they already exist on disk.
        // so, we need them to make the gl entries later.  Get them in bulk now:
        $docentrycostCache = [];
        if ($skipUnchangedDocEntryCostRecords) {
            $result = QueryResult([
                                    "SELECT dec.docentrykey, dec.itemkey, dec.unitcost, dec.quantity, dec.whencreated, dec.lastunitcost, dec.adjdocentrycostkey 
                                    FROM  docentrycost dec, docentrymst de
                                    WHERE dec.cny#=:1 AND de.cny#=:1
                                      AND dec.SYSTEMGENERATED = 'F'
                                      AND de.record# = dec.docentrykey
                                      AND de.dochdrkey = :2",
                                GetMyCompany(),
                                $values['RECORDNO']]);
            if ($result === false) {
                return false;   // ack!
            }
            foreach ($result as $row) {
                // note: only one warehouse per docentry, so....
                $docentrycostCache[$row['DOCENTRYKEY']][$row['ITEMKEY']][] = $row;
            }
        }

        // inout to find the source layer
        $sourceInOut = ($inOut == 'Increase') ? 'O' : 'I';
        $baseCurrencies = array();

        // PhpNext note: above we checked for existance....
        foreach ($values['ENTRIES'] as &$entry)      // we insured there was an array here above
        {
            $skipUpdatingThisRecord = false;

            // if we can skip records, and THIS record has not changed and item is not a non-inventory item, then
            //     we don't want to update the cost RECORDS, but we need the data for later GL updates....
            $upsertContext = [];
            if ($skipUnchangedDocEntryCostRecords && ( ! Matchmaker::needToUpdateLine($entry)) && $entry['ITEMTYPE'] !== 'NI') {
                $skipUpdatingThisRecord = true;
            } else {
                $upsertContext = DocumentEntryCostManager::prepareToAddOrUpsert($entry['RECORDNO']);
            }
            $entry['COST']  = 0;
            $findCost       = $this->needToFindCostLayers($docid, $spi, $inOut, $category, $updatesInv, $entry);

            //
            // get the location base currency
            $loc = $entry['LOCATION#'];
            if (!$values['CURRENCY'] || !$values['BASECURR']) {
                // GetLocationBaseCurrency will return GetBasecurrency if Location# is null
                $baseCurrencies[$loc] = $baseCurrencies[$loc] ?: GetLocationBaseCurrency($loc, false);
            }
            //
            // get the base currency of the location
            $basecurr = $values['BASECURR'] ?: $baseCurrencies[$loc];

            if (isset($entry['ITEMDETAILS'])) {
                foreach ($entry['ITEMDETAILS'] as &$kitEntry)      // we insured there was an array here above
                {
                    $kitItem = $itemRawCache[$kitEntry['ITEMID']];

                    if ($skipUpdatingThisRecord) {
                        $ok = $ok && $this->getCostingDetailsFromExisting($kitEntry, $entry['RECORDNO'], $docentrycostCache);
                    } else {
                        $ok = $ok && $this->getCostingDetails($kitEntry, $entry, $values, $kitItem, $isReturn, $sourceInOut, $findCost);
                    }
                    if (!$ok) {
                        break;
                    }

                    if (isset($kitEntry['COSTDETAILS'])) {
                        foreach ($kitEntry['COSTDETAILS'] as &$costDetails)     // we insured there was an array here above
                        {
                            $costDetails['ITEMID'] = $kitEntry['ITEMID'];
                            $costDetails['ITEMTYPE'] = $entry['ITEMTYPE'];
                            $costDetails['LOCATION'] = $entry['LOCATION'];
                            $costDetails['DEPARTMENT'] = $entry['DEPARTMENT'];
                            $costDetails['WAREHOUSE'] = array('LOCATION_NO' => $entry['WAREHOUSE']['LOCATION_NO']);
                            $costDetails['QUANTITY'] = $costDetails['QTY'];
                            $costDetails['VALUE'] = ibcmul($costDetails['QTY'] ?? '0', $entry['PRICE'], ItemManager::AVERAGE_COST_DECIMALS);
                            $costDetails['COST_METHOD'] = $kitEntry['COST_METHOD'];

                            $costDetails['TRX_VALUE'] = $costDetails['VALUE'];
                            //
                            // for Inventory Transactions & COGS the transaction currency should be in Basecurrency
                            $costDetails['BASECURR'] = $basecurr;
                            $costDetails['CURRENCY'] = $basecurr;
                            $costDetails['EXCHANGE_RATE'] = 1;

                            $kitItemGLGrpKey = $entry['ITEMGLGROUP'] ?? $values['ENTGLGROUP'];
                            $componentItemGlGrpKey = $kitItem['GLGRPKEY'];
                            if ($entry['COGS'] == 'K') {
                                //kit level revenue posting
                                $costDetails['ITEMGLGROUP'] = $kitItemGLGrpKey;
                                if ( $isReturn === false ) {
                                    //for invoices, we will take the credit side from the component
                                    $costDetails['CREDITITEMGLGROUP'] = $componentItemGlGrpKey;
                                } else {
                                    //for returns, we will take the debit side from the component
                                    $costDetails['DEBITITEMGLGROUP'] = $componentItemGlGrpKey;
                                }
                            } else {
                                //component level posting uses components itemglgroup
                                $costDetails['ITEMGLGROUP'] = $componentItemGlGrpKey;
                            }
                            // copy dimension fields from entry array to costkeyEntry
                            IADimensions::CopyIADimensionValues($entry, $costDetails, !util_isPlatformDisabled());
                        }
                        unset($costkeyEntry);
                    }

                    // no docentrycost record for non-inventory items
                    if (!in_array($kitItem['ITEMTYPE'], $nonInventoryItems) && $this->isInvInstalled) {
                        $ok = $ok && $costingObj->UpdateDocEntryCostEntries($upsertContext, $values, $entry, $kitEntry, $spi, $inOut, $updatesInv, $kitItem, $skipUpdatingThisRecord);
                    }
                }
                unset($kitEntry);
            }
            if (! $skipUpdatingThisRecord) {
                $ok = $ok && DocumentEntryCostManager::finishAddOrUpsert($upsertContext);   // for this docentry
            }
        }
        unset($entry);
        return $ok;
    }

    /**
     * @param string $docid
     * @param string $spi
     * @param string $inOut
     * @param string $category
     * @param string $updatesInv
     * @param array  $entry
     *
     * @return bool
     */
    private function needToFindCostLayers($docid, $spi, $inOut,
        /** @noinspection PhpUnusedParameterInspection */ $category, $updatesInv, $entry)
    {
        $findCost = false;
        if (empty($entry['ADJDOCENTRYKEY'])) {
            if ($spi == 'Sale') {
                $findCost = true;
            } else if ($spi == 'Purchase' && $inOut == 'Decrease') {
                $findCost = true;
            } else if ($spi == 'Internal' && $updatesInv != 'Value') {
                if ($inOut == 'Decrease') {
                    $findCost = true;
                } else if ($entry['SOURCE_DOCLINEKEY'] && $docid != ICTransferManager::INDOCTYPE) {

                    $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                        $entry['SOURCE_DOCLINEKEY'], $entry, false
                    );
                    if (!empty($rec)) {
                        $findCost = true;
                    }
                }
            }
        }

        return $findCost;
    }

    /**
     * @param array  $kitEntry
     * @param array  $entry
     * @param array  $values
     * @param array  $kitItem
     * @param bool   $isReturn
     * @param string $sourceInOut
     * @param bool   $findCost
     *
     * @return bool
     */
    private function getCostingDetails(&$kitEntry, &$entry, $values, $kitItem, $isReturn, $sourceInOut, $findCost)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;

        $inOut = $values['_DOCPAR']['IN_OUT'];
        $spi = $values['_DOCPAR']['SALE_PUR_TRANS'];

        $updatesInv = $values['_DOCPAR']['UPDATES_INV'];
        $itemMgr = $gManagerFactory->getManager('item');

        $nonInventoryItems = array('NI', 'NP', 'NS');
        $unitcost = $entry['PRICE'];
        $prevallocated = [];

        if ($kitItem['COST_METHOD'] == 'S') {
            $kitEntry['WHSE_STANDARD_COST'] = $itemMgr->GetStandardCost(
                $kitEntry['ITEMID'], $entry['WAREHOUSE']['LOCATION_NO'], $values['WHENCREATED']
            );
            $kitEntry['LASTUNITCOST'] = $kitEntry['WHSE_STANDARD_COST'];

            if (!$entry['ADJDOCENTRYKEY']) {
                // for standard cost items unitcost should be the standard cost
                $unitcost = $kitEntry['WHSE_STANDARD_COST'];
            }

        } else if ($kitItem['COST_METHOD'] == 'A') {
            $kitEntry['LASTUNITCOST'] = $itemMgr->GetAverageCost(
                $kitEntry['ITEMID'], $entry['WAREHOUSE']['LOCATION_NO'], $values['WHENCREATED']
            );
        }

        if (in_array($kitItem['ITEMTYPE'], $nonInventoryItems) || !$this->isInvInstalled) {

            if (
                $updatesInv != 'Quantity'
                && $spi == 'Sale'
                && $kitEntry['LASTUNITCOST'] > 0
            ) {

                $quantity = $kitEntry['QUANTITY'];

                //By this time we are expecting that Kit components quantity is expanded/computed.
                //Due to unknown reason at this point $kitEntry['QUANTITY'] is not expanded/computed.
                //Due to this reason we are computing the actual quantity of Kit Component as defined in Kit.
                if ($entry['ITEMTYPE'] == 'K' && $kitItem['ITEMTYPE'] != 'K') {
                    $quantity = ibcmul($entry['QUANTITY'], $kitEntry['QUANTITY'], ItemManager::BASEUNITPRECISION, true);
                }

                $costentry = array(
                    'UNITCOST' => $kitEntry['LASTUNITCOST'],
                    'COST' => ibcmul(
                        $kitEntry['LASTUNITCOST'], $quantity,
                        ItemManager::AVERAGE_COST_DECIMALS,
                        true
                    ),
                );

                $kitEntry['COSTDETAILS'][] = $costentry;
            }
        } else if ($findCost) {

            $costingObj = $this->GetCostingObject($kitItem['COST_METHOD']);

            $ok = $ok
                  && $costingObj->findCostingDetails(
                    $kitEntry, $entry, $values, $spi, $inOut, $sourceInOut, $isReturn, $kitItem, $updatesInv, $prevallocated
                );

        } else {
            if ($entry['ADJDOCENTRYKEY']) {
                $sourceDocEntryKey = $entry['ADJDOCENTRYKEY'];

                $multirec = DocumentEntryCostManager::getParentDocentryCostDetail(
                    $sourceDocEntryKey, $kitEntry, true,false
                );
                $adjDocEntryCostKey = $multirec[0]['RECORD#'];

                // docentcost should exist while adjusting existing document
                if (empty($adjDocEntryCostKey)) {

                    $msg = "Could not find the source cost record";
                    $gErr->addIAError('INV-0340', __FILE__ . ':' . __LINE__, $msg, []);
                    $ok = false;

                }

                // adjust the original layer 
                $kitEntry['ADJDOCENTRYCOSTKEY'] = $adjDocEntryCostKey;

            } else if ($updatesInv == 'Value') {
                $sourceDocEntryKey = $entry['SOURCE_DOCLINEKEY'];

                $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                    $sourceDocEntryKey, $kitEntry, false
                );
                $adjDocEntryCostKey = $rec['RECORD#'];

                $kitEntry['ADJDOCENTRYCOSTKEY'] = $adjDocEntryCostKey;
            }
            if(!isset($multirec)){
                $costentry[] = array(
                    'UNITCOST' => $unitcost,
                    'COST' => ibcmul(
                        $unitcost, $kitEntry['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS,
                        true
                    ),
                    'QTY' => $kitEntry['QUANTITY'],
                    'DATEIN' => $values['WHENCREATED'],
                    'WHSE_STANDARD_COST' => $kitEntry['WHSE_STANDARD_COST'],
                    'LASTUNITCOST' => $kitEntry['LASTUNITCOST'],
                    'ADJDOCENTRYCOSTKEY' => $kitEntry['ADJDOCENTRYCOSTKEY'],
                );
            }else{
                $totalQty = 0;
                foreach ($multirec as $row) {
                    $totalQty += $row['QUANTITY'];
                }
                $totalQty = ($totalQty != 0)? $totalQty : 1;
                $unitcostAndLc = $unitcost / $totalQty;
                foreach ($multirec as $row) {
                    $costentry[] = array(
                        'UNITCOST' => $unitcost,
                        'COST' => ibcmul(
                            ($unitcostAndLc * $row['QUANTITY']), $kitEntry['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS,
                            true
                        ),
                        'QTY' => $kitEntry['QUANTITY'],
                        'DATEIN' => $values['WHENCREATED'],
                        'WHSE_STANDARD_COST' => $kitEntry['WHSE_STANDARD_COST'],
                        'LASTUNITCOST' => $kitEntry['LASTUNITCOST'],
                        'ADJDOCENTRYCOSTKEY' => $row['RECORD#'],
                    );
                }
            }

            $kitEntry['COSTDETAILS'] = $costentry;
        }
        foreach ($kitEntry['COSTDETAILS'] ?? [] as $costkey => $costEntry) {
            $kitEntry['COSTDETAILS'][$costkey]['TRX_COST'] = $costEntry['COST'];
        }

        return $ok;
    }


    /**
     *      This should return a result as the above does, but from an exiting set of docentrycost records.
     *   Becuase of that, it can actually return MORE records than the above, and the data may not be as current
     *   as the data above (if, say, average cost changes).  But, the MIV tool can take care of that.
     *   What we're after here isn't docentrycost records, but fodder for the GL to post entries.
     *
     * @param array      $kitEntry              the item information
     * @param int        $docentryRecordno      the docentry
     * @param array      $docentrycostCache     cache of existing docentrycost records
     *
     * @return bool                 did it work?
     */
    private function getCostingDetailsFromExisting( & $kitEntry, $docentryRecordno, $docentrycostCache)
    {
        $kitEntry['COSTDETAILS'] = [];

        // This can generate more cost details entries than the above routine, in the cases of, say,
        //  bins, lots, sn's, multiple layers, etc.  But, for GL purposes, this is good enough.
        foreach ($docentrycostCache[$docentryRecordno][$kitEntry['ITEMID']] as $row) {

            $cost = ibcmul($row['QUANTITY'], $row['UNITCOST'], 2, true );

            $costentry = array(
                'UNITCOST'           => $row['UNITCOST'],
                'COST'               => $cost,                  // because $row[COST] is null
                'TRX_COST'           => $cost,
                'QTY'                => $row['QUANTITY'],
                'DATEIN'             => $row['WHENCREATED'],
                'WHSE_STANDARD_COST' => $row['UNITCOST'],       // if it is a standard cost item
                'LASTUNITCOST'       => $row['LASTUNITCOST'],
                'ADJDOCENTRYCOSTKEY' => $row['ADJDOCENTRYCOSTKEY'],
            );

            $kitEntry['COSTDETAILS'][] = $costentry;
        }

        return true;
    }


    /**
     *   Handle back orders
     *
     * @param array $values
     * @param array $itemRawCache
     *
     * @return bool
     */
    private function adjustCostingForBackOrder($values, $itemRawCache)
    {
        $ok = true;
        $spi = $values['_DOCPAR']['SALE_PUR_TRANS'];
        $inOut = $values['_DOCPAR']['IN_OUT'];
        // inout to find the source layer
        $sourceInOut = ($inOut == 'Increase') ? 'I' : 'O';
        
        $cny = GetMyCompany();
        $decMgr = Globals::$g->gManagerFactory->getManager('documententrycost');

        // lets make sure we have the array items we want.....
        if ( ! isset($values['ENTRIES'])) {
            $values['ENTRIES'] = [];
        }
        foreach ($values['ENTRIES'] as $key => $entry)
        {
            if ( ! isset($entry['ITEMDETAILS'])) {
                $values['ENTRIES'][$key]['ITEMDETAILS'] = [];
            } else {
                foreach ($entry['ITEMDETAILS'] as $key2 => $kitEntry) {
                    if ( ! isset($kitEntry['COSTDETAILS'])) {
                        $values['ENTRIES'][$key]['ITEMDETAILS'][$key2]['COSTDETAILS'] = [];
                    }
                }
            }
        }

        // because of the above, we know the arrays exist, though they may be empty
        foreach ($values['ENTRIES'] as $entry) {
            $srcRecordNo = $entry['SOURCE_DOCLINEKEY'];

            // if the source is not found then it might be new line added in back order
            // nothing to adjust here
            if (!$srcRecordNo) {
                continue;
            }

            foreach ( $entry['ITEMDETAILS']  as &$kitEntry) {

                $kitItem = $itemRawCache[$kitEntry['ITEMID']];

                if ($kitItem['ISSERIALIZED']) {
                    // only in case of back order need to free up the serialized item that was already sold
                    $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                        $entry['SOURCE_DOCLINEKEY'], $kitEntry, false
                    );

                    if ($rec) {
                        $docentrycostKeys = array($rec['RECORD#']);

                        $ok = $ok
                            && DocumentEntryCostManager::emptyDocentryCostKeys(
                                $docentrycostKeys, false, 'docentrycostkey'
                            );
                        $ok = $ok
                            && DocumentEntryCostManager::emptyDocentryCostKeys(
                                $docentrycostKeys, true, 'docentrycostkey'
                            );
                    }
                }

                $ok = $ok && $this->getCostingDetails($kitEntry, $entry, $values, $kitItem, true, $sourceInOut, true);

                $res = QueryResult(
                    array(
                        "select quantity, qty_converted from docentry where cny#=:1 and record#=:2", $cny, $srcRecordNo
                    )
                );
                $qtyAfterConverted = ibcsub($res[0]['QUANTITY'], $res[0]['QTY_CONVERTED'], ItemManager::BASEUNITPRECISION);

                foreach ($kitEntry['COSTDETAILS']  as $costkeyEntry) {

                    if ($qtyAfterConverted <= 0) {
                        break;
                    }

                    if (($qtyAfterConverted > $costkeyEntry['QTY'])) {
                        $quantity = $costkeyEntry['QTY'];
                        $qtyAfterConverted = ibcsub($qtyAfterConverted, $quantity, ItemManager::BASEUNITPRECISION);
                    } else {
                        $quantity = $qtyAfterConverted;
                        $qtyAfterConverted = 0;
                    }
                    if ($quantity > 0) {

                        $backOrderAdjEntry = array(
                            'DOCENTRYNO' => $entry['RECORDNO'],
                            'SALE_PUR_TRANS' => $spi,
                            'IN_OUT' => ($inOut == 'Increase') ? 'Decrease' : 'Increase',
                            'ITEMID' => $kitEntry['ITEMID'],
                            'WAREHOUSEID' => $entry['WAREHOUSE']['LOCATION_NO'],
                            'QUANTITY' => $quantity,
                            'CONTRIBUTEDQTY' => $quantity,
                            'COST' => 0,
                            'UNITCOST' => 0,
                            'LASTUNITCOST' => 0,
                            'CONTRIBUTEDCOST' => 0,
                            'DATEIN' => $entry['WHENCREATED'],
                            'VALUE' => 0,
                            'COST_METHOD' => $kitEntry['COST_METHOD'],
                            'SERIALNO' => $kitEntry['SERIALNO'],
                            'LOTNO' => $kitEntry['LOTNO'],
                            'AISLEKEY' => $kitEntry['AISLEKEY'],
                            'ROWKEY' => $kitEntry['ROWKEY'],
                            'BINKEY' => $kitEntry['BINKEY'],
                            'EXPIRATIONDATE' => $kitEntry['EXPIRATIONDATE'],
                            'AFFECTS_INVENTORY' => 'Quantity',
                            'SYSTEMGENERATED' => 'T',
                            'ADJDOCENTRYCOSTKEY' => $costkeyEntry['RECORD#'],
                        );

                        // unlink all associated documents
                        $docentrycostKeys = array($costkeyEntry['RECORD#']);

                        $ok = $ok
                            && DocumentEntryCostManager::emptyDocentryCostKeys(
                                $docentrycostKeys, false, 'docentrycostkey'
                            );
                        $ok = $ok
                            && DocumentEntryCostManager::emptyDocentryCostKeys(
                                $docentrycostKeys, true, 'docentrycostkey'
                            );

                        $ok = $ok && $decMgr->add($backOrderAdjEntry);
                    }
                }
            }
        }
        return $ok;
    }

}

