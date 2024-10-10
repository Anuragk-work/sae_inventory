<?php

/**
 * @author    Naresh Kannan <naresh.kannan@sage.com>
 * @copyright 2021 Sage Intacct Inc., All Rights Reserved
 */

trait ProjectContractBillingTrait
{

    /**
     * @var bool $_isUpdate
     */
    protected $_isUpdate = false;

    /**
     * @var array $_projectContractCache
     */
    protected $_projectContractCache = [];

    /**
     * @var array $_projectContractLineCache
     */
    protected $_projectContractLineCache = [];

    /**
     * @var array $_projectContractInvoicesCache
     */
    protected $_projectContractInvoicesCache = [];

    /**
    /**
     * @var array $_pcblDetails
     */
    protected $_pcblDetails = [];

    /**
     * @var array $_pcblDimension
     */
    protected $_pcblDimension = [];

    /**
     * @var array $_pcblDimensionName
     */
    protected $_pcblDimensionName = [];

    /* @var array $projectContractCache */
    private $projectContractCache = array();

    /* @var array $projectContractLinesCache */
    protected $projectContractLinesCache = [];

    /* @var array $projectContractLinesTotalPrice */
    protected $projectContractLinesTotalPrice = [];

    /**
     * @return array
     */
    private function getAllowedPCBModules(): array
    {
        $allowedModules = ['so'];

        return $allowedModules;
    }

    /**
     * @return string[]
     */
    private function getAllowedPCBEntities(): array
    {
        return ['arinvoice'];
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function isPCBEnabled($values) : bool
    {
        if (!CRESetupManager::isProjectContractEnabled()) {
            return false;
        }

        if (!isset($values["_DOCPAR"])) {
            global $gManagerFactory;
            $docparMgr = $gManagerFactory->getManager('documentparams');
            $values['DOCPARID'] = $values['DOCPARID'] ?? $this->_docType;
            $docpar = $docparMgr->GetLatest($values['DOCPARID'], false);
            if ($docpar) {
                $values['DOCPARKEY'] = $docpar['RECORDNO'];
                $values['_DOCPAR'] = $docpar;
            }
        }

        if (isset($values['ENABLECONTRACTBILLING']) && !isNullOrBlank($values['ENABLECONTRACTBILLING'])) {
            $contractBilling = $values['ENABLECONTRACTBILLING'];
        } else {
            $contractBilling = $values["_DOCPAR"]["ENABLECONTRACTBILLING"] ?? "false";
        }

        return CRESetupManager::isCREInstalled() &&
            (in_array(($this->mod ?? ''), $this->getAllowedPCBModules()) || in_array(($this->_entity ?? ''), $this->getAllowedPCBEntities()))
            && ($contractBilling == 'true');
    }

    /**
     * @param array $values
     *
     * @param bool $isUpdate
     *
     * @return bool
     */
    public function processPCB(&$values, $isUpdate = false) : bool
    {
        $ok = true;
        $pcbRequired = $this->isPCBEnabled($values);
        // Allow project contract values if the invoice is system generated (including retainage release invoices).
        if (($this->isItFromPGIProjectContract($values) && $pcbRequired) || ($this->_entity === 'arinvoice' && ($values['SYSTEMGENERATED'] ?? "false") == "true")) {
            $this->_isUpdate = $isUpdate;
            if ($pcbRequired) {
                $ok = $ok && $this->validatePCB($values);
            }
            if($this->_entity != 'arinvoice'){
                $ok = $ok && $this->validateRetainageRelease($values);
            }
            $ok = $ok && $this->convertIdsToKey($values);
            $ok = $ok && $this->preparePCB($values);

        } else { // Non PCB Documents
            if(!CRESetupManager::isCREInstalled()) {
                $ok = $this->validateNonPCB($values);
            } else {
                $ok = $this->documentDoesNotContainPCBFields($values);
            }
        }

        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function validatePCB(&$values) : bool
    {
        $gErr = Globals::$g->gErr;

        $fromGenerateInvoices = (($values['fromGenerateInvoices'] ?? false) || !isNullOrBlank($values['INVOICERUNKEY'])) ?? false;

        $entries = ($this->_entity === 'arinvoice') ? $values['ITEMS'] : $values['ENTRIES'];

        $duplicatePCBLines = [];

        if($this->_entity != 'arinvoice'){

            $srcId = !empty($values["CREATEDFROM"]) ? $values["CREATEDFROM"] :$values["ENTRIES"][0]["SOURCE_DOCID"];

            if(!$fromGenerateInvoices && !empty($srcId) && !empty($values["_DOCPAR"]["ENABLECONTRACTBILLING"]) && $values["_DOCPAR"]["ENABLECONTRACTBILLING"] == 'true'){
                $gErr->addIAError(number: 'CRE-3323', source: __FILE__ . ':' . __LINE__);
                return false;
            }

        }


        $hasPCBL = false;
        $pcbHeaderFields = array_flip($this->getPCBHeaderFields());

        // $this->getPCBEntries($entries); // to initialize the pcl cache
        foreach ($entries as &$entry) {
            $lineNo = $entry['LINE_NO']+1;
            // Document can also contain lines with neither a project contract nor project contract line ID
            if (isNullOrBlank($entry['PROJECTCONTRACTID']) || isNullOrBlank($entry['PROJECTCONTRACTLINEID'])) {
                $gErr->addIAError(number: 'CRE-1500', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);
                return false;
            }
            if (isNullOrBlank($entry['PROJECTCONTRACTID']) && !isNullOrBlank($values['PROJECTCONTRACTID'])) {
                $entry['PROJECTCONTRACTID'] = $values['PROJECTCONTRACTID'];
            }
            if (empty($entry['PROJECTCONTRACTKEY']) && !empty($values['PROJECTCONTRACTKEY'])
            ) {
                $entry['PROJECTCONTRACTKEY'] = $values['PROJECTCONTRACTKEY'];
            }
            if ((!isNullOrBlank($entry['PROJECTCONTRACTID']) && $entry['PROJECTCONTRACTID'] !== $values['PROJECTCONTRACTID']) ||
                (!empty($entry['PROJECTCONTRACTKEY']) && $entry['PROJECTCONTRACTKEY'] != $values['PROJECTCONTRACTKEY'])
            ) {
                // If the ProjectContractKey matches, this isn't a failure - just fix the ProjectContractID.
                if ($values['PROJECTCONTRACTKEY'] == $entry['PROJECTCONTRACTKEY']) {
                    $values['PROJECTCONTRACTID'] = $entry['PROJECTCONTRACTID'];
                }
                else {
                    $gErr->addIAError(number: 'CRE-1501', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);

                    return false;
                }
            }
            if (isNullOrBlank($entry['PROJECTCONTRACTLINEID']) && empty($entry['PROJECTCONTRACTLINEKEY'])
            ) {
                $gErr->addIAError(number: 'CRE-1502', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);

                return false;
            }
            $this->prefillPCBLDetails($entry);
            if($this->_entity === 'sodocument'  && $entry['PCBLBILLINGTYPE'] == "Progress" && $entry['CONVERSIONTYPE'] != "Price"){
                $gErr->addIAError(number: 'CRE-1503', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);

                return false;
            }
            if((isNullOrBlank($values['INVOICERUNKEY']) && !$fromGenerateInvoices) && $entry['PCBLBILLINGTYPE'] == 'TM'){
                $gErr->addIAError(number: 'CRE-1504', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);
                return false;
            }

            if($entry["PCBLBILLINGTYPE"] == "Progress" && $this->_entity != 'arinvoice'){
                $type = (!empty($entry["ISRETAINAGERELEASE"]) && $entry["ISRETAINAGERELEASE"] == "true") ? "releasing" : "billing";
                if(empty($duplicatePCBLines[$entry['PROJECTCONTRACTLINEID']][$type])){
                    $duplicatePCBLines[$entry['PROJECTCONTRACTLINEID']][$type] = $entry;
                }else{
                    $errNo = ($type == 'releasing') ? 'CRE-3307': 'CRE-3308';
                    $gErr->addIAError(number: $errNo, source: __FILE__ . ':' . __LINE__, corrPHs: ['lineNo' => $lineNo]);
                    return false;
                }
            }

            $hasPCBL = true;
        }

        if (!$fromGenerateInvoices && $this->entriesHaveBillingTypeOfTimeAndMaterial($entries)) {
            return false;
        }
        
        if($hasPCBL){
           if (isNullOrBlank($values['PROJECTCONTRACTID']) && empty($values['PROJECTCONTRACTKEY'])) {
               $gErr->addIAError(number: 'CRE-1505', source: __FILE__ . ':' . __LINE__);
               return false;
           }
        } else {
            if (isNullOrBlank($values['PROJECTCONTRACTID']) && empty($values['PROJECTCONTRACTKEY'])) {
                $pcbIntersect = array_intersect_key($values, $pcbHeaderFields);
                /*TODO HACK: I think there should be a better way to do this...*/
                unset($pcbIntersect['TOTALRETAINAGE']);
                unset($pcbIntersect['TOTALEARNEDLESSRET']);
                unset($pcbIntersect['CURRENTAMTDUE']);
                unset($pcbIntersect['BALANCETOFINISH']);
                unset($pcbIntersect['TOTALCOMPLETEDTODATE']);
                foreach ($pcbIntersect as $pcbIKey => $pcbI){
                    if(isNullOrBlank($pcbI) || $pcbI == 0){
                        continue;
                    }
                    $gErr->addIAError(number: 'CRE-1506', source: __FILE__ . ':' . __LINE__);
                    return false;
                }
            }
        }

        $ok = $this->validatePCBMaximumBilling($values);

        return $ok;
    }
    
    /**
     * Checks to see if any entries have a T&M billing type
     * Cases where the check is bypassed:
     * 1. During document update
     * 2. APIs
     * 3. Entry does not have Project contract id
     *
     * @param array $entries
     *
     * @return bool false when there are no T&M billing type entries or when bypassed
     */
    protected function entriesHaveBillingTypeOfTimeAndMaterial(array $entries)
    {
        $gErr = Globals::$g->gErr;
        // Bypass validation during update
        if ($this->getEntityManagerAction() == EntityManager::UPDATEACTION) {
            return false;
        }
        $pclManager = Globals::$g->gManagerFactory->getManager('projectcontractline');
        $ids = '';
        $billingTypeIsTM = false;
        foreach ($entries ?? [] as $entry) {
            //  We don't need this validation if line doesn't contain project contract
            if ($entry['PROJECTCONTRACTID'] === null) {
                continue;
            }
            //  We don't need this validation if from API or non PCN source
            if ($entry['SOURCE_LINETYPE'] !== null && $entry['SOURCE_LINETYPE'] !== 'PCNTRANSITEMS')  {
                continue;
            }

            $lineNo = $entry['LINE_NO'];
            $pclData = $this->getProjectContractLines($entry['PROJECTCONTRACTID'])[$entry['PROJECTCONTRACTLINEID']];
            if ($pclData['BILLINGTYPE'] == 'TM') {
                $ids .= _("line {$lineNo} - {$entry['PROJECTCONTRACTLINEID']}; ");
                $billingTypeIsTM = true;
            }
        }
        
        if ($billingTypeIsTM) {
            $gErr->addIAError(number: 'CRE-1507', source: __FILE__ . ':' . __LINE__, desc2PHs: ['IDS' => $ids]);
            
            return true;
        }
        
        return false;
    }

    /**
     * @param array $values
     */
    private function convertIdsToKey(&$values): bool
    {
        $ok = true;
        $entries = ($this->_entity === 'arinvoice') ? $values['ITEMS'] : $values['ENTRIES'];
        $this->convertPCBIdtokey($values);
        $ok = $ok && $this->convertPCBLineIdtoKey($entries);
        if ($this->_entity === 'arinvoice') {
            $values['ITEMS'] = $entries;
        } else {
            $values['ENTRIES'] = $entries;
        }
        return $ok;
    }

    /**
     * @param string $projectContractId
     *
     * @return array
     */

    protected function getPCB($projectContractId) : array
    {
        if (!$this->_projectContractCache[$projectContractId]) {
            $gManagerFactory = Globals::$g->gManagerFactory;
            [$pcbId] = explode('--', $projectContractId);
            $projectContract = $gManagerFactory->getManager('projectcontract')->get($pcbId);
            $this->_projectContractCache[$projectContractId] = $projectContract;
        }

        return $this->_projectContractCache;
    }

    /**
     * entries details are not available in pcb get, thats why separate method for entries
     *
     * @param array|string $obj
     *
     * @return array
     */
    protected function getPCBEntries($obj): array
    {
        if(is_array($obj)){
            $pcIds = [];
            foreach ($obj as $entry) {
                if (isset($entry['PROJECTCONTRACTID']) && !isNullOrBlank($entry['PROJECTCONTRACTID']) &&
                    isset($entry['PROJECTCONTRACTLINEID']) && !isNullOrBlank($entry['PROJECTCONTRACTLINEID'])
                ) {
                    [$projectContractId] = explode('--', $entry['PROJECTCONTRACTID']);
                    if (!in_array($projectContractId, $pcIds)
                        && !in_array($projectContractId, $this->_projectContractLineCache[$projectContractId] ?? [])) {
                        $pcIds[] = $projectContractId;
                    }
                }
            }
            if (!empty($pcIds)) {
                $gManagerFactory = Globals::$g->gManagerFactory;
                $params = [
                    'selects' => [],
                    'filters' => [[['PROJECTCONTRACTID', 'IN', $pcIds]]],
                ];
                $pclList = $gManagerFactory->getManager('projectcontractline')->GetList($params);
                foreach ($pclList as $pcbl) {
                    $this->_projectContractLineCache[$pcbl['PROJECTCONTRACTID'] . '--' . $pcbl['PROJECTCONTRACTLINEID']] = $pcbl;
                }
            }

            return $this->_projectContractLineCache;
        }else{
            return $this->_projectContractLineCache[$obj] ?? [];
        }
    }

    /**
     * @param array $values
     */
    protected function convertPCBIdtokey(&$values)
    {
        if (!isNullOrBlank($values['PROJECTCONTRACTID'])) {
            $projectContract = $this->getPCB($values['PROJECTCONTRACTID']);
            $values['PROJECTCONTRACTKEY'] = $projectContract[$values['PROJECTCONTRACTID']]['RECORDNO'];
        } else if (empty($values['PROJECTCONTRACTKEY'])) {
            $values['PROJECTCONTRACTKEY'] = "";
        }
    }

    /**
     * @param array $entries
     */
    protected function convertPCBLineIdtoKey(&$entries): bool
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        // $pcbEntries = $this->getPCBEntries($entries);
        foreach ($entries as $key => $entry) {
            if(isset($entry['PROJECTCONTRACTID']) && isset($entry['PROJECTCONTRACTLINEID'])){
                [$projectContractId] = explode('--', $entry['PROJECTCONTRACTID']);
                [$projectContractLineId] = explode('--', $entry['PROJECTCONTRACTLINEID']);
                $projectContract = $this->getPCB($projectContractId);
                $pcbEntries = $this->getProjectContractLines($projectContractId);
                if (isset($pcbEntries[$projectContractLineId])) {
                    $entries[$key]['PROJECTCONTRACTKEY'] = $projectContract[$projectContractId]['RECORDNO'];
                    $entries[$key]['PROJECTCONTRACTLINEKEY'] = $pcbEntries[$projectContractLineId]['PROJECTCONTRACTLINENO'];
                } else {
                    $gErr->addIAError(number: 'CRE-1508', source: __FILE__ . ':' . __LINE__);
                    return false;
                }
            }
        }
        return $ok;
    }

    /**
     * Removing Project Contract Billing TD for Process Transaction
     *
     * @param array $allTransactionDefs
     *
     * @return array
     */
    public function removePCBDocuments($allTransactionDefs): array
    {
        foreach ($allTransactionDefs as $key => &$transactionDef) {
            $projectContract = $transactionDef['ENABLECONTRACTBILLING'] ?? 'F';
            if ($projectContract == 'T') {
                unset($allTransactionDefs[$key]);
            }
        }

        return array_values($allTransactionDefs);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function validateNonPCB($values): bool
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $pcbHeaderFields = $this->getPCBHeaderFields();
        $pcbEntryFields = $this->getPCBEntryFields();

        foreach($pcbHeaderFields as $field){
            if(!empty($values[$field])){
                $gErr->addIAError(number: 'CRE-1509', source: __FILE__ . ':' . __LINE__, desc2PHs: ['FIELD' => $field]);
                return false;
            }
        }

        $entries = $values['ENTRIES'] ?? [];

        foreach ($entries as $entry) {
            foreach ($pcbEntryFields as $field) {
                if (!empty($entry[$field])) {
                    $gErr->addIAError(number: 'CRE-1510', source: __FILE__ . ':' . __LINE__, desc2PHs: ['FIELD' => $field]);
                    return false;
                }
            }
        }
        return $ok;
    }
    
    /**
     * Validates that PCB fields are not present in a document line entry
     * @param array $values
     *
     * @return bool Returns false if a PCB field exists in a document line entry
     */
   private function documentDoesNotContainPCBFields(array $values) : bool
   {
       //   Don't validate if from PGI
       $gErr = Globals::$g->gErr;
       $fromGenerateInvoices = $values['fromGenerateInvoices'] ?? false;
       if ($fromGenerateInvoices) {
           return true;
       }
       $documentContainsPCBFields = false;
       $pcbEntryFields = $this->getPCBEntryFields();
       $pcbFieldsInDocument = '';
       foreach ($values['ENTRIES'] ?? [] as $entry) {
           $fieldsInThisLine = '';
           foreach ($pcbEntryFields as $fieldName) {
               if ( !empty($entry[$fieldName]) && !empty(trim($entry[$fieldName]))) {
                   $fieldsInThisLine .= _("{$fieldName} ");
                   $documentContainsPCBFields = true;
               }
           }
           $fieldsInThisLine = trim($fieldsInThisLine);
           if ($fieldsInThisLine != '') {
               $pcbFieldsInDocument .= _("line {$entry['LINE_NO']} - {$fieldsInThisLine}; ");
           }
       }
       if ($documentContainsPCBFields) {
           $gErr->addIAError(number: 'CRE-1511', source: __FILE__ . ':' . __LINE__, desc2PHs: ['IDS' => $pcbFieldsInDocument]);
        
           return false;
       }
    
       return true;
   }

    /**
     * @return array
     */
    protected function getPCBHeaderFields(): array
    {
        $headerFields = ['PROJECTCONTRACTID', 'PROJECTCONTRACTKEY', 'PCBEXTERNALREFNO', 'PCBDESCRIPTION', 'PCBDATE',
                         'ARCHITECTKEY', 'BILLTHROUGHDATE', 'BILLAPPLICATIONNO', 'ORGCONTRACTAMT', 'NETCHANGES',
                         'REVISEDCONTRACTAMT', 'TOTALCOMPLETEDTODATE', 'RETCOMPLETEDAMT', 'RETSTOREDMATERIALS',
                         'TOTALRETAINAGE', 'TOTALEARNEDLESSRET', 'LESSPRIORAPPLICATION', 'CURRENTAMTDUE',
                         'BALANCETOFINISH', 'TCAPMADDITION', 'TCAPMDEDUCTION', 'TCATMADDITION', 'TCATMDEDUCTION',
                         'TOTALNETCHANGESADDITION', 'TOTALNETCHANGESDEDUCTION', 'TOTALNETCHANGES', 'ARCHITECT',
                         'PREVIOUSRETAINAGEBALANCE'];
        return $headerFields;
    }

    /**
     * @return array
     */
    protected function getPCBEntryFields(): array
    {
        $entryFields = ['PROJECTCONTRACTID', 'PROJECTCONTRACTKEY', 'PROJECTCONTRACTLINEID', 'PROJECTCONTRACTLINEKEY',
                        'PCBLEXTERNALREFNO','PCBLDESCRIPTION','CONTRACTLINEVALUE','PRIORAPPLICATIONAMT',
                        'COMPLETEDTHISPERIOD','STOREDMATERIALS'];
        $entryFields = array_merge($entryFields, $this->getPCBEntryReadOnlyFields());
        return $entryFields;
    }

    /**
     * @return array
     */
    protected function getPCBEntryReadOnlyFields(): array
    {
        $entryFields = ['PCBLBILLINGTYPE', 'TOTALCOMPLETEDTODATE','PERCENTCOMPLETEDTODATE','BALANCEREMAINING'];
        return $entryFields;
    }

    /**
     * @param array $values
     *
     */
    public function unsetPCBFields(&$values){
        $pcbHeaderFields = $this->getPCBHeaderFields();
        $pcbEntryFields = $this->getPCBEntryFields();

        foreach($pcbHeaderFields as $field){
            if(!empty($values[$field])){
                unset($values[$field]);
            }
        }

        foreach($values['ENTRIES'] as $entry){
            foreach($pcbEntryFields as $field){
                if(!empty($entry[$field])){
                    unset($entry[$field]);
                }
            }
        }
    }

    /**
     * To get the project contract details for ajax call from UI
     * @param array $params
     *
     * @return string
     */
    public function FetchProjectContractDetail($params): string
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $projectContractId = $params['projectcontractid'];
        [$pcId] = explode('--', $projectContractId);
        $select = ['EXTERNALREFNO', 'DESCRIPTION AS PCBDESCRIPTION', 'CONTRACTDATE AS PCBDATE',
                   'ARCHITECT.CONTACTNAME', 'TOTALRETAINAGEHELD AS RETCOMPLETEDAMT', 'TOTALRETAINAGEHELD AS TOTALRETAINAGE',
                'ORIGINALPRICE AS ORGCONTRACTAMT', 'RETAINAGEBALANCE', 'BILLEDPRICE'];

        // couldn't set column alias for join tables and name difference, so hareder way to rename the column
        $renameFields = ["EXTERNALREFNO" => "PCBEXTERNALREFNO", "ARCHITECT.CONTACTNAME" => "ARCHITECT", "BILLEDPRICE" => "TOTALCOMPLETEDTODATE"];


        $filter = [
            'selects' => $select,
            'filters' => [[['PROJECTCONTRACTID', '=', $pcId]]]
        ];

        $projectContract = $gManagerFactory->getManager('projectcontract');
        $result = $projectContract->GetList($filter);

        foreach ($result[0] ?? [] as $key => $value){
            if(array_key_exists($key , $renameFields)){
                $result[0][$renameFields[$key]] = $value;
                unset($result[0][$key]);
            }
        }

        $data = $result[0] ?? [];
        $data = array_map('htmlentities', $data);
        $json = json_encode($data);
        $xml = "<ProjectContractDetail>{$json}</ProjectContractDetail>";
        return $xml;
    }

    /**
     * @param array $params
     *
     * @return string
     */
    public function FetchProjectContractLineDetail($params): string
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $projectContractId = $params['projectcontractid'];
        $projectContractLineId = $params['projectcontractlineid'];
        [$pcId] = explode('--', $projectContractId);
        [$pclId] = explode('--', $projectContractLineId);

        // Todo need to add description once it is added in project contract line, removed it due to column ambiguously defined error
        $select = ['EXTERNALREFNO', 'BILLINGTYPE', 'RETAINAGEPERCENTAGE','BILLEDPRICE', 'PCCUSTOMERNAME', 'DESCRIPTION',
                   'PROJECTLOCATIONID', 'DEPARTMENTNAME', 'DEPARTMENTID', 'PROJECTLOCATIONNAME','PCCUSTOMERID' , 'TOTALREVISEDPRICE', 'RETAINAGEBALANCE'];

        $select = array_merge($select, $this->getPCBLDimensionFields(true), $this->getPCBLDimensionNameFields());

        $renameFields = ["EXTERNALREFNO" => "PCBLEXTERNALREFNO", "DESCRIPTION" => "PCBLDESCRIPTION", "BILLINGTYPE" => "PCBLBILLINGTYPE", "BILLEDPRICE" => "PRIORAPPLICATIONAMT",
                        "PROJECTLOCATIONID" => "LOCATION", "PROJECTLOCATIONNAME" => "LOCATIONNAME", "DEPARTMENTID" => 'DEPARTMENT',
                         "PCCUSTOMERID" => "CUSTOMERID", "PCCUSTOMERNAME" => "CUSTOMERNAME", "TOTALREVISEDPRICE" => "CONTRACTLINEVALUE"];

        $filter = [
            'selects' => $select,
            'filters' => [[
                            ['PROJECTCONTRACTID', '=', $pcId],
                            ['PROJECTCONTRACTLINEID', '=', $pclId]
                          ]]
        ];

        $projectContractLine = $gManagerFactory->getManager('projectcontractline');
        $result = $projectContractLine->GetList($filter);

        $pairedVal = ["LOCATION" => "LOCATIONNAME", "DEPARTMENT" => "DEPARTMENTNAME",
                      "CUSTOMERID" => "CUSTOMERNAME"];
        $pairedVal = array_merge($pairedVal, $this->getPCBLDimensionNameFields(true));

        foreach ($result[0] ?? [] as $key => $value){
            if(array_key_exists($key , $renameFields)){
                $result[0][$renameFields[$key]] = $value;
                unset($result[0][$key]);
            }
        }

        foreach ($pairedVal as $id => $name){
            if(!isNullOrBlank($result[0][$id]) && !isNullOrBlank($result[0][$name])){
                $result[0][$id] = $result[0][$id] ."--". $result[0][$name];
                unset($result[0][$name]);
            }
        }

        $data = $result[0] ?? [];
        $data = array_map('htmlentities', $data);
        $json = json_encode($data);
        $xml = "<ProjectContractLineDetail>{$json}</ProjectContractLineDetail>";
        return $xml;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function preparePCB(array &$values): bool
    {
        $ok = true;
        $gErr = Globals::$g->gErr;

        $pcb = null;
        if (!isNullOrBlank($values['PROJECTCONTRACTID'])) {
            $pcb = $this->getPCB($values['PROJECTCONTRACTID']);
            $pcb = $pcb[$values['PROJECTCONTRACTID']];
        }

        if(empty($values['PREVIOUSRETAINAGEBALANCE']) && !empty($pcb["RETAINAGEBALANCE"]) && !$this->_isUpdate){
            $values['PREVIOUSRETAINAGEBALANCE'] = $pcb["RETAINAGEBALANCE"];
        }

        $orgContractAmt = $values['ORGCONTRACTAMT'] ?? 0.00;
        if (isNullOrBlank($values['ORGCONTRACTAMT']) && !isNullOrBlank($pcb['ORIGINALPRICE'])) {
            $orgContractAmt = $pcb['ORIGINALPRICE'];
        }
        $values['ORGCONTRACTAMT'] = $orgContractAmt;
        if (isNullOrBlank($values['RETCOMPLETEDAMT']) && !isNullOrBlank($pcb['TOTALRETAINAGEHELD'])) {
            $values['RETCOMPLETEDAMT'] = $pcb['TOTALRETAINAGEHELD'];
        }
        if (isNullOrBlank($values['BALANCEREMAINING']) && !isNullOrBlank($pcb['BALANCETOBILL'])) {
            $values['BALANCEREMAINING'] = $pcb['BALANCETOBILL'];
        }
        if(isset($values['COSummary']) && is_array($values['COSummary'])){
            $values['TCAPMADDITION'] = $values['COSummary'][0]['Additions'] ?? 0.00;
            $values['TCATMADDITION'] = $values['COSummary'][1]['Additions'] ?? 0.00;
            $values['TCAPMDEDUCTION'] = $values['COSummary'][0]['Deductions'] ?? 0.00;
            $values['TCATMDEDUCTION'] = $values['COSummary'][1]['Deductions'] ?? 0.00;
        }
        $fromGenerateInvoices = (($values['fromGenerateInvoices'] ?? false) || !isNullOrBlank($values['INVOICERUNKEY'])) ?? false;

        $projectContractKey = !isNullOrBlank($values['PROJECTCONTRACTKEY']) ? $values['PROJECTCONTRACTKEY'] : 0;
        $docKey = ($this->_isUpdate) ? $values['RECORDNO'] : -1;
        $pcbTotRetHeld = $this->getProjectContractTotalRetainageHeld($projectContractKey, $docKey);

        if($this->_isUpdate){
            $pcbTotRetHeld = $this->getProjectContractTotalRetainageHeldByIDs($projectContractKey, $docKey, $values);
        }
        $priorMonthsAddition = $values['TCAPMADDITION'] ?? 0.00;
        $thisMonthsAddition = $values['TCATMADDITION'] ?? 0.00;
        $priorMonthsDeduction = $values['TCAPMDEDUCTION'] ?? 0.00;
        $thisMonthsDeduction = $values['TCATMDEDUCTION'] ?? 0.00;
        $totalNetChangesAddition = ibcadd($priorMonthsAddition, $thisMonthsAddition);
        $values['TOTALNETCHANGESADDITION'] = $totalNetChangesAddition;
        $totalNetChangesDeduction = ibcadd($priorMonthsDeduction, $thisMonthsDeduction);
        $values['TOTALNETCHANGESDEDUCTION'] = $totalNetChangesDeduction;
        $totalNetChanges = ibcsub($totalNetChangesAddition, $totalNetChangesDeduction);
        $values['TOTALNETCHANGES'] = $totalNetChanges;
        $values['NETCHANGES'] = $totalNetChanges;
        $revisedContractAmt = ibcadd($orgContractAmt, $totalNetChanges);
        $values['REVISEDCONTRACTAMT'] = $fromGenerateInvoices ? $revisedContractAmt : $pcb['TOTALREVISEDPRICE'];
        $totalCompletedToDate = 0.00;
        $totalRetainage = 0.00;
        $hasPCBL = false;
        $retFromCompletedAmt = 0.00;
        $retFromStoredMaterials = 0.00;
        $totRetFromStoredMaterials = 0.00;
        $trxAmtRet = 0.00;
        $priorApplications = [];
        $retainageBilled = 0.00;
        $retainageBalance = 0.00;
        $groupEntryByPCL = [];
        //get project contract line details
        $projectContractLines = $this->getProjectContractLines($values['PROJECTCONTRACTID']);

        // We only want to include PRIORAPPLICATIONAMT once from each Project Contract Line being billed.
        foreach($values['ENTRIES'] as $entry) {
            if (!key_exists($entry['PROJECTCONTRACTLINEID'], $priorApplications)) {
                $priorApplications[$entry['PROJECTCONTRACTLINEID']] = true;
                if (isset($entry['PRIORAPPLICATIONAMT'])) {
                    $totalCompletedToDate += floatval($entry['PRIORAPPLICATIONAMT']);
                }else if(isset($projectContractLines[$entry['PROJECTCONTRACTLINEID']]) && isset($projectContractLines[$entry['PROJECTCONTRACTLINEID']]['BILLEDPRICE'])){
                    $totalCompletedToDate += floatval($projectContractLines[$entry['PROJECTCONTRACTLINEID']]['BILLEDPRICE']);
                }
            }
        }

        if(!empty($pcb["BILLEDPRICE"])){
            $totalCompletedToDate = $pcb["BILLEDPRICE"];
            if($this->_isUpdate){
                $totalCompletedToDate = $this->getPreviousTotalCompletedToDate($values);
            }
        }

        foreach($values['ENTRIES'] as $key => $entry){
            if (empty($entry['PROJECTCONTRACTKEY']) && empty($entry['PROJECTCONTRACTLINEKEY'])) {
                continue;
            }
            [$projectContractId] = explode('--', $values['PROJECTCONTRACTID']);
            [$projectContractLineId] = explode('--', $entry['PROJECTCONTRACTLINEID']);
            $pcbentry = $projectContractLines[$entry['PROJECTCONTRACTLINEID']];

            if (isNullOrBlank($entry['PCBLDESCRIPTION']) && !isNullOrBlank($pcbentry['DESCRIPTION'])) {
                $values['ENTRIES'][$key]['PCBLDESCRIPTION'] = $pcbentry['DESCRIPTION'];
            }
            //if the request is from API, fetch and update project contract line details
            if(!empty($values['PROJECTCONTRACTID']) && !empty($entry['PROJECTCONTRACTLINEID']) && !$this->_isUpdate){
                if(!empty($pcbentry)){
                    $values['ENTRIES'][$key]['PCBLEXTERNALREFNO'] = $pcbentry['EXTERNALREFNO'] ?? '';
                    $values['ENTRIES'][$key]['PCBLDESCRIPTION'] = $pcbentry['DESCRIPTION'] ?? '';
                    $values['ENTRIES'][$key]['PCBLBILLINGTYPE'] = $pcbentry['BILLINGTYPE'] ?? '';
                    $values['ENTRIES'][$key]['CONTRACTLINEVALUE'] = $entry['CONTRACTLINEVALUE'] = $pcbentry['TOTALREVISEDPRICE'] ?? 0.00;
                    $values['ENTRIES'][$key]['PRIORAPPLICATIONAMT'] = $entry['PRIORAPPLICATIONAMT'] = $pcbentry['BILLEDPRICE'] ?? 0.00;
                    $values['ENTRIES'][$key]['RETAINAGEBALANCE'] = $values['ENTRIES'][$key]['PREVIOUSRETAINAGEBALANCE'] = $pcbentry['RETAINAGEBALANCE'] ?? 0.00;
                }
            }
            $lineNo = $entry['LINE_NO'] + 1;

            $contractLineAmt = empty($entry['CONTRACTLINEVALUE']) ? 0.00 : $entry['CONTRACTLINEVALUE'];
            $amtFromPriorApplication = empty($entry['PRIORAPPLICATIONAMT']) ? 0.00 : $entry['PRIORAPPLICATIONAMT'];
            $completedThisPeriod = empty($entry['COMPLETEDTHISPERIOD']) ? 0.00 : $entry['COMPLETEDTHISPERIOD'];
            $storedMaterials = empty($entry['STOREDMATERIALS']) ? 0.00 : $entry['STOREDMATERIALS'];

            if($entry['TRX_VALUE'] != (ibcadd($completedThisPeriod, $storedMaterials)) && (empty($entry['ISRETAINAGERELEASE']) || $entry['ISRETAINAGERELEASE'] == 'false') ){
                $gErr->addIAError(number: 'CRE-1512', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);

                return false;
            }
            if ($storedMaterials == 0 && $completedThisPeriod == 0) {
                $completedThisPeriod = $entry['TRX_VALUE'];
            }
            $retFromStoredMaterials = ibcdiv(ibcmul($storedMaterials, $entry['RETAINAGEPERCENTAGE']), 100);
            $amountRetained = $entry['AMOUNTRETAINED'] ?? 0.00;
            $totalRetainage = ibcadd($totalRetainage, $amountRetained);
            $retFromCompletedAmt = ibcadd($retFromCompletedAmt, ibcsub($amountRetained, $retFromStoredMaterials));
            $totRetFromStoredMaterials += $retFromStoredMaterials;
            if(!empty($entry["ISRETAINAGERELEASE"]) && $entry["ISRETAINAGERELEASE"] == "true"){
                $totalCompletedToDate_entry = $amtFromPriorApplication;
            }else{
                $totalCompletedToDate_entry = ibcadd(ibcadd($amtFromPriorApplication, $completedThisPeriod), $storedMaterials);
            }
            $values['ENTRIES'][$key]['TOTALCOMPLETEDTODATE'] = $totalCompletedToDate_entry;
            if(empty($entry["ISRETAINAGERELEASE"]) || $entry["ISRETAINAGERELEASE"] == "false") {
                $totalCompletedToDate += ibcadd($completedThisPeriod, $storedMaterials);
            }
            $percentCompletedToDate = ($contractLineAmt == 0) ? 0: ibcmul(ibcdiv($totalCompletedToDate_entry, $contractLineAmt, 4, true),100, 2, true);
            $values['ENTRIES'][$key]['PERCENTCOMPLETEDTODATE'] = $percentCompletedToDate;
            $balanceRemaining = ibcsub($contractLineAmt, $totalCompletedToDate_entry);
            $values['ENTRIES'][$key]['BALANCEREMAINING'] = $balanceRemaining;
            $trxAmtRet = ibcadd($trxAmtRet, $entry['TRX_AMOUNTRETAINED']);
            if(CRESetupManager::isRetainageBillingEnabled() && $entry["ISRETAINAGERELEASE"] == "true"){
                if(!$this->validateProjectContractRetainageReleseBilling($entry)){
                    return false;
                }
                $retainageBilled = ibcadd($retainageBilled, $entry["RETAINAGETOBILL"] ?? 0.00);
            }
            if(!$this->pcblDimensionsValidation($entry)){
                return false;
            }
            $hasPCBL = true;

            if(CRESetupManager::isRetainageBillingEnabled() && $fromGenerateInvoices && $this->_entity != 'arinvoice'){
                if((empty($entry["ISRETAINAGERELEASE"]) || $entry["ISRETAINAGERELEASE"] == "false") && isset($groupEntryByPCL[$projectContractLineId])){
                    array_unshift($groupEntryByPCL[$projectContractLineId], $values['ENTRIES'][$key]);
                }else{
                    $groupEntryByPCL[$projectContractLineId][] = $values['ENTRIES'][$key];
                }
            }
        }

        if(!empty($values['fromGenerateInvoices']) && $values['fromGenerateInvoices'] == true && $this->_entity != 'arinvoice'){
            $this->handlePCBLines($groupEntryByPCL);
        }

        if(CRESetupManager::isRetainageBillingEnabled() && $fromGenerateInvoices && $this->_entity != 'arinvoice'){
            unset($values['ENTRIES']);
            $idx = 0;

            foreach ($groupEntryByPCL as $lines){
                for($i=0; $i < count($lines); $i++) {
                    $values['ENTRIES'][$idx] = $lines[$i];
                    $values['ENTRIES'][$idx]['L_NO'] = $idx;
                    $values['ENTRIES'][$idx]['LINENO'] = $idx;
                    $values['ENTRIES'][$idx]['LINE_NO'] = $idx;
                    $values['ENTRIES'][$idx]['LINEKEY'] = $idx;
                    unset($values['ENTRIES'][$idx]['TAXDETAILS']);
                    $idx++;
                }
            }
            $docMgr = Globals::$g->gManagerFactory->getManager('document');
            $isCalcTaxOnRelease = $docMgr->isCalcTaxReleaseRetainageEnabled($values);
            if($isCalcTaxOnRelease){
                unset($values['SUBTOTALS']);
                $this->PrepareSubTotalsValues($values, $getTaxRequest, $entityTaxable);
            }
        }
        if($this->_entity != 'arinvoice'){
            $this->handleBillingFields($values);
            $this->recalculateLineRetainageBalance($values);
        }

        $totalRetainage += $pcbTotRetHeld;
        $retFromCompletedAmt += $pcbTotRetHeld;

        // Set the ProjectContract on each Subtotal.
        foreach ($values['SUBTOTALS'] as $key => $subtotal) {
            $values['SUBTOTALS'][$key]['PROJECTCONTRACTKEY'] = $values['PROJECTCONTRACTKEY'];
            $values['SUBTOTALS'][$key]['PROJECTCONTRACTID'] = $values['PROJECTCONTRACTID'];
            if(!empty($values['ITEMS'][$subtotal['DOC_LINENO']]) && empty($values['SUBTOTALS'][$key]['PROJECTCONTRACTLINEID']) && !empty($values['ITEMS'][$subtotal['DOC_LINENO']]['PROJECTCONTRACTLINEID'])){
                $values['SUBTOTALS'][$key]['PROJECTCONTRACTLINEID'] = $values['ITEMS'][$subtotal['DOC_LINENO']]['PROJECTCONTRACTLINEID'];
                $values['SUBTOTALS'][$key]['PROJECTCONTRACTLINEKEY'] = $values['ITEMS'][$subtotal['DOC_LINENO']]['PROJECTCONTRACTLINEKEY'] ?? null;
            }
        }

        if ($hasPCBL && (iround($totalRetainage, 2) != (ibcadd($retFromCompletedAmt, $totRetFromStoredMaterials, 2, true))) && !$fromGenerateInvoices) {
            $gErr->addIAError(number: 'CRE-1513', source: __FILE__ . ':' . __LINE__);
            return false;
        }
        $values['TOTALCOMPLETEDTODATE'] = $totalCompletedToDate;
        $values['TOTALRETAINAGE'] = $totalRetainage;
        $totalEarnedLessRetainage = ibcsub($totalCompletedToDate, $totalRetainage);
        $values['TOTALEARNEDLESSRET'] = $totalEarnedLessRetainage;

        if (!$this->_isUpdate) {
            $lessPriorApplication = ibcadd(ibcsub($pcb['BILLEDPRICE'] ?? 0, $pcb['TOTALRETAINAGEHELD'] ?? 0), $pcb['TOTALRETAINAGERELEASED'] ?? 0);
            $values['LESSPRIORAPPLICATION'] = $lessPriorApplication;
        }
        $currentAmountDue = ibcsub($values['TRX_TOTAL'] ?? 0.00, $trxAmtRet);
        $values['CURRENTAMTDUE'] = $currentAmountDue;

        $this->calculateBalanceToFinish($values);

        $preRetainageBalance = $values['PREVIOUSRETAINAGEBALANCE'] ?? 0;
        $totRetainageOnThisInvoice = $trxAmtRet;

        $values["RETAINAGEBALANCE"] =  ibcsub(ibcadd($preRetainageBalance, $totRetainageOnThisInvoice), $retainageBilled);
        $values["RETAINAGEBILLED"] =   $retainageBilled;

        $ok = $ok && $this->translateAndSetKeyForObject($values, 'contact', 'ARCHITECT', 'ARCHITECTKEY', 'contact', __FILE__.'.'.__LINE__);

        return $ok;
    }

    /**
     * @param array $entry
     *
     * @return bool
     */
    private function pcblDimensionsValidation(array $entry): bool
    {
        // This validation is only for PCN_TRANSITEMS.  Other trans types (like those coming from a PGI run) do not
        // require this validaiton.
        $gErr = Globals::$g->gErr;
        if ($entry['SOURCE_LINETYPE'] != 'PCNTRANSITEMS') {
            return true;
        }

        $ok = true;
        $dimensionFields = $this->getPCBLDimensionFields();
        $pcblDetails = $this->getProjectContractLines($entry['PROJECTCONTRACTID'])[$entry['PROJECTCONTRACTLINEID']];
        foreach ($dimensionFields as $dim){
            $dimField = $dim['path'];
            if(isset($entry[$dimField]) && !isNullOrBlank($entry[$dimField])){
                [$dimValue] = explode('--', $entry[$dimField]);
                if(isset($pcblDetails[$dimField]) && $dimValue != $pcblDetails[$dimField]){
                    $dimName = $dim['fullname'];
                    $gErr->addIAError(number: 'CRE-1514', source: __FILE__ . ':' . __LINE__, desc1PHs: ['DIMNAME' => $dimName, 'PROJECTCONTRACTLINEID' => $entry['PROJECTCONTRACTLINEID']]);

                    return false;
                }
            }
        }

        return $ok;
    }

    /**
     * @param bool $onlyPath
     *
     * @return array
     */
    private function getPCBLDimensionFields($onlyPath = false): array
    {
        if(!$this->_pcblDimension){
            $mgr = Globals::$g->gManagerFactory->getManager("projectcontractline");
            $dimensionFields = $mgr->GetDimensionFields();
            $this->_pcblDimension = $dimensionFields;
        }
        if($onlyPath){
            return array_column($this->_pcblDimension, 'path');
        }

        return $this->_pcblDimension;
    }

    /**
     *
     * To get dimension name fields
     * @param  bool $paired
     * @return array
     */
    private function getPCBLDimensionNameFields($paired = false): array
    {
        if(!$this->_pcblDimensionName){
            $mgr = Globals::$g->gManagerFactory->getManager("projectcontractline");
            $dimensionFields = $mgr->GetDimensionFields();
            foreach($dimensionFields as $dim){
                if(isset($dim['dimNameField']) && is_array($dim['dimNameField'])){
                    $this->_pcblDimensionName[$dim['path']] = array_keys($dim['dimNameField'])[0];
                }
            }
        }
        return (($paired) ? $this->_pcblDimensionName: array_values($this->_pcblDimensionName) );
    }

    /**
     * @param array $values
     * @param array $existingValues
     *
     * @return bool
     */
    public function API_ValidatePCBObject(&$values, $existingValues): bool
    {

        $gErr = Globals::$g->gErr;
        $isCreate = (is_null($existingValues)) ? true : false;
        if($this->isPCBEnabled($values)){
            $pcbEntryReadOnlyFields = array_flip($this->getPCBEntryReadOnlyFields());
            $pcbEntryFields = array_flip($this->getPCBEntryFields());
            $lineMgr = Globals::$g->gManagerFactory->getManager('sodocumententry');
            $itemsAlias = "SODOCUMENTENTRIES";
            $itemAlias = "SODOCUMENTENTRY";
            $entries = $values[$itemsAlias][$itemAlias]??$values[$itemAlias];
            foreach ($entries as $entry){
                $pcbIntersect = array_intersect_key($entry, $pcbEntryReadOnlyFields);
                foreach ( $pcbIntersect as $nextField => $nextValue) {
                    $typeInfo = &$lineMgr->GetFieldInfo(strtoupper($nextField));
                    if (isset($typeInfo)) {

                        //  Create-specific checks
                        if ($isCreate) {
                            if (($typeInfo['noapiadd'] ?? null) == 1) {
                                $gErr->addIAError(number: 'CRE-1515', source: __FILE__ . ':' . __LINE__, desc1PHs: ['NEXTFIELD' => $nextField]);
                                return false;
                            }
                        }

                        //  Create-specific checks
                        if (!$isCreate) {
                            if ($typeInfo['noapiset'] == 1) {
                                $gErr->addIAError(number: 'CRE-1515', source: __FILE__ . ':' . __LINE__, desc1PHs: ['NEXTFIELD' => $nextField]);
                                return false;
                            }
                        }
                    }
                }
                if ((!isset($entry['PROJECTCONTRACTID']) || $entry['PROJECTCONTRACTID'] == "")
                    && (!isset($entry['PROJECTCONTRACTLINEID']) || $entry['PROJECTCONTRACTLINEID'] == "")) {
                    $pcbIntersect = array_intersect_key($entry, $pcbEntryFields);
                    foreach ($pcbIntersect as $pcbI){
                        $gErr->addIAError(number: 'CRE-1516', source: __FILE__ . ':' . __LINE__);
                        return false;
                    }
                }
            }
        }

        return true;
    }

    /**
     * @param string $mod
     * @param array $docpar
     *
     * @return bool
     */
    public function validateRecurDocForPCB($mod, $docpar)
    {
        $gErr = Globals::$g->gErr;
        if ($mod == 'so') {
            $enabledPCB = isNullOrBlank($docpar['ENABLECONTRACTBILLING']) ? "false" : $docpar['ENABLECONTRACTBILLING'];
            if ($enabledPCB == 'true') {
                $gErr->addIAError(number: 'CRE-1517', source: __FILE__ . ':' . __LINE__);
                return false;
            }
        }
        return true;
    }

    /**
     * @param array $params
     * @return string
     */
    public function FetchPCBInvoiceTemplate(array $params): string
    {
        $isPCB = $params['pcb'];
        $docpars = $this->getFilteredPCBInvoices($isPCB);
        $data = array_map('htmlentities', $docpars);
        $json = json_encode($data);
        $xml = "<PCBFiltered>{$json}</PCBFiltered>";
        return $xml;
    }

    /**
     * Cache for invoices
     * @param string $isPCB
     * @return array
     */

    protected function getFilteredPCBInvoices(string $isPCB): array
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $soDocParMgr = $gManagerFactory->getManager('sodocumentparams');
        $filter = ($isPCB === 'true') ? 'PCB' : 'NonPCB';

        if (!$this->_projectContractInvoicesCache) {
            if ($filter === 'PCB') {
                $querySpec = array(
                    'selects' => array('RECORDNO', 'DOCID', 'DOCCLASS', 'CATEGORY', 'ENABLECONTRACTBILLING', 'USERPERM'),
                    'filters' => array(
                        array(
                            array('STATUS', '=', 'active'),
                            array('DOCCLASS', 'IN', array('Invoice', 'Adjustment')),
                            array('CATEGORY', '=', 'Invoice'),
                            array('ENABLECONTRACTBILLING', '=', true),
                        )
                    ),
                );

                $resultSet = $soDocParMgr->GetList($querySpec);

                foreach ($resultSet as &$res) {
                    $res['USERPERM'] = ($res['USERPERM'] == 'true' ? 'T' : 'F');
                }

                // filter the result, though intacct user sees everything.
                /** @noinspection PhpUnusedLocalVariableInspection */
                $authorizedDocPars = array();
                if (!CheckAuthorization(GetOperationId('inv/activities/document/nofilters'))) {
                    $authorizedDocPars = upermFilterResult($resultSet, GetMyUserid());
                } else {
                    // hack: "inv/activities/document/nofilters" permission is given
                    // for free only to intacct slidein users
                    $authorizedDocPars = $resultSet;
                }
                $docpars = array();
                foreach ($authorizedDocPars as $row) {
                    $docpars[] = $row['DOCID'];
                }

            } else {
                $expenseMrg = $gManagerFactory->getManager('expensebilling');
                $docpars = $expenseMrg->getInvoiceDefinitions();
            }
            $this->_projectContractInvoicesCache[$filter] = $docpars;
        }
        return $this->_projectContractInvoicesCache[$filter];
    }

    /**
     * Validate project contract line maximum billing amount respective of billing type
     * @param array $values
     * @return bool
     */
    private function validatePCBMaximumBilling(array $values): bool
    {
        $ok = true;
        $projectContractlineData = [];
        if(isset($values['ENTRIES']) && is_array($values['ENTRIES']) && !empty($values['ENTRIES']))
        {
            foreach($values['ENTRIES'] as $entry)
            {
                if(isset($entry['PROJECTCONTRACTID']) && isset($entry['PROJECTCONTRACTLINEID']) && !isNullOrBlank($entry['PROJECTCONTRACTID']) && !isNullOrBlank($entry['PROJECTCONTRACTLINEID']))
                {
                    // skipping the retainage release lines
                    if(isset($entry['ISRETAINAGERELEASE']) && $entry['ISRETAINAGERELEASE'] == "true"){
                        continue;
                    }
                    $oldTrxVal = 0;
                    $oldState = !empty($values["EXISTING_DOC"]["STATE"]) ? $values["EXISTING_DOC"]["STATE"] : $values["STATE"];
                    if($this->_isUpdate && $oldState != self::DRAFT_STATE){
                        $oldPCLEntry = $this->getPreviousPCLEntry($values['EXISTING_ENTRIES'] ?? [], $entry);
                        $oldTrxVal = $oldPCLEntry['TRX_VALUE'] ?? 0;
                    }
                    if(!isset($projectContractlineData[$entry['PROJECTCONTRACTLINEID']]))
                    {
                        $pclData = $this->getProjectContractLines($entry['PROJECTCONTRACTID'])[$entry['PROJECTCONTRACTLINEID']];
                        $billedPrice = ibcsub($pclData['BILLEDPRICE'], $oldTrxVal);
                        $projectContractlineData[$entry['PROJECTCONTRACTLINEID']] = [
                            'TRX_VALUE' => $entry['TRX_VALUE'],
                            'TOTAL_BILLEDPRICE' => ibcadd($entry['TRX_VALUE'] ?? 0, $billedPrice),
                            'BILLINGTYPE' => $pclData['BILLINGTYPE'],
                            'MAXIMUMBILLING' => $pclData['MAXIMUMBILLING'],
                            'MAXIMUMBILLINGAMOUNT' => $pclData['MAXIMUMBILLINGAMOUNT'],
                            'TOTALREVISEDPRICE' => $pclData['TOTALREVISEDPRICE'],
                            'BILLEDPRICE' => $pclData['BILLEDPRICE'],
                            'LINE_NO' => $entry['LINE_NO'] +1,
                        ];
                    } else
                    {
                        $billedPrice = ibcsub($projectContractlineData[$entry['PROJECTCONTRACTLINEID']]['BILLEDPRICE'], $oldTrxVal);
                        $totalTrxValue = ibcadd($projectContractlineData[$entry['PROJECTCONTRACTLINEID']]['TRX_VALUE'], $entry['TRX_VALUE']);
                        $projectContractlineData[$entry['PROJECTCONTRACTLINEID']]['TRX_VALUE'] = $totalTrxValue;
                        $projectContractlineData[$entry['PROJECTCONTRACTLINEID']]['TOTAL_BILLEDPRICE'] = ibcadd($projectContractlineData[$entry['PROJECTCONTRACTLINEID']]['TOTAL_BILLEDPRICE'], $entry['TRX_VALUE']);
                    }
                }
            }

            if(!empty($projectContractlineData) && $this->_entity == "sodocument"){
                foreach($projectContractlineData as $pclId => $pclData){
                    // for progress billing Maximum billing always Total revised price
                    $totalBilledPrice = isNullOrBlank($pclData['TOTAL_BILLEDPRICE']) ? 0.00 : $pclData['TOTAL_BILLEDPRICE'] ;
                    $totalRevisedPrice = isNullOrBlank($pclData['TOTALREVISEDPRICE']) ? 0.00 : $pclData['TOTALREVISEDPRICE'] ;
                    $maxBillAmt = isNullOrBlank($pclData['MAXIMUMBILLINGAMOUNT']) ? 0.00 : $pclData['MAXIMUMBILLINGAMOUNT'] ;
                    $totalRevisedPriceSign = $totalRevisedPrice <=> 0;
                    $maxBillAmtSign = $maxBillAmt <=> 0;
                    $totalBilledPriceSign = $totalBilledPrice <=> 0;

                    if ( in_array($pclData['BILLINGTYPE'] , ['Progress', 'TM']) && $pclData['MAXIMUMBILLING'] == 'Total revised price'  &&
                         $totalBilledPriceSign != 0 && $totalRevisedPriceSign != 0 && ($totalRevisedPriceSign != $totalBilledPriceSign ||
                       (($totalRevisedPriceSign != -1 && $totalRevisedPrice < $totalBilledPrice) || ($totalRevisedPriceSign == -1 && $totalRevisedPrice > $totalBilledPrice)))){
                        $ok = false;
                        $pclineId= $pclId;
                        break;
                    } else if($pclData['BILLINGTYPE'] == 'TM'){ // validate time and material line
                        if($pclData['MAXIMUMBILLING'] == 'No maximum'){
                            $ok = true;
                        } else if($pclData['MAXIMUMBILLING'] == 'Specified amount' &&
                                  $totalBilledPriceSign != 0 && $maxBillAmtSign != 0 && ($maxBillAmtSign != $totalBilledPriceSign ||
                                (($maxBillAmtSign != -1 && $maxBillAmt < $totalBilledPrice) || ($maxBillAmtSign == -1 && $maxBillAmt > $totalBilledPrice)))){
                            $ok = false;
                            $pclineId= $pclId;
                            break;
                        }
                    }
                }
            }

            if(!$ok){
                Globals::$g->gErr->addIAError(number: 'CRE-1518', source: __FILE__ . ':' . __LINE__, desc1PHs: ['PCLINEID' => $pclineId]);
            }
        }

        return $ok;
    }

    /**
     * To prefill pcl values for API
     * @param array $entry
     */
    public function prefillPCBLDetails(&$entry){

        [$pcId] = explode("--", $entry['PROJECTCONTRACTID']);
        [$pclId] = explode("--", $entry['PROJECTCONTRACTLINEID']);

        // $pcbentry = $this->getPCBEntries($pcId."--".$pclId) ?? [];
        $pcbentry = $this->getProjectContractLines($pcId)[$pclId] ?? [];

        if($pcbentry){
            if(isNullOrBlank($entry['PCBLBILLINGTYPE'])){
                $entry['PCBLBILLINGTYPE'] = $pcbentry['BILLINGTYPE'] ?? "";
            }
        }


    }

    /**
     * To get total retainage held value for the project contract
     * @param string|int $projectContractKey
     * @param string|int $currentDocKey
     *
     * @return float|mixed|string
     */
    public function getProjectContractTotalRetainageHeld($projectContractKey, $currentDocKey = -1){
        $cny    =   GetMyCompany();
        $ret    =   $this->DoQuery('QRY_SODOCUMENT_GET_PROJECTTOTALRETAINAGEHELD', array ($cny, $projectContractKey, $currentDocKey));
        if($ret && $ret[0]){
            return $ret[0]['PROJECTTOTALRETAINAGEHELD'] ?? 0.00;
        }
        return 0.00;
    }

    /**
     * To get total retainage held value for the project contract
     * @param string|int $projectContractKey
     * @param string|int $currentDocKey
     * @param array $values
     *
     * @return float|mixed|string
     */
    public function getProjectContractTotalRetainageHeldByIDs($projectContractKey, $currentDocKey = -1, array $values = [])
    {
        $ret = 0;

        $cny = GetMyCompany();
        $response = $this->DoQuery('QRY_SODOCUMENT_GET_PROJECTTOTALRETAINAGEHELDBYID', array($cny, $projectContractKey, $currentDocKey));
        foreach ($response as $row) {
            if ($row['DOCHDRKEY'] < $currentDocKey) {
                $ret += $row['TRX_AMOUNTRETAINED'];
            }
        }
        return $ret;
    }

    /**
     * get the old line values for the project contract line
     * @param array $oldEntries
     * @param array $currentLine
     *
     * @return array
     */
    private function getPreviousPCLEntry($oldEntries, $currentLine){
        // need to handle in better way especially when duplicate projectcontractlineid exist
        [$pcId] = explode("--", $currentLine['PROJECTCONTRACTID']);
        [$pclId] = explode("--", $currentLine['PROJECTCONTRACTLINEID']);
        if($oldEntries){
            foreach ($oldEntries as $oldentry){
                [$oldPcId] = explode("--", $oldentry['PROJECTCONTRACTID']);
                [$oldPclId] = explode("--", $oldentry['PROJECTCONTRACTLINEID']);
                if($pcId == $oldPcId && $pclId == $oldPclId){
                    return $oldentry;
                }
            }
        }
        return [];
    }

    /**
     * check invoice is generating from PGI and invocie by is project contract or not
     * @param array $values
     * @return bool
     */
    private function isItFromPGIProjectContract(array $values): bool{
        $ok = true;
        if(isset($values['fromGenerateInvoices']) && $values['fromGenerateInvoices'] == 'true'){
            if(isset($values['INVOICEBY']) && $values['INVOICEBY'] != 'Project contract'){
                $ok = false;
            }
        }
        return $ok;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    private function validateRetainageRelease($values){
        $retainageToBillByPCL = $this->groupRetainageToBillByPC($values);
        foreach ($retainageToBillByPCL as $id => $entry){
            [$projectContractId, $projectContractLineId] = explode("--", $id);
            $pcl = $this->getProjectContractLines($projectContractId)[$projectContractLineId] ?? [];
            if($pcl){
                $retainageBalance = $pcl['RETAINAGEBALANCE'] ?? 0;
                if($this->_isUpdate){
                    $retainageBalance = ibcadd($retainageBalance, $entry['EXISTING_RETAINAGETOBILL']);
                }
                // $retainageBalance = ibcadd($retainageBalance, $entry["TRX_AMOUNTRETAINED"]); // To add currenct invoice for validation
                $retainageToBill = isNullOrBlank($entry["RETAINAGETOBILL"]) ? 0.00 : $entry["RETAINAGETOBILL"];
                $retainageBalanceSign = $retainageBalance <=> 0;
                $retainageToBillSign = $retainageToBill <=> 0;
                if($retainageToBillSign != 0 && ($retainageBalanceSign != $retainageToBillSign || (($retainageBalanceSign != -1 && $retainageBalance < $retainageToBill) || ($retainageBalanceSign == -1 && $retainageBalance > $retainageToBill)))){
                    Globals::$g->gErr->addIAError(number: 'CRE-1519', source: __FILE__ . ':' . __LINE__);
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * @param String $ent
     * @param array $fields
     * @param array $orders
     * @param array $groupBy
     * @param  array $columnaliases
     * @param array $groupingFieldsList
     *
     * @return void
     */
    private function processPCBSummarizeForDocTemp($ent, &$fields, &$orders, &$groupBy, $columnaliases, $groupingFieldsList  ){
        $pcbGroupFields = $this->getPCBGroupFieldsForDocTemp();
        $orderFields = array_column($orders,"0");
        $isPCBFieldExist = false;
        $groupingFieldsList = $groupingFieldsList ?? [];
        foreach ($pcbGroupFields as $pcbField){
            $validate = array_search($pcbField, $groupingFieldsList);
            if($validate == false){
                continue;
            }
            $idx = array_search($pcbField, $fields);
            if($idx != false){
                $fld = [$ent.".".$pcbField];
                switch ($pcbField){
                    case "CONTRACTLINEVALUE":
                        $func = "avg(nvl(\${1},0))";
                        break;
                    case "PRIORAPPLICATIONAMT":
                        $func = "avg(nvl(\${1},0))";
                        break;
                    case "COMPLETEDTHISPERIOD" :
                        $func = "sum(nvl(\${1},0))";
                        break;
                    case "STOREDMATERIALS" :
                        $func = "sum(nvl(\${1},0))";
                        break;
                    case "TOTALCOMPLETEDTODATE":
                        $fld[0] = $ent.".PRIORAPPLICATIONAMT";
                        $fld[1] = $ent.".COMPLETEDTHISPERIOD";
                        $fld[2] = $ent.".STOREDMATERIALS";
                        $func = "avg(nvl(\${1},0))+sum(nvl(\${2},0)) +sum(nvl(\${3},0))";
                        break;
                    default:
                        continue(2);
                }
                $fields[$idx] = [
                    'fields' => $fld,
                    'function' => $func,
                ];
                $orderIdx = array_search($pcbField, $orderFields);
                if($orderIdx != false){
                    unset($orders[$orderIdx]);
                }
                $grpIdx = array_search($pcbField, $groupBy);
                if($grpIdx != false){
                    unset($groupBy[$grpIdx]);
                }
                $isPCBFieldExist = true;
            }
        }
        if($isPCBFieldExist){
            $qtyIdx = array_search('UIQTY', $columnaliases);
            if($qtyIdx != false){
                $fld[0] = "PROJECTCONTRACTLINE.BILLINGTYPE";
                $fld[1] = $ent.".UIQTY";
                $func = "( CASE \${1} WHEN 'T' THEN SUM(nvl(\${2}, 0)) WHEN 'P' THEN AVG(nvl(\${2}, 0))  ELSE 0 END )";
                $fields[$qtyIdx] = [
                    'fields' => $fld,
                    'function' => $func,
                ];
                if(!in_array("PROJECTCONTRACTLINE.BILLINGTYPE", $groupBy)){
                    $groupBy[] = "PROJECTCONTRACTLINE.BILLINGTYPE";
                }
            }
        }
    }

    /**
     * @param array $values
     *
     * @return array
     */
    private function groupRetainageToBillByPC($values){
        $retainageToBill = [];
        foreach ($values['ENTRIES'] as $entry){
            if(!empty($entry['PROJECTCONTRACTID']) && !empty($entry['PROJECTCONTRACTLINEID']) && !empty($entry["ISRETAINAGERELEASE"]) && $entry["ISRETAINAGERELEASE"] == "true"){
                [$pcID] = explode("--", $entry['PROJECTCONTRACTID']);
                [$pclID] = explode("--", $entry['PROJECTCONTRACTLINEID']);
                $id = $pcID."--".$pclID;
                $toBill = isNullOrBlank($entry["RETAINAGETOBILL"]) ? 0.00 : $entry["RETAINAGETOBILL"];
                $trxAmtRetained = isNullOrBlank($entry["TRX_AMOUNTRETAINED"]) ? 0.00 : $entry["TRX_AMOUNTRETAINED"];
                if(empty($retainageToBill[$id])){
                    $retainageToBill[$id]['RETAINAGETOBILL'] = $toBill;
                    $retainageToBill[$id]['TRX_AMOUNTRETAINED'] = $trxAmtRetained;
                }else{
                    $retainageToBill[$id]['RETAINAGETOBILL'] = ibcadd($retainageToBill[$id]['RETAINAGETOBILL'], $toBill);
                    $retainageToBill[$id]['TRX_AMOUNTRETAINED'] = ibcadd($retainageToBill[$id]['TRX_AMOUNTRETAINED'], $trxAmtRetained);
                }

                $retainageToBill[$id]['RETAINAGEBALANCE'] = $entry["RETAINAGEBALANCE"];
            }
        }

        foreach ($values["EXISTING_ENTRIES"] as $existingEntry){
            if(!empty($existingEntry['PROJECTCONTRACTID']) && !empty($existingEntry['PROJECTCONTRACTLINEID']) && !empty($existingEntry["ISRETAINAGERELEASE"]) && $existingEntry["ISRETAINAGERELEASE"] == "true"){
                [$pcID] = explode("--", $existingEntry['PROJECTCONTRACTID']);
                [$pclID] = explode("--", $existingEntry['PROJECTCONTRACTLINEID']);
                $id = $pcID."--".$pclID;
                $toBill = isNullOrBlank($existingEntry["RETAINAGETOBILL"]) ? 0.00 : $existingEntry["RETAINAGETOBILL"];
                if(empty($retainageToBill[$id]['EXISTING_RETAINAGETOBILL'])){
                    $retainageToBill[$id]['EXISTING_RETAINAGETOBILL'] = $toBill;
                }else{
                    $retainageToBill[$id]['EXISTING_RETAINAGETOBILL'] = ibcadd($retainageToBill[$id]['EXISTING_RETAINAGETOBILL'], $toBill);
                }
            }
        }
        return $retainageToBill;
    }

    /**
     * validate project contract retainage release billing
     * @param array $entry
     * @return bool
     */
    private function validateProjectContractRetainageReleseBilling(array $entry): bool{
        $ok = true;
        $gErr = Globals::$g->gErr;
        $lineNo = $entry['LINE_NO'] + 1;
        if(!empty(floatval($entry['COMPLETEDTHISPERIOD'])) || !empty(floatval($entry['STOREDMATERIALS'])) || !empty(floatval($entry['RETAINAGEPERCENTAGE']))){
            $gErr->addIAError(number: 'CRE-1520', source: __FILE__ . ':' . __LINE__);
            $ok = false;
        }

        if(floatval($entry['RETAINAGETOBILL']) != floatval($entry["TRX_PRICE"])){
            $gErr->addIAError(number: 'CRE-1521', source: __FILE__ . ':' . __LINE__, desc1PHs: ['LINENO' => $lineNo]);
            $ok = false;
        }
        return $ok;
    }

    /**
     * @param array $obj
     *
     * @return bool
     * @throws Exception
     */
    private function isProjectContractEnabledInDoc($obj){
        if(empty($obj['_DOCPAR']) && !empty($obj['DOCPARID'])){
            $docparMgr = $this->get_docpar_manager();
            $obj['_DOCPAR'] = $docparMgr->GetBaseLatest($obj['DOCPARID']);
        }
        return CRESetupManager::isRetainageBillingEnabled() && (!empty($obj['_DOCPAR']["ENABLECONTRACTBILLING"]) ? $obj['_DOCPAR']["ENABLECONTRACTBILLING"]: "false") == "true";
    }

    /**
     * @return array
     */
    private function getPCBGroupFieldsForDocTemp(){
        return  ["CONTRACTLINEVALUE", "PRIORAPPLICATIONAMT", "COMPLETEDTHISPERIOD", "STOREDMATERIALS", "TOTALCOMPLETEDTODATE"];
    }

    /**
     * @param $obj
     */
    public function calculateBalanceToFinish(&$obj)
    {
        if(empty($obj) || !is_array($obj)){
            return false;
        }
        if(!$this->isPCBEnabled($obj)){
            return false;
        }
        $revisedContractAmt  = $obj['REVISEDCONTRACTAMT'] ?? 0;
        $totalCompletedToDate  = $obj['TOTALCOMPLETEDTODATE'] ?? 0;
        $retainageBalance  = $obj['RETAINAGEBALANCE'] ?? 0;
        $totalRetainage  = $obj["TOTALRETAINAGE"] ?? 0;
        if(array_key_exists('BALANCETOFINISH', $obj)){
            $obj['BALANCETOFINISH'] = ibcadd(ibcsub($revisedContractAmt, $totalCompletedToDate), $retainageBalance);
        }
        if(array_key_exists('TOTALEARNEDLESSRET', $obj)){
            $obj["TOTALEARNEDLESSRET"] = ibcsub($totalCompletedToDate, $totalRetainage);
        }
    }

    /**
     * @param string|null $projectContractID
     *
     * @return array
     */
    protected function getProjectContractLines($projectContractID): array
    {
        if (isNullOrBlank($projectContractID)) {
            return [];
        }
        
        [$projectContractId] = explode("--",$projectContractID);
        if(!$this->projectContractLinesCache[$projectContractId]){
            // $pcMgr = Globals::$g->gManagerFactory->getManager('projectcontract');
            $this->projectContractLinesCache[$projectContractId] = $this->getAllProjectContractLines($projectContractId);
            // $this->projectContractLinesCache[$projectContractID] = $pcMgr->getLines($projectContractID);
        }

        return $this->projectContractLinesCache[$projectContractId] ?? [];
    }


    /**
     * @param string $ID
     *
     * @return array|mixed
     */
    protected function getAllProjectContractLines($ID){
        if(empty($ID)){
            return [];
        }
        $pcKey = $this->getProjectContractById($ID)['RECORDNO'];
        $details = $this->getProjectContractLinesDetails($ID);
        $details = $this->getProjectContractLinesRateTables($ID, $details);
        $details = $this->getProjectContractLinesTasks($pcKey, $details);
        $data = $this->getProjectContractLineEntriesByBatch($pcKey, $details);
        return $data;
    }

    /**
     * @param string $ID
     *
     * @return array
     */
    protected function getProjectContractLinesDetails($ID){
        [$projectContractId] = explode("--",$ID);
        $stmt = "
            SELECT
            projectcontractline.record# recordno,
            projectcontractline.record# projectcontractlineno,
            projectcontract.record# projectcontractno,
            projectcontract.projectcontractid projectcontractid,
            projectcontract.name projectcontractname,
            projectcontractline.projectcontractlineid projectcontractlineid,
            projectcontractline.name projectcontractname,
            projectcontractline.parentkey projectcontractparentno,
            parent.projectcontractlineid parentprojectcontractlineid,
            parent.name parentprojectcontractlinename,
            projectcontractline.description,
            projectcontractline.contractlinedate,    
            projectcontractline.retainagepercentage,
            projectcontractline.billable,
            projectcontractline.billingtype,
            projectcontractline.maxbilling,
            projectcontractline.maxbillingamount,
            projectcontractline.originalprice,
            projectcontractline.revisionprice,
            projectcontractline.forecastprice,
            projectcontractline.approvedchangeprice,
            projectcontractline.pendingchangeprice,
            projectcontractline.otherprice,
            projectcontractline.totalprice totalrevisedprice,
            projectcontractline.status,
            projectcontractline.createdby,
            projectcontractline.modifiedby,
            projectcontractline.billedprice,
            projectcontractline.billednetretainage,
            projectcontractline.percentagebilled,
            projectcontractline.percentagebillednetretainage,
            projectcontractline.retainageheld,
            projectcontractline.retainagereleased,
            projectcontractline.retainagebalance,
            projectcontractline.paymentsreceived,
            projectcontractline.balancetobill,
            projectcontractline.appliedtodate,
            projectcontractline.retainageamountfromwork,
            projectcontractline.retainageamountfromstored,
            projectcontractline.lastamountapplied,
            projectcontractline.percentcompleted,
            projectcontractline.storedmaterials,
            projectcontractline.projectdimkey projectno,
            projectcontractline.external_refno externalrefno,
            projectcontractline.maxbilling maximumbilling,
            projectcontractline.maxbillingamount maximumbillingamount,
            project.projectid projectid,
            project.name projectname,
            projectcontractline.customerdimkey customerno,
            customer.customerid customerid,
            customer.name customername,
            projectcontractline.vendordimkey vendorkey,
            vendor.vendorid vendorid,
            vendor.name vendorname,
            projectcontractline.employeedimkey employeeno,
            employee.employeeid employeeid,
            employee_contact.name employeename,
            projectcontractline.itemdimkey itemno,
            item.itemid itemid,
            item.name itemname,
            projectcontractline.classdimkey classno,
            class.classid classid,
            class.name classname,
            projectcontractline.taskdimkey taskno,
            task.taskid taskid,
            task.name taskname,
            projectcontractline.costtypedimkey costtypeno,
            costtype.costtypeid costtypeid,
            costtype.name costtypename,
            department.dept_no departmentid,
            department.title departmentname,
            projectcontractline.summarizebill
                   
        FROM
            projectcontractline    projectcontractline,
            projectcontractmst     projectcontract,
            projectcontractlinemst parent,
            projectmst             nondimproject,
            supdoc                 supdoc,
            project                project,
            customermst            customer,
            departmentmst          department,
            vendormst              vendor,
            employeemst            employee,
            contact                employee_contact,
            icitem                 item,
            class                  class,
            task                   task,
            costtype               costtype,
            supdocmaps             supdocmaps
        WHERE
            projectcontract.cny# = :1 
            AND projectcontract.projectcontractid  = :2
            AND projectcontractline.cny#(+) = projectcontract.cny#
            AND projectcontractline.projectcontractkey(+) = projectcontract.record#    
            AND projectcontractline.parentkey = parent.record# (+)
            AND parent.cny# (+) = projectcontractline.cny#
            AND projectcontractline.projectdimkey = nondimproject.record# (+)
            AND nondimproject.cny# (+) = projectcontractline.cny#
            AND supdocmaps.documentid = supdoc.record# (+)
            AND supdoc.cny# (+) = projectcontractline.cny#
            AND to_char(projectcontractline.record#) = supdocmaps.recordid (+)
            AND supdocmaps.cny# (+) = projectcontractline.cny#
            AND supdocmaps.transactiontype (+) = :3
            AND projectcontractline.projectdimkey = project.record# (+)
            AND project.cny# (+) = projectcontractline.cny#
            AND projectcontractline.customerdimkey = customer.record# (+)
            AND customer.cny# (+) = projectcontractline.cny#
            AND projectcontractline.deptkey = department.record# (+)
            AND department.cny# (+) = projectcontractline.cny#
            AND projectcontractline.vendordimkey = vendor.record# (+)
            AND vendor.cny# (+) = projectcontractline.cny#
            AND projectcontractline.employeedimkey = employee.record# (+)
            AND employee.cny# (+) = projectcontractline.cny#
            AND employee.contactkey = employee_contact.record# (+)
            AND employee_contact.cny# (+) = projectcontractline.cny#
            AND projectcontractline.itemdimkey = item.record# (+)
            AND item.cny# (+) = projectcontractline.cny#
            AND projectcontractline.classdimkey = class.record# (+)
            AND class.cny# (+) = projectcontractline.cny#
            AND projectcontractline.taskdimkey = task.record# (+)
            AND task.cny# (+) = projectcontractline.cny#
            AND projectcontractline.costtypedimkey = costtype.record# (+)
            AND costtype.cny# (+) = projectcontractline.cny#";
        $result = QueryResult([$stmt, GetMyCompany(), $projectContractId, "PROJECTCONTRACTLINE"]);
        $details = $this->processProjectContractLineDetails($result);
        return $details;
    }

    /**
     * @param array $result
     *
     * @return array
     */
    protected function processProjectContractLineDetails($result){
        $details = [];
        $gManagerFactory = Globals::$g->gManagerFactory;
        $pcleManager = $gManagerFactory->getManager('projectcontractline');
        foreach ($result as $line){
            if($line['STATUS'] != 'T'){
                continue;
            }
            foreach($line as $path => $value){
                if(isNullOrBlank($value)){
                    continue;
                }
                $line[$path] = $pcleManager->TransformValue($path, $value);
            }
            $details[$line['PROJECTCONTRACTLINEID']] = $line;
            $details[$line['PROJECTCONTRACTLINEID']]['PCLTASKS'] = [];
            $details[$line['PROJECTCONTRACTLINEID']]['ITEMS'] = [];
        }
        return $details;
    }

    /**
     * @param $key
     * @param $details
     *
     * @return mixed
     */
    protected function getProjectContractLineEntriesByBatch($key, $details)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;

        $params = [
            'selects' => [ 'RECORDNO', 'PROJECTCONTRACTLINEID' ],
            'filters' => [ [ [ 'PROJECTCONTRACTKEY', '=', $key] ]  ]
        ];
        $prjContractLineMgr = $gManagerFactory->getManager('projectcontractline');
        $projectContractLineKeys = $prjContractLineMgr->GetList($params);

        $limit = 300;
        if(!empty($projectContractLineKeys)){
            $projectContractLineKeysBatch = array_chunk($projectContractLineKeys, $limit);
            foreach($projectContractLineKeysBatch as $keys) {
                    $stmt = "
                        SELECT
                        projectcontractlineentry.record# recordno,
                        projectcontractlineentry.pclkey projectcontractlinekey,                        
                        projectcontractlineentry.recordtype,
                        projectcontractlineentry.wftype,
                        projectcontractlineentry.updatepjcontract,
                        changerequest.pricedate,
                        changerequest.crid changerequestid,
                        projectcontractlineentry.locationkey,
                        location.location_no locationid,
                        location.name locationname,
                        projectcontractlineentry.deptkey departmentkey,
                        department.dept_no departmentid,
                        department.title departmentname,
                        projectcontractlineentry.qty,
                        projectcontractlineentry.euom,
                        projectcontractlineentry.unitprice,
                        projectcontractlineentry.price,
                        projectcontractlineentry.pricemarkup_percent pricemarkuppercent,
                        projectcontractlineentry.pricemarkup_amount pricemarkupamount,
                        projectcontractlineentry.lineprice,
                        projectcontractlineentry.memo,
                        projectcontractlineentry.pricedate priceeffectivedate,
                        projectcontractlineentry.whencreated,
                        projectcontractlineentry.whenmodified,
                        projectcontractlineentry.createdby,
                        projectcontractlineentry.modifiedby,
                        projectcontractlineentry.projectdimkey projectdimkey,
                        project.projectid,
                        project.name projectname,
                        projectcontractlineentry.customerdimkey customerdimkey,
                        customer.customerid,
                        customer.name customername,
                        projectcontractlineentry.vendordimkey vendordimkey,
                        vendor.vendorid,
                        vendor.name vendorname,
                        projectcontractlineentry.employeedimkey employeedimkey,
                        employee.employeeid,
                        employee_contact.name employeename,
                        projectcontractlineentry.itemdimkey itemdimkey,
                        item.itemid,
                        item.name itemname,
                        projectcontractlineentry.classdimkey classdimkey,
                        class.classid,
                        class.name classname,
                        projectcontractlineentry.taskdimkey taskdimkey,
                        task.taskid,
                        task.name taskname,
                        projectcontractlineentry.costtypedimkey costtypedimkey,
                        costtype.costtypeid,
                        costtype.name costtypename
                    FROM 
                        crdetail            projectcontractlineentry 
                        left join crheadermst         changerequest on    
                            changerequest.cny# = projectcontractlineentry.cny#
                            AND changerequest.record# = projectcontractlineentry.crkey
                        left join locationmst         location on
                            location.record# = projectcontractlineentry.locationkey
                            AND projectcontractlineentry.cny# = location.cny#
                        left join departmentmst       department on
                            department.cny# = projectcontractlineentry.cny#
                            AND department.record# = projectcontractlineentry.deptkey         
                        left join project             project on
                            project.cny# = projectcontractlineentry.cny#
                            AND projectcontractlineentry.projectdimkey = project.record#    
                        left join customermst         customer on
                            customer.cny# = projectcontractlineentry.cny#
                            AND customer.record# = projectcontractlineentry.customerdimkey        
                        left join vendormst           vendor on
                            vendor.cny# = projectcontractlineentry.cny#
                            AND vendor.record# = projectcontractlineentry.vendordimkey
                        left join employeemst         employee on
                            employee.cny# = projectcontractlineentry.cny#
                            AND employee.record# =  projectcontractlineentry.employeedimkey    
                        left join contact             employee_contact on
                            employee_contact.cny# = projectcontractlineentry.cny#
                            AND employee_contact.record# = employee.contactkey
                        left join icitem              item on
                            item.cny# = projectcontractlineentry.cny#
                            AND item.record# = projectcontractlineentry.itemdimkey    
                        left join class               class on
                            class.cny# = projectcontractlineentry.cny#
                            AND class.record# = projectcontractlineentry.classdimkey    
                        left join task                task on
                            task.cny# = projectcontractlineentry.cny#
                            AND task.record# = projectcontractlineentry.taskdimkey        
                        left join costtype            costtype on
                            costtype.cny# = projectcontractlineentry.cny#
                            AND costtype.record# = projectcontractlineentry.costtypedimkey   
                    WHERE
                        projectcontractlineentry.cny# = :1";
                    $stmt = PrepINClauseStmt($stmt, array_column($keys, 'RECORDNO'), " and projectcontractlineentry.pclkey ");
                    $result = QueryResult([$stmt, GetMyCompany(), $key]);
                    $details = $this->processProjectContractLineEntries($result, $details, $keys);

            }

        }

        return $details;
    }

    /**
     * @param array $entries
     * @param array $details
     * @param array $keys
     *
     * @return mixed
     */
    protected function processProjectContractLineEntries($entries, $details, $keys){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $pcleManager = $gManagerFactory->getManager('projectcontractlineentry');
        $wfTypeField = $pcleManager->GetFieldInfo('WFTYPE');
        $pcleManager = $gManagerFactory->getManager('changerequestentry');
        $creWfTypeField = $pcleManager->GetFieldInfo('WFTYPE');
        foreach($entries as $entry){
            $idx = array_search($entry["PROJECTCONTRACTLINEKEY"], array_column($keys,'RECORDNO'));
            if($idx !== false){
                $entry['PROJECTCONTRACTLINEID'] = $keys[$idx]["PROJECTCONTRACTLINEID"];
            }
            if(isset($details[$entry['PROJECTCONTRACTLINEID']])){
                $creWFTField = $entry['WFTYPE'];
                foreach($entry as $path => $value){
                    if(isNullOrBlank($value)){
                        continue;
                    }
                    $entry[$path] = $pcleManager->TransformValue($path, $value);
                }
                // $index = array_search($entry['WFTYPE'], $wfTypeField['type']['_validivalues']);
                // if($index !== false){
                //     $entry['WFTYPE'] =  $wfTypeField['type']['validvalues'][$index];
                // }else{
                //     $entry['WFTYPE'] = "";
                // }
                $idx = array_search($creWFTField, $creWfTypeField['type']['_validivalues']);
                if($idx !== false){
                    $entry['CREWFTYPE'] =  $creWfTypeField['type']['validvalues'][$idx];
                }else{
                    $entry['CREWFTYPE'] = "";
                }
                $details[$entry['PROJECTCONTRACTLINEID']]['ITEMS'][] = $entry;
            }
        }
        return $details;
    }

    /**
     * @param $ID
     * @param $details
     *
     * @return array|mixed
     */
    protected function getProjectContractLinesRateTables($ID, $details){
        [$projectContractId] = explode("--",$ID);
        $stmt = "
            SELECT
            projectcontractline.record# recordno,
            projectcontractline.record# projectcontractlineno,
            projectcontract.record# projectcontractno,
            projectcontract.projectcontractid projectcontractid,
            projectcontract.name projectcontractname,
            projectcontractline.projectcontractlineid projectcontractlineid,
            projectcontractline.name projectcontractname,
            projectcontractline.defaultratetablekey ,
            defaultratetable.ratetableid DEFAULTRATETABLEID,
            projectcontractline.tsratetablekey,
            tsratetable.ratetableid TSRATETABLEID,
            projectcontractline.poratetablekey ,
            poratetable.ratetableid PORATETABLEID,
            projectcontractline.apratetablekey,
            apratetable.ratetableid APRATETABLEID,
            projectcontractline.glratetablekey,
            glratetable.ratetableid GLRATETABLEID,
            projectcontractline.ccratetablekey,
            ccratetable.ratetableid CCRATETABLEID, 
            projectcontractline.eeratetablekey,
            eeratetable.ratetableid EERATETABLEID
                   
        FROM
            projectcontractline    projectcontractline,
            projectcontractmst     projectcontract,
            ratetable              defaultratetable,
            ratetable              tsratetable,
            ratetable              poratetable,
            ratetable              apratetable,
            ratetable              glratetable,
            ratetable              ccratetable,
            ratetable              eeratetable
        WHERE
            projectcontract.cny# = :1 
            AND projectcontract.projectcontractid  = :2
            AND projectcontractline.cny#(+) = projectcontract.cny#
            AND projectcontractline.projectcontractkey(+) = projectcontract.record#
            AND projectcontractline.defaultratetablekey = defaultratetable.record# (+)
            AND defaultratetable.cny# (+) = projectcontractline.cny#
            AND projectcontractline.tsratetablekey = tsratetable.record# (+)
            AND tsratetable.cny# (+) = projectcontractline.cny#
            AND projectcontractline.poratetablekey = poratetable.record# (+)
            AND poratetable.cny# (+) = projectcontractline.cny#
            AND projectcontractline.apratetablekey = apratetable.record# (+)
            AND apratetable.cny# (+) = projectcontractline.cny#
            AND projectcontractline.glratetablekey = glratetable.record# (+)
            AND glratetable.cny# (+) = projectcontractline.cny#
            AND projectcontractline.ccratetablekey = ccratetable.record# (+)
            AND ccratetable.cny# (+) = projectcontractline.cny#
            AND projectcontractline.eeratetablekey = eeratetable.record# (+)
            AND eeratetable.cny# (+) = projectcontractline.cny#";
        $result = QueryResult([$stmt, GetMyCompany(), $projectContractId, "PROJECTCONTRACTLINE"]);
        $details = $this->processProjectContractLineRateTable($result, $details);
        return $details;

    }

    /**
     * @param $result
     * @param $details
     *
     * @return array $details
     */
    protected function processProjectContractLineRateTable($result, $details){
        foreach($result as $res){
            if(isset($details[$res['PROJECTCONTRACTLINEID']])){
                $details[$res['PROJECTCONTRACTLINEID']] = array_merge($details[$res['PROJECTCONTRACTLINEID']], $res);
            }
        }
        return $details;
    }

    /**
     * @param int $key
     * @param array $details
     *
     * @return array|mixed
     */
    protected function getProjectContractLinesTasks($key, $details){
        $stmt = "
        SELECT
            pcltask.record# recordno,
            pcltask.projectkey,
            pcltask.projectcontractlinekey,
            projectcontractline.projectcontractlineid,
            pcltask.taskkey,
            task.taskid,
            task.name pcltaskname,
            project.projectid,
            project.name pclprojectname,
            task.taskstatus pcltaskstatus,
            task.billable pcltaskbillable
        FROM
            projectcontractline projectcontractline
            LEFT JOIN pcltask  pcltask ON 
            pcltask.cny# = projectcontractline.cny#
            AND pcltask.projectcontractlinekey = projectcontractline.record#
            LEFT JOIN task  task ON 
            pcltask.cny# = task.cny# AND pcltask.taskkey = task.record#
            LEFT JOIN project project ON 
            project.record# = pcltask.projectkey AND project.cny# = pcltask.cny#
        WHERE
            projectcontractline.cny# = :1
            AND projectcontractline.projectcontractkey = :2";
        $result = QueryResult([$stmt, GetMyCompany(), $key]);
        $data = $this->processProjectContractLinesTasks($result, $details);
        return $data;
    }

    /**
     * @param array $tasks
     * @param array $details
     *
     * @return mixed
     */
    protected function processProjectContractLinesTasks($tasks, $details){
        $gManagerFactory = Globals::$g->gManagerFactory;
        $pclTaskManager = $gManagerFactory->getManager('pcltask');
        foreach($tasks as $task){
            if(isset($details[$task['PROJECTCONTRACTLINEID']])){
                foreach($task as $path => $value){
                    if(isNullOrBlank($value)){
                        continue;
                    }
                    $task[$path] = $pclTaskManager->TransformValue($path, $value);
                }
                $details[$task['PROJECTCONTRACTLINEID']]['PCLTASKS'][] = $task;
            }
        }
        return $details;
    }

    /**
     * @param string $id
     *
     * @return array
     */
    protected function getProjectContractById($id){
        if(!isset($this->projectContractCache[$id])){
            $idx = array_search($id, array_column($this->projectContractCache, 'PROJECTCONTRACTID'));
            if($idx !== false){
                $values = array_values($this->projectContractCache);
                $this->projectContractCache[$id] = $values[$idx];
            }else{
                $gManagerFactory = Globals::$g->gManagerFactory;
                $projectContractMgr = $gManagerFactory->getManager('projectcontract');
                $this->projectContractCache[$id] = $projectContractMgr->get($id);
            }
        }
        return $this->projectContractCache[$id] ?? [];
    }

    /**
     * @param int|string $recordNo
     *
     * @return array
     */
    protected function getProjectContractByRecordNo($recordNo){
        if(!isset($this->projectContractCache[$recordNo])){
            $idx = array_search($recordNo, array_column($this->projectContractCache, 'RECORDNO'));
            if($idx !== false){
                $values = array_values($this->projectContractCache);
                $this->projectContractCache[$recordNo] = $values[$idx];
            }else{
                $gManagerFactory = Globals::$g->gManagerFactory;
                $projectContractMgr = $gManagerFactory->getManager('projectcontract');
                $this->projectContractCache[$recordNo] = $projectContractMgr->GetByRecordNo($recordNo);
            }
        }
        return $this->projectContractCache[$recordNo] ?? [];
    }

    /**
     * list of fields value to be removeed for 2nd line onwards of same PCB line
     * @param $entry
     *
     * @return void
     */
    private function removeBillingFieldValues(&$entry){

        $billingFields = ['CONTRACTLINEVALUE', 'PRIORAPPLICATIONAMT', 'TOTALCOMPLETEDTODATE', 'BALANCEREMAINING', 'PREVIOUSRETAINAGEBALANCE', 'PERCENTCOMPLETEDTODATE'];
        foreach ($billingFields as $field){
            unset($entry[$field]);
        }

    }

    /**
     * handle the PCB lines which have more than one same ID
     * @param array $values
     *
     */
    public function handleBillingFields(&$values){
        $groupedEntries = [];
        foreach($values['ENTRIES'] as $key => &$entry){
            [$projectContractLineId] = explode('--', $entry['PROJECTCONTRACTLINEID']);
            $entry['actualIndex'] = $key;
            if(!isset($groupedEntries[$projectContractLineId])){
                if(empty($entry["ISRETAINAGERELEASE"])){
                    $entry["ISRETAINAGERELEASE"] = "false";
                }
                $groupedEntries[$projectContractLineId][] = $entry;
            }else{
                if((empty($entry["ISRETAINAGERELEASE"]) || $entry["ISRETAINAGERELEASE"] == "false")){
                    // if ISRETAINAGERELEASE is not set
                    $entry["ISRETAINAGERELEASE"] = "false";
                    if(array_search("false", array_column($groupedEntries[$projectContractLineId], "ISRETAINAGERELEASE")) !== false){
                        $this->removeBillingFieldValues($entry);
                    }else{
                        foreach ($groupedEntries[$projectContractLineId] as $line){
                            if(!empty($line["ISRETAINAGERELEASE"]) && $line["ISRETAINAGERELEASE"] == "true"){
                                $idx = $line["actualIndex"];
                                $this->removeBillingFieldValues($values['ENTRIES'][$idx]);
                            }
                        }
                    }
                    $groupedEntries[$projectContractLineId][] = $entry;

                }else{
                    $this->removeBillingFieldValues($entry);
                    $groupedEntries[$projectContractLineId][] = $entry;
                }
            }

            if($entry["PCBLBILLINGTYPE"] == "TM" && $entry["ISRETAINAGERELEASE"] == "false"){
                $entry['TOTALCOMPLETEDTODATE'] = ibcadd(($entry['PRIORAPPLICATIONAMT'] ?? 0), $entry['COMPLETEDTHISPERIOD']);
            }
        }
        unset($entry);
    }

    /**
     * To handle PCB line totals
     * @param array $values
     *
     * @return void
     */
    protected function handlePCBLines(&$values){
        if(empty($values)){
            return;
        }
        $projectContractID = current($values)[0]['PROJECTCONTRACTID'];
        $projectContractLines = $this->getProjectContractLines($projectContractID);
        foreach ($values as $id => $lines){
            $projectLineDetail = $projectContractLines[$id];
            // to check for release line alone
            if(is_array($lines) && count($lines) == 1){
                $idx = array_search('true', array_column($lines, 'ISRETAINAGERELEASE'));
                if($idx !== false){
                    //found release line
                    //adding bill line with price as zero
                    $values[$id][] = $lines[] = $lines[0];
                    $values[$id][0]['RETAINAGEPERCENTAGE'] = $projectLineDetail['RETAINAGEPERCENTAGE'];

                    $values[$id][0]['COMPLETEDTHISPERIOD'] = 0;
                    $values[$id][0]['STOREDMATERIALS'] = 0;
                    $values[$id][0]['RETAINAGETOBILL'] = 0;
                    $values[$id][0]['TRX_PRICE'] = 0;
                    $values[$id][0]['UIPRICE'] = 0;
                    $values[$id][0]['UIVALUE'] = 0;
                    $values[$id][0]['PRICE'] = 0;
                    $values[$id][0]['VALUE'] = 0;
                    $values[$id][0]['TRX_VALUE'] = 0;
                    $values[$id][0]['TRX_AMOUNTRETAINED'] = 0;
                    $values[$id][0]['AMOUNTRETAINED'] = 0;
                    $values[$id][0]['__SUPPORTING_BILLING'] = "true";
                    unset($values[$id][0]['ISRETAINAGERELEASE']);
                    $lines[0] = $values[$id][0];
                }
            }
        }
        unset($lines);
    }

    /**
     * @param array $values
     *
     * @return void
     */
    private function recalculateLineRetainageBalance(&$values){

        foreach($values['ENTRIES'] as $key => $entry){
            $previousRetainageBalance = $entry['PREVIOUSRETAINAGEBALANCE'] ?? 0;
            $trxAmountRetainage = $entry['TRX_AMOUNTRETAINED'] ?? 0;
            $retainageToBill = $entry['RETAINAGETOBILL'] ?? 0;
            $values['ENTRIES'][$key]['RETAINAGEBALANCE']  = ibcsub(ibcadd($previousRetainageBalance, $trxAmountRetainage), $retainageToBill);
        }
    }

    /**
     * @param array $values
     *
     * @return int|mixed|string
     */
    private function getPreviousTotalCompletedToDate($values){

        $ret = 0;
        $cny = GetMyCompany();
        $projectContractKey = !empty($values['PROJECTCONTRACTKEY']) ? $values['PROJECTCONTRACTKEY'] : 0;
        $currentDocKey = $values['RECORDNO'];
        $response = $this->DoQuery('QRY_SODOCUMENT_GET_PREVIOUSTOTALCOMPLETEDTODATE', array($cny, $projectContractKey, $currentDocKey));
        if($response){
            $ret = !empty($response[0]["PREVIOUSTOTALCOMPLETEDTODATE"]) ? $response[0]["PREVIOUSTOTALCOMPLETEDTODATE"] : 0;
        }
        return $ret;
    }

    /**
     * @param $pcKey
     *
     * @return array
     */
    private  function getProjectContractLinesTotalPrice($pcKey){

        if(!isset($this->projectContractLinesTotalPrice[$pcKey])){
            $cny = GetMyCompany();
            $stmt = "SELECT record# as projectcontractlinekey, ( nvl(originalprice, 0) + nvl(revisionprice, 0) + nvl(approvedchangeprice, 0) ) as totalprice FROM
            projectcontractlinemst WHERE cny# = :1 AND projectcontractkey = :2 and status = 'T'";

            $results = QueryResult([$stmt, $cny, $pcKey]);
            $data = [];
            foreach ($results as $result){
                $data[$result['PROJECTCONTRACTLINEKEY']] = $result;
            }
            $this->projectContractLinesTotalPrice[$pcKey] = $data;
        }

        return $this->projectContractLinesTotalPrice[$pcKey] ?? [];

    }

    private function clearProjectContractLinesTotalPrice(){
        $this->projectContractLinesTotalPrice = [];
    }

    /**
     * @param array $bulkData
     *
     * @return bool
     */
    private function doBulkUpdateProjectContractTotals($bulkData){
        $ok = true;
        if(!empty($bulkData)){
            $source = "ProjectContractBillingTrait::doBulkUpdateProjectContractTotals";
            $ok = Globals::$g->gQueryMgr->beginTrx($source);

            $bulkArr[0] = "UPDATE projectcontractlinemst set 
                    billedprice = (nvl(billedprice,0) + :3(i) )
                    ,billednetretainage = (nvl(billednetretainage, 0) + :7(i) )
                    ,retainageheld = (nvl(retainageheld, 0) + :10(i) )
                    ,percentagebilled = case when :14(i) = 0 or 
                        abs(((nvl(billedprice,0) + :4(i) ) * 100) / :14(i)) > 999 
                        then 0 else
                        (((nvl(billedprice,0) + :5(i) ) * 100) / :14(i)) end
                    ,percentagebillednetretainage = case when :14(i) = 0 or 
                        abs(((nvl(billednetretainage, 0) + :8(i) ) * 100) / :14(i)) > 999 
                        then 0 else
                        (((nvl(billednetretainage, 0) + :9(i) ) * 100) / :14(i)) end
                    ,retainagebalance = (nvl(retainageheld, 0) + :11(i) ) - nvl(retainagereleased, 0)
                    ,balancetobill = (nvl(originalprice, 0) + nvl(revisionprice, 0) + nvl(approvedchangeprice, 0)) -
                        (nvl(billedprice,0) + :6(i) ) 
                    WHERE cny# = :12(i) and record# = :13(i) ";
            $bulkArr[1] = $bulkData;
            $bulkArr[2] = ['integer','integer','integer','integer','integer','integer','integer','integer','integer',
                           'integer','integer','integer','integer','integer'];
            $ok = $ok && ExecBulkStmt($bulkArr);
            $ok = $ok && Globals::$g->gQueryMgr->commitTrx($source);

            if (!$ok) {
                Globals::$g->gQueryMgr->rollbackTrx($source);
            }
        }
        return $ok;
    }
}