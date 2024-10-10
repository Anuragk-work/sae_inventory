<?php
import('NLister');

require_once 'scm_util.inc';

class DocumentParamsLister extends NLister
{
    /** @var bool $isAdvanced */
    protected $isAdvanced = false;

    const SHOW_HIERARCHY = 'SHOW_HIERARCHY';

    function __construct()
    {
        $title = $this->getTitle();
        $fields = array (
            'DOCID', 'DESCRIPTION', 'CATEGORY', "'RECURLINK'"
        );
        $this->addModuleLevelFields($fields);
        // If inventory service is subscribed add column called
        // Inventory Effect
        $gManagerFactory = Globals::$g->gManagerFactory;
        $modMgr = $gManagerFactory->getManager('modules');
        $inventorySubscribed = $modMgr->isModuleSubscribed("7.INV");
        if ($inventorySubscribed) {
            $fields[] = 'INV_EFFECT';
        }

        $entityName = $this->getEntityName();
        $helpFile = $this->getHelpFileName();

        $params =
            array (
                'title'		=> $title,
                'entity' => $entityName,
                'importtype' => $entityName,
                'fields' => $fields,
                'nonencodedfields' => array('RECORD_URL', "'RECURLINK'", 'DOCID'),
                'helpfile' => $helpFile
            );

        /** @var DocumentParamsManager $docparManager */
        $docparManager = $gManagerFactory->getManager($entityName);

        $this->handleStickyDisplayWorkflow($docparManager);

        if (isset(Request::$r->_showhierarchy) && Request::$r->_showhierarchy &&
            isset($docparManager->_schemas[$entityName]['showhierarchy']) &&
            $docparManager->_schemas[$entityName]['showhierarchy']) {
            // Remove filtering if the entity is configured to display workflow and
            // the Display workflow check box is selected.
            $params['nofilteronthesefields'] = ['DOCID', 'DESCRIPTION', 'CATEGORY', "'RECURLINK'"];
        }
        if ($inventorySubscribed) {
            $params['nofilteronthesefields'][] = 'INV_EFFECT';
        }

        $this->isAdvanced = IsAdvancedConfiguration();

        parent::__construct($params);
    }

    /**
     * @return DocumentParamsManager
     */
    public function getEntityMgr()
    {
        assert($this->entityMgr instanceof DocumentParamsManager);
        return $this->entityMgr;
    }

    /**
     * Implements sticky display workflow by reading from the user preferences
     * the user selection for the Display Workflow check box.
     *
     * @param DocumentParamsManager $docparManager
     *
     * @throws Exception
     */
    private function handleStickyDisplayWorkflow(DocumentParamsManager $docparManager)
    {
        $module = $docparManager->GetHomeModule();
        $prefFieldName = strtoupper($module) . '_' . self::SHOW_HIERARCHY;

        /** @var UserPrefManager $userPrefManager */
        $userPrefManager = Globals::$g->gManagerFactory->getManager('userpref');

        $userPrefs = $userPrefManager->getUserPreferences();

        $showHierarchy = Request::$r->_showhierarchy;
        if (!is_null($showHierarchy) && in_array($showHierarchy, ['0', '1'])) {
            // Request comes from the lister
            if ('' === $showHierarchy) {
                // Request comes from menu by clicking Include inactive / private.
                // set the $prefValue to NOT checked
                $showHierarchy = '0';
            }
            if (!isArrayValueProvided($userPrefs, $prefFieldName) || $showHierarchy != $userPrefs[$prefFieldName]) {
                // The $showHierarchy is different from the value stored in
                // the database. Update the database
                $userPrefs[$prefFieldName] = $showHierarchy;
                $userPrefManager->set($userPrefs);
            }
        } else {
            // Request comes from the menu
            if (isArrayValueProvided($userPrefs, $prefFieldName)) {
                // If the user preference has been stored previously assign it
                Request::$r->_showhierarchy = $userPrefs[$prefFieldName];
            }
        }
    }

    /**
     * Returns the title of the page. Should be overridden by the extending
     * classes.
     *
     * @return string
     * 
     * @throws Exception
     */
    protected function getTitle()
    {
        // PhpStorm inspection workaround
        if (1) {
            throw new Exception('Bad method call exception -> getTitle()');
        }
        return '';
    }

    /**
     * Returns the name of the entity shown in the lister.
     * Should be overridden by the extending classes.
     *
     * @return string
     * 
     * @throws Exception
     */
    protected function getEntityName()
    {
        // PhpStorm inspection workaround
        if (1) {
            throw new Exception('Bad method call exception -> getEntityName()');
        }
        return '';
    }

    /**
     * Returns the name of the workflow entity shown in the lister.
     * Should be overridden by the extending classes.
     *
     * @throws Exception
     */
    protected function getWorkflowEntityName()
    {
        throw new Exception('Bad method call exception -> getWorkflowEntityName()');
    }

    /**
     * Returns the name of the help file available on the page.
     * Should be overridden by the extending classes.
     * 
     * @return string
     *
     * @throws Exception
     */
    protected function getHelpFileName()
    {
        // PhpStorm inspection workaround
        if (1) {
            throw new Exception('Bad method call exception -> getHelpFileName()');
        }
        return '';
    }

    /**
     * This function should be implemented by all extending classes.
     * It throws an exception if called directly.
     */
    function getRecurOperationKey() {
        throw new Exception("Bad method call exception -> getRecurOperationKey()");
    }

    function BuildTable()
    {
        global $_userid,$gManagerFactory;
        /** @var DocumentParamsManager $docparMgr */
        $docparMgr = $gManagerFactory->getManager($this->entity);
        $mod = Request::$r->_mod;

        NLister::BuildTable();

        //added for recurring transactions
        $recurOpID = GetOperationId($this->getRecurOperationKey());
        list($user,$cny) = explode('@', $_userid);  //separate the userid and cny

        foreach($this->table as $key => $row) {

            //added for recurring transactions
            //Get the transaction level permission for this user
            $args = array($row['DOCID'], $user, $cny, $cny );
            $res = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_GET_USER_PERMISSION', $args);

            if(
                (($res[0]['USERPERM'] ?? 'F') =='T' && ($res[0]['PERM'] ?? '?') == 'D')
                || in_array($row['DOCID'], DocumentParamsManager::$systemGeneratedTDs)
            ) {//if user is denied perm for this TD
                $this->table[$key]["'RECURLINK'"] = "";
            } else {
                $docpar['CREATION_RULE'] = $docparMgr->getCreationRule($row);
                if ('T' === $docpar['CREATION_RULE'] && $mod != 'inv') {
                    $this->table[$key]["'RECURLINK'"] = '<a  href="./lister.phtml?.op='.$recurOpID
                        .'&.r='.urlencode($row['RECORDNO'])
                        .'&.dt='.urlencode($row['DOCID'])
                        //.'&'.OptDone($done)
                        .'&'.OptDone(ScriptRequest())
                        .'" onmouseover=\'window.status="Recurring Templates'
                        .'"; return true;\' onfocus=\'window.status="Recurring Templates'
                        .'"; return true;\' onblur=\'window.status=""\''
                        .' onmouseout=\'window.status=""\'>'.GT($this->textMap,'IA.RECURRING_TEMPLATES').'</a>';
                } else {
                    $this->table[$key]["'RECURLINK'"] = "";
                }
            }
            $noChangeTokenVal =I18N::getSingleToken("IA.NO_CHANGE");
            $enabledDocChange = isNullOrBlank($row['ENABLEDOCCHANGE']) ? $noChangeTokenVal : I18N::getSingleToken($row['ENABLEDOCCHANGE']);
            if($enabledDocChange != $noChangeTokenVal){
                $this->table[$key]["'RECURLINK'"] = "";
            }
            $falseVal =  I18N::getSingleToken("IA.FALSE");
            $enableContractBilling = isNullOrBlank($row['ENABLECONTRACTBILLING']) ? $falseVal : I18N::getSingleToken($row['ENABLECONTRACTBILLING']);
            if($enableContractBilling != $falseVal){
                $this->table[$key]["'RECURLINK'"] = "";
            }
        }
    }

    /**
     * Overrides the method. If the page in the Show Workflow mode creates
     * the query spec for TD workflow information.
     * Otherwise, call the patent method.
     *
     * @return array
     */
    function BuildQuerySpec()
    {
        if ($this->showHierarchy) {
            $sh = $this->showHierarchy;
            $this->showHierarchy = false;
            $querySpec = parent::BuildQuerySpec();

            $querySpec['max'] = null;
            $querySpec['start'] = 0;

            $this->showHierarchy = $sh;

        } else {
            $querySpec = parent::BuildQuerySpec();
        }
        $querySpec['selects'][] = 'TD_CREATION_RULE';
        $querySpec['selects'][] = 'RECORDNO';
        $querySpec['selects'][] = 'ENABLEDOCCHANGE';

        $mod = Request::$r->_mod;
        if($mod === 'so'){
            $querySpec['selects'][] = 'ENABLECONTRACTBILLING';
        }
        return $querySpec;
    }

    /**
     * Import URL is for advanced configuration only.
     *
     * @return string
     */
    function addImportURL() {
        $importUrl = "";
        if (IsAdvancedConfiguration()) {
            $importUrl = parent::addImportURL();
        }
        return $importUrl;
    }

    /**
     * @return bool|string
     */
    function calcAddUrl() {

        if(!$this->isAdvanced){
            return false;
        }
        return parent::calcAddUrl();
    }

    /**
     * @param int   $i
     * @param array $vals
     *
     * @return array
     */
    function calcEditUrlParms($i, $vals) {
        return parent::calcEditUrlParms($i, $vals);
    }

    /**
     * @param int         $i
     * @param string|null $owner
     * @param string|null $ownerloc
     * @param bool|null   $ownedObj
     *
     * @return string
     */
    function calcDeleteUrl($i, $owner = null, $ownerloc = null, $ownedObj = null)
    {
        $t = &$this->table;
        
        if (in_array($t[$i]['DOCID'], DocumentParamsManager::$systemGeneratedTDs)) {
            return false;
        }
        
        return parent::calcDeleteUrl($i);
    }

    /**
     * Indicates if the Show Workflow check box is shown on the page.
     *
     * @return bool
     */
    protected function calcShowHierarchyOption()
    {
        // return false;
        $entityMgr = $this->getEntityMgr();
        return isset($entityMgr->_schemas[$this->entity]['showhierarchy'])
               && $entityMgr->_schemas[$this->entity]['showhierarchy'] === true;
    }

    /**
     * Indicates if the page must be rendered in the Show Workflow mode.
     *
     * @return bool
     */
    protected function calcShowHierarchy()
    {
        // Disable Hierarchy query for Recently viewed and modified views as they don;t work
        if ($this->IsAuditView($this->_params['userviewid'])) {
            return false;
        }
        else {
            // Default is NOT to show workflows
            return ( (isset(Request::$r->_showhierarchy) && Request::$r->_showhierarchy) && $this->showHierarchyOption);
        }

    }

    /**
     * Overrides the default display hierarchy label and tip.
     *
     * @return array
     */
    protected function  getDisplayHierarchy()
    {
        return ['text' => I18N::getSingleToken('IA.DISPLAY_WORKFLOWS'), 'tip' => GT($this->textMap, 'IA.TOGGLEVIEW')];
    }

    /**
     * @param array $table
     *
     * @return bool
     */
    function CustomizeList(&$table)
    {
        $showinactive = $this->_params['_showinactive'];
        $status = $this->_params['_showstatus'];
        $nostatus = $this->_params['_entitynostatus'];
        $entity = $this->_params['_entity'];

        // Filter only active TDs if the check box is not selected
        $showActiveOnly = ($showinactive == 0) && ($status != 1 && $nostatus != 1 && ($entity));

        if ($this->showHierarchy) {
            $manager = $this->getEntityMgr();
            $topDownRelations =
                $manager->getDocumentParamsRelations($table, $showActiveOnly);

            $table = $manager->getWorkflows($table, $topDownRelations);

            $domainSize = 1;
            if (isset($table[0])) {
                $domainSize = $table[0]['QCNT'];
            }
            $this->SetDomainSize($domainSize);

            $originalRangeSize = $this->_params['_rangesize'];
            $originalRangeBegin = $this->_params['_rangebegin'];
            $this->_params['_rangesize'] = $domainSize;
            $this->_params['_rangebegin'] = 0;

            parent::CustomizeList($table);

            $this->_params['_rangesize'] = $originalRangeSize;
            $this->_params['_rangebegin'] = $originalRangeBegin;
        } else {
            parent::CustomizeList($table);
        }


        return true;
    }

    /**
     * Overrides the list of fields for specific modules
     * @param array     $fields
     *
     * @return array
     */
    protected function addModuleLevelFields(&$fields)
    {
        return $fields;
    }

    /**
     * Initialize table tokens required in lister
     */
    protected function initTableTokens()
    {
        //This lister additional tokens
        $this->additionalTokens[] = 'IA.DISPLAY_WORKFLOWS';
        $this->additionalTokens[] = 'IA.TOGGLEVIEW';
        $this->additionalTokens[] = 'IA.RECURRING_TEMPLATES';
        $this->additionalTokens[] = 'IA.ENABLE_INV_ITEMS_FOR_RESERVING_PICKING_OPTIONS_ALERT_MESSAGE';

        //Let the parents a chance
        parent::initTableTokens();
    }
}
        

