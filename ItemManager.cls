<?php /** @noinspection ArgumentEqualsDefaultValueInspection */
/** @noinspection NestedPositiveIfStatementsInspection */
//===========================================================================
//	FILE: ItemManager.cls
//	AUTHOR: John P. Campbell
//	DESCRIPTION:
//
//	(C) 2000, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	Corporation and is protected by the copyright laws.  Information
//	herein may not be used, copied or disclosed in whole or in part
//	without prior written consent from Intacct Corporation.
//===========================================================================
require_once 'scm_util.inc';
require_once 'Util_DataRecordFormatter.cls';

define("INVENTORY", 'Inventory');
define("NONINV", 'Non-Inventory');
define("NONINV_PO", 'Non-Inventory (Purchase only)');
define("NONINV_SO", 'Non-Inventory (Sales only)');
define("KIT", 'Kit');
define("STOCKABLE_KIT", 'Stockable Kit');
define("COMPONENT", 'Component Level');
define("KITLEV", 'Kit Level');

define('DEFAULT_INVPRECISION', 2);

/**
 * Class ItemManager
 */
class ItemManager extends DimensionManager
{
    const AVERAGE_COST_DECIMALS = 10;
    const BASEUNITPRECISION = 10;

    //Represents the qty min/max for base price entry when it gets created
    const BASEPRICEENTRY_QTYLIMITMIN_ITEMMGR = '1'; //Need to be consistent with invpricelistentry.cqry
    const BASEPRICEENTRY_QTYLIMITMAX_ITEMMGR = '9999999999'; //Need to be consistent with invpricelistentry.cqry
    const BASEPRICEENTRY_QTYLIMITMIN_IMPORT = '0'; //Need to be consistent with csv_import_pricelist.cls
    const BASEPRICEENTRY_QTYLIMITMAX_IMPORT = '999999'; //Need to be consistent with csv_import_pricelist.cls

    /** @var array $itemCache */
    var $itemCache = array();


    /** @var bool $isAdvancedSetup */
    var $isAdvancedSetup = false;

    /** @var int  $_appPrecision */
    var $_appPrecision;

    /** @var array $_items */
    var $_items = array();

    /** @var array $_warehouse */
    var $_warehouse = array();

    /** @var array $warehouseCache */
    static $warehouseCache = [];        // to avoid looking up warehouses over and over

    /** @var array $_itemsqty */
    var $_itemsqty;

    /** @var int[]|null $firstEmptyPreferredVendor */
    private $firstEmptyPreferredVendor = null;        // we need to capture this info before we merge with existing data (on an update)

    /** @var bool $fromAPI */
    public static $fromAPI = false;

    const DEFAULT_UOM_PRECISION = '4';
    const DEFAULT_CONV_FACTOR = '1';

    /** @var array $stdCostCache */
    var $stdCostCache = array();

    /* @var bool $isInventoryIntalled */
    protected $isInventoryIntalled;

    /* @var bool $isShipDatesEnabled */
    protected $isAutoPrintLabelEnabled;

    /** @var bool $isFulfillmentPrefEnabled */
    var $isFulfillmentPrefEnabled;

    /** @var array $fulfillmentItemTypes */
    var $fulfillmentItemTypes;

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
        //For the AutoPrintlabel configuration, we have added this perticular code.
        $kINVid = Globals::$g->kINVid;
        $this->isInventoryIntalled = IsInstalled($kINVid);
        $this->isAutoPrintLabelEnabled =(GetPreferenceForProperty($kINVid, 'ENABLEAUTOPRINTLABEL') == 'T') ? true : false;
        $this->isFulfillmentPrefEnabled = (GetPreferenceForProperty($kINVid, 'ENABLEFULFILLMENT') == 'T') ? true : false;
        $this->fulfillmentItemTypes = [ NONINV, NONINV_SO ];
    }


    /**
     *  Is Supply Inventory enabled?
     *
     * @return bool|null
     *
     */
    public static function isSuppliesInventoryEnabled()
    {
        static $enabled = null;

        if ($enabled === null) {    // this has not been called yet
            $enabled = false;
            if (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_SUPPLIESINV_FEATURE')) {
                $enabled = (GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLESUPPLIESINVENTORY') === 'T') ? true : false;
            }
        }
        return $enabled;
    }

    /**
     *  Is item currently being used in a transaction? True if yes, false otherwise.
     *
     * @param array $itemId - the item id to check if being used in a transaction
     *
     * @return bool - true if used, false otherwise
     *
     */
    public static function isItemInUseOnTxn($itemId)
    {
        $result = QueryResult(["SELECT count(1) count FROM docentrymst WHERE cny#=:1 AND itemkey=:2", GetMyCompany(), $itemId]);
        $itemInUseOnTxn = ($result && $result[0]['COUNT'] === '0')? false : true;
        return $itemInUseOnTxn;
    }


    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Add(&$values)
    {
        self::$fromAPI = true;
        return parent::API_Add($values);
    }

    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Set(&$values)
    {
        self::$fromAPI = true;
        return parent::API_Set($values);
    }

    /**
     * Prepares the LANDEDCOSTINFO structure if landed cost is enabled and the structure doesn't exist
     *
     * @param array $values
     */
    private function PrepValuesForLandedCost(&$values)
    {
        if ($values['ENABLELANDEDCOST'] == 'true' && $values['LANDEDCOSTINFO'] == null && in_array($values['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT))) {
            $values['LANDEDCOSTINFO'] = array();
            $uomMgr = Globals::$g->gManagerFactory->getManager('uom');
            $uoms = array();

            $filter = array(
                'selects' => array('NAME', 'UOMDETAIL.UNIT'),
                'filters' => array(
                    array(
                        array('NAME', 'IN', ItemLandedCostManager::LANDEDCOSTMETHODS),
                        array('UOMDETAIL.ISBASE', '=', 'true')
                    )
                )
            );
            $result = $uomMgr->GetList($filter);

            foreach ($result as $res) {
                $uoms[$res['NAME']] = $res['UOMDETAIL.UNIT'];
            }

            foreach (ItemLandedCostManager::LANDEDCOSTMETHODS as $method) {

                if ($method == 'Value') {
                    continue;
                }

                if ($uoms[$method]) {
                    $cnt = count($values['LANDEDCOSTINFO']);
                    $values['LANDEDCOSTINFO'][$cnt]['METHOD'] = $method;
                    $values['LANDEDCOSTINFO'][$cnt]['METHODUOM'] = $uoms[$method];
                    $values['LANDEDCOSTINFO'][$cnt]['ACTIVE'] = 'false';
                }
            }
        }
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function PrepValues(&$values)
    {
        global $gManagerFactory, $gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        //$gErr = Globals::$g->gErr;

        $ok = true;

        $this->isAdvancedSetup = IsAdvancedConfiguration();

        $values = $this->PrepDefaultValues($values);

        if (!isset($values['ITEMID']) || $values['ITEMID']=='') {
            $msg = "Required field Item ID is missing.";
            $gErr->addIAError('INV-1101', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        if (!isset($values['NAME']) || $values['NAME']=='') {
            $msg = "Required field 'Name' is missing.";
            $gErr->addIAError('INV-1102', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        // Check for MRR value
        // TODO: Was this meant as an error check?
        //if (isset($values['MRR'])) {
        //    ($values['MRR']) ? true : false;
        //}

        // if item type is kit we are defaulting cost method as 'Standard'
        $arr1 = array(NONINV, NONINV_PO, NONINV_SO, KIT, STOCKABLE_KIT);

        if ( in_array($values['ITEMTYPE'], $arr1) ) {

            // Costmethod is FIFO for stkits and Std for non-inv items/kits
            if ($values['ITEMTYPE']==STOCKABLE_KIT) {
                $values['COST_METHOD'] = 'FIFO';
            } else {
                $values['COST_METHOD'] = 'Standard';

                // if fulfilment is not enabled for above mentioned type of items
                // then unset warehouseinfo as its not required.
                $fulfillmentEnabled = $this->isFulfillmentEnabled($values);

                $warehouseInfoRequired = $values['ITEMTYPE'] == STOCKABLE_KIT || $fulfillmentEnabled;
                if ( isset($values['WAREHOUSE_INFO']) && !$warehouseInfoRequired) {
                    unset($values['WAREHOUSE_INFO']);
                }
            }

            if ( $values['ITEMTYPE'] == NONINV_SO ) {
                if ( isset($values['VENDOR_INFO']) ) {
                    if (self::$fromAPI) {
                        $gErr->addIAError(
                            'INV-0171', __FILE__ . ":" . __LINE__, "Non-inventory items cannot add or set vendors into an item.", []);
                    }
                    unset($values['VENDOR_INFO']);
                }
            }
        }

        if ( !in_array($values['ITEMTYPE'], array(KIT, STOCKABLE_KIT)) ) {
            unset($values['COMPONENT_INFO']);
        }

        // while uploading CSV file if the Item Type is not specified
        if ($values['ITEMTYPE']=='') {
            $values['ITEMTYPE'] = INVENTORY;
        }

        $dropShipPref = GetPreferenceForProperty(Globals::$g->kSOid, 'DROPSHIPENABLE');
        if (
            (
                $dropShipPref != 'T'
                || ($values['ITEMTYPE'] != INVENTORY
                    && $values['ITEMTYPE'] != NONINV
                    && $values['ITEMTYPE'] != STOCKABLE_KIT
                )
            )
            && $values['DROPSHIP'] == 'true'
        ) {
            $msg = "Drop ship is not allowed for this item.";
            $gErr->addIAError('INV-1103', __FILE__ . ':' . __LINE__, $msg, [], 'Remove Drop ship field.', []);
            $ok = false;
        }

        $btoPref = GetPreferenceForProperty(Globals::$g->kSOid, 'BUYTOORDERENABLE');
        if (
            (
                $btoPref != 'T'
                || ($values['ITEMTYPE'] != INVENTORY
                    && $values['ITEMTYPE'] != NONINV
                    && $values['ITEMTYPE'] != STOCKABLE_KIT
                )
            )
            && $values['BUYTOORDER'] == 'true'
        ) {
            $msg = "'Buy to order' is not allowed for this item.";
            $gErr->addIAError('INV-1104', __FILE__ . ':' . __LINE__, $msg, [], 'Remove buy to order field.', []);
            $ok = false;
        }

        $landedcostPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLELANDEDCOST');
        if ($landedcostPref == 'T' && $values['ENABLELANDEDCOST'] == 'true') {
            if (
                $values['ITEMTYPE'] != INVENTORY
                && $values['ITEMTYPE'] != NONINV
                && $values['ITEMTYPE'] != NONINV_PO
                && $values['ITEMTYPE'] != STOCKABLE_KIT
            ) {
                $msg = "Allocating landed cost is not allowed for this item.";
                $gErr->addIAError(
                    'INV-1105', __FILE__ . ':' . __LINE__, $msg, [], 'Remove enable landed cost field.', []
                );
                $ok = false;
            }

            if (
                $values['ITEMTYPE'] == NONINV
                && $values['ITEMTYPE'] == NONINV_PO
            ) {
                $values['LANDEDCOSTINFO'] = array();
            } else {
                //Populate the landed cost info if landed cost is enabled and the structure isn't there
                $this->PrepValuesForLandedCost($values);
                // validate Landed Cost entries - this is needed for REST API
                $ok = $this->validateValuesForLandedCost($values);

                if (is_array($values['LANDEDCOSTINFO'])) {
                    foreach ($values['LANDEDCOSTINFO'] as &$landedCostInfo) {
                        if ($landedCostInfo['METHOD'] == $values['UOMGRP']) {
                            $landedCostInfo['VALUE'] = 1;
                        }
                    }
                }
            }

        } else {
            $values['ENABLELANDEDCOST'] = 'false';
            $values['LANDEDCOSTINFO'] = array();
        }

        // check for duplicate upc value
        if( $values['UPC'] != '' ) {
            $upcvalue = $values['UPC'];
            $qry = 'QRY_ITEM_GET_UPC';
            $args = array ($upcvalue, $values['ITEMID']);
            $upc = $this->DoQuery($qry, $args);

            if ($upc[0]) {
                $dupitem = $upc[0]['ITEMID'];
                $msg = "UPC '$upcvalue'  is already assigned to the item '$dupitem'";
                $gErr->addIAError(
                    'INV-1106',
                    __FILE__ . ':' . __LINE__,
                    $msg, [ 'UPCVALUE' => $upcvalue, 'DUPITEM' => $dupitem],
                    '', [],
                    'Use a unique value instead.',[]
                );
                $ok=false;
            }
        }

        if (isset($values['AVERAGE_COST']) ) {
            $values['AVERAGE_COST'] = preg_replace("/[^0-9.]/", "", $values['AVERAGE_COST']);
        }

        $ok = $ok && $this->AddItemGLGrpValues($values);

        if ($ok && $values['TAXGROUP']['NAME']) {
            $tgMgr = $gManagerFactory->getManager('taxgroup');
            $raw = $tgMgr->GetRaw($values['TAXGROUP']['NAME']);
            $ok = isset($raw[0]);
            if (!$ok) {
                $msg = "Invalid Value Provided for Tax Group!";
                $gErr->addIAError('INV-1107', __FILE__ . ':' . __LINE__, $msg, []);
                /** @noinspection PhpUndefinedVariableInspection */
                epp("$source: Error: $msg");
            }
            $values[':taxgroupkey'] = $raw[0]['RECORD#'];

        } else if ($ok && $values['TAXGROUP']['NAME'] == '') {
            $values[':taxgroupkey'] = null;
        }

        if (!$values['PRODUCTTYPE'] || $values['PRODUCTTYPE'] == '') {
            $values['PRODUCTTYPE'] = 'Item for Resale';
        }

        //unset kit component info for 'Inventory type' items.
        if ($values['ITEMTYPE']==INVENTORY) {
            unset($values['COMPONENT_INFO']);
        }

        $ok = $ok && $this->ValidateSerializedItem($values);

        if ($values['UOMGRP']) {
            $uomMgr = $gManagerFactory->getManager('uom');
            $raw = $uomMgr->GetRaw($values['UOMGRP']);
            //$ok = isset($raw[0]);
            $values[':uomgrpkey'] = $raw[0]['RECORD#'];
        }

        if (!isset($values[':uomgrpkey']) || $values[':uomgrpkey'] == '') {
            $msg = "Could not find a UOM Group to associate with this item";
            $gErr->addIAError('INV-1108', __FILE__ . ':' . __LINE__, $msg, [], 'Please select a UOM Group or select a default UOM group in the Inventory Setup.', []);
            return false;
        }

        if (isset($values['ITEMTYPE']) && ($values['ITEMTYPE'] == KIT || $values['ITEMTYPE'] == 'K' || $values['ITEMTYPE'] == STOCKABLE_KIT || $values['ITEMTYPE'] == 'SK')) {
            $ok = $ok && $this->ValidateKitTypeItem($values);
            if (!$ok) {
                return false;
            }
        }
        // For REST API we need to validate fields populated and
        // unset the fields if they are unnecessary. We dont need to do this for XML API
        if(!self::$fromAPI) {
            $this->validateFieldsForREST($values);
        }

        //  for fulfillment
        $ok = $ok && $this->validateFulfillmentInfo($values);

        $itemtype = $values['ITEMTYPE'];
        $fulfillmentEnabled = $this->isFulfillmentEnabled($values);
        //
        if ( in_array($itemtype, [ INVENTORY, KIT, STOCKABLE_KIT ]) || $fulfillmentEnabled ) {
            if ((float)$values['STANDARD_COST'] < 0 ) {
                $msg = "Item has a negative standard cost. " .
                    "Change the number to a non-negative, and try again.";
                $gErr->addIAError('INV-1109', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }
            if ((float)$values['BASEPRICE'] < 0 ) {
                $msg = "Item has a negative base price. " .
                    "Change the number to a non-negative, and try again.";
                $gErr->addIAError('INV-1110', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }

            $ok = $ok && $this->ValidateWarehouseInfo($values);
        }

        $ok = $ok && $this->ValidateItemTermValues($values);

        $ok = $ok && $this->validateItemCrossReferences($values);

        $ok = $ok && $this->validateItemAttributes($values);

        //  Saving the default Renewal Macro for the Item.
        if($values['RENEWALMACROID']!='') {
            $ok = $ok && $this->ValidateItemRenewalInfo($values);
        }else {
            unset($values['RENEWALMACROKEY']);
        }

        $IsBinTrackEnabled = $this->EnableBin();

        if ($IsBinTrackEnabled!='T' && $values['ENABLE_BINS']=='T') {
            $gErr->addIAError(
                'INV-0172', __FILE__.":".__LINE__, "You can not upload an item with Bin tracking enabled because your company does
                            not have this feature enabled.  If you wish to upload this item with this
                            functionality on you must first update your company settings.  Otherwise,
                            please modify your file and remove " . '"T"' ." in Enable Bin column.", []
            );
            $ok =  false;
        }

        if ($values['ENABLE_BINS']=='T' && $values['COST_METHOD']=='LIFO' && $values['ITEMTYPE']!='Stockable Kit') {
            $msg  = "Invalid cost method for item " .$values['ITEMID'].". "."We do not support aisle, row, bin, and expiration tracking for LIFO cost methods items.";
            $actionMsg = "You must choose a different cost method to use this functionality.";
            $gErr->addIAError(
                'INV-1141',
                __FILE__ . ':' . __LINE__,
                $msg, [ 'VALUES_ITEMID' => $values['ITEMID'] ],
                "", [],
                $actionMsg,[]
            );

            $ok = false;
        }

        //while uploading CSV file if the enable bin is 'T/F' make it 'true/false'.
        if ($values['ENABLE_BINS']=='T') {
            $values['ENABLE_BINS'] = 'true';
        }

        if ($values['ENABLE_BINS']=='F') {
            $values['ENABLE_BINS'] = 'false';
        }

        if( $values['REQUEST_ORIGINATOR'] == 'SFORCE' ) {
            $this->_substatecache['NO_IMS_SFORCE_DELIVERY'] = true;
        }

        $ok = $ok && $this->translateTemplates($values);

        // tell the vendors about the item's group key
        if (isset($values['VENDOR_INFO'])) {    // internal version, not the external version
            foreach ($values['VENDOR_INFO'] as &$vendor) {
                $vendor[':uomgrpkey']                = $values[':uomgrpkey'];
                $vendor['DEFAULT_REPLENISHMENT_UOM'] = $values['DEFAULT_REPLENISHMENT_UOM'];
            }
        }
        if (isset($values['WAREHOUSE_INFO'])) {
            foreach ($values['WAREHOUSE_INFO'] as $key => $wInfo) {
                if (isset($wInfo['ITEMWAREHOUSEVENDORENTRIES'])) {
                    foreach ($values['WAREHOUSE_INFO'][$key]['ITEMWAREHOUSEVENDORENTRIES'] as &$vendor) {
                        $vendor[':uomgrpkey']                = $values[':uomgrpkey'];
                        $vendor['DEFAULT_REPLENISHMENT_UOM'] = $values['DEFAULT_REPLENISHMENT_UOM'];
                    }
                }
            }
        }

        //Based on the configuration (Integrated scanner product in use),
        // unset the Auto Print Label for the item.
        if ( !$this->isInventoryIntalled || !$this->isAutoPrintLabelEnabled ){
            $values['AUTOPRINTLABEL'] = 'false';
        }

        //Multiple Item tax grp validations for Mutitax companies
        if (TaxSetupManager::isMultiTaxJurisdictionConfigured() && IsRoot()
            && $values['ALLOWMULTIPLETAXGRPS'] === 'true') {
            //If multiple tax groups is enabled, dont allow header tax group
            if (!empty($values['TAXGROUP']['NAME'])) {
                $msg = "The option for multiple item tax groups is enabled.";
                $actionMsg = "Remove the item tax group name for the header and map a tax solution to an item tax group.";
                $gErr->addIAError('INV-1111', __FILE__ . ':' . __LINE__, $msg, [], $actionMsg, []); //i18N::TODO - (Input from File owner (Invalid error code ))
                $ok = false;
            }

            //Dont allow empty tax group map
            $taxGrpMaps = $values['MULTIPLEITEMTAXGROUPS'];
            if ($ok && empty($taxGrpMaps)) {
                $msg = "The option for multiple item tax groups is enabled.";
                $actionMsg = "Map one or more valid item tax groups.";
                $gErr->addIAError('INV-1112', __FILE__ . ':' . __LINE__, $msg, [], $actionMsg, []); //i18N::TODO - (Input from File owner (Invalid error code ))
                $ok = false;
            }

            //Validate multiple tax group map values
            if ($ok && !empty($taxGrpMaps)) {
                //For API set itemid value for each map object
                foreach ($values['MULTIPLEITEMTAXGROUPS'] as &$itemTaxGrpMap) {
                    if (empty($itemTaxGrpMap['ITEMID'])) {
                        $itemTaxGrpMap['ITEMID'] = $values['ITEMID'];
                    }
                }

                //Check for invalid Itemid value of each map object
                $itemids = array_unique(array_column($values['MULTIPLEITEMTAXGROUPS'], 'ITEMID'));
                if (!empty($itemids)) {
                    if (!empty(array_diff($itemids, [$values['ITEMID']]))) {
                        $msg = "Invalid Item Id entered in Item tax group map";
                        $actionMsg = "Please enter valid Item Id in Item Tax group map";
                        $gErr->addIAError('INV-1113', __FILE__ . ':' . __LINE__, $msg, [], $actionMsg, []); //i18N::TODO - (Input from File owner (Invalid error code ))
                        $ok = false;
                    }
                }

                $taxGrps = array_unique(array_column(array_column($values['MULTIPLEITEMTAXGROUPS'], 'TAXGROUP'), 'NAME'));
                $taxGrpMngr = Globals::$g->gManagerFactory->getManager('itemtaxgroup');
                $filter = [
                    'selects' => array('RECORDNO', 'NAME', 'TAXSOLUTIONID'),
                    'filters' => array(array(array('NAME', 'IN', $taxGrps)))
                ];
                $taxgrpResult = $taxGrpMngr->GetList($filter);

                //Check for invalid taxgroup value of each map object
                $invalidTaxGrps = array_values(array_diff($taxGrps, array_column($taxgrpResult, 'NAME')));
                if (!empty($invalidTaxGrps)) {
                    $invTaxGrp = implode(", ", $invalidTaxGrps);
                    $msg = "Item tax groups " .  $invTaxGrp . " are invalid.";
                    $actionMsg = "Enter valid item tax groups in the mapping.";
                    $gErr->addIAError(
                        'INV-1114',
                        __FILE__ . ':' . __LINE__,
                        $msg,[ 'INVALID_TAX_GRPS' => $invTaxGrp ],
                        "", [],
                        $actionMsg,[]
                    );  //i18N::TODO - (Input from File owner (Invalid error code ))
                    $ok = false;
                }

                //Check for duplicate taxgroup map for a tax solution
                $taxSolns = array_column($taxgrpResult, 'TAXSOLUTIONID');
                if (count($taxSolns) > count(array_unique($taxSolns))) {
                    $msg = "Map only one item tax group for each tax solution.";
                    $gErr->addIAError('INV-1115', __FILE__ . ':' . __LINE__, $msg, []);
                    $ok = false;
                } //i18N::TODO - (Input from File owner (Invalid error code ))

                //Validate for duplicate item tax group
                $allTaxGrps = array_column(array_column($values['MULTIPLEITEMTAXGROUPS'], 'TAXGROUP'), 'NAME');
                if (count($allTaxGrps) > count($taxGrps)) {
                    $msg = "Map a unique item tax group for each tax solution.";
                    $gErr->addIAError('INV-1116', __FILE__ . ':' . __LINE__, $msg, []);//i18N::TODO - (Input from File owner (Invalid error code ))
                    $ok = false;
                }

                //Set taxgroupkey for each map object
                $taxgrpMap = [];
                if (!empty($taxgrpResult)) {
                    foreach ($taxgrpResult as $taxgrp) {
                        $taxgrpMap[$taxgrp['NAME']] = $taxgrp['RECORDNO'];
                    }
                    foreach ($values['MULTIPLEITEMTAXGROUPS'] as &$taxGroup) {
                        $taxGroup['TAXGROUPKEY'] = $taxgrpMap[$taxGroup['TAXGROUP']['NAME']];
                    }
                }
            }
        } else {
            //Allow multiple tax group is allowed only for Multi tax company at root level
            if ($values['ALLOWMULTIPLETAXGRPS'] === 'true') {
                $msg = "Your configuration does not support multiple item tax groups.";
                $actionMsg = "Omit the parameter.";
                $gErr->addIAError('INV-1117', __FILE__ . ':' . __LINE__, $msg, [], $actionMsg, []); //i18N::TODO - (Input from File owner (Invalid error code ))
                $ok = false;
            } else {
                //If multiple tax groups is disabled, dont allow multiple tax groups
                if (!empty($values['MULTIPLEITEMTAXGROUPS'])) {
                    $msg = "The option for multiple item tax groups is not enabled and you entered multiple item tax groups.";
                    $actionMsg = "Either enable the option for multiple item tax groups or enter only one item tax group for the header.";
                    $gErr->addIAError('INV-1118', __FILE__ . ':' . __LINE__, $msg, [], $actionMsg, []); //i18N::TODO - (Input from File owner (Invalid error code ))
                    $ok = false;
                }
            }
            //If multiple tax groups is disabled, remove multiple tax groups
            unset($values['MULTIPLEITEMTAXGROUPS']);
        }
        
        $ok = $ok && $this->validateEnableForContract($values);

        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    private function ValidateWarehouseInfo(&$values){
        $gErr = Globals::$g->gErr;

        $ok = true;
        $duplicateWhseID = array();
        $wLineNo = 1;
        $itemtype = $values['ITEMTYPE'];

        $fulfillmentEnabled = $this->isFulfillmentEnabled($values);
        $isInventoryItem = (in_array($itemtype, array(INVENTORY, KIT, STOCKABLE_KIT)) || $fulfillmentEnabled);

        if (!empty($values['WAREHOUSE_INFO'])) {
            foreach ($values['WAREHOUSE_INFO'] as &$warehouseInfo) {
                if ($itemtype == STOCKABLE_KIT) {
                    if ((float)$warehouseInfo['STANDARD_COST'] < 0) {
                        $msg = "Item has a negative standard cost given in warehouse '" . $warehouseInfo['WAREHOUSEID'] . "'." .
                            "Change the number to a non-negative, and try again.";
                        $gErr->addIAError('INV-1119', __FILE__ . ':' . __LINE__, $msg, [ 'WAREHOUSE_INFO_WAREHOUSEID' => $warehouseInfo['WAREHOUSEID']]);
                        $ok = false;
                        break;
                    }
                }

                // check for duplicate warehouseid
                // Duplicate effective start date in entries?
                if ($warehouseInfo['WAREHOUSEID'] != '') {
                    if ($duplicateWhseID[$warehouseInfo['WAREHOUSEID']]) {
                        $msg = "Duplicate Warehouse in line $wLineNo '" . $warehouseInfo['WAREHOUSEID'] . "'";
                        $gErr->addIAError(
                            'INV-1142',
                            __FILE__ . ':' . __LINE__,
                            "", [],
                            $msg , [ 'W_LINE_NO' => $wLineNo, 'WAREHOUSE_INFO_WAREHOUSEID' => $warehouseInfo['WAREHOUSEID']]
                        );
                        $ok = false;
                        break;
                    } else {
                        $duplicateWhseID[$warehouseInfo['WAREHOUSEID']] = 1;
                    }
                }

                $warehouseInfo['IS_INVENTORY_ITEM'] = $isInventoryItem;

                if($ok && $this->validateWarehouseStdCostEntries($warehouseInfo, $values)){
                    $ok = $ok && $this->PrepWarehouseStdCostEntries($warehouseInfo, $values);
                }


                $wLineNo++;
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function validateItemCrossReferences(&$values)
    {
        $ok     = true;
        $itemID = $values['ITEMID'];

        if (isset(   $values['ITEMCROSSREFERENCES']) &&
            is_array($values['ITEMCROSSREFERENCES']) &&
            ! empty( $values['ITEMCROSSREFERENCES'])) {
            foreach ($values['ITEMCROSSREFERENCES'] as &$crossRef) {
                if (empty($crossRef['ITEMID'])) {
                    $crossRef['ITEMID'] = $itemID;
                }
            }
        } else if (($values['ITEMCROSSREFERENCES_EXISTED'] ?? false) === true) {
            // There WERE item cross references but now there are not any.
            // This happens when the user deletes the cros refferences on the UI.
            // If we do nothing here, the EntityManager assumes we never read the
            //  ITEMCROSREFERENCES, and so does not delete the exiting ones.
            // If this flag is not set or false, we don't delete anything...

            $itemCrossReff = Globals::$g->gManagerFactory->getManager('itemcrossref');
            $ok = $itemCrossReff->deleteByParent($values['RECORDNO'], DELETE_FOR_DELETE);
        }
        return $ok;
    }

    /**
     * @param array $itemInfo
     *
     * @return bool
     */
    public function isFulfillmentEnabled($itemInfo)
    {
        // fulfilment can be set to true or false only for Non-Inventory or Non-Inventory(Sales only) type items
        // if fulfilment is not enabled for above mentioned type of items
        // then unset warehouseinfo as its not required. TODO test for all item types
        $fulfillmentEnabled = in_array($itemInfo['ITEMTYPE'], $this->fulfillmentItemTypes)
            && $itemInfo['ENABLEFULFILLMENT'] === 'true'
            && $this->isFulfillmentPrefEnabled;

        return $fulfillmentEnabled;
    }

    /**
     * @param array $warehouseInfo
     * @param array $itemInfo
     *
     * @return bool
     */
    private function validateWarehouseStdCostEntries(&$warehouseInfo, $itemInfo)
    {
        $gErr = Globals::$g->gErr;

        $ok = true;
        $fulfillmentEnabled = $this->isFulfillmentEnabled($itemInfo);
        // is item type Inventory or Fulfillment item
        $isInvType = ( $itemInfo['ITEMTYPE'] == INVENTORY || $fulfillmentEnabled );
        // is cost method Standard ?
        $isStdCostType = $itemInfo['COST_METHOD'] == 'Standard';

        $isWhseStdCostEntriesRequired = $isInvType && $isStdCostType;

        foreach ( ( ( $warehouseInfo['STDCOSTENTRIES'] ) ?? [] ) as $costEntry ) {
            $stdCostDetails = $costEntry['EFFECTIVE_START_DATE'] . $costEntry['STANDARD_COST'];
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $hasStdCostData = strlen($stdCostDetails) > 0;

        if ( ! $isWhseStdCostEntriesRequired ) {
            // from XML & CSV there might be cost entries data submitted accidentally.
            // if there is any cost entries data provided throw error. This is system requirement.
            if ( isset($warehouseInfo['STDCOSTENTRIES']) ) {
                if ( $hasStdCostData ) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    /**$msg1 =
                    ! $isInvType && strlen($msg1) == 0 ? _("Item is not Inventory type or not a fulfillment item.")
                    : "";
                    $msg1 = ! $isStdCostType && strlen($msg1) == 0
                    ? "Item cost method is not Standard or not a fulfillment item." : ""; */
                    $msg1 ="Unable to save item information because standard cost entries were specified for one or more warehouses.
                        The item does not support having a standard cost.";
                    $msg ="Remove the standard cost entries for the warehouses.";
                    $gErr->addIAError('INV-1197', __FILE__ . ':' . __LINE__,
                        "Unable to save Item Information - Invalid Warehouse Information provided", [],
                        $msg1 . $msg, []);
                    $ok = false;
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $warehouseInfo
     * @param array $itemInfo
     *
     * @return bool
     */
    private function PrepWarehouseStdCostEntries(&$warehouseInfo, $itemInfo)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        $itemID = $itemInfo['ITEMID'];
        $whseID = $warehouseInfo['WAREHOUSEID'];

        $stdCostDetails = '';
        foreach ( ( ( $warehouseInfo['STDCOSTENTRIES'] ) ?? [] ) as $costEntry ) {
            $stdCostDetails = $costEntry['EFFECTIVE_START_DATE'] . $costEntry['STANDARD_COST'];
        }

        $duplicateDates = array();
        if (is_array($warehouseInfo['STDCOSTENTRIES'])) {
            foreach ($warehouseInfo['STDCOSTENTRIES'] as $key=> &$costEntry) {
                $lineNo = $key+1;

                // validations are done in the ItemWarehouseStdcostManager::PrepValues for each costEntry
                $hasStdCostData = strlen($stdCostDetails) > 0 ;
                if (!$hasStdCostData) {
                    continue;
                }

                $startDate = $costEntry['EFFECTIVE_START_DATE'];
                // Duplicate effective start date in entries?
                if ($duplicateDates[$startDate]) {
                    $msg = "Duplicate effective start date '".$startDate."' in line $lineNo for warehouse '" . $whseID . "'";
                    $gErr->addIAError(
                        'INV-1143',
                        __FILE__ . ':' . __LINE__,
                        "", [],
                        $msg, [ 'START_DATE' => $startDate, 'LINE_NO' => $lineNo, 'WHSEID' => $whseID]);
                    $ok = false;
                    break;
                } else {
                    if (isl_strlen($startDate)!=0) {
                        $duplicateDates[$startDate] = 1;
                    }
                }

                //
                //
                $costEntry['ITEMID'] = $itemID;
                $costEntry['WAREHOUSEID'] = $whseID;
            }
        }

        //
        // sort the entries by Effective start date in descending order
        if($ok
            && isset($warehouseInfo['STDCOSTENTRIES'])
            && is_array($warehouseInfo['STDCOSTENTRIES'])){
            usort($warehouseInfo['STDCOSTENTRIES'], array($this, 'SortCostEntries'));
        }

        return $ok;
    }

    /**
     * Sort the item > warehouse standard cost entries by effective date in descending order
     *
     * @param array $a
     * @param array $b
     *
     * @return int
     */
    static function SortCostEntries($a, $b)
    {
        // Sort by date. in descending order
        $result = DateCompare($b['EFFECTIVE_START_DATE'], $a['EFFECTIVE_START_DATE']);

        return $result;
    }

    /**
     * @param array $values
     *
     * @return array
     */
    private function PrepDefaultValues($values)
    {
        global $kINVid;
        //$kINVid = Globals::$g->kINVid;

        GetModulePreferences($kINVid, $InvModPref);

        if (!isset($values['COST_METHOD'])) {
            if (isset($InvModPref['DEFAULT_COST_METHOD'])) {
                $defCostMethod = $this->_TransformInternalValue('COST_METHOD', $InvModPref['DEFAULT_COST_METHOD']);
                $values['COST_METHOD'] = ($defCostMethod && $defCostMethod != '') ? $defCostMethod : 'Standard';
            }
            else
            {
                $values['COST_METHOD'] = 'Standard';
            }
        }

        //if ($this->isAdvancedSetup && !isset($values['UOMGRP']))

        if (!isset($values['UOMGRP']) || $values['UOMGRP']=='') {
            if (isset($InvModPref['DEFAULT_UOMGRP']) && $InvModPref['DEFAULT_UOMGRP'] != '') {
                $values['UOMGRP'] = $InvModPref['DEFAULT_UOMGRP'];
            }
            else
            {
                $values['UOMGRP'] = 'Count';
            }
        }

        // this is only for CSV Upload case where we would consider the COST column based on the ItemType
        if ($values['COST_METHOD'] != '') {
            if ($values['COST_METHOD'] == 'Average' && !isset($values['AVERAGE_COST']) && isset($values['ITEM_COST'])) {
                $values['AVERAGE_COST'] = $values['ITEM_COST'];
            }
            if ($values['COST_METHOD'] == 'Standard' && !isset($values['STANDARD_COST']) && isset($values['ITEM_COST'])) {
                $values['STANDARD_COST'] = $values['ITEM_COST'];
            }
        }
        if (!isset($values['UOMGRP']) && isset($InvModPref['DEFAULT_UOMGRP'])) {
            $values['UOMGRP'] = $InvModPref['DEFAULT_UOMGRP'];
        }

        if (empty($values['VSOECATEGORY'])) {
            $values['VSOECATEGORY'] = 'Product - Specified';
        }
        if (empty($values['VSOEDLVRSTATUS'])) {
            $values['VSOEDLVRSTATUS'] = 'Delivered';
        }
        if (empty($values['VSOEREVDEFSTATUS'])) {
            $values['VSOEREVDEFSTATUS'] = ITEM_DEFERRAL;
        }


        return $values;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function ValidateSerializedItem(&$values)
    {
        global $gManagerFactory, $gErr;
        //        $gManagerFactory = Globals::$g->gManagerFactory;
        //$gErr = Globals::$g->gErr;

        $ok = true;

        if ($ok && $values['SERIAL_MASKKEY']) {
            $serialMgr = $gManagerFactory->getManager('serialmask');
            $row = $serialMgr->GetRaw($values['SERIAL_MASKKEY']);
            $ok = $ok && isset($row[0]);
            if (!$ok) {
                $msg = "Invalid Serial Mask.";
                $gErr->addIAError('INV-1120', __FILE__ . ':' . __LINE__, $msg, []);
                return $ok;
            }
            $values[':serialmaskkey'] = $row[0]['RECORD#'];
        }

        if ($values['ENABLE_LOT_CATEGORY']=='true' && !$values['LOT_CATEGORYKEY']) {
            $msg = "Lot Category not provided";
            $gErr->addIAError('INV-1121', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }

        if ($ok && $values['LOT_CATEGORYKEY']) {
            $lotcatMgr = $gManagerFactory->getManager('lotcategory');
            $row = $lotcatMgr->GetRaw($values['LOT_CATEGORYKEY']);
            $ok = $ok && isset($row[0]);
            if (!$ok) {
                $msg = "Invalid Lot Category.";
                $gErr->addIAError('INV-1122', __FILE__ . ':' . __LINE__, $msg, []);
                return $ok;
            }
            $values[':lotcatkey'] = $row[0]['RECORD#'];
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function ValidateKitTypeItem(&$values)
    {
        global $gManagerFactory, $gErr, $kINVid;
        //$gManagerFactory = Globals::$g->gManagerFactory;
        //$gErr = Globals::$g->gErr;
        //$kINVid = Globals::$g->kINVid;
        $enabledForContract = (($values['CONTRACTENABLED'] ?? '') === 'true');

        $ok = true;

        $uomMgr = $gManagerFactory->getManager('uom');

        GetModulePreferences($kINVid, $InvModPref);

        if (!isset($values['COMPONENT_INFO'][0])) {
            $msg = "No information for components is provided.";
            $gErr->addIAError('INV-1123', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }
        //If item type is stockable kit and 'Enable Light assembly' set to false, then throw error -- csv upload
        if ($InvModPref['LIGHTASSEMBLY']!='T' && ($values['ITEMTYPE'] == STOCKABLE_KIT || $values['ITEMTYPE'] == 'SK')) {
            $gErr->addIAError('INV-0173', __FILE__ . ":" . __LINE__, "Please make sure that the option 'Enable Light Assembly' in 'Inventory Set Up' set to True before creating any Stockable Kits", []);
            return false;
        }
        //If item type is kit and 'Enable Kitting' set to false, then throw error -- csv upload
        if (!IsKitEnabled() && ($values['ITEMTYPE'] == KIT || $values['ITEMTYPE'] == 'K')) {
            $gErr->addIAError('INV-0174', __FILE__ . ":" . __LINE__, "Please make sure that the option 'Enable Kitting' in 'Inventory Set Up' set to True before creating any Kits", []);
            return false;
        }
    
        // Default values for contract enabled kits
        if ($enabledForContract) {
            if (empty($values['REVPOSTING'])) {
                $values['REVPOSTING'] = COMPONENT;
            }

            if (empty($values['REVPRINTING'])) {
                $values['REVPRINTING'] = KIT;
            }
        }
        // if REVPOSTING is KITLEV then set REVPRINTING is KIT
        if(isset($values['REVPOSTING']) && $values['REVPOSTING'] === KITLEV ){
            $values['REVPRINTING'] = KIT;
        }

        //if item type is kit/stockable kit then if 'Rev posting' value passed other than 'Kit Level'/'Component level' then default to Kit Level' -- csv upload
        $levarr = [KITLEV, COMPONENT];
        if (isset($values['REVPOSTING']) && !in_array($values['REVPOSTING'], $levarr)) {
            $values['REVPOSTING'] = KITLEV;
        }

        if ($values['ITEMTYPE'] == STOCKABLE_KIT && $values['REVPOSTING'] != KITLEV) {
            $gErr->addIAError('INV-0175', __FILE__ . ":" . __LINE__, "Revenue Posting Preference for Stockable Kits can only be Kit Level", []);
            return false;
        }

        //unsetting the values which are not necessary for kits/stockable kits
        unset($values['UPC']);

        // unset the values which are not necessary for kits
        if ($values['ITEMTYPE'] == KIT) {
            unset($values['PURCHASE_UNIT'], $values['PURCHASE_UNIT_FACTOR'], $values['INV_PRECISION'], $values['SO_PRECISION'], $values['PO_PRECISION'], $values['WHEN_LASTRECEIVED']);
        }

        $RevPrecentTotal = 0;
        $KitCompArr = array();


        $uomcache = array();
        $itemMgr = $gManagerFactory->getManager('item');
        $companyid=GetMyCompany();
        $parentStKitsQry = 'QRY_ICITEM_GET_PARENT_STKITS';
        $parentStKitsArgs = array ($companyid,$values['ITEMID'],$companyid, $companyid);
        $retVal=$itemMgr->DoQuery($parentStKitsQry, $parentStKitsArgs);
        $parentStKits=array();
        foreach( $retVal as $stkit) {
            $parentStKits[]=$stkit['ITEMKEY'];
        }
        foreach($values['COMPONENT_INFO'] as $key => $line) {
            $lineno = $key+1;

            //for deleting the component for xml api
            if (isl_strtoupper($line['DELETE_COMPONENT']) == 'TRUE' || isl_strtoupper($line['DELETE_COMPONENT']) == 'T') {
                unset($values['COMPONENT_INFO'][$key]);
                if (count($values['COMPONENT_INFO']) < 1) {
                    $msg = "No information for components is provided.";
                    $gErr->addIAError('INV-1124', __FILE__ . ':' . __LINE__, $msg, []);
                    return false;
                }
                continue;
            }

            /*
             * If the component key is not specified, we shouldn't go any farther and try to query,
             * nor should we silently ignore and try to process others.
             * It's a malformed component specification.
             */
            if (!empty($line['COMPONENTKEY'])) {
                $qry = array( 'filters' => array( array( array( 'ITEMID', '=', $line['COMPONENTKEY'] ) ) ) );
                $raw = $this->GetList($qry);

                //if we are not being set, assign the value from the component setting
                if ( ! isset($line['KCDLVRSTATUS']) ) {
                    if ( $raw[0]['VSOEDLVRSTATUS'] == 'Delivered' ) {
                        $values['COMPONENT_INFO'][$key]['KCDLVRSTATUS'] = 'Delivered';
                    } else {
                        $values['COMPONENT_INFO'][$key]['KCDLVRSTATUS'] = 'Undelivered';
                    }
                }

                if ( ! isset($line['KCREVDEFSTATUS']) ) {
                    if ( $raw[0]['VSOEREVDEFSTATUS'] == BUNDLE_DEFERRAL ) {
                        $values['COMPONENT_INFO'][$key]['KCREVDEFSTATUS'] = BUNDLE_DEFERRAL;
                    } else {
                        $values['COMPONENT_INFO'][$key]['KCREVDEFSTATUS'] = ITEM_DEFERRAL;
                    }
                }

                //Duplicate kit components are not allowed, if so throw an error
                if ( ! in_array($line['COMPONENTKEY'], $KitCompArr, true) ) {
                    $KitCompArr[] = $line['COMPONENTKEY'];
                } else {
                    $msg = "Duplicate Kit Component Item " . "'" . $line['COMPONENTKEY'] . "'" . " is not allowed";
                    $gErr->addIAError(
                        'INV-1144',
                        __FILE__ . '.' . __LINE__,
                        "Line $lineno : " . $msg, [ 'LINE_COMPONENTKEY' => $line['COMPONENTKEY'], 'LINENO' => $lineno ]
                    );
                    return false;
                }
            }

            if (isset($raw[0])) {
                if ($raw[0]['ITEMTYPE'] == 'Non-Inventory (Purchase only)') {
                    $msg = "Non-Inventory Purchase only Item can not be a Kit Component";
                    $gErr->addIAError('INV-1145', __FILE__ . '.' . __LINE__, "Line $lineno : " . $msg, [ 'LINENO' => $lineno]);
                    return false;
                }
                if ( $values['ITEMTYPE'] == STOCKABLE_KIT || $values['ITEMTYPE'] == 'SK' ) {
                    if ( ! StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                        && ( $raw[0]['ENABLE_SERIALNO'] == 'true' || $raw[0]['ENABLE_LOT_CATEGORY'] == 'true' ) ) {
                        $msg = "Items enabled for Serial or Lot Tracking can not be a Stockable Kit Component";
                        $gErr->addIAError('INV-1146', __FILE__ . '.' . __LINE__, "Line $lineno : " . $msg, [ 'LINENO' => $lineno] );
                        return false;
                    }
                    if ($raw[0]['ITEMTYPE'] == 'Kit') {
                        $msg = "kit can not be a Stockable Kit Component";
                        $gErr->addIAError('INV-1147', __FILE__ . '.' . __LINE__, "Line $lineno : " . $msg, [ 'LINENO' => $lineno] );
                        return false;
                    }
                    //Do not allow circular references
                    if (in_array($line['COMPONENTKEY'], $parentStKits, true)) {
                        $msg = _(
                            " Circular references found. Stockable kit " ."'".
                            $line['COMPONENTKEY']."'"." is already a parent of '".$values['ITEMID']."'. It cannot be a component."
                        );
                        $gErr->addIAError(
                            'INV-1148',
                            __FILE__ . '.' . __LINE__,
                            "Line $lineno : " . $msg, [ 'LINE_COMPONENTKEY' => $line['COMPONENTKEY'], 'VALUES_ITEMID' => $values['ITEMID'] ,'LINENO' =>$lineno]
                        );
                        return false;
                    } else if ($line['COMPONENTKEY']===$values['ITEMID']) {
                        $msg =
                            " Circular references found. Stockable kit " ."'".
                            $line['COMPONENTKEY']."'"." cannot be a component of itself.";
                        $gErr->addIAError(
                            'INV-1149',
                            __FILE__ . '.' . __LINE__,
                            "Line $lineno : " . $msg,
                            [ 'LINE_COMPONENTKEY' => $line['COMPONENTKEY'],'LINENO' =>$lineno]
                        );
                        return false;
                    }

                }
                //Get Std UOM for the kit component
                if (!isset($line['UNIT'])) {
                    //SRAO:: we need a way for this defaulting.
                    $uomInfo = $this->GetUOMInfo($line['COMPONENTKEY']);
                    $values['COMPONENT_INFO'][$key]['UNIT'] = $uomInfo['STD_UNIT'];
                    $line['UNIT'] = $uomInfo['STD_UNIT'];

                }
                //Get cost of the item depends on its itemtype. Standard cost for Standard type, average cost for Average type, 0 for FIFO/LIFO type
                if (!isset($line['COST'])) {
                    $costInfo = $this->GetKitItemCost($line['COMPONENTKEY'], $line['ITEMID']);
                    $values['COMPONENT_INFO'][$key]['COST'] = $costInfo[0]['STANDARDCOST'] ?:0;
                }
                //If component key is missing then throw an error - csv uplaod
            }else{
                $msg = "Invalid 'Component ID' or 'Component ID is missing. ";
                $gErr->addIAError(
                    'INV-1150',
                    __FILE__ . '.' . __LINE__,
                    "Line $lineno : " . $msg , [ 'LINENO' => $lineno]
                );
                return false;
            }

            //fetch the component uom and round quantity based on the uom decimals
            if (!array_key_exists($line['UNIT'], $uomcache)) {
                $resUom =  $uomMgr->GetRaw($line['UNIT']);
                $resUom = $resUom[0];
                $uomcache[$line['UNIT']] = $resUom;
            }

            if( (float)$line['REVPERCENT'] < 0 ) {
                $msg = "Negative percentage of Revenue split for a kit component is not allowed";
                $gErr->addIAError('INV-1125', __FILE__ . '.' . __LINE__, $msg, []);
                return false;
            }
            //As qty is optional through xml gateway, validate qty should be there
            if( !is_numeric($line['QUANTITY']) || +$line['QUANTITY'] <= 0 ) {
                $msg = "Negative, zero, or non-numeric quantity for a kit component is not allowed";
                $gErr->addIAError('INV-1126', __FILE__ . '.' . __LINE__, $msg, []);
                return false;
            }
            // bug#41105
            // for now we are rounding off to 4 decimals as the base unit has no decimals set and the max decimals allowd in UOM is 4
            // proper fix will be provided with PDLC-0119-09
            $values['COMPONENT_INFO'][$key]['QUANTITY'] = round($line['QUANTITY'], 4);

            if ($values['REVPOSTING']==KITLEV) {
                unset($values['COMPONENT_INFO'][$key]['REVPERCENT']);
            }
            if($values['REVPOSTING']==COMPONENT) {
                //PHP 8.1 issue on bcadd to converting ibcadd and by default the precision is 2 and rounding is false
                // Component percent are set with precision 2 in UI so left same.
                $RevPrecentTotal = ibcadd($RevPrecentTotal, $line['REVPERCENT']);
            }
        }
        if($values['REVPOSTING']==COMPONENT && $values['VSOEAPPLIES'] != 'true' && $RevPrecentTotal!=100 ) {
            $msg = "Revenue split total for kit components should be 100";
            $gErr->addIAError('INV-1127', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function ValidateItemTermValues(&$values)
    {
        global $gErr;
        //$gErr = Globals::$g->gErr;

        if($values['HASSTARTENDDATES']=='true' && $values['TERMPERIOD']=='') {
            $msg = "Term Period is required when 'Item Has Start And End Date' is checked";
            $gErr->addIAError('INV-1128', __FILE__ . '.' . __LINE__, $msg, []);
            return false;
        }

        if($values['HASSTARTENDDATES']=='true' && $values['TOTALPERIODS']=='') {
            $msg = "'Number of periods' is required when 'Item Has Start And End Date' is checked";
            $gErr->addIAError('INV-1129', __FILE__ . '.' . __LINE__, $msg, []);
            return false;
        }

        if($values['TOTALPERIODS']!='' && ($values['TOTALPERIODS'] > 1500 || $values['TOTALPERIODS'] <= 0)) {
            $msg = "'Number of periods' should be between 1  and 1500.";
            $gErr->addIAError('INV-1130', __FILE__ . '.' . __LINE__, $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function ValidateItemRenewalInfo(&$values)
    {
        global $gManagerFactory, $gErr;
        //$gManagerFactory = Globals::$g->gManagerFactory;
        //$gErr = Globals::$g->gErr;

        //  Saving the default Renewal Macro for the Item.
        if($values['RENEWALMACROID']!='') {
            /** @var RenewalMacroManager $renewalMacroMgr */
            $renewalMacroMgr    = $gManagerFactory->getManager('renewalmacro');
            $macroID            =  isl_trim($values['RENEWALMACROID']);
            $renewalMacro       = $renewalMacroMgr->get($macroID);
            if(!isset($renewalMacro['RECORDNO']) || $renewalMacro['STATUS']!='active') {
                $msg = "Invalid Renewal Template. Please select a valid Renewal Template";
                $gErr->addIAError('INV-1131', __FILE__ . '.' . __LINE__, $msg, []);
                return false;
            }
            $values[':renewalmacrokey'] =$renewalMacro['RECORDNO'];
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $values[':renewalmacrokey'] = $renewalMacro['RECORDNO'];

        // set the default vsoe information if not set
        if(!isset($values['VSOEDLVRSTATUS']) || $values['VSOEDLVRSTATUS'] == '') {
            $values['VSOEDLVRSTATUS'] = 'Delivered';
        }
        if(!isset($values['VSOEREVDEFSTATUS']) || $values['VSOEREVDEFSTATUS'] == '') {
            $values['VSOEREVDEFSTATUS'] = ITEM_DEFERRAL;
        }

        if(!isset($values['VSOECATEGORY']) || $values['VSOECATEGORY'] == '') {
            $values['VSOECATEGORY'] = 'Product - Specified';
        }
        else
        {
            $opCode = Request::$r->_do;

            //in edit mode, if vsoecategory is not set to either service or pcs, we need to check if this item has already been
            //defined as a percentage vsoe price list.
            if($opCode == 'edit' && $values['VSOECATEGORY'] != 'Services' && $values['VSOECATEGORY'] != 'Post Contract Support(PCS)') {
                $vsoeItemPriceListMgr = $gManagerFactory->getManager('vsoeitempricelist');
                if($vsoeItemPriceListMgr->IsItemPercentBased($values['ITEMID'])) {
                    $msg  = "Can not proceed with changing vsoe category to ". $values['VSOECATEGORY'];
                    $actionMsg = "Please delete the fair value price list entry for this item and try update again.";
                    $gErr->addIAError(
                        'INV-1132',
                        __FILE__ . '.' . __LINE__,
                        $msg, [ 'VALUES_VSOECATEGORY' => $values['VSOECATEGORY']],
                        "", [],
                        $actionMsg, []
                    );

                    return false;
                }
            }
        }

        return true;
    }


    /**
     * @param string     $ID
     * @param null|array $fields
     *
     * @return array|false
     */
    public function Get($ID, $fields=null)
    {
        list($ID) = explode('--', $ID);
        $toreturn = parent::get($ID);

        if ($toreturn) {
            $toreturn['BASEPRICE'] = $this->GetBasePrice($ID, 1);

            if (in_array($toreturn['ITEMTYPE'], array(STOCKABLE_KIT, KIT))) {

                $toreturn['COMPONENT_INFO'] = $this->GetComponentDetails($toreturn['COMPONENT_INFO']);
            } else {
                //remove revenue pref is kit/stockable kit
                $toreturn['REVPOSTING'] = '';
            }

            if (!$this->isAdvancedSetup && !empty($toreturn['GLGROUP']) ) {
                $toreturn = $this->GetItemGlGroupAccounts($toreturn);
            }

            if (self::isReplenishmentOn()) {
                foreach ($toreturn['WAREHOUSE_INFO'] as &$iwi) {
                    ItemWarehouseInfoManager::possiblyCleanUpValues($iwi);
                    // set the "does the warehouse use replenishment" flag, but set it false if the item doesn't.
                    $iwi['W_ENABLE_REPLENISHMENT'] =
                        (($toreturn['ENABLE_REPLENISHMENT'] === 'true') &&
                            (self::GetWarehouseReplenishmentEnableFlag($iwi['WAREHOUSEID']) === 'true')) ? 'true' : 'false';

                    if ($iwi['W_ENABLE_REPLENISHMENT'] === 'false') {
                        $iwi['ENABLE_REPLENISHMENT'] = 'false';
                    }
                }
            }
            $toreturn['REORDER_QTY']   = $toreturn['REORDER_QTY']   ?? 1;
            $toreturn['MAX_ORDER_QTY'] = $toreturn['MAX_ORDER_QTY'] ?? 0;

            // setting item vendor VENDORID to VENDORID--VENDORNAME. to support XML API.
            if (isset($toreturn['VENDOR_INFO'])) {
                foreach ($toreturn['VENDOR_INFO'] as $key => $val) {
                    $val['VENDORID'] =  $val['VENDORID']."--".$val['VENDORNAME'];
                    $toreturn['VENDOR_INFO'][$key] = $val;
                }
            }

            // did we find any crossref records?
            // this won't help the API, but it will help us when returning from the UI....
            $toreturn['ITEMCROSSREFERENCES_EXISTED'] = (isset($toreturn['ITEMCROSSREFERENCES']) && ( ! empty($toreturn['ITEMCROSSREFERENCES'])));
        }

        return $toreturn;
    }

    /**
     * @param array $toreturn
     *
     * @return array
     */
    function GetItemGlGroupAccounts($toreturn)
    {
        global $gManagerFactory;
        //$gManagerFactory = Globals::$g->gManagerFactory;

        /** @var ItemGLGroupManager $grpMgr */
        $grpMgr = $gManagerFactory->getManager('itemglgroup');
        $itemGrpObj = $grpMgr->Get($toreturn['GLGROUP']);

        $toreturn['INCOMEACCTKEY'] = $itemGrpObj['INCOMEACCTKEY'];
        $toreturn['EXPENSEACCTKEY'] = $itemGrpObj['EXPENSEACCTKEY'];
        $toreturn['INVACCTKEY'] = $itemGrpObj['INVACCTKEY'];
        $toreturn['COGSACCTKEY'] = $itemGrpObj['COGSACCTKEY'];

        $toreturn['OFFSETPOGLACCOUNTKEY'] = $itemGrpObj['OFFSETPOGLACCOUNTKEY'];
        $toreturn['OFFSETOEGLACCOUNTKEY' ] = $itemGrpObj['OFFSETOEGLACCOUNTKEY'];

        $toreturn['DEFERREDREVACCTKEY'] = $itemGrpObj['DEFERREDREVACCTKEY'];
        $toreturn['DEFAULTREVRECTEMPLKEY'] = $itemGrpObj['DEFAULTREVRECTEMPLKEY'];
        return $toreturn;
    }

    /**
     * The verification for idw parameter for the Item object is required.
     *
     * @return bool
     */
    protected function isCheckForIdwRequired()
    {
        return true;
    }

    /**
     * Returns the specific helper class for result set iterator.
     *
     * @param array $queryParams
     *
     * @return ResultSetIteratorHelper
     */
    protected function getResultSetIteratorHelper($queryParams = [])
    {
        $helper = new ItemIteratorHelper($this, $queryParams);

        return $helper;
    }

    /**
     * @param array     $params
     * @param bool      $_crosscny
     * @param bool      $nocount
     *
     * @return array[]
     */
    function GetList($params = [],$_crosscny = false, $nocount = true)
    {

        // Columns cannot be removed or added if request is from DDS
        if ( $params['idw'] === true ) {
            return parent::GetList($params, $_crosscny, $nocount);
        }

        $docs = parent::GetList($params, $_crosscny, $nocount);

        $includeBasePrice = true;

        if(isset($params['selects'])){
            $includeBasePrice = false;
            foreach($params['selects'] as $selects){
                if ( $selects == 'BASEPRICE'){
                    $includeBasePrice = true;
                }
            }
        }


        //fetch and add component details
        foreach ($docs as $key => $doc) {
            if (in_array($doc['ITEMTYPE'] ?? null, array(STOCKABLE_KIT, KIT))) {

                if (isset($doc['ITEMID'])) {
                    // $itemrec = $this->Get($doc['ITEMID']);
                    $manager = Globals::$g->gManagerFactory->getManager('itemcomponent');
                    // Note: in GetListFull(), below, there's a note about only getting certain fields.
                    //       but here, I'll do what Get() would do: use GetByParent().
                    $componentInfo = $manager->getByParent($doc['ITEMID']);
                    $componentInfo = $this->GetComponentDetails($componentInfo); // and we need the average cost....
                    $docs[$key]['COMPONENT_INFO'] = $componentInfo; // $itemrec['COMPONENT_INFO'];
                }
            } else {
                // Unset breaks GetList since key itself is misssing
                //unset($docs[$key]['REVPOSTING']);
                $docs[$key]['REVPOSTING'] = null;
            }

            if($includeBasePrice == true){
                if(isset($doc['ITEMID']) && $doc['ITEMID'] != ''){
                    $docs[$key]['BASEPRICE'] = $this->GetBasePrice($doc['ITEMID'], 1);
                }else{
                    $docs[$key]['BASEPRICE'] = 0;
                }
            }
        }

        return $docs;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "Item::Add";
        global $gErr;
        //$gErr = Globals::$g->gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->validateItem($values, 'Add');

        $ok = $ok && $this->PrepValues($values);

        $ok = $ok && parent::regularAdd($values);

        // PHP8_NUMERIC_STRING_COMPARE; Priority: low; Behavior: same, Risk: low, Solution: php7eqEmptyStr
        if ( !Util::php7eqEmptyStr($values['BASEPRICE'] ?? '') ) {
            $ok = $ok && $this->SetPrice($values['ITEMID'], $values['BASEPRICE']);
        }

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if ($gErr->hasErrors()) {
                $msg = "Could not create Item record!";
                $gErr->addIAError('INV-1133', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
            }
            $this->_QM->rollbackTrx($source);
        }
        else {
            $this->DoEvent('Add', $values['ITEMID'], true, false, $values);
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
        $source = "Item::Set";

        global $gErr;

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->validateItem($values, 'Set');

        $ok = $ok && $this->PrepValues($values);

        //If allow multiple tax groups is disabled for an existing item, delete existing multiple tax groups
        if ($ok && TaxSetupManager::isMultiTaxJurisdictionConfigured() && IsRoot()
            && $values['ALLOWMULTIPLETAXGRPS'] != 'true') {
            $taxGrpItemMapMngr = Globals::$g->gManagerFactory->getManager('itemtaxgrpitemmap');
            $ok = $taxGrpItemMapMngr->deleteByParent($values['ITEMID'], DELETE_FOR_UPDATE);
        }

        $ok = $ok && parent::regularSet($values);

        // PHP8_NUMERIC_STRING_COMPARE; Priority: low; Behavior: same, Risk: low, Solution: php7eqEmptyStr
        if ( !Util::php7eqEmptyStr($values['BASEPRICE'] ?? '') ) {
            $ok = $ok && $this->SetPrice($values['ITEMID'], $values['BASEPRICE']);
        }

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if ($gErr->hasErrors()) {
                $msg = "Could not set Item record!";
                $gErr->addIAError('INV-1134', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
            }
            $this->_QM->rollbackTrx($source);
        }
        else {
            $this->DoEvent('Set', $values['ITEMID'], true, false, $values);
        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function AddItemGLGrpValues(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $ok = true;

        if ($this->isAdvancedSetup) {
            if (!isset($values['GLGROUP']) || $values['GLGROUP'] == '' ) {
                $plMgr     = $gManagerFactory->getManager('productline');
                $values[':glgrpkey'] = $plMgr->FindGLGroupAncestor($values['PRODUCTLINEID']);
            } else {
                $grpMgr = $gManagerFactory->getManager('itemglgroup');
                $raw = $grpMgr->GetRaw($values['GLGROUP']);
                $ok = $ok && isset($raw[0]['RECORD#']);
                if (!$ok) {
                    $msg = "Invalid GL Group Provided!";
                    $gErr->addIAError('INV-1135', __FILE__ . ':' . __LINE__, $msg, []);
                    /** @noinspection PhpUndefinedVariableInspection */
                    epp("$source: Error: $msg");
                }
                $values[':glgrpkey'] = $raw[0]['RECORD#'];
            }
        } else {
            $ok = $ok && $this->UpsertDefaultItemOffsets($values);
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function UpsertDefaultItemOffsets(&$values)
    {
        global $gManagerFactory;

        $ok = true;

        // EXPENSEACCTKEY value should be set only for Non-inventory and Non-inventory (purchase only) type
        $values['EXPENSEACCTKEY'] = (in_array($values['ITEMTYPE'], [NONINV, NONINV_PO])) ? $values['EXPENSEACCTKEY'] : '';

        $itemGlGrp = array (
            "NAME" => "SYS_ITEMGLGRP_".$values['ITEMID'],
            "INCOMEACCTKEY" => $values['INCOMEACCTKEY'],
            "EXPENSEACCTKEY" => $values['EXPENSEACCTKEY'],
            "INVACCTKEY" => $values['INVACCTKEY'],
            "COGSACCTKEY" => $values['COGSACCTKEY'],
            "OFFSETPOGLACCOUNTKEY" => $values['OFFSETPOGLACCOUNTKEY'],
            "OFFSETOEGLACCOUNTKEY" => $values['OFFSETOEGLACCOUNTKEY'],
            "DEFERREDREVACCTKEY" => $values['DEFERREDREVACCTKEY'],
            "DEFAULTREVRECTEMPLKEY" => $values['DEFAULTREVRECTEMPLKEY'],
            "ISSYSTEM" => 'true',
        );
        $grpMgr = $gManagerFactory->getManager('itemglgroup');
        $raw = $grpMgr->GetRaw("SYS_ITEMGLGRP_".$values['ITEMID']);

        if (isset($raw[0]['RECORD#'])) {
            $ok = $ok && $grpMgr->set($itemGlGrp);
            $itemGlGrp[':record#'] = $raw[0]['RECORD#'];
        } else {
            $ok = $ok && $grpMgr->add($itemGlGrp);
        }

        $itemGlGrp['RECORDNO'] = $itemGlGrp[':record#'];
        $values[':glgrpkey'] = $itemGlGrp[':record#'];

        if (in_array($values['ITEMTYPE'], array(INVENTORY, KIT, STOCKABLE_KIT))) {
            // Upsert the AP/AR & inventory gl posting accounts.
            $invdocParMgr = $gManagerFactory->getManager('invdocumentparams');
            $ok = $ok && $invdocParMgr->SetDocParPostingOffsetAccounts($values, $itemGlGrp);
        }

        if (in_array($values['ITEMTYPE'], array(INVENTORY, NONINV, NONINV_SO, KIT, STOCKABLE_KIT))) {
            $sodocParMgr = $gManagerFactory->getManager('sodocumentparams');
            $ok = $ok && $sodocParMgr->SetDocParPostingOffsetAccounts($values, $itemGlGrp);
        }

        if (in_array($values['ITEMTYPE'], array(INVENTORY, NONINV, NONINV_PO, STOCKABLE_KIT))) {
            $podocParMgr = $gManagerFactory->getManager('podocumentparams');
            $ok = $ok && $podocParMgr->SetDocParPostingOffsetAccounts($values, $itemGlGrp);
        }

        return $ok;
    }

    /**
     * @param string    $itemID
     * @param float     $price
     * @param string    $list
     * @param string    $currency
     *
     * @return bool
     */
    public function SetPrice($itemID,$price,$list='base',$currency='')
    {

        global $gManagerFactory;
        global $gErr;

        //$gManagerFactory = Globals::$g->gManagerFactory;
        //$gErr = Globals::$g->gErr;

        $mod = Request::$r->_mod;
        // get the preference for MCP
        $_ismcpEnabled = IsMCPEnabled($mod);
        $_basecurrency = ($_ismcpEnabled) ? GetBaseCurrency() : '';

        $entryMgr     = $gManagerFactory->getManager('invpricelistentry');
        $plMgr         = $gManagerFactory->getManager('invpricelist');

        if ($list == 'base') {
            $listname='Base Price List';
            $row = $plMgr->GetRaw($listname);
            $listkey = $row[0]['RECORD#'];
        } else {
            $row = $plMgr->GetRaw($list);
            if (!isset($row[0])) {
                $msg = 'Error updating price list.';
                $gErr->addIAError('INV-1136', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }
            $listkey = $row[0]['RECORD#'];
        }

        //Setting $datefrom and $dateto varaiables
        if (isset($row[0]['DATEFROM'], $row[0]['DATETO'])) {
            $datefrom =$row[0]['DATEFROM'];
            $dateto = $row[0]['DATETO'];
        } else {
            $datefrom ='01/01/2000';
            $dateto = '12/31/2100';
        }

        if($_ismcpEnabled) {
            $currency = ($currency=='') ? $_basecurrency : $currency;
            $qry = 'QRY_INVPRICELISTENTRY_SETPRCLIST_BY_MCP_ITEM';
            $args = array ( $price, $listkey, $datefrom, $dateto, $itemID, $_basecurrency, $currency);
        }else{
            $qry = 'QRY_INVPRICELISTENTRY_SETPRCLIST_BY_ITEM';
            $args = array ( $price, $listkey, $datefrom, $dateto, $itemID);
        }

        $ok = $entryMgr->DoQuery($qry, $args);

        if ( $entryMgr->_QM->QMAffectedRows() == 0) {
            $entry = array (
                'ITEMID'        => "$itemID",
                ':prclstkey'    => $listkey,
                'DATEFROM'        => $datefrom,
                'DATETO'        => $dateto,
                'VALUE'            => $price,
                'QTYLIMITMIN'    => self::BASEPRICEENTRY_QTYLIMITMIN_ITEMMGR,
                'QTYLIMITMAX'    => self::BASEPRICEENTRY_QTYLIMITMAX_ITEMMGR,
                'VALUETYPE'        => 'Actual',
            );

            if($_ismcpEnabled) {
                $entry['CURRENCY'] = $currency;
            }
            $ok = $entryMgr->add($entry);
        }else {
            if($_ismcpEnabled) {
                $currency = ($currency=='') ? $_basecurrency : $currency;
                $qry = 'QRY_INVPRICELISTENTRY_SELECT_BY_MCP_ITEM';
                $args = array ( $price, $listkey, $datefrom, $dateto, $itemID, $_basecurrency, $currency);
            }else{
                $qry = 'QRY_INVPRICELISTENTRY_SELECT_BY_ITEM';
                $args = array ( $price, $listkey, $datefrom, $dateto, $itemID);
            }
            $entryrow = $entryMgr->DoQuery($qry, $args);
            $entryId = $entryrow[0]['RECORD#'];
            //If entryId is set then call DoEvent for ims operation
            if($entryId != '') {
                $entryMgr->DoEvent('Set', $entryId, false);
            }
        }

        if (!$ok) {
            $msg = 'Error update Price List '. $list;
            $gErr->addIAError('INV-1137', __FILE__ . ':' . __LINE__, $msg, [ 'LIST' =>$list ]);
        }

        return $ok;
    }

    /**
     * @param array     $params
     * @param bool      $_crosscny
     * @param bool      $nocount
     *
     * @return array[]|null
     */
    function GetListFull(&$params,$_crosscny = false, $nocount = true)
    {
        global $gManagerFactory;
        $InLimit = 500;

        if ( !isset($params['selects']) ) {
            $params['selects'] = $this->GetGetFields();
        }

        $items = parent::GetList($params, $_crosscny, $nocount);
        $itemCount = count($items);

        // If there are no items to process, return
        if (!$itemCount) {
            return null;
        }

        //get the item's vendor, warehouse, kit components managers
        $itmVendorMgr = $gManagerFactory->getManager('itemvendor');
        $itmWhseMgr = $gManagerFactory->getManager('itemwarehouseinfo');
        $itmCompMgr = $gManagerFactory->getManager('itemcomponent');
        $itmwhsestdcostMgr = $gManagerFactory->getManager('itemwarehousestdcost');

        //Explicit selects because there are some undefined fields in the entity file which may cause oracle error.
        $itmCompEntryParams = array (
            'selects' => array (
                'RECORDNO',
                'ITEMID',
                'COMPONENTKEY' ,
                'QUANTITY',
                'UNIT',
                'COST',
                'REVPERCENT',
                'KCDLVRSTATUS',
                'KCREVDEFSTATUS',
            ),
        );

        $vendentries = array();
        $whseentries = array();
        $compentries = array();

        $numProcessedItems = 0;
        do {
            // IN clause max of 500
            $max = ($itemCount > $InLimit) ? $InLimit : $itemCount;
            $itemIDs = array();

            for ($i = $numProcessedItems; $i < $max + $numProcessedItems; $i++) {
                $item = $items[$i];
                $itemIDs[] = $item['ITEMID'];
                $links[$item['ITEMID']] = $i;
            }


            $itmVendEntryParams['filters'] = array (array (array('ITEMID','IN',$itemIDs)));
            $itmWhseEntryParams['filters'] = array (array (array('ITEMID','IN',$itemIDs)));
            $itmCompEntryParams['filters'] = array (array (array('ITEMID','IN',$itemIDs)));

            $newVendEntries = $itmVendorMgr->GetList($itmVendEntryParams);
            $vendentries = INTACCTarray_merge($vendentries, $newVendEntries);

            $newWhseEntries = $itmWhseMgr->GetList($itmWhseEntryParams);
            $whseentries = INTACCTarray_merge($whseentries, $newWhseEntries);

            $newCompEntries = $itmCompMgr->GetList($itmCompEntryParams);
            $compentries = INTACCTarray_merge($compentries, $newCompEntries);

            $numProcessedItems+=$max;
            $itemCount -= $InLimit;

        } while ($itemCount > 0) ;

        foreach ( $vendentries as $vendentry) {
            $itemid = $vendentry['ITEMID'];
            /** @noinspection PhpUndefinedVariableInspection */
            $items[$links[$itemid]]['VENDOR_INFO'][] = $vendentry;
        }

        foreach ($whseentries as $whseentry) {
            $itemid = $whseentry['ITEMID'];
            $whseid = $whseentry['WAREHOUSEID'];
            $itmWhseStdCostEntryParams['filters'] = array (array (array('ITEMID','=',$itemid), array('WAREHOUSEID','=',$whseid)));
            $whseStdCostEntries = $itmwhsestdcostMgr->GetList($itmWhseStdCostEntryParams);

            foreach ($whseStdCostEntries as $whseStdCostEntry) {
                $whseentry['STDCOSTENTRIES'][] = $whseStdCostEntry;
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $items[$links[$itemid]]['WAREHOUSE_INFO'][] = $whseentry;
        }

        foreach ($compentries as $compentry) {
            $itemid = $compentry['ITEMID'];
            /** @noinspection PhpUndefinedVariableInspection */
            $items[$links[$itemid]]['COMPONENT_INFO'][] = $compentry;
        }

        return $items;
    }


    /**
     * @param array $values
     *
     * @return array
     */
    private function GetComponentDetails($values)
    {
        foreach ($values as $compkey => $compval) {
            //fetch details for the kit component and add avg cost if cost method is average
            $filterUser = array(
                'selects' => array('COST_METHOD', 'AVERAGE_COST'),
                'filters' => array(
                    array(
                        array('ITEMID', '=', $compval['COMPONENTKEY'])
                    )
                )
            );
            $comprec =  $this->GetList($filterUser);
            $values[$compkey]['AVERAGE_COST'] = ($comprec['COST_METHOD'] == 'A') ? $comprec['AVERAGE_COST'] : '';
        }
        return $values;
    }


    /**
     * @param string    $ID
     * @param float     $qty
     *
     * @return int
     */
    public function GetBasePrice($ID, $qty)
    {
        $res = $this->DoQuery('QRY_ITEM_GETBASEPRICE', array($ID, $qty));
        if (!isset($res[0])) {
            return 0;
        }

        //If we have more than one base price list entries, we need to look for the one we created in ItemManager::SetPrice
        //and return that. If we don't have it, we need to look for the one we created in csvimport_pricelist.cls and return that.
        //Otherwise we will just return the first index one. When a user create/edit an item we always create a base price entry
        //in the ItemManager::SetPrice.
        if (count($res) > 1) {
            $priceEntryCreatedByItemMgrKey = -1;
            $priceEntryCreatedByImportKey = -1;
            foreach ($res as $key => $priceEntry) {
                if ($priceEntry['QTYLIMITMIN'] === self::BASEPRICEENTRY_QTYLIMITMIN_ITEMMGR
                    && $priceEntry['QTYLIMITMAX'] === self::BASEPRICEENTRY_QTYLIMITMAX_ITEMMGR) {
                    $priceEntryCreatedByItemMgrKey = $key;
                } else if ($priceEntry['QTYLIMITMIN'] === self::BASEPRICEENTRY_QTYLIMITMIN_IMPORT
                    && $priceEntry['QTYLIMITMAX'] === self::BASEPRICEENTRY_QTYLIMITMAX_IMPORT) {
                    $priceEntryCreatedByImportKey = $key;
                } else if ($priceEntryCreatedByItemMgrKey !== -1 && $priceEntryCreatedByImportKey !== -1) {
                    break;
                }
            }
            if ($priceEntryCreatedByItemMgrKey !== -1) {
                return $res[$priceEntryCreatedByItemMgrKey]['BASEPRICE'];
            } else if ($priceEntryCreatedByImportKey !== -1) {
                return $res[$priceEntryCreatedByImportKey]['BASEPRICE'];
            }
        }

        //Can't find a base price list entry created by us (ItemMgr) or by csv import, we will just return the first one.
        //Once the item is edited, we (ItemMgr) will create a price list entry.
        return $res[0]['BASEPRICE'];
    }

    /**
     * @param string $ID
     *
     * @return array|int
     */
    public function ItemFetch($ID)
    {
        //First search from the beginiing
        $qry = 'QRY_DOCUMENT_GET_ITEM_SINGLE';
        $escID = addcslashes($ID, '_');
        $args = array ($escID."%");
        $res = $this->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $qry = 'QRY_DOCUMENT_GET_ITEM_SINGLE_CASE_INSENSITIVE';
            $escID = addcslashes(isl_strtolower($ID), '_');
            $args = array ($escID."%");
            $res = $this->DoQuery($qry, $args);
        }

        if (!isset($res[0])) {
            $qry = 'QRY_DOCUMENT_GET_ITEM_SINGLE_BY_NAME';
            $escID = addcslashes($ID, '_');
            $args = array ($escID."%");
            $res = $this->DoQuery($qry, $args);
        }

        if (!isset($res[0])) {
            $qry = 'QRY_DOCUMENT_GET_ITEM_SINGLE_CASE_INSENSITIVE_BY_NAME';
            $escID = addcslashes(isl_strtolower($ID), '_');
            $args = array (isl_strtolower($escID)."%");
            $res = $this->DoQuery($qry, $args);
        }

        if (!isset($res[0])) {
            return 0;
        }
        return $res;
    }


    /**
     * @param string $ID
     * @param string $kitid
     *
     * @return array
     */
    function GetKitItemDesc($ID,/** @noinspection PhpUnusedParameterInspection */ $kitid)
    {

        $qry = 'QRY_ICITEM_SELECT_SINGLE_ITEMDESC';
        $args = array ($ID);
        $res = $this->DoQuery($qry, $args);
        return $res;
    }

    /**
     * @param string $ID
     * @param string $kitid
     *
     * @return array|int
     */
    function GetKitItemCost($ID,$kitid)
    {

        $qry = 'QRY_ICITEM_SELECT_SINGLE_ITEMDESC';
        $args = array ($ID);
        $res = $this->DoQuery($qry, $args);
        $StdCost=0;

        if (!isset($res[0])) {
            return 0;
        }else{
            if ($res[0]['ITEMTYPE']=='K') {
                $qry = 'QRY_ICITEM_SELECT_ITEMCOST';
                $companyid=GetMyCompany();
                $args = array ($companyid,$companyid,$ID,$companyid);
                $KitItem = $this->DoQuery($qry, $args);

                foreach( $KitItem as $key => $val){
                    if ($KitItem[$key]['ITEMID']==$kitid) {
                        $KitItem[0]['COSTMETHOD']='X';
                        return $KitItem;
                    }
                }

                foreach( $KitItem as $key => $val){
                    if ($KitItem[$key]['ITEMTYPE']=='K') {
                        unset($KitItem[$key]);
                    }
                    else{
                        unset($KitItem[$key]['PARENTID'], $KitItem[$key]['ITEMTYPE'], $KitItem[$key]['CURRENTROWNUM'] , $KitItem[$key]['ANCESTORROWNUMS']);
                    }
                }

                foreach ($KitItem as $item) {
                    if ($item['COST_METHOD']=='S') {
                        if(isset($item['STANDARD_COST'])) {
                            $StdCost=$StdCost + bcmul($item['STANDARD_COST'], $item['QUANTITY']);
                            $res[0]['COSTMETHOD']=$item['COST_METHOD'];
                        }
                    }elseif ($item['COST_METHOD']=='A') {
                        $tempitem = $this->GetRaw($item['ITEMID']);
                        $tempitem=$tempitem[0];
                        $StdCost=$StdCost + bcmul($tempitem['AVERAGE_COST'], $item['QUANTITY']);
                        $res[0]['COSTMETHOD']=$item['COST_METHOD'];
                    }
                    else{
                        $res[0]['STANDARDCOST']=0;
                        $res[0]['COSTMETHOD']=$item['COST_METHOD'];
                        return $res;
                    }
                }
                $res[0]['STANDARDCOST']=$StdCost;
                return $res;
            }
            else{
                return $res;
            }
        }
    }


    /**
     * @param string $ID
     *
     * @return array
     */
    function GetKitComponents($ID)
    {
        $companyid=GetMyCompany();

        //get kit details
        $kitid= $ID;
        $kitargs = array($kitid,$companyid);
        $kitargtypes = array( 'text', 'integer');

        $kitcode = array(
            'QUERY'=> "select itemid,name,icuom.unit,case
			when COST_METHOD='S' then 'STANDARD'  
			when COST_METHOD='A' then 'AVERAGE'  
			when COST_METHOD='L' then 'LIFO'  
			when COST_METHOD='F' then 'FIFO'  
			END  as COST_METHOD, itemtype from icitem,icuom where icitem.std_uom =icuom.record#  and icitem.cny# = icuom.cny# and itemid= ? and icitem.cny#=?",
            'ARGTYPES' => $kitargtypes
        );

        $kit = $this->_QM->DoCustomQuery($kitcode, $kitargs, true);

        $code = array(
            'QUERY' => "select ItemList.itemkey as parentid,ItemList.name as component_id,icitem.name as component_description ,
		 ItemList.quantity  as quantity, ItemList.UOM as UOM,ItemList.cost as STD_COST,
		 case
			when ItemList.COST_METHOD='S' then 'STANDARD'  
			when ItemList.COST_METHOD='A' then 'AVERAGE'  
			when ItemList.COST_METHOD='L' then 'LIFO'  
			when ItemList.COST_METHOD='F' then 'FIFO'  
			END  as COST_METHOD,ICITEM.ITEMTYPE from icitem,
 (select distinct kititem.cny#, kititem.record#,kititem.itemkey,
kititem.componentkey as name,kititem.COST_METHOD,kititem.COST,icitem.itemtype,
kititem.quantity as quantity,kititem.unit as UOM,icitem.sunit_factor
					from 
					(select distinct icitemcomponent.cny#, icitemcomponent.record#,icitemcomponent.itemkey,
icitemcomponent.componentkey ,icitem.COST_METHOD,icitemcomponent.COST/icitemcomponent.quantity as cost,icitem.itemtype,
icitemcomponent.quantity,icitemcomponent.unit,icitem.sunit_factor
					from icitemcomponent, icitem
					where icitem.cny#=icitemcomponent.cny#
						and icitemcomponent.componentkey = icitem.itemid ) kititem,
						 icitem
					where kititem.cny# = ?
						and icitem.cny#=kititem.cny#
						and kititem.itemkey = icitem.itemid
						
					start with kititem.cny# = ? and 
								kititem.itemkey= ? and
								icitem.cny#=kititem.cny# and 
								kititem.itemkey=icitem.itemid
					connect by kititem.itemkey = PRIOR kititem.componentkey and 
								kititem.cny# = ? and 
								icitem.cny#=kititem.cny# and 
								kititem.itemkey=icitem.itemid and
								kititem.itemtype = 'SK'
					order by kititem.record#) ItemList
							
							where icitem.cny# = ?
							and icitem.cny# = ItemList.cny#
							and icitem.itemid = ItemList.name order by ItemList.record# ",
            'ARGTYPES' => array('integer','integer','text', 'integer','integer'),
        );
        $args = array ($companyid,$companyid,$kitid,$companyid,$companyid);

        $KitItem = $this->_QM->DoCustomQuery($code, $args, true);

        $rec1=$KitItem;
        $rec2=$KitItem;

        foreach( $rec1 as $key1 => $val1){
            foreach( $rec2 as $key2 => $val2){
                if ($rec1[$key1]['COMPONENT_ID']==$rec2[$key2]['PARENTID']) {
                    $rec1[$key2]['QUANTITY']=ibcmul($rec1[$key1]['QUANTITY'], $rec2[$key2]['QUANTITY'], 8, true);
                }
            }
        }

        $rec=$rec1;
        foreach( $rec as $key => $val){
            if ($rec[$key]['ITEMTYPE']=='K') {
                unset($rec[$key]);
            }
            else{
                unset($rec[$key]['PARENTID'], $rec[$key]['ITEMTYPE']);
                /** @noinspection PhpUndefinedVariableInspection */
                $itemid= $itemid . "'" . $rec[$key]['COMPONENT_ID'] . "',";
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $itemid = "" . isl_substr($itemid, 0, isl_strlen($itemid) - 1) . "";
        // Get details for kit itself and then replace the kitid in ITEMID returned by that function with the
        // components list obtained here, and add the ITEMTYPE to the list
        $recnew=$this->GetKitItemCost($ID, '');
        $recnew[0]['ITEMID']=$itemid;
        $recnew[0]['ITEMTYPE']= $kit[0]['ITEMTYPE'];
        return $recnew;
    }

    /**
     * @param string $ID
     *
     * @return array
     */
    function GetKitComponentsValues($ID)
    {
        $companyid=GetMyCompany();

        //get kit details
        $kitid= $ID;

        $code = array(
            'QUERY' => "select ItemList.itemkey as parentid, ItemList.name as component_id, icitem.name as component_description,
		 ItemList.quantity as quantity, ItemList.UOM as UOM, ItemList.cost as STD_COST,
		 icitem.cnrevenuetemplkey, icitem.cnrevenue2templkey,ItemList.revpercent,ItemList.kcdlvrstatus,ItemList.kcrevdefstatus,
		 case
			when ItemList.COST_METHOD='S' then 'STANDARD'  
			when ItemList.COST_METHOD='A' then 'AVERAGE'  
			when ItemList.COST_METHOD='L' then 'LIFO'  
			when ItemList.COST_METHOD='F' then 'FIFO'  
			END  as COST_METHOD,ICITEM.ITEMTYPE from icitem,
 (select distinct kititem.cny#, kititem.record#,kititem.itemkey,
kititem.componentkey as name,kititem.COST_METHOD,kititem.COST,icitem.itemtype,
kititem.quantity as quantity,kititem.unit as UOM,icitem.sunit_factor,
kititem.revpercent,kititem.kcdlvrstatus,kititem.kcrevdefstatus
					from 
					(select distinct icitemcomponent.cny#, icitemcomponent.record#,icitemcomponent.itemkey,
icitemcomponent.componentkey ,icitem.COST_METHOD,icitemcomponent.COST/icitemcomponent.quantity as cost,icitem.itemtype,
icitemcomponent.quantity,icitemcomponent.unit,icitem.sunit_factor,
icitemcomponent.revpercent,icitemcomponent.kcdlvrstatus,icitemcomponent.kcrevdefstatus
					from icitemcomponent, icitem
					where icitem.cny#=icitemcomponent.cny#
						and icitemcomponent.componentkey = icitem.itemid ) kititem,
						 icitem
					where kititem.cny# = ?
						and icitem.cny#=kititem.cny#
						and kititem.itemkey = icitem.itemid
						
					start with kititem.cny# = ? and 
								kititem.itemkey= ? and
								icitem.cny#=kititem.cny# and 
								kititem.itemkey=icitem.itemid
					connect by kititem.itemkey = PRIOR kititem.componentkey and 
								kititem.cny# = ? and 
								icitem.cny#=kititem.cny# and 
								kititem.itemkey=icitem.itemid and
								kititem.itemtype = 'SK'
					order by kititem.record#) ItemList
							
							where icitem.cny# = ?
							and icitem.cny# = ItemList.cny#
							and icitem.itemid = ItemList.name order by ItemList.record# ",
            'ARGTYPES' => array('integer','integer','text', 'integer','integer'),
        );
        $args = [$companyid,$companyid,$kitid,$companyid,$companyid];

        $KitItem = $this->_QM->DoCustomQuery($code, $args, true);

        $rec1=$KitItem;
        $rec2=$KitItem;

        foreach( $rec1 as $key1 => $val1){
            foreach( $rec2 as $key2 => $val2){
                if ($rec1[$key1]['COMPONENT_ID']==$rec2[$key2]['PARENTID']) {
                    $rec1[$key2]['QUANTITY']=ibcmul($rec1[$key1]['QUANTITY'], $rec2[$key2]['QUANTITY'], 8, true);
                }
            }
        }

        $rec=$rec1;
        return $rec;
    }


    /**
     * @param int|null $companyid
     * @param string   $kitid
     *
     * @return bool|string[][]
     */
    private function getKitComponentsSummed(?int $companyid, string $kitid) : array|bool
    {
        $code = array(
            'QUERY'    => "SELECT compList.itemid as component_id, icitem.name as component_description 
                            ,SUM(compList.quantity) as quantity
                            ,compList.UOM as UOM,compList.cost as STD_COST
                            ,CASE
                                WHEN compList.COST_METHOD='S' THEN 'STANDARD'  
                                WHEN compList.COST_METHOD='A' THEN 'AVERAGE'  
                                WHEN compList.COST_METHOD='L' THEN 'LIFO'  
                                WHEN compList.COST_METHOD='F' THEN 'FIFO'  
                                END  as COST_METHOD
                            ,icitem.ITEMTYPE 
                        FROM icitem
                         ,(   SELECT iic.cny#, iic.record#, iic.itemkey as parentid, iic.componentkey as itemid
                                    ,kitComp.standard_cost as standard_cost, kitComp.cost_method as COST_METHOD
                                    ,round(inv_utils.eval(ltrim(sys_connect_by_path(iic.quantity, '*'), '*')),10)  as quantity
                                    ,kitComp.itemtype
                                    ,round(inv_utils.eval(ltrim(sys_connect_by_path(round(iic.revpercent/100,10), '*'), '*'))*100,10)  as revpercent
                                    ,iic.unit as UOM, iic.COST/iic.quantity as cost
                                    ,iic.KCDLVRSTATUS, iic.KCREVDEFSTATUS
                                    ,kitComp.sunit_factor, kitComp.record# as componentdimkey
                                FROM icitemcomponent iic
                                    INNER JOIN icitem kitComp on kitComp.CNY# = iic.CNY# AND kitComp.ITEMID = iic.componentkey 
                                WHERE 
                                     kitComp.CNY# = ?
                                START WITH kitComp.cny# = ?
                                    AND iic.itemKey = ? 
                                    AND iic.CNY# = kitComp.CNY#
                                CONNECT BY iic.itemkey = PRIOR iic.componentkey
                                    AND iic.cny# = PRIOR iic.cny#
                                    AND PRIOR kitComp.itemtype NOT IN ('SK')
                                    AND iic.cny# = ?
                                ORDER BY iic.record# desc
                         ) compList
                    WHERE icitem.cny# = ?
                    AND icitem.cny# = compList.cny#
                    AND icitem.itemtype in ('I','SK','K')
                    AND icitem.itemid = compList.itemid 
                    GROUP BY  compList.itemid, icitem.name  
                             ,compList.UOM, compList.cost, compList.COST_METHOD
                            ,icitem.ITEMTYPE 
                    ORDER BY compList.itemid",
            'ARGTYPES' => array( 'integer', 'integer', 'text', 'integer', 'integer' ),
        );
        $args = array( $companyid, $companyid, $kitid, $companyid, $companyid );

        $kitComponents = $this->_QM->DoCustomQuery($code, $args, true);

        return $kitComponents;
    }
    /**
     * @param string    $ID
     * @param string    $whseid
     * @param float     $qty
     *
     * @return string
     */
    function GetKitItemQty($ID,$whseid,$qty)
    {
        $companyid=GetMyCompany();

        //get kit details
        $kitid= $ID;
        $kitargs = array($kitid,$companyid);
        $kitargtypes = array( 'text', 'integer');

        $kitcode = array(
            'QUERY'=> "select icitem.itemid, icitem.name,salesuom.unit,
            case
			 when COST_METHOD='S' then 'STANDARD'  
			 when COST_METHOD='A' then 'AVERAGE'  
			 when COST_METHOD='L' then 'LIFO'  
			 when COST_METHOD='F' then 'FIFO'  
			END  as COST_METHOD 
            from icitem, icuomgrp uomgrp, icuom salesuom 
            where icitem.cny# = uomgrp.cny#(+)
			and icitem.uomgrpkey = uomgrp.record# (+)
			and salesuom.cny#(+) = uomgrp.cny# 
			and uomgrp.record# = salesuom.grpkey (+) 
			and salesuom.record# (+) = uomgrp.sodefunitkey 
            and itemid= ? 
            and icitem.cny#=?",
            'ARGTYPES' => $kitargtypes
        );

        $kit = $this->_QM->DoCustomQuery($kitcode, $kitargs, true);

        $rec=$this->getKitComponentsSummed($companyid, $kitid);
        $items = [];
        foreach( $rec as $key => $val){
            if ($rec[$key]['ITEMTYPE']=='K') {
                unset($rec[$key]);
            }
            else{
                unset($rec[$key]['ITEMTYPE']);
                $items[] = $rec[$key]['COMPONENT_ID'];
            }
        }

        $rec = is_array($rec) ? array_values($rec) : [];

        if (empty($items)) {
            $itemsqty = [];
        } else {
            $qry = [];
            $qry[] = "select warehousekey,itemkey,sum(qtyonhand) as QUANTITY from v_itemavail where warehousekey = :2 and cny#=:1 ";
            $qry[] = $companyid;
            $qry[] = $whseid;
            $qry = PrepINClauseStmt($qry, $items, " and itemkey ");
            $qry[0] .= " group by warehousekey,itemkey";
            $itemsqty = QueryResult($qry);
            if ($itemsqty === false) {
                $itemsqty = [];
            }
        }

        $this->_itemsqty = $itemsqty;
        $warehouseargs = array($whseid,$companyid);
        $warehouseargtypes = array( 'text', 'integer');
        $warehousecode = array(
            'QUERY'=> "SELECT location_no warehousekey FROM icwarehouse where location_no 	=? and cny#=? group by location_no",
            'ARGTYPES' => $warehouseargtypes
        );

        // moved the query into here because the one in qry file is putting an or between the item and product line ids
        $warehouse = (array) $this->_QM->DoCustomQuery($warehousecode, $warehouseargs, true);
        $this->_warehouse = $warehouse;
        $maxqty    = $qty;

        for($j=0; $j<count($warehouse); $j++) {
            $k=0;
            for($i=count($itemsqty)-1; $i>=0; $i--) {
                if($warehouse[$j]['WAREHOUSEKEY']==$itemsqty[$i]['WAREHOUSEKEY']) {
                    $warehouse[$j]['ITEM'][$k]['ITEMKEY']=$itemsqty[$i]['ITEMKEY'];
                    $warehouse[$j]['ITEM'][$k]['QUANTITY']=$itemsqty[$i]['QUANTITY'];
                }else{
                    $warehouse[$j]['ITEM'][$k]['ITEMKEY']=$itemsqty[$i]['ITEMKEY'];
                    $warehouse[$j]['ITEM'][$k]['QUANTITY']=0;
                }
                ++$k;
            }
        }
        for($i=count($rec)-1; $i>=0; $i--) {
            $rectemp[]=$rec[$i];
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $rec=$rectemp;
        foreach( $warehouse as $k => $v){
            /* @var array $rec1 */
            $rec1=$warehouse[$k]['ITEM'];

            $temparray=array();
            $i=0;
            foreach($rec1 as $key1 => $val1){
                if(!isset($temparray[0])) {
                    $temparray[$i]=$val1;
                    ++$i;
                }else{
                    foreach( $temparray as $key2 => $val2){
                        if ($rec1[$key1]['ITEMKEY']==$temparray[$key2]['ITEMKEY']) {
                            $temparray[$key2]['QUANTITY'] = ibcadd($temparray[$key2]['QUANTITY'], $rec1[$key1]['QUANTITY'], null, false);

                            $found=true;
                        }
                    }
                    /** @noinspection PhpUndefinedVariableInspection */
                    if( $found != true) {
                        $temparray[$i]['ITEMKEY']=$rec1[$key1]['ITEMKEY'];
                        $temparray[$i]['QUANTITY']=$rec1[$key1]['QUANTITY'];
                        ++$i;
                    }
                }
            }
            $warehouse[$k]['ITEM']=$temparray;
        }

        foreach( $warehouse as $warekey => $wareval){
            $itemsqty=$warehouse[$warekey]['ITEM'];

            $qtyvalues = [];
            foreach( $itemsqty as $k => $v){
                foreach( $rec as $key => $val){
                    if($itemsqty[$k]['ITEMKEY']==$rec[$key]['COMPONENT_ID']) {
                        if ($maxqty>0) {
                            $rec[$key]['QUANTITY_FORMAX'] = bcmul($rec[$key]['QUANTITY'], $maxqty);
                            if (isset($itemsqty[$k]['QUANTITY'])) {
                                $rec[$key]['QUANTITY_REQUIRED'] = ibcsub($rec[$key]['QUANTITY_FORMAX'], $itemsqty[$k]['QUANTITY'], null, false);
                            }else{
                                $rec[$key]['QUANTITY_REQUIRED'] = $rec[$key]['QUANTITY_FORMAX'];
                            }

                            $rec[$key]['MAXQTY_CHILD'] ='yes';
                        }else{
                            $rec[$key]['MAXQTY_CHILD'] ='no';
                        }
                        $qtyvalues[] = bcdiv($itemsqty[$k]['QUANTITY'], $rec[$key]['QUANTITY']);
                    }
                }
            }

            $minvalue = $qtyvalues[0] ?? 0;
            for($i=0; $i<count($qtyvalues)-1; $i++) {
                if ($i==0) {
                    $minvalue = $qtyvalues[$i];
                }else{
                    $minvalue = min($minvalue, min($qtyvalues[$i], $qtyvalues[$i+1]));
                }
            }

            if($minvalue<1) {
                $possiblevalue=0;
            }else{
                $possiblevalue=floor($minvalue);
            }

            $kit[0]['POSSIBLE_UNITS']=$possiblevalue;
            if ($maxqty>0) {
                $kit[0]['PREFERRED_UNITS']=$maxqty;
            }

            if ($maxqty>0) {
                foreach( $rec as $key => $val){
                    if(!isset($rec[$key]['QUANTITY_REQUIRED'])) {
                        $rec[$key]['QUANTITY_FORMAX'] = bcmul($rec[$key]['QUANTITY'], $maxqty);
                        $rec[$key]['QUANTITY_REQUIRED'] = $rec[$key]['QUANTITY_FORMAX'];
                        $rec[$key]['MAXQTY_CHILD'] ='yes';
                    }
                }
            }

            $items=$rec;
            $kit[0]['COMPONENT']=$rec;
            $warehouse[$warekey]['KIT']=$kit;
            unset($warehouse[$warekey]['ITEM']);
        }
        /** @noinspection PhpUndefinedVariableInspection */
        $this->_items = $items;


        $message =I18N::getSingleToken( "IA.KIT_ITEM_ONLY_QTY_ON_HAND_IN_WAREHOUSE_WARNING", [['name' => 'QTY', 'value' => $possiblevalue]]);
        $message= "<p> $message </p> <ol type='1'> ";
        $Initialmessage=$message;
        foreach ($items as $v) {
            // checking is_array($v) php 8.1
            if (is_array($v) && $v['QUANTITY_REQUIRED'] > 0) {
                $compText= I18N::getSingleToken( "IA.KIT_COMPONENT_ID_QTY_REQUIRED_QTY_MISSING_WARNING",[['name' => 'COMPONENT_ID', 'value' => $v['COMPONENT_ID']]
                    ,['name' => 'QTY_REQUIRED', 'value' => $v['QUANTITY_FORMAX']],['name' => 'QTY_MISSING', 'value' => $v['QUANTITY_REQUIRED']]]);
                $message .= "<li> $compText </li>";
            }
        }
        if($Initialmessage==$message) {
            $message='';
        }else{
            $message .= '</ol>';
        }

        return $message;
    }


    /**
     * @param array  $itemsArr
     * @param bool   $refresh
     * @param array  $fields
     * @param string $mod
     *
     * @return array
     */
    public function GetItemsRawCache($itemsArr, $refresh = false, $fields = array(), $mod='')
    {
        if (!empty($fields) ) {
            switch ($mod) {
                case 'so':
                    if(!in_array('NUMDEC_SALE', $fields)){
                        array_push($fields, 'NUMDEC_SALE');
                    }
                    break;

                case 'po':
                    if( !in_array('NUMDEC_PUR', $fields)){
                        array_push($fields, 'NUMDEC_PUR');
                    }
                    break;

                case 'inv':
                    if(!in_array('NUMDEC_STD', $fields)){
                        array_push($fields, 'NUMDEC_STD');
                    }
                    break;
            }
            $fieldList = implode(',', $fields);
        } else{
            $fieldList = '*';
        }

        if ( (!empty($itemsArr))
            && ($refresh || empty($this->itemCache)
                || empty($this->itemCache[$fieldList]) )
        ) {
            $stmt = array();
            $stmt[0] = "SELECT $fieldList FROM icitem WHERE cny# = :1 ";
            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, $itemsArr, " and icitem.itemid ");
            $res = QueryResult($stmt);

            $this->itemCache[$fieldList] = array();

            $itemcnt = Util::countOrZero($res);
            if ($itemcnt > 0) {
                for ($j = 0; $j < $itemcnt ; $j++) {
                    $res[$j]['ITEMRECORDNO'] = $res[$j]['RECORD#'];
                    $res[$j]['ISSERIALIZED'] = $this->IsItemSerialized($res[$j]['ITEMID'], true, $res[$j]);
                    if (!empty($mod)) {
                        $res[$j]['PRECISION'] = $this->_lookUpItemPrecision($res[$j], $mod);
                    }
                    $this->itemCache[$fieldList][$res[$j]['ITEMID']] = $res[$j];
                }
            }
        }
        return $this->itemCache[$fieldList];
    }

    /**
     * @param array        $entry
     * @param string[][][] $uomInfoVals
     * @param string       $conversion    A decimal value for the conversion multiplier
     * @param string       $uomPrecission An integer value for decimal precision
     */
    public function GetLineEntry_UOMPrecissionInfo($entry, $uomInfoVals, &$conversion, &$uomPrecission)
    {
        list($itemId) = explode('--', $entry['ITEMID']);

        $uomInfo = $uomInfoVals[$itemId][$entry['UNIT']];

        // Get the conversion factor
        $conversion        = $uomInfo['CONVFACTOR'] ?: self::DEFAULT_CONV_FACTOR;
        $uomPrecission     = $uomInfo['NUMDEC'] ?: 0;
        $uom_is_base = $uomInfo['ISBASE'] ?: 'F';

        /*
        if ($entry['UNIT'] != $uomInfo['STD_UNIT']) {
        if ($entry['UNIT'] == $uomInfo['PUR_UNIT']) {
        $conversion	= $uomInfo['PUNIT_FACTOR'];
        $uomPrecission = $uomInfo['PUR_DEC'];
        } elseif ($entry['UNIT'] == $uomInfo['SAL_UNIT']) {
        $conversion	= $uomInfo['SUNIT_FACTOR'];
        $uomPrecission = $uomInfo['SAL_DEC'];
        }
        }else{
        $uomPrecission = $uomInfo['STD_DEC'];
        }
        */

        $uomPrecission = ($uomInfo['ISSYSTEM'] == 'T') ? self::DEFAULT_UOM_PRECISION : $uomPrecission;
        $uomPrecission = ($uomPrecission > 0 && $uom_is_base != 'T') ? $uomPrecission : self::DEFAULT_UOM_PRECISION;
    }


    /**
     * @param string[] $itemarray
     * @param bool     $itemidAsKey
     * @param bool     $defaultPrecision
     * @param bool     $translateSystemUOMNames If true, translate system UOM group (and unit) names
     *
     * @return string[][][]|string[][]|false
     */
    public function GetUOMInfoCache($itemarray, $itemidAsKey = false, $defaultPrecision = true,
                                    $translateSystemUOMNames = false)
    {

        $uomGroupManager = Globals::$g->gManagerFactory->getManager("uom");
        $stmt = array();
        $stmt[0] = 'select icitem.itemid, icitem.cost_method, u1.record#, u1.unit, u1.numdec, u1.isbase, u1.convfactor, 
                    u1.convfactor factor, uomgrp.name, uomgrp.issystem, uomgrp.record# grpkey
					FROM icitem, icuom u1, icuomgrp uomgrp
					WHERE
					uomgrp.cny# (+)= icitem.cny# and uomgrp.record# (+)= icitem.uomgrpkey and u1.cny# (+)= icitem.cny# and u1.grpkey (+)= icitem.uomgrpkey and icitem.cny# = :1 ';
        $stmt[1] = GetMyCompany();
        $stmt = PrepINClauseStmt($stmt, $itemarray, " and icitem.itemid ");
        $res = QueryResult($stmt);
        //eppp_p($res);dieFL();
        if ($res !== false && $itemidAsKey) {
            $itemUOMcache = ['UNIT_RECORDNOS' => []];
            $uomCnt = Util::countOrZero($res);
            if ($uomCnt > 0) {
                for ($j = 0; $j < $uomCnt ; $j++) {
                    $res[$j]['NUMDEC'] = $res[$j]['NUMDEC'] ?: ( $defaultPrecision == true ? self::DEFAULT_UOM_PRECISION
                        : $res[$j]['NUMDEC'] );
                    $itemUOMcache[strval($res[$j]['ITEMID'])][$res[$j]['UNIT']] = $res[$j];
                    if ($translateSystemUOMNames) {
                        /*
                         * For system UOM groups, we need to retrieve translated names--unfortunately, issystem is
                         * unreliable on occasion, otherwise we could process only those here; instead, always delegate
                         * to the UOMManager to find them all even when issystem is not set.
                         */
                        $translatedSystemUomDetail =
                            $uomGroupManager->getTranslatedSystemUomDetail($res[$j]['GRPKEY'], $res[$j]['RECORD#']);
                        if (!empty($translatedSystemUomDetail)) {
                            $itemUOMcache[strval($res[$j]['ITEMID'])][$translatedSystemUomDetail['UNIT']] =
                                $res[$j];
                        }
                    }
                    $itemUOMcache['UNIT_RECORDNOS'][$res[$j]['RECORD#']] = $res[$j];
                }
            }
            return $itemUOMcache;
        } else {
            return $res;
        }
    }


    /**
     * @param array $itemarray
     * @param bool  $itemidAsKey
     * @param bool  $defaultPrecision
     *
     * @return array
     */
    public function GetDefaultUOMInfoCache($itemarray, $itemidAsKey = false, $defaultPrecision = true)
    {
        $stmt = array();
        $stmt[0] = "select icitem.itemid, u1.record#, u1.unit, u1.numdec, u1.isbase, 
                    u1.convfactor, uomgrp.name, uomgrp.issystem
					FROM icitem, icuom u1, icuomgrp uomgrp
					WHERE
					uomgrp.cny# (+)= icitem.cny# 
					and uomgrp.record# (+)= icitem.uomgrpkey 
					and u1.cny# (+)= icitem.cny# and u1.grpkey (+)= icitem.uomgrpkey 
					and uomgrp.invdefunitkey = u1.record#
					and icitem.cny# = :1 ";
        $stmt[1] = GetMyCompany();
        $stmt = PrepINClauseStmt($stmt, $itemarray, " and icitem.itemid ");
        $res = QueryResult($stmt);

        if ($itemidAsKey) {
            $itemUOMcache = array();
            $uomCnt = Util::countOrZero($res);
            if ($uomCnt > 0) {
                for ($j = 0; $j < $uomCnt ; $j++) {
                    $res[$j]['NUMDEC'] = $res[$j]['NUMDEC'] ?: ( $defaultPrecision == true ? self::DEFAULT_UOM_PRECISION
                        : $res[$j]['NUMDEC'] );
                    $itemUOMcache[strval($res[$j]['ITEMID'])] = $res[$j];
                }
            }
            return $itemUOMcache;
        } else {
            return $res;
        }
    }


    /**
     * @param string    $itemID
     *
     * @return array
     */
    public function GetUOMInfo($itemID)
    {
        $qry = 'QRY_ITEM_GET_UOMINFO';
        $info = $this->DoQuery($qry, array ($itemID));
        return $info[0];
    }


    /**
     * @param array     $itemsArr
     * @param string    $vendid
     * @param array     $warhsArr
     *
     * @return array
     */
    public function GetVendorStockNoCache($itemsArr, $vendid, $warhsArr)
    {
        $vendorStockNoCache = array();

        if (!empty($warhsArr)) {
            $Whsstmt = array();
            $Whsstmt[0] =  'SELECT  iw.ITEMKEY, iw.WAREHOUSEKEY, iv.STOCK_NUMBER 
                    FROM ICITEMWHSE iw
                    INNER JOIN icitemvendor iv ON iv.cny# = iw.cny# AND iv.itemwhsekey = iw.record#
                    WHERE iw.cny#         = :1
                    AND iv.vendorid   = :2';
            $Whsstmt[1] = GetMyCompany();
            $Whsstmt[2] = $vendid;
            $Whsstmt = PrepINClauseStmt($Whsstmt, $itemsArr, " and iw.itemkey ");
            $Whsstmt = PrepINClauseStmt($Whsstmt, $warhsArr, " and iw.warehousekey ");
            $Whsres = QueryResult($Whsstmt);
            //Prepare the Vendor Stock Cache with itemkey and Warehouse Key
            foreach ($Whsres as $Whs) {
                $vendorStockNoCache[$Whs['ITEMKEY']][$Whs['WAREHOUSEKEY']]['STOCK_NUMBER'] = $Whs['STOCK_NUMBER'];
            }
        }

        $stmt = array();
        $stmt[0] = 'select itemkey, stock_number from icitemvendor where vendorid = :1 and cny# = :2 ';
        $stmt[1] = $vendid;
        $stmt[2] = GetMyCompany();
        $stmt = PrepINClauseStmt($stmt, $itemsArr, " and icitemvendor.itemkey ");
        $res = QueryResult($stmt);
        //Prepare the Vendor Stock Cache with only itemkey
        foreach ($res as $r) {
            $vendorStockNoCache[strval($r['ITEMKEY'])]['STOCK_NUMBER'] = $r['STOCK_NUMBER'];
        }
        return $vendorStockNoCache;
    }



    /*

    //item is either the itemid or the full object
    function EnableKitting() {
    return $this->InvModPref['KIT'];
    }


    //item is either the itemid or the full object
    function EnableLightAssembly() {
    return $this->InvModPref['LIGHTASSEMBLY'];

    }

    */

    /**
     * @return string
     */
    function EnableBin()
    {
        global $kINVid;
        GetModulePreferences($kINVid, $InvModPref);

        return $InvModPref['ENABLEBIN'];
    }


    /**
     * @param array|string  $item
     * @param string        $mod
     *
     * @return int
     */
    public function _lookUpItemPrecision($item, $mod = '')
    {
        // all over inventory module it should be the maximum decimal that average costing supports
        if ($mod == 'inv') {
            return self::AVERAGE_COST_DECIMALS;
        }

        global $kINVid, $kSOid, $kPOid;
        //$kINVid = Globals::$g->kINVid;
        //$kSOid = Globals::$g->kSOid;
        //$kPOid = Globals::$g->kPOid;


        if (!is_array($item)) {
            $itemRec = $this->GetRaw($item);
            $item = $itemRec[0];
        }

        $modArray = array('so' => $kSOid, 'po' => $kPOid, 'inv' => $kINVid);
        $precisionFields = array('so' => 'NUMDEC_SALE', 'po' => 'NUMDEC_PUR', 'inv' => 'NUMDEC_STD');

        if ($item[$precisionFields[$mod]] != '') {
            $itemPrecision = $item[$precisionFields[$mod]];
        } else {
            if (!$this->_appPrecision) {
                GetModulePreferences($modArray[$mod], $prefs);
                $this->_appPrecision = ($prefs['ITEMPRECISION']) ?: 2;
            }
            $itemPrecision = $this->_appPrecision;
        }
        return $itemPrecision;
    }

    /**
     * @param array $groupOfValues records to validate
     * @param bool  $fastUpdate    true if input record values are from fast update flow
     *
     * @return bool
     */
    protected function validateAllValues(&$groupOfValues, $fastUpdate = false)
    {
        $ok = parent::validateAllValues($groupOfValues, $fastUpdate);

        if ($fastUpdate || !$ok) {
            // needs to skip validating all fields. Call the parent validateAllValues()
            return $ok;
        }
        $source = "ItemManager::_ValidateNew";

        $gErr = Globals::$g->gErr;
        $kValueDelimiter = &Globals::$g->kValueDelimiter;

        foreach ($groupOfValues as &$values) {
            $values = EntityManager::StructuredToFlat($values);
            $errorsfound = false;
            $object = $this->_schemas[$this->_entity]['basefieldinfo'];

            if ($values['ITEMTYPE'] == NONINV_SO) {
                $hiddenFields = array(
                    'SHIP_WEIGHT', 'COST_METHOD', 'INV_PRECISION', 'WHENLASTRECEIVED',
                    'PURCHASE_UNIT', 'PURCHASE_UNIT_FACTOR', 'PO_PRECISION'
                );

            } else if ($values['ITEMTYPE'] == NONINV_PO) {
                $hiddenFields = array(
                    'SHIP_WEIGHT', 'COST_METHOD', 'INV_PRECISION', 'WHENLASTRECEIVED',
                    'SALES_UNIT', 'SALES_UNIT_FACTOR', 'BASEPRICE', 'STANDARD_COST',
                    'SO_PRECISION', 'WHENLASTSOLD'
                );

            } else if ($values['ITEMTYPE'] == NONINV) {
                $hiddenFields = array('SHIP_WEIGHT', 'INV_PRECISION',);

            } else if ($values['ITEMTYPE'] == KIT) {
                $hiddenFields = array('COST_METHOD', 'PURCHASE_UNIT', 'PURCHASE_UNIT_FACTOR',);
            } else {
                $hiddenFields = [];
            }

            foreach ($object as $fldinfo) {
                foreach ($hiddenFields as $fld) {
                    if ($fldinfo['path'] == $fld) {
                        if (isset($fldinfo['required'])) {
                            $fldinfo['required'] = false;
                        }
                    }
                }
                // In order to include the dynamic field info settings, that may have been made by using the method
                // SetDynamicFieldInfos, retrieve the Field Info again here.
                // $fldinfo = $this->GetFieldInfo($fldinfo['path']);
                $err = false;
                $fieldname = $fldinfo['fullname'];
                $path = $fldinfo['path'];
                $localDelim = $fldinfo['type']['delimiter'] ?? $kValueDelimiter;

                // default validation only validates the top level of the nested object
                // kind of kludgy...
                $validvalues = $this->GetFieldValidValues($fldinfo['type'] ?? null, 1);

                if (((isset($fldinfo['required']) && $fldinfo['required'])
                        || (isset($fldinfo['forcerequired']) && $fldinfo['forcerequired']))
                    && (!isset($values[$path]) || isl_trim($values[$path]) == '')
                ) {
                    $gErr->addIAError(
                        'INV-1151', "$source(" . __FILE__ . ':' . __LINE__ . ')',
                        "Required field '" . $fldinfo['fullname'] . "' is missing.",
                        [ 'FLDINFO_FULLNAME' => $fldinfo['fullname']]
                    );
                    $errorsfound = true;
                    continue;
                } elseif ($validvalues && (isl_trim($values[$path] ?? '') || isl_trim($fldinfo['default'] ?? ''))) {
                    if ((isset($fldinfo['default']) && isl_trim($fldinfo['default']))
                        && !(isset($values[$path]) && isl_trim($values[$path]))
                    ) {
                        $values[$path] = isl_trim($fldinfo['default']);
                    }

                    // This block needs commenting
                    if (in_array($fldinfo['type']['ptype'], array('multienum', 'multipick'))) {
                        $nvalues = $values[$path] ? explode($localDelim, $values[$path]) : array();
                    } else {
                        $nvalues = $values[$path] ? array($values[$path]) : array();
                    }

                    if (((!is_null(array_diff($nvalues, $validvalues))) && (count(array_diff($nvalues, $validvalues)) > 0))) {
                        $err = true;
                    }
                } elseif (!((isset($fldinfo['required']) && $fldinfo['required'])
                        || (isset($fldinfo['forcerequired']) && $fldinfo['forcerequired']))
                    && (!isset($values[$path]) || isl_trim($values[$path]) == '')
                ) {
                    continue;
                    // empty value and non-required is ok
                } elseif (isset($fldinfo['type']['format'])) {
                    $pattern = $fldinfo['type']['format'];
                    // 				epp("checking ($path)" . $values[$path] . " against " . $pattern);
                    if (!isl_preg_match("$pattern", isl_trim($values[$path]))) {
                        epp("failed");
                        $err = true;
                    }
                }
                if (($fldinfo['type']['ptype'] == 'date') && !ValidDate(isl_trim($values[$path]), IADATE_STDFORMAT)) {
                    $err = true;
                }
                if ($err) {
                    $errorsfound = true;
                    $printas = $this->GetPrintAs();
                    $gErr->addIAError(
                        'INV-1152', "$source(" . __FILE__ . ':' . __LINE__ . ')',
                        'Illegal format for ' . $printas . ' : ' . $fieldname . ' ' . $values[$path] . '.',
                        [ 'PRINTAS' => $printas , 'FIELDNAME' => $fieldname,'VALUES_PATH' => $values[$path]]
                    );
                    epp('Error BEGIN');
                    epp("Illegal format for  $fieldname '" . $values[$path] . "'");
                    /** @noinspection PhpUndefinedVariableInspection */
                    epp("Expected format is $pattern");
                    epp("Values Validated were");
                    eppp($values);
                    epp("Path is $path");
                    epp('Error END');
                }
            }
            if (!empty($values['TAXCODE'])) {
                if (GetTaxEngine('so',TaxSolutionManager::TAXSOLUTION_AVALARA) == TaxSolutionManager::TAXMETHOD_I_AVALARA) {
                    //eppp_p('$values["TAXCODE"]');eppp_p($values['TAXCODE']);
                    global $gManagerFactory;
                    //$gManagerFactory = Globals::$g->gManagerFactory;

                    /** @var TaxCodeManager $manager */
                    $manager = $gManagerFactory->getManager('taxcode');
                    $object = $manager->Get($values['TAXCODE']);
                    //eppp_p('$object');eppp_p($object);
                    //dieFL();
                    if (empty($object)) {
                        $gErr->addIAError(
                            'INV-1153', __FILE__ . ':' . __LINE__,
                            $values['TAXCODE'] . ' is not a Valid Avalara Tax Code',
                            [ 'VALUES_TAXCODE' =>  $values['TAXCODE']]
                        );
                        $errorsfound = true;
                    }
                }
            }

            if ($errorsfound) {
                return false;
            }

            $values = $this->FlatToStructured($values);
        }

        return true;
    }

    /**
     * Parameter $fromItemMgr makes sure DoEvent should get call from Add/Set of item through item manager only
     * not from parent class Add/Set to stop the duplication of ims package in ims queue
     * This will help sync base price properly with standard price in Salesforce
     * This function allow any request to delete an Item, since delete can be called only from Item lister
     *
     * @param string $verb
     * @param string $key
     * @param mixed  $param1
     * @param mixed  $param2
     * @param array  $values
     *
     * @param bool   $fastUpdate
     *
     * @return bool
     */
    function DoEvent($verb, $key, $param1 = null, $param2 = null, $values = [], $fastUpdate = false)
    {
        $ok = true;
        if ( $verb == 'Delete' ) {
            $this->deleteChatter($key);
        }

        if ( $param1 || $verb == 'Delete') {
            global $gManagerFactory;
            $subscription = $gManagerFactory->getManager('imssubscription');
            $subscription->substatecache = $this->_substatecache;
            $subscription->FillSubscriptions($verb, 'item', $key);
            $this->doAuditEvent($verb, $key);
            $ok = $ok && $this->doDNSyncEvent($this->_entity, $verb, $key, $param1, $param2, $values);

        }

        return $ok;
    }



    /**
     * @param array $qparams
     *
     * @return string
     */
    function FetchShipto($qparams)
    {
        global $gManagerFactory;

        $_shipto    = $qparams['shiptocontact'];
        $_itemids     = $qparams['itemids'];
        $_mod        = $qparams['mod'];
        $_docparid    = $qparams['docpar'];

        $docparMgr = $gManagerFactory->getManager('documentparams');
        $_docpar = $docparMgr->GetLatestRaw($_docparid);
        $_docpar = $_docpar[0];

        $xmlItems = "";

        // Double quote (") separated items, as it is not allowed in itemid string
        $allitems = explode("\"", $_itemids);
        $itemMgr = $gManagerFactory->getManager('item');

        // Ship to taxability
        $contactMgr = $gManagerFactory->getManager('contact');
        $shiptoraw = $contactMgr->GetRaw($_shipto);
        $shiptoraw = $shiptoraw[0];

        $shiptotaxable = $shiptoraw['TAXABLE'];
        $shiptotaxgroupkey = $shiptoraw['TAXGROUPKEY'];

        $docparkey = $_docpar['RECORD#'];

        foreach($allitems as $itemid) {
            // Line item's tax capability is false by default
            $taxcapable = false;
            $itemtaxable = 'F';

            if($_docpar['ENABLEOVERRIDETAX'] == 'T') {
                // Item taxability
                $itemraw = $itemMgr->GetRaw($itemid);
                $itemraw = $itemraw[0];

                $itemtaxable = $itemraw['TAXABLE'];
                $itemtaxgroupkey = $itemraw['TAXGROUPKEY'];

                $taxcapable = $this->IsTaxCapable(
                    $_mod, $docparkey, $itemtaxgroupkey,
                    $shiptotaxable, $shiptotaxgroupkey
                );
            }

            $taxcapable = $taxcapable ? 'T' : 'F';
            $itemtaxable = ($itemtaxable == '') ? 'F' : $itemtaxable;
            $itemid = isl_htmlspecialchars($itemid);
            $xmlItems .= "<lineitem itemid = \"$itemid\" taxcapable = \"$taxcapable\" taxable=\"$itemtaxable\"/>";
        }

        $xmlStr = "<FetchShipto>".$xmlItems."</FetchShipto>";

        return $xmlStr;
    }


    /**
     * @access public
     * @return bool
     * @throws
     */
    /**
     * @param string    $_mod
     * @param int       $docparkey
     * @param int       $itemtaxgroupkey
     * @param string    $shiptotaxable
     * @param int       $shiptotaxgroupkey
     *
     * @return bool
     */
    public function IsTaxCapable($_mod, $docparkey, $itemtaxgroupkey, $shiptotaxable, $shiptotaxgroupkey)
    {
        // Simple tax
        if($shiptotaxable != 'T') {
            return false;
        }

        // Advance tax
        global $kSOid , $kPOid;
        //$kSOid = Globals::$g->kSOid;
        if($_mod == 'po') {
            $useSchedules = GetPreferenceForProperty($kPOid, 'TAXSCHED');
        } else {
            $useSchedules = GetPreferenceForProperty($kSOid, 'TAXSCHED');
        }

        if($useSchedules == 'T') {
            if($itemtaxgroupkey == "") {
                return false;
            }

            if($shiptotaxgroupkey == "") {
                return false;
            }

            $taxcapable = $this->IsAdvanceTaxCapable(
                $_mod, $docparkey,
                $itemtaxgroupkey, $shiptotaxgroupkey
            );

            return $taxcapable;
        }

        return true;
    }

    /**
     * called by QRequest
     *
     * @param array $qparams
     *
     * @return string
     */
    public function FetchItem($qparams)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $_custvendid = $qparams['custvendid'] ?? '';
        $_shipto    = $qparams['shiptocontact'] ?? '';
        $_billto    = $qparams['billtocontact'] ?? '';
        $_itemid    = $qparams['itemid'];
        $_qty       = $qparams['qty'] ?? '';
        $_whse      = $qparams['whse'] ?? '';
        $_whseIn    = $qparams['whsein'] ?? '';
        $_date      = $qparams['date'];
        $_docparid  = $qparams['docpar'] ?? '';
        $_mod       = $qparams['mod'];
        $_currency  = $qparams['currency'] ?? '';
        $from       = $qparams['from'] ?? '';
        $skipwhseinit = $qparams['skipwhseinit'] ?? '';

        $docparMgr = $gManagerFactory->getManager('documentparams');
        $_docpar = $docparMgr->GetLatestRaw($_docparid);
        $_docpar = $_docpar[0];

        //check to see if we have nested kit.
        if($_mod == 'so' && $_docpar['ENABLEREVREC'] == 'T') {
            $soSetupMgr = $gManagerFactory->getManager('sosetup');
            $soPrefs = $soSetupMgr->get('');

            //if vsoe is enabled, we don't allow nested kit for component level posting
            if( SOSetupManager::isVsoeEnabled($soPrefs) ) {
                $itemObj = $this->Get($_itemid);

                if ($itemObj['ITEMTYPE'] == 'Kit' && $itemObj['REVPOSTING'] == 'Component Level') {
                    foreach($itemObj['COMPONENT_INFO'] as $componentObj)
                    {
                        //return an error message that client js can understand.
                        if ($componentObj['ITEMTYPE1'] == 'K') {
                            $tokens = [
                                ['id' => 'IA.NESTED_KIT_IS_NOT_ALLOWED_IF_MEA_ALLOCATIONS_ARE_ENABLED']
                            ];
                            $textMap = getLocalizedTextWithThrow($tokens);
                            $errorMsg = GT($textMap,'IA.NESTED_KIT_IS_NOT_ALLOWED_IF_MEA_ALLOCATIONS_ARE_ENABLED');
                            $xmlStr = "<FetchItem><item itemid=\"". isl_htmlspecialchars($_itemid) ."\" error=\"$errorMsg\">
                                              </item></FetchItem>";

                            return $xmlStr;
                        }
                    }
                }
            }
        }

        $invtransout = false;
        $invtransin = false;

        if ($_docpar['SALE_PUR_TRANS']=='I' && ($_docpar['UPDINV'] =='V' || $_docpar['UPDINV'] == 'T')) {
            $invtransout = ($_docpar['IN_OUT']=='D') ? true : false;
            $invtransin  = ($_docpar['IN_OUT']=='I') ? true : false;
        }

        $res = $this->ItemFetch($_itemid);
        $res = $res[0];

        $uomGrpName = $res['UOMGRPNAME'];
        if (!$uomGrpName || $uomGrpName == '') {
            global $kINVid;
            //$kINVid = Globals::$g->kINVid;
            GetModulePreferences($kINVid, $invprefs);
            $uomGrpName = $invprefs['DEFAULT_UOMGRP'];
        }
        //LogToFile($uomGrpName);
        $uomXMLstr = "";
        $uomGrpKey = "";
        if ($uomGrpName && $uomGrpName != '') {
            $uomMgr = $gManagerFactory->getManager('uom');
            //$uomGrpVals = $uomMgr->DoQuery('QRY_UOM_SELECT_ALL_UOM_GRPNAME', array ($uomGrpName, $cny));
            $uomGrpVals = $uomMgr->get($uomGrpName);

            // Use the flag as the identifier to pick the right module to default.
            $modArray  = array("inv" => 'INVUOM', "po" => 'POUOM', "so" => 'OEUOM');

            $defUOM = '';
            foreach ( $uomGrpVals['ENTRIES'] as $uom) {
                $defUOM = (($uom['UNIT'] != '') && ($uomGrpVals[$modArray[$_mod]] == $uom['UNIT'])) ? $uom['UNIT'] : '';
                if ($defUOM != '') {
                    break;
                }
                if ($uom['ISBASE'] != '' && $uom['ISBASE'] == 'true') {
                    $baseUOM =  $uom['UNIT'];
                }
            }

            if ($defUOM == '') {
                /** @noinspection PhpUndefinedVariableInspection */
                $defUOM = $baseUOM;
            }

            foreach ( $uomGrpVals['ENTRIES'] as $uom) {
                $isdefault = ($defUOM == $uom['UNIT']) ? true : false;
                $uomXMLstr .= "<uom unit='".htmlspecialchars($uom['UNIT'], ENT_COMPAT)."' rec='".$uom['RECORD#']."' factor='".$uom['CONVFACTOR']."' sel='".$isdefault."' numdec='".$uom['NUMDECIMALS']."'></uom>";
            }
            //LogToFile(pp($uomXMLstr));
            $uomGrpKey = $uomGrpVals['RECORDNO'];
        }

        $_itemid = $res['ITEMID'];
        $cost_method = $res['COST_METHOD'];
        $standardCost = 0;
        $averageCost = 0;

        //prodline will not be set before fetching item from Jscript::AutoFill function. setting it from item rec.
        $_prodline = $res['PRODLINE'];

        //When an item is beling fetched, we looked at the txn TD and see what warehouse initialization method to pick
        //the warehouse for the item to initialize
        $cny = GetMyCompany();
        if ( $skipwhseinit != 'true' && $from != 'WAREHOUSEAVAIL' && $_docpar['WHSE_SEL_METHOD'] == 'A' ) {
            $invavailwhse = $this->DoQuery('QRY_ITEM_INVAVAIL_WHSE', array($_itemid,$cny));
            $invavailwhse = $invavailwhse[0];
            if(isset($invavailwhse)) {
                $_whse = $invavailwhse['WAREHOUSEKEY'];
            }
        }

        $warehouselocation = '';
        $warehouselocationrec = '';
        $isNonInvType = (in_array($res['ITEMTYPE'], array('NI', 'NP', 'NS')));

        if (IsMultiEntityCompany() && !GetContextLocation() && !$isNonInvType && $_whse != '') {
            $warehouselocationRes = QueryResult(
                array(
                    "select l.location_no, l.name, l.record# from locationmst l, icwarehouse w where w.cny#=:1 and w.location_no=:2
                      and w.cny#=l.cny# and w.locationrefkey=l.record#",
                    GetMyCompany(),
                    $_whse
                )
            );
            if (isset($warehouselocationRes[0]['LOCATION_NO'])) {
                $warehouselocation = $warehouselocationRes[0]['LOCATION_NO'] . '--' . $warehouselocationRes[0]['NAME'];
                $warehouselocationrec = $warehouselocationRes[0]['RECORD#'];
            }
        }

        if($res['ITEMTYPE']=='K') {
            $unitFactor = 1;

            if($_mod=='so' && ($res['SUNIT'] != $res['STDUNIT']) && $res['SUNIT'] != '') {
                $unitFactor = $res['SUNIT_FACTOR'];
            }elseif($_mod == 'po' &&  ($res['PUNIT'] != $res['STDUNIT']) && $res['PUNIT'] != '') {
                $unitFactor = $res['PUNIT_FACTOR'];
            }

            $qty = bcmul($_qty, $unitFactor);
            list($whse) = explode("--", $_whse);
            $qty_check = $this->GetKitItemQty($_itemid, $whse, $qty);

            $kitcomponentXMLStr = $this->GetKitComponentDetails($_itemid);
        }

        if ( StkitDocumentManager::isStockableKitComponentTrackingEnabled() && ( $res['ITEMTYPE'] == 'SK' ) ) {
            $kitcomponentXMLStr = $this->GetKitComponentDetails($_itemid);
        }

        $fetchprice = !($invtransin || $invtransout);
        //do not fetch price from price list if the following are true
        //document type - inventory transfer out
        //item type - inventory,Non-invenrory, Non-Inventory(purchase only),Non-Inventory(sales only),Kit
        //cost method - Standard
        if (in_array($res['ITEMTYPE'], array('I', 'NI', 'NP', 'NS', 'K'))) {
            list($wrhouse) = explode("--", $_whse);

            if ($cost_method == 'S') {
                $standardCost = $this->GetStandardCost($_itemid, $wrhouse, $_date);
            } else if ($cost_method == 'A') {
                $averageCost = $this->GetAverageCost($_itemid, $wrhouse, $_date);
            }
        }

        $res['ISSERIALIZED'] = $this->IsItemSerialized($res['ITEMID'], true, $res);
        $price = 0.0;
        // TODO: this is always true since $res just got an element added to it above so either remove this test
        // or move the ISSERIALIZED initialization above
        if ($res) {
            /*
             * Do not replace $_itemid with the escaped itemId--only return it in XML response;
             * backend db queries need the unescaped value.
             */
            $_escapedItemid = isl_htmlspecialchars($res['ITEMID']);
            $name = isl_htmlspecialchars($res['NAME']);
            $desc = isl_htmlspecialchars($res['EXTENDED_DESCRIPTION']);
            $taxable = isl_htmlspecialchars($res['TAXABLE']);
            $dropShip = $res['DROPSHIP'];
            $bto = $res['BUYTOORDER'];
            $prodline = isl_htmlspecialchars($res['PRODLINE']);
            $stdunit = isl_htmlspecialchars($res['STDUNIT']);
            $punit = isl_htmlspecialchars($res['PUNIT']);
            $punit_factor = isl_htmlspecialchars($res['PUNIT_FACTOR']);
            $sunit = isl_htmlspecialchars($res['SUNIT']);
            $sunit_factor = isl_htmlspecialchars($res['SUNIT_FACTOR']);
            $precision = $_mod == 'inv' ? self::AVERAGE_COST_DECIMALS : $res[strtoupper($_mod) . '_PRECISION'];
            $itemtype = isl_htmlspecialchars($res['ITEMTYPE']);
            $noninv_type = isl_htmlspecialchars($res['NONINV_TYPE']);
            $hasstartenddates = isl_htmlspecialchars($res['HASSTARTENDDATES']);
            $termperiod = isl_htmlspecialchars($res['TERMPERIOD']);
            $totalperiods = isl_htmlspecialchars($res['TOTALPERIODS']);
            $computeforshortterm = isl_htmlspecialchars($res['COMPUTEFORSHORTTERM']);
            $standardcost = $standardCost;
            $averagecost = $averageCost;
            $cost_method = isl_htmlspecialchars($res['COST_METHOD']);

            /** @noinspection PhpUndefinedVariableInspection */
            $qtycheck = isl_htmlspecialchars($qty_check);
            $invavailwhse = isl_htmlspecialchars($_whse);

            $enablesno = isl_htmlspecialchars($res['ENABLESNO']);
            $enablelot = isl_htmlspecialchars($res['ENABLELOT']);
            $enablebin = isl_htmlspecialchars($res['ENABLEBIN']);
            $enableexpiration = isl_htmlspecialchars($res['ENABLEEXPIRATION']);
            $enablefulfillment = isl_htmlspecialchars($res['ENABLEFULFILLMENT']);
            $default_conversiontype = (!empty($res['DEFAULTCONVERSIONTYPE'] ?? '') && $res['DEFAULTCONVERSIONTYPE'] == 'P') ? 'Price' : 'Quantity';
            $isserialized = isl_htmlspecialchars($res['ISSERIALIZED']);
            $warehouselocation = isl_htmlspecialchars($warehouselocation);
            if ( $fetchprice ) {
                $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
                $priceParams = $pricingHandler->PrepParams($_custvendid, $_billto, $_shipto, $_date, $_mod);
                $price = $pricingHandler->SuggestPrice($priceParams, $_itemid, $_prodline, $_qty, $_docpar, $_currency);
                if (($price == 0) && !empty($wrhouse) && ($_docpar['DOCID'] == PODocumentManager::SUPPLIESREQUESTDOCTYPE)) {
                    $price = $this->getLastCost($_itemid, $wrhouse, $_date); // default to last cost here
                    if ($price == 0) {
                        $price = $this->GetBasePrice($_itemid, 1);
                    }
                }
            }
            /** @noinspection PhpUndefinedVariableInspection */
            if ( ! $price ) {
                $price = "0.00";
            }
        } else {
            $sunit_factor = 0.0;
            $price = 0.0;
        }
        $qtyDenseArray = [];
        $itemWarehouseKey = $_itemid . '--' . $_whse;
        $qtyDetailXMLStr = '';
        if(($_docpar['SALE_PUR_TRANS']=='S' || $_docpar['IN_OUT']=='D')) {
            if(in_array($from, array('ITEMID','WAREHOUSEAVAIL', 'UIQTY'))) {
                $qtyDenseArray = $this->fetchQuantityTotals(array($_itemid) , array($_whse));
            }
            // If FetchQuantityTotals returns empty array
            if(empty($qtyDenseArray)) {
                $denseArray = [];
                $denseArray['itemkey'] = $_itemid;
                $denseArray['qtyleft'] = "0";
                $denseArray['qtyonhand'] = "0";
                $denseArray['qtyonhold'] = "0";
                $denseArray['qtyonorder'] = "0";
                $denseArray['warehousekey'] = $_whse;
                $qtyDenseArray[$itemWarehouseKey] = $denseArray;
            }

            $itemkey = isl_htmlspecialchars($qtyDenseArray[$itemWarehouseKey]['itemkey']);
            $warehousekey = isl_htmlspecialchars($qtyDenseArray[$itemWarehouseKey]['warehousekey']);
            $qtyleft = $qtyDenseArray[$itemWarehouseKey]['qtyleft'];
            $qtyonhand = $qtyDenseArray[$itemWarehouseKey]['qtyonhand'];
            $qtyonhold = $qtyDenseArray[$itemWarehouseKey]['qtyonhold'];
            $qtyonorder = $qtyDenseArray[$itemWarehouseKey]['qtyonorder'];
            $qtyavailable = $qtyDenseArray[$itemWarehouseKey]['qtyavailable'];
            $qtyuncommitted = $qtyDenseArray[$itemWarehouseKey]['qtyuncommitted'];

            // build string
            $qtyDetailXMLStr .= "<qtydetail ";
            $qtyDetailXMLStr .=  "itemkey= \"$itemkey\"";
            $qtyDetailXMLStr .= " warehousekey= \"$warehousekey\"";
            $qtyDetailXMLStr .= " qtyleft= \"$qtyleft\"";
            $qtyDetailXMLStr .= " qtyonhand= \"$qtyonhand\"";
            $qtyDetailXMLStr .= " qtyonhold= \"$qtyonhold\"";
            $qtyDetailXMLStr .= " qtyonorder= \"$qtyonorder\"";
            $qtyDetailXMLStr .= " qtyavailable= \"$qtyavailable\"";
            $qtyDetailXMLStr .= " qtyuncommitted= \"$qtyuncommitted\"";
            $qtyDetailXMLStr .= " > </qtydetail>";
        }
        //don't remove this line used for sfdc purpose
        //always false as UI from SFDC
        $sfdcpricing = false;

        if (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') {
            include_once 'SforceSynchronizer.cls';
            $sfSynchronizer = new SforceSynchronizer();
            $ProductDetails = $sfSynchronizer->GetProductDetails($_itemid);

            if(!empty($ProductDetails) && is_array($ProductDetails)) {
                //get SFDC Pricing info
                if (($sfSynchronizer->_preferences['SFORCEPRICINGOPT'] == SFORCEPRICING)) {
                    // updating code to fix PHP 8.1 issue 164641
                    // setting $sunit_factor , $ProductDetails['LISTPRICE'] , $ProductDetails['SALESPRICE'] to 0 in case of these are set/null and not numeric value and
                    // converting the values to float.
                    $sunit_factor = isset($sunit_factor) && is_numeric($sunit_factor) ? (float)$sunit_factor : 0;
                    $ProductDetails['LISTPRICE'] = isset($ProductDetails['LISTPRICE']) && is_numeric($ProductDetails['LISTPRICE']) ? (float)$ProductDetails['LISTPRICE'] : 0;
                    $ProductDetails['SALESPRICE'] = isset($ProductDetails['SALESPRICE']) && is_numeric($ProductDetails['SALESPRICE']) ? (float)$ProductDetails['SALESPRICE'] : 0;
                    if ( $sunit_factor != 0 ) {
                        $listprice = $ProductDetails['LISTPRICE']/$sunit_factor;
                        $price = $ProductDetails['SALESPRICE']/$sunit_factor;
                    } else {
                        $listprice = $ProductDetails['LISTPRICE'];
                        $price = $ProductDetails['SALESPRICE'];
                    }
                } else {
                    $listprice = $price;
                    /** @noinspection PhpSillyAssignmentInspection */
                    $price = $price;
                }

                $quantity =  $ProductDetails['QUANTITY'];
                $memo = $ProductDetails['LINE_DESCRIPTION'];
                $servicestartdate = $ProductDetails['SERVICEDATE'];
                $serviceenddate = $ProductDetails['SERVICEENDDATE__C'];
                $sfdcpricing = true;
            }
        }

        // Line item's tax capability is false by default
        $taxcapable = false;
        if($_docpar['ENABLEOVERRIDETAX'] == 'T' && $res['ITEMID'] != "") {

            // Ship to taxability
            $contactMgr = $gManagerFactory->getManager('contact');
            $shiptoraw = $contactMgr->GetRaw($_shipto);
            $shiptoraw = $shiptoraw[0];

            $taxcapable = $this->IsTaxCapable(
                $_mod,
                $_docpar['RECORD#'],
                $res['TAXGROUPKEY'],
                $shiptoraw['TAXABLE'],
                $shiptoraw['TAXGROUPKEY']
            );
        }
        $taxcapable = $taxcapable ? 'T' : 'F';

        $RenewalMacro   =   $this->GetRenewalMacro($_itemid, $_docpar);
        $RenewalMacro    =   isl_htmlspecialchars($RenewalMacro);

        $itemWarehouseInfo = $this->getItemWarehouseBinDefaults($_itemid, $_whse);
        $defaisle = isl_htmlspecialchars($itemWarehouseInfo[0]['DEFAULT_AISLE'] ?? '');
        $defrow   = isl_htmlspecialchars($itemWarehouseInfo[0]['DEFAULT_ROW'] ?? '');
        $defbin   = isl_htmlspecialchars($itemWarehouseInfo[0]['DEFAULT_BIN'] ?? '');
        $binwh    = isl_htmlspecialchars($_whse);
        $defbinIn = '';
        $binwhIn  = '';

        if ($_whseIn != '') {
            $itemWarehouseInfo = $this->getItemWarehouseBinDefaults($_itemid, $_whseIn);
            $defbinIn = isl_htmlspecialchars($itemWarehouseInfo[0]['DEFAULT_BIN'] ?? '');
            $binwhIn  = isl_htmlspecialchars($_whseIn);
        }

        $trackingXml = '';
        if (($_whse != '') && (($qparams['tracking'] ?? false) == true)) {
            $trackingXml = $this->fetchSnLotExpirationInternal($_itemid, $_whse, $_whseIn, $res,
                true);     // could be very large!
        }

        //Get item platform relationship to see if we have item-location relationship
        $warehouselocationrel = '';
        if ($qparams['fetchitemrelationship'] === 'true') {
            $result = Pt_RelationshipController::getRelated('ITEMID', $_escapedItemid);
            if ( is_array($result['related_fields']) ) {
                foreach ( $result['related_fields'] as $field ) {
                    if ($field['field'] === 'LOCATION') {
                        $warehouselocationrel = isl_htmlspecialchars($field['value']);
                        break; //Found it, no need to continue
                    }
                }
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $xmlStr = "<FetchItem>
					<item itemid=\"$_escapedItemid\" 
						name=\"$name\"
						desc=\"$desc\" 
						taxable=\"$taxable\" 
						prodline=\"$prodline\" 
						stdunit=\"$stdunit\" 
						punit=\"$punit\"
						punit_factor=\"$punit_factor\"
						sunit=\"$sunit\"
						sunit_factor=\"$sunit_factor\"
						precision=\"$precision\"
						price=\"$price\"
						itemtype=\"$itemtype\"
						noninv_type=\"$noninv_type\"
						qtycheck=\"$qtycheck\"	
						hasstartenddate=\"$hasStartEndDate\"
						termperiod=\"$termPeriod\"
						totalperiods=\"$totalPeriods\"
						computeforshortterm=\"$computeForShortTerm\"
						listprice=\"$listprice\" 
						quantity = \"$quantity\" 
						qtyavailable = \"$qtyavailable\" 
						qtyuncommitted = \"$qtyuncommitted\" 
						qtyonhand = \"$qtyonhand\" 
						memo = \"$memo\"
						sfdcpricing = \"$sfdcpricing\" 
						servicestartdate = \"$servicestartdate\"
						serviceenddate = \"$serviceenddate\"
			        	hasstartenddates = \"$hasstartenddates\"
			        	termperiod1 = \"$termperiod\"
			        	totalperiods1 = \"$totalperiods\"
			        	computeforshortterm1 = \"$computeforshortterm\"
						standardcost = \"$standardcost\"
						averagecost = \"$averagecost\"
						cost_method = \"$cost_method\"
						invavailwhse =	\"$invavailwhse\"
						enablesno =	\"$enablesno\"
						enablelot =	\"$enablelot\"
                        enablebin =	\"$enablebin\"
                        enableexpiration = \"$enableexpiration\"
						isserialized = \"$isserialized\"
						taxcapable = \"$taxcapable\"
                		renewalmacroid  = \"$RenewalMacro\"
                		dropship = \"$dropShip\"
                		buytoorder = \"$bto\"
                		uomgrpkey = \"$uomGrpKey\"
                		defaisle = \"$defaisle\"
                		defrow = \"$defrow\"
                		defbin = \"$defbin\"
                		binwh = \"$binwh\"
                		defbinIn = \"$defbinIn\"
                		binwhIn = \"$binwhIn\"
                		enablefulfillment = \"$enablefulfillment\"
                		warehouselocation = \"$warehouselocation\"
                		warehouselocationrel = \"$warehouselocationrel\"
                		warehouselocationrec = \"$warehouselocationrec\" 
                		default_conversiontype = \"$default_conversiontype\" >
		                <uomdetail>$uomXMLstr</uomdetail>
		                <qtydetailstr>$qtyDetailXMLStr</qtydetailstr>
		                <kitcomponents>$kitcomponentXMLStr</kitcomponents>
					</item>
					$trackingXml
				</FetchItem>";
        //LogToFile(pp($xmlStr));
        return $xmlStr;
    }


    /**
     * called by QRequest
     *
     * @param array $qparams
     *
     * @return string
     */
    public function fetchSnLotExpiration($qparams)
    {
        $_itemid    = $qparams['itemid'];
        $_whse      = $qparams['whse'] ?? '';
        $_whseIn    = $qparams['whsein'] ?? '';

        $res        = $this->ItemFetch($_itemid);

        $trackingXml = '';
        if (($_whse != '') && (($qparams['tracking'] ?? false) == true)) {
            $trackingXml = $this->fetchSnLotExpirationInternal($_itemid, $_whse, $_whseIn, $res,
                true);     // could be very large!
        }

        return $trackingXml;
    }



    /**
     * @param string    $itemId
     * @param string    $warehouseId
     *
     * @return array|string
     */
    private function getItemWarehouseBinDefaults($itemId, $warehouseId)
    {
        list($itemId)      = explode("--", $itemId);
        list($warehouseId) = explode("--", $warehouseId);

        $recs = [];
        if (($itemId != '') && ($warehouseId != '')) {
            $advancedBins = BinManager::areAdvanedBinsOn();
            $params = array(
                'selects' => $advancedBins ? ['DEFAULT_BIN'] : ['DEFAULT_AISLE', 'DEFAULT_ROW', 'DEFAULT_BIN'],
                'filters' => array(
                    array(
                        array('ITEMID', '=', $itemId),
                        array('WAREHOUSEID', '=', $warehouseId)
                    )
                ),
            );
            $recs = Globals::$g->gManagerFactory->getManager('itemwarehouseinfo')->GetList($params);
        }
        return $recs;
    }

    /**
     * @param string $itemID
     * @param string $whseID
     * @param string $effectiveDate
     *
     * @return float
     */
    function GetStandardCost($itemID, $whseID, $effectiveDate)
    {
        list($itemID) = explode("--", $itemID);
        list($whseID) = explode("--", $whseID);

        $key = $itemID . "~" . $whseID . "~".  $effectiveDate;
        if(!array_key_exists($key,$this->stdCostCache)) {
            $standardCost = 0;
            if ( ! empty($whseID) ) {
                if ( empty($effectiveDate) ) {
                    $effectiveDate = (string) GetCurrentDate();
                }
                // fetch the Standard cost from the Warehouse Standard Costs table
                $gManagerFactory = Globals::$g->gManagerFactory;
                $whseStdCostMgr = $gManagerFactory->getManager('itemwarehousestdcost');
                $standardCost = $whseStdCostMgr->GetStandardCostByEffectiveDate($effectiveDate, $itemID, $whseID);
            }

            // if standard cost is 0 then fetch from item header
            if ( $standardCost == 0 && ! IsMCMESubscribed() ) {
                $itemParams = [
                    'selects' => [ 'STANDARD_COST' ],
                    'filters' => [
                        [
                            [ 'ITEMID', '=', $itemID ],
                        ]
                    ],
                ];

                $itemInfo = $this->GetList($itemParams);
                $itemInfo = $itemInfo[0];
                if ( $itemInfo['STANDARD_COST'] && $itemInfo['STANDARD_COST'] > 0 ) {
                    $standardCost = $itemInfo['STANDARD_COST'];
                }
            }
            $this->stdCostCache[$key] = $standardCost;
        }
        return $this->stdCostCache[$key];
    }

    /**
     * @param string $itemID
     * @param string $whseID
     * @param string $date
     * @param float $lastCost
     *
     * @return float
     */
    function GetAverageCost($itemID, $whseID, $date, &$lastCost=0.0)
    {
        list($itemID) = explode("--", $itemID);
        list($whseID) = explode("--", $whseID);

        $averageCost = 0;
        if (!empty($whseID)) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            if (empty($date)) {
                $date = (string)GetCurrentDate();
            }

            $costHistMgr = $gManagerFactory->getManager('costhistory');
            $params = array(
                'selects' => array('ASON', 'UNITCOST', 'LASTCOST'),
                'filters' => array(
                    array(
                        array('ITEMKEY', '=', $itemID),
                        array('WHSEKEY', '=', $whseID),
                        array('ASON', '<=', $date),
                    )
                ),
                'orders' => array(array('ASON', 'desc')),
            );

            $res = $costHistMgr->GetList($params);

            $lastCost =  $res[0]['LASTCOST'];

            if ( $res[0]['UNITCOST'] && $res[0]['UNITCOST']>0 ) {
                $averageCost = $res[0]['UNITCOST'];
            } else if ( $res[0]['LASTCOST'] && $res[0]['LASTCOST']>0 ) {
                $averageCost = $res[0]['LASTCOST'];
            }
        }

        return $averageCost;
    }

    /**
     * @param string $itemID
     * @param string $whseID
     * @param string $date
     *
     * @return float
     */
    function getLastCost($itemID, $whseID, $date)
    {
        $lastCost = 0;
        if (!empty($whseID)) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            if (empty($date)) {
                $date = (string)GetCurrentDate();
            }

            $costHistMgr = $gManagerFactory->getManager('costhistory');
            $params = array(
                'selects' => array('ASON', 'LASTCOST'),
                'filters' => array(
                    array(
                        array('ITEMKEY', '=', $itemID),
                        array('WHSEKEY', '=', $whseID),
                        array('ASON', '<=', $date)
                    )
                ),
                'orders' => array(array('ASON', 'desc')),
            );

            $res = $costHistMgr->GetList($params);

            if (isset($res[0]['LASTCOST'])) {
                $lastCost = $res[0]['LASTCOST'];
            }
        }

        return $lastCost;
    }

    /**
     * @param string $kitID
     *
     * @return string
     */
    function GetKitComponentDetails($kitID){
        $cny = GetMyCompany();
        $kqry  = 'QRY_ICITEM_SELECT_KITCOMPONENTS';
        $kargs = array ($cny,$kitID);
        $kres  = $this->DoQuery($kqry, $kargs);
        $kitcomponentXMLStr = "";
        foreach ( $kres as $kitcomp) {
            $isKitItemSerialized = ($kitcomp['ENABLESNO']=='T' || $kitcomp['ENABLELOT']=='T' || $kitcomp['ENABLEBIN']=='T' || $kitcomp['ENABLEEXPIRATION']=='T');
            $kitcomponentXMLStr .= "<component item='".htmlspecialchars($kitcomp['COMPONENTKEY'],ENT_QUOTES).
                "' no_of_units='".$kitcomp['NO_OF_UNITS'].
                "' unit='".$kitcomp['UNIT'].
                "' enablesno='".$kitcomp['ENABLESNO'].
                "' enablelot='".$kitcomp['ENABLELOT'].
                "' enablebin='".$kitcomp['ENABLEBIN'].
                "' enableexpiration='".$kitcomp['ENABLEEXPIRATION'].
                "' isserialized='".$isKitItemSerialized.
                "' itemtype='".$kitcomp['ITEMTYPE'].
                "'></component>";
        }

        return $kitcomponentXMLStr;
    }


    /**
     * @param array $items
     * @param array $whse
     *
     * @return array
     */
    public function fetchQuantityTotals($items, $whse)
    {
        $itemavailtotal = [];

        if(empty($items) || empty($whse)) {
            return $itemavailtotal;
        }
        $source = "ItemManager::fetchQuantityTotals";

        $stmt    = [];
        $stmt[0] = "SELECT
                    itemkey,
                    warehousekey,
                    SUM(qtyonorder) - SUM(qtyonhold) qtyleft,
                    SUM(qtyonorder) qtyonorder,
                    SUM(qtyonhand) qtyonhand,
                    SUM(qtyonhold) qtyonhold,
                    SUM(qtyintransit) qtyintransit,
                    SUM(qtyreserved) qtyreserved,
                    SUM(qtyallocated) qtyallocated
                FROM
                    (
                        SELECT
                            itemkey,
                            warehousekey,
                            qtyonorder,
                            qtyonhand,
                            qtyonhold,
                            qtyintransit,
                            qtyreserved,
                            qtyallocated
                        FROM
                            v_itemavail
                        WHERE
                            cny# =:1 ";

        $stmt[1] = GetMyCompany();
        // get the unique item values
        $items   = array_unique($items);
        // get the unique warehouse values
        $whse    = array_unique($whse);
        // setting the begin trx.
        // If you dont set begin trx the item cache will be overwritten by warehouse cache
        // noticed this in case JIRA IA-90073
        $this->beginTrx($source);
        // prep the item cache for entity type itemCache
        $stmt    = PrepINClauseStmt($stmt, $items, " and  itemkey ", true,'itemCache');
        // prep the warehouse cache for entity type warehouseCache
        $stmt    = PrepINClauseStmt($stmt, $whse, " and  warehousekey ",true,'warehouseCache');

        $stmt[0] .= " ) qty
                GROUP BY
                    itemkey,
                    warehousekey";

        $res = QueryResult($stmt);
        foreach ( $res as $value) {
            $trimmedValues = array();
            foreach ($value as $trimKey => $trimValue) {
                $trimmedValues[isl_strtolower($trimKey)] = $trimValue;
            }
            $keyIndx = $value['ITEMKEY'] . "--" . $value["WAREHOUSEKEY"];
            $computedTotals = $this->calculateAvailAndUncommittedtotals($trimmedValues['qtyonorder'],
                $trimmedValues['qtyonhand'],
                $trimmedValues['qtyonhold'],
                $trimmedValues['qtyintransit'],
                $trimmedValues['qtyreserved'],
                $trimmedValues['qtyallocated']);
            $trimmedValues['qtyavailable']      = $computedTotals['AVAILABLE'];
            $trimmedValues['qtyuncommitted']    = $computedTotals['UNCOMMITTED'];
            $itemavailtotal[$keyIndx] = $trimmedValues;
        }
        $this->commitTrx($source);

        return $itemavailtotal;
    }


    /**
     * @param array $qparams
     *
     * @return string
     */
    function FetchWarehouseCurrency($qparams)
    {
        $warehouseid  = $qparams['warehouseid'];
        $baseCurrency = $this->GetWarehouseLocationCurrency($warehouseid);
        $xmlStr = "<FetchWarehouseCurrency currency=\"$baseCurrency\"></FetchWarehouseCurrency>";
        return $xmlStr;
    }

    /**
     * @param string $warehouseid
     *
     * @return string
     */
    function GetWarehouseLocationCurrency($warehouseid){

        // first fetch the base currency if we can from the cache;
        if (isset( self::$warehouseCache[$warehouseid]['BASE_CURRENCY'])) {
            return self::$warehouseCache[$warehouseid]['BASE_CURRENCY'];
        }

        // not in the cache, do it old school
        $gManagerFactory = Globals::$g->gManagerFactory;
        $isAtlas = IsMCMESubscribed();
        $baseCurr = '';
        if ($isAtlas) {
            //
            // get the LOCATIONREFKEY from warehouse
            $warehouseInfo  = self::AddToWarehouseCache( $warehouseid );
            $locationRefKey = $warehouseInfo[$warehouseid]['LOCATIONREFKEY'] ?? '';
            //
            // if LOCATIONREFKEY is null
            // not sure what to do

            //
            // get the currency of the location
            if ($locationRefKey != '') {
                $locMgr = $gManagerFactory->getManager('location');
                $locParams['selects'] = array('RECORDNO', 'LOCATIONID', 'NAME');
                $locParams['filters'] = array(array(array('RECORDNO', '=', $locationRefKey)));
                $locRec = $locMgr->GetList($locParams);
                $location = $locRec[0];
                if($location['LOCATIONID']){
                    $baseCurr = GetLocationBaseCurrency($location['LOCATIONID']);
                }
            }
        }else{
            $baseCurr = GetBaseCurrency();
        }
        self::$warehouseCache[$warehouseid]['BASE_CURRENCY'] = $baseCurr;   // cache it for next time
        return $baseCurr;
    }

    /**
     * @param array $qparams
     *
     * @return string
     */
    function FetchWarehouseCurrencyAndReplenishment($qparams)
    {
        $warehouseid  = $qparams['warehouseid'];
        $currency = $this->GetWarehouseLocationCurrency($warehouseid);
        $replenishment = self::GetWarehouseReplenishmentEnableFlag($warehouseid);
        $xmlStr = "<FetchWarehouseCurrencyAndReplenishment currency=\"$currency\" w_enable_replenishment=\"$replenishment\"></FetchWarehouseCurrencyAndReplenishment>";
        return $xmlStr;
    }


    /**
     *      a QuickRequest for warehouse/bin info for a specific warehouse.
     *
     * @param array $qparams
     *
     * @return string
     */
    function fetchBinTrackOptions($qparams)
    {
        $xmlStr = "";
        if (BinManager::areAdvanedBinsOn()) {
            $warehouseid = $qparams['warehouseid'];
            $myqry = array(
                'QUERY'    => "SELECT icbin.binid 
                            FROM icbin, icwarehouse 
                            WHERE icwarehouse.location_no = ? and icbin.cny#=? and icbin.cny#=icwarehouse.cny# and icbin.warehousekey = icwarehouse.record# 
                            ORDER BY binid",
                'ARGTYPES' => array('string', 'integer'),
            );
            $binMgr = Globals::$g->gManagerFactory->getManager('bin');
            $bindensearr = $binMgr->_QM->DoCustomQuery($myqry, [$warehouseid]);

            if (($bindensearr !== false) && (!empty($bindensearr))) {
                foreach ($bindensearr as $row) {
                    $xmlStr .= "<bin id='" . htmlspecialchars($row[0], ENT_COMPAT) . "'></bin>";
                }
            }
        }
        return $xmlStr;
    }


    /**
     *      When reading an existing transaction, we look for what tracking is AVAILABLE, but of course the existing
     *  transaction has already USED UP some/all of what was available.  So, for example, suppose you have a txn with
     *  10 hammers in the tracking and there are CURRENTLY 2 hammers, well, really, there are 12 for this transaction
     *  to have (the 10 it already had plus 2 more)
     *
     *  Here we merge the existing tracking data with the newly read available data; either could be empty arrays
     *
     * @param array     $existingEntries    Existing TRACKINGENTRIES records; must be an array, but can be empty
     * @param array     $resultOfQuery      Current state of affairs (so, NOT including existing records)
     *
     * @return array                        The combinaton of the two arrays, without dups
     */
    private function MergeTrackingOldAndNew( $existingEntries, $resultOfQuery )
    {
        $ret = [];

        // Get faster access to the existing records:
        //  'TRACK_QUANTITY', 'SERIALNO', 'LOTNO', 'EXPIRATION', 'BINID'
        $cache = [];
        foreach ($existingEntries as $key => $query) {
            $recordNumber = $query['RECORDNO'] ?? ($query['RECORD#'] ?? 0); // only matters if it ha been saved
            if ($recordNumber && isset($query['TRACK_QUANTITY']) && ($query['TRACK_QUANTITY'] != 0)) {
                $hint  = ($query['SERIALNO']   ?? '') . '|--|';
                $hint .= ($query['LOTNO']      ?? '') . '|--|';
                $hint .= ($query['EXPIRATION'] ?? '') . '|--|';
                $hint .= ($query['BINKEY']     ?? '') . '|--|';
                if (isset($cache[$hint])) {
                    $existingEntries[$cache[$hint]]['TRACK_QUANTITY'] += $query['TRACK_QUANTITY']; // collapse dups
                } else {
                    $cache[$hint] = $key;
                }
            }
        }

        // query results come from: bins.binid, serialno, lotno, expirationdate, sum(totalQty) qtyleft
        // merge existing entries so each entry has a unique combination of sn/lot/exp/bin
        foreach ($resultOfQuery as $query) {
            $hint  = ($query['SERIALNO']       ?? '') . '|--|';
            $hint .= ($query['LOTNO']          ?? '') . '|--|';
            $hint .= ($query['EXPIRATIONDATE'] ?? '') . '|--|'; // the raw sql field.  OBJECT is 'expiration'
            $hint .= ($query['BINKEY']         ?? '') . '|--|';
            if (isset($cache[$hint])) {
                $key = $cache[$hint];
                $query['QTYLEFT'] += $existingEntries[$key]['TRACK_QUANTITY']; // so add in what was in use before
                unset($cache[$hint]);   // consumed
            }
            $ret[] = $query;
        }

        // now add in existing entries that weren't used above
        foreach ($cache as $key) {
            $rec                    = [];
            $rec['SERIALNO']        = $existingEntries[$key]['SERIALNO'];
            $rec['LOTNO']           = $existingEntries[$key]['LOTNO'];
            $rec['EXPIRATIONDATE']  = $existingEntries[$key]['EXPIRATION']; // again, convert object name to raw sql
            $rec['BINID']           = $existingEntries[$key]['BINID'];
            $rec['BINKEY']          = $existingEntries[$key]['BINKEY'];
            $rec['QTYLEFT']         = $existingEntries[$key]['TRACK_QUANTITY'];
            $rec['ITEMKEY']         = $existingEntries[$key]['ITEMID'];
            $rec['WHSEKEY']         = $existingEntries[$key]['WHSEKEY'];
            $ret[]                  = $rec;
        }
        return $ret;
    }


    /**
     *      a QuickRequest for sn/lot/expiration info for a specific item and warehouse.
     *
     * @param string $itemid                    the item, no dashes
     * @param string $whseFrom                  the 'FROM' warehouse, or the one-and-only warehouse, cannot be empty
     * @param string $whseTo                    the 'TO' warehouse, can be empty
     * @param array  $res                       serial/lot/bin/exp data; if null it will be fetched
     * @param bool   $asXml                     xml or just plain table format suitible for json or whatever?
     * @param array  $existingEntries           factor in existing entries into the returned tracking data
     * @param bool  $deepFetchForItemTypeSK     default true for fetching stockable kits components tracking data
     *
     * @return string|array
     */
    function fetchSnLotExpirationInternal($itemid, $whseFrom, $whseTo, $res,
                                          $asXml = false, $existingEntries = [], $deepFetchForItemTypeSK = true)
    {

        $retXml         = "";
        $retArray       = [];
        list($itemid)   = explode("--", $itemid);
        list($whseFrom) = explode("--", $whseFrom);
        list($whseTo)   = explode("--", $whseTo);

        if ( ! empty($existingEntries) && $asXml) {
            throw new Exception("Code Bug: existing entries only works in NON-XML mode");
        }

        $enableBIN =  $res['ENABLEBIN'] ?? 'F';
        $enableSN =  $res['ENABLESNO'] ?? 'F';
        $enableLOT = $res['ENABLELOT'] ?? 'F';
        $enableEXP = $res['ENABLEEXPIRATION'] ?? 'F';

        $componentsparams = '';

        $count = 3;
        $components = [];
        $components[] = $itemid;
        $componentsparams =  $componentsparams  . ':' . $count++;

        $iskit = false;
        if ( $res['ITEMTYPE'] === 'K'
            || ( StkitDocumentManager::isStockableKitComponentTrackingEnabled()
                && ( $res['ITEMTYPE'] == 'SK' ) && $deepFetchForItemTypeSK) ) {
            $iskit = true;
            $KitComponentsValues = $this->GetKitComponentsValues($itemid);
            // get components for kit
            foreach ($KitComponentsValues as $compoent) {
                $components[] = $compoent['COMPONENT_ID'];
                $componentsparams =  $componentsparams .  ',:' . $count++;
            }
        }


        if (($enableBIN === 'T') || ($enableSN === 'T') ||  ($enableLOT === 'T') || ($enableEXP === 'T') || ($iskit)) {

            // if warehouse fulfillment is enabled, we want to SUBTRACT OUT the allocated items
            $allocated = "";   // no reduction
            if (InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
                $allocated = "UNION SELECT itemid as itemkey, binkey, serialno, lotno, expirationdate, allocatedQuantity as totalQty,
                                           warehouseid as whsekey
                                            FROM    V_INVTRACKINGALLOCATED
                                            WHERE   cny# = :1
                                             AND    itemid in ($componentsparams) AND warehouseid = :2 ";
            }

            // first we want the stuff from the FROM warehouse as a grid
            // note qtyLeft can be zero if the item is allocated (see qry above), so filter those out
            $qry   = [];
            $qry[] = "SELECT itemkey, binkey, serialno, lotno, expirationdate, sum(totalQty) qtyleft ,WHSEKEY FROM
                            (   SELECT itemkey, binkey, serialno, lotno, expirationdate, sum(qtyleft) totalQty ,WHSEKEY FROM  docentrycost     
                                WHERE cny#=:1 AND whsekey = :2 AND itemkey in ($componentsparams) AND qtyleft > 0
                                  AND in_out = 'I' AND affects_inventory in ('V', 'QV') and adjdocentrycostkey IS NULL
                                GROUP BY itemkey, binkey, serialno, lotno, expirationdate,WHSEKEY 
                                UNION
                                SELECT itemkey, binkey, serialno, lotno, expirationdate, sum(qtyleft) totalQty ,WHSEKEY FROM  docentrycostkits 
                                WHERE cny#=:1 AND whsekey = :2 AND itemkey in ($componentsparams) AND qtyleft > 0
                                  AND in_out = 'I' AND affects_inventory in ('V', 'QV') 
                                GROUP BY itemkey, binkey, serialno, lotno, expirationdate,WHSEKEY 
                                $allocated
                            )
                                GROUP BY itemkey, binkey, serialno, lotno, expirationdate,WHSEKEY ";
            $qry[] = GetMyCompany();
            $qry[] = $whseFrom;
            foreach ($components as $compoent) {
                $qry[] = $compoent;
            }
            $result = QueryResult($qry);

            if ($result !== false) {

                // if this is an exiting transaction, merge the existing data with
                // what is available NOW (it may be negative from the query, this may bump it up)
                if (! empty($existingEntries)) {
                    $result = $this->MergeTrackingOldAndNew($existingEntries, $result);
                }

                // if something is zero or negative, remove it (it is NOT available)
                foreach ($result as $weedOutNegativeIndex => $row) {
                    if ($row['QTYLEFT'] <= 0) {
                        unset($result[$weedOutNegativeIndex]);
                    }
                }
                $result = array_values($result);    // in case we removed any

                $binidsNeeded = [];
                $whereAreTheBinIds = [];
                if (($enableBIN === 'T') || ($iskit)) {
                    foreach ($result as $key => $row) {
                        if (isset($row['BINKEY'])) {
                            $binidsNeeded[$row['BINKEY']] = true;
                            $whereAreTheBinIds[$row['BINKEY']][] = $key;    // this record number goes here
                        }
                    }
                    if ( ! empty($binidsNeeded)) {
                        $qry = [];
                        $qry[] = "SELECT record# as binkey, binid FROM icbin WHERE cny#=:1 ";
                        $qry[] = GetMyCompany();
                        $qry = PrepINClauseStmt($qry, array_keys($binidsNeeded), " and record# ");
                        $binIds = QueryResult($qry);
                        if ($binIds !== false) {
                            foreach ($binIds as $row) {
                                $binkey = $row['BINKEY'];
                                $binid = $row['BINID'];
                                foreach ($whereAreTheBinIds[$binkey] as $oneBinKeyRow) {
                                    $result[$oneBinKeyRow]['BINID'] = $binid;
                                }
                            }
                        }
                    }
                }

                // construct the tracking info, much of this could be empty
                foreach ($result as $row) {
                    $attrs = '';
                    $rec   = [];
                    $attrs .= " itemid=\"" . isl_htmlspecialchars($row['ITEMKEY']) . "\"";
                    $rec['itemid'] = $row['ITEMKEY'];
                    if (isset($row['BINID'])) {
                        $attrs .= " binid=\"" . isl_htmlspecialchars($row['BINID']) . "\"";
                        $rec['binid'] = $row['BINID'];
                        $rec['binkey'] = $row['BINKEY'];
                    } else if ($enableBIN === 'T') {
                        $noBin = I18N::getSingleToken(TrackingHandler::NO_BIN_ID_TOKEN);
                        $attrs .= " binid='$noBin'";
                        $rec['binid'] = $noBin;
                        $rec['binkey'] = 0;
                    }
                    if (isset($row['SERIALNO'])) {
                        $attrs .= " serialno=\"" . isl_htmlspecialchars($row['SERIALNO']) . "\"";
                        $rec['serialno'] = $row['SERIALNO'];
                    } else if ($enableSN === 'T') {
                        $attrs .= " serialno=''";
                        $rec['serialno'] = '';
                    }
                    if (isset($row['LOTNO'])) {
                        $attrs .= " lotno=\"" . isl_htmlspecialchars($row['LOTNO']) . "\"";
                        $rec['lotno'] = $row['LOTNO'];
                    } else if ($enableLOT === 'T') {
                        $attrs .= " lotno=''";
                        $rec['lotno'] = '';
                    }
                    if (isset($row['EXPIRATIONDATE'])) {
                        $attrs .= " expiration=\"" . isl_htmlspecialchars($row['EXPIRATIONDATE']) . "\"";
                        $rec['expiration'] = $row['EXPIRATIONDATE'];
                    } else if ($enableEXP === 'T') {
                        $attrs .= " expiration=''";
                        $rec['expiration'] = '';
                    }
                    if (isset($row['WHSEKEY'])) {
                        $attrs .= " warehouse=\"" . isl_htmlspecialchars($row['WHSEKEY']) . "\"";
                        $rec['warehouse'] = $row['WHSEKEY'];
                    } else {
                        $attrs .= " warehouse=''";
                        $rec['warehouse'] = '';
                    }

                    if ($asXml) {
                        $attrs  .= " qtyleft=\"" . isl_htmlspecialchars($row['QTYLEFT']) . "\"";
                        $retXml .= " <track $attrs /> \n";
                    } else {
                        $rec['qtyleft'] = $row['QTYLEFT'];
                        $retArray['track'][] = $rec;
                    }
                }
            }
        }

        if (($whseTo != '') && ($enableBIN === 'T')) {
            $binsInTargetWarehouse = Globals::$g->gManagerFactory->getManager("bin")->getBinPicklist($whseTo, $itemid, false);
            foreach ($binsInTargetWarehouse as $row) {
                if ($asXml) {
                    $retXml .= " <targetBins binid=\"" . isl_htmlspecialchars($row['BINID']) . "\" /> \n";
                } else {
                    $rec = [];
                    $rec['binid']             = $row['BINID'];
                    $rec['binkey']            = $row['BINKEY'];
                    $retArray['targetBins'][] = $rec;
                }
            }
        }
        return $asXml ? $retXml : $retArray;
    }


    /**
     *  Maintain a cache of warehouse info used elsewhere in this routine.
     *  Takes one warehouse ID or multiple IDs
     *
     * @param string|string[] $warehouseIds     We can take ONE or multiple
     * @param array           $fromRawCache     optional raw warehouse cache
     *
     * @return array                            array of warehouses by ID
     */
    public static function AddToWarehouseCache( $warehouseIds, $fromRawCache = null )
    {
        // did we get a raw cache to start with?
        if ($fromRawCache !== null) {
            foreach ($fromRawCache as $id => $oneRawCache) {
                self::$warehouseCache[$id] = $oneRawCache;
            }
        }

        // passed is one or an array, lets deal with arrays only....
        if ( ! is_array($warehouseIds)) {
            $ids = [ $warehouseIds ];
        } else {
            $ids = $warehouseIds;
        }

        // Do we already have some/all?
        $idsToFetch = [];
        foreach ($ids as $id) {
            // is it already there?  (check for something specific from below)
            if (!isset(self::$warehouseCache[$id]['ENABLE_REPLENISHMENT'])) {
                $idsToFetch[] = $id;
            }
        }

        // anything to get?
        if ( ! empty($idsToFetch)) {
            $warehouseMgr = Globals::$g->gManagerFactory->getManager('warehouse');
            $rtn = $warehouseMgr->GetList( [
                'selects' => ['LOCATIONID', 'LOCATIONREFKEY', 'ENABLE_REPLENISHMENT'],
                'filters' => [[['LOCATIONID', 'IN', $idsToFetch]]],
            ] );
            if ($rtn !== false) {
                foreach ($rtn as $warehouse) {
                    self::$warehouseCache[$warehouse['LOCATIONID']] = $warehouse;
                }
            }
        }
        return self::$warehouseCache;
    }


    /**
     *      Is replenishment enabled for this warehouse?
     *
     * @param string $warehouseid
     *
     * @return string
     *
     */
    public static function GetWarehouseReplenishmentEnableFlag($warehouseid) {

        $warehouseInfo = self::AddToWarehouseCache( $warehouseid ); // in case it is not already in the cache
        return $warehouseInfo[$warehouseid]['ENABLE_REPLENISHMENT'] ?? 'false';
    }


    /**
     * @param array $qparams
     *
     * @return string
     * @throws Exception
     */
    function FetchUOMGrpInfo($qparams)
    {
        $gManagerFactory =& Globals::$g->gManagerFactory;
        $uomMgr = $gManagerFactory->getManager('uom');
        $uoms = $uomMgr->get($qparams['uomgrp']);
        $xmlStr = '';
        foreach ($uoms['ENTRIES'] as $uom) {
            $xmlStr .= "<uom unit='".htmlspecialchars($uom['UNIT'], ENT_COMPAT)."' factor='".htmlspecialchars($uom['CONVFACTOR'], ENT_COMPAT)."'></uom>";
        }
        $xmlStr .= "<purchase_default unit='".htmlspecialchars($uoms['POUOM'], ENT_COMPAT)."'></purchase_default>";
        $xmlStr .= "<sales_default unit='".htmlspecialchars($uoms['OEUOM'], ENT_COMPAT)."'></sales_default>";
        $xmlStr .= "<inventory_default unit='".htmlspecialchars($uoms['INVUOM'], ENT_COMPAT)."'></inventory_default>";
        return $xmlStr;
    }

    /**
     * @param array $qparams
     *
     * @return string
     * @throws Exception
     */
    function FetchVendorInfo($qparams)
    {
        $gManagerFactory =& Globals::$g->gManagerFactory;
        /** @var VendorManager $vendorMgr */
        $vendorMgr = $gManagerFactory->getManager('vendor');
        $vendor = $vendorMgr->Get($qparams['vendorId']);
        $leadTimeDefault = $vendor['DEFAULT_LEAD_TIME'];
        $xmlStr = "<FetchVendorInfo lead_time_default=\"$leadTimeDefault\"></FetchVendorInfo>";
        return $xmlStr;
    }

    /**
     * @param string    $_mod
     * @param int       $docparkey
     * @param int       $itemtaxgroupkey
     * @param int       $shiptotaxgroupkey
     *
     * @return bool
     */
    public function IsAdvanceTaxCapable($_mod, $docparkey, $itemtaxgroupkey, $shiptotaxgroupkey)
    {
        if($_mod=='so') {
            $dbmod = 'S';
        } else if($_mod == 'po') {
            $dbmod = 'P';
        }

        $taxqrystr = "SELECT schedkey FROM taxschedmap WHERE itemgrpkey = :1 AND entgrpkey = :2 ";
        $taxqrystr .= "AND (docparkey = :3 OR docparkey IS NULL) AND module = :4 AND cny# = :5";
        /** @noinspection PhpUndefinedVariableInspection */
        $taxqry = array( $taxqrystr, $itemtaxgroupkey, $shiptotaxgroupkey,
            $docparkey, $dbmod, GetMyCompany());
        $taxres = QueryResult($taxqry);

        $taxcapable = ((!is_null($taxres)) && (!empty($taxres)));

        return $taxcapable;
    }

    /**
     * @param array $qparams
     *
     * @return string
     */
    public function FetchPrice($qparams)
    {
        global $gManagerFactory;
        //$gManagerFactory = Globals::$g->gManagerFactory;

        $_custvendid     = $qparams['custvendid'];
        $_shipto        = $qparams['shiptocontact'];
        $_billto        = $qparams['billtocontact'];
        $_itemid         = $qparams['itemid'];
        $_prodline         = $qparams['prodline'];
        $_qty            = $qparams['qty'];
        $_date            = $qparams['date'];
        $_docparid        = $qparams['docpar'];
        $_mod            = $qparams['mod'];
        $_currency        = $qparams['currency'];
        $_whse            = $qparams['whse'];

        $docparMgr = $gManagerFactory->getManager('documentparams');
        $_docpar = $docparMgr->GetLatestRaw($_docparid);
        $_docpar = $_docpar[0];

        //$mgr = $gManagerFactory->GetManager('documententry');

        $pricingHandler = Globals::$g->gManagerFactory->_getObjectInstance('PricingHandler');
        $priceParams    = $pricingHandler->PrepParams($_custvendid,  $_billto, $_shipto, $_date, $_mod);

        $result         = $this->DoQuery('QRY_ITEM_COST_METHOD', array ($_itemid));
        $itemtype         = $result[0]['ITEMTYPE'];
        $cost_method     = $result[0]['COST_METHOD'];

        if ($_mod == 'inv') {
            $price = 0;
            if ($cost_method=='S') {
                $price = $this->GetStandardCost($_itemid, $_whse, $_date);
            } else if ($cost_method=='A') {
                $price = $this->GetAverageCost($_itemid, $_whse, $_date);
            }
        }else{
            $price = $pricingHandler->SuggestPrice($priceParams, $_itemid, $_prodline, $_qty, $_docpar, $_currency);
        }

        if (!$price) {
            $price = "0.00";
        }

        if (Profile::hasProperty('SFORCEKEY') && Profile::getProperty('SFORCEKEY') != '') {
            include_once 'SforceSynchronizer.cls';
            $sfSynchronizer = new SforceSynchronizer();
            if ($sfSynchronizer->_preferences['SFORCEPRICINGOPT'] == SFORCEPRICING) {
                $price ="0.00";
            }
        }

        $xmlStr = "<price num=\"$price\"
					costmethod = \"$cost_method\"
					itemtype = \"$itemtype\"></price>";
        return $xmlStr;
    }

    // function GetRenewalMacro()

    /**
     * @param string    $_itemid
     * @param array     $_docpar
     *
     * @return array|string
     */
    private function GetRenewalMacro($_itemid, $_docpar)
    {
        if ( $_itemid && in_array($_docpar['ENABLERENEWALS'], array('D', 'T'))) {
            $item               =   $this->Get($_itemid);
            if( is_array($item) && !empty($item) ) {
                return $item['RENEWALMACROID'];
            }
        }
        return '';
    }


    /**
     * @param string    $kitid
     *
     * @return bool
     */
    public function KithasSerializedItems($kitid)
    {
        $hasSerializedItems = false;
        if($kitid !='') {
            $cny  = GetMyCompany();
            $qry  = 'QRY_ICITEM_SELECT_KITCOMPONENT_TRACKINGDETAILS';
            $args = array ($cny, $cny, $kitid, $cny, $cny);
            $res  = $this->DoQuery($qry, $args);
            $hasSerializedItems = ($res[0]['COUNT'] >= 1 ? true : false);
        }
        return $hasSerializedItems;
    }


    /**
     * @param string    $itemID
     * @param bool      $useCache
     * @param array     $itemInfo
     *
     * @return bool
     */
    public function IsItemSerialized($itemID, $useCache = false, $itemInfo = array())
    {
        $item =  array();
        if ($useCache) {
            if (((!is_null($itemInfo)) && (!empty($itemInfo)))) { // Use the item info passed as a variable.
                $item = $itemInfo;
            } else if (((!is_null($this->itemCache)) && (!empty($this->itemCache))) && ((!is_null($this->itemCache[$itemID])) && (!empty($this->itemCache[$itemID])))) { // Use already Cached item info by default, can override later
                $item = $this->itemCache[$itemID];
            }
        }

        if (!$item) { // Force to Use Latest from Item. Also Default way to populate the item information.
            if ($itemID == '') {
                return false;   // otherwise bad query.
            }
            $item = $this->GetList(
                array(
                    'selects' => array('ENABLE_LOT_CATEGORY', 'ENABLE_SERIALNO', 'ENABLE_BINS', 'ENABLE_EXPIRATION'),
                    'filters' => array (array (array('ITEMID', '=', $itemID))),
                    'columnaliases' => array('ENABLELOT', 'ENABLESNO', 'ENABLEBIN', 'ENABLEEXPIRATION'),
                    'donottransform' => true
                )
            );
            $item = $item[0];
        }

        if($item['ENABLESNO']=='T' || $item['ENABLELOT']=='T' || $item['ENABLEBIN']=='T' || $item['ENABLEEXPIRATION']=='T') {
            return true;
        }else{
            return false;
        }

    }




    /**
     * Constructing cost details array to be used for cost calculation of line items
     * Also collecting Revenue Percent for kit components
     *
     * @param array|string      $item
     * @param float             $qty
     * @param string            $RevPosting
     * @param bool              $useItemCache
     *
     * @return array
     */
    function CollectItemCostDetails($item,$qty,$RevPosting='', $useItemCache = false)
    {

        $companyid    = GetMyCompany();

        //TODO: It must always be an array!!!
        if (!$useItemCache || !is_array($item)) {
            $ItemInfo    = $this->GetList(
                array(
                    'selects' => array('ITEMID', 'ITEMTYPE', 'STANDARD_COST', 'COST_METHOD'),
                    'filters' => array (array (array('ITEMID', '=', $item['ITEMID']))),
                    'donottransform' => true
                )
            );
            $item        = $ItemInfo[0];
        }

        // Adding SK in the if condition creates probs in inv-in for SK items - it puts some child components into ITEMDETAILS under $values[ENTRIES]
        // and if those child comps are tracked, it prevents us from doing a simple inv-in on the parent stkit - e.g. inv in of CPUBox in my exmaple
        // - Vish.
        //if ($item['ITEMTYPE']=='K' || $item['ITEMTYPE']=='SK'){
        if ($item['ITEMTYPE']=='K') {
            $qry        = 'QRY_ICITEM_SELECT_ITEMCOST';
            $args        = array ($companyid,$companyid,$item['ITEMID'],$companyid);
            $KitItem    = $this->DoQuery($qry, $args);

            if($RevPosting=='T') {
                $rec2=$KitItem;
                foreach($rec2 as $key2 => $val2){
                    $ParentRows= explode(',', $rec2[$key2]['ANCESTORROWNUMS']);
                    if (empty($ParentRows) || count($ParentRows)<2){
                        continue;
                    }
                    $immParentRowNum= $ParentRows[count($ParentRows)-2];
                    foreach($KitItem as $key1 => $val1){
                        if ($KitItem[$key1]['CURRENTROWNUM'] == $immParentRowNum) {
                            $KitItem[$key1]['REVPERCENT'] = ibcsub($KitItem[$key1]['REVPERCENT'], $rec2[$key2]['REVPERCENT'], 2, false);
                        }
                    }
                }
            }

            $rec=$KitItem;
            foreach( $rec as $key => $val){
                if ($rec[$key]['ITEMTYPE']=='K' && $RevPosting=='') {
                    unset($rec[$key]);
                }elseif($rec[$key]['REVPERCENT']<=0 && $RevPosting=='T') {
                    unset($rec[$key]);
                }else{
                    unset($rec[$key]['PARENTID'], $rec[$key]['CURRENTROWNUM'] , $rec[$key]['ANCESTORROWNUMS']);
                }
            }
        }else{
            $rec[0]['ITEMID']=$item['ITEMID'];
            $rec[0]['STANDARD_COST']=$item['STANDARD_COST'];
            $rec[0]['COST_METHOD']=$item['COST_METHOD'];
            $rec[0]['QUANTITY']=$qty;
            $rec[0]['ITEMTYPE']=$item['ITEMTYPE'];

            $isSupplies = (($item['ISSUPPLYITEM'] ?? 'F') === 'T');
            if ($isSupplies) {
                $rec[0]['ISSUPPLYITEM'] = 'T';  // only revealed when it IS a supply item, so as to not pollute others....
            }
        }

        return $rec;
    }



    /**
     * Constructing cost details array to be used for cost calculation of line items
     * Also collecting Revenue Percent for kit components
     *
     * @param array $item
     *
     * @return array
     */
    function CollectItemPrintingDetails($item)
    {

        $companyid    = GetMyCompany();

        $qry        = 'QRY_ICITEM_SELECT_ITEMPRINTING';
        $args        = array ($companyid,$companyid,$item['ITEMID'],$companyid);
        $KitItem    = $this->DoQuery($qry, $args);

        $rec2=$KitItem;
        foreach($rec2 as $key2 => $val2){
            $ParentRows= explode(',', $rec2[$key2]['ANCESTORROWNUMS']);
            if (empty($ParentRows) || count($ParentRows)<2){
                continue;
            }
            $immParentRowNum= $ParentRows[count($ParentRows)-2];
            foreach($KitItem as $key1 => $val1){
                 if ($KitItem[$key1]['CURRENTROWNUM'] == $immParentRowNum) {
                     $KitItem[$key1]['REVPERCENT']=ibcsub($KitItem[$key1]['REVPERCENT'], $rec2[$key2]['REVPERCENT'], 2,false);
                }
            }
        }

        foreach( $KitItem as $key => $val){
            if($KitItem[$key]['REVPERCENT']<0) {
                unset($KitItem[$key]);
            }else{
                unset($KitItem[$key]['PARENTID'], $KitItem[$key]['CURRENTROWNUM'] , $KitItem[$key]['ANCESTORROWNUMS']);
            }
        }
        return $KitItem;
    }




    /**
     * Constructing cost details array to be used for cost calculation of line items
     * Also collecting Revenue Percent for kit components for kit vsoe allocation.
     * vsoeAllocation should be all the leaf level item.
     *
     * @param array $item
     * @param float $qty
     * @param array $vsoeAllocation
     *
     * @return array
     */
    function CollectItemCostDetailsVSOE($item, $qty, $vsoeAllocation)
    {
        $companyid    = GetMyCompany();

        $args        = array ($item['ITEMID'],$companyid,$companyid,$companyid,$companyid,$companyid,$companyid);
        $ItemInfo    = $this->DoQuery('QRY_ITEM_SELECT_SINGLE_VID', $args);
        $item        = $ItemInfo[0];

        if ($item['ITEMTYPE']=='K') {
            $qry        = 'QRY_ICITEM_SELECT_ITEMCOST';
            $args        = array ($companyid,$companyid,$item['ITEMID'],$companyid);
            $KitItem    = $this->DoQuery($qry, $args);

            $rec1=$KitItem;
            $recNotInitialized = true;

            //for each leaf level vsoe allocation we've already calculated, stuff the cost information.
            foreach($vsoeAllocation['ITEMALLOCATION'] as $val)
            {
                foreach($rec1 as $val1)
                {
                    if($val['ITEMCOMPONENTKEY'] == $val1['ITEMID']) {
                        unset($val1['REVPERCENT']);

                        //this is the base amount value we use to stick to prentry/glentry
                        $val1['ENDVALUE'] = $val['VSOEALLOCATION'];

                        //this is the transaction amount value we use to stick to prentry/glentry
                        $val1['TRX_ENDVALUE'] = $val['TRX_VSOEALLOCATION'];

                        /**
                        determine what we need to do in the following order
                        -- If any item in the kit is marked as "bundle delivery" && is 'Undelivered', then all the components in
                        the kit needs to be deferred regardless of individual setting.
                        -- Else (item must be marked as "item delivery")
                        -- If status is 'undelivered',
                        -- if there is a rev. rec. template, then we need to create the rev. rec. schedule
                        and automatically "hold" it until its status changed to "delivered". Schedule status is "On Hold".
                        -- else book this entry (credit) into the deferred rev. account and no schdule be created
                        -- Else (status is 'delivered', proceed with the existing logic,
                        a) if there is schedule template associated with itemGLGroup that item belongs, then
                        book this entry (credit) into the deferred rev. account and create schedule. Schedule status is "Not Started".
                        b) else, book this entry (credit) into the rev. account. No schedule is created.
                         */
                        if($vsoeAllocation['KITHOLDALL']) {
                            $val1['VSOEREVRECACTION'] = 'hold';   //always book to def. rev. account. Schedule status is "On Hold" if Schedule is
                            //created(template are found)
                        }
                        else
                        {
                            if($val['DLVRSTATUS'] == 'Undelivered') {
                                $val1['VSOEREVRECACTION'] = 'hold';   //always book to def. rev. account.
                            }                                                                  //Schedule status is "On Hold" if Schedule is created(template are found)
                            else {
                                $val1['VSOEREVRECACTION'] = 'proceed';   //the existing logic
                            }
                        }
                        if ($recNotInitialized) {
                            $recNotInitialized = false;
                            $rec = [];
                        }
                        $rec[] = $val1;

                        break;
                    }
                }
            }
        }else{
            $rec = [];
            //TODO: we should be able to remove this since when we get into this function, it is always a kit.
            //we need to repeat the above logic for non-kit item as well.
            if($vsoeAllocation['KITHOLDALL']) {
                $rec[0]['VSOEREVRECACTION'] = 'hold';   //always book to def. rev. account. Schedule status is "On Hold" if Schedule is
                //created(template are found)
            }
            else
            {
                /** @noinspection PhpUndefinedVariableInspection */
                if( $val['DLVRSTATUS'] == 'Undelivered') {
                    $rec[0]['VSOEREVRECACTION'] = 'hold';   //always book to def. rev. account.
                }                                                            //Schedule status is "On Hold" if Schedule is created(template are found)
                else {
                    $rec[0]['VSOEREVRECACTION'] = 'proceed';   //the existing logic
                }
            }
            $rec[0]['ITEMID']=$item['ITEMID'];
            $rec[0]['STANDARD_COST']=$item['STANDARD_COST'];
            $rec[0]['COST_METHOD']=$item['COST_METHOD'];
            $rec[0]['QUANTITY']=$qty;
            $rec[0]['ITEMTYPE']=$item['ITEMTYPE'];
        }

        /** @noinspection PhpUndefinedVariableInspection */
        return $rec;
    }

    /**
     * @param string $itemid
     * @param string $whse
     * @param string $date
     *
     * @return float
     */
    public function GetCost_InvTransInOut($itemid, $whse, $date)
    {
        $invTranCost = $this->GetStandardCost($itemid, $whse, $date);

        return $invTranCost;
    }

    /**
     * @param array $qparams
     *
     * @return string
     */
    public function ItemCost_InvTransInOut($qparams)
    {

        $cost = 0;
        $itemid     = $qparams['itemid'];
        $whse        = $qparams['warehouseid'];

        $cost_method = $this->DoQuery('QRY_ITEM_COST_METHOD', array($itemid));
        $itemtype = $cost_method[0]['ITEMTYPE'];
        $cost_method = $cost_method[0]['COST_METHOD'];

        if ($cost_method =='S' && $itemtype=='I' && $itemtype!='SK') {
            $date = null;   // defaults to current date
            $cost = $this->GetCost_InvTransInOut($itemid, $whse, $date);
        }
        $xmlStr = "<itemcost invtransoutcost=\"$cost\">
				   </itemcost>";
        return $xmlStr;
    }


    /**
     * @param string    $itemid
     * @param string    $warehouseid
     *
     * @return bool|array
     */
    function GetICItemTotals($itemid, $warehouseid)
    {

        $itemFilter = '';
        $whseFilter = '';

        $bindIndex = 1;
        $args[0] = '';
        $args[$bindIndex++]  = GetMyCompany();

        if(isset($itemid) && $itemid!='') {
            $onhanditemFilter = " and itemid=:$bindIndex ";
            $itemFilter = " and itemkey=:$bindIndex ";
            $args[$bindIndex++] = $itemid;
        }

        if(isset($warehouseid) && $warehouseid!= '') {
            $onhandwhseFilter = " and docentry.warehousekey = :$bindIndex ";
            $whseFilter = " and warehousekey = :$bindIndex ";
            $args[$bindIndex] = $warehouseid;
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $qry = "select itemkey, warehousekey, aislekey, rowkey, binkey, sum(onorderqty) as qtyonorder, sum(onhandqty) as qtyonhand, sum(onholdqty) as qtyonhold 
		 		from (
					    (select item.cny#, doccost.itemkey, docentry.warehousekey, whseaisle.aisleid aislekey, whserow.rowkey, whsebin.binid binkey, 0 as onorderqty, doccost.qtyleft as onhandqty, 0 as onholdqty
					    from icitem item, docentrycost doccost , docentry, dochdr, docpar, icaisle whseaisle, icrow whserow,icbin whsebin, docpartotals, ictotal 
					    where doccost.cny# = :1"
            . $onhanditemFilter . $onhandwhseFilter .
            " 
					    and item.itemtype in ('I','SK')
						and item.enablebin = 'T'
					    and dochdr.state not in ('I','S','A', 'X', 'R') 
					    and docpar.in_out = 'I' 
					    and doccost.qtyleft > 0 
					    and docpartotals.q_qv in ('QV', (case 
					                                        when item.enablebin = 'T' then 'Q' 
					                                        else 'V' 
					                                    end)
					                              ) 
					    and ictotal.name = 'ONHAND'
					    and item.cny#=doccost.cny# 
					    and doccost.cny#=docentry.cny# 
					    and docentry.cny#=dochdr.cny# 
					    and dochdr.cny#=docpar.cny# 
					    and doccost.cny#=whseaisle.cny#(+) 
					    and doccost.cny#=whserow.cny#(+) 
					    and doccost.cny#=whsebin.cny#(+) 
					    and docpar.cny#=docpartotals.cny# 
					    and docpartotals.cny#=ictotal.cny# 
					    and item.itemid=doccost.itemkey 
					    and doccost.docentrykey=docentry.record# 
					    and docentry.dochdrkey=dochdr.record# 
					    and dochdr.docparkey=docpar.record# 
					    and doccost.aislekey=whseaisle.record#(+) 
					    and doccost.rowkey=whserow.record#(+) 
					    and doccost.binkey=whsebin.record#(+) 
					    and docpar.record# = docpartotals.docparkey 
					    and docpartotals.totalkey = ictotal.record#
	
						UNION ALL

						select onhand.cny#, onhand.itemkey, onhand.warehousekey,  null, null, null, 0 as onorderqty, nvl(onhand.posquantity,0) + nvl(onhand.negquantity,0) as onhandqty, 0 as onholdqty
						from icitemtotals onhand, ictotal onhandictotal
						where onhand.cny# = :1"
            . $itemFilter . $whseFilter .
            " 
						and onhand.cny# = onhandictotal.cny# 
						and onhand.totalkey = onhandictotal.record# 
						and onhandictotal.name = 'ONHAND' 
						and NOT exists (select 1 from icitem where cny# = :1 and itemid = onhand.itemkey and enablebin = 'T')
						)
						UNION ALL
		
						select onorder.cny#, onorder.itemkey, onorder.warehousekey,  null, null, null, nvl(onorder.posquantity,0) + nvl(onorder.negquantity,0) as onorderqty, 0 as onhandqty, 0 as onholdqty
						from icitemtotals onorder, ictotal onorderictotal
						where onorder.cny# = :1"
            . $itemFilter . $whseFilter .
            " 
						and onorder.cny# = onorderictotal.cny# 
						and onorder.totalkey = onorderictotal.record# 
						and onorderictotal.name = 'ONORDER'
		      
						UNION ALL
		    
						select onhold.cny#, onhold.itemkey, onhold.warehousekey, null, null, null, 0 as onorderqty, 0 as onhandqty, nvl(onhold.posquantity,0) + nvl(onhold.negquantity,0) as onholdqty
						from icitemtotals onhold, ictotal onholdictotal
						where onhold.cny# = :1"
            . $itemFilter . $whseFilter .
            "
						and onhold.cny# = onholdictotal.cny# 
						and onhold.totalkey = onholdictotal.record# 
						and onholdictotal.name = 'ONHOLD'
					)
		    	group by itemkey, warehousekey, aislekey, rowkey, binkey";

        $args[0] = $qry;
        $data = QueryResult($args);

        if (empty($data)) {
            global $gErr;
            //$gErr = Globals::$g->gErr;

            $gErr->addIAError(
                'INV-0176', __FILE__.'.'.__LINE__,
                "No results exist for specified input",
                []
            );
            return false;
        }
        return $data;
    }


    /**
     * @param string    $ID
     * @param string    $whseid
     * @param float     $qty
     * @param string    $unit
     *
     * @return string
     */
    function GetStKitItemQty($ID,$whseid,$qty,$unit)
    {
        $companyid=GetMyCompany();

        //get kit uom and cost method
        $kitid= $ID;
        $kitargs = array($kitid,$companyid,$unit);
        $kitargtypes = array( 'text', 'integer','text');
        $kitcode = array(
            'QUERY'=> "select icitem.itemid,icitem.name,icuom.unit,case
			when COST_METHOD='S' then 'STANDARD'  
			when COST_METHOD='A' then 'AVERAGE'  
			when COST_METHOD='L' then 'LIFO'  
			when COST_METHOD='F' then 'FIFO'  
			END  as COST_METHOD from icitem,icuom,icuomgrp uom 
			where 
			itemid= ? 
			and icitem.cny#=?
			and icitem.uomgrpkey = uom.record# (+)
			and icitem.cny# = uom.cny#(+)
			and uom.record# = icuom.grpkey
			and icuom.unit = ?
			and icitem.cny# = icuom.cny#(+)",
            'ARGTYPES' => $kitargtypes
        );
        $kit = $this->_QM->DoCustomQuery($kitcode, $kitargs, true);

        /*
        //get kit component details using recursion
        $code = array(
        'QUERY' =>"select	icitemcomponent.itemkey as parentid,
								icitemcomponent.componentkey as component_id,
						        icitem.name as component_description,
								icitemcomponent.quantity*icitem.sunit_factor as quantity,
								icitemcomponent.quantity*icitem.sunit_factor as quantityperkit,
								icitemcomponent.unit as uom,
								icitem.standard_COST as std_cost,
		 						case
									when icitem.COST_METHOD='S' then 'Standard'
									when icitem.COST_METHOD='A' then 'Average'
									when icitem.COST_METHOD='L' then 'LIFO'
									when icitem.COST_METHOD='F' then 'FIFO'
								END  as cost_method,
								case
									when ICITEM.itemtype = 'K' then 'Kit'
									when ICITEM.itemtype = 'SK' then 'Stockable Kit'
									else ICITEM.itemtype
								end as itemtype,
						        glgroup.name as itemglgrp,
								level as itemlevel
        from icitemcomponent, icitem, icitemglgrp glgroup
        where	icitem.cny#=icitemcomponent.cny# and
								icitemcomponent.componentkey = icitem.itemid and
								icitem.cny# = ? and
								icitem.status = 'T' and
						        icitem.cny# = glgroup.cny#(+) and
						        icitem.glgrpkey = glgroup.record#(+)
        start with icitemcomponent.itemkey= ?
        connect by icitemcomponent.itemkey = PRIOR icitemcomponent.componentkey",
        'ARGTYPES' => array('integer','text'),
        );
        */
        //get only immediate components of kit
        $code = array(
            'QUERY' =>"select	icitemcomponent.itemkey as parentid,
								icitemcomponent.componentkey as component_id,
						        icitem.name as component_description,
								icitemcomponent.quantity*icuom.convfactor as quantity,
								icitemcomponent.quantity*icuom.convfactor as quantityperkit,
								icitemcomponent.unit as uom,
								icitem.standard_COST as std_cost,
		 						case
									when icitem.COST_METHOD='S' then 'Standard'
									when icitem.COST_METHOD='A' then 'Average'
									when icitem.COST_METHOD='L' then 'LIFO'
									when icitem.COST_METHOD='F' then 'FIFO'
								END  as cost_method,
								case 
									when ICITEM.itemtype = 'K' then 'Kit' 
									when ICITEM.itemtype = 'SK' then 'Stockable Kit'	
									else ICITEM.itemtype 
								end as itemtype,
						        glgroup.name as itemglgrp
						from icitemcomponent, icitem, icitemglgrp glgroup,icuom,icuomgrp uom 
						where	icitemcomponent.cny# = ?  
				            and icitemcomponent.itemkey=?
				            and icitem.cny#=icitemcomponent.cny# 
				            and icitem.itemid= icitemcomponent.componentkey
				            and icitem.status = 'T' 
				            and icitem.cny# = glgroup.cny#(+) 
				            and icitem.glgrpkey = glgroup.record#(+)
					    and icitem.uomgrpkey = uom.record# (+)
					    and icitem.cny# = uom.cny#(+)
					    and uom.record# = icuom.grpkey
					    and icuom.unit = ?
					    and icitem.cny# = icuom.cny#(+)",
            'ARGTYPES' => array('integer','text','text'),
        );
        $args = array ($companyid,$kitid,$unit);
        $KitItem = $this->_QM->DoCustomQuery($code, $args, true);

        $rec=$KitItem;
        $rec=$this->propagateParentQuantitiesToChild($rec);

        //fetch the qty details of the given components - for every warehouse there will be only one item record in $itemsqty
        $itemsqty = $this->getItemsQuantities($companyid, $whseid, $whseid, $KitItem);
        $this->_itemsqty = $itemsqty;

        $warehouseargs = array($whseid,$companyid);
        $warehouseargtypes = array( 'text', 'integer');
        $warehousecode = array(
            'QUERY'=> "SELECT location_no warehousekey FROM icwarehouse where location_no 	=? and cny#=? group by location_no",
            'ARGTYPES' => $warehouseargtypes
        );

        $warehouse = (array) $this->_QM->DoCustomQuery($warehousecode, $warehouseargs, true);
        $this->_warehouse = $warehouse;

        $maxqty=$qty;

        for($j=0; $j<count($warehouse); $j++) {
            $k=0;
            for($i=count($itemsqty)-1; $i>=0; $i--) {
                if($warehouse[$j]['WAREHOUSEKEY']==$itemsqty[$i]['WAREHOUSEKEY']) {
                    //for every warehouse there will be only one item record in $itemsqty, no addition to existing record required here
                    $warehouse[$j]['ITEM'][$k]['ITEMKEY']=$itemsqty[$i]['ITEMKEY'];
                    $warehouse[$j]['ITEM'][$k]['QUANTITY']=$itemsqty[$i]['QUANTITY'];
                }else{
                    $warehouse[$j]['ITEM'][$k]['ITEMKEY']=$itemsqty[$i]['ITEMKEY'];
                    $warehouse[$j]['ITEM'][$k]['QUANTITY']=0;
                }
                ++$k;
            }
        }

        foreach( $warehouse as $warekey => $wareval){
            $itemsqty=$warehouse[$warekey]['ITEM'];

            $qtyvalues = [];
            foreach( $itemsqty as $k => $v){
                foreach( $rec as $key => $val){
                    if($itemsqty[$k]['ITEMKEY']==$rec[$key]['COMPONENT_ID']) {
                        if ($maxqty>0) {
                            $rec[$key]['QUANTITY_FORMAX'] = bcmul($rec[$key]['QUANTITY'], $maxqty);
                            if (isset($itemsqty[$k]['QUANTITY'])) {
                                $rec[$key]['QUANTITY_REQUIRED'] = ibcsub($rec[$key]['QUANTITY_FORMAX'], $itemsqty[$k]['QUANTITY'], null, false);
                            }else{
                                $rec[$key]['QUANTITY_REQUIRED'] = $rec[$key]['QUANTITY_FORMAX'];
                            }

                            $rec[$key]['MAXQTY_CHILD'] ='yes';
                        }else{
                            $rec[$key]['MAXQTY_CHILD'] ='no';
                        }
                        $qtyvalues[] = bcdiv($itemsqty[$k]['QUANTITY'], $rec[$key]['QUANTITY']);
                    }
                }
            }

            $minvalue = $qtyvalues[0] ?? 0;
            for($i=0; $i<count($qtyvalues)-1; $i++) {
                if ($i==0) {
                    $minvalue = $qtyvalues[$i];
                }else{
                    $minvalue = min($minvalue, min($qtyvalues[$i], $qtyvalues[$i+1]));
                }
            }

            if($minvalue<1) {
                $possiblevalue=0;
            }else{
                $possiblevalue=floor($minvalue);
            }

            $kit[0]['POSSIBLE_UNITS']=$possiblevalue;
            if ($maxqty>0) {
                $kit[0]['PREFERRED_UNITS']=$maxqty;
            }

            if ($maxqty>0) {
                foreach( $rec as $key => $val){
                    if(!isset($rec[$key]['QUANTITY_REQUIRED'])) {
                        $rec[$key]['QUANTITY_FORMAX'] = bcmul($rec[$key]['QUANTITY'], $maxqty);
                        $rec[$key]['QUANTITY_REQUIRED'] = $rec[$key]['QUANTITY_FORMAX'];
                        $rec[$key]['MAXQTY_CHILD'] ='yes';
                    }
                }
            }

            $items=$rec;
            $kit[0]['COMPONENT']=$rec;
            $warehouse[$warekey]['KIT']=$kit;
            unset($warehouse[$warekey]['ITEM']);
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $this->_items = $items;

        /** @noinspection PhpUndefinedVariableInspection */
        $message= "There are only " . $possiblevalue . " kit on hand in selected warehouse\n";
        $Initialmessage=$message;
        $nonInvItemTypes=array('NI', 'NP', 'NS', 'K');
        foreach( $items as $v){
            if ($v['QUANTITY_REQUIRED']>0 && !in_array($v['ITEMTYPE'], $nonInvItemTypes)) {
                $message=$message.' Component id = '.$v['COMPONENT_ID'].' , Quantity required= '.$v['QUANTITY_FORMAX'].' , Quantity missing= '.$v['QUANTITY_REQUIRED']."\n";
            }
        }
        if($Initialmessage==$message) {
            $message='';
        }
        return $message;
    }

    /**
     * @param array $itemArray
     *
     * @return array
     */
    function propagateParentQuantitiesToChild($itemArray)
    {

        $itemArrayRec1=$itemArray;
        $itemArrayRec2=$itemArray;
        foreach( $itemArrayRec1 as $key1 => $val1){
            foreach( $itemArrayRec2 as $key2 => $val2){
                if ($itemArrayRec1[$key1]['COMPONENT_ID']==$itemArrayRec2[$key2]['PARENTID']) {
                    $itemArrayRec1[$key2]['QUANTITYRATIO']=ibcmul($itemArrayRec1[$key1]['QUANTITY'], $itemArrayRec2[$key2]['QUANTITY'], 4);
                    $itemArrayRec1[$key2]['QUANTITY']=ibcmul($itemArrayRec1[$key1]['QUANTITY'], $itemArrayRec2[$key2]['QUANTITY'], 4);
                }
            }
        }
        return $itemArrayRec1;

    }

    /**
     * @param string    $companyId
     * @param string    $fromWarehouseId
     * @param string    $toWarehouseId
     * @param array     $itemsArray
     *
     * @return array
     */
    function getItemsQuantities($companyId,$fromWarehouseId,$toWarehouseId,$itemsArray)
    {

        $itemsqtyargs = array($fromWarehouseId,$toWarehouseId);
        $itemsqtyargtypes = array( 'text', 'text');

        $avgcostargs = array($companyId);
        $avgcostargtypes = array( 'integer');

        foreach( $itemsArray as $key => $val){
            if ($itemsArray[$key]['ITEMTYPE']=='Kit') {
                unset($itemsArray[$key]);
            }
            else{
                unset($itemsArray[$key]['PARENTID'], $itemsArray[$key]['ITEMTYPE']);

                $itemsqtyargs = INTACCTarray_merge($itemsqtyargs, $itemsArray[$key]['COMPONENT_ID']);
                $itemsqtyargtypes = INTACCTarray_merge($itemsqtyargtypes, 'text');

                $avgcostargs = INTACCTarray_merge($avgcostargs, $itemsArray[$key]['COMPONENT_ID']);
                $avgcostargtypes = INTACCTarray_merge($avgcostargtypes, 'text');

                /** @noinspection PhpUndefinedVariableInspection */
                $itemsparam = $itemsparam . "?,";
            }
        }

        $itemsqtyargs = INTACCTarray_merge($itemsqtyargs, $companyId);
        $itemsqtyargtypes = INTACCTarray_merge($itemsqtyargtypes, 'integer');
        /** @noinspection PhpUndefinedVariableInspection */
        $itemsparam = isl_substr($itemsparam, 0, isl_strlen($itemsparam) - 1);

        //fetch the qty details of the given components
        $itemsqtycode = array(
            'QUERY'=>"select 	warehousekey,
		 						sum(qtyonhand) as QUANTITY,
		 						itemkey 
		 			  from 		v_itemavail 
		 			  where 	warehousekey between ? and  ?   
		 			  and 		itemkey in (".$itemsparam.") 
		 			  and 		cny#=? 
		 			  group by 	warehousekey,itemkey",
            'ARGTYPES' => $itemsqtyargtypes
        );

        $itemsqty = $this->_QM->DoCustomQuery($itemsqtycode, $itemsqtyargs, true);
        return $itemsqty;

    }

    /**
     * Confirms the valid selection for templates.
     *
     * @param array $values
     *
     * @return bool
     */
    public function translateTemplates(& $values)
    {
        $ok = true;

        $templateMap = [
            [
                'field-name' => 'CNBILLINGTEMPLATENAME',
                'entity' => 'contractbillingtemplate',
                'field-key' => 'CNBILLINGTEMPLKEY',
                'field-label' => _('Billing template')
            ],
            [
                'field-name' => 'CNREVENUETEMPLATENAME',
                'entity' => 'contractrevenuetemplate',
                'field-key' => 'CNREVENUETEMPLKEY',
                'field-label' => 'Revenue template # 1'
            ],
            [
                'field-name' => 'CNREVENUE2TEMPLATENAME',
                'entity' => 'contractrevenuetemplate',
                'field-key' => 'CNREVENUE2TEMPLKEY',
                'field-label' => 'Revenue template # 2'
            ],
            [
                'field-name' => 'CNEXPENSETEMPLATENAME',
                'entity' => 'contractexpensetemplate',
                'field-key' => 'CNEXPENSETEMPLKEY',
                'field-label' => 'Expense template # 1'
            ],
            [
                'field-name' => 'CNEXPENSE2TEMPLATENAME',
                'entity' => 'contractexpensetemplate',
                'field-key' => 'CNEXPENSE2TEMPLKEY',
                'field-label' => 'Expense template # 2'
            ],
            [
                'field-name' => 'CNMEACATEGORYNAME',
                'entity' => 'meacategory',
                'field-key' => 'CNMEACATEGORYKEY',
                'field-label' => 'Contract fair value category'
            ],
        ];


        foreach ( $templateMap as $template ) {
            if ( isArrayValueProvided($values, $template['field-name']) ) {
                $arr = explode('--', $values[$template['field-name']]);
                /** @var ContractRevenueTemplateManager|ContractBillingTemplateManager|ContractExpenseTemplateManager $manager */
                $manager = Globals::$g->gManagerFactory->getManager($template['entity']);

                $recordNo = $manager->GetRecordNo('NAME', $arr[0]);
                if ( isset($recordNo) ) {
                    $values[$template['field-key']] = $recordNo;
                } else {
                    $templateMessage = $template['field-label'];
                    $msg = $templateMessage . ' is not valid.';
                    $corr = 'Provide a valid ' . $templateMessage . '.';
                    Globals::$g->gErr->addIAError(
                        'INV-1138',
                        __FILE__ . ':' . __LINE__,
                        $msg, [ 'TEMPLATE_FIELD_LABEL' => $templateMessage],
                        '', [],
                        $corr, [ 'TEMPLATE_FIELD_LABEL' => $templateMessage]
                    ); //placeholder
                    $ok = false;
                }
            }else{
                $values[$template['field-key']] = '';
            }
        }

        return $ok;
    }

    /**
     * Platform support for the Item objects. Platform uses RECORDNO for most of the
     * operations since RECORDNO is not vid here. Convert RECORDNOs to VIDs to read ITEM records.
     * 1) An empty (null) value (which performs a get of the first 100 records)
     * 2) A single id value
     * 3) An array of ids
     *
     * @param int|int[]     $recordNos      Record numbers to be fetched
     * @param null|array    $returnFields   Fields to be returned
     *
     * @return array
     */
    function API_Get($recordNos, $returnFields=null)
    {
        self::$fromAPI = true;
        if (empty($recordNos)) {
            return parent::API_Get(array(), $returnFields);
        }

        if (!is_array($recordNos)) {
            $recordNos = explode(',', $recordNos);
        }

        //  For each recordno, translate to the vid
        $vids = array();
        foreach ($recordNos as $nextRecId) {
            $tempVID = $this->GetVidFromRecordNo($nextRecId);
            if ($tempVID != '') {
                $vids[] = $tempVID;
            }
        }

        if (!empty($vids)) {
            // available records with valid vid
            $returnRecordSet = parent::API_Get($vids, $returnFields);
        } else {
            // Invalid recordnumbers are passed and no vids available
            $returnRecordSet = false;
        }
        return $returnRecordSet;
    }


    /**
     * @param string    $value
     *
     * @return bool
     *
     */
    public function replenishmentMethod(&$value)
    {
        self::getReplenishmentMethods($internal,$external);
        $ok = true;

        if ($value != '') {
            $key = array_search(strtolower($value), array_map('strtolower', $external));
            if ($key === false) {
                $externalValue = implode("', '", $external);
                Globals::$g->gErr->addIAError('INV-1004', __FILE__ . ":" . __LINE__,
                    "The REPLENISHMENT_METHOD of '$value' is not correct.  It should be one of '" . $externalValue . "'",
                ['VALUE' =>$value , 'EXTERNAL' => $externalValue]
                );
                // i18N::TODO - (Code Change Review).
                $ok = false;
            }
        } else {
            $invPrefs = array();
            $kINVid = Globals::$g->kINVid;
            GetModulePreferences($kINVid, $invPrefs);

            $internalValue = ReplenishDetailManager::getInternalSalesForecastMethod($invPrefs['FORECAST_METHOD']);  // should already be in internal value, but if it isn't...
            $key = array_search( $internalValue, $internal);
            if ($key !== false) {
                $value = $external[$key]; // get the external value
            } else {
                $ok = false;
            }
        }
        return $ok;
    }



    /**
     * Validate the values provided for the item by restricting the user from
     * providing values where they are not allowed to provide from UI
     * Here we handle the restriction for fields that has to be readonly and are not
     * meant to be provided for create or update.
     *
     * @param array     $values
     * @param string    $action
     *
     * @return bool
     */
    function validateItem(&$values, $action = 'Add')
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        /*
         *  Fields that require validation to stop user from providing values while
         * creating an item
         */
        $fldsToCompareForCreate = array(
            'AVERAGE_COST',
            'WHENLASTRECEIVED',
            'WHENLASTSOLD',
            'WAREHOUSE_INFO' => array(
                'AVERAGE_COST', 'LAST_COST', 'DATE_LASTRECEIVED', 'DATE_LASTSOLD'
            ),
            'VENDOR_INFO' => array(
                'BEST_COST', 'LAST_COST'
            )
        );

        /*
         *  Fields that require validation for not to update using the user input
         */
        $fldsToCompareForUpdate = array(
            'COST_METHOD',
            'AVERAGE_COST',
            'ITEMTYPE',
            'ITEMID',
            'WHENLASTRECEIVED',
            'WHENLASTSOLD',
            'WAREHOUSE_INFO' => array(
                'AVERAGE_COST', 'LAST_COST', 'DATE_LASTRECEIVED', 'DATE_LASTSOLD',
                'STDCOSTENTRIES' => array(
                    'ITEMWSEKEY',
                ),
                'ITEMWAREHOUSEVENDORENTRIES' => array(
                    'ITEMWSEKEY',
                ),
            ),
            'VENDOR_INFO' => array(
                'BEST_COST', 'LAST_COST'
            )
        );

        if ($action == 'Add') {
            /*
              * when the item is being created, we validate all the values that user cannot provide
              * and return errors if there are any auto generated values that are being provided by user.
              */
            $ok = $ok && $this->checkAndCompareValues($values, $fldsToCompareForCreate);
        } else if ($action == 'Set') {
            /*
             * Using the record Number we get the vid of the ITEM and then we fetch
             * the current item object available to verify with the values that user
             * is trying to update
             */
            $temp = $this->GetVidFromRecordNo($values['RECORDNO']);
            $oldValues = $this->Get($temp);
            /*
             * when the item is being updated, we validate all the values that user cannot update
             * on the existing object and return errors if there are any auto generated
             * values that are being modified by user.
             */

            // do not let user change UOM Group if there are transactions in the system
            $trans = QueryResult(
                array(
                    "select record# from docentrycost where cny# = :1 and itemkey = :2 and rownum = 1 ",
                    GetMyCompany(),
                    $values['ITEMID']
                )
            );
            if ($trans[0]['RECORD#']) {
                $fldsToCompareForUpdate[] = 'UOMGRP';
            }
            $ok = $ok && $this->checkAndCompareValues($values, $fldsToCompareForUpdate, $oldValues);

            $ok = $ok && $this->canPreferencesBeDisabled($values, $oldValues);
        }

        /*
         * Here we get the Inventory Setup Preferences to verify if the item is being
         * created or updated with values that are not enabled.
         */
        $invPrefs = array();
        $kINVid = Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);

        /*
         * Verification for Item Cost Method being provided with a value other than
         * default cost method when the Multiple cost method usage is disabled
         * in Inventory Setup
         */
        $costMethods = array(
            'S' => 'Standard',
            'A' => 'Average',
            'F' => 'FIFO',
            'L' => 'LIFO'
        );

        $defaultCostMethod = $costMethods[$invPrefs['DEFAULT_COST_METHOD']];
        /*
         * If the inventory module is not subscribed then default cost method property doesn't exist.
         * Hence, it need to be set it as Standard.
         */
        $defaultCostMethod = ($defaultCostMethod && $defaultCostMethod !== '') ? $defaultCostMethod : 'Standard';

        if (empty($values['COST_METHOD'])) {
            $values['COST_METHOD'] = $defaultCostMethod;
        }

        if (self::$fromAPI) {   // the API tends to encourage all-caps
            switch ($values['COST_METHOD']) {
                case 'STANDARD':
                    $values['COST_METHOD'] = 'Standard';
                    break;

                case 'AVERAGE':
                    $values['COST_METHOD'] = 'Average';
                    break;

                default:
                    break; // leave alone
            }
        }

        if ( ( empty($invPrefs['ENABLE_MULTI_COST'])
                || $invPrefs['ENABLE_MULTI_COST']=='F' )
            && $values['ITEMTYPE'] == INVENTORY
            && $values['COST_METHOD'] != $defaultCostMethod
        ) {
            $gErr->addIAError(
                'INV-1155', __FILE__ . '.' . __LINE__,
                "Invalid Cost Method ({$values['COST_METHOD']}) provided for the Inventory Item.",
                [ 'VALUES_COST_METHOD' => $values['COST_METHOD']],
                "Enable Multiple Cost methods in Inventory Setup or Use the Default Cost Method ($defaultCostMethod) from your Inventory Setup",
                [ 'DEFAULT_COST_METHOD' => $defaultCostMethod]
            );
            $ok = false;
        }

        /*
         * The tracking fields that are to be validated against the Inventory Setup
         * Preferences are added to $trackingFields array here
         */
        $trackingFields = array(
            'ENABLE_SERIALNO',
            'ENABLE_LOT_CATEGORY',
            'ENABLE_EXPIRATION'
        );

        if (StkitDocumentManager::isStockableKitTrackingEnabled()) {
            $trackingFields[] = 'ENABLE_BINS';
        } else {
            /*
             * Bin Tracking can only be enabled for
             * Inventory Items with cost method as Standard, Average, or FIFO
             * Stockable Kits with cost method FIFO
             */
            if ( $values['ITEMTYPE'] != STOCKABLE_KIT
                || ( $values['ITEMTYPE'] == STOCKABLE_KIT && $values['COST_METHOD'] != 'FIFO' )
            ) {
                $trackingFields[] = 'ENABLE_BINS';
            }
        }

        /*
         * Here we validate if there is any value for tracking information provided if
         * the cost method is LIFO or if the Item type is not inventory or SK (if SK tracking enabled)
         * Based on the $trackingFields generation we skip or validate tracking fields
         */
        if ( $values['COST_METHOD'] == 'LIFO'
            || ( ( $values['ITEMTYPE'] != INVENTORY )
                && ( ! StkitDocumentManager::isStockableKitTrackingEnabled()
                    || $values['ITEMTYPE'] != STOCKABLE_KIT ) ) ) {
            $msg = '';
            $placeholder = [];
            if ($values['COST_METHOD'] == 'LIFO') {
                $msg = " when Cost method is 'LIFO'";
                $errorCode = 'INV-0177';
            } else if ($values['ITEMTYPE'] != INVENTORY) {
                $msg = " for " . $values['ITEMTYPE'] . " Items";
                $errorCode = 'INV-1199';
                $placeholder = ['VALUES_ITEMTYPE' => $values['ITEMTYPE']];
            }
            foreach ($trackingFields as $trackFld) {
                if ($values[$trackFld] == 'true') {
                    $placeholder = array_merge($placeholder, ['TRACK_FLD' => $trackFld]);
                    $gErr->addIAError(
                        $errorCode,
                        __FILE__ . '.' . __LINE__,
                        "Cannot Provide value to enable ${trackFld} ${msg}.",
                        $placeholder
                    ); // i18N::TODO (code change review)
                    $ok = false;
                }
            }
        }

        /*
         * We set the tracking preferences from Inventory Setup in respective variables
         * for our reference while validating Item values
         */
        $serialEnabled = ($invPrefs['ENABLESERIAL'] == 'T') ? true : false;
        $lotEnabled = ($invPrefs['ENABLELOT'] == 'T') ? true : false;
        $binEnabled = ($invPrefs['ENABLEBIN'] == 'T') ? true : false;
        $expirationEnabled = ($invPrefs['ENABLE_EXPIRATION'] == 'T') ? true : false;

        /*
         * Validating if Serial Tracking is being enabled for Item
         * when Serial Tracking is not enabled in Inventory Setup
         */
        if (!$serialEnabled && $values['ENABLE_SERIALNO'] == 'true') {
            $gErr->addIAError(
                'INV-0178', __FILE__ . '.' . __LINE__, "Cannot enable 'Serial Tracking' for the item", [],"Please enable 'Serial Tracking' in the Inventory module Setup and try again.", []
            );
            $ok = false;
        }

        /*
         * Validating if Lot Tracking is being enabled for Item
         * when Serial Tracking is not enabled in Inventory Setup
         */
        if (!$lotEnabled && $values['ENABLE_LOT_CATEGORY'] == 'true') {
            $gErr->addIAError(
                'INV-0179', __FILE__ . '.' . __LINE__, "Cannot enable 'Lot Tracking' for the item", [], "Please enable 'Lot Tracking' in the Inventory module Setup and try again.", []
            );
            $ok = false;
        }

        /*
         * Validating if Bin Tracking is being enabled for Item
         * when Bin Tracking is not enabled in Inventory Setup
         */
        if (!$binEnabled && $values['ENABLE_BINS'] == 'true') {
            $gErr->addIAError(
                'INV-0180', __FILE__ . '.' . __LINE__, "Cannot enable 'Bin Tracking' for the item", [],"Please enable 'Bin Tracking' in the Inventory module Setup and try again.", []
            );
            $ok = false;
        }
        /*
         * Validating if Expiration Tracking is being enabled for Item
         * when Expiration Tracking is not enabled in Inventory Setup
         */
        if (!$expirationEnabled && $values['ENABLE_EXPIRATION'] == 'true') {
            $gErr->addIAError(
                'INV-0181', __FILE__ . '.' . __LINE__, "Cannot enable 'Expiration Tracking' for the item", [],"Please enable 'Expiration Tracking' in the Inventory module Setup and try again.", []
            );
            $ok = false;
        }

        /*
         * Validating if the Serial Mask is provided when Serial Tracking is not enabled
         */
        if ($values['ENABLE_SERIALNO'] != 'true' && !empty($values['SERIAL_MASKKEY'])) {
            $gErr->addIAError(
                'INV-0182', __FILE__ . '.' . __LINE__, "Cannot provide value for 'Serial Mask' when 'Serial Tracking' is not Enabled.", []
            );
            $ok = false;
        }

        /*
         * Validating if the Lot Category is provided when Lot Tracking is not enabled
         */
        if ($values['ENABLE_LOT_CATEGORY'] != 'true' && !empty($values['LOT_CATEGORYKEY'])) {
            $gErr->addIAError(
                'INV-0183', __FILE__ . '.' . __LINE__, "Cannot provide value for 'Lot Category' when 'Lot Tracking' is not Enabled.", []
            );
            $ok = false;
        }

        /*
         * Validating if the Expiration Tracking is enabled when
         * Lot Tracking or Serial Tracking is not enabled
         */
        if ($values['ENABLE_SERIALNO'] != 'true' && $values['ENABLE_LOT_CATEGORY'] != 'true' && $values['ENABLE_EXPIRATION'] == 'true') {
            $gErr->addIAError(
                'INV-0184', __FILE__ . '.' . __LINE__, "Cannot 'Enable Expiration' without enabling 'Serial Tracking' or 'Lot Tracking'.", []
            );
            $ok = false;
        }

        /*
         * Validation process to check if a valid product line id is being provided
         */
        if ( isset($values['PRODUCTLINEID']) && $values['PRODUCTLINEID'] !== '' ) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $plMgr     = $gManagerFactory->getManager('productline');

            $product_line = $plMgr->get($values['PRODUCTLINEID']);
            if (empty($product_line)) {
                $gErr->addIAError(
                    'INV-0185', __FILE__ . '.' . __LINE__, "Invalid Product Line value provided.", []
                );
                $ok = false;
            } else if ($product_line['STATUS'] != 'active') {
                $gErr->addIAError(
                    'INV-0186', __FILE__ . '.' . __LINE__, "Inactive Product Line provided.", []
                );
                $ok = false;
            }
        }

        if ($action == 'Set') {
            /*
            * Here we get the SO Setup Preferences to verify if the item is being
            * created or updated with values that are not enabled.
            */
            $soPrefs = array();
            $kSOid = Globals::$g->kSOid;
            GetModulePreferences($kSOid, $soPrefs);

            if ($soPrefs['USEFULFILLMENT'] == 'T') {
                /*
                * Validating if the Default Delivery Status is provided when Fulfillment Tracking is enabled
                */
                if (empty($values['VSOEDLVRSTATUS'])) {
                    $gErr->addIAError(
                        'INV-0187', __FILE__ . '.' . __LINE__, "No value provided for required field 'Default Delivery Status'.", []
                    );
                    $ok = false;
                }
                /*
                * Validating if the Default Deferral Status is provided when Fulfillment Tracking is enabled
                */
                if (empty($values['VSOEREVDEFSTATUS'])) {
                    $gErr->addIAError(
                        'INV-0188', __FILE__ . '.' . __LINE__, "No value provided for required field 'Default Deferral Status'.", []
                    );
                    $ok = false;
                }
            }

            if ( SOSetupManager::isVsoeEnabled($soPrefs) ) {
                /*
                * Validating if the Lot Category is provided when Lot Tracking is not enabled
                */
                if (empty($values['VSOECATEGORY'])) {
                    $gErr->addIAError(
                        'INV-0189', __FILE__ . '.' . __LINE__, "No value provided for required field 'VSOE Category'.", []
                    );
                    $ok = false;
                }
            }
        }

        if (IsInstalled(Globals::$g->kCNid) && $values['SO_PRECISION'] != ''
            && $values['SO_PRECISION'] != 10
        ) {
            $gErr->addIAError(
                'INV-0190', __FILE__ . __LINE__,
                "The item's Unit cost precision for Sales must"
                . " either be blank or  set to 10 when subscribed to Contracts.", []
            );
            $ok = false;
        }

        if (!IsInstalled(Globals::$g->kDBBid) && !IsInstalled(Globals::$g->kSAASMTid)) {
            /** @noinspection PhpUndefinedVariableInspection */
            if ( ( $action == 'Add' && $values['MRR'] === 'true')
                || $action == 'Set' && $values['MRR'] != $oldValues['MRR']) {
                $gErr->addIAError(
                    'INV-0191', __FILE__ . __LINE__,
                    "MRR can be selected only when Digital board book or SaaS metrics"
                    . "is subscribed in this company.", []
                );
                $ok = false;
            }
        }

        // 'Price' Default conversion type value, should only applicable for non-inventory items
        if (!empty($values['DEFAULT_CONVERSIONTYPE'] ?? '') && $values['DEFAULT_CONVERSIONTYPE'] == 'Price'
            && !in_array(($values['ITEMTYPE'] ?? ''), array(NONINV, NONINV_PO, NONINV_SO))) {
            $msg  = "Only non-inventory items can use price conversion. Change the default conversion type to Quantity for " .$values['ITEMID'].".";
            $gErr->addIAError(
                'INV-1454', __FILE__ . ":" . __LINE__, $msg,
                [ 'ITEMID' => $values['ITEMID'] ]);
            $ok = false;
        }

        // Check replenishment values:
        $inventoryItem = in_array($values['ITEMTYPE'], array(INVENTORY, KIT, STOCKABLE_KIT));
        if ($inventoryItem && self::isReplenishmentOn()) {

            if (self::$fromAPI || ($values['ENABLE_REPLENISHMENT'] === 'true') || ($values['ENABLE_REPLENISHMENT'] === 'T')) {

                // because of 8.1 we need to default some values; in 8.1 (0 != '')
                $defaultThese = ['SAFETY_STOCK'  => 1, 'REORDER_POINT' => 1, 'FORECAST_DEMAND_IN_LEAD_TIME' => 0,
                                 'MAX_ORDER_QTY' => 0, 'REORDER_QTY'   => 0, ];

                foreach ($defaultThese as $field => $theDefault) {
                    // PHP8_NUMERIC_STRING_COMPARE; Priority: low; Behavior: same, Risk: low, Solution: php7eqEmptyStr
                    if ( Util::php7eqEmptyStr($values[$field] ?? '') ) {
                        $values[$field] = $theDefault;
                    }
                    if ($values[$field] < 0) {
                        $gErr->addIAError(
                            'INV-1156',
                            __FILE__ . ":" . __LINE__,
                            sprintf("%s must be greater than or equal to zero.", $field),
                            ['FIELD' => $field]
                        );
                        $ok = false;
                        $values[$field] = $theDefault;
                    } else if (!is_numeric($values[$field]) || !is_integer(0 + $values[$field])) {
                        Globals::$g->gErr->addIAError(
                            'INV-1157',
                            __FILE__ . ":" . __LINE__,
                            sprintf("%s must be must be a whole number", $field),
                            ['FIELD' => $field]
                        );
                        $ok = false;
                    }
                }

                $ok = $ok && $this->replenishmentMethod($values['REPLENISHMENT_METHOD']);

                if ($values['MAX_ORDER_QTY'] != 0) {
                    if (($values['REORDER_QTY'] ?? 0) > $values['MAX_ORDER_QTY']) {
                        $gErr->addIAError(
                            'INV-0192', __FILE__ . ":" . __LINE__, "The 'Quantity to reorder' must be less than or the same as 'Maximum order quantity'.", []);
                        $ok = false;
                        $values['REORDER_QTY'] = $values['MAX_ORDER_QTY'];
                    }
                }

                if ($values['REORDER_POINT'] <= 0) {
                    $gErr->addIAError(
                        'INV-0193', __FILE__ . ":" . __LINE__, "Reorder point must be greater than zero.", []);
                    $ok = false;
                    $values['REORDER_POINT'] = 1;
                }

                // if there is a UOM GROUP, check any DEFAULT REPLENISHMENT GROUP against it
                if (isset($values['DEFAULT_REPLENISHMENT_UOM']) && ($values['DEFAULT_REPLENISHMENT_UOM'] != '')) {

                    if ($values['UOMGRP']) {
                        $stmt = array();
                        $stmt[0] = 'SELECT 1 FROM icuom, icuomgrp WHERE icuom.cny# = :1 AND icuomgrp.cny# = :1 AND icuom.unit = :2 AND icuomgrp.name = :3 AND icuom.grpkey = icuomgrp.record#';
                        $stmt[1] = GetMyCompany();
                        $stmt[2] = $values['DEFAULT_REPLENISHMENT_UOM'];
                        $stmt[3] = $values['UOMGRP'];
                        $res = QueryResult($stmt);
                        if (($res === false) || (empty($res))) {
                            $gErr->addIAError(
                                'INV-1158', __FILE__ . ":" . __LINE__,
                                "The Default Replenishment UOM of '" . $values['DEFAULT_REPLENISHMENT_UOM'] . "' must be valid for the UOM group '" . $values['UOMGRP'] . "'.",
                                [ 'VALUES_DEFAULT_REPLENISHMENT_UOM' => $values['DEFAULT_REPLENISHMENT_UOM'], 'VALUES_UOMGRP'=> $values['UOMGRP']]
                            );
                            $ok = false;
                        }
                    }
                } else if (isset($values['UOM']['POUOMDETAIL']['UNIT'])) {
                    $values['DEFAULT_REPLENISHMENT_UOM'] = $values['UOM']['POUOMDETAIL']['UNIT'];
                }
            }
        }

        // supplies checks
        if (self::isSuppliesInventoryEnabled()) {
            $isSupply = $values['ISSUPPLYITEM'] ?? 'F';

            //Check that supplies inv item cannot be kit or non-inv sales
            if (($isSupply === 'T') || ($isSupply === 'true')) {
                if ( in_array($values['ITEMTYPE'], array(NONINV_SO, KIT)) ) {
                    $gErr->addIAError(
                        'INV-1446', __FILE__ . ":" . __LINE__, "Supplies cannot be type 'Kit' or type 'Non-Inventory (Sales only)'.", []);
                    $ok = false;
                    $values['ISSUPPLYITEM'] = '';
                }
            }

            //If we are editing...
            if ($action === 'Set') {
                if ($oldValues['ISSUPPLYITEM'] === 'true') {
                    //We cannot turn OFF supplies if item is being used in txns
                    if (($isSupply === 'F' || $isSupply === 'false') && ItemManager::isItemInUseOnTxn($values['ITEMID'])) {
                        $gErr->addIAError(
                            'INV-1459', __FILE__ . ":" . __LINE__, "Supplies are being used and cannot be turned off'.", []);
                        $ok = false;
                        $values['ISSUPPLYITEM'] = 'true';
                    }
                } else {
                    //We cannot turn ON supplies if item is being used in txns
                    if (($isSupply === 'T' || $isSupply === 'true') && ItemManager::isItemInUseOnTxn($values['ITEMID'])) {
                        $gErr->addIAError(
                            'INV-1459', __FILE__ . ":" . __LINE__, "Item is being used and cannot be turned on'.", []);
                        $ok = false;
                        $values['ISSUPPLYITEM'] = 'true';
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
    private function validateFulfillmentInfo($values)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;

        if ( ! $this->isFulfillmentPrefEnabled && $values['ENABLEFULFILLMENT'] == 'true' ) {
            $msg = "Unable to set the value for Fulfillment and cannot save item information.";
            $gErr->addIAError('INV-1139', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }

        if ( $this->isFulfillmentPrefEnabled && ! in_array($values['ITEMTYPE'], [ NONINV, NONINV_SO ])
            && $values['ENABLEFULFILLMENT'] == 'true' ) {
            $msg = "Ensure that the item type is Non-Inventory or Non-Inventory (Sales) and that Inventory Control is configured for fulfillment.";
            $gErr->addIAError('INV-1140', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }

        return $ok;
    }

    /**
     *      What warehouses have Replenishment off?
     *  Since Replenishment ON is the DEFAULT, I expect far fewer warehouses to be OFF....
     *
     * @return bool[]
     */
    private function getWarehousesWithoutReplenishment()
    {
        $warehousesNotEnabledForReplenishment = [];
        $qry = [];
        $qry[0] = "SELECT name FROM icwarehouse WHERE cny#=:1 AND enable_replenishment='F' ";
        $qry[1] = GetMyCompany();
        $res = QueryResult($qry);
        if ($res !== false) {
            foreach ($res as $warehouse) {
                $warehousesNotEnabledForReplenishment[ strtoupper($warehouse['NAME'])] = true; // because people are sloppy with the API and CSV import, upshift the name
            }
        }
        return $warehousesNotEnabledForReplenishment;
    }


    /**
     *  When an API call goes to add or set values, validate to make sure all fields are welcome.
     *  This is done BEFORE we read any existing records, because then we merge the current values with the
     *  API values and you can't check to see if fields were specified by the caller.
     *
     * @param string    $itemType       the item's type (like 'Kit')
     * @param array     $values         the array of values to validate
     *
     * @return bool
     */
    private function apiFieldValidation($itemType, $values)
    {
        $ok = true;
        // Check replenishment values:
        $inventoryItem = (($itemType == '') || in_array($itemType, array(INVENTORY, KIT, STOCKABLE_KIT)));  // no item type is treated as an inventory item
        if (($inventoryItem == false) || (self::isReplenishmentOn() == false)) {

            $ok = $this->validateNoReplenishFields("item",'the main', $inventoryItem, $values);

            if ($ok && isset($values['VENDORINFO']['itemvendor'])) {
                foreach ($values['VENDORINFO']['itemvendor'] as $vendor) {
                    if (!empty($vendor)) {
                        $ok = $ok && $this->validateNoReplenishFields("itemvendor", 'a VENDORINFO', $inventoryItem, $values);
                    }
                }
            }

            if ($ok && isset($values['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'])) {   // WAREHOUSE_INFO is the internal name, WAREHOUSEINFO is the external name
                foreach ($values['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'] as $wInfo) {
                    $ok = $ok && $this->validateNoReplenishFields("itemwarehouseinfo", 'a WAREHOUSEINFO', $inventoryItem, $wInfo);
                    if (isset($wInfo['ITEMWAREHOUSEVENDORENTRIES'][0])) {  // at least one entry?
                        if ( ! $inventoryItem) {
                            Globals::$g->gErr->addIAError(
                                'INV-0194', __FILE__ . ":" . __LINE__, "Non-inventory items cannot set ITEMWAREHOUSEVENDORENTRIES.", []);
                        }
                        $ok = false;
                        break;
                    }
                }
            }
        } else {    // replenishment is ON and this is an inventory item
            $this->firstEmptyPreferredVendor = [];
            if (isset($values['VENDORINFO']['ITEMVENDOR'])) {
                $this->firstEmptyPreferredVendor['NON_WAREHOUSE'] = -1;
                foreach ($values['VENDORINFO']['ITEMVENDOR'] as $key => $vendor) {
                    if (!empty($vendor)) {
                        if (!isset($vendor['PREFERRED_VENDOR']) || ($vendor['PREFERRED_VENDOR'] == '')) {
                            $this->firstEmptyPreferredVendor['NON_WAREHOUSE'] = $key;
                            break;
                        }
                    }
                }
            }
            // is the warehouse enabled for replenishment?
            if ($ok && isset($values['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'])) {
                $warehousesNotEnabledForReplenishment = $this->getWarehousesWithoutReplenishment();
                foreach ($values['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'] as $whKey => $wInfo) {
                    $this->firstEmptyPreferredVendor[$whKey] = -1;
                    if (isset($wInfo['ITEMWAREHOUSEVENDORENTRIES'])) {
                        foreach ($wInfo['ITEMWAREHOUSEVENDORENTRIES'] as $key => $vendor) {
                            if (!isset($vendor['PREFERRED_VENDOR']) || ($vendor['PREFERRED_VENDOR'] == '')) {
                                $this->firstEmptyPreferredVendor[$whKey] = $key;
                                break;
                            }
                        }
                    }

                    if (isset($warehousesNotEnabledForReplenishment[ $wInfo['WAREHOUSEID']])) {
                        $ok = $ok && $this->validateNoReplenishFields("itemwarehouseinfo", 'warehouse ' . $wInfo['WAREHOUSEID'], $inventoryItem, $wInfo);
                    }
                }
            }
        }
        return $ok;
    }



    /**
     *      Make sure there are no replenishment fields being set
     *
     * @param string   $entity              who are we doing this for?
     * @param string   $context             for error messages to orient the customer in what area to look
     * @param bool     $inventoryItem       is this an inventory item?  (drives the error message)
     * @param string[] $values              what are their values?
     *
     * @return bool
     */
    private function validateNoReplenishFields($entity, $context, $inventoryItem, $values)
    {
        $ok = true;
        // make sure they don't give us replenishment fields
        if (isset($this->_schemas[$entity]['api']['LESS_GET_FIELDS_NO_REPLENISHMENT'])) {
            foreach ($this->_schemas[$entity]['api']['LESS_GET_FIELDS_NO_REPLENISHMENT'] as $field) {
                if (isset($values[$field])) {
                    if ($inventoryItem) {
                        Globals::$g->gErr->addIAError(
                            'INV-1159',
                            __FILE__ . ":" . __LINE__,
                            "Replenishment is not on, so you cannot set the field '$field' in $context section.",
                            [ 'FIELD' => $field, 'CONTEXT' => $context]
                        );
                    } else {
                        Globals::$g->gErr->addIAError(
                            'INV-1160',
                            __FILE__ . ":" . __LINE__,
                            "Non-inventory items cannot set the field '$field' in $context section.",
                            [ 'FIELD' => $field, 'CONTEXT' => $context]
                        );
                    }
                    $ok = false;
                    // yes, one message per field they try to set
                }
            }
        }
        return $ok;
    }


    /**
     * Function to Compare or check if the values provided are matching with existing data
     * or they are not provided
     * In case of edit, If value vaires we throw out an error and if no value is provided
     * we replace the existing value to keep the data safe without corrupting
     * In case of create we do not allow the user to provide any values for the restricted
     * fields
     *
     * @param array &$values       values
     * @param array $fldsToCompare fields to compare
     * @param array $oldValues     oldValues
     *
     * @return bool
     */
    function checkAndCompareValues(&$values, $fldsToCompare, $oldValues = array())
    {
        $ok = true;

        $gErr = Globals::$g->gErr;
        if (empty($fldsToCompare)) {
            return $ok;
        }
        foreach ($fldsToCompare as $fld => $key) {
            $ok1 = true;
            if (is_array($key)) {
                if (!empty($values[$fld])) {
                    /*
                     * Validating the owned objects if any restrictions are to be enforced
                     */
                    $ok1 = $this->checkAndCompareOwnedValues($values[$fld], $key, $oldValues[$fld]);

                    if ($ok1 == false) {
                        /*
                         * Error message to adopt the previously added errors by parent
                         */
                        $gErr->addIAError('INV-0195', __FILE__ . '.' . __LINE__, "Invalid information provided value for ${fld}", ['FLD' => $fld]);
                    }

                }
            } else {
                /*
                 * Validate and Set if a restricted match is not found and not set
                 * Throw an error if a restriction is not matched but is being set
                 */
                $ok1 = $this->validateAndSetValues($values, $key, $oldValues);
            }

            $ok = $ok && $ok1;

        }
        return $ok;
    }

    /**
     * Function to compare and check the values provided under the owned object
     *
     * @param array &$values       values
     * @param array $fldsToCompare fields to compare
     * @param array $oldValues     oldValues
     *
     * @return bool
     */
    function checkAndCompareOwnedValues(&$values, $fldsToCompare, $oldValues = array())
    {
        $ok = true;

        if (empty($fldsToCompare)) {
            return $ok;
        }
        foreach ( $values as &$value) {
            if (empty($value)) {
                continue;
            }

            /*
             * $old_value is a variable that holds the value against which the comparision and
             * validation has to happen. It holds null value if there is no reference that
             * is found in oldValues data
             */
            $old_value = null;
            if (!empty($oldValues)) {
                foreach ($oldValues as $old_line) {
                    /*
                     * Compare the recordno of old and current record to find out the
                     * appropriate record to send for validation.
                     */
                    if ($old_line['RECORDNO'] == $value['RECORDNO']) {
                        $old_value = $old_line;
                        break;
                    }
                }
            }
            foreach ($fldsToCompare as $key) {
                /*
                 * Validate and Set if a restricted match is not found and not set
                 * Throw an error if a restriction is not matched but is being set
                 */
                if (is_array($key)) {
                    $key = $key[0];
                }
                $ok = $ok && $this->validateAndSetValues($value, $key, $old_value);
            }
            unset($value);
        }

        return $ok;
    }

    /**
     * The logic for validation is handled here,
     *
     * @param array  &$values   values
     * @param string $key       key
     * @param array  $oldValues oldValues
     *
     * @return bool
     */
    function validateAndSetValues(&$values, $key, $oldValues = array())
    {
        $ok = true;
        $gErr = Globals::$g->gErr;

        if (empty($oldValues)) {
            /*
             * When creating, we do validate the values if they are provided
             * whey they are not supposed to be provided.
             *
             * Also we have to explicitly check the values for decimals changing the
             * datatype to float as the decimal(.) is making the empty function
             * call to return false when the value is 0.00. Hence the cost fields are
             * seperated from basic string empty validation
             */

            $costFlds = array('BEST_COST','LAST_COST','AVERAGE_COST');
            if (in_array($key, $costFlds)) {
                $value = (float) ($values[$key] ?? 0);
            } else {
                $value = $values[$key] ?? '';
            }

            if (!empty($value)) {
                /*
                 * If old values are empty then the operation is considered to be create
                 * Hence we just need to avoid the user from providing a value
                 */
                $gErr->addIAError('INV-0196', __FILE__ . '.' . __LINE__, "Cannot provide value for the field ${key}", ['KEY' => $key]);
                $ok = false;
            }
        } else if (!empty($oldValues)) {
            /*
             * While editing an item
             * IF A CHANGE IS HAPPENNING
             * we have few fields that should not be allowed to change
             * as they might be one time selection
             * or Value might be unique or
             * the value might be calculation dynamically by the business logic.
             * ELSE IF VALUE IS NOT PROVIDED
             * we set the old value to them to maintain consistancy
             *
             */
            $v  = $values[$key]    ?? '';
            $ov = $oldValues[$key] ?? '';
            if (($v != '') && ($ov != $v)) {
                $gErr->addIAError('INV-0197', __FILE__ . '.' . __LINE__, "Cannot Modify the value for ${key}", ['KEY' => $key]);
                $ok = false;
            } else if ($v == '') {
                $values[$key] = $ov;
            }
        }
        return $ok;
    }

    /**
     * API_UpdateMerge
     * This function takes the existing values for a given object, and the new values requested
     * to be applied by an API_Set, and merges them into a single object values array.  By default
     * this function simply lays the new values on top of the existing values.  However, subclasses
     * can override to perform class-specific value merging.
     *
     * @param array $object
     * @param array $values
     *
     * @return array
     */
    function API_UpdateMerge(&$object, &$values)
    {
        /*
         * Owned object that are to be merged will be added to the array below
         * with the respective child KEY and the Key Field to compare.
         */
        $ownedObjs = array(
            /*
             * WAREHOUSEINFO has ITEMWAREHOUSEINFO as child with WAREHOUSEID as key
             */
            'WAREHOUSEINFO' => array(
                'child' => 'ITEMWAREHOUSEINFO',
                'key' => 'WAREHOUSEID'
            ),
            /*
             * VENDORINFO has ITEMVENDOR as child with VENDORID as key
             */
            'VENDORINFO' => array(
                'child' => 'ITEMVENDOR',
                'key' => 'VENDORID'
            )
        );

        /**
         * The business logic to merge the Existing data with the data passed from
         * Gateway is handled here
         *
         * We loop through all the owned objects to check if they are to be updated
         * with respect to the input from the user and do the merge or insert if the values
         * are provided
         */
        foreach ($ownedObjs as $obj => $info) {
            /*
             * Fetch the values from existing data into $oldObjs and
             * values provided by the user to $newObjs
             *
             * KeyField will be stored in $keyFld
             */
            $oldObjs = $object[$obj][isl_strtolower($info['child'])];
            // PHP 8.1 exception error on sending the empty owned objects.
            $newObjs = is_array($values[$obj]) && !empty($values[$obj]) ? $values[$obj][$info['child']] : [];
            $keyFld = $info['key'];

            /**
             * We do not need to perform an insert or update when either one of
             * new or old objects are empty.
             */
            if (!empty($oldObjs) && !empty($newObjs)) {

                /*
                 * If the old objects or new objects are having just single element
                 * being retrieved or passed, We are creating a structure of
                 * obj[0] else we do not change anything existing on new or old objects
                 */
                if (!$oldObjs[0]) {
                    $temp = $oldObjs;
                    $oldObjs = array();
                    $oldObjs[0] = $temp;
                }
                if (!$newObjs[0]) {
                    $temp = $newObjs;
                    $newObjs = array();
                    $newObjs[0] = $temp;
                }

                /*
                 * We store the existing data in finalObjs which will be updated on $object
                 * and will be passed to API_UpdateMerge
                 */
                $finalObjs = $oldObjs;

                /**
                 * We go through all the new objects to check if a record with same keyfield
                 * already exists for the record that user is trying to update
                 *
                 * If the record Exists We Merge the user data to existing data,
                 * Else we add this entry to finalObjs
                 */
                foreach ($newObjs as $newObj) {
                    /*
                     * boolean $set  is the flag we use to check if an entry
                     * is been merged or has to be inserted
                     */
                    $set = false;
                    foreach ($oldObjs as $key => $oldObj) {

                        if ($newObj[$keyFld] == $oldObj[$keyFld]) {
                            /*
                             * if the KeyFields in existing and new entries are matched
                             *   We set the flag for update to true and store the values
                             *   that are merged into finalObjs of oldObject Key
                             */
                            $set = true;
                            $finalObjs[$key] = array_merge_clobber($finalObjs[$key], $newObj);
                        }
                    }
                    /*
                     * If there is no set happened the newEntry will be added to $finalObjs
                     */
                    if ($set == false) {
                        $finalObjs[] = $newObj;
                    }
                }

                /*
                 * Here we are unsetting the $values and $objects children with current
                 * owned object as we are inserting the updated $final objs to the object
                 * that is going to be returned to api_update
                 */
                unset($values[$obj], $object[$obj][isl_strtolower($info['child'])]);
                $object[$obj][$info['child']] = $finalObjs;
            }
        }

        //If Allow multiple tax group is true then unset header level tax group from old data
        //If Allow multiple tax group is false then unset multiple item tax group map from old data
        if ($values['ALLOWMULTIPLETAXGRPS'] == 'true') {
            unset($object['TAXGROUP']);
            unset($object['TAXGROUPKEY']);
        } elseif ($values['ALLOWMULTIPLETAXGRPS'] == 'false') {
            unset($object['ITEMTAXGRPITEMMAPS']);
        }

        return parent::API_UpdateMerge($object, $values);
    }


    /**
     *  make sure at least one vendor is 'preferred' or send an error.
     *
     *      the Preferred Vendor checkboxes follow these rules:
     *      1) If all are explicitly set to FALSE, that’s an error
     *      2) If one is set to TRUE, take that one
     *      3) If multiples are set to TRUE, that’s an error
     *      4) If none are set to TRUE, take the first one that isn’t specified as TRUE
     *
     * Now, what makes this INSANE is that, on an UPDATE, we've already had existing/old fields
     * MERGED with the new fields, so it is impossible to tell if a value is UNSPECIFIED, because
     * it came off disk as FALSE.  Soooooo.... when we were looking at the raw API stuff, we captured
     * the first unspecified value position and it is passed into here as '$firstUnset'.  Or false, if thats not how we got here.
     *
     * @param array       $vendors           the array of vendors
     * @param string      $identifier        identify which venodr group this is
     * @param int|bool    $firstUnset        do we already know the first unset PREFERRED_VENDOR?  If not, it is false
     *
     * @return bool
     */
    private function makeSureOneVendorIsPreferred(&$vendors,$identifier,$firstUnset)
    {
        // ya, crazy, I know, but the values for $firstUnset are:
        //      -1              none of the values are un-set (so, that's an error if there is no TRUE entry)
        //      false           I did not see this array early on in the API (so this is NOT the API, or there were records not set by the API in a merge)
        //      0 or greather   that is the first unset value
        if (((!is_null($vendors)) && (!empty($vendors)))) {
            $firstNotSet = $firstUnset;     // can be false, meaning there is no old data so don't trust the 'first not set', or -1 for 'NONE were not set'
            $firstTrue   = false;
            $vendorNames = [];
            foreach ($vendors as $key => &$entry) {

                // while we're here, check that vendor names are unique
                list($id) = explode('--', $entry['VENDORID']);
                if (isset($vendorNames[$id])) {
                    Globals::$g->gErr->addIAError(
                        'INV-1161',
                        __FILE__ . ":" . __LINE__,
                        sprintf("Vendor '%s' appears more than once in the table", $id),
                        [ 'ID' => $id ]
                    );
                    return false;
                }
                $vendorNames[$id] = true;

                $exists = (isset($entry['PREFERRED_VENDOR']) && ($entry['PREFERRED_VENDOR'] != ''));
                if (!$exists) {
                    if (($firstNotSet === -1) || ($firstNotSet === false)) {    // not previously set, or never examined, and now we discover it IS empty
                        $firstNotSet = $key;    // this is the first not set to anything
                    }
                } else {
                    $entry['PREFERRED_VENDOR'] = strtolower($entry['PREFERRED_VENDOR']);
                    if ($entry['PREFERRED_VENDOR'] == 'true') {
                        if ($firstTrue === false) {
                            $firstTrue = $key; // case 2: ONE (at least) IS SET TO TRUE
                        } else {
                            Globals::$g->gErr->addIAError(
                                'INV-1162',
                                __FILE__ . ":" . __LINE__,
                                sprintf("In %s, there is more than one vendor with PREFERRED_VENDOR set to 'true'.", $identifier),
                                [ 'IDENTIFIER' => $identifier]
                            );
                            return false;   // CASE 3: MORE THAN ONE TRUE
                        }
                    }
                }
            }

            // were ANY of the records set to true?
            if ($firstTrue === false) { // then lets try to set one to true
                if ($firstNotSet === -1) {  // none were empty in the API
                    Globals::$g->gErr->addIAError(
                        'INV-1188',
                        __FILE__ . ":" . __LINE__,
                        "In $identifier, there must be one row with PREFERRED_VENDOR set to 'true'.  They are all set to 'false'",
                        [ 'IDENTIFIER' => $identifier]
                    );
                    return false;   // CASE 1: ALL ARE FALSE
                } else if ($firstNotSet === false) {    // we haven't seen the record before, or not the API
                    $vendors[0]['PREFERRED_VENDOR'] = 'true';   // this would happen on the UI and on CSV for an UPDATE
                } else {
                    $vendors[$firstNotSet]['PREFERRED_VENDOR'] = 'true';    // CASE 4: set the first empty row TRUE
                }
            }
        }
        return true;
    }

    /**
     *  when the API sends us standard costs, they tend to look like this:
     *
     *  'STDCOSTENTRIES' =>
     *       array (
     *           0 =>
     *               array (
     *                   'STDCOSTENTRY' =>
     *                       array (
     *                           0 =>
     *                               array (
     *                               'EFFECTIVE_START_DATE' => '01/20/2016',
     *                               'STANDARD_COST' => '30',
     *                               ),
     *                           1 =>
     *                               array (
     *                               'EFFECTIVE_START_DATE' => '01/20/2017',
     *                               'STANDARD_COST' => '40',
     *                               ),
     *                       ),
     *                  ),
     * -- OR --
     *
     *   'STDCOSTENTRIES' =>
     *       array (
     *           0 =>
     *               array (
     *                   'STDCOSTENTRY' =>
     *                          // NOTE MISSING SUB ARRAY HERE.....
     *                       array (
     *                           'EFFECTIVE_START_DATE' => '01/20
     *                           'STANDARD_COST' => '30',
     *                      ),
     *               ),
     *     ,
     *  etc.
     *  On the other hand, existing values stored have 'STDCOSTENTRIES' with an array of records below it.
     *  So, here, straighten that out if present.
     *
     * @param array $newValues
     */
    private function cleanUpItemWarehouseStandardCosts(&$newValues)
    {
        if (isset($newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'])) {
            foreach ($newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'] as $wKey => $wInfo) {
                if (isset($wInfo['STDCOSTENTRIES'][0]['STDCOSTENTRY'])) {
                    $newEntries = [];
                    $oldEntries = (is_array($wInfo['STDCOSTENTRIES'][0]['STDCOSTENTRY'][0])) ? $wInfo['STDCOSTENTRIES'][0]['STDCOSTENTRY'] : $wInfo['STDCOSTENTRIES'][0];
                    foreach ($oldEntries as $stdCostEntry) {
                        $keep = false;
                        foreach ($stdCostEntry as $field) {
                            if ($field != '') {
                                $keep = true;
                                break;
                            }
                        }
                        if ($keep) {
                            $newEntries[] = $stdCostEntry;  // save the entries
                        }
                    }
                    if (count($newEntries)) {
                        unset($newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'][$wKey]['STDCOSTENTRIES']);
                        $newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'][$wKey]['STDCOSTENTRIES'] = $newEntries; // REPLACE the STDCOSTENTRY array with its contents
                    }
                }
            }
        }
    }



    /**
     *  Remove empty item warehouse and vendor records
     * @param array $newValues
     */
    private function cleanUpItemWarehouseAndVendor(&$newValues)
    {
        if (isset($newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'])) {
            foreach ($newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'] as $wKey => $wInfo) {
                $keep = false;
                foreach ($wInfo as $field) {
                    if (!is_array($field) && ($field != '')) {
                        $keep = true;
                        break;
                    }
                }
                if ($keep == false) {
                    unset($newValues['WAREHOUSEINFO']['ITEMWAREHOUSEINFO'][$wKey]);
                }
            }
        }

        if (isset($newValues['VENDORINFO']['ITEMVENDOR'])) {
            foreach ($newValues['VENDORINFO']['ITEMVENDOR'] as $key => $vendor) {
                $keep = false;
                foreach ($vendor as $field) {
                    if (!is_array($field) && ($field != '')) {
                        $keep = true;
                        break;
                    }
                }
                if ($keep == false) {
                    unset($newValues['VENDORINFO']['ITEMVENDOR'][$key]);
                }
            }
        }

        // and apparently we allow folks to define vendor info any darn way they WANT!
        // QA has examples of VENDOR_INFO and the above VENDORINFO/ITEMVENDOR.  Sheesh.
        if (isset($newValues['VENDOR_INFO'])) {
            foreach ($newValues['VENDOR_INFO'] as $key => $vendor) {
                $keep = false;
                if (true === \is_countable($vendor)) {
                    foreach ($vendor as $field) {
                        if (!is_array($field) && ($field != '')) {
                            $keep = true;
                            break;
                        }
                    }
                }
                if ($keep == false) {
                    unset($newValues['VENDOR_INFO'][$key]);
                }
            }
        }
    }


    /**
     * API_ValidateObject
     *    This function is called by both the Create and Update API functions.  It takes the existing
     *   values for a given object (if this is an update), and the new values requested
     *   to be applied (for both Create and Update), and validates that these values can be used.
     *
     *   This override lets us see what was actually specified by the client.  After here, we get a combined record.
     *
     * @param array $newValues      Set of given input values to create/update (associative name/value pairs)
     * @param array $existingValues Set of existing values for Update - pass as null for Create (assoc name/values)
     *
     * @return bool True if the update is allowed, false otherwise (with errors on stack)
     */
    function API_ValidateObject(&$newValues, $existingValues)
    {
        $itemType = $existingValues['ITEMTYPE'] ?? $newValues['ITEMTYPE'];   // if an add, there are no old values
        $ok = $this->apiFieldValidation($itemType, $newValues);
        if ($ok) {
            $this->cleanUpItemWarehouseStandardCosts($newValues);
            $this->cleanUpItemWarehouseAndVendor($newValues);
        }

        return ($ok && parent::API_ValidateObject($newValues, $existingValues));
    }


    /**
     *  on a SET or CREATE call, this is invoked to make sure things are set right
     *
     * @param array $values
     *
     * @return array
     */
    public function API_FormatObject($values)
    {
        $values = parent::API_FormatObject($values);

        $itemtype = $values['ITEMTYPE'];
        $costMethod = $this->GetItemCostMethod($values);
        $replenishmentOn = self::isReplenishmentOn();

        if ($replenishmentOn && isset($values['VENDOR_INFO'])) {

            foreach($values['VENDOR_INFO'] as $sKey => $vendor){
                if(empty($vendor)){
                    unset($values['VENDOR_INFO'][$sKey]);
                }
            }

            $firstUnset = $this->firstEmptyPreferredVendor['NON_WAREHOUSE'] ?? false;
            $this->makeSureOneVendorIsPreferred($values['VENDOR_INFO'], 'VENDORINFO', $firstUnset);  // may generate errors
        }

        // prepare the tracking info if it has any
        foreach ((($values['WAREHOUSE_INFO']) ?? []) as $wKey => $wInfo) {
            foreach((($wInfo['STDCOSTENTRIES']) ?? []) as $sKey => $stdCostEntry){
                if(empty($stdCostEntry)){
                    unset($values['WAREHOUSE_INFO'][$wKey]['STDCOSTENTRIES'][$sKey]);
                }
            }

            if (isset($wInfo['REPLENISHMENT_METHOD']) && $wInfo['REPLENISHMENT_METHOD'] != '') {
                self::getReplenishmentMethods($internal,$external);
                $rm = $wInfo['REPLENISHMENT_METHOD'];
                $key = array_search(strtolower($rm), array_map('strtolower', $external));
                if ($key === false) {
                    $externalImplode = implode("', '", $external);
                    Globals::$g->gErr->addIAError(
                        'INV-1189',
                        __FILE__ . ":" . __LINE__,
                        "The REPLENISHMENT_METHOD of '$rm' is not correct.  It should be one of '" . $externalImplode . "'",
                        [ 'VALUE' => $rm, 'EXTERNAL' => $externalImplode]
                    );
                } else {
                    $values['WAREHOUSE_INFO'][$wKey]['REPLENISHMENT_METHOD'] = $external[$key];
                }
                $internal = []; // avoid the inspection error saying we didn't use it...
            } else {
                $values['WAREHOUSE_INFO'][$wKey]['REPLENISHMENT_METHOD'] = $values['REPLENISHMENT_METHOD'];
            }

            if ($replenishmentOn && isset($wInfo['ITEMWAREHOUSEVENDORENTRIES'])) {
                foreach($wInfo['ITEMWAREHOUSEVENDORENTRIES'] as $sKey => $vendor){
                    $empty = empty($vendor);
                    if (!$empty) {
                        $empty = true;  // lets assume it is empty until we prove it is not
                        foreach ($vendor as $vValue) {
                            if ($vValue != '') {
                                $empty = false;
                                break;
                            }
                        }
                    }
                    if($empty){
                        unset($values['WAREHOUSE_INFO'][$wKey]['ITEMWAREHOUSEVENDORENTRIES'][$sKey]);
                    }
                }
                $firstUnset = $this->firstEmptyPreferredVendor[$wKey] ?? false;
                $this->makeSureOneVendorIsPreferred($values['WAREHOUSE_INFO'][$wKey]['ITEMWAREHOUSEVENDORENTRIES'], 'WAREHOUSE_INFO for ' . $wInfo['WAREHOUSEID'], $firstUnset);  // may generate errors
            }

            if (isset($wInfo['STDCOSTENTRIES']['STDCOSTENTRY'])) {
                if (is_array($wInfo['STDCOSTENTRIES']['STDCOSTENTRY'][0])){
                    $costEntries = $wInfo['STDCOSTENTRIES']['STDCOSTENTRY'];
                } else{
                    $costEntries = array($wInfo['STDCOSTENTRIES']['STDCOSTENTRY']);
                }

                $newCostEntries = array();
                foreach($costEntries as $cEntry){
                    if($cEntry['EFFECTIVE_START_DATE']!='' || $cEntry['STANDARD_COST']!=''){
                        $newCostEntries[] = $cEntry;
                    }
                }
                unset($values['WAREHOUSE_INFO'][$wKey]['STDCOSTENTRIES']);
                $values['WAREHOUSE_INFO'][$wKey]['STDCOSTENTRIES'] = $newCostEntries;
            }

            if ($itemtype == 'Inventory' &&
                $costMethod == 'Standard' &&
                (isset($wInfo['STANDARD_COST']) && $wInfo['STANDARD_COST'] != '')) {
                //
                // This is for backward compatibility
                // If customer continues to provide the Warehouse > Standard Cost (whichis no more supported from May2017 release)
                // make an additional entry in the Warehouse Standard cost with current date
                // only if there is no entry for current date
                $currDate = GetCurrentDate();
                $hasCurrDateEntry = false;
                foreach($values['WAREHOUSE_INFO'][$wKey]['STDCOSTENTRIES'] ?? [] as $costEntry){
                    if(DateCompare($currDate, $costEntry['EFFECTIVE_START_DATE']) == 0){
                        $hasCurrDateEntry = true;
                        break;
                    }
                }
                if(!$hasCurrDateEntry){
                    $values['WAREHOUSE_INFO'][$wKey]['STDCOSTENTRIES'][] = array('EFFECTIVE_START_DATE' => $currDate,
                        'STANDARD_COST' => $wInfo['STANDARD_COST']);
                }
            }
        }

        //When the values come from the API call, the key name comes as caps , but loaded from the ent comes as lowercase
        if (isset($values['LANDEDCOSTINFO']['ITEMLANDEDCOST']) ||
            isset($values['LANDEDCOSTINFO']['itemlandedcost'])) {
             $labelName= isset($values['LANDEDCOSTINFO']['ITEMLANDEDCOST']) ? 'ITEMLANDEDCOST' : 'itemlandedcost';
            if (is_array($values['LANDEDCOSTINFO'][$labelName][0])) {
                $values['LANDEDCOSTINFO'] = $values['LANDEDCOSTINFO'][$labelName];
            } else {
                $values['LANDEDCOSTINFO'] = array($values['LANDEDCOSTINFO'][$labelName]);
            }
        }

        // for now we are not supporting handling item cross reference records create/update of item through 3.0 API
        // TODO: plan is to support item cross reference record through 3.0 API in 2022 R2
        unset($values['ITEMCROSSREFERENCES']);

        return $values;
    }

    /**
     * @param array $values
     *
     * @return string
     */
    function GetItemCostMethod($values){
        if (!isset($values['COST_METHOD']) || empty($values['COST_METHOD'])) {
            $defCostMethod = GetPreferenceForProperty(Globals::$g->kINVid, 'DEFAULT_COST_METHOD');
            if (!empty($defCostMethod)) {
                $defCostMethod = $this->_TransformInternalValue('COST_METHOD', $defCostMethod);
                $costMethod = ($defCostMethod && $defCostMethod != '') ? $defCostMethod : 'Standard';
            }
            else
            {
                $costMethod = 'Standard';
            }
        }else{
            $costMethod = $values['COST_METHOD'];
        }

        return $costMethod;
    }

    /**
     * In Simplified workflow, SYS_ITEMGLGRP records don't get delete, as a result traces will left out in the db
     * @param string $ID
     *
     * @return bool
     */
    public function Delete($ID) {
        $source = __METHOD__;

        $ok = $this->beginTrx($source);
        if ($ok) {
            $ok = parent::Delete($ID);
            $ok = $ok && ContractUtil::checkContractPriceListForItem($ID);

            if ($ok && !IsAdvancedConfiguration()) {
                $query = "DELETE FROM ICITEMGLGRP where cny# = ".GetMyCompany()." and NAME = 'SYS_ITEMGLGRP_".$ID."'";
                $ok = $ok && ExecStmt(array($query));
            }

            $ok = $ok && $this->commitTrx($source);
            if (!$ok) {
                $this->rollbackTrx($source);
            }
        }
        return $ok;
    }



    /**
     *  API_pruneFields
     *   This override of the Entity Manager version looks deeper into the tree of returned values for items.
     *
     * @param array             $values
     * @param string|string[]   $fields
     *
     * @return array
     */
    function API_pruneFields(&$values, $fields)
    {
        $additionalApiPrune = '';

        // If the replenishment feature is off, we want to prune those fields involved with replenishment
        //  (I don't see this happening anywhere else, but that's the way our QA wants it)
        $inventoryItem = in_array($values['ITEMTYPE'], array(INVENTORY, KIT, STOCKABLE_KIT));
        if ( ($inventoryItem == false) || (self::isReplenishmentOn() == false)) {

            $additionalApiPrune = 'LESS_GET_FIELDS_NO_REPLENISHMENT';

            // remove the item warehoue vendor entries from being revealed entirely!
            if (isset($values['WAREHOUSEINFO']['itemwarehouseinfo'])) {
                foreach($values['WAREHOUSEINFO']['itemwarehouseinfo'] as &$warehouseInfo) {
                    // Remove the entirety of item-warehouse-vendor entries
                    if (isset($warehouseInfo['ITEMWAREHOUSEVENDORENTRIES'])) {
                        unset($warehouseInfo['ITEMWAREHOUSEVENDORENTRIES']);
                    }
                }
            }
        } else { // replenishment is ON and it IS an inventory item
            // make sure at least one vendor is labeled 'preferred'
            // also remove fields from itemwarehouseinfo where Replenishment is OFF for the warehouse
            if (isset($values['WAREHOUSEINFO']['itemwarehouseinfo'])) {

                $warehousesNotEnabledForReplenishment = $this->getWarehousesWithoutReplenishment();
                $warehouseManager = Globals::$g->gManagerFactory->getManager('itemwarehouseinfo');

                foreach($values['WAREHOUSEINFO']['itemwarehouseinfo'] as &$warehouseInfo) {

                    if (isset($warehousesNotEnabledForReplenishment[ $warehouseInfo['WAREHOUSEID']])) {

                        // Remove the entirety of item-warehouse-vendor entries
                        if (isset($warehouseInfo['ITEMWAREHOUSEVENDORENTRIES'])) {
                            unset($warehouseInfo['ITEMWAREHOUSEVENDORENTRIES']);
                        }
                        // brute force remove fields....
                        $warehouseManager->API_pruneFieldsOwnedToo($warehouseInfo, '*', 'LESS_GET_FIELDS_NO_REPLENISHMENT');

                    } else {
                        if (isset($warehouseInfo['ITEMWAREHOUSEVENDORENTRIES'])) {
                            $preferredFound = false;
                            $firstKey = NULL;
                            foreach ($warehouseInfo['ITEMWAREHOUSEVENDORENTRIES'] as $key => $oneVendotrEntry) {
                                if ($firstKey == NULL) {
                                    $firstKey = $key;
                                }
                                if (isset($oneVendotrEntry['PREFERRED_VENDOR']) && ($oneVendotrEntry['PREFERRED_VENDOR'] == 'true')) {  // true, not T (this is already exterior format)
                                    $preferredFound = true;
                                    break;
                                }
                            }
                            if (!$preferredFound && ($firstKey != NULL)) {
                                $warehouseInfo['ITEMWAREHOUSEVENDORENTRIES'][$firstKey]['PREFERRED_VENDOR'] = 'true';
                            }
                        }
                    }
                }
            }

            // Same thing for the list of vendors without warehouses
            if (isset($values['VENDORINFO']['itemvendor'])) {
                $preferredFound = false;
                $firstKey       = null;
                foreach ($values['VENDORINFO']['itemvendor'] as $key => &$oneVendotrEntry) {
                    if ($firstKey == null) {
                        $firstKey = $key;
                    }
                    if (isset($oneVendotrEntry['PREFERRED_VENDOR']) && ($oneVendotrEntry['PREFERRED_VENDOR'] == 'true')) {
                        $preferredFound = true;
                        break;
                    }
                }
                if ( ! $preferredFound && ($firstKey != null)) {
                    $values['VENDORINFO']['itemvendor'][$firstKey]['PREFERRED_VENDOR'] = 'true';
                }
            }
        }
        return $this->API_pruneFieldsOwnedToo($values, $fields, $additionalApiPrune); // we want owned items as well
    }

    /**
     *  is the replenishment preference on?
     * @return bool
     */
    public static function isReplenishmentOn()
    {
        static $isOn = null;    // we call this a number of times
        if ($isOn == null) {
            global $kINVid;
            $inventoryPrefs = array();
            GetModulePreferences($kINVid, $inventoryPrefs);
            $isOn = ($inventoryPrefs['AI_REPLENISHMENTS'] == 'T');  // in its internal form here
        }
        return $isOn;
    }

    /**
     * @param string[]  $internal   OUTPUT
     * @param string[]  $external   OUTPUT
     */
    public static function getReplenishmentMethods(&$internal,&$external)
    {
        global $gSalesForecastMethodValues, $gSalesForecastMethodIValues;
        $internal = $gSalesForecastMethodIValues;
        $external = $gSalesForecastMethodValues;
    }

    /**
     * @param int $itemKey
     * @param int $limitReplyTo // so we don't overwhelm the UI, for example
     *
     * @return array
     */
    public function getItemBinsInventory($itemKey, $limitReplyTo = 500)
    {
        $itemBinsInventory = [];
        if ($itemKey == null) {
            return $itemBinsInventory;
        }

        $dateinfield_field = " datereceived ";
        $exprdatefield_field = " expiration_date ";
        if (Profile::exists()) {
            // Here changing date format to user preference format
            $format = GetUserDateLabel();
            $dateinfield_field = " to_char(datereceived,'$format') ";
            $exprdatefield_field = " to_char(expiration_date,'$format') ";
        }

        /**
         * Get the fields.  Use the view v_availableinventory to do the work
         */
        $qry   = [];
        $qry[] = "SELECT item_id                       AS itemid,
                         bin_id                        AS bin,
                         serial_no                     AS serialno,
                         lot_no                        AS lotno,
                         $exprdatefield_field          AS expiration,
                         qty_left                      AS qoh,
                         qty_allocated                 AS qoa,
                         qty_reserved                  AS qor,
                         (qty_left - qty_reserved - qty_allocated) AS qoun,
                         itemdesc,
                         unit,        
                         $dateinfield_field            AS datereceived,
                         warehouse
                   FROM  v_availableinventorymst
                   WHERE cny# = :1
                     AND item_id = :2
                   ORDER BY datereceived 
                   FETCH FIRST $limitReplyTo ROWS ONLY";
        $qry[] = GetMyCompany();
        $qry[] = $itemKey;

        $itemBinsInventory = QueryResult($qry);

        return $itemBinsInventory;
    }

    /**
     * @param string $uomtype
     * @param string $uomvalue
     * @return bool
     */
    private function validationUOMFeilds($uomtype, &$uomvalue)
    {
        if ($uomtype == '' || $uomvalue == '') {
            return true;
        }

        $type = '';
        $fields = '';
        switch ($uomtype) {
            case 'WEIGHT':
                $type = 'Weight';
                $fields = 'Weight UOM';
                break;
            case 'LENGTH':
                $type = 'Length';
                $fields = 'Length UOM';
                break;
            case 'AREA':
                $type = 'Area';
                $fields = 'Area UOM';
                break;
            case 'VOLUME':
                $type = 'Volume';
                $fields = 'Volume UOM';
                break;
            case 'THICKNESS':
                $type = 'Length';
                $fields = 'Thickness UOM';
                break;
            case 'DIAMETER':
                $type = 'Length';
                $fields = 'Diameter UOM';
                break;
        }

        if ($uomtype == '' || $type == '') {
            return true;
        }

        $gErr = Globals::$g->gErr;
        $uomMgr = Globals::$g->gManagerFactory->getManager('uom');
        $filter = [
            'selects' => ['UOMDETAIL.UNIT'],
            'filters' => [
                [
                    ['UOMDETAIL.UNIT', '=', $uomvalue],
                    ['NAME', '=', $type],
                ]
            ]
        ];
        if (is_numeric($uomvalue)) {
            $filter['filters'] = [
                [
                    ['UOMDETAIL.RECORDNO', '=', $uomvalue],
                    ['NAME', '=', $type],
                ]
            ];

        }
        $result = $uomMgr->GetList($filter);

        if (!$result) {
            $msg = $uomvalue . " is not a valid " . $fields . ". Enter a valid value, then try again.";
            $gErr->addIAError(
                'INV-1163',
                __FILE__ . ':' . __LINE__,
                "",[],
                "", [],
                $msg,[ 'UOMVALUE' => $uomvalue, 'FIELDS' =>$fields]
            );
            return false;
        }
        elseif (is_numeric($uomvalue) && is_array($result) && isset($result[0]['UOMDETAIL.UNIT'])) {
            $uomvalue = $result[0]['UOMDETAIL.UNIT'];
        }

        return true;
    }
    /**
     * @param array $values
     * @return bool
     */
    private function validateThicknessUOMDetails($values)
    {
        $gErr = Globals::$g->gErr;
        if ($values['THICKNESS'] != '') {
            // Thickness validation
            // IF any value is provided for THICKNESS feild, THICKNESSUOM should be mandatory
            if ($values['THICKNESSUOM'] == '') {
                $msg = "Select a Thickness UOM. Then, try again.";
                $gErr->addIAError('INV-1164', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }

            // IF any value is provided for THICKNESS feild
            // MINIMUMTHICKNESS and MAXIMUMTHICKNESS are mandatory
            if ($values['MINIMUMTHICKNESS'] == '' || $values['MAXIMUMTHICKNESS'] == '') {
                $msg = "Enter values for both Minimum thickness and Maximum thickness. Then, try again.";
                $gErr->addIAError('INV-1165', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }

            // IF any value is provided for THICKNESS feild
            // THICKNESS values must be in the between range of MINIMUMTHICKNESS and MAXIMUMTHICKNESS
            if ($values['MINIMUMTHICKNESS'] != '' && $values['MAXIMUMTHICKNESS'] != ''
                && ($values['THICKNESS'] < $values['MINIMUMTHICKNESS']
                    || $values['THICKNESS'] > $values['MAXIMUMTHICKNESS'])) {
                $msg = "Enter a value for Thickness that is between the values of Minimum and Maximum thickness. Then, try again.";
                $gErr->addIAError('INV-1166', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }

        } else {
            // IF any value is provided for THICKNESSUOM feild then THICKNESS should be mandatory
            if ($values['THICKNESSUOM'] != '') {
                $msg = "Enter a value for Thickness. Then, try again.";
                $gErr->addIAError('INV-1167', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }

            // IF any value is provided for MINIMUMTHICKNESS and MAXIMUMTHICKNESS feild
            // THICKNESS should be mandatory
            if ($values['MINIMUMTHICKNESS'] != '' && $values['MAXIMUMTHICKNESS'] != '') {
                $msg = "Enter a value for Thickness. Then, try again.";
                $gErr->addIAError('INV-1168', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }
        }

        // IF any value is provided for THICKNESSUOM feild then THICKNESS should be mandatory
        if (($values['MINIMUMTHICKNESS'] != '' && $values['MAXIMUMTHICKNESS'] == '')
            || ($values['MINIMUMTHICKNESS'] == '' && $values['MAXIMUMTHICKNESS'] != '')) {
            $msg = "Ensure that values are entered for both Minimum thickness and Maximum thickness. Then, try again.";
            $gErr->addIAError('INV-1169', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // MAXIMUMTHICKNESS should not be less than or equal to MINIMUMTHICKNESS
        if ($values['MAXIMUMTHICKNESS'] < $values['MINIMUMTHICKNESS']) {
            $msg = "Enter a value for Maximum thickness that is larger than the value for Minimum thickness. Then, try again.";
            $gErr->addIAError('INV-1170', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateNetweightUOMDetails($values)
    {
        $gErr = Globals::$g->gErr;
        if($values['NETWEIGHT'] != ''){
            // IF any value is provided for NETWEIGHT or SHIP_WEIGHT feild, WEIGHTUOM should be mandatory
            if ($values['WEIGHTUOM'] == '') {
                $msg = "Select a Weight UOM. Then, try again.";
                $gErr->addIAError('INV-1171', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }

            // IF any value is provided for NETWEIGHT feild, SHIP_WEIGHT should be mandatory
            if ($values['SHIP_WEIGHT'] == '') {
                $msg = "Enter a value for Shipping weight. Then, try again.";
                $gErr->addIAError('INV-1172', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }

            // SHIP_WEIGHT should not be less than or equal to NETWEIGHT
            if ($values['SHIP_WEIGHT'] != ''&& $values['SHIP_WEIGHT'] <= $values['NETWEIGHT']) {
                $msg = "Enter a value for Net weight that is less than the value of Shipping weight. Then, try again.";
                $gErr->addIAError('INV-1173', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }
        }else{
            // IF any value is provided for WEIGHTUOM feild, NETWEIGHT should be mandatory
            if ($values['WEIGHTUOM'] != '') {
                $msg = "Enter a value for Net weight. Then, try again.";
                $gErr->addIAError('INV-1174', __FILE__ . ':' . __LINE__, "", [], $msg, []);
                return false;
            }
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateLWHUOMDetails($values)
    {
        $gErr = Globals::$g->gErr;
        if ($values['LWHUOM'] != ''
            && ($values['LENGTH'] == '' || $values['WIDTH'] == '' || $values['HEIGHT'] == '')) {
            $msg = "Enter a value for Length/Width/Height. Then, try again.";
            $gErr->addIAError('INV-1175', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        if ($values['LWHUOM'] == ''
            && ($values['LENGTH'] != '' || $values['WIDTH'] != '' || $values['HEIGHT'] != '')) {
            $msg = "Select a Length, Width, Height UOM. Then, try again.";
            $gErr->addIAError('INV-1176', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateAreaUOMDetails($values)
    {
        $gErr = Globals::$g->gErr;
        // IF any value is provided for AREA feild, AREAUOM should be mandatory
        if ($values['AREAUOM'] == '' && $values['AREA'] != '') {
            $msg = "Select an Area UOM. Then, try again.";
            $gErr->addIAError('INV-1177', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // IF any value is provided for AREAUOM feild, AREA should be mandatory
        if ($values['AREAUOM'] != '' && $values['AREA'] == '') {
            $msg = "Enter a value for Area. Then, try again.";
            $gErr->addIAError('INV-1178', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateVolumeUOMDetails($values)
    {
        $gErr = Globals::$g->gErr;
        // IF any value is provided for VOLUME feild, VOLUMEUOM should be mandatory
        if ($values['VOLUMEUOM'] == '' && $values['VOLUME'] != '') {
            $msg = "Select a Volume UOM. Then, try again.";
            $gErr->addIAError('INV-1179', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // IF any value is provided for VOLUMEUOM feild, VOLUME should be mandatory
        if ($values['VOLUMEUOM'] != '' && $values['VOLUME'] == '') {
            $msg = "Enter a value for Volume. Then, try again.";
            $gErr->addIAError('INV-1180', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateDiameterUOMDetails($values)
    {
        $gErr = Globals::$g->gErr;
        // IF any value is provided for INNERDIAMETER or OUTERDIAMETER feilds
        // DIAMETERUOM should be mandatory
        if ($values['DIAMETERUOM'] == '' && ($values['INNERDIAMETER'] != '' || $values['OUTERDIAMETER'] != '')) {
            $msg = "Select a Diameter UOM. Then, try again.";
            $gErr->addIAError('INV-1181', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // IF any value is provided for INNERDIAMETER or OUTERDIAMETER feilds
        // both INNERDIAMETER and OUTERDIAMETER should be mandatory
        if (($values['INNERDIAMETER'] != '' && $values['OUTERDIAMETER'] == '')
            || ($values['INNERDIAMETER'] == '' && $values['OUTERDIAMETER'] != '')) {
            $msg = "Enter values for both Inner diameter and Outer diameter. Then, try again.";
            $gErr->addIAError('INV-1182', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // IF any value is provided for DIAMETERUOM feilds
        // INNERDIAMETER and OUTERDIAMETER should be mandatory
        if ($values['DIAMETERUOM'] != '' && ($values['INNERDIAMETER'] == '' || $values['OUTERDIAMETER'] == '')) {
            $msg = "Enter values for both Inner diameter and Outer diameter. Then, try again.";
            $gErr->addIAError('INV-0688', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // IF any value is provided for INNERDIAMETER and OUTERDIAMETER feilds
        // INNERDIAMETER must be less than or equal to OUTERDIAMETER
        if ($values['INNERDIAMETER'] > $values['OUTERDIAMETER']) {
            $msg = "Enter a value for Outer diameter that is greater than the value for Inner diameter. Then, try again.";
            $gErr->addIAError('INV-1183', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateOtherAttributes($values)
    {
        $gErr = Globals::$g->gErr;
        // IF any value is provided for UPC12 feild then should not be more then 12 numberic digits
        if ($values['UPC12'] != '' && strlen($values['UPC12']) != 12) {
            $msg = "For UPC-12, enter a value that is 12 numeric digits. Then, try again.";
            $gErr->addIAError('INV-1184', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        // IF any value is provided for EAN13 feild then should not be more then 13 numberic digits
        if ($values['EAN13'] != '' && strlen($values['EAN13']) != 13) {
            $msg = "For EAN-13, enter a value that is 13 numeric digits. Then, try again.";
            $gErr->addIAError('INV-1185', __FILE__ . ':' . __LINE__, "", [], $msg, []);
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     * @return bool
     */
    private function validateItemAttributes(&$values)
    {
        $ok = true;
        $ok = $ok && $this->validationUOMFeilds('WEIGHT', $values['WEIGHTUOM']);
        $ok = $ok && $this->validationUOMFeilds('VOLUME', $values['VOLUMEUOM']);
        $ok = $ok && $this->validationUOMFeilds('AREA', $values['AREAUOM']);
        $ok = $ok && $this->validationUOMFeilds('LENGTH', $values['LWHUOM']);
        $ok = $ok && $this->validationUOMFeilds('THICKNESS', $values['THICKNESSUOM']);
        $ok = $ok && $this->validationUOMFeilds('DIAMETER', $values['DIAMETERUOM']);
        $ok = $ok && $this->validateNetweightUOMDetails($values);
        $ok = $ok && $this->validateLWHUOMDetails($values);
        $ok = $ok && $this->validateAreaUOMDetails($values);
        $ok = $ok && $this->validateVolumeUOMDetails($values);
        $ok = $ok && $this->validateDiameterUOMDetails($values);
        $ok = $ok && $this->validateThicknessUOMDetails($values);
        $ok = $ok && $this->validateOtherAttributes($values);

        return $ok;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    public function calculateInvTotals(&$obj)
    {
        $computedTotals = $this->calculateAvailAndUncommittedtotals($obj['IONORDER'],
            $obj['IONHAND'],
            $obj['IONHOLD'],
            $obj['IINTRANSIT'],
            $obj['IRESERVED'],
            $obj['IALLOCATED']);
        $obj['IAVAILABLE']      = $computedTotals['AVAILABLE'];
        $obj['IUNCOMMITTED']    = $computedTotals['UNCOMMITTED'];


        foreach( $obj['WAREHOUSE_INFO'] as &$whse) {
            $computedWTotals = $this->calculateAvailAndUncommittedtotals($whse['WONORDER'],
                $whse['WONHAND'],
                $whse['WONHOLD'],
                $whse['WINTRANSIT'],
                $whse['WRESERVED'],
                $whse['WALLOCATED']);
            $whse['WAVAILABLE']     = $computedWTotals['AVAILABLE'];
            $whse['WUNCOMMITTED']   = $computedWTotals['UNCOMMITTED'];
        }
        return true;
    }

    /**
     * @param array $values
     * @param array $oldValues
     *
     * @return bool
     */
    private function canPreferencesBeDisabled($values, $oldValues)
    {
        $ok = true;

        $ok = $ok && $this->canDisabledTrackingPreference($values, $oldValues);

        $ok = $ok && $this->canDisabledLandedCostPreference($values, $oldValues);

        return $ok;
    }

    /**
     * @param array $values
     * @param array $oldValues
     *
     * @return bool
     */
    private function canDisabledLandedCostPreference($values, $oldValues)
    {
        if ($oldValues['ENABLELANDEDCOST'] === 'true' && $values['ENABLELANDEDCOST'] === 'false') {

            $params = [];
            $params[0] = "SELECT count(de.itemkey) AS landedcostcount   
                          FROM docentrymst de
                             INNER JOIN icitem it ON it.cny# = de.cny#
                                                     AND it.itemid = de.itemkey
                          WHERE
                            de.cny# = :1
                            AND de.lccatkey IS NOT NULL
                            AND de.itemkey = :2 ";
            $params[1] = GetMyCompany();
            $params[2] = $values['ITEMID'];
            $res = QueryResult($params);

            if (($res[0]['LANDEDCOSTCOUNT'] ?? 0) > 0) {
                Globals::$g->gErr->addIAError('INV-0198', __FILE__ . ":" . __LINE__,
                    "",[],"To disable landed costs, first delete the transactions that use non-inventory items enabled for landed costs to distribute the landed costs to inventory items. Then, try again.", []);
                return false;
            }
        }

        return true;
    }

    /**
     * @param string $onorder
     * @param string $onhand
     * @param string $onhold
     * @param string $intransit
     * @param string $reserved
     * @param string $allocated
     *
     * @return array
     */
    public function calculateAvailAndUncommittedtotals($onorder, $onhand, $onhold, $intransit, $reserved, $allocated)
    {
        // we will call this routine A LOT, so cache these flags....
        static $includeOrders    = null;
        static $includeIntransit = null;
        if ($includeOrders === null) {
            global $kINVid;
            //if the preference is not set, then default is taken as true for INCLUDEONORDER
            $includeOrders    = (GetPreferenceForProperty($kINVid, 'INCLUDEONORDER') === 'F') ? false : true;
            //if the preference is not set, then default is taken as false for INCLUDEINTRANSIT
            $includeIntransit = (GetPreferenceForProperty($kINVid, 'INCLUDEINTRANSIT') === 'T') ? true : false;
        }

        $computedTotals = [];
        $computedTotals['AVAILABLE'] = ibcsub($onhand,$onhold,14,1) ;

        if($includeOrders){
            $computedTotals['AVAILABLE']  = ibcadd( $computedTotals['AVAILABLE'] ,$onorder,14,1) ;

        }
        if($includeIntransit){
            $computedTotals['AVAILABLE'] = ibcadd($computedTotals['AVAILABLE'] ,$intransit,14,1) ;

        }
        $computedTotals['UNCOMMITTED'] = ibcsub(ibcsub($onhand, $reserved,14,1),
            $allocated,14,1)  ;
        return $computedTotals;
    }


    /**
     * @param array $values
     * @param array $oldValues
     *
     * @return bool
     */
    private function canDisabledTrackingPreference($values, $oldValues)
    {
        $ok = true;
        $trackingPrefDisabled = false;

        if ($oldValues['ENABLE_SERIALNO'] === 'true' && $values['ENABLE_SERIALNO'] === 'false') {
            $trackingPrefDisabled = true;
        }

        if ($oldValues['ENABLE_LOT_CATEGORY'] === 'true' && $values['ENABLE_LOT_CATEGORY'] === 'false') {
            $trackingPrefDisabled = true;
        }

        if ($oldValues['ENABLE_BINS'] === 'true' && $values['ENABLE_BINS'] === 'false') {
            $trackingPrefDisabled = true;
        }

        if ($oldValues['ENABLE_EXPIRATION'] === 'true' && $values['ENABLE_EXPIRATION'] === 'false') {
            $trackingPrefDisabled = true;
        }

        if (!$trackingPrefDisabled) {
            return $this->canEnableTrackingPreference($values, $oldValues);
        }

        $params = [];
        $params[0] = "SELECT 
                            count(detrk.serialno)           AS   serialcount,
                            count(detrk.lotno)              AS   lotcount,
                            count(detrk.aislekey)           AS   aislecount,
                            count(detrk.rowkey)             AS   rowcount,
                            count(detrk.binkey)             AS   bincount,
                            count(detrk.expirationdate)     AS   expirationcount 
                    FROM docentrytrackdetail detrk
                    INNER JOIN icitem it ON it.cny# = detrk.cny#
                                         AND it.itemid = detrk.itemkey
                    WHERE detrk.cny# = :1 
                    AND detrk.itemkey = :2 ";
        $params[1] = GetMyCompany();
        $params[2] = $values['ITEMID'];
        $res = QueryResult($params);

        if (count($res ?? []) > 0) {
            $res = $res[0];
            if ($values['ENABLE_SERIALNO'] === 'false' && $res['SERIALCOUNT'] > 0) {
                Globals::$g->gErr->addIAError('INV-0199', __FILE__ . ":" . __LINE__,"", [],
                    "To disable serial tracking, first delete the transactions that use serial numbers. Then, try again.", []);
                $ok = false;
            }

            if ($values['ENABLE_LOT_CATEGORY'] === 'false' && $res['LOTCOUNT'] > 0) {
                Globals::$g->gErr->addIAError('INV-0200', __FILE__ . ":" . __LINE__,"", [],
                    "To disable lot tracking, first delete the transactions that use lot numbers. Then, try again.", []);
                $ok = false;
            }
            if ($values['ENABLE_BINS'] === 'false'
                && ($res['AISLECOUNT'] > 0 || $res['ROWCOUNT'] > 0 || $res['BINCOUNT'] > 0)) {
                Globals::$g->gErr->addIAError('INV-0201', __FILE__ . ":" . __LINE__,"", [],
                    "To disable bin tracking, first delete the transactions that use bin information. Then, try again.", []);
                $ok = false;
            }
            if ($values['ENABLE_EXPIRATION'] === 'false' && $res['EXPIRATIONCOUNT'] > 0) {
                Globals::$g->gErr->addIAError('INV-0202', __FILE__ . ":" . __LINE__,"", [],
                    "To disable expiration tracking, first delete the transactions that use expiration dates. Then, try again.", []);
                $ok = false;
            }
        }

        // if we're good so far, see if they're trying to ENABLE preferences...
        return $ok && $this->canEnableTrackingPreference($values, $oldValues);
    }


    /**
     *  Can we enable tracking preferences?
     *
     * @param array $values
     * @param array $oldValues
     *
     * @return bool
     */
    private function canEnableTrackingPreference($values, $oldValues)
    {
        $binsChanged   =    (($oldValues['ENABLE_BINS']          !== $values['ENABLE_BINS'])         && ($values['ENABLE_BINS']         === 'true'));
        $othersChanged =    (($oldValues['ENABLE_SERIALNO']      !== $values['ENABLE_SERIALNO'])     && ($values['ENABLE_SERIALNO']     === 'true')) ||
                            (($oldValues['ENABLE_LOT_CATEGORY']  !== $values['ENABLE_LOT_CATEGORY']) && ($values['ENABLE_LOT_CATEGORY'] === 'true')) ||
                            (($oldValues['ENABLE_EXPIRATION']    !== $values['ENABLE_EXPIRATION'])   && ($values['ENABLE_EXPIRATION']   === 'true'));
        if (!$binsChanged && !$othersChanged) {
            return true;
        }

        // you can ENABLE bins if ONHAND is positive, but not negative.
        // but if anything else changed, then we can't allow positive OR negative ONHAND
        $onlyBinsEnabled = $binsChanged && !$othersChanged;

        // Get the ONHAND total across all warehouses; figure out the max
        $qry   = [];
        $qry[] = "select onhand.warehousekey, sum(nvl(onhand.posquantity,0) + nvl(onhand.negquantity,0)) as onhandqty
				    from icitemtotals onhand, ictotal onhandictotal
				   where onhand.cny# = :1 and onhand.cny# = onhandictotal.cny# 
                     and onhand.totalkey = onhandictotal.record# 
                     and onhandictotal.name = 'ONHAND' 
                     and itemkey = :2 
                     GROUP BY onhand.warehousekey";
        $qry[] = GetMyCompany();
        $qry[] = $values['ITEMID'];
        $res   = QueryResult($qry);
        if ($res === false) {
            return false;
        }

        $ok            = true;
        $notZero       = false;
        foreach ($res as $row) {
            // negative quantity is bad.
            // postitive quantity is bad for everything other then enabling bins (only)
            $quantity = (float)$row['ONHANDQTY'];
            if (($quantity < 0) || (($quantity > 0) && !$onlyBinsEnabled)) {
                $notZero = true;
                break;
            }
        }

        // ONHAND negative, or non-bin-enabling ONHAND positive, is cause for concern
        if ($notZero) {
            Globals::$g->gErr->addIAError('INV-1426', __FILE__ . ":" . __LINE__,
                "The tracking option cannot be changed because the item's quantity on hand is not zero. To change the option, " .
                "set the quantity on hand to zero. After the option is changed, any existing transactions that include the item " .
                "cannot be converted.", []);
            $ok = false;
        }
        return $ok;
    }


    private function validateEnableForContract(array &$values) : bool
    {
        $ok = true;
        
        if (ContractUtil::isKitsEnabled()) {
            $errors = [];
            $generalErrors = [];
            $enabledForContract = (($values['CONTRACTENABLED'] ?? '') == 'true');
            $itemType = $values['ITEMTYPE'] ?? '';
    
            if ($itemType == KIT && $enabledForContract) {
                $revPosting = $values['REVPOSTING'] ?? '';
                if ($revPosting !== COMPONENT) {
                    $errors[] = "If CONTRACTENABLED is 'true', REVPOSTING must be 'Component Level'.";
                    $errorCodes[] = 'INV-1190';
                    $placeholder[] = [];
                    $ok = false;
                }
    
                $revPrinting = $values['REVPRINTING'] ?? '';
                if ($revPrinting !== KIT) {
                    $errors[] = "If CONTRACTENABLED is 'true', REVPRINTING must be 'Kit'.";
                    $errorCodes[] = 'INV-1191';
                    $placeholder[] = [];
                    $ok = false;
                }
    
                $components = $values['COMPONENT_INFO'];
                foreach ($components as $component) {
                    $itemId = $component['COMPONENTKEY'];
                    $itemName = $itemId . '--' . $component['ITEMDESC'];

                    $qry = [
                        'selects' => ['ITEMID', 'GLGROUP', 'CNREVENUETEMPLKEY', 'CNREVENUE2TEMPLKEY', 'ITEMTYPE'],
                        'filters' => [[['ITEMID', '=', $itemId]]]
                    ];
                    $ret = $this->GetList($qry);
                    $item = $ret[0] ?? [];

                    if (!in_array($item['ITEMTYPE'], [NONINV, NONINV_SO])) {
                        $itemTypeLabel = $this->getItemTypeLabel($item['ITEMTYPE']);
                        $errors[] = sprintf(
                            'Item %s has Item type = %s. Only items with Item type = Non-Inventory or Non-Inventory (Sales only) can be added to kits.',
                            $itemName,
                            $itemTypeLabel
                        );
                        $errorCodes[] = 'INV-1192';
                        $placeholder[] = [ 'ITEM_NAME' => $itemName, 'ITEM_TYPE_LABEL' => $itemTypeLabel];
                        $ok = false;
                    }
                    if (empty($item['GLGROUP'])) {
                        $errors[] = sprintf(
                            'Specify a valid Item GL group for item %s, then try adding it to the kit again.',
                            $itemName
                        );
                        $errorCodes[] = 'INV-1193';
                        $placeholder[] = [ 'ITEM_NAME' => $itemName ];
                        $ok = false;
                    }
                    if (empty($item['CNREVENUETEMPLKEY']) && ContractUtil::isEnabledJournal1()) {
                        $errors[] = sprintf(
                            'Specify a valid Revenue template 1 for item %s, then try adding it to the kit again.',
                            $itemName
                        );
                        $errorCodes[] = 'INV-1194';
                        $placeholder[] = [ 'ITEM_NAME' => $itemName ];
                        $ok = false;
                    } else {
                        if (!$this->validateKitRevenueTemplates($item, 1, $error)) {
                            $generalErrors[] = $error;
                            $ok = false;
                        }
                    }
                    if (empty($item['CNREVENUE2TEMPLKEY']) && ContractUtil::isEnabledJournal2()) {
                        $errors[] = sprintf(
                            'Specify a valid Revenue template 2 for item %s, then try adding it to the kit again.',
                            $itemName
                        );
                        $errorCodes[] = 'INV-1195';
                        $placeholder[] = [ 'ITEM_NAME' => $itemName ];
                        $ok = false;
                    } else {
                        if (!$this->validateKitRevenueTemplates($item, 2, $error)) {
                            $generalErrors[] = $error;
                            $ok = false;
                        }
                    }
            
                    if (!$ok) {
                        foreach ($errors as $key => $error) {
                            Globals::$g->gErr->addIAError(
                                $errorCodes[$key],
                                __FILE__ . ':' . __LINE__,
                                '', []
,                                '', [],
                                $error, $placeholder[$key]
                            );
                        }
                        foreach ($generalErrors as $error) {
                            Globals::$g->gErr->addError(
                                ContractUtil::GENERIC_BL_SAVE_ERROR,
                                __FILE__ . ':' . __LINE__,
                                '',
                                '',
                                $error
                            ); //i18N::TODO (reverted to original)
                        }
                        break;
                    }
                }
            }
        }
    
        return $ok;
    }
    
    /** For MVP, Contract Kits only support Straight line, Daily rate and Predefined percentage based Revenue templates */
    protected function validateKitRevenueTemplates(array $item, int $journal, ?string &$error): bool
    {
        $allowedMethods = ContractDetailManager::$allowedRevenueTemplateMethods;
        
        $ok = true;
        
        if ($journal === 1) {
            $path = 'CNREVENUETEMPLKEY';
            $errorToken = 'IA.INVALID_KIT_COMPONENT_ITEM_REV_TEMPLATE_METHOD_ERROR';
        } else {
            $path = 'CNREVENUE2TEMPLKEY';
            $errorToken = 'IA.INVALID_KIT_COMPONENT_ITEM_REV2_TEMPLATE_METHOD_ERROR';
        }
        
        $templateKey = $item[$path] ?? null;
        if ($templateKey) {
            $res = EntityManager::GetListQuick('contractrevenuetemplate', ['METHOD'], ['RECORDNO' => $templateKey]);
            if (!empty($res)) {
                $method = $res[0]['METHOD'];
                if (!in_array($method, $allowedMethods)) {
                    $error = I18N::getSingleToken(
                        $errorToken,
                        [['name' => 'ITEMID', 'value' => $item['ITEMID']]]
                    );
                    
                    $ok = false;
                }
            }
        }
        
        return $ok;
    }
    
    public function getItemTypeLabel(string $itemTypeValue) : string
    {
        global $gItemTypeValues, $gItemTypeLabels;
        static $textMap = null;
        
        if ($textMap === null) {
            $textMap = getLocalizedTextWithThrow(I18N::tokenArrayToObjectArray($gItemTypeLabels));
        }
        
        $itemTypeLabelMap = array_combine($gItemTypeValues, $gItemTypeLabels);
        
        return GT($textMap, $itemTypeLabelMap[$itemTypeValue] ?? $itemTypeValue);
    }

    /**
     * @return bool
     */
    protected function isDNSyncEnabled()
    {
        return true;
    }

    /**
     * Validate the LANDEDCOSTINFO structure if landed cost is enabled and the structure doesn't exist
     *
     * @param array $values
     */
    private function validateValuesForLandedCost(&$values)
    {
        global $gErr;
        $ok = true;
        if ($values['ENABLELANDEDCOST'] == 'true' && $values['LANDEDCOSTINFO'] !== null && in_array($values['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT))) {
            if (is_array($values['LANDEDCOSTINFO']) && Util::countOrZero($values['LANDEDCOSTINFO']) > 3) {
                $msg = "You cannot have more than 3 Landed Cost Entries for the Item.";
                $gErr->addIAError('INV-1446', __FILE__ . ':' . __LINE__, $msg, [], 'Please provide valid Landed Cost Entries.', []);
                $ok = false;
            }
            if (is_array($values['LANDEDCOSTINFO']) && Util::countOrZero($values['LANDEDCOSTINFO']) > 1) {
                $LandedCostMethods = [];
                foreach ($values['LANDEDCOSTINFO'] as $landedCost) {
                    if (is_array($landedCost) && isset($landedCost['METHOD']) && $landedCost['METHOD'] !== '' && isset($LandedCostMethods[$landedCost['METHOD']])) {
                        $msg = "You cannot have more than 1 landed cost entries with duplicate method for same item.";
                        $gErr->addIAError('INV-1447', __FILE__ . ':' . __LINE__, $msg, [], 'Please provide valid Landed Cost Entries.', []);
                        $ok = false;
                    }
                    $LandedCostMethods[$landedCost['METHOD']] = true;
                }
            }
        }
        return $ok;
    }


    /**
     * Validate the list of fields provided and unset depending Item Type.
     * When the users enter information through UI certain fields are not allowed to populate
     * but when REST API is used these fields are set and we cannot hide them.
     *
     * @param array $values
     */
    private function validateFieldsForREST(&$values)
    {
        $fieldsToUnset = array();
        $wsInfoFieldsToUnset = array();
        $vendorInfoFieldsToUnset = array();

        if (isset($values['ITEMTYPE']) && ($values['ITEMTYPE'] == KIT || $values['ITEMTYPE'] == 'K')) {
            // unset the vendor info and warehouse info for kit items while creating the item of type KIT
            // unset the replenishment for kit items while creating the item of type KIT
            $fieldsToUnset = array(
                'VENDOR_INFO','WAREHOUSE_INFO', 'ENABLE_REPLENISHMENT', 'REPLENISHMENT_METHOD',
                'DEFAULT_REPLENISHMENT_UOM', 'REORDER_POINT', 'SAFETY_STOCK',
                 'MAX_ORDER_QTY','INV_PRECISION','SO_PRECISION','PO_PRECISION','UPC');
        } // for non-inventory Item
        else if (isset($values['ITEMTYPE']) && ($values['ITEMTYPE'] == NONINV || $values['ITEMTYPE'] == 'NI')) {
            // unset the replenishment warehouse info, and landed cost info fields for non inventory item
            $fieldsToUnset = array(
                'SHIP_WEIGHT', 'ENABLE_REPLENISHMENT',
                'REPLENISHMENT_METHOD', 'DEFAULT_REPLENISHMENT_UOM', 'REORDER_POINT',
                'SAFETY_STOCK', 'MAX_ORDER_QTY', 'AUTOPRINTLABEL', 'LANDEDCOSTINFO','CONTRACTENABLED','REVPOSTING');
            $wsInfoFieldsToUnset = array(
                'ECONOMIC_ORDER_QTY','MIN_ORDER_QTY','CYCLE','REORDER_QTY',
                'MAX_ORDER_QTY','MIN_STOCK','MAX_STOCK','REORDER_POINT',
                'REPLENISHMENT_METHOD','SAFETY_STOCK','ENABLE_REPLENISHMENT'
            );
            $vendorInfoFieldsToUnset = array(
                'FORECAST_DEMAND_IN_LEAD_TIME','MIN_ORDER_QTY','UOM','UOMKEY'
            );

        } // for non-inventory sales only
        else if (isset($values['ITEMTYPE']) && ($values['ITEMTYPE'] == NONINV_SO || $values['ITEMTYPE'] == 'NS')) {
            $fieldsToUnset = array(
                'SHIP_WEIGHT', 'INV_PRECISION',
                'WHENLASTRECEIVED', 'PURCHASE_UNIT', 'PURCHASE_UNIT_FACTOR',
                'PO_PRECISION','REVPOSTING');
        } // for non-inventory purchase only
        else if (isset($values['ITEMTYPE']) && ($values['ITEMTYPE'] == NONINV_PO || $values['ITEMTYPE'] == 'NP')) {
            $fieldsToUnset = array(
                'SHIP_WEIGHT', 'INV_PRECISION',
                'WHENLASTRECEIVED', 'SALES_UNIT', 'SALES_UNIT_FACTOR',
                'BASEPRICE', 'SO_PRECISION', 'WHENLASTSOLD','REVPOSTING');
        }
        else if (isset($values['ITEMTYPE']) && ($values['ITEMTYPE'] == INVENTORY || $values['ITEMTYPE'] == 'I')){
            $fieldsToUnset = array('REVPOSTING');
        }

        // if ENABLE_REPLENISHMENT is set to false unset replenishment fields
        if (isset($values['ENABLE_REPLENISHMENT']) && $values['ENABLE_REPLENISHMENT'] !== 'true' && $values['ENABLE_REPLENISHMENT'] !== 'T') {
            $replFieldsToUnset = array(
                'REPLENISHMENT_METHOD', 'DEFAULT_REPLENISHMENT_UOM',
                'REORDER_POINT', 'MAX_ORDER_QTY','REORDER_QTY','SAFETY_STOCK'
                );
            $fieldsToUnset = array_merge($fieldsToUnset,$replFieldsToUnset);
        }

        // if contracts are not subscribed unset contract fields- Commenting this because this unsetting these fields breaking sanity test suit of XML
        /*if (!CNSetupManager::isContractInstalled()) {
            $contractFieldsToUnset = array('HASSTARTENDDATES','TERMPERIOD', 'TOTALPERIODS','COMPUTEFORSHORTTERM');
            $fieldsToUnset = array_merge($fieldsToUnset,$contractFieldsToUnset);
        }*/

        if (Util::countOrZero($fieldsToUnset) > 0) {
            foreach ($fieldsToUnset as $fieldToUnset) {
                unset($values[$fieldToUnset]);
            }
        }
        // unset warehouse info fields if any
        if (Util::countOrZero($wsInfoFieldsToUnset) > 0) {
            if (isset($values['WAREHOUSE_INFO'])) {
                foreach ($values['WAREHOUSE_INFO'] as $key => $wInfo) {
                    foreach ($wsInfoFieldsToUnset as $fieldToUnset) {
                        unset($values['WAREHOUSE_INFO'][$key][$fieldToUnset]);
                    }
                }
            }
        }
        // unset vendor info fields if any
        if (Util::countOrZero($vendorInfoFieldsToUnset) > 0) {
            if (isset($values['VENDOR_INFO'])) {
                foreach ($values['VENDOR_INFO'] as $key => $wInfo) {
                    foreach ($vendorInfoFieldsToUnset as $fieldToUnset) {
                        unset($values['VENDOR_INFO'][$key][$fieldToUnset]);
                    }
                }
            }
        }

    }

}
