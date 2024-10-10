<?php /** @noinspection NestedPositiveIfStatementsInspection */

/**
 * =============================================================================
 *
 * @filesource ItemFormEditor.cls
 * @author     Anish Kuriya <anishk@intacct.com>
 * @copyright  2000,2009, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */
require_once "scm_util.inc";

// Item Types/Valid Values
define("INVENTORY", 'Inventory');
define("NONINV", 'Non-Inventory');
define("NONINV_PO", 'Non-Inventory (Purchase only)');
define("NONINV_SO", 'Non-Inventory (Sales only)');
define("KIT", 'Kit');
define("STOCKABLE_KIT", 'Stockable Kit');

/**
 * Class ItemFormEditor
 */
class ItemFormEditor extends FormEditor
{

    /** @var bool $isAdvancedSetup */
    var $isAdvancedSetup = false;

    /** @var bool $isUserDefinedUOM */
    var $isUserDefinedUOM = false;

    /** @var string $defaultCostMethod */
    var $defaultCostMethod = "";

    /** @var string $defaultUOMGroup */
    var $defaultUOMGroup = "";

    /** @var bool $invKitPref */
    var $invKitPref = false;

    /** @var bool $invLightAssemblyPref */
    var $invLightAssemblyPref = false;

    /** @var bool $isMultiCost */
    var $isMultiCost = false;

    /** @var bool $suppliesInventoryConfigEnabled*/
    var $suppliesInventoryConfigEnabled = false;

    /** @var bool $itemhasTerm */
    var $itemhasTerm = false;

    /** @var bool $usefulfillment */
    var $usefulfillment = false;

    /** @var bool $useVSOE */
    var $useVSOE = false;

    /** @var bool $enableSerial */
    var $enableSerial = false;

    /** @var bool $enableLot */
    var $enableLot = false;

    /** @var bool $enableBin */
    var $enableBin = false;

    /** @var bool $enableExp */
    var $enableExp = false;

    /** @var bool $enableDropShip */
    private $enableDropShip = false;

    /** @var bool $enableDropShip */
    private $enableBTO = false;
    
    /** @var bool $enableLandedCost */
    private $enableLandedCost = false;

    /** @var bool $showAutoPrintLabelfields */
    var $showAutoPrintLabelfields = false;

    /** @var bool $isFulfillmentPrefEnabled */
    var $isFulfillmentPrefEnabled = false;

    const PermissionKeys_Create = ['inv/lists/item/create','so/lists/item/create','po/lists/item/create','pa/lists/item/create'] ;
    const PermissionKeys_Edit = ['inv/lists/item/edit','so/lists/item/edit','po/lists/item/edit','pa/lists/item/edit'] ;
    const PermissionKeys_View = ['inv/lists/item/view','so/lists/item/view','po/lists/item/view','pa/lists/item/view'] ;
    /**
     * @param array $_params
     */
    public function __construct($_params = array())
    {
        parent::__construct($_params);

        $kINVid = Globals::$g->kINVid;
        $gManagerFactory = Globals::$g->gManagerFactory;

        GetModulePreferences($kINVid, $invPrefs);

        if (IsKitEnabled()) {
            $this->invKitPref = true;
        }

        if ( $invPrefs['LIGHTASSEMBLY'] == 'T' ) {
            $this->invLightAssemblyPref = true;
        }

        if ( $invPrefs['ENABLE_MULTI_UOM'] == 'T' ) {
            $this->isUserDefinedUOM = true;
        }

        if ( $invPrefs['ENABLE_MULTI_COST'] == 'T' ) {
            $this->isMultiCost = true;
        }

        $this->suppliesInventoryConfigEnabled = ItemManager::isSuppliesInventoryEnabled();

        if ( isset($invPrefs['DEFAULT_COST_METHOD']) ) {
            $this->defaultCostMethod = $invPrefs['DEFAULT_COST_METHOD'];
        }

        if ( isset($invPrefs['DEFAULT_UOMGRP']) ) {
            $this->defaultUOMGroup = $invPrefs['DEFAULT_UOMGRP'];
        }

        if ( $invPrefs['ENABLELANDEDCOST'] == 'T' ) {
            $this->enableLandedCost = true;
        }

        $soSetupMgr = $gManagerFactory->getManager('sosetup');
        $soPrefs = $soSetupMgr->get('');

        $this->itemhasTerm = ($soPrefs['ITEMSHAVESTARTENDDATE'] != 'true') ? false : true;

        $this->usefulfillment = ($soPrefs['USEFULFILLMENT'] != 'true') ? false : true;

        $this->useVSOE = SOSetupManager::isVsoeEnabled($soPrefs);

        $this->enableDropShip = ($soPrefs['DROPSHIPENABLE'] != 'true') ? false : true;
        
        $this->enableBTO = ($soPrefs['BUYTOORDERENABLE'] != 'true') ? false : true;

        $this->isAdvancedSetup = IsAdvancedConfiguration();

        $this->enableSerial = ($invPrefs['ENABLESERIAL'] == 'T') ? true : false;
        $this->enableLot = ($invPrefs['ENABLELOT'] == 'T') ? true : false;
        $this->enableBin = ($invPrefs['ENABLEBIN'] == 'T') ? true : false;
        $this->enableExp = ($invPrefs['ENABLE_EXPIRATION'] == 'T') ? true : false;
        $this->isFulfillmentPrefEnabled = ($invPrefs['ENABLEFULFILLMENT'] == 'T') ? true : false;

        $this->additionalTokens= ["IA.INVENTORY"
                                    ,"IA.NON_INVENTORY"
                                    ,"IA.NON_INVENTORY_PURCHASE_ONLY"
                                    ,"IA.NON_INVENTORY_SALES_ONLY"
                                    ,"IA.KIT"
                                    ,"IA.STOCKABLE_KIT"
                                    ,"IA.TAXABLE_IGNORED_FOR_AVALARA"
                                    ,"IA.ENABLE_AS_LANDED_COST"];
    }

    protected function getFormTokens() : array
    {
        array_push( $this->textTokens
            , "IA.SK_COST_METHOD_SHOULD_BE_FIFO"
            ,"IA.ENTER_POSITIVE_NUMBER"
            ,"IA.KIT_ID_COMPONENT_ID_CANNOT_BE_SAME"
            ,"IA.NO_ITEM_MATCH_FOUND"
            ,"IA.ITEM_IN_PARENT_HIERARCHY"
            ,"IA.ENABLE_AS_LANDED_COST"
            ,"IA.ENABLE_DISTRIBUTION_OF_LANDED_COSTS_TO_THIS_ITEM"
            ,"IA.TAX_SOL_TAX_GROUP_MAPPING"
            ,"IA.SELECT_AN_ITEM"
            ,"IA.CANNOT_DISABLE_TRACKING_FEATURE_BIN"
            ,"IA.CANNOT_DISABLE_TRACKING_FEATURE_LOT"
            ,"IA.CANNOT_DISABLE_TRACKING_FEATURE_SERIALNO"
            ,"IA.CANNOT_DISABLE_TRACKING_FEATURE_EXPIRATION"
            ,"IA.CANNOT_DISABLE_LANDING_COST_FEATURE"
            ,"IA.TAXABLE_IGNORED_FOR_AVALARA"
            ,"IA.DIFFERENT_UOM_THAN_CURRENT_UOM_GROUP"
            ,"IA.COST_METHOD_STANDARD"
            ,"IA.COST_METHOD_AVERAGE"
            ,"IA.FIFO"
            ,"IA.LIFO"
            ,"IA.TRANSACTION_TYPE"
            ,"IA.QTY_RESERVE"
            ,"IA.SUPPLIES_CANNOT_BE_A_KIT"
            );
        return parent::getFormTokens();
    }

    /**
     * Get the layout file that has to be used for this editor
     *
     * @param array $params
     *
     * @return string
     */
    protected function getMetadataKeyName(&$params)
    {
        $file = 'item_form.pxml';
        if ( $this->isAdvancedSetup ) {
            $file = 'item_advanced_form.pxml';
        }
        return $file;
    }

    /**
     * This is a hook functions for subclases to add the dynamic metadata into the current layout.
     * At the time this function is called, the data, state and view objects are not available.
     * The subclass must operate on the given params structure.
     *
     * @param array &$params the metadata
     */
    protected function buildDynamicMetadata(&$params)
    {
        parent::buildDynamicMetadata($params);

        $_mod = Request::$r->_mod;
        $action = $this->getEditorAction();

        if ( in_array($action, array('new', 'create', 'copy')) ) {
            $this->showHideFields($params, array('AVERAGE_COST', 'LAST_COST', 'WHENLASTSOLD', 'WHENLASTRECEIVED'), true);
            $whMatches = array();
            self::findElements($params, array('path' => 'WAREHOUSE_INFO'), EditorComponentFactory::TYPE_GRID, $whMatches);
            self::findElements($whMatches, array('path' => 'AVERAGE_COST'), EditorComponentFactory::TYPE_FIELD, $avgmatch);
            if ( $avgmatch[0] ) {
                $avgmatch[0]['hidden'] = true;
            }
            $matches = array();
            self::findElements($params, array('id' => 'SummarySection'), EditorComponentFactory::TYPE_SECTION, $matches);
            if ( $matches[0] ) {
                $matches[0]['columnCount'] = '2';
            }
        } else {
            $matches = array();
            self::findElements($params, array('path' => 'ITEMTYPE'), EditorComponentFactory::TYPE_FIELD, $matches);
            if ( $matches ) {
                $matches[0]['readonly'] = true;
            }
        }

        if ( $_mod == 'so' ) {
            $this->showHideFields($params, array('SODESCRIPTION'), false);
        } else if ( $_mod == 'po' ) {
            $this->showHideFields($params, array('PODESCRIPTION'), false);
        }
        if ( !$this->isUserDefinedUOM ) {
            $this->showHideFields($params, array('PURCHASE_UNIT_FACTOR', 'SALES_UNIT_FACTOR'), true);
        }

        if ( !$this->isAdvancedSetup && !$this->isUserDefinedUOM ) {
            $this->showHideFields($params, array('UOMGRP'), true);
        }

        if ( $this->isAdvancedSetup && !$this->isMultiCost ) {
            $this->showHideFields($params, array('COST_METHOD'), true);
        }

        $kARid = Globals::$g->kARid;
        GetModulePreferences($kARid, $arPrefs);
        if ( $arPrefs['ENABLEREVREC'] != 'true' ) {
            $this->showHideFields($params, array('DEFERREDREVACCTKEY'), true);
            $this->showHideFields($params, array('DEFAULTREVRECTEMPLKEY'), true);
        }

        $kINVid = Globals::$g->kINVid;
        if ( !IsInstalled($kINVid) ) {
            $this->showHideFields($params, array('AVERAGE_COST'), true);
        }

        if ( CNSetupManager::isContractInstalled() ) {
            $this->showHideFields($params, array('CNBILLINGTEMPLATENAME'), false);

            $cnsetupMgr = Globals::$g->gManagerFactory->getManager('cnsetup');
            $revrecEnabled = $cnsetupMgr->isStandardRevRecEnabled();
            if ( $revrecEnabled == false ) {
                $revrecEnabled = $cnsetupMgr->isAdvancedRevRecEnabled();
            }
            if ( $revrecEnabled ) {
                $this->showHideFields($params, array('CNREVENUETEMPLATENAME'), false);
                $this->showHideFields($params, array('CNREVENUE2TEMPLATENAME'), false);
            }

            $expEnabled = $cnsetupMgr->isExpenseEnabled();
            if ( $expEnabled ) {
                $this->showHideFields($params, array('CNEXPENSETEMPLATENAME'), false);
                $this->showHideFields($params, array('CNEXPENSE2TEMPLATENAME'), false);
            }

            $unhiddenFields = CNSetupManager::getUnhiddenFieldsForContractsInItem();
            $this->showHideFields($params, $unhiddenFields, false);

            /** @noinspection ArgumentEqualsDefaultValueInspection */
            ContractUtil::findAndSetJournalsMetadata($params, EditorComponentFactory::TYPE_FIELD, EditorComponentFactory::TYPE_FIELD);
            
            $this->showHideFields($params, ['CONTRACTENABLED'], false);
        }
        if ( $this->itemhasTerm ) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $docParMgr = $gManagerFactory->getManager('sodocumentparams');
            $docPars = $docParMgr->DoQuery('QRY_SODOCUMENTPARAMS_RENEWALS_ENABLED', array(GetMyCompany()));

            if ( count($docPars) == 0 ) {
                $this->showHideFields($params, array('RENEWALMACROID'), true);
            }
        }

        if ( $this->usefulfillment == false ) {
            $this->showHideFields($params, array('KCDLVRSTATUS', 'KCREVDEFSTATUS'), true);
        } else if ( $this->useVSOE == false ) {
            $this->showHideFields($params, array('VSOECATEGORY'), true);
        } else {
            $this->showHideFields($params, array('FULFILLMENTFOOTNOTE'), true);
        }

        $isVatRootLevel = TaxSetupManager::isTaxModuleConfigured() && IsMultiEntityCompany() && !GetContextLocation();
        $isAvaInstalled = (IsModuleIdInstalled(Globals::$g->kAVAid) &&
            GetPreferenceForProperty(Globals::$g->kAVAid, 'AVA_ENABLE') == 'T') ? true : false;
        // if avalara enabled for the module hide advanced tax group, and help text for Taxable field
        if (!$isVatRootLevel && GetTaxEngine($_mod) == TaxSolutionManager::TAXMETHOD_I_AVALARA) { //GetTaxEngine will not be called at root multi-Entity
            $this->showHideFields($params, array('TAXGROUP.NAME'), true);
            $matches = array();
            self::findElements($params, array('path' => 'TAXABLE'), EditorComponentFactory::TYPE_SECTION, $matches);
            if ( $matches[0] ) {
                $matches[0]['fullname'] = GT($this->textMap ,"IA.TAXABLE_IGNORED_FOR_AVALARA");
            }
        } else if (($_mod != 'inv' && $isVatRootLevel && !$isAvaInstalled)
            || (GetTaxEngine('so',TaxSolutionManager::TAXSOLUTION_AVALARA) != TaxSolutionManager::TAXMETHOD_I_AVALARA
                && GetTaxEngine('po') != TaxSolutionManager::TAXMETHOD_I_AVALARA)) {
            $this->showHideFields($params, array('TAXCODE'), true);
        }
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {
        $action = $this->getEditorAction();

        parent::transformBizObjectToView($obj);

        if ( $action == 'new' && $obj['ITEMTYPE'] == '' ) {
            $obj['ITEMTYPE'] = INVENTORY; //set 'Inventory' as Default Item type
        }

        if ( $this->defaultUOMGroup != "" && $obj['UOMGRP'] == "" ) {
            $obj['UOMGRP'] = $this->defaultUOMGroup;
        }

        $this->defaultCostMethod = $this->getEntityMgr()->_TransformInternalValue('COST_METHOD', $this->defaultCostMethod);

        if ( $this->defaultCostMethod != "" && $obj['COST_METHOD'] == "" ) {
            $obj['COST_METHOD'] = $this->defaultCostMethod;
        }

        //
        // sort the cost entries in descending order fo the effective_start_date
        $baseCurrency = GetBaseCurrency();
        $whInfoOk     = isset($obj['WAREHOUSE_INFO']);
        if ($whInfoOk) {
            foreach ($obj['WAREHOUSE_INFO'] as $key => $val) {
                if (isset($obj['WAREHOUSE_INFO'][$key]['STDCOSTENTRIES'])
                    && is_array($obj['WAREHOUSE_INFO'][$key]['STDCOSTENTRIES'])) {
                    usort($obj['WAREHOUSE_INFO'][$key]['STDCOSTENTRIES'], array('ItemManager', 'SortCostEntries'));
                }
                if (empty($obj['WAREHOUSE_INFO'][$key]['WHSE_CURRENCY'])) {
                    $obj['WAREHOUSE_INFO'][$key]['WHSE_CURRENCY'] = $baseCurrency;
                }
            }
        }

        if ( $action == 'copy' ) {//Unset values while duplicating
            if (isset($obj['VENDOR_INFO'])) {
                foreach ($obj['VENDOR_INFO'] as $key => $val) {
                    $val['BEST_COST'] = '0';
                    $val['LAST_COST'] = '0';
                    $obj['VENDOR_INFO'][$key] = $val;
                }
            }

            if ($whInfoOk) {
                foreach ($obj['WAREHOUSE_INFO'] as $key => $val) {
                    $val['LAST_COST'] = '';
                    $val['AVERAGE_COST'] = '';
                    $val['DATE_LASTSOLD'] = '';
                    $val['DATE_LASTRECEIVED'] = '';

                    foreach ($val['STDCOSTENTRIES'] as $sKey => $sval) {
                        unset($val['STDCOSTENTRIES'][$sKey]['RECORDNO'], $val['STDCOSTENTRIES'][$sKey]['ITEMWSEKEY']);
                    }

                    $obj['WAREHOUSE_INFO'][$key] = $val;
                }
            }
        }
        return true;
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $action = $this->getEditorAction();
        parent::mediateDataAndMetadata($obj);

        $view = $this->getView();
        $inventoryPrefs = [];
        $itemfld = array();

        $isSupplyItem    = (($obj['ISSUPPLYITEM'] ?? '') === 'true'); // action can't be new here, I would guess

        $view->findComponents(array('path' => 'ISSUPPLYITEM'), EditorComponentFactory::TYPE_FIELD, $itemfld);
        if ( isset($itemfld[0]) ) {
            if ($this->suppliesInventoryConfigEnabled) {
                /*
                 *  not sure what this is intended for, so keep it hidden until we figure it out.
                $itemfld = [];
                $view->findComponents(array('id' => 'REQUISITIONENTRIES'), EditorComponentFactory::TYPE_TAB, $itemfld);
                if (isset($itemfld[0])) {
                    $itemfld[0]->setProperty('hidden', false);
                }
                */
            } else {
                $itemfld[0]->setProperty('hidden', true);   // can't see it if the flag is off
            }
        }

        $itemfld = [];
        $view->findComponents(array('path' => 'ITEMTYPE'), EditorComponentFactory::TYPE_FIELD, $itemfld);
        $itemType = $this->initItemType($itemfld);
        $itemfld[0]->setProperty(array('type', 'validvalues'), array_values($itemType['validvalues']));
        $itemfld[0]->setProperty(array('type', '_validivalues'), array_values($itemType['_validivalues']));
        $itemfld[0]->setProperty(array('type', 'validlabels'), array_values($itemType['validlabels']));

        $kINVid = Globals::$g->kINVid;

        $inventoryIntalled = IsInstalled($kINVid);
        $autoPrintLabelEnabled = $this->IsAutoPrintLabelEnabled();
        $this->showAutoPrintLabelfields  = ($inventoryIntalled && $autoPrintLabelEnabled) ? true : false ;


        if ( $this->isAdvancedSetup ) {
            $costfield = array();
            $view->findComponents(array('path' => 'COST_METHOD'), EditorComponentFactory::TYPE_FIELD, $costfield);
            if ( $costfield[0] && !IsInstalled($kINVid) ) {
                if (!$obj['COST_METHOD'] || strlen($obj['COST_METHOD'] ) == 0)
                {
                    // only if not already set
                    $obj['COST_METHOD'] = 'Standard';
                }
                $costfield[0]->setProperty('readonly', true);
            } else if ( $costfield[0] ) {
                if ( !in_array($action, array('new', 'create', 'copy')) ) {
                    $costfield[0]->setProperty('readonly', true);
                }
            }
        }

        if ( $obj['ITEMTYPE'] != '' && $obj['ITEMTYPE'] != INVENTORY && $obj['ITEMTYPE'] != STOCKABLE_KIT ) {
            $recFld = array();
            $view->findComponents(array('path' => 'WHENLASTRECEIVED'), EditorComponentFactory::TYPE_FIELD, $recFld);
            if ( $recFld[0] ) {
                $recFld[0]->setProperty('hidden', true);
            }

        }

        $obj['SHOW_REPLENISHMENT'] = 'false';
        $obj['FLUCTUATING_FORECAST'] =  'true';
        // replenishment section on the advanced tab only applies to inventory and stockable kits
        if ( $obj['ITEMTYPE'] != '' && (($obj['ITEMTYPE'] == INVENTORY) || ($obj['ITEMTYPE'] == STOCKABLE_KIT))) {
            $inventoryPrefs = $this->getReplenishmentPref();
            $replenishment = (($inventoryPrefs['AI_REPLENISHMENTS'] == 'T') && ($inventoryPrefs['ADVANCED_INVENTORY'] == 'T'));
            if ($replenishment) {
                $recFld = array();
                $view->findComponents(array('id' => 'ReplenishmentSectionId'), EditorComponentFactory::TYPE_SECTION, $recFld);
                if ($recFld[0]) {
                    $recFld[0]->setProperty('hidden', false);
                }
                $obj['SHOW_REPLENISHMENT'] = 'true';

                // defaults:
                if (($obj['ENABLE_REPLENISHMENT'] === null) || ($obj['ENABLE_REPLENISHMENT'] === '')) {
                     $obj['ENABLE_REPLENISHMENT'] = 'F';  // default to false?
                }

                if (($obj['SAFETY_STOCK'] === null) || ($obj['SAFETY_STOCK'] === '')) {
                     $obj['SAFETY_STOCK'] = 1;  // default to 1
                }

                if (($obj['REORDER_POINT'] === null) || ($obj['REORDER_POINT'] === '')) {
                    $obj['REORDER_POINT'] = 1;  // default to 1
                }

                if (($obj['REORDER_QTY'] === null) || ($obj['REORDER_QTY'] === '')) {
                    $obj['REORDER_QTY'] = 1;  // default to 1
                }

                if (($obj['FORECAST_DEMAND_IN_LEAD_TIME'] === null) || ($obj['FORECAST_DEMAND_IN_LEAD_TIME'] === '')) {
                    $obj['FORECAST_DEMAND_IN_LEAD_TIME'] = 0;  // default to 0
                }

                if (($obj['REPLENISHMENT_METHOD'] === null) || ($obj['REPLENISHMENT_METHOD'] === '')) {
                     $obj['REPLENISHMENT_METHOD'] = $inventoryPrefs['FORECAST_METHOD'];
                }

                if ($obj['MAX_ORDER_QTY'] === '0') {
                    $obj['MAX_ORDER_QTY'] = null;
                }
            }
        }

        //Page and Section are not able to hide inside buildDynamicMetadata. So moving the code below
        if ( !$this->itemhasTerm || $obj['ITEMTYPE'] == NONINV_PO || $isSupplyItem ) {
            $termPage = array();
            $view->findComponents(array('id' => 'term'), EditorComponentFactory::TYPE_TAB, $termPage);
            if ( $termPage[0] ) {
                $termPage[0]->setProperty('hidden', true);
            }
        }

        if ( $this->usefulfillment == false || $obj['REVPOSTING'] == 'Component Level' ) {
            $vsoeSect = array();
            $view->findComponents(array('id' => 'vsoe'), EditorComponentFactory::TYPE_SECTION, $vsoeSect);
            if ( $vsoeSect[0] ) {
                $vsoeSect[0]->setProperty('hidden', true);
            }
        }

        //Based on Itemtype hide fields
        if ( !in_array($obj['ITEMTYPE'], array(STOCKABLE_KIT, KIT)) ) {
            $kitSect = array();
            $view->findComponents(array('id' => 'kitComponent'), EditorComponentFactory::TYPE_SECTION, $kitSect);
            if ( $kitSect[0] ) {
                $kitSect[0]->setProperty('hidden', true);
            }
        }

        $isPriceConversionEnabled = (SOSetupManager::isPriceConversionEnabled() || POSetupManager::isPriceConversionEnabled());
        if ($isPriceConversionEnabled) {
            $convTypeField = [];
            $view->findComponents(['path' => 'DEFAULT_CONVERSIONTYPE'], EditorComponentFactory::TYPE_FIELD, $convTypeField);

            //Based on Itemtype readonly true fields
            $isConvTypeReadonly = false;
            if (in_array($obj['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT, KIT)) || $action == 'view') {
                $isConvTypeReadonly = true;
            }

            if($convTypeField[0]) {
                //Based on price conversion configuration field in OE & PO hidden fields decide
                $convTypeField[0]->setProperty('readonly', $isConvTypeReadonly);
                $convTypeField[0]->setProperty('hidden', false);
            }
        }

        // hide StdCostEntries
        if($obj['COST_METHOD'] != 'Standard'){
            $stdCostEntriesSect = array();
            $view->findComponents(array('id' => 'StdCostEntries'), EditorComponentFactory::TYPE_SECTION, $stdCostEntriesSect);
            if ( $stdCostEntriesSect[0] ) {
                $stdCostEntriesSect[0]->setProperty('hidden', true);
            }
        }

        if($obj['COST_METHOD'] != 'Average'){
            $avgFld = array();
            $view->findComponents(array('path' => 'AVERAGE_COST'), EditorComponentFactory::TYPE_FIELD, $avgFld);
            if ( $avgFld[0] ) {
                $avgFld[0]->setProperty('hidden', true);
            }
        }

        $whSectHidden = false;
        if ( !in_array($obj['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT)) ) {
            $whSect = array();
            $view->findComponents(array('id' => 'warehouse'), EditorComponentFactory::TYPE_SECTION, $whSect);
            if ( $whSect[0] ) {
                $whSect[0]->setProperty('hidden', true);
                $whSectHidden = true;
            }
        }

        if (!$whSectHidden) {
            $inventoryPrefs = $this->getReplenishmentPref();
            $prefReplenishmentOn = (($inventoryPrefs['ADVANCED_INVENTORY'] == 'T') &&
                                    ($inventoryPrefs['AI_REPLENISHMENTS'] == 'T'));

            if ($prefReplenishmentOn) {
                foreach($obj['WAREHOUSE_INFO'] as &$whDetailRow) {
                    if ($whDetailRow['WAREHOUSEID'] == null) {
                        $whDetailRow['ENABLE_REPLENISHMENT'] = 'false';
                        $whDetailRow['SAFETY_STOCK'] = '1';
                        $whDetailRow['REORDER_POINT'] = '1';
                        $whDetailRow['REORDER_QTY'] = '1';
                        $whDetailRow['FORECAST_DEMAND_IN_LEAD_TIME'] = '0';
                        $whDetailRow['REPLENISHMENT_METHOD'] = $inventoryPrefs['FORECAST_METHOD'];
                    }
                    $whDetailRow['MAX_ORDER_QTY_REP'] = $whDetailRow['MAX_ORDER_QTY'];
                }
            }
        }

        if ( in_array($obj['ITEMTYPE'], array(NONINV_SO, KIT))) {
            $vpage = array();
            $view->findComponents(array('id' => 'vendor'), EditorComponentFactory::TYPE_TAB, $vpage);
            if ( $vpage[0] ) {
                $vpage[0]->setProperty('hidden', true);
            }
        }

        if ($this->enableLandedCost && in_array($obj['ITEMTYPE'], array(INVENTORY, NONINV, NONINV_PO, STOCKABLE_KIT))) {

            $landedCost = array();
            $view->findComponents(
                array('path' => 'ENABLELANDEDCOST'), EditorComponentFactory::TYPE_FIELD, $landedCost
            );
            if ($landedCost[0]) {
                $landedCost[0]->setProperty('hidden', false);
                if (in_array($obj['ITEMTYPE'], array(NONINV_PO, NONINV))) {
                    $landedCost[0]->setProperty('fullname', GT($this->textMap , "IA.ENABLE_AS_LANDED_COST" ));
                }
            }

            if (in_array($obj['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT))) {
                $gManagerFactory = Globals::$g->gManagerFactory;
                $uomMgr = $gManagerFactory->getManager('uom');
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

                if ( ! isset($obj['LANDEDCOSTINFO'])) {
                    $obj['LANDEDCOSTINFO'] = [];        // we WANT this to eit
                }

                foreach (ItemLandedCostManager::LANDEDCOSTMETHODS as $method) {

                    if ($method == 'Value') {
                        continue;
                    }

                    $found = false;
                    if (isset($uoms[$method])) {
                        foreach ($obj['LANDEDCOSTINFO'] as &$landedcostInfo) {
                            if ($landedcostInfo['METHOD']   == $method) {
                                $landedcostInfo['METHODUOM'] = $uoms[$method];
                                $found = true;
                            }
                        }
                        unset($landedcostInfo);

                        if (!$found) {
                            $cnt = count($obj['LANDEDCOSTINFO']);
                            $obj['LANDEDCOSTINFO'][$cnt]['METHOD']    = $method;
                            $obj['LANDEDCOSTINFO'][$cnt]['METHODUOM'] = $uoms[$method];
                        }
                    }
                }
            }

            $landedCost = array();
            $view->findComponents(
                array('path' => 'LANDEDCOSTINFO'), EditorComponentFactory::TYPE_GRID, $landedCost
            );
            if ($landedCost[0]) {
                if ($obj['ENABLELANDEDCOST'] !== 'true' || in_array($obj['ITEMTYPE'], array(NONINV, NONINV_PO))) {
                    $landedCost[0]->setProperty('hidden', true);
                } else {
                    $landedCost[0]->setProperty('hidden', false);
                }
            }

        } else {
            $landedCost = array();
            $view->findComponents(
                array('id' => 'landedcost'), EditorComponentFactory::TYPE_SECTION, $landedCost
            );
            if ($landedCost[0]) {
                $landedCost[0]->setProperty('hidden', true);
            }
        }

        $kSOid = Globals::$g->kSOid;
        $kPOid = Globals::$g->kPOid;
        $kDBBid = Globals::$g->kDBBid;
        $hideFields = array();

        if ( $obj['ITEMTYPE'] == INVENTORY ) {
            $hideFields = array('EXPENSEACCTKEY');

            if ( !$this->enableSerial ) {
                $hideFields[] = 'ENABLE_SERIALNO';
                $hideFields[] = 'SERIAL_MASKKEY';
            }
            if ( !$this->enableLot ) {
                $hideFields[] = 'ENABLE_LOT_CATEGORY';
                $hideFields[] = 'LOT_CATEGORYKEY';
            }
            if ( !$this->enableBin ) {
                $hideFields[] = 'ENABLE_BINS';
            }
            if ( !$this->enableExp ) {
                $hideFields[] = 'ENABLE_EXPIRATION';
            }
            if (!$this->enableDropShip) {
                $hideFields[] = 'DROPSHIP';
            }

            if(!$this->showAutoPrintLabelfields){
                $hideFields[] = 'AUTOPRINTLABEL';
            }
            if (!$this->enableBTO) {
                $hideFields[] = 'BUYTOORDER';
            }
        } else if ( $obj['ITEMTYPE'] == NONINV ) {
            $hideFields = array('SHIP_WEIGHT', 'INVACCTKEY', 'ENABLE_SERIALNO', 'SERIAL_MASKKEY',
                'ENABLE_LOT_CATEGORY', 'LOT_CATEGORYKEY', 'ENABLE_BINS', 'ENABLE_EXPIRATION', 'AUTOPRINTLABEL',
                'NETWEIGHT', 'WEIGHTUOM');
            if ( $this->isAdvancedSetup ) {
                $hideFields[] = 'COST_METHOD';
            }
            if (!$this->enableDropShip) {
                $hideFields[] = 'DROPSHIP';
            }
            if (!$this->enableBTO) {
                $hideFields[] = 'BUYTOORDER';
            }
        } else if ( $obj['ITEMTYPE'] == NONINV_PO ) {
            $hideFields = array('SHIP_WEIGHT', 'INVACCTKEY', 'ENABLE_SERIALNO', 'SERIAL_MASKKEY',
                'ENABLE_LOT_CATEGORY', 'LOT_CATEGORYKEY', 'ENABLE_BINS', 'ENABLE_EXPIRATION',
                'SALES_UNIT', 'BASEPRICE', 'INCOMEACCTKEY', 'COGSACCTKEY', 'DROPSHIP', 'BUYTOORDER', 'AUTOPRINTLABEL',
                'NETWEIGHT', 'WEIGHTUOM');
            if ( $this->isAdvancedSetup ) {
                $hideFields[] = 'COST_METHOD';
            } else {
                $hideFields[] = 'OFFSETOEGLACCOUNTKEY';
            }
        } else if ( $obj['ITEMTYPE'] == NONINV_SO ) {
            $hideFields = array('SHIP_WEIGHT', 'INVACCTKEY', 'ENABLE_SERIALNO', 'SERIAL_MASKKEY',
                'ENABLE_LOT_CATEGORY', 'LOT_CATEGORYKEY', 'ENABLE_BINS', 'ENABLE_EXPIRATION',
                'PURCHASE_UNIT', 'EXPENSEACCTKEY', 'COGSACCTKEY', 'DROPSHIP', 'BUYTOORDER', 'AUTOPRINTLABEL',
                'NETWEIGHT', 'WEIGHTUOM');
            if ( $this->isAdvancedSetup ) {
                $hideFields[] = 'COST_METHOD';
            } else {
                $hideFields[] = 'OFFSETPOGLACCOUNTKEY';
            }
        } else if ( $obj['ITEMTYPE'] == KIT ) {
            $hideFields = array( 'ENABLE_SERIALNO', 'SERIAL_MASKKEY',
                'ENABLE_LOT_CATEGORY', 'LOT_CATEGORYKEY', 'ENABLE_BINS', 'ENABLE_EXPIRATION', 'EXPENSEACCTKEY', 'STANDARD_COST',
                'COGSACCTKEY', 'UPC', 'DROPSHIP', 'BUYTOORDER', 'AUTOPRINTLABEL');
            if ( $this->isAdvancedSetup ) {
                $hideFields[] = 'COST_METHOD';
                $hideFields[] = 'INCOMEACCTKEY';
                $hideFields[] = 'INVACCTKEY';
            } else {
                $hideFields[] = 'OFFSETPOGLACCOUNTKEY';
            }
        } else if ( $obj['ITEMTYPE'] == STOCKABLE_KIT ) {
            if (StkitDocumentManager::isStockableKitTrackingEnabled()) {
                $hideFields = array( 'EXPENSEACCTKEY', 'STANDARD_COST', 'UPC');
                if ( !$this->enableSerial ) {
                    $hideFields[] = 'ENABLE_SERIALNO';
                    $hideFields[] = 'SERIAL_MASKKEY';
                }
                if ( !$this->enableLot ) {
                    $hideFields[] = 'ENABLE_LOT_CATEGORY';
                    $hideFields[] = 'LOT_CATEGORYKEY';
                }
                if ( !$this->enableExp ) {
                    $hideFields[] = 'ENABLE_EXPIRATION';
                }
            } else {
                $hideFields = array( 'ENABLE_SERIALNO', 'SERIAL_MASKKEY', 'ENABLE_LOT_CATEGORY', 'LOT_CATEGORYKEY',
                                     'ENABLE_EXPIRATION', 'EXPENSEACCTKEY', 'STANDARD_COST', 'UPC');
            }
            if ( !$this->enableBin ) {
                $hideFields[] = 'ENABLE_BINS';
            }
            if ( $this->isAdvancedSetup ) {
                $hideFields[] = 'INCOMEACCTKEY';
                $hideFields[] = 'INVACCTKEY';
                $hideFields[] = 'COGSACCTKEY';
            }
            if (!$this->enableDropShip) {
                $hideFields[] = 'DROPSHIP';
            }

            if(!$this->showAutoPrintLabelfields){
                $hideFields[] = 'AUTOPRINTLABEL';
            }
            if (!$this->enableBTO) {
                $hideFields[] = 'BUYTOORDER';
            }
        }

        if ( $this->isAdvancedSetup ) {
            if ( !IsInstalled($kINVid) || in_array($obj['ITEMTYPE'], array(NONINV_SO, NONINV_PO, NONINV, KIT))
            ) {
                $hideFields[] = 'INV_PRECISION';
            }
            if ( !IsInstalled($kSOid) || in_array($obj['ITEMTYPE'], array(NONINV_PO, KIT)) || $isSupplyItem
            ) {
                $hideFields[] = 'SO_PRECISION';
            }
            if ( !IsInstalled($kPOid) || in_array($obj['ITEMTYPE'], array(NONINV_SO, KIT))
            ) {
                $hideFields[] = 'PO_PRECISION';
            }
        }

        if ( in_array($action, array('new', 'create', 'copy'))  || ( !in_array($obj['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT)) ) ) {
            $totalFields = array('IONHOLD', 'IONHAND', 'IONORDER', 'IINTRANSIT', 'IAVAILABLE', 'IRESERVED', 'IALLOCATED', 'IUNCOMMITTED',
                                 'WONHOLD', 'WONHAND', 'WONORDER', 'WINTRANSIT', 'WAVAILABLE', 'WRESERVED', 'WALLOCATED', 'WUNCOMMITTED');
            $hideFields = array_merge($hideFields, $totalFields);
        } else if (in_array($action, array('edit', 'view')) && in_array($obj['ITEMTYPE'], array(INVENTORY, STOCKABLE_KIT))) {
            //When editing an inventory or stockable kit, we hide reserved, allocated, and uncommited header and column if
            //there aren't ALLOCATED and RESERVED inventory totals
            $totalManager = Globals::$g->gManagerFactory->getManager('invtotal');
            $filter = array(
                'selects' => array('NAME'),
                'filters' => array(
                    array(
                        array('NAME', 'IN', ['ALLOCATED', 'RESERVED']),
                    )
                ),
            );
            $rows = $totalManager->GetList($filter);
            $totals = [];
            foreach($rows as $row){
                $totals[$row['NAME']] = true;
            }
            if (!isset($totals['ALLOCATED'])) {
                $hideFields = array_merge($hideFields, ['IALLOCATED', 'WALLOCATED']);
            }
            if (!isset($totals['RESERVED'])) {
                $hideFields = array_merge($hideFields, ['IRESERVED', 'WRESERVED']);
            }
            if (!isset($totals['ALLOCATED']) || !isset($totals['RESERVED'])) {
                $hideFields = array_merge($hideFields, ['IUNCOMMITTED', 'WUNCOMMITTED']);
            }
        }

        if (IsMCMESubscribed()) {
            $stdFld = array();
            $view->findComponents(array('path' => 'STANDARD_COST'), EditorComponentFactory::TYPE_FIELD, $stdFld);
            if ( $stdFld[0] ) {
                $stdFld[0]->setProperty('hidden', true);
            }
        }
        //hide the intransit field if the flag is not set
        /** @noinspection PhpUndefinedVariableInspection */
        if ( $inventoryPrefs['ENABLEINTRANSITTRANSFER'] !== 'T') {
            $hideFields[] = 'IINTRANSIT';
            $hideFields[] = 'WINTRANSIT';
        }

        foreach ( $hideFields as $fld ) {
            $view->findAndSetProperty(array('path' => $fld), array('hidden' => true));
        }

        /*
         * $obj is updated with standard defaults for VSOE delivery and deferal Status
         * Default values for VSOE fieldthe Object are applied here if there are no values set.
         */
        $pathDefaults = array(
            'VSOEDLVRSTATUS' => 'Delivered',
            'VSOEREVDEFSTATUS' => ITEM_DEFERRAL
        );

        foreach ($pathDefaults as $path => $default) {
            if ($this->usefulfillment && empty($obj[$path])) {
                $obj[$path] = $default;
            }
        }

        // Hide MRR checkbox if Digital board book is not subscribed
        if (!IsInstalled($kDBBid) && !IsInstalled(Globals::$g->kSAASMTid)) {
            $view->findAndSetProperty(array('path' => 'MRR'), array('hidden' => true));
        }

        $action = $this->getEditorAction();
        if ($action == 'edit') {
            $matches = array();
            $view->findComponents(array('path' => 'UOMGRP'), EditorComponentFactory::TYPE_FIELD, $matches);
            if ($matches) {
                $trans = QueryResult(
                    array(
                        "select record# from docentrycost where cny# = :1 and itemkey = :2 and rownum = 1 ",
                        GetMyCompany(),
                        $obj['ITEMID']
                    )
                );
                if ($trans[0]['RECORD#']) {
                    $matches[0]->setProperty('readonly', true);
                }
            }
        }

        global $gSalesForecastMethodValues;
         $isforecast  = $obj['REPLENISHMENT_METHOD'] == $gSalesForecastMethodValues[2];

        // add forcast button init
        $matches1 = [];
        $matches2 = [];
        $view->findComponents(['id' => 'addforecastitem'], EditorComponentFactory::TYPE_BUTTONS, $matches1);
        $view->findComponents(['id' => 'addforecastwarehouse'], EditorComponentFactory::TYPE_BUTTONS, $matches2);
        $matches = array_merge($matches1, $matches2);
        if ($matches)
        {
            $opedit = GetOperationId('inv/lists/replenishforecast/view');
            $opcreate = GetOperationId('inv/lists/replenishforecast/create');
            $sess = Session::getKey();

            if ($action == 'new')
            {
                // no forecast if creating item
                $forecast = false;
                $create = true;
            }
            else
            {
                $create = false;

                // see if there is already a forecast for this item
                $forecast = QueryResult(
                    [
                        "select record# from replenishforecasthdr where cny# = :1 and itemid = :2 ",
                        GetMyCompany(),
                        $obj['ITEMID'],
                    ]
                );
            }

            if (empty ($forecast))
            {
                // no existing forecast
                $op = "&.op=$opcreate";
                $record = '';
                $action = "&.itemaction=create";
                $do = '';
                $buttonText = 'Add forecast';
            }
            else
            {
                // forecast exists
                $op = "&.op=$opedit";
                $record = "&.r=" . urlencode($forecast[0]['RECORD#']);
                $action = "&.itemaction=edit";
                $do = '&.do=view';
                $buttonText = 'View forecast';
            }
            $itemid = "&.item=" . urlencode($obj['ITEMID']);
            // add javascript call here

            foreach ($matches as $match)
            {
                $url = "editor.phtml?.sess=$sess&.popup=1$op&.mod=inv$record$itemid$action$do";
                $clickdata =
                    [
                        'url' => $url,
                    ];
                /** @noinspection PhpUndefinedMethodInspection */
                $match->setProperty('clickdata', $clickdata);
                /** @noinspection PhpUndefinedMethodInspection */
                $match->setProperty('hidden', !$isforecast);
                $match->params['button'][0]['name'] = $buttonText;
                /** @noinspection PhpUndefinedMethodInspection */
                $match->setProperty('create', $create);
            }
        }

        if (TaxSetupManager::isMultiTaxJurisdictionConfigured()) {
            $itgPage = array();
            $view->findComponents(array('id' => 'sys_itg'), EditorComponentFactory::TYPE_TAB, $itgPage);
            if ($itgPage[0]) {
                $itgPage[0]->setProperty('hidden', false);
            }

            $itemTaxGroupField = array();
            $view->findComponents(array('path' => 'TAXGROUP.NAME'), EditorComponentFactory::TYPE_FIELD, $itemTaxGroupField);
            if ($itemTaxGroupField[0]) {
                $itemTaxGroupField[0]->setProperty('hidden', true);
            }

            if (GetContextLocation() != '' && $this->state != $this->kShowViewState) {
                $mgr = Globals::$g->gManagerFactory->getManager('taxsolution');
                $taxSoln = $mgr->getTaxsolutionDetailsForLocn(GetContextLocation());
                $restrict = array(
                    'value' => $taxSoln[0]['RECORD#'],
                    'pickField' => 'TAXSOLUTIONKEY',
                    'operand' => '='
                );
                $taxGroup = array();
                $view->findComponents(array('path' => 'TAXGROUP.NAME'), EditorComponentFactory::TYPE_FIELD, $taxGroup);

                $taxGroup = $taxGroup[1];

                if (!empty($taxGroup) && !empty($taxSoln[0]['RECORD#'])) {
                    $type = $taxGroup->getProperty('type');
                    $type['restrict'][] = $restrict;
                    $taxGroup->setProperty('type', $type);
                }
                $matches = array();
                $view->findComponents(array('path' => 'ALLOWMULTIPLETAXGRPS'), EditorComponentFactory::TYPE_FIELD, $matches);
                $matches[0]->setProperty('hidden', true);

                $matches = array();
                $view->findComponents(array('path' => 'TAXGROUP.TAXSOLUTION.SOLUTIONID'), EditorComponentFactory::TYPE_FIELD, $matches);
                $matches[0]->setProperty('hidden', true);

                $grid = array();
                $view->findComponents(array('path' => 'MULTIPLEITEMTAXGROUPS'), EditorComponentFactory::TYPE_GRID, $grid);
                $grid = $grid[0];
                $grid->setProperty('hidden', true);

            }
        }
        if ( $this->kShowNewState != $this->state ) {
            if ( $obj['ITEMID'] != '' ) {
                $itemTitle = $obj['ITEMID'] . ' -- ' . ( $obj['NAME'] ? : '' );
                if(isl_strlen($itemTitle) > 80) {
                    $itemTitle = isl_substr($itemTitle, 0, 76) . ' ...';
                }
                $this->setTitleEncoded($itemTitle);
            }
        }

        //for Fulfillment
        $this->mediateDataAndMetadata_FulfillmentFields($obj);

        $this->mediateDataAndMetadata_CrossReferences($obj);

        // This will show the report links of an inevntory item only in view mode
        $this->mediateDataAndMetadata_inventoryReportLink($obj['ITEMTYPE']);

        // This will show the bin items inevntory details only in view mode
        $this->mediateDataAndMetadata_binInventory($obj);


        $this->mediateDataAndMetadata_totals($obj);

        if (IsInstalled(Globals::$g->kINVid)
            && FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_INV_ITEMVIEW_FEATURE')) {
            // This will show the transactions in view/edit mode
            $this->mediateDataAndMetadata_inquiryTabTransactions($obj);
        }

        return true;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    private function mediateDataAndMetadata_FulfillmentFields(&$obj)
    {
        $itemMgr = Globals::$g->gManagerFactory->getManager('item');
        $view = $this->getView();

        if ( ( in_array($obj['ITEMTYPE'], array(NONINV,NONINV_SO)) ) && $this->isFulfillmentPrefEnabled ) {
            $enableFulfillment = array();
            $view->findComponents(
                array('id' => 'Enablefulfillment'), EditorComponentFactory::TYPE_SECTION, $enableFulfillment
            );
            if ($enableFulfillment[0]) {
                $enableFulfillment[0]->setProperty('hidden', false);
            }
        }

        $fulfillmentEnabled = $itemMgr->isFulfillmentEnabled($obj);
        if ( $fulfillmentEnabled ) {
            $whSect = [];
            $view->findComponents([ 'id' => 'warehouse' ], EditorComponentFactory::TYPE_SECTION, $whSect);
            if ( $whSect[0] ) {
                $whSect[0]->setProperty('hidden', false);
            }

            $warehseInfoViewArr = array();
            $view->findComponents(array('path' => 'WAREHOUSE_INFO'), EditorComponentFactory::TYPE_GRID, $warehseInfoViewArr);
            $warehseInfoView = $warehseInfoViewArr[0];

            $warehseInfoView->findAndSetProperty(array('path' => 'CYCLE'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
            $warehseInfoView->findAndSetProperty(array('path' => 'ECONOMIC_ORDER_QTY'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
            $warehseInfoView->findAndSetProperty(array('path' => 'MIN_ORDER_QTY'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
            $warehseInfoView->findAndSetProperty(array('path' => 'MAX_ORDER_QTY'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
            $warehseInfoView->findAndSetProperty(array('path' => 'MIN_STOCK'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
            $warehseInfoView->findAndSetProperty(array('path' => 'MAX_STOCK'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
            $warehseInfoView->findAndSetProperty(array('path' => 'REORDER_POINT'), array('disabled' => true), EditorComponentFactory::TYPE_FIELD);
        }
        return true;
    }

    /**
     * @param string $itemType
     * @return bool
     */
    private function mediateDataAndMetadata_inventoryReportLink($itemType)
    {
        $state = $this->getState();
        if (isset($state) && $state == $this->kShowViewState
            && in_array($itemType, [INVENTORY, STOCKABLE_KIT])) {
            $fieldsToHide = ['ITEMACTIVITY_RPTURL', 'INVENTORYSTATUS_RPTURL', 'PHYSICALINVENTORY_RPTURL'];

            $view = $this->getView();
            // Iterate each fields to hide it
            foreach ($fieldsToHide as $fieldToHide) {
                $linkField = [];
                $view->findComponents(['id' => $fieldToHide],
                    EditorComponentFactory::TYPE_LINK, $linkField);
                if (isset($linkField[0])) {
                    $linkField[0]->setProperty('hidden', false);
                }
            }
        }
        return true;
    }

    /**
     * Override to grand permission to an item based on OE\PO permissions when inventory is not installed
     * @return int[]
     */
    protected function getEntityPermissions()
    {
        $perm =parent::getEntityPermissions();

        // do additional checking from 'so', 'po' , only when inventory is not installed
        if((Request::$r->_mod == 'inv') && !IsInstalled(Globals::$g->kINVid)){
            if(IsInstalled(Globals::$g->kSOid)){
                $soParentOpID = Globals::$g->gSecurity->GetListerOperationID($this->getEntity(), 'so');
                $perm = array_merge($perm,GetPagePermissions($soParentOpID));
            }
            if(IsInstalled(Globals::$g->kPOid)){
                $poParentOpID = Globals::$g->gSecurity->GetListerOperationID($this->getEntity(), 'po');
                $perm = array_merge($perm,GetPagePermissions($poParentOpID));
            }
        }

        return $perm;
    }

    /**
     * @param array $obj
     */
    private function mediateDataAndMetadata_binInventory(&$obj)
    {
        $state = $this->getState();
        // TODO: Enabled for bath INVENTORY AND STOCKABLE_KIT
        if (isset($state)
            && ($state == $this->kShowViewState || $state == $this->kShowEditState)
            && in_array($obj['ITEMTYPE'], [INVENTORY, STOCKABLE_KIT])
            && ($obj['ENABLE_SERIALNO'] == 'true' || $obj['ENABLE_LOT_CATEGORY'] == 'true'
                || $obj['ENABLE_BINS'] == 'true' || $obj['ENABLE_EXPIRATION'] == 'true')) {
            $view = $this->getView();
            $binPage = [];
            $view->findComponents(['id' => 'itembinsinventory'], EditorComponentFactory::TYPE_TAB, $binPage);
            if (isset($binPage[0])) {
                $binPage[0]->setProperty('hidden', false);

                $itemMgr = Globals::$g->gManagerFactory->getManager('item');
                $obj['ITEMBINSINVENTORY'] = $itemMgr->getItemBinsInventory($obj['ITEMID']);
            }
        }
    }

    /**
     * @param array $obj
     */
    private function mediateDataAndMetadata_inquiryTabTransactions(&$obj)
    {
        $state = $this->getState();
        if (isset($state)
            && ($state == $this->kShowViewState || $state == $this->kShowEditState)
            && in_array($obj['ITEMTYPE'], [INVENTORY, STOCKABLE_KIT])) {
            $hideInquiryTransTab = true;
            $view = $this->getView();
            $transPage = [];
            $view->findComponents(['id' => 'ITEMTRANSACTIONS'], EditorComponentFactory::TYPE_TAB, $transPage);
            if (isset($transPage[0])) {
                $transPage[0]->setProperty('hidden', false);
                $hideInquiryTransTab = false;
            }


            if (!$hideInquiryTransTab) {
                // Display the intransit tab only if Configuration Enable in-transit transfers
                $inTransitPref = (GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLEINTRANSITTRANSFER') == 'T');
                if ($inTransitPref != true) {
                    $inTransitTab = [];
                    $view->findComponents(['id' => 'INTRANSITORDERENTRIES'], EditorComponentFactory::TYPE_TAB, $inTransitTab);
                    if (isset($inTransitTab[0])) {
                        $inTransitTab[0]->setProperty('hidden', true);
                    }
                }

                $this->hideFieldsForInquiryTabTransactions();
            }
        }
    }

    /**
     * @return bool
     */
    private function hideFieldsForInquiryTabTransactions()
    {
        if ($this->enableBTO && $this->enableDropShip) {
            // If both buy to order and drop ship is enabled no need to hide any fields
            return true;
        }

        $hideFields = [];
        if (!$this->enableBTO) {
            // hide the buy to order field 'TRANSBUYTOORDER'
            $hideFields[] = 'TRANSBUYTOORDER';
        }

        if (!$this->enableDropShip) {
            // if drop ship is not enabled hide this field 'TRANSDROPSHIP'
            $hideFields[] = 'TRANSDROPSHIP';
        }

        if (!$this->enableBTO && !$this->enableDropShip) {
            // If both are disabled hide these fields 'TRANSOEDOCID', 'TRANSPODOCID'
            $hideFields[] = 'TRANSOEDOCID';
            $hideFields[] = 'TRANSPODOCID';
        }

        if (count($hideFields) > 0) {
            $view = $this->getView();
            foreach ($hideFields as $field) {
                $fields = [];
                $view->findComponents(['path' => $field], EditorComponentFactory::TYPE_FIELD, $fields);
                foreach ($fields as $oneField) {
                    $oneField->setProperty('hidden', true);
                }
            }
        }
        return true;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    private function mediateDataAndMetadata_totals(&$obj)
    {
        $itemMgr = Globals::$g->gManagerFactory->getManager('item');
        $itemMgr->calculateInvTotals($obj);
        return true;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata_CrossReferences(/** @noinspection PhpUnusedParameterInspection */ &$obj)
    {
        $view = $this->getView();
        $crossRefGrid = array();
        $view->findComponents(array('path' => 'ITEMCROSSREFERENCES'), EditorComponentFactory::TYPE_GRID, $crossRefGrid);

        if ($crossRefGrid[0]) {
            $refTypeFld = array();
            $crossRefGrid[0]->findComponents(array('path' => 'REFTYPE'), EditorComponentFactory::TYPE_FIELD, $refTypeFld);

            if ($refTypeFld[0]) {
                $defaultrefType = Request::$r->_mod == 'po' ? 'Vendor' : 'Customer';
                $refTypeFld[0]->setProperty('default', $defaultrefType);
            }
        }

        return true;
    }

    /**
     * @return array
     */
    protected function getEditorGlobals()
    {
        $vars = parent::getEditorGlobals();

        $kARid = Globals::$g->kARid;
        $kINVid = Globals::$g->kINVid;
        $kSOid = Globals::$g->kSOid;
        $kPOid = Globals::$g->kPOid;

        GetModulePreferences($kARid, $arPrefs);
        $action = $this->getEditorAction();

        $vars['enablerevrec'] = $arPrefs['ENABLEREVREC'] == 'true' ? true : false;
        $vars['isadvsetup'] = $this->isAdvancedSetup;
        $vars['enabledropship'] = $this->enableDropShip;
        $vars['enableBTO'] = $this->enableBTO;
        $vars['enablelandedcost'] = $this->enableLandedCost;
        $vars['ismcmesubscribed'] = IsMCMESubscribed();
        $vars['ismulticost'] = $this->isMultiCost;
        $vars['suppliesInventoryConfigEnabled'] = $this->suppliesInventoryConfigEnabled;
        $vars['itemhasTerm'] = $this->itemhasTerm;
        $vars['invInstalled'] = IsInstalled($kINVid);
        $vars['soInstalled'] = IsInstalled($kSOid);
        $vars['poInstalled'] = IsInstalled($kPOid);
        $vars['soAvatax'] = GetTaxEngine('so', TaxSolutionManager::TAXSOLUTION_AVALARA); //'soAvatax' doesn't seem to be used
        $vars['mod'] = Request::$r->_mod;
        $vars['usefulfillment'] = $this->usefulfillment;

        $vars['enableserial'] = $this->enableSerial;
        $vars['enablelot'] = $this->enableLot;
        $vars['enablebin'] = $this->enableBin;
        $vars['enableexpir'] = $this->enableExp;

        //    $vars['userUOM'] = $this->isUserDefinedUOM;
        $vars['defaultCost'] = $this->defaultCostMethod;

        $vars['action'] = $action;

        // Note: in classic mode we fetched every bin, aisle, and row and sent them to the ui regardless
        //      of whether the item used that warehouse or even had bin tracking ON.
        //      Now, we interactively get the bins for a specific warehouse on demand (ajax)
        if (BinManager::areAdvanedBinsOn()) {
            $vars['wAisles'] = [];
            $vars['wRows']   = [];
            $vars['wBins']   = [];
            $vars['binsAdvanced'] = 'T';
        } else {
            $track_data = $this->CollectAutoFillData();
            $vars['wAisles'] = $track_data[0];
            $vars['wRows'] = $track_data[1];
            $vars['wBins'] = $track_data[2];
            $vars['binsAdvanced'] = 'F';
        }
        $vars['showAutoPrintLabelfields'] = $this->showAutoPrintLabelfields;

        // This Ops ids will be used to genarate report link in Inventory section.
        $vars['itemactivityop'] = GetOperationId('inv/reports/itemactivity');
        $vars['itemstatusop'] = GetOperationId('inv/reports/invstatus');
        $vars['itemsphysicalinventoryop'] = GetOperationId('inv/reports/physicalinventory');

        $crossRefItems = [];
        $obj = &Request::$r->GetCurrentObject();
        if ($obj['ITEMCROSSREFERENCES']) {
            $crossRefItems[] = $obj['ITEMID'];
            foreach ($obj['ITEMCROSSREFERENCES'] as $entry) {
                $itemid = explode('--', $entry['ALTERNATEITEMID'])[0];
                $crossRefItems[] = $itemid;
            }

            if (!empty($crossRefItems)) {
                $itemMgr = Globals::$g->gManagerFactory->getManager('item');
                $itemsUOMCache = $itemMgr->GetUOMInfoCache($crossRefItems, true);

                foreach ($itemsUOMCache as $iKey => $itemUOMs) {
                    unset($itemsUOMCache[$iKey]);
                    foreach ($itemUOMs as $uom) {
                        $itemsUOMCache[$iKey][] = $uom['UNIT'];
                    }
                }
                $vars['uomCache'] = $itemsUOMCache;
            }
        }
        if (StkitDocumentManager::isStockableKitTrackingEnabled()) {
            $vars['ENABLESTOCKABLEKITTRACKING'] =  'T';
        } else {
            $vars['ENABLESTOCKABLEKITTRACKING'] =  'F';
        }

        $vars['isFulfillmentPrefEnabled'] = $this->isFulfillmentPrefEnabled;

        // set the gridpaths and columns paths that
        // needs fulfillment enabled
        $vars['gridColumnsWithFulfillmentReq'] = [ 'ITEMBINSINVENTORY' => ['QOA','QOUN','QOR'],
                                                    'OPENSALESORDERENTRIES' => ['SOTRANSALLOCATED','SOTRANSRESERVE']];

        $vars['view_sodocument']    = GetOperationId('so/lists/sodocument/view');
        $vars['view_podocument']    = GetOperationId('po/lists/podocument/view');
        $vars['view_invdocument']   = GetOperationId('inv/lists/invdocument/view');
        $vars['view_customer']      = GetOperationId('so/lists/customer/view');
        $vars['view_vendor']        = GetOperationId('ap/lists/vendor/view');
        $vars['view_warehouse']     = GetOperationId('inv/lists/warehouse');
        $vars['view_contact']       = GetOperationId('co/lists/contact/view');

        //Init supplyiteminuse flag so we can enable/disable the "Item is supply inventory" checkbox on form
        if ($action === 'edit') {
            $vars['supplyiteminuse'] = ItemManager::isItemInUseOnTxn($obj['ITEMID']);
        } else {
            $vars['supplyiteminuse'] = false;
        }

        return $vars;
    }

    /**
     * @return array
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles[] = "../resources/js/itemeditor_new.js";
        return $jsfiles;
    }

    /**
     * @return array
     */
    protected function getCssFileNames()
    {
        $cssfiles[] = "../resources/css/item.css";
        return $cssfiles;
    }

    /**
     * @param array $_params
     */
    protected function SetHelpID(&$_params)
    {
        $_mod = Request::$r->_mod;
        if ( $_mod == 'pa' ) {
            $_params['view']['helpfile'] = 'Adding_Items';
            $_params['helpfile'] = 'Adding_Items'; //Not sure whether we need to change here also
        }
    }

    /**
     * @param array     $params
     * @param array     $fields
     * @param string    $show
     */
    function showHideFields(&$params, $fields, $show)
    {
        foreach ( $fields as $path ) {
            $matches = array();
            self::findElements($params, array('path' => $path), EditorComponentFactory::TYPE_FIELD, $matches);
            if ( $matches[0] ) {
                $matches[0]['hidden'] = $show;
            }
        }
    }


    /**
     *  Mark one or more fields as read-only
     *
     * @param array     $fields
     * @param string    $ro
     */
    private function setFieldsReadonly($fields, $ro)
    {
        $view    = $this->getView();
        $itemfld = array();

        foreach ( $fields as $path ) {
            $view->findComponents(array('path' => $path), EditorComponentFactory::TYPE_FIELD, $itemfld);
            if (isset($itemfld[0])) {
                $itemfld[0]->setProperty('readonly', $ro);
            }
        }
    }


    /**
     * @param array $itemfld
     *
     * @return string|array
     */
    function initItemType($itemfld)
    {
        $_mod = Request::$r->_mod;

        $itemType = $itemfld[0]->getProperty('type');

        if ( $_mod == 'so' || $_mod == 'pa' ) {
            $this->unsetItemValidVals($itemType, NONINV_PO, 'NP');
        } else if ( $_mod == 'po' ) {
            $this->unsetItemValidVals($itemType, NONINV_SO, 'NS');
        }

        if ( !$this->invKitPref ) {
            $this->unsetItemValidVals($itemType, KIT, 'K');
        }

        if ( !$this->invLightAssemblyPref ) {
            $this->unsetItemValidVals($itemType, STOCKABLE_KIT, 'SK');
        }

        return $itemType;
    }

    /**
     * @param string|array      $itemType
     * @param string            $val
     * @param string            $iVal
     */
    function unsetItemValidVals(&$itemType, $val, $iVal)
    {
        $key = array_search($val, $itemType['validvalues']);
        if ( $key !== false ) {
            unset($itemType['validvalues'][$key]);
            unset($itemType['validlabels'][$key]);
        }
        $key = array_search($iVal, $itemType['_validivalues']);
        if ( $key !== false ) {
            unset($itemType['_validivalues'][$key]);
        }
    }

    /**
     * @return array
     */
    private function CollectAutoFillData()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $advanced = BinManager::areAdvanedBinsOn();

        $aislesdensearr = [];
        $rowdensearr = [];

        if ( ! $advanced) {
            $aisleMgr = $gManagerFactory->getManager('warehouseaisle');
            $rowMgr   = $gManagerFactory->getManager('warehouserow');
            $binMgr   = $gManagerFactory->getManager('warehousebin');
            $myqry = array(
                'QUERY' => "select aisleid,whsekey from whseaisle where cny#=?",
                'ARGTYPES' => array('integer'),
            );
            $aislesdensearr = $aisleMgr->_QM->DoCustomQuery($myqry, array());

            $myqry = array(
                'QUERY' => "select rowkey,whsekey from whserow where cny#=?",
                'ARGTYPES' => array('integer'),
            );
            $rowdensearr = $rowMgr->_QM->DoCustomQuery($myqry, array());

            $myqry = array(
                'QUERY' => "select binid,whsekey from whsebin where cny#=?",
                'ARGTYPES' => array('integer'),
            );
            $bindensearr = $binMgr->_QM->DoCustomQuery($myqry, array());
        } else {
            $binMgr   = $gManagerFactory->getManager('bin');
            $myqry = array(
                'QUERY' => "SELECT icbin.binid, icwarehouse.location_no as whsekey 
                            FROM icbin, icwarehouse 
                            WHERE icbin.cny#=? and icbin.cny#=icwarehouse.cny# and icbin.warehousekey = icwarehouse.record# 
                            ORDER BY whsekey, binid",
                'ARGTYPES' => array('integer'),
            );
            $bindensearr = $binMgr->_QM->DoCustomQuery($myqry, array());
        }
        return(array($aislesdensearr, $rowdensearr, $bindensearr));
    }

    /**
     * @return string|null
     */
    function getEditorAction()
    {
        $action = Request::$r->{$this->kAction};
        if ( !$action ) {
            $kVerb = Globals::$g->kVerb;
            $action = $this->kDefaultVerbActions[Request::$r->$kVerb];
        }

        //new => (Add, Error go back), edit => (Edit, Error go back), view => (View), copy => (Duplicate), create => (Save and New)
        return $action;
    }

    /**
     * @return bool
     */
    protected function CanPrint()
    {
        return false;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForCopyNew(&$obj)
    {
        /*
         * Fields that require validation to stop user from providing values while
         * creating an item
         */
        $fldsToClear = array(
            'RECORDNO',
            'AVERAGE_COST',
            'WHENLASTRECEIVED',
            'WHENLASTSOLD',
        );

        foreach ($fldsToClear as $field) {
            unset($obj[$field]);
        }

        $whseFldsToClear = array(
            'AVERAGE_COST', 'LAST_COST', 'DATE_LASTRECEIVED', 'DATE_LASTSOLD'
        );
        if (!empty($obj['WAREHOUSE_INFO'])) {
            foreach($whseFldsToClear as $whseFld) {
                foreach( $obj['WAREHOUSE_INFO'] as $whseKey => $whseRow) {
                    unset($obj['WAREHOUSE_INFO'][$whseKey][$whseFld]);
                    foreach( $obj['WAREHOUSE_INFO'][$whseKey]['ITEMWAREHOUSEVENDORENTRIES'] as $vendorKey => $vendRow) {
                        unset($obj['WAREHOUSE_INFO'][$whseKey]['ITEMWAREHOUSEVENDORENTRIES'][$vendorKey]['RECORDNO'], $obj['WAREHOUSE_INFO'][$whseKey]['ITEMWAREHOUSEVENDORENTRIES'][$vendorKey]['BEST_COST'], $obj['WAREHOUSE_INFO'][$whseKey]['ITEMWAREHOUSEVENDORENTRIES'][$vendorKey]['LAST_COST']);
                    }
                }
            }
        }

        $vendFldsToClear = array(
            'BEST_COST', 'LAST_COST'
        );
        if (!empty($obj['VENDOR_INFO'])) {
            foreach($vendFldsToClear as $vendFld) {
                foreach( $obj['VENDOR_INFO'] as $key => $vendRow) {
                    unset($obj['VENDOR_INFO'][$key][$vendFld]);
                }
            }
        }
        if (!empty($obj['MULTIPLEITEMTAXGROUPS'])) {
            foreach ($obj['MULTIPLEITEMTAXGROUPS'] as $key => $multiItemTaxGrp) {
                unset($obj['MULTIPLEITEMTAXGROUPS'][$key]['ITEMID']);
                unset($obj['MULTIPLEITEMTAXGROUPS'][$key]['RECORDNO']);
            }
        }

        // for user convenience remove all item cross reference.
        // less likely they will be same for the duplicated/copied item.
        unset($obj['ITEMCROSSREFERENCES']);

        return parent::prepareObjectForCopyNew($obj);
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function transformViewObjectToBiz(&$obj)
    {
        // Get the entries
        $component_info = &$obj['COMPONENT_INFO'];

        foreach ( $component_info as $key => &$component ) {
            // Reset the line_no to handle drag and drop
            $component['LINE_NO'] = $key + 1;
        }

        $itemcrossrefinfo = &$obj['ITEMCROSSREFERENCES'];
        foreach ($itemcrossrefinfo as $key => $itemCrossRef) {
            if ($itemCrossRef['_isNewLine']) {
                $dataStr = '';
                $dataStr .= $itemCrossRef['ALTERNATEITEMID'];
                $dataStr .= $itemCrossRef['VENDORID'];
                $dataStr .= $itemCrossRef['CUSTOMERID'];
                $dataStr .= $itemCrossRef['ITEMALIASID'];
                $dataStr .= $itemCrossRef['ITEMALIASDESC'];
                $dataStr .= $itemCrossRef['UNIT'];

                if (strlen($dataStr) == 0) {
                    unset($obj['ITEMCROSSREFERENCES'][$key]);
                }
            }
        }

        //
        // unset the STDCOSTENTRIES if any if the item type is not invnetory or cost method is not standard
        $itemMgr = Globals::$g->gManagerFactory->getManager('item');
        $fulfillmentEnabled = $itemMgr->isFulfillmentEnabled($obj);
        $stdCostInfoRequired = ($obj['ITEMTYPE'] == 'Inventory' && $obj['COST_METHOD'] == 'Standard') || $fulfillmentEnabled;

        if(!$stdCostInfoRequired){
            foreach ( $obj['WAREHOUSE_INFO'] as $key => $val ) {
                unset($obj['WAREHOUSE_INFO'][$key]['STDCOSTENTRIES']);
            }
        }

        return true;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForCreate(&$obj)
    {
        $this->prepareReplenishmentDataForSaving($obj);
        return parent::prepareObjectForSave($obj);
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function prepareObjectForSave(&$obj)
    {
        $this->prepareReplenishmentDataForSaving($obj);
        return parent::prepareObjectForSave($obj);
    }

    /**
     * @param array $obj
     */
    function prepareReplenishmentDataForSaving(&$obj)
    {
        if (isset($obj['WAREHOUSE_INFO'])) {
            foreach ($obj['WAREHOUSE_INFO'] as &$whDetailRow) {
                //If the inv config or item replenishment is off, we need to turn off the warehouse replenishment
                if (!($obj['SHOW_REPLENISHMENT'] === 'true' && ($obj['ENABLE_REPLENISHMENT'] === 'true' || $obj['ENABLE_REPLENISHMENT'] === 'T'))) {
                    $whDetailRow['ENABLE_REPLENISHMENT'] = 'false';
                }
                if ($whDetailRow['ENABLE_REPLENISHMENT'] === 'true') {
                    $whDetailRow['MAX_ORDER_QTY'] = $whDetailRow['MAX_ORDER_QTY_REP'];
                }
            }
        }
    }

    /**
     * @return array the inv module pref
     */
    function getReplenishmentPref()
    {
        global $kINVid;
        $inventoryPrefs = array();
        GetModulePreferences($kINVid, $inventoryPrefs);

        global $gSalesForecastMethodValues, $gSalesForecastMethodIValues;
        $key = array_search($inventoryPrefs['FORECAST_METHOD'], $gSalesForecastMethodIValues);
        if ($key !== false) {
            $inventoryPrefs['FORECAST_METHOD'] = $gSalesForecastMethodValues[$key];
        }

        return $inventoryPrefs;
    }

    /**
     * @return bool
     */
    protected function IsAutoPrintLabelEnabled()
    {
        global $kINVid;
        $autoPrintLabelEnabled= (GetPreferenceForProperty($kINVid, 'ENABLEAUTOPRINTLABEL') == 'T') ? true : false;
        return $autoPrintLabelEnabled;
    }

    /**
     * @param EditorGrid    $grid
     * @param EntityManager $entityMgr
     * @param array         $_obj
     *
     */
    protected function innerCleanupLineItems($grid, $entityMgr, &$_obj)
    {
        $path = $grid->getProperty('path');
        if ($path === 'MULTIPLEITEMTAXGROUPS') {
            if ($_obj['ALLOWMULTIPLETAXGRPS'] !== 'true') {
                $_obj[$path] = array();//Empty the MULTIPLEITEMTAXGROUPS if ALLOWMULTIPLETAXGRPS is not true
            }
            foreach ($_obj[$path] as $key => &$itemTaxGroupLine) {
                if (empty($itemTaxGroupLine['TAXGROUP']['NAME'])) {
                    unset($_obj[$path][$key]);
                }
            }
        } else {
            parent::innerCleanupLineItems($grid, $entityMgr, $_obj);
        }
    }

    /**
     * @param array $_params
     * Override to check permission
     * @return bool
     */
    protected function ProcessViewAction(&$_params)
    {
        if(!hasPermissionForms(self::PermissionKeys_View)) {
            return false;
        }

        $itemId = isl_htmlspecialchars_decode(Request::$r->{Globals::$g->kId});
        Request::$r->{Globals::$g->kId} = $itemId;
        return parent::ProcessViewAction($_params);
    }

    /**
     * @param $_params
     * Override to check permission
     * @return bool
     */
    protected function ProcessEditAction(&$_params)
    {
        if(!hasPermissionForms(self::PermissionKeys_Edit)) {
            return false;
        }
        return parent::ProcessEditAction($_params);
    }

    /**
     * @param $_params
     * Override to check permission
     * @return bool
     */
    protected function ProcessEditNewAction(&$_params)
    {
        if(!hasPermissionForms(self::PermissionKeys_Create)) {
            return false;
        }
        return parent::ProcessEditNewAction($_params);
    }
}


