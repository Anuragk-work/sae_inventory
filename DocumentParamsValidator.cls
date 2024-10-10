<?php
/**
 * This module contains validation routine applied to all types of
 * transaction definitions.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */
import('AbstractValidator');

require_once "uperm.inc";
require_once 'DocumentParamsManager.cls';

/**
 * Class Operation
 * An abstract class that simulates the enumeration. The validator needs
 * to know what is the intended operation to apply the proper validation rules.
 */
abstract class Operation
{
    const CREATE_NEW = "create_new";
    const UPDATE = "update";
    const DELETE = "delete";
}

/**
 * Class DocumentParamsValidator - parent class for transaction definition
 * validators.
 */
abstract class DocumentParamsValidator extends AbstractValidator
{
    /* @var DocumentParamsManager $manager */
    protected $manager;
    /** @var  string $operation */
    private $operation;

    /** @var $localizedStringMap token to text map  */
    private static $localizedStringMap = null;

    /** @var string[] $docparaTokens Tokens to be translated */
    private static $docparaTokens = [
        'IA.DOCUMENT_POSTING_ACCOUNT_MAPPING',
        'IA.TRANSACTION_POSTING_GL_ACCOUNT_MAPPIN',
        'IA.TRANSACTION_POSTING_AR_ACCOUNT_MAPPING',
        'IA.TRANSACTION_POSTING_AP_ACCOUNT_MAPPING'
    ];
    /**
     * Public setter.
     *
     * @param string $operation
     */
    public function setOperation($operation) 
    {
        $this->operation = $operation;
    }

    /**
     * Public getter.
     *
     * @return string
     */
    public function getOperation() 
    {
        return $this->operation;
    }

    /**
     * @param DocumentParamsManager $manager
     */
    function __construct(DocumentParamsManager $manager)
    {
        $this->manager = $manager;
    }

    /**
     * Wrapper method to collect the validator class instances.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;

        $ok = $this->validateAll($values);

        if((isset($values['DOCID']) && $values['DOCID'] != '') && strpos( $values['DOCID'], '--' )!== false) {
            $ok = false;
            $msg = "This template name cannot be created. Leading/Trailing/Consecutive hyphens are not allowed.";
            $gErr->addIAError('INV-0398', __FILE__ . ':' . __LINE__, $msg, []);
        }

        //checking for special char availability in DOCID its excepting only (- and _)
        if (!empty($values['DOCID'])
            && !preg_match('/^(?!--|.*--)(^[0-9a-zA-Z\s_\-]{1,30})$/', $values['DOCID'])) {
            $ok = false;
            $msg = "The Template name field cannot include special characters.";
            $gErr->addIAError('PO-0186', __FILE__ . ':' . __LINE__, $msg, []);
        }

        if (!$values['SYSTEM_GENERATED']
            && in_array($values['UPDATES_INV'], array('Value', 'Quantity and Value'))
            && $values['UPDATES_GL'] == 'G'
            && in_array(
                $values['DOCID'], array(BUILD_KIT, DIS_KIT, ICTransferManager::INDOCTYPE, ICTransferManager::OUTDOCTYPE)
            )
        ) {
            if (empty($values['DOCPAR_INVGL']) && empty($values['DOCPAR_PRGL'])) {
                $msg = "Document that affects 'Value' requires posting configuration";
                $corr = "Enter posting configuration and try again";
                $gErr->addIAError(
                    'INV-0399', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr,[]
                );
                $ok = false;
            }
        }
        if (
            in_array($values['UPDATES_INV'], array('Value', 'Quantity and Value'))
            && $values['CONVTYPE'] == 'Close Original and Create Back Order'
        ) {
            $msg = "Select a Partial conversion handling option other than 'Close Original and Create Back Order' ";
            $msg .= "when the transaction affects 'Value' or 'Quantity and Value'.";
            $gErr->addIAError(
                'INV-0485', __FILE__ . ':' . __LINE__, $msg, [], '', [], '', []
            );
            $ok = false;
        }
        if ($values['SHOW_TOTALS'] != 'true' && $values['LINELEVELSIMPLETAX'] == 'true') {
            $msg = "Line level subtotal can be enabled only if the subtotal is enabled";
            $corr = "Enable SHOW_SUBTOTALS and try again";
            $gErr->addIAError(
                'INV-0400', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr, []
            );
            $ok = false;
        } else if ($values['SHOW_TOTALS'] == 'true' && $values['LINELEVELSIMPLETAX'] == 'true') {
            $kModArray = array('Sales' => Globals::$g->kSOid, 'Purchase' => Globals::$g->kPOid);
            $isTaxScheduleEnabled = GetPreferenceForProperty($kModArray[$values['SALE_PUR_TRANS']], 'TAXSCHED');
            if ($isTaxScheduleEnabled == 'T') {
                unset($values['LINELEVELSIMPLETAX']);
            }
        }


        return $ok;
    }

    /**
     * Initializes and adds validators used by all three types of
     * transaction definitions.
     */
    protected function addCommonValidators()
    {
        if ($this->getOperation() === Operation::UPDATE) {
            $this->addValidator(new DocumentNameValidator($this->manager));
        }
        $this->addValidator(new UserPermissionValidator());
        $this->addValidator(new SubtotalsSelectionValidator());
        $this->addValidator(new SubtotalsValidator($this->manager));
        $this->addValidator(new DocumentNumberingSchemeValidator());
        $this->addValidator(new WarehouseValidator());
        $this->addValidator(new MandatoryFieldsValidator());

        $this->addValidator(InventoryTotalsValidator::getInstance());
        $this->addValidator(new EntityPropertiesValidator());

    }

    /**
     * Translate a token to text.
     *
     * @param string $token Token to be translated
     *
     * @return string Translated token
     * @throws IAException
     */
    protected static function translateToken(string $token)
    {
        if (self::$localizedStringMap === null) {
            self::$localizedStringMap = getLocalizedTextWithThrow(I18N::tokenArrayToObjectArray(self::$docparaTokens));
        }
        return GT(self::$localizedStringMap, $token);
    }
}

/**
 * Class InvDocumentParamsValidator.
 *
 * Implementation of validation routine for the
 * Inventory Transaction Definition entities
 */
class InvDocumentParamsValidator extends DocumentParamsValidator
{
    /**
     * @param DocumentParamsManager $manager
     */
    function __construct(DocumentParamsManager $manager)
    {
        parent::__construct($manager);
    }

    /**
     * Validator for inventory transaction definitions.
     *
     * @param array $values
     *
     * @return bool
     */
    public function validate($values) 
    {

        $this->addCommonValidators();
        $this->addValidator(new PrimaryDocumentNotSupportedValidator());

        if (!$this->manager->isAutomaticallyGenerated()) {
            // Create validator for COGS Account Mapping
            $amValidator = new AccountMappingValidator();
            $amValidator->setMapping(AccountMappingValidator::DOCPAR_INVGL);
            $amValidator->setAccountMappingTitle('Inventory account mapping');
            $amValidator->setFields(
                array(
                    'ITEM_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'itemglgroup', 'activeOnly' => false),
                    'WAREHOUSE' => array('checkForUniqueness' => true, 'entity' => 'warehouse', 'activeOnly' => true),
                    'DEBIT_CREDIT' => array('checkForUniqueness' => true, 'validValues' => array('Debit', 'Credit')),
                    'GLACCOUNT' => array('checkForUniqueness' => false, 'entity' => 'glaccount', 'activeOnly' => true),
                    'ISOFFSET' => array('checkForUniqueness' => false, 'validValues' => array('true', 'false')),
                    'DEPT' => array('checkForUniqueness' => false, 'entity' => 'department', 'activeOnly' => true),
                    'LOCATION' => array('checkForUniqueness' => false, 'entity' => 'location', 'activeOnly' => true)
                )
            );
            $this->addValidator($amValidator);
	}
        $this->addValidator(new COGSValidator());
        $ok = parent::validate($values);

        if ($ok) {
            $gErr = Globals::$g->gErr;

            if ($values['DOCID'] != ICTransferManager::INTRANSITDOCTYPE &&
                $values['DOCID'] != ICTransferManager::INDOCTYPE &&
                !empty($values['DOCPAR_RECALLS'])) {
                foreach ($values['DOCPAR_RECALLS'] as $recallDocpar) {
                    // Populating the RECDOCPAR with DOCID to support RESTAPI
                    //  create post operation will provide docpar RECORDNO in RECDOCPARRECORDNO
                    if ($recallDocpar['RECDOCPAR'] === $recallDocpar['RECDOCPARRECORDNO']) {
                        $recallDocTemp = $this->manager->BaseGet($recallDocpar['RECDOCPARRECORDNO']);
                        $recallDocpar['RECDOCPAR'] = $recallDocTemp['DOCID'];
                        $recallDocpar['DOCPAR'] = $values['DOCID'];
                    }
                    $recallDoc = $this->manager->GetLatest($recallDocpar['RECDOCPAR']);
                    if ($recallDoc['UPDATES_INV'] !== $values['UPDATES_INV']) {
                        $msg = "This document is affecting '" . $values['UPDATES_INV'] .
                            "' whereas '" . $recallDocpar['RECDOCPAR'] . "' is affecting '" . $recallDoc['UPDATES_INV']
                            . "'";
                        $corr = "The converted from document and the current document should affect same inventory total";
                            $gErr->addIAError(
                                'INV-0401', __FILE__ . ':' . __LINE__,
                                $msg, ['VALUES_UPDATES_INV' => $values['UPDATES_INV'], 'RECALL_DOCPAR_RECDOCPAR' => $recallDocpar['RECDOCPAR'], 'RECALL_DOC_UPDATES_INV' => $recallDoc['UPDATES_INV']],
                                $corr, []
                            );
                        $ok = false;
                    }
                }
            }


        }
        return $ok;
    }
}

/**
 * Class PoDocumentParamsValidator
 *
 * Implementation of validation routine for the
 * Purchase Order Transaction Definition entities
 */
class PoDocumentParamsValidator extends DocumentParamsValidator
{
    /**
     * Validator for purchasing transaction definitions.
     *
     * @param array $values
     *
     * @return bool
     */
    public function validate($values) 
    {

        $this->addCommonValidators();

        // GLEntrySelectionValidator is only relevant if POSTTOGL === true
        if (isArrayValueProvided($values, 'POSTTOGL') && "true" === $values['POSTTOGL']) {
            $glEntryValidator = new GLEntrySelectionValidator();
            $glEntryValidator->setPostEntry("reversal");
            $this->addValidator($glEntryValidator);
        }

        $this->addValidator(new ContactsLabelValidator());

        // If the project account module is subscribed add validation for
        // consistency between entries in inventory totals table and
        // Increase / Decrease Inventory fiels.
        $gManagerFactory = Globals::$g->gManagerFactory;
        $modMgr = $gManagerFactory->getManager('modules');
        $moduleSubscribed = $modMgr->isModuleSubscribed("48.PROJACCT");
        if ($moduleSubscribed) {
            $this->addValidator(new InventoryTotalsConsistencyValidator());
        }

        $this->addValidator(new SubtotalsTaxValidator("po"));

        if (!$this->manager->isAutomaticallyGenerated()) {
            // Create validator for Additional GL entry account mapping
            $amValidator = new AccountMappingValidator();
            $amValidator->setMapping(AccountMappingValidator::DOCPAR_INVGL);
            $amValidator->setAccountMappingTitle('Additional GL posting account mapping');
            $amValidator->setFields(
                array(
                    'ITEM_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'itemglgroup', 'activeOnly' => false),
                    'WAREHOUSE' => array('checkForUniqueness' => true, 'entity' => 'warehouse', 'activeOnly' => true),
                    'DEBIT_CREDIT' => array('checkForUniqueness' => true, 'validValues' => array('Debit', 'Credit')),
                    'GLACCOUNT' => array('checkForUniqueness' => false, 'entity' => 'glaccount', 'activeOnly' => true),
                    'ISOFFSET' => array('checkForUniqueness' => false, 'validValues' => array('true', 'false')),
                    'DEPT' => array('checkForUniqueness' => false, 'entity' => 'department', 'activeOnly' => true),
                    'LOCATION' => array('checkForUniqueness' => false, 'entity' => 'location', 'activeOnly' => true)
                )
            );
            $this->addValidator($amValidator);

            $this->addValidator(new SubledgerPostingSelectionValidator());

            // Create validator for document posting account mapping
            $dpValidator = new AccountMappingValidator();
            $dpValidator->setMapping(AccountMappingValidator::DOCPAR_PRGL);
            $mappingTitle = $this->manager->getTrxPostingMappingTableTitle($values);
            $mappingTitle = self::translateToken($mappingTitle);
            $dpValidator->setAccountMappingTitle($mappingTitle);
            $dpValidator->setCheckForSingleAccount(true);
            $dpValidator->setFields(
                array(
                    'ITEM_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'itemglgroup', 'activeOnly' => false),
                    'WAREHOUSE' => array('checkForUniqueness' => true, 'entity' => 'warehouse', 'activeOnly' => true),
                    'ENT_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'vendglgroup', 'activeOnly' => true),
                    'DEBIT_CREDIT' => array('checkForUniqueness' => true, 'validValues' => array('Debit', 'Credit')),
                    'GLACCOUNT' => array('checkForUniqueness' => false, 'entity' => 'glaccount', 'activeOnly' => true),
                    'ISOFFSET' => array('checkForUniqueness' => false, 'validValues' => array('true', 'false')),
                    'DEPT' => array('checkForUniqueness' => false, 'entity' => 'department', 'activeOnly' => true),
                    'LOCATION' => array('checkForUniqueness' => false, 'entity' => 'location', 'activeOnly' => true)
                )
            );
            $this->addValidator($dpValidator);
        }

        $this->addValidator(new TDInventoryEffectValidator($this->manager));
        $this->addValidator(new AllocationValidator());
        $this->addValidator(new RetainageSelectionValidator('po'));
        $this->addValidator(new ThreewayMatchValidator());
        $this->addValidator(new PrimaryDocumentValidator());

        $ok = parent::validate($values);

        return $ok;
    }
}

/**
 * Class SoDocumentParamsValidator
 *
 * Implementation of validation routine for the
 * Sales Order Transaction Definition entities
 */
class SoDocumentParamsValidator extends DocumentParamsValidator
{
    /**
     * Validator for sales order transaction definitions.
     *
     * @param array $values
     *
     * @return bool
     */
    public function validate($values) 
    {
        $this->addCommonValidators();

        $this->addValidator(new ContactsLabelValidator());
        $this->addValidator(new SubtotalsTaxValidator("so"));
        $this->addValidator(new PaymentProcessingValidator());
        $this->addValidator(new RevRecSelectionValidator());
        $this->addValidator(new RenewalsSelectionValidator());
        $this->addValidator(new ExtPriceDiscSelectionValidator());
        $this->addValidator(new AdditionalGLValidator());
        $this->addValidator(new RetainageSelectionValidator('so'));
        $this->addValidator(new ProjectContractBillingValidator());

        if (!$this->manager->isAutomaticallyGenerated()) {
            // Create validator for COGS Account Mapping
            $amValidator = new AccountMappingValidator();
            $amValidator->setMapping(AccountMappingValidator::DOCPAR_INVGL);
            $amValidator->setAccountMappingTitle('COGS account mapping');
            $amValidator->setFields(
                array(
                    'ITEM_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'itemglgroup', 'activeOnly' => false),
                    'WAREHOUSE' => array('checkForUniqueness' => true, 'entity' => 'warehouse', 'activeOnly' => true),
                    'ENT_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'custglgroup', 'activeOnly' => true),
                    'DEBIT_CREDIT' => array('checkForUniqueness' => true, 'validValues' => array('Debit', 'Credit')),
                    'GLACCOUNT' => array('checkForUniqueness' => false, 'entity' => 'glaccount', 'activeOnly' => true),
                    'DEPT' => array('checkForUniqueness' => false, 'entity' => 'department', 'activeOnly' => true),
                    'LOCATION' => array('checkForUniqueness' => false, 'entity' => 'location', 'activeOnly' => true)
                )
            );
            $this->addValidator($amValidator);

            $this->addValidator(new SubledgerPostingSelectionValidator());

            // Create validator for document posting account mapping
            $dpValidator = new AccountMappingValidator();
            $dpValidator->setMapping(AccountMappingValidator::DOCPAR_PRGL);
            $mappingTitle = $this->manager->getTrxPostingMappingTableTitle($values);
            $mappingTitle = self::translateToken($mappingTitle);
            $dpValidator->setAccountMappingTitle($mappingTitle);
            $dpValidator->setCheckForSingleAccount(true);
            $dpValidator->setFields(
                array(
                    'ITEM_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'itemglgroup', 'activeOnly' => false),
                    'WAREHOUSE' => array('checkForUniqueness' => true, 'entity' => 'warehouse','activeOnly' => true),
                    'ENT_GLGROUP' => array('checkForUniqueness' => true, 'entity' => 'custglgroup','activeOnly' => true),
                    'DEBIT_CREDIT' => array('checkForUniqueness' => true, 'validValues' => array('Debit', 'Credit')),
                    'GLACCOUNT' => array('checkForUniqueness' => false, 'entity' => 'glaccount', 'activeOnly' => true),
                    'ISOFFSET' => array('checkForUniqueness' => false, 'validValues' => array('true', 'false') ),
                    'DEPT' => array('checkForUniqueness' => false, 'entity' => 'department', 'activeOnly' => true),
                    'LOCATION' => array('checkForUniqueness' => false, 'entity' => 'location', 'activeOnly' => true)
                )
            );
            $this->addValidator($dpValidator);

        }
        $this->addValidator(new COGSValidator());
        $this->addValidator(new TDInventoryEffectValidator($this->manager));
        $this->addValidator(new ContractInvoiceValidator($this->manager));
        $this->addValidator(new PrimaryDocumentNotSupportedValidator());
        $ok = parent::validate($values);

        return $ok;
    }
}

class SoDocumentParamsDeletionValidator extends DocumentParamsValidator
{
    /**
     * @param DocumentParamsManager $manager
     */
    public function __construct(DocumentParamsManager $manager)
    {
        parent::__construct($manager);
    }

    /**
     * Validator for sales order transaction definition deletion.
     *
     * @param array $values
     *
     * @return bool
     */
    public function validate($values)
    {
        $this->addValidator(new ContractInvoiceValidator($this->manager));
        $ok = $this->validateAll($values);

        return $ok;
    }
}

class DummyDocumentParamsDeletionValidator extends DocumentParamsValidator
{
    /**
     * @param DocumentParamsManager $manager
     */
    public function __construct(DocumentParamsManager $manager)
    {
        parent::__construct($manager);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function validate($values)
    {
        // Dummy validator.  Always valid.
        return true;
    }
}

/**
 * Class TransactionDefinitionType
 *
 * Emulates enumeration for transaction definition types.
 */
abstract class TransactionDefinitionType
{
    const TD_TYPE_INV = "inv";
    const TD_TYPE_PO = "po";
    const TD_TYPE_SO = "so";

    /**
     * Returns the transaction definition type for the given entity.
     *
     * @param string $entityType
     *
     * @return string
     * @throws Exception
     */
    public static function getTransactionDefinitionType($entityType)
    {
        switch ($entityType) {
        case "invdocumentparams":
            $tdtype = self::TD_TYPE_INV;
            break;
        case "podocumentparams":
            $tdtype = self::TD_TYPE_PO;
            break;
        case "sodocumentparams":
            $tdtype = self::TD_TYPE_SO;
            break;
        default:
            throw new Exception("Unsupported TD entity type -> " . $entityType);
        }
        return $tdtype;
    }
}

/**
 * Class DocumentParamsValidatorFactory - factory class that creates instance
 * of a proper validator class.
 */
class DocumentParamsValidatorFactory
{
    /**
     * Factory method for creating a proper validator for the given
     * transaction definition.
     *
     * @param DocumentParamsManager $manager
     * @param string                $operation
     *
     * @return DocumentParamsValidator
     * @throws Exception
     */
    public static function create(DocumentParamsManager $manager, $operation)
    {
        $tdType = TransactionDefinitionType::getTransactionDefinitionType($manager->_entity);

        if ($operation === DocumentParamsValidator::VALIDATION_MODE_DELETE) {
            if ($tdType == TransactionDefinitionType::TD_TYPE_SO) {
                $validator = new SoDocumentParamsDeletionValidator($manager);
            } else {
                $validator = new DummyDocumentParamsDeletionValidator($manager);
            }
        } else {
            switch ($tdType) {
                case TransactionDefinitionType::TD_TYPE_INV:
                    $validator = new InvDocumentParamsValidator($manager);
                    break;
                case TransactionDefinitionType::TD_TYPE_PO:
                    $validator = new PoDocumentParamsValidator($manager);
                    break;
                case TransactionDefinitionType::TD_TYPE_SO:
                    $validator = new SoDocumentParamsValidator($manager);
                    break;
                default:
                    throw new Exception("Unsupported transaction definition type: " . $tdType);
            }
        }

        $validator->setOperation($operation);

        return $validator;
    }
}

/**
 * Class UserPermissionValidator
 *
 * Checks for validity of the user permissions
 */
class UserPermissionValidator extends AbstractValidator
{
    /**
     * Validates provided user permissions:
     * 1. If the user has selected to use transaction level permissions
     *    (Enable permissions for specific users/groups check box) there should
     *    be at least one user / group with the acces permission.
     * 2. Verify that the permission fields are valid.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        global $gErr;
        $ok = true;
        if (isset($values['USERPERM']) && 'true' === $values['USERPERM']) {
            $processedUsers = array();
            $lineNumber = 1;
            foreach (($values['PERMLIST']) ?? [] as $record) {
                $user = explode('/', $record['PERMLISTMEMBER']);
                if (sizeof($user) == 1) {
                    $entity = 'userinfo';
                    $activeOnly = true;
                } else {
                    if ('Everyone' === $user[1]) {
                        // Mark this as a default group. Its validity will not be verified.
                        $entity = 'default-group';
                    } else {
                        $entity = 'usergroup';
                        $activeOnly = false;
                    }
                    $record['PERMLISTMEMBER'] = $user[1];
                }

                if (isset($processedUsers[$entity])
                    && in_array($record['PERMLISTMEMBER'], $processedUsers[$entity])
                ) {
                    $gErr->addIAError(
                        'INV-0404', __FILE__ . ':' . __LINE__,
                        "Duplicate user or group is provided: " . $record['PERMLISTMEMBER']. ".",
                        ['RECORD_PERMLISTMEMBER' => $record['PERMLISTMEMBER']]
                    );
                    $ok = false;
                    break;
                } else {
                    $processedUsers[$entity][] = $record['PERMLISTMEMBER'];
                }

                $fields = array(
                    'ALLOWACCESS' => array('validValues' => array('true', 'false')),
                    'ALLOWACCESS2' => array('validValues' => array('allow', 'deny'))
                );
                if ('default-group' != $entity) {
                    // If it is not the default group add the permission
                    // (user or group) to the list of validated fields
                    /** @noinspection PhpUndefinedVariableInspection */
                    $fields['PERMLISTMEMBER'] = array( 'entity' => $entity, 'activeOnly' => $activeOnly);
                }
                if (!$this->validateSingleRecord($record, $fields, $lineNumber)) {
                    $gErr->addIAError(
                        'INV-0063', __FILE__ . ':' . __LINE__,
                        "Invalid permission.", []
                    );
                    $ok = false;
                    break;
                }
                $lineNumber++;
            }

            if (IsAdvancedConfiguration() && $values['USERPERM'] == 'true' && !upermPrepValuesValid($values) ) {
                $gErr->addIAError(
                    'INV-0064', __FILE__ . ':' . __LINE__,
                    "You have decided to use transaction level permissions. " .
                    "Please grant permissions to at least one user on the 'Security Configuration' tab.", []
                );
                $ok = false;
            }
        }
        return $ok;
    }
}

/**
 * Class GLEntrySelectionValidator
 *
 * Checks for the validity of the GL entries
 */
class GLEntrySelectionValidator extends AbstractValidator
{
    /** @var string $postEntry */
    private $postEntry = null;

    /**
     * @param string $postEntry
     */
    public function setPostEntry($postEntry) 
    {
        $this->postEntry = $postEntry;
    }

    /**
     * Validates the user input for GL entry selection.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values) 
    {
        global $gErr;
        $ok = true;
        if (empty($values['DOCPAR_INVGL'])) {
            $errorMessage =
                "You selected to post $this->postEntry GL entries. " .
                "No $this->postEntry entries have been provided.";
            $gErr->addIAError(
                'INV-0402', __FILE__ . ':' . __LINE__,
                $errorMessage,
                ['POST_ENTRY' => $this->postEntry]
            );
            $ok = false;
        }
        return $ok;
    }
}

/**
 * Class SubledgerPostingSelectionValidator
 *
 * Implements validation for subledger posting selection.
 */
class SubledgerPostingSelectionValidator extends AbstractValidator
{
    /**
     * Validates correctness of the subledger posting selection.
     * If anything other than None is selected and the proper grid
     * (AR GL Information for SO / AP GL Information for PO) has
     * to be populated with GL account information.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        global $gErr;
        $ok = true;

        $updatesGL = isl_strtoupper($values['UPDATES_GL']);
        if (IsAdvancedConfiguration()) {
            if (($updatesGL == 'A' || $updatesGL == 'G') && (!is_array($values['DOCPAR_PRGL']) || empty($values['DOCPAR_PRGL'])) &&
                $values['SYSTEM_GENERATED'] != true) {
                $str = 'AP/AR';
                if ($updatesGL == 'G' ) {
                    $str = 'GL';
                }elseif ($updatesGL == 'A') {
                    $str = 'AP/AR';
                }
                $docid = $values['DOCID'];
                $gErr->addIAError(
                    'INV-0403', __FILE__ . ':' . __LINE__,
                    "The transaction definition '$docid' is defined to post to $str. " .
                    " Add at least one debit/credit account pair in the Transaction posting account mapping table on the Posting configuration tab and then try saving the transaction definition again.",
                    ['DOCID' => $docid, 'STR' => $str]
                );
                $ok = false;
            }
        }

        return $ok;
    }
}

/**
 * Class SubtotalsSelectionValidator
 *
 * Implements validation for subtotals selection.
 */
class SubtotalsSelectionValidator extends AbstractValidator
{

    /**
     * Validates correctness of the Subtotals selection.
     * 1. If the Has Subtotals check box is selected the proper
     *    subtotals information has to be provided.
     * 2. No duplication in subtotal descriptions is allowed.
     * 3. Validate provided data for each subtotal.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        global $gErr;
        $ok = true;
        if ($values['SHOW_TOTALS'] == 'true' && empty($values['DOCPAR_SUBTOTAL']) ) {
            $docid = $values['DOCID'];
            $gErr->addIAError(
                'INV-0405', __FILE__ . ':' . __LINE__,
                "The transaction definition $docid is expected to have subtotals. " .
                "Please specify the necessary information on the 'Transaction Subtotals' section.",
                ['DOCID' => $docid]
            );
            $ok = false;
        } else {
            $this->setFields(
                array(
                    'DISC_CHARGE' => array('validValues' => array('Discount', 'Charge')),
                    'AMT_PERC' => array('validValues' => array('Amount', 'Percent')),
                    'DEBIT_CREDIT' => array('validValues' => array('Debit', 'Credit')),
                    'GLACCOUNT' => array('entity' => 'glaccount', 'activeOnly' => true),
                    'GLOFFSETACCOUNT' => array('entity' => 'glaccount', 'activeOnly' => true),
                    'DEPARTMENT' => array('entity' => 'department', 'activeOnly' => true),
                    'LOCATION' => array('entity' => 'location', 'activeOnly' => true),
                    'APPORTIONED' => array('validValues' => array('true', 'false')),
                    'ISTAX' => array('validValues' => array('true', 'false')),
                    'ISAVATAX' => array('validValues' => array('true', 'false')),
                )
            );
            $processedSubtotals = array();
            $lineNumber = 1;
            foreach (($values['DOCPAR_SUBTOTAL'] ?? []) as $record) {
                $ok = $ok && $this->validateSingleRecord($record, $this->fields, $lineNumber);
                if ($ok) {
                    $description = $record['DESCRIPTION'];
                    $entityno = ( isset($record['ENTITYKEY']) && $record['ENTITYKEY'] != '') ? $record['ENTITYKEY'] : 0;
                    if ((isset($processedSubtotals[$entityno])) && (in_array($description, $processedSubtotals[$entityno]))) {
                        $gErr->addIAError(
                            'INV-0406', __FILE__ . ':' . __LINE__,
                            "Duplicate subtotal description is found on line #$lineNumber " .
                            "in the 'Transaction Subtotals' section.",
                            ['LINE_NUMBER' => $lineNumber]
                        );
                        $ok = false;
                        break;
                    } else {
                        $processedSubtotals[$entityno][] = $description;
                    }
                } else {
                    break;
                }
                $lineNumber++;
            }
        }
        return $ok;
    }
}

/**
 * Class SubtotalsValidator
 *
 * Implements validation for subtotals data.
 */
class SubtotalsValidator extends AbstractValidator
{
    /** @var DocumentParamsManager $manager */
    private $manager;

    /**
     * @param DocumentParamsManager $manager
     */
    function __construct(DocumentParamsManager $manager)
    {
        $this->manager = $manager;
    }

    /**
     * Validates correctness of the data provided for Subtotals.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $acctMgr = Globals::$g->gManagerFactory->getManager('glaccount');
        $noWarning = (!$values['NOWARNING'] && $this->manager->_warningValidation) ? true : false;
        $updatesGl = IsAdvancedConfiguration() ? $this->manager->isDocParUpdatesGL($values) : false;
        $isLineLevelSimpleTaxEnabled = $values['SHOW_TOTALS'] == 'true' && $values['LINELEVELSIMPLETAX'] == 'true';
        $avaModArray = array('Sale' => 'so', 'Purchase' => 'po');
        $taxEngine = TaxSolutionManager::TAXMETHOD_I_NONE;
        if ($isLineLevelSimpleTaxEnabled && array_key_exists($values['SALE_PUR_TRANS'], $avaModArray)) {
            $taxEngine = GetTaxEngine($avaModArray[$values['SALE_PUR_TRANS']],TaxSolutionManager::TAXSOLUTION_AVALARA);
        }

        //Tax solution for the slid into entity is No tax
        $isNotax = false;
        if (TaxSetupManager::isTaxModuleConfigured() && IsMultiEntityCompany() && GetContextLocation()) {
            //If we get in here, it means we are in multi entity company and slid into an entity. We should have a
            //tax solution for the entity so the GetTaxEngine will return the tax method of the current slid into entity.
            if (GetTaxEngine($values['TD_MODULE']) === TaxSolutionManager::TAXMETHOD_I_NONE) {
                $isNotax = true;
            }
        }

        $docParSubtotals = $values['DOCPAR_SUBTOTAL'] ?? null;
        $isMultiTaxCny = TaxSetupManager::isMultiTaxJurisdictionConfigured();
        $simpleTaxes = [];
        $avaTaxes = [];
        $isTaxes = [];
        if ( $docParSubtotals && is_array($docParSubtotals) ) {
            foreach ( $docParSubtotals as $key => $subtotal ) {
                if ( $updatesGl ) {
                    // GL account is required if neither ISTAX nor APPRTIONED are selected
                    if ( !$subtotal['GLACCOUNT'] && $subtotal['ISTAX'] != 'true' && $subtotal['APPORTIONED'] != 'true' ) {
                        $gErr->addIAError(
                            'INV-0407', __FILE__ . ':' . __LINE__,
                            "GL account is required for posting '"
                            . $values['DOCPAR_SUBTOTAL'][$key]['DESCRIPTION'] . "'.",
                            ['VALUES_DOCPAR_SUBTOTAL_KEY_DESCRIPTION' => $values['DOCPAR_SUBTOTAL'][$key]['DESCRIPTION']]
                        );
                        $ok = false;
                    }
                    if ( $subtotal['GLACCOUNT'] ) {
                        $acct_no = explode("--", $subtotal['GLACCOUNT']);
                        $obj = $acctMgr->GetRaw($acct_no[0]);
                        if ( !$obj[0] ) {
                            $gErr->addIAError(
                                'INV-0408', __FILE__ . ':' . __LINE__,
                                "GL account '" . $subtotal['GLACCOUNT'] . "' is not valid.",
                                ['SUBTOTAL_GLACCOUNT' => $subtotal['GLACCOUNT']]
                            );
                            $ok = false;
                        }
                    }
                    if ( $subtotal['GLOFFSETACCOUNT'] ) {
                        $acct_no = explode("--", $subtotal['GLOFFSETACCOUNT']);
                        $obj = $acctMgr->GetRaw($acct_no[0]);
                        if ( !$obj[0] ) {
                            $gErr->addIAError(
                                'INV-0409', __FILE__ . ':' . __LINE__,
                                "GL account '" . $subtotal['GLOFFSETACCOUNT'] . "' is not valid.",
                                ['SUBTOTAL_GLACCOUNT' => $subtotal['GLOFFSETACCOUNT']]
                            );
                            $ok = false;
                        }
                    }
                }

                if ( $subtotal['APPORTIONED'] === 'true' && $subtotal['ISTAX'] === 'true' ) {
                    $gErr->addIAError(
                        'INV-0065', __FILE__ . ':' . __LINE__,
                        'Apportioned can not be selected if Is Tax is selected.', []
                    );
                    $ok = false;
                }

                if ( $subtotal['APPORTIONED'] === 'false' && !isArrayValueProvided($subtotal, 'DEBIT_CREDIT') ) {
                    $gErr->addIAError(
                        'INV-0410', __FILE__ . ':' . __LINE__,
                        'If the subtotal \'' . $subtotal['DESCRIPTION'] . '\'' .
                        ' is being apportioned, then a Debit/Credit is required.',
                        ['SUBTOTAL_DESCRIPTION' => $subtotal['DESCRIPTION']]
                    );
                    $ok = false;
                }

                if ( is_array($subtotal) && isset($subtotal['ISAVATAX']) && $subtotal['ISAVATAX'] != 'true' ) {
                    unset($values['DOCPAR_SUBTOTAL'][$key]['ISAVATAX']);
                }

                if ( $noWarning && $subtotal['DISC_CHARGE'] == 'Discount' && $subtotal['ISTAX'] == 'true'
                     && $acctMgr->shouldWarn($acctMgr, $values, []) ) {
                    $i = $key + 1;
                    $fileLine = __FILE__ . ':' . __LINE__;
                    $gErr->AddWarning(
                        "Setting IsTax for Discount Line will cause tax amount to be reversed for subtotal line " . $i
                        . "." . " Do you want to continue?",
                        $fileLine
                    );
                    $ok = false;
                }

                if ( $isLineLevelSimpleTaxEnabled && $subtotal['ISTAX'] == 'true' && $subtotal['ISAVATAX'] != 'true'
                     && $subtotal['AMT_PERC'] != 'Percent' ) {
                    $gErr->addIAError(
                        'INV-0411', __FILE__ . ':' . __LINE__,
                        'When line level Simple Tax is enabled, taxes can’t be specified as a flat amount', [],
                        " In line #" . ($key + 1)
                        . " in the Transaction subtotals section, change the ‘Value type’ to ‘Percent’", ['KEY_PLUS_1' => $key + 1]
                    );
                    $ok = false;
                }
                if ( $isLineLevelSimpleTaxEnabled && $taxEngine == TaxSolutionManager::TAXMETHOD_I_AVALARA
                     && $subtotal['ISAVATAX'] == 'true' ) {
                    $gErr->addIAError(
                        'INV-0066', __FILE__ . ':' . __LINE__,
                        'Line-level Simple Tax cannot be enabled when a subtotal line is selected for Avalara ', [],
                        "Deselect the checkbox for line level Simple Tax. Then, try again", []
                    );
                    $ok = false;
                }

                //If tax solution for entity is No Tax, taxable subtotal is not allowed
                if ( $isNotax && $subtotal['ISTAX'] == 'true' ) {
                    $gErr->addIAError('INV-0067', __FILE__ . ':' . __LINE__,
                                    'No Tax Solution is enabled Is Tax cant be enabled for subtotals', [],
                                    "Deselect the checkbox Is Tax. Then, try again", []
                    );
                    $ok = false;
                }

                // to deal with subtotal templates we need to collect states by each entity
                // when not using subtotal templates entitykey will be always null which is index ''
                if ( $subtotal['ISTAX'] == 'true' ) {
                    $entityKey = $subtotal['ENTITYKEY'];
                    $isTaxes[$entityKey] = true;
                    if ( isset($subtotal['ISAVATAX']) && $subtotal['ISAVATAX'] == 'true' ) {
                        $avaTaxes[$entityKey] = true;
                    } else {
                        $simpleTaxes[$entityKey] = true;
                    }
                }

            } // end foreach

            // TODO these validations should be universal but for now limiting scope to multitax companies
            if ( $isMultiTaxCny) {
                // do now allow line level simple tax without a single tax line ( does not check for each subtotal templates)
                if ( $isLineLevelSimpleTaxEnabled && empty($isTaxes) ) {
                    $gErr->addIAError(
                        'INV-0068', __FILE__ . ':' . __LINE__,
                        "You cannot enable Line Level Simple Tax without a 'Is Tax' line in the subtotal.", [],
                        "Disable line level Simple Tax or add a tax line and try again.", []
                    );
                    $ok = false;
                }
                unset($entityKey);
                foreach ( $isTaxes as $entityKey => $hasTax ) {
                    // get the corresspondind simple and avalara taxes if present
                    $hasSimpleTax = $simpleTaxes[$entityKey];
                    $hasAvaTax = $avaTaxes[$entityKey];

                    //In multitax company its not allowed to have Avalara & Simple tax in same TD
                    if ( $hasSimpleTax && $hasAvaTax ) {
                        $gErr->addIAError(
                            'INV-0069', __FILE__ . ':' . __LINE__,
                            "You cannot have more than one tax line in subtotal.", [],
                            "Since you are using 'Select for Avalara' on one of them.", []
                        );
                        $ok = false;
                    }

                    // line level simple tax does not work when used as simple tax fallback for avalara tax engine
                    if ( $isLineLevelSimpleTaxEnabled && $hasSimpleTax
                            && $taxEngine == TaxSolutionManager::TAXMETHOD_I_AVALARA && !$hasAvaTax ) {
                        $gErr->addIAError(
                            'INV-0070', __FILE__ . ':' . __LINE__,
                            "Line level Simple Tax cannot be used when using Simple Tax fallback for Avalara.", [],
                            "Deselect the checkbox 'Enable line level Simple Tax' and try again.", []
                        );
                        $ok = false;
                    }
                }
            }

        }

        return $ok;
    }

}

class TDInventoryEffectValidator extends AbstractValidator
{
    /* @var DocumentParamsManager $manager */
    private $manager;

    /**
     * @param DocumentParamsManager $manager
     */
    function __construct(DocumentParamsManager $manager)
    {
        $this->manager = $manager;
    }
    
    /**
     * Validates inventory effect.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        global $gErr;
        $ok = true;

        if (!empty($values['DOCPAR_RECALLS'])) {
            foreach ($values['DOCPAR_RECALLS'] as $recallDocpar) {
                if (is_array($recallDocpar)){
                    $recallDoc = $this->manager->GetLatest($recallDocpar['RECDOCPAR']);
                    if ($recallDoc['UPDATES_INV'] != 'No'
                        && $values['UPDATES_INV'] != 'No'
                        && $recallDoc['IN_OUT'] == $values['IN_OUT']
                        && ($recallDoc['UPDATES_INV'] == $values['UPDATES_INV']
                            || $recallDoc['UPDATES_INV'] == 'Quantity and Value'
                            || $values['UPDATES_INV'] == 'Quantity and Value')
                    ){
                        $msg = sprintf ('This document is affecting \'%1$s %2$s\' and \'%3$s\' is affecting \'%4$s %5$s\'',
                            $values['UPDATES_INV'], $values['IN_OUT'], $recallDocpar['RECDOCPAR'], $recallDoc['UPDATES_INV'], $recallDoc['IN_OUT']);
                        $corr
                            = "The converted from document and the current document should not affect same inventory total";
                        $gErr->addIAError(
                            'INV-0412', __FILE__ . ':' . __LINE__,
                            $msg, ['VALUES_UPDATES_INV' => $values['UPDATES_INV'], 'VALUES_IN_OUT' => $values['IN_OUT'], 'RECALL_DOCPAR_RECDOCPAR' => $recallDocpar['RECDOCPAR'], 'RECALL_DOC_UPDATES_INV' => $recallDoc['UPDATES_INV'], 'RECALL_DOC_IN_OUT' => $recallDoc['IN_OUT']],
                            $corr, []
                        );
                        $ok = false;
                    }
                }
            }
        }

        if ($values['SALE_PUR_TRANS'] == 'Sale' 
            && $values['IN_OUT'] == 'Increase'
            && !empty($values['UPDATES_INV'])
            && $values['UPDATES_INV'] != 'No'
            && $values['UPDATES_INV'] != 'Quantity and Value'
        ) {
            $msg = "Return document should affect 'Quantity and value'";
            $gErr->addIAError(
                'INV-0413', __FILE__ . ':' . __LINE__, $msg, [], '', [], '', []
            );
            $ok = false;
        } else if ($values['SALE_PUR_TRANS'] == 'Purchase' 
            && $values['IN_OUT'] == 'Decrease'
            && !empty($values['UPDATES_INV'])
            && $values['UPDATES_INV'] != 'No'
            && $values['UPDATES_INV'] != 'Quantity and Value'
        ) {
            $msg = "Return document should affect 'Quantity and value'";
            $gErr->addIAError(
                'INV-0668', __FILE__ . ':' . __LINE__, $msg, [], '', [], '', []
            );
            $ok = false;
        }

        return $ok;
    }
}


/**
 * Class ContractInvoiceValidator
 *
 * Implementation of validation for contact title fields
 */
class ContractInvoiceValidator extends AbstractValidator
{
    /* @var DocumentParamsManager $manager */
    private $manager;

    /**
     * @param DocumentParamsManager $manager
     */
    function __construct(DocumentParamsManager $manager)
    {
        $this->manager = $manager;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $ok = true;

        if (!$this->manager->isAutomaticallyGenerated()) {
            $docId = $values['DOCID'];
            $cnSetupMgr = Globals::$g->gManagerFactory->getManager('cnsetup');
            if ($cnSetupMgr->isUsedForACPTransactionDefinition($docId)) {
                Globals::$g->gErr->addIAError(
                    'INV-0414', __FILE__ . ':' . __LINE__,
                    "$docId is a system-generated Transaction Defintion that cannot be modified or deleted.",
                    ['DOC_ID' => $docId]
                );
                $ok = false;
            }
        }
        return $ok;
    }
}


/**
 * Class ContactsLabelValidator
 *
 * Implementation of validation for contact title fields
 */
class ContactsLabelValidator extends AbstractValidator
{
    /**
     * Validates mandatory CONTACTTITLE1 and CONTACTTITLE2 fields.
     *
     * @param array $values
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if (!$values['CONTACTTITLE1'] || $values['CONTACTTITLE1'] == '') {
            $gErr->addIAError(
                'INV-0071', __FILE__ . ':' . __LINE__,
                "Required field 'Title of Contact1' is not provided.", []
            );
            $ok = false;

        }
        if (!$values['CONTACTTITLE2'] || $values['CONTACTTITLE2'] == '') {
            $gErr->addIAError(
                'INV-0072', __FILE__ . ':' . __LINE__,
                "Required field 'Title of Contact2' is not provided.", []
            );
            $ok = false;
        }
        return $ok;
    }
}

/**
 * Class DocumentNumberingSchemeValidator
 *
 * Validator class checking for correctness of the document numbering scheme.
 */
class DocumentNumberingSchemeValidator extends AbstractValidator
{
    /**
     * Validates that the numbering scheme (pattern) is provided if the
     * Enable Numbering Scheme check box is selected.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $ok = true;

        if ($values['ENABLE_SEQNUM'] == 'true' && $values['SEQUENCE'] == '') {
            Globals::$g->gErr->addIAError(
                'INV-0073', __FILE__ . ':' . __LINE__,
                "Required field 'Document Numbering Scheme' is missing", []
            );
            $ok = false;
        }
        return $ok;
    }
}

/**
 * Class WarehouseValidator
 *
 * Validates correctnes of user entry for warehouse when it is required.
 */
class WarehouseValidator extends AbstractValidator
{
    /**
     * Validates that if the 'Use Default Warehouse' is selected
     * for the warehouse selection method the default warehouse
     * is provided.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if ($values['WAREHOUSESELMETHOD'] == 'Use the default warehouse'
            && $values['DEFAULT_WAREHOUSE'] == ''
        ) {
            $gErr->addIAError(
                'INV-0074', __FILE__ . ':' . __LINE__,
                "Please enter the Default Warehouse", []
            );
            $ok = false;
        }
        if ($ok && $values['DEFAULT_WAREHOUSE']) {
            $warehouseMgr = Globals::$g->gManagerFactory->getManager('warehouse');
            $defwhse = explode("--", $values['DEFAULT_WAREHOUSE']);

            $recordno = $warehouseMgr->GetRecordNoFromVid($defwhse[0], true);
            if (!isset($recordno)) {
                $gErr->addIAError(
                    'INV-0075', __FILE__ . ':' . __LINE__,
                    "Unable to save the transaction definition", [],
                    "Invalid warehouse", []
                );
            }
        }
        return $ok;
    }
}

/**
 * Class RevRecSelectionValidator
 *
 * Validator implementation for revenue recognition selection.
 */
class RevRecSelectionValidator extends AbstractValidator
{
    /**
     * Validates correctness of the revenue recognition selection
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $ok = true;

        $updatesGL = isl_strtoupper($values['UPDATES_GL']);
        if ($updatesGL == 'N'
            && ($values['ENABLEREVREC'] == 'true'
            || $values['ENABLEREVREC'] == 'Post')
        ) {
            //if updatesgl is set to none and revrec is enabled trigger an error
            $msg = I18N::getSingleToken('IA.VALIDATE_REV_REC_SELECTION_ERROR_MESSAGE');
            Globals::$g->gErr->addIAError('INV-0415', __FILE__ . ':' . __LINE__, $msg, []);
            $ok = false;
        }
        return $ok;
    }
}

/**
 * Class PaymentProcessingValidator
 *
 * Validator implementaion for the payment processing fields selection
 */
class PaymentProcessingValidator extends AbstractValidator
{
    /**
     * Validates selection of payment processing fields for different use cases.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        global $kARid;
        $gErr = Globals::$g->gErr;
        $ok = true;

        $paymentBatchPref = GetPreferenceForProperty($kARid, 'RP_BATCHES');
        if ($values['ENABLEPAYMENTS'] == 'true') {
            if ($paymentBatchPref == 'O') {
                $gErr->addIAError(
                    'INV-0076', __FILE__ . ":" . __LINE__,
                    'Payment processing cannot work without Payments Auto-Batching enabled in AR', [],
                    '', [],
                    'Enable Payments Auto-Batching in AR', []
                );
                $ok = false;
            }
            if ($values['UPDATES_GL'] != 'A') {
                $gErr->addIAError('INV-0077', __FILE__ . ":" . __LINE__, 'Payment processing cannot be enabled because this transaction does not Post to AR', []);
                $ok = false;
            }
            if ($values['DOCCLASS'] != 'Invoice') {
                $gErr->addIAError('INV-0078', __FILE__ . ":" . __LINE__, 'Payment processing cannot be enabled because this transaction does not have a Template Class of Invoice', []);
                $ok = false;
            }
        } else {
            if (!empty($values['RECORDNO'])) {
                $soRecurDocumentManager = Globals::$g->gManagerFactory->getManager('sorecurdocument');
                $params = array();
                $params['filters'][0][] = array('NEXTEXECDATE', 'is not null');
                $params['filters'][0][] = array('PAYMETHOD', 'is not null');
                $params['filters'][0][] = array('PAYMETHOD', '<>', 'None');
                $params['filters'][0][] = array('DOCPARKEY', '=', $values['RECORDNO']);
                $soRecurDocumentCount = $soRecurDocumentManager->GetCount($params);
                if ($soRecurDocumentCount > 0) {
                    $gErr->addIAError(
                        'INV-0079', __FILE__.':'.__LINE__,
                        'Payments must be enabled for this Transaction Definition if at least one Order Entry Recurring Template with payment is scheduled for this Transaction Type', []
                    );
                }
            }
        }
        return $ok;
    }
}

/**
 * Class InventoryTotalsConsistencyValidator
 */
class InventoryTotalsConsistencyValidator extends AbstractValidator
{
    /**
     * Validates correctness of the user entry in the Inventory Total table.
     * Each record in the table must have the entered ADD / SUBTRACT value
     * matching the value entered in the Increases/Decreases Inventory and Billings
     * field (Increase / Decrease).
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $ok = true;

        if (isset($values['DOCPAR_TOTALS'])) {
            $IN_OUT_CHECK = ['Decrease' => 'Subtract', 'Increase' => 'Add'];

            // Read the selections on "Increases/Decreases Inventory"
            // drop down list box.
            $inout = $values['IN_OUT'];

            foreach ( $values['DOCPAR_TOTALS'] as $value) {
                $totalId = $value['TOTALID'];
                $sign = $value['SIGN'];
                if (isset($totalId) && 'ONHAND' === $totalId) {

                    if ($IN_OUT_CHECK[$inout] !== $sign) {
                        Globals::$g->gErr->addIAError(
                            'INV-0416', __FILE__ . ':' . __LINE__,
                            "Inconsistency in selection of $totalId inventory total " .
                            "with 'Increases/Decreases Inventory and Billings' field.",
                            ['TOTAL_ID' => $totalId]
                        );
                        $ok = false;
                        // Stop validation if error is found.
                        break;
                    }
                }
            }
        }
        return $ok;
    }
}

/**
 * Class SubtotalsTaxValidator
 *
 * Subtotals tax selection validator.
 */
class SubtotalsTaxValidator extends AbstractValidator
{
    /** @var bool $validateForVsoe */
    private $validateForVsoe = false;
    /** @var string $tdModule */
    private $tdModule;

    /**
     * @param string $tdModule
     */
    function __construct($tdModule) 
    {
        $this->tdModule = $tdModule;
        $this->validateForVsoe = ('so' === $tdModule);
    }

    /**
     * Validates correctness of the Tax check boxes selections
     * Is Tax / Apportioned / Select for Avalara on the Subtotals
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if ($values['SHOW_TOTALS'] == 'true') {
            /** @var ModuleSetupManager $setupMgr */
            $setupMgr = Globals::$g->gManagerFactory->getManager($this->tdModule . 'setup');
            $prefs = $setupMgr->get('');
            $avalaraSelectionCounter = [];

            foreach ( $values['DOCPAR_SUBTOTAL'] as $value) {
                $entityno = ( isset($value['ENTITYKEY']) && $value['ENTITYKEY'] != '') ? $value['ENTITYKEY'] : 0;

                if (!$value['GLACCOUNT'] && $value['APPORTIONED'] != 'true') {
                    if ($value['ISTAX'] == 'true') {
                        if ($prefs['TAXSCHED'] != 'true') {
                            $gErr->addIAError(
                                'INV-0417', __FILE__ . ":" . __LINE__,
                                "Select a GL account for the subtotal " . $value['DESCRIPTION'] . ", then try again.",
                                ['VALUE_DESCRIPTION' => $value['DESCRIPTION']]
                            );
                            $ok = false;
                            break;
                        }

                    } else {
                        $gErr->addIAError(
                            'INV-0418', __FILE__ . ":" . __LINE__,
                            "If the subtotal '" . $value['DESCRIPTION'] . "' is not being apportioned, then a GL account is required.",
                            ['VALUE_DESCRIPTION' => $value['DESCRIPTION']]
                        );
                        $ok = false;
                        break;
                    }
                }
                $isAvaAllowed = false;
                if (TaxSetupManager::isVATEnabled() && IsMultiEntityCompany()) {
                    $locn = GetContextLocation();
                    if (empty($locn)) {
                        $isAvaAllowed = true;
                    } else {
                        $taxSolnMngr = Globals::$g->gManagerFactory->getManager('taxsolution');
                        $isAvaAllowed = ($taxSolnMngr->getTaxMethodForLocn($locn) === TaxSolutionManager::TAXMETHOD_I_AVALARA);
                    }
                }

                if ($value['ISAVATAX'] == 'true' && $value['ISTAX'] != 'true' && !$isAvaAllowed) {
                    $gErr->addIAError(
                        'INV-0419',
                        __FILE__.":".__LINE__,
                        '"Select For Avalara" cannot be checked', [],
                        '"Is Tax" must be checked on line ' . $value['LINENO'] . ' because "Select For Avalara" is checked',['VALUE_LINENO' => $value['LINENO']],
                        'Check "Is Tax" or uncheck "Select For Avalara"',[]
                    );
                    $ok = false;
                    break;
                }

                // Only one Select For Avalara Check box can be selected
                if ($value['ISAVATAX'] == 'true') {
                    $avalaraSelectionCounter[$entityno]++;
                    if ($avalaraSelectionCounter[$entityno] > 1) {
                        $gErr->addIAError(
                            'INV-0080', __FILE__ . ":" . __LINE__,
                            "More than one Subtotal is checked for 'Select for Avalara'.", []
                        );
                        $ok = false;
                        break;

                    }
                }

                // if VAT is enabled and there is a tax line in the TD, we will not allow direct post to GL
                if ( $this->isVATEnabled()) {
                    // this is unlikely to happen via UI but can happen from API
                    if ($value['ISAVATAX'] == 'true' && !$isAvaAllowed) {
                        $gErr->addIAError(
                            'INV-0081',
                            __FILE__.":".__LINE__,
                            'You cannot use Avalara since VAT is enabled in this company', [],
                            '', [],
                            'Uncheck Select for Avalara', []
                        );
                        $ok = false;
                        break;
                    }
                }

                //VSOE constraint check for SO TD only.
                if ($this->validateForVsoe) {
                    if( SOSetupManager::isVsoeEnabled($prefs) && $values['ENABLEREVREC'] == 'Post') {
                        $ok = $this->validateVsoe($value);

                        if(!$ok) {
                            // No error messages here. The validateVsoe will put it.
                            break;
                        }
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * Validates the entry for the single Subtotal if the VSOE is selected.
     *
     * @param array $value
     *
     * @return bool
     */
    function validateVsoe($value)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if($value['DISC_CHARGE'] == 'Charge' && $value['APPORTIONED'] == 'true') {
            $ok = false;
            $gErr->addIAError(
                'INV-0420', __FILE__ . ":" . __LINE__,
                "When MEA Allocations enabled, if the subtotal '"
                . $value['DESCRIPTION'] . "' is a 'Charge' type, it can not be apportioned.",
                ['VALUE_DESCRIPTION' => $value['DESCRIPTION']]
            );
        }

        if($value['DISC_CHARGE'] == 'Discount' && $value['APPORTIONED'] != 'true') {
            $ok = false;
            $gErr->addIAError(
                'INV-0421', __FILE__ . ":" . __LINE__,
                "When MEA Allocations are enabled, if the subtotal '"
                . $value['DESCRIPTION'] . "' is a 'Discount' type, it must be apportioned.",
                ['VALUE_DESCRIPTION' => $value['DESCRIPTION']]
            );
        }
        return $ok;
    }

    /**
     * determines if VAT is enabled for this module
     * for now only PO and SO have VAT enabling , INV doesn't
     *
     * @return bool
     */
    function isVATEnabled()
    {
        if ( $this->tdModule == 'po' || $this->tdModule == 'so' ) {
            return TaxSetupManager::isVATEnabled();
        } else {
            return false;
        }
    }
}

/**
 * Class MandatoryFieldsValidator
 */
class MandatoryFieldsValidator extends AbstractValidator
{
    /**
     * Validates mandatory fields that are always have values in case of a
     * request coming from UI.
     * This method is essential only for API calls and CSV imports.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $mandatoryFields = array(
            array(
                'path' => 'DOCCLASS',
                'error' => 'The value for the mandatory Template Class field is not provided',
                'errorCode' => 'INV-0422'
            ),
            array(
                'path' => 'CATEGORY',
                'error' => 'The value for the mandatory Overview map/Menu category field is not provided',
                'errorCode' => 'INV-0423'
            ),
            array(
                'path' => 'DOCID',
                'error' => 'The value for the mandatory Template Name field is not provided',
                'errorCode' => 'INV-0424'
            ),
        );
        foreach ( $mandatoryFields as $field) {
            if (!isset($values[$field['path']])) {
                $ok = false;
                $gErr->addIAError(
                    $field['errorCode'],
                    __FILE__ . ":" . __LINE__,
                    $field['error'], []
                );
            }
        }
        return $ok;
    }
}

class COGSValidator extends AbstractValidator
{

    /**
     * When the TD is affecting Value, then in the posting configuration, the COGS account mapping should be affected.
     *
     * The COGS account mapping should have atleast one credit debit pair
     *
     * Inventory control and Order Entry incorporates COGS validation.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        if (!IsAdvancedConfiguration()) {
            return true;
        }

        $gErr = Globals::$g->gErr;

        /* @var bool $isCOGSValidationRequired */
        $isCOGSValidationRequired = false;

        /* @var bool $ok */
        $ok = true;

        // If the transaction is created during system configuration then this validation will be excluded
        if(isset($values['SYSTEM_GENERATED']) && $values['SYSTEM_GENERATED']){
            return true;
        }

        foreach ( (($values['DOCPAR_TOTALS']) ?? []) as $value) {
            $inventoryTotal = $value['TOTALID'];
            if (isset($inventoryTotal) && 'ONHAND' === $inventoryTotal) {
                $maintain = $value['Q_QV'];
                if (isset($maintain) && ('Value' === $maintain || 'Quantity & Value' === $maintain)) {
                    $isCOGSValidationRequired = true;
                }
            }
        }

        if ($values['SALE_PUR_TRANS'] == 'Internal') {
            $isCOGSValidationRequired = $isCOGSValidationRequired && ($values['UPDATES_GL'] == 'G');
        }

        if ($isCOGSValidationRequired) {
            if (empty($values['DOCPAR_INVGL'])) {
                $gErr->addIAError(
                    'INV-0425', __FILE__ . ":" . __LINE__,
                    "The transaction definition " . $values['DOCID'] . " is defined to affect ONHAND Value or Quantity & Value. Add at least one debit/credit account pair to the COGS/Inventory account mapping table on the Posting configuration tab and then try saving the transaction definition again.",
                    ['VALUES_DOCID' => $values['DOCID']]
                    );
                return false;
            }

            $accountCounters = ['Debit' => [], 'Credit' => []];
            $processedAccounts = array();

            foreach ($values['DOCPAR_INVGL'] as $value) {
                $dc = $value['DEBIT_CREDIT'];

                $acctsMapKey = (isArrayValueProvided($value, 'ITEM_GLGROUP') ? $value['ITEM_GLGROUP'] : "null") . ":" .
                    (isArrayValueProvided($value, 'WAREHOUSE') ? $value['WAREHOUSE'] : "null") . ":" .
                    (isArrayValueProvided($value, 'ENT_GLGROUP') ? $value['ENT_GLGROUP'] : "null");

                $accountCounters[$dc][] = $acctsMapKey;
                $processedAccounts[] = $acctsMapKey;
            }

            if (count($accountCounters['Debit']) !== 0 && count($accountCounters['Credit']) !== 0) {
                foreach ($processedAccounts as $val) {
                    if (!(in_array($val, $accountCounters['Credit']) && in_array($val, $accountCounters['Debit']))) {
                        $cogsAcct = explode(':', $val);
                        $itemGLGrp = $cogsAcct[0];
                        $whse = $cogsAcct[1];
                        $entityGLGrp = $cogsAcct[2];
                        $checkMap = array();
                        $creDeb = '';

                        if (in_array($val, $accountCounters['Credit'])) {
                            $creDeb = "Debit";
                            $checkMap = $accountCounters['Debit'];
                        } else if (in_array($val, $accountCounters['Debit'])) {
                            $creDeb = "Credit";
                            $checkMap = $accountCounters['Credit'];
                        }

                        $isMatchFound = false;

                        foreach ($checkMap as $iterVal) {
                            $cogsAcct_Iter = explode(':', $iterVal);
                            $itemGLGrp_Iter = $cogsAcct_Iter[0];
                            $whse_Iter = $cogsAcct_Iter[1];
                            $entityGLGrp_Iter = $cogsAcct_Iter[2];
                            if ((($itemGLGrp_Iter === $itemGLGrp || $itemGLGrp === "null" || $itemGLGrp_Iter === "null")
                                && ($whse === $whse_Iter || $whse === "null" || $whse_Iter === "null")
                                && ($entityGLGrp === $entityGLGrp_Iter || $entityGLGrp === "null" || $entityGLGrp_Iter === "null"))) {
                                $isMatchFound = true;
                                break;
                            }
                        }

                        if(!$isMatchFound)
                        {
                            $lineNum = (array_search($val, $processedAccounts) + 1);
                            $gErr->addIAError(
                                'INV-0426', __FILE__ . ":" . __LINE__,
                                "No account marked as $creDeb is found in line #$lineNum in the 'COGS account mapping' table.",
                                ['CRE_DEB' => $creDeb, 'LINE_NUM' => $lineNum]
                            );
                            $ok = false;
                        }
                    }
                }
            }
        }

        return $ok;
    }
}

class AdditionalGLValidator extends AbstractValidator
{

    /**
     * When the TD is enabled for Additional GL posting, then in the posting configuration
     *
     * the Additional GL posting account mapping should have atleast one credit debit pair
     *
     * only Order Entry incorporates Additional GL posting validation.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        if (!IsAdvancedConfiguration()) {
            return true;
        }

        $gErr = Globals::$g->gErr;

        /* @var bool $ok */
        $ok = true;

        // If the transaction is created during system configuration then this validation will be excluded
        if(isset($values['SYSTEM_GENERATED']) && $values['SYSTEM_GENERATED']){
            return true;
        }

        if ($values['SALE_PUR_TRANS'] !== 'Sale') {
            return true;
        }

        $additionalGLPostingEnabled = isArrayValueProvided($values, 'POSTTOGL') && "true" === $values['POSTTOGL'];

        if(!$additionalGLPostingEnabled){
            return true;
        }

        // In Sales TD If 'Additional GL posting' is enabled when directly posting to GL throw error
        if ($additionalGLPostingEnabled && ($values['UPDATES_GL'] == 'G' || $values['UPDATES_GL'] == 'N')) {
            $msg = "If the transaction definition " . $values['DOCID'];
            $msg .= " is posting to directly to General Ledger or Don't Post.";
            $msg .= " Then enabling additional GL posting is not allowed.";

            $gErr->addIAError('INV-0427',
                __FILE__ . ":" . __LINE__,
                $msg, ['VALUES_DOCID' => $values['DOCID']]
            );
            return false;
        }

        if (empty($values['DOCPAR_ADDGL'])) {
            $msg = "The transaction definition " . $values['DOCID'] . " has enabled additional posting.";
            $msg .= "Add at least one debit/credit account pair to the Additional GL posting account mapping table";
            $msg .= "on the Posting configuration tab and then try saving the transaction definition again.";

            $gErr->addIAError('INV-0428',
                __FILE__ . ":" . __LINE__,
                $msg, ['VALUES_DOCID' => $values['DOCID']]
            );
            return false;
        }

        $accountCounters = ['Debit' => [], 'Credit' => []];
        $processedAccounts = array();

        foreach ($values['DOCPAR_ADDGL'] as $value) {
            $dc = $value['DEBIT_CREDIT'];

            $acctsMapKey = (isArrayValueProvided($value, 'ITEM_GLGROUP') ? $value['ITEM_GLGROUP'] : "null") . ":" .
                (isArrayValueProvided($value, 'WAREHOUSE') ? $value['WAREHOUSE'] : "null") ;

            $accountCounters[$dc][] = $acctsMapKey;
            $processedAccounts[] = $acctsMapKey;
        }

        if (count($accountCounters['Debit']) !== 0 || count($accountCounters['Credit']) !== 0) {
            foreach ($processedAccounts as $val) {
                if (!(in_array($val, $accountCounters['Credit']) && in_array($val, $accountCounters['Debit']))) {
                    $addGLAcct = explode(':', $val);
                    $itemGLGrp = $addGLAcct[0];
                    $whse = $addGLAcct[1];

                    $checkMap = array();
                    $creDeb = '';

                    if (in_array($val, $accountCounters['Credit'])) {
                        $creDeb = "Debit";
                        $checkMap = $accountCounters['Debit'];
                    } else if (in_array($val, $accountCounters['Debit'])) {
                        $creDeb = "Credit";
                        $checkMap = $accountCounters['Credit'];
                    }

                    $isMatchFound = false;

                    foreach ($checkMap as $iterVal) {
                        $addGLAcct_Iter = explode(':', $iterVal);
                        $itemGLGrp_Iter = $addGLAcct_Iter[0];
                        $whse_Iter = $addGLAcct_Iter[1];

                        if (($itemGLGrp_Iter === $itemGLGrp || $itemGLGrp === "null" || $itemGLGrp_Iter === "null")
                            && ($whse === $whse_Iter || $whse === "null" || $whse_Iter === "null")
                            ) {
                            $isMatchFound = true;
                            break;
                        }
                    }

                    if(!$isMatchFound)
                    {
                        $lineNum = (array_search($val, $processedAccounts) + 1);
                        $msg = "No account marked as $creDeb is found in line #$lineNum";
                        $msg .= "in the 'Additional GL posting account mapping' table.";
                        $gErr->addIAError('INV-0429',
                            __FILE__ . ":" . __LINE__,
                            $msg, ['CRE_DEB' => $creDeb, 'LINE_NUM' => $lineNum]
                        );
                        $ok = false;
                    }
                }
            }
        }

        return $ok;
    }
}

/**
 * Class AccountMappingValidator
 */
class AccountMappingValidator extends AbstractValidator
{
    const DOCPAR_INVGL = 'DOCPAR_INVGL';
    const DOCPAR_PRGL = 'DOCPAR_PRGL';

    /* @var string $mapping */
    private $mapping;

    /* @var bool $checkForIsoffset */
    private $checkForIsoffset;

    /** @var string $accountMappingTitle */
    private $accountMappingTitle;

    /** @var bool $checkForSingleAccount */
    private $checkForSingleAccount = false;

    /**
     * Public setter for the fields array.
     *
     * @param array $fields
     */
    public function setFields(array $fields)
    {
        parent::setFields($fields);
        $this->checkForIsoffset = false;
        foreach ( $fields as $field => $checkForUniqueness) {
            if ('ISOFFSET' === $field) {
                $this->checkForIsoffset = true;
                break;
            }
        }
    }

    /**
     * Public setter for the mapping field.
     *
     * @param string $mapping
     */
    public function setMapping($mapping)
    {
        $this->mapping = $mapping;
    }

    /**
     * Setter for title on the account mapping section.
     *
     * @param string $title
     */
    public function setAccountMappingTitle($title) 
    {
        $this->accountMappingTitle = $title;
    }

    /**
     * @param bool $checkForSingleAccount
     */
    public function setCheckForSingleAccount($checkForSingleAccount) 
    {
        $this->checkForSingleAccount = $checkForSingleAccount;
    }

    /**
     * Verifies if the GL Account is provided if at least one of "unique"
     * fields is provided.
     *
     * @param string[] $record
     *
     * @return bool
     */
    function validateMandatoryGLAccount($record)
    {
        $glAccountValid = true;
        $checkForMandatoryGLAccount = false;

        foreach ($this->fields as $fieldKey => $field) {
            $checkForUniqueness = $field['checkForUniqueness'];
            if ($checkForUniqueness) {
                if (isset($record[$fieldKey]) && '' !== $record[$fieldKey]) {
                    $checkForMandatoryGLAccount = true;
                    break;
                }
            }
        }
        if ($checkForMandatoryGLAccount) {
            $glAccountValue = $record['GLACCOUNT'];
            $glAccountValid = (isset($glAccountValue) && '' !== $glAccountValue);
        }
        return $glAccountValid;

    }
    /**
     * Validates the user input on account mapping.
     *
     * THIS VALIDATION IS FOR ADVANCED SETUP ONLY
     *
     * The validation rules are as follows:
     * 1. For the records with matching input in designated fields the
     *    duplication is allowed only if the mapping type is different
     *    (DEBIT / CREDIT).
     * 2. If all the designated fields are the same as well as the provided
     *    GL Account but the mapping type is different those two records are
     *    considered valid.
     * 3. If the user input for IS OFFSET is provided, it has to be selected
     *    against the same mapping type.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $hasOffset = false;
        $ok = true;

        if (!IsAdvancedConfiguration()) {
            return $ok;
        }

        $processedAccounts = ['Debit' => [], 'Credit' => []];
        $accounts = ['Debit' => 'Credit', 'Credit' => 'Debit'];
        $mappingType = '';
        $records = $values[$this->mapping];
        $uniqueRecords = array();
        $lineNumber = 1;
        $accountCounters = ['Debit' => [], 'Credit' => []];
        if ( $records && is_array($records) ) {
            foreach ( $records as $record ) {
                // First check if there is a GL account
                if ( !$this->validateMandatoryGLAccount($record) ) {
                    $gErr->addIAError(
                        'INV-0430', __FILE__ . ":" . __LINE__,
                        "Missing GL Account on line #$lineNumber " .
                        "in the '$this->accountMappingTitle' table.",
                        ['LINE_NUMBER' => $lineNumber, 'ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                    );
                    $ok = false;
                    break;
                }

                // Consider only records with valid GL accounts
                $glaccount = $record['GLACCOUNT'];
                if ( isset($glaccount) ) {
                    // First check if the record is valid
                    $ok = $ok && $this->validateSingleRecord($record, $this->fields, $lineNumber);
                    if ( $ok ) {
                        // If GL account is provided Debit / Credit is mandatory
                        $dc = $record['DEBIT_CREDIT'];
                        if ( !isset($dc) ) {
                            $gErr->addIAError(
                                'INV-0431', __FILE__ . ":" . __LINE__,
                                "No value is selected for Debit/Credit on line #$lineNumber " .
                                "in the '$this->accountMappingTitle' table.",
                                ['LINE_NUMBER' => $lineNumber, 'ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                            );
                            $ok = false;
                            break;
                        }

                        $accountCounters[$dc][] = $glaccount;

                        if ( $this->checkForSingleAccount && 'A' === $values['UPDATES_GL'] ) {
                            $itemKey = $glaccount . ":" .
                                       ( isArrayValueProvided($record, 'ITEM_GLGROUP') ? $record['ITEM_GLGROUP']
                                           : "null" ) . ":" .
                                       ( isArrayValueProvided($record, 'WAREHOUSE') ? $record['WAREHOUSE'] : "null" )
                                       . ":" .
                                       ( isArrayValueProvided($record, 'ENT_GLGROUP') ? $record['ENT_GLGROUP']
                                           : "null" );
                            if ( in_array($itemKey, $processedAccounts[$accounts[$dc]]??[]) ) {
                                $gErr->addIAError(
                                    'INV-0432', __FILE__ . ":" . __LINE__,
                                    "The same GL account '$glaccount' is marked for both " .
                                    "Debit and Credit in the '$this->accountMappingTitle' table.",
                                    ['GLACCOUNT' => $glaccount, 'ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                                );
                                $ok = false;
                                break;
                            } else {
                                $processedAccounts[$dc][] = $itemKey;
                            }
                        }

                        // Continue validation only if the fields in the record
                        // are referencing valid entities / values
                        $uniqueRecord = "";
                        foreach ( $this->fields as $fieldKey => $field ) {
                            $checkForUniqueness = $field['checkForUniqueness'];
                            if ( $checkForUniqueness ) {
                                $uniqueRecord = $uniqueRecord .
                                                ( $record[$fieldKey] ?? "null" )
                                                . ":";
                            }
                        }
                        if ( in_array($uniqueRecord, $uniqueRecords) ) {
                            $gErr->addIAError(
                                'INV-0433', __FILE__ . ":" . __LINE__,
                                "Duplicate mapping is found on line #$lineNumber " .
                                "in the '$this->accountMappingTitle' table.",
                                ['LINE_NUMBER' => $lineNumber, 'ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                            );
                            $ok = false;
                            break;
                        } else {
                            $uniqueRecords[] = $uniqueRecord;
                        }

                        if ( $this->checkForIsoffset ) {
                            if ( '' !== $mappingType && isset($record['ISOFFSET']) ) {
                                if ( 'true' === $record['ISOFFSET'] && $mappingType !== $record['DEBIT_CREDIT'] ) {
                                    $gErr->addIAError(
                                        'INV-0434', __FILE__ . ":" . __LINE__,
                                        "Incorrect entry for 'IS OFFSET' is found on line #$lineNumber " .
                                        "in the '$this->accountMappingTitle' table. " .
                                        "'IS OFFSET' can be selected only against the same mapping type.",
                                        ['LINE_NUMBER' => $lineNumber, 'ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                                    );
                                    $ok = false;
                                    break;
                                }
                            } else {
                                if ( isset($record['ISOFFSET']) && 'true' === $record['ISOFFSET'] ) {
                                    $mappingType = $record['DEBIT_CREDIT'];
                                    $hasOffset = true;
                                }
                            }
                        }
                    }
                }
                $lineNumber++;
            }
        }

        if (sizeof($accountCounters['Credit']) > 0 || sizeof($accountCounters['Debit']) > 0) {
            if (sizeof($accountCounters['Credit']) == 0) {
                $gErr->addIAError(
                    'INV-0435', __FILE__ . ":" . __LINE__,
                    "No account marked as 'Credit' is found " .
                    "in the '$this->accountMappingTitle' table. ",
                    ['ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                );
                $ok = false;
            }
            if (sizeof($accountCounters['Debit']) == 0) {
                $gErr->addIAError(
                    'INV-0436', __FILE__ . ":" . __LINE__,
                    "No account marked as 'Debit' is found " .
                    "in the '$this->accountMappingTitle' table. ",
                    ['ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                );
                $ok = false;
            }
            if (($values['TD_MODULE'] == 'po' || $values['TD_MODULE'] == 'so') && $values['UPDATES_GL'] == 'A') {
                if (!$hasOffset && $this->checkForIsoffset) {
                    $gErr->addIAError(
                        'INV-0437', __FILE__ . ":" . __LINE__,
                        "No account marked as 'OFFSET' is found " .
                        " in the '$this->accountMappingTitle' table.",
                        ['ACCOUNT_MAPPING_TITLE' => $this->accountMappingTitle]
                    );
                    $ok = false;
                }
            }
        }
        return $ok;
    }

}

/**
 * Class InventoryTotalsValidator
 *
 * Validator class checking for correctness of the inventory totals.
 */
class InventoryTotalsValidator extends AbstractValidator
{

    /**
     * Validates the user entry in the Inventory Totals table. The rules are
     * as follows:
     * - No two records are allowed for the same Inventory total.
     * - All the provided data must be valid.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if (isset($values['DOCPAR_TOTALS'])) {

            $processedTotals = array();
            $lineNumber = 1;
            foreach ($values['DOCPAR_TOTALS'] as $record) {
                $totalId = $record['TOTALID'];
                if (isset($totalId)) {
                    // Check if the record is valid
                    $ok = $ok && $this->validateSingleRecord($record, $this->fields, $lineNumber);
                    if ($ok) {
                        if (in_array($totalId, $processedTotals)) {
                            $gErr->addIAError(
                                'INV-0438', __FILE__ . ":" . __LINE__,
                                "Duplicate 'Inventory Total' is found on line #$lineNumber.",
                                ['LINE_NUMBER' => $lineNumber]
                            );
                            $ok = false;
                            break;
                        } else {
                            $processedTotals[] = $totalId;
                        }
                    }
                }
                $lineNumber++;
            }
        }
        return $ok;
    }

    /**
     * Creates an instance of the InventoryTotalsValidator class.
     *
     * @return InventoryTotalsValidator
     */
    public static function getInstance()
    {
        $validator = new self();
        $validator->setFields(
            array(
                'TOTALID' => array('checkForUniqueness' => true, 'entity' => 'invtotal', 'activeOnly' => true),
                'Q_QV' => array('checkForUniqueness' => false, 'validValues' => array('Quantity','Value', 'Quantity & Value')),
                'SIGN' => array('checkForUniqueness' => false, 'validValues' => array('Add','Subtract')),
            )
        );
        return $validator;
    }
}

/**
 * Class DocumentNameValidator
 *
 * Validator class checking for the document name. Has to be called
 * only upon update
 */
class DocumentNameValidator extends AbstractValidator
{
    /**
     * @var DocumentParamsManager $manager
     */
    private $manager;

    /**
     * @param DocumentParamsManager $manager
     */
    function __construct(DocumentParamsManager $manager)
    {
        $this->manager = $manager;
    }

    /**
     * Confirms that the DOCID of the updated template hasn't been changed.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $filter = array(
            'selects' => array('DOCID'),
            'filters' => array(array(array('RECORDNO', '=', $values['RECORDNO'])))
        );
        $res = $this->manager->GetList($filter);
        if (!isset($res[0]['DOCID']) || $res[0]['DOCID'] != $values['DOCID']) {
            $gErr->addIAError(
                'INV-0082', __FILE__ . ":" . __LINE__,
                "The transaction definition cannot be renamed once it has been created.", []
            );
            $ok = false;
        }
        return $ok;
    }
}

/**
 * Class RenewalsSelectionValidator
 *
 * Validator implementation for the renewals selection.
 */
class RenewalsSelectionValidator extends AbstractValidator
{
    /**
     * Validates that the numbering scheme (pattern) is provided if the
     * Enable renewals is set to any value other than Don't Enable.
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values) {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if (($values['ENABLERENEWALS'] === 'Generate' || $values['ENABLERENEWALS'] === 'Display Only') &&
            !isArrayValueProvided($values, 'SEQUENCE')) {
            $gErr->addIAError(
                'INV-0083', __FILE__ . ':' . __LINE__,
                "'Numbering sequence' is required if 'Enable renewals' is " .
                "set to 'Generate' or 'Display Only' renewals fields.", []
            );
            $ok = false;
        }
        return $ok;
    }
}

/**
 * Class ExtPriceDiscSelectionValidator
 *
 * Validator class for extended price discount selection.
 */
class ExtPriceDiscSelectionValidator extends AbstractValidator
{
    /**
     * Validates that the discount calculation on extentded price is set only
     * when discount is enabled in TD and the company is enabled for 'Contracts'
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if ($values['DISCOUNT_ON_EXTENDEDPRICE'] === 'true'
            && $values['ENABLE_DISCOUNT_CHARGE'] !== 'true'
        ) {
            $gErr->addIAError(
                'INV-0084', __FILE__ . ':' . __LINE__,
                "'Track line item discount/surcharge' " .
                "is required if 'Enable for Contracts' is set", []
            );
            $ok = false;
        }

        if ($values['DISCOUNT_ON_EXTENDEDPRICE'] === 'true'
            && IsInstalled(Globals::$g->kCNid) === 'false'
        ) {
            $gErr->addIAError(
                'INV-0085', __FILE__ . ':' . __LINE__,
                "'Contracts' must be enabled  " .
                " to select 'Enable for Contracts' option.", []
            );
            $ok = false;
        }


        return $ok;
    }
}

/**
 * Class EntityPropertiesValidator
 *
 * Validator class for checking provided entity details.
 */
class EntityPropertiesValidator extends AbstractValidator
{
    /**
     * Validates completeness and correctness of the Entity Specific data.
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if (isset($values['DOCPAR_ENTITY_PROPS'])) {
            // Subtotal template are validated later so no need to use this construct
            $this->setFields(
                array(
                    'ENTITY_NAME' => array('entity' => 'locationentity', 'activeOnly' => true),
                    'SEQUENCE' => array('entity' => 'seqnum', 'activeOnly' => true),
                    'PRESERVE_SEQNUM' => array('validValues' => array('true', 'false')),
                    'INHERIT_SOURCE_DOCNO' => array('validValues' => array('true', 'false')),
                    'XSLTEMPLATE' => array('entity' => 'tplformat', 'activeOnly' => true),
                    'ENTITY_CREATION_RULE' => array('validValues' => array('true', 'false')),
                    'SHOWEXPANDEDTOTALS' => array('validValues' => array('true', 'false')),
                    'ENABLEOVERRIDETAX' => array('validValues' => array('true', 'false')),
                    'LINELEVELSIMPLETAX' => array('validValues' => array('true', 'false')),
                )
            );

            $processedEntities = array();
            $lineNumber = 1;
            foreach ($values['DOCPAR_ENTITY_PROPS'] as $record) {
                $entityName = $record['ENTITY_NAME'];
                if (isset($entityName)) {
                    // Check if the record is valid
                    $ok = $ok && $this->validateSingleRecord($record, $this->fields, $lineNumber);
                    if ($ok) {
                        if (in_array($entityName, $processedEntities)) {
                            $gErr->addIAError(
                                'INV-0439', __FILE__ . ":" . __LINE__,
                                "Duplicate 'Entity Name' is found on line #$lineNumber for Entity Settings.",
                                ['LINE_NUMBER' => $lineNumber]
                            );
                            $ok = false;
                            break;
                        } else {
                            $processedEntities[] = $entityName;
                        }
                    }

                    // If the entity name is provided the creation rule is required
                    if (!isArrayValueProvided($record, 'ENTITY_CREATION_RULE')) {
                        $gErr->addIAError(
                            'INV-0440', __FILE__ . ":" . __LINE__,
                            "The 'Create transaction in' field setting is not provided on line #$lineNumber for Entity Settings.",
                            ['LINE_NUMBER' => $lineNumber]
                        );
                        $ok = false;
                        break;
                    }
                }
                $lineNumber++;
            }
        }
        return $ok;
    }
}

/**
 * Class AllocationValidator
 *
 * Implementation of validation for allocations in PO documents
 */
class AllocationValidator extends AbstractValidator
{
    /**
     * Validates mandatory CONTACTTITLE1 and CONTACTTITLE2 fields.
     *
     * @param array $values
     * @return bool
     */
    function validate($values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        /**
         * the preference in GL/AP should not be allowed to diable if there are any TD in PO enabled allocations.
         */

        //
        // If AP has not enabled allocation
        $apAllocationEnabled = GetPreferenceForProperty(Globals::$g->kAPid, 'USEALLOCATION') == 'Y';
        if (!$apAllocationEnabled && isl_strtolower($values['ALLOW_ALLOCATIONS']) == 'true') {
            $gErr->addIAError(
                'INV-0086',
                __FILE__ . ":" . __LINE__,
                'Unable to create record.', [],
                'To enable allocations for the transaction definition, first enable allocation in Accounts Payable.', []
            );
            $ok = false;
        }

        //
        // don't allow if any of the subtotal is marked 'Apportioned'
        $docParSubtotals = $values['DOCPAR_SUBTOTAL'] ?? null;
        if ( $docParSubtotals && is_array($docParSubtotals) ) {
            foreach ( $docParSubtotals as $value ) {
                if ( $value['APPORTIONED'] === 'true' && isl_strtolower($values['ALLOW_ALLOCATIONS']) == 'true' ) {
                    $desc2 = 'Allocations can be enabled only when none of the subtotal lines are apportioned.' .
                        ' Either deselect the Enable allocations checkbox or the Apportioned checkboxes for the subtotal lines.';
                    $gErr->addIAError(
                        'INV-0441', __FILE__ . ':' . __LINE__,
                        'Unable to create record.', [],
                        $desc2, []
                    );
                    $ok = false;
                    break;
                }

                if ( $value['ISAVATAX'] === 'true' && isl_strtolower($values['ALLOW_ALLOCATIONS']) == 'true' ) {
                    $gErr->addIAError(
                        'INV-0087', __FILE__ . ':' . __LINE__,
                        "Allocations can be enabled only when none of subtotal lines are selected for Avalara.", [],
                        " Either deselect the Enable allocations checkbox or the Avalara checkboxes for the subtotal lines.", []
                    );
                    $ok = false;
                    break;
                }
            }
        }

        //
        // don't allow if Location and Department can't be overridden.
        if (isl_strtolower($values['ALLOW_ALLOCATIONS']) == 'true' &&
            (isl_strtolower($values['LOCOVERRIDE']) != 'true')
        ) {
            $gErr->addIAError(
                'INV-0088', __FILE__ . ':' . __LINE__,
                "To enable allocations, select Location as a user override.", []
            );
            $ok = false;
        }

        return $ok;
    }
}

/**
 * Class ProjectContractBillingValidator
 * 
 * Validates the Enable project contract billing setting.  ENABLECONTRACTBILLING
 */
class ProjectContractBillingValidator extends AbstractValidator
{
    /**
     * @param array $values
     * @return bool
     */
    function validate($values) {
        if (isset($values['ENABLECONTRACTBILLING']) && $values['ENABLECONTRACTBILLING'] == 'true') {
            if(isset($values['_edittype']) && $values['_edittype'] == 'duplicate'){
                unset($values['DOCPAR_CONVERTTO']);
            }
            $convertToDocIDs = [];
            foreach ($values['DOCPAR_CONVERTTO'] ?? [] as $convertToDocpar) {
                $convertToDocIDs[] = $convertToDocpar['TODOCPAR'];
            }
            
            if (isEmptyArray($convertToDocIDs)) {
                // This document is not setup to convert to any other document.
                return true;
            }
            
            $stmt = [];
            $stmt[0] = " select r.docid, r.enable_contract_billing from docparmst r where r.cny# = :1 and latestversionkey is null";
            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, $convertToDocIDs, " and docid ");
            $convertToDocs = QueryResult($stmt);

            if (!$convertToDocs) {
                // No documents were found that can be converted from this document.
                return true;
            }
            
            foreach ($convertToDocs as $convertToDoc) {
                if (!isset($convertToDoc['ENABLE_CONTRACT_BILLING']) || $convertToDoc['ENABLE_CONTRACT_BILLING'] == 'F') {
                    Globals::$g->gErr->addIAError(
                        'INV-0442', __FILE__ . ':' . __LINE__,
                        "You attempted to enable project contract billing on an originating transaction definition ".
                        "set up in a conversion workflow.", [],
                        '', [],
                        sprintf("Ensure that you enable project contract billing on all definitions in that conversion ".
                            "workflow and try again. (%s)", $convertToDoc['DOCID']), ['CONVERT_TO_DOC_DOCID' => $convertToDoc['DOCID']]
                    );
                    return false;
                }
            }
        }
        
        return true;
    }
}

/**
 * Class RetainageSelectionValidator
 *
 * Validator implementation for the retainage selection.
 */
class RetainageSelectionValidator extends AbstractValidator
{
    /** @var string $tdModule */
    private $tdModule;
    
    /**
     * @param string $tdModule
     */
    public function __construct($tdModule)
    {
        $this->tdModule = $tdModule;
    }

    /**
     * Validates that the retainage feature related scenarios
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values) {
        $gErr = Globals::$g->gErr;
        $ok = true;

        // Validation when retainage is enabled
        if ( isset($values['ENABLE_RETAINAGE']) && $values['ENABLE_RETAINAGE'] !== 'false' && $values['ENABLE_RETAINAGE'] !== '' ) {

            if ($this->tdModule == 'po' && !CRESetupManager::isAPRetainageEnabled()) {
                $gErr->addIAError(
                    'INV-0089', __FILE__ . ':' . __LINE__,
                    "Retainage feature must first be enabled in AP.", []
                );
                $ok = false;
            }
            else if ($this->tdModule == 'so' && !CRESetupManager::isARRetainageEnabled()) {
                $gErr->addIAError(
                    'INV-0090', __FILE__ . ':' . __LINE__,
                    "Retainage feature must first be enabled in AR.", []
                );
                $ok = false;
            }
            
            $isAdvancedConfiguration = IsAdvancedConfiguration();
            if (!$isAdvancedConfiguration) {
                $gErr->addIAError(
                    'INV-0091', __FILE__ . ':' . __LINE__,
                    "Retainage feature is only supported in Advanced configuration setup.", []
                );
                $ok = false;
            }

            if (!isset($values['ENABLECONTRACTBILLING']) || $values['ENABLECONTRACTBILLING'] != 'true') {
                if ('Invoice' === $values['DOCCLASS'] && 'A' !== $values['UPDATES_GL']) {
                    $gErr->addIAError(
                        'INV-0092', __FILE__ . ':' . __LINE__,
                        "Retainage cannot be enabled because this transaction does not post to AP/AR.", []
                    );
                    $ok = false;
                }
            }

            if ('Return' == $values['CATEGORY']) {
                $gErr->addIAError(
                    'INV-0093', __FILE__ . ':' . __LINE__,
                    "Retainage can not be enabled for Workflow category: Return.", []
                );
                $ok = false;
            }

            if ('Close Original and Create Back Order' == $values['CONVTYPE'] && 'A' == $values['UPDATES_GL']) {
                $gErr->addIAError(
                    'INV-0094', __FILE__ . ':' . __LINE__,
                    "Retainage is not supported for Partial conversion handling as 'Close Original and Create Back Order'", []
                );
                $ok = false;
            }

            if (isset($values['ENABLESCHEDULE']) && "true" === $values['ENABLESCHEDULE']) {
                $gErr->addIAError(
                    'INV-0095', __FILE__ . ':' . __LINE__,
                    "Retainage is not supported when 'line item conversion' is enabled.", []
                );
                $ok = false;
            }

            if (isset($values['ENABLERENEWALS']) && ('Generate' === $values['ENABLERENEWALS'] || 'Display Only' === $values['ENABLERENEWALS'])) {
                $gErr->addIAError(
                    'INV-0096', __FILE__ . ':' . __LINE__,
                    "Retainage is not supported when Renewals feature is enabled.", []
                );
                $ok = false;
            }

            // apportioning valiations for retainage
            if ($values['SHOW_TOTALS'] == 'true') {
                foreach ($values['DOCPAR_SUBTOTAL'] as $subtotal) {
                    if ($subtotal['APPORTIONED'] === 'true') {
                        $gErr->addIAError(
                            'INV-0443', __FILE__ . ':' . __LINE__,
                            sprintf("When retainage is enabled, the subtotal '%s' cannot be apportioned.", $subtotal['DESCRIPTION']),
                            ['SUBTOTAL_DESCRIPTION' => $subtotal['DESCRIPTION']]
                        );
                        $ok = false;
                    }
                }
            }
        }

        return $ok;
    }
}



/**
 * Class ThreewayMatchValidator
 *
 * Validator implementation for threeway match.
 */
class ThreewayMatchValidator extends AbstractValidator
{
    /**
     * Validates threeway match setup
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values) {
        $gErr = Globals::$g->gErr;
        $ok = true;

        $threeWayMatchEnabled = ThreeWayMatchHandler::checkIfThreeWayMatchEnabled($values['DOCID'],
                                                                                  $threeWayMatchGridPref, $threeWayMatchGLAccount);
        // Validation when threeway match is enabled and for this TD
        if ($threeWayMatchEnabled) {
            $recallDocparArray = [];
            if (!empty($values['DOCPAR_RECALLS'])) {
                foreach ( $values['DOCPAR_RECALLS'] as $recallDocpar ) {
                    $recallDocparArray[] = $recallDocpar['RECDOCPAR'];
                }
                $stmt = [];
                $stmt[0] = " select r.docid from docparmst r where r.cny# = :1 and r.convtype = :2 and latestversionkey is null";
                $stmt[1] = GetMyCompany();
                $stmt[2] = 'B';
                $stmt = PrepINClauseStmt($stmt, $recallDocparArray, " and docid ");
                $recallDocuments = QueryResult($stmt);

                if ( ! empty($recallDocuments) ) {
                    $msg = $values['DOCID']
                           . " this transaction definition is enabled for match tolerance validation. It can only be converted from transactions that have a partial conversion handling setting that leaves the converted from transaction open or closed.";
                    $corr = "Configure " . $values['DOCID'] . " to be converted from transactions that don’t create backorders.";
                    $gErr->addIAError(
                        'INV-0444', __FILE__ . ':' . __LINE__,
                        $msg, ['VALUES_DOCID' => $values['DOCID']],
                        '', [],
                        $corr, ['VALUES_DOCID' => $values['DOCID']]
                    );
                    $ok = false;
                }
            }
        }

        // Validation when threeway match is enabled for a child TD
        if ($values['CONVTYPE'] == 'Close Original and Create Back Order') {
            $recallDocuments = QueryResult(
                array(
                    "select r.docid from docparmst r, docrecalls dc where dc.cny# = :1 and dc.cny# = r.cny# 
                                and dc.recdocparkey = :2 and r.record# = dc.DOCPARKEY and r.latestversionkey is null",
                    GetMyCompany(), $values['RECORDNO']
                )
            );
            foreach ( $recallDocuments as $recallDocpar ) {
                $threeWayMatchEnabled = ThreeWayMatchHandler::checkIfThreeWayMatchEnabled($recallDocpar['DOCID'],
                                                                                          $threeWayMatchGridPref, $threeWayMatchGLAccount);
                if($threeWayMatchEnabled){
                    $msg = $recallDocpar['DOCID']. " you cannot set the partial conversion handling to create back orders because this transaction definition can be converted to a transaction that is enabled for match tolerance validation. Set the partial conversion handling to either leave the transaction open or close it.";
                    $corr = "Specify a partial conversion handling option that doesn’t create backorders.";
                    $gErr->addIAError(
                        'INV-0445', __FILE__ . ':' . __LINE__,
                        $msg, ['RECALL_DOCPAR_DOCID' => $recallDocpar['DOCID']],
                        $corr, []
                    );
                    return false;
                }
            }

        }


        return $ok;
    }
}


/**
 * Class PrimaryDocumentValidator
 *
 * Validates that the primary document checkbox cannot be enabled for change orders
 */
class PrimaryDocumentValidator extends AbstractValidator
{
    /**
     *
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
       global $gErr;
       $ok = true;

        if (CRESetupManager::isPrimaryDocEnabled()) {

            if ( $values['ENABLEDOCCHANGE'] == 'Change Order' && $values['PRIMARYDOC'] == 'true') {
                $gErr->addIAError('INV-0097', __FILE__ . ':' . __LINE__,
                                "Primary document feature is not supported for change order documents.", []
                );
                $ok = false;
            }

            if ( $ok && $values['ALLOW_ALLOCATIONS'] == 'true' && $values['PRIMARYDOC'] == 'true') {
                $gErr->addIAError('INV-0098', __FILE__ . ':' . __LINE__,
                                "Primary document feature is not supported along with allocations.", []
                );
                $ok = false;
            }

            $gManagerFactory = Globals::$g->gManagerFactory;
            $poDocumentMgr = $gManagerFactory->getManager('podocumentparams');

            $oldvalues = $poDocumentMgr->get($values['RECORDNO']);

            if ($ok && $values['PRIMARYDOC'] != $oldvalues['PRIMARYDOC'] && $values['PRIMARYDOC'] == "true") {
                $values = GetAllPreferenceForProperty('9.PO', 'AUTO_PPV_POSTING');
                $autoppvpref = ($values['']['AUTO_PPV_POSTING'] == 'true' || $values['']['AUTO_PPV_POSTING'] == 'T') ? true : false;
                if ($autoppvpref) {
                    $gErr->addIAError('INV-0099', __FILE__ . ':' . __LINE__,
                                    "You can use either primary document workflow or automatic price variance posting, but not both at the same time.", []
                    );
                    $ok = false;
                }
            }

        } else if (isset($values['PRIMARYDOC']) && $values['PRIMARYDOC'] == 'true') {

            $gErr->addIAError('INV-0100', __FILE__ . ':' . __LINE__,
                            "Primary document feature is not supported for non-Construction companies.", []);

            return false;
        }

        return $ok;
    }
}


/**
 * Class PrimaryDocumentNotSupportedValidator
 *
 * Validates that the primary document checkbox cannot be enabled for SO and INV docs
 */
class PrimaryDocumentNotSupportedValidator extends AbstractValidator
{
    /**
     *
     *
     * @param array $values
     *
     * @return bool
     */
    function validate($values)
    {
        global $gErr;
        $ok = true;

        if ( isset($values['PRIMARYDOC']) ) {

            if ( CRESetupManager::isPrimaryDocEnabled() ) {
                $gErr->addIAError('INV-0101', __FILE__ . ':' . __LINE__,
                                "Primary document feature is not supported for Order Entry and Inventory.", []);

            } else {
                $gErr->addIAError('INV-0102', __FILE__ . ':' . __LINE__,
                                "Only Construction-enabled companies can enable Primary document workflow.", []);
            }

            $ok = false;
        }

        return $ok;
    }
}

