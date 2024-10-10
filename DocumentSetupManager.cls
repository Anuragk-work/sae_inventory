<?
/**
 * DocumentSetupManager
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation, All Rights Reserved
 */
require_once 'scm_util.inc';

/**
 * Manager for subscription configuration and setup of Inventory, Order Entry and Purchasing
 */
class DocumentSetupManager extends ModuleSetupManager
{

    // Sub classes to set this variable.

    /** @var string $modStr */
    public $modStr = '';

    /** @var string $mod */
    public $mod = '';

    /** @var string $modKey */
    public $modKey = '';

    /** @var string $spi */
    public $spi = '';

    /** @var string $mcpEntity */
    public $mcpEntity = '';

    /** @var string[] $_modArray */
    public $_modArray = array('inv' => '7.INV', 'po' => '9.PO', 'so' => '8.SO');

    /** @var string[] $_spiArray */
    public $_spiArray = array('inv' => 'I', 'po' => 'P', 'so' => 'S');

    /** @var string[][] $_docPars */
    public $_docPars = array();

    /** @var bool $doInitModules */
    private static $doInitModules = true;

    const EMAILTEMPLATE_SUFFIX = '_EMAILTEMPLATE';

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {
        $params['moduleKey'] = $this->_modArray[$this->mod];
        parent::__construct($params);
        $this->_docPars = DocumentSetupUtil::GetTrxDefinitionsByMod($this->_spiArray[$this->mod]);
    }

    /**
     * Stores the order of the transaction definitions in the database.
     *
     * @param array $preferences
     *
     * @return bool
     */
    private function setTrxDefinisionOrders($preferences)
    {
        $ok = true;
        global $gManagerFactory, $gErr;
        $tdManager = $gManagerFactory->getManager($this->mod . "documentparams");

        // delete all the existing TD ordinal numbers first
        $this->deletePreferencesLike("TD_RECORD#");

        // Iterate over all TDs and save their ordinal numbers.
        $docIds = $preferences['DOCIDS'] ?? [];
        $orderNumber = 1;
        foreach ($docIds as $docId) {
            $recordNo = $tdManager->GetRecordNo('DOCID', $docId, false);
            $success = $this->SetPreference('TD_RECORD#' . $recordNo, $orderNumber, true, $this->_moduleKey);
            if (!$success) {
                $msg = "Failed to store ordinal # for " . $docId;
                $gErr->addIAError('INV-0446', __FILE__ . ':' . __LINE__, $msg, ['DOC_ID' => $docId]);
            }
            $ok = $ok && $success;
            $orderNumber++;
        }
        return $ok;
    }

    /**
     * @param string        $id
     * @param string[]|null $fields
     *
     * @return array|false
     */
    public function get($id, $fields = null)
    {
        $values = parent::get($id);

        global $kINVid;
        GetModulePreferences($kINVid, $invprefs);

        $values['DEFAULT_UOMGRP'] = $this->_TransformInternalValue('DEFAULT_UOMGRP', ($invprefs['DEFAULT_UOMGRP'] ?? ''));
        $values['ENABLE_MULTI_UOM'] = $this->_TransformInternalValue('ENABLE_MULTI_UOM', ($invprefs['ENABLE_MULTI_UOM'] ?? NULL));
        $values['ENABLE_UOM_IN_REPORT'] = $this->_TransformInternalValue('ENABLE_UOM_IN_REPORT', ($invprefs['ENABLE_UOM_IN_REPORT'] ?? NULL));
        $this->transformPreferences($values);

        return $values;
    }

    /**
     * @param array $values
     */
    protected function transformPreferences(&$values)
    {
        $docTypePrefs = $this->GetDocTypePrefs($this->mod);
        $doctypes = array();
        foreach ( $docTypePrefs as $pref) {
            $doctypes[$pref['PROPERTY']] = $pref['VALUE'];
        }

        $values = array_merge($values, $this->FlatToStructured($doctypes));

        $values['USERCONTACT'] = empty($values['USERCONTACT']) ? 'false' : $values['USERCONTACT'];
        $values['CONSTRICTCONTACT'] = empty($values['CONSTRICTCONTACT']) ? 'none' : $values['CONSTRICTCONTACT'];
        $values['MCPENTRY'] = empty($values['MCPENTRY']) ? 'false' : $values['MCPENTRY'];
        $values['DISPLAYPAYMENTS'] = empty($values['DISPLAYPAYMENTS']) ? 'false' : $values['DISPLAYPAYMENTS'];
        $values['ALLOWPROCESSTRANS'] = empty($values['ALLOWPROCESSTRANS']) ? 'false' : $values['ALLOWPROCESSTRANS'];
        $values['INSTALLEDWORKFLOW'] = empty($values['INSTALLEDWORKFLOW']) ? null : $values['INSTALLEDWORKFLOW'];
        $values['MOD'] = $this->mod;

        // 'KIT' and 'DISALLOW_NEGINV' option
        if ($this->mod == 'inv' || $this->mod == 'so') {
            $values['KIT'] = IsKitEnabled() ? 'true' : 'false';
            $values['DISALLOW_NEGINV'] = (!IsNegativeInventoryAllowed()) ? 'true' : 'false';
        }
        // 'DISALLOW_QTY_CHANGE_WHENCONVERT' option
        $values['DISALLOW_QTY_CHANGE_WHENCONVERT'] = (!isQuantityChangeAllowedWhenConverting($this->mod)) ? 'true'
            : 'false';

        // SRAO :: For now the advanced is always tied to the inventory module.
        static $enableAdvanced = null;  // and we really don't need to query this more than once....
        if ($enableAdvanced === null) {
            $enableAdvanced = $this->GetPreference('ENABLE_ADVANCED', Globals::$g->kINVid);
        }
        if ($enableAdvanced == 'true') {
            $values['ENABLE_ADVANCED'] = $enableAdvanced;
        }

    }

    /**
     * Override parent's method
     *
     * @param array &$values values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "DocumentSetupManager::Add";
        $ok = true;

        $this->_QM->beginTrx($source);

        /*
         * Bypass cache so as to use up to date installed module information,
         * but do it only once.
         */
        if (self::$doInitModules) {
            InitModules(false);
            self::$doInitModules = false;
        }
        $ok = $ok && $this->collectSetupPreferences($values);
        $ok = $ok && $this->validateInputs($values);
        $ok = $ok && parent::regularAdd($values);
        $ok = $ok && $this->setOtherModulePreferences($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * Override parent's method
     *
     * @param array &$values values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $source = "SetupManager::Set";
        $ok = true;

        $this->_QM->beginTrx($source);

        /*
         * Bypass cache so as to use up to date installed module information,
         * but do it only once.
         */
        if (self::$doInitModules) {
            InitModules(false);
            self::$doInitModules = false;
        }
        $ok = $ok && $this->collectSetupPreferences($values);
        $ok = $ok && $this->validateInputs($values);
        $ok = $ok && parent::regularSet($values);
        $ok = $ok && $this->setOtherModulePreferences($values);
        $ok = $ok && $this->installOtherRequiredSCMObjects();

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param array $preferences
     *
     * @return bool
     */
    public function SetByRef(&$preferences)
    {
        global $gManagerFactory, $gErr;

        $ok = $this->setTrxDefinisionOrders($preferences);

        $journals = [];
        // 'S' => 'Standard',  'U' => 'User Defined',
        $allowedBookTypes = ['S', 'U'];
        $jrnlList = GetJournalTypeMap();
        foreach ($jrnlList as $journal) {
            if ($journal['STATISTICAL'] == 'F' && in_array($journal['BOOKTYPE'], $allowedBookTypes)) {
                $journals[] = $journal['SYMBOL'];
            }
        }

        $documentExists = isset($preferences['DOCUMENT']);
        if ($documentExists) {
            foreach ($preferences['DOCUMENT'] as $key => $thisJrnl) {
                if (preg_match("/^(.*)_JOURNAL$/i", $key)) {
                    list($thisJrnl) = explode('--', $thisJrnl);
                    if (!in_array($thisJrnl, $journals)) {
                        $msg = "'" . $thisJrnl . "' is not a valid journal in the system.";
                        $gErr->addIAError('INV-0447', __FILE__ . ':' . __LINE__, $msg, ['THIS_JRNL' => $thisJrnl]);
                        return false;
                    }
                }
            }
        }

        $tmplList = EntityManager::GetListQuick('emailtemplate', 'RECORDNO');
        // init the $emailTemplates to be empty array due to PHP 8.1 exception
        $emailTemplates = array();
        foreach ($tmplList as $tmpl) {
            $emailTemplates[] = $tmpl['RECORDNO'];
        }

        if ($documentExists) {
            foreach ($preferences['DOCUMENT'] as $key => $thisTempl) {
                if (preg_match("/^(.*)_EMAILTEMPLATE$/i", $key)) {
                    if (!in_array($thisTempl, $emailTemplates) && !is_null($thisTempl)) {
                        $label = rtrim($key, '_EMAILTEMPLATE');
                        $label = implode(' ', explode('_', $label));
                        $msg = "The email template selected for '" . $label . "' is not a valid in the system.";
                        $gErr->addIAError('INV-0448', __FILE__ . ':' . __LINE__, $msg, ['LABEL' => $label]);
                        return false;
                    }
                }
            }
        }

        //	Check for format of all the field values here(including ITEMPRECISION)
        if (!$this->_ValidateNew($preferences)) {
            $msg = "Validate " . $this->_entity . " record failed!";
            $gErr->addIAError('INV-0449', __FILE__ . ':' . __LINE__, $msg, ['ENTITY' => $this->_entity]);
            /** @noinspection PhpUndefinedVariableInspection */
            epp("$source: Error: $msg");
            return false;
        }

        if (!isset($preferences['DEFAULT_UOMGRP']) || $preferences['DEFAULT_UOMGRP'] == '') {
            $preferences['DEFAULT_UOMGRP'] = 'Count';
        }

        if ($preferences['DEFAULT_UOMGRP'] && $preferences['DEFAULT_UOMGRP'] != '') {
            // As of now we save the module as INV for default uom group.
            global $kINVid;

            $uomMgr = $gManagerFactory->getManager('uom');
            $querySpec = array(
                'selects' => array('NAME'),
                'filters' => array(array(array('ISSYSTEM', '=', 'true')))
            );
            $list = $uomMgr->GetList($querySpec);

            // If there are no system UOM groups set, we do not execute the validation process
            // Because user might be saving the configuration without installing a workflow
            if (!empty($list)) {
                $res = $uomMgr->get($preferences['DEFAULT_UOMGRP']);

                if (!$res) {
                    $msg = "'" . $preferences['DEFAULT_UOMGRP'] . "' is not a valid UOM Group in the system.";
                    $gErr->addIAError(
                        'INV-0450', __FILE__ . ':' . __LINE__,
                        $msg, ['PREFERENCES_DEFAULT_UOMGRP' => $preferences['DEFAULT_UOMGRP']],
                        "Please select a valid UOM Group", []
                    );
                    $ok = false;
                }

            }
            $ok = $ok && $this->SetPreference('DEFAULT_UOMGRP', $preferences['DEFAULT_UOMGRP'], 1, $kINVid);

            $auditData['DEFAULT_UOMGRP'] = $preferences['DEFAULT_UOMGRP'];

            // We have to clear the default uom group preference so that its not saved again
            //  for the corresponding module.
            unset($preferences['DEFAULT_UOMGRP']);
        }

        if (isset($preferences['ENABLE_MULTI_UOM']) && $preferences['ENABLE_MULTI_UOM'] != '') {
            global $kINVid;

            $preferences['ENABLE_MULTI_UOM'] = $this->_TransformExternalValue(
                'ENABLE_MULTI_UOM', $preferences['ENABLE_MULTI_UOM']
            );

            $ok = $ok && $this->SetPreference('ENABLE_MULTI_UOM', $preferences['ENABLE_MULTI_UOM'], 1, $kINVid);

            $auditData['ENABLED_MULTI_UOM'] = $preferences['ENABLED_MULTI_UOM'];

            // We have to clear the enable multiple cost preference so that its not saved again
            // for the corresponding module.
            unset($preferences['ENABLE_MULTI_UOM']);
        }
        if (isset($preferences['ENABLE_UOM_IN_REPORT']) && $preferences['ENABLE_UOM_IN_REPORT'] != '') {
            global $kINVid;
            $preferences['ENABLE_UOM_IN_REPORT'] = $this->_TransformExternalValue(
                'ENABLE_UOM_IN_REPORT', $preferences['ENABLE_UOM_IN_REPORT']
            );
            $ok = $ok && $this->SetPreference('ENABLE_UOM_IN_REPORT', $preferences['ENABLE_UOM_IN_REPORT'], 1, $kINVid);
            $auditData['ENABLE_UOM_IN_REPORT'] = $preferences['ENABLE_UOM_IN_REPORT'];
            unset($preferences['ENABLE_UOM_IN_REPORT']);
        }

        //  Cache the parts that are removed.  Subsequent caching will merge this with the other pref data.
        if (!empty($auditData)) {
            $auditTrailSession = AuditTrailSession::getInstance();
            /** @noinspection PhpUndefinedVariableInspection */
            $auditTrailSession->cacheAuditRecord('modulepref', $kINVid, $auditData);
        }

        $ok = $ok && parent::setByRef($preferences);

        return $ok;
    }

    /**
     * Collect setup preferences
     *
     * @param array &$values preferences
     *
     * @return bool
     */
    protected function collectSetupPreferences(&$values)
    {
        if (empty($values['DISALLOW_QTY_CHANGE_WHENCONVERT'])) {
            $values['DISALLOW_QTY_CHANGE_WHENCONVERT'] = 'false';
        }

        return true;
    }

    /**
     * Returns an array containing the list of preferences that could be overriden at the entity level
     *
     * @return array
     */
    protected function getValidPreferencesAtEntityLevel()
    {
        return array();
    }

    /**
     * @param string[] &$preferences
     * @param string   $key
     *
     * @return bool
     */
    protected function includePreference(&$preferences, $key)
    {
        $ok = true;

        // At entity level, we should be saving transaction definitions that are only related to the current entity
        if (IsMultiEntityCompany() && GetContextLocation()) {
            // Preventing location keys flags from being saved in the database
            if (isl_str_startswith($key, 'LOCATIONKEYS.')) {
                $ok = false;
            }

            if (isl_str_startswith($key, 'DOCUMENT.') || isl_str_startswith($key, 'DOCTYPES.')) {
                // We need to check if the current preferences, related to a transaction definition
                // Is actually related to the current entity
                if (isl_str_startswith($key, 'DOCTYPES.')) {
                    $tdPath = isl_substr($key, isl_strlen('DOCTYPES.'));
                } else {
                    $tdPath = isl_substr($key, isl_strlen('DOCUMENT.'));
                    $tdPath = isl_substr($tdPath, 0, -(isl_strlen($tdPath) - isl_strrpos($tdPath, '_')));
                }

                if (empty($preferences['LOCATIONKEYS.' . $tdPath])) {
                    $ok = false;
                }
            }

            // Most of preferences at entity level must be synced with the root: don't save these at entity level
            // Root configuration will therefore be used
            if (!in_array($key, $this->getValidPreferencesAtEntityLevel())
                && !isl_str_startswith($key, 'DOCUMENT.')
                && !isl_str_startswith($key, 'DOCTYPES.')
            ) {
                $ok = false;
            }
        }

        return ($ok) ? parent::includePreference($preferences, $key) : $ok;
    }


    /**
     * Validate inputs
     *
     * @param array &$values values
     *
     * @return bool
     */
    protected function validateInputs(&$values)
    {

        $source = 'SetupManager::Set';
        $ok = $this->_QM->beginTrx($source);

        if (!$this->mod) {
            return false;
        }

        if ($values['ENABLE_ADVANCED'] == 'true') {
            foreach ($values['DOCTYPES'] as $key => $value) {
                $newkey = $values['DOCIDS'][$key];
                if ($value == 'true') {
                    $ok = $ok && $this->DocParSetStatus($newkey, 'T', 'SINGLE');
                } else {
                    $ok = $ok && $this->DocParSetStatus($newkey, 'F', 'SINGLE');
                }
            }
        } else {
            // For a simple company all the transaction definitions are always enabled.
            $this->DocParSetStatus($this->spi, 'T', 'ALL');
        }

        if (empty($values['DISPLAYPAYMENTS']) || $values['DISPLAYPAYMENTS'] == 'false') {
            unset($values['DISPLAYPAYMENTS']);
        }

        if (array_key_exists('INSTALLEDWORKFLOW', $values)) {
            if (empty($values['INSTALLEDWORKFLOW']) || $values['INSTALLEDWORKFLOW'] == 'false') {
                unset($values['INSTALLEDWORKFLOW']);
            }
        }

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Could not configure application!";
            Globals::$g->gErr->addIAError('INV-0451', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param string $emailTemplateID
     *
     * @return bool
     */
    public function isEmailTemplateUsed($emailTemplateID)
    {
        $retVal = false;
        $prefs = $this->get('');
        foreach ($prefs['DOCUMENT'] as $key => $val) {
            if (isl_str_endswith($key, self::EMAILTEMPLATE_SUFFIX)) {
                if ($val === $emailTemplateID) {
                    $retVal = true;
                    break;
                }
            }
        }
        return $retVal;
    }

    /**
     * @param string[] $doctypes
     *
     * @return array
     */
    public function getEmailTemplateIDs($doctypes)
    {
        $retVal = [];

        $prefs = $this->get('');
        foreach ($doctypes as $doctype) {
            $prop = str_replace(' ', '_', $doctype) . self::EMAILTEMPLATE_SUFFIX;
            if (isset($prefs['DOCUMENT'][$prop])) {
                $retVal[$doctype] = $prefs['DOCUMENT'][$prop];
            }
        }

        return $retVal;
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
        $ok = true;

        if (!GetContextLocation()) {
            // The following logic should be processed only at root level
            if ($this->mod == 'inv' || $this->mod == 'so') {
                // 'KIT' option should be synchronized
                $kit = ($values['KIT'] == 'true') ? 'T' : 'F';
                // Set preference in both module
                $ok = $ok && $this->SetPreference('KIT', $kit, 1, Globals::$g->kINVid);
                $ok = $ok && $this->SetPreference('KIT', $kit, 1, Globals::$g->kSOid);

                // 'DISALLOW_NEGINV' option should be synchronized
                $disNegInv = ($values['DISALLOW_NEGINV'] == 'true') ? 'T' : 'F';
                // Set preference in both module
                $ok = $ok && $this->SetPreference('DISALLOW_NEGINV', $disNegInv, 1, Globals::$g->kINVid);
                $ok = $ok && $this->SetPreference('DISALLOW_NEGINV', $disNegInv, 1, Globals::$g->kSOid);
            }

            // SRAO :: For now the advanced is always tied to the inventory module.
            $ok = $ok && $this->SetPreference('ENABLE_ADVANCED', $values['ENABLE_ADVANCED'], 1, Globals::$g->kINVid);
            if ($values['ENABLE_ADVANCED'] && $values['ENABLE_ADVANCED'] === "true") {
                $ok = $ok && $this->SetPreference('OFF_GLACCOUNT', '', 1, Globals::$g->kINVid);
                $ok = $ok && $this->SetPreference('OFF_GLACCOUNT', '', 1, Globals::$g->kSOid);
                $ok = $ok && $this->SetPreference('OFF_GLACCOUNT', '', 1, Globals::$g->kPOid);
                $ok = $ok && $this->SetPreference('DIRECT_GLACCOUNT', '', 1, Globals::$g->kPOid);
                $ok = $ok && $this->SetPreference('DIRECT_GLACCOUNT', '', 1, Globals::$g->kSOid);
                $ok = $ok && $this->SetPreference('SCRAP_GLACCOUNT', '', 1, Globals::$g->kINVid);
                $ok = $ok && $this->SetPreference('DAM_GLACCOUNT', '', 1, Globals::$g->kINVid);
                $ok = $ok && $this->SetPreference('INV_GLACCOUNT', '', 1, Globals::$g->kINVid);
            }
        }

        return $ok;
    }

    /**
     * MCP preferences setter
     *
     * @param array $values values
     *
     * @return bool
     */
    public function SetMCPPreferences($values)
    {
        $ok = true;

        // Set the value for creating, editing and deleting foreign currency documents
        if (IsMCPSubscribed()) {
            $mcpentry = $values['MCPENTRY'];

            $ismcpEnabled = IsMCPEnabled($this->mod);

            // We are doing the currency conversion for all the historical transactions
            // only when the user enables 'Foreign currency' preference in the respective modules ('OE','PO' and 'INV')
            // Conversion should not happen when the user disables the preference
            if ($mcpentry == "true" && !$ismcpEnabled) {
                $entity = $this->mcpEntity;
                $ok = $ok && $this->UpdateMCPValues($entity);
            }
        }

        return $ok;
    }

    /**
     * Update MCP values
     *
     * @param string $entity entity name
     *
     * @return bool
     */
    public function UpdateMCPValues($entity)
    {
        $gErr = Globals::$g->gErr;
        $source = "SetupManager::UpdateMCPValues";

        // get the base currency of the company
        $baseCurrency = GetBaseCurrency();
        $_cny = GetMyCompany();

        /**
         * @todo remplace count
         */
        // get the count of the documents in OE/PO
        $qry = "SELECT count(1) count FROM dochdr WHERE entity LIKE :1 AND cny#=:2";
        $doccount = QueryResult(array($qry, $entity, $_cny));

        if ($doccount[0]['COUNT'] == 0) {
            return true;
        }

        // begin transaction
        $ok = $this->_QM->beginTrx($source);

        // update docpar
        $updateDOCPAR
            = "UPDATE docpar
            SET exch_rate_type_id = nvl(exch_rate_type_id,-1)
            WHERE cny#=:1 AND sale_pur_trans = :2";
        $ok = $ok && ExecStmt(array($updateDOCPAR, $_cny, $this->spi));

        // recurdochdr
        $updateRECURDOCHDR
            = "UPDATE recurdochdrmst
            SET currency=NVL(currency, :1), trx_subtotal=NVL(trx_subtotal, subtotal), trx_total=NVL(trx_total,total)
            WHERE cny#=:2 AND entity LIKE :3";
        $ok = $ok && ExecStmt(array($updateRECURDOCHDR, $baseCurrency, $_cny, $entity));

        // recurdocentry
        $updateRECURDOCENTRY
            = "UPDATE recurdocentry
            SET currency=NVL(currency,:1), trx_price=NVL(trx_price,uiprice), trx_value=NVL(trx_value,uivalue)
            WHERE cny#=:2 AND EXISTS (SELECT 1 FROM recurdochdrmst
                WHERE record# = recurdocentry.recurdochdrkey AND entity LIKE :3 AND cny# = recurdocentry.cny#)";
        $ok = $ok && ExecStmt(array($updateRECURDOCENTRY, $baseCurrency, $_cny, $entity));

        // recursubtotals
        $updateRECURSUBTOTALS
            = "UPDATE recursubtotals
            SET trx_absval=NVL(trx_absval,absval), trx_total=NVL(trx_total, total)
            WHERE cny#=:1 AND EXISTS (SELECT 1 FROM recurdochdrmst
                WHERE record# = recursubtotals.recurdochdrkey AND entity LIKE :2 AND cny# = recursubtotals.cny#)";
        $ok = $ok && ExecStmt(array($updateRECURSUBTOTALS, $_cny, $entity));

        // dochdr
        $updateDOCHDR
            = "UPDATE dochdrmst
            SET currency=NVL(currency, :1), trx_subtotal=NVL(trx_subtotal, subtotal), trx_total=NVL(trx_total,total)
            WHERE cny#=:2 AND entity LIKE :3";
        $ok = $ok && ExecStmt(array($updateDOCHDR, $baseCurrency, $_cny, $entity));

        // docentry
        $updateDOCENTRY
            = "UPDATE docentry
            SET currency=NVL(currency,:1), trx_price=NVL(trx_price,uiprice), trx_value=NVL(trx_value,uivalue)
            WHERE cny#=:2 AND EXISTS (SELECT 1 FROM dochdrmst
                WHERE record# = docentry.dochdrkey AND entity LIKE :3 AND cny# = docentry.cny#)";
        $ok = $ok && ExecStmt(array($updateDOCENTRY, $baseCurrency, $_cny, $entity));

        // dochdrsubtotals
        $updateDOCHDRSUBTOTALS
            = "UPDATE dochdrsubtotals
            SET trx_absval=NVL(trx_absval,absval), trx_total=NVL(trx_total, total)
            WHERE cny#=:1 AND EXISTS (SELECT 1 FROM dochdrmst
                WHERE record# = dochdrsubtotals.dochdrkey AND entity LIKE :2 AND cny# = dochdrsubtotals.cny#)";
        $ok = $ok && ExecStmt(array($updateDOCHDRSUBTOTALS, $_cny, $entity));

        // commit transaction
        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $msg = "Unable to initialize MCP data";
            $gErr->addIAError('INV-0452', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * Generate dynamically the schema, object and fieldinfo for the document setup
     *
     * @param string $mod module
     *
     * @return array
     */
    public static function GenerateSchemaDocSetupInfo($mod)
    {
        $ret = array('schema' => array(), 'object' => array(), 'fieldinfo' => array());

        $setup_schema = DocumentSetupUtil::GenerateDocumentSetupSchema($mod);
        $ret['schema'] = $setup_schema['DOCUMENT'];
        $ret['fieldinfo'] = DocumentSetupUtil::GenerateDocumentSetupInfo($mod, true);

        $object = array_keys($setup_schema['DOCUMENT']);
        foreach ($object as &$element) {
            $element = 'DOCUMENT.' . $element;
        }
        $ret['object'] = $object;

        return $ret;
    }

    /**
     * Generate the fieldinfo for the document configuration
     *
     * @param string $mod module
     *
     * @return array
     */
    public static function GenerateSchemaDocInfo($mod)
    {
        $gUntransformedBooleanType = Globals::$g->gUntransformedBooleanType;

        $ret = DocumentSetupUtil::GetTrxDefinitionsByMod($mod);
        // Add documents in schema according to their class
        $sortedSchema = array();
        foreach ($ret as $docpar) {
            $docid = $docpar['DOCID'];
            $docid_path = str_replace(' ', '_', $docid);

            $fieldInfo = array(
                'path' => 'DOCTYPES.' . $docid_path,
                'desc' => $docid,
                'fullname' => $docid,
                'type' => $gUntransformedBooleanType,
                'default' => 'false',
            );

            $sortedSchema['schema'][$docid_path] = 'foo';
            $sortedSchema['object'][] = 'DOCTYPES.' . $docid_path;
            $sortedSchema['fieldinfo'][] = $fieldInfo;
        }

        return $sortedSchema;
    }

    /**
     * Definition of dimension fields info
     *
     * @param    bool       $merged
     *
     * @return array
     */
    public static function proxy_getDimensionPreferencesInfo($merged = false)
    {
        $dimUsed = parent::proxy_getDimensionPreferencesInfo();

        $dimObjInfo = array();
        $gBooleanType = Globals::$g->gBooleanType;
        $ctx = GetContextLocation();

        foreach ($dimUsed as $dimid => $dim) {
            $dimObjInfo[$dimid] = $dim;
            $dimObjInfo[$dimid]['dimfieldid'] = $dim['dimensionid'];
            $dimObjInfo[$dimid]['rightSideLabel'] = true;
            $dimObjInfo[$dimid]['path'] = isl_strtoupper($dim['dimensionid']);
            $dimObjInfo[$dimid]['type'] = $gBooleanType;
            if (IsMultiEntityCompany() && $ctx) {
                $dimObjInfo[$dimid]['readonly'] = true;
            }
        }

        return $dimObjInfo;
    }

    /**
     * GetDocTypePrefs
     *
     * @param string $mod module
     *
     * @return array
     */
    public function GetDocTypePrefs($mod)
    {
        if ($this->_cny) {

            static $cache = [];                 // lets get this just once.  Clients tend to do this in a loop....
            if ( ! isset($cache[$mod])) {
                $qryKey = 'QRY_SUBSRIPTIONWIZ_GETPREFS';
                $qry[$qryKey] = array(
                    'QUERY'    => 'select * from modulepref where modulekey = ? and property like ? and cny# = ?',
                    'ARGTYPES' => array('text', 'text', 'integer')
                );
                $this->_QM->LoadQueries($qry);

                $args = array($this->_modArray[$mod], 'DOCTYPES.%', $this->_cny);

                $cache[$mod] = $this->DoQuery($qryKey, $args);
            }

            return $cache[$mod];
        } else {
            return array();
        }
    }

    /**
     * DocParSetStatus
     *
     * @param string $name name
     * @param string $val  value
     * @param string $type type
     *
     * @return array
     */
    public function DocParSetStatus($name, $val, $type = 'SINGLE')
    {
        $qryKey = 'QRY_SUBSRIPTIONWIZ_INACTIVATE';
        $qryAllKey = 'QRY_SUBSRIPTIONWIZ_INACTIVATE_ALL';

        $qry[$qryAllKey] = array(
            'QUERY' => "update docparmst set status = ? where sale_pur_trans = ? and cny# = ? and status != 'F' ",
            'ARGTYPES' => array('text', 'text', 'integer')
        );
        $qry[$qryKey] = array(
            'QUERY' => "update docparmst set status = ? where docid = ? and cny# = ? ",
            'ARGTYPES' => array('text', 'text', 'integer')
        );
        $this->_QM->LoadQueries($qry);

        if ($type == 'ALL') {
            $QRY = $qryAllKey;
        } else {
            $QRY = $qryKey;
        }
        $args = array($val, $name, $this->_cny);

        return $this->DoQuery($QRY, $args);
    }

    /**
     * Install workflow
     *
     * @param string $installoption workflow to install
     *
     * @return bool
     */
    public function InstallWorkflow($installoption)
    {
        import("WorkflowPackageManager");
        $wflwMgr = new WorkflowPackageManager();
        return $wflwMgr->InstallWorflowTemplate($installoption, $this->mod);
    }

    /**
     * Export workflow
     *
     * @return bool
     */
    public function ExportWorkflow()
    {
        import("WorkflowPackageManager");
        WorkflowPackageManager::ExportDocParDefinitions($this->mod);

        return true;
    }

    /**
     * UpdateInstalledDefinitions
     *
     * @param array &$obj entity
     *
     * @return bool
     */
    public function UpdateInstalledDefinitions(&$obj)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $docParMgr = $gManagerFactory->getManager($this->mod . "documentparams");

        $filter = array(array(array('STATUS', '=', 'active')));
        $params = array('filters' => $filter);
        $docparlist = $docParMgr->GetList($params);

        $docTypes = array();
        foreach ( $docparlist ?? [] as $docpar) {
            $newkey = str_replace(' ', '_', $docpar['DOCID']);
            $docTypes[] = $newkey;
        }

        foreach ( $obj['DOCTYPES'] ?? [] as $key => $value) {
            if (in_array($key, $docTypes)) {
                $obj['DOCTYPES'][$key] = 'true';
            } else {
                $obj['DOCTYPES'][$key] = 'false';
            }
        }

        return true;
    }

    /**
     * Get all the documents which allow to post to a User Defined Journal
     *
     * @return array
     */
    public function getUDBAllowedDocs()
    {
        return array();
    }

    /**
     * @param array $preferences
     *
     * @return bool
     */
    protected function defaultJournalsByMod(/** @noinspection PhpUnusedParameterInspection */ &$preferences)
    {
        return true;
    }

    /**
     * @param array     $preferences
     * @param string    $mod
     *
     * @return bool
     */
    protected function defaultJournals(&$preferences, $mod)
    {

        $invJournal = '';
        $prJournal = '';
        $rrJournal = '';

        $ret = DocumentSetupUtil::GetTrxDefinitionsByMod($mod);

        if (count($ret) > 0) {

            $docParInfo = array();
            foreach ($ret as $row) {
                $doc4path = str_replace(' ', '_', $row['DOCID']);
                $docParInfo[$doc4path] = $row;
            }

            $res = DocumentSetupUtil::GenerateDocumentSetupSchema($mod);

            foreach ( $res['DOCUMENT'] as $key => $value) {
                if (!isset($preferences['DOCUMENT'][$key]) || $preferences['DOCUMENT'][$key] == ''
                    || $preferences['DOCUMENT'][$key] == 'dummy'
                ) {
                    $docID = isl_substr($key, 0, isl_strrpos($key, "_"));

                    if ($docParInfo[$docID]['UPDINV'] != 'F' || $docParInfo[$docID]['POSTTOGL'] == 'T') {
                        $jrnl = $docID . "_JOURNAL";
                        if (!isset($preferences['DOCUMENT'][$jrnl]) || $preferences['DOCUMENT'][$jrnl] == '') {

                            if ($docParInfo[$docID]['UPDGL'] == 'A') {
                                if ($prJournal == '') {
                                    $prJournal = $this->GetDefPRJournal();
                                }
                                $preferences['DOCUMENT'][$jrnl] = $prJournal;
                            } else {
                                if ($invJournal == '') {
                                    $invJournal = $this->GetDefInventoryJournal();
                                }
                                $preferences['DOCUMENT'][$jrnl] = $invJournal;
                            }

                        }
                    }

                    $this->PrepPRInvGLJournal($docParInfo, $preferences, $docID);

                    if ($docParInfo[$docID]['ENABLEREVREC'] == 'T') {
                        $rrjrnl = $docID . "_REVRECJOURNAL";
                        if (!isset($preferences['DOCUMENT'][$rrjrnl]) || $preferences['DOCUMENT'][$rrjrnl] == '') {
                            if ($rrJournal == '') {
                                $rrJournal = $this->GetDefRRJournal();
                            }
                            $preferences['DOCUMENT'][$rrjrnl] = $rrJournal;
                        }
                    }

                }
            }
        }

        return true;
    }

    /**
     * @return array
     */
    protected function GetDefInventoryJournal()
    {
        $jrnl = array('SYMBOL' => 'IJ', 'TITLE' => 'Inventory Journal', 'STATUS' => 'active');
        return $this->GetGLJournal($jrnl);
    }

    /**
     * @return bool
     */
    protected function GetDefPRJournal()
    {
        return true;
    }

    /**
     * @return bool
     */
    protected function GetDefDirectGLJournal()
    {
        return true;
    }

    /**
     * @param array   $docParInfo
     * @param array   $preferences
     * @param string  $docID
     *
     * @return bool
     */
    protected function PrepPRInvGLJournal($docParInfo, &$preferences, $docID){
        if ($docParInfo[$docID]['UPDGL'] == 'G') {
            $prjrnl = $docID . "_PRINVJOURNAL";
            if (!isset($preferences['DOCUMENT'][$prjrnl]) || $preferences['DOCUMENT'][$prjrnl] == '') {
                /** @noinspection PhpUndefinedVariableInspection */
                if ( $prDirectGLINVJournal == '') {
                    $prDirectGLINVJournal = $this->GetDefDirectGLJournal();
                }
                $preferences['DOCUMENT'][$prjrnl] = $prDirectGLINVJournal;
            }
        }
        return true;
    }

    /**
     * @return bool
     */
    protected function GetDefRRJournal()
    {
        return true;
    }

    /**
     * @param array $jrnl
     *
     * @return array
     */
    protected function GetGLJournal($jrnl)
    {
        global $gManagerFactory;

        // check if the gljournal already exists.
        /** @var JournalManager $journalMgr */
        $journalMgr = $gManagerFactory->getManager('journal');
        $res = $journalMgr->Get($jrnl['SYMBOL']);

        // if doesnt exists create one.
        if (!$res || !isset($res['SYMBOL'])) {
            $journalMgr->add($jrnl);
        }

        return $jrnl['SYMBOL'];
    }

    /**
     * @return bool
     */
    public function SetDefaultSetupForModule()
    {
        $ok = true;

        $setupInfo = $this->get('');
        if (!empty(Request::$r->_installoption) && $this->mod == 'po') {
            /** @var POSetupManager $this */
            $this->cleanUpApprovalProcess($setupInfo);
        }

        $docSchema = DocumentSetupUtil::GenerateDocumentSetupSchema($this->modStr);

        // This is needed to dynamically set the schema info so that set works.
        $setupSchema = $this->_schemas[$this->mod . 'setup'];
        $this->_schemas[$this->mod . 'setup']['schema'] = INTACCTarray_merge($setupSchema['schema'], $docSchema);

        $defSetupInfo = INTACCTarray_merge($setupInfo, $docSchema);

        foreach ( $defSetupInfo['DOCUMENT'] as $key => $value) {
            if (preg_match("/^(.*)BATCH$/i", $key)) {
                $defSetupInfo['DOCUMENT'][$key] = 'Daily';
            }
            if (preg_match("/^(.*)JOURNAL$/i", $key)) {
                if ($defSetupInfo['DOCUMENT'][$key] == 'dummy') {
                    $defSetupInfo['DOCUMENT'][$key] = '';
                }
            }
            if (preg_match("/^(.*)_EMAILTEMPLATE$/i", $key)) {
                if ($defSetupInfo['DOCUMENT'][$key] == 'dummy') {
                    unset($defSetupInfo['DOCUMENT'][$key]);
                }
            }
        }

        $ok = $ok && $this->defaultJournalsByMod($defSetupInfo);

        $ok = $ok && $this->set($defSetupInfo);

        return $ok;
    }

    /**
     * Copies all the root level TD ordinal number values to the entity level.
     *
     * @return bool
     */
    function copyRootTDOrderToEntity()
    {
        $contextLocation = GetContextLocation();
        if ($contextLocation) {
            $stmt = array();
            $stmt[0] = "insert into modulepref (CNY#, MODULEKEY, PROPERTY, VALUE, LOCATIONKEY) " .
                "select CNY#, MODULEKEY, PROPERTY, VALUE, $contextLocation " .
                "from modulepref " .
                "where CNY# = :1 and MODULEKEY = :2 and property like 'TD_RECORD#%' and LOCATIONKEY is null " .
                "and property not in " .
                "(select property from MODULEPREF where CNY# = :3 and MODULEKEY = :4 and property ".
                "like 'TD_RECORD#%' and LOCATIONKEY = :5)";
            $stmt[1] = $this->_cny;
            $stmt[2] = $this->_moduleKey;
            $stmt[3] = $this->_cny;
            $stmt[4] = $this->_moduleKey;
            $stmt[5] = $contextLocation;

            ExecStmt($stmt);

        }
        return true;
    }


    /**
     * Return the array of ordinal numbers for the TDs specified for an
     * entity but not for the root.
     * Returns false if no entity specific ordinal number is detected.
     *
     * @return string[][]|false|null   null at root, false on error
     */
    public function getEntitySpecificTDOrdinalNumbers()
    {
        $contextLocation = GetContextLocation();
        if ($contextLocation) {

            $args = array($this->_cny, $this->_moduleKey, $contextLocation, $this->_cny, $this->_moduleKey);
            $argTypes = array('integer', 'text', 'integer', 'integer', 'text');

            $query = array(
                'QUERY' =>
                    "select property from MODULEPREF where CNY# = ? and MODULEKEY = ? and property ".
                    "like 'TD_RECORD#%' and LOCATIONKEY = ? " .
                    "minus " .
                    "select property from MODULEPREF where CNY# = ? and MODULEKEY = ? and property ".
                    "like 'TD_RECORD#%' and LOCATIONKEY is null",
                'ARGTYPES' => $argTypes

            );
            $result = $this->DoCustomQuery($query, $args, true);
            return isset($result[0]) ? $result : false;
        }

        return null;
    }

    /**
     * Dynamically populates the entity with the schema and object
     * information for the selected TD setup object.
     */
    function MergeObjectSchema()
    {
        parent::MergeObjectSchema();

        $tdsetup = &$this->_schemas[$this->_entity];
        $schema = &$this->_schemas[$this->_entity]['schema'];

        $schema_info = self::GenerateSchemaDocInfo($this->spi);
        $setup_info = self::GenerateSchemaDocSetupInfo($this->spi);

        $schema['DOCTYPES'] = $schema_info['schema'] ?? [];
        $schema['DOCUMENT'] = $setup_info['schema'] ?? [];

        if (util::countOrZero($schema_info['object']) > 0) {
            $tdsetup['object']
                = INTACCTarray_merge($tdsetup['object'], $schema_info['object']);
        }
        if (util::countOrZero($setup_info['object']) > 0) {
            $tdsetup['object']
                = INTACCTarray_merge($tdsetup['object'], $setup_info['object']);
        }
    }

    /**
     * Dynamically populates the entity with the field
     * information for the selected TD setup object.
     */
    public function MergeFieldInfo()
    {
        parent::MergeFieldInfo();

        $tdsetup = &$this->_schemas[$this->_entity];

        $schema_info = self::GenerateSchemaDocInfo($this->spi);
        $setup_info = self::GenerateSchemaDocSetupInfo($this->spi);

        if (util::countOrZero($schema_info['fieldinfo']) > 0){
            $tdsetup['fieldinfo']
                = INTACCTarray_merge($tdsetup['fieldinfo'], $schema_info['fieldinfo']);
            $tdsetup['basefieldinfo']
                = INTACCTarray_merge($tdsetup['basefieldinfo'], $schema_info['fieldinfo']);
        }

        if (util::countOrZero($setup_info['fieldinfo']) > 0) {
            $tdsetup['fieldinfo']
                = INTACCTarray_merge($tdsetup['fieldinfo'], $setup_info['fieldinfo']);
            $tdsetup['basefieldinfo']
                = INTACCTarray_merge($tdsetup['basefieldinfo'], $setup_info['fieldinfo']);
        }
    }

    /**
     * @return mixed|string
     */
    function getConstrictedPref()
    {
        $prefs = $this->get('');

        $toReturn = $prefs['CONSTRICTCONTACT'] ?? 'none';
        return $toReturn;

    }

    /**
     * @param array $newPreferences
     *
     * @return bool
     */
    public function canDisabledKitsPreference($newPreferences)
    {
        $kitsPreference = IsKitEnabled();

        $newKitsPrefDisabled = ($newPreferences['KIT'] == null || $newPreferences['KIT'] == 'false');

        if ($kitsPreference && $newKitsPrefDisabled) {
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
            $params[2] = 'K';
            $res = QueryResult($params);

            if (count($res ?? []) > 0) {
                foreach ($res as $row) {
                    if (($row['LINEITEMCOUNT'] ?? 0) > 0) {
                        Globals::$g->gErr->addIAError('INV-0105', __FILE__ . ":" . __LINE__,
                            "", [], "", [],
                            "To disable kits, first delete the transactions that use kits. Then, try again.",
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
    public function canDisabledCustUOMPreference($newPreferences)
    {
        $currCustomUOMMethodsPref = GetPreferenceForProperty(Globals::$g->kINVid, 'ENABLE_MULTI_UOM');

        $newCustomUOMPrefDisabled = ($newPreferences['ENABLE_MULTI_UOM'] == null
            || $newPreferences['ENABLE_MULTI_UOM'] == 'false');

        if ($currCustomUOMMethodsPref === 'T' && $newCustomUOMPrefDisabled) {
            $params = [];
            $params[0] = "SELECT uomgrp.name, COUNT(1)
                         FROM icuomgrp uomgrp
                         INNER JOIN icuom icuom ON icuom.cny# = uomgrp.cny# 
                                                AND icuom.grpkey = uomgrp.record#
                         WHERE
                            uomgrp.cny# = :1
                            AND uomgrp.issystem = :2
                            AND EXISTS (SELECT 1 
                                        FROM docentrymst de
                                        WHERE de.cny# = icuom.cny#
                                            AND de.unit = icuom.unit
                                        )
                         GROUP BY uomgrp.name";
            $params[1] = GetMyCompany();
            $params[2] = 'F';
            $res = QueryResult($params);

            if (count($res ?? []) > 0) {
                Globals::$g->gErr->addIAError('INV-0106', __FILE__ . ":" . __LINE__,
                    "", [], "", [],
                    "To disable custom units of measure, first delete the transactions that include items with custom units of measure. Then, try again.",
                    []
                    );
                return false;
            }
        }

        return true;
    }

    /**
     *  Installing any required SCM objects
     * @return bool
     */
    public function installOtherRequiredSCMObjects(): bool
    {
        import("WorkflowPackageManager");
        $wflwMgr = new WorkflowPackageManager();
        // Installing standard UOM
        // The following function installs standard UOM's if doesn't exists
        return $wflwMgr->InstallStandardUOMGroups();
    }

}
