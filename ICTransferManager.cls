<?php

/**
 * Manager class for Warehouse transfer
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Manager class for Warehouse transfer
 */
class ICTransferManager extends EntityManager
{
    const OUTDOCTYPE = "SYS-Warehouse Transfer Out";
    const INDOCTYPE = "SYS-Warehouse Transfer In";
    const INTRANSITDOCTYPE = "SYS-Warehouse In Transit";

    // Action
    const DRAFT_ACTION = 'Draft';
    const POST_ACTION = 'Post';
    const TRANSFERIN_ACTION = 'Transfer in';
    const TRANSFEROUT_ACTION = 'Transfer out';

    // State
    const DRAFT_STATE = 'Draft';
    const DRAFT_RAWSTATE = 'D';
    const INTRANSIT_STATE = 'In transit';
    const POST_STATE = 'Posted';

    // Type
    const IMMEDIATE_TYPE = 'Immediate';


    /**
     * @var bool    $_fromAPI
     */
    private $_fromAPI = false; // Was operation initiated from the API?

    /**
     * @var string|bool $_btnAction
     */
    private $_btnAction;

    /* @var bool $deferPermissionCheck */
    private static $deferPermissionCheck;

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * unset defer permission validation at Init
     */
    public static function unsetDeferPermValidation()
    {
        self::$deferPermissionCheck = false;
    }

    /**
     * Setter to defer the permission validation at Init
     *
     * @param string $noun
     */
    public static function setDeferPermValidation($noun='')
    {
        $addOp = GetOperationId('inv/lists/ictransfer/create');
        self::$deferPermissionCheck = CheckAuthorization($addOp, 1);
    }
    
    /**
     * Getter to defer the permission validation at Init
     *
     * @return bool
     */
    public static function getDeferPermValidation()
    {
        return self::$deferPermissionCheck;
    }
    
        /**
     * Validate the permission for draft record
     *
     * @param array &$values the transaction data
     * 
     * @return bool
     */    
    protected function validateDataForAuthorization( &$values ) 
    {
        if ( $values['TRANSFERSTATE'] === self::DRAFT_STATE
            || $values['TRANSFERSTATE'] === self::DRAFT_RAWSTATE
        ) {
            $ok = true;
            static::unsetDeferPermValidation();
        } else {
            $ok = parent::validateDataForAuthorization($values);
        }
        return $ok;
    }
    
    /**
     * Add
     *
     * @param array &$values to be added to the table
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "ICTransferManager::Add";

        $ok = $this->_QM->beginTrx($source);

        // Process the action value
        $ok = $ok && $this->preProcessAction($values, false);

        $ok = $ok && $this->validate($values, false);

        $ok = $ok && $this->translateValues($values);

        $ok = $ok && $this->getNextDocNo($values);

        $ok = $ok && $this->postTransactions($values, false);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not create Warehouse Transfer";
                $gErr->addIAError('INV-0592', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

            $this->_QM->rollbackTrx($source);
        }


        return $ok;
    }

    /**
     * Set
     *
     * @param array &$values new values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "ICTransferManager::Set";

        $ok = $this->_QM->beginTrx($source);

        // Process the action value
        $ok = $ok && $this->preProcessAction($values, true);

        $ok = $ok && $this->validate($values, true);

        $ok = $ok && $this->translateValues($values, true);

        $ok = $ok && $this->postTransactions($values, true);

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not update warehouse transfer record!";
                $gErr->addIAError('INV-0593', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function getNextDocNo(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $invSubsMgr = $gManagerFactory->getManager('invsetup');
        $seqID = $invSubsMgr->getWarehouseSequnce();

        if (!$seqID) {
            $msg = "Could not find Document Numbering for Warehouse Transfer";
            $gErr->addIAError('INV-0594', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            return false;
        }

        $seqMgr = $gManagerFactory->getManager('seqnum');
        $values['DOCNO'] = $seqMgr->GetNextSequenceNonBlocking($seqID);

        return true;
    }

    /**
     * @param string $outDocType
     * @param string $inDocType
     * @param string $inTransitDocType
     */
    private static function getTransferDocTypes(&$outDocType, &$inDocType, &$inTransitDocType)
    {
        $outDocType = self::OUTDOCTYPE;
        $inDocType = self::INDOCTYPE;
        $inTransitDocType = self::INTRANSITDOCTYPE;
    }

    /**
     * @param array $values - data for warehouse transfer docs (out, intransit, and in documents)
     * @param bool $needToRecreateTransferOut - true if the transfer out doc needs to be deleted and then recreated
     *
     * @return bool
     */
    private function handleCosts(&$values, $needToRecreateTransferOut)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;

        $itemIDs = array();
        foreach ($values['TRANSFEROUT']['ENTRIES'] as $entry) {
            $itemIDs[] = $entry['ITEMID'];
        }
        $itemIDs = array_unique($itemIDs);

        $itemMgr = $gManagerFactory->getManager('item');
        $itemCache = $itemMgr->GetItemsRawCache($itemIDs, true, null, 'inv');
        $uomCache = $itemMgr->GetUOMInfoCache($itemIDs, true);


        /** @noinspection PhpUndefinedVariableInspection */
        $outWarehouseID = $entry['WAREHOUSEID'];

        if (empty($outWarehouseID)) {
            $msg = "Required field 'From warehouse' is missing";
            $gErr->addIAError('INV-0595', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            $ok = false;
        }

        if (empty($values['TRANSACTIONDATE'])) {
            $msg = "Required field 'Transaction date' is missing";
            $gErr->addIAError('INV-0596', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            $ok = false;
        }

        if ($ok) {
            $allowNegativeInventory = IsNegativeInventoryAllowed();
            // get warehouse information to check, whether allow negative inventory for warehouse or not.
            // if and only if Turn off negative inventory is enabled in Inv->configuration
            if ( ! $allowNegativeInventory ) {
                $warehouseMgr = $gManagerFactory->getManager('warehouse');
                $allowNegativeInventory = $warehouseMgr->isNegativeInventoryAllowed($outWarehouseID);
            }

            $costHistMgr = $gManagerFactory->getManager('costhistory');

            $params = array(
                'selects' => array('QTYONHAND', 'ITEMKEY'),
                'filters' => array(
                    array(
                        array('ITEMKEY', 'IN', $itemIDs),
                        array('WHSEKEY', '=', $outWarehouseID),
                        array('ASON', '<=', $values['TRANSACTIONDATE']),
                    )
                ),
                'orders' => array(array('ASON', 'desc')),
            );
            $res = $costHistMgr->GetList($params);

            $onHandQty = array();

            foreach ( $res as $val) {
                if (!isset($onHandQty[$val['ITEMKEY']])) {
                    $onHandQty[$val['ITEMKEY']] = $val['QTYONHAND'];
                }
            }

            foreach ($values['TRANSFEROUT']['ENTRIES'] as $key => $entry) {
                if ($entry['ITEMID']) {

                    $itemId = $entry['ITEMID'];
                    if (empty($itemCache[$itemId])) {
                        $msg = "Item ID '".$entry['ITEMID']."' is invalid.";
                        $gErr->addIAError('INV-0603', __FILE__ . ':' . __LINE__, $msg,
                        ['ENTRY_ITEMID'=>$itemId]);
                        $ok = false;
                    } else {

                        if (!isset($onHandQty[$itemId])) {
                            $onHandQty[$itemId] = 0;
                        }

                        $isSerialized = $itemMgr->IsItemSerialized($itemId, true, $itemCache[$itemId]);
                        $mustHaveQty  = $isSerialized || (!$allowNegativeInventory);

                        if ( $values['TRANSFERSTATE'] !== self::DRAFT_STATE
                             && ($entry['QUANTITY'] > $onHandQty[$itemId] && $mustHaveQty)
                             && $needToRecreateTransferOut === true ) {
                            $qn     = $entry['QUANTITY'];
                            $qoh    = $onHandQty[$itemId];
                            $row    = $key + 1;
                            $gErr->addIAError('INV-0604', __FILE__ . ':' . __LINE__,
                                "There is not enough quantity to transfer.",
                                [],
                                "In line # $row for item $itemId, the quantity to transfer is $qn,
                                but the available quantity is $qoh.",
                                ['ROW'=>$row,'ITEMID'=>$itemId,'QN'=>$qn,'QOH'=>$qoh],
                                "Either transfer less quantity or ensure enough quantity is available.",
                                []);
                            $ok = false;
                        }
                    }
                }
            }
        }
        $ok = $ok && $this->expandItemsForFIFOLIFO($values, $itemCache, $itemIDs, $outWarehouseID, $needToRecreateTransferOut,$uomCache);

        $ok = $ok && $this->setAverageCost($values, $itemCache, $itemIDs, $outWarehouseID,$uomCache);

        $ok = $ok && $this->setStandardCost($values, $itemCache, $itemIDs, $outWarehouseID);

        return $ok;
    }

    /**
     * @param array     $values
     * @param array     $itemCache
     * @param string[]  $itemIDs
     * @param string    $outWarehouseID
     *
     * @return bool
     */
    private function setStandardCost(&$values, $itemCache, $itemIDs, $outWarehouseID)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $itemStdCostMgr = $gManagerFactory->getManager('itemwarehousestdcost');

        $params = array(
            'selects' => array('ITEMID', 'WAREHOUSEID', 'EFFECTIVE_START_DATE', 'STANDARD_COST'),
            'filters' => array(array(
                                   array('ITEMID', 'IN', $itemIDs),
                                   array('WAREHOUSEID', '=', $outWarehouseID),
                                   array('EFFECTIVE_START_DATE', '<=', $values['TRANSACTIONDATE']),
                               )
            ),
            'orders' => array(array('EFFECTIVE_START_DATE', 'desc')),
        );
        $res = $itemStdCostMgr->GetList($params);

        $stdCost = array();
        foreach ($res as $r) {
            if (empty($stdCost[$r['ITEMID']])) {
                $stdCost[$r['ITEMID']] = $r['STANDARD_COST'];
            }
        }

        foreach ( $values['TRANSFEROUT']['ENTRIES'] as &$outEntry) {
            if ($itemCache[$outEntry['ITEMID']]['COST_METHOD'] == 'S') {
                if (empty($stdCost[$outEntry['ITEMID']])) {
                    $cost = $itemCache[$outEntry['ITEMID']]['STANDARD_COST'];
                } else {
                    $cost = $stdCost[$outEntry['ITEMID']];
                }

                $outEntry['TRX_PRICE'] = $cost;
                $outEntry['UIPRICE'] = $cost;
            }
        }
        unset($outEntry);

        foreach ( $values['TRANSFERIN']['ENTRIES'] as &$inEntry) {
            if ($itemCache[$inEntry['ITEMID']]['COST_METHOD'] == 'S') {
                if (empty($stdCost[$inEntry['ITEMID']])) {
                    $cost = $itemCache[$inEntry['ITEMID']]['STANDARD_COST'];
                } else {
                    $cost = $stdCost[$inEntry['ITEMID']];
                }
                $cost = ibcmul($cost, $values['EXCHANGE_RATE'], $itemCache[$inEntry['ITEMID']]['PRECISION'], true);

                $inEntry['TRX_PRICE'] = $cost;
                $inEntry['UIPRICE'] = $cost;
            }
        }
        unset($inEntry);

        return true;

    }

    /**
     * @param array     $values
     * @param array     $itemCache
     * @param string[]  $itemIDs
     * @param string    $outWarehouseID
     * @param array     $uomCache
     *
     * @return bool
     */
    private function setAverageCost(&$values, $itemCache,
        /** @noinspection PhpUnusedParameterInspection */ $itemIDs, $outWarehouseID,$uomCache)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $itemMgr = $gManagerFactory->getManager('item');
        $averageCost = array();
        foreach ( $values['TRANSFEROUT']['ENTRIES'] as &$outEntry) {
            if ($itemCache[$outEntry['ITEMID']]['COST_METHOD'] == 'A') {
                if (empty($averageCost[$outEntry['ITEMID']])) {
                    $averageCost[$outEntry['ITEMID']] = $itemMgr->GetAverageCost(
                        $outEntry['ITEMID'], $outWarehouseID, $values['TRANSACTIONDATE']
                    );
                }
                $cost = is_numeric($averageCost[$outEntry['ITEMID']]) ? $averageCost[$outEntry['ITEMID']]: 0;
                $itemPrecision = $itemCache[$outEntry['ITEMID']]['PRECISION'];
                $unitFactor = 1;
                 if (is_numeric($outEntry['UNITFACTOR'])){
                     $unitFactor =$outEntry['UNITFACTOR'];
                 } elseif (is_numeric($uomCache[$outEntry['ITEMID']][$outEntry['UNIT']]['CONVFACTOR'])){
                     $unitFactor =$uomCache[$outEntry['ITEMID']][$outEntry['UNIT']]['CONVFACTOR'];
                 }
                $trxcost = ibcmul($cost, $unitFactor, $itemPrecision, true);
                $outEntry['TRX_PRICE'] = $trxcost;
                $outEntry['UIPRICE'] = $trxcost;
            }
        }
        unset($outEntry);

        foreach ( $values['TRANSFERIN']['ENTRIES'] as &$inEntry) {
            if ($itemCache[$inEntry['ITEMID']]['COST_METHOD'] == 'A') {
                $cost = is_numeric($averageCost[$inEntry['ITEMID']]) ? $averageCost[$inEntry['ITEMID']] : 0;
                $itemPrecision = $itemCache[$inEntry['ITEMID']]['PRECISION'];
                $unitFactor = 1;
                if (is_numeric($inEntry['UNITFACTOR'])){
                    $unitFactor =$inEntry['UNITFACTOR'];
                } elseif (is_numeric($uomCache[$inEntry['ITEMID']][$inEntry['UNIT']]['CONVFACTOR'])){
                    $unitFactor =$uomCache[$inEntry['ITEMID']][$inEntry['UNIT']]['CONVFACTOR'];
                }
                $cost = ibcmul($cost, $unitFactor, $itemPrecision, true);
                $cost = ibcmul($cost, $values['EXCHANGE_RATE'], $itemPrecision, true);
                $inEntry['TRX_PRICE'] = $cost;
                $inEntry['UIPRICE'] = $cost;
            }
        }
        unset($inEntry);

        return true;

    }

    /**
     * @param array     $trackingEntries
     * @param array     $itemInfo
     *
     * @return bool     true if $trackingEntries contains tracking data
     */
    private function hasTrackingData($trackingEntries, $itemInfo)
    {
        foreach ($trackingEntries as $trackingEntry) {
            if (($itemInfo['ENABLEBIN'] === 'T' && !empty($trackingEntry['BINID']))
                || ($itemInfo['ENABLESNO'] === 'T' && !empty($trackingEntry['SERIALNO']))
                || ($itemInfo['ENABLELOT'] === 'T' && !empty($trackingEntry['LOTNO']))
                || ($itemInfo['ENABLEEXPIRATION'] === 'T' && !empty($trackingEntry['EXPIRATION']))) {
                return true;
            }
        }
        return false;
    }

    /**
     * @param array     $values
     * @param array     $itemCache
     * @param string[]  $itemIDs
     * @param string    $outWarehouseID
     * @param bool      $needToRecreateTransferOut - true if the transfer out doc needs to be deleted and then recreated
     * @param array     $uomCache
     *
     * @return bool
     */
    private function expandItemsForFIFOLIFO(&$values, $itemCache, $itemIDs, $outWarehouseID, $needToRecreateTransferOut,$uomCache)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $itemMgr = $gManagerFactory->getManager('item');

        //This block gather an array of items containing the qty and the cost of purchasing (in docs) for those qty,
        //to be used in the forming of WH transfer entries below at what qty and at what cost.
        $costLayers = array();
        if ($needToRecreateTransferOut) {
            //We are recreating the transfer-out doc.
            //We need to rely on the costlayers to tell us which qty is available at which cost layer.
            if (!empty($itemIDs) && !empty($outWarehouseID)) {
                $costLayers = LIFOFIFOCosting::getCostLayers($itemIDs, $outWarehouseID);
            }
        } else {
            //We are NOT recreating transfer-out doc.
            //We will use transfer-out doc db entries to guide us for which qty in which cost layer to use for the
            //transfer-in and in-transit docs below.
            foreach ($values['DB_ENTRIES'] as $dbEntry) {
                if ($dbEntry['IN_OUT'] === 'O') {
                    $costLayer = [];
                    $costLayer['QTYLEFT'] = $dbEntry['QUANTITY'];
                    $costLayer['COST'] = $dbEntry['TRX_PRICE'];
                    $costLayer['DOCENTRYKEY'] = $dbEntry['DOCENTRYKEY'];
                    $costLayers[$dbEntry['ITEMID']][] = $costLayer;
                }
            }
        }

        $newEntries = array();
        $outEntries = array();
        $inEntries = array();
        foreach ($values['TRANSFEROUT']['ENTRIES'] as $key => $entry) {
            if ($itemCache[$entry['ITEMID']]['COST_METHOD'] == 'F'
                || $itemCache[$entry['ITEMID']]['COST_METHOD'] == 'L') {
                $itemId = $entry['ITEMID'];
                $haveTrackedEntries = false;
                $isTrackedItem = $itemMgr->IsItemSerialized($itemId, true, $itemCache[$itemId]);
                $outTrackingSpecsInput = [];
                $inTrackingSpecsInput = [];
                $itemPrecision = $itemCache[$entry['ITEMID']]['PRECISION'] ?? ItemManager::BASEUNITPRECISION;
                if ($isTrackedItem) {
                    $outTrackingSpecsInput = $entry['TRACKINGENTRIES'];
                    unset($entry['TRACKINGENTRIES']);
                    $inTrackingSpecsInput = $values['TRANSFERIN']['ENTRIES'][$key]['TRACKINGENTRIES'];
                    $haveTrackedEntries = $this->hasTrackingData($outTrackingSpecsInput, $itemCache[$itemId]);
                }

                $qty = $entry['QUANTITY'];
                if ($costLayers[$entry['ITEMID']]) {

                    $baseUnit = $uomCache[$entry['ITEMID']][$entry['UNIT']]['ISBASE'];

                    if ($baseUnit !== 'T') {
                        $msg = "Only base unit is allowed for FIFO/LIFO items. Unit '" . $entry['UNIT']
                               . "' is not a base unit";
                        $corr = "Change the unit and try again.";
                        $gErr->addIAError('INV-0605', __FILE__ . ':' . __LINE__,
                         $msg,['ENTRY_UNIT'=>$entry['UNIT']],
                         '',[],$corr,[]);
                        return false;
                    }

                    //Walk through each cost layer and use up the qty in each one until we satisfy what the user is transfering
                    $layerCount = count($costLayers[$entry['ITEMID']]);
                    for ($index = 0; $index < $layerCount; ) { //We purposely not increment the $index here as we will do it at the bottom of this loop

                        //This is the current cost layer we are looping on
                        $cost = $costLayers[$entry['ITEMID']][$index];

                        //Check to see if there is any qty left in this $cost layer to use to transfer
                        if ($cost['QTYLEFT'] <= 0) {
                            $index++;
                            continue; //No qty left to use
                        }

                        $outEntry = $entry;
                        $outEntry['TRX_PRICE'] = $cost['COST'];
                        $outEntry['UIPRICE'] = $cost['COST'];

                        //See if the cost layers have docentry, if so, we need to use it so that when we save this
                        //WH transfer (ICTransferHdr/ICTransferEntry), we will have the correct docentry for the OUT entries.
                        //This case will happen when we are NOT recreating the transfer-out doc ($needToRecreateTransferOut = false)
                        if (!$needToRecreateTransferOut) {
                            $outEntry['DOCENTRYKEY'] = $cost['DOCENTRYKEY'];
                        }

                        $inEntry = $values['TRANSFERIN']['ENTRIES'][$key];

                        $cost['COST'] = ibcmul($cost['COST'], $values['EXCHANGE_RATE'], $itemCache[$inEntry['ITEMID']]['PRECISION'], true);
                        $inEntry['TRX_PRICE'] = $cost['COST'];
                        $inEntry['UIPRICE'] = $cost['COST'];

                        $costLayerQtyLeft = $cost['QTYLEFT'];
                        if ($haveTrackedEntries ) {
                            /*
                             * Now that we know the quantity required by this cost layer, consume only as many
                             * tracking specification--or parts thereof--as required by each of the in and out entries.
                             */
                            $trackingQuantityNeeded = $cost['QTYLEFT'];
                            if (!empty($outTrackingSpecsInput) && isset($outTrackingSpecsInput[0]['QUANTITY'])
                                && $cost['QTYLEFT'] > $outTrackingSpecsInput[0]['QUANTITY']) {
                                //We should only use up to what is left of qty in the cost layer and not the whole thing
                                $trackingQuantityNeeded = $outTrackingSpecsInput[0]['QUANTITY'];
                                $costLayerQtyLeft = $trackingQuantityNeeded;
                            }

                            $qty = ibcsub($qty, $trackingQuantityNeeded, $itemPrecision);

                            $outTrackingSpecsOutput = [];
                            $inTrackingSpecsOutput = [];
                            while (!empty($outTrackingSpecsInput) && $trackingQuantityNeeded > 0 &&
                                   $trackingQuantityNeeded >= $outTrackingSpecsInput[0]['QUANTITY']) {
                                // This entry can consume the entirety of this first tracking specification
                                $outNextTrackingSpec = array_shift($outTrackingSpecsInput);
                                $trackingQuantityNeeded = ibcsub($trackingQuantityNeeded, $outNextTrackingSpec['QUANTITY'], $itemPrecision);
                                $outTrackingSpecsOutput[] = $outNextTrackingSpec;

                                $inTrackingSpecsOutput[] = array_shift($inTrackingSpecsInput);
                            }
                            if (!empty($outTrackingSpecsInput) && $trackingQuantityNeeded > 0) {
                                // Remaining quantity doesn't completely encompass the next tracking spec, so split it
                                $outPartialTrackingSpec = $outTrackingSpecsInput[0];
                                $outPartialTrackingSpec['TRACK_QUANTITY'] = $outPartialTrackingSpec['QUANTITY'] = $trackingQuantityNeeded;
                                $outTrackingSpecsInput[0]['TRACK_QUANTITY'] = $outTrackingSpecsInput[0]['QUANTITY'] = ibcsub($outTrackingSpecsInput[0]['QUANTITY'], $trackingQuantityNeeded, $itemPrecision);
                                $outTrackingSpecsOutput[] = $outPartialTrackingSpec;

                                $inPartialTrackingSpec = $inTrackingSpecsInput[0];
                                $inPartialTrackingSpec['TRACK_QUANTITY'] = $inPartialTrackingSpec['QUANTITY'] = $trackingQuantityNeeded;
                                $inTrackingSpecsInput[0]['TRACK_QUANTITY'] = $inTrackingSpecsInput[0]['QUANTITY'] = ibcsub($inTrackingSpecsInput[0]['QUANTITY'], $trackingQuantityNeeded, $itemPrecision);
                                $inTrackingSpecsOutput[] = $inPartialTrackingSpec;
                            }
                            // Finally, associate the entries with the tracking specifications they consume
                            $outEntry['TRACKINGENTRIES'] = $outTrackingSpecsOutput;
                            $inEntry['TRACKINGENTRIES'] = $inTrackingSpecsOutput;
                        } else {
                            $qty = ibcsub($qty, $costLayerQtyLeft, $itemPrecision);
                        }

                        if ($qty <= 0) {
                            $outEntry['UIQTY'] = ibcadd($qty, $costLayerQtyLeft, $itemPrecision);
                            $outEntry['QUANTITY'] = $outEntry['UIQTY'];
                            $outEntries[] = $outEntry;

                            $inEntry['UIQTY'] = ibcadd($qty, $costLayerQtyLeft, $itemPrecision);
                            $inEntry['QUANTITY'] = $inEntry['UIQTY'];
                            $inEntries[] = $inEntry;

                            $newEntries[] = $outEntry;
                            $newEntries[] = $inEntry;

                            //Preserves the qty left to be used in current cost layer
                            $costLayers[$entry['ITEMID']][$index]['QTYLEFT'] = ibcsub($costLayers[$entry['ITEMID']][$index]['QTYLEFT'], $outEntry['QUANTITY'],$itemPrecision);

                            break;
                        } else {
                            $outEntry['UIQTY'] = $costLayerQtyLeft;
                            $outEntry['QUANTITY'] = $outEntry['UIQTY'];
                            $outEntries[] = $outEntry;

                            $inEntry['UIQTY'] = $costLayerQtyLeft;
                            $inEntry['QUANTITY'] = $inEntry['UIQTY'];
                            $inEntries[] = $inEntry;

                            $newEntries[] = $outEntry;
                            $newEntries[] = $inEntry;

                            //Preserves the qty left to be used in current cost layer
                            $costLayers[$entry['ITEMID']][$index]['QTYLEFT'] = ibcsub($costLayers[$entry['ITEMID']][$index]['QTYLEFT'], $outEntry['QUANTITY'], $itemPrecision);
                        }

                        //Only move to the next cost layer if there is qtyleft is zero or less
                        if ($costLayers[$entry['ITEMID']][$index]['QTYLEFT'] <= 0) {
                            $index++;
                        }
                    }
                    // ran off the end of the source layers available,
                    // yet we still have more quantity?
                    if ($qty > 0) {
                        $outEntry = $entry;
                        $outEntry['TRX_PRICE']   = "0";
                        $outEntry['UIPRICE']     = "0";
                        $outEntry['UIQTY']       = $qty;
                        $outEntry['QUANTITY']    = $qty;
                        $outEntry['DOCENTRYKEY'] = null;
                        $outEntries[]            = $outEntry;

                        $inEntry                 = $values['TRANSFERIN']['ENTRIES'][$key];
                        $inEntry['TRX_PRICE']    = "0";
                        $inEntry['UIPRICE']      = "0";
                        $inEntry['UIQTY']        = $qty;
                        $inEntry['QUANTITY']     = $qty;
                        $inEntry['DOCENTRYKEY']  = null;
                        $inEntries[]             = $inEntry;

                        $newEntries[]            = $outEntry;
                        $newEntries[]            = $inEntry;
                    }
                } else {
                    $entry['TRX_PRICE'] = 0;
                    $entry['UIPRICE'] = 0;

                    $values['TRANSFERIN']['ENTRIES'][$key]['TRX_PRICE'] = 0;
                    $values['TRANSFERIN']['ENTRIES'][$key]['UIPRICE'] = 0;

                    $outEntries[] = $entry;
                    $inEntries[] = $values['TRANSFERIN']['ENTRIES'][$key];

                    $newEntries[] = $entry;
                    $newEntries[] = $values['TRANSFERIN']['ENTRIES'][$key];
                }
            } else {
                $outEntries[] = $entry;
                $inEntries[] = $values['TRANSFERIN']['ENTRIES'][$key];

                $newEntries[] = $entry;
                $newEntries[] = $values['TRANSFERIN']['ENTRIES'][$key];
            }
        }

        $values['TRANSFEROUT']['ENTRIES'] = $outEntries;
        $values['TRANSFERIN']['ENTRIES'] = $inEntries;
        $values['ENTRIES'] = $newEntries;

        return true;
    }

    /**
     * @param array $values
     * @param bool  $update
     *
     * @return bool
     */
    private function postTransactions(&$values, $update)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;
        $outDocEntryKeysForInTransit = [];
        $outDocEntryKeysForTransferIn = [];

        self::getTransferDocTypes($outDocType, $inDocType, $inTransitDocType);

        $outMgr = $gManagerFactory->getManager('invdocument', true, array( 'DOCTYPE' => $outDocType));
        $inMgr  = $gManagerFactory->getManager('invdocument', true, array( 'DOCTYPE' => $inDocType));
        $inTransitMgr  = $gManagerFactory->getManager('invdocument', true, array( 'DOCTYPE' => $inTransitDocType));

        $isTransitTransfer = $values['TRANSFERTYPE'] == self::INTRANSIT_STATE;

        //
        //Code block to create transfer out document
        //
        $values['TRANSFEROUT']['DOCPARID'] = $outDocType;
        $values['TRANSFEROUT']['DOCNO'] = $values['DOCNO'] . '-Out';
        $values['TRANSFEROUT']['PONUMBER'] = $values['REFERENCENO'];
        $values['TRANSFEROUT']['ALLOWCREATION'] = true;
        $needToRecreateTransferOut = true; //default to true as the transfer out doc needs to initially be created
        if ($update) {
            //We get here when we are editing. So, we need to recreate a new transfer-out doc if one of the following is true
            //1. If transfer TYPE is transfer immediately.
            //2. If transfer STATE is in-transit, meaning we are updating a draft WH transfer.
            //3. We need to call checkIfTransferOutDataChanged to see if any data has changed that warrant a recreate of a new transfer-out doc.
            //We need to do this check before any call to deleteWithOverride.
            $needToRecreateTransferOut = $values['TRANSFERTYPE'] === self::IMMEDIATE_TYPE
                                         || $values['TRANSFERSTATE'] === self::INTRANSIT_STATE
                                         || $this->checkIfTransferOutDataChanged($values);

            $ok = $ok && $inMgr->deleteWithOverride( $values['TRANSFERIN' ]['DOCID'], true);
            unset($values['TRANSFERIN']['RECORDNO']);
            if($isTransitTransfer){
                $ok = $ok && $outMgr->deleteWithOverride($values['INTRANSIT']['DOCID'], true);
                unset($values['INTRANSIT']['RECORDNO']);
            }
            if ($needToRecreateTransferOut === true) {
                $ok = $ok && $outMgr->deleteWithOverride($values['TRANSFEROUT']['DOCID'], true);
                unset($values['TRANSFEROUT']['RECORDNO']);
            }
        }

        $ok = $ok && $this->handleCosts($values, $needToRecreateTransferOut);

        // Specific for the TRANSFERTYPE = In transit, we need to repopulate INTRANSIT Entries from TRANSFERIN Entries.
        // Because handleCosts calcualte the values based on the ITEMTYPE (FIFO,STD,AVG) and populate its Entries.
        // So we should use the newly calculated Entries from TRANSFERIN and copy it to INTRANSIT.
        if($isTransitTransfer){
            $values['INTRANSIT']['ENTRIES'] = $values['TRANSFERIN']['ENTRIES'];
        }

        if ($ok && $needToRecreateTransferOut === true) {
            $ok = $outMgr->add($values['TRANSFEROUT']);
        }
        if (!$ok) {
            $msg = "Could not create transfer out record!";
            $gErr->addIAError('INV-0597', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
        }

        //
        //Code block to create in transit document
        //
        if ($ok && $isTransitTransfer) {
            $values['OUTDOCHDRKEY'] = $values['TRANSFEROUT']['RECORDNO'];
            foreach ($values['TRANSFEROUT']['ENTRIES'] as $outEntry) {
                $outDocEntryKeysForInTransit[] = ($needToRecreateTransferOut === true)? $outEntry['RECORDNO'] : $outEntry['DOCENTRYKEY'];
            }

            $values['INTRANSIT']['DOCPARID'] = $inTransitDocType;
            $values['INTRANSIT']['DOCNO'] = $values['DOCNO'] . '-Intransit';
            $values['INTRANSIT']['PONUMBER'] = $values['REFERENCENO'];
            $values['INTRANSIT']['CREATEDFROM'] = $values['TRANSFEROUT']['DOCID'];
            $values['INTRANSIT']['ALLOWCREATION'] = true;
            foreach ($values['INTRANSIT']['ENTRIES'] as $ikey => &$intransitEntry) {
                $intransitEntry['SOURCE_DOCID'] = $values['TRANSFEROUT']['DOCID'];
                $intransitEntry['SOURCE_DOCKEY'] = $values['TRANSFEROUT']['RECORDNO'];
                /** @noinspection PhpUndefinedVariableInspection */
                $intransitEntry['SOURCE_DOCLINEKEY'] = $outDocEntryKeysForInTransit[$ikey];
            }
            unset($intransitEntry);

            $ok = $ok && $inTransitMgr->add($values['INTRANSIT']);
            if (!$ok) {
                $msg = "Could not create transfer in record!";
                $gErr->addIAError('INV-0598', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

        }

        //
        //Code block to create transfer in
        //
        if ($ok) {
            if($isTransitTransfer){
                $createdFrom = $values['INTRANSIT']['DOCID'];
                $sourceDocKey = $values['INTRANSIT']['RECORDNO'];
                $sourceDocForTransferIn = 'INTRANSIT';
            }else{
                $createdFrom = $values['TRANSFEROUT']['DOCID'];
                $sourceDocKey = $values['TRANSFEROUT']['RECORDNO'];
                $sourceDocForTransferIn = 'TRANSFEROUT';
            }
            $values['OUTDOCHDRKEY'] =  $values['TRANSFEROUT']['RECORDNO'];
            foreach ($values[$sourceDocForTransferIn]['ENTRIES'] as $outEntry) {
                $outDocEntryKeysForTransferIn[] = $outEntry['RECORDNO'];
            }

            $values['TRANSFERIN']['DOCPARID'] = $inDocType;
            $values['TRANSFERIN']['DOCNO'] = $values['DOCNO'] . '-In';
            $values['TRANSFERIN']['PONUMBER'] = $values['REFERENCENO'];
            $values['TRANSFERIN']['CREATEDFROM'] = $createdFrom;
            $values['TRANSFERIN']['ALLOWCREATION'] = true;
            foreach ($values['TRANSFERIN']['ENTRIES'] as $ikey => &$entry) {
                $entry['SOURCE_DOCID'] = $createdFrom;
                $entry['SOURCE_DOCKEY'] = $sourceDocKey;
                /** @noinspection PhpUndefinedVariableInspection */
                $entry['SOURCE_DOCLINEKEY'] = $outDocEntryKeysForTransferIn[$ikey];
            }
            unset($entry);

            $ok = $ok && $inMgr->add($values['TRANSFERIN']);
            if (!$ok) {
                $msg = "Could not create transfer in record!";
                $gErr->addIAError('INV-0677', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

        }

        if ($ok) {
            $values['INDOCHDRKEY'] = $values['TRANSFERIN']['RECORDNO'];
            $values['INTRANSITDOCHDRKEY'] = $values['INTRANSIT']['RECORDNO'];
            foreach ($values['TRANSFERIN']['ENTRIES'] as $inEntry) {
                $inDocEntryKeys[] = $inEntry['RECORDNO'];
            }

            if($isTransitTransfer){
                $outDocEntryKeys = $outDocEntryKeysForInTransit;
            } else {
                $outDocEntryKeys = $outDocEntryKeysForTransferIn;
            }

            $outIndex = 0;
            $inIndex = 0;
            foreach ($values['ENTRIES'] as &$entry) {
                if ($entry['IN_OUT'] == 'O') {
                    $entry['DOCHDRKEY'] = $values['OUTDOCHDRKEY'];
                    /** @noinspection PhpUndefinedVariableInspection */
                    $entry['DOCENTRYKEY'] = $outDocEntryKeys[$outIndex];
                    $outIndex++;
                } else {
                    $entry['DOCHDRKEY'] = $values['INDOCHDRKEY'];
                    /** @noinspection PhpUndefinedVariableInspection */
                    $entry['DOCENTRYKEY'] = $inDocEntryKeys[$inIndex];
                    $inIndex++;
                }
            }
        }

        return $ok;
    }

    /**
     *  Load up the current db values (RECORDNO) and compare with the passed in values to see if the
     *  transfer out data has changed.
     *
     * @param array $values - transfer transactions (out, in, transit) data
     *
     * @return bool true if the transfer out data have changed, false if not
     */
    private function checkIfTransferOutDataChanged(&$values)
    {
        //Get the transfer data from db to compare below
        $ictransferMgr = Globals::$g->gManagerFactory->getManager('ictransfer');
        $fields['DB_ENTRIES'] = true; //So that the call to Get will preserve the ICTransferEntries
        $dbValues = $ictransferMgr->Get($values['RECORDNO'], $fields);
        if (!$dbValues) {
            return true;
        }
        $this->translateValues($dbValues, true); //We need to translate so data match with setup to compare correctly

        // If this is the API, the client may not have told us what the recordnumbers are for the entries;
        // if the entry has no recordnumber/docentrykey, fill it in from the just-read data.  See IA-118127
        if (isset($values['TRANSFEROUT']['ENTRIES']) && isset($dbValues['TRANSFEROUT']['ENTRIES'])) {
            foreach ($values['TRANSFEROUT']['ENTRIES'] as $key => $entryRow) {
                $recordno = $entryRow['RECORDNO'] ?? ($entryRow['DOCENTRYKEY'] ?? 0);
                if ($recordno == 0) {
                    $existingRecordno = $dbValues['TRANSFEROUT']['ENTRIES'][$key]['DOCENTRYKEY'] ?? 0;
                    // if no existing recordno then this is a new out entry
                    if ($existingRecordno) {
                        $values['TRANSFEROUT']['ENTRIES'][$key]['RECORDNO']    = $existingRecordno;
                        $values['TRANSFEROUT']['ENTRIES'][$key]['DOCENTRYKEY'] = $existingRecordno;
                    }
                }
            }
        }

            //Compare header values
        $compareFields = $ictransferMgr->_schemas[$ictransferMgr->_entity]['schema'];
        $dbValues['INDATE'] = $values['INDATE']; //Don't need to compare the transfer in date as we alway saving it
        $dbValues['TRANSFERSTATE'] = $values['TRANSFERSTATE']; //Don't need to compare the transfer STAET as it's internal and we change it base on action of transfer in or save
        $match = Matchmaker::detailedCompare( $compareFields, $dbValues, $values );
        if (!$match) {
            return true;
        }

        //Compare ENTRIES and TRACKINGENTRIES values
        $entriesMgr = Globals::$g->gManagerFactory->getManager('ictransferitem');
        $entriesCompareFields = $entriesMgr->_schemas[$entriesMgr->_entity]['schema'];
        $docEntryTrackMgr = null;
        $trackingCompareFields = [];
        foreach (($values['TRANSFEROUT']['ENTRIES'] ?? []) as $key => $entriesRow) {
            //Compare the each entry row fields
            $match = Matchmaker::detailedCompare($entriesCompareFields,
                                                 $dbValues['TRANSFEROUT']['ENTRIES'][$key],
                                                 $values['TRANSFEROUT']['ENTRIES'][$key]);
            if (!$match) {
                return true;
            }
            if (!$docEntryTrackMgr) {
                $docEntryTrackMgr = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
                $trackingCompareFields = $docEntryTrackMgr->_schemas[$docEntryTrackMgr->_entity]['schema'];
                unset($trackingCompareFields['BINID']); //We already comparing BINKEY and translateValues will prefill this value to UI display
            }

            //Compare the tracking row fields in each entry row
            foreach (($values['TRANSFEROUT']['ENTRIES'][$key]['TRACKINGENTRIES'] ?? []) as $keyTracking => $trackingRow) {
                $match = Matchmaker::detailedCompare($trackingCompareFields,
                                                     $dbValues['TRANSFEROUT']['ENTRIES'][$key]['TRACKINGENTRIES'][$keyTracking],
                                                     $values['TRANSFEROUT']['ENTRIES'][$key]['TRACKINGENTRIES'][$keyTracking]);
                if (!$match) {
                    return true;
                }
            }

        }

        //No data change
        $values['DB_ENTRIES'] = $dbValues['DB_ENTRIES'];
        return false;
    }

    /**
     * Process the action value
     *
     * @param array $values
     * @param bool $update
     *
     * @return bool false if error else true
     */
    protected function preProcessAction(&$values, $update = false)
    {
        $ok = true;

        if(isset(Request::$r->_action) && Request::$r->_action != ''){
            $this->_btnAction = Request::$r->_action;
        } else  if(isset($values['ACTION']) && $values['ACTION'] != ''){
            // Validate and translate transaction action
            $ok = $ok && $this->validateTransactionAction($values, $update);
            $ok = $ok && $this->processAction($values);
        } else {
            //This is actually from API or CSV and ACTION is not provided.
            //So we need determine the default action based on the TRANSFERTYPE value
            $this->_btnAction = 'post';
            if(isset($values['TRANSFERTYPE']) && $values['TRANSFERTYPE'] == self::INTRANSIT_STATE){
                if(!$update){
                    $this->_btnAction = 'transferout';
                } else {
                    if($values['TRANSFERSTATE'] == self::DRAFT_STATE){
                        $this->_btnAction = 'transferout';
                    } else if ($values['TRANSFERSTATE'] == self::INTRANSIT_STATE){
                        $this->_btnAction = 'transferin';
                    }
                }
            }
        }
        unset($values['ACTION']);

        return $ok;
    }

    /**
     * API to validate the input.
     *
     * @param array $values
     * @param bool $update
     *
     * @return bool
     */
    protected function validate($values, $update)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $kINVid = Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invprefs);

        if(isset($invprefs['ENABLEINTRANSITTRANSFER']) && $invprefs['ENABLEINTRANSITTRANSFER'] == 'T'){
            if(isset($values['TRANSFERTYPE']) && $values['TRANSFERTYPE'] == self::INTRANSIT_STATE){
                $transferOutLabel = 'Estimated transfer out date filed';
                $transferInLabel  = 'Estimated transfer in date filed';
                if($update){
                    if($values['TRANSFERSTATE'] == self::INTRANSIT_STATE){
                        $transferOutLabel = 'transfer out date';
                    } else if($values['TRANSFERSTATE'] == self::POST_STATE){
                        $transferOutLabel = 'Transfer out date filed';
                        $transferInLabel  = 'Transfer in date filed';
                    }
                }

                if(!empty($values['OUTDATE']) && !empty($values['INDATE'])) {
                    // Validate the data provided for the Transfer out date (OUTDATE)
                    if (!ValidateDate(isl_trim($values['OUTDATE']))) {
                        $gErr->addIAError(
                            'INV-0606', __FILE__ . ':' . __LINE__,
                            'Invalid '.$transferOutLabel.' , please provide valid '.$transferOutLabel.'.',
                            ['TRANSFER_OUT_LABEL'=>$transferOutLabel]
                        );
                        $ok = false;
                    }
                    // Validate the data provided for the Transfer in date (INDATE)
                    if (!ValidateDate(isl_trim($values['INDATE']))) {
                        $gErr->addIAError(
                            'INV-0607', __FILE__ . ':' . __LINE__,
                            'Invalid '.$transferInLabel.' , please provide valid '.$transferInLabel.'.',
                            ['TRANSFER_IN_LABEL'=>$transferInLabel]
                        );
                        $ok = false;
                    }
                    //Compare the OUTDATE & TRANSACTIONDATE, make sure
                    if (DateCompare( $values['TRANSACTIONDATE'], $values['OUTDATE'] ) > 0) {
                        Globals::$g->gErr->addIAError( 'INV-0608', __FILE__ . ':' . __LINE__,
                        'Enter a date in the '.$transferOutLabel.' that is the same as or later than
                        the  value in the Date field for the transaction.',
                        ['TRANSFER_OUT_LABEL'=>$transferOutLabel]);
                        $ok = false;
                    }
                    //Compare the OUTDATE & TRANSACTIONDATE, make sure
                    if (DateCompare( $values['OUTDATE'], $values['INDATE'] ) > 0) {
                        Globals::$g->gErr->addIAError( 'INV-0609', __FILE__ . ':' . __LINE__,
                        'Enter a date in the '.$transferInLabel.' that is the same as or later than the
                        value in the '.$transferOutLabel.'.',
                        ['TRANSFER_IN_LABEL'=>$transferInLabel,'TRANSFER_OUT_LABEL'=>$transferOutLabel]);
                        $ok = false;
                    }
                } else if(empty($values['OUTDATE'])){
                    $gErr->addIAError(
                        'INV-0678', __FILE__ . ':' . __LINE__,
                        'Invalid '.$transferOutLabel.' , please provide valid '.$transferOutLabel.'.',
                        ['TRANSFER_OUT_LABEL'=>$transferOutLabel]
                    );
                    $ok = false;
                } else {
                    $gErr->addIAError(
                        'INV-0679', __FILE__ . ':' . __LINE__,
                        'Invalid '.$transferInLabel.' , please provide valid '.$transferInLabel.'.',
                        ['TRANSFER_IN_LABEL'=>$transferInLabel]
                    );
                    $ok = false;
                }
            }
        } else {
            // Validate Transfer Type, OUTDATE, INDATE only on Add
            if(!$update){
                if(isset($values['TRANSFERTYPE']) && $values['TRANSFERTYPE'] == self::INTRANSIT_STATE){
                    $ok = false;
                } else if (isset($values['OUTDATE']) && $values['OUTDATE'] != ''){
                    $ok = false;
                } else if (isset($values['INDATE']) && $values['INDATE'] != ''){
                    $ok = false;
                }
                if(!$ok){
                    $corr = "To use the TRANSFERTYPE, OUTDATE, or INDATE fields, first enable in-transit
                    warehouse transfer for Inventory Control. Then, try again.";
                    $gErr->addIAError('INV-0610', __FILE__ . ':' . __LINE__,
                        '',
                        [],
                        '',
                        [],
                        $corr,
                        []
                    );
                }
            }
        }

        return $ok;
    }

    /**
     * Validate the transaction action
     *
     * @param array $values
     * @param bool $update
     *
     * @return bool false if error else true
     */
    protected function validateTransactionAction(&$values, $update = false)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $action = $values['ACTION'];
        $transferType= $values['TRANSFERTYPE'];

        // Make sure the action is valid
        $validActionList = $this->getValidActionList($values, $update);
        if ( !in_array($action, $validActionList) ) {
            $ok = false;
            $msg = "";
            $corr = "Enter an ACTION that is valid for '" .$transferType . "' transfers (TRANSFERTYPE='" .$transferType . "'). Then, try again.";
            $gErr->addIAError('INV-0611', __FILE__ . ':' . __LINE__, $msg,
             [],'',[], $corr,['TRANSFER_TYPE'=>$transferType]);
        }
        return $ok;
    }

    /**
     * Get the list of valid action for the transaction
     * @param array $values
     * @param bool $update
     *
     * @return array the list of valid actions for the transaction
     */
    protected function getValidActionList($values, $update)
    {
        $actions = array();
        $kINVid = Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invprefs);
        if(isset($invprefs['ENABLEINTRANSITTRANSFER']) && $invprefs['ENABLEINTRANSITTRANSFER'] == 'T'){
            if(isset($values['TRANSFERTYPE']) && $values['TRANSFERTYPE'] == self::INTRANSIT_STATE){
                if($update){
                    if($values['TRANSFERSTATE']== self::DRAFT_STATE){
                        $actions[] = self::DRAFT_ACTION;
                        $actions[] = self::TRANSFEROUT_ACTION;
                    } else if($values['TRANSFERSTATE']== self::INTRANSIT_STATE){
                        $actions[] = self::TRANSFERIN_ACTION;
                    }
                } else {
                    $actions[] = self::DRAFT_ACTION;
                    $actions[] = self::TRANSFEROUT_ACTION;
                }
            } else {
                if($update){
                    if($values['TRANSFERSTATE']== self::DRAFT_STATE){
                        $actions[] = self::DRAFT_ACTION;
                    }
                    $actions[] = self::POST_ACTION;
                } else {
                    $actions[] = self::DRAFT_ACTION;
                    $actions[] = self::POST_ACTION;
                }
            }
        } else {
            if($update){
                if($values['TRANSFERSTATE']== self::DRAFT_STATE){
                    $actions[] = self::DRAFT_ACTION;
                }
                $actions[] = self::POST_ACTION;
            } else {
                $actions[] = self::DRAFT_ACTION;
                $actions[] = self::POST_ACTION;
            }
        }
        return $actions;
    }

    /**
     * Process the action value
     *
     * @param array  $values
     *
     * @return bool false if error else true
     */
    protected function processAction(&$values)
    {
        $ok = true;
        $action = $values['ACTION'];

        switch($action) {
            case self::DRAFT_ACTION:
                $this->_btnAction = 'draft';
                break;
            case self::TRANSFEROUT_ACTION:
                $this->_btnAction = 'transferout';
                break;
            case self::TRANSFERIN_ACTION:
                $this->_btnAction = 'transferin';
                break;
            default:
                $this->_btnAction = 'post';
        }
        return $ok;
    }

    /**
     * translateValues
     *
     * @param array     &$values    input values
     * @param bool      $update
     *
     * @return bool
     */
    public function translateValues(&$values, $update = false)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $ok = true;
        $ok = $ok && $this->ValidateDocumentNo($values, $update);

        $outTransaction = $values;
        $inTransaction = $values;
        $inTransitTransaction = [];
        $isTransitTransfer = $values['TRANSFERTYPE'] == self::INTRANSIT_STATE;
        if($values['_isdraft'] == true || $this->_btnAction == 'draft') {
            $values['TRANSFERSTATE'] = self::DRAFT_STATE;
        }else if ($isTransitTransfer && $this->_btnAction == 'transferin'){
            $values['TRANSFERSTATE'] = self::POST_STATE;
        }else if ($isTransitTransfer && $values['TRANSFERSTATE'] != self::POST_STATE
                  && ( $values['CREATE_OR_SAVE_ACTION'] == true || $this->_btnAction == 'transferout')){
            $values['TRANSFERSTATE'] = self::INTRANSIT_STATE;
        }else{
            $values['TRANSFERSTATE'] = self::POST_STATE;
        }


        self::setDefaultValues($values, $outTransaction);
        $outTransaction['RECORDNO'] = $values['OUTDOCHDRKEY'];
        if($values['TRANSFERSTATE'] == self::DRAFT_STATE){
            $outTransaction['STATE'] = self::DRAFT_STATE;
            $inTransaction['STATE'] = self::DRAFT_STATE;
            if ($isTransitTransfer ){
                $inTransitTransaction['STATE'] = self::DRAFT_STATE;
            }

        }
        self::setDefaultValues($values, $inTransaction);
        if($isTransitTransfer){
            $inTransitTransaction = array_merge($inTransitTransaction,$values);
            $outTransaction['WHENCREATED'] = $values['OUTDATE'];
            $inTransaction['WHENCREATED'] = (isset($values['INDATE']) && $values['INDATE'] != '')? $values['INDATE'] : $values['OUTDATE'];
            $inTransitTransaction['WHENCREATED'] = $values['OUTDATE'];
            $inTransitTransaction['RECORDNO'] = $values['INTRANSITDOCHDRKEY'];
            $inTransitTransaction['DOCID'] = $values['INTRANSIT_DOCID'];
            if($values['TRANSFERSTATE'] == self::INTRANSIT_STATE) {
                $inTransaction['STATE'] = self::DRAFT_STATE;
            }
        }
        $inTransaction['RECORDNO'] = $values['INDOCHDRKEY'];
        $inTransaction['DOCID'] = $values['IN_DOCID'];

        // Sorting and validating out and in entries
        $entries = array();
        $combinations = array();
        $itemsArr = array();
        $warehouseArr = array();

        if (empty($values['ENTRIES'])) {
            $msg = "No entries were selected";
            $corr = "Select at least one Item ID in the Entries section.";
            $gErr->addIAError('INV-0599', __FILE__ . ':' . __LINE__,
                $msg,
                [],
                '',
                [],
                $corr,
                []
            );
            return false;
        }

        foreach ($values['ENTRIES'] as $entry) {
            $itemMap = $entry['ITEMID'] . '-' . $entry['QUANTITY'] . '-' . $entry['UNIT'];
            $combinations[$itemMap] = 1;
            $entries[$itemMap][$entry['IN_OUT']][] = $entry;
            $itemsArr[] = $entry['ITEMID'];
            $warehouseArr[] = $entry['WAREHOUSEID'];
        }

        $values['ENTRIES'] = array();
        $lineNo = 0;
        foreach ( $combinations as $itemMap => $val) {
            $outCnt = !empty($entries[$itemMap]['O']) ? count($entries[$itemMap]['O']) : 0;
            $inCnt = !empty($entries[$itemMap]['I']) ? count($entries[$itemMap]['I']) : 0;

            if ($outCnt != $inCnt) {
                $gErr->addIAError('INV-0612', __FILE__ . ':' . __LINE__,);
                $ok = false;
                break;
            } else {
                for ($i = 0; $i < $outCnt; $i++) {
                    $entries[$itemMap]['O'][$i]['LINENO'] = ++$lineNo;
                    $entries[$itemMap]['I'][$i]['LINENO'] = $lineNo;

                    $values['ENTRIES'][] = $entries[$itemMap]['O'][$i];
                    $values['ENTRIES'][] = $entries[$itemMap]['I'][$i];
                }
            }
        }

        $itemMgr = $gManagerFactory->getManager('item');
        $itemRawCache = $itemMgr->GetItemsRawCache($itemsArr, true);

        $warehseMgr = $gManagerFactory->getManager('warehouse');
        $warhsRawCache = $warehseMgr->GetWareHouseRawCache($warehouseArr, true);

        $dimensions = IADimensions::getAllDimensionObjectProperties(!util_isPlatformDisabled());
        $outDimensions = array();
        $inDimensions = array();

        foreach ($values['ENTRIES'] as $entry) {
            $entry['WAREHOUSE']['LOCATION_NO'] = $entry['WAREHOUSEID'];
            $entry['LOCATION'] = $entry['LOCATIONID'];
            $entry['DEPARTMENT'] = $entry['DEPARTMENTID'];
            $entry['UIQTY'] = $entry['QUANTITY'];
            /** @noinspection PhpSillyAssignmentInspection */
            $entry['TRX_PRICE'] = $entry['TRX_PRICE'];
            $entry['UIPRICE'] = $entry['TRX_PRICE'];
            unset($entry['RECORDNO']);

            if ($entry['IN_OUT'] == 'O') {
                $ok = $ok && self::validateDimensionValues($entry, $dimensions, $outDimensions, $values);
                $outTransaction['ENTRIES'][] = $entry;
            } else {
                $ok = $ok && self::validateDimensionValues($entry, $dimensions, $inDimensions, $values);
                $inTransaction['ENTRIES'][] = $entry;
            }

            if (empty($itemRawCache[$entry['ITEMID']])
                || !in_array($itemRawCache[$entry['ITEMID']]['ITEMTYPE'], array('I', 'SK'))
                || $itemRawCache[$entry['ITEMID']]['STATUS'] == 'F'
            ) {
                $msg = "Invalid or inactive item '" . $entry['ITEMID'] . "' selected";
                $corr = "Pick a valid active item";
                $gErr->addIAError('INV-0613', __FILE__ . ':' . __LINE__, $msg,
                 ['ENTRY_ITEMID'=>$entry['ITEMID']],'',[], $corr,[]);
                $ok = false;
            }

            if (empty($warhsRawCache[$entry['WAREHOUSEID']])
                || $warhsRawCache[$entry['WAREHOUSEID']]['STATUS'] == 'F')
            {
                $msg = "Invalid or inactive warehouse '" . $entry['WAREHOUSEID'] . "' selected";
                $corr = "Pick a valid active warehouse";
                $gErr->addIAError('INV-0619', __FILE__ . ':' . __LINE__,
                 $msg,['ENTRY_WAREHOUSEID'=>$entry['WAREHOUSEID']],
                 '',[],
                 $corr,[]);
                $ok = false;
            }
        }
        if (IsMultiEntityCompany()) {
            if(empty($outDimensions['LOCATIONID'])){
                $msg = "Required field 'From Location' is missing";
                $gErr->addIAError('INV-0600', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
                $ok = false;
            }
            if(empty($inDimensions['LOCATIONID'])){
                $msg = "Required field 'To Location' is missing";
                $gErr->addIAError('INV-0601', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
                $ok = false;

            }
        }

        $outCur = GetLocationBaseCurrency($outDimensions['LOCATIONID']);
        $inCur = GetLocationBaseCurrency($inDimensions['LOCATIONID']);

        $values['IN_CURRENCY'] = $inCur;
        $values['OUT_CURRENCY'] = $outCur;

        if ((isset($outCur) && isset($inCur)) && $outCur != $inCur) {
            $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
            if (isset($values['EXCH_RATE_TYPE_ID'])) {
                $exchangeType = $values['EXCH_RATE_TYPE_ID'];
            }
            if (!isset($exchangeType) || empty($exchangeType)) {
                $invSubsMgr = $gManagerFactory->getManager('invsetup');
                $values['EXCH_RATE_TYPE_ID'] = $invSubsMgr->getExchangeRateType();
                $exchangeType = $values['EXCH_RATE_TYPE_ID'];
                if ($values['EXCH_RATE_TYPE_ID'] == '') {
                    $exchangeType = 'Intacct Daily Rate';
                }
            }
            if (!isArrayValueProvided($values, 'EXCH_RATE_DATE')) {
                $exchangeDate = $values['TRANSACTIONDATE'];
                $values['EXCH_RATE_DATE'] = $exchangeDate;
            } else {
                $exchangeDate = $values['EXCH_RATE_DATE'];
            }

            $exchTypeID = $exchTypeMgr->GetExchangeRateTypeID($exchangeType);
            if (!isset($exchTypeID)) {
                $errStr = "Exchange Rate Type '" . $exchangeType . "' does not exist.
                You need to specify a valid exchange rate type to use.";
                $errStr .= 'Please select an exchange rate type.';
                $gErr->addIAError(
                    'INV-0620', __FILE__ . ':' . __LINE__,
                    $errStr,
                    ['EXCHANGE_TYPE'=>$exchangeType]
                );
                $ok = false;
            }
            if($ok) {
                $exchangeRate = $this->calculateExchRate($exchTypeID, $outCur, $inCur, $exchangeDate);
            }
            if (!isArrayValueProvided($values, 'EXCHANGE_RATE')) {
                if (!isset($exchangeRate) || $exchangeRate == '') {
                    $gErr->addIAError('INV-0621', __FILE__ . ':' . __LINE__,
                    "No exchange rate found for exchange rate type ". $exchangeType . " on date:" . $exchangeDate,
                    ['EXCHANGE_TYPE'=>$exchangeType,
                    'EXCHANGE_DATE'=>$exchangeDate]);
                    $ok = false;
                }
                /** @noinspection PhpUndefinedVariableInspection */
                $values['EXCHANGE_RATE'] = $exchangeRate;
            } /** @noinspection PhpUndefinedVariableInspection */ elseif ( $exchangeRate != $values['EXCHANGE_RATE']) {
                $exchTypeID = CUSTOM_RATE_ID;
            }
        } else {
            $exchangeRate = 1;
            $exchTypeID = '';
            $values['EXCHANGE_RATE'] = $exchangeRate;
        }
        $values['EXCH_RATE_TYPE_ID'] = $exchTypeID;

        if (IsMultiEntityCompany()) {
            if ($outDimensions['LOCATIONID'] && $inDimensions['LOCATIONID']) {
                $locMgr = $gManagerFactory->getManager('locationentity');
                $map = $locMgr->GetEntityLocationMapbyID();
                if (empty($map[$outDimensions['LOCATIONID']]['ENTITY#'])) {
                    $gErr->addIAError('INV-0622', __FILE__ . ':' . __LINE__, null,
                                      [ 'OUT_DIMENSIONS_LOCATIONID' => $outDimensions['LOCATIONID'] ]);
                    $ok = false;
                }
                if (empty($map[$inDimensions['LOCATIONID']]['ENTITY#'])) {
                    $gErr->addIAError('INV-0623', __FILE__ . ':' . __LINE__, null,
                                      [ 'IN_DIMENSIONS_LOCATIONID' => $inDimensions['LOCATIONID'] ]);
                    $ok = false;
                }
                if ($ok) {

                    if ($map[$outDimensions['LOCATIONID']]['ENTITY#'] != $map[$inDimensions['LOCATIONID']]['ENTITY#']) {

                        $sourceEntity = $map[$outDimensions['LOCATIONID']]['ENTITY#'];
                        $targetEntity = $map[$inDimensions['LOCATIONID']]['ENTITY#'];

                        $outLocDetail = $map[$outDimensions['LOCATIONID']];
                        $inLocDetail = $map[$inDimensions['LOCATIONID']];

                        // If advance IET is enabled get the override account values else get default
                        // Get the source accounts
                        $accounts = InterEntitySetupManager::getSourceNTargetAccounts($sourceEntity, $targetEntity);
                        if ($accounts['SOURCEENTITY']['IEPAYABLEACCTKEY'] == ''
                            || $accounts['SOURCEENTITY']['IERECEIVABLEACCTKEY'] == '') {
                            $outDimLocID = $outDimensions['LOCATIONID'];
                            $inDimLocID = $inDimensions['LOCATIONID'];

                            $errMsg = "Unable to complete transaction";
                            $errDesc = "There is no inter-entity relationship defined between
                                        $outDimLocID and $inDimLocID";
                            $corr = "Please define relationship between $outDimLocID and $inDimLocID from
                            Inter-entity setup and retry";
                            $gErr->addIAError('INV-0624', __FILE__ . ':' . __LINE__, $errMsg,[],
                             $errDesc,
                             ['OUT_DIM_LOC'=>$outDimLocID,'IN_DIM_LOC'=>$inDimLocID],
                             $corr,['OUT_DIM_LOC'=>$outDimLocID,'IN_DIM_LOC'=>$inDimLocID]);
                            $ok = false;

                        } else {
                            $outLocDetail['IERECEIVABLEACCTKEY'] = $accounts['SOURCEENTITY']['IERECEIVABLEACCTKEY'];
                        }

                        $outTransaction['IETDETAIL'] = $outLocDetail;

                        // Get the target accounts
                        if ($accounts['TARGETENTITY']['IEPAYABLEACCTKEY'] == ''
                            || $accounts['TARGETENTITY']['IERECEIVABLEACCTKEY'] == '') {
                            $sourceEntityNo = $outDimensions['LOCATIONID'];
                            $targetEntityNo = $inDimensions['LOCATIONID'];

                            $errMsg = "Unable to complete transaction";
                            $errDesc = "There is no inter-entity relationship defined between $targetEntityNo and
                                $sourceEntityNo";
                            $corr = "Please define relationship between $targetEntityNo and $sourceEntityNo from
                                Inter-entity setup and retry";
                            $gErr->addIAError('INV-0618', __FILE__ . '.' . __LINE__, $errMsg,[],
                            $errDesc,['TARGET_ENTITY_NO'=>$targetEntityNo,'SOURCE_ENTITY_NO'=>$sourceEntityNo], $corr,
                            ['TARGET_ENTITY_NO'=>$targetEntityNo,'SOURCE_ENTITY_NO'=>$sourceEntityNo]);
                            return false;

                        } else {
                            $inLocDetail['IEPAYABLEACCTKEY'] = $accounts['TARGETENTITY']['IEPAYABLEACCTKEY'];
                        }

                        $inTransaction['IETDETAIL'] = $inLocDetail;

                    }

                    $warehouseMgr = $gManagerFactory->getManager('warehouse');

                    $params = array(
                        'selects' => array('LOCATIONID', 'LOC.LOCATIONID'),
                        'filters' => array(
                            array(
                                array(
                                    'LOCATIONID', 'IN',
                                    array($outDimensions['WAREHOUSEID'], $inDimensions['WAREHOUSEID'])
                                )
                            )
                        ),
                    );
                    $warLocations = $warehouseMgr->GetList($params);

                    foreach ($warLocations as $wlocs) {
                        if ($wlocs['LOCATIONID'] == $outDimensions['WAREHOUSEID']) {
                            if (
                                $map[$outDimensions['LOCATIONID']]['ENTITY#']
                                != $map[$wlocs['LOC.LOCATIONID']]['ENTITY#']
                            ) {
                                $msg = "From Warehouse's '" . $wlocs['LOC.LOCATIONID'] . "' should belong " .
                                       "to the same entity as from '" . $outDimensions['LOCATIONID'] . "'";
                                $gErr->addIAError('INV-0617', __FILE__ . ':' . __LINE__, $msg,
                                ['WLOCS_LOC_LOCATIONID'=>$wlocs['LOC.LOCATIONID'],
                                'OUT_DIMENSIONS_LOCATIONID'=>$outDimensions['LOCATIONID']]);
                                $ok = false;
                            }
                        } else {
                            if (
                                $map[$inDimensions['LOCATIONID']]['ENTITY#']
                                != $map[$wlocs['LOC.LOCATIONID']]['ENTITY#']
                            ) {
                                $msg = "To Warehouse's '" . $wlocs['LOC.LOCATIONID'] . "' should belong " .
                                       "to the same entity as to '" . $inDimensions['LOCATIONID'] . "'";
                                $gErr->addIAError('INV-0616', __FILE__ . ':' . __LINE__, $msg,
                                ['WLOCS_LOC_LOCATIONID'=>$wlocs['LOC.LOCATIONID'],
                                'IN_DIMENSIONS_LOCATIONID'=>$inDimensions['LOCATIONID']]);
                                $ok = false;
                            }
                        }
                    }
                }
            }
        }

        $values['TRANSFEROUT'] = $outTransaction;
        if($isTransitTransfer){
            $inTransitTransaction['ENTRIES'] = $inTransaction['ENTRIES'];
            $values['INTRANSIT'] = $inTransitTransaction;
        }
        $values['TRANSFERIN'] = $inTransaction;


        return $ok;
    }

    /**
     * @param int $exchratetypeId
     * @param string $fromcurrency
     * @param string $tocurrency
     * @param string $exchratedate
     *
     * @return string|false|null
     */
    private function calculateExchRate($exchratetypeId, $fromcurrency, $tocurrency, $exchratedate)
    {
        $exchRateMgr = Globals::$g->gManagerFactory->getManager('exchangerate');
        // This is called in regularAdd/set which is always English hence no need to translate it
        // Get the exhange rate
        $rate = $exchRateMgr->GetTrxExchangeRateByTypeID($exchratetypeId, $fromcurrency, $tocurrency, $exchratedate);
        return $rate;
    }

    /**
     * @param array $entry
     * @param array $dimensions
     * @param array $dimensionValues
     * @param array $values
     *
     * @return bool
     */
    private static function validateDimensionValues(&$entry, $dimensions, &$dimensionValues, &$values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        foreach ($dimensions as $dim) {
            if ($dim['path'] == 'ITEMID') {
                continue;
            }

            if (!isset($dimensionValues[$dim['path']]) || !isset($entry[$dim['path']])) {
                $dimensionValues[$dim['path']] = '';
                if ($entry[$dim['path']]) {
                    $dimensionValues[$dim['path']] = $entry[$dim['path']];
                }

                if ($entry['IN_OUT'] == 'O') {
                    $ok = $ok && self::mergeCustomDimensions($entry, $dim, 'OUT_', $dimensionValues, $values);
                } else {
                    $ok = $ok && self::mergeCustomDimensions($entry, $dim, 'IN_', $dimensionValues, $values);
                }
            } else {
                if ($dimensionValues[$dim['path']] != $entry[$dim['path']]) {

                    $msg = $dim['fullname'] . " '" . $entry[$dim['path']] . "' " .
                           "is different than '" . $dimensionValues[$dim['path']] . "'";
                    $corr = "Dimension values should be same for all lines of transfer documents.";
                    $gErr->addIAError(
                        'INV-0615', __FILE__ . ':' . __LINE__,
                        $msg, ['DIM_FULLNAME' => $dim['fullname'], 'ENTRY_DIM_PATH' => $entry[$dim['path']], 'DIMENSION_VALUES_DIM_PATH' => $dimensionValues[$dim['path']]],
                        '', [],
                        $corr, []
                    );
                    $ok = false;
                    break;
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     * @param array $transaction
     */
    private static function setDefaultValues(&$values, &$transaction)
    {
        $resetVars = array(
            'RECORDNO',
            'ENTRIES',
            'DOCNO',
            'WHENCREATED',
            'WHENMODIFIED',
            'CREATEDBY',
            'MODIFIEDBY'
        );

        foreach ($resetVars as $var) {
            unset($transaction[$var]);
        }

        $transaction['WHENCREATED'] = $values['TRANSACTIONDATE'];
    }
    /**
     * Get
     *
     * @param string        &$id    name
     * @param string[]|null $fields
     *
     * @return array
     */
    public function Get($id, $fields = null)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $obj = parent::get($id);

        if (!empty($obj)) {
            //Maintains the original entries from DB incase we don't need to recreate the transfer-out doc and need the data
            //to recreate the cost layers used by the transfer-out doc.
            if ($fields['DB_ENTRIES']) {
                $obj['DB_ENTRIES'] = $obj['ENTRIES'];
            }

            // FIFO layers are expanded in the DB. Need to group and show as how it was entered
            $groupedEntries = array();
            foreach ($obj['ENTRIES'] as $entry) {
                if (empty($groupedEntries[$entry['LINENO']][$entry['IN_OUT']])) {
                    $groupedEntries[$entry['LINENO']][$entry['IN_OUT']] = $entry;
                } else {
                    $itemPrecision = $itemCache[$entry['ITEMID']]['PRECISION'] ?? ItemManager::BASEUNITPRECISION;
                    $groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['QUANTITY'] =
                        ibcadd($groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['QUANTITY'], $entry['QUANTITY'], $itemPrecision);
                    $groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['TRX_VALUE'] =
                        ibcadd($groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['TRX_VALUE'], $entry['TRX_VALUE']);
                    $groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['VALUE'] =
                        ibcadd($groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['VALUE'], $entry['VALUE']);

                    $groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['TRX_PRICE'] = '';
                    $groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['PRICE'] = '';
                }

                //Maintain the docentrykey so we can get the tracking entries of it
                $groupedEntries[$entry['LINENO']][$entry['IN_OUT']]['TRACKINGENTRIESDOCENTRYKEY'][] = $entry['DOCENTRYKEY'];
            }

            $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
            $obj['EXCH_RATE_TYPE_ID'] = $exchTypeMgr->GetExchangeRateTypeName($obj['EXCH_RATE_TYPE_ID']);
            if (!isset($obj['EXCH_RATE_TYPE_KEY'])) {
                $obj['EXCH_RATE_TYPE_KEY']=$exchTypeMgr->GetExchangeRateTypeID($obj['EXCH_RATE_TYPE_ID']);
            }

            $docEntryTrackMgr = $gManagerFactory->getManager('documententrytrackdetail');

            //For each grouped (transfer IN & OUT) entries, we need to get the tracking entries in expanded lifo/fifo form
            $advancedBins = BinManager::areAdvanedBinsOn();
            $obj['ENTRIES'] = array();
            foreach ($groupedEntries as &$groupedPaired1) {
                foreach ( $groupedPaired1 as &$groupedEntry1) {

                    //The parent::get way above will have the TRACKINGENTRIESDOCENTRYKEY not sorted. We need to sort back to the order it was written out to disk
                    usort($groupedEntry1['TRACKINGENTRIESDOCENTRYKEY'], function($a,$b) {
                        if ($a < $b) { return -1; }
                        if ($a > $b) { return +1; }
                        return 0;
                    });

                    foreach ($groupedEntry1['TRACKINGENTRIESDOCENTRYKEY'] as $trackEntryDocEntryKey) {
                        $trackEntries = $docEntryTrackMgr->getByParent($trackEntryDocEntryKey);
                        if ( ! empty($trackEntries) ) {
                            foreach ( $trackEntries as &$tEntry ) {
                                if ( $advancedBins ) {
                                    unset($tEntry['AISLEID']);
                                    unset($tEntry['AISLEKEY']);
                                    unset($tEntry['ROWID']);
                                    unset($tEntry['ROWKEY']);
                                }
                                $groupedEntry1['TRACKINGENTRIES'][] = $tEntry;
                            }
                        }
                    }
                    unset($groupedEntry1['TRACKINGENTRIESDOCENTRYKEY']);
                }
            }

            //We now need to combine the tracking entries (in expanded form in loop above) into common tracking lines
            //base on the transfer OUT tracking criteria (serialno, binid, lotno, expiration) of each line.
            foreach ($groupedEntries as &$groupedPaired2) {
                $cachedOutTrackingEntries = [];
                $cachedInTrackingEntries = [];
                foreach ($groupedPaired2['O']['TRACKINGENTRIES'] as $index => $trackingEntry) {
                    $key = ($trackingEntry['SERIALNO'] ?? '')
                         . ($trackingEntry['BINID'] ?? '')
                         . ($trackingEntry['LOTNO'] ?? '')
                         . ($trackingEntry['EXPIRATION'] ?? '');
                    if (($key == '') || ($key == '0')) {
                        continue; //No tracking, go to next
                    }
                    if (!isset($cachedOutTrackingEntries[$key])) {
                        $cachedOutTrackingEntries[$key] = $trackingEntry;
                        $cachedInTrackingEntries[$key] = $groupedPaired2['I']['TRACKINGENTRIES'][$index];
                    } else {
                        $cachedOutTrackingEntries[$key]['QUANTITY'] += $trackingEntry['QUANTITY'];
                        $cachedInTrackingEntries[$key]['QUANTITY'] += $groupedPaired2['I']['TRACKINGENTRIES'][$index]['QUANTITY'];
                    }
                }
                $groupedPaired2['O']['TRACKINGENTRIES'] = [];
                foreach ($cachedOutTrackingEntries as $cachedOutTrackingEntry) {
                    $cachedOutTrackingEntry['TRACK_QUANTITY'] = $cachedOutTrackingEntry['QUANTITY'];
                    $groupedPaired2['O']['TRACKINGENTRIES'][] = $cachedOutTrackingEntry;
                }
                $groupedPaired2['I']['TRACKINGENTRIES'] = [];
                foreach ($cachedInTrackingEntries as $cachedInTrackingEntry) {
                    $cachedInTrackingEntry['TRACK_QUANTITY'] = $cachedInTrackingEntry['QUANTITY'];
                    $groupedPaired2['I']['TRACKINGENTRIES'][] = $cachedInTrackingEntry;
                }
            }

            //Finally, we copy the grouped entries back to the obj to return
            foreach ($groupedEntries as $groupedPaired3) {
                foreach ( $groupedPaired3 as $groupedEntry3) {
                    $obj['ENTRIES'][] = $groupedEntry3;
                }
            }

            //Populate history
            $this->GetDocHistory($obj);
        }
        return $obj;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    function GetDocHistory(&$obj)
    {
        global $gManagerFactory;
        $docHistMgr =    $gManagerFactory->getManager('dochistory');
        $obj['HISTORY'] = $docHistMgr->GetHistoryList($obj['OUTDOCHDRKEY']);
        return true;
    }
    /**
     * @param array $values
     *
     * @return array
     */
    function API_UnformatObject($values)
    {
        //$itemsAliases = $this->API_GetSetting('ITEMS_ALIAS');
        $itemAlias = $this->API_GetSetting('ITEM_ALIAS');
        $itemAlias = strtolower($itemAlias[0]);

        foreach ($values as &$value) {
            if (is_array($value['ENTRIES'][$itemAlias][0])) {
                foreach ($value['ENTRIES'][$itemAlias] as &$docentry) {
                    if (isset($docentry['TRACKINGENTRIES']) && is_array($docentry['TRACKINGENTRIES'])) {
                        $trackEntries = $docentry['TRACKINGENTRIES'];
                        unset($docentry['TRACKINGENTRIES']);
                        $docentry['TRACKINGENTRIES']['TRACKINGENTRY'] = $trackEntries;
                    }
                }
            }
        }

        $values = parent::API_UnformatObject($values);
        return $values;
    }

    /**
     * Delete
     *
     * @param int $recNo record no.
     *
     * @return bool
     */
    public function Delete($recNo)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $source = "ICTransferManager::Delete";

        $ok = $this->_QM->beginTrx($source);

        $params = array(
            'selects' => array('IN_DOCID', 'OUT_DOCID', 'INTRANSIT_DOCID'),
            'filters' => array(array(array('RECORDNO', '=', $recNo))),
        );

        $values = $this->GetList($params);

        $ok = $ok && parent::Delete($recNo);

        self::getTransferDocTypes($outDocType, $inDocType,$inTransitDocType);

        $inMgr = $gManagerFactory->getManager('invdocument', true, array( 'DOCTYPE' => $inDocType));

        $ok = $ok && $inMgr->deleteWithOverride($values[0]['IN_DOCID'], true, true);

        if(!empty($values[0]['INTRANSIT_DOCID'])){
            $inTransitMgr = $gManagerFactory->getManager('invdocument', true, array( 'DOCTYPE' => $inTransitDocType));

            $ok = $ok && $inTransitMgr->deleteWithOverride($values[0]['INTRANSIT_DOCID'], true, true);
        }


        $outMgr = $gManagerFactory->getManager('invdocument', true, array( 'DOCTYPE' => $outDocType));

        $ok = $ok && $outMgr->deleteWithOverride($values[0]['OUT_DOCID'], true, true);

        $ok = $ok && $this->_QM->commitTrx($source);

        if (!$ok) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not delete warehouse transfer record!";
                $gErr->addIAError('INV-0614', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     *  API_Validate
     *  This function performs a validation of the intended API operation.  If the operation
     *  cannot be performed, this function return false, with an appropriate error added to the
     *  global error stack.
     *
     * @param string $operation operation
     * @param array  &$values   input values
     *
     * @return bool
     */
    function API_Validate($operation, &$values = null)
    {
        $ok = parent::API_Validate($operation, $values);

        if (!$ok) {
            return false;
        }

        if ( $operation == API_READ || $operation == API_READ_API ||
             $operation == API_READ_BY_QUERY || $operation == API_READ_BY_NAME ||
             $operation == API_QUERY ) {
            return true;
        }

        $gErr = Globals::$g->gErr;
        $entries = ($values['ICTRANSFERITEMS']['ICTRANSFERITEM']) ?? [];

        foreach ($entries as $entry) {
            if (!empty($entry['TRX_PRICE']) || !empty($entry['PRICE'])) {
                $msg = "Cost should not be overridden.";
                $gErr->addIAError('INV-0602', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
                return false;
            }
        }

        return true;
    }

    /**
     * @param array $values
     *
     * @return array
     */
    public function API_FormatObject($values)
    {
        $values = parent::API_FormatObject($values);

        // prepare the tracking info if it has any
        foreach ($values['ENTRIES'] as $lineKey => $lineItem) {
            if (isset($lineItem['TRACKINGENTRIES']['TRACKINGENTRY'])) {
                if (is_array($lineItem['TRACKINGENTRIES']['TRACKINGENTRY'][0])) {
                    $trackEntries = $lineItem['TRACKINGENTRIES']['TRACKINGENTRY'];
                } else {
                    $trackEntries = array($lineItem['TRACKINGENTRIES']['TRACKINGENTRY']);
                }
                unset($values['ENTRIES'][$lineKey]['TRACKINGENTRIES']);
                $values['ENTRIES'][$lineKey]['TRACKINGENTRIES'] = $trackEntries;
            }
        }

        return $values;
    }

    /**
     * @param array $values
     * @param bool  $update
     *
     * @return bool
     */
    function ValidateDocumentNo(&$values,$update)
    {

        $gErr = Globals::$g->gErr;
        $ok = true;
        if ($update) {
            $params = array(
                'selects' => array('RECORDNO', 'DOCNO'),
                'filters' => array(array(array('RECORDNO', '=', $values['RECORDNO']))),
            );
            $res = $this->GetList($params);
            $res = $res[0];

            if ($values['DOCNO'] !== $res['DOCNO']) {
                //Does not allow to update docno for WT'S.
                $msg = "Document number can not be changed from " . $res['DOCNO'] . " to " . $values['DOCNO'] . " for Existing Document";
                $gErr->addIAError(
                    'INV-0625', __FILE__ . ":" . __LINE__,
                    "Invalid User Action", [],
                    $msg, ['RES_DOCNO' => $res['DOCNO'], 'VALUES_DOCNO' => $values['DOCNO']]
                );
                $ok = false;
            }
        }
        return $ok;
    }

    /**
     * @param array $entry
     * @param array $dim
     * @param string $prefix
     * @param array $dimensionValues
     * @param array $values
     *
     * @return bool
     */
    private static function mergeCustomDimensions(&$entry, $dim, $prefix, &$dimensionValues, &$values)
    {
        if (!empty($dim['standard']) && !isset($dim['dimensionid'])) {
            return true;
        }

        $custDimFieldsMap = [];
        if (!util_isPlatformDisabled()) {
            $custDimFieldsMap = GLEntryManager::getPTFieldsMap();
        }

        if (!empty($values) && empty($dim['standard']) && isset($dim['dimensionid']) && !empty($dim['dimensionid'])) {
            // From UI - custom dimensions value passing through header level
            $dimensionLineEntryValue = $values[$prefix . $custDimFieldsMap[$dim['dimensionid']]] ?? '';

            $dimensionValues[$dim['path']] = $dimensionLineEntryValue;
            $entry[$custDimFieldsMap[$dim['dimensionid']]] = $dimensionLineEntryValue;
        }

        return true;
    }

    /**
     * @param string[]|string[][]|string[][][]  $values
     *
     * @return bool
     */
    public function API_Add(&$values)
    {
        $this->_fromAPI = true;
        return parent::API_Add( $values );
    }

    /**
     * @param string[]|string[][]|string[][][]  $values
     *
     * @return bool
     */
    public function API_Set(&$values)
    {
        $this->_fromAPI = true;
        return parent::API_Set($values);
    }

    /**
     * @param array  $objRec
     * @param bool   $validateReadOnly
     *
     * @return bool
     */
    protected function useOwnedObject( $objRec,  $validateReadOnly)
    {
        //skip creating DOCHISTORY for ictransfers. The 3 generated documents will have them.
        if ($objRec['path'] == 'HISTORY') {
            return false;
        }
        return parent::useOwnedObject($objRec, $validateReadOnly);
    }

    /**
     * @return array
     */
    public function getDBTranslatedFieldsForEditor(): array
    {
        // Translate EXCH_RATE_TYPE_ID field explicitely in formeditor
        return ['EXCH_RATE_TYPE_ID'];
    }
}
