<?php /** @noinspection ArgumentEqualsDefaultValueInspection */

/**
 * INVSetupManager.cls
 *
 * @author    Alexandre Sonier <asonier@intacct.com>
 * @copyright 2000 Intacct Corporation, All Rights Reserved
 */

/**
 * Manager for INV Subscription & Setup
 */

/**
 * Class INVSetupManager
 */
class INVSetupManager extends DocumentSetupManager
{
    const   SYS_SUPPLY_ITEM = 'SYS-Supply-Item';


    /**
     * @var [] $translatedText Translated tokens
     */
    private $translatedText = [];

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        $this->modKey = Globals::$g->kINVid;

        $this->mod = 'inv';

        $this->spi = 'I';

        $this->modStr = 'I'; // DocumentSetupManager var

        I18N::addToken('IA.LANDED_COST_TOP_LEVEL');
        I18N::addToken('IA.RUN_UPDATES_NIGHTLY');
        I18N::addToken('IA.SYS_SUPPLIES_ITEM_NAME');
        $this->translatedText = I18N::getText();

        parent::__construct($params);
    }

    /**
     * Override parent's method
     * Collect setup preferences
     *
     * @param array &$preferences preferences
     *
     * @return bool
     */
    protected function collectSetupPreferences(&$preferences)
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $ok = $ok && parent::collectSetupPreferences($preferences);

        // Create tds for build and stockable kits
        if ($preferences['LIGHTASSEMBLY'] == 'true') {
            $ok = $ok && $this->CreateStockablekitsTDS();
        }

        if (!isset($preferences['DEFAULT_COST_METHOD']) || $preferences['DEFAULT_COST_METHOD'] == '') {
            $preferences['DEFAULT_COST_METHOD'] = 'Standard';
        }

        if (!IsAdvancedConfiguration()) {
            $offsetAccts = array(
                'INVACCTKEY' => $preferences['INV_GLACCOUNT'],
                'OFF_GLACCOUNT' => $preferences['OFF_GLACCOUNT']
            );

            $invDocparMgr = $gManagerFactory->getManager('invdocumentparams');
            $ok = $ok && $invDocparMgr->SetDocParPostingOffsetAccounts($offsetAccts);
        }

        $ok = $ok && $this->defaultJournals($preferences, 'I');

        if (!$ok) {
            $gErr->addIAError('INV-0151', __FILE__ . ':' . __LINE__,
                "Could not set default Journals.",
                []
            );
            return false;
        }

        $ok = $ok && $this->setLandedCost($preferences);
        // too early to do this here!
        // $ok = $ok && $this->setFulfillment($preferences);

        if (($preferences['ENABLESUPPLIESINVENTORY'] === 'true') &&
            FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_SUPPLIESINV_FEATURE')) {
            $ok = $ok && $this->setupSupplies($preferences);
        }


        return $ok;
    }


    /**
     * Other module preferences setter
     *
     * @param array &$values values
     *
     * @return bool
     */
    protected function setOtherModulePreferences(&$values)
    {
        $ok = parent::setOtherModulePreferences($values);

        // do this AFTER parent::set()
        $ok = $ok && $this->setFulfillment($values);

        if (InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            $ok = $ok && $this->setupFulfillmentTotals();   // do this even if fulfillment is not enabled
        }

        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    private function setLandedCost(&$values)
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ok = true;

        $currentLandedCostMap = array();
        $currentLandedCost = $this->getLandedCost();
        foreach ($currentLandedCost as $lCost) {
            $currentLandedCostMap[$lCost['LANDEDCOSTDOCPAR']] = $lCost;
        }

        if ($values['ENABLELANDEDCOST'] == 'true') {
            $ok = $ok && $this->changeOrderLandedCostsCheck($values);

            if ($values['LANDEDCOSTACCOUNT'] != '') {
                [$acctNo] = explode('--', $values['LANDEDCOSTACCOUNT']);

                $acctMgr = $gManagerFactory->getManager('glaccount');
                $acctsMap = $acctMgr->GetBankAccountsMap(array($acctNo));

                // If the GL account is associated to a bank account let's throw an error
                if ($acctsMap[$acctNo]['ISCASHACCT'] == 'T') {
                    $ok = false;
                    $gErr->addIAError(
                        'INV-0556',
                        __FILE__ . ':' . __LINE__,
                        "The GL Account no. '$acctNo' is associated to the Bank Account '"
                        . $acctsMap[$acctNo]['CASHACCTID'] . "' and cannot be used as Landed costs account.",
                        ['ACCT_NO'=>$acctNo,'ACCTS_MAP_ACCT_NO_CASHACCTID'=>$acctsMap[$acctNo]['CASHACCTID']],
                        '',[],
                        "Please select another GL account.",[]);
                }
                if (!isset($acctsMap[$acctNo]['RECORD#'])) {
                    $msg = "Invalid Landed costs account " . $acctNo . " selected";
                    $corr = "Pick a valid account.";
                    $gErr->addIAError('INV-0557', __FILE__ . ':' . __LINE__, $msg,
                     ['ACCT_NO'=>$acctNo],
                     '',[],
                     $corr,[]);
                    $ok = false;
                }
            } else {
                $msg = "Enter a valid account for the Landed costs account. Then, try again.";
                $gErr->addIAError('INV-0558', __FILE__ . ':' . __LINE__,
                    $msg,
                    [],
                    '',
                    []
                );
                $ok = false;
            }

            $ok = $ok && $this->createLandedCostTD();

            //If the LC-estimate is selected, we need to check for the LC-estimate account
            if ($values['LANDEDCOSTRADIO'] == 'lc-estimatesactuals') {
                if ($values['LANDEDCOSTACCOUNTESTIMATE'] != '') {
                    [$acctNo] = explode('--', $values['LANDEDCOSTACCOUNTESTIMATE']);

                    $acctMgr = $gManagerFactory->getManager('glaccount');
                    $acctsMap = $acctMgr->GetBankAccountsMap(array($acctNo));

                    // If the GL account is associated to a bank account let's throw an error
                    if ($acctsMap[$acctNo]['ISCASHACCT'] == 'T') {
                        $ok = false;
                        $gErr->addIAError(
                            'INV-0559',
                            __FILE__ . ':' . __LINE__,
                            "The GL Account no. '$acctNo' is associated to the Bank Account '"
                            . $acctsMap[$acctNo]['CASHACCTID'] . "' and cannot be used as Estimated
                            landed costs account.",
                            ['ACCT_NO'=>$acctNo,'ACCTS_MAP_ACCT_NO_CASHACCTID'=>$acctsMap[$acctNo]['CASHACCTID']],
                            '',[],
                            "Please select another GL account.",[]);
                    }
                    if (!isset($acctsMap[$acctNo]['RECORD#'])) {
                        $msg = "Invalid Estimated landed costs account " . $acctNo . " selected";
                        $corr = "Pick a valid account.";
                        $gErr->addIAError('INV-0560', __FILE__ . ':' . __LINE__, $msg,
                         ['ACCT_NO'=>$acctNo],'',[], $corr,[]);
                        $ok = false;
                    }

                } else {
                    $msg = "Enter a valid account for the Estimated landed costs account. Then, try again.";
                    $gErr->addIAError('INV-0561', __FILE__ . ':' . __LINE__,
                        $msg,
                        [],
                        '',
                        []
                    );
                    $ok = false;
                }

                $ok = $ok && $this->createLandedCostEstTD();
                $ok = $ok && $this->createLandedCostEstReversalTD();
            } else {
                $values['LANDEDCOSTACCOUNTESTIMATE'] = ''; //Empty the estimated LC account if user saves config with actuals LC
            }

            $landedCost = array();
            $newLandedCostDocs = array();
            $curLocation = '';
            if (IsMultiEntityCompany()) {
                $curLocation = GetContextLocation();
                $curLocation = GetContextLocationNoFromLocationKey($curLocation);
            }
            $docParMgr = $gManagerFactory->getManager('documentparams');

            $actualCostsToggled = ($values['LANDEDCOSTRADIO'] == "lc-actuals");
            foreach ($values['LANDEDCOSTGRID'] as $dsVal) {

                //Validation to make sure a TD is entered
                if (!$dsVal['LANDEDCOSTDOCPAR']) {
                    $msg = "Transaction definitions are required";
                    $corr = "Pick a valid transaction definitions.";
                    $gErr->addIAError('INV-0562', __FILE__ . ':' . __LINE__,
                        $msg,
                        [],
                        '',
                        [],
                        $corr,
                        []
                    );
                    $ok = false;
                    continue;
                }

                //Validation to make sure a checkbox for either actual or estimated costs is checked
                if ($dsVal['LANDEDCOSTACTUALTDENABLED'] != "true") {
                    if ($actualCostsToggled) {
                        $msg = "Under enable landed costs, select the 'Use to enter actual landed costs' checkbox for each transaction definition in the table.";
                        $corr = "";
                        $gErr->addIAError('INV-0563', __FILE__ . ':' . __LINE__,
                            $msg,
                            [],
                            '',
                            [],
                            $corr,
                            []
                        );
                        $ok = false;
                        continue;
                    } else {
                        /** @noinspection NestedPositiveIfStatementsInspection */
                        if ($dsVal['LANDEDCOSTESTIMATETDENABLED'] != "true") {
                            $msg = "Under enable landed costs, select the appropriate checkbox for each transaction definition in the table, either 'Use to enter actual landed costs' or 'Use to enter estimated landed costs'.";
                            $corr = "";
                            $gErr->addIAError('INV-0564', __FILE__ . ':' . __LINE__,
                                $msg,
                                [],
                                '',
                                [],
                                $corr,
                                []
                            );
                            $ok = false;
                            continue;
                        }
                    }
                }

                $currentLandedCost = $currentLandedCostMap[$dsVal['LANDEDCOSTDOCPAR']];
                if (!empty($curLocation)) {
                    /** @noinspection NestedPositiveIfStatementsInspection */
                    if (!empty($currentLandedCost) && $currentLandedCost['LANDEDCOSTLOC'] != $curLocation) {
                        $newLandedCostDocs[$dsVal['LANDEDCOSTDOCPAR']] = $dsVal;
                        continue;
                    }
                }

                $filter = array(
                    'selects' => array('RECORDNO'),
                    'filters' => array(
                        array(
                            array('DOCID', '=', $dsVal['LANDEDCOSTDOCPAR']),
                            array('SALE_PUR_TRANS', '=', 'Purchase'),
                            array('UPDATES_GL', '!=', 'N')
                        )
                    ),
                );

                $res = $docParMgr->GetList($filter);

                if (!isset($res[0]['RECORDNO'])) {
                    $msg = "Invalid incoming transaction definition '" . $dsVal['LANDEDCOSTDOCPAR'] . "' selected";
                    $corr = "Pick a valid sales transaction definition.";
                    $gErr->addIAError('INV-0565', __FILE__ . ':' . __LINE__, $msg,
                     ['DS_VAL_LANDEDCOSTDOCPAR'=>$dsVal['LANDEDCOSTDOCPAR']],
                     '',[],
                     $corr,[]);
                    $ok = false;
                }

                if (isset($newLandedCostDocs[$dsVal['LANDEDCOSTDOCPAR']])) {
                    $msg = "Each incoming transaction definition in the mapping table needs to be unique, and " .
                        "transaction definition '" . $dsVal['LANDEDCOSTDOCPAR'] . "' is already used. Choose a " .
                        "different incoming transaction definition.";
                    $gErr->addIAError('INV-0566', __FILE__ . ':' . __LINE__,
                     $msg,['DS_VAL_LANDEDCOSTDOCPAR'=>$dsVal['LANDEDCOSTDOCPAR']],
                     '',[],
                     '',[]);
                    $ok = false;
                }
                $newLandedCostDocs[$dsVal['LANDEDCOSTDOCPAR']] = $dsVal;

                //Create a macro for this TD entry if config changed
                $actualCurVal = ($currentLandedCost && $currentLandedCost['LANDEDCOSTACTUALTDENABLED'] == "true");
                $actualNewVal = ($dsVal['LANDEDCOSTACTUALTDENABLED'] == "true");
                $newMacroName = $currentLandedCost['MACRONAME'];
                if ($actualCostsToggled) {
                    $landedcostRadioBtnChanged = ($values['LANDEDCOSTRADIO'] != $values['LANDEDCOSTRADIOPREV']);
                    if ($landedcostRadioBtnChanged || $actualNewVal != $actualCurVal) {
                        $newMacroName = SCMMacroManager::LANDEDCOST;
                        $ok = $ok && SCMMacroManager::configureMacro(
                                                    $currentLandedCost['MACRONAME'],
                                                    $dsVal['LANDEDCOSTDOCPAR'],
                                                    array(InvDocumentManager::LANDEDCOSTDOCTYPE),
                                                    true,
                                                    $newMacroName);
                    }
                } else {
                    $estimateCurVal = ($currentLandedCost && $currentLandedCost['LANDEDCOSTESTIMATETDENABLED'] == "true");
                    $estimateNewVal = ($dsVal['LANDEDCOSTESTIMATETDENABLED'] == "true");
                    $landedcostRadioBtnChanged = ($values['LANDEDCOSTRADIO'] != $values['LANDEDCOSTRADIOPREV']);
                    if ($landedcostRadioBtnChanged || $actualNewVal != $actualCurVal || $estimateNewVal != $estimateCurVal) {
                        if ($actualNewVal && $estimateNewVal) {
                            $newMacroName = SCMMacroManager::LCACTANDEST;
                            $targetDocParArray = array(InvDocumentManager::LANDEDCOSTDOCTYPE, InvDocumentManager::LANDEDCOSTESTREVDOCTYPE);
                        } else if ($estimateNewVal) {
                            $newMacroName = SCMMacroManager::LCEST;
                            $targetDocParArray = array(InvDocumentManager::LANDEDCOSTESTDOCTYPE);
                        } else {
                            $newMacroName = SCMMacroManager::LCACTANDESTREV;
                            $targetDocParArray = array(InvDocumentManager::LANDEDCOSTDOCTYPE, InvDocumentManager::LANDEDCOSTESTREVDOCTYPE);
                        }
                        $ok = $ok && SCMMacroManager::configureMacro(
                                                        $currentLandedCost['MACRONAME'],
                                                        $dsVal['LANDEDCOSTDOCPAR'],
                                                        $targetDocParArray,
                                                        true,
                                                        $newMacroName);
                    }
                }

                $landedCost[] = array(
                    'MACRONAME' => $newMacroName,
                    'LANDEDCOSTDOCPAR' => $dsVal['LANDEDCOSTDOCPAR'],
                    'LANDEDCOSTLOC' => $curLocation,
                    'LANDEDCOSTACTUALTDENABLED' => $dsVal['LANDEDCOSTACTUALTDENABLED'],
                    'LANDEDCOSTESTIMATETDENABLED' => $dsVal['LANDEDCOSTESTIMATETDENABLED'],
                );
            }

            // delete macros if the row is deleted from the setup
            if ($ok) {
                foreach ($currentLandedCostMap as $curLC) {
                    $docparRemoved = !isset($newLandedCostDocs[$curLC['LANDEDCOSTDOCPAR']]);
                    if ($docparRemoved) {
                        $ok = $ok && $this->deleteLandedCost($curLC);
                    }
                }
            }

            if ($ok) {
                $values['LANDEDCOST'] = Util_DataRecordFormatter::phpToJson($landedCost);
            }
        } else if (!empty($currentLandedCostMap)) {
            //If we get here, it means the user has turned off the landed cost radio btn
            $ok = $ok && $this->canDisabledLandedCostPreference($values);
            //Reset to defaults when turning off the landed cost
            $values['LANDEDCOST'] = '';
            $values['LANDEDCOSTACCOUNT'] = '';
            $values['LANDEDCOSTACCOUNTESTIMATE'] = '';

            if ($ok) {
                //Delete macros since we disable landed costs
                foreach ($currentLandedCostMap as $lCost) {
                    $ok = $ok && $this->deleteLandedCost($lCost);
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     */
    protected function transformPreferences(&$values)
    {
        parent::transformPreferences($values);

        if ($values['ENABLELANDEDCOST'] == 'true') {
            $values['LANDEDCOSTGRID'] = $this->getLandedCost();
        }


        // COSTING_ON_A_SCHEDULE is saved in the preferences, but the Admin might manually delete
        //      the schedule over in the MIV tool.  So, don't trust the saved preference.
        $hlthrunMgr = Globals::$g->gManagerFactory->getManager('invhlthrun');
        $values['COSTING_ON_A_SCHEDULE']     = $hlthrunMgr->doesMIVQuickScheduleExist() ? 'true' : 'false';
        $values['COSTING_WAS_ON_A_SCHEDULE'] = $values['COSTING_ON_A_SCHEDULE'];
    }

    /**
     * @return array|bool|string
     */
    protected function getLandedCost()
    {
        $currentLandedCost = array();
        if (IsMultiEntityCompany()) {
            if (GetContextLocation()) {
                $currentLandedCost = $this->getEntityPreference('LANDEDCOST', Globals::$g->kINVid, true);
                $currentLandedCost = Util_DataRecordFormatter::jsonToPhp($currentLandedCost);

                $currentEntityLandedCost = $this->getEntityPreference('LANDEDCOST', Globals::$g->kINVid);
                if (!empty($currentEntityLandedCost)) {
                    $currentEntityLandedCost = Util_DataRecordFormatter::jsonToPhp($currentEntityLandedCost);
                    $currentLandedCost = INTACCTarray_merge($currentLandedCost, $currentEntityLandedCost);
                }
            } else {
                $stmt = array();
                $stmt[]
                    = "SELECT value FROM modulepref a, location b WHERE a.cny# = :1 and a.modulekey = :2 
                  and a.property = 'LANDEDCOST' and a.cny#=b.cny# (+)
                  and a.locationkey = b.record#(+) ORDER BY b.location_no";
                $stmt[] = GetMyCompany();
                $stmt[] = Globals::$g->kINVid;
                $result = QueryResult($stmt);

                foreach ($result as $res) {
                    $currentLandedCost = INTACCTarray_merge(
                        $currentLandedCost,
                        Util_DataRecordFormatter::jsonToPhp($res['VALUE'])
                    );
                }
            }
            foreach ($currentLandedCost as &$lCost) {
                if (!$lCost['LANDEDCOSTLOC']) {
                    $lCost['LANDEDCOSTLOC'] = GetContextLocationNoFromLocationKey();
                }
                $lCost['LANDEDCOSTLOCLOCALIZED'] = GT($this->translatedText, 'IA.LANDED_COST_TOP_LEVEL');
                if (!$lCost['MACRONAME']) {
                    $lCost['MACRONAME'] = SCMMacroManager::LANDEDCOST; //First version of LC released is LANDEDCOST so we init with it
                }
            }
        } else {
            $currentLandedCost = $this->GetPreference('LANDEDCOST', Globals::$g->kINVid);
            $currentLandedCost = Util_DataRecordFormatter::jsonToPhp($currentLandedCost);
        }

        return $currentLandedCost;

    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function setFulfillment(&$values)
    {
        $ok = true;

        // $currentFulfillment = $this->getFulfillment();

        if ($values['ENABLEFULFILLMENT'] == 'true') {

            $flow = 'OSI';//just a placeholder to say we are supporting Order -> Shipper - > Invoice for now

            //create the transaction definitions
            $fulfillmentGrid = [];
            $ok = $ok && $this->createFullfillmentDocpars($flow, $fulfillmentGrid);
        } else { // if (!empty( $currentFulfillment )) {
            //If we get here, it means the user has turned off fulfillment
            //Reset to default when turning off fulfillment
            $values['FULFILLMENT'] = '';
        }

        return $ok;
    }

    /**
     * @return array|bool|string
     */
    protected function getFulfillment()
    {
        $currentFulfillment = $this->GetPreference('FULFILLMENT', Globals::$g->kINVid);
        $currentFulfillment = Util_DataRecordFormatter::jsonToPhp($currentFulfillment);
        return $currentFulfillment;

    }

    /**
     * setupFulfillmentTotals
     *
     * @return bool
     */
    public function setupFulfillmentTotals()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $totalManager = $gManagerFactory->getManager('invtotal');
        $fulfilmentTotals = array('ALLOCATED', 'RESERVED');
        $filter = array(
            'selects' => array('NAME'),
            'filters' => array(
                array(
                    array('NAME', 'IN', $fulfilmentTotals),
                )
            ),
        );

        $invTotalRes = $totalManager->GetList($filter);
        $existingTotals= [];
        foreach($invTotalRes as $totalsFound){
            $existingTotals[] = $totalsFound['NAME'];
        }
        //if either of the totals are not present, then create it
        foreach($fulfilmentTotals as $total){
            if (!in_array($total, $existingTotals )) {
                $invTotalValues = array(
                    'NAME' => $total,
                    'STATUS' => 'active',
                    'UPDATETYPE' => 'Continuous',
                );
                $ok = $ok && $totalManager->add($invTotalValues);
            }
        }

        return $ok;
    }

    /**
     * @param array $landedCost
     *
     * @return bool
     */
    protected function deleteLandedCost($landedCost)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        if (IsMultiEntityCompany()) {
            $ctx = GetContextLocation();
            $lNo = GetContextLocationNoFromLocationKey($ctx);
            if (isset($landedCost['LANDEDCOSTLOC']) && $landedCost['LANDEDCOSTLOC'] != $lNo) {
                $msg = "Cannot delete '" . $landedCost['LANDEDCOSTDOCPAR'] . "' as it was set up at '"
                    . $landedCost['LANDEDCOSTLOC'] . "'";
                $corr = "Delete this from '" . $landedCost['LANDEDCOSTLOC'] . "'";
                $gErr->addIAError('INV-0567', __FILE__ . ':' . __LINE__, $msg,
                 ['LANDED_COST_LANDEDCOSTDOCPAR'=>$landedCost['LANDEDCOSTDOCPAR'],
                 'LANDED_COST_LANDEDCOSTLOC'=>$landedCost['LANDEDCOSTLOC']],
                 '',[], $corr,
                 ['LANDED_COST_LANDEDCOSTLOC'=>$landedCost['LANDEDCOSTLOC']]);
                $ok = false;
            }
        }

        $ok = $ok && SCMMacroManager::deleteMacro($landedCost['MACRONAME'], $landedCost['LANDEDCOSTDOCPAR']);

        return $ok;
    }

    /**
     * @param array $docParInfo
     * @param array $preferences
     * @param string $docID
     *
     * @return bool
     */
    protected function PrepPRInvGLJournal($docParInfo, &$preferences, $docID)
    {
        return true;
    }

    /**
     * @param string $account
     * @param string $name
     * @param string $errorNumber
     * @param bool $required
     * @param bool $statistical
     *
     * @return bool
     */
    protected function validateGLAccount(&$account, $name, $errorNumber, $required, $statistical = false)
    {
        $ok = true;
        // Validate Offset GL account
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $glacctmgr = $gManagerFactory->getManager(($statistical ? 'stataccount' : 'glaccount'));
        if (isset($account) && $account != '') {
            [$glacct_no] = explode('--', $account);
            $params = array(
                'filters' => array(
                    array(
                        array('ACCOUNTNO', '=', $glacct_no),
                        array('CNY#', '=', GetMyCompany())
                    )
                ),
                'selects' => array('ACCT_NO', 'TITLE'),
            );
            $glaccount = $glacctmgr->GetList($params);
            if (empty($glaccount[0])) {
                $gErr->addIAError(
                    'INV-0657', __FILE__ . ':' . __LINE__,
                    "Please enter a valid $name GL account",['NAME'=>$name]
                );
                // i18N::TODO - (Code Change Review)
                $ok = false;
            } else {
                $account = $glacct_no; //."--".$glaccount[0]['TITLE'];
            }
        } else if ($required) {

            $gErr->addIAError(
                'INV-0658', __FILE__ . ':' . __LINE__,
                "A valid $name GL account is required",['NAME'=>$name],
            );
            // i18N::TODO - (Code Change Review)
            $ok = false;
        }
        return $ok;
    }


    /**
     * Validate inputs
     *
     * @param array &$preferences values
     *
     * @return bool
     */
    protected function validateInputs(&$preferences)
    {
        $gErr = Globals::$g->gErr;

        $ok = true;
        $ok = $ok && parent::validateInputs($preferences);

        // Validate Offset GL account
        $ok = $ok && $this->validateGLAccount($preferences['OFF_GLACCOUNT'], "Offset", 'BL03000007', false);

        // Validate Inventory GL account
        $ok = $ok && $this->validateGLAccount($preferences['INV_GLACCOUNT'], "Inventory", 'BL03000007', false);

        // Validate/normalize AI fields
        $preferences['ADVANCED_INVENTORY'] = 'true';
        if ($preferences['ADVANCED_INVENTORY'] == 'false') {
            $preferences['AI_REPLENISHMENTS'] = 'false';
            $preferences['AI_CYCLE_COUNTS'] = 'false';
        }

        // Validate Demand Forecast GL account (for replenishment)
            $aiIsOn = ($preferences['AI_REPLENISHMENTS'] == 'true');

            if ($ok && $aiIsOn && (!isset($preferences['DEFAULT_PURCHASE_TRANSACTION']) || ($preferences['DEFAULT_PURCHASE_TRANSACTION'] == ''))) {
                $gErr->addIAError('INV-0152', __FILE__ . ":" . __LINE__,
                    "Default purchase transaction must be set",
                    []
                );
                $ok = false;
            }


        if ($preferences['ENABLEWAREHOUSETRANSFER'] == 'true') {
            $ok = $ok && $this->setupWarehouseTransfer();
            if ($preferences['ENABLEINTRANSITTRANSFER'] == 'true') {
                if ( IsModuleIdInstalled(Globals::$g->kAFRid) ) {
                    $gErr->addIAError('INV-1428', __FILE__ . ":" . __LINE__,
                        "Cannot enable 'In Transit Transfer' if 'Global Transaction Security' is subscribed",
                        []
                    );
                    $ok = false;
                }
                $ok = $ok && $this->setupInTransitWarehouseTransfer();
            }
        } else {
            $preferences['WAREHOUSESEQUENCE'] = '';
            $preferences['ENABLEINTRANSITTRANSFER'] = '';
            $preferences['DEFAULTINTRANSITTRANSFER'] = '';
            $preferences['INCLUDEINTRANSIT'] = '';
        }

        if (!ValidateInputDate($preferences['INVSTARTDATE'])) { // blank or empty is ok
            $gErr->addIAError(
                'INV-0153', __FILE__ . '.' . __LINE__,
                "The Inventory Start Date is invalid.",
                []
            );
        }

        // we'll do more later, but if supplies inventory is on, then turn on MIV nightly runs
        if ($preferences['ENABLESUPPLIESINVENTORY'] == 'true') {
            $preferences['COSTING_ON_A_SCHEDULE'] = 'true';
        }
        $hlthrunMgr = Globals::$g->gManagerFactory->getManager('invhlthrun');
        if ($preferences['COSTING_ON_A_SCHEDULE'] == 'true') {
            if ($preferences['COSTING_WAS_ON_A_SCHEDULE'] == 'false') {
                // in case the bookeeping is messed up here, delete any prior schedule:
                $ok = $hlthrunMgr->deleteMIVQuickSchedule();

                // create a schedule record
                $schedulerValues = [];
                $schedulerValues['ANALYZE_OR_UPDATE'] = InvHlthRunManager::QuickUpdate;
                $schedulerValues['SCHEDULE_SCHEDULETHIS']    = 'true';
                $schedulerValues['REPEAT_PERIOD']            = 'DAY';
                $schedulerValues['REPEAT_INTERVAL']          = 1;
                $schedulerValues['REPEAT_END_TYPE']          = 'NEVER';
                $schedulerValues['NOTES']                    = GT($this->translatedText, 'IA.RUN_UPDATES_NIGHTLY');
                $schedulerValues['SUMMARY_CHILDREN_ONLY']    = true; // only the summary records from the result are needed
                $schedulerValues['FROMITEMID']               = '';   // filters could fill these in...
                $schedulerValues['TOITEMID']                 = '';
                $schedulerValues['ITEMGLGROUP']              = '';
                $schedulerValues['WAREHOUSEID']              = '';
                $schedulerValues['LOCATIONID']               = '';

                $hlthrunMgr->add($schedulerValues);
            }
        } else if ($preferences['COSTING_WAS_ON_A_SCHEDULE'] == 'true') { // we need to delete the schedule record.
            $ok = $hlthrunMgr->deleteMIVQuickSchedule();
            $preferences['COSTING_WAS_ON_A_SCHEDULE'] = 'false'; // not strictly nescessary, but....
        }

        if ($preferences['ENABLECYCLECOUNT'] == 'true') {
            //Need to create Adjustment TD's for the Reconciliation process.
            $ok = $ok && $this->createCycleCountAdjustmentTemplates();
        } else {
            $preferences['CYCLECOUNTSEQUENCE'] = '';
        }

        $ok = $ok && $this->checkRelatedDimensions($preferences);

        $ok = $ok && $this->canPreferencesBeDisabled($preferences);

        return $ok;
    }


    /**
     * @param array $preferences
     *
     * @return bool
     */
    private function canPreferencesBeDisabled($preferences)
    {
        $ok = true;

        $ok = $ok && $this->canDisabledTrackingPreference($preferences);

        $ok = $ok && $this->canDisabledKitsPreference($preferences);

        $ok = $ok && $this->canDisabledStockableKitsPreference($preferences);

        $ok = $ok && $this->canDisabledMultiCostMethodsPreference($preferences);

        $ok = $ok && $this->canDisabledCustUOMPreference($preferences);

        return $ok;
    }

    /**
     * @param array $newPreferences
     *
     * @return bool
     */
    private function canDisabledStockableKitsPreference($newPreferences)
    {
        $stockableKitsPreference = GetPreferenceForProperty(Globals::$g->kINVid, 'LIGHTASSEMBLY');

        $newStockableKitsPrefDisabled = ($newPreferences['LIGHTASSEMBLY'] == null
            || $newPreferences['LIGHTASSEMBLY'] == 'false');

        if ($stockableKitsPreference === 'T' && $newStockableKitsPrefDisabled) {

            $params = [];
            $params[0] = "SELECT COUNT(1) lineitemcount
                          FROM icitem ic
                          WHERE
                            ic.cny# = :1
                            AND ic.itemtype = :2
                            AND EXISTS (SELECT 1 
                                        FROM docentrymst de
                                        WHERE de.cny# = ic.cny#
                                            AND de.itemkey = ic.itemid
                                        )";
            $params[1] = GetMyCompany();
            $params[2] = 'SK';
            $res = QueryResult($params);


            if (count($res ?? []) > 0) {
                foreach ($res as $row) {
                    if (($row['LINEITEMCOUNT'] ?? 0) > 0) {
                        Globals::$g->gErr->addIAError('INV-0154', __FILE__ . ":" . __LINE__,
                            "",
                            [],
                            "",
                            [],
                            "To disable stockable kits, first delete the transactions that use stockable kits. Then, try again.",
                            []
                        );
                        return false;
                    }
                }
            }
        }

        return true;
    }

    /**
     * @param array $newPreferences
     *
     * @return bool
     */
    private function canDisabledTrackingPreference($newPreferences)
    {
        $ok = true;

        $currSerialTrackingPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLESERIAL');
        $currLotTrackingPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLELOT');
        $currBinTrackingPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLEBIN');
        $currExpDateTrackingPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLE_EXPIRATION');

        $newSerialTrackingPrefDisabled = ($newPreferences['ENABLESERIAL'] == null
            || $newPreferences['ENABLESERIAL'] == 'false');
        $newLotTrackingPrefDisabled = ($newPreferences['ENABLELOT'] == null
            || $newPreferences['ENABLELOT'] == 'false');
        $newBinTrackingPrefDisabled = ($newPreferences['ENABLEBIN'] == null
            || $newPreferences['ENABLEBIN'] == 'false');
        $newExpDateTrackingPrefDisabled = ($newPreferences['ENABLE_EXPIRATION'] == null
            || $newPreferences['ENABLE_EXPIRATION'] == 'false');

        $trackingPreferenceDisabled = false;

        if ($currSerialTrackingPref === 'T' && $newSerialTrackingPrefDisabled) {
            $trackingPreferenceDisabled = true;
        }

        if ($currLotTrackingPref === 'T' && $newLotTrackingPrefDisabled) {
            $trackingPreferenceDisabled = true;
        }

        if ($currBinTrackingPref === 'T' && $newBinTrackingPrefDisabled) {
            $trackingPreferenceDisabled = true;
        }

        if ($currExpDateTrackingPref === 'T' && $newExpDateTrackingPrefDisabled) {
            $trackingPreferenceDisabled = true;
        }

        if (!$trackingPreferenceDisabled) {
            return true;
        }

        $params = [];
        $params[0] = "SELECT
                            COUNT(serialno) serialcount,
                            COUNT(lotno) lotcount,
                            COUNT(aislekey) aislecount,
                            COUNT(rowkey) rowcount,
                            COUNT(binkey) bincount,
                            COUNT(expirationdate) expirationcount
                        FROM
                            docentrytrackdetail
                        WHERE
                            docentrytrackdetail.cny# = : 1 ";
        $params[1] = GetMyCompany();
        $res = QueryResult($params);


        if (count($res ?? []) > 0) {
            $res = $res[0];
            if ($newSerialTrackingPrefDisabled && $res['SERIALCOUNT'] > 0) {
                Globals::$g->gErr->addIAError('INV-0155', __FILE__ . ":" . __LINE__,
                    "",
                    [],
                    "",
                    [],
                    "To disable serial tracking, first delete the transactions that use serial numbers. Then, try again.",
                    []
                );
                $ok = false;
            }

            if ($newLotTrackingPrefDisabled && $res['LOTCOUNT'] > 0) {
                Globals::$g->gErr->addIAError('INV-0156', __FILE__ . ":" . __LINE__,
                    "",
                    [],
                    "",
                    [],
                    "To disable lot tracking, first delete the transactions that use lot numbers. Then, try again.",
                    []
                );
                $ok = false;
            }
            if ($newBinTrackingPrefDisabled
                && ($res['AISLECOUNT'] > 0 || $res['ROWCOUNT'] > 0 || $res['BINCOUNT'] > 0)) {
                Globals::$g->gErr->addIAError('INV-0157', __FILE__ . ":" . __LINE__,
                    "",
                    [],
                    "",
                    [],
                    "To disable bin tracking, first delete the transactions that use bin information. Then, try again.",
                    []
                );
                $ok = false;
            }
            if ($newExpDateTrackingPrefDisabled && $res['EXPIRATIONCOUNT'] > 0) {
                Globals::$g->gErr->addIAError('INV-0158', __FILE__ . ":" . __LINE__,
                    "",
                    [],
                    "",
                    [],
                    "To disable expiration tracking, first delete the transactions that use expiration dates. Then, try again.",
                    []
                );
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * @param array $newPreferences
     *
     * @return bool
     */
    private function canDisabledMultiCostMethodsPreference($newPreferences)
    {
        $currMultiCostMethodsPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLE_MULTI_COST');

        $newMultiCostMethodsPrefDisabled = ($newPreferences['ENABLE_MULTI_COST'] == null
            || $newPreferences['ENABLE_MULTI_COST'] == 'false');

        if ($currMultiCostMethodsPref === 'T' && $newMultiCostMethodsPrefDisabled) {

            $params = [];
            $params[0] = "SELECT ic.cost_method, COUNT(1)
                         FROM icitem ic
                         WHERE
                            ic.cny# = :1
                            AND EXISTS (SELECT 1 
                                        FROM docentrymst de
                                        WHERE de.cny# = ic.cny#
                                            AND de.itemkey = ic.itemid
                                            AND de.costmethod != :2
                                        )
                         GROUP BY ic.cost_method
                         having count(ic.cost_method) > 0";
            $params[1] = GetMyCompany();
            $params[2] = 'S';
            $res = QueryResult($params);

            if (count($res ?? []) > 0) {
                Globals::$g->gErr->addIAError('INV-0159', __FILE__ . ":" . __LINE__,
                    "",
                    [],
                    "",
                    [],
                    "To disable multiple cost methods, first delete the transactions that use inventory items, which includes stockable kits. Then, try again.",
                    []
                );
                return false;
            }
        }

        return true;
    }

    /**
     * @param array $newPreferences
     *
     * @return bool
     */
    private function canDisabledLandedCostPreference($newPreferences)
    {
        $currLandedCostPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLELANDEDCOST');

        $newLandedCostPrefDisabled = ($newPreferences['ENABLELANDEDCOST'] == null
            || $newPreferences['ENABLELANDEDCOST'] == 'false');

        if ($currLandedCostPref === 'T' && $newLandedCostPrefDisabled) {

            $params = [];
            $params[0] = "SELECT
                            COUNT(1) AS landedcostcount
                         FROM
                            docentrymst de
                         WHERE
                            de.cny# = :1
                            AND de.lccatkey IS NOT NULL";
            $params[1] = GetMyCompany();
            $res = QueryResult($params);

            if ($res[0]["LANDEDCOSTCOUNT"] > 0) {
                Globals::$g->gErr->addIAError('INV-0160', __FILE__ . ":" . __LINE__,
                    "",
                    [],
                    "",
                    [],
                    "To disable landed costs, first delete the landed cost transactions—both the transactions that include estimated landed costs and those that distribute actual landed costs back to another transaction.",
                    []
                    );
                return false;
            }
        }

        return true;
    }

    /**
     * @return bool|string
     */
    public function getWarehouseSequnce()
    {
        $v = $this->GetPreference('WAREHOUSESEQUENCE', $this->modKey);

        return $v;
    }

    /**
     * @return bool|string
     */
    public function getCycleCountSequnce()
    {
        $v = $this->GetPreference('CYCLECOUNTSEQUENCE', $this->modKey);

        return $v;
    }

    /**
     * @return string
     */
    public function getExchangeRateType()
    {
        $v = $this->GetPreference('EXCH_RATE_TYPE_ID', $this->modKey);
        return $v;
    }

    /**
     * @return bool
     */
    private function setupWarehouseTransfer()
    {
        $ok = $this->createWarehouseTransferTDs();

        return $ok;
    }


    /**
     * @return bool
     */
    private function setupInTransitWarehouseTransfer()
    {
        $ok = $this->setupIntransitTotal();
        $ok = $ok && $this->createInTransitWarehouseTransferTDs();
        $ok = $ok && $this->updateRecallfWHTransferInDoc();

        return $ok;
    }

    /**
     * setupIntransitTotal
     *
     * @return bool
     */
    private function setupIntransitTotal()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $totalManager = $gManagerFactory->getManager('invtotal');
        $filter = array(
            'selects' => array('RECORDNO'),
            'filters' => array(
                array(
                    array('NAME', '=', 'INTRANSIT'),
                )
            ),
        );

        $invTotalRes = $totalManager->GetList($filter);

        //if INTRANSIT is not present, then create one
        if (!isset($invTotalRes[0])) {
            $invTotalValues = array(
                'NAME' => 'INTRANSIT',
                'STATUS' => 'active'
            );
            $ok = $ok && $totalManager->add($invTotalValues);
        }
        return $ok;
    }

    /**
     * updateRecallfWHTransferInDoc
     *
     * @return bool
     */
    private function updateRecallfWHTransferInDoc()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        $docRecallMgr = $gManagerFactory->getManager("docrecalls");

        //updating recallinfo for in doc
        $obj['DOCID'] = ICTransferManager::INDOCTYPE;
        $obj['RECDOCPAR'] = ICTransferManager::INTRANSITDOCTYPE;
        $obj['DOCPAR'] = $docparMgr->getLatestVersionKey($obj['DOCID']);
        if (!$docRecallMgr->IsExists($obj)) {
            $ok = $ok && $docRecallMgr->add($obj);
        }

       return $ok;
    }

/**
     * Return boolean whether if current configuration is advanced or not
     *
     * @return bool
     */
    public function IsAdvancedSetup()
    {
        $v = $this->GetPreference('ENABLE_ADVANCED', $this->modKey);
        return ($v == 'true') ? true : false;
    }

    /**
     * Get default journals by mod
     *
     * @param array &$preferences preferences
     *
     * @return bool
     */
    protected function defaultJournalsByMod(&$preferences)
    {
        return $this->defaultJournals($preferences, 'I');
    }

    /**
     * public function GetTrackingPrefs()
     * {
     *     global $kINVid;
     *     GetModulePreferences($kINVid,$prefs);
     *     return $prefs;
     * }
     */

    /**
     * @return bool
     */
    public static function getUOMPreference()
    {
        $pref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLE_UOM_IN_REPORT');

        return ($pref == 'T') ? true : false;
    }

    /**
     * Returns an array containing the list of preferences that could be overriden at the entity level
     *
     * @return string[]
     */
    protected function getValidPreferencesAtEntityLevel()
    {
        return array(
            'DRAFTMODE', 'ENABLE_MULTI_UOM', 'REORDER_METHOD', 'LIGHTASSEMBLY', 'ENABLE_MULTI_COST',
            'ENABLE_UOM_IN_REPORT', 'LANDEDCOST', 'ENABLEAUTOPRINTLABEL', 'DISTRIBUTE_SUBTOTALS_AT_ENTITY'
        );
    }

    /**
     * @param string[] &$preferences
     * @param string $key
     *
     * @return bool
     */
    protected function includePreference(&$preferences, $key)
    {
        $ok = true;
        if (($key == 'dummy')
            || ($key == 'MOD')
            || ($key == 'ENABLE_ADVANCED') // It is excluded here because it will be set in setOtherModulesPreferences()
            || (!IsAdvancedConfiguration() && false !== strstr($key, 'DOCTYPES'))
        ) {
            $ok = false;
        }

        return ($ok) ? parent::includePreference($preferences, $key) : $ok;
    }

    /**
     * MoveTDToTopLevelIfNeeded
     * Move the TD at $tdRecord from $tdLocation to top level if needed.
     *
     * @return bool
     */
    private function MoveTDToTopLevelIfNeeded($tdRecord, $tdLocation)
    {
        $ok = true;
        $curLocation = GetContextLocation();
        if ($tdLocation != null && $tdLocation != $curLocation) {
            $qry = 'QRY_DOCUMENTPARAMS_UPDATE_LOCATIONKEY_TO_NULL';
            $args = array($tdRecord, GetMyCompany());
            $docparMgr = Globals::$g->gManagerFactory->getManager('invdocumentparams');
            $ok = $docparMgr->DoQuery($qry, $args);
        }
        return $ok;
    }


    /**
     * CreateStockablekitsTDS
     *
     * @return bool
     */
    private function CreateStockablekitsTDS()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Build kits TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_FOR_UNIQUENESS_CHECK';
        $args = array('Build Kits', GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (isset($res[0])) {
            //If we already have the system TD for stkit build, make sure it's at top level
            $ok = $this->MoveTDToTopLevelIfNeeded($res[0]['RECORD#'], $res[0]['LOCATIONKEY']);
        } else {
            $values = array(
                'DOCID' => 'Build Kits',
                'DESCRIPTION' => 'Build Kits',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Receipt',
                'EDITTYPE' => 'Edit in Draft Only',
                'DELTYPE' => 'Delete in Draft Only',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL_numofrows_top' => '6',
                'DOCPAR_INVGL_numofrows_bottom' => '6',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS_numofrows_top' => '6',
                'DOCPAR_TOTALS_numofrows_bottom' => '6',
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Add',
                    )
                ),
                'DOCPAR_SUBTOTAL_numofrows_top' => '6',
                'DOCPAR_SUBTOTAL_numofrows_bottom' => '6',
                'DOCPAR_SUBTOTAL' => array(),
                'DOCPAR_RECALLS_numofrows_top' => '6',
                'DOCPAR_RECALLS_numofrows_bottom' => '6',
                'up_gu_0' => 'Group\Everyone',
                'up_gup_0' => 'allow_0',
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        // Disassemble kits TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_FOR_UNIQUENESS_CHECK';
        $args = array('Disassemble Kits', GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (isset($res[0])) {
            //If we already have the system TD for stkit disbuild, make sure it's at top level
            $ok = $this->MoveTDToTopLevelIfNeeded($res[0]['RECORD#'], $res[0]['LOCATIONKEY']);
        } else {
            $values = array(
                'DOCID' => 'Disassemble Kits',
                'DESCRIPTION' => 'Disassemble Kits',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Receipt',
                'EDITTYPE' => 'Edit in Draft Only',
                'DELTYPE' => 'Delete in Draft Only',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL_numofrows_top' => '6',
                'DOCPAR_INVGL_numofrows_bottom' => '6',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS_numofrows_top' => '6',
                'DOCPAR_TOTALS_numofrows_bottom' => '6',
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Subtract',
                    )
                ),
                'DOCPAR_SUBTOTAL_numofrows_top' => '6',
                'DOCPAR_SUBTOTAL_numofrows_bottom' => '6',
                'DOCPAR_SUBTOTAL' => array(),
                'DOCPAR_RECALLS_numofrows_top' => '6',
                'DOCPAR_RECALLS_numofrows_bottom' => '6',
                'up_gu_0' => 'Group\Everyone',
                'up_gup_0' => 'allow_0',
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }


    /**
     * createInTransitWarehouseTransferTDs
     *
     * @return bool
     */
    private function createInTransitWarehouseTransferTDs()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // transfer out TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(ICTransferManager::INTRANSITDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => ICTransferManager::INTRANSITDOCTYPE,
                'DESCRIPTION' => 'In Transit Warehouse Transfer',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Shipping',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'N',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'CREATETYPE' => 'Convert only',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'false',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'INTRANSIT',
                        'Q_QV' => 'Quantity',
                        'SIGN' => 'Add',
                    )
                ),
                'DOCPAR_RECALLS' => array(
                    array(
                        'RECDOCPAR' => ICTransferManager::OUTDOCTYPE
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }
        return $ok;
    }

    /**
     * createWarehouseTransferTDs
     *
     * @return bool
     */
    private function createWarehouseTransferTDs()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // transfer out TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(ICTransferManager::OUTDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => ICTransferManager::OUTDOCTYPE,
                'DESCRIPTION' => 'Warehouse Transfer Out',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Shipping',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Close Transaction',
                'CREATETYPE' => 'Convert only',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Subtract',
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        // transfer in TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(ICTransferManager::INDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => ICTransferManager::INDOCTYPE,
                'DESCRIPTION' => 'Warehouse Transfer In',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Receipt',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'CREATETYPE' => 'Convert only',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Add',
                    ),
                ),
                'DOCPAR_RECALLS' => array(
                    array(
                        'RECDOCPAR' => ICTransferManager::OUTDOCTYPE
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createLandedCostTD
     *
     * @return bool
     */
    private function createLandedCostTD()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Disassemble kits TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(InvDocumentManager::LANDEDCOSTDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => InvDocumentManager::LANDEDCOSTDOCTYPE,
                'DESCRIPTION' => 'Adjustment Increase for LC Actuals',
                'DOCCLASS' => 'Adjustment',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Value',
                        'SIGN' => 'Add',
                    ),
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createLandedCostEstTD
     *
     * @return bool
     */
    private function createLandedCostEstTD()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Disassemble kits TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(InvDocumentManager::LANDEDCOSTESTDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => InvDocumentManager::LANDEDCOSTESTDOCTYPE,
                'DESCRIPTION' => 'Adjustment Increase for LC Estimates',
                'DOCCLASS' => 'Adjustment',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Value',
                        'SIGN' => 'Add',
                    ),
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createLandedCostEstReversalTD
     *
     * @return bool
     */
    private function createLandedCostEstReversalTD()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Disassemble kits TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(InvDocumentManager::LANDEDCOSTESTREVDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => InvDocumentManager::LANDEDCOSTESTREVDOCTYPE,
                'DESCRIPTION' => 'Adjustment Decrease for LC Estimate Reversals',
                'DOCCLASS' => 'Adjustment',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Value',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Value',
                        'SIGN' => 'Subtract',
                    ),
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * Checking if Landed costs is enabled and is using documents with Change order enabled
     * @param array $values
     * @return bool
     */
    private function changeOrderLandedCostsCheck($values)
    {
        $ok = true;
        global $gManagerFactory;
        foreach (json_decode($values['LANDEDCOST']) as $item) {
            $item = get_object_vars($item);
            $filter = array(
                'selects' => array('RECORDNO', 'ENABLEDOCCHANGE'),
                'filters' => array(array(array('DOCID', '=', $item['LANDEDCOSTDOCPAR']))),
            );
            $managers = ['podocumentparams', 'sodocumentparams',];
            foreach ($managers as $manager) {
                $docParMgr = $gManagerFactory->getManager($manager);
                $res = $docParMgr->GetList($filter);

                if (isset($res[0]['ENABLEDOCCHANGE'])) {
                    $docChange = $res[0]['ENABLEDOCCHANGE'];
                    if (in_array($docChange, array('Enable Change', 'Change Order'), true)) {
                        Globals::$g->gErr->addIAError('INV-1427', __FILE__ . ':' . __LINE__,
                            "You cannot add document {$item['LANDEDCOSTDOCPAR']} as it is already enabled for change order.", ['DSVAL' => $item['LANDEDCOSTDOCPAR']]
                        );
                        $ok = false;
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * createCycleCountAdjustmentTemplates
     *
     *
     * @return bool
     */
    private function createCycleCountAdjustmentTemplates()
    {
        $ok = true;
        $ok = $ok && $this->createCycleCountAdjustmentIncreaseTemplate();
        $ok = $ok && $this->createCycleCountAdjustmentDecreaseTemplate();
        $ok = $ok && $this->createCycleCountAdjustmentDamagedTemplate();
        return $ok;
    }

    /**
     * createCycleCountAdjustmentIncreaseTemplate
     *
     * @return bool
     */
    private function createCycleCountAdjustmentIncreaseTemplate()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Increase Adjustment TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(ICCycleCountManager::ADJINCREASEDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => ICCycleCountManager::ADJINCREASEDOCTYPE,
                'DESCRIPTION' => 'Cyclecount Increase Adjustment',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Add',
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createCycleCountAdjustmentDecreaseTemplate
     *
     * @return bool
     */
    private function createCycleCountAdjustmentDecreaseTemplate()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Decrease Adjustment TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(ICCycleCountManager::ADJDECREASEDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => ICCycleCountManager::ADJDECREASEDOCTYPE ,
                'DESCRIPTION' => 'Cyclecount Decrease Adjustment',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Subtract',
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createCycleCountAdjustmentDamagedTemplate
     *
     * @return bool
     */
    private function createCycleCountAdjustmentDamagedTemplate()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');

        // Damaged Adjustment TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(ICCycleCountManager::ADJDAMAGEDDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {

           // Check if inv totlas has type DAMAGED, if not create one before creating Damaged Cycle count TD
            $totalManager = $gManagerFactory->getManager('invtotal');
            $filter = array(
                'selects' => array('RECORDNO'),
                'filters' => array(
                    array(
                        array('NAME', '=', 'DAMAGED'),
                    )
                ),
            );

            $invTotalRes = $totalManager->GetList($filter);

            //if DAMAGED is not present, then create one before creating Damaged Cycle count TD
            if (!isset($invTotalRes[0])) {
                $invTotalValues = array(
                    'NAME' => 'DAMAGED',
                    'STATUS' => 'active'
                );
                $ok = $ok && $totalManager->add($invTotalValues);
            }

            $values = array(
                'DOCID' => ICCycleCountManager::ADJDAMAGEDDOCTYPE,
                'DESCRIPTION' => 'Cyclecount Damaged Adjustment',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'N',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'No',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'DAMAGED',
                        'Q_QV' => 'Quantity',
                        'SIGN' => 'Add',
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createFullfillmentDocpars
     * @param string $flow
     * @param array $fulfillmentGrid
     *
     * @return bool
     */
    private function createFullfillmentDocpars($flow, &$fulfillmentGrid)
    {
        $ok = $this->createFullfillmentOrder();

        switch ($flow) {
            case 'OSI':
                $ok = $ok && $this->createFullfillmentShipper(SODocumentManager::FULFILLMENTORDERDOCTYPE);
                $ok = $ok && $this->createFullfillmentInvoice(SODocumentManager::FULFILLMENTSHIPPERDOCTYPE);
                //$fulfillmentGrid  = [
                //    '0' => ['FULFILLMENTDOCPAR' => SODocumentManager::FULFILLMENTORDERDOCTYPE],
                //    '1' => ['FULFILLMENTDOCPAR' => SODocumentManager::FULFILLMENTSHIPPERDOCTYPE],
                //    '2' => ['FULFILLMENTDOCPAR' => SODocumentManager::FULFILLMENTINVOICEDOCTYPE],
                //];
                break;

            case 'OIS':
                $ok = $ok && $this->createFullfillmentInvoice(SODocumentManager::FULFILLMENTORDERDOCTYPE);
                $ok = $ok && $this->createFullfillmentShipper(SODocumentManager::FULFILLMENTINVOICEDOCTYPE);
                //$fulfillmentGrid  = [
                //    '0' => ['FULFILLMENTDOCPAR' => SODocumentManager::FULFILLMENTORDERDOCTYPE],
                //    '1' => ['FULFILLMENTDOCPAR' => SODocumentManager::FULFILLMENTINVOICEDOCTYPE],
                //    '2' => ['FULFILLMENTDOCPAR' => SODocumentManager::FULFILLMENTSHIPPERDOCTYPE],
                //];
                break;
        }
        $fulfillmentGrid = [];

        return $ok;
    }

    /**
     * createFullfillmentOrder
     *
     * @return bool
     */
    private function createFullfillmentOrder()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('sodocumentparams');

        // Disassemble kits TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(SODocumentManager::FULFILLMENTORDERDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => SODocumentManager::FULFILLMENTORDERDOCTYPE,
                'DESCRIPTION' => 'Fulfillment Order',
                'DOCCLASS' => 'Order',
                'CATEGORY' => 'Order',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'N',
                'ENABLE_SEQNUM' => 'false',
                'UPDATES_INV' => 'No',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Leave Transaction Open',
                'EXTERNAL_ISSUE' => 'No',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'ENABLEFULFILLMENT' => 'true',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHOLD',
                        'Q_QV' => 'Quantity',
                        'SIGN' => 'Add',
                    ),
                ),
                'SALE_PUR_TRANS' => 'Sale',
                'CUST_VEND' => 'Warehouse',
                'ENABLERENEWALS' => 'None',
                'SYSTEM_GENERATED' => true,
                'CONVERT_UNITS' => 'true',
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * createFullfillmentShipper
     * 
     * @param string $createdFrom
     *
     * @return bool
     */
    private function createFullfillmentShipper($createdFrom)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('sodocumentparams');

        // Fulfillment Shipper TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(SODocumentManager::FULFILLMENTSHIPPERDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => SODocumentManager::FULFILLMENTSHIPPERDOCTYPE,
                'DESCRIPTION' => 'Fulfillment Shipper',
                'DOCCLASS' => 'List',
                'CATEGORY' => 'Shipping',
                'EDITTYPE' => 'All', // 'No Edit',
                'DELTYPE' => 'All', // 'No Delete',
                'UPDATES_GL' => 'N',
                'ENABLE_SEQNUM' => 'false',
                'INHERIT_SOURCE_DOCNO' => 'true',
                'UPDATES_INV' => 'No',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Leave Transaction Open',
                'EXTERNAL_ISSUE' => 'No',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'ENABLEFULFILLMENT' => 'true',
                'CREATETYPE' => 'Convert only',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity',
                        'SIGN' => 'Subtract',
                    ),
                ),
                'DOCPAR_RECALLS' => array(
                    array(
                        'RECDOCPAR' => $createdFrom,
                        'ISDEFAULT' => 'true',
                    )
                ),
                'SALE_PUR_TRANS' => 'Sale',
                'CUST_VEND' => 'Warehouse',
                'ENABLERENEWALS' => 'None',
                'SYSTEM_GENERATED' => true,
                'CONVERT_UNITS' => 'true',
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }


    /**
     * createFullfillmentInvoice
     *
     * @param string $createdFrom
     *
     * @return bool
     */
    private function createFullfillmentInvoice($createdFrom)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('sodocumentparams');

        // Fulillment Invoice TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(SODocumentManager::FULFILLMENTINVOICEDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => SODocumentManager::FULFILLMENTINVOICEDOCTYPE,
                'DESCRIPTION' => 'Fulfillment Invoice',
                'DOCCLASS' => 'Invoice',
                'CATEGORY' => 'Invoice',
                'EDITTYPE' => 'All', // 'No Edit',
                'DELTYPE' => 'All', // 'No Delete',
                'UPDATES_GL' => 'A',
                'ENABLE_SEQNUM' => 'false',
                'INHERIT_SOURCE_DOCNO' => 'true',
                'UPDATES_INV' => 'Yes',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Leave Transaction Open',
                'EXTERNAL_ISSUE' => 'No',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'ENABLEFULFILLMENT' => 'true',
                'CREATETYPE' => 'Convert only',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Value',
                        'SIGN' => 'Subtract',
                    ),
                ),
                'DOCPAR_RECALLS' => array(
                    array(
                        'RECDOCPAR' => $createdFrom,
                        'ISDEFAULT' => 'true',
                    )
                ),
                'SALE_PUR_TRANS' => 'Sale',
                'CUST_VEND' => 'Warehouse',
                'ENABLERENEWALS' => 'None',
                'SYSTEM_GENERATED' => true,
                'CONVERT_UNITS' => 'true',
            );

            $ok = $ok && $docparMgr->add($values);
        }

        return $ok;
    }

    /**
     * @return array
     */
    public function getDBTranslatedFieldsForEditor(): array
    {
        // Translate EXCH_RATE_TYPE_ID field explicitely in formeditor
        return ['EXCH_RATE_TYPE_ID'];
    }


    /**
     *  Set up Supplies Inventory TDs and the SYS-Supply-Item
     *
     * @param  array $preferences       the preferences before saving
     *
     * @return bool
     */
    private function setupSupplies(&$preferences)
    {
        $ok = true;
        $preferences['DISALLOW_NEGINV']         = 'true';
        $preferences['NEGATIVEFULFILLMENT']     = 'false';
        $preferences['COSTING_ON_A_SCHEDULE']   = 'true';   // should be redundant at this point, but....

        //If supplies inv is enabled, we need to turn off the warehouses that are overriding the negative inv
        $ok = $ok && WarehouseManager::turnOffAllNegativeInvOverriddenWarehouses();

        // If they specify a TD, make sure it is ok.... (if they don't specify, thats ok for now)
        $dsTD = $preferences['SUPPLIESINVENTORYDS'] ?? '';
        $poTD = $preferences['SUPPLIESINVENTORYPO'] ?? '';
        $suppliesManager = Globals::$g->gManagerFactory->getManager('invsupplies');
        if ($dsTD != '') {
            $ok = $ok && $suppliesManager->validatePO(true, $dsTD, true);  // true = report errors
        }
        if ($poTD != '') {
            $ok = $ok && $suppliesManager->validatePO(false, $poTD, true);
        }

        $ok = $ok && $this->createSuppliesInventoryTotal();
        $ok = $ok && $this->createSuppliesInventoryTDs();
        $ok = $ok && $this->createSuppliesInventoryItem();

        return $ok;
    }


    /**
     * createSuppliesInventoryTotal
     *
     * @return bool
     */
    private function createSuppliesInventoryTotal()
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $totalManager = $gManagerFactory->getManager('invtotal');
        $filter = array(
            'selects' => array('RECORDNO'),
            'filters' => array(
                array(
                    array('NAME', '=', 'SUPPLIES'),
                )
            ),
        );

        $invTotalRes = $totalManager->GetList($filter);

        //if SUPPLIES is not present, then create one
        if (!isset($invTotalRes[0])) {
            $invTotalValues = array(
                'NAME' => 'SUPPLIES',
                'STATUS' => 'active'
            );
            $ok = $ok && $totalManager->add($invTotalValues);
        }
        return $ok;
    }


    /**
     * createSuppliesInventoryTDs
     *
     * @return bool
     */
    private function createSuppliesInventoryTDs()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ok = true;
        $docparMgr = $gManagerFactory->getManager('podocumentparams');

        // transfer out TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array( PODocumentManager::SUPPLIESREQUESTDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => PODocumentManager::SUPPLIESREQUESTDOCTYPE,
                'DESCRIPTION' => 'Supplies request',
                'DOCCLASS' => 'Quote',
                'CATEGORY' => 'Quote',
                'EDITTYPE' => 'All',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'N',
                'ENABLE_SEQNUM' => 'true',
                'UPDATES_INV' => 'No',
                'UPDATES_COST' => 'No',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Leave Transaction Open',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    // todo: not clear how this will decrement.  On Issue?  Direct-Ship?
                    // Normally handled by conversion, but we don't convert....
                    array(
                        'TOTALID' => 'SUPPLIES',
                        'Q_QV' => 'Quantity',
                        'SIGN' => 'Add',
                    )
                ),
                'SALE_PUR_TRANS' => 'Purchase',
                'CUST_VEND' => 'Warehouse',
                'USERPERM' => 'false',
                'CONVERT_UNITS' => 'false',
                'ALLOWEDITDELIVERTO' => 'true',
                'SHOWTITLE3' => 'true',
                'OVERRIDE_PRICE' => 'true',
                'ALLOWEDITCUSTVEND' => 'Always',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        // SUPPLIESISSUEDOCTYPE TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(PODocumentManager::SUPPLIESISSUEDOCTYPE, GetMyCompany());
        $docparMgr = $gManagerFactory->getManager('invdocumentparams');
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => PODocumentManager::SUPPLIESISSUEDOCTYPE,
                'DESCRIPTION' => 'Supplies issue',
                'DOCCLASS' => 'Adjustment',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'true',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Decrease',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Subtract',
                    ),
                    array(
                        'TOTALID' => 'SUPPLIES',
                        'Q_QV' => 'Quantity',
                        'SIGN' => 'Subtract',
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }

        // SUPPLIESRETURNDOCTYPE TD
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
        $args = array(PODocumentManager::SUPPLIESRETURNDOCTYPE, GetMyCompany());
        $res = $docparMgr->DoQuery($qry, $args);

        if (!isset($res[0])) {
            $values = array(
                'DOCID' => PODocumentManager::SUPPLIESRETURNDOCTYPE,
                'DESCRIPTION' => 'Supplies return',
                'DOCCLASS' => 'Adjustment',
                'CATEGORY' => 'Adjustment',
                'EDITTYPE' => 'No Edit',
                'DELTYPE' => 'No Delete',
                'UPDATES_GL' => 'G',
                'ENABLE_SEQNUM' => 'true',
                'UPDATES_INV' => 'Quantity and Value',
                'IN_OUT' => 'Increase',
                'CONVTYPE' => 'Close Transaction',
                'EXTERNAL_ISSUE' => 'No',
                'WARNONLOWQTY' => 'true',
                'WAREHOUSESELMETHOD' => 'Sort by ID',
                'STATUS' => 'active',
                'DOCPAR_INVGL' => array(),
                'DOCPAR_TOTALS' => array(
                    array(
                        'TOTALID' => 'ONHAND',
                        'Q_QV' => 'Quantity & Value',
                        'SIGN' => 'Add',
                    )
                ),
                'DOCPAR_RECALLS' => array(
                    array(
                        'RECDOCPAR' => PODocumentManager::SUPPLIESISSUEDOCTYPE
                    )
                ),
                'SALE_PUR_TRANS' => 'Internal',
                'CUST_VEND' => 'Warehouse',
                'SYSTEM_GENERATED' => true,
            );

            $ok = $ok && $docparMgr->add($values);
        }
        return $ok;
    }



    /**
     * createSuppliesInventoryTDs
     *
     * @return bool
     */
    private function createSuppliesInventoryItem()
    {
        $ok          = true;

        // do we already have the supplies item?
        $qry    = [];
        $qry[]  = "select record# from icitemmst where cny# = :1 and itemid = :2 ";
        $qry[]  = GetMyCompany();
        $qry[]  = self::SYS_SUPPLY_ITEM;
        $result = QueryResult($qry);
        if ($result === false) {
            $ok = false;
        } else if (empty($result)) {
            // if it is empty, then add the record....
            $itemManager = Globals::$g->gManagerFactory->getManager('item');
            $values = [
                'ITEMID'            => self::SYS_SUPPLY_ITEM,
                'ISSUPPLYITEM'      => 'true',
                'NAME'              => GT($this->translatedText, 'IA.SYS_SUPPLIES_ITEM_NAME'),
                'STATUS'            => 'active',
                'ITEMTYPE'          => 'Non-Inventory',
                'ALLOW_BACKORDER'   => 'false',  // not sure this even applies to supplies?
                'TAXABLE'           => 'false',
                'PO_PRECISION'      => 8,
                'ITEMSHAVESTARTENDDATE' => 'false', // no contracts support
            ];
            $ok = $itemManager->add($values);
        }

        return $ok;
    }

}
