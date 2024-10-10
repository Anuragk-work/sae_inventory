<?php

/**
 * DocumentSetupEditor.cls
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation, All Rights Reserved
 */

require_once 'scm_util.inc';

/**
 * FormEditor for subscription configuration and setup of Inventory, Order Entry and Purchasing
 */

/**
 * Class DocumentSetupEditor
 */
class DocumentSetupEditor extends ModuleSetupEditor
{
    /** @var string $installedOption */
    public $installedOption         = '';

    /** @var bool $installedOption */
    public $isAdvancedConfiguration = false;

    /** @var string  $mod*/
    public $mod                     = '';

    /** @var string $kExportDefinitionAction */
    public $kExportDefinitionAction = 'exportdefinition';

    /** @var string $kInstallAction */
    public $kInstallAction          = 'install';

    /**
     * @var array I18n mapping
     */
    protected $setupTextMap = [];

    /**
     * User info specific tokens
     * @var string[]
     */
    protected const additionalTokens = [
        'IA.THIS_COMP_USING_WORKFLOW',
        'IA.IMPORTED_LOWER_CASE',
        'IA.INSTALLED_LOWER_CASE',
        'IA.SCM_WORKFLOW_INSTALL_CONFIRMATION',
        'IA.THIS_COMPANY_IS_USING_AN_XYZ_WORKFLOW'
    ];

    /**
     * @param array $_params parameters
     */
    public function __construct($_params = array())
    {
        $this->additionalTokens = array_merge($this->additionalTokens, self::additionalTokens);
        $this->setupTextMap = I18N::getTokensForArray(I18N::tokenArrayToObjectArray($this->additionalTokens));

        $this->isAdvancedConfiguration = IsAdvancedConfiguration();

        parent::__construct($_params);
    }

    /**
     * @return DocumentSetupManager
     */
    public function getEntityMgr()
    {
        assert($this->entityMgr instanceof DocumentSetupManager);
        return $this->entityMgr;
    }

    /**
     * Initialization of constants
     * Override parent's method
     */
    protected function InitConstants()
    {
        parent::InitConstants();

        $this->kActionHandlers[$this->kInstallAction] = array(
            'handler' => 'ProcessInstallAction',
            'states'  => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                $this->kShowNewState,
                $this->kCreateWarningState
            ),
            'csrf' => true,
        );
        $this->kActionHandlers[$this->kExportDefinitionAction] = array(
            'handler' => 'ProcessExportDefinitionAction',
            'states'  => array(
                $this->kShowEditState,
                $this->kEditWarningState,
                $this->kShowNewState,
                $this->kCreateWarningState
            )
        );
    }

    /**
     * Definition of action for export definition
     *
     * @param array &$_params parameters
     *
     * @return bool
     */
    public function ProcessExportDefinitionAction(/** @noinspection PhpUnusedParameterInspection */ &$_params)
    {
        $ok = $this->getEntityMgr()->ExportWorkflow();

        return $ok;
    }

    /**
     * Definition of action for install
     *
     * @param array &$_params parameters
     *
     * @return bool
     */
    public function ProcessInstallAction(&$_params)
    {
        // When installing workflow, set standardized name
        global $_FILES;
        if (!empty($_FILES['_obj__INSTALL_WORKFLOW_FORM-_obj__CUSTWORKFLOW'])) {
            $_FILES['_obj__CUSTWORKFLOW'] = $_FILES['_obj__INSTALL_WORKFLOW_FORM-_obj__CUSTWORKFLOW'];
            unset($_FILES['_obj__INSTALL_WORKFLOW_FORM-_obj__CUSTWORKFLOW']);
        }

        $installoption = Request::$r->_installoption;
        $ok = $this->getEntityMgr()->InstallWorkflow($installoption);

        $gErr = Globals::$g->gErr;
        if (!$ok || $gErr->hasErrors()) {
            $this->state = $this->kErrorState;
        } else {
            // This is to save the Custom Documents tab selection.
            $this->retrieveObjectFromView($_params, $obj);
            $this->getEntityMgr()->UpdateInstalledDefinitions($obj);
            // Clean up obj
            unset($obj['INSTALL_WORKFLOW_FORM']);
            unset($obj['CUSTWORKFLOW']);
            unset($obj['CUSTWORKFLOW_FILE_INFO']);

            $labels = $this->getWorkflowLabels();
            // Update installed workflow message
            if ($obj['WORKFLOW_LIST'] == 'None') {
                // Specific case
                $obj['INSTALLEDWORKFLOW'] = $this->getEntityMgr()->GetPreference('INSTALLEDWORKFLOW');

                $worflowTokens = [
                    [
                        'id' => 'IA.THIS_COMP_USING_WORKFLOW',
                        'placeHolders' => [
                            ['name' => 'WORKFLOW_NAME', 'value' => $labels[$obj['INSTALLEDWORKFLOW']]]
                        ]
                    ]
                ];

                $workflowLabels = getLocalizedText($worflowTokens, $errMsg);
                $obj['INSTALLED_WORKFLOW_TXT'] = GT($workflowLabels,'IA.THIS_COMP_USING_WORKFLOW');
            } else {
                $worflowTokens = [
                    [
                        'id' => 'IA.THIS_COMP_USING_WORKFLOW',
                        'placeHolders' => [
                            ['name' => 'WORKFLOW_NAME', 'value' => $obj['WORKFLOW_LIST']]
                        ]
                    ]
                ];

                $workflowLabels = getLocalizedText($worflowTokens, $errMsg);
                $obj['INSTALLED_WORKFLOW_TXT'] = GT($workflowLabels,'IA.THIS_COMP_USING_WORKFLOW');
                // Applied workflow
                $obj['APPLIED_WORKFLOW'] = array_search($obj['WORKFLOW_LIST'], $labels);
            }
            // Set current object
            Request::$r->SetCurrentObject($obj);

            //$installText = ($this->isAdvancedConfiguration) ? 'imported' : 'installed';
            $installText = ( $this->isAdvancedConfiguration )
                ? GT($this->textMap, 'IA.IMPORTED_LOWER_CASE') : GT($this->textMap, 'IA.INSTALLED_LOWER_CASE');

            $worflowinstalledConfirmation = [
                [
                    'id' => 'IA.SCM_WORKFLOW_INSTALL_CONFIRMATION',
                    'placeHolders' => [
                        ['name' => 'WORKFLOW_INSTALLED', 'value' => $installText]
                    ]
                ]
            ];
            $workflowLabels = getLocalizedText($worflowinstalledConfirmation, $errMsg);

            // Give the message to show the invoice number just created
            $confirmation = GT($workflowLabels,'IA.SCM_WORKFLOW_INSTALL_CONFIRMATION');
            $this->SetMessageWithObject($confirmation, $obj);
        }

        return $ok;
    }

    /**
     * Override parent's method
     *
     * @param array &$params parameters
     */
    protected function buildDynamicMetadata(&$params)
    {
        if ($this->isAdvancedConfiguration) {
            // Advanced company
            // enable subtotal templates only for mutientity companies for now
            if ( IsMultiEntityCompany() ) {
                self::findAndSetMetadata($params, array('path' => 'ENABLE_SUBTOTAL_TEMPLATE'), array('hidden' => false));
            }
            self::findAndSetMetadata($params, array('path' => 'ENABLE_ADVANCED'), array('readonly' => true));
            self::findAndSetMetadata(
                $params, array('path' => 'REINSTALLOPT'), array('hidden' => true), EditorComponentFactory::TYPE_ROW
            );
            self::findAndSetMetadata($params, array('path' => 'SPACE'), array('hidden' => true));
            self::findAndSetMetadata($params, array('path' => 'INSTALLED_WORKFLOW_TXT'), array('hidden' => true));
            self::findAndSetMetadata($params, array('path' => 'WORKFLOW_LIST'), array('hidden' => true));
            self::findAndSetMetadata($params, array('path' => 'WORKFLOW_APPLY'), array('hidden' => true));
            self::findAndSetMetadata($params, array('path' => 'WORKFLOW_LEARN_MORE'), array('hidden' => true));
        } else {
            // Simplified company
            self::findAndSetMetadata(
                $params,
                array('path' => 'INSTALL_WORKFLOW_FORM'),
                array('hidden' => true),
                EditorComponentFactory::TYPE_ROW
            );
            self::findAndSetMetadata(
                $params, array('path' => 'EXPORT_FORM'), array('hidden' => true), EditorComponentFactory::TYPE_ROW
            );

            // If not advanced company, hide 'Documents' status option
            $match = array();
            self::findElements($params, array('path' => 'STATUS'), EditorComponentFactory::TYPE_FIELD, $match);
            $match[0]['hidden'] = true;
        }

        $docInfo = DocumentSetupUtil::GenerateDocumentSetupInfo($this->getEntityMgr()->_spiArray[$this->mod]);
        $documentSetupOptionsPaths = $this->getDocumentSetupOptionsPaths($docInfo);
        // If there is no document informations, hide whole 'Documents' tab
        if (empty($documentSetupOptionsPaths) && !$this->isAdvancedConfiguration) {
            $match = array();
            self::findElements($params, array('id' => 'docs_configuration'), EditorComponentFactory::TYPE_PAGE, $match);
            $match[0]['hidden'] = true;
        }

        $ctx = GetContextLocation();
        if (IsMultiEntityCompany() && $ctx) {
            // Hide 'Workflow' section. At the entity level, one shouldn't be able to configure
            $match = array();
            self::findElements($params, array('id' => 'workflow_section'), EditorComponentFactory::TYPE_SECTION, $match);
            $match[0]['hidden'] = true;

            self::findAndSetMetadata($params,
                array('path' => 'DISTRIBUTE_SUBTOTALS_AT_ENTITY'),
                array('hidden' => false));
        }

        $ismeTop = IsMultiEntityCompany() && !GetContextLocation();
        if ($ismeTop) {
            self::findAndSetMetadata($params,
                array('path' => 'ALLOW_EDITING_SUBTOTALDIMENSIONS_ATROOT'),
                array('hidden' => false));

            self::findAndSetMetadata($params,
                array('path' => 'COPY_DIMENSIONS_FROM_LINEITEM'),
                array('hidden' => false));

            $featureConfigMgr = FeatureConfigManagerFactory::getInstance();
            $allowEditingSubtotLocDeptAtToplevel = $featureConfigMgr->isFeatureEnabled('ALLOW_EDITING_LOCDEPT_IN_SUBTOT_ATTOPLEVEL');
            $hidepref = !$allowEditingSubtotLocDeptAtToplevel;
            self::findAndSetMetadata($params,
                array('path' => 'ALLOW_EDITING_SUBTOT_LOC_DEPT_ATROOT'),
                array('hidden' => $hidepref));
        }
    }

    /**
     * Override parent's method
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        // Set major variables
        $view = $this->getView();
        $isMultiEntityCompany = IsMultiEntityCompany();
        $ctx = GetContextLocation();

        // Populate documents grid
        $obj['DOCUMENTS_GRID'] = array();
        // Get managers for handling documents
        $docParamsMgr = $this->GetManager('documentparams');
        $glAcctMgr = $this->GetManager('glaccount');


        $docInfo = DocumentSetupUtil::GenerateDocumentSetupInfo($this->getEntityMgr()->_spiArray[$this->mod], true);
        $documentSetupOptionsPaths = $this->getDocumentSetupOptionsPaths($docInfo);
        if (!empty($documentSetupOptionsPaths) || $this->isAdvancedConfiguration) {
            // Get module related documents
            $schema = $this->getEntityMgr()->GenerateSchemaDocInfo($this->getEntityMgr()->_spiArray[$this->mod]);
            $isRevRecEnabled = RevenueSetupManager::isRevRecEnabled(Globals::$g->kSOid);
            foreach ($schema['fieldinfo'] as $field) {
                // Document path
                $docPath = preg_replace('/ /', '_', $field['fullname']);
                // Retrieve document definition
                $params = array(
                    'filters' => array(
                        array(
                            array('DOCID', '=', $field['fullname']),
                            array('LATESTVERSIONKEY', 'IS NULL', '')
                        )
                    ),
                    'selects' => array('RECORDNO', 'LOCATIONKEY'),
                );
                $record = $docParamsMgr->GetList($params);
                // Label with hyperlink which open document definition
                $hyperLink = '<a href="#" onclick="LaunchDefinitionLink('.$record[0]['RECORDNO'].')">'
                    .$field['fullname'].'</a>';
                // Status
                $status = ($this->isAdvancedConfiguration) ? $obj['DOCTYPES'][$docPath] : 'true';
                // Summary frequency
                $batch = $this->canConfigTD($documentSetupOptionsPaths, $field['fullname'], '_BATCH') ?
                    $obj['DOCUMENT'][$docPath.'_BATCH'] : 'NON_EXISTENT';
                // Retrieve location key
                $locKey = $record[0]['LOCATIONKEY'];
                // Inventory journal
                $journal = $this->canConfigTD($documentSetupOptionsPaths, $field['fullname'], '_JOURNAL') ?
                    $obj['DOCUMENT'][$docPath.'_JOURNAL'] : 'NON_EXISTENT';

                if ($this->mod == 'so' && $isRevRecEnabled) {
                    // Rev rec journal
                    $revrecjournal = $this->canConfigTD($documentSetupOptionsPaths, $field['fullname'], '_REVRECJOURNAL') ?
                        $obj['DOCUMENT'][$docPath.'_REVRECJOURNAL'] : 'NON_EXISTENT';
                    // Default Deferred Revenue Account
                    $defrevacct = $this->canConfigTD($documentSetupOptionsPaths, $field['fullname'], '_DEFREVACCT') ?
                        $obj['DOCUMENT'][$docPath.'_DEFREVACCT'] : 'NON_EXISTENT';
                    if ($isMultiEntityCompany && $ctx && empty($locKey)) {
                        if ($defrevacct != 'NON_EXISTENT') {
                            $params = array(
                                'filters' => array(
                                    array(
                                        array('RECORDNO', '=', $defrevacct),
                                        array('CNY#', '=', GetMyCompany())
                                    )
                                ),
                                'selects' => array('ACCT_NO', 'TITLE'),
                            );
                            $glAccount = $glAcctMgr->GetList($params);
                            if (!empty($glAccount[0])) {
                                $defrevacct = $glAccount[0]['ACCT_NO'].'--'.$glAccount[0]['TITLE'];
                            }
                        }
                    } else {
                        $defrevacct = ($defrevacct != 'NON_EXISTENT' && $defrevacct !== null && $defrevacct != '') ?
                            $glAcctMgr->GetVidFromRecordNo($defrevacct) : $defrevacct;
                    }
                } else {
                    $revrecjournal = null;
                    $defrevacct = null;
                    $emailTemplate = null;
                }

                if ($this->mod == 'so') {
                    $additionalJournal = $this->canConfigTD($documentSetupOptionsPaths, $field['fullname'], '_ADDJOURNAL') ?
                        $obj['DOCUMENT'][$docPath.'_ADDJOURNAL'] : 'NON_EXISTENT';
                }else {
                    $additionalJournal = null;
                }

                if ($this->mod == 'so' || $this->mod == 'po') {
                    // Sales Posting Summary Frequency
                    // $prinvbatch = $this->canConfigTD($docPars, $documentSetupOptionsPaths, $field['fullname'], '_PRINVBATCH') ?
                    //    $obj['DOCUMENT'][$docPath.'_PRINVBATCH'] : 'NON_EXISTENT';
                    // Sales Journal
                    // Email template
                    if (isset($obj['DOCUMENT'][$docPath . '_EMAILTEMPLATE'])) {
                        $emailTemplate = $obj['DOCUMENT'][$docPath.'_EMAILTEMPLATE'];
                        $emailTemplates[] = $emailTemplate;
                    } else {
                        $emailTemplate = null;
                    }
                    $prinvjournal = $this->canConfigTD($documentSetupOptionsPaths, $field['fullname'], '_PRINVJOURNAL') ?
                        $obj['DOCUMENT'][$docPath.'_PRINVJOURNAL'] : 'NON_EXISTENT';
                } else {
                    //$prinvbatch = null;
                    $prinvjournal = null;
                }

                // Populate documents grid
                /** @noinspection PhpUndefinedVariableInspection */
                $obj['DOCUMENTS_GRID'][] = array(
                    'LOCATIONKEY'   => $locKey,
                    'DOCPATH'       => $docPath,
                    'DOCID'         => $field['fullname'],
                    'LABEL'         => $hyperLink,
                    'STATUS'        => $status,
                    'BATCH'         => $batch,
                    'JOURNAL'       => $journal,
                    'REVRECJOURNAL' => $revrecjournal,
                    'DEFREVACCT'    => $defrevacct,
                    //'PRINVBATCH'    => $prinvbatch,
                    'PRINVJOURNAL'  => $prinvjournal,
                    'ADDJOURNAL'  => $additionalJournal,
                    'EMAILTEMPLATE' => $emailTemplate,
                );
            }

            if ($isMultiEntityCompany && $ctx && !empty($emailTemplates)) {
                // HACK: Inside an entity, email templates are not editable, hence not a picker, hence it's missing the --Name.  This should've been handled by the framework.
                // This is a temporary workaround that is done in other places too :(
                $emailTemplates = INTACCTarray_unique($emailTemplates);
                $emailTempalteMgr = Globals::$g->gManagerFactory->getManager('emailtemplate');
                $results = $emailTempalteMgr->GetList([ 'selects' => ['RECORDNO', 'EMAILTEMPLATENAME'], 'filters' => [[[ 'RECORDNO', 'IN', $emailTemplates]]]]);
                foreach ($obj['DOCUMENTS_GRID'] as &$row) {
                    if (isset($row['EMAILTEMPLATE'])) {
                        foreach ($results as $result) {
                            if ($result['RECORDNO'] == $row['EMAILTEMPLATE']) {
                                $row['EMAILTEMPLATE'] .= '--' . $result['EMAILTEMPLATENAME'];
                                break;
                            }
                        }
                    }
                }
                unset($row);
            }
        }

        // Init ENABLE_ADVANCED from INV
        $obj['ENABLE_ADVANCED'] = $this->isAdvancedConfiguration ? 'true' : 'false';

        // Initialize common preferences if it's a new subscription
        if ($this->state == Editor_ShowNewState) {
            // 'KIT' and 'DISALLOW_NEGINV' option
            if ($this->mod == 'inv' || $this->mod == 'so') {
                $obj['KIT'] = IsKitEnabled() ? 'true' : 'false';
                $obj['DISALLOW_NEGINV'] = (!IsNegativeInventoryAllowed()) ? 'true' : 'false';
            }
            // 'DISALLOW_QTY_CHANGE_WHENCONVERT' option
            $obj['DISALLOW_QTY_CHANGE_WHENCONVERT'] = (!isQuantityChangeAllowedWhenConverting($this->mod)) ? 'true' : 'false';
        }

        // Workflow logic
        if (!$this->isAdvancedConfiguration) {
            $isreinstall = (Request::$r->_reinstall == 'true') ? true : false;
            $this->installedOption = $obj['INSTALLEDWORKFLOW'];

            if ((empty($obj['INSTALLEDWORKFLOW']) || $obj['INSTALLEDWORKFLOW'] == 'false'
                || $obj['INSTALLEDWORKFLOW'] == 'NONE' || $isreinstall) && $this->mod != 'inv'
            ) {
                /**
                 * If there is an installed workflow, hide all the install options and display the single workflow link.
                 * Else, display all the workflow options
                 */
                $view->findAndSetProperty(array('path' => 'SPACE'), array('hidden' => true));
                $view->findAndSetProperty(
                    array('path' => 'REINSTALLOPT'), array('hidden' => true), EditorComponentFactory::TYPE_ROW
                );

                // In this case, must initialize 'INSTALLEDWORKFLOW' if null
                if (empty($obj['INSTALLEDWORKFLOW'])) {
                    $obj['INSTALLEDWORKFLOW'] = 'INV';

                    // In simplified company, and with no installed workflow, display workflow list directly
                    $view->findAndSetProperty(array('path' => 'INSTALLED_WORKFLOW_TXT'), array('hidden' => true));
                    $view->findAndSetProperty(array('path' => 'WORKFLOW_LEARN_MORE'), array('hidden' => true));
                    $view->findAndSetProperty(array('path' => 'WORKFLOW_LIST'), array('hidden' => false));
                    $view->findAndSetProperty(
                        array('path' => 'WORKFLOW_APPLY'), array('hidden' => false), EditorComponentFactory::TYPE_ROW
                    );
                }
            }

            // Set workflow name if simplified company
            if (!empty($obj['INSTALLEDWORKFLOW'])) {
                $workflowLabels = $this->getWorkflowLabels();
                $match = array();
                $view->findComponents(
                    array('path' => 'INSTALLED_WORKFLOW_TXT'), EditorComponentFactory::TYPE_FIELD, $match
                );
                $elt =& $match[0];
                if (!empty($elt)) {
                    $tokens = [
                        [
                            'id'           => 'IA.THIS_COMPANY_IS_USING_AN_XYZ_WORKFLOW',
                            'placeHolders' => [
                                [ 'name' => 'WORKFLOW_NAME', 'value' => $workflowLabels[$obj['INSTALLEDWORKFLOW']] ],
                            ],
                        ],
                    ];
                    $result = I18N::getTokensForArray(I18N::tokenArrayToObjectArray($tokens));
                    $workflowname = GT($result, 'IA.THIS_COMPANY_IS_USING_AN_XYZ_WORKFLOW');
                    $elt->setProperty(
                        'default',
                        $workflowname
                    );
                }

                $workflowDescs = $this->getWorkflowDescs(true);
                $view->findAndSetProperty(
                    array('path' => 'INSTALLED_WORKFLOW_TXT'),
                    array('helpText' => $workflowDescs[$obj['INSTALLEDWORKFLOW']])
                );
            }
        }

        // you cannot turn off subtotal tempaltes if its already on
        if ($obj['ENABLE_SUBTOTAL_TEMPLATE'] == 'true') {
            $view->findAndSetProperty(
                array('path' => 'ENABLE_SUBTOTAL_TEMPLATE'),
                array('readonly' => true)
            );
        }

        // if taxes are installed, derive tax config from taxsolution, so disable advanced tax module config
        if (TaxSetupManager::isTaxModuleConfigured()) {
            $view->findAndSetProperty(array('path' => 'TAXSCHED'), array('disabled' => true));
        }

        return parent::mediateDataAndMetadata($obj);
    }

    /**
     * Returns true or false whether TD can be configured through documents configuration tab
     *
     * @param array  $documentSetupOptionsPaths     all configurable document setup paths
     * @param string $docID                         doc ID
     * @param string $suffix                        suffix to add for path
     *
     * @return bool
     */
    private function canConfigTD($documentSetupOptionsPaths, $docID, $suffix)
    {
        $docPath = preg_replace('/ /', '_', $docID);
        // In Advanced companies, this check is enough
        $configurable = in_array('DOCUMENT.'.$docPath.$suffix, $documentSetupOptionsPaths);

        if ($configurable && !$this->isAdvancedConfiguration) {
            /**
             * In Simplified company, all TD's status is default as true
             * However, some TD could still be inactive
             * We need to handle this case
             */
            $docPars = $this->getEntityMgr()->_docPars;
            foreach ($docPars as $docPar) {
                if ($docPar['DOCID'] == $docID && $docPar['STATUS'] == 'F') {
                    $configurable = false;
                    break;
                }
            }
        }

        return $configurable;
    }

    /**
     * Override parent's method
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    protected function prepareObjectForSave(&$obj)
    {
        $this->objCleansing($obj);
        return parent::prepareObjectForSave($obj);
    }

    /**
     * Override parent's method
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    protected function prepareObjectForCreate(&$obj)
    {
        $this->objCleansing($obj);
        return parent::prepareObjectForCreate($obj);
    }

    /**
     * Clean obj
     *
     * @param array &$obj entity
     */
    private function objCleansing(&$obj)
    {
        if ($obj['INSTALLEDWORKFLOW'] == 'false') {
            unset($obj['INSTALLEDWORKFLOW']);
        }
        if ($obj['ALLOWPROCESSTRANS'] == 'false') {
            unset($obj['ALLOWPROCESSTRANS']);
        }

        // Cleansing
        unset($obj['std_buttons']);
        unset($obj['DOCUMENTS_GRID']);
        if ($this->mod == 'po' || $this->mod == 'so') {
            unset($obj['PRICING.USEPRICESCHED']);
            unset($obj['PRICING.USEDISCOUNT']);
            unset($obj['PRICING.USEPRICELISTS']);
        }
        if ($this->mod == 'so') {
            unset($obj['PRICING.LINEDISCOUNTONSUGGESTEDPRICE']);
        }

    }

    /**
     * Override parent's method
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    protected function transformViewObjectToBiz(&$obj)
    {
        if (!empty($obj['DOCUMENTS_GRID'])) {
            $obj['DOCTYPES'] = array();
            $obj['DOCUMENT'] = array();
            foreach ($obj['DOCUMENTS_GRID'] as $row) {
                $prefs = $this->retrieveDocPref($obj['DOCUMENTS_GRID'], $row['LABEL']);
                $label = strip_tags($row['LABEL']);
                $docPath = preg_replace('/ /', '_', $label);

                if (!empty($prefs['STATUS']) && $prefs['STATUS'] != 'NON_EXISTENT') {
                    $obj['DOCTYPES'][$docPath] = $prefs['STATUS'];
                    $obj['DOCIDS'][$docPath] = $row['DOCID'];
                }
                if (!empty($row['LOCATIONKEY'])) {
                    $obj['LOCATIONKEYS'][$docPath] = $row['LOCATIONKEY'];
                }

                if (!empty($prefs['BATCH']) && $prefs['BATCH'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_BATCH'] = $prefs['BATCH'];
                }
                if (!empty($prefs['JOURNAL']) && $prefs['JOURNAL'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_JOURNAL'] = strip_tags($prefs['JOURNAL']);
                }
                if (!empty($prefs['REVRECJOURNAL']) && $prefs['REVRECJOURNAL'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_REVRECJOURNAL'] = strip_tags($prefs['REVRECJOURNAL']);
                }
                if (!empty($prefs['ADDJOURNAL']) && $prefs['ADDJOURNAL'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_ADDJOURNAL'] = strip_tags($prefs['ADDJOURNAL']);
                }
                if (!empty($prefs['DEFREVACCT']) && $prefs['DEFREVACCT'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_DEFREVACCT'] = strip_tags($prefs['DEFREVACCT']);
                }
                /*if (!empty($prefs['PRINVBATCH']) && $prefs['PRINVBATCH'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_PRINVBATCH'] = $prefs['PRINVBATCH'];
                }*/
                if (!empty($prefs['PRINVJOURNAL']) && $prefs['PRINVJOURNAL'] != 'NON_EXISTENT') {
                    $obj['DOCUMENT'][$docPath.'_PRINVJOURNAL'] = strip_tags($prefs['PRINVJOURNAL']);
                }
                if (!empty($prefs['EMAILTEMPLATE'])) {
                    $emailTemplate = strip_tags($prefs['EMAILTEMPLATE']);
                    list($emailTemplate) = explode('--', $emailTemplate);
                    $obj['DOCUMENT'][$docPath.'_EMAILTEMPLATE'] = $emailTemplate;
                }
            }
            unset($obj['DOCUMENTS_GRID']);
        }

        if (empty($obj['INSTALLEDWORKFLOW'])) {
            $obj['INSTALLEDWORKFLOW'] = $this->getEntityMgr()->GetPreference('INSTALLEDWORKFLOW');
        }

        return true;
    }

    /**
     * Override parent's method
     *
     * @param array &$obj UI data
     *
     * @return bool
     */
    protected function transformBizObjectToView(&$obj)
    {
        if (!empty($obj['DOCUMENT'])) {
            // Retrive global variable containing accounts map
            BuildAccountMap();
            global $pr_acctmapno;
            // Handle formatting accounts in documents configuration tab
            foreach ($obj['DOCUMENT'] as $key => &$value) {
                if (isl_str_endswith($key, '_DEFREVACCT') && isl_strpos($value, '--') !== false) {
                    $acct_no = explode('--', $value);
                    $value = $pr_acctmapno[$acct_no[0]]['RECORD#'];
                }
            }
        }

        return true;
    }

    /**
     * List of javascript files to include
     * Override parent's method
     *
     * @return array
     */
    protected function getJavaScriptFileNames()
    {
        return array('../resources/js/subscriptionwiz.js');
    }

    /**
     * Define vars to be used into javascript files
     * Override parent's method
     *
     * @return array
     */
    protected function getEditorGlobals()
    {
        $obj = $this->getBusinessObject();
        $mcp = IsMultiEntityCompany();
        $ctx = GetContextLocation();

        $toReturn = array(
            'WAREHOUSE_OP'            => GetOperationId($this->mod . '/lists/warehouse'),
            'PRODLINE_OP'             => GetOperationId($this->mod . '/lists/productline'),
            'APPROVALPOLICY_OP'       => GetOperationId($this->mod . '/lists/poapprovalpolicy'),
            'APPROVALRULE_OP'        => GetOperationId($this->mod . '/lists/poapprovalrule'),
            'CONFIG_OP'               => GetOperationId($this->mod . '/activities/' . $this->mod . 'documentparams/view'),
            'JOURNAL_OP'              => GetOperationId('gl/lists/journal/view'),
            'GLACCT_OP'               => GetOperationId('gl/lists/glaccount/view'),
            'SESS'                    => Session::getKey(),
            'MOD'                     => $this->mod,
            'CNY'                     => GetMyCompany(),
            'IS_ADVANCED'             => $this->isAdvancedConfiguration,
            'ORIGINAL_INSTALL_OPTION' => $this->installedOption,
            'IS_INSTALL_OPT_CHANGED'  => false,
            'CTX'                     => $ctx,
            'MCP'                     => $mcp,
            'WORKFLOW_LABELS'         => array_values($this->getWorkflowLabels()),
            'WORKFLOW_DESCS'          => array_values($this->getWorkflowDescs()),
            'WORKFLOW_CODES'          => array_keys($this->getWorkflowDescs()),
            'UDB_ALLOWED_DOCS'        => $this->getEntityMgr()->getUDBAllowedDocs(),
            'APPROVALDELEGATE_OP'     => GetOperationId($this->mod . '/activities/poapprovaldelegate'),
        );

        /**
         * Specific behavior for glaccounts
         * When grid is set to readonly (ie. at entity level), glaccounts don't show up properly
         * The following business logic aims at fixing it
         */
        if ($mcp && $ctx) {
            // In this case, documents grid is largely set to readonly, only entity level documents can be edited
            foreach ($obj['DOCUMENT'] as $key => $value) {
                if (strstr($key, '_DEFREVACCT')) {
                    /**
                     * We create an array 'DEFREVACCT' containing glaccounts properly formatted
                     * This array will become a global JS variable thanks to this current method
                     */
                    $toReturn['DEFREVACCT'][$key] = $value;
                }
            }
        }

        $toReturn['isSOModuleSubscribed'] = IsInstalled(Globals::$g->kSOid);
        return $toReturn;
    }

    /**
     * Override parent's method
     *
     * @param array   &$buttons          buttons
     * @param string  $id                id
     * @param string  $name              name
     * @param string  $button            button
     * @param string  $action            action
     * @param bool    $submitData        whether submit data or not
     * @param string  $jsCode            javascript
     * @param bool    $serverAction      server action
     * @param bool    $disableValidation whether disable validation or not
     * @param string  $args              parameters
     */
    protected function setButtonDetails(&$buttons, $id, $name, $button, $action, $submitData = true, $jsCode = '',
        $serverAction = true, $disableValidation = false, $args = ''
    ) {
        if ($id == Editor_SaveBtnID) {
            if ($button) {
                $jsCode = 'beforeSubmitJS()';
                $buttons[] = $this->createAction(
                    $id, $name, $button, $action, $submitData, $jsCode, $serverAction, $disableValidation, $args
                );
            }
        } else {
            parent::setButtonDetails(
                $buttons, $id, $name, $button, $action, $submitData, $jsCode, $serverAction, $disableValidation, $args
            );
        }
    }

    /**
     * Override parent's method
     *
     * @return bool
     */
    protected function canDuplicate()
    {
        return false;
    }

    /**
     * Get workflow labels
     * Since labels are different according to module, this method must be overridden into specific module editors
     *
     * @return array
     */
    protected function getWorkflowLabels()
    {
        return array();
    }

    /**
     * Get workflow descriptions
     * Since descriptions are different, this method must be overridden into specific module editors
     *
     * @param bool $isInstalled
     *
     * @return array
     */

    protected function getWorkflowDescs(/** @noinspection PhpUnusedParameterInspection */ $isInstalled = false)
    {
        return array();
    }

    /**
     * Return array containing preferences for a specific document
     *
     * @param array  $documents documents
     * @param string $label     label
     *
     * @return array
     */
    private function retrieveDocPref($documents, $label)
    {
        foreach ($documents as $doc) {
            if ($doc['LABEL'] == $label) {
                return $doc;
            }
        }

        return null;
    }

    /**
     * Get document setup options path
     *
     * @param array $docInfo fieldinfo
     *
     * @return array
     */
    private function getDocumentSetupOptionsPaths($docInfo)
    {
        $paths = array();
        if (isset($docInfo)) {
            foreach ($docInfo as $info) {
                if (array_key_exists('path', $info)) {
                    array_push($paths, $info['path']);
                }
            }
        }
        return $paths;
    }

    /**
     * @return string[] Tokens required by this form's js
     */
    protected function getFormTokens() : array
    {
        $this->textTokens = array_merge($this->textTokens, [
            'IA.CONFIRM_ENABLE_MULTI_UOM',
            'IA.CONFIRM_ENABLE_SUBTOTAL_TEMPLATES',
            'IA.CONFIRM_ENABLE_KITS',
            'IA.CONFIRM_APPLY_WORKFLOW',
            'IA.ALERT_BROWSE_TO_SELECT_FILE',
            'IA.ALERT_NONE_SELECTED',
            'IA.ALERT_SELECT_NEW_WORKFLOW',
            'IA.CONFIRM_DIFFERENT_WORKFLOW'
        ]);
        return parent::getFormTokens();
    }
}