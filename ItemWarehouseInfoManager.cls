<? /** @noinspection NestedPositiveIfStatementsInspection */

import('OwnedObjectManager');

/**
 * Class ItemWarehouseInfoManager
 */
class ItemWarehouseInfoManager extends OwnedObjectManager
{



    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = true;
        // ok, here's a thing: apparently people are happy to pass in EMPTY warehouse entries in the API.
        // but, the Item Manager fills in some fields (recordno, line_no, others), so I'm at a loss
        // how to insure that the ONLY thing they omitted was WAREHOUSEID.  Anyway, here, if they forget
        // the warehouse id, ignore the record with no error :-(.  Note that for API 3.0 I handle this
        // much better in API_ValidateObject in ItemManager.  This is for 2.1 APIs :-(
        if (isset($values['WAREHOUSEID']) && ($values['WAREHOUSEID'] != '')) {
            $ok = $this->validate($values);
            $ok = $ok && $this->prepValues($values);
            $ok = $ok && parent::regularAdd($values);
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
        $ok = true;
        // ok, here's a thing: apparently people are happy to pass in EMPTY warehouse entries in the API.
        // but, the Item Manager fills in some fields (recordno, line_no, others), so I'm at a loss
        // how to insure that the ONLY thing they omitted was WAREHOUSEID.  Anyway, here, if they forget
        // the warehouse id, ignore the record with no error :-(.  Note that for API 3.0 I handle this
        // much better in API_ValidateObject in ItemManager.  This is for 2.1 APIs :-(
        if (isset($values['WAREHOUSEID']) && ($values['WAREHOUSEID'] != '')) {
            $ok = $this->validate($values,true);
            $ok = $ok && $this->prepValues($values);
            $ok = $ok && parent::regularSet($values);
        }

        return $ok;
    }


    /**
     * @param string     $ID
     * @param array      $fields
     *
     * @return array|bool
     */
    public function Get($ID, $fields=null)
    {
        list($ID) = explode('--', $ID);
        $toreturn = parent::get($ID);

        if (is_array($toreturn) && ItemManager::isReplenishmentOn()) {
            self::possiblyCleanUpValues($toreturn);
            $toreturn['W_ENABLE_REPLENISHMENT'] = ItemManager::GetWarehouseReplenishmentEnableFlag($toreturn['WAREHOUSEID']);    // does the WAREHOUSE enable replenishment?
        }
        return $toreturn;
    }


    /**
     *  possibly clean up values        there is sql code somewhere that creates these records when you do a Purchase that refers to
     *                                  an item that doesn't already have the warehouse in the item/warehouse list.  That is ok,
     *                                  but the sql code doesn't bother to set fields to values that our QA currently finds valuable.
     *                                  I mean, the record works fine in code, but the values are EMPTY rather than ZERO, for example.
     *
     *                                  The sql routine doesn't use the manager here, of course, so we need to do this on each READ, which is infuriating.
     *
     * @param array     $values     values we will return to the client
     */
    public static function possiblyCleanUpValues(&$values)
    {
        $setEmptyTos = [
            'SAFETY_STOCK' => '0',  'REORDER_POINT' => '1', 'REORDER_QTY' => '0',
        ];
        foreach ($setEmptyTos as $setEmptyTo => $value) {
            if ( ! isset($values[$setEmptyTo]) || ($values[$setEmptyTo] == '')) {
                $values[$setEmptyTo] = $value; // so it shows in the UI as a ZERO not empty or "--"
            }
        }

        if ( ! isset($values['REPLENISHMENT_METHOD']) || ($values['REPLENISHMENT_METHOD'] == '')) {
            $inventoryPrefs = array();
            GetModulePreferences(Globals::$g->kINVid, $inventoryPrefs);
            $values['REPLENISHMENT_METHOD'] = $inventoryPrefs['FORECAST_METHOD'] ?? 'REORDER_POINT'; // default the answer if unspecified

            global $gSalesForecastMethodValues, $gSalesForecastMethodIValues;
            $key = array_search($values['REPLENISHMENT_METHOD'], $gSalesForecastMethodIValues); // now find it in the list
            if ($key !== false) {
                $values['REPLENISHMENT_METHOD'] = $gSalesForecastMethodValues[$key];            // and convert to English
            }

        }
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function validate(&$values,$isUpdate=false)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $maybeAnInventoryItem = true;
        if (isset($values['IS_INVENTORY_ITEM']) && ($values['IS_INVENTORY_ITEM'] === false)) {
            $maybeAnInventoryItem = false; // false means 'I'm sure it is NOT an inventory item', and is set by the item manager on an regularAdd() or set() call
        }

        $defaultFields = ['MIN_ORDER_QTY', 'MAX_STOCK','MIN_STOCK', "ECONOMIC_ORDER_QTY"];
        foreach ($defaultFields as $field => $theDefault) {
            if (( ! isset($values[$field])) || ($values[$field] === '')) {
                continue;
            }
            if ($values[$field] < 0) {
                $gErr->addIAError(
                    'INV-0739', __FILE__ . ":" . __LINE__,
                    sprintf("%s must be greater than or equal to zero.", $field),
                    ['FIELD' => $field]
                );
                $ok = false;
                $values[$field] = $theDefault;
            } else if (!is_numeric($values[$field]) || !is_integer(0 + $values[$field])) {
                Globals::$g->gErr->addIAError(
                    'INV-0740', __FILE__ . ":" . __LINE__,
                    sprintf("%s must be must be a whole number", $field),
                    ['FIELD' => $field]
                );
                $ok = false;
            }else if(strlen($values[$field])> 8){
                Globals::$g->gErr->addIAError(
                    'INV-0741', __FILE__ . ":" . __LINE__,
                    sprintf("Inserted value  is too large for the '%s' field.", $field),
                    ['FIELD' => $field]
                );
                $ok = false;
            }
        }
        // Check replenishment values:
        if (ItemManager::isReplenishmentOn() && $maybeAnInventoryItem) {
            // Check replenishment values:
            if (ItemManager::$fromAPI || ($values['ENABLE_REPLENISHMENT'] === 'true') || ($values['ENABLE_REPLENISHMENT'] === 'T')) {

                // because of 8.1 we need to default some values; in 8.1 (0 != '')
                $defaultThese = ['SAFETY_STOCK'  => 1, 'REORDER_POINT' => 1,
                    'MAX_ORDER_QTY' => 0, 'REORDER_QTY'   => 0];

                foreach ($defaultThese as $field => $theDefault) {
                    if (( ! isset($values[$field])) || ($values[$field] == '')) {
                        $values[$field] = $theDefault;
                    }
                    if ($values[$field] < 0) {
                        $gErr->addIAError(
                            'INV-0689', __FILE__ . ":" . __LINE__,
                            sprintf("%s must be greater than or equal to zero.", $field),
                            ['FIELD' => $field]
                        );
                        $ok = false;
                        $values[$field] = $theDefault;
                    } else if (!is_numeric($values[$field]) || !is_integer(0 + $values[$field])) {
                        Globals::$g->gErr->addIAError(
                            'INV-0690', __FILE__ . ":" . __LINE__,
                            sprintf("%s must be must be a whole number", $field),
                            ['FIELD' => $field]
                        );
                        $ok = false;
                    }else if(strlen($values[$field])> 8){
                        Globals::$g->gErr->addIAError(
                            'INV-0691', __FILE__ . ":" . __LINE__,
                            sprintf("Inserted value  is too large for the '%s' field.", $field),
                            ['FIELD' => $field]
                        );
                        $ok = false;
                    }
                }

                $values['MAX_ORDER_QTY_REP'] = $values['MAX_ORDER_QTY'];  // ..._REP is used in the UI for temp holding.  Not sure if this is needed.
                if ($values['MAX_ORDER_QTY'] != 0) {
                    if ($values['REORDER_QTY'] > $values['MAX_ORDER_QTY']) {
                        $gErr->addIAError(
                            'INV-0204', __FILE__ . ":" . __LINE__, "The 'Quantity to reorder' must be less than or the same as 'Maximum order quantity'.", []);
                        $ok = false;
                        $values['REORDER_QTY'] = $values['MAX_ORDER_QTY'];
                    }
                }

                if ($values['REORDER_POINT'] <= 0) {
                    $gErr->addIAError(
                        'INV-0205', __FILE__ . ":" . __LINE__, "Reorder point must be greater than zero.", []);
                    $ok = false;
                    $values['REORDER_POINT'] = 1;
                }

                // note: we screwed up early on and saved English in the preferences, and then of course the phrase changed.
                //      so, here we clean that up if it existed, and clean up any case issues for the API and CSV import
                global $gSalesForecastMethodValues, $gSalesForecastMethodIValues;
                // The CSV used to support 'SALES_FORECAST_METHOD', account for that change here:
                if (isset($values['SALES_FORECAST_METHOD']) && ($values['SALES_FORECAST_METHOD'] != '')) {
                    $values['REPLENISHMENT_METHOD'] = $values['SALES_FORECAST_METHOD'];
                }
                $method = ReplenishDetailManager::getInternalSalesForecastMethod($values['REPLENISHMENT_METHOD']); // normalize
                $key = array_search($method, $gSalesForecastMethodIValues);
                if ($key !== false) {
                    $values['REPLENISHMENT_METHOD'] = $gSalesForecastMethodValues[$key];
                }
            }
        }

        // For API: validate request body.
        if(!$isUpdate) {
            $qry = "SELECT count(1) AS isExist FROM icitemwhse iw WHERE iw.cny#=:1 AND itemkey= : 2 AND warehousekey = : 3";
            $res = QueryResult(array($qry, GetMyCompany(), $values['ITEMID'], $values['WAREHOUSEID']));
            if ($res && $res[0]['ISEXIST'] > 0) {
                $gErr->addIAError('INV-0742', GetFL(), "Duplicate warehouse " . $values['WAREHOUSEID'] . "!", ['WAREHOUSEID' => $values['WAREHOUSEID']]);
                $ok =  false;
            }
        }else{
            $qry = "SELECT count(1) AS isExist FROM icitemwhse iw WHERE iw.cny#=:1 AND itemkey= : 2 AND record# = : 3";
            $res = QueryResult(array($qry, GetMyCompany(), $values['ITEMID'], $values['RECORDNO']));
            if ($res && $res[0]['ISEXIST'] == 0) {
                $gErr->addIAError('INV-0206', GetFL(), "Cannot move warehouse between the items!", []);
                $ok =  false;
            }
        }
        if (isset($values['CYCLE']) && $values['CYCLE'] != "") {
            $qry = "SELECT count(1) AS isExist FROM iccycle i WHERE i.cny#=:1 AND i.cycleid= : 2";
            $res = QueryResult(array($qry, GetMyCompany(), $values['CYCLE']));
            if ($res && $res[0]['ISEXIST'] == 0) {
                $gErr->addIAError(
                    'INV-0743', GetFL(),
                    "Invalid inventory cycle '" . $values['CYCLE'] . "'!",
                    ['CYCLE' => $values['CYCLE']]
                );
                $ok =  false;
            }
        }

        if(isset($values['ENABLE_REPLENISHMENT']) && $values['ENABLE_REPLENISHMENT'] === true){
            $values['ENABLE_REPLENISHMENT']='true';
        }

        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    function prepValues(&$values)
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;

        if (isset($values['LAST_COST'])) {
            $values['LAST_COST'] = preg_replace("/[^0-9.]/", "", $values['LAST_COST']);
        }

        if (isset($values['AVERAGE_COST'])) {
            $values['AVERAGE_COST'] = preg_replace("/[^0-9.]/", "", $values['AVERAGE_COST']);
        }

        if ($ok && $values['DEFAULT_AISLE']) {
            $aisleMgr = $gManagerFactory->getManager('aisle');
            $row = $aisleMgr->GetRaw($values['DEFAULT_AISLE']);
            $ok = $ok && isset($row[0]);
            if (!$ok) {
                $msg = "Invalid Default Aisle '" . $values['DEFAULT_AISLE'] . "' specified For Item '" . $values['ITEMID'] . "'";
                $gErr->addIAError(
                    'INV-0744', __FILE__ . ':' . __LINE__,
                    $msg, ['DEFAULT_AISLE' => $values['DEFAULT_AISLE'], 'ITEMID' => $values['ITEMID']]
                );
            }
            $values['AISLEKEY'] = $row[0]['RECORD#'];
        }

        if ($ok && $values['DEFAULT_ROW']) {
            $rowMgr = $gManagerFactory->getManager('icrow');
            $row = $rowMgr->GetRaw($values['DEFAULT_ROW']);
            $ok = $ok && isset($row[0]);
            if (!$ok) {
                $msg = "Invalid Default Row '" . $values['DEFAULT_ROW'] . "' specified For Item '" . $values['ITEMID'] . "'";
                $gErr->addIAError(
                    'INV-0745', __FILE__ . ':' . __LINE__,
                    $msg, ['DEFAULT_ROW' => $values['DEFAULT_ROW'], 'ITEMID' => $values['ITEMID']]
                );
            }
            $values['ROWKEY'] = $row[0]['RECORD#'];
        }

        if ($ok && (isset($values['DEFAULT_BIN']) && $values['DEFAULT_BIN'] != '')) {
            $binMgr = $gManagerFactory->getManager('bin');
            $row = $binMgr->GetRaw($values['DEFAULT_BIN']);
            $ok = $ok && isset($row[0]);
            if (!$ok) {
                $msg = "Invalid Default Bin '" . $values['DEFAULT_BIN'] . "' specified For Item '" . $values['ITEMID'] . "'";
                $gErr->addIAError(
                    'INV-0746', __FILE__ . ':' . __LINE__,
                    $msg, ['DEFAULT_BIN' => $values['DEFAULT_BIN'], 'ITEMID' => $values['ITEMID']]
                );
            }
            $values['BINKEY'] = $row[0]['RECORD#'];
        }

        return $ok;
    }

    /**
     * @param string    $itemID
     * @param string    $whseID
     *
     * @return string
     */
    function GetItemWarehouseAverageCost($itemID, $whseID)
    {
        $params = array(
            'selects' => array('AVERAGE_COST'),
            'filters' => array(
                array(
                    array('ITEMID', '=', $itemID),
                    array('WAREHOUSEID', '=', $whseID),
                )
            ),
        );

        $res = $this->GetList($params);

        return $res[0]['AVERAGE_COST'] ?? '0';
    }

    /**
     * @param string $_parent parentkey
     *
     * @return array
     */
    function getByParent($_parent)
    {
        $rows = parent::getByParent($_parent);
        usort($rows, array('ItemWarehouseInfoManager', 'sortByWarehouseID'));

        return array_values($rows);
    }

    /**
     * Sort the item's warehouses by warehouseid
     *
     * @param array $a the first value to compare
     * @param array $b the second value to compare
     *
     * @return int
     */
    private function sortByWarehouseID($a, $b)
    {
        $retval = strnatcmp($a['WAREHOUSEID'], $b['WAREHOUSEID']);

        return $retval;
    }



    /**
     *      When upgrading bins from Classic to Advanced, we need to update the 'default bins'
     *
     * @param array       $binInfo        an array with BINKEY (the existing key), WHSEKEY, AISLEKEY, and ROWKEY
     *
     * @return bool
     */
    public function updateForNewBins(&$binInfo)
    {
        $ok    = true;
        $cny   = GetMyCompany();
        $qry   = [];
        $qry[] = "SELECT iw.record#, w.record# as warehousekey, iw.aislekey, iw.rowkey, iw.binkey 
                        FROM icitemwhse iw, icwarehouse w WHERE iw.cny#=:1 AND iw.cny#=w.cny# AND 
                             iw.warehousekey = w.location_no AND
                        (binkey IS NOT NULL OR aislekey IS NOT NULL OR rowkey IS NOT NULL)";
        $qry[] = $cny;
        $found = QueryResult($qry);
        if ($found === false) {
            $ok = false;
        } else {
            // make a quick lookup cache
            $binCache = [];
            foreach ($binInfo as $row) {
                $whsekey  = $row['WHSEKEY']  ?? 0;
                $aislekey = $row['AISLEKEY'] ?? 0;
                $rowkey   = $row['ROWKEY']   ?? 0;
                $binkey   = $row['BINKEY']   ?? 0;
                $binCache[$whsekey][$aislekey][$rowkey][$binkey] = $row['NEW_BINKEY'] ?? $row['BINKEY'];    // current key
            }

            foreach ($found as $row) {
                $whsekey   = $row['WAREHOUSEKEY']    ?? 0;
                $aislekey  = $row['AISLEKEY']        ?? 0;
                $rowkey    = $row['ROWKEY']          ?? 0;
                $binkey    = $row['BINKEY']          ?? 0;
                $newBinKey = $binCache[$whsekey][$aislekey][$rowkey][$binkey] ?? 0;  // found?
                if ($binkey != $newBinKey) {                                         // does it need to change?
                    $qry = [];
                    if ($newBinKey == 0) {
                        $qry[] = "UPDATE icitemwhse SET binkey TO NULL WHERE cny#=:1 AND record#=:2";
                    } else {
                        $qry[] = "UPDATE icitemwhse SET binkey=:3 WHERE cny#=:1 AND record#=:2";
                    }
                    $qry[] = $cny;
                    $qry[] = $row['RECORD#'];
                    if ($newBinKey) {
                        $qry[] = $newBinKey;
                    }
                    $ok = $ok && ExecStmt($qry);
                }
            }
        }

        // now zero out any aisle and row keys.....
        $qry   = [];
        $qry[] = "UPDATE icitemwhse SET aislekey=null, rowkey=null WHERE cny#=:1 AND (aislekey IS NOT NULL OR rowkey IS NOT NULL)";
        $qry[] = $cny;
        $ok = $ok && ExecStmt($qry);
        return $ok;
    }

    function BaseGet($ID, $fields = null)
    {
        $res = parent::BaseGet($ID, $fields);
        $gManagerFactory = Globals::$g->gManagerFactory;
        $invSetupMgr =  $gManagerFactory->getManager('invsetup');
        $invPrefs = $invSetupMgr->get('');
        //For NextGen API, Unset fulfillment columns from result if fulfillment is disabled.
        if ($invPrefs['ENABLEFULFILLMENT'] == 'false') {
            unset($res['WRESERVED']);
            unset($res['WALLOCATED']);
            unset($res['WUNCOMMITTED']);
        }
        //For NextGen API, If WHSE_CURRENCY is null get base currency
        if (empty($res['WHSE_CURRENCY'])) {
            $baseCurrency = GetBaseCurrency();
            $res['WHSE_CURRENCY'] = $baseCurrency;
        }
        return $res;
    }
}
