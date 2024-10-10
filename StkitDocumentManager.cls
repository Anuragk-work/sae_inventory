<?
/**
 * Manager class for build and disassemble kits
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

define('BUILD_KIT', 'Build Kits');
define('DIS_KIT', 'Disassemble Kits');

class StkitDocumentManager extends InvDocumentManager
{
    const BUILDKIT = "Build Kits";
    const DISKIT = "Disassemble Kits";

    /**
     * @var bool $isStockableKitTrackingEnabled True if stockable kit tracking enabled, false otherwise
     */
    private static $isStockableKitTrackingEnabled = null;

    /**
     * @var bool $isStockableKitComponentTrackingEnabled True if stockable kit component tracking enabled, false otherwise
     */
    private static $isStockableKitComponentTrackingEnabled = null;

    /**
     * Adjust component tracking information from the TRACKINGENTRIES since these should
     * be saved in the docentrytrackdetails with component id instead of SK id as itemkey.
     *
     * @param [] $entries
     */
    private static function adjustComponentTrackingEntries(&$entries)
    {
        foreach ( $entries ?? [] as $line => $entry ) {
            $trackDetails = $entry['TRACKINGENTRIES'] ?? [];
            for ( $i = count($trackDetails) - 1 ; $i >= 0; --$i ) {
                if (isset($trackDetails[$i]['COMPONENTID']) && !empty($trackDetails[$i]['COMPONENTID'])) {
                    // Replace itemid with componentid
                    $entries[$line]['TRACKINGENTRIES'][$i]['ITEMID'] =
                        $entries[$line]['TRACKINGENTRIES'][$i]['COMPONENTID'];
                }
            }
        }
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $gErr = Globals::$g->gErr;

        $source = "StKitDocumentManager::Add";
        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not create build/disassemble document";
            $gErr->addError('INV-0921', __FILE__ . ':' . __LINE__, $msg);
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
        $gErr = Globals::$g->gErr;

        $source = "StKitDocumentManager::Set";
        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not update build/disassemble document";
            $gErr->addError('INV-0922', __FILE__ . ':' . __LINE__, $msg);
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param string $ID
     *
     * @return bool
     */
    function Delete($ID)
    {
        $gErr = Globals::$g->gErr;

        $source = "StKitDocumentManager::Delete";
        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && parent::Delete($ID);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not delete build/disassemble document";
            $gErr->addError('INV-0923', __FILE__ . ':' . __LINE__, $msg);
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param array             $values
     * @param TrackingHandler[] $handlers
     * @param bool              $newdoc
     * @param array|null        $getTaxRequest
     * @param string|null       $entityTaxable

     * @return bool
     */
    function PrepValues(&$values, $handlers, $newdoc = true, &$getTaxRequest = null, &$entityTaxable = null)
    {
        $gErr = Globals::$g->gErr;
        global $gManagerFactory;
        $ok = true;

        if ($values['DOCPARID'] == self::DISKIT) {
            if (empty($values['CREATEDFROM'])) {
                $msg = 'Disassemble kits should be converted from build kits';
                $gErr->addIAError(
                    'INV-0924', __FILE__ . ':' . __LINE__,
                    'Error converting ' . $values['CREATEDFROM'],
                    ['VALUES_CREATEDFROM'=>$values['CREATEDFROM']],
                    $msg,
                    [],
                    'Invalid Operation',
                    []
                );
                $ok = false;
            }
            $ok = $ok && prepareDisassemblyFromBuild($values);
            $ok = $ok && $this->checkForNegativeInventory($values, 'D', true ); // pretend we're deleting and called BEFORE saving

            // Sanity check on matching Build and Disassembly entry quantities
            $docEntryMgr    = $gManagerFactory->getManager('stkitdocumententry');
            $entryQuerySpec = ['selects' => ['LINE_NO', 'ITEMID', 'QUANTITY'], 'filters' => [[['DOCID', '=', $values['CREATEDFROM']]]]];
            $bldEntries = $docEntryMgr->GetList($entryQuerySpec);
            $bldEntries = array_column($bldEntries, null, 'LINE_NO');
            foreach ($values['ENTRIES'] ?? [] as $lineNumber => $entry) {
                $buildQuantity = $bldEntries[$lineNumber]['QUANTITY'] ?? 0;
                $disassembleQuantity = $entry['UIQTY'] ?? 0;
                if (ibccomp($buildQuantity, $disassembleQuantity, ItemManager::BASEUNITPRECISION) != 0) {
                    $gErr->addIAError(
                        'INV-1450', __FILE__ . ':' . __LINE__,
                        "Disassembly quantity ${disassembleQuantity} is different from build quantity ${buildQuantity} on line ${lineNumber}.",
                        ['LINENO' => $lineNumber + 1, 'BLD_QTY' => $buildQuantity, 'DIS_QTY' => $disassembleQuantity],
                        '', [], 'Use the same quantity to disassemble.', []
                    );
                    $ok = false;
                    break;
                }
            }
        }

        $ok = $ok && parent::PrepValues($values, $handlers, $newdoc);

        if (self::isStockableKitComponentTrackingEnabled() && $values['DOCPARID'] == self::BUILDKIT) {
            // Component tracking details are only required for costing; no need to preserve them beyond this point.
            self::adjustComponentTrackingEntries($values['ENTRIES']);
        }

        $ok = $ok && $this->getCostingDetails($values);

        $ok = $ok && $this->populateCostInLineItem($values);

        return $ok;
    }


    /**
     *      If we are about to delete a transaction that would make ONHAND go negative, and we don't allow
     *  going negative, then don't let the customer delete this transaction.
     *
     * @param array    $docObj
     * @param string   $addUpdateOrDelete    'A' - adding a txn, 'U' - updating, 'D' - deleting
     * @param bool     $beforeSave           Are we being called BEFORE or AFTER the EntityManager save?
     * @param callback $errorReporter         callback to display the error, so this can be used by more than just
     *                                        delete. call with the item and warehouse in error
     *
     * @return bool
     */
    protected function checkForNegativeInventory(&$docObj, $addUpdateOrDelete, $beforeSave, $errorReporter = null)
    {
        if ($errorReporter === null) {
            $errorReporter = function ($itemid, $warehouseid, $quantity, $datein, $docid) {
                $msg = "Disassembling this kit will cause ON-HAND to be negative for item $itemid in warehouse $warehouseid.";
                $addl = '';
                $placeholder = [];
                $errorCode  = 'INV-0997';
                $placeholder = ['QUANTITY'=>$quantity,'DATEIN' => $datein];
                if ($docid !== '') {
                    $addl = "or delete '$docid',";
                    $errorCode  = 'INV-0998';
                    $placeholder = array_merge($placeholder, ['DOCID' => $docid]);
                }
                $corr = "Receive at least $quantity more of the kit into inventory as of $datein, $addl then try again.";
                Globals::$g->gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__,
                    $msg,
                    ['ITEMID'=>$itemid,'WAREHOUSEID'=>$warehouseid],
                    '',
                    [],
                    $corr,
                    $placeholder
                );
                // i18N::TODO - (Code Change Review).
            };
        }

        //If we are disassembling, then we can't be adding (A), we should be updating.
        //This is crucial as the call to parent::checkForNegativeInventory will not check for negative if adding
        if ($docObj['DOCPARID'] === self::DISKIT && $addUpdateOrDelete === 'A') {
            $addUpdateOrDelete = 'U';
        }

        // $docObj is by value, so no need to worry here....
        $oldDocPar = $docObj['_DOCPAR']['IN_OUT'];
        $docObj['_DOCPAR']['IN_OUT'] = 'Increase'; // just pretend, as we're deleting a build kit, essentially
        $ok = parent::checkForNegativeInventory( $docObj, $addUpdateOrDelete, $beforeSave, $errorReporter );
        $docObj['_DOCPAR']['IN_OUT'] = $oldDocPar;
        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    private function getCostingDetails(&$values)
    {
        //Draft state, we don't need to get costing details for the entries
        if ($values['STATE'] == self::DRAFT_STATE && self::isStockableKitTrackingEnabled()) {
            return true;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;

        $costingHandler = $this->get_costing_handler();
        $itemMgr = $gManagerFactory->getManager('item');
        $ok = true;

        $updatesInv = $values['_DOCPAR']['UPDATES_INV'];
        $inOut = $values['_DOCPAR']['IN_OUT'];
        $spi = $values['_DOCPAR']['SALE_PUR_TRANS'];
        $isReturn = ($inOut == 'Decrease');

        // inout to find the source layer
        $sourceInOut = ($values['DOCPARID'] == self::BUILDKIT) ? 'I' : 'O';

        $itemsArr = array();
        foreach ( $values['ENTRIES'] as $entry) {
            foreach ( $entry['ITEMDETAILS'] as $kitEntry) {
                if ($kitEntry['ITEMID'] != '' && !in_array($kitEntry['ITEMID'], $itemsArr, true)) {
                    $itemsArr[] = $kitEntry['ITEMID'];
                }
            }
        }

        $prevallocated = [];

        /*
         * NOTE: We can't use array_merge() here; when the itemids look like numbers ("is_numeric()"),
         * array_merge() will convert them to numbers, and then compact them as continguous numeric
         * indices to the resultant array.
         *
         * E.g., Given:
         * $a = ["Item01" => "Stuff" ];
         * $b = ["12345" => "More Stuff"];
         * Then array_merge() will combine them into:
         * [
         *     'Item01' => 'Stuff',
         *     0 => 'More Stuff',
         * ]
         *
         * And so, subsequent searches for the original itemid will come up empty.
         * The solution is to either use the array union (+) operator, or array_replace().
         */
        $this->itemRawCache = $this->itemRawCache + $itemMgr->GetItemsRawCache($itemsArr, true);
        foreach ( $values['ENTRIES'] as &$entry) {
            foreach ( $entry['ITEMDETAILS'] as &$kitEntry) {
                if ( $values['DOCPARID'] == self::DISKIT && $entry['ITEMID'] == $kitEntry['ITEMID']) {
                    // No costing layer for SK, only its components
                    continue;
                }

                $kitItem = $this->itemRawCache[$kitEntry['ITEMID']];

                $costingObj = $costingHandler->GetCostingObject($kitItem['COST_METHOD']);

                $ok = $ok
                      && $costingObj->findCostingDetails(
                        $kitEntry, $entry, $values, $spi, $inOut, $sourceInOut, $isReturn, $kitItem, $updatesInv, $prevallocated
                    );

                if ( ! empty($kitEntry['COSTDETAILS']) ) {
                    foreach ($kitEntry['COSTDETAILS'] as &$costkeyEntry) {

                        $item = $this->itemRawCache[$kitEntry['ITEMID']];

                        $costkeyEntry['ITEMID'] = $kitEntry['ITEMID'];
                        $costkeyEntry['ITEMTYPE'] = $entry['ITEMTYPE'];
                        $costkeyEntry['LOCATION'] = ($costkeyEntry['LOCATION'] ?: $entry['LOCATION']);
                        $costkeyEntry['DEPARTMENT'] = $entry['DEPARTMENT'];
                        $costkeyEntry['WAREHOUSE'] = array('LOCATION_NO' => $entry['WAREHOUSE']['LOCATION_NO'],);
                        $costkeyEntry['QUANTITY'] = $costkeyEntry['QTY'];
                        /** @noinspection PhpSillyAssignmentInspection */
                        $costkeyEntry['COST'] = $costkeyEntry['COST'];
                        $costkeyEntry['VALUE'] = iround($costkeyEntry['COST'], DEFAULT_INVPRECISION);
                        $costkeyEntry['COST_METHOD'] = $kitEntry['COST_METHOD'];
                        $costkeyEntry['ITEMGLGROUP'] = $item['GLGRPKEY'];

                    }
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */

    private function populateCostInLineItem(&$values)
    {
        $ok = true;

        //    Because the records are different from draft to post,  need to do a more complicated calculation.
        //    For each item
        //    Sum the  unit cost * number of items.   Sum(cost * # items)
        //    Sum the count of items       sum (count)
        //    Divide the summed cost by the summed number of items   to get unit cost       unit cost = Sum(cost * # items)/ sum (count)
        //    Multiply by the unit cost by  quantity in the kit.           item cost for kit.   = unit cost * items per kit
        //    Add to the cost of the other items.   Kit cost =  kit cost + item cost for kit.
        /*
         * Slight change to calculation above, to take tracking into account. To properly account for tracked
         * stockable kits and components, the itemdetails for a given SK may be split to represent tracked SK groupings,
         * and in all cases for tracked components the quantities are broken out (not per-SK quantities as when
         * untracked) since the component tracking specifications may span SK tracking specifications (e.g., 2 SK
         * lots being built, all from 1 component lot). Therefore, the calculation is reversed from before--first
         * determine the total cost for the entry (since tracked itemdetails simply need to be summed to get there),
         * and then divide by entry (SK) quantity to obtain the unit cost (per SK).
         */
        foreach ($values['ENTRIES'] as $key => $entry) {
            $trackedKitCost = 0;
            $untrackedKitCost = 0;
            foreach ( $entry['ITEMDETAILS'] as $costEntry) {
                $isTracked = self::isStockableKitAndComponentTrackingEnabled() && $this->isTracked($costEntry);
                $componentqty = '0';
                $componentvalue = '0';
                foreach ( $costEntry['COSTDETAILS'] as $costkeyEntry) {
                    // sum the cost of the individual components
                    // the cost may come from multiple cost entries which may have different costs
                    // compute the total cost for all of this component
                    $componentqty = ibcadd($componentqty, $costkeyEntry['QTY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                    $componentcost = ibcmul ($costkeyEntry['QTY'], $costkeyEntry['UNITCOST'], ItemManager::AVERAGE_COST_DECIMALS,true);
                    $componentvalue = ibcadd($componentcost, $componentvalue, ItemManager::AVERAGE_COST_DECIMALS, true);
                }
                // determine the unit cost for the item
                $componentavecost = $componentqty == 0 ? '0': ibcdiv($componentvalue, $componentqty, ItemManager::AVERAGE_COST_DECIMALS, true);
                // determine the unit cost * items for this ITEMDETAIL (may represent only part of an SK if tracked)
                $itemDetailMultiplier = $isTracked ? $costEntry['QUANTITY'] : $costEntry['KITQUANTITY'];
                $componentkitcost  = ibcmul($componentavecost, $itemDetailMultiplier, ItemManager::AVERAGE_COST_DECIMALS, true);
                // add to total cost of the kit.
                if ($isTracked) {
                    // These sum directly to total tracked component costs
                    $trackedKitCost =
                        ibcadd($trackedKitCost, $componentkitcost, ItemManager::AVERAGE_COST_DECIMALS, true);
                } else {
                    // These sum to per-unit (per SK) untracked component costs
                    $untrackedKitCost =
                        ibcadd($untrackedKitCost, $componentkitcost, ItemManager::AVERAGE_COST_DECIMALS, true);;
                }
            }

            // so COST is the overall cost of the transaction (the TOTAL COST)
            $totalCost = ibcadd($trackedKitCost, ibcmul($untrackedKitCost, $values['ENTRIES'][$key]['QUANTITY'],
                                                        ItemManager::AVERAGE_COST_DECIMALS),
                                ItemManager::AVERAGE_COST_DECIMALS);
            $kitcost =
                ibcdiv($totalCost, $values['ENTRIES'][$key]['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);

            // PRICE, UI_PRICE, TRX_PRICE is the UNIT COST (cost of ONE kit)
            $values['ENTRIES'][$key]['TRX_PRICE']   = $kitcost;
            $values['ENTRIES'][$key]['UIPRICE']     = $kitcost;
            $values['ENTRIES'][$key]['PRICE']       = $kitcost;

            $values['ENTRIES'][$key]['COST'] = $totalCost;

            // VALUE is the COST, rounded
            $totalCost = iround($totalCost, 2);
            $values['ENTRIES'][$key]['TRX_VALUE'] = $totalCost;
            $values['ENTRIES'][$key]['UIVALUE'] = $totalCost;
            $values['ENTRIES'][$key]['VALUE'] = $totalCost;
        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function postCostingEntries(&$values)
    {
        $ok = CostingHandler::initializeCosting();

        $inOut = $values['_DOCPAR']['IN_OUT'];
        $spi = $values['_DOCPAR']['SALE_PUR_TRANS'];
        $updatesInv = $values['_DOCPAR']['UPDATES_INV'];

        foreach ( $values['ENTRIES'] as $entry) {
            $ok = $ok && $this->processkitEntries($entry, $spi, $inOut, $updatesInv, $values['DOCPARID']);
            $ok = $ok && $this->processComponents($entry, $spi, $inOut, $updatesInv);
        }
        return $ok;
    }

    /**
     * @param array  $entry
     * @param string $spi
     * @param string $inOut
     * @param string $updatesInv
     *
     * @return bool
     */
    private function processComponents($entry, /** @noinspection PhpUnusedParameterInspection */ $spi, $inOut,
        /** @noinspection PhpUnusedParameterInspection */ $updatesInv) {
        if (self::isStockableKitTrackingEnabled() && $this->isTracked($entry)) {
            return $this->processComponentsForTrackedSK($entry, $spi, $inOut, $updatesInv);
        } else {
            return $this->processComponentsForUntrackedSK($entry, $spi, $inOut, $updatesInv);
        }
    }

    /**
     * @param array  $entry
     * @param string $spi
     * @param string $inOut
     * @param string $updatesInv
     *
     * @return bool
     */
    private function processComponentsForUntrackedSK($entry, /** @noinspection PhpUnusedParameterInspection */ $spi, $inOut,
        /** @noinspection PhpUnusedParameterInspection */ $updatesInv)
    {
        $gErr = Globals::$g->gErr;

        //components should be decreased while stockable kit is increased
        $inOut = ($inOut == 'Increase') ? 'Decrease' : 'Increase';
        $ok = true;

        $newDocEntryCostKits = [];
        $docentrycostkitKeys = [];
        if (isset($entry['ITEMDETAILS'])) {
            foreach ($entry['ITEMDETAILS'] as $key => $costEntry) {
                if (isset($costEntry['COSTDETAILS'])) {
                    foreach ($costEntry['COSTDETAILS'] as $costkeyEntry) {
                        // Do the insert
                        $newEntry = array(
                            'DOCENTRYNO'        => $entry['RECORDNO'],
                            'IN_OUT'            => $inOut,
                            'ITEMID'            => $costkeyEntry['ITEMID'],
                            'WAREHOUSEID'       => $costkeyEntry['WAREHOUSE']['LOCATION_NO'],
                            'QUANTITY'          => $costkeyEntry['QTY'],
                            'COST'              => $costkeyEntry['COST'],
                            'UNITCOST'          => $costkeyEntry['UNITCOST'],
                            'LASTUNITCOST'      => $costkeyEntry['UNITCOST'],
                            'DATEIN'            => $entry['WHENCREATED'],
                            'STATUS'            => 'active',
                            'COST_METHOD'       => $costkeyEntry['COST_METHOD'],
                            'SERIALNO'          => $entry['ITEMDETAILS'][$key]['SERIALNO'],
                            'LOTNO'             => $entry['ITEMDETAILS'][$key]['LOTNO'],
                            'AISLEKEY'          => $entry['ITEMDETAILS'][$key]['AISLEKEY'],
                            'ROWKEY'            => $entry['ITEMDETAILS'][$key]['ROWKEY'],
                            'BINKEY'            => $entry['ITEMDETAILS'][$key]['BINKEY'],
                            'ITEMGLGRPKEY'      => $costkeyEntry['ITEMGLGROUP'],
                            'EXPIRATIONDATE'    => $entry['ITEMDETAILS'][$key]['EXPIRATIONDATE'],
                            'AFFECTS_INVENTORY' => 'QV',
                        );

                        if (isset($costkeyEntry['RECORD#'])) {
                            if ($inOut == 'Increase') {
                                $docentrycostkitKeys[] = $costkeyEntry['RECORD#'];
                                $newEntry['DOCENTRYCOSTKITKEY'] = $costkeyEntry['RECORD#'];
                            } else {
                                $newEntry['DOCENTRYCOSTKEY'] = $costkeyEntry['RECORD#'];
                            }

                        } else {
                            if ($inOut == 'Decrease' && !IsNegativeInventoryAllowed()) {
                                $gErr->addIAError(
                                    'INV-0925', __FILE__ . ":" . __LINE__,
                                    "Insufficient quantity available for building kit.",
                                    [],
                                    "The quantity is not sufficient for the item '" . $costkeyEntry['ITEMID'] . "'",
                                    ['COSTKEY_ENTRY_ITEMID'=>$costkeyEntry['ITEMID']],
                                    'Ensure that enough quantity is available for the component',
                                    []
                                );
                                $ok = false;
                            } else if ($inOut == 'Increase') {
                                $gErr->addError(
                                    'INV-0259', __FILE__ . ":" . __LINE__,
                                    "Could not find build kits entries.",
                                    "It is either disassembled or wrong build kits document given",
                                    'Please ensure that correct build kits document given'
                                );
                                $ok = false;
                            }
                        }
                        $newDocEntryCostKits[] = $newEntry;
                    }
                }
            }
        }

        // update build kits docentrycostkeys to null to release quantities.
        if ($inOut == 'Increase' && !empty($docentrycostkitKeys)) {
            $ok = $ok && DocumentEntryCostManager::emptyDocentryCostKeys($docentrycostkitKeys, true);
        }

        // now add the records
        $ok = $ok && StkitDocumentEntryCostManager::addOrUpsert($entry['RECORDNO'], $newDocEntryCostKits);

        return $ok;
    }

    /**
     * @param array  $entry
     * @param string $spi
     * @param string $inOut
     * @param string $updatesInv
     *
     * @return bool
     */
    private function processComponentsForTrackedSK($entry, /** @noinspection PhpUnusedParameterInspection */ $spi, $inOut,
        /** @noinspection PhpUnusedParameterInspection */ $updatesInv)
    {
        $gErr = Globals::$g->gErr;

        //components should be decreased while stockable kit is increased
        $inOut = ($inOut == 'Increase') ? 'Decrease' : 'Increase';
        $ok = true;
        $isTracked = self::isStockableKitTrackingEnabled() && $this->isTracked($entry);

        $newDocEntryCostKits = [];
        $docentrycostkitKeys = [];
        if ( isset($entry['ITEMDETAILS']) ) {
            /*
             * ITEMDETAILS may represent multiple components, and may also represent multiple specifications
             * per component. Group by component so that we can consume the cost layer quantities correctly
             * for each component.
             */
            $itemDetailsPerComponent = self::separateItemdetailsByComponent($entry['ITEMDETAILS']);
            foreach ( $itemDetailsPerComponent as $itemDetails ) {
                // Here we are iterating over each component
                $allEntryCostRecs =
                    DocumentEntryCostManager::getParentDocentryCostDetail($entry['RECORDNO'], $entry, true, false);
                foreach ( $itemDetails as $costEntry ) {
                    // Here we are iterating over each tracking specification for a given component
                    if ( isset($costEntry['COSTDETAILS']) ) {
                        foreach ( $costEntry['COSTDETAILS'] as $costkeyEntry ) {
                            if ( $isTracked && $inOut == 'Decrease' ) {
                                $entryCostRecs = &$allEntryCostRecs;
                            } else {
                                $entryCostRecs = [ $costkeyEntry ];
                            }
                            while ( ! empty($entryCostRecs) ) {
                                /*
                                 * Prepare the new record.
                                 *
                                 * The $entryCostRec is the innermost (component) boundary, but it can only consume up to
                                 * ($costKeyEntry['QUANTITY'] * $costEntry['KITQUANTITY']) at a time (if that's less than
                                 * $entryCostRec['QUANTITY'], as might happen if the SK itself is tracked and distributed
                                 * across multiple tracking specifications).
                                 *
                                 * If either of $costKeyEntry['QUANTITY'] or $entryCostRec['QUANTITY'] is exhausted, then
                                 * move to the next respective one.
                                 *
                                 * The cost must likewise be apportioned according to the quantity being consumed.
                                 */
                                $entryCostRec = &$entryCostRecs[0];
                                $componentQty = ibcmul($entryCostRec['QUANTITY'], $costEntry['KITQUANTITY'],
                                    ItemManager::BASEUNITPRECISION);
                                // Save a running count of remaining qty for this SK docentrycost, for this component
                                if (empty($entryCostRec['THIS_COMPONENT_QUANTITY'])) {
                                    $entryCostRec['THIS_COMPONENT_QUANTITY'] = $componentQty;
                                }
                                $currentRecordQuantity = min($costkeyEntry['QUANTITY'],$componentQty);
                                $apportionedCost = ibcmul($currentRecordQuantity, $costkeyEntry['UNITCOST'],
                                                          ItemManager::AVERAGE_COST_DECIMALS);
                                $newEntry = [
                                    'DOCENTRYNO'        => $entry['RECORDNO'],
                                    'IN_OUT'            => $inOut,
                                    'ITEMID'            => $costkeyEntry['ITEMID'],
                                    'WAREHOUSEID'       => $costkeyEntry['WAREHOUSE']['LOCATION_NO'],
                                    'QUANTITY'          => $currentRecordQuantity,
                                    'COST'              => $apportionedCost,
                                    'UNITCOST'          => $costkeyEntry['UNITCOST'],
                                    'LASTUNITCOST'      => $costkeyEntry['UNITCOST'],
                                    'DATEIN'            => $entry['WHENCREATED'],
                                    'STATUS'            => 'active',
                                    'COST_METHOD'       => $costkeyEntry['COST_METHOD'],
                                    'SERIALNO'          => $costEntry['SERIALNO'],
                                    'LOTNO'             => $costEntry['LOTNO'],
                                    'AISLEKEY'          => $costEntry['AISLEKEY'],
                                    'ROWKEY'            => $costEntry['ROWKEY'],
                                    'BINKEY'            => $costEntry['BINKEY'],
                                    'ITEMGLGRPKEY'      => $costkeyEntry['ITEMGLGROUP'],
                                    'EXPIRATIONDATE'    => $costEntry['EXPIRATIONDATE'],
                                    'AFFECTS_INVENTORY' => 'QV',
                                ];

                                if ( $isTracked && $inOut == 'Decrease' ) {
                                    // When building, remember the origin SK docentrycost (per each component docentrycost)
                                    $newEntry['BUILDCOSTKEY'] = $entryCostRec['RECORD#'];
                                }

                                if ( isset($costkeyEntry['RECORD#']) ) {
                                    if ( $inOut == 'Increase' ) {
                                        $docentrycostkitKeys[] = $costkeyEntry['RECORD#'];
                                        $newEntry['DOCENTRYCOSTKITKEY'] = $costkeyEntry['RECORD#'];
                                    } else {
                                        $newEntry['DOCENTRYCOSTKEY'] = $costkeyEntry['RECORD#'];
                                    }
                                } else {
                                    if ( $inOut == 'Decrease' && ! IsNegativeInventoryAllowed() ) {
                                        $gErr->addIAError(
                                            'INV-0999', __FILE__ . ":" . __LINE__,
                                            "Insufficient quantity available for building kit.",
                                            [],
                                            "The quantity is not sufficient for the item '" . $costkeyEntry['ITEMID']
                                            . "'",
                                            ['COSTKEY_ENTRY_ITEMID'=>$costkeyEntry['ITEMID']],
                                            'Ensure that enough quantity is available for the component',
                                            []
                                        );
                                        $ok = false;
                                    } else if ( $inOut == 'Increase' ) {
                                        $gErr->addError(
                                            'INV-0260', __FILE__ . ":" . __LINE__,
                                            "Could not find build kits entries.",
                                            "It is either disassembled or wrong build kits document given",
                                            'Please ensure that correct build kits document given'
                                        );
                                        $ok = false;
                                    }
                                }
                                $newDocEntryCostKits[] = $newEntry;

                                // Decrement the amount of this SK docentrycost consumed by the current component
                                $entryCostRec['THIS_COMPONENT_QUANTITY'] -= $currentRecordQuantity;
                                $costkeyEntry['QUANTITY'] -= $currentRecordQuantity;
                                if ( $entryCostRec['THIS_COMPONENT_QUANTITY'] == 0 ) {
                                    // Remove this from further consideration
                                    array_shift($entryCostRecs);
                                }
                                if ( $costkeyEntry['QUANTITY'] == 0 ) {
                                    // Move to the next COSTDETAIL record
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // update build kits docentrycostkeys to null to release quantities.
        if ($inOut == 'Increase' && !empty($docentrycostkitKeys)) {
            $ok = $ok && DocumentEntryCostManager::emptyDocentryCostKeys($docentrycostkitKeys, true);
            if ( $isTracked ) {
                $ok = $ok
                      && DocumentEntryCostManager::emptyDocentryCostKeys(
                        $docentrycostkitKeys, true, 'record#', 'buildcostkey');
            }
        }

        // now add the records
        $ok = $ok && StkitDocumentEntryCostManager::addOrUpsert($entry['RECORDNO'], $newDocEntryCostKits);

        return $ok;
    }

    /**
     * @param array $itemdetails The Entry's ITEMDETAILS
     *
     * @return array The ITEMDETAILS grouped by component
     */
    private static function separateItemdetailsByComponent($itemdetails)
    {
        $itemdetailsByComponent = [];
        foreach ( $itemdetails as $itemdetail ) {
            $itemId = $itemdetail['ITEMID'];
            if ( ! empty($itemdetailsByComponent[$itemId]) ) {
                $itemdetailsByComponent[$itemId][] = $itemdetail;
            } else {
                $itemdetailsByComponent[$itemId] = [ $itemdetail ];
            }
        }

        return $itemdetailsByComponent;
    }

    /**
     * @param int   $docEntryKey
     * @param array $entry
     * @param bool  $noSource
     *
     * @return mixed
     */
    private static function getBuildDocentryCostKitsDetail($docEntryKey, $entry, $noSource)
    {
        $itemID = $entry['ITEMID'];
        $sNo = $entry['SERIALNO'];
        $lNo = $entry['LOTNO'];
        $aisle = $entry['AISLEKEY'];
        $row = $entry['ROWKEY'];
        $bin = $entry['BINKEY'];

        $where = "where cny# = :1 AND affects_inventory != 'Q' AND itemkey = :3 ";

        $qry = [];
        $qry[] = '';
        $qry[] = GetMyCompany();
        $qry[] = $docEntryKey;
        $qry[] = $itemID;
        $bind = count($qry);

        if ( $sNo ) {
            $where .= " AND serialno = :" . $bind++;
            $qry[] = $sNo;
        }

        if ( $lNo ) {
            $where .= " AND lotno = :" . $bind++;
            $qry[] = $lNo;
        }

        if ( $aisle ) {
            $where .= " AND aislekey = :" . $bind++;
            $qry[] = $aisle;
        }

        if ( $row ) {
            $where .= " AND rowkey = :" . $bind++;
            $qry[] = $row;
        }

        if ( $bin ) {
            $where .= " AND binkey = :" . $bind; // Last instance of $bind so no ++
            $qry[] = $bin;
        }

        $where .= " AND exists ( select 1 from docentrycostkits where buildcostkey = docentrycost.record# )";

        if ( $noSource ) {
            $qry[0] = "select * from docentrycost $where
                    AND docentrykey = :2 order by datein desc, record# desc";
        } else {
            $qry[0] = "select * from docentrycost $where
                    AND docentrykey in (
                      select record# from docentrymst where cny# = :1 START WITH cny# = :1 AND record# = :2  
                      CONNECT BY cny# = :1 and record# = PRIOR source_doclinekey
                    ) order by datein desc, record# desc";
        }

        $res = QueryResult($qry);

        return $res;
    }

    /**
     * @param array  $entry
     * @param string $spi
     * @param string $inOut
     * @param string $updatesInv
     * @param string $docparID
     *
     * @return bool
     */
    private function processkitEntries($entry, /** @noinspection PhpUnusedParameterInspection */ $spi, $inOut,
        /** @noinspection PhpUnusedParameterInspection */ $updatesInv, $docparID)
    {

        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $decMgr = $gManagerFactory->getManager('documententrycost');
        $ok = true;
        $docentrycostkey = null;
        $sourceDocentrycostKeys = [];

        if ($docparID == self::DISKIT) {
            $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                $entry['SOURCE_DOCLINEKEY'], $entry, false
            );
            $docentrycostkey = $rec['RECORD#'];
            $sourceDocentrycosts = self::getBuildDocentryCostKitsDetail($rec['DOCENTRYKEY'], $entry, true);
            foreach ( $sourceDocentrycosts as $sourceDocentrycost ) {
                $sourceDocentrycostKeys[] = $sourceDocentrycost['RECORD#'];
            }

            if (empty($docentrycostkey)) {
                $gErr->addError(
                    'INV-0261', __FILE__ . ":" . __LINE__,
                    "Could not find build kits entries.",
                    "It is either disassembled or wrong build kits document given",
                    'Please ensure that correct build kits document given'
                );

                $ok = false;
            } else {
                // Disassembly is only possible if the Stockable Kits from this build have
                // not yet been consumed.
                $ok = $ok && $this->isNotTrackedAndReferenced($sourceDocentrycostKeys, $entry);

                // unlink if the stockable kit is consumed in any other document
                $docentrycostKeys = !empty($sourceDocentrycostKeys) ? $sourceDocentrycostKeys : array($docentrycostkey);

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

        if (self::isStockableKitTrackingEnabled() && $this->isTracked($entry)) {
            // Tracking specification present--possibly multiple for this one entry (e.g., unique serial numbers per SK item)
            if (!$this->areTrackingQuantitiesCorrect($entry)) {
                $gErr->addError(
                    'INV-0262', __FILE__ . ":" . __LINE__,
                    "Tracking quantity mismatch.",
                    "The quantity specified for tracking must match the item quantity",
                    'Ensure that the sum of tracking quantities equals the quantity of the items, per entry'
                );
                $ok = false;
            }

            foreach ($entry['TRACKINGENTRIES'] as $tracking) {
                if ( ( isset($tracking['COMPONENTID']) && ! empty($tracking['COMPONENTID']) )
                     || ( $entry['ITEMID'] != $tracking['ITEMID'] ) ) {
                    // Ignore this, it refers to a component, not to the stockable kit itself
                    continue;
                }
                $newEntry = $this->prepNewEntry($entry, $inOut,
                                                $sourceDocentrycostKeys != null ? array_shift($sourceDocentrycostKeys)
                                                    : $docentrycostkey, $tracking);
                $ok = $ok && $decMgr->add($newEntry);
            }
        } else {
            // No tracking to worry about, entry requires only a single docentrycost record
            $newEntry = $this->prepNewEntry($entry, $inOut, $docentrycostkey);
            $ok = $ok && $decMgr->add($newEntry);
        }

        return $ok;
    }

    /**
     * If this entry has associated tracking information, make sure the
     * tracking quantity/quantities add up to the entry's overall quantity.
     *
     * @param array $entry The entry for which tracking quantities should be validated
     *
     * @return bool true if all is well, false otherwise
     */
    private function areTrackingQuantitiesCorrect($entry)
    {
        $ok = true;
        if ( self::isStockableKitTrackingEnabled() && $this->isTracked($entry) && $entry['ISSERIALIZED'] == 1
             && is_array($entry['TRACKINGENTRIES'])
             && ! empty($entry['TRACKINGENTRIES']) ) {
            $remainingQuantity = $entry['QUANTITY'];
            foreach ( $entry['TRACKINGENTRIES'] as $trackingEntry ) {
                if ( self::isStockableKitComponentTrackingEnabled() && $entry['ITEMID'] != $trackingEntry['ITEMID'] ) {
                    // This is a component; not verifying its quantity here
                    continue;
                }
                $remainingQuantity -= $trackingEntry['TRACK_QUANTITY'];
            }
            if ($remainingQuantity != 0) {
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * If a Stockable Kit entry is tracked, then there should be a docentrycost record for each tracking
     * item of the entry; e.g., a single entry or line item specifies an overall quantity, but this quantity
     * may be apportioned into multiple lots, bins, etc., as described in the tracking details.
     *
     * @param array      $entry           The originating entry
     * @param string     $inOut           Transaction type
     * @param string     $docentrycostkey Docentrycost reference for disassemble kits
     * @param array|null $tracking        The tracking details for the new entry being created, if any
     *
     * @return array The new entry to add
     */
    private function prepNewEntry($entry, $inOut, $docentrycostkey, $tracking = null)
    {
        /*
         * If there's no $tracking information specified, consume the entire quantity in this $newEntry,
         * otherwise consume only the quantity associated with the given tracking specification, and
         * apportion the cost to reflect only the quantity being consumed.
         */
        $quantity = $tracking != null ? $tracking['TRACK_QUANTITY'] : $entry['QUANTITY'];
        $unitcost = ibcdiv($entry['COST'], $entry['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS);
        if ($quantity < $entry['QUANTITY']) {
            // Need to apportion the cost
            $apportionedCost = ibcmul($quantity, $unitcost, ItemManager::AVERAGE_COST_DECIMALS);
        } else {
            $apportionedCost = $entry['COST'];
        }
        $newEntry = [
            'DOCENTRYNO'        => $entry['RECORDNO'],
            'SALE_PUR_TRANS'    => 'Internal',
            'IN_OUT'            => $inOut,
            'ITEMID'            => $entry['ITEMID'],
            'WAREHOUSEID'       => $entry['WAREHOUSE']['LOCATION_NO'],
            'QUANTITY'          => $quantity,
            'CONTRIBUTEDQTY'    => $quantity,
            'COST'              => $apportionedCost,
            'CONTRIBUTEDCOST'   => $apportionedCost,
            'UNITCOST'          => $unitcost,
            'LASTUNITCOST'      => $unitcost,
            'DATEIN'            => $entry['WHENCREATED'],
            'STATUS'            => 'active',
            'VALUE'             => $apportionedCost,
            'COST_METHOD'       => $entry['COST_METHOD'],
            'AISLEKEY'          => $entry['AISLEKEY'],
            'ROWKEY'            => $entry['ROWKEY'],
            'BINKEY'            => $entry['BINKEY'],
            'ITEMGLGRPKEY'      => $entry['ITEMGLGROUP'],
            'AFFECTS_INVENTORY' => 'Quantity and Value',
            'DOCENTRYCOSTKEY'   => $docentrycostkey,
            'SYSTEMGENERATED'   => 'F',
        ];
        if ( is_array($tracking) ) {
            // If tracking specified, we need to record the pertinent details here also.
            $newEntry['BINKEY'] = $tracking['BINKEY'];
            $newEntry['SERIALNO'] = $tracking['SERIALNO'];
            $newEntry['LOTNO'] = $tracking['LOTNO'];
            $newEntry['EXPIRATIONDATE'] = $tracking['EXPIRATION'];
        }

        return $newEntry;
    }

    /**
     * @param array $values
     * @param array $item
     * @param int   $key
     *
     * @return bool
     */
    function PopulateItemCostDetails(&$values, $item, $key)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;

        if ($item['ITEMTYPE'] != 'SK') {
            $gErr->addIAError('INV-0926', __FILE__ . '.' . __LINE__, null, [ 'ITEM_ITEMID' => $item['ITEMID'] ]);
            $ok = false;
        }

        if ($ok) {
            $itemMgr = $gManagerFactory->getManager('item');
            $companyid = GetMyCompany();
            if ($values['DOCPARID'] == self::DISKIT) {
                $qry = 'QRY_ICITEM_SELECT_ITEMCOSTDISKIT';
                $args = array($companyid, $values['ENTRIES'][$key]['SOURCE_DOCLINEKEY']);
            } else {
                $qry = 'QRY_ICITEM_SELECT_ITEMCOSTKIT';
                $args = array($companyid, $item['ITEMID']);
            }

            $values['ENTRIES'][$key]['ITEMDETAILS'] = $itemMgr->DoQuery($qry, $args);
        }

        return $ok;
    }

    /**
     * Process tracking information for Stockable Kits and their components iff the SK  and
     * SK component tracking feature is enabled, and advanced bins are enabled.
     *
     * @return bool Whether or not to process tracking information for Stockable Kits and their components
     */
    public static function isStockableKitAndComponentTrackingEnabled()
    {
        return ( self::isStockableKitTrackingEnabled()
                 && self::isStockableKitComponentTrackingEnabled() );
    }

    /**
     * Process tracking information for Stockable Kits iff the SK tracking feature is
     * enabled, and advanced bins are enabled.
     *
     * @return bool Whether or not to process tracking information for Stockable Kits
     */
    public static function isStockableKitTrackingEnabled()
    {
        if ( self::$isStockableKitTrackingEnabled != null ) {
            return self::$isStockableKitTrackingEnabled;
        }
        self::$isStockableKitTrackingEnabled = FeatureConfigManagerFactory::getInstance()
                                                                          ->isFeatureEnabled('STOCKABLE_KIT_TRACKING')
                                               && BinManager::areClassicBinsOn() === false;

        return self::$isStockableKitTrackingEnabled;
    }

    /**
     * Process tracking information for Stockable Kits iff the SK component tracking feature is
     * enabled, and advanced bins are enabled.
     *
     * @return bool Whether or not to process tracking information for Stockable Kit components
     */
    public static function isStockableKitComponentTrackingEnabled()
    {
        if ( self::$isStockableKitComponentTrackingEnabled != null ) {
            return self::$isStockableKitComponentTrackingEnabled;
        }
        self::$isStockableKitComponentTrackingEnabled = FeatureConfigManagerFactory::getInstance()
                                                                                   ->isFeatureEnabled('STOCKABLE_KIT_COMPONENT_TRACKING')
                                                        && BinManager::areClassicBinsOn() === false;

        return self::$isStockableKitComponentTrackingEnabled;
    }

    /**
     * Is this entry's item being tracked?
     *
     * @param string[] $entry
     *
     * @return bool
     */
    private function isTracked($entry)
    {
        $item = $this->itemRawCache[$entry['ITEMID']];
        return $item['ENABLESNO'] == 'T' || $item['ENABLELOT'] == 'T' || $item['ENABLEBIN'] == 'T'
               || $item['ENABLEEXPIRATION'] == 'T';
    }

    /**
     * Check whether Stockable Kits from the build in question are tracked, and if so,
     * whether any have been consumed.
     *
     * @param string[] $sourceDocentrycostKeys Docentrycost keys for the corresponding Build Kits transaction
     * @param array    $entry                  The entry being checked for references
     *
     * @return bool True if any Stockable Kit(s) corresponding to this entry is/are tracked and consumed
     */
    private function isNotTrackedAndReferenced($sourceDocentrycostKeys, $entry)
    {
        global $gErr;
        $ok = true;

        if ( empty($sourceDocentrycostKeys) || ! $this->isTracked($entry) ) {
            // This is fine
            return $ok;
        }

        // Since it's tracked, make sure there are no references (other than previous disassemblies).
        $qry = [];
        $qry[0] = "SELECT COUNT (1) count FROM (SELECT dc.record# FROM docentrycost dc, docentry de, dochdr dh
        WHERE dc.cny# = :1 AND de.cny# = dc.cny# AND de.record# = dc.docentrykey AND dh.cny# = dc.cny# and dh.record# = de.dochdrkey
        AND dh.docparkey NOT IN (
            SELECT dp.record# from docpar dp where dp.cny# = dh.cny# AND dp.docid = 'Disassemble Kits')
        AND ";
        $qry[1] = GetMyCompany();
        $qry = PrepINClauseStmt($qry, $sourceDocentrycostKeys, " dc.docentrycostkey ", true);

        $qry[0] .=" ) UNION ";

        $qry[0] .= "(SELECT dk.record# FROM docentrycostkits dk, docentry de, dochdr dh
        WHERE dk.cny# = :1 AND de.cny# = dk.cny# AND de.record# = dk.docentrykey AND dh.cny# = dk.cny# and dh.record# = de.dochdrkey
        AND dh.docparkey NOT IN (
            SELECT dp.record# from docpar dp where dp.cny# = dh.cny# AND dp.docid = 'Disassemble Kits')
        AND ";
        $qry = PrepINClauseStmt($qry, $sourceDocentrycostKeys, " dk.docentrycostkey ", true);
        $qry[0] .=" )";

        $childCount = QueryResult($qry);
        if ( $childCount === false ) {
            // Something went wrong
            return false;
        }

        $childCount = $childCount[0];
        if ( $childCount['COUNT'] > 0 ) {
            // No go, already consumed by other transactionss
            $ok = false;
            $msg =
                "This Document has item(s) enabled for Serial/Lot/Bin tracking which are referenced by other document(s)";
            $gErr->addError('INV-0927', __FILE__ . ':' . __LINE__, 'Error disassembling kit', $msg);
        }

        return $ok;
    }

    /**
     * Returns object definition id of 6012 for the stkitdocument object, This is defined in Util_StandardObjectRegistry.cls. We need
     * to override this method to not use the doctype as there is only one stkitdocument, which is consistent with the platform logic.
     * If we use the doctype, the id returned here and the platform logic will not match, hence the case below.
     * IA-133122 - Platform Trigger for inventory build kits does not seem to be firing
     *
     * @return int|null the entity's object "definition" id or null on some error
     */
    public function getObjectDefId()
    {
        //Purposely passing null to use the id defined in Util_StandardObjectRegistry.cls for stkitdocument
        return Util_StandardObjectMap::getObjectId($this->getEntity(), null);
    }
}
