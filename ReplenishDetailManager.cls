<?php
/**
 * Manager file for the standard object replenishDetail
 *
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation All, Rights Reserved
 */


/**
 * replenishDetailManager Doc Comment
 *
 * @category  Cls
 * @package   Source/inventory
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation, All Rights Reserved
 */
class ReplenishDetailManager extends OwnedObjectManager
{
    const   OLD_DEMAND_FORECAST_ENGLISH = 'Demand forecast defined by statistical account'; // this was the old version that got saved in some early versions


    /**
     * Constructor
     *
     * @param array $params List of parameters for specific to this object
     */
    function __construct($params = array())
    {
        // we aren't a document, but we want document treatment for things like custom dimensions....
        $this->_docType = $params['TRANSACTION_DEFINITION'];    // enables magic in the entity manager :-(
        if ($this->_docType == '') {
            // we need SOME transaction definition in order to get custom dimensions.  If we didn't get one from the caller,
            // use the default one in preferences, if available.  If may not be the one we evenually use, but all we need
            // is SOME TD to get the custom dimensions :-(
            $inventoryPrefs = array();
            GetModulePreferences(Globals::$g->kINVid, $inventoryPrefs);
            $this->_docType = $inventoryPrefs['DEFAULT_PURCHASE_TRANSACTION'];
            $params['TRANSACTION_DEFINITION'] = $this->_docType;
        }

        parent::__construct($params);
    }



    /**
     * Get the doctype for this document.
     *  Note: well, this normally comes from a DocumentManager, which I don't inherit from,
     *      but I *do* have a doc type!
     *
     * @return  string
     */
    function getDocType()
    {
        return $this->_docType;
    }


    /**
     * Set the doctype here
     *
     * @param string  $docType
     */
    function setDocType($docType)
    {
        $this->_docType = $docType;
    }


    /**
     *  init Record - make an empty record to be filled in by clients.
     *              This takes care of the non-read-from-DB fields.
     *              Next - fill in from the DB and finally call finishDetailRecords() on the set.
     *              Then write to disk if you are saving the snapshot.
     *
     * @param int $replenishmentRecordNumber    the record number of the enclosing replenishment record, if one.
     * @param string $snapshotName              what is the name of the snapshot?  If none, make it the 'CURRENT' snapshot
     *
     * @return array
     */
    function initRecord($replenishmentRecordNumber = 0, $snapshotName = 'CURRENT')
    {
        $rtn = array();

        $rtn['RECORDNO']            = 0;
        $rtn['SUMMARY_RECORDNO']    = $replenishmentRecordNumber;
        $rtn['SNAPSHOT_NAME']       = $snapshotName;
        $rtn['INCLUDED']            = 'false';
        $rtn['WAREHOUSE_ITEM_GROUP'] = 0;
        $rtn['PROPOSED_PO']         = 0;

        return $rtn;
    }

    /**
     * @param string    $method     either the internal or external 'sales forecast method'
     *
     * @return string               the internal sales forecast method
     */
    public static function getInternalSalesForecastMethod($method)
    {
        if ($method == '') {
            $inventoryPrefs = array();
            GetModulePreferences(Globals::$g->kINVid, $inventoryPrefs);
            $method = $inventoryPrefs['FORECAST_METHOD'] ?? 'REORDER_POINT'; // default the answer if unspecified
            return $method;
        }

        ItemManager::getReplenishmentMethods($internal,$external);

        // Clients may pass us a sales forecast method in EITHER its UI form, OR its DB form,
        // depending on who it is.  Here, let's normalize to the DB form
        // See if it is in its UI form.  Otherwise leave it alone.
        // Note: since the external form can come from CSV or API, let's be case-insensitive
        $lMethod = strtolower($method);
        $key = array_search($lMethod, array_map('strtolower', $external));
        if ($key !== false) {
            $method = $internal[$key];
        } else {
            if ($lMethod == strtolower(self::OLD_DEMAND_FORECAST_ENGLISH)) {
                $method = 'FORECAST_TABLE';
            }
        }
        return $method;
    }

    /**
     * generateCalculatedFields - Several of the fields are the result of calculations.
     *                          This routine calculates those fields
     *
     * @param array $values a ReplenishDetail record
     *
     */
    function generateCalculatedFields(&$values)
    {
        // safety valves; these should be fine, but.....
        if ($values['ECONOMIC_ORDER_QTY'] <= 0) {
            $values['ECONOMIC_ORDER_QTY'] = 1;     // avoid div by zero
        }
        if ($values['CONVFACTOR'] <= 0) {
            $values['CONVFACTOR'] = 1.0;
        }
        if ($values['ITEM_CONVFACTOR'] <= 0) {
            $values['ITEM_CONVFACTOR'] = 1.0;
        }
        if ($values['EXCHANGE_RATE'] <= 0) {
            $values['EXCHANGE_RATE'] = 1.0;
        }

        // There are, unbelievably, TREE units of measure in play here!
        // $baseUnits   = 1.0;
        $itemUnits      = $values['ITEM_CONVFACTOR'];   // same for item/warehouse info
        $vendorUnits    = $values['CONVFACTOR'];
        $method         = $values['REPLENISHMENT_METHOD'] ?? '';
        if ($method == '') {
            $method = 'REORDER_POINT';
        } else {
            $method = self::getInternalSalesForecastMethod($method);
        }

        switch ($method) {
            case 'FORECAST_TABLE':
                $futureDemand = $values['FORECAST_TABLE'];  // already in base units
                break;

            case 'FORECAST_DEMAND':
                $futureDemand = $values['FORECAST_DEMAND_IN_LEAD_TIME'] * $vendorUnits;
                break;

            case 'REORDER_POINT':
                $futureDemand = $values['REORDER_POINT'] * $itemUnits;
                break;

            default:
                throw new Exception("Method '$method' is not a valid REPLENISHMENT_METHOD.");
                //$futureDemand = 0;
        }

        // Now construct fields that are calculated....

        // While the raw numbers are in various units of quantity, for now I want the calculated amounts all in BASE UNITS so we don't go insane.
        //  maybe for the UI folks will want non-base units, but ....

        // Base units already
        $values['CURRENT_NET_INVENTORY']    = iround(($values['CURRENT_ON_HAND']  ?? 0)
                                                          + ($values['CURRENT_ON_ORDER'] ?? 0)
                                                          - ($values['CURRENT_ON_HOLD']  ?? 0), 0);

        $t = $values['SAFETY_STOCK'] * $itemUnits; // now in base units
        $values['INVENTORY_NEED']           = iround($futureDemand + $t,0);

        // base units already
        if ($method == 'REORDER_POINT') {
            $values['FUTURE_ACTIVITY'] = 0; // Shilpa and Tom say we shouldn't consider these for reorder-point
        } else {
            $values['FUTURE_ACTIVITY'] = iround($values['FUTURE_PO'] + $values['FUTURE_OE'] + $values['FUTURE_IC'], 0);
        }

        // kit needs are in base units the rest are calculated above and therefore also in base units
        $values['NEED_TO_PURCHASE']         = iround($values['KIT_NEEDS'] + $values['INVENTORY_NEED'] - $values['FUTURE_ACTIVITY'] - $values['CURRENT_NET_INVENTORY'], 0);

        // Do we raise Need To Purchase to The Reorder Quantity ("Quantity to Reorder")
        $t = $values['REORDER_QTY'] * $itemUnits; // now in base units
        if (($method == 'REORDER_POINT') &&
            ($t                          > 0) &&
            ($values['NEED_TO_PURCHASE'] > 0) &&        // base units
            ($values['NEED_TO_PURCHASE'] < $t)) {
             $values['NEED_TO_PURCHASE'] = $t;   // order this many
        }

        if ($values['NEED_TO_PURCHASE'] > 0) {
            if ($values['MAX_ORDER_QTY'] > 0) {          // is in base units
                $t = $values['MAX_ORDER_QTY'] * $itemUnits; // now in base units
                if ($values['NEED_TO_PURCHASE'] > $t) {
                    $values['NEED_TO_PURCHASE'] = $t;
                }
            }
            $t = $values['ECONOMIC_ORDER_QTY'] * $vendorUnits;
            $values['ROUND_UP'] = ceil($values['NEED_TO_PURCHASE'] / $t);   // round UP

            $t2 = $values['MIN_ORDER'] * $vendorUnits;
            $values['QUANTITY_TO_PURCHASE'] = iround(max($t2, ($values['ROUND_UP'] * $t)), 0);

            // turn base units back into vendor units; how many of the UOM do we want?
            $values['QUANTITY_TO_PURCHASE'] = ceil($values['QUANTITY_TO_PURCHASE'] / $vendorUnits);
        } else {
            $values['QUANTITY_TO_PURCHASE'] = 0;
        }
        // Extended price is the unit cost * # of units, which is vendor units, which we just above set.....
        $values['EXTENDED_PRICE']           = 0.0;
        if (($values['QUANTITY_TO_PURCHASE'] > 0) && ($values['PURCHASE_PRICE'] > 0)) {
            $values['EXTENDED_PRICE'] = iround($values['QUANTITY_TO_PURCHASE'] * $values['PURCHASE_PRICE'], 4);
        }

        // Now put the price back into dollars or whatever your base amount is, if you use multi-currency
        $values['EXTENDED_PRICE_BASE']      = iround(  $values['EXTENDED_PRICE'] * $values['EXCHANGE_RATE'], 4);

        // The UI seems to hate numbers and wants strings.
        //  Ya, I know I shouldn't have to worry about that here...:
        $forceZeroWhenEmpty = array(
            'FORECAST_TABLE', 'FORECAST_DEMAND_IN_LEAD_TIME', 'LEAD_TIME',
            'CURRENT_ON_HAND', 'CURRENT_ON_ORDER',   'CURRENT_ON_HOLD', 'CURRENT_NET_INVENTORY',
            'SAFETY_STOCK', 'INVENTORY_NEED',
            'FUTURE_PO', 'FUTURE_OE', 'FUTURE_IC', 'FUTURE_ACTIVITY',
            'KIT_NEEDS', 'NEED_TO_PURCHASE',
            'REORDER_POINT', 'REORDER_QTY',
            'ECONOMIC_ORDER_QTY', 'ROUND_UP',
            'MIN_ORDER', 'QUANTITY_TO_PURCHASE',
            'PURCHASE_PRICE', 'EXTENDED_PRICE', 'EXTENDED_PRICE_BASE', 'EXCHANGE_RATE',
            'ITEM_CONVFACTOR', 'CONVFACTOR',
        );

        foreach ($forceZeroWhenEmpty as $n2s) {
            $values[$n2s] = strval($values[$n2s]);
            if ($values[$n2s] == '') {
                $values[$n2s] = '0';
            }
        }
        // logFL("DETAILS:" . var_export($values,true));
    }


    /**
     *  Override, and ignore, the platform relationships thrust upon us
     *
     * @param Pt_RelationshipDef $relDef
     * @param int|null $platformObjDefId
     */
    function addPlatformRelationshipField($relDef, $platformObjDefId = null)
    {
        // no, I don't want the relationships from podocentry, which happen
        // because of the
        //   'platform_entity' => 'podocumententry'
        // line in the .ent file (so we get custom dimensions)
    }


}

