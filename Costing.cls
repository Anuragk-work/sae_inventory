<?
/**
 * class for all costing logic in SCM
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

define('DEFAULT_INVPRECISION', 2);

class Costing
{
    /**
     * @var bool $_isNegativeInventoryAllowed
     */
    var $_isNegativeInventoryAllowed;

    /** @var array $parentValueCache by docheader */
    private $parentValueCache = [];



    function __construct()
    {
        $this->_isNegativeInventoryAllowed = IsNegativeInventoryAllowed();
    }


    /**
     * @param array  $kitEntry
     * @param array  $entry
     * @param array  $values
     * @param string $spi
     * @param string $inOut
     * @param string $sourceInOut
     * @param bool   $isReturn
     * @param array  $kitItem
     * @param string $updatesInv
     *
     * @param      array  $prevallocated
     * @return bool
     */
    public function findCostingDetails(
        &$kitEntry, &$entry, $values, $spi, $inOut, $sourceInOut, $isReturn, $kitItem, $updatesInv, &$prevallocated
    )
    {
        $ok = true;
        $docparid = $values['DOCPARID'];
        $quantityToValue = false;

        // use the source key only if any of the ancestor affected onhand
        $sourceDocEntryKey = '';
        if ($entry['SOURCE_DOCLINEKEY']) {

            if ($docparid == StkitDocumentManager::DISKIT) {
                // find the source layer of stokable kit
                $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                    $entry['SOURCE_DOCLINEKEY'], $entry, false
                );
            } else {
                $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                    $entry['SOURCE_DOCLINEKEY'], $kitEntry, false
                );
            }

            if (!empty($rec)) {
                if ($spi != 'Internal') {
                    if ($isReturn) {
                        $sourceDocEntryKey = $rec['DOCENTRYKEY'];

                        // unlink OE documents to allow return
                        // Recalc tool has to be run to fix it back
                        if ($spi == 'Purchase') {
                            $docentrycostKeys = array($rec['RECORD#']);

                            // if the docentrycost record is adjusting another record(V only document)
                            // then, use the original layer instead
                            if ($rec['ADJDOCENTRYCOSTKEY']) {
                                $docentrycostKeys = array($rec['ADJDOCENTRYCOSTKEY']);
                            }

                            if (!$kitItem['ISSERIALIZED']) {
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
                    }

                    // inout to find the source layer
                    // source will always be same  while converting from quantity to value
                    if ($updatesInv == 'Value') {
                        $sourceDocEntryKey = $rec['DOCENTRYKEY'];
                        $sourceInOut = ($inOut == 'Increase') ? 'I' : 'O';
                        $quantityToValue = true;
                    }
                } else {
                    $sourceDocEntryKey = $rec['DOCENTRYKEY'];;
                }
            }

        }

        $warehouse = $entry['WAREHOUSE']['LOCATION_NO'];

        $kitHasTrackingEnabledItems = ($kitEntry['SERIALTRACKING'] == 'T' ||
            $kitEntry['LOTTRACKING'] == 'T' ||
            $kitEntry['BINTRACKING'] == 'T' ||
            $kitEntry['EXPTRACKING'] == 'T'
        );

        if ($entry['ITEMTYPE'] == 'K' && !$kitHasTrackingEnabledItems) {
            $quantity = ibcmul($entry['QUANTITY'], $kitEntry['QUANTITY'], ItemManager::BASEUNITPRECISION, true);
        } else {
            $quantity = $kitEntry['QUANTITY'];
        }

        if ((!isset($values['WHENPOSTED']) || $values['WHENPOSTED'] == '')) {
            $postingDate = $values['WHENCREATED'];
        } else {
            $postingDate = $values['WHENPOSTED'];
        }

        $kitEntry['COST_METHOD'] = $kitItem['COST_METHOD'];
        $kitEntry['WAREHOUSEID'] = $warehouse;
        $kitEntry['PRICE']       = $entry['PRICE'];
        $docentrykey             = (int)($entry['RECORDNO'] ?? 0);

        //in case of inventory transfers, the source warehouse would be different than current warehouse
        $inventoryConvert = ($spi == 'Internal' && $sourceDocEntryKey);
        $sourceWarehouse = $warehouse;
        if ($inventoryConvert) {
            $this->findSourceWarehouse($sourceDocEntryKey, $sourceWarehouse);
        }

        $currentCost = 0;
        $lastCost = 0;
        $useSourceCost = false;

        $sourceCostLayers = [];
        $ok = $ok
            && $this->findUnitCost(
                $spi, $currentCost, $lastCost, $kitEntry, $isReturn, $sourceDocEntryKey, $postingDate,
                $sourceWarehouse, $useSourceCost
            );

        $ok = $ok
            && $this->findSourceCostLayer(
                $sourceCostLayers, $isReturn, $sourceDocEntryKey, $spi, $sourceWarehouse, $kitEntry, $kitItem,
                $sourceInOut, $docparid, $docentrykey
            );

        $ok = $ok
            && $this->mergeCostDetailsWithEntry(
                $entry, $kitEntry, $kitItem, $sourceCostLayers, $quantity, $currentCost, $lastCost, $useSourceCost,
                $spi, $inOut, $updatesInv, $quantityToValue, $isReturn, $prevallocated
            );


        return $ok;
    }

    /**
     * @param int    $sourceDocEntryKey
     * @param string $warehouse
     */
    private function findSourceWarehouse(&$sourceDocEntryKey, &$warehouse)
    {
        $srcWarehouseRes = QueryResult(
            array(
                "select docentry.record#, docentry.warehousekey
					from dochdrmst dochdr, docpar, docentrymst docentry
					where dochdr.cny# = :1
						and docpar.cny#=dochdr.cny#
						and dochdr.docparkey = docpar.record#
						and docentry.cny# = dochdr.cny#
                        and docentry.dochdrkey = dochdr.record#
						and dochdr.state not in ('I','S','A', 'X', 'R')
						and docpar.updinv != 'F'
					START WITH docentry.cny# = :1
                         AND docentry.record# = :2
                    CONNECT BY docentry.record# = PRIOR docentry.source_doclinekey
                         AND docentry.cny# = :1
                    ORDER BY docentry.record#",
                GetMyCompany(),
                $sourceDocEntryKey
            )
        );

        // if the warehouse of ancestor is different then it could be transfer between warehouses
        // then we need to take the source warehouse's cost
        if ($srcWarehouseRes[0]['WAREHOUSEKEY'] && $srcWarehouseRes[0]['WAREHOUSEKEY'] != $warehouse) {
            $warehouse = $srcWarehouseRes[0]['WAREHOUSEKEY'];
        }
        if ($srcWarehouseRes[0]['RECORD#'] && $srcWarehouseRes[0]['RECORD#'] != $sourceDocEntryKey) {
            $sourceDocEntryKey = (int) $srcWarehouseRes[0]['RECORD#'];
        }
    }

    /**
     * @param string $spi
     * @param float|int  $unitcost
     * @param float|int  $lastcost
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
            $useSourceCost = true;
        } else if ($isReturn && $spi == 'Purchase') {
            $unitcost = $kitentry['PRICE'];
            $lastcost = $kitentry['PRICE'];
        } else {
            $itemMgr = Globals::$g->gManagerFactory->getManager('item');
            $unitcost = $itemMgr->getLastCost($kitentry['ITEMID'], $warehouse, $effectiveDate);
            $lastcost = $unitcost;
        }

        return true;
    }


    /**
     *      If we are upserting, then there are probably existing docentrycost/docentrycostkits that are using
     *  source records.  In the old days, they had been deleted when we look for source layers with qtyLeft > 0.
     *  now, the qtyLeft may be 0 or not enough because they're still in use.
     *
     *      Here, get the docentrycost[kits] records for this docentry.  Use them to get the 'source' entries
     *  we can later merge into the fetched lists.
     *
     * @param int $docEntryRecordNo     The exiting docentry record number
     *
     * @return array                    source docentrycost records with QtyLeft filled in from the current txn,
     *                                  indexed by record#
     */
    private function getExistingSourceCostLayers($docEntryRecordNo)
    {
        $rtn = [];
        $used = []; // quantity used, by source record#

        // If we're not upserting, then avoid this work
        if (DocumentManager::$upsertFeaturInUse) {

            // Get any existing docentry cost records for this docentry that have a source docentrycost ....
            $qry = [];
            $qry[]  = "SELECT docentrycostkey, quantity FROM docentrycost     WHERE cny#=:1 AND docentrykey=:2 and docentrycostkey IS NOT NULL 
                        UNION ALL 
                       SELECT docentrycostkey, quantity FROM docentrycostkits WHERE cny#=:1 AND docentrykey=:2 and docentrycostkey IS NOT NULL ";
            $qry[]  = GetMyCompany();
            $qry[]  = $docEntryRecordNo;
            $result = QueryResult($qry);
            if (($result !== false) && (!empty($result))) {
                foreach ($result as $row) {
                    $key        = $row['DOCENTRYCOSTKEY'];
                    $used[$key] = ($used[$key] ?? 0) + $row['QUANTITY'];
                }

                // now get those source docentrycost records.  Note that docentrycostkits are not sources
                $qry    = [];
                $qry[]  = "SELECT * FROM docentrycost WHERE cny#=:1 ";
                $qry[]  = GetMyCompany();
                $qry    = PrepINClauseStmt($qry, array_keys($used), " AND record# ");
                $result = QueryResult($qry);
                if (($result !== false) && (!empty($result))) {
                    foreach ($result as $row) {
                        $key            = $row['RECORD#'];
                        $row['QTYLEFT'] = ($row['QTYLEFT'] ?? 0) + ($used[$key] ?? 0);
                        $rtn[$key]      = $row;
                    }
                }
            }
        }
        return $rtn;
    }


    /**
     *      If we are upserting, increase the quantity left of the just-read source cost layers by the currently-in-use
     *  quantity, so that it LOOKS like we have enough on-hand.
     *
     * @param array         $newSourceCostLayers    the existing cost layers, whether they have quantity left or not
     * @param int[]         $existingCostLayers     just the QUANTITY, by docentry record#; the in-use source values, if any
     */
    private function mergeExistingAndNewSourceCostLayers(&$newSourceCostLayers, &$existingCostLayers)
    {
        foreach ($newSourceCostLayers as $index => $row) {
            $key = $row['RECORD#'];
            if (isset($existingCostLayers[$key])) {
                $newSourceCostLayers[ $index ]['QTYLEFT'] = $existingCostLayers[$key]['QTYLEFT'];   // replace, not add
                unset($existingCostLayers[$key]);   // handled
            }
        }

        // any existing that aren't in the new?  (because the qtyleft is now zero)
        foreach ($existingCostLayers as $row) {
            $newSourceCostLayers[] = $row;
        }
    }


    /**
     * This function is introduced to get all the records which are descendent to the $docentrycostkey,
     * Get all the sale invoice return's which are consumed qty from $docentrycostkey source.
     *
     * @param array       $kitEntry
     * @param int         $docentrycostkey
     * @param string      $inOut
     * @param string      $warehouse
     *
     * @return false|array
     */
    private function getDescendentCostEntries($kitEntry,$docentrycostkey,$inOut,$warehouse,$docparid){
        $cost_entry_keys = array();
        $qty_filter = " AND qtyleft > 0";
        $table = 'docentrycost';
        if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
            && $docparid == StkitDocumentManager::DISKIT ) {
            $table = 'docentrycostkits';
            $qty_filter = 'AND quantity > 0';
        }
        //Toggle InOut to get first opposite transactions of the source transaction($docentrycostkey),
        // example: if the src doc is In transaction('I', vendor invoice) then need to get all Out('O', sale invoice) transactions having $docentrycostkey as docentrycostkey.
        $toggled_inOut = ($inOut === 'I')?'O':'I';
        $sql_select = "SELECT record# ";
        $sql_from = "FROM ".$table." WHERE cny# = :1 AND itemkey = :2 AND whsekey = :3 AND in_out = :4 AND docentrycostkey = :5";
        $qry = array();
        $qry[] = $sql_select.$sql_from;
        $qry[] = GetMyCompany();
        $qry[] = $kitEntry['ITEMID'];
        $qry[] = $warehouse;
        $qry[] = $toggled_inOut;
        $qry[] = $docentrycostkey;
        $costdetails = QueryResult($qry);
        if ($costdetails === false) {
            return false;
        }else{
            //Traverse all the transactions and check if any transactions has been reversed,
            // i.e to find out sale invoice returns, which are consumed from $docentrycostkey.
            $sql_select = "SELECT record# ";
            foreach ($costdetails as $costdetail) {
                $qry = array();
                $qry[] = $sql_select.$sql_from.$qty_filter;
                $qry[] = GetMyCompany();
                $qry[] = $kitEntry['ITEMID'];
                $qry[] = $warehouse;
                $qry[] = $inOut;
                $qry[] = $costdetail["RECORD#"];
                $costentrydetails = QueryResult($qry);
                if($costentrydetails === false){
                    return false;
                }
                foreach ($costentrydetails as $costentrydetail) {
                    $cost_entry_keys[] = $costentrydetail['RECORD#'];
                }
            }
        }
        return $cost_entry_keys;
    }

    /**
     * @param array|false $sourceCostLayers
     * @param int         $sourceDocEntryKey
     * @param array       $kitEntry
     * @param string      $warehouse
     * @param string      $inOut
     * @param string      $docparid
     * @param int         $docentrykey
     *
     * @return bool
     */
    private function findSourceCostLayerForSerlizedItem(
        &$sourceCostLayers, $sourceDocEntryKey, &$kitEntry, $warehouse, $inOut, $docparid, $docentrykey,$isReturn,$spi
    )
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $where = "WHERE cny# = :1 AND affects_inventory != 'Q' AND itemkey = :2 AND whsekey = :3 AND in_out = :4";
        $qry = array();
        $qry[] = '';
        $qry[] = GetMyCompany();
        $qry[] = $kitEntry['ITEMID'];
        $qry[] = $warehouse;
        $qry[] = $inOut;

        if ($sourceDocEntryKey) {
            // check if the adjustment layer (V only document that is adjsting Q only document) is being returned
            $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                $sourceDocEntryKey, $kitEntry, false
            );
            if ($rec['ADJDOCENTRYCOSTKEY']) {
                $where .= " AND record# = :5";
                $qry[] = $rec['ADJDOCENTRYCOSTKEY'];
            } else if( $isReturn && ($spi == 'Purchase') && ((float)$rec['QTYLEFT'] < (float)$rec['QUANTITY'])) {
                //Get all the sale invoice return's if exist's which are consumed qty from $docentrycostkey source.
                $docentrycostkeys = $this->getDescendentCostEntries($kitEntry,$rec['RECORD#'],$inOut,$warehouse,$docparid);
                if($docentrycostkeys){
                    $where .= " AND record# IN (";
                    $bind = count($qry);
                    foreach ($docentrycostkeys as $docentrycostkey_item){
                        $where .= ":".($bind++).",";
                        $qry[] = $docentrycostkey_item;
                    }
                    $where .= ":".($bind++).")";
                    $qry[] = $rec['RECORD#'];
                }else{
                    $where .= " AND docentrykey = :5";
                    $qry[] = $sourceDocEntryKey;
                }
            } else {
                $where .= " AND docentrykey = :5";
                $qry[] = $sourceDocEntryKey;
            }
        }

        $bind = count($qry);
        $msg = array();
        $placeholderText = array();

        if (hasValue($kitEntry['SERIALNO'])) {
            $where .= " AND serialno = :" . $bind++;
            $qry[] = $kitEntry['SERIALNO'];
            $msg[] = ' Serial No. ' . $kitEntry['SERIALNO'];
            $placeholderText[] = I18N::getSingleToken('IA.SERIAL_NO_KIT_ENTRY', [['name' => 'SERIALNO', 'value' => $kitEntry['SERIALNO']]]);
        } else {
            $where .= " AND serialno IS NULL ";
        }

        if (hasValue($kitEntry['LOTNO'])) {
            $where .= " AND lotno = :" . $bind++;
            $qry[] = $kitEntry['LOTNO'];
            $msg[] = ' Lot No. ' . $kitEntry['LOTNO'];
            $placeholderText[] = I18N::getSingleToken('IA.LOT_NO_KIT_ENTRY', [['name' => 'LOTNO', 'value' => $kitEntry['LOTNO']]]);
        } else {
            $where .= " AND lotno IS NULL ";
        }

        if (BinManager::areAdvanedBinsOn() == false) {
            if (hasValue($kitEntry['AISLEKEY'])) {
                $where .= " AND aislekey = :" . $bind++;
                $qry[] = $kitEntry['AISLEKEY'];
                $aisleKey = AisleManager::IdForKey($kitEntry['AISLEKEY']);
                $msg[] = ' Aisle ' . $aisleKey;
                $placeholderText[] = I18N::getSingleToken('IA.AISLE_AISLEKEY', [['name' => 'AISLEKEY', 'value' => $aisleKey]]);
            } else {
                $where .= " AND aislekey IS NULL ";
            }

            if (hasValue($kitEntry['ROWKEY'])) {
                $where .= " AND rowkey = :" . $bind++;
                $qry[] = $kitEntry['ROWKEY'];
                $rowKey = icrowManager::IdForKey($kitEntry['ROWKEY']);
                $msg[] = ' Row ' . $rowKey;
                $placeholderText[] = I18N::getSingleToken('IA.ROW_ROWKEY', [['name' => 'ROWKEY', 'value' => $rowKey]]);
            } else {
                $where .= " AND rowkey IS NULL ";
            }
        }

        if (hasValue($kitEntry['BINKEY'])) {
            $where .= " AND binkey = :" . $bind;
            $qry[] = $kitEntry['BINKEY'];
            $binKey = BinManager::IdForKey($kitEntry['BINKEY']);
            $msg[] = ' Bin ' . $binKey;
            $placeholderText[] = I18N::getSingleToken('IA.BIN_BINKEY', [['name' => 'BINKEY', 'value' => $binKey]]);
        } else {
            $where .= " AND binkey IS NULL ";
        }

        /*
         * With tracked Stockable Kit components, we need to consult docentrycostkits instead of docentrycost
         * here as we do for unserialized Stockable Kit components.
         * In addition similar allowances have to be made for the table column mismatches.
         */
        $table = 'docentrycost';
        $qtyleft = 'qtyleft';
        $adjdocentrycostkey = 'adjdocentrycostkey';
        $systemgenerated = 'systemgenerated';
        $sale_pur_trans = 'sale_pur_trans';
        $qtyleftFilter = 'AND qtyleft>0';
        $adjdocentrycostFilter = 'AND adjdocentrycostkey IS NULL ';
        if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
             && $docparid == StkitDocumentManager::DISKIT ) {
            $table = 'docentrycostkits';
            $qtyleft = 'quantity as qtyleft';
            $adjdocentrycostkey = 'null as adjdocentrycostkey';
            $systemgenerated = "'F' as systemgenerated";
            $sale_pur_trans = 'in_out';
            $qtyleftFilter = 'AND quantity > 0';
            $adjdocentrycostFilter = '';
        }
        $qry[0]
            = "select record#, datein, cost, unitcost, lastunitcost, quantity, " . $qtyleft . ", " . $adjdocentrycostkey
              . ", " . $systemgenerated . ", " . $sale_pur_trans . " spi from " . $table
              . " $where " . $adjdocentrycostFilter . " " . $qtyleftFilter . " order by record#";

        $costdetails = QueryResult($qry);
        if ($costdetails === false) {
            $costdetails = [];
        }

        if (DocumentManager::$upsertFeaturInUse && ($docentrykey != 0)) {
            $existingsourceCostLayers = $this->getExistingSourceCostLayers($docentrykey); // those in use by this line
            $this->mergeExistingAndNewSourceCostLayers($costdetails, $existingsourceCostLayers);
        }

        if (!empty($costdetails[0])) {

            if (hasValue($kitEntry['SERIALNO'])) {
                $sourceCostLayers[] = $costdetails[0];
                $qtyleft = $costdetails[0]['QTYLEFT'];
            } else {
                $qtyleft = 0;
                foreach ($costdetails as $costdetail) {
                    $qtyleft = ibcadd($qtyleft, $costdetail['QTYLEFT'], ItemManager::BASEUNITPRECISION);
                    $sourceCostLayers[] = $costdetail;
                }
            }

            if ($qtyleft < $kitEntry['QUANTITY']) {
                $qtyFound = $costdetails[0]['QTYLEFT']; //Error found that we have less qty than needed
                $ok = false;
            }
        } else {
            $qtyFound = 0; //Error found, we have zero qty of what we needed
            $ok = false;
        }

        //If an error found, show error msg
        if ($ok === false) {
            $msg = implode(",", $msg);
            $placeholderText = implode(", ", $placeholderText);
            if ($isReturn && $spi === 'Sale') {
                $gErr->addIAError(
                    'INV-0336', __FILE__ . ':' . __LINE__,
                    "Not enough quantity sold",
                    [],
                    "You cannot accept returns that have more quantity than you sold. You can only accept a sales return of a maximum of {$qtyFound}",
                    ['QTY_FOUND' => $qtyFound],
                    "Specify a return quantity of {$qtyFound} or less for item {$kitEntry['ITEMID']} for {$msg}. If tracking is enabled, specify the correct serial, lot, or bin.",
                    ['QTY_FOUND' => $qtyFound, 'KIT_ENTRY_ITEMID' => $kitEntry['ITEMID'], 'MSG' => $placeholderText]
                );
            } else if ($isReturn && $spi === 'Purchase') {
                $gErr->addIAError(
                    'INV-0337', __FILE__ . ':' . __LINE__,
                    "Not enough quantity available",
                    [],
                    "You cannot return more quantity than you have available. You can only return a maximum of {$qtyFound}",
                    ['QTY_FOUND' => $qtyFound],
                    "Specify a return quantity of {$qtyFound} or less for item {$kitEntry['ITEMID']} for {$msg}. If tracking is enabled, specify the correct serial, lot, or bin.",
                    ['QTY_FOUND' => $qtyFound, 'KIT_ENTRY_ITEMID' => $kitEntry['ITEMID'], 'MSG' => $placeholderText]
                );
            } else {
                $gErr->addIAError(
                    'INV-0339', __FILE__ . ':' . __LINE__,
                    "There is not enough quantity for Item ID {$kitEntry['ITEMID']} for {$msg}",
                    ['KIT_ENTRY_ITEMID' => $kitEntry['ITEMID'], 'MSG' => $placeholderText],
                    "Quantity needed : {$kitEntry['QUANTITY']} and Quantity available : {$qtyFound}",
                    ['QUANTITY' => $kitEntry['QUANTITY'], 'QTY_FOUND' => $qtyFound],
                    "Ensure that enough quantity is available for the item. If tracking is enabled, specify the correct serial, lot, or bin.",
                    []
                );
            }
        }

        return $ok;
    }


    /**
     *      When doing a return, for a V transaction that modified a prior Q transaction,
     * The V transaction may have ONE docentrycost with a quantity of 2, say, and
     * ONE ADJDOCENTRYCOSTKEY.  But, the Q tranaction may have more layers.  For example:
     *
     *      Purchase 1
     *      Purchase 1
     *      Sales Invoice Q of 2 (so there are 2 docentrycost Q records and 2 docentrycost V records)
     *      Convert to Sales Invoice V
     *          We sometimes generate just ONE layer for the V, and update the two V-layers of the Q transaction
     *
     *      At this point, everything is fine..... until you try to RETURN the sale.
     *
     *      At that point, the code in findSourceCostLayer() finds the ONE ADJDOCENTRYCOSTKEY which points
     *      to only ONE V docentrycost record, and so we miss the other V docentrycost record(s).
     *
     *  This routine, then, discovers that and tries to find the missing docentrycost V layers (siblings of the first)
     *
     *  Ya, another approach would be to FIX the V transaction, so that could be done as well.  But this works with
     *  existing damaged records
     *
     * On entry, we know this is a SALES RETURN with ADJUSTMENT layers
     *
     * @param array     $sourceCostLayers       The found source layers
     * @param string[]  $parentFound            The parent docentry; what were we LOOKING for?
     * @param string[]  $kitEntry               The RETURN and what IT wants....
     */
    private function makeSureWeHaveEnoughSourceLayersToReturn($sourceCostLayers, $parentFound, $kitEntry)
    {
        $quantityWeFound = '0';
        foreach ($sourceCostLayers as $row) {
            $quantityWeFound = ibcadd($quantityWeFound, $row['QUANTITY'], ItemManager::BASEUNITPRECISION, true);
            $oneSibling      = $row['RECORD#'];     // on of our siblings
        }

        $quantityWeWant = $parentFound['QUANTITY'];
        if ($quantityWeWant > $quantityWeFound) {
            // relax, this is cached from the prior call and won't cost any SQL reads....
            $recs = DocumentEntryCostManager::getParentDocentryCostDetail($parentFound['DOCENTRYKEY'], $kitEntry, false, false);

            // find the docentry; it is not in $sourceCostLayers :-(
            $docEntryWeWant = 0;
            foreach ($recs as $row) {
                if ($row['RECORD#'] == $oneSibling) {
                    $docEntryWeWant = $row['DOCENTRYKEY'];
                    break;
                }
            }

            // now, collect all the siblings togeather:
            if ($docEntryWeWant != 0) {
                $sourceCostLayers = [];

                // find all the siblings
                foreach ($recs as $row) {
                    if ($row['DOCENTRYKEY'] == $docEntryWeWant){
                        $sourceCostLayers[] = $row;
                    }
                }
            }
        }
        return $sourceCostLayers;
    }



    /**
     * @param array|false $sourceCostLayers
     * @param bool        $isReturn
     * @param int         $sourceDocEntryKey
     * @param string      $spi
     * @param string      $warehouse
     * @param array       $kitEntry
     * @param array       $itm
     * @param string      $inOut
     * @param string      $docparid
     * @param int         $docentrykey
     *
     * @return bool
     */
    private function findSourceCostLayer(
        &$sourceCostLayers, $isReturn, $sourceDocEntryKey,
        /** @noinspection PhpUnusedParameterInspection */ $spi, $warehouse, &$kitEntry, $itm, $inOut, $docparid, $docentrykey
    )
    {
        $gErr = Globals::$g->gErr;
        $sourceCostLayers = array();

        // for serialized items
        // If quantity is 0, ignore error check
        if($itm['ISSERIALIZED'] && isset($kitEntry["QUANTITY"]) && $kitEntry["QUANTITY"] != '0') {
            return $this->findSourceCostLayerForSerlizedItem(
                $sourceCostLayers, $sourceDocEntryKey, $kitEntry, $warehouse, $inOut, $docparid, $docentrykey,$isReturn,$spi
            );
        }

        $ok = true;
        $cny = GetMyCompany();
        $docMgr = Globals::$g->gManagerFactory->getManager('document');

        $itemid = $kitEntry['ITEMID'];
        $method = ($itm['COST_METHOD'] == 'L') ? 'LIFO' : 'FIFO';

        if ($sourceDocEntryKey) {

            $kits = '';
            if ($docparid == StkitDocumentManager::DISKIT) {
                $kits = 'KITS';
            }

            $args = array($cny, $cny, $sourceDocEntryKey, $cny, $cny, $warehouse, $itemid, $warehouse, $inOut, $cny);
            $action = '_WITHSOURCE';
            $isReturningAdjLayer = false;
            if ($isReturn) {
                $action = '_RET';

                // check if the adjustment layer (V only document that is adjsting Q only document) is being returned
                $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                    $sourceDocEntryKey, $kitEntry, false
                );
                if ($rec['ADJDOCENTRYCOSTKEY']) {
                    $isReturningAdjLayer = true;
                    $action .= '_ADJ';
                    $args = array($cny, $sourceDocEntryKey, $itemid, $warehouse, $inOut, $cny);
                }
            }
            $qry = 'QRY_ITEM_COST_' . $method . $action . $kits;
            $sourceCostLayers = $docMgr->DoQuery($qry, $args);

            // Sometimes there aren't enough adjustment layers to satisfy a value-return....
            if ($isReturn && $isReturningAdjLayer) {
                $sourceCostLayers = $this->makeSureWeHaveEnoughSourceLayersToReturn($sourceCostLayers, $rec, $kitEntry);
            }

            // for line level conversion it has to go thru recurprentry to find source
            if (empty($sourceCostLayers) && !$isReturningAdjLayer) {
                $qry = 'QRY_ITEM_COST_' . $method . $action . $kits . '_PLUSRECUR';
                $sourceCostLayers = $docMgr->DoQuery($qry, $args);
            }

            // are there existing cost layers we're already using?
            if (DocumentManager::$upsertFeaturInUse && ($docentrykey != 0)) {
                $existingsourceCostLayers = $this->getExistingSourceCostLayers($docentrykey); // those in use by this line
                $this->mergeExistingAndNewSourceCostLayers($sourceCostLayers, $existingsourceCostLayers);
            }

            if (empty($sourceCostLayers)) {
                $gErr->addIAError(
                    'INV-0338', __FILE__ . ':' . __LINE__,
                    "Could not find cost", [],
                    "A cost entry doesn't exist for Item ID '" . $itemid . "'" , ['ITEMID' => $itemid]
                );
                $ok = false;
            }
        } else {
            $args = array($itemid, $warehouse, $inOut);
            $qry = 'QRY_ITEM_COST_' . $method;
            $sourceCostLayers = $docMgr->DoQuery($qry, $args);
        }

        return $ok;
    }

    /**
     * @param array       $entry
     * @param array       $kitEntry
     * @param array       $itm
     * @param array|false $sourceCostLayers
     * @param float       $quantity
     * @param float       $currentCost
     * @param float       $lastCost
     * @param bool        $useSourceCost
     * @param string      $spi
     * @param string      $inOut
     * @param string      $updatesInv
     * @param bool        $quantityToValue
     * @param bool        $isReturn
     *
     * @param   array      $prevallocated
     * @return bool
     */
    private function mergeCostDetailsWithEntry(
        &$entry, &$kitEntry, $itm, $sourceCostLayers, $quantity, $currentCost, $lastCost, $useSourceCost,
        $spi, $inOut, $updatesInv, $quantityToValue, $isReturn, &$prevallocated
    ) {
        $ok = true;
        $qtyFound = '0';
        $count = 0;
        $qtyCostArray = array();
        $totalCost = '0';

        foreach ( $sourceCostLayers as $costEntry) {

            // check if this is already allocated by a another entry line
            $recordno =  $costEntry['RECORD#'];
            $qtyAlreadyAllocated = $prevallocated[$recordno]['allocated']?? 0;
            // subtract any preious allocation from this record
            $qtyleft = ibcsub($costEntry['QTYLEFT'], $qtyAlreadyAllocated, ItemManager::BASEUNITPRECISION);
            if ($qtyleft <= 0 )
            {
                // nothing remaining.  next record
                continue;
            }
            if ($quantityToValue) {
                // if converting from quantity to value only adjdocentrycost should be there
                $qtyCostArray[$count]['ADJDOCENTRYCOSTKEY'] = $costEntry['RECORD#'];
            } else {
                $qtyCostArray[$count]['RECORD#'] = $costEntry['RECORD#'];
            }
            $qtyCostArray[$count]['DATEIN'] = $costEntry['DATEIN'];

            if ($qtyleft <= ibcsub($quantity, $qtyFound, ItemManager::BASEUNITPRECISION)) {

                $qtyCostArray[$count]['QTY'] = $qtyleft;
                $prevallocated[$recordno]['allocated'] = ibcadd($qtyAlreadyAllocated, $qtyleft, ItemManager::BASEUNITPRECISION);
            } else {
                $qtyCostArray[$count]['QTY'] = ibcsub($quantity, $qtyFound, ItemManager::BASEUNITPRECISION);
                $prevallocated[$recordno]['allocated'] = ibcadd($qtyAlreadyAllocated, $qtyCostArray[$count]['QTY'], ItemManager::BASEUNITPRECISION);
           }

            $qtyFound = ibcadd($qtyFound, $qtyleft, ItemManager::BASEUNITPRECISION);

            if ($qtyleft == 0) {
                    $qtyCostArray[$count]['COST'] = 0;
                } else {

                    // when converting sales quantity only to value only
                    // system needs to take the cost that was used when quantity only was created
                    // it is applicable only for FIFO/LIFO
                    if (
                        $spi == 'Sale'
                        && $inOut == 'Decrease'
                        && $updatesInv == 'Value'
                    ) {
                        $this->calculateSalesUnitCost($costEntry);
                    }
                    $ok = $ok && $this->calculateCost($qtyCostArray[$count], $costEntry, $currentCost, $useSourceCost);
                }

            $totalCost = ibcadd(
                $totalCost, $qtyCostArray[$count]['COST'], ItemManager::AVERAGE_COST_DECIMALS, true
            );

            $kitEntry['COSTDETAILS'][$count] = $qtyCostArray[$count];

            $count++;

            if ($qtyFound >= $quantity) {
                break;
            }
        }

        $kitEntry['COST'] = $totalCost;

        $ok = $this->handleNoSourceAndNegativeEntries(
            $itm, $lastCost, $qtyCostArray, $entry, $kitEntry, $qtyFound, $quantity, $isReturn, $spi
        );

        return $ok;
   }

    /**
     * @param array $costEntry
     */
    protected function calculateSalesUnitCost(&$costEntry)
    {
        if ($costEntry['SYSTEMGENERATED'] == 'T'
            && $costEntry['SPI'] == 'S'
            && ibccomp($costEntry['LASTUNITCOST'], '0', 10)
        ) {
            $costEntry['UNITCOST'] = $costEntry['LASTUNITCOST'];
        }
    }

    /**
     * @param array $qtyCostArray
     * @param array $costEntry
     * @param float $currentCost
     * @param bool  $useSourceCost
     *
     * @return bool
     */
    protected function calculateCost(&$qtyCostArray, $costEntry, $currentCost,
        /** @noinspection PhpUnusedParameterInspection */ $useSourceCost)
    {
        // for the receiver layer that never received value, use last cost
        if (!ibccomp($costEntry['UNITCOST'], '0', ItemManager::AVERAGE_COST_DECIMALS)
            && $costEntry['SYSTEMGENERATED'] == 'T'
        ) {
            // if zero value document is found then use zero. Otherwise use last cost
            $qry = array();
            $qry[]
                = "SELECT record# 
                    FROM docentrycost 
                    WHERE cny#=:1 AND adjdocentrycostkey=:2 AND affects_inventory <> 'Q' AND rownum = 1";
            $qry[] = GetMyCompany();
            $qry[] = $costEntry['RECORD#'];
            $res = QueryResult($qry);

            if ($res[0]['RECORD#']) {
                $qtyCostArray['UNITCOST'] = 0;
            } else {
                $qtyCostArray['UNITCOST'] = $currentCost;
            }

        } else {
            $qtyCostArray['UNITCOST'] = $costEntry['UNITCOST'];
        }

        $qtyCostArray['COST'] = ibcmul(
            $qtyCostArray['UNITCOST'], $qtyCostArray['QTY'], ItemManager::AVERAGE_COST_DECIMALS, true
        );

        return true;
    }

    /**
     * @param array $itm
     * @param float $lastCost
     * @param array $qtyCostArray
     * @param array $entry
     * @param array $kitentry
     * @param float $qtyFound
     * @param float $quantity
     * @param bool  $isReturn
     * @param string $spi       Contains one of these: "Sale", "Purchase", or "Internal".
     *
     * @return bool
     */
    private function handleNoSourceAndNegativeEntries(
        /** @noinspection PhpUnusedParameterInspection */ $itm, $lastCost,
        /** @noinspection PhpUnusedParameterInspection */ $qtyCostArray, &$entry, &$kitentry, $qtyFound, $quantity, $isReturn, $spi
    )
    {
        $ok = true;

        if ($qtyFound < $quantity) {

            if (!$this->validateNegativeQuantity($kitentry, $qtyFound, $quantity, $isReturn, $spi)) {
                return false;
            }

            $newQty = ibcsub($quantity, $qtyFound, ItemManager::BASEUNITPRECISION);
            $kitentry['COSTDETAILS'][] = array(
                'COST' => ibcmul($lastCost, $newQty, ItemManager::AVERAGE_COST_DECIMALS, true),
                'QTY' => $newQty,
                'DATEIN' => $entry['WHENCREATED'],
                'UNITCOST' => $lastCost
            );
        }

        return $ok;
    }

    /**
     * @param array  $kitentry
     * @param int    $qtyFound
     * @param int    $quantity
     * @param bool   $isReturn
     * @param string $spi       Contains one of these: "Sale", "Purchase", or "Internal".
     *
     * @return bool
     */
    private function validateNegativeQuantity($kitentry, $qtyFound, $quantity, $isReturn, $spi)
    {
        $ok = true;
        $kititemid = $kitentry['ITEMID'];
        $allowNegativeInventory = $this->_isNegativeInventoryAllowed;

        // if negativeinentory is not allowed in inventory contol setup
        // check if warehouse allows negative inventory
        if ( ! $allowNegativeInventory ) {
            $warehouseMgr = Globals::$g->gManagerFactory->getManager('warehouse');
            $allowNegativeInventory = $warehouseMgr->isNegativeInventoryAllowed($kitentry['WAREHOUSEID']);
        }

        if ( ! $allowNegativeInventory || $isReturn ) {
            $gErr = Globals::$g->gErr;

            if ($isReturn && $spi === 'Sale') {
                $gErr->addIAError(
                    'INV-0484', __FILE__ . ':' . __LINE__,
                   "Not enough quantity sold",[],
                    "You cannot accept returns that have more quantity than you sold. You can only accept a sales return of a maximum of {$qtyFound}",
                    ['QTY_FOUND' => $qtyFound],
                   "Specify a return quantity of {$qtyFound} or less for item {$kititemid}",
                   ['QTY_FOUND' => $qtyFound, 'KITITEMID' => $kititemid]
                );
            } else if ($isReturn && $spi === 'Purchase') {
                $gErr->addIAError(
                    'INV-0482', __FILE__ . ':' . __LINE__,
                    "Not enough quantity available",[],
                    "You cannot return more quantity than you have available. You can only return a maximum of {$qtyFound}",
                    ['QTY_FOUND' => $qtyFound],
                    "Specify a return quantity of {$qtyFound} or less for item {$kititemid}",
                    ['QTY_FOUND' => $qtyFound, 'KITITEMID' => $kititemid]
                );
            } else {
                $gErr->addIAError(
                    'INV-0483', __FILE__ . ':' . __LINE__,
                    "There is not enough quantity for Item ID '" . $kititemid . "'",
                    ['KITITEMID' => $kititemid],
                    "Quantity needed : " . $quantity
                    . " and Quantity available : " . $qtyFound,
                    ['QUANTITY' => $quantity, 'QTY_FOUND' => $qtyFound],
                    "Ensure that enough quantity is available for the item",
                    []
                );
            }
            $ok = false;
        }

        return $ok;
    }


    /**
     *      Does an immediate OR recent parent have a value layer?
     *  This is to help decide if we need a VALUE layer on a QUANTITY transaction.
     *  We DON'T if any of the immediate/recent txns, in the same direction, have VALUE (V or QV)
     *  And note that a transaction with "NO" for Q, V, or QV ('UPDATES_INV' => 'No') can be ignored
     *  both for direction and this calculation
     *
     * @param array     $values     The transaction tree
     * @param array     $entry      The docentry under discussion
     * @param string    $inOut      Is the transaction an innie or an outie?
     *
     * @return bool
     */
    private function parentWithValue($values, $entry, $inOut)
    {
        $docHdrKey = $values['RECORDNO'];
        // Organize the cache by dochdr, in case we get re-entered via a smart event...
        if ( ! isset($this->parentValueCache[$docHdrKey]) && $values['BACKORDER'] !== 'Yes') {
            $this->parentValueCache[$docHdrKey] = [];    // so we don't attempt this again
            $qry   = [];

            // We'll skip over things going in the wrong direction
            $io = "I";
            if ($inOut == 'Decrease') {
                $io = 'O';
            }

            // at this point we HAVE written out the docentry records for this transaction,
            // but NOT the docentrycost records.
            //
            // Here, I grab the CHAIN of docentry/docentrycosts going back from this transaction through
            //  prior transactions.  Some transactions have NO docentrycosts, or ones we don't care about, and those will still provide
            //  the docentry so we can crawl back to the PRIOR transaction, until we come to the end of the chain.
            //
            // 'VALUEFOUND' will be non-null when we have found a value layer with the same direction, item, and warehouse
            //      in the chain of source documents.
            $qry[] = "SELECT dec.record# as valuefound, de.record# as docentry#, de.dochdrkey, de.source_doclinekey
                        FROM docentrycost dec,
                            (
                                SELECT record#, dochdrkey, source_doclinekey, itemkey, warehousekey
                                  FROM docentrymst
                                 WHERE cny# = :1
                                 START WITH cny# = :1 AND dochdrkey = :2
                               CONNECT BY cny# = :1 and record# = PRIOR source_doclinekey
                            ) de
                        WHERE dec.cny# (+) =:1 AND dec.docentrykey (+) = de.record# 
                          AND dec.affects_inventory (+) != 'Q'
                          AND dec.in_out (+) = :3
                          AND dec.itemkey (+) = de.itemkey
                          AND dec.whsekey (+) = de.warehousekey
            ";

            $qry[] = GetMyCompany();
            $qry[] = $docHdrKey;
            $qry[] = $io;
            $res = QueryResult($qry);
            if ($res === false) {
                return false;
            }

            // save the records by docentry record#
            foreach ($res as $row) {
                $this->parentValueCache[$docHdrKey][$row['DOCENTRY#']][] = $row;
            }
        } // end of one-time cache setup

        // Now lets find the relevent records, starting with the current docentry.....
        $docentry         = $entry['RECORDNO'];
        $originalDocEntry = $docentry;

        while ($docentry && isset($this->parentValueCache[$docHdrKey][$docentry])) {

            $sourceDocLineKey = 0;
            foreach ($this->parentValueCache[$docHdrKey][$docentry] as $row) {

                // if 'VALUEFOUND' is not null, we have a value layer
                // but we don't care about value lauers in our own docentry
                if (($originalDocEntry != $docentry) && isset($row['VALUEFOUND'])) {
                    return true;            // this is a value docentrycost, so, yes, we found one
                }

                $sourceDocLineKey = $row['SOURCE_DOCLINEKEY'] ?? 0; // all docentrycost entries should have the same source....
            }

            // otherwise follow the chain to the end.....
            $docentry = $sourceDocLineKey;
        }
        return false;   // no value layer found
    }


    /**
     * @param array  $upsertContext      stuff to keep track of upserting
     * @param array  $values
     * @param array  $entry
     * @param array  $kitEntry
     * @param string $spi
     * @param string $inOut
     * @param string $updatesInv
     * @param array  $kitItem
     * @param bool   $skipUpdatingThisRecord        should we not actually WRITE this record?
     *
     * @return bool           did it work?
     */
    public function UpdateDocEntryCostEntries($upsertContext, $values, &$entry, &$kitEntry, $spi, $inOut, $updatesInv, $kitItem, $skipUpdatingThisRecord)
    {
        // if not updating inventory then no docentrycost record
        if ($updatesInv == 'No') {
            return true;
        }

        $ok = true;
        $updateInvMap = array('No' => 'N', 'Quantity' => 'Q', 'Value' => 'V', 'Quantity and Value' => 'QV');
        $affects_inventory_src = $affects_inventory = $updateInvMap[$updatesInv];
        $advancedBins = BinManager::areAdvanedBinsOn();

        if ($kitEntry['BINKEY'] === 0) {
            $kitEntry['BINKEY'] = null;     // warehouse transfer uses 0 to mean 'no bin'
        }

        if (BinManager::areAdvanedBinsOn()) {
            // just for good measure
            $kitEntry['AISLEKEY'] = null;
            $kitEntry['ROWKEY']   = null;
        }

        foreach (($kitEntry['COSTDETAILS'] ?? []) as $costkey => $costkeyEntry) {

            if ($spi == 'Internal') {
                // For inventory transaction docentrycost will always be for quantity and value
                if ($affects_inventory_src != 'QV') {
                    switch ($affects_inventory_src) {
                        case 'Q':
                            $costkeyEntry['COST'] = 0;
                            break;
                        case 'V':
                            $costkeyEntry['QTY'] = 0;
                            // for standard cost system should never affect the cost for value only documents
                            // it is created just to create GL entries.
                            if ($kitItem['COST_METHOD'] == 'S') {
                                $costkeyEntry['COST'] = 0;
                            }
                            break;
                    }

                    if (
                        $affects_inventory_src == 'V'
                        && (
                            $kitItem['COST_METHOD'] == 'F'
                            || $kitItem['COST_METHOD'] == 'L'
                        )
                        && empty($costkeyEntry['ADJDOCENTRYCOSTKEY'])
                    ) {
                        Globals::$g->gErr->addIAError(
                            'INV-0008', __FILE__ . ":" . __LINE__,
                            "Value-only inventory transactions for FIFO/LIFO items must be linked to " .
                            "Purchases or Inventory transactions that increase Quantity and/or Value", []
                        );
                        $ok = false;
                    }
                    $affects_inventory = 'QV';
                    $updatesInv = 'Quantity and Value';
                }

                // for standard cost system should never affect the cost of the original layer
                if (!empty($costkeyEntry['ADJDOCENTRYCOSTKEY']) && $kitItem['COST_METHOD'] == 'S') {
                    $costkeyEntry['COST'] = 0;
                }
            }

            // no costing record if both cost and qty are zero
            if (!ibccomp($costkeyEntry['COST'], '0', 10)
                && !ibccomp($costkeyEntry['QTY'], '0', 10)
            ) {
                return $ok; // ok may have been false in a past iteration from the error above
            }

            $newEntry = array(
                'DOCENTRYNO' => $entry['RECORDNO'],
                'SALE_PUR_TRANS' => $spi,
                'IN_OUT' => $inOut,
                'ITEMID' => $costkeyEntry['ITEMID'],
                'WAREHOUSEID' => $costkeyEntry['WAREHOUSE']['LOCATION_NO'],
                'QUANTITY' => $costkeyEntry['QTY'],
                'CONTRIBUTEDQTY' => $costkeyEntry['QTY'],
                'COST' => iround($costkeyEntry['COST'], ItemManager::AVERAGE_COST_DECIMALS),
                'UNITCOST' => $costkeyEntry['UNITCOST'],
                'LASTUNITCOST' => $costkeyEntry['LASTUNITCOST'] ?: $costkeyEntry['UNITCOST'],
                'CONTRIBUTEDCOST' => iround($costkeyEntry['COST'], ItemManager::AVERAGE_COST_DECIMALS),
                'DATEIN' => $entry['WHENCREATED'],
                'VALUE' => ibcmul($costkeyEntry['QTY'], $entry['PRICE'], ItemManager::AVERAGE_COST_DECIMALS),
                'COST_METHOD' => $costkeyEntry['COST_METHOD'],
                'AVERAGE_COST' => $costkeyEntry['AVERAGE_COST'],
                'WHSE_AVERAGE_COST' => $costkeyEntry['WHSE_AVERAGE_COST'],
                'SERIALNO' => $kitEntry['SERIALNO'],
                'LOTNO' => $kitEntry['LOTNO'],
                'AISLEKEY' => $advancedBins ? null : $kitEntry['AISLEKEY'],
                'ROWKEY' =>   $advancedBins ? null : $kitEntry['ROWKEY'],
                'BINKEY' => $kitEntry['BINKEY'],
                'ITEMGLGRPKEY' => $costkeyEntry['ITEMGLGROUP'],
                'EXPIRATIONDATE' => $kitEntry['EXPIRATIONDATE'],
                'AFFECTS_INVENTORY' => $updatesInv,
                'SYSTEMGENERATED' => 'F'
            );

            //get the cost of the entry
            $entry['COST'] = ibcadd($entry['COST'], $newEntry['COST'], ItemManager::AVERAGE_COST_DECIMALS);
            $entry['TRX_COST'] = $entry['COST'];

            if (isset($costkeyEntry['RECORD#'])) {
                $newEntry['DOCENTRYCOSTKEY'] = $costkeyEntry['RECORD#'];

            } else if ($costkeyEntry['ADJDOCENTRYCOSTKEY']) {

                // Inventory adjustment entries or purchase/sales documents that affects value only
                $newEntry['ADJDOCENTRYCOSTKEY'] = $costkeyEntry['ADJDOCENTRYCOSTKEY'];
            }

            if (( ! $skipUpdatingThisRecord) && $newEntry['ADJDOCENTRYCOSTKEY']) {
                // following is for adjusting system generated layer quantities in case of no back order.
                // If the quantity received in invoice is less than receiver then
                // it will split system generated layer.
                if ($spi == 'Purchase' && $inOut == 'Increase') {
                    $ok = $ok && $this->splitSystemGeneratedLayer($newEntry);
                }
            }

            $valueEntry = $newEntry;
            if ( ! $skipUpdatingThisRecord) {
                $ok = $ok && DocumentEntryCostManager::incrementalAddOrUpsert($upsertContext, $newEntry);
            }

            if ($ok) {
                $kitEntry['COSTDETAILS'][$costkey]['RECORDNO'] = $newEntry['RECORDNO'];
            }

            // create system generated 'V' only layer for 'Q' only document
            // Should not create if 'V' only document convert into 'Q' only (rare case)
            if ( (! $skipUpdatingThisRecord)
                && $affects_inventory == 'Q'
                && empty($newEntry['ADJDOCENTRYCOSTKEY'])
                && ( ! $this->parentWithValue($values, $entry, $inOut))) {
                $valueEntry['SYSTEMGENERATED'] = 'T';
                $valueEntry['AFFECTS_INVENTORY'] = 'Value';
                $valueEntry['COST'] = 0;
                $valueEntry['CONTRIBUTEDCOST'] = 0;
                $valueEntry['DOCENTRYCOSTKEY'] = $newEntry['DOCENTRYCOSTKEY'] ?: '';

                $ok = $ok && DocumentEntryCostManager::incrementalAddOrUpsert($upsertContext, $valueEntry);
            }
        }
        return $ok;
    }

    /**
     * @param array $newEntry
     *
     * @return bool
     */
    private function splitSystemGeneratedLayer($newEntry)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;

        $decMgr = Globals::$g->gManagerFactory->getManager('documententrycost');

        $adjValues = $decMgr->get($newEntry['ADJDOCENTRYCOSTKEY']);

        if ($adjValues['QUANTITY'] > $newEntry['QUANTITY']) {
            // reset existing sales that were tagged with this purchase layer if the quantity is more than
            // quantity received now in value document
            // Roger's note: in an escalation, there were many sales attached to this system-generated layer and the quantities were
            //          less than the new quantity.  This caused a crash.  Let's remove ALL the attached items and let MIV clean it up....
            $ok = $ok
                  && ExecStmt(
                      array(
                          "update docentrycost set docentrycostkey = null " .
                          "where cny#=:1 and docentrycostkey=:2 ",  // and quantity>:3,
                          GetMyCompany(),
                          $adjValues['RECORDNO'],       // this is the original system-generated layer
                          // $newEntry['QUANTITY']      // this is the quantity on the invoice (value layer) being added
                      )
                  );

            // now we removed ALL dependent sales/whatever from the system-generated layer.
            // we now set the quantity/contributed quantity of the system-generated layer to the
            // new invoice/value adjustment layer.
            $ok = $ok
                  && ExecStmt(
                      array(
                          "update docentrycost set quantity=:3, contributedqty=:3 " .
                          "where cny#=:1 and record#=:2",
                          GetMyCompany(),
                          $adjValues['RECORDNO'],       // this is the original system-generated layer
                          $newEntry['QUANTITY']
                      )
                  );

            unset($adjValues['RECORDNO']);
            $adjValues['QUANTITY'] = ibcsub(
                $adjValues['QUANTITY'], $newEntry['QUANTITY'], ItemManager::BASEUNITPRECISION
            );

            $adjValues['CONTRIBUTEDQTY'] = $adjValues['QUANTITY'];
            $adjValues['CONTRIBUTEDCOST'] = 0;

            $ok = $ok && $decMgr->add($adjValues); // the old but modified adjValues becomes the new value invoice

        } else if ($adjValues['QUANTITY'] < $newEntry['QUANTITY']) {
            $gErr->addIAError(
                'INV-0009', __FILE__ . ':' . __LINE__,
                "Enter a quantity on the invoice that is equal to or less than the quantity on the receiver", []
            );
            $ok = false;
        }

        return $ok;
    }
}
