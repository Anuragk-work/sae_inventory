<?php

/* File header
*	FILE: ICCycleCountEntryManager.cls
*	AUTHOR: shreerajath Hebbar <shreerajath.hebbar@sage.com>
*	DESCRIPTION: ICCycleCountEntryManager is owned class of ICCycleCountManager
*
*	(C) 2020, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/

define("CREATE", "Create");
define("UPDATE", "Update");
define("DELETE", "Delete");

class ICCycleCountEntryManager extends OwnedObjectManager
{

    const LINE_STATE_NOTCOUNTED = 'Not Counted';
    const LINE_STATE_COUNTED    = 'Counted';
    const LINE_STATE_INPROGRES  = 'In Progress';
    const LINE_STATE_SKIPPED    = 'Skipped';

    const IA_OPERATIONS    = 'ia::operation';

    const IA_CORRELATION_KEY    = 'ia::correlationKey';

    /** @var array $_ccDataCache */
    var $_ccDataCache = [];

    /** @var array $_ccLineCache */
    var $_ccLineCache = [];
    
    /** @var array $_itemsCache */
    var $_itemsCache = [];

    /** @var array $_itemsUOMCache */
    var $_itemsUOMCache = [];

    /** @var array $_itemsCycleCache */
    var $_itemsCycleCache = [];

    /** @var bool $fromAPI */
    private $fromAPI = false;

    /**
     * @param array $params the parameters of the class
     */
    public function __construct($params = [])
    {
        parent::__construct($params);
        $this->fromAPI = false;

    }

    /**
     * @return string
     */
    protected function GetEntryEntityName(): string
    {
        return ('iccyclecountentry');
    }

    /**
     * @return bool
     */
    function MergeTableInfo(): bool
    {
        return true;
    }

    /**
     * Dynamically populates the entity with the schema and object
     * information
     */
    function MergeObjectSchema()
    {
        parent::MergeObjectSchema();

        $schema = &$this->_schemas[$this->_entity]['schema'];
        $dimFields = $this->GetDimensionFields();
        if ($dimFields && count($dimFields) > 0) {
            foreach ($dimFields as $field) {
                $schema[strtoupper($field['dimfieldid'])] = 'docentry.' . $schema[strtoupper($field['dimfieldid'])];
            }
        }
    }

    /**
     *MergeSchemaChildren
     */
    function MergeSchemaChildren()
    {
        $origChildren = $this->_schemas[$this->_entity]['children'];
        parent::MergeSchemaChildren();
        $children =& $this->_schemas[$this->_entity]['children'];

        $childrenDiff = array_diff_assoc($children, $origChildren);
        foreach ($childrenDiff as $key=> $child) {
            $origChildren['docentry']['children'][$key] = $child;
        }

        $children = $origChildren;
    }

    /**
     * Override base function to handle task dimension dbfkid difference for docentry..
     *
     * @param array $dimInfo
     *
     */
    function SetDimensionFields(&$dimInfo)
    {
        // for docentry, task dimension has different dbfkid..
        if ( array_key_exists('task', $dimInfo)) {
            $dimInfo['task']['dimfieldid'] = 'taskkey';
            $dimInfo['task']['dimdbkey'] = 'TASKKEY';
            $dimInfo['task']['object_relation'] = [
                'fkey' => 'taskkey', 'invfkey' => 'record#', 'table' => 'task', 'join' => 'outer'
            ];
            $dimInfo['task']['referentialConstraints'] = ['project' => 'PROJECTDIMKEY'];
        }

        parent::SetDimensionFields($dimInfo);
    }

    /**
     * Parent override add a record to the database
     *
     * @param array &$values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $ok = true;
        // Adding these validations to check cycle count lines are valid or not for REST API
        // same set of validations are executed in API_Add method
        if ($this->fromAPI === false) {
            // since iccyclecount is not enabled for upsert when updating lines from REST or UI regularAdd
            // is used to add the lines
            // checking if these flags are provided to verify the request is only from REST
            if (isset($values[$this::IA_OPERATIONS]) && $values[$this::IA_OPERATIONS] === 'patch'
                && isset($values[$this::IA_CORRELATION_KEY])) {
                $ok = $this->regularSet($values);
            }

            if (!(isset($values['RECORDNO']) && $values['RECORDNO'] != '')) {
                $ok = $ok && $this->validateCycleCountState(CREATE, $values);
                $ok = $ok && $this->validateCycleCountEntry(CREATE, $values);
                // updated the prepCCEntryForCreate to return bool
                $ok = $ok && $this->prepCCEntryForCreate($values);
            }
        }
        $ok = $ok && parent::regularAdd($values);
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
    function API_Add(&$values): bool
    {
        $this->fromAPI = true;
        $ok =  $this->validateCycleCountState(CREATE, $values);
        $ok =  $ok && $this->validateCycleCountEntry(CREATE, $values);
        // updated the prepCCEntryForCreate to return bool
        $ok = $ok && $this->prepCCEntryForCreate($values);

        $ok = $ok && parent::API_Add($values);

        return $ok;
    }

    /**
     * Parent override to update a record to the database
     *
     * @param array &$values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $ok  = true;
        // Adding these validations to check cycle count lines are valid or not for REST API
        // same set of validations are executed in API_Set methods
        if (isset($values[$this::IA_OPERATIONS]) && $values[$this::IA_OPERATIONS] === 'patch'
            && isset($values[$this::IA_CORRELATION_KEY]) && $this->fromAPI === false) {
            $ok = $ok && $this->validateCycleCountState(UPDATE, $values);
            $ok = $ok && $this->validateCycleCountEntry(UPDATE, $values);
            if (!$ok) {
                throw new Exception(
                    "Unable to update cycle count entry- Invalid operation"
                );
            }
            $ccState = $this->_ccDataCache[$values['CYCLECOUNTKEY']]['COUNTSTATE'];
            $ok = $ok && $this->validateQtyForSerialItems($values, $ccState);
            if (isset($ccState) && $ccState === ICCycleCountFormEditor::STATE_INPROGRESS_VALUE) {
                $ok = $ok && $this->prepCCEntryForUpdate($values);
            }
        }

        $ok = $ok && parent::regularSet($values);

        return $ok;
    }

    /**
     * parent override so we know we came from the API
     *
     * @param array $values
     *
     * @return bool
     */
    function API_Set(&$values): bool
    {
        $ok = true;
        $this->fromAPI = true;
        $ccState = $this->_ccDataCache[$values['CYCLECOUNTKEY']]['COUNTSTATE'];
        $ok = $ok && $this->validateQtyForSerialItems($values, $ccState);
        if(isset($ccState) && $ccState === ICCycleCountFormEditor::STATE_INPROGRESS_VALUE){
            $ok = $ok && $this->prepCCEntryForUpdate($values);
        }

        $ok = $ok && parent::API_Set($values);

        return $ok;
    }


    /**
     * Delete an object from Web Services API
     *
     * @param string $recordno The unique record number for the object
     *
     * @return bool
     */
    function API_Delete($recordno): bool
    {
        $this->fromAPI = true;
        $values['RECORDNO'] = $recordno;
        $ok =  $this->validateCycleCountState(DELETE, $values);
        $ok =  $ok && $this->validateCycleCountEntry(DELETE, $values);
        $ok =  $ok && parent::API_Delete($recordno);
        return $ok;
    }

    /**
     * API entry point that merges given update values with existing values.
     *  For term objects, the VALUE field is read-only for Set, so make sure the VALUE
     *  is not passed in the inputs.
     *
     * @param array $object Existing object values
     * @param array $values Newly passed in values
     *
     * @return array merged values
     */
    function API_UpdateMerge(&$object, &$values): array
    {
        $this->fromAPI = true;
        // We are validate function here becuase we only support selected fields to update from API.
        // So we need to validate those fields before they merge with the getList data.
        $ok = $this->validateCycleCountState(UPDATE, $values);
        $ok = $ok && $this->validateCycleCountEntry(UPDATE, $values);
        if(!$ok){
            throw new Exception(
                "Unable to update cycle count entry- Invalid operation"
            );
        }
        return parent::API_UpdateMerge($object, $values);
    }

    /**
     * validateCycleCountState
     *
     * @param string $operation
     * @param array $values
     *
     * @return bool
     */
    function validateCycleCountState($operation, $values): bool
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ccState = "";
        $ccRecNo = "";
        $ccEntryRecNo = "";

        if($operation === CREATE){
            if(!isset($values['CYCLECOUNTKEY']) || $values['CYCLECOUNTKEY'] == ''){
                $msg = sprintf("Must supply CYCLECOUNTKEY in order to create iccyclecountentry.");
                $gErr->addIAError('INV-0568', __FILE__ . '.' . __LINE__,
                    "Unable to create cycle count entry- Required fields not provided",
                    [],
                    $msg,
                    []
                );
                return false;
            }

            $ccRecNo = $values['CYCLECOUNTKEY'];
        } else if(isset($values['RECORDNO'])) {
            // In case of Update or Delete RECORDNO is mandatory and the given RECORDNO should exist.
            $ccEntryRecNo = $values['RECORDNO'];
            if ($this->fromAPI) {
                $ccEntryParams = ['selects' => ['CYCLECOUNTKEY', 'LINECOUNTSTATE'],
                    'filters' => [[['RECORDNO', '=', $ccEntryRecNo]]]
                ];
                $ccEntryRecord = $this->GetList($ccEntryParams);
            } else {
                $ccEntryRecord [] = $values;
            }
            if(!empty($ccEntryRecord)){
                $ccRecNo = $ccEntryRecord[0]['CYCLECOUNTKEY'];
                $this->_ccLineCache[$ccEntryRecNo]['CYCLECOUNTKEY'] = $ccRecNo;
                $this->_ccLineCache[$ccEntryRecNo]['LINECOUNTSTATE'] = $ccEntryRecord[0]['LINECOUNTSTATE'];
            } else {
                //In case RECORDNO doesn't exist, we will thrwo error.
                if($operation === UPDATE){
                    $msg = sprintf("Cannot update non-existing ICCYCLECOUNTENTRY with RECORDNO='%1s'.".
                        "Please choose different cycle count entry.", $ccEntryRecNo);
                    $gErr->addIAError('INV-0569', __FILE__ . '.' . __LINE__,
                        "Unable to update cycle count entry.",[], $msg,['CC_ENTRY_REC_NO'=>$ccEntryRecNo]);

                    return false;
                } else if($operation === DELETE){
                    $msg = sprintf("Cannot delete non-existing ICCYCLECOUNTENTRY with RECORDNO='%1s'.".
                        "Please choose different cycle count entry.", $ccEntryRecNo);
                    $gErr->addIAError('INV-0570', __FILE__ . '.' . __LINE__,"Unable to delete cycle count entry.",
                     [],$msg,['CC_ENTRY_REC_NO'=>$ccEntryRecNo]);
                    return false;
                }
            }
        }

        //Get the Cycle count state so that we can validate the operation and restrict the user
        //from making wrong entry. Also we support only the field create/update from UI
        $ccMgr = $gManagerFactory->getManager( 'iccyclecount' );

        $ccParams = [
            'selects' => ['COUNTSTATE', 'WAREHOUSEID', 'EMPUSERID' ],
            'filters' => [[['RECORDNO', '=', $ccRecNo]]]
        ];

        $countData = $ccMgr->GetList($ccParams);
        if(!empty($countData)){
            // Prepare the cycle count Data and cache it.
            $ccState = $countData[0]['COUNTSTATE'];
            $this->_ccDataCache[$ccRecNo]['COUNTSTATE']  = $ccState;
            $this->_ccDataCache[$ccRecNo]['WAREHOUSEID'] = $countData[0]['WAREHOUSEID'];
            $this->_ccDataCache[$ccRecNo]['EMPUSERID']   = $countData[0]['EMPUSERID'];
        }
        if($operation === CREATE){
            // In case of CREATE cycle count transaction,
            // we can only create entry if the cycle count is in Not started or In Progress.
            // Otherwise we throw error
            $validCountStates = [ICCycleCountFormEditor::STATE_NOTSTARTED_VALUE, ICCycleCountFormEditor::STATE_INPROGRESS_VALUE];
            if(!in_array($ccState, $validCountStates)){
                $msg = sprintf("Can't add entry for cycle count in '%1s' State.".
                    "Please choose different cycle count", $ccState);
                $gErr->addIAError('INV-0571', __FILE__ . '.' . __LINE__,
                "Unable to create cycle count entry- Invalid operation",[], $msg,
                ['CC_STATE'=>$ccState]);
                return false;
            }
        } else if($operation === UPDATE){
            // In case of UPDATE cycle count transaction,
            // we can only update entry if the cycle count is in In Progress or Counted.
            // Otherwise we throw error
            $validCountStates = [ ICCycleCountFormEditor::STATE_INPROGRESS_VALUE, ICCycleCountFormEditor::STATE_COUNTED_VALUE ];
            if(!in_array($ccState, $validCountStates)){
                $msg = sprintf("Can't update entry for cycle count in '%1s' State.".
                    "Please choose different cycle count", $ccState);
                $gErr->addIAError('INV-0572', __FILE__ . '.' . __LINE__,
                    "Unable to update cycle count entry- Invalid operation", [],$msg,
                    ['CC_STATE'=>$ccState]);
                return false;
            }

            // In case of cycle count state In Progress,
            //We can only update the fileds like QUANTITYCOUNTED, QUANTITYDAMAGED, ADJUSTMENTREASON and COUNTEDBYID
            if(isset($ccState) && $ccState === ICCycleCountFormEditor::STATE_INPROGRESS_VALUE){
                $excludeFeilds = ['ACTUALADJ', 'ACTUALDMGADJ', 'REVIEWCOMMENT'];
                foreach ($excludeFeilds as $fields){
                    if(isset($values[$fields]) && $values[$fields] !== ''){
                        $msg = sprintf("Can't supply '%1s' for cycle count in '%2s' State.", $fields, $ccState);
                        $gErr->addIAError(
                            'INV-0573', __FILE__ . '.' . __LINE__,
                            "Unable to update cycle count entry- Invalid fields not provided",[],
                            $msg, ['FIELDS' => $fields, 'CC_STATE' => $ccState]
                        );
                        return false;
                    }
                }
            } else {
                // In case of cycle count state Counted,
                //We can only update the fileds like ACTUALADJ, ACTUALDMGADJ and REVIEWCOMMENT
                $excludeFeilds = ['QUANTITYCOUNTED', 'QUANTITYDAMAGED', 'ADJUSTMENTREASON', 'COUNTEDBYID'];
                foreach ($excludeFeilds as $fields){
                    if(isset($values[$fields]) && $values[$fields] !== ''){
                        $msg = sprintf("Can't supply '%1s' for cycle count in '%2s' State.", $fields, $ccState);
                        $gErr->addIAError(
                            'INV-0669', __FILE__ . '.' . __LINE__,
                            "Unable to update cycle count entry- Invalid fields not provided",[],
                            $msg, ['FIELDS' => $fields, 'CC_STATE' => $ccState]
                        );
                        return false;
                    }
                }
            }
        } else {
            // In case of Delete cycle count should not have been Started.
            if(isset($ccState) && $ccState !== ICCycleCountFormEditor::STATE_NOTSTARTED_VALUE ){
                $ccState = $countData[0]['COUNTSTATE'];
                $msg = sprintf("You attempted to delete a '%1s' cycle count entry, where count state is '%2s'.".
                "Please choose different cycle count entry.", $ccEntryRecNo, $ccState);
                $gErr->addIAError('INV-0574', __FILE__ . '.' . __LINE__,
                "Unable to delete cycle count entry.",[], $msg,
                ['CC_ENTRY_REC_NO'=>$ccEntryRecNo,'CC_STATE'=>$ccState]);
                return false;
            }
        }
        return true;
    }

    /**
     * validateCycleCountEntry
     *
     * @param string $operation
     * @param array $values
     *
     * @return bool
     */
    function validateCycleCountEntry($operation, $values): bool
    {
        $gErr = Globals::$g->gErr;
        GetModulePreferences(Globals::$g->kINVid, $invPrefs);

        if($operation === CREATE){
            // ITEMID is required for CREATE cycle count entries.
            if(!isset($values['ITEMID']) || $values['ITEMID'] == ''){
                $msg = sprintf("Must supply ITEMID in order to create iccyclecountentry.");
                $gErr->addIAError('INV-0575', __FILE__ . '.' . __LINE__,
                    "Unable to create cycle count entry- Required fields not provided",
                    [],
                    $msg,
                    []
                );
                return false;
            }

            $ccRecNo = $values['CYCLECOUNTKEY'];
            $warehouseKey = $this->_ccDataCache[$ccRecNo]['WAREHOUSEID'];
            if(isset($values['ITEMID']) && $values['ITEMID'] !== ''){
                $itemID = $values['ITEMID'];
                //Check the condition if alrady exist ,
                if(empty($this->_itemsCache[$itemID])){
                    $this->prepCache([$itemID], $warehouseKey);
                    if (empty($this->_itemsCache[$itemID])) {
                        $msg = sprintf("Item ID '%1s' provided in invalid.".
                        "Please provide valid Item ID and try again", $itemID);
                        $gErr->addIAError('INV-0576', __FILE__ . '.' . __LINE__,
                        "Unable to create cycle count entry- Invalid Item ID provided",[], $msg,
                        ['ITEMID'=>$itemID]);
                        return false;
                    }
                }
                //Get the details of the item and check for tracking details.
                $itemDetails = $this->_itemsCache[$itemID];

                // Validate Bin Info ..
                if(!$this->validateBinInfo($values, $itemDetails, $invPrefs)){
                    return false;
                }

                // Validate Lot Info .
                if(!$this->validateLotInfo($values, $itemDetails, $invPrefs)){
                    return false;
                }

                // Validate Expiration Info .
                if(!$this->validateExpirationInfo($values, $itemDetails, $invPrefs)){
                    return false;
                }

                // Validate Serial Info .
                if(!$this->validateSerialInfo($values, $itemDetails, $invPrefs)){
                    return false;
                }

                // Validate Serial Info .
                if(!$this->validateDuplicateInfo($values)){
                    return false;
                }
            }
        } else if($operation === UPDATE){
            $ccEntryRecNo = $values['RECORDNO'];
            $cycleCountLineState = $this->_ccLineCache[$ccEntryRecNo]['LINECOUNTSTATE'];

            // In case of UPDATE , we restict all the spipped cycle count entries from updating.
            if(isset($cycleCountLineState) && $cycleCountLineState == self::LINE_STATE_SKIPPED){
                $msg = sprintf("Can't update cycle count in Skipped State.");
                $gErr->addIAError('INV-0577', __FILE__ . '.' . __LINE__,
                    "Unable to update cycle count entry.",
                    [],
                    $msg,
                    []
                );
                return false;
            }
        } else {
            // In case of Delete cycle
            $ccEntryRecNo = $values['RECORDNO'];
            $cycleCountLineState = $this->_ccLineCache[$ccEntryRecNo]['LINECOUNTSTATE'];

            if( isset($cycleCountLineState) && $cycleCountLineState !== self::LINE_STATE_NOTCOUNTED ){
                $entryState = $cycleCountLineState;
                $msg = sprintf("You attempted to delete a '%1s' cycle count entry which in state '%2s'.".
                    "Please choose different cycle count entry.", $ccEntryRecNo, $entryState);
                $gErr->addIAError('INV-0578', __FILE__ . '.' . __LINE__,
                 "Unable to delete cycle count entry.",[], $msg,
                 ['CC_ENTRY_REC_NO'=>$ccEntryRecNo,'ENTRY_STATE'=>$entryState]);
                return false;
            }
        }

        return true;
    }

    /**
     * validateQtyForSerialItems
     *
     * @param array $values
     * @param string $ccState
     *
     * @return bool
     */
    protected function validateQtyForSerialItems($values, $ccState): bool
    {
        $ok = true;
        $gErr = Globals::$g->gErr;

        //If it is not serial tracked item, we just return true.
        //No need of validation.
        if(!isset($values['SERIALNO']) || $values['SERIALNO'] == ''){
            return $ok;
        }

        //In case update we need to validate all the Qty provoided for serial tracked item
        if(isset($ccState) && $ccState === ICCycleCountFormEditor::STATE_INPROGRESS_VALUE){
            $qtyCounted = $values['QUANTITYCOUNTED'];
            $qtyDamaged = $values['QUANTITYDAMAGED'];

            if(((int)($qtyCounted - floor($qtyCounted)) !== 0 ) || ((int)($qtyDamaged - floor($qtyDamaged)) !== 0)){
                $msg = sprintf("The item is enabled for serial tracking.".
                "Enter a value of 1 for either quantity counted or quantity damaged.");
                $gErr->addIAError('INV-0579', __FILE__ . ':' . __LINE__,
                    "Unable to create cycle count entry- Invalid quanity provided",
                    [],
                    $msg,
                    []
                );
                $ok = false;
            }

            if($ok){
                $totalQuantity = $qtyCounted + $qtyDamaged;
                if($totalQuantity > 1){
                    $msg = sprintf("The item is enabled for serial tracking.".
                    "Enter a value of 1 for either quantity counted or quantity damaged.");
                    $gErr->addIAError('INV-0670', __FILE__ . ':' . __LINE__,
                        "Unable to create cycle count entry- Invalid quanity provided",
                        [],
                        $msg,
                        []
                    );
                    $ok = false;
                }
            }
        } else {
            //Reconcile case we check the ACTUALADJ and ACTUALDMGADJ values.
            // For serial tracked item, we validate the Qty.
            $qtyActualAdj = ibcabs((float)$values['ACTUALADJ']);
            $qtyDamagedAdj = ibcabs((float)$values['ACTUALDMGADJ']);

            if(((int)($qtyActualAdj - floor($qtyActualAdj)) !== 0 ) || ((int)($qtyDamagedAdj - floor($qtyDamagedAdj)) !== 0)
                || $qtyActualAdj > 1 || $qtyDamagedAdj > 1){
                $msg = sprintf("The item is enabled for serial tracking.".
                    "Enter a value of 1 for either quantity counted or quantity damaged.");
                $gErr->addIAError('INV-0671', __FILE__ . ':' . __LINE__,
                    "Unable to create cycle count entry- Invalid quanity provided",
                    [],
                    $msg,
                    []
                );
                $ok = false;
            }

            if($ok){
                $totalQuantityAdj = $qtyActualAdj + $qtyDamagedAdj;
                if($totalQuantityAdj > 1){
                    $msg = sprintf("The item is enabled for serial tracking.".
                        "Enter a value of 1 for either quantity counted or quantity damaged.");
                    $gErr->addIAError('INV-0672', __FILE__ . ':' . __LINE__,
                        "Unable to create cycle count entry- Invalid quanity provided",
                        [],
                        $msg,
                        []
                    );
                    $ok = false;
                }
            }
        }
        return $ok;
    }

    /**
     * validateBinInfo, validate the Bin information provoided for the item
     *
     * @param array $values
     * @param array $itemDetails
     * @param array $invPrefs
     *
     * @return bool
     */
    protected function validateBinInfo($values, $itemDetails, $invPrefs): bool
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $itemID = $values['ITEMID'];

        if($itemDetails['ENABLEBIN'] =='T' && $invPrefs['ENABLEBIN'] == 'T'){
            if(!isset($values['BINID']) || $values['BINID'] == ''){
                $msg = sprintf("Bin tracking information is required for item '%1s'.".
                "Please provide the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0580', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                 ['ITEMID'=>$itemID]);
                return false;
            }

            $binId = $values['BINID'];
            $binMgr = $gManagerFactory->getManager('bin');
            $filter = [
                'selects' => ['RECORDNO'],
                'filters' => [[['BINID', '=', $binId]]]
            ];
            $binResults = $binMgr->GetList($filter);
            if(empty($binResults)){
                $msg = sprintf("Bin information provided '%1s' doesn't exist'.".
                "Please provide the valid Bin and try again", $binId);
                $gErr->addIAError('INV-0581', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['BIN_ID'=>$binId]);
                return false;
            }
        } else {
            if(isset($values['BINID']) && $values['BINID'] !== ''){
                $msg = sprintf("Bin tracking information not required for item '%1s'.".
                "Please remove the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0582', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        }
        return true;
    }

    /**
     * validateLotInfo, validate the Lot information provoided for the item
     *
     * @param array $values
     * @param array $itemDetails
     * @param array $invPrefs
     *
     * @return bool
     */
    protected function validateLotInfo($values, $itemDetails, $invPrefs): bool
    {
        $gErr = Globals::$g->gErr;

        $itemID = $values['ITEMID'];

        if($itemDetails['ENABLELOT'] =='T' && $invPrefs['ENABLELOT'] == 'T'){
            if(!isset($values['LOTNO']) || $values['LOTNO'] == ''){
                $msg = sprintf("Lot tracking information is required for item '%1s'.".
                    "Please provide the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0583', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        } else {
            if(isset($values['LOTNO']) && $values['LOTNO'] !== ''){
                $msg = sprintf("Lot tracking information not required for item '%1s'.".
                "Please remove the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0584', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        }
        return true;
    }

    /**
     * validateExpirationInfo, validate the Expiration information provoided for the item
     *
     * @param array $values
     * @param array $itemDetails
     * @param array $invPrefs
     *
     * @return bool
     */
    protected function validateExpirationInfo($values, $itemDetails, $invPrefs): bool
    {
        $gErr = Globals::$g->gErr;

        $itemID = $values['ITEMID'];

        if($itemDetails['ENABLEEXPIRATION'] =='T' && $invPrefs['ENABLE_EXPIRATION'] == 'T'){
            if(!isset($values['EXPIRATIONDATE']) || $values['EXPIRATIONDATE'] == ''){
                $msg = sprintf("Expiration tracking information is required for item '%1s'.".
                "Please provide the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0585', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        } else {
            if(isset($values['EXPIRATIONDATE']) && $values['EXPIRATIONDATE'] !== ''){
                $msg = sprintf("Expiration tracking information not required for item '%1s'.".
                "Please remove the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0586', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        }
        return true;
    }

    /**
     * validateSerialInfo, validate the Serial information provoided for the item
     *
     * @param array $values
     * @param array $itemDetails
     * @param array $invPrefs
     *
     * @return bool
     */
    protected function validateSerialInfo($values, $itemDetails, $invPrefs): bool
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ccRecNo = $values['CYCLECOUNTKEY'];
        $itemID = $values['ITEMID'];


        if($itemDetails['ENABLESNO'] =='T' && $invPrefs['ENABLESERIAL'] == 'T'){
            if(!isset($values['SERIALNO']) || $values['SERIALNO'] == ''){
                $msg = sprintf("Serial tracking information is required for item '%1s'.".
                "Please provide the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0587', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }

            $serialNo = $values['SERIALNO'];
            if(isset($itemDetails['SERIALMASKKEY']) && $itemDetails['SERIALMASKKEY'] != ''){
                $serialMaskMgr = $gManagerFactory->getManager('serialmask');
                $serialMaskFilter = [
                    'selects' => ['MASK'],
                    'filters' => [[['RECORDNO', '=', $itemDetails['SERIALMASKKEY']]]],
                ];
                $serialMasks = $serialMaskMgr->GetList($serialMaskFilter);
                if(isset($serialMasks[0]['MASK']) && $serialMasks[0]['MASK'] != ''){
                    $trackingHandlers = new TrackingHandler(['ACTION' => EDIT_ACTION]);
                    $maskPattern = $trackingHandlers->PrepSerialMaskRegExPattern($serialMasks[0]['MASK']);
                    if(isset($maskPattern) && $maskPattern!='') {
                        if (!preg_match($maskPattern, $serialNo) || strlen($serialMasks[0]['MASK'])!=strlen($serialNo)) {
                            $msg = sprintf("Serial number '%1s' is not as per masking '%2s'.".
                            "Please provide valid Serial number and try again", $serialNo, $maskPattern);
                            $gErr->addIAError('INV-0588', __FILE__ . ':' . __LINE__,
                            "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                            ['SERIAL_NO'=>$serialNo,'MASK_PATTERN'=>$maskPattern]);
                            return false;
                        }
                    }
                }
            }

            // We are validating the Serial Number in the current cycle count transaction.
            // If exist we throw error.
            // If The same Item ID and Serial Number exist in any other cycle count transaction we skip them.
            // This is handled in  prepCCEntryForCreate
            $ccyclecountparams = [
                'selects' => ['RECORDNO'],
                'filters' => [
                     [
                         ['CYCLECOUNTKEY', '=', $ccRecNo],
                         ['ITEMID', '=', $itemID],
                         ['SERIALNO', '=', $serialNo]
                    ],
                ]
            ];

            $existEntryRecords = $this->GetList($ccyclecountparams);

            if (count($existEntryRecords) > 0){
                $msg = sprintf("Unable to add selected item '%1s' - Duplicate Serial Number.".
                "Please select different Serial Item and try again", $itemID);
                $gErr->addIAError('INV-0589', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Same Item Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        } else {
            // if the Item is not enable for Serial Tracking , Serial Number is not required.
            if(isset($values['SERIALNO']) && $values['SERIALNO'] !== ''){
                $msg = sprintf("Serial tracking information not required for item '%1s'.".
                "Please remove the tracking details and try again", $itemID);
                $gErr->addIAError('INV-0590', __FILE__ . ':' . __LINE__,
                "Unable to create cycle count entry- Invalid Tracking Information provided",[], $msg,
                ['ITEMID'=>$itemID]);
                return false;
            }
        }
        return true;
    }


    /**
     * validateDuplicateInfo , check for duplication of item provoided in the cycle count.
     *
     * @param array $values
     *
     * @return bool
     */
    protected function validateDuplicateInfo($values): bool
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $ccRecNo = $values['CYCLECOUNTKEY'];
        $itemID = $values['ITEMID'];
        $itemKey        = $this->_itemsCache[$itemID]['RECORDNO'];
        $binId          = $values['BINID'];
        $binkey         = '';
        $serialNo       = $values['SERIALNO'];
        $lotNo          = $values['LOTNO'];
        $expirationdDate  = $values['EXPIRATIONDATE'];

        // Additional binkey detail need to fetch.
        if(isset($binId) && $binId != ''){
            $binMgr = $gManagerFactory->getManager('bin');
            $filter = [
                'selects' => ['RECORDNO'],
                'filters' => [[['BINID', '=', $binId]]]
            ];
            $binResults = $binMgr->GetList($filter);
            if(is_array($binResults) && count($binResults) > 0){
                $binkey = $binResults[0]['RECORDNO'];
            }
        }

        //Prepare uniquekey for skipping validation.
        $uniquePropnNRow = $itemKey .
            '#' . $binkey.
            '#' . $serialNo .
            '#' . $lotNo.$expirationdDate;

        //Check for the entry which  already present in this current cycle count
        $ccyclecountparams = [
            'selects' => ['RECORDNO'],
            'filters' => [
                [
                    ['CYCLECOUNTKEY', '=', $ccRecNo],
                    ['UNIQUEPROPONROW', '=', $uniquePropnNRow]
                ],
            ]
        ];
        $existEntryRecords = $this->GetList($ccyclecountparams);

        if (count($existEntryRecords) > 0){
            $msg = sprintf("Item '%1s' selected to count is currently present in the cycle count.".
            "Please select different Item and try again", $itemID);
            $gErr->addIAError('INV-0591', __FILE__ . ':' . __LINE__,
            "Unable to create cycle count entry- Same Item Information provided",[], $msg,
            ['ITEMID'=>$itemID]);
            return false;
        }

        return true;
    }

    /**
     * prepCCEntryForCreate
     *
     * @param $values
     * @return bool return false in case of failure.
     */
    protected function prepCCEntryForCreate(&$values)
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $ccEntry = [];

        $itemID         = $values['ITEMID'];
        $binId          = $values['BINID'];
        $serialNo       = $values['SERIALNO'];
        $lotNo          = $values['LOTNO'];
        $expirationdDate   = $values['EXPIRATIONDATE'];

        $ccMgr = $gManagerFactory->getManager( 'iccyclecount' );
        $warehouseKey = $this->_ccDataCache[$values['CYCLECOUNTKEY']]['WAREHOUSEID'];
        $countedbyId  = $this->_ccDataCache[$values['CYCLECOUNTKEY']]['EMPUSERID'];
        $ccState = $this->_ccDataCache[$values['CYCLECOUNTKEY']]['COUNTSTATE'];

        $ccEntry['CYCLECOUNTKEY'] = $values['CYCLECOUNTKEY'];

        //Additional item details need to fetch.
        if(isset($itemID) && $itemID != ''){
            $ccEntry['QUANTITYONHAND'] = 0;
            $ccEntry['ITEMID'] = $this->_itemsCache[$itemID]['ITEMID'];
            $ccEntry['ITEMKEY'] = $this->_itemsCache[$itemID]['RECORDNO'];
            $ccEntry['PRODUCTLINE'] = $this->_itemsCache[$itemID]['PRODUCTLINEKEY'];
            $ccEntry['ITEMUNIT'] = $this->_itemsCache[$itemID]['ITEMUNIT'];
            $ccEntry['ITEMCYCLE'] = $this->_itemsCache[$itemID]['ITEMCYCLE'];

            //Additional bin details need to fetch.
            if(isset($binId) && $binId != ''){
                $binMgr = $gManagerFactory->getManager('bin');
                $filter = [
                    'selects' => ['RECORDNO', 'BINID', 'AISLEKEY', 'AISLEID', 'ROWKEY', 'ROWID', 'ZONEKEY', 'ZONEID'],
                    'filters' => [[['BINID', '=', $binId]]]
                ];
                $binResults = $binMgr->GetList($filter);
                if(is_array($binResults) && count($binResults) > 0){
                    $ccEntry['BINKEY'] = $binResults[0]['RECORDNO'];
                    $ccEntry['BINID'] = $binResults[0]['BINID'];
                    $ccEntry['AISLEKEY'] = $binResults[0]['AISLEKEY'];
                    $ccEntry['AISLEID'] = $binResults[0]['AISLEID'];
                    $ccEntry['ROWKEY'] = $binResults[0]['ROWKEY'];
                    $ccEntry['ICROWID'] = $binResults[0]['ROWID'];
                    $ccEntry['ZONEKEY'] = $binResults[0]['ZONEKEY'];
                    $ccEntry['ZONEID'] = $binResults[0]['ZONEID'];
                }
            }

            if(isset($lotNo) && $lotNo != ''){
                $ccEntry['LOTNO'] = $lotNo;
            }

            if(isset($expirationdDate) && $expirationdDate != ''){
                $ccEntry['EXPIRATIONDATE'] = $expirationdDate;
            }

            if(isset($serialNo) && $serialNo != ''){
                $ccEntry['SERIALNO'] = $serialNo;
            }

            //Prepare uniquekey for skipping validation.
            $ccEntry['UNIQUEPROPONROW'] = $ccEntry['ITEMKEY'] .
                '#' . $ccEntry['BINKEY'].
                '#' . $serialNo .
                '#' . $lotNo.$expirationdDate;

            //Get the physical Inventory data Qty Onhand if this item exist in it. So be concistant in both Add items
            // and Select Items.

            // prepare $requestParams data and send it for QUANTITYONHAND calculation
            $requestParams['CYCLECOUNTKEY'] = $ccEntry['CYCLECOUNTKEY'];
            $requestParams['UNIQUEKEYS'][] = $ccEntry['UNIQUEPROPONROW'];
            $cycleCountData = $ccMgr->executeCycleCountQuery($warehouseKey, false, true, $requestParams);
            if( is_array($cycleCountData) && count($cycleCountData) > 0 && isset($cycleCountData[0]['QUANTITYONHAND'])){
                $ccEntry['QUANTITYONHAND'] = $cycleCountData[0]['QUANTITYONHAND'];
            } else if (!is_array($cycleCountData) && $cycleCountData === false) {
                // return false in case of query error
                return false;
            }

            // Assign prepared $ccEntry to the $values
            $values  = [$ccEntry];

            // In case of CREATE cycle count entry and the cycle count state is In Progress,
            //We need to check if already the item provoided is present in other cycle count.
            // If present then we should mark it skipped
            if(isset($ccState) && $ccState == ICCycleCountFormEditor::STATE_INPROGRESS_VALUE){
                $ccMgr->getSkipCycleCountList($values, $warehouseKey);
            }

            $countedbyKey = $this->prepCountedByKey($countedbyId);
            if( is_array($values) && count($values) > 0){
                //populate default data so that it can be used for filtering
                foreach ($values as $key => $selectedRow){
                    if($values[$key]['LINECOUNTSTATE'] !== self::LINE_STATE_SKIPPED){
                        $values[$key]['COUNTEDBYID'] = $countedbyId;
                        $values[$key]['COUNTEDBYKEY'] = $countedbyKey;
                        $values[$key]['LINECOUNTSTATE']  = self::LINE_STATE_NOTCOUNTED;
                    }
                }
            }
        }
        // return true in case everything went happy path
        return true;
    }

    /**
     * prepCCEntryForUpdate
     *
     * @param array $values
     *
     * @return bool
     */
    protected function prepCCEntryForUpdate(&$values): bool
    {
        $countedbyId = $values['COUNTEDBYID'];
        if(isset($countedbyId) && $countedbyId != ''){
            $countedbyKey = $this->prepCountedByKey($countedbyId);
            $values['COUNTEDBYKEY'] = $countedbyKey;
        }

        $qtyCounted = $values['QUANTITYCOUNTED'];
        $qtyDamaged = $values['QUANTITYDAMAGED'];
        if((isset($qtyCounted) && $qtyCounted != '') ||(isset($qtyDamaged) && $qtyDamaged != '')){
            $values['LINECOUNTSTATE'] = self::LINE_STATE_COUNTED;
        }

        return true;
    }

    /**
     * prepCountedByKey
     *
     * @param string $countedbyId
     *
     * @return int
     */
    protected function prepCountedByKey($countedbyId): int
    {
        //Prepare countedby for the cycle count entry
        $employeeMgr  = Globals::$g->gManagerFactory->getManager('employee');
        $filter = [
            'selects' => ['RECORDNO'],
            'filters' => [[['EMPLOYEEID', '=', $countedbyId]]]
        ];
        $res = $employeeMgr->GetList($filter);

        return  $res[0]['RECORDNO'];
    }

    /**
     * prepCache
     *
     * @param array $itemIDs
     * @param string $warehouseKey
     *
     */
    protected function prepCache($itemIDs, $warehouseKey)
    {
        $this->prepItemsCache($itemIDs);
        $this->prepItemsUOMCache($itemIDs);
        $this->prepItemsCycleCache($itemIDs, $warehouseKey);

        if(!empty($this->_itemsCache)){
            // Fetch the UOM and CYCLE details for each items and prepare them separately
            foreach($itemIDs as $itemID){
                $this->_itemsCache[$itemID]['ITEMCYCLE'] = $this->_itemsCycleCache[$itemID]['CYCLE'];
                foreach ($this->_itemsUOMCache[$itemID] as $itemUOM){
                    if(isset($itemUOM['ISBASE']) && $itemUOM['ISBASE'] == 'T'){
                        $this->_itemsCache[$itemID]['ITEMUNIT'] = $itemUOM['UNIT'];
                        break;
                    }
                }
            }
        }
    }

    /**
     * prepItemsCache
     *
     * @param array $itemIDs
     */
    private function prepItemsCache($itemIDs)
    {
        if (count($itemIDs) > 0) {
            $itemRecs = $this->getItemsCache($itemIDs);
            foreach ($itemRecs as $itemRec) {
                $itemID = $itemRec['ITEMID'];
                $this->_itemsCache[$itemID] = $itemRec;
            }
        }
    }

    /**
     * getItemsCache
     *
     * @param array $itemIDs
     *
     * @return array
     */
    private function getItemsCache($itemIDs): array
    {
        $itemRecs = [];
        if (count($itemIDs) > 0) {
            $itemMgr = Globals::$g->gManagerFactory->getManager('item');
            $queryparams = [
                'selects' => ['ITEMID', 'RECORDNO', 'ITEMTYPE','ENABLEBIN', 'ENABLESNO', 'ENABLELOT', 'SERIALMASKKEY', 'ENABLEEXPIRATION', 'PRODUCTLINEKEY'],
                'filters' => [
                    [
                        ['CNY#', '=', GetMyCompany()],
                        ['ITEMID', 'IN', $itemIDs],
                    ]
                ]
            ];

            $itemRecs = $itemMgr->GetList($queryparams);
        }

        return $itemRecs;
    }

    /**
     * prepItemsUOMCache
     *
     * @param array $itemIDs
     */
    private function prepItemsUOMCache($itemIDs)
    {
        if (count($itemIDs) > 0) {
            $itemMgr = Globals::$g->gManagerFactory->getManager('item');

            $this->_itemsUOMCache = $itemMgr->GetUOMInfoCache($itemIDs, true);
        }
    }

    /**
     * prepItemsCycleCache
     *
     * @param array $itemIDs
     * @param string $warehouseKey
     */
    private function prepItemsCycleCache($itemIDs, $warehouseKey)
    {
        if (count($itemIDs) > 0) {
            $itemCycleRecs = $this->getItemsCycleCache($itemIDs, $warehouseKey);
            foreach ($itemCycleRecs as $cycleRec) {
                $itemID = $cycleRec['ITEMID'];
                $this->_itemsCycleCache[$itemID] = $cycleRec;
            }
        }
    }

    /**
     * getItemsCycleCache
     *
     * @param array $itemIDs
     * @param string $warehouseKey
     *
     * @return array
     */
    private function getItemsCycleCache($itemIDs, $warehouseKey): array
    {
        $itemCycleRes = [];
        if (count($itemIDs) > 0) {
            $itemWhseMgr = Globals::$g->gManagerFactory->getManager('itemwarehouseinfo');

            $params = [
                'selects' => ['ITEMID', 'CYCLE'],
                'filters' => [
                    [
                        ['ITEMID', 'IN', $itemIDs],
                        ['WAREHOUSEID', '=', $warehouseKey],
                    ]
                ],
            ];

            $itemCycleRes = $itemWhseMgr->GetList($params);
        }

        return $itemCycleRes;
    }
}

