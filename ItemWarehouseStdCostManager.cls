<?

import('OwnedObjectManager');

/**
 * Class ItemWarehouseStdCostManager
 */
class ItemWarehouseStdCostManager extends OwnedObjectManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = true;
        $ok = $ok && $this->prepValues($values);

        $ok = $ok && parent::regularAdd($values);

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
        $ok = $ok && $this->prepValues($values);

        $ok = $ok && parent::regularSet($values);

        return $ok;
    }

    /**
     * @param string    $date
     * @param string    $itemID
     * @param string    $whseID
     *
     * @return string
     */
    function GetStandardCostByEffectiveDate($date, $itemID, $whseID)
    {
        $params = array(
            'selects' => array('ITEMID', 'WAREHOUSEID', 'EFFECTIVE_START_DATE', 'STANDARD_COST'),
            'filters' => array(array(
                array('ITEMID', '=', $itemID),
                array('WAREHOUSEID', '=', $whseID),
                array('EFFECTIVE_START_DATE', '<=', $date),
            )
            ),
            'orders' => array(array('EFFECTIVE_START_DATE', 'desc')),
        );

        $res = $this->GetList($params);

        return $res[0]['STANDARD_COST'] ?? '0';
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function prepValues(&$values)
    {
        $ok = true;

        $ok = $ok && $this->ValidateItem($values);

        $ok = $ok && $this->ValidateItemWarehouse($values);

        $ok = $ok && $this->ValidateEffectiveDate($values);

        $ok = $ok && $this->ValidateStandardCost($values);

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function ValidateItem(&$values){
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ok = true;

        $itemID = $values['ITEMID'];
        // Rest API will not write Item ID so we are getting the item id from Item Warehouse Key if its set.
        $itemWarehouseKey = $values['ITEMWSEKEY'];
        if (!isset($itemID) && isset($itemWarehouseKey) && $itemWarehouseKey !== '') {
            $itemWarehouseInfoManger =  $gManagerFactory->getManager('itemwarehouseinfo');
            $itemWarehouseParams = array(
                'selects' => array('ITEMID','WAREHOUSEID'),
                'filters' => array(array(
                    array('RECORDNO', '=', $itemWarehouseKey),
                )
                ),
            );
            $itemWarehouseInfo = $itemWarehouseInfoManger->GetList($itemWarehouseParams);
            $itemWarInfo = $itemWarehouseInfo[0];
            $itemID = $itemWarInfo['ITEMID'];
            $values['ITEMID'] = $itemID;
            $values['WAREHOUSEID'] = $itemWarInfo['WAREHOUSEID'];
        }
        // -- check if the item exists
        $itemMgr =  $gManagerFactory->getManager('item');

        $itemParams = array(
            'selects' => array('ITEMID', 'ITEMTYPE', 'COST_METHOD', 'ENABLEFULFILLMENT'),
            'filters' => array(array(
                array('ITEMID', '=', $itemID),
            )
            ),
        );

        $itemInfo = $itemMgr->GetList($itemParams);
        $itemInfo = $itemInfo[0];

        if(!$itemInfo){
            $msg = "Item '".$itemID."' doesnt exist";
            $gErr->addIAError(
                'INV-0747', __FILE__ . ':' . __LINE__,
                $msg, ['ITEMID' => $itemID]
            );
            $ok = false;
        }

        // if the item type is not inventory
        // throw error
        $fulfillmentEnabled = $itemMgr->isFulfillmentEnabled($itemInfo);
        if ( $itemInfo['ITEMTYPE'] != 'Inventory' && !$fulfillmentEnabled ) {
            $msg = "Item ID '" . $itemID . "' is an inventory item with a non-standard cost method or 
                is a non-inventory item that is not enabled for fulfilment. 
                These types of items cannot have standard costs. ";
            $gErr->addIAError(
                'INV-0748', __FILE__ . ':' . __LINE__,
                $msg, ['ITEMID' => $itemID]
            );
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function ValidateItemWarehouse(&$values){
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $itemID = $values['ITEMID'];
        $whseID = $values['WAREHOUSEID'];

        // -- check if the warehouse exists in Item
        $itemWhseMgr =  $gManagerFactory->getManager('itemwarehouseinfo');
        $itemWhseParams = array(
            'selects' => array('RECORDNO', 'ITEMID', 'WAREHOUSEID'),
            'filters' => array(array(
                array('ITEMID', '=', $itemID),
                array('WAREHOUSEID', '=', $whseID),
            )
            ),
        );

        $itemWhse = $itemWhseMgr->GetList($itemWhseParams);
        $itemWhse = $itemWhse[0];

        // if warehouse key is missing then the warehouse doesnt exist
        if(!isset($itemWhse['RECORDNO']) || $itemWhse['RECORDNO']==''){
            $msg = "Warehouse '".$whseID."' doesnt exist or it is not defined in the item '".$itemID."'.".
                " Create or add the warehouse to item and try again.";

            $gErr->addIAError(
                'INV-0749', __FILE__ . ':' . __LINE__,
                $msg, ['WHSEID' => $whseID, 'ITEMID' => $itemID]
            );
            $ok = false;
        }else{
            //
            // assign the parent key
            $values['ITEMWHSEKEY'] = $itemWhse['RECORDNO'];
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function ValidateEffectiveDate(&$values){
        $gErr = Globals::$g->gErr;

        $ok = true;
        $lineNo = $values['LINE_NO']+1;
        $whseID = $values['WAREHOUSEID'];
        $hasEffectiveStartdate = (isset($values['EFFECTIVE_START_DATE']) && $values['EFFECTIVE_START_DATE'] !='');
        $hasStandardCost = (isset($values['STANDARD_COST']) && $values['STANDARD_COST'] !='');

        // Effective start date entered?
        if (!$hasEffectiveStartdate && $hasStandardCost) {
            $msg = "Effective Start date in line $lineNo for warehouse '".$whseID."' is not entered.";
            $gErr->addIAError(
                'INV-0750', __FILE__ . ':' . __LINE__,
                "", [],
                $msg, ['LINE_NO' => $lineNo, 'WHSEID' => $whseID]
            );
            $ok = false;
        }

        // Effective start date is with correct date format?
        if ($hasEffectiveStartdate && !ValidateDate(isl_trim($values['EFFECTIVE_START_DATE']))) {
            $msg = "Effective Start date in line $lineNo for warehouse '".$whseID."' is not entered with proper format";
            $gErr->addIAError(
                'INV-0751', __FILE__ . ':' . __LINE__,
                "", [],
                $msg, ['LINE_NO' => $lineNo, 'WHSEID' => $whseID]
            );
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function ValidateStandardCost(&$values){
        $gErr = Globals::$g->gErr;

        $ok = true;
        $lineNo = $values['LINE_NO']+1;
        $whseID = $values['WAREHOUSEID'];
        $hasEffectiveStartdate = (isset($values['EFFECTIVE_START_DATE']) && $values['EFFECTIVE_START_DATE'] !='');
        $hasStandardCost = (isset($values['STANDARD_COST']) && $values['STANDARD_COST'] !='');

        // Standard Cost entered?
        if (!$hasStandardCost && $hasEffectiveStartdate) {
            $msg = "Standard cost in line $lineNo for warehouse '".$whseID."' is not entered.";
            $gErr->addIAError(
                'INV-0752', __FILE__ . ':' . __LINE__,
                "", [],
                $msg, ['LINE_NO' => $lineNo, 'WHSEID' => $whseID]
            );
            $ok = false;
        }

        // if Standard cost is negative
        if (is_numeric($values['STANDARD_COST']) && +$values['STANDARD_COST'] < 0) {
            $msg = "Item has a negative standard cost given in line $lineNo for warehouse '" .$whseID."'.".
                "Change the number to a non-negative, and try again.";
            $gErr->addIAError(
                'INV-0753', __FILE__ . ':' . __LINE__,
                $msg, ['LINE_NO' => $lineNo, 'WHSEID' => $whseID]
            );
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param string    $itemID
     * @param string    $whseID
     * @param string    $effectiveDate
     *
     * @return array[]
     */
    function GetByEffectiveStartDate($itemID, $whseID, $effectiveDate){
        $params = array(
            'selects' => array('RECORDNO', 'ITEMWHSEKEY', 'ITEMID', 'WAREHOUSEID', 'EFFECTIVE_START_DATE'),
            'filters' => array(array(
                array('ITEMID', '=', $itemID),
                array('WAREHOUSEID', '=', $whseID),
                array('EFFECTIVE_START_DATE', '=', $effectiveDate),
            )
            ),
        );

        $res = $this->GetList($params);
        $res = $res[0];

        return $res;
    }


}

