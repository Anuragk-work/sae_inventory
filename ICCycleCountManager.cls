<?php

/* File header
*	FILE: ICCycleCountManager.cls
*	AUTHOR: shreerajath Hebbar <shreerajath.hebbar@sage.com>
*	DESCRIPTION: ICCycleCountManager class
*
*	(C) 2020, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/

class ICCycleCountManager extends EntityManager
{

    const ADJINCREASEDOCTYPE = "SYS-CC Adjustment Increase";
    const ADJDECREASEDOCTYPE = "SYS-CC Adjustment Decrease";
    const ADJDAMAGEDDOCTYPE  = "SYS-CC Adjustment Damaged";

    const QUANTITY_PRECISION = 4;

    /**
     * @var array   $_cycleCountData
     */
    var $_cycleCountData = array();

    /**
     * @var string    $_wareHousenId
     */
    var $_wareHousenId = "";

    /**
     * @var string    $_locationId
     */
    var $_locationId = "";

    /**
     * @var string    $_postingDate
     */
    var $_postingDate = "";


    /**
     * Overridden to to API specific validation
     *
     * @param array $values Array Set of values to update
     *
     * @return bool signifying success or failuure
     */
    public function API_Set(&$values)
    {
        // Check if API is intentionally trying to change the EMPLOYEEID of an employee
        $ok           = true;
        $gErr         = Globals::$g->gErr;
        $rowData = $this->API_Get($values['RECORDNO']);

        if ( $rowData !== false && is_array($rowData) ) {
            if ( $rowData[0]['CYCLECOUNTID'] != $values['CYCLECOUNTID'] ) {
                $gErr->addIAError('INV-0128', __FILE__ . ':' . __LINE__,
                    "CYCLECOUNTID cannot be updated or modified.",
                    []
                );
                $ok = false;
            }
        }

        return $ok && parent::API_Set($values);
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
        $source = "ICCycleCountManager::Add";

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->getNextDocNo($values);

        $ok = $ok && $this->translateValues($values);

        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);

        if (!$ok) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not create Cycle count";
                $gErr->addIAError('INV-0531', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * Set
     *
     * @param array &$values new values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $gErr = Globals::$g->gErr;
        $source = "ICCycleCountManager::Set";

        $ok = $this->_QM->beginTrx($source);

        $ok = $ok && $this->validateCyclecountEntries($values);

        $ok = $ok && $this->translateValues($values);

        if(isset($values['COUNTSTATE']) && $values['COUNTSTATE'] === ICCycleCountFormEditor::STATE_COUNTED_VALUE){
            $ok = $ok && $this->prepareValuesOnComplete($values);
        }

        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);

        if (!$ok) {
            // do *not* add error, if it has only warnings
            if (!HasWarnings() || HasErrors()) {
                $msg = "Could not update cycle count record!";
                $gErr->addIAError('INV-0532', __FILE__ . ':' . __LINE__,
                    $msg,
                    []
                );
            }

            $this->_QM->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * Delete the values for the document using the id of the document.
     *
     * @param string $ID ID of the document.
     *
     * @return bool method execution was success or not.
     */
    public function Delete($ID)
    {
        $ok = true;

        $ok = $ok && $this->canDelete($ID);

        $ok = $ok && parent::Delete($ID);

        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    private function getNextDocNo(&$values)
    {

        $gManagerFactory = Globals::$g->gManagerFactory;
        $gErr = Globals::$g->gErr;
        $invSubsMgr = $gManagerFactory->getManager('invsetup');
        $seqID = $invSubsMgr->getCycleCountSequnce();

        if (!$seqID) {
            $msg = "Could not find Document Numbering for Cycle Count";
            $gErr->addIAError('INV-0533', __FILE__ . ':' . __LINE__,
                $msg,
                []
            );
            return false;
        }

        $seqMgr = $gManagerFactory->getManager('seqnum');
        $values['CYCLECOUNTID'] = $seqMgr->GetNextSequenceNonBlocking($seqID);

        return true;
    }

    /**
     * validateCyclecountEntries method to validate the Cyclecount entries
     *
     * @param  array $values values of the transaction
     *
     * @return bool denotes if the method execution had any error or not.
     */
    function validateCyclecountEntries(&$values)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;

        if( (!is_array($values['CYCLECOUNTENTRY']) || count($values['CYCLECOUNTENTRY']) == 0)
             && $values['COUNTSTATE'] === ICCycleCountFormEditor::STATE_INPROGRESS_VALUE ){
            $msg = "Add items to the count. Then, start the count again";
            $gErr->addIAError('INV-0534', __FILE__ . ':' . __LINE__,
             "Count ID " . $values['CYCLECOUNTID'] . " does not have any items to count.",
             ['VALUES_CYCLECOUNTID'=>$values['CYCLECOUNTID']],
             $msg,[]);
            $ok = false;

        }

        if( (!is_array($values['CYCLECOUNTENTRY']) || count($values['CYCLECOUNTENTRY']) == 0)
            && $values['COUNTSTATE'] === ICCycleCountFormEditor::STATE_NOTSTARTED_VALUE ){
            $msg = "Add items to the count. Then, use update quantity on hand for the count";
            $gErr->addIAError('INV-0535', __FILE__ . ':' . __LINE__,
             "Count ID " . $values['CYCLECOUNTID'] . " does not have any items to update count.",
             ['VALUES_CYCLECOUNTID'=>$values['CYCLECOUNTID']],
             $msg,[]);
            $ok = false;

        }

        if( ( isset($values['COUNTSTATE']) && $values['COUNTSTATE'] === ICCycleCountFormEditor::STATE_COUNTED_VALUE )){
            foreach ($values['CYCLECOUNTENTRY'] as &$cycleCountEntry ) {
                if (isset( $cycleCountEntry['LINECOUNTSTATE'] ) && $cycleCountEntry['LINECOUNTSTATE'] == 'Not Counted') {
                    $msg = "Enter quantities for the items or mark them as skipped.
                     Then, complete the count again.";
                    $gErr->addIAError(
                        'INV-0536', __FILE__ . ':' . __LINE__,
                        'One or more items have a status of not counted.',
                        [],
                        $msg,
                        []
                    );
                    $ok = false;
                    break;
                }
            }
        }

        return $ok;
    }


    /**
     * validateCyclecountEntries method to validate the Cyclecount entries
     *
     * @param  array $values values of the transaction
     *
     * @return bool denotes if the method execution had any error or not.
     */
    function populateOnHandQtyOnStartCyclecount(&$values)
    {
        $ok = true;

        $requestParams['EXCLUDEALLOCATEDQTY'] = $values['EXCLUDEALLOCATEDQTY'];
        if( isset($values['WAREHOUSEID']) && $values['WAREHOUSEID'] != ''){

            $uniquePropOnRowData  = [];
            $cycleCountData       = $this->executeCycleCountQuery($values['WAREHOUSEID'], false, false, $requestParams);

            if( is_array($cycleCountData) && count($cycleCountData) > 0){

                foreach ($cycleCountData as $key => $ccData){
                    $uniquePropOnRowData[$key] =  $ccData['UNIQUEPROPONROW'];
                }

                foreach ($values['CYCLECOUNTENTRY'] as &$ccEntry){
                    if(in_array($ccEntry['UNIQUEPROPONROW'], $uniquePropOnRowData )){
                        $index = array_search($ccEntry['UNIQUEPROPONROW'], $uniquePropOnRowData);
                        $ccEntry['QUANTITYONHAND'] = $cycleCountData[$index]['QUANTITYONHAND'];
                        $ccEntry['QOHLASTUPDATED'] = $ccEntry['QUANTITYONHAND'];
                    }
                }
            } else if (!is_array($cycleCountData) && $cycleCountData === false) {
                // return false in case of query error
                return false;
            }
        }

        return $ok;
    }

    /**
     * getSkipCycleCountList method to validate the Cyclecount entries
     *
     * @param array $cyclecountEntries values of the transaction
     * @param string $warehouseId
     *
     * @return bool
     */
    function getSkipCycleCountList(&$cyclecountEntries, $warehouseId)
    {
        $stmt = [];
        $uniquePropOnRowData = [];
        $itemsSkipped = false;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $cny = GetMyCompany();

        //Prepairing BIN, SERIAL NUMBER and LOT NUMBER information if required or else we ignore it.
        $warehouseMgr = $gManagerFactory->getManager('warehouse');
        $warehouseFilter = array(
            'selects' => array('RECORDNO'),
            'filters' => array (array (array('LOCATIONID', '=', $warehouseId))),
        );
        $warehouseDetails = $warehouseMgr->GetList($warehouseFilter);

        $stmt[0] = "SELECT
                            ice.uniqueproponrow
                        FROM
                            iccyclecount        ic,
                            iccyclecountentry   ice
                        WHERE
                            ic.cny# = :1
                            AND ice.cny# = ic.cny#
                            AND ic.record# = ice.cyclecountkey (+)
                            AND ic.warehousekey = :2
                            AND ic.countstate = 'I'";

        $stmt[1] = $cny;
        $stmt[2] = $warehouseDetails[0]['RECORDNO'];

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetReportViewContext();
        }
        $resultArray  = QueryResult($stmt);

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetTransactionViewContext();
        }

        if( is_array($resultArray) && count($resultArray) > 0 ) {
            
            foreach ($resultArray as $result) {
                $uniquePropOnRowData[] = $result['UNIQUEPROPONROW'];
            }

            foreach ($cyclecountEntries as &$cyclecountEntry){
                if(!empty($cyclecountEntry['UNIQUEPROPONROW'])
                   && in_array($cyclecountEntry['UNIQUEPROPONROW'], $uniquePropOnRowData )){
                    $cyclecountEntry['LINECOUNTSTATE'] = 'Skipped';
                    $cyclecountEntry['ADJUSTMENTREASON'] = 'In another count';
                    unset($cyclecountEntry['COUNTEDBYID']);
                    unset($cyclecountEntry['COUNTEDBYKEY']);
                    $itemsSkipped= true;
                }
            }
        }

        return $itemsSkipped;
    }

    /**
     * postAdjustments method to validate the Cyclecount entries
     *
     * @param array $cycleCountData
     * @param array $mappingEntries
     *
     * @return bool
     */
    function postAdjustments($cycleCountData, &$mappingEntries)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $adjDocEntries = [];

        //preparing cyclecount data.
        $this->_cycleCountData = $cycleCountData;
        $this->_wareHousenId = $this->_cycleCountData['WAREHOUSEID'];
        $this->_postingDate = $this->_cycleCountData['ADJUSTMENTPOSTDATE'];

        $source = "CycleCountManager::postAdjustments";

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetReportViewContext();
        }

        //Prepairing locationid for the transaction entries to be created
        $warehouseMgr = $gManagerFactory->getManager('warehouse');
        $warehouseFilter = array(
            'selects' => array('LOC.LOCATIONID'),
            'filters' => array (array (array('LOCATIONID', '=', $this->_wareHousenId))),
        );
        $warehouseDetails = $warehouseMgr->GetList($warehouseFilter);

        if(isset($warehouseDetails[0]['LOC.LOCATIONID']) && $warehouseDetails[0]['LOC.LOCATIONID'] != ''){
            $this->_locationId  = $warehouseDetails[0]['LOC.LOCATIONID'];
        }

        if((empty($this->_locationId) || $this->_locationId == '') && IsMultiEntityCompany()){
            $msg = 'A location must be specified for warehouse '. $this->_wareHousenId;
            $gErr->addIAError('INV-0537', __FILE__ . ':' . __LINE__,
            'Location is missing for the selected warehouse.',[],
             $msg,['HOUSEN_ID'=>$this->_wareHousenId]);
            return false;
        }

        $ok = $ok && $this->_QM->beginTrx($source);

        //preparing Adjustment entry data here for Increase, Decrease and Damaged.
        $ok = $ok && $this->prepAdjustmentEntries($adjDocEntries);

        //Prepare Adjustment Increase Transactions
        if( $ok && is_array($adjDocEntries[self::ADJINCREASEDOCTYPE]) && count($adjDocEntries[self::ADJINCREASEDOCTYPE]) > 0){
            $mgr = Globals::$g->gManagerFactory->getManager(
                'invdocument', true, ['DOCTYPE' => self::ADJINCREASEDOCTYPE]
            );

            $increaseAdjData = $this->prepareTransactionData($adjDocEntries[self::ADJINCREASEDOCTYPE], self::ADJINCREASEDOCTYPE);

            $ok = $ok && $mgr->regularAdd($increaseAdjData);

            //Each cyclecount entry can have either increase or decrease + Damaged (Not mandatory).
            foreach ($increaseAdjData['ENTRIES'] as $entry) {
                $entryMap = ['DOCHDRKEY' => $entry['DOCHDRNO'],
                             'DOCENTRYKEY' => $entry['RECORDNO']
                ];
                $mappingEntries[$entry['CCENTRYKEY']][self::ADJINCREASEDOCTYPE] = $entryMap;
            }
            unset($increaseAdjData);
        }

        //Prepare Adjustment Decrease Transactions
        if( $ok && is_array($adjDocEntries[self::ADJDECREASEDOCTYPE]) && count($adjDocEntries[self::ADJDECREASEDOCTYPE]) > 0){
            $mgr = Globals::$g->gManagerFactory->getManager(
                'invdocument', true, ['DOCTYPE' => self::ADJDECREASEDOCTYPE]
            );

            $decreaseAdjData = $this->prepareTransactionData($adjDocEntries[self::ADJDECREASEDOCTYPE], self::ADJDECREASEDOCTYPE);

            $ok = $ok && $mgr->regularAdd($decreaseAdjData);

            //Each cyclecount entry can have either increase or decrease + Damaged (Not mandatory).
            foreach ($decreaseAdjData['ENTRIES'] as $entry) {
                $entryMap = ['DOCHDRKEY' => $entry['DOCHDRNO'],
                             'DOCENTRYKEY' => $entry['RECORDNO']
                ];
                $mappingEntries[$entry['CCENTRYKEY']][self::ADJDECREASEDOCTYPE] = $entryMap;
            }
            unset($decreaseAdjData);
        }

        //Prepare Adjustment Damaged Transactions
        if( $ok && is_array($adjDocEntries[self::ADJDAMAGEDDOCTYPE]) && count($adjDocEntries[self::ADJDAMAGEDDOCTYPE]) > 0){
            $mgr = Globals::$g->gManagerFactory->getManager(
                'invdocument', true, ['DOCTYPE' => self::ADJDAMAGEDDOCTYPE]
            );

            $damagesAdjData = $this->prepareTransactionData($adjDocEntries[self::ADJDAMAGEDDOCTYPE], self::ADJDAMAGEDDOCTYPE);

            $ok = $ok && $mgr->regularAdd($damagesAdjData);
            //Each cyclecount entry can have either increase or decrease + Damaged (Not mandatory).
            foreach ($damagesAdjData['ENTRIES'] as $entry) {
                $entryMap = ['DOCHDRKEY' => $entry['DOCHDRNO'],
                             'DOCENTRYKEY' => $entry['RECORDNO']
                ];
                $mappingEntries[$entry['CCENTRYKEY']][self::ADJDAMAGEDDOCTYPE]= $entryMap;
            }
            unset($damagesAdjData);
        }

        if (!$ok) {
            $this->_QM->rollbackTrx($source);
        } else {
            $ok = $ok && $this->_QM->commitTrx($source);
            if (!$ok) {
                if (Request::$r->_kNoWarn != 'true' && Request::$r->_kNoDupl != 'true') {
                    $msg = "Could not post the Adjustment for Cyclecount record!";
                    $gErr->addIAError('INV-0538', __FILE__ . ':' . __LINE__,
                        $msg,
                        []
                    );
                    epp("$source: Error: $msg");
                }
                $this->_QM->rollbackTrx($source);
            }
        }

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetTransactionViewContext();
        }

        return $ok;
    }

    /**
     * hasTrackingDetails method to validate the Cyclecount entries
     *
     * @param  array $cycleCountEntry
     *
     * @return bool denotes if the method execution had any error or not.
     */
    private function hasTrackingDetails($cycleCountEntry)
    {
        $ok = false;

        if( isset($cycleCountEntry['SERIALNO']) || $cycleCountEntry['SERIALNO'] != ''
            || isset($cycleCountEntry['LOTNO']) || $cycleCountEntry['LOTNO'] != ''
            || isset($cycleCountEntry['BINID']) || $cycleCountEntry['BINID'] != ''
            || isset($cycleCountEntry['EXPIRATIONDATE']) || $cycleCountEntry['EXPIRATIONDATE'] != ''){
            $ok = true;
        }

        return $ok;
    }


    /**
     * prepAdjustmentEntries method to validate the Cyclecount entries
     *
     * @param array $adjDocEntries
     *
     * @return bool
     */
    private function prepAdjustmentEntries(&$adjDocEntries)
    {
        $ok = true;
        $gErr = Globals::$g->gErr;

        foreach ($this->_cycleCountData['CYCLECOUNTENTRY'] as $cycleCountEntry ){
            //Even though we have client side validation. For serial items quantity can be either 0 or 1.
            // So we are validating at server side also to make sure data provided is proper and not modified.
            if(isset($cycleCountEntry['SERIALNO']) && $cycleCountEntry['SERIALNO'] != ''){

                $enteredqtyActualAdj  = $cycleCountEntry['ACTUALADJ'];
                $qtyActualAdj  = ibcabs($cycleCountEntry['ACTUALADJ']);
                $qtyDamagedAdj = ibcabs($cycleCountEntry['ACTUALDMGADJ']);

                if($qtyActualAdj > 1 || $qtyDamagedAdj > 1){
                    $msg = "The item is enabled for serial tracking.
                            Enter a value of 1 or 0 or -1 for Adjustment or 1 or 0 for Damage adj.";
                    $gErr->addIAError(
                        'INV-0539', __FILE__ . ':' . __LINE__,
                        'The item is enabled for serial tracking',
                        [],
                        $msg,
                        []
                    );
                    $ok = false;
                    break;
                } else if( ibcadd($enteredqtyActualAdj, $qtyDamagedAdj, 4, true) > 1){
                    $msg = "The item is enabled for serial tracking.".
                           " Enter a value of 1 or 0 or -1 for either Adjustment or Damage adj.";
                    $gErr->addIAError(
                        'INV-0676', __FILE__ . ':' . __LINE__,
                        'The item is enabled for serial tracking.',
                        [],
                        $msg,
                        []
                    );
                    $ok = false;
                    break;
                }
                $cycleCountEntry['ISSERIALIZED'] = true;
            }

            //Prepare tracking in for each item here so that it will be used in future for validations.
            $cycleCountEntry['TRACKING_ENABLED'] = $this->hasTrackingDetails($cycleCountEntry);

            //Check for Suggested values and populate increase or decrease array based on that.
            if(isset($cycleCountEntry['ACTUALADJ']) && $cycleCountEntry['ACTUALADJ'] > 0){
                $adjDocEntries[self::ADJINCREASEDOCTYPE][] = $cycleCountEntry;
            } else if( $cycleCountEntry['ACTUALADJ'] < 0){
                $cycleCountEntry['ACTUALADJ'] = $cycleCountEntry['ACTUALADJ'] * -1;
                $adjDocEntries[self::ADJDECREASEDOCTYPE][] = $cycleCountEntry;
            }

            //Even though we have client side validation. For serial items quantity can be either 0 or 1.
            // So we are validating at server side also to make sure data provided is proper and not modified.
            if(isset($cycleCountEntry['ACTUALDMGADJ']) && $cycleCountEntry['ACTUALDMGADJ'] > 0){
                $adjDocEntries[self::ADJDAMAGEDDOCTYPE][] = $cycleCountEntry;
            }
        }

        return $ok;
    }

    /**
     * Creates prepareTransactionHeaderData and cancel buttons for new form state.
     *
     * @param string $docType
     *
     * @return array
     */
    private function prepareTransactionHeaderData($docType)
    {

        if(isset($this->_postingDate) && $this->_postingDate != ''){
            $postingDate    = $this->_postingDate;
        } else {
            $postingDate    = convert8601ToLocalDate(GetTimestampGMT());
        }

        $cycleCountData = $this->_cycleCountData;

        //Preparing Header data
        $adjHeaderData = [
            '_do' =>'create',
            'DOCPARID' => $docType,
            'WHENCREATED' => $postingDate,
            'DOCNO' => "ADJ-".$cycleCountData['CYCLECOUNTID'],
            'PONUMBER' => $cycleCountData['CYCLECOUNTID'],
            'MESSAGE' => "Adjustment for ".$cycleCountData['CYCLECOUNTID'],
            'STATE' => 'Closed',
            'BASECURR' => GetBaseCurrency(),
            'ALLOWCREATION' => true,
        ];

        return $adjHeaderData;
    }


    /**
     * Creates prepareTransactionEntryData and cancel buttons for new form state.
     *
     * @param array $adjustmentEntries
     * @param string $docType
     *
     * @return array
     */
    private function prepareTransactionEntryData($adjustmentEntries, $docType)
    {
        $adjEntryData   = [];
        $warehouseId = $this->_wareHousenId;
        $locationId  = $this->_locationId;

        foreach ($adjustmentEntries as $entry ){
            $trackingDetails = [];

            if($docType == self::ADJDAMAGEDDOCTYPE){
                $qty =  $entry['ACTUALDMGADJ'] ?? 0;
                $uiPrice = 0;
            } else {
                $qty =  $entry['ACTUALADJ']  ?? 0;
                $uiPrice =  $entry['UNITCOST']  ?? 0;
            }

            if($entry['TRACKING_ENABLED']){
                //prepare tracking entires if present
                if(isset($entry['SERIALNO']) && $entry['SERIALNO'] != ''){
                    $trackingDetails['ITEMID'] = $entry['ITEMID'];
                    $trackingDetails['SERIALNO'] = $entry['SERIALNO'];
                }

                if(isset($entry['LOTNO']) && $entry['LOTNO'] != ''){
                    $trackingDetails['LOTNO'] = $entry['LOTNO'];
                }

                if(isset($entry['EXPIRATIONDATE']) && $entry['EXPIRATIONDATE'] != ''){
                    $trackingDetails['EXPIRATION'] = $entry['EXPIRATIONDATE'];
                }

                if(isset($entry['BINID']) && $entry['BINID'] != ''){
                    $trackingDetails['BINID'] = $entry['BINID'];
                    $trackingDetails['AISLEID'] = $entry['AISLEID'];
                    $trackingDetails['ROWID'] = $entry['ICROWID'];
                }

                $trackingDetails['TRACK_QUANTITY'] = $qty;
                $trackingDetails['QUANTITY'] = $qty;
            }

            $thisentry = [
                '__dummy' => '',
                '_isNewLine' => 1,
                'ITEMID' => $entry['ITEMID'],
                'WAREHOUSE' => [
                    'LOCATION_NO' => $warehouseId,
                ],
                'UIQTY' => $qty,
                'UNIT' => $entry['ITEMUNIT'],
                'UIPRICE' => $uiPrice,
                'LOCATION' => $locationId,
                'COST_METHOD' => $entry['COST_METHOD'],
                'ISSERIALIZED' => isset($entry['ISSERIALIZED']) ?? false,
                'CCENTRYKEY' => $entry['RECORDNO'],
            ];

            if(is_array($trackingDetails) && count($trackingDetails) > 0){
                $thisentry['TRACKINGENTRIES'] = [$trackingDetails];
            }
            $thisentry = $this->prepareDimensionDataForTransactionEntry($thisentry, $entry);
            $adjEntryData[] = $thisentry;
        }

        return $adjEntryData;
    }

    /**
     * Creates prepareTransactionData and cancel buttons for new form state.
     *
     * @param array $adjustmentEntries
     * @param string $docType
     *
     * @return array
     */
    private function prepareTransactionData($adjustmentEntries, $docType)
    {
        $adjData = $this->prepareTransactionHeaderData($docType);
        $adjData['ENTRIES'] = $this->prepareTransactionEntryData($adjustmentEntries, $docType);
        return $adjData;
    }

    /**
     * If the customer fills in optional ID fields, look up the KEY values (record#) for them.
     *
     * @param array $values
     *
     * @return bool
     */
    function translateValues(&$values)
    {
        $ok = true;
        // Transalate WAREHOUSE values to their KEY repspectively.
        $cyclecountArr = array(
            'WAREHOUSE' => 'warehouse',
            'EMPUSER' => 'EMPUSER',
        );
        foreach ($cyclecountArr as $key => $manager) {
            $ccId  = $key . 'ID';
            $ccKey = $key . 'KEY';

            if (isset($values[$ccId]) && $values[$ccId] != '') {
                $recordNumber = $this->keyForId($ccId, $values[$ccId]);
                if ($recordNumber) {
                    $values[$ccKey] = $recordNumber;
                } else {
                    $tokenParam = array(
                        'errorCode' => 'INV-0654',
                        'placeHolder' => array(
                               'CCID' => $ccId,
                              'VALUES_CCID' => $values[$ccId]
                        )
                    );

                    $ok = $this->error($values, sprintf('The %1$s called "%2$s" does not exist.', $ccId, $values[$ccId]),$tokenParam);
                }
            }
        }

        /*if(is_array($values['CYCLECOUNTENTRY']) && count($values['CYCLECOUNTENTRY']) > 0){
            foreach ($values['CYCLECOUNTENTRY'] as $key => &$entries) {
                $this->translateEntryValues( $entries );
            }
        }*/

        if(is_array($values['CYCLECOUNTENTRY']) && count($values['CYCLECOUNTENTRY']) > 0) {

            foreach ($values['CYCLECOUNTENTRY'] as &$entries) {
                if( isset($entries['COUNTEDBYID']) && $entries['COUNTEDBYID'] != '' ){
                    $employeeMgr  = Globals::$g->gManagerFactory->getManager('employee');
                    $filter = array(
                        'selects' => array('RECORDNO'),
                        'filters' => array(
                            array(
                                array('EMPLOYEEID', '=', $entries['COUNTEDBYID']),
                            )
                        ),
                    );
                    $res = $employeeMgr->GetList($filter);
                    if ($res[0]['RECORDNO']) {
                        $entries['COUNTEDBYKEY'] = $res[0]['RECORDNO'];
                    } else {

                       $tokenParam = array(
                        'errorCode' => 'INV-0655',
                        'placeHolder' => ['ENTRIES_COUNTEDBYID' => $entries['COUNTEDBYID']]
                       );
                        $ok = $this->error($entries, sprintf('The COUNTEDBYID called "%1$s" does not exist.', $entries['COUNTEDBYID']), $tokenParam);
                    }
                }
            }
        }

        return $ok;
    }

    /**
     *      If the customer fills in optional ID fields, look up the KEY values (record#) for them.
     *
     * @param array $entries
     *
     * @return bool
     */
    function translateEntryValues(&$entries)
    {

        $ok = true;

        $cyclecountEntryArr = array(
            'ITEM'      => 'icitem',
            'BIN'       => 'bin',
            'AISLE'     => 'aisle',
            'ICROW'     => 'icrow',
            //'ZONE'    => 'zone',
            //'COUNTEDBY'  => 'countedby'
        );
        foreach ($cyclecountEntryArr as $key => $manager) {
            $ccId  = $key . 'ID';
            $ccKey = $key . 'KEY';

            if (isset($entries[$ccId]) && $entries[$ccId] != '') {
                $recordNumber = $this->keyForEntryId($ccId, $entries[$ccId]);

                if ($recordNumber) {
                    $entries[$ccKey] = $recordNumber;
                } else {

                $tokenParam = array(
                    'errorCode' => 'INV-0656',
                    'placeHolder' => array(
                           'CCID' => $ccId,
                          'ENTRIES_CCID' => $entries[$ccId]
                    )
                );

                    $ok = $this->error($entries, sprintf('The %1$s called "%2$s" does not exist.', $ccId, $entries[$ccId]), $tokenParam);
                }
            }
        }
        return $ok;
    }



    /**
     *      This will lookup the RECORD# (key) of a given ID.  For example, you can get the AISLE RECORD#
     * from the AISLEID.  This works whether or not we're cached.  Also cleans up the id for later use
     *
     * @param string    $type         one of SIZEID, ROWID, AISLEID, FACEID, ZONEID, WAREHOUSEID, or BINID.
     * @param string    $id           the id of the record
     *
     * @return int                  the record# (key); 0 if no such record
     */
    private function keyForId($type, &$id)
    {
        $keyForTable = [
            'WAREHOUSEID'        => ['icwarehouse', 'location_no'],
            'EMPUSERID'             => ['employee',     'employeeid'],
        ];

        $type = strtoupper(trim($type));
        $id   = trim($id);
        if ($id == '') {
            return 0;       // not specified?  then not found.
        }
        if ( ! isset($keyForTable[$type])) {
            throw new Exception("[Code bug]bad TYPE parameter for keyForId: $type");
        }


        $table  = $keyForTable[$type][0];
        $column = $keyForTable[$type][1];

        // oterwise, sadly, look it up
        $result = QueryResult(["select record# from $table where cny#=:1 and $column=:2", GetMyCompany(), $id]);
        if (($result !== false) && ( ! empty($result))) {
            return $result[0]['RECORD#'];
        }
        return 0;   // not found
    }

    /**
     *      This will lookup the RECORD# (key) of a given ID.  For example, you can get the AISLE RECORD#
     * from the AISLEID.  This works whether or not we're cached.  Also cleans up the id for later use
     *
     * @param string    $type         one of SIZEID, ROWID, AISLEID, FACEID, ZONEID, WAREHOUSEID, or BINID.
     * @param string    $id           the id of the record
     *
     * @return int                  the record# (key); 0 if no such record
     */
    private function keyForEntryId($type, &$id)
    {

        $keyForEntryTable = [
            'ITEMID'            =>  ['icitem',      'itemid'],
            'BINID'             => ['icbin',       'binid'],
            'AISLEID'           => ['icaisle',     'aisleid'],
            'ICROWID'           => ['icrow',       'rowkey'],
            //'ZONEID'          => ['iczone',      'zoneid'],
            //'COUNTEDBYID'       => ['employee',  'employeeid'],
        ];

        $type = strtoupper(trim($type));
        $id   = trim($id);
        if ($id == '') {
            return 0;       // not specified?  then not found.
        }
        if ( ! isset($keyForEntryTable[$type])) {
            throw new Exception("[Code bug]bad TYPE parameter for keyForId: $type");
        }


        $table  = $keyForEntryTable[$type][0];
        $column = $keyForEntryTable[$type][1];

        // oterwise, sadly, look it up
        $result = QueryResult(["select record# from $table where cny#=:1 and $column=:2", GetMyCompany(), $id]);
        if (($result !== false) && ( ! empty($result))) {
            return $result[0]['RECORD#'];
        }
        return 0;   // not found
    }

    /**
     *      Output an error message with an optional ROW (from the importer)
     *
     * @param array     $values         where I might find 'ROW'
     * @param string    $message        error message
     *
     * @return bool                     false, in case that is useful
     */
    private function error($values, $message, $param=array())
    {
        $placeHolder = [];
        $placeHolderText = '';
        if(isset($param['placeHolder'])){
             $placeHolder = $param['placeHolder'];
        }
        $row = $values['ROW'] ?? 0;
        if ($row) {
            $message .= sprintf(", on row %1s", $row);
            $placeHolderText = I18N::getSingleToken("IA.ON_ROW", ['ROW' => $row]);
        }
        $placeHolder = array_merge($placeHolder,['MSG' => $placeHolderText]);
        // Get the line and file of the CALLER
        $stack = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 2);
        $arr = array_shift($stack); // get the file which called this function
        $file = $arr['file'];
        $line = $arr['line'];
        Globals::$g->gErr->addIAError($param['errorCode'], $file . ':' . $line,  $message, $placeHolder);
        //i18N::TODO - (Code Change Review)
        return false;
    }

    /**
     * @param string      $recordNo
     *
     * @return bool
     */
    public function canEdit($recordNo)
    {
        $ok = true;
        $filter = array(
            'selects' => array('COUNTSTATE'),
            'filters' => array(
                array(
                    array('RECORDNO', '=', $recordNo)
                )
            )
        );
        $res = $this->GetList($filter);
        $states = [ ICCycleCountFormEditor::STATE_COUNTED_VALUE, ICCycleCountFormEditor::STATE_VOIDED_VALUE,
                        ICCycleCountFormEditor::STATE_RECONCILED_VALUE ];

        if( isset($res[0]['COUNTSTATE']) && in_array($res[0]['COUNTSTATE'], $states) ) {
            $ok = false;
        }

        return $ok;
    }

    /**
     * executeCycleCountQuery to get the QOH for all the entered cycle count entries
     *
     * @param string $warehouseKey
     * @param bool $fromGetCount
     * @param bool $fromInsertCount
     * @param array $requestParams
     *
     * @return bool|array $addedRows  the rows added in JSON format so that they can be added to the entry grid or false in case of query failure
     */
    public function executeCycleCountQuery($warehouseKey, $fromGetCount = false, $fromInsertCount= false, $requestParams = [])
    {
        $kINVid = Globals::$g->kINVid;
        $gQueryMgr = Globals::$g->gQueryMgr;
        GetModulePreferences($kINVid, $invPrefs);

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetReportViewContext();
        }

        //Query select and condition parameter based on the Inventory configuration
        $aislerowbinSelect = '';
        $aislerowbinFrom = '';
        $aislerowbinWhere = '';
        $aislerowbinGroupBy = '';
        $serialNoSelect = '';
        $serialNoGroupBy = '';
        $lotNoSelect = '';
        $lotNoGroupBy = '';
        $expDateSelect ='';
        $expDateGroupBy = '';
        $pageSize = -1;

        //select qtyOnHand value to get physical inventory quantity
        $selectQtyOnHandField = "SUM(DECODE(doccost.in_out, 'I', doccost.quantity, -doccost.quantity)) quantityonhand";

        //Filter logic on the CYCLECOUNTRECORD Grid, By defalut no filter applied
        $gridFieldsFilter = '';
        //To Filter the items which are already in CYCLECOUNTENTRY Grid,
        $uniqueKeyFilter = '';
        $params = [];

        //Default Order by is besed on Item Id, thet can be oveeridden by Grid lister Sort Action
        $orderBy = 'order by item.itemid asc';

        //For uniquekey generate logic to keep it consistant
        //$aislerowbinKeySelect = "'' || '#' || '' || '#' || '' || '#' || ";
        $aislerowbinKeySelect = "'' || '#' || ";
        $serialNoKeySelect    = "'' || '#' || ";
        $lotNoKeySelect       = "''";
        $expDateKeySelect     = "";

        //Sample Data for Creating UNIQUEPROPONROW
        // icitem.record#: 23
        // icicbin.record#: 12
        // serialNo: A001
        // lot no: Lot1
        // Exipration : 12/02/2022

        //This is the sample UNIQUEPROPONROW for cyclecount entry.
        //23#12#A001#Lot112/01/2022

        $cny = GetMyCompany();

        if(isset($invPrefs['ENABLEBIN']) && $invPrefs['ENABLEBIN'] == 'T') {
            $aislerowbinSelect =   "whsebin.binid        BINID,
                                    whsebin.record#      BINKEY,
                                    whserow.rowkey       ICROWID,
                                    whserow.record#      ROWKEY,
                                    whseaisle.aisleid    AISLEID,
                                    whseaisle.record#    AISLEKEY,
                                    whsezone.zoneid      ZONEID,
                                    whsezone.record#     ZONEKEY,";

            $aislerowbinFrom  =    "icaisle        whseaisle,
                                    icrow          whserow,
                                    icbin          whsebin,
                                    iczone         whsezone,";

            $aislerowbinWhere =    "AND doccost.cny# = whseaisle.cny# (+)
                                    AND doccost.cny# = whserow.cny# (+)
                                    AND doccost.cny# = whsebin.cny# (+)
                                    AND doccost.cny# = whsezone.cny# (+)
                                    AND doccost.binkey = whsebin.record# (+)
                                    AND whsebin.aislekey = whseaisle.record# (+)
                                    AND whsebin.rowkey = whserow.record# (+)
                                    AND whsebin.zonekey = whsezone.record# (+)";

            $aislerowbinGroupBy=   "whsebin.binid,
                                    whsebin.record#,
                                    whserow.rowkey,
                                    whserow.record#,
                                    whseaisle.aisleid,
                                    whseaisle.record#,
                                    whsezone.zoneid,
                                    whsezone.record#,";

            //$aislerowbinKeySelect = "whsebin.record# || '#' || whserow.record# || '#' || whseaisle.record# || '#' ||";
            $aislerowbinKeySelect = "whsebin.record# || '#' ||";
        }

        if(isset($invPrefs['ENABLESERIAL']) && $invPrefs['ENABLESERIAL'] == 'T') {
            $serialNoSelect       = "doccost.serialno  SERIALNO,";

            $serialNoKeySelect    = "doccost.serialno || '#' || ";

            $serialNoGroupBy      = "doccost.serialno,";
        }

        if(isset($invPrefs['ENABLELOT']) && $invPrefs['ENABLELOT'] == 'T') {
            $lotNoSelect    = "doccost.lotno  LOTNO,";

            $lotNoKeySelect = "doccost.lotno";

            $lotNoGroupBy   = "doccost.lotno,";
        }

        if(isset($invPrefs['ENABLE_EXPIRATION']) && $invPrefs['ENABLE_EXPIRATION'] == 'T') {
            $expDateSelect    = "doccost.expirationdate  EXPIRATIONDATE,";

            $expDateKeySelect = "|| doccost.expirationdate";

            $expDateGroupBy   = "doccost.expirationdate,";
        }

        $uniquePropOnRow = "item.record# || '#' || ".$aislerowbinKeySelect.$serialNoKeySelect.$lotNoKeySelect.$expDateKeySelect;

        // If it is from getCycleCountData function we need to Add filter, order by and start and max count,
        // if applicable for the Server Side Pagination. Below code will perform that logic based on the SSP request
        if($fromGetCount || $fromInsertCount){

            $cycleCountkey = $requestParams['CYCLECOUNTKEY'];

            if($fromInsertCount && $requestParams['SELECTIONSTATE'] === ICCycleCountFormEditor::NONE_EXCEPT_SOME){
                $fieldFilter= [];
            } else {
                //Adding Filter on the CYCLECOUNTRECORD Grid if any field filter applied
                $fieldFilter = $this->getFilters($requestParams, $fromGetCount);
            }

            if( is_array($fieldFilter) && count($fieldFilter) > 0){

                $processedFilter = $this->processFieldsFilter($fieldFilter);
                // Get the query filters
                if(isset($processedFilter) && $processedFilter != ''){
                    $gridFieldsFilter = $processedFilter;
                }
            }

            //Adding order by on the CYCLECOUNTRECORD Grid if any field sort applied.
            $orders = $requestParams['ORDERS'];
            if (!empty($orders)) {
                $processedOrderBy = $this->processOrderBy($orders);
                if(isset($processedOrderBy) && $processedOrderBy != ''){
                    $orderBy = $processedOrderBy;
                }
            }

            //Finally we need to exclude the entries which are already selected in CYCLECOUNTRECORD Grid from the
            //floating page. Basically we are getting stored data from the table and skipping them.
            //Get the uniqueKeys which are alredy in the main Grid to exclude from the adding to main Grid
            // to avoids duplicate entries.
            $uniqueKeys =  $this->getUniqueKeyFilterParams($cycleCountkey);

            if($fromGetCount){
                $page = $requestParams['PAGE'];
                $pageSize = $requestParams['PAGESIZE'];

                if ( $page !== -1 && $pageSize !== -1) {
                    $params['start'] = $page * $pageSize;
                    $params['max'] = $pageSize;
                }

                if( is_array($uniqueKeys) && count($uniqueKeys) > 0){
                    $uniqueKeyFilter = PrepINClauseStmt('', $uniqueKeys, " AND ($uniquePropOnRow) NOT",
                        true,'cyclecount',true);
                }
            } else {
                // If it is from getCycleCountData function we need to Add filter, order by and start and max count,
                // if applicable for the Server Side Pagination.Below code will perform that logic based on the SSP request
                $selectionState = $requestParams['SELECTIONSTATE'];
                if( isset($selectionState)){
                    if($selectionState === ICCycleCountFormEditor::ALL || $selectionState === ICCycleCountFormEditor::ALL_EXCEPT_SOME){
                        if( is_array($uniqueKeys) && count($uniqueKeys) > 0){
                            //For ALL_EXCEPT_SOME we need to merge the requestParam array with the uniqueKeys which is already
                            // existing entries in the main Grid
                            if($selectionState === ICCycleCountFormEditor::ALL_EXCEPT_SOME){
                                $requestParams['UNIQUEKEYS'] = array_merge($requestParams['UNIQUEKEYS'], $uniqueKeys);
                            } else {
                                //For ALL just add uniqueKeys which is already existing entries in the main Grid
                                $requestParams['UNIQUEKEYS'] = $uniqueKeys;
                            }
                        }
                        $uniqueKeyFilter = PrepINClauseStmt('', $requestParams['UNIQUEKEYS'],
                            " AND ($uniquePropOnRow) NOT",true,'insertcyclecount',true);
                    } else if($selectionState === ICCycleCountFormEditor::NONE_EXCEPT_SOME){
                        $uniqueKeyFilter = PrepINClauseStmt('', $requestParams['UNIQUEKEYS'],
                            " AND ($uniquePropOnRow)",true,'insertcyclecount',true);
                    }
                } else {
                    //This request will be from Add items button, we are running this to fecth the Qty OnHand if it is present.
                    $uniqueKeyFilter = PrepINClauseStmt('', $requestParams['UNIQUEKEYS'],
                        " AND ($uniquePropOnRow)",true,'insertcyclecount',true);
                }
            }
        }

        $exclude_Zero_QOH = $requestParams['EXCLUDE_ZERO_QOH'] ?? false;

        $whereInOut = '';
        if($exclude_Zero_QOH) {
            #Filter to get - QOH >0 or if QOH =0 ,only the active and non-tracked items  .
            $whereInOut = " 
             AND ( doccost.qtyleft >0 Or (item.status='T' and doccost.binkey is null and doccost.lotno is null and doccost.serialno is null and doccost.expirationdate is null)) ";
        }

        // 11/12/2022 - Sid Maganti updated code to get it from function to reuse is this query in next few steps
        $query = $this->buildCycleCountQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect, $expDateSelect, $lotNoSelect,
            $selectQtyOnHandField, $aislerowbinFrom, $aislerowbinWhere, $whereInOut, $gridFieldsFilter,
            $uniqueKeyFilter, $aislerowbinGroupBy, $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy);
        $args = array($cny,$warehouseKey, $cny,$warehouseKey);

        //Just for Note.
        if($fromGetCount){
            // From getCycleCountData function.
            $resultData = $gQueryMgr->DoCustomQuery($query, $args, true, $params['start'], $params['max']);
        } else {
            // From StartCycleCountProcess function.
            $resultData = $gQueryMgr->DoCustomQuery($query, $args, true);
        }
        // adding error in case of database connectivity or SQL error
        if ($resultData === false) {
            $gErr = Globals::$g->gErr;
            $gErr->addIAError('INV-0129', __FILE__ . ':' . __LINE__,
                'Unable to find item transactions',
                [],
                'Database error',
                []
            );
            return false;
        }

        // Query the -ve qty sales transaction to fix QOH values
        if (Util::countOrZero($resultData) > 0) {

            //If the QOH is negative, fix it to be '0'
            foreach ($resultData as $index => $rowData) {
                if ($rowData['QUANTITYONHAND'] < 0) {
                    $resultData[$index]['QUANTITYONHAND'] = '0';
                }
            }

            if ($fromGetCount) {
                // From getCycleCountData function.
                $uniqueKeys = [];
                foreach ($resultData as $uniqueRow) {
                    $uniqueKeys[] = $uniqueRow['UNIQUEPROPONROW'];
                }
                if(count($uniqueKeys) > 0){
                    $uniqueKeyFilter = PrepINClauseStmt('', $uniqueKeys,
                                                        " AND ($uniquePropOnRow) ",true,'cyclecount',true);
                }
            }

            // updating the $selectQtyOnHandField to get total quatity on hand value
            $selectQtyOnHandField = 'SUM(doccost.quantity) quantityonhand,';
            // updating Where condition to query only out going transactions and sales related and docentrycostkey is null
            // this where condition ony get orphaned OE invoices that dont have docentrycostkey populated.
            $whereInOut = 'AND doccost.in_out = \'O\'
                           AND docpar.sale_pur_trans = \'S\'
                           AND doccost.Docentrycostkey IS NULL';

            // 11/12/2022 - Sid Maganti updated code to get it from function to reuse is this query in next few steps
            $queryForOrphanedOeInvoices = $this->buildQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect, $expDateSelect, $lotNoSelect,
                $selectQtyOnHandField, $aislerowbinFrom, $aislerowbinWhere, $whereInOut, $gridFieldsFilter,
                $uniqueKeyFilter, $aislerowbinGroupBy, $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy);

            // From StartCycleCountProcess function.
            $OrphanedOeInvoicesData = $gQueryMgr->DoCustomQuery($queryForOrphanedOeInvoices, $args, true);

            // adding error in case of database connectivity or SQL error
            if ($OrphanedOeInvoicesData === false) {
                $gErr = Globals::$g->gErr;
                $gErr->addIAError(
                    'INV-0130', __FILE__ . ':' . __LINE__,
                    'Unable to find transactions with a negative quantity',
                    [],
                    'Database error',
                    []
                );
                return false;
            }

            // If we have Orphaned OE Invoices
            if (Util::countOrZero($OrphanedOeInvoicesData) > 0) {
                $this->checkForNegativeQuantitySalesInvoice($resultData, $OrphanedOeInvoicesData);
            }

        }
        // To figure out EXCLUDEALLOCATEDQTY is cheked
        $excludeAllocatedQty = (isset($requestParams['EXCLUDEALLOCATEDQTY'])
                                 && $requestParams['EXCLUDEALLOCATEDQTY'] == 'true') ?? false;
        if($excludeAllocatedQty){
            $this->excludeAllocatedQuantity($resultData, $warehouseKey);
        }

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetTransactionViewContext();
        }

        if($exclude_Zero_QOH) {
            $totalCount= $resultData[0]['QCNT'];
            //remove the net 0 entries
            foreach ($resultData as $key=>$uniqueRow) {
                if ($uniqueRow['QUANTITYONHAND'] > 0
                    || ($uniqueRow['ITEMACTIVE'] =='T' && is_null($uniqueRow["BINKEY"]) &&  is_null($uniqueRow["LOTNO"]) && is_null($uniqueRow["SERIALNO"]) && is_null($uniqueRow["EXPIRATIONDATE"]))){
                    continue;
                }
                unset($resultData[$key]);
                $totalCount--;
            }
            if ($totalCount != $resultData[0]['QCNT']){
                //compact the empty elements
                $resultData=array_values($resultData);
                if ($pageSize == -1){
                    $resultData[0]['QCNT']=$totalCount;
                }else if(empty($resultData)){ //Add atleast one dummy row to the current page
                    $resultData[0]['QCNT']=$totalCount+1;
                }
            }
        }
        return $resultData;
    }

    /**
     * Returns the reconciliation request.
     * @param string $cycleCountkey
     *
     * @return array
     */
    protected function getUniqueKeyFilterParams($cycleCountkey)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $uniqueKeys = [];

        $ccEntryManager = $gManagerFactory->getManager('iccyclecountentry');
        $ccyclecountparams = array(
            'selects' => array('UNIQUEPROPONROW'),
            'filters' => array (
                array (
                    array( 'CYCLECOUNTKEY', '=', $cycleCountkey)
                ),
            )
        );

        $uniquePropOnRowRecords = $ccEntryManager->GetList($ccyclecountparams);
        if( is_array($uniquePropOnRowRecords) && count($uniquePropOnRowRecords) > 0){
            foreach ($uniquePropOnRowRecords as $record){
                $uniqueKeys[] = $record['UNIQUEPROPONROW'];
            }
        }

        return $uniqueKeys;
    }

    /**
     * processFieldsFilter Returns the Order By.
     *
     * @param array $fieldFilter
     *
     * @return string
     */
    private function processFieldsFilter($fieldFilter)
    {
        $filter = '';

        $cycleCountFilterMapr = $this->getFieldMappings(false);

        foreach ($fieldFilter as $field){
            if(in_array($field[0], $cycleCountFilterMapr)){
                //Getting mapped table name for filtering
                $filterKey = array_keys($cycleCountFilterMapr, $field[0]);
                //Prepare fields filter here
                $filter .= "AND $filterKey[0] $field[1] '". $field[2] . "' ";
            }
        }

        return $filter;
    }

    /**
     * getFieldMappings Returns field mapped array.
     * @param bool $fromProcessOrder
     *
     * @return array
     */
    private function getFieldMappings($fromProcessOrder = true)
    {
        if($fromProcessOrder){
            $cycleCountFieldMap = array(
                'item.itemid'         => 'ITEMID',
                'item.name'           => 'ITEMNAME',
                'whsebin.binid'       => 'BINID',
                'whseaisle.aisleid'   => 'AISLEID',
                'whserow.rowkey'      => 'ICROWID',
                'whsezone.zoneid'     => 'ZONEID',
                'doccost.serialno'    => 'SERIALNO',
                'doccost.lotno'       => 'LOTNO',
                'icuom.unit'          => 'ITEMUNIT',
                'icitemwhse.cycle'    => 'ITEMCYCLE',
                'item.productlinekey' => 'PRODUCTLINE'
            );
        } else {
            $cycleCountFieldMap = array(
                'UPPER(item.itemid)'         => 'ITEMID',
                'UPPER(item.name)'           => 'ITEMNAME',
                'UPPER(whsebin.binid)'       => 'BINID',
                'UPPER(whseaisle.aisleid)'   => 'AISLEID',
                'UPPER(whserow.rowkey)'      => 'ICROWID',
                'UPPER(whsezone.zoneid)'     => 'ZONEID',
                'UPPER(doccost.serialno)'    => 'SERIALNO',
                'UPPER(doccost.lotno)'       => 'LOTNO',
                'UPPER(icuom.unit)'          => 'ITEMUNIT',
                'UPPER(icitemwhse.cycle)'    => 'ITEMCYCLE',
                'UPPER(item.productlinekey)' => 'PRODUCTLINE'
            );
        }

        return $cycleCountFieldMap;
    }

    /**
     * processOrderBy Returns the Order By.
     *
     * @param array $orders
     *
     * @return string
     */
    private function processOrderBy($orders)
    {
        $orderBy = '';

        $cycleCountOrderByMap = $this->getFieldMappings(true);

        if(in_array($orders[0], $cycleCountOrderByMap)){
            //Getting mapped table name
            $orderByKey = array_keys($cycleCountOrderByMap, $orders[0]);
            //Prepare order by here
            $orderBy = "order by " . $orderByKey[0] . " ". $orders[1];
        }

        return $orderBy;
    }

    /**
     * Returns the filters.
     *
     * @param array $requestParams
     * @param bool $fromGetCount
     *
     * @return array
     */
    public function getFilters($requestParams, $fromGetCount = true)
    {
        $filters = [];

        //Specific to the Grid CYCLECOUNTENTRY, so if the call is from getCycleCountData,
        // we should SKIP the below fields from filtering
        if(!$fromGetCount){
            //Default CYCLECOUNTKEY filter to get the entry of perticular CycleCount
            //if it is from loadCycleCountData
            $cycleCountRecordNo = $requestParams['CYCLECOUNTKEY'];
            $filters[]= [ 'CYCLECOUNTKEY', '=', $cycleCountRecordNo ];

            //All the Amount fields iteration done here
            $gridFilterAmtFields = ['QUANTITYCOUNTED', 'QUANTITYDAMAGED', 'QUANTITYONHAND','TOTALQTYCOUNTED',
                'SUGGESTEDADJ', 'SUGGESTEDDMGADJ', 'ACTUALADJ', 'ACTUALDMGADJ', 'UNITCOST',
                'ADJVALUE', 'QUANTITYONHANDEND', 'QOHLASTUPDATED'];
            foreach ($gridFilterAmtFields as $filterField) {
                if (isset($requestParams[$filterField]) && $requestParams[$filterField] != '') {
                    $filters[] = [ $filterField, '=', $requestParams[$filterField] ];
                }
            }

            //Line Count Status we just need to validate the values CYCLECOUNTENTRY
            $validState = ['Not Counted', 'Skipped', 'Counted', 'In Progress'];
            if (isset($requestParams['LINECOUNTSTATE']) && $requestParams['LINECOUNTSTATE'] != ''
                && in_array($requestParams['LINECOUNTSTATE'], $validState) ){
                $filters[] = [ 'LINECOUNTSTATE', '=', $requestParams['LINECOUNTSTATE'] ];
            }
        }

        //Fields filter logic common for both CYCLECOUNTENTRY and CYCLECOUNTRECORD Grid
        //All the Text fields iteration done.
        $gridFilterTxtFields = ['ITEMID', 'ITEMNAME', 'BINID', 'ICROWID', 'AISLEID', 'ZONEID', 'SERIALNO', 'LOTNO', 'ITEMUNIT',
            'ADJUSTMENTREASON', 'COUNTEDBYID', 'ITEMCYCLE', 'PRODUCTLINE', 'REVIEWCOMMENT'];
        foreach ($gridFilterTxtFields as $filterField) {
            if (isset($requestParams[$filterField]) && $requestParams[$filterField] != '') {
                $filters[] = [ $filterField, 'LIKE', '%' . strtoupper($requestParams[$filterField]) . '%' ];
            }
        }

        return $filters;
    }


    /**
     * @param string      $recordNo
     *
     * @return bool
     */
    public function canDelete($recordNo)
    {
        $ok = true;
        $gErr         = Globals::$g->gErr;

        $filter = array(
            'selects' => array('CYCLECOUNTID', 'COUNTSTATE'),
            'filters' => array(
                array(
                    array('RECORDNO', '=', $recordNo)
                )
            )
        );
        $res = $this->GetList($filter);

        $states = [ ICCycleCountFormEditor::STATE_COUNTED_VALUE, ICCycleCountFormEditor::STATE_VOIDED_VALUE,
            ICCycleCountFormEditor::STATE_RECONCILED_VALUE ];
        if( isset($res[0]['COUNTSTATE']) && in_array($res[0]['COUNTSTATE'], $states) ) {
            $msg = 'Cyclecount ' . $res[0]['CYCLECOUNTID'] . ' is completed. Cannot delete completed cyclecount.';
            $gErr->addIAError(
                'INV-0540', __FILE__ . ':' . __LINE__,
                'Error deleting Cyclecount ' . $res[0]['CYCLECOUNTID'],
                ['RES_0_CYCLECOUNTID'=>$res[0]['CYCLECOUNTID']],
                $msg,
                ['RES_0_CYCLECOUNTID'=>$res[0]['CYCLECOUNTID']],
                'Invalid Operation',[]
            );
            $ok = false;
        }

        return $ok;
    }

    /**
     * If the customer fills in optional ID fields, look up the KEY values (record#) for them.
     *
     * @param array $values
     *
     * @return bool
     */
    function prepareValuesOnComplete(&$values)
    {
        $ok = true;
        $linesAdjusted = 0;
        $linesDmgAdjustment = 0;
        $linesInCount = 0;
        $lineSkipped  = 0;

        if(is_array($values['CYCLECOUNTENTRY']) && count($values['CYCLECOUNTENTRY']) > 0) {
            $linesInCount = count($values['CYCLECOUNTENTRY']);
            $uniquePropOnRowData  = [];
            $cycleCountData  = [];

            if( isset($values['WAREHOUSEID']) && $values['WAREHOUSEID'] != ''){
                $cycleCountData       = $this->executeCycleCountQuery($values['WAREHOUSEID']);

                if( is_array($cycleCountData) && count($cycleCountData) > 0){
                    foreach ($cycleCountData as $key => $ccData){
                        $uniquePropOnRowData[$key] =  $ccData['UNIQUEPROPONROW'];
                    }
                } else if (!is_array($cycleCountData) && $cycleCountData === false) {
                    // return false in case of query error
                    return false;
                }
            }

            foreach ($values['CYCLECOUNTENTRY'] as &$entries) {

                if((isset($entries['QUANTITYCOUNTED']) && $entries['QUANTITYCOUNTED'] != '') ||
                    (isset($entries['QUANTITYDAMAGED']) || $entries['QUANTITYDAMAGED'] != '')){
                    if(isset($entries['QUANTITYCOUNTED']) && isset($entries['QUANTITYDAMAGED'])){
                        $entries['TOTALQTYCOUNTED'] = ibcadd ( $entries['QUANTITYCOUNTED'], $entries['QUANTITYDAMAGED'], self::QUANTITY_PRECISION, true);
                        $entries['SUGGESTEDADJ']    = ibcsub ( $entries['QUANTITYCOUNTED'], $entries['QUANTITYONHAND'], self::QUANTITY_PRECISION, true);
                        $entries['ACTUALADJ']       = $entries['SUGGESTEDADJ'];
                        $entries['SUGGESTEDDMGADJ'] = $entries['QUANTITYDAMAGED'];
                        $entries['ACTUALDMGADJ']    = $entries['SUGGESTEDDMGADJ'];
                    } else if(isset($entries['QUANTITYCOUNTED'])){
                        $entries['TOTALQTYCOUNTED'] = $entries['QUANTITYCOUNTED'];
                        $entries['SUGGESTEDADJ']    = ibcsub ($entries['TOTALQTYCOUNTED'], $entries['QUANTITYONHAND'], self::QUANTITY_PRECISION, true);
                        $entries['ACTUALADJ']       = $entries['SUGGESTEDADJ'];
                        $entries['SUGGESTEDDMGADJ'] = 0;
                        $entries['ACTUALDMGADJ']    = 0;
                    } else {
                        $entries['TOTALQTYCOUNTED'] = $entries['QUANTITYDAMAGED'];
                        $entries['SUGGESTEDADJ']    = ibcsub (0, $entries['QUANTITYONHAND'], self::QUANTITY_PRECISION, true);
                        $entries['ACTUALADJ']       = $entries['SUGGESTEDADJ'];
                        $entries['SUGGESTEDDMGADJ'] = $entries['QUANTITYDAMAGED'];
                        $entries['ACTUALDMGADJ']    = $entries['SUGGESTEDDMGADJ'];
                    }

                    //calculate the adjustment count in the cycle count reconcile process
                    if(isset($entries['SUGGESTEDADJ']) && $entries['SUGGESTEDADJ'] != 0){
                        $linesAdjusted += 1;
                    }

                    //calculate the damage adjustment count in the cycle count reconcile process
                    if(isset($entries['SUGGESTEDDMGADJ']) && $entries['SUGGESTEDDMGADJ'] != 0){
                        $linesDmgAdjustment += 1;
                    }
                }

                if( isset($entries['LINECOUNTSTATE']) && $entries['LINECOUNTSTATE'] == ICCycleCountFormEditor::LINE_STATE_SKIPPED ){
                    $lineSkipped += 1;
                }

                if(in_array($entries['UNIQUEPROPONROW'], $uniquePropOnRowData )){
                    $index = array_search($entries['UNIQUEPROPONROW'], $uniquePropOnRowData);
                    $entries['QUANTITYONHANDEND'] = $cycleCountData[$index]['QUANTITYONHAND'];
                }

            }
        }

        $this->populateUnitCostForItems($values['CYCLECOUNTENTRY'], $values['WAREHOUSEID']);

        //Prepairing Reconcile header values once they complete the count.
        $values['ADJUSTMENTCOUNT']    = $linesAdjusted;
        $values['DMGADJUSTMENTCOUNT'] = $linesDmgAdjustment;
        $values['LINESINCOUNT']       = $linesInCount;
        $values['LINESKIPPED']        = $lineSkipped;

        return $ok;
    }

    /**
     * If the customer fills in optional ID fields, look up the KEY values (record#) for them.
     *
     * @param array $entries
     * @param string $wareHouseId
     */
    function populateUnitCostForItems(&$entries, $wareHouseId)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');

        //Effective date should be as of complete cyclecount date to populate cost on complete
        $effectiveDate = (string) GetCurrentDate();

        foreach ($entries as &$entry) {
            $entry['UNITCOST'] = 0;
            if ($entry['COST_METHOD'] == 'S') {
                $entry['UNITCOST'] = $itemMgr->GetStandardCost( $entry['ITEMID'], $wareHouseId, $effectiveDate );
            } else if ($entry['COST_METHOD'] == 'A') {
                $entry['UNITCOST'] = $itemMgr->GetAverageCost( $entry['ITEMID'], $wareHouseId, $effectiveDate );
            }
            //By default 'Adj Value' and 'Damage Adj Value' will be set to 'Unit cost * Adj Value'.
            //Later they may be changed in UI by User while reconciling.
            $entry['ADJVALUE'] = ibcmul($entry['UNITCOST'], $entry['ACTUALADJ'], 4, true);
        }
    }

    /**
     * rePopulateUnitCostOnReconcile
     *
     * @param array $cycleCountData
     */
    function rePopulateUnitCostOnReconcile(&$cycleCountData)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $wareHouseId = $cycleCountData['WAREHOUSEID'];
        $effectiveDate = $cycleCountData['ADJUSTMENTPOSTDATE'];
        $itemMgr = $gManagerFactory->getManager('item');
        $hasDecreaseAdjustment = false;
        $resultDecreaseEntries = [];

        foreach ($cycleCountData['CYCLECOUNTENTRY'] as $entry) {
            if ($entry['ACTUALADJ'] < 0) {
                $hasDecreaseAdjustment = true;
                break;
            }
        }

        if($hasDecreaseAdjustment){
            $mgr = $gManagerFactory->getManager(
                'invdocument', true, ['DOCTYPE' => self::ADJDECREASEDOCTYPE] );
            $docId = self::ADJDECREASEDOCTYPE."—ADJ-".$cycleCountData['CYCLECOUNTID'];
            $docParams = array(
                'selects' => array('RECORDNO'),
                'filters' => array (
                    array (
                        array( 'DOCID', '=', $docId)
                    ),
                )
            );

            $documentRecordNo = $mgr->GetList($docParams);

            if(isset($documentRecordNo[0]['RECORDNO'])){
                $entryMgr = $gManagerFactory->getManager(
                    'invdocumententry', true, ['DOCTYPE' => self::ADJDECREASEDOCTYPE] );

                $docEntryParams = array(
                    'selects' => array('ITEMID', 'UIPRICE'),
                    'filters' => array (
                        array (
                            array( 'DOCHDRNO', '=', $documentRecordNo[0]['RECORDNO'])
                        ),
                    )
                );
                $docEntryRecords = $entryMgr->GetList($docEntryParams);

                //Populate deleteRecordNo list to skip
                foreach ($docEntryRecords as $docEntryRecord){
                    if(!isset($resultDecreaseEntries[$docEntryRecord['ITEMID']])){
                        $resultDecreaseEntries[$docEntryRecord['ITEMID']] = $docEntryRecord['UIPRICE'];
                    }
                }
            }
        }

        foreach ($cycleCountData['CYCLECOUNTENTRY'] as &$entry) {
            if ($entry['COST_METHOD'] == 'S') {
                $entry['UNITCOST'] = $itemMgr->GetStandardCost( $entry['ITEMID'], $wareHouseId, $effectiveDate );
                $entry['ADJVALUE'] = ibcmul($entry['UNITCOST'], $entry['ACTUALADJ'], 4, true);
            } else if ($entry['ACTUALADJ'] < 0 && array_key_exists($entry['ITEMID'], $resultDecreaseEntries)) {
                $entry['UNITCOST'] = $resultDecreaseEntries[$entry['ITEMID']];
                $entry['ADJVALUE'] = ibcmul($entry['UNITCOST'], $entry['ACTUALADJ'], 4, true);
            }
        }
    }

    /**
     * prepareDocumentLinksForCC
     *
     * @param array $cycleCountData
     * @param array $mappingEntries
     */
    function prepareDocumentLinksForCC(&$cycleCountData, $mappingEntries)
    {
        if (!is_array($mappingEntries) || count($mappingEntries) == 0) {
            return;
        }

        //Each cyclecount entry can have either Adjustment increase or decrease + Damaged (Not mandatory).

        // For each cycle count entry we should be mapping only to one of the following document type,
        // Adjustment increase
        // Adjustment decrease
        // Adjustment damaged
        foreach ($cycleCountData['CYCLECOUNTENTRY'] as &$ccEntry) {
            $entryMap = $mappingEntries[$ccEntry['RECORDNO']];

            if (!empty($entryMap[self::ADJINCREASEDOCTYPE]) && count($entryMap[self::ADJINCREASEDOCTYPE]) > 0) {
                $adjDocEntry = $entryMap[self::ADJINCREASEDOCTYPE];
            } else if (!empty($entryMap[self::ADJDECREASEDOCTYPE]) && count($entryMap[self::ADJDECREASEDOCTYPE]) > 0) {
                $adjDocEntry = $entryMap[self::ADJDECREASEDOCTYPE];
            } else {
                $adjDocEntry = $entryMap[self::ADJDAMAGEDDOCTYPE];
            }

            $ccEntry['DOCHDRKEY'] = $adjDocEntry['DOCHDRKEY'];
            $ccEntry['DOCENTRYKEY'] = $adjDocEntry['DOCENTRYKEY'];
        }
    }

    /**
     * prepareDimensionDataForTransactionEntry .
     *
     * @param array $thisentry
     * @param array $entry
     *
     * @return array
     */
    private function prepareDimensionDataForTransactionEntry($thisentry, $entry)
    {
        // Copy the dimensions
        $dimensions = IADimensions::getAllDimensionObjectProperties(!util_isPlatformDisabled());
        foreach ($dimensions as $dim) {
            if ($dim['path'] == 'ITEMID') {
                continue;
            }

            if(isset($entry[$dim['path']]) && $entry[$dim['path']] != ''){
                $thisentry[$dim['path']] = $entry[$dim['path']];
            }

            $thisentry['DEPARTMENT'] = $thisentry['DEPARTMENTID'];

            //We are separately merging the CustomDimensions
            $this->mergeCustomDimensions($thisentry, $dim, $entry);
        }

        return $thisentry;
    }

    /**
     * @param array $thisentry
     * @param array $dim
     * @param array $entry
     *
     */
    private function mergeCustomDimensions(&$thisentry, $dim, &$entry)
    {
        if (empty($dim['standard']) && isset($dim['dimensionid'])) {
            $custDimFieldsMap = [];
            if (!util_isPlatformDisabled()) {
                $custDimFieldsMap = GLEntryManager::getPTFieldsMap();
            }
            if (!empty($entry) && empty($dim['standard']) && isset($dim['dimensionid']) && !empty($dim['dimensionid'])) {
                // From UI - custom dimensions value passing through header level
                $dimensionLineEntryValue = $entry[$custDimFieldsMap[$dim['dimensionid']]] ?? '';
                $thisentry[$custDimFieldsMap[$dim['dimensionid']]] = $dimensionLineEntryValue;
            }
        }
    }

    /**
     * Figure out if the transaction is deletable
     *
     * @param int        $ID     the transaction key
     * @param bool       $doget  deprecated
     * @param array|null $values the transaction data
     *
     * @return bool false if error else true
     */
    public function isDeletable($ID, $doget = true, $values = null)
    {
        if (empty($values) || $values == false) {
            $msg = sprintf(" You attempted to delete a '%1s' cycle count which doesn't exist. Please choose different cycle count.", $ID);
            Globals::$g->gErr->addIAError(
                'INV-0541', __FILE__ . '.' . __LINE__,
                "Unable to delete cycle count.",[],
                $msg,['ID'=>$ID]
            );
            return false;
        }

        // Call the parent for common validations
        return parent::IsDeletable($ID, $doget, $values);
    }

    /**
     * getAllocatedQuantity Returns the $allocatedData.
     *
     * @param string $warehouseKey
     *
     * @return array
     */
    protected function getAllocatedQuantity($warehouseKey)
    {

        $kINVid = Globals::$g->kINVid;
        $gQueryMgr = Globals::$g->gQueryMgr;
        GetModulePreferences($kINVid, $invPrefs);

        $cny = GetMyCompany();
        $query = array(
            'QUERY' =>"SELECT
                            ( allocateditem.record#
                              || '#'
                              || ''
                              || '#'
                              || ''
                              || '#'
                              || '' ) uniqueproponrow,
                            nvl(allocated.posquantity, 0) + nvl(allocated.negquantity, 0) AS allocatedqty
                        FROM
                            icitemtotals   allocated,
                            ictotal        allocatedictotal,
                            icitem         allocateditem
                        WHERE
                            allocatedictotal.cny# = :1
                            AND allocated.cny# = allocatedictotal.cny#
                            AND allocated.totalkey = allocatedictotal.record#
                            AND allocateditem.cny# = allocatedictotal.cny#
                            AND allocateditem.itemid = allocated.itemkey
                            AND nvl(allocateditem.enablesno, 'F') = 'F'
                            AND nvl(allocateditem.enablelot, 'F') = 'F'
                            AND nvl(allocateditem.enableexpiration, 'F') = 'F'
                            AND nvl(allocateditem.enablebin, 'F') = 'F'
                            AND allocatedictotal.name = 'ALLOCATED'
                            AND allocated.warehousekey = :2
                        UNION ALL
                        SELECT
                          ( icitem.record#
                            || '#'
                            || vi.binkey
                            || '#'
                            || vi.serialno
                            || '#'
                            || vi.lotno
                            || vi.expirationdate ) uniqueproponrow,
                          decode(vi.serialno, null, nvl(abs(vi.allocatedquantity), 0), 1) AS allocatedqty
                      FROM
                          v_invtrackingallocated vi,
                          icitem
                      WHERE
                          vi.cny# = :1
                          AND icitem.cny# = vi.cny#
                          AND icitem.itemid = vi.itemid
                          AND vi.warehouseid = :2",
            'ARGTYPES' => array('integer', 'text'));
        $args = array($cny,$warehouseKey);

        if(IsMultiEntityCompany() && !GetContextLocation()){
            SetReportViewContext();
        }
        $allocatedData = $gQueryMgr->DoCustomQuery($query, $args, true);
        return $allocatedData;
    }

    /**
     * excludeAllocatedQuantity
     * @param array $resultData
     * @param string $warehouseKey
     *
     */
    protected function excludeAllocatedQuantity(&$resultData, $warehouseKey)
    {
        $allocatedData = $this->getAllocatedQuantity($warehouseKey);
        $uniquePropOnRowData = [];
        if( is_array($allocatedData) && count($allocatedData) > 0){
            foreach ($allocatedData as $key => $allocData){
                $uniquePropOnRowData[$key] =  $allocData['UNIQUEPROPONROW'];
            }
            foreach ($resultData as &$resData){
                if(in_array($resData['UNIQUEPROPONROW'], $uniquePropOnRowData )){
                    $index = array_search($resData['UNIQUEPROPONROW'], $uniquePropOnRowData);
                    $resData['QUANTITYONHAND'] = (string) ibcsub($resData['QUANTITYONHAND'] , $allocatedData[$index]['ALLOCATEDQTY'],ItemManager::BASEUNITPRECISION,true);
                    if(is_null($resData['QUANTITYONHAND']) || empty($resData['QUANTITYONHAND'])){
                        $resData['QUANTITYONHAND'] = '0';
                    }
                }
            }
        }
    }

    /**
     *  Balance the $resultData quantity by looping through all the records.
     *
     *  This should fix the issue of credit notes (sales return) transactions having quantity left populated
     *  even in case of source incoming transactions are reversed or deleted.
     *
     * @param array     &$resultData Result Data from physical inventory
     * @param array $OrphanedOeInvoicesData Orphaned OE Invoices Data
     *
     */

    private function checkForNegativeQuantitySalesInvoice(&$resultData, $OrphanedOeInvoicesData)
    {
        $uniquePropOnRowData = [];
        foreach ($OrphanedOeInvoicesData as $OrphanedOeInvoice) {
            $uniquePropOnRowData[$OrphanedOeInvoice['UNIQUEPROPONROW']] = $OrphanedOeInvoice['QUANTITYONHAND'];
        }
        if (Util::countOrZero($uniquePropOnRowData) > 0) {
            foreach ($resultData as &$resData) {
                $uniquePropOnRow = $resData['UNIQUEPROPONROW'];
                if ($resData['QUANTITYONHAND'] > 0 &&
                    key_exists($uniquePropOnRow, $uniquePropOnRowData) &&
                    $uniquePropOnRowData[$uniquePropOnRow] > 0) {
                    if (ibccomp($resData['QUANTITYONHAND'] , $uniquePropOnRowData[$uniquePropOnRow]) >=0) {
                        $resData['QUANTITYONHAND'] = (string) ibcsub($resData['QUANTITYONHAND'] , $uniquePropOnRowData[$uniquePropOnRow],ItemManager::BASEUNITPRECISION,true);
                        $uniquePropOnRowData[$uniquePropOnRow] = 0;
                    } else {
                        $uniquePropOnRowData[$uniquePropOnRow] = $uniquePropOnRowData[$uniquePropOnRow] - $resData['QUANTITYONHAND'];
                        $resData['QUANTITYONHAND'] =  "0";
                    }
                }
            }
        }
    }


    /**
     * Function will return the query for used to get qty on hand value for physical inventory value
     * @param string $uniquePropOnRow uniquePropOnRow key
     * @param string $aislerowbinSelect $aislerowbinSelect query string
     * @param string $serialNoSelect $serialNoSelect query string
     * @param string $expDateSelect $expDateSelect query string
     * @param string $lotNoSelect $lotNoSelect query string
     * @param string $selectQtyOnHandField $selectQtyOnHandField QOH select field query string
     * @param string $aislerowbinFrom $aislerowbinFrom query string
     * @param string $aislerowbinWhere $gridFieldsFilter to query string
     * @param string $whereInOut $whereInOut to query string
     * @param string $uniqueKeyFilter $gridFieldsFilter to query string
     * @param string $aislerowbinGroupBy $aislerowbinGroupBy to query string
     * @param string $serialNoGroupBy $serialNoGroupBy to query string
     * @param string $expDateGroupBy $expDateGroupBy to query string
     * @param string $lotNoGroupBy $lotNoGroupBy to query string
     * @param string $orderBy $orderBy to query string
     * @return array    query values
     */

    protected function buildQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect,
                                  $expDateSelect, $lotNoSelect, $selectQtyOnHandField,
                                  $aislerowbinFrom, $aislerowbinWhere, $whereInOut,
                                  $gridFieldsFilter, $uniqueKeyFilter, $aislerowbinGroupBy,
                                  $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy)
    {

        $query = array(
            'QUERY' => "SELECT
                        ($uniquePropOnRow)   UNIQUEPROPONROW,
                        item.itemid          ITEMID,
                        item.name            ITEMNAME,
                        item.record#         ITEMKEY,
                        item.status          ITEMACTIVE,
                        $aislerowbinSelect
                        icuom.unit           ITEMUNIT,
                        $serialNoSelect
                        $expDateSelect
                        $lotNoSelect
                        item.productlinekey  PRODUCTLINE,
                        icitemwhse.cycle     ITEMCYCLE,
                        $selectQtyOnHandField
                        count (1) over()     qcnt
                        FROM
                        icitem         item,
                        icprodline     ip,
                        docentrycost   doccost,
                        docentry,
                        dochdrmst      dochdr,
                        docpar,
                        $aislerowbinFrom
                        icuomgrp,
                        icuom,
                        icitemwhse
                        WHERE
                        item.cny# = doccost.cny#
                        AND item.itemid = doccost.itemkey
                        AND item.cny# = icuomgrp.cny#
                        AND item.uomgrpkey = icuomgrp.record#
                        AND icuomgrp.cny# = icuom.cny#
                        AND icuom.isbase = 'T'
                        AND icuom.grpkey = icuomgrp.record#
                        AND item.cny# = ip.cny# (+)
                        AND item.productlinekey = ip.productlineid (+)
                        AND item.itemtype IN ( 'I', 'SK' )
                        AND doccost.affects_inventory IN ( 'V', 'QV' )
                        AND doccost.adjdocentrycostkey IS NULL
                        AND doccost.cny# = docentry.cny#
                        AND doccost.docentrykey = docentry.record#
                        AND docentry.cny# = dochdr.cny#
                        AND docentry.dochdrkey = dochdr.record#
                        AND dochdr.cny# = docpar.cny#
                        AND dochdr.docparkey = docpar.record#
                        AND dochdr.state NOT IN ( 'I', 'S', 'A', 'X', 'R' )
                        $aislerowbinWhere
                        $whereInOut
                        AND item.cny# = icitemwhse.cny# (+)
                        AND item.itemid = icitemwhse.itemkey (+)
                        AND docentry.warehousekey = icitemwhse.warehousekey (+)
                        AND doccost.cny# = ?
                        AND docentry.warehousekey  = ?
                        $gridFieldsFilter
                        $uniqueKeyFilter
                        GROUP BY item.itemid,
                        item.name,
                        item.record#,
                        item.status,
                        $aislerowbinGroupBy
                        icuom.unit,
                        $serialNoGroupBy
                        $expDateGroupBy
                        $lotNoGroupBy
                        item.productlinekey,
                        icitemwhse.cycle
                        $orderBy",
            'ARGTYPES' => array('integer', 'text'));

        return $query;

    }

    /**
     * Function will return the query for use to get qty on hand for cycle count which represent physical inventory on the shelf.
     * This query will query from both docentrycost and docentrycostkits table.
     * @param string $uniquePropOnRow uniquePropOnRow key
     * @param string $aislerowbinSelect $aislerowbinSelect query string
     * @param string $serialNoSelect $serialNoSelect query string
     * @param string $expDateSelect $expDateSelect query string
     * @param string $lotNoSelect $lotNoSelect query string
     * @param string $selectQtyOnHandField $selectQtyOnHandField QOH select field query string
     * @param string $aislerowbinFrom $aislerowbinFrom query string
     * @param string $aislerowbinWhere $gridFieldsFilter to query string
     * @param string $whereInOut $whereInOut to query string
     * @param string $uniqueKeyFilter $gridFieldsFilter to query string
     * @param string $aislerowbinGroupBy $aislerowbinGroupBy to query string
     * @param string $serialNoGroupBy $serialNoGroupBy to query string
     * @param string $expDateGroupBy $expDateGroupBy to query string
     * @param string $lotNoGroupBy $lotNoGroupBy to query string
     * @param string $orderBy $orderBy to query string
     * @return array    query values
     */
    private function buildCycleCountQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect,
                                          $expDateSelect, $lotNoSelect, $selectQtyOnHandField,
                                          $aislerowbinFrom, $aislerowbinWhere, $whereInOut,
                                          $gridFieldsFilter, $uniqueKeyFilter, $aislerowbinGroupBy,
                                          $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy)
    {
        $docentrycostQuery = $this->buildDocEntryCostQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect,
            $expDateSelect, $lotNoSelect, $selectQtyOnHandField,
            $aislerowbinFrom, $aislerowbinWhere, $whereInOut,
            $gridFieldsFilter, $uniqueKeyFilter, $aislerowbinGroupBy,
            $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy);
        $docentrycostkitsQuery = $this->buildDocEntryCostKitsQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect,
            $expDateSelect, $lotNoSelect, $selectQtyOnHandField,
            $aislerowbinFrom, $aislerowbinWhere, $whereInOut,
            $gridFieldsFilter, $uniqueKeyFilter, $aislerowbinGroupBy,
            $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy);
        $query = array(
            'QUERY' => "SELECT
                                        UNIQUEPROPONROW,
                                        ITEMID,
                                        ITEMNAME,
                                        ITEMKEY,
                                        ITEMACTIVE,
                                        BINID,
                                        BINKEY,
                                        ICROWID,
                                        ROWKEY,
                                        AISLEID,
                                        AISLEKEY,
                                        ZONEID,
                                        ZONEKEY,
                                        ITEMUNIT,
                                        SERIALNO,
                                        EXPIRATIONDATE,
                                        LOTNO,
                                        PRODUCTLINE,
                                        ITEMCYCLE,
                                        SUM(QUANTITYONHAND)     QUANTITYONHAND,
                                        count (1) over()        QCNT
                                    FROM 
                                        (
                                            ($docentrycostQuery)
                                            UNION
                                            ($docentrycostkitsQuery)
                                        )
                                    GROUP BY
                                        UNIQUEPROPONROW,
                                        ITEMID,
                                        ITEMNAME,
                                        ITEMKEY,
                                        ITEMACTIVE,
                                        BINID,
                                        BINKEY,
                                        ICROWID,
                                        ROWKEY,
                                        AISLEID,
                                        AISLEKEY,
                                        ZONEID,
                                        ZONEKEY,
                                        ITEMUNIT,
                                        SERIALNO,
                                        EXPIRATIONDATE,
                                        LOTNO,
                                        PRODUCTLINE,
                                        ITEMCYCLE
                                    order by itemid asc",
            'ARGTYPES' => array('integer', 'text', 'integer', 'text')
        );
        return $query;
    }

    /**
     * Function will return the query for use to get qty on hand for cycle count which represent physical inventory on the shelf.
     * This query will query from docentrycost table.
     * @param string $uniquePropOnRow uniquePropOnRow key
     * @param string $aislerowbinSelect $aislerowbinSelect query string
     * @param string $serialNoSelect $serialNoSelect query string
     * @param string $expDateSelect $expDateSelect query string
     * @param string $lotNoSelect $lotNoSelect query string
     * @param string $selectQtyOnHandField $selectQtyOnHandField QOH select field query string
     * @param string $aislerowbinFrom $aislerowbinFrom query string
     * @param string $aislerowbinWhere $gridFieldsFilter to query string
     * @param string $whereInOut $whereInOut to query string
     * @param string $uniqueKeyFilter $gridFieldsFilter to query string
     * @param string $aislerowbinGroupBy $aislerowbinGroupBy to query string
     * @param string $serialNoGroupBy $serialNoGroupBy to query string
     * @param string $expDateGroupBy $expDateGroupBy to query string
     * @param string $lotNoGroupBy $lotNoGroupBy to query string
     * @param string $orderBy $orderBy to query string
     * @return array    query values
     */
    private function buildDocEntryCostQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect,
                                            $expDateSelect, $lotNoSelect, $selectQtyOnHandField,
                                            $aislerowbinFrom, $aislerowbinWhere, $whereInOut,
                                            $gridFieldsFilter, $uniqueKeyFilter, $aislerowbinGroupBy,
                                            $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy)
    {

        $query = "SELECT
                        ($uniquePropOnRow)   UNIQUEPROPONROW,
                        item.itemid          ITEMID,
                        item.name            ITEMNAME,
                        item.record#         ITEMKEY,
                        item.status          ITEMACTIVE,
                        $aislerowbinSelect
                        icuom.unit           ITEMUNIT,
                        $serialNoSelect
                        $expDateSelect
                        $lotNoSelect
                        item.productlinekey  PRODUCTLINE,
                        icitemwhse.cycle     ITEMCYCLE,
                        $selectQtyOnHandField
                    FROM
                        icitem         item,
                        icprodline     ip,
                        docentrycost   doccost,
                        docentry,
                        dochdrmst      dochdr,
                        docpar,
                        $aislerowbinFrom
                        icuomgrp,
                        icuom,
                        icitemwhse
                    WHERE
                        item.cny# = doccost.cny#
                        AND item.itemid = doccost.itemkey
                        AND item.cny# = icuomgrp.cny#
                        AND item.uomgrpkey = icuomgrp.record#
                        AND icuomgrp.cny# = icuom.cny#
                        AND icuom.isbase = 'T'
                        AND icuom.grpkey = icuomgrp.record#
                        AND item.cny# = ip.cny# (+)
                        AND item.productlinekey = ip.productlineid (+)
                        AND item.itemtype IN ( 'I', 'SK' )
                        AND doccost.affects_inventory IN ( 'V', 'QV' )
                        AND doccost.adjdocentrycostkey IS NULL
                        AND doccost.cny# = docentry.cny#
                        AND doccost.docentrykey = docentry.record#
                        AND docentry.cny# = dochdr.cny#
                        AND docentry.dochdrkey = dochdr.record#
                        AND dochdr.cny# = docpar.cny#
                        AND dochdr.docparkey = docpar.record#
                        AND dochdr.state NOT IN ( 'I', 'S', 'A', 'X', 'R' )
                        $aislerowbinWhere
                        $whereInOut
                        AND item.cny# = icitemwhse.cny# (+)
                        AND item.itemid = icitemwhse.itemkey (+)
                        AND docentry.warehousekey = icitemwhse.warehousekey (+)
                        AND doccost.cny# = ?
                        AND docentry.warehousekey  = ?
                        $gridFieldsFilter
                        $uniqueKeyFilter
                    GROUP BY item.itemid,
                        item.name,
                        item.record#,
                        item.status,
                        $aislerowbinGroupBy
                        icuom.unit,
                        $serialNoGroupBy
                        $expDateGroupBy
                        $lotNoGroupBy
                        item.productlinekey,
                        icitemwhse.cycle";

        return $query;

    }

    /**
     * Function will return the query for use to get qty on hand for cycle count which represent physical inventory on the shelf.
     * This query will query from docentrycostkits table.
     * @param string $uniquePropOnRow uniquePropOnRow key
     * @param string $aislerowbinSelect $aislerowbinSelect query string
     * @param string $serialNoSelect $serialNoSelect query string
     * @param string $expDateSelect $expDateSelect query string
     * @param string $lotNoSelect $lotNoSelect query string
     * @param string $selectQtyOnHandField $selectQtyOnHandField QOH select field query string
     * @param string $aislerowbinFrom $aislerowbinFrom query string
     * @param string $aislerowbinWhere $gridFieldsFilter to query string
     * @param string $whereInOut $whereInOut to query string
     * @param string $uniqueKeyFilter $gridFieldsFilter to query string
     * @param string $aislerowbinGroupBy $aislerowbinGroupBy to query string
     * @param string $serialNoGroupBy $serialNoGroupBy to query string
     * @param string $expDateGroupBy $expDateGroupBy to query string
     * @param string $lotNoGroupBy $lotNoGroupBy to query string
     * @param string $orderBy $orderBy to query string
     * @return array    query values
     */
    private function buildDocEntryCostKitsQuery($uniquePropOnRow, $aislerowbinSelect, $serialNoSelect,
                                                $expDateSelect, $lotNoSelect, $selectQtyOnHandField,
                                                $aislerowbinFrom, $aislerowbinWhere, $whereInOut,
                                                $gridFieldsFilter, $uniqueKeyFilter, $aislerowbinGroupBy,
                                                $serialNoGroupBy, $expDateGroupBy, $lotNoGroupBy, $orderBy)
    {

        $query = "SELECT
                        ($uniquePropOnRow)   UNIQUEPROPONROW,
                        item.itemid          ITEMID,
                        item.name            ITEMNAME,
                        item.record#         ITEMKEY,
                        item.status          ITEMACTIVE,
                        $aislerowbinSelect
                        icuom.unit           ITEMUNIT,
                        $serialNoSelect
                        $expDateSelect
                        $lotNoSelect
                        item.productlinekey  PRODUCTLINE,
                        icitemwhse.cycle     ITEMCYCLE,
                        $selectQtyOnHandField
                    FROM
                        icitem         item,
                        icprodline     ip,
                        docentrycostkits   doccost,
                        docentry,
                        dochdrmst      dochdr,
                        docpar,
                        $aislerowbinFrom
                        icuomgrp,
                        icuom,
                        icitemwhse
                    WHERE
                        item.cny# = doccost.cny#
                        AND item.itemid = doccost.itemkey
                        AND item.cny# = icuomgrp.cny#
                        AND item.uomgrpkey = icuomgrp.record#
                        AND icuomgrp.cny# = icuom.cny#
                        AND icuom.isbase = 'T'
                        AND icuom.grpkey = icuomgrp.record#
                        AND item.cny# = ip.cny# (+)
                        AND item.productlinekey = ip.productlineid (+)
                        AND item.itemtype IN ( 'I', 'SK' )
                        AND doccost.affects_inventory IN ( 'V', 'QV' )
                        AND doccost.docentrycostkitkey IS NULL
                        AND doccost.cny# = docentry.cny#
                        AND doccost.docentrykey = docentry.record#
                        AND docentry.cny# = dochdr.cny#
                        AND docentry.dochdrkey = dochdr.record#
                        AND dochdr.cny# = docpar.cny#
                        AND dochdr.docparkey = docpar.record#
                        AND dochdr.state NOT IN ( 'I', 'S', 'A', 'X', 'R' )
                        $aislerowbinWhere
                        $whereInOut
                        AND item.cny# = icitemwhse.cny# (+)
                        AND item.itemid = icitemwhse.itemkey (+)
                        AND docentry.warehousekey = icitemwhse.warehousekey (+)
                        AND doccost.cny# = ?
                        AND docentry.warehousekey  = ?
                        $gridFieldsFilter
                        $uniqueKeyFilter
                    GROUP BY item.itemid,
                        item.name,
                        item.record#,
                        item.status,
                        $aislerowbinGroupBy
                        icuom.unit,
                        $serialNoGroupBy
                        $expDateGroupBy
                        $lotNoGroupBy
                        item.productlinekey,
                        icitemwhse.cycle";

        return $query;

    }

}

