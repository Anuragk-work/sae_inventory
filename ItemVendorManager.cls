<?

/***	FILE:
*	AUTHOR: John P. Campbell
*	DESCRIPTION:
*
*	(C) 2000, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/


class ItemVendorManager extends OwnedObjectManager
{
    /** @var int[] $defaultLeadTimes */
    private $defaultLeadTimes = null;


    /**
     *  get the DEFAULT_LEAD_TIME for a given vendor ID.
     *
     *  Here, we get them in bulk so it saves getting single DEFAULT_LEAD_TIMEs from vendors.
     *  When we read or write, we often read or write in a loop on behalf of a vendor
     *
     * @param string    $vendorID       the vendor ID
     *
     * @return int
     */
    public function getDefaultLeadTimes($vendorID)
    {
        list($ID) = explode('--', $vendorID);
        if ( ! isset($this->defaultLeadTimes)) {
            $qry   = [];
            $qry[] = "SELECT vendorid, default_lead_time FROM vendor where CNY#=:1";
            $qry[] = GetMyCompany();

            $result = QueryResult($qry);
            if ($result !== false) {
                foreach ($result as $record) {
                    $this->defaultLeadTimes[$record['VENDORID']] = (int)$record['DEFAULT_LEAD_TIME']; // force to int
                }
            }
        }
        return $this->defaultLeadTimes[$ID] ?? 0;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = true;
        // ok, here's a thing: apparently people are happy to pass in EMPTY vendor entries in the API.
        // but, the Item Manager fills in some fields (recordno, line_no, others), so I'm at a loss
        // how to insure that the ONLY thing they omitted was VENDORID.  Anyway, here, if they forget
        // the vendor id, ignore the record with no error :-(.  Note that for API 3.0 I handle this
        // much better in API_ValidateObject in ItemManager.  This is for 2.1 APIs :-(
        if (isset($values['VENDORID']) && ($values['VENDORID'] != '')) {
            $ok = $this->PrepValues($values);
            $ok = $ok && OwnedObjectManager::regularAdd($values);
        }
        return $ok ;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $ok = true;
        // ok, here's a thing: apparently people are happy to pass in EMPTY vendor entries in the API.
        // but, the Item Manager fills in some fields (recordno, line_no, others), so I'm at a loss
        // how to insure that the ONLY thing they omitted was VENDORID.  Anyway, here, if they forget
        // the vendor id, ignore the record with no error :-(.  Note that for API 3.0 I handle this
        // much better in API_ValidateObject in ItemManager.  This is for 2.1 APIs :-(
        if (isset($values['VENDORID']) && ($values['VENDORID'] != '')) {
            $ok = $this->PrepValues($values);
            $ok = $ok && parent::regularSet($values);
        }
        return $ok ;
    }

    /**
     * @param string     $ID
     * @param array      $fields
     *
     * @return array|bool
     */
    public function get($ID, $fields=null)
    {
        list($ID) = explode('--', $ID);
        $toreturn = parent::get($ID);

        if (is_array($toreturn)) {
            $toreturn['ECONOMIC_ORDER_QTY']  = $toreturn['ECONOMIC_ORDER_QTY'] ?? 1;
            $toreturn['MIN_ORDER_QTY']       = $toreturn['MIN_ORDER_QTY']      ?? 1;
            if ((int)$toreturn['LEAD_TIME'] == 0) {
                $toreturn['LEAD_TIME'] = $this->getDefaultLeadTimes($toreturn['VENDORID']); // maybe we're doing a get() in a loop for an item
            }
        }
        return $toreturn;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function PrepValues(&$values)
    {
        $ok = true;
        if (isset($values['LAST_COST'])) {
            $values['LAST_COST'] = preg_replace("/[^0-9.]/", "", $values['LAST_COST']);
        }

        if (isset($values['BEST_COST'])) {
            $values['BEST_COST'] = preg_replace("/[^0-9.]/", "", $values['BEST_COST']);
        }

        /* If UOMKEY is populated and ia::operation is set then query UOM unit and populate the UOM
           this is requried since uom key can be populated using REST.*/
        if (isset($values['UOMKEY']) && $values['UOMKEY'] !== null
            && $values['UOMKEY'] !== '' && isset($values['ia::operation'])) {
            $this->getUomFromKey($values);
        }

        if (ItemManager::isReplenishmentOn() && isset($values[':uomgrpkey'])) {     // set by the item when adding/setting
            if (!isset($values['UOM']) || ($values['UOM'] == '')) {
                $values['UOM'] = $values['DEFAULT_REPLENISHMENT_UOM'];  // set by the item manager when setting/adding records
            }
            $oldConvFactor = $values['CONVFACTOR'] ?? '';
            $values['CONVFACTOR'] = self::getConvFactorFromUOM($values['UOM'], $values[':uomgrpkey']);   // get the conversion factor for it
            if ($values['CONVFACTOR'] === false) {
                $ok = false;
            } else if (ItemManager::$fromAPI && ($oldConvFactor !== '') && ($oldConvFactor != $values['CONVFACTOR'])) {
                Globals::$g->gErr->addIAError(
                    'INV-0735', __FILE__.":".__LINE__,
                    "The CONVFACTOR is for your information only, and cannot be altered.  Using the CONVFACTOR of " . $values['CONVFACTOR'] . " for the units '" . $values['UOM'] . "'.",
                    ['CONVFACTOR' => $values['CONVFACTOR'], 'UOM' => $values['UOM']]
                );
                $ok = false;
            }
        }

        // Make sure only ONE record is preferred
        if (isset($values['PREFERRED_VENDOR']) && ($values['PREFERRED_VENDOR'] == 'true')) {
            $values['PREFERRED_VENDOR'] = 'true';
            // make sure no OTHER record has true...
            $company = GetMyCompany();
            $currentRecordNumber = $values['RECORDNO'] ?? ($values['RECORD#'] ?? 0);    // is there a current record number?
            $stmt = array();
            $stmt[0] = "SELECT record# FROM icitemvendor WHERE cny#=:1 AND PREFERRED_VENDOR = 'T' AND itemkey = :2 AND itemwhsekey IS NULL";
            $stmt[1] = $company;
            $stmt[2] = $values['ITEMID'];
            $res = QueryResult($stmt);
            if ($res !== false) {
                // In practice there will be zero or one of these.
                // Also, it is likely the record that exists with 'T' is this record being updated!
                foreach ($res as $recordToFlip) {
                    if ($recordToFlip['RECORD#'] != $currentRecordNumber) {
                        $stmt[0] = "UPDATE icitemvendor SET PREFERRED_VENDOR = 'F' WHERE cny#=:1 AND record# = :2";
                        $stmt[1] = $company;
                        $stmt[2] = $recordToFlip['RECORD#'];
                        QueryResult($stmt);
                    }
                }
            }
        }

        $ok = $ok && $this->validateValues($values);

        return $ok;
    }




    /**
     *  get UOM conv factor from the item id and the uom
     *  not found?  return FALSE
     *
     * @param string $uom
     * @param string $uomGroup
     *
     * @return float|bool
     */
    public static function getConvFactorFromUOM( $uom, $uomGroup )
    {
        // Cache these because, in practice, we only use a few.
        /** @var float[][][] $uomCache */
        static $uomCache = array();

        if ($uom == '') {
            return 1.0;     // no uom, lets default to 1 conversion factor
        }

        $company = GetMyCompany();  // static and called from other places.  Dan reccomended this to protect against certain scenarios

        if ( ! isset($cache[$company][$uom][$uomGroup])) {
            $stmt = array();
            $stmt[0] = "SELECT uom.convfactor
                        FROM   icuom uom
                        WHERE  uom.cny#=:1 AND uom.unit=:2 AND uom.grpkey=:3 ";
            $stmt[1] = $company;
            $stmt[2] = $uom;
            $stmt[3] = $uomGroup;
            $res = QueryResult($stmt);
            if (($res === false) || (count($res) == 0)) {
                $uomCache[$company][$uom][$uomGroup] = false; // bad uom, let the caller know
                Globals::$g->gErr->addIAError(
                    'INV-0736', __FILE__.":".__LINE__,
                    "The UOM of '$uom'' is not valid for this item.",
                    ['UOM' => $uom]
                );
            } else {
                $convfactor = (float)($res[0]['CONVFACTOR']);
                if ($convfactor == 0.0) {
                    $convfactor = 1.0;    // odd, but happens (0 isn't a valid value)
                }
                $uomCache[$company][$uom][$uomGroup] = $convfactor; // only expect one.....
            }
        }
        return $uomCache[$company][$uom][$uomGroup];
    }

    /**
     * @param array $values
     * @return void
     */
    private function getUomFromKey(&$values)
    {

        $company = GetMyCompany();  // static and called from other places.  Dan reccomended this to protect against certain scenarios

        $stmt = array();
        $stmt[0] = "SELECT uom.unit
                        FROM   icuom uom
                        WHERE  uom.cny#=:1 AND uom.record#=:2 AND uom.grpkey=:3 ";
        $stmt[1] = $company;
        $stmt[2] = $values['UOMKEY'];
        $stmt[3] = $values[':uomgrpkey'];
        $res = QueryResult($stmt);
        if (($res === false) || (Util::countOrZero($res) === 0)) {
            Globals::$g->gErr->addIAError(
                'INV-0736', __FILE__ . ":" . __LINE__,
                "The UOM of '$stmt[2]'' is not valid for this item.",
                ['UOM' => $stmt[2]]
            );
        } else {
            $values['UOM'] = $res[0]['UNIT'];
        }

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function validateValues(&$values)
    {
        $ok = true;

        $cantBeNegative = ['LEAD_TIME', 'FORECAST_DEMAND_IN_LEAD_TIME', 'ECONOMIC_ORDER_QTY', 'MIN_ORDER_QTY' ];
        foreach ($cantBeNegative as $notNegative) {
            if (isset($values[$notNegative])) {
                $values[$notNegative] = trim($values[$notNegative]);
                if (empty($values[$notNegative]) || ($values[$notNegative] == '')) {
                    unset($values[$notNegative]);
                } else {
                    if ($values[$notNegative] < 0) {
                        Globals::$g->gErr->addIAError(
                            'INV-0737', __FILE__ . ":" . __LINE__, "Field $notNegative cannot be negative",
                            ['FIELD' => $notNegative]
                        );
                        $ok = false;
                    }
                    if (!is_numeric($values[$notNegative]) || !is_integer(0 + $values[$notNegative])) {
                        Globals::$g->gErr->addIAError(
                            'INV-0738', __FILE__ . ":" . __LINE__,
                            "Field $notNegative must be a whole number",
                            ['NOT_NEGATIVE' => $notNegative]
                        );
                        $ok = false;
                    }
                }
            }
        }

        if (isset($values['ECONOMIC_ORDER_QTY']) && ($values['ECONOMIC_ORDER_QTY'] < 1)) {
            $values['ECONOMIC_ORDER_QTY'] = 1;
        }

        if (isset($values['MIN_ORDER_QTY']) && ($values['MIN_ORDER_QTY'] < 1)) {
            $values['MIN_ORDER_QTY'] = 1;
        }

        if ( isset($values['ITEMID']) ) {
            list($id) = explode('--', $values['ITEMID']);
            $values['ITEMID'] = $id;
        } else {
            Globals::$g->gErr->addIAError('INV-0203', __FILE__ . ":" . __LINE__, 'ITEM ID is missing', []);
            $ok = false;
        }

        // CSV import may read the combined ID--NAME format of fields; for convienience we split them here
        if (isset($values['VENDORID']) && ($values['VENDORID'] != '')) {
            list($id) = explode('--', $values['VENDORID']);
            $values['VENDORID'] = $id;

            if ((int)$values['LEAD_TIME'] == 0) {
                $values['LEAD_TIME'] = $this->getDefaultLeadTimes($values['VENDORID']); // get them all in one swoop; when we add we add them all!
            }

        }

        return $ok;
    }


}
