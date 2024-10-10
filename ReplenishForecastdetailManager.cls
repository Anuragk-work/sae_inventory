<?php
/**
 * Manager file for the standard object replenishForecast
 *
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation All, Rights Reserved
 */


/**
 * @category  Cls
 * @package   Source/inventory
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation, All Rights Reserved
 */
class ReplenishForecastDetailManager extends OwnedObjectManager
{
    const       ADDING          = 0;
    const       UPDATING        = 1;
    const       ADD_OR_UPDATE   = 2;    // not sure if we want to add or to update (CSV import)
    const       ADD_UPDATE_FAIL = 3;    // can't add it or update it because of errors
    const       IGNORE          = 4;    // record is identical to what is on disk, don't bother to update.

    const       NO_WAREHOUSE    = '--';


    /** @var string[]|null $itemWarehouseCache   Warehouse IDs WITHIN the above item IDs that match the criteria for using this table. */
    private     $itemWarehouseCache = null;

    /** @var array|null  $replenishForecastTable   the exzisting table entries.  COULD GET BIG!  */
    private     $replenishForecastTable = null;     // indexed by recored #

    /** @var int[]|null  $forecastTableByItemWarehouse   item/warehouse --> record# for the above table  */
    private     $forecastTableByItemWarehouse = null;

    /**  @var array $UOMGroups  list of UOM Groups, indexed by UOM record# (because that's what the item table stores) */
    private     $UOMGroups = array();

    /** @var float[][]  $uomCache   the conversion factors for each UOM, cached */
    private     $uomCache = [];

    /** @var int $_appPrecision */
    private     $_appPrecision = 4;     // what precision do we put quantities into?

    /** @var array $errorMsg */
    private $errorMsg = null;     // what precision do we put quantities into?

    /** @var array $check4dup */
    private $check4dup = null;     // what precision do we put quantities into?


    /**
     * @param array $params List of parameters for specific to this object
     */
    function __construct($params = array())
    {
        parent::__construct($params);

        GetModulePreferences( Globals::$g->kPOid, $prefs);  // use PO prefs, what is the precision
        if (isset($prefs['ITEMPRECISION']) && ($prefs['ITEMPRECISION'] > $this->_appPrecision )) {  // is it at least some reasonable amount?
            $this->_appPrecision = $prefs['ITEMPRECISION'];
        }

        $this->getUOMGroups();
        $this->createErrorMessages();
    }


    private function createErrorMessages()
    {
        $this->errorMsg =
            [
                'notenabled'         =>
                    [
                        'number'                  => 'INV-0866',
                        'description1'            => 'Replenishment not enabled.',
                        'description2'            => 'Replenishment must be enabled in your inventory control configuration to use fluctuating demand forecasts.',
                        'correction'              => 'Check your configuration and try again.',
                        'description1Placeholder' => [],
                        'description2Placeholder' => [],
                        'correctionPlaceholder'   => [],
                    ],
                'Invalid_item'       =>
                    [
                        'number'       => 'INV-0867',
                        'description1' => 'Invalid item or replenishment method',
                        'description2' => 'The item ID ($itemID) is not valid for this operation. When a warehouse is not specified, the replenishment method for the item must be \'Demand forecast by fluctuating values\'.',
                        'correction'   => 'Check your item and try again.',
                        'description1Placeholder' => [],
                        'description2Placeholder' => ['ITEM_ID' => $itemID],
                        'correctionPlaceholder'   => [],
                    ],
                'record_nonexistant' =>
                    [
                        'number'       => 'INV-0868',
                        'description1' => 'Record number does not exist',
                        'description2' => 'The record number you supplied ($recordNo) does not exist.',
                        'correction'   => 'Check the record number and try again.',
                        'description1Placeholder' => [],
                        'description2Placeholder' => ['RECORD_NO' => $recordNo],
                        'correctionPlaceholder'   => [],
                    ],
                'duplicate'          =>
                    [
                        'number'       => 'INV-0869',
                        'description1' => ' Duplicates are not allowed',
                        'description2' => 'The record you are attempting to create or update would cause a duplicate of an existing record ($recordNo). Uniqueness is determined by the combination of Effective Date, Item ID, and Warehouse ID.',
                        'correction'   => 'Check your inputs and try again.',
                        'description1Placeholder' => [],
                        'description2Placeholder' => ['RECORD_NO' => $recordNo],
                        'correctionPlaceholder'   => [],
                    ],
                'could_not_identify' =>
                    [
                        'number'       => 'INV-0870',
                        'description1' => 'Could not identify the record to update',
                        'description2' => 'When updating a record, provide either a record number or an Effective Date, Item ID, and Warehouse ID combination that matches an existing record.',
                        'correction'   => ' Check your inputs and try again.',
                        'description1Placeholder' => [],
                        'description2Placeholder' => [],
                        'correctionPlaceholder'   => [],
                    ],
                'norecordno_on_add'  =>
                    [
                        'number'       => 'INV-0871',
                        'description1' => 'On an ADD, you cannot specify a RECORDNO.',
                        'description2' => '',
                        'correction'   => '',
                        'description1Placeholder' => [],
                        'description2Placeholder' => [],
                        'correctionPlaceholder'   => [],
                    ],

                'duplicate_date' =>
                    [
                        'number'       => 'INV-0872',
                        'description1' => 'duplicate forecast entry.  ',
                        'description2' => 'date ($date) and warehouse ($warehouse) must be unique.',
                        'correction'   => 'change duplicate entry',
                        'description1Placeholder' => [],
                        'description2Placeholder' => ['DATE' => $date, 'WAREHOUSE' => $warehouse],
                        'correctionPlaceholder'   => [],
                    ],
//                'errorid' =>
//                    [
//                        'number'       => 'BL03000018',
//                        'description1' => 'xxx',
//                        'description2' => 'xxx',
//                        'correction'   => 'xxx',
//                    ],

        ];
    }

    /**
     *  get UOM Groups - get the entire list of unit-of-measure groups.
     *  Relax!  There are only a handful of these....
     */
    private function getUOMGroups()
    {
        // I want to know the UOM Groups for display, get ALL of those (there are only a handfull)...
        $stmt = array();
        $stmt[0] = "SELECT grp.record#, grp.name, uom.unit, uom.convfactor
                        FROM icuomgrp grp, icuom uom 
                        WHERE grp.cny#=:1 and uom.cny#=:1 AND grp.podefunitkey=uom.record# ";
        $stmt[1] = GetMyCompany();
        $res     = QueryResult($stmt);
        if ($res !== false) {
            foreach ($res as $uomgroup) {
                $this->UOMGroups[$uomgroup['RECORD#']] = array('NAME' => $uomgroup['NAME'], 'DEFAULT_UNIT' => $uomgroup['UNIT'], 'CONVFACTOR' => $uomgroup['CONVFACTOR'],);
            }
        }
    }





    /**
     *  get conversion factor for UOM
     *
     * @param string $uom
     * @param string $uomGroupKey
     *
     * @return float
     */
    private function getConvFactorFromUOM($uom, $uomGroupKey)
    {
        // Cache these because, in practice, we only use a few.
        if ( ! isset($this->uomCache[$uom][$uomGroupKey])) {
            $qry = "SELECT uom.convfactor FROM   icuom uom  WHERE  uom.cny#=:1 AND uom.unit=:2 AND uom.grpkey=:3 ";
            $stmt = [ $qry, GetMyCompany(),$uom, $uomGroupKey ];

            $res = QueryResult($stmt);
            if ($res !== false) {
                $convfactor = (float)($res[0]['CONVFACTOR']);
                if ($convfactor == 0.0) {
                    $convfactor = 1.0;    // odd, but happens (0 isn't a valid value)
                }
            } else {
                $convfactor = 1.0;  // well, default to SOMETHING valid.
            }
            $this->uomCache[$uom][$uomGroupKey] = $convfactor;
        }
        return $this->uomCache[$uom][$uomGroupKey];
    }


    /**
     *
     * @param string $errorText the text of the error message
     * @param string[] $record if the error is for a record, you can include that here
     * @return string
     */

    private function getErrorText($errorText, $record = null, &$placeholderText = '')
    {
        $line = '';
        $placeholderText = '';
        if (($record != null) && isset($record['ROW']))
        {
            $line = "On row " . $record['ROW'] . ": ";
            $placeholderText = I18N::getSingleToken('IA.ON_ROW_RECORD_ROW',[
                ['name'=> 'RECORD_ROW', 'value' => $record['ROW']]
            ]);
        }
        return ($line . $errorText);
    }

    /**
     * @param string $errorid
     * @param string $source
     * @param array $replace
     */
    private function addErrorbyId($errorid, $source = '', $replace = [])
    {
        $errmsg = $this->errorMsg[$errorid];
        $description1 = '';
        $description2 = '';
        $correction = '';
        $number = '';
        $description1Placeholder = [];
        $description2Placeholder = [];
        $correctionPlaceholder = [];

        if (!is_null($errmsg))
        {
            $number = $errmsg['number'];
            $source = $errmsg['source'];
            $description1 = $errmsg['description1'];
            $description2 = $errmsg['description2'];
            $correction = $errmsg['correction'];
            $description1Placeholder = $errmsg['description1Placeholder'];
            $description2Placeholder = $errmsg['description2Placeholder'];
            $correctionPlaceholder = $errmsg['correctionPlaceholder'];

            // replace any matching data in string
            $matchval = [];
            $replaceval = [];
            foreach ($replace as $key => $data)
            {
                $matchval[] = $key;
                $replaceval[] = $data;
            }
            $description1 = str_replace($matchval, $replaceval, $description1);
            $description2 = str_replace($matchval, $replaceval, $description2);
            $correction = str_replace($matchval, $replaceval, $correction);
        }

        Globals::$g->gErr->addIAError(
            $number, $source,
            $description1, $description1Placeholder,
            $description2, $description2Placeholder,
            $correction, $correctionPlaceholder
        ); //TODO:i18N-INV-Error-Message (code change review)
    }


    /**
     *      Check to see if replenishment is on and the feature is included
     *
     * @return bool
     */
    private function validateReplenihsmentIsOn()
    {
        // If replenishment is not enabled, we can't do anything for this customer.....
        if  ( ! ItemManager::isReplenishmentOn()) {
            $this->addErrorbyId('notenabled', __FILE__ . ":" . __LINE__);
            return false;
        }
        return true;
    }


    /**
     * beforeUpdateEntries
     *
     * @param string             $path           the path of the owned object
     * @param OwnedObjectManager &$lineManager   line item manager object
     * @param int                $parentKey      parent record number
     * @param array              &$values        new values
     * @param array              &$oldRecNumbers existing record numbers
     *
     * @return bool
     */
    protected function beforeUpdateEntries($path, &$lineManager, &$parentKey, &$values, &$oldRecNumbers)
    {
        $ok = parent::beforeUpdateEntries($path, $lineManager, $parentKey, $values, $oldRecNumbers);
        $this->check4dup = [];
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok          = true;
        $addOrUpdate = $this->validate($values, self::ADDING);
        if ($addOrUpdate == self::ADDING) {
            $ok = parent::regularAdd($values);
        } else if ($addOrUpdate != self::IGNORE) {  // do we ignore this?
            $ok = false;
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
        $ok          = true;
        $addOrUpdate = $this->validate($values, self::UPDATING);
        if ($addOrUpdate == self::UPDATING) {
            $ok = parent::regularSet($values);
        } else if ($addOrUpdate != self::IGNORE) {  // do we ignore this?
            $ok = false;
        }
        return $ok;
    }

    /**
     * @param int|string $id
     *
     * @return bool
     */
    function delete($id)
    {
        parent::Delete($id);

        return true;
    }

    /**
     *      This non-standard entry point is for the CSV import, where you may have a large CSV
     *      of entries, some already added, some new.  So.... we try to figure out what you did.
     *
     * @param array $values
     *
     * @return bool
     */
    function AddOrUpdate(&$values)
    {
        $ok = true;
        $addOrUpdate = $this->validate($values, self::ADD_OR_UPDATE);
        switch ($addOrUpdate) {
            case self::UPDATING:
                $ok = parent::regularSet($values);
                break;

            case self::ADDING:
                $ok = parent::regularAdd($values);
                break;

            case self::IGNORE:   // ignore the record, return true (no errors, just nothing to do)
                break;

            default:
                $ok = false;
                break;
        }
        return $ok;
    }

    /**
     *  Given a single forecast record, convert the quantity in the record from BASE UNITS to the Item's Replenishment Default UOM
     *
     * @param array $record
     *
     * @return float|string
     */
    private function quantityForRecord($record)
    {
        $warehouse = $record['WAREHOUSEID'] ?? '';
        $warehouse = ($warehouse != '') ? $warehouse : self::NO_WAREHOUSE;
        $key = $record['ITEMID'] . ':' . $warehouse;

        $conversion = $this->itemWarehouseCache[$key] ?? 1.0;           // I assume it DOES exist, but just in case
        $conversion = ($conversion !== false) ? $conversion : 1.0;      // and, again, if something goes wrong (like someone turned OFF replenishment when there were existing records?)

        return iround( $record['QUANTITY'] / $conversion, $this->_appPrecision );
    }


    /**
     *  The quantity field is in BASE UNITS on the sql table.  But clients want to see them as Replenishment Default Units,
     *      which varies from item to item.
     *
     * @param array $records
     *
     * @return array
     */
    private function convertQuantityFields($records)
    {
        if (($records !== false) && count($records)) {               // not an error, and there IS an array here?

            $this->fetchExistingRecords(false); // false means don't read the entire Replenish Forecast table, just item/warehouse records

            // Did we get passed an array of records, or a single record?
            if (isset($records[0])) {
                foreach ($records as &$record) {
                    $record['QUANTITY'] = $this->quantityForRecord($record);
                }
            } else {
                $records['QUANTITY'] = $this->quantityForRecord($records);  // exactly one record, not an array of records
            }
        }
        return $records;
    }


    /**
     *  Override of Entity Manager get(), here just to make sure you don't attempt this on files NOT using Replenishment.
     *
     * @param string     $ID
     * @param array      $fields
     *
     * @return array|bool
     */
    function get($ID, $fields=null)
    {
        if ($this->validateReplenihsmentIsOn()) {
            return $this->convertQuantityFields(parent::get($ID, $fields));
        }
        return false;   // no record to be gotten
    }


    /**
     *  Override of Entity Manager GetList(), here just to make sure you don't attempt this on files NOT using Replenishment.
     *
     * @param array $queryParams
     * @param bool $_crosscny
     * @param bool $nocount
     * @return array list of objects matching the query
     */
    function GetList($queryParams = [], $_crosscny = false, $nocount = true)
    {
        if ($this->validateReplenihsmentIsOn())
        {
            return $this->convertQuantityFields(parent::GetList($queryParams , $_crosscny, $nocount));
        }
        return [];
    }


    /**
     *   fetchExistingRecords  cache items with the right kind of replenishment setting, and their warehouses.
     *          This is faster than fetching each item/warehouse one-at-a-time, and we assume folks will use
     *          CSV or some such to add/update the records in bulk.
     *
     *  Note: this is called both for READS and for WRITES.  For READS we just need the item conversion factors so
     *          we can present the QUANTITY in item Replenishment Unit Of Measures.  For WRITES we also want to get
     *          the existing table into ram (ouch!) to verify updates/adds
     *
     * @param bool $getExistingForecastTable        Should we read all the existing forecast records into the replenishForecastTable cache?
     */
    private function fetchExistingRecords($getExistingForecastTable)
    {
        // Get the list of existing records.  Once.
        if ($getExistingForecastTable && ($this->replenishForecastTable === null)) {
            $this->replenishForecastTable = [];
            $stmt = array();
            // TODO: Do we want to only recognize records within a week or two ago?  Then how do we validate recordno?
            //      otherwise there could be thousands of records....
            $stmt[0] = "SELECT record#, itemid, warehouseid, effectivedate, quantity FROM replenishforecast WHERE cny#=:1";
            $stmt[1] = GetMyCompany();

            $res = QueryResult($stmt);
            if ($res !== false) {
                foreach ($res as $entry) {
                    $this->replenishForecastTable[$entry['RECORD#']] = $entry;
                    $key =  $entry['ITEMID'] . ':' . ($entry['WAREHOUSEID'] ?? self::NO_WAREHOUSE);
                    $this->forecastTableByItemWarehouse[$key][$entry['EFFECTIVEDATE']] = $entry['RECORD#'];
                }
            }
        }

        // If the item cache has not been set up yet, do so now.
        if ($this->itemWarehouseCache === null) {
            $this->itemWarehouseCache = [];
            $stmt = array();
            $stmt[0] = "SELECT itemid, default_unit_of_measure, uomgrpkey as uomgroupkey FROM icitem WHERE cny#=:1 AND enable_replenishment='T' AND sales_forecast_method='FORECAST_TABLE'";
            $stmt[1] = GetMyCompany();

            $res = QueryResult($stmt);
            if ($res !== false) {
                foreach ($res as $item) {
                    if ( ! isset($item['DEFAULT_UNIT_OF_MEASURE'])) {
                        $item['DEFAULT_UNIT_OF_MEASURE'] = $this->UOMGroups[$item['UOMGROUPKEY']]['DEFAULT_UNIT'];
                    }
                    $conversionFactor = $this->getConvFactorFromUOM( $item['DEFAULT_UNIT_OF_MEASURE'], $item['UOMGROUPKEY'] );

                    $this->itemWarehouseCache[$item['ITEMID'] . ':' . self::NO_WAREHOUSE] = $conversionFactor; // this item supports the forecast table
                }
            }

            // now, we want item/warehouses that want FORECAST_TABLE,
            // AND we want item/warehouses that DON'T want FORECAST_TABLE, on those items that DO want FORECAST_TABLE.
            // In other words, we want to know if an item/warehouse combo supports FORECAST_TABLE or not.
            $stmt[0] = "SELECT icitemwhse.itemkey, icitemwhse.warehousekey, icitemwhse.sales_forecast_method, icitem.default_unit_of_measure, icitem.uomgrpkey as uomgroupkey FROM icitemwhse, icitem 
                        WHERE icitemwhse.cny#=:1 
                        AND   icitem.cny#=:1 
                        AND   icitemwhse.itemkey = icitem.itemid
                        AND   icitemwhse.enable_replenishment='T' 
                        AND   icitem.enable_replenishment='T' 
                        AND ( icitem.sales_forecast_method='FORECAST_TABLE' OR  icitemwhse.sales_forecast_method='FORECAST_TABLE')";   // we don't care what the item's method is

            $res = QueryResult($stmt);
            if ($res !== false) {
                foreach ($res as $itemWhse) {
                    if ( ! isset($itemWhse['DEFAULT_UNIT_OF_MEASURE'])) {
                        $itemWhse['DEFAULT_UNIT_OF_MEASURE'] = $this->UOMGroups[$itemWhse['UOMGROUPKEY']]['DEFAULT_UNIT'];
                    }
                    $conversionFactor = $this->getConvFactorFromUOM( $itemWhse['DEFAULT_UNIT_OF_MEASURE'], $itemWhse['UOMGROUPKEY'] );

                    $key = $itemWhse['ITEMKEY'] . ':' . $itemWhse['WAREHOUSEKEY'];
                    $ok = ($itemWhse['SALES_FORECAST_METHOD'] == 'FORECAST_TABLE');
                    $this->itemWarehouseCache[$key] = ($ok ? $conversionFactor : false) ; // this item/warehouse supports the forecast table (or not)
                }
            }
        }
    }


    /**
     * @param array $values
     * @param int   $addOrUpdate  are we adding, updating, or a little of both?
     *
     * @return int
     */
    function validate(&$values, $addOrUpdate)
    {
        $ok = $this->validateReplenihsmentIsOn();
        if (!$ok)
        {
            return self::ADD_UPDATE_FAIL;
        }

        $this->fetchExistingRecords(true); // true means 'get existing records too'

        // check item and warehouse ids
        // we can have an item with no warehouse; that applies to all warehouses not otherwise specified.
        // otherwise, we need a warehouse id that meets our criteria....
        $itemID = '';
        $key = '';
        $conversionFactor = 1.0;
        $quantityIsInBaseUnits = false;

        $recordNo = (int)($values['RECORDNO'] ?? 0);  // did they specify a record number?

        // If a record number was specified then we have some default values we can provide
        if (($recordNo > 0) && isset($this->replenishForecastTable[$recordNo]))
        {
            $existing = $this->replenishForecastTable[$recordNo];
            if (!isset($values['ITEMID']) || (trim($values['ITEMID']) == ''))
            {
                $values['ITEMID'] = $existing['ITEMID'];
            }
            if (!isset($values['WAREHOUSEID']) || (trim($values['WAREHOUSEID']) == ''))
            {
                $values['WAREHOUSEID'] = $existing['WAREHOUSEID'];
            }
            if (!isset($values['EFFECTIVEDATE']) || (trim($values['EFFECTIVEDATE']) == ''))
            {
                $values['EFFECTIVEDATE'] = $existing['EFFECTIVEDATE'];
            }
            if (!isset($values['QUANTITY']) || (trim($values['QUANTITY']) == ''))
            {
                $values['QUANTITY'] = $existing['QUANTITY'];
                $quantityIsInBaseUnits = true;
            }
        }

       if (isset($values['ITEMID']) && (trim($values['ITEMID']) != '')) {
           $itemID = $values['ITEMID'];
           if (isset($values['WAREHOUSEID']) && (trim($values['WAREHOUSEID']) != '')) {
               $warehouseID = $values['WAREHOUSEID'];
               $key = $itemID . ':' . $warehouseID;
           } else {
               $key = $values['ITEMID']. ':' . self::NO_WAREHOUSE;
           }
       } else {
           $this->addErrorbyId('Invalid_item', __FILE__.":".__LINE__, ['$itemID' => $values['ITEMID']]);
           $ok = false;
       }

        // check if this is an empty line

        if (
            (!isset($values['WAREHOUSE']) || (trim($values['WAREHOUSE']) == ''))
            &&
            (!isset($values['EFFECTIVEDATE']) || (trim($values['EFFECTIVEDATE']) == ''))
            &&
            (!isset($values['QUANTITY']) || (trim($values['QUANTITY']) == ''))
        )
        {
            // empty record
            $addOrUpdate = self::IGNORE;    // nothing to do
        }
        else
        {

            // add warehouse id if needed
            list($warehouseID) = explode('--', $values['WAREHOUSE']);
            $values['WAREHOUSEID'] = $values['WAREHOUSEID'] ?: $warehouseID;

            // do I need to check the EFFECTIVEDATE date?
            if (!isset($values['EFFECTIVEDATE']) || (trim($values['EFFECTIVEDATE']) == ''))
            {
                $msg = $this->getErrorText("Enter a valid date in the 'Effective Date' field.", $values, $placeholderText);
                Globals::$g->gErr->addIAError('INV-0873', __FILE__ . ":" . __LINE__, $msg, ['ROW_TEXT' => $placeholderText]);
                //TODO:i18N-INV-Error-Message (code change review)
                $ok = false;
            }

            // check the quantity field
            $badQuantity = false;
            if (isset($values['QUANTITY']) && (trim($values['QUANTITY']) != ''))
            {
                if ((!is_numeric($values['QUANTITY'])) || ($values['QUANTITY'] < 0))
                {
                    $badQuantity = true;
                }
                else
                {
                    if ($quantityIsInBaseUnits == false)
                    {
                        $values['QUANTITY'] *= $conversionFactor;   // so ONE DOZEN becomes 12
                    }
                }
            }
            else
            {
                $badQuantity = true;
            }
            if ($badQuantity)
            {
                $msg = $this->getErrorText("Enter 0 or a positive number in the 'Quantity' field.", $values, $placeholderText);
                Globals::$g->gErr->addIAError('INV-0874', __FILE__ . ":" . __LINE__, $msg, ['ROW_TEXT' => $placeholderText]);
                //TODO:i18N-INV-Error-Message (code change review)
                $ok = false;
            }

            if ($ok)
            {
                $recordNoStored = $this->forecastTableByItemWarehouse[$key][$values['EFFECTIVEDATE']] ?? 0; // is this an ADD or an UPDATE?

                if ($recordNo != 0)
                {
                    if ($addOrUpdate == self::ADDING)
                    {
                        $this->addErrorbyId('norecordno_on_add', __FILE__ . ":" . __LINE__);
                        $ok = false;
                    }
                    else
                    {
                        if (!isset($this->replenishForecastTable[$recordNo]))
                        {
                            $this->addErrorbyId('record_nonexistant', __FILE__ . ":" . __LINE__, ['$recordNo' => $recordNo]);
                            $ok = false;
                        }
                        else
                        {
                            if (($recordNoStored != 0) && ($recordNoStored != $recordNo))
                            {
                                $this->addErrorbyId('duplicate', __FILE__ . ":" . __LINE__, ['$recordNo' => $recordNo]);
                                $ok = false;
                            }
                            else
                            {
                                if ($ok)
                                {
                                    $addOrUpdate = self::UPDATING;  // so if it was add-or-update, it is now an update
                                    if (($this->replenishForecastTable[$recordNo]['ITEMID'] == $itemID) && ($this->replenishForecastTable[$recordNo]['WAREHOUSEID'] == $warehouseID)
                                        && ($this->replenishForecastTable[$recordNo]['EFFECTIVEDATE'] == $values['EFFECTIVEDATE']) && ($this->replenishForecastTable[$recordNo]['QUANTITY'] == $values['QUANTITY']))
                                    {
                                        $addOrUpdate = self::IGNORE;    // oh, nothing to do
                                    }
                                }
                            }
                        }
                    }
                }
                else
                {
                    if ($addOrUpdate == self::ADDING)
                    {  // no record# on update or add, so look for the record
                        if ($recordNoStored != 0)
                        {             // this is the record, I hope (well, it is a dup and they didn't specify a record#, so....)
                            $this->addErrorbyId('duplicate', __FILE__ . ":" . __LINE__, ['$recordNo' => $recordNo]);
                            $ok = false;
                        }
                    }
                    else
                    { // it is UPDATE or ADD_OR_UPDATE
                        if ($recordNoStored == 0)
                        {
                            if ($addOrUpdate == self::UPDATING)
                            {
                                $this->addErrorbyId('could_not_identify', __FILE__ . ":" . __LINE__);
                                $ok = false;
                            }
                            else
                            {
                                $addOrUpdate = self::ADDING;  // was ADD_OR_UPDATE but it is now an add
                            }
                        }
                        else
                        {
                            $values['RECORDNO'] = $recordNoStored;      // as if they'd specified it
                            $addOrUpdate = self::UPDATING;       // so it is now an update
                            if ($this->replenishForecastTable[$recordNoStored]['QUANTITY'] == $values['QUANTITY'])
                            {    // we know item/warehouse/effectivedate match
                                $addOrUpdate = self::IGNORE;    // nothing to do
                            }
                        }
                    }
                }
            }

            $itemid2 = $values['ITEMID'];
            $date2 = $values['EFFECTIVEDATE'];
            list($warehouseid2) = explode('--', $values['WAREHOUSEID']);
//            list($warehouseid2) = explode('--', $values['WAREHOUSE']);
            $date_id = '--' .$itemid2 . '--' . $date2 . '--' . $warehouseid2 . '--';
            if (is_null($this->check4dup[$date_id]))
            {
                // not found
                $this->check4dup[$date_id] = true;
            }
            else
            {
                // dup
                    $addOrUpdate = self::ADD_UPDATE_FAIL;
                    $ok = false;
                    $this->addErrorbyId('duplicate_date', __FILE__ . ":" . __LINE__, ['$date' => $date2, '$warehouse' => $warehouseid2]);
            }
        }


        if (!$ok)
        {
            $addOrUpdate = self::ADD_UPDATE_FAIL;
        }
        return $addOrUpdate;
    }

    /**
     * Applies post processing to the Custom Report query results
     *
     * @param CustomReport $customReport the custom report object currently running
     * @param string[][]   &$rawdata Raw access data as read from DB, will be modified with dynamic content.
     */
    public function postProcessCustomReportResults($customReport, &$rawdata)
    {
        // custom reports change the names of all the fields from whatever they are to names like 'C0' and 'C1' and so on.
        // so we need to get the field ALIAS' to see what we have to work with.
        // NOTE: we need the ITEMID, WAREHOUSEID, and QUANTITY to do our job.
        $fieldAliases = $customReport->nexusDB->GetAllFieldAlias();
        if (isset($fieldAliases['REPLENISHFORECAST.QUANTITY'], $fieldAliases['REPLENISHFORECAST.ITEMID'], $fieldAliases['REPLENISHFORECAST.WAREHOUSEID']) && count($rawdata))
        {

            $this->fetchExistingRecords(false); // false means don't read the entire Replenish Forecast table, just item/warehouse records

            $aliasForQuantity = $fieldAliases['REPLENISHFORECAST.QUANTITY'];   // like 'C4' or something
            $aliasForItem = $fieldAliases['REPLENISHFORECAST.ITEMID'];
            $aliasForWarehouse = $fieldAliases['REPLENISHFORECAST.WAREHOUSEID'];

            foreach ($rawdata as &$row)
            {
                $phoneyRecord['QUANTITY'] = $row[$aliasForQuantity];
                $phoneyRecord['ITEMID'] = $row[$aliasForItem];
                $phoneyRecord['WAREHOUSEID'] = $row[$aliasForWarehouse] ?? '';    // this one can be null
                $row[$aliasForQuantity] = $this->quantityForRecord($phoneyRecord);
            }
        }
    }

    /**
     *      compare proc for usort()  compare by item, then warehouse, then effective date
     *
     * @param string[] $left
     * @param string[] $right
     *
     * @return int
     */
    protected static function compareIWE($left,$right)
    {
        $rtn = strcmp($left['ITEMID'], $right['ITEMID']);
        if ($rtn == 0) {
            $leftWH  = $left[ 'WAREHOUSEID'] ?? '';     // warehouse is optional and so can be null
            $rightWH = $right['WAREHOUSEID'] ?? '';
            $rtn = strcmp($leftWH, $rightWH);
            if ($rtn == 0) {
                $leftDate  = $left['EFFECTIVEDATE'];
                $rightDate = $right['EFFECTIVEDATE'];
                // date compares are slow, cache the date format change:
                static $dateCache = [];
                if ( ! isset($dateCache[$leftDate])) {
                    $dateCache[$leftDate] = ReformatDate($leftDate, IADATE_SYSFORMAT, '/Ymd');
                }
                if ( ! isset($dateCache[$rightDate])) {
                    $dateCache[$rightDate] = ReformatDate($rightDate, IADATE_SYSFORMAT, '/Ymd');
                }

                $rtn = strcmp($dateCache[$leftDate], $dateCache[$rightDate]);
            }
        }
        return $rtn;
    }

    /**
     *      build a table in CSV format of the table.
     *
     *  Note: this is preliminary, and likely will eventually have filter information passed in....
     *
     * @return string
     */
    public function exportTableAsCSV()
    {
        $fields = [
            'ITEMID',
            'WAREHOUSEID',
            'EFFECTIVEDATE',
            'QUANTITY',
            'RECORDNO',
        ];

        $rtn = implode( ",", $fields) . "\n";  // put out top row in order;
        $table = $this->GetList(
            [
                'selects' => $fields,
            ]
        );
        if ($table !== false) {
            // sort by ITEM, WAREHOUSE, EFFECTIVE date
            usort( $table, 'ReplenishForecastdetailManager::compareIWE' );
            foreach ($table as $row) {
                foreach ($fields as $field) {
                    $row[$field] = $row[$field] ?? "";
                    $rtn .= $this->escapeForCSV($row[$field]) . ',';
                }
                $rtn .= "\n";
            }
        }
        return $rtn;
    }

    /**
     * @param string $itemid
     * @return string
     */
    public function exportItemAsCSV($itemid)
    {
        $fields = [
            'ITEMID',
            'WAREHOUSEID',
            'EFFECTIVEDATE',
            'QUANTITY',
            'FORECASTNAME',
        ];

        $rtn = implode(",", $fields) . "\n";  // put out top row in order;
        $table = $this->GetList(
            [
                'selects' => $fields,
                'filters' => [[['ITEMID', 'in', [$itemid]]]]
            ]
        );

        if ($table !== false)
        {
            // sort by ITEM, WAREHOUSE, EFFECTIVE date
            usort($table, 'ReplenishForecastdetailManager::compareIWE');
            foreach ($table as $row)
            {
                foreach ($fields as $field)
                {
                    $row[$field] = $row[$field] ?? "";
                    $rtn .= $this->escapeForCSV($row[$field]) . ',';
                }
                $rtn .= "\n";
            }
        }
        return $rtn;
    }


    /**
     * fputcsv() demands a file, addslashes() doesn't do what I want.
     *  Excel and Google Docs use "" around strings with commas, and escape " with " before it ("")
     *
     * @param bool|string $s
     *
     * @return string
     */
    private function escapeForCSV($s)
    {
        $rtn = str_replace('"', '""', $s);    // escape double quotes
        if ((strpos($rtn, '"') !== false) || (strpos($rtn, ',') !== false)) { // if any double quotes or commas; could check for newlines, but in practice we won't see those
            $rtn = '"' . $rtn . '"';
        }
        return $rtn;
    }



    }

