<?
import('OwnedObjectManager');
define('DEFAULT_INVPRECISION', 2);


class DocumentEntryManager extends OwnedObjectManager
{
    /**
     * @var string $mod
     */
    var $mod;

    /**
     * @var bool $_ismcpEnabled
     */
    var $_ismcpEnabled;

    /**
     * @var array   $locationCache
     */
    protected $locationCache = [];

    /**
     * @var array   $macroUIFieldInfo
     */
    private $macroUIFieldInfo = array();

    /**
     * @var array   $macroFields
     */
    protected $macroFields = array();

    /** @var int $useGetByParentCacheForID              cache the records from GetByParent() */
    protected $useGetByParentCacheForID = -1;       // -1 means 'DONT use the cache'

    /** @var array $getByParentCache                    if the above is set, use this, else don't */
    protected $getByParentCache = null;



    /**
     * @param array $params
     */
    function __construct($params=array())
    {
        $this->_docType = $params['DOCTYPE'] ?? '';   // PHP 7.1 note: DEFINED IN EntityManager; Not a dynamic field
        $this->mod = $params['_mod'] ?? '';
        if ($this->mod == '') {
            $this->mod = Request::$r->_mod;
        }

        parent::__construct($params);

        $this->_ismcpEnabled = IsMCPEnabled($this->mod);
        if($this->_ismcpEnabled) {
            $CurrencyFormatFourteenDec = '/^-{0,1}[0-9]*\.{0,1}[0-9]{0,14}$/';

            foreach($this->_schemas[$this->_entity]['basefieldinfo'] as $key => $fldinfo){
                // change the format for UIVALUE & VALUE fields to allow upto 14 decimal places.
                if($fldinfo['path'] === 'UIVALUE' || $fldinfo['path']==='TOTAL') {
                    $this->_schemas[$this->_entity]['basefieldinfo'][$key]['type']['format'] = $CurrencyFormatFourteenDec;
                }
            }
        }
    }

    /**
     * Get the doctype for this document.
     *
     * @return  string
     */
    function getDocType()
    {
        return $this->_docType;
    }

    /**
     * Figure out if the document is a draft document
     *
     * @param array $values the transaction data
     *
     * @return bool true if the document is a draft else false
     */
    protected function isDraftDocument($values)
    {
        return (in_array(($values['DOCSTATE'] ?? ''), [DocumentManager::DRAFT_STATE, DocumentManager::ANALYZING_STATE]));
    }


    /**
     * @param string      $verb
     * @param string      $key
     * @param null|string $param1
     * @param null|string $param2
     * @param array       $values
     *
     * @param bool        $fastUpdate
     *
     * @return bool
     */
    function DoEvent($verb, $key, $param1 = null, $param2 = null, $values = [], $fastUpdate = false)
    {
        // Pass DOCPARID to IMSSubscription so that the $obj has it for SmartEvent processing
        $subStateCache = $this->getSubstateCache();
        $subStateCache['DOCPARID'] = $this->getDocType();
        $this->setSubstateCache($subStateCache);

        if ($this->isDraftDocument($values)
            && FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_POMATCH')
            && POSetupManager::isPOMatchEnabled()) {
            return true;
        }

        return parent::DoEvent($verb, $key, $param1, $param2, $values, $fastUpdate);
    }


    /**
     * Validate record
     *
     * @param array &$values Array of values
     *
     * @return bool true if valid
     */
    protected function ValidateRecord(&$values)
    {
        $ok = parent::ValidateRecord($values);
        global $gErr;

        if ($ok) {
            $trx_totalvalue = (!isNullOrBlank($values['TRX_REVISEDVALUE']) &&  !empty($values['TRX_REVISEDVALUE'])  ) ? $values['TRX_REVISEDVALUE'] : $values['TRX_VALUE'];
            // Validate retainage fields
            if (abs((float)$values['TRX_AMOUNTRETAINED']) > abs($trx_totalvalue)) {
                $ok = false;
                $gErr->addIAError(
                    'INV-0013', GetFL(),
                    "TRX_AMOUNTRETAINED must not be greater than TRX_VALUE.", [] /**/
                );
            }

            // Validate retainage fields
            if ($ok
                && (float)$values['TRX_AMOUNTRETAINED'] != 0
                && (((float)$values['TRX_AMOUNTRETAINED'] <= 0) != ($trx_totalvalue <= 0))
            ) {
                $ok = false;
                $gErr->addIAError(
                    'INV-0014', GetFL(),
                    "TRX_AMOUNTRETAINED can not be negative unless TRX_VALUE is negative.", []
                );
            }
        }

            return $ok;
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
        $ok = parent::API_ValidateObject($newValues, $existingValues);

        if (!isNullOrBlank($newValues['TRX_AMOUNTRETAINED'])) {
            //Calculate Retainage Percentage if necessary.
            $calculatedRetained = 0;
            if (!isNullOrBlank($newValues['RETAINAGEPERCENTAGE'])) {
                $calculatedRetained = ibcdiv(ibcmul($existingValues['TRX_VALUE'], $newValues['RETAINAGEPERCENTAGE'], 2), '100', 2, true);
            }
            else {
                $newValues['RETAINAGEPERCENTAGE'] = 0;
            }
            if ($calculatedRetained != $newValues['TRX_AMOUNTRETAINED']) {
                $newValues['RETAINAGEPERCENTAGE'] = ibcmul(ibcdiv($newValues['TRX_AMOUNTRETAINED'], $existingValues['TRX_VALUE'], 4, true), '100', 2, true);
            }
        }
        else if (isNullOrBlank($newValues['TRX_AMOUNTRETAINED']) && !isNullOrBlank($newValues['RETAINAGEPERCENTAGE'])) {
            // If only RetainagePercentage is specified, calculate amount retained.
            $newValues['TRX_AMOUNTRETAINED'] = ibcdiv(ibcmul($existingValues['TRX_VALUE'], $newValues['RETAINAGEPERCENTAGE'], 2), '100', 2, true);
        }

        return $ok;
    }


    /**
     * API entry point for the Add method.  This is intended for callers other than the intacct UI.
     * Entity Manager sub classes should implement data translation and mapping logic here.  However,
     * the goal should be to keep this function as light weight as possible.
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Add(&$values)
    {
        // Set default Conversion type in the case when Document Entry is created in isolation via the API.
        // (Either SODOCUMENTENTRY or PODOCUMENTENTRY.)
        if (isNullOrBlank($values['CONVERSIONTYPE'])) {
            $values['CONVERSIONTYPE'] = 'Quantity';
        }

        return parent::API_Add($values);
    }


    /**
     * @param array $values
     * @return bool
     * @throws Exception
     */
    function TranslateRecord(&$values)
    {
        if ($values['PROJECTID'] != null && $values['TASKID'] != null && $values['TASKKEY'] == null) {
            $taskManager = $this->GetManager('task');

            $params = array(
                'selects' => array('RECORDNO'),
                'filters' => array(
                    array(
                        array('PROJECTID', '=', $values['PROJECTID']),
                        array('TASKID', '=', $values['TASKID']),
                    )
                ),
            );

            $values['TASKKEY'] = $taskManager->GetList($params)[0]['RECORDNO'];
        }

        return parent::TranslateRecord($values);
    }


    /**
     * @param string $column
     * @param array|null  $values
     *
     * @return bool
     */
    final public function PurgeCustomFieldColumn($column, $values = null)
    {
        $qry = "
			update docentrymst set $column = null where cny# = :1 and record# in (
				select e.record# from docentrymst e, dochdrmst d, docpar p where 
				e.dochdrkey = d.record# and d.docparkey = p.record# and p.docid = :2
				and e.cny# = :1 and d.cny# = :1 and p.cny# = :1 
			) and ";
        $qry = array($qry, GetMyCompany(), $this->_docType);
        if ( ! $values ) {
            $qry[0] .= "$column is not null";
        } else {
            $qry = PrepINClauseStmt($qry, $values, " $column ");
        }
        // Must purge recurring documents as well. This is an ugly hack
        // Long term task: refactor RecurDocumentEntryManager to not be a sub-class of DocumentEntryManager
        return (RecurDocumentEntryManager::PurgeCustomFieldColumn_static($column, $this->_docType, $values)
            && ExecStmt($qry));
    }


    /**
     * Determine how many records have the specified values for a custom field
     *
     * @param string $column  the custom field column name
     * @param array  $values  the values to look for
     *
     * @return int  the cound of records found matching the specified values
     */
    public function countForCustomFieldColumnValues($column, $values)
    {
        $qry = "select count(1) cnt from docentrymst where cny# = :1 and record# in (
				select e.record# from docentrymst e, dochdrmst d, docpar p where 
				e.dochdrkey = d.record# and d.docparkey = p.record# and p.docid = :2
				and e.cny# = :1 and d.cny# = :1 and p.cny# = :1 
			) and ";
        $qry = array($qry, GetMyCompany(), $this->_docType);
        $qry = PrepINClauseStmt($qry, $values, "$column ");
        $res = QueryResult($qry);
        if ( is_array($res) && array_key_exists(0, $res) ) {
            return $res[0]['CNT'];
        }

        return 0;
    }


    /**
     *      use Cache For DocHdr  - when calling GetByParent(), keep a cache for the passed-in doc hdr record#.
     *              if no parameter is passed then it means "DO NOT CACHE", which is the default state.
     *
     *
     * @param int $ID           Optional; the DocHdr# to cache
     */
    public function useCacheForDocHdr( $ID = -1 )
    {
        if ($this->useGetByParentCacheForID != $ID) {
            $this->getByParentCache         = null;     // invalidate the cache
            $this->useGetByParentCacheForID = $ID;      // and set it to this docHdr record #
        }
    }


    /**
     *      flush Cache For DocHdr - reset the cache so the next time someone calls getByParent(), it
     *                  reads a fresh set of records.
     */
    public function flushCacheForDocHdr()
    {
        $this->getByParentCache         = null;     // invalidate the cache
    }


    /**
     * @param string $ID
     *
     * @return array|false
     * @throws Exception
     */
    function GetByParent($ID)
    {
        // Are we using a cache for this?
        if (($this->useGetByParentCacheForID == $ID) &&
            ($this->getByParentCache !== null)) {
            return $this->getByParentCache;
        }

        $objs = parent::getByParent($ID);

        if ($objs !== false) {
            for ( $i = 0; $i < count($objs ?? []); $i++ ) {
                if (!empty($objs[$i]['LOCATIONKEY'] ?? '')) {
                    $objs[$i]['LOCATION'] = $objs[$i]['LOCATIONID'] . '--' . $objs[$i]['LOCATIONNAME'];
                }
                if (!empty($objs[$i]['DEPTKEY'] ?? '')) {
                    $objs[$i]['DEPARTMENT'] = $objs[$i]['DEPARTMENTID'] . '--' . $objs[$i]['DEPARTMENTNAME'];
                }

                if (!empty($objs[$i]['SC_EXISTINGSCHED'] ?? '')) {
                    $objs[$i]['SC_EXISTINGSCHED'] = $objs[$i]['SC_EXISTINGSCHED'] . '--' . $objs[$i]['RECURCONTRACTID'];
                }
                $this->TransformDimensionValues($objs[$i], $nullObj, true);
            }

            // Are we cacheing these?
            if ( $this->useGetByParentCacheForID == $ID ) {
                $this->getByParentCache = $objs;
            }
        }
        return $objs;
    }


    /**
     * !!!!!!!!!!!! KLUGE ALERT !!!!!!!!!!!!
     *
     * OVERRIDE THIS FUNCTION BECAUSE WE ALREADY HAVE A WHENCREATED COLUMN IN THE DOCENTRY TABLE
     * THAT WE CANNOT TOUCH. FOR NOW JUST UPDATE WHENMODIFIED
     *
     * @param array  &$values object or entity information in the form of array
     * @param string $action  the action ( add / set / delete )
     */
    protected function updateAuditColumns(&$values, $action)
    {
        // Update audit specific info only when object has specific audit columns
        if ( $this->hasAuditColumns() ) {

            $currentTime = GetTimestampGMT(); // Get current sysdate with time
            // irrespective of creating or updating object, always set modified time
            $values[':whenmodified'] = $currentTime;
        }
    }

    /**
     * @param string    $entity
     *
     * @return EntityManager
     * @throws Exception
     */
    function GetManager($entity)
    {
        $entManager = Globals::$g->gManagerFactory->getManager($entity, false, ['DOCTYPE' => $this->_docType]);
        return $entManager;
    }


    /**
     * @return bool
     */
    function ExistCustomFields()
    {

        $entity = $this->_entity;
        $doctype = $this->_docType;

        return $this->HasCustomFields($entity, $doctype);

    }


    /**
     * @return bool
     */
    function ExistSmartLinks()
    {

        $entity = $this->_entity;
        $doctype = $this->_docType;

        return $this->HasSmartLinks($entity, $doctype);

    }

    /**
     * @return bool
     */
    protected function needToMergeQueries()
    {
        if (!empty($this->macroFields)) {
            return true;
        }

        return parent::needToMergeQueries();
    }

    /**
     * @return array
     */
    public function getMacroFieldInfo()
    {
        return $this->macroUIFieldInfo;
    }

    /**
     * @return array
     */
    public function getMacroNames()
    {
        $names = array();
        foreach ($this->macroFields as $field) {
            $names[] = $field['name'];
        }

        return $names;
    }

    /**
     * @return array
     */
    public function getMacroPaths()
    {
        $paths = array();
        foreach ($this->macroFields as $field) {
            $paths[] = $field['path'];
        }

        return $paths;
    }

    /**
     *
     */
    public function MergeObjectFieldList()
    {
        parent::MergeObjectFieldList();

        if (!empty($this->macroFields)) {
            $schemaobject = &$this->_schemas[$this->_entity]['object'];
            $publish = &$this->_schemas[$this->_entity]['publish'];

            foreach ($this->macroFields as $macroField) {
                if (SCMMacroManager::hasMacroLinkFieldInDB($macroField['name'])) {
                    $schemaobject[] = $macroField['path'];
                    $publish[] = $macroField['path'];
                }
            }
            $schemaobject[] = "SCMMACROLINK";
            $api = &$this->_schemas[$this->_entity]['api'];
            $api['LESS_GET_FIELDS'][] = "SCMMACROLINK";
        }
    }

    /**
     * @param int $cny
     * @param string $entity
     * @param string $module
     * @param bool   $followgldimensions
     * @param array   $ignoreList
     *
     * @return array|bool
     */
    public static function LoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList)
    {
        $newDims = parent::LoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList);

        if (isset($newDims) && isset($newDims['task'])) {
            $newDims['task']['dimfieldid'] = 'taskkey';
            $newDims['task']['dimdbkey'] = 'TASKKEY';
            $newDims['task']['object_relation']['fkey'] = 'taskkey';
        }

        return $newDims;
    }

    /**
     * @param int $cny
     * @param string $entity
     * @param string $module
     * @param bool   $followgldimensions
     * @param array   $ignoreList
     *
     * @return array|bool
     */
    public static function DefaultLoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList)
    {
        return parent::LoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList);
    }

    public function MergeObjectSchema()
    {
        parent::MergeObjectSchema();

        if (!empty($this->macroFields)) {
            $schema = &$this->_schemas[$this->_entity]['schema'];
            foreach ($this->macroFields as $macroField) {
                if (SCMMacroManager::hasMacroLinkFieldInDB($macroField['name'])) {
                    $schema[$macroField['path']] = strtolower($macroField['path']);
                }
            }
            $schema['SCMMACROLINK'] = "state";
        }
    }

    /**
     * The default behavior for DocumentEntryManager is to use TASKKEY instead of TASKDIMKEY.  However, RecurDocumentEntry uses TASKDIMKEY.
     *
     * @return bool
     */
    protected function ShouldUseTASKKEY()
    {
        return true;
    }

    function MergeSchemaChildren()
    {
        parent::MergeSchemaChildren();

        if ($this->ShouldUseTASKKEY()) {
            // Fix Task Dimension to use TASKKEY instead of the default TASKDIMKEY (since the document entities had TASKKEY before Task was a dimension.)
            if (isset($this->_schemas[$this->_entity]['children']['task'])) {
                $this->_schemas[$this->_entity]['children']['task']['fkey'] = 'taskkey';
                if (!empty($this->_schemas[$this->_entity]['schema']['TASKDIMKEY'])) {
                    unset ($this->_schemas[$this->_entity]['schema']['TASKDIMKEY']);
                    $this->_schemas[$this->_entity]['schema']['TASKKEY'] = 'taskkey';
                }
            }
        }
    }

    /**
     * @return array
     */
    protected function getMacroFields()
    {
        global $gBooleanType;
        $fields = array();

        foreach ($this->macroFields as $key => $macroField) {
            $fields[] = array(
                'fullname' => $macroField['name'],
                'type' => $gBooleanType,
                'default' => 'false',
                'desc' => $macroField['name'],
                'path' => $macroField['path'],
                'events' => $macroField['events'],
                'macroField' => true,
                'id' => 1000+$key
            );
        }

        return $fields;
    }

    /**
     *
     */
    function MergeTableInfo()
    {
        parent::MergeTableInfo();

        $table = $this->_schemas[$this->_entity]['table'];
        $dbfieldinfo = &$this->tables[$table]['db_fieldinfo'];

        foreach ($this->macroFields as $macroField) {
            if (SCMMacroManager::hasMacroLinkFieldInDB($macroField['name'])) {
                $dbfieldinfo[strtolower($macroField['path'])] = ['type' => 'text'];
            }
        }
    }

    public function MergeFieldInfo()
    {
        parent::MergeFieldInfo();

        if ($this->ShouldUseTASKKEY()) {
            // Fix Task Dimension to use TASKKEY instead of the default TASKDIMKEY (since the document entities had TASKKEY before Task was a dimension.)
            if (isset($this->dimFields['task'])) {
                $this->dimFields['task']['dimfieldid'] = 'taskkey';
                $this->dimFields['task']['dimdbkey'] = 'TASKKEY';
                $this->dimFields['task']['object_relation']['fkey'] = 'taskkey';
            }
        }

        $this->macroUIFieldInfo = array();

        if (!empty($this->macroFields)) {

            $fieldInfo = &$this->_schemas[$this->_entity]['fieldinfo'];
            $baseFieldInfo = &$this->_schemas[$this->_entity]['basefieldinfo'];

            $macroFields = $this->getMacroFields();

            foreach ($macroFields as $macroField) {
                $fieldInfo[] = $macroField;
                $baseFieldInfo[] = $macroField;
                $this->macroUIFieldInfo[] = $macroField;
            }

            $macroLinkField = array(
                'fullname' => $this->macroFields[0]['name'].' link',
                'hidden'  => true,
                'readonly' => true,
                'path' => 'SCMMACROLINK',
                'formula' => array(
                    'typeOf' => 'STATE',
                    'fields' => array(
                        'CNY#',
                        'RECORDNO',
                    ),
                    'function' => "
                            case when (
                                select 1 from scmmacroresolve scmr
                                where scmr.cny# = \${1} and scmr.sourcedocentrykey = \${2} and rownum = 1
                            ) > 0 then 'T' else 'F' end",
                ),
                'calculated' => true,
                'macroField' => true,
            );

            $fieldInfo[] = $macroLinkField;
            $baseFieldInfo[] = $macroFields[0];
            $this->macroUIFieldInfo[] = $macroLinkField;
        }
    }

    public function LoadMacroFields()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $scmMacroMgr =  $gManagerFactory->getManager('scmmacro');
        $this->macroFields = array();
        $docType = $this->_docType;

        if (empty($docType)) {
            return;
        }

        $params = array(
            'selects' => array('RECORDNO', 'NAME', 'TARGETDOCFROM'),
            'filters' => array(
                array(
                    array('SOURCEDOCPARID', '=', $docType),
                    array('PRIORVERSIONKEY', 'ISNULL'),
                )
            ),
        );

        $recs = $scmMacroMgr->GetList($params);

        if (!empty($recs)) {
            foreach ($recs as $rec) {
                if (!empty($rec['RECORDNO'])) {
                    if ($rec['TARGETDOCFROM'] == 'entries') {
                        $this->macroFields[] = SCMMacroManager::getMacroFields($rec['NAME']);
                    }
                }
            }
        }

    }

    /**
     * @param int  $cny
     * @param bool $withLookup
     */
    function LoadCustomFields($cny = 0, $withLookup = true)
    {
        //load macro fields
        $this->LoadMacroFields();

        ////////////////////////////////////////////////////////////////////////////////
        // GET ALL THE FIELDS FROM THE DB
        ////////////////////////////////////////////////////////////////////////////////

        if ($cny == 0) {
            $cny = (int)GetMyCompany();
        }

        $queryArr = array('', $cny, $this->_entity, 'T', $cny, getUserLocale());
        $doctypeClause= '';

        if ( isl_strlen($this->_docType) > 0 ) {
            if ( $this->_docType !== '%' ) {
                //$doctypeClause = " and '#~#'||cf.DOCTYPE||'#~#' like '%#~#'||:4||'#~#%' ";
                $doctypeClause = " and :6||cf.DOCTYPE||:6 like :7 ";
                $queryArr[] = '#~#';//:6
                $queryArr[] = '%#~#' .$this->_docType . '#~#%';//:7
            }

            $idx = count($queryArr);
            if ( !$withLookup ) {
                $idx2 = $idx + 1;
                $lookupClause = " AND cf.TYPE != :$idx AND cf.TYPE != :$idx2 ";
                $queryArr[] = CUSTOMERP_RELATIONSHIPFIELDTYPE;
                $queryArr[] = CUSTOMERP_RELATIONSHIPFIELDTYPE_DIMENSION;
            } else {
                $lookupClause = " AND cf.TYPE != :$idx ";
                $queryArr[] = CUSTOMERP_RELATIONSHIPFIELDTYPE;
            }

            $qry = "
					select cf.RECORD# as RECORDNO, cf.CUSTOMFIELDID, cf.TYPE, cf.OBJECTFIELDID, cf.DATA DATADESCRIPTION, cf.REQUIRED, cf.PACKAGEKEY,
					cf.DESCRIPTION, cc.RECORD# as CUSTOMCOMPONENTKEY,
					cc.COMPONENTTYPE, cc.PATH, cc.LABEL as OLABEL, cc.HIDDEN, cc.CUSTOMLABELID, cf.DOCTYPE, cl.LABEL
					from CUSTOMFIELD cf, CUSTOMCOMPONENT cc, CUSTOMLABEL cl 
					where cf.RECORD# = cc.CUSTOMFIELDKEY 
					and cf.CNY# = :1 
					and cc.CNY# = :1 
					and cf.OWNEROBJECT = :2 
					$doctypeClause
					$lookupClause
					and cf.ACTIVE = :3
                    and cl.cny#(+) = :4
                    and cl.locale(+) = :5
                    and cl.id(+) = cc.customlabelid                
					order by to_number(substr(cf.OBJECTFIELDID,10))
				";

            $queryArr[0] = $qry;

            $res = QueryResult($queryArr);

            ////////////////////////////////////////////////////////////////////////////////
            // INSTANTIATE AN OBJECT FOR EACH RECORD
            ////////////////////////////////////////////////////////////////////////////////

            if ($res === false) {
                return;
            }
            foreach ( $res as $object ) {
                if ( isset($object['DATADESCRIPTION']) ) {
                    $object['DATADESCRIPTION'] = databaseStringUncompress($object['DATADESCRIPTION']);
                }
                if (empty($object['LABEL'])) {
                    $object['LABEL'] = $object['OLABEL'];
                }
                // CREATE A CLASS INSTANCE
                $classname = "CustomField" . isl_ucfirst(isl_strtolower($object['TYPE']));
                import($classname);
                /**
                 * @var  CustomField $class
                 */
                $class = new $classname($object);

                //  If there is a previous custom field with the same id, remember the doctype.
                $prevDocType = '';
                if ( isset($this->customFields[$object['CUSTOMFIELDID']]) ) {
                    $prevObj = $this->customFields[$object['CUSTOMFIELDID']];
                    $prevDocType = $prevObj->GetRawObjField('DOCTYPE');
                }

                // ADD TO THE ARRAY
                $this->customFields[$object['CUSTOMFIELDID']] = $class;

                //  Figure the custom field index (i.e. 'custfield1' to '1').
                $this->_SearchExtractCustomFieldInfo($object['OBJECTFIELDID'], $cfNum, $cfAlias);

                //  Merge the new doc type with any previous doc types, and set that array as the 'DOCTYPE' raw value.
                if ( $prevDocType === '' ) {
                    $docArray = [ $class->GetRawObjField('DOCTYPE') => $cfNum ];
                } else {
                    if ( !is_array($prevDocType) ) {
                        $prevDocType = [ $prevDocType ];
                    }
                    $docArray = array_merge( $prevDocType, [ $class->GetRawObjField('DOCTYPE') => $cfNum ]);
                }
                $class->SetRawObjField('DOCTYPE', $docArray);
            }
        }
    }


    ////////////////////
    //   SearchGetCustomFieldCalc
    //    This function returns the calculation needed for a custom field value as it is added to
    //   a search summary.  The information returned by this function determines if additional processing
    //   of the custom field value is needed and, if so, the metadata for that calculation.
    /**
     * @param string $custFieldName
     *
     * @return array
     */
    function SearchGetCustomFieldCalc($custFieldName)
    {

        //  DocumentEntryManager custom fields are dependant on their doctype.  A custom field only
        //   makes sense if the rows doctype matches the custom field doctype.  So, pass metadata
        //   that will be interpreted by Global Search to do this matching.
        $obj = $this->customFields[$custFieldName];
        $doctype = $obj->GetRawObjField('DOCTYPE');
        // in documententry.ent, DOCPARID = docparameter.docid, where docparameter refers to table docpar
        return array('DOCPARID', '==', $doctype);
    }

    /**
     * @param string $entity
     * @param string $doctype
     *
     * @return bool
     */
    function HasCustomFields($entity, $doctype)
    {

        // If no ownerobject specified, return
        if (!isset($entity) || $entity == '') {
            return false;
        }

        // If this is a global object, there are no custom fields, return
        if ( !EntityManager::isCompanySchema($entity)) {
            return false;
        }

        // If entity not in global map, return
        global $gCustomFieldMap;
        if ( !is_array($gCustomFieldMap) || !in_array($entity, $gCustomFieldMap) ) {
            return false;
        }

        $lookup = $entity.'--'.$doctype;
        // Check in cache for existence of customfields for this entity
        global $disableCustomERPCache;
        if(!$disableCustomERPCache) {

            $custFld = Profile::getCompanyCacheProperty('CUSTOMFIELDS');
            if ( is_array($custFld) ) {
                if ( in_array($lookup, $custFld) ) {
                    return true;
                }
                return false;
            }
        }

        // If somehow we reach this point, use DB query to find out
        $qry = "select count(*) as COUNT from CUSTOMFIELD where cny# = :1 and OWNEROBJECT = :2 and '#~#'||DOCTYPE||'#~#' like '%#~#'||:3||'#~#%' ";
        $res = QueryResult(array($qry, GetMyCompany(), $entity, $doctype));
        return ($res[0]['COUNT'] > 0);

    }


    /**
     * @param string     $entity
     * @param string    $doctype
     *
     * @return bool
     */
    function HasSmartLinks($entity, $doctype)
    {

        // If no ownerobject specified, return
        if (!isset($entity) || $entity == '') {
            return false;
        }

        // If this is a global object, there are no smart links, return
        if ( !EntityManager::isCompanySchema($entity)) {
            return false;
        }

        // If entity not in global map, return
        global $gSmartLinkMap;
        if ( ! isset($gSmartLinkMap) || ! is_array($gSmartLinkMap) || !in_array($entity, $gSmartLinkMap) ) {
            return false;
        }

        $lookup = $entity.'--'.$doctype;

        // Check in cache for existence of smartlinks for this entity
        global $disableCustomERPCache;
        if(!$disableCustomERPCache) {

            $smartLnk = Profile::getCompanyCacheProperty('SMARTLINKS');
            if ( is_array($smartLnk) ) {
                if ( in_array($lookup, $smartLnk) ) {
                    return true;
                }
                return false;
            }
        }

        // If somehow we reach this point, use DB query to find out
        $qry = "select count(*) as COUNT from SMARTLINK where cny# = :1 and OWNEROBJECT = :2 and '#~#'||DOCTYPE||'#~#' like '%#~#'||:3||'#~#%' ";
        $res = QueryResult(array($qry, GetMyCompany(), $entity, $doctype));
        return ($res[0]['COUNT'] > 0);

    }


    /**
     * @param null|array $types
     * @param bool $showInactive
     *
     * @return bool
     */
    function LoadSmartlinks($types=null, $showInactive=false)
    {
        if ($types == null) {
            $types = self::$defaultLinkTypes;
        }

        $typesNotLoaded = [];
        $showInactiveStr = $showInactive ? 'T' : 'F';
        foreach ( $types as $type ) {
            if (!isset($this->loadedSmartLinkTypes[$type][$showInactiveStr])) {
                $typesNotLoaded[] = $type;
                $this->loadedSmartLinkTypes[$type][$showInactiveStr] = true;
            }
        }

        if ( empty($typesNotLoaded) ) {
            return true;
        }

        //$keyfield = Request::PathToFieldName($this->_schemas[$this->_entity]['vid']);
        $keyfield = $this->_schemas[$this->_entity]['vid'];
 
        $qry = "select sl.RECORD#, sl.SMARTLINKID, sl.TYPE 
				from smartlink sl 
				where sl.ownerobject = :1
				and '#~#'||sl.doctype||'#~#' like '%#~#'||:3||'#~#%'
				and sl.cny# = :2";
        $stmt = [ $qry, $this->_entity, GetMyCompany(), $this->_docType ];
        if (!$showInactive) {
            /** @noinspection PhpUnusedLocalVariableInspection - $qry is updated by reference */
            $stmt[0] .= " and sl.active = :4";
            $stmt[] = 'T';
        }
        $stmt = PrepINClauseStmt($stmt, $types, ' and sl.type');

        $ret = QueryResult($stmt);

        foreach($ret as $smartlinkraw) {
            // CREATE THE CLASS INSTANCE
            $classname = self::$linkTypes[$smartlinkraw['TYPE']];
            $includefile = $classname . ".cls";
            include_once $includefile;

            $class = new $classname($smartlinkraw['RECORD#'], $keyfield);

            // ADD TO THE SMART LINKS ARRAY
            $this->smartLinks[$smartlinkraw['SMARTLINKID']] = $class;
        }

        return true;
    }

    /**
     *
     * This function validates the values against all the smartlinks
     *** Input - array of actions, values in the object.
     *** returns true or false
     */
    /**
     * @param array $actions
     * @param array $values
     * @param bool  $fromFastUpdate
     *
     * @return bool
     */
    function smartlinkValidate($actions, $values, $fromFastUpdate = false)
    {

        // we need to skip the smart rules for Draft document
        if ($this->isDraftDocument($values)
            && FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('ENABLE_POMATCH')
            && POSetupManager::isPOMatchEnabled()) {
            return true;
        }

        //While updating source document, during the deletion of change document skip the smart rules validation for source document
        $isChangeDocEnabled = Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled();
        if($isChangeDocEnabled && PODocumentEntryManager::$isFeedFromSystem === true){
            return true;
        }

        $allDimProperties = IADimensions::getAllDimensionObjectProperties();
        foreach($allDimProperties as $dimension){
            if(is_array($dimension['dependent_dimension_relationship'])){
                $parentDimID = $dimension['dependent_dimension_relationship']['parent'];
                if(isset($parentDimID)) {
                    if(isset($values[$dimension['path']]) && !empty($values[$dimension['path']])) {
                        $values[$dimension['path']] =
                            $values[$allDimProperties[$parentDimID]['path']] . '--' . $values[$dimension['path']];
                    }
                }
            }
        }

        // If this is a global object, there are no smart links, return
        if ($this->_schemas[$this->_entity]['globalschema'] ?? false) {
            return true;
        }

        // Validate smart links
        $ok = true;

        if($this->LoadSmartlinks(array(CUSTOMERP_SMARTLINKVALIDATE))) {
            if(!$this->smartLinks) {
                return true;
            }

            /**
             * @var SmartlinkValidate $smartlink
             */
            foreach($this->smartLinks as $smartlink) {
                $smartlink->SetDocType($this->_docType);

                if (!$smartlink->operationPermissible($actions, $this->_entity, $values, $this->_warningValidation,
                                                      $fromFastUpdate)) {
                    if ($smartlink->getErrorType() == SMARTLINK_VALIDATE_ERROR_STRING) {
                        return false; // if an error return
                    }
                    $ok = false; // it is a warning
                }
            }
        }

        return $ok;
    }


    /**
     * @param string $_schema
     *
     * @return string
     */
    public function GetPrintAs($_schema = '')
    {
        if (isset($this->_docType) && $this->_docType != '') {
            return $this->_docType . " Detail";
        }

        return parent::GetPrintAs($_schema);
    }

    /**
     * @param string $_schema
     *
     * @return string
     */
    public function GetPluralPrintAs($_schema = '')
    {
        if (isset($this->_docType) && $this->_docType != '') {
            return $this->_docType . " Details";
        }
        return parent::GetPluralPrintAs($_schema);
    }

    /**
     * Thsi function returns fieldinfo for custom documents processing, extending the logic
     * from GetPublishedFieldInfoForEntity() method, this fieldinfo helps in describing an object
     * and also used in data merge process as well.
     *
     * This method is overridden from EntityManager::GetCustomDocsFieldInfo()
     * and add the projects application specific fields to the entity definition.
     *
     * @param bool $includeRuntime
     *
     * @return array published fieldinfo
     */
    public function getFieldInfoForCustomDocs($includeRuntime = false)
    {
        $fields = parent::getFieldInfoForCustomDocs($includeRuntime);

        $customEntity = $this->GetCustomComponentsEntity();
        $platformDef = Pt_StandardUtil::getObjDef($customEntity);

        if ( $platformDef ) {
            $platformRels = Pt_StandardUtil::getRelationshipFields($platformDef);
            foreach( $platformRels as $fld ) {
                $fieldInfo = $fld->GetFieldInfo();
                $fieldInfo['type'] = array ('ptype' => 'text', 'type' => 'text');
                $fields[] = $fieldInfo;
            }
        }

        return $fields;
    }

    /**
     * Override useOwnedObject to prevent documententrysubtotals, sodocumententrysubtotals and podocumententrysubtotals
     * ownedobjects from being loaded or modified because these are readonly objects.
     * documentsubtotals, sodocumentsubtotals and podocumentsubtotals are the main object to write the data.
     */
    /**
     * @param array $objRec
     * @param bool  $validateReadOnly
     *
     * @return bool
     */
    protected function useOwnedObject($objRec, $validateReadOnly)
    {
        $entity = $objRec['entity'];
        //$isReadOnly = $objRec['readonlydata'];
        //uncomment below lines with GA of PDLC-0531-13
        //There is a bug: SUBTOTALSENTRY in XML3.0 should be available only for VAT enabled company but its for all now
        //if (($validateReadOnly && $isReadOnly) && in_array($entity, array('documententrysubtotals', 'sodocumententrysubtotals', 'podocumententrysubtotals'))) {
        if (in_array($entity, array('documententrysubtotals', 'sodocumententrysubtotals', 'podocumententrysubtotals'))) {
            return false;
        }

        if ($entity === 'documententrytrackdetail' && !DocumentManager::$upsertFeaturInUse) {
            //Case  IA-132258:
            //Since we are operating on the $this pointer at DocumentEntryManager and the
            //entity is 'documententrytrackdetail', we want to upsert the tracking entries
            $this->setUpsertEntries(true);
        } else {
            $this->setUpsertEntries(DocumentManager::$upsertFeaturInUse);
        }

        return parent::useOwnedObject($objRec, $validateReadOnly);
    }


    /**
     * @param array $values
     * @param array $oldEntries
     * @param array $newEntries
     */
    function getMappedEntries($values, &$oldEntries, &$newEntries)
    {
        $oldEntries = $values['EXISTING_ENTRIES'];
        $entries = $values['ENTRIES'];

        foreach ( $entries as $entry) {
            $recNo = $entry['RECORDNO'];

            if ($recNo != '') {
                $newEntries[$recNo] = $entry;
            } else {
                //
                // not sure if record number is missing;
            }
        }

    }



    /**
     *      See if there are any related adjustments and, if so, refuse to delete the record.
     *
     * @param string|int   $docEntryKey     the record# of the docentry about to be deleted
     *
     * @return bool
     */
    protected function checkForAdjustmentEntries($docEntryKey)
    {
        $ok = true;

        if ($docEntryKey) {
            $params = array(
                'selects' => array('RECORDNO'),
                'filters' => array(
                    array(
                        array(
                            'ADJDOCENTRYKEY', '=', $docEntryKey,
                        ),
                    ),
                ),
            );
            $res = $this->GetList($params);
            if (!empty($res)) {
                $msg  = "An inventory adjustment document is linked to a line item in this document that you deleted";
                $corr = "To update the document, first delete the linked inventory adjustment.";
                Globals::$g->gErr->addIAError('INV-0347', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr, []);

                $ok = false;
            }
        }

        return $ok;
    }


    /**
     *  See if there are any COGS Closed JE records and, if so, refuse to delete the record.
     *
     * @param string|int   $docEntryKey     the record# of the docentry about to be deleted
     *
     * @return bool
     */
    protected function checkForCOGSClosedJEEntries($docEntryKey)
    {
        $ok = true;
        if ($docEntryKey) {
            $res = QueryResult(
                [
                    "SELECT COUNT (1) count FROM cogsresolve WHERE cny# = :1 AND docentrykey = :2 ",
                    GetMyCompany(),
                    $docEntryKey ]
            );
            $ok = ($res !== false);
            if ($ok && ($res[0]['COUNT'] > 0)) {
                $msg  = "Prior period COGS adjustments are linked to a line item in this document that you deleted.";
                $corr = "To update the document, delete the posted prior period COGS adjustments. Then, try again.";
                Globals::$g->gErr->addIAError('INV-0348', __FILE__ . ':' . __LINE__, $msg, [], '', [], $corr, []);
                $ok = false;
            }
        }
        return $ok;
    }


    /**
     *      During upsert, some docentry records may be deleted during the Set() call.
     *  OWNED records will be deleted by the EntityManager, as will 'cascade delete' records
     *  like docentrycost and docentrycostkits.  However, things like the PR entry and PR entry resolve records
     *  are not automatically deleted, and need to be....
     *
     * @param array $raw         The values from the UI/API
     *
     * @return bool
     */
    public function beforeDelete(&$raw)
    {
        $ok = true;
        $docEntryKey = $raw[0]['RECORD#'] ?? 0;
        if (DocumentManager::$upsertFeaturInUse && $docEntryKey) {

            // is it ok to delete this docentry record?
            // Are there adjustments for it or COGS JE entries from closed periods?
            $ok = $this->checkForCOGSClosedJEEntries($docEntryKey) && $this->checkForAdjustmentEntries($docEntryKey);

            // note: docentrycost and docentrycostkits are 'cascade delete', so they take care of themselves.
            // note: revrec is 'cascade delete', however if we are deleting with POSTS, the dochdr has
            //       'HASPOSTEDREVREC' == 'T', and then the entire thing is thrown away and recreated.

            // If we are upserting the PRRecord and its owned objects, then we need to delete the
            // prentry record(s) that refer to this docentry
            if ($ok && DocumentManager::$upsertPRRecordToo) {
                $prentryManager = Globals::$g->gManagerFactory->getManager('prentry');
                $ok             = $ok && $prentryManager->deleteAllForDocEntry($docEntryKey);
            }
        }
        $ok = $ok && parent::beforeDelete($raw);
        $this->flushCacheForDocHdr();   // updated the underlying data, so invalidate the cache
        return $ok;
    }


    /**
     *      add - add a record
     *
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $this->flushCacheForDocHdr();   // updated the underlying data, so invalidate the cache


        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        // The :record# for each new entry is being pre-created in DocumentManager::PrepValues.
        // Here we are ensuring that the RECORDNO gets filled in appropriately.
        // Trying to set RECORDNO in PrepValues leads to problems in EntityManager::setOwnedObjects()
        foreach ($groupOfValues as &$entry) {

            if ( empty($entry) ) {
                continue;
            }

            if (isset($entry[':record#'])) {
                $entry['RECORDNO'] = $entry[':record#'];
            }
        }


        return parent::regularAdd($values);
    }

    /**
     * @return string[]
     */
    protected function getIgnoreFields()
    {
        static $ignoreFields = [
            'dochdrkey',
            'itemdescr',
            'pricecalcmemo',
            'lineno',
            'unit',
            'qty_converted',
            'retailprice',
            'price',
            'whencreated',
            'whenmodified',
            'auwhencreated',
            'createdby',
            'modifiedby',
            'state',
            'status',
            'cost',
            'costmethod',
            'uiqty',
            'discountpercent',
            'uiprice',
            'source_dockey',
            'source_doclinekey',
            'discount_memo',
            'trx_price',
            'scheduleid',
            'recurdocid',
            'timenotes',
            'customdimensions',
            'percentval',
            'taxabsval',
            'taxableamount',
            'total',
            'discount',
            'trx_taxabsval',
            'trx_total',
            'taxvaloverride',
            'multiplier',
        ];

        return $ignoreFields;
    }

    /**
     * @return string[]
     */
    protected function getExternalFieldsList()
    {
        static $externalFields = ['DROPSHIP', 'BUYTOORDER'];

        return $externalFields;
    }


    /**
     *      Did entries change? Are the entries now different than they were on disk (table)?
     *  What about the subrecords (well, here we only care about documententrytrackdetails)
     *
     *
     * @param array             $values                 The document being saved
     * @param EntityManager     $ownerEntityManager     The Document Manager
     */
    public function didEntriesChange(&$values, $ownerEntityManager)
    {
        if ( ! isset($values['EXISTING_ENTRIES'], $values['ENTRIES'])) {
            return; // nothing to do
        }

        // compare just for docentry, not her owned objects
        $compareFunc = function ($a, $b) {
            // see if the warehouse location/name has changed
            return (($a['WAREHOUSE']['LOCATION_NO'] ?? '') == ($b['WAREHOUSE']['LOCATION_NO'] ?? '')) &&
                // if a kit, the underlying kit might have changed, so lets say they don't match just in case
                (($a['ITEMTYPE'] ?? '') !== 'K') && (($a['ITEMTYPE'] ?? '') !== 'SK');
        };

        $mm = new Matchmaker($this);
        $nullIsFalse = ['SC_INSTALLPRICING', 'SC_EXTENDLINEPERIOD'];
        foreach ($nullIsFalse as $field) {
            $mm->setNullMeans( $field, 'false');
        }
        foreach ($values['EXISTING_ENTRIES'] as $index => $entry) {
            // make the names match so when we recurse down the tree we find them
            $values['EXISTING_ENTRIES'][$index]['TRACKINGENTRIES'] = $entry['EXISTING_TRACKINGENTRIES'] ?? [];
        }

        $mm->didExistingTreeChange( $values['EXISTING_ENTRIES'], $values['ENTRIES'],
             [], $ownerEntityManager, [$this->_entity => ['COMPARE_FUNCTION' => $compareFunc]] );
    }


    /**
     *      For any docentry record that has changed, we want to delete any corresponding docentrycost records
     *  so we can re-create them.  This assumes the above didEntriesChange() function has already been called.
     *
     * @param array $values     document tree from the UI
     *
     * @return bool
     */
    public function deleteDocEntryCostsForChangedRecords($values)
    {
        $docEntryKeys = [];
        foreach ($values['ENTRIES'] as $entry) {
            if (Matchmaker::needToUpdateLine($entry)) {
                $docEntryKeys[] = $entry['RECORDNO'];
            }
        }
        if (!empty($docEntryKeys)) {
            return DocumentEntryCostManager::deleteAllWithTheseDocEntryKeys($docEntryKeys);
        }
        return true;
    }


    /**
     * set() override
     *
     *      Could be one record, could be a bundle.  For upsert(), I want to track these so I can
     *  update item history properly later.
     *
     * @param array $values           DocumentEntry record(s)
     *
     * @return bool
     */
    protected function regularSet( &$values)
    {
        $this->flushCacheForDocHdr();   // updated the underlying data, so invalidate the cache
        return parent::regularSet($values);
    }


    /**
     *  If UPSERT is on, then we are NOT deleting all the docentry records for a document as part of the save.
     *  Instead we will either not write them at all, or just update them.  Without UPSERT, the docentry records
     *  are deleted and re-created.  This has MANY side-effects.  One is to delete any item activity records
     *  that belong to, or refer to, this document.
     *
     * Then the DocEntry triggers can update the item activity if they want.
     *
     * @param array   $values      The entire document tree
     *
     * @return bool
     */
    public function removeItemActivity($values)
    {
        $ok = true;

        if (DocumentManager::$upsertFeaturInUse) {

            // no entries?  nothing to do!
            if ( ! isset($values['ENTRIES'])) {
                return $ok;
            }

            global $gInventoryStateType;

            // process only if the document is in one of the following state
            // 'Pending'=>'O', 'Closed'=>'D', 'In Progress'=>'G', 'Converted'=>'C', 'Partially Converted'=>'P'
            $state = $values['STATE'] ?? $gInventoryStateType['default'];  // EXTERNAL VERSION OF THE NAME
            $stateKey = array_search($state, $gInventoryStateType['validvalues']);
            $state = ($stateKey === false) ? NULL : $gInventoryStateType['_validivalues'][$stateKey];    // INTERNAL VERSION OF THE NAME
            if (in_array($state, ['O', 'D', 'G', 'C', 'P']) === false) {
                return $ok;    // nothing to do
            }

            // Delete existing records; the cascade delete of the docentry would have deleted related records, which is important.
            // Here, though, the docentry was likely NOT deleted and so related records were not deleted either.
            // Example: change the date on a backorder transaction.  We want to change the date on the
            //      related transactions' icitemactivity records too.  Before UPSERT, the docentry would be deleted which
            //      would delete the item activity for the docentry AND related ones (the original order before the backorder)
            //      so even though the trigger tries to recreate things, it CANNOT update the related item activity records
            //      because they exist and there's a duplicate key colision (suppresed, but it is still there)
            $qry   = [];
            $qry[] = "DELETE FROM icitemactivity
                      WHERE cny# = :1
                        AND (parentdochdrkey = :2 OR childdochdrkey = :2)
                        AND totalkey not in
                            (select record# from ictotal where cny# = icitemactivity.cny# AND updatetype = 'CONTINUOUS')";
            $qry[] = GetMyCompany();
            $qry[] = $values['RECORDNO'];
            $ok    = ExecStmt($qry);
        }
        return $ok;
    }


    /**
     *      maybe update item activity, given UPSERT conditions
     *
     * Docentry Records that are new went through Add() and were already handled by the triggers.
     * Docentry Records that were deleted were removed and don't need further processing.
     * Above we deleted the item activity records AS IF we were deleting/re-creating the docentry records.
     *
     * During update, then, the DOCENTRY triggers will add item activity records if "significant things" change.
     * (which includes quantity, value, department, entity, create date, ...).
     *
     * So, if the above happens, then we're good.  But if the triggers detect nothing significant they will not
     * create item activity records, and so we must do that here.
     *
     * Note that before UPSERT, it would be significant that the record was being created and not updated, so almost
     * every re-created record would attempt to create item activity records.  This is what we're simulating here....
     *
     *
     * @param  array   $values      The entire document tree
     *
     * @return bool
     */
    public function maybeUpdateItemActivity($values)
    {
        $ok = true;

        // no entries?  nothing to do!
        if ( ! isset($values['ENTRIES'])) {
            return $ok;
        }

        if (DocumentManager::$upsertFeaturInUse) {

            global $gInventoryStateType;

            // process only if the document is in one of the following state
            // 'Pending'=>'O', 'Closed'=>'D', 'In Progress'=>'G', 'Converted'=>'C', 'Partially Converted'=>'P'
            $state     = $values['STATE']     ?? $gInventoryStateType['default'];  // EXTERNAL VERSION OF THE NAME
            $stateKey  = array_search($state, $gInventoryStateType['validvalues']);
            $state     = ($stateKey === false) ? null : $gInventoryStateType['_validivalues'][$stateKey];    // INTERNAL VERSION OF THE NAME
            if (in_array($state, ['O', 'D', 'G', 'C', 'P']) === false) {
                return $ok;    // nothing to do
            }

            // Which, if any, docentry records had item activity records written by the tiggers?
            $qry    = [];
            $qry[]  = "SELECT distinct docentrykey FROM icitemactivity
                       WHERE cny# = :1
                        AND parentdochdrkey = :2
                        AND totalkey not in
                            (select record# from ictotal where cny# = icitemactivity.cny# AND updatetype = 'CONTINUOUS')";
            $qry[]  = GetMyCompany();
            $qry[]  = $values['RECORDNO'];
            $result = QueryResult($qry);
            if ($result === false) {
                return false;
            }

            // index the items we do not need to fix (because the trigger fixed it):
            $alreadyCreatedItemActivity = [];
            foreach ($result as $row) {
                $alreadyCreatedItemActivity[$row['DOCENTRYKEY']] = true;
            }

            // Backorder is a boolean; turn it from external to internal form
            $backorder = (($values['BACKORDER'] ?? 'No') === 'Yes') ? 'T' : 'F';

            // Collect the record numbers with the right item types
            foreach ($values['ENTRIES'] as $row) {
                if ( ! isset($alreadyCreatedItemActivity[$row['RECORDNO']])) {
                    if (in_array(($row['ITEMTYPE'] ?? ''), ['I', 'K', 'SK'])) {
                        $this->updateItemActivityForOneItem($row, $backorder);
                    }
                }
            }
        }
        return $ok;
    }


    /**
     *      Add Item Activity for one row/one item (well, Kits have multiple items)
     *
     * @param array     $docEntryRow            A row from the document tree
     * @param string    $backorder              T or F, for passing along
     *
     * @return bool
     */
    protected function updateItemActivityForOneItem($docEntryRow, $backorder)
    {
        $cny = GetMyCompany();
        $ok  = true;
        $recs = [];

        // 'Inventory' => 'I', 'Kit'=>'K', 'Stockable Kit'=>'SK'
        if ($docEntryRow['ITEMTYPE'] == 'K') {
            Matchmaker::additionalLogging("icitemactivity fixup: THIS IS A KIT:" );

            // lets use what the trigger does, rather than what is used elsewhere.....
            // $kres  = $this->DoQuery('QRY_ICITEM_SELECT_KITCOMPONENTS', [$cny, $docEntryRow['ITEMID']]);
            $sql   = [];
            $sql[] = "SELECT  ic.componentkey,
                            sum(inv_utils.eval(ltrim(sys_connect_by_path(ic.quantity, '*'), '*')))  quantity,
                            it.itemtype
                            FROM icitemcomponent ic,  icitem it
                            WHERE IT.CNY#       = IC.CNY#
                            AND IC.COMPONENTKEY = IT.ITEMID
                            AND IT.itemtype	NOT IN ('K')
                            AND IT.CNY#             = :1
                              START WITH IC.itemkey = :2
                            AND IC.CNY#             = IT.CNY#
                              CONNECT BY IC.ITEMKEY = PRIOR IC.COMPONENTKEY
                              AND PRIOR IT.itemtype NOT IN ('SK')
                            AND ic.cny#             = :1
                            GROUP BY ic.componentkey, it.itemtype
                            ORDER BY ic.componentkey
                      ";
            $sql[] = $cny;
            $sql[] = $docEntryRow['ITEMID'];
            $kres  = QueryResult($sql);
            if ($kres === false) {
                return false;
            }

            foreach ( $kres as $oneRecord) {
                // note: 'VALUE' is not changed, so is the same value for all parts, which seems wrong, but this
                //       is the DocEntry record, not DocEntryCost, so I'm guessing it all works out....
                $newRow             = $docEntryRow;
                $newRow['ITEMID']   = $oneRecord['COMPONENTKEY'];
                $newRow['QUANTITY'] = ibcmul($newRow['QUANTITY'], $oneRecord['QUANTITY'], ItemManager::BASEUNITPRECISION, true);
                $newRow['ITEMTYPE'] = $oneRecord['ITEMTYPE'];
                $recs[]             = $newRow;
            }
        } else {  // must be I or SK....
            $recs = [$docEntryRow];     // just one row to process
        }

        // ok, finally, lets do what we're here for!
        foreach ($recs as $oneRecord) {
            $sql   = [];
            $sql[] = " BEGIN
                inv_utils.processitemondocentry(
                    :1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12, :13, :14, :15, :16, :17, :18
                    );
            END;";

            $sql[] = $cny;
            $sql[] = $oneRecord['RECORDNO'];
            $sql[] = $oneRecord['DOCHDRNO'];
            $sql[] = $oneRecord['ITEMID'];
            $sql[] = $oneRecord['WAREHOUSEID'];
            $sql[] = $oneRecord['COST'] ?? "0";
            $sql[] = $oneRecord['QUANTITY'];
            $sql[] = $oneRecord['TOTAL'] ?? "0";    // 'VALUE' on disk
            $sql[] = $oneRecord['WHENCREATED'];
            $sql[] = $oneRecord['LOCATIONKEY'];
            $sql[] = $oneRecord['DEPTKEY'] ?? '';
            $sql[] = $oneRecord['SOURCE_DOCKEY'] ?? '';
            $sql[] = $oneRecord['SOURCE_DOCLINEKEY'] ?? '';
            $sql[] = $cny;      // no, we're not changing cny!
            $sql[] = $oneRecord['RECORDNO'];    // again
            $sql[] = $oneRecord['DOCHDRNO'];
            $sql[] = $oneRecord['ITEMTYPE'];
            $sql[] = $backorder;

            $ok = ExecStmt($sql);
            if (!$ok) {
                break;
            }
        }
        return $ok;
    }


    /**
     * needToUpdateLine - called before UPSERTING our child entries (like tracking detail entries)
     *
     * @param array &$line line items
     *
     * @return bool
     */
    protected function needToUpdateLine(&$line)
    {
        return Matchmaker::needToUpdateLine($line);
    }


    /**
     * @param string $fieldName
     * @return string
     */
    protected function getDimensionRecordNoField($fieldName)
    {
        if ($fieldName == 'DEPARTMENT') {
            return 'DEPTKEY';
        }

        return parent::getDimensionRecordNoField($fieldName);
    }


    /**
     * Process a record for update
     *
     * @param array $values
     * @param bool  $transformPaths
     * @param array $transformed
     *
     * @return array
     */
    function _PreProcessForUpdate($values, $transformPaths = false, &$transformed = null)
    {
        unset($values['SCMMACROLINK']);

        return parent::_PreProcessForUpdate($values, $transformPaths, $transformed);
    }


    /**
     *      Can this docentry line be fulfilled?  (assumes the whole document can be fulfilled)
     *
     * @param array $docentry       The document entry fields
     *
     * @return bool                 Can this document entry participate in fulfillment?
     */
    public static function canBeFulfilled($docentry)
    {
        $itemType  = $docentry['ITEMTYPE'] ?? '';
        $warehouse = $docentry['WAREHOUSE']['LOCATION_NO'] ?? '';

        // is there anything LEFT to convert?
        $qty            = ($docentry['QUANTITY']        ?? 0) + 0;    // force numeric
        $qtyConverted   = ($docentry['QTY_CONVERTED']   ?? 0) + 0;    // ditto
        if ($qty <= $qtyConverted) {
            return false;   // completed fulfillment steps already
        }

        // Is this an inventory item and not a service or kit?
        // for a kit, you want to fulfill each part, not the kit itself
        if ((($itemType == 'I') || ($itemType == 'SK')) &&      // item is a warehouse item or stockable kit
            ($warehouse != '')) {                               // assigned to a warehouse
            return true;
        }
        return false;
    }

    /**
     * Get existing entries
     *
     * @param OwnedObjectManager &$lineManager line item manager object
     * @param int                $parentKey parent record number
     * @param array              &$values new values
     * @param array              &$oldRecNumbers existing record numbers
     *
     * @return bool
     */
    protected function getExistingEntries(&$lineManager, &$parentKey, &$values, &$oldRecNumbers)
    {
        if (in_array($lineManager->getEntity(), ['documententrytrackdetail'])) {
            if (isset($values['EXISTING_TRACKINGENTRIES'])) {
                // instead of calling getByParent() use the EXISTING_  structure in each line item
                // avoids unnecessary call to getByParent() as the EXISTING_ data already exists.

                $oldEntries = $values['EXISTING_TRACKINGENTRIES'];

                $values['EXISTING_ENTRIES'] = [];

                foreach ($oldEntries as $oldEntry) {
                    // Keep the list of old recordno
                    $oldRecNumbers[$oldEntry['RECORDNO']] = $oldEntry['RECORDNO'];

                    // We will keep the old entries data for post processing
                    $values['EXISTING_ENTRIES'][$oldEntry['RECORDNO']] = $oldEntry;
                }
            }
        } else {
            parent::getExistingEntries($lineManager, $parentKey, $values, $oldRecNumbers);
        }

        return true;
    }

    /**
     *  to check the field is required
     *
     * @param array $values
     * @param array $fldinfo field info
     *
     * @return bool
     **/
    protected function isFieldRequired($values, $fldinfo)
    {
        //For Draft Mode we need to skip this
        if ($this->isDraftDocument($values)){
            return false;
        }
        return parent::isFieldRequired($values, $fldinfo);
    }

    /**
     * Cleanup the data for the manager
     *
     * @param array $values the data
     *
     * @return bool false if error else true
     */
    public function cleanupEditorValues(&$values)
    {
        $ok = parent::CleanupEditorValues($values);

        /*
            * The 'ID' field for the LOCATION and DEPARTMENT attribute is typically used for REST API interactions.
            * However, the FormEditor utilizes the 'NAME' field, such as 'DEPARTMENT' and 'LOCATION'.
            * To avoid any discrepancies between these two fields, the 'DEPARTMENTID' and 'LOCATIONID' fields are omitted
            * from the '$values' array when the FormEditor is being used.
        */
        unset($values['DEPARTMENTID']);
        unset($values['LOCATIONID']);

        return $ok;
    }

}
