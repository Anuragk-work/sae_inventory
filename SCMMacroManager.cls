<?php

/**
 * Manager class for SCM Macro
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Manager class for SCM Macro
 */
class SCMMacroManager extends EntityManager
{
    const TARGETFROMDOC = 'all'; //String to use to create a single doc array for macros with target from doc rather than from entry

    const DROPSHIP = 'Drop ship';
    const BTO = 'Buy to order';
    const LANDEDCOST = 'Landed cost'; //LC only
    const LCEST = 'LC Est'; //LC Estimate only
    const LCACTANDEST = 'LC Act and Est'; //LC actual and estimate
    const LCACTANDESTREV = 'LC Act and EstRev'; //LC actual and just estimate reversal



    // trait that handles all logic related to state
    use SCMMacroErrorTrait;
    
    /**
     * __construct
     * 
     * @param array $params entitymanager param
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }
    
    /**
     * Add     
     * 
     * @param array &$values to be added to the table
     * 
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "SCMMacroManager::Add";

        $ok = $this->_QM->beginTrx($source);
        
        $ok = $ok && $this->translateValues($values);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if ( !HasWarnings() || HasErrors() ) {
                $msg = "Could not create SCM Macro";
                $gErr->addIAError('INV-0790', __FILE__ . ':' . __LINE__, $msg, []);
            }

            $this->_QM->rollbackTrx($source);
        }
        

        return $ok;
    }

    /**
     * translateValues     
     * 
     * @param array &$values input values
     * 
     * @return bool
     */    
    public function translateValues(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $docParMgr = $gManagerFactory->getManager('documentparams');
        
        $ok = true;
        
        if ( $values['SOURCEDOCPARID'] ) {

            // Get the source doc par key
            $params = array(
                'selects' => array('RECORDNO'),
                'filters' => array(
                    array(array('DOCID', '=', $values['SOURCEDOCPARID']))
                ),
            );

            $recs = $docParMgr->GetList($params);

            // If invalid let throw and error
            if (!isset($recs[0]['RECORDNO'])) {
                $msg = "Invalid Source Transaction Type " .  $values['SOURCEDOCPARID'] . " selected";
                $corr = "Pick a valid Source Transaction Type.";
                $gErr->addIAError(
                    'INV-0791', __FILE__ . ':' . __LINE__,
                    $msg, ['SOURCEDOCPARID' => $values['SOURCEDOCPARID']],
                    '', [],
                    $corr, []
                );
                $ok = false;
            } else {
                $values['SOURCEDOCPARKEY'] = $recs[0]['RECORDNO'];
            }

        } else {

            $msg = "Source Transaction type cannot be empty";
            $corr = "Pick a valid Source Transaction Type.";
            $gErr->addIAError('INV-0792', __FILE__ . ':' . __LINE__, $msg,[], '',[], $corr,[]);
            $ok = false;
        }
        
        
        $targetFlds = array();
        foreach ( $values['MEMBERS'] as &$member) {
            
            $member['SCMMACROKEY'] = $values['RECORDNO'];
            
            if ($member['TARGETDOCPARID']) {

                // Get the target doc par key
                $params = array(
                    'selects' => array('RECORDNO'),
                    'filters' => array(
                        array(array('DOCID', '=', $member['TARGETDOCPARID']))
                    ),
                );

                $recs = $docParMgr->GetList($params);

                // If invalid let throw and error
                if (!isset($recs[0]['RECORDNO'])) {
                    $msg = "Invalid Target Transaction Type " . $member['TARGETDOCPARID'] . " selected";
                    $corr = "Pick a valid Source Transaction Type.";
                    $gErr->addIAError(
                        'INV-0793', __FILE__ . ':' . __LINE__,
                        $msg, ['MEMBER_TARGETDOCPARID' => $member['TARGETDOCPARID']],
                        '', [],
                        $corr, []
                    );
                    $ok = false;
                } else {
                    $member['TARGETDOCPARKEY'] = $recs[0]['RECORDNO'];
                }

            } else {

                $msg = "Target Transaction type cannot be empty";
                $corr = "Pick a valid Source Transaction Type.";
                $gErr->addIAError('INV-0794', __FILE__ . ':' . __LINE__, $msg,[], '',[], $corr,[]);
                $ok = false;
            }
            
            if ($member['TYPE'] == 'map' && empty($member['SOURCEDOCFLD'])) {
                $msg = "Source field is required to map";
                $corr = "Pick a valid field from source transaction type.";
                $gErr->addIAError('INV-0795', __FILE__ . ':' . __LINE__, $msg,[], '',[], $corr,[]);
                $ok = false;
            }
            
            if (isset($targetFlds[$member['TARGETDOCPARID'].'-'.$member['TARGETDOCFLD']])) {
                $msg = "Target field is given more than once";
                $corr = "Pick a valid field from target transaction type.";
                $gErr->addIAError('INV-0796', __FILE__ . ':' . __LINE__, $msg,[], '',[], $corr,[]);
                $ok = false;                
            } else {
                $targetFlds[$member['TARGETDOCPARID'].'-'.$member['TARGETDOCFLD']] = true;
            }
            
        } 
        unset($member);
        
        return $ok;
    }

    /**
     * @param string    $id
     * @param array     $fields
     *
     * @return array|false
     */
    public function Get($id, $fields=null)
    {
        $obj = parent::get($id);
        return $obj;
    }

    /**
     * Set     
     *      
     * @param array &$values   new values
     * 
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $gManagerFactory =Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $source = "SCMMacroManager::Set";

        $ok = $this->_QM->beginTrx($source);
        
        $scmMacroResolveMgr = $gManagerFactory->getManager('scmmacroresolve');
        
        // Get the source doc par key
        $params = array(
            'selects' => array(
                'SOURCEDOCKEY',
            ),
            'filters' => array(
                array(array('SCMMACROKEY', '=', $values['RECORDNO']))
            ),
        );
        
        $recs = $scmMacroResolveMgr->GetList($params);

        if ($recs[0]['SOURCEDOCKEY']) {
            $oldRecNo = $values['RECORDNO'];
            $values['RECORDNO'] = $this->GetNextRecordKey();
            $ok = $ok && $this->updateVersion($values['RECORDNO'], $oldRecNo);
            $ok = $ok && $this->add($values);
        } else {
            $ok = $ok && $this->translateValues($values);
            $ok = $ok && parent::regularSet($values);
        }
        
        $ok = $ok && $this->_QM->commitTrx($source);
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not update macro record!";
                $gErr->addIAError('INV-0797', __FILE__ . ':' . __LINE__, $msg,[]);
            }

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }
    
    /**
     * Delete     
     *      
     * @param int $recNo record no.
     * 
     * @return bool
     */    
    public function Delete($recNo)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $source = "SCMMacroManager::Delete";
        
        $ok = $this->_QM->beginTrx($source);
        $values = $this->Get($recNo);
        
        $scmResolveManager = $gManagerFactory->getManager('scmmacroresolve');
        $params = array(
            'selects' => array(
                'SOURCEDOCPARID', 
            ),
            'filters' => array(
                array(
                    array('SCMMACROKEY', '=', $recNo),
                )
            ),
        );
        $results = $scmResolveManager->GetList($params);
        
        if ($results[0]['SOURCEDOCPARID']) {
            $params['SOURCE'] = $results[0]['SOURCEDOCPARID']; 
            self::getMacroErrorMessage($values['NAME'], "MACRO003", $msg, $corr, $params, $errorCode, $placeholder);
            $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
            $ok = false;
        }
        
        $ok = $ok && parent::Delete($recNo);
        
        $ok = $ok && $this->_QM->commitTrx($source);
        
        if ( !$ok ) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not delete macro record!";
                $gErr->addIAError('INV-0798', __FILE__ . ':' . __LINE__, $msg,[]);
            }

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }
    
    /**
     * to create new version of macro     
     *      
     * @param int $newRecNo new record no.
     * @param int $oldRecNo old record no.
     * 
     * @return bool
     */       
    private function updateVersion($newRecNo, $oldRecNo)
    {
        $stmt = array();
        $stmt[] = "update scmmacrohdr set priorversionkey=:2 where cny#=:1 and record# = :3";
        $stmt[] = GetMyCompany();
        $stmt[] = $newRecNo;
        $stmt[] = $oldRecNo;
        
        $ok = ExecStmt($stmt);
        
        return $ok;
    }
    
    /**
     * reset internal values at entry      
     *      
     * @param array &$newEntry entry
     */
    private function resetEntryValues(&$newEntry)
    {
        $resetArray = array(
            'RECORDNO',
            'REVRECTEMPLATE',
            'REVRECSTARTDATE',
            'REVRECENDDATE',
            'BILLINGTEMPLATE',
            'RENEWALMACRO',
            'STATE',
            'SOURCE_DOCKEY',
            'SOURCE_DOCLINEKEY',
            'SOURCE_DOCID',
            'OVERRIDETAX',
            'TAXVALOVERRIDE',
            'DISCOUNTPERCENT',
            'LINE_NO',
            'LINENO',
            'L_NO',
            'LINEKEY',
            'NAMEOFACQUIREDASSET',
            'INCLUDETAXINASSETCOST'
        );

        foreach ($resetArray as $fld) {
            unset($newEntry[$fld]);
        }
    }
    
    /**
     * reset internal values at header      
     *      
     * @param array &$newValues header
     * @param string $macroPath header
     */
    private function resetValues(&$newValues, $macroPath)
    {
        $resetArray = array(
            'RECORDNO',
            'DOCNO',
            'LINE_NO',
            '_DOCPAR',
            '_mod',
            'ENTRIES',
            'BILLTOADDRESS',
            'SHIPTOADDRESS',
            'STATE',
            'CREATEDFROM',
            'RECURRINGSCHEDULE',
            'SUBTOTALS',
            'SUPDOCID',
            'BACKORDER'
        );

        if ($macroPath == 'DROPSHIP' || $macroPath == 'BUYTOORDER') {
            $resetArray[] = 'TERMKEY';
        }

        foreach ($resetArray as $fld) {
            unset($newValues[$fld]);
        }
    }

    /**
     * set default values for each document      
     *      
     * @param array  &$newValues         new target document values
     * @param string $tDocType           target document type
     * @param array  &$targetDocDetails  target document details
     */
    private function setDefaultValues(&$newValues, $tDocType, &$targetDocDetails)
    {
        $newValues['MACRONAME'] = $targetDocDetails['MACRONAME'];
        $newValues['MACROKEY'] = $targetDocDetails['MACROKEY'];            
        $newValues['DOCPARID'] = $tDocType;
    }

    /**
     * to check whether the source has been changed after the target was created      
     *      
     * @param array $macroMapDetails mapping details
     * @param array &$srcValues      source values
     *                                   
     * @return bool
     */
    private function compareMapFields($macroMapDetails, &$srcValues)
    {
        $ok = true;
        
        //adding mandatory fields that should not be modified during update
        $macroMapDetails['ENTRIES.ITEMID']['PATH'] = 'ENTRIES.ITEMID';
        $macroMapDetails['ENTRIES.UIQTY']['PATH'] = 'ENTRIES.UIQTY';

        foreach ( $macroMapDetails as $field) {
            $sPath = $field['PATH'];
            if ($sPath) {
                // get value from path
                if (!strpos($sPath, '.')) {
                    $newVal = $srcValues[$sPath];
                    $oldVal = $srcValues['EXISTING_DOC'][$sPath];
                } else {
                    list( , $path) = explode('.', $sPath);
                    $sPath = str_replace(".", ".0.", $sPath);
                    $newVal = EntityManager::AccessByPath($srcValues, $sPath);
                    list($newVal) = explode('--', $newVal);
                    
                    $recNo = $srcValues['ENTRIES'][0]['SRCDOCENTRYRECORDNO'];
                    list($oldVal) = explode('--', $srcValues['EXISTING_ENTRIES'][$recNo][$path]);
                }
                
                if ($newVal != $oldVal) {
                    $ok = false;
                    break;
                }
            } 
            
        }
        
        return $ok;
    }
    
    /**
     * to map target document fields from source
     *      
     * @param array  $macroMapDetails mapping details
     * @param array  &$newValues      target values
     * @param string &$groupIndex     index to group multiple source lines
     *                                   
     * @return bool
     */    
    private function mapFields($macroMapDetails, &$newValues, &$groupIndex)
    {
        $groupby = array();
        foreach ($macroMapDetails as $tPath => $field) {
            $sPath = $field['PATH'];
            if ($sPath) {
                // get value from path
                if (!strpos($sPath, '.')) {
                    $tVal = $newValues[$sPath];
                } else {
                    $sPath = str_replace(".", ".0.", $sPath);
                    $tVal = EntityManager::AccessByPath($newValues, $sPath);
                }
            } else {
                $tVal = $field['VALUE'];
            }

            //set value
            if (!strpos($tPath, '.')) {
                $newValues[$tPath] = $tVal;
            } else {
                $tPath = str_replace("ENTRIES.", "ENTRIES.0.", $tPath);
                EntityManager::SetByPath($newValues, $tPath, $tVal);
            }
            
            if ($field['GROUPBY'] && $tVal) {
                $groupby[] = $tVal;
            }

        }
        
        if (!empty($groupby)) {
            $groupIndex = implode('-', $groupby);
        }
        
        return true;

    }
    
    /**
     * start processing macro 
     *      
     * @param string $srcDocType source document type
     * @param array  &$srcValues source values
     * @param string $macroName  macro name in source array
     * @param string $macroPath  macro path in source array
     *
     * @return bool
     */
    public function postMacro($srcDocType, &$srcValues, $macroName, $macroPath)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        $targetDocuments = $this->getMacros($srcDocType, $macroName);
        $entriesCount = 0;

        // no macro to post
        if (!empty($targetDocuments)) {
            
            $ok = $this->getDocuments($macroPath, $srcValues, $targetDocuments, $targetDocValues);

            if (!empty($targetDocValues)) {
                
                $source = "SCMMacroManager::postMacro";

                $this->_QM->beginTrx($source);

                $ok = $ok && $this->postDocuments($targetDocValues, $entriesCount, $macroName);

                $ok = $ok && $this->createMacroResolve($targetDocValues, $entriesCount);

                $ok = $ok && $this->_QM->commitTrx($source);
                if (!$ok) {
                    // do *not* add error, if it has only warnings
                    if (!HasWarnings() || HasErrors()) {
                        $msg = "Could not post macros!";
                        $gErr->addIAError('INV-0799', __FILE__ . ':' . __LINE__, $msg,[]);
                    }

                    $this->_QM->rollbackTrx($source);
                }
            }
        }
        
        return $ok;

    }
    
    /**
     * creating macro link
     *      
     * @param array   $targetDocValues details about target documents
     * @param int $entriesCount    total number of entries
     *                                   
     * @return bool
     */    
    private function createMacroResolve(&$targetDocValues, $entriesCount)
    {
        $bulkArr = array();
        $bulkArr[0] = "INSERT INTO SCMMACRORESOLVE "
            . "(cny#, record#, scmmacrokey, sourcedocparkey, targetdocparkey, sourcedockey, sourcedocentrykey, "
            . "targetdockey, targetdocentrykey, createdby, modifiedby)"
            . "VALUES (:1(i),:2(i),:3(i),:4(i),:5(i),:6(i),:7(i),:8(i),:9(i),:10(i),:11(i))";
        $bulkArr[1] = array();
        $bulkArr[2] = array(
            "integer", "integer", "integer", "integer", "integer", "integer", "integer", 
            "integer", "integer", "integer", "integer"
        );

        $values = array();
        $ok = true;
        $cny = GetMyCompany();
        $currentUserRec = GetMyUserid(); 
        $res = QueryResult(array(
            "select GET_NEXTRECORDID(:1, :2, :3) recno from dual", GetMyCompany(), 'SCMMACRORESOLVE', $entriesCount)
        );
        $recno = $res[0]['RECNO'];

        foreach ( $targetDocValues as &$multipledocValues) {

            foreach ($multipledocValues as &$docValues) {

                foreach ($docValues['ENTRIES'] as $entry) {
                    $values[] = array(
                        $cny,
                        $recno++,
                        $docValues['MACROKEY'],
                        $docValues['SRCDOCPARRECORDNO'],
                        $docValues['_DOCPAR']['RECORDNO'],
                        $docValues['SRCDOCRECORDNO'],
                        $entry['SRCDOCENTRYRECORDNO'],
                        $docValues['RECORDNO'],
                        $entry['RECORDNO'],
                        $currentUserRec,
                        $currentUserRec
                    );
                }
            }
        }
        
        if (!empty($values)) {
            $bulkArr[1] = $values;
            $ok = ExecBulkStmt($bulkArr);
        }
        
        return $ok;
        
    }

    /**
     * With the passed in macroPath and entry, should the entry be included in the document creation
     *
     * @param string  $macroPath
     * @param array   $entry
     * @param string  $docType
     * @param string  $macroName
     *
     * @return bool
     */
    private function includeEntry($macroPath, $entry, $docType, $macroName)
    {
        $includeEntry = false;

        if ( $entry[$macroPath] == 'true' ) {
            //Don't include this entry if it's a LC estimate reversal and user chooses not to reverse
            if ($macroName == self::LCACTANDESTREV && $docType == InvDocumentManager::LANDEDCOSTESTREVDOCTYPE
                && ($entry['LINKLC2EST_LINK'] == null || $entry['LINKLC2EST_LINK'] == 'No estimate linked')) {
                $includeEntry = false;
            } else {
                $includeEntry = true;
            }
        }

        return $includeEntry;
    }

    /**
     * getting target documents
     *      
     * @param string  $macroPath
     * @param array   &$srcValues
     * @param array   &$targetDocuments all target documents
     * @param array   &$targetDocValues details about target documents
     *                                   
     * @return bool
     */      
    private function getDocuments($macroPath, &$srcValues, &$targetDocuments, &$targetDocValues)
    {
        $gErr = Globals::$g->gErr;
        $targetDocValues = array();
        $ok = true;
        
        foreach ($targetDocuments as $tDocType => $targetDocDetails) {

            $fromEntry = false;
            $includeDocument = false;
            $includeEntry = false;
            $groupIndex = self::TARGETFROMDOC;
            
            if ($targetDocDetails['TARGETFROM'] == 'entries') {
                $fromEntry = true;
                $includeDocument = true;
            } else {
                if ( $srcValues['SCMMACROLINK'] == 'T' ) {
                    
                    //check if the macrolink is true for the current macro
                    $oldDoc = $srcValues['EXISTING_DOC'][$srcValues['RECORDNO']];
                    if ($oldDoc[$macroPath] != 'true') {
                        continue;
                    }

                    self::getMacroErrorMessage($targetDocDetails['MACRONAME'], "MACRO007", $msg, $corr, [], $errorCode, $placeholder);
                    $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
                    $ok = false;
                    break;
                }
                
                if ( $srcValues[$macroPath] == 'true' ) {
                    $includeDocument = true;
                    $includeEntry = true;
                }
            }


            if ($includeDocument) {
                
                foreach ($srcValues['ENTRIES'] as $key => $newEntry) {

                    if ($fromEntry) {

                        if ( $newEntry['SCMMACROLINK'] == 'T' ) {
                            
                            //check if the macrolink is true for the current macro of the line
                            $oldEntry = $srcValues['EXISTING_ENTRIES'][$newEntry['RECORDNO']] ?? [];
                            if (($oldEntry[$macroPath] ?? 'false') != 'true') {
                                continue;
                            }
                            
                            if ($newEntry[$macroPath] != 'true') {
                                self::getMacroErrorMessage($targetDocDetails['MACRONAME'], "MACRO006", $msg, $corr, [], $errorCode, $placeholder);
                                $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
                                $ok = false;
                                break;
                            } else {
                                $newValues = $srcValues;
                                $this->resetValues($newValues, $macroPath);
                                $this->resetEntryValues($newEntry);
                                $newValues['ENTRIES'][] = $newEntry;
                                
                                if (!$this->compareMapFields($targetDocDetails['MAPPING'], $newValues)) {
                                    self::getMacroErrorMessage($targetDocDetails['MACRONAME'], "MACRO005", $msg, $corr, [], $errorCode, $placeholder);
                                    $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
                                    $ok = false;
                                    break;
                                } else {

                                    //nothing to do with this as it has the child document
                                    continue;
                                }
                            }
                        }

                        if ($macroPath == 'DROPSHIP' || $macroPath == 'BUYTOORDER') {
                            // Validation for Back order document
                            if ($this->hasDropShipOrBTOCreated($srcValues, $key, $macroPath)) {
                                continue;
                            }
                        }

                        $includeEntry = $this->includeEntry($macroPath, $newEntry, $tDocType, $targetDocDetails['MACRONAME']);
                        $groupIndex = $key;
                    } 
                    
                    if ($includeEntry && $targetDocDetails['STATUS'] == 'inactive'){
                        $params['SOURCE'] = $srcValues['DOCPARID']; 
                        self::getMacroErrorMessage($targetDocDetails['MACRONAME'], "MACRO001", $msg, $corr, $params, $errorCode, $placeholder);
                        $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeholder['desc1'], '', [], $corr, $placeholder['corr']);
                        $ok = false;
                        break;
                    }

                    // if no SCM Macro checked continue;
                    if ($ok && $includeEntry) {

                        $newValues = $srcValues;

                        $this->resetValues($newValues, $macroPath);
                        $this->resetEntryValues($newEntry);
                        $this->setDefaultValues($newValues, $tDocType, $targetDocDetails);

                        $newValues['ENTRIES'][] = $newEntry;

                        $ok = $ok && $this->mapFields($targetDocDetails['MAPPING'], $newValues, $groupIndex);

                        if (isset($targetDocValues[$tDocType][$groupIndex])) {
                            $targetDocValues[$tDocType][$groupIndex]['ENTRIES'][] = $newValues['ENTRIES'][0];
                        } else {
                            $targetDocValues[$tDocType][$groupIndex] = $newValues;
                        }
                    }
                }
            }

        } 
        
        return $ok;
    }

    /**
     * Method to validate the macro Values before included entry in the document creation
     *
     * @param array  $srcValues   srcValues values
     * @param array  $key    offset of entries
     * @param string  $macroPath    can be DROPSHIP or BUYTOORDER
     *
     * @return bool
     */
    private function hasDropShipOrBTOCreated($srcValues, $key, $macroPath)
    {
        // If it is not a Backorder nothing to process
        if ($srcValues['BACKORDER'] != 'Yes') {
            return false;
        }

        // Backorder entry
        $boEntry = $srcValues['ENTRIES'][$key];
        // If the document is backorder we should not create PO for drop ship or buy to order
        // we would have already created PO reference for parent document so we should validate this
        // To perform a macro for dropship and buytoorder for new line item the PO should create for that new line.
        // If not new line, we should not allow to create PO
        $hasDropShipOrBTOCreated = false;

        // This Backorder entry may have already
        if ($boEntry[$macroPath] == 'true') {
            $hasDropShipOrBTOCreated = true;

            // In backorder document user try to add the new line / modified the existing line and enabled with dropship or buy to order
            if ($srcValues['_do'] == 'edit') {
                if (isset($boEntry['RECORDNO']) && !empty($boEntry['RECORDNO'])) {
                    // for back order dropship or buytoorder enabled for existing line items it should create the PO's
                    $sql_stmt = " SELECT
                                     de.cny#,
                                     de.record#,
                                     de.dochdrkey,
                                     dhr.docid,
                                     scmmacro.targetdocentrykey,
                                     de.source_doclinekey,
                                     de.dropship,
                                     de.buytoorder
                                 FROM
                                     docentry de
                                     INNER JOIN dochdr dhr ON dhr.cny# = de.cny# AND dhr.record# = de.dochdrkey
                                     LEFT JOIN scmmacroresolve scmmacro ON scmmacro.cny# = de.cny# AND scmmacro.sourcedocentrykey = de.source_doclinekey
                                     LEFT JOIN scmmacrohdr macrohdr ON macrohdr.cny# = scmmacro.cny# AND macrohdr.record# = scmmacro.scmmacrokey AND macrohdr.name IN (:3, :4)
                                     
                                 WHERE
                                     de.cny# = :1
                                     AND scmmacro.targetdocentrykey IS NOT NULL
                                 START WITH de.cny# = :1
                                            AND de.record# = :2
                                            CONNECT BY de.record# = PRIOR de.source_doclinekey 
                                                                                            AND de.cny# = :1 
                                 ORDER BY
                                     de.record# DESC";
                    $cny = GetMyCompany();
                    $existingLinePOCreated = QueryResult([$sql_stmt, $cny, $boEntry['RECORDNO'], 'Drop ship', 'Buy to order']);

                    if (count($existingLinePOCreated ?? []) > 0) {
                        $hasDropShipOrBTOCreated = true;
                    }
                } else {
                    // for back order dropship or buytoorder enabled new line items it should create the PO's
                    $hasDropShipOrBTOCreated = false;
                }
            }
        }

        return $hasDropShipOrBTOCreated;
    }

    /**
     * Set up the document array structure in the passed in $targetDocValues for posting
     *
     * @param array &$targetDocValues details about target documents
     * @param string $macroName  macro name in target doc
     *
     * @return bool
     */
    private function setupDocumentForPosting(&$targetDocValues, $macroName)
    {
        $ok = true;
        if ($macroName == self::LANDEDCOST
            || $macroName == self::LCACTANDESTREV
            || $macroName == self::LCEST
            || $macroName == self::LCACTANDEST) {
            $ok = $ok && PODocumentManager::setupDocumentForPosting($targetDocValues, $macroName);
        }
        return $ok;
    }

    /**
     * post target documents
     *      
     * @param array &$targetDocValues details about target documents
     * @param int   $entriesCount
     * @param string $macroName  macro name in target doc
     *                                   
     * @return bool
     */
    private function postDocuments(&$targetDocValues, &$entriesCount, $macroName)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $entriesCount = 0;
        
        $docparMgr = $gManagerFactory->getManager('documentparams');
        
        $ok = $this->setupDocumentForPosting($targetDocValues, $macroName);
        if (!$ok) {
            return $ok;
        }

        foreach ($targetDocValues as $docType => &$multipledocValues) {
            $targetEntity = $docparMgr->getEntityFromDocType($docType, $tarMod);
            $docCreateOp = GetOperationId("$tarMod/lists/$targetEntity/create");
            
            if (!CheckAuthorization($docCreateOp, 1)) {
                $msg = "You are not authorized to create $docType in ".$multipledocValues[0]['MACRONAME'];
                $corr = "Contact your admin to get permission.";
                $gErr->addIAError(
                    'INV-0800', __FILE__ . ':' . __LINE__,
                    $msg, ['DOC_TYPE' => $docType, 'MACRONAME' => $multipledocValues[0]['MACRONAME']],
                    '', [],
                    $corr, []
                );
                $ok = false;
                break;
            }
            
            foreach ($multipledocValues as &$docValues) {

                $ok = $ok && $this->beforePostDocument($docValues);
                    
                $docMgr = $gManagerFactory->getManager($targetEntity, true, array( 'DOCTYPE' => $docType));
                $entriesCount += count($docValues['ENTRIES']);
                $ok = $ok && $docMgr->add($docValues);

                $ok = $ok && $this->afterPostDocument($docValues);

            }
            
            if (!$ok) {
                $msg = "Failed to create $docType in ".$multipledocValues[0]['MACRONAME'];
                $corr = "Correct the errors and try again.";
                $gErr->addIAError(
                    'INV-0832', __FILE__ . ':' . __LINE__,
                    $msg, ['DOC_TYPE' => $docType, 'MACRONAME' => $multipledocValues[0]['MACRONAME']],
                    '', [],
                    $corr, []
                );
                break;
            }
            
        }
        
        return $ok;
        
    }

    /**
     * @param array $docValues
     *
     * @return bool
     */
    private function beforePostDocument(&$docValues)
    {
        $ok = true;
        if ($docValues['MACRONAME'] == self::LANDEDCOST
            || $docValues['MACRONAME'] == self::LCACTANDESTREV
            || $docValues['MACRONAME'] == self::LCEST
            || $docValues['MACRONAME'] == self::LCACTANDEST) {
            $ok = $ok && PODocumentManager::prepareLandedCostDocument($docValues);
        }

        // calling static function from PODocumentManager, if currency set for vendor, then overwrite and assign to docvalues.
        if ( $docValues['MACRONAME'] == self::DROPSHIP
             || $docValues['MACRONAME'] == self::BTO ) {
            $ok = $ok && PODocumentManager::prepareDropshipBTODocument($docValues);
        }
        return $ok;
    }

    /**
     * @param array $docValues
     *
     * @return bool
     */
    private function afterPostDocument(&$docValues)
    {
        $ok = true;
        if ($docValues['MACRONAME'] == self::LANDEDCOST
            || $docValues['MACRONAME'] == self::LCACTANDESTREV
            || $docValues['MACRONAME'] == self::LCEST
            || $docValues['MACRONAME'] == self::LCACTANDEST) {
            $ok = $ok && PODocumentManager::processAfterCreatingLandedCostDocument($docValues);
        }
        return $ok;
    }

    /**
     * get latest macro for given document type
     *      
     * @param string $docType document type
     * @param string $macroName macro name                       
     *                                   
     * @return array target documents details
     */    
    private function getMacros($docType, $macroName)
    {
        // Get the source doc par key
        $params = array(
            'selects' => array('RECORDNO'),
            'filters' => array(
                array(
                    array('NAME', '=', $macroName),
                    array('SOURCEDOCPARID', '=', $docType),
                    array('PRIORVERSIONKEY', 'ISNULL')
                )
            ),
        );

        $recs = $this->GetList($params);
        
        $targetDocuments = array();
        if ($recs[0]['RECORDNO']) {
            
            $macro = $this->Get($recs[0]['RECORDNO']);

            foreach ($macro['MEMBERS'] as $member) {
                $targetDocuments[$member['TARGETDOCPARID']]['MACRONAME'] = $macro['NAME'];
                $targetDocuments[$member['TARGETDOCPARID']]['MACROKEY'] = $macro['RECORDNO'];
                $targetDocuments[$member['TARGETDOCPARID']]['TARGETFROM'] = $macro['TARGETDOCFROM'];
                $targetDocuments[$member['TARGETDOCPARID']]['STATUS'] = $macro['STATUS'];
                if ($member['TYPE'] == 'map') {
                    $targetDocuments[$member['TARGETDOCPARID']]['MAPPING'][$member['TARGETDOCFLD']]['PATH']
                        = $member['SOURCEDOCFLD'];
                } else {
                    $targetDocuments[$member['TARGETDOCPARID']]['MAPPING'][$member['TARGETDOCFLD']]['VALUE']
                        = $member['VALUE'];
                }
                
                $targetDocuments[$member['TARGETDOCPARID']]['MAPPING'][$member['TARGETDOCFLD']]['GROUPBY'] = false;
                if ($member['GROUPBY'] == 'true') {
                    $targetDocuments[$member['TARGETDOCPARID']]['MAPPING'][$member['TARGETDOCFLD']]['GROUPBY'] = true;
                }
                
            }

        }

        return $targetDocuments;
    }
    
    /**
     * get the xml for configuration
     *      
     * @param string $macroName    name of the macro
     * @param string $srcDocPar    source document type
     *
     * @return string xml
     */    
    private static function getMacroXML($macroName, $srcDocPar)
    {
        $stmt = array();
        $stmt[] = "SELECT macroxml FROM scmmacro WHERE cny#=:1 and name=:2";
        $stmt[] = GetMyCompany();
        $stmt[] = $macroName;
        
        $result = QueryResult($stmt);
        $macroXML = $result[0]['MACROXML'];
        
        if (empty($macroXML)) {
            $stmt = array();
            $stmt[] = "SELECT macroxml FROM iascmmacro WHERE name=:1";
            $stmt[] = $macroName;

            $result = QueryResult($stmt);
            $macroXML = $result[0]['MACROXML'];
        }
        
        $macroXML = isl_str_replace("{!SOURCEDOCPAR!}", $srcDocPar, $macroXML);

        return $macroXML;
    }

    /**
     * In the passed in XML macro, find the "{!TARGETDOCPAR!}" and replace with the passed in targetDocPar.
     *
     * @param string $inMacroXML    the XML macro
     * @param array $targetDocParArray target document type
     *
     * @return string xml
     */
    private static function updateTargetDocParInMacroXML($inMacroXML, $targetDocParArray)
    {
        $macroXML = $inMacroXML;
        foreach ($targetDocParArray as $index => $targetDocPar) {
            $searchStr = ($index == 0)? "{!TARGETDOCPAR!}" : "{!TARGETDOCPAR-" .$index ."!}";
            $macroXML = isl_str_replace($searchStr, $targetDocPar, $macroXML);
        }
        return $macroXML;
    }

    /**
     * configure macro
     *
     * @param string  $macroName    name of the macro
     * @param string  $srcDocPar    source document type
     * @param array  $targetDocParArray target document type
     * @param bool    $status       macro status
     * @param string $newMacroName a new macro name to get the macro xml
     *                                   
     * @return bool
     */     
    public static function configureMacro($macroName, $srcDocPar, $targetDocParArray, $status=true, $newMacroName=null)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $scmMacroMgr = $gManagerFactory->getManager('scmmacro');
        $ok = true;

        //No new macro name, just use the original name. Otherwise use the new macro name to get the macro xml
        if ($newMacroName == null) {
            $newMacroName = $macroName;
        }
        
        $macroXML = self::getMacroXML($newMacroName, $srcDocPar);
        $macroXML = self::updateTargetDocParInMacroXML($macroXML, $targetDocParArray);
        $values = XMLUtils::XMLStr2PHPArray($macroXML);
        $values['STATUS'] = ($status == 'true') ? 'active' : 'inactive';
        if ( is_array($values['SCMMACROMEMBERS']['SCMMACROMEMBER'][0]) ) {
            $values['MEMBERS'] = $values['SCMMACROMEMBERS']['SCMMACROMEMBER'];
        } else {
            $values['MEMBERS'] = array($values['SCMMACROMEMBERS']['SCMMACROMEMBER']);
        }
        
        if (empty($values)) {
            throw new Exception ("Error on loading XML");
        }

        //Need to see if we already have a prior macro entry in the scmmacrohdr so we can add/set below
        $hasPriorVersion = false;
        $recs = [];
        if ($macroName) {
            $params = array(
                'selects' => array('RECORDNO'),
                'filters' => array(
                    array(
                        array('NAME', '=', $macroName),
                        array('SOURCEDOCPARID', '=', $srcDocPar),
                        array('PRIORVERSIONKEY', 'ISNULL')
                    )
                ),
            );

            $recs = $scmMacroMgr->GetList($params);
            $hasPriorVersion = !empty($recs[0]['RECORDNO']);
        }

        if (!$hasPriorVersion) {
            $ok = $ok && $scmMacroMgr->add($values);
        } else {
            $values['RECORDNO'] = $recs[0]['RECORDNO'];
            $ok = $ok && $scmMacroMgr->set($values);
        }
       
        return $ok;
    }
    
    /**
     * delete the macro configured 
     *      
     * @param string $macroName name of the macro
     * @param string $srcDocPar source document type
     *
     * @return bool
     */   
    public static function deleteMacro($macroName, $srcDocPar)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $scmMacroMgr = $gManagerFactory->getManager('scmmacro');

        $params = array(
            'selects' => array('RECORDNO'),
            'filters' => array(
                array(
                    array('NAME', '=', $macroName),
                    array('SOURCEDOCPARID', '=', $srcDocPar),
                    array('PRIORVERSIONKEY', 'ISNULL')
                )
            ),
        );
        
        $recs = $scmMacroMgr->GetList($params);
        
        if (!empty($recs[0]['RECORDNO'])) {
            $ok = $scmMacroMgr->Delete($recs[0]['RECORDNO']);
        } else {
            throw new Exception ("Error on finding the macro");
        }
        
        return $ok;
    }

    /**
     * @param string $macroName
     *
     * @return array
     */
    public static function getMacroFields($macroName)
    {
        $path = isl_strtoupper($macroName);
        $path = isl_str_replace(" ", "", $path);

        $field = array(
            'path' => $path,
            'name' => $macroName,
        );
        
        switch ($macroName) {
            case self::BTO :
                $field['events']['change'] = 'changeBTO(this);';
                break;
            case self::DROPSHIP :
                $field['events']['change'] = 'changeDropShip(this);';
                break;    
        }
        return $field;
    }
    
    /**
     * @param string $macroName
     *
     * @return bool
     */
    public static function hasMacroLinkFieldInDB($macroName)
    {
        $ok = false;

        switch ($macroName) {
            case self::BTO :
            case self::DROPSHIP :
                $ok = true;
                break;
        }

        return $ok;
    }
}