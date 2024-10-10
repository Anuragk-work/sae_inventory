<?
require_once "uperm.inc";        // The complex control...
require_once 'scm_util.inc';

require_once 'Pt_RelationshipManager.cls';
require_once 'Pt_RelationshipDefManager.cls';
require_once 'Util_StandardObjectRegistry.cls';
require_once 'Pt_Cache.cls';
import('DocumentParamsValidator');

/**
 * Class DocumentParamsManager
 *
 * Parent class for all transaction definition manager classes
 */
class DocumentParamsManager extends EntityManager
{
    // Cached preferences
    /**
     * @var array $_latestRaw
     */
    var $_latestRaw;
    /**
     * @var array $_latestDocpar
     */
    var $_latestDocpar;
    /**
     * @var array $_latestBaseObject
     */
    var $_latestBaseObject;
    /**
     * @var bool $_ismcpEnabled
     */
    var $_ismcpEnabled;

    /**
     * @var string $_mod
     */
    var $_mod;
    /**
     * @var string $_modID
     */
    var $_modID;
    /**
     * @var string $spi
     */
    var $spi;

    /**
     * Trait for Change Order validations
     */
    use DocumentParamsChangeOrderTrait;


    /**
     * Trait for AIA billing
     */
    use DocumentParamsAIABillingTrait;

    /**
     * @var bool $overrideOwnershipForDelete
     */
    protected $overrideOwnershipForDelete = false;

    /**
     * @var bool $automaticallyGenerated
     */
    private $automaticallyGenerated = false;

    /**
     * @var bool $includeOwnObjects
     */
    private $includeOwnObjects = false;

    /**
     * @var bool $initiateSubscribeToInventory
     */
    private $initiateSubscribeToInventory = false;

    /**
     * @var array $systemGeneratedTDs
     */
    public static $systemGeneratedTDs = array(
        ICTransferManager::INDOCTYPE,
        ICTransferManager::OUTDOCTYPE,
        ICTransferManager::INTRANSITDOCTYPE,
        StkitDocumentManager::BUILDKIT,
        StkitDocumentManager::DISKIT,
        InvDocumentManager::LANDEDCOSTDOCTYPE,
        InvDocumentManager::LANDEDCOSTESTDOCTYPE,
        InvDocumentManager::LANDEDCOSTESTREVDOCTYPE,
        ICCycleCountManager::ADJDECREASEDOCTYPE,
        ICCycleCountManager::ADJINCREASEDOCTYPE,
        ICCycleCountManager::ADJDAMAGEDDOCTYPE,
        SODocumentManager::FULFILLMENTORDERDOCTYPE,
        SODocumentManager::FULFILLMENTSHIPPERDOCTYPE,
        SODocumentManager::FULFILLMENTINVOICEDOCTYPE,
        PODocumentManager::SUPPLIESREQUESTDOCTYPE,
        PODocumentManager::SUPPLIESISSUEDOCTYPE,
        PODocumentManager::SUPPLIESRETURNDOCTYPE,
        PODocumentManager::DEFAULTPOAUTOMATIONDOCTYPE
    );

  /**
   *
   */
   const objectEntityMap = [
        'INVDOCUMENTENTRY' => 'invdocument',
        'INVDOCUMENT' => 'invdocument',
        'INVRECURDOCUMENT' => 'invdocument',
        'PODOCUMENTENTRY' => 'podocument',
        'PODOCUMENT' => 'podocument',
        'PORECURDOCUMENT' => 'podocument',
        'GENINVOICEPREBILLLINE' => 'sodocument',
        'GENINVOICEPREVIEWLINE' => 'sodocument',
        'SODOCUMENTENTRY' => 'sodocument',
        'SODOCUMENTSUBTOTALS' => 'sodocument',
        'SODOCUMENT' => 'sodocument',
        'SORECURDOCUMENT' => 'sodocument'
    ];

    /**
     * @param array $params
     */
    public function __construct($params = array())
    {

        parent::__construct($params);
        $this->_mod = $params['_mod'];
        $this->_modID = $params['_modID'];
        $this->spi = $params['docclass'];
        $this->_ismcpEnabled = IsMCPEnabled($this->_mod);

    }

    /**
     * Public setter.
     *
     * @param bool $automaticallyGenerated
     */
    public function setAutomaticallyGenerated($automaticallyGenerated)
    {
        $this->automaticallyGenerated = $automaticallyGenerated;
    }

    /**
     * Public getter.
     *
     * @return bool
     */
    public function isAutomaticallyGenerated()
    {
        return $this->automaticallyGenerated;
    }

    /**
     * Public setter.
     *
     * @param bool $includeOwnObjects
     */
    public function setIncludeOwnObjects($includeOwnObjects)
    {
        $this->includeOwnObjects = $includeOwnObjects;
    }

    /**
     * Public getter.
     *
     * @return bool
     */
    public function isIncludeOwnObjects()
    {
        return $this->includeOwnObjects;
    }

    /**
     * Public setter
     *
     * @param bool $initiateSubscribeToInventory
     */
    public function setInitiateSubscribeToInventory($initiateSubscribeToInventory)
    {
        $this->initiateSubscribeToInventory = $initiateSubscribeToInventory;
    }

    /**
     * Public getter.
     *
     * @return bool
     */
    public function isInitiateSubscribeToInventory()
    {
        return $this->initiateSubscribeToInventory;
    }

    /**
     * Implementation of delete functionality on transaction definition.
     *
     * @param int|string $ID
     * @param bool $systemDelete
     *
     * @return bool
     */
    public function Delete($ID, $systemDelete = false)
    {
        // Only set during system delete (delete from the transaction definition list)
        $origIdToDelete = null;

        if (!$systemDelete) {
            global $gErr;

            if (!$this->isTrxdefExists($ID)) {
                $gErr->addIAError(
                    'INV-0038', __FILE__ . ":" . __LINE__,
                    "Transaction Definitions does not exist.", []
                );
                return false;
            }

            if ($this->IsSystemDocPar($ID)) {
                $gErr->addIAError('INV-0039', __FILE__ . ":" . __LINE__, "System Definitions can not be deleted.", []);
                return false;
            }

            // Need to know this transaction definition's original id to figure out if we're
            // going to delete the platform bits below
            $template = $this->get($ID);
            if (!$template) {
                return false;
            }
            if ($template['LATESTVERSIONKEY'] == '') {
                $origIdToDelete = self::getInitialVersionId($template['DOCID']);
                if ($origIdToDelete === false) {
                    return false;
                }
            }

            $validator = DocumentParamsValidatorFactory::create($this, Operation::DELETE);
            if (!$validator->validate($template)) {
                return false;
            }
        }

        // Bug 34653
        $source = 'DocumentParamsManager::Delete';
        XACT_BEGIN($source);
        try {

            $ok = true;

            //get all prior versions of this TD
            $sql = "SELECT RECORD# FROM DOCPARMST WHERE latestversionkey = :1 AND CNY# = :2  order by record# desc";
            $docArray = QueryResult(array($sql, $ID, GetMyCompany()));

            // If we're deleting the latest version, delete all earlier versions.
            if (!empty($docArray)) {
                foreach($docArray as $docparKey){
                    $ok = $ok && parent::Delete($docparKey['RECORD#']);
                }
            }

            if (!$ok) {
                //check the DOCPAR mutating trigger error and add details - ticket 58041
                if (strpos(Globals::$g->gErr->errors[0]['CDESCRIPTION'], 'DOCPAR is mutating') !== false) {
                    /** @noinspection PhpUndefinedVariableInspection */
                    $msg = $template['DOCID'] . ' cannot be deleted because other records are referencing it.' .
                        ' Delete all records that reference the ' . $template['DOCID'] . ' Transaction Definition' .
                        ' first, and then delete the transaction definition';
                    Globals::$g->gErr->addIAError('INV-0385', __FILE__ . ':' . __LINE__, $msg, ['TEMPLATE_DOCID' => $template['DOCID']]);
                    epp("$source: Error: $msg");
                }
            }

            $ok = $ok && parent::Delete($ID);

            // Delete the platform bits if we're deleting the latest version
            // (and the root version too)
            if ($ok && $origIdToDelete !== null && !util_isPlatformDisabled()) {

                // After tx abort need to undo any changes to the platform cache
                XACT_REGISTER_POSTROLLBACK_EVENT($source, "Pt_Cache::refresh");

                $objDefId = Util_StandardObjectRegistry::getObjectDefId('sodocument', $ID);
                if ($objDefId > 0) {
                    $rels = Pt_RelationshipDefManager::getByObjectDef($objDefId);
                    if ($rels) {
                        Pt_RelationshipManagerChoose::deleteObjDefId($objDefId);
                        Pt_RelationshipDefManager::deleteObjDefId($objDefId);
                    }
                    Pt_Cache::removeObjDef($objDefId);
                }

                $objDefId2 = Util_StandardObjectRegistry::getObjectDefId('sodocumententry', $ID);
                if ($objDefId2 > 0) {
                    $rels2 = Pt_RelationshipDefManager::getByObjectDef($objDefId2);
                    if ($rels2) {
                        Pt_RelationshipManagerChoose::deleteObjDefId($objDefId2);
                        Pt_RelationshipDefManager::deleteObjDefId($objDefId2);
                    }
                    Pt_Cache::removeObjDef($objDefId2);
                }

            }

            // delete the ordinal number from the preferences table.
            // The last parameter set to false instructs to remove all the
            // records for root and corresponding entities.
            $ok = $ok && $this->_MM->DeletePreference('TD_RECORD#' . $ID, $this->_modID, false);

            if ($ok && !empty($template['DOCID']) && empty($template['LATESTVERSIONKEY'])) {
                // Delete DOCTYPES.<docid> preference if TD is completely deleted (except version cleanup)
                $ok = $ok && $this->_deleteDocParPrefStatus($template['DOCID']);
            }

            $ok = $ok && XACT_COMMIT($source);
            if ($ok) {
                return true;
            }

        } catch (Exception $ex) {
            Globals::$g->gErr->addIAError('INV-1414', $ex->getFile() . '.' . $ex->getLine(), $ex->getMessage(), []);
        }

        XACT_ABORT($source);
        return false;

    }


    /**
     * Get minimum RECORD# (used as part of object definition ID)
     *
     * @param string $docType
     *
     * @return string|false
     */
    public static function getInitialVersionId($docType)
    {
        /* @var string[][] $cache */
        static $cache = [];

        $cny = GetMyCompany();

        if (isset($cache[$cny][$docType])) {
            return $cache[$cny][$docType];
        }

        // use docparmst to query the full table rather than whatever mega view we happen
        // to be in.  This is the only way to ensure that we always get the real minimum
        // record#
        $sql = "SELECT MIN(RECORD#) MIN FROM DOCPARMST WHERE DOCID = :1 AND CNY# = :2";
        $res = Globals::$g->gQueryMgr->DoCustomQuery(
            ['QUERY' => $sql, 'ARGTYPES' => ['integer', 'integer']],
            [$docType, $cny],
            true
        );

        if (!$res) {
            // Error or no documents defined.
            return false;
        }

        $ret = $cache[$cny][$docType] = $res[0]['MIN'];
        return $ret;
    }

    /**
     * fetches a docType's name from it's record#
     *
     * @param int $recordNo the record# of the docType (docid)
     *
     * @return string|false   the docType's name (id) or false if not found
     */
    public static function getDocTypeFromRecordNo($recordNo)
    {
        static $docTypeCache = [];

        $cny = GetMyCompany();

        if (isset($docTypeCache[$cny][$recordNo])) {
            return $docTypeCache[$cny][$recordNo];
        }

        $mgr = Globals::$g->gManagerFactory->getManager('documentparams');
        $res = $mgr->GetList([
            'selects' => ['DOCID'],
            'filters' => [[['RECORDNO', '=', $recordNo]]],
            'nodbfilters' => true,  // We really don't want the lastversionkey = null predicate here.
        ]);

        if (isset($res[0]['DOCID'])) {
            return $docTypeCache[$cny][$recordNo] = $res[0]['DOCID'];
        }

        return false;
    }

    /**
     * Cleanup the template version in case the docpar has no transaction under it
     *
     * @param array $docpar array of the docpar values of the document.
     * @return bool returns if the method execution was success or not.
     */
    public function CleanupTemplateVersion($docpar)
    {

        $cny = GetMyCompany();
        $recNo = $docpar['RECORDNO'];
        $docType = $docpar['DOCID'];

        // If no other transaction is referring to the old definition and its not latest, get rid of it. (auto clean)
        // Don't get rid of the first version until the latest version is also deleted for Platform's sake.
        $origId = self::getInitialVersionId($docType);
        if ($origId === false) {
            LogToFile(
                "Error: CleanupTemplateVersion failed to get original id of document.  cny#: "
                . GetMyCompany() . " doctype: " . $docType . "\n"
            );
        } else if ($docpar['LATESTVERSIONKEY'] != '' && $recNo != $origId) {

            $ret = $this->DoQuery('QRY_DOCUMENTPARAMS_TRANSACTIONS_EXIST', array($recNo, $cny, $recNo, $cny, $recNo, $cny, $recNo, $cny, $cny, $recNo, $recNo));

            if ($ret[0]['CNT'] == 0) {
                // This is added for one special case:-
                // For deleting the last transction which is referring to a Root Level TD
                if (IsMultiEntityCompany() && GetContextLocation() != '') {
                    $this->overrideOwnershipForDelete = true;
                }
                return $this->Delete($recNo, true);
            }
        }
        return true;
    }

    /**
     * Implementation of the method for all transaction definition managers.
     *
     * @param array $result
     *
     * @return bool
     */
    public function _ProcessResultForOwnership(&$result)
    {
        $ok = parent::_ProcessResultForOwnership($result);

        //  Ownership of the TD will be made true for the entity for one special case.
        //  This should be set to 'true' in only one case, The case is:-
        //  When an entity level transction is deleted from the entity level, but the TD it refers is at root level.
        //  and this is the last transction referring to that TD.
        if ($this->_entityownership === false && $this->overrideOwnershipForDelete === true) {
            $this->_entityownership = true;
        }

        return $ok;
    }

    /**
     * Returns the transaction definition structure for the given id
     * ($docparkey)
     *
     * @param string $docparkey
     * @param string[]|null $fields
     *
     * @return array|false
     */
    public function get($docparkey, $fields = null)
    {
        return $this->getVerbose($docparkey, true);
    }

    /**
     * Returns the transaction definition structure for the given id
     * ($docparkey)
     *
     * @param string $docparkey
     * @param bool $verbose
     *
     * @return array|false
     */
    public function getVerbose($docparkey, $verbose = true)
    {
        if (!isset($docparkey) || $docparkey === '') {
            return false;
        }

        $docpar = parent::get($docparkey);
        if (!$docpar) {
            // Cannot find the TD with the given ID. Try to read the
            // TD by its name
            $recordno = $this->GetRecordNo('DOCID', $docparkey, false);
            if (isset($recordno)) {
                $docpar = parent::get($recordno);
            }
        }
        if (!$docpar) {
            Globals::$g->gErr->addIAError(
                'INV-0386', __FILE__ . ':' . __LINE__,
                "Cannot find the transaction definition with the given key $docparkey.",
                ['DOCPARKEY' => $docparkey]
            );
            return false;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;

        if ($verbose) {

            // flesh out the dept and loc fields
            if ($docpar['DEFAULTDEPT']) {
                $deptMgr = $gManagerFactory->getManager('department');
                $deptobj = $deptMgr->GetDeptWithPickSingle($docpar['DEFAULTDEPT']);
                $docpar['DEFAULTDEPT'] = $deptobj['PICK'];
            }
            if ($docpar['DEFAULTLOCATION']) {
                $locationMgr = $gManagerFactory->getManager('location');
                $locobj = $locationMgr->GetLocationWithPickSingle($docpar['DEFAULTLOCATION']);
                $docpar['DEFAULTLOCATION'] = $locobj['PICK'];
            }

            if ($docpar['XSLTEMPLATE']) {
                $XslformatMgr = $gManagerFactory->getManager('xslformat');
                $formatdata = $XslformatMgr->DoQuery('QRY_XSLFORMAT_SELECT_RAW_FROM_RECORDNO', array($docpar['XSLTEMPLATE'], $this->_cny));
                $docpar['XSLTEMPLATE'] = $formatdata[0]['DESCRIPTION'];
            }

        }

        if ($this->_ismcpEnabled) {
            if ($docpar['EXCH_RATE_TYPE_ID'] == '-1') {
                $exchTypeMgr = $gManagerFactory->getManager('exchangeratetypes');
                $docpar['EXCHRATETYPES']['NAME'] = $exchTypeMgr->GetExchangeRateTypeName($docpar['EXCH_RATE_TYPE_ID']);
            }
        }

        return $docpar;
    }

    /**
     * Returns the creation rule for the transaction definition with the
     * given recordNo.
     *
     * @param int $recordNo
     *
     * @return mixed
     * @throws Exception
     */
    public function getCreationRuleForRecordNo($recordNo)
    {
        $querySpec = [
            'selects' => ['RECORDNO', 'DOCID', 'TD_CREATION_RULE'],
            'filters' => [[['RECORDNO', '=', $recordNo]]],
        ];
        $record = $this->GetList($querySpec);
        if (!is_array($record) || count($record) < 1) {
            throw new Exception("Cannot find a TD with the record number of $recordNo.");
        }
        $creationRuleInfo = $this->getCreationRuleInfo($record[0]);
        return $creationRuleInfo['CREATION_RULE'];
    }

    /**
     * Returns the creation rule for the transaction definition with the
     * given docid.
     *
     * @param string $docid
     *
     * @return mixed
     * @throws Exception
     */
    public function getCreationRuleForDocid($docid)
    {
        $querySpec = [
            'selects' => ['RECORDNO', 'DOCID', 'TD_CREATION_RULE'],
            'filters' => [[['DOCID', '=', $docid]]],
        ];
        $record = $this->GetList($querySpec);
        if (!is_array($record) || count($record) < 1) {
            throw new Exception("Cannot find a TD with the document id of $docid.");
        }
        $creationRuleInfo = $this->getCreationRuleInfo($record[0]);
        return $creationRuleInfo['CREATION_RULE'];
    }

    /**
     * Returns creation rule for the given td record
     * @param string[] $tdRecord
     *
     * @return mixed
     */
    public function getCreationRule($tdRecord)
    {
        $creationRuleInfo = $this->getCreationRuleInfo($tdRecord);
        return $creationRuleInfo['CREATION_RULE'];
    }

    /**
     * Returns the creation rule for the array representing the transaction
     * definition. Depends upon the caller the input parameter contains
     * either a complete TD or TD proxy with RECORDNO, DOCID, and the
     * TD_CREATION_RULE fields.
     *
     * @param string[] $record
     *
     * @return array
     * @throws Exception
     */
    private function getCreationRuleInfo($record)
    {
        $creationRule = 'T';
        $copyProperties = false;

        $locationId = GetContextLocation();
        if (isArrayValueProvided($record, 'TD_CREATION_RULE')) {
            $tdCreationRule = DBTokensHandler::getInstance()->getInternalKey(I18N::getSingleToken($record['TD_CREATION_RULE']));
            // Creation rule is provided for TD.
            if (IsMultiEntityCompany() && $locationId) {
                // Logged in to entity
                if (!strcontains($tdCreationRule, CreationRuleConstants::ENTITY)) {
                    // If creation rule is not set to Entity in any way
                    // mark it false
                    $creationRule = 'F';
                } else {
                    if (isset($this->_mod)) {
                        /* @var DocumentParEntityPropManager $entityPropertyManager */
                        $entityPropertyManager =
                            Globals::$g->gManagerFactory->getManager($this->_mod . 'documentparentityprop');
                        $recordCount =
                            $entityPropertyManager->getEntityCountWithProperties($record['RECORDNO']);
                        if ($recordCount == 0) {
                            // By default the creation rule for entity is T if no
                            // entity has any specific property for the given TD
                            $creationRule = 'T';
                        } else {
                            $entityProperties = $entityPropertyManager->getEntityProperties($record['RECORDNO'], $locationId);
                            if (isset($entityProperties) && is_array($entityProperties)) {
                                // Entity specific properties are provided.
                                $copyProperties = true;
                                if (isArrayValueProvided($entityProperties, 'ENTITY_CREATION_RULE')) {
                                    $creationRule =
                                        'true' === $entityProperties['ENTITY_CREATION_RULE'] ? 'T' : 'F';
                                }
                            } else {
                                // No entity specific properties are found. Set it to 'F'
                                $creationRule = 'F';
                            }
                        }
                    } else {
                        LogToFile("ERROR in getCreationRule: Not reported to customer. TD -> " . $record['DOCID']);
                        logStackTraceBrief();
                    }
                }
            } else {
                // Logged in to the root
                $creationRule = strcontains($tdCreationRule, CreationRuleConstants::TOP_LEVEL) ? 'T' : 'F';
            }
        } else {
            // Legacy TD; no creation rule is provided. Set it to 'T'
            $creationRule = 'T';
        }

        return ['CREATION_RULE' => $creationRule, 'COPY_PROPERTIES' => $copyProperties];
    }

    /**
     * If logged in to the entity adjusts some TD fields with the predefined
     * once for the given entity.
     *
     * @param array $values
     */
    private function adjustEntitySpecificProperties(&$values)
    {
        global $gManagerFactory;
        $locationId = GetContextLocation();

        if (isset($values) && isset($values['DOCID'])) {
            // Valid values for TD are provided. Move on with the Entity Settings adjustment
            $creationRuleInfo = $this->getCreationRuleInfo($values);

            $values['CREATION_RULE'] = $creationRuleInfo['CREATION_RULE'];
            if ($creationRuleInfo['COPY_PROPERTIES']) {
                if (isset($this->_mod)) {
                    /* @var DocumentParEntityPropManager $entityPropertyManager */
                    $entityPropertyManager = $gManagerFactory->getManager($this->_mod . 'documentparentityprop');
                    $entityProperties = $entityPropertyManager->getEntityProperties($values['RECORDNO'], $locationId);
                    $properties = [
                        'ENABLE_SEQNUM',
                        'SEQUENCE',
                        'PRESERVE_SEQNUM',
                        'INHERIT_SOURCE_DOCNO',
                        'XSLTEMPLATE',
                        'SUBTOTALTEMPLATE',
                        'SHOWEXPANDEDTOTALS',
                        'ENABLEOVERRIDETAX',
                        'LINELEVELSIMPLETAX',
                    ];
                    foreach ($properties as $property) {
                        if (isArrayValueProvided($entityProperties, $property)) {
                            $values[$property] = $entityProperties[$property];
                        }
                    }
                }
            }
        }
    }


    /**
     * Populate the docparsubtotal rows from the subtotaltemplate/s specfied in the TD general tab
     * If there are overrides specified in the Entity Properties Table , read those and save them indexed by entity
     * We are copying these values into TD subtotal on create/edit to avoid versioning of the subtotal templates
     *
     * @param array $values
     *
     * @return bool true if we can find the subtotaltemplate values , false otherwise
     */
    private function populateSubtotalsfromTemplate(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gError = Globals::$g->gErr;

        if ($this instanceof PODocumentParamsManager) {
            $subtotaltemplateMgr = $gManagerFactory->getManager('posubtotaltemplate');
        } else if ($this instanceof SODocumentParamsManager) {
            $subtotaltemplateMgr = $gManagerFactory->getManager('sosubtotaltemplate');
        } else {
            // we only support PO and SO modules for subtotal templates
            return true;
        }

        // If a subtotal template is provided, find the record and populate the subtotal
        $values['SUBTOTALTEMPLATEKEY'] = null;
        if (isset($values['SUBTOTALTEMPLATE']) && $values['SUBTOTALTEMPLATE'] != '') {

            // read top level entity subtotalDetail
            $template = $subtotaltemplateMgr->get($values['SUBTOTALTEMPLATE']);

            if ($template && isset($template['RECORDNO'])) {
                $values['SUBTOTALTEMPLATEKEY'] = $template['RECORDNO'];
            } else {
                $gError->addIAError('INV-0387', __FILE__ . ':' . __LINE__,
                    "Incorrect value for the Subtotal Template.");
                return false;
            }

            // copy so/po subtotaltemplatedetail to so/po docparsubtotal lines of docpar , one set per entity
            // TODO Its important to store all the rows for a specific entity sequentially inthe docparsubtotal for the parsing to work later

            // COPY FROM  --> so/posubtotaltemplatedetail entity
            /*
             *  'RECORDNO', 'TEMPLATEKEY',
                    'DISC_CHARGE', 'LINENO', 'DESCRIPTION', 'AMT_PERC', 'VALUE', 'APPORTIONED', 'GLACCOUNT', 'GLOFFSETACCOUNT',
                    'DEBIT_CREDIT', 'BASELINE', 'ISTAX', 'GLACCTID', 'GLOFFSETACCTID',
                    'LOCATIONID','LOCATIONNAME', 'DEPARTMENTID', 'DEPARTMENTNAME', 'ISAVATAX'
             */
            // COPY TO --> so/podocumentparsubtotal entity
            /*
             * 'RECORDNO', 'DOCPARNO',
             *      'DISC_CHARGE', 'LINENO', 'DESCRIPTION', 'AMT_PERC','VALUE','APPORTIONED','GLACCOUNT', 'GLOFFSETACCOUNT',
             *      'DEBIT_CREDIT', 'BASELINE', 'ISTAX', 'GLACCTID','GLOFFSETACCTID',
                    'LOCATIONID', 'LOCATIONNAME', 'DEPARTMENTID', 'DEPARTMENTNAME', 'DEPARTMENT', 'LOCATION', 'ISAVATAX'
             */

            // get the DOCPARNO from the object to copy to each subtotal lines
            $docparno = $values['RECORDNO'];

            // 1. copy values for the root template

            // clear all existing subtotalDetail rows
            $values['DOCPAR_SUBTOTAL'] = array();

            $count = 0;
            foreach ($template['TEMPLATE_DETAILS'] as $subtotalDetail) {
                // remove values that doesn't matter to subtotal
                unset($subtotalDetail['RECORDNO']);
                unset($subtotalDetail['TEMPLATEKEY']);

                // copy the subtotalDetail from template to docpar subtotalDetail
                // TODO: Its' important that the so/posubtotaltemplatedetail matches with each other and with so/podocumentparsubtotals !
                $values['DOCPAR_SUBTOTAL'][$count] = $subtotalDetail;

                // add the docparno file
                $values['DOCPAR_SUBTOTAL'][$count]['DOCPARNO'] = $docparno;
                // this is for the top /root level
                $values['DOCPAR_SUBTOTAL'][$count]['ENTITY_NAME'] = null;
                $values['DOCPAR_SUBTOTAL'][$count]['ENTITYKEY'] = null;

                // had to fix GL field names in subtotaltemplate to match docparsubtotal
                $values['DOCPAR_SUBTOTAL'][$count]['GLACCOUNT'] = $subtotalDetail['GLACCTID'];
                $values['DOCPAR_SUBTOTAL'][$count]['GLOFFSETACCOUNT'] = $subtotalDetail['GLOFFSETACCTID'];

                $count++;

            }

            // copy all entity override templates and build the full docparsubtotal
            // this is being everytime we save since the get only returns data for current location

            foreach (($values['DOCPAR_ENTITY_PROPS']) ?? [] as $record) {
                $entityName = explode('--', $record['ENTITY_NAME']);
                $entityName = array_shift($entityName);
                $entitykey = $record['ENTITYNO'];
                // for the first time use, get the entity key since docparentityprops manager hasn't been called yet to resolve entity name
                if (!isset($entitykey) || $entitykey == '') {
                    $locManager = $gManagerFactory->getManager('location');
                    $recordno = $locManager->GetRecordNoFromVid($entityName);
                    if (isset($recordno)) {
                        $entitykey = $recordno;
                    } else {
                        $gError->addIAError(
                            'INV-0388', __FILE__ . ':' . __LINE__,
                            "Incorrect value for the Entity Name: " . $record['ENTITY_NAME'],
                            ['RECORD_ENTITY_NAME' => $record['ENTITY_NAME']]
                        );
                        return false;
                    }
                }

                $templateName = $record['SUBTOTALTEMPLATE'];

                if (isset($templateName) && $templateName != '') {
                    $template = $subtotaltemplateMgr->get($templateName);
                    if (!$template) {
                        $gError->addIAError(
                            'INV-0389', __FILE__ . ':' . __LINE__,
                            "In entity settings, we could not find the subtotal template $templateName specified.",
                            ['TEMPLATE_NAME' => $templateName]
                        );
                        return false;
                    }
                    foreach ($template['TEMPLATE_DETAILS'] as $subtotalDetail) {
                        // remove values that doesn't matter to subtotal
                        unset($subtotalDetail['RECORDNO']);
                        unset($subtotalDetail['TEMPLATEKEY']);

                        // copy the subtotalDetail from template to docpar subtotalDetail
                        $values['DOCPAR_SUBTOTAL'][$count] = $subtotalDetail;

                        // add the docparno file
                        $values['DOCPAR_SUBTOTAL'][$count]['DOCPARNO'] = $docparno;
                        // this is for the top /root level
                        $values['DOCPAR_SUBTOTAL'][$count]['ENTITY_NAME'] = $entityName;
                        $values['DOCPAR_SUBTOTAL'][$count]['ENTITYKEY'] = $entitykey;

                        // had to fix GL field names in subtotaltemplate to match docparsubtotal
                        $values['DOCPAR_SUBTOTAL'][$count]['GLACCOUNT'] = $subtotalDetail['GLACCTID'];
                        $values['DOCPAR_SUBTOTAL'][$count]['GLOFFSETACCOUNT'] = $subtotalDetail['GLOFFSETACCTID'];

                        $count++;
                    }

                }
            }
        } else {
            // if the root subtotal template (which is the default template) was removed, we cannot allow users to use
            // subtotal templates for any entities this TD since we don;t have a default value when overriding
            if (isset($values['DOCPAR_ENTITY_PROPS']) && is_array($values['DOCPAR_ENTITY_PROPS'])) {
                foreach ($values['DOCPAR_ENTITY_PROPS'] as $index => $props) {
                    $entityTemplate = $values['DOCPAR_ENTITY_PROPS'][$index]['SUBTOTALTEMPLATE'];
                    if (isset($entityTemplate) && $entityTemplate != '') {
                        $gError->addIAError('INV-0390', __FILE__ . ':' . __LINE__,
                            "You cannot add Subtotal template in Entity settings, if there is no
                                        Subtotal template selected in the General section for Top level.");

                        return false;
                    }
                }
            }

        }

        return true;

    }

    /**
     * Adjusts user provided data for subtotals:
     * 1. Removes subtotals entirely if the Show Subtotals check box
     *    is not selected.
     * 2. Adds the line number field for each subtotal record.
     *
     * @param array $values
     */
    private function prepareSubtotals(&$values)
    {
        $this->handleSubtotalLocationDepartment($values);

        if (!isset($values['SHOW_TOTALS']) || 'true' !== $values['SHOW_TOTALS']) {
            // remove subtotals if the Show Subtotals check box is not selected
            unset($values['DOCPAR_SUBTOTAL']);
            unset($values['SHOWEXPANDEDTOTALS']);
        } else {
            $count = 0;
            foreach (($values['DOCPAR_SUBTOTAL']) ?? [] as $key => $value) {
                // round the Value field to 10 decimal places
                if (is_numeric($values['DOCPAR_SUBTOTAL'][$key]['VALUE'])) {
                    $values['DOCPAR_SUBTOTAL'][$key]['VALUE'] =
                        round($values['DOCPAR_SUBTOTAL'][$key]['VALUE'], 10);
                }
                if ($values['LINELEVELSIMPLETAX'] == 'true') {
                    $values['DOCPAR_SUBTOTAL'][$key]['BASELINE'] = 0;
                }

                // add the line number
                $values['DOCPAR_SUBTOTAL'][$key]['LINENO'] = $count++;
            }
        }
    }

    /**
     * @param array $values
     */
    private function handleSubtotalLocationDepartment(&$values)
    {
        if (IsMultiEntityCompany() && GetContextLocation() == '') {
            $docparsubtotalsMgr = Globals::$g->gManagerFactory->getManager($this->_mod . 'documentparsubtotal');
            $unsetLocDept = !($docparsubtotalsMgr->_overrideLocDeptAtTopLevel
                && $docparsubtotalsMgr->_overrideDimensionsFromSubtotals);

            // For any multi-entity company in the top level set
            // the values of the location and department to blank
            if (isset($values['DOCPAR_SUBTOTAL']) && is_array($values['DOCPAR_SUBTOTAL'])) {
                foreach ($values['DOCPAR_SUBTOTAL'] as & $subtotal) {
                    $subtotal['LOCATION'] = $unsetLocDept ? '' : $subtotal['LOCATION'];
                    $subtotal['DEPARTMENT'] = $unsetLocDept ? '' : $subtotal['DEPARTMENT'];
                }
            }
        }
    }

    /**
     * Drops the account mapping data if the user has not selected to have them
     *
     * @param array $values
     */
    private function preparePostingConfiguration(&$values)
    {
        if ('so' === $this->_mod || 'po' === $this->_mod) {
            // Drop transaction posting data if the user has selected Don't post
            if ('N' === $values['UPDATES_GL']) {
                unset($values['DOCPAR_PRGL']);
            }

            switch ($this->_mod) {
                case 'po':
                    // Drop the additional GL account mapping if the user
                    // hasn't selected POSTTOGL
                    if (!isArrayValueProvided($values, 'POSTTOGL') || 'true' !== $values['POSTTOGL']) {
                        unset($values['DOCPAR_INVGL']);
                    }
                    break;

                case 'so':
                    if (!isArrayValueProvided($values, 'POSTTOGL') || 'true' !== $values['POSTTOGL']) {
                        unset($values['DOCPAR_ADDGL']);
                    }
                    break;
            }
        }
    }

    /**
     * Sets the values for enabling numbering scheme and preserving
     * sequence number depending of value provided / not provided
     * for the numbering sequence.
     *
     * @param array $values
     */
    private function prepareNumberingScheme(&$values)
    {
        $isProvided = isset($values['SEQUENCE']) && '' !== $values['SEQUENCE'];
        if ($isProvided) {
            $values['ENABLE_SEQNUM'] = 'true';
        } else {
            $values['ENABLE_SEQNUM'] = 'false';
            $values['PRESERVE_SEQNUM'] = 'false';
        }
    }

    /**
     * Specifies hidden inventory fields based on data on other fields:
     * - Affects Cost -> true if the ONHAND inventory total is specified
     *   as follows:
     *   * Maintain -> Quantity / Quantity & Value
     *   * Add / Substract -> Add
     * - Affects Inventory -> value is given based on the selection of field Maintain
     *   for the ONHAND inventory total
     *   * Quantity -> Quantity
     *   * Value -> Value
     *   * Quantity & Value -> Quantity and Value
     * - Increase / Decrease Inventory -> value is given based on the selection
     *   of the field Add / Subtract for the ONHAND inventory total
     *   * Subtract -> Decrease
     *   * Add -> Increase
     *
     * @param array $values
     */
    private function setHiddenInventoryFields(&$values)
    {

        $gManagerFactory = Globals::$g->gManagerFactory;
        $modMgr = $gManagerFactory->getManager('modules');

        $invModuleSubscribed = $modMgr->isModuleSubscribed("7.INV");
        if (!$invModuleSubscribed && !$this->isInitiateSubscribeToInventory()) {
            // If the Inventory Control module is not subscribed AND we are
            // NOT in the process of subscribing to Inventory Module
            // remove all inventory related fields
            unset($values['DOCPAR_TOTALS']);
            unset($values['WARNONLOWQTY']);
            unset($values['UPDATES_INV']);
            unset($values['UPDATES_COST']);
            unset($values['WAREHOUSESELMETHOD']);
            unset($values['DEFAULT_WAREHOUSE']);

            if (IsAdvancedConfiguration() && $this->isUpdateInOutFieldAutomatically()) {
                unset($values['IN_OUT']);
            }
        } else {

            $affectsInventoryMaintainMap = array(
                'Quantity' => 'Quantity',
                'Value' => 'Value',
                'Quantity & Value' => 'Quantity and Value');
            $updatesInventorySignMap = array(
                'Subtract' => 'Decrease',
                'Add' => 'Increase');

            $affectsCost = 'false';
            $affectsInventory = 'No';
            if (isArrayValueProvided($values, 'IN_OUT')) {
                $updatesInventory = $values['IN_OUT'];
            } else {
                $updatesInventory = 'Increase';     // Just some default "valid" value, otherwise EntityManager would complain
            }
            foreach (($values['DOCPAR_TOTALS']) ?? [] as $inventoryTotal) {
                $maintain = $inventoryTotal['Q_QV'];
                $sign = $inventoryTotal['SIGN'];
                if ('ONHAND' === $inventoryTotal['TOTALID']) {
                    if (('Value' === $maintain
                            || $maintain === 'Quantity & Value')
                        && 'Add' === $sign) {
                        $affectsCost = 'true';
                    }

                    $affectsInventory = $affectsInventoryMaintainMap[$maintain];

                    $updatesInventory = $updatesInventorySignMap[$sign];

                    break;
                }
            }
            if ($this->isUpdateInOutFieldAutomatically()) {
                $values['IN_OUT'] = $updatesInventory;
            }
            $values['UPDATES_COST'] = $affectsCost;
            $values['UPDATES_INV'] = $affectsInventory;
        }
    }

    /**
     * Identifies if the Increases/Decreases Inventory and Billings field
     * must be updated automatically base on user entry on other fields.
     * This method can be overridden by the implementing classes to add
     * additional logic.
     *
     * @return bool
     */
    protected function isUpdateInOutFieldAutomatically()
    {
        return true;
    }

    /**
     * Ensures correctness of format and completeness of permission data
     * as follows:
     * - If the user permission selection flag is NOT checked and there is no
     *   permissions provided add the default.
     * - Correct the format if there is a single permission provided and it
     *   is NOT in a collection but came as a set of fields.
     *
     * @param array $values
     */
    private function preparePermissions(&$values)
    {
        if (isset($values['USERPERM']) && 'true' !== $values['USERPERM']) {
            unset($values['PERMLIST']);
            $values['PERMLIST'] = array(
                array(
                    "PERMLISTMEMBER" => "Group/Everyone",
                    "ALLOWACCESS" => "true",
                    "ALLOWACCESS2" => "allow"
                )
            );
        }

        if (isset($values['PERMLIST']) && !is_array($values['PERMLIST'][0])) {
            if (is_array($values['PERMLIST'])) {
                $singlePermission = $values['PERMLIST'];
                $values['PERMLIST'] = array();
                $values['PERMLIST'][0] = $singlePermission;
            }
        }

        // Overwrite the values of field ALLOWACCESS based on ALLOWACCESS2
        if (isset($values['PERMLIST'])) {
            foreach ($values['PERMLIST'] as & $permission) {
                if ('allow' === $permission['ALLOWACCESS2']) {
                    $permission['ALLOWACCESS'] = 'true';
                } else if ('deny' === $permission['ALLOWACCESS2']) {
                    $permission['ALLOWACCESS'] = 'false';
                }
            }
        }
    }

    /**
     * Removes all the records from all owned objects that have no
     * valid (non-blank) field
     *
     * @param array $values
     */
    private function removeEmptyEntities(&$values)
    {
        $ownedObjects =& $this->GetOwnedObjects();
        // iterate over each owned object
        foreach ($ownedObjects as $ownedObject) {
            $path = $ownedObject['path'];
            if (isset($values[$path]) && is_array($values[$path])) {
                // iterate over each record in the collection
                foreach ($values[$path] as $key => $singleRecord) {
                    if (isset($singleRecord) && is_array($singleRecord)) {
                        // iterate over each field and confirm that at least
                        // one field has a valid value
                        $removeRecord = true;
                        foreach ($singleRecord as $field) {
                            if ('' !== $field) {
                                $removeRecord = false;
                                break;
                            }
                        }
                        if ($removeRecord) {
                            unset($values[$path][$key]);
                        }
                    }
                }
            }
        }
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    public function translateContactTitles(&$values)
    {
        return true;
    }

    /**
     * Drops the content of the the Entity Settings table if:
     * 1. This is a NON-multientity company.
     * 2. This is a multientity company but the user is logged in into
     *    the entity.
     *
     * @param array $values
     */
    private function prepareEntityProperties(&$values)
    {
        $dropEntitySpecifics = !IsMultiEntityCompany();
        $dropEntitySpecifics = $dropEntitySpecifics ||
            (IsMultiEntityCompany() && GetContextLocation());
        if ($dropEntitySpecifics && isArrayValueProvided($values, 'DOCPAR_ENTITY_PROPS')) {
            $values['DOCPAR_ENTITY_PROPS'] = [];
        } else {
            if (isset($values['DOCPAR_ENTITY_PROPS']) && is_array($values['DOCPAR_ENTITY_PROPS'])) {
                foreach ($values['DOCPAR_ENTITY_PROPS'] as $ind => & $entityProps) {
                    if (!isArrayValueProvided($entityProps, 'ENTITY_NAME')) {
                        // No entity name is specified. Drop the line
                        unset($values['DOCPAR_ENTITY_PROPS'][$ind]);
                    } else if (CreationRuleConstants::TOP_LEVEL === $entityProps['ENTITY_NAME']) {
                        // Drop the default reference line (with entity name = Top level)
                        unset($values['DOCPAR_ENTITY_PROPS'][$ind]);
                    } else {
                        // Valid record for entity
                        $nullableFields = ['SEQUENCE', 'XSLTEMPLATE', 'SUBTOTALTEMPLATE'];
                        foreach ($nullableFields as $nullableField) {
                            if ('' === $entityProps[$nullableField]) {
                                unset($entityProps[$nullableField]);
                            }
                        }
                    }
                }
            }

        }
    }

    /**
     * Prepares the creation rule for both root and entities.
     *
     * @param array $values
     */
    private function prepareCreationRule(&$values)
    {
        // Unconditionally unset the 'CREATION_RULE' field
        unset($values['CREATION_RULE']);

        if (!IsMultiEntityCompany() || !GetContextLocation()) {
            // Logged in as root
            if (!isset($values['TD_CREATION_RULE']) ||
                !strcontains($values['TD_CREATION_RULE'], 'Entity')) {
                // Unset the entity specific setting if:
                // - TD creation rule is not provided
                // - TD creation rule is NOT set to entity in any way
                unset($values['DOCPAR_ENTITY_PROPS']);
            } else {
                // Iterate over the Entity Settings and set the
                // entity creation rule to true
                if (isset($values['DOCPAR_ENTITY_PROPS']) && is_array($values['DOCPAR_ENTITY_PROPS'])) {
                    foreach ($values['DOCPAR_ENTITY_PROPS'] as & $entityProps) {
                        if (isArrayValueProvided($entityProps, 'ENTITY_NAME')) {
                            $entityProps['ENTITY_CREATION_RULE'] = 'true';
                        }
                    }
                }
            }
        }
    }

    /**
     * The transaction posting field is populated with label in the following case:
     * - standard setup
     * - view -> duplicate -> save
     *
     * Need to convert to the proper value.
     *
     * @param array $values
     * @param EntityManager $manager
     */
    private function prepareTxnPosting(&$values, EntityManager $manager)
    {
        if (isArrayValueProvided($values, 'UPDATES_GL')) {
            $entityMap = $manager->GetEntityInfoMap();
            if (isArrayValueProvided($entityMap, 'UPDATES_GL')) {
                $fldType = $entityMap['UPDATES_GL']['type'];

                foreach ($fldType['validlabels'] as $index => $label) {
                    if ($label === $values['UPDATES_GL']) {
                        $values['UPDATES_GL'] = $fldType['validvalues'][$index];
                        break;
                    }
                }
            }
        }
    }

    /**
     * The method checks out for correctness of provided optional fields
     * and populates with defaults against the corresponding database columns.
     *
     * Generates an error if the optional data is provided but is incorrect.
     *
     * @param array $values
     *
     * @return bool
     */
    protected function prepareEntityValues(&$values)
    {
        global $gManagerFactory, $gErr;
        $ok = true;

        // Remove all the entities in the owned objects having all fields blank
        $this->removeEmptyEntities($values);

        // Populate all the fields with the default values
        $this->populateDefaults($values);

        // for overwriting Contacttitle3 in UI
        $this->translateContactTitles($values);

        // Specify hidden fields of the Inventory Control section based
        // on data provided for Inventory Total
        $this->setHiddenInventoryFields($values);

        // adjust the numbering scheme related fields
        $this->prepareNumberingScheme($values);

        // Remove Posting Configuration if the tab is not visible
        $this->preparePostingConfiguration($values);

        // Ensures correctness of format and completeness of permission data
        $this->preparePermissions($values);

        $this->prepareTxnPosting($values, $this);

        // Remove the line item for the root from the TD entity properties
        $this->prepareEntityProperties($values);

        // Self-explanatory, on both entity and root level
        $this->prepareCreationRule($values);

        // Defaulting location/dept override for Mega root logins
        $contextLocation = GetContextLocation();
        if (IsMultiEntityCompany() && $contextLocation == '') {
            $values['LOCOVERRIDE'] = 'true';
            $values['DEPTOVERRIDE'] = 'true';
        }

        // If the warehouse selection method is not default remove the
        // default warehouse
        if ($values['WAREHOUSESELMETHOD'] != 'Use the default warehouse') {
            $values['DEFAULT_WAREHOUSE'] = '';
        } else {
            // Default warehouse selection method is selected
            $values[':defaultwhsekey'] = '';
            if (!$values['DEFAULT_WAREHOUSE']) {
                // default warehouse is NOT provided
                $ok = false;
                $gErr->addIAError(
                    'INV-0040', __FILE__ . ':' . __LINE__,
                    "Default warehouse is not provided.", []
                );
            } else {
                $warehouseMgr = $gManagerFactory->getManager('warehouse');
                $defwhse = explode("--", $values['DEFAULT_WAREHOUSE']);

                $recordno = $warehouseMgr->GetRecordNoFromVid($defwhse[0]);
                if (isset($recordno)) {
                    $values[':defaultwhsekey'] = $recordno;
                } else {
                    $ok = false;
                    $gErr->addIAError(
                        'INV-1439', __FILE__ . ':' . __LINE__,
                        "Default warehouse is invalid."
                    );
                }
            }
        }

        // Get the price list manager
        $plManager = $gManagerFactory->getManager('invpricelist');

        // If the Initial Price List is provided (text in a free form) check for a
        // proper record in the database and populate the default
        if ($ok) {
            $values[':prclistkey'] = '';
            if ($values['PRICELISTID']) {
                $recordno = $plManager->GetRecordNoFromVid(
                    $values['PRICELISTID']
                );
                if (isset($recordno)) {
                    $values[':prclistkey'] = $recordno;
                } else {
                    $gErr->addIAError(
                        'INV-0041', __FILE__ . ':' . __LINE__,
                        "Incorrect value for the Initial Price List.", []);
                    $ok = false;
                }
            }
        }

        // If the 'Price List To Update' is provided (text in a free form) check
        // for a proper record in the database and populate the default
        if ($ok) {
            $values[':updprclistkey'] = '';
            if ($values['UPDATES_PRICELISTID']) {
                $recordno = $plManager->GetRecordNoFromVid(
                    $values['UPDATES_PRICELISTID']
                );
                if (isset($recordno)) {
                    $values[':updprclistkey'] = $recordno;
                } else {
                    $gErr->addIAError(
                        'INV-0042', __FILE__ . ':' . __LINE__,
                        "Incorrect value for the Price List To Update.", []);
                    $ok = false;
                }
            }
        }

        // If the 'Price List To Update' is provided (text in a free form) check
        // for a proper record in the database and populate the default
        if ($ok) {
            $values[':spclprclistkey'] = '';
            if ($values['SPECIAL_PRICELISTID']) {
                $recordno = $plManager->GetRecordNoFromVid($values['SPECIAL_PRICELISTID']);
                if (isset($recordno)) {
                    $values[':spclprclistkey'] = $recordno;
                } else {
                    $gErr->addIAError(
                        'INV-0043', __FILE__ . ':' . __LINE__,
                        "Incorrect value for the Special Price List.", []);
                    $ok = false;
                }
            }
        }

        // If the 'Exchange Rate Type' is provided (text in a free form) check
        // for a proper record in the database and populate the default
        if ($ok) {
            $values[':exch_rate_type_id'] = '';
            // added check to is_array $values['EXCHRATETYPES'] for php 8.1 error
            if (is_array($values['EXCHRATETYPES']) && $values['EXCHRATETYPES']['NAME']) {
                $exchratetypeMgr = $gManagerFactory->getManager(
                    'exchangeratetypes'
                );
                $exchrateid = $exchratetypeMgr->GetExchangeRateTypeID(
                    $values['EXCHRATETYPES']['NAME']
                );
                if (isset($exchrateid)) {
                    $values[':exch_rate_type_id'] = $exchrateid;
                } else {
                    $gErr->addIAError(
                        'INV-0044', __FILE__ . ':' . __LINE__,
                        "Incorrect value for the Exchange Rate Type.", []);
                    $ok = false;
                }
            }
        }

        // If the Printed Format  is provided (text in a free form) check
        // for a proper record in the database and populate the default
        $ok = $ok && $this->translateXSLTemplate($values);
        // If the sequence (numbering pattern) is provided (text in a free form) check
        // for a proper record in the database and populate the default
        if ($ok) {
            $values[':seqnumkey'] = '';
            if (isArrayValueProvided($values, 'SEQUENCE')) {
                $seqnumManager = $gManagerFactory->getManager('seqnum');
                $recordno = $seqnumManager->GetRecordNoFromVid($values['SEQUENCE']);
                if (isset($recordno)) {
                    $values[':seqnumkey'] = $recordno;
                } else {
                    $gErr->addIAError(
                        'INV-0046', __FILE__ . ':' . __LINE__,
                        "Incorrect value for the Numbering Scheme.", []);
                    $ok = false;
                }
            }
        }

        // Check the provided term name. This is valid for PO and SO.
        // Throw an exception in case of Inventory TD
        if ($ok) {
            $values[':termkey'] = '';
            if ($values['TERM_NAME']) {
                if ('so' !== $this->_mod
                    && 'po' !== $this->_mod
                ) { // $isInventory
                    $msg =
                        "Remove Term name from your input data. It is redundant for Inventory transaction definition.";
                    $gErr->addIAError(
                        'INV-0391', __FILE__ . ':' . __LINE__, $msg, []
                    );
                    $ok = false;
                } else {
                    $termMap = ['so' => 'arterm', 'po' => 'apterm'];
                    $termManager = $gManagerFactory->getManager(
                        $termMap[$this->_mod]
                    );
                    $recordno = $termManager->GetRecordNoFromVid(
                        $values['TERM_NAME']
                    );
                    if (isset($recordno)) {
                        $values[':termkey'] = $recordno;
                    } else {
                        $msg = "Invalid Term " . $values['TERM_NAME'];
                        $gErr->addIAError(
                            'INV-0392', __FILE__ . ':' . __LINE__, $msg, ['VALUES_TERM_NAME' => $values['TERM_NAME']]
                         );
                        $ok = false;
                    }
                }
            }
        }
        $this->formingLineNo($values);

        $ok = $ok && $this->populateSubtotalsfromTemplate($values);

        $this->prepareSubtotals($values);

        // Adjust the values for DEPTOVERRIDE and LOCOVERRIDE
        $this->adjustOverwriteFields($values);

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     * @throws IAException
     */
    protected function translateXSLTemplate(&$values)
    {
        $ok = true;
        $values[':docxslkey'] = '';
        if ( $values['XSLTEMPLATE'] ) {
            $XslformatMgr = Globals::$g->gManagerFactory->getManager('xslformat');
            $recordno = $XslformatMgr->GetRecordNo('DESCRIPTION', $values['XSLTEMPLATE']);
            if ( isset($recordno) ) {
                $values[':docxslkey'] = $recordno;
            } else {
                Globals::$g->gErr->addIAError(
                    'INV-0045', __FILE__ . ':' . __LINE__,
                    "Incorrect value for the Printed Format.", []);
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * Adjust the values of certain fields and set them to blank if they have
     * no value or the value is not 'true'.
     *
     * @param array $values
     */
    private function adjustOverwriteFields(&$values)
    {
        $overwriteFields = ['DEPTOVERRIDE', 'LOCOVERRIDE'];
        foreach ($overwriteFields as $field) {
            if (!isset($values[$field]) || 'true' !== $values[$field]) {
                $values[$field] = '';
            }
        }
    }

    /**
     * Adds the transaction definition ordinal number to its preferences
     * if it hasn't been stored yet. Does nothing otherwise.
     *
     * @param string $tdRecordId
     *
     * @return bool     true if successful and false otherwise
     * @throws Exception
     */
    private function insertOrdinalNumber($tdRecordId)
    {
        $ok = true;

        $moduleKey = $this->_modID;

        // first check if the order for the given TD has been stored already
        $recordExist = $this->_MM->getEntityPreference('TD_RECORD#' . $tdRecordId, $moduleKey);

        if (!$recordExist) {
            // for the entity if it has no ordinal # stored do the following:
            // 1. Check if the root has ordinal # stored
            // 2. Check if there is no any entity specific ordinal number stored
            //    and do not implement step #3 if YES
            // 3. Copy all root level ordinal # to the entity level
            if (IsMultiEntityCompany() && GetContextLocation()) {
                $rootPrefs = $this->_MM->getPreferencesByPattern('TD_RECORD#', $moduleKey, true);
                if ($rootPrefs && is_array($rootPrefs)) {
                    /* @var DocumentSetupManager $documentSetupManager */
                    $documentSetupManager
                        = Globals::$g->gManagerFactory->getManager($this->_mod . 'setup');
                    $entitySpecificPrefs = $documentSetupManager->getEntitySpecificTDOrdinalNumbers();
                    if (!$entitySpecificPrefs) {
                        $documentSetupManager->copyRootTDOrderToEntity();
                    }
                }
            }

            // find the next ordinal number
            $nextOrdinalNumber = $this->getNextOrdinalNumber();

            $ok = $nextOrdinalNumber
                && $this->_MM->SetPreference(
                    'TD_RECORD#' . $tdRecordId, $nextOrdinalNumber, true,
                    $moduleKey
                );
        }
        return $ok;
    }

    /**
     * Returns the ordinal number that will be assigned to the transaction
     * definition.
     *
     * @return null|string
     */
    private function getNextOrdinalNumber()
    {
        $nextOrdinalNo = null;
        $stmt = array();

        $stmt[0] =
            "SELECT nvl(max(to_number(value)), 0) + 1 as NEXT_VALUE " .
            "FROM MODULEPREF " .
            "WHERE cny# = :1 and modulekey = :2 and property like 'TD_RECORD#%'";
        $stmt[1] = GetMyCompany();
        $stmt[2] = $this->_modID;

        if (IsMultiEntityCompany() && GetContextLocation()) {
            $stmt[0] .= " and locationkey = :3 ";
            $stmt[3] = GetContextLocation();
        } else {
            $stmt[0] .= " and locationkey is null ";
        }

        $result = QueryResult($stmt);
        if (isset($result[0])) {
            $nextOrdinalNo = $result[0]['NEXT_VALUE'];
        }

        return $nextOrdinalNo;
    }

    /**
     * 1. If the $tdRecordIdOld parameter is not provided simply calls the
     *    insertOrdinalNumber method.
     * 2. If the $tdRecordIdOld parameter is provided reads the ordinal
     *    number for that id, deletes the existing record and inserts a
     *    new record for a $tdRecordIdNew
     *
     * @param string $tdRecordIdNew
     * @param string $tdRecordIdOld
     *
     * @return bool
     * @throws Exception
     */
    private function updateOrdinalNumber($tdRecordIdNew, $tdRecordIdOld = null)
    {

        if (!isset($tdRecordIdOld) || $tdRecordIdOld == null) {
            $ok = $this->insertOrdinalNumber($tdRecordIdNew);
        } else {
            $moduleKey = $this->_modID;
            // check if the ordinal number for the TD old is exists
            $ordinalNumber = $this->_MM->getEntityPreference('TD_RECORD#' . $tdRecordIdOld, $moduleKey);
            if (!$ordinalNumber) {
                // there is no record in the DB with the old ID
                $ok = $this->insertOrdinalNumber($tdRecordIdNew);
            } else {
                // First delete an existing record
                $ok = $this->_MM->DeletePreference('TD_RECORD#' . $tdRecordIdOld, $this->_modID);
                // Now insert the preference for the new id with the existing
                // ordinal number
                $ok = $ok && $this->_MM->SetPreference(
                        'TD_RECORD#' . $tdRecordIdNew, $ordinalNumber, true, $moduleKey
                    );

                if (!GetContextLocation()) {
                    // If updating the TD on root update all the preferences
                    // on relevant entities
                    $ok = $ok && $this->_MM->updatePreferenceForAllEntities(
                            'TD_RECORD#' . $tdRecordIdNew,
                            'TD_RECORD#' . $tdRecordIdOld,
                            $this->_modID
                        );
                }
            }
        }
        return $ok;
    }

    /**
     * Placeholder for validat API call
     *
     * @param array $values
     */
    public function Validate(/** @noinspection PhpUnusedParameterInspection */ &$values)
    {
        epp("Validate in " . get_class($this));
    }


    /**
     * @param array     $values     The values for the td
     *
     * @return bool                 is it ok?
     */
    private function validateFulfillmentParams($values)
    {
        if (InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            $fulfillmentOn = (($values['ENABLEFULFILLMENT']  === 'true') || ($values['ENABLEFULFILLMENT']  === 'T'));
            if ($fulfillmentOn) {
                $docclass = $values['DOCCLASS'] ?? '';
                $workflow = $values['CATEGORY'] ?? '';

                $isOrder   = (($docclass === 'Order') && ($workflow === 'Order'));
                $isOrder2  = ((($docclass === 'Order') || ($docclass === 'List')) && ($workflow === 'Order'));
                $isInvoice = (($docclass === 'Invoice') && ($workflow === 'Invoice'));
                $isShipper = ((($docclass === 'Order') || ($docclass === 'List')) && ($workflow === 'Shipping'));
                $classAndWorkflowOk = ($isOrder || $isShipper || $isInvoice);

                // is fulfillment checked?  Is it right?
                if ($fulfillmentOn && ! $classAndWorkflowOk) {
                    Globals::$g->gErr->addIAError('INV-0047', __FILE__ . ':' . __LINE__,
                        "To enable for fulfillment, set the combination of ‘Template type’ and ‘Workflow category’ to Order/Order, Order/Shipping, List/Shipping, or Invoice/Invoice. ", [],
                        "Uncheck 'Enable for fulfillment' or select different options, and try again.", []);
                    return false;
                }

                $totals     = $this->getOnHandOnHold($values);

                // only ONE of the totals, right?
                if (( ! empty($totals["ONHOLD"])) && ( ! empty($totals["ONHAND"]))) {
                    Globals::$g->gErr->addIAError('INV-0048', __FILE__ . ':' . __LINE__,
                        "You can only affect ONHAND or ONHOLD, not both. Remove one from the inventory totals. Then, try again. ", []);
                    return false;
                }

                // check orders for fulfillment and reserve/allocate:
                $isOnHold   = (( ! empty($totals["ONHOLD"])) && ($totals["ONHOLD"]['SIGN'] === 'Add'));
                if (($isOrder || $isOrder2) && ! $isOnHold) {
                    Globals::$g->gErr->addIAError('INV-0049', __FILE__ . ':' . __LINE__,
                        "For the workflow type of ‘Order’, change the inventory total to increase ONHOLD quantity. Then, try again. ", []);
                    return false;
                }

                // now check shipper or invoice
                $isOnHand   = (( ! empty($totals["ONHAND"])) || ($totals["ONHAND"]['SIGN'] !== 'Subtract'));
                if (($isInvoice || $isShipper) && ! $isOnHand) {
                    Globals::$g->gErr->addIAError('INV-0050', __FILE__ . ':' . __LINE__,
                        "For the workflow type of ‘Shipper’ or 'Invoice', change the inventory total to decrease ONHAND. Then, try again. ", []);
                    return false;
                }

                // for fulfillment, check convert type, updates gl, and enable renewals....
                if ($fulfillmentOn) {
                    $convtype = $values['CONVTYPE'] ?? '';
                    $updateGL = $values['UPDATES_GL'] ?? '';
                    $renewals = $values['ENABLERENEWALS'] ?? '';
                    $bad      = ($convtype !== 'Leave Transaction Open') ||
                        ($updateGL !== (($docclass === "Invoice") ? 'A' : 'N')) ||
                        ($renewals !== 'None');
                    if ($bad) {
                        Globals::$g->gErr->addIAError('INV-0051', __FILE__ . ':' . __LINE__,
                            "To enable fulfillment, the Partial conversion handling needs to be 'Leave Transaction Open', Enable renewals needs to be 'Don't enable', and Transaction posting needs to be 'Accounts Receivable' for Invoices, otherwise 'Don't post'.  Fix these values and try again. ", []);
                        return false;
                    }
                }
            }

            if (($fulfillmentOn === false)) {
                // WAS it on and they created transactions for this TD?
                if (isset($values['RECORDNO']) && $this->anyTransactionsUseThisDocPar('ENABLEFULFILLMENT', $values['RECORDNO'], $fulfillmentOn)) {
                    Globals::$g->gErr->addIAError(
                        'INV-0052', __FILE__ . ':' . __LINE__,
                        "The option for fulfillment cannot be turned off because existing transactions are using the transaction definition.", [],
                        "To turn the options off, delete the transactions.", []
                    );
                    return false;
                }
            }
        } else {
            // feature is NOT enabled.....
            $fulfillmentOn = (($values['ENABLEFULFILLMENT']  === 'true') || ($values['ENABLEFULFILLMENT']  === 'T'));
            if ($fulfillmentOn) {
                Globals::$g->gErr->addIAError(
                    'INV-0053', __FILE__ . ':' . __LINE__,
                    "ENABLEFULFILLMENT is not valid, as the Fulfillment feature has not been enabled.", [],
                    "Enable fulfillment and try again", []
                );
                return false;
            }
        }
        return true;
    }

    /**
     * @param array     $values     The values for the td
     *
     * @return bool                 is it ok?
     */
    private function validateAllocReserveParams($values)
    {
        if (InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            $allocReserve  = (($values['ENABLEALLOCRESERVE'] === 'true') || ($values['ENABLEALLOCRESERVE'] === 'T'));
            if ($allocReserve) {
                $docclass = $values['DOCCLASS'] ?? '';
                $workflow = $values['CATEGORY'] ?? '';

                $isOrder   = (($docclass === 'Order') && ($workflow === 'Order'));
                $isOrder2  = ((($docclass === 'Order') || ($docclass === 'List')) && ($workflow === 'Order'));
                $isInvoice = (($docclass === 'Invoice') && ($workflow === 'Invoice'));
                $isShipper = ((($docclass === 'Order') || ($docclass === 'List')) && ($workflow === 'Shipping'));

                // is alloc/reserve checked?  Is it right?
                if ($allocReserve && ! $isOrder2) {
                    // alert( _("To enable inventory items for reserving and picking, the 'Template type' must be Order or List, and the 'Workflow category' must be Order. "));
                    Globals::$g->gErr->addIAError(
                        'INV-0054', __FILE__ . ':' . __LINE__,
                        "To enable inventory items for reserving and picking, set ‘Template type’ to Order or List and ‘Workflow category’ to Order. ", [],
                        "Uncheck 'Enable inventory items for reserving and picking' or select different options, and try again.", []
                    );
                    return false;
                }

                $totals     = $this->getOnHandOnHold($values);

                // only ONE of the totals, right?
                if (( ! empty($totals["ONHOLD"])) && ( ! empty($totals["ONHAND"]))) {
                    Globals::$g->gErr->addIAError('INV-0055', __FILE__ . ':' . __LINE__,
                        "You can only affect ONHAND or ONHOLD, not both. Remove one from the inventory totals. Then, try again. ", []);
                    return false;
                }

                // check orders for fulfillment and reserve/allocate:
                $isOnHold   = (( ! empty($totals["ONHOLD"])) && ($totals["ONHOLD"]['SIGN'] === 'Add'));
                if (($isOrder || $isOrder2) && ! $isOnHold) {
                    Globals::$g->gErr->addIAError('INV-0056', __FILE__ . ':' . __LINE__,
                        "For the workflow type of ‘Order’, change the inventory total to increase ONHOLD quantity. Then, try again. ", []);
                    return false;
                }

                // now check shipper or invoice
                $isOnHand   = (( ! empty($totals["ONHAND"])) || ($totals["ONHAND"]['SIGN'] !== 'Subtract'));
                if (($isInvoice || $isShipper) && ! $isOnHand) {
                    Globals::$g->gErr->addIAError('INV-0057', __FILE__ . ':' . __LINE__,
                        "For the workflow type of ‘Shipper’ or 'Invoice', change the inventory total to decrease ONHAND. Then, try again. ", []);
                    return false;
                }
            }

            if (($allocReserve === false)) {
                // WAS it on and they created transactions for this TD?
                if (isset($values['RECORDNO']) && $this->anyTransactionsUseThisDocPar('ENABLEALLOCRESERVE', $values['RECORDNO'], $allocReserve)) {
                    Globals::$g->gErr->addIAError(
                        'INV-0058', __FILE__ . ':' . __LINE__,
                        "The option for reserving and picking inventory items cannot be turned off because existing transactions are using the transaction definition.", [],
                        "To turn the options off, delete the transactions.", []
                    );
                    return false;
                }
            }
        } else {
            // feature is NOT enabled.....
            $allocReserve  = (($values['ENABLEALLOCRESERVE'] === 'true') || ($values['ENABLEALLOCRESERVE'] === 'T'));
            if ($allocReserve) {
                Globals::$g->gErr->addIAError(
                    'INV-0059', __FILE__ . ':' . __LINE__,
                    "ENABLEALLOCRESERVE is not valid, as the Fulfillment feature has not been enabled.", [],
                    "Enable fulfillment and try again", []
                );
                return false;
            }
        }
        return true;
    }


    /**
     *  Search the totals for ONHAND and ONHOLD values
     *
     * @param array     $values     the document being saved
     *
     * @return array                the ONHAND and ONHOLD values, if they exist
     */
    private function getOnHandOnHold($values)
    {
        $rtn = [
            'ONHAND' => [],
            'ONHOLD' => [],
        ];
        foreach (($values['DOCPAR_TOTALS']) ?? [] as $inventoryTotal) {
            $maintain = $inventoryTotal['Q_QV'];    // 'Value', 'Quantity & Value', 'Quantity'
            $sign     = $inventoryTotal['SIGN'];    // 'Add'
            $totalID  = $inventoryTotal['TOTALID'];

            if (($totalID === 'ONHAND') || ($totalID === 'ONHOLD')) {
                $rtn[$totalID] = ['SIGN' => $sign, 'Q_QV' => $maintain];
            }
        }
        return $rtn;
    }


    /**
     *      Is fulfilment or alloc/reserve being turned off?  Does any transaction use it?
     *
     *
     * @param string        $path               the path of 'ENABLEFULFILLMENT', 'ENABLEALLOCRESERVE' to check if it has transactions?
     * @param int           $docParRecordno     the record number being changed
     * @param bool          $enabled            is the passed in $path ('ENABLEFULFILLMENT', 'ENABLEALLOCRESERVE') on?
     *
     * @return bool                             are there any transactions still around that need this DocPar????
     */
    private function anyTransactionsUseThisDocPar($path, $docParRecordno, $enabled)
    {
        if ($docParRecordno) {
            // the passed parameters are what we want to set to,
            // lets see what it WAS
            $params = [
                'selects' => [ $path ],
                'filters' => [ [ [ 'RECORDNO', '=', $docParRecordno ] ] ],
                'usemst'  => true,
            ];
            $result = $this->GetList($params);
            if ( ( $result === false ) || empty($result) ) {
                return false;   // well, this means there aren't any txns, but it will have to do
            }

            // you can turn it ON but you can't turn it OFF
            $pathResult = ( $result[0][$path] ?? 'false' ) === 'true';
            if ( ( $pathResult === true ) && ( $enabled === false ) ) {
                // THE FLAG CHANGED - WAS A TX USING THIS?
                $sql = [];
                $sql[] = "SELECT distinct 1 FROM dochdrmst WHERE cny# = :1 and docparkey = :2 ";
                $sql[] = GetMyCompany();
                $sql[] = $docParRecordno;
                $result = QueryResult($sql);
                if ( ( $result !== false ) && ! empty($result) ) {
                    return true;
                }
            }
        }
        return false;   // either the flags did not change or no one was using them
    }

    /**
     * @param array $values
     * @return bool
     */
    private function translateAcctNoToRecNo(&$values)
    {
        $allOwnedObject = $this->GetOwnedObjects();
        $glAccounts = [];
        $pathArr = [];
        foreach ($allOwnedObject as $ownedObject) {
            $ownedObjectPath = $ownedObject['path'];
            $pathArr[] = $ownedObjectPath;
            $ownedObjectPathData =  $values[$ownedObjectPath] ?? [];
            foreach ($ownedObjectPathData as $objData){
                if(isset($objData['GLACCOUNT'])){
                    $glAccounts[] = explode(BaseAccountManager::ACCT_NO_TITLE_SEPERATOR, $objData['GLACCOUNT'])[0];
                }
            }
        }

        if (!Util::isEmptyCountable($glAccounts)) {
            $glAccountMgr = Globals::$g->gManagerFactory->getManager("glaccount");

            $filters = ['selects' => ['RECORDNO', 'ACCOUNTNO'], 'filters' => [[['ACCOUNTNO', 'in', array_unique($glAccounts)]]]];
            $result = $glAccountMgr->GetList($filters);
            $acctNoNdRecNoMap = [];
            if (!Util::isEmptyCountable($result)) {
                foreach ($result as $acctNoSet) {
                    $acctNoNdRecNoMap[$acctNoSet['ACCOUNTNO']] = $acctNoSet['RECORDNO'];
                }
            }

            foreach ($pathArr ?? [] as $ownedObjPath) {
                $ownedObjectData = &$values[$ownedObjPath];
                foreach ($ownedObjectData as &$entry) {
                    $glAccountNo = explode(BaseAccountManager::ACCT_NO_TITLE_SEPERATOR, $entry['GLACCOUNT'] ?? "")[0];
                    $recordNo = $acctNoNdRecNoMap[$glAccountNo];
                    if (isset($recordNo)) {
                        $entry['GLACCOUNTRECORDNO'] = $recordNo;
                    }
                }
            }
        }
        return true;
    }


    /**
     * Creates a new transaction definition.
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = "DocumentParamsManager::Add";

        global $gErr;
        global $gManagerFactory;

        // Show error message if there is an attempt to create a new TD
        // in a company with standard setup
        if (!IsAdvancedConfiguration() && !$this->isAutomaticallyGenerated()) {
            $gErr->addIAError(
                'INV-0060', __FILE__ . ':' . __LINE__,
                'New transaction definition cannot be created for the account with the standard setup.', []
            );
        }

        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->validateParams($values);
        $ok = $ok && $this->validateFulfillmentParams($values);
        $ok = $ok && $this->validateAllocReserveParams($values);
        $ok = $ok && $this->validateAIAParams($values);
        $ok = $ok && $this->additionalInfoFieldsValidation($values);
        //remove unwanted spaces in between while creating.
        $values['DOCID'] = isl_preg_replace('/\s\s+/', ' ', trim($values['DOCID']));
        $ok = $ok && $this->isDocumentIDUnique($values['DOCID']);

        // $ok = $ok && $this->PrepValues($values);
        $ok = $ok && $this->prepareEntityValues($values);
        $validator = DocumentParamsValidatorFactory::create($this, Operation::CREATE_NEW);
        $ok = $ok && $validator->validate($values);


        $ok = $ok && $this->CreateRecurringSchedule($values['ENABLESCHEDULE']);
        $ok = $ok && $this->translateAcctNoToRecNo($values);
        $ok = $ok && parent::regularAdd($values);

        // Update the permissions for the given document
        $ok = $ok && processPermissions($values);

        $ok = $ok && $this->insertOrdinalNumber($values['RECORDNO']);

        $ok = $ok && $this->_setDocParPrefStatus($values['DOCID'], $values['STATUS']);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if (!HasErrors() && HasWarnings()) {
                $this->_QM->rollbackTrx($source);
            } else {
                $msg = "Could not create Document Parameter record!";
                $gErr->addIAError('INV-0393', __FILE__ . ':' . __LINE__, $msg, []);
                epp("$source: Error: $msg");
                $this->_QM->rollbackTrx($source);
            }
        }

        if ($ok) {

            // Let  platform know about the new doc
            $scmDocs = CustomERPCatalog::getSCMDocumentMap($values);
            foreach ($scmDocs as $docTypeCatName => $docTypeCatList) {
                if (isset($docTypeCatList) && is_array($docTypeCatList)) {
                    foreach ($docTypeCatList as $docType) {
                        $entMgr = $gManagerFactory->getManager($docTypeCatName, true, array('DOCTYPE' => $docType));
                        Pt_Cache::createStandardObjectDef($entMgr);
                    }
                }
            }
        }

        return $ok;
    }

    /**
     * Removes the RECORDNO field from transaction definition object and
     * any containing child.
     *
     * @param array $values
     */
    private function unsetRecordNo(&$values)
    {
        unset($values['RECORDNO']);

        $ownedObjects =& $this->GetOwnedObjects();

        if (is_array($ownedObjects)) {
            foreach ($ownedObjects as $objRec) {
                $path = $objRec['path'];
                if (is_array($values[$path])) {
                    foreach ($values[$path] as &$ownObjValues) {
                        if (isArrayValueProvided($ownObjValues, 'RECORDNO')) {
                            unset($ownObjValues['RECORDNO']);
                        }
                    }
                    unset($ownObjValues);
                }
            }
        }
    }

    /**
     * Updates the transaction definition.
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $source = "DocumentParamsManager::Set";

        global $gErr;
        global $gManagerFactory;

        $latestVersionKey = $this->getLatestVersionKey($values['DOCID']);
        if ($latestVersionKey !== $values['RECORDNO']) {
            $gErr->addIAError(
                'INV-0061', __FILE__ . ':' . __LINE__,
                "Cannot update locked transaction definition.", []
            );
            return false;
        }
        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->validateParams($values);
        $ok = $ok && $this->validateFulfillmentParams($values);
        $ok = $ok && $this->validateAllocReserveParams($values);
        $ok = $ok && $this->validateAIAParams($values, true);
        $ok = $ok && $this->additionalInfoFieldsValidation($values);
        $ok = $ok && $this->prepareEntityValues($values);
        $validator = DocumentParamsValidatorFactory::create($this, Operation::UPDATE);
        $ok = $ok && $validator->validate($values);

        $ok = $ok && $this->CreateRecurringSchedule($values['ENABLESCHEDULE']);

        //Give a warning message if this transaction definition is reffered by any recurring templates
        $RecurTransExists = $this->CheckRecurringTransactions($values['RECORDNO']);

        // For cases where we install the workflow from the setup, we do not want to throw warning messages.
        if (!$values['NOWARNING'] && $this->_warningValidation && $this->shouldWarn(null, $values, []) && $RecurTransExists) {
            global $gErr;
            $gErr->AddWarning("This Transaction definition is refered by some Recurring Transactions. Do you want to continue?");
            $this->_QM->rollbackTrx($source);
            return false;
        }

        $documentManager = Globals::$g->gManagerFactory->getManager('document');
        $enableDocChange = $values['ENABLEDOCCHANGE'] ?? 'No Change';
        $ok = $ok && $documentManager->updateTransactionFields($this, $values['RECORDNO'], $enableDocChange, $values['DOCID']);

        //If this template is used by existing transactions, then version it and create a new version
        //All old transactions will point to this template through their latestversionkey.
        $oldVersionKey = null;
        $ok = $ok && $this->translateAcctNoToRecNo($values);
        if ($ok && $this->NeedsVersioning($values['RECORDNO'])) {
            $oldVersionKey = $values['RECORDNO'];
            $this->unsetRecordNo($values);
            $ok = $ok && parent::regularAdd($values);

            $ok = $ok && $this->updateOffsetGLAccounts($oldVersionKey, $values['RECORDNO']);

            $ok = $ok && $this->SetTemplateVersion($values['DOCID'], $values['RECORDNO']);
            $ok = $ok && $this->SetDocumentValues($oldVersionKey, $values['RECORDNO'], $values['DOCID']);
        } else {
            $ok = $ok && parent::regularSet($values);
        }

        $ok = $ok && $this->setStatusForAllVersions($values['STATUS'], $values['DOCID']);
        $ok = $ok && $this->setReportingCategoryForAllVersions($values['REPORTINGCATEGORY'], $values['DOCID']);

        // Update the permissions for the given document
        $ok = $ok && processPermissions($values);

        $ok = $ok && $this->updateOrdinalNumber($values['RECORDNO'], $oldVersionKey);

        $ok = $ok && $this->_setDocParPrefStatus($values['DOCID'], $values['STATUS']);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            if (!HasErrors() && HasWarnings()) {
                $this->_QM->rollbackTrx($source);
            } else {
                $msg = "Could not update Document Parameter record!";
                $gErr->addIAError('INV-0394', __FILE__ . ':' . __LINE__, $msg, []);
                epp ("$source: Error: $msg");
                $this->_QM->rollbackTrx($source);
            }
        }

        if ($ok) {
            // Let  platform know about the change
            $scmDocs = CustomERPCatalog::getSCMDocumentMap($values);
            foreach ($scmDocs as $docTypeCatName => $docTypeCatList) {
                if (isset($docTypeCatList) && is_array($docTypeCatList)) {
                    foreach ($docTypeCatList as $docType) {
                        $objDef = Pt_StandardUtil::getPlatformObject($docTypeCatName, $docType);
                        if ($objDef) {
                            Pt_Cache::updateStandardObjectDef($objDef->getId(), $objDef->getObjectDefName(), $docType);
                        } else {
                            $entMgr = $gManagerFactory->getManager($docTypeCatName, true, ['DOCTYPE' => $docType]);
                            Pt_Cache::createStandardObjectDef($entMgr);
                        }
                    }
                }
            }

        }

        return $ok;
    }


    /**
     * keeping the sequence order, in the TD for posting configuration tab
     * @param array $values
     */
    protected function formingLineNo(&$values)
    {
        if (isset($values['DOCPAR_INVGL'])) {
            $lineCnt = 0;
            foreach ($values['DOCPAR_INVGL'] as &$line) {
                parent::setLineNo($line, $lineCnt);
            }
            unset($line);
        }

        if (isset($values['DOCPAR_PRGL'])) {
            $lineCnt = 0;
            foreach ($values['DOCPAR_PRGL'] as &$line) {
                parent::setLineNo($line, $lineCnt);
            }
            unset($line);
        }
    }

    /**
     * @param string $oldVersionKey
     * @param string $latestVersionKey
     *
     * @return bool
     */
    protected function updateOffsetGLAccounts($oldVersionKey, $latestVersionKey)
    {
        $ok = true;

        $advanced = IsAdvancedConfiguration();
        if (!$advanced) {
            // for simplified inventory we hide the gl tabs
            // and to avoid overloading the browser we do not pass that data
            // so now we need to copy from previous version

            //
            // Inventory control GL information
            $stmt = "insert into offsetacct (CNY#, RECORD#, ITEMGRPKEY, ENTGRPKEY, WHSEKEY, GLACCOUNTRECORDNO, ISOFFSET, DR_CR, MODULE, DEPTKEY, LOCATIONKEY, LDOVERRIDE, DOCPARKEY)
                        select cny#, GET_NEXTRECORDID(:1, 'OFFSETACCT'), ITEMGRPKEY, ENTGRPKEY, WHSEKEY, GLACCOUNTRECORDNO, ISOFFSET, DR_CR, MODULE, DEPTKEY, LOCATIONKEY, LDOVERRIDE, :3
                        from offsetacct where cny#=:1 and DOCPARKEY = :2 and MODULE = 'INV'";

            $ok = $ok && ExecStmt(array($stmt, GetMyCompany(), $oldVersionKey, $latestVersionKey));

            //
            // Ap/AR GL Information
            $stmt = "insert into offsetacct (CNY#, RECORD#, ITEMGRPKEY, ENTGRPKEY, WHSEKEY, GLACCOUNTRECORDNO, ISOFFSET, DR_CR, MODULE, DEPTKEY, LOCATIONKEY, LDOVERRIDE, DOCPARKEY)
                select cny#, GET_NEXTRECORDID(:1, 'OFFSETACCT'), ITEMGRPKEY, ENTGRPKEY, WHSEKEY, GLACCOUNTRECORDNO, ISOFFSET, DR_CR, MODULE, DEPTKEY, LOCATIONKEY, LDOVERRIDE, :3
                from offsetacct where cny#= :1 and DOCPARKEY= :2 and MODULE = 'PR'";

            $ok = $ok && ExecStmt(array($stmt, GetMyCompany(), $oldVersionKey, $latestVersionKey));
        }

        return $ok;
    }

    /**
     * Override useOwnedObject to prevent documentparinvgl and documentparprgl ownedobjects from being loaded or modified.
     * In simplified inventory we manage gl mappings in the item object rather than the transaction definition.
     *
     * @param array $objRec represent an owned object
     * @param bool $validateReadOnly
     *
     * @return bool
     */
    protected function useOwnedObject($objRec, $validateReadOnly)
    {
        if (!$this->isIncludeOwnObjects()) {
            $entity = $objRec['entity'];
            if (in_array($entity, array($this->_mod . 'documentparinvgl', $this->_mod . 'documentparprgl')) && !IsAdvancedConfiguration()) {
                return false;
            }
        }
        return parent::useOwnedObject($objRec, $validateReadOnly);
    }

    /**
     * Sets the status module preference.
     *
     * @param string $docid
     * @param string $status
     *
     * @return bool
     */
    private function _setDocParPrefStatus($docid, $status)
    {
        // Set Mod pref status, same as docpar status
        $docid_path = $this->_getDocParPrefPath($docid);
        $prefState = ($status == 'active') ? 'true' : 'false';
        return $this->_MM->SetPreference($docid_path, $prefState, 1, $this->_modID);

    }

    /**
     * @param string $docid
     *
     * @return string
     */
    private function _getDocParPrefPath(string $docid) : string
    {
        return "DOCTYPES." . str_replace(' ', '_', $docid);
    }

    /**
     * Delete the status module preference
     * @param string $docid
     *
     * @return bool
     */
    private function _deleteDocParPrefStatus(string $docid)
    {
        $docid_path = $this->_getDocParPrefPath($docid);
        return $this->_MM->DeletePreference($docid_path, $this->_modID, true);
    }

    /**
     * Returns true if the transaction definition with the given record#
     * exists and false otherwise.
     *
     * @param string $docparKey
     *
     * @return bool
     */
    private function NeedsVersioning($docparKey)
    {
        $cny = GetMyCompany();
        $ret = $this->DoQuery('QRY_DOCUMENTPARAMS_TRANSACTIONS_EXIST', array($docparKey, $cny, $docparKey, $cny, $docparKey, $cny, $docparKey, $cny, $cny, $docparKey, $docparKey));
        return ($ret[0]['CNT'] > 0) ? true : false;
    }


    /**
     * Returns true if the transaction definition is referred by any
     * recurring template.
     *
     * @param string $docparKey
     *
     * @return bool
     */
    private function CheckRecurringTransactions($docparKey)
    {
        $ret = $this->DoQuery('QRY_DOCUMENTPARAMS_RECURRING_TRANSACTIONS_EXIST', array($docparKey));
        return ($ret[0]['CNT'] > 0) ? true : false;
    }

    /**
     * Create a schedule if the user has selected ENABLESCHEDULE field
     *
     * @param string $enableschedule
     *
     * @return bool
     */
    private function CreateRecurringSchedule($enableschedule)
    {
        $ok = true;
        global $gManagerFactory;

        $schMgr = $gManagerFactory->getManager('sorecurschedule');

        $result = $schMgr->GetRaw('One Time Creation');

        if (!isset($result[0]) && $enableschedule == 'true') {
            $ok = $ok && $schMgr->CreateOneTimeSchedule();
        }

        return $ok;
    }


    /**
     * Set the latestversionkey field for the transaction definition.
     *
     * @param string $id
     * @param string $versionKey
     *
     * @return bool|string[][]
     */
    private function SetTemplateVersion($id, $versionKey)
    {
        return $this->DoQuery(
            'QRY_DOCUMENTPARAMS_UPDATE_VERSION',
            [$versionKey, $versionKey, $id]
        );
    }

    /**
     * This method updates status with latest to all previous versions
     *
     * @param string $status
     * @param string $docid
     *
     * @return bool
     */
    private function setStatusForAllVersions($status, $docid)
    {
        $fieldInfo = $this->GetFieldInfo('STATUS');
        $valStatus = $this->_TransformValue($status, $fieldInfo['type'], 0);
        $ok = $this->DoQuery('QRY_DOCUMENTPARAMS_UPDATE_TO_LATEST_STATUS', array($valStatus, $docid));
        return $ok;
    }

    /**
     * Set the doctype field of the newly created transaction definition to
     * the dame type as the existing one.
     *
     * @param string $oldVersionKey
     * @param string $newVersionKey
     * @param string $docid
     *
     * @return bool|string[][]
     */
    private function SetDocumentValues($oldVersionKey, $newVersionKey, $docid)
    {
        $ok = $this->DoQuery('QRY_DOCUMENTPARAMS_UPDATE_DOCTYPE', array($oldVersionKey, $newVersionKey));
        $ok = $ok && $this->DoQuery('QRY_DOCRECALLS_UPDATE_TO_LATEST', array($newVersionKey, $oldVersionKey));
        $ok = $ok && $this->DoQuery('QRY_TAXSCHEDMAP_UPDATE_TO_LATEST', array($newVersionKey, $docid));
        $ok = $ok && $this->DoQuery('QRY_SCMMACROHDR_UPDATE_TO_LATEST', array($newVersionKey, $docid));
        $ok = $ok && $this->DoQuery('QRY_SCMMACROENTRY_UPDATE_TO_LATEST', array($newVersionKey, $docid));
        return $ok;
    }

    /**
     * Registers an error if the document with the given id exists in the
     * database and it is marked as the one with the laterstversionkey = true
     *
     * @param string $id
     *
     * @return bool
     */
    private function isDocumentIDUnique($id)
    {
        $ret = true;
        if ($this->DoQuery(
            'QRY_DOCUMENTPARAMS_SELECT_LATEST_FOR_UNIQUENESS_CHECK', array($id))) {
            Globals::$g->gErr->addIAError(
                'INV-0395', __FILE__ . ':' . __LINE__,
                "Transaction Definition for $id already exists.", ['ID' => $id]
            );
            $ret = false;
        }
        return $ret;
    }

    /**
     * Returns true if the transaction definition with the given id exists
     * and false otherwise.
     *
     * @param string $id
     *
     * @return bool
     */
    private function isTrxdefExists($id)
    {
        $result = $this->GetByRecordNo($id);
        return (isset($result));
    }

    /**
     * Returns true (1) if the transaction definition has marked as 'system'
     * and false (0) otherwise.
     *
     * @param string $docparKey
     *
     * @return int
     */
    private function IsSystemDocPar($docparKey)
    {
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_DOCTYPE';
        $ret = $this->DoQuery($qry, array($docparKey));
        return ($ret[0]['DOCTYPE'] != 'U') ? 1 : 0;
    }

    /**
     * check if documentType is valid and valid for the object given
     * @param string $documentType
     * @param string $objectName
     * @return false
     */
    public function isValidDocParId4Object($documentType, $objectName) {
      try {
        $docParamType = $this->getEntityFromDocType($documentType);
        $objectName = strtoupper($objectName);
        if (array_key_exists($objectName, self::objectEntityMap) && self::objectEntityMap[$objectName] == $docParamType) {
          return true;
        }
      } catch ( Exception $e ) {
        return false;
      }
      return false;
    }

    /**
     * Returns the entity of the given document by its type.
     *
     * @param string|null $docType
     * @param string $module
     *
     * @return string
     * @throws IAException
     */
    public function getEntityFromDocType($docType = null, &$module = '')
    {
        if (empty($docType)) {
            throw new IAException(
                "Invalid document type: $docType.");
        }

        $params['selects'] = array("sale_pur_trans");
        $params['filters'] = array(
            array(
                array('latestversionkey', 'IS NULL'),
                array('docid', '=', $docType),
            ),
        );
        $res = $this->GetList($params);
        if ($res && is_string($res[0]['SALE_PUR_TRANS'])) {
            switch ($res[0]['SALE_PUR_TRANS']) {
                case 'Purchase':
                    $entity = 'podocument';
                    $module = 'po';
                    break;
                case 'Sale':
                    $entity = 'sodocument';
                    $module = 'so';
                    break;
                default:
                    $entity = 'invdocument';
                    $module = 'inv';
                    break;
            }
        } else {
            throw new IAException(
                "Entity cannot be resolved for TD with $docType document type.");
        }


        return $entity;
    }

    /**
     * Returns the record number for the active transaction definition - the
     * one with the given docId and latestversionkey is set to null.
     *
     * @param string $docID
     *
     * @return bool|string  record# or false if the record# cannot
     *                      be found.
     */
    public function getLatestVersionKey($docID)
    {
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RECORDNO_FROM_ID';
        $args = array($docID);
        $ret = $this->DoQuery($qry, $args);
        return $ret[0]['RECORD#'];
    }

    /**
     * Queries the active transaction definition (latestversionkey = null)
     * with the given Id.
     *
     * @param string $docparID
     * @param bool $verbose
     * @param bool $cleanCopy
     *
     * @return bool|array
     */
    public function GetLatest($docparID, $verbose = true, $cleanCopy = false)
    {
        if ($cleanCopy || !isset($this->_latestDocpar[$docparID])) {
            $docparkey = $this->getLatestVersionKey($docparID);
            if (!$this->_latestDocpar) {
                $this->_latestDocpar = array();
            }
            $this->_latestDocpar[$docparID] = $this->getVerbose($docparkey, $verbose);
        }
        return $this->_latestDocpar[$docparID];
    }

    /**
     * Query from the database the active record for the transaction
     * definition with the given id.
     *
     * @param string $docparID
     * @param bool $cleanCopy
     *
     * @return array|bool
     */
    public function GetLatestRaw($docparID, $cleanCopy = false)
    {
        if ($cleanCopy || !$this->_latestRaw[$docparID]) {
            $qry = 'QRY_DOCUMENTPARAMS_SELECT_LATEST_RAW';
            if (!$this->_latestRaw) {
                $this->_latestRaw = array();
            }
            $this->_latestRaw[$docparID] = $this->DoQuery($qry, array($docparID));
        }
        return $this->_latestRaw[$docparID];
    }


    //     Returns all versions of a docpar

    /**
     * Query all the versions of the transaction definition with the given id.
     *
     * @param string $docparID
     *
     * @return bool|string[][]
     */
    public function GetAllRaw($docparID)
    {
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_ALL_RAW';
        return $this->DoQuery($qry, array($docparID));
    }

    /**
     * Query all the versions of the transaction definition with the given sales/purchase indicator (S, P, or I).
     *
     * @param string $spi 'S', 'P', or 'I'
     *
     * @return bool|string[][]
     */
    public function GetAllRawBySPI($spi)
    {
        $qry = 'QRY_DOCUMENTPARAMS_SELECT_TYPE_RAW';
        return $this->DoQuery($qry, array($spi));
    }

    /**
     * @param string $docparID
     * @param bool $cleanCopy
     *
     * @return array|false
     */
    public function GetBaseLatest($docparID, $cleanCopy = false)
    {

        if ($cleanCopy || !$this->_latestBaseObject[$docparID]) {
            $docparkey = $this->getLatestVersionKey($docparID);
            if (!$this->_latestBaseObject) {
                $this->_latestBaseObject = array();
            }
            $docpar = $this->BaseGet($docparkey);

            $this->_latestBaseObject[$docparID] = $docpar;
        }
        return $this->_latestBaseObject[$docparID];
    }


    /**
     * Returns a transaction definition by its id.
     *
     * @param string $id
     * @param string[]|null $fields
     *
     * @return array|false
     */
    function BaseGet($id, $fields = null)
    {
        $docpar = parent::BaseGet($id, $fields);
        $this->adjustEntitySpecificProperties($docpar);
        return $docpar;
    }

    /**
     * @return string
     */
    public function getModId()
    {
        return $this->_modID;
    }

    /**
     * Returns true if any of the TD has enable rev rec set to true else false.
     *
     * @return bool
     */
    public static function TDHasEnableRevRec()
    {
        $qry = "select count(ENABLEREVREC) enablerevreccount from docpar where enablerevrec != :1 and latestversionkey is null and cny# = :2";

        $res = QueryResult(array($qry, 'N', GetMyCompany()));

        if ($res[0]['ENABLEREVRECCOUNT'] > 0) {
            return true;
        } else {
            return false;
        }

    }

    /**
     * Returns the list of transaction definitions that can be used to create
     * a new TD with the given doc type.
     *
     * @param string $docType
     *
     * @return bool|string[][]
     */
    public function getRecallDocs($docType)
    {
        $allowedDocs = $this->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($this->spi, 'T', $docType));
        return $allowedDocs;
    }

    /**
     * Returns the formatted list of transaction definitions that can be created from
     * the one with the passed query parameters.
     *
     * @param string[] $qparams
     *
     * @return array|string
     */
    public function GetRecalledDocs($qparams)
    {
        // get all the list of doctypes to which we can convert from the doctype passed as parameter
        global $_userid;

        $doctype = $qparams['doctype'];
        $mod = $qparams['mod'];

        if ($doctype == '') {
            return array();
        }

        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$mod];

        //$docparMgr	= $gManagerFactory->GetManager('documentparams');

        //$allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO',array($spi, $doctype));
        $allowedDocs = $this->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_FROM', array($spi, $doctype));
        $userkey = explode('@', $_userid);
        $userkey = array_shift($userkey);

        $allowedDocs = upermFilterResult($allowedDocs, $userkey);
        $allowedDocs = ($allowedDocs ?: array());
        $allowedDocs = filterDocsForUserType($allowedDocs);


        $xmlAllowedDocs = "";
        foreach ($allowedDocs as $doc) {
            $docid = isl_htmlspecialchars($doc['DOCID']);
            if ($doc['DISCOUNT_ON_EXTENDEDPRICE'] != 'T') {
                $xmlAllowedDocs .= "<alloweddocs docid = \"$docid\" />";
            }
        }

        $xmlStr = "<GetRecalledDocs>" . $xmlAllowedDocs . "</GetRecalledDocs>";
        return $xmlStr;
    }

    /**
     * Returns the list of parameters of the active transaction definition
     * (latestversionkey = null) of a specific type
     *
     * @param string $spi
     *
     * @return string[]
     */
    public function GetDocParsForUIValidation($spi)
    {
        $params['selects'] = array("docid", "docclass", "warnonlowqty", "creditlimitcheck", "locoverride");
        $params['filters'] = array(
            array(
                array('latestversionkey', 'IS NULL'),
                array('sale_pur_trans', '=', $spi),
            ),
        );
        $res = $this->GetList($params);

        $indexedDocPars = [];
        foreach ($res as $value) {
            $indexedDocPars[$value['DOCID']] = $value;
        }

        return $indexedDocPars;
    }

    /**
     * SRAO :: Only sub functions to return this value, based on their module preferences.
     * For now, we maintain only inventory.
     *
     * @param string[] $offsetAccts
     *
     * @param string $option
     *
     * @return string
     */
    function GetOffsetAccountForPosting(&$offsetAccts, /** @noinspection PhpUnusedParameterInspection */ $option = '')
    {
        if (!isset($offsetAccts['OFF_GLACCOUNT']) || $offsetAccts['OFF_GLACCOUNT'] == '') {
            GetModulePreferences($this->_modID, $prefs);
            return $prefs['OFF_GLACCOUNT'];
        } else {
            return $offsetAccts['OFF_GLACCOUNT'];
        }
    }

    /**
     * Returns offset account for GL posting.
     *
     * @param string[] $offsetAccts
     *
     * @return null|string
     */
    function GetOffsetAccountForDirectGLPosting($offsetAccts)
    {
        if (!isset($offsetAccts['DIRECT_GLACCOUNT']) || $offsetAccts['DIRECT_GLACCOUNT'] == '') {
            GetModulePreferences($this->_modID, $prefs);
            $offsetAccts['DIRECT_GLACCOUNT'] = $prefs['DIRECT_GLACCOUNT'];
        }
        return $offsetAccts['DIRECT_GLACCOUNT'];
    }

    /**
     * Default implementation.
     *
     * @param string[] $offsetAccts
     *
     * @return bool
     */
    function GetAccountForGLPosting(/** @noinspection PhpUnusedParameterInspection */ $offsetAccts)
    {
        return true;
    }

    /**
     * Default implementation.
     *
     * @param string[] $offsetAccts
     *
     * @return string
     */
    function GetAccountForSubledgerPosting(/** @noinspection PhpUnusedParameterInspection */ $offsetAccts)
    {
        return '';
    }

    /**
     * @param string[] $offsetAccts
     *
     * @return null|string
     */
    function GetAccountForCOGSPosting($offsetAccts)
    {
        return $offsetAccts['COGSACCTKEY'];
    }

    /**
     * @param string[] $offsetAccts
     *
     * @return null|string
     */
    function GetOffsetAccountForCOGSPosting($offsetAccts)
    {
        return $offsetAccts['INVACCTKEY'];
    }

    /**
     * Note that for inventory this API is overridden. For inventory cases we only have one set of accounts.
     * For SO/PO we have the subledger as well as COGS Postings.
     *
     * @param string[] $offsetAcctsParams
     * @param string[] $itemGLGrp
     *
     * @return bool
     */
    public function SetDocParPostingOffsetAccounts($offsetAcctsParams, $itemGLGrp = array())
    {
        $ok = true;
        global $gManagerFactory;

        //$gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;

        $params['selects'] = array("docid", "docclass", "recordno", "sale_pur_trans", "updates_gl", "updates_inv", "in_out");
        $params['filters'] = array(
            array(
                array('latestversionkey', 'IS NULL'),
                array('status', '=', 'T'),
            ),
        );

        $docpars = $this->GetList($params);

        $offsetAcctsParams['ISPOOE_OFFSET'] = false;

        // the managers are needed for setting the proper offset accounts
        /* @var DocumentParInvGLManager $docParInvGLMgr */
        $docParInvGLMgr = $gManagerFactory->getManager($this->_mod . 'documentparinvgl');
        /* @var DocRecallsManager $docRecallsMgr */
        $docRecallsMgr = $gManagerFactory->getManager($this->_mod . 'docrecalls');

        // We need a different strcuture for subledger postings because the offsetaccounts can change based on the docpar definition and
        // we do not want to disturb the original offsetacct array.
        $subledgeroffsetAccts = array();


        // Prepare a lookup structure based on docparid
        $docParByDocID = array();
        foreach ($docpars as $docpar) {
            $docParByDocID[$docpar['DOCID']] = $docpar;
        }

        // loop through the docpar structure and set the offsets.
        foreach ($docParByDocID as $key => $docpar) {
            $offsetAccts = $offsetAcctsParams;

            // The constants keep changing for various conditions of the docpar so initialize to '' each time. This would make sure we do not carry the previous value.
            $postingAccount = '';
            $offsetAccount = '';
            $postingSign = '';
            $offsetSign = '';

            if ($docpar['UPDATES_GL'] == 'G' || $docpar['UPDATES_GL'] == 'A') {
                // Only SO and PO have transaction posting
                /* @var DocumentParPRGLManager $docParPRGLMgr */
                $docParPRGLMgr = $gManagerFactory->getManager($this->_mod . 'documentparprgl');

                // In case we have a document recall information in the prior chain of the workflow, then the offset accounts
                // change as below. The direct GL posting acct will be the posting account and the offset for posting [modulewise] will be the offset account.
                $docRecalls = $docRecallsMgr->GetAllowedRecallIDs($key);

                if ($docRecalls[0] && $docRecalls[0]['RECDOCPAR'] != '') {
                    $recallDocPar = $docParByDocID[$docRecalls[0]['RECDOCPAR']];
                    if ($recallDocPar && $recallDocPar['UPDATES_GL'] == 'G') {
                        $postingAccount = $this->GetOffsetAccountForDirectGLPosting($offsetAccts);
                        $offsetAccount = $this->GetOffsetAccountForPosting($offsetAccts);
                    }
                }

                // For Default cases, take the subledger account for posting [either from item info or from the setup screen
                if ($postingAccount == '') {
                    $postingAccount = $this->GetAccountForSubledgerPosting($offsetAccts);
                }

                // Offset is [either from item info or from the setup screen
                if ($offsetAccount == '') {
                    $offsetAccount = $this->GetOffsetAccountForPosting($offsetAccts);
                }

                $subledgeroffsetAccts['POSTING_GLACCOUNT'] = $postingAccount;
                $offsetAccts['OFF_GLACCOUNT'] = $offsetAccount;

                // for direct gl posting offset is taken from setup.
                if ($docpar['UPDATES_GL'] == 'G') {
                    $subledgeroffsetAccts['OFF_GLACCOUNT'] = $this->GetOffsetAccountForDirectGLPosting($offsetAccts);
                } else {
                    $subledgeroffsetAccts['OFF_GLACCOUNT'] = $offsetAccts['OFF_GLACCOUNT'];
                    $subledgeroffsetAccts['ISPOOE_OFFSET'] = $offsetAccts['ISPOOE_OFFSET'];
                }


                if ($postingSign == '') {
                    $postingSign = ($docpar["IN_OUT"] == 'Increase') ? 'Debit' : 'Credit';
                }

                if ($offsetSign == '') {
                    $offsetSign = ($docpar["IN_OUT"] == 'Increase') ? 'Credit' : 'Debit';
                }

                $subledgeroffsetAccts['POSTING_SIGN'] = $postingSign;
                $subledgeroffsetAccts['OFFSET_SIGN'] = $offsetSign;

                // First, set for the GL/ Subledger offset preferences.
                $ok = $ok && $docParPRGLMgr->RecreateItemGrpValues($docpar, $subledgeroffsetAccts, $itemGLGrp);
            }


            // Switch to the cogs posting offset preferences.
            if (in_array($docpar['UPDATES_INV'], array('Value', 'Quantity and Value'))) {

                $offsetAccts['POSTING_GLACCOUNT'] = $this->GetAccountForCOGSPosting($offsetAccts);
                $offsetAccts['OFF_GLACCOUNT'] = $this->GetOffsetAccountForCOGSPosting($offsetAccts);

                if ($docpar["IN_OUT"] == 'Increase') {
                    $offsetAccts['POSTING_SIGN'] = 'Credit';
                    $offsetAccts['OFFSET_SIGN'] = 'Debit';
                } else {
                    $offsetAccts['POSTING_SIGN'] = 'Debit';
                    $offsetAccts['OFFSET_SIGN'] = 'Credit';
                }

                // Pass the flag so that the RecreateItemGrpValues will update the values based on this condition.
                $offsetAccts['ISCOGSOFFSET'] = true;

                $ok = $ok && $docParInvGLMgr->RecreateItemGrpValues($docpar, $offsetAccts, $itemGLGrp);
            }

        }
        //dieFL();
        if (!$ok) {
            $msg = "Cannot set the document params offset details ";
            $gErr->addIAError('INV-0511', __FILE__ . ':' . __LINE__, $msg, []);
        }

        return $ok;
    }

    /**
     * Implementation of the processContextClause method for the
     * transaction definition managers.
     *
     * @param array $params
     */
    protected function processContextClause(&$params)
    {
        if (array_key_exists('context', $params)) {
            // we will get something like this:
            // [
            //  0 => [ 'DOCID' = ? ]
            //  1 => [ 'SALESCON' = ? ]
            // ]
            $docid = null;
            $salescon = null;
            foreach ($params['context'] as $filter) {
                if (!is_array($filter)) {
                    continue;
                }
                if ($filter[0] == 'DOCID') {
                    $docid = $filter[2];
                } else if ($filter[0] == 'SALESCON') {
                    $salescon = $filter[2];
                }
            }

            if ($salescon == 'T') {
                $cny = GetMyCompany();
                $subquery = array("
                            SELECT docpar.record#
                            FROM 
                                     docpar, docrecalls, docpar recdpr 
                            WHERE 
                                  docpar.latestversionkey is null 
                                  and docpar.sale_pur_trans = 'S' 
                                  and docpar.status = 'T' 
                                  and docpar.RECORD# = docrecalls.DOCPARKEY (+) 
                                  and docrecalls.RECDOCPARKEY = recdpr.record# 
                                  and recdpr.docid = (select docpar.docid from docpar,dochdr
                                          where 
                                                        docpar.record# = dochdr.docparkey and
                                                            docpar.cny# = $cny 
                                                            and dochdr.cny# = $cny
                                                            and dochdr.docid = '" . $docid . "'" . ")
                                      and recdpr.record# = docrecalls.recdocparkey 
                                      and recdpr.cny# (+) = $cny 
                                      and docpar.cny# = $cny 
                                      and docrecalls.CNY# (+) = $cny"
                );
                $params['filters'][0][] = array('RECORDNO', 'INSUBQUERY', $subquery);
            }
        }
    }

    /**
     * @param array $qparams
     *
     * @return array
     */
    public function getAllDocPars($qparams = null)
    {

        $querySpec = array(
            'selects' => array('RECORDNO', 'DOCID', 'DOCCLASS', 'CATEGORY', 'DESCRIPTION', 'USERPERM', 'PSAIMPORT', 'ENABLEREVREC'),
            'filters' => array(
                array(
                    array('STATUS', '=', 'active'),
                    //array('UPDATES_GL', '!=', 'N'),
                    //array('DOCCLASS', 'IN', array('Invoice', 'Adjustment')),
                    //array('CATEGORY', '=', 'Invoice'),
                )
            ),
        );

        if (isset($qparams['enableMST'])) {
            $querySpec['usemst'] = true;
        }

        //if ( $docClass != '' ) {
        //$querySpec['filters'][0][] = array('', '=', $docClass);
        //}

        $resultSet = $this->GetList($querySpec);

        foreach ($resultSet as &$res) {
            $res['USERPERM'] = ($res['USERPERM'] == 'true' ? 'T' : 'F');
        }

        // filter the result, though intacct user sees everything.
        if (!CheckAuthorization(GetOperationId('inv/activities/document/nofilters'))) {
            $authorizedDocPars = upermFilterResult($resultSet, GetMyUserid());
        } else {
            // hack: "inv/activities/document/nofilters" permission is given
            // for free only to intacct slidein users
            $authorizedDocPars = $resultSet;
        }

        $retArray = array();
        foreach ($authorizedDocPars as $row) {
            $retArray[$row['DOCCLASS']][] = $row;
        }

        // figure out the entry object

        switch ($this->_entity) {
            case 'sodocumentparams' :
                $entryObject = 'sodocumententry';
                break;
            case 'podocumentparams' :
                $entryObject = 'podocumententry';
                break;
            case 'invdocumentparams' :
                $entryObject = 'invdocumententry';
                break;
            default :
                $entryObject = 'documententry';
                break;
        }

        $gManagerFactory = Globals::$g->gManagerFactory;

        foreach ($retArray as $docclass => $docpars) {
            foreach ($docpars as $idx => $row) {
                $docparam =& $retArray[$docclass][$idx];

                // figure out the fields list for entry object
                if (class_lookup($entryObject . 'manager')) {

                    $objMgr = $gManagerFactory->getManager($entryObject, true, array('DOCTYPE' => $row['DOCID']));

                    $columns = $objMgr->getFieldInfoForCustomDocs();

                    $docparam['DOCENTRYFIELDS'] = array();
                    $docentryfields = array();
                    foreach ($columns as $col) {
                        if ($col['fullname'] != '') {
                            $docentryfields[] = array(
                                'FIELDID' => $col['path'],
                                'FIELDTITLE' => $col['fullname']
                            );
                        }
                    }
                    $docparam['DOCENTRYFIELDS'] = $docentryfields;
                }
            }
        }

        return $retArray;
    }

    /**
     * Performs validation of the entity data for the intended API operation.
     * Supported API operations are:
     * - API_CREATE
     * - API_UPDATE
     * - API_DELETE
     * - API_READ
     * If the operation is null the validation is done for completeness
     * and correctness of the entity data.
     *
     * @param array $values
     *
     * @return bool  true if the data is valid for a given operation
     *               and false otherwise
     */
    function API_ValidateEntity(&$values)
    {
        $ok = $this->prepareEntityValues($values);
        if ($ok) {
            $validator = DocumentParamsValidatorFactory::create($this, Operation::CREATE_NEW);
            $ok = $validator->validate($values);
            if (!$ok) {
                global $gErr;
                $msg =
                    "Validation is failed on the entity of a given type - "
                    . $this->_entity;
                $gErr->addIAError('INV-0512', __FILE__ . ':' . __LINE__, $msg, ['ENTITY' => $this->_entity]);
            }
        }
        return $ok;
    }

    /**
     * Implementation of a method for transaction definitions.
     *
     * @param array $object
     * @param array $values
     *
     * @return array
     */
    function API_UpdateMerge(&$object, &$values)
    {
        $finalObject = parent::API_UpdateMerge($object, $values);
        $itemsName = $this->API_GetSetting("ITEMS_ALIAS");
        if (isset($itemsName) && is_array($itemsName)) {
            foreach ($itemsName as &$itemsAlias) {
                $itemsList = &$finalObject[$itemsAlias];
                if (isset($itemsList) && is_array($itemsList)) {
                    foreach ($itemsList as &$items) {
                        if (isset($items) && is_array($items)) {
                            foreach ($items as $key => $item) {
                                if (!is_array($item)) {
                                    unset($items[$key]);
                                }
                            }
                        }
                        unset($items);
                    }
                }
            }
        }

        return $finalObject;
    }

    /**
     * This function is the opposite of API_FormatObject, and allows the
     * subclass to 'untransform' the outbound values in a suitable PHP
     * structure.  The API integration point is responsible for formatting
     * values -- Objects are responsible for formatting structures
     *
     * @param array $values Outbound object structure
     *
     * @return array unformatted structure
     */
    function API_UnformatObject($values)
    {

        //  If the 'ITEMS_ALIAS' is specified, that means that we'll change the items from the
        //   the 'internal' name  that was needed by the particular EntityManager subclass to the external 'alias' name.
        $ownObjects = $this->GetOwnedObjects();
        $itemsAliases = $this->API_GetSetting('ITEMS_ALIAS');
        $itemAliases = $this->API_GetSetting('ITEM_ALIAS');
        $itemsInternals = $this->API_GetSetting('ITEMS_INTERNAL');       // Internal item array name
        for ($i = 0; $i < count($itemsAliases); $i++) {
            $itemsAlias = strtoupper($itemsAliases[$i]);
            $itemAlias = strtoupper($itemAliases[$i]);
            $itemsInternal = strtoupper($itemsInternals[$i]);
            if ($itemsAlias) {
                foreach ($values as $key => $nextObject) {
                    if (isset($values[$key][$itemsInternal])) {
                        $values[$key][$itemsAlias] = $values[$key][$itemsInternal];
                        foreach ($ownObjects as $ownObject) {
                            if ($ownObject['path'] == $itemsInternal) {

                                $values[$key][$itemsAlias][$itemAlias] = $values[$key][$itemsAlias][$ownObject['entity']];
                                if ($values[$key][$itemsAlias][$ownObject['entity']] !== $itemAlias) {
                                    // Remove the original item if the original key
                                    // doesn't match the alias
                                    unset($values[$key][$itemsAlias][$ownObject['entity']]);
                                }
                                break;
                            }
                        }

                        // The item has been copied. Remove the original one
                        // if the keys are different
                        if ($itemsAlias !== $itemsInternal) {
                            unset($values[$key][$itemsInternal]);
                        }
                    }
                }
            }
        }

        //  If given, map internal field names to external ones.
        $this->mapInternalNamesToExternal($values);

        return $values;
    }

    /**
     * Returns the title of the transaction posting GL account mapping
     * table based on TD type and the transaction posting selection.
     *
     * @param array $values
     *
     * @return string
     */
    public function getTrxPostingMappingTableTitle($values)
    {
        $title = 'IA.DOCUMENT_POSTING_ACCOUNT_MAPPING';
        if (isArrayValueProvided($values, 'UPDATES_GL')) {
            if ("G" === $values['UPDATES_GL']) {
                $title = 'IA.TRANSACTION_POSTING_GL_ACCOUNT_MAPPIN';
            } else {
                if ("A" === $values['UPDATES_GL']) {
                    $sectionTitleMap = [
                        'so' => 'IA.TRANSACTION_POSTING_AR_ACCOUNT_MAPPING',
                        'po' => 'IA.TRANSACTION_POSTING_AP_ACCOUNT_MAPPING'
                    ];
                    $title = $sectionTitleMap[$this->_mod];
                }
            }
        }

        return $title;

    }

    /**
     * Compiles the list of transaction definitions with all the additional
     * fields (LEVEL, HIERPATH, PARENTKEY) that is interpreted by the lister
     * as a collection of hierarchical workflows.
     *
     * @param array $tds List of unique transaction definitions
     * @param array $topDownRelations List of relations for each transaction definition
     *
     * @return array
     */
    public function getWorkflows($tds, $topDownRelations)
    {
        $workflows = [];
        // First transform the array of TDs by setting the key of each record
        // to its DOCID
        foreach ($tds as $index => $docpar) {
            $tds[$docpar['DOCID']] = $docpar;
            unset($tds[$index]);
        }

        // Find all the top-down relationship structures where the first
        // element has no parent. It may or may not have any children
        $workflowRoots = $this->getWorkflowRoots($topDownRelations);

        foreach ($workflowRoots as $parentDocId => $record) {
            $workflowRoot = $tds[$parentDocId];
            $workflowRoot['HIERPATH'] = '/' . $record['RECORDNO'];
            $workflowRoot['LEVEL'] = 1;
            $workflowRoot['PARENTKEY'] = null;

            // Initialize the Quantity status and Value status for the WF root
            $quantityEffect = $this->getInventoryControlStatus(
                $workflowRoot['INV_EFFECT'], InventoryTotalProperty::QUANTITY);
            $workflowRoot[InventoryTotalProperty::QUANTITY] = is_null($quantityEffect) ?
                WorkflowInventoryControlStatus::UNDEFIND : $quantityEffect;
            $valueEffect = $this->getInventoryControlStatus(
                $workflowRoot['INV_EFFECT'], InventoryTotalProperty::VALUE);
            $workflowRoot[InventoryTotalProperty::VALUE] = is_null($valueEffect) ?
                WorkflowInventoryControlStatus::UNDEFIND : $valueEffect;

            try {
                // Find the remaining TDs in the workflow
                $workflowLeaves =
                    $this->generateWorkflow($workflowRoot, $record, $topDownRelations, $tds);
                // Add the remaining TDs in the workflow only if there is no
                // exception thrown
                $workflows[] = $workflowRoot;
                foreach ($workflowLeaves as & $workflowLeaf) {
                    $workflows[] = $workflowLeaf;
                    $workflowRoot['isRoot'] = false;
                }
            } catch (TDWorkflowException $e) {
                logFL($e->getMessage());
            }
        }

        $numberOfRecords = count($workflows);
        foreach ($workflows as & $workflow) {
            $workflow['QCNT'] = $numberOfRecords;
            // If for any TD there is an indication of invalid inventory total
            // property prepend the value of INV_EFFECT field with '*'
            if (WorkflowInventoryControlStatus::INVALID === $workflow[InventoryTotalProperty::QUANTITY] ||
                WorkflowInventoryControlStatus::INVALID === $workflow[InventoryTotalProperty::VALUE]) {
                $workflow['INV_EFFECT'] = "* " . $workflow['INV_EFFECT'];
            }
            unset($workflow[InventoryTotalProperty::QUANTITY]);
            unset($workflow[InventoryTotalProperty::VALUE]);
        }
        return $workflows;
    }

    /**
     * Returns the inventory total status (Increases / Decreases) over
     * specific inventory control property (Value / Quantity) based on
     * inventory effect.
     *
     * @param string $inventoryEffect
     * @param string $inventoryTotalProperty
     *
     * @return null|string
     * @throws TDWorkflowException
     */
    private function getInventoryControlStatus($inventoryEffect, $inventoryTotalProperty)
    {
        $retVal = null;
        $itpPosition = strpos($inventoryEffect, $inventoryTotalProperty);
        if ($itpPosition !== false) {
            // Found the property. Now see if it increases / decreases inventory
            if (strpos($inventoryEffect, WorkflowInventoryControlStatus::INCREASE) !== false) {
                $retVal = WorkflowInventoryControlStatus::INCREASE;
            } else if (strpos($inventoryEffect, WorkflowInventoryControlStatus::DECREASE) !== false) {
                $retVal = WorkflowInventoryControlStatus::DECREASE;
            } else {
                throw new TDWorkflowException(
                    "TD is set to affects inventory with no data for increasing or decreasing.");
            }
        }
        return $retVal;
    }

    /**
     * Identifies the list of  relationships (TD with the list of children)
     * each of which considered the single workflow root.
     *
     * @param array $topDownRelations
     *
     * @return array
     */
    private function getWorkflowRoots($topDownRelations)
    {
        // make a copy of the relationship structure
        $workflowRoots = (new ArrayObject($topDownRelations))->getArrayCopy();

        $leaves = [];
        foreach ($topDownRelations as $record) {
            foreach ($record['children'] as $child) {
                if ($record['RECORDNO'] != $child['RECORDNO']) {
                    // Mark the record as a leaf only if it is not
                    // referring to itself
                    $leaves[$child['RECORDNO']] = true;
                }
            }
        }

        // Iterate over the relationship structure and remove the once
        // marked as leaves
        foreach ($topDownRelations as $docId => $record) {
            if (array_key_exists($record['RECORDNO'], $leaves)) {
                unset($workflowRoots[$docId]);
            }
        }

        // Sort by the TD name ignoring case
        uksort($workflowRoots, "strnatcasecmp");

        return $workflowRoots;
    }

    /**
     * Recursive function that generates the workflow for the parent with the
     * given parameters.
     *
     * @param array $parentTd a transaction definition which is
     *                                considered a root for transactions in the
     *                                next level of workflow hierarchy
     * @param array $parentRelations a TD with the list of its direct
     *                                children
     * @param array $topDownRelations full hierarchy of TDs
     * @param array $tds complete list of all TDs
     *
     * @return array
     * @throws TDWorkflowException
     */
    private function generateWorkflow($parentTd, $parentRelations, $topDownRelations, $tds)
    {
        $workflows = [];
        $completedHierarchy = explode('/', substr($parentTd['HIERPATH'], 1));
        $children = $parentRelations['children'];
        foreach ($children as $child) {
            $childDocId = $child['DOCID'];
            $childRecordNo = $child['RECORDNO'];

            // Ignore the child if it is the same as the parent (loop on itself)
            if ($parentTd['RECORDNO'] == $childRecordNo) {
                continue;
            }

            // Ignore the workflow if the child exists anywhere in the hierarchy
            // (handle cyclical loop)
            if (in_array($childRecordNo, $completedHierarchy)) {
                throw new TDWorkflowException(
                    "TDWorkflowException - ignore workflow with the id " . $childRecordNo);
            }

            $childTd = $tds[$childDocId];
            $childTd['HIERPATH'] = $parentTd['HIERPATH'] . '/' . $childRecordNo;
            $childTd['LEVEL'] = $parentTd['LEVEL'] + 1;
            $childTd['PARENTKEY'] = $parentTd['RECORDNO'];

            $childTd[InventoryTotalProperty::VALUE] =
                $this->getTDInventoryControlStatus($parentTd, $childTd, InventoryTotalProperty::VALUE);
            $childTd[InventoryTotalProperty::QUANTITY] =
                $this->getTDInventoryControlStatus($parentTd, $childTd, InventoryTotalProperty::QUANTITY);

            $workflows[] = $childTd;

            $singleRelation = $topDownRelations[$childDocId];
            $grandChildren = $singleRelation['children'];
            if (isset($grandChildren) && is_array($grandChildren)) {
                $descendants = $this->generateWorkflow(
                    $childTd, $topDownRelations[$childDocId], $topDownRelations,
                    $tds);
                foreach ($descendants as $descendant) {
                    $workflows[] = $descendant;
                }
            }
        }
        return $workflows;
    }

    /**
     * Returns the inventory control status for the given TD by comparing it
     * with the one of its parent TD in the workflow.
     *
     * @param array $parentTd
     * @param array $childTd
     * @param string $inventoryTotalProperty Quantity / Value
     *
     * @return null|string
     * @throws TDWorkflowException
     */
    private function getTDInventoryControlStatus($parentTd, $childTd, $inventoryTotalProperty)
    {
        if (WorkflowInventoryControlStatus::IGNORE === $parentTd[$inventoryTotalProperty] ||
            WorkflowInventoryControlStatus::INVALID === $parentTd[$inventoryTotalProperty]) {
            // If the parent TD workflow status is invalid or marked to
            // be ignored set the status for the processing child to ignore
            $retVal = WorkflowInventoryControlStatus::IGNORE;
        } else {
            $childPropertyEffect = $this->getInventoryControlStatus(
                $childTd['INV_EFFECT'], $inventoryTotalProperty);
            if (is_null($childPropertyEffect)) {
                // the status is NOT available for the child; copy it from parent
                $retVal = $parentTd[$inventoryTotalProperty];
            } else {
                // Mark the status as invalid if it is the same for both
                // parent and child.
                $retVal =
                    $childPropertyEffect === $parentTd[$inventoryTotalProperty] ?
                        WorkflowInventoryControlStatus::INVALID :
                        $childPropertyEffect;
            }
        }
        return $retVal;
    }

    /**
     * Takes the array of transaction definitions on the input and returns the
     * list of TDs with corresponding TDs that can be created from it in the
     * following format:
     * DOCID => [
     *           'children' => [
     *                            [DOCID => docid, RECORDNO => recordno]
     *                         ]
     *           'RECORDNO' => recordno
     * ]
     *
     * All the TDs that found in the passed array that have no record in the
     * parent-child relationship table (docrecalls) are appended to the end
     * of the resulting array with no children.
     *
     * @param array $tds
     * @param bool|true $activeOnly
     *
     * @return array
     * @throws Exception
     */
    public function getDocumentParamsRelations($tds, $activeOnly = true)
    {
        /* @var DocRecallsManager $recallManager */
        $recallManager = $this->getRecalsManager();

        $topDownRelations = $recallManager->getTopDownRelations($tds, $activeOnly);

        $tdKeys = [];
        foreach ($topDownRelations as $record) {
            $tdKeys[$record['RECORDNO']] = true;
            foreach ($record['children'] as $child) {
                $tdKeys[$child['RECORDNO']] = true;
            }
        }

        foreach ($tds as $td) {
            if (!array_key_exists($td['RECORDNO'], $tdKeys)) {
                $topDownRelations[$td['DOCID']] = ['children' => [], 'RECORDNO' => $td['RECORDNO']];
            }
        }

        return $topDownRelations;
    }

    /**
     * Returns the list of TDs that the current user is authorised to
     * use for creating the transactions.
     *
     * @param string $mod
     *
     * @return array
     */
    public static function getAuthorizedTDs($mod)
    {
        if (!isset($mod)) {
            throw new InvalidArgumentException(
                __METHOD__ . ": Required mod parameter is not provided.");
        }
        $authorizesTds = [];
        $doclist = GetDocumentMenuList($mod);
        $createOp = GetOperationId($mod . '/activities/' . $mod . 'document/create');
        $viewOp = GetOperationId($mod . '/lists/' . $mod . 'document/view');
        foreach ($doclist as $doc) {
            $docid = $doc['DOCID'];
            if ($docid !== BUILD_KIT && $docid !== DIS_KIT) {
                if ((CheckAuthorization($createOp, 1) || CheckAuthorization($viewOp, 1))) {
                    $authorizesTds[$docid] = $doc;
                }
            }
        }
        return $authorizesTds;
    }

    /**
     * Returns the manager based on entity.
     *
     * @return DocRecallsManager|null
     * @throws Exception
     */
    private function getRecalsManager()
    {
        $recallManager = null;

        $ownedObjects = $this->GetOwnedObjects();
        foreach ($ownedObjects as $key => $ownedObject) {
            if ('DOCPAR_RECALLS' === $ownedObject['path']) {
                $ownedEntity = $ownedObjects[$key]['entity'];
                /** @var DocRecallsManager $recallManager */
                $recallManager =
                    Globals::$g->gManagerFactory->getManager($ownedEntity);
                break;
            }
        }
        if (!isset($recallManager)) {
            throw new IAException("No manager for recall entity!!!");
        }
        return $recallManager;

    }

    /**
     * @param array $values
     *
     * @throws IAException
     */
    public function isDocParUpdatesGL(/** @noinspection PhpUnusedParameterInspection */ $values)
    {
        throw new IAException("Cannot be called on the parent method!");
    }

    /**
     * Query a template type for a td with the given name.
     *
     * @param string $tdName
     *
     * @return string|null
     * @throws IAException
     */
    public function getClass($tdName)
    {
        $params = [
            'selects' => ['DOCCLASS', 'CATEGORY'],
            'filters' => [[['DOCID', '=', $tdName]]],
            'usemst' => true,
        ];
        $td = $this->GetList($params);
        if (!isset($td) || count($td) !== 1) {
            // Throw an error if the TD cannot be found
            throw new IAException("PartnerFieldMapService: Document with the $tdName cannot be identified!!!");
        }

        return $td[0]['DOCCLASS'];
    }


    /**
     * Initialize the User Permissions for this document param record
     *
     * @param array $obj the record so far
     */
    public function initPermissions(&$obj)
    {
        if (!isset($obj['USERPERM']) || 'true' !== $obj['USERPERM']) {
            $obj['USERPERM'] = 'false';
        }

        // Initialize permissions only if there are no permissions for the selected TD
        if (!isset($obj['PERMLIST']) || !is_array($obj['PERMLIST']) || count($obj['PERMLIST']) == 0) {
            $obj['PERMLIST'] = array();
            $fs = new FSEntityManager();
            $templateName = $obj['DOCID'];

            if ($obj['TYPE'] == 'S'
                && !isl_str_startswith(
                    $obj['TITLE'], 'System_'
                )
            ) {
                $templateName = "System_" . $templateName;
            }
            [$gus, $gups] = $fs->GetADVals($templateName);
            if (!empty($gus) && !empty($gups)) {
                for ($i = 0; $i < count($gus); $i++) {
                    if ($gups[$i] == 'A') {
                        $access = 'true';
                        $access2 = 'allow';
                    } else {
                        $access = 'false';
                        $access2 = 'deny';
                    }
                    if (preg_match("/Group\\\\(.*)/", $gus[$i], $parts)) {
                        $gus[$i] = 'Group/' . $parts[1];
                    }


                    $obj['PERMLIST'][$i] = array(
                        'PERMLISTMEMBER' => $gus[$i], 'ALLOWACCESS' => $access,
                        'ALLOWACCESS2' => $access2
                    );
                }
            } else {
                $obj['PERMLIST'][0] = array(
                    'PERMLISTMEMBER' => 'Group/Everyone', 'ALLOWACCESS' => 'true',
                    'ALLOWACCESS2' => 'allow'
                );
            }
        }
    }

    /**
     * @param [] $fields
     * @param string $docId
     */
    function removeCustomListerFields(&$fields, /** @noinspection PhpUnusedParameterInspection */ $docId)
    {
        $addInfoFields = ['ENABLEADDINFOSCOPE', 'ENABLEADDINFOSCHEDULE', 'ENABLEADDINFOINTERNALREF', 'ENABLEADDINFOEXTERNALREF', 'ENABLEADDINFOBOND'];
        if (!CRESetupManager::isCREInstalled()) {
            foreach ($fields as $key => $value) {
                if (in_array($value['path'], $addInfoFields)) {
                    unset($fields[$key]);
                }
            }
        }
    }

    /**
     * @param array $fields
     *
     * @return bool
     */
    function additionalInfoFieldsValidation(&$fields)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $addInfoFields = ['ENABLEADDINFOSCOPE', 'ENABLEADDINFOSCHEDULE', 'ENABLEADDINFOINTERNALREF', 'ENABLEADDINFOEXTERNALREF', 'ENABLEADDINFOBOND'];
        if (!CRESetupManager::isCREInstalled()) {
            foreach ($addInfoFields as $value) {
                if ($fields[$value] && ($fields[$value] == 'true' || $fields[$value] == 'T')) {
                    $gErr->addIAError('INV-0396', __FILE__ . ':' . __LINE__,
                        "Construction subscription required",[],
                        "The $value field are valid only when you have a subscription to Construction.",['VALUE' => $value],
                        "Either remove these fields or subscribe to the Construction application and try again",[]
                    );
                    return false;
                }
            }
        }else{
            if(isset($fields['DOCCLASS']) && !in_array($fields['DOCCLASS'],['Order','Quote'])){
                foreach ($addInfoFields as $value){
                    if($fields[$value] && ($fields[$value] == 'true' || $fields[$value] == 'T' )){
                        $gErr->addIAError('INV-0397', __FILE__ . ':' . __LINE__,
                            "To use $value, document class should be Order or Quote",['VALUE' => $value],
                            '',[],
                           "Either remove these fields or change document class to either Order or Quote and try again", []
                        );
                        return false;
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * Returns the list of names for all transaction definitions specified
     * for top level and all intacct entities.
     *
     * @return string[]
     */
    public function getAllTransactionDefinitionsNames()
    {
        static $tdNames = null;
        if (is_null($tdNames)) {
            $tds = $this->getAllDocparIdFields();
            $tdNames
                = array_map(
                function ($element) {
                    return $element['DOCID'];
                }, $tds
            );
        }
        return $tdNames;
    }

    /**
     * Returns the list of transaction definitions specified for top level
     * and all intacct entities
     *
     * @return array
     */
    public function getAllDocparIdFields($documentName = "")
    {
        static $tds = [];
        if (!isset($tds[$documentName])) {
            $params = [
                'selects' => [ 'DOCID', 'RECORDNO', 'DOCCLASS', 'LOCATIONKEY', 'DEPTKEY' ],
                'orders'  => [ [ 'DOCID' ] ],
                'usemst'  => true,
            ];
            $tds[$documentName] = $this->GetList($params);
        }
        return $tds[$documentName];
    }

    /**
     * Validating API request for CCO TD restricted fields
     *
     * @param string $operation
     * @param mixed  $values
     *
     * @return bool
     */
    public function API_Validate($operation, &$values = null)
    {
        if(is_array($values)) {
            if($operation === "CREATE"){
                $values['ENABLEDOCCHANGE'] =
                    ( isset($values['ENABLEDOCCHANGE']) && ! isNullOrBlank($values['ENABLEDOCCHANGE']) )
                        ? $values['ENABLEDOCCHANGE'] : 'No Change';
            }else{ // update
                if ( isset($values['ENABLEDOCCHANGE']) && isNullOrBlank($values['ENABLEDOCCHANGE']) ) {
                    $values['ENABLEDOCCHANGE'] = "No Change";
                }
            }
            $enableDocChange = $values['ENABLEDOCCHANGE'] ?? 'No Change';
            $allowedValues = [ 'No Change', 'Enable Change', 'Change Order' ];
            if ( ! in_array($enableDocChange, $allowedValues) ) {
                $message =
                    'Invalid value for ENABLEDOCCHANGE. Change Order cannot be enabled for the given values';
                Globals::$g->gErr->addIAError('INV-0465', __FILE__ . ':' . __LINE__, $message, []);
                return false;
            }
            // Before Set method
            if ( $this->isChangeOrderEnabled() && isset($values['ENABLEDOCCHANGE']) && $operation !== "UPDATE"
                 && $values['ENABLEDOCCHANGE'] !== 'No Change'
                 && ( $values['DOCCLASS'] !== "Order" || $values['CATEGORY'] !== "Order" ) ) {
                $message =
                    'Invalid value for ENABLEDOCCHANGE. Change Order cannot be enabled for the given values';
                Globals::$g->gErr->addIAError('INV-0667', __FILE__ . ':' . __LINE__, $message, []);
                return false;
            }
        }

        return parent::API_Validate($operation, $values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function validateTaxCapture($values)
    {
        $ok = true;
        if ( !(TaxSetupManager::isVATEnabled() && DocumentManager::hasTaxSubTotals($values) && $values['UPDATES_GL'] == 'G') ) {
            if ( $values['DISABLEVAT'] == 'true' ) {
                global $gErr;
                $gErr->addIAError(
                    'INV-0062', __FILE__ . ':' . __LINE__,
                    "You cannot disable tax capture because this Transaction definition is either not posting directly to GL or there is no isTax Subtotal line", []
                );
                $ok = false;
            }
        }
        return $ok;
    }

    /**
     * Removing fulfillment TD for Process Transaction functionality
     *
     * @param array $allTransactionDefs
     *
     * @return array
     */
    public function removeFulfillmentbDocuments($allTransactionDefs)
    {
        foreach ($allTransactionDefs as $key => &$transactionDef) {
            $fulfillmentEnabled = $transactionDef['ENABLEFULFILLMENT'] ?? 'F';
            $allocreserveEnabled = $transactionDef['ENABLEALLOCRESERVE'] ?? 'F';
            if ($fulfillmentEnabled === 'T' || $allocreserveEnabled === 'T') {
                unset($allTransactionDefs[$key]);
            }
        }

        return array_values($allTransactionDefs);
    }

    /**
     * @return array
     */
    public function getDBTranslatedFieldsForEditor(): array
    {
        // Translate EXCHRATETYPES.NAME field explicitely in formeditor
        // This is used in podocumentparams and sodocumentparams and documentparams ent
        return ['EXCHRATETYPES.NAME'];
    }

}


/**
 * Class TDWorkflowException
 *
 * Used by the workflow generation process in order to indicate cyclical loop
 * between the TDs in the workflow.
 */
class TDWorkflowException extends Exception
{

}

/**
 * Class WorkflowInventoryControlStatus
 *
 * An abstract class that simulates the enumeration. Used to indicate the status
 * of the Inventory Control property (Value / Quantity) while traversing the
 * workflow from its root to each leaf.
 */
abstract class WorkflowInventoryControlStatus
{
    const UNDEFIND = "Undefined";
    const INCREASE = "Increase";
    const DECREASE = "Decrease";
    const INVALID = "Invalid";
    const IGNORE = "Ignore";
}

/**
 * Class InventoryTotalProperty
 *
 * An abstract class that simulates the enumeration. Used to mark the
 * Inventory Total property - Quantity / Value.
 */
abstract class InventoryTotalProperty
{
    const QUANTITY = "Quantity";
    const VALUE = "Value";
}

/**
 * Class CreationRuleConstants
 *
 * Enumeration with the creation rule constants.
 */
abstract class CreationRuleConstants
{
    const TOP_LEVEL = "Top level";
    const ENTITY = "Entity";
    const TOP_LEVEL_OR_ENTITY = "Top level or Entity";
    const TOP_LEVEL_ONLY = "Top level only";
    const ENTITY_ONLY = "Entity only";
}

/**
 * Class CreationPolicyConstants
 *
 * Enumeration with teh creation policy constants.
 */
abstract class CreationPolicyConstants
{
    const NEW_DOCUMENT_OR_CONVERT = "New document or Convert";
    const CONVERT_ONLY = "Convert only";
}




