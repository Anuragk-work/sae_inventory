<?
/***	FILE:
 *	AUTHOR:         Roger Collins (rcollins@intacct.com)
 *	DESCRIPTION:    Manager for the item warehouse vendor table
 *
 *	(C) 2018, Intacct Corporation, All Rights Reserved
 *
 *	This document contains trade secret data that belongs to Intacct
 *	Corporation and is protected by the copyright laws.  Information
 *	herein may not be used, copied or disclosed in whole or in part
 *	without prior written consent from Intacct Corporation.
 */


class ItemWarehouseVendorManager extends OwnedObjectManager
{
    /** @var ItemVendorManager|null $itemVendorManager  */
    private $itemVendorManager = null;


    /**
     * Constructor
     *
     * @param string[]  $params List of parameters for specific to this object
     *
     */
    function __construct($params = array())
    {
        parent::__construct($params);

        $this->itemVendorManager = Globals::$g->gManagerFactory->getManager('itemvendor');
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
                $toreturn['LEAD_TIME'] = $this->itemVendorManager->getDefaultLeadTimes($toreturn['VENDORID']); // maybe we're doing a get() in a loop for an item
            }
        }
        return $toreturn;
    }

    /**
     * Validate the record
     *
     * @param array $values  the object values
     *
     * @return bool  true on success and false on failure
     */
    protected function ValidateRecord(&$values)
    {
        $ok = true;

        //I have to add this here because somehow for ItemWarehouseVendor, clearing a number field will leave the field as
        //empty when we get here and trip the NOT numeric check below. Also, this same check in ItemVendor works because it
        //doesn't have this issue.
        $cantBeNegative = ['LEAD_TIME', 'FORECAST_DEMAND_IN_LEAD_TIME', 'ECONOMIC_ORDER_QTY', 'MIN_ORDER_QTY' ];
        foreach ($cantBeNegative as $notNegative) {
            if (isset($values[$notNegative])) {
                $values[$notNegative] = trim($values[$notNegative]);
                if (empty($values[$notNegative]) || ($values[$notNegative] == '')) {
                    unset($values[$notNegative]);
                } else {
                    if ($values[$notNegative] < 0) {
                        Globals::$g->gErr->addIAError('INV-0754', __FILE__ . ":" . __LINE__, "Field $notNegative cannot be negative", ['FIELD' => $notNegative]);
                        $ok = false;
                    }
                    if (!is_numeric($values[$notNegative]) || !is_integer(0 + $values[$notNegative])) {
                        Globals::$g->gErr->addIAError(
                            'INV-0755',
                            __FILE__ . ":" . __LINE__,
                            "Field $notNegative must be a whole number" ,['NOT_NEGATIVE' => $notNegative]
                        );
                        $ok = false;
                    }
                }
            }
        }

        if ((int)$values['LEAD_TIME'] == 0) {
            $values['LEAD_TIME'] = $this->itemVendorManager->getDefaultLeadTimes($values['VENDORID']); // maybe we're doing a save() in a loop for an item
        }

        if ( ! isset($values['ITEMWHSEKEY'])) {
            // UI wouldn't do this, so this is an API or CSV error
            Globals::$g->gErr->addIAError('INV-0207', __FILE__ . ":" . __LINE__, 'Item / Warehouse key not specified', []);
            $ok = false;
        } else {

            // CSV import may read the combined ID--NAME format of fields; for convienience we split them here
            if (isset($values['VENDORID'])) {
                list($id) = explode('--', $values['VENDORID']);
                $values['VENDORID'] = $id;
            } else {
                Globals::$g->gErr->addIAError('INV-0208', __FILE__ . ":" . __LINE__, 'VENDOR ID is missing', []);
                $ok = false;
             }
        }

        if (isset($values['ITEMID'])) {         // they can pass it in, but it shouldn't go into the db
            unset($values['ITEMID']);
        }

        if (isset($values['WAREHOUSEID'])) {
            unset($values['WAREHOUSEID']);
        }

        if (isset($values['LAST_COST'])) {
            $values['LAST_COST'] = preg_replace("/[^0-9.]/", "", $values['LAST_COST']);
        }

        if (isset($values['BEST_COST'])) {
            $values['BEST_COST'] = preg_replace("/[^0-9.]/", "", $values['BEST_COST']);
        }

        if (isset($values[':uomgrpkey'])) {     // set by the item when adding/setting
            if (!isset($values['UOM']) || ($values['UOM'] == '')) {
                $values['UOM'] = $values['DEFAULT_REPLENISHMENT_UOM'];  // set by the item manager when setting/adding records
            }
            $oldConvFactor = $values['CONVFACTOR'] ?? '';
            $values['CONVFACTOR'] = ItemVendorManager::getConvFactorFromUOM($values['UOM'], $values[':uomgrpkey']);   // get the conversion factor for it
            if ($values['CONVFACTOR'] === false) {
                $ok = false;
            } else if (ItemManager::$fromAPI && ($oldConvFactor !== '') && ($oldConvFactor != $values['CONVFACTOR'])) {
                Globals::$g->gErr->addIAError(
                    'INV-0692', __FILE__.":".__LINE__,
                    "The CONVFACTOR is for your information only, and cannot be altered.  Using the CONVFACTOR of " . $values['CONVFACTOR'] . " for the units '" . $values['UOM'] . "'.",
                    ['CONVFACTOR' => $values['CONVFACTOR'], 'UOM' => $values['UOM']]
                );
                $ok = false;
            }
        }
        // Make sure only ONE record is preferred
        if ($ok && isset($values['PREFERRED_VENDOR']) && ($values['PREFERRED_VENDOR'] == 'true')) {
            // make sure no OTHER record has true...
            $company = GetMyCompany();
            $currentRecordNumber = $values['RECORDNO'] ?? ($values['RECORD#'] ?? 0);    // is there a current record number?
            $stmt = array();
            $stmt[0] = "SELECT record# FROM icitemvendor WHERE cny#=:1 AND PREFERRED_VENDOR = 'T' AND itemwhsekey = :2";
            $stmt[1] = $company;
            $stmt[2] = $values['ITEMWHSEKEY'];
            $res = QueryResult($stmt);
            if ($res !== false) {
                // In practice there will be zero or one of these.
                // Also, it is likely the record that exists with 'T' is this record being updated!
                foreach ($res as $recordToFlip) {
                    if ($recordToFlip['RECORD#'] != $currentRecordNumber) {
                        $stmt[0] = "UPDATE icitemvendor SET PREFERRED_VENDOR = 'F' WHERE cny#=:1 AND record# is :2";
                        $stmt[1] = $company;
                        $stmt[2] = $recordToFlip['RECORD#'];
                        QueryResult($stmt);
                    }
                }
            }
        }

        return $ok && parent::ValidateRecord($values);
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        // Turns out that the API interface has records that are ALMOST EMPTY.  They have an ITEMWHSEKEY, LINE_NO, and STATUS.
        // And nothing else.  Since these seem to happen, I don't want to crash here because the record "isn't valid".
        if ((count($values) <= 4) && ( ! isset($values['VENDORID']))) {   // are they trying to set values, just not the vendor?
            return true;    // don't save it, but don't complain
        }
        return parent::regularAdd($values);
    }
}
