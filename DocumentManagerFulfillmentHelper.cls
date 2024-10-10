<?php

/**
 *    FILE: DocumentManagerFulfillmentHelper.cls
 *
 *    (C) 2021, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 *    Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */

/**
 * Liaison between DocumentManager and Fulfillment
 *
 * Utility methods to handle Fulfillment-enabled transactions during actions taken outside
 * fulfillment workflows (e.g., editing, deleting, or otherwise rearranging the order of entries).
 *
 * @package    source
 * @subpackage inventory
 */
class DocumentManagerFulfillmentHelper
{

    /**
     * @var array $fieldsToCollate Specifics about the $values fields to collate and their respective mappings.
     */
    private static $fieldsToCollate = [
        'FULFILLMENTDETAILS' => [ 'LINENO' => 'FFLINENO',
                                  'ITEMID' => 'FFITEMID' ],
        'ENTRIES'            => [ 'LINE_NO'          => 'NEW_LINE_NO', 'QUANTITY' => 'NEW_QUANTITY',
                                  'RELATEDDOCLINENO' => 'LINE_NO',
                                  'ITEMID'           => 'NEW_ITEMID', 'UNIT' => 'NEW_UNIT',
                                  'WAREHOUSE'        => 'NEW_WAREHOUSE',
                                  'ITEMUOM'          => 'NEW_ITEMUOM' ],
        'EXISTING_ENTRIES'   => [ 'LINE_NO' => 'OLD_LINE_NO', 'QUANTITY' => 'OLD_QUANTITY',
                                  'ITEMID'  => 'OLD_ITEMID',
                                  'UNIT'    => 'OLD_UNIT', 'WAREHOUSE' => 'OLD_WAREHOUSE',
                                  'ITEMUOM' => 'OLD_ITEMUOM', 'QTY_CONVERTED' => 'QTY_CONVERTED' ],
    ];

    /**
     * @var string[] $errorLabels Mapping from constrained mutable attribute keys to display labels
     */
    private static $errorLabels = [];

    /**
     * @var InventoryWorkQueueManager $inventoryWorkQueueManager The work queue manager instance
     */
    private static $inventoryWorkQueueManager;

    /**
     * @var array $collatedEntries Intersection of per-entry details from fulfillment, existing entry, and newly edited
     *      entry
     */
    private $collatedEntries = [];

    /**
     * Gather all the pertinent attributes which are needed to decide what is or is not allowed,
     * and if fulfillment work queue records require updating (or "deleting").
     *
     * @param array $values
     */
    private function collateUpdates($values)
    {
        if ( ! self::isFulfillmentEnabledTransaction($values) ) {
            // Nothing to do; this TD isn't eligible for fulfillment
            return;
        }
        foreach ( self::$fieldsToCollate as $fkey => $fields ) {
            foreach ( $values[$fkey] as $value ) {
                $collatedEntry = [];
                foreach ( $fields as $inField => $outField ) {
                    $collatedEntry[$outField] = $value[$inField] ?? '';
                }
                // Need to fix up a few things.
                if ( $fkey == 'FULFILLMENTDETAILS' ) {
                    // Line number prior to any change (such as from line rearrangement or addition/deletion)
                    $lineno = $collatedEntry['FFLINENO'];
                    $collatedEntry['LINENO'] = $lineno;
                    if ( $value['COMPLETED'] === 'false' ) {
                        if ( $value['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN ) {
                            $this->collatedEntries["$lineno"]['OPEN_QUANTITY'] =
                                ( $this->collatedEntries["$lineno"]['OPEN_QUANTITY'] ?? 0 + $value['QUANTITY'] );
                        } else {
                            $this->collatedEntries["$lineno"]['COMMITTED_QUANTITY'] =
                                ( $this->collatedEntries["$lineno"]['COMMITTED_QUANTITY'] ?? 0 + $value['QUANTITY'] );
                        }
                        $this->collatedEntries["$lineno"]['RESERVED_QUANTITY'] =
                            ( $this->collatedEntries["$lineno"]['RESERVED_QUANTITY'] ??
                              0 + $value['QUANTITYINRESERVE'] );
                        $this->collatedEntries["$lineno"]['ALLOCATED_QUANTITY'] =
                            ( $this->collatedEntries["$lineno"]['ALLOCATED_QUANTITY'] ??
                              0 + $value['QUANTITYINALLOCATION'] );
                    }
                } else if ( $fkey == 'EXISTING_ENTRIES' ) {
                    // EXISTING_ENTRIES: Line number offset by -1 (0-based)
                    $oldLine = empty($collatedEntry['OLD_LINE_NO']) ? 0 : $collatedEntry['OLD_LINE_NO'];
                    $collatedEntry['OLD_LINE_NO'] = $oldLine + 1;
                    $lineno = $collatedEntry['OLD_LINE_NO'];
                } else {
                    // ENTRIES: Line number offset by -1 (0-based)
                    $newLine = empty($collatedEntry['OLD_LINE_NO']) ? 0 : $collatedEntry['OLD_LINE_NO'];
                    $collatedEntry['NEW_LINE_NO'] = $newLine + 1;
                    // Here the RELATEDDOCLINENO (which is 1-based, i.e., *not* offset) is the preexisting line
                    $lineno = $collatedEntry['LINE_NO'];
                }
                // WORKKEY: May be only in a new entry, may be only in a deleted entry; just pick any if found
                if ( isset($value['WORKKEY']) ) {
                    $collatedEntry['WORKKEY'] = $value['WORKKEY'];
                }
                $collatedEntry['LINENO'] = $lineno;
                $this->collatedEntries[$lineno] =
                    array_merge((array) $this->collatedEntries[$lineno], (array) $collatedEntry);
            }
        }
    }

    /**
     * Check if specified transaction definition is enabled for fulfillment.
     *
     * @param array $documentTree The document in question
     *
     * @return bool True if enabled, false otherwise
     */
    private static function isFulfillmentEnabledTransaction($documentTree)
    {
        $documentType = InvBizLogicForWD::documentTypeFromDocTree($documentTree);
        return (($documentType !== InvBizLogicForWD::TD_TYPE_HIDDEN_SALESORDER) &&
                ($documentType !== InvBizLogicForWD::TD_TYPE_OTHER));
    }

    /**
     * @return InventoryWorkQueueManager
     */
    private static function getIwqManager()
    {
        if ( self::$inventoryWorkQueueManager == null ) {
            self::$inventoryWorkQueueManager = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");
        }

        return self::$inventoryWorkQueueManager;
    }

    /**
     * Populate required display labels with internationalizable strings.
     */
    private static function initErrorLabels()
    {
        if ( empty(self::$errorLabels) ) {
            self::$errorLabels['ITEMID'] = _('item ID');
            self::$errorLabels['UOM'] = _('unit');
            self::$errorLabels['UOMFACTOR'] = _('unit'); // Only changed implicitly when UOM changes, hence display label overlap
            self::$errorLabels['WAREHOUSEID'] = _('warehouse');
            self::$errorLabels['LINENO'] = _('line number');
        }
    }

    /**
     * Take advantage of the InvBizLogicForWD to correctly calculate any changes to allocations
     * and/or reservations in case of quantity decreases. We can short circuit this when the bundle
     * is OPEN since we know its allocation and reservation must remain zero, and no change in quantity
     * will result in allocation or reservation deltas.
     *
     * We're fetching the detail records one at a time--it's possible or likely if there are many
     * quantity changes in an update (for multiple bundles and/or entries) we could optimize it
     * by fetching multiple detail records up front. But, it's not clear if that's a common use
     * case or if it would just be unnecessarily wasteful if the opposite case is more common--i.e., if
     * most quantity changes apply to a single bundle while other entries and bundles remain unaffected.
     *
     * @param [] $iwqRec The updated work queue record
     *
     * @return bool True if things went smoothly, false otherwise
     */
    private static function recalculateAllocationAndReserve(&$iwqRec)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        if ( $iwqRec['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN ) {
            return $ok;
        }
        $iwqDetailManager = Globals::$g->gManagerFactory->getManager("inventorywqdetail");
        $iwDetailBizLog   = Globals::$g->gManagerFactory->_getObjectInstance("InvBizLogicForWD");
        $oldDetail = $iwqDetailManager->get($iwqRec['RECORD#']);
        if ( ! $oldDetail ) {
            $ok = false;
            $gErr->addIAError('INV-0028', __FILE__ . ':' . __LINE__, 'Unable to reduce quantity', [],
                            'Unable to fetch work queue detail record in fulfillment', []);

            return $ok;
        }
        $newDetail = $oldDetail;
        $newDetail['QUANTITY'] = $iwqRec['QUANTITY'];
        $ok = $ok && $iwDetailBizLog->maybeAllocate($oldDetail, $newDetail);
        if ( ! $ok ) {
            $ok = false;
            $gErr->addIAError('INV-0029', __FILE__ . ':' . __LINE__, 'Unable to reduce quantity', [],
                            'Unable to determine change in allocation in fulfillment', []);
        }
        $ok = $ok && $iwDetailBizLog->maybeReserve($oldDetail, $newDetail);
        if ( ! $ok ) {
            $ok = false;
            $gErr->addIAError('INV-0030', __FILE__ . ':' . __LINE__, 'Unable to reduce quantity', [],
                            'Unable to determine change in reservation in fulfillment', []);
        }
        $iwqRec['QUANTITYINRESERVE']    = $newDetail['QUANTITYINRESERVE'] ?? 0;
        $iwqRec['QUANTITYINALLOCATION'] = $newDetail['QUANTITYINALLOCATION'] ?? 0;

        $tracking           = InvBizLogicForWD::getTrackedStatusOfItems( [ $iwqRec['ITEMID'] ] );             // likely already IN the cache
        $canRunOut          = ($tracking[ $iwqRec['ITEMID'] ]['CANRUNOUT'] ?? true);                          // do we NEED to track stuff?

        if ($canRunOut) {
            $iwqRec['DELTARESERVE']    = $newDetail['DELTARESERVE'] ?? 0;
            $iwqRec['DELTAALLOCATION'] = $newDetail['DELTAALLOCATION'] ?? 0;
        }
        return $ok;
    }

    /**
     * @param string[] $collatedEntry
     *
     * @return bool
     */
    private function hasFulfillmentRecords($collatedEntry)
    {
        // This should be set if there were fulfillment records included
        return isset($collatedEntry['FFLINENO']);
    }

    /**
     * @param string[] $collatedEntry
     *
     * @return bool
     */
    private function isDeleted($collatedEntry)
    {
        return isset($collatedEntry['OLD_LINE_NO']) && ! isset($collatedEntry['NEW_LINE_NO']);
    }

    /**
     * DocumentManagerFulfillmentHelper constructor.
     *
     * Collate important attributes of old and new docentries, along with fulfillment attributes; used later to
     * decide whether anything in fulfillment needs to be updated based on changes.
     *
     * @param array $values
     */
    public function __construct($values)
    {
        self::initErrorLabels();
        $this->collateUpdates($values);
    }

    /**
     * If this is a copy of a fulfillment-enabled TD, sanitize any old WORKKEYs in the entries.
     *
     * @param array $values
     */
    public static function sanitizeCopy(&$values)
    {
        if ( ! self::isFulfillmentEnabledTransaction($values) ) {
            // Not concerned with these
            return;
        }
        $copyMode = Request::$r->_copymode;
        if ( ( $copyMode ?? '' ) == 'Copy' ) {
            // Yep, this is a copy; clear the WORKKEYs to avoid spurious relationships with fulfillment records
            self::sanitizeWorkKeys($values);
        }
    }

    /**
     * @param array $values Values from which to strip offending WORKKEYs
     */
    private static function sanitizeWorkKeys(&$values) {
        foreach ( $values['ENTRIES'] ?? [] as $key => $value ) {
            unset($values['ENTRIES'][$key]['WORKKEY']);
        }
    }

    /**
     * Consolidate source document(s) and associated work queue records.
     *
     * @param array $entries    Entries in current document
     * @param array $sourceDocs Source document(s) referenced by entries
     *
     * @return bool True if successful, false otherwise
     */
    private static function getSourceDocWithWorkQueueRecords($entries, &$sourceDocs)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $iwqManager = self::getIwqManager();
        $documentManager = Globals::$g->gManagerFactory->getManager("document");
        foreach ( $entries as $entry ) {
            $sourceDocId = $entry['SOURCE_DOCID'];
            if ( isset($sourceDocId) ) {
                if ( ! array_key_exists($sourceDocId, $sourceDocs) ) {
                    $sourceDoc = $documentManager->get($sourceDocId);
                    if ( $sourceDoc == false ) {
                        $ok = false;
                        $gErr->addIAError('INV-0031', __FILE__ . ':' . __LINE__, 'Unable to convert document', [],
                                        'Unable to fetch source document', []);
                        break;
                    }
                    $sourceDocs[$sourceDocId] = $sourceDoc;
                }
                $workkey = $entry['WORKKEY'];
                if ( isset($workkey) ) {
                    $iwqRecs = [];
                    $ok = $iwqManager->getByWorkKey([ $workkey ], $iwqRecs);
                    if ( ! $ok ) {
                        $gErr->addIAError('INV-0032', __FILE__ . ':' . __LINE__, 'Unable to convert document', [],
                                        'Unable to fetch work queue records', []);
                        break;
                    }
                    $sourceDocs[$sourceDocId]['WORKKEYRECS'][$workkey] = $iwqRecs;
                }
            }
        }

        return $ok;
    }

    /**
     * Validate whether or not there are multiple bundles in fulfillment for each entry.
     *
     * @param array $entries Entries in current document
     * @param array $sourceDocs Source document(s) referenced by entries
     *
     * @return bool
     */
    private static function areAllSingleGroupsPerEntry($entries, $sourceDocs) {
        $ok = true;
        $gErr = Globals::$g->gErr;
        if ( ! empty($sourceDocs) ) {
            foreach ( $entries as $entry ) {
                $wqBundlesExist = isset($sourceDocs[$entry['SOURCE_DOCID']]['WORKKEYRECS'][$entry['WORKKEY']][0]);
                $wqQty = $sourceDocs[$entry['SOURCE_DOCID']]['WORKKEYRECS'][$entry['WORKKEY']][0]['QUANTITY'] ?? 0;
                $bundleCount = count($sourceDocs[$entry['SOURCE_DOCID']]['WORKKEYRECS'][$entry['WORKKEY']]);
                if ( $entry['QTY_CONVERTED'] > 0 ) {
                    $ok = false;
                    $gErr->addIAError('INV-0033', __FILE__ . ':' . __LINE__, 'Unable to convert document', [],
                                    'Transaction has already been partially converted in fulfillment', []);
                    break;
                }
                if ( isset($entry['SOURCE_DOCID']) && isset($entry['WORKKEY'])
                     && ( $bundleCount > 1
                          || ( $wqBundlesExist && $wqQty != $entry['UIQTY'] ) ) ) {
                    $ok = false;
                    $gErr->addIAError('INV-0034', __FILE__ . ':' . __LINE__, 'Unable to convert document', [],
                                    'Transaction has multiple groups in fulfillment', []);
                    break;
                }
            }
        }
        return $ok;
    }

    /**
     * If this is a conversion of a fulfillment-enabled TD, fail if there are any work queue records in any PLACE
     * other than OPEN. Otherwise proceed, but first complete any OPEN work queue records.
     *
     * @param array $values
     *
     * @return bool True if able to convert, false otherwise
     */
    public static function isConversionAllowedByFulfillment($values)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        if ( ! isset($values['CREATEDFROM']) && $values['CREATEDFROM'] == '' ) {
            // Cannot be a conversion
            return $ok;
        }
        // Infer source type based on CREATEDFROM
        $oldDocparKey = '';
        $ok = $ok && self::getDocumentTypeKey($values['CREATEDFROM'], $oldDocparKey);
        if ( ! $ok ) {
            $gErr->addIAError('INV-0035', __FILE__ . ':' . __LINE__, 'Unable to convert document', [],
                            'Unable to determine source document type', []);
        }
        // And check if source type is fulfillment-enabled
        if ( $ok && self::isFulfillmentEnabledTransaction($values) ) {
            /*
             * Conditions under which conversion is allowed to proceed (applies to each entry):
             * 1. There is at most a single bundle in fulfillment
             * 2. If there is 1 bundle, it must comprise the entire quantity of the entry
             * (This also means QTY_CONVERTED must be zero; i.e., it must not yet have participated in any
             * conversion in fulfillment.)
             * Since it's all-or-nothing, it's ok to continue as usual and close the document after.
             */
            $sourceDocs = [];
            $ok = $ok && self::getSourceDocWithWorkQueueRecords($values['ENTRIES'], $sourceDocs);
            $ok = $ok && self::areAllSingleGroupsPerEntry($values['ENTRIES'], $sourceDocs);
            self::sanitizeWorkKeys($values);
        }

        return $ok;
    }

    /**
     * Get the TD RECORD# based on its DOCID.
     *
     * @param string  $docid     Docid to look up
     * @param string &$docparkey Key (record#) corresponding to given docid
     *
     * @return bool True if successful, false otherwise
     */
    private static function getDocumentTypeKey($docid, &$docparkey)
    {
        $ok = true;
        $qry = "select d.docparkey as docparkey from dochdr d where d.cny#=:1 and d.docid=:2";
        $result = QueryResult(array( $qry, GetMyCompany(), $docid ));

        if ( $result == false ) {
            $gErr = Globals::$g->gErr;
            $gErr->addIAError('INV-0036', __FILE__ . ':' . __LINE__, 'Unable to find parent transaction definition', [],
                            'Database error', []);

            return false;
        }

        $docparkey = $result[0]['DOCPARKEY'];

        return $ok;
    }

    /**
     * Delete the work queue records associated with the given workkeys.
     *
     * @param array          $workKeysToDelete WORKKEYs to be deleted
     * @param IAIssueHandler $gErr             Just in case
     * @param bool           $ignoreHold       Pay no attention to HOLD if true, otherwise treat as not OPEN (i.e., disallow)
     *
     * @return bool True if successful, false otherwise
     */
    private static function deleteByWorkkeys($workKeysToDelete, IAIssueHandler $gErr, bool $ignoreHold = true)
    {
        $ok = true;
        $iwqManager = self::getIwqManager();
        $iwqRecs = [];
        $placeholderTxt = '';
        if ( ! empty($workKeysToDelete) ) {
            $msg2 = sprintf("Database error reading fulfillment records");
            $ok = $iwqManager->getByWorkKey(array_keys($workKeysToDelete), $iwqRecs);
            if ( ! $ok ) {
                $msg = "Unable to fetch fulfillment record(s) for entry to be deleted";
                $gErr->addIAError('INV-0365', __FILE__ . ':' . __LINE__, $msg, [], $msg2, []);
            }
            foreach ( $iwqRecs as $iwqRec ) {
                $msg = sprintf("Unable to delete line %1s", $iwqRec['LINENO']);
                $placeholderTxt = $iwqRec['LINENO'];
                if ( $workKeysToDelete[$iwqRec['WORKKEY']] != 0 ) {
                    // Not allowed to unilaterally delete this; must be unwound via fulfillment first
                    $ok = false;
                    $gErr->addIAError('INV-0366', __FILE__ . ':' . __LINE__, $msg, ['IWQ_REC_LINENO' => $iwqRec['LINENO']],
                                    "Quantity is converted for the line item entry in fulfillment.", [],
                                    "To delete the line, the line item entry in fulfillment must not be converted.", []
                    );
                    break;
                }
                if ( $iwqRec['PLACE'] !== InventoryWorkQueueManager::QUEUE_OPEN ) {
                    // Not allowed to unilaterally delete this; must be unwound via fulfillment first
                    $ok = false;
                    $gErr->addIAError(
                        'INV-0367',
                        __FILE__ . ':' . __LINE__,
                        $msg, ['IWQ_REC_LINENO' => $iwqRec['LINENO']],
                       "Quantity is reserved or allocated for the line item entry in fulfillment.", [],
                      "To delete the line, the status of the line item entry in fulfillment needs to be Open.", []
                    );
                    break;
                }
                if ( $iwqRec['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN && ! $ignoreHold && $iwqRec['HOLDPROGRESS'] == 'true' ) {
                    // Not allowed to unilaterally delete this; must be unwound via fulfillment first
                    $ok = false;
                    $gErr->addIAError(
                        'INV-0368',
                        __FILE__ . ':' . __LINE__,
                        $msg, ['IWQ_REC_LINENO' => $iwqRec['LINENO']],
                        "Order or line item entry is on hold in fulfillment",[],
                        "To delete the line, the line item entry in fulfillment should not be on hold.", []
                    );
                    break;
                }
                // TODO: Enhancement request: batch delete for performance?
                $ok = $ok && $iwqManager->Delete($iwqRec['RECORD#']);
                if ( ! $ok ) {
                    $gErr->addIAError('INV-0369', __FILE__ . ':' . __LINE__, $msg, ['IWQ_REC_LINENO' => $placeholderTxt]);
                    break;
                }
            }
        }

        return $ok;
    }

    /**
     * Inspect the collated fields and if necessary, delete (complete) and/or update the required fulfillment records
     * based on any entry deletes and/or edits.
     *
     * @return bool True if successful, false otherwise
     */
    public function updateFulfillment()
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $iwqManager = Globals::$g->gManagerFactory->getManager("inventoryworkqueue");
        $ok = $ok && $this->handleDeletedEntries($gErr);
        $ok = $ok && $this->handleUpdatedEntries($iwqManager, $gErr);

        return $ok;
    }

    /**
     * Check whether there are any deleted entries, and if so, delete (i.e., complete) the corresponding
     * work queue records. (In case there are allocations, we're relying here on fulfillment to unwind
     * them correctly.)
     *
     * @param IAIssueHandler $gErr
     *
     * @return bool
     */
    private function handleDeletedEntries(IAIssueHandler $gErr)
    {
        $ok = true;
        $workKeysToDelete = [];
        foreach ( $this->collatedEntries as $collatedEntry ) {
            if ( $this->hasFulfillmentRecords($collatedEntry) && $this->isDeleted($collatedEntry) ) {
                // This line has been deleted. Need to complete any associated ICWQ records.
                $workKeysToDelete[$collatedEntry['WORKKEY']] =
                    $workKeysToDelete[$collatedEntry['WORKKEY']] ?? 0 + $collatedEntry['QTY_CONVERTED'];
            }
        }
        $ok = $ok && self::deleteByWorkkeys($workKeysToDelete, $gErr);
        if ( ! $ok ) {
            $gErr->addIAError('INV-0037', __FILE__ . ':' . __LINE__, 'Unable to edit entry', [],
                            'Error validating fulfillment', []);
        }

        return $ok;
    }

    /**
     * Check whether there are any edited updates. Edits include: quantity, line number, warehouse, uom, and itemid.
     *
     * In case of uom, also determine the new convfactor/uomfactor.
     *
     * In case of quantity decrease, there are additional rules as to when it's allowed, and yet more rules as to
     * the order in which existing work queue records' quantities should be affected.
     *
     * @param InventoryWorkQueueManager $iwqManager
     * @param IAIssueHandler            $gErr
     *
     * @return bool
     */
    private function handleUpdatedEntries(InventoryWorkQueueManager $iwqManager, IAIssueHandler $gErr)
    {
        $ok = true;
        $changes = [];
        $qtyDecreases = [];
        foreach ( $this->collatedEntries as $lineno => $collatedEntry ) {
            // Skip entries not in fulfillment (including new ones), as well as deleted entries
            if ( ! $this->hasFulfillmentRecords($collatedEntry) || $this->isDeleted($collatedEntry) ) {
                // Nothing to do here
                continue;
            }
            $workkey = $collatedEntry['WORKKEY'];
            // First, check if quantity has decreased; increase requires no special handling
            if ( $collatedEntry['NEW_QUANTITY'] < $collatedEntry['OLD_QUANTITY'] ) {
                // Yes, there may be more work to do
                $qtyDecrease = $collatedEntry['OLD_QUANTITY'] - $collatedEntry['NEW_QUANTITY'];
                $qtyNotAllocated = $collatedEntry['OLD_QUANTITY'] - $collatedEntry['ALLOCATED_QUANTITY'];
                $qtyWithoutFulfillmentRecords = $collatedEntry['OLD_QUANTITY'] - $collatedEntry['OPEN_QUANTITY']
                                                - $collatedEntry['COMMITTED_QUANTITY'];
                if ( $qtyDecrease > $qtyNotAllocated - $collatedEntry['QTY_CONVERTED'] ) {
                    // No can do, decrease not possible/allowed; we can't touch allocated or converted quantity here
                    $itemId = $collatedEntry['NEW_ITEMID'];
                    $msg =
                        sprintf("Unable to reduce quantity of item '%1s' on line %2s", $itemId, $lineno);
                    $corr = 'Decrease the quantity by an amount that does not exceed the open and reserved quantity for the line item entry.';
                    $gErr->addIAError('INV-0370', __FILE__ . ':' . __LINE__, $msg, ['ITEM_ID' => $itemId, 'LINENO' => $lineno],
                                    'There is not enough open and reserved quantity.', [],
                                    $corr, []
                    );
                    $ok = false;
                    break;
                }
                if ( $qtyDecrease > $qtyWithoutFulfillmentRecords ) {
                    // The decrease cannot be accommodated without affecting work queue records
                    $qtyDecrease -= $qtyWithoutFulfillmentRecords;
                    $qtyDecreases[$collatedEntry['WORKKEY']] = $qtyDecrease;
                } // Otherwise fulfillment doesn't need to know about this decrease
            }

            // Next, check if unit has changed
            if ( $ok && $collatedEntry['NEW_UNIT'] != $collatedEntry['OLD_UNIT'] ) {
                // Add the new unit to the changelist
                $changes[$workkey]['UOM'] = $collatedEntry['NEW_UNIT'];
                // Along with the new uomfactor
                $changes[$workkey]['UOMFACTOR'] =
                    $this->getUomFactor($collatedEntry['NEW_ITEMUOM'], $collatedEntry['NEW_UNIT']);
            }

            // Finally round up any remaining edits to the entry; potentially: LINENO, WAREHOUSEID, ITEMID
            if ( $ok && $collatedEntry['NEW_ITEMID'] != $collatedEntry['OLD_ITEMID'] ) {
                $changes[$workkey]['ITEMID'] = $collatedEntry['NEW_ITEMID'];
            }
            if ( $ok && is_array($collatedEntry['NEW_WAREHOUSE']) && is_array($collatedEntry['OLD_WAREHOUSE'])
                 && $collatedEntry['NEW_WAREHOUSE']['LOCATION_NO'] != $collatedEntry['OLD_WAREHOUSE']['LOCATION_NO'] ) {
                $changes[$workkey]['WAREHOUSEID'] = $collatedEntry['NEW_WAREHOUSE']['LOCATION_NO'];
            }
            if ( $ok && $collatedEntry['NEW_LINE_NO'] != $collatedEntry['OLD_LINE_NO'] ) {
                $changes[$workkey]['LINENO'] = $collatedEntry['NEW_LINE_NO'];
            }
        }

        if ( $ok && ( ! empty($changes) || ! empty($qtyDecreases) ) ) {
            $isQtyDecreaseOnly = empty($changes);
            // Note: Anything other than a quantity decrease requires updates to all (uncompleted) ICWQ records.
            $changedWorkkeys = array_keys($changes);
            $iwqRecs = [];
            $ok = $iwqManager->getByWorkKey($changedWorkkeys, $iwqRecs);
            if ( ! $ok ) {
                $msg = sprintf("Database error reading fulfillment records");
                $gErr->addIAError('INV-0371', __FILE__ . ':' . __LINE__,
                                'Unable to read fulfillment records', [], $msg, []);
                return $ok;
            }

            // Filter allocations and sort $iwqRecs in order of quantity decrease consumption
            $sortedIwqRecs = $this->filterAndSort($iwqRecs);
            $changedIwqRecs = [];
            foreach ( $sortedIwqRecs as &$iwqRec ) {
                if ( isset($qtyDecreases[$iwqRec['WORKKEY']]) ) {
                    // Handle quantity decreases
                    if ( $qtyDecreases[$iwqRec['WORKKEY']] >= $iwqRec['QUANTITY'] ) {
                        // Need more than there is in the icwq record: Zero this record out.
                        $qtyDecreases[$iwqRec['WORKKEY']] -= $iwqRec['QUANTITY'];
                        $iwqRec['QUANTITY'] = 0;
                    } else if ( $qtyDecreases[$iwqRec['WORKKEY']] > 0 ) {
                        // Need less than there is in this icwq record: Subtract the remainder
                        $iwqRec['QUANTITY'] -= $qtyDecreases[$iwqRec['WORKKEY']];
                        $qtyDecreases[$iwqRec['WORKKEY']] = 0;
                    }
                    $ok = $ok && self::recalculateAllocationAndReserve($iwqRec);
                    if ( ! $ok ) {
                        break;
                    }
                    $changedIwqRecs[] = $iwqRec;
                }
                foreach ( $changes[$iwqRec['WORKKEY']] ?? [] as $key => $value ) {
                    $errorLabel = self::$errorLabels[$key] ?? $key;
                    $msg =
                        sprintf("Unable to change the %1s for item '%2s' on line %3s",$errorLabel ,
                                $iwqRec['ITEMID'], $iwqRec['LINENO']);
                    if ( $this->collatedEntries[$iwqRec['LINENO']]['QTY_CONVERTED'] > 0 ) {
                        // This can't be allowed; some or all of this entry has already been converted
                        $corr =
                            'To edit this attribute, the status of the line item entry in fulfillment needs to be Open.';
                        $gErr->addIAError(
                             'INV-0372', __FILE__ . ':' . __LINE__,
                             $msg, ['ERROR_LABELS_KEY_COALESCE_KEY' => $errorLabel, 'IWQ_REC_ITEMID' => $iwqRec['ITEMID'], 'IWQ_REC_LINENO' => $iwqRec['LINENO']],
                            'Quantity is reserved or allocated for the line item entry in fulfillment.', [] ,
                             $corr, []
                        );
                        // i18N::TODO - (Code Change Review).
                        $ok = false;
                        break;
                    }
                    if ( $key != 'LINENO' && $iwqRec['PLACE'] !== InventoryWorkQueueManager::QUEUE_OPEN) {
                        // This can't be allowed; e.g., can't change WAREHOUSE after picking
                        $corr = 'You may only edit this attribute when this entry is open in fulfillment';
                        $gErr->addIAError(
                            'INV-0373', __FILE__ . ':' . __LINE__,
                            $msg, ['ERROR_LABELS_KEY_COALESCE_KEY' => $errorLabel, 'IWQ_REC_ITEMID' => $iwqRec['ITEMID'], 'IWQ_REC_LINENO' => $iwqRec['LINENO']],
                            'Entry is committed or reserved in fulfillment', [],
                            $corr, []
                        );
                        $ok = false;
                        break;
                    }
                    $iwqRec[$key] = $value;
                }
                if ( $ok && ! $isQtyDecreaseOnly ) {
                    // Changes other than quantity decreases require updates to all work queue records for this entry
                    $changedIwqRecs[] = $iwqRec;
                }
            }
            unset($iwqRec);

            // TODO: 1 set() at the very end is faster?
            if ( $ok ) {
                $ok = $ok && $iwqManager->set($changedIwqRecs);
                if ( ! $ok ) {
                    $msg = sprintf("Error updating fulfillment records");
                    $gErr->addIAError('INV-0374', __FILE__ . ':' . __LINE__,
                                    'Unable to update fulfillment records', [], $msg, []);
                }
            }
        }

        return $ok;
    }

    /**
     * @param string[][] $itemuoms
     * @param string     $newUnit
     *
     * @return mixed|string
     */
    private function getUomFactor($itemuoms, $newUnit)
    {
        $convfactor = '';
        foreach ( $itemuoms as $itemuom ) {
            if ( $itemuom['UNIT'] == $newUnit ) {
                $convfactor = $itemuom['CONVFACTOR'];
                break;
            }
        }

        return $convfactor;
    }

    /**
     * Arrange work queue records in the order in which quantity may be decreased. Allocations appear last--technically
     * they may not be decreased, so the caller is responsible for keeping them off limits.
     *
     * @param array $iwqRecs
     *
     * @return array
     */
    private function filterAndSort(array $iwqRecs)
    {
        $openNotPrinted = [];
        $openPrinted = [];
        $reservedNotPrinted = [];
        $reservedPrinted = [];
        $allocated = [];
        foreach ( $iwqRecs as $iwqRec ) {
            if ( $iwqRec['PLACE'] === InventoryWorkQueueManager::QUEUE_OPEN) {
                if ( $this->isPrinted($iwqRec) ) {
                    $openPrinted[] = $iwqRec;
                } else {
                    $openNotPrinted[] = $iwqRec;
                }
            } else if ( $iwqRec['QUANTITYINRESERVE'] > 0 ) {
                if ( $this->isPrinted($iwqRec) ) {
                    $reservedPrinted[] = $iwqRec;
                } else {
                    $reservedNotPrinted[] = $iwqRec;
                }
            } else {
                $allocated[] = $iwqRec;
            }
        }

        return array_merge($openNotPrinted, $openPrinted, $reservedNotPrinted, $reservedPrinted, $allocated);
    }

    /**
     * @param string[] $iwqRec
     *
     * @return bool
     */
    private function isPrinted($iwqRec)
    {
        return isset($iwqRec['PICKLISTPRINTED']) || isset($iwqRec['PACKLISTPRINTED']);
    }
}
