<?php

/**
 * Parent class for all the Transaction Definition editors implementation
 * (Inventory, Purchasing, Order Entry).
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */
class DocumentParamsEditor extends FormEditor
{


    const GENERIC_DOC_SAVE_ERROR = 'BL0100001';
    const GENERIC_DOC_CRE_ERROR = 'BL0100002';
    const GENERIC_DOC_GL_ERROR = 'BL0100003';
    const GENERIC_DOC_LINE_ITEM_ERROR = 'BL0100004';
    const GENERIC_DOC_REV_REC_ERROR = 'BL0100005';
    const GENERIC_DOC_RENEWALS_ERROR = 'BL0100006';
    const GENERIC_DOC_ONHAND_ERROR = 'BL0100007';
    const GENERIC_DOC_SUBTOTALS_ERROR = 'BL0100008';
    const GENERIC_DOC_LINECONVERSION_ERROR = 'BL0100010';
    const GENERIC_DOC_ALLOC_ERROR = 'BL01000011';
    const GENERIC_DOC_DROPSHIP_ERROR = 'BL0100012';
    const GENERIC_DOC_LANDEDCOSTS_ERROR = 'BL01000013';
    const GENERIC_DOC_RECALLS_ERROR = 'BL0100014';
    const GENERIC_DOC_APPROVALS_ERROR = 'BL0100015';
    const GENERIC_DOC_VARIANCE_ERROR = 'BL0100016';
    const GENERIC_DOC_DECIMAL_ERROR = 'BL0100017';
    const GENERIC_DOC_CONVHANDLING_ERROR = 'BL0100018';
    const GENERIC_DOC_INV_LANDEDCOSTS_ERROR = 'BL0100019';
    const GENERIC_DOC_SO_DROPSHIP_ERROR = 'BL0100020';

    /**
     * @param array $_params
     */
    public function __construct($_params = array())
    {
        parent::__construct($_params);
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.TRANSACTION_DEFINITION_FOR';
        $this->textTokens[] = 'IA.ONCHANGE_SUBTOTAL_TEMPLATE_CONFIRM_MESSAGE';
        $this->textTokens[] = 'IA.DOCUMENT_POSTING_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.TRANSACTION_POSTING_GL_ACCOUNT_MAPPIN';
        $this->textTokens[] = 'IA.TRANSACTION_POSTING_AR_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.TRANSACTION_POSTING_AP_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.TOP_LEVEL';
        $this->textTokens[] = 'IA.ENTITY';
        $this->textTokens[] = 'IA.TOP_LEVEL_OR_ENTITY';
        $this->textTokens[] = 'IA.TOP_LEVEL_ONLY';
        $this->textTokens[] = 'IA.ENTITY_ONLY';
        $this->textTokens[] = 'IA.GET_GLPOSTING_HELP_TEXT';
        $this->textTokens[] = 'IA.GET_COGS_GLENTRY_ERROR_MESSAGE';
        $this->textTokens[] = 'IA.COGS_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.INVENTORY_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.ADDITIONAL_GLENTRY_ERROR_MESSAGE';
        $this->textTokens[] = 'IA.ADDITIONAL_GL_POSTING_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.SET_TRNSACTION_POSTING_HELP_TEXT';
        $this->textTokens[] = 'IA.VALIDATE_REV_REC_SELECTION_ERROR_MESSAGE';
        $this->textTokens[] = 'IA.ENABLE_INV_ITEMS_FOR_RESERVING_PICKING_OPTIONS_ALERT_MESSAGE';
        $this->textTokens[] = 'IA.ENABLE_INV_ITEMS_FOR_RESERVING_PICKING_ONLY_ONHOLD_INCREASE_ALERT_MESSAGE';
        $this->textTokens[] = 'IA.ENABLE_FOR_FULFILLMENT_SET_TEMPLATE_TYPE_AND_WORKFLOW_CATEGORY_ALERT_MESSAGE';
        $this->textTokens[] = 'IA.GET_GL_POSTING_HELP_TEXT';
        $this->textTokens[] = 'IA.FOR_WORKFLOW_TYPE_ORDER_TOTALS_ONHAND_NEED_TO_INCREASE';
        $this->textTokens[] = 'IA.FOR_WORKFLOW_TYPE_INVOICE_TOTALS_ONHAND_NEED_TO_DECREASE';
        $this->textTokens[] = 'IA.FOR_WORKFLOW_TYPE_SHIPPING_TOTALS_EITHER_INCREASE_ONHOLD_OR_DECREASE_ONHAND';
        $this->textTokens[] = 'IA.TRANSACTION_POSTING_AR_ACCOUNT_MAPPING';
        $this->textTokens[] = 'IA.TRX_DEFINITION_IS_EXPECTED_SUBTOTALS_SPECIFY_INFORMATION_ON_TRANSACTION_SUBTOTALS_SECTION';
        $this->textTokens[] = 'IA.DUPLICATE_SUBTOTAL_DESCRIPTION_FOUND_ON_LINE_NUMBER';
        $this->textTokens[] = 'IA.LINE_LEVEL_SIMPLE_TAX_ENABLED_TAXES_CANT_BE_FLAT_AMOUNT';
        $this->textTokens[] = 'IA.UNSUPPORTED_TRANSACTION_POSTING';
        $this->textTokens[] = 'IA.TRANSACTION_DEFINITION_POST_AFFECTED_JOURNAL_ATLEAST_ONE_DEBIT_OR_CREDIT_AMOUNT_PAIR';
        $this->textTokens[] = 'IA.IF_PARTIAL_CONVERSION_HANDLING_SET_BACKORDER_YOU_CANNOT_ENABLE_PROJECT_CONTRACT_BILLING';
        $this->textTokens[] = 'IA.PROJECT_CONTRACT_BILLING_BLOCKS_YOUR_ABILITY_TO_CREATE_BACKORDER';
        $this->textTokens[] = 'IA.CONTRACT_BILLING_NOT_SUPPORTED_WHEN_RENEWALS_FEATURE_ENABLED';
        $this->textTokens[] = 'IA.RENEWALS_FEATURE_IS_NOT_SUPPORTED_WHEN_CONTRACT_BILLING_ENABLED';
        $this->textTokens[] = 'IA.PROJECT_CONTRACT_BILLING_CANNOT_ENABLED_WITH_LINE_ITEM_CONVERSION_OR_REVENUE_RECOGNITION';
        $this->textTokens[] = 'IA.PROJECT_CONTRACT_BILLING_ENABLED_CANNOT_CONVERT_LINE_ITEMS_OR_RECOGNIZE_REVENUE';
        $this->textTokens[] = 'IA.PLEASE_GRANT_PERMISSIONS_ATLEAST_ONE_USER_ON_SECURITY_CONFIGURATION_TAB';
        $this->textTokens[] = 'IA.REQUIRED_FIELD_MAINTAIN_MISSING_INVENTORY_CONTROL_TABLE';
        $this->textTokens[] = 'IA.REQUIRED_FIELD_ADD_OR_SUBTRACT_MISSING_INVENTORY_CONTROL_TABLE';
        $this->textTokens[] = 'IA.DUPLICATE_INVENTORY_TOTAL_FOUND_ON_LINE_NUMBER';
        $this->textTokens[] = 'IA.INCONSISTENCY_IS_VERIFIED_FOR_ONHAND_SECTION_ONLY_ERROR_MESSAGE';
        $this->textTokens[] = 'IA.SHOULD_ATLEAST_ONE_CREDIT_AND_DEBIT_ACCOUNT_DEFINED_COGS_ERROR_MESSAGE';
        $this->textTokens[] = 'IA.NO_ACCOUNT_MARKED_AS_OPERATION_FOUND_IN_GRID_TABLE';
        $this->textTokens[] = 'IA.THIS_WILL_RESET_ALL_COLUMN_VALUE_ZERO_YOU_WANT_TO_CONTINUE';
        $this->textTokens[] = 'IA.FOR_FULFILLMENT_CANNOT_HAVE_BOTH_ONHAND_ONHOLD_ONLY_ONHOLD';
        $this->textTokens[] = 'IA.FOR_FULFILLMENT_CANNOT_HAVE_BOTH_ONHAND_ONHOLD_ONLY_ONHAND';
        $this->textTokens[] = 'IA.FOR_FULFILLMENT_CANNOT_HAVE_BOTH_ONHAND_ONHOLD_ONE_OR_OTHER';
        $this->textTokens[] = 'IA.DUPLICATE_ENTITY_FOUND_ON_LINENO_FOR_ENTITY_SETTINGS';
        $this->textTokens[] = 'IA.UNSUPPORTED_ENTITY';
        $this->textTokens[] = 'IA.DONOT_POST';
        $this->textTokens[] = 'IA.SELECT_GL_ACCOUNT_FOR_SUBTOTAL_TRY_AGAIN';
        $this->textTokens[] = 'IA.SUBTOTAL_NOT_APPORTIONED_REQUIRES_GL_ACCOUNT';
        $this->textTokens[] = 'IA.IS_TAX_AND_AVALARA_BOTH_CHECKED_OR_UNCHECKED';
        $this->textTokens[] = 'IA.IS_TAX';
        $this->textTokens[] = 'IA.SELECT_FOR_AVALARA';
        $this->textTokens[] = 'IA.TAXABLE_TRANSACTIONS_MAY_NOT_POST_DIRECTLY_TO_GENERAL_LEDGER';
        $this->textTokens[] = 'IA.YOU_MAY_NOT_USE_AVALARA_WITH_VAT_ENABLED';
        $this->textTokens[] = 'IA.AVALARA';
        $this->textTokens[] = 'IA.VAT';
        $this->textTokens[] = 'IA.MEA_ALLOCATION_CHARGE_SUBTOTAL_MAY_NOT_BE_APPORTIONED';
        $this->textTokens[] = 'IA.MEA_ALLOCATIONS';
        $this->textTokens[] = 'IA.CHARGE';
        $this->textTokens[] = 'IA.MEA_ALLOCATION_DISCOUNT_SUBTOTAL_MUST_BE_APPORTIONED';
        $this->textTokens[] = 'IA.DISCOUNT';
        $this->textTokens[] = 'IA.REQUIRED_FIELD_MISSING';
        $this->textTokens[] = 'IA.NUMBERING_SEQUENCE';
        $this->textTokens[] = 'IA.REQUIRED_FIELD_IS_NOT_PROVIDED';
        $this->textTokens[] = 'IA.CONTACT_TITLE';
        $this->textTokens[] = 'IA.RETAINAGE_IS_NOT_SUPPORTED_LINE_ITEM_CONVERSION';
        $this->textTokens[] = 'IA.RETAINAGE_IS_NOT_SUPPORTED_RENEWALS';
        $this->textTokens[] = 'IA.RETAINAGE_IS_NOT_SUPPORTED_FOR_PARTIAL';
        $this->textTokens[] = 'IA.RETAINAGE_IS_NOT_SUPPORTED_FOR_SIMPLIFIED_INVENTORY';
        $this->textTokens[] = 'IA.RETAINAGE_CAN_NOT_BE_ENABLED_FOR_RETURN';
        return parent::getFormTokens();
    }

    /**
     * Specifies an array of javascript files that will be included into the page.
     *
     * @return array the list of javascript files
     */
    protected function getJavaScriptFileNames()
    {
        return array(
            '../resources/js/documentparams.js'
        );
    }

    /**
     * Specifies an array of CSS files that will be included into the page.
     *
     * @return array the array of CSS files.
     */
    protected function getCssFileNames()
    {
        $cssfiles[] = "../resources/css/documentparams.css";
        return $cssfiles;

    }

    /**
     * Specified the name of the form configuration file that is using for
     * rendering the page.
     *
     * @param array $params
     *
     * @return string form configuration file name
     */
    protected function getMetadataKeyName(&$params)
    {
        $entity = $params['entity'];
        $metadataFileName = "${entity}_adv_form.pxml";
        /*
        // There is no need for a different form.xml for the standard
        // setup. Both standard and advanced setups are covered by the
        // single form.xml file.
        $metadataFileName = "${entity}_form.pxml";
        $advancedConfiguration = IsAdvancedConfiguration();
        if ($advancedConfiguration) {
            $metadataFileName = "${entity}_adv_form.pxml";
        }
        */
        return $metadataFileName;
    }

    /**
     * Initialize the User Permissions Tab
     *
     * @param array $obj
     */
    private function initPermissions(&$obj)
    {
        $docParMgr = Globals::$g->gManagerFactory->getManager('documentparams');
        $docParMgr->initPermissions($obj);

        $view = $this->getView();
        $view->findAndSetProperty(
            array('path' => 'ALLOWACCESS'), array('hidden' => true)
        );
        if (Request::$r->_state == "showview") {
            $view->findAndSetProperty(
                array('path' => 'ALLOWACCESS'), array('hidden' => true)
            );
            $view->findAndSetProperty(
                array('id' => 'USERGROUP_section'), array('hidden' => true),
                EditorComponentFactory::TYPE_SECTION
            );
        }
    }

    /**
     * @param array $obj
     */
    private function setSubtotalsVisibility(& $obj)
    {
        $view = $this->getView();

        $visibility = 'true' === $obj['SHOW_TOTALS'];

        $view->findAndSetProperty(
            array('path' => 'DOCPAR_SUBTOTAL'), array('hidden' => !$visibility),
            EditorComponentFactory::TYPE_GRID
        );
        $view->findAndSetProperty(
            array('path' => 'SHOWEXPANDEDTOTALS'), array('hidden' => !$visibility),
            EditorComponentFactory::TYPE_FIELD
        );
        $view->findAndSetProperty(
            array('path' => 'ENABLEOVERRIDETAX'), array('disabled' => !$visibility),
            EditorComponentFactory::TYPE_FIELD
        );

        $view->findAndSetProperty(
            array('path' => 'SUBTOTALTEMPLATE'), array('hidden' => !$visibility),
            EditorComponentFactory::TYPE_FIELD
        );
        $view->findAndSetProperty(
            array('path' => 'LINELEVELSIMPLETAX'), array('disabled' => !$visibility),
            EditorComponentFactory::TYPE_FIELD
        );
    }

    /**
     * Method verifies if the Inventory modules are NOT Subscribed
     * and disables proper widgets on the page related to inventory.
     *
     */
    private function setInventoryControlSectionVisibility()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $modMgr = $gManagerFactory->getManager('modules');
        $moduleSupported = $modMgr->isModuleSubscribed("7.INV");
        if (!$moduleSupported) {
            $view = $this->getView();
            $view->findAndSetProperty(
                array('id' => 'inventory_control_section'),
                array('hidden' => true),
                EditorComponentFactory::TYPE_SECTION
            );
        }
    }

    /**
     * Enables / disables sequence and preserve_seqnum fields depending upon
     * status of the enable_seqnum check box.
     *
     * @param array $obj
     */
    protected function setSeqnumAvailability(&$obj) 
    {
        $view = $this->getView();
        $isEnabled = isset($obj['SEQUENCE']) && '' !== $obj['SEQUENCE'];
        $view->findAndSetProperty(
            array('path' => 'PRESERVE_SEQNUM'),
            array('disabled' => !$isEnabled),
            EditorComponentFactory::TYPE_FIELD
        );
    }

    /**
     * For the Root company hide certain fields and columns on different grids.
     *
     * @param array $obj
     */
    private function hideNonRootFields(/** @noinspection PhpUnusedParameterInspection */ &$obj)
    {
        $view = $this->getView();
        $fieldsToHide = array(
            array('path' => 'LOCOVERRIDE', 'fieldType' => EditorComponentFactory::TYPE_FIELD),
            array('path' => 'DEPTOVERRIDE', 'fieldType' => EditorComponentFactory::TYPE_FIELD),
            array('path' => 'LOCATION', 'fieldType' => EditorComponentFactory::TYPE_GRID_COLUMN),
            array('path' => 'DEPARTMENT', 'fieldType' => EditorComponentFactory::TYPE_GRID_COLUMN),
            array('path' => 'DEPT', 'fieldType' => EditorComponentFactory::TYPE_GRID_COLUMN),
        );
        foreach($fieldsToHide as $field) {
            $view->findAndSetProperty(
                array('path' => $field['path']),
                array('hidden' => true),
                $field['fieldType']
            );
        }

        $this->handleSubtotalLocationDepartment();

    }

    /**
     * at top level (root)
     * and if the company is migrated from standard to MEGA
     */
    private function handleSubtotalLocationDepartment()
    {
        $view = $this->getView();

        $moduleMap = ['invdocumentparams' => 'inv',
            'sodocumentparams' => 'so',
            'podocumentparams' => 'po'];

        $module = $moduleMap[$view->params["entity"]];
        $docparsubtotalsMgr = Globals::$g->gManagerFactory->getManager($module . 'documentparsubtotal');

        if ($docparsubtotalsMgr->_overrideLocDeptAtTopLevel
            && $docparsubtotalsMgr->_overrideDimensionsFromSubtotals) {
            $fieldsToHide = [
                ['path' => 'LOCATION', 'fieldType' => EditorComponentFactory::TYPE_GRID_COLUMN],
                // the followingis only in subtotals grid
                ['path' => 'DEPARTMENT', 'fieldType' => EditorComponentFactory::TYPE_GRID_COLUMN],
                // the following is in posting configuration grids
                ['path' => 'DEPT', 'fieldType' => EditorComponentFactory::TYPE_GRID_COLUMN],
            ];

            foreach ($fieldsToHide as $field) {
                $view->findAndSetProperty(
                    ['path' => $field['path']],
                    ['hidden' => false],
                    $field['fieldType']
                );
            }
        }
    }

    /**
     * Alter the fields if the company has the multi currency processing
     * enabled.
     *
     * @param array $obj
     */
    private function setMcpDependentFields(&$obj) 
    {
        global $gManagerFactory;
        $view = $this->getView();

        self::findElements(
            $view->params['child'], array('path' => 'EXCHRATETYPES.NAME'),
            null, $exchfields
        );
        self::findElements(
            $view->params['child'],
            array('path' => 'OVERRIDE_EXCH_RATE_TYPE'), null, $exchfields
        );
        self::findElements(
            $view->params['child'], array('path' => 'DISPLAY_BASECURRENCY'),
            null, $exchfields
        );

        foreach ($exchfields as $i => $field) {
            if ($field['path'] == 'EXCHRATETYPES.NAME'
                && $field['value'] == ''
                && $this->state == 'shownew'
            ) {
                $exchMgr = $gManagerFactory->getManager('exchangeratetypes');
                $rtype = $exchMgr->GetDefaultExchangeRateType();
                $obj['EXCHRATETYPES']['NAME'] = $rtype[0]['NAME'];
            }
            $exchfields[$i]['hidden'] = false;
        }
    }

    /**
     * Enable / disable default warehouse based upon its value. It is
     * disabled if there is no or black value.
     *
     * @param array $obj
     */
    private function setDefaultWarehouseAvailability(&$obj) 
    {
        $view = $this->getView();
        $view->findAndSetProperty(
            array('path' => 'DEFAULT_WAREHOUSE'),
            array('disabled' => (!isset($obj['DEFAULT_WAREHOUSE']) || '' === $obj['DEFAULT_WAREHOUSE'])),
            EditorComponentFactory::TYPE_FIELD
        );
    }


    /**
     * Enable / disable AllowCustVendEdit based on Edit Policy.
     * It will be disabled if Edit Policy is set as 'No Edit'
     *
     * @param array $obj
     */
    private function setAllowCustVendEdit(&$obj)
    {
        if($obj['EDITTYPE'] == 'No Edit'){
            $view = $this->getView();
            $view->findAndSetProperty(
                array('path' => 'ALLOWEDITCUSTVEND'),
                array('disabled' => 'true'),
                EditorComponentFactory::TYPE_FIELD
            );
        }
    }


    /**
     * Overwrites the entity and pick entity fields of the Transaction
     * Conversion pick list to show only the appropriate entities.
     */
    private function configureTransactionConversionPicklist() 
    {
        $view = $this->getView();
        $matches = [];
        self::findElements(
            $view->params['child'], array('path' => 'RECDOCPAR'), null,
            $matches
        );
        foreach ( $matches as $k => $field2) {
            $matches[$k]['type']['entity'] = $view->params["entity"];
            $matches[$k]['type']['pickentity'] = $view->params["entity"];
        }
    }

    /**
     * Overwrites the GL Group entity pick list as follows:
     * - SO TD - show customers
     * - PO TD - show vendors
     * - INV TD - irrelevant.
     */
    private function configureGlgroupEntityPicklist() 
    {
        $view = $this->getView();
        $glGroupMap = array(
            'sodocumentparams' => 'custglgroup',
            'podocumentparams' => 'vendglgroup'
        );
        $matches = [];
        self::findElements(
            $view->params['child'], array('path' => 'ENT_GLGROUP'), null,
            $matches
        );
        foreach ( $matches as $key => $field) {
            $matches[$key]['type']['entity'] = $glGroupMap[$view->params["entity"]];
            $matches[$key]['type']['pickentity'] = $glGroupMap[$view->params["entity"]];
            $matches[$key]['listAllowed'] = "true";
            $matches[$key]['ptrViewAllowed'] = "true";
            $matches[$key]['createAllowed'] = "true";
        }
    }


    /**
     * Interceptor function to adjust the metadata according to the object's
     * state. The data is available to access throug the view as follows:
     *     <code>$view = $this->getView()</code>
     *
     * @param array $obj the data
     *
     * @return bool true if the data is altered successfully and false
     *              otherwise.
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        global $gManagerFactory;

        $view = $this->getView();

        $this->configureTransactionConversionPicklist();

        $this->configureGlgroupEntityPicklist();

        $isRoot = IsMultiEntityCompany() && (!GetContextLocation());
        if ($isRoot) {
            $this->hideNonRootFields($obj);
        }

        // correct the printed format
        $this->correctPrintedFormat($obj);

        if (IsMCPEnabled(Request::$r->_mod)) {
            // alter data for the company with multi currency processing enabled.
            $this->setMcpDependentFields($obj);
        }

        // The transaction posting must render the label in view mode and the
        // value otherwise
        $this->correctTransactionPosting($obj);

        // For the view mode limit the subtotal values to 2 decimal places.
        $this->correctSubtotalsForView($obj);
        if (isset($obj['LINELEVELSIMPLETAX'])) {
            $kModArray = array('so' => Globals::$g->kSOid, 'po' => Globals::$g->kPOid);
            $module = Request::$r->_mod;
            $isTaxScheduleEnabled = GetPreferenceForProperty($kModArray[$module], 'TAXSCHED');
            $view->findAndSetProperty(
                array('path' => 'LINELEVELSIMPLETAX'),
                array('hidden' => ($obj['SHOW_TOTALS'] == 'true' && $isTaxScheduleEnabled == 'F') ? false : true),
                EditorComponentFactory::TYPE_FIELD
            );
            if ($isTaxScheduleEnabled == 'T') {
                $view->findAndSetProperty(
                    array('path' => 'LINELEVELSIMPLETAX'),
                    array('readonly' => true),
                    EditorComponentFactory::TYPE_FIELD
                );
            }
            if ($obj['LINELEVELSIMPLETAX'] == 'true') {
                $view->findComponents(array('path' => 'BASELINE'), EditorComponentFactory::TYPE_GRID, $applyToLineFields);
                /* @var EditorComponent[] $applyToLineFields */
                foreach ($applyToLineFields as $key => $field) {
                    $applyToLineFields[$key]->setProperty('hidden', true);
                }
            }
        }

        if ('shownew' !== $this->state) {
            // for a new TD disable the DOCID field
            $view->findAndSetProperty(
                array('path' => 'DOCID'), array('readonly' => true),
                EditorComponentFactory::TYPE_FIELD
            );

            $view->findAndSetProperty(
                array('path' => 'SHOWTITLE1'), array('value' => 'false'),
                EditorComponentFactory::TYPE_FIELD
            );

            $view->findAndSetProperty(
                array('path' => 'SHOWTITLE2'), array('value' => 'true'),
                EditorComponentFactory::TYPE_FIELD
            );

            $titleTxtToken = [
                [
                    'id' => 'IA.TRANSACTION_DEFINITION_FOR',
                    'placeHolders' => [
                        ['name' => 'DOCID', 'value' => $obj['DOCID']]
                    ]
                ]
            ];
            $tokenText = I18N::getTokensForArray($titleTxtToken);
            $titleText = GT($tokenText, 'IA.TRANSACTION_DEFINITION_FOR');
            $this->setTitle($titleText);
        }
        if ($this->state == $this->kShowViewState || !$isRoot) {
            $view->findAndSetProperty(
                array('path' => 'POPULATEENTITIES'), array('hidden' => 'true'),
                EditorComponentFactory::TYPE_BUTTONS
            );
        }
        // enable / disable enable_seqnum dependent fields
        $this->setSeqnumAvailability($obj);

        // Disable inventory controls if inventory modules are not subscribed
        $this->setInventoryControlSectionVisibility();

        // Show / hide grid and expanded subtotals check box
        $this->setSubtotalsVisibility($obj);

        // Initialize permissions
        $this->initPermissions($obj);

        // Enable / disable default warehouse based upon its value
        $this->setDefaultWarehouseAvailability($obj);

        //disable AllowCustVendEdit based on Edit Policy
        $this->setAllowCustVendEdit($obj);

        // Show / hide user permission details visibility
        $this->setUserpermDetailsVisibility($obj);

        // show / hide Entity Settings tab depend upon selected root / entity
        $this->configureEntityPropertiesGrid($obj);

        // hides the Creation rule drop down list box is logged in to entity
        $this->setCreationRuleVisibility($obj);

        $this->restrictUsergroupCreation($obj);

        $this->setDefaultsForLegacyTDs($obj);

        // Set the flags that will be used on the client side validation
        $obj['ADVANCED_CONFIGURATION'] = IsAdvancedConfiguration();

        $this->setSubtotalPrefs($obj, $view);

        // Set the inventory module supported flag.
        $modMgr = $gManagerFactory->getManager('modules');
        $obj['INV_MODULE_SUPPORTED'] = $modMgr->isModuleSubscribed("7.INV");

        // Set the root flag
        $obj['IS_TOP_LEVEL'] = $isRoot;

        return true;
    }

    /**
     * @param array &$obj the documentparam array
     *
     *
     */
    protected function showTaxCapture(&$obj){
        $obj['TAXCPTVATENABLED'] = TaxSetupManager::isVATEnabled();
        if ( $this->state == $this->kShowEditState || $this->state == $this->kShowViewState || Request::$r->_edittype == 'duplicate' ) {
            $view = $this->getView();
            // adding $obj['DISABLEVAT'] == 'true' condition to make Disable checkbox editable in case user 'Go back' when error comes
            if ( ($obj['TAXCPTVATENABLED'] && DocumentManager::hasTaxSubTotals($obj) && $obj['UPDATES_GL'] == 'G') || $obj['DISABLEVAT'] == 'true' ) {
                $view->findAndSetProperty(['path' => 'DISABLEVAT'], ['disabled' => false], EditorComponentFactory::TYPE_FIELD);
            }
        }
    }

    /**
     * Set the module, subtotal template and tax related fields based on module prefs
     *
     * @param array &$obj the documentparam array
     * @param EditorView $view the documentparam view object
     */
    private function setSubtotalPrefs(&$obj, $view)
    {
        global $gManagerFactory;

        $moduleMap = array('invdocumentparams' => 'inv', 'sodocumentparams' => 'so', 'podocumentparams' => 'po');
        $module = $moduleMap[$view->params["entity"]];
        $obj['TD_MODULE'] = $module;

        // for multitax at root, use the module prefs to decide if avalara is present, since taxsolution is not available
        // for multi-tax at entity or singletax or non-Taxes companies, use GetTaxEngine() call with null taxsolution
        $taxsolutionId = null;
        if ( TaxSetupManager::isMultiTaxJurisdictionConfigured() && IsRoot()) {
            if ( GetTaxEngineForNotSubscribedTaxes($module) == TaxSolutionManager::TAXMETHOD_I_AVALARA) {
                $taxsolutionId = TaxSolutionManager::TAXSOLUTION_AVALARA;
            }
        }
        // check if Avalara tax engine is being used
        if (GetTaxEngine($module, $taxsolutionId) == TaxSolutionManager::TAXMETHOD_I_AVALARA) {
            // if Avalara is enabled hide the "Allow user to override line item tax"
            // check box (default for check box is visible).
            $view->findAndSetProperty(
                array('path' => 'ENABLEOVERRIDETAX'),
                array('hidden' => true),
                EditorComponentFactory::TYPE_FIELD
            );
        } else {
            // if Avalara is NOT enabled hide the "SELECT FOR AVALARA" column on
            // the Subtotals tab (default is visible).
            $view->findAndSetProperty(
                array('path' => 'ISAVATAX'),
                array('hidden' => true),
                EditorComponentFactory::TYPE_GRID_COLUMN
            );
        }

        // if vat/gst is enabled in a transaction we hide the line level taxablity options
        // so for TDs at entity level and for single tax companies we should simply hide the overrride option
        if ( (TaxSetupManager::isVATEnabled() && !IsRoot()) || TaxSetupManager::isSingleTaxJurisdictionConfigured() ) {
            $view->findAndSetProperty(
                array( 'path' => 'ENABLEOVERRIDETAX' ),
                array( 'hidden' => true ),
                EditorComponentFactory::TYPE_FIELD
            );
        }

        //Hide IsTax option for subtotals for entity level TDs for NoTax tax jurisdictions
        if (TaxSetupManager::isTaxModuleConfigured() && IsMultiEntityCompany() && GetContextLocation()
            && ('shownew' === $this->state || 'showedit' === $this->state)) {
            //If we get in here, it means we are in multi entity company and slid into an entity. We should have a
            //tax solution for the entity so the GetTaxEngine will return the tax engine(method) of the current slid into entity.
            $taxEngine = GetTaxEngine($module);
            if ($taxEngine === TaxSolutionManager::TAXMETHOD_I_NONE) {
                $view->findAndSetProperty(array('path' => 'ISTAX'), array('hidden' => true),
                    EditorComponentFactory::TYPE_FIELD);
                $view->findAndSetProperty(array('path' => 'SHOWEXPANDEDTOTALS'), array('disabled' => true),
                                          EditorComponentFactory::TYPE_FIELD);
            }
        }
        /* @var DocumentSetupManager $setupMgr */
        $setupMgr = $gManagerFactory->getManager($module . 'setup');
        $prefs = $setupMgr->get('');
        $obj['TAXSCHED'] = isset($prefs['TAXSCHED']) && 'true' === strtolower($prefs['TAXSCHED']);
        $obj['ENABLE_SUBTOTAL_TEMPLATE'] = isset($prefs['ENABLE_SUBTOTAL_TEMPLATE']) &&
                                                    'true' === strtolower($prefs['ENABLE_SUBTOTAL_TEMPLATE']);

        // show subtotal templates only when the feature is tuned on in module prefs
        if ( !$obj['ENABLE_SUBTOTAL_TEMPLATE']) {
            $view->findAndSetProperty(
                array('path' => 'SUBTOTALTEMPLATE'),
                array('hidden' => true)
            );
        }
        // disable access to templates in docpars of entity level for multi-entity companies
        if ('shownew' === $this->state || 'showedit' === $this->state) {
            // temporarily disable access to subtotal templates in entity for ME companies
            if ( IsMultiEntityCompany() && GetContextLocation() && $obj['ENABLE_SUBTOTAL_TEMPLATE'] ) {
                $obj['ENABLE_SUBTOTAL_TEMPLATE'] = false;
                $obj['SUBTOTALTEMPLATE'] = null; // clear the subtotal template in case it was copied from existing root TD
                $view->findAndSetProperty(
                    array('path' => 'SUBTOTALTEMPLATE'),
                    array('hidden' => true)
                );
            }
        } else if ('showview' === $this->state) {
            // when viewing a TD via transaction history link, do not show the VIEW link for templates since the versions may not match
            $view->findAndSetProperty(
                array('path' => 'SUBTOTALTEMPLATE'),
                array('noedit' => true, 'noview' => true)
            );
        }

    }

    /**
     * Populates default fields for legacy TDs
     *
     * @param array $obj
     */
    private function setDefaultsForLegacyTDs(&$obj)
    {
        if (!isArrayValueProvided($obj, 'CREATETYPE')) {
            $obj['CREATETYPE'] = CreationPolicyConstants::NEW_DOCUMENT_OR_CONVERT;
        }
        if (!isArrayValueProvided($obj, 'TD_CREATION_RULE')) {
            $obj['TD_CREATION_RULE'] = CreationRuleConstants::TOP_LEVEL_OR_ENTITY;
        }

    }
    /**
     * Adjusts the form for the standard configuration.
     *
     * @param array $obj
     */
    protected function adjustForStandardConfiguration(/** @noinspection PhpUnusedParameterInspection */ &$obj)
    {
        $view = $this->getView();
        $advancedFields = $this->getAdvancedSetupFields();
        foreach ($advancedFields as $field) {
            $view->findAndSetProperty(
                array($field['key'] => $field['id']),
                array($field['property'] => $field['value']),
                $field['type']
            );
        }
    }
    /**
     * Restrics creation of a new user group directly from the page by
     * removing the +Add link from the pick list header.
     *
     * @param array $obj
     */
    private function restrictUsergroupCreation(/** @noinspection PhpUnusedParameterInspection */ &$obj)
    {
        $view = $this->getView();
        $view->findAndSetProperty(
            array('path' => 'GROUP'), array('createAllowed' => false)
        );
    }

    /**
     * Hides the Creation rule drop down list box is logged in to entity
     *
     * @param array $obj
     */
    private function setCreationRuleVisibility(/** @noinspection PhpUnusedParameterInspection */ $obj)
    {
        $view = $this->getView();
        $hideTab = !IsMultiEntityCompany();
        $hideTab = $hideTab ||
            (IsMultiEntityCompany() && (GetContextLocation()));
        $view->findAndSetProperty(
            array('path' => 'TD_CREATION_RULE'), array('hidden' => $hideTab),
            EditorComponentFactory::TYPE_FIELD
        );

    }

    /**
     * Show the Entity Settings tab if the root company is selected and
     * hide in case of entity.
     *
     * @param array $obj
     */
    private function configureEntityPropertiesGrid(&$obj)
    {
        $view = $this->getView();

        $loggedinAsRoot = IsMultiEntityCompany() && (!GetContextLocation());
        $isEntitySpecificsVisible = $loggedinAsRoot;
        if (isArrayValueProvided($obj, 'TD_CREATION_RULE')) {
            $isEntitySpecificsVisible = $isEntitySpecificsVisible
                && strcontains($obj['TD_CREATION_RULE'], CreationRuleConstants::ENTITY);
        }

        $view->findAndSetProperty(
            array('id' => 'entity_properties_tab'), array('hidden' => !$isEntitySpecificsVisible),
            EditorComponentFactory::TYPE_TAB
        );

        // hide the tax override column in entity prop grid for single-tax vat companies since they are all vat
        if ( TaxSetupManager::isSingleTaxJurisdictionConfigured() ) {
            /* @var EditorComponent[] $entriesViewArr */
            $view->findComponents([ 'path' => 'DOCPAR_ENTITY_PROPS' ], EditorComponentFactory::TYPE_GRID,
                                  $entriesViewArr);
            $entriesView = $entriesViewArr[0];
            $entriesView->findAndSetProperty([ 'path' => 'ENABLEOVERRIDETAX' ], [ 'hidden' => true ]);
        }

        // Add the row for the Root

        if ($loggedinAsRoot && isArrayValueProvided($obj, 'DOCPAR_ENTITY_PROPS')) {
            if (is_array($obj['DOCPAR_ENTITY_PROPS'])) {
                $lines = count($obj['DOCPAR_ENTITY_PROPS']);
                if ($lines > 0 && CreationRuleConstants::TOP_LEVEL !== $obj['DOCPAR_ENTITY_PROPS'][0]['ENTITY_NAME']) {
                    for ($ind = $lines; $ind > 0; $ind--) {

                        $obj['DOCPAR_ENTITY_PROPS'][$ind] = $obj['DOCPAR_ENTITY_PROPS'][$ind - 1];
                        if (isArrayValueProvided($obj['DOCPAR_ENTITY_PROPS'][$ind], 'ENTITY_NAME') &&
                            isArrayValueProvided($obj['DOCPAR_ENTITY_PROPS'][$ind], 'ENTITY_LOCATION_NO')) {
                            $obj['DOCPAR_ENTITY_PROPS'][$ind]['ENTITY_NAME'] =
                                $obj['DOCPAR_ENTITY_PROPS'][$ind]['ENTITY_LOCATION_NO'] . '--' . $obj['DOCPAR_ENTITY_PROPS'][$ind]['ENTITY_NAME'];
                        }
                    }
                    $rootCreationRule = 'false';
                    if (strpos($obj['TD_CREATION_RULE'], CreationRuleConstants::TOP_LEVEL) !== false) {
                        $rootCreationRule = 'true';
                    }
                    $rootEntry = [
                        'is-root' => true,
                        'ENTITY_NAME' => CreationRuleConstants::TOP_LEVEL,
                        'SEQUENCE' => $obj['SEQUENCE'],
                        'PRESERVE_SEQNUM' => $obj['PRESERVE_SEQNUM'],
                        'INHERIT_SOURCE_DOCNO' => $obj['INHERIT_SOURCE_DOCNO'],
                        'XSLTEMPLATE' => $obj['XSLTEMPLATE'],
                        'SUBTOTALTEMPLATE' => $obj['SUBTOTALTEMPLATE'],
                        'ENABLEOVERRIDETAX' => $obj['ENABLEOVERRIDETAX'],
                        'SHOWEXPANDEDTOTALS' => $obj['SHOWEXPANDEDTOTALS'],
                        'LINELEVELSIMPLETAX' => $obj['LINELEVELSIMPLETAX'],
                        'ENTITY_CREATION_RULE' => $rootCreationRule
                    ];
                    $obj['DOCPAR_ENTITY_PROPS'][0] = $rootEntry;
                }
            }
        }


    }

    /**
     * If the user permissions check box is not selected hide the
     * relevan user permission sections.
     *
     * @param array $obj
     */
    private function setUserpermDetailsVisibility(&$obj) 
    {
        $sectionsHidden = !isset($obj['USERPERM']) || 'true' !== $obj['USERPERM'];

        $view = $this->getView();
        $sectionsToHide = array("USERGROUP_section", "permgrid_section");
        foreach ($sectionsToHide as $sectionId) {
            $view->findAndSetProperty(
                array('id' => $sectionId), array('hidden' => $sectionsHidden),
                EditorComponentFactory::TYPE_SECTION
            );
        }
    }

    /**
     * The printed format shows the ID instead of the label. This method
     * corrects the value for the printed format before rendering.
     *
     * @param array $obj
     */
    private function correctPrintedFormat(&$obj) {
        // Do not alter the printed format if the data is taken from the page:
        // - duplicating the TD.
        // - adding or creating the TD

        if ("duplicate" !== Request::$r->_edittype &&
                !isArrayValueProvided($obj, 'CREATE_OR_SAVE_ACTION')) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            $tplformatMgr = $gManagerFactory->getManager('tplformat');
            if (isArrayValueProvided($obj, 'XSLTEMPLATE')) {
                // Read the saved value for the XSLTEMPLATE and if it cannot
                // be found do the transformation
                if (is_numeric($obj['XSLTEMPLATE'])) {
                    $description = $tplformatMgr->getDescription($obj['XSLTEMPLATE']);
                    if (!is_null($description)) {
                        $obj['XSLTEMPLATE'] = $description;
                    }
                }
            }

            $tdEntityProps = & $obj['DOCPAR_ENTITY_PROPS'];
            if (isset($tdEntityProps) && is_array($tdEntityProps)) {
                foreach($tdEntityProps as & $prop) {
                    if (isArrayValueProvided($prop, 'XSLTEMPLATE')) {
                        if (is_numeric($prop['XSLTEMPLATE'])) {
                            $description = $tplformatMgr->getDescription($prop['XSLTEMPLATE']);
                            if (!is_null($description)) {
                                $prop['XSLTEMPLATE'] = $description;
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * The transaction posting must render the label in the view mode and
     * the corresponding value otherwise to be correctly shown on the page.
     *
     * @param array $obj
     */
    private function correctTransactionPosting(&$obj)
    {
        $view = $this->getView();
        self::findElements(
            $view->params['child'], array('path' => 'UPDATES_GL'),
            null, $trxPostInfo
        );
        $checkForAttribute = 'validlabels';
        $renderedAttribute = 'validvalues';
        if ('showview' != $this->state) {
            if (isset($trxPostInfo) && sizeof($trxPostInfo) == 1) {
                foreach($trxPostInfo[0]['type'][$checkForAttribute] as $k => $val) {
                    if ($obj['UPDATES_GL'] === $val) {
                        $obj['UPDATES_GL'] = $trxPostInfo[0]['type'][$renderedAttribute][$k];
                        break;
                    }
                }
            }
        }

    }
    /**
     * For the view mode limit the subtotal values to 2 decimal places.
     *
     * @param array $obj
     */
    private function correctSubtotalsForView(&$obj) {
        if ('showview' == $this->state) {
            foreach ( $obj['DOCPAR_SUBTOTAL'] as $key => $value) {
                // round the Value field to 10 decimal places
                if (is_numeric($obj['DOCPAR_SUBTOTAL'][$key]['VALUE'])) {
                    $obj['DOCPAR_SUBTOTAL'][$key]['VALUE'] =
                        round($obj['DOCPAR_SUBTOTAL'][$key]['VALUE'], 2);
                }
            }
        }
    }

    /**
     * Packages the contact information into the grid to show it
     * on the page.
     *
     * @param array $obj  entity data
     */
    protected function packageContactData(&$obj) 
    {
        $obj['CONTACT_INFO'][0] =
            array('CONTACTTITLE1' => $obj['CONTACTTITLE1'],
                'SHOWTITLE1' => $obj['SHOWTITLE1'],
                'ALLOWEDITBILLTO' => $obj['ALLOWEDITBILLTO']);
        $obj['CONTACT_INFO'][1] =
            array('CONTACTTITLE1' => $obj['CONTACTTITLE2'],
                'SHOWTITLE1' => $obj['SHOWTITLE2'],
                'ALLOWEDITBILLTO' => $obj['ALLOWEDITSHIPTO']);
    }

    /**
     * Populate contact data.
     *
     * @param array $obj
     */
    protected function retrieveContactData(& $obj)
    {
        $obj['CONTACTTITLE1'] = $obj['CONTACT_INFO'][0]['CONTACTTITLE1'];
        $obj['SHOWTITLE1'] = $obj['CONTACT_INFO'][0]['SHOWTITLE1'];
        $obj['ALLOWEDITBILLTO'] = $obj['CONTACT_INFO'][0]['ALLOWEDITBILLTO'];

        $obj['CONTACTTITLE2'] = $obj['CONTACT_INFO'][1]['CONTACTTITLE1'];
        $obj['SHOWTITLE2'] = $obj['CONTACT_INFO'][1]['SHOWTITLE1'];
        $obj['ALLOWEDITSHIPTO'] = $obj['CONTACT_INFO'][1]['ALLOWEDITBILLTO'];

    }

    /**
     * Adjusts the labels on the page based on the selected page.
     * The implementations of this method are in the proper classes extending
     * the parent class.
     */
    protected function setLabels()
    {
        // Nothing to be done by default.
    }

    /**
     * Returns the list of fields that are specific for the advanced setup.
     *
     * @return array
     */
    protected function getAdvancedSetupFields()
    {
        return array(
            "DOCCLASS" => array(
                'key' => 'path', 'id' => "DOCCLASS", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "CATEGORY" => array(
                'key' => 'path', 'id' => "CATEGORY", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "UPDATES_INV" => array(
                'key' => 'path', 'id' => "UPDATES_INV", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "IN_OUT" => array(
                'key' => 'path', 'id' => "IN_OUT", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "UPDATES_COST" => array(
                'key' => 'path', 'id' => "UPDATES_COST", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "UPDATES_GL" => array(
                'key' => 'path', 'id' => "UPDATES_GL", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "ENABLE_RETAINAGE" => array(
                'key' => 'path', 'id' => "ENABLE_RETAINAGE", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "WARNONLOWQTY" => array(
                'key' => 'path', 'id' => "WARNONLOWQTY", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "posting_conf_tab" => array(
                'key' => 'id', 'id' => "posting_conf_tab", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_TAB
            ),
            "DOCPAR_TOTALS" => array(
                'key' => 'path', 'id' => "DOCPAR_TOTALS", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_GRID
            ),
            "DOCPAR_RECALLS" => array(
                'key' => 'path', 'id' => "DOCPAR_RECALLS", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_GRID
            ),
            "trx_conversion_section" => array(
                'key' => 'id', 'id' => "trx_conversion_section", 'property' => 'helpText',
                'value' => '', "type" => EditorComponentFactory::TYPE_SECTION
            ),
            "POSTTOGL" => array(
                'key' => 'path', 'id' => "POSTTOGL", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "TD_CREATION_RULE" => array(
                'key' => 'path', 'id' => "TD_CREATION_RULE", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_FIELD
            ),
            "entity_properties_tab" => array(
                'key' => 'id', 'id' => "entity_properties_tab", 'property' => 'hidden',
                'value' => true, "type" => EditorComponentFactory::TYPE_TAB
            ),
        );
    }

    /**
     * Overriding the base method instructing to show / hide the Duplicate
     * button on the editor. Hide it for the companies with the non-advanced
     * (simplified) setup.
     *
     * @return bool
     */
    protected function CanDuplicate()
    {
        $showDuplicate =   parent::CanDuplicate();
        if (!IsAdvancedConfiguration()) {
            $showDuplicate = false;
        }
        return $showDuplicate;
    }

    /**
     * Uses DOCID of the transaction definition instead of the key (record#)
     * to generate a javascript string representing a function called upon
     * closing popup window.
     *
     * @param string $key
     * @param array  $obj
     *
     * @return string
     */
    protected function getPopupCloseJS($key, $obj = [])
    {
        return "ClosePopup(\"" . util_encode($obj['DOCID']) . "\", false);";
    }

    /**
     * @param array $obj
     * @param EditorContainer $view
     */
    protected function changeOrderMetaDataValidation(&$obj, EditorContainer $view)
    {
        $allowedModules = DocumentParamsManager::getAllowedModules();

        $advanced = IsAdvancedConfiguration();

        if( $advanced && Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled() && in_array($obj['TD_MODULE'], $allowedModules)  )
        {

            $docChange = $obj['ENABLEDOCCHANGE'] ?? "No Change";
            $enableChangeOrder = "";
            $docType = "";

            if ($docChange == "" || $docChange == "No Change") {
                $enableChangeOrder = 'false';
            }  elseif ($docChange == "Enable Change") {
                $enableChangeOrder = 'true';
                $docType = 'Source Document';
            } elseif ($docChange == 'Change Order') {
                $enableChangeOrder = 'true';
                $docType = 'Change Document';
            }

            $obj['ENABLECHANGEORDER'] = $obj['ENABLECHANGEORDER'] ?? $enableChangeOrder;
            $obj['DOC_TYPE'] = $obj['DOC_TYPE'] ?? $docType;

            if (!isNullOrBlank($obj['RECORDNO'])) {
                $docParMgr = Globals::$g->gManagerFactory->getManager('documentparams');
                $hasChange=$docParMgr->getHasChangeFlag($obj);
                $hasChange = ($docChange === "Change Order") ?true:$hasChange;
                $orderExist=$docChange != "No Change" && $docParMgr->checkOrderDocExists($obj);
                if (($orderExist && $hasChange) ) {
                    $view->findAndSetProperty(array('path' => 'ENABLECHANGEORDER'), array('readonly' => true));
                    $view->findAndSetProperty(array('path' => 'DOC_TYPE'), array('readonly' => true));
                }
            }
        }
        else{
            $view->findAndSetProperty(array('path' => 'ENABLECHANGEORDER'), array('hidden' => true));
            $view->findAndSetProperty(array('path' => 'DOC_TYPE'), array('hidden' => true));
        }

    }

    /**
     * we dont want the New Document only option for create type in non-cco company
     * @param EditorView $view
     */
    protected function removeCCOOptions(EditorView $view) {
        $createTypeField = [];
        if($view->findComponents(['path' => 'CREATETYPE'], EditorComponentFactory::TYPE_FIELD, $createTypeField)) {
            $validValues = $createTypeField[0]->params['validvalues'] ?? [];
            // note: values are NOT English, but the LABELS are....
            if (($key = array_search("New document only", $validValues)) !== false) {
                $type = $createTypeField[0]->getProperty('type');
                $validLabels  = $type['validlabels'] ?? [];
                $validIvalues = $type['_validivalues'] ?? [];
                unset($validValues[$key]);
                unset($validLabels[$key]);
                unset($validIvalues[$key]);

                $createTypeField[0]->setProperty(array('type', 'validvalues'), array_values($validValues));
                $createTypeField[0]->setProperty(array('type', 'validlabels'), array_values($validLabels));
                $createTypeField[0]->setProperty(array('type', '_validivalues'), array_values($validIvalues));
                $createTypeField[0]->params['validvalues'] = $validValues;
            }
        }
    }
}
