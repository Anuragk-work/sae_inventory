<?

import('OwnedObjectManager');

/**
 * Class ItemCrossRefManager
 */
class ItemCrossRefManager extends OwnedObjectManager
{

    /**
     * @var array $_itemsCache
     */
    var $_itemsCache = [];

    /**
     * @var array $_itemsUOMCache
     */
    var $_itemsUOMCache = [];

    /**
     * @var array $_vendorCache
     */
    var $_vendorCache = [];

    /**
     * @var array $_customerCache
     */
    var $_customerCache = [];

    /**
     * @var array $_uomInfoCache
     */
    var $_uomInfoCache = [];

    /**
     * @var array $_alternateItemsCache
     */
    var $_alternateItemsCache = [];

    /**
     * @var array $_oldValuesCache
     */
    var $_oldValuesCache = [];

    /**
     * @var array $_locEntityMap
     */
    var $_locEntityMap = [];

    /**
     * @var string CUSTOMER_TOKEN The customer token
     */
    const CUSTOMER_TOKEN = 'IA.CUSTOMER';
    /**
     * @var string ITEM_CROSSREF The itemcrossref
     */
    const ITEM_CROSSREF = 'itemcrossref';


    /**
     * @var string ITEM_TOKEN The item token
     */
    const ITEM_TOKEN = 'IA.ITEM';

    /**
     * @var string VENDOR_TOKEN The vendor token
     */
    const VENDOR_TOKEN = 'IA.VENDOR';

    /** @var bool $fromAPI */
    public static $fromAPI = false;

    /** @var bool $isDigitalNetworkSyncEnabled */
    protected $isDigitalNetworkSyncEnabled = false;

    /**
     * @var string[] $itemCrossReferenceTokens Tokens used here
     */
    private static $itemCrossReferenceTokens = [
        self::CUSTOMER_TOKEN,
        self::ITEM_TOKEN,
        self::VENDOR_TOKEN,
        'IA.CUSTOMER_ID',
        'IA.ITEM_ID',
        'IA.REFERENCE_TYPE'
    ];

    /**
     * @var string[] $localizedStringMap Localized strings
     */
    private static $localizedStringMap = null;

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);

        if( FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_POMATCH_DATASYNC')
            && POSetupManager::isPOMatchEnabled()
            && $this->isDNSyncEnabled() ) {
            $this->isDigitalNetworkSyncEnabled = true;
        }
    }

    /**
     * Translate a token to text.
     *
     * @param string $token Token to be translated
     *
     * @return string Translated token
     * @throws IAException
     */
    private static function translateToken(string $token)
    {
        if (self::$localizedStringMap === null) {
            self::$localizedStringMap = getLocalizedTextWithThrow(I18N::tokenArrayToObjectArray(self::$itemCrossReferenceTokens));
        }
        return GT(self::$localizedStringMap, $token);
    }

    /**
     * @param array $nValues
     *
     * @return bool
     */
    protected function regularAdd(&$nValues)
    {
        if (!is_array($nValues[0] ?? null)) {
            $tmpValues = $nValues;
            $nValues = [];
            $nValues[0] = $tmpValues;
        }

        $ok = true;
        $ok = $ok && $this->prepValues('add', $nValues);

        $ok = $ok && $this->validateValues('add', $nValues);

        $ok = $ok && parent::regularAdd($nValues);

        // as we support bulk insert we process all the records at once like prepvalues, validatevalues etc.
        // so even if its a singe record it comes in form of multi dimentional array
        // after set we have to return the single record not the array of record
        if (is_array($nValues[0]) && count($nValues) == 1
            && isset($nValues[0]['ITEMIDREST'])
            && $nValues[0]['ITEMIDREST'] !== ''
            && isset($nValues[0]['ITEMID'])) {
            $nValues = $nValues[0];
        }

        return $ok;
    }

    /**
     * @param array $nValues
     *
     * @return bool
     */
    protected function regularSet(&$nValues)
    {
        if (!is_array($nValues[0] ?? null)) {
            $tmpValues = $nValues;
            $nValues = [];
            $nValues[0] = $tmpValues;
        }

        $ok = true;
        $ok = $ok && $this->prepValues('set', $nValues);

        $ok = $ok && $this->validateValues('set', $nValues);

        $ok = $ok && parent::regularSet($nValues);

        // Cache the values for auditing to avoid an extra read later.
        if ($ok) {
            $auditTrailSession = AuditTrailSession::getInstance();
            $auditTrailSession->cacheAuditRecord($this->getAuditEntity(), $this->GetKeyValue($nValues), $nValues);
        }

        // as we support bulk insert we process all the records at once like prepvalues, validatevalues etc.
        // so even if its a singe record it comes in form of multi dimentional array
        // after set we have to return the single record not the array of record
        if (is_array($nValues[0]) && count($nValues) == 1
            && isset($nValues[0]['ITEMIDREST'])
            && $nValues[0]['ITEMIDREST'] !== ''
            && isset($nValues[0]['ITEMID'])) {
            $nValues = $nValues[0];
        }


        return $ok;
    }

    /**
     * @param string $action
     * @param array $nValues
     *
     * @return bool
     */
    function validateValues($action, &$nValues)
    {
        $gErr = Globals::$g->gErr;

        $itemText = self::translateToken(self::ITEM_TOKEN);
        $vendorText = self::translateToken(self::VENDOR_TOKEN);
        $custText = self::translateToken(self::CUSTOMER_TOKEN);

        $renamedTextArray = ['Item' => $itemText,
            'Vendor' => $vendorText,
            'Customer' => $custText];

        $ok = true;

        if (IsMultiEntityCompany() && GetContextLocation()) {
            // if at entity
            $locMgr = Globals::$g->gManagerFactory->getManager('locationentity');
            $this->_locEntityMap = $locMgr->GetEntityLocationMapbyID();
        }

        foreach ($nValues as &$values) {
            //
            // if reference type is null throw error
            if ($values['REFTYPE'] == '') {
                $msg = "Provide a valid reference type, then try again.";
                $gErr->addIAError('INV-0706', __FILE__ . '.' . __LINE__, $msg, []);
                return false;
            }

            //
            // if required field itemid is null throw error
            if ($values['ITEMID'] == '') {
                $msg = "Provide an $itemText ID, then try again.";
                $gErr->addIAError('INV-0707', __FILE__ . '.' . __LINE__, $msg, ['ITEM_TEXT' => $itemText]);
                return false;
            }

            // if $values['ITEMIDREST']  is set use it since with REST API ITEMIDREST will be set and for UI or xml api ITEMID not ITEMIDREST
            $itemID = (!self::$fromAPI) && isset($values['ITEMIDREST']) && $values['ITEMIDREST'] !== '' ? $values['ITEMIDREST'] : $values['ITEMID'];
            //
            // check if the given Item ID exists
            if (!isset($this->_itemsCache[$itemID])) {
                $msg = "The provided $itemText ID is invalid";
                $correction = "Provide a $itemText Item ID, then try again.";
                $gErr->addIAError('INV-0708',
                    __FILE__ . '.' . __LINE__,
                    $msg, ['ITEM_TEXT' => $itemText],
                    '', [],
                    $correction, ['ITEM_TEXT' => $itemText]
                );
                return false;
            }

            // prepare reference type context
            $values['REFTYPECONTEXT'] = ($values['REFTYPE'] == 'Customer' || $values['REFTYPE'] == 'Vendor')
                ? 'External' : 'Internal';

            switch($values['REFTYPECONTEXT']) {
                case 'External':
                    if(!$this->validateExternalValues($action, $renamedTextArray, $values)) {
                        return false;
                    }

                    switch ($values['REFTYPE']) {
                        case 'Customer':
                            $cusID = $values['CUSTOMERID'];
                            $values['CUSTOMERKEY'] = $this->_customerCache[$cusID]['RECORDNO'];
                            break;
                        case 'Vendor':
                            $vendID = $values['VENDORID'];
                            $values['VENDORKEY'] = $this->_vendorCache[$vendID]['RECORDNO'];
                            break;
                    }
                    break;

                case 'Internal':
                    if(!$this->validateInternalValues($action, $renamedTextArray, $values)) {
                        return false;
                    }
                    break;
            }

            // If ALTERNATEITEMKEY or ALTERNATEITEMIDREST is populated for external cross reference object
            if($values['REFTYPECONTEXT'] === 'External'){
               if(isset($values['ALTERNATEITEMKEY'])){
                   unset($values['ALTERNATEITEMKEY']);
               }
               if(isset($values['ALTERNATEITEMIDREST'])){
                    unset($values['ALTERNATEITEMIDREST']);
                }
            }


            // prep itemkey value
            $values['ITEMKEY'] = $this->_itemsCache[$itemID]['RECORDNO'];
        }

        if ($action == 'set') {
            $ok = $ok && $this->validateOldValuesForUpdate($nValues);
        }

        return $ok;
    }

    /**
     * @param string $action
     * @param array $renamedTextArray
     * @param array $values
     *
     * @return bool
     */
    function validateExternalValues($action, $renamedTextArray, &$values)
    {
        $gErr = Globals::$g->gErr;

        $itemText = $renamedTextArray['Item'];
        $vendorText = $renamedTextArray['Vendor'];
        $custText = $renamedTextArray['Customer'];

        $validVendIDs = array_keys($this->_vendorCache);
        $validCustIDs = array_keys($this->_customerCache);

        $custVendText = '';
        $custVendID = '';
        $custVendLoc = '';

        $ok = true;
        $lineMsg = '';
        if (isset($values['LINE_NO'])) {
            $lineno = $values['LINE_NO'];
            $lineMsg = $lineno >= 0 ? _("in line no : $lineno") : '';
        }

        $itemID = $values['ITEMID'];

        if(!$this->restrictedItemTypeValidation($values['REFTYPE'], $itemID, $renamedTextArray)){
            return false;
        }

        //
        // Get the line UOM Values for validation and passing it to PricingHandler to get the right converted quantity and value.
        if (!empty($values['UNIT'])) {
            // for REST some times the UOM key is changed or UOM ID can be changed so check for that
            $this->checkForUomChange($values);
            $unit = $values['UNIT'];
            $lineUOMValues = $this->_itemsUOMCache[$itemID][$unit];

            // Added check if UNIT provided check if its valid and update UNITKEY
            if ((!isset($lineUOMValues) || count($lineUOMValues) == 0) && isset($values['UNITKEY'])) {
                $lineUOMValues = $this->prepUnitOfMeasureForREST($values, $itemID);
            }

            if (!isset($lineUOMValues) || count($lineUOMValues) == 0) {
                $msg = sprintf('Provided unit \'%1$s\' is invalid', $unit);
                $correction = "Provide a valid unit and try again" . $lineMsg;

                $gErr->addIAError('INV-0709',
                    __FILE__ . ':' . __LINE__,
                    $msg, ['UNIT' => $unit],
                    '', [],
                    $correction, ['LINE_MSG' => $lineMsg]
                );
                return false;
            }
        }

        //
        // unset either vendorid/customerid
        switch (isl_strtolower($values['REFTYPE'])) {
            case 'vendor':
                if ($values['CUSTOMERID'] != '') {
                    $msg = "A $vendorText reference type does not accept a $custText ID.";
                    $correction = "Remove the $custText ID, then try again";

                    $gErr->addIAError(
                        'INV-0710',
                        __FILE__ . '.' . __LINE__,
                        $msg, ['VENDOR_TEXT' => $vendorText, 'CUST_TEXT' => $custText],
                        '', [],
                        $correction, ['CUST_TEXT' => $custText]
                    );
                    return false;
                }

                if ($values['VENDORID'] == '') {
                    $msg = "Provide a $vendorText ID when specifying a $vendorText reference type.";
                    $gErr->addIAError('INV-0711', __FILE__ . '.' . __LINE__, $msg, ['VENDOR_TEXT' => $vendorText]);
                    return false;
                }

                // check if the given vendor exits
                if (!in_array($values['VENDORID'], $validVendIDs)) {
                    $msg = sprintf('%1$s ID \'%2$s\' is invalid.', $vendorText, $values['VENDORID']);
                    $correction = sprintf('Provide a valid %1$s ID, then try again.', $vendorText);

                    $gErr->addIAError(
                        'INV-0712',
                        __FILE__ . '.' . __LINE__,
                        $msg, ['VENDOR_TEXT' => $vendorText, 'VENDORID' => $values['VENDORID']],
                        '', [],
                        $correction, ['VENDOR_TEXT' => $vendorText]
                    );
                    return false;
                }
                $custVendText = $vendorText;
                $custVendID = $values['VENDORID'];
                $custVendLoc = $this->_vendorCache[$custVendID]['LOCATIONKEY'];
                break;

            case 'customer':
                if ($values['VENDORID'] != '') {
                    $msg = "A $custText reference type does not accept a $vendorText ID.";
                    $correction = "Remove the $vendorText ID, then try again";

                    $gErr->addIAError(
                        'INV-0713',
                        __FILE__ . '.' . __LINE__,
                        $msg, ['CUST_TEXT' => $custText, 'VENDOR_TEXT' => $vendorText],
                        '', [],
                        $correction, ['VENDOR_TEXT' => $vendorText]
                    );
                    return false;
                }

                if ($values['CUSTOMERID'] == '') {
                    $msg = sprintf('Provide a %1$s ID when specifying a %1$s reference type.', $custText);
                    $gErr->addIAError('INV-0714', __FILE__ . '.' . __LINE__, $msg, ['CUST_TEXT' => $custText]);
                    return false;
                }

                // check if ht egiven customer exists
                if (!in_array($values['CUSTOMERID'], $validCustIDs)) {
                    $msg = sprintf('%1$s ID \'%2$s\' is invalid.', $custText, $values['CUSTOMERID']);
                    $correction = sprintf('Provide a valid %1$s ID, then try again.', $custText);

                    $gErr->addIAError(
                        'INV-0715',
                        __FILE__ . '.' . __LINE__,
                        $msg, ['CUST_TEXT' => $custText, 'CUSTOMERID' => $values['CUSTOMERID']],
                        '', [],
                        $correction, ['CUST_TEXT' => $custText]
                    );
                    return false;
                }
                $custVendText = $custText;
                $custVendID = $values['CUSTOMERID'];
                $custVendLoc = $this->_customerCache[$custVendID]['LOCATIONKEY'];
                break;
        }

        if ($values['ITEMALIASID'] == '') {
            $msg = "Provide an $itemText cross reference ID, then try again.";
            $gErr->addIAError('INV-0716', __FILE__ . '.' . __LINE__, $msg, ['ITEM_TEXT' => $itemText]);
            return false;
        }

        // check for any duplicates
        $res = $this->GetByReferenceType($values['REFTYPE'],
            '',
            $values['CUSTOMERID'],
            $values['VENDORID'],
            $values['ITEMALIASID']);
        //
        // check for any duplicates
        $throwDuplicateRecordError = false;
        if ($action == 'add') {
            //
            // make sure we passed correct parameters
            // here we are expecting only one row else throw excception
            if (count($res) > 0) {
                $throwDuplicateRecordError = true;
            }
        } else {
            //
            // make sure we passed correct parameters
            // here we are expecting only one row else throw excception
            if (count($res) > 0 && $res[0]['RECORDNO'] != $values['RECORDNO']) {
                $throwDuplicateRecordError = true;
            }
        }

        if($throwDuplicateRecordError) {
            $dupItemID = $res[0]['ITEMID'];
            $msg = "$itemText cross reference '" . $values['ITEMALIASID'] . "'";
            $msg .= " already exists for the $custVendText '$custVendID'" ;
            $msg .= " and $itemText '$dupItemID' combination.";

            $correction = "Enter a unique value for the cross reference $itemText ID, then try again.";

            $gErr->addIAError(
                'INV-0717',
                __FILE__ . '.' . __LINE__,
                $msg, ['ITEM_TEXT' => $itemText, 'ITEMALIASID' => $values['ITEMALIASID'], 'CUST_VEND_TEXT' => $custVendText, 'CUST_VEND' => $custVendID, 'DUP_ITEM' => $dupItemID],
                '', [],
                $correction, ['ITEM_TEXT' => $itemText]
            );
            return false;
        }

        //
        // in multientity company at entity level
        // throw error if Item belongs to root and Customer/Vendor belongs to entity
        //
        $itemLoc = $this->_itemsCache[$itemID]['LOCATIONKEY'];
        if (IsMultiEntityCompany() && GetContextLocation()) {
            $itemEntity = $this->_locEntityMap[$itemLoc]['ENTITY#'];
            $custVendEntity = $this->_locEntityMap[$custVendLoc]['ENTITY#'];

            if (isset($custVendEntity) && $itemEntity != $custVendEntity) {
                $msg = "The provided $custVendText ID '$custVendID' and $itemText ID $itemID are in different entities";
                $gErr->addIAError(
                    'INV-0718', __FILE__ . '.' . __LINE__,
                    $msg, ['CUST_VEND_TEXT' => $custVendText, 'CUST_VEND' => $custVendID, 'ITEM_TEXT' => $itemText, 'ITEMID' => $itemID]
                );
                return false;
            }
        }

        return $ok;
    }

    /**
     * @param string $action
     * @param array $renamedTextArray
     * @param array $values
     *
     * @return bool
     */
    function validateInternalValues($action, $renamedTextArray, &$values)
    {
        $gErr = Globals::$g->gErr;
        $itemText = $renamedTextArray['Item'];
        $vendorText = $renamedTextArray['Vendor'];
        $custText = $renamedTextArray['Customer'];
        $refType = $values['REFTYPE'];

        $ok = true;

        $lineMsg = '';
        if (isset($values['LINE_NO'])) {
            $lineno = $values['LINE_NO'];
            $lineMsg = $lineno >= 0 ? _("in line no : $lineno") : '';
        }

        if ($values['ALTERNATEITEMID'] == '') {
            $msg = "Provide a alternate $itemText ID when specifying a '$refType' reference type.";
            $gErr->addIAError('INV-0719', __FILE__ . '.' . __LINE__, $msg, ['ITEM_TEXT' => $itemText, 'REF_TYPE' => $refType]);
            return false;
        }

        if ($values['VENDORID'] != '') {
            $msg = "A $refType reference type does not accept a $vendorText ID.";
            $correction = "Remove the $vendorText ID, then try again";

            $gErr->addIAError(
                'INV-0720',
                __FILE__ . '.' . __LINE__,
                $msg, ['REF_TYPE' => $refType, 'VENDOR_TEXT' => $vendorText],
                '', [],
                $correction, ['VENDOR_TEXT' => $vendorText]
            );
            return false;
        }

        if ($values['CUSTOMERID'] != '') {
            $msg = "A $refType reference type does not accept a $custText ID.";
            $correction = "Remove the $custText ID, then try again";

            $gErr->addIAError(
                'INV-0721',
                __FILE__ . '.' . __LINE__,
                $msg, ['REF_TYPE' => $refType, 'CUST_TEXT' => $custText],
                '', [],
                $correction, ['CUST_TEXT' => $custText]
            );
            return false;
        }

        if ($values['ITEMALIASID'] != '') {
            $msg = "A $refType reference type does not accept $itemText cross reference ID.";
            $correction = "Remove the $itemText cross reference ID, then try again";

            $gErr->addIAError(
                'INV-0722',
                __FILE__ . '.' . __LINE__,
                $msg, ['REF_TYPE' => $refType, 'ITEM_TEXT' => $itemText],
                '', [],
                $correction, ['ITEM_TEXT' => $itemText]
            );
            return false;
        }

        if ($values['ITEMALIASDESC'] != '') {
            $msg = "A $refType reference type does not accept $itemText cross reference description.";
            $correction = "Remove the $itemText cross reference description, then try again";

            $gErr->addIAError(
                'INV-0723',
                __FILE__ . '.' . __LINE__,
                $msg, ['REF_TYPE' => $refType, 'ITEM_TEXT' => $itemText],
                '', [],
                $correction, ['ITEM_TEXT' => $itemText]
            );
            return false;
        }

        $alternateItemID = $values['ALTERNATEITEMID'];
        $itemID = $values['ITEMID'];

        // if $values['ITEMIDREST']  is set use it since with REST API ITEMIDREST will be set and for UI ITEMID not ITEMIDREST
        $alternateItemID = (!self::$fromAPI) && isset($values['ALTERNATEITEMIDREST']) && $values['ALTERNATEITEMIDREST'] !== '' ? $values['ALTERNATEITEMIDREST'] : $alternateItemID;
        $itemID = (!self::$fromAPI) && isset($values['ITEMIDREST']) && $values['ITEMIDREST'] !== '' ? $values['ITEMIDREST'] : $itemID;
        //
        // Get the line UOM Values for validation and passing it to PricingHandler to get the right converted quantity and value.
        if (!empty($values['UNIT'])) {
            // for REST some times the UOM key is changed or UOM ID can be changed so check for that
            $this->checkForUomChange($values);
            $unit = $values['UNIT'];
            $lineUOMValues = $this->_itemsUOMCache[$alternateItemID][$unit];
            // Added check if UNIT provided check if its valid and update UNITKEY
            if ((!isset($lineUOMValues) || count($lineUOMValues) == 0) && isset($values['UNITKEY'])) {
                $lineUOMValues = $this->prepUnitOfMeasureForREST($values, $alternateItemID);
            }
            if (!isset($lineUOMValues) || count($lineUOMValues) == 0) {
                $msg = "The provided unit '$unit' for alternate $itemText ID '$alternateItemID' is invalid";
                $correction = "Provide a valid unit and try again" . $lineMsg;

                $gErr->addIAError(
                    'INV-0724',
                    __FILE__ . ':' . __LINE__,
                    $msg, ['UNIT' => $unit, 'ITEM_TEXT' => $itemText, 'ALTERNATE_ITEM' => $alternateItemID],
                    '', [],
                    $correction, ['LINE_MSG' => $lineMsg]
                );
                return false;
            }
        }

        //
        // check if the given Alternate item ID exists
        if (!isset($this->_alternateItemsCache[$alternateItemID])) {
            $msg = "The provided alternate $itemText ID is invalid";
            $correction = "Provide a valid alternate $itemText ID, then try again.";
            $gErr->addIAError(
                'INV-0725',
                __FILE__ . '.' . __LINE__,
                $msg, ['ITEM_TEXT' => $itemText],
                '', [],
                $correction, ['ITEM_TEXT' => $itemText]
            );
            return false;
        }

        //
        // throw error if the item ID and Alternate item ID is same
        if($itemID == $alternateItemID) {
            $msg = "The provided values for $itemText ID and alternate $itemText ID are same";
            $correction = "Please provide different values and try again.";
            $gErr->addIAError(
                'INV-0726',
                __FILE__ . '.' . __LINE__,
                $msg, ['ITEM_TEXT' => $itemText],
                '', [],
                $correction, []
            );
            return false;
        }

        // throw error if the Alternate item ID is inactive
        // TBD

        // throw error if there is duplicate
        $res = $this->GetByReferenceType($refType,
            $itemID,
            '',
            '',
            '',
            $alternateItemID);
        //
        // check for any duplicates
        $throwDuplicateRecordError = false;
        if ($action == 'add') {
            //
            // make sure we passed correct parameters
            // here we are expecting only one row else throw excception
            if (count($res) > 0) {
                $throwDuplicateRecordError = true;
            }
        } else {
            //
            // make sure we passed correct parameters
            // here we are expecting only one row else throw excception
            if (count($res) > 0 && $res[0]['RECORDNO'] != $values['RECORDNO']) {
                $throwDuplicateRecordError = true;
            }
        }

        if($throwDuplicateRecordError) {
            $msg = "Alternate $itemText ID '$alternateItemID'";
            $msg .= " already exists for the reference type '$refType'" ;
            $msg .= " and $itemText '$itemID' combination.";

            $correction = "Enter a unique value for the alternate $itemText ID, then try again.";

            $gErr->addIAError(
                'INV-0727',
                __FILE__ . '.' . __LINE__,
                $msg, ['ITEM_TEXT' => $itemText, 'ALTERNATE_ITEM' => $alternateItemID, 'REF_TYPE' => $refType, 'ITEMID' => $itemID],
                '', [],
                $correction, ['ITEM_TEXT' => $itemText]
            );
            return false;
        }

        // throw error if hte item type of the item ID and the Alternate Item ID doesnt match
        // TBD

        $values['ALTERNATEITEMKEY'] = $this->_alternateItemsCache[$alternateItemID]['RECORDNO'];

        return $ok;
    }


    /**
     * @param $values
     * @param $itemID
     * @return void
     */
    private function prepUnitOfMeasureForREST(&$values, $itemID)
    {
        $returnUom = array();
        foreach ($this->_itemsUOMCache[$itemID] as $uom => $uomRecord) {
            if ($uomRecord['RECORD#'] === $values['UNITKEY']) {
                $values['UNIT'] = $uom;
                $returnUom = $this->_itemsUOMCache[$itemID][$uom];
                break;
            }
        }
        return $returnUom;

    }

    /**
     * @param $values
     * @return void
     */
    private function checkForUomChange(&$values)
    {
        if ($values['ia::operation'] === 'patch') {
            if ($values['UNIT'] !== $this->_oldValuesCache[$values['RECORDNO']]['UNIT']) {
                $values['UNITKEY'] = $values['UNIT'];
            } else if ($values['UNITKEY'] !== $this->_oldValuesCache[$values['RECORDNO']]['UNITKEY']) {
                $values['UNIT'] = $values['UNITKEY'];
            }
        }
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function validateOldValuesForUpdate($values)
    {
        $ok = true;
        $fldsToCompare = ['REFTYPE', 'ITEMID', 'VENDORID', 'CUSTOMERID'];

        //
        // $values is one/multiple Item cross reference records
        //
        foreach ($values as $itemCrossRefRec) {
            if (empty($itemCrossRefRec)) {
                continue;
            }

            $recNo = $itemCrossRefRec['RECORDNO'];
            $oldValues = $this->_oldValuesCache[$recNo];

            foreach ($fldsToCompare as $key) {
                /*
                 * Validate and Set if a restricted match is not found and not set
                 * Throw an error if a restriction is not matched but is being set
                 */
                $ok = $ok && $this->compareOldValues($itemCrossRefRec, $key, $oldValues);
            }

            unset($itemCrossRefRec);
        }

        return $ok;
    }

    /**
     * @param array $values
     * @param string $key
     * @param array $oldValues
     *
     * @return bool
     */
    private function compareOldValues($values, $key, $oldValues = array())
    {
        $ok = true;
        $fldInfo = $this->GetFieldInfo($key);
        $fieldName = $fldInfo['fullname'] != '' ? $fldInfo['fullname'] : $key;
        $fieldName = self::translateToken($fieldName);
        $itemText = self::translateToken(self::ITEM_TOKEN);

        if (!empty($oldValues)) {
            /*
             * While editing an item if a change is happenning
             * we have few fields that should not be allowed to change
             * as they might be one time selection
             *
             */
            $v = $values[$key] ?? '';
            $ov = $oldValues[$key] ?? '';
            if (($v != '') && ($ov != $v)) {
                Globals::$g->gErr->addIAError('INV-0728',
                    __FILE__ . '.' . __LINE__,
                    "You cannot modify the $fieldName for an $itemText cross reference",
                    ['FIELD_NAME' => $fieldName, 'ITEM_TEXT' => $itemText]
                );
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * @param string $action
     * @param array $itemCrossReferences
     *
     * @return bool
     */
    public function prepValues($action, &$itemCrossReferences)
    {
        $ok = true;
        $itemIDs = [];
        $custIDs = [];
        $vendIDs = [];
        $newEntries = [];
        $existingRecs = [];
        $alternateItemIDs = [];

        // collect customer, vendors, items, for validations
        foreach ($itemCrossReferences as $crossRef) {

            if (is_array($crossRef) && self::$fromAPI === false) {
                // Creating ITEMCROSSREFF using REST API will set VENDORIDREST or CUSTOMERIDREST not VENDORID and CUSTOMERID
                // setting the VENDORID and CUSTOMERID with VENDORIDREST or CUSTOMERIDREST
                $crossRef['CUSTOMERID'] = isset($crossRef['CUSTOMERIDREST']) && $crossRef['CUSTOMERIDREST'] !== '' ? $crossRef['CUSTOMERIDREST'] : $crossRef['CUSTOMERID'];
                $crossRef['VENDORID'] = isset($crossRef['VENDORIDREST']) && $crossRef['VENDORIDREST'] !== '' ? $crossRef['VENDORIDREST'] : $crossRef['VENDORID'];
                $crossRef['ITEMID'] = isset($crossRef['ITEMIDREST']) && $crossRef['ITEMIDREST'] !== '' ? $crossRef['ITEMIDREST'] : $crossRef['ITEMID'];
                $crossRef['ALTERNATEITEMID'] = isset($crossRef['ALTERNATEITEMIDREST']) && $crossRef['ALTERNATEITEMIDREST'] !== '' ? $crossRef['ALTERNATEITEMIDREST'] : $crossRef['ALTERNATEITEMID'];
            }
            $valueExists = "";

            if (isset($crossRef['RECORDNO']) && $crossRef['RECORDNO'] != '') {
                $existingRecs[] = $crossRef['RECORDNO'];
            }

            if (isset($crossRef['CUSTOMERID']) && $crossRef['CUSTOMERID'] != '') {
                list($custID) = explode('--', $crossRef['CUSTOMERID']);
                $custIDs[] = $custID;
                $valueExists .= $custID;
            }

            if (isset($crossRef['VENDORID']) && $crossRef['VENDORID'] != '') {
                list($vendID) = explode('--', $crossRef['VENDORID']);
                $vendIDs[] = $vendID;
                $valueExists .= $vendID;
            }

            if (isset($crossRef['ITEMID']) && $crossRef['ITEMID'] != '') {
                list($itemID) = explode('--', $crossRef['ITEMID']);
                $itemIDs[] = $itemID;
                $valueExists .= $itemID;
            }

            if (isset($crossRef['ALTERNATEITEMID']) && $crossRef['ALTERNATEITEMID'] != '') {
                list($alternateItemID) = explode('--', $crossRef['ALTERNATEITEMID']);
                $alternateItemIDs[] = $alternateItemID;
                $valueExists .= $alternateItemID;
            }

            if (isset($crossRef['ITEMALIASID']) && $crossRef['ITEMALIASID'] != '') {
                $valueExists .= $crossRef['ITEMALIASID'];
            }
            if (isset($crossRef['ITEMALIASDESC']) && $crossRef['ITEMALIASDESC'] != '') {
                $valueExists .= $crossRef['ITEMALIASDESC'];
            }

            if (strlen($valueExists) > 0) {
                $newEntries[] = $crossRef;
            }
        }

        $itemCrossReferences = $newEntries;

        $this->prepVendorCache($vendIDs);
        $this->prepCustomerCache($custIDs);
        $this->prepItemsCache($itemIDs);
        $this->prepAlternateItemsCache($alternateItemIDs);

        $allItems = array_merge($itemIDs, $alternateItemIDs);
        $this->prepItemsUOMCache($allItems);

        if ($action == 'set') {
            $this->prepOldValuesCache($existingRecs);
        }

        return $ok;
    }

    /**
     * @param array $vendorIDs
     */
    private function prepVendorCache($vendorIDs)
    {
        if (count($vendorIDs) > 0) {
            $vendormgr = Globals::$g->gManagerFactory->getManager('vendor');
            $queryparams = [
                'selects' => ['RECORDNO', 'VENDORID', 'LOCATIONKEY'],
                'filters' => [
                    [
                        ['CNY#', '=', GetMyCompany()],
                        ['VENDORID', 'IN', $vendorIDs],
                    ]
                ],
                'usemst' => true,
            ];

            $vendRecs = $vendormgr->GetList($queryparams);
            foreach ($vendRecs as $r) {
                $vendID = $r['VENDORID'];
                $this->_vendorCache[$vendID] = $r;
            }
        }
    }

    /**
     * @param array $customerIDs
     */
    private function prepCustomerCache($customerIDs)
    {
        if (count($customerIDs) > 0) {
            $vendormgr = Globals::$g->gManagerFactory->getManager('customer');
            $queryparams = [
                'selects' => ['RECORDNO', 'CUSTOMERID', 'LOCATIONKEY'],
                'filters' => [
                    [
                        ['CNY#', '=', GetMyCompany()],
                        ['CUSTOMERID', 'IN', $customerIDs],
                    ]
                ],
                'usemst' => true,
            ];

            $custRecs = $vendormgr->GetList($queryparams);
            foreach ($custRecs as $r) {
                $custID = $r['CUSTOMERID'];
                $this->_customerCache[$custID] = $r;
            }
        }
    }

    /**
     * @param array $itemIDs
     *
     * @return array
     */
    private function getItemsCache($itemIDs)
    {
        $itemRecs = [];
        if (count($itemIDs) > 0) {
            $itemMgr = Globals::$g->gManagerFactory->getManager('item');
            $queryparams = [
                'selects' => ['ITEMID', 'RECORDNO', 'ITEMTYPE', 'LOCATIONKEY'],
                'filters' => array(
                    array(
                        ['CNY#', '=', GetMyCompany()],
                        ['ITEMID', 'IN', $itemIDs],
                    )
                )
            ];

            $itemRecs = $itemMgr->GetList($queryparams);
        }

        return $itemRecs;
    }

    /**
     * @param array $itemIDs
     */
    private function prepItemsCache($itemIDs)
    {
        if (count($itemIDs) > 0) {
            $itemRecs = $this->getItemsCache($itemIDs);
            foreach ($itemRecs as $r) {
                $itemID = $r['ITEMID'];
                $this->_itemsCache[$itemID] = $r;
            }
        }
    }

    /**
     * @param array $alternateItemIDs
     */
    private function prepAlternateItemsCache($alternateItemIDs)
    {
        if (count($alternateItemIDs) > 0) {
            $itemRecs = $this->getItemsCache($alternateItemIDs);
            foreach ($itemRecs as $r) {
                $itemID = $r['ITEMID'];
                $this->_alternateItemsCache[$itemID] = $r;
            }
        }
    }

    /**
     * @param array $itemIDs
     */
    private function prepItemsUOMCache($itemIDs)
    {
        if (count($itemIDs) > 0) {
            $itemMgr = Globals::$g->gManagerFactory->getManager('item');

            $this->_itemsUOMCache = $itemMgr->GetUOMInfoCache($itemIDs, true);
        }
    }

    /**
     * @return array
     */
    protected function getSelectFieldList()
    {
        return [
            'RECORDNO',
            'REFTYPE',
            'ITEMID',
            'VENDORID',
            'CUSTOMERID',
            'REFTYPECONTEXT',
            'ALTERNATEITEMID',
            'ITEMKEY',
            'ITEMALIASID',
            'ITEMALIASDESC',
        ];
    }

    /**
     * @param array $existingRecs
     */
    private function prepOldValuesCache($existingRecs)
    {
        if (count($existingRecs) > 0) {
            foreach ($existingRecs as $rec) {

                if (isset($thjis->_oldValuesCache[$rec]) && is_array($this->_oldValuesCache[$rec])) {
                    continue;
                } else {
                    $this->_oldValuesCache[$rec] = $this->Get($rec);
                }
            }
        }

        if (count($existingRecs) > 0) {
            $selectFields = ['REFTYPE', 'ITEMID', 'VENDORID', 'CUSTOMERID', 'RECORDNO', 'UNIT'];
            if ($this->objVisibilityType === self::ITEM_CROSSREF) {
                $selectFields [] = 'UNITKEY';
            }
            $queryparams = [
                'selects' => $selectFields,
                'filters' => array(
                    array(
                        ['CNY#', '=', GetMyCompany()],
                        ['RECORDNO', 'IN', $existingRecs],
                    )
                )
            ];

            $existingRecs = $this->GetList($queryparams);
            foreach ($existingRecs as $rec) {
                $this->_oldValuesCache[$rec['RECORDNO']] = $rec;
            }
        }

    }

    /**
     * @param string $ID
     * @param string[] $fields
     *
     * @return array|bool
     */
    public function Get($ID, $fields = null)
    {
        $obj = parent::get($ID);

        if ($obj === false) {
            return false;
        }

        if (isl_strlen($obj['ITEMNAME']) > 0) {
            $obj['ITEMID'] .= '--' . $obj['ITEMNAME'];
        }

        if (isl_strlen($obj['ALTERNATEITEMNAME']) > 0) {
            $obj['ALTERNATEITEMID'] .= '--' . $obj['ALTERNATEITEMNAME'];
        }

        if ($obj['REFTYPE'] == 'Customer' && isl_strlen($obj['CUSTOMERNAME']) > 0) {
            $obj['CUSTOMERID'] .= '--' . $obj['CUSTOMERNAME'];
        } else if ($obj['REFTYPE'] == 'Vendor' && isl_strlen($obj['VENDORNAME']) > 0) {
            $obj['VENDORID'] .= '--' . $obj['VENDORNAME'];
        }

        return $obj;
    }

    /**
     * @param string $refType
     * @param string $itemID
     * @param string $customerID
     * @param string $vendorID
     * @param string $itemaliasid
     * @param string $alternateItemId
     *
     * @return array|array[]
     */
    public function GetByReferenceType($refType,
                                       $itemID = '',
                                       $customerID = '',
                                       $vendorID = '',
                                       $itemaliasid = '',
                                       $alternateItemId = '')
    {
        if (empty($refType)) {
            return [];
        }

        $filters[] = ['REFTYPE', '=', $refType];

        if (!empty($itemID)) {
            $filters[] = ['ITEMID', '=', $itemID];
        }

        switch (isl_strtolower($refType)) {
            case 'customer':
                if (!empty($customerID)) {
                    $filters[] = ['CUSTOMERID', '=', $customerID];
                }
                break;

            case 'vendor':
                if (!empty($vendorID)) {
                    $filters[] = ['VENDORID', '=', $vendorID];
                }
                break;

            case 'substitute':
            case 'upgrade':
            case 'downgrade':
            case 'complement':
                if (!empty($alternateItemId)) {
                    $filters[] = ['ALTERNATEITEMID', '=', $alternateItemId];
                }
                break;
        }

        if (!empty($itemaliasid)) {
            $filters[] = ['ITEMALIASID', '=', $itemaliasid];
        }

        $selectFields = $this->getSelectFieldList();
        $params = [
            'selects' => $selectFields,
            'filters' => [$filters],
        ];

        $res = $this->GetList($params);

        return $res;
    }

    /**
     * @param array $refTypes
     * @return int
     */
    public function hasItemCrossReferences($refTypes)
    {
        $recCount = 0;

        // refTypes is an array
        $filters = [];
        if (is_array($refTypes) && count($refTypes) > 0) {
            $filters[] = ['REFTYPE', 'IN', $refTypes];
        } else {
            $recCount = 0;
        }

        $params = [
            'selects' => ['COUNT(1)'],
            'columnaliases' => ['COUNT'],
            'filters' => [$filters],
        ];

        $res = $this->GetList($params);

        if (isset($res)) {
            $recCount = $res[0]['COUNT'];
        }

        return $recCount;
    }

    /**
     * Looks up a the vid of an object given its record number
     *
     * @param int $recordno is the record's number
     * @param bool $forceCheck True means don't assume if key is recordno that given value is valid - check it.
     *
     * @return string|null the record's vid
     */
    public function getVidFromRecordNo($recordno, $forceCheck = false)
    {
        return parent::GetVidFromRecordNo($recordno, true);
    }

    /**
     * @return bool
     */
    public function IsAuditEnabled()
    {
        return true;
    }

    /**
     * @param array $qparams
     *
     * @return string
     */
    public function FetchItemUOMInfo($qparams)
    {
        $itemMgr = Globals::$g->gManagerFactory->getManager('item');
        list($itemid) = explode('--', $qparams['itemid']);

        if (is_array($this->_uomInfoCache[$itemid])) {
            $uomInfo = $this->_uomInfoCache[$itemid];
        } else {
            $params['selects'] = array('UOMGRPKEY');
            $params['filters'] = array(array(array('ITEMID', '=', $itemid)));
            $itemUOM = $itemMgr->GetList($params);
            $uomgrpKey = $itemUOM[0]['UOMGRPKEY'];

            $uomMgr = Globals::$g->gManagerFactory->getManager('uom');
            $params['selects'] = array('UOMDETAIL.UNIT', 'POUOM', 'OEUOM');
            $params['filters'] = array(array(array('RECORDNO', '=', $uomgrpKey)));
            $uomInfo = $uomMgr->GetList($params);
            $this->_uomInfoCache[$itemid] = $uomInfo;
        }

        $pouom = '';
        $souom = '';
        $uomXMLstr = '';
        foreach ($uomInfo as $uom) {
            $uomXMLstr .= "<uom unit='" . htmlspecialchars($uom['UOMDETAIL.UNIT'], ENT_COMPAT) . "'></uom>";
            $pouom = $uom['POUOM'];
            $souom = $uom['OEUOM'];
        }

        $xmlStr = "<FetchItemUOMInfo>
                        <uomdetail
                        pouom=\"$pouom\" 
						oeuom=\"$souom\">
                        $uomXMLstr
                        </uomdetail>
                   </FetchItemUOMInfo>";

        return $xmlStr;
    }

    /**
     * @param array $qparams
     *
     * @return string
     */
    public function FetchItemCrossReferences($qparams)
    {
        list($itemid) = explode('--', $qparams['itemid']);
        // refTypes may be comma separated values
        $refTypes = explode(',', $qparams['refTypes']);
        $refTypeContext = $qparams['refTypeContext'];
        $warehouse = $qparams['warehouse'];

        $filters = [];
        if (!empty($itemid)) {
            $filters[] = ['ITEMID', '=', $itemid];
        }

        if (!empty($refTypeContext)) {
            $filters[] = ['REFTYPECONTEXT', '=', $refTypeContext];
        }

        // refTypes is an array
        if (is_array($refTypes) && count($refTypes) > 0) {
            $filters[] = ['REFTYPE', 'IN', $refTypes];
        }

        $params = [
            'selects' => ['RECORDNO',
                'REFTYPE', 'REFTYPECONTEXT',
                'ITEMID', 'ITEMKEY',
                'ALTERNATEITEMID', 'ALTERNATEITEMKEY',
                'UNIT'],
            'filters' => [$filters],
        ];

        $res = $this->GetList($params);

        $qtyDenseArray = $this->getItemTotals($res, $warehouse);

        $crossRefItems = "";
        foreach ($res as $rec) {
            $itemWhseKey = $rec['ALTERNATEITEMID'] . "--" . $warehouse;
            $qtyonhand = $qtyDenseArray[$itemWhseKey]['onhandqty'];
            // build string
            $crossRefItems .= "<crossrefitem ";
            $crossRefItems .= " reftype='" . htmlspecialchars($rec['REFTYPE'], ENT_COMPAT) . "'";
            $crossRefItems .= " reftypecontext='" . htmlspecialchars($rec['REFTYPECONTEXT'], ENT_COMPAT) . "'";
            $crossRefItems .= " itemid='" . htmlspecialchars($rec['ITEMID'], ENT_COMPAT) . "'";
            $crossRefItems .= " itemkey='" . htmlspecialchars($rec['ITEMKEY'], ENT_COMPAT) . "'";
            $crossRefItems .= " alternateitemid='" . htmlspecialchars($rec['ALTERNATEITEMID'], ENT_COMPAT) . "'";
            $crossRefItems .= " alternateitemkey='" . htmlspecialchars($rec['ALTERNATEITEMKEY'], ENT_COMPAT) . "'";
            $crossRefItems .= " onhandqty='" . htmlspecialchars($qtyonhand, ENT_COMPAT) . "'";
            $crossRefItems .= " unit='" . htmlspecialchars($rec['UNIT'], ENT_COMPAT) . "'";
            $crossRefItems .= " > </crossrefitem>";
        }

        $xmlStr = "<FetchItemCrossReferences>$crossRefItems</FetchItemCrossReferences>";

        return $xmlStr;
    }

    /**
     * @param array  $res
     * @param string $warehouse
     *
     * @return array
     */
    private function getItemTotals($res, $warehouse)
    {
        $alternateItemIds = [];
        $itemWhsePair = [];
        $qtyDenseArray = [];

        foreach ($res as $rec) {
            $alternateItemIds[] = $rec['ALTERNATEITEMID'];
            $itemWhsePair[] = $rec['ALTERNATEITEMID'] . "--" . $warehouse;
        }

        if (empty($alternateItemIds) || empty($warehouse)) {
            return $qtyDenseArray;
        }

        $qry = [];
        $qry[] = "select icitemtotals.itemkey, icitemtotals.warehousekey,
                            sum(nvl(icitemtotals.posquantity,0) + nvl(icitemtotals.negquantity,0)) as onhandqty 
                        from icitemtotals, ictotal 
                        where icitemtotals.cny#= :1 
                        and ictotal.cny#= :1 
                        and icitemtotals.warehousekey = :2
                        and ictotal.name = 'ONHAND'
                        and icitemtotals.totalkey = ictotal.record#
                    ";
        $qry[] = GetMyCompany();
        $qry[] = $warehouse;
        $qry = PrepINClauseStmt($qry, $alternateItemIds, " and icitemtotals.itemkey ");
        $qry[0] .= " group by icitemtotals.itemkey, icitemtotals.warehousekey ";

        $result = QueryResult($qry);

        if ($result !== false) {
            foreach ($result as $value) {
                $trimmedValues = array();
                foreach ($value as $trimKey => $trimValue) {
                    $trimmedValues[isl_strtolower($trimKey)] = $trimValue;
                }
                $keyIndx = $value['ITEMKEY'] . "--" . $value["WAREHOUSEKEY"];
                $qtyDenseArray[$keyIndx] = $trimmedValues;
            }
        }

        foreach ($itemWhsePair as $keys) {
            $denseArray = [];
            $itemWhseArr = explode('--', $keys);
            if (empty($qtyDenseArray[$keys])) {
                $denseArray['itemkey'] = $itemWhseArr[0];
                $denseArray['onhandqty'] = "0";
                $denseArray['warehousekey'] = $itemWhseArr[1];
                $qtyDenseArray[$keys] = $denseArray;
            }
        }

        return $qtyDenseArray;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function API_Add(&$values)
    {
        self::$fromAPI = true;
        $ret = parent::API_Add($values);

        // as we support bulk insert we process all the records at once like prepvalues, validatevalues etc.
        // so even if its a singe record it comes in form of multi dimentional array
        // after create we have to return the single record not the array of record
        if (is_array($values[0]) && count($values) == 1) {
            $values = $values[0];
        }

        return $ret;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function API_Set(&$values)
    {
        self::$fromAPI = true;
        $ret = parent::API_Set($values);

        // as we support bulk insert we process all the records at once like prepvalues, validatevalues etc.
        // so even if its a singe record it comes in form of multi dimentional array
        // after set we have to return the single record not the array of record
        if (is_array($values[0]) && count($values) == 1) {
            $values = $values[0];
        }

        return $ret;
    }

    /**
     * @param string $referenceType
     * @param string $itemID
     * @param array $renamedTextArray
     * @return bool
     */
    private function restrictedItemTypeValidation($referenceType, $itemID, $renamedTextArray)
    {

        if (!empty($referenceType) && ($referenceType == 'Vendor' || $referenceType == 'Customer')) {

            $refText = $renamedTextArray['Customer'];

            $isRestrictedItemType = ($this->_itemsCache[$itemID]['ITEMTYPE'] == 'Non-Inventory (Purchase only)');
            if ($referenceType == 'Vendor') {
                $isRestrictedItemType = ($this->_itemsCache[$itemID]['ITEMTYPE'] == 'Kit'
                    || $this->_itemsCache[$itemID]['ITEMTYPE'] == 'Non-Inventory (Sales only)');
                $refText = $renamedTextArray['Vendor'];
            }

            if ($isRestrictedItemType) {
                $gErr = Globals::$g->gErr;
                $itemtype = $this->_itemsCache[$itemID]['ITEMTYPE'];
                $correction = "Because the item type is '$itemtype',
                either select a reference type other than $refText or select a different Item ID.
                Then, try again";

                $gErr->addIAError('INV-0729',
                    __FILE__ . '.' . __LINE__,
                    '', [],
                    '', [],
                    $correction, ['ITEMTYPE' => $itemtype, 'REF_TEXT' => $refText]
                );
                return false;
            }
        }

        return true;
    }
    /**
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

        $icrSyncValues = $values;

        if ($verb == 'Delete') {
            $this->deleteChatter($key);
            if ($this->isDigitalNetworkSyncEnabled) {
                $params = array(
                    'selects' => array('RECORDNO', 'REFTYPE', 'ITEMALIASID', 'ITEMID', 'VENDORID'),
                    'filters' => array(
                        array(
                            array('RECORDNO', '=', $key),
                        )
                    ),
                );
                $icrData = $this->GetList($params);
                if (Util::countOrZero($icrData) > 0) {
                    $icrSyncValues = $icrData[0];
                }
            }
        }

        if ($this->isDigitalNetworkSyncEnabled
            && Util::countOrZero($icrSyncValues) > 0
            && $icrSyncValues['REFTYPE'] == 'Vendor') {
            $this->doDNSyncEvent('itemcrossref', $verb, $key, $param1, $param2, $icrSyncValues);
        }

        $subscription = Globals::$g->gManagerFactory->getManager('imssubscription');
        $subscription->FillSubscriptions($verb, 'itemcrossref', $key);
        $this->doAuditEvent($verb, $key);
        return true;
    }

    /**
     * @return false
     */
    protected function isDNSyncEnabled()
    {
        return true;
    }

    /**
     * @return string
     */
    protected function getDNSyncQueueEntity(): string
    {
        return 'podigitalnetworksyncqueue';
    }

}

